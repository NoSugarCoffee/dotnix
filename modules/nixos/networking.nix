# Networking defaults: NetworkManager + a sensible firewall.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  networking = {
    networkmanager.enable = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ ];
    };

    # Use systemd-resolved for DNS.
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };
}
