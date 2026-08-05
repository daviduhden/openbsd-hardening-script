#!/bin/ksh

# Interactive, conservative hardening helpers for OpenBSD workstations.
# See LICENSE for copyright and licence details.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export PATH
umask 077

if [ -t 1 ] && [ "${NO_COLOR:-}" != 1 ]; then
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

log() { print "${GREEN}[INFO]${RESET} $*"; }
warn() { print "${YELLOW}[WARN]${RESET} $*" >&2; }
error() { print "${RED}[ERROR]${RESET} $*" >&2; }

REBOOT_NEEDED=0
BACKUP_PATH=""

confirm() {
	print "$1 [y/N]: \c"
	read -r answer
	case "$answer" in
	[yY] | [yY][eE][sS]) return 0 ;;
	*) return 1 ;;
	esac
}

check_root() {
	if [ "$(id -u)" -ne 0 ]; then
		error "This script must be run as root."
		exit 1
	fi
}

backup_file() {
	typeset file=$1
	BACKUP_PATH=""
	[ -f "$file" ] || return 0
	BACKUP_PATH=$(mktemp "${file}.hardening.XXXXXX") || return 1
	if ! cp -p "$file" "$BACKUP_PATH"; then
		rm -f "$BACKUP_PATH"
		BACKUP_PATH=""
		return 1
	fi
	log "Backup: $BACKUP_PATH"
}

ensure_package() {
	typeset package=$1
	if pkg_info -e "$package" >/dev/null 2>&1; then
		return 0
	fi
	log "Installing package $package..."
	pkg_add "$package" || {
		error "Could not install $package."
		return 1
	}
}

configure_firewall() {
	confirm "Install a default-deny PF ruleset for an outbound-only workstation?" || return
	warn "This replaces /etc/pf.conf. Servers, bridges, VPNs and custom anchors need tailored rules."
	confirm "Replace the current PF policy after syntax validation?" || return

	pf_tmp=$(mktemp /tmp/pf.conf.XXXXXX) || exit 1
	cat >"$pf_tmp" <<'EOF'
# Workstation baseline installed by hardening.ksh
set skip on lo
block return

# Outbound rules are stateful by default, so reply traffic is admitted.
pass out

# IPv6 control traffic required for path MTU and neighbour/router discovery.
pass inet6 proto icmp6 icmp6-type {
	unreach, toobig, timex, paramprob,
	routersol, routeradv, neighbrsol, neighbradv
}
EOF

	if ! pfctl -nf "$pf_tmp"; then
		rm -f "$pf_tmp"
		error "PF rejected the candidate ruleset; nothing was changed."
		return
	fi
	backup_file /etc/pf.conf || {
		rm -f "$pf_tmp"
		error "Could not back up /etc/pf.conf."
		return
	}
	install -o root -g wheel -m 600 "$pf_tmp" /etc/pf.conf || {
		rm -f "$pf_tmp"
		error "Could not install /etc/pf.conf."
		return
	}
	rm -f "$pf_tmp"
	pfctl -f /etc/pf.conf || {
		error "The validated PF ruleset could not be loaded; restore $BACKUP_PATH."
		return
	}
	if ! pfctl -s info | grep -q '^Status: Enabled'; then
		pfctl -e || warn "PF is configured but could not be enabled."
	fi
	log "PF workstation policy installed and loaded."
}

configure_privacy_services() {
	if confirm "Install and enable the Tor service?"; then
		ensure_package tor || return
		rcctl enable tor
		rcctl start tor || warn "Tor was enabled but did not start; inspect its log."
	fi
	if confirm "Install and enable the I2P service?"; then
		ensure_package i2pd || return
		rcctl enable i2pd
		rcctl start i2pd || warn "i2pd was enabled but did not start; inspect its log."
	fi
}

configure_clamav() {
	confirm "Install ClamAV and enable its database/daemon services?" || return
	ensure_package clamav || return

	for config in /etc/clamd.conf /etc/freshclam.conf; do
		if [ -f "$config" ] && grep -q '^Example$' "$config"; then
			backup_file "$config" || {
				error "Could not back up $config."
				return
			}
			clam_tmp=$(mktemp /tmp/clam-config.XXXXXX) || exit 1
			if ! sed '/^Example$/d' "$config" >"$clam_tmp"; then
				rm -f "$clam_tmp"
				error "Could not activate $config."
				return
			fi
			if ! install -o root -g wheel -m 644 "$clam_tmp" "$config"; then
				rm -f "$clam_tmp"
				error "Could not install the activated $config."
				return
			fi
			rm -f "$clam_tmp"
		fi
	done

	rcctl enable freshclam
	rcctl enable clamd
	rcctl start freshclam || warn "freshclam did not start; inspect its log."
	rcctl start clamd || warn "clamd did not start; inspect its log."
	warn "ClamAV is available for explicit scans; Linux-only clamonacc is not configured."
}

