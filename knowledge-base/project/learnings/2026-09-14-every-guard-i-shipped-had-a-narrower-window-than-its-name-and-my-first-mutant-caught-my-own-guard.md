---
module: System
date: 2026-09-14
problem_type: test_failure
component: testing_framework
symptoms:
  - "Three shipped guards were green on the live tree while each had a path outside its window: B9 never summed verify-doppler-secrets, the ledger enumerator scored cancel=yes on a group carrying github.sha, G5 rows were satisfied by the step's own comments"
  - "A6, written at review to pin the replicated concurrency block, passed vacuously: printf '%s' | while read skipped the only line and the comparison never ran"
  - "Dropping a literal default the pattern seat called dead made the vacuity meta-guard report the suite unconstructible (rc=1) — the in-file comment had said the literal was load-bearing"
  - "PR #8149 went CONFLICTING on the generated knowledge-base/INDEX.md while git merge-tree was clean, and three pushes dispatched zero pull_request workflows — the race the PR documents"
root_cause: missing_validation
resolution_type: test_fix
severity: high
status: open
rule_id: cq-assert-anchor-not-bare-token
synced_to: [review, git-history-analyzer]
tags: [guard-vacuity, mutation-testing, presence-vs-exclusivity, comment-stripped-grep, printf-newline-read, delimiter-collision, ledger, merge-queue, prod-version-drift, pr-fanout]
---

# Every guard I shipped had a narrower window than its name, and my first mutant caught my own guard

## Problem

PR #8149 implemented two decisions left over from the `workflow_run` deploy split
(ADR-217): put the CI term into drift check B9 and raise `DRIFT_SUSTAINED_THRESHOLD_MIN`
207 → 225 (option (a)), and — because the merge queue is not adoptable (CodeQL default
setup never posts on `merge_group`; `codeql-action#1537` still open; a queue adds a run per
merge on a Free-plan 20-slot pool) — bound the per-PR workflow fan-out with a ledger
(`scripts/pr-fanout-ledger.txt` + `plugins/soleur/test/pr-fanout-ledger.test.sh`) as
ADR-216's second filing-time lever, plus a fold of three `ci.yml` jobs and PR-only
`cancel-in-progress` on five stateless workflows.

The work phase shipped three guards, each mutation-proven by its author. A ten-seat review
found 41 findings, all fixed inline, and the structural roll-up was one sentence three
times over: **each guard's assembly was a subset of the property its name claims.**

## Environment

- Module: System-wide (CI machinery, `scripts/`, `plugins/soleur/test/`)
- Affected Component: `scripts/prod-version-drift-check.test.sh` (B9, Part C),
  `plugins/soleur/test/pr-fanout-ledger.test.sh` (enumerator, Parts A/B),
  `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` (GUARD 5),
  `.github/workflows/{ci,web-platform-release,reusable-release}.yml`
- Date: 2026-09-14

## Symptoms

- **Guard 1 (B9)**: the formula `max(ci, release) + resolve-target + migrate +
  verify-migrations + deploy` assumed `verify-doppler-secrets` (a `deploy` prerequisite
  that runs alongside the serial chain) is dominated, and nothing asserted it — raising it
  to 200 m left `crit` at 220 with B8e's set-membership pin untouched. `strategy.max-parallel`
  and a `needs:` predecessor inside the callee's `reusable-release.yml` were equally unread.
- **Guard 2 (ledger)**: `GROUP_RE.search(grp)` scored `cancel=yes` when the group merely
  *contained* a per-PR ref; `pqg-${{ github.ref }}-${{ github.sha }}` never collides across
  pushes and never cancels. `fires()` looked only at `pull_request*`, so
  `fix-constraints-stage-b.yml` (`workflow_run` on stage-a, no `branches:` filter) fired per
  PR push with no row. A `uses:` job counted as 1 while dispatching N callee jobs.
- **Guard 3 (G5)**: every row grepped `budget.blk` un-stripped. The step's own comment quotes
  `THRESHOLD=$(read_threshold)`, so `THRESHOLD=225` on the real line survived (test-design
  S5); `RT=0 # job_ceiling "$REL" resolve-target)` survived G5-21 (S6); a second `RT=0`
  before the arithmetic survived (S7); `… - D + RT ))` survived because the regex had no
  `))` terminator (S4).
- **Harness truth from the SUT**: Part C derived `tail = ctl_crit - max(ci, release)` from
  the extractor's own emit, so dropping `migrate` from the sum shifted every expected figure
  with the defect and all five rows stayed green (S1).

## What Didn't Work

