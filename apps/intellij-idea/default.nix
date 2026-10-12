{ pkgs, ... }:
{
  # IntelliJ IDEA Ultimate; unfree, activation needs your JetBrains license.
  home.packages = [ pkgs.jetbrains.idea ];
}
