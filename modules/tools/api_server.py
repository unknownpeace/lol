#!/usr/bin/env python3
"""
🚀 Universal Sidecar Gateway & Homelab: Ultra-Lightweight REST & SSE API Daemon
Listens on 127.0.0.1:8080.
Exposes real-time system metrics, proxy routing controls, homelab status and long-running streaming jobs (SSE).
Zero external Python packages required.
"""

import os
import sys
import json
import time
import hmac
import shutil
import urllib.request
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

PORT = 8080
HOST = "127.0.0.1"
GATEWAY_ENV_FILE = "/etc/sing-box/gateway.env"
HOMELAB_ENV_FILE = "/etc/sing-box/homelab.env"
GATEWAY_BIN = "/usr/bin/gateway"


def load_env_file(path):
    data = {}
    if not os.path.exists(path):
        return data
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip("'\"")
                data[k] = v
    except Exception:
        pass
    return data


def get_admin_pass():
    gw = load_env_file(GATEWAY_ENV_FILE)
    return gw.get("ADMIN_PASS", "admin")


def check_auth(headers):
    auth_header = headers.get("Authorization", "")
    token = headers.get("X-Gateway-Token", "")
    admin_pass = get_admin_pass()

    if token and hmac.compare_digest(token, admin_pass):
        return True

    if auth_header.startswith("Bearer "):
        bearer = auth_header[7:].strip()
        if hmac.compare_digest(bearer, admin_pass):
            return True

    return False


