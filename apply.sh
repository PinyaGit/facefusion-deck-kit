#!/usr/bin/env bash
# Apply facefusion-deck-kit on top of a clean FaceFusion / Pinokio install.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
SKIP_NSFW=0
SKIP_PROFILES=0
SKIP_PINOKIO=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./apply.sh [options] [target]

Options:
  --target PATH     Pinokio app folder or FaceFusion clone
  --skip-nsfw       Do not patch NSFW filter
  --skip-profiles   Do not copy profile .ini files
  --skip-pinokio    Do not overwrite run.js / menu.js
  --dry-run         Show actions without writing
  -h, --help        Show help

If target is omitted, tries common Pinokio paths.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --skip-nsfw) SKIP_NSFW=1; shift ;;
    --skip-profiles) SKIP_PROFILES=1; shift ;;
    --skip-pinokio) SKIP_PINOKIO=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$TARGET" && "$1" != -* ]]; then TARGET="$1"; shift
      else echo "Unknown arg: $1" >&2; usage; exit 1
      fi
      ;;
  esac
done

detect_target() {
  local c
  for c in \
    "$HOME/pinokio/api/facefusion-pinokio.git" \
    "$HOME/.pinokio/api/facefusion-pinokio.git" \
    "/pinokio/api/facefusion-pinokio.git"
  do
    [[ -d "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

if [[ -z "$TARGET" ]]; then
  TARGET="$(detect_target || true)"
  [[ -n "$TARGET" ]] || { echo "Target not found. Pass path to Pinokio FaceFusion or FaceFusion clone." >&2; exit 1; }
  echo "Auto-detected target: $TARGET"
fi

TARGET="$(cd "$TARGET" && pwd)"

layout="unknown"
if [[ -f "$TARGET/run.js" && -f "$TARGET/facefusion/facefusion.py" ]]; then
  layout="pinokio"
elif [[ -f "$TARGET/facefusion.py" ]]; then
  layout="standalone"
elif [[ -f "$TARGET/facefusion/facefusion.py" ]]; then
  layout="nested"
fi

[[ "$layout" != "unknown" ]] || { echo "Unrecognized layout at $TARGET" >&2; exit 1; }

echo "==> Target: $TARGET"
echo "==> Layout: $layout"

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="$TARGET/deck-kit-backup/$TS"
mkdir -p "$BACKUP"
echo "==> Backup folder: $BACKUP"

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local base parent tag dest
  base="$(basename "$f")"
  parent="$(basename "$(dirname "$f")")"
  dest="$BACKUP/${parent}__${base}"
  cp -f "$f" "$dest"
}

if [[ $SKIP_PROFILES -eq 0 ]]; then
  echo "==> Installing profile configs"
  if [[ "$layout" == "standalone" ]]; then
    FACE_ROOT="$TARGET"
  else
    FACE_ROOT="$TARGET/facefusion"
  fi
  [[ -f "$FACE_ROOT/facefusion.py" ]] || { echo "facefusion.py not found under $FACE_ROOT" >&2; exit 1; }
  for ini in "$KIT_ROOT"/overlay/facefusion/*.ini; do
    dest="$FACE_ROOT/$(basename "$ini")"
    backup_file "$dest"
    if [[ $DRY_RUN -eq 0 ]]; then
      cp -f "$ini" "$dest"
    fi
    echo "  copied $(basename "$ini")"
  done
fi

if [[ $SKIP_PINOKIO -eq 0 && "$layout" == "pinokio" ]]; then
  echo "==> Installing Pinokio launcher overlay"
  for name in run.js menu.js; do
    src="$KIT_ROOT/overlay/pinokio/$name"
    dest="$TARGET/$name"
    backup_file "$dest"
    if [[ $DRY_RUN -eq 0 ]]; then
      cp -f "$src" "$dest"
    fi
    echo "  copied $name"
  done
elif [[ $SKIP_PINOKIO -eq 0 ]]; then
  echo "  (not a Pinokio app root — skipping run.js/menu.js)"
fi

if [[ $SKIP_NSFW -eq 0 ]]; then
  echo "==> Patching NSFW filter"
  PYTHON=""
  for p in "$TARGET/.env/bin/python" "$TARGET/.env/python.exe" "$TARGET/facefusion/.env/bin/python" "python3" "python"; do
    if [[ "$p" == python* ]]; then
      command -v "$p" >/dev/null 2>&1 && { PYTHON="$p"; break; }
    elif [[ -x "$p" ]]; then
      PYTHON="$p"; break
    fi
  done
  [[ -n "$PYTHON" ]] || { echo "Python not found" >&2; exit 1; }

  for pkg in "$TARGET/facefusion/facefusion" "$TARGET/facefusion"; do
    for f in content_analyser.py core.py; do
      [[ -f "$pkg/$f" ]] && backup_file "$pkg/$f"
    done
  done

  args=("$KIT_ROOT/scripts/patch_nsfw.py" "$TARGET")
  [[ $DRY_RUN -eq 1 ]] && args+=(--dry-run)
  "$PYTHON" "${args[@]}"
fi

echo
echo "Done."
echo "Backups: $BACKUP"
echo
echo "Next steps:"
echo "  1. Stop FaceFusion if running"
echo "  2. In Pinokio pick Fast / Balanced / Quality"
echo "  3. After Update/Reset, re-run this script"
echo
echo "Standalone:"
echo "  python facefusion.py run --config-path facefusion.balanced.ini"
