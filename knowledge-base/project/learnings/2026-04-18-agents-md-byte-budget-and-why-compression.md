# Learning: AGENTS.md byte budget discipline and `**Why:**` compression

## Problem

AGENTS.md loads into context on every turn via `CLAUDE.md @AGENTS.md`. It had grown to 40,771 bytes (111 lines, 90 rules) — triggering Claude Code's 40k-char performance warning — primarily because `**Why:**` narratives on ~25 rules had accumulated multi-sentence incident descriptions (PR numbers + root cause + recovery path, sometimes spanning 3-5 sentences).

Compound's step 8 rule-budget check warned on rule **count** (>100) but not on **bytes**. Rule count was fine (90/100); bytes were not. The metric that correlated with real performance impact (char count, per-rule length) was not tracked.

## Solution

Two-pronged: retrofit + prevention.

**Retrofit — compress existing Why narratives.**

- Compressed ~25 verbose `**Why:**` sections to one-line pointers: `**Why:** #NNNN — one-line description.` or `**Why:** see knowledge-base/project/learnings/<file>.md`.
- Also trimmed unrelated verbose rules that restated information better housed in linked skill/runbook files (e.g., `rf-review-finding-default-fix-inline` duplicated content already in `review/SKILL.md` §5 and `compound/SKILL.md`).
- Result: 40,771 → 30,091 bytes (26.2% reduction). All rules now ≤ 582 bytes.

**Prevention — durable workflow guards.**

1. `plugins/soleur/skills/compound/SKILL.md` step 8 now measures **byte size** alongside rule count:
   - `wc -c < AGENTS.md` → warn at >40,000 bytes (perf threshold).
   - Longest rule length → warn at >600 bytes.
   - Existing: >100 rules warning, >300 constitution.md rule warning, 8-week unused-rule aggregator hook.

2. New AGENTS.md rule `cq-agents-md-why-single-line`:
   > AGENTS.md rules cap at ~600 bytes each; `**Why:**` annotations must be one sentence pointing to a PR # or learning file … Compound step 8 warns at >40000 file bytes, >100 rules, or any single rule >600 bytes.

3. `scripts/lint-rule-ids.py` — raised slug-length regex 40→60 chars (fixes two pre-existing format failures for long Cloudflare rule IDs).

## Key Insight

**The right metric for a loaded-every-turn file is bytes, not rule count.** 100 one-line rules is fine; 50 paragraph-long rules is not. The rule-count check gave false comfort — it stayed green while the actual performance impact (context bloat) grew unchecked.

Incident narratives belong in learning files, not in always-loaded context. The rule text is the *invariant*; the incident is the *example*. Pointing to the learning file (`See #NNNN — <file>.md`) preserves traceability without paying the byte cost on every turn.

## Session Errors

- **500-byte rule cap was too aggressive** — Recovery: raised to 600 in both AGENTS.md rule and compound step 8 after three legitimate rules (Cloudflare cache, Next.js route, progressive-rendering) exceeded 500. Prevention: when setting a threshold, first measure the current distribution (`grep '^- ' AGENTS.md | awk '{print length}' | sort -n | tail -5`) to pick a number above the tail, not a round number.
- **Pre-existing `lint-rule-ids.py` format failures** — Two Cloudflare IDs exceeded the hardcoded 40-char slug limit. Pre-existing on main (not introduced by this session), but surfaced because the new CQ rule triggered a re-lint. Recovery: bumped regex to 60. Prevention: lint limits should be validated against existing data when introduced, and re-validated as the rule set grows — a latent lint failure is a tripwire for the next unrelated PR.

## Tags

category: tooling / workflow-infra
module: compound, AGENTS.md, lint-rule-ids
