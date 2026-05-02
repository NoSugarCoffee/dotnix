# Optional desktop module — GNOME on Wayland with PipeWire audio.
# Disabled by default. Enable per-host with:
#   modules.desktop.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.desktop;
in
{
  options.modules.desktop = {
    enable = lib.mkEnableOption "GNOME desktop with PipeWire";
  };

  config = lib.mkIf cfg.enable {
    services.xserver = {
      enable = true;
      xkb.layout = "us";
      displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
    };

    # Modern audio stack.
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    services.printing.enable = true;

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      jetbrains-mono
      fira-code
    ];
  };
}
