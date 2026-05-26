---
title: Plan-AC verification commands must verify their own correctness — awk range self-match + marker-conjunction failure modes
date: 2026-05-15
category: best-practices
component: plugins/soleur/skills/plan
tags:
  - plan-skill
  - acceptance-criteria
  - awk
  - verification
  - transcript-judging
  - cross-implementation
related:
  - plugins/soleur/skills/plan/SKILL.md
  - knowledge-base/project/plans/2026-05-15-feat-goal-primitive-operator-escape-hatch-plan.md
  - knowledge-base/project/learnings/2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md
---

# Learning: Plan-AC verification commands must verify their own correctness

## Problem

Two plan-AC defect classes surfaced at plan-review time during the `/goal`-primitive-wiring brainstorm-to-plan pipeline. Both were caught by Kieran-rails-reviewer (P1 findings). Both would have shipped silently passing-but-vacuous merge gates if not caught.

### Defect 1 — Awk range self-match on the start line

The plan's FR2 acceptance criterion used:

```bash
awk '/^### Primitive Choice: \/goal/,/^###/' plugins/soleur/AGENTS.md | wc -w
```

…to verify the new H3 section body is ≤120 words. **The bug:** awk's `/start/,/end/` range matches *from the start line through the next line that matches the terminator pattern* — which on the very first matching row is the start line itself. The command returns only the heading line's word count (≈10 words), not the paragraph body. A reviewer adding the H3 with an *empty* body would pass this AC.

**Fix:** use a flag-based pattern that excludes the start line and terminates on the next H3 OR H2:

```bash
awk '/^### Primitive Choice: \/goal/{flag=1; next} /^### /{flag=0} /^## /{flag=0} flag' plugins/soleur/AGENTS.md | wc -w
```

The `next` after setting flag skips the heading line; `flag=0` terminators fire on subsequent H3 or H2 boundaries. Returns the body word count.

### Defect 2 — Marker conjunction across incompatible implementations

The plan's recipe #4 (lint clean) used the condition:

```
'npm run lint' exited with code 0 (confirmed by an explicit 'echo "exit=$?"' showing exit=0) AND its output line contains "0 errors" or "✓ all good"
```

**The bug:** the conjunction *required* the literal-summary clause, but real-world linters emit incompatible summaries on clean codebases:

- **ESLint default formatter on clean:** no output at all.
- **Biome on clean:** `Checked N files in Xms. No fixes applied.`
- **Prettier `--check` on clean:** `All matched files use Prettier code style!`
- **pytest:** `N passed in 0.03s` (no "0 failed").
- **bun test:** `X pass / Y fail` (no "0 errors").

None match `0 errors` OR `✓ all good`. Result: a Soleur operator running this `/goal` recipe against any of these tools on a clean codebase has the goal run to its cap, **burning API budget on already-passing code** — the exact brand-survival threshold (`single-user incident`) the plan was designed to prevent.

The same defect class applied to recipes #1 (test gate) and #3 (API migration sweep), each conjoining `exit=0` with a tool-specific summary literal.

**Fix:** the structured signal (exit code echoed as `exit=0`) is the canonical-across-implementations marker. Pair the literal-summary clause only when the verifier has grepped every real-world implementation's actual output. For Soleur's recipes, drop the literal-summary clause entirely:

```
the most recent lint command exited with code 0 (confirmed by an explicit 'echo "exit=$?"' showing exit=0 in the transcript), or stop after 10 turns
```

## Solution

**For Defect 1 (awk range self-match):** before any plan AC uses awk's `/start/,/end/` range for body-extraction (heading-to-next-heading word count, fenced-block content, section-bound greps), test the command against a fixture where the start line and body are distinguishable. The range is correct for *line-inclusive* operations (e.g., printing every line in the range), but wrong for "extract the body between heading and next heading." Default to the flag-based pattern unless you specifically need the inclusive form. The flag-based pattern is also more readable, terminates on multiple boundary types (next H3 OR H2), and preserves grep-ability.

**For Defect 2 (marker conjunction):** when an AC, recipe condition, hook predicate, or any verification gate combines two signals with AND, classify each signal as either *implementation-invariant* (exit code, HTTP status, file existence, byte count) or *implementation-variant* (summary literals, prose text, format-version-specific output). Implementation-variant signals MUST NOT be the load-bearing half of an AND that gates "correctness." Either drop the variant clause entirely, OR enumerate every implementation's output via grep across `node_modules/` / docs / package-lock dependencies AND ship the AC with an OR over all variants. Adding more ANDs to a verifier doesn't make it stricter — it makes it more brittle.

## Key Insight

**An AC verification command must itself be falsified by something other than the bug it's supposed to catch.** The awk range AC passed on heading-only output because the *bug class* (empty body) and the *verification class* (heading-only output passes the check) overlap. The recipe-conjunction AC passed (in the sense of "the literal-summary clause never matched, so the goal stays no") in a way that made the verification a no-op. Plan-AC authoring is a verification-of-the-verifier problem: every grep, jq, awk, test command an AC ships should be exercised against (a) a known-good fixture that should pass, (b) a known-broken fixture that should fail, AND (c) the most permissive failure mode of the underlying implementation that the AC is meant to enforce. If (c) passes the verifier, the verifier is broken — not the implementation.

The same lens generalizes: any "command succeeded AND its output looks a certain way" gate (preflight checks, ship-skill verification, CI assertions) must use only the implementation-invariant half OR enumerate every implementation. The brand-survival incidence (operator burns API budget on clean codebase because the conjunction never matches) is the most extreme form — most defect-class instances will instead be "verifier always passes" and the bug ships silently.

## Session Errors

1. **Repo-research-analyst reported `AGENTS.core.md` missing when verifying the FR1.2 rule citation.** Recovery: independent grep at worktree root found the sidecar with the rule body at line ≈21. Prevention: same as brainstorm-time learning `2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md` Mode 1 (subagent CWD path-resolution false-negatives). No new prevention proposal — the existing learning already prescribes "verify subagent file-existence claims independently before propagating into artifacts."
2. **Edit tool old_string mismatches** on two large block edits during plan refinement. Recovery: Read + retry to capture exact whitespace/regex form. Prevention: for long block replacements (≥100 chars), fetch the exact lines via Read immediately before Edit. In-context paraphrase drifts from on-disk text after intermediate edits.

## Tags

category: best-practices
module: plan
