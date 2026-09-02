{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  openssl,
  stdenv,
}:
let
  assets = {
    aarch64-darwin = {
      name = "aac-macos-aarch64";
      hash = "sha256-XSCSPku5ZJ713yeY2aoOlbShhAzmY9MJFTQXehGCMcE=";
    };
    x86_64-darwin = {
      name = "aac-macos-x86_64";
      hash = "sha256-E701NaYyhaSL/McAe4AQIj7vqO8dGtc6Se9cv3KQaTg=";
    };
    x86_64-linux = {
      name = "aac-linux-x86_64";
      hash = "sha256-oFs1vMLLnIe8MsL/r4Oh6PKawyWQ5gliH5LouU2G42g=";
    };
  };
  inherit (stdenvNoCC.hostPlatform) isDarwin isLinux system;
  asset = assets.${system} or (throw "agent-access: no upstream release asset for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "agent-access";
  version = "0.11.0";

  src = fetchurl {
    url = "https://github.com/bitwarden/agent-access/releases/download/v${finalAttrs.version}/${asset.name}.tar.gz";
    inherit (asset) hash;
  };

  sourceRoot = ".";

  nativeBuildInputs = lib.optionals isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals isLinux [
    openssl
    stdenv.cc.cc.lib
  ];

  dontConfigure = true;
  dontBuild = true;
  dontFixup = isDarwin;

  installPhase = ''
    runHook preInstall
    install -Dm755 aac "$out/bin/aac"
    runHook postInstall
  '';

  meta = {
    description = "Open protocol, CLI, and SDK to provide agents with credentials without exposing their entire vault (official prebuilt release)";
    homepage = "https://github.com/bitwarden/agent-access";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.attrNames assets;
    mainProgram = "aac";
  };
})
