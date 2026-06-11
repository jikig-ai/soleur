---
title: "Building the model-launch-review skill — brainstorm/spec premise corrections caught at plan + review"
date: 2026-06-11
category: workflow-patterns
tags: [model-launch, premise-validation, retired-rules, pricing-source, cron-host, skill-budget, drift-detection]
issue: 5100
pr: 5157
related_issues: [3791, 5096, 5106, 5172]
module: [model-launch-review, plan, deepen-plan, ship]
related_learnings:
  - 2026-06-10-model-economics-brainstorm-dormant-triggers-and-pricing-source.md
  - 2026-04-18-action-pin-sync-with-model-bump.md
  - 2026-02-22-model-id-update-patterns.md
---

# Learning: model-launch-review skill build — premise corrections caught at plan + review

## Problem

`/soleur:model-launch-review` (#5100) productizes the recurring per-Anthropic-model-release
checklist. The brainstorm + spec were authored from the operator's mental model and carried
**six premises that were wrong against the codebase**. All six were caught downstream (plan
research-reconciliation, plan-review, deepen-plan gates, work, review) — none reached `main`.
The value of this learning is the *catalog of premise classes* and *which gate caught each*,
so the next "productize a recurring checklist" brainstorm front-loads the verification.

## Premise corrections (claim → reality → gate that caught it)

1. **Cited a RETIRED AGENTS.md rule.** Spec FR4 + brainstorm cited
   `cq-claude-code-action-pin-freshness` as the governing rule. It was **retired 2026-04-24**
   (`scripts/retired-rule-ids.txt:80`) and its guidance moved to
   `plugins/soleur/skills/ship/references/ci-workflow-authoring.md`. → Caught by plan research
   (grep AGENTS*.md returned nothing; retired-rule registry confirmed). **Canonical check:**
   deepen-plan's "every cited rule-ID exists as an active rule" gate + the retired-rule registry.
   Cite the *real* surface (the ship reference), not the dead ID.

2. **Pricing claimed harness-only; it lives in-repo.** Spec TR1 said model pricing lived only
   in the `claude-api` harness skill. Reality: `agent-on-spawn-requested.ts:79-102`
   `MODEL_PRICING` is an authoritative in-code table. → Caught by repo-research grep. Disposition:
   **flag-only, never auto-edit** (a billing constant; a wrong "fix" is silently wrong, not
   loud). The `claude-api` table is the *source of truth* for the numbers; the repo table is the *sink*.

3. **Wrong cron host.** Brainstorm leaned `kb-drift-walker.yml`. It has **no `issues: write`**
   (it POSTs HMAC-signed JSON to an ingest route), so it cannot file the detection issue FR7
   requires. The correct host was `rule-audit.yml` (has `issues: write`, governance theme, repo
   checked out), borrowing `scheduled-terraform-drift.yml`'s find-or-update `gh issue` idiom. →
   Caught by repo-research reading the candidate workflow's permissions/architecture. **ADR-033's
   "Inngest > GH-Actions cron" does NOT apply to repo-file-drift detection** — the check needs a
   repo checkout (grep config + `gh api`) that Inngest's server runtime lacks.

4. **Adjacent OPEN issue was a deliberate split, not a dependency.** #5106 (centralize cron
   model literals into `model-tiers.ts`) records "zero shared code/runtime/deploy surface with
   the plugin PR" from a prior 5-agent review. → Ship against the scattered surface with
   `Ref #5106`; do NOT fold in or hard-sequence. When #5106 lands, the model-ID grep target
   collapses to the registry (future simplification).

