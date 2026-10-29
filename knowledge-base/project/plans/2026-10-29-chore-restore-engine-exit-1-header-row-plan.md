---
title: "chore(registry): list exit 1 in the restore engine's header exit-code table"
date: 2026-10-29
slug: restore-engine-exit-1-header-row
branch: feat-one-shot-10932-restore-engine-exit1-header-row
issue: 10932
type: chore
closes: none
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# chore(registry): list exit 1 in the restore engine's header exit-code table

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-29
**Sections enhanced:** 4 (Research Insights, Phase 1, Observability, Acceptance Criteria)
**Method:** proportionate to a comment-only change: the mechanical halts 4.6-4.13 were run against the plan, and every claim the new header text makes was re-derived against the engine source (no broad agent fan-out; no skill, learning or framework surface applies beyond the two learnings already cited).

### Key Improvements
1. The "wrote nothing before any network call" claim is now evidenced: every `die 1` site is at engine lines 132-195 and the first real registry call (`crane_capture ... manifest`) is at line 370; the credential `die 5` checks sit between, still before it. The header row therefore states "this attempt wrote nothing" and nothing about the store.
2. `## Observability` was rewritten to the 5-field schema with a probe Check 10 can run (`grep -c '^#   1  INPUT' scripts/registry-restore-from-ghcr.sh` -> `1`), and the Phase 1 text pins the row's first line so the probe cannot rot.
3. Line references corrected: the runbook sentence wraps over lines 495-497; the A2 stale phrase ends at line 295.

### New Considerations Discovered
- The `tests?/` over-inclusive command-shape reject in Phase 4.7 would have refused a probe that ran the W9 suite; the one-line `grep` probe avoids it and stays inside the 15 s cap.
- Halt results: 4.6 pass (threshold `none`, no sensitive path among the five files); 4.7 pass after the rewrite; 4.8 pass (no PAT shapes); 4.9, 4.10, 4.11, 4.13 not triggered (no UI file, no .tf/migration, no new guard, no new autonomous task); 4.12 pass (one unfenced `## Scope Check`, all three subsections, no `unmapped` row, justification present on the one `inferred` row); 4.55 not triggered (no host, DB or deploy operation).
- Cited identifiers verified live: #10932 OPEN, #9757 OPEN, PR #11518 OPEN draft, PR #11438 MERGED, commit 11505d70c3 is an ancestor of `origin/main`; the only rule id cited (`wg-use-closes-n-in-pr-body-not-title-to`) is active in AGENTS.md.

## Overview

`scripts/registry-restore-from-ghcr.sh` opens with a fully enumerated exit-code table (rows 0, 2, 3, 4, 5, 6, 78). The engine also exits 1 (`die 1`, `die 1` call sites at lines 132-195, all before the first network call), but the table has no row for it. This is item (a) of #10932, split out of the earlier PR (#11438, commit 11505d70c3) because a comment-only edit to the engine still changes its bytes and arms the ~860 s registry mutation battery (`scripts/lib/test-relevance-paths.sh` `REGISTRY_BATTERY_PATHS`, entry `SUT_ENGINE`). That earlier PR landed everything on the workflow side (the `1)` arm, the runbook row, W9 coverage); this PR is the header side only.

Deliverables, all comment/message text, no logic change:

1. Add the exit-1 row to the engine header table.
2. Clear the two stale "tracked in #10932" comments (`tests/scripts/lib/restore-engine-header.sh`, `tests/scripts/test-registry-pull-path-health.sh`). Both files are battery members, so touching them costs nothing beyond what the engine edit already arms.
3. Two truth-keeping edits the header row would otherwise contradict (CTO-ruled, see Decisions): one runbook sentence that says the header "does not yet list exit 1", and two stale count messages.

