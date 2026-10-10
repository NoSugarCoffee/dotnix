# Grok Bot isn't in nixpkgs. Linux comes from llm-agents.nix; this repacks
# the official macOS DMG. The image is APFS, which undmg cannot read (it
# only extracts HFS), so the unpack mounts it with hdiutil the way
# cida-darwin does. The bundle is notarized, so it is copied verbatim.
#
# The download feed still identifies the product as `sand` -- the name it
# shipped under -- and the Intel filename carries an `_x64` suffix the
# Apple silicon one does not. release_pins.py follows that feed.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  pin = import ../release-pin.nix { inherit lib fetchurl; } ./pin.json stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation {
  pname = "grok-bot";
  inherit (pin) version src;

  sourceRoot = ".";

  unpackPhase = ''
    runHook preUnpack
    mkdir grok-mounted
    /usr/bin/hdiutil attach -quiet -readonly -nobrowse -mountpoint "$PWD/grok-mounted" "$src"
    app=$(find grok-mounted -maxdepth 1 -name "*.app" -print -quit)
    test -n "$app"
    cp -R "$app" .
    /usr/bin/hdiutil detach -quiet "$PWD/grok-mounted"
    rmdir grok-mounted
    runHook postUnpack
  '';

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
    description = "Grok Bot desktop agent (official prebuilt macOS app)";
    homepage = "https://x.ai/bot";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    inherit (pin) platforms;
  };
}
