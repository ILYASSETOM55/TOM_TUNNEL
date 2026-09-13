#!/usr/bin/env python3
"""
Vérifie que le token Telegram dans /etc/tom_tunnel_bot/config.json est valide.
Retourne 0 si OK, code non-zero sinon.
"""
import json
import os
import sys
import requests

CONFIG = "/etc/tom_tunnel_bot/config.json"


def load_config():
    if not os.path.exists(CONFIG):
        print(f"[ERROR] Fichier de configuration introuvable : {CONFIG}")
        sys.exit(2)
    with open(CONFIG, "r", encoding="utf-8") as f:
        return json.load(f)


def main():
    cfg = load_config()
    token = cfg.get("bot_token") or cfg.get("BOT_TOKEN")
    if not token:
        print("[ERROR] Clef 'bot_token' introuvable dans le fichier de configuration.")
        sys.exit(2)

    url = f"https://api.telegram.org/bot{token}/getMe"
    try:
        r = requests.get(url, timeout=10)
        r.raise_for_status()
        data = r.json()
    except Exception as e:
        print(f"[ERROR] Échec requête HTTP vers l'API Telegram : {e}")
        sys.exit(3)

    if not data.get("ok"):
        print(f"[ERROR] Token invalide ou erreur API : {data}")
        sys.exit(4)

    result = data.get("result", {})
    print("[OK] Token valide.")
    print(
        f"Bot id: {result.get('id')}, "
        f"username: @{result.get('username')}, "
        f"name: {result.get('first_name')}"
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
