---
date: 2026-07-29
category: workflow-patterns
module: verification
tags: [verification, mutation-testing, false-green, git-index, contention, anti-vacuity]
issue: 7012
pr: 7034
adr: ADR-150
---

# Four checks reported the right answer for the wrong reason, and each one looked normal

## Problem

Collapsing the AGENTS change-class sidecars (#7012 / ADR-150) is a governance
change: it decides which rules are in an agent's context. So every claim in it
was measured rather than asserted — and *four separate times* a measurement
returned the expected value **for a reason that had nothing to do with what I
was testing**. None of them looked like a failure. Every one presented as an
ordinary, expected outcome:

| # | What I ran | What I concluded | What actually happened |
|---|---|---|---|
| 1 | enforcement-tags lint against `main`'s files copied into a bare temp dir | "the failure is pre-existing" | the temp dir had no `plugins/` tree, so **all 40** anchors failed for a missing-environment reason. The real number is 12. |
| 2 | the new manifest-side deletion check, against the attack it was written for | "rc=1, the guard blocks it" | `new_acks()` was called ~40 lines before its closure is defined. Clean tree passed (the loop `continue`s first); the attack raised **NameError**. rc=1 was a crash. |
| 3 | the `--snapshot-all` vacuity guard on an empty corpus | "rc=2, the guard fires" | `--root D --snapshot-all FILE` put a positional where argparse rejected it. rc=2 was **argparse**. |
| 4 | `test-all.sh`, then read its verdict | "231/232, ship it" | the run had started **before my last commit**. It was validating a tree that no longer existed. |

The common shape is not "the check was wrong". Each check was fine. **The
check's *reason* was unexamined**, and a correct-looking exit code is the single
most convincing way to stop looking.

## Root cause

An exit code is a one-bit summary of a rich event, and every one of these
failure modes collapses into the same bit:

- a crash and a verdict both exit non-zero
- an argument-parsing error and a fired guard both exit 2
- a suite that measured the wrong tree and a suite that measured the right one
  both print a pass count
- an environment too broken to run the thing and a genuinely failing thing both
  produce "N errors"

So "the number came out how I expected" is compatible with the instrument never
having touched the property. This is the same family as the repo's existing
`cq-assert-anchor-not-bare-token` (anchor on what is actually asserted) and
"a mutation that does not mutate reports a false result" — but those are about
the *assertion*; this is about the *reason the assertion fired*.

## Solution

Per check, demand a signal that only the intended cause can produce:

- **Assert the message, not the code.** The deletion check is now verified with
  an explicit `grep -qiE 'Traceback|NameError'` **negative** alongside the
  rc — a guard that cannot report is indistinguishable from one that passed.
- **Positive + negative control.** Every mutation run asserts the mutation
  *landed* (`diff -q` against a pristine backup, and `assert s.count(old) == 1`
  before replacing), and that neutering **only** that check restores the green.
  If the baseline is already red, the whole battery is void.
- **Measure in a real environment.** A "pre-existing failure" claim was re-run in
  a genuine `git worktree add --detach origin/main` — with the plugins tree, the
  scripts, everything — which produced 12 errors and a byte-identical failing
  set. The bare-temp-dir version had been measuring the absence of a directory.
- **Pin the tree under test.** Record the SHA the suite started against and
  compare it to `HEAD` before accepting a verdict; restart on any drift.

## Key insight

**A check that fires for the wrong reason is indistinguishable from one that
works, and it fails in the direction that stops you looking.**

The tell is always available and always cheap: ask *what specific evidence would
exist if this fired for the reason I believe?* — a named error string, a diff
that proves the mutation landed, a control that must go the other way — and then
require that evidence rather than the exit code. Four times in one session the
exit code was right and the reason was wrong; each was caught by looking at the
output text rather than the status.

Corollary, learned the expensive way: **`git checkout <ref> -- .` rewrites the
INDEX, not just the working tree.** Running it to "compare against main", then
`git checkout-index -a -f`, restored the working tree from an index that now
held `origin/main` content and destroyed every uncommitted edit in the session.
Comparing against another ref is a **separate worktree** operation
(`git worktree add --detach <tmp> origin/main`), never a shared-index one. The
same session then proved the point twice more: a background baseline started
while the tree was being mutated, and a suite accepted after a later commit.
Verified work belongs in a commit before anything else runs.

## Session Errors

- **`git checkout origin/main -- .` + `git checkout-index -a -f` reverted all uncommitted Phase 3–7 work** — Recovery: `git reset --hard HEAD`, rebase onto the newer main, re-apply everything (the merged corpus survived only because it was staged). **Prevention:** compare against a ref in a throwaway `git worktree`, never through the shared index; commit verified work immediately.
- **"Pre-existing" verdict measured in a bare temp dir** — Recovery: re-ran in a real `origin/main` worktree; 40 phantom errors became the true 12 with a byte-identical failing set. **Prevention:** when a tool resolves paths relative to a repo (SKILL.md anchors, configs, plugins), a stripped fixture measures the strip, not the tool.
- **Deletion-check fix passed by raising NameError** — Recovery: relocated the loop below the `new_acks` closure; re-verified with a no-traceback assertion. **Prevention:** assert the specific error message; a guard whose only evidence is a non-zero exit is unverified.
- **Vacuity guard "fired" via argparse** — Recovery: corrected flag order, re-tested, guard message confirmed. **Prevention:** same rule — pin the message.
- **Comments claimed "mutation-verified" / "BOTH paths block" before measuring** — Recovery: measured; one claim was overstated and one was false under this PR's own (vacuous) base; both corrected in-branch. **Prevention:** never write a verification adjective you have not just run; the repo already treats such comments as protection that discourages the next reader from checking.
- **Baseline `test-all` started in background, then the tree was mutated under it** — Recovery: discarded as contaminated. **Prevention:** a baseline is only a baseline if the tree is frozen for its duration.
- **Accepted a suite started before the last commit** — Recovery: killed, restarted on the final SHA. **Prevention:** record and compare the SHA.
- **Foreground infra run timed out at 2 min but its child survived; relaunching created two `xargs -P 6` runners on one worktree** — Recovery: identified the orphan by `lstart`/elapsed and killed it by explicit PID (never `pkill -f`, which matches the invoking shell). **Prevention:** after any foreground timeout, check for and reap the surviving child before relaunching.
- **Background waiters blocked forever on rc files that could not be written** (machine slept ~10.7 h mid-run; both gates died mid-stream) — Recovery: treated the truncated logs as **un-run, not passing**, and re-ran from scratch. **Prevention:** a log that ends without a summary line is not a verdict; `setsid` the runner so a session pause cannot orphan-kill it.
- **`comm` given unsorted input** — one-off; conclusion unaffected because the substantive check was a direct per-path membership test. **Prevention:** sort both sides or use `grep -qxF` per item.
- **Push rejected non-fast-forward after two rebases** — Recovery: `--force-with-lease` on an own-feature branch. **Prevention:** none warranted — this is the expected and correct signal after a rebase, and `--force-with-lease` (never bare `--force`) is already the right response. Recorded so the inventory is complete, not because it needs a fix. One-off.

## Related

- `2026-07-27-my-refutation-measured-a-shim-and-my-safe-fixture-hid-12240-deletions.md` — the instrument removing the phenomenon it measures; same family, different mechanism.
- `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md` — the direct predecessor; this session supplies four fresh instances and the git-index variant.
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` — why a self-run battery's green is evidence about the mutations, not the tests.
- ADR-150 — the change this was learned on.
