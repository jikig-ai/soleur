---
module: verification-scaffold
date: 2026-10-21
problem_type: logic_error
component: tooling
symptoms:
  - "verification-scaffold.sh left a /tmp/verification-scaffold-XXXXXX bookkeeping dir behind on every invocation path"
  - "the success path disarmed the EXIT trap (`trap - EXIT INT TERM`) and exited with no rm of $WORK"
  - "a naive `rm -rf $WORK` placed before `emit_doc` removes the doc table's source — emit_doc sed-reads $WORK/doc-rows"
  - "after fix 419c48c3b1, pre-trap exits (--dry-run, --uninstall, pre-arm die paths) still leak $WORK — verified empirically"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [mktemp, cleanup, exit-trap, verification-scaffold, shell]
synced_to: [plan]
---

# Learning: A mktemp dir whose cleanup is armed late leaks every exit before the trap — and rm placed before the last reader breaks the artifact it feeds

## Problem

`plugins/soleur/skills/verification-scaffold/scripts/verification-scaffold.sh`
creates its bookkeeping dir unconditionally at ~L167
(`WORK="$(mktemp -d -t verification-scaffold-XXXXXX)"`) — it holds `emitted`,
`dirs-created`, `settings.json.bak`/`.absent`, the `settings.jq` scratch file,
and `doc-rows`. But `trap '_vs_cleanup' EXIT` was only armed at ~L707, just
before the first write, and `_vs_cleanup` itself never removed `$WORK`. Two
leak classes shipped:

1. **The armed-failure path** — `_vs_cleanup` removed the emitted files, the
   bite worktree and `BITE_DIR`, but not `$WORK` itself.
2. **The success path** — `CLEANUP_ARMED=0; trap - EXIT INT TERM` disarmed the
   traps and `exit 0` ran with no `rm` at all.

The fix (419c48c3b1) needed **two** `rm -rf -- "$WORK"` calls, and their
*positions* were load-bearing: one inside `_vs_cleanup` (covers every armed
exit), and one on the success path placed **after** `emit_doc` — because
`emit_doc` writes `$WORK/doc-rows` and then sed-reads it
(`-e "/@GUARD_TABLE@/r $WORK/doc-rows"`). An `rm` placed anywhere earlier on
that path removes the doc table's source and emits a VERIFICATION.md missing
its guard rows.

And the fix's own commit message ("remove $WORK bookkeeping dir on all exit
paths") overshot: every exit *before* the trap arms still leaks — `--dry-run`
(~L702), both `--uninstall` exits (~L645/L648), and every `die` in the pre-arm
window (TMPDIR containment 69, merge-tool precheck 69, malformed settings.json
69, refuse-if-exists 66). Verified during compound: `--dry-run` against a
fixture repo left `verification-scaffold-XXXXXX` behind under TMPDIR. The
one-line completion is `trap 'rm -rf -- "$WORK"' EXIT` immediately after the
mktemp — the later `trap '_vs_cleanup' EXIT` replaces it (and `_vs_cleanup`
already carries the rm). Filed as a new finding on #10759 rather than edited
inline, because a sibling session held uncommitted edits in the same file.

## Solution

- `rm -rf -- "$WORK"` inside `_vs_cleanup` (armed path) and after `emit_doc`
  (success path) — landed in 419c48c3b1.
- Residual: arm a minimal `trap 'rm -rf -- "$WORK"' EXIT` at creation so the
  pre-arm window is covered too — tracked on #10759.

## Key Insight

**"Cleans up on failure" is a property of the window between resource creation
and success, not of the cleanup function it names** (the same shape as #8352's
cleanup-on-failure learning, one level down). Two corollaries:

- **Arm the resource's own minimal cleanup at creation**, then let the richer
  trap replace it. Trap arm-site is a second ordering constraint: every exit
  between `mktemp` and `trap` is a leak no later code can see.
- **A removal placed before the last read is a deletion of the artifact's
  input.** Bookkeeping dirs are both leak-risk AND data-source; the `rm` goes
  after the last consumer (`emit_doc`'s sed `-r` read), never at "we're done
  writing" time.

## Session Errors

1. **`decision-challenges.md` shipped non-canonical** (forwarded from plan
   phase): a 5-col `| # | Decision | Class | Status | Ruling |` table plus
   rows 10/11 appended as stray rows below a different section — the ruling
   gate's `@BADHEADER`/`@STRAY` classes. Recovery: `b33c34d2c4` restored the
   canonical `| Item | Class | Ruling |` table with rulings in-table.
   **Prevention:** `technical-ruling-gate.sh --branch` before returning the
   plan; rows go INSIDE the canonical table, never appended below it.
2. **`$WORK` leaked on every exit path** (this learning's subject). Recovery:
   `419c48c3b1`. **Prevention:** arm `trap 'rm -rf -- "$WORK"' EXIT` at the
   mktemp line; verify cleanup by *running each exit path* against a sentinel
   TMPDIR, not by reading the trap.
3. **Incomplete "regenerate derived artifacts" sweep** — three committed-state
   reds (stale `model.likec4.json`, missing `fixture-relative-assert.baseline.txt`
   row, README count 103→104) were ONE gap. Recovery: `0400ffe62a`.
   **Prevention:** enumerate every generator/`--check` pair the touched paths
   can invalidate before declaring the sweep done; the plan's regen list is a
   hypothesis, not the set.
4. **Sibling session wrote this branch mid-flight** — `96b243a740` (Devin) plus
   live unstaged edits during review. Recovery: staged only review-owned paths.
   **Prevention:** before committing in a shared worktree, check `git log
   origin/<branch>..HEAD` and `git status` for foreign writes; never `git add -A`.
5. **Compound-time discovery: `419c48c3b1`'s coverage claim was false** —
   pre-trap exits still leak. Recovery: filed to #10759 (file dirty with
   sibling edits). **Prevention (null-guardrail, step-3.6 `unwired`):**
   `generator.test.sh` covers the exit matrix but asserts no TMPDIR-emptiness —
   wire a `find "$ISO_TMPDIR" -name 'verification-scaffold-*' | wc -l` == 0
   arm onto the dry-run/uninstall paths when the fix lands.

## Tags

category: logic-errors
module: plugins/soleur/skills/verification-scaffold
