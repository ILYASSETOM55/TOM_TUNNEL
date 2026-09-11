import telebot
import subprocess
from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
import json
import os
import logging
import threading
import re
from datetime import datetime, timedelta
from modules import system_core, ssh_core, admin_core, xray_core, zivpn_core

logging.basicConfig(level=logging.WARNING, format='%(asctime)s %(levelname)s %(message)s')
CONFIG_FILE    = '/etc/the_s_bot/config.json'
RESELLERS_FILE = '/etc/the_s_bot/resellers.json'
CONVS_FILE     = '/etc/the_s_bot/convs.json'
VISITORS_FILE  = '/etc/the_s_bot/visitors.json'
MENU_IMAGE_URL = "https://github.com/ppstech237/pps-tg-bot/blob/main/pps.jpg?raw=true"

def load_config():
    if not os.path.exists(CONFIG_FILE): return None
    with open(CONFIG_FILE, 'r') as f: return json.load(f)

config = load_config()
if not config: exit(1)

bot         = telebot.TeleBot(config.get('bot_token'))
SUPER_ADMIN = int(config.get('super_admin'))
BRAND       = config.get('brand', 'THE_S BOT')

#‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
#  VALIDATION
#‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
def validate_username(username):
    if not username or len(username) < 4:
        return False, "❌ Minimum 4 caractères.\n📌 Exemple : <code>jean01</code>"
    if " " in username:
        return False, "❌ Pas d'espaces autorisés.\n📌 Exemple : <code>jean01</code>"
    if not re.match(r'^[a-zA-Z0-9_-]+$', username):
        return False, "❌ Caractères autorisés : lettres, chiffres, <code>_</code> et <code>-</code> uniquement.\n📌 Exemple : <code>jean_01</code>"
    return True, ""

def validate_password(password):
    if len(password) < 4:
        return False, (
            f"❌ Mot de passe trop court.\n\n"
            f"➡️ <code>{password}</code> ⬅️ ({len(password)} caractère(s))\n\n"
            f"📌 Minimum 4 caractères. Exemple : <code>pass1234</code>"
        )
    return True, ""

def validate_days(text, max_days):
    if not text.isdigit():
        return False, (
            f"❌ Valeur invalide : <code>{text}</code>\n\n"
            f"📌 Entrez un nombre entier. Exemple : <code>7</code>\n"
            f"⏳ Maximum autorisé : <b>{max_days} jour(s)</b>"
        )
    days_int = int(text)
    if days_int < 1:
        return False, (
            f"❌ Le nombre de jours doit être au moins 1.\n"
            f"📌 Exemple : <code>7</code> | Max : <b>{max_days}j</b>"
        )
    if days_int > max_days:
        return False, (
            f"❌ Durée refusée : <b>{days_int}j</b> dépasse votre maximum.\n"
            f"⏳ Maximum autorisé : <b>{max_days} jour(s)</b>\n"
            f"📌 Exemple : <code>{max_days}</code>"
        )
    return True, ""

# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
#  BOUTON ANNULER
# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
def cancel_keyboard(back_menu):
    markup = InlineKeyboardMarkup()
    markup.add(InlineKeyboardButton("❌ Annuler", callback_data=f"cancel_to_{back_menu}"))
    return markup

@bot.callback_query_handler(func=lambda call: call.data.startswith("cancel_to_"))
def handle_cancel(call):
    uid      = call.from_user.id
    target   = call.data[len("cancel_to_"):]
    user_sessions.pop(uid, None)
    try:
        bot.delete_message(call.message.chat.id, call.message.message_id)
    except Exception:
        pass
    bot.send_message(
        call.message.chat.id,
        "❌ <b>Opération annulée.</b>",
        parse_mode="HTML",
        reply_markup=protocol_menu_keyboard(target, uid) if target != "home" else main_menu_keyboard(uid)
    )

# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
#  REVENDEURS — PERSISTANCE
# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
def load_resellers():
    if not os.path.exists(RESELLERS_FILE): return {}
    with open(RESELLERS_FILE, 'r') as f: return json.load(f)

