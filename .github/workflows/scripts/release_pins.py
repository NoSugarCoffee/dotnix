"""Bump every pkgs/*/pin.json to its upstream's latest release."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.request
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Callable, Union

HttpGetJson = Callable[[str], object]
Prefetch = Callable[[str], str]

PLACEHOLDER = re.compile(r"\{(\w+)\}")


class PinError(Exception):
    pass


@dataclass(frozen=True)
class GithubSource:
    repo: str
    asset: str | None


@dataclass(frozen=True)
class JetbrainsSource:
    code: str


@dataclass(frozen=True)
class UnversionedUrlSource:
    pass


@dataclass(frozen=True)
class CursorDownloadSource:
    """Cursor's stable download feed. `product` is the feed id (Grok Bot is
    still `sand`, the name it shipped under), and `platform` maps a nix
    system to the feed's platform slug."""

    product: str
    platform: dict[str, str]


Source = Union[GithubSource, JetbrainsSource, UnversionedUrlSource, CursorDownloadSource]


@dataclass(frozen=True)
class Pin:
    source: Source
    version: str
    vars: dict[str, str]
    url: str
    arch: dict[str, str] | None
    suffix: dict[str, str] | None
    hash: dict[str, str]


@dataclass(frozen=True)
class Release:
    version: str
    vars: dict[str, str]
    # When set, each rendered URL must equal the upstream's own download URL.
    urls: dict[str, str] | None = None


@dataclass(frozen=True)
class Bump:
    pin: Pin
    summary: str


def parse_pin(raw: dict[str, object], where: str) -> Pin:
    source_raw = _expect(raw, "source", dict, where)
    kind = _expect(source_raw, "type", str, where)
    source: Source
    if kind == "github":
        asset = source_raw.get("asset")
        if asset is not None and not isinstance(asset, str):
            raise PinError(f"{where}: source.asset must be a string")
        source = GithubSource(repo=_expect(source_raw, "repo", str, where), asset=asset)
    elif kind == "jetbrains":
        source = JetbrainsSource(code=_expect(source_raw, "code", str, where))
    elif kind == "unversioned-url":
        source = UnversionedUrlSource()
    elif kind == "cursor-download":
        platform = _string_map(_expect(source_raw, "platform", dict, where), f"{where}: source.platform")
        if not platform:
            raise PinError(f"{where}: source.platform must name at least one system")
        source = CursorDownloadSource(product=_expect(source_raw, "product", str, where), platform=platform)
    else:
        raise PinError(f"{where}: unknown source.type {kind!r}")
    arch = raw.get("arch")
    suffix = raw.get("suffix")
    parsed_hash = _string_map(_expect(raw, "hash", dict, where), f"{where}: hash")
    parsed_suffix = None if suffix is None else _string_map(suffix, f"{where}: suffix")
    if parsed_suffix is not None and set(parsed_suffix) != set(parsed_hash):
        raise PinError(f"{where}: suffix systems must match hash systems")
    if isinstance(source, CursorDownloadSource) and set(source.platform) != set(parsed_hash):
        raise PinError(f"{where}: source.platform systems must match hash systems")
    return Pin(
        source=source,
        version=_expect(raw, "version", str, where),
        vars=_string_map(raw.get("vars", {}), f"{where}: vars"),
        url=_expect(raw, "url", str, where),
        arch=None if arch is None else _string_map(arch, f"{where}: arch"),
        suffix=parsed_suffix,
        hash=parsed_hash,
    )


def dump_pin(pin: Pin) -> str:
    source: dict[str, object]
    if isinstance(pin.source, GithubSource):
        source = {"type": "github", "repo": pin.source.repo}
        if pin.source.asset is not None:
            source["asset"] = pin.source.asset
    elif isinstance(pin.source, JetbrainsSource):
        source = {"type": "jetbrains", "code": pin.source.code}
    elif isinstance(pin.source, CursorDownloadSource):
        source = {"type": "cursor-download", "product": pin.source.product, "platform": pin.source.platform}
    else:
        source = {"type": "unversioned-url"}
    doc: dict[str, object] = {"source": source, "version": pin.version}
    if pin.vars:
        doc["vars"] = pin.vars
    doc["url"] = pin.url
    if pin.arch is not None:
        doc["arch"] = pin.arch
    if pin.suffix is not None:
        doc["suffix"] = pin.suffix
    doc["hash"] = pin.hash
    return json.dumps(doc, indent=2) + "\n"


def render_url(pin: Pin, system: str) -> str:
    values = {**pin.vars, "version": pin.version}
    if pin.arch is not None:
        values["arch"] = pin.arch[system]
    if pin.suffix is not None:
        values["suffix"] = pin.suffix[system]
    if isinstance(pin.source, CursorDownloadSource):
        values["platform"] = pin.source.platform[system]
    url = PLACEHOLDER.sub(lambda m: values.get(m.group(1), m.group(0)), pin.url)
    unresolved = PLACEHOLDER.findall(url)
    if unresolved:
        raise PinError(f"url {pin.url!r} has no value for {unresolved}")
    return url


