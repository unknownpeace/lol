#!/usr/bin/env python3
"""Lightweight zero-dependency HTTP server for the Alpine Gateway & Homelab Web Dashboard."""

import base64
import hmac
import json
import mimetypes
import os
import re
import secrets
import select
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
GATEWAY_DIR = os.environ.get("GATEWAY_DIR") or os.path.realpath(os.path.join(SCRIPT_DIR, "..", ".."))
API_SH = os.path.join(GATEWAY_DIR, "modules", "webui", "api.sh")
STATIC_DIR = os.path.realpath(os.path.join(SCRIPT_DIR, "static"))
ENV_FILE = os.environ.get("GATEWAY_ENV_FILE", "/etc/sing-box/gateway.env")
HOMELAB_ENV_FILE = os.environ.get("GATEWAY_HOMELAB_ENV_FILE", "/etc/sing-box/homelab.env")
PROXY_TOKEN_FILE = os.environ.get("GATEWAY_PROXY_TOKEN_FILE", "/etc/sing-box/homelab/webui_proxy.token")
RUN_GW_DIR = "/run/gateway"
CONSOLE_TOK_DIR = os.path.join(RUN_GW_DIR, "console_tokens")

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
HTTP_SOCKET_TIMEOUT = 20.0
WS_IDLE_TIMEOUT = 300.0
WS_WRITE_STALL_TIMEOUT = 30.0
WS_MAX_PENDING_BYTES = 65536
DU_CACHE_TTL = 120.0

SB_DIR = "/etc/sing-box"
SB_CONF = os.path.join(SB_DIR, "config.json")
CUSTOM_NODES_FILE = os.path.join(SB_DIR, "providers", "my_nodes.yaml")
WARP_NODES_FILE = os.path.join(SB_DIR, "providers", "warp_nodes.json")
USER_DIRECT_FILE = os.path.join(SB_DIR, "rule_sets", "user_direct_domains.list")
USER_PROXY_FILE = os.path.join(SB_DIR, "rule_sets", "user_proxy_domains.list")
USER_BYPASS_IPS = os.path.join(SB_DIR, "bypass_devices.conf")
USER_FORCE_PROXY_IPS = os.path.join(SB_DIR, "force_proxy_devices.conf")
BACKUP_ARCHIVE = "/root/gateway_backup.tar.gz"
CRON_FILE = "/etc/crontabs/root"
UI_DIR = os.path.join(SB_DIR, "ui")
UI_VER_FILE = os.path.join(UI_DIR, ".ui_version")
UI_TYPE_FILE = os.path.join(UI_DIR, ".ui_type")
AGH_CONF = "/etc/AdGuardHome/AdGuardHome.yaml"
ALPINE_NFT_CONF = "/etc/nftables.nft"
HOMELAB_STATE = os.path.join(SB_DIR, "homelab", "modules.state")
SSL_FULLCHAIN_FILE = "/etc/ssl/caddy/fullchain.pem"
SSL_KEY_FILE = "/etc/ssl/caddy/key.pem"
LUKS_KEYFILE = "/etc/sing-box/homelab/storage.luks.key"
LUKS_MAPPER_NAME = "homelab_storage"

GROUP_ORDER = [
    "⚡ Авто (Самый быстрый)",
    "🤖 Нейросети (ИИ)",
    "🤖 Авто-ИИ",
    "🇩🇪 Германия",
    "🇩🇪 Авто-DE",
    "🇺🇸 США",
    "🇺🇸 Авто-US",
    "▶️ YouTube & Медиа",
    "💬 Мессенджеры",
    "🎮 Гейминг",
    "🎮 Авто-Гейминг",
    "🧱 Roblox",
    "🛑 Обход блокировок",
    "🌐 Google & Android",
    "🧲 Торренты",
    "🌐 Остальной трафик",
]

_ARG_REDACT_RE = re.compile(r"([?&](?:arg|token)=)[^&\s\"]+", re.IGNORECASE)
_LAN_LABEL_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\.lan$")
_IPV4_RE = re.compile(r"^\d+\.\d+\.\d+\.\d+$")
_HEX32_RE = re.compile(r"^[a-f0-9]{32}$")

_CRED_LOCK = threading.Lock()
_CRED_CACHE = {"gw_sig": None, "hl_sig": None, "gw_env": {}, "hl_env": {}, "user": "admin", "password": ""}

_TOKEN_LOCK = threading.Lock()
_TOKEN_CACHE = {"sig": None, "token": ""}

_AUTH_FAIL_LOCK = threading.Lock()
_AUTH_FAILS = {}

_NET_LOCK = threading.Lock()
_NET_CACHE = {"ts": 0.0, "lan_if": "", "lan_ip": "", "gw_ip": "", "local_ips": set()}

_VER_LOCK = threading.Lock()
_VER_CACHE = {}

_AGH_COOKIE_LOCK = threading.Lock()
_AGH_COOKIE_CACHE = {"cred_key": None, "cookie": ""}

_DU_LOCK = threading.Lock()
_DU_CACHE = {"ts": 0.0, "data": {}, "refreshing": False}
_DU_EVENT = threading.Event()

_SSL_LOCK = threading.Lock()
_SSL_CACHE = {"sig": None, "issuer": "", "expiry": "", "days_left": 0}

_GIT_LOCK = threading.Lock()
_GIT_CACHE = {"sig": None, "is_repo": False, "sha": "Standalone", "branch": "main"}


class _BodyReadError(Exception):
    def __init__(self, code, message):
        self.code = code
        self.message = message


mimetypes.init()
mimetypes.add_type("application/javascript; charset=utf-8", ".js")
mimetypes.add_type("text/css; charset=utf-8", ".css")
mimetypes.add_type("text/html; charset=utf-8", ".html")
mimetypes.add_type("image/svg+xml", ".svg")


def _file_sig(path):
    try:
        st = os.stat(path)
        return (st.st_mtime_ns, st.st_size, st.st_ino)
    except OSError:
        return None


def _parse_env_file(path):
    res = {}
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for raw_line in fh:
                line = raw_line.rstrip("\r\n")
                stripped = line.lstrip()
                if not stripped or stripped.startswith("#") or "=" not in stripped:
                    continue
                k, v = stripped.split("=", 1)
                k = k.strip()
                if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k):
                    continue
                v = v.strip()
                if len(v) >= 2 and v[0] == "'" and v[-1] == "'":
                    v = v[1:-1].replace("'\\''", "'")
                elif len(v) >= 2 and v[0] == '"' and v[-1] == '"':
                    v = v[1:-1].replace('\\"', '"').replace("\\\\", "\\")
                res[k] = v
    except OSError:
        pass
    return res


