#!/bin/ksh

# Interactive, conservative hardening helpers for OpenBSD workstations.
# See LICENSE for copyright and licence details.

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export PATH
umask 077

log() { print "[INFO] $*"; }
warn() { print "[WARN] $*" >&2; }
error() {
	print "[ERROR] $*" >&2
	return 1
}

REBOOT_NEEDED=0
BACKUP_PATH=""
TMP_FILES=""
RC_CONF_BACKED_UP=0
CLAMD_BACKUP=""
FRESHCLAM_BACKUP=""

confirm() {
	typeset answer=""

	printf '%s [y/N]: ' "$1"
	read -r answer
	case "$answer" in
	[yY] | [yY][eE][sS]) return 0 ;;
	*) return 1 ;;
	esac
}

check_platform() {
	if [ "$(uname -s)" != "OpenBSD" ]; then
		error "This script only supports OpenBSD."
		exit 1
	fi
}

check_root() {
	if [ "$(id -u)" -ne 0 ]; then
		error "This script must be run as root."
		exit 1
	fi
}

track_tmp() {
	TMP_FILES="$TMP_FILES $1"
}

# Remove only paths registered by this script. The list is whitespace
# separated, so callers must register temporary paths without whitespace.
# Cleanup is best-effort and must not hide the status of the selected task.
# The EXIT trap calls this function indirectly, which ShellCheck cannot infer.
# shellcheck disable=SC2329
cleanup_tmp() {
	typeset file
	for file in $TMP_FILES; do
		rm -f "$file"
	done
}

trap 'cleanup_tmp' EXIT
trap 'exit 130' HUP INT TERM

