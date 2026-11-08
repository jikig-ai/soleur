---
title: "fix(ci): add headSha to the merge-queue stall issue's Triage step 2 field list"
type: fix
date: 2026-11-08
slug: merge-queue-stall-triage-headsha
branch: feat-one-shot-12362-stall-triage-headsha
issue: 12362
closes: 12362
lane: cross-domain
---

# fix(ci): add headSha to the merge-queue stall issue's Triage step 2 field list

Spec lacks valid `lane:` (no spec.md for this branch) - defaulted to cross-domain (TR2 fail-closed).

## Overview

The stall issue body filed by `.github/workflows/merge-queue-stall-check.yml` tells its reader, in
Triage step 2, to "correlate recent merge_group runs by headSha/createdAt". The `gh run list ... --json`
field list on the same line does not request `headSha`, so the instruction cannot be followed from that
command's output. Pre-existing since PR #12295; raised in the PR #12350 review (agent-native seat, P3) and
filed as #12362 with a follow-through probe. A CTO ruling (Ruled by CTO agent, 2026-11-08) lifted the hold
that kept the template byte-identical in #12350 (merged as 10e66d9ab8).

One PR, three files: the one-token workflow edit, one new membership assertion in the stall-check suite
(written and proven red first), and deletion of the now-redundant follow-through probe.

PR body: `Closes #12362` and `Ref #9927` only. #9927 is an open epic and must never appear after a closing
keyword; `closingIssuesReferences` must be exactly `[#12362]`. Keep every other closing verb out of the PR
body prose (learning `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`).

## Research Insights

**Premise Validation (Phase 0.6).** Checked and held: #12362 is OPEN (labels `follow-through`,
`deferred-scope-out`, `meta/machinery`, `priority/p3-low`), no closing PR yet; epic #9927 OPEN; #12272
(the open `action-required` issue for the epic) OPEN; #12350 MERGED (10e66d9ab8); draft PR #12378 is this
branch's own PR. Collision pre-check: the only open change naming #12362 is #12378 itself; four foreign
`test-all.sh` processes belong to an unrelated worktree (`feat-one-shot-10862-norun-investigation`) and do
not touch these files. Cited paths exist on this checkout: Triage step 2 is line 263 of the workflow
(single `--event merge_group --limit 100 --json ` occurrence), the probe exists at
`scripts/followthroughs/stall-triage-headsha-12350.sh`, and `gh run list --help` (gh 2.103.3) lists
`headSha` among the JSON fields (verified 2026-11-08), so the new token is a valid field. No ADR covers
this mechanism (a one-token template edit); none to grep against.

**Property List (Phase 0.6b).**

1. P1: the stall issue's Triage step 2 command returns the head SHA of each listed run, so "correlate by
   headSha/createdAt" is followable from its output.
2. P2: a future edit that drops `headSha` from that list turns CI red, even though the prose on the same
   line still contains the word.
3. P3: no follow-through probe is left pointing at a closed tracker.

**Cut List.**

- A second, parallel probe or a new follow-through enrollment -> P2 -> already covered by the suite
  assertion; the existing probe is retired, not replaced.
