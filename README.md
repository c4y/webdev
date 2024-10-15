# Entwicklungsumgebung

Das Ziel dieser Entwicklungsumgebung ist eine Docker-basierte Lösung auf einem Linux Server analog Devilbox mit den folgenden Vorteilen:

- One-Click-Installation
- alle Projekte sind automatisch lokal über projekt.local.example.de erreichbar
- alle Projekte können nach außen "freigeschaltet" werden inkl. SSL, z.B. projekt.dev.example.de
- jedes Projekt ist gleichzeitig über mehrere PHP Versionen aufrufbar, z.B. projekt.dev.example.de:8074 (PHP 7.4)
- VS Code Remote inkl. Xdebug
- VS Code im Browser
- Mailhog

## Installation (ohne Proxmox)

```
curl -sL https://contao4you.de/webdev-setup | sudo bash
```

**Weitere Schritte**
- Einrichten eines DynDNS Dienstes (falls nicht vorhanden). Z.B. bei ipv64.net.
- Anlegen eines DNS Eintrages *.local.example.de A 192.168.1.x (IP-Adresse des Web-Containers)
- Anlegen eines DNS Eintrages *.dev.example.de CNAME example.ipv64.net 
- im Router die DNS Server 1.1.1.1/8.8.8.8 eintragen (zumindest in der Fritzbox)
- im Router eine Port-Weiterleitung vom Port 80+443 auf den proxy-Container einrichten

## Installation in Proxmox

1. Container "Web"
- Einen Ubuntu 24.04 Container erstellen
- Docker installieren
- Benutzer web erstellen
- ssh für web freischalten
- Rechte für web anpassen
- cd /var
- git clone https://github.com/c4y/webdev.git
- sudo docker compose up -d

2. Container "proxy"
- Einen Ubuntu 24.04 Container erstellen
- Docker installieren
- docker-compose.yml downloaden
- sudo docker compose up -d


**weitere Schritte**
siehe Installation ohne Proxmox.


## Einrichten eines Projektes

In /var/www befinden sich alles, was zur Entwicklungsumgebung gehört. In /var/www/html befinden sich alle Projekte. 

Um ein neues Projekt zu starten (z.B. Contao) geht man nun wie folgt vor:

- cd /var/www/html
- composer create-project contao/managed-edition contao-test 5.4

Das war's! 

Das Projekt ist nun mit allen Endgeräten im lokalen Netzwerk unter http://contao-test.local.example.de erreichbar. Möchte man nun das Projekt öffentlich verfügbar machen, startet man den nginx Proxy Manager. Dieser ist unter der bei der Installation angegebenen IP-Adresse aufrufbar, z.B. http://192.168.1.x/81. Hier richtet man nun einen Proxy Host ein (per GUI). Nun ist die Webseite öffentlich inkl. SSL (Lets Encrypt) erreichbar. 

Im Fall von Contao/Symfony muss für den Proxy noch ein Eintrag in der .env erfolgen:

```
.env.local
TRUSTED_PROXIES=IP-ADRESSE-DES-NGINX-PROXY
```

Zum Testen der E-Mails/Formulare kann der lokale Mailhog Service genutzt werden:

```
# .env.local
MAILER_DSN=smtp://egal:egal@IP-ADRESSE-DES-WEB-CONTAINERS:1025
```

Mailhog ist über http://IP-ADRESSE-DES-WEB-CONTAINERS:8025 erreichbar.

## Backup

```
crontab -e
0 0 * * * /var/www/bin/backup.sh
```

## nginx Proxy Manager

Benutzername: admin@example.com
Passwort: changeme