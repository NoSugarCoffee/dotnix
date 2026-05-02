# `nix/` — niv-pinned non-flake sources

This directory holds [niv](https://github.com/nmattia/niv) state. Use it for
sources that don't ship a flake but you still want pinned and updateable.

```sh
# Inside `nix develop`:
niv init                        # initialise (already done if sources.json exists)
niv add owner/repo              # add a GitHub source
niv update                      # update everything to latest
niv update <name> -b <branch>   # update a single source
niv drop <name>                 # remove a source
```

Consume them from Nix:

```nix
let
  sources = import ./nix/sources.nix;
  someTool = import sources.some-tool { };
in
  ...
```

`sources.json` starts empty — `niv init` will populate it the first time.
