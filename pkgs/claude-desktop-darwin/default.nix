# The claude-desktop flake input is Linux-only, so this repacks the official
# prebuilt macOS app from Anthropic's DMG -- same approach as
# clash-verge-rev-darwin. The app is a universal binary (arm64 + x86_64), so
# one DMG covers both darwin systems. Upstream only publishes an unversioned
# "latest" URL, so the hash pins the exact release; when upstream updates,
# the fetch fails with a hash mismatch and both version and hash must be
# bumped together (nix store prefetch-file <url> for the new hash).
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation {
  pname = "claude-desktop";
  version = "0.14.10";

  src = fetchurl {
    url = "https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest/Claude.dmg";
    hash = "sha256-HEiBcVg0p8f/F/LKa8fOQeEMYqorTKtXEv56qrx92JY=";
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
    description = "Claude AI desktop app (official prebuilt macOS app)";
    homepage = "https://claude.ai/download";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
}
