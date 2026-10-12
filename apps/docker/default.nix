{ pkgs, ... }:
{
  home.packages = [
    pkgs.docker-client
    pkgs.docker-compose
  ];
  home.file.".docker/cli-plugins/docker-compose".source =
    "${pkgs.docker-compose}/libexec/docker/cli-plugins/docker-compose";
}
