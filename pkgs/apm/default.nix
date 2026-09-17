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
      hash = "sha256-O5hbpzVbPNkl/ThPQ699LUWRJUQx3yj10BY/FtOhPoE=";
    };
    x86_64-darwin = {
      name = "apm-darwin-x86_64";
      hash = "sha256-glgpV4VqpdFfQyQxRwAn4FvcBM3rde/5mXOpQXAaBwA=";
    };
    x86_64-linux = {
      name = "apm-linux-x86_64";
      hash = "sha256-hm1/LMCV6FjlLEyB4vwKy5nR+xlI/lRkFluzYtCOlkU=";
    };
  };
  inherit (stdenvNoCC.hostPlatform) isDarwin isLinux system;
  asset = assets.${system} or (throw "apm: no upstream release asset for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "apm";
  version = "0.31.0";

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
