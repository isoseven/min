{ pkgs, ... }:
let
  overview = pkgs.writeShellScriptBin "hypr-overview" ''
    selected=$(${pkgs.hyprland}/bin/hyprctl workspaces -j \
      | ${pkgs.jq}/bin/jq -r 'sort_by(.id) | .[] | "\(.id)\t Workspace \(.id)  (\(.windows) window\(if .windows == 1 then "" else "s" end))"' \
      | ${pkgs.rofi}/bin/rofi -dmenu -p "Workspaces" -theme-str 'window {width: 30%;}' \
      | cut -f1)
    [ -n "$selected" ] && ${pkgs.hyprland}/bin/hyprctl dispatch workspace "$selected"
  '';
in
{
  home.packages = [ overview ];
}
