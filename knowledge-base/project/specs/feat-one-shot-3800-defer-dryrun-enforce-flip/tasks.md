---
title: "Tasks — F2 enforce-flip (SOLEUR_DEFER_DRYRUN 1 → 0)"
issue: 3800
lane: single-domain
plan: knowledge-base/project/plans/2026-06-02-feat-defer-dryrun-enforce-flip-plan.md
---

# Tasks — F2 enforce-flip

> Derived from `2026-06-02-feat-defer-dryrun-enforce-flip-plan.md`. RED-first: pin the new default behavior before flipping it.

## Phase 1 — RED: pin the default-unset behavior

- [ ] 1.1 Add Tier-D case `D4 default-unset enforce` to `.claude/hooks/prod-write-defer-gate.test.sh`: run the hook for `terraform apply` with `SOLEUR_DEFER_DRYRUN` **unset**; assert `permissionDecision=defer`, `hookEventName=PreToolUse`, `kind=defer_requested`.
- [ ] 1.2 Run `bash .claude/hooks/prod-write-defer-gate.test.sh` — confirm D4 FAILS against the current `:-1` default (emits `would_defer`/allow). (RED.)

## Phase 2 — GREEN: the flip + comment

- [ ] 2.1 `.claude/hooks/prod-write-defer-gate.sh:35` — change `${SOLEUR_DEFER_DRYRUN:-1}` → `${SOLEUR_DEFER_DRYRUN:-0}`.
- [ ] 2.2 `.claude/hooks/prod-write-defer-gate.sh:15` — comment `default 1` → `default 0`.
- [ ] 2.3 Re-run `bash .claude/hooks/prod-write-defer-gate.test.sh` → `FAIL=0` (all green incl. D4). (GREEN.) [AC1, AC2, AC3, AC4]

## Phase 3 — consumer-side edits (CI + docs)

- [ ] 3.1 `.github/workflows/test-pretooluse-hooks.yml` — add `env: SOLEUR_DEFER_DRYRUN: "1"` to the Test-6 claude-code-action step (pins dry-run so it still emits `would_defer`); update the `:130` prose to "dry-run pinned for this test; the hardcoded default is now 0 (enforce)". Keep the `:186` `would_defer` assertion. [AC5]
- [ ] 3.2 Run `actionlint .github/workflows/test-pretooluse-hooks.yml` (workflow file — NOT a composite action; actionlint is correct here). [AC5]
- [ ] 3.3 `.claude/hooks/README.md` — Modes section (`:248–252`): mark `SOLEUR_DEFER_DRYRUN=0` as the new DEFAULT; rewrite `:322–323` enforce-flip note to past tense crediting PR #3800. [AC6]

## Phase 4 — verify + ship

- [ ] 4.1 Run AC1–AC6 verify commands; capture output:
  - `grep -n ':-0}' .claude/hooks/prod-write-defer-gate.sh` (line 35)
  - `grep -c ':-1}' .claude/hooks/prod-write-defer-gate.sh` (= 0)
  - `bash .claude/hooks/prod-write-defer-gate.test.sh` (FAIL=0)
  - `grep -n 'SOLEUR_DEFER_DRYRUN' .github/workflows/test-pretooluse-hooks.yml` (env pin present)
- [ ] 4.2 File the heredoc-body false-positive follow-up issue (label `type/chore`, `domain/engineering`, milestone Phase 4) per plan §Deferred — verify labels exist via `gh label list --limit 200 | grep -E '^(type/chore|domain/engineering)\b'` first.
- [ ] 4.3 Ship per `/soleur:ship`. PR body uses `Closes #3800` (NOT in title). Body notes parent #3789 stays OPEN. Body links the follow-up issue from 4.2. [AC7]
- [ ] 4.4 Post-merge (operator): on next gated prod-write, confirm session pauses + `claude --resume <id>` works + `tail -1 .claude/logs/approvals.jsonl | jq .` shows the row. [AC8]
