#!/usr/bin/env bash
set -euo pipefail

sudo apt install -y openssh-server
sudo systemctl enable --now ssh

# Point git at the repo's tracked hooks (.githooks/) instead of the
# untracked, per-clone-only .git/hooks/ default - pre-commit scans staged
# changes for PII/public-IP/Tailscale-hostname/card-number leaks, pre-push
# runs gitleaks for credential leaks. Local git config, so this must be set
# on every clone/machine.
git config core.hooksPath .githooks

sudo apt install -y net-tools copyq gnupg rclone fzf zsh thefuck gh

# Extend unattended-upgrades (already running twice daily via
# apt-daily.timer/apt-daily-upgrade.timer) to also cover the Docker and
# Tailscale apt repos, which aren't in Ubuntu's own archive and so aren't
# touched by unattended-upgrades' default Allowed-Origins. Adds a new
# apt.conf.d fragment rather than editing the shipped 50unattended-upgrades
# file, since apt.conf list options append across fragments (read in
# filename order) - no need to touch/merge the maintainer-owned conffile.
#
# Tradeoff worth knowing: Docker's apt repo has one rolling "stable" suite
# with no separation between minor and major versions, so this will also
# auto-install a future Docker CE major-version bump with no manual review.
# A docker-ce upgrade restarts the Docker daemon (briefly restarts every
# container) whenever apt-daily-upgrade.timer next fires (currently ~06:50
# and ~19:00 IST) if a new version is available that day.
sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-thirdparty > /dev/null <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "Docker:noble";
    "Tailscale:noble";
};
EOF

# Install oh-my-zsh
if [[ ! -d ~/.oh-my-zsh ]]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Clone plugins into oh-my-zsh custom plugins dir
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# Configure .zshrc — set theme and plugins
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' ~/.zshrc
sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc

# Add fzf and thefuck if not already there
if ! grep -q "thefuck" ~/.zshrc; then
  printf '\neval "$(fzf --zsh)"\neval "$(thefuck --alias)"\n' >> ~/.zshrc
fi

# Set zsh as default shell
if [[ "$SHELL" != "$(which zsh)" ]]; then
  chsh -s "$(which zsh)" "$USER"
fi

# Autostart CopyQ on login
mkdir -p ~/.config/autostart
cp /usr/share/applications/com.github.hluk.copyq.desktop ~/.config/autostart/

# Schedule daily Vaultwarden backup at 2 AM
HOMELAB_DIR="$(cd "$(dirname "$0")" && pwd)"

# Tailnet suffix (e.g. tailXXXXX.ts.net) - kept out of tracked files, lives in .env
ENV_FILE="$HOMELAB_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi
if [[ -z "${TAILNET_SUFFIX:-}" ]]; then
  read -r -p "Tailscale tailnet domain suffix (e.g. tailXXXXX.ts.net): " TAILNET_SUFFIX
  echo "TAILNET_SUFFIX=$TAILNET_SUFFIX" >> "$ENV_FILE"
fi

# Samba credentials for the phone-uploads share (docker-compose reads these
# directly) - generate once and persist, same pattern as TAILNET_SUFFIX above
if [[ -z "${SAMBA_USER:-}" ]]; then
  SAMBA_USER="phoneupload"
  echo "SAMBA_USER=$SAMBA_USER" >> "$ENV_FILE"
fi
if [[ -z "${SAMBA_PASSWORD:-}" ]]; then
  SAMBA_PASSWORD=$(openssl rand -base64 20 | tr -dc 'A-Za-z0-9' | head -c20)
  echo "SAMBA_PASSWORD=$SAMBA_PASSWORD" >> "$ENV_FILE"
fi

