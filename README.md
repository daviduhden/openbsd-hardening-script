# OpenBSD hardening helpers

This is an interactive, conservative set of OpenBSD workstation-hardening helpers. Every material change is optional, existing configuration is backed up, and candidate PF syntax is checked before installation.

Run it as root on OpenBSD after reviewing both the script and the policy choices:

```sh
$ doas ksh hardening.ksh
```

## Supported operations

- Install a default-deny, outbound-only workstation PF policy. It keeps loopback unfiltered, relies on PF's stateful outbound rules and admits the ICMPv6 control messages needed for IPv6. It is not suitable unchanged for servers, routers, bridges, VPN gateways or machines with custom anchors.
- Optionally install and enable the packaged Tor and/or i2pd services. The script does not redirect OpenBSD updates through them.
- Install ClamAV, activate the packaged sample configurations by removing `Example`, then enable `freshclam` and `clamd`. Scanning remains explicit; `clamonacc` on-access scanning is Linux-specific and is not configured.
- Remove `wxallowed` from `/etc/fstab`. OpenBSD enforces W^X by default and `wxallowed` is the per-mount relaxation. A second confirmation warns that ports requiring executable writable mappings may stop working. Existing mounts are not silently remounted; the change takes effect after reboot.
- Optionally set the documented `vm.malloc_conf=S` security-audit mode. This is more expensive than the OpenBSD default and can affect performance, so a second confirmation is required.
- Configure the packaged `anacron` exactly for `/etc/daily`, `/etc/weekly` and `/etc/monthly`, comment their direct root-crontab entries to avoid duplicate execution, and invoke anacron at boot and daily. It never runs `sysupgrade` or `pkg_add -u` unattended.

Backups use a unique `.hardening.XXXXXX` suffix next to the changed file. The previous root crontab is saved below `/root/crontab.before-anacron.XXXXXX`.

## Deliberately excluded behaviour

Earlier versions performed operations that are unsupported, obsolete or counterproductive and have been removed:

- creating a hard-coded user with an MD5-crypt password and printing that password;
- patching `/usr/sbin/sysupgrade` and `/usr/sbin/syspatch`, changing `login.conf`, or selecting unverified Tor/I2P mirrors;
- blocking `firmware.openbsd.org` (firmware updates are security updates);
- setting the nonexistent `kern.wxallowed` sysctl or pretending that `mount -a` remounts active filesystems;
- making base configuration files immutable with `schg`;
- replacing Xenocara's base `Xsession`, forcing the legacy Intel X driver, or writing into `/usr/X11R6`;
- disabling every USB controller, which can remove keyboards, storage and recovery paths without a machine-specific hardware review.

## Official references

- [pf.conf(5)](https://man.openbsd.org/pf.conf.5) and [pfctl(8)](https://man.openbsd.org/pfctl.8)
- [mount(8)](https://man.openbsd.org/mount.8) and [fstab(5)](https://man.openbsd.org/fstab.5)
- [malloc(3)](https://man.openbsd.org/malloc.3) (`vm.malloc_conf` and option `S`)
- [sysctl(8)](https://man.openbsd.org/sysctl.8)
- [bsd.re-config(5)](https://man.openbsd.org/bsd.re-config.5)
- [OpenBSD ports tree: ClamAV](https://github.com/openbsd/ports/tree/master/security/clamav)
- [OpenBSD ports tree: anacron](https://github.com/openbsd/ports/tree/master/sysutils/anacron)

## License

See [LICENSE](LICENSE).
