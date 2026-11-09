{ pkgs, ... }:

let
  # Shows the focused window's app name in the bar only while it's
  # fullscreened, collapsing to nothing otherwise — no built-in Wayle option
  # does this, so it's a custom module (see modules.custom below).
  #
  # Watches Hyprland's event socket (.socket2.sock) rather than polling, and
  # re-asks `hyprctl activewindow -j` for the ground truth on every event
  # that could plausibly change fullscreen state, rather than parsing the
  # event payload itself — simpler and can't drift out of sync.
  wayle-fullscreen-watch = pkgs.writeShellScriptBin "wayle-fullscreen-watch" ''
    set -euo pipefail

    sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

    check() {
      local json fs class
      json=$(hyprctl activewindow -j 2>/dev/null || echo '{}')
      fs=$(printf '%s' "$json" | ${pkgs.jq}/bin/jq -r '.fullscreen // 0')
      class=$(printf '%s' "$json" | ${pkgs.jq}/bin/jq -r '.class // empty')
      if [ -n "$class" ] && [ "$fs" != "0" ] && [ "$fs" != "false" ] && [ "$fs" != "null" ]; then
        printf '{"text":"%s"}\n' "$class"
      else
        printf '{"text":""}\n'
      fi
    }

    # Emit current state immediately on startup, then again on every event
    # that could plausibly mean fullscreen state changed.
    check

    ${pkgs.socat}/bin/socat -U - UNIX-CONNECT:"$sock" | while IFS= read -r line; do
      case "$line" in
        fullscreen*|activewindow*|workspace*|closewindow*|movewindow*)
          check
          ;;
      esac
    done
  '';

  wayle-theme-name = pkgs.writeShellScriptBin "wayle-theme-name" ''
    state="$HOME/.cache/shaderbg/state"
    dir="$(dirname "$state")"
    mkdir -p "$dir"

    emit() {
      name=$(${pkgs.gnused}/bin/sed -n 's/^theme=//p' "$state" 2>/dev/null | head -n1 | tr '_' ' ')
      printf '{"text":"%s"}\n' "$name"
    }

    emit

    ${pkgs.inotify-tools}/bin/inotifywait -m -q -e close_write,moved_to,create --format '%f' "$dir" | while IFS= read -r f; do
      if [ "$f" = "state" ]; then
        emit
      fi
    done
  '';
in
{
  # Wayle: compositor-agnostic Rust shell (pkgs.wayle), the status bar.
  # services.wayle installs its own systemd user service that autostarts on
  # the Wayland session target — no exec-once entry needed in hyprland.nix.
  #
  # Config is TOML, written verbatim to ~/.config/wayle/config.toml from the
  # `settings` attrset below (arrays of attrsets become TOML's [[array-of-
  # table]] syntax, e.g. bar.layout).
  services.wayle = {
    enable = true;

    settings = {
      bar = {
        layout = [
          {
            monitor = "*";
            left = [
              "hyprland-workspaces"
              "custom-fullscreen-app"
            ];
            center = [ "clock" ];
            right = [
              "custom-theme-name"
              "network"
              "bluetooth"
              "volume"
              "battery"
              "systray"
              "notifications"
            ];
          }
        ];

        # Flat/minimal look, no pill-shaped colored boxes behind every
        # module: "basic" = icon + label with minimal background, versus the
        # default "block-prefix" (colored pill container per module).
        button-variant = "basic";
        button-group-background = "transparent";
        button-group-rounding = "none";
      };

      modules = {
        # e.g. "16:22 Wed 16 Sep"
        clock.format = "%H:%M %a %d %b";
        clock.right-click = "dropdown:media";
        brightness.right-click = "${pkgs.hyprland}/bin/hyprctl dispatch exec night";

        hyprland-workspaces = {
          # Off: shows an icon per running app per workspace by default,
          # which reads as clutter — plain numbers instead. No built-in Wayle
          # option shows an icon only when fullscreened (that's what
          # custom-fullscreen-app above is for instead).
          app-icons-show = false;

          # active-indicator = "underline" and container-bg-color =
          # "transparent" made the whole widget disappear instead of just
          # restyling it — left at defaults.

          # Distinct color per workspace (1-10, matching the $mod+[1-9,0]
          # binds in hyprland.nix).
          workspace-map = {
            "1" = {
              color = "#ff3b30";
            }; # red
            "2" = {
              color = "#ff9500";
            }; # orange
            "3" = {
              color = "#ffcc00";
            }; # yellow
            "4" = {
              color = "#34c759";
            }; # green
            "5" = {
              color = "#00c7be";
            }; # teal
            "6" = {
              color = "#007aff";
            }; # blue
            "7" = {
              color = "#5856d6";
            }; # indigo
            "8" = {
              color = "#af52de";
            }; # purple
            "9" = {
              color = "#ff2d55";
            }; # pink
            "10" = {
              color = "#ffd60a";
            }; # gold
          };
        };

        # fullscreen-app-name indicator (wayle-fullscreen-watch above). "id"
        # must match the name used in bar.layout's `left` array.
        # hide-if-empty makes it take zero space when nothing's fullscreened.
        custom = [
          {
            id = "fullscreen-app";
            command = "${wayle-fullscreen-watch}/bin/wayle-fullscreen-watch";
            mode = "watch";
            restart-policy = "on-exit";
            restart-interval-ms = 1000;
            format = "{{ text }}";
            hide-if-empty = true;
          }
          {
            id = "theme-name";
            command = "${wayle-theme-name}/bin/wayle-theme-name";
            left-click = "${pkgs.hyprland}/bin/hyprctl dispatch exec atr";
            right-click = "${pkgs.hyprland}/bin/hyprctl dispatch exec 'apply-theme mode toggle --notify'";
            middle-click = "${pkgs.hyprland}/bin/hyprctl dispatch exec 'apply-theme vivid toggle --notify'";
            mode = "watch";
            restart-policy = "on-exit";
            restart-interval-ms = 1000;
            format = "󰏘 {{ text }}";
            hide-if-empty = true;
          }
        ];
      };
    };
  };
}
