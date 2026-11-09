{ pkgs, lib, ... }:

let
  # shaderbg: a tiny wlr-layer-shell client that renders a shadertoy-style
  # GLSL frag shader. https://sr.ht/~mstoeckl/shaderbg/
  # builds from source, if a rebuild complains about a missing dependency,
  # add it to the buildInputs list. (it's on the main branch)
  # nativeBuildInputs/buildInputs is a reconstruction of the build dependencies,
  # not a verified list from its actual meson.build.
  shaderbg = pkgs.stdenv.mkDerivation {
    pname = "shaderbg";
    version = "unstable-2026-09";
    
    src = pkgs.fetchFromSourcehut {
      owner = "~mstoeckl";
      repo = "shaderbg";
      rev = "027d4f87fd542c79d4276b521e39025477b6d03e"; # main, as of 2026-09-17
      hash = "sha256-/HtbS+vn69oEDVP4HDBvnmpkGRLz62j8lCZx+plrUeI=";
    };

    nativeBuildInputs = with pkgs; [
      meson
      ninja
      pkg-config
      wayland-scanner
    ];
    buildInputs = with pkgs; [
      wayland
      wayland-protocols
      libGL
      libglvnd
      libxkbcommon
      mesa
    ];

    meta = with pkgs.lib; {
      description = "Render GLSL (Shadertoy-style) shaders as a Wayland layer-shell wallpaper";
      homepage = "https://sr.ht/~mstoeckl/shaderbg/";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "shaderbg";
    };
  };

  # the entire theme engine lies here!!
  # given one monkeytype theme name, it now regenerates:
  #   1. the wallpaper shader
  #   2. Hyprland border/shadow/bg colors
  #   3. GTK CSS files
  #   4. bookkeeping data
  #
  # since monkeytype has 10 fields, we map them to the 5 slots in our palette
  #   background=bg
  #   background-secondary=subAlt
  #   text=text
  #   text-inactive=sub
  #   accent=main
  #
  # monkeytype themes come from monkeytype.json imported verbatim
  # (from source frontend/src/ts/constants/themes.ts)
  # 
  # note: don't modify to add new theme/shaders.

  # adwaita css isn't modified since themes are applied on start.
  adwaitaDarkCss =
    pkgs.runCommand "adwaita-dark-gtk3.css"
      {
        nativeBuildInputs = [
          pkgs.glib.bin
          pkgs.glib.dev
        ];
      }
      ''
        gresource extract ${pkgs.gtk3}/lib/libgtk-3.so.0 /org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css > $out
      '';

  # the default GTK4 dark theme is also not modified 
  # for the same reason.
  gtk4DefaultDarkCss =
    pkgs.runCommand "gtk4-default-dark.css"
      {
        nativeBuildInputs = [
          pkgs.glib.bin
          pkgs.glib.dev
        ];
      }
      ''
        gresource extract ${pkgs.gtk4}/lib/libgtk-4.so.1 /org/gtk/libgtk/theme/Default/Default-dark.css > $out
      '';

  render-theme = pkgs.writeScriptBin "render-theme" ''
    #!${pkgs.python3}/bin/python3
    import colorsys
    import json
    import os
    import re
    import pathlib
    import struct
    import sys
    import zlib

    CONFIG = pathlib.Path.home() / ".config" / "shaderbg"
    SHADERBG_CACHE = pathlib.Path.home() / ".cache" / "shaderbg"
    THEME_CACHE = pathlib.Path.home() / ".cache" / "theme"
    GTK3_CSS = pathlib.Path.home() / ".config" / "gtk-3.0" / "gtk.css"
    GTK4_CSS = pathlib.Path.home() / ".config" / "gtk-4.0" / "gtk.css"
    ADWAITA_DARK_CSS = pathlib.Path("${adwaitaDarkCss}")
    GTK4_DEFAULT_DARK_CSS = pathlib.Path("${gtk4DefaultDarkCss}")

    VALID_SHADERS = ("simplex", "warp", "balatro", "lines", "halftone", "solid", "black")

    # imports 187 themes from monkeytype. custom.json is
    # deliberately NOT part of the Nix-managed xdg.configFile set 
    # but the file is still loaded if you drop one at that path by
    # hand later
    def load_themes():
        themes = json.loads((CONFIG / "palettes" / "monkeytype.json").read_text())
        custom_path = CONFIG / "palettes" / "custom.json"

        if custom_path.exists():
            themes.update(json.loads(custom_path.read_text()))
        return themes

    # cleans up hex color values from 3-digit shorthand to 6-digit
    def hex_clean(hexval):
        hexval = hexval.lstrip("#")

        if len(hexval) == 3:
            hexval = "".join(c * 2 for c in hexval)
        
        return hexval[:6]

    # converts a hex color value to a GLSL vec3
    def hex_to_vec3(hexval):
        hexval = hex_clean(hexval)

        r = int(hexval[0:2], 16) / 255.0
        g = int(hexval[2:4], 16) / 255.0
        b = int(hexval[4:6], 16) / 255.0
        
        return f"vec3({r:.4f}, {g:.4f}, {b:.4f})"

    # calculates the perceptual brightness of a hex color value
    # >= 128 is light, < 128 is dark
    def relative_brightness(hexval):
        hexval = hex_clean(hexval)
        r, g, b = int(hexval[0:2], 16), int(hexval[2:4], 16), int(hexval[4:6], 16)
        return (r * 299 + g * 587 + b * 114) / 1000

    # returns if a theme is light background dark text
    def is_light_theme(p):
        return relative_brightness(p["text"]) < 128

    # opposite of text color's brightness.
    # bright text = dark stripes, dark text = light stripes
    # derived from theme
    def stripe_color(p):
        return "rgba(0, 0, 0, 0.25)" if relative_brightness(p["text"]) >= 128 else "rgba(255, 255, 255, 0.25)"

    # shows up only on light themes as a contrasting outline
    # used for occupied-workspace text primarily.
    def bg_contrast_color(p):
        if not is_light_theme(p):
            return "transparent"
        return "#ffffff" if relative_brightness(p["background"]) < 128 else "#000000"

    # for legibility of text drawn on top of the accent color
    def accent_contrast_color(p):
        return "#ffffff" if relative_brightness(p["accent"]) < 128 else "#000000"

    # writes the generated CSS for Walker's theme
    # since walker's theme is managed by Nix and not hot reloaded, 
    # we import the generated CSS file instead. the file itself is 
    # updated instantly on every `apply-theme`.
    def write_walker_colors(p):
        THEME_CACHE.mkdir(parents=True, exist_ok=True)
        css = (
            "/* Generated by render-theme — DO NOT hand-edit, overwritten on\n"
            "   every `apply-theme` call. */\n"
            ":root {\n"
            f"    --bg: #{p['background']};\n"
            f"    --fg: #{p['text']};\n"
            f"    --fg-muted: #{p['text_inactive']};\n"
            f"    --border: #{p['accent']};\n"
            f"    --accent: #{p['accent']};\n"
            f"    --accent-contrast: {accent_contrast_color(p)};\n"
            "}\n"
        )
        (THEME_CACHE / "walker-colors.css").write_text(css)


    # The ten bright per-workspace colors from wayle.nix's workspace-map,
    # duplicated here so they can be darkened together with everything else.
    # if changing these in wayle.nix, update this dict to match since there's 
    # no single source of truth between Nix and this script for these.
    WORKSPACE_BASE_COLORS = {
        "1": "90dfdf", "2": "90b0df", "3": "a090df", "4": "cf90df", "5": "df90bf",
        "6": "df9090", "7": "dfbf90", "8": "cfdf90", "9": "a0df90", "10": "90dfb0",
    }

    # darkens hex color by a factor (0-1)
    def darken_hex(hexval, factor):
        hexval = hex_clean(hexval)
        r = int(int(hexval[0:2], 16) * factor)
        g = int(int(hexval[2:4], 16) * factor)
        b = int(int(hexval[4:6], 16) * factor)
        return f"{r:02x}{g:02x}{b:02x}"

    # lightens hex color by a factor (0-1)
    # used for alacritty's "bright" ANSI variants
    def lighten_hex(hexval, factor):
        hexval = hex_clean(hexval)
        r = int(int(hexval[0:2], 16) + (255 - int(hexval[0:2], 16)) * factor)
        g = int(int(hexval[2:4], 16) + (255 - int(hexval[2:4], 16)) * factor)
        b = int(int(hexval[4:6], 16) + (255 - int(hexval[4:6], 16)) * factor)
        return f"{r:02x}{g:02x}{b:02x}"

    # derives workspace colors from the base colors. adjusts for theme color
    # full brightness on dark theme, reduced brightness on light theme.
    def workspace_colors(p):
        darken = is_light_theme(p)
        return {
            ws: (darken_hex(hexval, 0.65) if darken else hexval)
            for ws, hexval in WORKSPACE_BASE_COLORS.items()
        }

    # derives the main color palette from the given colors.
    # this decides what background, accent, etc. mean in context
    def derive_palette(colors):
        return {
            "background": hex_clean(colors["bg"]),
            "background_secondary": hex_clean(colors["subAlt"]),
            "text": hex_clean(colors["text"]),
            "text_inactive": hex_clean(colors["sub"]),
            "accent": hex_clean(colors["main"]),
            "error": hex_clean(colors.get("error", "ca4754")),
        }


    # writes the generated hyprland color configuration to a file.
    def write_hypr_colors(p):
        conf = (
            "# Generated by render-theme — DO NOT hand-edit, overwritten on\n"
            "# every `apply-theme` call. See hyprland.nix's `source =` line.\n"
            "general {\n"
            f"    col.active_border = rgba({p['accent']}ee) rgba({p['accent']}66) 45deg\n"
            f"    col.inactive_border = rgba({p['background_secondary']}aa)\n"
            "}\n"
            "misc {\n"
            f"    background_color = rgb({p['background']})\n"
            "}\n"
            "group {\n"
            f"    col.border_active = rgba({p['accent']}ee) rgba({p['accent']}66) 45deg\n"
            f"    col.border_inactive = rgba({p['background_secondary']}aa)\n"
            f"    col.border_locked_active = rgba({p['accent']}ee) rgba({p['accent']}66) 45deg\n"
            f"    col.border_locked_inactive = rgba({p['background_secondary']}aa)\n"
            "    groupbar {\n"
            f"        col.active = rgba({p['accent']}ff)\n"
            f"        col.inactive = rgba({p['background_secondary']}ff)\n"
            f"        col.locked_active = rgba({p['accent']}ff)\n"
            f"        col.locked_inactive = rgba({p['background_secondary']}ff)\n"
            f"        text_color = rgba({accent_contrast_color(p).lstrip('#')}ff)\n"
            f"        text_color_inactive = rgba({p['text_inactive']}ff)\n"
            "    }\n"
            "}\n"
            "plugin {\n"
            "    borders-plus-plus {\n"
            f"        col.border_1 = rgba({p['background']}ff)\n"
            "    }\n"
            "    hyprexpo {\n"
            f"        bg_col = rgba({p['background']}ff)\n"
            f"        border_color_current = rgba({p['accent']}ff)\n"
            "    }\n"
            "}\n"
        )
        THEME_CACHE.mkdir(parents=True, exist_ok=True)
        (THEME_CACHE / "hypr-colors.conf").write_text(conf)


    # writes the generated alacritty color configuration to a file.
    # monkeytype's 5-slot palette has no full 16-color ANSI set, so the
    # R/G/B/C/M/Y slots reuse Wayle's per-workspace colors.
    def write_alacritty_colors(p):
        ws = workspace_colors(p)
        normal = {
            "black": p["background"],
            "red": ws["6"],
            "green": ws["9"],
            "yellow": ws["7"],
            "blue": ws["2"],
            "magenta": ws["5"],
            "cyan": ws["1"],
            "white": p["text"],
        }
        bright = dict(normal)
        bright["black"] = p["background_secondary"]
        bright["white"] = p["text"] if is_light_theme(p) else lighten_hex(p["text"], 0.3)
        for k in ("red", "green", "yellow", "blue", "magenta", "cyan"):
            bright[k] = lighten_hex(normal[k], 0.15)

        toml = (
            "# Generated by render-theme — DO NOT hand-edit, overwritten on\n"
            "# every `apply-theme` call. See alacritty.nix's general.import line.\n"
            "[colors.primary]\n"
            f'background = "#{p["background"]}"\n'
            f'foreground = "#{p["text"]}"\n'
            "\n"
            "[colors.cursor]\n"
            f'text = "#{p["background"]}"\n'
            f'cursor = "#{p["accent"]}"\n'
            "\n"
            "[colors.normal]\n"
            + "".join(f'{k} = "#{v}"\n' for k, v in normal.items())
            + "\n[colors.bright]\n"
            + "".join(f'{k} = "#{v}"\n' for k, v in bright.items())
        )
        THEME_CACHE.mkdir(parents=True, exist_ok=True)
        (THEME_CACHE / "alacritty-colors.toml").write_text(toml)


    # writes a solid-color PNG to the specified path. 
    # used to get hyprlock's background.path to accept solid color
    # instead of an image file. zero syntax uncertainty :)
    def write_solid_png(path, hexval, size=64):
        hexval = hex_clean(hexval)
        r, g, b = int(hexval[0:2], 16), int(hexval[2:4], 16), int(hexval[4:6], 16)

        def chunk(tag, data):
            c = tag + data
            return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

        sig = b"\x89PNG\r\n\x1a\n"
        ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # 8-bit depth, RGB truecolor
        row = b"\x00" + bytes([r, g, b]) * size  # filter-type byte + one solid-color row
        raw = row * size
        idat = zlib.compress(raw, 9)
        png = sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
        pathlib.Path(path).write_bytes(png)

    # writes the generated hyprlock color configuration to a file.
    # it works please don't touch this
    def write_hyprlock_colors(p):
        conf = (
            "# Generated by render-theme — DO NOT hand-edit, overwritten on\n"
            "# every `apply-theme` call. See hyprlock.nix's `source` line.\n"
            f"$bgColor = rgba({p['background']}e6)\n"
            f"$surfaceColor = rgba({p['background_secondary']}ff)\n"
            f"$accentColor = rgba({p['accent']}ff)\n"
            f"$textColor = rgba({p['text']}ff)\n"
            f"$textMutedColor = rgba({p['text_inactive']}ff)\n"
        )
        THEME_CACHE.mkdir(parents=True, exist_ok=True)
        (THEME_CACHE / "hyprlock-colors.conf").write_text(conf)
        write_solid_png(THEME_CACHE / "lock-bg.png", p["background"])

    # writes Wayle theme, since Wayle's SCSS (~/.config/wayle/styles/)
    # is self-managed and hot-reloads, no restart is needed here.
    # `wayle panel inspect` on any widget shows its real CSS variables.
    def write_wayle_theme(p):
        WAYLE_STYLES = pathlib.Path.home() / ".config" / "wayle" / "styles"
        WAYLE_THEMES = pathlib.Path.home() / ".config" / "wayle" / "themes"
        w_bg = "#" + p["background"]
        w_surface = "#" + p["background_secondary"]
        w_elevated = mix_hex(w_surface, "#" + p["text"], 0.08)
        w_fg = "#" + p["text"]
        w_fg_muted = readable("#" + p["text_inactive"], [w_bg, w_surface, w_elevated], 4.5, w_fg)
        w_primary = "#" + p["accent"]
        w_red = "#" + p["error"]
        w_yellow = "#e0af68"
        w_green = "#9ece6a"
        w_blue = "#7aa2f7"
        css = (
            "/* Generated by render-theme — DO NOT hand-edit, overwritten on\n"
            "   every `apply-theme` call. @import \"wayle-theme-vars\"; from\n"
            "   your own index.scss to pull this in (Sass resolves the\n"
            "   leading-underscore partial by its base name). */\n"
            ":root {\n"
            f"    --accent: #{p['accent']};\n"
            f"    --primary: #{p['accent']};\n"
            f"    --palette-primary: #{p['accent']};\n"
            f"    --palette-fg: #{p['text']};\n"
            f"    --bg-base: #{p['background']};\n"
            f"    --palette-bg: #{p['background']};\n"
            f"    --stripe-color: {stripe_color(p)};\n"
            f"    --bg-contrast: {bg_contrast_color(p)};\n"
            f"    --palette-surface: {w_surface};\n"
            f"    --palette-elevated: {w_elevated};\n"
            f"    --palette-fg-muted: {w_fg_muted};\n"
            f"    --palette-fg_muted: {w_fg_muted};\n"
            f"    --palette-red: {w_red};\n"
            f"    --palette-yellow: {w_yellow};\n"
            f"    --palette-green: {w_green};\n"
            f"    --palette-blue: {w_blue};\n"
        )
        for ws, hexval in workspace_colors(p).items():
            css += f"    --ws-color-{ws}: #{hexval};\n"
        css += "}\n"
        WAYLE_STYLES.mkdir(parents=True, exist_ok=True)
        (WAYLE_STYLES / "_wayle-theme-vars.scss").write_text(css)

        theme_toml = (
            f'bg = "{w_bg}"\n'
            f'surface = "{w_surface}"\n'
            f'elevated = "{w_elevated}"\n'
            f'fg = "{w_fg}"\n'
            f'fg_muted = "{w_fg_muted}"\n'
            f'primary = "{w_primary}"\n'
            f'red = "{w_red}"\n'
            f'yellow = "{w_yellow}"\n'
            f'green = "{w_green}"\n'
            f'blue = "{w_blue}"\n'
        )
        WAYLE_THEMES.mkdir(parents=True, exist_ok=True)
        tmp = WAYLE_THEMES / ".apply-theme.toml.tmp"
        tmp.write_text(theme_toml)
        os.replace(tmp, WAYLE_THEMES / "apply-theme.toml")

    # standard GTK/libadwaita CSS. redefines them without needing a new theme package
    # for every theme. doesn't hot-reload, GTK apps need to be restarted.
    def write_gtk_css(p):
        css = (
            "/* Generated by render-theme — DO NOT hand-edit, overwritten on\n"
            "   every `apply-theme` call. */\n"
            f"@define-color window_bg_color #{p['background']};\n"
            f"@define-color window_fg_color #{p['text']};\n"
            f"@define-color view_bg_color #{p['background_secondary']};\n"
            f"@define-color view_fg_color #{p['text']};\n"
            f"@define-color headerbar_bg_color #{p['background_secondary']};\n"
            f"@define-color headerbar_fg_color #{p['text']};\n"
            f"@define-color accent_color #{p['accent']};\n"
            f"@define-color accent_bg_color #{p['accent']};\n"
            f"@define-color theme_bg_color #{p['background']};\n"
            f"@define-color theme_fg_color #{p['text']};\n"
            f"@define-color theme_text_color #{p['text']};\n"
            f"@define-color theme_base_color #{p['background']};\n"
            # Extra named colors the Thunar block below leans on. Kept as
            # @define-color rather than literals so the Thunar rules read the
            # same way the rest of this file does, and so you can reference
            # them yourself from a hand-written override later.
            f"@define-color theme_fg_muted #{p['text_inactive']};\n"
            f"@define-color theme_surface #{p['background_secondary']};\n"
            f"@define-color accent_contrast {accent_contrast_color(p)};\n"
            f"@define-color theme_error #{p['error']};\n"
        )

        # --- Thunar ---------------------------------------------------------
        # GTK3 ONLY — deliberately not written into gtk-4.0/gtk.css below.
        # Thunar is a GTK3 app, `treeview` isn't a GTK4 node at all, and
        # there's no reason to hand GTK4 a pile of selectors that can never
        # match anything.
        #
        # NOTE ON SELECTORS: the standard GTK3 nodes here (window, toolbar,
        # treeview, scrollbar, entry, button, paned, rubberband, menu) are
        # solid. Thunar's own widgets are less certain because they don't
        # set custom CSS names on everything, so their nodes fall back to
        # raw type names, which is why both a generic and a type-name
        # selector are listed in a few places below. 
        # run `GTK_DEBUG=interactive thunar` and look at the CSS tab 
        # to inspect the CSS of the running Thunar instance.
        stripe = stripe_color(p)
        thunar_css = (
            "\n"
            "/* ---- Thunar ---------------------------------------------- */\n"
            "\n"
            "    border-radius: 0;\n"
            "}\n"
            "\n"
            "window { background-color: @theme_bg_color; }\n"
            "treeview.view, .view, iconview, ExoIconView, ThunarStandardView {\n"
            "    background-color: @theme_bg_color;\n"
            "    color: @theme_fg_color;\n"
            "}\n"
            "\n"
            "toolbar, headerbar, .toolbar {\n"
            "    background-color: @theme_surface;\n"
            "    border-bottom: 2px solid @accent_color;\n"
            "    padding: 4px 6px;\n"
            "}\n"
            "\n"
            "toolbar, .toolbar {\n"
            "    background-image: repeating-linear-gradient(\n"
            f"        -45deg, {stripe} 0, {stripe} 6px,\n"
            "        transparent 6px, transparent 12px\n"
            "    );\n"
            "}\n"
            "\n"
            ".sidebar, .sidebar treeview, ThunarShortcutsView,\n"
            "ThunarShortcutsView.view {\n"
            "    background-color: @theme_surface;\n"
            "    color: @theme_fg_color;\n"
            "    border-right: 2px solid @accent_color;\n"
            "}\n"
            "\n"
            ".sidebar treeview.view:disabled,\n"
            ".sidebar .dim-label,\n"
            "ThunarShortcutsView .dim-label {\n"
            "    color: @theme_fg_muted;\n"
            "    padding-top: 6px;\n"
            "    padding-bottom: 2px;\n"
            "}\n"
            "\n"
            "treeview.view:selected, .view:selected, iconview:selected,\n"
            ".sidebar treeview.view:selected, ExoIconView:selected {\n"
            "    background-image: repeating-linear-gradient(\n"
            "        -45deg,\n"
            "        @accent_color 0, @accent_color 6px,\n"
            "        shade(@accent_color, 1.3) 6px, shade(@accent_color, 1.3) 12px\n"
            "    );\n"
            "    color: @accent_contrast;\n"
            "}\n"
            "treeview.view:selected:focus, .view:selected:focus,\n"
            "iconview:selected:focus {\n"
            "    color: @accent_contrast;\n"
            "}\n"
            "\n"
            "treeview.view:hover, .view:hover, iconview:hover,\n"
            ".sidebar treeview.view:hover {\n"
            "    background-color: alpha(@accent_color, 0.18);\n"
            "}\n"
            "\n"
            "treeview.view { -GtkTreeView-vertical-separator: 0; }\n"
            "treeview.view:not(:selected) { padding-top: 1px; padding-bottom: 1px; }\n"
            "\n"
            "treeview.view header button {\n"
            "    background-color: @theme_surface;\n"
            "    background-image: none;\n"
            "    color: @theme_fg_muted;\n"
            "    border: none;\n"
            "    border-right: 1px solid alpha(@accent_color, 0.35);\n"
            "    border-bottom: 2px solid @accent_color;\n"
            "    padding: 3px 8px;\n"
            "}\n"
            "treeview.view header button:hover {\n"
            "    color: @theme_fg_color;\n"
            "    background-color: alpha(@accent_color, 0.18);\n"
            "}\n"
            "\n"
            "rubberband, .rubberband, treeview.view rubberband {\n"
            "    background-color: alpha(@accent_color, 0.25);\n"
            "    border: 2px solid @accent_color;\n"
            "}\n"
            "\n"
            "treeview.view:drop(active), .view:drop(active),\n"
            ".sidebar treeview.view:drop(active) {\n"
            "    border: 2px solid @accent_color;\n"
            "    background-color: alpha(@accent_color, 0.22);\n"
            "}\n"
            "\n"
            "scrollbar { background-color: transparent; border: none; }\n"
            "scrollbar trough { background-color: transparent; border: none; }\n"
            "scrollbar slider {\n"
            "    background-color: alpha(@accent_color, 0.55);\n"
            "    border-radius: 0;\n"
            "    border: none;\n"
            "    min-width: 8px;\n"
            "    min-height: 8px;\n"
            "}\n"
            "scrollbar slider:hover { background-color: @accent_color; }\n"
            "\n"
            "paned > separator {\n"
            "    background-color: @accent_color;\n"
            "    min-width: 2px;\n"
            "    min-height: 2px;\n"
            "}\n"
            "\n"
            "entry {\n"
            "    background-color: @theme_bg_color;\n"
            "    color: @theme_fg_color;\n"
            "    border: 2px solid @accent_color;\n"
            "    padding: 3px 8px;\n"
            "}\n"
            "entry:focus { border-color: shade(@accent_color, 1.25); }\n"
            "\n"
            "toolbar button, .toolbar button, .path-bar button {\n"
            "    background-color: transparent;\n"
            "    background-image: none;\n"
            "    color: @theme_fg_color;\n"
            "    border: 2px solid transparent;\n"
            "    padding: 2px 8px;\n"
            "}\n"
            "toolbar button:hover, .toolbar button:hover, .path-bar button:hover {\n"
            "    background-color: alpha(@accent_color, 0.20);\n"
            "    border-color: alpha(@accent_color, 0.55);\n"
            "}\n"
            "toolbar button:checked, .path-bar button:checked,\n"
            "toolbar button:active, .path-bar button:active {\n"
            "    background-color: alpha(@accent_color, 0.30);\n"
            "    border-color: @accent_color;\n"
            "}\n"
            "\n"
            "menubar, menu, .menu, popover, popover.background {\n"
            "    background-color: @theme_surface;\n"
            "    color: @theme_fg_color;\n"
            "    border: 2px solid @accent_color;\n"
            "}\n"
            "menu menuitem:hover, .menu menuitem:hover, popover modelbutton:hover {\n"
            "    background-color: alpha(@accent_color, 0.25);\n"
            "    color: @theme_fg_color;\n"
            "}\n"
            "\n"
            "statusbar, .statusbar {\n"
            "    background-color: @theme_surface;\n"
            "    color: @theme_fg_muted;\n"
            "    border-top: 2px solid @accent_color;\n"
            "    padding: 2px 8px;\n"
            "}\n"
            "\n"
            "button {\n"
            "    background-image: none;\n"
            "    background-color: @theme_surface;\n"
            "    color: @theme_fg_color;\n"
            "    border: 2px solid alpha(@accent_color, 0.35);\n"
            "    border-radius: 0;\n"
            "    box-shadow: none;\n"
            "    text-shadow: none;\n"
            "    -gtk-icon-shadow: none;\n"
            "}\n"
            "button:hover {\n"
            "    background-color: alpha(@accent_color, 0.20);\n"
            "    border-color: alpha(@accent_color, 0.65);\n"
            "}\n"
            "button:checked, button:active {\n"
            "    background-image: repeating-linear-gradient(\n"
            "        -45deg,\n"
            "        @accent_color 0, @accent_color 6px,\n"
            "        shade(@accent_color, 1.3) 6px, shade(@accent_color, 1.3) 12px\n"
            "    );\n"
            "    border-color: @accent_color;\n"
            "    color: @accent_contrast;\n"
            "}\n"
            "button:checked label, button:active label { color: @accent_contrast; }\n"
            "button:disabled {\n"
            "    background-color: @theme_bg_color;\n"
            "    color: @theme_fg_muted;\n"
            "    border-color: alpha(@theme_fg_muted, 0.3);\n"
            "}\n"
            ".linked > button:not(:first-child) { border-left-width: 0; }\n"
            "button.suggested-action {\n"
            "    background-color: @accent_color;\n"
            "    color: @accent_contrast;\n"
            "    border-color: @accent_color;\n"
            "}\n"
            "button.destructive-action {\n"
            "    background-color: @theme_error;\n"
            "    color: @accent_contrast;\n"
            "    border-color: @theme_error;\n"
            "}\n"
            "button.titlebutton, headerbar button.flat, button.flat {\n"
            "    background-color: transparent;\n"
            "    border-color: transparent;\n"
            "}\n"
            "button.titlebutton:hover, headerbar button.flat:hover, button.flat:hover {\n"
            "    background-color: alpha(@accent_color, 0.20);\n"
            "}\n"
            ".titlebar, headerbar {\n"
            "    background-image: none;\n"
            "    background-color: @theme_surface;\n"
            "    border-bottom: 2px solid @accent_color;\n"
            "    box-shadow: none;\n"
            "}\n"
            "*:link, button.link { color: @accent_color; }\n"
            "*:visited { color: shade(@accent_color, 0.8); }\n"
        )

        GTK3_CSS.parent.mkdir(parents=True, exist_ok=True)
        GTK3_CSS.write_text("")

        slot_file = THEME_CACHE / "gtk-slot"
        current = slot_file.read_text().strip() if slot_file.exists() else ""
        slot = "apply-theme-b" if current == "apply-theme-a" else "apply-theme-a"
        nb = "button:not(.suggested-action):not(.destructive-action)"
        flat_buttons = (
            "\n"
            + nb + " {\n"
            "    background-image: none;\n"
            "    background-color: transparent;\n"
            "    border-color: transparent;\n"
            "    box-shadow: none;\n"
            "}\n"
            + nb + ":hover {\n"
            "    background-color: alpha(@accent_color, 0.20);\n"
            "}\n"
            + nb + ":checked, " + nb + ":active {\n"
            "    background-image: repeating-linear-gradient(\n"
            "        -45deg,\n"
            "        @accent_color 0, @accent_color 6px,\n"
            "        shade(@accent_color, 1.3) 6px, shade(@accent_color, 1.3) 12px\n"
            "    );\n"
            "    border-color: @accent_color;\n"
            "    color: @accent_contrast;\n"
            "}\n"
            + nb + ":disabled {\n"
            "    background-color: transparent;\n"
            "    color: @theme_fg_muted;\n"
            "}\n"
            "dropdown > " + nb + ", combobox " + nb + " {\n"
            "    background-color: @theme_surface;\n"
            "    border: 1px solid alpha(@accent_color, 0.35);\n"
            "}\n"
            "dropdown > " + nb + ":hover, combobox " + nb + ":hover {\n"
            "    background-color: alpha(@accent_color, 0.20);\n"
            "}\n"
            "button.suggested-action {\n"
            "    background-image: none;\n"
            "    background-color: @accent_color;\n"
            "    color: @accent_contrast;\n"
            "    border-color: @accent_color;\n"
            "}\n"
            "button.destructive-action {\n"
            "    background-image: none;\n"
            "    background-color: @theme_error;\n"
            "    color: @accent_contrast;\n"
            "    border-color: @theme_error;\n"
            "}\n"
        )
        widget_css = (
            "scale trough, scale trough:disabled, scale > trough, scale > trough:disabled {\n"
            "    background-image: none;\n"
            "    background-color: alpha(@theme_fg_color, 0.15);\n"
            "    border: none;\n"
            "    border-radius: 0;\n"
            "}\n"
            "scale highlight, scale highlight:disabled, scale trough highlight, scale > trough > highlight {\n"
            "    background-image: none;\n"
            "    background-color: @accent_color;\n"
            "    border: none;\n"
            "    border-radius: 0;\n"
            "}\n"
            "scale slider, scale slider:hover, scale slider:active, scale slider:disabled, "
            "scale > trough > slider, scale > trough > slider:hover, scale > trough > slider:active, scale > trough > slider:disabled {\n"
            "    background-image: none;\n"
            "    background-color: @accent_color;\n"
            "    border: 2px solid @accent_color;\n"
            "    border-radius: 0;\n"
            "    box-shadow: none;\n"
            "}\n"
            "scale slider:hover, scale slider:active, scale > trough > slider:hover, scale > trough > slider:active {\n"
            "    background-color: shade(@accent_color, 1.15);\n"
            "    border-color: shade(@accent_color, 1.15);\n"
            "}\n"
            "switch, switch:hover, switch:disabled {\n"
            "    background-image: none;\n"
            "    background-color: @theme_surface;\n"
            "    border: 2px solid alpha(@accent_color, 0.35);\n"
            "    border-radius: 0;\n"
            "    box-shadow: none;\n"
            "}\n"
            "switch:checked, switch:checked:hover {\n"
            "    background-color: @accent_color;\n"
            "    border-color: @accent_color;\n"
            "}\n"
            "switch slider, switch:hover slider, switch:checked slider, switch:disabled slider {\n"
            "    background-image: none;\n"
            "    background-color: @theme_fg_color;\n"
            "    border: none;\n"
            "    border-radius: 0;\n"
            "    box-shadow: none;\n"
            "}\n"
            "switch:checked slider {\n"
            "    background-color: @accent_contrast;\n"
            "}\n"
        )
        theme_css = remap_adwaita(p) + "\n" + css + thunar_css + flat_buttons + widget_css
        theme_dir = pathlib.Path.home() / ".local" / "share" / "themes" / slot / "gtk-3.0"
        theme_dir.mkdir(parents=True, exist_ok=True)
        (theme_dir / "gtk.css").write_text(theme_css)
        (theme_dir / "gtk-dark.css").write_text(theme_css)
        gtk4_css = (
            remap_adwaita(p, GTK4_DEFAULT_DARK_CSS, "resource:///org/gtk/libgtk/theme/Default/assets/")
            + "\n"
            + css
            + flat_buttons
            + widget_css
        )
        gtk4_dir = theme_dir.parent / "gtk-4.0"
        gtk4_dir.mkdir(parents=True, exist_ok=True)
        (gtk4_dir / "gtk.css").write_text(gtk4_css)
        (gtk4_dir / "gtk-dark.css").write_text(gtk4_css)
        THEME_CACHE.mkdir(parents=True, exist_ok=True)
        slot_file.write_text(slot + "\n")

        GTK4_CSS.parent.mkdir(parents=True, exist_ok=True)
        GTK4_CSS.write_text(css + adwaita_vars(p))

    # define CSS variables for the Adwaita theme
    def adwaita_vars(p):
        bg = "#" + p["background"]
        bg2 = "#" + p["background_secondary"]
        fg = "#" + p["text"]
        acc = "#" + p["accent"]
        err = "#" + p["error"]
        toward = "#ffffff" if luminance(bg) < 0.5 else "#000000"
        acc_text = readable(acc, [bg, bg2], 4.5, fg)
        err_text = readable(err, [bg, bg2], 4.5, fg)
        popover = mix_hex(bg, bg2, 0.5)
        border = rgba_hex(fg, "0.15")
        shade = rgba_hex("#000000", "0.25")
        pairs = [
            ("--accent-bg-color", acc),
            ("--accent-fg-color", accent_contrast_color(p)),
            ("--accent-color", acc_text),
            ("--destructive-bg-color", err),
            ("--destructive-fg-color", toward),
            ("--destructive-color", err_text),
            ("--error-bg-color", err),
            ("--error-fg-color", toward),
            ("--error-color", err_text),
            ("--window-bg-color", bg),
            ("--window-fg-color", fg),
            ("--view-bg-color", bg),
            ("--view-fg-color", fg),
            ("--headerbar-bg-color", bg2),
            ("--headerbar-fg-color", fg),
            ("--headerbar-border-color", fg),
            ("--headerbar-backdrop-color", bg),
            ("--headerbar-shade-color", shade),
            ("--sidebar-bg-color", bg2),
            ("--sidebar-fg-color", fg),
            ("--sidebar-backdrop-color", bg2),
            ("--sidebar-border-color", border),
            ("--sidebar-shade-color", shade),
            ("--secondary-sidebar-bg-color", bg2),
            ("--secondary-sidebar-fg-color", fg),
            ("--secondary-sidebar-backdrop-color", bg2),
            ("--secondary-sidebar-border-color", border),
            ("--secondary-sidebar-shade-color", shade),
            ("--card-bg-color", bg2),
            ("--card-fg-color", fg),
            ("--card-shade-color", shade),
            ("--dialog-bg-color", popover),
            ("--dialog-fg-color", fg),
            ("--popover-bg-color", popover),
            ("--popover-fg-color", fg),
            ("--popover-shade-color", shade),
            ("--thumbnail-bg-color", bg2),
            ("--thumbnail-fg-color", fg),
            ("--shade-color", shade),
            ("--scrollbar-outline-color", shade),
        ]
        return "\n" + css_block(":root", pairs)


    VESKTOP_DIR = pathlib.Path.home() / ".config" / "vesktop"

    # define helper functions for color manipulation
    def hex_rgb(h):
        h = h.lstrip("#")
        return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)

    # mix two hex colors
    def mix_hex(a, b, t):
        ra, ga, ba = hex_rgb(a)
        rb, gb, bb = hex_rgb(b)
        return "#%02x%02x%02x" % (
            round(ra + (rb - ra) * t),
            round(ga + (gb - ga) * t),
            round(ba + (bb - ba) * t),
        )

    # hex color to RGBA
    def rgba_hex(h, a):
        r, g, b = hex_rgb(h)
        return "rgba(%d, %d, %d, %s)" % (r, g, b, a)

    # calculate the relative luminance of a hex color
    def luminance(h):
        def channel(c):
            c = c / 255
            return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
        r, g, b = hex_rgb(h)
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)

    # calculate the contrast between two hex colors
    def contrast(a, b):
        la, lb = luminance(a), luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

    # find a color that has sufficient contrast with a set of background colors
    def readable(fg, bgs, target, toward):
        out = fg
        step = 0.0
        while min(contrast(out, b) for b in bgs) < target and step < 1.0:
            step = min(1.0, step + 0.05)
            out = mix_hex(fg, toward, step)
        return out

    # system24 settings
    SYSTEM24_SETTINGS = [
        ("--font", "'Iosevka SKYC'"),
        ("--code-font", "'Iosevka SKYC'"),
        ("font-weight", "400"),
        ("letter-spacing", "-0.05ch"),
        ("--gap", "12px"),
        ("--divider-thickness", "4px"),
        ("--border-thickness", "2px"),
        ("--border-hover-transition", "0.2s ease"),
        ("--animations", "on"),
        ("--list-item-transition", "0.2s ease"),
        ("--dms-icon-svg-transition", "0.4s ease"),
        ("--top-bar-height", "var(--gap)"),
        ("--top-bar-button-position", "titlebar"),
        ("--top-bar-title-position", "off"),
        ("--subtle-top-bar-title", "off"),
        ("--custom-window-controls", "off"),
        ("--window-control-size", "14px"),
        ("--custom-dms-icon", "off"),
        ("--dms-icon-svg-url", 'url("")'),
        ("--dms-icon-svg-size", "90%"),
        ("--dms-icon-color-before", "var(--icon-subtle)"),
        ("--dms-icon-color-after", "var(--white)"),
        ("--custom-dms-background", "off"),
        ("--dms-background-image-url", 'url("")'),
        ("--dms-background-image-size", "cover"),
        ("--dms-background-color", "linear-gradient(70deg, var(--blue-2), var(--purple-2), var(--red-2))"),
        ("--background-image", "off"),
        ("--background-image-url", 'url("")'),
        ("--transparency-tweaks", "off"),
        ("--remove-bg-layer", "off"),
        ("--panel-blur", "off"),
        ("--blur-amount", "12px"),
        ("--bg-floating", "var(--bg-3)"),
        ("--small-user-panel", "on"),
        ("--unrounding", "on"),
        ("--round-pfp", "off"),
        ("--remove-pfp-decor", "off"),
        ("--custom-spotify-bar", "on"),
        ("--ascii-titles", "on"),
        ("--ascii-loader", "system24"),
        ("--panel-labels", "on"),
        ("--label-color", "var(--text-muted)"),
        ("--label-font-weight", "500"),
    ]

    # remap the Adwaita theme to use the system24 color scheme
    def remap_adwaita(p, source=None, assets="resource:///org/gtk/libgtk/theme/Adwaita/assets/"):
        bg = "#" + p["background"]
        bg2 = "#" + p["background_secondary"]
        text = "#" + p["text"]
        accent = "#" + p["accent"]
        err = "#" + p["error"]
        contrast = accent_contrast_color(p)
        ramp = [
            (0.000, mix_hex(bg, "#000000", 0.75)),
            (0.106, mix_hex(bg, "#000000", 0.35)),
            (0.176, bg),
            (0.208, bg2),
            (0.357, mix_hex(bg2, text, 0.30)),
            (0.568, mix_hex(text, bg, 0.40)),
            (0.930, text),
            (1.000, text),
        ]

        # calculate the gray value for a given luminance
        def gray(l):
            for (l0, c0), (l1, c1) in zip(ramp, ramp[1:]):
                if l <= l1:
                    return mix_hex(c0, c1, 0.0 if l1 == l0 else (l - l0) / (l1 - l0))
            return ramp[-1][1]

        # create a shaded version of a color based on its luminance
        def shade(base, l, ref):
            if l <= ref:
                return mix_hex(base, "#000000", 1.0 - l / ref)
            return mix_hex(base, "#ffffff", (l - ref) / (1.0 - ref) * 0.8)

        # remap a color to its appropriate shade based on its luminance
        def remap(r, g, b):
            if (r, g, b) == (255, 255, 255):
                return contrast
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if s < 0.12 or l < 0.02:
                return gray(l)
            if 0.53 <= h <= 0.67:
                return shade(accent, l, 0.351)
            if (h < 0.03 or h > 0.95) and s > 0.4:
                return shade(err, l, 0.400)
            return "#%02x%02x%02x" % (r, g, b)

        # replace hex color values with their remapped versions
        def hex_sub(m):
            v = m.group(1)
            if len(v) == 3:
                v = "".join(ch * 2 for ch in v)
            return remap(int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))

        def rgba_sub(m):
            r, g, b = int(m.group(1)), int(m.group(2)), int(m.group(3))
            alpha = m.group(4)
            if (r, g, b) in ((0, 0, 0), (255, 255, 255)):
                return m.group(0)
            rr, gg, bb = hex_rgb(remap(r, g, b))
            if alpha:
                return "rgba(%d, %d, %d%s)" % (rr, gg, bb, alpha)
            return "rgb(%d, %d, %d)" % (rr, gg, bb)

        src = (source or ADWAITA_DARK_CSS).read_text()
        src = re.sub(r"(?<![\w-])#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![\w-])", hex_sub, src)
        src = re.sub(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(,\s*[\d.]+\s*)?\)", rgba_sub, src)
        src = re.sub(r"(?<=[\s:,(])white(?=[\s;,)])", text, src)
        src = src.replace('url("assets/', 'url("' + assets)

        radius_re = re.compile(r"((?:border(?:-[a-z]+)*-radius|-gtk-outline-radius)\s*:\s*)([^;}]*)")
        shadow_re = re.compile(r"((?:text-shadow|-gtk-icon-shadow|box-shadow)\s*:\s*)([^;}]*)")

        def rule_sub(m):
            selector, body = m.group(1), m.group(2)
            keep_round = "radio" in selector

            def radius_sub(r):
                return r.group(0) if keep_round and "100%" in r.group(2) else r.group(1) + "0"

            body = radius_re.sub(radius_sub, body)
            body = shadow_re.sub(lambda s: s.group(1) + "none", body)
            return selector + "{" + body + "}"

        src = re.sub(r"([^{}]+)\{([^{}]*)\}", rule_sub, src)
        return src

    # create a CSS block with the given selector and properties
    def css_block(selector, pairs, important=False):
        suffix = " !important" if important else ""
        return selector + " {\n" + "".join("    %s: %s%s;\n" % (k, v, suffix) for k, v in pairs) + "}\n"

    # all Obsidian vaults
    def obsidian_vaults():
        conf = pathlib.Path.home() / ".config" / "obsidian" / "obsidian.json"
        if not conf.is_file():
            return []
        try:
            data = json.loads(conf.read_text())
        except ValueError:
            return []
        out = []
        for entry in (data.get("vaults") or {}).values():
            path = entry.get("path")
            if path and pathlib.Path(path).is_dir():
                out.append(pathlib.Path(path))
        return out


    # get a list of all browser profiles
    def browser_profiles():
        out = []
        home = pathlib.Path.home()
        for root in (
            home / ".config" / "zen",
            home / ".zen",
            home / ".mozilla" / "firefox",
        ):
            ini = root / "profiles.ini"
            if not ini.is_file():
                continue
            path = None
            relative = True
            for line in ini.read_text().splitlines() + ["["]:
                line = line.strip()
                if line.startswith("["):
                    if path:
                        full = (root / path) if relative else pathlib.Path(path)
                        if full.is_dir():
                            out.append(full)
                    path = None
                    relative = True
                elif line.startswith("Path="):
                    path = line[5:]
                elif line.startswith("IsRelative="):
                    relative = line[11:] != "0"
        return out

    # remove comments and trailing commas from a JSONC string
    def strip_jsonc(text):
        out = []
        i = 0
        in_string = False
        while i < len(text):
            c = text[i]
            if in_string:
                out.append(c)
                if c == "\\" and i + 1 < len(text):
                    out.append(text[i + 1])
                    i += 2
                    continue
                if c == '"':
                    in_string = False
                i += 1
                continue
            if c == '"':
                in_string = True
                out.append(c)
                i += 1
                continue
            if text.startswith("//", i):
                j = text.find("\n", i)
                i = len(text) if j == -1 else j
                continue
            if text.startswith("/*", i):
                j = text.find("*/", i + 2)
                i = len(text) if j == -1 else j + 2
                continue
            out.append(c)
            i += 1
        cleaned = "".join(out)
        cleaned = re.sub(r",(\s*[}\]])", r"\1", cleaned)
        return cleaned

    # write a VS Code theme file based on the given palette
    def write_vscode_theme(p):
        ext_root = pathlib.Path.home() / ".vscode" / "extensions"
        if not ext_root.is_dir():
            return
        ext = ext_root / "caligo.apply-theme-1.0.0"

        def alpha(hexval, a):
            return "#%s%02x" % (hex_clean(hexval), round(float(a) * 255))

        bg = "#" + p["background"]
        bg2 = "#" + p["background_secondary"]
        fg = "#" + p["text"]
        muted = "#" + p["text_inactive"]
        acc = "#" + p["accent"]
        err = "#" + p["error"]
        on_acc = accent_contrast_color(p)
        acc_text = readable(acc, [bg, bg2], 4.5, fg)
        err_text = readable(err, [bg, bg2], 4.5, fg)
        border = alpha(fg, "0.15")
        sel = alpha(acc, "0.25")
        hover = alpha(fg, "0.08")
        ws = workspace_colors(p)
        dark = not is_light_theme(p)
        colors = {
            "editor.background": bg,
            "editor.foreground": fg,
            "editorLineNumber.foreground": alpha(muted, "0.6"),
            "editorLineNumber.activeForeground": acc,
            "editorCursor.foreground": acc,
            "editor.selectionBackground": sel,
            "editor.inactiveSelectionBackground": alpha(acc, "0.15"),
            "editor.lineHighlightBackground": alpha(fg, "0.05"),
            "editorWhitespace.foreground": alpha(muted, "0.3"),
            "editorIndentGuide.background1": alpha(fg, "0.1"),
            "editorIndentGuide.activeBackground1": alpha(acc, "0.5"),
            "editorGutter.background": bg,
            "editorWidget.background": bg2,
            "editorWidget.border": border,
            "editorSuggestWidget.selectedBackground": sel,
            "editorHoverWidget.background": bg2,
            "editorError.foreground": err,
            "editorBracketMatch.background": alpha(acc, "0.2"),
            "editorBracketMatch.border": acc,
            "sideBar.background": bg2,
            "sideBar.foreground": fg,
            "sideBar.border": border,
            "sideBarTitle.foreground": muted,
            "sideBarSectionHeader.background": bg2,
            "sideBarSectionHeader.foreground": muted,
            "activityBar.background": bg2,
            "activityBar.foreground": fg,
            "activityBar.inactiveForeground": muted,
            "activityBar.border": border,
            "activityBarBadge.background": acc,
            "activityBarBadge.foreground": on_acc,
            "statusBar.background": bg2,
            "statusBar.foreground": fg,
            "statusBar.border": border,
            "statusBar.noFolderBackground": bg2,
            "statusBar.debuggingBackground": acc,
            "statusBar.debuggingForeground": on_acc,
            "titleBar.activeBackground": bg2,
            "titleBar.activeForeground": fg,
            "titleBar.inactiveBackground": bg2,
            "titleBar.inactiveForeground": muted,
            "titleBar.border": border,
            "menu.background": bg2,
            "menu.foreground": fg,
            "menu.selectionBackground": sel,
            "menubar.selectionBackground": sel,
            "tab.activeBackground": bg,
            "tab.activeForeground": fg,
            "tab.inactiveBackground": bg2,
            "tab.inactiveForeground": muted,
            "tab.border": border,
            "tab.activeBorderTop": acc,
            "tab.hoverBackground": hover,
            "editorGroupHeader.tabsBackground": bg2,
            "editorGroupHeader.noTabsBackground": bg2,
            "editorGroup.border": border,
            "panel.background": bg,
            "panel.border": border,
            "panelTitle.activeForeground": fg,
            "panelTitle.inactiveForeground": muted,
            "panelTitle.activeBorder": acc,
            "terminal.background": bg,
            "terminal.foreground": fg,
            "terminal.ansiBlack": "#" + p["background"],
            "terminal.ansiRed": "#" + ws["6"],
            "terminal.ansiGreen": "#" + ws["9"],
            "terminal.ansiYellow": "#" + ws["7"],
            "terminal.ansiBlue": "#" + ws["2"],
            "terminal.ansiMagenta": "#" + ws["5"],
            "terminal.ansiCyan": "#" + ws["1"],
            "terminal.ansiWhite": fg,
            "terminal.ansiBrightBlack": bg2,
            "terminal.ansiBrightRed": "#" + lighten_hex(ws["6"], 0.15),
            "terminal.ansiBrightGreen": "#" + lighten_hex(ws["9"], 0.15),
            "terminal.ansiBrightYellow": "#" + lighten_hex(ws["7"], 0.15),
            "terminal.ansiBrightBlue": "#" + lighten_hex(ws["2"], 0.15),
            "terminal.ansiBrightMagenta": "#" + lighten_hex(ws["5"], 0.15),
            "terminal.ansiBrightCyan": "#" + lighten_hex(ws["1"], 0.15),
            "terminal.ansiBrightWhite": fg,
            "terminalCursor.foreground": acc,
            "list.activeSelectionBackground": sel,
            "list.activeSelectionForeground": fg,
            "list.inactiveSelectionBackground": alpha(acc, "0.15"),
            "list.hoverBackground": hover,
            "list.highlightForeground": acc_text,
            "list.errorForeground": err_text,
            "tree.indentGuidesStroke": alpha(fg, "0.15"),
            "input.background": bg,
            "input.foreground": fg,
            "input.border": muted,
            "input.placeholderForeground": alpha(muted, "0.7"),
            "inputOption.activeBorder": acc,
            "dropdown.background": bg,
            "dropdown.foreground": fg,
            "dropdown.border": muted,
            "button.background": acc,
            "button.foreground": on_acc,
            "button.hoverBackground": mix_hex(acc, fg, 0.15),
            "badge.background": acc,
            "badge.foreground": on_acc,
            "progressBar.background": acc,
            "scrollbarSlider.background": alpha(fg, "0.15"),
            "scrollbarSlider.hoverBackground": alpha(fg, "0.25"),
            "scrollbarSlider.activeBackground": alpha(acc, "0.5"),
            "focusBorder": acc,
            "foreground": fg,
            "widget.border": border,
            "quickInput.background": bg2,
            "quickInputList.focusBackground": sel,
            "notifications.background": bg2,
            "notifications.foreground": fg,
            "notificationCenterHeader.background": bg2,
            "peekViewEditor.background": bg2,
            "peekViewResult.background": bg2,
            "peekViewResult.selectionBackground": sel,
            "breadcrumb.background": bg,
            "breadcrumb.foreground": muted,
            "breadcrumb.focusForeground": fg,
            "minimap.background": bg,
            "gitDecoration.modifiedResourceForeground": acc_text,
            "gitDecoration.deletedResourceForeground": err_text,
            "gitDecoration.untrackedResourceForeground": "#" + ws["9"],
            "gitDecoration.ignoredResourceForeground": alpha(muted, "0.6"),
            "errorForeground": err,
            "descriptionForeground": muted,
            "textLink.foreground": acc_text,
            "textLink.activeForeground": acc,
        }
        tokens = [
            {"scope": ["comment", "punctuation.definition.comment"],
             "settings": {"foreground": muted, "fontStyle": "italic"}},
            {"scope": ["string", "constant.other.symbol"],
             "settings": {"foreground": "#" + ws["9"]}},
            {"scope": ["constant.numeric", "constant.language", "keyword.other.unit"],
             "settings": {"foreground": "#" + ws["7"]}},
            {"scope": ["keyword", "storage", "storage.type", "keyword.control"],
             "settings": {"foreground": acc_text}},
            {"scope": ["entity.name.function", "support.function", "meta.function-call"],
             "settings": {"foreground": "#" + ws["2"]}},
            {"scope": ["entity.name.type", "entity.name.class", "support.type", "support.class"],
             "settings": {"foreground": "#" + ws["1"]}},
            {"scope": ["variable", "variable.other", "meta.definition.variable"],
             "settings": {"foreground": fg}},
            {"scope": ["variable.parameter", "entity.name.tag"],
             "settings": {"foreground": "#" + ws["5"]}},
            {"scope": ["invalid", "message.error"],
             "settings": {"foreground": err}},
        ]
        theme = {
            "name": "apply-theme",
            "type": "dark" if dark else "light",
            "semanticHighlighting": True,
            "colors": colors,
            "tokenColors": tokens,
        }
        package = {
            "name": "apply-theme",
            "displayName": "apply-theme",
            "description": "Generated by render-theme",
            "version": "1.0.0",
            "publisher": "caligo",
            "engines": {"vscode": "^1.60.0"},
            "categories": ["Themes"],
            "contributes": {
                "themes": [
                    {
                        "label": "apply-theme",
                        "uiTheme": "vs-dark" if dark else "vs",
                        "path": "./themes/apply-theme-color-theme.json",
                    }
                ]
            },
        }
        try:
            (ext / "themes").mkdir(parents=True, exist_ok=True)
            (ext / "package.json").write_text(json.dumps(package, indent=2))
            tmp = ext / "themes" / ".apply-theme.json.tmp"
            tmp.write_text(json.dumps(theme, indent=2))
            os.replace(tmp, ext / "themes" / "apply-theme-color-theme.json")
        except OSError:
            return

        settings_path = pathlib.Path.home() / ".config" / "Code" / "User" / "settings.json"
        if settings_path.is_file():
            try:
                raw = settings_path.read_text()
                data = json.loads(strip_jsonc(raw))
            except (OSError, ValueError):
                data = None
            if isinstance(data, dict):
                data["workbench.colorCustomizations"] = colors
                data["editor.tokenColorCustomizations"] = {"textMateRules": tokens}
                data["window.restoreWindows"] = "none"
                data["window.newWindowDimensions"] = "default"
                try:
                    tmp = settings_path.parent / ".settings.json.tmp"
                    tmp.write_text(json.dumps(data, indent=2))
                    os.replace(tmp, settings_path)
                except OSError:
                    pass

        index = ext_root / "extensions.json"
        entry = {
            "identifier": {"id": "caligo.apply-theme"},
            "version": "1.0.0",
            "location": {"$mid": 1, "path": str(ext), "scheme": "file"},
            "relativeLocation": ext.name,
            "metadata": {
                "installedTimestamp": 0,
                "pinned": True,
                "source": "vsix",
                "targetPlatform": "undefined",
                "updated": False,
                "private": False,
                "isPreReleaseVersion": False,
                "hasPreReleaseVersion": False,
            },
        }
        try:
            entries = json.loads(index.read_text()) if index.is_file() else []
            if not isinstance(entries, list):
                return
        except (OSError, ValueError):
            return
        kept = []
        for item in entries:
            ident = (item or {}).get("identifier") or {}
            if ident.get("id") == "caligo.apply-theme":
                entry["metadata"]["installedTimestamp"] = (
                    (item.get("metadata") or {}).get("installedTimestamp") or 0
                )
                continue
            kept.append(item)
        if not entry["metadata"]["installedTimestamp"]:
            entry["metadata"]["installedTimestamp"] = int(os.path.getmtime(ext) * 1000)
        kept.append(entry)
        try:
            tmp = ext_root / ".extensions.json.tmp"
            tmp.write_text(json.dumps(kept))
            os.replace(tmp, index)
        except OSError:
            return

    # write a Zen theme based on the given palette (not working atm)
    def write_zen_theme(p):
        profiles = browser_profiles()
        if not profiles:
            return
        bg = "#0b0b0c"
        bg2 = "#151517"
        fg = "#e8e8ea"
        muted = "#6e6e74"
        acc = "#d0d0d4"
        border = "rgba(232, 232, 234, 0.15)"
        stripes = "rgba(255, 255, 255, 0.05)"
        faint = "rgba(255, 255, 255, 0.04)"
        css = (
            "@namespace url(\"http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul\");\n"
            "/* Generated by render-theme — DO NOT hand-edit, overwritten on\n"
            "   every `apply-theme` call. */\n"
            + css_block(
                ":root",
                [
                    ("--lwt-accent-color", bg),
                    ("--lwt-text-color", fg),
                    ("--toolbar-bgcolor", bg2),
                    ("--toolbar-color", fg),
                    ("--toolbar-field-background-color", bg),
                    ("--toolbar-field-color", fg),
                    ("--toolbar-field-focus-background-color", bg),
                    ("--toolbar-field-border-color", muted),
                    ("--toolbar-field-focus-border-color", acc),
                    ("--toolbarbutton-icon-fill", fg),
                    ("--toolbarbutton-hover-background", rgba_hex(fg, "0.08")),
                    ("--toolbarbutton-active-background", rgba_hex(acc, "0.2")),
                    ("--tab-selected-bgcolor", bg),
                    ("--tab-selected-textcolor", fg),
                    ("--arrowpanel-background", bg2),
                    ("--arrowpanel-color", fg),
                    ("--arrowpanel-border-color", border),
                    ("--panel-background", bg2),
                    ("--panel-color", fg),
                    ("--panel-border-color", border),
                    ("--focus-outline-color", acc),
                    ("--zen-primary-color", acc),
                    ("--zen-colors-primary", bg2),
                    ("--zen-colors-secondary", bg),
                    ("--zen-colors-tertiary", bg),
                    ("--zen-colors-border", muted),
                    ("--zen-themed-toolbar-bg", bg2),
                    ("--zen-branding-bg", bg),
                ],
                important=True,
            )
            + css_block(
                "#navigator-toolbox, #titlebar, #TabsToolbar, #nav-bar, #PersonalToolbar, #zen-sidebar-bottom-buttons",
                [("background-color", bg2), ("border-radius", "0")],
                important=True,
            )
            + css_block(
                "#urlbar-background, #searchbar, .urlbarView, #urlbar-input-container",
                [
                    ("background-color", bg),
                    ("border", "1px solid " + muted),
                    ("border-radius", "0"),
                    ("box-shadow", "none"),
                ],
                important=True,
            )
            + css_block(
                "#urlbar[focused=\"true\"] > #urlbar-background, #searchbar:focus-within",
                [("border-color", acc)],
                important=True,
            )
            + css_block(
                ".tab-background, .tab-content, toolbarbutton, .toolbarbutton-1, menupopup, panel, .panel-arrowcontent",
                [("border-radius", "0")],
                important=True,
            )
            + css_block(
                ".tab-background[selected], .tab-background[multiselected], .tabbrowser-tab[selected] .tab-background, #zen-sidebar-web-panel-wrapper .tab-background[selected]",
                [
                    ("background-color", bg),
                    (
                        "background-image",
                        "repeating-linear-gradient(45deg, %s 0 6px, transparent 6px 12px)" % stripes,
                    ),
                    ("box-shadow", "inset 0 -2px 0 " + acc),
                ],
                important=True,
            )
            + css_block(
                ".tabbrowser-tab:hover .tab-background:not([selected])",
                [
                    (
                        "background-image",
                        "repeating-linear-gradient(45deg, %s 0 6px, transparent 6px 12px)" % faint,
                    ),
                ],
                important=True,
            )
            + css_block(
                ".tab-label",
                [("color", fg)],
                important=True,
            )
            + css_block(
                "#urlbar .urlbarView-row[selected] > .urlbarView-row-inner, .urlbarView-row:hover > .urlbarView-row-inner",
                [("background-color", rgba_hex(acc, "0.2")), ("color", fg), ("border-radius", "0")],
                important=True,
            )
            + css_block(
                "#zen-appcontent-navbar-container, .zen-view-splitter",
                [("background-color", bg2)],
                important=True,
            )
        )
        for profile in profiles:
            chrome = profile / "chrome"
            try:
                chrome.mkdir(parents=True, exist_ok=True)
                tmp = chrome / ".userChrome.css.tmp"
                tmp.write_text(css)
                os.replace(tmp, chrome / "userChrome.css")
            except OSError:
                continue

    # write an Obsidian theme based on the given palette
    def write_obsidian_theme(p):
        vaults = obsidian_vaults()
        if not vaults:
            return
        bg = "#" + p["background"]
        bg2 = "#" + p["background_secondary"]
        fg = "#" + p["text"]
        muted = "#" + p["text_inactive"]
        acc = "#" + p["accent"]
        err = "#" + p["error"]
        on_acc = accent_contrast_color(p)
        acc_text = readable(acc, [bg, bg2], 4.5, fg)
        border = rgba_hex(fg, "0.15")
        hover = mix_hex(bg, fg, 0.08)
        stripes = stripe_color(p)
        err_text = readable(err, [bg, bg2], 4.5, fg)
        faint = "rgba(0, 0, 0, 0.08)" if relative_brightness(p["text"]) >= 128 else "rgba(255, 255, 255, 0.08)"
        css = (
            "/* Generated by render-theme — DO NOT hand-edit, overwritten on\n"
            "   every `apply-theme` call. */\n"
            + css_block(
                "body",
                [
                    ("--background-primary", bg),
                    ("--background-primary-alt", bg2),
                    ("--background-secondary", bg2),
                    ("--background-secondary-alt", bg),
                    ("--background-modifier-border", border),
                    ("--background-modifier-border-hover", rgba_hex(fg, "0.25")),
                    ("--background-modifier-border-focus", acc),
                    ("--background-modifier-hover", hover),
                    ("--background-modifier-active-hover", rgba_hex(acc, "0.2")),
                    ("--background-modifier-error", err),
                    ("--text-normal", fg),
                    ("--text-muted", muted),
                    ("--text-faint", rgba_hex(muted, "0.6")),
                    ("--text-accent", acc_text),
                    ("--text-accent-hover", acc),
                    ("--text-on-accent", on_acc),
                    ("--text-error", err),
                    ("--text-selection", rgba_hex(acc, "0.3")),
                    ("--text-highlight-bg", rgba_hex(acc, "0.3")),
                    ("--interactive-normal", bg2),
                    ("--interactive-hover", hover),
                    ("--interactive-accent", acc),
                    ("--interactive-accent-hover", mix_hex(acc, fg, 0.15)),
                    ("--titlebar-background", bg2),
                    ("--titlebar-background-focused", bg2),
                    ("--titlebar-text-color", fg),
                    ("--tab-text-color-focused-active", fg),
                    ("--code-background", bg2),
                    ("--code-normal", fg),
                    ("--hr-color", border),
                    ("--divider-color", border),
                    ("--scrollbar-thumb-bg", rgba_hex(fg, "0.2")),
                    ("--scrollbar-active-thumb-bg", acc),
                    ("--font-text-theme", "'Iosevka SKYC'"),
                    ("--font-interface-theme", "'Iosevka SKYC'"),
                    ("--font-monospace-theme", "'Iosevka SKYC'"),
                    ("--h1-color", fg),
                    ("--h2-color", fg),
                    ("--h3-color", acc_text),
                    ("--h4-color", acc_text),
                    ("--h5-color", muted),
                    ("--h6-color", muted),
                    ("--radius-s", "0"),
                    ("--radius-m", "0"),
                    ("--radius-l", "0"),
                    ("--radius-xl", "0"),
                    ("--input-radius", "0"),
                    ("--button-radius", "0"),
                    ("--tab-radius", "0"),
                    ("--tab-radius-active", "0"),
                    ("--tab-curve", "0"),
                    ("--tab-outline-radius", "0"),
                    ("--modal-radius", "0"),
                    ("--checkbox-radius", "0"),
                    ("--toggle-radius", "0"),
                    ("--toggle-thumb-radius", "0"),
                    ("--slider-thumb-radius", "0"),
                    ("--prompt-border-radius", "0"),
                    ("--icon-color-focused", acc),
                ],
            )
            + css_block(
                ".nav-file-title.is-active, .nav-folder-title.is-active, .tree-item-self.is-clickable.is-active, .suggestion-item.is-selected, .menu-item.selected",
                [
                    (
                        "background-image",
                        "repeating-linear-gradient(45deg, %s 0 6px, transparent 6px 12px)" % stripes,
                    ),
                    ("background-color", rgba_hex(acc, "0.18")),
                    ("box-shadow", "inset 2px 0 0 " + acc),
                ],
                important=True,
            )
            + css_block(
                ".workspace-tab-header.is-active",
                [
                    ("background-color", bg),
                    (
                        "background-image",
                        "repeating-linear-gradient(45deg, %s 0 6px, transparent 6px 12px)" % stripes,
                    ),
                    ("box-shadow", "inset 0 -2px 0 " + acc),
                ],
                important=True,
            )
            + css_block(
                ".titlebar-button-container.mod-right, .titlebar-button.mod-minimize, .titlebar-button.mod-maximize, .titlebar-button.mod-close",
                [("display", "none")],
                important=True,
            )
            + css_block(
                "button:not(.clickable-icon), input[type=\"text\"], input[type=\"search\"], input[type=\"number\"], textarea, .dropdown",
                [
                    ("background-color", rgba_hex(fg, "0.06")),
                    ("border", "1px solid " + muted),
                    ("box-shadow", "none"),
                    ("color", fg),
                ],
                important=True,
            )
            + css_block(
                "button:not(.clickable-icon):hover, input[type=\"text\"]:focus, input[type=\"search\"]:focus, textarea:focus, .dropdown:hover",
                [
                    ("border-color", acc),
                    (
                        "background-image",
                        "repeating-linear-gradient(45deg, %s 0 6px, transparent 6px 12px)" % faint,
                    ),
                ],
                important=True,
            )
            + css_block(
                "button.mod-cta",
                [
                    ("background-color", rgba_hex(acc, "0.12")),
                    ("border", "1px solid " + acc),
                    ("color", acc_text),
                ],
                important=True,
            )
            + css_block(
                "button.mod-warning, button.mod-destructive",
                [
                    ("background-color", rgba_hex(err, "0.12")),
                    ("border", "1px solid " + err),
                    ("color", err_text),
                ],
                important=True,
            )
            + css_block(
                "button.mod-warning:hover, button.mod-destructive:hover",
                [
                    ("border-color", err),
                    ("background-color", rgba_hex(err, "0.2")),
                    (
                        "background-image",
                        "repeating-linear-gradient(45deg, %s 0 6px, transparent 6px 12px)" % faint,
                    ),
                ],
                important=True,
            )
            + css_block(
                ".checkbox-container.is-enabled",
                [("background-color", acc), ("border", "1px solid " + acc)],
                important=True,
            )
            + css_block(
                ".checkbox-container.is-enabled::after",
                [("background-color", on_acc)],
                important=True,
            )
            + css_block(
                "input[type=\"range\"]",
                [
                    ("--slider-track-background", rgba_hex(fg, "0.15")),
                    ("--slider-thumb-border-color", acc),
                    ("accent-color", acc),
                ],
                important=True,
            )
            + css_block(
                "input[type=\"range\"]::-webkit-slider-thumb",
                [("background-color", acc), ("border", "none")],
                important=True,
            )
            + css_block(
                ".workspace-tab-header, .workspace-tab-header-inner, .workspace-tab-header-container, .workspace-tab-container, .workspace-tabs, .workspace-leaf, .workspace-leaf-content, .view-content, .markdown-source-view, .markdown-preview-view, input, textarea, button, .search-input-container, .search-input-container input, .prompt, .modal, .menu, .suggestion-container",
                [("border-radius", "0")],
                important=True,
            )
            + css_block(
                ".workspace-tab-header::before, .workspace-tab-header::after, .workspace-tab-header-inner::before, .workspace-tab-header-inner::after",
                [("display", "none")],
                important=True,
            )
        )
        for vault in vaults:
            snippets = vault / ".obsidian" / "snippets"
            try:
                snippets.mkdir(parents=True, exist_ok=True)
                tmp = snippets / ".apply-theme.css.tmp"
                tmp.write_text(css)
                os.replace(tmp, snippets / "apply-theme.css")
            except OSError:
                continue

    # write a Vesktop theme based on the given palette
    def write_vesktop_theme(p):
        if not VESKTOP_DIR.is_dir():
            return
        bg = "#" + p["background"]
        bg2 = "#" + p["background_secondary"]
        text = "#" + p["text"]
        sub = "#" + p["text_inactive"]
        accent = "#" + p["accent"]
        err = "#" + p["error"]
        neutral = mix_hex(text, bg, 0.5)
        bg1 = mix_hex(bg2, text, 0.08)
        bg3 = mix_hex(bg, bg2, 0.40)
        panels = [bg, bg3, bg2]
        colors = [
            ("--colors", "on"),
            ("--text-0", accent_contrast_color(p)),
            ("--text-1", text),
            ("--text-2", readable(mix_hex(text, bg, 0.10), panels, 7.0, text)),
            ("--text-3", readable(mix_hex(text, bg, 0.20), panels, 6.0, text)),
            ("--text-4", readable(mix_hex(text, sub, 0.55), panels, 4.5, text)),
            ("--text-5", readable(sub, panels, 3.0, text)),
            ("--bg-1", bg1),
            ("--bg-2", bg2),
            ("--bg-3", bg3),
            ("--bg-4", bg),
            ("--hover", rgba_hex(neutral, 0.1)),
            ("--active", rgba_hex(neutral, 0.2)),
            ("--active-2", rgba_hex(neutral, 0.3)),
            ("--message-hover", "var(--hover)"),
            ("--accent-1", mix_hex(accent, text, 0.20)),
            ("--accent-2", accent),
            ("--accent-3", accent),
            ("--accent-4", mix_hex(accent, text, 0.10)),
            ("--accent-5", mix_hex(accent, bg, 0.15)),
            ("--accent-new", err),
            ("--username-outline", "rgba(0, 0, 0, 0.85)"),
            ("--selected-stripe-a", accent),
            ("--selected-stripe-b", mix_hex(accent, "ffffff", 0.23)),
            ("--mention", "linear-gradient(to right, color-mix(in hsl, var(--accent-2), transparent 90%) 40%, transparent)"),
            ("--mention-hover", "linear-gradient(to right, color-mix(in hsl, var(--accent-2), transparent 95%) 40%, transparent)"),
            ("--reply", "linear-gradient(to right, color-mix(in hsl, var(--text-3), transparent 90%) 40%, transparent)"),
            ("--reply-hover", "linear-gradient(to right, color-mix(in hsl, var(--text-3), transparent 95%) 40%, transparent)"),
            ("--online", "var(--green-2)"),
            ("--dnd", "var(--red-2)"),
            ("--idle", "var(--yellow-2)"),
            ("--streaming", "var(--purple-2)"),
            ("--offline", "var(--text-4)"),
            ("--border-light", "var(--hover)"),
            ("--border", "var(--active)"),
            ("--border-hover", "var(--accent-2)"),
            ("--button-border", rgba_hex(text, 0.1)),
            ("--red-1", mix_hex(err, text, 0.15)),
            ("--red-2", err),
            ("--red-3", mix_hex(err, bg, 0.08)),
            ("--red-4", mix_hex(err, bg, 0.16)),
            ("--red-5", mix_hex(err, bg, 0.24)),
            ("--green-1", "oklch(75% 0.12 170)"),
            ("--green-2", "oklch(70% 0.12 170)"),
            ("--green-3", "oklch(65% 0.12 170)"),
            ("--green-4", "oklch(60% 0.12 170)"),
            ("--green-5", "oklch(55% 0.12 160)"),
            ("--blue-1", "oklch(75% 0.11 215)"),
            ("--blue-2", "oklch(70% 0.11 215)"),
            ("--blue-3", "oklch(65% 0.11 215)"),
            ("--blue-4", "oklch(60% 0.11 215)"),
            ("--blue-5", "oklch(55% 0.11 215)"),
            ("--yellow-1", "oklch(80% 0.12 90)"),
            ("--yellow-2", "oklch(75% 0.12 90)"),
            ("--yellow-3", "oklch(70% 0.12 90)"),
            ("--yellow-4", "oklch(65% 0.12 90)"),
            ("--yellow-5", "oklch(60% 0.12 90)"),
            ("--purple-1", "oklch(75% 0.12 310)"),
            ("--purple-2", "oklch(70% 0.12 310)"),
            ("--purple-3", "oklch(65% 0.12 310)"),
            ("--purple-4", "oklch(60% 0.12 310)"),
            ("--purple-5", "oklch(55% 0.12 310)"),
        ]
        native = [
            ("--background-primary", "var(--bg-4)"),
            ("--background-secondary", "var(--bg-4)"),
            ("--background-secondary-alt", "var(--bg-3)"),
            ("--background-tertiary", "var(--bg-4)"),
            ("--background-accent", "var(--bg-2)"),
            ("--background-floating", "var(--bg-3)"),
            ("--background-nested-floating", "var(--bg-2)"),
            ("--background-mobile-primary", "var(--bg-4)"),
            ("--background-mobile-secondary", "var(--bg-4)"),
            ("--background-base-lowest", "var(--bg-4)"),
            ("--background-base-lower", "var(--bg-4)"),
            ("--background-base-low", "var(--bg-4)"),
            ("--background-surface-high", "var(--bg-3)"),
            ("--background-surface-higher", "var(--bg-2)"),
            ("--background-surface-highest", "var(--bg-1)"),
            ("--background-gradient-lowest", "var(--bg-4)"),
            ("--background-gradient-lower", "var(--bg-4)"),
            ("--background-gradient-low", "var(--bg-4)"),
            ("--background-gradient-high", "var(--bg-3)"),
            ("--background-gradient-higher", "var(--bg-2)"),
            ("--background-gradient-highest", "var(--bg-1)"),
            ("--background-gradient-chat", "var(--bg-4)"),
            ("--__header-bar-background", "var(--bg-4)"),
            ("--bg-base-primary", "var(--bg-4)"),
            ("--bg-base-secondary", "var(--bg-4)"),
            ("--bg-base-tertiary", "var(--bg-4)"),
            ("--bg-surface-overlay", "var(--bg-3)"),
            ("--bg-surface-raised", "var(--bg-3)"),
            ("--chat-background", "var(--bg-4)"),
            ("--chat-background-default", "var(--bg-4)"),
            ("--channeltextarea-background", "var(--bg-3)"),
            ("--input-background", "var(--bg-3)"),
            ("--input-background-default", "var(--bg-3)"),
            ("--modal-background", "var(--bg-3)"),
            ("--modal-footer-background", "var(--bg-4)"),
            ("--home-background", "var(--bg-4)"),
            ("--deprecated-card-bg", "var(--bg-3)"),
            ("--text-normal", "var(--text-3)"),
            ("--text-default", "var(--text-3)"),
            ("--text-strong", "var(--text-2)"),
            ("--text-muted", "var(--text-5)"),
            ("--text-subtle", "var(--text-4)"),
            ("--text-link", "var(--accent-1)"),
            ("--header-primary", "var(--text-2)"),
            ("--header-secondary", "var(--text-4)"),
            ("--channels-default", "var(--text-4)"),
            ("--interactive-normal", "var(--text-4)"),
            ("--interactive-hover", "var(--text-2)"),
            ("--interactive-active", "var(--text-1)"),
            ("--interactive-muted", "var(--text-5)"),
            ("--interactive-text-default", "var(--text-4)"),
            ("--interactive-text-hover", "var(--text-2)"),
            ("--interactive-text-active", "var(--text-1)"),
            ("--icon-default", "var(--text-4)"),
            ("--icon-subtle", "var(--text-4)"),
            ("--icon-muted", "var(--text-5)"),
            ("--icon-strong", "var(--text-2)"),
        ]
        css = (
            '@import url("https://refact0r.github.io/system24/build/system24.css");\n\n'
            + css_block("body", SYSTEM24_SETTINGS)
            + "\n"
            + css_block(":root", colors)
            + "\n"
            + css_block(":root, .theme-dark, .theme-darker, .theme-midnight, .theme-light, .visual-refresh", native, important=True)
            + "\n"
            + css_block('[class*="username_"]', [
                ("text-shadow",
                 "-1px -1px 0 var(--username-outline), 0 -1px 0 var(--username-outline), "
                 "1px -1px 0 var(--username-outline), 1px 0 0 var(--username-outline), "
                 "1px 1px 0 var(--username-outline), 0 1px 0 var(--username-outline), "
                 "-1px 1px 0 var(--username-outline), -1px 0 0 var(--username-outline)"),
            ], important=True)
            + "\n"
            + css_block('[data-username-with-effects], [data-username-with-effects] *', [
                ("text-shadow", "none"),
            ], important=True)
            + "\n"
            + css_block('[class*="modeSelected_"] [class*="link_"], [class*="interactiveSelected_"], [class*="folderGroupBackground_"], [class*="folderIconWrapper_"]', [
                ("background-image",
                 "repeating-linear-gradient(-45deg, "
                 "var(--selected-stripe-a) 0, var(--selected-stripe-a) 6px, "
                 "var(--selected-stripe-b) 6px, var(--selected-stripe-b) 12px)"),
            ], important=True)
            + "\n"
            + css_block('[class*="modeSelected_"] [class*="link_"] [class*="name_"], [class*="modeSelected_"] [class*="link_"] svg, [class*="interactiveSelected_"] [class*="name_"], [class*="interactiveSelected_"] [class*="subText_"], [class*="interactiveSelected_"] svg', [
                ("color", "var(--text-0)"),
            ], important=True)
            + "\n"
            + css_block('nav[class*="guilds_"], [data-list-id="guildsnav"], [data-list-id="guildsnav"] [class*="scroller_"]', [
                ("background", "var(--bg-4)"),
            ], important=True)
            + "\n"
            + css_block('[class*="topicsPillContainer_"], [class*="search_"], [class*="channelTextArea_"], [class*="channelTextArea_"] [class*="scrollableContainer_"]', [
                ("background", "var(--bg-3)"),
            ], important=True)
        )
        themes = VESKTOP_DIR / "themes"
        themes.mkdir(parents=True, exist_ok=True)
        tmp = themes / ".system24.theme.css.tmp"
        tmp.write_text(css)
        os.replace(tmp, themes / "system24.theme.css")

    # main function. renders the theme
    def main():
        themes = load_themes()

        if 2 <= len(sys.argv) <= 4 and sys.argv[1] == "list":
            mode = sys.argv[2] if len(sys.argv) >= 3 else "any"
            skip_vivid = len(sys.argv) == 4 and sys.argv[3] == "novivid"
            for name in sorted(themes):
                bg = themes[name]["bg"]
                light = relative_brightness(bg) >= 128
                if mode != "any" and (mode == "light") != light:
                    continue
                if skip_vivid:
                    _, l, s = colorsys.rgb_to_hls(*[int(hex_clean(bg)[i:i + 2], 16) / 255 for i in (0, 2, 4)])
                    if s * (1 - abs(2 * l - 1)) >= 0.5:
                        continue
                print(name)
            return

        if len(sys.argv) != 3 or sys.argv[1] not in themes or sys.argv[2] not in VALID_SHADERS:
            sys.stderr.write(
                "usage: render-theme <monkeytype-theme-name> <%s>\n"
                "       render-theme list   (print all available theme names)\n"
                % "|".join(VALID_SHADERS)
            )
            sys.exit(1)

        theme, shader = sys.argv[1], sys.argv[2]
        colors = themes[theme]
        template = (CONFIG / "templates" / f"{shader}.frag.tmpl").read_text()

        rendered = template
        for name, hexval in colors.items():
            rendered = rendered.replace(f"@{name.upper()}@", hex_to_vec3(hexval))

        SHADERBG_CACHE.mkdir(parents=True, exist_ok=True)
        (SHADERBG_CACHE / "live.frag").write_text(rendered)
        (SHADERBG_CACHE / "state").write_text(f"theme={theme}\nshader={shader}\n")

        palette = derive_palette(colors)
        write_hypr_colors(palette)
        write_alacritty_colors(palette)
        write_gtk_css(palette)
        write_wayle_theme(palette)
        write_walker_colors(palette)
        write_hyprlock_colors(palette)
        write_vesktop_theme(palette)
        write_obsidian_theme(palette)
        write_zen_theme(palette)
        write_vscode_theme(palette)


    if __name__ == "__main__":
        main()
  '';

  # wallpaper-shader [stop|<path>] — kills any running shaderbg and
  # relaunches it. No args -> ~/.cache/shaderbg/live.frag (generating a
  # sensible default via render-theme if this is the very first run and
  # nothing's been themed yet). `stop` just kills it. Any other argument is
  # treated as a literal shader path, for trying out an arbitrary .frag
  # (e.g. a downloaded Shadertoy shader) without touching the theme system
  # at all.
  wallpaper-shader = pkgs.writeShellScriptBin "wallpaper-shader" ''
    set -u
    live="$HOME/.cache/shaderbg/live.frag"
    arg="''${1:-}"

    pkill -x shaderbg 2>/dev/null || true

    if [ "$arg" = "stop" ]; then
      exit 0
    fi

    if [ -n "$arg" ]; then
      shader="$arg"
    else
      if [ ! -f "$live" ]; then
        ${render-theme}/bin/render-theme catppuccin simplex
      fi
      shader="$live"
    fi

    sleep 0.2
    # setsid + fully-redirected streams + background (not `exec`): shaderbg
    # needs to outlive whatever invoked this script — Hyprland's exec-once,
    # or a terminal you ran `apply-theme`/`wallpaper-shader` from by hand.
    # `exec` here would make shaderbg literally BECOME that shell process,
    # which is why closing/exiting the terminal killed the wallpaper along
    # with it, and why the terminal never returned to a prompt. setsid
    # detaches it into its own session so it's independent of whatever
    # terminal (if any) launched it.
    setsid ${shaderbg}/bin/shaderbg --layer background '*' "$shader" \
      > /tmp/shaderbg.log 2>&1 < /dev/null &
    disown
  '';

  # apply-theme [<monkeytype-theme-name>|random] [simplex|warp] — the ONE
  # command that reskins everything: wallpaper, Hyprland border/shadow/bg
  # colors, and GTK app colors, all from a single Monkeytype theme name.
  # Shader arg is optional: omit it to keep whatever's currently selected
  # (read from ~/.cache/shaderbg/state), so e.g. `apply-theme bushido` alone
  # just recolors everything using whichever shader is already running.
  # `apply-theme list` prints every available theme name (all 187, one per
  # line — pipe it through `grep`/`fzf` to browse: `apply-theme list | fzf`).
  # Called with NO theme name at all, it hands that same list to Walker's
  # `--dmenu` mode instead of just erroring, so `apply-theme` alone opens an
  # interactive fuzzy picker (same stdin-list/stdout-selection contract as
  # the old `rofi -dmenu`, confirmed from Walker's own docs) — cancel with
  # Escape and it falls through to the usual usage message, same as before.
  #
  # After render-theme regenerates every output file, `hyprctl reload` forces
  # Hyprland to re-read its config (including sourced files) immediately —
  # Hyprland is generally expected to pick up a changed sourced file on its
  # own via its file watcher, but this makes it unconditional rather than
  # relying on that. GTK apps do NOT hot-reload gtk.css; already-open Thunar
  # windows etc. need a restart to pick up the new colors, same as any other
  # GTK theme change. The wallpaper swap itself is a sub-second restart of
  # shaderbg, not a live crossfade (shaderbg has no channel for pushing new
  # uniforms into a running process).
  apply-theme = pkgs.writeShellScriptBin "apply-theme" ''
    set -u
    state="$HOME/.cache/shaderbg/state"

    # apply-theme list — used to just dump names to stdout and exit
    # immediately, which only made sense from a terminal. Now it opens the
    # exact same Walker picker as bare `apply-theme` (below) so it behaves
    # the same whether it's typed in a terminal or launched from Walker's
    # own "Apply Theme" entry. `apply-theme list warp` still works — the
    # second word is kept as the shader arg either way.
    modefile="$HOME/.cache/theme/mode"
    vividfile="$HOME/.cache/theme/vivid"
    if [ "''${1:-}" = "vivid" ]; then
      current=$(cat "$vividfile" 2>/dev/null || echo on)
      case "''${2:-}" in
        on|off) next="$2" ;;
        toggle) if [ "$current" = on ]; then next=off; else next=on; fi ;;
        "") echo "$current"; exit 0 ;;
        *) echo "usage: apply-theme vivid [on|off|toggle] [--notify]" >&2; exit 1 ;;
      esac
      mkdir -p "$(dirname "$vividfile")"
      echo "$next" > "$vividfile"
      if [ "$next" = on ]; then
        msg="Saturated themes can be selected!"
      else
        msg="Saturated themes will be skipped!"
      fi
      echo "$msg"
      if [ "''${3:-}" = "--notify" ]; then
        ${pkgs.libnotify}/bin/notify-send --app-name=Theme --icon=preferences-desktop-theme "Random theme mode" "$msg"
      fi
      exit 0
    fi

    if [ "''${1:-}" = "mode" ]; then
      current=$(cat "$modefile" 2>/dev/null || echo any)
      case "''${2:-}" in
        light|dark|any) next="$2" ;;
        toggle)
          case "$current" in
            light) next=dark ;;
            dark) next=any ;;
            *) next=light ;;
          esac
          ;;
        "") echo "$current"; exit 0 ;;
        *) echo "usage: apply-theme mode [light|dark|any|toggle] [--notify]" >&2; exit 1 ;;
      esac
      mkdir -p "$(dirname "$modefile")"
      echo "$next" > "$modefile"
      case "$next" in
        light) msg="Only light themes will be selected!" ;;
        dark) msg="Only dark themes will be selected!" ;;
        *) msg="All themes will be selected!" ;;
      esac
      echo "$msg"
      if [ "''${3:-}" = "--notify" ]; then
        ${pkgs.libnotify}/bin/notify-send --app-name=Theme --icon=preferences-desktop-theme "Random theme mode" "$msg"
      fi
      exit 0
    fi

    if [ "''${1:-}" = "list" ]; then
      theme=$(${render-theme}/bin/render-theme list | walker --dmenu --placeholder "Pick a theme")
      shader="''${2:-}"
    else
      theme="''${1:-}"
      shader="''${2:-}"
    fi

    # apply-theme random [simplex|warp] — picks one of all 187 Monkeytype
    # themes plus anything in custom.json, uniformly at random, and applies
    # it exactly like naming it directly. `render-theme list` is the same
    # merged name list `apply-theme list` prints, so this can never pick a
    # name that doesn't actually exist.
    if [ "$theme" = "random" ]; then
      mode=$(cat "$modefile" 2>/dev/null || echo any)
      vivid=$(cat "$vividfile" 2>/dev/null || echo on)
      filter=""
      [ "$vivid" = off ] && filter=novivid
      theme=$(${render-theme}/bin/render-theme list "$mode" $filter | shuf -n1)
    fi

    # apply-theme, with nothing else on the command line — interactive pick
    # via Walker instead of immediately failing. Whatever comes back on
    # stdout is one of the exact names `render-theme list` printed (or
    # nothing at all, if you hit Escape), so it's always safe to fall
    # through to the theme lookup below with no separate validation step.
    if [ -z "$theme" ]; then
      theme=$(${render-theme}/bin/render-theme list | walker --dmenu --placeholder "Pick a theme")
    fi

    if [ -z "$theme" ]; then
      echo "usage: apply-theme [<monkeytype-theme-name>|random] [simplex|warp|balatro|lines|halftone|solid]" >&2
      echo "       apply-theme list   (print all available theme names)" >&2
      echo "       apply-theme        (pick one interactively via Walker)" >&2
      exit 1
    fi

    if [ -z "$shader" ]; then
      shader=$(grep -m1 '^shader=' "$state" 2>/dev/null | cut -d= -f2)
      shader="''${shader:-simplex}"
    fi

    ${render-theme}/bin/render-theme "$theme" "$shader"
    hyprctl reload >/dev/null 2>&1 || true

    gtk_slot=$(cat "$HOME/.cache/theme/gtk-slot" 2>/dev/null || true)
    if [ -n "$gtk_slot" ]; then
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'$gtk_slot'" || true
    fi

    exec ${wallpaper-shader}/bin/wallpaper-shader
  '';
