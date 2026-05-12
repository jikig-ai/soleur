---
lane: "single-domain"
issue: 3704
plan: "../../plans/2026-05-12-fix-harden-web-platform-release-pipeline-3704-plan.md"
---

# Tasks — Harden Web Platform Release Pipeline (#3704)

Derived from the plan. Each task corresponds to a phase + Acceptance Criterion in the plan.

## 1. Wrapper + script trap (Phase 1)

- [x] 1.1 Create `apps/web-platform/infra/ci-deploy-wrapper.sh` — single `exec timeout --signal=TERM --kill-after=20s 900s /usr/local/bin/ci-deploy.sh`. Mode `0755`.
- [x] 1.2a Add `set -m` to `apps/web-platform/infra/ci-deploy.sh` at top (between `set -euo pipefail` and the first `readonly`).
- [x] 1.2b Add the TERM/INT trap to `apps/web-platform/infra/ci-deploy.sh` directly after the existing EXIT trap. **Deviation from plan literal:** uses `pkill -TERM -P $$` instead of `kill -TERM 0`. Empirical testing confirmed `kill -TERM 0` from a script invoked by webhook would TERM the webhook.service parent (ci-deploy.sh inherits webhook's PGID; `set -m` puts children in new PGIDs but does NOT move bash itself out of the parent's PGID). `pkill -P $$` sends TERM only to direct children — same intent, safe semantic.
- [x] 1.3 Edit `apps/web-platform/infra/hooks.json.tmpl` `execute-command` to `/usr/local/bin/ci-deploy-wrapper.sh`.
- [x] 1.4 Edit `apps/web-platform/infra/server.tf`:
  - [x] 1.4.1 Add `file("${path.module}/ci-deploy-wrapper.sh")` to `terraform_data.deploy_pipeline_fix.triggers_replace`.
  - [x] 1.4.2 Add a `provisioner "file"` block uploading `ci-deploy-wrapper.sh` to `/usr/local/bin/ci-deploy-wrapper.sh`.
  - [x] 1.4.3 Add a `chmod +x /usr/local/bin/ci-deploy-wrapper.sh` line to the trailing `remote-exec` block.
  - [x] 1.4.4 Add `ci_deploy_wrapper_script_b64 = base64encode(file("${path.module}/ci-deploy-wrapper.sh"))` to the cloud-init `templatefile` args.
- [x] 1.5 Edit `apps/web-platform/infra/cloud-init.yml`:
  - [x] 1.5.1 Add `write_files` entry for `/usr/local/bin/ci-deploy-wrapper.sh` (b64 encoded, root:root, 0755).
  - [x] 1.5.2 Mirror the `hooks.json` content (no template change needed — `hooks_json_b64` already covers `.tmpl` re-render).

## 2. Tests (Phase 2)

- [x] 2.1 Create `apps/web-platform/infra/ci-deploy-wrapper.test.sh` — file-shape invariants, single-non-comment-line check, GNU `timeout(1)` SIGTERM-exit-124 contract, env propagation via `exec`, success path.
- [x] 2.2 Add SIGTERM trap coverage to `apps/web-platform/infra/ci-deploy.test.sh`. **Two-part design** (foreground-hang defer was empirically confirmed unavoidable for raw `docker pull`): (a) static assertion that ci-deploy.sh has `set -m` + canonical trap, (b) isolated repro of the trap pattern in a controlled `sleep & wait $!` script so the trap can fire and writes the expected state. The wrapper's `--kill-after=20s` SIGKILL fallback is what saves us when bash is stuck on a foreground `docker pull` and the trap can't run.
- [x] 2.3 Run both tests locally: 5/5 + 69/69 pass.

## 3. Workflow alignment + docs (Phase 3)

- [x] 3.1 Add a cross-reference comment in `.github/workflows/web-platform-release.yml` near `IN_FLIGHT_CEILING_S: 900` pointing at the `timeout … 900s …` line in `apps/web-platform/infra/ci-deploy-wrapper.sh`.
- [x] 3.2 Append `timeout | 124 | …` row to the reason taxonomy table in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`.

## 4. Pre-merge verification (Phase 4)

- [x] 4.1 `terraform fmt -check apps/web-platform/infra/` returns rc=0 (no diff).
- [x] 4.2 `terraform validate apps/web-platform/infra/` returns success.
- [x] 4.3 `bun test plugins/soleur/test/components.test.ts` passes (1045/1045).
- [ ] 4.4 Pre-commit hooks pass (rule-budget, AGENTS.md tier-gate). Runs at commit time.
- [ ] 4.5 Multi-agent plan review (DHH-rails-reviewer, Kieran-rails-reviewer, code-simplicity-reviewer) returns no P0/P1 unresolved findings — runs in the `/soleur:review` phase that follows.

## 5. Post-merge (Operator — outside PR scope) (Phase 5)

- [ ] 5.1 Operator pulls `main`, runs the canonical apply triplet (AWS_* exports + `terraform init` + `doppler run --name-transformer tf-var -- terraform apply -target=terraform_data.deploy_pipeline_fix`).
- [ ] 5.2 Operator confirms `yes` at Terraform prompt.
- [ ] 5.3 Post-apply file+systemd contract verification (sha256sum comparison, `systemctl is-active webhook`).
- [ ] 5.4 Trigger or await next organic web-platform release; verify `Deploy verified` log line within 900s and absence of `running` past 900s.
- [ ] 5.5 `gh issue close 3704` AND `gh issue close 2207` with the verification run URL in the close comment.
