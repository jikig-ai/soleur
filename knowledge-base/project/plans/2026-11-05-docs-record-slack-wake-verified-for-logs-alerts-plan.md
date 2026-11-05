---
title: "docs: record the verified Slack wake path for Better Stack Logs alerts"
date: 2026-11-05
slug: record-slack-wake-verified-for-logs-alerts
branch: feat-one-shot-10455-slack-wake-verified-docs
issue: 10455
type: docs
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-11-05
**Scope of the pass:** proportionate to a four-file markdown change. The skill's full agent fan-out (every
skill, learning, research and review agent) was NOT run: the plan-review panel (DHH, Kieran, code-simplicity)
and the CTO ruling already covered the design, and a wide fan-out over a wording change adds cost, not recall.
What ran instead: the deepen-plan halt gates and the quality-check list, done by direct verification.

### Gate results

- 4.6 User-Brand Impact: section present, threshold `none`, diff touches no sensitive path (knowledge-base only).
- 4.7 Observability, 4.10 Encryption Posture, 4.11 Guard Contract, 4.13 Task Design, 4.9 UI wireframe, 4.55
  Downtime: not triggered (no code, infra, store, guard, UI or serving-surface change). 4.5 Network-outage: no
  trigger pattern in the plan.
- 4.8 PAT-shaped variables: no match.
- 4.12 Scope Check: one unfenced `## Scope Check`, all three subsections present, no `unmapped` Status cell, no
  empty justification, `Recommendation:` line present. The review panel's `inferred` relabel of the ADR-218 and
  PIR rows is in place with justifications.

### Quality checks done live

- Cited issues: #10455 OPEN, #12142 OPEN (this branch's draft PR), #10453 / #10445 / #9168 CLOSED (historical
  context only, none cited as a blocker), #10548 OPEN (not edited).
- Cited rule ids exist as active rules: `cq-cite-content-anchor-not-line-number`,
  `hr-always-read-a-file-before-editing-it`, `hr-no-dashboard-eyeball-pull-data-yourself`.
- Cited ADRs exist: ADR-218, ADR-260, ADR-283, ADR-298. Attribution claims re-read from the files: ADR-298 says
  the Oct-22 heartbeat incidents were posted to the channel and still went unseen; ADR-283 names `#error-found`;
  the 2026-10-19 section of `canary-probe-set.md` says all 17 Logs alerts carried a team-level escalation target;
  the `faithful_canary_sandbox_broken` entry is the deploy-time SDK Bash smoke alert.
- Cited test scripts and the lint exist at the stated paths; the three guards in AC 7 read the touched
  runbooks (anchor resolution, outer-wrap token scan) and none asserts runbook wake-path prose.

### New considerations from the pass

- The "Current team" claim now cites the repo-recorded 2026-10-19 read as corroboration of the dashboard
  statement instead of resting on the dashboard alone.
- Self-grep scope: ACs 2 and 3 grep `knowledge-base/engineering/**` only, so the plan and `tasks.md` (which quote
  the stale phrases) are outside the scan by construction.

## Overview

Item 4 of the post-incident follow-up list in #10455 ("Verify the Slack wake path (ADR-260) across all
Better Stack alerts") is answered. On 2026-11-05 the account owner read the Better Stack dashboard: the
Slack integration (Incidents product, single-channel mode, channel `#error-found`, workspace Soleur.ai)
is connected, and the incident for the Logs alert `soleur-egress-gw-probe-fail-prd` (2026-11-04) shows
Slack posts on its timeline, at incident start and at auto-resolve, next to the email sends. Every Logs
alert shares the same "Current team" escalation target and the integration is account-wide, so Logs-alert
incidents reach Slack. For `agent_sandbox_bash_denial` that is inferred from the shared route, not
separately observed.

Repo text still says the Logs-alert wake path is email only and Slack is unverified. This plan changes
only that text, so the repo records the dated result, its evidence source, and its limits. It is a
docs-only change: four markdown files, no code, no Terraform, no Better Stack change, no production write.
`Ref #10455` only; the issue stays open (nine items remain).

Spec note: no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (fail-closed).

## Research Insights

### Premise Validation (Phase 0.6)