**Attempted Solution 1:** Each guard shipped with a self-run mutation battery (axis13/14/15
+ two must-PASS rows; 13 ledger mutants; the invariants suite's 5/5). All green.

- **Why it failed:** every row perturbed the SUT's *inputs* and read the verdict *through*
  the guard's own predicate. A mutation cannot reach an input class the predicate does not
  quantify over (a chained `workflow_run`), a token the predicate does not test for
  (`github.sha` beside `github.ref`), or a comment the grep does not strip.

**Attempted Solution 2:** Writing A6 at review to pin the five copied concurrency blocks to
`ci.yml`'s group, and checking it by eye.

- **Why it failed:** `while IFS= read -r g; …; done < <(printf '%s' "$tgroup" | tr '|' '\n')`
  — with no trailing newline `read` returns 1 on the only line and the loop body never runs,
  so `a6_ok` stayed 1. Separately the `|` join delimiter split the group at the `||` inside
  `github.event_name == 'pull_request' && github.ref || github.sha`. Both were caught by
  the B6f mutant on its first run (`child exited 0 — mutant SURVIVED`), not by reading.

**Attempted Solution 3:** Applying the pattern seat's "dead default" simplification —
`MIN_CASES="${PR_FANOUT_MIN_CASES:-139}"` → `MIN_CASES="$PR_FANOUT_MIN_CASES"`.

- **Why it failed:** `scripts/guard-vacuity-floor.test.sh` constructs its mutant from a
  LITERAL bound adjacent to the floor's `if`; an env-only bound is unconstructible and the
  suite fell into the uncovered set (`mutant-construction failures GREW to 16`). The file's
  own comment two lines above said "the default stays a literal". A reviewer-prescribed
  simplification is a claim to measure against the guard that depends on the shape.

## Session Errors

**Plan `Write` denied by the IaC write guard** (forwarded) — a passing mention of "the GitHub
UI" matched the vendor-dashboard regex.

- **Recovery:** reworded; no content lost.
- **Prevention:** in plans about CI machinery, say "GitHub's side" / "the Actions API", not
  "the GitHub UI".

**Attribution error in the plan** (forwarded) — `codeql-1537-revisit-watch.yml` finds its
tracking issue by the `merge-queue-revisit` label, not by `#5840`.

- **Recovery:** corrected at four sites in the deepen pass.
- **Prevention:** a "finds issue #N" claim about a workflow is a claim to grep the workflow for.

**`plugin:github` and `playwright` MCP servers failed to connect** (forwarded).

- **Recovery:** every GitHub read went through `gh`; Playwright was not needed.
- **Prevention:** none needed — `gh` is the documented path for these reads.

**Session-start preamble skipped (`plugin-root-unverified`)** — `CLAUDE_PLUGIN_ROOT` is
unset when Claude Code runs from the repo checkout, and ADR-179 forbids defaulting to
`./plugins/soleur`.

- **Recovery:** the readiness fallback (`is-inside-work-tree` = true) cleared the gate; the
  worktree manager was invoked by explicit path later.
- **Prevention:** by design; a session started via the installed plugin sets the root.

**`test-all.sh` refused twice (rc=4)** — three sibling full-gate runs in flight.

- **Recovery:** consumer-derived 80-suite set (`git grep -l <basename>` over every changed
  file + new `SOLEUR_*`/`PR_FANOUT_*`/`DRIFT_*` tokens), run sequentially and detached,
  ~25 min each time; 79/79 green, one DB-backed integration test skipped.
- **Prevention:** already the rule (`work/SKILL.md` §9 fallback); budget for it on a
  contended host and re-run the set when the inputs change.

**`DRIFT_TEST_PARTS=AB` exited 1 on the global `MIN_ASSERTIONS` floor** — the plan's own
Phase 0 command (`… | grep -E "B9|B8e"`) hid the rc behind a pipe.

- **Recovery:** the global floor is asserted equal to `MIN_A+MIN_B+MIN_C` and is therefore
  unreachable on any subset run; it is now checked on full `ABC` runs only, the per-part
  floors guard subsets, and the Check-10 probe needs rc 0.
- **Prevention:** never read a suite's verdict through a pipe (`cmd > log; rc=$?`).

**RED-first predicted two SURVIVED rows and got five reds** — axis15/green1/green2 also
failed by figure mismatch because the expected figures are computed by the intended formula
(tail 150) and the old formula gave 125.

- **Recovery:** recorded verbatim; expected under a formula change.
- **Prevention:** when the RED-first run's expected figures are derived by the NEW formula,
  say so in the plan — every derived-figure row reds, not only the axes.

**A6 `printf '%s'` + `read` loop never executed** — vacuous green (see Attempted Solution 2).

- **Recovery:** `printf '%s\n'` plus a row-count guard (`a6_n >= 1`).
- **Prevention:** a `while read` over `printf '%s'` output skips the last line; write the
  mutant before trusting the assertion.

**`|` join delimiter collided with `||` in the expression** — A6 compared fragments.

- **Recovery:** joined with US (0x1f); `tr '\037' '\n'` on the read side.
- **Prevention:** never join with a character the payload's grammar uses.

**`PERSHA_RE` rejected `ci.yml`'s own ternary-group idiom** — the reference group carries
`|| github.sha` on its non-PR arm.

- **Recovery:** fold `event_name == 'pull_request' && <ref> || github.sha` to `<ref>`
  before the per-run check.
- **Prevention:** run the live tree as the FIRST control of any new exclusion rule.

**Removed the `:-139` literal on the pattern seat's advice** (see Attempted Solution 3).

- **Recovery:** restored as `:-167` with a comment naming the meta-guard.
- **Prevention:** a comment saying why a shape exists is a claim to check by running the
  guard that depends on it before applying a simplification that removes the shape.

**PR went `CONFLICTING` mid-review; zero `pull_request` dispatch for three pushes** — `main`
moved on the generated `knowledge-base/INDEX.md`; `git merge-tree` was clean, GitHub's
test-merge was not.

- **Recovery:** `git merge origin/main`; INDEX regenerated by the pre-commit hook;
  `MERGEABLE` again and dispatch resumed.
- **Prevention:** re-probe `gh pr view --json mergeable` after every push on a fast-moving
  `main`; a clean `merge-tree` is not GitHub's verdict on a generated file.

**git-history seat reported two pre-existing lines as contradictions and a GitHub-side
workflow state as UNVERIFIABLE.**

- **Recovery:** `git show origin/main:` proved the `195 -> 207 (#7902)` line pre-existing
  (#7902 is the issue, #7907 the PR); `gh api repos/{o}/{r}/actions/workflows` returned
  `disabled_manually 2026-02-12` for `claude-code-review.yml`.
- **Prevention:** a workflow's enabled/disabled state lives on GitHub's side — read it from
  the Actions API, never from git.

**test-design seat's sandbox control was red on G4/G8** — the sandbox had no `apps/`, so
the consumer-discovery rows found zero consumers.

- **Recovery:** per-row G5 verdicts read directly (all green in the control), totals discarded.
- **Prevention:** a sandbox for a suite that discovers consumers must carry the consumer tree,
  or the battery reads per-row and states which rows the control could not run.

**Guessed `--changed` for `lint-shell-capture-exit.py`** — it takes paths.

- **Recovery:** re-ran with the six changed shell files.
- **Prevention:** `--help` before assuming a sibling lint's CLI.

**Three folded step names carried an unquoted `, #8149)`** — a space-`#` starts a YAML
comment mid-scalar; the parsed names ended in `,`.

- **Recovery:** quoted the scalars; AC8 amended to `"?` explicitly rather than satisfied by
  a looser grep.
- **Prevention:** quote any YAML scalar containing ` #`.

**`lint-window-closure-assertion.py` fails on five untouched `.test.ts` files on `main`** —
an unregistered lint with standing findings nobody sees.

- **Recovery:** none needed for this PR (files untouched); not filed (net-issue-flow; a
  different subsystem).
- **Prevention:** a lint that is not registered in CI is documentation; register it or
  retire it.

## Solution

**Guard 1 — assert the assumptions, read the tail raw.** The extractor now emits every
summed term plus `verify-doppler-secrets`; B9d asserts
`verify-doppler-secrets <= resolve-target + migrate + verify-migrations`; B9e asserts no
`strategy.max-parallel` in `ci.yml`; B8f asserts the callee's `jobs.release` has no `needs:`.
Part C reads the four tail ceilings raw from the sandbox YAML and asserts they equal the emit
(`C-tail`) — the S1 mutant now reds there. Every mutated value is derived (`v13` = the
smallest `test-scripts` that lifts CI above release AND crit past the threshold), so axis13
keeps proving "CI is in the sum" whatever the tree declares. B9's FAIL prints the term vector
and switches its remedy to "restore `timeout-minutes` on `<job>`" when a deploy-arm term
reads the 360 default.

**Guard 2 — exclusivity, not presence; reach, not the direct trigger.**

```python
# Before: presence — yes if the group mentions a per-PR ref anywhere
if form != "false" and GROUP_RE.search(grp):
    cancel = "yes"

# After: fold ci.yml's idiom to its ref arm, then require a ref AND no per-run token
folded = TERNARY_GROUP_RE.sub(r"\1", grp)
if form != "false" and GROUP_RE.search(folded) and not PERSHA_RE.search(folded):
    cancel = "yes"
```

`fires()` is now a fixpoint over `on.workflow_run` (no `branches` filter, naming a firing
workflow's `name:`); a `uses: ./…` job counts its local callee's jobs; A6 pins every
ternary-form block to `ci.yml`'s group byte-for-byte; the accepted spellings and shapes are
emitted by the enumerator (SPEC records) so messages cannot drift from the scorer. New
mutants: B6e (ref + sha), B6f (ternary with a per-ref-only group), B7b (cancel=no row with
no reason), B11 (`zz-chain.yml`), B12 (`uses:` callee), must-PASS B9b (`branches: [main]`).

**Guard 3 — strip, terminate, count.**

```bash
sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]\{1,\}#.*$//' "$W/budget.blk" > "$W/budget.code"
grep -qE '^\s*CI_BUDGET_MIN=\$\(\(\s*THRESHOLD - RT - M - V - D\s*\)\)\s*$' "$W/budget.code"
for var in THRESHOLD RT M V D CI_BUDGET_MIN CI_DECLARED_PATH_MIN SOFT_CEILING_S; do
  [ "$(grep -cE "^\s*${var}=" "$W/budget.code" || true)" -eq 1 ] || _multi="${_multi}${var} "
done
[ "$(grep -c -- '- name: Derive the CI budget' "$REL")" -eq 1 ]   # no decoy step
```

S4–S7 and the decoy are each killed by name (G5-18, G5-21, G5-22, G5-23).

**Both suites** gain an instrument self-test (drive `pass`/`fail` once, require both counters
to move, `exit 2` otherwise) — a `fail()` that takes the pass branch is caught before Part A.

## Key Insight

**A mutation battery answers "can this guard fail?"; it cannot answer "is the predicate the
property?"** Every row the author writes perturbs an input the predicate already reads and
scores the result through that predicate, so a presence check (`contains github.ref`),
a direct-trigger check (`on.pull_request`), an un-stripped grep, or a tail derived from the
SUT's own emit is invisible to it by construction. The panel's structural-enumeration seat
found the uncovered paths by asking, per guard, "enumerate every path by which a member can
reach the sink" — and the fixes were each an ESCAPE row (pristine guard, corpus it must
refuse), not another mutation row. Companion: the first mutant I wrote at review caught my
own new assertion twice on its first run. Write the mutant before trusting the guard; and
when a reviewer prescribes deleting a shape, read the comment above it — if it says why the
shape exists, run the guard that depends on it first.

## Prevention

- **Per guard, write one sentence for the property and one for the predicate's SCOPE, then
  ask what the property quantifies over that the predicate does not** — transitive dispatch,
  a second token in the same expression, a comment in the grepped block, a parallel branch
  the sum assumes dominated.
- **Every `while read` over `printf '%s'` is a skipped last line.** Use `printf '%s\n'` and
  count the iterations.
- **Never join with a character the payload's grammar uses** (`|` vs `||`); prefer a control
  character (US 0x1f).
- **Run the live tree as the FIRST control of a new exclusion rule** — it is the corpus most
  likely to contain the idiom the rule was not written for.
- **Harness truth comes from the artifact, not from the SUT's emit** — read the raw terms
  and assert the emit agrees (`C-tail`).
- **Grep over code, never over prose**: strip whole-line and trailing comments into a
  `.code` file before any assertion, terminate the anchor, and pin exactly-one binding.
- **A reviewer-prescribed simplification that removes a literal is a claim to check against
  every guard that reads the file's shape** (`guard-vacuity-floor.test.sh` constructs its
  mutant from a literal adjacent to the floor).
- **After each push on a fast-moving `main`, re-read `gh pr view --json mergeable`** — a
  CONFLICTING PR dispatches nothing, and `git merge-tree` does not predict GitHub's verdict
  on a generated file.

## Related Issues

- #8149 (this PR); ADR-216 (filing-time lever), ADR-217 D4 addendum (the formula), ADR-032
  2026-09-14 amendment (queue stays off); #8006 (matrix-leg balance, option (b) input);
  #5800/#5811/#5812 (the 2026-06-30 merge-queue deadlock).
- `knowledge-base/project/learnings/2026-09-10-every-instrument-i-used-to-judge-my-own-guards-agreed-with-them.md`
  — the measure-the-fix-size rule and the vacuous-guard class this PR inherited.
- `knowledge-base/project/learnings/2026-09-10-every-escape-my-mutations-could-not-reach.md`
  — escape rows vs mutation rows, the same finding one PR earlier.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — the window-narrower-than-property class and its structural-enumeration remedy.
- `knowledge-base/project/learnings/2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`
  — comment-collision anchors (G5 S5/S6 are this class).
