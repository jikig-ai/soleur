---
title: "chore: remove the obsolete cron-gh-pages-cert-state routine and its Sentry monitor"
type: chore
date: 2026-09-30
slug: remove-obsolete-gh-pages-cert-state-cron-and-sentry-monitor
branch: feat-one-shot-remove-gh-pages-cert-state
issue: 9304
closes: 7711
lane: cross-domain
priority: p3-low
domain: engineering
brand_survival_threshold: none
---

# chore: remove the obsolete cron-gh-pages-cert-state routine and its Sentry monitor

## Enhancement Summary

**Deepened on:** 2026-09-30
**Verification passes run:** deepen-plan halt gates 4.6 (user-brand impact), 4.7 (observability), 4.8 (PAT shapes), 4.9/4.11 (no UI surface, no guard deliverable: skipped), 4.10 (skipped: deletion only, no store or connection introduced); live check of every cited issue/PR state; rule-id existence; probe-verb gate and shell-active-byte scan on the `discoverability_test.command`; plus the plan-review panel (DHH, Kieran, code-simplicity, CTO devex lens) and the CTO/CLO/learnings passes recorded under Research Insights.

### Key improvements over the first draft

1. The two-PR rule (#8630) was found and drives the whole shape; the brief's file list (`issue-alerts.tf`) and counts (55/11/44) were corrected against the tree (60/16/44).
2. An opaque-id consumer the name-keyed grep cannot see was found: the #6178 dedicated-host soak probe pins 52 function UUIDs and refuses on any missing one unless it is in `RETIRED_IDS`. Handled with one post-deploy registry-vs-population comparison, not a pre-merge guess.
3. Review findings applied: acceptance grep patterns corrected to the real hit set, the RED step reworded to what actually goes red (registry count only), the `discoverability_test` made a positive, rc-0, shell-active-free probe, and PR B's hand-off made self-contained on tracker #9304.

### Verified in this pass

- Cited state: #9304, #7711, #7799, #8595, #6178, #8714 OPEN; #4650, #8630, #6589, #7640 CLOSED; #9071 MERGED (the `RETIRED_IDS` precedent; its test row `C0e` in `inngest-soak-6178.test.sh` is the pattern PR B mirrors — that suite runs longer than two minutes, so run it in the background).
- The soak population file has exactly 52 non-comment lines (82 total with the header).
- `probe-verb-gate.sh` accepts the declared probe (`grep`); it contains none of `| ; & < > $` or a backtick.

## Overview

The daily GitHub Pages certificate poll (`cron-gh-pages-cert-state`) and its Sentry cron monitor
(`scheduled-gh-pages-cert-state`) measure an origin certificate that ADR-194 deliberately abandoned
when the marketing site moved to Cloudflare Pages (cutover completed 2026-09-03). The monitor is
already `enabled = false` and is the only Sentry cron monitor that is not active. This change
removes the routine, its test and its wiring, and deletes the monitor through the repo's Terraform
CI apply path.

**Delivery is two PRs, not one** — this is the load-bearing planning finding (see Research
Reconciliation row 4). The Sentry root's own README (`apps/web-platform/infra/sentry/README.md`,
"Adding or removing a cron monitor — the two-PR rule (#8630)") forbids an unroute and a delete in
one apply:

