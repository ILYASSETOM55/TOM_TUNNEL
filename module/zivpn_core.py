import json
import subprocess
import os
from datetime import datetime, timedelta

ZIVPN_CONFIG = "/etc/zivpn/config.json"
ZIVPN_USERS  = "/etc/zivpn/user.txt"

def _load_users():
    users = {}
    if not os.path.exists(ZIVPN_USERS):
        return users
    with open(ZIVPN_USERS, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) >= 3:
                users[parts[0]] = {"password": parts[1], "expiry": parts[2]}
    return users

def _save_users(users):
    os.makedirs(os.path.dirname(ZIVPN_USERS), exist_ok=True)
    with open(ZIVPN_USERS, 'w') as f:
        for uname, info in users.items():
            f.write(f"{uname} {info['password']} {info['expiry']}\n")
    subprocess.run("systemctl restart zivpn 2>/dev/null || true", shell=True)

def _add_password_to_config(password):
    subprocess.run(
        f"""sed -i '/"config": \\[/a\\        "{password}",' {ZIVPN_CONFIG}""",
        shell=True
    )

def _remove_password_from_config(password):
    subprocess.run(
        f"""sed -i '/"\\"{password}\\""/d' {ZIVPN_CONFIG}""",
        shell=True
    )

def _get_remaining_days(created_by_id):
    """Retourne le nombre de jours restants de l'abonnement du revendeur/admin."""
    try:
        from admin_core import get_user_expiry_days
        return get_user_expiry_days(created_by_id)
    except Exception:
        return 9999  # super admin : pas de limite

def create_zivpn_account(username, password, days, created_by_id=None):
    # Vérification username
    users = _load_users()
    if username in users:
        return False, f"❌ Le nom d'utilisateur <code>{username}</code> existe déjà."

    # Vérification password
    all_passwords = [info['password'] for info in users.values()]
    if password in all_passwords:
        return False, f"❌ Ce mot de passe est déjà utilisé."

    # Vérification jours vs abonnement restant
    if created_by_id:
        remaining = _get_remaining_days(created_by_id)
        if days > remaining:
            return False, (
                f"❌ Vous ne pouvez pas créer un compte pour <b>{days} jours</b>.\n"
                f"Il vous reste <b>{remaining} jours</b> d'abonnement."
            )

    expiry = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    users[username] = {"password": password, "expiry": expiry}
    _save_users(users)
    _add_password_to_config(password)

    ip = subprocess.getoutput("curl -s ifconfig.me").strip()
    domain = subprocess.getoutput("cat /etc/xray/domain 2>/dev/null || echo 'N/A'").strip()

    return True, (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        f"┃      ZIVPN ACCOUNT DETAILS\n"
        f"┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"👤 Username: <code>{username}</code>\n"
        f"🔑 Password: <code>{password}</code>\n"
        f"⏳ Expiry: <code>{expiry}</code>\n"
        f"🖥️ IP: <code>{ip}</code>\n"
        f"🌐 Host: <code>{domain}</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def renew_zivpn_account(username, days, created_by_id=None):
    users = _load_users()
    if username not in users:
        return False, f"❌ Compte <code>{username}</code> introuvable."

    # Vérification jours vs abonnement restant
    if created_by_id:
        remaining = _get_remaining_days(created_by_id)
        if days > remaining:
            return False, (
                f"❌ Renouvellement de <b>{days} jours</b> impossible.\n"
                f"Il vous reste <b>{remaining} jours</b> d'abonnement."
            )

    old_expiry = users[username]["expiry"]
    new_expiry = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    users[username]["expiry"] = new_expiry
    _save_users(users)

    return True, (
        f"✅ Compte <code>{username}</code> renouvelé.\n"
        f"📅 Ancienne expiry : <b>{old_expiry}</b>\n"
        f"📅 Nouvelle expiry : <b>{new_expiry}</b>\n"
        f"➕ Jours ajoutés   : <b>{days}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def delete_zivpn_account(username):
    users = _load_users()
    if username not in users:
        return False, f"❌ Compte <code>{username}</code> introuvable."

    password = users[username]["password"]
    del users[username]
    _save_users(users)
    _remove_password_from_config(password)

    return True, (
        f"✅ Compte <code>{username}</code> supprimé avec succès.\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def get_zivpn_usernames():
    return list(_load_users().keys())

def get_zivpn_account_details(username):
    users = _load_users()
    if username not in users:
        return False, f"❌ Compte <code>{username}</code> introuvable."

    info = users[username]
    ip = subprocess.getoutput("curl -s ifconfig.me").strip()
    domain = subprocess.getoutput("cat /etc/xray/domain 2>/dev/null || echo 'N/A'").strip()

    return True, (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        f"┃      DÉTAILS ZIVPN\n"
        f"┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"👤 Username : <code>{username}</code>\n"
        f"🔑 Password : <code>{info['password']}</code>\n"
        f"📅 Expiry   : <code>{info['expiry']}</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MRTOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
  )
