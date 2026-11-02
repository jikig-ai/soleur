# Tasks: docs: a `lower_than` silence incident may stay open after the data returns

Plan: `knowledge-base/project/plans/2026-11-02-docs-lower-than-silence-incident-stays-open-note-plan.md`
Branch: feat-one-shot-silent-incident-docs-note | Refs: #11820, #11869 (never a closing keyword)

## Phase 1: Runbook entries

- [x] 1.1 Re-read `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` bullets for `egress_gw_probe_silent` and `inngest_cutover_flip_silent`.
- [x] 1.2 Insert the verbatim note on its own line in the `egress_gw_probe_silent` bullet (after "...cannot mask the other's silence.").
- [x] 1.3 Insert the verbatim note on its own line in the `inngest_cutover_flip_silent` bullet (after "...first row after boot).").

## Phase 2: Terraform comment (comment-only)

- [x] 2.1 Add the `INCIDENT LIFECYCLE` comment paragraph (note plus dated evidence lines) after the `WINDOW.` paragraph, before `locals {`, in `apps/web-platform/infra/betterstack-logs-alerts.tf`.
- [x] 2.2 Run the comment-only diff filter (prints nothing) and `terraform fmt -check`.
- [x] 2.3 Confirm the file-wide counts are unchanged from `origin/main`: `inngest_cutover_flip_silent_sql = <<-SQL`, `inngest_luks_key_probe_runbook_url =` and `EXPECTED during an owner-authorized inngest-host-replace` (each 1), plus `<<-SQL` and `resource "logtail_exploration_alert" ` (the comment must contain neither).

## Phase 3: Verification

- [x] 3.1 Run `inngest-cutover-flip-silent-alert.test.sh`, `inngest-luks-key-probe-alert.test.sh`, `egress-gw-alert.test.sh`, `logs-alert-query-period-ceiling.test.sh`, `betterstack-alert-structure.test.sh`, and the other alert suites that read the `.tf`.
- [x] 3.2 Run `bun test plugins/soleur/test/terraform-target-parity.test.ts`.
- [x] 3.3 Re-measure the data read-only with `scripts/betterstack-query.sh` before the PR body says "healthy". Measured 2026-11-02 ~16:00Z, `--since 1h --limit 500`: flip tag 11 object-typed rows in the hour (about one per 5 min plus transitions), egress tag 22 `egress-gw-probe` rows.
- 3.4 Read the PR `plan` job comment: no resource change.

## Phase 4: PR

- 4.1 PR body: `Ref #11820`, `Ref #11869`; evidence block; manual resolve test pending the owner's per-command go-ahead.
- 4.2 Do not resolve any incident, change any predicate, or pause any alert.
