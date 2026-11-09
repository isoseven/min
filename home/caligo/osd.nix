{ ... }:
{
  # On-screen popup for volume/mute/brightness/caps-lock changes.
  # hyprland.nix's media keybinds call swayosd-client so this actually
  # fires (see the `binde` block there).
  services.swayosd = {
    enable = true;
    topMargin = 0.9; # 0.0 = top of screen, 1.0 = bottom
  };
}
