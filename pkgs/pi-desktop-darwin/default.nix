# PI-Desktop is not in nixpkgs and ships only as prebuilt installers, so this
# repacks the official DMG -- same approach as claude-desktop-darwin.
#
# The bundle is unsigned: every Mach-O carries only the linker's ad-hoc
# signature and no bundle seal at all, so `codesign -vv` reports "code has no
# resources but signature indicates they must be present". Upstream's DMG
# therefore ships a helper that strips com.apple.quarantine after the drag to
# /Applications. Nothing here needs it -- nix fetches the DMG without the
# quarantine attribute in the first place, and copying out of the store keeps
# it that way -- so there is no notarization to preserve and no seal to
# repair, and the bundle is copied verbatim.
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
    aarch64-darwin = "sha256-IqzoF6+vMtjSjqYqwmSv4eoLRETeRRoHxC/SFrD6WHk=";
    x86_64-darwin = "sha256-ox3oazRYL2PoBSMbx8vn7QmO0AW4WjDLtuJoRjDW7PY=";
  };
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-desktop";
  version = "0.14.6";

  src = fetchurl {
    url = "https://github.com/vastsa/PI-Desktop/releases/download/v${finalAttrs.version}/PI-Desktop-${finalAttrs.version}-${archName.${system}}.dmg";
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
    description = "Local-first desktop workspace for AI coding agents (official prebuilt macOS app, not in nixpkgs)";
    homepage = "https://github.com/vastsa/PI-Desktop";
    changelog = "https://github.com/vastsa/PI-Desktop/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.lgpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.attrNames archName;
  };
})