(crontab -l 2>/dev/null | grep -v "backup_vaultwarden.sh"; echo "0 2 * * * $HOMELAB_DIR/cron/backup_vaultwarden.sh >> $HOMELAB_DIR/backup.log 2>&1") | crontab -
(crontab -l 2>/dev/null | grep -v "backup_homeassistant.sh"; echo "0 3 * * * $HOMELAB_DIR/cron/backup_homeassistant.sh >> $HOMELAB_DIR/backup.log 2>&1") | crontab -
# Renew Tailscale certs weekly, via cron/renew_certs.sh.
#
# This used to be a long inline entry running `sudo tailscale cert ... && sudo
# docker kill --signal=USR1 caddy`. That entry failed silently for three months
# (sudo has no NOPASSWD for tailscale and cron has no TTY), and its caddy reload
# also marked the container manually-stopped so it never came back after a
# reboot. Both are written up in incidents/ (2026-09-04 and 2026-09-06). The
# live crontab was replaced on 2026-09-04; this line was stale until 2026-09-06,
# meaning a freshly provisioned machine would have reintroduced both bugs.
#
# Weekly, not monthly: a monthly job that fails has no retry before a 90-day
# cert lapses. 5am not 4am to avoid racing watchtower, which restarts containers
# on Sundays at 4.
#
# Prerequisite: the tailscale operator must be set to $USER so renew_certs.sh
# can run unprivileged from cron - without it, renewal fails on every run. That
# is handled automatically further down, in the Tailscale section.
(crontab -l 2>/dev/null | grep -vE "tailscale cert|renew_certs.sh"; echo "0 5 * * 0 $HOMELAB_DIR/cron/renew_certs.sh") | crontab -

# Let pramod run ONLY `shutdown` without a password, so watchdog_power.sh
# can act unattended from cron. Scoped to that single command - no broader
# sudo access granted.
SUDOERS_RULE='pramod ALL=(root) NOPASSWD: /usr/sbin/shutdown -h now'
SUDOERS_FILE=/etc/sudoers.d/power-watchdog
echo "$SUDOERS_RULE" | sudo tee "$SUDOERS_FILE" > /dev/null
sudo chmod 440 "$SUDOERS_FILE"
sudo visudo -cf "$SUDOERS_FILE" && echo "OK: power-watchdog sudoers rule installed and syntax-checked"

git config --global user.email "pjangam2015@gmail.com"
git config --global user.name "Pramod"

# Install Tailscale
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
sudo systemctl enable --now tailscaled
echo "ACTION REQUIRED: run 'sudo tailscale up' to authenticate this machine with Tailscale"

# Generate Tailscale cert for Caddy (requires tailscale to be authenticated first)
mkdir -p "$HOMELAB_DIR/certs"
TAILSCALE_TIMEOUT=120
TAILSCALE_ELAPSED=0
echo "Waiting for Tailscale authentication (timeout: ${TAILSCALE_TIMEOUT}s)..."
echo "Run 'sudo tailscale up' in another terminal to authenticate."
until tailscale status &>/dev/null; do
  if [[ $TAILSCALE_ELAPSED -ge $TAILSCALE_TIMEOUT ]]; then
    echo "[$(date)] TIMED OUT waiting for Tailscale auth — skipping cert generation. Re-run script after 'sudo tailscale up'."
    break
  fi
  sleep 5
  TAILSCALE_ELAPSED=$((TAILSCALE_ELAPSED + 5))
done
if tailscale status &>/dev/null; then
  # Let $USER drive tailscale without sudo. This is what makes the weekly
  # cron/renew_certs.sh job work: cron has no TTY, so a `sudo tailscale cert`
  # in there fails instantly and silently - which is exactly how renewal went
  # unnoticed for three months (see incidents/2026-09-04-tls-cert-renewal-
  # silently-broken.md). Idempotent, so re-running this script is harmless.
  sudo tailscale set --operator="$USER"
  # Read the setting back rather than trusting the exit code. If the operator
  # didn't actually take, renewal would fail the same silent way it did before,
  # and shipping that again is the one outcome this block exists to prevent.
  ts_operator=$(tailscale debug prefs 2>/dev/null |
    python3 -c "import json,sys; print(json.load(sys.stdin).get('OperatorUser') or '')" 2>/dev/null || true)
  if [ "$ts_operator" = "$USER" ]; then
    echo "OK: tailscale operator is $USER - cron/renew_certs.sh can run unprivileged"
  else
    echo "WARNING: tailscale operator is '${ts_operator:-unset}', expected '$USER' - cron/renew_certs.sh will fail silently every week. Fix with: sudo tailscale set --operator=$USER"
  fi

  # Unprivileged now that the operator is set - no sudo, and so no chown to
  # undo root ownership afterwards.
  tailscale cert \
    --cert-file "$HOMELAB_DIR/certs/xero.$TAILNET_SUFFIX.crt" \
    --key-file  "$HOMELAB_DIR/certs/xero.$TAILNET_SUFFIX.key" \
    "xero.$TAILNET_SUFFIX"
