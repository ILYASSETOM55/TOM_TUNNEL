import html
import json
import os
import re
import subprocess
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

DB_DIR = Path("/etc/tom_tunnel_bot/ssh_accounts")
LEGACY_DB_DIR = Path("/etc/nexus_bot/ssh_accounts")
WEB_CONFIG = Path("/etc/nexus-tunnel-web/config.json")
USER_RE = re.compile(r"^[A-Za-z0-9._-]{1,32}$")


def _esc(value):
    return html.escape(str(value if value is not None else ""), quote=False)


def get_file(path, default="N/A"):
    try:
        value = Path(path).read_text(encoding="utf-8").strip()
        return value or default
    except (OSError, UnicodeError):
        return default


def _valid_user(user):
    return bool(USER_RE.fullmatch((user or "").strip()))


def _run(args, input_text=None, timeout=15):
    try:
        return subprocess.run(args, input=input_text, text=True, capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None


def _user_exists(user):
    if not _valid_user(user):
        return False
    result = _run(["id", "--", user], timeout=5)
    return bool(result and result.returncode == 0)


def _account_path(user):
    return DB_DIR / f"{user}.txt"


def _legacy_path(user):
    return LEGACY_DB_DIR / f"{user}.txt"


def _read_account(user):
    for path in (_account_path(user), _legacy_path(user)):
        if not path.is_file():
            continue
        data = {}
        try:
            for line in path.read_text(encoding="utf-8").splitlines():
                if "=" in line:
                    key, value = line.split("=", 1)
                    data[key.strip()] = value.strip()
            return data
        except OSError:
            return None
    return None


def _write_account(user, data):
    DB_DIR.mkdir(parents=True, exist_ok=True)
    path = _account_path(user)
    tmp = path.with_suffix(".tmp")
    lines = []
    order = ["username", "password", "expiry", "createdById", "createdAt", "protocol", "status"]
    for key in order:
        if key in data:
            lines.append(f"{key}={data[key]}")
    for key, value in data.items():
        if key not in order:
            lines.append(f"{key}={value}")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def _server_info():
    domain = get_file("/etc/xray/domain", "N/A")
    pub = get_file("/etc/slowdns/server.pub", "N/A")
    ns = get_file("/etc/slowdns/nsdomain", "N/A")
    ip = "N/A"
    for cmd in (["curl", "-4", "-fsS", "--max-time", "4", "https://ipv4.icanhazip.com"], ["wget", "-qO-", "--timeout=4", "https://ipv4.icanhazip.com"]):
        result = _run(cmd, timeout=6)
        if result and result.returncode == 0 and result.stdout.strip():
            ip = result.stdout.strip()
            break
    return domain, pub, ns, ip


def _sync_web(user, password, expiry):
    try:
        port = 2087
        if WEB_CONFIG.is_file():
            with WEB_CONFIG.open(encoding="utf-8") as f:
                port = int(json.load(f).get("port", port))
        payload = json.dumps({"username": user, "protocol": "ssh", "password": password, "expiry": expiry, "uuid": ""}).encode()
        req = urllib.request.Request(f"http://127.0.0.1:{port}/api/clients/sync", data=payload, method="POST", headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=2) as response:
            response.read()
    except Exception:
        pass


def _valid_days(days):
    try:
        value = int(str(days).strip())
        return value if 1 <= value <= 3650 else None
    except (TypeError, ValueError):
        return None


def _account_status(user):
    result = _run(["passwd", "-S", "--", user], timeout=5)
    if not result or result.returncode != 0:
        return "unknown"
    parts = result.stdout.split()
    return "locked" if len(parts) > 1 and parts[1].startswith("L") else "active"


def create_ssh_account(user, password, days, created_by_id=None):
    user = str(user or "").strip()
    password = str(password or "")
    if not _valid_user(user):
        return False, "❌ Nom d'utilisateur invalide. Utilisez lettres, chiffres, point, tiret ou underscore (1-32 caractères)."
    if not password or "\n" in password or "\r" in password:
        return False, "❌ Mot de passe invalide."
    day_count = _valid_days(days)
    if day_count is None:
        return False, "❌ La durée doit être comprise entre 1 et 3650 jours."
    if _user_exists(user):
        return False, f"❌ L'utilisateur <code>{_esc(user)}</code> existe déjà."

    expiry = (datetime.now() + timedelta(days=day_count)).strftime("%Y-%m-%d")
    result = _run(["useradd", "-e", expiry, "-s", "/bin/false", "-M", "--", user], timeout=15)
    if not result or result.returncode != 0:
        err = result.stderr.strip() if result else "commande indisponible"
        return False, f"❌ Échec useradd : <code>{_esc(err)}</code>"

    result = _run(["chpasswd"], input_text=f"{user}:{password}\n", timeout=15)
    if not result or result.returncode != 0:
        _run(["userdel", "--", user], timeout=10)
        err = result.stderr.strip() if result else "commande indisponible"
        return False, f"❌ Échec du mot de passe : <code>{_esc(err)}</code>"

    try:
        _write_account(user, {"username": user, "password": password, "expiry": expiry, "createdById": created_by_id or "", "createdAt": datetime.utcnow().replace(microsecond=0).isoformat() + "Z", "protocol": "ssh", "status": "active"})
    except OSError as exc:
        return False, f"⚠️ Compte Linux créé mais métadonnées impossibles à écrire : <code>{_esc(exc)}</code>"
    _sync_web(user, password, expiry)
    domain, pub, ns, ip = _server_info()
    return True, (
        "╭▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╮\n┃ <b>SSH / WS ACCOUNT</b>\n╰▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╯\n"
        f"👤 <b>Username:</b> <code>{_esc(user)}</code>\n🔑 <b>Password:</b> <code>{_esc(password)}</code>\n"
        f"⏳ <b>Expiry:</b> <code>{expiry}</code>\n🖥️ <b>IP:</b> <code>{_esc(ip)}</code>\n🌐 <b>Domain:</b> <code>{_esc(domain)}</code>\n⚓ <b>NS:</b> <code>{_esc(ns)}</code>\n"
        "🔌 <b>Ports:</b> SSH 22 | Dropbear 109/143 | WS 80/443\n"
        f"🐌 <b>SlowDNS PUB:</b>\n<code>{_esc(pub)}</code>"
    )


def get_ssh_usernames():
    users = set()
    for directory in (DB_DIR, LEGACY_DB_DIR):
        if directory.is_dir():
            for path in directory.glob("*.txt"):
                if _valid_user(path.stem) and _user_exists(path.stem):
                    users.add(path.stem)
    return sorted(users)


def get_ssh_account_details(user):
    user = str(user or "").strip()
    if not _valid_user(user):
        return False, "❌ Nom d'utilisateur invalide."
    data = _read_account(user)
    if data is None or not _user_exists(user):
        return False, f"❌ Compte SSH <code>{_esc(user)}</code> introuvable."
    domain, pub, ns, ip = _server_info()
    return True, (
        "╭▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╮\n┃ <b>SSH ACCOUNT DETAILS</b>\n╰▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╯\n"
        f"👤 <b>Username:</b> <code>{_esc(user)}</code>\n🔑 <b>Password:</b> <code>{_esc(data.get('password', 'N/A'))}</code>\n"
        f"⏳ <b>Expiry:</b> <code>{_esc(data.get('expiry', 'N/A'))}</code>\n📌 <b>Status:</b> <code>{_account_status(user)}</code>\n"
        f"🖥️ <b>IP:</b> <code>{_esc(ip)}</code>\n🌐 <b>Domain:</b> <code>{_esc(domain)}</code>\n⚓ <b>NS:</b> <code>{_esc(ns)}</code>\n"
        f"🐌 <b>SlowDNS PUB:</b>\n<code>{_esc(pub)}</code>"
    )


def renew_ssh_account(user, days):
    user = str(user or "").strip()
    if not _valid_user(user) or not _user_exists(user):
        return False, f"❌ Utilisateur <code>{_esc(user)}</code> introuvable."
    day_count = _valid_days(days)
    if day_count is None:
        return False, "❌ La durée doit être comprise entre 1 et 3650 jours."
    data = _read_account(user) or {}
    try:
        base = datetime.strptime(data.get("expiry", ""), "%Y-%m-%d")
        if base < datetime.now():
            base = datetime.now()
    except ValueError:
        base = datetime.now()
    new_expiry = (base + timedelta(days=day_count)).strftime("%Y-%m-%d")
    result = _run(["usermod", "-e", new_expiry, "--", user], timeout=10)
    if not result or result.returncode != 0:
        err = result.stderr.strip() if result else "commande indisponible"
        return False, f"❌ Renouvellement impossible : <code>{_esc(err)}</code>"
    data["expiry"] = new_expiry
    data.setdefault("username", user)
    data.setdefault("protocol", "ssh")
    _write_account(user, data)
    _sync_web(user, data.get("password", ""), new_expiry)
    return True, f"✅ <b>SSH RENOUVELÉ</b>\n👤 <code>{_esc(user)}</code>\n📅 Nouvelle expiration : <code>{new_expiry}</code>"


def delete_ssh_account(user):
    user = str(user or "").strip()
    if not _valid_user(user):
        return False, "❌ Nom d'utilisateur invalide."
    if not _user_exists(user):
        for path in (_account_path(user), _legacy_path(user)):
            try:
                if path.exists(): path.unlink()
            except OSError: pass
        return False, f"❌ Utilisateur <code>{_esc(user)}</code> introuvable."
    _run(["pkill", "-u", user], timeout=10)
    result = _run(["userdel", "-r", "--", user], timeout=15)
    if not result or result.returncode != 0:
        err = result.stderr.strip() if result else "commande indisponible"
        return False, f"❌ Suppression impossible : <code>{_esc(err)}</code>"
    for path in (_account_path(user), _legacy_path(user)):
        try:
            if path.exists(): path.unlink()
        except OSError: pass
    return True, f"🗑️ <b>Compte SSH <code>{_esc(user)}</code> supprimé.</b>"


def lock_ssh_account(user):
    user = str(user or "").strip()
    if not _valid_user(user) or not _user_exists(user):
        return False, f"❌ Utilisateur <code>{_esc(user)}</code> introuvable."
    result = _run(["passwd", "-l", "--", user], timeout=10)
    if not result or result.returncode != 0:
        err = result.stderr.strip() if result else "commande indisponible"
        return False, f"❌ Verrouillage impossible : <code>{_esc(err)}</code>"
    data = _read_account(user) or {"username": user, "protocol": "ssh"}
    data["status"] = "locked"
    _write_account(user, data)
    return True, f"🔒 <b>Compte <code>{_esc(user)}</code> verrouillé.</b>"


def unlock_ssh_account(user):
    user = str(user or "").strip()
    if not _valid_user(user) or not _user_exists(user):
        return False, f"❌ Utilisateur <code>{_esc(user)}</code> introuvable."
    result = _run(["passwd", "-u", "--", user], timeout=10)
    if not result or result.returncode != 0:
        err = result.stderr.strip() if result else "commande indisponible"
        return False, f"❌ Déverrouillage impossible : <code>{_esc(err)}</code>"
    data = _read_account(user) or {"username": user, "protocol": "ssh"}
    data["status"] = "active"
    _write_account(user, data)
    return True, f"🔓 <b>Compte <code>{_esc(user)}</code> déverrouillé.</b>"
