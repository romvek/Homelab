#!/bin/bash
# GLPI Installation Script (Fixed Execution Flow)
# Source: https://help.glpi-project.org/tutorials/procedures/install_glpi

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (or using sudo)"
  exit
fi

clear
echo "=========================================================="
echo "          GLPI AUTOMATED INSTALLATION SCRIPT             "
echo "=========================================================="

echo "==> 1. UPDATING SYSTEM & INSTALLING PACKAGES"
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl wget apache2 mariadb-server php libapache2-mod-php \
php-{apcu,cli,common,curl,gd,imap,ldap,mysql,xmlrpc,xml,mbstring,bcmath,intl,zip,redis,bz2,soap,cas}

# ==========================================
# 2. INTERACTIVE CONFIGURATION
# ==========================================
echo ""
echo "==> 2. CONFIGURATION & DETECTION"
echo "----------------------------------------------------------"

# --- TIMEZONE ---
DETECTED_TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')

while true; do
    echo -n "Detected Timezone is [$DETECTED_TZ]. Accept? (y/n): "
    read -r TZ_CONFIRM < /dev/tty
    if [[ $TZ_CONFIRM =~ ^[Yy]$ ]]; then
        TIMEZONE=$DETECTED_TZ
        break
    elif [[ $TZ_CONFIRM =~ ^[Nn]$ ]]; then
        echo -n "Enter custom Timezone (e.g., America/New_York): "
        read -r TIMEZONE < /dev/tty
        [ -n "$TIMEZONE" ] && break
    else
        echo "Invalid input. Please enter 'y' or 'n'."
    fi
done

# --- DOMAIN ---
DEFAULT_DOMAIN="localhost"
while true; do
    echo -n "Default Domain/Hostname is [$DEFAULT_DOMAIN]. Accept? (y/n): "
    read -r DOM_CONFIRM < /dev/tty
    if [[ $DOM_CONFIRM =~ ^[Yy]$ ]]; then
        DOMAIN_NAME=$DEFAULT_DOMAIN
        break
    elif [[ $DOM_CONFIRM =~ ^[Nn]$ ]]; then
        echo -n "Enter custom Domain/Hostname: "
        read -r DOMAIN_NAME < /dev/tty
        [ -n "$DOMAIN_NAME" ] && break
        echo "Error: Domain name cannot be empty."
    else
        echo "Invalid input. Please enter 'y' to accept or 'n' to customize."
    fi
done

# --- DB USERNAME ---
while true; do
    echo -n "Enter Database Username [glpi]: "
    read -r DB_USER < /dev/tty
    DB_USER=${DB_USER:-glpi}
    [ -n "$DB_USER" ] && break
done

# --- DB NAME ---
while true; do
    echo -n "Enter Database Name [glpidb]: "
    read -r DB_NAME < /dev/tty
    DB_NAME=${DB_NAME:-glpidb}
    [ -n "$DB_NAME" ] && break
done

