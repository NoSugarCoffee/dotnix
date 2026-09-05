{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs,
  makeWrapper,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ccstatusline";
  version = "2.2.29";

  # Published npm tarball rather than a GitHub checkout: upstream builds
  # dist/ccstatusline.js as a single dependency-free bundle (bun build), so
  # there's nothing to compile here -- just wrap the bundle with node.
  src = fetchurl {
    url = "https://registry.npmjs.org/ccstatusline/-/ccstatusline-${finalAttrs.version}.tgz";
    hash = "sha256-3FgL4V0EN4cR8uFfDXZ4zhSqDct7IOVXqJsNlCoGeeU=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec/ccstatusline" "$out/bin"
    cp -R dist LICENSE README.md package.json "$out/libexec/ccstatusline/"
    makeWrapper ${lib.getExe' nodejs "node"} "$out/bin/ccstatusline" \
      --add-flags "$out/libexec/ccstatusline/dist/ccstatusline.js"
    runHook postInstall
  '';

  meta = {
    description = "Customizable status line formatter for Claude Code CLI (prebuilt npm release, not in nixpkgs)";
    homepage = "https://github.com/sirmalloc/ccstatusline";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    mainProgram = "ccstatusline";
    platforms = lib.platforms.unix;
  };
})
