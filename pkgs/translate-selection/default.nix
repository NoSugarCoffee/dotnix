{
  lib,
  stdenv,
  writeShellApplication,
  translate-shell,
  python3,
  xclip,
}:

let
  # zellij grabs the mouse, so kitty's own selection (shift+drag) and zellij's
  # (plain drag, copied to the system clipboard by copy_on_select) are two
  # separate channels; the clipboard reader covers the second one. xclip is
  # X11-only -- under Wayland it fails loudly rather than silently returning
  # nothing.
  pasteCommand = if stdenv.isDarwin then "pbpaste" else "xclip -out -selection clipboard";
in
writeShellApplication {
  name = "translate-selection";
  runtimeInputs = [
    translate-shell
    python3
  ]
  ++ lib.optional stdenv.isLinux xclip;
  text = ''
    raw=$(cat)
    if [ -z "''${raw//[[:space:]]/}" ]; then
      raw=$(${pasteCommand})
    fi

    # Terminal selections are hard-wrapped mid-sentence and trans translates
    # each line independently, which splits sentences into separate
    # translations; undoing the wrapping first is what makes the output read.
    text=$(printf '%s' "$raw" | tr -s '[:space:]' ' ')

    if [ -z "''${text// /}" ]; then
      printf 'Nothing selected, and the clipboard is empty.\n'
    else
      # trans has no "translate into whichever language this is not" mode, so
      # the direction is decided here: CJK in, English out; anything else in,
      # Chinese out.
      target=$(printf '%s' "$text" | python3 -c \
        'import sys; print("en" if any("㐀" <= c <= "鿿" for c in sys.stdin.read()) else "zh-CN")')

      printf '\033[2m%s\033[0m\n\n' "$text"
      if translated=$(trans -brief -no-warn -target "$target" -- "$text" 2>&1); then
        printf '%s\n' "$translated"
      else
        printf '\033[31mtranslate-shell failed:\033[0m\n%s\n' "$translated"
      fi
    fi

    # Only the kitty overlay needs holding open; piped into something else this
    # stays a plain filter. kitty's --stdin-source hands us a pipe on fd 0, so
    # the keypress has to be read from the pty directly.
    if [ -t 1 ]; then
      printf '\n\033[2m[any key to close]\033[0m'
      read -r -s -n 1 < /dev/tty
    fi
  '';

  meta = {
    description = "Translate text on stdin (or the clipboard) between Chinese and English";
    platforms = lib.platforms.unix;
    mainProgram = "translate-selection";
  };
}
