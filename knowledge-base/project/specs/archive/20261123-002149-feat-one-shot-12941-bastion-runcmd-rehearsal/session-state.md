# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-20-feat-bastion-runcmd-rehearsal-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- PreToolUse hook blocked first plan Write on systemctl words; resolved with iac-routing-ack marker.
- plan-sharp-edges catalogue read by keyword, not in full.
- Deepen corrected three false claims (job gates merges; -b scopes container boots; offline fixture covers stub routing).

### Decisions
- Real cloud-init boots in privileged systemd containers with host containment (CTO Q1, Q13, Q21).
- Template fixes: install systemd-timesyncd (FAULT-A); real failure reason from both services' logs (FAULT-B).
- 9 boots in 3 waves, 780 s in-suite deadline, 18-min job (CTO Q14).
- Dedicated advisory bastion-boot-rehearsal job, out of shards and main-health-monitor (CTO Q6, Q16, Q20, Q22).
- CI: at most 2 skipped rows, healthy row never skips (CTO Q17, Q23).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto (Q1-Q24), terraform-architect, repo-research-analyst, learnings-researcher, best-practices-researcher, functional-discovery, dhh/kieran/simplicity/security/test-design reviewers.

## Overlap
- post-plan re-probe: SOLEUR_OVERLAP exit=13 prs=6778,9745,12932,12964 (shared files only, continue).

## Operator Constraints

- constraint: Never SSH, never read a live secret, no production dispatch without the owner's typed go naming the exact command.
- cto_spawns=0 (main context; planning subagent's CTO rounds were inside plan)
## Work Phase
- Status: complete (c98b4ae411). Suite RED on unfixed template (B1 egress_load "User does not exist"; F1 boilerplate detail), PASS 87/0 cold 335 s and warm 230 s on fixed template.
- Committed-state gates rc 0: infra registration, guard-vacuity-floor, lint-orphan, fixture-relative/dir-operand, apt-bounded, aggregator diagnosis, bastion.test.sh. c4-count-parity rc 0.
- Affected gate: selected 366 of 771; queued on the sibling-held test-all lock at 12:42Z (log /var/tmp/brh-gates/gate.log).
- #12942 comment posted (Checks API gate on bastion-boot-rehearsal).
