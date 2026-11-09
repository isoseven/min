{
  pkgs,
  inputs,
  lib,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  zenWithCodecs = pkgs.symlinkJoin {
    name = "zen-with-codecs";
    paths = [ inputs.zen-browser.packages.${system}.default ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for b in $out/bin/*; do
        wrapProgram "$b" \
          --prefix LD_LIBRARY_PATH : ${
            lib.makeLibraryPath [
              pkgs.ffmpeg
              (pkgs.ffmpeg_7 or pkgs.ffmpeg)
            ]
          } \
          --add-flags "-width 1400 -height 900"
      done
    '';
  };
in
{
  home.packages = [
    # Browser
    zenWithCodecs

    # AI assistant desktop app
    inputs.claude-desktop.packages.${system}.default

    # Code editor
    pkgs.vscode

    # Notes
    pkgs.obsidian

    # Office suite (Word/Excel/PowerPoint-compatible)
    pkgs.onlyoffice-desktopeditors

    # Photo viewer/manager - browses folders like a gallery, not just a
    # single-image viewer
    pkgs.nomacs

    # Media player
    pkgs.vlc

    # Mail client - picked over Thunderbird for a more modern look out of
    # the box; swap for pkgs.thunderbird here if you'd rather have that
    pkgs.mailspring

    # Digital painting
    pkgs.krita

    # Screen recording / streaming
    pkgs.obs-studio

    # Digital audio workstation
    pkgs.ardour
  ];
}
