---
name: openbsd-system-hardening
description: Evaluate OpenBSD workstation hardening advice for wxallowed, malloc auditing, ClamAV, Tor/i2pd and anacron, and reject obsolete or unsupported recommendations.
---

# OpenBSD system hardening

## When to use

Activate this skill when evaluating or documenting a hardening operation,
reviewing a recommendation for an OpenBSD workstation, or deciding whether an
older practice should be reintroduced. This skill covers the non-PF operations
in `hardening.ksh`.

## Preconditions

- The target is a workstation. Do not generalize the advice to servers,
  routers, bridges, VPN gateways or appliances.
- Verify claims against current OpenBSD manual pages and the packaged ports,
  not against old blog posts, old script revisions or Linux behavior.
- Do not install packages, edit `/etc`, start services or change sysctls during
  review.

## Procedure

1. **wxallowed.** Treat `wxallowed` as a per-mount `fstab(5)` relaxation of
   W^X, not a global sysctl. The script removes the exact comma-separated
   option from field 4, does not remount active filesystems, and requires a
   reboot. Warn that ports needing executable writable mappings may fail. Never
   recommend `kern.wxallowed` or claim `mount -a` remounts active mounts.
2. **malloc auditing.** `vm.malloc_conf=S` enables the expensive
   security-audit set. Explain that it applies to processes started after the
   change, can expose bugs and reduce performance, and is persisted in
   `/etc/sysctl.conf`. It is not a free default and requires explicit
   confirmation.
3. **ClamAV.** Use the packaged OpenBSD port. Activating the sample
   configuration means removing the exact `Example` line from
   `/etc/clamd.conf` and `/etc/freshclam.conf`; enabling `freshclam` and `clamd`
   does not schedule scans. Starting `clamd` does not wait for the first
   database download, so it may need a later restart. Scanning remains explicit.
   `clamonacc` is Linux-specific and must not be configured on OpenBSD.
4. **Tor and i2pd.** Install and enable the packaged services only. Do not edit
   mirror lists, `/etc/installurl`, `login.conf`, `sysupgrade` or `syspatch`,
   and do not claim that OpenBSD updates are redirected through Tor or I2P.
5. **anacron.** Use the packaged anacrontab for `/etc/daily`, `/etc/weekly` and
   `/etc/monthly`; comment simple matching direct root-crontab entries; leave
   compound lines that also run other commands unchanged and warn about them;
   invoke anacron at boot and daily. Validate the candidate with `anacron -T`.
   Never add unattended `sysupgrade` or `pkg_add -u`. If `/etc/daily.local`,
   `/etc/weekly.local` or `/etc/monthly.local` contain such commands, warn and
   require confirmation because anacron will execute those files.
6. **Obsolete advice.** Reject, and do not reintroduce:
   - a hard-coded user with an MD5-crypt password or a printed password;
   - patched `/usr/sbin/sysupgrade` or `/usr/sbin/syspatch`;
   - unverified Tor/I2P mirrors or edited `/etc/installurl`;
   - blocking `firmware.openbsd.org`;
   - `kern.wxallowed` or `mount -a` as a remount;
   - `schg` on base configuration files;
   - replacing Xenocara's `Xsession` or forcing the Intel driver;
   - blanket USB controller disabling without hardware review;
   - unattended OS or package upgrades.
7. Check whether the change is documented in `README.md`, including its
   limitations and confirmation prompts.

## Validation

- Compare each claim with the current `hardening.ksh` function and `README.md`.
- Prefer OpenBSD manual pages and ports documentation over secondary sources.
- Confirm the operation is reversible or has an explicit backup/restore path.
- Confirm the script does not silently widen scope from workstation to server.
- Static review only. Do not run package, service, sysctl, mount or reboot
  commands.

## Common problems

- Describing `wxallowed` as a kernel-wide setting.
- Assuming `mount -a` applies new mount flags to active filesystems.
- Presenting `vm.malloc_conf=S` as harmless or always beneficial.
- Treating ClamAV daemon enablement as scheduled or on-access scanning.
- Reusing Linux `clamonacc` instructions on OpenBSD.
- Claiming Tor transparently proxies package or system updates.
- Letting old `/etc/daily.local` content run upgrades under the new anacron
  configuration.
- Citing removed `bsd.re-config` or X11 workarounds as current practice.

## References

- `../../../hardening.ksh`
- `../../../README.md`
- `../../../AGENTS.md`
- [malloc(3)](https://man.openbsd.org/malloc.3)
- [sysctl(8)](https://man.openbsd.org/sysctl.8)
- [fstab(5)](https://man.openbsd.org/fstab.5)
- [mount(8)](https://man.openbsd.org/mount.8)
- [OpenBSD ports: ClamAV](https://github.com/openbsd/ports/tree/master/security/clamav)
- [OpenBSD ports: anacron](https://github.com/openbsd/ports/tree/master/sysutils/anacron)

## Maintenance & Continuous Learning

Whenever this skill is used to change the repository, review this skill after
the implementation. Correct procedures that proved wrong, update commands,
paths, configuration and examples, incorporate reusable findings, and remove
outdated assumptions. Review the applicable root and nested `AGENTS.md` files,
specialized agents and related skills; update only the knowledge affected by
the work. Validate local references and run
`python3 scripts/validate-agent-knowledge.py --scope worktree` plus the
applicable project checks. For pull request comparisons, use the documented
`--scope range --base BASE_REF --head HEAD_REF` command. The canonical validator
is read-only and is required even when a task restricts execution of project
scripts; this does not authorize running installers or changing the host.
Report checks actually performed. A structural pass does not prove semantic
relevance, and a task is incomplete until synchronization is validated.