5. **Skill-description budget at ~1-word headroom.** The cumulative cap (`components.test.ts`
   `SKILL_DESCRIPTION_WORD_BUDGET`) was 2009 with ~2008 used. Any new skill needs a cap bump.
   Bumped +32 → 2041 per the established `#5021`/`#4742` per-skill-bump precedent (bump by the
   new description's exact word count, cite the issue, show before/after).

## Key Insight

When productizing a recurring checklist, treat **every brainstorm/spec claim about a named
artifact (rule ID, file, table, workflow, adjacent issue) as a hypothesis to grep, not a fact.**
The six corrections here split into two families: (a) *cited-artifact drift* (retired rule,
in-repo pricing, wrong host) — caught by a one-command grep against the real surface; and
(b) *scope/sequencing* (deliberate-split adjacency, budget headroom) — caught by reading the
adjacent issue's recorded decision + measuring before assuming. The plan research-reconciliation
table and deepen-plan halt-gates are where these land; front-loading the greps in brainstorm
Phase 1.1 moves the catch even earlier.

## Design dispositions that fell out (for the next model-launch-shaped skill)

- **Auto-fix only the one mechanical-bulk item** (model-ID swaps); flag pin/pricing/tier-map/
  dormant. A flag-heavy auditor with one narrow auto-fix is far safer than a multi-dimension
  auto-fixer (DHH/Kieran/simplicity converged on this, cutting ~35-40% of the first plan).
- **Anchored swap is mandatory.** `sed -E "s/${from}([^0-9A-Za-z-]|$)/${to}\1/g"` preserves
  dated/longer variants (`claude-opus-4-7-20260101` is NOT corrupted by an `opus-4-7→4-8` swap).
- **Detection must loud-fail.** A `--detect` cron step that treats *any* non-success as "clean"
  silent-masks a broken auditor. Only exit 0 is clean; non-0/non-10 must fail the step loudly.
- **Operator-identity PR, not bot token** — a `GITHUB_TOKEN` PR skips CI/CLA; the skill is
  interactive and the cron files an *issue*, never a PR.

## Validation

Post-merge, `gh workflow run rule-audit.yml` ran green and the new detect step filed
**model-drift issue #5172** ("stale Anthropic model IDs in config") for the live `claude-opus-4-7`
drift in 5 cron files — confirming the dormancy fix end-to-end (#3791's "pricing change" trigger
had never fired when Fable 5 shipped).

## Session Errors

1. **SKILL.md `description:` began "used after" not "used when"** — Recovery: reworded to the
   third-person "This skill should be used when…" convention. Prevention: the components.test
   already asserts the `description: "This skill` prefix; author to it first.
2. **Skill-description budget exceeded** — Recovery: cap bump +32→2041. Prevention: measure
   `bun test plugins/soleur/test/components.test.ts` BEFORE finalizing the description (deepen-plan
   Phase 1.8); near-zero headroom means a bump is mandatory, not optional.
3. **Backtick file-ref lint** (`` `references/*.md` `` in SKILL.md) — Recovery: reworded to prose.
   Prevention: the "No backtick file references in skills" component test; use markdown links or
   prose, never `` `references/…` `` / `` `scripts/…` `` inline.
4. **Auditor flagged its own script** (the `AUTOFIX_FROM` patterns matched `audit-models.sh`) —
   Recovery: added `/model-launch-review/` to the exclusion regex. Prevention: a scanner that
   embeds its own match patterns must exclude its own directory.
5. **Review findings (one-off, all fixed inline):** detect step silent-masked non-0/non-10 exits;
   unanchored `--fix` sed; `--detect` test asserted `not.toBe(0)` instead of `toBe(10)`; missing
   `--exclude-dir=community`; predictable `/tmp` body file; `gh issue create` hard-fails on a
   nonexistent label. Prevention: these are the standard GHA-detect-step + bash-auditor review
   checklist — security-sentinel + code-reviewer caught them.
6. **`readme-counts` CI check failed post-push** — Recovery: ran `scripts/sync-readme-counts.sh`
   + added the Development-table row, re-pushed. Prevention: ship **Phase 3 (Verify Documentation)**
   already prescribes the README sync when new components are added; run it BEFORE `gh pr ready`,
   not after CI red. This is the load-bearing recurring miss — a new skill ALWAYS needs the count
   sync + table row.
7. **Two `Edit` calls failed "file not read yet"** (`components.test.ts`, `rule-audit.yml`) —
   Recovery: `Read` then `Edit`. Prevention: Read a pre-existing file before editing (a Write in a
   prior turn satisfies state for that file, but a never-read existing file does not).
