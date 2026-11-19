-- Normalize idempotent replay comparison against the canonical server-derived
-- variance. JavaScript's decimal arithmetic can serialize values such as
-- 0.33999999999999997 and 0.42000000000000004; the accepted row stores the
-- canonical decimal. Replays of the same payload must still be idempotent.

DO $migration$
DECLARE
  v_definition text;
  v_signature regprocedure := 'public.backward_submit_trial(uuid,uuid,smallint,smallint,smallint,smallint,numeric,bigint,integer,integer,integer)'::regprocedure;
BEGIN
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  IF position('v_existing.speed_variance = p_speed_variance' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Expected trial idempotency comparison was not found; refusing to apply precision patch';
  END IF;
  v_definition := replace(
    v_definition,
    'v_existing.speed_variance = p_speed_variance',
    'v_existing.speed_variance = v_expected_variance'
  );
  EXECUTE v_definition;
END;
$migration$;
