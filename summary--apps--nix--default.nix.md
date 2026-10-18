`b0c826d3221d1d0c4efc3b3731643e3f00b5dc0e1ce9e836e98656358584faff`
Defines a shared Nix garbage-collection script for Linux and macOS. A weekly systemd or launchd job scans writable user profile directories, keeps the newest two generations with `nix-env --delete-generations +2`, and then runs `nix-collect-garbage`; missing or unwritable directories are skipped.
