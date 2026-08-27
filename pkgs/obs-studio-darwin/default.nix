# nixpkgs' obs-studio is Linux-only, so this repacks the official prebuilt
# macOS app from upstream's release DMGs. The bundle arrives notarized and
# with an intact seal (no AppleDouble sidecars, no re-signing needed), so it
# is copied verbatim. Version and hashes are pinned; bump both together when
# updating (nix store prefetch-file <url> for hashes).
#
# Caveat: the bundled virtual camera (com.obsproject.obs-studio.mac-camera-
# extension) will not install. macOS only accepts a system extension from an
# app inside /Applications, and home-manager links apps into
# ~/Applications/Home Manager Apps. Everything else -- capture, encoding,
# recording, streaming, obs-websocket -- works from the store path.
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
let
  archName = {
    aarch64-darwin = "Apple";
    x86_64-darwin = "Intel";
  };
  archHash = {
    aarch64-darwin = "sha256-kg1vJnA9LfbkCFvTwcvtMEiDJQhBNsem6eNwIfvWqvc=";
    x86_64-darwin = "sha256-+Niv49/9yG76BpjAL/DJl4ZrrD5iCN2vVtNxCLqs8Zc=";
  };
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "obs-studio";
  version = "32.2.2";

  src = fetchurl {
    url = "https://github.com/obsproject/obs-studio/releases/download/${finalAttrs.version}/OBS-Studio-${finalAttrs.version}-macOS-${archName.${system}}.dmg";
    hash = archHash.${system};
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    app=$(find . -maxdepth 1 -name "*.app" -print -quit)
    test -n "$app"
    mkdir -p "$out/Applications"
    cp -R "$app" "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "Live streaming and screen recording studio (official prebuilt macOS app)";
    homepage = "https://obsproject.com/";
    license = lib.licenses.gpl2Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames archName;
  };
})
