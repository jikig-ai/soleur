# Repairing a silent guard reintroduced the guard's own defect class — in the tests, repeatedly

## Problem

#6775: `.claude/hooks/pre-merge-auto-close-scan.sh` was reported as "scans commit
messages but not the PR body." The PR-body fetch *existed* but was dead code — the
`--repo` slug it built kept the trailing `.git` on SSH remotes, so `gh` errored,
`2>/dev/null || true` swallowed it, and the arm was dark for 17 days while the
suite reported 8/8 passed. The test's `gh` stub ignored `argv`, so the fixture
seam sat above the code under test (the exact
[fixture-seam class](test-failures/2026-07-20-a-fixture-seam-above-the-code-under-test-makes-the-default-path-untestable.md)).

The fix was straightforward. Keeping the fix honest was not: across implementation
and two review rounds, the vacuity kept landing **in the tests**, in the same
shape the hook exists to prevent — a check that looks like coverage while being
structurally incapable of failing.

## Key Insight

**When you repair a guard that failed silently, the tests you write to prove the
repair are the most likely place the same silent-failure class recurs — and a
passing suite, even one with your own green mutation battery, is not evidence.**
Every vacuity in this PR was a test asserting a property over a set it only ever
sampled once, or against a value the boilerplate always contained:

- **Surface assertions matched the deny-message boilerplate, not the attribution
  line.** The deny template names every surface ("GitHub's parser reads the PR
  title, the PR body AND the squash commit body"), so `grep -qF 'the PR body'`
  passed even when a `sort -u -k1,1` collapse dropped that surface from the
  per-issue attribution. Fix: assert the full `#N — referenced from <surface>`
  line, which only the attribution produces.
- **6 of the 9 close keywords were never exercised.** Only `Closes`/`fixes` had
  fixtures; a mutation dropping `fixed`/`resolved` from the label-arm extraction
  flipped a real tracker close from deny→allow with all tests green. Fix: one
  deny + one allow fixture per alternation branch.
- **The keyword-set parity check was a spelling-count.** It counted the closer
  `resolve[sd]?)` and missed a keyword inserted *mid*-alternation
  (`close|complete|fix…`) — the exact drift it named. Fix: extract the
  alternation from the scanner and both hook copies and assert string equality.
- **The gh stub validated only `--repo`.** A slug rebuilt via `GH_REPO` walked
  past both the stub and the static `AC10` grep. Fix: validate `GH_REPO` in the
  stub too, broaden `AC10`.
- **A `Fixed #N` fixture the scanner rejected upstream was vacuous** — the
  laundered target must be resolvable to an observable effect, so pair the
  substring with a line-leading close the scanner admits.

The first mutation battery (10 mutations, all caught, baseline 0) proved nothing
about any of these, because it only mutated what its author imagined. The
independent test-design pass, mandated to find what the battery *missed*, found
five more; keying a second battery on different mutations found the rest. This is
the same lesson as
[[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]] and
[[2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once]], recurring
in the PR whose entire subject is a guard that looked like coverage and was not.

## Solution

- Verified every review finding against the artifact before fixing (several
  "findings" were the reviewer's model; most were real and self-introduced).
- For each fixed defect, a mutation that violates the named property must turn
  the suite red **from a baseline of 0** — and the mutation must be confirmed to
  have *landed* (`diff -q` vs a pristine backup), because a `sed`/`perl` anchor
  that silently fails to apply reports the baseline count, which reads exactly
  like "caught nothing to catch."
- Anchor static assertions on syntax the property owns, never a bare token the
  file also names in a comment (the hook's own comments name `--repo` and
  `gh issue list` *because* the code must not) — strip comments first.

## Session Errors

1. **`while ps -ef | grep -q '[t]est-all.sh'` sibling-wait loops deadlocked.**
   Each wrapper's command line *contains* `bash scripts/test-all.sh`, so the
   `[t]est-all.sh` regex matched the sibling *wrappers*, not just the real
   runner, and every wrapper waited forever for the others. Recovery: `kill` the
   stale wrappers. **Prevention:** to wait on a real `test-all.sh`, match the
   child process specifically — `pgrep -f 'scripts/test-all\.sh$'` or
   `ps … | grep '[s]cripts/test-all.sh' | grep -v 'grep -q'` — never a bare
   substring that a sibling command line also carries. Better: don't gate on a
   global process scan at all; run the suite and accept the documented
   sibling-contention re-run instead.
2. **A 2-minute timeout killed a mutation loop before its restore, stranding a
   `fix(es)?` mutation in the tracked hook.** Exactly the trap `review/SKILL.md`
   already documents. Recovery: `git diff` surfaced the one-line drift;
   `git checkout --` restored it (safe here — the hook had no *other* uncommitted
   edits; the legit edits were all in the test files). **Prevention:** mutate a
   **sandbox copy**, never the tracked file; if mutating in place, put the
   restore in a **separate** Bash call and run the suite under a `timeout` short
   enough that the outer harness cannot kill the whole call mid-restore.
3. **Full-suite background runs signal-killed (exit 144 / SIGUSR1)** after many
   concurrent `test-all.sh` runs across sibling worktrees. **Prevention:** don't
   stack multiple background full-suite runs; the local exit gate's purpose
   (catch orphan/sibling suites your diff affects) is met by running the
   specific cross-cutting suite directly, with the complete `test-all` covered by
   CI's required check.
4. **My own commit message carried `fixes #4242` in prose** — would auto-close
   #4242 on merge. The guard this PR builds caught it via
   `auto-close-scan.sh`. **Prevention:** run the scanner over every commit
   message and PR body before committing (already the workflow; here it worked).
5. **test-design-reviewer #1 died on an API ENOTIMP.** One-off; re-spawned.
6. **(Forwarded)** plan AC8/AC10 verify commands were vacuous (matched the hook's
   comments); caught and fixed during /work — the same anchor-on-syntax lesson.

## Tags
category: test-failures
module: .claude/hooks
