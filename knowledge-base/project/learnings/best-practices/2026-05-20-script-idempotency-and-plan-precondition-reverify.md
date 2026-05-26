---
title: "Script idempotency claims need automated multi-run gates; plan-time preconditions must be re-verified at /work start"
date: 2026-05-20
category: best-practices
module: scripts/backfill-frontmatter.py
tags:
  - idempotency
  - plan-preconditions
  - test-fixtures
  - yaml-serialization
  - red-verification
severity: medium
problem_type: best_practices
symptoms:
  - "Re-running `scripts/backfill-frontmatter.py` doubles YAML single-quote escapes on each pass (`'''eu'''` → `''''''''eu''''''''`)"
  - "Plan-quoted sentinel-grep regex (`^- (module-level-state|category-design)`) returned 0 hits because sentinels live at column-3 YAML-list indent, not column-1"
  - "Plan AC asserted sentinel-file diffs would be empty; first script run added a missing `date:` field, producing a non-empty (but semantically correct) diff"
  - "Initial RED test passed vacuously — structured-kv path's tag values never naturally collide with the `category-*`/`module-*` reject prefixes"
synced_to: []
---

# Script idempotency + plan precondition re-verify

## Problem

Three precondition / idempotency traps surfaced while shipping the Stage 2 follow-up to #4119 (PR #4156 → #4163).

### Trap 1: idempotency claim without enforcement

`scripts/backfill-frontmatter.py` opens with `"""Idempotent: safe to run multiple times with identical results."""` But running the script a second time mutates 9 of 1166 files: titles containing literal `'` characters get their YAML quote-escape doubled on each pass. Stage 1 (PR #4156) ran the script once → titles became `''''eu''''` (2 literal quotes). Stage 2 re-ran it → titles became `''''''''eu''''''''` (4 literal quotes). The next run will double again to 8.

The bug lives in `frontmatter_lib.serialize_frontmatter`'s yaml-dump path. The docstring assertion is unenforced — no CI gate verifies idempotency against the corpus.

### Trap 2: plan-quoted regex anchored at wrong column

The plan's §Acceptance Criteria specified `grep -rEn "^- (module-level-state|category-design)\b" knowledge-base/project/learnings/` as the sentinel-survival gate, expecting 2 hits. In reality, both sentinels live in YAML-list frontmatter at column-3 indent (`  - module-level-state`), not at line-start. The `^-` anchor returned 0 hits.

The plan-author never grepped this against current main before quoting it. Surfaced at Phase 0 baseline check.

### Trap 3: plan AC asserted "diff returns EMPTY" for files needing schema enrichment

The plan claimed `process_file_with_frontmatter()` would short-circuit on sentinel-A because the file had "complete pre-existing frontmatter". It actually was missing the `date:` field — the script correctly extracted the date from the filename and added it. The diff was non-empty (schema enrichment), but the tag `category-design` survived (sentinel intent met).

### Trap 4: vacuous-green RED test

`test_structured_kv_path_drops_noise_prefixes` was authored against fixture `category: integration-issues / module: marketing-aeo / severity: medium` and asserted "no tags start with `category-` or `module-`". This passed without the filter — the structured-kv path emits VALUES (`integration-issues`, `marketing-aeo`, `medium`), none of which start with the reject prefixes. The test was indistinguishable pre/post-filter.

Caught during RED verification per the existing rule `2026-04-18-red-verification-must-distinguish-gated-from-ungated`. Restructured with a synthetic fixture `severity: --synthetic-noise` to force a token through the filter that wouldn't survive without it.

## Solution

Each trap was worked around at the session level. The compounding insights:

### Trap 1 — idempotency-claim policy

**Rule:** A script that asserts idempotency in its docstring/README MUST have a CI test that runs it twice and `git diff --quiet`'s the result.

For backfill-frontmatter specifically: filed as a noted pre-existing bug (not in scope for this PR). Reverted the 9 over-escaped files via `git checkout --`.

### Trap 2 — plan-precondition re-verify gate

**Rule:** Plan-quoted regexes / grep commands / CLI commands ARE preconditions, not facts. /work MUST re-run each one at Phase 0 against the worktree's current state before depending on them. AGENTS.md already captures the bytes-budget version of this (`hr-plan-preconditions-must-be-verified`). The grep-regex case is a subspecies — same fix.

### Trap 3 — schema-enrichment is NOT a corruption signal

**Rule:** When a plan AC reads "diff returns EMPTY" against a script that adds missing schema fields, the AC must either (a) be relaxed to "tag X survives" / "field Y present" semantic checks, or (b) be preceded by a Phase 0 step that pre-enriches the sentinel files so the diff is genuinely no-op.

### Trap 4 — synthesized RED fixtures

**Rule:** Per `2026-04-18-red-verification-must-distinguish-gated-from-ungated.md` — RED tests must distinguish gate-present from gate-absent. For prefix-filter helpers, this means: if real-world inputs don't naturally collide with the reject pattern, synthesize a fixture that does. The synthesized value can be flagged as a fixture in a comment so future readers don't grep production for it.

## Key Insight

A docstring assertion (idempotency, schema, etc.) without an automated enforcement gate is documentation, not a contract. The first time someone violates the assertion at runtime, three things happen: (a) the violation is invisible (no error), (b) the asserter trusts the docstring and skips verification, (c) the violation compounds across runs. The fix is an enforcement gate, not a stronger assertion.

Same shape applies to plan-quoted preconditions: any line the plan claims as a current-state fact (regex returns N, file has field X, baseline count is M) is actually a precondition that drifts in parallel branches and must be re-verified at /work entry.

## Session Errors

1. **Plan sentinel grep regex was wrong-anchored** — Recovery: corrected to a non-anchored grep in actual verification; ACs still passed semantically. **Prevention:** plan authors should grep the exact regex against current main before committing it as a precondition.

2. **Sentinel-A diff non-empty despite plan claim** — Recovery: inspected the diff, confirmed schema enrichment (added missing `date:` field) not corruption; AC interpreted semantically. **Prevention:** when an AC reads "diff returns EMPTY" against a script that adds missing required fields, either pre-enrich the sentinels at Phase 0 or relax the AC to a tag/field-survival check.

3. **Vacuous-green RED test on structured-kv path** — Recovery: restructured with `severity: --synthetic-noise` fixture to distinguish gate-absent from gate-present. **Prevention:** explicitly applied during RED verification per existing rule `2026-04-18-red-verification-must-distinguish-gated-from-ungated`; no new rule needed.

4. **Pre-existing idempotency bug in serialize_frontmatter** — Recovery: reverted the 9 over-escaped files via `git checkout --`. **Prevention:** add a CI test that runs `python3 scripts/backfill-frontmatter.py` twice against a checkout and asserts `git diff --quiet`. Out of scope for #4163; not filed as a follow-up issue given low-9-file-cosmetic impact.

5. **`_reject_yaml_block_noise` docstring drift caught only by 3-agent review** — Recovery: corrected docstring inline (commit `258e62d2`). **Prevention:** helper docstrings that describe a corruption-shape mechanism must trace the actual code paths that produce the shape; multi-agent review reliably catches drift when prompt explicitly asks "does docstring claim match the path?".

## Related

- `2026-04-18-red-verification-must-distinguish-gated-from-ungated.md` — RED fixtures must force the gate
- `2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md` — plan-quoted preconditions drift
- AGENTS.md `hr-plan-preconditions-must-be-verified` (bytes-budget application of the same rule)

## Tags

category: best-practices
module: scripts/backfill-frontmatter.py
severity: medium
prs:
  - "4182"
closes:
  - "4163"
