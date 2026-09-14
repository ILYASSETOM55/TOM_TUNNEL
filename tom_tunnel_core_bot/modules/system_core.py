import subprocess
import psutil

def get_vps_status():
    try:
        uptime = subprocess.check_output(
            "uptime -p", shell=True, text=True
        ).strip()
        os_info = subprocess.check_output(
            "grep '^PRETTY_NAME=' /etc/os-release | cut -d '=' -f 2-",
            shell=True, text=True
        ).strip().strip('"')
        cpu = psutil.cpu_percent(interval=1)
        ram = psutil.virtual_memory()
        disk = psutil.disk_usage("/")
        return (
            "📊 <b>ÉTAT DU SERVEUR TOM</b>\n\n"
            f"🖥️ <b>OS:</b> <code>{os_info}</code>\n"
            f"⏱️ <b>Uptime:</b> <code>{uptime}</code>\n"
            f"⚙️ <b>CPU:</b> <code>{cpu}%</code>\n"
            f"💾 <b>RAM:</b> <code>{ram.percent}%</code> "
            f"({ram.used // 1048576}MB / {ram.total // 1048576}MB)\n"
            f"💽 <b>Disque:</b> <code>{disk.percent}%</code> "
            f"({disk.used // 1073741824}GB / {disk.total // 1073741824}GB)"
        )
    except Exception as e:
        return f"❌ Erreur de lecture système : {e}"

def clean_system_logs():
    subprocess.run(
        "journalctl --vacuum-time=1d && apt-get clean",
        shell=True
    )
    return "🧹 <b>Logs et cache nettoyés avec succès.</b>"
