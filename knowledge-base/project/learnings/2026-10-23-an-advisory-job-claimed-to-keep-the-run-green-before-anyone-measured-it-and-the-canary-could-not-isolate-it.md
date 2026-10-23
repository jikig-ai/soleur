# Learning: an advisory job claimed to keep the run green before anyone measured it, and the canary could not isolate it

## Problem

PR #10851 (S4 affected-index PR3a, the ratchet job, Ref #10448 / Ref #9729) adds `affected-index-ratchet` as an advisory job (`continue-on-error: true`, `pull_request` and `merge_group` only). Four sites asserted that "`continue-on-error` keeps the `pull_request` and `merge_group` RUN conclusions green while the context is not required": the ci.yml comment, the runbook, ADR-276 amendment item 6 and the probe header. The panel (architecture seat) and the CTO ruling 7 flagged it: no one had measured it, and the sibling `harness-discovery` job's comment stated the opposite view.

The planned canary (a throwaway DRAFT PR with one deliberate unbaselined pair, task 3.5) then produced two results, one of them not the one asked for:

- **Job level (measured):** the failing advisory job concludes `failure` in the jobs API, `gh pr checks` buckets it as `fail`, and the PR check list shows a red check with the `::error exit=1 reason=new-pair` annotation. `continue-on-error` does not render the job green.
- **Run level (not isolated):** the canary run concluded `failure`, but the draft-light `test` leg is red on every draft by design (ADR-276 Option R: a light draft concludes RED) and `e2e` failed on an unrelated `ERR_CONNECTION_REFUSED`, so the run-level effect of `continue-on-error` could not be read from it.

Separately, the audit did not flag the first two canary pairs: a trailing comment is not read (only non-comment text is), and a path already baselined for another suite is a different (suite, path) pair that still needed to be genuinely new for THIS suite; the third attempt used a no-op shell line `: "docs/legal/cookie-policy.md"`.

## Solution

- State only what was measured, at the level it was measured: the job-level `failure` and the red check are measured; the documented run-level behaviour is cited as GitHub's and marked "not confirmed here". All four sites, the observation log and tasks.md were rewritten in one commit, after a sweep of the CLAIM (grep for `keeps the .* RUN conclusions`, `UNMEASURED`, `task 3.5`, `PENDING`) rather than of the new text.
- Verify a canary fixture LOCALLY with the real subcommand before pushing it (`ratchet` on the canary commit gave `exit=1 reason=new-pair`), so a no-op canary never costs a hosted run.
- Record the first hosted datapoint (162 s job wall, `exit=0 reason=pass live=1886 baseline=1886`) as a single point; the 210 s / 270 s ceilings stay provisional.
- After the fix rounds, two further rebases (a sibling ADR-276 amendment and a sibling's anti-vacuity floors in the shared replay suite) were resolved additively; the floor numbers were estimated (898+3, 354+3 and so on) and then CONFIRMED by a measured run (1069 assertions, 420 of 420 mutants) before the push. The baseline was regenerated after each rebase (1887, 1886, 1888 pairs) because main's new suites and declared edges move the live set.
- A squash-then-revert of the branch on `origin/main` gives a tree identical to `origin/main`, which is the shape of the documented rollback.

## Key Insight

A canary only measures the variable it isolates. A DRAFT canary on this repo carries a second, deliberately red job (draft-light `test`), so it can answer "how does this job render" but never "what is the run conclusion". When a claim is about the RUN, design the canary so nothing else in the run is red (a ready PR costs a full battery, which is a budget call), or state the claim at the level you can read. And a claim a reviewer flags as unmeasured is cheaper to fix by rewording to the measured level than by building the experiment that would settle the broader one.

## Session Errors

1. **Asserted "continue-on-error keeps the run green" in four places before measuring** — Recovery: canary plus a claim-keyed sweep, wording replaced at all sites in one commit — **Prevention:** when a plan marks a rendering or conclusion UNMEASURED, write the sentence in the "unmeasured" form from the start and list every site in the task that will replace it (done here: tasks.md 3.5 named the four sites).
2. **Canary pairs 1 and 2 did not trip the ratchet** (trailing comment not read; path already paired elsewhere) — Recovery: ran the real `ratchet` on the canary commit locally until `exit=1`, then pushed — **Prevention:** never push a canary or fixture whose trigger was not reproduced locally first.
3. **Canary run conclusion confounded by the draft-light `test` leg and an unrelated `e2e` failure** — Recovery: reported the job-level result as measured and the run-level result as not isolated — **Prevention:** before running a canary, list the other jobs that will be red on that PR shape and decide whether the claim under test survives them.
4. **Two extra rebases after the fix rounds (sibling ADR amendment; shared replay-suite floor lines)** — Recovery: resolved additively, regenerated the baseline, confirmed floors by a measured run — **Prevention:** run the sibling-PR overlap loop and `git merge-tree` right before the push, not only at review start; hard-coded floors in a shared suite conflict with every sibling that adds rows (ADR-193), so treat floor lines as expected conflict points.
5. **Baseline drift on each rebase (1887, 1886, 1888)** — Recovery: `gen-baseline.sh HEAD`, diff, commit — **Prevention:** none beyond the PR3b entry condition already filed (#10859: cumulative baseline check, rename-carry); regenerate on the final rebased tree.
6. **Wrong suite paths (`scripts/ci-concurrency-key.test.sh`, `scripts/fixture-relative-assert.test.sh`, rc=127)** — Recovery: `git ls-files | grep` for the real paths under `plugins/soleur/test/` — **Prevention:** resolve a suite's path with `git ls-files` before putting it in a detached loop; read every rc file, an rc=127 is "did not run".
7. **`npx markdownlint-cli2` on a spec file the repo ignores (`.markdownlintignore` excludes `knowledge-base/project/`)** — Recovery: ran the repo's own `scripts/markdown-lint.sh` on the two in-scope files — **Prevention:** lint with the script CI uses, not a bare linter.
8. **Hook rejections: `pgrep -f`, a `git stash list` inside a compound command, and `git commit` with a `$VAR` or not-yet-created path** — Recovery: `list_runs`, dropped the stash call, used literal absolute paths and created the worktree in a separate call — **Prevention:** already hook-enforced; use literal `git -C /abs/path` forms.

## Tags
category: logic-errors
module: .github/workflows/ci.yml, scripts/ci-pr-affected-replay.py
