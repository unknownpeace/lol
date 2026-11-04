install_module_ytdlp() {
    echo "${C_CYN}[*] Установка модуля yt-dlp + Веб-панель загрузки (Audio -> Music / Video -> Videos)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add yt-dlp ffmpeg python3; then
        echo "${C_RED}[X] Не удалось установить пакеты yt-dlp / ffmpeg / python3!${C_RES}"
        return 1
    fi
    apk add py3-yt-dlp py3-mutagen >/dev/null 2>&1 || true

    init_homelab_storage
    if ! id ytdlp >/dev/null 2>&1; then
        adduser -D -H -s /sbin/nologin -G "$MEDIA_GROUP" ytdlp 2>/dev/null || \
        adduser -D -H -s /sbin/nologin ytdlp 2>/dev/null || true
    fi
    addgroup ytdlp "$MEDIA_GROUP" 2>/dev/null || true

    mkdir -p "$HOMELAB_LIB_DIR"
    chmod 755 "$HOMELAB_LIB_DIR" 2>/dev/null || true
    cat << 'PY_EOF' > "$YTDLP_WEB_SCRIPT"
#!/usr/bin/env python3
import grp
import json
import os
import shutil
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

if os.path.isfile("/usr/bin/yt-dlp"):
    sys.path.insert(0, "/usr/bin/yt-dlp")
import yt_dlp

MUSIC_DIR = os.environ.get("STORAGE_MUSIC", "/srv/storage/Music")
VIDEO_DIR = os.environ.get("STORAGE_VIDEOS", "/srv/storage/Videos")
MOVIES_DIR = os.path.join(VIDEO_DIR, "Movies")
SERIES_DIR = os.path.join(VIDEO_DIR, "Series")
DL_MUSIC_DIR = os.environ.get("STORAGE_DL_MUSIC", "/srv/storage/Downloads/Music")
DL_VIDEO_DIR = os.environ.get("STORAGE_DL_VIDEOS", "/srv/storage/Downloads/Videos")
TEMP_DIR = os.environ.get("STORAGE_INC_YTDLP", "/srv/storage/Downloads/Incomplete/ytdlp")
LISTEN_PORT = int(os.environ.get("PORT_YTDLP", "8081"))
MEDIA_GROUP = os.environ.get("MEDIA_GROUP", "media")

os.umask(0o002)
for d in (MUSIC_DIR, VIDEO_DIR, MOVIES_DIR, SERIES_DIR, DL_MUSIC_DIR, DL_VIDEO_DIR, TEMP_DIR):
    os.makedirs(d, exist_ok=True)

def apply_media_perms(path):
    try:
        gid = grp.getgrnam(MEDIA_GROUP).gr_gid
    except KeyError:
        gid = -1
    if os.path.isdir(path):
        for root, dirs, files in os.walk(path):
            if gid != -1:
                try:
                    os.chown(root, -1, gid)
                except OSError:
                    pass
            try:
                os.chmod(root, 0o2775)
            except OSError:
                pass
            for f in files:
                fp = os.path.join(root, f)
                if gid != -1:
                    try:
                        os.chown(fp, -1, gid)
                    except OSError:
                        pass
                try:
                    os.chmod(fp, 0o664)
                except OSError:
                    pass
    elif os.path.isfile(path):
        if gid != -1:
            try:
                os.chown(path, -1, gid)
            except OSError:
                pass
        try:
            os.chmod(path, 0o664)
        except OSError:
            pass

JOBS = {}
JOBS_LOCK = threading.Lock()
TASK_QUEUE = []
QUEUE_COND = threading.Condition()

HTML_PAGE = """<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Homelab Media Downloader (yt-dlp)</title>
<style>
  body { font-family: system-ui, sans-serif; background: #0f172a; color: #f1f5f9; max-width: 920px; margin: 1.5rem auto; padding: 0 1rem; }
  .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 1.25rem; margin-bottom: 1.25rem; }
  h1 { color: #38bdf8; margin-top: 0; font-size: 1.5rem; }
  input, select, button { padding: 0.7rem 0.9rem; border-radius: 8px; border: 1px solid #475569; background: #0f172a; color: #fff; font-size: 0.95rem; }
  input[type=text] { width: 100%; box-sizing: border-box; margin-bottom: 0.8rem; }
  .row { display: flex; gap: 0.8rem; flex-wrap: wrap; align-items: center; }
  button { background: #0284c7; border: none; font-weight: 600; cursor: pointer; }
  button:hover { background: #0369a1; }
  button.sec { background: #475569; }
  table { width: 100%; border-collapse: collapse; margin-top: 0.8rem; font-size: 0.9rem; }
  th, td { text-align: left; padding: 0.6rem; border-bottom: 1px solid #334155; }
  .bar { background: #0f172a; border-radius: 6px; height: 10px; width: 120px; overflow: hidden; }
  .fill { background: #22c55e; height: 100%; }
  .st-done { color: #4ade80; font-weight: 600; }
  .st-err { color: #f87171; font-weight: 600; }
  .st-run { color: #38bdf8; font-weight: 600; }
</style>
</head>
<body>
<div class="card">
  <h1>⬇️ Загрузчик медиатеки yt-dlp (Jellyfin &amp; Navidrome)</h1>
  <form onsubmit="addTask(event)">
    <input type="text" id="url" placeholder="Вставьте ссылку на видео, трек или плейлист (YouTube, SoundCloud, VK, Rutube, Twitch...)" required>
    <div class="row">
      <select id="mode">
        <option value="video_best">🎬 Видео: Максимальное качество (MP4/MKV &rarr; Jellyfin Videos)</option>
        <option value="video_1080">🎬 Видео: До 1080p FullHD (MP4 &rarr; Jellyfin Videos)</option>
        <option value="video_720">🎬 Видео: До 720p HD (MP4 &rarr; Jellyfin Videos)</option>
        <option value="audio_mp3">🎵 Музыка: MP3 320 kbps + Обложка &amp; Теги (&rarr; Music)</option>
        <option value="audio_m4a">🎵 Музыка: M4A / AAC + Обложка &amp; Теги (&rarr; Music)</option>
        <option value="audio_flac">🎵 Музыка: FLAC Lossless + Обложка &amp; Теги (&rarr; Music)</option>
      </select>
      <select id="playlist">
        <option value="no">Один ролик / трек</option>
        <option value="yes">Весь плейлист целиком</option>
      </select>
      <button type="submit">Добавить в очередь</button>
      <button type="button" class="sec" onclick="clearFinished()">Очистить завершенные</button>
    </div>
  </form>
</div>
<div class="card">
  <h2 style="margin-top:0;font-size:1.15rem;color:#94a3b8;">Очередь и статус загрузок</h2>
  <table>
    <thead><tr><th>Название / URL</th><th>Тип</th><th>Статус</th><th>Прогресс</th><th>Скорость</th></tr></thead>
    <tbody id="jobs"></tbody>
  </table>
</div>
<script>
async function addTask(e) {
  e.preventDefault();
  const url = document.getElementById('url').value.trim();
  const mode = document.getElementById('mode').value;
  const playlist = document.getElementById('playlist').value;
  if (!url) return;
  await fetch('/api/add', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({url, mode, playlist})
  });
  document.getElementById('url').value = '';
  loadJobs();
}
async function clearFinished() {
  await fetch('/api/clear', {method: 'POST'});
  loadJobs();
}
async function loadJobs() {
  try {
    const r = await fetch('/api/jobs');
    const data = await r.json();
    const tbody = document.getElementById('jobs');
    tbody.innerHTML = data.map(j => {
      const cls = j.status.startsWith('Готово') ? 'st-done' : (j.status.startsWith('Ошибка') ? 'st-err' : 'st-run');
      return `<tr>
        <td style="max-width:320px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="${j.title}">${j.title}</td>
        <td>${j.target}</td>
        <td class="${cls}">${j.status}</td>
        <td><div class="bar"><div class="fill" style="width:${j.percent}%"></div></div> ${j.percent}%</td>
        <td>${j.speed}</td>
      </tr>`;
    }).join('') || '<tr><td colspan="5" style="color:#64748b;">Очередь пуста</td></tr>';
  } catch (e) {}
}
setInterval(loadJobs, 1500);
loadJobs();
</script>
</body>
</html>
"""

def worker_loop():
    while True:
        with QUEUE_COND:
            while not TASK_QUEUE:
                QUEUE_COND.wait()
            job_id = TASK_QUEUE.pop(0)
        run_download(job_id)

def run_download(job_id):
    with JOBS_LOCK:
        job = JOBS.get(job_id)
        if not job:
            return
        job["status"] = "Скачивание..."
        url = job["url"]
        mode = job["mode"]
        allow_pl = job["playlist"] == "yes"

    is_audio = mode.startswith("audio_")
    final_dir = MUSIC_DIR if is_audio else VIDEO_DIR
    mirror_dl_dir = DL_MUSIC_DIR if is_audio else DL_VIDEO_DIR
    os.makedirs(final_dir, exist_ok=True)
    os.makedirs(mirror_dl_dir, exist_ok=True)
    job_tmp = os.path.join(TEMP_DIR, job_id)
    os.makedirs(job_tmp, exist_ok=True)
    apply_media_perms(job_tmp)

    def progress_hook(d):
        with JOBS_LOCK:
            j = JOBS.get(job_id)
            if not j:
                return
            info = d.get("info_dict") or {}
            if info.get("title"):
                j["title"] = info.get("title")
            if d.get("status") == "downloading":
                total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
                downloaded = d.get("downloaded_bytes") or 0
                if total > 0:
                    j["percent"] = min(99, int(downloaded * 100 / total))
                spd = d.get("speed") or 0
                j["speed"] = f"{spd / 1048576:.1f} МБ/с" if spd else "—"
            elif d.get("status") == "finished":
                j["percent"] = 99
                j["status"] = "Вшивание обложки и тегов..."

    ydl_opts = {
        "noplaylist": not allow_pl,
        "paths": {"home": job_tmp, "temp": job_tmp},
        "outtmpl": "%(title).150B [%(id)s].%(ext)s",
        "windowsfilenames": True,
        "progress_hooks": [progress_hook],
        "quiet": True,
        "no_warnings": True,
    }

    if is_audio:
        acodec = "mp3" if mode == "audio_mp3" else ("m4a" if mode == "audio_m4a" else "flac")
        aqual = "320" if mode == "audio_mp3" else ("256" if mode == "audio_m4a" else "0")
        ydl_opts["format"] = "bestaudio/best"
        ydl_opts["writethumbnail"] = True
        ydl_opts["postprocessors"] = [
            {"key": "FFmpegExtractAudio", "preferredcodec": acodec, "preferredquality": aqual},
            {"key": "FFmpegThumbnailsConvertor", "format": "jpg", "when": "before_dl"},
            {"key": "FFmpegMetadata", "add_metadata": True},
            {"key": "EmbedThumbnail", "already_have_thumbnail": False},
        ]
    elif mode == "video_1080":
        ydl_opts["format"] = "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        ydl_opts["merge_output_format"] = "mp4"
        ydl_opts["postprocessors"] = [{"key": "FFmpegMetadata", "add_metadata": True}]
    elif mode == "video_720":
        ydl_opts["format"] = "bestvideo[height<=720]+bestaudio/best[height<=720]"
        ydl_opts["merge_output_format"] = "mp4"
        ydl_opts["postprocessors"] = [{"key": "FFmpegMetadata", "add_metadata": True}]
    else:
        ydl_opts["format"] = "bestvideo+bestaudio/best"
        ydl_opts["merge_output_format"] = "mp4"
        ydl_opts["postprocessors"] = [{"key": "FFmpegMetadata", "add_metadata": True}]

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])
        saved_count = 0
        for fname in os.listdir(job_tmp):
            if fname.endswith((".part", ".ytdl", ".temp", ".webp", ".jpg", ".jpeg", ".png")):
                continue
            src = os.path.join(job_tmp, fname)
            dst = os.path.join(final_dir, fname)
            mirror_dst = os.path.join(mirror_dl_dir, fname)
            if os.path.isfile(src):
                if os.path.exists(dst):
                    os.remove(dst)
                shutil.move(src, dst)
                apply_media_perms(dst)
                # Создаем жесткую ссылку (0 лишних байт) также в /srv/storage/Downloads/{Music,Videos},
                # чтобы файл был виден и в корневой папке Music, и в папке Downloads/Music!
                try:
                    if os.path.exists(mirror_dst):
                        os.remove(mirror_dst)
                    os.link(dst, mirror_dst)
                    apply_media_perms(mirror_dst)
                except OSError:
                    pass
                saved_count += 1
        apply_media_perms(final_dir)
        apply_media_perms(mirror_dl_dir)
        with JOBS_LOCK:
            if job_id in JOBS:
                JOBS[job_id]["percent"] = 100
                JOBS[job_id]["speed"] = "—"
                JOBS[job_id]["status"] = f"Готово ({final_dir})" if saved_count > 0 else "Ошибка: файл не создан"
    except Exception as exc:
        with JOBS_LOCK:
            if job_id in JOBS:
                JOBS[job_id]["status"] = f"Ошибка: {str(exc)[:60]}"
                JOBS[job_id]["speed"] = "—"
    finally:
        shutil.rmtree(job_tmp, ignore_errors=True)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/api/jobs":
            with JOBS_LOCK:
                out = list(JOBS.values())[::-1]
            body = json.dumps(out).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)
        else:
            body = HTML_PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)

    def do_POST(self):
        p = urlparse(self.path).path
        if p == "/api/add":
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length).decode("utf-8")
            data = json.loads(raw)
            url = (data.get("url") or "").strip()
            mode = data.get("mode") or "video_best"
            pl = data.get("playlist") or "no"
            if url.startswith(("http://", "https://")):
                jid = uuid.uuid4().hex[:10]
                target_lbl = f"🎵 {MUSIC_DIR}" if mode.startswith("audio_") else f"🎬 {VIDEO_DIR}"
                with JOBS_LOCK:
                    JOBS[jid] = {
                        "id": jid,
                        "url": url,
                        "title": url,
                        "mode": mode,
                        "playlist": pl,
                        "target": target_lbl,
                        "status": "В очереди",
                        "percent": 0,
                        "speed": "—",
                    }
                with QUEUE_COND:
                    TASK_QUEUE.append(jid)
                    QUEUE_COND.notify()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
        elif p == "/api/clear":
            with JOBS_LOCK:
                to_del = [k for k, v in JOBS.items() if v["status"].startswith("Готово") or v["status"].startswith("Ошибка")]
                for k in to_del:
                    del JOBS[k]
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"ok":true}')

