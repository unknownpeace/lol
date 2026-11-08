#!/usr/bin/env python3
# ==============================================================================
# Universal Gateway REST & SSE Dashboard API Daemon (Alpine Linux Native)
# Standard library only (zero external pip/npm dependencies, ultra-low RAM ~15MB)
# ==============================================================================

import os
import sys
import json
import time
import shutil
import subprocess
import urllib.request
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

HOST = "127.0.0.1"
PORT = 8080
GATEWAY_BIN = "/usr/bin/gateway"
GATEWAY_ENV_FILE = "/etc/sing-box/gateway.env"
HOMELAB_ENV_FILE = "/srv/homelab/homelab.env"
CUSTOM_NODES_FILE = "/etc/sing-box/providers/my_nodes.yaml"
USER_SUB_LIST = "/etc/sing-box/providers/user_subscriptions.list"
DIRECT_DOMAINS_FILE = "/etc/sing-box/rule_sets/user_direct_domains.list"
PROXY_DOMAINS_FILE = "/etc/sing-box/rule_sets/user_proxy_domains.list"


def load_env_file(filepath):
    """Parses key=value shell environment file safely."""
    data = {}
    if not os.path.exists(filepath):
        return data
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    data[k.strip()] = v.strip().strip('"').strip("'")
    except Exception:
        pass
    return data


def get_admin_pass():
    env = load_env_file(GATEWAY_ENV_FILE)
    return env.get("ADMIN_PASS", "")


def check_auth(headers):
    """Verifies X-Gateway-Token or Authorization Bearer header against ADMIN_PASS."""
    expected = get_admin_pass()
    if not expected:
        return True
    token = headers.get("X-Gateway-Token")
    if token and token == expected:
        return True
    auth = headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        token = auth[7:].strip()
        if token == expected:
            return True
    return False


