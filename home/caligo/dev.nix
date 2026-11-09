{ pkgs, ... }:

{
  home.packages = [
    pkgs.python3
    pkgs.uv
  ];

  # Auto-loads a project's `.envrc`/`devShell` on `cd`, backed by
  # nix-direnv's derivation-input caching so repeat entries into an
  # already-built shell are instant instead of a fresh `nix develop`.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };
}
