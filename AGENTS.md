# AGENTS.md

## Project scope

This repository contains one interactive OpenBSD **workstation** hardening
script, `hardening.ksh`, plus user documentation. It is not a server, router,
bridge, VPN or container hardening tool. Keep recommendations and code changes
inside that scope unless the user explicitly asks for a different target.

## Layout

- `hardening.ksh` - the complete interactive workflow. It must run as root on
  OpenBSD and accepts no arguments.
- `README.md` - user-facing behavior, supported operations and excluded
  practices.
- `LICENSE` - ISC-style license. Preserve the copyright and permission notice.
- `.agents/skills/` - task-specific procedures linked at the end of this file.

There is no project build system, package manifest, or application test
suite. The dedicated PR workflow runs only the read-only agent-validation
contract tests and range gate; no project CI checks are configured.

## Architecture

`main` runs, in order: platform/root checks, privacy services (Tor/i2pd),
ClamAV, anacron, `wxallowed` removal, malloc auditing, PF, then `finish`.
PF runs late so that package installation still has working networking.

Each task is a function guarded by its own confirmation prompts. Shared helpers
are `log`, `warn`, `error`, `confirm`, `backup_file`, `restore_file`,
`restore_or_remove`, `backup_rc_conf_once`, `ensure_package`, `track_tmp` and
`cleanup_tmp`. Mutating tasks must:

1. back up an existing target before replacing it;
2. generate candidate content in a tracked `mktemp` file;
3. validate the candidate where a validator exists;
4. install it with explicit owner and mode;
5. restore the previous file content if installation or candidate validation
   fails. Package, service and live kernel state are not transactional.

Temporary files are tracked in `TMP_FILES` and removed by an `EXIT` trap.
Backups are retained intentionally. PF is validated with `pfctl -nf`, compared
after installation, and restored and reloaded on installation, load or enable
failure. The root crontab has a separate retained backup in `/root`.

## Conventions

- Target OpenBSD `/bin/ksh`; do not introduce bashisms or rely on Linux tools.
- Use tabs for block indentation, ASCII only, and no ANSI colors, emoji or
  timestamps in output.
- Log with exactly `[INFO] `, `[WARN] ` (stderr) or `[ERROR] ` (stderr).
- Use `snake_case` function names, `typeset` for function-local variables, and
  quote variable expansions.
- Do not add `set -e`. Handle each failure explicitly.
- `confirm` defaults to no. Declined work returns success (`return 0`); failed
  work returns nonzero (`return 1`).
- `error` returns 1. Do not follow it with a bare `return`, which can hide the
  failure; return explicitly.
- Keep independent optional tasks independent: a failed Tor step must not skip
  the i2pd prompt, and a failed ClamAV service must not abort other tasks.
- Prefer small, reviewable changes over rewrites. Update `README.md` whenever
  user-visible behavior, prompts, backups or failure handling changes.
- Never reintroduce the obsolete practices listed in `README.md`.

## Commands

There is no project build step or application test suite. The shared agent
validator tests live in `tests/agent_knowledge_validator/`; do not invent
project build or test targets.

Static analysis (does not execute the hardening workflow):

```sh
ksh -n hardening.ksh
shellcheck -s ksh hardening.ksh
git diff --check
git status --short
git diff
```

`ksh -n` checks syntax only; it does not validate PF, service or filesystem
semantics. `shellcheck` is optional and has no repository configuration.
Read-only `git` commands are the review tools.

Real verification requires a disposable OpenBSD workstation, root access and
explicit user approval. It is not an agent task. Never run `hardening.ksh`,
`pfctl -f`, `pfctl -e`, `pkg_add`, `rcctl enable/start`,
`sysctl vm.malloc_conf=...`, `crontab`, `mount`, `reboot`, or writes under
`/etc` and `/root` while working on this repository. `pfctl -nf` is parse-only
but privileged; run it only when the user explicitly authorizes it on a
disposable host.

## Safety policy

- Default to static review and fixture-based reasoning. Do not execute
  privileged, interactive or destructive commands.
- Do not install packages, modify services, change PF, remount filesystems or
  edit system configuration as part of repository work.
- Do not commit, amend, push, tag or rewrite history unless explicitly asked.
- Treat uncommitted or untracked files as user work. Inspect `git status` and
  the relevant diff before editing; do not revert or overwrite unrelated
  changes. If a change conflicts with user work, stop and ask.
