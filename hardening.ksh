#!/bin/ksh
#
# Script to automate the configuration from the guides:
#  - OpenBSD workstation hardening
#  - OpenBSD mirror configuration over I2P (only)
#  - Using anacron to run periodic tasks
#
# REQUIREMENT: Must be run as root.
#
# Read and adapt each section according to your environment!

# --- Check for root privileges ---
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# --- Installing necessary packages ---
echo "Installing necessary packages..."
for pkg in anacron i2pd clamav; do
  if ! pkg_info "$pkg" >/dev/null 2>&1; then
    echo "Installing $pkg..."
    pkg_add "$pkg" || { echo "Error installing $pkg"; exit 1; }
  else
    echo "$pkg is already installed."
  fi
done

# --- 2. User Configuration ---
# Configure the "normal" user as described in the guides.
# It is assumed that the user to configure is $USER_TO_CONFIG (default "solene")
USER_TO_CONFIG=${USER:-solene}

# 2.1. Remove the user from the wheel group to prevent privilege escalation.
if grep '^wheel:' /etc/group | grep -q "\b${USER_TO_CONFIG}\b"; then
  echo "Removing $USER_TO_CONFIG from the wheel group..."
  cp /etc/group /etc/group.bak
  sed -i '' -e "s/\b${USER_TO_CONFIG}\b//g" /etc/group
fi

# 2.3. Set home directory permissions and configure umask.
HOME_DIR="/home/${USER_TO_CONFIG}"
if [ -d "$HOME_DIR" ]; then
  echo "Setting permissions on $HOME_DIR..."
  chown ${USER_TO_CONFIG}:${USER_TO_CONFIG} "$HOME_DIR"
  chmod 700 "$HOME_DIR"
  # Add umask 077 to .profile if not already present.
  if [ -f "$HOME_DIR/.profile" ]; then
    grep -q "umask 077" "$HOME_DIR/.profile" || echo "umask 077" >> "$HOME_DIR/.profile"
  fi
else
  echo "Home directory for $USER_TO_CONFIG does not exist. Check your configuration."
fi

# --- 3. Firewall Configuration (PF) ---
echo "Configuring PF..."
PF_CONF="/etc/pf.conf"
[ -f "$PF_CONF" ] && cp "$PF_CONF" "${PF_CONF}.bak"
cat > "$PF_CONF" <<'EOF'
# Custom PF configuration for hardening (as in the guide)
block all
pass out inet
# Allow ICMP because it's useful
pass in proto icmp
# Block outbound traffic for user "solene" (adjust if necessary)
block return out proto { tcp udp } user solene
EOF
pfctl -f "$PF_CONF"

# --- 4. Disabling Network for Desktop User ---
# Create a dedicated proxy user (_proxy) if needed. (Not used for I2P mirror,
# but provided per the guide for controlling networking on the desktop.)
if ! id _proxy >/dev/null 2>&1; then
  echo "Creating _proxy user..."
  useradd -s /sbin/nologin -m _proxy
  # IMPORTANT: Manually add your SSH key to /home/_proxy/.ssh/authorized_keys
fi

# SSH configuration to force proxy usage via ProxyJump.
SSH_CONFIG="${HOME_DIR}/.ssh/config"
mkdir -p "${HOME_DIR}/.ssh"
chown ${USER_TO_CONFIG}:${USER_TO_CONFIG} "${HOME_DIR}/.ssh"
chmod 700 "${HOME_DIR}/.ssh"
if [ ! -f "$SSH_CONFIG" ]; then
  echo "Creating SSH configuration for proxy..."
  cat > "$SSH_CONFIG" <<'EOF'
Host localhost
  User _proxy
  ControlMaster auto
  ControlPath ~/.ssh/%h%p%r.sock
  ControlPersist 60

Host *.*
  ProxyJump localhost
EOF
  chown ${USER_TO_CONFIG}:${USER_TO_CONFIG} "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
fi

# Note:
# For Chromium, if GNOME proxy settings are not configured, launch it with:
#   --proxy-server=socks5://localhost:10000
#
# For Syncthing, set the environment variable:
#   all_proxy=socks5://localhost:10000
# in its startup environment.

# --- 5. Live in a Temporary File-System ---
echo "Note: To use a temporary file-system for your home, install and configure 'home-impermanence' (not included in this script)."

# --- 6. Disable Webcam and Microphone ---
echo "Reminder: In OpenBSD, webcam and microphone recording are disabled by default."

# --- 7. Disabling USB Ports ---
echo "Disabling USB controllers..."
cat > /etc/bsd.re-config <<'EOF'
disable usb
disable xhci
EOF

