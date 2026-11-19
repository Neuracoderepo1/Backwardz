-- BACKWARDZ: serialize trial acceptance and make run finalization + leaderboard
-- publication one PostgreSQL transaction. Additive functions only; no table
-- data, RLS policies, or existing constraints are modified.

CREATE OR REPLACE FUNCTION public.backward_submit_trial(
  p_run_id uuid, p_player_id uuid, p_round_index smallint, p_level smallint,
  p_grid_cols smallint, p_grid_rows smallint, p_speed_variance numeric,
  p_round_seed bigint, p_response_cell_index integer, p_rt_ms integer,
  p_expected_cell_index integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_run public.backward_game_runs%ROWTYPE;
  v_existing public.backward_game_trials%ROWTYPE;
  v_inserted public.backward_game_trials%ROWTYPE;
  v_prior_count integer;
  v_prior_correct integer;
  v_prior_losses integer;
  v_expected_level integer;
  v_expected_seed bigint;
  v_expected_variance numeric;
  v_max_ms integer;
  v_recorded_rt integer;
  v_outcome text;
BEGIN
  IF p_run_id IS NULL OR p_player_id IS NULL OR p_round_index IS NULL OR p_round_index < 1
     OR p_level IS NULL OR p_grid_cols IS NULL OR p_grid_rows IS NULL
     OR p_speed_variance IS NULL OR p_round_seed IS NULL OR p_rt_ms IS NULL
     OR p_expected_cell_index IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'Invalid trial payload');
  END IF;

  SELECT * INTO v_run FROM public.backward_game_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND OR v_run.player_id <> p_player_id THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'Run not found');
  END IF;
  IF v_run.status <> 'in_progress' THEN
    RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'Run inactive');
  END IF;

  SELECT count(*)::integer,
         count(*) FILTER (WHERE outcome = 'correct')::integer,
         count(*) FILTER (WHERE outcome <> 'correct')::integer
  INTO v_prior_count, v_prior_correct, v_prior_losses
  FROM public.backward_game_trials
  WHERE run_id = p_run_id AND round_index < p_round_index;

  v_expected_level := 1 + v_prior_correct;
  v_expected_variance := least(0.9::numeric, 0.1::numeric + v_expected_level * 0.08::numeric);
  v_expected_seed := mod(v_run.challenge_seed::numeric * 100 + (p_round_index - 1), 4294967296)::bigint;
  v_max_ms := round(greatest(5::numeric, 14::numeric - v_expected_level * 0.7::numeric) * 1000)::integer;

  IF p_round_seed <> v_expected_seed OR p_expected_cell_index < 0
     OR p_expected_cell_index >= p_grid_cols::integer * p_grid_rows::integer THEN
    RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'Puzzle binding rejected');
  END IF;
  IF p_grid_cols <> least(3 + v_expected_level, 12) OR p_grid_rows <> 8
     OR p_level <> v_expected_level
     OR abs(p_speed_variance - v_expected_variance) > 0.00001 THEN
    RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'Puzzle parameters rejected');
  END IF;

  IF p_response_cell_index IS NULL THEN
    IF p_rt_ms < 0 OR p_rt_ms > 120000 THEN
      RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'Invalid timeout duration');
    END IF;
    v_outcome := 'timeout';
    v_recorded_rt := v_max_ms;
  ELSE
    IF p_response_cell_index < 0
       OR p_response_cell_index >= p_grid_cols::integer * p_grid_rows::integer
       OR p_rt_ms < 0 OR p_rt_ms > v_max_ms + 300 THEN
      RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'Invalid response');
    END IF;
    v_recorded_rt := least(p_rt_ms, v_max_ms);
    v_outcome := CASE WHEN p_response_cell_index = p_expected_cell_index THEN 'correct' ELSE 'incorrect' END;
  END IF;

  SELECT * INTO v_existing FROM public.backward_game_trials
  WHERE run_id = p_run_id AND round_index = p_round_index;
  IF FOUND THEN
    IF v_existing.player_id = p_player_id AND v_existing.level = p_level
       AND v_existing.grid_cols = p_grid_cols AND v_existing.grid_rows = p_grid_rows
       AND v_existing.speed_variance = p_speed_variance AND v_existing.round_seed = p_round_seed
       AND v_existing.response_cell_index IS NOT DISTINCT FROM p_response_cell_index
       AND v_existing.outcome = v_outcome AND v_existing.rt_ms = v_recorded_rt
       AND v_existing.verification_status = 'verified' THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true,
        'trial', to_jsonb(v_existing), 'verified_correct', v_existing.outcome = 'correct');
    END IF;
    RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'Conflicting duplicate trial submission');
  END IF;

  IF p_round_index <> v_prior_count + 1 THEN
    RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'Trials must be sequential');
  END IF;
  IF v_run.mode = 'daily' AND p_round_index > 8 THEN
    RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'Daily challenge is complete');
  END IF;
  IF v_run.mode = 'endless' AND v_prior_losses >= 3 THEN
    RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'No lives remaining');
  END IF;

  INSERT INTO public.backward_game_trials (
    run_id, player_id, round_index, level, grid_cols, grid_rows, speed_variance,
    round_seed, response_cell_index, outcome, rt_ms, claimed_correct, verification_status
  ) VALUES (
    p_run_id, p_player_id, p_round_index, p_level, p_grid_cols, p_grid_rows,
    v_expected_variance, p_round_seed, p_response_cell_index, v_outcome,
    v_recorded_rt, v_outcome = 'correct', 'verified'
  ) RETURNING * INTO v_inserted;

  RETURN jsonb_build_object('ok', true, 'idempotent', false,
    'trial', to_jsonb(v_inserted), 'verified_correct', v_outcome = 'correct');
