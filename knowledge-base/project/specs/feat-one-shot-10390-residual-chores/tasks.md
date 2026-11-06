---
title: Tasks — feat-one-shot-10390-residual-chores
plan: knowledge-base/project/plans/2026-11-06-chore-one-shot-10390-residual-chores-plan.md
issue: 12092
pr: 12235
---

# Tasks

Derived from the plan (2026-11-06). Per-workstream commits land in draft PR #12235.

## Phase 1 — WS1: dedupe-lint residual surfaces (#12092)

- [ ] 1.1 Normalize `.github/workflows/scheduled-machinery-drain.yml:187` — `matches="$(gh issue list …)"` gets `|| { echo "::error::…refusing to touch the standing issue…"; exit 1; }` outside the capture.
- [ ] 1.2 Normalize `.github/workflows/codeql-1537-revisit-watch.yml:84` — `track_num="$(gh …)"` gets `|| { echo "::warning::…"; track_num=""; }` outside the capture (lands on the existing loud no-op path).
- [ ] 1.3 Disposition `.github/workflows/scheduled-supabase-watchdog.yml:512` and `.github/workflows/scheduled-actions-queue-health.yml:228` — `# dedupe: benign` markers per the assumed ruling (decision-challenges), or out-of-capture `::warning::` normalize if review rules otherwise. One mechanism per site.
- [ ] 1.4 Mark the nine `set +e`/`list_rc` sites `# dedupe: fail-closed — deliberate list_rc: …`: devin-docs-drift :400/:465, marketplace-drift :612/:811/:901, prod-version-drift :263/:426/:561/:604.
- [ ] 1.5 Surface 2 — `# dedupe: fail-closed` documentary marker on `dev-ledger-reconcile.yml:344`; re-enumerate `gh api` issues-GETs and verify the rest bound (codeql:66/68 recorded no-edit in PR audit table).
- [ ] 1.6 Surface 3 — 13-site `gh issue|pr view` inventory: normalize `scheduled-inngest-health.yml:699` to the `HAS_ESC_RC` sibling shape; markers on `terraform-drift:1746`, `auto-label-security:30/32`, `supabase-watchdog:441`, `reusable-release:253`, `apply-deploy-pipeline-fix:1682/2448/2538`; consumer-read then marker-or-normalize on `rehearsal-skip-monitor:341`, `terraform-drift:1642`, `post-merge-monitor:121/138`, `web-platform-release:1193`.
- [ ] 1.7 Surface 4 — extend `collect()` in `scripts/lint-gh-dedupe-shape.py` to enumerate `.github/actions/*/action.yml` (symlink-skip parity; docstring SCOPE + residual paragraph; honest scanned-count label).
- [ ] 1.8 Update `scripts/lint-gh-dedupe-shape.test.sh` — `ADVISORY_CEILING` decremented to the post-resolution live count (target 0, comment naming resolved sites); new fixtures: undispositioned action.yml capture FIRES, handled/marked action.yml capture passes, second-member-after-compliant-first.
- [ ] 1.9 Run `bash scripts/lint-gh-dedupe-shape.test.sh` green + `python3 scripts/lint-gh-dedupe-shape.py --root .` → `unclassified: 0`, advisory == ceiling.

## Phase 2 — WS2: route `scheduled_agent_spawn_stale_settle`

- [ ] 2.0 GATE — re-run the Sentry monitor read (command in plan Phase 2.0): proceed only if env `production` `status=ok`, `activeIncident=null`, `lastCheckIn` current. Else → deferral arm (keep unrouted entry, sharpen reason, document; skip 2.1–2.3 and AC8/AC9).
- [ ] 2.1 `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — remove the `scheduled_agent_spawn_stale_settle` unrouted entry + comment block; insert `sentry_cron_monitor.scheduled_agent_spawn_stale_settle.id,` in `monitor_ids` sorted position (before `scheduled_anthropic_credit_probe`).
- [ ] 2.2 `apps/web-platform/infra/sentry/alert-reference.json` — append `"2607514"` to `cron-monitor-failure.detectorIds` (string-sorted, after `"2586358"`). `plan_pr` gate is the proof; on red reconcile via the `sentry-alert-reference-expected-<run>` artifact.
- [ ] 2.3 `bun test apps/web-platform/test/server/inngest/sentry-cron-monitor-routing-parity.test.ts` + `sentry-monitor-iac-parity.test.ts` green.

## Phase 3 — WS3: cherry-pick the merge record

- [ ] 3.1 `git cherry-pick 5a8ffeefb8` (dry-run verified clean; keeps its own commit — do not re-write).

## Phase 4 — Commit, push, PR body

- [ ] 4.1 Per-workstream commits; push the branch.
- [ ] 4.2 Update PR #12235 title/body: `Closes #12092` own line; `Ref #10390`, `Ref #8839`, `Ref #9659`; per-surface audit table; Sentry evidence; `## Changelog`; `semver:patch` label expectation.

## Phase 5 — Merge gate + post-merge (operator-held)

- [ ] 5.1 `gh pr ready`/`gh pr merge` ONLY on fresh operator go-ahead (#10390 delegation = drift dispatch + revert-PR, expires 2026-11-20).
- [ ] 5.2 Post-merge: `apply-sentry-infra.yml` green on the merge commit; live `cron-monitor-failure` `detectorIds` contains `2607514`; delete remote `feat-one-shot-10390-ci-hygiene-batch`; verify #12092 closed.
