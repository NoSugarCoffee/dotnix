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
    aarch64-darwin = "sha256-IRiDcaHn15LL0tlbCuhpXly2LLN6v/ZYXQQi0IgKd0s=";
    x86_64-darwin = "sha256-Wroit+G5PQ/eM3euJHugkN0/E52xmL0GyL3/+spQJqA=";
  };
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "orca";
  version = "1.4.221";

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
