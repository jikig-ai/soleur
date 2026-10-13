# Tasks — feat: Wire dormant env-gated integration suites into scheduled CI (#9855 PR 2)

Plan: `knowledge-base/project/plans/2026-10-10-feat-dormant-integration-ci-plan.md`
Issue: #9855 (Closes) | PR 1: #9890 (merged) | Draft PR: #9947

Constraint: no live dev-Supabase writes in-session. Pre-merge verification is
static only (actionlint/YAML parse, shellcheck, sentinel battery, `git grep`
census). Live validation is the post-merge `workflow_dispatch` AC.

## Phase 0 — Preconditions

- [x] 0.1 `gh issue view 9855` — confirm OPEN (this PR closes it).
- [x] 0.2 Confirm no plan drift: `git log --oneline origin/main -- .github/workflows/tenant-integration.yml scripts/dev-suite-mutex.sh | head -5` — re-read any post-plan changes to the mirrored blocks before copying them.
- [x] 0.3 Re-run the gate census to catch gates added since the plan: 59 gated files / 12 vars — matches the plan's table (6× SUPABASE_DEV_INTEGRATION, 7 dormant vars, 4 allowlisted).

## Phase 1 — Sentinel (failing-test-first)

- [x] 1.1 Created `scripts/lint-integration-env-gates.sh`:
  - Producer: `git grep` per-FILE over `apps/web-platform/{test,lib}` (lib is in unit-project scope) → file→vars map. Zero census = error; floor MIN_GATED_FILES=50.
  - Consumer: every `.github/workflows/*.{yml,yaml}` file, comment-stripped; setting positions = `env <VAR>=1` run-prefix OR `<VAR>: ["']?1` env-mapping.
  - TWO arms: var-level wiring AND file-level collection (file path or depth>=2 ancestor dir, whitespace/EOL-bounded, in a workflow that sets ALL its non-allowlisted gates — skipIf conjunction).
  - Seed allowlist: `RLS_FUZZ_LOCAL`, `SOLEUR_ISOLATION_IN_IMAGE`, `SOLEUR_ISOLATION_TEST_HOST`, `ANTHROPIC_ISOLATION_TEST_OK` — all cited to #9855; `ALLOWLIST_FILES` empty.
  - Summary: `env-gates: found=<F> wired=<W> allowlisted=<A> uncovered=<U>`; non-zero on uncovered>0, unwired var, or census violation.
  - Fixture seam `SOLEUR_LINT_GATES_ROOT` (real git work tree).
- [x] 1.2 Created `scripts/lint-integration-env-gates.test.sh` — 30-row mutation battery over synthetic git fixture repos (55-file pad population satisfies the floor without a tunable override): control-green, unwired-var, zero-census, new-gate, two-gates-named, spelling-drift, env-mapping ×3 spellings PASS, commented-out-setting, lib/-scope, wired+uncollected (departed-member shape), dir-filter PASS, echo-not-a-setting, ancestor-dir PASS, conjunction, `!==` polarity, depth-1 test//lib/ rejection, `.yaml` wiring PASS, string-literal env/mapping non-settings, lib file-token PASS, space-in-string env, multi-var prefix PASS, sub-floor census, self-vacuity.
- [x] 1.3 Sentinel RED on pre-workflow tree (13 uncovered = 12 dormant + departed-member; 7 unwired vars) = failing-test proof; battery 30/30 GREEN.
- [x] 1.4 Registered in `scripts/test-all.sh` beside `lint-orphan-test-suites*` — `scripts/lint-integration-env-gates-live` + `-battery`, unconditional. Classified in `scripts/lib/test-affected-paths.sh` (`-live` → ALWAYS_ON_SUITES; battery → `AFFECTED_SCRIPTS_LINT_INTEGRATION_ENV_GATES_BATTERY_PATHS`). Shard manifests regenerated.

## Phase 2 — Workflow

