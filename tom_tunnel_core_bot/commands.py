#!/usr/bin/env python3
"""
Commandes du Bot Telegram Tom_tunnel
Gestion de toutes les commandes disponibles pour l'administrateur
"""

import telebot
import json
import os
import subprocess
from datetime import datetime

# Dictionnaire des commandes disponibles
COMMANDS = {
    '/start': 'Démarrer le bot et s\'authentifier',
    '/status': 'Afficher le statut du serveur',
    '/users': 'Liste des utilisateurs VPN',
    '/add_user': 'Ajouter un nouvel utilisateur',
    '/remove_user': 'Supprimer un utilisateur',
    '/ssh_status': 'Statut du service SSH',
    '/xray_status': 'Statut de Xray',
    '/restart_services': 'Redémarrer tous les services',
    '/server_info': 'Informations du serveur',
    '/help': 'Afficher cette aide',
}

def load_config():
    """Charger la configuration du bot"""
    config_path = '/etc/nexus_bot/config.json'
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            return json.load(f)
    return {}

def is_admin(user_id, config):
    """Vérifier si l'utilisateur est administrateur"""
    return user_id == config.get('super_admin') or user_id in config.get('admins', [])

def get_server_status():
    """Récupérer le statut du serveur"""
    try:
        result = subprocess.run(['systemctl', 'status'], capture_output=True, text=True, timeout=5)
        return result.stdout
    except Exception as e:
        return f"Erreur: {str(e)}"

def format_help_message():
    """Formater le message d'aide"""
    msg = "📋 *Commandes Disponibles:*\n\n"
    for cmd, desc in COMMANDS.items():
        msg += f"`{cmd}` - {desc}\n"
    return msg

def format_status_message():
    """Formater le message de statut"""
    try:
        # Vérifier les services
        services = ['ssh', 'xray', 'nginx']
        msg = "🔍 *Statut du Serveur:*\n\n"
        
        for service in services:
            result = subprocess.run(['systemctl', 'is-active', service], 
                                  capture_output=True, text=True, timeout=5)
            status = "✅ Actif" if result.returncode == 0 else "❌ Arrêté"
            msg += f"{service.upper()}: {status}\n"
        
        # Uptime
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = int(float(f.readline().split()[0]))
            days = uptime_seconds // 86400
            hours = (uptime_seconds % 86400) // 3600
            msg += f"\n⏱️ *Uptime:* {days}j {hours}h"
        
        return msg
    except Exception as e:
        return f"❌ Erreur: {str(e)}"

def format_server_info():
    """Formater les infos du serveur"""
    try:
        msg = "ℹ️ *Informations du Serveur:*\n\n"
        
        # Hostname
        result = subprocess.run(['hostname'], capture_output=True, text=True, timeout=5)
        msg += f"*Hostname:* `{result.stdout.strip()}`\n"
        
        # IP Address
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, timeout=5)
        msg += f"*IP Address:* `{result.stdout.strip()}`\n"
        
        # OS Info
        if os.path.exists('/etc/os-release'):
            with open('/etc/os-release', 'r') as f:
                lines = f.readlines()
                for line in lines:
                    if line.startswith('PRETTY_NAME'):
                        os_name = line.split('=')[1].strip().strip('"')
                        msg += f"*OS:* `{os_name}`\n"
                        break
        
        # Kernel
        result = subprocess.run(['uname', '-r'], capture_output=True, text=True, timeout=5)
        msg += f"*Kernel:* `{result.stdout.strip()}`\n"
        
        return msg
    except Exception as e:
        return f"❌ Erreur: {str(e)}"
