---
feature: feat-code-quality-linters-10331
issue: 10331
pr: 10342
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-15-code-quality-linters-brainstorm.md
---

# Spec: triage GitHub Code Quality findings and wire deterministic linters

## Problem Statement

GitHub Code Quality reported 169 open findings (22 rules) on `main`. Most are recurring agent-written-code habits the pipeline should catch deterministically. Two sit in GDPR-sensitive server code, and several silent exception handlers sit in scripts that ship to users. Python has no linter, and eslint does not scan the root and plugin test dirs.

## Goals

- Resolve the two incompatible-type comparisons (fix or dismiss with reason) with no regression in erasure/DSAR guards.
- Replace silent handlers in shipped plugin scripts with logged handling, without changing fail-closed behavior.
- Add deterministic, ratcheting linters for this repo (ruff; eslint over the unscanned test dirs).
- Give plugin `work`/`review` a detect-and-run step for a customer project's own linters.
- Decide, from measured rule overlap, whether per-PR Code Quality stays on; record its billing.

## Non-Goals

- Clearing all 169 findings; the ratchet absorbs the remainder (archived spec scratch, fixtures, trivial-conditional cleanups).
- Bundling ruff/eslint into the plugin or imposing rule sets on customer stacks.
- Changing redaction-proxy fail-closed behavior.

## Functional Requirements

- **FR1 (PR1):** Both comparison findings located (GitHub UI), each with a failing test or a documented dismissal reason; `gdpr-gate` run on the diff.
- **FR2 (PR2):** `playwright-mcp-redact-proxy.py`, `founder-check.py`, `resolve-debt.py`, `scan-ancestor-signal-helpers.py`: empty handlers gain logging; proxy test suite passes; fail-closed paths unchanged.
- **FR3 (PR3a):** ruff CI + lefthook step (`glob: "**/*.py"`) scoped to shipped Python, excluding `knowledge-base/**`; root eslint config covering `test/` and `plugins/soleur/test/`; ratchet keyed on `file:rule` plus content anchor, tool versions pinned.
- **FR4 (PR3b):** `work` and `review` detect the project's eslint/ruff config, run it on changed files only, report the changed-line delta, and emit "no linter configured" when none exists.
- **FR5 (PR4):** ADR-276 S5 amendment from a rule-by-rule overlap table of the 22 rules; `knowledge-base/operations/expenses.md` records Code Quality billing.

## Technical Requirements

- **TR1:** Ratchet pattern follows the existing count-down ratchets (`apps/web-platform/test/eslint-config.test.ts`, `scripts/lint-trap-tempfile-ownership.py --check-highwater`, `work/SKILL.md` baselined-lint drawdown).
- **TR2:** `cq-silent-fallback-must-mirror-to-sentry` applies to server-side handlers; plugin scripts log locally.
- **TR3:** Test fixtures stay synthetic (`cq-test-fixtures-synthesized-only`).
- **TR4:** Slice order PR1 → PR2 → PR3a → PR3b → PR4; PR3b depends on PR3a's design.
