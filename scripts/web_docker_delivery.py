"""Check the business app and write Flutter Web delivery metadata for CI."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess

import yaml


MODES = ("build", "push", "publish-nas")
DIGEST = r"sha256:[0-9a-f]{64}"
COMMIT = r"[0-9a-f]{40}"


def check_dependencies():
    overrides = Path("pubspec_overrides.yaml")
    if overrides.exists() or overrides.is_symlink():
        raise ValueError("Remove pubspec_overrides.yaml before building a release.")
    packages = yaml.safe_load(Path("pubspec.lock").read_text(encoding="utf-8"))["packages"]
    for name, package in packages.items():
        if package.get("source") != "path":
            continue
        dependency = PurePosixPath(package["description"]["path"].replace("\\", "/"))
        if not dependency.is_relative_to("third_party/app-foundation") or ".." in dependency.parts:
            raise ValueError(f"{name} must resolve to its committed Foundation snapshot.")
        subprocess.run(
            ["git", "ls-files", "--error-unmatch", "--", str(dependency / "pubspec.yaml")],
            check=True, capture_output=True,
        )


def read_channel_compose(args):
    text = args.compose.read_text(encoding="utf-8-sig")
    document = yaml.safe_load(text)
    if "${" in text or not isinstance(document, dict) or "include" in document:
        raise ValueError("Use a self-contained channel Compose.")
    services = document.get("services")
    if not isinstance(services, dict) or set(services) != {"xy-car-web"}:
        raise ValueError("Register the single Web image as Compose service 'xy-car-web'.")
    web = services["xy-car-web"]
    if (not isinstance(web, dict) or web.keys() & {"build", "env_file", "extends"}
            or web.get("image") != f"{args.repository}:{args.channel}"
            or web.get("platform") != args.platform or web.get("pull_policy") != "always"):
        raise ValueError("Channel Compose must match the image, channel, platform and pull policy.")
    return document, text


def write_json(path, document):
    path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


def write_delivery(args):
    compose, channel_text = read_channel_compose(args)
    if not re.fullmatch(COMMIT, args.commit) or not re.fullmatch(DIGEST, args.image_id):
        raise ValueError("A Git commit and a Docker image ID are required.")
    published = args.mode != "build"
    nas = args.mode == "publish-nas"
    if published != bool(args.digest) or (args.digest and not re.fullmatch(DIGEST, args.digest)):
        raise ValueError("A registry digest is required only for published images.")
    validation = json.loads(args.validation.read_text(encoding="utf-8"))
    if validation.get("passed") is not True:
        raise ValueError("A passed image smoke check is required.")

    args.output.mkdir(parents=True, exist_ok=False)
    image = {
        "tag": f"{args.repository}:sha-{args.commit}",
        "imageId": args.image_id,
        "sourceRevision": args.commit,
    }
    if published:
        reference = f"{args.repository}@{args.digest}"
        image["reference"] = reference
        compose["services"]["xy-car-web"]["image"] = reference
        (args.output / "docker-compose.yml").write_text(
            yaml.safe_dump(compose, sort_keys=False), encoding="utf-8"
        )
    if nas:
        (args.output / "docker-compose.nas.yml").write_text(channel_text, encoding="utf-8")
    write_json(args.output / "release.json", {
        "schemaVersion": 1,
        "sourceRevision": args.commit,
        "dirtySource": False,
        "platform": args.platform,
        "published": published,
        "nasChannelPublished": nas,
        "images": {"website": image},
    })
    write_json(args.output / "validation.json", validation)
    checksums = "".join(
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
        for path in sorted(args.output.iterdir())
    )
    (args.output / "checksums.sha256").write_text(checksums, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compose", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--platform", choices=("linux/amd64", "linux/arm64"), required=True)
    parser.add_argument("--channel", required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check")
    record = commands.add_parser("record")
    record.add_argument("--mode", choices=MODES, required=True)
    record.add_argument("--commit", required=True)
    record.add_argument("--image-id", required=True)
    record.add_argument("--digest", default="")
    record.add_argument("--validation", type=Path, required=True)
    record.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "check":
            check_dependencies()
            read_channel_compose(args)
        else:
            write_delivery(args)
    except (OSError, ValueError, KeyError, TypeError, yaml.YAMLError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
