# Local helper functions.
{ lib }:
rec {
  # Glob every .nix file under `dir` except `default.nix` and return them as
  # a list of paths suitable for `imports`.
  importAllModules =
    dir:
    let
      contents = builtins.readDir dir;
      isImportable =
        name: type:
        (type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix")
        || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"));
      names = builtins.filter (n: isImportable n contents.${n}) (builtins.attrNames contents);
    in
    map (n: dir + "/${n}") names;
}
