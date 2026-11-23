"""Build reproducible static Web layers and content-based cache validators."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil


WEB_ROOT = Path("usr/share/nginx/html")
GROUPS = ("engine", "fonts", "media", "app")
FONT_SUFFIXES = {".ttf", ".otf", ".woff", ".woff2"}


def group_for(path):
    if path.parts[0] == "canvaskit" or path == Path("flutter.js"):
        return "engine"
    if path.suffix.lower() in FONT_SUFFIXES:
        return "fonts"
    if (path.parts[0] == "icons" or path == Path("favicon.png")
            or (path.parts[0] == "assets" and len(path.parts) > 2)):
        return "media"
    return "app"


def prepare(source, destination, configuration):
    if not all((source / name).is_file() for name in ("index.html", "main.dart.js")):
        raise ValueError("A complete Flutter Web build is required")
    destination.mkdir()
    for group in GROUPS:
        (destination / group).mkdir()

    etags = []
    for path in sorted(source.rglob("*")):
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise ValueError(f"Unsupported Web build file: {path}")
        relative = path.relative_to(source)
        if path.is_dir() or relative == Path(".last_build_id"):
            continue
        name = relative.as_posix()
        if any(character in name for character in ('$', '\\', '"', '\r', '\n')):
            raise ValueError(f"Unsupported characters in Web resource path: {name!r}")
        target = destination / group_for(relative) / WEB_ROOT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        with target.open("rb") as content:
            digest = hashlib.file_digest(content, "sha256").hexdigest()
        # Literal map keys ignore case. Anchored patterns preserve URL case.
        pattern = json.dumps("~^/" + re.escape(name) + "$", ensure_ascii=False)
        etag = json.dumps(f'"sha256:{digest}"')
        etags.append(f"{pattern} {etag};\n")

    nginx = destination / "nginx/etc/nginx/templates/default.conf.template"
    nginx.parent.mkdir(parents=True)
    shutil.copyfile(configuration, nginx)
    mapping = destination / "etag/etc/nginx/web-etags.map"
    mapping.parent.mkdir(parents=True)
    mapping.write_text("".join(etags), encoding="utf-8")
    # Include every parent directory in each layer to avoid BuildKit assigning
    # wall-clock timestamps to implicit destination directories.
    for path in sorted(destination.rglob("*"), reverse=True):
        path.chmod(0o755 if path.is_dir() else 0o644)
        os.utime(path, (0, 0))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("configuration", type=Path)
    args = parser.parse_args()
    prepare(args.source, args.destination, args.configuration)
