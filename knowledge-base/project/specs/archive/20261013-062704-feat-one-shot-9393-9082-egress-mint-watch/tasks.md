# Tasks — feat-one-shot-9393-9082-egress-mint-watch

Plan: knowledge-base/project/plans/2026-10-07-fix-web2-cron-egress-delivery-and-mint-backstops-plan.md
Issues: #9393 (web-2 cron-egress delivery), #9082 (auto-mint backstops)

## Phase 1 — Failing tests first (TDD)

- [ ] 1.1 Extend `apps/web-platform/infra/cron-egress-firewall.test.sh` with a
      `deploy_pipeline_fix_web2` delivery-parity section: resource-block-scoped
      source/destination rows for the three artifacts, triggers_replace `file()`
      rows, mode/owner rows, and the `bash …/cron-egress-postapply-assert.sh`
      execution row. Confirm the new rows are RED pre-implementation.
- [ ] 1.2 Extend `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`:
      paths-filter expected set +3 cron-egress paths; web2 `allowed` set +3
      basenames (named exception group, mirroring the web-2 pin precedent).
      Confirm RED pre-implementation.
- [ ] 1.3 Add Guard A2 block to `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
      (pins + recipe, tag-vs-HEAD) AND extend `g3_parity` in
      `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` with extractor
      byte-parity rows. Confirm the parity rows red when extractor tokens diverge.
- [ ] 1.4 Add mintwatch rows to `plugins/soleur/test/main-health-monitor-workflow.test.sh`
      (step presence, `gh --json`→standalone-jq convention, red set
      {failure,startup_failure}, filer/closer/heartbeat wiring). Confirm RED.

## Phase 2 — #9393 implementation

- [ ] 2.1 `apps/web-platform/infra/server.tf` `deploy_pipeline_fix_web2`:
      +3 `file()` entries in triggers_replace; sentinel `dpf-web2-remote-exec-v1`→`v2`;
      `mkdir -p /etc/soleur` on the first remote-exec; +3 file provisioners
      (cidr→/etc/soleur 0644, resolve.sh→/usr/local/bin 0755,
      postapply-assert.sh→/usr/local/bin 0755); remote-exec chown/chmod +
      sha256sum content assertions; execute the assert script last; update the
      scope-boundary comment.
- [ ] 2.2 `.github/workflows/apply-deploy-pipeline-fix.yml`: +3 `on.push.paths`
      entries with a comment naming the parity obligation.
- [ ] 2.3 `terraform fmt` the edited block; `bash cron-egress-firewall.test.sh`
      green; `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`
      green; `bash web-host-provisioner-parity.test.sh` green (terraform present).
- [ ] 2.4 Update `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`
      "Known residual: running web-2" for the new channel.

## Phase 3 — #9082 implementation

- [ ] 3.1 Guard A2 block in `cloud-init-inngest-bootstrap.test.sh` after Guard A:
      pin extraction at `vinngest-$GA_PIN_TAG` + HEAD via `git show`,
      mint-script-identical extractors, per-pin byte-parity asserts, recipe
      assert, unresolved/empty-extractor rows, exact-count anti-vacuity floor.
- [ ] 3.2 `.github/workflows/main-health-monitor.yml`: `mintwatch` step
      (`continue-on-error: true`, no `timeout-minutes`, `timeout`-bounded
      `gh run list --workflow=mint-inngest-bootstrap-tag.yml --branch main
      --json …` → standalone jq, verdict red|green|unknown → GITHUB_OUTPUT);
      filer `if:` + dedicated mint arm (TITLE/LEDE/ACTIONS); closer `if:`
      `!= 'red'` conjunct; heartbeat `status:` conjunct.
- [ ] 3.3 Run the touched suites green (cloud-init-inngest-bootstrap,
      test-mint-inngest-bootstrap-tag, main-health-monitor-workflow).

## Phase 4 — wrap-up

- [ ] 4.1 Commit per-phase; push; `gh pr merge --auto` on PR #9680; poll MERGED.
- [ ] 4.2 PR body carries `Closes #9393` and `Closes #9082` on their own lines,
      plus `## Changelog` and Merge Danger/Pipeline Tally sections.