def _read_agh_user_from_yaml():
    try:
        in_users = False
        with open(AGH_CONF, "r", encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                line = raw.rstrip("\r\n")
                if line.startswith("users:"):
                    in_users = True
                    continue
                if in_users:
                    if line and not line[0].isspace():
                        break
                    m = re.match(r"^\s*-\s*name:\s*(.+?)\s*$", line)
                    if m:
                        return m.group(1).strip("\"'")
    except OSError:
        pass
    return ""


def _read_sb_conf_fallbacks(gw_env):
    gw_ip = gw_env.get("GW_IP", "")
    admin_pass = gw_env.get("ADMIN_PASS", "")
    sub_url = gw_env.get("SUB_URL", "")
    has_sub_key = "SUB_URL" in gw_env
    if (gw_ip and admin_pass and (sub_url or has_sub_key)) or not os.path.isfile(SB_CONF):
        return gw_ip, admin_pass, sub_url
    try:
        with open(SB_CONF, "r", encoding="utf-8", errors="replace") as fh:
            cfg = json.load(fh)
        if not gw_ip:
            for srv in (cfg.get("dns") or {}).get("servers") or []:
                if isinstance(srv, dict) and srv.get("tag") == "dns_local" and srv.get("server"):
                    gw_ip = str(srv.get("server"))
                    break
        if not admin_pass:
            secret = ((cfg.get("experimental") or {}).get("clash_api") or {}).get("secret")
            if secret:
                admin_pass = str(secret)
        if not sub_url and not has_sub_key:
            urls = [
                str(p.get("url"))
                for p in (cfg.get("providers") or [])
                if isinstance(p, dict) and p.get("type") == "remote" and p.get("url")
            ]
            sub_url = " ".join(urls).strip()
    except Exception:
        pass
    return gw_ip, admin_pass, sub_url


def _load_env_cached():
    with _CRED_LOCK:
        gw_sig = _file_sig(ENV_FILE)
        hl_sig = _file_sig(HOMELAB_ENV_FILE)
        if gw_sig != _CRED_CACHE["gw_sig"] or hl_sig != _CRED_CACHE["hl_sig"]:
            gw_env = _parse_env_file(ENV_FILE)
            hl_env = _parse_env_file(HOMELAB_ENV_FILE)
            gw_ip, admin_pass, sub_url = _read_sb_conf_fallbacks(gw_env)
            if gw_ip and not gw_env.get("GW_IP"):
                gw_env["GW_IP"] = gw_ip
            if admin_pass and not gw_env.get("ADMIN_PASS"):
                gw_env["ADMIN_PASS"] = admin_pass
            if sub_url and "SUB_URL" not in gw_env:
                gw_env["SUB_URL"] = sub_url

            user = gw_env.get("AGH_USER") or _read_agh_user_from_yaml() or hl_env.get("SMB_USER") or "admin"
            password = gw_env.get("ADMIN_PASS") or ""

            _CRED_CACHE["gw_sig"] = gw_sig
            _CRED_CACHE["hl_sig"] = hl_sig
            _CRED_CACHE["gw_env"] = gw_env
            _CRED_CACHE["hl_env"] = hl_env
            _CRED_CACHE["user"] = user
            _CRED_CACHE["password"] = password

        return dict(_CRED_CACHE["gw_env"]), dict(_CRED_CACHE["hl_env"]), _CRED_CACHE["user"], _CRED_CACHE["password"]


def _load_credentials():
    _, _, user, password = _load_env_cached()
    return user, password


def _ensure_runtime_dirs():
    for d in (RUN_GW_DIR, CONSOLE_TOK_DIR):
        try:
            os.makedirs(d, mode=0o700, exist_ok=True)
            os.chmod(d, 0o700)
        except OSError:
            pass


def _ensure_proxy_token():
    with _TOKEN_LOCK:
        try:
            with open(PROXY_TOKEN_FILE, "r", encoding="utf-8") as fh:
                cur = fh.read().strip()
            if _HEX32_RE.match(cur):
                try:
                    os.chmod(PROXY_TOKEN_FILE, 0o600)
                except OSError:
                    pass
                _TOKEN_CACHE["sig"] = _file_sig(PROXY_TOKEN_FILE)
                _TOKEN_CACHE["token"] = cur
                return cur
        except OSError:
            pass

        parent = os.path.dirname(PROXY_TOKEN_FILE)
        try:
            os.makedirs(parent, mode=0o750, exist_ok=True)
        except OSError:
            pass

        new_tok = secrets.token_hex(16)
        tmp_path = f"{PROXY_TOKEN_FILE}.tmp.{os.getpid()}"
        try:
            fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(new_tok + "\n")
            os.chmod(tmp_path, 0o600)
            os.replace(tmp_path, PROXY_TOKEN_FILE)
            os.chmod(PROXY_TOKEN_FILE, 0o600)
        except OSError:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        _TOKEN_CACHE["sig"] = _file_sig(PROXY_TOKEN_FILE)
        _TOKEN_CACHE["token"] = new_tok
        return new_tok


def _get_proxy_token():
    sig = _file_sig(PROXY_TOKEN_FILE)
    with _TOKEN_LOCK:
        if sig is not None and sig == _TOKEN_CACHE["sig"] and _TOKEN_CACHE["token"]:
            return _TOKEN_CACHE["token"]
    return _ensure_proxy_token()


def _extract_host_only(raw_host):
    if not raw_host:
        return ""
    s = raw_host.strip().lower()
    if s.startswith("["):
        end = s.find("]")
        if end == -1:
            return ""
        rest = s[end + 1:]
        if rest and (not rest.startswith(":") or not rest[1:].isdigit()):
            return ""
        return s[1:end]
    if ":" in s:
        host_part, port_part = s.rsplit(":", 1)
        if not port_part.isdigit():
            return ""
        return host_part
    return s


def _get_network_snapshot(force=False):
    now = time.monotonic()
    with _NET_LOCK:
        if not force and (now - _NET_CACHE["ts"]) < 5.0 and _NET_CACHE["lan_ip"]:
            return _NET_CACHE["lan_if"], _NET_CACHE["lan_ip"], _NET_CACHE["gw_ip"], set(_NET_CACHE["local_ips"])

    excluded_exact = {"gateway-tun", "singbox-tun", "mihomo0", "lo", "lxcbr0"}
    excluded_prefixes = ("veth", "docker", "br-", "wg", "tun")

    def _is_excl(ifname):
        return ifname in excluded_exact or ifname.startswith(excluded_prefixes)

    lan_if = ""
    gw_ip = ""
    local_ips = set()
    if_ips = {}

    try:
        with open("/proc/net/route", "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
        for line in lines[1:]:
            cols = line.split()
            if len(cols) < 4:
                continue
            iface, dest_hex, gw_hex, flags_hex = cols[0], cols[1], cols[2], cols[3]
            if dest_hex != "00000000":
                continue
            try:
                flags = int(flags_hex, 16)
            except ValueError:
                continue
            if not (flags & 0x1):
                continue
            if not _is_excl(iface) and not lan_if:
                lan_if = iface
            try:
                gw_int = int(gw_hex, 16)
                cand_gw = socket.inet_ntoa(gw_int.to_bytes(4, "little"))
                if cand_gw not in ("0.0.0.0", "172.19.0.1") and not gw_ip:
                    gw_ip = cand_gw
            except Exception:
                pass
    except OSError:
        pass

    try:
        proc = subprocess.run(
            ["ip", "-4", "-o", "addr", "show", "scope", "global"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
        for line in proc.stdout.decode("utf-8", errors="replace").splitlines():
            parts = line.split()
            if len(parts) >= 4 and parts[2] == "inet":
                ifn = parts[1].rstrip(":")
                ip_addr = parts[3].split("/", 1)[0]
                if _IPV4_RE.match(ip_addr):
                    local_ips.add(ip_addr)
                    if ifn not in if_ips:
                        if_ips[ifn] = ip_addr
    except Exception:
        pass

    if not lan_if:
        if "eth0" in if_ips:
            lan_if = "eth0"
        else:
            for ifn in if_ips:
                if not _is_excl(ifn):
                    lan_if = ifn
                    break
        if not lan_if:
            lan_if = "eth0"

    lan_ip = if_ips.get(lan_if) or if_ips.get("eth0") or ""
    if not lan_ip:
        try:
            with open("/etc/network/interfaces", "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    m = re.match(r"^\s*address\s+(\d+\.\d+\.\d+\.\d+)", line)
                    if m:
                        lan_ip = m.group(1)
                        break
        except OSError:
            pass
    if not lan_ip:
        lan_ip = "192.168.1.2"
    local_ips.add(lan_ip)

    with _NET_LOCK:
        _NET_CACHE["ts"] = now
        _NET_CACHE["lan_if"] = lan_if
        _NET_CACHE["lan_ip"] = lan_ip
        _NET_CACHE["gw_ip"] = gw_ip
        _NET_CACHE["local_ips"] = set(local_ips)

    return lan_if, lan_ip, gw_ip, local_ips


def _invalidate_net_cache():
    with _NET_LOCK:
        _NET_CACHE["ts"] = 0.0


def _is_allowed_host(hostname):
    if not hostname:
        return False
    if hostname in ("localhost", "127.0.0.1", "::1"):
        return True
    if BIND_HOST and BIND_HOST != "0.0.0.0" and hostname == BIND_HOST.lower():
        return True
    _, _, _, local_ips = _get_network_snapshot()
    if hostname in local_ips:
        return True
    if _LAN_LABEL_RE.match(hostname):
        return True
    _, hl_env, _, _ = _load_env_cached()
    ssl_dom = (hl_env.get("SSL_DOMAIN") or "").strip().lower().lstrip(".")
    if ssl_dom and (hostname == ssl_dom or hostname.endswith("." + ssl_dom)):
        return True
    return False


def _fmt_du_size(num_bytes):
    if num_bytes < 1024:
        return f"{num_bytes}B"
    val = float(num_bytes)
    for unit in ("K", "M", "G", "T"):
        val /= 1024.0
        if val < 1024.0 or unit == "T":
            if val >= 100 or abs(val - round(val)) < 0.05:
                return f"{val:.0f}{unit}"
            return f"{val:.1f}{unit}"
    return f"{num_bytes}"


def _read_text(path, default=""):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return default


def _find_proc_pids():
    targets = {"sing-box": None, "mihomo": None, "AdGuardHome": None, "smbd": None, "caddy": None, "ttyd": None}
    try:
        entries = os.listdir("/proc")
    except OSError:
        return targets
    for ent in entries:
        if not ent.isdigit():
            continue
        comm = _read_text(f"/proc/{ent}/comm").strip()
        if comm in targets and targets[comm] is None:
            targets[comm] = ent
    return targets


def _read_proc_rss_mb(pid):
    if not pid:
        return ""
    txt = _read_text(f"/proc/{pid}/status")
    m = re.search(r"^VmRSS:\s+(\d+)\s+kB", txt, re.MULTILINE)
    if not m:
        return ""
    kb = int(m.group(1))
    return f"{kb / 1024.0:.1f} МБ"


def _read_proc_env_var(pid, key):
    if not pid:
        return ""
    try:
        with open(f"/proc/{pid}/environ", "rb") as fh:
            raw = fh.read()
        prefix = (key + "=").encode("utf-8")
        for item in raw.split(b"\x00"):
            if item.startswith(prefix):
                return item[len(prefix):].decode("utf-8", errors="replace")
    except OSError:
        pass
    return ""


def _get_cached_version(key, bin_path, cmd_args, parser_fn):
    sig = _file_sig(bin_path)
    if sig is None or not os.access(bin_path, os.X_OK):
        return "не установлен" if key in ("singbox", "mihomo") else ""
    with _VER_LOCK:
        cached = _VER_CACHE.get(key)
        if cached and cached["sig"] == sig:
            return cached["val"]
    val = "установлен" if key in ("singbox", "mihomo") else ""
    try:
        proc = subprocess.run(cmd_args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=3)
        out = proc.stdout.decode("utf-8", errors="replace")
        parsed = parser_fn(out)
        if parsed:
            val = parsed
    except Exception:
        pass
    with _VER_LOCK:
        _VER_CACHE[key] = {"sig": sig, "val": val}
    return val


def _parse_sb_ver(out):
    first = out.splitlines()[0] if out else ""
    parts = first.split()
    if len(parts) >= 3:
        return "v" + parts[2].lstrip("v")
    return ""


def _parse_mihomo_ver(out):
    m = re.search(r"(v[0-9][0-9.a-zA-Z_-]*)", out or "")
    return m.group(1) if m else ""


def _parse_agh_ver(out):
    m = re.search(r"version\s+(v[0-9.a-zA-Z_.-]*)", out or "")
    return m.group(1) if m else ""


def _parse_lxc_ver(out):
    return (out.splitlines()[0].strip() if out else "")


def _agh_request_json(path, user, password):
    if not user or not password:
        return None
    base_url = "http://127.0.0.1:3000"
    with _AGH_COOKIE_LOCK:
        cookie = _AGH_COOKIE_CACHE["cookie"] if _AGH_COOKIE_CACHE["cred_key"] == (user, password) else ""

    def _do_get(cookie_val):
        req = Request(base_url + path)
        if cookie_val:
            req.add_header("Cookie", cookie_val)
        with urlopen(req, timeout=2.0) as resp:
            return json.loads(resp.read().decode("utf-8", errors="replace"))

    if cookie:
        try:
            return _do_get(cookie)
        except HTTPError as exc:
            if exc.code not in (401, 403):
                return None
        except Exception:
            return None

    # Login once to obtain session cookie (avoids 2x bcrypt cost-10 per poll)
    new_cookie = ""
    try:
        login_req = Request(
            base_url + "/control/login",
            data=json.dumps({"name": user, "password": password}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(login_req, timeout=3.0) as resp:
            hdrs = resp.headers.get_all("Set-Cookie") or []
            for h in hdrs:
                part = h.split(";", 1)[0].strip()
                if part.startswith("agh_session="):
                    new_cookie = part
                    break
    except Exception:
        new_cookie = ""

    if new_cookie:
        with _AGH_COOKIE_LOCK:
            _AGH_COOKIE_CACHE["cred_key"] = (user, password)
            _AGH_COOKIE_CACHE["cookie"] = new_cookie
        try:
            return _do_get(new_cookie)
        except Exception:
            return None

    # Fallback to BasicAuth if session endpoint unavailable
    try:
        tok = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
        req = Request(base_url + path, headers={"Authorization": f"Basic {tok}"})
        with urlopen(req, timeout=2.0) as resp:
            return json.loads(resp.read().decode("utf-8", errors="replace"))
    except Exception:
        return None


def _run_du_single(path):
    try:
        proc = subprocess.run(
            ["timeout", "2", "du", "-sh", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        out = proc.stdout.decode("utf-8", errors="replace").strip()
        if out:
            return out.split()[0]
    except Exception:
        pass
    return ""


def _refresh_du_cache_worker(paths):
    results = {}
    try:
        if paths:
            with ThreadPoolExecutor(max_workers=min(4, len(paths))) as pool:
                fut_map = {pool.submit(_run_du_single, p): p for p in paths}
                for fut, p in fut_map.items():
                    try:
                        val = fut.result(timeout=3.5)
                        if val:
                            results[p] = val
                    except Exception:
                        pass
    finally:
        with _DU_LOCK:
            for k, v in results.items():
                _DU_CACHE["data"][k] = v
            _DU_CACHE["ts"] = time.monotonic()
            _DU_CACHE["refreshing"] = False
            _DU_EVENT.set()


def _get_du_sizes(paths):
    existing = [p for p in paths if os.path.isdir(p)]
    now = time.monotonic()
    need_wait = False
    with _DU_LOCK:
        is_stale = (now - _DU_CACHE["ts"]) > DU_CACHE_TTL or any(p not in _DU_CACHE["data"] for p in existing)
        if is_stale and not _DU_CACHE["refreshing"] and existing:
            _DU_CACHE["refreshing"] = True
            need_wait = (_DU_CACHE["ts"] == 0.0)
            _DU_EVENT.clear()
            t = threading.Thread(target=_refresh_du_cache_worker, args=(existing,), daemon=True)
            t.start()
        snapshot = dict(_DU_CACHE["data"])

    if need_wait:
        _DU_EVENT.wait(timeout=0.22)
        with _DU_LOCK:
            snapshot = dict(_DU_CACHE["data"])

    return snapshot


def _read_mounts():
    mounts = []
    for line in _read_text("/proc/mounts").splitlines():
        parts = line.split()
        if len(parts) >= 3:
            src = parts[0].replace("\\040", " ")
            mp = parts[1].replace("\\040", " ")
            fstype = parts[2]
            mounts.append((src, mp, fstype))
    return mounts


def _find_mount_info(target_path, mounts):
    real = os.path.realpath(target_path) if os.path.exists(target_path) else target_path
    cur = real
    while cur != "/" and not os.path.ismount(cur):
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    best_src, best_fs = "", ""
    for src, mp, fstype in mounts:
        if mp == cur and src != "rootfs":
            best_src, best_fs = src, fstype
    if not best_src:
        for src, mp, fstype in mounts:
            if mp == cur:
                best_src, best_fs = src, fstype
    return best_src, best_fs


def _statvfs_info(path):
    target = path if os.path.isdir(path) else "/"
    try:
        st = os.statvfs(target)
        bsize = st.f_frsize or st.f_bsize or 4096
        total_bytes = st.f_blocks * bsize
        used_bytes = (st.f_blocks - st.f_bfree) * bsize
        avail_nonroot = st.f_bavail * bsize
        denom = used_bytes + avail_nonroot
        pct = int((used_bytes * 100) / denom) if denom > 0 else 0
        pct = max(0, min(100, pct))
        return pct, _fmt_du_size(used_bytes), _fmt_du_size(total_bytes)
    except OSError:
        return 0, "0", "0"


def _mask_token(tok):
    if not tok:
        return ""
    if len(tok) <= 10:
        return "****"
    return f"{tok[:4]}...{tok[-4:]}"


def _read_git_status():
    git_dir = os.path.join(GATEWAY_DIR, ".git")
    if not os.path.isdir(git_dir):
        return False, "Standalone", "main"
    head_path = os.path.join(git_dir, "HEAD")
    head_sig = _file_sig(head_path)
    if head_sig is None:
        return True, "HEAD", "main"

    branch = "main"
    sha = "HEAD"
    head_txt = _read_text(head_path).strip()
    ref_sig = None
    if head_txt.startswith("ref:"):
        ref_rel = head_txt[4:].strip()
        if ref_rel.startswith("refs/heads/"):
            branch = ref_rel[len("refs/heads/"):] or "main"
        ref_path = os.path.join(git_dir, ref_rel)
        ref_sig = _file_sig(ref_path)
    packed_sig = _file_sig(os.path.join(git_dir, "packed-refs"))
    sig = (head_sig, ref_sig, packed_sig)

    with _GIT_LOCK:
        if _GIT_CACHE["sig"] == sig:
            return _GIT_CACHE["is_repo"], _GIT_CACHE["sha"], _GIT_CACHE["branch"]

    if head_txt.startswith("ref:"):
        ref_rel = head_txt[4:].strip()
        ref_path = os.path.join(git_dir, ref_rel)
        ref_sha = _read_text(ref_path).strip()
        if ref_sha:
            sha = ref_sha[:7]
        else:
            for line in _read_text(os.path.join(git_dir, "packed-refs")).splitlines():
                if not line or line.startswith("#") or line.startswith("^"):
                    continue
                parts = line.split()
                if len(parts) >= 2 and parts[1] == ref_rel:
                    sha = parts[0][:7]
                    break
    elif len(head_txt) >= 7:
        sha = head_txt[:7]

    with _GIT_LOCK:
        _GIT_CACHE["sig"] = sig
        _GIT_CACHE["is_repo"] = True
        _GIT_CACHE["sha"] = sha
        _GIT_CACHE["branch"] = branch
    return True, sha, branch


def _read_ssl_cert_info(le_active):
    if not le_active:
        return "", "", 0
    sig = _file_sig(SSL_FULLCHAIN_FILE)
    if sig is None or sig[1] <= 0:
        return "", "", 0
    with _SSL_LOCK:
        if _SSL_CACHE["sig"] == sig:
            return _SSL_CACHE["issuer"], _SSL_CACHE["expiry"], _SSL_CACHE["days_left"]
    issuer = ""
    expiry = ""
    days_left = 0
    try:
        proc = subprocess.run(
            ["openssl", "x509", "-in", SSL_FULLCHAIN_FILE, "-noout", "-issuer", "-enddate"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        for line in proc.stdout.decode("utf-8", errors="replace").splitlines():
            if line.startswith("issuer="):
                m = re.search(r"CN\s*=\s*([^,/\r\n]+)", line)
                issuer = m.group(1).strip() if m else line.split("=", 1)[1].strip()
            elif line.startswith("notAfter="):
                expiry = line.split("=", 1)[1].strip()
                clean_dt = re.sub(r"\s+", " ", expiry)
                try:
                    dt = datetime.strptime(clean_dt, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
                    delta = int((dt.timestamp() - time.time()) // 86400)
                    if delta > 0:
                        days_left = delta
                except Exception:
                    pass
    except Exception:
        pass
    with _SSL_LOCK:
        _SSL_CACHE["sig"] = sig
        _SSL_CACHE["issuer"] = issuer
        _SSL_CACHE["expiry"] = expiry
        _SSL_CACHE["days_left"] = days_left
    return issuer, expiry, days_left


def _query_lxc_info(ct_name):
    res = {"state": "STOPPED", "pid": "", "ipv4": "", "memory": ""}
    try:
        proc = subprocess.run(
            ["lxc-info", "-n", ct_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
        txt = proc.stdout.decode("utf-8", errors="replace")
        if re.search(r"State:.*RUNNING", txt):
            res["state"] = "RUNNING"
            ips = []
            for line in txt.splitlines():
                if line.startswith("PID:"):
                    parts = line.split()
                    if len(parts) >= 2:
                        res["pid"] = parts[1]
                elif line.startswith("IP:"):
                    parts = line.split()
                    if len(parts) >= 2 and _IPV4_RE.match(parts[1]):
                        ips.append(parts[1])
                elif line.startswith("Memory use:"):
                    parts = line.split()
                    if len(parts) >= 4:
                        res["memory"] = f"{parts[2]} {parts[3]}"
                    elif len(parts) == 3:
                        res["memory"] = parts[2]
            res["ipv4"] = ", ".join(ips)
    except Exception:
        pass
    return res


def _is_job_running_py(jid):
    base = os.path.join(RUN_GW_DIR, f"gw_job_{jid}")
    if os.path.isfile(base + ".rc"):
        return False
    pid_txt = _read_text(base + ".pid").strip()
    pid_digits = "".join(ch for ch in pid_txt if ch.isdigit())
    if pid_digits and os.path.isdir(f"/proc/{pid_digits}"):
        return True
    if os.path.isfile(base + ".starting"):
        return True
    return False


def _collect_status_fast():
    gw_env, hl_env, agh_user, admin_pass = _load_env_cached()
    lan_if, lan_ip, route_gw, _ = _get_network_snapshot()
    gw_ip = gw_env.get("GW_IP") or route_gw or "192.168.1.5"

    # OS & System metrics
    alp_ver = _read_text("/etc/alpine-release").strip()
    os_name = f"Alpine Linux v{alp_ver}" if alp_ver else "Alpine Linux"
    model = ""
    for mp in ("/tmp/sysinfo/model", "/sys/devices/virtual/dmi/id/product_name", "/proc/device-tree/model"):
        raw_m = _read_text(mp).replace("\r", "").replace("\n", "").replace("\x00", "").strip()
        if raw_m:
            model = raw_m
            break
    if not model:
        model = socket.gethostname().split(".")[0] or os_name
    kernel_ver = os.uname().release

    uptime_sec = 0
    up_txt = _read_text("/proc/uptime").strip()
    if up_txt:
        try:
            uptime_sec = int(float(up_txt.split()[0]))
        except ValueError:
            uptime_sec = 0
    load_parts = _read_text("/proc/loadavg").split()
    load_avg = " ".join(load_parts[:3])

    mem_vals = {}
    for line in _read_text("/proc/meminfo").splitlines():
        if ":" in line:
            k, rest = line.split(":", 1)
            toks = rest.split()
            if toks and toks[0].isdigit():
                mem_vals[k] = int(toks[0])
    mem_total_kb = mem_vals.get("MemTotal", 0)
    mem_avail_kb = mem_vals.get("MemAvailable", 0)
    if mem_avail_kb <= 0:
        mem_avail_kb = mem_vals.get("MemFree", 0) + mem_vals.get("Buffers", 0) + mem_vals.get("Cached", 0)
    mem_used_kb = max(0, mem_total_kb - mem_avail_kb)
    ram_total_mb = mem_total_kb // 1024
    ram_used_mb = mem_used_kb // 1024
    ram_pct = int((mem_used_kb * 100) / mem_total_kb) if mem_total_kb > 0 else 0

    disk_pct, disk_used, disk_total = _statvfs_info("/")
    ct_used_txt = _read_text("/proc/sys/net/netfilter/nf_conntrack_count").strip()
    ct_used = int(ct_used_txt) if ct_used_txt.isdigit() else 0
    ct_max_txt = _read_text("/proc/sys/net/netfilter/nf_conntrack_max").strip()
    if ct_max_txt.isdigit():
        ct_max = int(ct_max_txt)
    elif ram_total_mb <= 300:
        ct_max = 16384
    elif ram_total_mb <= 600:
        ct_max = 32768
    elif ram_total_mb <= 1200:
        ct_max = 65536
    else:
        ct_max = 131072

    # Processes
    pids = _find_proc_pids()

    # Core & UI
    core_raw = (gw_env.get("CORE_ENGINE") or "singbox").lower()
    core_engine = "mihomo" if core_raw in ("mihomo", "clash", "meta") else "singbox"
    core_name = "Mihomo (Clash Meta)" if core_engine == "mihomo" else "Sing-Box Extended"
    core_proc_key = "mihomo" if core_engine == "mihomo" else "sing-box"
    core_pid = pids.get(core_proc_key) or ""
    core_running = bool(core_pid)
    core_rss = _read_proc_rss_mb(core_pid)
    if core_engine == "mihomo":
        core_ver = _get_cached_version("mihomo", "/usr/bin/mihomo", ["/usr/bin/mihomo", "-v"], _parse_mihomo_ver)
    else:
        core_ver = _get_cached_version("singbox", "/usr/bin/sing-box", ["/usr/bin/sing-box", "version"], _parse_sb_ver)
    core_memlimit = _read_proc_env_var(core_pid, "GOMEMLIMIT") if core_pid else ""
    if not core_memlimit:
        init_txt = _read_text(f"/etc/init.d/{core_proc_key}")
        m_lim = re.search(r"GOMEMLIMIT=[\"']?([A-Za-z0-9]+)[\"']?", init_txt)
        if m_lim:
            core_memlimit = m_lim.group(1)
        elif ram_total_mb <= 300:
            core_memlimit = "60MiB"
        elif ram_total_mb <= 600:
            core_memlimit = "110MiB"
        elif ram_total_mb <= 1200:
            core_memlimit = "200MiB"
        elif ram_total_mb <= 2500:
            core_memlimit = "400MiB"
        else:
            core_memlimit = "600MiB"

    tun_if = "gateway-tun"
    tun_up = os.path.exists(f"/sys/class/net/{tun_if}")

    ui_raw = gw_env.get("WEB_UI") or _read_text(UI_TYPE_FILE).strip() or "zashboard"
    ui_engine = "metacubexd" if ui_raw.lower() in ("metacubexd", "metacube", "xd") else "zashboard"
    ui_name = "MetaCubeXD" if ui_engine == "metacubexd" else "Zashboard"
    ui_ver = _read_text(UI_VER_FILE).strip()

    # Firewall Kill-Switch
    killswitch = "#KILLSWITCH_ACTIVE" in _read_text(ALPINE_NFT_CONF)

    # AdGuard Home
    agh_pid = pids.get("AdGuardHome") or ""
    agh_running = bool(agh_pid)
    agh_rss = _read_proc_rss_mb(agh_pid)
    agh_ver = _get_cached_version("agh", "/usr/bin/AdGuardHome", ["/usr/bin/AdGuardHome", "--version"], _parse_agh_ver)

    dhcp_enabled = False
    in_dhcp = False
    for line in _read_text(AGH_CONF).splitlines():
        if line.startswith("dhcp:"):
            in_dhcp = True
            continue
        if in_dhcp:
            if line and line[0].isalnum():
                break
            if re.match(r"^\s*enabled:\s*true\b", line):
                dhcp_enabled = True
                break

    agh_status = {}
    agh_dhcp = {"enabled": False, "leases": []}
    if agh_running and agh_user and admin_pass:
        st_j = _agh_request_json("/control/status", agh_user, admin_pass)
        if isinstance(st_j, dict):
            agh_status = st_j
        dh_j = _agh_request_json("/control/dhcp/status", agh_user, admin_pass)
        if isinstance(dh_j, dict):
            agh_dhcp = dh_j

    # Cron
    cron_txt = _read_text(CRON_FILE)
    watchdog_en = "/usr/bin/gateway watchdog" in cron_txt
    autoupdate_en = "/usr/bin/gateway autoupdate" in cron_txt

    # Telegram
    tg_tok = gw_env.get("TG_BOT_TOKEN", "")
    tg_cid = gw_env.get("TG_CHAT_ID", "")
    tg_cfg = bool(tg_tok and tg_cid)
    tg_masked = _mask_token(tg_tok)

    # Backup
    bak_exists = os.path.isfile(BACKUP_ARCHIVE)
    bak_size = ""
    bak_mtime = ""
    if bak_exists:
        try:
            bst = os.stat(BACKUP_ARCHIVE)
            bak_size = _fmt_du_size(bst.st_size)
            bak_mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(bst.st_mtime))
        except OSError:
            pass

    # Git
    git_is_repo, git_sha, git_branch = _read_git_status()
    upd_status = ""
    upd_behind = 0
    upd_cache_path = os.path.join(RUN_GW_DIR, "update_check.cache")
    upd_txt = _read_text(upd_cache_path).strip()
    if upd_txt:
        parts = upd_txt.split("|")
        upd_status = parts[0]
        if len(parts) >= 2 and parts[1].isdigit():
            upd_behind = int(parts[1])

    # Homelab state & SSL
    ssl_type = hl_env.get("SSL_TYPE") or "local"
    ssl_domain = hl_env.get("SSL_DOMAIN") or ""
    duck_tok = hl_env.get("DUCKDNS_TOKEN") or ""
    le_active = (
        ssl_type == "letsencrypt"
        and bool(ssl_domain)
        and os.path.isfile(SSL_FULLCHAIN_FILE)
        and os.path.getsize(SSL_FULLCHAIN_FILE) > 0
        and os.path.isfile(SSL_KEY_FILE)
        and os.path.getsize(SSL_KEY_FILE) > 0
    )

    hl_rows = []
    caddy_enabled = False
    for raw_line in _read_text(HOMELAB_STATE).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        cols = line.split("|")
        if len(cols) < 7:
            continue
        hl_rows.append(cols[:7])
        if cols[0] == "caddy" and cols[1] == "yes":
            caddy_enabled = True

    issuer, expiry, days_left = _read_ssl_cert_info(le_active)
    ssl_obj = {
        "type": ssl_type,
        "domain": ssl_domain,
        "le_active": le_active,
        "caddy_enabled": caddy_enabled,
        "expiry": expiry,
        "issuer": issuer,
        "days_left": days_left,
        "duckdns_token_set": bool(duck_tok),
        "duckdns_token_masked": _mask_token(duck_tok),
    }

    homelab_list = []
    for m_id, m_en, m_svc, m_port, m_dom, _m_usr, m_title in hl_rows:
        m_run = False
        if m_svc:
            started_lnk = f"/run/openrc/started/{m_svc}"
            crashed_pth = f"/run/openrc/crashed/{m_svc}"
            if os.path.islink(started_lnk) and not os.path.exists(crashed_pth):
                m_run = True
        if not m_run and m_id == "samba" and pids.get("smbd"):
            m_run = True
        elif not m_run and m_id == "caddy" and pids.get("caddy"):
            m_run = True

        url = ""
        smb_share = ""
        if m_id == "caddy":
            if m_en == "yes":
                url = f"https://ca.{ssl_domain}" if (le_active and ssl_domain) else "http://ca.lan"
        elif m_id == "samba":
            if m_en == "yes":
                smb_share = f"\\\\{lan_ip}\\storage"
        elif m_en == "yes":
            sub = m_dom.split(".", 1)[0]
            if caddy_enabled:
                url = f"https://{sub}.{ssl_domain}" if (le_active and ssl_domain) else f"https://{m_dom}"
            else:
                url = f"http://{lan_ip}:{m_port}"

        homelab_list.append({
            "id": m_id,
            "enabled": (m_en == "yes"),
            "service": m_svc,
            "running": m_run,
            "port": m_port,
            "domain": m_dom,
            "url": url,
            "smb_share": smb_share,
            "title": m_title,
        })

    # Links
    if caddy_enabled:
        if le_active and ssl_domain:
            links_obj = {
                "gateway_url": f"https://gateway.{ssl_domain}",
                "ui_url": f"https://zashboard.{ssl_domain}/ui/",
                "agh_url": f"https://adguard.{ssl_domain}",
                "ca_url": f"https://ca.{ssl_domain}",
            }
        else:
            links_obj = {
                "gateway_url": "https://gateway.lan",
                "ui_url": "https://zashboard.lan/ui/",
                "agh_url": "https://adguard.lan",
                "ca_url": "http://ca.lan",
            }
    else:
        links_obj = {
            "gateway_url": f"http://{lan_ip}:{BIND_PORT}",
            "ui_url": f"http://{lan_ip}:9090/ui/",
            "agh_url": f"http://{lan_ip}:3000",
            "ca_url": "",
        }

    # Proxies & Rules
    sub_urls = gw_env.get("SUB_URL", "")
    if "http://" not in sub_urls and "https://" not in sub_urls:
        sub_urls = ""
    sub_tokens = [u for u in re.split(r"[\s|,]+", sub_urls) if u.startswith(("http://", "https://"))]
    sub_count = len(sub_tokens)
    allow_ru = (gw_env.get("ALLOW_RU_NODES", "no") == "yes")
    warp_enabled = bool(re.search(r'"type":\s*"(wireguard|masque)"', _read_text(WARP_NODES_FILE)))
    warp_license_set = bool(gw_env.get("WARP_LICENSE"))

    my_nodes = []
    idx = 0
    for raw_line in _read_text(CUSTOM_NODES_FILE).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("proxies:"):
            continue
        idx += 1
        proto = line.split("://", 1)[0] if "://" in line else line
        tag = "(без названия)"
        if "#" in line:
            tag = line.split("#", 1)[1].replace("%20", " ")
        host = re.sub(r"^[a-zA-Z0-9+-]+://([^@]*@)?", "", line)
        host = re.split(r"[/?#]", host, 1)[0]
        my_nodes.append({"index": idx, "proto": proto, "host": host, "tag": tag, "uri": line})

    proxy_domains = [ln.rstrip("\r\n") for ln in _read_text(USER_PROXY_FILE).splitlines() if ln.strip()]
    direct_domains = [ln.rstrip("\r\n") for ln in _read_text(USER_DIRECT_FILE).splitlines() if ln.strip()]

    proxy_groups = []
    if core_running and admin_pass:
        try:
            req = Request("http://127.0.0.1:9090/proxies", headers={"Authorization": f"Bearer {admin_pass}"})
            with urlopen(req, timeout=2.0) as resp:
                px_data = json.loads(resp.read().decode("utf-8", errors="replace"))
            p_map = px_data.get("proxies") or {}
            for gname in GROUP_ORDER:
                entry = p_map.get(gname)
                if not isinstance(entry, dict):
                    continue
                now_val = entry.get("now") or ""
                if now_val and isinstance(p_map.get(now_val), dict) and p_map[now_val].get("now"):
                    now_val = f"{now_val} -> {p_map[now_val]['now']}"
                proxy_groups.append({
                    "name": gname,
                    "type": entry.get("type") or "",
                    "now": now_val,
                    "count": len(entry.get("all") or []),
                })
        except Exception:
            pass

    # LAN Devices
    byp_set = {ln.strip() for ln in _read_text(USER_BYPASS_IPS).splitlines() if ln.strip()}
    vpn_set = {ln.strip() for ln in _read_text(USER_FORCE_PROXY_IPS).splitlines() if ln.strip()}
    dev_map = {}

    for lease in (agh_dhcp.get("leases") or []):
        if not isinstance(lease, dict):
            continue
        ip = str(lease.get("ip") or "").strip()
        if not _IPV4_RE.match(ip) or ip == lan_ip:
            continue
        mac = str(lease.get("mac") or "").lower()
        host = str(lease.get("hostname") or "").strip()
        if host == "*":
            host = ""
        dev_map[ip] = {"mac": mac, "hostname": host}

    arp_lines = _read_text("/proc/net/arp").splitlines()
    for line in arp_lines[1:]:
        cols = line.split()
        if len(cols) < 4:
            continue
        ip, flags, mac = cols[0], cols[2], cols[3].lower()
        if ip != lan_ip and _IPV4_RE.match(ip) and flags != "0x0" and mac != "00:00:00:00:00:00":
            cur = dev_map.setdefault(ip, {"mac": "", "hostname": ""})
            if not cur["mac"]:
                cur["mac"] = mac

    for ip in byp_set | vpn_set:
        if _IPV4_RE.match(ip):
            dev_map.setdefault(ip, {"mac": "", "hostname": ""})

    devices = []
    for ip in sorted(dev_map.keys()):
        info = dev_map[ip]
        hostname = info["hostname"]
        if ip == gw_ip:
            hostname = f"Роутер ({hostname})" if hostname else "Основной роутер"
        mode = "default"
        if ip in byp_set:
            mode = "bypass"
        if ip in vpn_set:
            mode = "force_proxy"
        devices.append({"ip": ip, "mac": info["mac"], "hostname": hostname, "mode": mode})

    # Storage & LXC (collect du targets together to overlap one TTL cache)
    st_root = hl_env.get("STORAGE_ROOT") or "/srv/storage"
    try:
        os.makedirs(st_root, exist_ok=True)
    except OSError:
        pass
    ext_expected = (hl_env.get("EXT_STORAGE_EXPECTED", "no") == "yes")
    ext_luks_uuid = hl_env.get("EXT_STORAGE_LUKS_UUID", "")
    mounts = _read_mounts()
    ext_src, ext_fstype = "", ""
    for src, mp, fstype in mounts:
        if mp == st_root:
            ext_src, ext_fstype = src, fstype
    ext_mounted = bool(ext_src)
    luks_mapped = os.path.exists(f"/dev/mapper/{LUKS_MAPPER_NAME}")
    luks_key_exists = os.path.isfile(LUKS_KEYFILE) and os.path.getsize(LUKS_KEYFILE) > 0
    st_pct, st_used, st_total = _statvfs_info(st_root)
    st_dev, st_fs = _find_mount_info(st_root, mounts)

    if ext_mounted:
        if ext_src.startswith("/dev/mapper/") or "luks" in ext_src or "crypt" in ext_src:
            st_badge = f"● LUKS2 UNLOCKED [{ext_fstype or 'FS'}]"
        else:
            st_badge = f"● Внешний [{os.path.basename(ext_src)}: {ext_fstype or 'FS'}]"
    elif ext_expected:
        if ext_luks_uuid:
            st_badge = "▲ Ждет разблокировки LUKS2 (выполните: gateway unlock)"
        else:
            st_badge = "▲ Внешний диск отключен (выполните: gateway disk)"
    else:
        st_badge = "○ Системный раздел"

    storage_dir_specs = [
        ("Music", f"{st_root}/Music"),
        ("Videos", f"{st_root}/Videos"),
        ("Downloads", f"{st_root}/Downloads"),
        ("Incomplete", f"{st_root}/Downloads/Incomplete"),
        ("Backups", f"{st_root}/Backups"),
        ("LXC", f"{st_root}/lxc"),
        ("Git-Repos", f"{st_root}/Git-Repos"),
        ("Workspace", f"{st_root}/Workspace"),
        ("Shared", f"{st_root}/Shared"),
    ]

    lxc_installed = shutil.which("lxc-create") is not None
    lxc_bridge_up = os.path.exists("/sys/class/net/lxcbr0")
    mach = os.uname().machine
    if mach == "x86_64":
        lxc_arch = "amd64"
    elif mach == "aarch64":
        lxc_arch = "arm64"
    elif mach.startswith("armv7"):
        lxc_arch = "armhf"
    else:
        lxc_arch = mach
    lxc_version = _get_cached_version("lxc", "/usr/bin/lxc-create", ["/usr/bin/lxc-create", "--version"], _parse_lxc_ver) if lxc_installed else ""
    console_ready = (
        shutil.which("ttyd") is not None
        and (os.path.islink("/run/openrc/started/gateway-console") or bool(pids.get("ttyd")))
    )

    ct_entries = []
    if lxc_installed:
        real_lxc_path = os.path.realpath("/var/lib/lxc")
        if os.path.isdir(real_lxc_path):
            try:
                for name in sorted(os.listdir(real_lxc_path)):
                    ct_dir = os.path.join(real_lxc_path, name)
                    ct_conf = os.path.join(ct_dir, "config")
                    if os.path.isdir(ct_dir) and os.path.isfile(ct_conf):
                        ct_entries.append((name, ct_dir, ct_conf))
            except OSError:
                pass

    du_targets = [dp for _, dp in storage_dir_specs if os.path.isdir(dp)]
    du_targets.extend(os.path.join(ct_dir, "rootfs") for _, ct_dir, _ in ct_entries if os.path.isdir(os.path.join(ct_dir, "rootfs")))
    du_map = _get_du_sizes(du_targets)

    storage_dirs = []
    for dname, dpath in storage_dir_specs:
        if os.path.isdir(dpath):
            storage_dirs.append({"name": dname, "path": dpath, "size": du_map.get(dpath) or "..."})

    storage_obj = {
        "root": st_root,
        "ext_expected": ext_expected,
        "ext_mounted": ext_mounted,
        "luks_mapped": luks_mapped,
        "luks_key_exists": luks_key_exists,
        "disk_pct": st_pct,
        "disk_used": st_used,
        "disk_total": st_total,
        "fs_type": st_fs,
        "device": st_dev,
        "badge": st_badge,
        "dirs": storage_dirs,
    }

    ct_info_map = {}
    if ct_entries:
        with ThreadPoolExecutor(max_workers=min(4, len(ct_entries))) as pool:
            futs = {pool.submit(_query_lxc_info, name): name for name, _, _ in ct_entries}
            for fut, name in futs.items():
                try:
                    ct_info_map[name] = fut.result(timeout=2.5)
                except Exception:
                    ct_info_map[name] = {"state": "STOPPED", "pid": "", "ipv4": "", "memory": ""}

    containers = []
    for ct_name, ct_dir, ct_conf in ct_entries:
        conf_txt = _read_text(ct_conf)
        inf = ct_info_map.get(ct_name, {"state": "STOPPED", "pid": "", "ipv4": "", "memory": ""})
        autostart = bool(re.search(r"^lxc\.start\.auto\s*=\s*1", conf_txt, re.MULTILINE))
        nesting = bool(re.search(r"GW_NESTING_BEGIN|nesting\.conf", conf_txt))
        storage_mount = bool(re.search(r"GW_STORAGE_BEGIN|\smnt/storage\s", conf_txt))
        net_mode = "macvlan" if re.search(r"^lxc\.net\.0\.type\s*=\s*macvlan", conf_txt, re.MULTILINE) else "nat"

        m_sip = re.search(r"^\s*lxc\.net\.0\.ipv4\.address\s*=\s*(.+)$", conf_txt, re.MULTILINE)
        static_ip = m_sip.group(1).strip() if m_sip else ""

        m_mem = re.search(r"^\s*lxc\.cgroup2\.memory\.max\s*=\s*(.+)$", conf_txt, re.MULTILINE)
        mem_limit = m_mem.group(1).strip() if m_mem else ""

        cpu_limit = ""
        m_cpu = re.search(r"^\s*lxc\.cgroup2\.cpu\.max\s*=\s*(.+)$", conf_txt, re.MULTILINE)
        if m_cpu:
            cparts = m_cpu.group(1).split()
            if cparts and cparts[0].isdigit() and int(cparts[0]) > 0:
                quota = int(cparts[1]) if len(cparts) >= 2 and cparts[1].isdigit() and int(cparts[1]) > 0 else 100000
                val = int(cparts[0]) / float(quota)
                cpu_limit = str(int(val)) if val == int(val) else f"{val:.1f}"

        os_pretty = ""
        os_rel_path = os.path.join(ct_dir, "rootfs", "etc", "os-release")
        if os.path.isfile(os_rel_path):
            m_os = re.search(r'^PRETTY_NAME=(.+)$', _read_text(os_rel_path), re.MULTILINE)
            if m_os:
                os_pretty = m_os.group(1).strip().strip("\"'")
        if not os_pretty:
            os_pretty = _read_text(os.path.join(ct_dir, ".gw_os")).strip()

        rootfs_path = os.path.join(ct_dir, "rootfs")
        disk_usage = du_map.get(rootfs_path, "") if os.path.isdir(rootfs_path) else ""

        snaps = []
        snaps_dir = os.path.join(ct_dir, "snaps")
        if os.path.isdir(snaps_dir):
            try:
                for sname in sorted(os.listdir(snaps_dir)):
                    sdir = os.path.join(snaps_dir, sname)
                    if not os.path.isdir(sdir):
                        continue
                    dt = _read_text(os.path.join(sdir, "ts")).strip()
                    if not dt:
                        try:
                            dt = time.strftime("%Y-%m-%d %H:%M", time.localtime(os.stat(sdir).st_mtime))
                        except OSError:
                            dt = ""
                    cmt = _read_text(os.path.join(sdir, "comment")).replace("\r", "").replace("\n", "").replace("\t", "")[:120]
                    snaps.append({"name": sname, "date": dt, "comment": cmt})
            except OSError:
                pass

        containers.append({
            "name": ct_name,
            "state": inf["state"],
            "pid": inf["pid"],
            "ipv4": inf["ipv4"],
            "memory": inf["memory"],
            "mem_limit": mem_limit,
            "cpu_limit": cpu_limit,
            "disk_usage": disk_usage,
            "os_pretty": os_pretty,
            "net_mode": net_mode,
            "static_ip": static_ip,
            "autostart": autostart,
            "nesting": nesting,
            "storage_mount": storage_mount,
            "snapshots": snaps,
        })

    lxc_obj = {
        "installed": lxc_installed,
        "bridge_up": lxc_bridge_up,
        "arch": lxc_arch,
        "lxc_version": lxc_version,
        "console_ready": console_ready,
        "containers": containers,
    }

    active_job_id = ""
    cur_jid = "".join(ch for ch in _read_text(os.path.join(RUN_GW_DIR, "job_current.id")) if ch.isalnum() or ch in ("_", "-"))
    if cur_jid and _is_job_running_py(cur_jid):
        active_job_id = cur_jid

    return {
        "ok": True,
        "system": {
            "os_name": os_name,
            "is_openwrt": False,
            "model": model,
            "kernel": kernel_ver,
            "uptime_sec": uptime_sec,
            "load": load_avg,
            "ram_pct": ram_pct,
            "ram_used_mb": ram_used_mb,
            "ram_total_mb": ram_total_mb,
            "disk_pct": disk_pct,
            "disk_used": disk_used,
            "disk_total": disk_total,
            "conntrack_used": ct_used,
            "conntrack_max": ct_max,
        },
        "core": {
            "engine": core_engine,
            "name": core_name,
            "version": core_ver,
            "running": core_running,
            "pid": core_pid,
            "rss": core_rss,
            "memlimit": core_memlimit,
            "tun_up": tun_up,
            "tun_if": tun_if,
            "ui": ui_engine,
            "ui_name": ui_name,
            "ui_ver": ui_ver,
        },
        "network": {
            "lan_ip": lan_ip,
            "lan_if": lan_if,
            "gw_ip": gw_ip,
            "killswitch": killswitch,
        },
        "adguard": {
            "running": agh_running,
            "pid": agh_pid,
            "rss": agh_rss,
            "version": agh_ver,
            "user": agh_user,
            "protection_enabled": bool(agh_status.get("protection_enabled", False)),
            "dhcp_enabled": dhcp_enabled,
            "dhcp_v4": agh_dhcp.get("v4"),
            "dhcp_leases": agh_dhcp.get("leases") or [],
        },
        "cron": {
            "watchdog": watchdog_en,
            "autoupdate": autoupdate_en,
        },
        "telegram": {
            "configured": tg_cfg,
            "chat_id": tg_cid,
            "token_masked": tg_masked,
        },
        "backup": {
            "exists": bak_exists,
            "size": bak_size,
            "mtime": bak_mtime,
        },
        "git": {
            "is_repo": git_is_repo,
            "sha": git_sha,
            "branch": git_branch,
            "update_status": upd_status,
            "update_behind": upd_behind,
        },
        "proxies": {
            "sub_urls": sub_urls,
            "sub_count": sub_count,
            "allow_ru": allow_ru,
            "warp_enabled": warp_enabled,
            "warp_license_set": warp_license_set,
            "my_nodes": my_nodes,
            "proxy_domains": proxy_domains,
            "direct_domains": direct_domains,
            "groups": proxy_groups,
        },
        "devices": devices,
        "ssl": ssl_obj,
        "homelab": homelab_list,
        "storage": storage_obj,
        "lxc": lxc_obj,
        "links": links_obj,
        "active_job_id": active_job_id,
    }


class GatewayWebHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    rbufsize = 0  # Unbuffered rfile prevents read-ahead swallowing WebSocket frames on upgrade

    def setup(self):
        self.request.settimeout(HTTP_SOCKET_TIMEOUT)
        super().setup()

    def log_message(self, format, *args):
        try:
            msg = format % args
        except Exception:
            msg = f"{format} {args!r}"
        msg = _ARG_REDACT_RE.sub(r"\1[REDACTED]", msg)
        sys.stderr.write(f"[webui] {self.address_string()} - {msg}\n")
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
            except (BrokenPipeError, ConnectionResetError, OSError):
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
                if not line or not line.endswith(b"\n"):
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
                crlf = self._read_exact(2)
                if crlf != b"\r\n":
                    raise _BodyReadError(400, "Некорректный разделитель chunk")
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

    def _deny(self, code, message, extra_headers=None):
        if (self.path or "").startswith("/api/"):
            self._send_json(code, {"ok": False, "error": message})
        else:
            self._send_bytes(code, "text/plain; charset=utf-8", message.encode("utf-8"), extra_headers)

    def _check_host_and_origin(self):
        req_host = _extract_host_only(self.headers.get("Host", ""))
        if not req_host or not _is_allowed_host(req_host):
            self._deny(403, "Forbidden: untrusted Host header")
            return False

        origin = self.headers.get("Origin")
        if origin is not None:
            origin_s = origin.strip()
            if not origin_s or origin_s.lower() == "null":
                self._deny(403, "Forbidden: invalid Origin header")
                return False
            try:
                parsed_o = urlparse(origin_s)
            except Exception:
                self._deny(403, "Forbidden: invalid Origin header")
                return False
            origin_host = (parsed_o.hostname or "").lower()
            if parsed_o.scheme not in ("http", "https") or not origin_host:
                self._deny(403, "Forbidden: invalid Origin header")
                return False
            if not _is_allowed_host(origin_host) or origin_host != req_host:
                self._deny(403, "Forbidden: cross-origin request rejected")
                return False
        return True

    def _check_auth(self):
        if AUTH_MODE == "caddy":
            expected_tok = _get_proxy_token()
            supplied_tok = self.headers.get("X-Gateway-Proxy-Token", "")
            if expected_tok and supplied_tok and hmac.compare_digest(supplied_tok, expected_tok):
                return True
            self._deny(403, "Forbidden: invalid proxy authentication token", {"Cache-Control": "no-store"})
            return False

        if AUTH_MODE != "basic":
            self._deny(403, "Forbidden: unsupported authentication mode", {"Cache-Control": "no-store"})
            return False

        client_ip = self.client_address[0] if self.client_address else "unknown"
        now = time.monotonic()
        with _AUTH_FAIL_LOCK:
            if len(_AUTH_FAILS) > 256:
                stale = [k for k, v in _AUTH_FAILS.items() if now - v["last"] > 300.0]
                for k in stale:
                    del _AUTH_FAILS[k]
            rec = _AUTH_FAILS.get(client_ip)
            if rec and rec["blocked_until"] > now:
                wait_s = max(1, int(rec["blocked_until"] - now + 0.99))
                self._deny(
                    429,
                    "Too many authentication attempts",
                    {"Retry-After": str(wait_s), "Cache-Control": "no-store"},
                )
                return False

        expected_user, expected_pass = _load_credentials()
        if not expected_pass:
            self._send_bytes(503, "text/plain; charset=utf-8", b"Gateway password is not initialized")
            return False

        hdr = self.headers.get("Authorization", "")
        if hdr.startswith("Basic "):
            try:
                raw = base64.b64decode(hdr[6:].strip()).decode("utf-8", errors="strict")
                u, p = raw.split(":", 1)
                user_ok = hmac.compare_digest(u, expected_user)
                pass_ok = hmac.compare_digest(p, expected_pass)
                if user_ok and pass_ok:
                    with _AUTH_FAIL_LOCK:
                        _AUTH_FAILS.pop(client_ip, None)
                    return True
            except Exception:
                pass

            # Only count towards brute-force backoff when credentials were actively presented and wrong
            with _AUTH_FAIL_LOCK:
                rec = _AUTH_FAILS.get(client_ip)
                if not rec or (now - rec["last"]) > 300.0:
                    rec = {"count": 0, "last": now, "blocked_until": 0.0}
                rec["count"] += 1
                rec["last"] = now
                if rec["count"] >= 5:
                    delay = min(60.0, float(2 ** min(rec["count"] - 5, 6)))
                    rec["blocked_until"] = now + delay
                _AUTH_FAILS[client_ip] = rec

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
            upstream = socket.create_connection(("127.0.0.1", CONSOLE_PORT), timeout=8.0)
        except OSError:
            self._send_bytes(
                503,
                "text/plain; charset=utf-8",
                "Веб-консоль ttyd недоступна".encode("utf-8"),
            )
            return

        self.close_connection = True
        try:
            try:
                self.connection.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
                upstream.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            except OSError:
                pass

            req_lines = [f"{self.command} {self.path} HTTP/1.1"]
            is_ws = False
            for k, v in self.headers.items():
                kl = k.lower()
                if kl in ("authorization", "x-gateway-proxy-token", "proxy-connection", "keep-alive", "connection"):
                    continue
                if kl == "upgrade" and "websocket" in v.lower():
                    is_ws = True
                req_lines.append(f"{k}: {v}")
            req_lines.append("Connection: Upgrade" if is_ws else "Connection: close")
            raw_req = ("\r\n".join(req_lines) + "\r\n\r\n").encode("utf-8")
            upstream.sendall(raw_req)

            if is_ws:
                self._relay_sockets(self.connection, upstream)
            else:
                upstream.settimeout(15.0)
                self.connection.settimeout(15.0)
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
        buffers = {sock_a: bytearray(), sock_b: bytearray()}
        eof = {sock_a: False, sock_b: False}
        write_wait_since = {sock_a: None, sock_b: None}
        last_activity = time.monotonic()

        while True:
            if (eof[sock_a] and not buffers[sock_b]) or (eof[sock_b] and not buffers[sock_a]):
                break

            rlist = []
            wlist = []
            now = time.monotonic()
            for s, peer in ((sock_a, sock_b), (sock_b, sock_a)):
                if not eof[s] and len(buffers[peer]) < WS_MAX_PENDING_BYTES:
                    rlist.append(s)
                if buffers[s]:
                    wlist.append(s)
                    if write_wait_since[s] is None:
                        write_wait_since[s] = now
                    elif (now - write_wait_since[s]) > WS_WRITE_STALL_TIMEOUT:
                        return
                else:
                    write_wait_since[s] = None

            if not rlist and not wlist:
                break

            try:
                readable, writable, exceptional = select.select(rlist, wlist, [sock_a, sock_b], 10.0)
            except (ValueError, OSError):
                break

            if exceptional:
                break

            now = time.monotonic()
            if not readable and not writable:
                if (now - last_activity) > WS_IDLE_TIMEOUT:
                    break
                continue

            for s in readable:
                peer = sock_b if s is sock_a else sock_a
                try:
                    data = s.recv(65536)
                except BlockingIOError:
                    continue
                except OSError:
                    eof[s] = True
                    continue
                if not data:
                    eof[s] = True
                else:
                    buffers[peer].extend(data)
                    last_activity = now

            for s in writable:
                buf = buffers[s]
                if not buf:
                    continue
                try:
                    sent = s.send(buf)
                except BlockingIOError:
                    continue
                except (BrokenPipeError, ConnectionResetError, OSError):
                    return
                if sent > 0:
                    del buf[:sent]
                    last_activity = now
                    write_wait_since[s] = now if buf else None

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

        self._send_bytes(200, ctype, data, {"Cache-Control": "no-cache"})

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        if not self._check_host_and_origin():
            return
        if not self._check_auth():
            return
        parsed = urlparse(self.path)
        if parsed.path == "/console":
            loc = "/console/" + (f"?{parsed.query}" if parsed.query else "")
            self._send_bytes(302, "text/plain; charset=utf-8", b"Redirecting", {"Location": loc, "Cache-Control": "no-store"})
            return
        if parsed.path.startswith("/console/"):
            self._proxy_console()
            return
        if parsed.path.startswith("/api/"):
            self._send_json(405, {"ok": False, "error": "Используйте POST запрос"})
            return
        self._serve_static(parsed.path)

    def do_POST(self):
        if not self._check_host_and_origin():
            return
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

        # Fast native /api/status collector on Alpine Linux (< 250ms vs ~7s shell fork storm)
        if method == "status" and not os.path.isfile("/etc/openwrt_release"):
            try:
                status_payload = _collect_status_fast()
                self._send_json(200, status_payload)
                return
            except Exception as exc:
                sys.stderr.write(f"[webui] fast /api/status fallback: {exc}\n")
                sys.stderr.flush()

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
        except Exception as exc:
            sys.stderr.write(f"[webui] api.sh exec error ({method}): {exc}\n")
            sys.stderr.flush()
            self._send_json(500, {"ok": False, "error": "Ошибка запуска API бэкенда"})
            return

        raw_out = proc.stdout.decode("utf-8", errors="replace").strip()
        last_line = raw_out.splitlines()[-1].strip() if raw_out else ""
        try:
            parsed_out = json.loads(last_line)
        except Exception:
            err_tail = proc.stderr.decode("utf-8", errors="replace").strip()[-500:]
            sys.stderr.write(f"[webui] invalid api.sh output ({method}, rc={proc.returncode}): {err_tail}\n")
            sys.stderr.flush()
            self._send_json(500, {"ok": False, "error": "Некорректный ответ API бэкенда"})
            return

        if method in ("set_network", "set_password"):
            _invalidate_net_cache()
        if method == "set_password":
            with _AGH_COOKIE_LOCK:
                _AGH_COOKIE_CACHE["cred_key"] = None
                _AGH_COOKIE_CACHE["cookie"] = ""

        self._send_json(200, parsed_out)


class ReusableThreadingHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True
    request_queue_size = 64
    block_on_close = False


def main():
    _ensure_runtime_dirs()
    if AUTH_MODE == "caddy":
        _ensure_proxy_token()

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
