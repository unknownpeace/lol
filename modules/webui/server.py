#!/usr/bin/env python3
"""Lightweight zero-dependency HTTP server for the Alpine Gateway & Homelab Web Dashboard."""

import base64
import hmac
import json
import mimetypes
import os
import select
import signal
import socket
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
GATEWAY_DIR = os.environ.get("GATEWAY_DIR") or os.path.realpath(os.path.join(SCRIPT_DIR, "..", ".."))
API_SH = os.path.join(GATEWAY_DIR, "modules", "webui", "api.sh")
STATIC_DIR = os.path.realpath(os.path.join(SCRIPT_DIR, "static"))
ENV_FILE = os.environ.get("GATEWAY_ENV_FILE", "/etc/sing-box/gateway.env")

BIND_HOST = os.environ.get("GATEWAY_WEBUI_HOST", "127.0.0.1")
BIND_PORT = int(os.environ.get("GATEWAY_WEBUI_PORT", "8095"))
CONSOLE_PORT = int(os.environ.get("GATEWAY_WEBUI_CONSOLE_PORT", "8096"))
AUTH_MODE = os.environ.get("GATEWAY_WEBUI_AUTH", "caddy").strip().lower()

ALLOWED_METHODS = {
    "status",
    "trace",
    "domain_inspect",
    "set_dhcp",
    "set_killswitch",
    "set_cron",
    "set_network",
    "set_subscription",
    "node_add",
    "node_delete",
    "domain_rule",
    "device_rule",
    "set_telegram",
    "set_password",
    "update_check",
    "get_logs",
    "lxc_autostart",
    "lxc_templates",
    "lxc_console_token",
    "lxc_exec",
    "lxc_config",
    "storage_clean_cache",
    "job_start",
    "job_poll",
}

MAX_BODY_BYTES = 65536
_CRED_CACHE = {"mtime": -1.0, "user": "admin", "password": ""}


class _BodyReadError(Exception):
    def __init__(self, code, message):
        self.code = code
        self.message = message


mimetypes.init()
mimetypes.add_type("application/javascript; charset=utf-8", ".js")
mimetypes.add_type("text/css; charset=utf-8", ".css")
mimetypes.add_type("text/html; charset=utf-8", ".html")
mimetypes.add_type("image/svg+xml", ".svg")


def _load_credentials():
    try:
        st = os.stat(ENV_FILE)
        mtime = st.st_mtime
    except OSError:
        return "admin", ""

    if mtime == _CRED_CACHE["mtime"]:
        return _CRED_CACHE["user"], _CRED_CACHE["password"]

    user = ""
    password = ""
    try:
        with open(ENV_FILE, "r", encoding="utf-8", errors="replace") as fh:
            for raw_line in fh:
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip()
                if len(v) >= 2 and ((v[0] == "'" and v[-1] == "'") or (v[0] == '"' and v[-1] == '"')):
                    v = v[1:-1]
                if k == "AGH_USER" and v:
                    user = v
                elif k == "SMB_USER" and v and not user:
                    user = v
                elif k == "ADMIN_PASS":
                    password = v
    except OSError:
        return "admin", ""

    if not user:
        user = "admin"
    _CRED_CACHE["mtime"] = mtime
    _CRED_CACHE["user"] = user
    _CRED_CACHE["password"] = password
    return user, password


class GatewayWebHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        sys.stderr.write("[webui] %s - %s\n" % (self.address_string(), format % args))
        sys.stderr.flush()

    def _send_security_headers(self):
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "SAMEORIGIN")
        self.send_header("Referrer-Policy", "no-referrer")

    def _send_bytes(self, code, content_type, data, extra_headers=None):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self._send_security_headers()
        if code >= 400:
            self.close_connection = True
            self.send_header("Connection", "close")
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                self.close_connection = True

    def _read_exact(self, length):
        chunks = []
        remaining = length
        while remaining > 0:
            chunk = self.rfile.read(remaining)
            if not chunk:
                raise _BodyReadError(400, "Неожиданный конец тела запроса")
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def _read_body(self):
        te = (self.headers.get("Transfer-Encoding") or "").lower()
        if "chunked" in te:
            buf = bytearray()
            while True:
                line = self.rfile.readline(256)
                if not line:
                    raise _BodyReadError(400, "Некорректный chunked-запрос")
                size_token = line.split(b";", 1)[0].strip()
                try:
                    chunk_size = int(size_token, 16)
                except ValueError:
                    raise _BodyReadError(400, "Некорректный размер chunk")
                if chunk_size < 0:
                    raise _BodyReadError(400, "Некорректный размер chunk")
                if chunk_size == 0:
                    while True:
                        trailer = self.rfile.readline(256)
                        if not trailer or trailer in (b"\r\n", b"\n"):
                            break
                    break
                if len(buf) + chunk_size > MAX_BODY_BYTES:
                    raise _BodyReadError(413, "Слишком большой объем запроса")
                buf.extend(self._read_exact(chunk_size))
                _ = self.rfile.read(2)
            return bytes(buf)

        try:
            clen = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            raise _BodyReadError(400, "Некорректный Content-Length")

        if clen < 0 or clen > MAX_BODY_BYTES:
            raise _BodyReadError(413, "Слишком большой объем запроса")

        return self._read_exact(clen) if clen > 0 else b"{}"

    def _send_json(self, code, obj):
        payload = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self._send_bytes(
            code,
            "application/json; charset=utf-8",
            payload,
            {"Cache-Control": "no-store"},
        )

    def _check_auth(self):
        if AUTH_MODE != "basic":
            return True
        expected_user, expected_pass = _load_credentials()
        if not expected_pass:
            self._send_bytes(
                503,
                "text/plain; charset=utf-8",
                b"Gateway password is not initialized",
            )
            return False
        hdr = self.headers.get("Authorization", "")
        if hdr.startswith("Basic "):
            try:
                raw = base64.b64decode(hdr[6:].strip()).decode("utf-8", errors="strict")
                u, p = raw.split(":", 1)
                user_ok = hmac.compare_digest(u, expected_user) or hmac.compare_digest(u, "admin")
                pass_ok = hmac.compare_digest(p, expected_pass)
                if user_ok and pass_ok:
                    return True
            except Exception:
                pass
        self._send_bytes(
            401,
            "text/plain; charset=utf-8",
            b"Authentication required",
            {
                "WWW-Authenticate": 'Basic realm="Gateway Dashboard"',
                "Cache-Control": "no-store",
            },
        )
        return False

    def _proxy_console(self):
        """Transparently proxy HTTP and WebSocket traffic for /console* to local ttyd."""
        try:
            upstream = socket.create_connection(("127.0.0.1", CONSOLE_PORT), timeout=8)
        except OSError:
            self._send_bytes(
                503,
                "text/plain; charset=utf-8",
                "Веб-консоль ttyd недоступна".encode("utf-8"),
            )
            return

        self.close_connection = True
        try:
            req_lines = [f"{self.command} {self.path} HTTP/1.1"]
            is_ws = False
            for k, v in self.headers.items():
                kl = k.lower()
                if kl in ("authorization", "proxy-connection", "keep-alive"):
                    continue
                if kl == "upgrade" and "websocket" in v.lower():
                    is_ws = True
                if kl == "connection":
                    continue
                req_lines.append(f"{k}: {v}")
            req_lines.append("Connection: Upgrade" if is_ws else "Connection: close")
            raw_req = ("\r\n".join(req_lines) + "\r\n\r\n").encode("utf-8")
            upstream.sendall(raw_req)

            if is_ws:
                self._relay_sockets(self.connection, upstream)
            else:
                while True:
                    chunk = upstream.recv(65536)
                    if not chunk:
                        break
                    self.connection.sendall(chunk)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            try:
                upstream.close()
            except OSError:
                pass

    @staticmethod
    def _relay_sockets(sock_a, sock_b):
        sock_a.setblocking(False)
        sock_b.setblocking(False)
        sockets = [sock_a, sock_b]
        while True:
            readable, _, exceptional = select.select(sockets, [], sockets, 60.0)
            if exceptional:
                break
            if not readable:
                continue
            for s in readable:
                other = sock_b if s is sock_a else sock_a
                try:
                    data = s.recv(65536)
                except (BlockingIOError, OSError):
                    data = b""
                if not data:
                    return
                other.setblocking(True)
                other.sendall(data)
                other.setblocking(False)

    def _serve_static(self, req_path):
        rel = req_path.lstrip("/")
        if not rel or rel == "index.html":
            rel = "index.html"
        elif rel == "favicon.ico":
            rel = "favicon.svg"

        target = os.path.realpath(os.path.join(STATIC_DIR, rel))
        if target != STATIC_DIR and not target.startswith(STATIC_DIR + os.sep):
            self._send_bytes(403, "text/plain; charset=utf-8", b"Forbidden")
            return
        if not os.path.isfile(target):
            self._send_bytes(404, "text/plain; charset=utf-8", b"Not Found")
            return

        ctype, _ = mimetypes.guess_type(target)
        if not ctype:
            ctype = "application/octet-stream"
        try:
            with open(target, "rb") as fh:
                data = fh.read()
        except OSError:
            self._send_bytes(500, "text/plain; charset=utf-8", b"Read Error")
            return

        cache = "no-cache" if rel == "index.html" else "public, max-age=300"
        self._send_bytes(200, ctype, data, {"Cache-Control": cache})

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        if not self._check_auth():
            return
        parsed = urlparse(self.path)
        if parsed.path == "/console" or parsed.path.startswith("/console/"):
            self._proxy_console()
            return
        if parsed.path.startswith("/api/"):
            self._send_json(405, {"ok": False, "error": "Используйте POST запрос"})
            return
        self._serve_static(parsed.path)

    def do_POST(self):
        if not self._check_auth():
            return
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/api/"):
            self._send_json(404, {"ok": False, "error": "Маршрут не найден"})
            return

        if self.headers.get("X-Gateway-Action") != "1":
            self._send_json(403, {"ok": False, "error": "Отсутствует заголовок X-Gateway-Action"})
            return

        method = parsed.path[len("/api/"):].strip("/")
        if method not in ALLOWED_METHODS:
            self._send_json(404, {"ok": False, "error": "Неизвестный метод API"})
            return

        try:
            body_bytes = self._read_body()
        except _BodyReadError as exc:
            self._send_json(exc.code, {"ok": False, "error": exc.message})
            return

        if not body_bytes.strip():
            body_bytes = b"{}"
        try:
            json.loads(body_bytes.decode("utf-8"))
        except Exception:
            self._send_json(400, {"ok": False, "error": "Некорректный JSON"})
            return

        env = os.environ.copy()
        env["GATEWAY_DIR"] = GATEWAY_DIR
        try:
            proc = subprocess.run(
                ["/bin/sh", API_SH, "call", method],
                input=body_bytes,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=65,
                env=env,
            )
        except subprocess.TimeoutExpired:
            self._send_json(504, {"ok": False, "error": "Превышено время ожидания API"})
            return
        except Exception:
            self._send_json(500, {"ok": False, "error": "Ошибка запуска API бэкенда"})
            return

        raw_out = proc.stdout.decode("utf-8", errors="replace").strip()
        last_line = raw_out.splitlines()[-1].strip() if raw_out else ""
        try:
            parsed_out = json.loads(last_line)
        except Exception:
            self._send_json(500, {"ok": False, "error": "Некорректный ответ API бэкенда"})
            return

        self._send_json(200, parsed_out)


class ReusableThreadingHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    httpd = ReusableThreadingHTTPServer((BIND_HOST, BIND_PORT), GatewayWebHandler)

    def _handle_sig(_signum, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, _handle_sig)
    signal.signal(signal.SIGINT, _handle_sig)

    try:
        httpd.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
