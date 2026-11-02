# Tasks — feat-one-shot-11372-logtail-alert-422

Plan: `knowledge-base/project/plans/2026-10-28-fix-logtail-key-probe-alert-422-plan.md`
Issue: #11372 (PR body: `Ref #11372`, never `Closes` — remediation verifies post-merge)

## Phase 1 — Terraform resource edit

- [x] 1.1 In `apps/web-platform/infra/betterstack-logs-alerts.tf`, resource `logtail_exploration_alert.inngest_luks_key_probe_fail` (~line 382): change `query_period = 10800` to `query_period = 5400`. Leave `check_period = 300`, `recovery_period = 3600`, `confirmation_period = 0`, `on_missing_data`, `paused`, `email`, `push`, the SQL local, and the `escalation_target` block untouched.
- [x] 1.2 Rewrite the window-rationale comment above the resource: state the 1.5 h window, the hourly re-probe + ~30 min slack reasoning (mirroring the sibling's), the ~1.5–2.5 h incident-clear time, and the #11372 422 cause. Add the `#11372` reference per the file's issue-tag convention.

## Phase 2 — Guard pin sync (same diff; a .tf edit without this is immediate CI red)

- [x] 2.1 `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` ~line 175–177: update the `param "$FAIL_AL" query_period` pin from `10800` to `5400`, and update the `[ok]`/`[FAIL]` strings to `check 300 s, query 5400 s (1.5 h), recovery 3600 s`.
- [x] 2.2 Same file ~line 308–309: update the mutation-row edit anchor literal `"query_period        = 10800"` → `"query_period        = 5400"` (keep the `"90000"` replacement and the "25 h" label).
- [x] 2.3 Run `bash apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` — expect all `[ok]` rows and every mutation row RED-by-design; verify exit 0.

## Phase 3 — Doc sync

- [x] 3.1 `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` ~line 63–64: "evaluated every 300 s over a 10800 s window" → 5400 s window.
- [x] 3.2 `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` "Key-continuity probe (#9927 item 2)" section (~line 630): replace the "3 h window … 3 to 4 hours" clear-time description with the 1.5 h window and ~1.5–2.5 h clear time. Do NOT touch the `### Key-continuity probe (#9927 item 2)` heading — the drift guard pins it verbatim via `grep -qxF`.

## Phase 4 — Verification

- [x] 4.1 AC-2 check: confirm `inngest_luks_key_probe_fail_sql` is byte-identical to its pre-change form (`git diff` on the SQL heredoc shows no change).
- [x] 4.2 AC-6 check: `git diff --quiet origin/main...HEAD -- apps/web-platform/infra/server.tf` exits 0.
- [x] 4.3 `terraform validate`-class check if available locally; otherwise rely on the guard suite + CI (`infra-validation.yml`).
- [ ] 4.4 Post-merge (AC-4): confirm the next `apply-web-platform-infra.yml` run's `terraform apply` step exits 0 and the alert exists in Better Stack. If it still 422s, follow the contingency ladder (check_period 900 → 3600) under the same pin-update discipline, recorded in `decision-challenges.md` first.

## Out of scope

- `server.tf` `ignore_changes` and vector allow-set (#6027 cutover owns those).
- The dead-man/absence alert (#11266, D12-pinned split).
- Any SQL rewrite (SQL RULES are pinned by the guard).
