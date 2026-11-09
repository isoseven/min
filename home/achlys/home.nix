{
  config,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.walker.homeManagerModules.default

    # Shared desktop infra - same modules caligo's profile uses, reused
    # directly from ../caligo/ rather than duplicated.
    ../caligo/theme.nix
    ../caligo/gtk.nix
    ../caligo/hyprland.nix
    ../caligo/wallpaper-shader.nix
    ../caligo/hyprlock.nix
    ../caligo/hypridle.nix
    ../caligo/hyprpaper.nix
    ../caligo/walker.nix
    ../caligo/commands.nix
    ../caligo/alacritty.nix
    ../caligo/zsh.nix
    ../caligo/dunst.nix
    ../caligo/thunar.nix
    ../caligo/wayle.nix
    ../caligo/utils.nix
    ../caligo/scripts.nix
    ../caligo/clipboard.nix
    ../caligo/desktop-overrides.nix
    ../caligo/nightmode.nix
    ../caligo/groups.nix
    ../caligo/floating.nix
    ../caligo/app-window-size.nix
    ../caligo/snap.nix
    ../caligo/focus.nix
    ../caligo/osd.nix
    ../caligo/screenshot.nix
    ../caligo/overview.nix
    ../caligo/discord.nix

    # Apps: just the basics (web browser, Discord above, image/video
    # viewer). Steam comes from configuration.nix's system-wide
    # programs.steam.enable, already on PATH for every user - nothing
    # needed here for it.
    ./apps.nix
  ];

  # Already matches users.users.achlys in hosts/nixos/configuration.nix.
  home.username = "achlys";
  home.homeDirectory = "/home/achlys";

  # Same format-version pin as caligo's profile - see the note there.
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = true;
  };
}
