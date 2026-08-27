# Personal fork of erha19/ping-island (NoSugarCoffee/ping-island) with zellij
# support and precise kitty-window focus added -- upstream only speaks tmux
# for pane-jump/type-message routing, which doesn't help since this setup
# uses zellij, and kitty's single-process-per-many-windows model means
# app-level activation can't tell windows apart without it. Repacks a
# self-published release zip (ad-hoc signed, built via the fork's
# .github/workflows/build-test-artifact.yml) -- same approach as
# pulsar-darwin, but from our own release rather than upstream's.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ping-island";
  version = "0.28.2-zellij2";

  src = fetchurl {
    url = "https://github.com/NoSugarCoffee/ping-island/releases/download/v${finalAttrs.version}/PingIsland-0.28.2-release-unsigned.zip";
    hash = "sha256-+1JSF0HlDlfU+oCj8imlK23mw0UthZtoSDJigzl8kbs=";
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
    description = "Dynamic Island-style command center for AI coding agent sessions, with zellij support (personal fork)";
    homepage = "https://github.com/NoSugarCoffee/ping-island";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
  };
})
