`eba7cb554775d75bd5fa09899756bd1942421e935cddb83cd8b892f234031024`
Defines a shared Nix garbage-collection script for Linux and macOS. A weekly systemd or launchd job scans writable user profile directories, keeps the newest two generations with `nix-env --delete-generations +2`, and then runs `nix-collect-garbage`; missing or unwritable directories are skipped.