in
{
  home.packages = [
    shaderbg
    render-theme
    wallpaper-shader
    apply-theme
  ];

  # Makes `apply-theme` itself show up as a normal launchable item in
  # Walker's default search (the "desktopapplications" provider), typing
  # "theme" or "apply" finds it same as any installed app — instead of only
  # being runnable by typing its exact command name via Walker's `>` runner
  # prefix. No arguments here on purpose: running it bare triggers the
  # no-args branch inside apply-theme itself, which opens ITS OWN
  # `walker --dmenu` theme picker — so selecting "Apply Theme" from the
  # main Walker window immediately chains into the interactive theme list.
  xdg.desktopEntries.apply-theme = {
    name = "Apply Theme";
    genericName = "Theme Picker";
    comment = "Pick a Monkeytype-derived theme for the wallpaper, Hyprland, GTK apps, and Walker itself";
    exec = "apply-theme";
    icon = "preferences-desktop-theme";
    terminal = false;
    categories = [ "Settings" ];
    # Alternate search terms — same idea as the aliases you want on the
    # other custom commands, just using the desktop-entry spec's own
    # built-in field for it rather than anything Walker-specific. Home
    # Manager's xdg.desktopEntries module has no first-class `keywords`
    # option (only `actions`/`settings`/`categories`, per the eval error —
    # it suggested `settings`) — `Keywords` is a real Desktop Entry
    # Specification key regardless, it just has to go through the generic
    # `settings` passthrough, semicolon-terminated per that spec.
    settings.Keywords = "theme;colors;colorscheme;monkeytype;wallpaper;";
  };

  # Templates and palettes: plain, home-manager-managed (read-only) files
  # under ~/.config/shaderbg/. render-theme reads these at runtime to build
  # ~/.cache/shaderbg/live.frag, which is the one mutable, non-Nix-managed
  # file in this whole pipeline.
  xdg.configFile = {
    "shaderbg/templates/simplex.frag.tmpl".source = ./assets/templates/simplex.frag.tmpl;
    "shaderbg/templates/warp.frag.tmpl".source = ./assets/templates/warp.frag.tmpl;
    "shaderbg/templates/balatro.frag.tmpl".source = ./assets/templates/balatro.frag.tmpl;
    "shaderbg/templates/lines.frag.tmpl".source = ./assets/templates/lines.frag.tmpl;
    "shaderbg/templates/halftone.frag.tmpl".source = ./assets/templates/halftone.frag.tmpl;
    "shaderbg/templates/solid.frag.tmpl".source = ./assets/templates/solid.frag.tmpl;
    "shaderbg/templates/black.frag.tmpl".source = ./assets/templates/black.frag.tmpl;

    # All 187 Monkeytype built-in themes, imported from their public repo
    # (frontend/src/ts/constants/themes.ts) as one JSON file: { "theme_name":
    # { bg, caret, main, sub, subAlt, text, error, errorExtra, colorfulError,
    # colorfulErrorExtra }, ... }. `apply-theme list` prints the names.
    "shaderbg/palettes/monkeytype.json".source = ./assets/palettes/monkeytype.json;

    # No custom.json entry here on purpose: you decided against a fixed
    # hand-defined palette (the old "navy-orange" idea) in favor of always
    # deriving colors from whichever real Monkeytype theme is active. If you
    # ever DO want a hand-defined theme later, load_themes() below already
    # merges one in if it happens to exist at ~/.config/shaderbg/palettes/
    # custom.json — you'd just drop a file there yourself; nothing here
    # needs to change, since that path isn't Nix-managed at all now.
  };

  # hyprland.nix sources ~/.cache/theme/hypr-colors.conf, and Hyprland reads
  # that file at startup, BEFORE any exec-once command runs — so we can't
  # rely on a script to create it, it has to already exist by the time
  # Hyprland itself parses its config, every single login. This activation
  # hook writes a Catppuccin Mocha fallback the FIRST time only (never
  # touches an existing file), so a fresh install doesn't hit a missing-file
  # config error, while your actual chosen theme survives every future
  # rebuild untouched. Run `apply-theme <name>` once and this default is
  # irrelevant from then on.
  #
  # entryBefore "writeBoundary" (not entryAfter): this has to create the
  # fallback file BEFORE home-manager relinks hyprland.conf itself. With
  # entryAfter, there's a window during activation where the NEW
  # hyprland.conf (with its `source =` line) is already on disk, Hyprland's
  # own file-watcher notices and tries to reload immediately, but this
  # script hasn't run yet — hitting exactly the "globbing error: found no
  # match" you saw, since the sourced file doesn't exist yet at that instant.
  home.activation.themeEngineBootstrap = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        THEME_CACHE="$HOME/.cache/theme"
        mkdir -p "$THEME_CACHE" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"

        if [ ! -f "$THEME_CACHE/hypr-colors.conf" ]; then
          cat > "$THEME_CACHE/hypr-colors.conf" <<'THEMEEOF'
    general {
        col.active_border = rgba(cba6f7ee) rgba(cba6f766) 45deg
        col.inactive_border = rgba(313244aa)
    }
    misc {
        background_color = rgb(1e1e2e)
    }
    plugin {
        borders-plus-plus {
            col.border_1 = rgba(1e1e2eff)
        }
        hyprexpo {
            bg_col = rgba(1e1e2eff)
            border_color_current = rgba(cba6f7ff)
        }
    }
    THEMEEOF
        fi

        if [ ! -f "$HOME/.config/gtk-3.0/gtk.css" ]; then
          cat > "$HOME/.config/gtk-3.0/gtk.css" <<'THEMEEOF'
    @define-color window_bg_color #1e1e2e;
    @define-color window_fg_color #cdd6f4;
    @define-color view_bg_color #313244;
    @define-color view_fg_color #cdd6f4;
    @define-color headerbar_bg_color #313244;
    @define-color headerbar_fg_color #cdd6f4;
    @define-color accent_color #cba6f7;
    @define-color accent_bg_color #cba6f7;
    @define-color theme_bg_color #1e1e2e;
    @define-color theme_fg_color #cdd6f4;
    @define-color theme_text_color #cdd6f4;
    @define-color theme_base_color #1e1e2e;
    THEMEEOF
          cp "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
        fi

        if [ ! -f "$THEME_CACHE/alacritty-colors.toml" ]; then
          # Same Catppuccin Mocha fallback values as everything else above,
          # hand-computed to match write_alacritty_colors()'s logic exactly
          # (workspace-rainbow ANSI colors, +15% lightened bright variants).
          cat > "$THEME_CACHE/alacritty-colors.toml" <<'THEMEEOF'
    [colors.primary]
    background = "#1e1e2e"
    foreground = "#cdd6f4"

    [colors.cursor]
    text = "#1e1e2e"
    cursor = "#cba6f7"

    [colors.normal]
    black = "#1e1e2e"
    red = "#df9090"
    green = "#a0df90"
    yellow = "#dfbf90"
    blue = "#90b0df"
    magenta = "#df90bf"
    cyan = "#90dfdf"
    white = "#cdd6f4"

    [colors.bright]
    black = "#313244"
    red = "#e3a0a0"
    green = "#aee3a0"
    yellow = "#e3c8a0"
    blue = "#a0bbe3"
    magenta = "#e3a0c8"
    cyan = "#a0e3e3"
    white = "#dce2f7"
    THEMEEOF
        fi

        if [ ! -f "$THEME_CACHE/hyprlock-colors.conf" ]; then
          cat > "$THEME_CACHE/hyprlock-colors.conf" <<'THEMEEOF'
    $bgColor = rgba(1e1e2ee6)
    $surfaceColor = rgba(313244ff)
    $accentColor = rgba(cba6f7ff)
    $textColor = rgba(cdd6f4ff)
    $textMutedColor = rgba(a6adc8ff)
    THEMEEOF
        fi

        if [ ! -f "$THEME_CACHE/lock-bg.png" ]; then
          # A real (tiny, hand-encoded) solid #1e1e2e PNG, base64-inlined —
          # same Catppuccin Mocha fallback as everything else above, decoded
          # rather than generated here since this activation script is plain
          # bash, not Python. Overwritten with the real theme's color the
          # moment `apply-theme` runs once.
          base64 -d > "$THEME_CACHE/lock-bg.png" <<'THEMEEOF'
    iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3PQQkAAAgEsEtyEewfzwi+hcEKLO28FgEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQGBywKOJKBbJJnqNAAAAABJRU5ErkJggg==
    THEMEEOF
        fi
  '';
}
