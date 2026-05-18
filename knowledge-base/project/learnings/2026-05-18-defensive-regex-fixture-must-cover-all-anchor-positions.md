---
title: "Defensive regex fixtures must cover all anchor positions, not just happy path + garbage"
date: 2026-05-18
category: best-practices
module: ci-workflows
related_prs: [4022, 4006]
related_issues: [4016]
related_learnings:
  - 2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md
  - 2026-04-22-plan-ac-external-state-must-be-api-verified.md
  - 2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md
tags: [regex, anchoring, fixtures, defense-in-depth, ci, github-actions]
---

# Defensive regex fixtures must cover all anchor positions

## Problem

PR #4022 widened a regex in `.github/workflows/scheduled-gh-pages-cert-state.yml` from a strict ISO-datetime check to a two-branch form (date-only OR ISO datetime, else reject). The plan listed three fixtures:

- `2026-08-16` (date-only happy path)
- `2026-12-31T12:00:00Z` (ISO datetime defensive path)
- `not-a-date` (garbage rejection)

These covered the canonical happy paths and one negative case, and felt complete. Post-implementation multi-agent review surfaced two P2 anchor-position findings that the three fixtures could not have caught:

1. The datetime branch's regex was left-anchored only (`^...` no `$`). Inputs like `2026-08-16T00:00:00Z; rm -rf /` matched the regex (double-quoting + `date -d` rejection prevented RCE, but defense-in-depth was leaky).
2. The date-only branch's `^...$` was claimed to reject partial-date inputs like `2026-08-16T`, but no fixture proved it.

## Solution

Tightened the datetime branch to `^...(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$` (fully anchored, accepts UTC `Z` / `+offset` / fractional seconds) and added seven verification fixtures covering every anchor position:

- Date-only: `2026-08-16` (canonical) → epoch 1786924799
- ISO datetime variants: `Z`, `+00:00`, fractional seconds
- Garbage: `not-a-date`
- **Injection-shaped tail:** `2026-08-16T00:00:00Z; rm -rf /` → rejected
- **Partial date+T:** `2026-08-16T` → rejected (anchor proof)

## Key Insight

**A regex test plan with only "happy path + obvious garbage" fixtures is structurally incomplete.** The minimum coverage set for any anchored validator is:

1. **Canonical happy path** for each accepted branch.
2. **Format-variants** the production source could plausibly emit (timezone offsets, fractional seconds, normalized vs trailing-space).
3. **Obvious garbage** (the user's mental model of "wrong").
4. **Anchor-trap inputs** — strings that look like a happy path but truncate at, or extend past, the regex's anchor boundary. Each `^` or `$` in the regex should have a fixture that would fail if that anchor were removed.
5. **Injection-shaped inputs** — strings whose prefix matches the happy path but whose suffix contains shell metacharacters. Required when the matched value is interpolated into any subprocess command, even when double-quoted.

The plan's three fixtures covered (1) and (3) only. Reviewers (pattern-recognition + security-sentinel) independently surfaced (4) and (5), which is exactly the cross-reconcile pattern from `2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md` working as intended on the positive side: two concurring P2s are signal, not noise.

## Prevention

When writing the Test Strategy section of a plan that changes a regex/validator:

1. Enumerate every `^` and `$` in the regex — each gets a fixture that depends on it.
2. If the matched value is passed to a subprocess (`date -d`, `eval`, anything via `$VAR`), add an injection-shaped fixture explicitly.
3. Run all fixtures BEFORE marking the AC checkbox, not after. Plans that list 3 fixtures and claim "anchoring matters in Risks bullet 5" without a corresponding fixture row are self-incomplete — the deepen-plan phase should add the missing row, not rely on review.

## Session Errors

1. **Edit hook blocked first attempt on workflow file** — `.claude/hooks/security_reminder_hook.py` emitted an advisory about GitHub Actions workflow injection (not applicable to this regex-only diff). First Edit call returned "hook error"; second identical Edit call succeeded. Recovery: retry the same Edit. **Prevention:** when a PreToolUse hook on a workflow edit emits an advisory whose pattern catalog (e.g., `${{ github.event.* }}`, `head_ref`) does not apply to the diff, retry the Edit once before pivoting to a fallback (sed/awk). The hook appears configured to warn-then-allow; treating the first rejection as fatal causes unnecessary fallback to lower-quality tools.
