import subprocess
import json
import uuid
import os
import re
import base64
from datetime import datetime, timedelta

XRAY_CONFIG = "/etc/xray/config.json"

def _get_info():
    domain = subprocess.getoutput("cat /etc/xray/domain 2>/dev/null || echo 'N/A'").strip()
    ip     = subprocess.getoutput("curl -s ifconfig.me").strip()
    return domain, ip

def _user_exists(username):
    content = subprocess.getoutput(f"grep -w '{username}' {XRAY_CONFIG}")
    return bool(content.strip())

def _make_vmess_link(params):
    raw = json.dumps(params, separators=(',', ':'))
    return "vmess://" + base64.b64encode(raw.encode()).decode()

# ══════════════════════════════════════════
#  VMESS
#  Marqueur : ### user expiry uuid
# ══════════════════════════════════════════

def _create_vmess(username, days):
    domain, ip = _get_info()
    new_uuid   = str(uuid.uuid4())
    expiry     = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")

    # Injection exactement comme vmess.sh
    subprocess.run(
        f"sed -i '/#vmess$/a\\### {username} {expiry} {new_uuid}\\n"
        f"}},{{\"id\": \"{new_uuid}\",\"alterId\": 0,\"email\": \"{username}\"' "
        f"{XRAY_CONFIG}",
        shell=True
    )
    subprocess.run(
        f"sed -i '/#vmessgrpc$/a\\### {username} {expiry} {new_uuid}\\n"
        f"}},{{\"id\": \"{new_uuid}\",\"alterId\": 0,\"email\": \"{username}\"' "
        f"{XRAY_CONFIG}",
        shell=True
    )
    subprocess.run("systemctl restart xray 2>/dev/null", shell=True)

    link_tls  = _make_vmess_link({"v":"2","ps":username,"add":domain,"port":"443","id":new_uuid,"aid":"0","net":"ws","path":"/vmess","type":"none","host":"","tls":"tls"})
    link_ntls = _make_vmess_link({"v":"2","ps":username,"add":domain,"port":"80","id":new_uuid,"aid":"0","net":"ws","path":"/vmess","type":"none","host":"","tls":"none"})
    link_grpc = _make_vmess_link({"v":"2","ps":username,"add":domain,"port":"443","id":new_uuid,"aid":"0","net":"grpc","path":"vmess-grpc","type":"none","host":"","tls":"tls"})

    return True, (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        f"┃ Username    : {username}\n"
        f"┃ Expiry Date : {expiry}\n"
        f"┃ UUID        : {new_uuid}\n"
        f"●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●\n"
        f"┃ Domain      : {domain}\n"
        f"┃ Port TLS    : 443\n"
        f"┃ Port NonTLS : 80\n"
        f"┃ Port gRPC   : 443\n"
        f"┃ alterId     : 0\n"
        f"┃ Security    : auto\n"
        f"┃ Network     : ws\n"
        f"┃ Path        : /vmess\n"
        f"●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●\n"
        f"┃ TLS  :\n┃ {link_tls}\n┃\n"
        f"┃ NTLS :\n┃ {link_ntls}\n┃\n"
        f"┃ GRPC :\n┃ {link_grpc}\n"
        f"┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def _renew_vmess(username, days):
    exp = subprocess.getoutput(f"grep -E '^### {username} ' {XRAY_CONFIG} | awk '{{print $3}}' | sort -u").strip()
    uid = subprocess.getoutput(f"grep -E '^### {username} ' {XRAY_CONFIG} | awk '{{print $4}}' | sort -u").strip()
    if not exp:
        return False, f"❌ Utilisateur <code>{username}</code> introuvable."
    now   = datetime.now().strftime("%Y-%m-%d")
    d1    = subprocess.getoutput(f"date -d '{exp}' +%s").strip()
    d2    = subprocess.getoutput(f"date -d '{now}' +%s").strip()
    remaining = (int(d1) - int(d2)) // 86400
    new_days  = remaining + days
    new_exp   = subprocess.getoutput(f"date -d '{new_days} days' +%Y-%m-%d").strip()
    subprocess.run(f"sed -i '/### {username}/c\\### {username} {new_exp} {uid}' {XRAY_CONFIG}", shell=True)
    subprocess.run("systemctl restart xray 2>/dev/null", shell=True)
    return True, (
        f"✅ Compte <code>{username}</code> (VMESS) renouvelé.\n"
        f"📅 Nouvelle expiry : <b>{new_exp}</b>\n"
        f"➕ Jours ajoutés   : <b>{days}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def _delete_vmess(username):
    exp = subprocess.getoutput(f"grep -E '^### {username} ' {XRAY_CONFIG} | awk '{{print $3}}' | sort -u").strip()
    if not exp:
        return False, f"❌ Utilisateur <code>{username}</code> introuvable."
    subprocess.run(f"sed -i '/^### {username} {exp}/,/^}}{{/d' {XRAY_CONFIG}", shell=True)
    subprocess.run("systemctl restart xray 2>/dev/null", shell=True)
    return True, (
        f"✅ Compte <code>{username}</code> (VMESS) supprimé.\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def _list_vmess():
    out = subprocess.getoutput(f"grep -E '^### ' {XRAY_CONFIG} | awk '{{print $2}}' | sort -u")
    return [u for u in out.splitlines() if u]

def _details_vmess(username):
    exp = subprocess.getoutput(f"grep -E '^### {username} ' {XRAY_CONFIG} | awk '{{print $3}}' | sort -u").strip()
    uid = subprocess.getoutput(f"grep -E '^### {username} ' {XRAY_CONFIG} | awk '{{print $4}}' | sort -u").strip()
    if not exp:
        return False, f"❌ Utilisateur <code>{username}</code> introuvable."
    return True, (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        f"┃ Username    : {username}\n"
        f"┃ Expiry Date : {exp}\n"
        f"┃ UUID        : {uid}\n"
        f"┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

# ══════════════════════════════════════════
#  VLESS
#  Marqueur : #& user expiry uuid
# ══════════════════════════════════════════

def _create_vless(username, days):
    domain, ip = _get_info()
    new_uuid   = str(uuid.uuid4())
    expiry     = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")

    subprocess.run(
        f"sed -i '/#vless$/a\\#& {username} {expiry} {new_uuid}\\n"
        f"}},{{\"id\": \"{new_uuid}\",\"email\": \"{username}\"' "
        f"{XRAY_CONFIG}",
        shell=True
    )
    subprocess.run(
        f"sed -i '/#vlessgrpc$/a\\#& {username} {expiry} {new_uuid}\\n"
        f"}},{{\"id\": \"{new_uuid}\",\"email\": \"{username}\"' "
        f"{XRAY_CONFIG}",
        shell=True
    )
    subprocess.run("systemctl restart xray 2>/dev/null", shell=True)

    link_tls  = f"vless://{new_uuid}@{domain}:443?path=/vless&security=tls&encryption=none&type=ws#{username}"
    link_ntls = f"vless://{new_uuid}@{domain}:80?path=/vless&encryption=none&type=ws#{username}"
    link_grpc = f"vless://{new_uuid}@{domain}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc#{username}"

    return True, (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        f"┃ Username    : {username}\n"
        f"┃ Expiry Date : {expiry}\n"
        f"┃ UUID        : {new_uuid}\n"
        f"●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●\n"
        f"┃ Domain      : {domain}\n"
        f"┃ Port TLS    : 443\n"
        f"┃ Port NonTLS : 80\n"
        f"┃ Port gRPC   : 443\n"
        f"┃ Security    : auto\n"
        f"┃ Network     : ws\n"
        f"┃ Path        : /vless\n"
        f"●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●\n"
        f"┃ TLS  :\n┃ {link_tls}\n┃\n"
        f"┃ NTLS :\n┃ {link_ntls}\n┃\n"
        f"┃ GRPC :\n┃ {link_grpc}\n"
        f"┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def _renew_vless(username, days):
    exp = subprocess.getoutput(f"grep -E '^#& {username} ' {XRAY_CONFIG} | awk '{{print $3}}' | sort -u").strip()
    uid = subprocess.getoutput(f"grep -E '^#& {username} ' {XRAY_CONFIG} | awk '{{print $4}}' | sort -u").strip()
    if not exp:
        return False, f"❌ Utilisateur <code>{username}</code> introuvable."
    now       = datetime.now().strftime("%Y-%m-%d")
    d1        = subprocess.getoutput(f"date -d '{exp}' +%s").strip()
    d2        = subprocess.getoutput(f"date -d '{now}' +%s").strip()
    remaining = (int(d1) - int(d2)) // 86400
    new_days  = remaining + days
    new_exp   = subprocess.getoutput(f"date -d '{new_days} days' +%Y-%m-%d").strip()
    subprocess.run(f"sed -i '/^#& {username} /c\\#& {username} {new_exp} {uid}' {XRAY_CONFIG}", shell=True)
    subprocess.run("systemctl restart xray 2>/dev/null", shell=True)
    return True, (
        f"✅ Compte <code>{username}</code> (VLESS) renouvelé.\n"
        f"📅 Nouvelle expiry : <b>{new_exp}</b>\n"
        f"➕ Jours ajoutés   : <b>{days}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def _delete_vless(username):
    exp = subprocess.getoutput(f"grep -E '^#& {username} ' {XRAY_CONFIG} | awk '{{print $3}}' | sort -u").strip()
    if not exp:
        return False, f"❌ Utilisateur <code>{username}</code> introuvable."
    subprocess.run(f"sed -i -e '/^#& {username} /d' -e '/\"email\": \"{username}\"/d' {XRAY_CONFIG}", shell=True)
    subprocess.run("systemctl restart xray 2>/dev/null", shell=True)
    return True, (
        f"✅ Compte <code>{username}</code> (VLESS) supprimé.\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def _list_vless():
    out = subprocess.getoutput(f"grep -E '^#& ' {XRAY_CONFIG} | awk '{{print $2}}' | sort -u")
    return [u for u in out.splitlines() if u]

def _details_vless(username):
    exp = subprocess.getoutput(f"grep -E '^#& {username} ' {XRAY_CONFIG} | awk '{{print $3}}' | sort -u").strip()
    uid = subprocess.getoutput(f"grep -E '^#& {username} ' {XRAY_CONFIG} | awk '{{print $4}}' | sort -u").strip()
    if not exp:
        return False, f"❌ Utilisateur <code>{username}</code> introuvable."
    return True, (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        f"┃ Username    : {username}\n"
        f"┃ Expiry Date : {exp}\n"
        f"┃ UUID        : {uid}\n"
        f"┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

# ══════════════════════════════════════════
#  SOCKS (Shadowsocks)
#  Marqueur : #@ user expiry uuid
# ══════════════════════════════════════════

def _create_socks(username, days):
    domain, ip = _get_info()
    new_uuid   = str(uuid.uuid4())
    expiry     = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    cipher     = "aes-128-gcm"

    subprocess.run(
        f"sed -i '/#ssws$/a\\#@ {username} {expiry} {new_uuid}\\n"
        f"}},{{\"password\": \"{new_uuid}\",\"method\": \"{cipher}\",\"email\": \"{username}\"' "
        f"{XRAY_CONFIG}",
        shell=True
    )
    subprocess.run(
        f"sed -i '/#ssgrpc$/a\\#@ {username} {expiry} {new_uuid}\\n"
        f"}},{{\"password\": \"{new_uuid}\",\"method\": \"{cipher}\",\"email\": \"{username}\"' "
        f"{XRAY_CONFIG}",
        shell=True
    )
    subprocess.run("systemctl restart xray 2>/dev/null", shell=True)

    raw_b64   = base64.b64encode(f"{cipher}:{new_uuid}".encode()).decode()
    link_tls  = f"ss://{raw_b64}@{domain}:443?path=ss-ws&security=tls&host={domain}&type=ws&sni={domain}#{username}"
    link_ntls = f"ss://{raw_b64}@{domain}:80?path=ss-ws&security=none&host={domain}&type=ws#{username}"
    link_grpc = f"ss://{raw_b64}@{domain}:443?mode=gun&security=tls&type=grpc&serviceName=ss-grpc&sni={domain}#{username}"

    return True, (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        f"┃ Username    : {username}\n"
        f"┃ Expiry Date : {expiry}\n"
        f"┃ Password    : {new_uuid}\n"
        f"┃ Cipher      : {cipher}\n"
        f"●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●\n"
        f"┃ Domain      : {domain}\n"
        f"┃ Port TLS    : 443\n"
        f"┃ Port NonTLS : 80\n"
        f"┃ Port gRPC   : 443\n"
        f"┃ Path        : /ss-ws\n"
        f"┃ ServiceName : ss-grpc\n"
        f"●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●\n"
        f"┃ TLS  :\n┃ {link_tls}\n┃\n"
        f"┃ NTLS :\n┃ {link_ntls}\n┃\n"
        f"┃ GRPC :\n┃ {link_grpc}\n"
        f"┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def _renew_socks(username, days):
    exp = subprocess.getoutput(f"grep -E '^#@ {username} ' {XRAY_CONFIG} | awk '{{print $3}}' | sort -u").strip()
    uid = subprocess.getoutput(f"grep -E '^#@ {username} ' {XRAY_CONFIG} | awk '{{print $4}}' | sort -u").strip()
    if not exp:
        return False, f"❌ Utilisateur <code>{username}</code> introuvable."
    now       = datetime.now().strftime("%Y-%m-%d")
    d1        = subprocess.getoutput(f"date -d '{exp}' +%s").strip()
    d2        = subprocess.getoutput(f"date -d '{now}' +%s").strip()
    remaining = (int(d1) - int(d2)) // 86400
    new_days  = remaining + days
    new_exp   = subprocess.getoutput(f"date -d '{new_days} days' +%Y-%m-%d").strip()
    subprocess.run(f"sed -i '/#@ {username}/c\\#@ {username} {new_exp} {uid}' {XRAY_CONFIG}", shell=True)
    subprocess.run("systemctl restart xray 2>/dev/null", shell=True)
    return True, (
        f"✅ Compte <code>{username}</code> (SOCKS) renouvelé.\n"
        f"📅 Nouvelle expiry : <b>{new_exp}</b>\n"
        f"➕ Jours ajoutés   : <b>{days}</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def _delete_socks(username):
    exp = subprocess.getoutput(f"grep -E '^#@ {username} ' {XRAY_CONFIG} | awk '{{print $3}}' | sort -u").strip()
    if not exp:
        return False, f"❌ Utilisateur <code>{username}</code> introuvable."
    subprocess.run(f"sed -i '/^#@ {username} {exp}/,/^}}{{/d' {XRAY_CONFIG}", shell=True)
    subprocess.run("systemctl restart xray 2>/dev/null", shell=True)
    return True, (
        f"✅ Compte <code>{username}</code> (SOCKS) supprimé.\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

def _list_socks():
    out = subprocess.getoutput(f"grep -E '^#@ ' {XRAY_CONFIG} | awk '{{print $2}}' | sort -u")
    return [u for u in out.splitlines() if u]

def _details_socks(username):
    exp = subprocess.getoutput(f"grep -E '^#@ {username} ' {XRAY_CONFIG} | awk '{{print $3}}' | sort -u").strip()
    uid = subprocess.getoutput(f"grep -E '^#@ {username} ' {XRAY_CONFIG} | awk '{{print $4}}' | sort -u").strip()
    if not exp:
        return False, f"❌ Utilisateur <code>{username}</code> introuvable."
    return True, (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        f"┃ Username    : {username}\n"
        f"┃ Expiry Date : {exp}\n"
        f"┃ Password    : {uid}\n"
        f"┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"✅ Développé par 🜲 MR TOM TECH.✅\n"
        f" ━━━━━━━━━━━━━━━━━━━━━━━━"
    )

# ══════════════════════════════════════════
#  TROJAN — à compléter après réception du script
# ══════════════════════════════════════════

def _create_trojan(username, days):
    return False, "❌ Module TROJAN en attente du script source."

def _renew_trojan(username, days):
    return False, "❌ Module TROJAN en attente du script source."

def _delete_trojan(username):
    return False, "❌ Module TROJAN en attente du script source."

def _list_trojan():
    return []

def _details_trojan(username):
    return False, "❌ Module TROJAN en attente du script source."

# ══════════════════════════════════════════
#  FONCTIONS PUBLIQUES
# ══════════════════════════════════════════

def create_xray_account(proto, username, days, created_by_id=None):
    if _user_exists(username):
        return False, f"❌ L'utilisateur <code>{username}</code> existe déjà."
    if proto == "vmess":  return _create_vmess(username, days)
    if proto == "vless":  return _create_vless(username, days)
    if proto == "socks":  return _create_socks(username, days)
    if proto == "trojan": return _create_trojan(username, days)
    return False, f"❌ Protocole <code>{proto}</code> inconnu."

def renew_xray_account(proto, username, days):
    if proto == "vmess":  return _renew_vmess(username, days)
    if proto == "vless":  return _renew_vless(username, days)
    if proto == "socks":  return _renew_socks(username, days)
    if proto == "trojan": return _renew_trojan(username, days)
    return False, f"❌ Protocole <code>{proto}</code> inconnu."

def delete_xray_account(proto, username):
    if proto == "vmess":  return _delete_vmess(username)
    if proto == "vless":  return _delete_vless(username)
    if proto == "socks":  return _delete_socks(username)
    if proto == "trojan": return _delete_trojan(username)
    return False, f"❌ Protocole <code>{proto}</code> inconnu."

def get_xray_usernames(proto):
    if proto == "vmess":  return _list_vmess()
    if proto == "vless":  return _list_vless()
    if proto == "socks":  return _list_socks()
    if proto == "trojan": return _list_trojan()
    return []

def get_xray_account_details(proto, username):
    if proto == "vmess":  return _details_vmess(username)
    if proto == "vless":  return _details_vless(username)
    if proto == "socks":  return _details_socks(username)
    if proto == "trojan": return _details_trojan(username)
    return False, f"❌ Protocole <code>{proto}</code> inconnu."
