{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  autoPatchelfHook,
}:
let
  version = "0.41.2";
  # Tag v0.41.2. The release assets are single-file binaries; this checkout
  # only supplies skills/ and skill-data/, which the CLI loads from the
  # directory above bin/.
  rev = "d52a5e90c372ec4710c69adc3837ac14bbd852aa";

  # nixos-26.05 has agent-browser 0.27.0 and the pinned nixpkgs-unstable has
  # 0.41.1. Neither is this release, and flake.lock stays put.
  binaries = {
    aarch64-darwin = {
      name = "agent-browser-darwin-arm64";
      hash = "sha256-GWgPBs+H0AlcMYougL6mtxUj2V07ZRzRjYGIXNGCR3o=";
    };
    aarch64-linux = {
      name = "agent-browser-linux-arm64";
      hash = "sha256-ANKR9F4cTVJ7OqCMcMVMfDAw/eB5T41FdaqjyhaA9yg=";
    };
    x86_64-darwin = {
      name = "agent-browser-darwin-x64";
      hash = "sha256-/FVgjCIiZQ5uDQFU+e3r0gO2O/hTuF0iJAv73bsAbqE=";
    };
    x86_64-linux = {
      name = "agent-browser-linux-x64";
      hash = "sha256-xDUfOAL/pSVNjGnyClLi/PVpJcYBb89CA9sloH2BE3k=";
    };
  };

  binary =
    binaries.${stdenv.hostPlatform.system}
      or (throw "agent-browser has no release binary for ${stdenv.hostPlatform.system}");

  skillsSrc = fetchFromGitHub {
    owner = "vercel-labs";
    repo = "agent-browser";
    inherit rev;
    hash = "sha256-dN9PIp0ir3rg6Gv57cdcCZ65n5eHW0icfloaVCdSVys=";
  };
in
stdenv.mkDerivation {
  pname = "agent-browser";
  inherit version;

  src = fetchurl {
    url = "https://github.com/vercel-labs/agent-browser/releases/download/v${version}/${binary.name}";
    inherit (binary) hash;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  # Skill templates are text the CLI prints for agents to copy. Leave
  # `#!/bin/bash` as upstream wrote it.
  dontPatchShebangs = true;

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  # The macOS binaries are already linked against libSystem. Skipping fixup
  # leaves that linkage alone.
  dontFixup = stdenv.isDarwin;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/agent-browser
    cp -R ${skillsSrc}/skills $out/skills
    cp -R ${skillsSrc}/skill-data $out/skill-data
    runHook postInstall
  '';

  meta = {
    description = "Browser automation CLI for AI agents";
    homepage = "https://github.com/vercel-labs/agent-browser";
    changelog = "https://github.com/vercel-labs/agent-browser/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [
      binaryNativeCode
      fromSource
    ];
    mainProgram = "agent-browser";
    platforms = lib.attrNames binaries;
  };
}
