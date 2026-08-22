# nixpkgs' copyq is Linux-only, so this repacks the official prebuilt macOS
# app from upstream's release DMGs -- same approach as clash-verge-rev-darwin.
# Version and hashes are pinned; bump all together when updating
# (nix store prefetch-file <url> for hashes).
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
let
  # Upstream names macOS assets by builder image, not by arch:
  # macos-12-m1 is the arm64 build, macos-13 the x86_64 one.
  archAsset = {
    aarch64-darwin = "macos-12-m1";
    x86_64-darwin = "macos-13";
  };
  archHash = {
    aarch64-darwin = "sha256-V1Y/ssokdRl0w1t0TKfqLFwXG8XAD1mzyDeZEodq5LE=";
    x86_64-darwin = "sha256-gXo1zF4UMgdJbXjMwNjdYqmFj+zoCZ0fRZHQCyTbyic=";
  };
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "copyq";
  version = "16.0.0";

  src = fetchurl {
    url = "https://github.com/hluk/CopyQ/releases/download/v${finalAttrs.version}/CopyQ-${finalAttrs.version}-${archAsset.${system}}.dmg";
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
    description = "Clipboard manager (official prebuilt macOS app)";
    homepage = "https://hluk.github.io/CopyQ/";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames archAsset;
  };
})
