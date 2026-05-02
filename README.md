# nix-flake-starter

A batteries-included starter template for a personal **NixOS** and/or
**home-manager** configuration, built around Nix flakes. Fork it, rename a
few things, and you have a reproducible, pinned, modular system config in
under five minutes.

## What's in the box

- **`flake.nix`** — pinned to `nixos-25.11` and matching `home-manager`
  release-25.11. Outputs `nixosConfigurations`, `homeConfigurations`,
  `devShells`, `formatter` and `checks`.
- **`modules/nixos/`** — small, composable system modules (`base`,
  `networking`, `users`, `desktop`).
- **`modules/home-manager/`** — per-user modules (`shell`, `git`, `packages`,
  `development`).
- **`hosts/example-host/`** — example machine wiring the NixOS modules.
- **`home/example-user/`** — example user wiring the home-manager modules.
- **`overlays/`, `pkgs/`, `lib/`** — places to add your own packages and
  helpers.
- **`devshell`** — `nix develop` gives you `niv`, `nixpkgs-fmt`, `nixfmt`,
  `nil`, `statix`, `deadnix`, `nix-tree`, `nvd`, `home-manager`, `just` and
  more.
- **`nix/`** — `niv` state for pinning non-flake sources.
- **`justfile`** — one-line aliases for `rebuild`, `update`, `check`, `fmt`,
  `gc`, `diff`.
- **`.envrc`** — direnv autoloads the devshell.
- **`.gitignore`** — ignores `result`, `result-*`, `.direnv/`, secrets.

## Repository layout

```
.
├── flake.nix                  # entry point — inputs, outputs, devshells
├── justfile                   # common tasks: rebuild, update, check, fmt
├── .envrc                     # direnv → drops you into `nix develop`
├── modules/
│   ├── nixos/                 # NixOS modules
│   │   ├── base.nix
│   │   ├── networking.nix
│   │   ├── users.nix
│   │   └── desktop.nix
│   └── home-manager/          # home-manager modules
│       ├── shell.nix
│       ├── git.nix
│       ├── packages.nix
│       └── development.nix
├── hosts/
│   └── example-host/
│       ├── configuration.nix
│       └── hardware-configuration.nix
├── home/
│   └── example-user/
│       └── home.nix
├── overlays/                  # nixpkgs overlays
├── pkgs/                      # custom packages
├── lib/                       # helper functions
└── nix/                       # niv-pinned sources, treefmt config
```

## Quickstart

### 1. Fork or use as a template

Click **Use this template** on GitHub, then clone your copy:

```sh
git clone git@github.com:<you>/<your-config>.git
cd <your-config>
```

### 2. Enter the devshell

If you have [direnv](https://direnv.net/) + `nix-direnv` installed:

```sh
direnv allow
```

Otherwise:

```sh
nix develop
```

You now have `niv`, `home-manager`, `just`, `statix`, `deadnix`, `nil`,
`nix-tree`, formatters, etc. on your `PATH`.

### 3. Generate a real lockfile

The repo ships without a `flake.lock`. Generate one on first use:

```sh
nix flake update
```

### 4. Personalise

- Rename `hosts/example-host/` to your hostname; update
  `networking.hostName` in `configuration.nix`.
- Replace `hosts/example-host/hardware-configuration.nix` with the file
  produced by `nixos-generate-config` on the target machine.
- Rename `home/example-user/` to your username; update `home.username` and
  `home.homeDirectory`.
- Set `users.users.<you>.hashedPassword` (generate via `mkpasswd -m sha-512`)
  and add your SSH public key in `modules/nixos/users.nix`.
- Update `programs.git.userName` / `userEmail` in
  `home/example-user/home.nix`.
- Adjust the host attribute in `flake.nix`
  (`nixosConfigurations.<name> = ...`) to match.

### 5. Build and switch

NixOS:

```sh
sudo nixos-rebuild switch --flake .#example-host
# or, via just:
just rebuild HOST=example-host
```

Standalone home-manager (any Linux):

```sh
home-manager switch --flake .#alice@example-host
# or:
just hm USER=alice HOST=example-host
```

## Updating

```sh
just update                   # bump every input
just update-input nixpkgs     # bump one input only
just check                    # treefmt + statix + deadnix
just diff                     # nvd diff between current and pending generation
```

## Pinning extra sources with niv

For tools or repos that don't have a flake:

```sh
nix develop
niv add some-org/some-repo
```

Then in Nix:

```nix
let sources = import ./nix/sources.nix; in
  import sources.some-repo { }
```

See [`nix/README.md`](./nix/README.md) for details.

## Adding a new host

1. `cp -r hosts/example-host hosts/laptop`
2. Replace `hardware-configuration.nix` with the one generated on that
   machine.
3. Set `networking.hostName = "laptop";`.
4. Add a new attribute under `nixosConfigurations` in `flake.nix`:

   ```nix
   nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
     system = "x86_64-linux";
     specialArgs = mkSpecialArgs "x86_64-linux";
     modules = [
       ./hosts/laptop/configuration.nix
       home-manager.nixosModules.home-manager
       { /* home-manager.users.<you> = import ./home/<you>/home.nix; */ }
     ];
   };
   ```

## Adding a new user

1. `cp -r home/example-user home/bob`
2. Update `home.username` / `home.homeDirectory`.
3. Add to `flake.nix`:

   ```nix
   homeConfigurations."bob@laptop" = home-manager.lib.homeManagerConfiguration {
     pkgs = mkPkgs "x86_64-linux";
     extraSpecialArgs = mkSpecialArgs "x86_64-linux";
     modules = [ ./home/bob/home.nix ];
   };
   ```

## Useful commands

| Command                               | What it does                                  |
| ------------------------------------- | --------------------------------------------- |
| `nix develop`                         | Enter the devshell                            |
| `nix fmt`                             | Format every Nix/shell/markdown file          |
| `nix flake check`                     | Run formatting + statix + deadnix             |
| `nix flake update`                    | Refresh `flake.lock`                          |
| `sudo nixos-rebuild switch --flake .` | Apply NixOS config                            |
| `home-manager switch --flake .`       | Apply home-manager config                     |
| `nix-tree`                            | Browse a derivation's dependency closure      |
| `nvd diff /run/current-system result` | Diff package versions between two generations |

## Conventions

- **State versions** in `modules/nixos/base.nix` and
  `home/example-user/home.nix` are pinned to `25.11`. Don't bump them
  without reading the relevant release notes.
- Modules expose feature flags via `options.modules.<name>.enable` so hosts
  opt in to functionality (`modules.desktop.enable = true;` etc.).
- `specialArgs` makes `inputs`, `self`, and an `unstable` package set
  available inside every module — no need to thread inputs manually.

## License

MIT — see [`LICENSE`](./LICENSE).
