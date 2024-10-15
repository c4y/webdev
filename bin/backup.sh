#!/bin/bash

set -e

# SSH_SERVER=
WEB_FOLDER=/var/www/html
DB_FOLDER=/var/www/database_backups
MYSQL_USER=root
MYSQL_PASSWORD=root
MYSQLDUMP=/usr/bin/mysqldump
MYSQL=/usr/bin/mysql

# Sichern der Datenbanken
backup_db() {
  if [ -d "$DB_FOLDER" ]; then
    rm -R $DB_FOLDER
  fi  
  mkdir $DB_FOLDER
  databases=`$MYSQL --defaults-extra-file=/var/www/mysql/config.cnf -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|mysql)"` 
  for db in $databases; do
    $MYSQLDUMP --defaults-extra-file=/var/www/mysql/config.cnf --force --opt --column-statistics=0 --databases $db | gzip > "$DB_FOLDER/$db.sql.gz"
  done
}

catch() {
   # echo -e "Subject: Backup-Fehler\nFehler in Zeile $1" #| msmtp info@contao4you.de
   if [ "$1" != "0" ]; then
    echo "Error $1 occurred on $2"
  fi
 }

echo `date +"%y%m%d-%H%M%S Datenbank Dumps werden erzeugt"` > /var/www/backup.log 2>&1
backup_db
echo `date +"%y%m%d-%H%M%S Die Webseiten werden gesichert"` >> /var/www/backup.log 2>&1
rsync -avz -e 'ssh -p23' --delete --exclude-from=/var/www/rsync-excludes /var/www/html/ u349110@u349110.your-storagebox.de:/home/backups/html 
echo `date +"%y%m%d-%H%M%S Die Datenbanken werden gesichert"` >> /var/www/backup.log 2>&1
rsync -avz -e 'ssh -p23' --delete /var/www/database_backups/ uXXX@uXXX.your-storagebox.de:/home/backups/databases/ 
echo `date +"%y%m%d-%H%M%S Sicherung erfolgreich beendet"` >> /var/www/backup.log 2>&1