`081d97a28d9dc78b88e9abd8d7ac3c13e43c61588d07388142026736fee7b303`
The helper parses TOML, replaces only `model`, `approval_policy`, and `sandbox_mode` in the root table, inserts missing keys, validates the result, and atomically replaces the writable config with mode 0600. Malformed current files are left untouched.
