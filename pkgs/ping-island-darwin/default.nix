# Personal fork of erha19/ping-island (NoSugarCoffee/ping-island) with zellij
# support added -- upstream only speaks tmux for pane-jump/type-message
# routing, which doesn't help since this setup uses zellij. Repacks a
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
  version = "0.28.2-zellij1";

  src = fetchurl {
    url = "https://github.com/NoSugarCoffee/ping-island/releases/download/v${finalAttrs.version}/PingIsland-0.28.2-release-unsigned.zip";
    hash = "sha256-5mHtcLQsYZFVNrMTT9mZKA4IhGifyVSTZPyc+5Lt/Ts=";
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
