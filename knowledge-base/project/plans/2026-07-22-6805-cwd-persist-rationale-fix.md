---
title: "Correct the false 'CWD does not persist' rationale in two skill files (#6805)"
issue: 6805
branch: feat-one-shot-6805-cwd-persist-rationale-fix
change_class: docs-only
status: ready
---

# Overview

Two `SKILL.md` sites justify a (still-correct) instruction with a now-false
mechanism: *"the Bash tool does NOT persist CWD across calls."* The current
Bash-tool contract says the opposite — CWD **does** persist between calls. The
false reason is load-bearing: this session it caused a `test-all.sh` run to be
killed on the belief it must have executed from the bare root when it had not.

This is the repo's documented "false comment" class (a comment asserting a
mechanism nothing verifies, load-bearing for a reader's decision). It is a
**drift** defect, not an authoring error: the claim was likely true when written
(PR #2683 / learning dated 2026-04-19) and the harness changed since — which is
why it survived, the surrounding advice still working.

The fix keeps the instruction at both sites and replaces only the reason with the
real, still-live hazard: **CWD drift**. Any intervening Bash call that `cd`s
elsewhere (`cd "$(mktemp -d)" && git clone …`) silently redirects everything
after it to the wrong tree; and because the bare repo root holds stale synced
copies of tracked files, the failure surfaces as wrong pass/fail counts that look
like real regressions rather than a missing-file error.

# Affected sites (swept, not assumed)

`git grep -n "NOT persist" -- plugins/ .claude/` and `git grep -n "persist CWD" -- plugins/ .claude/`
return exactly two in-scope sites (a third `NOT persist` hit in
`data-protection-disclosure.md` is unrelated legal prose about data retention —
out of scope):

1. `plugins/soleur/skills/work/SKILL.md` (~line 620) — primary, PR #2683 rationale.
2. `plugins/soleur/skills/one-shot/SKILL.md:83` — Step 0c draft-PR creation; the
   claim was copied here, so correcting only site 1 would leave the twin asserting
   the false mechanism.

# Acceptance Criteria

- [x] `work/SKILL.md` no longer asserts that CWD does not persist across Bash calls.
- [x] The chaining / absolute-path instruction is retained at **both** sites.
- [x] The retained rationale describes CWD **drift** (an intervening `cd`), which
      is the real and still-live hazard, and preserves the bare-root stale-copy
      consequence.
- [x] `one-shot/SKILL.md:83` corrected the same way (instruction kept, reason fixed).
- [x] After the change, `git grep -n "persist CWD" -- plugins/ .claude/` returns
      **zero** stale assertions.

# Implementation Steps

1. Edit `plugins/soleur/skills/work/SKILL.md` — replace the "does NOT persist CWD"
   sentence with a CWD-drift rationale; keep the `cd <abs> && <cmd>` / absolute-path
   instruction and the PR #2683 "Why" line (reframed as a *drifted* CWD).
2. Edit `plugins/soleur/skills/one-shot/SKILL.md:83` — replace the "does NOT persist
   CWD across calls" clause in the Step 0c parenthetical; keep the "single
   `cd && bash`" instruction.
3. Verify: `git grep -n "persist CWD" -- plugins/ .claude/` → zero rows; and
   `git grep -n "NOT persist CWD" -- plugins/ .claude/` → zero rows.

# Test Scenarios

Docs-only change; no runtime behavior. Verification is the acceptance grep above
(zero stale assertions) plus a read-back confirming both instructions are intact
and both rationales now describe drift. No browser/API scenarios apply.
