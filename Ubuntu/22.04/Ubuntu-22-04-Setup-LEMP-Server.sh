#!/bin/bash
# Configuration BEGIN
SWAP_MEMORY_SIZE=2G
DB_NAME=AppDB
DB_USERNAME=appdbu
DB_PASSWORD=`head -c 10 /dev/random | md5sum | head -c 15`
DB_HOST="localhost"

PHP_VERSION="php8.1"
NODEJS_VERSION="16.x"

# Config END

# Get Input From User
read -e -p "Enter SWAP Memory:" -i "2G" SWAP_MEMORY_SIZE


read -e -p "Enter DataBase Name:" -i "$DB_NAME" DB_NAME
read -e -p "Enter DB Username:" -i "$DB_USERNAME" DB_USERNAME
read -e -p "Enter DB Password:" -i "$DB_PASSWORD" DB_PASSWORD

# Update Repository
sudo apt update -y
sudo apt-get install -y language-pack-en-base
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Setup Swap Memory
sudo fallocate -l $SWAP_MEMORY_SIZE /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo sysctl vm.swappiness=20
echo 'vm.swappiness=20' | sudo tee -a /etc/sysctl.conf
sudo sysctl vm.vfs_cache_pressure=40
echo 'vm.vfs_cache_pressure=40' | sudo tee -a /etc/sysctl.conf
# Install Common Software
sudo apt-get install software-properties-common vim htop tree curl zip unzip git -y

# Install Nginx
sudo apt-get install -y nginx
sudo ufw allow 'Nginx Full'
sudo systemctl restart nginx.service
sudo systemctl enable nginx.service
# Install Supervisor
sudo apt-get install -Y supervisor
sudo systemctl restart supervisor.service
sudo systemctl enable supervisor.service
# Install Redis
sudo apt install -y redis-server
sudo systemctl restart redis-server.service
sudo systemctl enable redis-server.service

# Install Mysql
sudo apt install -y mysql-server
sudo systemctl restart mysql.service
sudo systemctl enable mysql.service

# Create Mysql DB and User
echo "#Database Credentials" | sudo tee -a ~/deployapps_io_credentials
echo "DB_NAME=${DB_NAME}" | sudo tee -a ~/deployapps_io_credentials
echo "DB_USERNAME=${DB_USERNAME}" | sudo tee -a ~/deployapps_io_credentials
echo "DB_PASSWORD=${DB_PASSWORD}" | sudo tee -a ~/deployapps_io_credentials
echo "DB_HOST=${DB_HOST}" | sudo tee -a ~/deployapps_io_credentials

mysql -e "CREATE DATABASE ${DB_NAME} /*\!40100 DEFAULT CHARACTER SET utf8 */;"
mysql -e "CREATE USER \`${DB_USERNAME}\`@\`${DB_HOST}\` IDENTIFIED BY '${DB_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO \`${DB_USERNAME}\`@\`${DB_HOST}\`;"
mysql -e "FLUSH PRIVILEGES;"


# Install NodeJS
curl -sL "https://deb.nodesource.com/setup_${NODEJS_VERSION}" | sudo bash -
sudo apt-get install -y nodejs

# PHP
sudo add-apt-repository --yes ppa:ondrej/php
sudo apt update -y
sudo apt install -y ${PHP_VERSION}
sudo apt install -y ${PHP_VERSION}-fpm
sudo apt install -y ${PHP_VERSION}-bcmath ${PHP_VERSION}-curl ${PHP_VERSION}-gd ${PHP_VERSION}-intl ${PHP_VERSION}-mbstring ${PHP_VERSION}-mysql ${PHP_VERSION}-xml ${PHP_VERSION}-zip ${PHP_VERSION}-redis

# Install Composer
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
sudo chmod +x /usr/local/bin/composer

# Install Certbot
sudo apt-get install -y certbot python3-certbot-nginx