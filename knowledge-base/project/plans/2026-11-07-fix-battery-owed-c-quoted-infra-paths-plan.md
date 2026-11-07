---
title: "fix: battery-owed.sh infra refusal reads C-quoted paths and submodule gitlinks (Closes #12251)"
type: fix
date: 2026-11-07
slug: fix-battery-owed-c-quoted-infra-paths
branch: feat-one-shot-12251-battery-owed-c-quoted-infra-paths
issue: 12251
closes: 12251
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: single-domain
---

# fix: battery-owed.sh infra refusal reads C-quoted paths and submodule gitlinks (Closes #12251)

## Enhancement Summary

**Deepened on:** 2026-11-07
**Sections enhanced:** Guard Contract (matrix expected sets), Phase 1 (rows and helpers), Risks, Property List
**Agents used:** plan-review panel (DHH, Kieran, code-simplicity), a sharp-edges verifier over the full catalogue, `soleur:engineering:review:security-sentinel`, `soleur:engineering:review:test-design-reviewer`; mechanical gates 4.6-4.8, 4.11, 4.12 run directly (all pass); gates 4.9, 4.10, 4.13 do not fire (no UI, no store, no new task surface). The 40-agent catch-all fan-out was not run: a one-line change in one script with a ruled design does not repay it, and six independent seats plus live probes already covered correctness, simplicity, tests and security.

### Key improvements
1. A second, PR-carriable submodule hide (a committed `.gitmodules` `ignore = all`) is now a row of its own, alongside the repo-config spelling; matrix row 4 expects both RED.
2. The `diff.relative` row's verdict-line assertion could not go red as first written (`assert_reason` runs from the fixture root); a sub-directory helper is now specified.
3. Four mutation-matrix expected sets (rows 2, 6, 9, 10) were corrected against the script and the existing T5 rows; the SIGPIPE caveat on the `head` mutant is recorded.

### New considerations discovered
- `refs/replace/*` and a missing sentinel on the final here-string grep are pre-existing residuals; recorded in Risks, deliberately not fixed here.
- The suite already carries a real-submodule fixture (the T18x gitlink row) that the new variant reuses.
- Every cited PR, issue and rule id was verified live; `#12247` is a closed issue, `#12294` is the merged PR, `#12246` is a merged PR.

## Overview

`plugins/soleur/skills/ship/scripts/battery-owed.sh` decides whether `soleur:ship` Phase 4 still owes a local test run. Its no-token infra refusal (the block headed "Condition 3" in the script, evaluated after condition 4 at the final `grep -qE "$INFRA_RE" <<<"$CHANGED"`) builds `CHANGED` with `git diff --name-status -M ... | cut -f2- | tr '\t' '\n'`. That line has two blind spots, both measured on a probe repo in this planning session:

