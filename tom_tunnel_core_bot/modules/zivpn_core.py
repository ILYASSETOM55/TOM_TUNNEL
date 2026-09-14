import os
import re
import subprocess
from datetime import datetime, timedelta

DB_FILE = "/etc/zivpn/user.db"
CONF_FILE = "/etc/zivpn/config.json"
META_DIR = "/etc/tom_tunnel_bot/zivpn_accounts"

def get_file(path, default="NON_DEFINI"):
    try:
        return open(path, encoding="utf-8").read().strip()
    except Exception:
        return default

def _valid_user(user):
    return bool(re.fullmatch(r"[A-Za-z0-9._-]{1,32}", user or ""))

def create_zivpn_account(user, password, days, created_by_id=None):
    if not _valid_user(user) or not password:
        return False, "❌ Nom d'utilisateur ou mot de passe invalide."
    if not os.path.exists(CONF_FILE):
        return False, "❌ Fichier config ZIVPN introuvable."
    try:
        days=int(days)
        if days <= 0: raise ValueError
    except ValueError:
        return False, "❌ La durée doit être un nombre positif."

    existing=[]
    if os.path.exists(DB_FILE):
        existing=open(DB_FILE,encoding="utf-8").read()
        if user in existing or password in existing:
            return False, "❌ Nom d'utilisateur ou mot de passe déjà utilisé."

    expiry=(datetime.now()+timedelta(days=days)).strftime("%Y-%m-%d")
    with open(CONF_FILE,encoding="utf-8") as f: lines=f.readlines()
    new=[]; inserted=False
    for line in lines:
        new.append(line)
        if '"config": [' in line and not inserted:
            new.append(f'      "{password}",\n')
            inserted=True
    if not inserted:
        return False, '❌ Tableau "config" introuvable dans ZIVPN.'
    raw="".join(new)
    raw=re.sub(r',(\s*\])',r'\1',raw)
    with open(CONF_FILE,"w",encoding="utf-8") as f: f.write(raw)

    os.makedirs(os.path.dirname(DB_FILE),exist_ok=True)
    with open(DB_FILE,"a",encoding="utf-8") as f:
        f.write(f"{user} {password} {expiry}\n")
    os.makedirs(META_DIR,exist_ok=True)
    with open(f"{META_DIR}/{user}.txt","w",encoding="utf-8") as f:
        f.write(
            f"username={user}\npassword={password}\nexpiry={expiry}\n"
            f"createdById={created_by_id}\ncreatedAt={datetime.utcnow().isoformat()}Z\n"
            "protocol=zivpn\nstatus=active\n"
        )
    subprocess.run(["systemctl","restart","zivpn"],capture_output=True)
    domain=get_file("/etc/xray/domain","votre-domaine.com")
    ip=subprocess.getoutput("wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ipv4.icanhazip.com")
    return True, (
        "╭▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╮\n┃ <b>ZIVPN ACCOUNT</b>\n╰▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╯\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"🔑 <b>Password:</b> <code>{password}</code>\n"
        f"⏳ <b>Expiry:</b> <code>{expiry}</code>\n"
        f"🖥️ <b>IPv4:</b> <code>{ip}</code>\n"
        f"🌐 <b>Domain:</b> <code>{domain}</code>"
    )

def get_zivpn_usernames():
    if not os.path.isdir(META_DIR): return []
    return [x[:-4] for x in sorted(os.listdir(META_DIR)) if x.endswith(".txt")]

