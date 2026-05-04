#!/bin/bash
#
# Builds an ad-hoc-signed NotchPrompter.app with bundled API keys for internal
# team distribution via Slack / Drive. Outputs a .zip ready to upload.
#
# Prereqs (one-time):
#   - brew install xcodegen
#   - Copy notch-prompter/Secrets.plist.example to notch-prompter/Secrets.plist
#     and fill in your real Anthropic + ElevenLabs API keys.
#     (The file is gitignored — it never leaves your machine.)
#
# Usage:
#   ./scripts/build-team-release.sh
#

set -euo pipefail

# Resolve paths relative to repo root regardless of where this is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_FILE="$PROJECT_ROOT/notch-prompter/Secrets.plist"
SECRETS_EXAMPLE="$PROJECT_ROOT/notch-prompter/Secrets.plist.example"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED_DIR="$BUILD_DIR/derived"

cd "$PROJECT_ROOT"

# ---- Sanity checks -------------------------------------------------------

if ! command -v xcodegen >/dev/null 2>&1; then
    cat <<'EOF' >&2
Error: xcodegen is not installed.
Install it with:
  brew install xcodegen
EOF
    exit 1
fi

if [[ ! -f "$SECRETS_FILE" ]]; then
    cat <<EOF >&2
Error: $SECRETS_FILE does not exist.

Set it up once:
  cp "$SECRETS_EXAMPLE" "$SECRETS_FILE"
  open -e "$SECRETS_FILE"     # paste your real Anthropic + ElevenLabs keys

The file is gitignored — it stays on your machine and is bundled into the
team .app at build time so your teammates never have to enter keys.
EOF
    exit 1
fi

# Refuse to build if Secrets.plist still has the placeholder values.
if grep -q "PASTE-YOUR-KEY-HERE" "$SECRETS_FILE"; then
    echo "Error: $SECRETS_FILE still contains placeholder values." >&2
    echo "Open it and paste your real Anthropic + ElevenLabs keys." >&2
    exit 1
fi

# ---- Generate Xcode project ---------------------------------------------

echo "==> xcodegen generate"
xcodegen generate

# ---- Build (Release) -----------------------------------------------------

echo "==> xcodebuild (Release, ad-hoc signed)"
mkdir -p "$BUILD_DIR"

xcodebuild \
    -project NotchPrompter.xcodeproj \
    -scheme notch-prompter \
    -configuration Release \
    -derivedDataPath "$DERIVED_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    clean build \
    | xcbeautify 2>/dev/null || \
xcodebuild \
    -project NotchPrompter.xcodeproj \
    -scheme notch-prompter \
    -configuration Release \
    -derivedDataPath "$DERIVED_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    clean build

APP_SOURCE="$DERIVED_DIR/Build/Products/Release/notch-prompter.app"

if [[ ! -d "$APP_SOURCE" ]]; then
    echo "Error: Built app not found at $APP_SOURCE" >&2
    exit 1
fi

# ---- Re-sign + package ---------------------------------------------------

APP_DEST="$BUILD_DIR/notch-prompter.app"
ZIP_DEST="$BUILD_DIR/NotchPrompter-team-$(date +%Y%m%d-%H%M%S).zip"

echo "==> packaging"
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"

# Re-sign ad-hoc, deeply, so every embedded framework + bundle is consistent.
# Without this, Gatekeeper sometimes refuses to launch on a new machine.
codesign --force --deep --sign - "$APP_DEST"

# `ditto -c -k --keepParent` produces a zip that preserves the .app bundle
# directory structure, which is what macOS expects when extracted.
rm -f "$ZIP_DEST"
ditto -c -k --keepParent "$APP_DEST" "$ZIP_DEST"

ZIP_SIZE=$(du -h "$ZIP_DEST" | cut -f1)

cat <<EOF

✓ Build complete.

  App:  $APP_DEST
  Zip:  $ZIP_DEST  ($ZIP_SIZE)

Drop the zip in Slack / Drive. Team install:

  1. Download zip → unzip → drag notch-prompter.app to /Applications
  2. First launch: right-click → Open → Open  (one-time Gatekeeper warning)
  3. Grant Screen Recording permission when prompted
  4. Quit (⌘Q) and relaunch ONCE — macOS needs the relaunch to apply the permission
  5. Settings → Interview → fill in name + company; ready to use

API keys are pre-bundled — teammates do not need to enter them.

EOF
