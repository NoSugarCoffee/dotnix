{ pkgs, ... }:
{
  programs.yazi = {
    enable = true;
    shellWrapperName = "y";
    extraPackages = [
      pkgs.fd
      pkgs.ripgrep
      pkgs.fzf
      pkgs.file
    ];
  };
}
