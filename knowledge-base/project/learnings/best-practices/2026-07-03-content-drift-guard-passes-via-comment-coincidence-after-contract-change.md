---
date: 2026-07-03
category: best-practices
module: ci-workflow-drift-guards
issue: 5960
pr: 5963
tags: [drift-guard, content-assertion, toContain, contract-change, false-pass, seccomp]
---

# Learning: a content-drift-guard test passes for the wrong reason when the removed field name survives in an explanatory comment

## Problem

#5960 rewrote `.github/workflows/apply-deploy-pipeline-fix.yml`'s redeploy step so its
load-bearing "is the committed seccomp profile actually loaded?" assert reads NEW live
discriminators (`seccomp_profile_loaded_matches_host`, `seccomp_profile_host_sha256`) instead
of the OLD ephemeral recorded field `seccomp_profile_sha256`. AC6 required no
`.seccomp_profile_sha256` equality gate remain.

A drift-guard test — `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` — asserts the
redeploy step's content with `expect(stepBlock).toContain("seccomp_profile_sha256")`. After the
rewrite the suite still reported **89 pass / 0 fail**. But it passed only because the rewrite
left an *explanatory comment* in the step: `# recorded .seccomp_profile_sha256 (reboot-cleared,
latch-blind)`. The `toContain` matched the comment, not a live gate. The test now certified a
contract the code no longer implements — a false-authoritative GREEN. Caught at review by
`pattern-recognition-specialist`, not by the passing suite.

## Solution

When you change the load-bearing field/identifier that a **content-drift-guard** test asserts on
(any `toContain("<literal>")` / `toMatch(/<literal>/)` over a source-text block), update the
guard's assertions to the NEW contract in the **same** change:

- Replaced `expect(stepBlock).toContain("seccomp_profile_sha256")` with assertions on the two
  new load-bearing discriminators (`seccomp_profile_loaded_matches_host` +
  `seccomp_profile_host_sha256`).
- Re-ran: still 89 pass — but now for the *right* reason (the assertions track the real gate).

## Key Insight

A content-assertion drift guard (`toContain`/`toMatch` over source text) cannot distinguish a
**live gate** from a **comment or dead reference** — the literal it greps for lives in both. So
removing a field as a load-bearing gate while leaving the field name in an explanatory comment
makes the guard pass *for the wrong reason*: it certifies a contract the code abandoned.

Mechanical tripwire when editing a step/block that a content-drift-guard asserts on: after the
edit, grep the test for every literal it asserts on the block, then confirm each literal appears
in the block as **executable code**, not just prose. If the assert's intent moved to a new field,
move the assertion too — don't rely on an incidental comment match to keep the suite green. Same
class as "self-claimed cross-artifact contract drift" and "replicated literal without parity
test" in `review/SKILL.md` — a passing content-grep test is necessary but not sufficient; the
grepped literal must be load-bearing, not incidental.

## Session Errors

1. **ADR-079 amendment Edit failed on first attempt** (`String to replace not found`). The
   `old_string` spanned a line-wrap ("...must not widen the deploy\ncontract...") that didn't
   match the file's actual break. **Recovery:** re-anchored on a shorter unique string
   (`**The deploy contract stays semver-only.** ...`). **Prevention:** for multi-line `old_string`
   on prose files, anchor on the shortest unique single-line span rather than a wrapped sentence.
   One-off — no recurrence vector.

2. **Drift-guard test passed for the wrong reason** (the subject of this learning). **Recovery:**
   updated `ship-deploy-pipeline-fix-gate.test.ts` to assert the new discriminators. **Prevention:**
   when a `/work` change removes/renames a field that a content-drift-guard `toContain`s, update the
   guard's assertions in the same commit; a comment retaining the old literal is a false-pass vector.
   Recurring — captured here + routed to the review skill's defect-class catalogue.
