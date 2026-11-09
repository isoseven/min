{ pkgs, ... }:

{
  # GNOME Calendar + Planify.
  #
  # Planify, not GNOME To Do — pkgs.gnome-todo no longer exists in nixpkgs
  # (unmaintained upstream, dropped). Planify is the actively-maintained
  # GTK4/libadwaita replacement.
  #
  # Trade-off worth knowing: Planify syncs via Todoist, Nextcloud, and CalDAV
  # accounts (configured inside the app), NOT Google Tasks — Google doesn't
  # expose Tasks over CalDAV, so there's no Google link for the to-do side.
  # The calendar side still gets full Google + Apple sync through GNOME
  # Calendar, both via GNOME Online Accounts (configuration.nix's
  # services.gnome.gnome-online-accounts) rather than their own separate
  # account setup:
  #
  #   Google:  Calendar > menu > Add Calendar > Google, sign in — a real GOA
  #            account.
  #   Apple:   iCloud calendars aren't a GOA provider upstream. Add them
  #            directly: Calendar > Add Calendar > CalDAV, server
  #            caldav.icloud.com, your Apple ID as the username, and an
  #            app-specific password (generate one at appleid.apple.com —
  #            your normal Apple ID password won't work here).
  home.packages = [
    pkgs.gnome-calendar
    pkgs.planify
  ];
}
