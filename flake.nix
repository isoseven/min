{
  description = "CaligoNix";

  inputs = {
    # Core NixOS package (unstable for new features)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Home Manager
    # pinned to nixpkgs to avoid duplicate builds.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Zen Browser (firefox based)
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Claude Desktop (hello claude!)
    claude-desktop = {
      url = "github:poeck/claude-desktop-nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Spicetify (spotify + themes)
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Walker
    # ships its own home-manager module (walker.homeManagerModules.default)
    # which also auto-wires in elephant (required backend daemon)
    # pinned to nixpkgs to avoid duplicate builds.
    walker = {
      url = "github:abenz1267/walker";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };



  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:

    let
      system = "x86_64-linux"; # change to "aarch64-linux" if you're on ARM
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # formats every .nix file (RFC 166)
      formatter.${system} = pkgs.nixfmt;

      # nixos-rebuild switch --flake .#nixos
      # rename "nixos" to your hostname (see hosts/nixos/configuration.nix)
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };

        modules = [
          ./hosts/nixos/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };

            # home manager backups are saved as .hm-backup
            home-manager.backupFileExtension = "hm-backup";

            # caligo is MY linux username. change to your own.
            home-manager.users.caligo = import ./home/caligo/home.nix;
            home-manager.users.achlys = import ./home/achlys/home.nix;
          }
        ];
      };
    };
}