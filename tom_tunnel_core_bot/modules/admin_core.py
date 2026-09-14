import json
import os
import tempfile

CONFIG_FILE = "/etc/tom_tunnel_bot/config.json"
LEGACY_CONFIG_FILE = "/etc/nexus_bot/config.json"


def _read(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _normalize(cfg):
    cfg = dict(cfg or {})
    try:
        cfg["super_admin"] = int(cfg["super_admin"])
    except (KeyError, TypeError, ValueError):
        cfg["super_admin"] = None

    admins = []
    for value in cfg.get("admins", []):
        try:
            value = int(value)
        except (TypeError, ValueError):
            continue
        if value not in admins:
            admins.append(value)
    cfg["admins"] = admins

    supers = []
    for value in cfg.get("super_admins", []):
        try:
            value = int(value)
        except (TypeError, ValueError):
            continue
        if value not in supers:
            supers.append(value)
    cfg["super_admins"] = supers
    return cfg


def get_config():
    for path in (CONFIG_FILE, LEGACY_CONFIG_FILE):
        try:
            if os.path.isfile(path):
                return _normalize(_read(path))
        except (OSError, json.JSONDecodeError):
            continue
    return _normalize({})


def save_config(cfg):
    cfg = _normalize(cfg)
    os.makedirs(os.path.dirname(CONFIG_FILE), mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="config.", suffix=".tmp", dir=os.path.dirname(CONFIG_FILE))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, CONFIG_FILE)
    finally:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass


def is_super_admin(user_id):
    cfg = get_config()
    try:
        user_id = int(user_id)
    except (TypeError, ValueError):
        return False
    return user_id == cfg.get("super_admin") or user_id in cfg.get("super_admins", [])


def list_admins():
    cfg = get_config()
    lines = ["👑 <b>SUPER ADMINS :</b>"]
    if cfg.get("super_admin") is not None:
        lines.append(f"<code>{cfg['super_admin']}</code>")
    for sa in cfg.get("super_admins", []):
        if sa != cfg.get("super_admin"):
            lines.append(f"<code>{sa}</code>")
    lines.append("")
    lines.append("👮‍♂️ <b>ADMINISTRATEURS DÉLÉGUÉS :</b>")
    if not cfg.get("admins"):
        lines.append("<i>Aucun administrateur secondaire.</i>")
    else:
        lines.extend(f"▪️ <code>{a}</code>" for a in cfg["admins"])
    return "\n".join(lines)


def approve_new_admin(admin_id):
    try:
        admin_id = int(admin_id)
    except (TypeError, ValueError):
        return False, "ID Telegram invalide."
    cfg = get_config()
    if cfg.get("super_admin") is None:
        return False, "Super Admin non configuré."
    if admin_id == cfg["super_admin"] or admin_id in cfg["super_admins"] or admin_id in cfg["admins"]:
        return False, "Déjà administrateur."
    cfg["admins"].append(admin_id)
    save_config(cfg)
    return True, f"Administrateur <code>{admin_id}</code> ajouté avec succès."


def promote_admin_to_supreme(admin_id):
    try:
        admin_id = int(admin_id)
    except (TypeError, ValueError):
        return False, "ID Telegram invalide."
    cfg = get_config()
    if admin_id == cfg.get("super_admin") or admin_id in cfg.get("super_admins", []):
        return False, "Déjà Super Admin."
    if admin_id not in cfg.get("admins", []):
        return False, "ID introuvable dans la liste des admins."
    cfg["admins"].remove(admin_id)
    cfg.setdefault("super_admins", []).append(admin_id)
    save_config(cfg)
    return True, f"Admin <code>{admin_id}</code> promu Super Admin avec succès."


def remove_admin(admin_id):
    try:
        admin_id = int(admin_id)
    except (TypeError, ValueError):
        return False, "ID Telegram invalide."
    cfg = get_config()
    if admin_id == cfg.get("super_admin"):
        return False, "Le Super Admin principal ne peut pas être supprimé."
    if admin_id in cfg.get("super_admins", []):
        cfg["super_admins"].remove(admin_id)
        save_config(cfg)
        return True, f"Super Admin <code>{admin_id}</code> révoqué."
    if admin_id in cfg.get("admins", []):
        cfg["admins"].remove(admin_id)
        save_config(cfg)
        return True, f"Administrateur <code>{admin_id}</code> révoqué."
    return False, "ID introuvable."
