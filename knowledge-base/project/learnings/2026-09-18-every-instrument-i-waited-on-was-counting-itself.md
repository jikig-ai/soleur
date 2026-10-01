# Learning: every instrument I waited on was counting itself

## Problem

A nine-seat review of PR #8270 produced 24 findings, 8 of them P1. Two were live
bypasses of the PR's own headline fix. But the costliest hours of the session went
to instruments that reported "still waiting" when they could never have fired, and
to guards I wrote that could never have failed.

The session's own defect rate matched the PR's: of the four red rows the full
battery finally produced, **three were introduced by this review's own fixes** and
the fourth was caused by the reviewer committing during the run.

## Solution

### The two live bypasses (the findings that justified the review)

PR #8270's subject was "a user's ambient git config cannot silently disarm a
scanner". It pinned `color.ui`/`color.diff` off through `GIT_CONFIG_COUNT`. Both
bypasses survived that pin:

1. **`GIT_CONFIG_PARAMETERS` is a separate config source read AFTER the
   `GIT_CONFIG_COUNT` list**, so it wins outright — and `git -c <anything>`
   **exports it into every hook git spawns**. Measured: with only the count-list
   pin, `git -c color.diff=always commit` on a staged AWS key scanned
   `rc=0 / 0 findings` and the key landed. Appending the pin to
   `GIT_CONFIG_PARAMETERS` too restores `rc=1 / 1 finding`; the unfixed hook
   reproduces `allow`, the fixed one `deny`.

2. **A `-diff` gitattribute removes the `+` lines entirely**, so gitleaks parses
   nothing regardless of colour. `.git/info/attributes` containing `creds.txt -diff`
   took a staged key from `rc=1/1` to `rc=0/0`.

**The prescribed remedy for (2) did not work, and testing it rather than applying
it is the transferable part.** `core.attributesFile=/dev/null` and
`GIT_ATTR_NOSYSTEM=1` both still scanned `rc=0 / 0 findings`: they govern the
GLOBAL and SYSTEM attributes files, while `.git/info/attributes` is per-repo and
always read. Applying that fix would have looked applied and changed nothing.
The working fix re-scans only the affected paths from their staged blobs with
`gitleaks detect --no-git`, which never consults git's diff machinery;
`git check-attr diff` discriminates precisely (explicit `-diff` → `unset`,
auto-detected binary → `unspecified`), so binary files are untouched.

### The instruments that were counting themselves

Two battery watchers polled with `ps -eo args | grep -c '[t]est-all\.sh'`. The
Bash tool runs a command as `bash -c '<the whole command>'`, so **the watcher's own
argv contained the pattern**. The count never reached zero, the quiet counter never
advanced, and both watchers reported "still waiting" indefinitely. Two operator
"check now" turns returned the same answer for this reason.

The fix is an argv-anchored count that cannot self-match:

```bash
n=$(ps -eo args | awk '$1=="bash" && $2=="scripts/test-all.sh"' | wc -l)
```

A real runner has `argv[1]=scripts/test-all.sh`; the watcher is `bash -c …`, so its
`argv[1]` is `-c`. Verified against an independent count before trusting it.