def save_resellers(data):
    os.makedirs(os.path.dirname(RESELLERS_FILE), exist_ok=True)
    with open(RESELLERS_FILE, 'w') as f: json.dump(data, f, indent=2)

def load_convs():
    if not os.path.exists(CONVS_FILE): return {}
    with open(CONVS_FILE, 'r') as f: return json.load(f)

def save_convs(data):
    os.makedirs(os.path.dirname(CONVS_FILE), exist_ok=True)
    with open(CONVS_FILE, 'w') as f: json.dump(data, f, indent=2)

def load_visitors():
    if not os.path.exists(VISITORS_FILE): return {}
    with open(VISITORS_FILE, 'r') as f: return json.load(f)

def save_visitors(data):
    os.makedirs(os.path.dirname(VISITORS_FILE), exist_ok=True)
    with open(VISITORS_FILE, 'w') as f: json.dump(data, f, indent=2)

def add_conv_msg(uid, alias, text, direction):
    convs = load_convs()
    key   = str(uid)
    if key not in convs:
        convs[key] = {"alias": alias, "messages": []}
    convs[key]["alias"] = alias
    convs[key]["messages"].append({
        "direction": direction,
        "sender":    alias if direction == "from" else BRAND,
        "text":      text,
        "time":      datetime.now().strftime("%d/%m %H:%M")
    })
    convs[key]["messages"] = convs[key]["messages"][-50:]
    save_convs(convs)

def register_visitor(user):
    visitors = load_visitors()
    key = str(user.id)
    if key not in visitors:
        visitors[key] = {
            "first_name": user.first_name or "N/A",
            "username":   user.username or "N/A",
            "joined_at":  datetime.now().strftime("%Y-%m-%d %H:%M")
        }
        save_visitors(visitors)
        try:
            bot.send_message(
                SUPER_ADMIN,
                f"🆕 *Nouvel utilisateur a lancé le bot {BRAND} *\n\n"
                f"👤 Nom : {user.first_name or 'N/A'}\n"
                f"🔗 Username : @{user.username or 'N/A'}\n"
                f"🆔 ID : `{user.id}`",
                parse_mode="Markdown"
            )
        except Exception:
            pass

# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
#  GESTION REVENDEURS
# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
def get_reseller(uid):
    return load_resellers().get(str(uid))

def is_active(uid):
    r = get_reseller(uid)
    if not r: return False
    added_str = r.get("added_datetime") or (r["added_date"] + " 00:00:00")
    added     = datetime.strptime(added_str, "%Y-%m-%d %H:%M:%S")
    max_hours = r.get("max_hours", 48 if r["type"] == "trial" else r.get("max_days", 30) * 24)
    return datetime.now() <= added + timedelta(hours=max_hours)

def fmt_remain(uid):
    r = get_reseller(uid)
    if not r: return "N/A"
    added_str = r.get("added_datetime") or (r["added_date"] + " 00:00:00")
    added     = datetime.strptime(added_str, "%Y-%m-%d %H:%M:%S")
    max_hours = r.get("max_hours", 48 if r["type"] == "trial" else r.get("max_days", 30) * 24)
    expiry    = added + timedelta(hours=max_hours)
    remain    = expiry - datetime.now()
    if remain.total_seconds() <= 0: return "Expiré"
    days  = remain.days
    hours = remain.seconds // 3600
    return f"{days}j {hours}h" if days > 0 else f"{hours}h"

def days_remaining(uid):
    if is_admin(uid): return 9999
    r = get_reseller(uid)
    if not r: return 0
    added_str = r.get("added_datetime") or (r["added_date"] + " 00:00:00")
    added     = datetime.strptime(added_str, "%Y-%m-%d %H:%M:%S")
    max_hours = r.get("max_hours", 48 if r["type"] == "trial" else r.get("max_days", 30) * 24)
    expiry    = added + timedelta(hours=max_hours)
    remain    = expiry - datetime.now()
    return max(0, remain.days)

# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
#  VÉRIFICATION EXPIRATION AUTO (thread)
# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
def _expiration_loop():
    while True:
        try:
            resellers = load_resellers()
            to_remove = []
            for rid, info in resellers.items():
                uid_int   = int(rid)
                added_str = info.get("added_datetime") or (info["added_date"] + " 00:00:00")
                added     = datetime.strptime(added_str, "%Y-%m-%d %H:%M:%S")
                max_hours = info.get("max_hours", 48 if info["type"] == "trial" else info.get("max_days", 30) * 24)
                alias     = info.get("alias", rid)
                if datetime.now() > added + timedelta(hours=max_hours):
                    to_remove.append(rid)
                    try:
                        markup = InlineKeyboardMarkup()
                        markup.add(InlineKeyboardButton(f"📩 Contacter {BRAND}", callback_data="contact_pps"))
                        bot.send_message(
                            uid_int,
                            f"⛔ *Abonnement expiré à {BRAND}*\n\n"
                            f"Votre abonnement est arrivé à son terme.\n"
                            f"Contactez {BRAND} pour le renouveler.",
                            parse_mode="Markdown",
                            reply_markup=markup
                        )
                    except Exception:
                        pass
                    try:
                        bot.send_message(
                            SUPER_ADMIN,
                            f"ℹ️ Revendeur *{alias}* (`{rid}`) expiré — supprimé automatiquement.",
                            parse_mode="Markdown"
                        )
                    except Exception:
                        pass
            if to_remove:
                for rid in to_remove: del resellers[rid]
                save_resellers(resellers)
        except Exception:
            pass
        threading.Event().wait(300)

threading.Thread(target=_expiration_loop, daemon=True).start()

# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
#  ACCÈS
# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
def is_admin(user_id):
    cfg = load_config()
    return user_id == SUPER_ADMIN or user_id in cfg.get('admins', [])

def has_access(user_id):
    return is_admin(user_id) or (get_reseller(user_id) is not None and is_active(user_id))

# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
#  NOTIFICATION OWNER — COMPTE CRÉÉ
# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
def notify_owner_account_created(creator_id, proto, username, days, password=""):
    if creator_id == SUPER_ADMIN:
        return
    try:
        r     = get_reseller(creator_id)
        alias = r.get("alias", str(creator_id)) if r else "OWNER"
        msg   = (
            f"🔔 <b>Nouveau compte créé sur {BRAND}</b>\n\n"
            f"👤 Revendeur : <b>{alias}</b> (<code>{creator_id}</code>)\n"
            f"🔌 Protocole : <b>{proto.upper()}</b>\n"
            f"🧑 Username  : <code>{username}</code>\n"
        )
        if password:
            msg += f"🔑 Mot de passe : <code>{password}</code>\n"
        msg += f"⏳ Durée : <b>{days} jour(s)</b>"
        bot.send_message(SUPER_ADMIN, msg, parse_mode="HTML")
    except Exception:
        pass

# ══════════════════════════════════════════
#  RÉCUPÉRATION INFOS SYSTÈME
# ══════════════════════════════════════════
def get_system_info():
    ip          = subprocess.getoutput("curl -s ifconfig.me").strip()
    domain      = subprocess.getoutput("cat /etc/xray/domain 2>/dev/null || echo 'N/A'").strip()
    slowdns_pub = subprocess.getoutput("cat /etc/slowdns/server.pub 2>/dev/null || echo 'N/A'").strip()
    return ip, domain, slowdns_pub

# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
#  CLAVIERS
# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
def main_menu_keyboard(uid):
    markup = InlineKeyboardMarkup(row_width=2)
    markup.add(
        InlineKeyboardButton("🗽 SSH/WS",      callback_data="menu_ssh"),
        InlineKeyboardButton("🗽 VMESS",       callback_data="menu_vmess"),
        InlineKeyboardButton("🗽 VLESS",       callback_data="menu_vless"),
        InlineKeyboardButton("🗽 TROJAN",      callback_data="menu_trojan"),
        InlineKeyboardButton("🐌 SLOW DNS",    callback_data="menu_slowdns"),
        InlineKeyboardButton("🚀 UDP FAST",    callback_data="menu_udpfast"),
        InlineKeyboardButton("🔌 SOCKS",       callback_data="menu_socks"),
        InlineKeyboardButton("🛫 ZIVPN",       callback_data="menu_zivpn"),
        InlineKeyboardButton("📊 VPS STATUS",  callback_data="menu_status"),
        InlineKeyboardButton("🧹 CLEAN LOGS",  callback_data="menu_log"),
    )
    if is_admin(uid):
        markup.add(
            InlineKeyboardButton("👥 Revendeurs",  callback_data="menu_resellers"),
            InlineKeyboardButton("💬 Messagerie",  callback_data="msg_panel"),
            InlineKeyboardButton("🔄 REBOOT VPS",  callback_data="action_reboot"),
            InlineKeyboardButton("👑 ADMINS",       callback_data="menu_admins"),
        )
    if uid == SUPER_ADMIN:
        markup.add(InlineKeyboardButton("🏷️ Définir ma marque", callback_data="set_brand_menu"))
    else:
        markup.add(InlineKeyboardButton(f"📩 Contacter {BRAND}", callback_data="contact_pps"))
    return markup

