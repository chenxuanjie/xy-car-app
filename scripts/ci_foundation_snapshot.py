"""Freeze locally referenced Foundation files for GitHub-hosted Web builds."""

import argparse
import gzip
import hashlib
import io
import json
import subprocess
import tarfile
from pathlib import Path, PurePosixPath

import yaml


ARCHIVE = "shared-packages.tar.gz"
LOCK = "shared-packages.lock.json"
WORKSPACE_MANIFEST = "app-foundation/pubspec.yaml"
PACKAGE_ROOTS = ("packages", "legacy_packages")
MANIFEST_FILES = {"pubspec.yaml", "pubspec.lock", "LICENSE", "NOTICE"}


def git(path, *args):
    return subprocess.run(
        ["git", "-C", str(path), *args], check=True, capture_output=True, timeout=30
    ).stdout


def checksum(data):
    return hashlib.sha256(data).hexdigest()


def dependencies(project):
    pending = [project]
    visited = set()
    while pending:
        folder = pending.pop().resolve()
        if folder in visited:
            continue
        visited.add(folder)
        manifest = yaml.safe_load((folder / "pubspec.yaml").read_bytes())
        if folder != project:
            relative = folder.relative_to(project.parent)
            if len(relative.parts) != 3 or relative.parts[:2] not in {
                ("app-foundation", root) for root in PACKAGE_ROOTS
            }:
                raise ValueError(f"Unexpected path dependency: {relative}")
            yield folder, relative.as_posix(), manifest["name"], manifest.get("version")
        for section in ("dependencies", "dev_dependencies", "dependency_overrides"):
            for dependency in (manifest.get(section) or {}).values():
                if isinstance(dependency, dict) and "path" in dependency:
                    pending.append(folder / dependency["path"])


def allowed_file(relative):
    path = PurePosixPath(relative)
    parts = path.parts
    if (path.as_posix() != relative or "\\" in relative
            or any(part.startswith(".") or ":" in part for part in parts)):
        return False
    if relative == WORKSPACE_MANIFEST:
        return True
    return (
        len(parts) >= 4
        and parts[0] == "app-foundation"
        and parts[1] in PACKAGE_ROOTS
        and (
            (len(parts) == 4 and parts[3] in MANIFEST_FILES)
            or (len(parts) >= 5 and parts[3] in {"lib", "assets"})
        )
    )


def snapshot(project, directory):
    foundation = project.parent / "app-foundation"
    files = {WORKSPACE_MANIFEST: git(foundation, "show", "HEAD:pubspec.yaml")}
    packages = []
    for folder, path, name, version in sorted(dependencies(project)):
        if git(folder, "status", "--porcelain", "--untracked-files=all", "--", "."):
            raise ValueError(f"Use a clean checkout for {name}")
        revision = git(folder, "rev-parse", "HEAD").decode().strip()
        prefix = git(folder, "rev-parse", "--show-prefix").decode().strip()
        packages.append({"path": path, "name": name, "version": version, "commit": revision})
        for member in git(folder, "ls-files", "-z", "--", ".").decode().split("\0"):
            relative = f"{path}/{member}"
            if not member or not allowed_file(relative):
                continue
            if (folder / member).is_symlink():
                raise ValueError(f"Symbolic link cannot enter the snapshot: {relative}")
            files[relative] = git(folder, "show", f"HEAD:{prefix}{member}")

    result = io.BytesIO()
    with gzip.GzipFile(fileobj=result, mode="wb", filename="", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as archive:
            for name, data in sorted(files.items()):
                member = tarfile.TarInfo(name)
                member.size, member.mode = len(data), 0o644
                archive.addfile(member, io.BytesIO(data))
    packed = result.getvalue()
    directory.mkdir(parents=True, exist_ok=True)
    (directory / ARCHIVE).write_bytes(packed)
    (directory / LOCK).write_text(json.dumps({
        "schemaVersion": 1,
        "archiveSha256": checksum(packed),
        "workspaceCommit": git(foundation, "rev-parse", "HEAD").decode().strip(),
        "packages": packages,
        "files": {name: checksum(data) for name, data in sorted(files.items())},
    }, indent=2) + "\n", encoding="utf-8")
    print(f"Frozen {len(packages)} packages and {len(files)} files ({len(packed)} bytes)")


def restore(project, directory):
    lock = json.loads((directory / LOCK).read_bytes())
    packed = (directory / ARCHIVE).read_bytes()
    if lock["schemaVersion"] != 1 or checksum(packed) != lock["archiveSha256"]:
        raise ValueError("Foundation snapshot digest mismatch")
    if (project.parent / "app-foundation").exists():
        raise ValueError("Restore the snapshot beside a clean, isolated app checkout")
    files = {}
    with tarfile.open(fileobj=io.BytesIO(packed), mode="r:gz") as archive:
        for member in archive:
            if (not member.isfile() or not allowed_file(member.name)
                    or member.name in files or member.size > 16 * 1024 * 1024):
                raise ValueError(f"Unsafe snapshot member: {member.name}")
            data = archive.extractfile(member).read()
            if checksum(data) != lock["files"].get(member.name):
                raise ValueError(f"Snapshot file digest mismatch: {member.name}")
            files[member.name] = data
    if files.keys() != lock["files"].keys():
        raise ValueError("Foundation snapshot is incomplete")
    for name, data in files.items():
        path = project.parent / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    expected = {(item["path"], item["name"], item["version"]) for item in lock["packages"]}
    if {(path, name, version) for _, path, name, version in dependencies(project)} != expected:
        raise ValueError("Snapshot packages do not match the application's dependencies")
    print(f"Verified and restored {len(expected)} Foundation packages")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("snapshot", "restore"))
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--directory", type=Path)
    args = parser.parse_args()
    project = args.project.resolve()
    directory = args.directory or project / "packaging/ci"
    try:
        (snapshot if args.command == "snapshot" else restore)(project, directory)
    except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Foundation snapshot failed: {error}\n")


if __name__ == "__main__":
    main()
