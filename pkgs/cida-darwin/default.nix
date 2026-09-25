{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cida";
  version = "1.0.0";
  build = "124";

  src = fetchurl {
    url = "https://github.com/Xuanwo/cida/releases/download/v${finalAttrs.version}/Cida-${finalAttrs.version}-${finalAttrs.build}.zip";
    hash = "sha256-+8dIqGRahyCaSYI67WaZq6HbtDEkO6Ofn8KGmc9X1Uo=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";

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
