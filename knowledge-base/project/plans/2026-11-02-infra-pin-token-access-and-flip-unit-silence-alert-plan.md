---
title: "infra: pin token access in the Inngest replace gate and alert when the flip unit goes silent"
date: 2026-11-02
slug: pin-token-access-and-flip-unit-silence-alert
branch: feat-one-shot-11831-11820-flip-token-gate-alert
issue: 11831
closes: [11831]
refs: [11820, 9927]
lane: single-domain
type: infra
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
---

# infra: pin token access in the Inngest replace gate and alert when the flip unit goes silent

## Overview

Two deferred follow-ups of the flip-token split, shipped as one change at the owner's instruction (Batch A of the CTO ruling of 2026-11-02: neither touches `user_data`, so neither forces a host replace).

1. **#11831 — gate pin.** The Inngest host-replace gate (`tests/scripts/lib/inngest-host-replace-gate.sh`) judges the ACTION on the two Doppler token addresses (`doppler_token_touched`) but never the `access` level. Add a counter that requires `after.access == "read/write"` for `doppler_service_token.inngest_flip` and `== "read"` for `doppler_service_token.inngest` on any plan entry that creates the token. A flip token minted `read`, or a boot token left `read/write`, then aborts before any apply instead of surfacing as repeated `unexpected-exit(from=flushed)` rows after `op=resume`.
2. **#11820 — silence alert.** Add one Better Stack Logs alert, `inngest_cutover_flip_silent`, that emails when no JSON `inngest-cutover-flip` row arrives from the production Inngest host for 15 minutes. It covers the three failure arms in #11820's scope that share the cause "the flip unit is not running to completion". Replace-window suppression is NOT part of this change (see CTO ruling); #11820 stays open for it.

Nothing here dispatches `apply_target=inngest-host-replace`, writes to Hetzner or Doppler, or changes `user_data`.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue text) | Reality (origin/main, 2026-11-02) | Plan response |
|---|---|---|
| #11831: the gate lives at `tests/scripts/lib/inngest-host-replace-gate.sh` | Confirmed; counter block at the `doppler_token_touched` jq expression and a reason chain at the file's tail | Add `doppler_token_access_wrong` beside it |
| #11831: existing synthetic token rows use an empty `after` | Confirmed: `rc_obj` emits `{"address","change":{"actions":[...]}}` with no `after` | New helper `tok_obj` carries `after.access`; every token row that creates gets it |
| #11831: runbook step 1 says neither gate reads `.after` | Confirmed at the "Flip-token split" first-replace step 1 | Reword: the gate now pins `access`; the owner's read of the two lines stays as a cheap pre-go cross-check |
| #11820: scheduled alert query keyed on a bare tag would count the doppler error line | Measured by the CTO ruling (read-only Better Stack query): flip rows have an object-typed `message` (about 12/h), doppler lines a string `message` (about 160/h) | Discriminate with `JSONType(raw,'message') = 'Object'`, not a string pattern |
| #11820: merging creates a live alert via the per-merge apply | Confirmed: `logtail_exploration*` resources join the explicit `-target` list in `apply-web-platform-infra.yml` | Add both targets; email-only, like `egress_gw_probe_silent` |

## Research Insights

**Premise validation (Phase 0.6).** #11831 and #11820 are OPEN, no linked or body-referencing PR other than the originating merged flip-token PR (a citation, not a collision). No open PR touches the planned files (`pr-overlap-preflight.sh` exit 0). Both ruling inputs held: `access` is a configured literal in `inngest-host.tf` (lines 284 `read`, 311 `read/write`), so it is present in `.change.after` at plan time even on a first replace.

**Property List (Phase 0.6b).**
- P1: a replace plan that would mint the flip token without `read/write`, or the boot token without `read`, aborts before apply.
- P2: a missing or unreadable `after.access` on a created token also aborts (fail closed).
- P3: a token that is only a no-op on this plan is not judged (the pin applies to creation).
- P4: a page-class signal exists when the flip unit stops emitting its JSON liveness row from the production host.
- P5: the signal does not fire in production today.