enforce_wx_mounts() {
	confirm "Remove every wxallowed option from /etc/fstab?" || return
	[ -f /etc/fstab ] || {
		warn "/etc/fstab does not exist."
		return
	}
	if ! awk '
		!/^[[:space:]]*#/ && NF >= 4 {
			n = split($4, option, ",")
			for (i = 1; i <= n; i++)
				if (option[i] == "wxallowed") found = 1
		}
		END { exit !found }
	' /etc/fstab; then
		log "No wxallowed mount option is present."
		return
	fi
	warn "Removing wxallowed can prevent ports that require executable writable mappings from starting."
	confirm "Continue after reviewing the affected filesystems and installed software?" || return

	backup_file /etc/fstab || {
		error "Could not back up /etc/fstab."
		return
	}
	fstab_tmp=$(mktemp /tmp/fstab.XXXXXX) || exit 1
	awk '
	/^[[:space:]]*#/ || NF < 4 { print; next }
	{
		n = split($4, option, ",")
		result = ""
		for (i = 1; i <= n; i++)
			if (option[i] != "wxallowed" && option[i] != "")
				result = result (result == "" ? "" : ",") option[i]
		$4 = (result == "" ? "rw" : result)
		print
	}' /etc/fstab >"$fstab_tmp" || {
		rm -f "$fstab_tmp"
		error "Could not generate the new fstab."
		return
	}
	if ! install -o root -g wheel -m 600 "$fstab_tmp" /etc/fstab; then
		rm -f "$fstab_tmp"
		error "Could not install the new /etc/fstab."
		return
	fi
	rm -f "$fstab_tmp"
	REBOOT_NEEDED=1
	warn "Existing mounts are unchanged. Reboot is required to enforce the new flags."
}

harden_malloc() {
	confirm "Enable vm.malloc_conf=S system-wide (security-audit mode)?" || return
	warn "This enables expensive malloc checks and can expose bugs or reduce performance."
	confirm "Apply and persist vm.malloc_conf=S?" || return

	backup_file /etc/sysctl.conf || {
		error "Could not back up /etc/sysctl.conf."
		return
	}
	if ! sysctl vm.malloc_conf=S; then
		error "The running kernel rejected vm.malloc_conf; nothing was persisted."
		return
	fi
	sysctl_tmp=$(mktemp /tmp/sysctl.conf.XXXXXX) || exit 1
	if [ -f /etc/sysctl.conf ]; then
		awk '!/^[[:space:]]*vm\.malloc_conf[[:space:]]*=/' \
			/etc/sysctl.conf >"$sysctl_tmp"
	fi
	print 'vm.malloc_conf=S' >>"$sysctl_tmp"
	if ! install -o root -g wheel -m 600 "$sysctl_tmp" /etc/sysctl.conf; then
		rm -f "$sysctl_tmp"
		error "Could not install /etc/sysctl.conf; the setting is active only until reboot."
		return
	fi
	rm -f "$sysctl_tmp"
	log "vm.malloc_conf=S is active and persistent."
}

configure_anacron() {
	confirm "Use anacron for the standard daily, weekly and monthly jobs?" || return
	ensure_package anacron || return

	backup_file /etc/anacrontab || {
		error "Could not back up /etc/anacrontab."
		return
	}
	anacron_tmp=$(mktemp /tmp/anacrontab.XXXXXX) || exit 1
	cat >"$anacron_tmp" <<'EOF'
SHELL=/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin
HOME=/var/log

1  5  cron.daily    /bin/sh /etc/daily
7  10 cron.weekly   /bin/sh /etc/weekly
30 15 cron.monthly  /bin/sh /etc/monthly
EOF
	if ! install -o root -g wheel -m 600 "$anacron_tmp" /etc/anacrontab; then
		rm -f "$anacron_tmp"
		error "Could not install /etc/anacrontab."
		return
	fi
	rm -f "$anacron_tmp"

	cron_old=$(mktemp /tmp/root-crontab.XXXXXX) || exit 1
	crontab -l >"$cron_old" 2>/dev/null || : >"$cron_old"
	cron_backup=$(mktemp /root/crontab.before-anacron.XXXXXX) || exit 1
	cp "$cron_old" "$cron_backup"
	log "Root crontab backup: $cron_backup"
	cron_new=$(mktemp /tmp/root-crontab-new.XXXXXX) || exit 1
	awk '
	/^[[:space:]]*#/ { print; next }
	/\/usr\/local\/sbin\/anacron[[:space:]]+-ds/ { next }
	/\/bin\/sh[[:space:]]+\/etc\/(daily|weekly|monthly)([[:space:]]|$)/ {
		print "# disabled in favour of anacron: " $0
		next
	}
	{ print }
	END {
		print "@reboot /usr/local/sbin/anacron -ds"
		print "15 2 * * * /usr/local/sbin/anacron -ds"
	}' "$cron_old" >"$cron_new"
	if crontab "$cron_new"; then
		log "Anacron installed without unattended OS or package upgrades."
	else
		error "Could not install root's updated crontab."
	fi
	rm -f "$cron_old" "$cron_new"
}

finish() {
	if [ "$REBOOT_NEEDED" -eq 1 ]; then
		warn "A reboot is required for the changed mount flags."
		if confirm "Reboot now?"; then
			reboot
		fi
	else
		log "Selected configuration tasks are complete; no reboot is required by this script."
	fi
}

main() {
	check_root
	configure_firewall
	configure_privacy_services
	configure_clamav
	enforce_wx_mounts
	harden_malloc
	configure_anacron
	finish
}

main "$@"
