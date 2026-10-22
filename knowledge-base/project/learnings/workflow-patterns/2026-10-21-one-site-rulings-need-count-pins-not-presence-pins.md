---
title: "An exactly-ONE-site ruling needs a count pin — a presence pin cannot express cardinality"
date: 2026-10-21
category: workflow-patterns
module: plugins/soleur/test
tags: [pins, sentinels, test-authoring, cardinality, review-findings]
issue: 10400
pr: 10718
---

# Learning: match the pin's assertion form to the claim's quantifier — `found` proves ≥1, never =1

## Problem

PR #10718 carries a CTO ruling that cut `work/SKILL.md`'s RED-vocabulary selection guidance
from two sites to exactly ONE (byte ceiling: only ~118 B headroom under
`lint-skill-body-budget.py`). The first pin draft used `found()` — presence, ≥1 — which is
satisfied whether the token appears once or five times, so it could not detect a second site
re-added later. The fix-round's code-quality seat flagged it; the fix (c51e00febd) changed the
pin to `assert_eq "1" "$(count "$WORK_SKILL" 'RED\(unit\|integration\|e2e\|property\)')"` with a
message naming the one-site ruling.

Adjacent in the same fix commit: stale "both sites" wording had survived the ruling at two
places in the plan doc — a correction sweep keyed on subject, not phrasing, caught them.

## Solution

- Presence specs (`X must appear`) → `found` / `grep -q`.
- Cardinality specs (`X at exactly N sites`) → `count` against the literal N, with the ruling
  named in the assert message.
- After any ruling that CHANGES a count, sweep the claim's subject repo-wide — `git diff
  --name-only` cannot see a twin wording site in a file the diff never touched.

## Key Insight

A pin asserts a quantifier, not a string. `found` encodes `∃`; a one-site ruling encodes `=1`.
When the spec's quantifier tightens, the pin's arithmetic must tighten with it — otherwise the
gate certifies a weaker claim than the one that was ruled.

## Session Errors

**crates.io API returned 403 without a User-Agent header**

- **Recovery:** retried with a UA header; proptest 1.12.0 verified.
- **Prevention:** crates.io requires a `User-Agent` on API calls — send one on first request.

**deepen-plan §4.7 pure-docs exemption does not cover `plugins/*/skills/*.md`**

- **Recovery:** plan carried the full `## Observability` block; gate passed.
- **Prevention:** none needed — the boundary is deliberate (skill definitions are executable
  instructions, not docs). Recognise a `plugins/soleur/skills/**` docs-shaped change as
  gate-bearing at plan time.

## Related

- `cq-assert-anchor-not-bare-token` — the anchor-shape sibling rule (anchoring vs cardinality).
- `plugins/soleur/skills/review/references/generated-input-oracle-surfaces.md` — review
  checklist where the cardinality bullet was routed.
