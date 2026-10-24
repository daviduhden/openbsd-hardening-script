---
name: openbsd-dry-run-and-review
description: Review or "test" changes to this OpenBSD hardening repository by static analysis, without executing the interactive script or any privileged system command.
---

# OpenBSD dry run and review

## When to use

Activate this skill when the user asks to test, dry-run, validate, verify or
review the repository; before approving a change to `hardening.ksh`; or whenever
a proposed verification step would touch PF, packages, services, `/etc`,
crontabs or the running kernel.

## Preconditions

- Read `AGENTS.md`, `README.md` and the complete `hardening.ksh`.
- Inspect `git status` and `git diff` first. Treat uncommitted work as the
  user's.
- Default to no execution. This repository's workflow is interactive, requires
  root and mutates the system.

## Procedure

1. **Classify the requested verification.** State clearly which level applies:
   - static analysis: reading code, rules and docs;
   - syntax check: `ksh -n`, which parses but does not execute;
   - build: none exists in this repository;
   - test suite: none exists;
   - real verification: a disposable OpenBSD workstation with root and explicit
     approval.
2. **Map the change to functions.** Identify the affected task, helpers, prompts,
   backup paths, validators, rollback paths and README claims.
3. **Review control flow statically.** Check declines return 0, failures return
   nonzero, independent tasks continue, temporary files are tracked, and no
   success message follows a failed command.
4. **Review sensitive content statically.** For PF, inspect rule order and
   direction, DHCP/ICMPv6 exceptions and `pfctl` sequencing. For `awk`
   transformations, reason about comments, field boundaries and output format.
   For crontabs, check duplicate suppression and restore behavior.
5. **Check documentation and links.** Verify that `AGENTS.md` and every
   `SKILL.md` path exists, frontmatter has `name` and `description`, skill names
   match directory names, and README claims match code.
6. **Use read-only repository checks:** `git diff --check`, `git status
   --short`, `git diff`, and `git ls-files`. These do not execute the hardening
   workflow.
7. **Do not run the workflow.** Never run `hardening.ksh`, `pfctl -f`,
   `pfctl -e`, `pkg_add`, `rcctl`, `sysctl vm.malloc_conf=...`, `crontab`,
   `mount`, `reboot`, or writes under `/etc` or `/root`.
8. **Report the gap.** If real verification was not performed, say so and list
   what remains unverified. Do not describe static review as a runtime test.

## Validation

- Check YAML frontmatter by inspection: delimiters, `name`, `description`,
  indentation and plain-scalar safety.
- Check every relative link and referenced path from the repository root.
- Check headings, activation conditions, procedure, validation, common issues
  and references are present in each skill.
- Check `git diff --check` and review the final diff for unintended edits.
- Check that no command in documentation claims a build or test target that does
  not exist.
- If the user authorizes a syntax check, run only `ksh -n hardening.ksh`; it does
  not execute prompts or mutations. `pfctl -nf` remains privileged and is not
  part of ordinary review.

## Common problems

- Running `hardening.ksh` as root "just to see the prompts"; it mutates `/etc`.
- Treating `ksh -n` as proof that PF rules, `rcctl` calls or `awk` output are
  correct.
- Using Linux `ksh`, `pfctl`, `pkg_add` or `rcctl` behavior as authoritative.
- Calling `pfctl -nf` harmless because it is parse-only; it still requires
  privileges and a suitable host.
- Forgetting that package installation and live `sysctl` changes are not rolled
  back by file restoration.
- Testing on a production workstation instead of a disposable OpenBSD host.
- Reporting a documentation-only review as a functional test.

## References

- `../../../AGENTS.md`
- `../../../README.md`
- `../../../hardening.ksh`
- `../../../.agents/skills/openbsd-ksh-maintenance/SKILL.md`
- `../../../.agents/skills/pf-rules-review/SKILL.md`
- `../../../.agents/skills/safe-config-backup-and-rollback/SKILL.md`
