---
lane: cross-domain
requires_cpo_signoff: false
type: ops-remediation
classification: ops-only-prod-write
issue: 4144
related_issues: [4140, 4132, 4115, 4118, 4126]
---

# fix(infra): migrate TF `integrations/github` provider from PAT to App auth (closes #4144)

## Overview

`Apply deploy-pipeline-fix.yml` has been failing on every merge to `main` since PR-H #4066 (2026-05-19T21:41Z) because the workflow's `doppler run --name-transformer tf-var -- terraform apply` injects ALL Doppler `prd_terraform` keys as `TF_VAR_*`, and three required variables added by PR-H were never populated in Doppler:

- `github_app_client_secret`
- `github_actions_token`  ← **the PAT — eliminated by this PR**
- `doppler_token_kb_drift`

The downstream effect is real: the deploy webhook for `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.1` fails at `sudo: deploy : command not allowed` because the `terraform_data.deploy_pipeline_fix` resource — which writes `/etc/sudoers.d/deploy-inngest-bootstrap` — never re-applies (every workflow run errors before `terraform plan` evaluates the required-variable check).

Two of the three missing variables already have correct values stashed in Doppler (`GITHUB_APP_CLIENT_SECRET`, `DOPPLER_TOKEN_KB_DRIFT` — see "State already in place" in the parent ARGUMENTS). The third — `github_actions_token` — is a fine-grained PAT that:

1. Requires per-operator minting at `github.com/settings/personal-access-tokens/new` (manual gate, no API).
2. Expires (30/60/90 days, max 1y).
3. Is tied to one operator's identity — doesn't survive operator handoff.
4. Carries a rotation burden that has already been documented as a recurring source of CI breakage (this is the third such incident in 2026).

The `soleur-ai` GitHub App is already fully provisioned (App ID `3261325`, private key in Doppler `prd.GITHUB_APP_PRIVATE_KEY`) and the `integrations/github` Terraform provider has supported `app_auth` since v5.x. This PR migrates the provider block from PAT auth to App auth, then deletes `var.github_actions_token` outright. The PAT goes away.