| PR | Branch | Carries | Needs `[ack-destroy]` |
|---|---|---|---|
| **PR A** (this branch) | `feat-one-shot-remove-gh-pages-cert-state` | function + test + wiring deletion, monitor moved from `monitor_ids` to `cron_monitor_alert_unrouted`, `alert-reference.json` regenerated, ADR-194 addendum, C4 prose + runbook fixes | no (`destroy_count` 0) |
| **PR B** (tracker #9304) | new branch, started only after PR A's `apply-sentry-infra.yml` run on `main` is green | delete the `sentry_cron_monitor` + its unrouted entry, remove the temporary registry exemption, count ledgers (README, audit script, `model.c4`, `model.likec4.json`), Art. 30 register note | **yes** (exactly one delete) |

Scope the user chose ("function + monitor") is unchanged; only the sequencing follows the repo rule.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (verified 2026-09-30 on this worktree) | Plan response |
|---|---|---|
| `issue-alerts.tf` and `alert-reference.json` reference the monitor | `issue-alerts.tf` has NO reference to `cert-state`; its only cert entry is `gh_pages_cert_reissue_failed` (event-triggered, stays). The monitor's alert binding is `sentry_alert.cron_monitor_failure.monitor_ids` in **`cron-monitor-alerts.tf`**; `alert-reference.json` carries its numeric detector id in `cron-monitor-failure.detectorIds` | Edit `cron-monitor-alerts.tf` + `alert-reference.json`; leave `issue-alerts.tf` and the `gh-pages-cert-reissue-failed` reference entry untouched |
| model.c4 monitor counts are 55/11/44 | Live derivation is **60 monitors / 16 GitHub / 44 webapp** (`derive_cron_monitors`, `derive_github_slugs` in `plugins/soleur/test/c4-count-parity.test.sh`). The brief's numbers are stale | Never type a count from the brief; PR B re-derives 59/16/43. A second, UNGATED `44 Inngest-substrate sentry_cron_monitors` phrase sits on the `webapp -> sentry` edge and must move to 43 too |
| "cron-shared test references" exist | `cron-shared.test.ts` names only `cron-gh-pages-cert-reissue` (a `TIER2_DEFERRED_CRONS` negative assertion). Zero references to `cert-state` | No `cron-shared` edit; recorded as verified-clean |
| Delete the monitor via Terraform in this change | Two-PR rule (#8630): unroute first, delete after the first apply; also `function-registry-count.test.ts` (c2) rejects a tf monitor with no handler slug unless it is in `NON_INNGEST_MONITORS` | Split into PR A / PR B; PR A adds ONE temporary `NON_INNGEST_MONITORS` entry |
| Handler must leave with the monitor, else the code->IaC parity guard breaks | The guard (`sentry-monitor-iac-parity.test.ts`) is **one-way code -> IaC**: deleting the handler while the monitor remains is legal there. The reverse direction is guarded only by (c2) above | Handler deletion can ship in PR A; the exemption in (c2) bridges to PR B |
| Comment in `cron-monitors.tf` cites a `DISABLED_CRON_SLUG_EXEMPTIONS` entry | That symbol does not exist in any code file (only in old plans/specs). The live analogue is `NON_INNGEST_MONITORS` | Delete the whole stale comment block with the resource in PR B |
| `[ack-destroy]` is reserved for the DNS cutover PR | Cutover completed 2026-09-03 (PR5 merged, ADR-194 amendment) — the reservation is spent | PR B spends the ack |
| A `-target=`-scoped apply needs its `-target=` line kept for a delete (learning 2026-07-17) | Obsolete: `apply-sentry-infra.yml` plans the root FULL since #6589 and pins that no `-target=` survives | Ignore that learning; declared == applied by construction |
| Nothing outside the listed wiring names the function | **An opaque-id consumer exists.** `scripts/followthroughs/inngest-soak-6178.sh` (the open #6178 dedicated-host soak) pins 52 cron function UUIDs from `inngest-soak-6178.function-ids.txt` and answers `cannot_establish registry_drift` for any population id missing from the registry unless that id is in its `RETIRED_IDS` (the #9071 precedent for the GHCR minter). The population file carries UUIDs, not slugs, so a name-keyed grep cannot see it (learning `2026-09-27-a-retirement-census-by-name-missed-the-consumer-that-pinned-the-id.md`) | Measure membership after PR A deploys with ONE read-only registry probe compared against the population file (Phase 6); if a population id is missing from the registry beyond the already-retired minter, that id is the deleted function's and PR B adds it to `RETIRED_IDS` with a test row |

## Research Insights

### Premise Validation (Phase 0.6)

Cited references checked: ADR-194 (status `accepted`, PR5 amendment says the GitHub Pages origin is
retained cold and DNS-detached; its "Consequences" list states cert-expiry detection is
"deliberately retired, not replaced" and that re-arming the poll would be harmful); ADR-194's
"What gets deleted" list already names `cron-gh-pages-cert-state.ts`; and the ADR text says
"Deleting it later is fine" for this routine — only the `ssl = "full"` rule is gated on the
rollback window (#7799). Issue #4650 (the desync incident the routine once served) is CLOSED
(2026-05-30). Open issue #7711 (`[cert-poll] GitHub Pages cert requires attention`) is an
auto-filed artifact of the routine; its body instructs firing the reissue routine, which ADR-194
identifies as hazardous post-cutover. Stale premise found: the brief's count triple (row 2 above).

### Property List (Phase 0.6b)

1. After PR A merges, no served Inngest function, manifest row, placement row or routine-metadata
   row names `cron-gh-pages-cert-state`, and the watchdog reports no MISSING/UNPLANNED defect for it.
2. After PR B applies, Sentry holds no `scheduled-gh-pages-cert-state` monitor and Terraform state
   agrees with config (drift probe green).
3. At no point does an apply both unroute and delete the monitor (two-PR rule).
4. Every count-gated artifact (model.c4, README, audit-script prose) equals its live derivation at
   the moment its PR merges.
5. `cron-gh-pages-cert-reissue.ts` and `cert-reissue-marker.ts` are byte-unchanged and import nothing deleted.
6. No sweeper reading on #6178 turns `registry_drift` because of this deletion (the opaque-id consumer the name-keyed grep cannot see).

### Cut List (Phase 0.6b)

- New `ADR-NNN` for the removal -> property 4/none -> **cut**: ADR-194 already records the decision
  (detection retired, deletion permitted); a dated addendum to ADR-194 is enough.
- `DISABLED_CRON_SLUG_EXEMPTIONS`-style new exemption set -> property 3 -> **cut**: the existing
  `NON_INNGEST_MONITORS` set already buys it (one temporary entry).
- Editing `cron-gh-pages-cert-reissue.ts` to fix its dangling comment about `cron-gh-pages-cert-state.ts`
  -> none -> **cut**: the user said leave it alone (property 5); a dangling comment is harmless.
- Touching `issue-alerts.tf` -> none -> **cut**: no reference exists.
- Rewriting the 2026-05-19 Art. 30 inventory sentence -> none -> **cut**: append-only register
  convention (CLO); PR B appends a dated supersession note instead.

### Institutional learnings applied

- `2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md` — the two-PR rule's origin.
- `2026-09-27-an-import-block-breaks-terraform-test-and-a-count-ack-reaches-every-destroy.md` — a
  count-based `[ack-destroy]` is a boolean over `destroy_count`: PR B's plan must show exactly one
  delete so the ack cannot wave anything else through.
- `2026-06-05-new-inngest-cron-requires-five-registry-lockstep.md` — the registries move in lockstep on
  removal too (route, manifest, count test, placement, metadata).
- `2026-09-03-a-type-check-cannot-protect-against-a-count-change.md` — counts need derivation-backed gates, not types.

### Domain findings carried in

- **CTO (Phase 2.5):** two-PR split is correct; no evidence a single PR is safe. Hidden consumers of the
  function id derive from `EXPECTED_CRON_FUNCTIONS` (`lib/inngest/manual-trigger-allowlist.ts`,
  `app/api/internal/trigger-cron/route.ts`, `app/api/dashboard/routines/runs/route.ts`) and update
  automatically; the watchdog has no "unexpected function in registry" class, so a lingering registered
  function is never flagged. **Dissent recorded:** the CTO, and on plan review the DHH and simplicity seats, preferred keeping handler and
  monitor deletion together in PR B (no temporary exemption, no throwaway comment rewrite). This plan ships the
  handler in PR A for two reasons: (1) the soak-probe UUID is only measurable AFTER the function leaves the
  registry, so deleting it in PR A lets PR B carry a measured `RETIRED_IDS` edit, whereas deleting it in PR B
  would force a third PR for that edit; (2) it keeps the ack-carrying PR to a single-delete diff and delivers
  the user's first-named deliverable first. The cost is one temporary `NON_INNGEST_MONITORS` line. Reversal is
  trivial (move the Phase 1-2 tasks to PR B, drop the exemption) and is recorded in `decision-challenges.md`.
- **CLO (Phase 2.5):** no Art. 30 fact changes (heartbeat monitor carries no personal data); leave the
  2026-05-19 sentence verbatim and append a dated supersession; no `docs/legal/**` edit; gdpr-gate not triggered.

## Open Code-Review Overlap

One open `code-review` issue touches a planned file: **#8595** (`review: monitor registry guard gaps —
NON_INNGEST_MONITORS stale entries + no cadence parity`) names `function-registry-count.test.ts`.
**Disposition: acknowledge.** Different concern (no stale-entry guard exists); this plan adds one
temporary entry and PR B's acceptance criteria assert its removal, which mitigates exactly the gap
#8595 describes for this entry. The issue stays open.

## Architecture Decision (ADR/C4)

Detection: the plan removes a monitored subsystem and its ADR-194 "What gets deleted" item; the
existing ADR-194 sentence "manual-trigger arm retained" and the `api -> cloudflare` C4 prose become
false. A future reader would be misled, so the record is a deliverable of THIS plan.

### ADR

Amend **ADR-194** (`knowledge-base/engineering/architecture/decisions/ADR-194-migrate-marketing-docs-site-off-github-pages-to-cloudflare-pages.md`)
with a short dated addendum (two or three lines) at the end of the file: `cron-gh-pages-cert-state.ts` and the
`[cert-poll]` machinery were deleted early (PR A), the Sentry monitor follows in PR B (#9304), and the #7799
conditions gating `ssl = "full"` do NOT apply to this item. The ordering narrative lives on #9304, not in the
ADR. Use the `soleur:architecture` skill. No new ADR (Cut List).

### C4 views

All three model files were read/enumerated (`model.c4` targeted regions incl. the `github`,
`cloudflare`, `letsencrypt`, `publicResolvers`, `api -> cloudflare`, `webapp -> sentry`,
`github -> sentry` edges; `views.c4` and `spec.c4` in full). Checked and found **already modeled, no
change**: external human actors (none involved), external systems/vendors (Sentry, GitHub, Cloudflare,
Let's Encrypt — unchanged), containers/data stores (none touched), actor-to-surface access
relationships (none changed). No element, tag, relationship or `view ... include` line is added or
removed. **Two prose edits only:**

- PR A: on `api -> cloudflare` (the `cron-gh-pages-cert-reissue` edge), the clause "its `0 3 * * *`
  detector cron (`cron-gh-pages-cert-state`) is removed, manual-trigger arm retained" becomes a
  statement that the detector routine was deleted (cite the ADR-194 addendum). Then regenerate
  `model.likec4.json` with `bash scripts/regenerate-c4-model.sh` (lefthook does this on commit).
- PR B: on `github -> sentry` change `Of 60 cron monitors, 16 check in from here and 44 from webapp` to
  `Of 59 cron monitors, 16 check in from here and 43 from webapp`; on `webapp -> sentry` change the
  ungated `44 Inngest-substrate sentry_cron_monitors` to 43; regenerate the JSON.
- After each, run `bash plugins/soleur/test/c4-count-parity.test.sh` (green is the count evidence),
  `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

### Sequencing

Decision is fully true after PR A for the code; the Sentry-side statements are true after PR B. The
addendum is written once in PR A and states the two-step ordering explicitly (with the PR B tracker).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing in the intended case. The
  failure shapes are a red web-platform build or deploy (a stale import of the deleted module), or a
  watchdog MISSING classification that triggers the Inngest restart backstop and briefly interrupts
  scheduled routines — bounded by the restart cooldown.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the
  change removes a poll of a public certificate state and a heartbeat monitor; no credential, data
  path or permission is added. The retained `gh-pages-cert-reissue-failed` pager and the DNS-edit
  token are untouched.
- **Brand-survival threshold:** none
- `threshold: none, reason: the diff touches apps/web-platform/server/ and apps/web-platform/infra/ only to delete a disabled, consumer-less detector and its heartbeat monitor; no user-facing surface, credential or data flow changes.`

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO assessment above (Research Insights -> Domain findings). Two-PR sequencing
confirmed; hidden consumers derive from the manifest; low stale-registry risk.

### Legal

**Status:** reviewed
**Assessment:** CLO assessment above. No Art. 30 fact change; append-only dated note in PR B;
`scripts/lint-legal-registers.sh` is the only gate to run (avoid a bare unresolved-marker token).

Product/UX Gate: not relevant — no UI surface in Files to Edit (mechanical UI-surface override checked:
no `components/**/*.tsx`, `app/**/page.tsx` or `layout.tsx` path).

## Observability

Deletion-only change; the surviving runtime signal is the cron watchdog that classifies the served
registry against the (now smaller) manifest.

```yaml
liveness_signal:
  what: scheduled-inngest-cron-watchdog check-in; the watchdog classifies EXPECTED_CRON_FUNCTIONS against the live Inngest registry and reports MISSING/UNPLANNED defects
  cadence: every 4h
  alert_target: Sentry cron-monitor-failure email workflow (sentry_alert.cron_monitor_failure)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (scheduled_inngest_cron_watchdog) + apps/web-platform/infra/sentry/cron-monitor-alerts.tf
error_reporting:
  destination: Sentry (reportSilentFallback from the watchdog handler)
  fail_loud: true
failure_modes:
  - mode: route.ts and cron-manifest.ts disagree after the edit (one still names the deleted function)
    detection: function-registry-count.test.ts (a)/(b)/(e) and execution-placement.test.ts Guard 1 in CI; at runtime the watchdog's classifyRegistry MISSING status
    alert_route: CI red on the PR; Sentry feature=cron-inngest-cron-watchdog then the cron-monitor-failure email
  - mode: PR A's unroute leaves the routing set inconsistent (label in both lists, or in neither)
    detection: sentry-cron-monitor-routing-parity.test.ts Guard 1 in CI; sentry-alert-reference-gate.sh in plan_pr
    alert_route: CI red on the PR before merge
  - mode: apply of PR A or PR B fails on main
    detection: apply-sentry-infra.yml job status plus the twice-daily full-root drift plan (scheduled-terraform-drift.yml)
    alert_route: infra-drift GitHub issue and the workflow-failure email
  - mode: alert-reference.json goes stale after a merge that bypassed the PR gate
    detection: scheduled-sentry-alert-drift.yml daily probe
    alert_route: drift issue naming the regeneration command
logs:
  where: Sentry project soleur-web-platform (org jikigai-eu) for watchdog and drift events; GitHub Actions run logs for apply and gate output
  retention: per the Sentry plan and GitHub Actions retention settings (no change from today)
discoverability_test:
  command: grep -c -e "monitor deleted in follow-up (#9304)" apps/web-platform/infra/sentry/cron-monitor-alerts.tf
  expected_output: 1
```

## Files to Delete (PR A)

- `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts`
- `apps/web-platform/test/server/inngest/cron-gh-pages-cert-state.test.ts`

## Files to Edit — PR A

Code and tests:

- `apps/web-platform/app/api/inngest/route.ts` — remove the `cronGhPagesCertState` import and its entry in the `serve()` `functions` array (69 entries after).
- `apps/web-platform/server/inngest/cron-manifest.ts` — remove `"cron-gh-pages-cert-state"` from `EXPECTED_CRON_FUNCTIONS`.
- `apps/web-platform/server/inngest/execution-placement.ts` — remove its `EXECUTION_PLACEMENT` row.
- `apps/web-platform/server/inngest/routine-metadata.ts` — remove its `ROUTINE_METADATA` row.
- `apps/web-platform/server/inngest/functions/oneshot-4650-monitor-close.ts` — `TARGET_FN_IDS` 3 -> 2 (`cron-community-monitor`, `cron-inngest-cron-watchdog`) and rewrite the adjacent comment (#4650 is closed; the one-shot is inert, so the edit is bookkeeping to keep the `TARGET_FN_IDS` subset-of-`EXPECTED_CRON_FUNCTIONS` invariant true).
- `apps/web-platform/test/server/inngest/oneshot-4650-monitor-close.test.ts` — `TARGET_SLUGS` and the two partial-registry fixtures.
- `apps/web-platform/test/server/inngest/cron-inngest-cron-watchdog.test.ts` — the "includes the two regressed monitors" test (assert `cron-community-monitor` + `cron-inngest-cron-watchdog`), the `manualTriggerEventFor` case, and the ~10 fixture uses of the deleted id as an arbitrary MISSING/streak subject (substitute another live cron id, e.g. `cron-oauth-probe`, which the file already uses).
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — `70 -> 69` with a dated changelog comment line in the existing style; add `"scheduled-gh-pages-cert-state"` to `NON_INNGEST_MONITORS` with a comment `TEMPORARY: producer deleted in PR A; monitor deleted by PR B (#9304) — remove this entry in that PR`.
- `apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts` and `apps/web-platform/test/server/inngest/cron-supabase-disk-io.test.ts` — comment-only: the "mirrors cron-gh-pages-cert-state.ts" reference becomes a pointer to a surviving sibling (e.g. `cron-inngest-cron-watchdog.ts`).

Terraform (Sentry root):

- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — remove `sentry_cron_monitor.scheduled_gh_pages_cert_state.id` from `monitor_ids`; add `scheduled_gh_pages_cert_state = "disabled, producer deleted; monitor deleted in follow-up (#9304)"` to `local.cron_monitor_alert_unrouted`.
- `apps/web-platform/infra/sentry/alert-reference.json` — drop that monitor's detector id from `cron-monitor-failure.detectorIds`; regenerate from the `sentry-alert-reference-expected-<run>` CI artifact (or the gate's printed regeneration command), never hand-guess the id.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — comment-only in PR A: rewrite the `scheduled_gh_pages_cert_state` comment block so it no longer claims the handler "still heartbeats on the retained manual-trigger arm" (false after PR A); keep `enabled = false` and every attribute.

Docs / records:

- `knowledge-base/engineering/architecture/decisions/ADR-194-migrate-marketing-docs-site-off-github-pages-to-cloudflare-pages.md` — dated addendum (see ADR section).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — the one clause on `api -> cloudflare`; then regenerate `model.likec4.json`.
- `knowledge-base/engineering/operations/runbooks/gh-pages-cert-renewal.md` — drop the deleted `.ts` from the `applies_to` frontmatter and add one line where the runbook says the routine is "manual-trigger-only" (deleted 2026-09-30; see ADR-194 addendum). The `## Detection` section already carries a "Superseded" banner and needs no second note.

Deliberately NOT edited: `cron-gh-pages-cert-reissue.ts` and `cert-reissue-marker.ts` (zero diff; imports verified below), `issue-alerts.tf`, `uptime-alerts.tf` (its dated comment describes reasoning at #7749), `cron-shared.test.ts`, `cron-inngest-cron-watchdog.ts` (its historical comment names the slug as an example), `knowledge-base/engineering/architecture/principles-register.md` (AP-019's dated note on the removed trigger is historical), `tests/scripts/fixtures/tfplan-sentry-real-baseline.json` (a frozen captured plan consumed as a static document by `tests/scripts/test-destroy-guard-counter-sentry.sh`; it derives no count from the live tf), the ADR-125/ADR-194 body text, closed plans/specs/learnings.

## Files to Edit — PR B (tracker #9304; do not start before PR A's apply is green)

- `apps/web-platform/infra/sentry/cron-monitors.tf` — delete `sentry_cron_monitor.scheduled_gh_pages_cert_state` and its comment block; reword the two sibling comments that cite the resource label (`scheduled_strategy_review`'s "(cf. scheduled_gh_pages_cert_state)" and the DOW-range note).
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — delete the unrouted entry (routing-parity row 11 fails on an entry naming no declared monitor; `cron_monitor_alert_unrouted` returns to `{}`).
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — remove the temporary `NON_INNGEST_MONITORS` entry.
- **Conditional:** `scripts/followthroughs/inngest-soak-6178.sh` (`RETIRED_IDS`) and `scripts/followthroughs/inngest-soak-6178.test.sh` — only if the post-deploy registry probe (Phase 6) shows exactly one population id missing from the registry beyond the already-retired minter; mirror #9071's edit (id added to `RETIRED_IDS`, its comment naming `cron-gh-pages-cert-state`, and one test row). Land PR B before `SOAK_STALE` (2026-10-06 in that script) or the drift reading turns into an overdue-verb reading.
- `apps/web-platform/infra/sentry/README.md` — both `60` citations -> 59 (the `**60 cron monitors**` bullet and the "declares **60** of them" sentence); T25 pins these.
- `apps/web-platform/scripts/sentry-monitors-audit.sh` — the one-line `60 \`resource "sentry_cron_monitor"\` blocks` addendum -> 59 and note the removal (T25 greps that exact line).
- `knowledge-base/engineering/architecture/diagrams/model.c4` (+ regenerate `model.likec4.json`) — counts per the C4 section.
- `knowledge-base/legal/article-30-register.md` — append a dated supersession note under the 2026-05-19 monitor-inventory sentence (same paragraph chain, past tense only if it lands with the delete); keep that sentence verbatim; optionally bump `last_reviewed`; run `bash scripts/lint-legal-registers.sh`.
- A commit BODY line reading `[ack-destroy]` (never the subject; the squash emulation `scripts/sentry-squash-ack-detect.sh` renders a subject ack as `* [ack-destroy]`, which does not match).
- PR body: `Closes #9304`.

## Implementation Phases

### Phase 0 — Preconditions (PR A, before any edit)

1. Re-run `git grep -n "cron-gh-pages-cert-state\|cronGhPagesCertState\|CertState" -- ':!knowledge-base' ':!tests/scripts/fixtures'` and confirm the hit set equals the Files list above (a new consumer since planning would show here).
2. Confirm the reissue pair imports nothing deleted: `grep -n 'from "' apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts apps/web-platform/server/cert-reissue-marker.ts` — expected sources are `@/server/inngest/client`, `@/server/observability`, `@/server/cert-reissue-marker`, `./_cron-shared`, `pino` and dynamic `node:dns/promises` / `@octokit/core` only.
3. Baseline: run the Inngest parity vitest set once and record it green: `function-registry-count`, `execution-placement`, `routine-metadata-parity`, `cron-inngest-cron-watchdog`, `oneshot-4650-monitor-close`, `sentry-monitor-iac-parity`, `sentry-cron-monitor-routing-parity`, plus the two dependents `.github/enforcement-contracts.json` (`cron-tier2-parity`) lists for `cron-manifest.ts`: `cron-safe-commit-parity` and `cron-shared` (run from `apps/web-platform`; runner is `./node_modules/.bin/vitest run <paths>`, never `bun test` — the package ignores bun discovery).
4. Note the soak probe's current retired set (`grep -n RETIRED_IDS scripts/followthroughs/inngest-soak-6178.sh` -> the minter's `26e6836b-...` only) so Phase 6 can subtract it; no pre-merge probe is needed.

### Phase 1 — Tests first (RED)

Per `cq-write-failing-tests-before`, edit the assertions to the post-state before deleting code: registry count 69 + the temporary exemption, and the manifest/oneshot/watchdog fixtures without the deleted id. Run the set: `function-registry-count` (a) MUST fail (70 wiring entries vs the asserted 69) — that is the RED. The lockstep guards (`function-registry-count` (b)/(e), `execution-placement` Guard 1, `routine-metadata-parity`) stay green here because every wiring row still exists; they are the GREEN evidence in Phase 2, where the four rows and the file leave together, and they go red if any ONE row is removed alone. Delete the function's own test file last.

### Phase 2 — Delete and unwire (GREEN)

Delete the two files, remove the four wiring rows and the route import/entry, edit the oneshot constant. Re-run the Phase 0.3 set: all green.

### Phase 3 — Sentry route-off

Edit `cron-monitor-alerts.tf` (list + unrouted map) and the `cron-monitors.tf` comment. Run `terraform fmt -check` and `terraform validate` in `apps/web-platform/infra/sentry` if the toolchain is present (no credentials needed; never plan or apply locally — `use_lockfile = false`). Run the routing-parity test.

### Phase 4 — alert-reference.json

Push the branch. The PR-time `plan_pr` job's alert-reference gate reports the projection mismatch and uploads `sentry-alert-reference-expected-<run>`; download it (`gh run download <run> -n sentry-alert-reference-expected-<run>`), commit it as `alert-reference.json`, push, and confirm the gate is green. Expected diff: exactly one id removed from `cron-monitor-failure.detectorIds`, nothing else.

### Phase 5 — Records

ADR-194 addendum (via `soleur:architecture`), the `model.c4` clause + regenerate JSON, runbook notes. Run the C4 parity/syntax/render tests and the markdown/legal lints that apply.

### Phase 6 — Ship PR A

PR body, first line (the answer to "does merging THIS alone mutate production?"): merging deploys web-platform without the deleted function AND applies one in-place Sentry alert update through `apply-sentry-infra.yml` (one disabled monitor's detector leaves `cron-monitor-failure`); zero destroys. Then `Ref #9304`, `Closes #7711` (the `[cert-poll]` issue filed by the deleted routine — comment first that the routine and the abandoned cert are gone), no `[ack-destroy]` needed (`destroy_count` 0; the plan_pr gate prints PASS). Avoid the words `Operator`, `Post-merge` and `Follow-up` as PR-body headings (ship's operator-step gate denies them).

After merge, `soleur:postmerge` (all automatable, no operator step): confirm the `apply-sentry-infra.yml` run on `main` is green; wait for the web-platform release to deploy; then dispatch the read-only `cutover-inngest.yml` with `op=registry-probe` (`gh workflow run cutover-inngest.yml -f op=registry-probe`; a dispatched run is async, so arm a watch on its run id — `hr-dispatch-async-must-arm-watch`), save the sorted `function_ids`, and compute `comm -23` of the sorted population file (`scripts/followthroughs/inngest-soak-6178.function-ids.txt`) against them, subtracting the retired minter id. Empty result: the deleted function is not in the soak population, nothing to do. Exactly one id: it is the deleted function's UUID (cross-check `git log --since` for any other function removal in the window); PR B carries the `RETIRED_IDS` edit. More than one: another removal landed, attribute before proceeding. **Post the result as a comment on #9304** (a fresh PR B session cannot tell "not in the population" from "nobody measured it" otherwise). Also confirm the watchdog's next tick reports no defect for the manifest (Sentry, no SSH).

### Phase 7 — PR B (separate branch, from updated `main`)

Execute the PR B list. Before pushing: the PR plan (plan_pr job output) must show **exactly 1 delete** (`sentry_cron_monitor.scheduled_gh_pages_cert_state`) and zero other destroys/replaces — the ack is blanket. Commit body carries `[ack-destroy]`. The apply happens only through `apply-sentry-infra.yml` on merge; never locally.

## Acceptance Criteria

### PR A (this branch) — before merge

- [ ] `git ls-files apps/web-platform | xargs grep -l "gh-pages-cert-state\|gh_pages_cert_state\|GhPagesCertState"` returns exactly these six files and no other: `infra/sentry/cron-monitors.tf` (resource and its rewritten comment, until PR B), `infra/sentry/cron-monitor-alerts.tf` (the unrouted entry), `infra/uptime-alerts.tf` (dated comment), `server/inngest/functions/cron-gh-pages-cert-reissue.ts` (untouched comment), `server/inngest/functions/cron-inngest-cron-watchdog.ts` (historical comment) and `test/server/inngest/function-registry-count.test.ts` (the temporary exemption).
- [ ] `git diff origin/main --stat -- apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts apps/web-platform/server/cert-reissue-marker.ts` is empty.
- [ ] `route.ts` `functions` array has 69 entries; `function-registry-count.test.ts` (a) asserts 69; the set (b)-(e), `execution-placement` Guard 1, `routine-metadata-parity`, `cron-inngest-cron-watchdog`, `oneshot-4650-monitor-close` are green.
- [ ] `sentry-monitor-iac-parity.test.ts` and `sentry-cron-monitor-routing-parity.test.ts` green; the routing test shows the label only in `cron_monitor_alert_unrouted`, with a `(#9304)` reason.
- [ ] `alert-reference.json` diff is exactly one removed detector id, produced from the CI artifact; the PR's alert-reference gate is green.
- [ ] `plan_pr` reports `destroy_count` 0 (`sentry destroy gate: PASS (plan destroys nothing)`) and the `sentry-destroy-required` check is green.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` green (counts unchanged in PR A: monitor still declared), `c4-code-syntax` and `c4-render` tests green, `model.likec4.json` regenerated and consistent.
- [ ] ADR-194 addendum present, dated 2026-09-30, naming PR B and #9304 and stating the #7799 conditions do not apply.
- [ ] PR body's first line states the production effect (web-platform deploy + one in-place Sentry alert update, zero destroys); it contains `Ref #9304` and `Closes #7711`; no `Closes #9304`.

### PR A — after merge (automated by `soleur:postmerge`, no operator step)

- [ ] `apply-sentry-infra.yml` run on `main` for the merge commit is green (`gh run list -w apply-sentry-infra.yml -L 3`).
- [ ] The post-deploy registry-vs-population result (empty, or the one missing UUID) is posted as a comment on #9304 before PR B starts; PR B lands before `SOAK_STALE` (2026-10-06 in `inngest-soak-6178.sh`) whenever the result is non-empty.
- [ ] The watchdog's next tick shows no MISSING/UNPLANNED defect for the manifest.

### PR B (tracker #9304; verified when that PR is opened)

- [ ] PR plan shows exactly `1 to destroy`; commit body has a line-anchored `[ack-destroy]`; `sentry-destroy-required` green.
- [ ] `grep -c '^resource "sentry_cron_monitor"' apps/web-platform/infra/sentry/cron-monitors.tf` prints 59; `c4-count-parity.test.sh` green with 59/16/43; the ungated `44 Inngest-substrate` phrase reads 43.
- [ ] `apps/web-platform/scripts/sentry-monitors-audit.test.sh` T25 green (README and script prose say 59); the temporary `NON_INNGEST_MONITORS` entry is gone; `cron_monitor_alert_unrouted = {}`.
- [ ] If the vanished UUID is in the soak population: `RETIRED_IDS` in `scripts/followthroughs/inngest-soak-6178.sh` names it, `bash scripts/followthroughs/inngest-soak-6178.test.sh` is green with a new accept row for it, and the next sweeper reading on #6178 carries no `registry_drift`.
- [ ] Art. 30 note appended with the 2026-05-19 sentence unchanged; `bash scripts/lint-legal-registers.sh` green.
- [ ] Post-merge `apply-sentry-infra.yml` run green and the next `scheduled-terraform-drift.yml` sentry leg exits 0 (state matches config).

## Test Scenarios

- Given the function still exists but its test file and wiring rows were removed, when `function-registry-count` (b) runs, then it is RED naming the orphan cron file (proves the guard sees the change).
- Given route.ts drops the entry but `cron-manifest.ts` keeps it, when `function-registry-count` (e) runs, then RED (manifest != cron file set).
- Given the monitor label stays in `monitor_ids` and is also added to the unrouted map, when the routing-parity test runs, then RED "in BOTH" (must-fail row); given it appears only in the unrouted map with a `(#9304)` reason, then green (must-pass row that is not the canonical tree).
- Given the temporary exemption is missing in PR A, when (c2) runs, then RED naming `scheduled-gh-pages-cert-state` as a phantom monitor (proves the exemption is load-bearing, not decorative).
- Given PR B leaves the unrouted entry behind, when the routing-parity test runs, then RED row 11 ("names no declared monitor").
- Given PR B changes the monitor count but not model.c4, when `c4-count-parity.test.sh` runs, then RED naming edge `github -> sentry` (C4/C6) — the count evidence.
- Deterministic verification (no credentials): `grep -c '^resource "sentry_cron_monitor"' apps/web-platform/infra/sentry/cron-monitors.tf` (60 after PR A, 59 after PR B); `bash plugins/soleur/test/c4-count-parity.test.sh`; `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh`.

## Risks and Sharp Edges

- **The count triple in the brief is stale** (55/11/44 vs live 60/16/44). Re-derive at each PR; never copy a number from a plan into a gated file.
- **The `[ack-destroy]` is blanket.** PR B must show one delete and nothing else. If any other destroy or replace appears (e.g. a resource re-imported since), stop and split — a blanket ack would approve it too.
- **Ack placement.** In a commit body line, not the subject; the pre-merge gate may warn that it cannot read the repo squash setting — the post-merge gate reads the merge commit itself.
- **Do not hand-edit `alert-reference.json`'s id.** The detector id is not derivable from the repo; use the CI artifact (Phase 4). A wrong id turns the daily drift probe into a false alarm.
- **Soak-probe drift window.** If the deleted function's UUID is in the #6178 soak population, the sweeper reads `cannot_establish registry_drift` from the PR A deploy until PR B lands `RETIRED_IDS`. It pages nobody, but "do not flip" is the probe's verdict and `SOAK_STALE` (2026-10-06 in that script) turns it into an overdue verdict; order PR B accordingly. The id is measured (before/after diff), never guessed: the population file holds UUIDs with no slugs and they are not the UUIDv5 of the slug.
- **Audit warning window.** Between PR A's apply and PR B, the monitors audit lists the unrouted monitor with a `::warning::` on each run; expected and bounded by PR B.
- **`ssl = "full"` and the rest of ADR-194's deferred list stay deferred** (#7799, expires 2026-11-20). This change touches only the detector routine and its monitor.
- **A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6.** Filled above (`none` with a scope-out reason because the diff touches sensitive paths).
- **PR B could stall.** The temporary exemption is inert if it does (a disabled monitor and no producer page nothing); #9304 carries the full checklist so a fresh session can resume from it.

## Resume prompt

```text
soleur:work knowledge-base/project/plans/2026-09-30-chore-remove-obsolete-gh-pages-cert-state-cron-and-sentry-monitor-plan.md. Branch: feat-one-shot-remove-gh-pages-cert-state. Worktree: .worktrees/feat-one-shot-remove-gh-pages-cert-state/. PR-B tracker: #9304. PR A first (function + wiring + unroute), PR B after PR A's Sentry apply is green.
```
