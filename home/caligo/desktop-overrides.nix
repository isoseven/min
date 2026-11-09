{ config, lib, ... }:

{
  # Generic mechanism for relabeling/re-iconing/hiding specific installed
  # .desktop files, without touching the packages that ship them. Works by
  # copying the REAL file into ~/.local/share/applications (which every
  # XDG-aware launcher, Walker included, checks first — confirmed against
  # Walker's own maintainer: a ~/.local/share/applications copy with
  # Hidden=true is the documented way to hide an entry, and the same
  # override-by-copy mechanism applies to relabeling) and patching only the
  # named fields. Exec=/TryExec=/everything else in the file is left
  # exactly as the real package wrote it, so the app still launches
  # correctly — this only changes how it's labeled/found in the launcher.
  #
  # Runs on every activation (not just once) so it stays in sync if the
  # underlying package updates its .desktop file, and every step is
  # best-effort (a glob that matches nothing just does nothing) so a
  # missing app never breaks a rebuild.
  home.activation.desktopEntryOverrides = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    APPDIR="$HOME/.local/share/applications"
    mkdir -p "$APPDIR"

    SEARCH_DIRS="/run/current-system/sw/share/applications /etc/profiles/per-user/${config.home.username}/share/applications $HOME/.nix-profile/share/applications /var/lib/flatpak/exports/share/applications $HOME/.local/share/flatpak/exports/share/applications"

    find_desktop_file() {
      pattern="$1"
      for dir in $SEARCH_DIRS; do
        [ -d "$dir" ] || continue
        for f in "$dir"/$pattern; do
          [ -f "$f" ] && { echo "$f"; return 0; }
        done
      done
      return 1
    }

    override_field() {
      dest="$1"; field="$2"; value="$3"
      if grep -q "^$field=" "$dest" 2>/dev/null; then
        sed -i "s|^$field=.*|$field=$value|" "$dest"
      else
        sed -i "/^\[Desktop Entry\]/a $field=$value" "$dest"
      fi
    }

    # --- Zen: hide the duplicate "private browsing" launcher entry --------
    # Best-effort glob on both word orders. If Zen actually ships this as a
    # Desktop Action on the main entry rather than its own top-level
    # .desktop file, neither glob matches and this is a silent no-op —
    # `find /run/current-system/sw/share/applications -iname '*zen*'` shows
    # the real filename if it's still showing up as two entries.
    src="$(find_desktop_file '*[Zz]en*rivate*.desktop' || find_desktop_file '*rivate*[Zz]en*.desktop' || true)"
    if [ -n "$src" ]; then
      dest="$APPDIR/$(basename "$src")"
      cp -f "$src" "$dest"
      override_field "$dest" "Hidden" "true"
    fi

    # --- Vesktop -> "Discord" ----------------------------------------------
    # Icon=discord assumes the active icon theme ships that name. Confirmed
    # Colloid-Dark (gtk.nix) does NOT — this is showing a generic fallback
    # icon until either the theme changes or a real discord.svg is embedded
    # (same pattern as the Roblox icon below).
    src="$(find_desktop_file '*[Vv]esktop*.desktop' || true)"
    if [ -n "$src" ]; then
      dest="$APPDIR/$(basename "$src")"
      cp -f "$src" "$dest"
      override_field "$dest" "Name" "Discord"
      override_field "$dest" "Icon" "discord"
    fi

    # --- Sober -> "Roblox" --------------------------------------------------
    # No icon theme ships a Roblox icon, so this uses a manually-placed
    # ~/.local/share/icons/roblox.svg instead once it exists.
    src="$(find_desktop_file '*[Ss]ober*.desktop' || find_desktop_file '*org.vinegarhq.Sober*.desktop' || true)"
    if [ -n "$src" ]; then
      dest="$APPDIR/$(basename "$src")"
      cp -f "$src" "$dest"
      override_field "$dest" "Name" "Roblox"
      if [ -f "$HOME/.local/share/icons/roblox.svg" ]; then
        override_field "$dest" "Icon" "$HOME/.local/share/icons/roblox.svg"
      fi
    fi
  '';
}
