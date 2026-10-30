{
  config,
  lib,
  pkgs,
  homeDirectory,
  ...
}:
let
  ego-lite = pkgs.nosugarcoffee.ego-lite or null;

  # The app bundles the ego-browser skill matching its own CLI. Link the copy
  # in Home Manager Apps, not the store's: EgoUpdater rewrites that copy in
  # place, so Versions/Current tracks the version that actually runs.
  egoSkill = "${homeDirectory}/${config.targets.darwin.copyApps.directory}/ego lite.app/Contents/Frameworks/ego Framework.framework/Versions/Current/Resources/ego-skills/ego-browser";
in
{
  home = {
    packages = lib.optional (ego-lite != null) ego-lite;

    # ~/.agents/skills serves Codex, Pi and Cursor.
    file = lib.mkIf (ego-lite != null && pkgs.stdenv.isDarwin) {
      ".claude/skills/ego-browser".source = config.lib.file.mkOutOfStoreSymlink egoSkill;
      ".agents/skills/ego-browser".source = config.lib.file.mkOutOfStoreSymlink egoSkill;
    };
  };
}
