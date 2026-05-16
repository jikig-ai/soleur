---
date: 2026-05-12
category: best-practices
component: plan-skill
problem_type: paraphrase_without_verification_extended_to_own_proposals
severity: medium
tags:
  - plan-quality
  - parsing-patterns
  - verify-before-cite
  - awk
  - frontmatter-extraction
related_issues:
  - 2721
related_learnings:
  - knowledge-base/project/learnings/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md
  - knowledge-base/project/learnings/2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md
---

# Learning: Plan-time pattern proposals need codebase-precedent grep, same as issue-body claims

## Problem

While drafting the v1 plan for #2721 (orchestration lanes), I prescribed `awk '/^lane:/ {print $2; exit}'` as the frontmatter-extraction pattern across three call sites (plan SKILL.md, work SKILL.md, test scaffold). The pattern is brittle:

- A quoted YAML value (`lane: "cross-domain"`) prints `"cross-domain"` including the quotes.
- Trailing whitespace is preserved verbatim.
- `$2` assumes a single-token value with no embedded spaces.

Multi-agent plan review (Kieran P1.2) surfaced the canonical precedent already in the codebase: `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:34` uses the robust form:

```bash
awk '/^version:/ { gsub(/^version:[[:space:]]*"?|"?$/, ""); print; exit }'
```

This strips the key prefix, optional whitespace, and surrounding quotes in a single substitution before printing. Three call sites had to be rewritten at plan-review time.

## Solution

Before prescribing any parsing/extraction pattern (`awk`, `grep`, `jq`, `sed`, `yq`) in a plan, grep the codebase for the closest precedent at **plan-write time**, not at /work time. Concretely:

```bash
# Look for awk/sed/grep patterns that extract from frontmatter or YAML
git grep -E "awk.*['\"]/\^(lane|brand|version|name):" plugins/ knowledge-base/
git grep -E "gsub\(/\^" plugins/ scripts/
```

Adopt the existing pattern verbatim if one exists; only invent a new pattern when no precedent is found AND document the absence in the plan body.

## Key Insight

The `paraphrase-without-verification` learning class (`2026-04-22-ts-sql-normalizer-parity...`) covers issue-body claims and adjacent-PR symbol claims. It applies equally to **one's own pattern proposals authored at plan time**.

The asymmetry is sharp:
- **Plan-time grep cost:** ~2 minutes for a single `git grep` invocation.
- **Plan-review-time pivot cost:** rewriting 3 call sites + a test fixture + the plan body's Risks section + the resume prompt — easily 15-30 minutes.
- **/work-time pivot cost (worse):** rewriting after RED tests have been authored against the brittle form — easily 45 minutes plus a checkpoint commit revert.

The LLM authoring a plan does not have native introspection on its own brittleness. It must externalize that check via codebase grep, the same way it externalizes issue-body verification.

## Prevention

- For any parsing/extraction pattern in a plan, add a Phase 0 / Research Reconciliation step: "grep the closest precedent in `plugins/` and `scripts/` for this extraction shape; adopt verbatim or document absence."
- Add a one-bullet entry to `plan/SKILL.md` Sharp Edges so the rule applies at plan-skill execution time, not just in memory.
- Extend the rule beyond parsing: any "X is the convention" assertion in a plan body should have a codebase-grep citation within 1-2 lines (e.g., "uses the gsub awk pattern from `skill-security-scan/scripts/run-scan.sh:34`").

## Session Errors

- **Plan v1 prescribed brittle awk extraction in 3 call sites** — Recovery: rewrote all 3 + the test fixture at plan-review time after Kieran P1.2 surfaced the gsub precedent. Prevention: as documented above; route a bullet to plan SKILL.md Sharp Edges.
- **Initial plan over-decomposed (9 phases / 10 assertions / 5 deferrals)** — Recovery: review panel converged on 5/7/2; cuts dissolved 3 of the correctness findings. Prevention: markdown-driven plans default to ≤5 phases unless cross-file ordering demands more. (Already covered by `2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails` — no new learning needed.)
- **Brainstorm-doc frontmatter prescription duplicated brainstorm-techniques canonical template** — Recovery: dropped the inline prescription; spec.md is canonical post-Phase-3.6. Prevention: before prescribing prose changes, check whether a "canonical template" skill exists for that artifact class.
- **"Informational not binding" self-deception** — Recovery: architecture-strategist reframed as "non-binding in skill logic; operators may use as heuristic". Prevention: when asserting a read-only invariant, ask whether the human-in-the-loop who sees the value can ignore it.
- **Silent default events buried in artifact** — Recovery: added operator-terminal echoes for procedural skip, fail-closed override, expansion. Prevention: default fail-closed paths to "echo AND artifact", not "artifact only".

## Tags

category: best-practices
module: plan-skill
