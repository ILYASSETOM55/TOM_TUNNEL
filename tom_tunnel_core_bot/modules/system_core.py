import os
import platform
import shutil
import subprocess
import psutil


def _run(args, timeout=15):
    try:
        return subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None


def _uptime():
    result = _run(["uptime", "-p"], 5)
    if result and result.returncode == 0:
        return result.stdout.strip()
    try:
        return str(__import__("datetime").timedelta(seconds=int(__import__("time").time() - psutil.boot_time())))
    except Exception:
        return "N/A"


def _os_name():
    try:
        for line in open("/etc/os-release", encoding="utf-8"):
            if line.startswith("PRETTY_NAME="):
                return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return platform.platform()


def get_vps_status():
    try:
        ram = psutil.virtual_memory()
        disk = psutil.disk_usage("/")
        load = os.getloadavg()[0] if hasattr(os, "getloadavg") else 0
        return (
            "📊 <b>ÉTAT DU SERVEUR TOM_TUNNEL</b>\n\n"
            f"🖥️ <b>OS:</b> <code>{_os_name()}</code>\n"
            f"⏱️ <b>Uptime:</b> <code>{_uptime()}</code>\n"
            f"⚙️ <b>CPU:</b> <code>{psutil.cpu_percent(interval=0.5)}%</code>\n"
            f"📈 <b>Load:</b> <code>{load:.2f}</code>\n"
            f"💾 <b>RAM:</b> <code>{ram.percent}%</code> ({ram.used // 1048576}MB / {ram.total // 1048576}MB)\n"
            f"💽 <b>Disque:</b> <code>{disk.percent}%</code> ({disk.used // 1073741824}GB / {disk.total // 1073741824}GB)\n"
        )
    except Exception as exc:
        return f"❌ Erreur de lecture système : <code>{str(exc)[:1000]}</code>"


def clean_system_logs():
    results = []
    if shutil.which("journalctl"):
        result = _run(["journalctl", "--vacuum-time=1d"], 30)
        results.append("journalctl OK" if result and result.returncode == 0 else "journalctl: échec")
    if shutil.which("apt-get"):
        result = _run(["apt-get", "clean"], 30)
        results.append("apt clean OK" if result and result.returncode == 0 else "apt clean: échec")
    return "🧹 <b>Nettoyage terminé.</b>\n" + "\n".join(results or ["Aucun outil de nettoyage disponible."])
