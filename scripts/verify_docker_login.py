"""Verify the delivered Web and API images through a local TLS gateway."""

import argparse
import hashlib
import json
import os
import socket
import ssl
import subprocess
import sys
import time
from datetime import UTC, datetime, timedelta
from ipaddress import IPv4Address
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4

import httpx
import yaml
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa

APP = "/api/v1/apps/xy_car_app"
AUTH = APP + "/auth/browser/"
COOKIE = "__Host-app-session-xy_car_app"
WSL = ["wsl.exe", "-d", "Ubuntu", "--exec"] if os.name == "nt" else []
DOCKER = [*WSL, "docker"]


def host_path(path):
    if not WSL:
        return str(path)
    return subprocess.check_output(
        [*WSL, "wslpath", "-u", path.as_posix()], text=True, timeout=10
    ).strip()


def tls_files(directory):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME, "XY-CAR test")])
    now = datetime.now(UTC)
    certificate = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=5))
        .not_valid_after(now + timedelta(hours=1))
        .add_extension(
            x509.SubjectAlternativeName(
                [x509.DNSName("dsm.test"), x509.IPAddress(IPv4Address("127.0.0.1"))]
            ),
            critical=False,
        )
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )
    (directory / "ca.pem").write_bytes(
        certificate.public_bytes(serialization.Encoding.PEM)
    )
    (directory / "key.pem").write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )


def fixture_stack(args, directory, origin, port):
    sys.path[:0] = [str(args.api_project / name) for name in ("tools", "src")]
    from render_stack import stack

    release = json.loads(
        (args.api_project / "release/metadata/release.json").read_text("utf-8")
    )
    images = {item["component"]: item for item in release["archives"]}
    for component in ("app-data-service-api", "postgres"):
        item = images[component]
        image_id = subprocess.check_output(
            [*DOCKER, "image", "inspect", "--format", "{{.Id}}", item["image"]],
            text=True,
            timeout=15,
        ).strip()
        if image_id != item["imageId"]:
            raise RuntimeError(
                f"Loaded image differs from the API release bundle: {component}"
            )

    api_image = images["app-data-service-api"]["image"]
    config = stack(
        "/volume1/xy-car-test-only",
        origin,
        "https://dsm.test:9443",
        api_image=api_image,
        application_settings={"xy_car_app": {"browser_origin": origin}},
    )
    services = config["services"]
    services.pop("powersync")
    services["postgres"]["image"] = images["postgres"]["image"]
    services["postgres"]["volumes"] = ["fixture_db:/var/lib/postgresql/data"]
    config["volumes"] = {"fixture_db": {}}
    api = services["api"]
    api.pop("ports")
    api["environment"]["APP_DATA_DSM_CA"] = "/tls/ca.pem"
    tls_mount = f"{host_path(directory)}:/tls:ro"
    api["volumes"] = [tls_mount]
    dsm = args.api_project / "tests/fixtures/mock_dsm.py"
    services["mock-dsm"] = {
        "image": api_image,
        "command": ["python", "/fixture/mock_dsm.py", "/tls/ca.pem", "/tls/key.pem"],
        "volumes": [tls_mount, f"{host_path(dsm)}:/fixture/mock_dsm.py:ro"],
        "networks": {"default": {"aliases": ["dsm.test"]}},
    }
    web = yaml.safe_load(args.compose.read_text("utf-8"))["services"]["xy-car-web"]
    services["xy-car-web"] = {
        "image": web["image"],
        "platform": web["platform"],
        "environment": {"APP_SERVICE_UPSTREAM": "http://api:8000"},
        "depends_on": {"api": {"condition": "service_healthy"}},
    }
    (directory / "nginx.conf").write_text(
        "events {}\nhttp { server { listen 8443 ssl;\n"
        "ssl_certificate /tls/ca.pem; ssl_certificate_key /tls/key.pem;\n"
        "location / { proxy_set_header Host $http_host; "
        "proxy_pass http://xy-car-web:8080; } } }\n",
        encoding="utf-8",
    )
    services["https"] = {
        "image": web["image"],
        "entrypoint": ["nginx", "-g", "daemon off;"],
        "ports": [f"127.0.0.1:{port}:8443"],
        "volumes": [
            tls_mount,
            f"{host_path(directory / 'nginx.conf')}:/etc/nginx/nginx.conf:ro",
        ],
        "depends_on": ["xy-car-web"],
    }
    return config


