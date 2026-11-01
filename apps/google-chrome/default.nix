{
  config,
  lib,
  pkgs,
  homeDirectory,
  ...
}:
{
  home.packages = lib.optionals pkgs.stdenv.isDarwin [ pkgs.google-chrome ];
  home.file."Applications/Google Chrome.app" = lib.mkIf pkgs.stdenv.isDarwin {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/${config.targets.darwin.copyApps.directory}/Google Chrome.app";
  };
  programs.google-chrome = {
    enable = pkgs.stdenv.isDarwin;
    package = null;
    extensions = map (id: { inherit id; }) (
      lib.attrValues {
        "1Password" = "aeblfdkhhhdcdjpifhhbdiojplfjncoa";
        "Bitwarden" = "nngceckbapebfimnlniiiahkandclblb";
        "Buster" = "mpbjkejclgfgadiemmefgebjfooflfhl";
        "docu.md Markdown Viewer" = "jekhhoflgcfoikceikgeenibinpojaoi";
        "Google Docs Offline" = "ghbmnnjooekpmoecnnnilnnbdlolhkhi";
        "Grammarly" = "kbfnbcaeplbcioakkpcpgfkobkghlhen";
        "JSONView" = "cgphfnglahpambfhocchajalljaeegef";
        "Obsidian Web Clipper" = "cnjifjpddelmedmihgijeibhnjfabmlf";
        "Proxy SwitchyOmega (V3)" = "hihblcmlaaademjlakdpicchbjnnnkbo";
        "React Developer Tools" = "fmkadmapgofadopljbjfkapdkoienihi";
        "RSS Subscription Extension" = "nlbjncdgjeocebhnmkbbbdekmmmcbfjd";
        "Sourcegraph" = "dgjhfomjieaadpoljlnidmbgkdffpack";
        "Tampermonkey" = "dhdgffkkebhmkfjojejmpbldmpobfkfo";
        "Doubao" = "dbjibobgilijgolhjdcbdebjhejelffo";
      }
    );
  };
}
