---
title: "docs: a lower_than silence incident may stay open after the data returns"
date: 2026-11-02
slug: lower-than-silence-incident-stays-open-note
branch: feat-one-shot-silent-incident-docs-note
issue: 11820
type: docs
lane: cross-domain
detail_level: minimal
---

# docs: a `lower_than` silence incident may stay open after the data returns

Lane note: no spec.md exists for this branch, so `lane:` defaulted to `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-02
**Method:** the halt gates (Phases 4.6 to 4.13) were run mechanically against this file, and the load-bearing claims were
re-measured against the tree. The 40-agent research fan-out was not run: the change is one sentence in three places, there
is no external API, library or UI to research, and every residual risk is a guard-anchor question that a grep answers.

### Key Improvements

1. Measured the pristine baseline: the flip suite passes `41 passed, 0 failed` in about 4 s on `origin/main`, so Phase 3 is
   cheap and a red suite after the edit is attributable to the edit.
2. Measured the three single-occurrence anchors on `origin/main` (each file-wide count is 1): `inngest_cutover_flip_silent_sql = <<-SQL`,
   `inngest_luks_key_probe_runbook_url =`, `EXPECTED during an owner-authorized inngest-host-replace`. Phase 2 now forbids
   reproducing them and lists the same constraint for two more file-wide counters found in this pass (below).
3. Found two further file-wide counters the first draft did not name: `egress-gw-alert.test.sh` counts `<name>_sql = <<-SQL` openers and
   `resource "<type>" "<name>"` headers file-wide ("decoy copies count", a `#`-wrapped copy still counts), and
   `logs-alert-query-period-ceiling.test.sh` counts `resource "logtail_exploration_alert" `. The new comment therefore carries
   no `resource "` text and no `<<-SQL` text.
4. Confirmed the insertion point: the `WINDOW.` comment paragraph ends on the line directly above `locals {` (no blank line between),
   so the new paragraph keeps that adjacency; no blank line is added or removed.
5. Confirmed the discoverability command passes the probe-verb gate (`probe-verb-gate.sh` exit 0) and finishes well inside 15 s.

### New Considerations Discovered

- The `.tf` extension triggers Phase 4.10 literally; the plan adds a short `## Encryption Posture` section stating that no store
  or connection is introduced (plan Phase 2.11 would skip it silently; the section makes the deepen gate pass without ambiguity).
- The mirror workflow closes a mirror issue with "resolved upstream" when the incident leaves Better Stack's open list, so the
  manual resolve test, once the owner authorizes it, will let the mirror close issues 11047 and 11869 as a side effect. Neither PR text nor commit may
  pre-empt that with a closing keyword (already an Acceptance Criterion).

## Overview

Docs-only follow-up on #11820 (mirror issue #11869), ruled by the CTO agent on 2026-11-02: leave the
silence alerts as they are, document the class finding, no predicate rewrite, no pause. Add one note to
three places so the next reader of a Better Stack "silent" incident does not read "open" as "currently silent":

> A `lower_than` silence incident may stay open after the data returns. Open does not mean currently silent. Verify with `betterstack-query.sh`, and resolve manually.

Places (the sentence is copied verbatim, backticks included):

1. the `inngest_cutover_flip_silent` entry in `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`;
2. the `egress_gw_probe_silent` entry in the same file;
3. the comment block above the flip alert in `apps/web-platform/infra/betterstack-logs-alerts.tf`
   (comment lines only; the Terraform plan must show no resource change).

No Better Stack incident is resolved, no predicate changes, no alert is paused. The manual resolve test is a
Better Stack write that needs the owner's per-command go-ahead; it is pending and is named as pending in the PR body.

## Research Insights

### Premise Validation (Phase 0.6)

