#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="debug"
MODE="live"
EXTRA_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --demo) MODE="demo" ;;
    --release) CONFIGURATION="release" ;;
    --open-settings) EXTRA_ARGS+=("--open-settings") ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--demo] [--release] [--open-settings]" >&2
      exit 1
      ;;
  esac
done

CONFIGURATION="$CONFIGURATION" ./scripts/package.sh

APP="dist/Iles.app"
if pgrep -x Iles >/dev/null 2>&1; then
  killall Iles 2>/dev/null || true
  for _ in {1..40}; do
    if ! pgrep -x Iles >/dev/null 2>&1; then
      break
    fi
    sleep 0.05
  done
  if pgrep -x Iles >/dev/null 2>&1; then
    echo "Iles did not exit; refusing to reactivate an older build." >&2
    exit 1
  fi
fi

echo "Launching Iles ($MODE, $CONFIGURATION)..."
ARGS=()
if [[ "$MODE" == "demo" ]]; then
  ARGS+=("--demo")
fi
ARGS+=("${EXTRA_ARGS[@]}")
if [[ ${#ARGS[@]} -gt 0 ]]; then
  open "$APP" --args "${ARGS[@]}"
else
  open "$APP"
fi
