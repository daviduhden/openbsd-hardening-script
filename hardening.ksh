#!/bin/ksh

##########################################################################
# OpenBSD hardening script
# This script automates various security hardening tasks on an OpenBSD system.
# It includes functions for logging, user prompts, package installation,
# user configuration, firewall setup, Tor configuration, antivirus setup,
# system hardening, and more.
#
# See the LICENSE file at the top of the project tree for copyright
# and license details.
##########################################################################

if [ -t 1 ] && [ "${NO_COLOR:-}" != "1" ]; then
	GREEN="\033[32m"
	YELLOW="\033[33m"
	RED="\033[31m"
	RESET="\033[0m"
else
	GREEN=""
	YELLOW=""
	RED=""
	RESET=""
fi

log() { print "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[INFO]${RESET} ✅ $*"; }
warn() { print "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[WARN]${RESET} ⚠️ $*" >&2; }
error() { print "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[ERROR]${RESET} ❌ $*" >&2; }

# Function to prompt the user for confirmation
confirm() {
	while true; do
		print -n "$1 [y/n]: "
		read -r yn
		case "$yn" in
		[Yy]*) return 0 ;;                     # User confirmed with 'yes'
		[Nn]*) return 1 ;;                     # User declined with 'no'
		*) print "Please answer yes or no." ;; # Invalid input, prompt again
		esac
	done
}

# Function to check for root privileges
check_root() {
	if [ "$(id -u)" -ne 0 ]; then
		error "This script must be run as root."
		exit 1 # Exit if not running as root
	fi
}

# Function to install necessary packages
install_packages() {
	if confirm "Do you want to install necessary packages?"; then
		log "Installing necessary packages..."
		for pkg in anacron tor torsocks clamav; do
			if ! pkg_info -e "$pkg" >/dev/null 2>&1; then
				log "Installing $pkg..."
				pkg_add "$pkg" || {
					error "Error installing $pkg"
					exit 1
				} # Install package or exit on error
			else
				log "$pkg is already installed."
			fi
		done
	fi
}

# Function to configure user settings
configure_user() {
	if confirm "Do you want to configure the user settings?"; then
		USER_TO_CONFIG="user"
		PASSWORD=$(openssl rand -base64 12)                 # Generate a random password
		ENCRYPTED_PASSWORD=$(openssl passwd -1 "$PASSWORD") # Encrypt the password
		useradd -m -s /bin/ksh ${USER_TO_CONFIG}            # Create the user with a home directory and ksh shell
		usermod -p "$ENCRYPTED_PASSWORD" "$USER_TO_CONFIG"  # Set the encrypted password for the user
		log "User 'user' created with password: $PASSWORD"

		# Remove the user from the wheel group if present
		if grep '^wheel:' /etc/group | grep -w -q "${USER_TO_CONFIG}"; then
			log "Removing $USER_TO_CONFIG from the wheel group..."
			sed -i.bak -e "s/\b${USER_TO_CONFIG}\b//g" /etc/group # Remove user from wheel group
		fi

		HOME_DIR="/home/${USER_TO_CONFIG}"
		if [ -d "$HOME_DIR" ]; then
			log "Setting permissions on $HOME_DIR..."
			chown ${USER_TO_CONFIG}:${USER_TO_CONFIG} "$HOME_DIR" # Set ownership
			chmod 700 "$HOME_DIR"                                 # Set permissions
			if [ -f "$HOME_DIR/.profile" ]; then
				if ! grep -Fq "umask 077" "$HOME_DIR/.profile"; then
					log "Adding umask 077 to $HOME_DIR/.profile"
					print "umask 077" >>"$HOME_DIR/.profile" # Set umask in .profile
				fi
			fi
		else
			warn "Home directory for $USER_TO_CONFIG does not exist."
		fi
	fi
}