if __name__ == "__main__":
    t = threading.Thread(target=worker_loop, daemon=True)
    t.start()
    srv = ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), Handler)
    srv.serve_forever()
PY_EOF
    chmod 755 "$YTDLP_WEB_SCRIPT"

    cat << YTDLP_INIT > /etc/init.d/ytdlp-webui
#!/sbin/openrc-run
name="ytdlp-webui"
description="yt-dlp Web UI Media Downloader"
supervisor="supervise-daemon"
command="/usr/bin/python3"
command_args="${YTDLP_WEB_SCRIPT}"
command_user="ytdlp:${MEDIA_GROUP}"
umask="0002"
output_log="/var/log/ytdlp-webui.log"
error_log="/var/log/ytdlp-webui.log"
export STORAGE_MUSIC="${STORAGE_MUSIC}"
export STORAGE_VIDEOS="${STORAGE_VIDEOS}"
export STORAGE_DL_MUSIC="${STORAGE_DL_MUSIC}"
export STORAGE_DL_VIDEOS="${STORAGE_DL_VIDEOS}"
export STORAGE_INC_YTDLP="${STORAGE_INC_YTDLP}"
export PORT_YTDLP="${PORT_YTDLP}"
export MEDIA_GROUP="${MEDIA_GROUP}"

