---
title: "chore(registry): engine-edit + battery-armed polish after restore exit-1 tracker (#10932 residue)"
date: 2026-10-31
slug: registry-restore-engine-polish
branch: feat-one-shot-11667-registry-restore-engine-polish
issue: 11667
lane: single-domain
type: chore
---

# chore(registry): engine-edit + battery-armed polish after restore exit-1 tracker (#10932 residue)

## Enhancement Summary

**Deepened on:** 2026-10-31. **Review inputs:** CTO rulings (R1-R5, F1-F2, C1-C6), DHH, Kieran and
code-simplicity reviewers, a sharp-edges verification pass that ran the plan's sed, grep and lint commands on
the real files. **Gates run:** user-brand impact (pass, threshold none with scope-out), PAT sweep (no hits),
Guard Contract lint (exit 0, 2 entries), scope check (one live section, every ask mapped, inferred rows
justified), markdownlint (0 issues). **Not applicable, with reason:** network-outage deep-dive (the word
"unreachable" appears only inside the quoted message text; the plan diagnoses no outage and proposes no
connectivity fix), downtime and cutover (no serving surface is changed), encryption posture (no store or
connection), UI wireframe, task-design.

**Key corrections folded in:** arm 3 is workflow text, so only the engine half of item (b) is editable; the
workflow is 490,228 bytes and main is red (#11687), so merge waits for #11690; line 664 is a `die 2` site, so
the partial-store sentence sits in the EXIT CODES preamble and the exit-3 row is untouched; the engine suite
needs a separate assertion pair (a folded check would leave the count at 98); two W9 controls, not three; the
diff-scope checks use the three-dot form and exclude pipeline KB artifacts; ship must not write `Closes`.

**Verify-the-negative pass.** Negative claims re-checked on the real tree: no other file asserts "Nothing was
copied" (repo grep over scripts, tests, .github, apps, plugins, knowledge-base/engineering); none of the five
`die 3` messages claims emptiness; no battery anchor touches the edited lines; no open code-review issue names
a planned file. **Post-edit self-audit.** After the C1-C6 cuts the plan was re-read for dropped symbols
(`hdr-drop1`, `emit-drop1`, `hdr-label1`, the A2 why-comment, the exit-3 clause, the folded assertion): none
remain outside the Cut List and the decision table.

## Overview

Issue #11667 is the consolidated residue of a closed restore-exit-1 tracker (#10932, umbrella #9757; their
three PRs #11438, #11557 and #11589 merged 2026-10-29 and 2026-10-30). It lists one test-logic item, one
engine-wording item and three stale comments, all in or beside the registry restore engine and its shared
exit-code header extractor. Editing the engine or the extractor arms the ~860 s registry mutation battery, so
every item ships in ONE pull request and the battery runs once.

Ruled by CTO agent, 2026-10-31: proceed (the battery cost is CI minutes on a required context, not
production risk; the engine edit paths do not match the apply workflow's push-paths filter, so nothing fires
the production apply). The ruling table is in
`knowledge-base/project/specs/feat-one-shot-11667-registry-restore-engine-polish/decision-challenges.md`.

Two operator-brief facts changed under this plan (details in Research Reconciliation): arm 3's "The store is
EMPTY" text lives in the forbidden workflow, so only the engine half of item (b) is editable here; and main is
red (#11687), so merge is blocked behind #11690 regardless of this PR's content.

PR body rule: only `Ref #11667` and `Ref #9757` (the exact line from #11667's body). Never `Closes`/`Fixes`;
#11667 stays open and carries the accepted residue (arm 3, by its string).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (checked 2026-10-31) | Plan response |
|---|---|---|
| (b) "engine wording ... and arm 3 'The store is EMPTY'" are `scripts/registry-restore-from-ghcr.sh` text | "Nothing was copied" is at the engine line `die 2 "GHCR was unreachable while resolving ${src} ..."` (inside the per-entry loop, so earlier entries may already be copied). Arm 3 is the `3)` arm of the restore step `case` in `.github/workflows/apply-web-platform-infra.yml` (the forbidden file) | Edit the engine only. Record arm 3, quoted by its string, as accepted residue on #11667 (CTO ruling R2) |
| "apply-web-platform-infra.yml is 489,131 of 490,000 bytes" | `wc -c` on `origin/main` d1fa52f9 is 490,228 (228 over the gate); `plugins/soleur/test/workflow-file-size.test.ts` is red on main | Never touch the file; do not fold the fix into this PR; wait for #11690 (CTO ruling F2) |
| "(c) a hook-test wording comment" (unnamed) | Not named in the issue. The only stale wording row found: `.claude/hooks/grep-q-pipe-guard.test.sh` PRODUCER_JOIN exempt row for `tests/scripts/test-registry-d10-workflow-wiring.sh` says "the suite runs only the restore step body"; since #11589 the suite also runs the Restore summary step body | Reword that row (CTO ruling R4); the work phase does one grep for `runs only the restore step` and swaps to a better candidate only if one exists |
| (c) `test-registry-pull-path-health.sh:302` says "1 + six header rows" | The header now lists seven rows (1,2,3,4,5,6,78); the A2 loop still unions `{1}` | Reword the message to "1 plus the header rows" (no count; CTO C4) |
| (c) lib comment "a computed die is not seen, and neither suite claims to cover one" | False for the wiring suite since #11589 (`w9_computed_sites`); still true for the pull-path-health A2 loop | Reword to say which suite covers it |
| (a) "the `grep -vx 1` ignore on both sides" is test logic only | Confirmed: `w9_check` line `hdr="$(restore_header_codes <<<"$eng" \| grep -vx 1)"; emit="$(... \| grep -vx 1)"`. The header lists 1 and the engine has twelve literal non-comment `die 1` sites, so removing both filters keeps the real tree green | Remove both; add two controls so each side of the former hole is closed |
| `collision-precheck.sh 11667` reports PR #11692 and two foreign `test-all.sh` pids | #11692 is this branch's own draft PR; the pids belong to `feat-one-shot-11578-ruling-gate-midnight-flake` | No collision. The local battery may queue behind the foreign run; CI's required `test` context is then the gate |

## Research Insights

**Premise Validation.** Checked: #11667 OPEN (p3-low, deferred-scope-out, meta/machinery, Post-MVP / Later);
its `Ref` line is `Ref #9757`; #9757 and #10932 CLOSED; PRs #11438, #11557, #11589 MERGED. Held: all three
residue families still exist on `origin/main`. Stale: the workflow byte figure (above); "arm 3" is not engine
text; the hook-test item had no path. Main is red on d1fa52f9 (#11687, `ci/main-broken`) with draft fix PR
#11690. No external premises beyond those.

**Property List (Phase 0.6b).**

1. A header row for exit 1 that is dropped, or an engine whose `die 1` sites vanish, turns the W9 row red (today neither does).
2. The engine's source-resolution network error does not claim that nothing was copied when earlier entries were.
3. Every stale comment in the battery-armed paths states what the code now does.

**Cut List (Phase 0.6b).** No mechanism in the ask is cut. Not added, and why: a runbook-vs-header parity
test (W9 already compares header to emit sites; CTO ruled it out in #11557); any header table row or edit to the exit-3 row (the
partial-store fact is one plain comment sentence under the EXIT CODES preamble, so `restore_header_codes`
output is unchanged); a label-reword must-pass control and a pull-path A2 why-comment (cut after plan review,
CTO C2/C4: the real-tree W9 row is the must-pass; the existing comment already explains the union); an absence
check on the retired sentence (CTO C3); any edit to arm 3 (forbidden file);
dropping the `{ echo 1; header }` union (kept, CTO R3: defensive, and it keeps exit 1 exercised if the
comparison is ever weakened).

**Value-proposition measurement (0.6c).** The only cost claim is "the battery runs once". Measured baselines:
`scripts/suite-durations.tsv` lists `tests/scripts/registry-restore-from-ghcr` at 12,160 and the battery's
documented cost is ~860 s (`scripts/lib/test-relevance-paths.sh`, REGISTRY_BATTERY_PATHS comment). Splitting
(b) from (c) would arm it twice; a single PR arms it once.

**Files and facts used.**

- `scripts/registry-restore-from-ghcr.sh`: EXIT CODES preamble and header table rows (lines ~58-89); the wording at the NETWORK arm of source resolution (line ~664, a `die 2` site); `die 3` sites at lines 543, 679, 694, 860, 874. Swept: none of the five claims emptiness or "nothing copied" (all read "sink unavailable/became unavailable"), so only line 664 and one preamble comment sentence change.
- `tests/scripts/test-registry-d10-workflow-wiring.sh`: `w9_check` (line ~621-626); comments at the "Exit 1 is always in the tested population" block and the "Exit 1 follows the rule in that lib" sentence (~349-363, cite by anchor); `EXPECTED_ASSERTIONS=89` exact pin (measured green today: `89 passed, 0 failed`, 36 s); controls loop and `engine-extra-code` control at ~688-707; nested meta-control stops at `W9_NESTED` exit 64 before the controls.
- `tests/scripts/lib/restore-engine-header.sh`: 24 lines; comments only change (no code), so `restore_header_codes` / `restore_emit_codes` behaviour is byte-stable.
- `tests/scripts/test-registry-pull-path-health.sh`: A2 block lines ~285-304.
- `tests/scripts/test-registry-restore-from-ghcr.sh`: DNS-failure case lines ~670-683 (only checks rc==2); `MIN_ASSERTIONS=98`.
- `.claude/hooks/grep-q-pipe-guard.test.sh` line 2225; only the leading vocabulary word `text-only` is machine-checked (lines ~2649-2652), the trailing `(1 non-test producers)` count must stay byte-stable.
- Battery: `tests/scripts/test-registry-gate-mutation-battery.sh` copies the lib and the two suites into a sandbox and mutates the engine by unique anchors; no anchor touches the lines this plan edits (grepped `Nothing`, `SINK unavailable`, `RETRYABLE`, `unreachable`, `header`).
- No test, script or doc outside the engine asserts the old string "Nothing was copied" (repo-wide grep).

**Institutional learnings applied.**

- `2026-10-30-the-meta-control-shared-the-suspect-and-my-fix-denylist-had-nine-bypasses.md`: a control must not share the code path it audits. The new controls call `w9_check` directly and score through the existing `w9_expect`; the must-pass control is reported through `_report` with an inline predicate, not through `w9_verdict`.
- `2026-10-23-a-guard-over-a-case-statement-should-run-the-case-not-parse-it.md`: controls mutate the real artifact (the real engine text) and assert the refusal names the cause (`differs`).
- `2026-10-29-a-timed-out-call-skipped-the-launch-line-behind-it-and-i-reported-the-gate-running.md` and `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`: launch the battery detached in its own Bash call, confirm `gate.log` exists before saying it runs, redirect to a log and capture `$?` (never `| tail`).
- `2026-10-18-sole-copy-drift-check-fixes-were-the-least-audited-surface.md` (item 8): run `.claude/hooks/grep-q-pipe-guard.test.sh` by hand after the row edit; the affected selector may not pick it.
- `2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so.md`: why the workflow is untouchable here and why #11687 is not this PR's to fix.

**Observability (Phase 2.9).** Skipped: the diff adds no error path, log call or failure mode. It rewords an
existing `::error::` message and comments; `scripts/` top-level is not among the code-class roots the gate
lists, and no new infrastructure surface is introduced.

**Not applicable gates (stated, not silently skipped).** Domain review: none (infrastructure/tooling
chore). GDPR gate: no regulated-data surface. IaC routing, encryption posture, ADR/C4: no new
infrastructure, store or connection, and no architectural decision. Task-design gate: no new autonomous task.
Soak enrollment: no time-gated close criterion (the recut check below is a passive note, not a close
criterion). UI/wireframe gates: no UI surface. Skill-description budget: no `SKILL.md` edit.

## Observability

The diff adds no error path or log call; it rewords one existing `::error::` message. The message itself is the
operator-facing signal, and it is already mirrored by the restore step's annotations in the job log.

```yaml
liveness_signal:
  what: the engine's source-resolution network error line carries the truthful clause
  cadence: on every registry-luks-recut restore (rehearsal and real), only when GHCR is unreachable
  alert_target: the job's ::error:: annotation in the Actions run log
  configured_in: scripts/registry-restore-from-ghcr.sh
error_reporting:
  destination: GitHub Actions ::error:: annotation, read by the operator from the run page
  fail_loud: the engine exits 2 through die(); the restore step maps exit 2 to its own named annotation
failure_modes:
  - mode: the reworded clause is reverted or lost
    detection: the new engine-suite assertion for the anchor phrase fails in CI
    alert_route: required test context on the PR and on main
logs:
  where: the Actions run log of the registry-luks-recut restore job
  retention: GitHub Actions log retention
discoverability_test:
  command: grep -cF "entries restored earlier in this run stay in the sink" scripts/registry-restore-from-ghcr.sh
  expected_output: 1
```

## Open Code-Review Overlap

None. Queried open `code-review` issues for every planned file path; no body names any of them.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly (CI-only tests and message text). The engine
  runs only on `registry-luks-recut`; a broken wording edit could at worst mislead an operator reading the
  `::error::` line after a destroy, and a syntax slip would fail the engine suites in CI before merge.
- **If this leaks, the user's data is exposed via:** no vector. No credential, token or user data is read,
  written or logged; the engine's secret handling lines are not touched.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** wording and test-logic edits with no behaviour change on any code
  path, so no single-user or aggregate exposure.

threshold: none, reason: the touched registry paths run only inside the operator-dispatched recut and its CI
suites, and this diff changes message text, comments and test assertions, never a branch, credential or
destructive step.

## Guard Contract

The deliverable changes a guard (the W9 header-vs-emit comparison) and adds an assertion to a second suite,
so the contract applies. Write the controls BEFORE removing the filters (RED first).

### Guard 1 — W9 header-vs-emitted-codes comparison covers exit 1

**Property.** The engine's header table lists exactly the non-zero codes its literal `die N` / `exit N` sites
emit, INCLUDING 1; dropping the header row for 1, or removing every emit site for 1, turns the real W9 row red.

**Assembly.** One chokepoint: the `hdr` / `emit` pair computed in `w9_check` (the only place the two sets are
compared), fed by the two shared extractors `restore_header_codes` and `restore_emit_codes` in
`tests/scripts/lib/restore-engine-header.sh`. The other reader of the header, the A2 loop in
`tests/scripts/test-registry-pull-path-health.sh`, does not compare sets; it unions `{1}` on purpose and is
not a second comparison site. The `tested` set inside `w9_check` (`{ echo 1; header } | sort -un`) is a third
use of the header and is unchanged. Two sides, two filters today, so two independent holes; each gets its own
committed control.

**Mutation matrix** (every row is backed by a committed control or an existing assertion):

| # | Mutation | Expected |
|---|---|---|
| 1 | Engine text with the header row for code 1 deleted (control `eng-hdr-row1-removed`) | RED, refusal names `differs` |
| 2 | Engine text with every non-comment `die 1` / `exit 1` rewritten to `die 2` / `exit 2` (control `eng-emit-sites1-removed`) | RED, refusal names `differs` |
| 3 | Engine text with one extra `die <max+1>` (existing control `engine-extra-code`) | still RED `differs` once the filters are gone |
| 4 | Own dispatch: the new controls report one row each through the existing `w9_expect` path, so removing a control lowers the pass count | RED via the exact `EXPECTED_ASSERTIONS` pin (89 + 2 = 91, measured from a green run) |

Harness rows: (a) the suite-edit row is row 4 (a deleted or silenced control cannot pass the exact pin);
(b) RED-first evidence recorded in the PR body: on the unchanged tree (filters still present) both new controls
are RED, which is what proves a no-op sed or a filter that hides code 1 cannot stay green. Must-PASS
non-canonical input: the real-tree W9 row on the unmodified engine is the must-pass (it fails against any stub
that rejects everything); the CTO ruled a separate label-reword control out (2026-10-31, C2), and
`scripts/lint-guard-contract.py` is run after the edit — re-add the control only if the lint demands it.

Anchor: the header table and the die sites live in the engine and the expected sets are derived from the
engine itself, so one diff can move both sides together (consistency, not integrity). What stands outside the
commit: the committed controls mutate the real engine text in memory, so weakening either extractor or
re-adding a filter cannot pass without also editing a control in the same diff, which the battery-armed review
sees. Stated, not hidden: this is a consistency pin by design.

### Guard 2 — engine suite pins the truthful source-resolution wording

**Property.** The engine's network-error message for source resolution states that entries restored earlier
stay in the sink.

**Assembly.** The single `die 2` NETWORK arm in the per-entry source resolution (the signature-read NETWORK
arm and the five `die 3` sites do not use the sentence; swept). The assertion lives in the existing
DNS-failure case of `tests/scripts/test-registry-restore-from-ghcr.sh`, which already runs that exact arm.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove or revert the clause "stay in the sink" in the engine message | RED (the new anchor assertion) |
| 2 | Change the arm's `die 2` to `die 3` | RED (existing rc==2 assertion) |
| 3 | Delete the new assertion | RED via `MIN_ASSERTIONS` (98 to 99, measured from a green run; it is a floor, so a deletion is caught only because the floor was raised in the same edit) |

Harness rows: the assertion is a separate pass/fail pair after the rc check (so the count really rises); the
must-pass input is the real engine on the same fixture. Anchor: the engine and the suite change in one
reviewable pair; the `MIN_ASSERTIONS` floor is the part a weakening must also edit. The anchor is one short
phrase on purpose so a re-word that keeps the fact survives.

## Implementation Phases

### Phase 0 — Preconditions (no edits)

1. `git fetch origin main`; confirm the worktree is current. Record `wc -c .github/workflows/apply-web-platform-infra.yml` (490,228 today) and never edit it.
2. Baselines, each captured in its own call and logged: wiring suite `89 passed, 0 failed`; engine suite `98 passed, 0 failed`; pull-path-health suite (re-measure).
3. Run the hook-test sweep once: `grep -rn "runs only the restore step" .claude plugins tests scripts` (returns exactly line 2225 today); swap candidates only if a better one appears.

### Phase 1 — RED (controls first; they must fail on the unchanged tree)

1. In `tests/scripts/test-registry-d10-workflow-wiring.sh`, after the `engine-extra-code` control (which sits after the nested `W9_NESTED` exit, so the nested run is unaffected), add two controls built from `RESTORE_ENGINE_TEXT`, each reported through the existing `w9_expect` path with a failure-only "mutation landed" check (so each adds exactly one passing row):
   - `eng-hdr-row1-removed`: `sed -E '/^#[[:space:]]+1[[:space:]][[:space:]]+[A-Za-z]/d'` removes only the row line (continuation lines do not match the row shape); expect `differs`.
   - `eng-emit-sites1-removed`: `sed -E '/^[[:space:]]*#/! s/\b(die|exit) 1\b/\1 2/g'` rewrites non-comment sites only; expect `differs`. A no-op sed leaves the engine unchanged, so the control is RED by itself; no bespoke second assertion.
2. In `tests/scripts/test-registry-restore-from-ghcr.sh`, right after the DNS-failure case's rc check, add a SEPARATE pass/fail pair: `grep -qF -- 'stay in the sink' <<<"$out"` (a here-string, not a `| grep -q` pipe, per the grep-q-pipe guard).
3. Run both suites: expect both new controls RED (the filters still hide them) and the engine-suite assertion RED (old wording). Write the RED counts and the accepted-residue list to `knowledge-base/project/specs/feat-one-shot-11667-registry-restore-engine-polish/red-evidence.md` for ship to fold into the PR body (ship full-replaces the body; keep "Operator <verb>" and "Post-merge" wording out of it).

### Phase 2 — GREEN

1. `tests/scripts/test-registry-d10-workflow-wiring.sh`: delete both `| grep -vx 1` in `w9_check`; drop ", both without 1" from the message; rewrite those two comment blocks (exit 1 is exercised via the union and compared like any other code); set `EXPECTED_ASSERTIONS` from a green run (91 expected).
2. `tests/scripts/lib/restore-engine-header.sh`: rewrite the EXIT 1 RULE comment (union kept as defence; the comparison now covers 1, so dropping the header row reds the wiring suite) and the `restore_emit_codes` comment (the wiring suite covers computed die/exit via `w9_computed_sites`; the A2 loop does not). No counts in the new text. Comments only.
3. `tests/scripts/test-registry-pull-path-health.sh`: the message "(1 + six header rows)" becomes "(1 plus the header rows)" with no count; the `-ge 7` threshold stays the only number. No comment added (the existing comment above the A2 block already explains the union).
4. `scripts/registry-restore-from-ghcr.sh`: the source-resolution NETWORK message becomes "GHCR was unreachable while resolving ${src} (network/DNS). Nothing was copied for this entry; entries restored earlier in this run stay in the sink and a re-run resumes. crane: ${err}". Add ONE plain `#` sentence under the EXIT CODES preamble covering codes 2-6, worded as fact and not as a promise: a failure after the first entry can leave the sink holding a partial set; crane skips blobs the sink already holds, so a re-run does not redo them, but only the retryable codes are fixed by one (code 4 says re-running will not fix it). The exit-3 row is NOT changed (CTO C1). The sentence must not begin `#   <digits>  <letter>`. Do not touch any `die` code, branch or the `die()` body (W9_DIE_BODY pins it).
5. `.claude/hooks/grep-q-pipe-guard.test.sh` line ~2225: reason becomes "the suite runs the restore step body and the Restore summary step body, of which only the restore step calls doppler (bare, in a command substitution, no stdin); the text piped into doppler lives in other steps that never run". Keep `text-only` first and `(1 non-test producers)` last, byte-stable.
6. Raise `MIN_ASSERTIONS` in `tests/scripts/test-registry-restore-from-ghcr.sh` to the green-run count (98 to 99 expected).

### Phase 3 — Verification

1. Run, each alone: wiring suite (expect `91 passed, 0 failed`, or the measured count); pull-path-health suite; engine suite; `bash .claude/hooks/grep-q-pipe-guard.test.sh`; `python3 scripts/lint-guard-contract.py <this plan>`; `shellcheck` on the changed shell files; `bash -n` on the engine; `bash plugins/soleur/test/fixture-relative-assert.test.sh` (its baseline has row-equality rows for the pull-path-health and engine suites) and `python3 scripts/lint-shell-capture-exit.py` against its baseline; `markdownlint-cli2` on the plan and tasks. Engine diff check: `git diff -U0 origin/main...HEAD -- scripts/registry-restore-from-ghcr.sh | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*#'` prints exactly two lines (the removed and added source-resolution `die 2` line). Guard 2 rows 1 and 2 run once on a scratch copy of the engine (revert the clause; change `die 2` to `die 3`) and the engine suite (about 12 s) must go RED each time.
2. Rebase onto the post-#11690 main first (see Phase 4), THEN launch the ~860 s battery detached in its own Bash call (`setsid nohup env TMPDIR=/var/tmp bash -c "bash scripts/test-all.sh ... > <log> 2>&1; echo \$? > <rc>" </dev/null &`; `scripts/test-all.sh --affected` is the local default), confirm the log exists, read it. If it queues behind a foreign `test-all.sh` run, say so; CI's required `test` context is then the gate and the local run is never reported as passed.
3. Passive note (no action): the next `registry-luks-recut` run executes the engine from the dispatched ref; on that run confirm the D10 rehearsal log shows no `[FATAL]` and ends `restored=N`. Do NOT dispatch a recut for this (the zot store has been live LUKS since 2026-08-10 and a recut empties the registry with no pull fallback).

### Phase 4 — Ship (through merge)

1. Dependency: main is red (#11687; fix draft #11690). This PR must not touch the workflow or fold the fix in. Hold ship until #11690 lands, then rebase on main and re-run CI before the final battery run. Do not mark ready early to jump the queue; never admin-merge; if the merge stays blocked for hours, report it in the session and on #11667.
2. Before any push run `plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh`.
3. PR body: `Ref #11667` and `Ref #9757` only, plus the RED and green counts and the accepted-residue list read from `red-evidence.md`. `gh pr merge <N> --squash --auto` in its own Bash call; never `--delete-branch`.
4. After merge: deploy-arm check (the engine paths are outside `apply-web-platform-infra.yml`'s push filter, so no production apply should arm; verify rather than assume), `soleur:postmerge`, `cleanup-merged`.
5. Comment on #11667 (the issue stays open): items (a), (b-engine) and (c) done; accepted residue quoted by string, not line: workflow arm 3 text "The store is EMPTY" (#11690 may move its line); reopen condition: the operator lifts the workflow-file constraint.

## Files to Edit

- `scripts/registry-restore-from-ghcr.sh` (one message string at the source-resolution NETWORK arm; one comment sentence under the EXIT CODES preamble)
- `tests/scripts/lib/restore-engine-header.sh` (comments only)
- `tests/scripts/test-registry-d10-workflow-wiring.sh` (remove two filters, message tail, comments, two controls, `EXPECTED_ASSERTIONS`)
- `tests/scripts/test-registry-pull-path-health.sh` (message at ~302)
- `tests/scripts/test-registry-restore-from-ghcr.sh` (one assertion pair after the DNS rc check, `MIN_ASSERTIONS`)
- `.claude/hooks/grep-q-pipe-guard.test.sh` (line ~2225 reason text)

## Files to Create

- `knowledge-base/project/plans/2026-10-31-chore-registry-restore-engine-polish-plan.md` (this plan)
- `knowledge-base/project/specs/feat-one-shot-11667-registry-restore-engine-polish/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-11667-registry-restore-engine-polish/decision-challenges.md`

Path check: every path above exists on `origin/main` (verified with `git ls-files`/`wc`), except the three created ones.
Not edited, on purpose: `.github/workflows/apply-web-platform-infra.yml`,
`knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` (its exit-3 row already says
"Retryable", and #11557 just rewrote its exit-1 paragraph; no sentence in it claims emptiness for exit 3 that
this PR falsifies), `scripts/lib/test-relevance-paths.sh` and `scripts/lib/test-affected-paths.sh` (no new
path enters or leaves any battery list; editing them would re-arm every `--pr-gated` battery).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "(a) tests/scripts/test-registry-d10-workflow-wiring.sh: the `grep -vx 1` ignore on both sides of the header-vs-emitted-codes comparison (test logic only)." [brief] | Phase 2 step 1, Guard 1 | mapped |
| 2 | "(b) scripts/registry-restore-from-ghcr.sh: engine wording \"Nothing was copied\" and arm 3 \"The store is EMPTY\"." [brief] | Phase 2 step 4 (engine half); arm 3 recorded as residue on #11667 | mapped (arm 3 descoped — justification: it lives in `.github/workflows/apply-web-platform-infra.yml`, which the brief forbids editing) |
| 3 | "(c) Stale comments: tests/scripts/lib/restore-engine-header.sh (\"a computed die is not seen, and neither suite claims to cover one\" — now false for the wiring suite)" [brief] | Phase 2 step 2 | mapped |
| 4 | "tests/scripts/test-registry-pull-path-health.sh:302 (\"1 + six header rows\")" [brief] | Phase 2 step 3 | mapped |
| 5 | "and a hook-test wording comment." [brief] | Phase 2 step 5 | mapped |
| 6 | "Do NOT edit .github/workflows/apply-web-platform-infra.yml" [brief] | Files-to-Edit exclusion; Phase 4 step 1 | mapped |
| 7 | "PR body uses only `Ref #11667` plus a Ref line to the closed umbrella ... Never `Closes`/`Fixes`." [brief] | Phase 4 step 3 | mapped |
| 8 | "Ship through merge, deploy-arm check, soleur:postmerge, cleanup-merged." [brief] | Phase 4 | mapped |
| 9 | "Passive note only (no action now)" about the next `registry-luks-recut` [brief] | Phase 3 step 3 | mapped (no action) |
| 10 | "have the CTO agent (soleur:engineering:cto) rule whether the battery cost is worth a p3 wording fix before starting" [brief] | Overview + decision-challenges.md row 1 | mapped (ruled: proceed) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Remove both filters in `w9_check` | "the `grep -vx 1` ignore on both sides" | asked |
| Engine message reword | "engine wording \"Nothing was copied\"" | asked |
| Preamble comment sentence (codes 2-6 can follow copied entries) | — | inferred — justification: the reworded message says earlier entries stay; the header is the operator-facing contract and must not be read as "the store is always empty" (CTO C1 moved it from the exit-3 row to the preamble) |
| Lib comment rewrite | "\"a computed die is not seen, and neither suite claims to cover one\" — now false for the wiring suite" | asked |
| Pull-path message at :302 | "\"1 + six header rows\"" | asked |
| Hook-test row reword | "a hook-test wording comment" | asked |
| Two W9 controls (`eng-hdr-row1-removed`, `eng-emit-sites1-removed`) | — | inferred — justification: removing a filter without a control that reddens when the row or sites vanish leaves the suite green with the defect restored; the guard-contract rule requires them (CTO R3/C5) |
| Engine-suite assertion pair and `MIN_ASSERTIONS` bump | — | inferred — justification: without it the false sentence can return on the post-destroy path with every suite green (CTO F1/C3) |
| `EXPECTED_ASSERTIONS` recount | — | inferred — justification: the exact pin fails the suite the moment a control is added |

### Split Assessment

- Subsystems touched: 3 — `scripts`, `tests`, `.claude`
- Planned files: 6 edited + 3 created | Estimated changed lines: ~90
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (splitting would arm the ~860 s battery twice)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git diff --name-only origin/main...HEAD | grep -v '^knowledge-base/'` lists exactly the six edited files (the pipeline also adds KB artifacts such as session-state, a learning and archive moves). Workflow untouched: `git diff --quiet origin/main...HEAD -- .github/workflows/apply-web-platform-infra.yml` exits 0 (three-dot, so a #11690 change on main does not read as this branch's).
- [ ] `grep -vE '^[[:space:]]*#' tests/scripts/test-registry-d10-workflow-wiring.sh | grep -c 'grep -vx 1'` prints `0` (non-comment lines only, so explanatory comments may cite the literal) and `grep -c ', both without 1' tests/scripts/test-registry-d10-workflow-wiring.sh` prints `0`.
- [ ] The non-comment diff of `scripts/registry-restore-from-ghcr.sh` is exactly the one source-resolution `die 2` line (Phase 3 step 1 command), and the header table still yields `1 2 3 4 5 6 78`: `bash -c 'source tests/scripts/lib/restore-engine-header.sh; restore_header_codes < scripts/registry-restore-from-ghcr.sh | tr "\n" " "'`.
- [ ] `grep -c "stay in the sink" scripts/registry-restore-from-ghcr.sh tests/scripts/test-registry-restore-from-ghcr.sh` prints a count of at least 1 for each file; the engine suite asserts the anchor as a separate pass/fail pair after the rc check, and `MIN_ASSERTIONS` equals the measured green count.
- [ ] Wiring suite green with the measured total (91 expected), `EXPECTED_ASSERTIONS` equal to that total; RED-first evidence recorded (`eng-hdr-row1-removed` and `eng-emit-sites1-removed` failed before the filters were removed). `python3 scripts/lint-guard-contract.py <plan>` exits 0.
- [ ] `tests/scripts/test-registry-pull-path-health.sh`, `tests/scripts/test-registry-restore-from-ghcr.sh` and `.claude/hooks/grep-q-pipe-guard.test.sh` pass; `shellcheck` clean on the changed shell files; `bash -n` clean on the engine.
- [ ] The ~860 s battery result is the one against the post-#11690 main (rebase first), read from a log with its captured rc; or, if it queued, the PR body says so and CI's required `test` context is the gate. No claim of a local pass that was not run.
- [ ] `plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh` run before every push.
- [ ] PR body and every commit message carry `Ref #11667` and `Ref #9757` and none of the words `close`, `closes`, `fixes`, `resolves` (GitHub's parser ignores negation, so not even in a sentence saying the PR does not close). Ship defaults to `Closes #N` from the branch name: close #11667 only after the workflow-file constraint is lifted and arm 3 is reworded.

### Post-merge (operator-free)

- [ ] Deploy-arm check: confirm the merge commit did not arm `apply-web-platform-infra.yml` (its push paths are `apps/web-platform/infra/**`, the workflow file, and `tests/scripts/lib/destroy-guard-filter-web-platform.jq`; none changed).
- [ ] `soleur:postmerge` then `cleanup-merged`.
- [ ] Comment on #11667 listing what landed and the accepted residue (workflow arm 3 text "The store is EMPTY", by string); #11667 stays open.

## Test Scenarios

1. Real tree: `w9_check` on the unmodified engine and workflow prints nothing (the real W9 row stays green with 1 now compared).
2. Header row for 1 deleted: refusal text contains `differs`.
3. Every `die 1` rewritten to `die 2`: refusal text contains `differs`.
4. Engine DNS failure on the first required entry: exit 2 and the output contains `stay in the sink`.
5. Real engine and workflow: the real W9 row prints no problem (the must-pass).
6. `.claude/hooks/grep-q-pipe-guard.test.sh`: still passes with the reworded reason.

## Risks and Sharp Edges

- Main is red (#11687); the required `test` context cannot go green for this PR until #11690 lands. Plan for the wait; do not "fix" the workflow here.
- `EXPECTED_ASSERTIONS` and `MIN_ASSERTIONS` are pinned from a GREEN run, never from arithmetic.
- `eng-emit-sites1-removed`: the sed must skip whole-line comments (`/^[[:space:]]*#/!`), and a no-op sed is RED by itself (expected `differs`, got nothing), so no bespoke second assertion is added.
- The new engine-suite check must be a SEPARATE pass/fail pair (folding it into the rc check leaves the count at 98 and a raised `MIN_ASSERTIONS` would fail the suite). `MIN_ASSERTIONS` is a floor, not an exact pin.
- The new controls' "mutation landed" checks are failure-only so each control adds exactly one passing row (89 + 2 = 91).
- The header edit must not add a table row or a continuation line shaped like a row (`#   <digits>  <letter>`), or `restore_header_codes` and the A2 loop change.
- `W9_DIE_BODY` pins the `die()` body: edit nothing inside it.
- `ci-pr-affected-audit.accept.tsv` anchors are hashes of suite lines that merely name a path; none of the lines edited here are anchors (checked: the only anchored rows for the lib are in other suites).
- Local battery may queue behind another worktree's `test-all.sh`; that is not a pass.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan`; this one declares threshold `none` with the sensitive-path scope-out line.
