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
# Set GOOGLE_MAPS_BROWSER_KEY in Cloudflare Pages → Settings → Environment
# variables. It is a Maps JavaScript API key, restricted by HTTP referrer to the
# Pages domains. It is NOT a secret — any browser key is readable in the shipped
# bundle, which is why the referrer restriction is what protects it — but it is
# kept out of the repository so rotating it is a dashboard change, and so a
# checkout does not carry a key that bills to this account.
#
# It is injected in TWO places because two layers need it, and they must agree:
#   - web/index.html   the <script> tag, or google.maps never exists
#   - --dart-define    so Dart knows whether to build a Google map or OSM tiles
#
# UNSET IS A SUPPORTED CONFIGURATION, not a failure: the script tag is removed,
# no define is passed, and the picker draws OpenStreetMap exactly as it did
# before any of this — which is also what every local `flutter run` gets.
# ---------------------------------------------------------------------------
MAPS_KEY="${GOOGLE_MAPS_BROWSER_KEY:-}"
DART_DEFINES=()

if [ -n "$MAPS_KEY" ]; then
  echo ">> Google Maps browser key present — enabling the Google map picker"
  # The key can contain '/' and '-', so use '|' as the sed delimiter. Edits the
  # build checkout only; nothing is written back to git.
  sed -i "s|__GOOGLE_MAPS_BROWSER_KEY__|${MAPS_KEY}|g" web/index.html
  DART_DEFINES+=(--dart-define=GOOGLE_MAPS_BROWSER_KEY="$MAPS_KEY")
  # Fail loudly rather than shipping a page that requests a map with the literal
  # placeholder as its key — that renders a blank grey box and bills nothing,
  # which is a confusing way to find out the substitution silently missed.
  if grep -q "__GOOGLE_MAPS_BROWSER_KEY__" web/index.html; then
    echo "!! placeholder still present in web/index.html after substitution" >&2
    exit 1
  fi
else
  echo ">> No GOOGLE_MAPS_BROWSER_KEY — the picker will use OpenStreetMap"
  # Drop the whole script tag. Leaving it in would request the Maps SDK with the
  # literal placeholder as the key on every page load, for nothing.
  sed -i '\|maps.googleapis.com/maps/api/js|d' web/index.html
fi

flutter build web --release --base-href "/" "${DART_DEFINES[@]+"${DART_DEFINES[@]}"}"

echo ">> Done — output in build/web"
