# Tasks — fix verify-deploy step + apply terraform for /hooks/deploy-status

**Plan:** `knowledge-base/project/plans/2026-04-14-fix-one-shot-verify-deploy-and-apply-tf-plan.md`
**Issues:** Closes #2214, Closes #2215
**Branch:** `feat-one-shot-fix-verify-deploy-and-apply-tf-2214-2215`

## Phase 1 — Workflow hardening (#2214)

- [ ] 1.1 Re-read `.github/workflows/web-platform-release.yml` "Verify deploy script completion" step in the worktree (post-compaction read).
- [ ] 1.2 Insert `jq -e . >/dev/null 2>&1` guard block between the empty-body check and the three `jq -r` parses, with the "endpoint not ready" log message and `continue`.
- [ ] 1.3 Preserve the 12-space indentation of the existing `run: |` block (AGENTS.md hard rule: no base-indent violations).
- [ ] 1.4 Run `actionlint .github/workflows/web-platform-release.yml` — expect zero errors.
- [ ] 1.5 Local sanity-check the new branch logic with a simulated non-JSON body (see plan "Test Scenarios" → local dry-run).
- [ ] 1.6 Local sanity-check the valid-JSON path still parses correctly.

## Phase 2 — Learning capture

- [ ] 2.1 Write `knowledge-base/project/learnings/bug-fixes/2026-04-14-signed-get-verify-step-must-tolerate-non-json.md` documenting: the cold-start failure mode, the `bash -e` + `jq` interaction, the fix pattern (pre-parse guard with `jq -e .`), and the rule "any signed GET verify step in a release workflow must guard against non-JSON bodies."

## Phase 3 — PR prep

- [ ] 3.1 Run `npx markdownlint-cli2 --fix` on the new plan and learning files.
- [ ] 3.2 Run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` state checks (session-start hygiene already done).
- [ ] 3.3 Commit: `fix(ci): tolerate non-JSON body in verify-deploy step (#2214, #2215)`.
- [ ] 3.4 Push branch to remote.
- [ ] 3.5 Open PR with `Closes #2214\nCloses #2215` in body and `## Changelog` section.
- [ ] 3.6 Set labels: `semver:patch`, `bug`, `priority/p1-high`, `domain/engineering`.

## Phase 4 — Review + merge

- [ ] 4.1 Run `skill: soleur:review` (workflow + infra scope).
- [ ] 4.2 Run `skill: soleur:qa` if review flags runtime behavior uncertainty; otherwise skip (no UI surface).
- [ ] 4.3 Run `skill: soleur:compound` to capture learnings before commit.
- [ ] 4.4 Ship with `skill: soleur:ship`.
- [ ] 4.5 After merge, run `skill: soleur:postmerge` to verify release workflow succeeds.

## Phase 5 — Terraform apply (#2215 — operator action)

> Runs outside CI. Operator must have Doppler `prd_terraform` access and SSH agent with the server key.

- [ ] 5.1 From the repo root: `cd apps/web-platform/infra`.
- [ ] 5.2 Export R2 backend credentials:
      `export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)`
      `export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)`.
- [ ] 5.3 `doppler run --name-transformer tf-var -p soleur -c prd_terraform -- terraform init`.
- [ ] 5.4 `doppler run --name-transformer tf-var -p soleur -c prd_terraform -- terraform plan -out=/tmp/deploy-status.tfplan`.
- [ ] 5.5 Review plan — must show only `terraform_data.deploy_pipeline_fix` replacement. If anything else shows drift (especially `hcloud_server.web`, `hcloud_volume_attachment.workspaces`), STOP and triage.
- [ ] 5.6 `doppler run --name-transformer tf-var -p soleur -c prd_terraform -- terraform apply /tmp/deploy-status.tfplan`.
- [ ] 5.7 Verify endpoint: signed GET `https://deploy.soleur.ai/hooks/deploy-status` returns HTTP 200 + valid JSON (see plan "Verification — post-apply").

## Phase 6 — End-to-end release verification

- [ ] 6.1 Trigger `web-platform-release.yml` via `workflow_dispatch` (`skip_deploy: false`) OR wait for next natural push to `apps/web-platform/**`.
- [ ] 6.2 Watch the run — `Verify deploy script completion` step must log `ci-deploy.sh completed successfully for vX.Y.Z` and exit 0.
- [ ] 6.3 Close #2215 manually with evidence (apply output + endpoint response + successful release run URL). #2214 auto-closes via PR body.
- [ ] 6.4 Confirm `gh issue view 2214 --json state` and `gh issue view 2215 --json state` both return `CLOSED`.