- `#11820`: OPEN ("silence alert for the cutover-flip unit ... ADR-282 flip-token residual"), no closing PR. Holds.
- `#11869`: OPEN, the CI mirror issue `[ci/betterstack-incident] soleur-inngest-cutover-flip-silent-prd`, opened 2026-11-02. Holds.
- Both alerts exist on `origin/main` (`betterstack-logs-alerts.tf`: `egress_gw_probe_silent` at the
  `logtail_exploration_alert` resource, `inngest_cutover_flip_silent` comment block ending just above its `locals {`), and both
  runbook entries exist (`betterstack-log-query.md`, bullets for each alert name). Holds.
- Evidence check against the mirror history (`gh issue list --search "[ci/betterstack-incident] in:title"`, 18 rows):
  - `#11047` (`soleur-egress-gw-probe-silent-prd`, incident `1031046761`) is OPEN. Its body records `Started: 2026-10-12T20:15:00Z`,
    `Detected: 2026-10-25 03:53 UTC` (the mirror workflow began seeing it on the 25th; Better Stack's start time is the 12th).
  - `#11869` (`soleur-inngest-cutover-flip-silent-prd`, incident `1045365287`) is OPEN.
  - `#11048` (`luks-monitor-host-timer-dark`) and `#11049` (`claude-cost-capture-dark`) closed 2026-10-31 20:47 UTC with
    "resolved upstream", which is the retirement of those alerts (the runbook records the luks one as replaced by a heartbeat armed
    2026-10-31, #11631), not an auto-resolve while live.
  - `#11151` (`egress-gw-probe-fail`, the `higher_than` twin) opened and closed on 2026-10-26.
  - The other closed rows are uptime monitors or heartbeats.
  The "30 minutes" figure for the twin was verified from the issue timestamps (created 09:16:31Z, closed 09:46:48Z; a mirror-issue
  lifetime, not an incident duration). The "healthy data" statements were re-read read-only in the work phase on 2026-11-02 (flip: 11
  object rows in the prior hour; egress: 22 probe rows) and are recorded in `tasks.md` task 3.3. Review also showed the mirror has
  only run since 2026-10-24 (first mirror issue 2026-10-25), so "never auto-resolved" is stated as "no `lower_than` incident has resolved while its alert was live".
- Collision pre-check (`collision-precheck.sh 11820` and `11869`): no open PR names either issue; the two foreign hits are
  `test-all.sh` processes of an unrelated worktree (`feat-prod-readiness-gap-analysis`). No duplicate vehicle.
- ADR corpus: no ADR decides how to document an incident that outlives its signal. `ADR-218` (native Better Stack alerts are
  Terraform-managed) governs the `.tf` resources and is untouched. No mechanism is proposed that an ADR rejected.

### Property List and Cut List (Phase 0.6b)

Properties the ask buys:

- P1: a reader of either runbook entry learns that an open silence incident is not proof the signal is currently silent.
- P2: a reader of the `.tf` comment block above the flip alert learns the same.
- P3: the reader is told how to check (`betterstack-query.sh`) and what to do about it (resolve manually).
- P4: nothing changes in Better Stack or Terraform state.
- P5: the sibling guard suites keep passing, in particular their single-occurrence anchors.

Mechanisms considered and cut:

| Mechanism | Property it would buy | Cut because |
|---|---|---|
| Rewrite the predicate or add `recovery_period` so the incident auto-resolves | the incident closes itself | The CTO ruled "leave the alert as is". It also changes a resource (violates P4). |
| Pause the alert | stops the open incident | CTO ruled no pause; a paused liveness alert is blind. |
| New drift guard asserting the sentence exists | P1-P3 stay true | Not asked. Existing guards already pin the runbook row's presence; a prose-presence guard is more machinery than a one-sentence note. |
| Put the sentence in `incident_cause` (the email text) | the emailed reader sees it | It is a resource attribute: it changes the plan (violates P4) and the flip guard anchors on that string. |
| Resolve incidents 1031046761 and 1045365287 now | clean incident list | A Better Stack write needing the owner's per-command go-ahead; the brief says do not resolve. |

### Institutional learnings applied

- The sibling `AUTO-RESOLVE WINDOW` comment above `inngest_luks_key_probe_fail` (`.tf`) and the runbook row that points at it
  are the in-repo precedent for recording incident lifecycle beside the alert; this plan follows the same placement.
- Guard suites read this `.tf` by anchored `awk` regions and `s.count(old) == 1` mutation anchors. A comment must not
  reproduce an anchored literal (see Phase 2 and the Sharp Edges).

## Research Reconciliation: brief vs codebase

| Brief or existing text | Reality | Plan response |
|---|---|---|
| "Add one sentence" to each of the three places | The added text is four short sentences, given verbatim by the brief. | Copy it verbatim; it is "the note", not a rewrite. |
| (not in the brief) the flip runbook entry says the replace-window email is "expected; it clears at the first row after boot" | The class finding says such an incident may not clear. `betterstack-log-query.md` line for the flip entry, the `.tf` comment ("That is expected; it clears on its own."), `incident_cause`, and `inngest-server.md` ("it clears on its own once the row arrives") all say the incident clears itself. | Do NOT reword them: it widens scope beyond the brief, and `incident_cause` is a resource attribute (a plan change). The new note sits next to two of them and states the exception. Recorded as an `operator (scope)` row in `decision-challenges.md` so the owner can ask for the reword. |
| Terraform plan "must show no resource change" | The PR `plan` job in `infra-validation.yml` runs `terraform plan` against live state and comments the result; a push to `apps/web-platform/infra/**` also triggers `apply-web-platform-infra.yml`. | Prove comment-only locally (Phase 2), and read the PR plan comment (Acceptance Criteria). |

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
  - `egress_gw_probe_silent` bullet: insert the note as its own line after "...one host's beats cannot mask the other's silence."
    and before "Defined in `apps/web-platform/infra/betterstack-logs-alerts.tf`."
  - `inngest_cutover_flip_silent` bullet: insert the note as its own line after "...(expected; it clears at the first row after boot)."
    and before "To read the rows yourself use ...".
- `apps/web-platform/infra/betterstack-logs-alerts.tf`
  - Add an `INCIDENT LIFECYCLE` comment paragraph to the comment block above the flip alert, after the `WINDOW.` paragraph and
    immediately before `locals {` (the line that precedes `inngest_cutover_flip_silent_sql`). Comment lines only, no blank-line changes
    outside the comment block, no change to any attribute.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-silent-incident-docs-note/decision-challenges.md` (CTO ruling row plus the scope row)
- `knowledge-base/project/specs/feat-one-shot-silent-incident-docs-note/tasks.md`

(This plan file is the third artifact. The work phase touches no other file.)

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` bodies for both edited paths
(`betterstack-log-query.md`, `betterstack-logs-alerts.tf`). Work phase re-runs the two-stage `jq --arg` query and records the result here;
none is expected to be foldable (a one-sentence docs note), and any match is acknowledged, not folded.

## Implementation Phases

### Phase 1 - Runbook entries (P1, P3)

1. Re-read the two bullets (Read tool) so the edit anchors on current text.
2. Insert the verbatim note, indented to the bullet's continuation column (2 spaces), on its own line in each bullet at the positions above.
3. Keep every existing token the guards read: `logtail_exploration_alert.inngest_cutover_flip_silent`,
   `logtail_exploration_alert.egress_gw_probe_silent`.

### Phase 2 - `.tf` comment (P2, P4, P5)

Insert, wrapped at about 100 columns, before `locals {`:

```text
#
# INCIDENT LIFECYCLE (#11820, mirror #11869). A `lower_than` silence incident may stay open after the data returns.
# Open does not mean currently silent. Verify with `betterstack-query.sh`, and resolve manually. The runbook bullets for
# this alert and for egress_gw_probe_silent carry the same note; edit all three together.
# Observed 2026-11-02 (the evidence lines were revised after review; the shipped text in the .tf file is authoritative).
```

Rules for the inserted text (each is a guard-safety constraint):

- Every added line starts with `#`. No attribute, heredoc, or blank non-comment line is touched.
- Do not write the strings `inngest_cutover_flip_silent_sql = <<-SQL`, `inngest_luks_key_probe_runbook_url =`, or
  `EXPECTED during an owner-authorized inngest-host-replace` in the comment: the flip suite's `sql_replace` takes the first
  index of the heredoc opener, and the flip (A11) and luks-key-probe (`old = ...`) mutation anchors require exactly one occurrence
  in the whole file. The comment mentions `egress_gw_probe_fail` and `egress_gw_probe_silent` only as bare names, which no
  guard counts.
- Do not write `resource "` followed by a type, or `<<-SQL`, anywhere in the comment: `egress-gw-alert.test.sh` counts openers and
  resource headers file-wide and counts a `#`-wrapped copy ("decoy copies count"), and `logs-alert-query-period-ceiling.test.sh`
  counts `resource "logtail_exploration_alert" `.
- Do not put the note inside any `resource` or `locals` body.

Comment-only proof (run, do not eyeball):

```bash
git diff -U0 origin/main -- apps/web-platform/infra/betterstack-logs-alerts.tf \
  | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*#'   # must print nothing
terraform fmt -check apps/web-platform/infra/betterstack-logs-alerts.tf
```

### Phase 3 - Verification

Run, in this order, each to exit 0 (the batteries include mutation rows, so allow time):

1. `bash apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh`
2. `bash apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh`
3. `bash apps/web-platform/test/infra/egress-gw-alert.test.sh`
4. `bash apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh`
5. `bash apps/web-platform/infra/betterstack-alert-structure.test.sh`
6. The remaining `apps/web-platform/test/infra/*-alert.test.sh` suites that read the same `.tf` (the list printed by
   `grep -l betterstack-logs-alerts.tf apps/web-platform/test/infra/*.sh`).
7. `bun test plugins/soleur/test/terraform-target-parity.test.ts` (it reads this `.tf`).

Then re-read the live data read-only (`scripts/betterstack-query.sh --since 1h --grep inngest-cutover-flip --limit 500`, and the
egress equivalent) so the "healthy data" statement in the PR body is a fresh measurement, not a quotation. Do not call any Better Stack
write endpoint.

### Phase 4 - Ship notes (for the PR body)

- Body uses `Ref #11820` and `Ref #11869`; never a closing keyword (both issues stay open).
- Evidence block: incidents 1031046761 and 1045365287, the mirror-history finding, the 30-minute twin.
- Pending item: "Manual resolve test (a Better Stack write on incidents 1031046761 / 1045365287) is pending the owner's
  per-command go-ahead; not run in this PR."
- Link the `plan` job's PR comment showing no resource change.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add one sentence to the `inngest_cutover_flip_silent` and `egress_gw_probe_silent` entries in knowledge-base/engineering/operations/runbooks/betterstack-log-query.md" [brief] | Phase 1, Files to Edit (runbook) | mapped |
| 2 | "Add the same note to the comment block above the flip alert in apps/web-platform/infra/betterstack-logs-alerts.tf (comment-only" [brief] | Phase 2, Files to Edit (.tf) | mapped |
| 3 | "the Terraform plan must show no resource change, and the single-occurrence anchors in sibling guard suites ... must still pass" [brief] | Phase 2 proof, Phase 3, Acceptance Criteria | mapped |
| 4 | "Evidence to cite: incident 1031046761 ... the higher_than twin egress_gw_probe_fail resolved in 30 minutes." [brief] | Phase 2 comment evidence lines, Phase 4 PR body | mapped |
| 5 | "Use `Ref #11820` and `Ref #11869`, never Closes." [brief] | Phase 4 | mapped |
| 6 | "Do NOT resolve any Better Stack incident, change the predicate, or pause the alert." [brief] | Cut List, Non-Goals, Acceptance Criteria | mapped |
| 7 | "mention it in the PR body as pending." [brief] | Phase 4 | mapped |
| 8 | "persist rulings as rows of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/feat-one-shot-silent-incident-docs-note/decision-challenges.md" [brief] | Files to Create | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Runbook edit (two bullets) | asks 1 | asked |
| `.tf` comment edit | asks 2, 3 | asked |
| Evidence lines inside the `.tf` comment | "Evidence to cite: incident 1031046761 (egress, no JSONType) is Started/unresolved since 2026-10-12" | asked |
| `decision-challenges.md` | ask 8 | asked |
| Scope row about adjacent "clears on its own" claims | - | inferred - justification: the added note contradicts four neighbouring statements; the owner decides whether to widen scope, so the plan records it instead of editing |
| `tasks.md` | - | inferred - justification: the plan skill derives it; it carries no product change |

### Split Assessment

- Subsystems touched: 2 (knowledge-base runbooks, apps/web-platform/infra)
- Planned files: 2 edited product files plus 3 planning artifacts | Estimated changed lines: about 30
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

**If this lands broken, the user experiences:** nothing. No product surface changes; the worst case is a runbook line or
a `.tf` comment that reads badly or, if a guard anchor were broken, a red CI check on the PR.

**If this leaks, the user's data is exposed via:** no vector. The text names incident ids and issue numbers already in the repo's
public mirror issues; no row content, host address, or token is quoted.

**Brand-survival threshold:** none

threshold: none, reason: comment-only edit under `apps/web-platform/infra/` (a sensitive path) plus a runbook sentence; the
Terraform plan shows no resource change and no code, credential, or state is touched.

## Observability

No new runtime signal is added; the existing alerts are unchanged. The fields below describe the unchanged signal the note
documents, and the discoverability test proves the note is present where a reader of the alert looks.

```yaml
liveness_signal:
  what: existing Better Stack logs alert inngest_cutover_flip_silent (JSON inngest-cutover-flip rows, lower_than 1 over 900 s); unchanged
  cadence: checked every 300 s
  alert_target: email (team address on the free tier)
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf
error_reporting:
  destination: Better Stack incident email plus the CI mirror issue (#11869 for this alert)
  fail_loud: an unreadable alert surfaces as a failed per-merge terraform apply and a red infra-validation plan job
failure_modes:
  - mode: the added comment text reproduces a guard-anchored literal and a sibling suite goes red
    detection: the deploy-script-tests job in infra-validation.yml runs the alert-guard suites on the PR
    alert_route: red required check on the PR
  - mode: the edit is not comment-only and the apply changes a resource
    detection: the infra-validation plan job comments the plan on the PR
    alert_route: PR comment read before merge
logs:
  where: Better Stack Logs (source for the prd hosts), read with scripts/betterstack-query.sh
  retention: per the Better Stack plan, unchanged
discoverability_test:
  command: grep -m1 -o "Open does not mean currently silent" apps/web-platform/infra/betterstack-logs-alerts.tf
  expected_output: Open does not mean currently silent
```

## Encryption Posture

This plan introduces no persistent store and no cross-component connection. The `.tf` file is edited only in comment lines, so no
resource, volume, bucket, queue, log sink, or network edge is created or changed.

```yaml
at_rest: []          # no store introduced; the existing Better Stack source and its posture are untouched
in_transit: []       # no connection introduced; the read-only query script already pins its host allowlist
```

No `exception` block applies (no plaintext exception, no certificate verification switched off).

## Test Scenarios

1. Pristine-tree control: every Phase 3 suite passes on `origin/main` before the edit (their own `[FATAL] instrument control` row does this per suite). Measured in the deepen pass: the flip suite runs `41 passed, 0 failed` in about 4 s.
2. After the edit: the same suites pass; the comment-only diff filter prints nothing; `terraform fmt -check` exits 0.
3. Presence: `grep -c` of the verbatim sentence returns 2 in the runbook (one per entry) and the `.tf` carries it across two comment lines.
4. Anchors: `grep -cF` of `inngest_cutover_flip_silent_sql = <<-SQL`, `inngest_luks_key_probe_runbook_url =` and
   `EXPECTED during an owner-authorized inngest-host-replace` each return 1 (measured on `origin/main`) before and after the edit;
   `grep -c 'resource "logtail_exploration_alert" '` and `grep -c '<<-SQL'` return the same counts before and after.

## Acceptance Criteria

- [x] The verbatim note (`A \`lower_than\` silence incident may stay open after the data returns. Open does not mean currently silent. Verify with \`betterstack-query.sh\`, and resolve manually.`) appears once inside the `egress_gw_probe_silent` bullet and once inside the `inngest_cutover_flip_silent` bullet of `betterstack-log-query.md` (`grep -c 'Open does not mean currently silent' <file>` = 2).
- [x] The same note appears once in the comment block above the flip alert in `betterstack-logs-alerts.tf`, before `locals {` of `inngest_cutover_flip_silent_sql` (`grep -c 'Open does not mean currently silent' <file>` = 1).
- [x] Comment-only: the diff filter in Phase 2 prints nothing and `terraform fmt -check` exits 0.
- [ ] The PR's `plan` job comment shows no resource change for the web-platform root (`No changes` or `0 to add, 0 to change, 0 to destroy`).
- [x] All Phase 3 suites exit 0, including `inngest-cutover-flip-silent-alert.test.sh` and `inngest-luks-key-probe-alert.test.sh`.
- [x] `git diff --name-only origin/main...HEAD` (three-dot; the two-dot form also lists commits main gained since the branch base) lists only the runbook, the `.tf`, and files under `knowledge-base/project/{plans,specs}/`.
- [x] No Better Stack write was made: no incident resolved, no alert paused, no predicate, `query_period`, `operator`, `incident_cause` or other attribute edited.
- [ ] PR body uses `Ref #11820` and `Ref #11869` (no closing keyword anywhere), cites the evidence, and lists the manual resolve test as pending the owner's per-command go-ahead.
- [x] `decision-challenges.md` carries a `## Decision Classes` table with the CTO row (`Ruled by CTO agent, 2026-11-02: ...`).

## Non-Goals

- Rewriting the predicate, adding `recovery_period`, or pausing either alert (CTO ruling).
- Resolving incidents 1031046761 or 1045365287, or running the manual resolve test (owner's per-command go-ahead).
- Rewording the neighbouring "clears on its own" statements in `incident_cause`, `inngest-server.md`, and the existing flip bullet
  parenthetical (recorded in `decision-challenges.md` for the owner).
- Changing the CI mirror workflow's close behaviour.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - infrastructure and runbook documentation change. The engineering decision was
already ruled by the CTO agent (recorded in `decision-challenges.md`); no UI surface, no regulated-data surface, no new
store or connection, no architectural decision (no ADR or C4 change), no new guard. GDPR and Guard Contract gates skip
silently; the Encryption Posture section above states the absence explicitly because the edited file ends in `.tf`.

## Sharp Edges

- The guard suites read the `.tf` three ways: anchored `awk` regions from a `resource`/`locals` opener, whole-file `grep -c`,
  and Python `s.count(old) == 1`. A comment that repeats an anchored literal turns a single-occurrence anchor into two and the
  suite fails with "anchor drift". Re-run the three `grep -c` anchor checks in Test Scenarios 4 after the edit.
- Do not add a blank line or reflow neighbouring comment lines: the diff filter in Phase 2 treats any non-`#` changed line as a
  failure, and a reflow makes the review diff noisy.
- Do not paste the note into `incident_cause`: it is a resource attribute and would make the plan non-empty.
- Merging a `.tf` change under `apps/web-platform/infra/**` triggers `apply-web-platform-infra.yml`; with a comment-only change
  the apply must be a no-op. Read its run result after merge (postmerge), do not assume.
- The brief's "30 minutes", "healthy data" and "Started since 2026-10-12" are the operator's measurements. The mirror issue #11047
  shows `Started 2026-10-12` and `Detected 2026-10-25`; cite both dates if the PR body mentions detection, and re-measure the
  data before repeating "healthy".
- `## User-Brand Impact` is filled (threshold `none` with a reason) because the diff touches `apps/web-platform/infra/`, a
  sensitive path; an empty section would fail deepen-plan and preflight.
