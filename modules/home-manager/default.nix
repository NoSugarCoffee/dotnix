# Re-exports each home-manager module. Use `all` to pull everything in.
{
  shell = ./shell.nix;
  git = ./git.nix;
  packages = ./packages.nix;
  development = ./development.nix;
  codex = ./codex.nix;

  all = {
    imports = [
      ./shell.nix
      ./git.nix
      ./packages.nix
      ./development.nix
      ./codex.nix
    ];
  };
}
