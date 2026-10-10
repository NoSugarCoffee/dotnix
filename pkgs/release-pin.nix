{ lib, fetchurl }:
pinFile: system:
let
  pin = lib.importJSON pinFile;
  # A per-system map, or one string shared by every system. Only forced when
  # the rendered URL needs it, so a pin that omits the current system still
  # evaluates far enough for `meta.platforms` to filter it out.
  perSystem =
    name: value:
    if builtins.isString value then
      value
    else
      value.${system} or (throw "${toString pinFile}: no ${name} entry for ${system}");
  values =
    (pin.vars or { })
    // {
      inherit (pin) version;
    }
    // lib.optionalAttrs (pin ? arch) {
      arch = perSystem "arch" pin.arch;
    }
    // lib.optionalAttrs (pin ? suffix) {
      suffix = perSystem "suffix" pin.suffix;
    }
    // lib.optionalAttrs (pin.source ? platform) {
      platform = perSystem "platform" pin.source.platform;
    };
  names = builtins.attrNames values;
  url = builtins.replaceStrings (map (name: "{${name}}") names) (map (
    name: values.${name}
  ) names) pin.url;
in
{
  inherit (pin) version;
  platforms = builtins.attrNames pin.hash;
  src = fetchurl {
    inherit url;
    hash = pin.hash.${system} or (throw "${toString pinFile}: no hash for ${system}");
  };
}
