import json
import logging
import os
import subprocess
import telebot
from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
from modules import system_core, ssh_core, admin_core, xray_core, zivpn_core

CONFIG_FILE = "/etc/tom_tunnel_bot/config.json"
MENU_IMAGE_URL = "https://github.com/user-attachments/assets/3a7c7588-48f0-4e3e-ad95-f9a23cd20311"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

def load_config():
    if not os.path.exists(CONFIG_FILE):
        return {}
    with open(CONFIG_FILE, encoding="utf-8") as f:
        return json.load(f)

config = load_config()
if not config.get("bot_token") or config.get("super_admin") is None:
    raise SystemExit("Configuration Telegram absente ou invalide.")

bot = telebot.TeleBot(config["bot_token"])
SUPER_ADMIN = int(config["super_admin"])

def is_admin(user_id):
    cfg = load_config()
    admins = [int(x) for x in cfg.get("admins", [])]
    supers = [int(x) for x in cfg.get("super_admins", [])]
    return int(user_id) == int(cfg.get("super_admin", -1)) or int(user_id) in admins or int(user_id) in supers

def home_markup():
    m=InlineKeyboardMarkup(row_width=2)
    for text,data in [
        ("📡 SSH/WS","menu_ssh"),("🛡️ VMESS","menu_vmess"),
        ("🛡️ VLESS","menu_vless"),("🔥 TROJAN","menu_trojan"),
        ("🔌 SOCKS","menu_socks"),("📱 ZIVPN","menu_zivpn"),
        ("📊 VPS STATUS","menu_status"),("🧹 CLEAN LOGS","menu_log"),
        ("👑 ADMINS","menu_admins"),("🔄 REBOOT VPS","action_reboot")]:
        m.add(InlineKeyboardButton(text,callback_data=data))
    return m

def protocol_markup(proto):
    m=InlineKeyboardMarkup(row_width=1)
    for label,action in [
        (f"➕ Créer {proto.upper()}","add_"),
        (f"🔄 Renouveler {proto.upper()}","renew_"),
        (f"🗑️ Supprimer {proto.upper()}","del_"),
        (f"📋 Liste {proto.upper()}","list_")]:
        m.add(InlineKeyboardButton(label,callback_data=action+proto))
    if proto=="ssh":
        m.add(InlineKeyboardButton("🔒 Verrouiller","lock_ssh"))
        m.add(InlineKeyboardButton("🔓 Déverrouiller","unlock_ssh"))
    m.add(InlineKeyboardButton("🔙 Accueil",callback_data="action_home"))
    return m

def show(call,text,markup):
    try:
        bot.answer_callback_query(call.id)
    except Exception:
        pass
    try:
        if call.message.content_type=="photo":
            bot.delete_message(call.message.chat.id,call.message.message_id)
            bot.send_message(call.message.chat.id,text,parse_mode="HTML",reply_markup=markup)
        else:
            bot.edit_message_text(text,call.message.chat.id,call.message.message_id,parse_mode="HTML",reply_markup=markup)
    except Exception:
        bot.send_message(call.message.chat.id,text,parse_mode="HTML",reply_markup=markup)

def send_home(chat_id):
    """Affiche le menu principal. Si Telegram ne peut pas récupérer
    l'image distante, le menu texte est envoyé automatiquement."""
    markup = home_markup()
    caption = "<b>💻 TOM_TUNNEL SERVER</b>\nSélectionnez un module :"
    try:
        bot.send_photo(
            chat_id,
            MENU_IMAGE_URL,
            caption=caption,
            parse_mode="HTML",
            reply_markup=markup
        )
    except Exception as exc:
        logging.warning("Image du menu indisponible: %s", exc)
        bot.send_message(
            chat_id,
            caption,
            parse_mode="HTML",
            reply_markup=markup
        )

