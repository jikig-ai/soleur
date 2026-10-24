---
title: "review: orphan-sweep residuals — monitored signal, project-identity proof, ADR-241 entry, filer labels"
type: fix
date: 2026-10-24
slug: orphan-sweep-residuals
branch: feat-one-shot-10952-orphan-sweep-residuals
issue: 10952
closes: 10952
priority: p3
domain: engineering
brand_survival_threshold: none
lane: single-domain
---

# review: orphan-sweep residuals — monitored signal, project-identity proof, ADR-241 entry, filer labels

## Overview

Issue #10952 bundles four follow-ups left after the two Hetzner orphan sweeps in `.github/workflows/scheduled-terraform-drift.yml` (`rung2-rehearsal-orphan-sweep`, `inngest-rehearsal-orphan-sweep`) moved to the read-only token with a failure email (PR #10936, merged 2026-10-23). This plan covers only those four items, in their smallest form after plan review and two CTO rulings rounds (2026-10-24):

1. **A monitored signal for the sweeps themselves** — one aggregator job posts a Sentry Crons check-in on a new slug, `ok` only when both sweeps' job results are `success`, so a sweep that never ran (failed checkout, cancel, timeout, rejected email) reaches Sentry.
2. **A project-identity proof inside each sweep** — before any listing, each sweep proves the token can see the pinned production volume; an unproven identity ends the sweep red with a named error slug, a distinct failure-email subject and an `error` check-in.
3. **The ADR-241 amendment entry** for the two jobs that left the Tier-B environment set, plus the runbook true-up.
4. **The harvested labels on the two orphan filers** (labels on create).

