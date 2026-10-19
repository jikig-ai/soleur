---
title: "docs: record the second wipe_check (run 39136900735) in the LUKS cutover runbook"
type: docs
date: 2026-10-18
slug: record-second-wipe-check-in-luks-cutover-runbook
branch: feat-one-shot-runbook-second-wipe-check-record
issue: 10138
closes: none
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-10-18
**Sections enhanced:** 6 (E1 to E3 wording, E2 scope, Acceptance Criteria 5, 8, 9, Test Scenarios)
**Review passes used:** CLO agent (twice, wording), CTO agent (placement, lint, test coupling), learnings-researcher,
user-impact-reviewer (single-user threshold), a scratch-copy dry run of E1 to E4.

### Key Improvements

1. E2 no longer says the C1 hold is superseded: it is scoped "as to run 39136900735 only", states that the note does not
   otherwise change the hold and does not read C1's parenthetical for a later `wipe`, and authorizes nothing.
2. E3 states what `repos=0` measures, read from `apps/web-platform/infra/git-data-wipe-assert.sh` (count of entries directly
   under a top-level `repositories` directory in the transient snapshot; 0 also when that directory is absent), so it cannot
   be read as "no user repository remains".
3. E1's dispatch-absence claim carries a mandatory as-of date; AC 5 is widened to synonyms and to every added file, the PR
   body and commit messages; AC 8 (owner has posted or approved the line in the runbook) is blocking for marking the PR ready.

### New Considerations Discovered

- The exit-34 line is printed after `repos` is counted; what the exit skips is the later `repositories_not_empty` refusal.
- Deepen-plan halts 4.6 to 4.12 checked: User-Brand Impact present with threshold; no Observability (pure docs); no PAT-shaped
  token; no UI surface; no store or connection (Encryption Posture n/a); no guard (Guard Contract n/a); one unfenced
  `## Scope Check`. No AGENTS rule IDs are cited; PR #10480 verified MERGED, #10506 OPEN, #10138/#6897/#9066 OPEN.
- Dry-run hits of the AC 5 grep on the added lines are all negations or an exclusion description (`Nothing in this note
  authorizes ...`, `an empty lost+found excluded`, `not a statement that no user repository remains`); the negative control
  (an inserted `benign`/`empty`) hits as it should.

## Overview

Record the measured result of the second read-only `wipe_check` of the git-data cutover workflow in
`knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`. The run (workflow_dispatch on
`main` by the owner, 2026-10-18) refused at the host assertion with exit 34. The edit adds dated markers beneath two
held sentences instead of rewriting them, resolves the one hypothesis the first run left open, and updates the Status
paragraph. Docs only: no script, workflow, gate or allowlist change, and nothing is dispatched. Draft PR #10506 is
already open; its body uses `Ref #10138` and `Ref #6897`, never `Closes`.

## Research Insights

**Premise Validation (Phase 0.6), all checked on 2026-10-18 with read-only `gh` calls:**

- Run 39136900735: `git-data wipe_check 106867358`, `workflow_dispatch`, branch `main`, dispatched by the owner,
  head `840dc667fc`, attempt 1, conclusion `failure`; the failed step is `Host-side wipe assertion (W7)`, the `cutover`
  job was skipped and `notify-failure` succeeded.
