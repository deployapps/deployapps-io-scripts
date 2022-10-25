#!/bin/bash
#Check Root User or Not
if [ "$(id -nu)" != "root" ]; then
  echo -e '\033[31m Run this script as root user, you can switch to root user by running command sudo su \033[0m '
  exit 1
fi
# Configuration BEGIN
export SWAP_MEMORY_SIZE=2G
export DB_DATABASE=AppDB
export DB_USERNAME=appdbu
export DB_PASSWORD=$(head -c 10 /dev/random | md5sum | head -c 15)
export DB_HOST="localhost"

export PHP_VERSION="php8.1"
export NODEJS_VERSION="16.x"

export PRIMARY_DOMAIN="example.org"

# Config END

# Get Input From User
read -e -p "Enter SWAP Memory:" -i "2G" SWAP_MEMORY_SIZE

read -e -p "Enter DataBase Name:" -i "$DB_DATABASE" DB_DATABASE
read -e -p "Enter DB Username:" -i "$DB_USERNAME" DB_USERNAME
read -e -p "Enter DB Password:" -i "$DB_PASSWORD" DB_PASSWORD

read -e -p "Enter Domain Name:" -i "$PRIMARY_DOMAIN" PRIMARY_DOMAIN

# Update Repository
apt update -y
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Setup Swap Memory
if [ ! -f /swapfile ]; then
  fallocate -l $SWAP_MEMORY_SIZE /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
  sysctl vm.swappiness=20
  echo 'vm.swappiness=20' | tee -a /etc/sysctl.conf
  sysctl vm.vfs_cache_pressure=40
  echo 'vm.vfs_cache_pressure=40' | tee -a /etc/sysctl.conf
fi
# Install Common Software
apt-get install software-properties-common vim htop tree curl zip unzip git -y

# Install Nginx
apt-get install -y nginx
ufw allow 'Nginx Full'
systemctl restart nginx.service
systemctl enable nginx.service
# Install Supervisor
apt-get install -Y supervisor
systemctl restart supervisor.service
systemctl enable supervisor.service
# Install Redis
apt install -y redis-server
systemctl restart redis-server.service
systemctl enable redis-server.service

# Install Mysql
apt install -y mysql-server
systemctl restart mysql.service
systemctl enable mysql.service

# Create Mysql DB and User
echo "#Database Credentials" | tee -a ~/deployapps_io_credentials
echo "DB_DATABASE=${DB_DATABASE}" | tee -a ~/deployapps_io_credentials
echo "DB_USERNAME=${DB_USERNAME}" | tee -a ~/deployapps_io_credentials
echo "DB_PASSWORD=${DB_PASSWORD}" | tee -a ~/deployapps_io_credentials
echo "DB_HOST=${DB_HOST}" | tee -a ~/deployapps_io_credentials

mysql -e "CREATE DATABASE ${DB_DATABASE} /*\!40100 DEFAULT CHARACTER SET utf8 */;"
mysql -e "CREATE USER \`${DB_USERNAME}\`@\`${DB_HOST}\` IDENTIFIED BY '${DB_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_DATABASE}.* TO \`${DB_USERNAME}\`@\`${DB_HOST}\`;"
mysql -e "FLUSH PRIVILEGES;"

# Install NodeJS
curl -sL "https://deb.nodesource.com/setup_${NODEJS_VERSION}" | bash -
apt-get install -y nodejs

# PHP
add-apt-repository --yes ppa:ondrej/php
apt update -y
apt install -y ${PHP_VERSION}
apt install -y ${PHP_VERSION}-fpm
apt install -y ${PHP_VERSION}-bcmath ${PHP_VERSION}-curl ${PHP_VERSION}-gd ${PHP_VERSION}-intl ${PHP_VERSION}-mbstring ${PHP_VERSION}-mysql ${PHP_VERSION}-xml ${PHP_VERSION}-zip ${PHP_VERSION}-redis

# Install Composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

# Install Certbot
apt-get install -y certbot python3-certbot-nginx
##
# LEMP SETUP END
##

# Install Laravel
export COMPOSER_ALLOW_SUPERUSER=1
PROJECT_ROOT_DIR="/var/www/${PRIMARY_DOMAIN}"
APPLICATION_CURRENT_DIRECTORY="${PROJECT_ROOT_DIR}/current"
APPLICATION_WEB_ROOT_DIRECTORY="${APPLICATION_CURRENT_DIRECTORY}/public"
mkdir -p "${PROJECT_ROOT_DIR}"
composer create-project --prefer-dist --no-dev laravel/laravel "${APPLICATION_CURRENT_DIRECTORY}" 9.x

#Move Storage Folder and Link
mv "${APPLICATION_CURRENT_DIRECTORY}/storage" "${PROJECT_ROOT_DIR}/"
ln -s "${PROJECT_ROOT_DIR}/storage" "${APPLICATION_CURRENT_DIRECTORY}/"
#Move .env Folder and Link
mv "${APPLICATION_CURRENT_DIRECTORY}/.env" "${PROJECT_ROOT_DIR}/"
ln -s "${PROJECT_ROOT_DIR}/.env" "${APPLICATION_CURRENT_DIRECTORY}/"

# Update .env Config
sed -i "s/^\(DB_DATABASE\s*=\s*\).*\$/\1$DB_DATABASE/" "${PROJECT_ROOT_DIR}/.env"
sed -i "s/^\(DB_USERNAME\s*=\s*\).*\$/\1$DB_USERNAME/" "${PROJECT_ROOT_DIR}/.env"
sed -i "s/^\(DB_PASSWORD\s*=\s*\).*\$/\1$DB_PASSWORD/" "${PROJECT_ROOT_DIR}/.env"

CACHE_QUEUE_SESSION_DRIVER="redis"
sed -i "s/^\(CACHE_DRIVER\s*=\s*\).*\$/\1$CACHE_QUEUE_SESSION_DRIVER/" "${PROJECT_ROOT_DIR}/.env"
sed -i "s/^\(QUEUE_CONNECTION\s*=\s*\).*\$/\1$CACHE_QUEUE_SESSION_DRIVER/" "${PROJECT_ROOT_DIR}/.env"
sed -i "s/^\(SESSION_DRIVER\s*=\s*\).*\$/\1$CACHE_QUEUE_SESSION_DRIVER/" "${PROJECT_ROOT_DIR}/.env"

# Change Ownership to www-data
chown -R www-data:www-data "${PROJECT_ROOT_DIR}"

# Create VirtualHost
if [ -f "/etc/nginx/sites-enabled/default" ]; then
  mv /etc/nginx/sites-enabled/default /root/nginx-default-config.bak
fi
cat >"/etc/nginx/conf.d/${PRIMARY_DOMAIN}.conf" <<EOL
server {
    listen 80;
    listen [::]:80;
    server_name ${PRIMARY_DOMAIN};
    root ${APPLICATION_WEB_ROOT_DIRECTORY};

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOL
# Restart Services

systemctl restart php8.1-fpm.service
systemctl restart nginx.service


# Enable Free SSL

echo "To Enable Free SSL you can run following command"
echo "sudo certbot --nginx -d ${PRIMARY_DOMAIN} -d www.${PRIMARY_DOMAIN}"