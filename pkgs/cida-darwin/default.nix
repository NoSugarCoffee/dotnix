{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cida";
  version = "1.4.0";
  build = "200";

  src = fetchurl {
    url = "https://github.com/Xuanwo/cida/releases/download/v${finalAttrs.version}/Cida-${finalAttrs.version}-${finalAttrs.build}.dmg";
    hash = "sha256-HT+bQ0qL8hx6fx+raTMKX/SwmjcXBK2R5wGZIqRC0/c=";
  };

  sourceRoot = ".";

  unpackPhase = ''
    runHook preUnpack
    mkdir cida-mounted
    /usr/bin/hdiutil attach -quiet -readonly -nobrowse -mountpoint "$PWD/cida-mounted" "$src"
    cp -R cida-mounted/Cida.app .
    /usr/bin/hdiutil detach -quiet "$PWD/cida-mounted"
    rmdir cida-mounted
    runHook postUnpack
  '';

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R Cida.app "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "Translate and polish text anywhere on macOS with an LLM of your choice";
    homepage = "https://github.com/Xuanwo/cida";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
  };
})