The epic stays open: `Ref #9927`, `Ref #10112`, never a closing keyword. `Closes #10952` is the only closing keyword in the PR body. Not started here (operator sequence): the first-run look at both sweeps (blocked on #10854), the Doppler version-history measurement, the Hetzner project-deletion coverage, and epic items 3 to 5.

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue or brief | Reality (verified 2026-10-24) | Plan response |
|---|---|---|
| "Whichever of the two open PRs that edit ADR-241 merges second adds the dated amendment entry; the open sibling is the Inngest site-C change (#10891)" | #10891 is MERGED (2026-10-23) and added its own dated entry ("2026-10-23 (#10664 Site C)"). `grep -in orphan` over ADR-241 returns one unrelated hit (an orphan repo secret). No entry covers the two sweeps. This PR is the second to merge by construction. | Append one dated entry after the Site C entry; no edit of any earlier entry. |
| "Both orphan filers keep the single `infra-drift` label" | True for the two orphan filers (`--label "infra-drift"` only). The scratch-config filer already uses `infra-drift`, `action-required`, `priority/p2-medium`. Labels `infra-drift`, `action-required`, `priority/p1-high`, `priority/p2-medium` all exist (`gh label list`, 2026-10-24). No orphan issue has ever been filed (a search of open and closed issues titled "orphaned rehearsal" returned nothing). | Add `action-required` plus a priority label on create; no re-assert path (nothing to upgrade). No label creation step needed. |
| "No Sentry check-in covers these jobs (only `drift-check` publishes one)" | Two jobs publish: `drift-check` (`scheduled-terraform-drift`) and `heartbeat-live-reconcile` (`scheduled-heartbeat-reconcile`). The sweep claim holds. The sole-copy job also has none (open #10430, out of scope). | Add one slug for the sweeps; leave #10430 alone. |
| "The sweeps do not check project identity ... caught only indirectly by `sole-copy-protection-check` paging on `volume-not-found`" | True. That job pins volume id `106903269` and name and files a p1 `action-required` issue plus an email. A 404 on the by-id volume GET cannot tell a deleted volume from a token of another project (the postmerge section-5c one-liner maps 404 to `volume-gone`). | The sweep proves "the token can see the production volume" and the page text names both causes; "wrong project" is never claimed as a detection. The sole-copy job is not touched (#10430). |
| "scheduled, read-only check that the token resolves the same project id the sweeps target ... with its own page" | The sweeps do not target a project id: they list whatever project the token belongs to. The rehearsal roots run in the production Hetzner project (`apps/web-platform/infra/rung2-rehearsal/rehearsal.tf` says so). No Hetzner project-identity endpoint is recorded anywhere in the repo (unverified). A separate job would add a third Hetzner lister. | The sweeps' own cadence (twice daily) is the schedule; "own page" is the named error slug, the distinct email subject and the `error` check-in. A second p1 issue would duplicate the sole-copy filer (CTO ruling C2). |
| "re-eval by 2026-11-23" | Still in the future. | Carried into the follow-up issues as dated close-or-route criteria. |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #9927 OPEN, #10112 OPEN, #10430 OPEN (sole-copy check-in; not closed by anything), #10854 OPEN (no live Inngest scheduler; last drift run 2026-10-22T06:00Z), #10891 MERGED, #10936 MERGED. Cited paths exist on this branch: the workflow, `cron-monitors.tf`, `cron-monitor-alerts.tf`, ADR-241, the runbook `infra-credential-tiers-8209.md`, `plugins/soleur/test/token-drift-workflow-causes.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`. ADR corpus grep for the proposed mechanisms: ADR-031 owns the check-in topology (the "#8630 amendment" the workflow cites for "a shared slug cannot do per-job liveness"); ADR-282 owns the id pin; no ADR rejects an aggregator or an in-sweep anchor. Stale: only the ADR-241 "second PR to merge" premise (above).

### Property List (Phase 0.6b)

- P1. A sweep job that did not run to a verdict reaches a person without depending on Resend or on the job's own steps.
- P2. A sweep that ran and produced no verdict (token unreadable, listing unreachable, issue filer dead) reaches a person (already true by email; P1 adds a second channel).
- P3. A clean sweep verdict is only possible when the token can see the pinned production volume.
- P4. A sweep that cannot prove that has its own named reason (error slug, email subject, check-in), distinct from "an orphan was found", and the text names both possible causes.
- P5. A real paying-box orphan is visible on the operator's only comprehension surface (the digest), sorted by priority.
- P6. The recorded architecture (ADR-241, the runbook, C4 counts) does not lie about the two jobs after this ships.

### Cut List (Phase 0.6b, updated after plan review and CTO rulings C1 to C7)

| Mechanism proposed or implied | Property | Disposition |
|---|---|---|
| Better Stack heartbeat (issue text offers it) | P1 | Cut: the repo's GitHub Actions observability layer is Sentry Crons; Better Stack heartbeats need a new Terraform root plus a credential. Ruled by CTO agent, 2026-10-24. |
| A separate scheduled project-identity job | P3, P4 | Cut: adds a third Hetzner lister and its verdict says nothing about the sweeps' own token. |
| A second pinned anchor (server id) | P4 | Cut for now: the volume is delete-protected and a sanctioned lift already pages p1; revisit only if the sole-copy job and the sweeps ever disagree. |
| Per-sweep Sentry slugs | P1 | Cut: second ledger pass. |
| Job-level `outputs:` and `identity`/`scratch_cfg_*` clauses in the aggregator status | P1 | Cut (C1): an identity failure `exit 1`s so the job result already carries it; the scratch-config condition means the sweep did run and has its own filer and email. Residual recorded in the ADR-241 entry. |
| A dedicated identity issue filer | P4 | Cut (C2): the sole-copy job already files a p1 for the same underlying condition; a 5xx must not file a p1; two sweeps race on one title. |
| `scripts/lib/hetzner-identity-anchor.sh` and its own suite | P3 | Cut (C3): inline in both sweeps; the pin reuses the constant name `VOLUME_ID_PIN`, pinned by an exact-count row. |
| ADR-031 amendment | P6 | Cut (C4): the rule goes in the comment block above the aggregator, next to the #8630 citation. |
| Follow-through enrollment script and directive | none in scope | Cut (C5): a plain dated issue. |
| Label re-assert on the existing-issue path | P5 | Cut (C6): no orphan issue has ever been filed. |
| Exporting a `sent` output from the email steps | P1 | Cut: a failed sweep job already turns the aggregator `error`. |
| Folding the sole-copy job into the aggregator | none in scope | Cut: #10430 owns it. |

### Institutional learnings that bind this plan

- `2026-10-23-a-converted-jobs-guard-pinned-its-spelling-and-its-shim-could-not-fail.md` — derive the guard population by behaviour; shims must honour `-f`, `-o`, `-w` and argv; unset `orphans` is `''` and passes `!= '0'`; `outcome == 'success'` on the notify step is not proof of delivery; job cap above the sum of step bounds.
- `2026-09-18-local-composite-action-needs-checkout-continue-on-error-masks-it.md` — the aggregator needs its own checkout before the local `sentry-heartbeat` action; verify the first live run's step list.
- `2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md` and `2026-10-11-two-pr-rule-monitor-routing-recipe.md` — unknown detector id renders `null` at plan time; the unrouted reason must cite a real `#N`; the XOR routed/unrouted parity test.
- `2026-09-07-my-instruments-reported-green-while-measuring-nothing.md` — a new monitor moved four prose counts; run `c4-count-parity`, assert the slug destination.
- `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` — one terminal `if: always()` POST, no `|| true`.
- `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md` — a clean verdict reports what it inspected; an unproven identity is "could not measure", not clean.
- `2026-10-09-my-scripted-adr-rewrite-cut-the-file-at-the-wrong-match-and-every-gate-passed.md` — ADR edits are line-anchored with a single-match assertion; check the deletion count.
- `2026-09-23-the-alert-i-was-told-paged-routed-to-nobody.md` — "pages" has three hops (emit, rule exists, rule routes); the unrouted monitor opens a Sentry issue only, which the PR body must say.

## Open Code-Review Overlap

None of the open `code-review` issues names a file this plan edits (checked 2026-10-24 against the workflow, both Sentry `.tf` files, ADR-241, `model.c4`, the two suites, `function-registry-count.test.ts` and the runbook). Related open `deferred-scope-out` issues: #8595 (NON_INNGEST_MONITORS stale entries) — acknowledge: its reverse-direction guard `(c3)` now exists and this plan adds one entry that the guard keeps honest; #10664 (Site C and sweep follow-ups) — acknowledge: the Site C item is done; its remaining items are host-window work; #10530 (shape-check every `::add-mask::`) — acknowledge: the sweeps' masks are not touched. Also observed: two open duplicate issues (#10829, #7233) for the standing rung-2 scratch-config condition, the older one carrying three priority labels (it will rank at the top of the digest as a false p0). Out of scope here; a separate dated follow-up issue covers closing the duplicate and finding why the exact-title dedupe let both exist (Phase 6.2, follow-up (c)).

## Problem Statement / Motivation

The two sweeps guard against paying Hetzner boxes (one with a live LUKS key in its scratch Doppler config) that Terraform state forgot. Since #10936 they send a failure email, but:

- the email step cannot run when checkout fails (the local action is not on disk), a job-level cancel or timeout leaves `failure()` false, and a Resend rejection leaves a warning, so a sweep that never ran produces no message and no Sentry signal;
- a read-only token that cannot see the production project would list nothing and report a clean sweep; only the sole-copy job notices, and its page is worded for a lost volume;
- a real orphan files an issue labelled `infra-drift` only, which the weekly operator digest does not harvest;
- ADR-241 does not record that the two jobs left the Tier-B set, and the runbook prose says project identity is "checked only indirectly" and that no Sentry check-in covers these jobs.

## Proposed Solution

### 1. Aggregator job and one Sentry cron monitor (item 1)

New job `orphan-sweeps-checkin` in the same workflow:

- `needs: [rung2-rehearsal-orphan-sweep, inngest-rehearsal-orphan-sweep]`, `if: always() && github.ref == 'refs/heads/main'`, `runs-on: ubuntu-24.04`, `timeout-minutes: 5`. `always()` is kept deliberately (CTO ruling C7): a manual cancel posts `error`, which is accurate (that slot's sweeps did not complete) and only costs noise on a deliberate cancel.
- Steps: `actions/checkout` (same pinned sha, `persist-credentials: false`, step timeout 2) then `./.github/actions/sentry-heartbeat` with `continue-on-error: true`, `monitor-slug: scheduled-orphan-sweeps`, and the three `SENTRY_*` secrets only. If the aggregator's own checkout fails, no check-in is sent and Sentry reports MISSED, which is the intended property.
- It must not name `api.hetzner.cloud`, the read-only token name, or any secret other than the three `SENTRY_*` ones (otherwise the R7 population rule pulls it into the Hetzner-lister set). It carries no job-level `outputs:` and the sweeps gain none.
- Status expression (positive evidence only):

```yaml
status: >-
  ${{ (needs.rung2-rehearsal-orphan-sweep.result == 'success'
  && needs.inngest-rehearsal-orphan-sweep.result == 'success')
  && 'ok' || 'error' }}
```

- Orphans found and filed is `ok` (drift-check precedent: "ran and found something" is not "could not run"; the issue is the signal). An identity failure, a failed listing, a dead filer or a cancel all end the sweep job non-success and so post `error`.
- A comment block above the job records the rule (CTO ruling C4): one slug per job group, `ok` only on `needs` results, a shared slug cannot do per-job liveness (the #8630 amendment cited at the drift-check check-in), and that the sole-copy job joins later by adding itself to `needs` (#10430).
- New monitor `sentry_cron_monitor.scheduled_orphan_sweeps` in `apps/web-platform/infra/sentry/cron-monitors.tf`: `name = "scheduled-orphan-sweeps"`, `schedule = { crontab = "0 6,18 * * *" }`, `checkin_margin_minutes = 60`, `max_runtime_minutes = 30`, `failure_issue_threshold = 1`, `recovery_threshold = 1`, `timezone = "UTC"`. The 25-minute job cap puts a worst-case check-in about 30 minutes after the slot, inside the margin. `max_runtime_minutes` has no effect (single check-in).
- Created unrouted: add `scheduled_orphan_sweeps = "failure emails and filed issues are the primary channels; route after the first measured check-in (#<routing issue>)"` to `local.cron_monitor_alert_unrouted` in `cron-monitor-alerts.tf` (two-PR rule, precedent `workspaces_luks_verify_web2`). The routing follow-up issue is filed FIRST (Phase 0) so the reason cites a real number; the routing-parity test requires it.
- Ledgers: `README.md` counts (monitor total 65 -> 66, including the two literals test T25 reads, the "66 resource sentry_cron_monitor blocks" sentence in the audit script and the bold "66 cron monitors" in the README; re-derive the exact strings from the test, do not trust this paraphrase), `NON_INNGEST_MONITORS` in `function-registry-count.test.ts`, the count prose in `apps/web-platform/scripts/sentry-monitors-audit.sh`, `model.c4` (`Of 65 cron monitors` -> 66; `20 check in from here` -> 21), `model.likec4.json` regenerated with `scripts/regenerate-c4-model.sh` (the parity test names it), and the header of `.github/actions/sentry-heartbeat/action.yml` ("13 steps across 12 workflow files — scheduled-terraform-drift.yml carries two" -> 14 steps, three). Unchanged by derivation: C1 (18 workflows), C6/C9 (45 webapp), C7.

### 2. Project-identity proof inside each sweep (item 2)

Inline in both sweeps' `sweep` step, after the token shape check and BEFORE any listing, mirroring the sole-copy probe's call shape:

- `readonly VOLUME_ID_PIN=106903269` in each sweep step (the constant name is reused on purpose so one grep covers every copy; CTO ruling C3).
- One GET: `bc_curl ... -- -sS --max-time 30 -o "$body_file" -w '%{http_code}' "https://api.hetzner.cloud/v1/volumes/${VOLUME_ID_PIN}"`. No `-f` (the code is read). The inngest sweep keeps its stdin-config curl form already used by that job; the request shape (no `-f`, `-o`, `-w`, `--max-time`) is the same. Two attempts, 5 s apart, retried only on transport error, 429 and 5xx (worst case about 285 s for the whole step, under the unchanged 6-minute `timeout-minutes`).
- Pass requires HTTP 200 and `.volume.id == pin` (numeric), read with `jq` guarded as `|| id=""` (an unguarded `jq` under `set -e` would abort with `identity` unpublished). No name check, no new credential, GET only.
- Outcomes. The step publishes `identity=proven|unproven|unreachable` to `$GITHUB_OUTPUT` BEFORE it exits, prints the named slug as `::error::`, and `exit 1`s:
  - `proven`: continue to the listings.
  - `unproven` (401, 403, 404, 200 with a wrong id or a malformed body): `orphan_sweep_project_identity_unproven`.
  - `unreachable` (transport error, 429, 5xx after the attempts): `orphan_sweep_project_identity_unreachable` — an unreachable Hetzner is not an unproven identity and the text must not claim it is.
- Identity failure suppresses the orphan listing for that run (a blind sweep must not read as clean; stricter side wins).
- The page is the named slug, the red job, the failure email and the `error` check-in. The failure email stays the LAST step of each job with `if: failure()`; its subject becomes conditional: `[INFRA DRIFT] <rung-2|inngest> orphan sweep: cannot prove the production volume is visible to this token` when `steps.sweep.outputs.identity == 'unproven'`, else the current subject; the body adds the `identity` value and the sweep name next to the step outcomes. The text names both causes (the volume is gone, or the token belongs to another project) and gives the first read-only action (list server names with the read-only token); it never says "wrong project" as a detection. No second issue filer: `sole-copy-protection-check` already files a p1 for the same underlying condition (CTO ruling C2).
- Pin equality: extend row N1 of `plugins/soleur/test/sole-copy-drift-check.test.sh`: extract every `readonly VOLUME_ID_PIN=` from the workflow file, assert the count is exactly 3 (sole-copy probe plus the two sweeps), assert all three are equal, and keep the existing equality to ADR-282, the postmerge skill's section-5c one-liner and the runbook one-liner. The exact count stops a deleted copy from passing silently. The sole-copy probe's own `readonly VOLUME_ID_PIN=` line is not moved (the suite reads it with `sed`).

### 3. Labels on the orphan filers (item 4)

- `rung2-rehearsal-orphan-sweep` filer: create with `--label "infra-drift" --label action-required --label priority/p1-high` (paying box plus a scratch config holding a live `GIT_DATA_LUKS_KEY` and the production ingest token: credential-exposure class, not an outage, so not p0).
- `inngest-rehearsal-orphan-sweep` filer: `--label "infra-drift" --label action-required --label priority/p2-medium` (throwaway values; cost, not exposure). The digest caps at eight, sorts by priority, and `action-required` is saturated; the PR body states the p2 may not surface and that is the ruled priority.
- Labels on create only. No re-assert on the existing-issue path (CTO ruling C6: no orphan issue has ever been filed, so there is nothing to upgrade). The filers' `if` gates stay unchanged. No `ci/` label.

### 4. Documentation (item 3 and P6)

- ADR-241: append `### 2026-10-24 (#10952; the move itself landed in #10936 on 2026-10-23): the two orphan sweeps leave the Tier-B environment set` after the Site C entry. Body: the sweeps hold the read-only token only, send a failure email, now prove they can see the pinned production volume before listing, and are monitored through the aggregator (one sentence pointing at the comment block above the job); no status change; D4's body and the Statuses table are not edited. Residuals recorded (CTO ruling C1): the scratch-config issue filer failing AND Resend rejecting its email in the same run, on a standing condition tracked by #10829 and #7233, reaches no one; there is no second pinned anchor; the sole-copy job is out of scope (#10430). Line-anchored edit with a single-match assertion and a deletion-count check (learning 2026-10-09).
- Runbook `infra-credential-tiers-8209.md`: fix the two sweep rows (project identity is now checked in the sweep, as "can the token see the pinned volume"), the residuals paragraph ("no Sentry check-in covers these jobs"), and add a row for `orphan-sweeps-checkin`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a monitored signal for the sweeps themselves (a Better Stack heartbeat or a Sentry check-in, per the repo's observability layers), so a sweep that never ran reaches a person" [issue #10952] | Proposed Solution 1; Phase 1 | mapped |
| 2 | "a scheduled, read-only check that the token resolves the same project id the sweeps target, with its own page" [issue #10952] | Proposed Solution 2; Phase 2 | mapped |
| 3 | "ADR-241 amendment entry for the two jobs that left the Tier-B environment set" [issue #10952] | Proposed Solution 4; Phase 5 | mapped |
| 4 | "add the labels the operator digest harvests (verify they exist first)" [issue #10952] | Proposed Solution 3; Phase 3 | mapped |
| 5 | "Ref #9927 and Ref #10112 only, never a closing keyword; #9927 stays open" [brief] | PR body in Phase 6 | mapped |
| 6 | "Do ONLY #10952 in this run; do not start steps 2 to 4, and do not start epic items 3 to 5" [brief] | Non-Goals | mapped |
| 7 | "Run the local affected gate before marking the PR ready, not after." [brief] | Phase 6 | mapped |
| 8 | "The PR body states what was measured and what was not, with dates." [brief] | Phase 6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Aggregator job and `scheduled-orphan-sweeps` monitor | "a Better Stack heartbeat or a Sentry check-in" | asked |
| Inline identity anchor in both sweeps | "token resolves the same project id the sweeps target" | asked |
| Conditional failure-email subject and named slugs | "with its own page" | asked |
| Labels on create | "add the labels the operator digest harvests" | asked |
| ADR-241 entry | "ADR-241 amendment entry for the two jobs" | asked |
| Ledger edits (README, audit script, `function-registry-count.test.ts`, `model.c4`, `model.likec4.json`, heartbeat `action.yml` header) | "a monitored signal" | inferred — justification: a new monitor moves these ledgers and `c4-count-parity` and T25 redden main otherwise |
| Unrouted entry in `cron-monitor-alerts.tf` | — | inferred — justification: the routing-parity guard fails any monitor in neither list; the two-PR rule forbids routing in the same PR |
| Runbook row and prose fixes | "ADR-241 amendment entry ... (the change is recorded in the runbook ... rows)" | inferred — justification: two sentences in the runbook become false when this ships |
| New guards R10, R9 anchor rows, label rows, N1 count extension | — | inferred — justification: the new mechanisms need guards or they rot (the 2026-10-23 learning) |
| Follow-up issues (routing, sole-copy `zero` ambiguity and join, duplicate scratch-config issues) | "Re-eval by: date 2026-11-23" | inferred — justification: wg-when-deferring-a-capability-create-a requires a tracked issue per deferral |

### Split Assessment

- Subsystems touched: 4 — `.github/workflows` (+ the heartbeat action header), `apps/web-platform` (sentry infra, audit script, registry test), `plugins/soleur/test`, `knowledge-base/engineering` (ADR, C4, runbook). The items share one mechanism chain (the monitor needs the ledgers; the identity proof needs the guard), and the CTO ruled one PR.
- Planned files: about 14 | Estimated changed lines: about 350 (workflow ~120, tests ~150, docs ~60, tf ~20)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The Sentry routing PR 2 is the one forced split (two-PR rule) and is a tracked follow-up.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — no end-user surface. The operator experiences a monitor that reports `error` on every run (noise that hides a real one), or a sweep step that reds on a healthy token and suppresses the orphan listing until fixed.

**If this leaks, the user's data is exposed via:** no new exposure vector. The identity step is a GET with the existing read-only token on the same stdin-config path; the aggregator holds only the three Sentry ingest secrets and no Hetzner or Doppler credential; the email body carries no token, API body or volume identifier.

**Brand-survival threshold:** none

*Scope-out (threshold none, sensitive-path check): the diff touches `.github/workflows/` and `apps/web-platform/infra/` paths; reason: operator-facing monitoring of two scheduled infrastructure sweeps, no tenant data, no credential widened, no write capability added.*

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Five forks ruled by the CTO agent on 2026-10-24, then seven simplification cuts (C1 to C7) after plan review (see `knowledge-base/project/specs/feat-one-shot-10952-orphan-sweep-residuals/decision-challenges.md`): aggregator on one new Sentry slug with a results-only status, an inline identity anchor on the pinned volume id, p1/p2 labels on create, an ADR-241 entry, single PR with the alert created unrouted. No Product/UX, legal, finance or marketing implication: no user-facing surface and no regulated data.

## Architecture Decision (ADR/C4)

### ADR

- Amend ADR-241 (dated entry, Phase 5). No new ADR and no ADR-031 amendment (CTO ruling C4): the aggregator rule extends the #8630 check-in topology rule already cited in the workflow and is recorded in the comment block above the job; the identity pin extends ADR-282 and reverses nothing.

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`) before concluding. Checked and already modeled: external actor — the operator who receives the failure email and the digest (modeled); external systems — Hetzner API, Doppler, Resend, Sentry, GitHub Actions (all present as the `github -> hetzner/doppler/resend/sentry` edges); containers/data stores — none added; actor-surface access — unchanged. The only change is the derived cardinality on the `github -> sentry` edge: `Of 65 cron monitors` -> 66 and `20 check in from here` -> 21 (C4 and C5 of `c4-count-parity.test.sh`, verified by running the derivations on 2026-10-24: 65 and 20 today, 13/13 passing); C1, C6, C7, C9 do not move. Edit `model.c4`, regenerate `model.likec4.json`, and run `plugins/soleur/test/c4-count-parity.test.sh`; do not conclude by reasoning about actors.

### Sequencing

The ADR entry describes the state after this PR; the monitor's routing is the one piece that becomes true only after a later PR and is recorded as such (status "unrouted" in the entry).

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/sentry/cron-monitors.tf` (one `sentry_cron_monitor`) and `cron-monitor-alerts.tf` (one unrouted-map entry). Existing root and provider pin; no new provider, no new variable, no sensitive value. Applied by the existing merge-to-main `apply-sentry-infra.yml` (privileged environment, unchanged). The monitor's detector id does not exist until that apply, which is why routing is a second PR.

### Apply path

Existing automated path (cloud-init and host replace do not apply): `apply-sentry-infra.yml` on push to main. No downtime, no blast radius beyond one new monitor in the Sentry project; a monitor with no check-in yet shows MISSED once its first slot passes.

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner is touched.

### Distinctness / drift safeguards

The drift workflow's own Sentry leg plans this root; a monitor declared but not yet applied shows as in-place drift on the standing issue until the apply converges.

### Vendor-tier reality check

Sentry Crons monitor count is not a tier-gated resource here (65 declared today). Whether an unrouted MISSED monitor emails anyone by default, and whether `sentry_cron_monitor` supports a muted flag, are unverified: Phase 0 measures both and the PR body states the result.

## Observability

```yaml
liveness_signal:
  what: "Sentry Crons check-in on slug scheduled-orphan-sweeps, status ok only when both sweep jobs concluded success"
  cadence: "twice daily, 06:00 and 18:00 UTC, Inngest-dispatched workflow_dispatch; margin 60 minutes"
  alert_target: "Sentry issue on missed or error check-in (unrouted at first, so a Sentry issue only until the routing follow-up); failure emails and filed issues remain the primary channels"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf and .github/workflows/scheduled-terraform-drift.yml (job orphan-sweeps-checkin)"
error_reporting:
  destination: "Sentry Crons (error status), the sweeps' own failure email via notify-ops-email, and the infra-drift/action-required GitHub issues"
  fail_loud: "any non-success sweep result posts status error; a job that never ran posts nothing and Sentry reports MISSED"
failure_modes:
  - mode: "checkout fails in a sweep job"
    detection: "needs.<sweep>.result is failure, aggregator posts error"
    alert_route: "Sentry issue (unrouted); no sweep email in this mode (known gap, closed by Sentry only)"
  - mode: "sweep job cancelled or killed by its 25 minute cap"
    detection: "needs.<sweep>.result is cancelled or failure"
    alert_route: "Sentry issue (unrouted)"
  - mode: "Resend rejects the failure email"
    detection: "the failed sweep already makes the aggregator post error; Sentry does not depend on Resend"
    alert_route: "Sentry issue (unrouted)"
  - mode: "aggregator job itself never runs or its checkout fails"
    detection: "no check-in, Sentry reports MISSED after the 60 minute margin"
    alert_route: "Sentry issue (unrouted)"
  - mode: "token cannot see the pinned production volume (volume gone, or token of another project)"
    detection: "identity step: orphan_sweep_project_identity_unproven slug, identity=unproven, job red"
    alert_route: "distinct failure-email subject plus aggregator error plus the sole-copy job's own p1 issue"
  - mode: "Hetzner unreachable during the identity proof"
    detection: "orphan_sweep_project_identity_unreachable slug, identity=unreachable, job red"
    alert_route: "standard failure-email subject (body names the value) plus aggregator error"
logs:
  where: "GitHub Actions run logs of scheduled-terraform-drift.yml (named ::error:: slugs); Sentry monitor check-in history"
  retention: "GitHub Actions default run-log retention; Sentry Crons check-in history per plan retention"
discoverability_test:
  command: grep -c "monitor-slug: scheduled-orphan-sweeps" .github/workflows/scheduled-terraform-drift.yml
  expected_output: "1"
```

Run before the change this command prints 0; Phase 0.3b records that and Phase 1 flips it. Live verification after deploy is the first `ok` check-in, which waits on the scheduler (#10854) and is tracked by the routing follow-up issue.

## Guard Contract

### Guard 1 — aggregator coverage (new suite rule R10 in `plugins/soleur/test/token-drift-workflow-causes.test.sh`)

**Property.** The sweeps' check-in reports `ok` only when every `*-orphan-sweep` job concluded `success`, and it covers every such job that exists.

**Assembly.** Every `*-orphan-sweep` job (derived from the parsed workflow, not a list); the aggregator's `needs`, `if`, secrets, `uses`, `monitor-slug` value and status expression; the monitor name in `cron-monitors.tf`; the sentry-heartbeat composite call sites. Chokepoint: the single status expression; a second check-in elsewhere for the same slug is itself a violation.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Drop one sweep from `needs` | property: coverage of every sweep |
| 2 | Add a third `*-orphan-sweep` job (copy of the inngest one) without adding it to `needs` | second member after a compliant first |
| 3 | Remove `always()` from the aggregator `if` | a failed sweep would skip the check-in and read as MISSED instead of error |
| 4 | Change the status expression to omit one sweep's `result` clause | positive-evidence property |
| 5 | Change `monitor-slug:` to a different value | destination must equal the `.tf` monitor name |
| 6 | Remove the main-only guard | branch dispatch would post a check-in |
| 7 | Add `api.hetzner.cloud` or the read-only token name to the aggregator | it would become an unguarded lister |
| 8 | Delete the guard's own dispatch (population derived as zero jobs) | the guard must fail on `0 checked`, not pass |
| 9 | Swap `&&` and `\|\|` in the expression, or compare with `!=` | the evaluator itself must be able to fail |
| 10 | Move the aggregator checkout after the heartbeat step | the local action must resolve before use |

**Harness rows.** (a) Break the suite instead of the workflow: a stub extractor that returns an empty jobs map must fail the suite on its population floor. (b) Must-PASS inputs that are not the canonical: the aggregator renamed (any name without the `-orphan-sweep` suffix), comments inserted, and the sweeps' step order otherwise reshuffled all pass. (c) A behavioural table drives the extracted status expression through an evaluator with GitHub semantics (case-insensitive `==`, unset coerces to `''`): both success -> ok; either of failure, cancelled, skipped -> error; a result missing from `needs` -> error; orphans found and filed (sweep result success) -> ok. Rows 9 above prove the evaluator can fail.

**Anchor.** The slug is compared against `cron-monitors.tf` at the same commit, and `c4-count-parity` moves with it (C4 and C5), so a weakening needs the tf, the workflow and the C4 prose to move together in one reviewed diff; the monitor-name set is also read by the existing `function-registry-count.test.ts` `(c2)`/`(c3)` guards. Set identity (superset of all `*-orphan-sweep` jobs), not a count floor.

### Guard 2 — project-identity proof (R9 behaviour rows, N1 exact-count pin)

**Property.** A sweep cannot report a clean verdict unless the anchor GET returned HTTP 200 with the pinned id, and no listing runs after a failed proof.

**Assembly.** Both sweeps' `sweep` steps (extracted from the workflow and executed by the R9 harness against PATH shims; mutations are applied to a copy of the workflow the harness reads), the three `readonly VOLUME_ID_PIN=` copies, ADR-282, the postmerge skill and the runbook one-liner; the `identity` step output and the conditional email subject.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Delete the anchor block in the inngest sweep | listing runs unproven |
| 2 | Delete it in the rung-2 sweep (second member after a compliant first) | per-member property |
| 3 | Treat 404 as proven | an invisible volume passes |
| 4 | Accept a 200 whose `.volume.id` differs from the pin | mismatch passes |
| 5 | Move the listings before the anchor (reorder) | property is about order: a case must observe the listing attempts INSIDE the failed-proof window and assert zero |
| 6 | Change one `VOLUME_ID_PIN` copy | N1 equality across the three copies |
| 7 | Delete one `VOLUME_ID_PIN` copy (or add a fourth) | N1 exact count of 3 |
| 8 | Drop the `identity=` publish before `exit 1` | the email subject loses the discriminator |
| 9 | Add `-f` to the anchor request | the HTTP code could no longer be read; 401/403/404 would collapse into transport failure |
| 10 | Remove `--max-time` from the anchor request, or retry on 404 | every request is bounded; retry only on transport, 429, 5xx |

**Harness rows.** (a) A shim that ignores credentials must fail: assert the shim saw the Authorization header on the stdin config for the anchor request. (b) Must-PASS inputs: 200 with the pin; 200 with extra unknown fields; a retried 503 then 200; a 429 then 200. (c) Suite-level: removing the new anchor branch from the curl shim must fail the suite, not skip it; the shim honours `-o` and `-w`; a `sleep` shim on `PATH` keeps the 5 s retry sleep out of the run. (d) The required row (CTO ruling C1): listing clean while the anchor answers 404, 200 with a wrong id, or 401/403 -> the step exits 1 with the named slug and `identity=unproven`; this row is what catches a future edit that deletes the proof.

**Anchor.** The pin literal appears in the three workflow copies (N1 exact count) and in ADR-282, the postmerge skill and the runbook one-liner (existing N1 equality); a weakening needs all of them to move in one diff, and ADR-282 and the postmerge skill are independent documents. The literal also appears in other files (encryption-posture ledger, compliance posture, runbooks) that are not pinned by N1 and are named as residual copies.

### Guard 3 — labels on both orphan filers (R3-adjacent rows)

**Property.** Every orphan filer creates its issue with `infra-drift`, `action-required` and a priority label.

**Assembly.** Both orphan-filer steps (by the `label_selector` listing R3 already identifies) and every `gh issue create` in a `*-orphan-sweep` job.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Remove `--label action-required` from the rung-2 filer | digest stops harvesting |
| 2 | Remove the priority label from the inngest filer (second member) | per-filer property |
| 3 | Swap the priorities (p2 on rung-2, p1 on inngest) | the ruled priority per filer |
| 4 | Add a third `gh issue create` in a sweep job without the labels | population derived from the parsed job, not a list |

**Harness rows.** Must-PASS: label flags reordered, `--label=x` spelling, labels on a continued line. A stubbed `gh` records argv and the suite asserts the recorded labels from a real run of the extracted step, not a grep of the text.

**Anchor.** The label names are checked against `gh label list` in Phase 0 (existence), not against a committed list that the same diff could edit.

## Implementation Phases

### Phase 0 — Setup and measurements (read-only)

- 0.1 Read the R7/R8/R9 sections of `token-drift-workflow-causes.test.sh` (`SWEEP_JOB_KEYS`, the `curl` shim, the `apifail`/`paginated`/`orphan` modes, the hard floor at the end of the suite and its prose ledger) and the sentry-heartbeat call sites.
- 0.2 Verify, with documentation or one names-only measurement, what a by-id volume GET returns from a token that cannot see the volume (404 expected) and whether any Hetzner project-identity endpoint exists. Record date and source in the PR body; if unverifiable, keep "any non-200 is red".
- 0.3 Confirm labels exist: `gh label list` for `infra-drift`, `action-required`, `priority/p1-high`, `priority/p2-medium`.
- 0.3b Run once, before relying on them, every literal command this plan prescribes: the `discoverability_test` grep (0 now, 1 after Phase 1), the count derivations, the `git ls-files` path checks, `lint-guard-contract.py` and `technical-ruling-gate.sh` (both green on this plan, 2026-10-24).
- 0.3c Measure whether an unrouted MISSED monitor emails anyone and whether `sentry_cron_monitor` supports a muted flag (`is_muted` is not used in this root); if it does, ship the monitor muted and make un-muting part of the routing follow-up; if not, the PR body states that one open Sentry issue will exist until the scheduler returns.
- 0.3d File follow-up issues (a) and (b) now, so the unrouted reason and the PR body cite real numbers: (a) route `scheduled-orphan-sweeps` — a plain dated issue, re-eval 2026-11-07 or seven days after the first `ok` check-in, whichever is later, explicit close-or-route criterion, repo milestone; if no `ok` check-in exists by 2026-11-21, comment on #10854 and move the date by 14 days with the monitor left unrouted; (b) the sole-copy follow-ups (reason `zero` ambiguity of `volume-not-found`; add the sole-copy job to the aggregator `needs`), as a comment on #10430 plus its own issue. Follow-up (c): close the duplicate scratch-config issue (#7233 vs #10829), fix its three priority labels, and find why exact-title dedupe let both exist (Phase 6.2).
- 0.4 Measure the current derived counts (`grep -cF 'resource "sentry_cron_monitor"'`, distinct `monitor-slug:`), then compare after edits.

### Phase 1 — Tests first, aggregator (item 1)

- 1.1 (RED) Add R10 rows and the evaluator-backed status table to `token-drift-workflow-causes.test.sh`; add the mutation rows and raise BOTH ratchets: `R78_MIN` and the hard floor at the end of the suite (plus its prose ledger; the comment says the floor must equal the realised count).
- 1.2 (GREEN) Add the `orphan-sweeps-checkin` job and its comment block to the workflow.
- 1.3 Add the `sentry_cron_monitor` resource and the unrouted entry; update the ledgers (README, audit-script literals, `NON_INNGEST_MONITORS`, `model.c4`, regenerate `model.likec4.json`, heartbeat `action.yml` header); run `c4-count-parity.test.sh`, `sentry-cron-monitor-routing-parity.test.ts`, `function-registry-count.test.ts`, `sentry-monitors-audit.test.sh`, `tests/scripts/test-sentry-alert-reference-gate.sh` (the unrouted entry needs no `alert-reference.json` change in this PR).

### Phase 2 — Tests first, identity proof (item 2)

- 2.1 (RED) Extend the R9 harness: a `curl` shim branch for `/v1/volumes/<pin>` honouring `-o` and `-w '%{http_code}'` with a per-mode anchor answer (default 200 with the pin); scope the existing "every request carries `-f`" assertion to the listing requests; add a `sleep` shim; add the cases (200 match, 200 other id, 404, 401/403, 5xx after two attempts, transport error, 429 retry), each asserting the exact slug, the `identity` value and zero listing calls after a failed proof; the required row (d); extend N1 (exact count of 3, equality across copies).
- 2.2 (GREEN) Add the inline anchor block to both `sweep` steps (function-free; the step itself owns the publish, the `::error::` slug and the `exit 1`; every `jq` guarded; the temp body file created and removed under the step's traps) and the conditional failure-email subject and body.
- 2.3 Confirm R7/R8 stay green: the failure email is still the last step with `if: failure()`, step sets are unchanged, the sweep step's worst case (about 285 s) is under its unchanged 6-minute bound and the job-cap sum is unchanged.

### Phase 3 — Labels (item 4)

- 3.1 (RED) Add the label rows and the stubbed-`gh` recorder case; raise the hard floor again.
- 3.2 (GREEN) Edit both orphan filers: labels on create.

### Phase 4 — Runbook

- 4.1 Runbook rows and prose (two sweep rows, the residuals paragraph, the new aggregator row).

### Phase 5 — ADR (item 3)

- 5.1 ADR-241 entry (line-anchored, single-match assertion, zero deleted lines, the C1 residual recorded).

### Phase 6 — Gate and ship

- 6.1 Run the local affected gate before marking the PR ready: the suites above, `lint-workflow-local-action-checkout.py`, `lint-orphan-test-suites.sh` (no new suite is created, so no registration step), actionlint if present, markdownlint on touched docs, and the sentry parity tests. The affected gate may degrade to the full battery for a workflow-YAML-subject suite change; name the substitute in the PR body.
- 6.2 Finish the follow-up issues from Phase 0.3d (dates in the body, milestone `Post-MVP / Later` unless a more specific roadmap phase applies).
- 6.3 PR body: `Closes #10952`, `Ref #9927`, `Ref #10112`; a "Measured / Not measured" table with dates (counts, labels existence, anchor behaviour and unrouted-monitor email behaviour measured or not; the first live run is NOT measured because the scheduler is dead, #10854); the statement that the new monitor is unrouted, opens a Sentry issue only on a missed or error check-in and will report MISSED until the scheduler fires again; the p2 digest-visibility statement for the inngest filer.
- 6.4 After merge: the Sentry apply must converge before the next drift run; read the live monitor by name (names and metadata only). The first live run of the new job is not measured here; check its step list once the scheduler returns.

## Files to Edit

- `.github/workflows/scheduled-terraform-drift.yml` — aggregator job and comment block, inline identity anchor in both sweeps, label edits, conditional email subject
- `.github/actions/sentry-heartbeat/action.yml` — header count line only
- `apps/web-platform/infra/sentry/cron-monitors.tf` — new `sentry_cron_monitor`
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — unrouted map entry
- `apps/web-platform/infra/sentry/README.md` — monitor counts
- `apps/web-platform/scripts/sentry-monitors-audit.sh` — count prose
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — `NON_INNGEST_MONITORS`
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated) — C4 and C5 counts
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` — dated entry
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` — rows and residuals paragraph
- `plugins/soleur/test/token-drift-workflow-causes.test.sh` — R9 anchor shim and cases, R10, label rows, ratchets
- `plugins/soleur/test/sole-copy-drift-check.test.sh` — N1 exact-count extension

## Files to Create

None. (The lib, its suite, the follow-through script and the ADR-031 amendment were cut by CTO rulings C3 to C5.)

All paths verified against the tree with `git ls-files` on 2026-10-24.

## Non-Goals / Deferrals

- Routing the new monitor (PR 2 of the two-PR rule): tracked follow-up (a).
- Disambiguating the sole-copy `volume-not-found` reason `zero`, and joining the sole-copy job to the aggregator: #10430 (follow-up (b)).
- A second pinned anchor to separate a deleted volume from a token that cannot see it: revisit if the sole-copy job and the sweeps ever disagree.
- Closing the duplicate standing scratch-config issues (#10829, #7233) and the dedupe-failure root cause: follow-up (c).
- The first-run look at both sweeps (#10854), the Doppler version-history measurement, Hetzner project-deletion coverage, and epic items 3 to 5: not started.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `orphan-sweeps-checkin` exists with `needs` covering every `*-orphan-sweep` job, `if` beginning `always()` plus the main-only guard, a checkout with a step timeout before the local action, and only the three `SENTRY_*` secrets; it names neither `api.hetzner.cloud` nor the read-only token; no job in the workflow declares `outputs:` (`token-drift-workflow-causes.test.sh` R10; `scripts/lint-workflow-local-action-checkout.py` green).
- [ ] AC2. The status expression is `ok` only when both sweeps' results are `success`; every other combination, including `cancelled`, `skipped` and a result missing from `needs`, is `error`; orphans found and filed is `ok` (evaluator-backed behavioural table, R10, with the evaluator-can-fail row).
- [ ] AC3. The failure email remains the last step of each sweep with `if` exactly `failure()`; no step follows it (R8).
- [ ] AC4. `sentry_cron_monitor.scheduled_orphan_sweeps` is declared with crontab `0 6,18 * * *`, margin 60, UTC; `scheduled_orphan_sweeps` appears in `cron_monitor_alert_unrouted` with a reason citing the real follow-up issue number, and NOT in `monitor_ids` (routing-parity test green).
- [ ] AC5. `c4-count-parity.test.sh` is green with C4 = 66 and C5 = 21; C1, C6, C7, C9 unchanged; README, audit-script literals (T25), `NON_INNGEST_MONITORS`, `model.c4`, regenerated `model.likec4.json` and the heartbeat `action.yml` header all agree (derivation commands quoted in the PR).
- [ ] AC6. Each sweep runs the anchor GET before any listing; R9 cases cover 200 match, 200 other id, 404, 401/403, 5xx after two attempts, transport error and 429 retry, each asserting the exact slug (`..._unproven` or `..._unreachable`), the `identity` value and zero listing calls after a failed proof; the reorder mutation (listings before the anchor) reddens a case that observes inside the window; the required row (listing clean, anchor 404 / wrong id / 401 / 403 -> exit 1 with the slug) passes.
- [ ] AC7. N1 extracts every `readonly VOLUME_ID_PIN=` from the workflow, asserts exactly 3 copies, all equal, and equal to ADR-282, the postmerge skill one-liner and the runbook one-liner.
- [ ] AC8. The anchor request carries no `-f`, carries `--max-time`, retries only on transport error, 429 and 5xx with two attempts, and the sweep step's worst case stays under its unchanged 6-minute bound (R7 job-cap sum unchanged).
- [ ] AC9. The failure-email subject is conditional on `identity == 'unproven'`; the text says "cannot prove the production volume is visible to this token", names both causes (volume gone, token of another project), never claims "wrong project" as a detection, and carries no token, API body or volume identifier; an `unreachable` identity keeps the standard subject and names the value in the body.
- [ ] AC10. Rung-2 orphan filer creates with `infra-drift`, `action-required`, `priority/p1-high`; inngest orphan filer with `infra-drift`, `action-required`, `priority/p2-medium`; verified by a stubbed-`gh` argv recorder over the extracted step, not by a grep (Guard 3 rows); no re-assert path exists.
- [ ] AC11. ADR-241 has exactly one new entry dated 2026-10-24 after the Site C entry, `git diff --numstat` shows zero deleted lines in the ADR, no status row changed, the C1 residual and the pointer to the aggregator comment block are present; no ADR-031 edit.
- [ ] AC12. The runbook's two sweep rows no longer say identity is checked only indirectly; the residuals paragraph no longer says no Sentry check-in covers these jobs; a row for `orphan-sweeps-checkin` exists.
- [ ] AC13. Both suite ratchets (`R78_MIN` and the hard floor with its prose ledger) are raised to the realised counts.
- [ ] AC14. The local affected gate ran green before the PR was marked ready (suites in Phase 6.1 listed in the PR body with results).
- [ ] AC15. Follow-up issues (a), (b) and (c) exist with dates and a milestone before the PR is marked ready; the unrouted reason cites (a).
- [ ] AC16. PR body: `Closes #10952`, `Ref #9927`, `Ref #10112`, no closing keyword for the epics; a Measured / Not measured table with dates; the unrouted-monitor, MISSED-until-scheduler and inngest-p2 statements; the result of the Phase 0.2 and 0.3c measurements or "not measured".

### Post-merge (automated or read-only)

- [ ] AC17. The Sentry apply run for the merge converged and the live monitor `scheduled-orphan-sweeps` exists (read by name, metadata only). The first live check-in is NOT expected until the scheduler (#10854) fires again and is tracked by follow-up (a).

## Test Scenarios

- Both sweeps succeed, identity proven, no orphans -> aggregator `ok`.
- Rung-2 sweep finds an orphan and files the issue (labelled) -> aggregator `ok`; the issue appears in the digest at p1.
- Inngest sweep checkout fails -> its result `failure`, aggregator `error`; no sweep email (the known gap) but a Sentry issue.
- A sweep cancelled (manual cancel or the 25-minute cap) -> `cancelled`/`failure` -> `error`.
- Resend rejects the failure email -> the sweep job is already `failure` -> `error`.
- Token cannot see the pinned volume -> anchor 404 -> `..._unproven` slug, `identity=unproven`, distinct email subject, no orphan listing, aggregator `error`.
- Hetzner unreachable -> `..._unreachable` slug, standard subject (not an identity claim), aggregator `error`.
- Standing rung-2 scratch-config `unsatisfiable` state with a healthy sweep -> aggregator `ok` (the condition keeps its own create-only issue).
- Branch dispatch (not main) -> sweeps and aggregator skipped; no check-in.
- Scheduler dead (today) -> no dispatch -> Sentry MISSED on the new monitor, unrouted: a Sentry issue only.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, a placeholder, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `none` with the sensitive-path scope-out bullet.
- `outcome == 'success'` of the notify action proves nothing about delivery; the aggregator does not read it.
- A status expression comparing against a literal reads an unset value as `error`; keep every clause a positive equality against `'success'`.
- The aggregator is named without the `-orphan-sweep` suffix on purpose; R10 (not R7) guards it, and R10's population must still be derived by behaviour.
- Do not move the sole-copy probe's `readonly VOLUME_ID_PIN=` line; the pin-equality suite reads it with `sed`. The two sweep copies reuse the name on purpose.
- The anchor must not use `-f`; an unguarded `jq` under `set -e` aborts the step with `identity` unpublished, so every `jq` in the block is guarded and `identity=` is written before `exit 1`.
- Re-derive every count at implementation time with the quoted commands; a sibling PR can move them.
- Do not run Hetzner or Doppler writes, a terraform apply, a dispatch, or print a token, response body or volume identifier into logs, PR text or fixtures; fixtures are synthesized.
