{ pkgs, ... }:

let
  snip = pkgs.writeShellScriptBin "snip" ''
    if ${pkgs.procps}/bin/pgrep -x slurp >/dev/null; then
      ${pkgs.procps}/bin/pkill -x slurp
      exit 0
    fi

    geom=$(${pkgs.slurp}/bin/slurp) || exit 0

    file="''${XDG_RUNTIME_DIR:-/tmp}/snip-$(date +%s%N).png"
    ${pkgs.grim}/bin/grim -g "$geom" "$file" || exit 0
    ${pkgs.wl-clipboard}/bin/wl-copy --type image/png < "$file"

    (
      action=$(${pkgs.libnotify}/bin/notify-send \
        --app-name=Screenshot \
        --icon="$file" \
        --action=edit=Edit \
        --wait \
        "Screenshot copied" "Click Edit to annotate it")
      if [ "$action" = "edit" ]; then
        ${pkgs.swappy}/bin/swappy -f "$file"
      fi
    ) >/dev/null 2>&1 &
    disown
  '';
in
{
  home.packages = [
    pkgs.swappy
    snip
  ];

  xdg.configFile."swappy/config".text = ''
    [Default]
    save_dir=$HOME/Pictures/Screenshots
    save_filename_format=screenshot-%Y-%m-%d-%H-%M-%S.png
    show_panel=true
    line_size=5
    text_size=20
    text_font=sans-serif
    paint_mode=brush
    early_exit=false
    fill_shape=false
  '';
}
