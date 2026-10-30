{ lib, ... }:
{
  options.dotnix.darwin.systemFolderApps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "1Password.app" ];
    description = ''
      App bundles that refuse to run outside /Applications although they ship
      no system extension, so copyApps cannot tell from the bundle itself.
      They get the same /Applications placement and ownership rules.
    '';
  };
}
