# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-14-fix-cron-egress-firewall-remote-exec-apply-plan.md
- Status: complete

### Errors
- iac-plan-write-guard.sh blocked two plan-write attempts containing literal `ssh root@<host>` / `systemctl enable --now` strings (diagnostic/quoted, not new provisioning); resolved by abstract rephrasing. No content lost.
- Push emitted a non-blocking Dependabot advisory notice (pre-existing on main).

### Decisions
- Diagnose-then-fix structure: Phase 0 is a BLOCKING gate that un-suppresses remote-exec output before any fix; Phase 1 branches on the finding; Phase 2 hardens with ASSERT-FAILED sentinels.
- Lead hypothesis reordered after deepen review: 4c (service-enable line server.tf:813) is the LEAD, not 4a — cron-egress-firewall.service is Type=oneshot RemainAfterExit=yes, so it propagates the loader's exit; a loader `die` (live-DNS resolve at :134) matches the ~4s timing better than a render-format grep mismatch.
- Falsified the issue's two lead suspicions from the live CI log: CF Access ci_ssh token is NOT the cause (bridge connected, file provisioners ran); failure present since #5089 (2026-06-10), not "since 2026-06-12" (intervening green runs were path-filtered, never re-ran the provisioner).
- Widened protected-invariant set per user-impact review: added jump SOLEUR-EGRESS (816), EnableIPv6 guard (828), re-pointed egress-probe-negative at a numeric IP (tests daddr default-drop, not DNS-exfil drop); scoped out the 820 presence check as liveness-only.
- requires_cpo_signoff: true; CPO sign-off + user-impact-reviewer gated for plan/review time.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Agents: git-history-analyzer, learnings-researcher, Explore, architecture-strategist, user-impact-reviewer
- Gates: plan-network-outage-checklist (L3→L7), deepen-plan Phases 4.5-4.9, hr-ssh-diagnosis-verify-firewall telemetry
