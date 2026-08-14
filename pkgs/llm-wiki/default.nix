{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  makeWrapper,
  glib-networking,
  gtk3,
  webkitgtk_4_1,
  libayatana-appindicator,
  openssl,
  nodejs_22,
}:
let
  version = "0.6.9";
  releaseUrl = "https://github.com/nashsu/llm_wiki/releases/download/v${version}";

  artifacts = {
    x86_64-linux = {
      url = "${releaseUrl}/LLM.Wiki_${version}_amd64.deb";
      hash = "sha256-nzuSMfZ3fYaeRWqFFBSqQQAw3N9k7ha6Yu1De6yfC4w=";
    };
    aarch64-linux = {
      url = "${releaseUrl}/LLM.Wiki_${version}_arm64.deb";
      hash = "sha256-AGiQ+hOxnDHWbNJzb61z/au4dKkuQyBXX0Vo6pKpY8E=";
    };
  };

  inherit (stdenv.hostPlatform) system;
in
stdenv.mkDerivation {
  pname = "llm-wiki";
  inherit version;

  src = fetchurl (
    artifacts.${system} or (throw "llm-wiki: no upstream build for ${system}")
  );

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    wrapGAppsHook3
    makeWrapper
  ];

  buildInputs = [
    glib-networking
    gtk3
    webkitgtk_4_1
    libayatana-appindicator
    openssl
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  dontWrapGApps = true;

  # Tauri resolves its resources as <exe dir>/../lib/<product name>, so the
  # Debian layout has to survive verbatim for the bundled MCP server and pdfium
  # to be found.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r usr/bin usr/lib usr/share $out/
    runHook postInstall
  '';

  # The tray icon library is dlopen'd, so autoPatchelfHook cannot wire it up.
  postFixup = ''
    wrapProgram $out/bin/llm-wiki \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ nodejs_22 ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libayatana-appindicator ]}
  '';

  meta = {
    description = "Desktop app that incrementally builds a persistent wiki from your documents";
    homepage = "https://github.com/nashsu/llm_wiki";
    license = lib.licenses.gpl3Only;
    platforms = lib.attrNames artifacts;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "llm-wiki";
  };
}
