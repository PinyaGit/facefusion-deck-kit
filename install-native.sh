#!/usr/bin/env bash
# Native FaceFusion 3.6.1 + deck-kit on SteamOS / Linux. No Pinokio, no root.
#
#   git clone https://github.com/PinyaGit/facefusion-deck-kit.git
#   cd facefusion-deck-kit
#   ./install-native.sh
#
# Re-run is safe: missing pieces are installed, kit overlay is re-applied.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FF_VERSION="${FF_VERSION:-3.6.1}"
FF_REPO="${FF_REPO:-https://github.com/facefusion/facefusion.git}"
FACEFUSION_HOME="${FACEFUSION_HOME:-$HOME/facefusion}"
CONDA_ROOT="${CONDA_ROOT:-$HOME/miniforge3}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-facefusion}"
MINIFORGE_URL="${MINIFORGE_URL:-https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh}"

FORCE_DEPS=0
SKIP_DESKTOP=0

usage() {
  cat <<EOF
Usage: ./install-native.sh [options]

Install FaceFusion ${FF_VERSION} into \$HOME (Miniforge + conda env + deck-kit).
Designed for Steam Deck / SteamOS. Does not write to the read-only rootfs.

Options:
  --force-deps      Re-run FaceFusion pip installer
  --skip-desktop    Do not write .desktop / PATH symlink
  --prefix PATH     FaceFusion directory (default: \$HOME/facefusion)
  --conda-root PATH Miniforge prefix (default: \$HOME/miniforge3)
  -h, --help        Show help

Env:
  FACEFUSION_HOME, CONDA_ROOT, CONDA_ENV_NAME, FF_VERSION
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-deps) FORCE_DEPS=1; shift ;;
    --skip-desktop) SKIP_DESKTOP=1; shift ;;
    --prefix) FACEFUSION_HOME="$2"; shift 2 ;;
    --conda-root) CONDA_ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

export TMPDIR="${TMPDIR:-$HOME/.tmp}"
mkdir -p "$TMPDIR" "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/icons"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Need '$1' in PATH"
}

need_cmd git
need_cmd curl
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "warning: ffmpeg not found. FaceFusion needs it for video. On SteamOS it is usually preinstalled." >&2
fi

if [[ "$(uname -s)" != Linux ]]; then
  die "install-native.sh is for Linux / SteamOS. On Windows use Pinokio + apply.ps1."
fi

log "FaceFusion ${FF_VERSION} native install"
log "Prefix:     $FACEFUSION_HOME"
log "Conda:      $CONDA_ROOT  (env: $CONDA_ENV_NAME)"
log "Kit:        $KIT_ROOT"

# --- Miniforge (user-space, no sudo) ---------------------------------------
if [[ ! -x "$CONDA_ROOT/bin/conda" ]]; then
  log "Installing Miniforge into $CONDA_ROOT"
  installer="$TMPDIR/Miniforge3-Linux-x86_64.sh"
  curl -L --fail --retry 3 -o "$installer" "$MINIFORGE_URL"
  bash "$installer" -b -p "$CONDA_ROOT"
  rm -f "$installer"
else
  log "Miniforge already present"
fi

# shellcheck disable=SC1091
source "$CONDA_ROOT/etc/profile.d/conda.sh"

if ! conda env list | awk '{print $1}' | grep -qx "$CONDA_ENV_NAME"; then
  log "Creating conda env $CONDA_ENV_NAME (Python 3.12)"
  conda create -y -n "$CONDA_ENV_NAME" python=3.12 pip
else
  log "Conda env $CONDA_ENV_NAME already present"
fi

conda activate "$CONDA_ENV_NAME"
python -V

# --- FaceFusion clone ------------------------------------------------------
if [[ ! -f "$FACEFUSION_HOME/facefusion.py" ]]; then
  if [[ -e "$FACEFUSION_HOME" && ! -d "$FACEFUSION_HOME" ]]; then
    die "$FACEFUSION_HOME exists and is not a directory"
  fi
  if [[ -d "$FACEFUSION_HOME" && -n "$(ls -A "$FACEFUSION_HOME" 2>/dev/null || true)" ]]; then
    die "$FACEFUSION_HOME exists but is not a FaceFusion tree. Move it aside or set FACEFUSION_HOME."
  fi
  log "Cloning FaceFusion $FF_VERSION"
  git clone --branch "$FF_VERSION" --depth 1 "$FF_REPO" "$FACEFUSION_HOME"
else
  log "FaceFusion already at $FACEFUSION_HOME"
fi

# --- Python deps -----------------------------------------------------------
need_install=1
if [[ $FORCE_DEPS -eq 0 ]]; then
  if python -c "import onnxruntime, gradio, cv2, numpy" >/dev/null 2>&1; then
    need_install=0
  fi
