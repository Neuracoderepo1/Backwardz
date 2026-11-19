# BACKWARDZ security review

## Inspected production boundaries
- All five `backward_*` tables have RLS enabled.
- Private player, run and trial tables have owner-scoped SELECT policies; player profile UPDATE is owner-scoped.
- Private `backward_daily_leaderboard` has RLS enabled with no client policy. This is intentional: the Edge Function's service-role client is the only writer/reader.
- `backward_daily_leaderboard_public` exposes only id, challenge date, display name, score, completed rounds and timestamp; anon/authenticated have SELECT only.
- Trial uniqueness: `UNIQUE(run_id, round_index)`.
- Private leaderboard uniqueness: `UNIQUE(challenge_date, player_id)` and unique run_id.
- The Edge Function verifies the JWT and resolves the user through `auth.getUser()`. Anonymous Supabase users receive the authenticated database role and are scoped by `auth.uid()`.

## Changes
- Added `backward_submit_trial`: locks the owning run row, serializes round submissions, checks order and game limits, and returns an identical accepted submission as an idempotent success. Conflicting replays are rejected.
- Added `backward_finalize_run`: locks the run, recomputes the score, marks completion, updates the private leaderboard and upserts the public projection in one PostgreSQL transaction.
- A retry against an already-completed run re-synchronizes the private/public leaderboard projection, repairing the previous partial-publication failure mode.
- Both RPCs are SECURITY DEFINER with a fixed search_path and EXECUTE granted only to service_role. No RLS policy or table privilege was loosened.
- Edge Function version 5 adds owner-checked resume retrieval and delegates trial/finalization writes to the transactional RPCs.

## Supabase advisor findings
- INFO: private leaderboard has RLS enabled and no policy. This is intentional server-only access.
- WARN: owner-scoped policies on runs/trials/player profiles include authenticated role, which includes anonymous-authenticated game players. Access remains scoped to auth.uid().
- WARN: leaked-password protection is disabled. This is unrelated to anonymous game sign-in; no password-auth flow was introduced.
- INFO: five indexes are currently unused. No index was removed because the project has very low row counts and these indexes may support future query patterns.

## Remaining checks
- Real iOS Safari and Mobile Chrome interaction tests have not been run by the available browser automation.
- Anonymous sign-in was confirmed as the existing frontend onboarding flow, but a fresh anonymous sign-in was not exercised end-to-end from a real browser.
- Concurrent two-client HTTP stress tests are not yet performed. Database row locking plus uniqueness are implemented; transaction smoke tests cover sequential, duplicate, conflicting and rollback cases.