PR body: `Ref #9757` and `Ref #10932` only. No closing keyword anywhere (not in the title, body or commit messages). Merge with `gh pr merge <N> --squash --auto` (draft PR is #11518).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (checked on this branch) | Plan response |
|---|---|---|
| Header has rows 0,2,3,4,5,6,78, none for 1 | Confirmed (`scripts/registry-restore-from-ghcr.sh` lines ~57-79). `restore_header_codes` therefore yields `2 3 4 5 6 78`. | Add row `1` between 0 and 2 (table is in ascending order). |
| Stale comments at lib lines ~8-11 and pull-path-health ~295 | Confirmed: lib lines 8-11 ("tracked in #10932 ... adding a header row for 1 turns nothing red"); pull-path-health comment block lines 290-295 ("the workflow side is tracked in #10932"). | Reword both; see Phase 2. |
| "A2 requires >= 7 codes; the union stays the same" | A2 computes `{ echo 1; header codes } \| sort -un` -> 7 today and 7 after. W9 computes the same union. Both `-ge 7` floors stay correct. | Leave floors and `EXPECTED_ASSERTIONS=47` untouched. |
| "any comment says header-vs-emit ignores 1 on both sides?" | Yes. Lib lines 8-11 say so, and W9 does it for real at `tests/scripts/test-registry-d10-workflow-wiring.sh` line 492 (`grep -vx 1` on both `hdr` and `emit`). The ignore also appears in W9's failure text ("both without 1"). | Keep the ignore (CTO ruling, Q1). Reword the lib comment to say the ignore remains, truthfully. |
| Header should match workflow/runbook wording | Workflow arm (`apply-web-platform-infra.yml` ~3661): "exit 1 (INPUT/MANIFEST fault) — the engine refused its arguments or the pin manifest before any network call, so this attempt wrote nothing ...". Runbook row: "Input or manifest fault ... before any network call. A correct refusal, not an engine defect." | Header row uses the same vocabulary at the granularity the engine proves (this attempt wrote nothing; nothing is claimed about the store). |
| (not in brief) the runbook says the header lacks a 1 row | `registry-luks-recut-6929.md` ~line 495-496: "Its own header table does not yet list exit 1 (input faults, tracked on #10932)". False after this PR. | Fix that one sentence (CTO ruling, Q2). No test pins it (repo grep: only an archived plan matches). |

## Research Insights

**Premise validation.** #10932 is OPEN; its (a) item is exactly this scope. #9757 OPEN. PR #11518 is this branch's own draft (collision pre-check hit = self). Four foreign `test-all.sh` processes belong to other agent worktrees with no PR naming #10932; they are unrelated to this change. Commit 11505d70c3 (`git log`) is on main and contains the workflow arm, runbook row and W9 extension, so the premise "workflow side is already merged" holds. No cited file is missing on `origin/main`. ADR corpus: only ADR-169/096/280 mention the engine; none decides anything about the header table, and nothing here is an architecture decision.

**Property List.**
- P1: The engine's header table lists every non-zero code the engine can emit (an operator reading the header sees exit 1).
- P2: No comment in the repo claims the header lacks a row for 1 or defers it to #10932.
- P3: The header text does not contradict the workflow `1)` arm or the runbook exit-1 row.
- P4: Nothing about test logic, the `grep -vx 1` ignore, the `-ge 7` floors or `EXPECTED_ASSERTIONS` changes.

**Mechanism minimality (Cut List).** No new mechanism is proposed; this is text only. Cuts considered and rejected: (1) dropping the `grep -vx 1` ignore so a deleted row 1 goes red — buys a new guard (property outside P1-P4), is test-logic change, and the earlier ruling plus this PR's brief say do not widen; recorded as a follow-up candidate, not filed (see Deferral); (2) bumping the `-ge 7` floors — the union with {1} already makes 7 regardless, so a bump buys nothing.

**Value measurement (0.6c).** Not a cost-saving plan; skipped.

**Institutional learnings applied.**
- `knowledge-base/project/learnings/2026-10-28-my-new-runbook-sentence-about-the-gate-was-false-and-a-job-key-allowlist-left-twenty-edits-green.md`: re-derive every sentence added about another component against the code it names. The row therefore claims only what the engine proves: every `die 1` call sits at lines 132-195 (the credential `die 5` checks sit between 160 and 163), all before the first `crane` invocation, so the claim is "this attempt wrote nothing", not "the store is unchanged" or "empty". Work re-checks this with `grep -n 'die 1' ...` against the first `$CRANE`/`crane_capture` call line.
- `2026-10-23-a-guard-over-a-case-statement-should-run-the-case-not-parse-it.md`: the existing W9 design (runs the case) is untouched.
- Mutation battery anchors (`tests/scripts/test-registry-gate-mutation-battery.sh`, engine section) are code lines (`die 1 ` guard lines, `if ... then` lines); a header comment cannot match them provided the new text contains none of those code fragments verbatim. Work Phase 1 verifies this by running the battery's `py_replace` uniqueness on the edited engine (the battery itself aborts, exit 2, on a non-unique anchor).
- AC9 (`tests/scripts/test-registry-restore-from-ghcr.sh` line ~909): whole-file grep for the literal two-word container-pull command must find nothing; the new text must not contain it.

## Open Code-Review Overlap

None. (Queried `gh issue list --label code-review --state open`; no body names any of the five planned files.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add an exit-1 row to the header exit-code table of scripts/registry-restore-from-ghcr.sh" | Phase 1 / Files to Edit #1 | mapped |
| 2 | "The same PR can clear the stale \"#10932 tracks the workflow arm\" comments in tests/scripts/lib/restore-engine-header.sh and tests/scripts/test-registry-pull-path-health.sh" | Phase 2 / Files to Edit #2, #3 | mapped |
| 3 | "PR body uses Ref #9757 and Ref #10932 only, never a closing keyword" | Phase 4 | mapped |
| 4 | "Merge with gh pr merge <N> --squash --auto" | Phase 4 | mapped |
| 5 | "Check what the tests assert about the code count ... and decide whether that ignore should be kept" | Decisions row 1 (kept) | mapped |
| 6 | "Check the apply workflow / runbook (already on main) for wording the new header row should match, so the header does not contradict it" | Phase 1 wording; Phase 3 runbook sentence | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Header row for 1 | "add an exit-1 row to the header exit-code table" | asked |
| Reword lib comment + A2 comment | "clear the stale ... comments" | asked |
| Runbook sentence fix | "so the header does not contradict it" | asked |
| Reword two stale count messages (A2 "1 + six header rows", W9 "fewer than 6") | — | inferred — justification: message-only text that becomes a lie ("six header rows") once the header has seven; CTO ruled it in (Q3). W9 file is not a battery member and no assertion count moves. |

### Split Assessment

- Subsystems touched: 2 — `scripts/` + `tests/scripts/` (one registry-restore concern), `knowledge-base/` (one sentence)
- Planned files: 5 | Estimated changed lines: ~35
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

1. `scripts/registry-restore-from-ghcr.sh` — header table only (comment lines inside the leading `#` block; insert between the `0` row and the `2` row). No non-comment byte changes.
2. `tests/scripts/lib/restore-engine-header.sh` — rewrite lines 8-11 (the "EXIT 1 RULE" comment).
3. `tests/scripts/test-registry-pull-path-health.sh` — A2 comment (lines ~290-295) and the fail message at line ~302.
4. `tests/scripts/test-registry-d10-workflow-wiring.sh` — one message string at line ~495 ("fewer than 6" -> "fewer than 7").
5. `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` — the sentence at ~lines 495-497 only (it wraps across three lines).

**Files NOT touched (assert in review):** `.github/workflows/apply-web-platform-infra.yml` and anything under `apps/web-platform/infra/` (would fire the production apply), `apply-web-platform-infra-job-rationale.md`, `scripts/registry-pull-path-health.sh`, any test logic.

No files to create other than this plan, `tasks.md`, and `decision-challenges.md` under `knowledge-base/project/specs/feat-one-shot-10932-restore-engine-exit1-header-row/`.

## Implementation Phases

### Phase 1 — Engine header row (arms the battery)

Insert after the `#   0  every required reference restored AND verified (blobs + signature)` row (keep the `#   N  LABEL` shape: three spaces before the digit for single-digit codes, two spaces after it; continuation lines indent with `#      `). The extractor `restore_header_codes` matches `^#[[:space:]]+[0-9]+[[:space:]][[:space:]]+[A-Za-z]`, so the row line must start with a letter label and no continuation line may begin with digits followed by two spaces. Proposed text (final wording may be tightened at work time; the vocabulary must stay aligned with the workflow arm and runbook row):

```text
#   1  INPUT or MANIFEST fault — the engine refused its arguments or the pin manifest: an unknown
#      argument or an option missing its value, the removed `--rehearse`, a missing `--target` or
#      `--tags-from`, an unreadable manifest, a `--target` that is not a registry host:port, a
#      manifest with no numeric `.floor`, an `.entries` that is unparseable or not an array, zero
#      required entries, or duplicated repo:tag pairs. Raised before any network call, so THIS
#      ATTEMPT wrote nothing. NOT retryable: the same inputs fail identically. A correct refusal,
#      not an engine defect — the `::error::` line names the check that fired.
```

Constraints: the row's first line must read exactly `#   1  INPUT ...` so the discoverability probe above matches; ASCII quoting consistent with neighbours (the existing rows use `—` and backticks, so those are fine); the new text must not contain `docker pull`, and none of the battery's `py_replace` anchor fragments (code lines like `die 1 `, `if false; then`).

Verify (commands in Acceptance Criteria): comment-only diff; `bash -n`; extractor output; AC9 grep.

### Phase 2 — Clear the stale comments (test files, messages only)

- `tests/scripts/lib/restore-engine-header.sh` lines 8-11 become (CTO Q1 wording): exit 1 is ALWAYS exercised (header non-zero codes UNION {1}, deduped), whether or not the header lists it; the workflow arm for exit 1 and the header row are already in place; the header-vs-emit comparison in W9 still ignores 1 on BOTH sides, so a header that drops the row for 1 (or an engine that stops emitting 1) is not caught by it. Drop "tracked in #10932" and "adding a header row for 1 turns nothing red" (now false in the past tense and misleading).
- `tests/scripts/test-registry-pull-path-health.sh` A2 comment: drop "the workflow side is tracked in #10932" (the gate has an arm for the engine's input fault; the workflow arm is on main). Change the line-302 fail message "(1 + six header rows)" to "(seven header rows, exit 1 included)". The `-ge 7` floor and the `{ echo 1; ...}` union stay.
- `tests/scripts/test-registry-d10-workflow-wiring.sh` line ~495: message "fewer than 6 failure codes" -> "fewer than 7 failure codes". The check `-ge 7` itself stays. W9 controls grep other fragments (`differs`, `exit 1 fell`, ...), none grep "fewer than", so no control changes (verified: `grep -rn "fewer than" tests/scripts` shows only the W9 line).

### Phase 3 — Runbook sentence

In `registry-luks-recut-6929.md` under "Restore exit codes", replace "Its own header table does not yet list exit 1 (input faults, tracked on #10932), but the restore step annotates it and it has a row here." with a sentence stating the header lists exit 1 (input faults), as does the restore step annotation and the row below (CTO's suggested wording). Touch nothing else in the runbook (line ~477 "except exit 1, which re-runs identically" stays; it is accurate).

### Phase 4 — Verify, PR, merge

Run the three suites directly, then the battery through the affected-tests harness; update draft PR #11518 title/body (`Ref #9757`, `Ref #10932`; test plan lists the commands); mark ready; `gh pr merge 11518 --squash --auto`. The PR must carry the standard `wg-use-closes-n-in-pr-body-not-title-to` exception: here the rule is explicitly inverted (Ref only), because #10932's remaining items stay open on #9757/#10932 residuals.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash -c 'source tests/scripts/lib/restore-engine-header.sh; restore_header_codes < scripts/registry-restore-from-ghcr.sh | tr "\n" " "'` prints `1 2 3 4 5 6 78 `.
- [ ] `restore_emit_codes < scripts/registry-restore-from-ghcr.sh | tr "\n" " "` prints `1 2 3 4 5 6 78 ` (unchanged vs `origin/main`: `diff <(git show origin/main:scripts/registry-restore-from-ghcr.sh | restore_emit_codes) <(restore_emit_codes < scripts/registry-restore-from-ghcr.sh)` is empty).
- [ ] The Observability probe `grep -c '^#   1  INPUT' scripts/registry-restore-from-ghcr.sh` prints `1` (it prints `0` on `origin/main`).
- [ ] The engine diff is comment-only: `diff <(git show origin/main:scripts/registry-restore-from-ghcr.sh | grep -vE '^[[:space:]]*#') <(grep -vE '^[[:space:]]*#' scripts/registry-restore-from-ghcr.sh)` is empty, and `bash -n scripts/registry-restore-from-ghcr.sh` exits 0.
- [ ] `grep -cF 'docker pull' scripts/registry-restore-from-ghcr.sh` prints `0`.
- [ ] `grep -n '10932' tests/scripts/lib/restore-engine-header.sh tests/scripts/test-registry-pull-path-health.sh` prints nothing.
- [ ] `grep -rn 'does not yet list exit 1' knowledge-base/engineering/operations/runbooks/` prints nothing.
- [ ] `grep -n 'grep -vx 1' tests/scripts/test-registry-d10-workflow-wiring.sh` still prints the two-sided ignore (line 492) and `EXPECTED_ASSERTIONS=47` is unchanged.
- [ ] `bash tests/scripts/test-registry-restore-from-ghcr.sh`, `bash tests/scripts/test-registry-pull-path-health.sh` and `bash tests/scripts/test-registry-d10-workflow-wiring.sh` all exit 0 with the same pass counts as on `origin/main` (record both).
- [ ] `bash tests/scripts/test-registry-gate-mutation-battery.sh` exits 0 (the ~860 s run the engine edit arms; run via `scripts/test-all.sh --affected` or directly with a backgrounded run, as the repo's runner conventions require). Exit 2 means an anchor went non-unique: fix the header text, never the battery.
- [ ] `git diff origin/main --name-only` is exactly the five Files-to-Edit entries plus this plan, `tasks.md` and `decision-challenges.md`; in particular nothing under `.github/workflows/` or `apps/web-platform/infra/`.
- [ ] PR body contains `Ref #9757` and `Ref #10932`, and `git log origin/main..HEAD --format=%B` plus the PR body match none of `(close[sd]?|fix(es|ed)?|resolve[sd]?) #`.

### Post-merge (operator)

None. No workflow, infra or runtime surface changes, so no apply fires and no post-deploy verification applies.

## Test Scenarios

- Header-derived population: extractor on the edited engine yields the 7-code set; W9 and A2 iterate the same set as before (the union with {1} masked the missing row), so pass counts are unchanged.
- Negative/vacuity controls already in the suites keep covering the header: W9 control `engine-extra-code` (adds one `die N` and requires "differs") still refuses; this PR does not add a control because P4 forbids test-logic change.
- Header-row malformation (a row that does not match the extractor shape, e.g. a single space after `1`) would silently drop 1 from the header set and still pass because of the union; the Phase 1 AC (`prints 1 2 3 4 5 6 78`) is the check that catches it.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The change is comment text in an operator script header, three test-message strings and one runbook sentence.

**If this leaks, the user's data / workflow / money is exposed via:** no vector; no secret, credential or data path is touched.

**Brand-survival threshold:** none

(None of the five paths matches the canonical sensitive-path regex in `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1, so no scope-out bullet is required.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling comment change.

## Observability

Comment/message-only change to an existing operator script and its tests: no new error path, log call or infra surface. The schema is declared anyway because the Files-to-Edit list is not pure-docs; every value below is an existing signal this PR leaves untouched or a probe of the one new artifact (the header row).

```yaml
liveness_signal:
  what: the engine header table row for exit 1 exists and is extractor-visible (restore_header_codes yields 1)
  cadence: on every run of the registry mutation battery and the W9/A2 suites (they derive their code population from the header)
  alert_target: CI red on the PR/main (the mutation battery and the registry suites are required checks via the affected-tests harness)
  configured_in: scripts/lib/test-relevance-paths.sh (REGISTRY_BATTERY_PATHS) and tests/scripts/lib/restore-engine-header.sh
error_reporting:
  destination: engine `::error::registry-restore-from-ghcr:` lines in the job log (unchanged); CI failure annotations for the suites
  fail_loud: yes - a malformed row that the extractor cannot see leaves the header at 6 codes, and the A2 floor (-ge 7 with the union) plus the Phase 1 acceptance check surface it
failure_modes:
  - mode: header row written in a shape the extractor skips (single space after the code, digit-led first word)
    detection: Phase 1 acceptance check prints the header population; it must read 1 2 3 4 5 6 78
    alert_route: PR check failure before merge
  - mode: new header text collides with a mutation-battery py_replace anchor
    detection: battery aborts with exit 2 (non-unique anchor) on the PR run
    alert_route: PR check failure before merge
  - mode: header text contains the forbidden two-word container-pull command
    detection: engine suite AC9 whole-file grep
    alert_route: PR check failure before merge
logs:
  where: CI run logs of the affected-tests job (suite output and battery ledger)
  retention: GitHub Actions default log retention
discoverability_test:
  command: grep -c '^#   1  INPUT' scripts/registry-restore-from-ghcr.sh
  expected_output: "1"
```

## Decisions (technical rulings)

Persisted in `knowledge-base/project/specs/feat-one-shot-10932-restore-engine-exit1-header-row/decision-challenges.md` (Q1-Q3, ruled by the CTO agent, 2026-10-29):

1. Keep the two-sided `grep -vx 1` ignore; reword the lib comment accordingly; do not widen.
2. Fix the single false runbook sentence in this PR.
3. Reword the two stale count messages; leave floors and `EXPECTED_ASSERTIONS` alone.

## Deferral tracking

Follow-up candidate (not in scope, not a blocker): drop the `grep -vx 1` ignore (and the redundant union) so a header that loses its row for 1 goes red. The brief fences scope to item (a), and this changes test logic and needs its own control rows, so it belongs with the residual items already tracked under #10932/#9757 (the "Restore summary" step, computed `die "$x"`, the W9 verdict swap). Mentioned in the PR body as a note on #10932; no new issue is filed because #10932 stays open and already owns the residual list.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder text fails `deepen-plan` Phase 4.6; this one carries concrete text and threshold `none`.
- The extractor row shape is load-bearing: two or more spaces after the code, a letter-initial label, and no continuation line that starts with digits plus two spaces.
- Do not paste the battery's mutation anchors into the header text (a comment that duplicates a code anchor makes `py_replace` non-unique and aborts the battery with exit 2).
- Any non-comment byte change to the engine would turn a header PR into a behaviour PR; the comment-only diff check is mandatory.
- Do not use a closing keyword anywhere (title, body, commits): #10932 and #9757 stay open.
