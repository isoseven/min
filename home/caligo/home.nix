{
  config,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.spicetify-nix.homeManagerModules.default
    inputs.walker.homeManagerModules.default

    ./theme.nix
    ./gtk.nix
    ./hyprland.nix
    ./wallpaper-shader.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./hyprpaper.nix
    ./walker.nix
    ./commands.nix
    ./alacritty.nix
    ./zsh.nix
    ./dunst.nix
    ./thunar.nix
    ./wayle.nix
    ./utils.nix
    ./scripts.nix
    ./clipboard.nix
    ./calendar.nix
    ./mail.nix
    ./desktop-overrides.nix
    ./nightmode.nix
    ./groups.nix
    ./floating.nix
    ./app-window-size.nix
    ./snap.nix
    ./focus.nix
    ./games.nix
    ./dev.nix
    ./osiris.nix

    # Apps (2026-09 batch)
    ./apps.nix
    ./spotify.nix
    ./discord.nix
    ./osd.nix
    ./screenshot.nix
    ./overview.nix
  ];

  # Already matches users.users.caligo in hosts/nixos/configuration.nix.
  home.username = "caligo";
  home.homeDirectory = "/home/caligo";

  # Don't bump this on upgrades — it's the format version of your home-manager
  # state, not a "target this NixOS release" knob.
  home.stateVersion = "25.05";

  # Let home-manager manage itself.
  programs.home-manager.enable = true;

  # XDG user directories (Desktop, Downloads, Pictures, etc.)
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = true;
  };
}
