import base64
import json
import os
import re
import subprocess
import uuid
from datetime import datetime, timedelta

XRAY_CONF = "/etc/xray/config.json"
DB_DIR = "/etc/tom_tunnel_bot/xray_accounts"
WEB_CONFIG = "/etc/nexus-tunnel-web/config.json"
PROTOCOLS = {"vless", "vmess", "trojan", "socks"}

def get_domain():
    try:
        return open("/etc/xray/domain", encoding="utf-8").read().strip()
    except Exception:
        return "votre-domaine.com"

def _valid_user(user):
    return bool(re.fullmatch(r"[A-Za-z0-9._-]{1,32}", user or ""))

def _sync_web(user, protocol, client_id, expiry):
    try:
        port = 2087
        try:
            with open(WEB_CONFIG, encoding="utf-8") as f:
                port = int(json.load(f).get("port", port))
        except Exception:
            pass
        import urllib.request
        data = json.dumps({
            "username": user, "protocol": protocol,
            "password": client_id, "expiry": expiry, "uuid": client_id
        }).encode()
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/clients/sync",
            data=data, method="POST",
            headers={"Content-Type": "application/json"}
        )
        urllib.request.urlopen(req, timeout=2).read()
    except Exception:
        pass

def _links(protocol, user, client_id, domain):
    if protocol == "vless":
        return (
            f"vless://{client_id}@{domain}:443?path=/vless&security=tls&encryption=none&type=ws#{user}",
            f"vless://{client_id}@{domain}:80?path=/vless&encryption=none&type=ws#{user}",
            f"vless://{client_id}@{domain}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc#{user}"
        )
    if protocol == "vmess":
        a = json.dumps({"v":"2","ps":user,"add":domain,"port":"443","id":client_id,"aid":"0","net":"ws","path":"/vmess","type":"none","host":"","tls":"tls"}, separators=(",",":"))
        b = json.dumps({"v":"2","ps":user,"add":domain,"port":"80","id":client_id,"aid":"0","net":"ws","path":"/vmess","type":"none","host":"","tls":"none"}, separators=(",",":"))
        c = json.dumps({"v":"2","ps":user,"add":domain,"port":"443","id":client_id,"aid":"0","net":"grpc","path":"vmess-grpc","type":"none","host":"","tls":"tls"}, separators=(",",":"))
        return tuple("vmess://" + base64.b64encode(x.encode()).decode() for x in (a,b,c))
    if protocol == "trojan":
        return (
            f"trojan://{client_id}@{domain}:443?path=/trws&security=tls&encryption=none&host={domain}&type=ws#{user}",
            f"trojan://{client_id}@{domain}:80?path=/trws&encryption=none&security=none&host={domain}&type=ws#{user}",
            f"trojan://{client_id}@{domain}:443?mode=gun&security=tls&type=grpc&serviceName=trojan-grpc&sni={domain}#{user}"
        )
    if protocol == "socks":
        link = f"socks5://{user}:{client_id}@{domain}:1080"
        return link, link, link
    raise ValueError("Protocole inconnu")

def create_xray_account(protocol, user, days, created_by_id=None):
    protocol = protocol.lower()
    if protocol not in PROTOCOLS:
        return False, "❌ Protocole Xray invalide."
    if not _valid_user(user):
        return False, "❌ Nom d'utilisateur invalide."
    if not os.path.exists(XRAY_CONF):
        return False, "❌ Fichier config Xray introuvable."
    try:
        days = int(days)
        if days <= 0: raise ValueError
    except ValueError:
        return False, "❌ La durée doit être un nombre positif."

    client_id = str(uuid.uuid4())
    expiry = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    lines = open(XRAY_CONF, encoding="utf-8").readlines()
    markers = {
        "vless": ("#vless", "#vlessgrpc"),
        "vmess": ("#vmess", "#vmessgrpc"),
        "trojan": ("#trojanws", "#trojangrpc"),
        "socks": ("#socks",)
    }
    new = []
    injected = False
    for line in lines:
        new.append(line)
        clean = line.strip()
        if clean in markers[protocol]:
            injected = True
            if protocol == "vless":
                new += [f"#& {user} {expiry} {client_id}\n", f'}},{{"id": "{client_id}","email": "{user}"\n']
            elif protocol == "vmess":
                new += [f"### {user} {expiry} {client_id}\n", f'}},{{"id": "{client_id}","alterId": 0,"email": "{user}"\n']
            elif protocol == "trojan":
                new += [f"#! {user} {expiry} {client_id}\n", f'}},{{"password": "{client_id}","email": "{user}"\n']
            else:
                new += [f"## {user} {expiry} {client_id}\n", f'}},{{"user": "{user}","pass": "{client_id}"\n']
            break
    if not injected:
        return False, f"❌ Balise Xray pour {protocol.upper()} introuvable."
    # Keep the remainder of the original config after the marker.
    idx = next(i for i,l in enumerate(lines) if l.strip() in markers[protocol])
    new.extend(lines[idx+1:])
    with open(XRAY_CONF, "w", encoding="utf-8") as f:
        f.writelines(new)
    subprocess.run(["systemctl", "restart", "xray"], capture_output=True)

    os.makedirs(DB_DIR, exist_ok=True)
    with open(f"{DB_DIR}/{protocol}_{user}.txt", "w", encoding="utf-8") as f:
        f.write(
            f"username={user}\nuuid={client_id}\nexpiry={expiry}\n"
            f"createdById={created_by_id}\ncreatedAt={datetime.utcnow().isoformat()}Z\n"
            f"protocol={protocol}\nstatus=active\n"
        )
    _sync_web(user, protocol, client_id, expiry)
    a,b,c = _links(protocol, user, client_id, get_domain())
    return True, (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n┃ <b>{protocol.upper()} ACCOUNT</b>\n┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"⏳ <b>Expiry:</b> <code>{expiry}</code>\n"
        f"🔑 <b>UUID/Pass:</b> <code>{client_id}</code>\n\n"
        f"🔗 <b>TLS:</b>\n<code>{a}</code>\n\n"
        f"🔗 <b>NTLS:</b>\n<code>{b}</code>\n\n"
        f"🔗 <b>GRPC:</b>\n<code>{c}</code>"
    )

