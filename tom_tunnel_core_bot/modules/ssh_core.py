import os
import re
import subprocess
from datetime import datetime, timedelta

DB_DIR = "/etc/tom_tunnel_bot/ssh_accounts"
WEB_CONFIG = "/etc/nexus-tunnel-web/config.json"

def get_file(path, default="NON_DEFINI"):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return default

def _valid_user(user):
    return bool(re.fullmatch(r"[A-Za-z0-9._-]{1,32}", user or ""))

def _server_info():
    domain = get_file("/etc/xray/domain", "votre-domaine.com")
    pub_key = get_file("/etc/slowdns/server.pub", "PUB_KEY_NOT_FOUND")
    ns_domain = get_file("/etc/slowdns/nsdomain", "NS_DOMAIN_NOT_FOUND")
    myip = subprocess.getoutput(
        "wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ipv4.icanhazip.com"
    )
    return domain, pub_key, ns_domain, myip

def _sync_web(user, password, expiry):
    try:
        import json, urllib.request
        port = 2087
        try:
            with open(WEB_CONFIG, "r", encoding="utf-8") as f:
                port = int(json.load(f).get("port", port))
        except Exception:
            pass
        data = json.dumps({
            "username": user, "protocol": "ssh",
            "password": password, "expiry": expiry, "uuid": ""
        }).encode()
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/clients/sync",
            data=data, method="POST",
            headers={"Content-Type": "application/json"}
        )
        urllib.request.urlopen(req, timeout=2).read()
    except Exception:
        pass

def create_ssh_account(user, password, days, created_by_id=None):
    if not _valid_user(user):
        return False, "❌ Nom d'utilisateur invalide. Utilisez lettres, chiffres, point, tiret ou underscore."
    if not password:
        return False, "❌ Le mot de passe est obligatoire."
    try:
        days = int(days)
        if days <= 0:
            raise ValueError
    except ValueError:
        return False, "❌ La durée doit être un nombre positif."

    if subprocess.run(["id", user], capture_output=True).returncode == 0:
        return False, f"❌ L'utilisateur <code>{user}</code> existe déjà."

    expiry = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    try:
        subprocess.run(
            ["useradd", "-e", expiry, "-s", "/bin/false", "-M", user],
            check=True, capture_output=True, text=True
        )
        subprocess.run(
            ["chpasswd"], input=f"{user}:{password}\n",
            check=True, capture_output=True, text=True
        )
    except subprocess.CalledProcessError as e:
        return False, f"❌ Échec de la création : <code>{e.stderr.strip()}</code>"

    os.makedirs(DB_DIR, exist_ok=True)
    with open(f"{DB_DIR}/{user}.txt", "w", encoding="utf-8") as f:
        f.write(
            f"username={user}\npassword={password}\nexpiry={expiry}\n"
            f"createdById={created_by_id}\ncreatedAt={datetime.utcnow().isoformat()}Z\n"
            "protocol=ssh\nstatus=active\n"
        )
    _sync_web(user, password, expiry)

    domain, pub_key, ns_domain, myip = _server_info()
    msg = (
        "╭▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╮\n"
        "┃ <b>SSH ACCOUNT DETAILS</b>\n"
        "╰▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╯\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"🔑 <b>Password:</b> <code>{password}</code>\n"
        f"⏳ <b>Expiry Date:</b> {expiry}\n"
        f"🖥️ <b>Host/IP:</b> <code>{myip}</code>\n"
        f"🌐 <b>Domain:</b> <code>{domain}</code>\n"
        f"⚓ <b>NS Domain:</b> <code>{ns_domain}</code>\n"
        "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬\n"
        "🔌 <b>Ports:</b>\n"
        "OpenSSH(22), Dropbear(109,143)\n"
        "Stunnel(447,777), WS(80,443)\n"
        "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬\n"
        f"🐌 <b>Slow DNS PUB:</b>\n<code>{pub_key}</code>"
    )
    return True, msg

def get_ssh_usernames():
    if not os.path.isdir(DB_DIR):
        return []
    return [x[:-4] for x in sorted(os.listdir(DB_DIR)) if x.endswith(".txt")]

