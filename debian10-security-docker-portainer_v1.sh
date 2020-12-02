#!/bin/bash
#
# Debian 10 w/basic setup, security, postfix gmail relay, openjdk8, Docker, Rancher
#
# Copyright (c) 2020 Native IT
#
# IMPORTANT: Once deployed, visit https://{host}:9000 to change the default admin password!
# 
# <UDF name="user1_name" label="User 1 account name" example="This is the account that you will be using to log in." />
# <UDF name="user1_password" label="User 1 password" />
# <UDF name="user1_sshkey" label="Public Key for user 1" default="" example="Recommended method of authentication. It is more secure than password log in." />
# <UDF name="user1_shell" label="Shell" oneof="/bin/zsh,/bin/bash" default="/bin/bash" />
#
# <UDF name="domain" label="System domain name" default="example.com" example="Domain w/out hostname" />
# <UDF name="fqdn" label="Fully Qualified Domain Name (FQDN)" example="Example: docker01.mydomain.com" />
# <UDF name="enable_le" label="Use Let's Encrypt to manage Portainer's HTTPS certificate? (Y/n)" default="Y" />
# <UDF name="letsencrypt_email" label="E-mail address for Let's Encrypt" default="sdavis@nativeit.net" />
# <UDF name="tz" label="Time Zone" default="America/New_York" example="Example: America/New_York (see: http://bit.ly/TZlisting)" />
#
# <UDF name="sshd_passwordauth" label="Allow SSH password authentication" oneof="Yes,No" default="No" example="Turn off password authentication if you have added a Public Key." />
# <UDF name="sshd_permitrootlogin" label="Allow SSH root login" oneof="No,Yes" default="No" example="Root account should not be exposed." />
# <UDF name="relay_email" label="Gmail email including domain as relay" example="Email used to login into Gmail/GApps" />
# <UDF name="relay_password" label="Gmail account app-specific password" example="Email account password (app specific with 2factor auth)" />


# Setup "Unofficial Bash Strict Mode" -- http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -e # Exit immediately on error
set -u # Throw error on undefined variable
#set -x # Uncomment to enable debugging

exec &> /root/stackscript.log

set +u

source <ssinclude StackScriptID="1"> # StackScript Bash Library
#source ./linode-ss1.sh

source <ssinclude StackScriptID="691666"> # lib-system-utils
#source ./lib-system-utils.sh

source <ssinclude StackScriptID="691674"> # lib-system-debian
#source ./lib-system-debian.sh

set -u

# Set variables
IPADDR=$(/sbin/ifconfig eth0 | awk '/inet / { print $2 }' | sed 's/addr://')
USER_GROUPS=sudo
NOTIFY_EMAIL=$LETSENCRYPT_EMAIL

echo "###################################################################################"
echo "Please be Patient: Installation will start now....... It may take some time :)"
echo "###################################################################################"

###########################################################
# System
###########################################################

# System update
debian_upgrade
system_update

# Set timezone
system_set_timezone "$TZ"

# Setup /etc versioning
system_install_git
system_start_etc_dir_versioning 

# Initialize hostname
system_update_hostname "$FQDN"
system_record_etc_dir_changes "Updated hostname" 

# Setup NTP
system_configure_ntp

###########################################################
# User & Security
###########################################################

# Create user accounts
system_add_user "$USER1_NAME" "$USER1_PASSWORD" "$USER_GROUPS" "$USER1_SHELL"
if [ "$USER1_SSHKEY" ]; then
    system_user_add_ssh_key "$USER1_NAME" "$USER1_SSHKEY"
fi

system_record_etc_dir_changes "Added user accounts"

# Configure sshd
system_sshd_permitrootlogin "$SSHD_PERMITROOTLOGIN"
system_sshd_passwordauthentication "$SSHD_PASSWORDAUTH"
touch /tmp/restart-ssh
system_record_etc_dir_changes "Configured sshd" # SS124

# Lock user account if not used for login
if [ "SSHD_PERMITROOTLOGIN" == "No" ]; then
    system_lock_user "root"
    system_record_etc_dir_changes "Locked root account" # SS124
fi

