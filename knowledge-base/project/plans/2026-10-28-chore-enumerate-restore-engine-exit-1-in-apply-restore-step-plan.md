---
title: "chore(registry): enumerate restore-engine exit 1 in the apply restore-step case"
date: 2026-10-28
slug: enumerate-restore-engine-exit-1-in-apply-restore-step
branch: feat-one-shot-10932-restore-exit-1
issue: 10932
type: chore
closes: none
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# chore(registry): enumerate restore-engine exit 1 in the apply restore-step case

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

The registry restore engine (`scripts/registry-restore-from-ghcr.sh`) exits 1 for argument, manifest and
floor faults. The apply workflow's restore step (job `registry_store_restore`, `case "$rc" in`) has no `1)`
arm, so exit 1 reaches the `*)` arm, whose text claims every engine code is enumerated and carries an
"exit 1 is the known exception (#10932, already filed)" aside. The runbook's "Restore exit codes" table also
lacks a `1` row. This plan adds the `1)` arm (modelled on `scripts/registry-pull-path-health.sh` A2),
keeps the workflow under its 490,000-byte gate by relocating prose, adds the runbook row, and extends the
behavioural W9 test so exit 1 is covered and the six residual gaps from the #10932 comment are each
classified. It is a separate PR for this one item; the umbrella #9757 and #10932 stay open (the engine
header row, task item (a), cannot ride this PR — see Premise Validation).

## Research Insights

### Premise Validation (Phase 0.6)

- `#10932` is OPEN with no closing PR; the only open change naming it is this branch's own draft PR #11438
  (collision pre-check exit 10, own PR only, no foreign run). Umbrella `#9757` stays open by instruction.