fi

# Free port 53 for Pi-hole. systemd-resolved squats on it and Pi-hole can't
# bind until it's gone, so this part is load-bearing.
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved

# Deliberately NOT writing /etc/resolv.conf here.
#
# This used to do `rm /etc/resolv.conf` followed by a hand-written
# `nameserver 127.0.0.1 / nameserver 1.1.1.1`, to point the machine at its own
# Pi-hole. That line never survived: tailscale runs with --accept-dns on by
# default, owns /etc/resolv.conf, and rewrites it to the MagicDNS resolver
# (100.100.100.100) - and it runs *before* this point in the script, so the
# hand-written file was overwritten at the next tailscale reconfigure. It had
# been dead on xero for a long time before anyone noticed (2026-09-06).
#
# What actually routes this machine's own queries into Pi-hole is a setting
# this script cannot make, because it lives in the Tailscale admin console:
#   Tailscale admin -> DNS -> Nameservers -> this host's 100.x address
# With that set, the chain is
#   host -> MagicDNS (100.100.100.100) -> this host:53 -> Pi-hole -> upstream
# so MagicDNS keeps working *and* Pi-hole's blocklist still applies. Verified
# on xero by sending a uniquely-named query to 100.100.100.100 and finding it
# in Pi-hole's log arriving from the host's own tailscale address.
#
# LAN clients are unaffected by any of this - they get Pi-hole's LAN address
# from the router's DHCP, not from this file.
#
# The old `1.1.1.1` fallback is intentionally not reinstated either: it would
# mean that with Pi-hole down the machine silently resolves unfiltered through
# Cloudflare rather than failing visibly.
#
# check_dns_reaches_pihole() below verifies all of this once Pi-hole is up.

# Install ZFS userspace tools (no DKMS — use pre-built kernel module)
if ! command -v zfs &>/dev/null; then
  sudo apt install -y zfsutils-linux
fi
sudo zpool import -a 2>/dev/null || true

# Create the phone-uploads ZFS dataset, then push the generated Samba
# credentials into Vaultwarden so they can be fetched from the Bitwarden
# mobile app instead of being relayed through chat. The ZFS step needs
# sudo; the Bitwarden step prompts for your own Bitwarden email/master
# password interactively, neither of which ever passes through Claude.
if ! zfs list datapool/phone-uploads &>/dev/null; then
  echo "Creating datapool/phone-uploads..."
  sudo zfs create datapool/phone-uploads
  sudo chown 1000:1000 /datapool/phone-uploads
fi

export PATH="$HOME/.local/bin:$PATH"
bw config server "https://xero.${TAILNET_SUFFIX}"
echo "Logging in to Bitwarden - enter your email and master password when prompted."
BW_SESSION=$(bw login --raw)
export BW_SESSION
SAMBA_BW_NAME="Homelab Samba (phone video uploads)"
bw get template item | jq \
  --arg name "$SAMBA_BW_NAME" \
  --arg user "$SAMBA_USER" \
  --arg pass "$SAMBA_PASSWORD" \
  --arg notes "SMB share for uploading videos from iPhone to the homelab ZFS pool (datapool/phone-uploads). Connect via iOS Files app: Connect to Server -> smb://192.168.1.123" \
  '.type=1 | .name=$name | .login.username=$user | .login.password=$pass | .notes=$notes' \
  | bw encode | bw create item
echo "Done - '$SAMBA_BW_NAME' should now be in your vault, syncs to the Bitwarden app on your phone."

# Allow running docker without sudo
sudo usermod -aG docker "$USER"

