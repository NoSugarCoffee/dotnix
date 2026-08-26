# Vibe Notch has no nixpkgs derivation, so this repacks the official
# prebuilt macOS DMG from upstream's GitHub release -- same approach as
# claude-desktop-darwin.
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "vibe-notch";
  version = "1.3.2";

  src = fetchurl {
    url = "https://github.com/farouqaldori/vibe-notch/releases/download/v${finalAttrs.version}/VibeNotch-${finalAttrs.version}.dmg";
    hash = "sha256-x1lWadJMt8BdpJD65PvuK0EsB7oKIV+G2tbUEM0N3MA=";
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
    description = "Dynamic Island-style notch notifications for Claude Code sessions (official prebuilt macOS app)";
    homepage = "https://github.com/farouqaldori/vibe-notch";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
  };
})
