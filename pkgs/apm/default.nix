{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  bzip2,
  libffi,
  libuuid,
  openssl,
  readline,
  sqlite,
  xz,
  zlib,
}:
let
  assets = {
    aarch64-darwin = {
      name = "apm-darwin-arm64";
      hash = "sha256-062wNeCowbgmgSI3RdiGe15iou0hRrZ6eyfHef7Xqgo=";
    };
    x86_64-darwin = {
      name = "apm-darwin-x86_64";
      hash = "sha256-I6eIaUwMDcRY1uli/LixfY8TChjbnsqe8U51xSmgVV4=";
    };
    x86_64-linux = {
      name = "apm-linux-x86_64";
      hash = "sha256-U8mMUPQ2qLWsHWo89EP5TSntHlOFr1KFnPGxtRL3FXg=";
    };
  };
  inherit (stdenvNoCC.hostPlatform) isDarwin isLinux system;
  asset = assets.${system} or (throw "apm: no upstream release asset for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "apm";
  version = "0.29.0";

  src = fetchurl {
    url = "https://github.com/microsoft/apm/releases/download/v${finalAttrs.version}/${asset.name}.tar.gz";
    inherit (asset) hash;
  };

  sourceRoot = asset.name;

  nativeBuildInputs = lib.optionals isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals isLinux [
    bzip2
    libffi
    libuuid
    openssl
    readline
    sqlite
    xz
    zlib
  ];

  dontConfigure = true;
  dontBuild = true;
  dontFixup = isDarwin;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec" "$out/bin"
    cp -R . "$out/libexec/apm"
    ln -s "$out/libexec/apm/apm" "$out/bin/apm"
    runHook postInstall
  '';

  meta = {
    description = "Agent Package Manager, a CLI for installing and authoring agent packages (official prebuilt release)";
    homepage = "https://microsoft.github.io/apm/";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.attrNames assets;
    mainProgram = "apm";
  };
})
