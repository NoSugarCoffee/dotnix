# treefmt configuration — formats Nix, shell, JSON, YAML and Markdown.
{
  projectRootFile = "flake.nix";

  programs = {
    nixfmt.enable = true; # Nix
    shfmt.enable = true; # shell
    prettier.enable = true; # md / json / yaml
  };

  settings.formatter.shfmt.options = [
    "-i"
    "2"
    "-ci"
  ];
}
