---
title: "Tasks — restore Better Stack ingest and make refusal alarm"
branch: feat-one-shot-7569-registry-log-channel-dark
plan: knowledge-base/project/plans/2026-08-16-fix-betterstack-ingest-quota-exhaustion-plan.md
issue: 7569
lane: cross-domain
---

# Tasks

Derived from `2026-08-16-fix-betterstack-ingest-quota-exhaustion-plan.md`. Phase order is
dependency-directed; Phase 0 is time-critical.

## Phase 0 — Snapshot evidence before it ages out

- [ ] 0.1 Dump per-day counts, per-producer counts, message-shape distribution, hourly cliff, and
      bytes/row to `knowledge-base/project/specs/<branch>/evidence-snapshot.md` and commit.
      **Deadline ~2026-08-17 19:07Z** — irreversible if missed.
- [x] 0.2 Re-probe the ingest endpoint; record HTTP status and timestamp.
- [x] 0.3 Re-derive the ADR ordinal, scoped to `refs/remotes/origin` (local `refs/backup/*` are
      not claims).
- [x] 0.4 Re-verify the Sentry PAYG cap state (#3958) — it may be at cap, in which case this
      guard has no working backstop.

## Phase 1 — Reuse the existing absence taxonomy

- [x] 1.1 Read `scripts/betterstack-assert-absence.sh` in full.
- [x] 1.2 Extract its four-outcome discriminator into `scripts/lib/betterstack-absence.sh`
      without changing semantics; add the `SELECT max(dt)` freshness helper.
- [x] 1.3 RED: write the Guard 1 mutation matrix (7 rows) + harness rows H1/H2 in
      `tests/scripts/test-betterstack-absence-classifier.sh`.
- [x] 1.4 GREEN: route both absence arms in `scripts/zot-restart-loop-alarm.sh` through the shared
      helper (`git grep -n 'control_rc'` finds both); split the `||` collapse at each.
- [ ] 1.5 Fail closed when the 24h lookback is empty (today it routes to the "fresh host"
      non-alarming arm — the state this outage produces once the cliff ages out).
- [x] 1.6 Add the anti-vacuity floor (a guard evaluating zero arms must not exit 0).
- [ ] 1.7 Point `scripts/betterstack-assert-absence.sh` at the extracted helper — one
      implementation, not two.
- [x] 1.8 Do **not** modify `scripts/betterstack-query.sh`; record the measured exit codes
      (22 / 6 / 0 / 3) in the PR body as the correction to #7569's premise.

## Phase 2 — Ingest probe as cause annotation only

- [x] 2.1 Measure whether an empty-batch POST (`[]`, `{}`) returns 402 when quota-exhausted and
      202 otherwise. Record the result; it decides the design.
- [x] 2.2 Implement `scripts/betterstack-ingest-probe.sh` + classification tests (2xx/402/401/
      5xx/unreachable).
- [x] 2.3 If the probe writes a row, exclude its marker from the control query and assert that
      coupling with a test (self-masking guard).
- [x] 2.4 Ensure the probe has no veto over the reader-derived verdict.

## Phase 3 — Alarm wiring

- [x] 3.1 File `[ci/betterstack-ingest-dark]` with `action-required`, reusing the existing
      `[ci/zot-telemetry-silent]` dedupe-by-title shape.
- [x] 3.2 Extend the Sentry check-in status mapping.
- [ ] 3.3 Verify the Sentry path actually reaches a person; if an errored check-in does not open
      an issue, add an N-consecutive escalation in the alarm itself.

## Phase 4 — Volume reduction at the structural chokepoint

- [ ] 4.0 **L3 precondition.** Editing `vector.toml` re-fires `terraform_data.journald_persistent`
      (`apps/web-platform/infra/server.tf:982-991`), which reaches `web-1:22` over an SSH
      provisioner. Confirm the CI/operator egress IP is in `var.admin_ips` BEFORE the apply. A
      handshake reset is admin-IP drift → `/soleur:admin-ip-refresh`, never an sshd fault.
- [ ] 4.1 Bound the `parse_err != null → true` arm at `apps/web-platform/infra/vector.toml:83`.
- [ ] 4.2 Add a `throttle` transform keyed on container/`SYSLOG_IDENTIFIER` ahead of
      `[sinks.betterstack]` (line 543).
- [ ] 4.3 `vector validate` on the pinned 0.43.1; PII parity suite 26/26.
- [ ] 4.4 CI grep asserting `[sinks.betterstack].inputs` reads only from throttled transforms
      (invariant I-1).
- [ ] 4.5 Declare per-emitter budgets in `scripts/betterstack-emitter-ceilings.json`,
      **denominated in GB/month, not rows/day**.
- [ ] 4.6 Write the Guard 2 mutation matrix (6 rows) + harness rows.
- [ ] 4.7 Re-denominate `scripts/followthroughs/betterstack-quota-verdict-5105.sh` from
      25k rows/day to a byte budget.
- [ ] 4.8 Rate-cap `resolve-origin` — treat as a **security control** (an unauthenticated third
      party's write handle on the vendor bill), not tidy-up. Note edge-runtime counters are
      per-isolate; prefer the Vector-side bound as the real fix.

## Phase 5 — Blast-radius sweep

- [ ] 5.1 Classify all 63 `betterstack-query.sh` consumers as presence-assert vs absence-assert;
      commit the table.
- [ ] 5.2 Route absence-asserts through the freshness precondition so they return **unresolved,
      not passed**. Start with `.github/workflows/inngest-config-drift.yml` and
      `.github/workflows/reusable-release.yml`.
- [ ] 5.3 Scope any remainder to a tracked follow-up; the classification itself lands here.

## Phase 6 — ADR, PIR, C4

- [x] 6.1 Write the ADR (`status: adopting`) with invariants I-1 and I-2, and the explicit
      rejection of source-splitting.
- [ ] 6.2 File the PIR via `soleur:incident`; cite and close the 2026-06-10 near-miss
      postmortem's 5-Why #5 action item rather than restating it.
- [x] 6.3 Re-prioritise **#5134** `vendor-quota-watch`, re-denominated in GB/mo.
- [ ] 6.4 Correct the `betterstack` system description and the `github -> betterstack` edge in
      `knowledge-base/engineering/architecture/diagrams/model.c4`.
- [ ] 6.5 Run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [ ] 6.6 Enroll `scripts/followthroughs/betterstack-ingest-7569.sh` on a **dedicated** tracker,
      never on #7569.

## Phase 7 — Restoration and close

- [ ] 7.1 Confirm steady-state volume against the 3 GB/month allowance.
- [ ] 7.2 Address the current period's consumed allowance per the operations advisory. Preserve
      source id 2457081, `table_name`, and region eu-fsn-3 — capture before and after.
- [ ] 7.3 Assert restoration by a 2xx from the ingest endpoint, never a dashboard figure.
- [ ] 7.4 Capture the free acceptance evidence: the new matrix returns a dark verdict against prod
      today, and GREEN after restoration.
- [ ] 7.5 Confirm rows resume for every declared producer.
- [ ] 7.6 Close #7569; comment the unblock on #7556 and #7555; cross-reference #7462.

## Ship-time gates

- [ ] Recurring-vendor-expense gate will fire (the PR body contains "upgrade"). Choose one of the
      three exits; **headless aborts on all three — run ship interactively.**
- [ ] Fix the two pre-existing `knowledge-base/operations/expenses.md` defects (Responder rate
      note; line 44 row/day → GB/mo denomination).
- [ ] If a paid tier is chosen, refresh `knowledge-base/finance/cost-model.md` (+12.58% COGS;
      break-even 5→6 and 14→15 users) — CFO decision.
- [ ] `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own
      invocation, not a hand-enumerated path list).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] Re-derive the ADR ordinal against freshly-fetched origin refs immediately before merge.

## Disposition at /work exit (2026-08-16)

Checked boxes above were verified individually, not bulk-toggled. What did NOT land, and why —
recorded here rather than left as silently-unchecked boxes:

- **0.1 evidence-snapshot.md — CUT, per review finding R22.** The repo is PUBLIC, so a verbatim
  dump of log rows is a permanent egress. The measurements live in ADR-187 and in the #7577
  body as counts and byte totals, never as captured rows.
- **1.5 / 1.7** — the "fresh host" arm and pointing `betterstack-assert-absence.sh` at the
  shared helper. Deferred: both change the semantics of a second consumer, and the primary
  detector is complete and mutation-proven without them. The `any-row` / `marker` split in
  ADR-187 is the seam they land on.
- **Phase 4 (volume reduction), Phase 5 (blast-radius sweep)** → **#7577**. Split at the
  infra-apply seam on review recommendation R29.
- **Phase 6.2 (PIR), 6.4-6.5 (C4), 6.6 (soak enrollment)** — not started.
- **Phase 7 (restoration)** — blocked on an account-level billing action that no code change
  can perform. Tracked on #7569 itself.
- **R7's detector gap** → **#7578**. The AP-021 linter never saw the false message at all; a
  bounded widening measures 30 hits across unrelated subsystems.