def get_xray_usernames(protocol):
    if not os.path.isdir(DB_DIR):
        return []
    prefix = protocol + "_"
    return [f[len(prefix):-4] for f in sorted(os.listdir(DB_DIR)) if f.startswith(prefix) and f.endswith(".txt")]

def get_xray_account_details(protocol, user):
    path = f"{DB_DIR}/{protocol}_{user}.txt"
    if not os.path.exists(path):
        return False, f"❌ Compte {protocol.upper()} <code>{user}</code> introuvable."
    data = {}
    for line in open(path, encoding="utf-8"):
        if "=" in line:
            k,v=line.rstrip().split("=",1); data[k]=v
    a,b,c = _links(protocol, user, data.get("uuid","N/A"), get_domain())
    return True, (
        f"┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n┃ <b>{protocol.upper()} ACCOUNT</b>\n┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"⏳ <b>Expiry:</b> <code>{data.get('expiry','N/A')}</code>\n"
        f"🔑 <b>UUID/Pass:</b> <code>{data.get('uuid','N/A')}</code>\n\n"
        f"🔗 <b>TLS:</b>\n<code>{a}</code>\n\n🔗 <b>NTLS:</b>\n<code>{b}</code>\n\n🔗 <b>GRPC:</b>\n<code>{c}</code>"
    )

def renew_xray_account(protocol, user, days):
    path = f"{DB_DIR}/{protocol}_{user}.txt"
    if not os.path.exists(path):
        return False, f"❌ Compte {protocol.upper()} <code>{user}</code> introuvable."
    try: days=int(days)
    except ValueError: return False, "❌ Durée invalide."
    data = {}
    for line in open(path, encoding="utf-8"):
        if "=" in line:
            k,v=line.rstrip().split("=",1); data[k]=v
    try:
        base=datetime.strptime(data.get("expiry",""),"%Y-%m-%d")
        if base < datetime.now(): base=datetime.now()
    except ValueError:
        base=datetime.now()
    new_exp=(base+timedelta(days=days)).strftime("%Y-%m-%d")
    lines=open(path,encoding="utf-8").readlines()
    with open(path,"w",encoding="utf-8") as f:
        for line in lines:
            f.write(f"expiry={new_exp}\n" if line.startswith("expiry=") else line)
    if os.path.exists(XRAY_CONF):
        content=open(XRAY_CONF,encoding="utf-8").read()
        content=re.sub(
            rf'((?:#[&!]|###+)\s+{re.escape(user)}\s+)\S+(\s)',
            rf'\g<1>{new_exp}\2', content
        )
        open(XRAY_CONF,"w",encoding="utf-8").write(content)
        subprocess.run(["systemctl","restart","xray"],capture_output=True)
    return True, f"✅ <b>COMPTE {protocol.upper()} RENOUVELÉ</b>\n📅 Nouvelle expiration : <code>{new_exp}</code>"

def delete_xray_account(protocol, user):
    if not os.path.exists(XRAY_CONF):
        return False, "❌ Fichier config Xray introuvable."
    content=open(XRAY_CONF,encoding="utf-8").read().splitlines(True)
    new=[]; skip=False; removed=False
    for line in content:
        if re.match(rf'^(?:#[&!]|###+)\s+{re.escape(user)}\s+', line.strip()):
            skip=True; removed=True; continue
        if skip:
            skip=False; continue
        new.append(line)
    if not removed:
        return False, f"❌ Utilisateur <code>{user}</code> introuvable dans Xray."
    open(XRAY_CONF,"w",encoding="utf-8").writelines(new)
    subprocess.run(["systemctl","restart","xray"],capture_output=True)
    path=f"{DB_DIR}/{protocol}_{user}.txt"
    if os.path.exists(path): os.remove(path)
    return True, f"🗑️ <b>Compte {protocol.upper()} <code>{user}</code> supprimé.</b>"

def list_xray_accounts(protocol):
    users=get_xray_usernames(protocol)
    if not users: return f"📋 Aucun compte {protocol.upper()} trouvé."
    return f"📋 <b>LISTE {protocol.upper()}</b>\n\n" + "\n".join(f"👤 <code>{u}</code>" for u in users) + f"\n\n📊 Total: {len(users)}"
