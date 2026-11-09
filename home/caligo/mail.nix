{ pkgs, ... }:

{
  # Geary — GNOME's own mail client. Picked over Thunderbird for this
  # specifically because you wanted mail kept separate from calendar/todo:
  # minimal, GTK-native, no built-in calendar/tasks bloat, and it's the one
  # most commonly described as the "clean/aesthetic" option in this space.
  # Account setup happens inside Geary itself on first launch (also usable
  # through GNOME Online Accounts if you add a Google account there for
  # calendar.nix — Geary will offer to use that same account for mail too,
  # or you can add IMAP/SMTP accounts directly, including a plain Gmail
  # login with an app password if you'd rather not route mail through GOA).
  home.packages = [ pkgs.geary ];
}
