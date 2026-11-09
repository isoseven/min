{
  config,
  pkgs,
  inputs,
  ...
}:

let
  # Custom Iosevka build — see fonts/private-build-plans.toml for the plan.
  # `set` must satisfy "Iosevka" + set == the [buildPlans.X] key in that file
  # (currently [buildPlans.IosevkaSkyc]).
  iosevka-skyc = pkgs.iosevka.override {
    set = "Skyc";
    privateBuildPlan = builtins.readFile ../../fonts/private-build-plans.toml;
  };
in
{
  imports = [
    # IMPORTANT: keep using the hardware-configuration.nix that
    # `nixos-generate-config` already made for you — don't replace it with
    # this repo's version (there isn't one here on purpose). Just copy this
    # whole repo next to your existing /etc/nixos/hardware-configuration.nix,
    # or copy that file into hosts/nixos/ and uncomment the next line:
    ./hardware-configuration.nix

  ];

  # --- Boot -----------------------------------------------------------
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Only keep the 3 most recent generations as boot entries. Note: this
  # only trims the boot MENU — the older generations' store paths still
  # exist on disk until garbage-collected (`nix-collect-garbage -d` or a
  # `nix.gc` schedule) if you also want to reclaim that space.
  boot.loader.systemd-boot.configurationLimit = 3;

  # --- Networking -------------------------------------------------------
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # --- Locale / time ------------------------------------------------------
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  console.keyMap = "us";

  # --- Users ------------------------------------------------------------
  # Already set to your chosen username. Rename "caligo" here (and in
  # flake.nix's home-manager.users.<name>) if you ever want a different one.
  users.users.caligo = {
    isNormalUser = true;
    description = "Caligo";
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "audio"
    ];
    shell = pkgs.zsh;

    # Sets your login password the FIRST time this config is activated on a
    # fresh account (NixOS won't touch it again after that, so `passwd`
    # afterwards to change it is safe and expected — this is meant as a
    # bootstrap password, not a permanent one).
    #
    # SECURITY NOTE: this is stored in plaintext in the Nix store (world
    # readable on this machine) and right here in this file. That's fine for
    # your own private use, but don't push this repo anywhere public
    # (GitHub, etc.) with this line still in it — either delete the line
    # once you've logged in and changed your password, or swap it for
    # `hashedPasswordFile`/`hashedPassword` (via `mkpasswd -m sha-512`)
    # before sharing this config with anyone.
    initialPassword = "changeme";
  };

  # Second personal profile, shares the same desktop setup (theme engine,
  # bar, lock screen, keybinds) via home/achlys/home.nix, with a much
  # smaller app list. Same bootstrap-password caveat as caligo above.
  users.users.achlys = {
    isNormalUser = true;
    description = "Achlys";
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "audio"
    ];
    shell = pkgs.zsh;
    initialPassword = "changeme";
  };

  programs.zsh.enable = true;

  security.sudo.extraRules = [
    {
      users = [ "caligo" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/nix-collect-garbage";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/nix-env";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/nix-store";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # --- Hyprland -----------------------------------------------------------
  programs.hyprland = {
    enable = true;
    xwayland.enable = true; # lets normal X11 apps still run
  };

  # Portals: needed for screen sharing, file pickers from sandboxed apps,
  # screenshot tools, etc. to work correctly under Wayland/Hyprland.
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    configPackages = [ pkgs.hyprland ];
  };

  # dconf daemon — required for gtk.nix's dark-mode dconf.settings (and any
  # other home-manager dconf.settings) to actually apply; without this at
  # the system level, home-manager can write the dconf profile but nothing
  # reads it back.
  programs.dconf.enable = true;

  # A GUI polkit agent so graphical apps can prompt for sudo/root
  # authentication (e.g. installing packages via a GUI, mounting drives).
  security.polkit.enable = true;
  systemd.user.services.hyprpolkitagent = {
    description = "Hyprland's polkit authentication agent";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
      Restart = "on-failure";
    };
  };

  # --- Audio (PipeWire) ---------------------------------------------------
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # wireplumber.enable defaults to true and is what Wayle's volume widget
    # talks to.
  };

  # --- Bluetooth ----------------------------------------------------------
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true; # GTK bluetooth manager + tray applet

  # --- Power / battery -----------------------------------------------------
  # The UPower daemon is what actually reports battery charge/state over
  # D-Bus — both Wayle's battery widget and the `battery` CLI command
  # (home/caligo/scripts.nix) read from it.
  services.upower.enable = true;

  # --- Thunar / file manager support --------------------------------------
  programs.thunar.enable = true;
  programs.thunar.plugins = with pkgs; [
    thunar-archive-plugin
    thunar-volman
  ];
  services.gvfs.enable = true; # trash, mounting removable media, network shares
  services.tumbler.enable = true; # thumbnail previews in Thunar

  # --- Fonts -------------------------------------------------------------
  fonts.packages = with pkgs; [
    iosevka-skyc
    nerd-fonts.symbols-only # icon-glyph fallback only — IosevkaSKYC handles the actual text
    noto-fonts
    noto-fonts-color-emoji
  ];

  # --- Gaming ---------------------------------------------------------------
  # Enables 32-bit graphics drivers + controller udev rules, not just the
  # steam package itself. Proton/Steam Play is a one-time toggle inside the
  # Steam client afterwards (Settings > Compatibility) - nothing to set here.
  programs.steam.enable = true;

  # --- Flatpak ----------------------------------------------------------
  # Only needed for Sober (the Roblox client) - there's no native Nix
  # package for it yet. After the first rebuild, one-time setup:
  #   flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  #   flatpak install flathub org.vinegarhq.Sober
  services.flatpak.enable = true;

  # --- Power management -------------------------------------------------
  # Exposes a power-profile switcher (battery saver/balanced/performance)
  # that GNOME-style applets and status bars can hook into.
  services.power-profiles-daemon.enable = true;

  # --- nix-ld ---------------------------------------------------------
  # Lets you run non-Nix, dynamically-linked binaries (downloaded tools,
  # some VS Code server bits, prebuilt CTF/pentest binaries, Python wheels
  # with native extensions, etc.) by providing a standard dynamic linker
  # and an interpreter path they expect to find.
  programs.nix-ld.enable = true;

  # nix-ld on its own only gets you the dynamic linker + glibc. Most real
  # binaries also need a handful of shared libraries that plain NixOS
  # doesn't put on the standard library path. The normal workflow: try
  # running the binary, and when it errors with something like
  # "error while loading shared libraries: libfoo.so.6: cannot open shared
  # object file", add the matching package below and rebuild. A reasonable
  # starting set covering most common cases:
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib # libstdc++ — needed by a huge fraction of prebuilt binaries
    zlib
    openssl
    curl
    icu
    libxml2
    libGL
  ];

  # --- GNOME Online Accounts ------------------------------------------------
  # Backs gnome-calendar/gnome-todo's Google Calendar + Google Tasks sync
  # (calendar.nix). Installing the package is enough for it to be
  # dbus-activated on demand — no separate systemd service to enable. Apple
  # iCloud calendars don't go through GOA (no built-in iCloud entry
  # upstream); add those directly in GNOME Calendar's own "Add Calendar >
  # CalDAV" dialog instead, using https://caldav.icloud.com and an
  # app-specific password from appleid.apple.com.
  #
  # gnome-control-center is here too since GOA's actual "sign in" UI lives
  # in its Online Accounts panel — gnome-calendar's own "Add Calendar" flow
  # may be able to trigger that sign-in inline without it, but this is the
  # guaranteed fallback if it doesn't. Drop it if you'd rather not have a
  # whole GNOME Settings window installed just for this.
  services.gnome.gnome-online-accounts.enable = true;

  # Evolution Data Server — the actual account/mail/calendar/contacts storage
  # backend that Geary (mail.nix) and GNOME Calendar (calendar.nix) both talk
  # to over D-Bus. A full GNOME desktop pulls this in implicitly; on a bare
  # Hyprland session it has to be enabled by hand, and without it Geary dies
  # on startup with "Error creating controller: The name is not activatable"
  # (that name being the EDS D-Bus service, which isn't registered at all) plus
  # the matching "Failed to find primary PersonaStore ... type ID 'eds'".
  # GNOME Calendar hits the same wall when you try to add an account.
  services.gnome.evolution-data-server.enable = true;

  # gnome-keyring — where GOA and Geary/EDS actually store account passwords
  # and OAuth tokens. Without a running secret service they can authenticate
  # once and then lose the credentials, or refuse to save them at all.
  services.gnome.gnome-keyring.enable = true;

  # --- Misc system packages / niceties -------------------------------------
  environment.systemPackages = with pkgs; [
    git
    wget
    curl
    killall
    wl-clipboard
    gnome-control-center

    # C toolchain (CSc 3320) — gcc alone compiles a single file, but
    # coursework usually ships a Makefile and expects gdb for debugging,
    # so both are included rather than just the bare compiler.
    gcc
    gnumake
    gdb
  ];

  # --- greetd / regreet -----------------------------------------------------
  # regreet replaces tuigreet's fixed --cmd flag with a real session picker,
  # so the launch command below is set for you by programs.regreet — do not
  # set services.greetd.settings.default_session.command explicitly, or it'll
  # override regreet's own (mkDefault) command and silently bring tuigreet
  # back even though it's no longer referenced anywhere.
  services.greetd = {
    enable = true;
    settings.default_session.user = "caligo";
  };

  services.displayManager.regreet = {
    enable = true;

    # regreet runs pre-login, before apply-theme's session-level theme
    # engine exists to color anything — there's no live palette to source
    # here, so this is a plain neutral dark GTK theme (ships with GTK
    # itself via gnome-themes-extra, no Catppuccin package needed) rather
    # than any specific accent color.
    theme = {
      package = pkgs.gnome-themes-extra;
      name = "Adwaita-dark";
    };

    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus-Dark"; # matches the icon-theme already set in gtk.nix
    };

    font = {
      package = iosevka-skyc; # the let-bound custom build from the top of this file
      name = "Iosevka SKYC";
      size = 12;
    };

    # GTK4's header bar/window chrome still needs this explicitly set to
    # pick the dark variant rather than defaulting to light chrome around
    # a dark theme.
    settings.GTK.application_prefer_dark_theme = true;
  };

  # Let home-manager & flakes-based tooling work smoothly.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.warn-dirty = false;
  nixpkgs.config.allowUnfree = true;

  # Weekly GC + store optimisation so old generations/store paths don't
  # quietly pile up (boot.loader.systemd-boot.configurationLimit above only
  # trims the boot menu, not the underlying disk usage).
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  # Cap journal size/retention instead of letting it grow unbounded.
  services.journald.settings.Journal = {
    SystemMaxUse = "500M";
    MaxRetentionSec = "2week";
  };

  # Don't change this after your first install unless you know why:
  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
