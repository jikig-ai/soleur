---
lane: "single-domain"
issue: 3704
plan: "../../plans/2026-05-12-fix-harden-web-platform-release-pipeline-3704-plan.md"
---

# Tasks — Harden Web Platform Release Pipeline (#3704)

Derived from the plan. Each task corresponds to a phase + Acceptance Criterion in the plan.

## 1. Wrapper + script trap (Phase 1)

- [ ] 1.1 Create `apps/web-platform/infra/ci-deploy-wrapper.sh` — single `exec timeout --signal=TERM --kill-after=20s 900s /usr/local/bin/ci-deploy.sh`. Mode `0755`.
- [ ] 1.2a Add `set -m` to `apps/web-platform/infra/ci-deploy.sh` at top (between `set -euo pipefail` and the first `readonly`).
- [ ] 1.2b Add `trap 'final_write_state 124 "timeout"; kill -TERM 0 2>/dev/null || true; exit 124' TERM INT` to `apps/web-platform/infra/ci-deploy.sh` directly after the existing EXIT trap (around line 102).
- [ ] 1.3 Edit `apps/web-platform/infra/hooks.json.tmpl` `execute-command` to `/usr/local/bin/ci-deploy-wrapper.sh`.
- [ ] 1.4 Edit `apps/web-platform/infra/server.tf`:
  - [ ] 1.4.1 Add `file("${path.module}/ci-deploy-wrapper.sh")` to `terraform_data.deploy_pipeline_fix.triggers_replace`.
  - [ ] 1.4.2 Add a `provisioner "file"` block uploading `ci-deploy-wrapper.sh` to `/usr/local/bin/ci-deploy-wrapper.sh`.
  - [ ] 1.4.3 Add a `chmod +x /usr/local/bin/ci-deploy-wrapper.sh` line to the trailing `remote-exec` block.
  - [ ] 1.4.4 Add `ci_deploy_wrapper_script_b64 = base64encode(file("${path.module}/ci-deploy-wrapper.sh"))` to the cloud-init `templatefile` args.
- [ ] 1.5 Edit `apps/web-platform/infra/cloud-init.yml`:
  - [ ] 1.5.1 Add `write_files` entry for `/usr/local/bin/ci-deploy-wrapper.sh` (b64 encoded, root:root, 0755).
  - [ ] 1.5.2 Mirror the `hooks.json` content (no template change needed — `hooks_json_b64` already covers `.tmpl` re-render).

## 2. Tests (Phase 2)

- [ ] 2.1 Create `apps/web-platform/infra/ci-deploy-wrapper.test.sh` (mock `systemd-run`, smoke test env-var forwarding).
- [ ] 2.2 Add a SIGTERM scenario to `apps/web-platform/infra/ci-deploy.test.sh` (start the script in background with mock dependencies, `kill -TERM $pid`, assert state file shows `exit_code=124 reason=timeout`).
- [ ] 2.3 Run both tests locally: `bash apps/web-platform/infra/ci-deploy.test.sh` and `bash apps/web-platform/infra/ci-deploy-wrapper.test.sh`.

## 3. Workflow alignment + docs (Phase 3)

- [ ] 3.1 Add a cross-reference comment in `.github/workflows/web-platform-release.yml` near `IN_FLIGHT_CEILING_S: 900` pointing at `RuntimeMaxSec=900s` in `apps/web-platform/infra/ci-deploy-wrapper.sh`.
- [ ] 3.2 Append `timeout | 124 | systemd-run RuntimeMaxSec hit | Investigate why deploy exceeded 900s — likely network hang or hung docker exec` row to the reason taxonomy table in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`.

## 4. Pre-merge verification (Phase 4)

- [ ] 4.1 `terraform fmt apps/web-platform/infra/` reports no diff.
- [ ] 4.2 `terraform validate apps/web-platform/infra/` returns success (after `terraform init -input=false`).
- [ ] 4.3 `bun test plugins/soleur/test/components.test.ts` passes.
- [ ] 4.4 Pre-commit hooks pass (rule-budget, AGENTS.md tier-gate).
- [ ] 4.5 Multi-agent plan review (DHH-rails-reviewer, Kieran-rails-reviewer, code-simplicity-reviewer) returns no P0/P1 unresolved findings — applied inline or filed as deferred-scope-out.

## 5. Post-merge (Operator — outside PR scope) (Phase 5)

- [ ] 5.1 Operator pulls `main`, runs the canonical apply triplet (AWS_* exports + `terraform init` + `doppler run --name-transformer tf-var -- terraform apply -target=terraform_data.deploy_pipeline_fix`).
- [ ] 5.2 Operator confirms `yes` at Terraform prompt.
- [ ] 5.3 Post-apply file+systemd contract verification (sha256sum comparison, `systemctl is-active webhook`).
- [ ] 5.4 Trigger or await next organic web-platform release; verify `Deploy verified` log line within 900s and absence of `running` past 900s.
- [ ] 5.5 `gh issue close 3704` AND `gh issue close 2207` with the verification run URL in the close comment.
