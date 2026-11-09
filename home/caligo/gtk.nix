{ pkgs, ... }:

let
  mikuCursors = import ./miku-cursor.nix { inherit pkgs; };
in
{
  # GTK3/GTK4 theming for default UI apps (Thunar, file pickers, etc), plus
  # cursor and system dark-mode.
  #
  # Base gtk.enable/gtk.font are set in theme.nix, NOT here — setting them
  # in both places is a hard "conflicting definitions" eval error.
  #
  # No base GTK theme package set here — GTK ships Adwaita by default, and
  # render-theme's generated gtk.css (wallpaper-shader.nix's
  # write_gtk_css(), written straight to ~/.config/gtk-{3,4}.0/gtk.css at
  # runtime) is what actually recolors GTK apps regardless of base theme.
  #
  # Icon theme: Colloid-Dark for the desktop session. The login screen
  # (regreet, configuration.nix) uses Papirus-Dark instead — the two are
  # independent surfaces, not synced.
  gtk.iconTheme = {
    package = pkgs.colloid-icon-theme;
    name = "Colloid-Dark";
  };

  # Deliberately NOT setting gtk.gtk3.extraCss / gtk.gtk4.extraCss — home
  # -manager's gtk module only writes xdg.configFile."gtk-{3,4}.0/gtk.css"
  # when extraCss is non-empty, so leaving both unset keeps those paths free
  # for render-theme (wallpaper-shader.nix) to write directly on every
  # `apply-theme` call instead of home-manager fighting it for the file.
  #
  # Cursor: Miku Hatsune, hand-converted from a Windows cursor pack (see
  # miku-cursor.nix + assets/cursors/miku-hatsune/). Not a nixpkgs package,
  # so `package` points at the local derivation instead of `pkgs.<name>`.
  home.pointerCursor = {
    enable = true;
    package = mikuCursors;
    name = "Miku-Hatsune";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
    hyprcursor.enable = true;
  };

  # System dark-mode preference (org.freedesktop.appearance color-scheme via
  # dconf) — respected by GTK4/libadwaita apps, Firefox, and most portal-
  # aware software. configuration.nix already has programs.dconf.enable =
  # true; at the system level for the dconf daemon to exist.
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-enable-primary-paste = false;
    };
  };
}
