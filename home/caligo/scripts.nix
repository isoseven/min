{ pkgs, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.numpy ]);

  perlin-art = pkgs.writeScriptBin "perlin-art" ''
    #!${pythonEnv}/bin/python3
    """Animated Perlin-noise generative art for the terminal.

    Classic 2D Perlin noise implemented from scratch (no noise libraries),
    vectorized with numpy, rendered as a density-ramped ASCII grid colored
    along a configurable xterm-256 palette. Scrolls smoothly over time.
    Ctrl+C to quit. Run `perlin-art --help` for all options.
    """
    import argparse
    import numpy as np
    import shutil, sys, time

    PALETTES = {
        "mauve": [17, 60, 61, 97, 98, 141, 183, 219],  # dark blue -> mauve/lavender (default)
        "green": [22, 28, 34, 40, 46, 82, 118, 154],
        "fire": [52, 88, 124, 160, 196, 202, 208, 214],
        "mono": [235, 239, 243, 247, 251, 255, 255, 255],
        "ocean": [17, 18, 24, 30, 37, 44, 51, 87],
    }
    DEFAULT_RAMP = " .:-=+*#%@"

    rng = np.random.default_rng()
    _p = rng.permutation(256)
    PERM = np.tile(_p, 2)  # length 512, avoids index overflow below


    def parse_colors(spec):
        if spec == "random":
            spec = str(rng.choice(list(PALETTES.keys())))
        if spec in PALETTES:
            return PALETTES[spec]
        try:
            codes = [int(c.strip()) for c in spec.split(",") if c.strip() != ""]
            if codes:
                return codes
        except ValueError:
            pass
        sys.stderr.write(
            f"perlin-art: --colors {spec!r} isn't a known palette ({', '.join(PALETTES)}) "
            "or a comma-separated list of xterm-256 codes; falling back to 'mauve'\n"
        )
        return PALETTES["mauve"]


    def parse_args():
        p = argparse.ArgumentParser(
            prog="perlin-art",
            description="Animated Perlin-noise generative art for the terminal.",
        )
        p.add_argument(
            "--scale", type=float, default=10.0,
            help="Noise zoom level: higher = smoother/more zoomed-in, lower = busier/noisier (default: 10)",
        )
        p.add_argument(
            "--speed", type=float, default=0.06,
            help="Horizontal scroll speed per frame (default: 0.06)",
        )
        p.add_argument(
            "--fps", type=float, default=12.5,
            help="Target frames per second (default: 12.5)",
        )
        p.add_argument(
            "--colors", default="random", metavar="PALETTE|LIST",
            help=(
                "Palette name (" + ", ".join(PALETTES) + "), 'random' to pick one "
                "of those each run (default), or a comma-separated list of "
                "xterm-256 color codes, e.g. '17,60,61,97'"
            ),
        )
        p.add_argument(
            "--ramp", default=DEFAULT_RAMP,
            # argparse does %-style substitution on help text internally, so a
            # literal '%' in the ramp (it has one: '#%@') has to be escaped to
            # '%%' or this crashes on *every* invocation, not just --help.
            help="Density ramp string, light to dense (default: %s)" % repr(DEFAULT_RAMP).replace("%", "%%"),
        )
        return p.parse_args()


    def fade(t):
        return t * t * t * (t * (t * 6 - 15) + 10)


    def lerp(t, a, b):
        return a + t * (b - a)


    def grad(h, x, y):
        h = h & 3
        u = np.where(h < 2, x, y)
        v = np.where(h < 2, y, x)
        return np.where((h & 1) == 0, u, -u) + np.where((h & 2) == 0, v, -v)


    def perlin2d(x, y):
        xi = np.floor(x).astype(np.int64) & 255
        yi = np.floor(y).astype(np.int64) & 255
        xf = x - np.floor(x)
        yf = y - np.floor(y)
        u = fade(xf)
        v = fade(yf)

        aa = PERM[PERM[xi] + yi]
        ab = PERM[PERM[xi] + yi + 1]
        ba = PERM[PERM[xi + 1] + yi]
        bb = PERM[PERM[xi + 1] + yi + 1]

        x1 = lerp(u, grad(aa, xf, yf), grad(ba, xf - 1, yf))
        x2 = lerp(u, grad(ab, xf, yf - 1), grad(bb, xf - 1, yf - 1))
        return lerp(v, x1, x2)


    def render(width, height, t, scale, speed, colors, ramp):
        xs = np.linspace(0, width / scale, width) + t * speed
        ys = np.linspace(0, height / scale, height)
        xx, yy = np.meshgrid(xs, ys)
        n = perlin2d(xx, yy)
        n = (n - n.min()) / (n.max() - n.min() + 1e-9)

        ramp_idx = np.clip((n * (len(ramp) - 1)).astype(int), 0, len(ramp) - 1)
        color_idx = np.clip((n * (len(colors) - 1)).astype(int), 0, len(colors) - 1)

        lines = []
        for row in range(height):
            parts = []
            prev_color = None
            for col in range(width):
                c = colors[color_idx[row, col]]
                ch = ramp[ramp_idx[row, col]]
                if c != prev_color:
                    parts.append(f"\x1b[38;5;{c}m{ch}")
                    prev_color = c
                else:
                    parts.append(ch)
            lines.append("".join(parts))
        return "\x1b[0m\n".join(lines)


    def main():
        args = parse_args()
        colors = parse_colors(args.colors)
        ramp = args.ramp if args.ramp else DEFAULT_RAMP
        delay = 1.0 / args.fps if args.fps > 0 else 0.08

        t = 0.0
        sys.stdout.write("\x1b[?25l")  # hide cursor
        sys.stdout.write("\x1b[2J")  # clear once
        try:
            while True:
                size = shutil.get_terminal_size(fallback=(80, 24))
                width, height = size.columns, max(size.lines - 1, 1)
                frame = render(width, height, t, args.scale, args.speed, colors, ramp)
                sys.stdout.write("\x1b[H")  # cursor home, overwrite in place
                sys.stdout.write(frame)
                sys.stdout.write("\x1b[0m")
                sys.stdout.flush()
                t += 1.0
                time.sleep(delay)
        except KeyboardInterrupt:
            pass
        finally:
            sys.stdout.write("\x1b[0m\x1b[?25h\n")
            sys.stdout.flush()


    if __name__ == "__main__":
        main()
  '';

  # Thin wrapper around pkgs.pipes' `pipes.sh` binary with defaults tuned for
  # a fuller/faster generative-art look: 8 concurrent pipes, randomized
  # starting positions/directions, and keeping color+type when a pipe
  # crosses the screen edge instead of resetting. Ctrl+C to quit.
  pipe-art = pkgs.writeShellScriptBin "pipe-art" ''
    exec ${pkgs.pipes}/bin/pipes.sh -p 8 -R -K -f 70 "$@"
  '';

  # Quick terminal battery check via upower (services.upower.enable is set
  # in configuration.nix — that's the actual daemon this talks to over
  # D-Bus; this is just a friendlier CLI wrapper around it).
  battery = pkgs.writeShellScriptBin "battery" ''
    set -u
    upower="${pkgs.upower}/bin/upower"
    dev=$("$upower" -e | grep -m1 'BAT')
    if [ -z "$dev" ]; then
      echo "No battery device found (desktop, or upower isn't seeing it)."
      exit 1
    fi
    "$upower" -i "$dev" | grep -E "state|percentage|time to (empty|full)" | sed 's/^ *//'
  '';

  # Launches the workspace-1 "showcase" — four *real* dwindle-tiled kitty
  # windows (not floating), built by opening them one at a time and
  # steering dwindle's split direction + ratio right after each one maps:
  #
  #   fastfetch (top-left, 45w/70h)     | perlin-art #1 (top-right, 55w/30h)
  #   perlin-art #2 (bot-left, 45w/30h) | btop (bot-right, 55w/70h)
  #
  # `layoutmsg preselect <l|r|u|d>` forces which side the *next* opened
  # window goes on. `splitratio <delta>` ADDS that delta to the current
  # split ratio rather than setting an absolute value — the deltas below
  # were found by hand-testing against this exact setup, each applied once
  # right after its split is freshly created from the default 50/50.
  #
  # Safe to re-run by hand any time; just (re)spawns the four windows.
  workspace1-showcase = pkgs.writeShellScriptBin "workspace1-showcase" ''
    set -u
    kitty="${pkgs.kitty}/bin/kitty"
    hyprctl="${pkgs.hyprland}/bin/hyprctl"

    wait_for_class() {
      for _ in $(seq 1 50); do
        "$hyprctl" clients -j | grep -q "\"class\": \"$1\"" && return 0
        sleep 0.1
      done
    }

    focus_class() {
      "$hyprctl" dispatch focuswindow "class:^($1)\$" >/dev/null
    }

    "$kitty" --class showcase-fastfetch -e sh -c 'fastfetch; exec zsh' &
    wait_for_class showcase-fastfetch
    focus_class showcase-fastfetch
    "$hyprctl" dispatch layoutmsg preselect r

    "$kitty" --class showcase-perlin -e ${perlin-art}/bin/perlin-art &
    wait_for_class showcase-perlin
    sleep 0.3
    "$hyprctl" dispatch layoutmsg "splitratio -0.1" # fastfetch(left) 45% / perlin+btop's column(right) 55%

    focus_class showcase-fastfetch
    "$hyprctl" dispatch layoutmsg preselect d

    "$kitty" --class showcase-perlin2 -e ${perlin-art}/bin/perlin-art &
    wait_for_class showcase-perlin2
    sleep 0.3
    "$hyprctl" dispatch layoutmsg "splitratio 0.1" # fastfetch(top) 70% / perlin2(bottom) 30%

    focus_class showcase-perlin
    "$hyprctl" dispatch layoutmsg preselect d

    "$kitty" --class showcase-btop -e ${pkgs.btop}/bin/btop &
    wait_for_class showcase-btop
    sleep 0.3
    "$hyprctl" dispatch layoutmsg "splitratio -0.4" # perlin(top) 30% / btop(bottom) 70%
  '';
in
{
  # Logo: inverted (white symbol, transparent background) crescent/star mark,
  # rendered as a real image via kitty's graphics protocol rather than ASCII.
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        type = "kitty";
        source = ./assets/fetch-logo.png;
        width = 28; # height auto-scales to preserve aspect ratio
      };
      display.separator = " -> ";
      modules = [
        "title"
        "separator"
        "os"
        "kernel"
        "uptime"
        "packages"
        "shell"
        "wm"
        "terminal"
        "cpu"
        "gpu"
        "memory"
        "disk"
        "localip"
        "break"
        "colors"
      ];
    };
  };

  home.packages = [
    perlin-art
    pipe-art
    battery
    workspace1-showcase
    pkgs.asciiquarium-transparent # installs the `asciiquarium` binary — no longer in the showcase, still available standalone
    pkgs.notcurses # installs `notcurses-demo` plus a few extras (nctetris, ncneofetch, ncplayer, ncls, tfman)
  ];
}
