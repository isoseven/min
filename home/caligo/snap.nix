{ pkgs, ... }:

let
  snapScript = pkgs.writers.writePython3Bin "snap-window" { flakeIgnore = [ "E501" ]; } ''
    import json
    import subprocess
    import sys


    def hypr(*args):
        return subprocess.run(
            ["${pkgs.hyprland}/bin/hyprctl", *args],
            capture_output=True, text=True, check=False,
        ).stdout


    def hypr_json(*args):
        try:
            return json.loads(hypr("-j", *args))
        except ValueError:
            return None


    def active_monitor():
        for mon in hypr_json("monitors") or []:
            if mon.get("focused"):
                return mon
        return None


    def work_area(mon):
        res = mon.get("reserved") or [0, 0, 0, 0]
        scale = mon.get("scale") or 1
        width = int(mon["width"] / scale)
        height = int(mon["height"] / scale)
        x = mon["x"] + res[0]
        y = mon["y"] + res[1]
        return x, y, width - res[0] - res[2], height - res[1] - res[3]


    def place(x, y, w, h):
        hypr("dispatch", "setfloating", "active")
        hypr("dispatch", "resizeactive", "exact", str(w), str(h))
        hypr("dispatch", "moveactive", "exact", str(x), str(y))


    def snap(where):
        mon = active_monitor()
        if not mon:
            return
        if where == "down":
            x, y, w, h = work_area(mon)
            gap = 8
            place(x + w // 4, y + h // 4, w // 2 - gap, h // 2 - gap)
            return
        hypr("dispatch", "settiled", "active")
        if where == "left":
            hypr("dispatch", "movewindow", "l")
        elif where == "right":
            hypr("dispatch", "movewindow", "r")
        elif where == "up":
            hypr("dispatch", "movewindow", "u")


    def snap_from_cursor():
        mon = active_monitor()
        if not mon:
            return
        pos = hypr_json("cursorpos")
        if not pos:
            return
        x, y, w, h = work_area(mon)
        edge = 12
        cx, cy = pos["x"], pos["y"]
        if cy <= y + edge:
            snap("up")
        elif cx <= x + edge:
            snap("left")
        elif cx >= x + w - edge:
            snap("right")


    if __name__ == "__main__":
        arg = sys.argv[1] if len(sys.argv) > 1 else ""
        if arg == "cursor":
            snap_from_cursor()
        elif arg in ("up", "down", "left", "right"):
            snap(arg)
        else:
            sys.stderr.write("usage: snap-window [up|down|left|right|cursor]\n")
            sys.exit(1)
  '';
in
{
  home.packages = [ snapScript ];

  wayland.windowManager.hyprland.settings = {
    bind = [
      "$mod CTRL, up, exec, snap-window up"
      "$mod CTRL, down, exec, snap-window down"
      "$mod CTRL, left, exec, snap-window left"
      "$mod CTRL, right, exec, snap-window right"
    ];

    bindr = [
      "$mod, mouse:272, exec, snap-window cursor"
    ];
  };
}