def latest_release(pin: Pin, http_get_json: HttpGetJson) -> Release:
    source = pin.source
    if isinstance(source, UnversionedUrlSource):
        return Release(version=pin.version, vars=pin.vars)
    if isinstance(source, JetbrainsSource):
        products = http_get_json(f"https://data.services.jetbrains.com/products?code={source.code}")
        if not isinstance(products, list) or not products:
            raise PinError(f"JetBrains returned no product for code {source.code}")
        return Release(version=products[0]["releases"][0]["build"], vars={})
    if isinstance(source, CursorDownloadSource):
        version: str | None = None
        urls: dict[str, str] = {}
        for system, platform in source.platform.items():
            feed_url = f"https://api2.cursor.sh/updates/api/download/stable/{platform}/{source.product}"
            data = http_get_json(feed_url)
            if not isinstance(data, dict):
                raise PinError(f"{platform}: unexpected cursor feed payload")
            feed_version = data.get("version")
            download = data.get("downloadUrl")
            if not isinstance(feed_version, str) or not feed_version:
                raise PinError(f"{platform}: cursor feed missing version")
            if not isinstance(download, str) or not download:
                raise PinError(f"{platform}: cursor feed missing downloadUrl")
            if version is None:
                version = feed_version
            elif feed_version != version:
                raise PinError(f"cursor feed versions diverged: {version} vs {feed_version} for {system}")
            urls[system] = download
        if version is None:
            raise PinError(f"{source.product}: cursor feed returned no platforms")
        return Release(version=version, vars=pin.vars, urls=urls)
    release = http_get_json(f"https://api.github.com/repos/{source.repo}/releases/latest")
    if not isinstance(release, dict):
        raise PinError(f"{source.repo}: unexpected latest-release payload")
    version = str(release["tag_name"]).removeprefix("v")
    if source.asset is None:
        return Release(version=version, vars={})
    pattern = re.compile(source.asset.replace("{version}", re.escape(version)))
    matches = [m for m in (pattern.match(a["name"]) for a in release["assets"]) if m]
    if len(matches) != 1:
        raise PinError(f"{source.repo} {version}: expected one asset matching {source.asset}, found {len(matches)}")
    return Release(version=version, vars=matches[0].groupdict())


def bump_pin(name: str, pin: Pin, release: Release, prefetch: Prefetch) -> Bump | None:
    candidate = replace(pin, version=release.version, vars=release.vars)
    if release.urls is not None:
        for system, url in release.urls.items():
            rendered = render_url(candidate, system)
            if rendered != url:
                raise PinError(f"{name}: {system} feed URL {url} does not match template {rendered}")
    unversioned = isinstance(pin.source, UnversionedUrlSource)
    if not unversioned and candidate == pin:
        return None
    hashes = {system: prefetch(render_url(candidate, system)) for system in pin.hash}
    if unversioned and hashes == pin.hash:
        return None
    bumped = replace(candidate, hash=hashes)
    if unversioned:
        return Bump(
            pin=bumped,
            summary=f"- `{name}`: upstream republished at its unversioned URL; hashes updated, "
            f"version label `{pin.version}` left as is.",
        )
    return Bump(pin=bumped, summary=f"- `{name}`: {_label(pin)} -> {_label(bumped)}")


def bump_all(pkgs_dir: Path, http_get_json: HttpGetJson, prefetch: Prefetch) -> list[str]:
    summaries: list[str] = []
    for pin_file in sorted(pkgs_dir.glob("*/pin.json")):
        name = pin_file.parent.name
        pin = parse_pin(json.loads(pin_file.read_text()), str(pin_file))
        bump = bump_pin(name, pin, latest_release(pin, http_get_json), prefetch)
        if bump is not None:
            pin_file.write_text(dump_pin(bump.pin))
            summaries.append(bump.summary)
    return summaries


def http_get_json(url: str) -> object:
    request = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "dotnix-release-pins"})
    token = os.environ.get("GH_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def nix_prefetch(url: str) -> str:
    result = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", url],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)["hash"]


def write_step_output(summaries: list[str], output: Path | None) -> None:
    text = f"changed={'true' if summaries else 'false'}\nsummary<<SUMMARY_EOF\n" + "\n".join(summaries) + "\nSUMMARY_EOF\n"
    if output is None:
        sys.stdout.write(text)
    else:
        with output.open("a") as handle:
            handle.write(text)


def main() -> None:
    summaries = bump_all(Path("pkgs"), http_get_json, nix_prefetch)
    github_output = os.environ.get("GITHUB_OUTPUT")
    write_step_output(summaries, Path(github_output) if github_output else None)


def _label(pin: Pin) -> str:
    extras = "".join(f" ({key} {value})" for key, value in sorted(pin.vars.items()))
    return f"{pin.version}{extras}"


def _expect(doc: dict[str, object], key: str, kind: type, where: str):
    value = doc.get(key)
    if not isinstance(value, kind):
        raise PinError(f"{where}: {key} must be a {kind.__name__}")
    return value


def _string_map(value: object, where: str) -> dict[str, str]:
    if not isinstance(value, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in value.items()):
        raise PinError(f"{where} must map strings to strings")
    return dict(value)


if __name__ == "__main__":
    main()
