---
title: "Four instruments answered instead of failing, and the guard I built could be disarmed at full green"
date: 2026-09-20
category: test-failures
module: plugins/soleur/commands/go.md
issues: [8308, 8061, 8283]
pr: 8391
tags: [vacuity, mutation-testing, instruments, plugin-root, guards, review]
---

# Learning: an instrument that answers is worse than one that errors

## Problem

`/soleur:go`'s three session gates read the plugin root through
`ROOT="${GROK_PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}"`. The inner reference is unbraced, so it is
not the loader's substitution token: the line reached bash verbatim and expanded EMPTY in any
session exporting neither variable. All three gates took their degraded branch — `cleanup-merged`
never ran, `.mcp.json` went stale, cloud-mode was decided by the absence of a signal — while two
CI guards **pinned the broken literal** and stayed green over it. Both guards were authored in
the same commit as the defect.

## Solution

One byte-identical resolver per fence: the loader token, then `GROK_PLUGIN_ROOT`, then the two
documented Devin caches (Step 0.5 only, because Step 0 dispatches destructive git verbs). Every
dispatch inside `if [ "$VERIFIED" = true ]` and its own `if [ -f … ]`. A new marker naming the
arm. Measured on both harnesses before deciding.

## Key Insight

**The defects were not in the fix. They were in the things built to prove the fix.**

An 11-seat review found 47 findings; every merge-blocking one was in this PR's own verification.
The unifying shape: *a broken instrument does not error, it answers* — and an answer is already
shaped like a result, so nothing prompts a second look.

### 1. A control on the dispatcher is not a control on the decision

`pass()`/`fail()` had a positive control. That proves DISPATCH. The deciders — `want_in`,
`want_not_in`, `want_eq`, and two composites — each decide a branch and THEN call `pass()`. A
decider that always passes appends a genuine `PASS` row, and counters, append-only ledger and
assertion floor all reconcile exactly.

Measured, each a single edit, each leaving the suite byte-identical at `137 passed, 0 failed`:

    want_in() { ck; pass "$3"; }                    GREEN
    case "$1" in  ->  case "$1$2" in   (one token)  GREEN   (21 rows blind)
    check_r8 / check_r9 bodies -> `ck; pass` loops  GREEN

With three of those plus a ban-evading revert of the resolver, **the defect the suite exists to
catch was live and the suite reported 137/0, rc=0.** The same shape appeared one language over:
gutting the TS scan body left 27/27 green while the control — which drove only the *predicate* —
stayed happy.

**Litmus:** for every verdict-owning helper ask *if this always said yes, what would notice?*
If the answer is "the floor", check who increments the floor's operand.

### 2. Four of my own measurements answered without measuring

- A scripted batch edit **asserted before its single write**, so a mid-script anchor miss
  discarded every edit while the suite reported its previous green. Hit twice.
- A lint run **without its CI flags** (`--allowlist`) produced 6 phantom FAILs I nearly filed.
- A vitest verdict grep was **defeated by ANSI codes** and returned empty for every arm —
  including the control, which is the tell.
- A mutation whose anchor missed printed `rc=0, 27 passed` **from the restored file**.

Each produced a confident reading rather than an error.

### 3. A convergent panel can still be wrong, and a narrow grep can make me wrong about them

Two seats told me to change `grok plugin list` → `grok inspect`. My `grok --help | grep` had been
too narrow to show `inspect`, so I briefly concluded they were wrong. They were right.

The inverse also happened: two seats proposed admitting `not-local:sentinel-absent` to the
session-class proceed set. The symptom was real (a local box with a stray `DEVIN_DIR` skips its
preamble forever). The fix **inverts the safety property** — `cloud-detect.sh`'s header says
consumers MUST fail closed on every `not-local` reason and names exactly one carve-out, and that
reason means "Devin-MARKED box, no sentinel". Admitting it would let a real cloud session reach
`cleanup-merged`. Reading the classifier's own contract took ten seconds.

### 4. Arming a guard and running it are the same event

The gate had been inert for a week. Making it work means the first correct run processes the
whole accumulated backlog at once — and the arming hold is keyed on a per-repo stamp that is
already spent on any machine where `cleanup-merged` ever ran by hand. Worse, the transition is
**untestable on the author's machine**: in this repo the `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}`
fallback in four sibling skills *resolves*, so the reaper ran all week; in a customer repo all
five dispatch paths were dead and their backlog is their entire history.

### 5. The `>` in `cmd > file` truncates before `cmd` runs

`git show main:.mcp.json > .mcp.json 2>/dev/null || true` left a **0-byte** `.mcp.json` on every
failure path — including the normal case for a customer repo, where `main` carries no `.mcp.json`.
This repo tracks one, which is exactly why every fixture had one and nobody saw it. Measured:
67 bytes → 0, silently, rc 0, on an untracked file commonly holding MCP server tokens.

## Prevention

- **Every verdict-owning helper needs a two-sided control**, driven through the real helper with
  the probe retracted from counters AND ledger, reporting via `printf` + `exit` — never through
  the helper under test. A pass/fail control does not cover a decider.
- **Audit a battery's AXES, not its row count.** The first battery here scored 27/27 and never
  edited the decider branch, fixture direction on the harness, or set cardinality.
- **Verify the instrument before reading its verdict**: run the control first, assert each
  mutation LANDED, strip ANSI, read exit codes rather than parsed summaries, and copy a lint's
  invocation from `test-all.sh` before quoting its output.
- **Make a batch edit report per item**, so a partial application cannot look like a clean run.
- **Commit each verified unit immediately** — a `cleanup-merged` anywhere reverts the tree.
- **Write-then-rename** for any redirect whose target must survive the command failing.
- **Read the contract before widening a safety predicate**, even when seats converge.

## Session Errors

1. **All three go gates no-op'd in this session** — Recovery: ran `cleanup-merged` via the AGENTS.md path. Prevention: this PR.
2. **Uncommitted work reverted mid-session by my own AC12 run** — Recovery: full re-application. Prevention: H3 and AC12 now run from a scratch workspace; commit verified units immediately.
3. **Batch edit asserted before its single write (×2)** — Recovery: re-applied against real anchors. Prevention: per-edit reporting instead of all-or-nothing.
4. **Lint run without its CI flags produced 6 phantom FAILs** — Recovery: re-ran the CI form. Prevention: copy the invocation from `test-all.sh`.
5. **`grok --help` grep too narrow; nearly rejected a correct finding** — Recovery: read the full subcommand list. Prevention: a negative from a filtered probe is not a negative.
6. **vitest grep defeated by ANSI; empty for every arm incl. the control** — Recovery: read exit codes. Prevention: a uniform result across arms including the control means the instrument, not the subject.
7. **Mutation anchor missed; `rc=0` read off the restored file** — Recovery: asserted the mutation landed. Prevention: never score a row whose mutation is unproven.
8. **Plan's AC12 command wrong two ways** — Recovery: measured both failure modes. Prevention: the recipe now ships inside the capture artifact.
9. **Local three-shard gate REFUSED (`rc=4`) on every attempt over ~5h** — Recovery: derived the substitute set from consumers + new marker vocabulary. Prevention: none available; CI's required `test` context is the merge gate.
10. **`git stash list` hook-denied; `cd /tmp` reset the worktree CWD twice** — one-off.

## Related

- ADR-179 decision 11 + amendment A15
- #8400 / #8401 / #8402 (filed), #7453 (deliberately not folded in)
- `knowledge-base/project/specs/feat-one-shot-8308-go-gates-plugin-root/mutation-log.md`
