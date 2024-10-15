#!/usr/bin/bash

#====================================================================
# Set config file
#====================================================================
sudo bash -c "cat <<EOF > setup.conf
containername_www=web
containername_nginx=proxy
webip=192.168.1.253
proxyip=192.168.1.252
gateway=192.168.1.1
domain=example.de
containersize_www=5GB
EOF"


#====================================================================
# Prompt User Function with default Value
#====================================================================
prompt_user() {
  local hint="$1"
  local current_value="$2"
  local user_input
  

  read -p "$hint [$current_value]: " user_input
  if [ -n "$user_input" ]; then
    echo "$user_input"
  else
    echo "$current_value"
  fi
}


#====================================================================
# Get Config Variables
#====================================================================
echo "============================="
echo "Installing Web-Development..."
echo "============================="

containername_www=$(prompt_user "Container-Name für die Web-Entwicklung:"  "$containername_www")
containersize_www=$(prompt_user "Container-Größe für die Web-Entwicklung:" "$containersize_www")
containername_nginx=$(prompt_user "Container-Name für den nginx:" "$containername_nginx")
webip=$(prompt_user "Feste IP-Adresse für den Web-Container:" "$webip")
proxyip=$(prompt_user "Feste IP-Adresse für den Proxy-Manager:" "$proxyip")
gateway=$(prompt_user "IP-Adresse des Gateways:" "$gateway")
domain=$(prompt_user "Domain (bei z.B dev.example.de bitte nur example.de eingeben. Siehe Readme):" "$domain")


#====================================================================
# Write Config
#====================================================================
sudo bash -c "cat <<EOF > /etc/netplan/50-cloud-init.yaml 
containername_www=$containername_www
containersize_www=$containersize_www
webip=$webip
containername_nginx=$containername_nginx
proxyip=$proxyip
gateway=$gateway
domain=$domain
EOF"