# Start services
cd "$(dirname "$0")"
sudo docker compose up -d

# Verify DNS actually ends up at Pi-hole, rather than assuming it does. The
# resolv.conf note further up explains why this can't be asserted from config
# alone: the path runs through MagicDNS and depends on a Tailscale admin-console
# setting this script can't make. Warnings only - a fresh machine may legitimately
# not have that setting yet, and this shouldn't abort provisioning.
check_dns_reaches_pihole() {
  local marker blocked waited=0
  echo "Verifying DNS..."

  # Pi-hole needs to be answering before any of this means anything.
  until sudo docker exec pihole true 2>/dev/null && getent hosts github.com >/dev/null 2>&1; do
    if [ "$waited" -ge 60 ]; then
      echo "WARNING: Pi-hole not resolving after 60s - skipping DNS verification. Check: docker logs pihole"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  echo "OK: name resolution works ($(getent hosts github.com | awk '{print $1}' | head -1) for github.com)"

  # Does *this host's* traffic actually traverse Pi-hole? A uniquely-named
  # query through the system resolver must show up in Pi-hole's own log. This
  # is the check that config inspection can't replace - resolution succeeding
  # proves nothing about which resolver did the work.
  marker="setup-check-$(date +%s).example.com"
  getent hosts "$marker" >/dev/null 2>&1 || true   # expected not to resolve
  sleep 2
  if sudo docker exec pihole grep -q "$marker" /var/log/pihole/pihole.log 2>/dev/null; then
    echo "OK: this host's queries reach Pi-hole"
  else
    echo "WARNING: this host's queries are NOT reaching Pi-hole - it is resolving somewhere else."
    echo "         Set the tailnet nameserver to this host: Tailscale admin -> DNS -> Nameservers -> $(tailscale ip -4 2>/dev/null || echo '<this host 100.x address>')"
  fi

  # And is the blocklist actually applied? A Pi-hole that resolves everything
  # but blocks nothing looks perfectly healthy to a plain lookup.
  blocked=$(getent hosts doubleclick.net 2>/dev/null | awk '{print $1}' | head -1)
  case "$blocked" in
    ""|"0.0.0.0"|"::") echo "OK: blocklist is active (doubleclick.net -> ${blocked:-NXDOMAIN})" ;;
    *) echo "WARNING: blocklist does not appear active - doubleclick.net resolved to $blocked. Check gravity: docker exec pihole pihole -g" ;;
  esac
}
check_dns_reaches_pihole

# Install HACS if not already installed
if [[ ! -d "$HOMELAB_DIR/HOMEASSISTANT_CONFIG/custom_components/hacs" ]]; then
  sudo docker exec homeassistant bash -c "wget -O - https://get.hacs.xyz | bash -"
fi

# Set static IP (last — drops network connection)
if ! ip addr show enp1s0 | grep -q "192.168.1.123"; then
  sudo nmcli con mod "Wired connection 1" \
    ipv4.method manual \
    ipv4.addresses 192.168.1.123/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "8.8.8.8 1.1.1.1"
  sudo nmcli con up "Wired connection 1"
else
  echo "Static IP already set, skipping."
fi

