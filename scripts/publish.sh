#!/bin/zsh
# Create the GitHub release for a tag from the artifacts scripts/release.sh wrote.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$PROJECT_ROOT"

TAG="${1:?Usage: scripts/publish.sh vX.Y.Z}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Iles/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Iles/Info.plist)"
ARCHIVE="$PROJECT_ROOT/dist/Iles-$VERSION-$BUILD.zip"
CHECKSUM="$ARCHIVE.sha256"

[[ -f "$ARCHIVE" && -f "$CHECKSUM" ]] || {
  echo "Missing $ARCHIVE or $CHECKSUM. Run scripts/release.sh first." >&2
  exit 1
}

NOTES="$(awk '
  $0 == "## Unreleased" { next }
  $0 ~ /^## / { if (found) exit; found=1 }
  found { print }
' CHANGELOG.md)"
[[ -n "$NOTES" ]] || NOTES="Iles $VERSION."

gh release create "$TAG" \
  --title "Iles $VERSION" \
  --notes "$NOTES" \
  "$ARCHIVE" \
  "$CHECKSUM"