**Cut List.**
- Replace-window suppression in the alert query: a logs query cannot express it; it belongs to the #11266 feeder dead-man (CTO ruling). Cut, and #11820 stays open.
- A paging (push/call) channel: the precedent `egress_gw_probe_silent` is email-only; cut.
- Reading `before.access` for drift: out of scope; the gate judges the plan's `after`.
- A new terraform-target-parity entry: `terraform-target-parity.test.ts` covers `terraform_data`, not logtail alerts; the per-resource guard owns the `-target` presence (the sibling pattern).

**CTO ruling.** Ruled by CTO agent, 2026-11-02: Option A. Alert `inngest_cutover_flip_silent` (display name `soleur-inngest-cutover-flip-silent-prd`), threshold `lower_than 1`, check 300 s, query 900 s, confirmation 0, recovery 900 s, `treat_as_zero`, email only. Query keyed on `SYSLOG_IDENTIFIER='inngest-cutover-flip'`, `host_name='soleur-inngest-prd'`, `JSONType(raw,'message')='Object'`, `dt` column, one aggregate with no GROUP BY. PR body says `Closes #11831` and `Ref #11820`. Measured: 1,891 object rows over 7 days, no gap over 900 s, so it does not fire now. Evidence limit: `JSONType` is verified through `betterstack-query.sh` only; if the alert evaluator rejects it the per-merge apply fails and the fix is a revert.

**Conventions applied.** Read files by merge SHA (`origin/main`), not local main. `gh issue create` as its own call with `--body-file`. Monitor, not background, for polling. Run the repo-global ratchets before pushing.

## Open Code-Review Overlap

Two open code-review issues name `.github/workflows/infra-validation.yml`: #8735 (cancelled-job failure notice) and #7942 (two mutation batteries named `*.mutation.sh` run in no gate). Acknowledge both: different concerns, this plan adds one blocking test step and neither issue's scope. They remain open.

## Files to Edit

- `tests/scripts/lib/inngest-host-replace-gate.sh` — new counter `doppler_token_access_wrong`, PASS conjunct, reason token, header comment, ABORT-line text.
- `tests/scripts/test-inngest-host-replace-gate.sh` — `tok_obj` helper; `after.access` on every creating token row; new rows for both wrong-access shapes, a missing-access row, no-op rows, and mutation rows.
- `apps/web-platform/infra/betterstack-logs-alerts.tf` — local `inngest_cutover_flip_silent_sql`, `logtail_exploration.inngest_cutover_flip_silent`, `logtail_exploration_alert.inngest_cutover_flip_silent`, with a comment block naming what it covers, what it does not, and the expected firing during an owner-authorized replace.
- `.github/workflows/apply-web-platform-infra.yml` — two `-target` lines beside the `web_nic_guard_unpinned_url` pair.
- `.github/workflows/infra-validation.yml` — blocking step for the new alert test, beside the `web-nic-guard-unpinned-url-alert` step, plus `knowledge-base/engineering/operations/runbooks/inngest-server.md` and the new test file in `pull_request` paths (the sibling adds its runbook there).
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` — exploration count anchor `17` becomes `18` (grep for the anchor; do not trust the line number).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — "Flip-token split" first-replace step 1 sentence (the gate now pins `access`), the "What an agent may verify" bullet (3), and one line that the new alert emails during an authorized replace and clears at the first post-boot `noop-*` row.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — standing-alarms table bullet for the new alert.
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` — one append-only addendum line: the gate pin and the silence alert shipped (no `## Decision` edit). The separate ADR-218 alert-list line is cut (plan review, taste: a second doc for the same fact).
- `scripts/ci-pr-affected-audit.accept.tsv` — the accept row for the known `affected-index-ratchet` finding (anchor `ef13fc106737/1`), per the owner's resume brief of 2026-11-02; cite the finding by its content anchor in the row's reason text, not by the test file's line number, and copy the exact column shape from a neighbouring row.

## Files to Create

- `apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh` — drift guard modelled on `web-nic-guard-unpinned-url-alert.test.sh` (emitter needle read from the emitting script, whole-predicate compare, paging semantics, `-target` presence, runbook and standing-alarms presence, mutation rows on copies).

## Implementation Phases

