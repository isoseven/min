{ pkgs, ... }:

let
  warm = 4000;
  start = "20:00";
  end = "07:00";

  night = pkgs.writeShellScriptBin "night" ''
    state="''${XDG_CACHE_HOME:-$HOME/.cache}/nightmode"
    mkdir -p "$(dirname "$state")"
    hctl=${pkgs.hyprland}/bin/hyprctl

    on() {
      "$hctl" hyprsunset temperature ${toString warm} >/dev/null && echo on > "$state"
    }
    off() {
      "$hctl" hyprsunset identity >/dev/null && echo off > "$state"
    }
    scheduled() {
      now=$(date +%H%M)
      s=$(echo "${start}" | tr -d :)
      e=$(echo "${end}" | tr -d :)
      if [ "$now" -ge "$s" ] || [ "$now" -lt "$e" ]; then echo on; else echo off; fi
    }

    case "''${1:-toggle}" in
      on) on ;;
      off) off ;;
      auto) [ "$(scheduled)" = on ] && on || off ;;
      toggle)
        if [ "$(cat "$state" 2>/dev/null)" = on ]; then off; else on; fi
        ;;
      *) echo "usage: night [on|off|auto|toggle]" >&2; exit 1 ;;
    esac
  '';
in
{
  home.packages = [ night ];

  services.hyprsunset = {
    enable = true;
    settings.profile = [
      {
        time = end;
        identity = true;
      }
      {
        time = start;
        temperature = warm;
      }
    ];
  };

  systemd.user.services.nightmode-auto = {
    Unit = {
      Description = "Apply scheduled night mode state at login";
      After = [ "hyprsunset.service" ];
      Requires = [ "hyprsunset.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      ExecStart = "${night}/bin/night auto";
    };
    Install.WantedBy = [ "hyprsunset.service" ];
  };

  wayland.windowManager.hyprland.settings.bind = [ "$mod SHIFT, N, exec, night" ];

  xdg.desktopEntries.night = {
    name = "Night Mode";
    comment = "Toggle warm screen: night — or night on, night off, night auto";
    exec = "night";
    icon = "weather-clear-night";
    terminal = false;
    categories = [ "System" ];
  };
}
