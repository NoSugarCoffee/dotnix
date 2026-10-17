{
  config,
  lib,
  pkgs,
  ...
}:
let
  generationsToKeep = 2;
  nixGc = pkgs.writeShellScript "nix-gc" ''
    set -eu
    for profile in "${config.xdg.stateHome}"/nix/profiles/*; do
      case "$profile" in *-link) continue ;; esac
      [ -L "$profile" ] || continue
      ${config.nix.package}/bin/nix-env --profile "$profile" \
        --delete-generations +${toString generationsToKeep}
    done
    exec ${config.nix.package}/bin/nix-collect-garbage
  '';
in
{
  # nix.gc.options only reaches nix-collect-garbage, whose --delete-older-than
  # is time-bounded; keeping the newest N generations needs nix-env's +N, so
  # both platforms' job is replaced with a script.
  launchd.agents.nix-gc.config.ProgramArguments = lib.mkForce [ "${nixGc}" ];
  systemd.user.services.nix-gc.Service.ExecStart = lib.mkForce "${nixGc}";
  nix = {
    # Bounds generation history so the store can't fill the disk again (a
    # full root disk once broke everything on the Linux box): a weekly timer
    # (systemd on Linux, launchd on macOS) keeps only the newest generations
    # of each profile and garbage-collects what the rest referenced, so
    # rollback reaches back exactly one switch.
    gc = {
      automatic = true;
      dates = "weekly";
    };
    # Required by home-manager to generate nix.conf; it only names the nix
    # version used for config validation, nothing is installed.
    package = pkgs.nix;
    # Prefer the China mirrors over cache.nixos.org: the system-level
    # /etc/nix/nix.custom.conf only *appends* them (extra-substituters), so
    # the slow upstream is always tried first. This user-level list overrides
    # the order; nix falls back per-path to later entries automatically.
    # pi.cachix.org serves the lukasl-dev/pi.nix builds (the flake's own
    # nixConfig is opt-in via --accept-flake-config and never reaches an
    # unattended switch); nix-community.cachix.org serves its bun2nix
    # toolchain. Without them pkgs.pi-coding-agent builds from source.
    # nosugarcoffee.cachix.org serves NoSugarCoffee/nur-packages (albert
    # would otherwise compile from source).
    # HARD PREREQUISITE: the daemon silently ignores user-level substituters
    # unless the user is in trusted-users. bootstrap-macos.sh ensures that on
    # macOS; on other machines add it manually to the system nix.conf
    # (e.g. `extra-trusted-users = ${username}`) or this list is a no-op
    # and downloads just fall through to the system substituters.
    settings.substituters = [
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://pi.cachix.org/"
      "https://nix-community.cachix.org/"
      "https://cache.numtide.com/"
      "https://nosugarcoffee.cachix.org/"
      "https://cache.nixos.org/"
    ];
    settings.extra-trusted-public-keys = [
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nosugarcoffee.cachix.org-1:gQkOArBt+myqJZvfmk4L6LqbuScp2LCn2fG1bWRoJhE="
    ];
  };
}
