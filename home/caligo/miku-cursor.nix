{ pkgs, ... }:

# A hand-converted XCursor theme, not something from nixpkgs — the source
# is a Windows/Cursors-4U cursor pack (Hatsune Miku, by supermariofps),
# converted with win2xcur into real Xcursor binaries and a full set of
# freedesktop cursor-name aliases (default/text/pointer/wait/etc, plus the
# resize-direction and drag/zoom names GTK and Hyprland actually look up).
# The converted theme itself lives at ./assets/cursors/miku-hatsune — this
# file just packages that directory as a proper icon-theme derivation so
# home.pointerCursor (gtk.nix) can point at it like any nixpkgs cursor
# package.
#
# One known gap: the source pack has no dedicated "/"-diagonal resize
# cursor (Windows SizeNESW) — nesw-resize/ne-resize/sw-resize all alias to
# the same "\"-diagonal art as nwse-resize. Cosmetic only; resizing still
# works, the cursor glyph is just not direction-accurate on that one corner.
pkgs.runCommand "miku-hatsune-cursors" { } ''
  mkdir -p $out/share/icons/Miku-Hatsune
  cp -a ${./assets/cursors/miku-hatsune}/. $out/share/icons/Miku-Hatsune/
''
