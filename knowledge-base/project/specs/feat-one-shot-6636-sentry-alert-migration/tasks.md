# Tasks — fix: un-wedge the Sentry Terraform root (410 on sentry_issue_alert reads) (#6636)

lane: cross-domain
Plan: knowledge-base/project/plans/2026-07-17-fix-sentry-issue-alert-410-provider-bump-plan.md

> Decision-gated. Phase 0 MEASURES whether a provider bump clears the 410. Phase A (bump) is the recommended path; Phase B (migrate to sentry_alert) runs only if Phase 0 proves no stable version clears the read. Do NOT edit `.tf` until Phase 0 passes.

## Phase 0 — Measurement gate (decides A vs B)

- [ ] 0.1 Reproduce the break on beta2: `cd apps/web-platform/infra/sentry && terraform init -input=false && terraform plan` → capture one verbatim `410 "This API no longer exists"` line into the spec evidence file. (R2 creds from Doppler `prd_terraform`; Sentry token per README §Local invocation.)
- [ ] 0.2 Enumerate versions: `curl -s https://registry.terraform.io/v1/providers/jianyuan/sentry/versions | jq -r '.versions[].version' | tail -20`. Pick the lowest stable ≥ current that reworks the issue-alert read (do NOT trust the research's exact version — the registry is authoritative).
- [ ] 0.3 Bump + upgrade in a scratch copy: set `version = "<chosen>"` in versions.tf; `terraform init -upgrade`; regenerate lock via `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64`.
- [ ] 0.4 MEASURE: `terraform validate` (exit 0) then `terraform plan -no-color`. Record (a) 410 cleared? (b) full-root plan shape (0/0/0 across issue-alert + cron + uptime)?
- [ ] 0.5 Decision fork: cleared+no-op → Phase A; cleared+drift → Phase A + reconciliation; NOT cleared → Phase B (record the proof).
- [ ] 0.6 Baseline guard/tooling: `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` `[ok]`; `grep -c 'sentry_issue_alert\|sentry_alert' apps/web-platform/scripts/sentry-monitors-audit.{sh,test.sh}` → 0.

## Phase A — Provider bump (recommended)

- [ ] A.1 versions.tf: pin `<chosen stable>`; update header comment (resolved stable pin + #6636 410 rationale + sentry_alert deferral persists).
- [ ] A.2 Commit regenerated `.terraform.lock.hcl` (new version + full h1:/zh: hash set incl. linux_amd64 — CI uses `init -lockfile=readonly`).
- [ ] A.3 If Phase 0.5 found drift: reconcile per-resource `lifecycle.ignore_changes` / `_v2` attribute shape across all 23 (grep-driven sweep) until plan is no-op.
- [ ] A.4 README.md: "6 issue alerts" → 23; correct `de.sentry.io` API-host prose only if touched.
- [ ] A.5 Amend ADR-031 (Amendment 2026-07-17 #6636: bump; sentry_alert deferral RE-AFFIRMED; re-eval criterion updated).

## Phase B — Migrate to sentry_alert (fallback; only if Phase 0 proves no version clears the 410)

- [ ] B.0 Re-obtain CPO sign-off (high blast radius). Dump `terraform providers schema -json`; verify sentry_alert monitor_ids/project + that `sentry_project_error_monitor`/`sentry_project_issue_stream_monitor` data sources exist and let a project-wide frequency rule fire faithfully. If a pure-frequency rule (zot_mirror) can't be expressed → escalate to Option C.
- [ ] B.1 Translate all 23 → sentry_alert (lifecycle conds → trigger_conditions; frequency+filters → action_filters[].conditions; filter_match → logic_type; actions_v2+frequency → action_filters[].actions+frequency_minutes; monitor_ids → default/issue-stream monitor data source). Preserve every `name` byte-for-byte.
- [ ] B.2 `terraform state rm sentry_issue_alert.<each>` for all 23 (refresh-free; survives the 410; does NOT delete server-side). Do NOT use `removed {}` unless Phase 0 proves it doesn't refresh.
- [ ] B.3 `terraform import sentry_alert.<each> <import-id>` for all 23 (import-id format per B.0). Partial-failure → README §Import rollback.
- [ ] B.4 Execution vehicle: one-time `workflow_dispatch` job (state rm → import → plan no-op) with the apply job's Doppler R2 + SENTRY_IAC_AUTH_TOKEN plumbing, run BEFORE the merge.
- [ ] B.5 Extend destroy guard for sentry_alert BEFORE it enters the plan: `select(.type == "sentry_alert")` nested-clause in destroy-guard-filter-sentry.jq (action_filters[].conditions[]+actions[]+trigger_conditions[] shrink); allow in test-destroy-guard-sentry-scope-guard.sh; update counter test + fixture.
- [ ] B.6 Amend ADR-031 (sentry_alert adopted; monitor-binding + guard extension); update assert-byok-rules-exist.sh only if names change (must not).

## Phase 2 — Verification (both options)

- [ ] 2.1 `terraform validate` exit 0.
- [ ] 2.2 `terraform plan` full-root no-op (0/0/0), no 410, across all three types.
- [ ] 2.3 `terraform fmt -check` clean on every edited .tf.
- [ ] 2.4 `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` `[ok]`; `test-destroy-guard-counter-sentry.sh` pass; `test-sentry-full-root-apply.sh` pass.
- [ ] 2.5 PR `sentry-destroy-required` gate GREEN (self-verifying via committed lockfile).
- [ ] 2.6 Acceptance criteria AC1–AC8 checked (plan §Acceptance Criteria).