# Save an existing regular file to a unique sibling path, preserving its
# metadata with cp -p. An absent file is not an error; BACKUP_PATH remains
# empty so callers can distinguish a newly created target from a replacement.
backup_file() {
	typeset file="$1"
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

# Restore a previously saved file over its target. This helper deliberately
# does not remove the backup, allowing the operator to inspect or reuse it.
restore_file() {
	typeset backup="$1" target="$2"
	[ -n "$backup" ] && [ -f "$backup" ] || return 1
	cp -p "$backup" "$target"
}

# Roll back either kind of change: restore the saved contents when a file
# existed, or remove the target when this run created it.
restore_or_remove() {
	typeset backup="$1" target="$2"
	if [ -n "$backup" ] && [ -f "$backup" ]; then
		cp -p "$backup" "$target"
	else
		rm -f "$target"
	fi
}

# Restore ClamAV configuration files only when this run recorded a backup.
# Package installation and service state are outside this file-level rollback.
restore_clamav_configs() {
	if [ -n "$CLAMD_BACKUP" ]; then
		restore_file "$CLAMD_BACKUP" /etc/clamd.conf ||
			warn "Could not restore /etc/clamd.conf from $CLAMD_BACKUP."
	fi
	if [ -n "$FRESHCLAM_BACKUP" ]; then
		restore_file "$FRESHCLAM_BACKUP" /etc/freshclam.conf ||
			warn "Could not restore /etc/freshclam.conf from $FRESHCLAM_BACKUP."
	fi
}

# Keep one pre-change copy of rc.conf.local for this run, even if several
# services are enabled. The flag is set only after the backup succeeds.
backup_rc_conf_once() {
	[ "$RC_CONF_BACKED_UP" -eq 1 ] && return 0
	backup_file /etc/rc.conf.local || return 1
	RC_CONF_BACKED_UP=1
}

ensure_package() {
	typeset package="$1"
	if pkg_info -e "$package" >/dev/null 2>&1; then
		return 0
	fi
	log "Installing package $package..."
	pkg_add "$package" || {
		error "Could not install $package."
		return 1
	}
}

restore_runtime_malloc() {
	typeset old="$1"
	# An empty prior value is not a value that can be restored immediately;
	# it indicates the live setting may remain in effect until reboot.
	if [ -n "$old" ]; then
		sysctl "vm.malloc_conf=$old" >/dev/null 2>&1 ||
			warn "The previous vm.malloc_conf value could not be restored."
	else
		warn "vm.malloc_conf remains changed until the next reboot."
	fi
}

# Restore both the on-disk PF policy and the active ruleset. A successful file
# copy alone does not put the previous firewall rules back into effect.
restore_pf() {
	typeset backup="$1"
	[ -n "$backup" ] && [ -f "$backup" ] || return 1
	restore_file "$backup" /etc/pf.conf && pfctl -f /etc/pf.conf
}

configure_firewall() {
	typeset pf_tmp pf_backup
	confirm "Install a default-deny PF ruleset for an outbound-only workstation?" || return 0
	warn "This replaces /etc/pf.conf. Servers, bridges, VPNs and custom anchors need tailored rules."
	confirm "Replace the current PF policy after syntax validation?" || return 0

	pf_tmp=$(mktemp /tmp/pf.conf.XXXXXX) || {
		error "Could not create a temporary PF candidate."
		return 1
	}
	track_tmp "$pf_tmp"
	if ! cat >"$pf_tmp" <<'EOF'
# Workstation baseline installed by hardening.ksh
set skip on lo
block return

# DHCP replies are broadcast and do not match outbound state.
# DHCPv4 client 68 to server 67, and the reply.
pass out quick inet proto udp from any port 68 to any port 67
pass in quick inet proto udp from any port 67 to any port 68
# DHCPv6 client 546 to server 547, and the reply.
pass out quick inet6 proto udp from any port 546 to any port 547
pass in quick inet6 proto udp from any port 547 to any port 546

# Outbound rules are stateful by default, so reply traffic is admitted.
pass out

# IPv6 control traffic required for path MTU and neighbour/router discovery.
pass inet6 proto icmp6 icmp6-type {
	unreach, toobig, timex, paramprob,
	routersol, routeradv, neighbrsol, neighbradv
}
EOF
	then
		rm -f "$pf_tmp"
		error "Could not write the PF candidate; nothing was changed."
		return 1
	fi

	if ! pfctl -nf "$pf_tmp"; then
		rm -f "$pf_tmp"
		error "PF rejected the candidate ruleset; nothing was changed."
		return 1
	fi
	backup_file /etc/pf.conf || {
		rm -f "$pf_tmp"
		error "Could not back up /etc/pf.conf."
		return 1
	}
	pf_backup="$BACKUP_PATH"
	if ! install -o root -g wheel -m 600 "$pf_tmp" /etc/pf.conf; then
		rm -f "$pf_tmp"
		if restore_pf "$pf_backup"; then
			error "Could not install /etc/pf.conf; previous policy restored."
		else
			error "Could not install /etc/pf.conf; review /etc/pf.conf manually."
		fi
		return 1
	fi
	if ! cmp -s "$pf_tmp" /etc/pf.conf; then
		rm -f "$pf_tmp"
		if restore_pf "$pf_backup"; then
			error "The installed PF file did not match the candidate; previous policy restored."
		else
			error "The installed PF file did not match the candidate; review /etc/pf.conf manually."
		fi
		return 1
	fi
	rm -f "$pf_tmp"
	if ! pfctl -f /etc/pf.conf; then
		if restore_pf "$pf_backup"; then
			error "The new ruleset did not load; previous PF policy restored."
		else
			error "The new ruleset did not load; review /etc/pf.conf manually."
		fi
		return 1
	fi
	if ! pfctl -s info | grep -q '^Status: Enabled'; then
		if ! pfctl -e; then
			if restore_pf "$pf_backup"; then
				error "PF could not be enabled; previous PF policy restored."
			else
				error "PF could not be enabled; review /etc/pf.conf manually."
			fi
			return 1
		fi
	fi
	if grep -Eq '^[[:space:]]*pf=NO([[:space:]]|$)' \
		/etc/rc.conf /etc/rc.conf.local 2>/dev/null; then
		warn "PF is disabled in the rc configuration and will not start at boot."
	fi
	log "PF workstation policy installed and loaded."
}

configure_privacy_services() {
	typeset status=0

	if confirm "Install and enable the Tor service?"; then
		if ! ensure_package tor; then
			status=1
		elif ! backup_rc_conf_once; then
			error "Could not back up /etc/rc.conf.local; Tor was not enabled."
			status=1
		elif ! rcctl enable tor; then
			error "Could not enable Tor."
			status=1
		elif ! rcctl start tor; then
			warn "Tor did not start; inspect its log."
			status=1
		fi
	fi

	if confirm "Install and enable the I2P service?"; then
		if ! ensure_package i2pd; then
			status=1
		elif ! backup_rc_conf_once; then
			error "Could not back up /etc/rc.conf.local; i2pd was not enabled."
			status=1
		elif ! rcctl enable i2pd; then
			error "Could not enable i2pd."
			status=1
		elif ! rcctl start i2pd; then
			warn "i2pd did not start; inspect its log."
			status=1
		fi
	fi

	return "$status"
}

configure_clamav() {
	typeset config config_backup clam_tmp status=0
	CLAMD_BACKUP=""
	FRESHCLAM_BACKUP=""
	confirm "Install ClamAV and enable its database/daemon services?" || return 0
	ensure_package clamav || return 1

	for config in /etc/clamd.conf /etc/freshclam.conf; do
		[ -f "$config" ] || continue
		grep -q '^Example$' "$config" 2>/dev/null || continue
		backup_file "$config" || {
			restore_clamav_configs
			error "Could not back up $config."
			return 1
		}
		config_backup="$BACKUP_PATH"
		case "$config" in
		/etc/clamd.conf) CLAMD_BACKUP="$config_backup" ;;
		/etc/freshclam.conf) FRESHCLAM_BACKUP="$config_backup" ;;
		esac
		clam_tmp=$(mktemp /tmp/clam-config.XXXXXX) || {
			restore_clamav_configs
			error "Could not create a temporary ClamAV configuration."
			return 1
		}
		track_tmp "$clam_tmp"
		if ! sed '/^Example$/d' "$config" >"$clam_tmp"; then
			rm -f "$clam_tmp"
			restore_clamav_configs
			error "Could not activate $config."
			return 1
		fi
		if ! install -o root -g wheel -m 644 "$clam_tmp" "$config"; then
			rm -f "$clam_tmp"
			restore_clamav_configs
			error "Could not install the activated $config."
			return 1
		fi
		rm -f "$clam_tmp"
	done

	if ! backup_rc_conf_once; then
		restore_clamav_configs
		error "Could not back up /etc/rc.conf.local; ClamAV services were not enabled."
		return 1
	fi
	if ! rcctl enable freshclam; then
		error "Could not enable freshclam."
		status=1
	fi
	if ! rcctl enable clamd; then
		error "Could not enable clamd."
		status=1
	fi
	rcctl start freshclam || {
		warn "freshclam did not start; inspect its log."
		status=1
	}
	rcctl start clamd || {
		warn "clamd did not start; inspect its log."
		status=1
	}
	warn "ClamAV is available for explicit scans; Linux-only clamonacc is not configured."
	return "$status"
}

