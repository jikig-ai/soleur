---
title: "Tasks — fix(infra) journald-config stale agent=true assertion (#4864)"
date: 2026-06-03
issue: 4864
plan: knowledge-base/project/plans/2026-06-03-fix-journald-test-stale-agent-assertion-plan.md
lane: cross-domain
---

# Tasks — narrow stale `agent = true` assertion (#4864)

## Phase 1 — Baseline (RED capture)

- [x] 1.1 Run `bash apps/web-platform/infra/journald-config.test.sh`; confirm
  `32/33`, FAIL on "connection uses the operator SSH agent (agent = true)",
  exit `1`. Capture output.
- [x] 1.2 Run `bash apps/web-platform/infra/infra-config-handler-bootstrap.test.sh`;
  confirm `33/33` (the **false-pass** via the `server.tf:381` comment).
- [x] 1.3 Confirm the universe is exactly 2 files:
  `grep -rln "operator SSH agent (agent = true)" apps/web-platform/infra/*.test.sh`
  → exactly `journald-config.test.sh` + `infra-config-handler-bootstrap.test.sh`.

## Phase 2 — Narrow the journald assertion

- [x] 2.1 In `apps/web-platform/infra/journald-config.test.sh` (lines 114-115),
  change the condition regex `agent[[:space:]]*=[[:space:]]*true` →
  `agent[[:space:]]*=[[:space:]]*var\.ci_ssh_private_key[[:space:]]*==[[:space:]]*null`.
- [x] 2.2 Update the `assert "…"` description from "connection uses the
  operator SSH agent (agent = true)" to a dual-context description (e.g.
  "connection uses the dual-context ssh-agent toggle (agent = var… == null)").
  Keep the description free of intervening parens around the grep-target
  words (Sharp Edge: punctuation-split substring matches).
- [x] 2.3 Add a one-line comment: literal-`true` was stale post-#4845; the
  conditional regex cannot false-match the `#4829` dual-context comment.

## Phase 3 — Narrow the sibling (bootstrap) assertion

- [x] 3.1 Apply the identical regex narrowing to
  `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` lines 86-87.
- [x] 3.2 Apply the identical description + comment update.

## Phase 4 — GREEN verification (Pre-merge ACs)

- [x] 4.1 (AC2) `bash apps/web-platform/infra/journald-config.test.sh` →
  `33/33`, exit `0`.
- [x] 4.2 (AC5) `bash apps/web-platform/infra/infra-config-handler-bootstrap.test.sh`
  → `33/33`, exit `0` — now matching real config, not the comment.
- [x] 4.3 (AC6) Anti-false-pass proof: confirm the narrowed regex matches the
  real `agent = var…` config line in the bootstrap block and NOT the
  comment at `server.tf:381`:
  `awk '/^resource "terraform_data" "infra_config_handler_bootstrap"/{f=1} f{print} f&&/^}/{exit}' apps/web-platform/infra/server.tf | grep -cE 'agent[[:space:]]*=[[:space:]]*var\.ci_ssh_private_key'`
  ≥1, and the same awk `| grep -cE 'agent[[:space:]]*=[[:space:]]*true'`
  returns only the comment line.
- [x] 4.4 (AC3/AC4) `grep -c "operator SSH agent (agent = true)"` → `0` in
  both edited files.
- [x] 4.5 (AC7) `grep -rln "operator SSH agent (agent = true)" apps/web-platform/infra/*.test.sh`
  → 0 files.
- [x] 4.6 (AC8) `git diff --stat origin/main -- apps/web-platform/infra/server.tf`
  → empty (server.tf untouched).
- [x] 4.7 (AC9) Run every `deploy-script-tests` step locally:
  `grep -oE 'bash apps/web-platform/infra/[a-z0-9-]+\.test\.sh' .github/workflows/infra-validation.yml | sort -u`
  → run each → all exit `0`.

## Phase 5 — Ship

- [ ] 5.1 Commit (test-only), push, open PR. PR body: `Ref #4864` if any
  post-merge step remains, else `Closes #4864` (this fix is fully verified
  pre-merge — `Closes` is appropriate). Include `## Changelog` + `semver:patch`.
- [ ] 5.2 (AC10, post-merge/operator via `gh`) After merge, confirm
  `deploy-script-tests` green on `main`:
  `gh run list --workflow=infra-validation.yml --branch main --limit 1`
  → `gh run view <id>` → `success`. Folded into `/soleur:ship`.