The remaining four acceptance criteria (workflow re-run green, sudoers entry written, deploy webhook fires green, heartbeat green, Better Stack flip) are downstream cascade verifications that confirm the migration unblocked the pipeline end-to-end.

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user impact (operator-only deploy pipeline; Inngest cron jobs continue running on the prior image `v1.0.0` until the operator manually intervenes). The brand-survival risk is concentrated in continued operator opacity — the longer the deploy pipeline stays red, the higher the chance the next outage (data-shaped, user-shaped) is invisible until a customer reports it.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — the migration replaces operator-minted PAT with App-auth (private key in Doppler `prd.GITHUB_APP_PRIVATE_KEY`); no user-controlled data flows through the changed surface. The new authentication is strictly stronger (Apps don't carry per-operator identity, can be revoked at the org level, and have scoped permissions).

**Brand-survival threshold:** `aggregate pattern` — operator-only observability gap with no per-user incident. No CPO sign-off required per `hr-weigh-every-decision-against-target-user-impact`.

## Research Reconciliation — Spec vs. Codebase

| Claim from parent ARGUMENTS / issue body | Codebase reality (verified) | Plan response |
|---|---|---|
| `var.github_actions_token` deletion is sufficient to eliminate the PAT | Confirmed: only 4 grep hits across `apps/web-platform/infra/` (main.tf:60, variables.tf:180-184, kb-drift.tf:48-50 comments). No `.github/workflows/*.yml` reads the var directly. | Delete cleanly; update kb-drift.tf comment to reference App-auth. |
| `var.github_app_id` already exists | Confirmed at variables.tf:156-160 (`sensitive = true`, no default). | Reuse as-is for `app_auth.id`. |
| `var.github_app_private_key` already exists | Confirmed at variables.tf:162-166 (PEM string, `sensitive = true`). | Reuse as-is for `app_auth.pem_file` — the provider accepts PEM contents OR a path; we pass contents to avoid disk-write side effects in CI. |
| `var.github_app_installation_id` does NOT exist | Confirmed: no match in `variables.tf`. | Add new `variable "github_app_installation_id"` (string, sensitive). |
| Doppler `prd_terraform` already has `GITHUB_APP_INSTALLATION_ID` | Not verified — needs explicit Doppler write at apply time. | AC includes `doppler secrets set GITHUB_APP_INSTALLATION_ID=<discovered>` before the post-merge workflow re-run. |
| GitHub App permissions include `secrets: write` | Not verified — gated by App config UI at github.com/apps/soleur-ai. | AC includes `gh api /app/installations/<id>` permission probe; if missing, surface the one-time install-permission-grant URL (#4115 future work). |
| `integrations/github` v6.0 supports `app_auth { id, installation_id, pem_file }` | Provider docs (Terraform Registry, integrations/github 6.x) confirm — `app_auth` block has been stable since v5.x. main.tf:42-44 pins `~> 6.0`. | No version bump needed. |
| The Better Stack heartbeat `460830` is currently `paused=true` | Confirmed in parent ARGUMENTS; verifiable via `GET /api/v2/heartbeats/460830`. | Verify via API immediately before the PATCH unpause. |

## Hypotheses

- **H1 (primary):** The `Apply deploy-pipeline-fix.yml` workflow's `terraform plan` step fails on missing `TF_VAR_github_actions_token` because `doppler run --name-transformer tf-var` doesn't inject the variable (Doppler `prd_terraform` config has never had it). Verified by reading the workflow YAML (no `TF_VAR_github_actions_token` env, no `doppler secrets set` for it).
- **H2:** Migrating the provider to `app_auth` removes the variable dependency, and the workflow's existing `--name-transformer tf-var` flow picks up `TF_VAR_github_app_installation_id` once the operator writes it to Doppler. No workflow YAML changes needed.
- **H3:** The deploy webhook for v1.0.1 will succeed once `terraform apply -target=terraform_data.deploy_pipeline_fix` writes the sudoers entry; the OCI image is already on ghcr.

## Files to Edit

- `apps/web-platform/infra/main.tf` — replace `provider "github" { token = var.github_actions_token; owner = "jikig-ai" }` with the `app_auth` block.
- `apps/web-platform/infra/variables.tf` — delete `variable "github_actions_token"` block (lines 180-184); add `variable "github_app_installation_id"` (string, sensitive, no default).
- `apps/web-platform/infra/kb-drift.tf` — update the comment at lines 48-50 to reference App-auth (the resource itself doesn't change; `github_actions_secret` works identically under either auth scheme).
- `AGENTS.core.md` — add `[hr-github-app-auth-not-pat]` rule. Budget at 21962/22000 — needs trim of an existing rule to make room (see Phase 1.5 below).
- `AGENTS.md` — add pointer entry `- [id: hr-github-app-auth-not-pat] → core` under `## Hard Rules`.
- `plugins/soleur/skills/deepen-plan/SKILL.md` — add Phase 4.8 (PAT-shaped variable halt) that mirrors Phase 4.7's halt-on-detection pattern.
- `knowledge-base/project/specs/feat-one-shot-fix-4144-pat-to-app-auth/tasks.md` — derived from this plan (generated post-review).

## Files to Create

- `apps/web-platform/infra/scripts/get-app-installation-id.sh` — idempotent discovery script (reads `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` from Doppler, mints a JWT, calls `/orgs/jikig-ai/installation`, prints numeric ID to stdout). Output is non-sensitive (numeric ID, safe to log).
- `knowledge-base/project/learnings/bug-fixes/<topic>.md` — root cause + generalization note (App-auth-vs-PAT for infra-time GitHub writes). Filename author picks date at write-time per Sharp Edges.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` returned no matches for any of the files in `## Files to Edit` or `## Files to Create`.

## Domain Review

**Domains relevant:** engineering (CTO — infrastructure / Terraform provider migration / AGENTS.md rule addition).

### Engineering (CTO)

**Status:** assessed inline (Phase 2.5 carry-forward not applicable — no brainstorm exists for this work).
**Assessment:** Single-provider migration with a 4-line code change, gated behind GitHub App permission state. The architectural axis is well-precedented (App auth is the GitHub-recommended pattern for infra-time writes per the GitHub Apps documentation; PATs are explicitly deprecated for org-level automation). Risks are concentrated in (a) the operator-facing permission-grant gate if App permissions don't include `secrets: write`, and (b) the budget pressure on `AGENTS.core.md` (currently 21962/22000 — needs a trim before the new rule lands).

No Product, Legal, Finance, Marketing, Operations (CMO/CFO/COO/CRO), or Support (CCO) involvement — operator-only infra remediation, no user-facing surface.

## Infrastructure (IaC)

### Terraform changes

- **File:** `apps/web-platform/infra/main.tf`
  - Provider block (lines 58-62) is replaced:
    ```hcl
    # PR for #4144 — migrated from PAT (var.github_actions_token, expired/expires) to
    # GitHub App auth. App ID + installation_id are non-sensitive identifiers; the
    # PEM lives in Doppler prd.GITHUB_APP_PRIVATE_KEY (operator-supplied one-shot).
    provider "github" {
      owner = "jikig-ai"
      app_auth {
        id              = var.github_app_id
        installation_id = var.github_app_installation_id
        pem_file        = var.github_app_private_key
      }
    }
    ```
- **File:** `apps/web-platform/infra/variables.tf`
  - DELETE `variable "github_actions_token"` block (lines 180-184).
  - ADD:
    ```hcl
    variable "github_app_installation_id" {
      description = "Installation ID of the soleur-ai GitHub App on the jikig-ai org. Discoverable once via apps/web-platform/infra/scripts/get-app-installation-id.sh; stable thereafter."
      type        = string
      sensitive   = true
    }
    ```
- **Required providers + version pins:** No change — `integrations/github ~> 6.0` already pinned in main.tf:42-44; `app_auth` block has been stable since v5.x.
- **Sensitive variables (final list after migration):**
  - `TF_VAR_github_app_id` (existing, from `prd_terraform.GITHUB_APP_ID`)
  - `TF_VAR_github_app_private_key` (existing, from `prd_terraform.GITHUB_APP_PRIVATE_KEY`)
  - `TF_VAR_github_app_installation_id` (**new** — operator runs the discovery script once and pastes into Doppler `prd_terraform`)
  - `TF_VAR_github_app_client_secret` (existing — needed for github-app.tf, was missing before this PR, populated per parent ARGUMENTS)
  - `TF_VAR_doppler_token_kb_drift` (existing — populated per parent ARGUMENTS)

### Apply path

**(b) cloud-init + idempotent bootstrap script — implicit.** The change is to the provider block + a variable. No cloud-init or remote-exec is invoked by the migration itself. The post-merge re-run of `Apply deploy-pipeline-fix.yml` re-evaluates `terraform_data.deploy_pipeline_fix` (which is the sudoers-write resource) — its file/remote-exec provisioners then SSH to `135.181.45.178` and write `/etc/sudoers.d/deploy-inngest-bootstrap`. Expected downtime: zero (the existing sudoers state is "missing the new entry"; the apply only adds, never removes).

### Distinctness / drift safeguards

- `dev != prd` preconditions: `app_auth.installation_id` is per-org; the dev environment does not run `apps/web-platform/infra/*.tf` (this root is prd-only). N/A.
- `lifecycle.ignore_changes`: not needed on the provider block; the existing `ignore_changes = [value]` on `doppler_secret.github_app_*` (github-app.tf:31-37 etc.) is unaffected.
- State-storage notes: the App private key remains in `terraform.tfstate` (sensitive), same as before. No new sensitive surface introduced — `installation_id` is non-sensitive but we mark it `sensitive = true` defensively to keep it out of plan output.

### Vendor-tier reality check

- **GitHub App auth:** No tier gate. The `soleur-ai` App is owned by the org and has no per-installation cost.
- **Doppler:** No tier change — three existing variables, one new variable.

## Observability

```yaml
liveness_signal:
  what: "Apply deploy-pipeline-fix.yml run status on push to main"
  cadence: "Every merge that touches the 5 trigger paths in .github/workflows/apply-deploy-pipeline-fix.yml:36-42"
  alert_target: "GitHub Actions run page + the `apply-deploy-pipeline-fix.yml` workflow's existing `issues: write` post-failure annotation"
  configured_in: ".github/workflows/apply-deploy-pipeline-fix.yml (no changes — already wired)"

error_reporting:
  destination: "GitHub Actions step summary (existing) + the workflow's existing `Auto-close any open drift issues` step closes infra-drift issues on success, leaving failures visible in the open backlog."
  fail_loud: true

failure_modes:
  - mode: "GitHub App permission insufficient for `github_actions_secret` write"
    detection: "`terraform apply` fails on `github_actions_secret.doppler_token_kb_drift` with HTTP 403 from /repos/jikig-ai/soleur/actions/secrets/DOPPLER_TOKEN_KB_DRIFT"
    alert_route: "Workflow run fails red; operator opens the run, reads the error, follows the install-URL in the AC9 probe."
  - mode: "Doppler `prd_terraform.GITHUB_APP_INSTALLATION_ID` missing"
    detection: "`terraform plan` errors: `Error: No value for required variable github_app_installation_id`"
    alert_route: "Workflow run fails red; operator runs the discovery script and writes the value to Doppler."
  - mode: "App private key rotated in Doppler but Terraform state references stale key"
    detection: "Provider auth fails with 401 on the next `terraform plan`."
    alert_route: "Workflow run fails red; operator re-runs after Doppler refresh."

logs:
  where: "GitHub Actions run logs (retained 90 days per org default) + `terraform.tfstate` in R2 backend (R2 lifecycle: indefinite)."
  retention: "90 days for Actions logs; indefinite for state."

discoverability_test:
  command: "gh run list --workflow=apply-deploy-pipeline-fix.yml --branch=main --limit=1 --json conclusion,databaseId | jq '.[0]'"
  expected_output: '{"conclusion":"success","databaseId":<numeric>} on the first run after merge'
```

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 (TF provider migration):** `apps/web-platform/infra/main.tf` provider `"github"` block uses `app_auth { id, installation_id, pem_file }`; `token = var.github_actions_token` is removed. Verify with `grep -A 6 'provider "github"' apps/web-platform/infra/main.tf` — output contains `app_auth {` and NOT `token = var.github_actions_token`.
- **AC2 (var deletion):** `var.github_actions_token` removed from `apps/web-platform/infra/variables.tf`. Verify with `grep -c 'github_actions_token' apps/web-platform/infra/variables.tf` → `0`.
- **AC3 (var addition):** `variable "github_app_installation_id"` added to `apps/web-platform/infra/variables.tf` with `type = string` and `sensitive = true`. Verify with `grep -A 4 'variable "github_app_installation_id"' apps/web-platform/infra/variables.tf` → block contains `sensitive   = true`.
- **AC4 (no orphan refs):** No `.tf` file or `.github/workflows/*.yml` references `github_actions_token` or `TF_VAR_github_actions_token`. Verify with `git grep -nE 'github_actions_token|TF_VAR_github_actions_token' apps/web-platform/infra/ .github/workflows/` → no matches (kb-drift.tf comment updated; no live references remain).
- **AC5 (discovery script):** `apps/web-platform/infra/scripts/get-app-installation-id.sh` exists, is executable (`-rwxr-xr-x`), runs idempotently (re-running prints the same numeric ID), and writes nothing to disk except the captured JWT to a `mktemp -p /dev/shm`-style location that is deleted on EXIT. Verify with `bash apps/web-platform/infra/scripts/get-app-installation-id.sh 2>&1 | tail -1` → numeric ID matches `^[0-9]+$`.
- **AC6 (AGENTS.core.md trim before new rule):** Run `python3 scripts/lint-agents-rule-budget.py` BEFORE adding the new rule and confirm the post-trim baseline. Trim plan: demote `wg-block-pr-ready-on-undeferred-operator-steps` from core to rest (it's a workflow-gate that fires during `/ship`, which loads code-class — rest is loaded). Verify post-trim with the same lint script: `B_ALWAYS` should drop by ~400-500B, giving ≥500B headroom for the new ~450B rule.
- **AC7 (AGENTS.core.md rule add):** Add `[hr-github-app-auth-not-pat]` rule under "## Hard Rules" in `AGENTS.core.md`. Rule body ≤600B (per `cq-agents-md-why-single-line`). Verify with `awk '/hr-github-app-auth-not-pat/{found=1} found{print; if(/\[id: hr-github-app-auth-not-pat\]/)exit}' AGENTS.core.md | wc -c` ≤600.
- **AC8 (AGENTS.md index pointer):** Add `- [id: hr-github-app-auth-not-pat] → core` under "## Hard Rules" in `AGENTS.md`. Verify with `grep -c '\[id: hr-github-app-auth-not-pat\]' AGENTS.md` → `1`.
- **AC9 (deepen-plan Phase 4.8):** Add a new `### 4.8. PAT-Shaped Variable Halt (Always)` phase to `plugins/soleur/skills/deepen-plan/SKILL.md` that greps the target plan for `var.github_actions_token`, `TF_VAR_GITHUB_TOKEN`, `var\..*_pat\b`, `ghp_[A-Za-z0-9]{36,}` patterns inside fenced HCL/bash blocks AND halts with a message pointing at `hr-github-app-auth-not-pat`. Verify with `grep -c '4.8. PAT-Shaped Variable Halt' plugins/soleur/skills/deepen-plan/SKILL.md` → `1`.
- **AC10 (budget post-add):** Run `python3 scripts/lint-agents-rule-budget.py` and confirm `B_ALWAYS < 22000` (the harness ceiling). Net change after trim + add should leave ≥50B headroom.
- **AC11 (PR body):** PR body uses `Ref #4144` (NOT `Closes #4144`). The issue closes post-merge after the operator confirms the workflow re-run is green. Per `ops-remediation` classification.

### Post-merge (operator)

- **AC12 (Doppler write — automated via doppler CLI):** `doppler secrets set GITHUB_APP_INSTALLATION_ID=<value> -p soleur -c prd_terraform` where `<value>` is the output of the discovery script. Verify with `doppler secrets get GITHUB_APP_INSTALLATION_ID -p soleur -c prd_terraform --plain` → numeric. Automation feasible: `doppler` CLI is loaded.
- **AC13 (App permission check):** `gh api /app/installations/<id> | jq -r '.permissions.secrets'` returns `"write"`. If missing, the operator visits `https://github.com/organizations/jikig-ai/settings/installations/<id>/permissions/update` to grant `Repository permissions → Secrets: Read and write`, then re-runs the probe. Automation: read is automatable (`gh api`); the permission-grant click is the legitimate manual gate (vendor UI; #4115 tracks the Manifest-flow automation). Justification per `wg-block-pr-ready-on-undeferred-operator-steps`: GitHub App permission changes require an authenticated browser session at the org-owner level — no API.
- **AC14 (workflow re-run green):** `gh workflow run apply-deploy-pipeline-fix.yml --ref main` triggers a run that completes with `conclusion=success`. Verify with `gh run list --workflow=apply-deploy-pipeline-fix.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'` → `success`. Automation: `gh` CLI.
- **AC15 (sudoers entry written):** On-host `/etc/sudoers.d/` contains an entry permitting `deploy` to run the inngest-bootstrap command. Verify with `ssh root@135.181.45.178 'ls /etc/sudoers.d/'` → output contains a file matching `deploy-inngest-bootstrap` (or whatever name the TF resource writes — TBD pending read of `apps/web-platform/infra/inngest.tf` at /work time). Read-only SSH check; no host mutation.
- **AC16 (deploy webhook fires green):** Re-fire the v1.0.1 deploy webhook (signed HMAC + CF Access pattern in `apps/web-platform/infra/hooks.json.tmpl`); verify the webhook server logs `exit_code=0, reason=success`. Automation feasible: curl-based webhook fire is scriptable.
- **AC17 (heartbeat service green):** `ssh root@135.181.45.178 'systemctl is-active inngest-heartbeat.service'` returns `active`; `systemctl show inngest-heartbeat.service -p ExecMainStatus` → `ExecMainStatus=0`. Read-only SSH.
- **AC18 (Better Stack heartbeat flipped):** `PATCH https://uptime.betterstack.com/api/v2/heartbeats/460830` with `paused=false`, using `BETTERSTACK_API_TOKEN` from Doppler `prd_terraform`. Verify with `GET /api/v2/heartbeats/460830` → `paused=false`, AND wait 90s, then re-GET → `status=up`. Automation feasible: curl + Doppler. Must be the LAST step.
- **AC19 (issue closure):** `gh issue close 4144 --comment "Closed via PR #<N> (App-auth migration) + post-merge sudoers re-apply + heartbeat unpause."`. Automation: `gh` CLI. Also close #4132 (Better Stack programmatic unpause — this PR exercises that API end-to-end).

## Implementation Phases

### Phase 0 — Preconditions and discovery

0.1 Verify the working directory equals the worktree path:
```bash
test "$(pwd)" = "/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-4144-pat-to-app-auth" || exit 1
```
0.2 Confirm `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` are present in Doppler `prd`:
```bash
doppler secrets get GITHUB_APP_ID -p soleur -c prd --plain >/dev/null
doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd --plain | head -1 | grep -q 'BEGIN'
```
0.3 Read `apps/web-platform/infra/inngest.tf` to find the exact sudoers-entry resource name and the on-disk filename it writes — needed for AC15's verification grep.
0.4 Confirm `python3 scripts/lint-agents-rule-budget.py` baseline: 21962/22000 (38B headroom — too tight for the new rule without a trim).
0.5 Read `plugins/soleur/skills/deepen-plan/SKILL.md` to confirm the Phase 4.x section structure (Phase 4.5, 4.6, 4.7 exist; 4.8 is the next).

### Phase 1 — Discovery script (TDD)

1.1 Write `apps/web-platform/infra/scripts/get-app-installation-id.test.sh` first: assert that when `GITHUB_APP_ID` and a known-test PEM are passed via env, the script prints a numeric ID OR errors clearly (the test runs against the real Doppler-loaded values; not a fixture). Test is a smoke probe.
1.2 Implement `apps/web-platform/infra/scripts/get-app-installation-id.sh`:
- `set -euo pipefail`
- Read `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY` from env (caller does `doppler run ...` or `export`).
- Mint a JWT (RS256, 10-min expiry, `iss=<app_id>`) using `openssl` + base64url encoding (see the canonical form in `knowledge-base/project/learnings/best-practices/2026-05-05-workflow-jwt-mint-silent-failure-traps.md`).
- `curl --max-time 10 -sH "Authorization: Bearer $JWT" -H "Accept: application/vnd.github+json" https://api.github.com/orgs/jikig-ai/installation | jq -er .id`
- Trap on EXIT to `rm -f` the PEM tempfile.
1.3 Run the test against live Doppler:
```bash
doppler run -p soleur -c prd -- bash apps/web-platform/infra/scripts/get-app-installation-id.sh
```
Capture the numeric ID for use in 2.1.

### Phase 2 — Doppler population

2.1 `doppler secrets set GITHUB_APP_INSTALLATION_ID=<value-from-1.3> -p soleur -c prd_terraform`. The variable is consumed by `--name-transformer tf-var` as `TF_VAR_github_app_installation_id`. Verify with `doppler secrets get GITHUB_APP_INSTALLATION_ID -p soleur -c prd_terraform --plain` → numeric.
2.2 Sanity-check the existing presence of `GITHUB_APP_CLIENT_SECRET` and `DOPPLER_TOKEN_KB_DRIFT` per parent ARGUMENTS (already populated in the pre-work; this step is a read-only re-verification).

### Phase 3 — Terraform provider migration

3.1 Write the failing test first: `terraform validate` against the current state — confirm it errors with `Error: No value for required variable: var.github_actions_token` (when run without that var set). This is the RED state — the PAT dependency is real.
3.2 Edit `apps/web-platform/infra/main.tf` lines 58-62 to the `app_auth` form.
3.3 Edit `apps/web-platform/infra/variables.tf`: delete lines 180-184 (`var.github_actions_token`); add the `var.github_app_installation_id` block.
3.4 Edit `apps/web-platform/infra/kb-drift.tf` comment at lines 48-50 to reference `var.github_app_installation_id` + the App-auth path.
3.5 GREEN: `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform validate` (must pass after Phase 2.1 is done). Then run a no-op `terraform plan -target=github_actions_secret.doppler_token_kb_drift` and confirm the plan is `0 to add, 0 to change, 0 to destroy` (provider re-auth doesn't change resource state).

### Phase 4 — AGENTS.md rule + index pointer (with budget trim)

4.1 Verify current budget: `python3 scripts/lint-agents-rule-budget.py` → `B_ALWAYS=21962 (38B headroom)`.
4.2 **Trim:** demote `wg-block-pr-ready-on-undeferred-operator-steps` from `AGENTS.core.md` to `AGENTS.rest.md`. Justification per `cq-agents-md-tier-gate`: this gate fires during `/ship` (code-class diff — `AGENTS.rest.md` loads on code class). Update the index in `AGENTS.md` to `→ rest`. Re-run lint; expect `B_ALWAYS ≈ 21500`.
4.3 Add the new rule to `AGENTS.core.md` under `## Hard Rules`:

> When Soleur infra/CI needs to write GitHub repo state (Secrets, Releases, Issues, PRs, file commits) from infra-time or CI-time code paths, authenticate via GitHub App auth (App ID + installation_id + private key), never PAT/token-based auth [hr-github-app-auth-not-pat]. Apps don't expire, don't require per-operator minting, and survive operator handoff. **Why:** #4144 — PR-H's PAT dependency blocked the entire deploy pipeline for ~14 hours.

4.4 Add the index pointer to `AGENTS.md`: `- [id: hr-github-app-auth-not-pat] → core`.
4.5 Re-run `python3 scripts/lint-agents-rule-budget.py` → confirm `B_ALWAYS < 22000` with ≥50B headroom.

### Phase 5 — Deepen-plan Phase 4.8 gate

5.1 Write a test fixture: a synthetic plan file containing `var.github_actions_token` and `TF_VAR_GITHUB_TOKEN`. Confirm the deepen-plan halt fires (manual probe; deepen-plan doesn't have a unit test suite).
5.2 Edit `plugins/soleur/skills/deepen-plan/SKILL.md` to add `### 4.8. PAT-Shaped Variable Halt (Always)` after Phase 4.7:
- Grep the target plan for patterns matching `\bvar\.github_actions_token\b`, `\bTF_VAR_GITHUB_(?:TOKEN|PAT)\b`, `\bvar\.[a-z_]*_pat\b`, `\bghp_[A-Za-z0-9]{36,}\b` (the synthetic-token form is documented per `2026-05-15-github-push-protection-rejects-synthetic-tokens-in-plan-prose.md`; for that one we keep the placeholder-shape note and don't reject — only the literal-shape token in TF blocks rejects).
- On match, HALT with: `Error: Plan references PAT-shaped variable. Use GitHub App auth (App ID + installation_id + pem_file) per [hr-github-app-auth-not-pat].`
- Emit incident telemetry: `emit_incident hr-github-app-auth-not-pat applied "..."`.
- Pass-through on no match.

### Phase 6 — Commit and PR

6.1 Commit (Files-to-Edit + Files-to-Create) with `Ref #4144` in body, NOT `Closes #4144` (post-merge operator action gate per `ops-remediation` classification).
6.2 PR body includes the post-merge operator checklist (AC12-AC19) as a copy-pasteable block, with each step's automation form (gh / doppler / curl / ssh-readonly).

### Phase 7 — Post-merge remediation cascade

7.1 (AC12) Set `GITHUB_APP_INSTALLATION_ID` in Doppler `prd_terraform`.
7.2 (AC13) Probe App permissions; on `secrets != "write"`, post the install-URL to the PR and pause.
7.3 (AC14) `gh workflow run apply-deploy-pipeline-fix.yml --ref main`; wait for green.
7.4 (AC15) Read-only SSH: confirm `/etc/sudoers.d/deploy-inngest-bootstrap` (or equivalent) exists.
7.5 (AC16) Re-fire deploy webhook for v1.0.1; verify `exit_code=0`.
7.6 (AC17) Read-only SSH: `systemctl is-active inngest-heartbeat.service` → `active`.
7.7 (AC18) Better Stack PATCH unpause + verify status `up` within 90s.
7.8 (AC19) Close issues #4144 + #4132.

## Test Strategy

- **TF validate:** Phase 3.1 + 3.5 — RED before migration, GREEN after, no-op `terraform plan`.
- **Discovery script smoke:** Phase 1.3 — assert numeric output.
- **AGENTS budget:** Phase 4.5 — `python3 scripts/lint-agents-rule-budget.py` exits 0 with `B_ALWAYS < 22000`.
- **Deepen-plan halt:** Phase 5.1 — synthetic plan fixture triggers the halt.
- **Cascade:** Phases 7.x — each AC's verification command is the test.

Existing `package.json scripts.test` and `bun test plugins/soleur/test/components.test.ts` continue to pass (no skill-description budget impact — this work doesn't add a new skill).

## Risks and Sharp Edges

- **R1 — App permission gap:** If `permissions.secrets != "write"`, AC14 fails with HTTP 403 on `github_actions_secret`. Mitigation: AC13 probe runs BEFORE AC14; if the probe fails, the operator visits the install-permission URL once. #4115 tracks Manifest-flow automation that eliminates even this click.
- **R2 — AGENTS.md budget tight:** Current baseline 21962/22000; trim of `wg-block-pr-ready-on-undeferred-operator-steps` (~400-500B) gives runway. If the demotion is rejected at review, alternative trims: `hr-github-api-endpoints-with-enum` (terse rule, ~300B) or `wg-zero-agents-until-user-confirms` (~250B).
- **R3 — `wg-block-pr-ready-on-undeferred-operator-steps` demotion loader-class fit:** This gate fires during `/ship` (code-class diff with operator-checklist items in the PR body). `AGENTS.rest.md` loads on `code` class (see `.claude/hooks/session-rules-loader.sh:88-115`). Demotion is loader-safe. Verify by reading the loader before committing.
- **R4 — Better Stack PATCH timing:** Per parent ARGUMENTS, flipping `paused=false` before AC17 confirms the heartbeat service is green will trigger email alerts every 90s. Phase 7.8 is the LAST step; AC17 must pass first.
- **R5 — Existing PAT in Doppler:** If `prd_terraform.GITHUB_ACTIONS_TOKEN` is set (artifact of PR-H), it doesn't cause harm post-migration (no consumer), but it should be deleted to avoid future confusion: `doppler secrets delete GITHUB_ACTIONS_TOKEN -p soleur -c prd_terraform`. Add to Phase 7.

### Sharp Edges (general)

- **Plan-time empty-section sentinel:** A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares the threshold inline.
- **Filename without date:** Learning file in `Files to Create` is prescribed by topic only (`<topic>.md`); author picks date at write-time per Sharp Edges of plan skill.
- **PR-vs-issue probe:** Both `gh issue view N` and `gh pr view N` were verified for the 5 cross-referenced numbers (#4144, #4140, #4132, #4115, #4118, #4126). All resolve as issues (no PR-vs-issue conflation).
- **CLI form for `jq` filter:** The discovery script uses `jq -er .id` (raw output + error on missing). The `-er` combination is verified against `jq 1.6+`.
- **Trim of operator-step gate:** Demoting `wg-block-pr-ready-on-undeferred-operator-steps` core→rest applies to a `wg-*` rule (workflow gate, demotion permitted per CPO sign-off PR #3496 condition 3 — `hr-*` may NOT be demoted, but `wg-*` may).

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Just populate the PAT in Doppler and move on | Recurring class — third such operator-mint incident in 2026. Doesn't eliminate the underlying coupling. |
| Use a shared "soleur-bot" personal account's PAT | Still per-operator (creating the bot account requires a real owner); still expires; still requires per-operator handoff. |
| Migrate ALL provider blocks (cloudflare, hetzner, etc.) to App-equivalent auth in one PR | Out of scope. Cloudflare and Hetzner don't have App-auth equivalents; their tokens are role-scoped already. |
| Defer the migration; just populate the PAT in Doppler now and fix later | Risk: the PAT will expire mid-incident next time. The cost of the migration is small enough now that "later" never comes. |

## Related Issues

- **Closes (post-merge):** #4144 (root cause), #4132 (Better Stack programmatic unpause — exercised end-to-end in AC18).
- **Ref:** #4140 (separate downstream block, orthogonal), #4118 / #4126 (Inngest disaster-recovery gate, parent class), #4115 (GitHub App Manifest flow — future automation of the AC13 click).

## Post-Merge Verification

See AC12-AC19 above. Each is an automated step except AC13's permission-grant click (legitimate manual gate per `hr-never-label-any-step-as-manual-without` — vendor UI, no API).
