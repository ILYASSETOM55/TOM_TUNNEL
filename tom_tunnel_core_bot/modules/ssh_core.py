import subprocess
import os
from datetime import datetime, timedelta

DB_DIR = "/etc/the_s_bot/ssh_accounts"


def get_file(path, default="NON_DEFINI"):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return default


def _server_info():
    domain = get_file("/etc/xray/domain", "votre-domaine.com")
    pub_key = get_file("/etc/slowdns/server.pub", "PUB_KEY_NOT_FOUND")
    ns_domain = get_file("/etc/slowdns/nsdomain", "NS_DOMAIN_NOT_FOUND")
    myip = subprocess.getoutput(
        "wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ipv4.icanhazip.com || curl -s ifconfig.me"
    ).strip()
    return domain, pub_key, ns_domain, myip


def _format_ssh_details(user, password, exp_date):
    domain, pub_key, ns_domain, myip = _server_info()
    return (
        f"▬▬▬▬▬▬▬▬▬▬MRTOM▬▬▬▬▬▬▬▬▬\n"
        f"┃ <b>SSH ACCOUNT DETAILS</b>\n"
        f"▬▬▬▬▬▬▬▬▬▬MRTOM▬▬▬▬▬▬▬▬▬\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"🔑 <b>Password:</b> <code>{password}</code>\n"
        f"⏳ <b>Expiry Date:</b> {exp_date}\n"
        f"🖥️ <b>Host/IP:</b> <code>{myip}</code>\n"
        f"🌐 <b>Domain:</b> <code>{domain}</code>\n"
        f"🪐 <b>NS Domain:</b> <code>{ns_domain}</code>\n"
        f"▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬\n"
        f"🔌 <b>Ports:</b>\n"
        f"  OpenSSH(22), Dropbear(109,143)\n"
        f"  Stunnel(447,777), WS(80,443)\n"
        f"  UDPGW(7100-7900), Squid(3128,8880)\n"
        f"▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬\n"
        f"🚀 <b>UDP Custom:</b>\n"
        f"<code>{myip}:1-65535@{user}:{password}</code>\n"
        f"▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬\n"
        f"🐌 <b>Slow DNS PUB:</b>\n"
        f"<code>{pub_key}</code>\n"
        f"▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬\n"
        f"⚓ <b>Payload WS:</b>\n"
        f"<code>GET / HTTP/1.1[crlf]Host: {domain}[crlf]Upgrade: websocket[crlf][crlf]</code>\n"
        f"▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬\n"
        f"📥 <b>OpenVPN:</b> https://{domain}:2081\n"
    )


def create_ssh_account(user, password, days, created_by_id=None):
    cmd = (
        f"useradd -e $(date -d '{days} days' +'%Y-%m-%d') -s /bin/false -M {user} "
        f"&& echo '{user}:{password}' | chpasswd"
    )
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    if res.returncode != 0:
        return False, f"❌ Échec de la création:\n<code>{res.stderr}</code>"

    exp_date = (datetime.now() + timedelta(days=int(days))).strftime("%Y-%m-%d")
    os.makedirs(DB_DIR, exist_ok=True)
    with open(f"{DB_DIR}/{user}.txt", "w", encoding="utf-8") as f:
        f.write(
            f"username={user}\n"
            f"password={password}\n"
            f"expiry={exp_date}\n"
            f"createdById={created_by_id}\n"
            f"createdAt={datetime.utcnow().isoformat()}Z\n"
            f"protocol=ssh\n"
            f"status=active\n"
        )
    return True, _format_ssh_details(user, password, exp_date)


def get_ssh_usernames():
    if not os.path.exists(DB_DIR):
        return []
    return [
        f.replace(".txt", "")
        for f in sorted(os.listdir(DB_DIR))
        if f.endswith(".txt")
    ]


def get_ssh_account_details(user):
    db_file = f"{DB_DIR}/{user}.txt"
    if not os.path.exists(db_file):
        return False, f"❌ Compte SSH <code>{user}</code> introuvable."
    data = {}
    with open(db_file, "r", encoding="utf-8") as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                data[k] = v
    return True, _format_ssh_details(
        user, data.get("password", "N/A"), data.get("expiry", "N/A")
    )


