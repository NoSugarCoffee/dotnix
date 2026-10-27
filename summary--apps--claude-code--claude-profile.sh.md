`8ec7df20d1be3ceddab92ccc072b501912ee4fdfb043d259cf60cc75db0fcc7e`
`claude-profile NAME [args...]` validates a profile name, keeps account-bound Claude files under `~/.claude-profiles/NAME`, symlinks shared configuration, and synchronizes `mcpServers` and `projects` through `.claude.json`. It preserves migrations and merges concurrent shared changes on exit.
