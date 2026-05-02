# Custom Packages

Drop `default.nix` files for your own packages here, then expose them via
`overlays/default.nix`:

```nix
final: prev: {
  my-tool = final.callPackage ../pkgs/my-tool { };
}
```

See the [Nixpkgs Manual](https://nixos.org/manual/nixpkgs/stable/) for
package authoring conventions.
