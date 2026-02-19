# Script d'Installation Serveur Mail Postfix/Dovecot

**Auteur** : Philippe Muller  
**Licence** : GNU General Public License v3.0 (GPL-3.0)  
**Version** : 1.2  
**Date** : Février 2026

## 📧 Description

Script BASH complet pour l'installation automatisée d'un serveur mail sur Debian 13 avec :
- **Postfix** (SMTP) pour l'envoi et la réception d'emails
- **Dovecot** (IMAP/POP3) pour la consultation des emails
- Support de **TLS/SSL** avec Let's Encrypt ou certificats auto-signés
- Choix entre authentification par **comptes Unix** ou **base de données MySQL**
- **PostfixAdmin** (optionnel) pour la gestion web des comptes mail

## ✨ Fonctionnalités

### Interface Utilisateur
- 🎨 Interface colorée et visuellement agréable
- 📊 Barres de progression et indicateurs d'avancement
- ✅ Validation des entrées utilisateur
- 🔄 Spinners d'attente pour les opérations longues

### Gestion des Erreurs
- 📝 Logs détaillés de toutes les opérations
- ⚠️ Affichage des erreurs uniquement en cas de problème
- 🛡️ Vérifications préalables (root, version Debian, Internet)
- 🔍 Tests de configuration post-installation

### Configuration
- 🌐 Configuration du nom de domaine et hostname
- 🔐 Choix du type d'authentification (Unix ou MySQL)
- 🔒 Installation automatique des certificats TLS
- 📬 Configuration complète SMTP/IMAP/POP3

## 📋 Prérequis