### Phase 1 — gate pin (#11831), tests first
1. In `test-inngest-host-replace-gate.sh` add `tok_obj <addr> <actions> <access>` and re-point every row whose token action includes `create` at it with the correct access. Redefining the shared constants `TOKEN_REPLACE`, `FLIP_CREATE` and `FLIP_REPLACE` fixes T1, T1b, T1d, T1e and T1h at once; then handle the inline rows (T1n, T1o, T1o2, T1o3 and any other found by `grep -n "doppler_service_token" tests/scripts/test-inngest-host-replace-gate.sh`). Add a second helper `expect_access_abort` (the existing `expect_token_abort` hard-codes `reason=doppler_token_touched`). Run the suite: all prior rows still PASS.
2. Add the new rows RED first: flip `create` with `read` aborts; flip `delete,create` with `read` aborts; boot `delete,create` with `read/write` aborts; flip with `after` absent aborts; flip with `access` absent aborts; boot `create` with `read` passes; flip `create` with `read/write` passes; a no-op boot token with NO `after` passes (P3). Each abort row asserts `reason=doppler_token_access`. Add a wiring twin of the existing `T1r` row asserting the new counter appears inside the `plan_gate_assert_numeric` call.
3. Implement the counter in the gate, in the same jq object as `doppler_token_touched`; add the `local` name (gate line 100 declaration), a `dta=$(echo "$counts" | jq -r '.doppler_token_access_wrong')` line, the `plan_gate_assert_numeric` argument, the `echo` counter line, the PASS conjunction, and the reason chain directly after `doppler_token_touched`. Fail closed: `(.change.after.access? // "") != $want`.
4. Run the whole gate suite, `shellcheck`, and the grep for every other consumer of the counter line (`doppler_token_touched` appears only in the gate, its test, the runbook and ADR-282, so no parser consumes the echoed line).

### Phase 2 — silence alert (#11820), tests first
0. FIRST read the emitting script (`apps/web-platform/infra/inngest-cutover-flip.sh`) so the test pins the real `noop-*` JSON emitter and its throttle period, not a retyped needle, and so the 900 s window is checked against the real cadence. Record in the alert's comment block the maximum gap the read-only query shows (`scripts/betterstack-query.sh` through Doppler `prd_terraform`, never printing row content) next to the 900 s window, so the headroom is visible.
1. Create the new alert test against the not-yet-existing resources (RED). Keep its mutation rows to what the sibling tests do (predicate, `-target` presence, runbook and standing-alarms presence); the structure and ceiling suites already cover the channel settings.
2. Add the SQL local, exploration and alert to `betterstack-logs-alerts.tf`, then the two `-target` lines (inside the contiguous logtail block, after the `web_nic_guard_unpinned_url` pair and before the `random_password.inngest_redis_luks` line), the infra-validation step, the count anchor bump, and the docs lines. The exploration must use the exact `    values        = [local.vector_prd_source_id]` form the count anchor matches, or the count stays at 17. Update the stale comment above the `== 17` anchor (the word, the number and the contributor list) in the same edit. Run `betterstack-alert-structure.test.sh`, `logs-alert-query-period-ceiling.test.sh`, `betterstack-send-failed-alert-mutation.test.sh`, `terraform fmt -check` and `terraform validate` where available, and fix what reds (the structure test may classify alerts; follow its pattern).
3. `JSONType` is the first use in this repo (every sibling uses `JSONExtractString`). The CTO ruling keeps it; the PR body states the blast radius: an evaluator rejection fails the per-merge apply until the change is reverted.

### Phase 3 — docs, ratchets, accept row
1. Runbook, ADR addendum, log-query bullet, accept row.
2. Run the repo-global ratchets a file-selected run cannot see: `grep-q-pipe-guard`, `PJ_TRIPLES` (this PR adds no `grep -q` pipeline rows, so it should not move; if it does, read the value from the file at commit time), suite-shard-legs parity, fixture-relative-assert, capture lint. `BASELINE_DECLARED_PROBES`: this PR declares no probe, so it must not touch it; if a ratchet says otherwise, rebase and read the file value.

## Guard Contract

### Guard 1 — access pin in the Inngest replace gate

**Property.** No plan that creates `doppler_service_token.inngest_flip` with an `access` other than `read/write`, or `doppler_service_token.inngest` with an `access` other than `read`, passes the replace gate; an unreadable `after.access` counts as wrong.