@bot.message_handler(commands=["start"])
def start(message):
    if not is_admin(message.from_user.id):
        bot.reply_to(message,"⛔ Accès refusé.")
        return
    try:
        send_home(message.chat.id)
    except Exception:
        logging.exception("Erreur pendant /start")
        bot.send_message(
            message.chat.id,
            "<b>💻 TOM_TUNNEL SERVER</b>\nSélectionnez un module :",
            parse_mode="HTML",
            reply_markup=home_markup()
        )

@bot.callback_query_handler(func=lambda c:c.data=="action_home")
def home(c):
    if is_admin(c.from_user.id):
        try: bot.delete_message(c.message.chat.id,c.message.message_id)
        except Exception: pass
        send_home(c.message.chat.id)

@bot.callback_query_handler(func=lambda c:c.data in ["menu_ssh","menu_vmess","menu_vless","menu_trojan","menu_socks","menu_zivpn"])
def protocol_menu(c):
    if not is_admin(c.from_user.id): return
    proto=c.data.split("_",1)[1]
    show(c,f"<b>Module {proto.upper()}</b>\nChoisissez une action :",protocol_markup(proto))

def ask(c,prompt,handler,*args):
    msg=bot.send_message(c.message.chat.id,prompt,parse_mode="HTML")
    bot.register_next_step_handler(msg,handler,*args)

def _send_result(message,result):
    ok,res=result
    bot.send_message(message.chat.id,res,parse_mode="HTML",reply_markup=home_markup())

# SSH
@bot.callback_query_handler(func=lambda c:c.data=="add_ssh")
def add_ssh(c):
    if is_admin(c.from_user.id): ask(c,"👤 Entrez le nom d'utilisateur SSH :",ssh_user,c.from_user.id)
def ssh_user(m,creator):
    ask(m,"🔑 Entrez le mot de passe :",ssh_pass,m.text.strip(),creator)
def ssh_pass(m,user,creator):
    ask(m,"⏳ Entrez la durée en jours :",ssh_days,user,m.text.strip(),creator)
def ssh_days(m,user,password,creator):
    if not m.text.strip().isdigit(): bot.send_message(m.chat.id,"❌ Durée invalide.",reply_markup=home_markup()); return
    _send_result(m,ssh_core.create_ssh_account(user,password,m.text.strip(),creator))

@bot.callback_query_handler(func=lambda c:c.data=="renew_ssh")
def renew_ssh(c):
    if is_admin(c.from_user.id): ask(c,"👤 Utilisateur SSH :",ssh_renew_user)
def ssh_renew_user(m):
    ask(m,"⏳ Jours à ajouter :",ssh_renew_days,m.text.strip())
def ssh_renew_days(m,user):
    _send_result(m,ssh_core.renew_ssh_account(user,m.text.strip()))

@bot.callback_query_handler(func=lambda c:c.data=="del_ssh")
def del_ssh(c):
    if is_admin(c.from_user.id): ask(c,"👤 Utilisateur SSH à supprimer :",ssh_delete)
def ssh_delete(m):
    _send_result(m,ssh_core.delete_ssh_account(m.text.strip()))

@bot.callback_query_handler(func=lambda c:c.data in ["lock_ssh","unlock_ssh"])
def lock_ssh(c):
    if is_admin(c.from_user.id): ask(c,"👤 Utilisateur SSH :",ssh_lock,c.data)
def ssh_lock(m,action):
    r=ssh_core.lock_ssh_account(m.text.strip()) if action=="lock_ssh" else ssh_core.unlock_ssh_account(m.text.strip())
    _send_result(m,r)

@bot.callback_query_handler(func=lambda c:c.data=="list_ssh")
def list_ssh(c):
    if not is_admin(c.from_user.id): return
    users=ssh_core.get_ssh_usernames()
    m=InlineKeyboardMarkup(row_width=1)
    for u in users: m.add(InlineKeyboardButton("👤 "+u,callback_data="view_ssh_"+u))
    m.add(InlineKeyboardButton("🔙 Accueil",callback_data="action_home"))
    show(c,"📋 <b>COMPTES SSH</b>\nSélectionnez un compte :",m) if users else show(c,"📋 Aucun compte SSH.",m)

