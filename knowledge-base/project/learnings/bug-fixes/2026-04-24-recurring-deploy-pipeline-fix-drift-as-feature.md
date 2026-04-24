---
date: 2026-04-24
category: bug-fixes
tags: [terraform, infra-drift, ci-deploy, recurring-pattern, ops-remediation]
related_issues: ["#2873", "#2874", "#2618", "#2234", "#1899", "#1505", "#1412", "#994", "#988", "#2881"]
related_prs: ["#2842"]
related_files:
  - apps/web-platform/infra/server.tf
  - apps/web-platform/infra/ci-deploy.sh
  - apps/web-platform/infra/webhook.service
  - apps/web-platform/infra/cat-deploy-state.sh
  - apps/web-platform/infra/hooks.json.tmpl
  - .github/workflows/scheduled-terraform-drift.yml
---

# Recurring `terraform_data.deploy_pipeline_fix` drift is a feature, not a bug

## The pattern (7 remediation cycles across 9 filed issues in ~6 weeks)

`#988` (2026-03-21) → `#994` → `#1412` → `#1505` → `#1899` → `#2234` (2026-04-15) → `#2618` (2026-04-19) → `#2873`+`#2874` (2026-04-23/24, same drift detected across two 12h cron ticks before the apply ran).

The drift workflow (`.github/workflows/scheduled-terraform-drift.yml`, cron `0 6,18 * * *`) auto-files a new issue on each tick until the apply lands, so the issue count slightly overstates the incident count — the remediation cycle count (one per operator apply) is the load-bearing number.

Every instance has the same shape: the scheduled drift workflow (`scheduled-terraform-drift.yml`, cron `0 6,18 * * *`) detects

```text
# terraform_data.deploy_pipeline_fix must be replaced
-/+ resource "terraform_data" "deploy_pipeline_fix" {
      ~ triggers_replace = (sensitive value) # forces replacement
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

Every resolution is the same: a human-authorized `terraform apply -target=terraform_data.deploy_pipeline_fix` against the `prd_terraform` Doppler config.

## Why this is by design

`apps/web-platform/infra/server.tf`:

- `hcloud_server.web` has `lifecycle.ignore_changes = [user_data, ssh_keys, image]` (`:43-49`, per `#967`) to prevent import-artifact-driven server replacement.
- Consequence: cloud-init never re-runs on the existing prod server, so any change to `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, or `hooks.json.tmpl` would stay on-disk locally and never reach the server.
- The `terraform_data.deploy_pipeline_fix` resource (`:209-269`, per `#2185`) is the **single intentional bridge**: a sha256 hash over those four inputs drives `triggers_replace`, forcing the resource to be destroyed and re-created (with `file` + `remote-exec` provisioners) whenever any input changes.

The drift IS the feature working. Each drift detection corresponds to a merged PR that edited one of the four trigger files:

- `#2873`/`#2874` → PR #2842 edited `ci-deploy.sh` (GIT_ASKPASS migration)
- `#2618` → PR #2187 added `cat-deploy-state.sh` and modified `hooks.json.tmpl`
- (and so on)

## What the "fix" is

Not a Terraform code change. A `terraform apply` ritual:

```bash
cd apps/web-platform/infra
doppler run -p soleur -c prd_terraform -- terraform apply -target=terraform_data.deploy_pipeline_fix -input=true
```

Per `hr-menu-option-ack-not-prod-write-auth`:

- Never pass `-auto-approve` — Terraform's interactive `yes` prompt is the load-bearing safety net.
- The apply requires per-command operator authorization, not a menu ack.
- `-target` scopes the blast radius to the one intentionally-drifting resource.

The apply takes ~10–15s: destroys, recreates, uploads 4 files via `file` provisioner, restarts `webhook.service` via `remote-exec`.

## What NOT to try

The 2026-04-24 plan (`knowledge-base/project/plans/2026-04-24-fix-infra-drift-deploy-pipeline-fix-2873-2874-plan.md`, "Alternative Approaches Considered" section) derives each rejection against `server.tf` line-by-line. Two are worth surfacing here because they are the most tempting future-agent mistakes:

- **CI auto-apply with `-auto-approve` on merge** — (a) Violates `hr-menu-option-ack-not-prod-write-auth`. (b) CI SSH keys are dummies per `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` — the `remote-exec` provisioner would fail in CI regardless.
- **Replace `triggers_replace` hash with `null` / no-op** — `terraform_data` requires a non-null `triggers_replace` for the replacement-forcing semantics; setting `null` silently no-ops and the `file` provisioners never run. Drift detection is suppressed but the script updates never reach the server.

Structural rejections (remove the resource entirely, drop `lifecycle.ignore_changes = [user_data]`, add an AGENTS.md rule) are covered in the plan's alternatives table with full server.tf references.

## The structural fix (deferred)

Each recurrence costs a planning + remediation cycle (~20 min of operator attention). The structural fix is a `/ship` post-merge gate that detects PRs touching the four trigger files and either prompts for `terraform apply` as part of the merge ritual or blocks merge until apply is scheduled.

Tracked in #2881 — not implemented in this PR. Implementation requires:

1. File-path matcher in `/ship` Phase 5.5 (conditional domain leader gates already exist there).
2. Doppler + SSH credentials in the shipping environment (currently operator-local only; `remote` claude-code-action workflows can't run terraform with prod creds).
3. A retry/resume path for when the operator can't schedule the apply immediately.

## Deep-dive references

- Resource definition: `apps/web-platform/infra/server.tf:209-269`
- Why cloud-init can't re-run: `apps/web-platform/infra/server.tf:43-49` (refs `#967`)
- Why the bridge is intentional: `apps/web-platform/infra/server.tf:212-215` (refs `#2185`), sync-comments at `apps/web-platform/infra/cloud-init.yml:130,139`
- SSH provisioner contract (agent-only, not `private_key = file(...)`): [`2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`](../2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md)
- Prod-write authorization rule: [`2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md`](../2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md)
- Plan-error vs drift exit codes: [`2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`](../2026-03-21-terraform-drift-dead-code-and-missing-secrets.md)

## Session Errors (PR #2880 session)

- **Worktree create reported success but the worktree did not materialize.** First invocation of `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create feat-one-shot-fix-infra-drift-2873-2874` printed `✓ Worktree created successfully!` but `git worktree list` and `ls .worktrees/<name>/` both returned empty. Second identical invocation worked. **Recovery:** re-ran the script. **Prevention:** always verify worktree presence post-invocation via `git worktree list | grep <name>` and `ls .worktrees/<name>/.git`, not the script's exit message alone. Candidate follow-up: add a `verify_worktree_exists` step inside `worktree-manager.sh create` that fails loudly if the directory is absent after the `git worktree add` succeeds.

- **Plan acceptance criterion prescribed `Closes #N` for an ops-remediation PR whose remediation is post-merge operator action.** Plan line 378 originally read `PR body includes Closes #2873 and Closes #2874`; since `Closes` auto-closes on merge but the drift isn't resolved until the operator runs `terraform apply` post-merge, this would create a false-resolved state. **Recovery:** multi-agent review caught it pre-merge; fixed inline to `Ref` with an explanatory note citing `wg-use-closes-n-in-pr-body-not-title-to`. **Prevention:** for plans with `classification: ops-only-prod-write` (or any `type: ops-remediation` where Phase N post-merge is operator work), acceptance criteria use `Ref #N` not `Closes #N`. The existing rule covers the general `Closes` semantics but doesn't surface this corner case — consider a Sharp Edge note on the `soleur:plan` skill for the `ops-remediation` class.