**Assembly.** The population is every `resource_changes` entry whose address is one of the two token addresses AND whose `actions` array contains `create` (`["create"]`, `["delete","create"]`, `["create","delete"]`); the single chokepoint is the `doppler_token_access_wrong` jq counter in `inngest_host_replace_gate`, which is the only function the `inngest_host_replace` workflow job and the suite call. The expected access is derived from the address in one jq `if`, so adding a third token address to the allow-set without an access mapping fails closed (empty expected value never equals a real access). Members are not enumerated by hand: the jq selects by `IN(.address; ...)` over the same two-address list that `doppler_token_touched` uses.

**Mutation matrix.**

| # | Mutation | Must go RED |
|---|---|---|
| M1 | Flip token planned `create` with `access: "read"` | gate ABORT `reason=doppler_token_access` |
| M2 | Boot token planned `["delete","create"]` with `access: "read/write"` | ABORT `reason=doppler_token_access` |
| M3 | Remove the new conjunct from the PASS condition in a COPY of the gate | the M1 plan wrongly passes, so the suite's mutation row reds |
| M4 | Flip token planned `create` with `after` absent entirely | ABORT (fail closed) |
| M5 | Make the access mapping wrong for the flip address in a COPY (expected `read` instead of `read/write`) | the canonical flip-token PASS rows red |

The address-to-access mapping in the gate must sit on a line the existing T1h `sed '/"doppler_service_token\.inngest_flip"/d'` cannot match (select the flip token with `endswith("_flip")` or equivalent, never a second quoted literal of the full address), or T1h would abort on a jq parse error and pass for the wrong reason.

**Harness rows.** (a) Edit the SUITE, not the gate: delete the `read/write` PASS row for the flip token in a copy of the test and assert the suite's own anti-vacuity pass-count floor (the literal expected count near the end of `test-inngest-host-replace-gate.sh`) reds; the floor's literal moves with this change and is part of the diff. (b) Must-PASS inputs that are NOT the canonical: a flip token `["create","delete"]` with `read/write` (the other replace order), and a boot token that is `no-op` with no `after` at all.

**Anchor.** The expected strings live in the gate and in `inngest-host.tf` (lines `access = "read"` and `access = "read/write"`); a diff that edits both would agree with itself. The independent anchor is the runbook's owner pre-go read of the two literals at the dispatch SHA, which stays in step 1 as a cross-check, and the ADR-282 build record, which names the access of each token.

## Infrastructure (IaC)

### Terraform changes
`apps/web-platform/infra/betterstack-logs-alerts.tf` gains one local, one `logtail_exploration` and one `logtail_exploration_alert`; no new provider, no new variable, no secret. The source is `local.vector_prd_source_id` as for the siblings. Added to the per-merge apply `-target` list (two lines).

### Apply path
(a) Per-merge `apply` job creates the alert on merge. No host replace, no cloud-init change, no downtime. Blast radius: one Better Stack alert and its exploration; an evaluator rejection fails the per-merge apply and is reverted (disclosed in the PR body).

### Host fan-out
No `terraform_data` SSH provisioner is touched.

### Distinctness / drift safeguards
The alert names `soleur-inngest-cutover-flip-silent-prd` (prd only; dev has no Inngest host in this root). `host_name` is pinned to `soleur-inngest-prd`, so a dev or web-class host cannot satisfy it.

### Vendor-tier reality check
Query window 900 s is within the ceiling every alert since 2026-10-01 uses; `logs-alert-query-period-ceiling.test.sh` enforces it. Escalation uses the same free/paid ternary as the siblings.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly: a mis-tuned gate counter would abort a future owner-authorized replace (a delay, not a loss), and a mis-tuned alert would send one extra email to the owner. Neither changes runtime behavior of the scheduler.
**If this leaks, the user's data is exposed via:** no new exposure vector: the gate reads plan JSON that already omits token values, and the alert query selects counts of rows, not content.
**Brand-survival threshold:** aggregate pattern.

## Observability