# Install Postfix
postfix_install_gmail_relay
system_record_etc_dir_changes "Installed postfix gmail relay" 

# Setup logcheck
system_security_logcheck
system_record_etc_dir_changes "Installed logcheck" 

# Setup fail2ban
system_security_fail2ban
system_record_etc_dir_changes "Installed fail2ban"

# Install basic system utilities
system_install_utils
system_record_etc_dir_changes "Installed common utils"

# Install UFW
system_security_ufw_install
system_record_etc_dir_changes "Installed UFW"

# Setup UFW
system_security_ufw_configure_basic
system_record_etc_dir_changes "Setup UFW with basic settings"

# Install Docker
system_install_docker

# Generate TLS certificates via Let's Encrypt for Portainer
apt update && apt install certbot -y
if [ -n $LETSENCRYPT_EMAIL ] && [ -n $FQDN ] && [ "${ENABLE_LE,,}" = 'y' ] && [ "${ENABLE_WWW,,}" = 'y' ]
then
  certbot certonly --standalone --preferred-challenges http --email "${LETSENCRYPT_EMAIL}" --noninteractive --quiet --agree-tos -d $FQDN -d www.$FQDN
elif [ -n $LETSENCRYPT_EMAIL ] && [ -n $FQDN ] && [ "${ENABLE_LE,,}" = 'y' ]
then
  certbot certonly --standalone --preferred-challenges http --email "${LETSENCRYPT_EMAIL}" --noninteractive --quiet --agree-tos -d $FQDN
fi
if [ "${ENABLE_LE,,}" = 'y' ]
then
  cat <(crontab -l) <(echo "0 1,13 * * * certbot renew") | crontab -
fi

# Create portainer_data volume
mkdir /usr/share/portainer_data
docker volume create portainer_data

# Setup admin password
 echo -n $USER1_PASSWORD > /tmp/portainer_password

# Install Portainer
docker run -d -p 9000:9000 --restart unless-stopped --name portainer \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v /usr/share/portainer_data:/data \
  -v /tmp/portainer_password:/tmp/portainer_password \
	-v /etc/letsencrypt/live/$FQDN:/certs/live/$FQDN:ro \
	-v /etc/letsencrypt/archive/$FQDN:/certs/archive/$FQDN:ro \
	portainer/portainer-ce \
  --admin-password-file /tmp/portainer_password \
  --ssl --sslcert /certs/live/$FQDN/cert.pem --sslkey /certs/live/$FQDN/privkey.pem
system_record_etc_dir_changes "Setup Portainer Docker container"

# Install ctop: https://github.com/bcicen/ctop
wget https://github.com/bcicen/ctop/releases/download/v0.7/ctop-0.7-linux-amd64 -O /usr/local/bin/ctop
chmod +x /usr/local/bin/ctop

# Set firewall ports for Portainer & CapRover
ufw allow 3000,996,7946,4789,2377/tcp
ufw allow 7946,4789,2377/udp
ufw reload

# Install Caprover
    cat << EOF > /tmp/caprover.json
    {"caproverIP": $IPADDR, "caproverPassword": $USER1_PASSWORD, "caproverRootDomain": $DOMAIN, "newPassword": $USER1_PASSWORD, "certificateEmail": $LETSENCRYPT_EMAIL, "caproverName": "captain-$DOMAIN"}
EOF
    docker run -p 80:80 -p 443:443 -p 3000:3000 -v /var/run/docker.sock:/var/run/docker.sock -v /captain:/captain caprover/caprover
    npm install -g caprover
    caprover serversetup -c /tmp/caprover.json

# Retain log after reboot
system_configure_persistent_journal
system_record_etc_dir_changes "Configure persistent journal"

# Send info message
cat > ~/setup_message <<EOD
Hi,

Your Linode VPS configuration is completed. You may access Portainer at https://$FQDN:9000 or Caprover at https://$FQDN:3000.

EOD

mail -s "Your Linode VPS $FQDN is ready" "$NOTIFY_EMAIL" < ~/setup_message

# Wrap it up
automatic_security_updates
goodstuff
all_set
restartServices

# Reboot
reboot

