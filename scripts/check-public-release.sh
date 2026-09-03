#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$PROJECT_ROOT"

required_files=(
  LICENSE
  PRIVACY.md
  SECURITY.md
  CONTRIBUTING.md
  CODE_OF_CONDUCT.md
  THIRD_PARTY_NOTICES.md
  Sources/Iles/Resources/PrivacyInfo.xcprivacy
  Sources/Iles/Resources/Iles.icns
  packaging/certs/AppleDeveloperIDCA.cer
  packaging/certs/AppleDeveloperIDG2CA.cer
)

for required_file in "${required_files[@]}"; do
  [[ -s "$required_file" ]] || { echo "Missing release file: $required_file" >&2; exit 1; }
done

plutil -lint Sources/Iles/Info.plist Sources/Iles/Resources/PrivacyInfo.xcprivacy >/dev/null

# Same published shapes as jean-humann/gwnative: X.Y.Z or X.Y.Z-(alpha|beta|rc).N.
# Tags add the v; CFBundleShortVersionString and the About line do not.
version_identifier() {
  [[ -n "$1" && "$1" == [0-9]* && "$1" != *[^0-9]* && "$1" != 0?* ]]
}
published_version() {
  local version=$1 core rest channel sequence major minor patch extra
  [[ -n "$version" && "$version" != v* ]] || return 1
  if [[ "$version" == *-* ]]; then
    core=${version%%-*}
    rest=${version#*-}
    [[ "$rest" == *.* && "$rest" != *.*.* ]] || return 1
    channel=${rest%%.*}
    sequence=${rest#*.}
    case "$channel" in
      alpha|beta|rc) ;;
      *) return 1 ;;
    esac
    version_identifier "$sequence" || return 1
  else
    core=$version
  fi
  IFS=. read -r major minor patch extra <<< "$core"
  [[ -n "$major" && -n "$minor" && -n "$patch" && -z "${extra:-}" ]] || return 1
  version_identifier "$major" && version_identifier "$minor" && version_identifier "$patch"
}

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Iles/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Iles/Info.plist)"
published_version "$VERSION" || {
  echo "CFBundleShortVersionString must be X.Y.Z or X.Y.Z-(alpha|beta|rc).N (found: $VERSION)." >&2
  exit 1
}
[[ "$BUILD" == [1-9]* && "$BUILD" != *[^0-9]* ]] || {
  echo "CFBundleVersion must be a positive integer (found: $BUILD)." >&2
  exit 1
}
grep -qE "^## ${VERSION} - [0-9]{4}-[0-9]{2}-[0-9]{2}\$" CHANGELOG.md || {
  echo "CHANGELOG.md needs a dated section for $VERSION." >&2
  exit 1
}
grep -q 'NSPrivacyAccessedAPICategoryFileTimestamp' Sources/Iles/Resources/PrivacyInfo.xcprivacy || {
  echo "PrivacyInfo.xcprivacy must declare File Timestamp access." >&2
  exit 1
}

SWIFTTERM_VERSION="$(sed -n 's/.*SwiftTerm\.git", exact: "\([^"]*\)".*/\1/p' Package.swift | head -n 1)"
[[ -n "$SWIFTTERM_VERSION" ]] || {
  echo "Package.swift must pin SwiftTerm with exact: \"X.Y.Z\"." >&2
  exit 1
}
grep -q "^### SwiftTerm$" THIRD_PARTY_NOTICES.md || {
  echo "THIRD_PARTY_NOTICES.md must name SwiftTerm without a second version pin." >&2
  exit 1
}

git diff --check

if git grep --untracked -I -n -E -e \
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|/Users/[^/[:space:]]+/' \
  -- ':!scripts/check-public-release.sh'; then
  echo "Potential secret or personal absolute path found." >&2
  exit 1
fi

if [[ "${CHECK_HISTORY:-0}" == "1" ]]; then
  history_emails="$(git log --format='%ae')"
  if grep -q '\.local$' <<< "$history_emails"; then
    echo "Git history contains private .local author addresses; rewrite them before the first public push." >&2
    exit 1
  fi
fi

echo "Public-release checks passed."