# Function to configure the firewall
configure_firewall() {
	if confirm "Do you want to configure the firewall?"; then
		log "Configuring PF..."
		PF_CONF="/etc/pf.conf"
		[ -f "$PF_CONF" ] && cp "$PF_CONF" "${PF_CONF}.bak" # Backup existing PF configuration
		cat >"$PF_CONF" <<'EOF'
# Custom PF configuration
# Block all traffic by default
block all

# Allow all outgoing traffic
pass out inet

# Allow incoming ICMP traffic (e.g., ping)
pass in proto icmp

# Allow all traffic on the loopback interface
pass in on lo0
EOF
		pfctl -f "$PF_CONF" # Load new PF configuration
	fi
}

# Function to setup Tor service
setup_tor() {
	if confirm "Do you want to enable and start the Tor service?"; then
		log "Enabling and starting Tor..."
		rcctl enable tor
		rcctl start tor
	fi
}

# Function to configure mirror over Tor
configure_tor_mirror() {
	if confirm "Do you want to configure the system to use an onion (Tor) mirror for updating the system and installing/updating packages?"; then
		log "Configuring /etc/installurl for Tor mirror..."
		INSTALLURL_FILE="/etc/installurl"
		print "http://kdzlr6wcf5d23chfdwvfwuzm6rstbpzzefkpozp7kjeugtpnrixldxqd.onion/pub/OpenBSD/" >"$INSTALLURL_FILE"

		LOGIN_CONF_FILE="/etc/login.conf"
		if ! grep -q "setenv=FETCH_CMD" "$LOGIN_CONF_FILE"; then
			print "default:" >>"$LOGIN_CONF_FILE"
			print "    :setenv=FETCH_CMD=/usr/local/bin/curl -L -s -q -N -x socks5h://127.0.0.1:9050:" >>"$LOGIN_CONF_FILE"
		fi

		log "Rebuilding login.conf database..."
		cap_mkdb /etc/login.conf

		log "Patching sysupgrade and syspatch to use torsocks..."
		for bin in sysupgrade syspatch; do
			if [ -f "/usr/sbin/$bin" ]; then
				sed -i.bak 's,ftp -N,/usr/local/bin/torsocks &,' "/usr/sbin/$bin" 2>/dev/null # Patch binaries to use torsocks
			fi
		done
	fi
}

# Function to disable firmware updates
disable_firmware_updates() {
	if confirm "Do you want to disable firmware updates?"; then
		log "Configuring firmware mirror..."
		if ! grep -q "firmware.openbsd.org" /etc/hosts; then
			log "Adding firmware.openbsd.org entry to /etc/hosts..."
			print "127.0.0.9 firmware.openbsd.org" >>/etc/hosts # Add entry to /etc/hosts
		fi
	fi
}

# Function to disable USB controllers
disable_usb_controllers() {
	if confirm "Do you want to disable USB controllers?"; then
		log "Disabling USB controllers..."
		cat >/etc/bsd.re-config <<'EOF'
disable usb
disable xhci
EOF
	fi
}

# Function to configure ClamAV services
configure_clamd() {
	if confirm "Do you want to configure ClamAV antivirus?"; then
		log "Configuring ClamAV..."
		rcctl enable clamd
		rcctl enable freshclam
		rcctl start clamd
		rcctl start freshclam

		CLAMD_CONF="/etc/clamd.conf"
		FRESHCLAM_CONF="/etc/freshclam.conf"
		if [ -f "$CLAMD_CONF" ]; then
			sed -i.bak '/^Example$/d' "$CLAMD_CONF" # Remove 'Example' line
			log "Removed 'Example' from $CLAMD_CONF"
			sed -i '/^#LocalSocket \/run\/clamav\/clamd.sock/s/^#//' "$CLAMD_CONF" # Uncomment LocalSocket line
			log "Uncommented 'LocalSocket /run/clamav/clamd.sock' in $CLAMD_CONF"
		fi
		if [ -f "$FRESHCLAM_CONF" ]; then
			sed -i.bak '/^Example$/d' "$FRESHCLAM_CONF" # Remove 'Example' line
			log "Removed 'Example' from $FRESHCLAM_CONF"
		fi
	fi
}