```yaml
liveness_signal:
  what: JSON inngest-cutover-flip row count from soleur-inngest-prd in the last 15 minutes (Better Stack)
  cadence: check every 300 s, window 900 s
  alert_target: owner email via the Better Stack team policy (email-only, critical_alert=false)
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf (logtail_exploration_alert.inngest_cutover_flip_silent)
error_reporting:
  destination: Better Stack alert incident; the apply job log if the evaluator rejects the query
  fail_loud: true
failure_modes:
  - mode: flip unit fails at the Doppler CLI (revoked or invalid flip token) so no JSON row is written
    detection: row count drops to 0 in the 900 s window
    alert_route: email
  - mode: boot-time flip-file write abort stops runcmd so the unit never starts
    detection: same silence
    alert_route: email
  - mode: Vector stops shipping the tag
    detection: same silence
    alert_route: email
logs:
  where: Better Stack source soleur-vector-prd, SYSLOG_IDENTIFIER inngest-cutover-flip
  retention: the source's configured retention
discoverability_test:
  command: bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh
  expected_output: "0 failed"
```

## Acceptance Criteria

- [ ] AC1: Gate aborts with `reason=doppler_token_access` for flip-token create with `read`, boot-token replace with `read/write`, and a created token with no `after.access`. Pointer: `tests/scripts/lib/inngest-host-replace-gate.sh` (counter beside `doppler_token_touched`), `tests/scripts/test-inngest-host-replace-gate.sh`.
- [ ] AC2: Gate still passes the existing shapes (first replace, flip rotation, no-op boot token without `after`).
- [ ] AC3: `bash tests/scripts/test-inngest-host-replace-gate.sh` and `shellcheck` on both files are green; the mutation rows M3 and M5 go RED when applied to copies, and T1h still fails for the intended reason (the mutation lands on the `def allow` line only).
- [ ] AC4: `logtail_exploration.inngest_cutover_flip_silent` and its alert exist with the CTO-ruled settings; both `-target` lines are in `apply-web-platform-infra.yml` (`betterstack-logs-alerts.tf`, `apply-web-platform-infra.yml`).
- [ ] AC5: The new alert test, `betterstack-alert-structure.test.sh`, `logs-alert-query-period-ceiling.test.sh` and `betterstack-send-failed-alert-mutation.test.sh` (count 18) are green, and `infra-validation.yml` runs the new test in a blocking step.
- [ ] AC6: Runbook step 1 and bullet (3) no longer say the gate does not read `.after`; the replace-window email expectation is stated once in the runbook and once in the alert's `incident_cause`.
- [ ] AC7: ADR-282 gains one append-only addendum line (0 removed lines in its diff); `betterstack-log-query.md` names the alert.
- [ ] AC8: The repo-global ratchets (grep-q-pipe-guard, PJ_TRIPLES, suite-shard-legs parity, fixture-relative-assert, capture lint) are green before the first push; `affected-index-ratchet` has the accept row.
- [ ] AC9: PR body says `Closes #11831` and `Ref #11820`, names what remains for #11820 (replace-window suppression via the #11266 feeder dead-man), and states that the alert will email during an owner-authorized replace and that a rejected `JSONType` query would fail the per-merge apply and be reverted.
- [ ] AC10: No change to `user_data`, `cloud-init*.yml` or `inngest-host.tf`; `inngest-userdata-budget.sh --cap-only` is untouched and green.

## Domain Review

**Domains relevant:** engineering

### Engineering
**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-11-02 (design of the alert, PR-body wording, companion-file list). No product, marketing, legal or finance surface: no user-facing page, copy, personal data or spend.

## Test Scenarios

- Gate suite: every row of AC1 and AC2, plus M3 and M4 as mutation rows.
- Alert guard: predicate equals the string built from the emitter's own needle; no negation; no extra `host_name` beyond the pinned one; settings match the CTO ruling; targets present; mutation rows on copies for each.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or lacks the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- Do not re-derive the `JSONType` discriminator: it was measured by the CTO ruling and is not exercised by any in-repo test beyond the string compare, so say so in the alert's comment block.
- `betterstack-send-failed-alert-mutation.test.sh` counts explorations by an exact anchor; a second new exploration anywhere would need the count to move again.
- The gate fixture rows are synthesized (`cq-test-fixtures-synthesized-only`); no captured real plan.
