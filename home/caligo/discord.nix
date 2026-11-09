{ pkgs, ... }:
{
  # Vesktop = Discord client with Vencord (mod loader) built in: proper
  # native Wayland screen-share, plus its own Settings > Themes tab for
  # custom CSS/QuickCSS if you want to restyle it further.
  home.packages = [ pkgs.vesktop ];
}
