#!/bin/bash

# Add Longview repo to sources
echo "deb http://apt-longview.linode.com/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/longview.list
wget https://apt-longview.linode.com/linode.gpg -O /etc/apt/trusted.gpg.d/linode.gpg

# Generate new Longview client, pipe response to longview.json
curl -H "Content-Type: application/json" \
    -H "Authorization: Bearer 3b8c3ec9c71dc0265b51218c8864903ba3f84be1899862dd3e7d1614d8d517fb" \
    -X POST -d '{
      "label": "client789"
    }' \
    -o /tmp/longview.json \
    https://api.linode.com/v4/longview/clients

# Assign install code and API key to variables
LONGVIEW_API_KEY=$(jq -r '.api_key' /tmp/longview.json)
LONGVIEW_INSTALL_CODE=$(jq -r '.install_code' /tmp/longview.json)

# Store API key file
mkdir -p /etc/linode/
echo "$LONGVIEW_API_KEY" | sudo tee /etc/linode/longview.key

# Install Longview agent
apt-get update
apt-get install -y linode-longview

# Start agent and enable start at boot
systemctl start longview
systemctl enable longview
