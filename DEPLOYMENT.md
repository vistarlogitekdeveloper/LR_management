# Deployment — Cloudflare Pages

The Flutter web build is deployed to **Cloudflare Pages**, project
**`vistar-transport-management-system`** — which keeps the
`lr-management.pages.dev` domain from before it was renamed, so the domain and
the project name deliberately do not match. Confirm the name with
`npx wrangler pages project list` before pointing anything at it; naming it
`lr-management` targets a project that does not exist.

Production is deployed by **Cloudflare Pages' own Git integration**. GitHub
Actions runs the checks but does **not** deploy.

---

## How a push reaches production

Pushing to `main` triggers the Pages Git integration, which:

1. clones the repo,
2. runs the project's **Build command**, `bash cloudflare-build.sh` — that
   script installs the pinned Flutter SDK (Cloudflare's build image has Node
   and git but no Flutter) and runs `flutter build web --release --base-href "/"`,
3. publishes `build/web`, the directory named by `pages_build_output_dir` in
   [wrangler.toml](wrangler.toml).

`build/` is gitignored and must never be committed — Cloudflare builds it.

### The one setting that does not live in this repo

Cloudflare Pages takes its **Build command from the dashboard**, not from
`wrangler.toml`. If it is ever cleared, every deploy fails with:

```
No build command specified. Skipping build step.
Error: Output directory "build/web" not found.
```

That reads like a missing build output, but it is really a missing build
command — nothing ever ran. Restore it at Pages → the project →
Settings → Builds & deployments:

| Setting | Value |
|---|---|
| Build command | `bash cloudflare-build.sh` |
| Build output directory | `build/web` |

### CI — runs the checks, does not gate the deploy

[.github/workflows/deploy-cloudflare.yml](.github/workflows/deploy-cloudflare.yml)
runs `flutter analyze --no-fatal-infos`, `flutter test`, and a release web build
on every push and PR. It has **no publish step**: publishing from both places
would race two deploys for the same commit.

Because it does not gate Cloudflare, a red run means *"a broken commit is
deploying right now"*, not *"the deploy was stopped"*. Fix forward promptly.

---

## Manual deploy from your machine

For an ad-hoc deploy that bypasses the Git integration:

```bash
# The build emits a self-unregistering cleanup service worker that removes any
# caching worker an older build installed (see "Stale UI" below).
flutter build web --release --base-href "/"

npm install -g wrangler   # if you don't have it
wrangler login            # browser-based, one-time

wrangler pages deploy build/web \
  --project-name=vistar-transport-management-system --branch=main
```

`--branch=main` is what makes it a **production** deploy: Pages compares the
branch name against the project's `production_branch` (`main`); any other value
publishes a preview instead.

---

## Custom domain

In the Pages project settings → **Custom domains** → add `lr.vistarlogitek.com`
(or your domain). Cloudflare handles the SSL cert automatically.

---

## What's wired up for production web

- **Path URL strategy** ([lib/main.dart](lib/main.dart)) — clean URLs (`/lrs/new` not `/#/lrs/new`)
- **SPA fallback** ([web/_redirects](web/_redirects)) — any unknown path serves `index.html` so go_router can handle it
- **Cache headers** ([web/_headers](web/_headers)) — everything Flutter emits under a *stable* filename (`index.html`, the entry JS, the service worker, and everything under `/assets/`) is served `max-age=0, must-revalidate`, so a new deploy reaches returning browsers. Flutter does **not** content-hash asset filenames, so do not add an `immutable` rule on the assumption that it does: the test is whether the FILENAME changes per build, not whether the file is an "asset". A stale `AssetManifest.bin` also makes assets added in a later release unresolvable.
- **No caching service worker** — current Flutter no longer keeps a cache-first service worker; `flutter build web` emits a self-unregistering *cleanup* `flutter_service_worker.js` instead (do not overwrite it — `flutter.js` version-coordinates with it). A browser re-fetches `/flutter_service_worker.js` on its own (the service-worker update check, independent of the page), so a browser still carrying a caching worker from an **older** build fetches this cleanup worker, unregisters the old one, and reloads — every user picks up the new build without clearing their cache. This, together with the `no-cache` header on that file, is what fixes "some users stuck on the old build after deploy."

---

## Common issues

- **`No build command specified` → `Output directory "build/web" not found`** — the dashboard Build command was cleared. See "The one setting that does not live in this repo" above. Nothing was built; this is not a build failure.
- **A deploy targets a missing project** — the project is `vistar-transport-management-system`, not `lr-management`. Check with `npx wrangler pages project list`.
- **`wrangler: command not found`** — install Node 18+ and run `npm install -g wrangler`
- **404 on deep links** — confirm `web/_redirects` was included in the build (it should auto-copy to `build/web/_redirects`)
- **Stale UI after deploy** — should no longer happen: `flutter build web` emits a self-unregistering cleanup service worker that removes any caching worker older builds installed, so returning users pick up the new build automatically (at most one extra reload, no manual cache clear). The critical requirement is that [web/_headers](web/_headers) serves `/flutter_service_worker.js` with `no-cache` (it does) so the browser always re-checks it. If a specific browser is *still* stuck, it hasn't re-fetched the worker yet — one hard-reload (Ctrl+Shift+R) forces it; after that it self-heals. Do **not** add a caching service worker (an older Flutter's `--pwa-strategy=offline-first`, or a hand-rolled Workbox cache) or this returns.
- **CI fails on `flutter test`** — run `flutter test` locally first. Note this does not stop the Cloudflare deploy.