def verify_http(origin, ca, web_root):
    tls = ssl.create_default_context(cafile=str(ca))
    with (
        httpx.Client(
            base_url=origin, verify=tls, trust_env=False, timeout=40
        ) as browser,
        httpx.Client(
            base_url=origin, verify=tls, trust_env=False, timeout=40
        ) as reloaded,
    ):

        def expect(path, status, *, client=browser, body=None, headers=None):
            if body is None:
                result = client.get(path)
            else:
                result = client.post(
                    path, json=body, headers={"Origin": origin, **(headers or {})}
                )
            if result.status_code != status:
                raise RuntimeError(
                    f"{path} expected HTTP {status}, got {result.status_code}"
                )
            if (
                path.startswith(AUTH)
                and result.headers.get("Cache-Control") != "no-store"
            ):
                raise RuntimeError(f"Session endpoint can be cached: {path}")
            return result

        deadline = time.monotonic() + 15
        while True:
            try:
                if browser.get("/healthz", timeout=2).status_code == 200:
                    break
            except httpx.TransportError:
                pass
            if time.monotonic() >= deadline:
                raise RuntimeError("Local HTTPS gateway did not become ready")
            time.sleep(0.25)
        index = expect("/", 200)
        deep = expect("/settings/account", 200)
        if (
            deep.content != index.content
            or index.headers.get("Cache-Control") != "no-store"
        ):
            raise RuntimeError("Flutter routes must fall back to the uncached index")
        js = expect("/main.dart.js", 200)
        if (
            hashlib.sha256(js.content).digest()
            != hashlib.sha256((web_root / "main.dart.js").read_bytes()).digest()
        ):
            raise RuntimeError(
                "Image JavaScript does not match the compiled Flutter output"
            )
        for path in (
            "/assets/shaders/fixture-missing.frag",
            "/assets/fixture-missing",
            "/canvaskit/fixture-missing.wasm",
            "/fixture-missing.woff2",
        ):
            expect(path, 404)

        if (
            expect(f"{APP}/client-config", 200).json().get("browser_sessions")
            is not True
        ):
            raise RuntimeError("Client config does not enable XY-CAR browser sessions")
        expect("/api/v1/apps/board_game_agent/auth/browser/bootstrap", 404, body={})
        expect(
            AUTH + "bootstrap",
            403,
            body={},
            headers={"Origin": "https://unlisted.example"},
        )
        guest = expect(AUTH + "bootstrap", 200, body={})
        cookie = guest.headers["Set-Cookie"].lower()
        if not (
            cookie.startswith(COOKIE.lower() + "=")
            and all(
                flag in cookie
                for flag in ("secure", "httponly", "samesite=strict", "path=/")
            )
            and "domain=" not in cookie
            and guest.json()["authenticated"] is False
        ):
            raise RuntimeError(
                "Guest bootstrap did not issue a scoped Secure session cookie"
            )
        csrf = {"X-CSRF-Token": guest.json()["csrf_token"]}
        expect(AUTH + "restore", 401, body={}, headers=csrf)
        credentials = {"account": "alice", "password": "fixture-password"}
        expect(AUTH + "login", 403, body=credentials)
        expect(
            AUTH + "login",
            401,
            body={**credentials, "password": "incorrect"},
            headers=csrf,
        )
        login = expect(AUTH + "login", 200, body=credentials, headers=csrf).json()
        if login.get("display_name") != "alice" or "refresh_token" in login:
            raise RuntimeError(
                "Login returned the wrong identity or exposed a refresh token"
            )

        reloaded.cookies.update(browser.cookies)
        boot = expect(AUTH + "bootstrap", 200, client=reloaded, body={}).json()
        if boot["authenticated"] is not True:
            raise RuntimeError("A new client with the browser cookie lost its session")
        csrf = {"X-CSRF-Token": boot["csrf_token"]}
        restored = expect(
            AUTH + "restore", 200, client=reloaded, body={}, headers=csrf
        ).json()
        if restored.get("user_id") != login.get("user_id"):
            raise RuntimeError("Restored browser identity differs from login")
        old_cookie = reloaded.cookies[COOKIE]
        expect(AUTH + "logout", 200, client=reloaded, body={}, headers=csrf)
        expect(
            AUTH + "restore",
            401,
            client=reloaded,
            body={},
            headers={**csrf, "Cookie": f"{COOKIE}={old_cookie}"},
        )
        if expect(AUTH + "bootstrap", 200, client=reloaded, body={}).json()[
            "authenticated"
        ]:
            raise RuntimeError("Logout did not return the browser to guest mode")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-project", type=Path, required=True)
    parser.add_argument("--compose", type=Path, required=True)
    parser.add_argument("--web-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    args.api_project = args.api_project.resolve()
    with TemporaryDirectory(prefix="xycar-login-") as path:
        directory = Path(path).resolve()
        tls_files(directory)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        origin = f"https://127.0.0.1:{port}"
        configuration = fixture_stack(args, directory, origin, port)
        compose_file = directory / "compose.yml"
        compose_file.write_text(yaml.safe_dump(configuration), encoding="utf-8")
        compose = [
            *DOCKER,
            "compose",
            "-p",
            "xycar-login-" + uuid4().hex[:12],
            "-f",
            host_path(compose_file),
        ]
        try:
            subprocess.run(
                [
                    *compose,
                    "up",
                    "-d",
                    "--wait",
                    "--wait-timeout",
                    "90",
                    "--pull",
                    "never",
                ],
                check=True,
                timeout=120,
            )
            verify_http(origin, directory / "ca.pem", args.web_root)
        finally:
            subprocess.run(
                [*compose, "down", "--volumes", "--timeout", "10"],
                check=True,
                timeout=45,
            )
    report = {
        "passed": True,
        "scope": "delivered Web and API images, PostgreSQL, local TLS, DSM test substitute",
        "realNasTested": False,
        "checks": [
            "static and deep routes",
            "guest session",
            "cookie flags",
            "origin and CSRF",
            "app scope",
            "wrong password",
            "login",
            "restore after reload",
            "logout and revocation",
        ],
        "images": {
            name: svc["image"]
            for name, svc in configuration["services"].items()
            if name in ("xy-car-web", "api", "postgres")
        },
    }
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("Docker sign-in verification passed")


if __name__ == "__main__":
    main()
