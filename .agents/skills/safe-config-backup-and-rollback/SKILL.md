---
name: safe-config-backup-and-rollback
description: Design and review backups, temporary-file handling and restoration paths for OpenBSD configuration changes, including PF, fstab, sysctl.conf, anacrontab, rc.conf.local and the root crontab.
---

# Safe configuration backup and rollback

## When to use

Activate this skill when adding or changing a file mutation, backup, temporary
file, installation step, rollback path or system-wide setting in
`hardening.ksh`. Also use it when reviewing whether a failed task leaves the
system in a recoverable state.

## Preconditions

- Read `AGENTS.md`, `hardening.ksh`, `README.md` and the relevant manual pages.
- Enumerate every side effect, not only the obvious file: `pkg_add`,
  `rcctl enable`, `crontab`, live `sysctl`, `pfctl` and `reboot` all change
  state outside the target file.
- Work statically. Do not create backups, edit `/etc`, install packages or run
  the script.

## Procedure

1. **Enumerate targets and side effects.** For each task, list:
   - file content replaced;
   - file mode and ownership;
   - live kernel or service state changed;
   - package database, `/etc/rc.conf.local`, `/var/cron/tabs/root` or `/root`
     changes;
   - whether the action can be undone automatically.
2. **Back up before mutating.** Call `backup_file` while the original still
   exists. It creates `<file>.hardening.XXXXXX` with `mktemp`, copies with
   `cp -p` to preserve ownership and mode, and logs the path. A missing original
   returns success with an empty `BACKUP_PATH`; do not treat that as a restorable
   backup.
3. **Generate candidates separately.** Write new content to a tracked `mktemp`
   file, never directly to the target. Validate it where possible:
   - PF: `pfctl -nf` on the candidate;
   - anacron: install then `anacron -T`, restoring on rejection;
   - structured text: review the `awk` transformation and test on fixtures only
     when the user permits execution.
4. **Install atomically and verify.** Use `install` with explicit owner and
   mode. For PF, compare the installed file with the validated candidate before
   loading.
5. **Restore on failure.** Use `restore_file` when a backup exists. Use
   `restore_or_remove` when the original may have been absent so a failed
   creation does not leave a partial file. Reload PF after restoring
   `/etc/pf.conf`.
6. **Treat the root crontab specially.** Read it with `crontab -l` into a
   temporary file. Distinguish "no crontab for root" from a read error; never
   treat every failure as an empty crontab. Retain a backup at
   `/root/crontab.before-anacron.XXXXXX`. If installing the new crontab fails,
   restore the old crontab and the previous anacrontab.
7. **Back up `/etc/rc.conf.local` once** with `backup_rc_conf_once` before the
   first `rcctl enable`. It is modified by service enablement and is easy to
   overlook.
8. **Track temporary files.** Register every disposable `mktemp` path with
   `track_tmp`; the `EXIT` trap removes them. Never register retained backups.
9. **Do not hide failures.** Return nonzero when backup, validation,
   installation or activation fails. A declined optional task is success.
10. **Document limits.** Package installation, `rcctl` state and live `sysctl`
    changes are not transactionally rolled back. Say so in the README or skill
    output rather than implying a full transaction.

## Validation

- Trace every failure path from the failing command to the function return.
- Confirm the backup exists before the first mutation, not after it.
- Confirm restore commands check their own status and warn on failure.
- Confirm no message claims "restored" unless the restore command succeeded.
- Confirm created files have intended owner and mode, and restored files keep
  the backup's owner and mode.
- Confirm every temporary file is either tracked or intentionally retained.
- Check `git diff --check` and `git status --short`.

## Common problems

- Backing up after replacing the file, which preserves only the new content.
- Treating `BACKUP_PATH=""` as a valid backup when the original was absent.
- Using `crontab -l ... || : > file`, which can erase a root crontab after a
  transient read failure.
- Installing `/etc/anacrontab` before the root-crontab backup succeeds.
- Forgetting that `rcctl enable` changes `/etc/rc.conf.local`.
- Assuming `pkg_add` or a live `sysctl` change can be rolled back with a file
  copy.
- Registering a retained backup in `TMP_FILES` and deleting it on exit.
- Leaving partial config after a failed heredoc or failed second file install.
- Changing file modes unintentionally when installing or restoring.
- Commenting a compound cron line and silently disabling unrelated commands;
  the script leaves such lines unchanged and warns instead.
- Forgetting that a duplicate daily job remains when a compound line is left
  unchanged.

## References

- `../../../hardening.ksh` (`backup_file`, `restore_file`,
  `restore_or_remove`, `backup_rc_conf_once`, `configure_anacron`)
- `../../../AGENTS.md`
- `../../../README.md`
- OpenBSD `mktemp(1)`, `install(1)`, `cp(1)`, `crontab(1)`, `rcctl(8)` and
  `pfctl(8)` manual pages.

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
