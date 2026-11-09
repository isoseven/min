{ pkgs, ... }:

{
  # CopyQ — replaces cliphist entirely (utils.nix used to enable
  # services.cliphist, and hyprland.nix used to watch the clipboard via
  # `wl-paste --watch cliphist store`, both removed). cliphist's history is
  # a plain text list piped through Walker's dmenu mode — no way to see an
  # image before pasting it. CopyQ has its own real GUI window with live
  # image thumbnails, search/filter, pinning, and editing built in, so this
  # is a genuine replacement of the whole workflow, not an add-on: CopyQ
  # runs its own server (exec-once "copyq" in hyprland.nix), watches the
  # clipboard on its own, and $mod+C now runs `copyq toggle` to show/hide
  # its window instead of piping through Walker.
  home.packages = [ pkgs.copyq ];
}
