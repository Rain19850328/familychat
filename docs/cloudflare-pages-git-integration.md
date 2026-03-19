# Cloudflare Pages Git Integration

This repository is configured to use Cloudflare Pages Git integration as the only automatic frontend deployment path.

## What changed

- GitHub Actions no longer deploy the frontend.
- The old `wrangler` deployment workflow was removed.
- The frontend GitHub Actions workflow now verifies the build only.

## Recommended Cloudflare Pages settings

- Production branch: `main`
- Build command: `npm run build:static`
- Build output directory: `dist`

## GitHub Actions behavior

The workflow at `.github/workflows/pages-deploy.yml` now runs:

- `npm run verify:deploy`
- `npm run build:static`

That workflow is CI only. Production deployment should be triggered by Cloudflare Pages after pushes to `main`.
