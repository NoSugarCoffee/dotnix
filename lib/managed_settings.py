"""Keep a declared subset of keys in a machine-owned settings file."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
import tomllib
from pathlib import Path
from typing import Callable, Literal

Format = Literal["json", "toml"]

TOML_TABLE = re.compile(r"^\s*\[")
TOML_ASSIGNMENT = re.compile(r"^\s*([A-Za-z0-9_-]+)\s*=")


class ManagedSettingsError(Exception):
    pass


def merge_json(current: str, managed: str) -> str:
    merged = _deep_merge(_load_json_object(current, "current"), _load_json_object(managed, "managed"))
    return json.dumps(merged, indent=2, ensure_ascii=False) + "\n"


def merge_toml(current: str, managed: str) -> str:
    _load_toml(current, "current")
    values = _load_toml(managed, "managed")
    tables = [key for key, value in values.items() if isinstance(value, dict)]
    if tables:
        raise ManagedSettingsError(f"managed TOML may only hold top-level keys, found tables {tables}")
    replacements = {key: f"{key} = {json.dumps(value)}\n" for key, value in values.items()}
    lines = current.splitlines(keepends=True)
    root_end = next((i for i, line in enumerate(lines) if TOML_TABLE.match(line)), len(lines))
    seen: set[str] = set()
    for index in range(root_end):
        match = TOML_ASSIGNMENT.match(lines[index])
        if match and match.group(1) in replacements:
            lines[index] = replacements[match.group(1)]
            seen.add(match.group(1))
    missing = [line for key, line in replacements.items() if key not in seen]
    if missing:
        if root_end and not lines[root_end - 1].endswith("\n"):
            missing.insert(0, "\n")
        lines[root_end:root_end] = missing
    result = "".join(lines)
    _load_toml(result, "merged")
    return result


MERGERS: dict[Format, Callable[[str, str], str]] = {"json": merge_json, "toml": merge_toml}


def sync(fmt: Format, managed: str, seed: str, target: Path, mode: int) -> bool:
    if target.is_symlink():
        raise ManagedSettingsError(f"{target} is a symlink; remove it so it can become a writable file")
    current = target.read_text() if target.exists() else seed
    updated = MERGERS[fmt](current, managed)
    if target.exists() and updated == current:
        return False
    _write_atomically(target, updated, mode)
    return True


def main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", required=True, choices=sorted(MERGERS))
    parser.add_argument("--managed", required=True, type=Path)
    parser.add_argument("--seed", type=Path)
    parser.add_argument("--mode", required=True, type=lambda text: int(text, 8))
    parser.add_argument("target", type=Path)
    args = parser.parse_args(argv)
    empty_seed = "{}\n" if args.format == "json" else ""
    seed = args.seed.read_text() if args.seed else empty_seed
    try:
        sync(args.format, args.managed.read_text(), seed, args.target, args.mode)
    except ManagedSettingsError as error:
        sys.exit(f"managed_settings: {args.target}: {error}")


def _deep_merge(base: dict[str, object], overlay: dict[str, object]) -> dict[str, object]:
    merged = dict(base)
    for key, value in overlay.items():
        existing = merged.get(key)
        if isinstance(existing, dict) and isinstance(value, dict):
            merged[key] = _deep_merge(existing, value)
        else:
            merged[key] = value
    return merged


def _load_json_object(text: str, label: str) -> dict[str, object]:
    try:
        value = json.loads(text)
    except json.JSONDecodeError as error:
        raise ManagedSettingsError(f"{label} JSON is malformed ({error}); fix or delete it") from error
    if not isinstance(value, dict):
        raise ManagedSettingsError(f"{label} JSON must be an object")
    return value


def _load_toml(text: str, label: str) -> dict[str, object]:
    try:
        return tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise ManagedSettingsError(f"{label} TOML is malformed ({error}); fix or delete it") from error


def _write_atomically(target: Path, text: str, mode: int) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=target.parent, prefix=f"{target.name}.hm-")
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write(text)
        os.chmod(temporary, mode)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main(sys.argv[1:])
