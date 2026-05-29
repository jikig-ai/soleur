# Tasks — Migrate `sentry_issue_alert` → `sentry_alert` (#4610)

> Source of truth: `knowledge-base/project/plans/2026-05-29-refactor-sentry-issue-alert-to-sentry-alert-migration-plan.md`
> Lane: cross-domain (spec.md absent — defaulted per TR2 fail-closed).
> **GATE: requires CPO sign-off (single-user-incident threshold) AND user
> decision on Option A vs C BEFORE any /work edit. The recommended outcome is
> documentation-only — confirm before proceeding.**

## Phase 0 — Preconditions (read-only, before any edit)

- [ ] 0.1 Confirm provider pin unchanged: `grep -A2 jianyuan/sentry apps/web-platform/infra/sentry/.terraform.lock.hcl` shows `0.15.0-beta2`. If advanced, re-run the schema dump and re-validate every attribute claim in the plan.
- [ ] 0.2 Reproduce the warning: `cd apps/web-platform/infra/sentry && terraform init -backend=false && terraform validate` → 4 deprecation warnings + exit 0.
- [ ] 0.3 Re-dump schema and confirm `sentry_alert.monitor_ids.required == true` AND `sentry_alert.trigger_conditions.required == true` AND `sentry_alert` has no `project` attribute (the three blockers).
- [ ] 0.4 Warning-suppression feasibility probe: confirm the deprecation warning is NOT suppressible while the resource type stays `sentry_issue_alert` (`-compact-warnings` only collapses; no provider opt-out attribute; TF core 1.10.5 has no warning allow-list). Expected: NOT suppressible → Option A degrades to documented-warning (= Option C content, resources stay in code).
- [ ] 0.5 **STOP for user/CPO decision:** present the mutually-exclusive halves of claim (4). Get explicit choice: Option A (documented-warning, ship) vs Option C (defer + tracking note on #4610). Do NOT proceed to Phase 1 without it.

## Phase 1 — Documentation (Option A; skip to Phase 2 verify-only if Option C)

- [ ] 1.1 Edit `apps/web-platform/infra/sentry/issue-alerts.tf` header: add an accepted-warning block citing the schema incompatibility (`monitor_ids`/`trigger_conditions` required, no `project`), ADR-031's existing defer, this plan, and the GA re-evaluation issue.
- [ ] 1.2 (Optional) Add 1-line amendment to `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`: `Amendment (2026-05-29, #4610): re-confirmed at beta2 — sentry_alert requires monitor_ids/trigger_conditions; migration stays deferred to GA.`
- [ ] 1.3 Edit `apps/web-platform/infra/sentry/README.md` ONLY if a grep shows it claims a pending migration needing the beta-blocker note (currently it does not reference `sentry_alert`).

## Phase 2 — Verification (read-only; no prod write)

- [ ] 2.1 `terraform validate` exits 0 (warning present + documented).
- [ ] 2.2 `terraform fmt -check` clean on every edited `.tf`.
- [ ] 2.3 `git grep -c 'sentry_issue_alert\|sentry_alert' apps/web-platform/scripts/sentry-monitors-audit.sh apps/web-platform/scripts/sentry-monitors-audit.test.sh` → 0 (claim 3 no-op).
- [ ] 2.4 `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` → `[ok]`.
- [ ] 2.5 `git diff --stat` shows no `*.tfstate` change; no new prod-state-mutation token (import/state mv/apply) in any committed file.

## Phase 3 — PR

- [ ] 3.1 PR body: `Ref #4610` (not `Closes`) until the user confirms the resolution path. If Option A documented-warning is the accepted resolution → `Closes #4610`; if Option C → keep open with GA re-evaluation note.
- [ ] 3.2 No post-merge operator step (no apply/import/state mv).

## Explicitly NOT done
- No rewrite to `sentry_alert` (blocked — required monitor_ids/trigger_conditions).
- No cross-type state rename (impossible — disjoint schemas).
- No `apply-sentry-infra.yml` `-target=` allow-list change.
- No `destroy-guard-filter-sentry.jq` change.