def get_zivpn_account_details(user):
    path=f"{META_DIR}/{user}.txt"
    if not os.path.exists(path):
        return False, f"❌ Compte ZIVPN <code>{user}</code> introuvable."
    data={}
    for line in open(path,encoding="utf-8"):
        if "=" in line:
            k,v=line.rstrip().split("=",1); data[k]=v
    ip=subprocess.getoutput("wget -qO- ipv4.icanhazip.com 2>/dev/null || curl -s ipv4.icanhazip.com")
    return True, (
        "┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n┃ <b>ZIVPN ACCOUNT</b>\n┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        f"👤 <b>Username:</b> <code>{user}</code>\n"
        f"🔑 <b>Password:</b> <code>{data.get('password','N/A')}</code>\n"
        f"⏳ <b>Expiry:</b> <code>{data.get('expiry','N/A')}</code>\n"
        f"🖥️ <b>IPv4:</b> <code>{ip}</code>"
    )

def renew_zivpn_account(user, days):
    if not os.path.exists(DB_FILE): return False, "❌ Base ZIVPN introuvable."
    try: days=int(days)
    except ValueError: return False, "❌ Durée invalide."
    lines=open(DB_FILE,encoding="utf-8").readlines()
    new=[]; found=False; current=None
    for line in lines:
        p=line.strip().split()
        if len(p)>=3 and p[0]==user:
            found=True; current=p[2]
            try:
                base=datetime.strptime(current,"%Y-%m-%d")
                if base<datetime.now(): base=datetime.now()
            except ValueError: base=datetime.now()
            exp=(base+timedelta(days=days)).strftime("%Y-%m-%d")
            new.append(f"{p[0]} {p[1]} {exp}\n")
        else: new.append(line)
    if not found: return False, f"❌ Utilisateur ZIVPN <code>{user}</code> introuvable."
    open(DB_FILE,"w",encoding="utf-8").writelines(new)
    meta=f"{META_DIR}/{user}.txt"
    if os.path.exists(meta):
        ml=open(meta,encoding="utf-8").readlines()
        with open(meta,"w",encoding="utf-8") as f:
            for line in ml: f.write(f"expiry={exp}\n" if line.startswith("expiry=") else line)
    subprocess.run(["systemctl","restart","zivpn"],capture_output=True)
    return True, f"✅ <b>COMPTE ZIVPN RENOUVELÉ</b>\n📅 Nouvelle expiration : <code>{exp}</code>"

def delete_zivpn_account(user):
    if not os.path.exists(DB_FILE): return False, "❌ Base ZIVPN introuvable."
    lines=open(DB_FILE,encoding="utf-8").readlines()
    new=[]; password=None
    for line in lines:
        p=line.strip().split()
        if len(p)>=2 and p[0]==user: password=p[1]
        else: new.append(line)
    if password is None: return False, f"❌ Utilisateur ZIVPN <code>{user}</code> introuvable."
    open(DB_FILE,"w",encoding="utf-8").writelines(new)
    if os.path.exists(CONF_FILE):
        raw=open(CONF_FILE,encoding="utf-8").read()
        raw=re.sub(rf'[ \t]*"{re.escape(password)}",?\n?', '', raw)
        raw=re.sub(r',(\s*\])',r'\1',raw)
        open(CONF_FILE,"w",encoding="utf-8").write(raw)
    subprocess.run(["systemctl","restart","zivpn"],capture_output=True)
    meta=f"{META_DIR}/{user}.txt"
    if os.path.exists(meta): os.remove(meta)
    return True, f"🗑️ <b>Compte ZIVPN <code>{user}</code> supprimé.</b>"

def list_zivpn_accounts():
    if not os.path.exists(DB_FILE): return "📋 Aucun compte ZIVPN trouvé."
    lines=[x for x in open(DB_FILE,encoding="utf-8").readlines() if x.strip()]
    if not lines: return "📋 Aucun compte ZIVPN trouvé."
    msg="📋 <b>LISTE DES COMPTES ZIVPN:</b>\n\n"
    count=0
    for line in lines:
        p=line.strip().split()
        if len(p)>=3:
            msg+=f"👤 <code>{p[0]}</code> | Exp: <i>{p[2]}</i>\n"; count+=1
    return msg+f"\n📊 <b>Total:</b> {count}"
