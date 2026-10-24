---
name: openbsd-ksh-maintenance
description: Maintain and review the interactive OpenBSD ksh hardening script, including function structure, prompts, logging, error propagation, and ksh portability.
---

# OpenBSD ksh maintenance

## When to use

Activate this skill when changing `hardening.ksh`: adding, removing or
reordering a hardening task; editing prompts, logging or error handling;
changing function-local state; or reviewing a patch for OpenBSD ksh
compatibility. Pair it with `safe-config-backup-and-rollback` for mutations and
`pf-rules-review` for firewall changes.

## Preconditions

- Read `AGENTS.md`, `README.md` and the complete `hardening.ksh` before editing.
- Inspect `git status` and `git diff` so existing user work is not overwritten.
- Confirm the change is workstation-scoped and is not a new server feature.
- Work statically. Do not execute the script or any privileged command.

## Procedure

1. Locate the relevant function and its call site in `main`. Preserve the
   existing order unless the change explicitly requires a different one. PF
   runs late so package installation still has network access.
2. Confirm that optional tasks remain independent. A failure or decline in one
   service prompt must not silently skip an unrelated prompt.
3. Keep the shared output contract: `[INFO] ` on stdout, `[WARN] ` and
   `[ERROR] ` on stderr, ASCII only, no color and no timestamps.
4. Use OpenBSD `/bin/ksh` constructs only: `print`, `[ ]`, `$(...)`,
   `typeset`, `read -r`. Avoid bash arrays, `local`, `[[ ]]`, `read -p`,
   process substitution and `set -e`.
5. Quote expansions. Use `mktemp` for temporary and backup names. Register
   temporary files with `track_tmp`; never register retained backups.
6. Make decline and failure status explicit:
   - `confirm ... || return 0` for a user decline;
   - `error ...; return 1` for a failed task;
   - accumulate independent failures in a local `status` variable and return it.
7. Do not follow `error` with a bare `return`; `error` already returns 1, but an
   explicit `return 1` documents intent and survives refactoring.
8. If behavior, prompts, backups or exit status change, update `README.md` and
   the architecture section of `AGENTS.md`.
9. Re-read the changed function from entry to every return path. Check that
   temporary files are either tracked or intentionally retained, and that no
   path claims success after a failed command.

## Validation

Static review is required and sufficient for repository work:

- Trace each `if`, `elif`, `else` and `return` for the intended status.
- Check every command substitution and variable expansion is quoted.
- Check heredocs: the opening command is guarded, the delimiter is quoted, and
  the terminator is on its own line.
- Check all new commands exist in OpenBSD base or the relevant package.
- Check `git diff --check` for whitespace errors and `git status --short` for
  unintended files.

When the user explicitly permits command execution, `ksh -n hardening.ksh` is a
syntax-only check and `shellcheck -s ksh hardening.ksh` is optional static
analysis. Neither proves runtime behavior. Never run the script itself as a
validation step.

## Common problems

- **Bare `return` after `error`:** hides failure if `error` changes.
- **Decline treated as failure:** `confirm ... || return` returns 1 when the
  user says no; use `return 0`.
- **Skipped sibling task:** `ensure_package tor || return` prevents the i2pd
  prompt; use a status accumulator.
- **Bashism:** `local`, `[[ ]]`, `echo -e`, `read -p`, arrays.
- **Unchecked heredoc:** a partial candidate can still pass a later parser.
- **Wrong ownership or mode:** installed files must state owner and mode.
- **Untracked temporary file:** leaks on normal exit.
- **Backup tracked as temporary:** gets deleted by the `EXIT` trap.
- **Line length:** the historical 72-column goal is not enforced; prioritize
  clarity and do not reflow unrelated lines.

## References

- `../../../AGENTS.md`
- `../../../hardening.ksh`
- `../../../README.md`
- `../../../LICENSE`
- OpenBSD `ksh(1)`, `sh(1)`, `mktemp(1)` and `install(1)` manual pages.