# WiFi failover for Pi-hole. Context: Pi-hole runs on this box with a static
# IP (192.168.1.123) on the wired interface, and the router's LAN DNS
# setting points at that IP. The server reaches the LAN via an ethernet
# cable into a WiFi range extender that is NOT on the UPS. On a power
# outage the extender drops, enp1s0 loses carrier, and 192.168.1.123
# disappears from the network entirely - the whole LAN loses DNS even
# though the router and this server are both still up on UPS power.
# Fix: fail over to a direct WiFi connection to the router's own radio
# (dlink_pramod), using the SAME static IP, so the router's DNS setting
# never needs to change. A NetworkManager dispatcher script brings the
# WiFi connection up when the wired interface loses carrier, and back
# down once wired returns, so only one interface ever holds the address
# at a time. Prompts for the WiFi password (not stored anywhere).
WIFI_IFACE="wlp2s0"
WIFI_SSID="dlink_pramod"
WIFI_CON_NAME="dlink_pramod-failover"
WIFI_DISPATCHER_SCRIPT="/etc/NetworkManager/dispatcher.d/99-wifi-failover"
if ! nmcli -t -f NAME con show | grep -qx "$WIFI_CON_NAME"; then
  read -r -s -p "WiFi password for $WIFI_SSID (failover profile): " WIFI_PSK
  echo
  echo "Creating WiFi failover connection profile ($WIFI_CON_NAME)..."
  sudo nmcli con add type wifi ifname "$WIFI_IFACE" con-name "$WIFI_CON_NAME" ssid "$WIFI_SSID" \
    wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WIFI_PSK" \
    ipv4.method manual ipv4.addresses "192.168.1.123/24" ipv4.gateway "192.168.1.1" ipv4.dns "8.8.8.8,1.1.1.1" \
    connection.autoconnect no
  unset WIFI_PSK

  echo "Installing dispatcher script ($WIFI_DISPATCHER_SCRIPT)..."
  sudo tee "$WIFI_DISPATCHER_SCRIPT" > /dev/null << SCRIPT
#!/bin/bash
# Bring up the WiFi failover connection when enp1s0 loses carrier; drop it
# again once enp1s0 is back, so only one interface ever holds the static
# IP at a time.
[ "\$1" = "enp1s0" ] || exit 0

case "\$2" in
  down|unavailable)
    logger -t wifi-failover "enp1s0 \$2 - bringing up $WIFI_CON_NAME"
    nmcli con up "$WIFI_CON_NAME" >/dev/null 2>&1
    ;;
  up)
    logger -t wifi-failover "enp1s0 up - bringing down $WIFI_CON_NAME"
    nmcli con down "$WIFI_CON_NAME" >/dev/null 2>&1
    ;;
esac
exit 0
SCRIPT
  sudo chmod 755 "$WIFI_DISPATCHER_SCRIPT"
  echo "WiFi failover installed. Real test: pull power on the range extender (or"
  echo "unplug the ethernet cable) and confirm the LAN stays resolvable, then"
  echo "restore and confirm it fails back to wired."
else
  echo "WiFi failover profile already exists, skipping."
fi

# =============================================================================
# Machine-specific config: Beelink Mini PC, Intel N5105, Lubuntu
# See Readme.md for details on why these fixes are needed.
# =============================================================================
if grep -q "N5105" /proc/cpuinfo; then

  # Intel N5105 Jasper Lake — deep C-states cause hard system freezes on Linux
  if ! grep -q "intel_idle.max_cstate=1" /etc/default/grub; then
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 intel_idle.max_cstate=1"/' /etc/default/grub
    sudo update-grub
  fi

  # 512MB default swap is too low for Docker workloads
  if [[ ! -f /swapfile ]]; then
    sudo swapoff -a
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  fi

  # Logitech USB receiver drops on USB auto-suspend — disable it
  if [[ ! -f /etc/udev/rules.d/50-usb-autosuspend.rules ]]; then
    echo 'ACTION=="add", SUBSYSTEM=="usb", TEST=="power/autosuspend" ATTR{power/autosuspend}="-1"' | \
      sudo tee /etc/udev/rules.d/50-usb-autosuspend.rules
    sudo udevadm control --reload-rules
  fi

  # HDMI hot-plug detection on i915 Jasper Lake doesn't work by default -
  # the display doesn't show up when HDMI is connected after boot. Installs
  # a udev rule + helper script to auto-enable the display via xrandr.
  if [[ ! -f /etc/udev/rules.d/95-hdmi-hotplug.rules ]]; then
    echo "Installing HDMI hot-plug helper script..."
    sudo tee /usr/local/bin/hdmi-hotplug.sh > /dev/null << 'SCRIPT'
#!/bin/bash
# Triggered by udev when HDMI state changes.
# Runs xrandr as the logged-in user to enable the newly connected display.

sleep 2

USER_SESSION=$(loginctl list-sessions --no-legend | awk '{print $1}' | head -1)
if [ -z "$USER_SESSION" ]; then
    exit 0
