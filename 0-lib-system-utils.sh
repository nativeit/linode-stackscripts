#!/bin/bash
#
# Common utilities derived from https://cloud.linode.com/stackscripts/10444
#

function system_install_utils {
    DEBIAN_FRONTEND=noninteractive apt-get -y install htop iotop iftop bsd-mailx zsh vim-nox wget zip mc psmisc net-tools nodejs npm
}

function system_install_git {
    DEBIAN_FRONTEND=noninteractive apt-get -y install git-core
}

function system_install_mercurial {
    DEBIAN_FRONTEND=noninteractive apt-get -y install mercurial
}

function system_start_etc_dir_versioning {
    git config --global user.name "root"
    git config --global user.email "$NOTIFY_EMAIL"
    git init /etc
    git --git-dir /etc/.git --work-tree=/etc add /etc
    git --git-dir /etc/.git --work-tree=/etc commit -m "Started versioning of /etc directory" || echo > /dev/null # catch "nothing changed" return code
    chmod -R go-rwx /etc/.git
}

function system_record_etc_dir_changes {
    if [ ! -n "$1" ];
        then MESSAGE="Committed /etc changes"
        else MESSAGE="$1"
    fi
    git --git-dir /etc/.git --work-tree=/etc add -A /etc
    git --git-dir /etc/.git --work-tree=/etc commit -m "$MESSAGE" || echo > /dev/null # catch "nothing changed" return code
}

function system_install_java8 {
    DEBIAN_FRONTEND=noninteractive apt-get -y install dirmngr openjdk-8-jdk
}

function system_install_docker {
    DEBIAN_FRONTEND=noninteractive apt-get -y install dirmngr --install-recommends
    DEBIAN_FRONTEND=noninteractive apt-get -y install apt-transport-https ca-certificates curl gnupg2 software-properties-common
    apt-key adv --no-tty --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys F273FCD8
    DEBIAN_FRONTEND=noninteractive add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y install docker-ce docker-ce-cli containerd.io
}

function system_install_rancher {
docker run --privileged -d --restart=unless-stopped -p 80:80 -p 443:443 rancher/rancher
}

function system_setup_iptables {
    cat > /etc/iptables.firewall.rules << EOF
*filter

#  Allow all loopback (lo0) traffic and drop all traffic to 127/8 that doesn't use lo0
-A INPUT -i lo -j ACCEPT
-A INPUT ! -i lo -d 127.0.0.0/8 -j REJECT

#  Accept all established inbound connections
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

#  Allow all outbound traffic - you can modify this to only allow certain traffic
-A OUTPUT -j ACCEPT

#  Allow HTTP and HTTPS connections from anywhere (the normal ports for websites and SSL).
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT

#  Allow ports for testing
-A INPUT -p tcp --dport 8080:8090 -j ACCEPT

#  Allow ports for MOSH (mobile shell)
-A INPUT -p udp --dport 60000:61000 -j ACCEPT

#  Allow SSH connections
#  The -dport number should be the same port number you set in sshd_config
-A INPUT -p tcp -m state --state NEW --dport 22 -j ACCEPT

#  Allow ping
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT

#  Log iptables denied calls
-A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables denied: " --log-level 7

#  Reject all other inbound - default deny unless explicitly allowed policy
-A INPUT -j REJECT
-A FORWARD -j REJECT

COMMIT
EOF
    
    /sbin/iptables-restore < /etc/iptables.firewall.rules
    DEBIAN_FRONTEND=noninteractive apt-get -y install iptables-persistent
    mv /etc/iptables.firewall.rules /etc/iptables/rules.v4    
}

function system_setup_oom_policy {
    cat >> /etc/sysctl.conf << EOF
## Enable panic on OOM, reboot 10s after panicking
vm.panic_on_oom=1
kernel.panic=10
EOF
}

function postfix_install_gmail_relay {
    # Installs postfix and configure to listen only on the local interface. Also
    # allows for local mail delivery
	
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
    echo "postfix postfix/mailname string localhost" | debconf-set-selections
    echo "postfix postfix/destinations string localhost.localdomain, localhost" | debconf-set-selections
    DEBIAN_FRONTEND=noninteractive apt-get -y install postfix mailutils libsasl2-2 ca-certificates libsasl2-modules
    /usr/sbin/postconf -e "inet_interfaces = loopback-only"
    /usr/sbin/postconf -e "relayhost = [smtp.gmail.com]:587"
    /usr/sbin/postconf -e "mailbox_command = "
    /usr/sbin/postconf -e "smtp_sasl_auth_enable = yes"
    /usr/sbin/postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl/passwd"
    /usr/sbin/postconf -e "smtp_sasl_security_options = noanonymous"
    /usr/sbin/postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
    /usr/sbin/postconf -e "smtp_use_tls = yes"
    echo "[smtp.gmail.com]:587    $RELAY_EMAIL:$RELAY_PASSWORD" > /etc/postfix/sasl/passwd
    chmod 400 /etc/postfix/sasl/passwd
    postmap /etc/postfix/sasl/passwd
    cat /etc/ssl/certs/Thawte_Premium_Server_CA.pem | sudo tee -a /etc/postfix/cacert.pem
    echo "root: $NOTIFY_EMAIL" >> /etc/aliases
    /usr/bin/newaliases
    
    touch /tmp/restart-postfix
}

