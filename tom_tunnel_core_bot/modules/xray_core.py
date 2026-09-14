import base64
import html
import json
import os
import re
import shutil
import subprocess
import urllib.request
import uuid
from datetime import datetime, timedelta
from pathlib import Path

XRAY_CONF = Path("/etc/xray/config.json")
DB_DIR = Path("/etc/tom_tunnel_bot/xray_accounts")
LEGACY_DB_DIR = Path("/etc/tom_tunnel_bot/xray_accounts")
WEB_CONFIG = Path("/etc/tom_tunnel_web/config.json")
VALID_PROTOCOLS = {"vless", "vmess", "trojan", "socks"}
USER_RE = re.compile(r"^[A-Za-z0-9._-]{1,32}$")

MARKERS = {
    "vless": ("#vless", "#vlessgrpc"),
    "vmess": ("#vmess", "#vmessgrpc"),
    "trojan": ("#trojanws", "#trojangrpc"),
    "socks": ("#ssws", "#ssgrpc"),
}
PREFIX = {"vless": "#&", "vmess": "###", "trojan": "#!", "socks": "#@"}


def _esc(v):
    return html.escape(str(v if v is not None else ""), quote=False)


def _run(args, timeout=30):
    try:
        return subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None


def get_domain():
    try:
        value = Path("/etc/xray/domain").read_text(encoding="utf-8").strip()
        return value or "votre-domaine.com"
    except OSError:
        return "votre-domaine.com"


def _valid(protocol, user):
    return protocol in VALID_PROTOCOLS and bool(USER_RE.fullmatch((user or "").strip()))


def _db_dir():
    DB_DIR.mkdir(parents=True, exist_ok=True)
    return DB_DIR


def _db_path(protocol, user):
    return _db_dir() / f"{protocol}_{user}.txt"


def _legacy_path(protocol, user):
    return LEGACY_DB_DIR / f"{protocol}_{user}.txt"


def _find_db(protocol, user):
    for path in (_db_path(protocol, user), _legacy_path(protocol, user)):
        if path.is_file():
            return path
    return None


