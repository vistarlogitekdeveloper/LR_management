#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Cloudflare Pages build for the Flutter web app.
#
# Cloudflare's build image has Node/Python/git but NOT Flutter, and it won't
# run a build unless you give it a command — that's why the deploy failed with
# 'Output directory "build/web" not found'. This script installs the pinned
# Flutter SDK and produces build/web.
#
# In the Cloudflare Pages project → Settings → Builds & deployments, set:
#     Build command:            bash cloudflare-build.sh
#     Build output directory:   build/web      (already set in wrangler.toml)
# ---------------------------------------------------------------------------
set -euo pipefail

# Match the team's local Flutter (run `flutter --version`). Bump when you upgrade.
#
# This is the SDK production is actually compiled with. It had drifted to 3.41.9
# while every developer ran 3.44.4, which meant any dependency requiring Dart
# ^3.12.0 or Flutter >=3.44.0 resolved locally and failed here — and CI could not
# catch it because CI pinned the same wrong version. Keep this, the
# `flutter-version` in .github/workflows/deploy-cloudflare.yml, and pubspec.yaml's
# `environment.flutter` floor in lockstep; CI fails if the first two disagree.
FLUTTER_VERSION="3.44.4"
FLUTTER_DIR="$HOME/flutter"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo ">> Cloning Flutter $FLUTTER_VERSION ..."
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
# Cloudflare's container runs as a non-root user in a fresh checkout; Flutter
# 3.x warns about a "dubious ownership" git dir otherwise.
git config --global --add safe.directory "$FLUTTER_DIR" || true

flutter --version
flutter config --enable-web
flutter pub get

# ---------------------------------------------------------------------------
# Google Maps browser key
#
# Set GOOGLE_MAPS_BROWSER_KEY as a BUILD variable in Cloudflare Pages —
# Settings → Build → Variables and secrets.
#
# THE BUILD LIST, NOT THE RUNTIME ONE. The dashboard has two separate lists and
# they look almost identical. "Variables and Secrets" on the project page is the
# RUNTIME scope: what Pages Functions read when serving a request. This script
# runs in the BUILD container, which only sees the build list. A key entered in
# the runtime list is present in the project, shows up in
# `wrangler pages download config` under [env.production.vars], and is still
# completely invisible here — the build takes the else branch below, ships no
# key, and the picker falls back to OpenStreetMap. That cost an afternoon on
# 2026-09-15; the diagnostic in that branch exists to stop it costing another.
#
# It is a Maps JavaScript API key, restricted by HTTP referrer to the Pages
# domains. It is NOT a secret — any browser key is readable in the shipped
# bundle, which is why the referrer restriction is what protects it — but it is
# kept out of the repository so rotating it is a dashboard change, and so a
# checkout does not carry a key that bills to this account.
#
# ONE CHANNEL. The key used to be injected twice — here as a --dart-define AND
# by substituting a placeholder in web/index.html — and the two could disagree.
# The SDK is now loaded at runtime from Dart (features/maps/utils/maps_loader.dart),
# so this define is the only input and web/index.html is untouched by this script.
#
# UNSET IS A SUPPORTED CONFIGURATION, not a failure: no define is passed and the
# picker draws OpenStreetMap, which is also what a plain local `flutter run`
# gets. The pin it returns is exact either way.
# ---------------------------------------------------------------------------
MAPS_KEY="${GOOGLE_MAPS_BROWSER_KEY:-}"
DART_DEFINES=()

if [ -n "$MAPS_KEY" ]; then
  echo ">> Google Maps browser key present — the picker will request a Google map"
  DART_DEFINES+=(--dart-define=GOOGLE_MAPS_BROWSER_KEY="$MAPS_KEY")
else
  echo ">> No GOOGLE_MAPS_BROWSER_KEY — the picker will use OpenStreetMap"
  # Say WHY, because "not set" and "set in the wrong list" look identical from
  # here and only one of them is what anyone intended. Never echo the value.
  if [ "${GOOGLE_MAPS_BROWSER_KEY+set}" = "set" ]; then
    echo "   (the variable EXISTS but is empty — check for stray whitespace or an empty value)"
  else
    echo "   (the variable is NOT in this build's environment at all)"
    echo "   If you added it under Settings -> Variables and Secrets, that is the RUNTIME"
    echo "   list and builds cannot see it. Add it under Settings -> Build -> Variables"
    echo "   and secrets, then redeploy."
  fi

  # On the PRODUCTION branch this is now a build failure, not a warning.
  #
  # Shipping without the key is a supported configuration — the picker draws
  # OpenStreetMap and still returns an exact pin — which is precisely why nobody
  # noticed that production had been doing it. A green deploy serving a map the
  # business asked to replace is the worst of both outcomes: nothing is broken
  # enough to alert on, and the only evidence is a line in a build log nobody
  # reads. Failing here puts the message in front of the person who just clicked
  # deploy, at the one moment they can fix it.
  #
  # Scoped to the production branch so preview deploys, forks and local runs are
  # unaffected. CF_PAGES_BRANCH is set by Cloudflare Pages; outside Pages it is
  # empty and this never fires. Set ALLOW_NO_MAPS_KEY=1 to ship production
  # without a key deliberately.
  if [ "${CF_PAGES_BRANCH:-}" = "main" ] && [ "${ALLOW_NO_MAPS_KEY:-}" != "1" ]; then
    echo "!! Refusing to publish production without a Maps browser key." >&2
    echo "!! Add GOOGLE_MAPS_BROWSER_KEY under Settings -> Build -> Variables and secrets" >&2
    echo "!! and retry this deployment, or set ALLOW_NO_MAPS_KEY=1 to ship OpenStreetMap." >&2
    exit 1
  fi
fi

flutter build web --release --base-href "/" "${DART_DEFINES[@]+"${DART_DEFINES[@]}"}"

echo ">> Done — output in build/web"