- Preserve `/etc` content: backups use unique `.hardening.XXXXXX` names next to
  the target and must remain restorable. Never delete a backup unless the user
  asks.
- Do not add obsolete or unsupported advice such as `kern.wxallowed`,
  `mount -a` as a remount, `schg` on base files, firmware-host blocking,
  MD5-crypt users, patched `sysupgrade`/`syspatch`, X11 replacement, blanket USB
  disabling or unattended upgrades.

## Skills

Load the relevant skill before changing the corresponding area:

- [openbsd-ksh-maintenance](.agents/skills/openbsd-ksh-maintenance/SKILL.md) -
  editing the ksh script, functions, prompts, logging and exit status.
- [pf-rules-review](.agents/skills/pf-rules-review/SKILL.md) - reviewing the PF
  candidate, DHCP/ICMPv6 rules, `pfctl` sequence and rollback.
- [openbsd-system-hardening](.agents/skills/openbsd-system-hardening/SKILL.md) -
  evaluating `wxallowed`, malloc auditing, ClamAV, Tor/i2pd and anacron advice.
- [safe-config-backup-and-rollback](.agents/skills/safe-config-backup-and-rollback/SKILL.md) -
  adding or reviewing backups, temporary files and restoration paths.
- [openbsd-dry-run-and-review](.agents/skills/openbsd-dry-run-and-review/SKILL.md) -
  reviewing or "testing" changes without executing the workflow.

## GitHub Actions pin maintenance

`.github/workflows/agent-knowledge-validation.yml` pins every external action
to an immutable 40-character commit SHA; tags and branches are not acceptable.
Update a pin only after verifying the release SHA, and change the `uses:` line
and its trailing `# vX.Y.Z` comment together. Do not change triggers,
permissions, concurrency, job names, or commands while updating a pin.

| Action | Version | Commit SHA |
| --- | --- | --- |
| `actions/checkout` | `v7.0.1` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/upload-artifact` | `v7.0.2` | `cf430e030ddbb5b0abf93d22962f4752f3646cd9` |
| `actions/cache` | `v6.1.0` | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` |
| `actions/setup-java` | `v6.2.0` | `77dd5b2ce225ea11469928ac317850245a74ae78` |
| `actions/setup-node` | `v7.1.0` | `949feb2413d6458794dcd2491c4babbbce0c15c1` |

Validate a workflow edit with `actionlint .github/workflows/*.yml` and, when a
`yamllint` configuration exists, `yamllint -c <config> .github/workflows`.

## Continuous Agent & Skills Maintenance

Every repository change MUST trigger an Agent & Skills Maintenance Review.
Agent instructions and skills are living repository artifacts. Before
completing any repository modification, review all applicable `AGENTS.md`
files, specialized agents, and `SKILL.md` files. Update the affected knowledge
artifacts to reflect the implementation, correct outdated instructions, and
incorporate reusable knowledge. A task is incomplete until knowledge
synchronization has been performed and validated. Never skip synchronization
silently or claim that unexecuted checks have passed.

After each change:

1. Identify and review the applicable agents and skills, even when no update
   initially appears necessary.
2. Update relevant operational guidance, reusable procedures, references,
   commands, and paths; remove stale or contradictory instructions.
3. Do not use whitespace-only, timestamp-only, empty, or otherwise cosmetic
   edits to satisfy synchronization. For a project change, at least one
   relevant knowledge artifact must receive a substantive update.
4. Run `perl scripts/validate-agent-knowledge.pl --scope worktree` and the
   applicable project checks. For a pull request, CI compares the base and head
   revisions with `--scope range --base BASE_SHA --head HEAD_SHA`.
5. Review the validator output and final diff, then report the synchronization
   result. Warnings require human review; a structural pass does not establish
   semantic relevance.

Run the validator tests with
`prove tests/agent_knowledge_validator/test_validator.pl`.
The validator is read-only and uses Perl 5.14+ (JSON::PP core) and the standard library. It
must not be confused with project-specific validation or installation tools.
See [Agent Knowledge Validation Contract](docs/agent-knowledge-validation.md)
for AK001–AK006, JSON schema, exit codes, configuration, and maintenance rules.

All repositories must implement the same Agent Knowledge Validation CLI
contract, rule identifiers, output conventions and exit codes. Repository-
specific validations may extend the canonical behavior but must not silently
redefine it. Any change to the validator contract must be reflected in the
repository's agent instructions, related skills and tests.