# --- DB PASSWORD ---
while true; do
    echo "Setting password for DB user '$DB_USER'..."
    echo -n "Enter Password: "
    read -rs DB_PASS < /dev/tty
    echo ""
    echo -n "Confirm Password: "
    read -rs DB_PASS_CONFIRM < /dev/tty
    echo ""

    if [ -z "$DB_PASS" ]; then
        echo "Error: Password cannot be empty!"
    elif [ "$DB_PASS" != "$DB_PASS_CONFIRM" ]; then
        echo "Error: Passwords do not match!"
    elif [[ ${#DB_PASS} -lt 8 || ! "$DB_PASS" =~ [A-Za-z] || ! "$DB_PASS" =~ [0-9] ]]; then
        echo "Warning: Password is weak (needs 8+ chars, letters, and numbers)."
        echo -n "Continue anyway? (y/n): "
        read -r PASS_WEAK_CONFIRM < /dev/tty
        [[ $PASS_WEAK_CONFIRM =~ ^[Yy]$ ]] && break
    else
        break
    fi
done

# --- FINAL CONFIRMATION ---
echo ""
echo "SUMMARY:"
echo "Timezone: $TIMEZONE | Domain: $DOMAIN_NAME | DB: $DB_NAME"
echo "----------------------------------------------------------"
echo -n "Proceed with installation? (y/n): "
read -r FINAL_CONFIRM < /dev/tty
if [[ ! $FINAL_CONFIRM =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 1
fi

# ==========================================
# 3. EXECUTION STEPS (Automated)
# ==========================================

echo "==> 3. Identifying Latest GLPI Version..."
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
GLPI_VERSION=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | grep '"tag_name":' | head -n 1 | awk -F '"' '{print $4}')

echo "==> 4. Configuring MariaDB..."
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql mysql
mysql -uroot -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
mysql -uroot -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -uroot -e "GRANT SELECT ON \`mysql\`.\`time_zone_name\` TO '${DB_USER}'@'localhost';"
mysql -uroot -e "FLUSH PRIVILEGES;"

echo "==> 5. Downloading and Extracting GLPI..."
cd /var/www/html || exit
wget -q https://github.com/glpi-project/glpi/releases/download/"${GLPI_VERSION}"/glpi-"${GLPI_VERSION}".tgz
tar -xzf glpi-"${GLPI_VERSION}".tgz
rm glpi-"${GLPI_VERSION}".tgz

echo "==> 6. Configuring File Hierarchy (FHS)..."
cat <<EOF > /var/www/html/glpi/inc/downstream.php
<?php
define('GLPI_CONFIG_DIR', '/etc/glpi/');
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
    require_once GLPI_CONFIG_DIR . '/local_define.php';
}
EOF

mkdir -p /etc/glpi /var/lib/glpi /var/log/glpi
[ -d /var/www/html/glpi/config ] && cp -r /var/www/html/glpi/config/ /etc/glpi/ && rm -rf /var/www/html/glpi/config
[ -d /var/www/html/glpi/files ] && cp -r /var/www/html/glpi/files/ /var/lib/glpi/ && rm -rf /var/www/html/glpi/files
[ -d /var/lib/glpi/_log ] && cp -r /var/lib/glpi/_log /var/log/glpi/ && rm -rf /var/lib/glpi/_log

cat <<EOF > /etc/glpi/local_define.php
<?php
define('GLPI_VAR_DIR', '/var/lib/glpi');
define('GLPI_LOG_DIR', '/var/log/glpi');
define('GLPI_DOC_DIR', GLPI_VAR_DIR);
define('GLPI_CACHE_DIR', GLPI_VAR_DIR . '/_cache');
define('GLPI_CRON_DIR', GLPI_VAR_DIR . '/_cron');
define('GLPI_GRAPH_DIR', GLPI_VAR_DIR . '/_graphs');
define('GLPI_LOCAL_I18N_DIR', GLPI_VAR_DIR . '/_locales');
define('GLPI_LOCK_DIR', GLPI_VAR_DIR . '/_lock');
define('GLPI_PICTURE_DIR', GLPI_VAR_DIR . '/_pictures');
define('GLPI_PLUGIN_DOC_DIR', GLPI_VAR_DIR . '/_plugins');
define('GLPI_RSS_DIR', GLPI_VAR_DIR . '/_rss');
define('GLPI_SESSION_DIR', GLPI_VAR_DIR . '/_sessions');
define('GLPI_TMP_DIR', GLPI_VAR_DIR . '/_tmp');
define('GLPI_UPLOAD_DIR', GLPI_VAR_DIR . '/_uploads');
define('GLPI_INVENTORY_DIR', GLPI_VAR_DIR . '/_inventories');
define('GLPI_THEMES_DIR', GLPI_VAR_DIR . '/_themes');
EOF

echo "==> 7. Setting Security Permissions..."
chown root:root /var/www/html/glpi/ -R
chown www-data:www-data /etc/glpi -R
chown www-data:www-data /var/lib/glpi -R
chown www-data:www-data /var/log/glpi -R
chown www-data:www-data /var/www/html/glpi/marketplace -Rf
find /var/www/html/glpi/ -type f -exec chmod 0644 {} \;
find /var/www/html/glpi/ -type d -exec chmod 0755 {} \;
find /etc/glpi -type f -exec chmod 0644 {} \;
find /etc/glpi -type d -exec chmod 0755 {} \;
find /var/lib/glpi -type f -exec chmod 0644 {} \;
find /var/lib/glpi -type d -exec chmod 0755 {} \;
find /var/log/glpi -type f -exec chmod 0644 {} \;
find /var/log/glpi -type d -exec chmod 0755 {} \;

echo "==> 8. Configuring Apache & PHP..."
cat <<EOF > /etc/apache2/sites-available/glpi.conf
<VirtualHost *:80>
    ServerName ${DOMAIN_NAME}
    DocumentRoot /var/www/html/glpi/public
    <Directory /var/www/html/glpi/public>
        Require all granted
        RewriteEngine On
        RewriteCond %{HTTP:Authorization} ^(.+)$
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
</VirtualHost>
EOF

a2dissite 000-default.conf >/dev/null 2>&1
a2enmod rewrite >/dev/null 2>&1
a2ensite glpi.conf >/dev/null 2>&1

PHP_INI="/etc/php/${PHP_VER}/apache2/php.ini"
if [ -f "$PHP_INI" ]; then
    sed -i "s/^\s*upload_max_filesize.*/upload_max_filesize = 20M/" "$PHP_INI"
    sed -i "s/^\s*post_max_size.*/post_max_size = 20M/" "$PHP_INI"
    sed -i "s/^\s*max_execution_time.*/max_execution_time = 60/" "$PHP_INI"
    sed -i "s/^\s*max_input_vars.*/max_input_vars = 5000/" "$PHP_INI"
    sed -i "s/^\s*memory_limit.*/memory_limit = 256M/" "$PHP_INI"
    sed -i "s/^\s*session.cookie_httponly.*/session.cookie_httponly = On/" "$PHP_INI"
    sed -i "s|^\s*;\?date.timezone.*|date.timezone = ${TIMEZONE}|" "$PHP_INI"
fi

systemctl restart apache2

echo "=========================================================="
echo "DONE! GLPI is available at: http://${DOMAIN_NAME}"
echo "=========================================================="
