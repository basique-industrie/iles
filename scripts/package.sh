#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$PROJECT_ROOT"

CONFIGURATION="${CONFIGURATION:-release}"
PRODUCT_NAME="Iles"
IDENTIFIER="com.jean.iles"
FINAL_APP="$PROJECT_ROOT/dist/${PRODUCT_NAME}.app"
ENTITLEMENTS="$PROJECT_ROOT/Sources/Iles/Iles.entitlements"
ICON="$PROJECT_ROOT/Sources/Iles/Resources/Iles.icns"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/Iles-package.XXXXXX")"
STAGED_APP="$STAGE_ROOT/${PRODUCT_NAME}.app"

cleanup() {
  [[ "$STAGE_ROOT" == *"/Iles-package."* ]] && /bin/rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

if [[ -n "${PREBUILT_BINARY:-}" ]]; then
  BINARY="$PREBUILT_BINARY"
else
  echo "Building ${PRODUCT_NAME} (${CONFIGURATION})..."
  swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME"
  BINARY_DIRECTORY="$(swift build -c "$CONFIGURATION" --show-bin-path)"
  BINARY="$BINARY_DIRECTORY/$PRODUCT_NAME"
fi

[[ -x "$BINARY" ]] || { echo "Missing executable: $BINARY" >&2; exit 1; }
[[ -f "$ICON" ]] || { echo "Missing application icon: $ICON" >&2; exit 1; }

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
install -m 0755 "$BINARY" "$STAGED_APP/Contents/MacOS/$PRODUCT_NAME"
install -m 0644 Sources/Iles/Info.plist "$STAGED_APP/Contents/Info.plist"
install -m 0644 "$ICON" "$STAGED_APP/Contents/Resources/Iles.icns"
install -m 0644 Sources/Iles/Resources/PrivacyInfo.xcprivacy "$STAGED_APP/Contents/Resources/PrivacyInfo.xcprivacy"
install -m 0644 LICENSE "$STAGED_APP/Contents/Resources/LICENSE.txt"
install -m 0644 THIRD_PARTY_NOTICES.md "$STAGED_APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
printf 'APPL????' > "$STAGED_APP/Contents/PkgInfo"

# SPM's generated Bundle.module looks next to the .app, which codesign rejects
# as unsealed bundle-root contents. IlesResourceBundle reads this copy instead.
BUNDLED_RESOURCES="$STAGED_APP/Contents/Resources/Iles_IlesCore.bundle"
mkdir -p "$BUNDLED_RESOURCES"
for resource in Sources/Iles/Resources/*; do
  [[ -f "$resource" ]] || continue
  case "${resource:t}" in
    PrivacyInfo.xcprivacy|Iles.icns|IlesAppIcon.png) continue ;;
  esac
  install -m 0644 "$resource" "$BUNDLED_RESOURCES/${resource:t}"
done
for license in Sources/Iles/Resources/Licenses/*; do
  [[ -f "$license" ]] || continue
  install -m 0644 "$license" "$BUNDLED_RESOURCES/${license:t}"
done
[[ -f "$BUNDLED_RESOURCES/ClaudeIcon.svg" ]] || {
  echo "Missing packaged resource bundle at $BUNDLED_RESOURCES" >&2
  exit 1
}

SIGNATURE="${SIGNING_IDENTITY:--}"
SIGN_ARGUMENTS=(--force --sign "$SIGNATURE" --entitlements "$ENTITLEMENTS" --identifier "$IDENTIFIER")
if [[ "$SIGNATURE" != "-" ]]; then
  SIGN_ARGUMENTS+=(--options runtime --timestamp)
else
  echo "Using an ad-hoc signature; this build is for local development only."
fi
codesign "${SIGN_ARGUMENTS[@]}" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

mkdir -p "$PROJECT_ROOT/dist"
PREVIOUS_APP="$STAGE_ROOT/previous.app"
if [[ -e "$FINAL_APP" ]]; then
  mv "$FINAL_APP" "$PREVIOUS_APP"
fi
if ! mv "$STAGED_APP" "$FINAL_APP"; then
  [[ -e "$PREVIOUS_APP" ]] && mv "$PREVIOUS_APP" "$FINAL_APP"
  exit 1
fi

echo "Packaged $FINAL_APP"
