---
title: hr-rule retirement guard
feature: feat-hr-rule-retirement-guard
issue: 2871
brainstorm: knowledge-base/project/brainstorms/2026-04-24-hr-rule-retirement-guard-brainstorm.md
status: ready-for-plan
---

# hr-rule retirement guard — spec

## Problem Statement

`scripts/retired-rule-ids.txt` is an append-only allowlist that enables intentional removal of AGENTS.md rules. Combined with the immutability contract enforced by `cq-rule-ids-are-immutable` + `scripts/lint-rule-ids.py` (retired ids cannot be reused as active rule ids), adding an id to the allowlist is a **one-way door**. A future PR could retire a security-critical hard-rule (prefix `hr-`) with a plausible-looking breadcrumb, reviewer approves, and the rule becomes permanently unrecoverable under its original id. Surfaced by security-sentinel review of PR #2862 as MEDIUM / CWE-284 (Improper Access Control). No `hr-*` is currently retired — this is future-risk hardening.

## Goals

1. Prevent accidental or low-scrutiny retirement of any `hr-*` rule by making the retirement visible in the PR diff via a linter-level block.
2. Preserve the ability to legitimately retire an `hr-*` rule when truly warranted, at the cost of a visible code change to the enforcement script itself.
3. Keep the surface self-contained: no new files, no new hooks, no new CI jobs.

## Non-Goals

- **CODEOWNERS protection.** Defer until a second governance surface justifies it.
- **Commit-trailer enforcement (`Retires-HR-Rule:`).** Developer-discipline layer; weaker than hard-block.
- **Signed manifest with per-id approval.** Overhead not justified by threat model.
- **Extending the block to `wg-*`, `cq-*`, `rf-*`, `pdr-*`, `cm-*`.** Those prefixes do not carry the same blast-radius as hard-rules.
- **Backfilling hr-* retroactive remediation.** Zero `hr-*` are currently retired; the gate fix IS the remediation.

## Functional Requirements

- **FR1.** `scripts/lint-rule-ids.py` MUST exit non-zero with a diagnostic message if any line parsed from `scripts/retired-rule-ids.txt` has an id matching `^hr-`.
- **FR2.** The diagnostic message MUST include (a) the offending id(s), (b) a pointer to the pointer-preservation migration pattern (PR #2754 / learning `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`), and (c) an explicit note that editing `lint-rule-ids.py` is the only legitimate path to retire an `hr-*` rule.
- **FR3.** The block MUST fire before the existing reintroduction and removed-id diff checks, so that a developer seeing the hr-* block does not also see downstream noise from the same file.
- **FR4.** AGENTS.md rule `cq-rule-ids-are-immutable` MUST gain a concise note that hr-* retirement is linter-blocked. The rule must remain under the 600-byte per-rule cap.
- **FR5.** The pointer-preservation learning file MUST gain a short "hr-* caveat" section documenting the new constraint.
- **FR6.** A unit test in `tests/scripts/test_lint_rule_ids.py` (or equivalent pytest path per repo convention) MUST assert that a synthetic `retired-rule-ids.txt` fixture containing `hr-some-id | 2026-04-24 | #X | test` causes `lint()` (or the top-level `main()`) to return non-zero. A second test MUST assert that a fixture with no `hr-*` ids passes.

## Technical Requirements

- **TR1.** The block lives inside `scripts/lint-rule-ids.py` (not in a new module). The simplest implementation is a check in `load_retired_ids()` or `main()` after the file is parsed but before the set is returned to `lint()`.
- **TR2.** The block uses the canonical `^hr-` prefix check — no regex alternation with other prefixes, no config flag to disable.
- **TR3.** The error message is plain-text to stderr, exit code 2 (distinguishable from the lint-failure exit code 1 — this is a usage/policy error, not a content error). Reconsider during plan if exit-code collision with existing script behavior.
- **TR4.** No changes to `scripts/retired-rule-ids.txt` format. Existing format (`<id> | <date> | <pr> | <breadcrumb>`) is preserved.
- **TR5.** No changes to `lefthook.yml`. The existing pre-commit hook that invokes `lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md` already covers the new check.
- **TR6.** If `scripts/rule-prune.sh` has a parallel code path that loads retired ids, it MUST either share the block or be explicitly scoped out (its behavior differs — it regulates active-rule pruning, not retirement — so block is likely not needed there; confirm during plan).

## Acceptance Criteria

- [ ] FR1–FR6 satisfied and proven by the new unit tests.
- [ ] `lefthook run pre-commit` (or direct `python scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md`) passes on the current retired-rule-ids.txt (no `hr-*` present).
- [ ] A deliberate temporary addition of `hr-test-fake | 2026-04-24 | - | test` to `retired-rule-ids.txt` causes the linter to fail with a clear message pointing to pointer-preservation. (Revert before commit.)
- [ ] AGENTS.md `cq-rule-ids-are-immutable` rule updated; `scripts/lint-rule-ids.py` passes on the updated AGENTS.md.
- [ ] Learning file updated with hr-* caveat section.
- [ ] Issue #2871 closed via `Closes #2871` in PR body.

## Test Scenarios

| Scenario | Input | Expected |
|---|---|---|
| Happy path — no hr-* | `cq-foo-bar \| ...` | exit 0 |
| Block fires — single hr-* | `hr-some-rule \| ...` | exit non-zero, message names `hr-some-rule`, points to pointer-preservation |
| Block fires — multiple hr-* | Two `hr-*` lines | exit non-zero, message lists both |
| Block fires with other errors | `hr-some-rule` + reintroduction | hr-* block fires first (FR3) |
| Comment-only lines ignored | `# hr-fake-commented-out` | exit 0 (comment parser skip path already handles this — re-verify) |
| Empty retired file | Only header comments | exit 0 |

## References

- Issue #2871 — parent tracking issue
- PR #2862 — shipped the retired-ids allowlist (security-sentinel finding #4 origin)
- PR #2754, Issue #2686 — earlier pointer-preservation migration pattern
- `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` — pattern documentation
- AGENTS.md `cq-rule-ids-are-immutable` — the immutability contract to extend
- `scripts/lint-rule-ids.py` — enforcement script to modify
- `scripts/retired-rule-ids.txt` — protected surface