depend() {
    need net
}

start_pre() {
    checkpath -f -m 0644 -o ytdlp:${MEDIA_GROUP} /var/log/ytdlp-webui.log
    checkpath -d -m 2775 -o ytdlp:${MEDIA_GROUP} "${STORAGE_INC_YTDLP}"
}
YTDLP_INIT
    chmod +x /etc/init.d/ytdlp-webui

    repair_storage_permissions
    service_ctl ytdlp-webui enable
    if ! service_ctl ytdlp-webui restart; then
        echo "${C_RED}[X] Служба ytdlp-webui не смогла запуститься!${C_RES}"
        return 1
    fi
    register_caddy_site "ytdlp" "$DOM_YTDLP" "$PORT_YTDLP" "yes"
    set_module_state "ytdlp" "yes"

    echo "${C_GRN}[✓] Веб-панель yt-dlp запущена: https://${DOM_YTDLP} (Логин: ${SMB_USER:-admin} / Пароль: единый пароль шлюза)${C_RES}"
    return 0
}

remove_module_ytdlp() {
    service_ctl ytdlp-webui stop
    service_ctl ytdlp-webui disable
    remove_caddy_site "ytdlp"
    set_module_state "ytdlp" "no"
    echo "${C_GRN}[✓] Модуль yt-dlp Web UI отключен.${C_RES}"
    return 0
}

# 7. Модуль qBittorrent-nox + Hardlink-импортер в медиатеку (Movies / Series / Music) без потери раздачи
