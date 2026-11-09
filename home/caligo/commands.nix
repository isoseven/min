{ pkgs, ... }:

let
  # Several of these wrap the same script body under multiple names (one
  # real script, several `writeShellScriptBin` wrappers) so each alias is a
  # genuinely separate command on $PATH — Walker's `>` runner finds any of
  # them by name and runs it with arguments, like a normal shell command.
  #
  # A few names are deliberately DROPPED rather than shadowed:
  # `sleep`, `shutdown`, `halt`, `poweroff`, `reboot`, and `reset` are all
  # real system/coreutils binaries already relied on elsewhere (this very
  # flake's wallpaper-shader.nix calls plain `sleep` in its own launch
  # script) — a home-manager package on $PATH with one of those exact
  # names would silently replace the real one for every shell on the
  # system, not just inside Walker. Each dropped name is called out below
  # with what's kept instead.

  # --- Sleep / suspend -----------------------------------------------------
  # `sleep` itself dropped (see above). `nap` is the primary name;
  # `standby`/`slp` are aliases — all three just suspend.
  sleepScript = ''
    exec systemctl suspend
  '';
  nap = pkgs.writeShellScriptBin "nap" sleepScript;
  standby = pkgs.writeShellScriptBin "standby" sleepScript;
  slp = pkgs.writeShellScriptBin "slp" sleepScript;

  # --- Shutdown --------------------------------------------------------------
  # `shutdown`/`halt`/`poweroff` dropped (all real systemd-provided
  # binaries). `po` is the primary name — bare `po` now powers off
  # immediately (no more built-in 5s grace period); `po 2h15m` / `po 10s`
  # (or `po 2h 15m` as separate words — both are accepted) still parses
  # any combination of d/h/m/s tokens and schedules the poweroff that far
  # out when you actually want a delay.
  # (Also dropped `sd` as a second alias: it collides with a real,
  # moderately popular find-and-replace CLI some people install — not
  # worth it for a two-letter shortcut.)
  po = pkgs.writeShellScriptBin "po" ''
    set -euo pipefail
    spec="$(printf '%s' "$*" | tr -d '[:space:]')"
    secs=0
    if [ -n "$spec" ]; then
      while [[ "$spec" =~ ([0-9]+)([dhms]) ]]; do
        n="''${BASH_REMATCH[1]}"
        u="''${BASH_REMATCH[2]}"
        case "$u" in
          d) secs=$((secs + n * 86400)) ;;
          h) secs=$((secs + n * 3600)) ;;
          m) secs=$((secs + n * 60)) ;;
          s) secs=$((secs + n)) ;;
        esac
        spec="''${spec/"''${BASH_REMATCH[0]}"/}"
      done
    fi
    if [ "$secs" -gt 0 ]; then
      notify-send "Shutdown scheduled" "Powering off in ''${secs}s" 2>/dev/null || true
      setsid bash -c "sleep ''${secs} && systemctl poweroff" >/dev/null 2>&1 < /dev/null &
      disown
    else
      exec systemctl poweroff
    fi
  '';

  # --- Restart -----------------------------------------------------------
  # `reboot` and `reset` dropped — `reset` especially is the everyday
  # terminal-recovery command, not something to gamble on shadowing.
  # `restart` is the primary name; `rs`/`rb` are aliases.
  restartScript = ''
    exec systemctl reboot
  '';
  restart = pkgs.writeShellScriptBin "restart" restartScript;
  rs = pkgs.writeShellScriptBin "rs" restartScript;
  rb = pkgs.writeShellScriptBin "rb" restartScript;

  windowsScript = ''
    exec systemctl reboot --boot-loader-entry=auto-windows
  '';
  win = pkgs.writeShellScriptBin "win" windowsScript;
  to_windows = pkgs.writeShellScriptBin "to_windows" windowsScript;

  # --- Volume --------------------------------------------------------------
  # Dropped the bare single-letter `v` alias — a one-character command on
  # $PATH is too easy to collide with something you install later, or to
  # fat-finger by accident. `volume` is primary; `vol`/`audio`/`sound` are
  # aliases. `volume 50` sets level (0-100); `volume 50 true` sets level
  # and mutes; `volume` alone prints the current level.
  volumeScript = ''
    set -euo pipefail
    sink="@DEFAULT_AUDIO_SINK@"
    level="''${1:-}"
    mute="''${2:-}"

    if [ -n "$level" ]; then
      wpctl set-volume "$sink" "''${level}%"
    fi

    case "$mute" in
      true | 1 | on) wpctl set-mute "$sink" 1 ;;
      false | 0 | off) wpctl set-mute "$sink" 0 ;;
    esac

    if [ -z "$level" ] && [ -z "$mute" ]; then
      wpctl get-volume "$sink"
    fi
  '';
  volume = pkgs.writeShellScriptBin "volume" volumeScript;
  vol = pkgs.writeShellScriptBin "vol" volumeScript;
  audio = pkgs.writeShellScriptBin "audio" volumeScript;
  sound = pkgs.writeShellScriptBin "sound" volumeScript;

  # --- Bluetooth -----------------------------------------------------------
  # Bare `bluetooth` opens the blueman GUI (you're already running its
  # tray applet via hyprland.nix's exec-once, so the package is already
  # on the system). `bluetooth on` / `bluetooth off` toggles the radio
  # directly via bluetoothctl. `blue`/`blt`/`wireless` are aliases.
  bluetoothScript = ''
    set -euo pipefail
    arg="''${1:-}"
    case "$arg" in
      on | true | 1) bluetoothctl power on ;;
      off | false | 0) bluetoothctl power off ;;
      "") blueman-manager & disown ;;
      *)
        echo "usage: bluetooth [on|off]" >&2
        exit 1
        ;;
    esac
  '';
  bluetooth = pkgs.writeShellScriptBin "bluetooth" bluetoothScript;
  blue = pkgs.writeShellScriptBin "blue" bluetoothScript;
  blt = pkgs.writeShellScriptBin "blt" bluetoothScript;
  wireless = pkgs.writeShellScriptBin "wireless" bluetoothScript;

  atr = pkgs.writeShellScriptBin "atr" ''
    exec apply-theme random "$@"
  '';
