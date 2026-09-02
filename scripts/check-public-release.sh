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
