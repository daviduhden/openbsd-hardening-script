#!/bin/ksh
#
# Script to automate configuration from the guides:
#  - OpenBSD workstation hardening
#  - OpenBSD mirror over Tor (Tor mirror only)
#  - Firmware mirror configuration
#  - Using anacron to run periodic tasks
#
# Default user is set to "user".
#
# REQUIREMENT: Must be run as root.
#
# Review and adapt each section according to your environment!

# --- 1. Check for root privileges ---
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# --- 2. Installing necessary packages ---
echo "Installing necessary packages..."
# Install packages: anacron, tor, torsocks, and clamav.
for pkg in anacron tor torsocks clamav; do
  if ! pkg_info "$pkg" >/dev/null 2>&1; then
    echo "Installing $pkg..."
    pkg_add "$pkg" || { echo "Error installing $pkg"; exit 1; }
  else
    echo "$pkg is already installed."
  fi
done

# --- 3. User Configuration ---
# Set the user to configure (default "user")
USER_TO_CONFIG="user"

# 3.1. Remove the user from the wheel group to prevent privilege escalation.
if grep '^wheel:' /etc/group | grep -q "\b${USER_TO_CONFIG}\b"; then
  echo "Removing $USER_TO_CONFIG from the wheel group..."
  cp /etc/group /etc/group.bak
  sed -i '' -e "s/\b${USER_TO_CONFIG}\b//g" /etc/group
fi

# 3.2. Set home directory permissions and add umask 077.
HOME_DIR="/home/${USER_TO_CONFIG}"
if [ -d "$HOME_DIR" ]; then
  echo "Setting permissions on $HOME_DIR..."
  chown ${USER_TO_CONFIG}:${USER_TO_CONFIG} "$HOME_DIR"
  chmod 700 "$HOME_DIR"
  if [ -f "$HOME_DIR/.profile" ]; then
    grep -q "umask 077" "$HOME_DIR/.profile" || echo "umask 077" >> "$HOME_DIR/.profile"
  fi
else
  echo "Home directory for $USER_TO_CONFIG does not exist. Check your configuration."
fi

# --- 4. Firewall Configuration (PF) ---
echo "Configuring PF..."
PF_CONF="/etc/pf.conf"
[ -f "$PF_CONF" ] && cp "$PF_CONF" "${PF_CONF}.bak"
cat > "$PF_CONF" <<'EOF'
# Custom PF configuration for workstation hardening
block all
pass out inet
# Allow ICMP because it's useful
pass in proto icmp
# Block outbound traffic for the default user (change "user" if needed)
block return out proto { tcp udp } user user
EOF
pfctl -f "$PF_CONF"

# --- 5. Tor Service Setup ---
echo "Enabling and starting Tor..."
rcctl enable tor
rcctl start tor

# --- 6. Mirror Configuration over Tor ---
# Configure the system to use a Tor onion mirror for package fetching.
# Set /etc/installurl to the onion mirror URL.
INSTALLURL_FILE="/etc/installurl"
echo "Configuring /etc/installurl for Tor mirror..."
echo "http://kdzlr6wcf5d23chfdwvfwuzm6rstbpzzefkpozp7kjeugtpnrixldxqd.onion/" > "$INSTALLURL_FILE"
# Note: Replace <onion_mirror_address> with your actual Tor mirror onion address.

# Export FETCH_CMD for pkg_* commands to use the Tor proxy.
# Add it to /etc/profile so it persists for all users.
PROFILE_FILE="/etc/profile"
if ! grep -q "FETCH_CMD=" "$PROFILE_FILE"; then
  echo 'export FETCH_CMD="/usr/local/bin/curl -L -s -q -N -x socks5h://127.0.0.1:9050"' >> "$PROFILE_FILE"
fi

# Patch sysupgrade and syspatch to use torsocks.
echo "Patching sysupgrade and syspatch to use torsocks..."
for bin in sysupgrade syspatch; do
  if [ -f "/usr/sbin/$bin" ]; then
    sed -i.bak 's,ftp -N,/usr/local/bin/torsocks &,' "/usr/sbin/$bin" 2>/dev/null
  fi
done

# --- 7. Firmware Mirror Configuration ---
# Prevent fw_update from contacting the official firmware server.
echo "Configuring firmware mirror..."
if ! grep -q "firmware.openbsd.org" /etc/hosts; then
  echo "Adding firmware.openbsd.org entry to /etc/hosts..."
  echo "127.0.0.9 firmware.openbsd.org" >> /etc/hosts
fi

# --- 8. Additional Hardening Measures ---
# 8.1. Live in a Temporary File-System (note only)
echo "Note: To use a temporary file-system for your home, install and configure 'home-impermanence' (not included in this script)."

# 8.2. Disable Webcam and Microphone (reminder)
echo "Reminder: In OpenBSD, webcam and microphone recording are disabled by default."

# 8.3. Disabling USB Ports
echo "Disabling USB controllers..."
cat > /etc/bsd.re-config <<'EOF'
disable usb
disable xhci
EOF

# --- 9. System-wide Services ---
# Configure ClamAV antivirus and freshclam updater.
echo "Configuring ClamAV..."
rcctl enable clamav
rcctl enable freshclam
rcctl start clamav
rcctl start freshclam

# --- 10. System Configuration ---
# Enable extra malloc checks for memory allocation hardening.
echo "Applying vm.malloc_conf=S..."
SYSCTL_CONF="/etc/sysctl.conf"
grep -q "^vm.malloc_conf=S" "$SYSCTL_CONF" 2>/dev/null || echo "vm.malloc_conf=S" >> "$SYSCTL_CONF"
sysctl vm.malloc_conf=S

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

# Add anacron entries to root's crontab to run at boot and daily.
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
#    Installs anacron, tor, torsocks, and clamav if not already installed.
#
# 2. User Configuration:
#    - Uses the default user "user".
#    - Removes "user" from the wheel group to prevent privilege escalation.
#    - Sets the home directory permissions to 700 and appends "umask 077" to .profile.
#
# 3. Firewall (PF):
#    - Configures PF to block all incoming traffic except ICMP and blocks outbound traffic
#      for the default user "user".
#
# 4. Tor Service Setup:
#    - Enables and starts the Tor service.
#
# 5. Mirror Configuration over Tor:
#    - Sets /etc/installurl to the Tor onion mirror (replace placeholder with the actual address).
#    - Exports FETCH_CMD for pkg_* commands to use curl with a Tor SOCKS5 proxy.
#    - Patches sysupgrade and syspatch to invoke torsocks.
#
# 6. Firmware Mirror Configuration:
#    - Adds an entry to /etc/hosts to neutralize firmware.openbsd.org DNS lookup.
#
# 7. Additional Hardening Measures:
#    - Reminds about using a temporary home filesystem.
#    - Notes that webcam/microphone are disabled by default.
#    - Disables USB controllers.
#
# 8. System-wide Services:
#    - Enables and starts ClamAV and its updater.
#
# 9. System Configuration:
#    - Applies memory allocation hardening by setting vm.malloc_conf=S.
#
# 10. Anacron Configuration:
#     - Sets up /etc/anacrontab with daily, weekly, and monthly tasks.
#     - Adds entries to root's crontab to run anacron at boot and daily.
#########################################################################
