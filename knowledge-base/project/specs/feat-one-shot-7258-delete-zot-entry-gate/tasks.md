# Tasks: delete the superseded zot-entry-gate.sh (#7258 Step B)

Plan: knowledge-base/project/plans/2026-10-11-chore-delete-zot-entry-gate-plan.md
Branch: feat-one-shot-7258-delete-zot-entry-gate | Draft PR: #10016 | Closes #7258 | Refs #7079

## Phase 0: Preflight (read-only)

- [ ] 0.1 `git fetch origin main`; rebase (never merge) if behind; check for conflict markers before any `git add`
- [ ] 0.2 Re-run `git grep -n 'zot-entry-gate' -- . ':!knowledge-base'`; compare with the plan census; re-grep every line number
- [ ] 0.3 Confirm no entry for the gate in `scripts/guard-vacuity-floor.test.sh`, `plugins/soleur/test/fixture-relative-assert.baseline.txt`, `scripts/suite-*.tsv` (use `/usr/bin/grep -a` if ugrep returns nothing)
- [ ] 0.4 Check open PRs touching `ci-deploy.sh` (#9938 at plan time) and `reusable-release.yml` (#7390 WIP)

## Phase 1: Delete script, test, registrations

- [ ] 1.1 `git rm apps/web-platform/infra/zot-entry-gate.sh apps/web-platform/infra/zot-entry-gate.test.sh`
- [ ] 1.2 Delete the `zot-entry-gate.test.sh` row from `apps/web-platform/infra/suite-shard-legs.tsv` (by content, not line number)
- [ ] 1.3 Delete the `zot-entry-gate.test.sh` row from `apps/web-platform/infra/suite-durations.tsv`
- [ ] 1.4 `bash .github/scripts/test/test-infra-suite-registration.sh` and `bash plugins/soleur/test/regenerate-shard-manifest.test.sh`

## Phase 2: Dangling comment references (comment-only)

- [ ] 2.1 `apps/web-platform/infra/ci-deploy.sh`: re-point the "zot's real 403 lives" line to `web-zot-consumer-probe.sh` (no version, no date)
- [ ] 2.2 `.github/workflows/reusable-release.yml`: drop the gate from the namespace comment (~:1219) and the pre-flip claim (~:1420)
- [ ] 2.3 `.github/workflows/build-inngest-bootstrap-image.yml` ~:817: drop "+ zot-entry-gate.sh"
- [ ] 2.4 Verify `ci-deploy.sh` diff is comment-only; `shellcheck apps/web-platform/infra/ci-deploy.sh`

## Phase 3: Post-Step-A truth in build-inngest-bootstrap-image.yml

- [ ] 3.1 Grep the suites under `apps/web-platform/infra/*.test.sh` and `.github/scripts/test/` for the strings about to change
- [ ] 3.2 Rewrite ~:929-931 ("no live probe ... SUPERSEDED/UNWIRED") to the post-Step-A truth
- [ ] 3.3 Align the `GITHUB_STEP_SUMMARY` "host-side pull is unverified for this repo" clause; keep "does not license a pin"

## Phase 4: The two stale Slack statements

- [ ] 4.1 `build-inngest-bootstrap-image.yml` ~:971-979: replace the false "AHEAD / ZERO times / tracked separately (#7256)" paragraph (verify `cancelled()` count and the `Post to Slack (release BLOCKED)` step first)
- [ ] 4.2 `plugins/soleur/skills/ship/references/ci-workflow-authoring.md:10`: replace the single-step carve-out with the set returned by `git grep -n -E 'name: .*Slack' -- .github/workflows`
- [ ] 4.3 `bash plugins/soleur/test/reusable-release-idempotency.test.sh`; parse both edited workflows as YAML

## Phase 5: Local verification

- [ ] 5.1 Zero-residual census (excluding knowledge-base)
- [ ] 5.2 `bash scripts/guard-vacuity-floor.test.sh`; `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` (count stays 58); relative-assert ratchet; no floor or baseline edit
- [ ] 5.3 `.claude/hooks/*.test.sh` (timeout above 120 s for `pre-merge-rebase.test.sh`)
- [ ] 5.4 Optional full battery: skip if the capacity probe shows contention

## Phase 6: Ship

- [ ] 6.1 PR body: `Closes #7258`, `Refs #7079`, threshold `none` + reason, census, challengeable Slack-target note, sequencing note
- [ ] 6.2 Comment on #7079 that its zot-entry-gate item is resolved (leave #7079 open)
- [ ] 6.3 Raise `cron_monitor_alert_unrouted` no-expiry to the operator in the final report (do not file an issue)

## Phase 7: Deploy sequencing

- [ ] 7.1 Before enqueue: no apply in flight (`gh run list --status in_progress`, "Apply web-platform infra", "Apply deploy-pipeline-fix"); read the Deploy Pipeline Fix Drift Gate in `plugins/soleur/skills/ship/SKILL.md`
- [ ] 7.2 Do not push while queued (`plugins/soleur/scripts/sync-pr-behind.sh <PR> --queue-state`)
- [ ] 7.3 Post-merge: `bash plugins/soleur/scripts/deploy-arm.sh find --wait <full-sha>` then `served <full-sha>`; exactly one `apply-deploy-pipeline-fix.yml` run, green; a red `apply-web-platform-infra.yml` is acceptable only if it fails solely on `terraform_data.egress_gateway_web2` (#10003)