# Function to apply system configuration changes for memory allocation hardening
harden_malloc() {
	if confirm "Do you want to apply system configuration changes for memory allocation hardening?"; then
		log "Applying vm.malloc_conf=S..."
		SYSCTL_CONF="/etc/sysctl.conf"
		grep -q "^vm.malloc_conf=S" "$SYSCTL_CONF" 2>/dev/null || print "vm.malloc_conf=S" >>"$SYSCTL_CONF" # Add setting to sysctl.conf
		sysctl vm.malloc_conf=S                                                                             # Apply setting immediately
	fi
}

# Function to configure anacron for periodic tasks
configure_anacron() {
	if confirm "Do you want to configure anacron for periodic tasks?"; then
		log "Configuring anacron..."
		ANACRON_TAB="/etc/anacrontab"
		cat >"$ANACRON_TAB" <<'EOF'
SHELL=/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
MAILTO=""

1  5 daily_maintenance    /bin/sh /etc/daily
7  5 weekly_maintenance   /bin/sh /etc/weekly
30 5 monthly_maintenance  /bin/sh /etc/monthly
EOF

		CRON_TMP=$(mktemp /tmp/cron.XXXXXX) # Securely create a temporary file
		crontab -l >"$CRON_TMP" 2>/dev/null
		if ! grep -q "/usr/local/sbin/anacron -ds" "$CRON_TMP"; then
			print "@reboot /usr/local/sbin/anacron -ds" >>"$CRON_TMP"
			print "0 1 * * * /usr/local/sbin/anacron -ds" >>"$CRON_TMP"
			crontab "$CRON_TMP"
		fi
		rm -f "$CRON_TMP"

		# Create /etc/daily.local and add commands
		DAILY_LOCAL="/etc/daily.local"
		cat >"$DAILY_LOCAL" <<'EOF'
sysupgrade -ns
pkg_add -u
EOF
	fi
}

# Function to make shell environment files immutable
make_shell_files_immutable() {
	if confirm "Do you want to make shell environment files immutable?"; then
		log "Making shell environment files immutable..."
		for file in /etc/profile /etc/csh.cshrc /etc/ksh.kshrc; do
			if [ -f "$file" ]; then
				chflags schg "$file" # Set schg flag to make the file immutable
				log "Set schg flag on $file"
			fi
		done
	fi
}

# Function to configure Xenocara
configure_xenocara() {
	# Configure Xenocara to use CWM instead of FVWM by default
	if confirm "Do you want to configure Xenocara to use CWM instead of FVWM by default?"; then
		log "Configuring Xenocara to use CWM instead of FVWM by default..."
		XSESSION="/etc/X11/xenodm/Xsession"
		if [ -f "$XSESSION" ]; then
			sed -i.bak 's,exec fvwm,exec cwm,' "$XSESSION" # Replace FVWM with CWM
			log "Replaced 'exec fvwm' with 'exec cwm' in $XSESSION"
			rcctl enable xenodm
		fi
	fi

	# Fix screen tearing for Intel-based video chipsets
	if confirm "Do you want to fix screen tearing for Intel-based video chipsets?"; then
		log "Fixing screen tearing for Intel-based video chipsets..."
		mkdir -p /etc/X11/xorg.conf.d
		cat >/etc/X11/xorg.conf.d/intel.conf <<'EOF'
Section "Device"
  Identifier "drm"
  Driver "intel"
  Option "TearFree" "true"
EndSection
EOF
		log "Created /etc/X11/xorg.conf.d/intel.conf with TearFree option enabled."
	fi
}

# Function to prompt for system restart
prompt_restart() {
	log "OpenBSD configuration completed."
	if confirm "Do you want to restart the system now?"; then
		log "Rebooting the system..."
		reboot
	else
		warn "Please remember to reboot the system later to apply all changes."
	fi
}

# Main script execution
main() {
	check_root
	install_packages
	configure_user
	configure_firewall
	setup_tor
	configure_tor_mirror
	disable_firmware_updates
	disable_usb_controllers
	configure_clamd
	harden_malloc
	configure_anacron
	make_shell_files_immutable
	configure_xenocara
	prompt_restart
}

main