def get_system_metrics():
    # 1. RAM
    mem_total_mb = 1
    mem_avail_mb = 1
    try:
        with open("/proc/meminfo", "r") as f:
            for line in f:
                parts = line.split()
                if parts[0] == "MemTotal:":
                    mem_total_mb = int(parts[1]) // 1024
                elif parts[0] == "MemAvailable:":
                    mem_avail_mb = int(parts[1]) // 1024
    except Exception:
        pass
    mem_used_mb = max(0, mem_total_mb - mem_avail_mb)
    mem_pct = int((mem_used_mb / max(1, mem_total_mb)) * 100)

    # 2. CPU load & temp
    load1, load5, load15 = 0.0, 0.0, 0.0
    try:
        load1, load5, load15 = os.getloadavg()
    except Exception:
        pass

    cpu_temp = None
    for zone in ["/sys/class/thermal/thermal_zone0/temp", "/sys/class/hwmon/hwmon0/temp1_input"]:
        if os.path.exists(zone):
            try:
                with open(zone, "r") as f:
                    raw = int(f.read().strip())
                    cpu_temp = round(raw / 1000.0, 1) if raw > 1000 else raw
                    break
            except Exception:
                pass

    # 3. Uptime
    uptime_sec = 0
    try:
        with open("/proc/uptime", "r") as f:
            uptime_sec = int(float(f.read().split()[0]))
    except Exception:
        pass

    # 4. Storage (/srv/storage)
    storage_root = "/srv/storage"
    disk_total_gb, disk_used_gb, disk_free_gb, disk_pct = 0, 0, 0, 0
    try:
        usage = shutil.disk_usage(storage_root if os.path.exists(storage_root) else "/")
        disk_total_gb = round(usage.total / (1024**3), 1)
        disk_used_gb = round(usage.used / (1024**3), 1)
        disk_free_gb = round(usage.free / (1024**3), 1)
        disk_pct = int((usage.used / max(1, usage.total)) * 100)
    except Exception:
        pass

    # 5. Sing-box proxy active node info
    active_node = "Определяется..."
    try:
        adm_p = get_admin_pass()
        req = urllib.request.Request(
            "http://127.0.0.1:9090/proxies",
            headers={"Authorization": f"Bearer {adm_p}"}
        )
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            data = json.loads(resp.read().decode())
            proxies = data.get("proxies", {})
            auto_group = proxies.get("⚡ Авто (Самый быстрый)", {})
            active_node = auto_group.get("now", "Auto")
    except Exception:
        pass

    # 6. Service statuses (OpenRC)
    services = ["sing-box", "adguardhome", "caddy", "metube", "transmission-daemon", "vaultwarden", "forgejo", "samba"]
    service_status = {}
    for s in services:
        try:
            res = subprocess.run(["rc-service", s, "status"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            service_status[s] = "running" if res.returncode == 0 else "stopped"
        except Exception:
            service_status[s] = "unknown"

    # 7. Slot information
    gw_env = load_env_file(GATEWAY_ENV_FILE)
    hl_env = load_env_file(HOMELAB_ENV_FILE)

    sub_url = gw_env.get("SUB_URL", "")
    has_sub = bool(sub_url and ("http://" in sub_url or "https://" in sub_url))

    warp_file = "/etc/sing-box/providers/warp_nodes.json"
    warp_active = False
    if os.path.exists(warp_file):
        try:
            with open(warp_file, "r") as f:
                w_data = json.load(f)
                warp_active = len(w_data.get("outbounds", [])) > 0
        except Exception:
            pass

    return {
        "ram": {"total_mb": mem_total_mb, "used_mb": mem_used_mb, "free_mb": mem_avail_mb, "pct": mem_pct},
        "cpu": {"load1": round(load1, 2), "load5": round(load5, 2), "temp": cpu_temp},
        "uptime": uptime_sec,
        "storage": {"total_gb": disk_total_gb, "used_gb": disk_used_gb, "free_gb": disk_free_gb, "pct": disk_pct},
        "active_node": active_node,
        "services": service_status,
        "slots": {
            "slot1_sub": {"active": has_sub, "url": sub_url if has_sub else ""},
            "slot3_warp": {"active": warp_active}
        },
        "ssl": {
            "type": hl_env.get("SSL_TYPE", "local"),
            "domain": hl_env.get("SSL_DOMAIN", "inadzumka.duckdns.org" if hl_env.get("SSL_TYPE") == "letsencrypt" else "lan")
        }
    }


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


class GatewayApiHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Quiet standard HTTP access logs to keep terminal and files clean
        return

    def send_json(self, status_code, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Gateway-Token")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Gateway-Token")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]

        # Public auth verification endpoint
        if path == "/api/auth/verify":
            if check_auth(self.headers):
                return self.send_json(200, {"status": "ok", "authenticated": True})
            return self.send_json(401, {"status": "error", "message": "Неверный пароль"})

        # All other endpoints require authentication
        if not check_auth(self.headers):
            return self.send_json(401, {"status": "error", "message": "Требуется авторизация"})

        if path == "/api/status":
            return self.send_json(200, get_system_metrics())

        if path == "/api/domains":
            direct_file = "/etc/sing-box/rule_sets/user_direct_domains.list"
            proxy_file = "/etc/sing-box/rule_sets/user_proxy_domains.list"
            direct_list = []
            proxy_list = []
            if os.path.exists(direct_file):
                with open(direct_file, "r") as f:
                    direct_list = [l.strip() for l in f if l.strip() and not l.startswith("#")]
            if os.path.exists(proxy_file):
                with open(proxy_file, "r") as f:
                    proxy_list = [l.strip() for l in f if l.strip() and not l.startswith("#")]
            return self.send_json(200, {"direct": direct_list, "proxy": proxy_list})

        self.send_json(404, {"status": "error", "message": "Маршрут не найден"})

    def do_POST(self):
        path = self.path.split("?")[0]

        if not check_auth(self.headers):
            return self.send_json(401, {"status": "error", "message": "Требуется авторизация"})

        content_length = int(self.headers.get("Content-Length", 0))
        body_bytes = self.rfile.read(content_length) if content_length > 0 else b"{}"
        try:
            payload = json.loads(body_bytes.decode("utf-8")) if body_bytes else {}
        except Exception:
            payload = {}

        # 1. Action: Stream long-running command (gw doctor, gw update, etc.) via SSE
        if path == "/api/action/stream":
            cmd = payload.get("cmd", "")
            valid_cmds = {
                "doctor": [GATEWAY_BIN, "doctor"],
                "update": [GATEWAY_BIN, "update"],
                "restart": [GATEWAY_BIN, "restart"],
                "test": [GATEWAY_BIN, "test"],
                "warp_enable": [GATEWAY_BIN, "proxy", "add", "warp"],
            }
            if cmd not in valid_cmds:
                return self.send_json(400, {"status": "error", "message": "Неизвестная команда"})

            # Send Server-Sent Events headers
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

            # Execute command and stream output line by line
            proc = subprocess.Popen(
                valid_cmds[cmd],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            try:
                for line in proc.stdout:
                    sse_chunk = f"data: {json.dumps({'line': line.rstrip()})}\n\n"
                    self.wfile.write(sse_chunk.encode("utf-8"))
                    self.wfile.flush()
                proc.wait()
                done_chunk = f"data: {json.dumps({'done': True, 'code': proc.returncode})}\n\n"
                self.wfile.write(done_chunk.encode("utf-8"))
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                proc.kill()
            return

        # 2. Add subscription / proxy key
        if path == "/api/proxy/add":
            url = payload.get("url", "").strip()
            if not url:
                return self.send_json(400, {"status": "error", "message": "Ссылка не указана"})
            res = subprocess.run([GATEWAY_BIN, "proxy", "add", url], capture_output=True, text=True)
            return self.send_json(200, {"status": "ok" if res.returncode == 0 else "error", "output": res.stdout + res.stderr})

        # 3. Add domain routing rule (direct / proxy)
        if path == "/api/domain/rule":
            domain = payload.get("domain", "").strip()
            mode = payload.get("mode", "proxy")
            if not domain:
                return self.send_json(400, {"status": "error", "message": "Домен не указан"})
            if mode not in ["direct", "proxy"]:
                return self.send_json(400, {"status": "error", "message": "Неверный режим"})
            res = subprocess.run([GATEWAY_BIN, "domain", mode, domain], capture_output=True, text=True)
            return self.send_json(200, {"status": "ok" if res.returncode == 0 else "error", "output": res.stdout + res.stderr})

        # 4. Service restart (sing-box, adguardhome, metube, etc.)
        if path == "/api/service/control":
            service = payload.get("service", "")
            action = payload.get("action", "restart")
            allowed_services = ["sing-box", "adguardhome", "caddy", "metube", "transmission-daemon", "vaultwarden", "forgejo", "code-server", "samba"]
            if service not in allowed_services or action not in ["restart", "stop", "start"]:
                return self.send_json(400, {"status": "error", "message": "Недопустимый сервис или действие"})
            res = subprocess.run(["rc-service", service, action], capture_output=True, text=True)
            return self.send_json(200, {"status": "ok" if res.returncode == 0 else "error", "output": res.stdout + res.stderr})

        # 5. Safe reboot
        if path == "/api/system/safe-reboot":
            subprocess.Popen(["sh", "-c", "sleep 1 && /usr/bin/gateway safe-reboot"])
            return self.send_json(200, {"status": "ok", "message": "Шлюз безопасно перезагружается..."})

        self.send_json(404, {"status": "error", "message": "Маршрут не найден"})


def main():
    server = ThreadedHTTPServer((HOST, PORT), GatewayApiHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()


if __name__ == "__main__":
    main()
