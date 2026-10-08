# JetBrains Air (agentic development environment) isn't in nixpkgs, so this
# repacks the official prebuilt macOS app from JetBrains' DMG -- same approach
# as claude-desktop-darwin. Air is still a preview product: JetBrains ships
# per-arch DMGs and prunes older preview builds from the CDN, so pin.json
# needs bumping fairly often; release_pins.py follows the JetBrains products
# API for it.
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
let
  pin = import ../release-pin.nix { inherit lib fetchurl; } ./pin.json stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation {
  pname = "jetbrains-air";
  inherit (pin) version src;

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
    description = "JetBrains Air, an agentic development environment (official prebuilt macOS app)";
    homepage = "https://air.dev/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    inherit (pin) platforms;
  };
}
