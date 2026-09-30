{ proxyUrl, noProxy }:
{
  "$schema" = "https://json.schemastore.org/claude-code-settings.json";
  env = {
    HTTP_PROXY = proxyUrl;
    HTTPS_PROXY = proxyUrl;
    NO_PROXY = noProxy;
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
  };
  permissions = {
    deny = [ "Read(.env)" ];
    # Sessions start with no permission prompts at all.
    defaultMode = "bypassPermissions";
  };
  # Skips the are-you-sure prompt bypassPermissions otherwise shows.
  skipDangerousModePermissionPrompt = true;
  # "opus" is the rolling alias for the newest Opus model, so this
  # tracks upgrades without pinning a dated model id.
  model = "opus";
  theme = "dark";
  tui = "fullscreen";
  remoteControlAtStartup = true;
  # Names the ccstatusline binary as Claude Code's status line. Widget layout
  # remains machine-owned in ~/.config/ccstatusline/settings.json.
  statusLine = {
    type = "command";
    command = "ccstatusline";
    padding = 0;
  };
}
