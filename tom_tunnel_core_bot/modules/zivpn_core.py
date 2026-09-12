import subprocess
import os
import re
from datetime import datetime, timedelta

META_DIR = "/etc/the_s_bot/zivpn_accounts"
DB_FILE = "/etc/zivpn/user.db"
CONF_FILE = "/etc/zivpn/config.json"


def get_file(path, default="NON_DEFINI"):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return default


def create_zivpn_account(user, password, days, created_by_id=None):
    if not os.path.exists(CONF_FILE):
        return False, "❌ Fichier config ZIVPN introuvable. Le VPS est-il bien configuré ?"

    try:
        with open(DB_FILE, "r", encoding="utf-8") as f:
            content = f.read()
            if user in content or password in content:
                return False, "❌ Nom d'utilisateur ou Mot de passe déjà utilisé."
    except Exception:
        pass

    days = int(days)
    exp_date = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")

    with open(CONF_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()

    new_lines = []
    for line in lines:
        new_lines.append(line)
        if '"config": [' in line:
            new_lines.append(f'      "{password}",\n')

    with open(CONF_FILE, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    with open(CONF_FILE, "r", encoding="utf-8") as f:
        raw = f.read()
    raw = re.sub(r",(\s*\])", r"\1", raw)
    with open(CONF_FILE, "w", encoding="utf-8") as f:
        f.write(raw)

    os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
    with open(DB_FILE, "a", encoding="utf-8") as f:
        f.write(f"{user} {password} {exp_date}\n")

    subprocess.run("systemctl restart zivpn", shell=True, capture_output=True)

    os.makedirs(META_DIR, exist_ok=True)
    with open(f"{META_DIR}/{user}.txt", "w", encoding="utf-8") as f:
        f.write(
            f"username={user}\n"
            f"password={password}\n"
            f"expiry={exp_date}\n"
            f"createdById={created_by_id}\n"
            f"createdAt={datetime.utcnow().isoformat()}Z\n"
            f"protocol=zivpn\n"
            f"status=active\n"
        )

    domain = get_file("/etc/xray/domain", "votre-domaine.com")
    myip = subprocess.getoutput(
        "wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ipv4.icanhazip.com"
    ).strip()

    msg = (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        f"┃ <b>ZIVPN ACCOUNT DETAILS</b>\n"
        f"┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"🔑 <b>Password:</b> <code>{password}</code>\n"
        f"⏳ <b>Expiry Date:</b> {exp_date}\n"
        f"🖥️ <b>IPV4:</b> <code>{myip}</code>\n"
        f"🌐 <b>Domain:</b> <code>{domain}</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    )
    return True, msg


def get_zivpn_usernames():
    if not os.path.exists(META_DIR):
        return []
    return [
        f.replace(".txt", "")
        for f in sorted(os.listdir(META_DIR))
        if f.endswith(".txt")
    ]


def get_zivpn_account_details(user):
    meta_file = f"{META_DIR}/{user}.txt"
    if not os.path.exists(meta_file):
        return False, f"❌ Compte ZIVPN <code>{user}</code> introuvable."
    data = {}
    with open(meta_file, "r", encoding="utf-8") as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                data[k] = v
    domain = get_file("/etc/xray/domain", "votre-domaine.com")
    myip = subprocess.getoutput(
        "wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ipv4.icanhazip.com"
    ).strip()
    msg = (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        f"┃ <b>ZIVPN ACCOUNT DETAILS</b>\n"
        f"┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"🔑 <b>Password:</b> <code>{data.get('password', 'N/A')}</code>\n"
        f"⏳ <b>Expiry Date:</b> {data.get('expiry', 'N/A')}\n"
        f"🖥️ <b>IPV4:</b> <code>{myip}</code>\n"
        f"🌐 <b>Domain:</b> <code>{domain}</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    )
    return True, msg


def renew_zivpn_account(user, days):
    if not os.path.exists(DB_FILE):
        return False, "❌ Base ZIVPN introuvable."

    with open(DB_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()

    current_exp = None
    new_lines = []
    found = False
    days = int(days)
    new_exp = None

    for line in lines:
        parts = line.strip().split()
        if len(parts) >= 3 and parts[0] == user:
            current_exp = parts[2]
            try:
                base_date = datetime.strptime(current_exp, "%Y-%m-%d")
                if base_date < datetime.now():
                    base_date = datetime.now()
            except ValueError:
                base_date = datetime.now()
            new_exp = (base_date + timedelta(days=days)).strftime("%Y-%m-%d")
            new_lines.append(f"{parts[0]} {parts[1]} {new_exp}\n")
            found = True
        else:
            new_lines.append(line)

    if not found:
        return False, f"❌ Utilisateur ZIVPN <code>{user}</code> introuvable."

    with open(DB_FILE, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    meta_file = f"{META_DIR}/{user}.txt"
    if os.path.exists(meta_file):
        with open(meta_file, "r", encoding="utf-8") as f:
            meta_lines = f.readlines()
        with open(meta_file, "w", encoding="utf-8") as f:
            for l in meta_lines:
                f.write(f"expiry={new_exp}\n" if l.startswith("expiry=") else l)

    ok, details = get_zivpn_account_details(user)
    if ok:
        header = (
            f"✅ <b>COMPTE ZIVPN RENOUVELÉ</b>\n"
            f"📅 <b>Ancienne expiration:</b> {current_exp} → <b>{new_exp}</b>\n\n"
        )
        return True, header + details
    return True, (
        f"✅ <b>COMPTE ZIVPN RENOUVELÉ</b>\n\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"📅 <b>Ancienne expiration:</b> {current_exp}\n"
        f"➕ <b>Jours ajoutés:</b> {days}\n"
        f"📅 <b>Nouvelle expiration:</b> {new_exp}\n"
    )


def delete_zivpn_account(user):
    if not os.path.exists(DB_FILE):
        return False, "❌ Base ZIVPN introuvable."

    with open(DB_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()

    password = None
    new_lines = []
    for line in lines:
        parts = line.strip().split()
        if len(parts) >= 2 and parts[0] == user:
            password = parts[1]
        else:
            new_lines.append(line)

    if password is None:
        return False, f"❌ Utilisateur ZIVPN <code>{user}</code> introuvable."

    with open(DB_FILE, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    if os.path.exists(CONF_FILE):
        with open(CONF_FILE, "r", encoding="utf-8") as f:
            content = f.read()
        content = re.sub(rf'[ \t]*"{re.escape(password)}",?\n?', "", content)
        content = re.sub(r",(\s*\])", r"\1", content)
        with open(CONF_FILE, "w", encoding="utf-8") as f:
            f.write(content)

    subprocess.run("systemctl restart zivpn", shell=True, capture_output=True)

    meta_file = f"{META_DIR}/{user}.txt"
    if os.path.exists(meta_file):
        os.remove(meta_file)

    return True, f"🗑️ <b>Compte ZIVPN <code>{user}</code> supprimé avec succès.</b>"


def list_zivpn_accounts():
    if not os.path.exists(DB_FILE):
        return "📋 Aucun compte ZIVPN trouvé."

    with open(DB_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()

    if not lines:
        return "📋 Aucun compte ZIVPN trouvé."

    msg = "📋 <b>LISTE DES COMPTES ZIVPN:</b>\n\n"
    count = 0
    for line in lines:
        parts = line.strip().split()
        if len(parts) >= 3:
            msg += f"👤 <code>{parts[0]}</code> | Pass: <code>{parts[1]}</code> | Exp: <i>{parts[2]}</i>\n"
            count += 1
    msg += f"\n📊 <b>Total:</b> {count} compte(s)"
    return msg
