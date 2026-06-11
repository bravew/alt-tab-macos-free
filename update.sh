#!/usr/bin/env bash
#
# update.sh — keep your free AltTab fork current.
#
# Pulls the latest upstream AltTab source, re-applies this fork's patches
# (Pro unlocked, auto-updater disabled, renamed bundle), rebuilds, signs with
# your local code-signing identity, and installs to /Applications.
#
# The fork patches live as commits on this branch, so a normal merge of
# upstream/master carries them forward. A conflict only happens if upstream
# edits the exact lines we patched (rare) — resolve it, commit, re-run.
#
# Usage:
#   ./update.sh                # update to latest upstream tag
#   ./update.sh 8.4.0          # force a specific version string
#   ALTTAB_SIGN_ID="" ./update.sh   # ad-hoc sign (re-grant permissions after)
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

APP_NAME="AltTab Free"
DEST="/Applications/${APP_NAME}.app"
SCHEME="Release"
BUILD_DIR="/tmp/altab-free-build"

# Signing identity so macOS keeps your Accessibility / Screen Recording grants
# across updates (same identity => same Designated Requirement => grant sticks).
# Override with ALTTAB_SIGN_ID; set to "" to force ad-hoc signing.
SIGN_ID="${ALTTAB_SIGN_ID-Apple Development: Justin Badua (J78B67C75H)}"

echo "==> Fetching upstream…"
git fetch --tags upstream

echo "==> Merging upstream/master (fork patches preserved)…"
if ! git merge --no-edit upstream/master; then
  echo "!! Merge conflict. Resolve it, run 'git commit', then re-run ./update.sh"
  exit 1
fi

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
[ -z "$VERSION" ] && VERSION="0.0.0"
echo "==> Version: $VERSION"

echo "==> Building ($SCHEME, unsigned)…"
rm -rf "$BUILD_DIR"
xcodebuild -project alt-tab-macos.xcodeproj -scheme "$SCHEME" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build >/tmp/altab-free-build.log 2>&1 \
  || { echo "Build failed:"; tail -25 /tmp/altab-free-build.log; exit 1; }

APP="$BUILD_DIR/Build/Products/$SCHEME/AltTab.app"
PL="$APP/Contents/Info.plist"

echo "==> Stamping version $VERSION (upstream leaves it blank, which crashes on launch)…"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PL" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PL" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PL"

if [ -n "$SIGN_ID" ] && security find-identity -v -p codesigning | grep -qF "$SIGN_ID"; then
  echo "==> Signing with: $SIGN_ID"
  codesign --force --deep --sign "$SIGN_ID" --options runtime "$APP"
else
  echo "==> Identity not found — ad-hoc signing (you'll re-grant permissions once)."
  codesign --force --deep --sign - "$APP"
fi

echo "==> Installing to $DEST…"
osascript -e 'quit app "AltTab"' 2>/dev/null || true
pkill -x AltTab 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
open "$DEST"

echo "==> Done. '$APP_NAME' updated to $VERSION."
echo "    Pro unlocked · auto-updater disabled · signed for stable permissions."

# (fork build pipeline — see .github/workflows/build-dmg.yml)
