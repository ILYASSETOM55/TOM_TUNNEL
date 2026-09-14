import json
import os

CONFIG_FILE = "/etc/tom_tunnel_bot/config.json"

def get_config():
    if not os.path.exists(CONFIG_FILE):
        return {}
    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        return json.load(f)

def save_config(cfg):
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    tmp = CONFIG_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    os.replace(tmp, CONFIG_FILE)
    os.chmod(CONFIG_FILE, 0o600)

def list_admins():
    cfg = get_config()
    super_admin = cfg.get("super_admin")
    super_admins = cfg.get("super_admins", [])
    admins = cfg.get("admins", [])
    msg = "👑 <b>SUPER ADMINS :</b>\n"
    if super_admin is not None:
        msg += f"<code>{super_admin}</code>\n"
    for sa in super_admins:
        if sa != super_admin:
            msg += f"<code>{sa}</code>\n"
    msg += "\n👮‍♂️ <b>ADMINISTRATEURS DÉLÉGUÉS :</b>\n"
    if not admins:
        msg += "<i>Aucun administrateur secondaire.</i>"
    else:
        for admin_id in admins:
            msg += f"▪️ <code>{admin_id}</code>\n"
    return msg

def is_super_admin(user_id):
    cfg = get_config()
    return (
        int(user_id) == int(cfg.get("super_admin", -1))
        or int(user_id) in [int(x) for x in cfg.get("super_admins", [])]
    )

def approve_new_admin(admin_id):
    cfg = get_config()
    admin_id = int(admin_id)
    if (
        admin_id == int(cfg.get("super_admin", -1))
        or admin_id in [int(x) for x in cfg.get("super_admins", [])]
        or admin_id in [int(x) for x in cfg.get("admins", [])]
    ):
        return False, "Déjà administrateur."
    cfg.setdefault("admins", []).append(admin_id)
    save_config(cfg)
    return True, "Administrateur approuvé."

def promote_admin_to_supreme(admin_id):
    cfg = get_config()
    admin_id = int(admin_id)
    if admin_id == int(cfg.get("super_admin", -1)) or admin_id in cfg.get("super_admins", []):
        return False, "Déjà Super Admin."
    admins = [int(x) for x in cfg.get("admins", [])]
    if admin_id not in admins:
        return False, "ID introuvable dans la liste des admins."
    admins.remove(admin_id)
    cfg["admins"] = admins
    cfg.setdefault("super_admins", []).append(admin_id)
    save_config(cfg)
    return True, f"Admin <code>{admin_id}</code> promu Super Admin."

def remove_admin(admin_id):
    cfg = get_config()
    admin_id = int(admin_id)
    if admin_id == int(cfg.get("super_admin", -1)):
        return False, "Le Super Admin principal ne peut pas être supprimé."
    admins = [int(x) for x in cfg.get("admins", [])]
    if admin_id not in admins:
        return False, "ID introuvable."
    admins.remove(admin_id)
    cfg["admins"] = admins
    save_config(cfg)
    return True, "Administrateur révoqué."
