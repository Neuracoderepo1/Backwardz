# Netlify deployment

Existing site: `backwardz`  
Production URL: https://backwardz.netlify.app

## Current production release

- Deploy ID: `6b002f118d8fe32648b5e987`
- Published: 2026-11-20
- State: `ready`
- Deploy source: manual file drop
- Published content: exactly one file, root `index.html`
- Production URL: https://backwardz.netlify.app

The production site has been updated with the current green-orbit reveal fix. The project owner confirmed in Safari that the green correct-orbit ring appears after both a correct selection and a timeout.

## Repeatable manual deployment

1. Confirm the intended frontend changes have passed GitHub Actions validation.
2. Package exactly the root `index.html` for the manual Netlify upload. Do not upload repository documentation, tests, or Supabase migrations as site files.
3. Open the existing `backwardz` site in Netlify. Do not rename it or change visitor access controls.
4. Upload the packaged `index.html` through the existing Netlify deploy flow.
5. Wait for Netlify to publish the new deploy and verify its state is `ready`.
6. Verify the landing page and game controls at the production URL. Test a Daily Challenge and an Endless run using real browsers when making a broader gameplay release.
7. Confirm server-verified scores and the public leaderboard. Do not treat a local score as verified if the Edge Function reports an error.

The connected Netlify integration supports inspection but does not expose a manual file-upload/publish action. The site is not confirmed as Git-connected.
