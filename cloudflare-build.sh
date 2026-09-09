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
flutter build web --release --base-href "/"

echo ">> Done — output in build/web"
