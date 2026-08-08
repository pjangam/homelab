#!/bin/bash
# One-off: create the phone-uploads ZFS dataset, then push the generated
# Samba credentials into Vaultwarden so they can be fetched from the
# Bitwarden mobile app instead of being relayed through chat. Run this
# yourself - the ZFS step needs your sudo password, and the Bitwarden step
# prompts for your own Bitwarden email/master password interactively,
# neither of which ever passes through Claude.
set -euo pipefail

echo "Creating datapool/phone-uploads..."
sudo zfs create datapool/phone-uploads
sudo chown 1000:1000 /datapool/phone-uploads

export PATH="$HOME/.local/bin:$PATH"

# shellcheck disable=SC1091
source .env

bw config server "https://xero.${TAILNET_SUFFIX}"

echo "Logging in - enter your Bitwarden email and master password when prompted."
BW_SESSION=$(bw login --raw)
export BW_SESSION

NAME="Homelab Samba (phone video uploads)"

bw get template item | jq \
  --arg name "$NAME" \
  --arg user "$SAMBA_USER" \
  --arg pass "$SAMBA_PASSWORD" \
  --arg notes "SMB share for uploading videos from iPhone to the homelab ZFS pool (datapool/phone-uploads). Connect via iOS Files app: Connect to Server -> smb://192.168.1.123" \
  '.type=1 | .name=$name | .login.username=$user | .login.password=$pass | .notes=$notes' \
  | bw encode | bw create item

echo "Done - '$NAME' should now be in your vault, syncs to the Bitwarden app on your phone."
