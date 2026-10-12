_: {
  # kitty replaces Terminal.app as the terminal emulator: Terminal.app
  # translates Option+arrows into Esc-prefixed sequences (e.g. Esc f) that
  # collide with zellij's Alt bindings, and its settings live in a plist
  # nix can't reliably own. macos_option_as_alt makes Option send Alt so
  # the zellij keybindings work; it is ignored on Linux.
  programs.kitty = {
    enable = true;
    themeFile = "Catppuccin-Mocha";
    settings = {
      font_size = 14;
      macos_option_as_alt = "yes";
      # zellij is deliberately not kitty's `shell`: it daemonizes its server
      # with ppid 1, so a pane's process is a child of that server rather than
      # of kitty.app, and macOS attributes permissions (Screen Recording) to
      # the server -- which, being a bare nix-store binary, can never hold a
      # grant. Start it per window with `zellij` / `zellij attach`.
      # kitty runs one process for every window it owns, so session-level
      # activation can only raise "some" kitty window, not necessarily the
      # right one. Remote control on a fixed socket lets callers target the
      # exact window by KITTY_WINDOW_ID instead.
      # socket-only restricts control to this socket, not all local/network
      # access.
      allow_remote_control = "socket-only";
      listen_on = "unix:/tmp/kitty-remote-control";
    };
  };
}
