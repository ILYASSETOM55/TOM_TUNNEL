# ───────────────────────── SYSTÈME ─────────────────────────

def _back_home_markup():
    m = InlineKeyboardMarkup()
    m.add(B("🏠 Accueil", callback_data="action_home"))
    return m


@bot.callback_query_handler(func=lambda c: c.data == "menu_status")
def status(c):
    if not is_admin(c.from_user.id):
        return
    _show(c, system_core.get_vps_status(), _back_home_markup())


@bot.callback_query_handler(func=lambda c: c.data == "menu_log")
def logs(c):
    if not is_admin(c.from_user.id):
        return
    _show(c, system_core.clean_system_logs(), _back_home_markup())


@bot.callback_query_handler(func=lambda c: c.data == "action_reboot")
def reboot(c):
    if not admin_core.is_super_admin(c.from_user.id):
        _answer(c, "⛔ Super Admin uniquement.")
        return
    parts = c.data.split(":")
    if len(parts) != 4:
        _answer(c, "❌ Requête invalide.")
        return
    action, target, requester = parts[1], parts[2], parts[3]
    _answer(c)
    if action == "add":
        result = admin_core.approve_new_admin(target)
        text = "✅ Admin ajouté." if result[0] else f"❌ {result[1]}"
    elif action == "revoke":
        result = admin_core.remove_admin(target)
        text = "✅ Admin révoqué." if result[0] else f"❌ {result[1]}"
    else:
        text = "ℹ️ Demande annulée."
    try:
        bot.edit_message_reply_markup(c.message.chat.id, c.message.message_id, reply_markup=None)
    except Exception:
        pass
    bot.send_message(c.message.chat.id, text, parse_mode="HTML")
    try:
        bot.send_message(int(requester), text, parse_mode="HTML", reply_markup=home_markup())
    except Exception:
        pass


@bot.message_handler(func=lambda m: True, content_types=["text"])
def fallback(message):
    if is_admin(message.from_user.id) and not (message.text or "").startswith("/"):
        bot.send_message(message.chat.id, "ℹ️ Aucune action en attente.", reply_markup=home_markup())


if __name__ == "__main__":
    log.info("TOM_TUNNEL Telegram Bot démarrage")
    bot.infinity_polling(skip_pending=True, timeout=30, long_polling_timeout=30)
