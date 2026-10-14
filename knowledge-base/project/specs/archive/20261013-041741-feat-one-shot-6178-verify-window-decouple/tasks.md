---
feature: inngest-verify-window-anchor
issue: 6178
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-24-fix-inngest-verify-window-decouple-plan.md
pr: 6933
revision: 2
---

# Tasks: `op=verify` scan window + trust anchor (#6178)

> v2 after a 7-agent plan-review panel. Registry-sourced missed-tick discovery is CUT to a
> follow-up (operator-confirmed). Do NOT close #6178 and do NOT delete Hetzner image 411798619.
>
> **Correct test paths** (v1 named a nonexistent directory):
> - `apps/web-platform/infra/inngest-doublefire-probe.test.sh` — CI `infra-validation.yml:641`
> - `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — CI `infra-validation.yml:656`
> Do NOT create files under `tests/scripts/infra/` — nothing runs them.

## Phase 0 — Measure before coding (STOP gate) — ✅ DONE 2026-07-24, run 30121678305
- [x] 0.1 Set `CUTOVER_WINDOW_UNTIL = now + 199d` → `DF_FROM ≈ now − 1d`; dispatched
      `op=doublefire-probe`. **Result: 728 runs in a 1-day window, scan completed in 34 s.**
- [x] 0.2 `gh variable delete CUTOVER_WINDOW_UNTIL`; repo variable count re-verified **0**.
- [x] 0.3 Measurement recorded in the plan (§ Phase 0 RESULT). Satisfies AC1.
- [x] 0.4 STOP GATE passed — a narrow window IS exhaustible; diagnosis confirmed.
- [x] 0.5 `INNGEST_GQL_PAGE_SIZE=500` s/page — still unmeasured; the hook plumbs only
      `from` + `function_ids`. Record as unmeasured with the reason, or thread the env.

**Two findings that change Phases 1–2 (do not skip):**
- **Density: ~728 runs/day.** 200 d ≈ 145,600 runs ≈ 1,456 pages. Affordable at 90 s ≈ 18 pages
  ≈ ~2.5 days (shipped divisor 5 s/page, 4.2 rounded up for headroom). **A 7-day fallback is NOT exhaustible** — the floor is `1 d`, and an underivable
  anchor must FAIL CLOSED rather than scan a window that cannot finish.
- **Second defect, blocks the fix:** the bucketing `jq` dies on a null `startedAt`
  (`fromdateiso8601` → `strptime/1 requires string inputs`, exit 5). Reproduced. Narrowing the
  window alone would move the failure from `reason=deadline` to a jq crash.

## Phase 1 — Probe: `totalCount` + page-1 feasibility gate
- [x] 1.1 RED: reshape `make_page` to take an explicit `totalCount` arg (it currently hardcodes
      `totalCount:($edges|length)`, so `totalCount` can never exceed the page's edge count); update
      its existing call sites.
- [x] 1.2 RED: assert emitted object + `_TIMEOUT` marker carry `total_count`; a pre-page-1 abort
      emits `total_count=unknown` (never empty, never `0`); `totalCount` over budget aborts on page 1.
- [x] 1.3 GREEN: parse `.data.runs.totalCount` from page 1.
- [x] 1.4 GREEN: page-1 feasibility gate — compute affordable runs from the measured budget; abort
      with the numbers inline and a COMPUTED remediation naming the latest viable anchor.
- [x] 1.5 Correct both FATAL remediation strings AND the header's `raise PREFLIGHT_DEADLINE_S`
      phrasing (v1's `increase`-only grep missed it). Target: `(increase|raise|bump)` count == 0.
- [x] 1.6 Update the header's RESIDUAL LIMITATION + `window ⊇ …` paragraphs — they currently assert
      "the time WINDOW is NEVER narrowed", which this PR makes false.

## Phase 2 — Workflow: anchor derivation + min() floor + fail-closed
- [x] 2.1 RED: build an **execute-and-assert** harness for `doublefire_from()` in
      `cutover-inngest-workflow.test.sh`. Precedent: `call_build_request_body` +
      `test_df_build_body_harness_is_live` in the probe suite. Do NOT grep — extract and run.
- [x] 2.2 RED: table — FSM-derived / var-set / var-malformed / all-unset × `CRON_PERIOD` {1200, 3600};
      assert exact ISO output.
- [x] 2.3 GREEN: rewrite `doublefire_from()`:
      `DF_FROM = min( bucket_floor(anchor) − 2×CRON_PERIOD , now − FALLBACK )`
      where `bucket_floor(x) = x_epoch / CRON_PERIOD * CRON_PERIOD`.
- [x] 2.4 GREEN: anchor precedence `fsm | var | floor`; emit `anchor_source=` for off-box visibility.
- [x] 2.5 GREEN: FSM derivation via the existing `confirm_flip_state()` plumbing. Extract ONLY the
      `dt` field (the function's contract is "NEVER echoes a raw row") + add a purity test.
      Retention miss ⇒ per-branch ::warning::, fall through to CUTOVER_WINDOW_FROM, then FAIL CLOSED (never a wide window).
- [x] 2.6 GREEN: per-arm fallback passed as `$1` — `op=doublefire-probe` (`:292`) keeps 200 d;
      only `op=verify` (`:1198`) narrows. Assert both in the test.
- [x] 2.7 GREEN: read `${CUTOVER_CRON_PERIOD_SECONDS:-3600}` directly, not the caller-local
      `CRON_PERIOD` ambient global.
- [x] 2.8 GREEN: drop v1's `DOUBLEFIRE_FALLBACK_DAYS` knob entirely — use a literal. (An unmapped
      env var would be a fifth instance of the very bug class this file already documents twice.)
- [x] 2.9 GREEN: fail-closed — abort unless `DF_FROM` matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}T`.
      Note `date -u -d ''` SUCCEEDS (returns today's midnight), so a non-empty guard is required.
      Remove v1's tautological "DF_FROM precedes CUTOVER_WINDOW_FROM" comparison.
- [x] 2.10 GREEN: assert `DF_URL` carries no `until` parameter + rationale comment (post-repoint and
      post-rollback coexistence regions lie AFTER `CUTOVER_WINDOW_UNTIL`).
- [x] 2.11 RED: fixture with a `startedAt: null` run → bucketing must NOT exit 5.
- [x] 2.12 GREEN: null-safe bucketing via `select(.startedAt != null)` in **BOTH** the `op=verify`
      arm and the `op=doublefire-probe` arm, AND in the missed-tick `OBSERVED` expression (same
      construct). Emit the dropped count as a `::notice::` — a silent drop is the false-clean shape
      this gate exists to prevent. A run with no `startedAt` has not fired, so it cannot double-fire.
- [x] 2.13 GREEN: `FALLBACK_DAYS = 1` (not 7 — Phase 0 measured 7 d as non-exhaustible); an
      underivable anchor FAILS CLOSED rather than scanning a window that cannot complete.

## Phase 3 — Docs + deferred work
- [x] 3.1 Amend ADR-106 `## Decision` item 4: ⊇ restatement; `2×max_cron_period` was the
      function-discovery term; recall trade recorded; open-topped invariant; `timeField: STARTED_AT`
      coupling; re-anchor the stale `:704-743` cross-reference by content.
- [x] 3.2 Author `ADR-146-trust-anchor-for-cutover-coexistence-window.md` (`amends: ADR-106`).
      Ordinal is PROVISIONAL — re-verify at ship; a renumber must sweep plan + tasks + ACs.
- [x] 3.3 Runbook `inngest-server.md` §2.6: two windows, anchor sources, `cron_period_seconds=1200`.
- [x] 3.4 File deferred issues: (a) registry-sourced discovery w/ the second scoped query design;
      (b) missed-tick emits a nonexistent command + fires for never-due crons — interim de-fang via
      a `workflow_dispatch` input defaulting off; (c) `CUTOVER_REGISTRY_BASELINE` +
      `CUTOVER_QUIESCE_PROBES` mapping + anchored guard, to land AFTER AC-V4 is green;
      (d) #6178 triage is stale (`priority/p2-medium` / `Post-MVP / Later`).

## Phase 4 — Verify + ship
- [x] 4.1 `bash apps/web-platform/infra/inngest-doublefire-probe.test.sh`
- [x] 4.2 `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`
- [x] 4.3 AC6 demonstration: mutate `doublefire_from()` to return empty → suite FAILS; revert.
      Record both outputs in the PR body.
- [x] 4.4 Confirm every AC's measured baseline still matches (see plan § Acceptance Criteria).
- [ ] 4.5 `/review` → `/qa` (if the structural gate fires) → `/compound` → `/ship`.

## Exit
- [ ] PR body: `Ref #6178` (NOT `Closes`). Note the probe is a WEB-host script delivered in-place by
      `apply-deploy-pipeline-fix` on merge — not on the dedicated host, no host replace, #6780 N/A.
- [ ] Post-merge: AC-V1 (delivery sha256) MUST pass before AC-V2 dispatches — different concurrency
      groups, nothing serializes them; a premature dispatch lets the OLD probe answer.
- [ ] AC-V2 `gh workflow run cutover-inngest.yml -f op=verify -f cron_period_seconds=1200`.
- [ ] AC-V3 non-vacuity, then AC-V4 verdict split:
      deadline ⇒ failed, open, snapshot retained · DOUBLE-FIRE ⇒ **incident**, open, snapshot
      retained · VERIFIED + non-vacuous ⇒ #6178 eligible to close, image 411798619 eligible to delete.
