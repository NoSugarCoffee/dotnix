{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
let
  archName = {
    aarch64-darwin = "arm64";
    x86_64-darwin = "x64";
  };
  archHash = {
    aarch64-darwin = "sha256-8NCQgsaRs8crObt+dApqo5n8CRErxwaGC0MpYLK0GpM=";
    x86_64-darwin = "sha256-ovqq7Pv0086/0RMqrrkxugdjrfR6A94yJ2BxF3ekwjo=";
  };
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "orca";
  version = "1.4.220";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${finalAttrs.version}/orca-macos-${archName.${system}}.dmg";
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
    description = "ADE for working with a fleet of parallel coding agents (official prebuilt macOS app, not in nixpkgs)";
    homepage = "https://onorca.dev";
    changelog = "https://github.com/stablyai/orca/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.attrNames archName;
  };
})
