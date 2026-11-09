{ ... }:

{
  services.hyprpaper = {
    enable = true;
    settings = {
      ipc = true;
      splash = false;

      # IMPORTANT: hyprpaper needs the image decoded into memory via `preload`
      # *before* a `wallpaper` line can reference it. Without this, the
      # monitor just shows Hyprland's plain background_color (see
      # misc.background_color in hyprland.nix) until hyprpaper catches up on
      # its own — that's almost certainly your "flashes for ~2 seconds"
      # symptom on login/desktop-open.
      preload = [
        "~/Pictures/wallpapers/wp_cloud.jpg"
      ];

      wallpaper = [
        {
          # blank monitor = fallback applied to any output without its own
          # explicit block, so this covers single- and multi-monitor setups
          monitor = "";
          path = "~/Pictures/wallpapers/wp_cloud.jpg";
          fit_mode = "cover";
        }
      ];
    };
  };

  # wp_cloud.jpg gets copied to ~/Pictures/wallpapers/ so hyprpaper (and
  # hyprlock, see hyprlock.nix) have something to show. Swap it out any
  # time — just keep the filename or update the paths in both files to
  # match. (mocha-gradient.png is still in ./wallpaper/ if you want to
  # switch back later.)
  home.file."Pictures/wallpapers/wp_cloud.jpg" = {
    source = ./wallpaper/wp_cloud.jpg;
  };
}
