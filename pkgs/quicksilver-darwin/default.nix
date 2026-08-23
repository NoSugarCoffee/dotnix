# Quicksilver is not in nixpkgs, so this repacks the official prebuilt
# macOS app from the GitHub release DMG -- same approach as
# claude-desktop-darwin. The app is a universal binary (arm64 + x86_64),
# so one DMG covers both darwin systems.
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "quicksilver";
  version = "2.6.0";

  src = fetchurl {
    url = "https://github.com/quicksilver/Quicksilver/releases/download/v${finalAttrs.version}/Quicksilver.${finalAttrs.version}.dmg";
    hash = "sha256-R9T9+xKBCeIT7iHCcqEA+gQI04mTLEf2awRAtaDTLIw=";
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
    description = "macOS launcher and productivity tool (official prebuilt app)";
    homepage = "https://qsapp.com/";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
})
