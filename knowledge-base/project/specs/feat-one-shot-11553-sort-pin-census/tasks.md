# Tasks — feat-one-shot-11553-sort-pin-census

Plan: `knowledge-base/project/plans/2026-10-31-chore-followthroughs-events-ordering-pin-plan.md`
Issue: #11553 (deferred scope-out of PR #11543)

## Phase 1 — Probe pins

- [x] 1.1 `scripts/followthroughs/ac10-workspace-reconcile-sentry-4246.sh:55` — append `&sort=-timestamp` to the URL literal.
- [x] 1.2 `scripts/followthroughs/cron-machinery-soak-9272.sh:87` — append `&sort=-timestamp`; FIRST verify the `case "$URL" in` destination-pin glob is prefix-shaped (plan §Technical Considerations, spec-flow note a).
- [x] 1.3 `scripts/followthroughs/dashboard-cold-tiers-8978.sh:57` — append `&sort=-timestamp`.
- [x] 1.4 `scripts/followthroughs/egress-enforce-probe-11361.sh:44` — append `&sort=-timestamp` (URL is inline in the curl argv).
- [x] 1.5 `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh:68` — append `&sort=-timestamp`.
- [x] 1.6 `scripts/followthroughs/workspaces-luks-soak-6604.sh:71` — append `&sort=-timestamp`.
- [x] 1.7 `scripts/followthroughs/anthropic-admin-key-6297.sh` — comment above the `--data-urlencode 'statsPeriod=48h'` block: aggregate `field=count()` select, ordering meaningless, exempt under rule 6's function-field exemption; no param change.
- [x] 1.8 `scripts/followthroughs/anthropic-admin-key-6297.test.sh` — one characterization assertion pinning `field=count()` on the `/events/` invocation (the exemption basis).
- [x] 1.9 `sync-health-residual-5689.sh` — byte-untouched (out-of-scope `/issues/` call; AC6).

## Phase 2 — Lint rule 6

- [x] 2.1 `scripts/lint-followthrough-varq-ban.sh` — header index entry for RULE 6 naming the bound predicate, the `field=<name>()` aggregate exemption, the probe set, and the declared blind spots (non-continuation assembly, runtime-constructed endpoints, indirection-passed sort).
- [x] 2.2 Same file — RULE 6 body: per-probe backslash-continuation folding; executable-line `/events/` scan (full-line comments dropped); bound predicate `sort=` OR (`start=` AND `end=`) OR `field=<fn>()` with non-identifier left-edge matching (`(^|[^A-Za-z_])sort=`); violation cites the physical line where `/events/` matched; own counter `scanned_rule6` (counts examined hits incl. exempt); production floor ≥5 with its own exit-2 diagnostic naming rule 6.
- [x] 2.3 `scripts/lint-followthrough-varq-ban.test.sh` — R6-* rows covering every Guard Contract matrix row: R6-M1 dropped `&sort=-timestamp` (mirror fixture) → RED at true line; R6-M2 `end=` without `start=` → RED; R6-M3 guard copy with neutered `/events/` needle → exit 2 naming rule 6; R6-M4 second unbounded call after a compliant first → RED; R6-H1 must-PASS `start=`+`end=` no `sort=` → GREEN; R6-H2 must-PASS `field=count()` aggregate statsPeriod-only → GREEN; R6-H3 `/events/` in full-line comment → GREEN; R6-H4 `--data-urlencode 'sort=-timestamp'` folded curl -G → GREEN.
- [x] 2.4 `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — amend the "Pin an ordering" bullet to name rule 6 as the mechanical enforcer (shape: "Enforced as **rule 6** of `scripts/lint-followthrough-varq-ban.sh`"); keep the WHY paragraph; re-point or drop the "census of unpinned sibling probes" tail.

## Phase 3 — Verification

- [x] 3.1 `bash scripts/lint-followthrough-varq-ban.sh` (no arg) → exit 0, `scanned_rule6 >= 5`.
- [x] 3.2 `bash scripts/lint-followthrough-varq-ban.test.sh` → all rows pass incl. R6-*.
- [x] 3.3 Re-derived census: executable `/events/` lines under `scripts/followthroughs/` — every hit carries `sort=`, `start=`+`end=`, or `field=<fn>()` (no `| head` truncation on an absence claim).
- [x] 3.4 `bash -n` on every touched probe; run `scripts/test-all.sh --affected` suites: `scripts/followthrough-varq-ban`, `scripts/followthrough-varq-ban-live`, `anthropic-admin-key-6297.test.sh` suite. If `--affected` is lock-contended, run the named suites directly and record the substitution (per source-learning session error 3).
- [x] 3.5 `python3 scripts/lint-guard-contract.py <plan>` green; `npx markdownlint-cli2` on edited docs if in hook path.

## Deviation (work phase, 2026-10-31)

- `dispatch-recovery-sweeper-11211.sh` — plan classified it "already bounded"; its `/events/` literal and `start=`/`end=` live on SEPARATE statements (the lint's declared blind spot). Inlined the bound into each `/events/` logical line (SENTRY_BASE/TAIL split removed; `[mut:*]` anchors kept). Suite + live lint green.
- 3.4 ran the named suites directly: `lint-followthrough-varq-ban.test.sh` (204/0) + live lint (exit 0, scanned_rule6=16); `anthropic-admin-key-6297.test.sh` delegated to ship-phase affected run.