# --- 8. System-wide Services ---
# 8.1. Configure ClamAV antivirus and freshclam updater.
echo "Configuring ClamAV..."
rcctl enable clamav
rcctl enable freshclam
rcctl start clamav
rcctl start freshclam

# 8.2. Auto-update of packages and base system will be handled via anacron (see below).

# --- 9. System Configuration ---
# 9.1. Enable extra malloc checks for memory allocation hardening.
echo "Applying vm.malloc_conf=S..."
SYSCTL_CONF="/etc/sysctl.conf"
grep -q "^vm.malloc_conf=S" "$SYSCTL_CONF" 2>/dev/null || echo "vm.malloc_conf=S" >> "$SYSCTL_CONF"
sysctl vm.malloc_conf=S

# --- 10. Mirror Configuration over I2P (Only) ---
# I2P configuration for accessing the OpenBSD mirror.
echo "Configuring I2P mirror..."
I2PD_CONF="/etc/i2pd/i2pd.conf"
if [ -f "$I2PD_CONF" ]; then
  if ! grep -q "^notransit" "$I2PD_CONF"; then
    echo "notransit = true" >> "$I2PD_CONF"
  else
    sed -i.bak 's/^notransit.*/notransit = true/' "$I2PD_CONF"
  fi
else
  echo "notransit = true" > "$I2PD_CONF"
fi

cat > /etc/i2pd/tunnels.conf <<'EOF'
[MIRROR]
type = client
address = 127.0.0.1
port = 8080
destination = 2st32tfsqjnvnmnmy3e5o5y5hphtgt4b2letuebyv75ohn2w5umq.b32.i2p
destinationport = 8081
keys = mirror.dat
EOF

rcctl enable i2pd
rcctl restart i2pd

# For firmware: Prevent fw_update from contacting the official firmware server.
if ! grep -q "firmware.openbsd.org" /etc/hosts; then
  echo "Adding firmware.openbsd.org entry to /etc/hosts..."
  echo "127.0.0.9 firmware.openbsd.org" >> /etc/hosts
fi

# --- 11. Anacron Configuration for Periodic Tasks ---
echo "Configuring anacron..."
ANACRON_TAB="/etc/anacrontab"
cat > "$ANACRON_TAB" <<'EOF'
SHELL=/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
MAILTO=""

1  5 daily_maintenance    /bin/sh /etc/daily
7  5 weekly_maintenance   /bin/sh /etc/weekly
30 5 monthly_maintenance  /bin/sh /etc/monthly
EOF

# Add entries to root's crontab to run anacron at boot and daily.
CRON_TMP="/tmp/cron.$$"
crontab -l > "$CRON_TMP" 2>/dev/null
if ! grep -q "/usr/local/sbin/anacron -ds" "$CRON_TMP"; then
  echo "@reboot /usr/local/sbin/anacron -ds" >> "$CRON_TMP"
  echo "0 1 * * * /usr/local/sbin/anacron -ds" >> "$CRON_TMP"
  crontab "$CRON_TMP"
fi
rm -f "$CRON_TMP"

echo "OpenBSD configuration completed."

#########################################################################
# Explanation of Main Sections:
#
# 1. Package Installation:
#    Installs anacron, i2pd, and clamav if they are not already installed.
#
# 2. User Configuration:
#    - Removes the specified user (default "solene") from the wheel group to prevent privilege escalation.
#    - Sets the user's home directory permissions to 700 and appends "umask 077" to .profile.
#
# 3. Firewall (PF):
#    - Replaces the default PF configuration with one that blocks all incoming traffic except ICMP,
#      allows outbound traffic, and blocks outbound traffic for the specified user.
#
# 4. Disabling Network for Desktop User:
#    - Creates a _proxy user and sets up SSH configuration (in the user's .ssh/config) to force
#      the use of a proxy via ProxyJump. (This is kept per the guide although the I2P mirror is used.)
#
# 5. Temporary File-System:
#    - Reminds you to install and configure "home-impermanence" if you want a temporary home.
#
# 6. Webcam and Microphone:
#    - Reminds you that these devices are disabled by default in OpenBSD.
#
# 7. Disabling USB Ports:
#    - Disables USB controllers by writing /etc/bsd.re-config.
#
# 8. System-wide Services:
#    - Enables and starts ClamAV and freshclam.
#
# 9. System Configuration:
#    - Applies memory allocation hardening by setting vm.malloc_conf=S.
#
# 10. Mirror Configuration over I2P:
#     - Configures I2P tunnels for accessing the OpenBSD mirror.
#     - Prevents fw_update from connecting to the official firmware server.
#
# 11. Anacron Configuration:
#     - Sets up /etc/anacrontab with daily, weekly, and monthly tasks.
#     - Adds entries to root's crontab to run anacron at boot and daily.
#########################################################################
