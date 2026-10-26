`4910ecd0ac299a0ccec4b0e0c3a98da81b5d0980f4dbb66c0d2f8f281a5a1e96`
Defines a shared Nix garbage-collection script for Linux and macOS. A weekly systemd or launchd job scans writable user profile directories, keeps the newest two generations with `nix-env --delete-generations +2`, and then runs `nix-collect-garbage`; missing or unwritable directories are skipped.