- [x] 2.1 Created `.github/workflows/scheduled-integration-suites.yml` per consolidated plan:
  - `# <!-- gate-override: new-scheduled-cron-prefer-inngest -->` marker line 1 (YAML comment form — actionlint rejects the bare HTML form).
  - `on:` `schedule` `30 4 * * *` + `workflow_dispatch` only. NO `pull_request`/`merge_group`/`push`.
  - `permissions: {contents: read, issues: write}`; `concurrency.group: dev-supabase-${{ github.ref }}`, `cancel-in-progress: false`; `timeout-minutes: 70`.
  - Steps: checkout → Bun/Node/`npm ci` → Doppler CLI (v4 pinned) → token non-empty check → `environment=dev` + `SUPABASE_ACCESS_TOKEN`-absence via `scripts/assert-dev-doppler-scope.sh` (extracted — the ONE copy shared by all three dev-scoped workflows; reconcile's rc-branched form wins) → `dev-suite-mutex.sh acquire` (identity `di-${{ github.run_id }}-${{ github.ref_name }}`, `DEV_SUITE_MUTEX_HOLD_S=4500` > job timeout, pinned by wiring-test W9) → seed bot fixtures (soft-fail, `timeout-minutes: 5`, `$GITHUB_WORKSPACE`-anchored path) → schema-vs-ledger preflight → `run-migrations.sh --bootstrap=skip` with `MIGRATION_SCHEMA_PRECONDITION_PROBE=1` and NO `ALLOW_UNMERGED_DEV_APPLY` → WORM-cascade preflight (`id: worm` — the substrate gate) → **8** suite steps (supabase-dev ×6 files, worktree-lease, acquire-slot, byok, slot-trigger, workspace-binding, mu1, departed-member), each `if: ${{ !cancelled() && steps.worm.outcome == 'success' }}`, `timeout-minutes: 6`, `working-directory: apps/web-platform` → mutex release `if: always()` → `aggregate` step (`compgen -v OUT_` single enumeration + vacuity floor → `status`, `failed_md` outputs) → issue file-or-comment `if: failure() || cancelled() && main` consuming `failed_md` (labels `ci/integration-suites` + `priority/p1-high`, both self-healed) → auto-close stale tracker on green main run → terminal sentry-heartbeat `if: always()` consuming `status` (producer-outcome-first: ok iff all 8 suite steps succeeded).
- [x] 2.2 Static-verify: `actionlint` clean (except benign SC2016 ratchet class); `lint-workflow-*` lints all pass (issue-write-scope, errexit-capture, install-sites, step-env-refs, local-action-checkout, run-body-syntax).
- [x] 2.3 Sentinel GREEN: `env-gates: found=59 wired=8 allowlisted=4 uncovered=0`.

## Phase 3 — CI wiring + docs + monitor IaC

- [x] 3.1 `ci.yml` `lint-bot-statuses` job: advisory `- name: Lint integration env gates` step beside "Lint orphan test suites". NOT in `required-checks.txt` / ruleset.
- [x] 3.2 `apps/web-platform/test/README.md`: flag table completed for all gates + "CI wiring" paragraph — workflow, eight gates, shared-dev substrate decision + two-consecutive-filings revisit trigger.
- [x] 3.3 `bash scripts/lint-orphan-test-suites.sh` — 655 covered, 0 orphaned.
- [x] 3.4 `sentry_cron_monitor.scheduled_integration_suites` in `cron-monitors.tf` (crontab `30 4 * * *`, margin 1440, max_runtime 70 tracking the job timeout) + unrouted entry in `cron-monitor-alerts.tf` citing #9959 (two-PR rule; dedicated routing follow-up). Full five-ledger update: `NON_INNGEST_MONITORS` entry, README 63→64, audit figure-of-record, `model.c4` edges + `model.likec4.json` regen. `sentry-monitor-iac-parity.test.ts` 24/24; `function-registry-count.test.ts` 11/11; `sentry-monitors-audit.test.sh` 82/82; `c4-count-parity.test.sh` 13/13.
- [x] 3.5 `mu1.integration.test.ts:220` stale comment corrected (AC-2 now runs nightly under `dev_scheduled`).

## Phase 4 — Verification & ship prep

- [ ] 4.1 AC sweep against the plan's `## Acceptance Criteria` — all pre-merge items static-verifiable.
- [ ] 4.2 PR body: `Closes #9855` in body (not title) + `## Changelog` section.
- [ ] 4.3 Post-merge (pipeline step, not in-session): `gh workflow run scheduled-integration-suites.yml` on main + `gh run watch` — reaches suite steps; files `ci/integration-suites` issue on red.
- [ ] 4.4 If first nightly/dispatch fails on shared-dev substrate (grant divergence, cruft — NOT a real regression): file per-suite follow-up; do NOT weaken gates to force green. Two consecutive substrate-cruft filings → reopen dedicated-project evaluation (plan §Risks revisit trigger).
