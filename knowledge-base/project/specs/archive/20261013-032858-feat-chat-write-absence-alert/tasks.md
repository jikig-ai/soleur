---
feature: chat-write-absence-alert
issue: 4849
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-03-feat-chat-write-absence-liveness-alert-plan.md
---

# Tasks: Chat Write-Absence Liveness Alert (#4849)

## Phase 0 — Preconditions

- [ ] 0.1 Confirm `jianyuan/sentry` 0.15.0-beta2 supports `first_seen_event` /
  `reappeared_event` / `regression_event` + `tagged_event` `IS_IN` (proven by
  `byok_art_33_breach` + `byok_cap_exceeded:310`; spot-check only).
- [ ] 0.2 Choose the free `frequency` integer — `10` (taken: 5,15,30,60,61,62).
- [ ] 0.3 Read `apps/web-platform/scripts/sentry-monitors-audit.sh`; determine
  whether a new apply-created issue alert needs an audit-allowlist entry. Record
  the answer; edit ONLY if required.
- [ ] 0.4 Confirm the contract-test path matches the web-platform vitest
  `include:` glob (`apps/web-platform/vitest.config.ts` → `test/**/*.test.ts`);
  place under `apps/web-platform/test/`, not co-located.

## Phase 1 — Resource + RED contract test

- [ ] 1.1 Write `apps/web-platform/test/sentry-chat-alert-op-contract.test.ts`
  FIRST (RED): assert `"cc-dispatcher"` + the 3 op-slug literals
  (`tenant-mint.persistUserMessage`, `persistUserMessage.workspaceRead`,
  `persist-user-message`) appear in BOTH `issue-alerts.tf` AND `cc-dispatcher.ts`
  via plain whole-file substring match (no AST/const resolution — `persist-user-message`
  is found at the `CC_OP_SLUGS` def `:292`).
- [ ] 1.2 Add `resource "sentry_issue_alert" "chat_message_save_failure"` to
  `apps/web-platform/infra/sentry/issue-alerts.tf` (AC1: `action_match="any"`,
  `filter_match="all"`, `frequency=10`, conditions first_seen/reappeared/regression,
  filters feature EQUAL cc-dispatcher + op IS_IN the 3 slugs, notify_email
  IssueOwners→ActiveMembers, `lifecycle.ignore_changes=[environment]`). SHORT
  comment — only `action_match=any` recurrence rationale + N=1 recipient note.
  → contract test GREEN.

## Phase 2 — Wire apply + detector liveness

- [ ] 2.1 Add `-target=sentry_issue_alert.chat_message_save_failure` to the
  `Terraform plan (cron + uptime monitors)` step in
  `.github/workflows/apply-sentry-infra.yml` (~:213-214).
- [ ] 2.2 Add `chat-message-save-failure` to `EXPECTED_RULES` (`:49`) in
  `apps/web-platform/scripts/assert-byok-rules-exist.sh`; retitle the header to
  issue-alert detector liveness. Add the slug to the T1 positive fixture
  (`:40-46`) in `assert-byok-rules-exist.test.sh` (array-membership, NO count).

## Phase 3 — Docs

- [ ] 3.1 Add the new apply-created issue alert to the resource inventory in
  `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`.
- [ ] 3.2 PR body: one line noting the `-target` guard-sweep found no
  jq/scope-guard/counter edit needed (same `sentry_issue_alert` type). Use
  `Closes #4849`.

## Verification (pre-merge)

- [ ] V1 `vitest run apps/web-platform/test/sentry-chat-alert-op-contract.test.ts` green.
- [ ] V2 `assert-byok-rules-exist.test.sh` green (T1 includes the new slug).
- [ ] V3 `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` green (unchanged).
- [ ] V4 `grep` the `terraform plan` step region confirms the `-target` is present.

## Post-merge (operator-automatic)

- [ ] PM1 On merge, `apply-sentry-infra.yml` fires (path filter incl. issue-alerts.tf),
  destroy-guard passes (0 destroys), apply creates the rule, post-apply
  `assert-byok-rules-exist.sh` confirms `chat-message-save-failure` exists.
  Verify via run log + read-only Sentry `/rules/` GET (no SSH).