fi

SESSION_USER=$(loginctl show-session "$USER_SESSION" -p Name --value)
DISPLAY_VAL=$(loginctl show-session "$USER_SESSION" -p Display --value)
XAUTHORITY_VAL="/home/$SESSION_USER/.Xauthority"

if [ -z "$DISPLAY_VAL" ]; then
    DISPLAY_VAL=":0"
fi

export DISPLAY="$DISPLAY_VAL"
export XAUTHORITY="$XAUTHORITY_VAL"

for connector in /sys/class/drm/card*-HDMI-A-*/status; do
    if [ "$(cat "$connector")" = "connected" ]; then
        output=$(basename "$(dirname "$connector")" | sed 's/card[0-9]*-//' | sed 's/-A-/-/')
        su - "$SESSION_USER" -c "DISPLAY=$DISPLAY_VAL XAUTHORITY=$XAUTHORITY_VAL xrandr --output $output --auto" 2>/dev/null
    fi
done
SCRIPT
    sudo chmod +x /usr/local/bin/hdmi-hotplug.sh

    echo "Installing udev rule..."
    echo 'ACTION=="change", SUBSYSTEM=="drm", RUN+="/usr/local/bin/hdmi-hotplug.sh"' | \
      sudo tee /etc/udev/rules.d/95-hdmi-hotplug.rules > /dev/null
    sudo udevadm control --reload-rules
    echo "HDMI hot-plug should now auto-detect when you plug in the cable."
  fi

  # Console font on TTY1: the video mode negotiated at boot varies (e.g.
  # depending on whether a monitor is attached), so a font baked in from
  # one successful run can start failing on a later boot with a different
  # console geometry, crash-looping getty entirely. Try largest-to-smallest
  # at every getty start instead of hardcoding one font.
  if [[ ! -f /etc/systemd/system/getty@.service.d/powerline-font.conf ]]; then
    CONSOLE_FONTS="ter-powerline-v24b ter-powerline-v22b ter-powerline-v20b ter-powerline-v18b ter-powerline-v16b"
    CONSOLE_FONT_CHOSEN=""
    for FONT in $CONSOLE_FONTS; do
      FONT_FILE="/usr/share/consolefonts/${FONT}.psf.gz"
      if [ ! -f "$FONT_FILE" ]; then
        echo "Downloading ${FONT}..."
        curl -sL "https://raw.githubusercontent.com/powerline/fonts/master/Terminus/PSF/${FONT}.psf.gz" \
          -o /tmp/${FONT}.psf.gz
        sudo cp /tmp/${FONT}.psf.gz /usr/share/consolefonts/
      fi
      if sudo setfont "$FONT_FILE" 2>/dev/null; then
        CONSOLE_FONT_CHOSEN="$FONT"
        echo "Loaded: $FONT"
        break
      fi
    done

    if [ -n "$CONSOLE_FONT_CHOSEN" ]; then
      grep -q '^FONT=' /etc/default/console-setup \
        && sudo sed -i "s/^FONT=.*/FONT=\"${CONSOLE_FONT_CHOSEN}.psf.gz\"/" /etc/default/console-setup \
        || echo "FONT=\"${CONSOLE_FONT_CHOSEN}.psf.gz\"" | sudo tee -a /etc/default/console-setup

      # getty drop-in runs setfont before each TTY login prompt (more
      # reliable than console-setup.service which runs before framebuffer
      # is ready); the trailing `; true` guarantees getty always starts
      # even if no font fits.
      sudo mkdir -p /etc/systemd/system/getty@.service.d
      sudo tee /etc/systemd/system/getty@.service.d/powerline-font.conf > /dev/null <<EOF
[Service]
ExecStartPre=/bin/sh -c 'for f in ${CONSOLE_FONTS}; do setfont /usr/share/consolefonts/\${f}.psf.gz 2>/dev/null && break; done; true'
EOF
      sudo systemctl daemon-reload
      echo "Console font will persist via getty drop-in on next boot."
    else
      echo "WARNING: no compatible console font found - skipping persistence."
    fi
  fi

fi
