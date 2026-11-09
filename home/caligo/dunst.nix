{ ... }:

{
  # Disabled: Wayle's own "notifications" module (wayle.nix) owns
  # org.freedesktop.Notifications on the D-Bus instead. Running both trips a
  # hard home-manager assertion ("Only one notification daemon can be
  # enabled at once"). Settings below are left in place in case you ever
  # want to switch back — flip `enable` to `true` and disable Wayle's
  # notifications module.
  services.dunst = {
    enable = false;
    settings = {
      global = {
        width = 320;
        height = 100;
        origin = "top-right";
        offset = "12x12";
        gap_size = 8;
        corner_radius = 10;
        frame_width = 2;
        font = "Iosevka SKYC 10";
        markup = "full";
        format = "<b>%s</b>\\n%b";
        vertical_alignment = "center";
        show_age_threshold = 60;
        ignore_newline = false;
        stack_duplicates = true;
        show_indicators = true;
        icon_position = "left";
        max_icon_size = 48;
        sort = true;
        idle_threshold = 120;
      };

      urgency_low.timeout = 4;
      urgency_normal.timeout = 6;
      urgency_critical.timeout = 0; # stays until dismissed
    };
  };
}
