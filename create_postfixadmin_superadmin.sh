#!/bin/bash

################################################################################
# Script de création d'un super-administrateur PostfixAdmin
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
ADMIN_EMAIL=""
ADMIN_PASSWORD=""

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

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
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
║         Création Super-Administrateur PostfixAdmin               ║
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

# Vérifier la connexion MySQL
print_info "Vérification de la connexion MySQL..."
if ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" &> /dev/null; then
    print_error "Impossible de se connecter à MySQL avec le mot de passe root fourni"
    exit 1
fi
print_success "Connexion MySQL OK"

# Demander l'email de l'administrateur
echo ""
echo -e -n "${CYAN}Email du super-administrateur (ex: admin@example.com): ${NC}"
read ADMIN_EMAIL

if [ -z "$ADMIN_EMAIL" ]; then
    print_error "L'email est requis"
    exit 1
fi

# Valider le format de l'email
if ! [[ "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    print_error "Format d'email invalide"
    exit 1
fi

# Demander le mot de passe
echo ""
while true; do
    echo -e -n "${CYAN}Mot de passe du super-administrateur: ${NC}"
    read -rs ADMIN_PASSWORD
    echo ""
    
    if [ -z "$ADMIN_PASSWORD" ]; then
        print_error "Le mot de passe ne peut pas être vide"
        continue
    fi
    
    if [ ${#ADMIN_PASSWORD} -lt 8 ]; then
        print_error "Le mot de passe doit contenir au moins 8 caractères"
        continue
    fi
    
    echo -e -n "${CYAN}Confirmez le mot de passe: ${NC}"
    read -rs ADMIN_PASSWORD_CONFIRM
    echo ""
    
    if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
        print_error "Les mots de passe ne correspondent pas"
        continue
    fi
    
    break
done

print_section "Création du super-administrateur"

# Vérifier si l'administrateur existe déjà
ADMIN_EXISTS=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -N -e "SELECT COUNT(*) FROM mailserver.admin WHERE username = '${ADMIN_EMAIL}';" 2>/dev/null)

if [ "$ADMIN_EXISTS" -gt 0 ]; then
    print_warning "Un administrateur avec cet email existe déjà"
    echo -e -n "${YELLOW}Voulez-vous mettre à jour son mot de passe ? (o/N): ${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Oo]$ ]]; then
        print_info "Opération annulée"
        exit 0
    fi
fi

# Générer le hash du mot de passe (SHA512-CRYPT compatible avec PostfixAdmin)
print_info "Génération du hash du mot de passe..."
PASSWORD_HASH=$(doveadm pw -s SHA512-CRYPT -p "$ADMIN_PASSWORD")

if [ -z "$PASSWORD_HASH" ]; then
    print_error "Échec de la génération du hash du mot de passe"
    print_info "Tentative avec une méthode alternative..."
    
    # Méthode alternative avec PHP
    if command -v php &> /dev/null; then
        PASSWORD_HASH=$(php -r "echo '{SHA512-CRYPT}' . crypt('$ADMIN_PASSWORD', '\$6\$rounds=5000\$' . substr(base64_encode(random_bytes(16)), 0, 16) . '\$');")
    else
        print_error "Impossible de générer le hash du mot de passe"
        print_info "Veuillez installer dovecot-core ou PHP"
        exit 1
    fi
fi

print_success "Hash généré"

# Créer ou mettre à jour l'administrateur
print_info "Création du super-administrateur..."

CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')

if [ "$ADMIN_EXISTS" -gt 0 ]; then
    # Mise à jour
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << EOF
UPDATE admin 
SET password = '${PASSWORD_HASH}',
    modified = '${CURRENT_DATE}',
    active = 1,
    superadmin = 1
WHERE username = '${ADMIN_EMAIL}';
EOF
    print_success "Mot de passe du super-administrateur mis à jour"
else
    # Création
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << EOF
INSERT INTO admin (username, password, created, modified, active, superadmin)
VALUES ('${ADMIN_EMAIL}', '${PASSWORD_HASH}', '${CURRENT_DATE}', '${CURRENT_DATE}', 1, 1);
EOF
    print_success "Super-administrateur créé"
fi

# Ajouter l'entrée dans domain_admins pour ALL
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" mailserver << EOF
INSERT INTO domain_admins (username, domain, created, active)
VALUES ('${ADMIN_EMAIL}', 'ALL', '${CURRENT_DATE}', 1)
ON DUPLICATE KEY UPDATE active = 1;
EOF

print_success "Privilèges super-admin accordés"

print_section "Création terminée"

echo -e "${GREEN}${BOLD}Le super-administrateur a été créé avec succès !${NC}\n"
echo -e "${CYAN}Informations de connexion:${NC}"
echo -e "  Email:    ${WHITE}${ADMIN_EMAIL}${NC}"
echo -e "  Password: ${WHITE}[le mot de passe que vous avez défini]${NC}\n"

echo -e "${YELLOW}${BOLD}Accès à PostfixAdmin:${NC}"
echo -e "  URL: ${WHITE}http://mail.votre-domaine.com/login.php${NC}"
echo -e "  ou:  ${WHITE}http://$(hostname -I | awk '{print $1}')/postfixadmin/public/login.php${NC}\n"

print_info "Vous pouvez maintenant vous connecter à PostfixAdmin avec ces identifiants"
