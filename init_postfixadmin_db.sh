#!/bin/bash

################################################################################
# Script d'initialisation de la base de données PostfixAdmin
################################################################################

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# Variables
MYSQL_ROOT_PASSWORD=""
MYSQL_MAIL_PASSWORD=""

# Fonctions d'affichage
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_section() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${WHITE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════${NC}\n"
}

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then 
    print_error "Ce script doit être exécuté en tant que root"
    exit 1
fi

clear
echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║         Initialisation Base de Données PostfixAdmin              ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

print_section "Configuration"

# Demander le mot de passe root MySQL
echo -e -n "${CYAN}Mot de passe root MySQL: ${NC}"
read -rs MYSQL_ROOT_PASSWORD
echo ""

if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    print_error "Le mot de passe root MySQL est requis"
    exit 1
fi

# Demander le mot de passe mailuser
echo -e -n "${CYAN}Mot de passe de l'utilisateur mailuser: ${NC}"
read -rs MYSQL_MAIL_PASSWORD
echo ""

if [ -z "$MYSQL_MAIL_PASSWORD" ]; then
    print_error "Le mot de passe mailuser est requis"
    exit 1
fi

# Vérifier la connexion MySQL root
print_info "Vérification de la connexion MySQL root..."
if ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" &> /dev/null; then
    print_error "Impossible de se connecter à MySQL avec le mot de passe root fourni"
    exit 1
fi
print_success "Connexion MySQL root OK"

print_section "Création des tables PostfixAdmin"

# Créer les tables PostfixAdmin
print_info "Création de la table config..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `config` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(20) NOT NULL DEFAULT '',
  `value` varchar(20) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `config` (`name`, `value`) VALUES ('version', '1843') ON DUPLICATE KEY UPDATE `value` = '1843';
EOF

print_success "Table config créée"

print_info "Création de la table admin..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `admin` (
  `username` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `superadmin` tinyint(1) NOT NULL DEFAULT 0,
  `phone` varchar(30) DEFAULT NULL,
  `email_other` varchar(255) DEFAULT NULL,
  `token` varchar(255) DEFAULT NULL,
  `token_validity` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  PRIMARY KEY (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table admin créée"

print_info "Création de la table alias..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `alias` (
  `address` varchar(255) NOT NULL,
  `goto` text NOT NULL,
  `domain` varchar(255) NOT NULL,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`address`),
  KEY `domain` (`domain`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table alias créée"

print_info "Création de la table alias_domain..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `alias_domain` (
  `alias_domain` varchar(255) NOT NULL,
  `target_domain` varchar(255) NOT NULL,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`alias_domain`),
  KEY `active` (`active`),
  KEY `target_domain` (`target_domain`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table alias_domain créée"

print_info "Création de la table domain..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `domain` (
  `domain` varchar(255) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `aliases` int(10) NOT NULL DEFAULT 0,
  `mailboxes` int(10) NOT NULL DEFAULT 0,
  `maxquota` bigint(20) NOT NULL DEFAULT 0,
  `quota` bigint(20) NOT NULL DEFAULT 0,
  `transport` varchar(255) DEFAULT NULL,
  `backupmx` tinyint(1) NOT NULL DEFAULT 0,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`domain`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table domain créée"

print_info "Création de la table domain_admins..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `domain_admins` (
  `username` varchar(255) NOT NULL,
  `domain` varchar(255) NOT NULL,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table domain_admins créée"

print_info "Création de la table fetchmail..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `fetchmail` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `mailbox` varchar(255) NOT NULL,
  `src_server` varchar(255) NOT NULL,
  `src_auth` enum('password','kerberos_v5','kerberos','kerberos_v4','gssapi','cram-md5','otp','ntlm','msn','ssh','any') DEFAULT NULL,
  `src_user` varchar(255) NOT NULL,
  `src_password` varchar(255) NOT NULL,
  `src_folder` varchar(255) NOT NULL,
  `poll_time` int(11) unsigned NOT NULL DEFAULT 10,
  `fetchall` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `keep` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `protocol` enum('POP3','IMAP','POP2','ETRN','AUTO') DEFAULT NULL,
  `usessl` tinyint(1) unsigned NOT NULL DEFAULT 0,
  `extra_options` text,
  `returned_text` text,
  `mda` varchar(255) NOT NULL,
  `date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table fetchmail créée"

print_info "Création de la table log..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `log` (
  `timestamp` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `username` varchar(255) NOT NULL,
  `domain` varchar(255) NOT NULL,
  `action` varchar(255) NOT NULL,
  `data` text NOT NULL,
  KEY `timestamp` (`timestamp`),
  KEY `domain_timestamp` (`domain`,`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table log créée"

print_info "Création de la table mailbox..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `mailbox` (
  `username` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `maildir` varchar(255) NOT NULL,
  `quota` bigint(20) NOT NULL DEFAULT 0,
  `local_part` varchar(255) NOT NULL,
  `domain` varchar(255) NOT NULL,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `phone` varchar(30) DEFAULT NULL,
  `email_other` varchar(255) DEFAULT NULL,
  `token` varchar(255) DEFAULT NULL,
  `token_validity` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  PRIMARY KEY (`username`),
  KEY `domain` (`domain`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table mailbox créée"

print_info "Création de la table quota..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `quota` (
  `username` varchar(255) NOT NULL,
  `path` varchar(100) NOT NULL,
  `current` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`username`,`path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table quota créée"

print_info "Création de la table quota2..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `quota2` (
  `username` varchar(100) NOT NULL,
  `bytes` bigint(20) NOT NULL DEFAULT 0,
  `messages` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table quota2 créée"

print_info "Création de la table vacation..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `vacation` (
  `email` varchar(255) NOT NULL,
  `subject` varchar(255) DEFAULT NULL,
  `body` text NOT NULL,
  `activefrom` timestamp NOT NULL DEFAULT '2000-01-01 00:00:00',
  `activeuntil` timestamp NOT NULL DEFAULT '2038-01-18 00:00:00',
  `cache` text NOT NULL,
  `domain` varchar(255) NOT NULL,
  `interval_time` int(11) NOT NULL DEFAULT 0,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`email`),
  KEY `email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table vacation créée"

print_info "Création de la table vacation_notification..."
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << 'EOF'
CREATE TABLE IF NOT EXISTS `vacation_notification` (
  `on_vacation` varchar(255) NOT NULL,
  `notified` varchar(255) NOT NULL,
  `notified_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`on_vacation`,`notified`),
  CONSTRAINT `vacation_notification_pkey` FOREIGN KEY (`on_vacation`) REFERENCES `vacation` (`email`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

print_success "Table vacation_notification créée"

# Vérifier que toutes les tables ont été créées
print_info "Vérification des tables..."
TABLE_COUNT=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'mailserver' AND table_name IN ('config', 'admin', 'alias', 'domain', 'mailbox');" 2>/dev/null)

if [ "$TABLE_COUNT" -ge 5 ]; then
    print_success "Toutes les tables principales ont été créées"
else
    print_error "Certaines tables n'ont pas été créées correctement"
    exit 1
fi

print_section "Initialisation terminée"

echo -e "${GREEN}${BOLD}La base de données PostfixAdmin a été initialisée avec succès !${NC}\n"
echo -e "${CYAN}Vous pouvez maintenant accéder à PostfixAdmin pour créer un compte administrateur.${NC}\n"