# Remove only the exact wxallowed token from the fourth fstab field; comments,
# short records, and similarly named options are left alone. This edits the
# boot-time policy only, so already mounted filesystems are unchanged.
enforce_wx_mounts() {
	typeset fstab_backup fstab_tmp
	confirm "Remove every wxallowed option from /etc/fstab?" || return 0
	[ -f /etc/fstab ] || {
		warn "/etc/fstab does not exist."
		return 0
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
		return 0
	fi
	warn "Removing wxallowed can prevent ports that require executable writable mappings from starting."
	confirm "Continue after reviewing the affected filesystems and installed software?" || return 0

	backup_file /etc/fstab || {
		error "Could not back up /etc/fstab."
		return 1
	}
	fstab_backup="$BACKUP_PATH"
	fstab_tmp=$(mktemp /tmp/fstab.XXXXXX) || {
		error "Could not create a temporary /etc/fstab candidate."
		return 1
	}
	track_tmp "$fstab_tmp"
	if ! awk '
	/^[[:space:]]*#/ || NF < 4 { print; next }
	{
		n = split($4, option, ",")
		result = ""
		for (i = 1; i <= n; i++)
			if (option[i] != "wxallowed" && option[i] != "")
				result = result (result == "" ? "" : ",") option[i]
		$4 = (result == "" ? "rw" : result)
		print
	}' /etc/fstab >"$fstab_tmp"; then
		rm -f "$fstab_tmp"
		error "Could not generate the new /etc/fstab."
		return 1
	fi
	if ! install -o root -g wheel -m 644 "$fstab_tmp" /etc/fstab; then
		rm -f "$fstab_tmp"
		restore_file "$fstab_backup" /etc/fstab ||
			warn "Could not restore /etc/fstab from $fstab_backup."
		error "Could not install the new /etc/fstab."
		return 1
	fi
	rm -f "$fstab_tmp"
	REBOOT_NEEDED=1
	warn "Existing mounts are unchanged. Reboot is required to enforce the new flags."
}

# Apply the malloc audit mode to the running kernel before persisting it. If
# writing or verifying sysctl.conf fails, restore the prior live value when it
# was known and restore or remove the file according to its original state.
harden_malloc() {
	typeset malloc_old sysctl_tmp sysctl_backup
	confirm "Enable vm.malloc_conf=S system-wide (security-audit mode)?" || return 0
	warn "This enables expensive malloc checks and can expose bugs or reduce performance."
	confirm "Apply and persist vm.malloc_conf=S?" || return 0

	malloc_old=$(sysctl -n vm.malloc_conf 2>/dev/null) || malloc_old=""
	backup_file /etc/sysctl.conf || {
		error "Could not back up /etc/sysctl.conf."
		return 1
	}
	sysctl_backup="$BACKUP_PATH"
	if ! sysctl vm.malloc_conf=S; then
		error "The running kernel rejected vm.malloc_conf; nothing was persisted."
		return 1
	fi
	sysctl_tmp=$(mktemp /tmp/sysctl.conf.XXXXXX) || {
		error "Could not create a temporary /etc/sysctl.conf; the setting is active only until reboot."
		restore_runtime_malloc "$malloc_old"
		return 1
	}
	track_tmp "$sysctl_tmp"
	if [ -f /etc/sysctl.conf ]; then
		if ! awk '!/^[[:space:]]*vm\.malloc_conf[[:space:]]*=/' \
			/etc/sysctl.conf >"$sysctl_tmp"; then
			rm -f "$sysctl_tmp"
			error "Could not rewrite /etc/sysctl.conf; the setting is active only until reboot."
			restore_runtime_malloc "$malloc_old"
			return 1
		fi
	fi
	if ! print 'vm.malloc_conf=S' >>"$sysctl_tmp"; then
		rm -f "$sysctl_tmp"
		error "Could not prepare /etc/sysctl.conf; the setting is active only until reboot."
		restore_runtime_malloc "$malloc_old"
		return 1
	fi
	if ! install -o root -g wheel -m 600 "$sysctl_tmp" /etc/sysctl.conf; then
		rm -f "$sysctl_tmp"
		restore_or_remove "$sysctl_backup" /etc/sysctl.conf ||
			warn "Could not restore /etc/sysctl.conf from $sysctl_backup."
		error "Could not install /etc/sysctl.conf; the setting is active only until reboot."
		restore_runtime_malloc "$malloc_old"
		return 1
	fi
	rm -f "$sysctl_tmp"
	if ! grep -qx 'vm.malloc_conf=S' /etc/sysctl.conf ||
		[ "$(sysctl -n vm.malloc_conf)" != "S" ]; then
		restore_or_remove "$sysctl_backup" /etc/sysctl.conf ||
			warn "Could not restore /etc/sysctl.conf from $sysctl_backup."
		error "The vm.malloc_conf change could not be verified."
		restore_runtime_malloc "$malloc_old"
		return 1
	fi
	log "vm.malloc_conf=S is active and persistent."
}

# Replace only direct standard daily/weekly/monthly cron invocations. Compound
# lines are retained to avoid disabling their unrelated commands; the new
# anacron file and root crontab are installed in stages with best-effort restore.
configure_anacron() {
	typeset cron_old cron_err cron_backup cron_new anacron_tmp anacron_backup
	typeset local_file unattended=0
	confirm "Use anacron for the standard daily, weekly and monthly jobs?" || return 0

	for local_file in /etc/daily.local /etc/weekly.local /etc/monthly.local; do
		[ -f "$local_file" ] || continue
		if grep -Eq '^[[:space:]]*[^#[:space:]].*(sysupgrade|pkg_add[[:space:]]+-u)' \
			"$local_file" 2>/dev/null; then
			warn "$local_file contains an unattended upgrade command."
			unattended=1
		fi
	done
	if [ "$unattended" -eq 1 ]; then
		confirm "Continue although anacron may run these commands?" || return 0
	fi

	ensure_package anacron || return 1

	cron_old=$(mktemp /tmp/root-crontab.XXXXXX) || {
		error "Could not create a temporary root crontab."
		return 1
	}
	track_tmp "$cron_old"
	cron_err=$(mktemp /tmp/root-crontab-err.XXXXXX) || {
		error "Could not create a temporary crontab error file."
		return 1
	}
	track_tmp "$cron_err"
	if ! crontab -l >"$cron_old" 2>"$cron_err"; then
		if grep -qi 'no crontab' "$cron_err"; then
			: >"$cron_old" || {
				error "Could not prepare an empty root crontab."
				return 1
			}
		else
			error "Could not read the root crontab; it is unchanged."
			cat "$cron_err" >&2
			return 1
		fi
	fi

	cron_new=$(mktemp /tmp/root-crontab-new.XXXXXX) || {
		error "Could not create a temporary new root crontab."
		return 1
	}
	track_tmp "$cron_new"
	if ! awk '
	/^[[:space:]]*#/ { print; next }
	/(^|[[:space:]]|\/)anacron([[:space:]]|$)/ { next }
	/\/etc\/(daily|weekly|monthly)([[:space:]]|$)/ {
		if ($0 ~ /&&|\|\||;|\|/) {
			print "[WARN] direct job left unchanged because the line has multiple commands: " $0 > "/dev/stderr"
			print
		} else {
			print "# disabled in favour of anacron: " $0
		}
		next
	}
	{ print }
	END {
		print "@reboot /usr/local/sbin/anacron -ds"
		print "15 2 * * * /usr/local/sbin/anacron -ds"
	}' "$cron_old" >"$cron_new"; then
		error "Could not generate the new root crontab; it is unchanged."
		return 1
	fi

	anacron_tmp=$(mktemp /tmp/anacrontab.XXXXXX) || {
		error "Could not create a temporary /etc/anacrontab candidate."
		return 1
	}
	track_tmp "$anacron_tmp"
	if ! cat >"$anacron_tmp" <<'EOF'
SHELL=/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin
HOME=/var/log

1  5  cron.daily    /bin/sh /etc/daily
7  10 cron.weekly   /bin/sh /etc/weekly
30 15 cron.monthly  /bin/sh /etc/monthly
EOF
	then
		error "Could not write the /etc/anacrontab candidate."
		return 1
	fi

	backup_file /etc/anacrontab || {
		error "Could not back up /etc/anacrontab."
		return 1
	}
	anacron_backup="$BACKUP_PATH"

	cron_backup=$(mktemp /root/crontab.before-anacron.XXXXXX) || {
		error "Could not create a root crontab backup."
		return 1
	}
	if ! cp "$cron_old" "$cron_backup"; then
		rm -f "$cron_backup"
		error "Could not back up the root crontab."
		return 1
	fi
	log "Root crontab backup: $cron_backup"

	if ! install -o root -g wheel -m 600 "$anacron_tmp" /etc/anacrontab; then
		restore_or_remove "$anacron_backup" /etc/anacrontab ||
			warn "Could not restore /etc/anacrontab from $anacron_backup."
		error "Could not install /etc/anacrontab."
		return 1
	fi
	if ! /usr/local/sbin/anacron -T; then
		restore_or_remove "$anacron_backup" /etc/anacrontab ||
			warn "Could not restore /etc/anacrontab from $anacron_backup."
		error "anacron rejected /etc/anacrontab; the previous file was restored where possible."
		return 1
	fi
	if crontab "$cron_new"; then
		log "Anacron installed without unattended OS or package upgrades."
	else
		restore_or_remove "$anacron_backup" /etc/anacrontab ||
			warn "Could not restore /etc/anacrontab from $anacron_backup."
		crontab "$cron_backup" >/dev/null 2>&1 ||
			warn "Could not restore the root crontab from $cron_backup."
		error "Could not install root's updated crontab; the previous configuration was restored where possible."
		return 1
	fi
	rm -f "$cron_old" "$cron_new" "$cron_err"
}

finish() {
	if [ "$REBOOT_NEEDED" -eq 1 ]; then
		warn "A reboot is required for the changed mount flags."
		confirm "Reboot now?" || return 0
		if ! reboot; then
			error "The reboot command failed; reboot manually to apply the mount flags."
			return 1
		fi
	else
		log "Selected configuration tasks are complete; no reboot is required by this script."
	fi
}

main() {
	typeset status=0
	if [ "$#" -gt 0 ]; then
		error "This script takes no arguments."
		exit 1
	fi
	check_platform
	check_root
	configure_privacy_services || status=1
	configure_clamav || status=1
	configure_anacron || status=1
	enforce_wx_mounts || status=1
	harden_malloc || status=1
	configure_firewall || status=1
	finish || status=1
	if [ "$status" -ne 0 ]; then
		error "One or more selected tasks failed; review the output above."
	fi
	exit "$status"
}

main "$@"
