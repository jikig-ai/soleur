---
title: Every guard pinned the artifact and none pinned the wire
date: 2026-09-20
category: workflow-patterns
tags: [review, guards, vacuity, wiring, mutation-testing, generated-artifacts, adr-235]
module: plugins/soleur/scripts, scripts/ensure-kb-index.sh, .claude/hooks
issue: "#8377"
pr: "#8384"
severity: P1
---

# Learning: every guard pinned the artifact and none pinned the wire

## Problem

PR #8384 untracked four generated knowledge-base caches and added a regenerate-on-conflict
resolver for the one still-committed product. The untracking half was sound and the
regeneration was provably byte-faithful (0 divergent rows over the real 9,521-file corpus).
Review still found **eight P1s, all PR-introduced**, and every one lived in the new
mechanism or its verification — not in the change the PR existed to make.

Five of the eight were **one gap, not five bugs**: each guard pinned an artifact's PATH or
CONTENT and never the WIRING that made it load-bearing.

| Guard | Pinned | Did not pin | How it read green |
|---|---|---|---|
| `devin-matcher-parity.test.sh` | a path inside the command resolves | the command RUNS | `canon()` regex stops at `.sh`, discarded ` --soft"`; hook exited **127** at 9/9 green |
| ship-phase-7 parity token list | some token spellings | the new regen arm | ship had 5 refs, the mirror 0, suite 191/191 — under a sentence *promising* the list would catch it |
| resolver | that the regen command ran | that `MERGE_HEAD` existed | a non-conflict merge failure fell through to an ordinary commit at rc=0; callers push it |
| `cron-rule-prune.ts` | stdout sentinels | the exit code | exit 2 → `noCandidates` → `ok:true` heartbeat, forever |
| `RESOLVABLE_PATHS` | — | cardinality | the CACHE side had `EXPECTED_N=5`; the PRODUCT side — where the ADR makes the stronger claim — had nothing |

The tell in the last row generalises: **when one side of a symmetric design gets a ratchet
and the other does not, the unratcheted side is the one nobody re-read.**

Three more, each a claim that outran its check:

- **An inherited env var reached `eval` in a script that commits unattended.** "TEST SEAM ONLY
  — nothing in production sets it" is a statement about who DOES set it, not who CAN. All
  three production call sites passed a plain inherited environment; one was a PreToolUse
  hook on `gh pr merge` with both streams discarded. Demonstrated end-to-end: one exported
  variable ran an arbitrary command, side-picked a conflicted file, committed the merge,
  exited 0.
- **The freshness probe could not see a second edit.** `git status --porcelain` carries a
  path and two letters, never content; `ls-files -s` carries the *index* blob. So the FIRST
  edit to a clean file moved the fingerprint and every later edit did not. Reproduced: rewrite
  an untracked learning → probe prints nothing, `kb-tags.txt` keeps the old tag. This is the
  repo's COMMON path (an agent iterating on a learning keeps it `??` all session). The suite's
  staleness row did exactly ONE edit — the case that works.
