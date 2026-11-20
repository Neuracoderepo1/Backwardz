# BACKWARDZ

BACKWARD is a cognitive orbit-finding game. This repository preserves the recovered original interface and mechanics while hardening its client/server contract.

## Architecture
- Static browser frontend: root `index.html`.
- Supabase anonymous authentication: persisted browser session.
- Edge Function: `backward-game`, with JWT verification enabled.
- Authoritative game writes: service-role Edge Function only.
- Database: RLS-protected private player/run/trial tables and a separate privacy-safe public leaderboard projection.

The browser never writes authoritative run or trial rows directly. Scores are recomputed by PostgreSQL from verified trial rows.

The correct-orbit reveal is explicitly held through the post-selection and timeout reveal phase before save/continuation. Native share cancellation does not trigger an asynchronous clipboard fallback, which Safari may block after transient user activation expires.

## Local checks
Requires Node.js 18+:

```sh
node tests/validate.mjs
```

For transactional database verification, run `tests/backend-transaction-smoke.sql` in the Supabase SQL editor. It creates test rows inside an explicit transaction and rolls the entire test back. It requires at least one existing `backward_players` row.

## Supabase deployment
The current production Edge Function is version 5. Its source is mirrored under `supabase/functions/backward-game/`. Migration `20261119195820_backward_atomic_trial_and_finalization.sql` creates the atomic RPC operations. Migration `20261119200546_backward_trial_idempotency_precision.sql` normalizes the retry comparison for JavaScript floating-point serialization.

Do not expose the service-role key in the frontend. Do not weaken RLS to resolve client permission errors.

## Netlify
The existing site is `backwardz` at https://backwardz.netlify.app. The root `index.html` is the only static publish entrypoint. The GitHub Actions workflow validates the frontend and packages exactly this one file as `backwardz-manual-deploy`. The connected Netlify integration supports inspection but not uploading/publishing a manual deploy. For a manual publish, upload the packaged `index.html` through the existing Netlify deploy flow. Do not upload repository documentation, tests, or Supabase migrations as site files; do not rename the site or change visitor access settings.
