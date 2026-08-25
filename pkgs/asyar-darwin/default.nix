# asyar is not in nixpkgs, so this repacks the official prebuilt macOS app
# from the GitHub release DMG -- same approach as clash-verge-rev-darwin.
# It is a self-contained Tauri app. Upstream only publishes prereleases so
# far; version and hashes are pinned, bump together when updating.
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
let
  archName = {
    aarch64-darwin = "aarch64";
    x86_64-darwin = "x64";
  };
  archHash = {
    aarch64-darwin = "sha256-aECoHwxvaRKkm7cFLmvaDhAabGEs7qsY6tPeF5BpcXg=";
    x86_64-darwin = "sha256-Q03vnvsdcgQhwDPMdlbV1G0jgvI3gcoMlwVFBqUjaP8=";
  };
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "asyar";
  version = "0.1.1-43";

  src = fetchurl {
    url = "https://github.com/Xoshbin/asyar/releases/download/v${finalAttrs.version}/asyar_${finalAttrs.version}_${archName.${system}}.dmg";
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
    description = "Extensible keyboard launcher (official prebuilt macOS app)";
    homepage = "https://github.com/Xoshbin/asyar";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames archName;
  };
})
