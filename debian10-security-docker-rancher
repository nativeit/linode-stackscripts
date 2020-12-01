#!/bin/bash
#
# Debian 10 w/basic setup, security, postfix gmail relay, openjdk8, Docker, Rancher
#
# Copyright (c) 2020 Native IT
#
# <UDF name="notify_email" Label="Send email notification to" example="Email address to send notification and system alerts. Check Spam folder if you don't receive a notification within 6 minutes." />
#
# <UDF name="user1_name" label="User 1 account name" example="This is the account that you will be using to log in." />
# <UDF name="user1_password" label="User 1 password" />
# <UDF name="user1_sshkey" label="Public Key for user 1" default="" example="Recommended method of authentication. It is more secure than password log in." />
# <UDF name="user1_shell" label="Shell" oneof="/bin/zsh,/bin/bash" default="/bin/bash" />
# <UDF name="sshd_passwordauth" label="Allow SSH password authentication" oneof="Yes,No" default="No" example="Turn off password authentication if you have added a Public Key." />
# <UDF name="sshd_permitrootlogin" label="Allow SSH root login" oneof="No,Yes" default="No" example="Root account should not be exposed." />
# <UDF name="sys_hostname" label="System hostname" default="myvps" example="Name of your server, i.e. linode1." />
# <UDF name="relay_email" label="Gmail email including domain as relay" example="Email used to login into Gmail/GApps" />
# <UDF name="relay_password" label="Gmail account app-specific password" example="Email account password (app specific with 2factor auth)" />

set -e
set -u
#set -x

USER_GROUPS=sudo

exec &> /root/stackscript.log

source <ssinclude StackScriptID="1"> # StackScript Bash Library
#source ./linode-ss1.sh

source <ssinclude StackScriptID="691666"> # lib-system-utils
#source ./lib-system-utils.sh

source <ssinclude StackScriptID="691674"> # lib-system-debian
#source ./lib-system-debian.sh

# Basic system update
system_install_locales
system_set_timezone

# Setup /etc versioning
system_install_git
system_start_etc_dir_versioning 

# Initialize hostname
system_update_hostname "$SYS_HOSTNAME"
system_record_etc_dir_changes "Updated hostname" 

# Setup firewall
system_setup_iptables
system_record_etc_dir_changes "Enabled firewall"

# Create user accounts
system_add_user "$USER1_NAME" "$USER1_PASSWORD" "$USER_GROUPS" "$USER1_SHELL"
if [ "$USER1_SSHKEY" ]; then
    system_user_add_ssh_key "$USER1_NAME" "$USER1_SSHKEY"
fi

system_record_etc_dir_changes "Added user accounts"

#system_rbackup_install "rbackup"
#system_record_etc_dir_changes "Added rbackup"

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

# Install OpenJDK8 and set it as system default
system_install_java8
system_record_etc_dir_changes "Installed java8"

# Install Docker
system_install_docker
system_record_etc_dir_changes "Installed docker"

# Install Rancher
system_install_rancher
system_record_etc_dir_changes "Setup Rancher Docker container"

# Setup kernel OOM policy
system_setup_oom_policy
system_record_etc_dir_changes "Set panic on OOM + reboot"

# Retain log after reboot
system_configure_persistent_journal
system_record_etc_dir_changes "Configure persistent journal"

# Install all updates (including eventual service restarts)
system_configure_unattended_upgrades
system_record_etc_dir_changes "Configure automatic upgrades at 2am"

# Restart changed services
restart_services

# Send info message
cat > ~/setup_message <<EOD
Hi,

Your Linode VPS configuration is completed.

EOD

mail -s "Your Linode VPS $(hostname) is ready" "$NOTIFY_EMAIL" < ~/setup_message
