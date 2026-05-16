#!/bin/bash
#
# Nukes every stale copy of the app, rebuilds from scratch, and installs ONE
# canonical copy to /Applications. Use this whenever you're unsure which build
# you're running — afterwards there is exactly one app, freshly compiled, and
# its version string (menu bar + Settings footer) will match the current code.
#
# Usage:
#   ./scripts/clean-rebuild.sh            # Debug build (default, for testing)
#   ./scripts/clean-rebuild.sh release    # Release build
#

set -euo pipefail

CONFIG="Debug"
if [[ "${1:-}" == "release" ]]; then CONFIG="Release"; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DIR="$PROJECT_ROOT/build/derived"
APP_NAME="notch-prompter.app"
INSTALLED="/Applications/$APP_NAME"

cd "$PROJECT_ROOT"

VERSION_LINE=$(grep -E 'static let (marketing|label|buildDate)' notch-prompter/AppVersion.swift \
  | sed -E 's/.*= "(.*)"/\1/' | paste -sd' ' -)

echo "==> Target version: AiLA $VERSION_LINE  ($CONFIG)"

# 1. Kill any running instance ------------------------------------------------
echo "==> Killing running instances"
pkill -f "notch-prompter" 2>/dev/null || true
pkill -f "NotchPrompter"  2>/dev/null || true
sleep 1

# 2. Remove every known stale copy -------------------------------------------
echo "==> Removing stale copies"
rm -rf "$INSTALLED"
rm -rf "$HOME/Downloads/$APP_NAME"
# any unzipped team builds sitting in Downloads
find "$HOME/Downloads" -maxdepth 1 -name "$APP_NAME" -exec rm -rf {} + 2>/dev/null || true
# Xcode DerivedData for this project
rm -rf "$HOME/Library/Developer/Xcode/DerivedData/"NotchPrompter-* 2>/dev/null || true
rm -rf "$PROJECT_ROOT/build"

# 3. Tell LaunchServices to forget stale registrations ------------------------
echo "==> Resetting LaunchServices registration"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -kill -r -domain local -domain system -domain user 2>/dev/null || true

# 4. Regenerate + build -------------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Error: xcodegen not installed (brew install xcodegen)" >&2
    exit 1
fi
echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild ($CONFIG, ad-hoc)"
mkdir -p "$DERIVED_DIR"
xcodebuild \
    -project NotchPrompter.xcodeproj \
    -scheme notch-prompter \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    clean build \
    | (xcbeautify 2>/dev/null || cat)

APP_SRC="$DERIVED_DIR/Build/Products/$CONFIG/$APP_NAME"
if [[ ! -d "$APP_SRC" ]]; then
    echo "Error: build product not found at $APP_SRC" >&2
    exit 1
fi

# 5. Install ONE canonical copy ----------------------------------------------
echo "==> Installing fresh build to $INSTALLED"
cp -R "$APP_SRC" "$INSTALLED"
codesign --force --deep --sign - "$INSTALLED" 2>/dev/null || true

cat <<EOF

✓ Clean rebuild complete.

  Installed: $INSTALLED
  Version:   AiLA $VERSION_LINE

There is now exactly ONE copy of the app on this machine. Launch it with:

  open "$INSTALLED"

Then open the menu bar dropdown — the first line should read:

  AiLA $VERSION_LINE

If it does NOT match, something is still cached — quit, run this script
again, and confirm no Finder window has an old copy open.

EOF
