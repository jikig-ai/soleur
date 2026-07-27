---
title: Tasks — context-governance instrument fixes
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-27-chore-context-governance-instrument-fixes-plan.md
issue: 7008
pr: 7006
---

# Tasks

## Phase 0 — Baselines on `main` (blocking; must precede every edit)

- [x] 0.1 Capture the three per-class `$CONTEXT` body hashes (`tail -n +4 | sha256sum`) for
      docs-only, code/infra, and multi-class changesets. Record in the PR body.
- [x] 0.2 Capture `grep -c '^- \[id: ' AGENTS.md` (expect 101).
- [x] 0.3 Capture per-sidecar body counts: core 53, docs 6, rest 42.
- [x] 0.4 Capture retired-id count with the pinned command
      `grep -cE '^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]+[[:space:]]*\|' scripts/retired-rule-ids.txt`
      (expect 58 — pinning the command resolves the 58-vs-62 disagreement between reviewers,
      which came from counting ids inside breadcrumb prose).

## Phase 1 — Fix the instrument (FR1, FR2, TR1)

- [x] 1.1 RED: add the denominator test to `session-rules-loader.test.sh`. **Commit alone.**
      Confirm it fails reporting 202.
- [x] 1.2 Add the permanent anti-regression assertion: `grep -q 'AGENTS\*\.md'` on the loader
      must FAIL.
- [x] 1.3 GREEN: change `TOTAL_RULES=` to glob `AGENTS.{core,docs,rest}.md`.
- [x] 1.4 FR2: append the byte figure to `STAMP` using `printf '%s' "$CONTEXT" | wc -c`
      (bytes, not `${#CONTEXT}` chars).
- [x] 1.5 Assert the **worst-case composed** stamp (fail-safe + over-strip notes + byte
      figure) is ≤200 bytes via `wc -c`. Switch Test 11 from `awk length` to `wc -c`.

## Phase 2 — Rule/skill conflicts (FR7, FR8)

- [x] 2.1 FR7: correct all six sites to ack-then-`-auto-approve` —
      `ship/SKILL.md:821,856`; `admin-ip-refresh/SKILL.md:42`;
      `admin-ip-refresh/references/admin-ip-refresh-procedure.md:107,148`;
      `knowledge-base/engineering/operations/runbooks/admin-ip-drift.md:104,162,223`.
      For the Doppler-write site, drop the inapplicable `-auto-approve` reference (that
      command has no such flag) rather than inverting it.
- [x] 2.2 FR8: add the ~180 B precedence clause to `wg-when-an-audit-identifies-pre-existing`
      (`AGENTS.rest.md:21`). Do NOT touch `AGENTS.core.md`.
- [x] 2.3 Re-run `lint-agents-rule-budget.py … 2>&1`; confirm `[WARN]`, exit 0, and
      `B_ALWAYS` still exactly 22,900.

## Phase 3 — `hr-`/`wg-` prefix class (FR6)

- [x] 3.1 `article-30-register.md:417` → `wg-block-pr-ready-on-undeferred-operator-steps`.
- [x] 3.2 `worktree-manager.sh:817` → `wg-cla-signed-author-before-merge`.
- [x] 3.3 Verify both corrected ids resolve in `AGENTS.md`.

## Phase 4 — Orphaned citations (FR9)

- [x] 4.1 `ship/SKILL.md:770` — drop the dead `cq-when-a-plan-prescribes-a-validator-guard-or`
      citation, keep the sentence (inline the rationale).
- [x] 4.2 `.claude/hooks/durable-reminder-prefer-inngest.sh:6` — drop
      `hr-durable-reminders-use-inngest-primitive` (it even claims "AGENTS.core.md"); inline.
- [x] 4.3 `scripts/betterstack-query.sh:52` — drop
      `hr-observability-probe-transient-is-not-no-access`; inline.
- [x] 4.4 `scripts/rule-prune.sh:17` — drop `hr-rule-retirement-guard`; inline.
- [x] 4.5 **Do NOT touch** `plan/SKILL.md:968`, `deepen-plan/SKILL.md:775`, or any of the six
      `cq-pencil-collapse-auto-recover` sites. Verify with `git diff --stat`.

## Phase 5 — Sibling doubled glob (FR11)

- [x] 5.1 `compound/SKILL.md:257-258` — fix the `AGENTS*.md` glob so it reports 101.

## Phase 6 — Verify

- [x] 6.1 All ACs AC1–AC3, AC6–AC8, AC10–AC14 green (see plan).
- [x] 6.2 `bash .claude/hooks/session-rules-loader.test.sh` — all PASS.
- [x] 6.3 `python3 scripts/lint-rule-ids.py` exits 0.
- [x] 6.4 AC6: re-derive the three per-class hashes; match Phase 0 pairwise.
- [x] 6.5 AC12: counts identical to Phase 0 (101 / 53-6-42 / 58).
