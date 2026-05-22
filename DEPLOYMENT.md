# Deployment — Cloudflare Pages

The Flutter web build is deployed to **Cloudflare Pages**. Two flows are supported:

1. **GitHub Actions** (recommended) — auto-deploys on every push to `main`
2. **Direct CLI** — `wrangler pages deploy` from your machine

---

## Prerequisites

You'll need:

- A Cloudflare account (free tier is fine)
- A Cloudflare API token with **Pages — Edit** permission
- Your Cloudflare **Account ID**

### Generate the API token

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. **Create Token** → use the **Edit Cloudflare Pages** template
3. Copy the token (you only see it once)

### Find your Account ID

Open https://dash.cloudflare.com → any domain page → right sidebar shows **Account ID**.

---

## Option 1 — GitHub Actions (auto deploy)

The workflow at [.github/workflows/deploy-cloudflare.yml](.github/workflows/deploy-cloudflare.yml) builds and publishes on every push to `main`.

### One-time setup

In the GitHub repo settings → **Secrets and variables → Actions**, add two repository secrets:

| Secret name | Value |
|---|---|
| `CLOUDFLARE_API_TOKEN` | the token you generated above |
| `CLOUDFLARE_ACCOUNT_ID` | your account ID |

### Create the Pages project (one-time)

In Cloudflare Pages dashboard → **Create application → Pages → Direct Upload** → name it `lr-management`. You don't need to upload anything — the GitHub workflow will push the build directly to this project.

Alternative (faster): just push to `main` once. The workflow's `wrangler pages deploy` step will auto-create the project if it doesn't exist.

### After setup

Every `git push origin main` triggers:

1. Flutter setup (cached)
2. `flutter pub get` · `flutter analyze` · `flutter test`
3. `flutter build web --release`
4. Upload `build/web` to Cloudflare Pages

You'll get a deployment URL like `https://lr-management.pages.dev` plus a per-commit preview URL.

---

## Option 2 — Direct CLI deploy

For ad-hoc deploys from your laptop:

```bash
# Build locally
flutter build web --release

# Install Wrangler if you haven't
npm install -g wrangler

# Login (browser-based, one-time)
wrangler login

# Deploy
wrangler pages deploy build/web --project-name=lr-management
```

The first run creates the Pages project. Subsequent runs publish new versions.

---

## Custom domain

In the Pages project settings → **Custom domains** → add `lr.vistarlogitek.com` (or your domain). Cloudflare handles the SSL cert automatically.

---

## What's wired up for production web

- **Path URL strategy** ([lib/main.dart](lib/main.dart)) — clean URLs (`/lrs/new` not `/#/lrs/new`)
- **SPA fallback** ([web/_redirects](web/_redirects)) — any unknown path serves `index.html` so go_router can handle it
- **Cache headers** ([web/_headers](web/_headers)) — long-cache for hashed assets, no-cache for `index.html` and the service worker so updates roll out immediately

---

## Common issues

- **`wrangler: command not found`** — install Node 18+ and run `npm install -g wrangler`
- **404 on deep links** — confirm `web/_redirects` was included in the build (it should auto-copy to `build/web/_redirects`)
- **Stale UI after deploy** — the `_headers` rule for `index.html` should fix this; if not, hard-reload (Ctrl+Shift+R)
- **Workflow fails on `flutter test`** — run `flutter test` locally first; the workflow blocks deploy on test failure
