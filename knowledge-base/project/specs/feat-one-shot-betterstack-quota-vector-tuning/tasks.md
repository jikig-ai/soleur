---
feature: feat-one-shot-betterstack-quota-vector-tuning
plan: knowledge-base/project/plans/2026-06-10-fix-betterstack-quota-vector-host-metrics-tuning-plan.md
lane: cross-domain
status: pending
created: 2026-06-10
---

# Tasks — Better Stack quota fix via Vector host-metrics tuning

> Lane defaulted to `cross-domain` (no spec.md with `lane:` exists for this branch — TR2 fail-closed).

## Phase 1: vector.toml host_metrics tuning

- [ ] 1.1 Edit `apps/web-platform/infra/vector.toml` Source 4 block ONLY (per plan Phase 1 verbatim TOML):
  - [ ] 1.1.1 `scrape_interval_secs = 30` → `300`
  - [ ] 1.1.2 Replace stale `# 30s scrape. Each scrape emits ~80-100 metric series...` comment with the 2026-06-10 quota-incident comment (names ~196k rows/day baseline, 80% warning, 300s rationale, loop*/dm-* excludes, expenses.md decision record, #4296)
  - [ ] 1.1.3 Add `[sources.host_metrics.disk]` with `devices.excludes = ["loop*", "dm-*"]`
  - [ ] 1.1.4 Add `[sources.host_metrics.filesystem]` with `devices.excludes = ["loop*", "dm-*"]`
- [ ] 1.2 Invariant check: do NOT touch sources 1–3, `app_container_warn_filter`, the three `pii_scrub_*` transforms, `tag_journald`, `tag_metrics`, `[sinks.betterstack]`, `[sources.vector_internal]` (keeps `scrape_interval_secs = 60`), `[sinks.vector_console]`

## Phase 2: expense ledger

- [ ] 2.1 `knowledge-base/operations/expenses.md` frontmatter `last_updated:` → `2026-06-10`
- [ ] 2.2 Append 2026-06-10 incident note to the Better Stack `0.00 | free-tier` row Notes (plan Phase 2 text; no `|` chars; fill real PR number after `gh pr create`). Do NOT touch the `Better Stack Responder (DEFERRED)` row

## Phase 3: verification (pre-push)

- [ ] 3.1 Download pinned Vector binary (version parsed from `vector.tf`; form per plan Phase 3)
- [ ] 3.2 `vector validate --no-environment --config-toml apps/web-platform/infra/vector.toml` → exit 0 (AC6). NOTE (deepen-time probe): validate does NOT catch misspelled filter sub-keys (`devices.exclude` validates clean as a silent no-op) — AC4's byte-exact `devices.excludes = ["loop*", "dm-*"]` grep is the spelling guard; do not weaken it
- [ ] 3.3 `bash apps/web-platform/test/infra/vector-pii-scrub.test.sh` with `VECTOR_BIN` + `SENTRY_USERID_PEPPER=fixture-only-do-not-use-in-prod` → all pass (AC7; precondition: `apps/web-platform` node_modules)
- [ ] 3.4 Run AC1–AC5 + AC8 grep/diff gates (plan § Acceptance Criteria, commands tested green on baseline at plan time)

## Phase 4: PR

- [ ] 4.1 PR body: `Ref #4296` (NOT Closes), deployment note (tag → image build → cloud-init pin bump → operator-acked webhook → AC12 query verdict), AC12 deterministic rule (first full post-deploy day host rows ≤ 25k vs ~196k baseline)
- [ ] 4.2 Confirm `validate-vector-config.yml` PR check green (AC10)

## Phase 5: post-merge (operator / in-session, per AC11–AC13)

- [ ] 5.1 Tag merge commit `vinngest-v1.1.12` (re-check next free semver first) + push → image build
- [ ] 5.2 Poll `build-inngest-bootstrap-image.yml` run → success
- [ ] 5.3 Follow-up PR: `cloud-init.yml` pin `v1.1.11` → `v1.1.12` (all 4 occurrences; AC6 drift guard)
- [ ] 5.4 Fire deploy webhook (canonical HTTPS HMAC form; **operator ack required** — prod write)
- [ ] 5.5 Verify clean reload via `/hooks/deploy-status` (`exit_code: 0`, clean `vector_journal_tail`)
- [ ] 5.6 ≥24h later: AC12 betterstack-query.sh verdict (post-deploy day ≤ 25k host-metrics rows)
- [ ] 5.7 Confirm #4296 still OPEN
