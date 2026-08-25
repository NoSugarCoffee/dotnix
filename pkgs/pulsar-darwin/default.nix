# Pulsar (Atom successor) is Linux-only in nixpkgs, so this repacks the
# official prebuilt macOS app from upstream's GitHub release zip -- same
# approach as clash-verge-rev-darwin, but a .zip instead of a .dmg since
# that's all upstream publishes per-arch. Only the Apple Silicon build is
# packaged here; add an x86_64-darwin hash (nix store prefetch-file the
# Intel.Mac zip from the same release) if that arch is ever needed.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pulsar";
  version = "1.132.1";

  src = fetchurl {
    url = "https://github.com/pulsar-edit/pulsar/releases/download/v${finalAttrs.version}/Silicon.Mac.Pulsar-${finalAttrs.version}-arm64-mac.zip";
    hash = "sha256-y7WjrOD2Kn67zgqwFH7MhHMPnLTihEvqdrTSVvU58tY=";
  };

  nativeBuildInputs = [ unzip ];
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
    description = "Community-led hyperhackable text editor (official prebuilt macOS app)";
    homepage = "https://pulsar-edit.dev/";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
  };
})