def protocol_menu_keyboard(proto, uid):
    markup = InlineKeyboardMarkup(row_width=1)
    d_rem  = days_remaining(uid)
    note   = f"  (max {d_rem}j)" if not is_admin(uid) and d_rem < 9999 else ""
    markup.add(
        InlineKeyboardButton(f"➕ Créer compte {proto.upper()}{note}", callback_data=f"add_{proto}"),
        InlineKeyboardButton(f"🔄 Renouveler compte {proto.upper()}",  callback_data=f"renew_{proto}"),
        InlineKeyboardButton(f"🗑️ Supprimer compte {proto.upper()}",   callback_data=f"del_{proto}"),
        InlineKeyboardButton(f"📋 Liste des comptes {proto.upper()}",  callback_data=f"list_{proto}"),
    )
    if proto == 'ssh':
        markup.add(
            InlineKeyboardButton("🔒 Verrouiller un compte",   callback_data="lock_ssh"),
            InlineKeyboardButton("🔓 Déverrouiller un compte", callback_data="unlock_ssh"),
        )
    markup.add(InlineKeyboardButton("🔙 Retour Accueil", callback_data="action_home"))
    return markup

def _show_submenu(call, text, markup):
    if call.message.content_type == 'photo':
        try: bot.delete_message(call.message.chat.id, call.message.message_id)
        except Exception: pass
        bot.send_message(call.message.chat.id, text, parse_mode="HTML", reply_markup=markup)
    else:
        bot.edit_message_text(text, chat_id=call.message.chat.id,
                              message_id=call.message.message_id,
                              parse_mode="HTML", reply_markup=markup)

# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
#  /start
# ‎▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
@bot.message_handler(commands=['start'])
def send_welcome(message):
    uid = message.from_user.id
    register_visitor(message.from_user)
    if not has_access(uid):
        markup = InlineKeyboardMarkup()
        markup.add(InlineKeyboardButton(f"📩 Contacter {BRAND}", callback_data="contact_pps_unauth"))
        bot.send_message(
            uid,
            f"⛔ <b>Accès refusé à {BRAND}</b>\n\n"
            f"Vous n'êtes pas autorisé à utiliser ce bot.\n"
            f"Contactez <b>{BRAND}</b> pour obtenir un accès.",
            parse_mode="HTML",
            reply_markup=markup
        )
        return
    r      = get_reseller(uid)
    rtype  = r['type'].upper() if r else "OWNER"
    remain = fmt_remain(uid) if r else ""
    extra  = f"\n🏷️ Type : <b>{rtype}</b> | ⏳ Restant : <b>{remain}</b>" if r else ""
    bot.send_photo(
        uid,
        MENU_IMAGE_URL,
        caption=f"<b> {BRAND}</b>{extra}\nSélectionnez un Protocole :",
        parse_mode="HTML",
        reply_markup=main_menu_keyboard(uid)
    )

# ... rest of file unchanged ...
if __name__ == "__main__":
    os.makedirs("/etc/the_s_bot", exist_ok=True)
    if not os.path.exists(RESELLERS_FILE): save_resellers({})
    if not os.path.exists(CONVS_FILE):    save_convs({})
    if not os.path.exists(VISITORS_FILE): save_visitors({})
    bot.infinity_polling()
