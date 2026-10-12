# ccstatusline itself comes from llm-agents.nix (see apps/llm-agents).
# ccstatusline writes ~/.config/ccstatusline/settings.json on schema
# migration and from its TUI, so that path cannot be a store symlink
# (EACCES → "⚠ invalid config"). Leave the live file unmanaged; a copyable
# export lives at ./settings.json.
_: { }
