---
title: "feat: route the approval-expiry Sentry cron monitor into cron_monitor_failure (ADR-309 flip item 3)"
date: 2026-11-07
slug: route-approval-expiry-monitor-adr309-item3
branch: feat-one-shot-9601-adr309-item3-expiry-monitor-alert
issue: 9601
type: feat
lane: single-domain
---

# feat: route the approval-expiry Sentry cron monitor into cron_monitor_failure (ADR-309 flip item 3)

## Enhancement Summary

**Deepened on:** 2026-11-07
**Agents used:** `soleur:engineering:cto` (three rulings, plan phase), `soleur:engineering:review:observability-coverage-reviewer`, `soleur:engineering:review:code-simplicity-reviewer`. The full 40-agent sweep was not run: the diff is about 40 lines in one Terraform list, one generated id and two doc paragraphs; the two reviewers above were chosen for the two real risks (live-signal truth, missed consumers).

### Key improvements

1. Halt gates run mechanically: User-Brand Impact (threshold `none` with scope-out for the `apps/web-platform/infra/` sensitive path), Observability (5 fields, `grep` probe, literal `expected_output`), PAT sweep (clean), Scope Check (restructured into the canonical Ask Mapping / Provenance / Split Assessment form, placed before Acceptance Criteria), Encryption Posture, no guard so no Guard Contract, no UI so no wireframe.
2. Baselines measured so every AC can fail: the sorted-labels command prints 24 and `sorted` today, the reference `jq` prints `24 null`, the discoverability `grep` prints `0`, `terraform fmt -check` passes, and Guard 1 plus the IaC-parity test pass 51/51 on the unchanged tree.
3. Reviewer findings applied: `max_runtime` marked inert in the Observability block (the handler posts only ok/error check-ins); Observability layer wording; the read-back named as the authoritative probe behind the repo-text probe; ADR sentence reworded to "declared, applied on merge" so it cannot be false before the apply; resource-block-unchanged AC given a command; `collision-precheck.sh` given its full path.
4. Reviewer findings declined: trimming the Scope Check, Encryption Posture, IaC and Domain Review sections (each is a required gate section; deepen-plan halts without them); dropping the Phase 0 monitor re-read (the brief's stated precondition, one command); rewriting the ADR "Until then" clause in place (CTO ruling B chose an appended dated sentence over editing the historical statement).

### New considerations discovered

- `alert-reference.json` is a mandatory companion edit the brief omits (plan_pr reference gate).
- The merge-time monitors audit may print one advisory Class A warning before the apply lands; it self-heals in the same apply.
- The live read-back baseline is 24 detector ids without `2557403`.

## Overview

The `scheduled_approval_expiry` Sentry cron monitor watches the 5-minute approval-queue expiry sweep
(`apps/web-platform/server/inngest/functions/cron-approval-expiry.ts`). It is declared-unrouted today, so a dead
sweep opens a Sentry issue that emails nobody, and no independent cover exists (the unanswered alert is emitted by the
sweep itself; no Better Stack missing-`SOLEUR_APPROVAL_SWEEP` monitor exists). This change moves the monitor into the
`cron_monitor_failure` alert rule so a missed or failed check-in emails the org before the `approval-queue` flag is
ever turned on.

Delivered as ONE PR under the CTO ruling of 2026-11-07 (epic Ref #9601, tracking Ref #4672). The two-PR rule is already
satisfied: the monitor was created on 2026-10-30, its detector id (`2557403`) exists and is readable, so the plan
projection no longer errors on it.

Nothing here discharges any flip item, creates or flips any flag, or touches any environment. Checklist item 3 stays
open and says so; it is confirmed only by the post-merge read-back (Phase 4).

## Premise Validation (Phase 0.6)

| Premise | Check | Result |
|---|---|---|
| Epic #9601 and tracker #4672 are open | `gh issue view` | Both OPEN. Nothing already resolved. |
| Monitor `scheduled_approval_expiry` exists on `origin/main` and is unrouted | `git grep` | Declared in `cron-monitors.tf`; key of `cron_monitor_alert_unrouted`; absent from `monitor_ids`. |
| Precondition: measured check-ins | Live read-only GET on `monitors/scheduled-approval-expiry/` (Doppler `soleur`/`prd`, `SENTRY_AUTH_TOKEN`, GET only) | env `production` `status=ok`, `activeIncident=null`, `lastCheckIn 2026-11-07T10:05:01Z`, config `*/5`, margin 30, runtime 10, thresholds 1/1, created 2026-10-30. Matches `cron-monitors.tf`. Holds, and is consistent with the CTO's "latest 100 check-ins ok" ruling. |
| Detector id exists | `GET detectors/?query=scheduled-approval-expiry` | `"2557403"`, `monitor_check_in_failure`, enabled. |
| Live workflow does not yet bind it | `GET workflows/?query=cron-monitor-failure` | 24 detector ids, `"2557403"` absent. Baseline for the read-back. |
| Open PRs collide | `plugins/soleur/scripts/collision-precheck.sh 9601`; scan of every open PR's files for `infra/sentry/`, ADR-309, the handover | Only this branch's own draft PR #12293. No PR touches the files. Foreign `test-all.sh` processes belong to an unrelated worktree. |
| Mechanism vs ADR corpus | Read ADR-309 "Accepted deviation: cron monitor routing" and ADR-031 #8630 amendment | The ADR itself prescribes this exact route (checklist item 3). No rejected alternative. |

## Research Insights

**Property List (Phase 0.6b).**

1. A missed or failed approval-sweep check-in emails the org (today it opens a Sentry issue nobody sees).
2. The repo's routing ledgers stay consistent: Guard 1 (routed XOR unrouted), the plan_pr projection gate, the
   monitors audit.
3. The ADR checklist item and its verbatim handover copy describe the same, accurate state.
4. No flip item is discharged and no flag/environment is touched.

**Cut List.** None proposed by the ask beyond what is needed: no new monitor, no Better Stack monitor (the ADR's other
cover option), no new test, no new alert rule. The existing `cron_monitor_failure` rule (frequency 1441, email to
issue owners falling through to ActiveMembers) already provides property 1; the route is one list element.

**Companion file the brief did not name: `apps/web-platform/infra/sentry/alert-reference.json`.** The `plan_pr` job
runs `scripts/sentry-alert-reference-gate.sh`, which requires the committed reference to equal the projection of the
plan. Adding a detector to `monitor_ids` changes that projection, so the PR is red until
`cron-monitor-failure.detectorIds` gains `"2557403"`. Precedents: PR #11999 (adds `2586358`) and PR #12235 (adds
`2607514`). Derive it locally (one string-sorted insertion, between `"2409332"` and `"2586358"`); CI is the proof, not
the producer (plan-sharp-edges: a PR-required generated artifact is never deferred to the CI artifact). CTO ruled it in
scope (decision-challenges row 3).

**Learnings applied.** `2026-10-11-two-pr-rule-monitor-routing-recipe` (four greppable moves; the merge-time monitors
audit may print one advisory Class A warning before the apply lands, which self-heals in the same apply: say so in the
PR body); `2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name` (derive the label list, never
hand-type it; the id is the live detector id, not derivable from the repo).

**Conventions.** `cron-monitor-alerts.tf` header: monitor_ids is sorted with `LC_ALL=C sort` over labels; derive with
the `grep -hoE '^resource "sentry_cron_monitor" ...' | LC_ALL=C sort` command in that header.

**Sort position.** `scheduled_anthropic_credit_probe` < `scheduled_approval_expiry` < `scheduled_git_data_erasure_redrive`
(`an` < `ap` < `gi`), so the new element goes between the first and the last of those.

## Research Reconciliation: Brief vs Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Scope lists `cron-monitor-alerts.tf`, ADR item 3, handover, comment in `cron-monitors.tf` | The plan_pr reference gate also requires `alert-reference.json` to move | Add it as a mandatory companion (CTO ruling C). |
| "Guard 1 two-PR check and monitors audit pass" | Guard 1 is `sentry-cron-monitor-routing-parity.test.ts` (XOR; no per-monitor assertions about `scheduled_approval_expiry`, so no tombstone test to invert, unlike #11999). The monitors audit (`sentry-monitors-audit.sh`, run by `sentry-audit-gate.yml`) is advisory and reads the unrouted map only to classify declared-pending detectors; it warns once for a detector that is bound to no workflow and not declared pending, until the apply lands | No test edit. Note the transient advisory warning in the PR body. |
| "infra-validation terraform plan shows exactly one change" | In-place update of `sentry_alert.cron_monitor_failure` (`monitor_ids` 24 to 25). No resource is created or destroyed | State it as an AC: exactly one resource change, an in-place update, with the added element equal to the monitor id. |

## Open Code-Review Overlap

None. Queried open `code-review` issues for each of the five files; no match.

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: insert
  `sentry_cron_monitor.scheduled_approval_expiry.id,` into `monitor_ids` between the `scheduled_anthropic_credit_probe`
  and `scheduled_git_data_erasure_redrive` elements; delete the `scheduled_approval_expiry` entry and its comment block
  from `local.cron_monitor_alert_unrouted` (the block that starts `# #4672 — the approval-queue expiry sweep's liveness
  monitor`). Leave the neighbouring entries and their comments untouched.
- `apps/web-platform/infra/sentry/alert-reference.json`: add `"2557403"` to `cron-monitor-failure.detectorIds`
  (string-sorted, between `"2409332"` and `"2586358"`). No other hunk.
- `apps/web-platform/infra/sentry/cron-monitors.tf`: in the comment above
  `resource "sentry_cron_monitor" "scheduled_approval_expiry"`, replace the last sentence ("Routing to
  cron_monitor_failure follows the two-PR rule (cron_monitor_alert_unrouted in cron-monitor-alerts.tf).") with a
  statement that the monitor is routed into `cron_monitor_failure` (`cron-monitor-alerts.tf`, Ref #9601, ADR-309 flip
  item 3), so a missed or failed check-in emails once the apply has landed. Keep every other sentence of the comment.
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md`: rewrite
  checklist item 3 (Phase 2 text), and append one dated sentence to the "Accepted deviation: cron monitor routing"
  section.
- `knowledge-base/project/specs/archive/20261029-164429-feat-hitl-approval-queue/flag-create-handover.md`: the
  identical item 3 text, byte for byte.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9601-adr309-item3-expiry-monitor-alert/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9601-adr309-item3-expiry-monitor-alert/decision-challenges.md`

No code, test, workflow, script, flag or migration file changes.

## Implementation Phases

### Phase 0 — Re-verify the precondition (gate)

Immediately before the `.tf` edit, re-run the read-only GET (monitor and detector):

```bash
doppler run -p soleur -c prd -- bash -c 'printf "Authorization: Bearer %s\n" "$SENTRY_AUTH_TOKEN" | curl -sS --disable --noproxy "*" --proto "=https" -g --header @- "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-approval-expiry/"' | jq -c '.environments[]|{name,status,activeIncident,lastCheckIn,nextCheckInLatest}'
```

Proceed only if `production` reports `status=ok`, `activeIncident=null` and `lastCheckIn` is inside the margin. If not,
do not route: keep the unrouted entry, sharpen its reason with the observed evidence, and stop (the brief's
precondition failed; that is a finding, not a retry). The detector-id read uses `detectors/?query=scheduled-approval-expiry`
and must still print `2557403`; if the id differs, use the live one everywhere below. Reads only (GET); `SENTRY_ISSUE_RO_TOKEN`
403s on `/monitors/`, so the broader token is used read-only.

### Phase 1 — Terraform ledger

1. Edit `cron-monitor-alerts.tf`: add the element, delete the unrouted entry and its comment block.
2. Edit `alert-reference.json`: add `"2557403"` in sorted position.
3. Edit the `cron-monitors.tf` comment.
4. Local gates: `terraform fmt -check apps/web-platform/infra/sentry`; `jq -S . alert-reference.json` equals the file
   (canonical); `detectorIds` sorted and length 25; run
   `bun test`/`vitest` for `apps/web-platform/test/server/inngest/sentry-cron-monitor-routing-parity.test.ts` and
   `sentry-monitor-iac-parity.test.ts` (Guard 1: exactly one home per monitor); optionally
   `bash tests/scripts/test-sentry-alert-reference-gate.sh`.

### Phase 2 — Docs, in lockstep

Rewrite item 3 in BOTH the ADR checklist and the handover with this text (CTO ruling A: keep the number, status plus
re-check, never "discharged"; the handover copy cites items by number, and items 8 and 12 cross-reference each other):

```text
3. **Route the cron monitor** (accepted deviation, below): the `scheduled_approval_expiry` sweep monitor had no independent cover for a dead sweep (the unanswered alert is emitted by the sweep itself, and no Better Stack
   missing-`SOLEUR_APPROVAL_SWEEP` monitor exists). Routing is now **declared, not yet confirmed**: Ref #9601 (PR #12293) adds the monitor's id to the sorted `monitor_ids` of `cron_monitor_failure` and deletes its
   unrouted entry in `cron-monitor-alerts.tf`, so a missed or failed check-in emails the org once the change is applied. Keep this item open until both hold, read-only: `apply-sentry-infra` is green for that change, and the
   live `cron-monitor-failure` workflow's `detectorIds` contains the monitor's detector id (detectors endpoint, query `scheduled-approval-expiry`). Re-read both at flip time.
```

(The work phase may re-wrap lines to the surrounding style; the two copies must stay byte-identical.) Then append to the
ADR "Accepted deviation: cron monitor routing" section one sentence: "Routed 2026-11-07 by PR #12293 (declared, applied on
merge; checklist item 3 states the confirmation it still owes)." Leave the post-deploy verification paragraph and the handover "Other
preconditions" bullet untouched (they are dated, time-bound statements that item 3 does not contradict).

> Superseded 2026-11-07 (review round 1): the text shipped in ADR-309 item 3 and the handover is the reviewed wording, not the
> plan-time draft above; the dated ADR sentence is likewise reworded as an inline `*Updated 2026-11-07 ...*` note.

Lockstep proof (content anchors, not line numbers): extract each copy from the line starting `3. **Route the cron
monitor` up to, not including, the line starting `4. **Real-SDK probe` and `cmp` the two extracts.

Then `bash scripts/markdown-lint.sh --repo-sweep` before committing the markdown edits.

### Phase 3 — PR-time verification (CI is the gate)

The slow local `--affected` battery is NOT awaited (CI is the ship gate); record that in the PR test plan. In CI:
`plan_pr` (infra-validation) shows exactly one resource change, an in-place update of
`sentry_alert.cron_monitor_failure` with `monitor_ids` 24 to 25; the reference gate prints `PASS (N rules, plan ==
alert-reference.json)`; `sentry-audit-gate.yml` may print one advisory Class A warning for the not-yet-bound detector
(expected, self-heals in the apply).

### Phase 4 — After merge (read-only)

1. `apply-sentry-infra.yml` run for the merge commit is green (`gh run list --workflow apply-sentry-infra.yml -L 3`).
2. Read-back: `GET .../workflows/?query=cron-monitor-failure`, select name `cron-monitor-failure`, expect
   `detectorIds | length == 25` and `index("2557403") != null` (baseline before: 24 and null).
3. Confirm the monitor is still `ok` with no incident. No synthetic event, no flag read, no write.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add `sentry_cron_monitor.scheduled_approval_expiry.id` to the sorted `monitor_ids` list and delete its entry from `cron_monitor_alert_unrouted`" [brief] | Phase 1 steps 1-2; Files to Edit `cron-monitor-alerts.tf` | mapped |
| 2 | "Update the ADR-309 flip checklist item 3 text and `flag-create-handover.md` together (they must be edited in lockstep)" [brief] | Phase 2; Files to Edit ADR-309 and handover | mapped |
| 3 | "and the comment above the monitor in `cron-monitors.tf`" [brief] | Phase 1 step 3; Files to Edit `cron-monitors.tf` | mapped |
| 4 | "Guard 1 two-PR check and monitors audit (`sentry-audit-gate.yml`) pass; infra-validation `terraform plan` shows exactly one change" [brief] | Phase 1 step 4, Phase 3, Acceptance Criteria | mapped |
| 5 | "after merge confirm it is green and `monitor_ids` contains the new id via the read-only Sentry call" [brief] | Phase 4, post-merge Acceptance Criteria | mapped |
| 6 | "Nothing here discharges any flip item or creates/flips any flag; do not touch the flag or environment." [brief] | Non-Goals; item-3 wording (status plus re-check, never "discharged") | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cron-monitor-alerts.tf` edit | "add `sentry_cron_monitor.scheduled_approval_expiry.id` to the sorted `monitor_ids` list" | asked |
| ADR-309 item 3 and handover item 3 | "Update the ADR-309 flip checklist item 3 text and `flag-create-handover.md` together" | asked |
| `cron-monitors.tf` comment | "the comment above the monitor in `cron-monitors.tf`" | asked |
| Phase 0 re-read of the monitor and detector | "Precondition met per CTO: latest 100 Sentry check-ins are all ok" | asked (re-verifies the stated precondition at edit time) |
| Phase 4 read-back | "confirm it is green and `monitor_ids` contains the new id via the read-only Sentry call" | asked |
| `alert-reference.json` edit | none | inferred - justification: the plan_pr reference gate (`scripts/sentry-alert-reference-gate.sh`) reds the PR until the committed reference equals the plan projection, and the brief's "infra-validation ... passes" requires it; CTO-ruled in scope |
| One dated sentence in the ADR "Accepted deviation" section | none | inferred - justification: that section says "Until then a dead sweep is not paged" next to an item 3 that now says routing is declared, so the two would contradict; CTO-ruled |

### Split Assessment

- Subsystems touched: 2 - `apps/web-platform/infra/sentry`, `knowledge-base`
- Planned files: 7 (5 edited, 2 created under specs) | Estimated changed lines: about 40
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `grep -c 'sentry_cron_monitor.scheduled_approval_expiry.id' apps/web-platform/infra/sentry/cron-monitor-alerts.tf` prints `1`.
- [ ] `monitor_ids` labels are `LC_ALL=C` sorted and number 25. Command (measured on the current tree: prints 24 and `sorted`):
  `awk '/^  monitor_ids = \[/{f=1;next} f&&/^  \]/{exit} f' apps/web-platform/infra/sentry/cron-monitor-alerts.tf | sed -E 's/^ *sentry_cron_monitor\.([a-z0-9_]+)\.id,/\1/' > "$TMP/ml.txt"; wc -l < "$TMP/ml.txt"; LC_ALL=C sort -c "$TMP/ml.txt" && echo sorted`
- [ ] No line in `cron-monitor-alerts.tf` matches `^\s*scheduled_approval_expiry\s*=` (the unrouted entry is gone) and the three other unrouted entries are byte-unchanged.
- [ ] `jq -r '."cron-monitor-failure".detectorIds | "\(length) \(index("2557403"))"' apps/web-platform/infra/sentry/alert-reference.json` prints `25 <n>` with `<n>` a number (it prints `24 null` on the current tree; `null` means absent); `git diff -U0` of that file shows exactly one added line.
- [ ] `terraform fmt -check` passes in `apps/web-platform/infra/sentry`.
- [ ] Guard 1 (`sentry-cron-monitor-routing-parity.test.ts`) and `sentry-monitor-iac-parity.test.ts` pass.
- [ ] The two item-3 extracts (ADR and handover) are byte-identical, and neither contains the words "discharged", "done" or "closed".
- [ ] The `cron-monitors.tf` comment no longer says routing "follows the two-PR rule" and states the monitor is routed; the resource block itself is unchanged (`git diff -U0 origin/main...HEAD -- apps/web-platform/infra/sentry/cron-monitors.tf | grep '^[-+]' | grep -v '^[-+][-+]' | grep -vE '^[-+]#'` prints nothing).
- [ ] Binding greps print nothing: `git diff origin/main...HEAD -U0 | grep '^+' | grep -E '\b112[0-9]{2}\b' | grep -v 11258` and `git log origin/main..HEAD --format=%B | grep -E '\b112[0-9]{2}\b' | grep -v 11258`.
- [ ] `git diff --name-only origin/main...HEAD` contains none of: `docs/legal`, `plugins/soleur/docs`, `dsar-export-allowlist.ts`, any flag file, any workflow, any script.
- [ ] `bash scripts/markdown-lint.sh --repo-sweep` is clean.
- [ ] CI: infra-validation plan shows exactly one change (in-place update of `cron_monitor_failure`); the alert-reference gate passes.
- [ ] PR body: `Ref #9601` only (closingIssuesReferences empty), a `## Changelog` section, the transient-audit-warning note, the test-plan line that the slow local `--affected` battery was not awaited, ends with the Claude Code attribution line; contains none of the banned words; `ci_cycles` written once, after the final push.

### Post-merge (read-only)

- [ ] `apply-sentry-infra.yml` green for the merge commit.
- [ ] Live `cron-monitor-failure` workflow `detectorIds` has 25 entries including `2557403`.

## Test Scenarios

| Mutation of the change | Expected |
|---|---|
| Leave the label in both `monitor_ids` and the unrouted map | Guard 1 RED (double-listed) |
| Add the element but forget `alert-reference.json` | plan_pr reference gate RED |
| Put the element out of sorted order | the sorted AC RED (and a spurious plan diff ordering) |
| Delete the unrouted entry without adding the element | Guard 1 RED (declared monitor with no home) |
| Edit the ADR copy but not the handover | the byte-identical extract AC RED |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. A mis-edit reds `plan_pr` or `apply-sentry-infra`
  (an internal gate), or leaves the sweep monitor un-emailed as today. The `approval-queue` flag is off, so no live
  approval request depends on the sweep.
- **If this leaks, the user's data / workflow / money is exposed via:** no vector. The diff is an operator-only email
  route, a generated detector id and two doc paragraphs. No user data, credential or workspace content is read or
  written; the live reads are GET-only against Sentry config with an existing infra token.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches apps/web-platform/infra/sentry (a sensitive path) only to add an operator-only cron-monitor email route and its generated detector id; no user data, auth, billing or runtime behaviour changes, and the approval-queue flag stays off.`

## Observability

```yaml
liveness_signal:
  what: "the scheduled-approval-expiry Sentry cron check-in (posted by the cron-approval-expiry Inngest function every 5 min); after this change a missed or errored check-in emails via sentry_alert.cron_monitor_failure"
  cadence: "*/5 * * * * UTC; checkin_margin 30m (max_runtime 10m is inert: the handler posts only ok or error check-ins, never in_progress)"
  alert_target: "email to all active Sentry org members (issue_owners falling through to ActiveMembers), throttled to about one email per monitor group per 24h (frequency_minutes 1441)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitor-alerts.tf (monitor_ids) and cron-monitors.tf (the monitor)"

error_reporting:
  destination: "Sentry issue group per monitor environment (fingerprint crons:{monitor_env.id}); the sweep's own gate_unanswered event keeps its own alert (approval-gate-unanswered)"
  fail_loud: "a failed sweep_approvals() RPC posts a status=error check-in; a dead scheduler pages as a missed check-in after nextCheckInLatest"

failure_modes:
  - mode: "the sweep stops running (Inngest scheduler dead, function dropped or unregistered)"
    detection: "Sentry monitor (cron check-in) missed past nextCheckInLatest"
    alert_route: "sentry_alert.cron_monitor_failure email; this change adds that route (before it, only an un-emailed Sentry issue existed)"
  - mode: "the sweep runs but sweep_approvals() fails"
    detection: "Sentry monitor (cron check-in) status=error, failure_issue_threshold 1"
    alert_route: "sentry_alert.cron_monitor_failure email after this change"
  - mode: "route drift: committed alert-reference.json diverges from live Sentry"
    detection: "daily scheduled-sentry-alert-drift.yml probe (scripts/sentry-alert-live-fidelity.sh)"
    alert_route: "one daily infra-drift GitHub issue naming the regeneration remedy"

logs:
  where: "GitHub Actions run logs (apply-sentry-infra.yml, plan_pr); Sentry cron monitor check-in history"
  retention: "GitHub run retention; Sentry issue retention"

discoverability_test:
  command: grep -c 'sentry_cron_monitor.scheduled_approval_expiry.id' apps/web-platform/infra/sentry/cron-monitor-alerts.tf
  expected_output: "1"
```

The probe prints `0` before the change (the label appears only as an unrouted-map key, which the pattern does not
match) and `1` after. It proves only that the repo text changed; the live binding is proven by the Phase 4 read-back
(`workflows/?query=cron-monitor-failure`: 25 detector ids including `2557403`), the authoritative probe for `liveness_signal`.

## Encryption Posture

Not applicable: no persistent data store and no new cross-component connection. Detection fires on `\.tf$`, but the
resource set is unchanged (one list element added to an existing alert, one locals-map entry removed).

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/sentry/cron-monitor-alerts.tf` only (existing root, existing R2 backend, existing providers).
No new variables, secrets or providers.

### Apply path

`apply-sentry-infra.yml` applies on merge: an in-place update of `sentry_alert.cron_monitor_failure`. No downtime, no
replace; the rule keeps firing on its other 24 detectors throughout.

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner is involved.

### Distinctness / drift safeguards

Single Sentry org. `environment` stays under `lifecycle.ignore_changes`, unchanged. Drift between the committed
reference and live Sentry is covered by the daily drift probe and the plan_pr reference gate.

### Vendor-tier reality check

No tier gate involved; the detector already exists and the workflow already binds 24 detectors.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an infrastructure alert-routing change plus two engineering-doc paragraphs. No
UI surface, no legal text, no schema, no auth. (CTO already ruled on the three technical forks; see
decision-challenges.md.)

## Non-Goals

- Creating, flipping or reading any feature flag, `AGENT_OUTER_WRAP`, or any environment.
- Discharging any other ADR-309 flip item; adding a Better Stack monitor; adding a test or a new alert rule.
- Editing the epic body, `docs/legal`, `plugins/soleur/docs`, workflows or scripts.
- Sending a synthetic check-in or event (delivery proof of the email is out of scope; rule config is proven by the
  read-back).

## Sharp Edges

- The brief's file list omits `alert-reference.json`; without it `plan_pr` is red. It is in Files to Edit.
- The id `2557403` is the LIVE detector id, not derivable from the repo; Phase 0 re-reads it.
- Do not renumber ADR checklist items: items 8 and 12 cite each other by number and other docs cite item numbers.
- The ADR/handover item-3 copies must stay byte-identical; assert by content anchor, not line number.
- Never write the egress-audit enablement issue number anywhere; run both binding greps before each push.
- A plan whose `## User-Brand Impact` is empty fails deepen-plan; it is filled above.
