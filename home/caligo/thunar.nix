{ pkgs, ... }:

{
  # Thunar itself + its system-level plugins/services (gvfs, tumbler) are
  # enabled in hosts/nixos/configuration.nix. This just adds a couple of
  # user-facing niceties.
  home.packages = with pkgs; [
    xfce.thunar
    xfce.thunar-archive-plugin
    xfce.thunar-volman
    file-roller # archive GUI, used by the archive plugin
  ];
}
