---
title: "Tasks: Ruleset bypass audit token-scope fix (#3569)"
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-13-fix-ruleset-bypass-audit-token-scope-plan.md
issues: [3569, 3544, 3542, 2719]
last_updated: 2026-05-13
---

# Tasks — Ruleset bypass audit token-scope fix (#3569)

Derived from `knowledge-base/project/plans/2026-05-13-fix-ruleset-bypass-audit-token-scope-plan.md`.

## Phase 0 — Decision gate (App reuse vs new App)

- 0.1 Operator probes installation permissions:
  `gh api /orgs/jikig-ai/installations --jq '.installations[] | {id, app_slug, permissions}'`.
- 0.2 Decide: reuse drift-guard App OR provision new
  `soleur-audit-readonly` App with `Repository.Administration: Read`
  + `Repository.Metadata: Read` only.
- 0.3 Record decision in PR body; if new App, add 3 repo secrets:
  `GH_APP_RULESET_AUDIT_APP_ID`, `GH_APP_RULESET_AUDIT_PRIVATE_KEY_B64`,
  `GH_APP_RULESET_AUDIT_INSTALLATION_ID`.

## Phase 1 — Test scaffolding (RED)

- 1.1 Add `t_token_scope_insufficient` test case to
  `tests/scripts/test-audit-ruleset-bypass.sh`.
- 1.2 Add `_run_with_scope_probe` helper (sets
  `AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE=enabled`).
- 1.3 Verify T12 (existing) still passes (scope probe OFF path).
- 1.4 Run tests; confirm new test FAILS (RED), all 18+ existing tests PASS.

## Phase 2 — Audit script (GREEN)

- 2.1 Edit `scripts/audit-ruleset-bypass.sh`: add
  `token_scope_insufficient` branch after live-fetch HTTP 200 check,
  gated by `.id == 14145388 AND .enforcement == "active"` sentinel.
- 2.2 Run tests; confirm new test PASSES, all existing tests PASS.

## Phase 3 — Workflow auth swap

- 3.1 Edit `.github/workflows/scheduled-ruleset-bypass-audit.yml`:
  add `mint-app-jwt` step (port from drift-guard lines 119-150).
- 3.2 Add `mint-install-token` step (POST to
  `/app/installations/{id}/access_tokens` with scope-down body
  `{"repository_ids":[<id>],"permissions":{"administration":"read","metadata":"read"}}`).
- 3.3 Replace `id: check` step's `GH_TOKEN: ${{ github.token }}` with
  `GH_TOKEN: ${{ steps.mint-install-token.outputs.install_token }}`.
- 3.4 Verify `permissions:` block UNCHANGED (no `administration:` line).
- 3.5 Add header comment block citing
  `2026-05-05-workflow-jwt-mint-silent-failure-traps.md` trap dossier.

## Phase 4 — Runbook fix

- 4.1 Edit
  `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`
  line 105 row: replace "ruleset deleted entirely" + destructive
  restore with both-interpretations + probe-first remediation.
- 4.2 Add `token_scope_insufficient` row to failure-modes table
  (line 38-53 region).
- 4.3 Add new triage subsection
  "### Drift = `token_scope_insufficient`" with App
  permission-restore procedure.
- 4.4 Update YAML `last_updated: 2026-05-13`.

## Phase 5 — Pre-merge verification

- 5.1 `gh workflow run scheduled-ruleset-bypass-audit.yml --ref feat-one-shot-3569`.
- 5.2 Confirm `conclusion: success` AND log emits
  `Ruleset bypass audit passed.` (script line 292).
- 5.3 Confirm `failure_mode` line in `$GITHUB_OUTPUT` is empty.

## Post-merge (operator)

- POST.1 Wait for next 06:13 UTC daily run; verify #3569 auto-closes.
- POST.2 Before auto-close, `gh issue comment 3569` with diagnosis + PR link.
- POST.3 If 30h passes without auto-close,
  `gh workflow run scheduled-ruleset-bypass-audit.yml` manually.