in
{
  # Desktop entries purely for discoverability in Walker's app search — the
  # Comment field shows as subtext under the name. Selecting one runs the
  # bare command with no arguments; for the argumented forms shown in the
  # hint (e.g. "volume 50"), type them through the `>` runner instead.
  xdg.desktopEntries = {
    nap = {
      name = "Sleep";
      comment = "Suspend now: nap";
      exec = "nap";
      icon = "system-suspend";
      terminal = false;
      categories = [ "System" ];
    };
    po = {
      name = "Power Off";
      comment = "Shut down now: po — or delay it: po 10s, po 2h15m";
      exec = "po";
      icon = "system-shutdown";
      terminal = false;
      categories = [ "System" ];
    };
    win = {
      name = "Restart to Windows";
      comment = "Reboot straight into Windows once: win";
      exec = "win";
      icon = "system-reboot";
      terminal = false;
      categories = [ "System" ];
    };
    restart = {
      name = "Restart";
      comment = "Reboot: restart";
      exec = "restart";
      icon = "system-reboot";
      terminal = false;
      categories = [ "System" ];
    };
    volume = {
      name = "Volume";
      comment = "Set volume: volume <0-100> [mute] — bare shows the current level";
      exec = "volume";
      icon = "audio-volume-high";
      terminal = false;
      categories = [ "System" ];
    };
    bluetooth = {
      name = "Bluetooth";
      comment = "bluetooth [on|off] — bare opens the Bluetooth manager";
      exec = "bluetooth";
      icon = "bluetooth";
      terminal = false;
      categories = [ "System" ];
    };
  };

  home.packages = [
    nap
    standby
    slp
    po
    restart
    rs
    rb
    win
    to_windows
    volume
    vol
    audio
    sound
    bluetooth
    blue
    blt
    wireless
    atr
    pkgs.bluez # bluetoothctl — harmless if hardware.bluetooth.enable already pulls this in system-wide
  ];
}
