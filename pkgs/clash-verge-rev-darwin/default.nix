# nixpkgs' clash-verge-rev is Linux-only, so this repacks the official
# prebuilt macOS app from upstream's release DMGs -- same approach nixpkgs
# takes for google-chrome on darwin. Version and hashes are pinned; bump
# both together when updating (nix store prefetch-file <url> for hashes).
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
    aarch64-darwin = "sha256-8JwO8PJKu0bBJoMyufmHEI+KpQpHqsyIXW+J3YRcVfI=";
    x86_64-darwin = "sha256-CvzfQm+yGXDwLFdWfU4BBByQpuMZ3hOmomhPOFBPtPE=";
  };
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "clash-verge-rev";
  version = "2.4.3";

  src = fetchurl {
    url = "https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v${finalAttrs.version}/Clash.Verge_${finalAttrs.version}_${archName.${system}}.dmg";
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
    description = "Clash Meta GUI (official prebuilt macOS app)";
    homepage = "https://www.clashverge.dev/";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames archName;
  };
})
