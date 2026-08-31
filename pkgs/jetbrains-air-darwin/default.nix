# JetBrains Air (agentic development environment) isn't in nixpkgs, so this
# repacks the official prebuilt macOS app from JetBrains' DMG -- same approach
# as claude-desktop-darwin. Air is still a preview product: JetBrains ships
# per-arch DMGs and prunes older preview builds from the CDN, so the version
# needs bumping fairly often. New version + hash come from
# `curl -s 'https://data.services.jetbrains.com/products?code=AIR'`, whose
# first release entry carries both the macos_aarch64 link and its checksum.
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "jetbrains-air";
  version = "262.579.44";

  src = fetchurl {
    url = "https://download.jetbrains.com/air/installers/macos_aarch64/Air-${finalAttrs.version}-aarch64.dmg";
    hash = "sha256-dbYfKKYZ4au7mlXs8lBmSpxnDzJfS7KiEtvbbanG4fk=";
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
    description = "JetBrains Air, an agentic development environment (official prebuilt macOS app)";
    homepage = "https://air.dev/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
  };
})
