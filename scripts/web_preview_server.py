"""Serve the XY-CAR Web build and its fixed same-origin API routes."""

import argparse
import json
import re
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

APP_PATH = "/v1/apps/xy_car_app"
COOKIE = "__Host-app-session-xy_car_app"
AUTH = re.compile(rf"/api{APP_PATH}/auth/browser/(bootstrap|login|restore|logout)")
CONFIG_PATHS = {f"/api{APP_PATH}/client-config", "/api/v1/client-config"}
STATION_WRITES = {f"/api{APP_PATH}/station/{path}" for path in ("device", "mission")}
STATION_READS = STATION_WRITES | {f"/api{APP_PATH}/station/missions"}


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def parse_upstream(value):
    url = urlsplit(value)
    local = url.hostname in {"127.0.0.1", "localhost", "::1"}
    if (url.scheme != "https" and not (local and url.scheme == "http")) or (
        not url.hostname or url.username or url.password or url.query or url.fragment
        or url.path not in ("", "/")
    ):
        raise ValueError("API upstream must be an HTTPS or loopback HTTP origin")
    return value.rstrip("/")


class PreviewHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, api_upstream, **kwargs):
        self.api_upstream = api_upstream
        super().__init__(*args, **kwargs)

    def end_headers(self):
        if self.command in ("GET", "HEAD") and not self.path.startswith("/api/"):
            # Flutter uses stable asset URLs across builds.
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def _reject(self, status, message):
        self._reply(status, [("Content-Type", "application/json")], json.dumps({"detail": message}).encode())

    def _reply(self, status, headers, body):
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _proxy(self, target, data=None, *, station=False):
        headers = {"X-App-ID": "xy_car_app"}
        if station and (authorization := self.headers.get("Authorization")):
            headers["Authorization"] = authorization
        if data is not None:
            host = self.headers.get("Host")
            allowed = {f"{name}:{self.server.server_port}" for name in ("127.0.0.1", "localhost")}
            if host not in allowed or self.headers.get("Origin") != f"http://{host}":
                return self._reject(403, "invalid_origin")
            headers["Content-Type"] = "application/json"
            headers["Origin"] = self.headers["Origin"]
            if not station:
                if csrf := self.headers.get("X-CSRF-Token"):
                    headers["X-CSRF-Token"] = csrf
                for field in self.headers.get("Cookie", "").split(";"):
                    if field.strip().startswith(f"{COOKIE}="):
                        headers["Cookie"] = field.strip()
                        break
        request = Request(f"{self.api_upstream}{target}", data=data, headers=headers)
        opener = build_opener(NoRedirect())
        try:
            try:
                response = opener.open(request, timeout=35)
            except HTTPError as error:
                response = error
            with response:
                if 300 <= response.status < 400:
                    return self._reject(502, "unexpected_upstream_redirect")
                body = response.read(128 * 1024 + 1)
                if len(body) > 128 * 1024:
                    return self._reject(502, "upstream_response_too_large")
                forwarded = [("Content-Type", response.headers.get("Content-Type", "application/json"))]
                forwarded.extend(
                    ("Set-Cookie", value)
                    for value in response.headers.get_all("Set-Cookie", [])
                    if not station and value.startswith(f"{COOKIE}=")
                )
                self._reply(response.status, forwarded, body)
        except (URLError, TimeoutError, OSError):
            self._reject(502, "account_service_unavailable")

    def do_GET(self):
        if self.path == "/api/v1/vehicles":
            return self._proxy("/v1/vehicles")
        if self.path in CONFIG_PATHS:
            return self._proxy(f"{APP_PATH}/client-config")
        if self.path.partition("?")[0] in STATION_READS:
            return self._proxy(self.path.removeprefix("/api"), station=True)
        if self.path.startswith("/api/"):
            return self._reject(404, "unknown_api_route")
        return super().do_GET()

    def do_POST(self):
        station = self.path in STATION_WRITES
        if not station and not AUTH.fullmatch(self.path):
            return self._reject(404, "unknown_api_route")
        if self.headers.get_content_type() != "application/json":
            return self._reject(415, "json_required")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self._reject(400, "invalid_body_length")
        if not 0 < length <= 32 * 1024:
            return self._reject(413, "invalid_body_length")
        self.connection.settimeout(10)
        body = self.rfile.read(length)
        if len(body) != length:
            return self._reject(400, "incomplete_body")
        return self._proxy(self.path.removeprefix("/api"), body, station=station)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8089)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--api-upstream", type=parse_upstream, required=True)
    options = parser.parse_args()
    if not (options.directory / "index.html").is_file():
        parser.error("Build the Flutter Web output before starting the proxy")
    handler = partial(PreviewHandler, directory=str(options.directory), api_upstream=options.api_upstream)
    with ThreadingHTTPServer(("127.0.0.1", options.port), handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