def get_ssh_account_details(user):
    path = f"{DB_DIR}/{user}.txt"
    if not os.path.exists(path):
        return False, f"❌ Compte SSH <code>{user}</code> introuvable."
    data = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if "=" in line:
                k, v = line.rstrip().split("=", 1)
                data[k] = v
    domain, pub_key, ns_domain, myip = _server_info()
    return True, (
        "╭▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╮\n"
        "┃ <b>SSH ACCOUNT DETAILS</b>\n"
        "╰▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╯\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"🔑 <b>Password:</b> <code>{data.get('password','N/A')}</code>\n"
        f"⏳ <b>Expiry Date:</b> <code>{data.get('expiry','N/A')}</code>\n"
        f"🖥️ <b>Host/IP:</b> <code>{myip}</code>\n"
        f"🌐 <b>Domain:</b> <code>{domain}</code>\n"
        f"⚓ <b>NS Domain:</b> <code>{ns_domain}</code>\n"
        f"🐌 <b>Slow DNS PUB:</b>\n<code>{pub_key}</code>"
    )

def renew_ssh_account(user, days):
    if not _valid_user(user) or subprocess.run(["id", user], capture_output=True).returncode != 0:
        return False, f"❌ Utilisateur <code>{user}</code> introuvable."
    try:
        days = int(days)
        if days <= 0: raise ValueError
    except ValueError:
        return False, "❌ La durée doit être un nombre positif."

    path = f"{DB_DIR}/{user}.txt"
    current = None
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith("expiry="):
                    current = line.strip().split("=",1)[1]
                    break
    try:
        base = datetime.strptime(current, "%Y-%m-%d") if current else datetime.now()
        if base < datetime.now(): base = datetime.now()
    except ValueError:
        base = datetime.now()
    new_exp = (base + timedelta(days=days)).strftime("%Y-%m-%d")

    subprocess.run(["usermod", "-e", new_exp, user], capture_output=True)
    subprocess.run(["passwd", "-u", user], capture_output=True)

    if os.path.exists(path):
        lines = open(path, encoding="utf-8").readlines()
        with open(path, "w", encoding="utf-8") as f:
            for line in lines:
                f.write(f"expiry={new_exp}\n" if line.startswith("expiry=") else line)

    _sync_web(user, "", new_exp)
    return True, f"✅ <b>COMPTE SSH RENOUVELÉ</b>\n📅 Nouvelle expiration : <code>{new_exp}</code>"

def delete_ssh_account(user):
    if not _valid_user(user) or subprocess.run(["id", user], capture_output=True).returncode != 0:
        return False, f"❌ Utilisateur <code>{user}</code> introuvable."
    subprocess.run(["pkill", "-u", user], capture_output=True)
    subprocess.run(["userdel", "-r", user], capture_output=True)
    path = f"{DB_DIR}/{user}.txt"
    if os.path.exists(path): os.remove(path)
    return True, f"🗑️ <b>Compte SSH <code>{user}</code> supprimé.</b>"

def lock_ssh_account(user):
    if subprocess.run(["id", user], capture_output=True).returncode != 0:
        return False, f"❌ Utilisateur <code>{user}</code> introuvable."
    subprocess.run(["passwd", "-l", user], capture_output=True)
    return True, f"🔒 <b>Compte <code>{user}</code> verrouillé.</b>"

def unlock_ssh_account(user):
    if subprocess.run(["id", user], capture_output=True).returncode != 0:
        return False, f"❌ Utilisateur <code>{user}</code> introuvable."
    subprocess.run(["passwd", "-u", user], capture_output=True)
    return True, f"🔓 <b>Compte <code>{user}</code> déverrouillé.</b>"

def list_ssh_accounts():
    users = get_ssh_usernames()
    if not users:
        return "📋 Aucun compte SSH trouvé."
    msg = "📋 <b>LISTE DES COMPTES SSH:</b>\n\n"
    for user in users:
        ok, details = get_ssh_account_details(user)
        msg += f"👤 <code>{user}</code>\n"
    return msg + f"\n📊 <b>Total:</b> {len(users)} compte(s)"
