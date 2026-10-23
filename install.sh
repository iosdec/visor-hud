#!/usr/bin/env bash
# Visor HUD installer for cmux and Ghostty on macOS.
#
#   ./install.sh               install everything
#   ./install.sh --no-shell    skip the zsh shield hook
#   ./install.sh --no-font     skip installing Share Tech Mono
#
# Safe to run again: it updates files in place and backs up anything it edits.
set -euo pipefail

REPO_URL="https://github.com/iosdec/visor-hud.git"
SHARE_DIR="$HOME/.local/share/visor-hud"
GHOSTTY_DIR="$HOME/.config/ghostty"
CMUX_SIDEBARS="$HOME/.config/cmux/sidebars"
STATE_DIR="$HOME/.config/visor-hud"
CMUX_THEME_FILE="$HOME/Library/Application Support/com.cmuxterm.app/config.ghostty"
CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
BEGIN="# >>> visor-hud >>>"
END="# <<< visor-hud <<<"

with_shell=1
with_font=1
for arg in "$@"; do
    case "$arg" in
        --no-shell) with_shell=0 ;;
        --no-font) with_font=0 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

say() { printf '\033[38;2;63;208;255m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[38;2;245;184;65m!\033[0m %s\n' "$*"; }

[[ "$(uname)" == "Darwin" ]] || { echo "Visor HUD is for macOS (cmux / Ghostty)." >&2; exit 1; }

# Use the files next to this script, or fetch the repo when run via curl | bash.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ ! -f "$SRC/shaders/visor-hud.glsl" ]]; then
    say "Downloading Visor HUD"
    if [[ -d "$SHARE_DIR/.git" ]]; then
        git -C "$SHARE_DIR" pull --quiet --ff-only
    else
        rm -rf "$SHARE_DIR"
        git clone --quiet --depth 1 "$REPO_URL" "$SHARE_DIR"
    fi
    SRC="$SHARE_DIR"
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup() { [[ -f "$1" ]] && cp "$1" "$1.visor-backup-$stamp" || true; }

mkdir -p "$GHOSTTY_DIR/shaders" "$GHOSTTY_DIR/themes" "$CMUX_SIDEBARS" "$STATE_DIR"

say "Installing shader, theme and sidebar"
cp "$SRC/shaders/visor-hud.glsl" "$GHOSTTY_DIR/shaders/visor-hud.glsl"
cp "$SRC/themes/Visor" "$GHOSTTY_DIR/themes/Visor"
cp "$SRC/cmux/visor-hud.swift" "$CMUX_SIDEBARS/visor-hud.swift"
cp "$SRC/shell/shield.zsh" "$STATE_DIR/shield.zsh"

say "Adding settings to ~/.config/ghostty/config"
config="$GHOSTTY_DIR/config"
touch "$config"
backup "$config"
# Drop an older Visor block, then append a fresh one (the last setting wins in Ghostty).
sed -i '' "/^$BEGIN\$/,/^$END\$/d" "$config"
{
    echo "$BEGIN"
    echo "# Managed by visor-hud. Edit freely; run uninstall.sh to remove."
    sed "s|__SHADER__|$GHOSTTY_DIR/shaders/visor-hud.glsl|" "$SRC/ghostty/visor-hud.conf"
    echo "$END"
} >> "$config"

# cmux keeps its own theme choice, which overrides Ghostty's. Point it at Visor.
if [[ -f "$CMUX_THEME_FILE" ]]; then
    if [[ ! -f "$STATE_DIR/previous-cmux-theme" ]]; then
        grep '^theme = ' "$CMUX_THEME_FILE" > "$STATE_DIR/previous-cmux-theme" || echo "" > "$STATE_DIR/previous-cmux-theme"
    fi
    backup "$CMUX_THEME_FILE"
    if grep -q '^theme = ' "$CMUX_THEME_FILE"; then
        sed -i '' 's/^theme = .*/theme = light:Visor,dark:Visor/' "$CMUX_THEME_FILE"
    else
        printf '# cmux themes start\ntheme = light:Visor,dark:Visor\n# cmux themes end\n' >> "$CMUX_THEME_FILE"
    fi
fi

if (( with_font )); then
    if ls "$HOME/Library/Fonts"/ShareTechMono* /Library/Fonts/ShareTechMono* >/dev/null 2>&1; then
        say "Share Tech Mono already installed"
    elif command -v brew >/dev/null; then
        say "Installing the Share Tech Mono font"
        brew install --cask --quiet font-share-tech-mono || warn "Font install failed; get it from fonts.google.com/specimen/Share+Tech+Mono"
    else
        warn "Install the Share Tech Mono font: fonts.google.com/specimen/Share+Tech+Mono"
    fi
fi

if (( with_shell )); then
    zshrc="$HOME/.zshrc"
    line='[[ -f ~/.config/visor-hud/shield.zsh ]] && source ~/.config/visor-hud/shield.zsh  # visor-hud'
    if ! grep -qF '# visor-hud' "$zshrc" 2>/dev/null; then
        say "Adding the shield hook to ~/.zshrc"
        backup "$zshrc"
        printf '\n%s\n' "$line" >> "$zshrc"
    fi
fi

"$CMUX_BIN" reload-config >/dev/null 2>&1 && reloaded=1 || reloaded=0

echo
say "Visor HUD installed."
if (( reloaded )); then
    echo "  Open a new tab to load the shield hook."
else
    echo "  In cmux, run:  cmux reload-config   (or restart Ghostty), then open a new tab."
fi
echo "  Sidebar: right-click the sidebar button in cmux and pick visor-hud."
echo "  Tweak effects at the top of ~/.config/ghostty/shaders/visor-hud.glsl."
