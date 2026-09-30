# Tasks: fix-luks-monitor-epipe-flake (+ artifact-list pagination bundle)

Plan: `knowledge-base/project/plans/2026-09-30-fix-luks-monitor-epipe-flake-plan.md`
Issue: #9245 — luks-monitor.test.sh EPIPE flake; bundled: deferred artifact-list
pagination nit from #9232's review.

## Phase 1: EPIPE drains + wire assert (the #9245 fix)

- [ ] 1.1 `apps/web-platform/infra/workspaces-luks-harness.sh` — `mon_prepare`'s
      `bin/cryptsetup` stub: `luksOpen` arm drains stdin to
      `"$CALLS.escrow-stdin"` guarded by `[ ! -t 0 ]`, then
      `exit "${MON_ESCROW_RC:-0}"` as before.
- [ ] 1.2 `apps/web-platform/infra/workspaces-luks-harness.sh` — `run_case`'s
      `cryptsetup()` function stub: guarded `cat >/dev/null` drain as the
      first statement after `rec`, scoped to argv containing `--key-file -`
      (covers cutover luksFormat/luksOpen, reopen, git-data SUT lines).
- [ ] 1.3 `apps/web-platform/infra/workspaces-luks-staging.test.sh` ~885 —
      inline `bin/cryptsetup` printf-stub: drain stdin in the `*luksFormat*`
      and `*luksOpen*` arms.
- [ ] 1.4 `apps/web-platform/infra/luks-monitor.test.sh` — after the
      healthy-heartbeat case, assert the escrow key arrived:
      `[ "$(cat "$CALLS.escrow-stdin" 2>/dev/null)" = "k" ]` (MON_KEY
      default).
- [ ] 1.5 GREEN: `bash apps/web-platform/infra/luks-monitor.test.sh` (79
      asserts), `bash apps/web-platform/infra/workspaces-luks-staging.test.sh`,
      `bash apps/web-platform/infra/workspaces-luks-freeze.test.sh`; stress
      loop `for i in $(seq 60); do bash apps/web-platform/infra/luks-monitor.test.sh >/dev/null 2>&1 || echo "FLAKE $i"; done`
      prints nothing.

## Phase 2: pagination + regression fixtures

- [ ] 2.1 `scripts/regenerate-shard-manifest.py` — new
      `list_run_artifacts(run_id)` page loop (`per_page=100&page=N`,
      terminate on short page or `len >= total_count`);
      `fetch_timings_from_run` consumes it.
- [ ] 2.2 `plugins/soleur/test/regenerate-shard-manifest.test.sh` —
      PATH-stubbed `gh` multi-page fixture: 101 artifacts, the
      `suite-timings-scripts-*` artifact only on page 2; merged timings must
      contain its label.
- [ ] 2.3 `.github/workflows/web-platform-release.yml` — release-monitor
      step: `jobs` call (~605) and `artifacts` call (~620) both become
      `--paginate` + `jq -s` flatten; `arts=` line gains
      `|| fail_closed "..." "github_api_unavailable"`.
- [ ] 2.4 `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-b.template`
      AND `.github/workflows/fix-constraints-stage-b.yml` — identical
      artifacts-call edit (parity.test.sh #5 pins them byte-equal).
- [ ] 2.5 `scripts/followthroughs/ci-leg-balance-9232.sh` — artifacts call →
      `--paginate` + `jq -s`; `ci-leg-balance-9232.test.sh` adds the
      calls.log `--paginate`-on-artifacts shape assert (mirrors
      actions-queue-health.test.sh:379-383).
- [ ] 2.6 `scripts/sentry-last-applied-sha.sh:63` — `jobs?filter=all` →
      `--paginate` + `jq -s` (no dedicated suite — `bash -n` + review read).
- [ ] 2.7 GREEN: `bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh`,
      `bash plugins/soleur/test/regenerate-shard-manifest.test.sh`,
      `bash scripts/followthroughs/ci-leg-balance-9232.test.sh`,
      `bash tests/scripts/test-main-duplicate-skip.sh`,
      `actionlint` on the two edited workflows.

## Phase 3: CI verification

- [ ] 3.1 Push; watch `deploy-script-tests` legs on the PR go green.
- [ ] 3.2 Re-trigger the legs twice more (`gh run rerun --failed` or empty
      push) — 3 consecutive green infra-validation runs (issue AC).
- [ ] 3.3 Confirm the artifacts/jobs call sites all carry `--paginate`
      (or the python `page=` loop): `grep -rn -- '--paginate\|page='
      scripts/regenerate-shard-manifest.py scripts/followthroughs/ci-leg-balance-9232.sh
      scripts/sentry-last-applied-sha.sh .github/workflows/web-platform-release.yml
      .github/workflows/fix-constraints-stage-b.yml`.