@bot.callback_query_handler(func=lambda c:c.data.startswith("view_ssh_"))
def view_ssh(c):
    if not is_admin(c.from_user.id): return
    ok,text=ssh_core.get_ssh_account_details(c.data[9:])
    m=InlineKeyboardMarkup().add(InlineKeyboardButton("🔙 Liste",callback_data="list_ssh"))
    m.add(InlineKeyboardButton("🏠 Accueil",callback_data="action_home"))
    show(c,text,m)

# Xray
def xray_proto(c): return c.data.split("_",1)[1]

@bot.callback_query_handler(func=lambda c:c.data in ["add_vless","add_vmess","add_trojan","add_socks"])
def add_xray(c):
    if is_admin(c.from_user.id): ask(c,"👤 Nom d'utilisateur :",xray_user,xray_proto(c),c.from_user.id)
def xray_user(m,proto,creator):
    ask(m,"⏳ Durée en jours :",xray_days,m.text.strip(),proto,creator)
def xray_days(m,user,proto,creator):
    _send_result(m,xray_core.create_xray_account(proto,user,m.text.strip(),creator))

@bot.callback_query_handler(func=lambda c:c.data in ["renew_vless","renew_vmess","renew_trojan","renew_socks"])
def renew_xray(c):
    if is_admin(c.from_user.id): ask(c,"👤 Utilisateur :",xray_renew_user,xray_proto(c))
def xray_renew_user(m,proto): ask(m,"⏳ Jours à ajouter :",xray_renew_days,proto,m.text.strip())
def xray_renew_days(m,proto,user): _send_result(m,xray_core.renew_xray_account(proto,user,m.text.strip()))

@bot.callback_query_handler(func=lambda c:c.data in ["del_vless","del_vmess","del_trojan","del_socks"])
def del_xray(c):
    if is_admin(c.from_user.id): ask(c,"👤 Utilisateur :",xray_delete,xray_proto(c))
def xray_delete(m,proto): _send_result(m,xray_core.delete_xray_account(proto,m.text.strip()))

@bot.callback_query_handler(func=lambda c:c.data in ["list_vless","list_vmess","list_trojan","list_socks"])
def list_xray(c):
    if not is_admin(c.from_user.id): return
    proto=xray_proto(c); users=xray_core.get_xray_usernames(proto)
    m=InlineKeyboardMarkup(row_width=1)
    for u in users: m.add(InlineKeyboardButton("👤 "+u,callback_data=f"view_{proto}_{u}"))
    m.add(InlineKeyboardButton("🔙 Accueil",callback_data="action_home"))
    show(c,f"📋 <b>COMPTES {proto.upper()}</b>",m)

@bot.callback_query_handler(func=lambda c:c.data.startswith("view_vless_") or c.data.startswith("view_vmess_") or c.data.startswith("view_trojan_") or c.data.startswith("view_socks_"))
def view_xray(c):
    if not is_admin(c.from_user.id): return
    _,proto,user=c.data.split("_",2)
    ok,text=xray_core.get_xray_account_details(proto,user)
    m=InlineKeyboardMarkup().add(InlineKeyboardButton("🔙 Liste",callback_data="list_"+proto))
    m.add(InlineKeyboardButton("🏠 Accueil",callback_data="action_home"))
    show(c,text,m)

# ZIVPN
@bot.callback_query_handler(func=lambda c:c.data=="add_zivpn")
def add_zivpn(c):
    if is_admin(c.from_user.id): ask(c,"👤 Nom d'utilisateur ZIVPN :",z_user,c.from_user.id)
