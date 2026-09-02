#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$PROJECT_ROOT"

NOTARY_PROFILE="${NOTARY_PROFILE:-iles}"
if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  SIGNING_IDENTITY="$("$PROJECT_ROOT/scripts/sign-identity")"
fi
case "$SIGNING_IDENTITY" in
  "Developer ID Application:"*) ;;
  *)
    echo "Need a Developer ID Application identity (found: ${SIGNING_IDENTITY:-none})." >&2
    exit 1
    ;;
esac

PRODUCT_NAME="Iles"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Iles/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Iles/Info.plist)"
EXPECTED_TAG="v$VERSION"
if [[ "${ILES_SKIP_TAG_CHECK:-}" != "1" ]]; then
  CURRENT_TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
  [[ "$CURRENT_TAG" == "$EXPECTED_TAG" ]] || {
    echo "Release from tag $EXPECTED_TAG (current tag: ${CURRENT_TAG:-none})." >&2
    exit 1
  }
fi
[[ -z "$(git status --porcelain 2>/dev/null)" ]] || {
  echo "The working tree has uncommitted changes; commit or stash them first." >&2
  exit 1
}
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/Iles-release.XXXXXX")"

cleanup() {
  [[ "$WORK_ROOT" == *"/Iles-release."* ]] && /bin/rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

CHECK_HISTORY=1 ./scripts/check-public-release.sh
./scripts/test.sh

for architecture in arm64 x86_64; do
  triple="${architecture}-apple-macosx26.0"
  swift build -c release --product "$PRODUCT_NAME" --triple "$triple"
  binary_directory="$(swift build -c release --show-bin-path --triple "$triple")"
  cp "$binary_directory/$PRODUCT_NAME" "$WORK_ROOT/$PRODUCT_NAME-$architecture"
done

lipo -create \
  "$WORK_ROOT/$PRODUCT_NAME-arm64" \
  "$WORK_ROOT/$PRODUCT_NAME-x86_64" \
  -output "$WORK_ROOT/$PRODUCT_NAME"
lipo "$WORK_ROOT/$PRODUCT_NAME" -verify_arch arm64 x86_64

PREBUILT_BINARY="$WORK_ROOT/$PRODUCT_NAME" \
SIGNING_IDENTITY="$SIGNING_IDENTITY" \
./scripts/package.sh

APP="$PROJECT_ROOT/dist/$PRODUCT_NAME.app"
ARCHIVE="$PROJECT_ROOT/dist/$PRODUCT_NAME-$VERSION-$BUILD.zip"
CHECKSUM="$ARCHIVE.sha256"
SUBMISSION_ARCHIVE="$WORK_ROOT/$PRODUCT_NAME-notarization.zip"
FINAL_ARCHIVE="$WORK_ROOT/$PRODUCT_NAME-release.zip"

codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION_ARCHIVE"
xcrun notarytool submit "$SUBMISSION_ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$FINAL_ARCHIVE"
mv -f "$FINAL_ARCHIVE" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$CHECKSUM"

echo "Release artifact: $ARCHIVE"
echo "Checksum: $CHECKSUM"
