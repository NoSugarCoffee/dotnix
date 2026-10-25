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
    generationsToKeep=''${GENERATIONS_TO_KEEP:-${toString generationsToKeep}}
    xdgProfiles=''${XDG_NIX_PROFILES:-"${config.xdg.stateHome}"/nix/profiles}
    userProfiles=''${NIX_USER_PROFILES:-/nix/var/nix/profiles/per-user/"$USER"}
    nixProfileLink=''${NIX_PROFILE_LINK:-"$HOME"/.nix-profile}

    dirs=()
    add_dir() {
      local dir=$1 existing
      [ -n "$dir" ] || return 0
      while [ "$dir" != "''${dir%/}" ]; do
        dir=''${dir%/}
      done
      [ -d "$dir" ] || return 0
      [ -w "$dir" ] || return 0
      for existing in "''${dirs[@]}"; do
        [ "$existing" = "$dir" ] && return 0
      done
      dirs+=("$dir")
    }

    add_dir "$xdgProfiles"
    add_dir "$userProfiles"
    if [ -L "$nixProfileLink" ]; then
      target=$(readlink "$nixProfileLink") || target=
      if [ -n "$target" ]; then
        case "$target" in
          /*) ;;
          *) target="$(dirname "$nixProfileLink")/$target" ;;
        esac
        add_dir "$(dirname "$target")"
      fi
    fi

    pruned=0
    for dir in "''${dirs[@]}"; do
      for profile in "$dir"/*; do
        case "$profile" in *-link) continue ;; esac
        [ -L "$profile" ] || continue
        if ${config.nix.package}/bin/nix-env --profile "$profile" \
          --delete-generations +"$generationsToKeep"; then
          echo "nix-gc: pruned $profile" >&2
          pruned=$((pruned + 1))
        else
          echo "nix-gc: warning: failed to prune $profile" >&2
        fi
      done
    done

    if [ "$pruned" -eq 0 ]; then
      echo "nix-gc: no profile was pruned (searched: $xdgProfiles, $userProfiles, parent of $nixProfileLink)" >&2
      exit 1
    fi

    exec ${config.nix.package}/bin/nix-collect-garbage
  '';
  # The daemon's own CLI; the profile path is fixed by the Determinate
  # installer, which bootstrap-macos.sh requires on macOS.
  determinateNix = pkgs.runCommandLocal "determinate-nix-bin" { } ''
    mkdir -p $out
    ln -s /nix/var/nix/profiles/default/bin $out/bin
  '';
in
{
  # home-manager runs activation with nix.package (nixpkgs' nix) on PATH, which
  # warns on every Determinate-only setting in /etc/nix/nix.conf (eval-cores,
  # lazy-trees). extraActivationPath precedes it, so the system nix wins.
  # Pinning Determinate's nix as a flake input instead would build it from
  # source: its binaries are only on the auth-gated FlakeHub cache.
  home.extraActivationPath = lib.optional pkgs.stdenv.hostPlatform.isDarwin determinateNix;
  # nix.gc.options only reaches nix-collect-garbage, whose --delete-older-than
  # is time-bounded; keeping the newest N generations needs nix-env's +N, so
  # both platforms' job is replaced with a script.
  launchd.agents.nix-gc.config.ProgramArguments = lib.mkForce [ "${nixGc}" ];
  systemd.user.services.nix-gc.Service.ExecStart = lib.mkForce "${nixGc}";
  nix = {
    # Bounds generation history so the store can't fill the disk again (a
    # full root disk once broke everything on the Linux box): a weekly timer
    # (systemd on Linux, launchd on macOS) keeps the newest two generations
    # of each profile and garbage-collects what the rest referenced.
    # Between runs, every generation since the last GC is still a rollback
    # target; the two-generation cap only applies after the job runs.
    gc = {
      automatic = true;
      dates = "weekly";
    };
    # Required by home-manager to generate nix.conf; it validates that config,
    # runs the nix-gc job, and is the activation nix on Linux.
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