- Cited artifacts verified on this branch (= `origin/main` + the init commit): the engine header table
  (lines ~55-76 list 0, 2, 3, 4, 5, 6, 78), the restore-step `case "$rc"` (~line 3671, no `1)` arm, `*)` text
  contains "exit 1 is the known exception (#10932, already filed)"), the A2 `1)` arm
  (`scripts/registry-pull-path-health.sh` ~line 576), the runbook table (~line 482, lead sentence says "except
  exit 1 (input faults, #10932)"), the rationale doc (`## registry_store_restore`, line ~618).
- Stale-premise finding: the #10932 comment says the assertion-count floor "is the only backstop" for a verdict
  swap on the W9 row. Reading `_report` (test-registry-d10-workflow-wiring.sh:41) and the floor (:520) shows a
  swapped `if true` still increments `passes`, so the floor catches removal or silencing, never a swap.
- Task item (a) vs the hard constraint: the header is a `#` comment block, but editing it changes the engine's
  bytes. The operator's rule is "if the header edit would change the file at all, STOP and report". The STOP
  fires for (a) only; (b), (c), (d) do not depend on it (the shared extractor already unions {1} into the tested
  population and strips 1 from the header-vs-emit comparison, so a future header row turns nothing red).
- ADR corpus: no ADR rejects an exit-1 arm. ADR-231 (workflow byte budget, relocation to the rationale doc) and
  ADR-169 (the could-not-measure vs measured-bad split the arms preserve) govern the shape.
- Local research was done directly (repo-research-analyst not spawned: every cited path was read in full by the
  planner); `learnings-researcher` returned the applicable learnings listed below.

### Property List and Cut List (Phase 0.6b)

Properties: (P1) an engine exit 1 at the real restore step is annotated as an input/manifest fault, not as an
"unenumerated" defect. (P2) the runbook row for exit 1 exists and does not give the false "re-run the job"
advice. (P3) the workflow stays at or under 490,000 bytes. (P4) a regression that drops the `1)` arm is caught
by a test, not by review. (P5) the engine's bytes are unchanged.

Mechanisms named by the ask: the `1)` arm (buys P1, nothing existing covers it); the runbook row (P2); prose
relocation (P3); the header-derived test (P4 — the derived population already exercises exit 1 via the union,
what is missing is the fall-through flag, see Phase 2); the engine header row (buys documentation only, and is
blocked by P5). Cut List: none cut; the header row is deferred, not cut (stays on #10932).

### Applicable learnings

- `2026-10-23-a-guard-over-a-case-statement-should-run-the-case-not-parse-it.md`: W9 runs the real body; the
  new check must run the case, and every control must mutate the real workflow text and assert the mutation landed.
- `2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so.md`:
  GitHub silently refuses an oversized workflow; relocate comments verbatim, confirm anchors by deleting and
  re-running their consumer, not by regex-derived lists.
- `2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md`: move text
  verbatim rather than rewording it to save bytes.
- `2026-09-23-a-mutation-anchor-can-match-inside-your-own-comment.md`: a stub or rationale line that repeats a
  grep pattern can satisfy a presence check with the real line removed; anchors in `once()` must be unique.
- `2026-10-22-a-verdict-function-inside-command-substitution-cannot-exit-and-an-echoing-stub-inflated-my-counts.md`:
  derive `EXPECTED_ASSERTIONS` from a green run, never from the expected number.
- `lint-infra-no-human-steps.py` fires on runbook prose pairing a human actor with an infra imperative; describe,
  do not quote trigger wording; run it with `--changed --base origin/main` (the gate's own invocation).
- Sharp-edges catalogue (`plan-sharp-edges.md`) was read in part only (lines 1-77 of 341, the file exceeds one
  turn's context budget); the entries read that apply: diff-scope ACs list pipeline-written files, ACs run the
  gate's own invocation, verify named paths exist, no vendor-behaviour claims without measurement.

### Evidence for the exit-1 arm text (CTO ruling, 2026-10-28)

- Engine exit-1 sites (all before any network call, engine lines ~132-195): unknown argument, option missing a
  value, `--rehearse` removed, `--target`/`--tags-from` required, `--tags-from` unreadable, bad `--target`,
  non-numeric `.floor`, `.entries` not an array, zero required entries, duplicate repo:tag pairs.
- The restore step passes fixed arguments (`--target 127.0.0.1:5000 --tags-from ${RUNNER_TEMP}/pins/restore-pins.json`),
  so the argument sites cannot fire; an unreadable file is near-impossible (the artifact download and
  `if-no-files-found: error` fail earlier). Reachable: manifest-content faults (floor, entries, zero/duplicate pairs).
- In a normal dispatch the uploaded `registry-restore-pins` bytes are the file the D10 VERDICT step wrote with
  `--tags-out` and A2 already ran the engine against; reaching exit 1 here means the artifact was altered or this is
  the resume arm (VERDICT skipped, PREPARE's manifest unrehearsed this run). Same run, same commit, same engine.
- Therefore "re-run this job" is useless (the same artifact is re-downloaded, 7-day retention). There is no
  restore-only `apply_target`. A new `registry-luks-recut` with the NEW volume id re-derives and re-rehearses the
  manifest before destroying anything, but that path is unmeasured for this failure, so the wording is conservative.
- The step's own `exit 1` after a failed Doppler read (before the retry loop) never reaches the `case`; the `1)`
  arm text says "engine ... refused" so the two exit-1 origins are not conflated.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "add an exit-1 row to the header table WITHOUT changing the script's code" | Header is a comment block, but any edit changes the engine file's bytes; the engine path arms the ~860 s registry mutation battery | STOP per instruction: (a) not done here; stays on #10932 |
| "let the header-derived enumeration test cover it" | The lib already unions {1} into `$tested` and strips 1 from the header-vs-emit compare; the fall-through flag at W9 line ~474 keys on `$hdr`, which never holds 1 | Re-key that flag on `$tested` and add a `drop1` control (test-only, no lib edit) |
| "the assertion-count floor is the only backstop for a W9 verdict swap" | The floor catches removal/silencing, not a swap | Residual G4; correction recorded in the PR body and on #10932 |
| Workflow headroom | 489,888 bytes, gate 490,000: 112 bytes | Relocate the 766-byte `if:` rationale block; net size roughly neutral |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add an exit-1 row to the header exit-code table of scripts/registry-restore-from-ghcr.sh WITHOUT changing the script's code" [brief] | Phase 0 STOP check | descoped — justification: the header edit changes the engine's bytes; the brief's own rule says STOP and report; stays on #10932 |
| 2 | "add a `1)` arm to the restore-step `case \"$rc\" in` (registry_store_restore) in .github/workflows/apply-web-platform-infra.yml, modelled on the `1)` arm in scripts/registry-pull-path-health.sh A2" [brief] | Phase 3 (workflow `1)` arm) | mapped |
| 3 | "add an exit-1 row to the runbook \"Restore exit codes\" table in registry-luks-recut-6929.md if missing" [brief] | Phase 4 (runbook row) | mapped |
| 4 | "let the header-derived enumeration test cover it" [brief] | Phase 2 (W9 fall-through re-key + `drop1` control) | mapped |
| 5 | "relocate prose to apply-web-platform-infra-job-rationale.md rather than grow the workflow" [brief] | Phase 3 (relocation of the job `if:` block) | mapped |
| 6 | "Plan must classify each as picked-up-in-this-PR or left-as-residual with a reason" [brief] | Residual-Gap Classification table | mapped |
| 7 | "The plan must record that the work edits .github/workflows/apply-web-platform-infra.yml (fires the production apply) and that the pipeline STOPS at a pushed draft PR" [brief] | Ship constraints | mapped |
| 8 | "Plan must also list the pre-ready gates" [brief] | Ship constraints | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Workflow `1)` arm + `*)` wording | "add a `1)` arm to the restore-step `case \"$rc\" in`" | asked |
| Rationale-doc subsection for the relocated `if:` block and for the exit-1 reasoning | "relocate prose to apply-web-platform-infra-job-rationale.md rather than grow the workflow" | asked |
| Runbook row, lead-sentence fix, and the "then re-run that job" qualifier | "add an exit-1 row to the runbook \"Restore exit codes\" table" | asked (the qualifier is the same row's false advice, see Phase 4) |
| W9 fall-through re-key and `drop1` control | "let the header-derived enumeration test cover it" | asked |
| W9 credential-env pin and its control (G1) | "W9 ... does not assert the values of the credential env" / "are picked up with exit 1" | asked |
| W9 job-level-key pin and its controls (G2a) | "does not cover job-level keys (`if`, `needs`, `continue-on-error`)" / "are picked up with exit 1" | asked |
| `*)` wording for shell codes (G5) | "shell codes 126/127/137/143 reach the `*)` arm and are not engine codes" | asked |
| `EXPECTED_ASSERTIONS` bump | — | inferred — justification: the suite pins the count exactly, so adding rows without bumping it fails the anti-vacuity floor |
| `decision-challenges.md` | "record `Ruled by CTO agent, <date>: <decision> - <rationale>` as a row in knowledge-base/project/specs/feat-one-shot-10932-restore-exit-1/decision-challenges.md" | asked |

### Split Assessment

- Subsystems touched: 3 — `.github`, `tests`, `knowledge-base`
- Planned files: 4 edited (workflow, rationale doc, runbook, one suite) + plan/tasks/decision-challenges | Estimated changed lines: ~160
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Residual-Gap Classification (the #10932 comment, 2026-10-23)

| # | Gap | Disposition | Reason |
|---|---|---|---|
| G1 | W9 does not assert the values of the credential env (`DOPPLER_TOKEN`, `GH_TOKEN_FOR_ENGINE`) | picked up in this PR | cheap PyYAML read via the existing `W9_PY`; the rationale doc records a post-destroy failure from the wrong name; test-only |
| G2a | W9 does not cover job-level keys (`if`, `needs`, `continue-on-error`) | picked up in this PR | this PR relocates the comment on that very `if:`, so its pin belongs here; test-only |
| G2b | W9 does not cover the "Restore summary" step | left as residual | not engine-coupled; nothing in this PR touches the step (its "one row per code" sentence becomes true with the new row) |
| G3 | derived population reads literal `die N`/`exit N` only; computed `die "$x"` unseen | left as residual | verified: the only non-literal sites in the engine are the `die()` definition and its own `exit "$code"`; closing it needs a lint over the engine, which this PR cannot touch |
| G4 | a verdict swap on the W9 row (`if true`) is not caught by W9's controls | left as residual | the count floor does not back it (corrected above); closing it needs a self-test harness able to drive the final verdict row RED, out of scope for a one-arm PR |
| G5 | shell codes 126/127/137/143 reach `*)` and are not engine codes | picked up (wording only) | the `*)` arm is edited anyway; W9 already runs 137 through it; keep the phrase "unenumerated exit" |
| G6 | wording owned elsewhere: engine "Nothing was copied", workflow arm 3 "The store is EMPTY" | left as residual | the engine is byte-frozen here; arm 3 is not part of exit 1 and editing it grows the file |
| G7 | (additional) stale "#10932 tracks the workflow arm" comments in `tests/scripts/lib/restore-engine-header.sh:9` and `tests/scripts/test-registry-pull-path-health.sh:295` | left as residual | both paths are in `REGISTRY_BATTERY_PATHS` (`scripts/lib/test-relevance-paths.sh`); touching either arms the ~860 s battery for a comment |

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — add the `1)` arm; reword `*)`; relocate the job `if:` comment block (stub left).
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` — two `###` subsections under `## registry_store_restore`: the relocated `if:` rationale (verbatim, `#` stripped) and "Why exit 1 has its own restore-step arm (#10932)".
- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` — new `1` row; fix the lead sentence ("except exit 1"); qualify the "then re-run that job" sentence in "If it finishes but the registry never comes back".
- `tests/scripts/test-registry-d10-workflow-wiring.sh` — W9: re-key the fall-through flag, add the exit-1 content pin, env pin, job-level pin, four controls, `EXPECTED_ASSERTIONS` bump, header-comment refresh.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10932-restore-exit-1/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10932-restore-exit-1/decision-challenges.md` (already written by planning)

Must stay unchanged (verified by `git diff --stat origin/main`): `apps/**`, `scripts/registry-restore-from-ghcr.sh`,
and — to avoid arming the registry mutation battery — `scripts/registry-pull-path-health.sh`,
`tests/scripts/test-registry-pull-path-health.sh`, `tests/scripts/lib/restore-engine-header.sh`.

## Open Code-Review Overlap

One open code-review issue names a planned file: #11388 ("drift guards pin literal params but not the
effective-config paths", PR #11374) names `.github/workflows/apply-web-platform-infra.yml`. Acknowledge: it
concerns alert-window guards, a different concern and different workflow regions; it stays open.

## Implementation Phases

### Phase 0 — Preflight checks (no edits)

1. `git diff --stat origin/main -- apps scripts/registry-restore-from-ghcr.sh` prints nothing (baseline).
2. Baseline suite: `bash tests/scripts/test-registry-d10-workflow-wiring.sh` ends `=== 39 passed, 0 failed ===`
   (measured green during planning); `wc -c .github/workflows/apply-web-platform-infra.yml` = 489,888.
3. Re-confirm the STOP for task item (a): the header block is `#` lines 55-76 of the engine; any edit changes
   the file. Do not edit. Record in the PR body.

### Phase 1 — RED tests first (cq-write-failing-tests-before)

Edit `tests/scripts/test-registry-d10-workflow-wiring.sh` before the workflow:

- Line ~474: change `grep -qx "$code" <<<"$hdr"` to `grep -qx "$code" <<<"$tested"`, so a `*)` fall-through of
  exit 1 is flagged ("exit 1 fell to the *) arm"). With the workflow unedited the main W9 row goes RED. That is the
  expected RED; capture the output.
- In the per-code `case`, add `1) grep -qiF 'manifest' <<<"$line" || w9_add "the annotation for exit 1 does not name the manifest fault" ;;`.
- Python helper `W9_PY`: add `drop1` (regex `\n( *1\) echo [^\n]*)`, computed lazily inside the branch, `once()`
  removal), `envswap` (`DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}` to `${{ secrets.DOPPLER_TOKEN }}` inside the step segment), plus two
  whole-text job mutations `jobif` (drop `!cancelled() &&` from the single job-level `if:` line) and `jobcoe`
  (insert `    continue-on-error: true` after the unique `  registry_store_restore:` line); and read-only modes `env` and
  `job` that print the step's `env` mapping and the job's `needs` / `if` / `continue-on-error` presence.
- `w9_check`: assert `env.DOPPLER_TOKEN == ${{ secrets.DOPPLER_TOKEN_PRD }}` and
  `env.GH_TOKEN_FOR_ENGINE == ${{ secrets.GITHUB_TOKEN }}` (message contains "credential env"); assert
  `needs == registry_luks_recut`, `if` contains `!cancelled()` and `store_refill_needed == 'true'`, and no job-level
  `continue-on-error` (message contains "job-level").
- Controls list: add `"drop1|exit 1 fell"`, `"envswap|credential env"`, `"jobif|job-level"`, `"jobcoe|job-level"`.
  Every control asserts the mutation landed (existing loop) and the refusal message names the right cause.
- Update the W9 header comment (the "NOT covered here" paragraph now lists only the Restore summary step and
  computed `die "$x"`; exit 1 line updated).
- Set `EXPECTED_ASSERTIONS` to the exact count printed by a green run (expected 43 = 39 + 4 controls).

### Phase 2 — Workflow edits (GREEN)

1. Add the `1)` arm between `0)` and `2)` (text from the CTO ruling; em dash style matches neighbours):

   ```text
   1) echo "::error::restore FAILED exit 1 (INPUT/MANIFEST fault) — the engine refused its arguments or the pin manifest before any network call, so nothing was written and the store is still EMPTY. This step passes fixed arguments, so the cause is the manifest (floor, entries, zero or duplicated required pairs) or an unreadable file: read the engine's own ::error:: line above, it names the check. Re-running this job re-downloads the SAME registry-restore-pins artifact and fails identically. Do not re-run blindly: follow the runbook row for exit 1, capture the engine line and file it." ;;
   ```

2. Reword `*)`: keep "unenumerated exit ${rc}"; drop the "exit 1 is the known exception (#10932, already filed)"
   clause; add that 126/127/137/143 are shell or runner codes (not found, not executable, killed, terminated), not
   engine codes. Target text: `...unenumerated exit ${rc}. Every exit code the restore engine emits is enumerated above, so a new one is a defect worth filing alongside the recovery; 126/127/137/143 are shell or runner codes (not found, not executable, killed, terminated), not engine codes.`
3. Byte budget: move the 11-line `# EXPLICIT, not inherited ...` block above `if:` (workflow lines ~3531-3541,
   766 bytes) verbatim to the rationale doc; leave a one-line stub of the form
   `# Why this if: is explicit, not inherited: see "Why the restore job's if: is explicit" in the registry_store_restore section of the rationale runbook.`
   No test anchors on the moved text (CTO grep, repo-wide). Re-check with a delete-and-rerun of the W9 and the
   workflow-structure suites listed in Verification, not with a regex list.
4. Measure `wc -c`: target <= 489,950; hard gate 490,000. Expected net: +~600 (arm) +~60 (`*)`) +~120 (stub) -766.

### Phase 3 — Rationale doc and runbook

- Rationale doc: `### Why the restore job's if: is explicit` (verbatim move, `#` stripped, ADR-231 pattern) and
  `### Why exit 1 has its own restore-step arm (#10932)` (the reachability and recovery evidence above, citing the
  engine sites by content, not line number — cq-cite-content-anchor-not-line-number).
- Runbook `registry-luks-recut-6929.md`: add the `1` row (meaning: input/manifest fault, a correct refusal not an
  engine defect; what to do: nothing was written and on the real restore the store is still empty; re-running the
  job fails identically; in a normal dispatch the same bytes passed the D10 rehearsal, so suspect artifact
  alteration or the resume arm; read the engine's `::error::` line, capture it and file it; there is no
  restore-only dispatch, and a new `registry-luks-recut` with the NEW volume id re-derives and re-rehearses the
  manifest before destroying anything but is unmeasured for this failure; at the D10 rehearsal (A2) the same code
  aborts with nothing destroyed, so fix the cause and re-dispatch). Fix the lead sentence to say the engine's
  header table does not yet list exit 1 (tracked on #10932). Qualify "then re-run that job (the engine is
  resumable)" with "except exit 1, see its row".
- Run `python3 -I scripts/lint-infra-no-human-steps.py --changed --base origin/main` and fix wording, never
  suppress.

### Phase 4 — Verify and stop

Run the Verification commands; update `decision-challenges.md` only if a new fork appears; commit, push the draft
PR (#11438); STOP (see Ship constraints).

## Guard Contract

### Guard 1 — W9 exit-1 fall-through flag

**Property.** No exit code the suite exercises (the engine header's non-zero codes union {1}) may be rendered by the restore step's `*)` arm.

**Assembly.** The population is `$tested` (`restore_header_codes` union 1) inside the single `w9_check` function; the arm text lives in the one `case "$rc"` of the real workflow step, extracted by PyYAML; the main W9 row and every control all flow through `w9_check` (one chokepoint). The prior flag keyed on `$hdr`, a narrower set that never held 1 — that gap is the defect being closed.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `1)` arm from the real workflow text (control `drop1`) | RED naming "exit 1 fell" |
| 2 | Own dispatch: revert the flag to key on `$hdr` while the `drop1` mutation is applied (scratch copy of the suite) | the `drop1` control row goes RED (control refuses nothing) |
| 3 | Second member: add a new engine code (header row plus `die N`) with no workflow arm, after the compliant `1)` arm | RED naming the new code fell to `*)` |
| 4 | Renumber the arm to `11)` | RED ("exit 1 fell") |

Harness rows: edit the suite so the per-code loop skips code 1 (`for code in 0 $tested` minus 1) must turn the
`drop1` control RED; must-PASS input that is not the canonical: a workflow whose `1)` arm has different wording
that still names "exit 1" and "manifest" must pass (the check pins presence of meaning words, not canonical text).
Anchor: the population is derived from the engine's own `die`/`exit` sites and header, not stored in the suite; the
engine is held byte-unchanged by the merge-base `git diff --stat` AC, which is the anchor outside the suite.

### Guard 2 — W9 credential-env pin

**Property.** The restore step's `env` carries `DOPPLER_TOKEN` from `secrets.DOPPLER_TOKEN_PRD` and `GH_TOKEN_FOR_ENGINE` from `secrets.GITHUB_TOKEN`.

**Assembly.** The step's `env:` mapping (one step, found by name, unique, inside job `registry_store_restore`); the pin reads it through the same PyYAML extraction as the other W9 modes; the run body also exports `GHCR_TOKEN` from `GH_TOKEN_FOR_ENGINE`, so the second variable is a consumer of the first pin.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `DOPPLER_TOKEN` re-pointed at `secrets.DOPPLER_TOKEN` (control `envswap`) | RED naming "credential env" |
| 2 | Own dispatch: `env` mode prints nothing (step renamed so extraction returns empty) | RED (extract/unique-step check), not a silent pass |
| 3 | Second member: keep `DOPPLER_TOKEN` correct, change `GH_TOKEN_FOR_ENGINE` to an empty string | RED naming "credential env" |

Harness rows: removing the env assertion from `w9_check` must turn `envswap` RED; must-PASS: the same values
re-ordered or with extra unrelated env keys pass.
Anchor: the expected values are the two literals in the suite; changing them and the workflow in one commit is
visible in the same diff as a reviewable pair, which is the integrity limit of a consistency pin (stated, not hidden).

### Guard 3 — W9 job-level key pin

**Property.** Job `registry_store_restore` keeps `needs: registry_luks_recut`, an `if` that is `!cancelled()` and keyed on `store_refill_needed == 'true'`, and no job-level `continue-on-error`.

**Assembly.** The job mapping in the parsed workflow (one job by key); the step-level FORBID list already blocks `if` / `continue-on-error` on the step, so the job level is the remaining surface. Members drift: any new job-level key that changes run semantics is out of the pin, so the pin asserts the named keys and the check lists the job's full key set in its failure message.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `!cancelled() &&` from the job `if:` (control `jobif`) | RED naming "job-level" |
| 2 | Insert job-level `continue-on-error: true` (control `jobcoe`) | RED naming "job-level" |
| 3 | Change `needs` to another job, after a compliant `if` | RED naming "job-level" |
| 4 | Own dispatch: job lookup returns no job | RED (not "0 checked, exit 0") |

Harness rows: removing the `job` assertions from `w9_check` must turn `jobif` and `jobcoe` RED; must-PASS: the job
`if:` re-wrapped across lines with the same expression passes.
Anchor: as Guard 2.

## Ship constraints

- This work edits `.github/workflows/apply-web-platform-infra.yml`. Merging that file to `main` fires the
  production apply workflow (it runs under the `infra-privileged` environment). The edit changes comments and one
  annotation `echo`, with no Terraform change, so the expected plan is empty, but the trigger is real.
- The pipeline STOPS at a pushed draft PR (#11438) for operator approval. No `gh pr ready`, no auto-merge, never
  `--admin`, never `git stash`. No doppler command and no live credentialed probe at any step.
- PR body uses `Ref #9757` and `Ref #10932` only. Never a closing keyword on #9757, #10924 or #10932 (the ship
  skill's default `Closes` line must be replaced). Out of scope: #11312, #11379, #10924, #9757 themselves.
- Pre-ready gates (all must be green before the PR is marked ready, by the operator):
  1. `python3 -I scripts/ci-pr-affected-replay.py ratchet`
  2. `bunx vitest run --project repo-wide test/plugin-root-anchoring.test.ts` (from `apps/web-platform`)
  3. `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh`
  4. `bash tests/scripts/test-registry-d10-workflow-wiring.sh` and `bun test plugins/soleur/test/workflow-file-size.test.ts`

## User-Brand Impact

- **If this lands broken, the user experiences:** an operator reading a mislabelled or missing `::error::` line on a failed restore of the production image registry, during the window when no host can pull an image.
- **If this leaks, the user's workflow is exposed via:** no exposure vector — the change adds an annotation string, comments and test assertions; it reads or writes no credential, secret, user data or network resource.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the arm is operator-facing text on a path already guarded by W9's behavioural run; a wrong word cannot change what the step does or exits with.

threshold: none, reason: the touched `.github/workflows/apply-web-platform-infra.yml` path matches the sensitive-path regex by filename only; the diff changes an annotation string and comments, never a credential, permission, trigger or command.

## Observability

```yaml
liveness_signal:
  what: the restore step's per-exit-code ::error:: annotation, and the Restore summary step in the run's step summary
  cadence: per-run (each registry-luks-recut dispatch that chains the restore)
  alert_target: the run's job annotations and step summary, read by the operator; the apply-failure notifier covers a red run
  configured_in: .github/workflows/apply-web-platform-infra.yml (job registry_store_restore)
error_reporting:
  destination: GitHub Actions annotations plus the existing notify-apply-failure job
  fail_loud: the step exits with the engine's own code; exit 1 now prints "restore FAILED exit 1 (INPUT/MANIFEST fault)"
failure_modes:
  - mode: engine exit 1 (manifest content fault) at the real restore
    detection: the named annotation, asserted by W9 on every PR
    alert_route: red job plus notify-apply-failure
  - mode: the arm is dropped or renumbered by a later edit
    detection: W9 control drop1 and the re-keyed fall-through flag
    alert_route: PR check failure
logs:
  where: GitHub Actions run log for the registry_store_restore job
  retention: GitHub default run-log retention
discoverability_test:
  command: grep -c "exit 1 (INPUT/MANIFEST fault)" .github/workflows/apply-web-platform-infra.yml
  expected_output: 1
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git diff --stat origin/main -- apps scripts/registry-restore-from-ghcr.sh scripts/registry-pull-path-health.sh tests/scripts/test-registry-pull-path-health.sh tests/scripts/lib/restore-engine-header.sh` prints nothing.
- [ ] The diff is a subset of: the workflow, the rationale doc, the runbook, `tests/scripts/test-registry-d10-workflow-wiring.sh`, this plan, `specs/feat-one-shot-10932-restore-exit-1/{tasks,decision-challenges,session-state}.md`, and `knowledge-base/INDEX.md` if the pipeline regenerates it.
- [ ] `wc -c .github/workflows/apply-web-platform-infra.yml` <= 490,000 (target <= 489,950) and `bun test plugins/soleur/test/workflow-file-size.test.ts` passes.
- [ ] `bash tests/scripts/test-registry-d10-workflow-wiring.sh` ends `=== 43 passed, 0 failed ===` (count taken from the green run; the RED run in Phase 1 shows the exit-1 fall-through failure first).
- [ ] With the `1)` arm deleted from the workflow, the same suite fails with "exit 1 fell to the *) arm" (the `drop1` control is the standing proof; do the manual delete once to see it).
- [ ] The workflow contains `exit 1 (INPUT/MANIFEST fault)` exactly once and no longer contains `known exception (#10932`.
- [ ] `bash tests/scripts/test-registry-pull-path-health.sh` and `bash tests/scripts/test-registry-restore-from-ghcr.sh` still pass (unchanged inputs; confirms the shared lib contract).
- [ ] `python3 -I scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes (the gate's own invocation).
- [ ] The runbook table has a `1` row and the lead sentence no longer says the engine "enumerates every failure it can have except exit 1" without the header caveat.
- [ ] Every claim the new arm and runbook row add traces to a cited engine or workflow source (Evidence section above); the rationale subsection cites sites by content, not line number.
- [ ] Pre-ready gates in Ship constraints are green; PR body carries `Ref #9757` and `Ref #10932` and no closing keyword; PR left DRAFT.
- [ ] PR body states: (a) not done (STOP), G2b/G3/G4/G6/G7 left as residual, and the corrected G4 backstop claim.

### Post-merge (operator)

- [ ] None required by this change. The merge-triggered apply is expected to plan empty; the operator confirms the run is green before treating #10932 item (a) as the only open piece.

## Test Scenarios

- Given the unedited workflow and the re-keyed flag, when W9 runs, then it fails with "exit 1 fell to the *) arm" (RED).
- Given the `1)` arm, when the stubbed engine exits 1, then the step exits 1 after one engine call and the annotation names exit 1 and the manifest.
- Given a stubbed engine exit 137, the step still exits 137 via `*)` whose text contains "unenumerated exit 137".
- Given `DOPPLER_TOKEN` re-pointed, `continue-on-error: true` on the job, or `!cancelled()` removed from the `if`, W9 refuses each (controls).

## Non-Goals

- The engine header row (task item (a)): blocked by the byte-unchanged rule; remains open on #10932.
- Residual gaps G2b, G3, G4, G6, G7 (see classification); no new tracking issues are created because #10932 stays open and carries them in the PR-body correction and its closing comment at ship time.
- A restore-only dispatch, and any change to retry behaviour (exit 3 only).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one declares `none` with the sensitive-path scope-out line.
- Mutation anchors in `W9_PY` must each match exactly once (`once()`); the `1)` regex must not match `11)`; the `registry_store_restore:` job-key anchor must be asserted unique before use.
- `EXPECTED_ASSERTIONS` is pinned exactly; take the number from the green run.
- The `1)` arm and the step's own Doppler `exit 1` are different exit-1 origins; the arm text says "engine".
- Do not shorten the relocated text to save bytes; move it verbatim.
