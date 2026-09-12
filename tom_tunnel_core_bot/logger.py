#!/usr/bin/env python3
"""
Logger pour le Bot Telegram Tom_tunnel
Gestion des logs et du monitoring
"""

import logging
import os
from datetime import datetime

def setup_logger(name, log_file='/var/log/tom_bot/bot.log'):
    """Configurer le logger"""
    
    # Créer le répertoire s'il n'existe pas
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    
    # Créer le logger
    logger = logging.getLogger(name)
    logger.setLevel(logging.DEBUG)
    
    # Format
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    # File handler
    try:
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
    except Exception as e:
        print(f"Impossible de créer le fichier log: {e}")
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    
    return logger

def log_event(logger, event_type, user_id, message):
    """Enregistrer un événement"""
    log_msg = f"[{event_type}] User: {user_id} - {message}"
    logger.info(log_msg)