fi
if [[ $need_install -eq 1 ]]; then
  log "Installing FaceFusion Python deps (CPU onnxruntime)"
  (
    cd "$FACEFUSION_HOME"
    python install.py --onnxruntime default
  )
else
  log "Python deps already importable (use --force-deps to reinstall)"
fi

python -c "import onnxruntime as o; print('onnxruntime', o.__version__, o.get_available_providers())"

# --- deck-kit overlay ------------------------------------------------------
log "Applying deck-kit (NSFW patch + Deck profiles, skip Pinokio)"
chmod +x "$KIT_ROOT/apply.sh" "$KIT_ROOT/scripts/run-facefusion.sh" "$KIT_ROOT/install-native.sh"
"$KIT_ROOT/apply.sh" --target "$FACEFUSION_HOME" --skip-pinokio

install -m 0755 "$KIT_ROOT/scripts/run-facefusion.sh" "$FACEFUSION_HOME/run-facefusion.sh"
cat > "$FACEFUSION_HOME/reapply-deck-kit.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$KIT_ROOT/apply.sh" --target "$FACEFUSION_HOME" --skip-pinokio "\$@"
EOF
chmod +x "$FACEFUSION_HOME/reapply-deck-kit.sh"

# --- Desktop / PATH --------------------------------------------------------
if [[ $SKIP_DESKTOP -eq 0 ]]; then
  log "Installing launcher and desktop entry"
  ln -sfn "$FACEFUSION_HOME/run-facefusion.sh" "$HOME/.local/bin/facefusion"

  icon="$HOME/.local/share/icons/facefusion.png"
  if [[ ! -f "$icon" && -f "$FACEFUSION_HOME/facefusion.ico" ]]; then
    python - <<PY || true
from pathlib import Path
try:
    from PIL import Image
except ImportError:
    raise SystemExit(0)
src = Path("$FACEFUSION_HOME/facefusion.ico")
dst = Path("$icon")
img = Image.open(src)
best = None
i = 0
while True:
    try:
        img.seek(i)
        best = img.copy()
        i += 1
    except EOFError:
        break
if best is None:
    best = img
best.convert("RGBA").save(dst)
print("wrote", dst)
PY
  fi

  desktop_body=$(cat <<EOF
[Desktop Entry]
Name=FaceFusion
Comment=FaceFusion ${FF_VERSION} + deck-kit (native SteamOS)
Exec=${FACEFUSION_HOME}/run-facefusion.sh
Icon=${icon}
Terminal=true
Type=Application
Categories=Graphics;Video;
StartupNotify=true
EOF
)
  printf '%s\n' "$desktop_body" > "$HOME/.local/share/applications/facefusion.desktop"
  chmod +x "$HOME/.local/share/applications/facefusion.desktop"
  if [[ -d "$HOME/Desktop" ]]; then
    printf '%s\n' "$desktop_body" > "$HOME/Desktop/FaceFusion.desktop"
    chmod +x "$HOME/Desktop/FaceFusion.desktop"
    command -v gio >/dev/null 2>&1 && gio set "$HOME/Desktop/FaceFusion.desktop" metadata::trusted true 2>/dev/null || true
  fi
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

# --- bashrc conda hook (does not auto-activate the env) --------------------
bashrc="$HOME/.bashrc"
if [[ -f "$bashrc" ]] && ! grep -q '>>> facefusion conda >>>' "$bashrc"; then
  log "Adding conda hook to ~/.bashrc"
  cat >> "$bashrc" <<EOF

# >>> facefusion conda >>>
export PATH="\$HOME/.local/bin:\$PATH"
if [[ -f "$CONDA_ROOT/etc/profile.d/conda.sh" ]]; then
  # shellcheck disable=SC1091
  source "$CONDA_ROOT/etc/profile.d/conda.sh"
fi
# <<< facefusion conda <<<
EOF
fi

(
  cd "$FACEFUSION_HOME"
  python facefusion.py -v
)

echo
log "Done."
echo
echo "Launch:"
echo "  facefusion                 # zenity menu, default Balanced"
echo "  facefusion fast"
echo "  facefusion quality"
echo "  $FACEFUSION_HOME/run-facefusion.sh"
echo
echo "Desktop: FaceFusion (KDE app menu / ~/Desktop)"
echo
echo "Notes:"
echo "  - DirectML is Windows-only. This install uses CPU onnxruntime."
echo "  - First UI start downloads models (hundreds of MB). Stay online + on charger."
echo "  - Video is slow on Deck CPU. Prefer Fast/Balanced; Quality for stills/final."
echo "  - Re-apply kit after FaceFusion updates:"
echo "      $FACEFUSION_HOME/reapply-deck-kit.sh"
echo