#====================================================================
#  Create the bridge
#====================================================================
echo "============================="
echo "Setup bridge for LXC..."
echo "============================="
main_iface=$(ip route | grep default | awk '{print $5}' | head -n 1)
hostip=$(ip -4 addr show $main_iface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
	
sudo bash -c "cat <<EOF > /etc/netplan/50-cloud-init.yaml 
network:
    version: 2
    renderer: networkd
    ethernets:
        $main_iface:
          dhcp4: false
    bridges:
        br0:
          interfaces: [$main_iface]
          dhcp4: false  
          addresses:
            - $hostip/24  
          routes:
            - to: default
              via: $gateway
          nameservers:
            addresses: [1.1.1.1, 8.8.8.8]
          parameters:
            stp: false
            forward-delay: 0
EOF"
  # Apply the netplan configuration 
  sudo chmod 700 /etc/netplan/50-cloud-init.yaml
  sudo netplan apply 
  echo "Bridge br0 created and configured." 


#====================================================================
# Adopt container size for LXD
#====================================================================
# Containergröße für Web in die INI Datei schreiben
sed -i '/^\s*size:\s*/s/size: .*/size: '"$containersize_www"'/' "lxd-init.yaml"


#====================================================================
# Install LXD with Snap
#====================================================================
echo "============================="
echo "Installing LXC/LXD..."
echo "============================="
sudo apt install -y snapd
sudo apt update
sudo snap install lxd

sudo bash -c "cat <<EOF > lxd-init.yaml 
config: {}
networks:
- config:
    ipv4.address: auto
    ipv6.address: auto
  description: ""
  name: lxdbr0
  type: bridge
storage_pools:
- config:
    source: /var/snap/lxd/common/lxd/disks/default.img
    size: 5GB
  description: ""
  name: default
  driver: zfs
profiles:
- config: {}
  description: ""
  devices:
    root:
      path: /
      pool: default
      type: disk
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
  name: default
cluster: null
EOF"

if lxc info | grep -q "config: {}"; then
  echo "Starting lxd init..."
  sudo cat lxd-init.yaml | lxd init --preseed
fi
rm lxd-init.yaml


#====================================================================
#  Create the LXC "bridge" Profile
#====================================================================
echo "============================="
echo "LXC bridge-Profil erstellen..."
echo "============================="
PROFILE_NAME="bridge"

# Check if profile already exists
if lxc profile list | grep -q "^| $PROFILE_NAME "; then
  echo "Profile '$PROFILE_NAME' already exists."
else
  echo "Creating profile '$PROFILE_NAME'..."
  lxc profile create "$PROFILE_NAME"
  lxc profile device add "$PROFILE_NAME" eth0 nic nictype=bridged parent=br0
  lxc profile device add "$PROFILE_NAME" root disk path=/ pool=default
  echo "LXD Profile '$PROFILE_NAME' created successfully."
fi


#====================================================================
# Create Web-Container
#====================================================================
echo "============================="
echo "Web Container erstellen und starten..."
echo "============================="
lxc launch ubuntu:24.04 $containername_www -p bridge -c security.privileged=true -c security.nesting=true

echo "Waiting for the container to start..."
while [ "$(lxc info $containername_www | grep 'Status: RUNNING')" == "" ]; do
  sleep 1
done

echo "Waiting for the container to be ready..."
while ! lxc exec $containername_www -- ls / >/dev/null 2>&1; do
  sleep 1
done

echo "Web Container is ready..."


#====================================================================
# Set static IP to Web-Container
#====================================================================
echo "============================="
echo "Set static IP for Web-Container..."
echo "============================="

sudo bash -c "cat <<EOF > 01-web-init.yaml 
network:
    version: 2
    ethernets:
        eth0:
          dhcp4: false
          addresses:
            - $webip/24
          routes:
            - to: default
              via: $gateway
          nameservers:
            addresses: [1.1.1.1, 8.8.8.8]
EOF"

sleep 1
lxc file delete -- "${containername_www}/etc/netplan/50-cloud-init.yaml"
lxc file push 01-web-init.yaml ${containername_www}/etc/netplan/
lxc exec web -- chmod 700 /etc/netplan/01-web-init.yaml
lxc restart $containername_www
rm 01-web-init.yaml

echo "Static IP ${webip} for Web-Container is set..."

#====================================================================
# Install docker in Web-Container and start
#====================================================================
echo "============================="
echo "Install docker in Web-Container and start services..."
echo "============================="
sleep 1
lxc file push setup.conf $containername_www/root/
curl -O https://raw.githubusercontent.com/c4y/webdev/refs/heads/main/setup/setup-container.web.sh
lxc file push setup-container-web.sh $containername_www/root/
rm setup-container.web.sh
lxc exec $containername_www bash /root/setup-container-web.sh

echo "Web is ready..."

#====================================================================
# Create Proxy-Container
#====================================================================
echo "============================="
echo "Proxy Container erstellen und starten..."
echo "============================="
lxc launch ubuntu:24.04 $containername_nginx -p bridge -c security.privileged=true -c security.nesting=true

echo "Waiting for the container to start..."
while [ "$(lxc info $containername_nginx | grep 'Status: RUNNING')" == "" ]; do
  sleep 1
done

echo "Waiting for the container to be ready..."
while ! lxc exec $containername_nginx -- ls / >/dev/null 2>&1; do
  sleep 1
done

echo "Container ${containername_nginx} is ready..."


#====================================================================
# Set static IP to Proxy-Container
#====================================================================
echo "============================="
echo "Set static IP for Proxy-Container..."
echo "============================="

sudo bash -c "cat <<EOF > 01-web-init.yaml 
network:
    version: 2
    renderer: networkd
    ethernets:
        eth0:
          dhcp4: false
          addresses:
            - $proxyip/24
          routes:
            - to: default
              via: $gateway
          nameservers:
            addresses: [1.1.1.1, 8.8.8.8]
EOF"

sleep 1
lxc file delete $containername_nginx/etc/netplan/50-cloud-init.yaml
lxc file push 01-web-init.yaml $containername_nginx/etc/netplan/01-web-init.yaml
rm 01-web-init.yaml
lxc restart $containername_nginx

#====================================================================
# Install docker in nginx-Container and start
#====================================================================
echo "============================="
echo "Install docker in nginx-Container and start services..."
echo "============================="
sleep 1
lxc file push setup.conf $containername_nginx/root/
curl -O https://raw.githubusercontent.com/c4y/webdev/refs/heads/main/setup/setup-container-nginx.sh
lxc file push setup-container-nginx.sh $containername_nginx/root/
lxc exec $containername_nginx bash /root/setup-container-nginx.sh
rm setup-container-nginx.sh
echo "Container ${containername_nginx} is ready..."


#====================================================================
# Ready
#====================================================================
echo "============================="
echo "Try http://example.local.${domain}"
echo "============================="


