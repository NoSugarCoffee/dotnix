`sha256: 7474e76b377e25c2cc037dbd2ab799c5b32fed94b94258d9177a9e646bdc9c72`

Repository guidance: app-per-directory Home Manager modules; shared activation in `home.nix`; package sources are nixpkgs, `llm-agents`, and `nur-packages`. macOS bundles are routed by system-extension detection or module opt-in, with ownership sentinels. dotnix manages programs/settings and bundled skills; dotai owns agent instructions, hooks, and MCP lists. Commits and PRs require explicit request.
