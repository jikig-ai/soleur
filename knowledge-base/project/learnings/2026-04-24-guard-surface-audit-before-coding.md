---
title: Guard-surface audit before coding — count existing matches against the guard's reject-criteria at plan time
date: 2026-04-24
category: best-practices
tags: [planning, guards, linter, data-validation, agents-md, hr-rules]
pr: 2877
issue: 2871
related_learnings:
  - 2026-04-21-agents-md-rule-retirement-deprecation-pattern.md
---

# Guard-surface audit before coding

## Context

PR #2877 (issue #2871) added a hard-block in `scripts/lint-rule-ids.py`
preventing retirement of `hr-*` rule ids via `scripts/retired-rule-ids.txt`.
Threat model: a future PR retires a security-critical hard-rule (e.g.
`hr-never-fake-git-author`) via a plausible-looking allowlist append; under
`cq-rule-ids-are-immutable`, retirement is one-way, so a missed review
permanently disables the rule.

The brainstorm, spec, and plan all asserted **"no `hr-*` currently
retired — this is future-risk hardening."** When the guard landed and was
run against the real allowlist, the linter immediately rejected two ids
that had been retired in PR #2865 via the discoverability-litmus pass:
`hr-before-running-git-commands-on-a` and
`hr-never-use-sleep-2-seconds-in-foreground`.

The fix was straightforward — introduce a `HR_RETIREMENT_ALLOWLIST`
frozenset grandfathering the two pre-existing retirements — but the
real learning is that the premise "no hr-* currently retired" was never
actually verified. Two minutes of plan-time grep would have surfaced
the need for grandfathering before any code was written, avoiding a
mid-implementation pivot.

## Root cause

The brainstorm researched the threat model (what to protect), the spec
defined the guard shape (how to enforce), and the plan enumerated
implementation steps — but none of those phases audited the **current
state of the protected surface** against the guard's reject-criteria.

The question "would this guard reject any existing data?" was never
asked, let alone answered.

## The pattern

When adding a guard, validator, or linter that protects a surface with
existing data, audit the data against the new rule at plan time. The
audit is mechanical:

```bash
# For a guard that rejects `X` entries in file F, run:
grep -cE '<reject-pattern>' <protected-file>

# If count > 0, the plan must account for grandfathering OR
# retroactive remediation. Choose one:
#   (a) grandfather existing entries via an allowlist in the guard
#   (b) retroactively remove/migrate existing entries in the same PR
#   (c) narrow the guard's pattern so existing data is not rejected
```

For this PR specifically:

```bash
grep -cE '^hr-' scripts/retired-rule-ids.txt  # Returned 2, not 0.
```

Two minutes. Would have surfaced at brainstorm time, not at GREEN.

## Generalization

This pattern applies to any new enforcement primitive:

- Adding a schema validator → count existing records that violate the schema.
- Adding a field-shape regex → count existing strings that don't match.
- Adding a lint rule to CI → count existing files that would fail.
- Adding a CODEOWNERS requirement → count PRs that would have been blocked.
- Adding a new required header to API responses → count endpoints missing it.

The question to ask at **plan time** (not work time): "Run the guard's
reject-criteria against the current surface. What does the count return?
If non-zero, the plan's Acceptance Criteria must cover grandfathering or
remediation — not just future enforcement."

## Relationship to `cq-when-a-plan-paraphrases-an-issue-bodys-file-path-or-site-count-claims`

The existing AGENTS.md rule
`cq-when-a-plan-paraphrases-an-issue-bodys-file-path-or-site-count-claims`
says plans must not paraphrase issue-body claims without verification.
This learning is that rule's **forward-looking sibling**: plans must
not assert forward claims about the protected surface
("no hr-* currently retired") without the same verification.

Paraphrase-without-verification and assertion-without-verification are
the same failure mode, and the same mechanical fix (run the grep)
addresses both.

## Prevention

Add a plan-time step in the brainstorm/plan skills: **Guard-Surface
Audit**. Any feature adding a validator/guard/linter must include a
command in the plan body that runs the guard's reject-criteria against
the current surface and records the count. If the count is non-zero,
the plan's Acceptance Criteria must name the grandfathering or
remediation approach.

Proposed one-line bullet for `plugins/soleur/skills/plan/SKILL.md`
(Sharp Edges):

> When a plan prescribes a validator/guard/linter that rejects a
> pattern in existing data, include a plan-time grep counting current
> matches. If non-zero, Acceptance Criteria must cover grandfathering
> or remediation — "future-only enforcement" is a false framing when
> the surface already contains matches.

## Session Errors

1. **Plan asserted "no hr-* currently retired" without verification.**
   Recovery: introduced `HR_RETIREMENT_ALLOWLIST` grandfather set mid-GREEN.
   Prevention: proposed plan-skill addition above.

2. **Literal Unicode BOM characters (U+FEFF) in markdown docs broke
   `markdownlint-cli`** with `MD038/no-space-in-code` when placed inside
   backtick code spans. Recovery: `sed` substitution replacing BOM
   with `﻿` escape sequence in prose, plus `markdownlint-cli --fix`
   for fence-blank-line issues.
   Prevention: when describing a test fixture containing a BOM in
   markdown, use the escape sequence `﻿` in prose and commit the
   raw character only in the test file itself. Filed as an instance of
   `cq-prose-issue-ref-line-start`-class (markdownlint-sensitive prose).

3. **Review agent (git-history-analyzer) reported "unrelated deletions"**
   of two files that were actually ahead on main (diff-direction artifact).
   Recovery: verified with three-dot `git diff origin/main...HEAD` per
   `rf-review-diff-direction` Sharp Edge.
   Prevention: already documented; no new rule.

## See also

- `cq-when-a-plan-paraphrases-an-issue-bodys-file-path-or-site-count-claims`
  (AGENTS.md) — verification requirement for paraphrased claims
- `2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` —
  pointer-preservation pattern that precedes this learning
- `wg-every-session-error-must-produce-either` — discoverability exit
  (this PR's error message IS the signal, so no AGENTS.md rule edit)
- PR #2877 / issue #2871 — the implementation
- PR #2865 — the retired-ids allowlist that introduced the pre-existing
  `hr-*` entries this PR grandfathered