1. **C-quoted paths.** Git prints a path holding a byte at or above 0x80, a tab, a double quote or a backslash as a C-quoted string (`"apps/web-platform/infra/\303\251.tf"`). The `^`-anchored `INFRA_RE` never matches the leading `"`, so the infra refusal is skipped and the gate can return SKIPPABLE for a diff that touches the one shard no required CI check covers (#6480). Four probe paths (`é`, tab, `"`, `\`) gave 0 matches with the current line and 4 with the fix.
2. **Submodule gitlinks.** The line does not pass `--ignore-submodules=none`, so a repo-local `diff.ignoreSubmodules=all` hides a gitlink changed under the infra directory. Probe: current line printed nothing, the fixed form printed `apps/web-platform/infra/sub`.

A third hide, found while measuring: the line runs `git diff` in the caller's cwd, so a repo-local `diff.relative=true` run from a subdirectory limits the diff to that subtree (probe: 0 paths from `plugins/`, 4 with `git -C <top>`). The script already resolves the repo top (`_tp`, line 113); using it is a one-token change on a line this PR rewrites anyway.

The fix is the CTO-ruled recipe (decision F4 of PR #12294, 2026-11-07): build `CHANGED` from a NUL-delimited, rename-free list, the form the operator-token arm already uses, and keep `INFRA_RE` and the exit contract (42 skippable / 0 owed / 2 undecidable) untouched. `core.quotePath=false` alone is rejected: it governs only bytes at or above 0x80 (probe: `é` came out unquoted, tab, `"` and `\` stayed quoted).

Closing mechanism (stated honestly): #12251 is a `deferred-scope-out` issue, not a follow-through tracker, and has no soak or post-merge step. The merge of this PR is the fix; the PR body says `Closes #12251`, `Ref #12246`, `Ref #12247`. After the merge, verify the issue reads CLOSED; if the queue's squash did not auto-close it, close it with a comment citing the merge commit.

## Research Reconciliation

| Claim | Reality (measured) | Plan response |
|---|---|---|
| Issue body: "Fix: `git -c core.quotePath=false diff -z --no-renames --name-only`" | With `-z`, git never quotes; `-c core.quotePath=false` is redundant on the `-z` form and insufficient on its own (tab, `"`, `\` stay quoted). | Use `-z` only. Do not add `-c core.quotePath=false`. |
| Handoff recipe: `git -C "$_top" diff ...` | `_top` exists only inside the token branch (line ~295); the unconditional repo-top variable is `_tp` (line 113). | Use `git -C "${_tp:-.}" diff ...`; `${_tp:-.}` keeps the old cwd behaviour if `_tp` were ever empty. |
| Issue body: "condition 3/4 infra check" | One site: the single `CHANGED=` assignment feeds the empty-diff check (line ~278) and the final infra `grep` after condition 4. The token arm builds its own four lists (already NUL-safe). `battery-refusal-wait.sh` uses `core.quotePath=false` plus an unanchored substring match; the leading `apps/web-platform/infra/` survives C-quoting, so it has no blind spot. `scripts/test-all.sh` `_infra_in_diff` is the runner the gate mirrors (parity pinned by T11). | One production edit site. Other readers need no change; recorded so the next reader does not re-derive it. |
| Existing comment at line ~293: "The existing non-token check above shares the C-quoted-path blind spot (#12251)" | Becomes false after this PR. The header comment at lines ~251-271 also explains `--name-status -M` and `tr '\t' '\n'`, both of which go away. | Rewrite both comments in the same edit (Phase 2). |
| T5g comment: "Both die if `tr '\t' '\n'` is removed" | After the fix there is no tab-joined line. The rename rows T5f and T5h now depend on `--no-renames` (a rename-detected diff prints only the new path). | Replace that one comment line in place, keeping the line count (Phase 2), so the accept-row cites stay valid. |

## Research Insights

**Premise validation (Phase 0.6).** `gh issue view 12251`: OPEN, labels `deferred-scope-out`, no closing PR. PR #12326 is this branch's own draft (the collision pre-check's only hit). PR #12294 (merge `46347a44fd`) closed issue #12247. The archived plan `knowledge-base/project/plans/archive/20261107-134717-2026-11-07-feat-ci-is-the-gate-token-reaches-work-review-grok-gate-plan.md` (Non-Goals and Deferrals) holds the recipe and the CTO ruling F4. No ADR gap: the ADR-242 2026-11-07 amendment already says #12251 "ships as its own PR".

**Property List (Phase 0.6b).**
- P-a: a changed path under the infra surface refuses the skip whatever bytes its name holds.
- P-b: a changed gitlink under the infra surface refuses the skip whatever hides it: the repo config key `diff.ignoreSubmodules` OR a per-submodule `ignore = all` in a committed `.gitmodules` (the second is the spelling a PR can carry in its own commit; measured by the security seat: the old form printed only the `.gitmodules` entry, the new form printed the gitlink too).
- P-c: the answer does not depend on the caller's cwd or on `diff.relative`.
- P-d: renames still count on both sides (old path and new path).
- P-e: the exit contract and `INFRA_RE` are unchanged.

**Cut List.**
- `-c core.quotePath=false` on the new line: buys nothing `-z` does not already buy (P-a); rejected by the ruling as a sole fix.
- Reusing the token arm's `_w1` for `CHANGED` (dedupe): the arms have different failure exits (token arm exits through `undecidable "operator ci-is-the-gate set but ..."`); merging is a refactor of a reader the ruling says not to fork. Left as two identical commands.
- A fix to `battery-refusal-wait.sh` or `scripts/test-all.sh`: no blind spot measured (above).
- A new suite file: would add `suite-durations.tsv` and `suite-shard-legs.tsv` rows and a new declared edge; extend the existing suite instead.
- An ADR edit: no architectural decision (bug fix on an existing surface).

**Learnings applied.**
- `knowledge-base/project/learnings/test-failures/2026-10-14-c-quoted-names-evade-extension-anchored-list-filters.md`: `core.quotePath=false` governs only bytes at or above 0x80; `-z` is the fix.
- `knowledge-base/project/learnings/2026-11-06-a-nine-seat-review-and-a-16-mutant-battery-both-missed-what-a-fresh-verifier-found.md`: ask what each git plumbing call hides by configuration (`--ignore-submodules=none`, and here `diff.relative`); run a fresh read-only verifier over the final diff.

**Measured on a probe repo** (scratchpad, git 2.56.0): see Overview items 1-3. Rename behaviour is proven by the existing rows T5f-T5h, not by the probe.

## Open Code-Review Overlap

None. Queried 94 open `code-review` issues for `plugins/soleur/skills/ship/scripts/battery-owed.sh`, `plugins/soleur/test/ship-battery-owed.test.sh` and `scripts/ci-pr-affected-audit.accept.tsv`: no body names any of them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "build CHANGED from a NUL-delimited list (`git -c core.quotePath=false diff -z --no-renames --name-only`-style, as the token arm already does) AND add `--ignore-submodules=none`" [brief] | Phase 2 (CHANGED line) | mapped |
| 2 | "Keep the `INFRA_RE` semantics and the battery-owed.sh exit contract (42 skippable / 0 owed / 2 undecidable); do not fork the reader." [brief] | Phase 2 (one edit site; AC-4) | mapped |
| 3 | "Add mutation-proven test rows to plugins/soleur/test/ship-battery-owed.test.sh (a T5-style row with an `é.tf` infra path, a tab/quote path, and a submodule gitlink)" [brief] | Phase 1 (rows), Phase 3 (mutation battery) | mapped |
| 4 | "inserted AFTER the existing accept-row cited lines and re-check scripts/ci-pr-affected-audit.accept.tsv anchors/line numbers after any insertion" [brief] | Phase 1 placement, Phase 4 (accept-row re-check) | mapped |
| 5 | "PR body: `Closes #12251` ..., `Ref #12246`, `Ref #12247`." [brief] | Phase 5 (PR body) | mapped |
| 6 | "Registry rows go in sorted position (scripts/ci-pr-affected-audit.accept.tsv, suite-durations.tsv, suite-shard-legs.tsv)." [brief] | Phase 4 (no new registry rows expected; sorted position if one is needed) | mapped |
| 7 | "Write the ci-is-the-gate token into session-state.md for this run." [brief] | `knowledge-base/project/specs/feat-one-shot-12251-battery-owed-c-quoted-infra-paths/session-state.md` | mapped |
| 8 | "PR merged with required checks green and deploy/health verified post-merge; #12251 closed by the merged fix" [brief] | Phase 5-6 (ship, `soleur:postmerge`) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `battery-owed.sh` CHANGED line, including the trailing `--` pathspec terminator | "build CHANGED from a NUL-delimited list (`git -c core.quotePath=false diff -z --no-renames --name-only`-style, as the token arm already does)" - the token arm's commands end in `-- ` | asked |
| `--ignore-submodules=none` on that line | "AND add `--ignore-submodules=none`" | asked |
| `git -C "${_tp:-.}"` on that line | — | inferred — justification: the handoff recipe spells `git -C "$_top" diff`; `diff.relative` hides a subtree when the caller's cwd is a subdirectory (measured), and the new row for it is the mutation proof, so the token is not untested code |
| Comment rewrites in `battery-owed.sh` (header block, line ~293) | — | inferred — justification: both comments would state a false mechanism after the edit (`--name-status -M`, `tr '\t'`, "shares the blind spot") and the header is this gate's only written rationale |
| T20 rows in the suite (é, tab, quote, backslash) | "a T5-style row with an `é.tf` infra path, a tab/quote path" | asked |
| T20 gitlink row | "and a submodule gitlink" | asked |
| T20 `diff.relative` row | — | inferred — justification: proof for the `-C` token above; without it the token is a dead edit |
| T20 controls (SKIPPABLE for the same shape outside infra) | "Mutation-battery discipline for any new guard: a green unmutated control" | asked |
| T5g comment line edit | — | inferred — justification: the comment names a mutation (`tr '\t' '\n'`) that no longer exists; a stale mutation claim is how a pin rots |
| `print_results` floor bump | — | inferred — justification: the floor is set EQUAL to the row count by the suite's own rule; leaving it low makes a deleted row invisible |
| session-state.md token | "Write the ci-is-the-gate token into session-state.md for this run." | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur` (script and suite), `knowledge-base` (plan, spec artifacts)
- Planned files: 2 product files (plus plan, tasks, session-state, decision-challenges under `knowledge-base/`) | Estimated changed lines: ~150 (about 25 in the script including comments, about 110 in the suite)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** `soleur:ship` Phase 4 returns OWED (a needless local test run) for a diff it should skip, or still returns SKIPPABLE for a diff touching `apps/web-platform/infra/` with an awkward file name, so a red infra suite reaches the merge queue with no blocking check (#6480). The first costs minutes; the second is the defect being fixed.
- **If this leaks, the user's workflow is exposed via:** nothing new. The script reads only git state and, with a token, `session-state.md`; this change adds no input source and no output. The change ships to customers' machines inside the plugin, and a failure there degrades to a local run (the caller treats anything but 42 as OWED).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the failure needs an infra file with an unusual name, an agent that skipped the local shard, AND a red infra suite that no one reads from the non-required `infra-validation` workflow; the merge queue and the required `test` check still gate every merge, so one occurrence is not a single-user incident.

## Observability

```yaml
liveness_signal:
  what: the gate prints exactly one verdict line per call, "battery-owed: OWED|SKIPPABLE|UNDECIDABLE - <reason>", and exits 0, 42 or 2
  cadence: per ship Phase 4 run
  alert_target: the ship transcript and the PR Test plan (the caller echoes the verdict); no pager, by design
  configured_in: plugins/soleur/skills/ship/scripts/battery-owed.sh (say/owed/skippable/undecidable helpers)
error_reporting:
  destination: stdout verdict line plus exit code; every non-42 status is treated by the caller as OWED, so a failure of the check degrades to running the tests
  fail_loud: the reason text names the condition that fired ("diff touches the infra surface ...")
failure_modes:
  - mode: a C-quoted or gitlink infra path is missed again
    detection: suite rows T20a-T20c (CI required test check, shard 3) go red; the control rows keep the failure attributable
    alert_route: the PR check list on any PR that edits the script or the suite
  - mode: the git diff cannot run
    detection: the pipeline's non-zero status reaches the existing undecidable arm ("could not compute the branch diff")
    alert_route: verdict line UNDECIDABLE, treated as OWED
logs:
  where: the ship session transcript and the PR body Test plan
  retention: the PR and session history
discoverability_test:
  command: bash plugins/soleur/skills/ship/scripts/battery-owed.sh --bogus
  expected_output: UNDECIDABLE
```

The probe proves the reader is present and speaks its contract without network or CI state; the infra-specific behaviour is proven by the suite rows in CI, which a 15-second probe cannot hold (the suite takes about 18 s).

## Guard Contract

### Guard 1 — infra refusal sees every infra path git reports

**Property.** Every path git reports as changed in `origin/main...HEAD` that starts with an `INFRA_RE` prefix reaches the `INFRA_RE` grep as its raw bytes, whatever its characters, whether it is a file or a gitlink, and from whatever working directory and diff configuration the gate runs under.

**Assembly.** One chokepoint: the single `CHANGED=` assignment in `battery-owed.sh`, whose value feeds exactly two consumers (the empty-diff `undecidable` check and the post-condition-4 `grep -qE "$INFRA_RE"`). The operator-token arm is a SECOND, separate chokepoint (its four `_w1`..`_w4` lists plus its sentinel grep); it is already NUL-delimited and is out of this PR's edit set, but it shares the property, so the suite row for the token arm (T18e-i) stays in the battery and Phase 3 mutates the shared flags there too. The mirrored predicate in `scripts/test-all.sh` is a third reader, pinned by T11 parity. Members drift; the structural rule is "one diff command, NUL-delimited, rename-free, submodule-honest, repo-top-rooted".

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert the `CHANGED=` line to the pre-fix pipeline (`--name-status -M ... cut -f2- ... tr '\t' '\n'`) | RED: the infra assertions of all four name shapes, the gitlink row and the `diff.relative` row; every control row stays GREEN |
| 2 | Keep the old pipeline but add `-c core.quotePath=false` (the partial fix the ruling rejects) | RED: tab, quote and backslash infra rows, plus the gitlink row and the `diff.relative` row (the old pipeline has neither fix); GREEN: the `é` infra row and every control (proves the partial fix is partial) |
| 3 | Drop `-z` and keep `tr '\0' '\n'` | RED: all four name-shape infra rows (paths come back quoted) |
| 4 | Drop `--ignore-submodules=none` | RED: the gitlink infra rows of BOTH T20b variants (config key and committed `.gitmodules`) |
| 5 | Drop `--no-renames` | RED: T5f and T5h (a rename-detected diff prints only the new path) |
| 6 | Replace `tr '\0' '\n'` with `tr -d '\0'` (second member glued onto the first) | RED: the four T20a infra rows and the T20b gitlink row (the control path `Zcontrol-20/...` sorts before `apps/` and glues in front of it), plus T5b and T5h (the glued workflow literal loses its `$` anchor); GREEN: T20c, T5, T5f, T5g (`apps/` sorts first) |
| 7 | Append `\| head -n 1` to the `CHANGED=` pipeline (check stops at the first member) | RED: the four T20a infra rows and the T20b gitlink row (the control path is first); GREEN: T20c and the existing T5 rows. Under `pipefail` a `head` can SIGPIPE the writer, so the driver compares failing row LABELS, never exit codes |
| 8 | Drop `-C "${_tp:-.}"` | RED: the `diff.relative` row only |
| 9 | Insert an unconditional `owed` immediately BEFORE the `if ! jq -e ... infra-validate-required` block (inside the block T5c would stay green) | RED: every SKIPPABLE-asserting non-token row (T1, T5c, T5e, the T4 family, every T20 control) - only a SKIPPABLE control can see a guard that refuses everything |
| 10 | Rewrite the `CHANGED=` line to `CHANGED=""` (guard reads nothing, "0 checked") | RED: the empty-diff check exits 2 before condition 3 is reached, so every row that reaches that check and asserts 42 or 0 goes RED (T1, the T20 controls and infra rows, T5, T5b, T5f-T5h, and the token-arm SKIPPABLE rows, since that check precedes the token arm); rows that refuse earlier at condition 1 or 2 (T2, T2b, T2c, T5d) stay GREEN |

**Harness rows.**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H1 | Delete one T20 `assert_*` row | RED: the `print_results` floor (set equal to the measured count) |
| H2 | Empty the T20 shape table (the loop iterates nothing) | RED: the `print_results` floor (16 asserts missing); no separate loop counter is kept |
| H3 | Make a shape's file name ASCII (`e.tf`) so its precondition no longer sees a C-quoted INFRA line | RED: the per-shape precondition row (the plain `git diff --name-only` must hold exactly one line starting `"apps/web-platform/infra/`, which the also-quoted control path cannot satisfy), so a row cannot pass vacuously on an unquoted name |
| H4 | Change a control's expected value from SKIPPABLE to OWED | RED: the control (proves the must-PASS rows are asserted, not only the RED rows) |

Note on the gitlink control: a gitlink at `Zcontrol-20/sub` is SKIPPABLE on the unfixed script too; it proves the control state is reachable, and the discrimination is carried by the infra row plus its precondition (zero `sub20` lines in the plain diff).

Must-PASS inputs that are NOT the canonical fixture: the four outside-infra special-character paths (`Zcontrol-20/<name>.md`) and a gitlink outside infra, each expected SKIPPABLE with every required check green.

**Anchor.** The guard compares no stored value. The thing it protects (the `INFRA_RE` prefix set) is pinned against `scripts/test-all.sh` by the existing T11 parity row, and the merge queue plus the required `test` check gate every merge; a diff that weakens both the script and the suite is caught by the suite running the mutated script in CI only if the mutation is one of the rows above, so the matrix is the anchor, re-run by the work phase.

## Implementation Phases

### Phase 1 — RED: add the T20 rows (suite only)

Insert one new section at the END of the suite, immediately before the trailing comment block "The floor counts the instrument self-test's two rows..." (after the T19h block). Every existing accept-row cite (`plugins/soleur/test/ship-battery-owed.test.sh` lines 96, 465, 468, 1105, 1114) stays at the same line, because nothing is inserted above line 1114. The only edit above it is Phase 2's same-line-count comment replacement.

Section shape (named helpers are the suite's own: `new_fixture_root`, `build_fixture`, `in_fixture`, `make_stub`, `head_sha_of`, `run_gate`, `run_gate_sub`, `assert_eq`, `assert_reason`):

- Every precondition count is written `assert_eq 1 "$(... | grep -c ... || true)"`: a bare `grep -c` assignment that counts 0 exits 1 and, under the helpers' `errexit` plus `pipefail`, kills the suite silently instead of recording a FAIL row (as T19 does).
- `T20` header comment: says what is pinned (the C-quote and gitlink and cwd hides), names `#12251`, and states the mutation list in one line (Guard Contract rows 1-10 and H1-H4 are the full list, kept in the plan).
- A small local helper `t20_commit <work> <relpath>`: `in_fixture "$work" bash -c 'mkdir -p "$(dirname "$1")" && printf x > "$1" && git add -A && git commit --quiet -m t20' _ "$relpath"`, so the special bytes travel as an argv element, not through a nested quote layer.
- `T20a` shape loop over a table of four names built with ANSI-C quoting: `é` (`$'\303\251'`), tab (`$'t\tb'`), double quote (`$'q"x'`), backslash (`$'b\\s'`). Per shape, a fresh fixture, then:
  1. control: commit `Zcontrol-20/<name>.md` (the `Z` makes it sort before `apps/`), make the stub green for the new head, assert SKIPPABLE;
  2. commit `apps/web-platform/infra/<name>.tf`, then the precondition: the plain `git diff --name-only refs/remotes/origin/main...HEAD` (default config) holds exactly one line starting `"apps/web-platform/infra/` (counted with `grep -c`; the C-quoted control path must not satisfy it, so the row exercises C-quoting and fails loudly if the fixture env ever unquotes);
  3. re-stub for the new head, assert OWED and `assert_reason ... "diff touches the infra surface"` (condition 3 specifically, not an accidental refusal).
  One fresh fixture per shape is deliberate: sharing one fixture would let the first infra file make every later row OWED, so the shapes could not be told apart.
- `T20b` gitlink: fresh fixture; `git config diff.ignoreSubmodules all`; add each gitlink with `git update-index --add --cacheinfo 160000,<head sha>,<path>` and commit; precondition: after the infra gitlink commit, the plain `git diff --name-only` output holds zero lines matching `sub20` (counted with `grep -c`, so the fixture's other changed file does not make the check vacuous); control with the gitlink at `Zcontrol-20/sub` asserts SKIPPABLE; the same gitlink at `apps/web-platform/infra/sub20` asserts OWED plus the reason.
- `T20b` second variant (the committed spelling): a fresh fixture that reuses the existing T18x one-liner (the row "a gitlink under the infra surface hidden by ignore=all" in this suite: `git init ../subsrc`, an empty commit, `git submodule add` with `protocol.file.allow=always`, `git config -f .gitmodules submodule.<path>.ignore all`, `git add -A`, commit) with the submodule at `Zcontrol-20/sub` for the SKIPPABLE control and at `apps/web-platform/infra/sub` for the OWED row plus reason, and a precondition of zero plain-diff lines matching `infra/sub$`. `.gitmodules` is not a tracked file of this repo, so mentioning it creates no audit pair. Variant 1 (config key) uses `update-index --cacheinfo` as above.
- `T20c` cwd: fresh fixture; set `git config diff.relative true` first; control: run from the subdirectory `plugins` with no infra change, assert SKIPPABLE; then commit an ASCII `apps/web-platform/infra/rel20.tf`; precondition: the plain `git diff --name-only` run in `plugins` holds zero lines matching `rel20` (the fixture's `plugins/soleur/thing.md` still shows, relative, so count the infra name, not the whole output); then `run_gate_sub` from `plugins` asserts OWED. The reason assert needs a sub-directory VERDICT-LINE helper: `assert_reason` goes through `run_gate_out`, which always runs from the fixture root where `diff.relative` has no effect, so it would pass on the unfixed script (measured by the test-design seat). Add a local `t20_reason_sub <work> <stub> <subdir> <needle> <label>` that mirrors `run_gate_out` with `cd "$work/$subdir"`, ends in `return 0` (errexit) and reports through `assert_eq` like `assert_reason`.
- `print_results` floor: run the suite once after the rows land and set the number to the exact PASS count it reports (the existing rule: equal, never below). Expected: 391 + 28 = 419 (4 shapes x 4 asserts, gitlink variant 1: 4, variant 2: 4, cwd 4; re-count from the suite's own output, do not trust this figure).

Run: `bash plugins/soleur/test/ship-battery-owed.test.sh` (this one file; the operator constraint forbids the full or affected battery). Expected at this point: the T20 infra and reason rows FAIL against the unfixed script, controls PASS. That RED state is the evidence of `cq-write-failing-tests-before`; record the failing row labels in the work log.

### Phase 2 — GREEN: the one production edit

In `plugins/soleur/skills/ship/scripts/battery-owed.sh`, replace the `CHANGED=` assignment (currently `git diff --name-status -M refs/remotes/origin/main...HEAD 2>/dev/null | cut -f2- | tr '\t' '\n'`) with:

```bash
CHANGED="$(git -C "${_tp:-.}" diff -z --no-renames --ignore-submodules=none --name-only refs/remotes/origin/main...HEAD -- 2>/dev/null | tr '\0' '\n')"
```

Keep the `rc=$?` line and the `undecidable` arm unchanged (pipefail makes a failing `git diff` surface). Keep `INFRA_RE`, the empty-diff check and the final grep unchanged.

Comment edits, all in the same hunk region and none naming a new real file path (the audit reads this script's text; mention only paths the script already names):
- Replace the block above `CHANGED=` (the `--name-status -M` / `tr '\t' '\n'` / "A COPY is not affected" paragraphs) with at most about 6 lines: "same construction and reasons as the operator-token arm below" (do not repeat its NUL, `--no-renames` and `--ignore-submodules=none` rationale), plus only what is new: `git -C` the repo top because `diff.relative` limits the diff to the cwd subtree; `core.quotePath=false` alone is not a fix (it governs only bytes at or above 0x80); a COPY needs no handling and `-C` must not be added. The rename rows T5f-T5h are named as the pins.
- DELETE (do not rewrite) the sentence "The existing non-token check above shares the C-quoted-path blind spot (#12251)." at the end of the token-arm comment; a historical "since #12251" note would itself go stale.
- Leave the suite comment near line 425 (it records the original `--name-status` measurement) as it is.
- In `plugins/soleur/test/ship-battery-owed.test.sh`, replace only the comment line "Both die if `tr '\t' '\n'` is removed from the CHANGED pipeline." (T5g/T5h block) with a same-length statement that T5f and T5h die if `--no-renames` is dropped; the line count of the file above line 1114 must not change (`wc -l` before and after the edit, compared with the accept-row cites).

Run the suite again: all rows green, floor equal to the PASS count.

### Phase 3 — mutation battery (Guard Contract rows 1-10, H1-H4)

Discipline from the brief: a green unmutated control, a mutation-landed check, a lead-unique scratchpad name, at most two targeted fix rounds plus one verification pass.

- Scratchpad driver `/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/04e4ac0f-4106-40cb-aa48-61f77a3bd7dd/scratchpad/mut-12251-battery-owed.sh` (the session scratchpad; the lead-unique token is `12251`). It: (1) backs up the script and the suite to files in the same scratchpad; (2) runs the suite once unmutated and requires `rc=0` and the expected PASS count (green control); (3) per mutation, applies a `sed`/`ed` edit to the REAL file in the worktree, then asserts `cmp -s backup file` is false and that the diff contains the expected hunk (mutation-landed check, so a no-op `sed` cannot read as a surviving mutant); (4) runs the suite, captures the failing row labels, and compares with the matrix's expected set; (5) restores from backup unconditionally (EXIT trap) and finishes with `git diff --stat` equal to the pre-battery stat.
- Never use `git stash`; restore by copying the backup back. No `rm -rf` in the worktree (the scratchpad is outside it).
- Each mutation runs the single suite (about 20-25 s); ten script mutations plus four harness edits is a few minutes.
- A mutant that survives (suite stays green) is a missing row: add the row, re-run only that mutation (fix round 1); a second miss is fix round 2; then one full verification pass.

### Phase 4 — registry and ratchet re-check

- `scripts/ci-pr-affected-audit.accept.tsv`: the five rows citing `plugins/soleur/test/ship-battery-owed.test.sh` lines 96, 465, 468, 1105, 1114 must still point at the same lines. Verify with `sed -n '96p;465p;468p;1105p;1114p'` before and after (identical output), and `git diff --stat -- scripts/ci-pr-affected-audit.accept.tsv` is empty. No accept row cites the script `battery-owed.sh` by line (`grep -n 'battery-owed.sh' scripts/ci-pr-affected-audit.accept.tsv` is empty), so editing it moves no cite.
- No new declared edge, no new suite: `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv` are generator-owned and untouched (the suite keeps its measured row and shard leg 3).
- New fixture names must not be real repo files: `Zcontrol-20/...`, `apps/web-platform/infra/<name>.tf` and `apps/web-platform/infra/sub20` do not exist, so no new file-mention pair appears. Do not write `README.md`, `.gitignore` or any other existing repo file name in the new section or the comments (each such mention is a new audit pair needing an accept row). Verify with `git grep -n` on the added lines against `git ls-files`.
- CI's advisory `affected-index-ratchet` runs for the PR and is the evidence of record; if it reports a new pair, add its accept row in sorted position keyed by the 12-hex anchor with a file:line cite, and re-check that no earlier cite moved. Run `python3 -I scripts/ci-pr-affected-replay.py ratchet --report <scratchpad file>` once (about 6 minutes; it is not the test battery, which the operator constraint waives) and record that it reports 0 new pairs: cites staying put proves nothing about a NEW pair, and the ratchet is content-keyed.
- Single-file runs of the repo-global linters that read `*.test.sh` text, because the local battery is waived and the new section adds text for them: `bash .claude/hooks/hook-suite-dep-unresolved.test.sh` (no quoted literal holding the skip token followed by `exit`/`return 0`), `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `python3 scripts/lint-trap-tempfile-ownership.py`, `bash scripts/lint-orphan-test-suites.sh`. The new section uses `grep -c` (never `grep -q` on a pipe) and the suite's existing `new_fixture_root` trap ownership.

### Phase 5 — ship

`soleur:ship` canonically (never the slash form in any file). Phase 4 of ship will read the `ci-is-the-gate` token in `session-state.md` and print the SKIPPABLE verdict (this diff does not touch the infra surface, so the token's infra refusal does not fire); rely on CI's required `test`, `lockfile-sync`, `markdown-lint` and `tenant-integration-required`; read `infra-validation` and `sandbox-canary-capture-gate` by hand.

PR body (backtick every file path that is not in the diff or avoid naming it; the diff contains the script, the suite and the plan artifacts):

- `Closes #12251` (deferred-scope-out, merge delivers the fix), `Ref #12246`, `Ref #12247`.
- Net issue flow: files 0 issues, closes 1 (#12251); declared in the PR body.
- Test plan states: local battery NOT executed per the operator constraint; operator declared CI `test` the gate; the one suite run locally plus the mutation battery results (counts, not prose).
- `## Changelog` section; `semver:patch` label.
- Never push while the PR is queued: `bash plugins/soleur/scripts/sync-pr-behind.sh 12326 --queue-state` must read `not_queued` before any push; a second dequeue means stop and report.

### Phase 6 — post-merge

`soleur:postmerge`: there is no runtime deploy surface (a plugin script and its suite). Verify: the PR is MERGED, #12251 reads CLOSED (close it with the merge commit cited if the queue did not), the required checks were green on the merge commit, and the release workflow `version-bump-and-release.yml` ran for the merge. The "deploy/health" evidence is the green `test` check plus the release run; there is no host or app to health-check.

## Files to Edit

- `plugins/soleur/skills/ship/scripts/battery-owed.sh` — the `CHANGED=` line and two comment blocks (Phase 2).
- `plugins/soleur/test/ship-battery-owed.test.sh` — new T20 section before the floor comment, floor bump, and one same-length comment line in the T5g/T5h block.

## Files to Create

- None under product paths. Planning artifacts only: this plan, `knowledge-base/project/specs/feat-one-shot-12251-battery-owed-c-quoted-infra-paths/tasks.md`, `session-state.md`, `decision-challenges.md`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — an engineering-only fix to a plugin gate script and its suite. No UI-surface file, no regulated-data surface, no new infrastructure, no persistent store, no architectural decision (the ADR-242 2026-11-07 amendment already records that #12251 ships as its own PR).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-1: `bash plugins/soleur/test/ship-battery-owed.test.sh` exits 0 and its PASS count equals the `print_results` floor.
- [ ] AC-2: against the UNFIXED script the T20 infra and reason rows fail and the T20 control rows pass (RED recorded in the work log with the failing labels).
- [ ] AC-3: `git grep -c -e '^CHANGED="$(git -C "${_tp:-.}" diff -z --no-renames --ignore-submodules=none --name-only' -- plugins/soleur/skills/ship/scripts/battery-owed.sh` prints 1 (it prints 0 on the unfixed script, so the check is not satisfied by the token arm's identical substring), and `git grep -c -e '--name-status' -e 'cut -f2-' -- plugins/soleur/skills/ship/scripts/battery-owed.sh` prints 0 (the rewritten comments never spell those tokens).
- [ ] AC-4: `INFRA_RE`, the `VERDICT_*` values and the three exit codes are untouched: `git diff origin/main...HEAD -- plugins/soleur/skills/ship/scripts/battery-owed.sh` shows no added or removed line containing `INFRA_RE=`, `VERDICT_` or an `exit` of those values; T11 parity and T12 still pass.
- [ ] AC-5: the mutation battery reproduces matrix rows 1-10 and H1-H4 exactly (each RED set equals the expected set, the unmutated control is green, each mutation's landed check passed, the worktree is restored byte-for-byte).
- [ ] AC-6: `sed -n '96p;465p;468p;1105p;1114p' plugins/soleur/test/ship-battery-owed.test.sh` is identical before and after the change, and `git diff --quiet origin/main...HEAD -- scripts/ci-pr-affected-audit.accept.tsv scripts/suite-durations.tsv scripts/suite-shard-legs.tsv` exits 0 (or, if the ratchet demands a row, the row is in sorted position with a verified cite); the local ratchet report shows 0 new pairs.
- [ ] AC-7: `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-11-07-fix-battery-owed-c-quoted-infra-paths-plan.md` passes; markdownlint passes on the plan and tasks files.
- [ ] AC-8: PR body carries `Closes #12251`, `Ref #12246`, `Ref #12247`, declares net issue flow (files 0, closes 1), backticks every file path, and contains no `Closes` for any tracker.
- [ ] AC-9: required checks `test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required` green; `infra-validation` and `sandbox-canary-capture-gate` read by hand and recorded.

### Post-merge

- [ ] AC-10: PR MERGED, #12251 CLOSED by the merge (or closed by hand with the merge commit cited, stated as such), release workflow ran, required checks green on the merge commit.

## Test Scenarios

- T20a (x4 shapes): infra path whose name holds `é`, a tab, `"` or `\` with every required check green -> OWED, reason names the infra surface; the same name outside infra -> SKIPPABLE.
- T20b: gitlink under infra with `diff.ignoreSubmodules=all` -> OWED; gitlink outside infra -> SKIPPABLE.
- T20c: infra file with `diff.relative=true`, gate run from `plugins` -> OWED; same state before the infra commit -> SKIPPABLE.
- Existing regression set: T5-T5h (both prefixes, self-retire, rename out and in), T11 parity, T12 timeout pin, T18 token arm, T19 `--token-only` and call sites.

## Risks and Sharp Edges

- A mutation helper that runs inside `$( )` or edits a copy the suite does not read leaves mutants "surviving" for the wrong reason; the driver edits the real file (the suite resolves its gate relative to its own location) and checks the mutation landed.
- `git_fixture_env` may already set a quoting config; the per-shape precondition (plain diff prints a leading `"`) turns that into a loud failure rather than a vacuous pass. Work must confirm it on the first RED run.
- Git sorts the diff by path bytes; the glue and first-member mutations (rows 6 and 7) only bite because the control path begins with `Z` (0x5a) and sorts before `apps/` (0x61). A rename of the control directory to a lower-case name silently disarms those rows; H3-style review of the first RED run must confirm each of rows 6 and 7 turns red.
- `${_tp:-.}`: `_tp` is a physical path from `pwd -P`; `git -C` with it is safe in a linked worktree. The gate's existing `unset GIT_DIR ...` line runs before the `CHANGED=` assignment, so inherited git-location variables cannot redirect it.
- Residuals recorded, not fixed (security seat, 2026-11-07; probed in a scratch repo): (a) `refs/replace/*` can make `HEAD` look like main's tree for every `git diff` and `merge-base --is-ancestor` call in this script (`git --no-replace-objects diff` showed the infra paths); it needs a local ref write, the same class as the already-accepted assume-unchanged residual, and the required `test` check plus the merge queue still gate the merge. Adding `--no-replace-objects` to this one call would cover only this call, so it is not added. (b) The final `grep -qE ... <<<"$CHANGED"` has no sentinel like the token arm's; a here-string whose temp-file write fails (bash older than 5.1, for example the stock macOS bash) could read as no match. Could not be reproduced on bash 5.3; recorded, not changed, to keep one edit site.
- A newline inside a changed path makes `tr '\0' '\n'` split it into two lines; that can only add lines, so it fails toward OWED (the safe direction). Not worth a row.
- A plan or PR body naming a repo file path in plain prose that is not in the diff turns `quality-advisory` red; backtick it or omit it.
- A `## User-Brand Impact` section that is empty or lacks the threshold fails deepen-plan Phase 4.6; this one carries all three lines.
- Components are written canonically (`soleur:ship`, `soleur:postmerge`), never the slash form, or harness-parity Guard 3 fails.