- **The load-bearing statistic did not reproduce.** "42 of 71" was 71 of 102; the 71 was the
  numerator written into the denominator slot. Four independent measurements agreed. It had
  propagated to NINE sites including an Accepted ADR. The six-place design premise ("no
  likec4 compiler", citing `c4-render.ts`) was false on both clauses — the cited file is the
  WRITER and proves a compiler exists; the real reader fetches the committed blob from GitHub.
  Conclusion survived; reason did not.

## Solution

Fixed inline, each mutation-proven in both directions before commit:

- Resolver: argv-only seam (`--test-resolvable`, argument 1) + argv-array dispatch, no `eval`;
  `MERGE_HEAD` asserted after the merge with stderr captured; `INT/TERM/HUP` trap while a
  10-60s regen holds a live merge; **delete the path before regenerating** so "did not write"
  collapses into the already-checked "does not exist" (closes the binary-attribute ours-side
  side-pick); `tree_fp` positive control; member-set ratchet.
- Probe: fold in content (diff text for tracked modifications, blob hash per untracked file)
  **only when status is non-empty**, so the clean tree stays at 61–83 ms; excludes derived
  from `TARGETS` instead of typed twice.
- Cron: branch on `exitCode !== 0` before parsing sentinels.
- Mirror: port the arm AND add its token to the parity list — fixing only the first leaves the
  false promise standing.
- Devin: move the quote; add a gate row asserting the command SHAPE, not a path inside it.
- Prose: corrected at every site the claim reached, indexed by claim not by file.

## Key Insight

**A unit test observes the helper, never whether anything CALLS it.** Both endpoints of a
data path can be fully pinned while the wire between them is not, and no mutation of the
helper can reach that — reverting the call site leaves the suite green. Ask of every guard:
*"name the one-line edit that reverts this PR's central change, and say which test reds."*
If the answer is "none", the guard pins a proxy.

Companion rule for the reviewer's own instruments, hit three times in one session: **a
regression row you add during review is exactly as unpinned as the bug it closes.** Mutate
it back out before committing. Two of my three new rows were vacuous on first write (an
anchor that matched a sibling occurrence; a fixture that mapped a path that never conflicted)
and only the mutation showed it.

## Session Errors

1. **`git stash list` no-op inside a compound command** — guardrail denied the call. Recovery: re-ran without it. **Prevention:** never include `git stash` in any form in a command; the hook is right to be literal.
2. **`rm -rf "$SB"` before `cd`** (twice) — the static guard resolved the unexpanded variable against the worktree root and blocked. Recovery: `mktemp -d` and a literal path. **Prevention:** compute sandbox paths with `mktemp -d` in the same call that uses them; never `rm -rf` a `$VAR`.
3. **`ps … | awk '/tsc|typecheck/'` self-matched** — blocked by the pkill-self-match guard. Recovery: `grep <pat> | grep -v grep` / argv-slot awk. **Prevention:** already hook-enforced; the remedy text is correct.
4. **Sandbox repo created on `main`, then `git commit`** — blocked by the commit-on-main guard, which evaluates pre-execution so a same-call `checkout -b` does not help. Recovery: tested with an already-tracked file instead. **Prevention:** `git init -b fixture` (or `symbolic-ref HEAD` before first commit) when building a throwaway repo.
5. **Wrong hook extracted** — `[0]["hooks"][0]` took the rules-loader, not the index hook; 37 KB of false output. Recovery: filtered by substring. **Prevention:** select by content, never by position, when a config array has several entries.
6. **Vacuous anchor** — first cron-guard test matched `result.exitCode !== 0`, present 3× in the file; **37/37 green with the guard deleted**. Recovery: anchored on unique throw text + cardinality. **Prevention:** `cq-assert-anchor-not-bare-token` — assert the anchor is unique within its search scope, and mutate the guard out before trusting the row.
7. **Vacuous fixture** — env-seam regression mapped `$SRC` (merges cleanly, never conflicted) instead of `$MODEL`; the payload could never fire; found only by mutating the seam back. Recovery: mapped the conflicted path. **Prevention:** a fixture must be able to CONTAIN the thing it looks for — run the reintroduced bug against the row before committing.
8. **Coincident count** — `--enumerate-commands` gave 470 before (all lines) and after (`SUITE_COMMAND` lines only); nearly read as "no change". Recovery: grepped for the specific label. **Prevention:** compare like with like, and assert presence of the specific member, not a total.
9. **Multi-line `bash -c` in `run_suite`** — `--enumerate-commands` cannot encode a NEWLINE in argv. Recovery: moved the body to `scripts/generate-kb-index-live.test.sh`. **Prevention:** registered `run_suite` commands are single-line argv; anything with control flow is a file.
10. **Commit chained before lock release** — `git add && git commit` fired while the prior commit held `index.lock`; `add` failed, the chain short-circuited, `tail` reported 0. Recovery: waited, re-staged. **Prevention:** never start a commit while a background commit is pending in the same worktree; read `rc` from the command, not from `tail`.
11. **Five `.ts` commits died silently** — the `bun-test` pre-commit hook runs the FULL `scripts/test-all.sh`; under 7-10 sibling gates (load 29) the memcg `soleurtest-agents.slice` OOM-killed them (journalctl). "The shard gate is owed" and "the commit keeps dying" were the same blocker. Recovery: ran applicable hooks sequentially by hand (gitleaks, tsc, callsites — all rc=0), committed `LEFTHOOK=0` with that record in the message; full gate explicitly still owed. **Prevention:** when a commit hook is the full gate and the box is saturated, enumerate the applicable hooks from `lefthook.yml`, run them one at a time, and document the bypass — do not retry blind.
12. **Byte-ratchet breach** — `ship/SKILL.md` went 320 over its 274,000 ceiling from a wordy correction; trimmed twice. **Prevention:** a correction to a ratcheted file should be shorter than or equal to what it replaces; run `lint-skill-body-budget.py --base` before committing SKILL.md edits.
13. **Right verdict, wrong reason** — read `main`'s widened `(a|b|c|i|o|w)` prefix class as a live bypass fix; mutating it back left 127/127 because the hook forces `--dst-prefix=b/`. Two agents independently reached the correct reason. **Prevention:** mutation-test your own merge resolutions; a green suite after reverting one side means that side was not the guard.
14. **argv-order bug in my own seam** — `BASE="${1:-}"` was read before the `--test-resolvable` shift. Recovery: caught on re-read, moved the assignment. **Prevention:** re-read the whole file after inserting an argv-consuming block, not just the block.
15. **Fixture tripped the wrong precondition** — overwriting the regen stub uncommitted made the clean-tree check refuse first; the row passed for an unrelated reason. Recovery: committed the stub. **Prevention:** a fixture edit to the SUT's inputs must be committed before the SUT's own preconditions run.

## Prevention

- Structural roll-up is mandatory in synthesis, and when it names a class, fix the class:
  audit every guard the PR ships for "path/content vs wiring" before closing any instance.
- On a guard-shaped PR, run the cheap deterministic lints and a mutation of each new guard
  BEFORE the panel; their yields are disjoint from the panel's.
- Re-derive every number and every "X cannot / X ships no Y" sentence the diff ADDS. Both of
  this PR's headline claims were false and both had been copied verbatim to 6–9 sites.

## Related

- `2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md`
- `2026-09-18-every-defect-was-in-my-verification-not-the-feature.md`
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
- ADR-235, ADR-091, ADR-210
