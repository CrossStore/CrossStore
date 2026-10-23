#!/usr/bin/env python3
"""Validate submissions and build a deterministic, entirely static CrossStore."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CAPABILITIES = {"wifi", "lora", "esp_now", "tox", "imu", "touch", "frontlight", "rtc", "psram", "storage", "buzzer", "audio"}
PERMISSIONS = {"network", "radio", "notifications", "background", "reading_data", "wallpaper", "sound", "device_info", "files_export", "keep_awake"}
ID = re.compile(r"[a-z][a-z0-9_]{0,30}\Z")
VERSION = re.compile(r"(?:0|[1-9][0-9]{0,4})\.(?:0|[1-9][0-9]{0,4})\.(?:0|[1-9][0-9]{0,4})\Z")
MAX_PACKAGE = 1024 * 1024
MAX_SCRIPT = 32768
PAGE_SIZE = 16


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def validate(manifest, folder):
    if manifest.get("schema") != 1 or manifest.get("api") not in (1, 2, 3, 4):
        raise ValueError("schema must be 1, API must be 1, 2, 3 or 4")
    ident = manifest.get("id", "")
    if not ID.fullmatch(ident) or ident != folder.name:
        raise ValueError("invalid package ID/directory")
    if not VERSION.fullmatch(manifest.get("version", "")):
        raise ValueError("expected major.minor.patch version")
    if manifest.get("runtime") != "crossmux-lua54" or manifest.get("entry") != "main.lua":
        raise ValueError("unsupported runtime or entry")
    memory = manifest.get("memory_bytes")
    if type(memory) is not int or not 16384 <= memory <= 131072:
        raise ValueError("memory_bytes must be 16384..131072")
    requires = manifest.get("requires")
    if not isinstance(requires, list) or len(requires) != len(set(requires)) or not set(requires) <= CAPABILITIES:
        raise ValueError("unknown or duplicate capability")
    permissions = manifest.get("permissions", [])
    if not isinstance(permissions, list) or len(permissions) != len(set(permissions)) or not set(permissions) <= PERMISSIONS:
        raise ValueError("unknown or duplicate permission")
    if manifest['api'] < 3 and set(permissions) & {'files_export', 'keep_awake'}:
        raise ValueError("file export and awake permissions require API 3")
    if memory > 65536 and "psram" not in requires:
        raise ValueError("VM budgets above 64 KiB require PSRAM")
    if manifest.get("status") not in {"ready", "porting", "source-library"}:
        raise ValueError("invalid migration status")
    for key, limit in (("name", 95), ("description", 191)):
        value = manifest.get(key)
        if not isinstance(value, dict):
            raise ValueError(f"{key} must have en and zh translations")
        for language in ("en", "zh"):
            text = value.get(language)
            if not isinstance(text, str) or not text or "\0" in text or len(text.encode()) > limit:
                raise ValueError(f"invalid {key}.{language}")
    if len(json_bytes(manifest)) > 4096:
        raise ValueError("manifest exceeds 4 KiB")
    if not (folder / "LICENSE").is_file() or not manifest.get("license"):
        raise ValueError("license is required")
    return manifest


def make_package(folder, manifest):
    files = {"manifest.json": json_bytes(manifest)}
    script = folder / "main.lua"
    if script.is_symlink() or not script.is_file():
        raise ValueError("ready packages need a regular main.lua")
    raw = script.read_bytes()
    if not raw or len(raw) > MAX_SCRIPT or raw.startswith(b"\x1b") or b"\0" in raw:
        raise ValueError("entry must be UTF-8 Lua source, at most 32 KiB")
    raw.decode("utf-8")
    files["main.lua"] = raw
    files["LICENSE"] = (folder / "LICENSE").read_bytes()
    for relative in manifest.get("assets", []):
        path = PurePosixPath(relative)
        if path.is_absolute() or ".." in path.parts or not relative.startswith("assets/") or "\\" in relative:
            raise ValueError("invalid asset path")
        source = folder / relative
        if source.is_symlink() or not source.is_file() or not source.resolve().is_relative_to(folder.resolve()):
            raise ValueError("asset must be inside the package")
        files[relative] = source.read_bytes()
    if len(files) > 32:
        raise ValueError("at most 32 files per package")
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_STORED) as archive:
        for name, data in sorted(files.items()):
            item = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            item.external_attr = 0o100644 << 16
            archive.writestr(item, data)
    result = out.getvalue()
    if len(result) > MAX_PACKAGE:
        raise ValueError("package exceeds 1 MiB")
    return result


def build(packages, output):
    output.mkdir(parents=True, exist_ok=True)
    artifacts = output / "packages"
    artifacts.mkdir(exist_ok=True)
    rows, migration = [], []
    seen = set()
    for path in sorted(packages.glob("*/manifest.json")):
        manifest = validate(json.loads(path.read_text()), path.parent)
        ident = manifest["id"]
        if ident in seen:
            raise ValueError(f"duplicate package {ident}")
        seen.add(ident)
        migration.append({"id": ident, "status": manifest["status"]})
        if manifest["status"] != "ready":
            continue
        archive = make_package(path.parent, manifest)
        digest = hashlib.sha256(archive).hexdigest()
        filename = f'{ident}-{manifest["version"]}-{digest[:16]}.csp'
        (artifacts / filename).write_bytes(archive)
        rows.append({**manifest, "artifact": f"packages/{filename}", "bytes": len(archive), "sha256": digest})
    pages = max(1, (len(rows) + PAGE_SIZE - 1) // PAGE_SIZE)
    for page in range(pages):
        document = {"schema": 1, "api": 1, "packages": rows[page * PAGE_SIZE:(page + 1) * PAGE_SIZE],
                    "next": f"page-{page + 2}.json" if page + 1 < pages else ""}
        raw = json_bytes(document)
        if len(raw) > 24576:
            raise ValueError("catalog page exceeds device budget")
        (output / ("index.json" if page == 0 else f"page-{page + 1}.json")).write_bytes(raw)
    (output / "migration.json").write_bytes(json_bytes(migration))
    (output / ".nojekyll").write_text("")
    pending = sum(item["status"] == "porting" for item in migration)
    libraries = sum(item["status"] == "source-library" for item in migration)
    print(f"Built {len(rows)} runnable universal packages; {pending} awaiting migration; {libraries} shared source libraries.")
    return rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages", type=Path, default=ROOT / "packages")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    build(args.packages, args.output)
