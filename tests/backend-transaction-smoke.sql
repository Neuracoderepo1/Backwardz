-- Rollback-only integration test for BACKWARDZ transactional RPCs.
-- Run in Supabase SQL Editor. Requires one existing backward_players row.
-- All inserted runs/trials/leaderboard rows and the temporary constraint are rolled back.

BEGIN;

DO $trial_and_retry$
DECLARE
  v_player uuid;
  v_run uuid;
  v_result jsonb;
  i integer;
  v_seed bigint;
  v_variance numeric;
BEGIN
  SELECT user_id INTO v_player FROM public.backward_players ORDER BY created_at LIMIT 1;
  IF v_player IS NULL THEN RAISE EXCEPTION 'No existing player fixture'; END IF;

  INSERT INTO public.backward_game_runs
    (player_id, mode, challenge_date, challenge_seed, device_class, client_version)
  VALUES (v_player, 'daily', DATE '2099-01-01', 20261119, 'unknown', 'rollback-test')
  RETURNING id INTO v_run;

  v_result := public.backward_submit_trial(v_run, gen_random_uuid(), 1::smallint, 1::smallint, 4::smallint, 8::smallint, 0.18::numeric, 2026111900::bigint, 0, 1000, 0);
  IF (v_result->>'ok')::boolean OR (v_result->>'status')::integer <> 404 THEN
    RAISE EXCEPTION 'Cross-player trial access was not rejected: %', v_result;
  END IF;

  v_result := public.backward_submit_trial(v_run, v_player, 2::smallint, 1::smallint, 4::smallint, 8::smallint, 0.18::numeric, 2026111901::bigint, 0, 1000, 0);
  IF (v_result->>'ok')::boolean OR (v_result->>'status')::integer <> 409 THEN
    RAISE EXCEPTION 'Out-of-order submission was not rejected: %', v_result;
  END IF;

  FOR i IN 1..8 LOOP
    v_seed := mod(20261119::numeric * 100 + (i - 1), 4294967296)::bigint;
    v_variance := least(0.9::double precision, 0.1::double precision + i * 0.08::double precision)::numeric;
    v_result := public.backward_submit_trial(v_run, v_player, i::smallint, i::smallint, least(3+i,12)::smallint, 8::smallint, v_variance, v_seed, 0, 1000, 0);
    IF NOT (v_result->>'ok')::boolean THEN RAISE EXCEPTION 'Trial % failed: %', i, v_result; END IF;
    v_result := public.backward_submit_trial(v_run, v_player, i::smallint, i::smallint, least(3+i,12)::smallint, 8::smallint, v_variance, v_seed, 0, 1000, 0);
    IF NOT (v_result->>'ok')::boolean OR NOT (v_result->>'idempotent')::boolean THEN
      RAISE EXCEPTION 'Exact duplicate trial % was not idempotent: %', i, v_result;
    END IF;
  END LOOP;

  v_result := public.backward_submit_trial(v_run, v_player, 8::smallint, 8::smallint, 11::smallint, 8::smallint, 0.74::numeric, 2026111907::bigint, 1, 1000, 0);
  IF (v_result->>'ok')::boolean OR (v_result->>'status')::integer <> 409 THEN
    RAISE EXCEPTION 'Conflicting duplicate was not rejected: %', v_result;
  END IF;

  v_result := public.backward_finalize_run(v_run, v_player, 0);
  IF NOT (v_result->>'ok')::boolean OR NOT (v_result->>'verified')::boolean
     OR (v_result->>'rounds_completed')::integer <> 8
     OR (v_result->>'verified_score')::integer <= 0
     OR NOT (v_result->>'leaderboard_published')::boolean THEN
    RAISE EXCEPTION 'Finalization failed: %', v_result;
  END IF;
  DELETE FROM public.backward_daily_leaderboard_public
  WHERE id IN (SELECT id FROM public.backward_daily_leaderboard WHERE run_id = v_run);
  v_result := public.backward_finalize_run(v_run, v_player, 0);
  IF NOT (v_result->>'ok')::boolean OR NOT (v_result->>'already_completed')::boolean THEN
    RAISE EXCEPTION 'Completed-run retry failed: %', v_result;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.backward_daily_leaderboard_public p
                 JOIN public.backward_daily_leaderboard l ON l.id = p.id
                 WHERE l.run_id = v_run) THEN
    RAISE EXCEPTION 'Completed-run retry did not repair the public projection';
  END IF;
END;
$trial_and_retry$;

-- Force public-projection failure for a second, isolated daily run. The
-- failed function call must roll back the run completion and private entry.
ALTER TABLE public.backward_daily_leaderboard_public
  ADD CONSTRAINT backward_test_force_projection_failure CHECK (score < 0) NOT VALID;

DO $atomicity$
DECLARE
  v_player uuid;
  v_run uuid;
  v_result jsonb;
  v_status text;
  i integer;
  v_seed bigint;
  v_variance numeric;
BEGIN
  SELECT user_id INTO v_player FROM public.backward_players ORDER BY created_at LIMIT 1;
  INSERT INTO public.backward_game_runs
    (player_id, mode, challenge_date, challenge_seed, device_class, client_version)
  VALUES (v_player, 'daily', DATE '2099-01-02', 20261119, 'unknown', 'atomicity-test')
  RETURNING id INTO v_run;

  FOR i IN 1..8 LOOP
    v_seed := mod(20261119::numeric * 100 + (i - 1), 4294967296)::bigint;
    v_variance := least(0.9::double precision, 0.1::double precision + i * 0.08::double precision)::numeric;
    v_result := public.backward_submit_trial(v_run, v_player, i::smallint, i::smallint, least(3+i,12)::smallint, 8::smallint, v_variance, v_seed, 0, 1000, 0);
    IF NOT (v_result->>'ok')::boolean THEN RAISE EXCEPTION 'Trial % failed: %', i, v_result; END IF;
  END LOOP;

  BEGIN
    PERFORM public.backward_finalize_run(v_run, v_player, 0);
    RAISE EXCEPTION 'Expected projection constraint to abort finalization';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  SELECT status::text INTO v_status FROM public.backward_game_runs WHERE id = v_run;
  IF v_status <> 'in_progress' THEN
    RAISE EXCEPTION 'Run completion survived publication failure: %', v_status;
  END IF;
  IF EXISTS (SELECT 1 FROM public.backward_daily_leaderboard WHERE run_id = v_run) THEN
    RAISE EXCEPTION 'Private leaderboard row survived failed publication';
  END IF;
END;
$atomicity$;

ALTER TABLE public.backward_daily_leaderboard_public
  DROP CONSTRAINT backward_test_force_projection_failure;

DO $repair$
DECLARE
  v_player uuid;
  v_run uuid;
  v_result jsonb;
BEGIN
  SELECT user_id INTO v_player FROM public.backward_players ORDER BY created_at LIMIT 1;
  SELECT id INTO v_run FROM public.backward_game_runs
  WHERE player_id = v_player AND client_version = 'atomicity-test'
  ORDER BY created_at DESC LIMIT 1;
  v_result := public.backward_finalize_run(v_run, v_player, 0);
  IF NOT (v_result->>'ok')::boolean OR NOT (v_result->>'leaderboard_published')::boolean THEN
    RAISE EXCEPTION 'Finalization repair after removing injected fault failed: %', v_result;
  END IF;
END;
$repair$;

ROLLBACK;