- **Système** : Debian 13 (Trixie)
- **Accès** : Droits root (sudo)
- **Réseau** : Connexion Internet active
- **DNS** : Nom de domaine pointant vers le serveur (pour Let's Encrypt)
- **Ports** : Ports 25, 587, 465, 143, 993, 110, 995 disponibles

## ⚠️ Corrections Importantes (Version 1.2)

Cette version corrige plusieurs problèmes identifiés lors de l'installation sur Debian 13 :

### Corrections apportées :
1. **Paquet `software-properties-common`** : Supprimé car non disponible dans Debian 13
2. **Paquet `php-imap`** : Supprimé car non disponible dans Debian 13
3. **Configuration PostfixAdmin** : 
   - Algorithme de chiffrement corrigé : `php_crypt:SHA512-CRYPT` au lieu de `sha512crypt`
   - Création automatique de toutes les tables PostfixAdmin nécessaires
   - Création automatique du super-administrateur lors de l'installation
   - Colonne `password_expiry` de type `INT(11)` (nombre de jours) au lieu de `DATETIME`
4. **Vérifications Apache/PHP** : Détection si déjà installés avant tentative d'installation
5. **Configuration Dovecot 2.4** : Mise à jour pour la syntaxe Dovecot 2.4
   - Ajout de `dovecot_config_version = 2.4.0` et `dovecot_storage_version = 2.4`
   - `disable_plaintext_auth` → `auth_allow_cleartext`
   - `mail_location` → `mail_driver` + `mail_path`
   - `ssl_cert`/`ssl_key` → `ssl_server_cert_file`/`ssl_server_key_file`
   - Variables `%d`/`%n` → `%{user | domain}`/`%{user | username}`
   - Nouvelle syntaxe `passdb sql { }` et `userdb static { }`
   - Configuration SQL intégrée directement (plus de fichier externe pour MySQL)

## 🚀 Installation

### 1. Télécharger le script

```bash
# Cloner ou télécharger le script
wget https://votre-repo/install_mail_server.sh
# ou
curl -O https://votre-repo/install_mail_server.sh
```

### 2. Rendre le script exécutable

```bash
chmod +x install_mail_server.sh
```

### 3. Exécuter le script

```bash
sudo ./install_mail_server.sh
```

## 📖 Utilisation

### Étape 1 : Vérifications préliminaires
Le script vérifie automatiquement :
- Que vous êtes root
- La version de Debian
- La connectivité Internet

### Étape 2 : Configuration
Le script vous posera les questions suivantes :

1. **Nom de domaine principal** (ex: `example.com`)
2. **Hostname du serveur** (ex: `mail.example.com`)
3. **Email administrateur** (ex: `admin@example.com`)
4. **Type d'authentification** :
   - Comptes Unix (utilisateurs système)
   - Base de données MySQL (avec PostfixAdmin)
5. **Type de certificat** :
   - Let's Encrypt (gratuit, automatique)
   - Certificat auto-signé (pour tests)

### Étape 3 : Installation automatique
Le script procède à l'installation complète :
- Mise à jour du système
- Installation de Postfix
- Installation de Dovecot
- Configuration des certificats TLS
- Installation de MySQL (si sélectionné)
- Installation de PostfixAdmin (si MySQL)
- Tests de configuration

## 🔧 Configuration Post-Installation

### Avec Comptes Unix

#### Créer un utilisateur mail
```bash
# Créer un utilisateur système
sudo adduser jean

# L'utilisateur peut maintenant se connecter avec :
# - Email : jean@example.com
# - Mot de passe : son mot de passe système
```

### Avec MySQL/PostfixAdmin

#### Option 1 : Via PostfixAdmin (Interface Web)
1. Le super-administrateur est créé automatiquement lors de l'installation
2. Accéder à `http://votre-serveur/postfixadmin/public/login.php`
3. Se connecter avec l'email et le mot de passe définis lors de l'installation
4. Gérer les domaines et utilisateurs via l'interface

**Note** : Le script crée automatiquement :
- Toutes les tables PostfixAdmin nécessaires
- Le domaine principal dans PostfixAdmin
- Un compte super-administrateur avec tous les privilèges

#### Option 2 : Manuellement via MySQL
```bash
# Générer un hash de mot de passe
doveadm pw -s SHA512-CRYPT
# Entrer le mot de passe souhaité

# Se connecter à MySQL
mysql -u root -p mailserver

# Créer un utilisateur
INSERT INTO virtual_users (domain_id, email, password)
VALUES (1, 'jean@example.com', '{SHA512-CRYPT}$6$...');

# Créer un alias (optionnel)
INSERT INTO virtual_aliases (domain_id, source, destination)
VALUES (1, 'contact@example.com', 'jean@example.com');
```

## 🧪 Tests de Connexion

### Test IMAP (port 993)
```bash
openssl s_client -connect mail.example.com:993
# Une fois connecté :
# a1 LOGIN utilisateur@example.com motdepasse
# a2 LIST "" "*"
# a3 LOGOUT
```

### Test SMTP (port 587)
```bash
openssl s_client -connect mail.example.com:587 -starttls smtp
# Une fois connecté :
# EHLO example.com
# AUTH LOGIN
# (entrer username et password en base64)
```

### Test avec un client mail
Configurez votre client mail (Thunderbird, Outlook, etc.) avec :

**Serveur entrant (IMAP)** :
- Serveur : `mail.example.com`
- Port : `993`
- Sécurité : `SSL/TLS`
- Authentification : `Mot de passe normal`

**Serveur sortant (SMTP)** :
- Serveur : `mail.example.com`
- Port : `587`
- Sécurité : `STARTTLS`
- Authentification : `Mot de passe normal`

## 📊 Ports Utilisés

| Port | Service | Description |
|------|---------|-------------|
| 25   | SMTP    | Réception d'emails (serveur à serveur) |
| 587  | Submission | Envoi d'emails avec authentification |
| 465  | SMTPS   | Envoi d'emails avec SSL |
| 143  | IMAP    | Consultation d'emails |
| 993  | IMAPS   | Consultation d'emails avec SSL |
| 110  | POP3    | Consultation d'emails (ancien) |
| 995  | POP3S   | Consultation d'emails avec SSL (ancien) |

## 📁 Fichiers et Répertoires

### Logs
- `/chemin/script/mail_server_install.log` - Log complet de l'installation
- `/chemin/script/mail_server_errors.log` - Erreurs d'installation
- `/var/log/mail.log` - Logs Postfix et Dovecot

### Configuration Postfix
- `/etc/postfix/main.cf` - Configuration principale
- `/etc/postfix/master.cf` - Configuration des services
- `/etc/postfix/mysql-*.cf` - Requêtes MySQL (si applicable)

### Configuration Dovecot
- `/etc/dovecot/dovecot.conf` - Configuration principale
- `/etc/dovecot/conf.d/` - Configurations détaillées
- `/etc/dovecot/dovecot-sql.conf.ext` - Configuration MySQL (si applicable)

### Certificats
- Let's Encrypt : `/etc/letsencrypt/live/[hostname]/`
- Auto-signés : `/etc/ssl/mailserver/`

### Boîtes aux lettres
- Comptes Unix : `~/Maildir/` (dans le home de chaque utilisateur)
- MySQL : `/var/mail/vhosts/[domaine]/[utilisateur]/`

## 🔍 Commandes Utiles

### Gestion des services
```bash
# Statut des services
systemctl status postfix
systemctl status dovecot

# Redémarrer les services
systemctl restart postfix
systemctl restart dovecot

# Voir les logs en temps réel
tail -f /var/log/mail.log
```

### Postfix
```bash
# Voir la file d'attente
postqueue -p

# Vider la file d'attente
postsuper -d ALL

# Tester la configuration
postfix check

# Recharger la configuration
postfix reload
```

### Dovecot
```bash
# Tester la configuration
doveconf -n

# Recharger la configuration
doveadm reload

# Lister les utilisateurs connectés
doveadm who
```

### MySQL (si applicable)
```bash
# Se connecter à la base
mysql -u mailuser -p mailserver

# Lister les domaines
SELECT * FROM virtual_domains;

# Lister les utilisateurs
SELECT * FROM virtual_users;

# Lister les alias
SELECT * FROM virtual_aliases;
```

## 🛡️ Sécurité

### Certificats TLS
- Le script configure automatiquement TLS pour tous les services
- Let's Encrypt : renouvellement automatique via cron
- Protocoles obsolètes désactivés (SSLv2, SSLv3, TLSv1, TLSv1.1)

### Authentification
- Authentification obligatoire pour l'envoi d'emails
- Mots de passe chiffrés (SHA512-CRYPT pour MySQL)
- Protection contre le spam (RBL Spamhaus, SpamCop)

### Recommandations
1. **Firewall** : Configurer un firewall (UFW, iptables)
   ```bash
   ufw allow 25/tcp
   ufw allow 587/tcp
   ufw allow 465/tcp
   ufw allow 993/tcp
   ```

2. **Fail2ban** : Installer fail2ban pour bloquer les tentatives de connexion
   ```bash
   apt-get install fail2ban
   ```

3. **SPF/DKIM/DMARC** : Configurer les enregistrements DNS
   - SPF : `v=spf1 mx ~all`
   - DKIM : Utiliser OpenDKIM
   - DMARC : `v=DMARC1; p=quarantine`

4. **Reverse DNS** : Configurer le PTR chez votre hébergeur

## ❗ Dépannage

### Le script échoue lors de l'installation
- Vérifier les logs : `cat mail_server_errors.log`
- Vérifier la connexion Internet
- Vérifier l'espace disque : `df -h`

### Impossible d'envoyer des emails
- Vérifier que le port 25 n'est pas bloqué par votre FAI
- Vérifier les logs : `tail -f /var/log/mail.log`
- Tester la configuration : `postfix check`

### Impossible de recevoir des emails
- Vérifier les enregistrements DNS (MX)
- Vérifier que le port 25 est ouvert
- Tester : `telnet mail.example.com 25`

### Erreur de certificat
- Vérifier que le domaine pointe vers le serveur
- Vérifier les certificats : `ls -la /etc/letsencrypt/live/`
- Renouveler manuellement : `certbot renew`

### Authentification échouée
- Comptes Unix : Vérifier que l'utilisateur existe
- MySQL : Vérifier la base de données et les mots de passe
- Tester : `doveadm auth test utilisateur@example.com`

## 📝 Notes Importantes

### Let's Encrypt
- Nécessite que le domaine pointe vers le serveur
- Limite de 5 certificats par semaine par domaine
- Renouvellement automatique tous les 60 jours

### Certificats Auto-signés
- Non approuvés par les autorités de certification
- Les clients afficheront un avertissement
- À utiliser uniquement pour les tests

### PostfixAdmin
- Interface web pour gérer les comptes mail
- Nécessite Apache et PHP
- Accessible via `http://votre-serveur/postfixadmin/public/login.php`
- Le super-administrateur est créé automatiquement lors de l'installation
- Toutes les tables nécessaires sont créées automatiquement

## 🤝 Support

En cas de problème :
1. Consulter les logs d'installation
2. Vérifier les logs système (`/var/log/mail.log`)
3. Tester la configuration avec les commandes fournies
4. Consulter la documentation officielle :
   - [Postfix](http://www.postfix.org/documentation.html)
   - [Dovecot](https://doc.dovecot.org/)

## 📜 Licence

Copyright (C) 2026 Philippe Muller

Ce programme est un logiciel libre ; vous pouvez le redistribuer et/ou le modifier selon les termes de la **Licence Publique Générale GNU** (GNU General Public License) telle que publiée par la Free Software Foundation ; soit la version 3 de la Licence, soit (à votre choix) toute version ultérieure.

Ce programme est distribué dans l'espoir qu'il sera utile, mais **SANS AUCUNE GARANTIE** ; sans même la garantie implicite de **COMMERCIALISATION** ou d'**ADAPTATION À UN USAGE PARTICULIER**. Voir la Licence Publique Générale GNU pour plus de détails.

Vous devriez avoir reçu une copie de la Licence Publique Générale GNU avec ce programme. Si ce n'est pas le cas, consultez <https://www.gnu.org/licenses/>.

### Résumé de la licence GPL-3.0

✅ **Permissions** :
- Utilisation commerciale
- Modification
- Distribution
- Utilisation privée

⚠️ **Conditions** :
- Divulgation du code source
- Même licence pour les œuvres dérivées
- Indication des modifications
- Conservation des mentions de licence et de copyright

❌ **Limitations** :
- Aucune garantie
- Aucune responsabilité

Pour plus d'informations, consultez le texte complet de la licence GPL-3.0 : https://www.gnu.org/licenses/gpl-3.0.html

## 🎯 Informations Techniques

- **Version** : 1.2
- **Date** : Février 2026
- **Compatibilité** : Debian 13 (Trixie) avec Dovecot 2.4
- **Langage** : Bash
- **Auteur** : Philippe Muller

### Historique des versions

**Version 1.2** (19/02/2026)
- Correction : Type de colonne `password_expiry` (INT au lieu de DATETIME)
- Correction : Configuration Dovecot 2.4 (nouvelle syntaxe)
  - Ajout des versions de configuration Dovecot
  - Mise à jour des directives d'authentification
  - Mise à jour des directives mail_location
  - Mise à jour des directives SSL
  - Mise à jour des variables utilisateur
  - Nouvelle syntaxe passdb/userdb pour MySQL

**Version 1.1** (19/02/2026)
- Correction : Suppression du paquet `software-properties-common` (non disponible sur Debian 13)
- Correction : Suppression du paquet `php-imap` (non disponible sur Debian 13)
- Correction : Algorithme de chiffrement PostfixAdmin (`php_crypt:SHA512-CRYPT`)
- Amélioration : Création automatique de toutes les tables PostfixAdmin
- Amélioration : Création automatique du super-administrateur PostfixAdmin
- Amélioration : Vérification si Apache/PHP sont déjà installés
- Amélioration : Messages explicatifs pour les mots de passe MySQL

**Version 1.0** (Février 2026)
- Version initiale

## 🤝 Contribution

Les contributions sont les bienvenues ! N'hésitez pas à :
- Signaler des bugs
- Proposer des améliorations
- Soumettre des pull requests
- Partager vos retours d'expérience

---

**Bon déploiement de votre serveur mail ! 📧**

*Ce logiciel libre est mis à disposition de la communauté dans l'esprit du partage et de la collaboration.*
