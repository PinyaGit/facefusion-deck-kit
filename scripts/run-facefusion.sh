#!/usr/bin/env bash
# Native FaceFusion launcher for SteamOS / Linux (no Pinokio).
set -euo pipefail

FACEFUSION_HOME="${FACEFUSION_HOME:-$HOME/facefusion}"
CONDA_ROOT="${CONDA_ROOT:-$HOME/miniforge3}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-facefusion}"
PROFILE="${1:-}"

export TMPDIR="${TMPDIR:-$FACEFUSION_HOME/.tmp}"
mkdir -p "$TMPDIR" "$FACEFUSION_HOME/.jobs"

if [[ -z "$PROFILE" ]]; then
  if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    PROFILE="$(zenity --list \
      --title="FaceFusion" \
      --text="Профиль Steam Deck" \
      --column="id" --column="Профиль" --column="Зачем" \
      --hide-column=1 \
      balanced "Balanced" "Обычная работа (swap + рот)" \
      fast "Fast" "Превью / батарея" \
      quality "Quality" "Финал (медленнее на CPU)" \
      --width=480 --height=280 2>/dev/null || true)"
  fi
  PROFILE="${PROFILE:-balanced}"
fi

case "$PROFILE" in
  fast|balanced|quality) ;;
  *)
    echo "Usage: $0 [fast|balanced|quality]" >&2
    exit 1
    ;;
esac

CONFIG="$FACEFUSION_HOME/facefusion.${PROFILE}.ini"
[[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG" >&2; exit 1; }
[[ -f "$CONDA_ROOT/etc/profile.d/conda.sh" ]] || {
  echo "Conda not found at $CONDA_ROOT. Run ./install-native.sh first." >&2
  exit 1
}

# shellcheck disable=SC1091
source "$CONDA_ROOT/etc/profile.d/conda.sh"
conda activate "$CONDA_ENV_NAME"

cd "$FACEFUSION_HOME"
echo "FaceFusion — profile: $PROFILE"
echo "Config: $CONFIG"
echo "Provider: CPU onnxruntime (DirectML is Windows-only)"
echo "Opening UI in the browser..."
exec python facefusion.py run --open-browser --config-path "$CONFIG"
