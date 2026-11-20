# Engineering change log

## 2026-11-20
- Restored and hardened the correct-orbit reveal lifecycle: both successful selection and timeout enter the reveal phase before asynchronous persistence and continuation.
- Added a high-visibility success ring, glow, enlarged orbit marker and reveal status message.
- Added regression assertions for the shared selection/timeout settlement path, reveal styling, timeout routing and reveal duration.
- Confirmed by the project owner in production Safari that the green correct-orbit ring appears after both a correct selection and timeout.
- Published the single-file frontend to the existing Netlify production site. Deploy `6b002f118d8fe32648b5e987` reached `ready` state on 2026-11-20.
- GitHub Actions run `44727692550` passed frontend static validation and manual-deployment packaging.

## 2026-11-19
- Added root-level `index.html`, derived from the recovered original `index 5.html`; retained the original orbit gameplay, scoring display, daily challenge and endless mode.
- Added request timeouts, actionable network errors and one session-refresh attempt on HTTP 401.
- Await each trial write before progressing; failed saves pause the game and offer an exact-payload retry.
- Added finalization retry and local active-run recovery after refresh.
- Improved iOS viewport/safe-area handling, touch hit-testing, orientation updates and pause/resume when the browser is backgrounded.
- Added transactional trial acceptance with run-row locking and idempotent exact retries.
- Normalized trial-variance replay comparison to the server-derived canonical value, covering JavaScript floating-point serialization edge cases.
- Added atomic finalization and public leaderboard projection repair.
- Deployed Supabase Edge Function version 5 with JWT verification enabled.
- Applied additive migration `backward_atomic_trial_and_finalization`; no table data or RLS policies changed.
- Added static frontend and rollback-only PostgreSQL transaction smoke tests.
