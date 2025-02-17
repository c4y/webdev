#!/usr/bin/bash

source setup.conf

#====================================================================
# Pakete installieren
#====================================================================
apt update
apt -y install samba net-tools bridge-utils vsftpd ca-certificates curl unzip git
install -m 0755 -d /etc/apt/keyrings


#====================================================================
# git Repository clonen
#====================================================================
cd /var
git clone https://github.com/c4y/webdev.git
mv webdev www
cd /var/www

#====================================================================
# Docker installieren
#====================================================================
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

#====================================================================
# Benutzer anlegen
#====================================================================
deluser --remove-home ubuntu
mkdir -p /var/www
mkdir -p /home/web
sudo useradd -s /bin/bash -g www-data -u 1000 web && echo "web:web" | sudo chpasswd
chown web:www-data /var
chown -R web:www-data /var/www
chmod 775 /var
chmod -R 775 /var/www
chmod +x /var


#====================================================================
# FTP mit write-access aktivieren
#====================================================================
grep -rl '#write_enable=YES' /etc/vsftpd.conf | xargs sed -i "s/#write_enable=YES/write_enable=YES/g"
grep -rl '#local_umask=022' /etc/vsftpd.conf | xargs sed -i "s/#local_umask=022/local_umask=002/g"
service vsftpd restart


#====================================================================
# Samba einrichten
#====================================================================
sudo bash -c "cat <<EOF >> /etc/samba/smb.conf
[web]
path = /var/www
writeable = yes
valid users = web
EOF"

SAMBA_USER="web"
SAMBA_PASSWORD="web"
(echo "$SAMBA_PASSWORD"; echo "$SAMBA_PASSWORD") | sudo smbpasswd -a "$SAMBA_USER"

sudo systemctl restart smbd.service 

#====================================================================
# Domain/nginx anpassen
#====================================================================
cp -f configs/nginx/nginx.conf.txt configs/nginx/nginx.conf
grep -l 'example.com' configs/nginx/nginx.conf | xargs sed -i "s/example.com/$domain/g"


#====================================================================
# IP-Adresse vom Container ermitteln
#====================================================================
ip=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)


#====================================================================
# XDEBUG IP Adresse eintragen
#====================================================================
# Kopiere jede xdebug.txt nach xdebug.ini, ohne die xdebug.txt zu verändern
for file in configs/php/*/xdebug.txt; do
  cp "$file" "${file%.txt}.ini"
done

# Ersetze "CONTAINER_IPv4" nur in den xdebug.ini Dateien
grep -rl 'CONTAINER_IPv4' configs/php/*/xdebug.ini | xargs sed -i "s/CONTAINER_IPv4/$ip/g"


#====================================================================
# mysql Config anpassen
#====================================================================
cp -f configs/mysql/config.cnf.txt configs/mysql/config.conf
grep -rl 'a.b.c.d' configs/mysql/config.cnf | xargs sed -i "s/a.b.c.d/$ip/g"
chmod 777 configs/mysql/config.cnf

#====================================================================
# PHP Repository einbinden und PHP installieren
#====================================================================
sudo apt-get install software-properties-common
add-apt-repository -y ppa:ondrej/php
apt update

apt -y install php7.4-curl php7.4-fpm php7.4-gd php7.4-imagick php7.4-intl php7.4-mbstring php7.4-mysql php7.4-xml php7.4-zip
apt -y install php8.1-curl php8.1-fpm php8.1-gd php8.1-imagick php8.1-intl php8.1-mbstring php8.1-mysql php8.1-xml php8.1-zip
apt -y install php8.2-curl php8.2-fpm php8.2-gd php8.2-imagick php8.2-intl php8.2-mbstring php8.2-mysql php8.2-xml php8.2-zip
apt -y install php8.3-curl php8.3-fpm php8.3-gd php8.3-imagick php8.3-intl php8.3-mbstring php8.3-mysql php8.3-xml php8.3-zip



#====================================================================
# SSH per User erlauben
#====================================================================
rm /etc/ssh/sshd_config.d/*
sudo bash -c "cat <<EOF > /etc/ssh/sshd_config.d/web.conf
PasswordAuthentication yes
PermitRootLogin yes
EOF"
systemctl restart ssh


#====================================================================
# Composer installieren
#====================================================================
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('sha384', 'composer-setup.php') === 'dac665fdc30fdd8ec78b38b9800061b4150413ff2e3b6f88543c636f7cd84f6db9189d43a81e5503cda447da73c7e5b6') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php
php -r "unlink('composer-setup.php');"
mv composer.phar /usr/local/bin/composer


#====================================================================
# Aliases hinzufügen
#====================================================================
sudo bash -c "cat <<EOF > /home/web/.bash_aliases
alias php74="/usr/bin/php74"
alias php81="/usr/bin/php81"
alias php82="/usr/bin/php82"
alias php83="/usr/bin/php83"
alias composer74="/usr/bin/php7.4 /usr/local/bin/composer"
alias composer81="/usr/bin/php8.1 /usr/local/bin/composer"
alias composer82="/usr/bin/php8.2 /usr/local/bin/composer"
alias cmigrate="vendor/bin/contao-console contao:migrate"
alias csetup="vendor/bin/contao-console contao:setup"
ccreate() {
    composer create-project contao/managed-edition $1 $2
}
EOF"


#====================================================================
# Docker starten
#====================================================================
cd /var/www
mkdir -p /var/www/configs/coder/.local
chmod 777 /var/www/configs/coder/.local
docker compose up -d
