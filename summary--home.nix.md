`sha256: a336c48751a7d57831a5cf604727b464a4d5762cc12f38b9d7407b05f7f3ab3a`
Imports every apps directory, configures shared and platform-specific packages, settings, shell paths, launchd jobs, Nix GC, and macOS app copying. App bundles are routed by system-extension detection or module opt-in and stamped for ownership; current activation also refreshes LaunchServices with a dedicated awk path.
