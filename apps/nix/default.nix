{
  config,
  lib,
  pkgs,
  ...
}:
let
  gcOptions = [
    "--delete-older-than"
    "14d"
  ];
in
{
  launchd.agents.nix-gc.config.ProgramArguments = lib.mkForce (
    [ "${config.nix.package}/bin/nix-collect-garbage" ] ++ gcOptions
  );
  nix = {
    # Bounds generation history so the store can't fill the disk again (a
    # full root disk once broke everything on the Linux box): a weekly timer
    # (systemd on Linux, launchd on macOS) deletes generations older than two
    # weeks and garbage-collects what they referenced. Time-bounded because
    # Nix has no "keep at most N generations" -- rollback still works within
    # the 14-day window.
    gc = {
      automatic = true;
      dates = "weekly";
      options = lib.concatStringsSep " " gcOptions;
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
