# Declarative user accounts. Replace `alice` with your own username and add
# your SSH public key(s) below.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  users.mutableUsers = false;

  users.users.alice = {
    isNormalUser = true;
    description = "Alice Example";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "video"
      "audio"
    ];

    # Replace this placeholder with your own password hash generated via:
    #   mkpasswd -m sha-512
    # or comment out and use `initialPassword` for first boot.
    hashedPassword = "!"; # locked by default — set before deploying

    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... your-key-here"
    ];
  };

  # Passwordless sudo for the wheel group (still requires a TTY).
  security.sudo.wheelNeedsPassword = lib.mkDefault false;
}
