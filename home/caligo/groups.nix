{ ... }:

{
  wayland.windowManager.hyprland.settings.bind = [
    "$mod, G, togglegroup,"
    "$mod SHIFT, G, moveoutofgroup,"
    "$mod, bracketright, changegroupactive, f"
    "$mod, bracketleft, changegroupactive, b"
    "$mod ALT, left, moveintogroup, l"
    "$mod ALT, right, moveintogroup, r"
    "$mod ALT, up, moveintogroup, u"
    "$mod ALT, down, moveintogroup, d"
  ];
}