def renew_ssh_account(user, days):
    if subprocess.run(f"id {user}", shell=True, capture_output=True).returncode != 0:
        return False, f"❌ Utilisateur <code>{user}</code> introuvable."

    exp_cmd = f"chage -l {user} | grep 'Account expires' | awk -F': ' '{{print $2}}'"
    current_exp = (
        subprocess.run(exp_cmd, shell=True, capture_output=True, text=True)
        .stdout.strip()
    )

    try:
        if current_exp in ("never", "", "password must be changed"):
            old_date = datetime.now()
        else:
            old_date = datetime.strptime(current_exp, "%b %d, %Y")
        new_exp = (old_date + timedelta(days=int(days))).strftime("%Y-%m-%d")
    except ValueError:
        new_exp = (datetime.now() + timedelta(days=int(days))).strftime("%Y-%m-%d")

    subprocess.run(f"usermod -e {new_exp} {user}", shell=True)
    subprocess.run(f"passwd -u {user}", shell=True, capture_output=True)

    db_file = f"{DB_DIR}/{user}.txt"
    if os.path.exists(db_file):
        with open(db_file, "r", encoding="utf-8") as f:
            db_lines = f.readlines()
        with open(db_file, "w", encoding="utf-8") as f:
            for l in db_lines:
                f.write(f"expiry={new_exp}\n" if l.startswith("expiry=") else l)

    ok, details = get_ssh_account_details(user)
    if ok:
        header = (
            f"✅ <b>COMPTE SSH RENOUVELÉ</b>\n"
            f"📅 <b>Ancienne expiration:</b> {current_exp} → <b>{new_exp}</b>\n\n"
        )
        return True, header + details
    return True, (
        f"✅ <b>COMPTE SSH RENOUVELÉ</b>\n\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"📅 <b>Ancienne expiration:</b> {current_exp}\n"
        f"➕ <b>Jours ajoutés:</b> {days}\n"
        f"📅 <b>Nouvelle expiration:</b> {new_exp}\n"
    )


def delete_ssh_account(user):
    if subprocess.run(f"id {user}", shell=True, capture_output=True).returncode != 0:
        return False, f"❌ Utilisateur <code>{user}</code> introuvable."

    subprocess.run(f"pkill -u {user}", shell=True, capture_output=True)
    subprocess.run(f"userdel -r {user}", shell=True, capture_output=True)

    db_file = f"{DB_DIR}/{user}.txt"
    if os.path.exists(db_file):
        os.remove(db_file)

    return True, f"🗑️ <b>Compte SSH <code>{user}</code> supprimé avec succès.</b>"


def lock_ssh_account(user):
    if subprocess.run(f"id {user}", shell=True, capture_output=True).returncode != 0:
        return False, f"❌ Utilisateur <code>{user}</code> introuvable."
    subprocess.run(f"passwd -l {user}", shell=True, capture_output=True)
    return True, f"🔒 <b>Compte <code>{user}</code> verrouillé.</b>"


def unlock_ssh_account(user):
    if subprocess.run(f"id {user}", shell=True, capture_output=True).returncode != 0:
        return False, f"❌ Utilisateur <code>{user}</code> introuvable."
    subprocess.run(f"passwd -u {user}", shell=True, capture_output=True)
    return True, f"🔓 <b>Compte <code>{user}</code> déverrouillé.</b>"


def list_ssh_accounts():
    cmd = "awk -F: '($3 >= 1000 && $1 != \"nobody\") {print $1}' /etc/passwd"
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    users = [u for u in res.stdout.strip().split("\n") if u]
    if not users:
        return "📋 Aucun compte SSH trouvé."

    msg = "📋 <b>LISTE DES COMPTES SSH:</b>\n\n"
    for u in users:
        exp_cmd = f"chage -l {u} | grep 'Account expires' | awk -F': ' '{{print $2}}'"
        exp_date = (
            subprocess.run(exp_cmd, shell=True, capture_output=True, text=True)
            .stdout.strip()
        )
        status_cmd = f"passwd -S {u} | awk '{{print $2}}'"
        status = (
            subprocess.run(status_cmd, shell=True, capture_output=True, text=True)
            .stdout.strip()
        )
        lock_icon = "🔒" if status == "L" else "🔓"
        msg += f"{lock_icon} <code>{u}</code> | Exp: <i>{exp_date}</i>\n"
    msg += f"\n📊 <b>Total:</b> {len(users)} compte(s)"
    return msg
