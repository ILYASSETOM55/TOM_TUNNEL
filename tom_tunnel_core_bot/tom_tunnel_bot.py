import html
import json
import logging
import os
import subprocess

import telebot
from telebot.types import InlineKeyboardButton, InlineKeyboardMarkup

from modules import admin_core, ssh_core, system_core, xray_core, zivpn_core

CONFIG_FILE = "/etc/tom_tunnel_bot/config.json"
MENU_IMAGE_URL = "https://github.com/user-attachments/assets/3283223c-3cef-4f66-89b8-c061027fb12e"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("TOM_TUNNEL_BOT")


def load_config():
    try:
        with open(CONFIG_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


config = load_config()
if not config.get("bot_token") or config.get("super_admin") is None:
    raise SystemExit("Configuration Telegram absente ou invalide : /etc/tom_tunnel_bot/config.json")

bot = telebot.TeleBot(config["bot_token"], parse_mode=None)


def is_admin(user_id):
    cfg = admin_core.get_config()
    try:
        uid = int(user_id)
    except (TypeError, ValueError):
        return False
    return uid == cfg.get("super_admin") or uid in cfg.get("admins", []) or uid in cfg.get("super_admins", [])


def _safe(v):
    return html.escape(str(v or ""), quote=False)


def home_markup():
    m = InlineKeyboardMarkup(row_width=2)
    for label, data in [
        ("📡 SSH/WS", "menu_ssh"), ("🛡️ VMESS", "menu_vmess"),
        ("🛡️ VLESS", "menu_vless"), ("🔥 TROJAN", "menu_trojan"),
        ("🔌 SOCKS", "menu_socks"), ("📱 ZIVPN", "menu_zivpn"),
        ("📊 VPS STATUS", "menu_status"), ("🧹 CLEAN LOGS", "menu_log"),
        ("👑 ADMINS", "menu_admins"), ("🔄 REBOOT VPS", "action_reboot")
    ]:
        m.add(InlineKeyboardButton(label, callback_data=data))
    return m


def protocol_markup(proto):
    m = InlineKeyboardMarkup(row_width=1)
    m.add(
        InlineKeyboardButton(f"➕ Créer {proto.upper()}", callback_data=f"add_{proto}"),
        InlineKeyboardButton(f"🔄 Renouveler {proto.upper()}", callback_data=f"renew_{proto}"),
        InlineKeyboardButton(f"🗑️ Supprimer {proto.upper()}", callback_data=f"del_{proto}"),
        InlineKeyboardButton(f"📋 Liste {proto.upper()}", callback_data=f"list_{proto}"),
    )
    if proto == "ssh":
        m.add(InlineKeyboardButton("🔒 Verrouiller", callback_data="lock_ssh"))
        m.add(InlineKeyboardButton("🔓 Déverrouiller", callback_data="unlock_ssh"))
    m.add(InlineKeyboardButton("🔙 Accueil", callback_data="action_home"))
    return m


def _answer(call, text=None):
    try:
        bot.answer_callback_query(call.id, text or "")
    except Exception:
        pass


def _show(call, text, markup):
    _answer(call)
    try:
        if call.message.content_type == "photo":
            bot.delete_message(call.message.chat.id, call.message.message_id)
            bot.send_message(call.message.chat.id, text, parse_mode="HTML", reply_markup=markup)
        else:
            bot.edit_message_text(text, call.message.chat.id, call.message.message_id, parse_mode="HTML", reply_markup=markup)
    except Exception:
        bot.send_message(call.message.chat.id, text, parse_mode="HTML", reply_markup=markup)


def _send_home(chat_id):
    caption = "<b>💻 TOM_TUNNEL SERVER</b>\nSélectionnez un module :"
    try:
        bot.send_photo(chat_id, MENU_IMAGE_URL, caption=caption, parse_mode="HTML", reply_markup=home_markup())
    except Exception:
        bot.send_message(chat_id, caption, parse_mode="HTML", reply_markup=home_markup())


def _ask(chat_id, prompt, handler, *args):
    msg = bot.send_message(chat_id, prompt, parse_mode="HTML")
    bot.register_next_step_handler(msg, handler, *args)


def _result(message, result):
    try:
        ok, text = result
    except Exception as exc:
        text = f"❌ Erreur interne : <code>{_safe(exc)}</code>"
    bot.send_message(message.chat.id, str(text), parse_mode="HTML", reply_markup=home_markup())


@bot.message_handler(commands=["start"])
def start(message):
    if not is_admin(message.from_user.id):
        bot.reply_to(message, "⛔ Accès refusé.")
        return
    _send_home(message.chat.id)


@bot.callback_query_handler(func=lambda c: c.data == "action_home")
def home(c):
    if not is_admin(c.from_user.id): return
    _answer(c)
    try: bot.delete_message(c.message.chat.id, c.message.message_id)
    except Exception: pass
    _send_home(c.message.chat.id)


@bot.callback_query_handler(func=lambda c: c.data in {"menu_ssh", "menu_vmess", "menu_vless", "menu_trojan", "menu_socks", "menu_zivpn"})
def protocol_menu(c):
    if not is_admin(c.from_user.id): return
    _answer(c, "📡 Ouverture...")
    proto = c.data.split("_", 1)[1]
    _show(c, f"<b>📡 MODULE {proto.upper()}</b>\n\nChoisissez une action :", protocol_markup(proto))


# SSH
@bot.callback_query_handler(func=lambda c: c.data == "add_ssh")
def add_ssh(c):
    if not is_admin(c.from_user.id): return
    _answer(c)
    _ask(c.message.chat.id, "👤 <b>Nom d'utilisateur SSH :</b>", _ssh_user, c.from_user.id)


def _ssh_user(m, creator):
    text = (m.text or "").strip()
    if not text:
        bot.send_message(m.chat.id, "❌ Nom vide.", reply_markup=home_markup()); return
    _ask(m.chat.id, "🔑 <b>Mot de passe SSH :</b>", _ssh_pass, text, creator)


def _ssh_pass(m, user, creator):
    password = m.text or ""
    _ask(m.chat.id, "⏳ <b>Durée en jours :</b>", _ssh_days, user, password, creator)


def _ssh_days(m, user, password, creator):
    _result(m, ssh_core.create_ssh_account(user, password, (m.text or "").strip(), creator))


@bot.callback_query_handler(func=lambda c: c.data == "renew_ssh")
def renew_ssh(c):
    if not is_admin(c.from_user.id): return
    _answer(c)
    _ask(c.message.chat.id, "👤 <b>Utilisateur SSH :</b>", _ssh_renew_user)


def _ssh_renew_user(m):
    _ask(m.chat.id, "⏳ <b>Jours à ajouter :</b>", _ssh_renew_days, (m.text or "").strip())


def _ssh_renew_days(m, user):
    _result(m, ssh_core.renew_ssh_account(user, (m.text or "").strip()))


@bot.callback_query_handler(func=lambda c: c.data == "del_ssh")
def del_ssh(c):
    if not is_admin(c.from_user.id): return
    _answer(c)
    _ask(c.message.chat.id, "👤 <b>Utilisateur SSH à supprimer :</b>", _ssh_delete)


def _ssh_delete(m):
    _result(m, ssh_core.delete_ssh_account((m.text or "").strip()))


@bot.callback_query_handler(func=lambda c: c.data in {"lock_ssh", "unlock_ssh"})
def lock_ssh(c):
    if not is_admin(c.from_user.id): return
    _answer(c)
    _ask(c.message.chat.id, "👤 <b>Utilisateur SSH :</b>", _ssh_lock, c.data)


def _ssh_lock(m, action):
    user = (m.text or "").strip()
    result = ssh_core.lock_ssh_account(user) if action == "lock_ssh" else ssh_core.unlock_ssh_account(user)
    _result(m, result)


@bot.callback_query_handler(func=lambda c: c.data == "list_ssh")
def list_ssh(c):
    if not is_admin(c.from_user.id): return
    users = ssh_core.get_ssh_usernames()
    m = InlineKeyboardMarkup(row_width=1)
    for user in users:
        m.add(InlineKeyboardButton(f"👤 {user}", callback_data=f"view_ssh_{user}"))
    m.add(InlineKeyboardButton("🔙 Accueil", callback_data="action_home"))
    _show(c, "📋 <b>COMPTES SSH</b>\nSélectionnez un compte :" if users else "📋 Aucun compte SSH trouvé.", m)


@bot.callback_query_handler(func=lambda c: c.data.startswith("view_ssh_"))
def view_ssh(c):
    if not is_admin(c.from_user.id): return
    user = c.data[len("view_ssh_"):]
    ok, text = ssh_core.get_ssh_account_details(user)
    m = InlineKeyboardMarkup(row_width=1)
    m.add(InlineKeyboardButton("🔙 Liste", callback_data="list_ssh"), InlineKeyboardButton("🏠 Accueil", callback_data="action_home"))
    _show(c, text, m)


# Xray
XRAY_PROTOCOLS = {"vless", "vmess", "trojan", "socks"}


def _proto_from_callback(c):
    return c.data.split("_", 1)[1]


@bot.callback_query_handler(func=lambda c: c.data in {"add_vless", "add_vmess", "add_trojan", "add_socks"})
def add_xray(c):
    if not is_admin(c.from_user.id): return
    proto = _proto_from_callback(c); _answer(c)
    _ask(c.message.chat.id, f"👤 <b>Nom d'utilisateur {proto.upper()} :</b>", _xray_user, proto, c.from_user.id)


def _xray_user(m, proto, creator):
    _ask(m.chat.id, "⏳ <b>Durée en jours :</b>", _xray_days, (m.text or "").strip(), proto, creator)


def _xray_days(m, user, proto, creator):
    _result(m, xray_core.create_xray_account(proto, user, (m.text or "").strip(), creator))


@bot.callback_query_handler(func=lambda c: c.data in {"renew_vless", "renew_vmess", "renew_trojan", "renew_socks"})
def renew_xray(c):
    if not is_admin(c.from_user.id): return
    proto = _proto_from_callback(c); _answer(c)
    _ask(c.message.chat.id, f"👤 <b>Utilisateur {proto.upper()} :</b>", _xray_renew_user, proto)


def _xray_renew_user(m, proto):
    _ask(m.chat.id, "⏳ <b>Jours à ajouter :</b>", _xray_renew_days, proto, (m.text or "").strip())


def _xray_renew_days(m, proto, user):
    _result(m, xray_core.renew_xray_account(proto, user, (m.text or "").strip()))


@bot.callback_query_handler(func=lambda c: c.data in {"del_vless", "del_vmess", "del_trojan", "del_socks"})
def del_xray(c):
    if not is_admin(c.from_user.id): return
    proto = _proto_from_callback(c); _answer(c)
    _ask(c.message.chat.id, f"👤 <b>Utilisateur {proto.upper()} à supprimer :</b>", _xray_delete, proto)


def _xray_delete(m, proto):
    _result(m, xray_core.delete_xray_account(proto, (m.text or "").strip()))


@bot.callback_query_handler(func=lambda c: c.data in {"list_vless", "list_vmess", "list_trojan", "list_socks"})
def list_xray(c):
    if not is_admin(c.from_user.id): return
    proto = _proto_from_callback(c); users = xray_core.get_xray_usernames(proto)
    m = InlineKeyboardMarkup(row_width=1)
    for user in users: m.add(InlineKeyboardButton(f"👤 {user}", callback_data=f"view_{proto}_{user}"))
    m.add(InlineKeyboardButton("🔙 Accueil", callback_data="action_home"))
    _show(c, f"📋 <b>COMPTES {proto.upper()}</b>\nSélectionnez un compte :" if users else f"📋 Aucun compte {proto.upper()} trouvé.", m)


@bot.callback_query_handler(func=lambda c: any(c.data.startswith(f"view_{p}_") for p in XRAY_PROTOCOLS))
def view_xray(c):
    if not is_admin(c.from_user.id): return
    _, proto, user = c.data.split("_", 2)
    ok, text = xray_core.get_xray_account_details(proto, user)
    m = InlineKeyboardMarkup(row_width=1)
    m.add(InlineKeyboardButton("🔙 Liste", callback_data=f"list_{proto}"), InlineKeyboardButton("🏠 Accueil", callback_data="action_home"))
    _show(c, text, m)


# ZIVPN
@bot.callback_query_handler(func=lambda c: c.data == "add_zivpn")
def add_zivpn(c):
    if not is_admin(c.from_user.id): return
    _answer(c); _ask(c.message.chat.id, "👤 <b>Nom d'utilisateur ZIVPN :</b>", _z_user, c.from_user.id)


def _z_user(m, creator): _ask(m.chat.id, "🔑 <b>Mot de passe ZIVPN :</b>", _z_pass, (m.text or "").strip(), creator)

def _z_pass(m, user, creator): _ask(m.chat.id, "⏳ <b>Durée en jours :</b>", _z_days, user, m.text or "", creator)
def _z_days(m, user, password, creator): _result(m, zivpn_core.create_zivpn_account(user, password, (m.text or "").strip(), creator))


@bot.callback_query_handler(func=lambda c: c.data == "renew_zivpn")
def renew_zivpn(c):
    if not is_admin(c.from_user.id): return
    _answer(c); _ask(c.message.chat.id, "👤 <b>Utilisateur ZIVPN :</b>", _z_renew_user)

def _z_renew_user(m): _ask(m.chat.id, "⏳ <b>Jours à ajouter :</b>", _z_renew_days, (m.text or "").strip())
def _z_renew_days(m, user): _result(m, zivpn_core.renew_zivpn_account(user, (m.text or "").strip()))


@bot.callback_query_handler(func=lambda c: c.data == "del_zivpn")
def del_zivpn(c):
    if not is_admin(c.from_user.id): return
    _answer(c); _ask(c.message.chat.id, "👤 <b>Utilisateur ZIVPN à supprimer :</b>", _z_delete)
def _z_delete(m): _result(m, zivpn_core.delete_zivpn_account((m.text or "").strip()))


@bot.callback_query_handler(func=lambda c: c.data == "list_zivpn")
def list_zivpn(c):
    if not is_admin(c.from_user.id): return
    users = zivpn_core.get_zivpn_usernames(); m = InlineKeyboardMarkup(row_width=1)
    for user in users: m.add(InlineKeyboardButton(f"👤 {user}", callback_data=f"view_zivpn_{user}"))
    m.add(InlineKeyboardButton("🔙 Accueil", callback_data="action_home"))
    _show(c, "📋 <b>COMPTES ZIVPN</b>\nSélectionnez un compte :" if users else "📋 Aucun compte ZIVPN trouvé.", m)


@bot.callback_query_handler(func=lambda c: c.data.startswith("view_zivpn_"))
def view_zivpn(c):
    if not is_admin(c.from_user.id): return
    user = c.data[len("view_zivpn_"):]; ok, text = zivpn_core.get_zivpn_account_details(user)
    m = InlineKeyboardMarkup(row_width=1); m.add(InlineKeyboardButton("🔙 Liste", callback_data="list_zivpn"), InlineKeyboardButton("🏠 Accueil", callback_data="action_home"))
    _show(c, text, m)


# System
@bot.callback_query_handler(func=lambda c: c.data == "menu_status")
def status(c):
    if not is_admin(c.from_user.id): return
    m=InlineKeyboardMarkup(); m.add(InlineKeyboardButton("🔙 Accueil", callback_data="action_home")); _show(c, system_core.get_vps_status(), m)

@bot.callback_query_handler(func=lambda c: c.data == "menu_log")
def logs(c):
    if not is_admin(c.from_user.id): return
    m=InlineKeyboardMarkup(); m.add(InlineKeyboardButton("🔙 Accueil", callback_data="action_home")); _show(c, system_core.clean_system_logs(), m)

@bot.callback_query_handler(func=lambda c: c.data == "action_reboot")
def reboot(c):
    if not admin_core.is_super_admin(c.from_user.id): _answer(c, "⛔ Super Admin uniquement."); return
    _answer(c, "♻️ Reboot..."); bot.send_message(c.message.chat.id, "♻️ <b>Reboot VPS lancé.</b>", parse_mode="HTML")
    subprocess.Popen(["systemctl", "reboot"])


# Admins
@bot.callback_query_handler(func=lambda c: c.data == "menu_admins")
def admins(c):
    if not is_admin(c.from_user.id): return
    m=InlineKeyboardMarkup(row_width=1); m.add(InlineKeyboardButton("📋 Liste", callback_data="list_admins"))
    if admin_core.is_super_admin(c.from_user.id):
        m.add(InlineKeyboardButton("➕ Ajouter", callback_data="req_add_admin"), InlineKeyboardButton("👑 Promouvoir", callback_data="req_promote_admin"), InlineKeyboardButton("❌ Supprimer", callback_data="req_del_admin"))
    m.add(InlineKeyboardButton("🔙 Accueil", callback_data="action_home")); _show(c, admin_core.list_admins(), m)

@bot.callback_query_handler(func=lambda c: c.data == "list_admins")
def list_admins(c):
    if not is_admin(c.from_user.id): return
    m=InlineKeyboardMarkup(); m.add(InlineKeyboardButton("🔙 Admins", callback_data="menu_admins")); _show(c, admin_core.list_admins(), m)


def _admin_id_prompt(c, prompt, handler):
    if not is_admin(c.from_user.id): return
    _answer(c); _ask(c.message.chat.id, prompt, handler, c.from_user.id)

@bot.callback_query_handler(func=lambda c: c.data == "req_add_admin")
def req_add_admin(c): _admin_id_prompt(c, "👤 <b>ID Telegram du nouvel admin :</b>", _process_add_admin)

def _process_add_admin(m, requester):
    target=(m.text or "").strip()
    if not target.isdigit(): bot.send_message(m.chat.id,"❌ ID invalide.",reply_markup=home_markup()); return
    if admin_core.is_super_admin(requester): _result(m, admin_core.approve_new_admin(int(target))); return
    cfg=admin_core.get_config(); super_id=cfg.get("super_admin")
    markup=InlineKeyboardMarkup(row_width=2); markup.add(InlineKeyboardButton("✅ Approuver",callback_data=f"adm:add:{target}:{requester}"),InlineKeyboardButton("❌ Refuser",callback_data=f"adm:cancel:{target}:{requester}"))
    bot.send_message(m.chat.id,"⏳ Demande envoyée au Super Admin.",reply_markup=home_markup())
    bot.send_message(super_id,f"⚠️ <b>DEMANDE ADMIN</b>\n\nAdmin <code>{requester}</code> demande l'ajout de <code>{target}</code>.",parse_mode="HTML",reply_markup=markup)

@bot.callback_query_handler(func=lambda c: c.data == "req_del_admin")
def req_del_admin(c): _admin_id_prompt(c,"👤 <b>ID Telegram à révoquer :</b>",_process_del_admin)

def _process_del_admin(m, requester):
    target=(m.text or "").strip()
    if not target.isdigit(): bot.send_message(m.chat.id,"❌ ID invalide.",reply_markup=home_markup()); return
    if admin_core.is_super_admin(requester): _result(m, admin_core.remove_admin(int(target))); return
    super_id=admin_core.get_config().get("super_admin"); markup=InlineKeyboardMarkup(row_width=2); markup.add(InlineKeyboardButton("✅ Révoquer",callback_data=f"adm:revoke:{target}:{requester}"),InlineKeyboardButton("❌ Annuler",callback_data=f"adm:cancel:{target}:{requester}"))
    bot.send_message(m.chat.id,"⏳ Demande envoyée au Super Admin.",reply_markup=home_markup()); bot.send_message(super_id,f"⚠️ <b>DEMANDE RÉVOCATION</b>\n\nAdmin <code>{requester}</code> demande la révocation de <code>{target}</code>.",parse_mode="HTML",reply_markup=markup)

@bot.callback_query_handler(func=lambda c: c.data == "req_promote_admin")
def req_promote(c):
    if not admin_core.is_super_admin(c.from_user.id): _answer(c,"⛔ Super Admin uniquement."); return
    _answer(c); _ask(c.message.chat.id,"👑 <b>ID Telegram à promouvoir :</b>",_process_promote)

def _process_promote(m):
    target=(m.text or "").strip(); _result(m, admin_core.promote_admin_to_supreme(int(target)) if target.isdigit() else (False,"❌ ID invalide."))

@bot.callback_query_handler(func=lambda c: c.data.startswith("adm:"))
def admin_approval(c):
    if not admin_core.is_super_admin(c.from_user.id): _answer(c,"⛔ Super Admin uniquement."); return
    parts=c.data.split(":")
    if len(parts)!=4: _answer(c,"❌ Requête invalide."); return
    action,target,requester=parts[1],parts[2],parts[3]; _answer(c)
    if action=="add": result=admin_core.approve_new_admin(target); text="✅ Admin ajouté." if result[0] else f"❌ {result[1]}"
    elif action=="revoke": result=admin_core.remove_admin(target); text="✅ Admin révoqué." if result[0] else f"❌ {result[1]}"
    else: text="ℹ️ Demande annulée."
    try: bot.edit_message_reply_markup(c.message.chat.id,c.message.message_id,reply_markup=None)
    except Exception: pass
    bot.send_message(c.message.chat.id,text,parse_mode="HTML")
    try: bot.send_message(int(requester),text,parse_mode="HTML",reply_markup=home_markup())
    except Exception: pass


@bot.message_handler(func=lambda m: True, content_types=["text"])
def fallback(message):
    if is_admin(message.from_user.id) and not (message.text or "").startswith("/"):
        bot.send_message(message.chat.id,"ℹ️ Aucune action en attente.",reply_markup=home_markup())


if __name__ == "__main__":
    log.info("TOM_TUNNEL Telegram Bot démarrage")
    bot.infinity_polling(skip_pending=True, timeout=30, long_polling_timeout=30)
