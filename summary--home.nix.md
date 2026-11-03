`sha256: b5a83da15999dc6571f0b94474b826a8598b784865d73524d0a1dac6af250900`
Imports every apps directory, configures shared and platform-specific packages, settings, shell paths, launchd jobs, Nix GC, and macOS app copying. App bundles are routed by system-extension detection or module opt-in and stamped for ownership; current activation also refreshes LaunchServices with a dedicated awk path.
