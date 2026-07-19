# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-19-fix-workspaces-luks-freeze-quiesce-redis-g4-canary-plan.md
- Status: complete

### Errors
- IaC write-guard blocked the plan write twice. The hook flags `systemctl` verbs in plan prose; here they are program logic inside the automated cutover script, not operator SSH steps. First ack attempt failed because the `<!-- iac-routing-ack -->` comment was placed before the YAML frontmatter; the hook honors it only in the body. Diagnosed by testing the hook directly, then resolved. No other errors.

### Decisions
- All 4 briefed claims confirmed at source — freeze quiesce set (`workspaces-cutover.sh:461-462`), G4's `command -v lsof` skip (`:471`), canary URL vs `middleware.ts:113`, and the `DRY_RUN` gating that makes C1 unreachable in a rehearsal. Claim 3 is stronger than briefed: there is no `/api/health` route at all.
- Found two additional G4 defects; fix #2 alone would have shipped a still-broken gate. `lsof … | grep -q .` under `set -uo pipefail` returns 141 on large output, so `&& die` never fires — the gate fails OPEN precisely when many stragglers exist. G4 also logs no holders, reproducing the undiagnosable-abort failure just fixed. Plan adds `ensure_lsof` delivery (`lsof` is provisioned by no repo artifact) plus a dry-run advisory holder probe.
- Three restore sites, not the two briefed. The dead-man timer is the unattended path; omitting it leaves the durable Inngest queue down with no operator signal.
- Reversed a round-1 decision at deepen: `inngest-server` is NOT quiesced. Its unit is `ProtectSystem=strict` with `ReadWritePaths=/var/lib/inngest /var/lock` — it provably cannot write `/mnt/data` — and carries `TimeoutStopSec=180`, costing up to 3 min of a ~10 min freeze for zero benefit. Replaced with a zero-cost post-freeze reconcile.
- ADR-119 addendum is in-scope, not deferred (`wg-architecture-decision-is-a-plan-deliverable`). `ADR-119:73` already prescribes `lsof +D`, so fix #2 restores ADR conformance rather than changing a decision.

### Components Invoked
- Skill: soleur:plan, Skill: soleur:deepen-plan
- Agent: general-purpose (test-harness shape, CI registration contract, learnings, ADR-119)
- Deepen gates: 4.4 precedent-diff, 4.55 Downtime & Cutover (fired), 4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped, 4.9 UI-wireframe (skipped)
- Verification: gh issue/pr view (7 citations), AGENTS.md rule-ID sweep, KB path resolution, empirical pipefail/SIGPIPE reproduction

### Work-phase prerequisite flagged by planning
The freeze block sits BELOW the script's sourced-detection guard, so it is currently untestable. Extracting `freeze_writers()` / `resume_writers()` / `app_canary()` above that guard is a prerequisite for behavioral tests — without it only static greps are possible, which cannot catch the ordering and exit-status defects this PR fixes.
