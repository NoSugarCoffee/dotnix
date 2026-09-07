{
  lib,
  buildNpmPackage,
  fetchurl,
}:
let
  version = "0.85.1";

  # Upstream's publish-time shrinkwrap generator emits pi's own sibling
  # packages with a `resolved` URL but no `integrity`, and fetchNpmDeps
  # refuses any non-git dependency without one ("non-git dependencies should
  # have associated integrity"). These are the sha512 of the published
  # tarballs at `version`; on every bump refresh them with
  #   npm view @earendil-works/<name>@<version> dist.integrity
  siblingIntegrity = {
    chord = "sha512-VDlkEC3dhCzQ5fcyH1OhG19dq+6jCn+rqc/iXFivwDYGR5anwo2RCiXij9PpHhqNR5GuhhE+Er69Zi1Sn4eY6w==";
    pi-agent-core = "sha512-hIXIP3eAWueAYiAl8aMvWCvvZ8Q5gT3Dip5bE5uJyIGh4+YlWRjtMLI4BaeoXoSs93zndjue61u1B/vhefLnuA==";
    pi-ai = "sha512-+VgVIJDkDO2efYJKEEqvPTH4zmnIaXdAppGbO+vKFA9qy5PdhFiAenuFAkU+oiCSfOC4dMHDyrjdQeL4ZoC5CQ==";
    pi-telemetry = "sha512-Bg/YN6kA7Swja/NQxka8xFdecb4E/auIEGF2G5A25EaQXhRnPj300/7/KpgsDDMYUzHTDAv4RyUxaQPJKW81Rw==";
    pi-tui = "sha512-OIzw9efInmO4WOBnD4TxcTdBjmzvYJpzslkgoUro946nEGoYWg5rwv1p4fDt3/JvMx9QybryUCUwlm7j8Dreig==";
  };

  # substituteInPlace rather than jq: buildNpmPackage forwards postPatch into
  # the separate fetchNpmDeps derivation, whose nativeBuildInputs it does not
  # forward, so only stdenv's own shell functions are available there.
  # Each tarball URL occurs exactly once, so --replace-fail is an unambiguous
  # anchor that breaks loudly if a bump changes the lockfile's shape.
  repairIntegrity = lib.concatStrings (
    lib.mapAttrsToList (
      name: hash:
      let
        resolved = ''"resolved": "https://registry.npmjs.org/@earendil-works/${name}/-/${name}-${version}.tgz",'';
      in
      ''
        substituteInPlace npm-shrinkwrap.json \
          --replace-fail '${resolved}' '${resolved} "integrity": "${hash}",'
      ''
    ) siblingIntegrity
  );
in
buildNpmPackage {
  pname = "pi-coding-agent";
  inherit version;

  # Published npm tarball rather than a GitHub checkout: upstream builds
  # dist/ from a monorepo whose sibling workspaces are not published as
  # sources, so there is nothing to compile here -- but unlike ccstatusline
  # the shipped bundle is not self-contained (it still resolves
  # @earendil-works/chord, typebox/* and @silvia-odwyer/photon-node at
  # runtime), so node_modules has to be installed rather than dropped.
  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-H0mHKWSb3OZH0RYJk7TZK/PGFMyBkhO+4vkd008qevQ=";
  };

  sourceRoot = "package";

  # The shipped shrinkwrap is production-only, but `npm ci` demands the lock
  # describe every package.json dependency including dev ones it will not
  # install -- so it goes to the network for @earendil-works/pi-client and
  # dies ENOTCACHED in the sandbox (`--omit=dev` does not help, the request
  # is for a packument, not a tarball). Renaming the key rather than deleting
  # the block keeps this to a one-token edit that substituteInPlace can do
  # without jq; npm ignores keys it does not know, and the lock's root entry
  # already carries no devDependencies, so the two agree afterwards.
  postPatch = repairIntegrity + ''
    substituteInPlace package.json \
      --replace-fail '"devDependencies"' '"//devDependencies"'
  '';

  npmDepsHash = "sha256-HF3Anl4xnnb6tVQM7u90N7TzWAtiBZ4sU1jxMHWwYr4=";

  # dist/ ships prebuilt in the tarball; there is no build script to run.
  dontNpmBuild = true;

  meta = {
    description = "Minimal coding agent harness with pluggable providers, extensions and skills (prebuilt npm release, not in nixpkgs)";
    homepage = "https://pi.dev/";
    changelog = "https://www.npmjs.com/package/@earendil-works/pi-coding-agent/v/${version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    mainProgram = "pi";
    platforms = lib.platforms.unix;
  };
}
