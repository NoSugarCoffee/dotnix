{
  pkgs,
  homeDirectory,
  lib,
  ...
}:
let
  android = (pkgs.androidenv.override { licenseAccepted = true; }).composeAndroidPackages { };
  sdkLink = if pkgs.stdenv.isDarwin then "Library/Android/sdk" else "Android/Sdk";
  sdkRoot = "${homeDirectory}/${sdkLink}";
  sdkStorePath = "${android.androidsdk}/libexec/android-sdk";
in
{
  home = {
    packages = [ android.androidsdk ];
    sessionVariables = {
      ANDROID_HOME = sdkRoot;
      ANDROID_SDK_ROOT = sdkRoot;
    };
  };

  # Android Studio downloads its own SDK straight into this same default
  # path, so a plain `home.file` link here would collide with that existing,
  # unmanaged directory and fail `switch` outright (home-manager refuses to
  # replace a path it doesn't already own). Link it by hand instead: any
  # existing unmanaged path is moved aside with a timestamped suffix rather
  # than deleted, then the link is pointed at the current store path.
  # Re-running `switch` after a nixpkgs bump just repoints the symlink.
  home.activation.androidSdkLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target=${lib.escapeShellArg sdkRoot}
    storePath=${lib.escapeShellArg sdkStorePath}
    # A symlink already pointing somewhere in /nix/store is a link we (or a
    # prior nixpkgs bump) made; just repoint it, even if the store path
    # changed. Anything else real file, real directory, or a symlink
    # pointing outside the store (Android Studio's own unmanaged SDK) gets
    # moved aside instead of clobbered.
    if [[ -L "$target" && "$(readlink "$target" 2>/dev/null)" == /nix/store/* ]]; then
      :
    elif [[ -e "$target" || -L "$target" ]]; then
      backup="$target.pre-dotnix-$(date +%Y%m%d%H%M%S)"
      echo "moving existing $target to $backup before linking the managed Android SDK..." >&2
      run mkdir -p "$(dirname "$target")"
      run mv "$target" "$backup"
    fi
    run mkdir -p "$(dirname "$target")"
    run ln -sfn "$storePath" "$target"
  '';
}
