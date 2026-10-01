---
date: 2026-09-22
category: test-failures
module: scripts/lib/repo-write-boundary + shallow-fetch producers
problem_type: logic_error
severity: high
pr: 8510
issues: [7924]
tags: [repo-write-boundary, git-shallow, failure-state-vocabulary, remedy-executability, scratch-isolation, pass-message-interpolation]
---

# Learning: a node that exists but cannot be read is a MEASURED state, and a remedy that cannot run is a defect

Two design lessons dominated the #7924 review round (9-seat code panel + 2 design
lenses on PR #8510), plus a cluster of test-authoring slips worth recording
verbatim because several recurred inside one file.

## 1 — `unreadable` is a state, not an absence

The first sampler for `.git/shallow` did `[[ -e $f ]] && cat $f | sha256sum` —
"exists and readable" collapsed to absent-ish on one axis and blocked forever on
another. Five review seats converged on the two failure modes:

- **A FIFO at `.git/shallow` hangs `cat`** — the after-snapshot never returns,
  and the guard that exists to catch mutation becomes the thing that wedges the
  run.
- **An unreadable/non-regular node launders into UNMEASURABLE** — git itself
  treats an unreadable shallow file as "not shallow" (a real history-availability
  change), while `UNMEASURABLE` is the guard's only *non-blocking* verdict. The
  most dangerous transition shipped with the weakest signal.

The fix is a three-state vocabulary: `absent` / `present<TAB>digest` /
`unreadable`, where `unreadable` covers any node that exists (`-e` or `-L` —
dangling symlinks are not absent) but fails `-f && -r`. Only *toolchain*
failures (common-dir unresolvable, no digest utility) return not-measured →
UNMEASURABLE. The ordering matters: check `-f && -r` **before** opening, never
open then handle the error — for a FIFO there is no error, just silence.

Corollary discovered in test: the honest "does not block" pin is the *dimension
function*, not the snapshot — git itself opens `.git/shallow` while parsing
commits, so a FIFO also wedges `git status` inside `_repo_state`. Scope the
`timeout` bound to the sampler arm; document that git's own read is out of the
guard's control.

## 2 — a prescribed remedy must be executable for the transition that fired

`repo_boundary_next_action` originally answered every shallow FATAL with
`git fetch --unshallow`. The agent-native seat verified against the repo's own
git pin: on a *complete* repository `--unshallow` exits 128 — so for the
`present → absent` transition the guard's advice was a command that cannot run.
Operability is part of correctness: the classifier's detail string now carries
transition keywords (CREATED/REMOVED/CHANGED/readable↔unreadable), the runner
passes it through, and `next_action` dispatches on it — REMOVED and non-regular
transitions prescribe diagnosis (`git rev-parse --is-shallow-repository`,
`ls -l`, `git worktree list`, bounded `git fsck`), only CREATED/CHANGED keep the
unshallow recipe.

Adjacent: one-sided manifest pairing (iterating the BEFORE manifest only)
misclassified an after-only dimension as a fabricated "REMOVED" FATAL. Pair over
the union; a dimension present at one boundary is UNMEASURABLE exactly once.

## 3 — producer isolation is about bytes, not just files

All four shallow-fetch producers were redirected to scratch repos, but the
review pushed past "don't fetch into the live repo":

- **`cp` of a checked-out file ≠ the committed blob.** `core.autocrlf`, smudge
  filters, and post-checkout hooks can all rewrite the bytes a gate consumes.
  Extract with `git -C "$scratch" show HEAD:path` — in shell *and* the vitest
  fixture (`execSync('git show …')` instead of `readFileSync`).
- **`git remote add origin "$url"` persists credential-bearing URLs** into the
  scratch repo's `.git/config`. Fetch directly by URL:
  `git fetch --no-tags --depth 1 -- "$remote_url" "$sha"` — no remote object, no
  persistence. (`cat --` is a GNUism too — BSD `cat` rejects it.)
- `--` separators before URL/path operands; validate a fetched SHA as exactly
  40 lowercase hex before the fetch/archive.

## Session Errors

1. **Arm 56 fixture created the deepen commit inside the boundary window** —
   head/refs fired alongside shallow, polluting the assertion.
   **Prevention:** when a test pins "only this dimension fires", construct every
   prerequisite object *before* the snapshot boundary; the window must contain
   only the mutation under test.
2. **Backticks in double-quoted pass messages executed `absent`/`unreadable`
   as commands** — twice in one file (initial arms, then again in the review
   arms).
   **Prevention:** pass/fail message text is interpolated like any other string —
   quote literals, never use command-substitution syntax in human prose; a grep
   lint for backticks inside `pass|fail "` strings in this suite would catch the
   third occurrence.
