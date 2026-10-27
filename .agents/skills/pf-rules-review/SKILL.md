---
name: pf-rules-review
description: Review the workstation PF candidate, DHCP and ICMPv6 exceptions, pfctl validation and load sequence, and rollback behavior without changing live firewall state.
---

# PF rules review

## When to use

Activate this skill when editing the PF heredoc, prompts, `pfctl` sequence,
firewall rollback, or README claims about firewall behavior. Also use it when a
review question concerns default-deny policy, outbound state, DHCP, IPv6 control
traffic or custom anchors.

## Preconditions

- The target is an outbound-only OpenBSD workstation, not a server, router,
  bridge, VPN gateway or host with custom anchors.
- Read the `configure_firewall` function, `restore_pf`, `README.md` and the PF
  references before judging a rule.
- Do not run `pfctl -f` or `pfctl -e` while reviewing. Do not change live PF.

## Procedure

1. Read the candidate exactly as written in the heredoc. Check the order:
   `set skip on lo`, `block return`, explicit quick DHCP exceptions, `pass out`,
   then the ICMPv6 exception block. PF is last-match unless a rule is `quick`.
2. Confirm loopback is intentionally skipped and therefore unfiltered.
3. Confirm `block return` is the default policy. Remember that it sends TCP RST
   or ICMP unreachable rather than dropping silently.
4. Confirm `pass out` is stateful by default and admits replies to outbound
   connections. It is not egress filtering: every outbound destination is
   allowed.
5. Verify the DHCP exceptions cover client traffic in both directions:
   - DHCPv4 client `68` to server `67` and the reply `67` to `68`;
   - DHCPv6 client `546` to server `547` and the reply `547` to `546`.
   Broadcast replies do not reliably match outbound state, so the inbound
   `quick` rules are required. The script does not configure a DHCP server.
6. Verify the ICMPv6 types cover unreachable, packet-too-big, time-exceeded,
   parameter-problem, router solicitation/advertisement and neighbour
   solicitation/advertisement. Do not claim this admits every ICMPv6 type.
7. Verify the sequence:
   - write the candidate to a tracked `mktemp` file;
   - run `pfctl -nf` on the candidate before replacing `/etc/pf.conf`;
   - back up the existing file;
   - install with root ownership and mode 600;
   - compare the installed file with the candidate;
   - load with `pfctl -f`, then enable with `pfctl -e` if needed;
   - restore and reload the previous file on mismatch, load failure or enable
     failure.
8. Check that a missing previous `/etc/pf.conf` cannot produce a false claim of
   restoration. The current code reports that manual review is required.
9. Check the `pf=NO` warning in `/etc/rc.conf` and `/etc/rc.conf.local`; loading
   a ruleset at runtime does not override boot-time disablement.
10. Confirm `README.md` still says the policy is for workstations and does not
    promise server, router, VPN or anchor support.

## Validation

- Static rule review against `pf.conf(5)` and `pfctl(8)`.
- Check every rule for direction, address family, protocol, ports and `quick`.
- Check that no rule relies on a non-existent service name.
- Check that the candidate is validated before the installed file is replaced.
- Check every failure path for a restore attempt and an honest error message.
- `pfctl -nf` is parse-only but privileged. Run it only with explicit user
  approval on a disposable OpenBSD host. Never run `pfctl -f` or `pfctl -e` as
  part of repository review.

## Common problems

- Omitting DHCP exceptions and breaking lease renewal on a workstation.
- Assuming outbound state covers broadcast DHCP replies.
- Treating `pass out` as egress filtering.
- Forgetting that `block return` is not a silent drop.
- Adding `quick` rules after a broader `pass` and expecting them to win.
- Replacing a host with custom anchors and losing those rules.
- Claiming all IPv6 works because a subset of ICMPv6 is admitted.
- Reporting success after `pfctl -e` fails.
- Rolling back only on `pfctl -f` failure but not on installation mismatch or
  enablement failure.
- Forgetting that reloading rules does not flush existing PF state; old flows
  may continue to pass traffic.
- Testing connectivity only by a successful `pfctl -f`; a syntactically valid
  policy can still be operationally wrong.

## References

- `../../../hardening.ksh` (`configure_firewall`, `restore_pf`)
- `../../../README.md`
- `../../../AGENTS.md`
- [pf.conf(5)](https://man.openbsd.org/pf.conf.5)
- [pfctl(8)](https://man.openbsd.org/pfctl.8)

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
