#!/bin/bash

################################################################################
# Script d'installation Serveur Mail Postfix/Dovecot pour Debian 13
# Auteur: Script automatisé
# Version: 1.0
# Description: Installation complète d'un serveur mail avec SMTP/IMAP
#              Support des comptes Unix ou MySQL/PostfixAdmin
################################################################################

set -euo pipefail

# Variables globales
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/mail_server_install.log"
ERROR_LOG="${SCRIPT_DIR}/mail_server_errors.log"
STEP_CURRENT=0
STEP_TOTAL=0

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Variables de configuration
DOMAIN=""
HOSTNAME=""
ADMIN_EMAIL=""
AUTH_TYPE=""
MYSQL_ROOT_PASSWORD=""
MYSQL_MAIL_PASSWORD=""
CERT_TYPE=""
CERT_EMAIL=""

################################################################################
# Fonctions d'interface utilisateur
################################################################################

# Afficher le logo
show_logo() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║     ███╗   ███╗ █████╗ ██╗██╗         ███████╗███████╗██████╗    ║
║     ████╗ ████║██╔══██╗██║██║         ██╔════╝██╔════╝██╔══██╗   ║
║     ██╔████╔██║███████║██║██║         ███████╗█████╗  ██████╔╝   ║
║     ██║╚██╔╝██║██╔══██║██║██║         ╚════██║██╔══╝  ██╔══██╗   ║
║     ██║ ╚═╝ ██║██║  ██║██║███████╗    ███████║███████╗██║  ██║   ║
║     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚══════╝    ╚══════╝╚══════╝╚═╝  ╚═╝   ║
║                                                                   ║
║              Installation Postfix/Dovecot - Debian 13            ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Afficher un titre de section
print_section() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${WHITE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════${NC}\n"
}

# Afficher une étape
print_step() {
    STEP_CURRENT=$((STEP_CURRENT + 1))
    echo -e "${BOLD}${CYAN}[Étape ${STEP_CURRENT}/${STEP_TOTAL}]${NC} $1"
}

# Afficher un message de succès
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Afficher un message d'erreur
print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Afficher un message d'avertissement
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Afficher un message d'information
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Barre de progression
progress_bar() {
    local duration=$1
    local width=50
    local progress=0
    local filled=0
    
    while [ $progress -le 100 ]; do
        filled=$((progress * width / 100))
        printf "\r${CYAN}["
        printf "%${filled}s" | tr ' ' '█'
        printf "%$((width - filled))s" | tr ' ' '░'
        printf "]${NC} ${WHITE}%3d%%${NC}" $progress
        progress=$((progress + 2))
        sleep $(echo "scale=3; $duration / 50" | bc)
    done
    echo ""
}

# Spinner d'attente
spinner() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r${CYAN}${spin:$i:1}${NC} ${message}..."
        sleep 0.1
    done
    printf "\r"
}

# Demander une confirmation
confirm() {
    local message=$1
    local response
    
    while true; do
        echo -e -n "${YELLOW}${message} [o/n]: ${NC}"
        read -r response
        case $response in
            [oO]|[oO][uU][iI])
                return 0
                ;;
            [nN]|[nN][oO][nN])
                return 1
                ;;
            *)
                print_error "Réponse invalide. Veuillez répondre par 'o' ou 'n'."
                ;;
        esac
    done
}

# Demander une entrée utilisateur
ask_input() {
    local prompt=$1
    local var_name=$2
    local default=$3
    local value
    
    if [ -n "$default" ]; then
        echo -e -n "${CYAN}${prompt} [${default}]: ${NC}"
    else
        echo -e -n "${CYAN}${prompt}: ${NC}"
    fi
    
    read -r value
    
    if [ -z "$value" ] && [ -n "$default" ]; then
        value=$default
    fi
    
    eval "$var_name='$value'"
}

# Demander un mot de passe
ask_password() {
    local prompt=$1
    local var_name=$2
    local password
    local password_confirm
    
    while true; do
        echo -e -n "${CYAN}${prompt}: ${NC}"
        read -rs password
        echo ""
        
        if [ -z "$password" ]; then
            print_error "Le mot de passe ne peut pas être vide."
            continue
        fi
        
        echo -e -n "${CYAN}Confirmez le mot de passe: ${NC}"
        read -rs password_confirm
        echo ""
        
        if [ "$password" = "$password_confirm" ]; then
            eval "$var_name='$password'"
            break
        else
            print_error "Les mots de passe ne correspondent pas. Réessayez."
        fi
    done
}

################################################################################
# Fonctions de gestion des erreurs et logs
################################################################################

# Initialiser les logs
init_logs() {
    echo "=== Installation du serveur mail - $(date) ===" > "$LOG_FILE"
    echo "=== Erreurs d'installation - $(date) ===" > "$ERROR_LOG"
}

# Logger une commande
log_command() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Exécuter une commande avec gestion d'erreur
execute_command() {
    local cmd=$1
    local error_msg=$2
    
    log_command "Exécution: $cmd"
    
    if eval "$cmd" >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
        return 0
    else
        print_error "$error_msg"
        echo "[ERREUR] $error_msg" >> "$ERROR_LOG"
        echo "Commande: $cmd" >> "$ERROR_LOG"
        return 1
    fi
}

# Afficher les logs d'erreur et quitter
exit_with_error() {
    local message=$1
    
    print_error "$message"
    echo ""
    print_warning "Affichage des dernières erreurs:"
    echo -e "${RED}"
    tail -n 20 "$ERROR_LOG"
    echo -e "${NC}"
    
    echo ""
    print_info "Logs complets disponibles dans:"
    echo "  - $LOG_FILE"
    echo "  - $ERROR_LOG"
    
    exit 1
}

