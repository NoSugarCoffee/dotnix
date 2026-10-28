{
  config,
  lib,
  pkgs,
  ...
}:
let
  qingjian = pkgs.nosugarcoffee.qingjian or null;
in
{
  home.activation.qingjian = lib.mkIf (qingjian != null) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      qingjianSource=${lib.escapeShellArg "${qingjian}/Library/Input Methods/Qingjian.app"}
      qingjianDir="$HOME/Library/Input Methods"
      qingjianTarget="$qingjianDir/Qingjian.app"
      qingjianStaging="$qingjianDir/.Qingjian.app.new"
      qingjianMarker=${lib.escapeShellArg "${config.xdg.stateHome}/home-manager/qingjian-source"}

      if [[ ! -d "$qingjianTarget" || "$(readlink "$qingjianMarker" 2>/dev/null)" != "$qingjianSource" ]]; then
        $DRY_RUN_CMD mkdir -p "$qingjianDir" "$(dirname "$qingjianMarker")"
        $DRY_RUN_CMD rm -rf "$qingjianStaging"
        $DRY_RUN_CMD cp -R "$qingjianSource" "$qingjianStaging"
        $DRY_RUN_CMD chmod -R u+w "$qingjianStaging"
        $DRY_RUN_CMD /usr/bin/pkill -x qingjian-macos || true
        $DRY_RUN_CMD /usr/bin/pkill -x qingjian-settings || true
        $DRY_RUN_CMD rm -rf "$qingjianTarget"
        $DRY_RUN_CMD mv "$qingjianStaging" "$qingjianTarget"
        qingjianCache=$(/usr/bin/getconf DARWIN_USER_CACHE_DIR)
        $DRY_RUN_CMD rm -f "$qingjianCache"com.apple.IntlDataCache.le* "$qingjianCache"*/com.apple.IntlDataCache.le*
        if ! $DRY_RUN_CMD "$qingjianTarget/Contents/MacOS/qingjian-macos" --register; then
          warnEcho "Qingjian: registering the input source failed; log out and back in, or add 青简 under System Settings > Keyboard > Input Sources"
        fi
        $DRY_RUN_CMD ln -sfn "$qingjianSource" "$qingjianMarker"
      fi
    ''
  );
}
