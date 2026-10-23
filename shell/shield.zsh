# Visor HUD per-pane shield for cmux/Ghostty (read by ~/.config/ghostty/shaders/visor-hud.glsl).
#
# Shield level = git health of this pane's folder (full when clean, lower with each
# changed file, critical on merge conflicts, full outside a repo). A failed command is
# a hit: red flash, a drop, then a gold recharge back to the git level.
#
# The value travels to the shader through palette colour 255 (OSC 4):
#   red   = shield level 0..255
#   green = 0 normal, 128 recharging, 255 hit
#   blue  = 1, a marker so the shader knows the hook is active
# install.sh sources this from ~/.zshrc. Remove that line to turn it off.

[[ -o interactive && -t 1 ]] || return 0

typeset -g _visor_ran=0 _visor_fails=0 _visor_job=0
typeset -g _visor_level=255

_visor_emit() { # level(0-255) mode(0|128|255)
    printf '\e]4;255;rgb:%02x/%02x/01\e\\' "$1" "$2" > /dev/tty 2>/dev/null
}

_visor_git_level() {
    local out
    out=$(GIT_OPTIONAL_LOCKS=0 command git status --porcelain=v1 --untracked-files=normal 2>/dev/null) || { print 255; return; }
    [[ -z $out ]] && { print 255; return; }
    local -a lines=("${(@f)out}")
    if (( ${#${(M)lines:#(DD|AU|UD|UA|DU|AA|UU) *}} )); then
        print 30; return            # merge conflicts: critical
    fi
    local n=${#lines}
    (( n > 15 )) && n=15
    print $(( 255 - n * 170 / 15 ))  # 15+ changed files bottoms out at ~33%
}

_visor_preexec() { _visor_ran=1 }

_visor_precmd() {
    local ec=$?
    local ran=$_visor_ran
    _visor_ran=0
    # A new hit or refresh replaces any animation still playing.
    (( _visor_job )) && kill $_visor_job 2>/dev/null

    local hit=0
    if (( ran )); then
        if (( ec != 0 && ec != 130 && ec != 146 && ec != 148 )); then
            (( _visor_fails++ )); hit=1        # 130/146/148 = Ctrl-C / suspend, not damage
        else
            _visor_fails=0
        fi
    fi

    {
        local target=$(_visor_git_level)
        if (( hit )); then
            local dmg=$(( 80 * (_visor_fails > 3 ? 3 : _visor_fails) ))
            local low=$(( target - dmg ))
            (( low < 8 )) && low=8
            _visor_emit $low 255
            sleep 0.35
            local i lvl
            for i in {1..12}; do
                lvl=$(( low + (target - low) * i / 12 ))
                _visor_emit $lvl 128
                sleep 0.08
            done
        fi
        _visor_emit $target 0
    } &!
    _visor_job=$!
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _visor_preexec
# Run first so $? is still the command's exit status.
precmd_functions=(_visor_precmd ${precmd_functions:#_visor_precmd})
