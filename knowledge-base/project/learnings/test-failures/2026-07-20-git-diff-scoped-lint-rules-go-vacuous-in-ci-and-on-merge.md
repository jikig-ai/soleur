---
date: 2026-07-20
category: test-failures
module: scripts/lint-trap-tempfile-ownership
problem_type: logic_error
severity: high
pr: 6743
issues: [6734, 6736, 6737]
tags: [lint-gates, ci, git-scoping, vacuous-tests, fetch-depth, shellcheck]
---

# Learning: a lint rule scoped to git-diff-added lines goes vacuous twice — in CI, and on its own merge

## Problem

`scripts/lint-trap-tempfile-ownership.py` rule (c) flags a shell file that allocates a
tempfile with no owning trap. To avoid re-litigating an accepted 102-file population
(ADR-129), commit 6404e99d2 scoped it to **lines added vs the merge base**, computed with
`git merge-base HEAD origin/main`.

The suite recorded 203/203 green locally. In CI, 5 of 17 failed, with the fifth naming the
cause outright:

```
error: cannot resolve changed files:
Command '['git','merge-base','HEAD','origin/main']' returned non-zero exit status 128
```

`actions/checkout` defaults to `fetch-depth: 1`. On a shallow checkout `origin/main` does
not exist, `merge-base` exits 128, the changed-file set resolves empty, the linter emits
nothing and returns 0 — so every "should fire" assertion failed. A full local clone
resolves the base, which is exactly why it passed on the developer machine.

## The second failure, which the CI failure was hiding

Fixing the checkout depth alone would have left a worse defect in place.

The test fixtures are **committed files**. Under line scoping they read as "added" only
while this PR is unmerged. The moment it merges, `git diff base...HEAD` for each fixture is
empty, `added_lines()` returns the empty set, rule (c) filters every allocation away, and
the positive arm stops firing — permanently.

Confirmed before acting on it, rather than assumed:

```bash
git diff --unified=0 HEAD...HEAD -- <fixture>   # post-merge shape → empty
```

So the suite would have gone red on `main` the day it landed, for a reason nothing in the
suite explained. A gate whose own tests expire on merge is worse than no gate: it reports
health right up until it reports nothing.

## Root cause

One decision — "scope rule (c) to added lines" — was applied at a layer where it doesn't
belong. Line scoping answers *"is this a new entrant to an accepted population?"*, which is
a question about a **repo sweep**. It is the wrong question when a caller has named a path
explicitly: naming the path **is** the scoping decision.

Both failures are the same mistake wearing different hats. The rule's output was made a
function of branch history rather than file content, so anything that perturbs history —
clone depth, merge — perturbs the findings.

## Solution

1. **Explicit-path mode lints the whole file and consults git not at all.** Line scoping
   stays in the full-scan and `--changed` modes, which are what actually enforce the
   ADR-129 new-entrant accept.
2. **`merge_base()` tries `origin/main`, `main`, `origin/HEAD` and returns `None`** rather
   than raising, so a clone with a differently-named remote works.
3. **`git_changed_files()` degrades to untracked-only with a loud warning** instead of
   `exit 2`. The warning is load-bearing: the degraded scope silently *narrows* rule (c),
   so without it a shallow run looks identical to a clean one.
4. **CI pins `fetch-depth: 0`** on the `test-scripts` job so it exercises the real
   semantics rather than the fallback.

## The verification that made this trustworthy

A passing test proves nothing until it has been shown to fail. The regression test runs the
linter with a `git` on `PATH` that exits 128 for every call — strictly harsher than a
shallow checkout, and it proves the code path consults no history at all:

```bash
printf '#!/bin/sh\nexit 128\n' > "$GITSHIM/git"
PATH="$GITSHIM:$PATH" python3 "$LINT" "$FIX/bad-mktemp-no-trap.sh.fixture"
```

Checked against the pre-fix linter using `git show 7bd82d28a:...` (never `git stash` in a
worktree) — pre-fix `rc=0` and silent, post-fix `rc=1` with the finding.

A companion assertion keeps the **negative** arm negative under the same shim. Without it,
a rule (c) that fired on everything once git disappeared would satisfy the positive
assertion and look like a fix.

## Key Insight

**A gate's findings must be a function of the code, not of the repository's history.** The
moment a rule's output depends on `merge-base`, its correctness is coupled to clone depth,
remote naming, and its own merge status — three things no assertion in the suite mentions,
and all three fail toward silence.

Where history scoping is genuinely wanted (ratcheting an accepted population), confine it
to the mode that sweeps the repo, and make the degraded path **narrate that it narrowed**.
A gate that fails open must say so; otherwise "no findings" and "could not look" are the
same observation.

Corollary for fixtures: a committed fixture is not "new" for long. Any rule that treats
newness as a precondition will stop seeing its own fixtures one merge later.

## Prevention

- When a lint rule calls `git`, ask what it reports on (a) a `fetch-depth: 1` checkout and
  (b) after this PR merges. If either answer is "nothing", the scoping is at the wrong layer.
- Prove a new gate can fail: run its positive arm against the pre-fix implementation via
  `git show <sha>:<path>`, and pair every "fires" assertion with a "still doesn't fire on
  good input" assertion under the same adverse condition.
- `2>&1 >/dev/null` in the test harness is deliberate and order-dependent (fd2 → the
  caller's capture, then fd1 → `/dev/null`, yielding stderr only, which is where findings
  print). shellcheck flags it SC2069 as a likely mistake; it carries an inline
  `# shellcheck disable=SC2069` and a comment. Reversing it to the "correct-looking"
  `>/dev/null 2>&1` captures nothing and makes every message assertion vacuous.

## Session Errors

- **Bash CWD race** — issued a parallel tool call that depended on a `cd` from a sibling
  call in the same block, and guessed `.sh` for a file that is `.py`. Recovery: absolute
  paths + `ls` to confirm the real name. **Prevention:** never pair a `cd`-dependent call
  with a parallel call; verify a filename before reading it.
- **Scratchpad directory did not exist** despite being named in the session prompt; two
  `cd` failures. Recovery: `mkdir -p`. **Prevention:** `mkdir -p` before first use.
- **Shallow-clone reproduction used a non-existent bare-repo path** and failed twice.
  Recovery: abandoned the repro — the CI log was already conclusive proof.
  **Prevention:** when a CI log already names the failing command and its exit status,
  that IS the reproduction; re-deriving it locally is optional work, not diligence.
- **`sleep 45 && gh pr checks` blocked by the harness.** Recovery: re-done via `Monitor`
  with an until-loop. **Prevention:** already covered by
  `hr-monitor-not-run-in-background-for-polling` — no new rule warranted.
- **Forwarded from `session-state.md`:** `iac-plan-write-guard.sh` blocked the v2 plan twice
  on the prose phrase "out-of-band", and the sanctioned `<!-- iac-routing-ack: ... -->`
  comment did not clear the block. The author rewrote correct prose to satisfy a false
  positive. **Prevention:** already tracked by #5142 / #6494 / #6501 — corroborating
  evidence with the concrete trigger phrase added to #5142 rather than filing a fourth
  duplicate tracker.

## Related

- ADR-129 — jq argv ceiling and shell cleanup ownership (defines the class-b accept this
  rule ratchets)
- #6752 — the three genuine remaining class-c/d tempfile-ownership sites
- #6750 — deferred handler-local cron liveness work
- #6751 — `lint-agents-enforcement-tags.test.sh` pre-existing failure on main
- Commit 7f84318dc — "make three structurally-unfailable gates capable of failing", the
  same defect class in the secret-scan gates
