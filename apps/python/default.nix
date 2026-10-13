{ pkgs, ... }:
{
  # Python comes prebuilt from nixpkgs rather than asdf: asdf's python
  # plugin compiles from source and needs Xcode CLT on macOS, and its
  # "latest" resolution picks the free-threaded 3.14t variant. Switch
  # major version by swapping this for pkgs.python312/313/314.
  home.packages = [
    (pkgs.python3.withPackages (ps: [
      ps.pip
      ps.ipython
    ]))
  ];
}