################################################################################
# Fonctions de vérification
################################################################################

# Vérifier que le script est exécuté en root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Ce script doit être exécuté en tant que root."
        exit 1
    fi
}

# Vérifier la version de Debian
check_debian_version() {
    if [ ! -f /etc/debian_version ]; then
        print_error "Ce script est conçu pour Debian uniquement."
        exit 1
    fi
    
    local version
    version=$(cat /etc/debian_version | cut -d. -f1)
    
    if [ "$version" -lt 12 ]; then
        print_warning "Ce script est optimisé pour Debian 13, mais peut fonctionner sur Debian 12+."
        if ! confirm "Voulez-vous continuer?"; then
            exit 0
        fi
    fi
}

# Vérifier la connectivité Internet
check_internet() {
    print_info "Vérification de la connectivité Internet..."
    
    if ! ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        print_error "Pas de connexion Internet détectée."
        exit 1
    fi
    
    print_success "Connexion Internet OK"
}

# Valider un nom de domaine
validate_domain() {
    local domain=$1
    
    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    
    return 0
}

# Valider une adresse email
validate_email() {
    local email=$1
    
    if [[ ! $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    
    return 0
}

################################################################################
# Fonctions de collecte d'informations
################################################################################

collect_information() {
    print_section "Configuration du serveur mail"
    
    # Nom de domaine
    while true; do
        ask_input "Nom de domaine principal (ex: example.com)" DOMAIN ""
        
        if [ -z "$DOMAIN" ]; then
            print_error "Le nom de domaine est obligatoire."
            continue
        fi
        
        if ! validate_domain "$DOMAIN"; then
            print_error "Nom de domaine invalide."
            continue
        fi
        
        break
    done
    
    # Hostname
    local current_hostname
    current_hostname=$(hostname -f 2>/dev/null || hostname)
    ask_input "Nom d'hôte du serveur (FQDN)" HOSTNAME "mail.${DOMAIN}"
    
    # Email administrateur
    while true; do
        ask_input "Adresse email de l'administrateur" ADMIN_EMAIL "admin@${DOMAIN}"
        
        if ! validate_email "$ADMIN_EMAIL"; then
            print_error "Adresse email invalide."
            continue
        fi
        
        break
    done
    
    # Type d'authentification
    echo ""
    print_info "Choisissez le type d'authentification:"
    echo "  1) Comptes Unix (utilisateurs système)"
    echo "  2) Base de données MySQL (avec PostfixAdmin)"
    
    while true; do
        echo -e -n "${CYAN}Votre choix [1-2]: ${NC}"
        read -r choice
        
        case $choice in
            1)
                AUTH_TYPE="unix"
                print_success "Authentification par comptes Unix sélectionnée"
                break
                ;;
            2)
                AUTH_TYPE="mysql"
                print_success "Authentification par MySQL sélectionnée"
                
                # Mots de passe MySQL
                echo ""
                ask_password "Mot de passe root MySQL" MYSQL_ROOT_PASSWORD
                ask_password "Mot de passe pour l'utilisateur mail MySQL" MYSQL_MAIL_PASSWORD
                break
                ;;
            *)
                print_error "Choix invalide."
                ;;
        esac
    done
    
    # Type de certificat
    echo ""
    print_info "Configuration des certificats TLS:"
    echo "  1) Let's Encrypt (certificat gratuit, automatique)"
    echo "  2) Certificat auto-signé (pour tests)"
    
    while true; do
        echo -e -n "${CYAN}Votre choix [1-2]: ${NC}"
        read -r choice
        
        case $choice in
            1)
                CERT_TYPE="letsencrypt"
                print_success "Let's Encrypt sélectionné"
                
                while true; do
                    ask_input "Email pour Let's Encrypt" CERT_EMAIL "$ADMIN_EMAIL"
                    
                    if ! validate_email "$CERT_EMAIL"; then
                        print_error "Adresse email invalide."
                        continue
                    fi
                    
                    break
                done
                
                print_warning "Assurez-vous que le domaine $HOSTNAME pointe vers ce serveur!"
                sleep 2
                break
                ;;
            2)
                CERT_TYPE="selfsigned"
                print_success "Certificat auto-signé sélectionné"
                break
                ;;
            *)
                print_error "Choix invalide."
                ;;
        esac
    done
    
    # Récapitulatif
    echo ""
    print_section "Récapitulatif de la configuration"
    echo -e "${WHITE}Domaine:${NC}              $DOMAIN"
    echo -e "${WHITE}Hostname:${NC}             $HOSTNAME"
    echo -e "${WHITE}Email admin:${NC}          $ADMIN_EMAIL"
    echo -e "${WHITE}Authentification:${NC}     $AUTH_TYPE"
    echo -e "${WHITE}Certificats:${NC}          $CERT_TYPE"
    echo ""
    
    if ! confirm "Confirmer et démarrer l'installation?"; then
        print_warning "Installation annulée."
        exit 0
    fi
}

################################################################################
# Fonctions d'installation
################################################################################

# Mettre à jour le système
update_system() {
    print_step "Mise à jour du système"
    
    execute_command "apt-get update" "Échec de la mise à jour des paquets" || exit_with_error "Impossible de mettre à jour le système"
    
    print_info "Installation des paquets de base..."
    execute_command "DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common bc" \
        "Échec de l'installation des paquets de base" || exit_with_error "Impossible d'installer les paquets de base"
    
    print_success "Système mis à jour"
}

