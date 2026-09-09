# ego lite is not in nixpkgs and ships only as a macOS DMG (Windows and Linux
# are on upstream's roadmap), so this repacks the official prebuilt app --
# same approach as claude-desktop-darwin. The bundle arrives notarized with
# an intact seal, so it is copied verbatim.
#
# Upstream publishes no versioned download URL, and the token below does NOT
# roll: it is frozen to this release, while the download button now links
# .../egolite.dmg, which as of 2026-09-09 serves this same 0.4.7.4 build
# byte-for-byte. So a hash mismatch will not fire to announce a new release --
# check upstream by hand. To bump, `nix store prefetch-file <url>` for the new
# hash, then read CFBundleShortVersionString out of the extracted app.
#
# `version` describes the DMG in the store, which is not necessarily the
# version that runs: EgoUpdater ships releases the DMG channel never gets
# (0.5.0.28 existed only as Omaha CRX3 packages behind update.citrolabs.ai)
# and rewrites the installed app in place. It can do that because
# home-manager copies the bundle out to a writable path rather than
# symlinking the store, so the store copy is the one that cannot self-update.
{
  lib,
  stdenvNoCC,
  fetchurl,
  runtimeShell,
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
  # normally drops it into ~/.local/bin; this puts it on PATH declaratively
  # instead.
  #
  # It picks the bundle at run time instead of symlinking the store's, because
  # a store symlink strands PATH on the DMG's build while the browser service
  # it drives moves on with each EgoUpdater release. That skew is worth this
  # much indirection because the service misreports it: 0.4.7.4 driving
  # 0.5.0.28 failed `import --browser chrome` with
  # SOURCE_DATABASE_COOKIES_TOO_OLD against a profile whose cookie schema
  # matched ego's own exactly.
  installPhase = ''
    runHook preInstall
    app=$(find . -maxdepth 1 -name "*.app" -print -quit)
    test -n "$app"
    mkdir -p "$out/Applications" "$out/bin"
    cp -R "$app" "$out/Applications/"

    cat > "$out/bin/ego-browser" <<'WRAPPER'
    #!${runtimeShell}
    helper='Contents/Frameworks/ego Framework.framework/Versions/Current/Helpers/ego-browser'
    # Home Manager Apps first: that copy is the one EgoUpdater can write to,
    # so it is the newest, and it is what LaunchServices actually opens.
    for bundle in \
      "$HOME/Applications/Home Manager Apps/ego lite.app" \
      "$HOME/Applications/ego lite.app" \
      "/Applications/ego lite.app" \
      '@store@'; do
      if [ -x "$bundle/$helper" ]; then
        exec "$bundle/$helper" "$@"
      fi
    done
    printf 'ego-browser: found no ego lite.app containing %s\n' "$helper" >&2
    exit 1
    WRAPPER

    substituteInPlace "$out/bin/ego-browser" \
      --replace-fail '@store@' "$out/Applications/ego lite.app"
    chmod +x "$out/bin/ego-browser"
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
