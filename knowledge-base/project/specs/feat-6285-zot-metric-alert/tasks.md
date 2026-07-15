---
title: Tasks — zot mirror-fallback alarm threshold fix
issue: 6285
branch: feat-6285-zot-metric-alert
pr: 6424
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-15-fix-zot-fallback-alarm-unreachable-threshold-plan.md
---

# Tasks — #6285

Plan: `knowledge-base/project/plans/2026-07-15-fix-zot-fallback-alarm-unreachable-threshold-plan.md`

> **Order is load-bearing.** 1.1 (the test) must land with or before 1.2 (the value), or CI is red
> and nothing downstream runs. v1 of this plan missed that and was unmergeable.

## Phase 1 — The fix

- [ ] **1.1** `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`
  - [ ] `:68` `expect(scoped).toMatch(/value\s*=\s*3/)` → `/value\s*=\s*0/`
  - [ ] `:10`, `:59` — update the `>3 / 1h` prose to fire-on-first
- [ ] **1.2** `apps/web-platform/infra/sentry/issue-alerts.tf:1380` — `value = 3` → `value = 0`
  - [ ] Do **not** touch `frequency = 23` (`:1374`) or `ignore_changes = [environment]` (`:1428`)

## Phase 2 — Correct the comment (`issue-alerts.tf:1326-1367`)

Remove all four false statements (see the plan's table): `:1326` ">3 in 1h" · `:1331`
"load-bearing at Phase-5" (inverted) · `:1343` "many hosts → SAME group" (**this produced `3`**) ·
`:1346-1350` metric-alert rejection ("CI-only token", "tracked as a follow-up") · `:1352-1362`
per-signal asymmetry note (moot at `value = 0`).

- [ ] **2.1** Write mechanism → invariant → sibling-contrast → change-trigger (plan §Changes 2)
- [ ] **2.2** **No host count in the comment** — state the invariant (`value = 0` is the only
      fleet-independent setting). A count rots the day web-3 lands; that is how the original rotted.
- [ ] **2.3** Contrast `web_terminal_boot_fatal:1462` (`value = 1` works only because its group is
      never new) so nobody normalizes this rule to match it
- [ ] **2.4** Do **not** claim `frequency = 23` throttles re-notification here — false for this
      rule's fresh-per-deploy grouping

## Phase 3 — Tripwire at the 5.3 removal site

- [ ] **3.1** `apps/web-platform/infra/ci-deploy.sh:857-871` — one comment: removing this branch
      (ADR-096 task 5.3) darkens 3 of 4 signals; retire the alarm in the same PR;
      `zot_gate_degraded_event` (`:630`) survives (gate, not pull path)

## Phase 4 — ADR-096

- [ ] **4.1** `:103-106` — window **opens** when `ZOT_REGISTRY_URL` is set in Doppler `prd` (task
      1.8), **not** at the `ZOT_ACTIVE=1` flip; **closes at 5.3 for 3 of 4 signals**
      (`zot-gate-degraded` survives); threshold is `value = 0`, matching the soak's zero tolerance
- [ ] **4.2** Drop "deferred to #6285"
- [ ] **4.3** Sweep the stale ">3/1h" at `:90` and `:101`

## Phase 5 — Verify (pre-merge)

- [ ] **5.1** AC1-AC3 (source + comment) — all three fail pre-fix today; that is the point
- [ ] **5.2** AC4 `cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` → 5 pass
- [ ] **5.3** AC5 `terraform init -backend=false && terraform validate` (deprecation warning is expected)
- [ ] **5.4** AC6-AC8 (ADR, `-target` survives, no guard-artifact drift — three-dot diff)
- [ ] **5.5** AC9 — `Ref #6285` in the PR body, **not** `Closes`

## Phase 6 — Post-merge (automated)

- [ ] **6.1** AC10 — live rule: `.conditions[0].value == 0` **and** `.actions` non-empty (read-only)
- [ ] **6.2** AC11 — live-fire: synthetic `registry:"zot-gate-degraded"` +
      `zot_gate_reason: "synthetic_ac_probe_6285"` → alarm fires. Safe: not counted by any of the
      soak's four queries, pre-cutover so outside the window, cannot inflate the zot sample.
- [ ] **6.3** AC12 — `gh issue close 6285`

## Out of scope (filed)

#6435 soak blind to 2 of 4 signals (**higher value than this fix**) · #6436 Sentry unmodeled in C4 ·
#6437 Doppler-less silent fallback · #6429 sibling `sandbox_startup_failure` · #6427 retargeted
(5.3 must retire/re-point the soak) · #4656 comment (`N=1` premise falsified)