def z_user(m,creator): ask(m,"🔑 Mot de passe :",z_pass,m.text.strip(),creator)
def z_pass(m,user,creator): ask(m,"⏳ Durée en jours :",z_days,user,m.text.strip(),creator)
def z_days(m,user,password,creator): _send_result(m,zivpn_core.create_zivpn_account(user,password,m.text.strip(),creator))

@bot.callback_query_handler(func=lambda c:c.data=="renew_zivpn")
def renew_z(c):
    if is_admin(c.from_user.id): ask(c,"👤 Utilisateur ZIVPN :",z_renew_user)
def z_renew_user(m): ask(m,"⏳ Jours à ajouter :",z_renew_days,m.text.strip())
def z_renew_days(m,user): _send_result(m,zivpn_core.renew_zivpn_account(user,m.text.strip()))

@bot.callback_query_handler(func=lambda c:c.data=="del_zivpn")
def del_z(c):
    if is_admin(c.from_user.id): ask(c,"👤 Utilisateur ZIVPN :",z_delete)
def z_delete(m): _send_result(m,zivpn_core.delete_zivpn_account(m.text.strip()))

@bot.callback_query_handler(func=lambda c:c.data=="list_zivpn")
def list_z(c):
    if not is_admin(c.from_user.id): return
    users=zivpn_core.get_zivpn_usernames()
    m=InlineKeyboardMarkup(row_width=1)
    for u in users: m.add(InlineKeyboardButton("👤 "+u,callback_data="view_zivpn_"+u))
    m.add(InlineKeyboardButton("🔙 Accueil",callback_data="action_home"))
    show(c,"📋 <b>COMPTES ZIVPN</b>",m)

@bot.callback_query_handler(func=lambda c:c.data.startswith("view_zivpn_"))
def view_z(c):
    if not is_admin(c.from_user.id): return
    ok,text=zivpn_core.get_zivpn_account_details(c.data[11:])
    m=InlineKeyboardMarkup().add(InlineKeyboardButton("🔙 Liste",callback_data="list_zivpn"))
    m.add(InlineKeyboardButton("🏠 Accueil",callback_data="action_home"))
    show(c,text,m)

# System
@bot.callback_query_handler(func=lambda c:c.data=="menu_status")
def status(c):
    if is_admin(c.from_user.id):
        m=InlineKeyboardMarkup().add(InlineKeyboardButton("🔙 Accueil",callback_data="action_home"))
        show(c,system_core.get_vps_status(),m)

@bot.callback_query_handler(func=lambda c:c.data=="menu_log")
def logs(c):
    if is_admin(c.from_user.id):
        m=InlineKeyboardMarkup().add(InlineKeyboardButton("🔙 Accueil",callback_data="action_home"))
        show(c,system_core.clean_system_logs(),m)

@bot.callback_query_handler(func=lambda c:c.data=="action_reboot")
def reboot(c):
    if not admin_core.is_super_admin(c.from_user.id): return
    bot.answer_callback_query(c.id,"♻️ Reboot en cours...")
    bot.send_message(c.message.chat.id,"♻️ <b>Reboot VPS lancé.</b>",parse_mode="HTML")
    subprocess.Popen(["systemctl","reboot"])

# Admins
@bot.callback_query_handler(func=lambda c:c.data=="menu_admins")
def admins(c):
    if not is_admin(c.from_user.id): return
    m=InlineKeyboardMarkup(row_width=1)
    m.add(InlineKeyboardButton("📋 Liste",callback_data="list_admins"))
    if admin_core.is_super_admin(c.from_user.id):
        m.add(InlineKeyboardButton("➕ Ajouter",callback_data="req_add_admin"))
        m.add(InlineKeyboardButton("👑 Promouvoir",callback_data="req_promote_admin"))
        m.add(InlineKeyboardButton("❌ Supprimer",callback_data="req_del_admin"))
    m.add(InlineKeyboardButton("🔙 Accueil",callback_data="action_home"))
    show(c,admin_core.list_admins(),m)

