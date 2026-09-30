"""Sync managed Codex settings without replacing its writable config file."""

import json
import os
from pathlib import Path
import re
import sys
import tempfile
import tomllib


MANAGED_KEYS = ("model", "approval_policy", "sandbox_mode")
ASSIGNMENT = re.compile(r"^\s*(" + "|".join(MANAGED_KEYS) + r")\s*=")
TABLE = re.compile(r"^\s*\[")


def merge(defaults: str, current: str) -> str:
    values = tomllib.loads(defaults)
    tomllib.loads(current)  # Leave a malformed machine-owned file untouched.
    replacements = {key: f"{key} = {json.dumps(values[key])}\n" for key in MANAGED_KEYS}
    lines = current.splitlines(keepends=True)
    root_end = next((i for i, line in enumerate(lines) if TABLE.match(line)), len(lines))
    seen = set()

    for i in range(root_end):
        match = ASSIGNMENT.match(lines[i])
        if match:
            key = match.group(1)
            lines[i] = replacements[key]
            seen.add(key)

    missing = [replacements[key] for key in MANAGED_KEYS if key not in seen]
    if missing:
        if root_end and not lines[root_end - 1].endswith("\n"):
            missing.insert(0, "\n")
        lines[root_end:root_end] = missing

    result = "".join(lines)
    tomllib.loads(result)
    return result


def main() -> None:
    defaults_path, config_path = map(Path, sys.argv[1:])
    current = config_path.read_text()
    updated = merge(defaults_path.read_text(), current)
    if updated == current:
        return

    descriptor, temporary = tempfile.mkstemp(dir=config_path.parent, prefix="config.toml.hm-")
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write(updated)
        os.chmod(temporary, 0o600)
        os.replace(temporary, config_path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()
