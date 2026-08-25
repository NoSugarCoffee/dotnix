# Alfred is not in nixpkgs (proprietary macOS-only app), so this repacks
# the official prebuilt app from upstream's release DMG -- same approach
# as claude-desktop-darwin. The app is a universal binary (arm64 + x86_64),
# so one DMG covers both darwin systems. The download URL embeds both the
# version and a build number; bump version, build, and hash together when
# updating (nix store prefetch-file <url> for the new hash).
{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "alfred";
  version = "5.7.3";

  src = fetchurl {
    url = "https://cachefly.alfredapp.com/Alfred_${finalAttrs.version}_2320.dmg";
    hash = "sha256-/DlTnfod+PRCMHmjVdTv9tFRTSVjZ0JlFfKRSEgzFKc=";
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
    description = "macOS launcher and productivity app (official prebuilt app)";
    homepage = "https://www.alfredapp.com/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
})