function system_configure_unattended_upgrades {
    DEBIAN_FRONTEND=noninteractive apt-get -y install unattended-upgrades apt-listchanges apt-config-auto-update
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << "END"
// Unattended-Upgrade::Origins-Pattern controls which packages are
// upgraded.
//
// Lines below have the format format is "keyword=value,...".  A
// package will be upgraded only if the values in its metadata match
// all the supplied keywords in a line.  (In other words, omitted
// keywords are wild cards.) The keywords originate from the Release
// file, but several aliases are accepted.  The accepted keywords are:
//   a,archive,suite (eg, "stable")
//   c,component     (eg, "main", "contrib", "non-free")
//   l,label         (eg, "Debian", "Debian-Security")
//   o,origin        (eg, "Debian", "Unofficial Multimedia Packages")
//   n,codename      (eg, "jessie", "jessie-updates")
//     site          (eg, "http.debian.net")
// The available values on the system are printed by the command
// "apt-cache policy", and can be debugged by running
// "unattended-upgrades -d" and looking at the log file.
//
// Within lines unattended-upgrades allows 2 macros whose values are
// derived from /etc/debian_version:
//   ${distro_id}            Installed origin.
//   ${distro_codename}      Installed codename (eg, "jessie")
Unattended-Upgrade::Origins-Pattern {
        // Codename based matching:
        // This will follow the migration of a release through different
        // archives (e.g. from testing to stable and later oldstable).
//      "o=Debian,n=jessie";
//      "o=Debian,n=jessie-updates";
//      "o=Debian,n=jessie-proposed-updates";
//      "o=Debian,n=jessie,l=Debian-Security";

        // Archive or Suite based matching:
        // Note that this will silently match a different release after
        // migration to the specified archive (e.g. testing becomes the
        // new stable).
//      "o=Debian,a=stable";
//      "o=Debian,a=stable-updates";
//      "o=Debian,a=proposed-updates";
//      "origin=Debian,codename=${distro_codename},label=Debian-Security";
        "origin=Debian,codename=${distro_codename}";
};

// List of packages to not update (regexp are supported)
Unattended-Upgrade::Package-Blacklist {
//	"vim";
//	"libc6";
//	"libc6-dev";
//	"libc6-i686";
};

// This option allows you to control if on a unclean dpkg exit
// unattended-upgrades will automatically run 
//   dpkg --force-confold --configure -a
// The default is true, to ensure updates keep getting installed
//Unattended-Upgrade::AutoFixInterruptedDpkg "false";

// Split the upgrade into the smallest possible chunks so that
// they can be interrupted with SIGUSR1. This makes the upgrade
// a bit slower but it has the benefit that shutdown while a upgrade
// is running is possible (with a small delay)
//Unattended-Upgrade::MinimalSteps "true";

// Install all unattended-upgrades when the machine is shuting down
// instead of doing it in the background while the machine is running
// This will (obviously) make shutdown slower
//Unattended-Upgrade::InstallOnShutdown "true";

// Send email to this address for problems or packages upgrades
// If empty or unset then no email is sent, make sure that you
// have a working mail setup on your system. A package that provides
// 'mailx' must be installed. E.g. "user@example.com"
//Unattended-Upgrade::Mail "root";
Unattended-Upgrade::Mail "root";

// Set this value to "true" to get emails only on errors. Default
// is to always send a mail if Unattended-Upgrade::Mail is set
//Unattended-Upgrade::MailOnlyOnError "true";

// Do automatic removal of new unused dependencies after the upgrade
// (equivalent to apt-get autoremove)
//Unattended-Upgrade::Remove-Unused-Dependencies "false";

// Automatically reboot *WITHOUT CONFIRMATION* if
//  the file /var/run/reboot-required is found after the upgrade 
//Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot "true";

// Automatically reboot even if there are users currently logged in.
//Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
// If automatic reboot is enabled and needed, reboot at the specific

// time instead of immediately
//  Default: "now"
//Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Use apt bandwidth limit feature, this example limits the download
// speed to 70kb/sec
//Acquire::http::Dl-Limit "70";

// Enable logging to syslog. Default is False
// Unattended-Upgrade::SyslogEnable "false";
Unattended-Upgrade::SyslogEnable "true";

// Specify syslog facility. Default is daemon
// Unattended-Upgrade::SyslogFacility "daemon";

END
  
}

function system_configure_persistent_journal {
    mkdir -p /var/log/journal
    systemd-tmpfiles --create --prefix /var/log/journal
    #killall -USR1 systemd-journald
    journalctl --flush
}
