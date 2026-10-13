{ pkgs, ... }:
# git is installed as a plain package, not via programs.git: that module's
# only other job is writing ~/.config/git/config, and git config is left
# unmanaged here. Identity has to be switched per checkout (personal vs
# employer), and git can only express that with `includeIf`, which takes a
# path -- so the split needs a second, machine-local file no matter what.
# Generating half a chain from the store while the other half stays
# hand-written was worse than owning none of it: the values never change,
# and a store symlink means a rebuild to correct an email address.
# ~/.gitconfig is hand-maintained instead.
{
  home.packages = [
    pkgs.git
    # `git open` (paulirish/git-open): opens the repo/PR/issue URL for the
    # current branch in the browser. Picked up by git from PATH.
    pkgs.git-open
  ];
}
