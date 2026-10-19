`3817ec1a88bbf1601232eacf567f90cafd2b2502674e9c5bb9c7dcf4aa63934d`
Uses `tailscale-gui` plus a high-priority shell wrapper on Darwin; the wrapper executes the app-bundled CLI so it can resolve its bundle identifier. Linux receives `pkgs.tailscale`; its `tailscaled` service is host-managed.