- The run log carries, byte for byte, `[git-data-cutover] probe-stderr: wipe-assert: rc=34 reason=offlist top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=1`
  and `STORE probe=wipe-assert verdict=wipe_boot_layout_signal_offlist`. No `lock_residue=` or `store_root_repos=`
  value was printed (the only log hits are the step's own script text).
- CLO addendum 2 (`https://github.com/jikig-ai/soleur/issues/6897#issuecomment-6251181879`) was posted 14:38:21Z; the
  run was created 14:38:27Z. Its item 7: the lift is spent after one run; any further run needs a new addendum; the DPD
  10.3(b) re-ruling stays due 2026-10-24. Item 2 is the closed posting list (PR #10480). Item 1 sets out the command; it
  does NOT say the owner named it (the CLO review caught my draft claiming that).
- #10138 and #6897 are both OPEN. The first run, 39081408368 (2026-10-18 00:04Z), is already recorded in the runbook.
- Nothing in the test suite binds this prose: only `apps/web-platform/infra/git-data-wipe-access.test.sh` (G8) and
  `apps/web-platform/infra/git-data-cutover-access.test.sh` (RB) read the runbook, and both check verdict-word parity.
  No verdict word is added or removed.

**Property List (Phase 0.6b):**

1. The runbook states the second run's posted line and the sanctioned reading, with the run URL.
2. The first run's open hypothesis ("`hooks` is the off-list entry") is shown as measured, with the run URL, and what
   stays unproven is stated.
3. The two sentences that said "hold" and "a further `wipe_check` needs ... a new CLO addendum" stay readable as
   written and are marked dated, anchored to the run URL, with the exact scope of what changed.
4. The Status paragraph says two `wipe_check` runs were dispatched, both refused, and no `wipe`, `wipe_finish` or
   `snapshot_clear` was.
5. CLO addendum 2 is recorded as spent; the closed posting list is not extended.
6. The new text leaks no listing name beyond the fixed word `hooks` and claims no emptiness, cleanliness, erasure or purge.

**Cut List:** no mechanism is proposed (text edits only), so nothing was cut. Grepped the authority for tests binding
this prose (the two test files above, via `git grep`), not a consumer.

**Institutional learnings applied** (from `soleur:engineering:research:learnings-researcher`):

- `2026-08-06-i-deleted-the-measurement-that-was-my-own-evidence.md` and
  `implementation-patterns/2026-10-07-an-append-only-latch-is-superseded-by-a-later-record-not-erased.md`: add a dated
  later entry; do not overwrite a dated claim.
- `2026-09-18-my-supersession-pointer-named-the-wrong-bracket.md`: write locators that stay true; the markers quote the
  sentence they refer to by its opening words rather than saying "above" or "below".
- `2026-07-20-a-correction-pr-verified-the-old-claim-was-gone-not-that-the-new-one-was-supported.md`: do not accept
  an absence grep as proof; each new claim must trace to a named measurement (see Acceptance Criteria 6).
- `2026-09-11-every-sentence-my-runbook-inherited-was-false-when-measured.md` and
  `2026-07-30-one-blocked-mechanism-is-not-a-blocked-capability.md`: re-measure each factual sentence; no universal negative.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Status paragraph "~1106" needs "two wipe_check runs, both refused" | The paragraph already carries an `Update (2026-10-18, measured)` sentence naming the first run only; the leading `Status (2026-10-14)` text is a dated snapshot | Rewrite only that Update sentence; keep the dated snapshot and its heading |
| Hold sentence "~line 1181" | It is the tail of the `wipe_check` bullet in "Step order, and what each mode does" (a list item, not its own paragraph) | Add an indented blockquote under that bullet |
| "move the ~1254 'Not proven' hypothesis to a measured finding" | The bullet's own condition ("stays unconfirmed until a run prints `has_hooks_d=1 offlist_n=1 lf_entries=0`") is now met | Replace the bullet with a measured finding; the part about what `hooks` holds stays "not proven" |
| "extend the closed posting list to lock_residue and store_root_repos only if the run reaches them" | The run did not reach them | Do not extend; say so in the Status paragraph and the C1 marker |

## Open Code-Review Overlap

Checked at plan time against the `code-review` label for the single file this plan edits.
Result: None (a docs-only runbook edit; recorded so the next planner can see the check ran).

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (four edits, E1 to E4 below)

## Files to Create

- `knowledge-base/project/plans/2026-10-18-docs-record-second-wipe-check-in-luks-cutover-runbook-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-runbook-second-wipe-check-record/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-runbook-second-wipe-check-record/decision-challenges.md`
- `knowledge-base/project/learnings/2026-10-18-<slug>.md` (one learning, written at work/compound time)

## User-Brand Impact

- **If this lands broken, the user experiences:** a runbook that tells the owner (and an agent reading it before a
  destructive `wipe` dispatch) that the C1 hold is gone, or that the volume was found empty, when neither is true: the
  owner could dispatch a deletion of a volume whose contents were never read.
- **If this leaks, the user's data is exposed via:** a public runbook and public run logs (this repository and #6897 are
  public): a listing name, a per-user identifier, or a count read as a statement about what the volume holds would be
  published against a user who has no way to retract it.
- **Misreads this text must block** (E1 to E3 and the CLO/review rationale in this plan): the tenant git data on the retired
  volume is the artifact; the vectors are a marker read as precedent to dispatch a further run or a `wipe`, `hooks` or
  `repos=0` read as an emptiness statement, and a dated 'nothing dispatched' sentence read after the next dispatch.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** inherited from the parent plan; a wipe of user repositories is
  single-user-visible and irreversible, and this runbook is the control text for it.

## Implementation Phases

Single phase, one file. Each edit is made with the Edit tool, quoting an anchor from the live file (the file is 1977
lines; line numbers are approximate and drift).

### E1 Status paragraph

In the paragraph starting `**Status (2026-10-14).**`, replace only the sentence starting `Update (2026-10-18, measured):`
with:

> Update (2026-10-18, measured): two `wipe_check` runs have since been dispatched (read-only) and both refused with `wipe_boot_layout_signal_offlist`: run 39081408368, and [run 39136900735](https://github.com/jikig-ai/soleur/actions/runs/39136900735), the first to print the `has_hooks_d`, `lf_entries` and `offlist_n` fields (see 'Reading the exit-34 line'). As of the `gh run list` read on 2026-10-18, no `wipe`, `wipe_finish` or `snapshot_clear` had been dispatched; re-read the run list before relying on this. CLO addendum 2 ([#6897 comment](https://github.com/jikig-ai/soleur/issues/6897#issuecomment-6251181879)) lifted C1 for one further `wipe_check` only; run 39136900735 is that run and spent the lift. It refused at exit 34 before `lock_residue` and `store_root_repos` printed, so neither run measured either field and the closed posting list is unchanged.

Wording follows the CLO review (R2) and the user-impact review (finding 4: the as-of date is mandatory, never
optional; the run list is re-read at work time, AC 4, and the date in the sentence is the date of that read).

### E2 Marker beneath the `wipe_check` bullet (C1 hold)

Immediately after the `- **`wipe_check`** (confirm ...` bullet, leaving the bullet untouched, add an indented
blockquote, two-space indent so it stays inside the list item. That list is already loose (blank lines between items), so a
blank line before the quote changes nothing (CTO ruling 1, `decision-challenges.md`; measured with the repo's markdownlint,
0 errors):

> **Superseded 2026-10-18, as to run 39136900735 only ([run](https://github.com/jikig-ai/soleur/actions/runs/39136900735), CLO addendum 2 on #6897):** addendum 2 lifted C1 for one further `wipe_check`, and that run is run 39136900735; the lift is spent. This note does not otherwise change the hold above (`Hold the first run that prints the residue counts ...`), and does not read C1's parenthetical for a later `wipe`. Both prior `wipe_check` runs refused at exit 34 and printed neither `lock_residue` nor `store_root_repos`. `repos` did print (`repos=0`) in both exit-34 lines; whether that falls under C1 is the CLO's to say. Any further `wipe_check` needs a new CLO addendum (addendum 2, item 7) and the owner to name the exact command ('Who names a dispatch'). Nothing in this note authorizes dispatching any mode; `wipe`, `wipe_finish` and `snapshot_clear` stay held (addendum 2). The DPD §10.3(b) re-ruling stays due 2026-10-24.

CLO review R1 and follow-up (a)-(c): "Superseded" is kept because the brief requires it, but only with the "as to run
39136900735 only" scope and the sentence "This note does not otherwise change the hold above". Rejected: the bare
"superseded as to that hold" form (the hold is not superseded, it was lifted once) and a lead of "Hold still binds every
later run" (that would interpret C1, which the CLO leaves open). The user-impact review's finding that a later `wipe` might
read as having a "prior `wipe_check`" is met by stating that the note does not read the parenthetical, not by
interpreting it.

### E3 Measured finding replaces the 'Not proven' hypothesis

In 'Reading the exit-34 line', replace the bullet starting `- Not proven: that `hooks` is the off-list entry` with:

> - Measured 2026-10-18 ([run 39136900735](https://github.com/jikig-ai/soleur/actions/runs/39136900735), read-only, verdict `wipe_boot_layout_signal_offlist`): `wipe-assert: rc=34 reason=offlist top_d=3 top_f=0 top_l=0 top_o=0 repos=0 has_hooks_d=1 lf_entries=0 offlist_n=1`. Read through the table in this section, row `has_hooks_d=1 offlist_n=1 lf_entries=0`: the only off-list entry is a directory named `hooks`; its owner and contents are unread. This is not an emptiness reading, the allowlist is unchanged and the refusal stands. `repos=0` is a count at one moment, in the transient host-local snapshot, of the entries directly under a top-level `repositories` directory (lock-named files and an empty `lost+found` excluded); it also reads 0 when no such directory is present. It is not a statement that no user repository remains and not an emptiness reading. `lock_residue` and `store_root_repos` are not in the line; this run did not print or measure them. Recorded here from the public run log; posting to #6897 stays the owner's act. Not proven: what `hooks` holds.

The earlier bullets (`Measured 2026-10-18 (run 39081408368 ...)` and `Inherited ...`) are not edited.

### E4 Marker beneath the 'a further `wipe_check`' bullet

Immediately after the bullet starting `- Nothing here dispatches a run or sets a date; a further `wipe_check` needs ...`, add the
quote with a two-space indent and NO blank line before it, so this tight list stays tight (CTO ruling 1, variant c; an
unindented quote would make the next list start trip MD032):

> **Superseded 2026-10-18, as to that sentence for run 39136900735 only:** the exact command was set out in CLO addendum 2, item 1 ([comment](https://github.com/jikig-ai/soleur/issues/6897#issuecomment-6251181879)), and [run 39136900735](https://github.com/jikig-ai/soleur/actions/runs/39136900735) is that further `wipe_check`; the lift in addendum 2 is spent. The sentence still binds any run after it.

CLO review R3: the draft said "the owner named the command"; addendum 2 does not say that, so the claim is dropped.

### Deliberate non-edits

- The 'Reading the exit-34 line' table, the Policy bullet, and the 'Other results that route to the CLO' paragraph.
- The `Not proven` section's H9/H8, 3600 s window and snapshot-listing statements ("first measured by `wipe_check`"):
  still literally true. Exit 34 is reached by control flow only after those checks pass, but none of their values was
  printed, so that is an inference from code, not a measurement, and it is not recorded as one (CTO ruling 3).
- Any claim of same-day posting to #6897 or #9066 (addendum item 5 is an instruction, not a recorded fact).

## Acceptance Criteria

### Pre-merge (PR)

1. `git diff --stat origin/main` lists exactly the runbook plus plan, spec, decision-challenges and learning files; no
   script, workflow, test, ADR or allowlist file.
2. The runbook diff has no deleted lines other than the Status `Update (2026-10-18, measured)` sentence and the
   `Not proven: that hooks is the off-list entry` bullet (`git diff origin/main -- <runbook> | grep -c '^-[^-]'` equals
   those two lines' wrapped line count; the two Superseded markers are pure additions).
3. The posted line in the runbook is byte-identical to the log line (`grep -cF` of the exact string in the runbook is
   at least 1, and the same string was read from `gh run view 39136900735 --log`).
4. Dispatch claims were re-read: `gh run list --workflow git-data-cutover.yml` shows no `wipe`, `wipe_finish` or
   `snapshot_clear` dispatch; the date of that read is the one the Status sentence carries (or the anchor is omitted).
5. Added lines contain none of `empty`, `clean`, `safe`, `benign`, `harmless`, `wiped`, `cleared`, `erased`, `purged`,
   `ready` except as a negation or inside quoted prior text, and no listing name other than `hooks`
   (`git diff origin/main | grep '^+' | grep -n -i -E '\b(empty|clean|safe|benign|harmless|wiped|cleared|erased|purged|ready|nothing|no (user|personal))\b'`
   over ALL added files, not only the runbook, plus the PR description and commit messages; each hit explained). Only the
   closed-list fields, the posted line and the word `hooks` may appear as measured values: no `lock_residue=` or
   `store_root_repos=` value anywhere.
6. Presence check: each new claim maps to a named measurement (log line, addendum item, or run-list read); the mapping
   is in the PR description.
7. `lint-infra-no-human-steps.py` and markdownlint pass on the runbook; `git-data-wipe-access.test.sh` and
   `git-data-cutover-access.test.sh` still pass (or are unchanged by a docs-only diff, shown by running them).
8. The PR description states that the quoted line is copied from the public run log and carries only the fixed closed
   fields (counts and one boolean), with no listing name; it flags to the owner, rather than asserting, whether the owner has
   posted the line on #6897 (the runbook's rule: the owner posts, an agent does not). This AC is blocking: PR #10506 stays
   draft, and is not marked ready, until the owner (or the CLO) has said the runbook may carry the line.
9. `node_modules/.bin/markdownlint` on the runbook reports 0 errors, and no new backticked `wipe_*` verdict word and no
   change to the 'Verdict map' section appear in the diff (`git diff origin/main -- <runbook> | grep -c 'Verdict map'` is 0).
10. PR #10506 body carries `Ref #10138` and `Ref #6897`, no `Closes`/`Fixes`/`Resolves`.

### Post-merge (operator)

None. No dispatch, no deployment.

## Domain Review

**Domains relevant:** Legal, Engineering

### Legal

**Status:** reviewed
**Assessment:** CLO agent reviewed the four texts (2026-10-18). Required changes R1 to R3 applied above: scope the
"Superseded" marker to run 39136900735 only; name `lock_residue` and `store_root_repos` instead of "residue count";
drop the unsupported "owner named the command" attribution. No emptiness claim, no listing name beyond `hooks`.

### Engineering

**Status:** reviewed
**Assessment:** CTO agent reviewed marker placement, markdownlint, test coupling and stale-sentence risk; rulings are rows
in `decision-challenges.md`.

## Test Scenarios

- Re-run the two access test scripts and the repo markdown/infra lints against the edited runbook.
- Negative control for AC 5: run the same grep on a scratch copy with a deliberately inserted `empty` and `benign` and confirm both hit.
- Dry run (done at deepen time on a scratch copy, not the repo): E1 to E4 applied, markdownlint 0 errors (baseline 0),
  `lint-infra-no-human-steps.py` OK, 2 lines deleted, no 'Verdict map' hunk, posted line byte-identical, no hits on
  empty/clean/erased/purged in added lines.

## GDPR / Compliance

`soleur:gdpr-gate` trigger (b) holds (threshold `single-user incident`). The change touches no schema, auth, API or
processing activity; it narrows what a public document says about a personal-data deletion. The CLO review above is the
gate for the wording; no `compliance-posture.md` item is opened.

## Observability

Pure-docs plan: skipped (Phase 2.9; no code or infra file in Files to Edit).

## Architecture Decision (ADR/C4)

No architectural decision is made or changed (no ADR amendment, no C4 impact: no actor, system, store or access
relationship is added; the runbook records an already-decided gate's measured result). The ADR-239 amendment that the
policy bullet requires for any allowlist change is explicitly not part of this PR.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add a dated `Superseded 2026-10-18` marker beneath the hold sentence at ~line 1181 (DPD hold / C1 lift)" | E2 | mapped |
| 2 | "and beneath ~line 1256 (\"a further wipe_check needs the owner to name the exact command and a new CLO addendum\"), each anchored to the run URL, WITHOUT editing those lines in place" | E4, Acceptance Criteria 2 | mapped |
| 3 | "move the line ~1254 'Not proven' hypothesis to a measured finding with the run URL" | E3 | mapped |
| 4 | "update the Status paragraph ~1106 (two wipe_check runs, both refused; no wipe, wipe_finish or snapshot_clear dispatched)" | E1 | mapped |
| 5 | "state CLO addendum 2 ... was spent by that run and extend the closed posting list ... only if the run reaches them" | E1, E2, E4 (spent stated; list not extended) | mapped |
| 6 | "No script, workflow, gate or allowlist change. Dispatch nothing." | Acceptance Criteria 1, Deliberate non-edits | mapped |
| 7 | "record nothing from them in this PR" (concurrent rulings on the open allowlist question and the DPD 10.3(b) re-ruling, both tracked on #6897) | Deliberate non-edits; no allowlist or re-ruling text | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| E1 | "update the Status paragraph ~1106" | asked |
| E2 | "add a dated `Superseded 2026-10-18` marker beneath the hold sentence" | asked |
| E3 | "move the line ~1254 'Not proven' hypothesis to a measured finding" | asked |
| E4 | "beneath ~line 1256" | asked |
| "as to run 39136900735 only" scope on E2 and E4 | — | inferred — justification: CLO review R1/R3; the lift was for one run and a bare "superseded" would read as lifting the hold for later runs |
| Learning file | "plan/spec/learning artifacts" | asked |

### Split Assessment

- Subsystems touched: 1 — knowledge-base
- Planned files: 5 | Estimated changed lines: 40
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; it is filled above.
- Do not write "above" or "below" in the new markers; quote the opening words of the sentence they refer to.
- The `Superseded` marker must keep its "as to run 39136900735 only" scope; without it, it reads as lifting the C1 hold for every later run.
- The Status paragraph keeps its `(2026-10-14)` heading date: the sentence after it is a dated snapshot.
- Do not copy anything from the concurrent rulings (open allowlist question, DPD 10.3(b) re-ruling) into this PR.
