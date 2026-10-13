---
title: "Tasks: observability heartbeat fix + plan-skill observability gate"
plan: knowledge-base/project/plans/2026-05-20-feat-observability-heartbeat-and-plan-gate-plan.md
lane: cross-domain
date: 2026-05-20
issue: 4116
---

# Tasks — feat-one-shot-observability-heartbeat-4116

Derived from the deepened plan. Hierarchical numbering; phases match the plan's Implementation Phases.

## 0. Preconditions

- 0.1 Verify `apps/web-platform/infra/inngest-bootstrap.sh` HEARTBEAT_UNIT block shape at ~lines 165-181 (anchor: substring `HEARTBEAT_UNIT`).
- 0.2 Run `python3 scripts/lint-agents-rule-budget.py` and capture baseline (expected: REJECT, B_ALWAYS=24499 > 22000).
- 0.3 `gh issue list --label code-review --state open --limit 200 > /tmp/open-review-issues.json` then per-file scan with standalone `jq --arg path '<file>'` (NOT `gh --jq` per `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`).
- 0.4 SSH-read-only diagnose doppler path on prod: `ssh deploy@<host> 'command -v doppler && readlink -f /usr/bin/doppler 2>/dev/null || echo "no-symlink"'`. Record result.

## 1. Heartbeat fix (RED → GREEN)

- 1.1 Add `test_heartbeat_unit_uses_doppler_run` to `apps/web-platform/infra/inngest.test.sh` — assert generated HEARTBEAT_UNIT contains `doppler run --project soleur --config prd`.
- 1.2 Add `test_heartbeat_unit_execstart_shape` — assert exactly one `ExecStart=` line and it begins with the doppler binary path.
- 1.3 Run `bash apps/web-platform/infra/inngest.test.sh` — confirm new tests FAIL against current bootstrap (RED).
- 1.4 Edit `apps/web-platform/infra/inngest-bootstrap.sh`:
  - 1.4.1 Insert `DOPPLER_BIN=$(command -v doppler 2>/dev/null || true)` + emptiness guard before HEARTBEAT_UNIT cat.
  - 1.4.2 Replace `ExecStart=${HEARTBEAT_SCRIPT}` with `ExecStart=${DOPPLER_BIN} run --project soleur --config prd -- ${HEARTBEAT_SCRIPT}`.
  - 1.4.3 Update header comments at lines ~159-164 to reflect the new ExecStart shape.
- 1.5 Re-run `bash apps/web-platform/infra/inngest.test.sh`; tests GREEN.

## 2. Discoverability_test wiring (`cat-deploy-state.sh`)

- 2.1 Extend `apps/web-platform/infra/cat-deploy-state.sh` JSON output with `services.inngest_heartbeat` field derived from `systemctl is-active inngest-heartbeat.service`.
- 2.2 Add or extend test (`cat-deploy-state.test.sh` if present) to assert the new field shape.

## 3. Plan-skill gate

- 3.1 Insert `### 2.9. Observability Quality Gate` in `plugins/soleur/skills/plan/SKILL.md` after Phase 2.8 (mirror Phase 2.8 structure: detection regex / required output block).
- 3.2 Insert `## Observability` block with the 5-field schema into all three detail levels (MINIMAL, MORE, A-LOT) of `plugins/soleur/skills/plan/references/plan-issue-templates.md`, placed between `## User-Brand Impact` and `## Acceptance Criteria`.
- 3.3 Insert `### 4.7. Observability Gate Verification` in `plugins/soleur/skills/deepen-plan/SKILL.md` symmetric to Phase 4.6 (halt condition: missing section OR TODO/TBD/placeholder/manual/ssh in required fields; distinguish field-value-equals-TBD from fallback-note-containing-TBD).
- 3.4 Add a deepen-plan fixture (or extend existing test harness) asserting halt on `ssh root@`/`TODO`/`TBD` field values.

## 4. AGENTS.md budget restoration (BLOCKING for 5)

- 4.0.1 Trim `hr-tagged-build-workflow-needs-initial-tag-push` (AGENTS.core.md:15) by extracting `**Why:** PR-F #3940 …` long body to existing or new sibling learning; leave one-line pointer. Target ≤ 600 bytes.
- 4.0.2 Trim `wg-after-marking-a-pr-ready-run-gh-pr-merge` (AGENTS.core.md:55) by similar extraction. Target ≤ 600 bytes.
- 4.0.3 Trim one more small candidate (e.g., line 49 `wg-end-of-work-emit-resume-prompt`) by ~150-200 bytes to recover remaining cumulative headroom.
- 4.0.4 Run `python3 scripts/lint-agents-rule-budget.py` → exit 0 GREEN before proceeding.

## 5. AGENTS.md new rule

- 5.1 Add the trimmed 487-byte `hr-observability-as-plan-quality-gate` rule under `## Hard Rules` in `AGENTS.core.md`.
- 5.2 Add the pointer `[id: hr-observability-as-plan-quality-gate] → core` in `AGENTS.md` index.
- 5.3 Re-run both lints: `python3 scripts/lint-rule-ids.py` AND `python3 scripts/lint-agents-rule-budget.py`. Both exit 0.
- 5.4 Cite the loader-class-fit `sed -n '88,126p' .claude/hooks/session-rules-loader.sh` output in the commit message.

## 6. Backfill TR9 specs

- 6.1 Append `## Observability` block to `knowledge-base/project/specs/feat-cron-follow-through-monitor-tr9/spec.md`.
- 6.2 Append `## Observability` block to `knowledge-base/project/specs/feat-agent-loop-crons-inngest-tr9/spec.md`.

## 7. Learning

- 7.1 Write `knowledge-base/project/learnings/bug-fixes/<topic>.md` documenting the env-injection-via-EnvironmentFile bug class (filename date chosen at write-time per AGENTS.md guidance — do not prescribe dated filename here).

## 8. Pre-merge gates

- 8.1 `/soleur:qa` — local `bash apps/web-platform/infra/inngest.test.sh` GREEN.
- 8.2 `/soleur:preflight` — Check 6 (User-Brand Impact threshold = `aggregate pattern`).
- 8.3 `/soleur:review` — multi-agent (architecture-strategist, Kieran for AGENTS.md placement + budget arithmetic, pattern-recognition for sibling /usr/bin/doppler latent risk).

## 9. Ship

- 9.1 `/soleur:ship` Phase 7 — push `vinngest-vX.Y.Z` tag → OCI build → deploy webhook → `services.inngest_heartbeat` verification via deploy-status.
- 9.2 Operator-driven: unpause `betteruptime_heartbeat.inngest_prd` via Better Stack UI; verify green within 60s.
- 9.3 `gh issue close 4116 --comment "Resolved via PR #<N>. Heartbeat green at <timestamp>."`
