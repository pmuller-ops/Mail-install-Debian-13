#!/bin/bash

################################################################################
# Script d'installation PostfixAdmin uniquement
# Pour reprendre après une erreur d'installation
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
MYSQL_MAIL_PASSWORD=""
DOMAIN=""

# Fonctions d'affichage
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
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

# Logo
clear
echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║              Installation PostfixAdmin - Debian 13               ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

print_section "Configuration"

# Demander le mot de passe MySQL
echo -e -n "${CYAN}Mot de passe de l'utilisateur mailuser MySQL: ${NC}"
read -rs MYSQL_MAIL_PASSWORD
echo ""

if [ -z "$MYSQL_MAIL_PASSWORD" ]; then
    print_error "Le mot de passe MySQL est requis"
    exit 1
fi

# Demander le domaine
echo -e -n "${CYAN}Nom de domaine (ex: example.com): ${NC}"
read DOMAIN

if [ -z "$DOMAIN" ]; then
    print_error "Le nom de domaine est requis"
    exit 1
fi

# Vérifier la connexion MySQL
print_info "Vérification de la connexion MySQL..."
if ! mysql -u mailuser -p"${MYSQL_MAIL_PASSWORD}" -e "USE mailserver;" &> /dev/null; then
    print_error "Impossible de se connecter à MySQL avec les identifiants fournis"
    print_info "Vérifiez que l'utilisateur mailuser existe et que le mot de passe est correct"
    exit 1
fi
print_success "Connexion MySQL OK"

print_section "Installation de PostfixAdmin"

# Vérifier si Apache est déjà installé
if command -v apache2 &> /dev/null; then
    print_info "Apache2 est déjà installé"
else
    print_info "Installation d'Apache2..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y apache2
    print_success "Apache2 installé"
fi

# Vérifier si PHP est déjà installé
if command -v php &> /dev/null; then
    PHP_VERSION=$(php -v | head -n 1 | cut -d ' ' -f 2)
    print_info "PHP est déjà installé (version ${PHP_VERSION})"
else
    print_info "Installation de PHP..."
fi

# Installer les dépendances PHP
print_info "Installation des dépendances PHP..."
DEBIAN_FRONTEND=noninteractive apt-get install -y php php-mysql php-mbstring php-curl libapache2-mod-php

print_success "Dépendances installées"

# Supprimer l'ancienne installation si elle existe
if [ -d "/var/www/html/postfixadmin" ]; then
    print_warning "Une installation de PostfixAdmin existe déjà"
    echo -e -n "${YELLOW}Voulez-vous la remplacer ? (o/N): ${NC}"
    read -r response
    if [[ "$response" =~ ^[Oo]$ ]]; then
        rm -rf /var/www/html/postfixadmin
        print_info "Ancienne installation supprimée"
    else
        print_error "Installation annulée"
        exit 1
    fi
fi

# Télécharger PostfixAdmin
print_info "Téléchargement de PostfixAdmin..."
cd /tmp

if ! wget -q https://github.com/postfixadmin/postfixadmin/archive/postfixadmin-3.3.13.tar.gz -O postfixadmin.tar.gz; then
    print_warning "Échec du téléchargement depuis GitHub"
    print_info "Tentative avec SourceForge..."
    
    if ! wget -q https://sourceforge.net/projects/postfixadmin/files/postfixadmin/postfixadmin-3.3.13/postfixadmin-3.3.13.tar.gz -O postfixadmin.tar.gz; then
        print_error "Impossible de télécharger PostfixAdmin"
        exit 1
    fi
fi

print_success "PostfixAdmin téléchargé"

# Extraire et installer
print_info "Installation de PostfixAdmin..."
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
\$CONF['aliases'] = '10';
\$CONF['mailboxes'] = '10';
\$CONF['maxquota'] = '100';
\$CONF['quota'] = 'YES';
?>
EOF

# Créer le répertoire templates_c
mkdir -p templates_c
chown -R www-data:www-data /var/www/html/postfixadmin
chmod 750 templates_c

print_success "PostfixAdmin configuré"

# Configuration Apache
print_info "Configuration d'Apache..."

cat > /etc/apache2/sites-available/postfixadmin.conf << EOF
<VirtualHost *:80>
    ServerName mail.${DOMAIN}
    DocumentRoot /var/www/html/postfixadmin/public
    
    <Directory /var/www/html/postfixadmin/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/postfixadmin_error.log
    CustomLog \${APACHE_LOG_DIR}/postfixadmin_access.log combined
</VirtualHost>
EOF

# Activer le site et les modules nécessaires
a2ensite postfixadmin.conf
a2enmod rewrite
systemctl reload apache2

print_success "Apache configuré"

# Nettoyer
cd /tmp
rm -f postfixadmin.tar.gz

print_section "Installation terminée"

echo -e "${GREEN}${BOLD}PostfixAdmin a été installé avec succès !${NC}\n"
echo -e "${CYAN}Accès à PostfixAdmin:${NC}"
echo -e "  URL: ${WHITE}http://mail.${DOMAIN}/setup.php${NC}"
echo -e "  ou:  ${WHITE}http://$(hostname -I | awk '{print $1}')/postfixadmin/public/setup.php${NC}\n"

echo -e "${YELLOW}${BOLD}Prochaines étapes:${NC}"
echo -e "  1. Accédez à l'URL ci-dessus pour terminer la configuration"
echo -e "  2. Créez un compte administrateur"
echo -e "  3. Configurez vos domaines et comptes mail\n"

print_warning "N'oubliez pas de configurer votre DNS pour pointer mail.${DOMAIN} vers ce serveur"