- Editing the issue-body prose, the `--jq`, steps 1/3/4 or the jq near line 222 -> none of P1-P3 -> out of
  scope per the ask (and the previous PR's reasoning that the template stays otherwise byte-identical).
- Reusing the probe's logic via a new shared helper script -> P2 -> the suite already runs jq over the
  parsed run bodies; a helper would be a new mechanism for one assertion.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-11-08-a-locale-ordered-regex-range-and-a-probe-that-matched-the-prose-on-its-own-line.md`
  - the direct precedent. The probe passed on the unfixed tree because the prose `by headSha/createdAt`
  shares the line. Fix shape: require exactly ONE matching Triage line and test the comma-separated
  `--json` list, with controls for a `headShaX` lookalike, a decoy comment quoting the command, and an
  empty or absent line. Also: run the new check against the real unfixed tree first, expecting the
  unfixed verdict.
- `AGENTS.rules.md` `cq-assert-anchor-not-bare-token` - anchor on the field list, never a bare token a
  comment or sibling prose can produce; mutation-test the assertion.
- `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`
  - the suite's mutation engine and exact `EXPECTED_PASSES` floor: bump the floor deliberately and count
  producers of passes.
- `grep-q-pipe-guard` learning (session error 9 of the precedent): `.claude/hooks/grep-q-pipe-guard.test.sh`
  flakes under load; re-run before blaming the diff. It carries a registry row for this suite
  (`plugins/soleur/test/merge-queue-stall-check.test.sh | jq | exempt | ...`, line ~2178), so new test
  code must not add a `| grep -q` or a new pipe shape that registry does not already exempt.
- Follow-through convention (`knowledge-base/engineering/operations/runbooks/followthrough-convention.md`):
  the sweeper's closed-set pass keeps running the probe of a tracker closed as completed, for the lookback
  window, for as long as the `follow-through` label is on -> remove the label after close (post-merge).

**Gap callouts / Research Reconciliation - brief vs codebase.**

| Brief claim | Reality | Plan response |
|---|---|---|
| "confirm run-all.sh registration of the suite" | `plugins/soleur/test/run-all.sh` does not exist. The suite is picked up by the `SUITE_GLOBS` entry `plugins/soleur/test/*.test.sh` in `scripts/test-all.sh`, assigned to shard leg 5 by `scripts/suite-shard-legs.tsv` (row for this suite), mapped in `scripts/lib/test-affected-paths.sh` (the affected-index entry names the workflow, the `.tf`, and the suite) and timed in `scripts/suite-durations.tsv`. `.github/scripts/test/run-all.sh` is a different runner (the `.github/scripts` suites). | Registration is by glob and tsv rows that already exist; no new suite is created, so nothing to add. AC verifies the suite still runs under `bash scripts/test-all.sh` selection by name and that `plugins/soleur/test/scripts-shard-totality.test.sh` stays green. |
| "census: grep scripts, plugins, tests, .github, knowledge-base/engineering for other references" to the probe | Content references to `stall-triage-headsha`: none outside the probe's own file name (git grep over the tracked tree excluding plans returns nothing). The tracker #12362's directive names the script path (`script=scripts/followthroughs/stall-triage-headsha-12350.sh`). `12350` appears in `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md` only as a PR citation, not the probe. No closed `follow-through` issue from the last 14 days (closed since 2026-10-25) names the script. Open issue search shows only #12362. | Deletion is a pure file removal; no sibling reference to disposition. The directive lives in #12362 itself, which closes with this PR. Re-run the census at work time (it is one grep) before `git rm`. |
| Probe header: "RETIREMENT: delete this file when #12362 closes" | Verified in the header; it lists only the coupling to the literal Triage step 2 line. | Honoured by deleting in this PR. |

## Files to Edit

- `.github/workflows/merge-queue-stall-check.yml` - Triage step 2 (the single line containing
  `--event merge_group --limit 100 --json `): change `databaseId,workflowName,headBranch,status,conclusion,createdAt,url`
  to `databaseId,workflowName,headBranch,headSha,status,conclusion,createdAt,url`. Nothing else on the line or file changes.
- `plugins/soleur/test/merge-queue-stall-check.test.sh` - one new arm inside the existing `structural_check`
  (the real-workflow row `S0` runs it; the M0 positive-control chain already includes it), five new
  mutation rows and one must-pass row (labels `MT1`-`MT5`, `PT1`; the label `M15` is taken by an
  existing row), and the `EXPECTED_PASSES` floor. No new engine, no new S-row, no header edit (a header
  edit risks shifting the `:2`/`:14` line citations in `scripts/lib/test-affected-paths.sh`).

## Files to Delete

- `scripts/followthroughs/stall-triage-headsha-12350.sh` - retired by its own header when #12362 closes.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12362-stall-triage-headsha/tasks.md` - task breakdown (planning artifact).
- `knowledge-base/project/specs/feat-one-shot-12362-stall-triage-headsha/decision-challenges.md` - the CTO ruling row.

Pipeline-written files that the diff-scope AC must also allow (sharp-edge: list what the PIPELINE writes):
the plan file, `specs/feat-one-shot-12362-stall-triage-headsha/{tasks.md,decision-challenges.md,session-state.md}`,
`knowledge-base/INDEX.md` if regenerated, and any `scripts/ci-pr-affected-audit.accept.tsv` row the ratchet
requires for the edited suite (see Phase 1.3).

## Open Code-Review Overlap

None checked-in-scope: the query `gh issue list --label code-review --state open` is run at work time
against the three edited paths; the planner-time grep of the issue body for #12362 shows it is itself the
deferred scope-out (`deferred-scope-out`), which this PR closes (the "Fold in" disposition). Record the
result of the `jq --arg path` scan for the two edited paths in the PR description; expected none.

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user surface. A broken edit would make the
  merge-queue stall issue body's Triage step 2 command fail with an unknown-JSON-field error or omit the SHA,
  so the maintainer/agent triaging a suspected stall cannot do the by-SHA correlation the same sentence asks for.
- **If this leaks, the user's data / workflow / money is exposed via:** nothing - the change adds a public
  run-metadata field name to a text template; no credential, token, path or personal data is read or written.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none` because the edit is a documentation-grade field name in an
  agent-facing issue template, with no user-facing or sensitive-path surface (the workflow filename does not
  match the canonical sensitive-path regex, so no scope-out bullet is required).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "insert `headSha` after `headBranch` in the single Triage step 2 `gh run list ... --json` field list" [brief] | Files to Edit: workflow; Phase 2 | mapped |
| 2 | "Leave --jq, prose, steps 1/3/4 and the jq at ~line 222 untouched." [brief] | AC (diff of the workflow is exactly one inserted token); Sharp Edges | mapped |
| 3 | "one new assertion that parses the comma list after `--json ` on that Triage step 2 line and tests MEMBERSHIP of headSha" [brief] | Phase 1 (new `structural_check` arm; `S0`) | mapped |
| 4 | "Write it FIRST and prove it red on the unmodified file." [brief] | Phase 1 step 2 (red proof before Phase 2) | mapped |
| 5 | "Before pushing: python3 -I scripts/ci-pr-affected-replay.py ratchet; bash plugins/soleur/test/fixture-env-adoption.test.sh; bash .claude/hooks/grep-q-pipe-guard.test.sh (flakes under load; re-run before blaming the diff); confirm run-all.sh registration of the suite." [brief] | Phase 4; Research Reconciliation row 1 | mapped |
| 6 | "Delete scripts/followthroughs/stall-triage-headsha-12350.sh" [brief] | Files to Delete; Phase 3 | mapped |
| 7 | "Census: grep scripts, plugins, tests, .github, knowledge-base/engineering for other references; also check closed follow-through issues from the last 14 days for the script name." [brief] | Phase 3 step 1 (+ Research Reconciliation row 2) | mapped |
| 8 | "PR body uses 'Closes #12362' and 'Ref #9927' only, NEVER 'Closes #9927'; closingIssuesReferences must be exactly [#12362]" [brief] | Phase 5 step 1; AC | mapped |
| 9 | "workflow-editing PR so NO agent --admin hatch (UNTRUSTED-CI); Guard 1 evidence is only a merge_group or dispatch run on a SHA (merge_group `test` leg), never a push-run of ci.yml" [brief] | Phase 5 steps 2-4 | mapped |
| 10 | "Monitor not Bash sleep, bare `gh pr merge`, separate git add / git commit calls, check-workflow-duplicate-keys.py after any merge from main" [brief] | Phase 5 | mapped |
| 11 | "after #12362 closes remove its `follow-through` label (reversible); post a Ref-only classification comment on #9927 (must not close/edit/relabel it); reuse open action-required issue #12272 if any operator note is needed, never file new" [brief] | Phase 6 | mapped |
| 12 | "OUT OF SCOPE: any apps/web-platform/infra/** path, apply-web-platform-infra.yml, ci.yml, CI_ORACLE_LANE, the SOLEUR-DEBT marker, ci-head-verdict.sh, all operator-held items" [brief] | Non-Goals; AC (diff-path allowlist) | mapped |
| 13 | "technical forks go to soleur:engineering:cto, recorded in knowledge-base/project/specs/<branch>/decision-challenges.md as `\| Item \| Class \| Ruling \|` rows" [brief] | Files to Create (decision-challenges.md) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Workflow token insert | asks 1-2 | asked |
| New `structural_check` arm (exercised by `S0`) | ask 3 ("parses the comma list ... tests MEMBERSHIP") | asked |
| Five mutation rows + one must-pass row | ask 3 ("cq-assert-anchor-not-bare-token" - mutation-test the anchor) | inferred - justification: the suite's header states "Every structural/behavioural arm is proven live by a mutation row" and the learning precedent requires lookalike (`headShaX`), decoy and absent-line controls; an assertion with no mutation row would be the one arm in the suite that cannot be shown to go red |
| `EXPECTED_PASSES` bump | ask 3 | inferred - justification: the suite ends in an exact floor; adding rows without bumping it exits 1 |
| Probe deletion | ask 6 | asked |
| Census | ask 7 | asked |
| Pre-push checks | ask 5 | asked |
| Merge/queue handling | asks 8-10 | asked |
| Post-merge label removal + #9927 comment | ask 11 | asked |
| decision-challenges.md | ask 13 | asked |
| tasks.md | (skill output) | inferred - justification: the plan skill's Save Tasks step derives tasks.md for `soleur:work`; no product behaviour |

### Split Assessment

- Subsystems touched: 3 - `.github/workflows`, `plugins/soleur/test`, `scripts/followthroughs`
- Planned files: 3 product files (+2 planning artifacts) | Estimated changed lines: ~60 added in the suite, 1 in the workflow, ~45 deleted
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Non-Goals / Out of Scope

Per the brief, none of these is touched or decided here: any `apps/web-platform/infra/**` path,
`apply-web-platform-infra.yml`, `ci.yml`, `CI_ORACLE_LANE`, the `SOLEUR-DEBT` marker, `ci-head-verdict.sh`,
and every operator-held item (A6 signing, the Hetzner checks/question, the off-project copy decision,
host-replace authorisation/dispatch, arm-token revoke/scope/delete, the G2e pin, flip-token design, the
item 7 correction, closing #9927/#12158/#11265). No new GitHub issue is deferred by this plan (no deferral
exists to track).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - CI/tooling change confined to an agent-facing issue template, its
test suite, and a retired follow-through probe. Product/UX Gate: no UI surface (no file matches the
UI-surface term list). GDPR gate, IaC routing, encryption posture, observability schema, task-design and
ADR/C4 gates: skipped - no regulated-data surface, no infrastructure, no persistent store or connection, no
file under `apps/*/server|src|infra` or `plugins/*/scripts`, no new workflow or autonomous task, and no
architectural decision (a one-token field addition does not mislead a reader of the existing ADRs/C4; the
C4 count-parity test is unaffected because no count in `model.c4` derives from this line).

## Guard Contract

The deliverable includes an assertion-based CI check, so the contract applies.

### Guard 1 - Triage step 2 `--json` field list carries `headSha`

**Property.** Exactly one line of the workflow's run bodies is the Triage step 2 `gh run list ... --event merge_group` command, and the comma-separated field list that follows its `--json ` contains the whole field `headSha`.

**Assembly.** The chokepoint is the set of lines, across every `run:` body that `facts.py wf` returns (`.runs[]`, split on newlines), that contain both `gh run list ` and `--event merge_group`; the guard must count that set (not assume one member) and then parse the token after `--json ` up to the first whitespace. Today that set has one member (the line inside the `tmpl` heredoc of the detection step; `grep 'gh run list'` over the whole file returns only that line). Other `--json` consumers in the file (the `gh issue list --json number,title` lines, `gh issue view --json state`) are not `gh run list` lines and are deliberately outside the set; the issue-body prose on the same physical line is excluded by parsing the field list rather than the line. The cause-lookup path uses `gh api`, not `gh run list`, so it is not a member either. If a later change adds a second `gh run list ... --event merge_group` line inside a run body (a copy, or a decoy line quoting the command), the count arm fails closed rather than letting whichever line prints first decide. A line that matches the selector but carries no `--json` list yields a distinct failure (never an empty-output GREEN: the program is run as `jq -e` over a boolean-valued expression).

**Mutation matrix.**

| # | Edit (to a sandbox copy of the workflow) | Must go RED because |
|---|---|---|
| MT1 | drop `headSha` from the field list, leave the prose `by headSha/createdAt` intact (`headBranch,headSha,status` -> `headBranch,status`) | membership, not substring: a bare grep for `headSha` on the line still passes here |
| MT2 | lookalike: `headBranch,headSha,status` -> `headBranch,headShaX,status` | whole-field equality, not prefix/substring |
| MT3 | own dispatch: make the command line stop matching the selector (`gh run list --repo @REPO@ --event merge_group` -> `gh run view --repo @REPO@ --event merge_group`) | zero members must fail ("exactly one ... found 0"), never "0 checked, exit 0" |
| MT4 | second member after a compliant first: insert, INDENTED to the block-scalar level (10 spaces) inside the same `tmpl` heredoc, a second `gh run list ... --event merge_group --json databaseId,url` line (a column-0 line breaks the YAML, and a real YAML comment is stripped by the loader and would never count) | count must be exactly 1 ("found 2"); a check that stops at the first member is the defect |
| MT5 | selector still matches but the `--json ` list is gone (`--json databaseId,...,url` removed from the line) | a missing list must fail with its own reason, not an empty-output GREEN |

**Harness rows.**

- Must-PASS non-canonical (`PT1`): `headSha` moved to the END of the list (`...,createdAt,url,headSha`) -> `structural_check` GREEN. Proves the check is position-independent and that a stub equal to the canonical string, or one rejecting everything, cannot satisfy the matrix.
- Suite-edit RED: leaving `EXPECTED_PASSES` at 160 while the new rows exist exits 1 with "pass count ... != exact floor" - the existing floor is the row that goes red for a harness edit.
- Positive control: `M0` already chains `structural_check`, so the unmutated sandbox is shown green on the new arm for free.
- Red-on-unfixed proof (Phase 1 step 3): on the unmodified workflow, `S0` fails with a reason naming `headSha`. Because the new arm lives in `structural_check`, the existing structural mutation rows and `M0` also go RED on the unfixed tree (their pristine copy now fails the structural engine) - that cascade is expected, is not a defect, and disappears once Phase 2 lands. Only the `S0` reason text is the evidence to record.

**Anchor.** The assertion compares a field list to a literal token. A weakening that passes needs BOTH the test and the workflow edited in one diff, which is the normal shape of this PR, so the guard proves consistency, not integrity. The independent anchor is the real `gh run list` field set: an AC runs `gh run list --event merge_group --limit 1 --json databaseId,workflowName,headBranch,headSha,status,conclusion,createdAt,url` read-only against the live CLI (an unknown field is rejected by `gh`), and the existing structural arm requiring `gh run list [^\n]*--event merge_group` stays untouched.

## Implementation Phases

### Phase 1 - Test first (RED)

1. Add the arm at the END of `structural_check` in `plugins/soleur/test/merge-queue-stall-check.test.sh` (after the drain arms, so every existing structural mutant still hits its own reason first), before `return 0`. It reuses the already-parsed `$f` (`python3 "$HELPER" wf`; no new Python) and the `REASON` contract of its neighbours:
   - count: `jq -e '[.runs[] | split("\n")[] | select(test("gh run list ") and test("--event merge_group"))] | length == 1' <<<"$f"`; on failure `REASON="expected exactly one Triage step 2 gh run list --event merge_group line (the template moved or was copied?)"` (include the observed count via a second jq call);
   - membership, as `jq -e` over a boolean-valued program: `[...same selector...][0] | capture("--json (?<f>[^ ]+)").f | split(",") | any(.[]; . == "headSha")`; on failure `REASON="Triage step 2 --json field list lacks headSha"`. A selected line with no `--json` makes `capture` emit nothing and `jq -e` exit 4, which is a failure with its own REASON (`"Triage step 2 line carries no --json field list"`) - never a plain `jq` whose empty output reads as success;
   - stay within the existing pipe shapes (jq with here-strings, no `| grep -q`), so `.claude/hooks/grep-q-pipe-guard.test.sh` is unaffected.
2. No new pass-producing row is needed for the real workflow: `S0` (`structural_check "$WF_REAL"`) already runs the arm. Do NOT bump `EXPECTED_PASSES` yet.
3. **Prove it red on the unmodified workflow** (before any edit to the `.yml`): run `bash plugins/soleur/test/merge-queue-stall-check.test.sh` with a long timeout (the suite is ~20 s measured in `scripts/suite-durations.tsv` but took >110 s on a loaded machine; use the 600000 ms Bash cap or a `Monitor` until-loop on its output file, never `sleep`); capture the output to a scratch file and confirm `S0` appears under FAIL with `lacks headSha` in its reason. Also run the old probe `bash scripts/followthroughs/stall-triage-headsha-12350.sh` and record `exit 5` on the unfixed tree (two independent parsers agreeing; sharp edge: never delete a probe on the strength of its own conclusion alone).
4. Add the mutation rows MT1-MT5 and the must-pass row PT1 (matrix above) after the existing `MD*` block, as `mutate "<label>" structural '<expected-reason-regex>' "<python expr over s>"`. Anchor every python expression on the exact pristine substring (for MT1/MT2/PT1 `headBranch,headSha,status` - only valid AFTER Phase 2 lands, so write them now and expect them to be unrunnable-until-fixed; the engine reports "mutation did not land" on the unfixed tree, which is the correct red). For PT1 build the mutant inline (python, `cmp` guard, then `structural_check` GREEN -> `pass`, else `fail`) since `mutate` expects RED. Labels `MT*`/`PT*` are fresh (`grep` the suite first); `M15` is an existing row.

### Phase 2 - The one-token fix (GREEN)

1. `Edit` line 263 of `.github/workflows/merge-queue-stall-check.yml`: `headBranch,status` -> `headBranch,headSha,status` in the `--json` list, anchored on the full original list string so the prose `headSha/createdAt` on the same line cannot be the match. Use a unique `old_string` (the whole `--json databaseId,workflowName,headBranch,status,conclusion,createdAt,url` fragment).
2. `git diff -U0 origin/main -- .github/workflows/merge-queue-stall-check.yml`: exactly one `-` and one `+` line, differing by exactly `headSha,`.
3. Re-run the suite (long timeout as in Phase 1); `S0`, MT1-MT5 and PT1 pass; count the PASS total and set `EXPECTED_PASSES` to the observed value (expected 160 + 6 = 166: MT1-MT5 and PT1; trust the run, not this arithmetic) immediately next to the `if`, then re-run once more to green.
4. Live-CLI anchor: `gh run list --event merge_group --limit 1 --json databaseId,workflowName,headBranch,headSha,status,conclusion,createdAt,url` exits 0 (read-only, authenticated `gh`; an unknown field would make gh exit non-zero).
5. Run the old probe: `bash scripts/followthroughs/stall-triage-headsha-12350.sh` -> exit 0 `PASS` on the fixed tree (it is the independent parser from step 3 above).

### Phase 3 - Retire the probe

1. Census (re-run; it is cheap): `git grep -n 'stall-triage-headsha' -- scripts plugins tests .github knowledge-base/engineering` (expect no hits), `git grep -n 'followthroughs/stall-triage'` repo-wide minus planning artifacts, and `gh issue list --label follow-through --state closed --search "closed:>=$(date -u -d '14 days ago' +%F)" --limit 100 --json number,body` filtered with standalone `jq --arg` for the script name (expect none). Disposition every hit in the PR description; a hit that is a live registry row is a Files-to-Edit entry.
2. `git rm scripts/followthroughs/stall-triage-headsha-12350.sh` (never `git add -A`).
3. Run `bash plugins/soleur/test/ship-followthrough-directive.test.sh`; the census above is the authority that no suite or registry enumerates the deleted file.

### Phase 4 - Pre-push verification

Run each as its own Bash call (read the exit code of each; no pipes that mask it):

1. `python3 -I scripts/ci-pr-affected-replay.py ratchet` - the edited suite is listed in `scripts/ci-pr-affected-audit.accept.tsv` (rows keyed by file, target and a hash, with line numbers cited in the reason prose, e.g. `...test.sh:754`). If the ratchet reds because inserted lines shifted a cited line number or a new `.github/workflows/*.yml` mention needs an accepted row, update the tsv row(s) in this PR and say so in the PR body. Do not hand-edit hashes: regenerate through the script's documented path (`--help`).
2. `bash plugins/soleur/test/fixture-env-adoption.test.sh`.
3. `bash .claude/hooks/grep-q-pipe-guard.test.sh` - it flakes under load (SIGPIPE probe); on a red, re-run twice before attributing it to the diff, and compare its derived-triple count to `origin/main` (the precedent's count was unchanged).
4. Registration confirmation (replaces the brief's "run-all.sh" wording, see Research Reconciliation): `git ls-files scripts/suite-shard-legs.tsv` row exists (`grep -n 'merge-queue-stall-check' scripts/suite-shard-legs.tsv`), then `bash plugins/soleur/test/scripts-shard-totality.test.sh`, and `bash plugins/soleur/test/merge-queue-stall-check.test.sh` once more as the final authority. The per-edit selection of the suite via `scripts/lib/test-affected-paths.sh` already lists both the workflow and the suite.
5. `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-11-08-fix-merge-queue-stall-triage-headsha-plan.md` (the plan's Guard Contract) and `python3 .github/scripts/check-workflow-duplicate-keys.py` (it scans every workflow under its root and takes no per-file argument).
6. `bash scripts/test-all.sh` is NOT run whole; the targeted suites above are the verification plus CI's full run.

### Phase 5 - Ship and merge (workflow-editing PR; no `--admin`)

1. `git add` and `git commit` as two separate Bash calls (never chained); commit trailer per the session attribution. PR #12378 exists as a draft: take it out of draft via the ship skill. PR body: `Closes #12362`, `Ref #9927`, a Decision Classes table rendered from `decision-challenges.md`, no other closing verb in prose; `gh pr view 12378 --json closingIssuesReferences` must show exactly `#12362` before arming the merge.
2. Because the diff edits a file under `.github/workflows/`, the merge is NOT agent-`--admin` (UNTRUSTED-CI). Use the bare `gh pr merge 12378` form the lifecycle prescribes (the repo's merge-queue ruleset supplies the method; no `--admin`, no `--squash` override), then wait with the `Monitor` tool on the PR's state/check conclusions with an until-loop - never `Bash sleep`, never a backgrounded Bash poll (`hr-monitor-not-run-in-background-for-polling`).
3. Guard 1 evidence = a `merge_group` run (the `test` aggregate leg) or a `workflow_dispatch` run on the SHA - never a `push`-run of `ci.yml` and never the PR-event checks alone. Read the queue candidate's run for the entry's temp ref (`gh run list --event merge_group --json databaseId,workflowName,headBranch,headSha,status,conclusion --limit 50`, filtered by `headBranch` starting `gh-readonly-queue/main/pr-12378-`; `headSha` makes the by-SHA check possible with the very field this PR adds) and record its conclusion in the PR/ship record. If the queue ejects the entry, read the failing context before any re-enqueue; do not bypass.
4. After any merge FROM main into this branch (queue rebase conflicts, `git merge origin/main`), run `python3 .github/scripts/check-workflow-duplicate-keys.py` before pushing.

### Phase 6 - Post-merge (soleur:postmerge)

1. Verify `gh issue view 12362 --json state,closedByPullRequestsReferences` -> `CLOSED` by PR #12378 (closing is the merge's job; do not close it by hand unless the keyword failed, and then with a comment citing the merge commit).
2. After it is closed: `gh issue edit 12362 --remove-label follow-through` (reversible: `--add-label follow-through` restores it). Reason: the sweeper's closed-set pass would otherwise keep running a probe path that no longer exists for the whole lookback window. Verify with `gh issue view 12362 --json labels`. First confirm the label name exists in the issue's label set (it does today: `follow-through`).
3. Post ONE comment on #9927 via `gh issue comment 9927 --body-file <file>` (a body file, not inline, to keep the keyword scan out of shell quoting): a Ref-only classification, e.g. "Classification (Ref only; this comment does not close, edit or relabel the epic): #12362 / PR #12378 is a merge-queue triage-template fix (one `--json` field added to the stall issue's Triage step 2), not an epic deliverable; the epic's Hold lines and close conditions are unchanged." The body contains no `Closes`/`Fixes`/`Resolves` verb. Never `gh issue close`, `gh issue edit` or label changes on #9927. Verify afterwards: `gh issue view 9927 --json state,labels,title` unchanged (OPEN).
4. No operator note is needed (nothing in this change requires the operator). If one arises, append it to the existing open `action-required` issue #12272 (`gh issue comment 12272`); never `gh issue create` a new `action-required`.
5. `rf-after-merging-read-files-from-the-merged`: read the merged workflow line 263 on `origin/main` (`git show origin/main:.github/workflows/merge-queue-stall-check.yml` filtered to the Triage step 2 line) and confirm `headSha` is in the field list; confirm the probe file is gone on main.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git diff -U0 origin/main -- .github/workflows/merge-queue-stall-check.yml` shows exactly one removed and one added line, and the only character difference is the inserted `headSha,` after `headBranch,` inside the `--json` list of the single `--event merge_group --limit 100 --json ` line (`--jq`, prose, steps 1/3/4 and the jq near line 222 byte-identical).
- [ ] RED proven before the fix: the captured run of the suite against the unmodified workflow shows `S0` failing with a reason naming `headSha`, and the old probe printed `exit 5` on that tree (record both in the PR description).
- [ ] `bash plugins/soleur/test/merge-queue-stall-check.test.sh` exits 0 on the fixed tree; the final line reports the exact new pass count and `EXPECTED_PASSES` equals it.
- [ ] Mutation proof: each of MT1-MT5 passes (goes RED for its own reason, no crash signature) and PT1 passes; the must-pass row would fail if the arm rejected a non-canonical position.
- [ ] A bare-token regression is impossible: replacing the arm's membership test with `grep -F headSha` on the line makes MT1 report "guard stayed GREEN" (run once by hand at work time and note it in the PR description).
- [ ] `gh run list ... --json databaseId,workflowName,headBranch,headSha,status,conclusion,createdAt,url --limit 1` exits 0 against the live CLI.
- [ ] The old probe exits 0 (PASS) on the fixed tree before it is deleted; `git ls-files scripts/followthroughs/stall-triage-headsha-12350.sh` returns nothing after `git rm`.
- [ ] Census recorded: no content reference to `stall-triage-headsha` in scripts/plugins/tests/.github/knowledge-base/engineering; no closed `follow-through` issue in the last 14 days names the script.
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet`, `bash plugins/soleur/test/fixture-env-adoption.test.sh`, `bash .claude/hooks/grep-q-pipe-guard.test.sh` (re-run on flake), `bash plugins/soleur/test/scripts-shard-totality.test.sh`, `python3 .github/scripts/check-workflow-duplicate-keys.py` all exit 0.
- [ ] PR diff paths are a subset of: the three product files, the plan, `specs/feat-one-shot-12362-stall-triage-headsha/{tasks.md,decision-challenges.md,session-state.md}`, `knowledge-base/INDEX.md` (if regenerated), and `scripts/ci-pr-affected-audit.accept.tsv` (only if the ratchet requires it). No path under `apps/web-platform/infra/`, no `apply-web-platform-infra.yml`, no `ci.yml`, no `ci-head-verdict.sh`.
- [ ] `gh pr view 12378 --json closingIssuesReferences` is exactly `[#12362]`; the body contains `Closes #12362` and `Ref #9927` and no other closing keyword.
- [ ] Merged by the queue without `--admin`; Guard 1 evidence is a `merge_group` `test`-leg run (or dispatch run) on the SHA, recorded in the PR.

### Post-merge (operator-free, agent-run)

- [ ] #12362 is CLOSED by PR #12378; its `follow-through` label is removed (reversible).
- [ ] One Ref-only classification comment exists on #9927; #9927 remains OPEN, title, labels and body unchanged.
- [ ] `origin/main` carries `headSha` in the Triage step 2 field list and no longer carries the probe.

## Test Scenarios

1. Unfixed tree: the arm -> 1 (`S0` red), reason `Triage step 2 --json field list lacks headSha` (the prose `by headSha/createdAt` on that line does not satisfy it).
2. Fixed tree: the arm -> 0.
3. `headShaX` lookalike -> 1 (whole-field equality).
4. Selector no longer matches (command renamed) -> 1, `found 0` (no vacuous pass).
5. A second, indented `gh run list ... --event merge_group` line inside the heredoc -> 1, `found 2`.
5b. Selector matches but no `--json` list -> 1 with its own reason (not an empty-output GREEN).
6. `headSha` last in the list -> 0 (position-independent).
7. Old probe on unfixed tree -> exit 5; on fixed tree -> exit 0 (independent cross-check).

## Risks

- **Line drift in the accept tsv.** Inserted lines in the suite shift line numbers cited in `ci-pr-affected-audit.accept.tsv` reason prose; the ratchet may require touching those rows. Mitigation: Phase 4 step 1; treat as in-scope only if the ratchet says so.
- **Exact pass floor.** A miscounted `EXPECTED_PASSES` exits 1. Mitigation: set it from the observed run, then re-run.
- **Suite runtime / flake.** ~20 s, runs under load in a multi-worktree machine; four foreign `test-all.sh` processes were seen. Mitigation: re-run before blaming the diff; the suite is deterministic (stubbed `gh`).
- **Queue ejection.** Workflow-editing PRs cannot use the agent `--admin` hatch. Mitigation: read the failing context, fix forward; no bypass.
- **Sweeper race.** Between merge and the sweeper's next pass the tracker is already closed by the merge keyword, and the label is removed post-merge; the closed-set pass would otherwise report a missing script as TRANSIENT noise. Low impact.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this plan declares `none` with a reason.
- The edit anchor must be the whole original `--json` list, never `headSha` - that token already appears on the line in prose, so a token-anchored `Edit`/`str.replace` would match the wrong place (and a scripted multi-edit keyed on a literal that also appears in prose can splice the wrong span).
- The new engine must not use `grep -q` after a pipe; the suite has a registry row in `.claude/hooks/grep-q-pipe-guard.test.sh` that exempts only the existing jq wrapper shape.
- Do not run `git stash`; commit WIP instead. `git add` and `git commit` are separate Bash calls; no `git add -A`.
- `hr-when-a-plan-specifies-relative-paths-e-g`: every path above was verified to exist (`git ls-files`) except `plugins/soleur/test/run-all.sh`, which the brief names and which does not exist - see Research Reconciliation.
- Do not widen to the `--jq`, the prose, or the jq near line 222; the next reader of this PR will diff the workflow against the one-token expectation.
