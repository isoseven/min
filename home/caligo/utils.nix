{ pkgs, ... }:

{
  # services.cliphist.enable removed — clipboard history is now CopyQ
  # (clipboard.nix), which manages its own history independently.

  home.packages = with pkgs; [
    grim # screenshot capture
    slurp # region selector, used together with grim
    swappy # quick screenshot annotate/save tool (optional: `grim -g "$(slurp)" - | swappy -f -`)

    wl-clipboard # wl-copy / wl-paste, still used by the screenshot binds

    pavucontrol # GUI volume mixer, in case you need more than the media keys
    networkmanagerapplet # nm-applet, a tray icon for NetworkManager

    btop # process/resource monitor
    baobab
    ncdu
    kitty # secondary terminal, used for the workspace-1 fastfetch showcase later
  ];
}
