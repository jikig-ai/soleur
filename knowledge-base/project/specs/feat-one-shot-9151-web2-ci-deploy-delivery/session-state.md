# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-29-fix-web-2-ci-deploy-delivery-plan.md
- Status: complete

### Errors
- `skill`/`Task`/`advisor` tools unavailable in the Devin subagent harness — `plan` and `deepen-plan` were executed by reading their SKILL.md files and running all steps/gates manually (sequential fallback). All mechanical halt gates passed; `lint-guard-contract.py` reports 2 guard entries OK.
- One markdownlint hit (MD004) — fixed before commit.
- `apply-deploy-pipeline-fix.yml` deliberately excludes `server.tf` from `paths:` (R13) — reconciled in the plan: the sibling still applies because the diff touches `ci-deploy.sh`/`cat-deploy-state.sh`.

### Decisions
- One guarded SSH `terraform_data.deploy_pipeline_fix_web2` sibling with `connection.host = web-2` — the issue's `for_each` direction is infeasible as written (the resource is `local-exec` POSTing to a single hostname; the web-1 pin lives in the tunnel ingress), so #7103's pre-decided shape controls.
- Route: `ssh -L` forward through the existing pinned web-1 bridge (ADR-220 `-W` precedent) — no new Cloudflare ingress/Access/DNS objects.
- Credential boundary kept: `SOLEUR_DOPPLER_TOKEN`/`local.webhook_doppler_token_env` excluded from the web-2 delivery set (refresh remains #7103-B4 scope).
- Parity assertion three-layered: `DEPLOY_SCRIPT_SHA` log emit → Better Stack (per-host `host_name`), `ci_deploy_sha256` in `/hooks/deploy-status`, plus in-band `remote-exec` sha256 asserts at apply time.
- PR body: `Ref #7103` + `Ref #9151` (no `Closes` — closure waits for PM3 post-merge Better Stack evidence of `IMAGE_FRESHNESS: ok` + `IMAGE_VERIFY: ok` from `host_name=soleur-web-2`).

### Components Invoked
- `plan` skill (manual fallback), `deepen-plan` skill (manual fallback)
- Live verifications: `gh issue view 9151/7103`, PR #9156 mergedAt, Hetzner API, Doppler `ADMIN_IPS`, `ssh-keyscan` of web-2, markdownlint, lint-guard-contract.py, lint-encryption-posture.py, code-review overlap sweep
