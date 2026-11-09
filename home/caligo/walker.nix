{ config, pkgs, ... }:

{
  # Walker's home-manager module (walker.homeManagerModules.default, wired
  # in via flake.nix + home.nix) auto-enables its required backend daemon,
  # elephant, which implements the actual search providers (desktop apps,
  # calculator, files, ...) — walker itself is just the GTK4 frontend. No
  # separate elephant.nix needed.
  programs.walker = {
    enable = true;

    # Keeps a background instance alive (like Wayle's own systemd service)
    # so opening the launcher is instant instead of a cold process start
    # every time — this is what hyprland.nix's `menu = "walker";` and the
    # $mod+R/Super_L binds assume is running.
    runAsService = true;

    # Left at Walker's own shipped defaults otherwise, to avoid guessing at
    # its full config.toml shape and silently misconfiguring a provider.
    config = {
      theme = "custom";

      providers.empty = [ "desktopapplications" ];
    };

    # @import pulls in wallpaper-shader.nix's generated walker-colors.css
    # (same `source`d-file trick as Hyprland's hypr-colors.conf), so colors
    # below follow whichever theme is active via `apply-theme`. This file's
    # STYLE STRUCTURE is still Nix-managed and needs a rebuild to change;
    # only the CSS variables it references update live.
    themes.custom.style = ''
      @import "${config.home.homeDirectory}/.cache/theme/walker-colors.css";

      /* No font-family/font-size here — falls back to the system font
         (gtk.nix's Iosevka SKYC) and default size instead of forcing one
         size onto both primary and secondary text. */
      * { all: unset; color: var(--fg); }
      scrollbar { opacity: 0; }
      .normal-icons { -gtk-icon-size: 16px; } .large-icons { -gtk-icon-size: 32px; }

      .box-wrapper {
        /* 0.94 = very slightly transparent, not a see-through panel. */
        background: alpha(var(--bg), 0.94);
        padding: 15px;
        /* 2px: --border resolves to the theme's accent color, but a
           hairline 1px border can anti-alias away to nothing under
           fractional display scaling. */
        border: 2px solid var(--border);
        border-radius: 0px;
      }
      .search-container {
        padding: 8px 12px;
        margin-bottom: 10px;
        border: 2px solid var(--border);
        /* Same diagonal caution-stripe pattern as the active workspace /
           bar sections, at low alpha so it reads as texture not highlight. */
        background-image: repeating-linear-gradient(
          -45deg,
          var(--stripe-color) 0, var(--stripe-color) 6px,
          transparent 6px, transparent 12px
        );
      }
      /* Scoped exception to the base `*` rule above — typed search text
         goes back to the muted tone. */
      .input { color: var(--fg-muted); }
      child:selected .item-box {
        /* Same treatment as .workspace.active in Wayle's SCSS: two-tone
           diagonal stripe using this item's accent color plus a lightened
           shade of it, instead of a flat fill. */
        background: repeating-linear-gradient(
          -45deg,
          var(--accent) 0, var(--accent) 6px,
          shade(var(--accent), 1.3) 6px, shade(var(--accent), 1.3) 12px
        );
      }
      child:selected .item-box * { color: var(--accent-contrast); }
      .item-box { padding-left: 14px; padding-right: 14px; min-height: 52px; }
      .item-quick-activation {
        font-size: 11px;
        color: var(--fg-muted);
        margin-left: 10px;
      }
      .item-text-box { padding: 8px 0; min-height: 36px; }
      .item-subtext { font-size: 11px; }
      .item-image { margin-right: 14px; }
    '';
  };
}
