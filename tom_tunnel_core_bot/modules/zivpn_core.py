import html
import json
import os
import re
import shutil
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

CONF_FILE = Path("/etc/zivpn/config.json")
DB_FILE = Path("/etc/zivpn/user.db")
META_DIR = Path("/etc/tom_tunnel_bot/zivpn_accounts")
LEGACY_META_DIR = Path("/etc/nexus_bot/zivpn_accounts")
USER_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")


def _esc(v):
    return html.escape(str(v if v is not None else ""), quote=False)


def _valid_user(user):
    return bool(USER_RE.fullmatch((user or "").strip()))


def _valid_password(password):
    return bool(password) and not re.search(r"\s", password) and len(password) <= 128


def _valid_days(days):
    try:
        n = int(str(days).strip())
        return n if 1 <= n <= 3650 else None
    except (TypeError, ValueError):
        return None


def _run(args, timeout=30):
    try:
        return subprocess.run(
            args,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def _meta_path(user):
    return META_DIR / f"{user}.txt"


def _find_meta(user):
    for path in (
        _meta_path(user),
        LEGACY_META_DIR / f"{user}.txt"
    ):
        if path.is_file():
            return path
    return None


def _read_meta(user):
    path = _find_meta(user)

    if not path:
        return {}

    data = {}

    try:
        for line in path.read_text(
            encoding="utf-8"
        ).splitlines():

            if "=" in line:
                k, v = line.split("=", 1)
                data[k] = v

    except OSError:
        pass

    return data


def _write_meta(user, data):
    META_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    path = _meta_path(user)

    path.write_text(
        "".join(
            f"{k}={v}\n"
            for k, v in data.items()
        ),
        encoding="utf-8"
    )

    os.chmod(path, 0o600)


def _server_info():
    try:
        domain = (
            Path("/etc/xray/domain")
            .read_text()
            .strip()
            or "N/A"
        )
    except OSError:
        domain = "N/A"

    ip = "N/A"

    result = _run(
        [
            "curl",
            "-4",
            "-fsS",
            "--max-time",
            "4",
            "https://ipv4.icanhazip.com"
        ],
        6
    )

    if (
        result
        and result.returncode == 0
        and result.stdout.strip()
    ):
        ip = result.stdout.strip()

    return domain, ip


def _load_config():
    with CONF_FILE.open(
        encoding="utf-8"
    ) as f:
        cfg = json.load(f)

    auth = cfg.setdefault(
        "auth",
        {}
    )

    passwords = auth.setdefault(
        "config",
        []
    )

    if not isinstance(passwords, list):
        raise ValueError(
            "auth.config n'est pas une liste"
        )

    return cfg, passwords


def _save_config(cfg):
    backup = CONF_FILE.with_suffix(
        ".json.bot.bak"
    )

    shutil.copy2(
        CONF_FILE,
        backup
    )

    tmp = CONF_FILE.with_suffix(
        ".json.tmp"
    )

    tmp.write_text(
        json.dumps(
            cfg,
            indent=2,
            ensure_ascii=False
        ) + "\n",
        encoding="utf-8"
    )

    os.replace(
        tmp,
        CONF_FILE
    )

    return backup


def _restart_or_restore(backup):
    result = _run(
        ["systemctl", "restart", "zivpn"],
        30
    )

    if result and result.returncode == 0:
        return True

    try:
        shutil.copy2(
            backup,
            CONF_FILE
        )
    except OSError:
        pass

    _run(
        ["systemctl", "restart", "zivpn"],
        30
    )

    return False


def create_zivpn_account(
    user,
    password,
    days,
    created_by_id=None
):
    user = str(user or "").strip()
    password = str(password or "")

    if not _valid_user(user):
        return False, (
            "❌ Nom d'utilisateur ZIVPN invalide."
        )

    if not _valid_password(password):
        return False, (
            "❌ Mot de passe ZIVPN invalide : "
            "pas d'espaces ni retour à la ligne."
        )

    day_count = _valid_days(days)

    if day_count is None:
        return False, (
            "❌ La durée doit être comprise entre "
            "1 et 3650 jours."
        )

    if not CONF_FILE.is_file():
        return False, (
            "❌ /etc/zivpn/config.json introuvable."
        )

    DB_FILE.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    existing = []

    if DB_FILE.is_file():
        existing = DB_FILE.read_text(
            encoding="utf-8"
        ).splitlines()

    for line in existing:
        parts = line.split()

        if (
            len(parts) >= 2
            and (
                parts[0] == user
                or parts[1] == password
            )
        ):
            return False, (
                "❌ Nom d'utilisateur ou "
                "mot de passe déjà utilisé."
            )

    expiry = (
        datetime.now()
        + timedelta(days=day_count)
    ).strftime("%Y-%m-%d")

    try:
        cfg, passwords = _load_config()

        passwords.append(password)

        backup = _save_config(cfg)

    except Exception as exc:
        return False, (
            "❌ Impossible de modifier ZIVPN : "
            f"<code>{_esc(exc)}</code>"
        )

    DB_FILE.write_text(
        (
            "\n".join(
                [
                    f"{user} {password} {expiry}"
                ] + existing
            )
            + "\n"
        ),
        encoding="utf-8"
    )

    _write_meta(
        user,
        {
            "username": user,
            "password": password,
            "expiry": expiry,
            "createdById": created_by_id or "",
            "createdAt": (
                datetime.utcnow()
                .replace(microsecond=0)
                .isoformat()
                + "Z"
            ),
            "protocol": "zivpn",
            "status": "active"
        }
    )

    if not _restart_or_restore(backup):
        return False, (
            "❌ ZIVPN n'a pas redémarré. "
            "Configuration restaurée."
        )

    domain, ip = _server_info()

    # ==========================================================
    # AFFICHAGE DU COMPTE
    #
    # Aucune modification de la logique ZIVPN.
    # ==========================================================

    return True, (
        "╭▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╮\n"
        "┃ <b>ZIVPN ACCOUNT</b>\n"
        "╰▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬╯\n"

        f"👤 <b>Username:</b> "
        f"<code>{_esc(user)}</code>\n"

        f"🔑 <b>Password:</b> "
        f"<code>{_esc(password)}</code>\n"

        f"📅 <b>Expiry:</b> "
        f"<code>{_esc(expiry)}</code>\n"

        "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬\n"

        f"🖥️ <b>IP:</b> "
        f"<code>{_esc(ip)}</code>\n"

        f"🌐 <b>Domain:</b> "
        f"<code>{_esc(domain)}</code>\n"

        "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬\n"

        "📡 <b>Port:</b> "
        "<code>5667/UDP</code>\n"

        "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬"
    )


def get_zivpn_usernames():
    names = set()

    if DB_FILE.is_file():
        for line in DB_FILE.read_text(
            encoding="utf-8"
        ).splitlines():

            parts = line.split()

            if (
                len(parts) >= 3
                and _valid_user(parts[0])
            ):
                names.add(parts[0])

    for directory in (
        META_DIR,
        LEGACY_META_DIR
    ):
        if directory.is_dir():

            for path in directory.glob("*.txt"):

                if _valid_user(path.stem):
                    names.add(path.stem)

    return sorted(names)


def get_zivpn_account_details(user):
    user = str(user or "").strip()

    if not _valid_user(user):
        return False, (
            "❌ Nom d'utilisateur invalide."
        )

    data = _read_meta(user)

    if not data and DB_FILE.is_file():

        for line in DB_FILE.read_text(
            encoding="utf-8"
        ).splitlines():

            parts = line.split()

            if (
                len(parts) >= 3
                and parts[0] == user
            ):
                data = {
                    "username": parts[0],
                    "password": parts[1],
                    "expiry": parts[2]
                }
                break

    if not data:
        return False, (
            f"❌ Compte ZIVPN "
            f"<code>{_esc(user)}</code> introuvable."
        )

    domain, ip = _server_info()

    return True, (
        "┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        "┃ <b>ZIVPN ACCOUNT DETAILS</b>\n"
        "┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"

        f"👤 <b>Username:</b> "
        f"<code>{_esc(user)}</code>\n"

        f"🔑 <b>Password:</b> "
        f"<code>{_esc(data.get('password', 'N/A'))}</code>\n"

        f"📅 <b>Expiry:</b> "
        f"<code>{_esc(data.get('expiry', 'N/A'))}</code>\n"

        f"🖥️ <b>IP:</b> "
        f"<code>{_esc(ip)}</code>\n"

        f"🌐 <b>Domain:</b> "
        f"<code>{_esc(domain)}</code>\n"

        f"📡 <b>Port:</b> "
        f"<code>5667/UDP</code>"
    )


def renew_zivpn_account(user, days):
    user = str(user or "").strip()
    day_count = _valid_days(days)

    if not _valid_user(user):
        return False, (
            "❌ Nom d'utilisateur invalide."
        )

    if day_count is None:
        return False, "❌ Durée invalide."

    if not DB_FILE.is_file():
        return False, (
            "❌ Base ZIVPN introuvable."
        )

    lines = DB_FILE.read_text(
        encoding="utf-8"
    ).splitlines()

    found = False
    old_exp = None
    new_lines = []

    for line in lines:
        parts = line.split()

        if (
            len(parts) >= 3
            and parts[0] == user
        ):
            found = True
            old_exp = parts[2]

            try:
                base = datetime.strptime(
                    old_exp,
                    "%Y-%m-%d"
                )

                if base < datetime.now():
                    base = datetime.now()

            except ValueError:
                base = datetime.now()

            new_exp = (
                base + timedelta(days=day_count)
            ).strftime("%Y-%m-%d")

            new_lines.append(
                f"{parts[0]} {parts[1]} {new_exp}"
            )

        else:
            new_lines.append(line)

    if not found:
        return False, (
            f"❌ Utilisateur ZIVPN "
            f"<code>{_esc(user)}</code> introuvable."
        )

    DB_FILE.write_text(
        "\n".join(new_lines) + "\n",
        encoding="utf-8"
    )

    data = _read_meta(user) or {
        "username": user,
        "protocol": "zivpn"
    }

    data["expiry"] = new_exp

    _write_meta(
        user,
        data
    )

    return True, (
        "✅ <b>ZIVPN RENOUVELÉ</b>\n"
        f"👤 <code>{_esc(user)}</code>\n"
        f"📅 <code>{old_exp}</code> → "
        f"<code>{new_exp}</code>"
    )


def delete_zivpn_account(user):
    user = str(user or "").strip()

    if not _valid_user(user):
        return False, (
            "❌ Nom d'utilisateur invalide."
        )

    if not DB_FILE.is_file():
        return False, (
            "❌ Base ZIVPN introuvable."
        )

    lines = DB_FILE.read_text(
        encoding="utf-8"
    ).splitlines()

    password = None
    kept = []

    for line in lines:
        parts = line.split()

        if (
            len(parts) >= 2
            and parts[0] == user
        ):
            password = parts[1]
        else:
            kept.append(line)

    if password is None:
        return False, (
            f"❌ Utilisateur ZIVPN "
            f"<code>{_esc(user)}</code> introuvable."
        )

    try:
        cfg, passwords = _load_config()

        cfg["auth"]["config"] = [
            p for p in passwords
            if str(p) != password
        ]

        backup = _save_config(cfg)

    except Exception as exc:
        return False, (
            "❌ Impossible de modifier la "
            "configuration ZIVPN : "
            f"<code>{_esc(exc)}</code>"
        )

    DB_FILE.write_text(
        (
            "\n".join(kept) + "\n"
            if kept
            else ""
        ),
        encoding="utf-8"
    )

    for path in (
        _meta_path(user),
        LEGACY_META_DIR / f"{user}.txt"
    ):
        try:
            if path.exists():
                path.unlink()
        except OSError:
            pass

    if not _restart_or_restore(backup):
        return False, (
            "❌ ZIVPN n'a pas redémarré. "
            "Configuration restaurée."
        )

    return True, (
        f"🗑️ <b>Compte ZIVPN "
        f"<code>{_esc(user)}</code> supprimé.</b>"
    )


def list_zivpn_accounts():
    users = get_zivpn_usernames()

    if not users:
        return "📋 Aucun compte ZIVPN trouvé."

    lines = [
        "📋 <b>LISTE DES COMPTES ZIVPN</b>",
        ""
    ]

    for user in users:
        data = _read_meta(user)

        if not data and DB_FILE.is_file():

            for line in DB_FILE.read_text(
                encoding="utf-8"
            ).splitlines():

                parts = line.split()

                if (
                    len(parts) >= 3
                    and parts[0] == user
                ):
                    data = {
                        "password": parts[1],
                        "expiry": parts[2]
                    }
                    break

        lines.append(
            f"👤 <code>{_esc(user)}</code> | "
            f"Exp: <code>"
            f"{_esc(data.get('expiry', 'N/A'))}"
            f"</code>"
        )

    lines.append(
        f"\n📊 <b>Total:</b> {len(users)}"
    )

    return "\n".join(lines)