def get_custom_nodes():
    """Parses my_nodes.yaml for URI keys."""
    nodes = []
    if not os.path.exists(CUSTOM_NODES_FILE):
        return nodes
    try:
        idx = 0
        with open(CUSTOM_NODES_FILE, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or line.startswith("proxies:"):
                    continue
                idx += 1
                proto = line.split("://")[0] if "://" in line else "proxy"
                tag = "(без названия)"
                if "#" in line:
                    tag = urllib.parse.unquote(line.split("#", 1)[1])
                nodes.append({"index": idx, "proto": proto, "tag": tag, "raw": line})
    except Exception:
        pass
    return nodes


def get_lxc_containers():
    """Lists LXC containers on Alpine host via lxc-info."""
    containers = []
    try:
        res = subprocess.run(["lxc-ls", "-1"], capture_output=True, text=True)
        if res.returncode == 0:
            names = [n.strip() for n in res.stdout.splitlines() if n.strip()]
            for name in names:
                info_res = subprocess.run(["lxc-info", "-n", name], capture_output=True, text=True)
                state = "STOPPED"
                ip = "-"
                ram = "-"
                for line in info_res.stdout.splitlines():
                    line = line.strip()
                    if line.startswith("State:"):
                        state = line.split(":", 1)[1].strip()
                    elif line.startswith("IP:"):
                        ip = line.split(":", 1)[1].strip()
                    elif line.startswith("Memory use:"):
                        ram = line.split(":", 1)[1].strip()
                containers.append({"name": name, "state": state, "ip": ip, "ram": ram})
    except Exception:
        pass
    return containers


def get_ssl_details():
    """Retrieves full SSL details (Let's Encrypt vs Local CA)."""
    hl_env = load_env_file(HOMELAB_ENV_FILE)
    ssl_type = hl_env.get("SSL_TYPE", "local")
    ssl_domain = hl_env.get("SSL_DOMAIN", "inadzumka.duckdns.org" if ssl_type == "letsencrypt" else "lan")
    fullchain = "/etc/ssl/caddy/fullchain.pem"
    days_left = None
    issuer = "Alpine Homelab CA"

    if ssl_type == "letsencrypt" and os.path.exists(fullchain):
        try:
            res = subprocess.run(["openssl", "x509", "-in", fullchain, "-noout", "-enddate", "-issuer"], capture_output=True, text=True)
            for line in res.stdout.splitlines():
                if line.startswith("notAfter="):
                    date_str = line.split("=", 1)[1].strip()
                    # e.g. Feb  6 17:44:11 2027 GMT
                    import email.utils
                    parsed = email.utils.parsedate_to_datetime(date_str)
                    now = time.time()
                    diff = parsed.timestamp() - now
                    days_left = max(0, int(diff // 86400))
                elif line.startswith("issuer="):
                    if "CN=" in line:
                        issuer = line.split("CN=")[-1].strip()
                    else:
                        issuer = "Let's Encrypt"
        except Exception:
            pass

    return {
        "type": ssl_type,
        "domain": ssl_domain,
        "days_left": days_left,
        "issuer": issuer
    }


def get_system_metrics():
    """Collects real-time RAM, CPU, Load, Storage, Services, LXC, and Proxy info."""
    # 1. RAM
    mem_total_mb, mem_avail_mb, mem_used_mb, mem_pct = 0, 0, 0, 0
    try:
        with open("/proc/meminfo", "r") as f:
            lines = f.readlines()
        mem = {}
        for line in lines:
            parts = line.split(":")
            if len(parts) == 2:
                mem[parts[0].strip()] = int(parts[1].split()[0])
        total_kb = mem.get("MemTotal", 0)
        avail_kb = mem.get("MemAvailable", mem.get("MemFree", 0))
        mem_total_mb = total_kb // 1024
        mem_avail_mb = avail_kb // 1024
        mem_used_mb = mem_total_mb - mem_avail_mb
        mem_pct = int((mem_used_mb / max(1, mem_total_mb)) * 100)
    except Exception:
        pass

    # 2. CPU load & temp
    load1, load5 = 0.0, 0.0
    try:
        load1, load5, _ = os.getloadavg()
    except Exception:
        pass

    cpu_temp = None
    for t_path in ["/sys/class/thermal/thermal_zone0/temp", "/sys/class/hwmon/hwmon0/temp1_input"]:
        if os.path.exists(t_path):
            try:
                with open(t_path, "r") as f:
                    cpu_temp = round(int(f.read().strip()) / 1000.0, 1)
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
    active_node = "Compatible"
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
            active_node = auto_group.get("now", "Compatible")
    except Exception:
        pass

    # 6. Service statuses (OpenRC)
    services = ["sing-box", "adguardhome", "caddy", "metube", "transmission-daemon", "vaultwarden", "forgejo", "samba", "lxc"]
    service_status = {}
    for s in services:
        try:
            res = subprocess.run(["rc-service", s, "status"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            service_status[s] = "running" if res.returncode == 0 else "stopped"
        except Exception:
            service_status[s] = "unknown"

    # 7. Slot information
    gw_env = load_env_file(GATEWAY_ENV_FILE)
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

    custom_nodes = get_custom_nodes()
    lxc_containers = get_lxc_containers()
    ssl_details = get_ssl_details()

    # LUKS2 status
    luks_unlocked = os.path.ismount("/srv/storage") and os.path.exists("/dev/mapper/homelab_storage")

    return {
        "ram": {"total_mb": mem_total_mb, "used_mb": mem_used_mb, "free_mb": mem_avail_mb, "pct": mem_pct},
        "cpu": {"load1": round(load1, 2), "load5": round(load5, 2), "temp": cpu_temp},
        "uptime": uptime_sec,
        "storage": {"total_gb": disk_total_gb, "used_gb": disk_used_gb, "free_gb": disk_free_gb, "pct": disk_pct, "luks": luks_unlocked},
        "active_node": active_node,
        "services": service_status,
        "slots": {
            "slot1_sub": {"active": has_sub, "url": sub_url if has_sub else ""},
            "slot2_keys": {"count": len(custom_nodes), "nodes": custom_nodes},
            "slot3_warp": {"active": warp_active}
        },
        "ssl": ssl_details,
        "lxc": lxc_containers
    }


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


class GatewayApiHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
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

        if path == "/api/auth/verify":
            if check_auth(self.headers):
                return self.send_json(200, {"status": "ok", "authenticated": True})
            return self.send_json(401, {"status": "error", "message": "Неверный пароль"})

        if not check_auth(self.headers):
            return self.send_json(401, {"status": "error", "message": "Требуется авторизация"})

        if path == "/api/status":
            return self.send_json(200, get_system_metrics())

        if path == "/api/domains":
            direct_list, proxy_list = [], []
            if os.path.exists(DIRECT_DOMAINS_FILE):
                with open(DIRECT_DOMAINS_FILE, "r", encoding="utf-8", errors="ignore") as f:
                    direct_list = [l.strip() for l in f if l.strip() and not l.startswith("#")]
            if os.path.exists(PROXY_DOMAINS_FILE):
                with open(PROXY_DOMAINS_FILE, "r", encoding="utf-8", errors="ignore") as f:
                    proxy_list = [l.strip() for l in f if l.strip() and not l.startswith("#")]
            return self.send_json(200, {"direct": direct_list, "proxy": proxy_list})

        if path == "/api/backup/download":
            backup_file = "/root/gateway_backup.tar.gz"
            if not os.path.exists(backup_file):
                subprocess.run([GATEWAY_BIN, "backup", "create"], capture_output=True)
            if os.path.exists(backup_file):
                try:
                    fsize = os.path.getsize(backup_file)
                    self.send_response(200)
                    self.send_header("Content-Type", "application/gzip")
                    self.send_header("Content-Disposition", 'attachment; filename="gateway_backup.tar.gz"')
                    self.send_header("Content-Length", str(fsize))
                    self.end_headers()
                    with open(backup_file, "rb") as bf:
                        shutil.copyfileobj(bf, self.wfile)
                    return
                except Exception as e:
                    return self.send_json(500, {"status": "error", "message": str(e)})
            return self.send_json(404, {"status": "error", "message": "Файл бэкапа не найден"})

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

        # 1. Action: Stream long-running command via SSE
        if path == "/api/action/stream":
            cmd = payload.get("cmd", "")
            valid_cmds = {
                "doctor": [GATEWAY_BIN, "doctor"],
                "update": [GATEWAY_BIN, "update"],
                "restart": [GATEWAY_BIN, "restart"],
                "test": [GATEWAY_BIN, "test"],
                "warp_enable": [GATEWAY_BIN, "proxy", "add", "warp"],
                "warp_disable": [GATEWAY_BIN, "proxy", "del", "warp"],
                "sub_clear": [GATEWAY_BIN, "proxy", "del", "sub"],
                "ssl_renew": [GATEWAY_BIN, "ssl", "renew"],
                "ssl_local": [GATEWAY_BIN, "ssl", "local"],
                "backup_create": [GATEWAY_BIN, "backup", "create"],
                "backup_telegram": [GATEWAY_BIN, "backup", "telegram"],
            }
            if cmd not in valid_cmds:
                return self.send_json(400, {"status": "error", "message": "Неизвестная команда"})

            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

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

        # 3. Delete proxy (sub, warp, or key by index)
        if path == "/api/proxy/delete":
            target = str(payload.get("target", "")).strip()
            if not target:
                return self.send_json(400, {"status": "error", "message": "Цель удаления не указана"})
            res = subprocess.run([GATEWAY_BIN, "proxy", "del", target], capture_output=True, text=True)
            return self.send_json(200, {"status": "ok" if res.returncode == 0 else "error", "output": res.stdout + res.stderr})

        # 4. Domain route add
        if path == "/api/domain/rule":
            domain = payload.get("domain", "").strip()
            mode = payload.get("mode", "proxy")
            if not domain:
                return self.send_json(400, {"status": "error", "message": "Домен не указан"})
            if mode not in ["direct", "proxy"]:
                return self.send_json(400, {"status": "error", "message": "Неверный режим"})
            res = subprocess.run([GATEWAY_BIN, "domain", mode, domain], capture_output=True, text=True)
            return self.send_json(200, {"status": "ok" if res.returncode == 0 else "error", "output": res.stdout + res.stderr})

        # 5. Domain route delete
        if path == "/api/domain/delete":
            domain = payload.get("domain", "").strip()
            if not domain:
                return self.send_json(400, {"status": "error", "message": "Домен не указан"})
            res = subprocess.run([GATEWAY_BIN, "domain", "del", domain], capture_output=True, text=True)
            return self.send_json(200, {"status": "ok" if res.returncode == 0 else "error", "output": res.stdout + res.stderr})

        # 6. Service control
        if path == "/api/service/control":
            service = payload.get("service", "")
            action = payload.get("action", "restart")
            allowed_services = ["sing-box", "adguardhome", "caddy", "metube", "transmission-daemon", "vaultwarden", "forgejo", "code-server", "samba", "lxc"]
            if service not in allowed_services or action not in ["restart", "stop", "start"]:
                return self.send_json(400, {"status": "error", "message": "Недопустимый сервис или действие"})
            res = subprocess.run(["rc-service", service, action], capture_output=True, text=True)
            return self.send_json(200, {"status": "ok" if res.returncode == 0 else "error", "output": res.stdout + res.stderr})

        # 7. LXC container control
        if path == "/api/lxc/control":
            name = payload.get("name", "").strip()
            action = payload.get("action", "start")
            if not name or action not in ["start", "stop", "restart", "delete"]:
                return self.send_json(400, {"status": "error", "message": "Неверные параметры LXC"})
            cmd_action = "rm" if action == "delete" else action
            res = subprocess.run([GATEWAY_BIN, "lxc", cmd_action, name], capture_output=True, text=True)
            return self.send_json(200, {"status": "ok" if res.returncode == 0 else "error", "output": res.stdout + res.stderr})

        # 8. Setup DuckDNS SSL
        if path == "/api/ssl/duckdns":
            domain = payload.get("domain", "").strip()
            token = payload.get("token", "").strip()
            if not domain or not token:
                return self.send_json(400, {"status": "error", "message": "Домен и токен DuckDNS обязательны"})
            res = subprocess.run([GATEWAY_BIN, "ssl", "duckdns", domain, token], capture_output=True, text=True)
            return self.send_json(200, {"status": "ok" if res.returncode == 0 else "error", "output": res.stdout + res.stderr})

        # 9. System safe reboot
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
