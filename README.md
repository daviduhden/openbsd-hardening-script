# OpenBSD hardening helpers

This is an interactive, conservative set of OpenBSD workstation-hardening
helpers. Every material change is optional, existing files are backed up before
they are modified, candidate PF syntax is checked before installation, and the
script exits nonzero when a selected task fails. The script only runs on OpenBSD
and removes its temporary working files on normal exit.

Run it as root on OpenBSD after reviewing both the script and the policy choices:

```sh
$ doas ksh hardening.ksh
```

The script takes no arguments.

## Supported operations

- Install a default-deny, outbound-only workstation PF policy. It keeps loopback
  unfiltered, admits DHCPv4 and DHCPv6 client traffic explicitly, relies on PF's
  stateful outbound rules, and admits the ICMPv6 control messages needed for
  path MTU and neighbour/router discovery. It is not suitable unchanged for
  servers, routers, bridges, VPN gateways or machines with custom anchors.
- Optionally install and enable the packaged Tor and/or i2pd services. The
  script does not redirect OpenBSD updates through them.
- Install ClamAV, activate the packaged sample configurations by removing
  `Example`, then enable `freshclam` and `clamd`. Scanning remains explicit;
  `clamonacc` on-access scanning is Linux-specific and is not configured.
- Remove the exact `wxallowed` option token from `/etc/fstab`. OpenBSD enforces
  W^X by default and `wxallowed` is the per-mount relaxation. A second
  confirmation warns that ports requiring executable writable mappings may stop
  working. Existing mounts are not silently remounted; the change takes effect
  after reboot.
- Optionally set the documented `vm.malloc_conf=S` security-audit mode. This is
  more expensive than the OpenBSD default and can affect performance, so a
  second confirmation is required. The setting applies to processes started
  after the change and is persisted in `/etc/sysctl.conf`.
- Configure the packaged `anacron` exactly for `/etc/daily`, `/etc/weekly` and
  `/etc/monthly`, comment their simple direct root-crontab entries to avoid
  duplicate execution, and invoke anacron at boot and daily. Compound crontab
  lines that also run other commands are left unchanged with a warning so those
  commands are not disabled. The previous `/etc/anacrontab` is backed up but
  custom jobs are not merged into the replacement. The candidate is validated
  with `anacron -T`, and the previous anacrontab and root crontab are restored
  if installation fails. The script warns before continuing if local
  `/etc/daily.local`, `/etc/weekly.local` or `/etc/monthly.local` files contain
  `sysupgrade` or `pkg_add -u`. It never invokes those upgrade commands itself.

## Backups and failure handling

Backups use a unique `.hardening.XXXXXX` suffix next to the changed file and
preserve its ownership and mode. The previous root crontab is saved below
`/root/crontab.before-anacron.XXXXXX`. `/etc/rc.conf.local` is backed up before
the first `rcctl enable`.

PF is validated with `pfctl -nf` before `/etc/pf.conf` is replaced. The installed
file is compared with the validated candidate, and the previous file and loaded
ruleset are restored if installation, loading or enabling PF fails. A
syntactically valid ruleset can still disrupt connectivity, so review the policy
for the machine before running the script; the script does not test network
reachability after loading it. Other configuration files are restored if their
installation fails. Package installation, live `sysctl` changes and service
state are not transactionally rolled back.

The script exits with status 0 only when every selected task succeeds or is
declined. Errors are printed with an `[ERROR]` prefix and produce a nonzero exit
status. A declined reboot leaves the new `/etc/fstab` in place for the next boot.

## Deliberately excluded behaviour

Earlier versions performed operations that are unsupported, obsolete or
counterproductive and have been removed:

- creating a hard-coded user with an MD5-crypt password and printing that
  password;
- patching `/usr/sbin/sysupgrade` and `/usr/sbin/syspatch`, changing
  `login.conf`, or selecting unverified Tor/I2P mirrors;
- blocking `firmware.openbsd.org` (firmware updates are security updates);
- setting the nonexistent `kern.wxallowed` sysctl or pretending that `mount -a`
  remounts active filesystems;
- making base configuration files immutable with `schg`;
- replacing Xenocara's base `Xsession`, forcing the legacy Intel X driver, or
  writing into `/usr/X11R6`;
- disabling every USB controller, which can remove keyboards, storage and
  recovery paths without a machine-specific hardware review;
- running `sysupgrade` or `pkg_add -u` unattended, including through
  `/etc/daily.local`.

The current script does not undo artifacts left by earlier versions on systems
that already ran them. Review `/etc/daily.local`, `/etc/installurl`,
`/etc/hosts`, `/etc/login.conf`, `/etc/bsd.re-config`, Xenocara files and
`schg` flags manually before relying on the current behavior.

## Official references

- [pf.conf(5)](https://man.openbsd.org/pf.conf.5) and
  [pfctl(8)](https://man.openbsd.org/pfctl.8)
- [mount(8)](https://man.openbsd.org/mount.8) and
  [fstab(5)](https://man.openbsd.org/fstab.5)
- [malloc(3)](https://man.openbsd.org/malloc.3) (`vm.malloc_conf` and option
  `S`)
- [sysctl(8)](https://man.openbsd.org/sysctl.8)
- [OpenBSD ports tree: ClamAV](https://github.com/openbsd/ports/tree/master/security/clamav)
- [OpenBSD ports tree: anacron](https://github.com/openbsd/ports/tree/master/sysutils/anacron)

## License

See [LICENSE](LICENSE).