@bot.callback_query_handler(func=lambda c:c.data=="list_admins")
def list_admin(c):
    if not is_admin(c.from_user.id): return
    m=InlineKeyboardMarkup().add(InlineKeyboardButton("🔙 Admins",callback_data="menu_admins"))
    show(c,admin_core.list_admins(),m)

@bot.callback_query_handler(func=lambda c:c.data in ["req_add_admin","req_del_admin","req_promote_admin"])
def admin_request(c):
    if not is_admin(c.from_user.id):
        return
    action=c.data
    if action=="req_promote_admin" and not admin_core.is_super_admin(c.from_user.id):
        bot.answer_callback_query(c.id,"⛔ Réservé au Super Admin.")
        return
    msg=bot.send_message(c.message.chat.id,"👤 Entrez l'ID Telegram :")
    bot.register_next_step_handler(msg,admin_action,action,c.from_user.id)

def admin_action(m,action,requester_id):
    if not m.text.strip().isdigit():
        bot.send_message(m.chat.id,"❌ ID invalide.",reply_markup=home_markup())
        return
    target=int(m.text.strip())

    # Le Super Admin exécute directement l'action.
    if admin_core.is_super_admin(requester_id):
        if action=="req_add_admin":
            result=admin_core.approve_new_admin(target)
        elif action=="req_del_admin":
            result=admin_core.remove_admin(target)
        else:
            result=admin_core.promote_admin_to_supreme(target)
        _send_result(m,result)
        return

    # Un administrateur délégué peut demander une action au Super Admin.
    if action=="req_promote_admin":
        bot.send_message(m.chat.id,"⛔ Seul le Super Admin peut promouvoir un administrateur.",reply_markup=home_markup())
        return

    super_id=int(admin_core.get_config().get("super_admin"))
    prefix="add" if action=="req_add_admin" else "revoke"
    markup=InlineKeyboardMarkup(row_width=2)
    markup.add(
        InlineKeyboardButton("✅ Approuver",callback_data=f"adm:{prefix}:{target}:{requester_id}"),
        InlineKeyboardButton("❌ Refuser",callback_data=f"adm:cancel:{target}:{requester_id}")
    )
    label="ajouter" if prefix=="add" else "révoquer"
    bot.send_message(
        m.chat.id,
        f"⏳ Demande envoyée au Super Admin pour {label} <code>{target}</code>.",
        parse_mode="HTML"
    )
    bot.send_message(
        super_id,
        f"⚠️ <b>DEMANDE ADMIN</b>\n\n"
        f"L'admin <code>{requester_id}</code> demande de {label} <code>{target}</code>.",
        parse_mode="HTML",
        reply_markup=markup
    )

@bot.callback_query_handler(func=lambda c:c.data.startswith("adm:"))
def admin_approval(c):
    if not admin_core.is_super_admin(c.from_user.id):
        bot.answer_callback_query(c.id,"⛔ Réservé au Super Admin.")
        return

    parts=c.data.split(":")
    if len(parts)!=4:
        return
    action,target,requester=parts[1],int(parts[2]),int(parts[3])

    try:
        bot.edit_message_reply_markup(
            c.message.chat.id,c.message.message_id,reply_markup=None
        )
    except Exception:
        pass

    if action=="add":
        ok,res=admin_core.approve_new_admin(target)
        text="✅ Administrateur ajouté." if ok else f"❌ {res}"
    elif action=="revoke":
        ok,res=admin_core.remove_admin(target)
        text="✅ Administrateur révoqué." if ok else f"❌ {res}"
    elif action=="cancel":
        text="ℹ️ Demande annulée."
    else:
        text="❌ Action inconnue."

    bot.send_message(c.message.chat.id,text,parse_mode="HTML")
    try:
        bot.send_message(requester,text,parse_mode="HTML",reply_markup=home_markup())
    except Exception:
        pass

if __name__=="__main__":
    bot.infinity_polling(skip_pending=True)
