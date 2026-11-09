{ pkgs, ... }:

let
  focus = pkgs.writeShellScriptBin "focus" ''
    set -u
    state="$HOME/.cache/focus/state"
    theme_state="$HOME/.cache/shaderbg/state"

    current=$(grep -m1 '^enabled=' "$state" 2>/dev/null | cut -d= -f2)
    current="''${current:-0}"

    case "''${1:-toggle}" in
      on) next=1 ;;
      off) next=0 ;;
      toggle) if [ "$current" = 1 ]; then next=0; else next=1; fi ;;
      *) echo "usage: focus [on|off|toggle]" >&2; exit 1 ;;
    esac

    if [ "$next" = "$current" ]; then
      exit 0
    fi

    mkdir -p "$(dirname "$state")"

    theme=$(grep -m1 '^theme=' "$theme_state" 2>/dev/null | cut -d= -f2)
    theme="''${theme:-catppuccin}"

    if [ "$next" = 1 ]; then
      shader=$(grep -m1 '^shader=' "$theme_state" 2>/dev/null | cut -d= -f2)
      shader="''${shader:-simplex}"
      echo "enabled=1" > "$state"
      echo "shader=$shader" >> "$state"
      hyprctl keyword animations:enabled 0 >/dev/null 2>&1 || true
      hyprctl keyword decoration:blur:enabled 0 >/dev/null 2>&1 || true
      apply-theme "$theme" black >/dev/null 2>&1 || true
    else
      shader=$(grep -m1 '^shader=' "$state" 2>/dev/null | cut -d= -f2)
      shader="''${shader:-simplex}"
      apply-theme "$theme" "$shader" >/dev/null 2>&1 || true
      hyprctl reload >/dev/null 2>&1 || true
      echo "enabled=0" > "$state"
    fi
  '';
in
{
  home.packages = [ focus ];

  wayland.windowManager.hyprland.settings.bind = [
    "$mod SHIFT, F, exec, focus toggle"
  ];
}
