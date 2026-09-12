import uuid
import base64
import subprocess
from datetime import datetime, timedelta
import os
import re

XRAY_CONF = "/etc/xray/config.json"
DB_DIR = "/etc/the_s_bot/xray_accounts"

# Balises possibles selon les installs courantes
MARKERS = {
    "vless": ["#vless", "#vlessws", "#vlessgrpc", "# vless"],
    "vmess": ["#vmess", "#vmessws", "#vmessgrpc", "# vmess"],
    "trojan": ["#trojanws", "#trojangrpc", "#trojan", "# trojan"],
    "socks": ["#socks", "# socks"],
}


def get_domain():
    try:
        with open("/etc/xray/domain", "r", encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return "votre-domaine.com"


def _build_links(protocol, user, client_id, domain):
    if protocol == "vless":
        link_tls = (
            f"vless://{client_id}@{domain}:443?path=/vless&security=tls"
            f"&encryption=none&type=ws#{user}"
        )
        link_ntls = (
            f"vless://{client_id}@{domain}:80?path=/vless"
            f"&encryption=none&type=ws#{user}"
        )
        link_grpc = (
            f"vless://{client_id}@{domain}:443?mode=gun&security=tls"
            f"&encryption=none&type=grpc&serviceName=vless-grpc#{user}"
        )
    elif protocol == "vmess":
        ws_tls = (
            f'{{"v":"2","ps":"{user}","add":"{domain}","port":"443","id":"{client_id}",'
            f'"aid":"0","net":"ws","path":"/vmess","type":"none","host":"","tls":"tls"}}'
        )
        ws_ntls = (
            f'{{"v":"2","ps":"{user}","add":"{domain}","port":"80","id":"{client_id}",'
            f'"aid":"0","net":"ws","path":"/vmess","type":"none","host":"","tls":"none"}}'
        )
        grpc = (
            f'{{"v":"2","ps":"{user}","add":"{domain}","port":"443","id":"{client_id}",'
            f'"aid":"0","net":"grpc","path":"vmess-grpc","type":"none","host":"","tls":"tls"}}'
        )
        link_tls = "vmess://" + base64.b64encode(ws_tls.encode()).decode()
        link_ntls = "vmess://" + base64.b64encode(ws_ntls.encode()).decode()
        link_grpc = "vmess://" + base64.b64encode(grpc.encode()).decode()
    elif protocol == "trojan":
        link_tls = (
            f"trojan://{client_id}@{domain}:443?path=/trws&security=tls"
            f"&encryption=none&host={domain}&type=ws#{user}"
        )
        link_ntls = (
            f"trojan://{client_id}@{domain}:80?path=/trws"
            f"&encryption=none&security=none&host={domain}&type=ws#{user}"
        )
        link_grpc = (
            f"trojan://{client_id}@{domain}:443?mode=gun&security=tls"
            f"&type=grpc&serviceName=trojan-grpc&sni={domain}#{user}"
        )
    else:  # socks
        link_tls = f"socks5://{user}:{client_id}@{domain}:1080"
        link_ntls = link_tls
        link_grpc = link_tls
    return link_tls, link_ntls, link_grpc


def _format_details(protocol, user, client_id, exp_date, domain):
    link_tls, link_ntls, link_grpc = _build_links(protocol, user, client_id, domain)
    return (
        f"▬▬▬▬▬▬▬▬▬▬MRTOM▬▬▬▬▬▬▬▬▬\n"
        f"┃ <b>{protocol.upper()} ACCOUNT DETAILS</b>\n"
        f"▬▬▬▬▬▬▬▬▬▬MRTOM▬▬▬▬▬▬▬▬▬\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"⏳ <b>Expired:</b> <code>{exp_date}</code>\n"
        f"🔑 <b>UUID/Pass:</b> <code>{client_id}</code>\n"
        f"🌐 <b>Domain:</b> <code>{domain}</code>\n"
        f"▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬\n"
        f"🔗 <b>TLS (443):</b>\n<code>{link_tls}</code>\n\n"
        f"🔗 <b>NTLS (80):</b>\n<code>{link_ntls}</code>\n\n"
        f"🔗 <b>GRPC (443):</b>\n<code>{link_grpc}</code>\n"
        f"▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬"
    )


def create_xray_account(protocol, user, days, created_by_id=None):
    if not os.path.exists(XRAY_CONF):
        return False, "❌ Fichier config Xray introuvable (/etc/xray/config.json)."

    days = int(days)
    exp_date = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    client_id = str(uuid.uuid4())
    domain = get_domain()

    with open(XRAY_CONF, "r", encoding="utf-8") as f:
        content = f.read()

    tag_map = {
        "vless": (
            f'#& {user} {exp_date} {client_id}\n'
            f'}},{{"id": "{client_id}","email": "{user}"\n'
        ),
        "vmess": (
            f'### {user} {exp_date} {client_id}\n'
            f'}},{{"id": "{client_id}","alterId": 0,"email": "{user}"\n'
        ),
        "trojan": (
            f'#! {user} {exp_date} {client_id}\n'
            f'}},{{"password": "{client_id}","email": "{user}"\n'
        ),
        "socks": (
            f'## {user} {exp_date} {client_id}\n'
            f'}},{{"user": "{user}","pass": "{client_id}"\n'
        ),
    }

    injected = False
    for marker in MARKERS.get(protocol, []):
        if marker in content:
            content = content.replace(marker, marker + "\n" + tag_map[protocol], 1)
            injected = True
            break

    if not injected:
        return False, (
            f"❌ Aucune balise trouvée pour {protocol.upper()}.\n"
            f"Balises attendues : {', '.join(MARKERS.get(protocol, []))}\n"
            f"Vérifie /etc/xray/config.json"
        )

    with open(XRAY_CONF, "w", encoding="utf-8") as f:
        f.write(content)

    subprocess.run("systemctl restart xray", shell=True, capture_output=True)

    os.makedirs(DB_DIR, exist_ok=True)
    with open(f"{DB_DIR}/{protocol}_{user}.txt", "w", encoding="utf-8") as f:
        f.write(
            f"username={user}\n"
            f"uuid={client_id}\n"
            f"expiry={exp_date}\n"
            f"createdById={created_by_id}\n"
            f"createdAt={datetime.utcnow().isoformat()}Z\n"
            f"protocol={protocol}\n"
            f"status=active\n"
        )

    return True, _format_details(protocol, user, client_id, exp_date, domain)


def get_xray_usernames(protocol):
    if not os.path.exists(DB_DIR):
        return []
    prefix = f"{protocol}_"
    return [
        f[len(prefix) :].replace(".txt", "")
        for f in sorted(os.listdir(DB_DIR))
        if f.startswith(prefix) and f.endswith(".txt")
    ]


def get_xray_account_details(protocol, user):
    db_file = f"{DB_DIR}/{protocol}_{user}.txt"
    if not os.path.exists(db_file):
        return False, f"❌ Compte {protocol.upper()} <code>{user}</code> introuvable."
    data = {}
    with open(db_file, "r", encoding="utf-8") as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                data[k] = v
    return True, _format_details(
        protocol,
        user,
        data.get("uuid", "N/A"),
        data.get("expiry", "N/A"),
        get_domain(),
    )


def renew_xray_account(protocol, user, days):
    db_file = f"{DB_DIR}/{protocol}_{user}.txt"
    if not os.path.exists(db_file):
        return False, f"❌ Compte {protocol.upper()} <code>{user}</code> introuvable."

    days = int(days)
    current_exp = None
    lines_db = []
    with open(db_file, "r", encoding="utf-8") as f:
        lines_db = f.readlines()
    for l in lines_db:
        if l.startswith("expiry="):
            current_exp = l.split("=", 1)[1].strip()
            break

    try:
        base_date = (
            datetime.strptime(current_exp, "%Y-%m-%d") if current_exp else datetime.now()
        )
        if base_date < datetime.now():
            base_date = datetime.now()
    except (ValueError, TypeError):
        base_date = datetime.now()

    new_exp = (base_date + timedelta(days=days)).strftime("%Y-%m-%d")

    if os.path.exists(XRAY_CONF):
        with open(XRAY_CONF, "r", encoding="utf-8") as f:
            content = f.read()
        content = re.sub(
            rf"((?:#[&!]|###+)\s+{re.escape(user)}\s+)\S+(\s)",
            rf"\g<1>{new_exp}\2",
            content,
        )
        with open(XRAY_CONF, "w", encoding="utf-8") as f:
            f.write(content)
        subprocess.run("systemctl restart xray", shell=True, capture_output=True)

    new_db_lines = []
    for l in lines_db:
        if l.startswith("expiry="):
            new_db_lines.append(f"expiry={new_exp}\n")
        else:
            new_db_lines.append(l)
    with open(db_file, "w", encoding="utf-8") as f:
        f.writelines(new_db_lines)

    ok, details = get_xray_account_details(protocol, user)
    if ok:
        header = (
            f"✅ <b>COMPTE {protocol.upper()} RENOUVELÉ</b>\n"
            f"📅 <b>Ancienne expiration:</b> {current_exp} → <b>{new_exp}</b>\n\n"
        )
        return True, header + details
    return True, (
        f"✅ <b>COMPTE {protocol.upper()} RENOUVELÉ</b>\n\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"📅 <b>Ancienne expiration:</b> {current_exp}\n"
        f"➕ <b>Jours ajoutés:</b> {days}\n"
        f"📅 <b>Nouvelle expiration:</b> {new_exp}\n"
    )


def delete_xray_account(protocol, user):
    if not os.path.exists(XRAY_CONF):
        return False, "❌ Fichier config Xray introuvable."

    with open(XRAY_CONF, "r", encoding="utf-8") as f:
        lines = f.readlines()

    new_lines = []
    skip_next = False
    removed = False
    for line in lines:
        clean = line.strip()
        if re.match(rf"^(?:#[&!]|###+)\s+{re.escape(user)}\s+", clean):
            skip_next = True
            removed = True
            continue
        if skip_next:
            skip_next = False
            continue
        new_lines.append(line)

    if not removed:
        return False, f"❌ Utilisateur <code>{user}</code> introuvable dans la config {protocol.upper()}."

    with open(XRAY_CONF, "w", encoding="utf-8") as f:
        f.writelines(new_lines)
    subprocess.run("systemctl restart xray", shell=True, capture_output=True)

    db_file = f"{DB_DIR}/{protocol}_{user}.txt"
    if os.path.exists(db_file):
        os.remove(db_file)

    return True, f"🗑️ <b>Compte {protocol.upper()} <code>{user}</code> supprimé avec succès.</b>"


def list_xray_accounts(protocol):
    if not os.path.exists(DB_DIR):
        return f"📋 Aucun compte {protocol.upper()} trouvé."

    entries = [f for f in os.listdir(DB_DIR) if f.startswith(f"{protocol}_")]
    if not entries:
        return f"📋 Aucun compte {protocol.upper()} trouvé."

    msg = f"📋 <b>LISTE DES COMPTES {protocol.upper()}:</b>\n\n"
    for e in sorted(entries):
        user = e[len(protocol) + 1 :].replace(".txt", "")
        expiry = "N/A"
        try:
            with open(f"{DB_DIR}/{e}", encoding="utf-8") as f:
                for l in f:
                    if l.startswith("expiry="):
                        expiry = l.split("=", 1)[1].strip()
        except Exception:
            pass
        msg += f"👤 <code>{user}</code> | Exp: <i>{expiry}</i>\n"
    msg += f"\n📊 <b>Total:</b> {len(entries)} compte(s)"
    return msg
