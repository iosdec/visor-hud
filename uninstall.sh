#!/usr/bin/env bash
# Removes Visor HUD and puts your previous cmux theme back.
set -euo pipefail

GHOSTTY_DIR="$HOME/.config/ghostty"
STATE_DIR="$HOME/.config/visor-hud"
CMUX_THEME_FILE="$HOME/Library/Application Support/com.cmuxterm.app/config.ghostty"
CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
BEGIN="# >>> visor-hud >>>"
END="# <<< visor-hud <<<"

say() { printf '\033[38;2;63;208;255m▸\033[0m %s\n' "$*"; }

[[ -f "$GHOSTTY_DIR/config" ]] && sed -i '' "/^$BEGIN\$/,/^$END\$/d" "$GHOSTTY_DIR/config"
[[ -f "$HOME/.zshrc" ]] && sed -i '' '/# visor-hud$/d' "$HOME/.zshrc"

if [[ -f "$CMUX_THEME_FILE" && -f "$STATE_DIR/previous-cmux-theme" ]]; then
    previous="$(cat "$STATE_DIR/previous-cmux-theme")"
    if [[ -n "$previous" ]]; then
        escaped="$(printf '%s' "$previous" | sed 's/[&|]/\\&/g')"
        sed -i '' "s|^theme = .*Visor.*|$escaped|" "$CMUX_THEME_FILE"
    else
        sed -i '' '/^theme = .*Visor.*/d' "$CMUX_THEME_FILE"
    fi
fi

rm -f "$GHOSTTY_DIR/shaders/visor-hud.glsl" "$GHOSTTY_DIR/themes/Visor" "$HOME/.config/cmux/sidebars/visor-hud.swift"
rm -rf "$STATE_DIR" "$HOME/.local/share/visor-hud"

"$CMUX_BIN" reload-config >/dev/null 2>&1 || true
say "Visor HUD removed. Backups made during install (*.visor-backup-*) were left in place."
echo "  Open a new tab, or run: cmux reload-config"