**The repo already had this rule and it did not reach me.**
`.claude/hooks/pkill-self-match-guard.sh` blocks exactly this class — but only for
`pkill -f` / `pgrep -f`. `ps … | grep <pat>` is the same defect in a different
spelling and is unguarded (filed as #8330). That is the documented "review the matcher against the
GRAMMAR, not the one spelling it was written for" shape, one level up: the guard
itself was written against one spelling.

### The guards I wrote that could not fail

- **Two harness "GUARD FAIL" checks were decoys.** Both injected `GIT_CONFIG_*`
  into a *direct* `git -C … diff` — a sibling command — not into the hook/gate under
  test. Deleting the injection from `run_decision_cfg` / `run_gate` left both suites
  fully green (127/127 and 71/0). **My first replacement reproduced the same decoy
  one level over**: it built its own inline `env … bash "$HOOK"` instead of routing
  through `run_decision_cfg`, so the mutation still survived. The working version
  points the function at a stub that reports the env it was handed.

- **My own regression arm was vacuous.** The OpenHands conflict-marker arm asserted
  `2:deny`, and passed with the guard fully disarmed — because the fixture defaulted
  to branch `main`, so the deny came from the **commit-on-main** gate, not the
  conflict guard. Caught only by mutation-testing my own fix. Fixed by running on a
  non-main branch and asserting *which* guard fired (`2:deny:conflict`).

### The battery's four red rows

| Row | Cause |
|---|---|
| `lint-trap-tempfile-ownership` | the new shared lib allocated a tempfile with no owning trap; a **sourced** library cannot register an EXIT trap without stealing the caller's, so the fix is no tempfile |
| `fixture-cd-containment` | my conflict fixture opened a bare `cd "$CM_REPO"` then ran `git config`/`add`/`commit` — the 2026-08-20 incident shape, in a fixture written for a guard against silent disarms |
| `fixture-relative-assert` | count drift 77→78 from the new harness guard; baseline regenerated only after confirming the site is guarded and no violation is reported |
| `[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY` | **false positive caused by the reviewer.** The runner samples the repo boundary exactly twice and flags HEAD/ref movement; HEAD moved five times inside the window because this session committed while the battery ran. The runner states outright it cannot attribute the change to a suite |

The first three are all invisible to any file-selected run: **a repo-global ratchet
references no changed file**, so no path-based selection can return it. Every
targeted run that verified those edits was structurally blind to them.

## Key Insight

**An instrument that has never been shown to produce a positive has not returned a
negative — it has returned silence.** Every wasted hour here came from reading
silence as a result: a watcher that counted itself, a guard whose fixture could not
reach the branch under test, a lint invoked without its baseline, a mutation script
that aborted before writing and left three suites reporting "survived".

The corollary that actually changes behaviour: **run the instrument against a case
whose answer you already know, before reading its verdict.** An argv-anchored count
checked against an independent one. A mutation asserted landed against a pristine
copy. A guard driven in both directions. A lint run with the flags CI uses.

And the second-order one: **on a fix PR, the new assertions are the least-audited
surface.** They are written while holding the defect in mind, so they pin the shape
of that bug rather than the property — which is why three of four battery reds were
authored by the review that existed to prevent them.

## Session Errors

1. **Branch conflicted with main at review start** (15 commits behind) — Recovery:
   rebased before spawning the panel. **Prevention:** the review skill already
   prescribes `git merge-tree --write-tree` before the panel; it is worth doing
   *first*, because a conflict found by a seat costs a rebase plus a second CI round.

2. **Rebase #1 dropped a counter.** Resolved `rule-metrics.json` by verifying
   `.rules[].id` were identical — true, and narrower than the reassurance it gave.
   `summary.non_corpus_counts["gdpr-gate-staleness"]` (value 4) was lost.
   **Prevention:** when verifying a generated file, diff **every** key path the file
   carries, not the one array you thought of; or do not hand-patch it at all (see 3).

3. **Rebase #2 kept stale counters** — 15 keys *lower* than main's, because the
   sibling that landed #8272 had regenerated more recently. **Prevention:** the
   aggregator's own #6794 note says it reads ONE per-checkout incidents ledger, so
   these are checkout-local and non-monotonic (`gdpr-gate-staleness` reads 2 →
   absent → 4 → 2 across four main commits). Take main's copy wholesale; the next
   compound run regenerates it. Hand-patching a generated file fights the generator.

4. **Wrote `#8275` into a committed comment before `gh issue create` returned it.**
   #8275 is an unrelated WIP PR. **Prevention:** never write a `#N` into an artifact
   before the create call returns the number — an existing rule, violated anyway.

5. **Ran `lint-shell-capture-exit.py` without `--baseline`**, producing a false
   "203 NEW findings" that briefly read as a real regression. **Prevention:** invoke
   a lint the way `test-all.sh` invokes it; read the registration line first.

6. **First replacement harness guard reproduced the decoy one level over** — it built
   its own inline invocation instead of routing through the function under test.
   **Prevention:** a plumbing control must drive the *exact* call path the rows use;
   verify by deleting the injection and confirming the guard fires.

7. **First OpenHands regression arm was vacuous** — fixture on `main`, so the deny
   came from the commit-on-main gate. **Prevention:** assert *which* guard fired, not
   that one did; an exit code is a symptom several guards share.

8. **`local mode="$1" label="…$mode…"` read `$mode` as unset under `set -u`** —
   `local` may declare every name before assigning any. **Prevention:** split the
   declarations.

9. **A test fixture leaked a `seed` commit and `seed.txt` into the real branch**
   (shell CWD reset between calls). **Recovery:** dropped via `git rebase --onto`,
   verified the only tree difference was that file. **Prevention:** fixtures use
   `git -C "$dir"`, never `cd`; the `fixture-cd-containment` ratchet enforces it and
   caught the sibling instance in the same session.

10. **Stray `conflicted.md` fixture debris staged** — caught by reading
    `git status` before committing. **Prevention:** same as 9.

11. **Two battery watchers counted `test-all.sh` with a substring grep matching their
    own `bash -c` argv**, so they could never fire, and reported "still waiting"
    across two operator checks. **Prevention:** anchor process counts on an argv
    slot (`$1=="bash" && $2=="scripts/test-all.sh"`), and verify against an
    independent count. `pkill-self-match-guard.sh` blocks this for `pkill -f`/`pgrep
    -f` but not for `ps … | grep` — filed as a follow-up.

12. **`&`-backgrounded a whole `&&` chain twice**, so the variable assigned earlier in
    the chain was empty in the verification echo. **Prevention:** assign in the
    parent shell, or echo a literal path.

13. **Committed during the battery**, moving HEAD five times inside its window and
    producing a `[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY` false positive that
    cost ~10 minutes to disambiguate against the reflog. **Prevention:** do not write
    to the repo while a gate run is in flight — the runner samples the boundary
    exactly twice and cannot attribute movement to a suite.

## Tags

category: workflow-issues
module: test-all, secret-scanning, review