- `#10455` is OPEN. Its item 4 is already ticked in the issue body ("Verified 2026-11-05 in the Better Stack
  dashboard ... Slack posts on its timeline next to the email sends"); the issue text needs no edit.
- Collision pre-check: the only open change naming `#10455` is PR #12142, which is this branch's own draft
  PR (no files yet). Two foreign `test-all.sh` processes belong to the `feat-one-shot-10390-ci-hygiene-batch`
  worktree and touch no file in this plan. No live duplicate.
- Every cited file exists on this branch: `betterstack-log-query.md`, `canary-probe-set.md`,
  `app-database-readiness-alarm.md`, `betterstack-logs-alerts.tf`, `issue-alerts.tf`. ADR-260 and ADR-218
  exist. The PIR is `hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md`.
- ADR corpus check (the mechanism is "append a dated record"): ADR-218 states its amendments are
  "Appended, not edited", and its later amendments say "The text above is unchanged; where it conflicts
  with this section, this section wins". ADR-283 already records that Slack posts appear on an
  **Uptime-product** heartbeat incident (read from the Uptime API); that does not cover Logs-alert incidents
  and is left alone. ADR-298 records that the Oct-22 heartbeat incidents were posted to the channel and
  still went unseen, which is the reason the limits below matter.

### Property List and Cut List (Phase 0.6b)

Properties the change must buy:

1. A reader of any Logs-alert runbook entry can learn whether a Slack post accompanies the email, and on
   what evidence.
2. The dated result states how it was established (dashboard read), what is observed versus inferred, and
   what it does not prove (phone push; escalation policies).
3. No statement about Better Stack Logs alerts claims Slack is unverified, and none claims more than was
   observed.
4. Statements that are still true (the alert's own channel flags, Sentry rules with no Slack action) are
   not disturbed, so the tests that pin them stay true.

Mechanisms: the brief proposes none beyond "update the text". The only mechanism choices are where the
record lives and what form it takes; both were ruled (see `decision-challenges.md`).

Cut List:

- Editing the six `email only` comments in `betterstack-logs-alerts.tf` -> property 3 -> not needed: they
  describe the alert's own channel flags, which are still true; an infra-path change also triggers the
  production apply workflow. (CTO ruling A.)
- Copying the full result into every runbook/ADR site -> property 1 -> already covered by one canonical
  record plus pointers. (CTO ruling C.)
- A new Better Stack API probe to re-prove the result -> property 2 -> the brief rules out API proof and any
  Better Stack change.

### Live-text inventory (git grep, 2026-11-05)

Stale wake-path statements (in scope):

| # | File | Statement | Action |
|---|------|-----------|--------|
| 1 | `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`, entry `logtail_exploration_alert.agent_sandbox_bash_denial` | "Wake path: email only ... Slack wake ... NOT been verified for this alert ... 2026-10-19 read-only check ..." | replace with a one-sentence pointer to the record |
| 1b | same file, entry `logtail_exploration_alert.faithful_canary_sandbox_broken` | "Wake path: email only (the same unverified Slack caveat as the siblings above)" | replace with a short pointer |
| 2 | `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`, "Tenant-visible helper notice" paragraph | "The wake path for both alerts is email-only on the Better Stack free tier until the ADR-260 Slack integration is verified." | rewrite to point at the new record |
| 2b | same file, end of "Slack wake check, run 2026-10-19" section | "What an agent cannot establish is whether the dashboard routes team alerts to the connected Slack workspace ... it stays open on #10455." | keep as history; add the dated successor paragraph directly after it |
| 3 | `knowledge-base/engineering/architecture/decisions/ADR-218-...logtail-provider.md`, bullet "Wake path." in the 2026-10-19 amendment | "Email on the free tier; the Slack wake of ADR-260 is not verified for Logs alerts" | append a dated amendment at the end; leave the old bullet unchanged |
| 4 | `knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md`, action-item row "(item 4)" | "...the new alerts are email-only until then \| open" | flip the row to done |

Deliberately out of scope (statement stays true or is not about Better Stack Logs alerts):

- `apps/web-platform/infra/betterstack-logs-alerts.tf` comments (L723, L783, L828, L1300, L1785, L1881),
  `uptime-alerts.tf`, `web-probe.tf`: channel-flag prose; any `apps/web-platform/infra/**` edit triggers the
  production apply workflow and the infra validate suite. `cron-monitors.tf` L507 is a historical
  "2026-10-22 email-only incident delivery" fact.
- `apps/web-platform/infra/sentry/issue-alerts.tf` L1769 and L1825, and the `canary-probe-set.md` paragraph
  for Sentry rule `masked-dir-precreate-failed`: Sentry rules with no Slack action.
- `registry-clientip-rfc1918-7530.md`, `workspaces-luks-cutover-6604.md`, `monitor-send-failed-alert.md`,
  `betterstack-log-query.md` entries that say "email only" about channel flags, ADR-211/ADR-222, the PIR
  L141 parenthetical "(email)": channel-flag statements, still true.
- `app-database-readiness-alarm.md` (Delivery-path check): Uptime-product monitors; it makes no Logs-alert
  claim and "non-empty means wired" is still true. Review panel (3 of 3 reviewers) cut the pointer edit.
- ADR-283 (the Uptime heartbeat), ADR-260 body, `model.c4`: not statements about Logs alerts.

### Test and guard hazards found

- Tests pin the alert channel flags; one assertion message calls them "the runbook's email-only wake-path
  statement" (`apps/web-platform/test/infra/sandbox-alerts.test.sh`; siblings: `registry-clientip-not-rfc1918-alert.test.sh`,
  `inngest-cutover-flip-silent-alert.test.sh`, `egress-gw-alert.test.sh`). None greps runbook prose, but the
  canonical record keeps one sentence that the alert's own flags stay `email = true` with
  push/call/sms/critical_alert false, so that message stays true.
- `bwrap-probe-rollback-alert.test.sh` and `faithful-canary-sandbox-alert.test.sh` resolve a runbook anchor
  to a real heading in `canary-probe-set.md`. Do not rename or add a heading that shifts a slug; the new
  record is a bold-led paragraph, like the 2026-10-19 one it follows.
- `apps/web-platform/infra/sandbox-canary-soak.test.sh` scans the tree for the `sandbox-canary-outer-wrap`
  op token (excluded for `canary-probe-set.md`, ADR-218, `betterstack-log-query.md` and the PIR dir only). The
  new text does not need that token and must not use it.
- `scripts/lint-infra-no-human-steps.py` scans plans/specs/runbooks for a human-actor token next to an
  infra imperative on one line; write "the account owner read the dashboard", never an owner-run apply.

### Institutional learnings applied

- `2026-09-14-the-sweep-that-retired-false-sentences-wrote-new-ones-from-my-own-issue-comment.md`: a sweep
  that retires false sentences can write new ones. Every new sentence below is derived from the dated
  observation, with each claim labelled observed or inferred; nothing is copied from issue prose.
- `2026-08-25-i-wrote-the-evidence-down-and-then-concluded-the-opposite.md`: a half-true summary ends
  inquiry. The record says exactly which incident was observed and which alerts are inferred.
- AGENTS `cq-cite-content-anchor-not-line-number`: pointers cite the paragraph's bold lead-in
  ("Slack wake check, dashboard read 2026-11-05"), never a line number.
- AGENTS `hr-no-dashboard-eyeball-pull-data-yourself`: the dashboard is the only source that shows the
  timeline here; the 2026-10-19 API reads were exhausted (they found the integration and no link to a Logs
  alert). The record states that explicitly rather than implying the API confirms it.

## Research Reconciliation: Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Logs alerts are described as "email-only / Slack-unverified" in `betterstack-log-query.md`, `canary-probe-set.md`, `app-database-readiness-alarm.md`, `.tf` comments and `issue-alerts.tf` comments | `app-database-readiness-alarm.md` makes no Logs-alert claim (it covers Uptime monitors and already says Slack is the primary wake path); `.tf` "email only" comments describe channel flags, not the Slack route; the two `issue-alerts.tf` hits are Sentry rules | Edit only the two runbooks for Logs-alert claims; no edit to the readiness runbook (review-panel cut); no `.tf` edit |
| "Start with a git grep ... in runbooks, `.tf` and `issue-alerts.tf`" | Two stale places sit outside that list: ADR-218 (Wake path bullet) and the PIR action-item row | Include both (they state the same stale fact), per the CTO ruling on boundary |
| "the API cannot prove it" | True for the 2026-10-19 read-only reads (integration exists; no field ties a Logs alert to a Slack channel). ADR-283 shows the Uptime incident timeline does expose "posted to #error-found" events for an Uptime-product incident | State the evidence source as a dashboard read; do not run a new API probe (brief forbids Better Stack changes; reads are not needed) |

## Implementation Phases

All edits are markdown. Re-read each file around the edit site first (`hr-always-read-a-file-before-editing-it`),
and cite sections by content, not line number. The runbooks wrap at about 130 columns and some quoted spans
break across lines with a two-space indent ("**Wake path: email" ends one line, "only.**" starts the next), so
match multi-line spans exactly or replace by a short scripted substitution; a single-spaced quote will not match.

### Phase 1: the canonical record (`canary-probe-set.md`)

1. In the paragraph that ends "...the email only prompts the check above. The wake path for both alerts is
   email-only on the Better Stack free tier until the ADR-260 Slack integration is verified.", replace the last
   sentence with: "Wake path: email, plus a Slack post (inferred); see **Slack wake check, dashboard read
   2026-11-05** below."
2. Leave the **Slack wake check, run 2026-10-19 (#10455 d)** section unchanged, including its closing
   "What an agent cannot establish ... stays open on #10455." paragraph (history).
3. Directly after that closing paragraph, add the successor paragraph (bold lead-in, no new heading, so no
   slug shifts):

   > **Slack wake check, dashboard read 2026-11-05 (#10455 item 4).** This closes the open point above, from
   > the Better Stack dashboard; the API check of 2026-10-19 found no field tying a Logs alert to a Slack
   > channel and was not re-run. **Observed:** the Slack integration is connected (Incidents product,
   > single-channel mode, channel `#error-found`, workspace Soleur.ai), and the incident for the Logs alert
   > `soleur-egress-gw-probe-fail-prd` (2026-11-04) shows Slack posts on its timeline at incident start and at
   > auto-resolve, next to the email sends. **Inferred:** every Logs alert has the same "Current team"
   > escalation target (the 2026-10-19 read above shows a team-level `escalation_target` on all 17) and the
   > integration is account-wide, so Logs-alert incidents reach Slack, including `agent_sandbox_bash_denial`
   > and `faithful_canary_sandbox_broken`, which were not separately observed. **Unchanged:** each alert's
   > own flags are still `email = true` with `push`, `call`, `sms` and `critical_alert` false and no
   > escalation policy; the Slack post comes from the Incidents integration, not from an alert flag.
   > **Limits:** a Slack post is not proof of a phone push or a read (a push depends on the Slack client's
   > notification settings; the Oct-22 incidents were posted and still went unseen, ADR-298), and Logs-alert
   > escalation policies stay gated off on the free tier (`var.betterstack_paid_tier`). To repeat the check,
   > read the timeline of a recent Logs-alert incident in the dashboard.

   The wording must not name any person; the incident timeline lists people and none appears here.

### Phase 2: pointers in `betterstack-log-query.md`

1. `agent_sandbox_bash_denial` entry: replace the span from "**Wake path: email only.** On the free tier the
   alert emails the team and nothing else; ..." through "...in `canary-probe-set.md`, "Slack wake check".)"
   with: "**Wake path: email (the alert's own channel) plus an inferred Slack post;** see `canary-probe-set.md`,
   \"Slack wake check, dashboard read 2026-11-05\"." Keep "**Accepted limitation:** ..." intact.
2. `faithful_canary_sandbox_broken` entry: replace "**Wake path: email only** (the same unverified Slack
   caveat as the siblings above)." with "**Wake path: email plus an inferred Slack post** (same record)." and keep
   the "**Positive control ...**" text that follows.
3. Do not touch other entries that say "email only" about channel flags.

### Phase 3: ADR-218 amendment

Append at the end of the file, after the 2026-10-30 amendment, `## Amendment — 2026-11-05 (#10455): the Slack
post for Logs-alert incidents is observed`, in three or four lines: a dated amendment, "The text above is
unchanged; where it conflicts with this section, this section wins"; the "Wake path" bullet of the 2026-10-19
(#10453) amendment ("the Slack wake of ADR-260 is not verified for Logs alerts") is superseded by the
2026-11-05 dashboard read, recorded in `canary-probe-set.md` under "Slack wake check, dashboard read
2026-11-05"; a factual correction, no decision changes. Do not restate the evidence here.

### Phase 4: post-mortem row

In the hosted-agent PIR's action-item table, replace the row
`| #10455 | (item 4) Verify the Slack wake path (ADR-260) across all Better Stack alerts; the new alerts are email-only until then | open |`
with the same item text, then: verified in the dashboard, a Slack post is observed on a Logs-alert incident
through the account-wide integration while the alerts' own channel stays email (see `canary-probe-set.md`,
"Slack wake check, dashboard read 2026-11-05"), status `done 2026-11-05 (verified in the dashboard)`. Leave
the L141 "(`agent_sandbox_bash_denial`, email)" parenthetical, which describes the alert's channel.

### Phase 5: verification (no writes)

Run the Acceptance Criteria checks. Open the PR with `Ref #10455` (not `Closes`), and state in the body that
`.tf` was deliberately left untouched and why.

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`
- `knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md`

## Files to Create

None beyond this planning set (`tasks.md`, `decision-challenges.md`).

## Open Code-Review Overlap

None. 95 open `code-review` issues were queried; none names any of the four files.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "update the repo text that still says Logs alerts are email-only / Slack-unverified so it records this dated result and the evidence source" [brief] | Phases 1-4 | mapped |
| 2 | "(read the incident timeline in the dashboard; the API cannot prove it)" [brief] | Phase 1 successor paragraph, evidence-source sentence | mapped |
| 3 | "Start with a git grep for "email-only", "until the ADR-260 Slack", "Slack wake" and "unverified" in ... runbooks ... apps/web-platform/infra/*.tf comments and apps/web-platform/infra/sentry/issue-alerts.tf comments" [brief] | Research Insights inventory (a grep scope, not an edit mandate) | mapped |
| 4 | "fix only statements about Better Stack Logs alerts, and leave Sentry rules that genuinely have no Slack action as they are" [brief] | Phases 1-4; out-of-scope list; no `.tf` edit | mapped |
| 5 | "Do NOT include any person's name from the incident timeline." [brief] | Phase 1 wording note; AC 5 | mapped |
| 6 | "a Slack post is not proof of a phone push (depends on the Slack client's notification settings), and Logs-alert escalation policies remain gated off on the free tier" [brief] | Phase 1 **Limits** | mapped |
| 7 | "Do not close #10455 (nine items remain); reference it with Ref only." [brief] | Phase 5 PR body; AC 6 | mapped |
| 8 | "No production writes, no Better Stack changes." [brief] | no `.tf`, workflow or script file edited; AC 1 | mapped |
| 9 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/<branch>/decision-challenges.md" [brief] | `decision-challenges.md` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `canary-probe-set.md` edit | "update the repo text that still says Logs alerts are email-only / Slack-unverified" (ask 1) | asked |
| `betterstack-log-query.md` edit | "betterstack-log-query.md, canary-probe-set.md" (ask 3) | asked |
| ADR-218 amendment | — | inferred — justification: the same stale statement ("Slack wake ... not verified for Logs alerts") lives there, and ask 1 covers "the repo text that still says" it; left alone it contradicts the new record |
| PIR action-item row | — | inferred — justification: same stale fact in an action-item status column ("email-only until then \| open"); ask 1 covers it |
| `decision-challenges.md` | ask 9 | asked |

### Split Assessment

- Subsystems touched: 1 (knowledge-base docs: `engineering/operations`, `engineering/architecture`)
- Planned files: 4 edited | Estimated changed lines: about 30 added, about 12 replaced
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; the change is internal runbook text. The
internal failure is a responder reading "Slack posts accompany the email" for an alert where it was only
inferred, or reading "Slack unverified" and discounting a channel that is live.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector; the text carries
the Slack channel name (already present in ADR-283) and the workspace name only, no token, no person, no user data.

**Brand-survival threshold:** none

threshold: none, reason: documentation-only change to internal runbooks, one ADR and one post-mortem row; no code, schema, auth, API or user-visible surface is touched.

## Acceptance Criteria

### Pre-merge (PR)

- [x] 1. The diff is markdown-only: `git diff --name-only origin/main...HEAD` lists only `knowledge-base/**.md`;
  `git diff origin/main...HEAD --stat -- apps .github scripts` is empty (no `.tf`, workflow or script edit).
- [x] 2. The stale phrases are gone from the runbooks:
  `git grep -n -E "until the ADR-260 Slack integration is verified|NOT been verified for this alert|same unverified Slack caveat" -- knowledge-base/engineering/operations/runbooks`
  returns nothing, and the 2026-10-19 history paragraphs plus the ADR-218 old "Wake path" bullet are unchanged
  (`git diff` shows only additions after them).
- [x] 3. The record exists once and is pointed to: `git grep -l "dashboard read 2026-11-05" -- knowledge-base/engineering`
  lists `canary-probe-set.md`, `betterstack-log-query.md`, ADR-218 and the PIR (match the short single-line anchor
  "dashboard read 2026-11-05"; wrapped lines can hide the longer phrase).
- [x] 4. The canonical paragraph is complete. Extract it first, then read it:
  `awk '/^\*\*Slack wake check, dashboard read 2026-11-05/,/^$/' knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
  and confirm it labels Observed (`soleur-egress-gw-probe-fail-prd`) apart from Inferred
  (`agent_sandbox_bash_denial`, `faithful_canary_sandbox_broken`), states the flags are still `email = true`
  with push/call/sms/critical_alert false, and states the two limits (no proof of a phone push; escalation
  policies gated off on the free tier).
- [x] 5. No person's name in any added line: read `git diff origin/main...HEAD -U0 | grep '^+'`; the only proper
  nouns allowed are `Soleur.ai`, `Better Stack`, `Slack`, `ADR-*` and the alert and channel names above.
- [ ] 6. PR body: `Ref #10455`, no `Closes`/`Fixes`/`Resolves` for it; says `.tf` deliberately untouched and why;
  Sentry rule text (the `masked-dir-precreate-failed` paragraph) is unchanged.
- [x] 7. Guards still pass: `bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh`,
  `bash apps/web-platform/test/infra/bwrap-probe-rollback-alert.test.sh` (runbook anchor resolution),
  `bash apps/web-platform/infra/sandbox-canary-soak.test.sh` (outer-wrap token scan), and
  `python3 scripts/lint-infra-no-human-steps.py` on the touched runbooks and the planning set.

### Post-merge

None. `#10455` stays open; its remaining unticked items are unaffected.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an internal runbook/ADR/post-mortem wording change recording an
already-observed vendor-integration fact. No UI surface, no schema, no regulated-data surface (no GDPR gate),
no new infrastructure (no IaC routing), no new vendor, no architectural decision (the model already shows the
`betterstack -> slack -> founder` edge, so no C4 change; the ADR-218 amendment corrects a status, it decides
nothing). The Observability, Encryption Posture, Guard Contract and Task Design gates skip silently: the
change touches no code, infra, store or guard.

## Test Scenarios

This change ships no behavior, so the scenarios are read-checks on the final text:

1. A reader opens the `agent_sandbox_bash_denial` entry and learns: email is the alert's own channel, a Slack
   post is inferred from an observed sibling incident, and it is not proof of a phone push.
2. A reader opens `canary-probe-set.md` and finds both the 2026-10-19 API result and the 2026-11-05 dashboard
   result, in date order, with the second saying it closes the first's open point.
3. A reader of ADR-218's 2026-10-19 amendment still sees the old bullet, and the last section tells them it is
   superseded.
4. A reader of the PIR sees item 4 as done with the date and evidence source.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6;
  this one carries threshold `none` with the scope-out line.
- Do not turn "inferred" into "verified" for `agent_sandbox_bash_denial` or `faithful_canary_sandbox_broken`
  while editing; only `soleur-egress-gw-probe-fail-prd` was observed.
- Do not weaken the channel-flag statements ("email only" as to an alert's own flags): four test suites assert
  those flags and cite the runbook's wording.
- Do not edit inside the 2026-10-19 history text or the ADR-218 old bullet; add after them.
- The `.tf` comments were left alone on purpose. If a later reviewer finds one that says Slack is unverified or
  that nobody is notified (rather than describing flags), that is a separate infra-touching PR.