# Configurer le hostname
configure_hostname() {
    print_step "Configuration du hostname"
    
    execute_command "hostnamectl set-hostname $HOSTNAME" "Échec de la configuration du hostname" || exit_with_error "Impossible de configurer le hostname"
    
    # Mettre à jour /etc/hosts
    if ! grep -q "$HOSTNAME" /etc/hosts; then
        echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
    fi
    
    print_success "Hostname configuré: $HOSTNAME"
}

# Installer Postfix
install_postfix() {
    print_step "Installation de Postfix"
    
    # Préconfigurer Postfix
    execute_command "echo 'postfix postfix/main_mailer_type select Internet Site' | debconf-set-selections" \
        "Échec de la préconfiguration Postfix" || exit_with_error "Erreur de préconfiguration Postfix"
    
    execute_command "echo 'postfix postfix/mailname string $DOMAIN' | debconf-set-selections" \
        "Échec de la préconfiguration Postfix" || exit_with_error "Erreur de préconfiguration Postfix"
    
    print_info "Installation de Postfix..."
    execute_command "DEBIAN_FRONTEND=noninteractive apt-get install -y postfix postfix-mysql" \
        "Échec de l'installation de Postfix" || exit_with_error "Impossible d'installer Postfix"
    
    print_success "Postfix installé"
}

# Configurer Postfix pour comptes Unix
configure_postfix_unix() {
    print_step "Configuration de Postfix (comptes Unix)"
    
    # Backup de la configuration
    execute_command "cp /etc/postfix/main.cf /etc/postfix/main.cf.backup" \
        "Échec du backup de main.cf" || print_warning "Impossible de sauvegarder main.cf"
    
    # Configuration principale
    cat > /etc/postfix/main.cf << EOF
# Configuration Postfix - Comptes Unix
# Généré automatiquement le $(date)

# Paramètres de base
smtpd_banner = \$myhostname ESMTP
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 3.6

# Paramètres réseau
myhostname = $HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain
mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain
relayhost = 
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all

# Boîtes aux lettres
home_mailbox = Maildir/
mailbox_command = 

# TLS/SSL - Paramètres de base (à compléter)
smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key
smtpd_tls_security_level = may
smtpd_tls_auth_only = yes
smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtpd_tls_ciphers = high
smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtpd_tls_mandatory_ciphers = high

smtp_tls_security_level = may
smtp_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtp_tls_ciphers = high

# Authentification SASL
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = \$mydomain
broken_sasl_auth_clients = yes

# Restrictions
smtpd_helo_required = yes
smtpd_helo_restrictions = 
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_invalid_helo_hostname,
    reject_non_fqdn_helo_hostname

smtpd_sender_restrictions = 
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_non_fqdn_sender,
    reject_unknown_sender_domain

smtpd_recipient_restrictions = 
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_non_fqdn_recipient,
    reject_unknown_recipient_domain,
    reject_unauth_destination,
    reject_rbl_client zen.spamhaus.org,
    reject_rbl_client bl.spamcop.net

smtpd_data_restrictions = 
    reject_unauth_pipelining

# Limites
message_size_limit = 52428800
mailbox_size_limit = 0
smtpd_client_connection_count_limit = 10
smtpd_client_connection_rate_limit = 30
EOF

    # Configuration de master.cf
    cat > /etc/postfix/master.cf << EOF
# Postfix master process configuration file
smtp      inet  n       -       y       -       -       smtpd
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_helo_restrictions=
  -o smtpd_sender_restrictions=
  -o smtpd_recipient_restrictions=
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_helo_restrictions=
  -o smtpd_sender_restrictions=
  -o smtpd_recipient_restrictions=
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
EOF

    print_success "Postfix configuré pour comptes Unix"
}

# Installer et configurer MySQL
install_mysql() {
    print_step "Installation de MySQL"
    
    print_info "Installation de MariaDB..."
    execute_command "DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client" \
        "Échec de l'installation de MariaDB" || exit_with_error "Impossible d'installer MariaDB"
    
    execute_command "systemctl start mariadb" "Échec du démarrage de MariaDB" || exit_with_error "Impossible de démarrer MariaDB"
    execute_command "systemctl enable mariadb" "Échec de l'activation de MariaDB" || print_warning "Impossible d'activer MariaDB au démarrage"
    
    print_success "MySQL installé"
}

