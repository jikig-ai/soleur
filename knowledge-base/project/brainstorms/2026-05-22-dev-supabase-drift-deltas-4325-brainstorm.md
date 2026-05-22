---
date: 2026-05-22
issue: 4325
related_issues: [4338, 4241, 4230]
related_prs: [4339, 4354]
brand_survival_threshold: single-user incident
lane: cross-domain
tags: [database, migrations, supabase, ci, dev-environment, drift]
---

# Brainstorm: #4325 — dev-Supabase drift code deliverable

## TL;DR

Premise was stale. The drift-detection code deliverable shipped today as PR #4339 (closes #4338), which is the same broken-state instance #4325 reports. Path forward: ship a small delta bundle (probes default-on locally + FK-precondition lint + new forward migration for idempotency hardening), run the operator-paced dev recovery SQL from the learning runbook, then close #4325 as duplicate-class with proof.

## What We're Building

A four-part delta bundle on top of PR #4339's drift detection, plus an operator-task dev recovery:

1. **Delta 1 (operator-task, no code):** Execute Branch A from `2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md` against dev-Supabase. Verify partial-apply survivors via `pg_policies` + `pg_constraint` queries, `DELETE` 5 stale `_schema_migrations` rows (053/058/059/060/061), re-run `run-migrations.sh` to re-apply. Confirm tenant-integration goes green.
2. **Delta 2 (code):** CI lint that fails any new migration with a cross-file `REFERENCES public.<table>` lacking a `to_regclass` `RAISE EXCEPTION` precondition. Enforces the learning's Part-2 canonical shape as policy.
3. **Delta 3 (code, re-shape needed):** Idempotency hardening for the `CREATE POLICY` / `ADD CONSTRAINT` patterns the learning calls out as Branch-A stallers (mig 058: `attestations_select_for_members`, `workspace_members_attestation_id_fkey`; mig 060: `user_session_state_owner_select`). **Must NOT modify mig 058/060 in place** — that changes their `content_sha` and trips the #4241 drift probe. Two candidate shapes for plan-time decision: (a) forward-only migration 064 with `DROP IF EXISTS` guards on the surviving constructs; (b) helper convention (`idempotent_create_policy(...)` PL/pgSQL helper) for future migrations only.
4. **Delta 4 (code):** Flip `MIGRATION_SCHEMA_PRECONDITION_PROBE` default in `run-migrations.sh` from `0` to `1`. CI already sets it explicitly; this brings parity to operator-local invocations.

After deltas land: comment + close #4325 as duplicate-class of #4338.

## Why This Approach

PR #4339 implemented the four-part remediation (probe, preflight, scheduled drift cron, learning) called out in the post-mortem. The deliverable for #4325 narrows to:
- An *operator action* (run the documented recovery) — Delta 1
- *Hardening deltas* the post-mortem identified but did not bundle into #4339 — Deltas 2-4

Closing #4325 without deltas leaves the next operator one mistake away from re-introducing the drift class. The deltas turn "we have a runbook" into "the lint and default-on probe make the drift class harder to re-introduce."

## Key Decisions

| Decision | Rationale |
|---|---|
| Do NOT re-design drift detection | PR #4339 already shipped probe + preflight + cron + learning. Duplication is waste. |
| Delta 3 must be forward-only (mig 064) — NOT in-place edit of 058/060 | Modifying applied migrations breaks the #4241 content_sha drift probe by changing the file hash. The #4241 probe IS the load-bearing invariant we just shipped; do not regress it. |
| Default-on the probe locally (Delta 4) | CI is already protected (`MIGRATION_SCHEMA_PRECONDITION_PROBE: "1"` in `tenant-integration.yml`). Default-on locally closes the operator-workstation gap with one line. |
| Defer Delta 3 detailed shape to `/soleur:plan` | The forward-only vs. helper-convention choice has downstream consequences (file count, future-author training cost) that warrant the plan-skill's design phase. |
| Operator runs Delta 1 BEFORE PR merges | Recovery must succeed against dev independently of the PR. PR can land with the deltas regardless of recovery state; recovery proves the deltas don't regress the existing drift detection. |

## User-Brand Impact

**Threshold: single-user incident.** All four impact classes acknowledged by operator at Phase 0.1:

- **Silent prd schema/data corruption:** A future migration's apply could commit a tracking insert with body silently failing if `--single-transaction` discipline is broken. Mitigated by the probe (now default-on with Delta 4) + the FK-precondition lint (Delta 2) blocking the missing-relation class at PR time.
- **Cross-tenant RLS hole during recovery:** Branch A's `DELETE` chain re-applies workspace-keyed RLS migrations atomically; partial-apply survivors are pre-checked. Delta 3 closes the partial-apply stall risk.
- **Release deadlock / outage:** The scheduled drift probe (`scheduled-dev-migration-drift.yml`, 6-hourly) catches drift independent of PR cadence. Delta 4 widens that coverage to operator-local applies.
- **Dev-only blast radius:** Acknowledged but not relied upon — the drift class is reproducible on prd with the same write paths.

**Vector named:** non-runner writes to `_schema_migrations` (batched INSERT, dashboard UI, ad-hoc script). The learning's Prevention #1 names this as forbidden; no automated gate enforces it. Out of scope for this brainstorm — separate follow-up issue if desired.

## Open Questions

1. **Delta 3 shape (forward-only mig 064 vs. helper convention):** punt to `/soleur:plan` design phase.
2. **Should Delta 2's lint apply to existing migrations or only new ones?** Tentative: only new ones (`git diff origin/main...HEAD --name-only` filter). Existing 058/060/etc. are grandfathered; the lint is forward-protection.
3. **Order of Delta 1 vs PR merge:** Tentative: Delta 1 runs against dev *before* PR ready-for-review, so the green tenant-integration on this PR is the proof of recovery. Confirm at work-skill time.

## Domain Assessments

**Assessed:** None this brainstorm — prior-art discovery at Phase 1.1 short-circuited Phase 0.5 leader spawn. The premise was stale before leader assessment would have added value. CTO/CPO/CLO triad spawn deferred; if Delta 3 design at `/soleur:plan` time surfaces a brand-survival re-frame, the plan skill's Phase 2.6 carries forward the `single-user incident` threshold and the user-impact-reviewer agent fires at PR review.

## Capability Gaps

None identified. All deltas extend existing infrastructure (`run-migrations.sh`, `tenant-integration.yml`, the migrations directory). No new substrate needed.

## Session Errors

1. **Initial /soleur:go routing recommended one-shot for #4325.** Caller paused before worktree-creation to ask scope — the right call. The premise-staleness check inside brainstorm Phase 1.1 (reading `run-migrations.sh`, checking for #4338 + the learning file) is what surfaced the duplicate-class. One-shot would have produced a redundant PR. — Prevention: when a `/soleur:go #N` target is filed during a /work session on a sibling (`#4325` filed during #4230 work), grep for closely-dated sibling issues + their closing PRs before assuming the target needs a fresh deliverable.

## References

- Closing PR for sibling: #4339 (merged 2026-05-22 12:34 UTC)
- Sibling issue (same broken-state instance): #4338
- Filename-vs-main drift precedent: #4241
- Recovery runbook: `knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md`
- Adjacent learning: `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`
- Touched files (this PR): `apps/web-platform/scripts/run-migrations.sh`, `apps/web-platform/scripts/lint-migration-fk-preconditions.sh` (new), `apps/web-platform/scripts/run-migrations-schema-probe.test.sh`, `apps/web-platform/supabase/migrations/064_*.sql` (Delta 3, shape TBD), `.github/workflows/tenant-integration.yml` (lint wire-up)
