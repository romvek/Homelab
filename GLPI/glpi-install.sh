#!/bin/bash
# GLPI Installation Script 
# Source: https://help.glpi-project.org/tutorials/procedures/install_glpi
# Requires: Ubuntu Server 22.04 LTS

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (or using sudo)"
  exit
fi

# ==========================================
# CONFIGURATION VARIABLES
# Change these values to match your desired setup
# ==========================================
DB_NAME="glpi"
DB_USER="glpi"
DB_PASS="yourstrongpassword"
GLPI_VERSION="11.0.7"
DOMAIN_NAME="localhost"
TIMEZONE="America/Los_Angeles"
PHP_VERSION="8.4"
# ==========================================

echo "==> 1. Updating system and installing components..."
apt update && apt upgrade -y
apt install -y apache2 php php-{apcu,cli,common,curl,gd,imap,ldap,mysql,xmlrpc,xml,mbstring,bcmath,intl,zip,redis,bz2} libapache2-mod-php php-soap php-cas mariadb-server

echo "==> 2. Configuring the Database..."
# Load timezone data into MariaDB
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql mysql

# Create GLPI database and user
mysql -uroot -e "CREATE DATABASE ${DB_NAME};"
mysql -uroot -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -uroot -e "GRANT SELECT ON \`mysql\`.\`time_zone_name\` TO '${DB_USER}'@'localhost';"
mysql -uroot -e "FLUSH PRIVILEGES;"

echo "==> 3. Preparing files and installing GLPI..."
cd /var/www/html
wget https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz
tar -xvzf glpi-${GLPI_VERSION}.tgz

# Instruct GLPI application where the configuration directory is stored
cat <<EOF > /var/www/html/glpi/inc/downstream.php
<?php
define('GLPI_CONFIG_DIR', '/etc/glpi/');
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
    require_once GLPI_CONFIG_DIR . '/local_define.php';
}
EOF

# Move directories to comply with File Hierarchy Standard
mv /var/www/html/glpi/config /etc/glpi
mv /var/www/html/glpi/files /var/lib/glpi
mv /var/lib/glpi/_log /var/log/glpi

# Instruct GLPI where the other directories are stored
cat <<EOF > /etc/glpi/local_define.php
<?php
define('GLPI_VAR_DIR', '/var/lib/glpi');
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
define('GLPI_LOG_DIR', '/var/log/glpi');
EOF

echo "==> 4. Setting correct folder and file permissions..."
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

echo "==> 5. Configuring Web Server (Apache) & PHP..."
# Create Apache VirtualHost file
cat <<EOF > /etc/apache2/sites-available/glpi.conf
# Start of the VirtualHost configuration for port 80
<VirtualHost *:80>
    ServerName ${DOMAIN_NAME}
    DocumentRoot /var/www/html/glpi/public

    <Directory /var/www/html/glpi/public>
        Require all granted
        RewriteEngine On
        # Ensure authorization headers are passed to PHP
        RewriteCond %{HTTP:Authorization} ^(.+)$
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        # Redirect all requests to GLPI router, unless the file exists
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
</VirtualHost>
EOF

# Apply Apache settings
a2dissite 000-default.conf
a2enmod rewrite
a2ensite glpi.conf

# Modify php.ini parameters based on documentation recommendations
PHP_INI="/etc/php/${PHP_VERSION}/apache2/php.ini"
sed -i "s/^\s*upload_max_filesize.*/upload_max_filesize = 20M/" $PHP_INI
sed -i "s/^\s*post_max_size.*/post_max_size = 20M/" $PHP_INI
sed -i "s/^\s*max_execution_time.*/max_execution_time = 60/" $PHP_INI
sed -i "s/^\s*max_input_vars.*/max_input_vars = 5000/" $PHP_INI
sed -i "s/^\s*memory_limit.*/memory_limit = 256M/" $PHP_INI
sed -i "s/^\s*session.cookie_httponly.*/session.cookie_httponly = On/" $PHP_INI
# Replace commented or pre-existing timezone entry
sed -i "s|^\s*;\?date.timezone.*|date.timezone = ${TIMEZONE}|" $PHP_INI

# Restart Apache
systemctl restart apache2

echo "=========================================================="
echo "GLPI Script Setup Complete!"
echo "It is highly recommended that you run 'mysql_secure_installation' manually to secure MariaDB."
echo "Once done, open your browser and navigate to http://${DOMAIN_NAME} to begin the web installation."
echo "=========================================================="