# Configurer la base de données mail
configure_mail_database() {
    print_step "Configuration de la base de données mail"
    
    # Sécuriser MySQL
    print_info "Sécurisation de MySQL..."
    mysql -e "UPDATE mysql.user SET Password=PASSWORD('${MYSQL_ROOT_PASSWORD}') WHERE User='root';" 2>> "$ERROR_LOG" || true
    mysql -e "DELETE FROM mysql.user WHERE User='';" 2>> "$ERROR_LOG" || true
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>> "$ERROR_LOG" || true
    mysql -e "DROP DATABASE IF EXISTS test;" 2>> "$ERROR_LOG" || true
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>> "$ERROR_LOG" || true
    mysql -e "FLUSH PRIVILEGES;" 2>> "$ERROR_LOG" || true
    
    # Créer la base de données et l'utilisateur
    print_info "Création de la base de données mail..."
    
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" << EOF 2>> "$ERROR_LOG"
CREATE DATABASE IF NOT EXISTS mailserver CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'mailuser'@'localhost' IDENTIFIED BY '${MYSQL_MAIL_PASSWORD}';
GRANT ALL PRIVILEGES ON mailserver.* TO 'mailuser'@'localhost';
FLUSH PRIVILEGES;
EOF

    if [ $? -ne 0 ]; then
        exit_with_error "Échec de la création de la base de données"
    fi
    
    # Créer les tables
    print_info "Création des tables..."
    
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << EOF 2>> "$ERROR_LOG"
CREATE TABLE IF NOT EXISTS virtual_domains (
    id INT NOT NULL AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS virtual_users (
    id INT NOT NULL AUTO_INCREMENT,
    domain_id INT NOT NULL,
    email VARCHAR(255) NOT NULL,
    password VARCHAR(255) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY email (email),
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS virtual_aliases (
    id INT NOT NULL AUTO_INCREMENT,
    domain_id INT NOT NULL,
    source VARCHAR(255) NOT NULL,
    destination VARCHAR(255) NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO virtual_domains (name) VALUES ('${DOMAIN}');
EOF

    if [ $? -ne 0 ]; then
        exit_with_error "Échec de la création des tables"
    fi
    
    print_success "Base de données configurée"
}

# Configurer Postfix pour MySQL
configure_postfix_mysql() {
    print_step "Configuration de Postfix (MySQL)"
    
    # Backup de la configuration
    execute_command "cp /etc/postfix/main.cf /etc/postfix/main.cf.backup" \
        "Échec du backup de main.cf" || print_warning "Impossible de sauvegarder main.cf"
    
    # Créer les fichiers de requêtes MySQL
    cat > /etc/postfix/mysql-virtual-mailbox-domains.cf << EOF
user = mailuser
password = ${MYSQL_MAIL_PASSWORD}
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s'
EOF

    cat > /etc/postfix/mysql-virtual-mailbox-maps.cf << EOF
user = mailuser
password = ${MYSQL_MAIL_PASSWORD}
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_users WHERE email='%s'
EOF

    cat > /etc/postfix/mysql-virtual-alias-maps.cf << EOF
user = mailuser
password = ${MYSQL_MAIL_PASSWORD}
hosts = 127.0.0.1
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s'
EOF

    chmod 640 /etc/postfix/mysql-*.cf
    chown root:postfix /etc/postfix/mysql-*.cf
    
    # Configuration principale
    cat > /etc/postfix/main.cf << EOF
# Configuration Postfix - MySQL
# Généré automatiquement le $(date)

# Paramètres de base
smtpd_banner = \$myhostname ESMTP
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 3.6

# Paramètres réseau
myhostname = $HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain
mydestination = localhost
relayhost = 
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all

# Domaines et boîtes virtuelles
virtual_mailbox_domains = mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf
virtual_mailbox_maps = mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf
virtual_alias_maps = mysql:/etc/postfix/mysql-virtual-alias-maps.cf
virtual_mailbox_base = /var/mail/vhosts
virtual_minimum_uid = 100
virtual_uid_maps = static:5000
virtual_gid_maps = static:5000

# TLS/SSL - Paramètres de base (à compléter)
smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key
smtpd_tls_security_level = may
smtpd_tls_auth_only = yes
smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtpd_tls_ciphers = high
smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtpd_tls_mandatory_ciphers = high

smtp_tls_security_level = may
smtp_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtp_tls_ciphers = high

# Authentification SASL
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = \$mydomain
broken_sasl_auth_clients = yes

# Restrictions
smtpd_helo_required = yes
smtpd_helo_restrictions = 
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_invalid_helo_hostname,
    reject_non_fqdn_helo_hostname

smtpd_sender_restrictions = 
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_non_fqdn_sender,
    reject_unknown_sender_domain

smtpd_recipient_restrictions = 
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_non_fqdn_recipient,
    reject_unknown_recipient_domain,
    reject_unauth_destination,
    reject_rbl_client zen.spamhaus.org,
    reject_rbl_client bl.spamcop.net

smtpd_data_restrictions = 
    reject_unauth_pipelining

# Limites
message_size_limit = 52428800
mailbox_size_limit = 0
smtpd_client_connection_count_limit = 10
smtpd_client_connection_rate_limit = 30
EOF

    # Utiliser le même master.cf que pour Unix
    cat > /etc/postfix/master.cf << EOF
# Postfix master process configuration file
smtp      inet  n       -       y       -       -       smtpd
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_helo_restrictions=
  -o smtpd_sender_restrictions=
  -o smtpd_recipient_restrictions=
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_helo_restrictions=
  -o smtpd_sender_restrictions=
  -o smtpd_recipient_restrictions=
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
EOF

    # Créer le répertoire pour les boîtes virtuelles
    mkdir -p /var/mail/vhosts/${DOMAIN}
    groupadd -g 5000 vmail 2>/dev/null || true
    useradd -g vmail -u 5000 vmail -d /var/mail -s /usr/sbin/nologin 2>/dev/null || true
    chown -R vmail:vmail /var/mail/vhosts
    chmod -R 770 /var/mail/vhosts
    
    print_success "Postfix configuré pour MySQL"
}

# Installer Dovecot
install_dovecot() {
    print_step "Installation de Dovecot"
    
    print_info "Installation de Dovecot..."
    
    if [ "$AUTH_TYPE" = "mysql" ]; then
        execute_command "DEBIAN_FRONTEND=noninteractive apt-get install -y dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-mysql" \
            "Échec de l'installation de Dovecot" || exit_with_error "Impossible d'installer Dovecot"
    else
        execute_command "DEBIAN_FRONTEND=noninteractive apt-get install -y dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd" \
            "Échec de l'installation de Dovecot" || exit_with_error "Impossible d'installer Dovecot"
    fi
    
    print_success "Dovecot installé"
}

# Configurer Dovecot pour comptes Unix
configure_dovecot_unix() {
    print_step "Configuration de Dovecot (comptes Unix)"
    
    # Backup des configurations
    cp -r /etc/dovecot /etc/dovecot.backup 2>/dev/null || true
    
    # Configuration principale
    cat > /etc/dovecot/dovecot.conf << EOF
# Configuration Dovecot - Comptes Unix
# Généré automatiquement le $(date)

protocols = imap pop3 lmtp
listen = *, ::
dict {
}
!include conf.d/*.conf
!include_try local.conf
EOF

    # Configuration 10-auth.conf
    cat > /etc/dovecot/conf.d/10-auth.conf << EOF
disable_plaintext_auth = yes
auth_mechanisms = plain login
!include auth-system.conf.ext
EOF

    # Configuration 10-mail.conf
    cat > /etc/dovecot/conf.d/10-mail.conf << EOF
mail_location = maildir:~/Maildir
namespace inbox {
  inbox = yes
}
mail_privileged_group = mail
protocol !indexer-worker {
}
EOF

    # Configuration 10-master.conf
    cat > /etc/dovecot/conf.d/10-master.conf << EOF
service imap-login {
  inet_listener imap {
    port = 143
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}

service pop3-login {
  inet_listener pop3 {
    port = 110
  }
  inet_listener pop3s {
    port = 995
    ssl = yes
  }
}

service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
  unix_listener auth-userdb {
    mode = 0600
    user = vmail
  }
  user = dovecot
}

service auth-worker {
  user = root
}

service dict {
  unix_listener dict {
  }
}
EOF

    # Configuration 10-ssl.conf (temporaire)
    cat > /etc/dovecot/conf.d/10-ssl.conf << EOF
ssl = required
ssl_cert = </etc/ssl/certs/ssl-cert-snakeoil.pem
ssl_key = </etc/ssl/private/ssl-cert-snakeoil.key
ssl_min_protocol = TLSv1.2
ssl_cipher_list = HIGH:!aNULL:!MD5
ssl_prefer_server_ciphers = yes
EOF

    print_success "Dovecot configuré pour comptes Unix"
}

# Configurer Dovecot pour MySQL
configure_dovecot_mysql() {
    print_step "Configuration de Dovecot (MySQL)"
    
    # Backup des configurations
    cp -r /etc/dovecot /etc/dovecot.backup 2>/dev/null || true
    
    # Configuration principale
    cat > /etc/dovecot/dovecot.conf << EOF
# Configuration Dovecot - MySQL
# Généré automatiquement le $(date)

protocols = imap pop3 lmtp
listen = *, ::
dict {
}
!include conf.d/*.conf
!include_try local.conf
EOF

    # Configuration 10-auth.conf
    cat > /etc/dovecot/conf.d/10-auth.conf << EOF
disable_plaintext_auth = yes
auth_mechanisms = plain login
!include auth-sql.conf.ext
EOF

    # Configuration auth-sql.conf.ext
    cat > /etc/dovecot/conf.d/auth-sql.conf.ext << EOF
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
}
EOF

    # Configuration dovecot-sql.conf.ext
    cat > /etc/dovecot/dovecot-sql.conf.ext << EOF
driver = mysql
connect = host=127.0.0.1 dbname=mailserver user=mailuser password=${MYSQL_MAIL_PASSWORD}
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email as user, password FROM virtual_users WHERE email='%u';
EOF

    chmod 640 /etc/dovecot/dovecot-sql.conf.ext
    chown root:dovecot /etc/dovecot/dovecot-sql.conf.ext
    
    # Configuration 10-mail.conf
    cat > /etc/dovecot/conf.d/10-mail.conf << EOF
mail_location = maildir:/var/mail/vhosts/%d/%n
namespace inbox {
  inbox = yes
}
mail_privileged_group = mail
protocol !indexer-worker {
}
first_valid_uid = 5000
last_valid_uid = 5000
first_valid_gid = 5000
last_valid_gid = 5000
EOF

    # Configuration 10-master.conf (identique à Unix)
    cat > /etc/dovecot/conf.d/10-master.conf << EOF
service imap-login {
  inet_listener imap {
    port = 143
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}

service pop3-login {
  inet_listener pop3 {
    port = 110
  }
  inet_listener pop3s {
    port = 995
    ssl = yes
  }
}

service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
  unix_listener auth-userdb {
    mode = 0600
    user = vmail
  }
  user = dovecot
}

service auth-worker {
  user = vmail
}

service dict {
  unix_listener dict {
  }
}
EOF

    # Configuration 10-ssl.conf (temporaire)
    cat > /etc/dovecot/conf.d/10-ssl.conf << EOF
ssl = required
ssl_cert = </etc/ssl/certs/ssl-cert-snakeoil.pem
ssl_key = </etc/ssl/private/ssl-cert-snakeoil.key
ssl_min_protocol = TLSv1.2
ssl_cipher_list = HIGH:!aNULL:!MD5
ssl_prefer_server_ciphers = yes
EOF

    print_success "Dovecot configuré pour MySQL"
}

# Installer les certificats Let's Encrypt
install_letsencrypt() {
    print_step "Installation des certificats Let's Encrypt"
    
    print_info "Installation de Certbot..."
    execute_command "DEBIAN_FRONTEND=noninteractive apt-get install -y certbot" \
        "Échec de l'installation de Certbot" || exit_with_error "Impossible d'installer Certbot"
    
    print_info "Obtention du certificat pour $HOSTNAME..."
    
    # Arrêter temporairement les services qui utilisent les ports 80/443
    systemctl stop postfix dovecot 2>/dev/null || true
    
    if certbot certonly --standalone --non-interactive --agree-tos --email "$CERT_EMAIL" -d "$HOSTNAME" >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
        print_success "Certificat Let's Encrypt obtenu"
        
        # Mettre à jour les configurations
        sed -i "s|/etc/ssl/certs/ssl-cert-snakeoil.pem|/etc/letsencrypt/live/${HOSTNAME}/fullchain.pem|g" /etc/postfix/main.cf
        sed -i "s|/etc/ssl/private/ssl-cert-snakeoil.key|/etc/letsencrypt/live/${HOSTNAME}/privkey.pem|g" /etc/postfix/main.cf
        
        sed -i "s|/etc/ssl/certs/ssl-cert-snakeoil.pem|/etc/letsencrypt/live/${HOSTNAME}/fullchain.pem|g" /etc/dovecot/conf.d/10-ssl.conf
        sed -i "s|/etc/ssl/private/ssl-cert-snakeoil.key|/etc/letsencrypt/live/${HOSTNAME}/privkey.pem|g" /etc/dovecot/conf.d/10-ssl.conf
        
        # Configurer le renouvellement automatique
        cat > /etc/cron.d/certbot-renew << EOF
0 3 * * * root certbot renew --quiet --post-hook "systemctl reload postfix dovecot"
EOF
        
    else
        print_error "Échec de l'obtention du certificat Let's Encrypt"
        print_warning "Utilisation des certificats auto-signés à la place"
        CERT_TYPE="selfsigned"
        install_selfsigned_cert
    fi
    
    # Redémarrer les services
    systemctl start postfix dovecot 2>/dev/null || true
}

# Installer un certificat auto-signé
install_selfsigned_cert() {
    print_step "Installation d'un certificat auto-signé"
    
    local cert_dir="/etc/ssl/mailserver"
    mkdir -p "$cert_dir"
    
    print_info "Génération du certificat..."
    
    openssl req -new -x509 -days 3650 -nodes \
        -out "${cert_dir}/cert.pem" \
        -keyout "${cert_dir}/key.pem" \
        -subj "/C=FR/ST=France/L=Paris/O=Mail Server/OU=IT/CN=${HOSTNAME}" \
        >> "$LOG_FILE" 2>> "$ERROR_LOG"
    
    if [ $? -eq 0 ]; then
        chmod 644 "${cert_dir}/cert.pem"
        chmod 600 "${cert_dir}/key.pem"
        
        # Mettre à jour les configurations
        sed -i "s|/etc/ssl/certs/ssl-cert-snakeoil.pem|${cert_dir}/cert.pem|g" /etc/postfix/main.cf
        sed -i "s|/etc/ssl/private/ssl-cert-snakeoil.key|${cert_dir}/key.pem|g" /etc/postfix/main.cf
        
        sed -i "s|/etc/ssl/certs/ssl-cert-snakeoil.pem|${cert_dir}/cert.pem|g" /etc/dovecot/conf.d/10-ssl.conf
        sed -i "s|/etc/ssl/private/ssl-cert-snakeoil.key|${cert_dir}/key.pem|g" /etc/dovecot/conf.d/10-ssl.conf
        
        print_success "Certificat auto-signé installé"
        print_warning "Ce certificat n'est pas approuvé par une autorité de certification"
    else
        exit_with_error "Échec de la génération du certificat auto-signé"
    fi
}

# Installer PostfixAdmin
install_postfixadmin() {
    print_step "Installation de PostfixAdmin"
    
    print_info "Installation des dépendances..."
    execute_command "DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 php php-mysql php-imap php-mbstring php-curl libapache2-mod-php" \
        "Échec de l'installation des dépendances" || exit_with_error "Impossible d'installer les dépendances de PostfixAdmin"
    
    print_info "Téléchargement de PostfixAdmin..."
    cd /tmp
    
    if ! wget -q https://github.com/postfixadmin/postfixadmin/archive/postfixadmin-3.3.13.tar.gz -O postfixadmin.tar.gz >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
        print_warning "Échec du téléchargement de PostfixAdmin depuis GitHub"
        print_info "Tentative avec une version alternative..."
        
        # Version de secours
        if ! wget -q https://sourceforge.net/projects/postfixadmin/files/postfixadmin/postfixadmin-3.3.13/postfixadmin-3.3.13.tar.gz -O postfixadmin.tar.gz >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
            print_error "Impossible de télécharger PostfixAdmin"
            print_warning "PostfixAdmin ne sera pas installé, mais le serveur mail fonctionnera"
            return 0
        fi
    fi
    
    tar -xzf postfixadmin.tar.gz
    mv postfixadmin-* /var/www/html/postfixadmin
    
    # Configuration de PostfixAdmin
    cd /var/www/html/postfixadmin
    
    cat > config.local.php << EOF
<?php
\$CONF['configured'] = true;
\$CONF['database_type'] = 'mysqli';
\$CONF['database_host'] = 'localhost';
\$CONF['database_user'] = 'mailuser';
\$CONF['database_password'] = '${MYSQL_MAIL_PASSWORD}';
\$CONF['database_name'] = 'mailserver';
\$CONF['encrypt'] = 'sha512crypt';
\$CONF['default_aliases'] = array (
    'abuse' => 'abuse@${DOMAIN}',
    'hostmaster' => 'hostmaster@${DOMAIN}',
    'postmaster' => 'postmaster@${DOMAIN}',
    'webmaster' => 'webmaster@${DOMAIN}'
);
\$CONF['domain_path'] = 'YES';
\$CONF['domain_in_mailbox'] = 'NO';
?>
EOF

    mkdir -p templates_c
    chown -R www-data:www-data /var/www/html/postfixadmin
    chmod -R 755 /var/www/html/postfixadmin
    
    # Configuration Apache
    cat > /etc/apache2/sites-available/postfixadmin.conf << EOF
<VirtualHost *:80>
    ServerName ${HOSTNAME}
    DocumentRoot /var/www/html/postfixadmin/public
    
    <Directory /var/www/html/postfixadmin/public>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/postfixadmin_error.log
    CustomLog \${APACHE_LOG_DIR}/postfixadmin_access.log combined
</VirtualHost>
EOF

    a2ensite postfixadmin.conf >> "$LOG_FILE" 2>> "$ERROR_LOG"
    a2enmod rewrite >> "$LOG_FILE" 2>> "$ERROR_LOG"
    systemctl restart apache2 >> "$LOG_FILE" 2>> "$ERROR_LOG"
    
    print_success "PostfixAdmin installé"
    print_info "Accès: http://${HOSTNAME}/setup.php"
}

# Démarrer et activer les services
start_services() {
    print_step "Démarrage des services"
    
    print_info "Redémarrage de Postfix..."
    if systemctl restart postfix >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
        systemctl enable postfix >> "$LOG_FILE" 2>> "$ERROR_LOG"
        print_success "Postfix démarré"
    else
        exit_with_error "Échec du démarrage de Postfix"
    fi
    
    print_info "Redémarrage de Dovecot..."
    if systemctl restart dovecot >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
        systemctl enable dovecot >> "$LOG_FILE" 2>> "$ERROR_LOG"
        print_success "Dovecot démarré"
    else
        exit_with_error "Échec du démarrage de Dovecot"
    fi
}

################################################################################
# Fonctions de test
################################################################################

# Tester la configuration
test_configuration() {
    print_section "Tests de configuration"
    
    local all_tests_passed=true
    
    # Test 1: Postfix
    print_info "Test de la configuration Postfix..."
    if postfix check >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
        print_success "Configuration Postfix valide"
    else
        print_error "Configuration Postfix invalide"
        all_tests_passed=false
    fi
    
    # Test 2: Dovecot
    print_info "Test de la configuration Dovecot..."
    if doveconf > /dev/null 2>> "$ERROR_LOG"; then
        print_success "Configuration Dovecot valide"
    else
        print_error "Configuration Dovecot invalide"
        all_tests_passed=false
    fi
    
    # Test 3: Ports
    print_info "Test des ports réseau..."
    local ports_ok=true
    
    for port in 25 587 465 143 993; do
        if ss -tuln | grep -q ":${port} "; then
            print_success "Port $port ouvert"
        else
            print_error "Port $port non accessible"
            ports_ok=false
            all_tests_passed=false
        fi
    done
    
    # Test 4: Certificats
    print_info "Test des certificats TLS..."
    if [ "$CERT_TYPE" = "letsencrypt" ]; then
        if [ -f "/etc/letsencrypt/live/${HOSTNAME}/fullchain.pem" ]; then
            print_success "Certificat Let's Encrypt présent"
        else
            print_error "Certificat Let's Encrypt manquant"
            all_tests_passed=false
        fi
    else
        if [ -f "/etc/ssl/mailserver/cert.pem" ]; then
            print_success "Certificat auto-signé présent"
        else
            print_error "Certificat auto-signé manquant"
            all_tests_passed=false
        fi
    fi
    
    # Test 5: Authentification SMTP
    print_info "Test de l'authentification SMTP..."
    if echo "EHLO test" | nc localhost 587 2>/dev/null | grep -q "250-AUTH"; then
        print_success "Authentification SMTP disponible"
    else
        print_warning "Authentification SMTP non détectée (peut être normal)"
    fi
    
    # Test 6: MySQL (si applicable)
    if [ "$AUTH_TYPE" = "mysql" ]; then
        print_info "Test de la connexion MySQL..."
        if mysql -u mailuser -p"${MYSQL_MAIL_PASSWORD}" -e "USE mailserver;" >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
            print_success "Connexion MySQL OK"
        else
            print_error "Échec de la connexion MySQL"
            all_tests_passed=false
        fi
    fi
    
    echo ""
    if [ "$all_tests_passed" = true ]; then
        print_success "Tous les tests sont passés avec succès!"
        return 0
    else
        print_warning "Certains tests ont échoué. Vérifiez les logs pour plus de détails."
        return 1
    fi
}

# Afficher le résumé final
show_summary() {
    print_section "Installation terminée!"
    
    echo -e "${GREEN}${BOLD}✓ Le serveur mail est installé et configuré${NC}\n"
    
    echo -e "${WHITE}${BOLD}Informations du serveur:${NC}"
    echo -e "  ${CYAN}Domaine:${NC}              $DOMAIN"
    echo -e "  ${CYAN}Hostname:${NC}             $HOSTNAME"
    echo -e "  ${CYAN}Type d'auth:${NC}          $AUTH_TYPE"
    echo -e "  ${CYAN}Certificats:${NC}          $CERT_TYPE"
    
    echo -e "\n${WHITE}${BOLD}Ports ouverts:${NC}"
    echo -e "  ${CYAN}SMTP:${NC}                 25 (réception)"
    echo -e "  ${CYAN}Submission:${NC}           587 (envoi avec auth)"
    echo -e "  ${CYAN}SMTPS:${NC}                465 (envoi SSL)"
    echo -e "  ${CYAN}IMAP:${NC}                 143"
    echo -e "  ${CYAN}IMAPS:${NC}                993 (SSL)"
    echo -e "  ${CYAN}POP3:${NC}                 110"
    echo -e "  ${CYAN}POP3S:${NC}                995 (SSL)"
    
    if [ "$AUTH_TYPE" = "unix" ]; then
        echo -e "\n${WHITE}${BOLD}Création d'un utilisateur mail:${NC}"
        echo -e "  ${YELLOW}sudo adduser nomutilisateur${NC}"
        echo -e "  L'utilisateur pourra se connecter avec son login système"
        
    else
        echo -e "\n${WHITE}${BOLD}PostfixAdmin:${NC}"
        echo -e "  ${CYAN}URL:${NC}                  http://${HOSTNAME}/setup.php"
        echo -e "  ${CYAN}Base de données:${NC}      mailserver"
        echo -e "  ${CYAN}Utilisateur DB:${NC}       mailuser"
        
        echo -e "\n${WHITE}${BOLD}Création manuelle d'un utilisateur mail:${NC}"
        echo -e "  ${YELLOW}# Générer un hash de mot de passe${NC}"
        echo -e "  ${YELLOW}doveadm pw -s SHA512-CRYPT${NC}"
        echo -e ""
        echo -e "  ${YELLOW}# Insérer dans la base${NC}"
        echo -e "  ${YELLOW}mysql -u root -p mailserver${NC}"
        echo -e "  ${YELLOW}INSERT INTO virtual_users (domain_id, email, password)${NC}"
        echo -e "  ${YELLOW}VALUES (1, 'user@${DOMAIN}', 'HASH_DU_MOT_DE_PASSE');${NC}"
    fi
    
    echo -e "\n${WHITE}${BOLD}Test de connexion IMAP:${NC}"
    echo -e "  ${YELLOW}openssl s_client -connect ${HOSTNAME}:993${NC}"
    
    echo -e "\n${WHITE}${BOLD}Test de connexion SMTP:${NC}"
    echo -e "  ${YELLOW}openssl s_client -connect ${HOSTNAME}:587 -starttls smtp${NC}"
    
    echo -e "\n${WHITE}${BOLD}Logs:${NC}"
    echo -e "  ${CYAN}Installation:${NC}         $LOG_FILE"
    echo -e "  ${CYAN}Erreurs:${NC}              $ERROR_LOG"
    echo -e "  ${CYAN}Postfix:${NC}              /var/log/mail.log"
    echo -e "  ${CYAN}Dovecot:${NC}              /var/log/mail.log"
    
    echo -e "\n${WHITE}${BOLD}Commandes utiles:${NC}"
    echo -e "  ${YELLOW}systemctl status postfix${NC}     - Statut de Postfix"
    echo -e "  ${YELLOW}systemctl status dovecot${NC}     - Statut de Dovecot"
    echo -e "  ${YELLOW}tail -f /var/log/mail.log${NC}    - Suivre les logs"
    echo -e "  ${YELLOW}postqueue -p${NC}                 - Voir la file d'attente"
    
    if [ "$CERT_TYPE" = "selfsigned" ]; then
        echo -e "\n${YELLOW}${BOLD}⚠ ATTENTION:${NC}"
        echo -e "  Vous utilisez un certificat auto-signé."
        echo -e "  Les clients mail afficheront un avertissement de sécurité."
        echo -e "  Pour un usage en production, utilisez Let's Encrypt."
    fi
    
    echo -e "\n${GREEN}${BOLD}Installation réussie! 🎉${NC}\n"
}

################################################################################
# Fonction principale
################################################################################

main() {
    # Initialisation
    show_logo
    init_logs
    
    # Vérifications préliminaires
    print_section "Vérifications préliminaires"
    check_root
    check_debian_version
    check_internet
    
    # Collecte des informations
    collect_information
    
    # Calcul du nombre d'étapes
    STEP_TOTAL=8
    if [ "$AUTH_TYPE" = "mysql" ]; then
        STEP_TOTAL=$((STEP_TOTAL + 3))  # MySQL, DB config, PostfixAdmin
    fi
    
    # Installation
    print_section "Installation en cours"
    
    update_system
    configure_hostname
    install_postfix
    
    if [ "$AUTH_TYPE" = "mysql" ]; then
        install_mysql
        configure_mail_database
        configure_postfix_mysql
    else
        configure_postfix_unix
    fi
    
    install_dovecot
    
    if [ "$AUTH_TYPE" = "mysql" ]; then
        configure_dovecot_mysql
    else
        configure_dovecot_unix
    fi
    
    # Certificats
    if [ "$CERT_TYPE" = "letsencrypt" ]; then
        install_letsencrypt
    else
        install_selfsigned_cert
    fi
    
    # PostfixAdmin si MySQL
    if [ "$AUTH_TYPE" = "mysql" ]; then
        install_postfixadmin
    fi
    
    # Démarrage des services
    start_services
    
    # Tests
    sleep 2
    test_configuration
    
    # Résumé
    show_summary
}

################################################################################
# Point d'entrée
################################################################################

# Gestion des signaux
trap 'echo -e "\n${RED}Installation interrompue par l'\''utilisateur${NC}"; exit 130' INT TERM

# Exécution
main "$@"

exit 0