END;
$function$;

CREATE OR REPLACE FUNCTION public.backward_finalize_run(
  p_run_id uuid, p_player_id uuid, p_claimed_score integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_run public.backward_game_runs%ROWTYPE;
  v_trial record;
  v_count integer := 0;
  v_level integer := 1;
  v_combo integer := 0;
  v_lives integer := 3;
  v_score integer := 0;
  v_max_ms integer;
  v_left numeric;
  v_name text;
  v_entry public.backward_daily_leaderboard%ROWTYPE;
  v_already_completed boolean := false;
BEGIN
  IF p_run_id IS NULL OR p_player_id IS NULL OR p_claimed_score IS NULL OR p_claimed_score < 0 THEN
    RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'Invalid finish payload');
  END IF;
  SELECT * INTO v_run FROM public.backward_game_runs WHERE id = p_run_id FOR UPDATE;
  IF NOT FOUND OR v_run.player_id <> p_player_id THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'Run not found');
  END IF;
  IF v_run.status = 'abandoned' THEN
    RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'Run inactive');
  END IF;

  IF v_run.status = 'completed' THEN
    v_already_completed := true;
    IF v_run.verified_score IS NULL OR v_run.verification_status <> 'verified' THEN
      RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'Completed run lacks verified score');
    END IF;
    v_score := v_run.verified_score;
    v_count := v_run.rounds_completed;
  ELSE
    FOR v_trial IN
      SELECT round_index, level, outcome, rt_ms, verification_status
      FROM public.backward_game_trials WHERE run_id = p_run_id ORDER BY round_index
    LOOP
      v_count := v_count + 1;
      IF v_trial.round_index <> v_count OR v_trial.level <> v_level
         OR v_trial.verification_status <> 'verified' THEN
        RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'Run history failed verification');
      END IF;
      IF v_trial.outcome = 'correct' THEN
        v_max_ms := round(greatest(5::numeric, 14::numeric - v_level * 0.7::numeric) * 1000)::integer;
        v_left := greatest(0, v_max_ms - coalesce(v_trial.rt_ms, 0)) / 1000.0;
        v_combo := v_combo + 1;
        v_score := v_score + round((10 + v_left * 10) * (1 + v_combo * 0.1))::integer;
        v_level := v_level + 1;
      ELSE
        v_combo := 0;
        IF v_run.mode = 'endless' THEN v_lives := v_lives - 1; END IF;
      END IF;
    END LOOP;

    IF (v_run.mode = 'daily' AND v_count <> 8) OR (v_run.mode = 'endless' AND v_lives > 0) THEN
      RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'Run is not complete', 'rounds_recorded', v_count);
    END IF;
    UPDATE public.backward_game_runs
    SET status = 'completed', claimed_score = p_claimed_score, verified_score = v_score,
        verification_status = 'verified', rounds_completed = v_count, completed_at = now()
    WHERE id = p_run_id AND player_id = p_player_id;
  END IF;

  IF v_run.mode = 'daily' AND v_run.challenge_date IS NOT NULL THEN
    SELECT coalesce(nullif(btrim(display_name), ''), 'Player') INTO v_name
    FROM public.backward_players WHERE user_id = p_player_id;
    v_name := coalesce(v_name, 'Player');

    INSERT INTO public.backward_daily_leaderboard (
      challenge_date, player_id, run_id, display_name, score, rounds_completed
    ) VALUES (v_run.challenge_date, p_player_id, p_run_id, left(v_name, 24), v_score, v_count)
    ON CONFLICT (challenge_date, player_id) DO UPDATE
      SET run_id = EXCLUDED.run_id, display_name = EXCLUDED.display_name,
          score = EXCLUDED.score, rounds_completed = EXCLUDED.rounds_completed, achieved_at = now()
      WHERE EXCLUDED.score > public.backward_daily_leaderboard.score;

    SELECT * INTO v_entry FROM public.backward_daily_leaderboard
    WHERE challenge_date = v_run.challenge_date AND player_id = p_player_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Leaderboard entry could not be resolved after upsert'; END IF;

    INSERT INTO public.backward_daily_leaderboard_public (
      id, challenge_date, display_name, score, rounds_completed, achieved_at
    ) VALUES (v_entry.id, v_entry.challenge_date, v_entry.display_name,
              v_entry.score, v_entry.rounds_completed, v_entry.achieved_at)
    ON CONFLICT (id) DO UPDATE
      SET challenge_date = EXCLUDED.challenge_date, display_name = EXCLUDED.display_name,
          score = EXCLUDED.score, rounds_completed = EXCLUDED.rounds_completed,
          achieved_at = EXCLUDED.achieved_at;
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'already_completed', v_already_completed, 'verified', true,
    'claimed_score', CASE WHEN v_already_completed THEN v_run.claimed_score ELSE p_claimed_score END,
    'verified_score', v_score,
    'score_matches', (CASE WHEN v_already_completed THEN v_run.claimed_score ELSE p_claimed_score END) = v_score,
    'rounds_completed', v_count, 'leaderboard_published', (v_run.mode = 'daily')
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.backward_submit_trial(uuid, uuid, smallint, smallint, smallint, smallint, numeric, bigint, integer, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.backward_submit_trial(uuid, uuid, smallint, smallint, smallint, smallint, numeric, bigint, integer, integer, integer) TO service_role;
REVOKE ALL ON FUNCTION public.backward_finalize_run(uuid, uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.backward_finalize_run(uuid, uuid, integer) TO service_role;
