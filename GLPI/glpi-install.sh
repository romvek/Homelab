#!/bin/bash
# GLPI Installation Script (Interactive Domain & Auto-Configuration)
# Source: https://help.glpi-project.org/tutorials/procedures/install_glpi

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (or using sudo)"
  exit
fi

# ==========================================
# INTERACTIVE CONFIGURATION
# ==========================================
echo "--- GLPI Setup Configuration ---"

# Prompt for Domain Name
read -p "Enter your domain name [default: localhost]: " DOMAIN_INPUT
DOMAIN_NAME=${DOMAIN_INPUT:-localhost}

# Prompt for Database Password
read -s -p "Enter password for GLPI database user: " DB_PASS
echo "" # New line after hidden password input

DB_NAME="glpi"
DB_USER="glpi"

# AUTO-DETECT TIMEZONE
TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}')
TIMEZONE=${TIMEZONE:-UTC}

echo "------------------------------------------"
echo "Setup Summary:"
echo "Domain:   $DOMAIN_NAME"
echo "Timezone: $TIMEZONE"
echo "Database: $DB_NAME (User: $DB_USER)"
echo "------------------------------------------"
sleep 2

# ==========================================
# INSTALLATION STEPS
# ==========================================

echo "==> 1. Updating system and installing components..."
apt update && apt upgrade -y
apt install -y curl wget apache2 php php-{apcu,cli,common,curl,gd,imap,ldap,mysql,xmlrpc,xml,mbstring,bcmath,intl,zip,redis,bz2} libapache2-mod-php php-soap php-cas mariadb-server

echo "==> 2. Detecting Environment..."
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
GLPI_VERSION=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | grep '"tag_name":' | head -n 1 | awk -F '"' '{print $4}')

if [ -z "$GLPI_VERSION" ]; then
  echo "Error: Could not determine GLPI version."
  exit 1
fi

echo "==> 3. Configuring MariaDB..."
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql mysql
mysql -uroot -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
mysql -uroot -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -uroot -e "GRANT SELECT ON \`mysql\`.\`time_zone_name\` TO '${DB_USER}'@'localhost';"
mysql -uroot -e "FLUSH PRIVILEGES;"

echo "==> 4. Downloading GLPI ${GLPI_VERSION}..."
cd /var/www/html
wget https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz
tar -xvzf glpi-${GLPI_VERSION}.tgz
rm glpi-${GLPI_VERSION}.tgz

echo "==> 5. Structuring File Hierarchy (FHS)..."
# Path hooks
cat <<EOF > /var/www/html/glpi/inc/downstream.php
<?php
define('GLPI_CONFIG_DIR', '/etc/glpi/');
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
    require_once GLPI_CONFIG_DIR . '/local_define.php';
}
EOF

# Directories and migration
mkdir -p /etc/glpi /var/lib/glpi /var/log/glpi
[ -d /var/www/html/glpi/config ] && cp -r /var/www/html/glpi/config/* /etc/glpi/ && rm -rf /var/www/html/glpi/config
[ -d /var/www/html/glpi/files ] && cp -r /var/www/html/glpi/files/* /var/lib/glpi/ && rm -rf /var/www/html/glpi/files

# Local Definitions
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

echo "==> 6. Applying Security Permissions..."
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

echo "==> 7. Finalizing Web Server and PHP Tuning..."
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

a2dissite 000-default.conf
a2enmod rewrite
a2ensite glpi.conf

PHP_INI="/etc/php/${PHP_VER}/apache2/php.ini"
if [ -f "$PHP_INI" ]; then
    sed -i "s/^\s*upload_max_filesize.*/upload_max_filesize = 20M/" $PHP_INI
    sed -i "s/^\s*post_max_size.*/post_max_size = 20M/" $PHP_INI
    sed -i "s/^\s*max_execution_time.*/max_execution_time = 60/" $PHP_INI
    sed -i "s/^\s*max_input_vars.*/max_input_vars = 5000/" $PHP_INI
    sed -i "s/^\s*memory_limit.*/memory_limit = 256M/" $PHP_INI
    sed -i "s/^\s*session.cookie_httponly.*/session.cookie_httponly = On/" $PHP_INI
    sed -i "s|^\s*;\?date.timezone.*|date.timezone = ${TIMEZONE}|" $PHP_INI
fi

systemctl restart apache2

echo "=========================================================="
echo "GLPI Installation Finished!"
echo "Access: http://${DOMAIN_NAME}"
echo "----------------------------------------------------------"
echo "Use the following credentials in the web wizard:"
echo "Database Host: localhost"
echo "Database Name: ${DB_NAME}"
echo "Database User: ${DB_USER}"
echo "Database Password: (The one you just entered)"
echo "=========================================================="