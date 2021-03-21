#!/bin/bash

echo "encpass.sh requires a POSIX-compliant shell and openssl"
echo "encpass.sh provides a lightweight solution for using encrypted passwords in shell scripts. It allows a user to encrypt a password (or any other secret) at runtime and then use it, decrypted, within a script. This prevents shoulder surfing secrets and avoids storing the secret in plain text, which could inadvertently be sent to or$
echo --
echo "Please wait while encpass.sh is installed."

## Download and install encpass.sh to /usr/local/bin        
    curl https://raw.githubusercontent.com/ahnick/encpass.sh/master/encpass.sh -o /usr/local/bin/encpass.sh    

## Create temporary file for rc arguments
    touch /tmp/encpassrc

## Write rc arguments for command completion, aliasing, and encpass home directory function
    cat <<'EOF' | tee -a /tmp/encpassrc >/dev/null
      # encpass.sh
      alias ep="encpass.sh"
      export ENCPASS_HOME_DIR="$HOME/.encpass"
      export ENCPASS_DIR_LIST="$HOME/.encpass"  # colon delimited list of dirs
      ehd() { export ENCPASS_HOME_DIR="$1"; [ -f "$1/completion" ] && . "$1/completion"; }
      ehd $ENCPASS_HOME_DIR
    EOF

echo "encpass.sh runtime arguments will be added as aliases in user rc files"

## Add rc arguments to bashrc files for existing and new users

    cp ~/.bashrc{,.bak.`date +%F`}                      # Create backup of ~/.bashrc
    cat /tmp/encpassrc >> ~/.bashrc

    cp /etc/skel/.bashrc{,.bak.`date +%F`}              # Create backup of /etc/skel/.bashrc
    cat /tmp/encpassrc >> /etc/skel/.bashrc

    cp /etc/bash.bashrc{,.bak.`date +%F`}               # Create backup of /etc/bash.bashrc
    cat /tmp/encpassrc >> /etc/bash.bashrc

## Clean up 
    rm /tmp/encpassrc 

echo "Done. See https://github.com/plyint/encpass.sh/blob/master/examples/example.sh for examples of calling the get_secret function."    

cp "$0"{,.bak.`date +%F`}
rm -- "$0"
 