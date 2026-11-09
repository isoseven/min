{
  pkgs,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  home.packages = [
    # Browser
    inputs.zen-browser.packages.${system}.default

    # Image viewer
    pkgs.nomacs

    # Video player
    pkgs.vlc
  ];
}
