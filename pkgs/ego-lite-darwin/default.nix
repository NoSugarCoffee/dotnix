# ego lite is not in nixpkgs and ships only as a macOS DMG (Windows and Linux
# are on upstream's roadmap), so this repacks the official prebuilt app --
# same approach as claude-desktop-darwin. The bundle arrives notarized with
# an intact seal, so it is copied verbatim.
#
# Upstream publishes no versioned download URL: the filename token is theirs
# to rotate and the same path keeps serving whatever the current build is, so
# the hash is what actually pins the release. On an upstream update the fetch
# fails with a hash mismatch and version and hash must be bumped together
# (nix store prefetch-file <url> for the new hash, then read
# CFBundleShortVersionString out of the extracted app for the version).
#
# Caveat: `ego-browser upgrade` and the app's bundled Keystone updater cannot
# work from a read-only store path -- bumping the pin above is the upgrade
# path here.
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
    aarch64-darwin = "sha256-wMP9OXtOHCXyCr3ZxqFSuPycehamCZDVDL2enkLCDp0=";
    x86_64-darwin = "sha256-Tx5ew3zzC4snbk/H0C53BQ7XQYg1Kz/mrpU4+5IhNFo=";
  };
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation {
  pname = "ego-lite";
  version = "0.4.7.4";

  src = fetchurl {
    url = "https://cdn.ego.app/setup/macos/${archName.${system}}/egolite-Y7MbxKIuhzFB.dmg";
    hash = archHash.${system};
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  # `ego-browser` is the whole point of the package for agent use, and it is
  # not a separate download: it is a self-contained helper (Mach-O with an
  # embedded Node) inside the app bundle. Upstream's GUI onboarding is what
  # normally drops it into ~/.local/bin; symlinking it here puts it on PATH
  # declaratively instead, and via Versions/Current so a version bump does
  # not have to touch this path.
  installPhase = ''
    runHook preInstall
    app=$(find . -maxdepth 1 -name "*.app" -print -quit)
    test -n "$app"
    mkdir -p "$out/Applications" "$out/bin"
    cp -R "$app" "$out/Applications/"
    ln -s \
      "$out/Applications/ego lite.app/Contents/Frameworks/ego Framework.framework/Versions/Current/Helpers/ego-browser" \
      "$out/bin/ego-browser"
    runHook postInstall
  '';

  meta = {
    description = "Chromium-based browser that shares your logged-in state with AI agents, plus its ego-browser automation CLI (official prebuilt macOS app)";
    homepage = "https://lite.ego.app/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "ego-browser";
    platforms = lib.attrNames archName;
  };
}
