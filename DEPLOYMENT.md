# Netlify deployment

Existing site: `backwardz`  
Production URL: https://backwardz.netlify.app

1. Confirm the GitHub PR has been reviewed and merged to the production branch.
2. Open the existing `backwardz` site in Netlify. Do not rename it or change visitor access controls.
3. The Netlify integration connected to this workspace can inspect the site and deploy history but does not expose a manual file-upload/publish action. The site is not confirmed as Git-connected.
4. For the existing manual deployment workflow, upload the contents of the repository root (not the containing folder), ensuring `index.html` is at the publish root.
5. Wait for Netlify to publish the new deploy.
6. Verify the landing page and game controls at the production URL. Then test one Daily Challenge and one Endless run using real browsers.
7. Confirm server-verified scores and the public leaderboard. Do not treat a local score as verified if the Edge Function reports an error.

The production site has not been overwritten by this engineering task.
