---
title: "tasks: ops(ci): audit CodeQL coverage of bot PRs (#3545)"
date: 2026-05-11
plan: knowledge-base/project/plans/2026-05-11-ops-audit-codeql-coverage-bot-prs-plan.md
issue: 3545
---

# Tasks — ops(ci): audit CodeQL coverage of bot PRs

## Phase 1 — Audit script

- [ ] 1.1. Author `scripts/audit-bot-codeql-coverage.sh` skeleton: shebang, `set -euo pipefail`, `--help`/`--limit`/`--workflows`/`--json`/`--dry-run` arg parsing.
- [ ] 1.2. Implement dynamic bot-workflow enumeration (union of composite-action + scheduled-inline-pattern). Save to `/tmp/bot-workflows.txt`. Assert `wc -l >= 8`.
- [ ] 1.3. Implement per-workflow PR enumeration via `gh pr list --state all --json ...`.
- [ ] 1.4. Implement check-runs fetch via `gh api repos/<repo>/commits/<sha>/check-runs?per_page=100`. Filter for `name == "CodeQL"` && `app.id == 57789`.
- [ ] 1.5. Drift classification: missing | failure | cancelled | timed_out | action_required → drift. success | neutral | skipped → pass.
- [ ] 1.6. Atomic state-file write to `~/.local/state/soleur/codeql-bot-coverage-<timestamp>.json` (`mktemp` + `mv`). Skip on `--dry-run`.
- [ ] 1.7. Human output to stderr (per-PR table); structured envelope to stdout (`--json` only).
- [ ] 1.8. Add 60-second `timeout` wrapper on every `gh api` call.
- [ ] 1.9. CR/LF strip on any GitHub-Annotation echo (per Sharp Edges).

## Phase 1.5 — Audit fixtures + regression test

- [ ] 1.10. Create `scripts/fixtures/audit-bot-codeql-coverage/` directory with synthesized JSON fixtures (no real PR numbers).
- [ ] 1.11. Fixture A: missing-CodeQL — check-runs JSON without `CodeQL` entry.
- [ ] 1.12. Fixture B: failed-CodeQL — check-runs JSON with `CodeQL.conclusion == "failure"`.
- [ ] 1.13. Fixture C: passing — check-runs JSON with `CodeQL.conclusion == "neutral"`.
- [ ] 1.14. Add a small `scripts/test-audit-bot-codeql-coverage.sh` harness that runs the script against each fixture via a `--fixture` flag and asserts exit code + drift entry.

## Phase 2 — Runbook + reconciliation

- [ ] 2.1. Author `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md` with sections: Trigger / What this runbook is / The as-built behavior / When to run / Step-by-step / Drift triage / Rollback-escalation / Cross-refs.
- [ ] 2.2. Cross-link from `skill-security-scan-required-check.md` §Smoke test.
- [ ] 2.3. Append row to `knowledge-base/legal/compliance-posture.md` under #2719: `#3545 R15 D2 audit completed YYYY-MM-DD`.

## Phase 3 — Conditional (only fires if Phase 1 detects drift)

- [ ] 3.1. (only if drift) Sub-classify: missing entirely vs. ran-but-failed.
- [ ] 3.2. (only if missing) File `compliance/critical` issue, transcript audit output, defer admin-UI edit to operator per `hr-menu-option-ack-not-prod-write-auth`.
- [ ] 3.3. (only if failed) File `type/security` issue with alert details, route to `/soleur:fix-issue`.

## Phase 4 — PR hygiene

- [ ] 4.1. Run `bun test scripts/test-audit-bot-codeql-coverage.sh` (or shell harness equivalent) — all fixtures pass.
- [ ] 4.2. Run `bash scripts/audit-bot-codeql-coverage.sh --limit 5` against live state — exits 0.
- [ ] 4.3. PR body uses `Ref #3545`, NOT `Closes #3545` (ops-only-read, post-merge audit step).
- [ ] 4.4. Verification greps from plan §Verification all return expected hits.
- [ ] 4.5. `/soleur:compound` before commit.

## Post-merge (operator)

- [ ] P.1. Run `bash scripts/audit-bot-codeql-coverage.sh --json | jq '.summary'` against `main`. Paste into #3545.
- [ ] P.2. `gh issue close 3545 --comment "Audit healthy. Envelope: <...>. Runbook: knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md"`.
- [ ] P.3. Update `compliance-posture.md` from `audit pending` → `audit completed YYYY-MM-DD`.
