# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-29-fix-web-2-ci-deploy-delivery-plan.md
- Status: complete

### Errors
- `skill`/`Task`/`advisor` tools unavailable in the Devin subagent harness — `plan` and `deepen-plan` were executed by reading their SKILL.md files and running all steps/gates manually (sequential fallback). All mechanical halt gates passed; `lint-guard-contract.py` reports 2 guard entries OK.
- One markdownlint hit (MD004) — fixed before commit.
- `apply-deploy-pipeline-fix.yml` deliberately excludes `server.tf` from `paths:` (R13) — reconciled in the plan: the sibling still applies because the diff touches `ci-deploy.sh`/`cat-deploy-state.sh`.
  - **Corrected at work time:** the R13 comment was stale — `server.tf` has been in `paths:` for months (the test's expected set already required it). The comment was rewritten to record only the true consequence: a Doppler-only rotation touches no repo path and therefore does not fire the workflow.

### Decisions
- One guarded SSH `terraform_data.deploy_pipeline_fix_web2` sibling with `connection.host = web-2` — the issue's `for_each` direction is infeasible as written (the resource is `local-exec` POSTing to a single hostname; the web-1 pin lives in the tunnel ingress), so #7103's pre-decided shape controls.
- Route: `ssh -L` forward through the existing pinned web-1 bridge (ADR-220 `-W` precedent) — no new Cloudflare ingress/Access/DNS objects.
- Credential boundary kept: `SOLEUR_DOPPLER_TOKEN`/`local.webhook_doppler_token_env` excluded from the web-2 delivery set (refresh remains #7103-B4 scope).
- Parity assertion three-layered: `DEPLOY_SCRIPT_SHA` log emit → Better Stack (per-host `host_name`), `ci_deploy_sha256` in `/hooks/deploy-status`, plus in-band `remote-exec` sha256 asserts at apply time.
- PR body: `Ref #7103` + `Ref #9151` (no `Closes` — closure waits for PM3 post-merge Better Stack evidence of `IMAGE_FRESHNESS: ok` + `IMAGE_VERIFY: ok` from `host_name=soleur-web-2`).

### Components Invoked
- `plan` skill (manual fallback), `deepen-plan` skill (manual fallback)
- Live verifications: `gh issue view 9151/7103`, PR #9156 mergedAt, Hetzner API, Doppler `ADMIN_IPS`, `ssh-keyscan` of web-2, markdownlint, lint-guard-contract.py, lint-encryption-posture.py, code-review overlap sweep

## Work Phase
- Status: implementation complete; review/qa/ship pending.
- Commits: `7ce546a090` (host-key pin + HCL plumbing), `e6cfe30fca` (sibling resource + workflow route + parity surface), docs commit pending.

### Errors / corrections
- `FLOOR_DESTS`/`FLOOR_BLOCKS` first guessed 79/22; measured reality is 75/23 — floors pinned to measured.
- G2-7 mutation masked: the fixed 600-char RHS window let web-2's `one(` survive after web-1's was loosened. Fix: bound the local-shape capture at the end of the enclosing `locals {}` block; `.tf.json` local detection parameterised per key.
- Mutation anchors M30/M35/G2-3 re-derived for the new baselines (74 dests, 27 seed-overlap, 19 server.tf connection blocks).
- `check-deploy-script-parity.sh`: two extraction fixes — `awk` default-FS split `dt`'s internal space (tab-FS now), and jq `capture` throws on non-matching messages (wrapped in `try/catch`).
- `host_name_for` needed a trailing newline for line-oriented consumers; self-test fixture sha shortened below 64 hex — both fixed.

### Measured verdicts
- `web-host-provisioner-parity.test.sh`: 15+8 green.
- `web-host-provisioner-parity-mutation.test.sh`: 82/82.
- `web-2-host-key-local.test.sh`: 23/23.
- `terraform-target-parity.test.ts` + `ship-deploy-pipeline-fix-gate.test.ts`: 372 then 114 green (incl. new sibling-containment test).
- `cat-deploy-state.test.sh`: 116/116; `ci-deploy.test.sh`: 360/360; `check-deploy-script-parity.test.sh`: 11/11.
- `terraform fmt -check` clean; `terraform validate` green.