3. **FIFO no-block test wrapped the whole `_repo_state` in `timeout`** — git's
   own commit parsing opens `.git/shallow` and blocked independently of the
   sampler.
   **Prevention:** bound the *unit under test* (the dimension function), and
   state explicitly which parts of the system the guard cannot protect
   (documented in the arm's comment).
4. **Negative grep for `unshallow` false-failed** — the removed-transition
   diagnostic prose itself mentions `--unshallow`.
   **Prevention:** assert on the command being *prescribed* (`git fetch`), not
   on vocabulary that legitimately appears in diagnostic prose; read the actual
   output text before writing a negative assertion.
5. **New arms called `repo_boundary_next_action`/`repo_boundary_classify`
   directly** — the test shell never sources the lib → `command not found`.
   **Prevention:** this suite's convention is `bash -c 'source "$LIB"; fn …'`;
   copy the nearest existing arm's invocation shape before writing a new one.
6. **Fixture-relative ratchet flagged 7 new write sites** — `$common/shallow`
   resolves through a function call the scanner cannot prove is under the
   fixture root.
   **Prevention:** when a path is derived (not a literal under `$FIXTURE`), add
   the canonical `assert_fixture_dir` guard at the binding site — it is the
   scanner-visible proof, not a workaround.
7. **`grep -c` under `set -e` in `test-dev-suite-mutex.sh`** (authored in
   #8475) died on zero-match instead of reporting the assertion.
   **Prevention:** `grep -c` exits 1 on no match; under `set -e` always append
   `|| true` (or use the count in an arithmetic context). `lint-shell-capture-
   exit-live` caught it — the mechanism works; the fix raced identically via
   #8513 on main, a reminder that cheap lints converge.
8. **`INDEX.md` merge conflict** — deleted on main per ADR-235 while our hook
   regenerated it on-branch.
   **Prevention:** hook-regenerated files deleted upstream resolve to deletion;
   check whether the file is sanctioned-untracked before resolving toward keep.
9. **Standalone `test-all` refused by the sibling-guard** — needed
   `SOLEUR_ALLOW_FULL_GATE=1` for the lead's sanctioned gate.
   **Prevention:** the gate is the prescribed escape, not an obstacle; set the
   env var on the sanctioned invocation instead of treating the refusal as a
   failure to route around.
10. **Commit shell reaped mid-hook** — the pre-commit hook's `test-all` died
    with its parent shell, leaving staged changes orphaned (twice).
    **Prevention:** any commit whose hooks run a multi-hour battery must be
    launched detached (`setsid`/`nohup`, output to a log) — a foreground exec
    makes hook runtime a function of shell-session lifetime.
11. **Security-sentinel review agent returned empty output** — claiming its
    seat would have overclaimed coverage.
    **Prevention:** count agents that *returned substantive output*, not agents
    spawned; respawn empty returns and reflect the respawn in the coverage
    trailer (`--agents-missing` exists for the case where respawn fails).
12. **Task annotation claimed the gate was "fully clean"** when the observed
    result included one real failure plus environment declines.
    **Prevention:** record the actual counts and the actual AC boundary (zero
    shallow observations, no boundary FATAL) — "clean" is a claim, not a
    measurement.
13. **Linear CDN check reported `fail` on a superseded job set** — resolved on
    the new head with no action.
    **Prevention:** before treating a check failure as real, confirm it is on
    the current head SHA; `gh pr checks` mixes job sets across pushes during a
    re-push window.

## Prevention (recurring class, rank-ordered)

- **Failure-state vocabularies need the adversarial middle state.** Any sampler
  that emits `absent|present` will launder "exists but broken" into whichever
  side is weaker. Enumerate the node-type matrix (file/dir/fifo/socket/
  symlink-dangling/unreadable) and decide each row *before* the review panel
  does it for you.
- **Remedy text is code.** A `next_action` string is executable advice — apply
  the same "can this command actually run in this state" test as for the
  implementation, and dispatch on the transition, not the dimension.
- **Detach anything that outlives a shell.** Batteries, long commits, hooks —
  `setsid`/`nohup` is not optional when runtime is measured in hours.
- **Mutant-proof the stable case.** Nine transition arms all asserted "X fires"
  and a "present always FATALs" mutant survived every one; the
  `present → present` no-verdict arm is what kills it. Every verdict suite
  needs its must-PASS twin.

## Related

- PR #8510 / issue #7924 (this work); ADR-207 amendment.
- #8515 — `.git/objects/info/grafts` residual (same invisible-rewrite class).
- `2026-09-21-env-markers-cannot-gate-provenance-and-floors-need-sentinel-vocab.md`
  — sibling lesson on guard vocabulary vs. measured reality (#8471).
