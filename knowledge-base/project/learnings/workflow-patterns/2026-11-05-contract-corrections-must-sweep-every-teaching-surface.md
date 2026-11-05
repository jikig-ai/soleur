---
title: "A contract correction that reaches 3 of ~8 teaching surfaces leaves the old contract live"
date: 2026-11-05
tags: [review, fix-to-class, phrase-pins, devin, emit-sites]
---

# Contract corrections must sweep every teaching surface, and the guard must cover the population

PR #12135 corrected the Devin `run_subagent` contract ("takes a profile, not a
Soleur agent id") in `devin/INSTRUCTIONS.md` plus two `harness.ts` emit arms — and
left the OLD contract live on four unrouted surfaces: `routingInstructions("devin")`
in the same file, two `harness-forms` rows in `commands/go.md`, and
`skills/go/SKILL.md` (the actual `/soleur:go` Devin handler). Six independent review
seats converged on it as the top finding; the guard suite that shipped with the fix
pinned only the new copies.

**The two-layer defect, both halves required to fix:**

1. **Sweep the class, not the instance.** The review reference's fix-to-class
   defect applies to *instruction prose* as much as to code: enumerate every
   surface that teaches the contract (`git grep` the tool name + the arg shape,
   then a structural-enumeration pass for emit sites, `harness-forms` regions,
   and entry-point SKILL.md shims), and change all of them — or explicitly
   record the deferred sites. A contract taught in N places needs N edits or
   N-1 deletions.
2. **Guard the population, not the exemplar.** A phrase-pin suite that greps
   one canonical file for presence tokens is blind to (a) the same claim on
   other surfaces, (b) reordered/inverted/comment-wrapped copies of the claim.
   The durable shapes that landed: ordered regexes binding predicate→profile
   inside a single match; `not.toContain("with agent id")` negatives scoped so
   a legit sibling line (Grok's `spawn_subagent` agent-id bullet) survives;
   and the suite *reading the other emit surfaces* (`commands/go.md`,
   `skills/go/SKILL.md`) rather than only the canonical doc.

**Cheap durable check:** when a PR "corrects" a sentence, grep the sentence's
*subject* repo-wide — `run_subagent`, the profile names, the arg shape — not the
corrected phrase, and pin every hit that must stay corrected.

**Recorded artifact drift is the sibling class.** The same review caught
`spec.md` G6/TR1, the ADR addendum's seam sentence, and `tasks.md` asserting a
pre-review state as shipped. Any artifact that says "the PR does X" needs a
final reconcile pass against the diff after review fixes land.

## Session Errors

- **Secret scan run from the bare/root surface** (empty-range verdict) —
  Recovery: reran from the worktree — Prevention: verify `git rev-parse
  --show-toplevel` is the worktree before trusting a `range=N` count.
- **Push ran before the prepush secret scan** (script path guessed
  `scripts/` instead of `skills/ship/scripts/`); retro-scan CLEAN — Recovery:
  resolved path from the plugin tree — Prevention: resolve ship-script paths
  from the manifest, not memory.
- **`SOLEUR_TALLY_ERROR reason=missing-file`** — ledger not initialized before
  first push — Recovery: `tally-init` — Prevention: init at setup.
- **Two `edit` misses on `formatAgentSpawn`** (assumed 8-space indent; file
  uses 6) — Recovery: `cat -A` the region, then python — Prevention: read
  exact indentation before constructing `old_string`.
- **`\u00a7` written literally into `harness.ts`** (heredoc escape bug) —
  Recovery: immediate python fix — Prevention: verify written output for
  non-ASCII intent.
- **`sed -i 's/[[:space:]]*$//'` ran file-wide** for a one-line fix —
  Recovery: `git diff` confirmed only the target line changed — Prevention:
  scope sed line-ranges.

## Key Insight

The failure was not a wrong fix — it was a correct fix applied to the visible
instances while the *class* of surfaces teaching the contract stayed stale,
guarded by a suite that measured the tokens it wrote rather than the property
it named. Instruction prose has emit sites exactly like code has call sites.

## Tags
category: workflow-patterns
module: plugins/soleur (devin harness, review skill)
