# Learning: GitHub push protection rejects synthetic secret tokens in plan/spec prose

## Problem

While committing plan + spec + tasks for the `code-to-prd` skill (#2726), `git push` was rejected by GitHub push protection:

```
- Push cannot contain secrets
  Stripe API Key
  path: knowledge-base/project/plans/2026-05-15-feat-code-to-prd-skill-plan.md:230
```

The literal token in the plan body was `sk_test_<<24+ alnum chars, no underscores>>` — a deliberately synthetic Stripe-format fixture token used to illustrate a Kieran P0 plan-review finding (the original buggy form `sk_test_<<tail-with-underscores>>` would not match the sentinel regex `sk_(test|live)_[A-Za-z0-9]{16,}` because `_` is not in `[A-Za-z0-9]`).

GitHub's Stripe-key detector uses `sk_(test|live)_[a-zA-Z0-9]{24,}` (24-char minimum). Our 30-char alnum-only fixture matched. Push declined regardless of `.gitleaks.toml` allowlists (those govern local pre-commit gitleaks; push protection runs server-side and ignores them).

## Solution

Replace literal synthetic tokens in plan/spec/learning **prose** with structural descriptions:

- `sk_test_<<24+ alnum chars, no underscores>>` → `sk_test_<<24+ alnum chars, no underscores>>`
- `sk_test_<<tail-with-underscores>>` → `sk_test_<<tail-with-underscores-that-fails-regex>>`
- `sk_live_<<24+ alnum Layer-2 RED-test fixture>>` → `sk_live_<<24+ alnum Layer-2 RED-test fixture>>`

The angle brackets `<<...>>` break the GitHub regex's `[a-zA-Z0-9]` class while preserving readability and semantic intent.

The **actual fixture file** (e.g., `.env.example` in a test fixture directory) gets the literal token at /work time — combined with a `.gitleaks.toml` allowlist entry for the fixture path, GitHub's secret scanner ignores it because the path is allowlisted at the repo level via Push Protection bypass.

## Key Insight

GitHub push protection ignores local `.gitleaks.toml` — they govern your local pre-commit hook only. Push protection's allowlist mechanism is the operator-clickable URL embedded in the rejection message, OR repo-level "Allowed patterns" configured in Settings → Secret Scanning. Plan/spec/learning prose must NOT contain literal tokens that match the server-side regex floor (Stripe: `{24,}` alnum after prefix). Test fixtures DO get literals — but they go in the fixture file, never in cross-referenced markdown prose.

The asymmetry: **fixture files = allowlisted path = literal tokens fine**; **markdown prose referring to the fixture = no allowlist applies = use structural placeholders**.

## Tags

category: integration-issues
module: git-workflow
related:
  - knowledge-base/project/learnings/2026-05-15-fail-closed-redaction-enables-committed-default-output.md
  - knowledge-base/project/plans/2026-05-15-feat-code-to-prd-skill-plan.md
issue: 2726

## Prevention

Before committing a plan/spec/learning that documents test-fixture secret patterns:

1. `grep -nE 'sk_(test|live)_[A-Za-z0-9]{16,}' <file>` against EVERY markdown file you've touched in the commit.
2. If matches exist, replace each with a structural placeholder using `<<...>>` (or any non-alnum bracket form that breaks the regex).
3. The actual fixture file at `<skill>/test/fixture/.env.example` keeps the literal token. Plan/spec/tasks/learning reference it by structural shape, never by content.