def _write_db(protocol, user, data):
    path = _db_path(protocol, user)
    content = "".join(f"{k}={v}\n" for k, v in data.items())
    tmp = path.with_suffix(".tmp")
    tmp.write_text(content, encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def _read_db(path):
    data = {}
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                data[k] = v
    except OSError:
        return {}
    return data


def _sync_web(user, password, protocol, expiry, client_id):
    try:
        port = 2087
        if WEB_CONFIG.is_file():
            with WEB_CONFIG.open(encoding="utf-8") as f:
                port = int(json.load(f).get("port", port))
        payload = json.dumps({"username": user, "protocol": protocol, "password": password, "expiry": expiry, "uuid": client_id}).encode()
        req = urllib.request.Request(f"http://127.0.0.1:{port}/api/clients/sync", data=payload, method="POST", headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=2) as response:
            response.read()
    except Exception:
        pass


def _valid_days(days):
    try:
        n = int(str(days).strip())
        return n if 1 <= n <= 3650 else None
    except (TypeError, ValueError):
        return None


def _insert_client(protocol, user, expiry, client_id):
    if not XRAY_CONF.is_file():
        return False, "Fichier config Xray introuvable."
    markers = MARKERS[protocol]
    prefix = PREFIX[protocol]
    lines = XRAY_CONF.read_text(encoding="utf-8").splitlines(True)
    # Refuse duplicates by our metadata comments.
    user_re = re.compile(rf"^\s*{re.escape(prefix)}\s+{re.escape(user)}\s+")
    if any(user_re.search(line) for line in lines):
        return False, "Cet utilisateur existe déjà dans la configuration Xray."

    if protocol == "vless":
        client_line = f'}},{{"id": "{client_id}","email": "{user}"\n'
    elif protocol == "vmess":
        client_line = f'}},{{"id": "{client_id}","alterId": 0,"email": "{user}"\n'
    elif protocol == "trojan":
        client_line = f'}},{{"password": "{client_id}","email": "{user}"\n'
    else:
        client_line = f'}},{{"password": "{client_id}","method": "aes-128-gcm","email": "{user}"\n'

    out = []
    injected = 0
    for line in lines:
        out.append(line)
        marker = line.strip()
        if marker in markers:
            out.append(f"{prefix} {user} {expiry} {client_id}\n")
            out.append(client_line)
            injected += 1

    if injected == 0:
        return False, f"Balises {protocol.upper()} introuvables dans /etc/xray/config.json."

    backup = XRAY_CONF.with_suffix(".json.bot.bak")
    shutil.copy2(XRAY_CONF, backup)
    XRAY_CONF.write_text("".join(out), encoding="utf-8")
    result = _run(["xray", "run", "-test", "-config", str(XRAY_CONF)], timeout=20)
    if not result or result.returncode != 0:
        shutil.copy2(backup, XRAY_CONF)
        return False, f"Configuration Xray invalide : {_esc((result.stderr if result else 'test indisponible').strip()[-1200:])}"
    restart = _run(["systemctl", "restart", "xray"], timeout=30)
    if not restart or restart.returncode != 0:
        shutil.copy2(backup, XRAY_CONF)
        _run(["systemctl", "restart", "xray"], timeout=30)
        return False, "Xray n'a pas pu redémarrer. Configuration restaurée."
    return True, "OK"


def _links(protocol, user, client_id):
    domain = get_domain()
    if protocol == "vless":
        return (
            f"vless://{client_id}@{domain}:443?path=/vless&security=tls&encryption=none&type=ws#{user}",
            f"vless://{client_id}@{domain}:80?path=/vless&security=none&encryption=none&type=ws#{user}",
            f"vless://{client_id}@{domain}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc#{user}",
        )
    if protocol == "vmess":
        def enc(port, tls, net="ws"):
            path = "/vmess" if net == "ws" else "vmess-grpc"
            obj = {"v":"2","ps":user,"add":domain,"port":str(port),"id":client_id,"aid":"0","net":net,"path":path,"type":"none","host":"","tls":tls}
            return "vmess://" + base64.b64encode(json.dumps(obj, separators=(",", ":")).encode()).decode()
        return enc(443, "tls"), enc(80, "none"), enc(443, "tls", "grpc")
    if protocol == "trojan":
        return (
            f"trojan://{client_id}@{domain}:443?path=/trws&security=tls&type=ws&sni={domain}#{user}",
            f"trojan://{client_id}@{domain}:80?path=/trws&security=none&type=ws&host={domain}#{user}",
            f"trojan://{client_id}@{domain}:443?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni={domain}#{user}",
        )
    raw = base64.b64encode(f"aes-128-gcm:{client_id}".encode()).decode().rstrip("=")
    return (
        f"ss://{raw}@{domain}:443?path=ss-ws&security=tls&type=ws&sni={domain}#{user}",
        f"ss://{raw}@{domain}:80?path=ss-ws&security=none&type=ws#{user}",
        f"ss://{raw}@{domain}:443?mode=gun&security=tls&type=grpc&serviceName=ss-grpc&sni={domain}#{user}",
    )


def _format(protocol, user, client_id, expiry):
    domain = get_domain()
    a, b, c = _links(protocol, user, client_id)
    return (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n┃ <b>{protocol.upper()} ACCOUNT</b>\n┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"👤 <b>Username:</b> <code>{_esc(user)}</code>\n📅 <b>Expiry:</b> <code>{expiry}</code>\n"
        f"🔑 <b>UUID/Password:</b> <code>{_esc(client_id)}</code>\n🌐 <b>Domain:</b> <code>{_esc(domain)}</code>\n\n"
        f"🔗 <b>TLS:</b>\n<code>{_esc(a)}</code>\n\n🔗 <b>NTLS:</b>\n<code>{_esc(b)}</code>\n\n🔗 <b>gRPC:</b>\n<code>{_esc(c)}</code>"
    )


def create_xray_account(protocol, user, days, created_by_id=None):
    protocol = str(protocol or "").lower().strip()
    user = str(user or "").strip()
    if not _valid(protocol, user):
        return False, "❌ Protocole ou nom d'utilisateur invalide."
    day_count = _valid_days(days)
    if day_count is None:
        return False, "❌ La durée doit être comprise entre 1 et 3650 jours."
    if _find_db(protocol, user):
        return False, f"❌ Le compte <code>{_esc(user)}</code> existe déjà."
    expiry = (datetime.now() + timedelta(days=day_count)).strftime("%Y-%m-%d")
    client_id = str(uuid.uuid4())
    ok, message = _insert_client(protocol, user, expiry, client_id)
    if not ok:
        return False, f"❌ {message}"
    try:
        _write_db(protocol, user, {"username": user, "uuid": client_id, "expiry": expiry, "createdById": created_by_id or "", "createdAt": datetime.utcnow().replace(microsecond=0).isoformat()+"Z", "protocol": protocol, "status": "active"})
    except OSError as exc:
        return False, f"⚠️ Compte Xray créé mais métadonnées impossibles à écrire : <code>{_esc(exc)}</code>"
    _sync_web(user, client_id, protocol, expiry, client_id)
    return True, _format(protocol, user, client_id, expiry)


def get_xray_usernames(protocol):
    protocol = str(protocol or "").lower()
    if protocol not in VALID_PROTOCOLS:
        return []
    names = set()
    for directory in (DB_DIR, LEGACY_DB_DIR):
        if directory.is_dir():
            prefix = protocol + "_"
            for path in directory.glob(prefix + "*.txt"):
                user = path.stem[len(prefix):]
                if _valid(protocol, user):
                    names.add(user)
    return sorted(names)


def get_xray_account_details(protocol, user):
    protocol = str(protocol or "").lower().strip()
    user = str(user or "").strip()
    if not _valid(protocol, user):
        return False, "❌ Données invalides."
    path = _find_db(protocol, user)
    if not path:
        return False, f"❌ Compte {protocol.upper()} <code>{_esc(user)}</code> introuvable."
    data = _read_db(path)
    return True, _format(protocol, user, data.get("uuid", "N/A"), data.get("expiry", "N/A"))


def renew_xray_account(protocol, user, days):
    protocol = str(protocol or "").lower().strip()
    user = str(user or "").strip()
    if not _valid(protocol, user):
        return False, "❌ Données invalides."
    path = _find_db(protocol, user)
    if not path:
        return False, f"❌ Compte {protocol.upper()} <code>{_esc(user)}</code> introuvable."
    day_count = _valid_days(days)
    if day_count is None:
        return False, "❌ La durée doit être comprise entre 1 et 3650 jours."
    data = _read_db(path)
    current = data.get("expiry")
    try:
        base = datetime.strptime(current, "%Y-%m-%d") if current else datetime.now()
        if base < datetime.now(): base = datetime.now()
    except ValueError:
        base = datetime.now()
    new_expiry = (base + timedelta(days=day_count)).strftime("%Y-%m-%d")
    pattern = re.compile(rf"^(\s*{re.escape(PREFIX[protocol])}\s+{re.escape(user)}\s+)\S+(\s+\S+\s*)$", re.MULTILINE)
    content = XRAY_CONF.read_text(encoding="utf-8") if XRAY_CONF.is_file() else ""
    new_content, count = pattern.subn(rf"\g<1>{new_expiry}\2", content)
    if count == 0:
        return False, f"❌ Entrée {protocol.upper()} de <code>{_esc(user)}</code> introuvable dans Xray."
    backup = XRAY_CONF.with_suffix(".json.bot.bak")
    shutil.copy2(XRAY_CONF, backup)
    XRAY_CONF.write_text(new_content, encoding="utf-8")
    test = _run(["xray", "run", "-test", "-config", str(XRAY_CONF)], timeout=20)
    if not test or test.returncode != 0:
        shutil.copy2(backup, XRAY_CONF)
        return False, "❌ Nouvelle configuration Xray invalide. Configuration restaurée."
    restart = _run(["systemctl", "restart", "xray"], timeout=30)
    if not restart or restart.returncode != 0:
        shutil.copy2(backup, XRAY_CONF)
        _run(["systemctl", "restart", "xray"], timeout=30)
        return False, "❌ Xray n'a pas redémarré. Configuration restaurée."
    data["expiry"] = new_expiry
    _write_db(protocol, user, data)
    _sync_web(user, data.get("uuid", ""), protocol, new_expiry, data.get("uuid", ""))
    return True, f"✅ <b>{protocol.upper()} RENOUVELÉ</b>\n👤 <code>{_esc(user)}</code>\n📅 <code>{new_expiry}</code>"


def delete_xray_account(protocol, user):
    protocol = str(protocol or "").lower().strip()
    user = str(user or "").strip()
    if not _valid(protocol, user):
        return False, "❌ Données invalides."
    if not XRAY_CONF.is_file():
        return False, "❌ Fichier config Xray introuvable."
    prefix = PREFIX[protocol]
    marker = re.compile(rf"^\s*{re.escape(prefix)}\s+{re.escape(user)}\s+\S+\s+\S+\s*\n?", re.MULTILINE)
    content = XRAY_CONF.read_text(encoding="utf-8")
    matches = list(marker.finditer(content))
    if not matches:
        return False, f"❌ Utilisateur <code>{_esc(user)}</code> introuvable dans Xray."
    # Each marker is immediately followed by the generated client object line.
    spans = []
    for match in matches:
        end = match.end()
        next_nl = content.find("\n", end)
        if next_nl >= 0:
            end = next_nl + 1
        spans.append((match.start(), end))
    new_content = content
    for start, end in reversed(spans):
        new_content = new_content[:start] + new_content[end:]
    backup = XRAY_CONF.with_suffix(".json.bot.bak")
    shutil.copy2(XRAY_CONF, backup)
    XRAY_CONF.write_text(new_content, encoding="utf-8")
    test = _run(["xray", "run", "-test", "-config", str(XRAY_CONF)], timeout=20)
    if not test or test.returncode != 0:
        shutil.copy2(backup, XRAY_CONF)
        return False, "❌ Suppression rendrait la configuration Xray invalide. Configuration restaurée."
    restart = _run(["systemctl", "restart", "xray"], timeout=30)
    if not restart or restart.returncode != 0:
        shutil.copy2(backup, XRAY_CONF)
        _run(["systemctl", "restart", "xray"], timeout=30)
        return False, "❌ Xray n'a pas redémarré. Configuration restaurée."
    for path in (_db_path(protocol, user), _legacy_path(protocol, user)):
        try:
            if path.exists(): path.unlink()
        except OSError: pass
    return True, f"🗑️ <b>Compte {protocol.upper()} <code>{_esc(user)}</code> supprimé.</b>"
