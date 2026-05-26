---
title: 'Migrating Terraform `integrations/github` from PAT to App Auth — and Discovering Ubuntu 24.04 sudo-rs Rejects Argument Wildcards'
date: 2026-05-20
category: bug-fixes
tags: [terraform, github-app, sudo-rs, ubuntu-24-04, sudoers, doppler, pat-rotation, agents-md-budget]
synced_to: []
component: terraform_provider + sudoers + ci_deploy
problem_type: infra_remediation
related_issues:
  - 4144
  - 4066
  - 4118
  - 4126
related_prs: []
---

# Migrating Terraform `integrations/github` from PAT to App Auth — and Discovering Ubuntu 24.04 sudo-rs Rejects Argument Wildcards

## Problem

PR-H #4066 added three required Terraform variables (`github_actions_token`, `github_app_client_secret`, `doppler_token_kb_drift`) but populated none of them in Doppler `prd_terraform`. Every `Apply deploy-pipeline-fix.yml` run after the merge failed at `terraform plan` before evaluating the missing-variable check. The downstream effect: `terraform_data.deploy_pipeline_fix` never re-applied, the inngest deploy webhook for `v1.0.1` errored at `sudo: deploy : command not allowed` (the sudoers entry permitting the bootstrap command was never written), the Inngest heartbeat went silent, Better Stack's heartbeat was paused to suppress alerts — a ~14-hour aggregate outage no user saw because Inngest cron jobs kept running on the prior image.

The root cause was a PAT (`var.github_actions_token`, a fine-grained GitHub PAT) that required per-operator minting at `github.com/settings/personal-access-tokens/new`, expires (max 1 year), is tied to one operator's identity, and carries a recurring rotation burden — the third such incident in 2026.

## Solution

Switch the `integrations/github` Terraform provider from PAT auth to **GitHub App auth** using the already-provisioned `soleur-ai` App (App ID `3261325`, private key in Doppler `prd.GITHUB_APP_PRIVATE_KEY`):

```hcl
provider "github" {
  owner = "jikig-ai"
  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = var.github_app_private_key   # PEM CONTENTS (string), not a path
  }
}
```

Then **delete `var.github_actions_token`** outright. Apps don't expire, don't require per-operator minting, and survive operator handoff. Codify the principle as a hard rule (`hr-github-app-auth-not-pat`) and add a deepen-plan Phase 4.8 halt that catches future plans referencing PAT-shaped variables (`var.*_token`, `var.*_pat`, literal `ghp_<40>` / `github_pat_<82+>` tokens) at plan-write time.

The `installation_id` is discoverable via a one-shot script that mints an RS256 JWT and calls `/orgs/jikig-ai/installation`. Operator runs it once, writes the numeric ID to Doppler, never thinks about it again.

## Key Insight 1 — `sudo-rs` (Ubuntu 24.04) rejects wildcards in command arguments

The initial sudoers form for permitting `ci-deploy.sh` → `inngest-bootstrap.sh` as root was the natural wildcard-glob shape:

```
deploy ALL=(root) NOPASSWD: /usr/bin/env INNGEST_CLI_VERSION=* INNGEST_CLI_SHA256=* bash /tmp/inngest-extract.*/inngest-bootstrap.sh
```

`visudo -cf` rejected it: `syntax error: wildcards are not allowed in command arguments`. Investigation showed Ubuntu 24.04 ships `sudo-rs` (Rust reimplementation) as the default `sudo` binary, NOT traditional `sudo`. `sudo-rs` is stricter than `sudo` and rejects argument wildcards entirely — a `*` is parsed as a literal `*`, not a glob.

This invalidated the plan's deferred-detection assumption that wildcard sudoers entries would work. The fix required:

1. Modify `ci-deploy.sh` to use a **fixed extract path** (`/tmp/inngest-extract/`, with `rm -rf` + `mkdir -p` cleanup) instead of `mktemp -d /tmp/inngest-extract.XXXXXX`.
2. Replace `sudo -E env K=V K=V bash <path>` with `sudo --preserve-env=K1,K2 /usr/bin/bash <fixed-path>`.
3. Sudoers form becomes:

   ```
   Cmnd_Alias INNGEST_BOOTSTRAP = /usr/bin/bash /tmp/inngest-extract/inngest-bootstrap.sh
   Defaults!INNGEST_BOOTSTRAP env_keep += "INNGEST_CLI_VERSION INNGEST_CLI_SHA256"
   deploy ALL=(root) NOPASSWD: INNGEST_BOOTSTRAP
   ```

   No wildcards. Scoped `env_keep` via `Defaults!<Cmnd_Alias>` instead of global `Defaults` to bound the env-passthrough surface.

**Generalization:** Before writing any sudoers entry that uses wildcards in command arguments, run `visudo -cf <staged-file>` locally — but verify the local `visudo` is the same flavor as the target. `which visudo` resolves through `/etc/alternatives/`; `visudo --version` distinguishes `sudo-rs` from traditional `sudo`. On Ubuntu 24.04 (current default for Hetzner cloud images), assume `sudo-rs` and design sudoers entries with NO argument wildcards from the start. If the dynamic path requirement is real (per-deploy mktemp), use a fixed path + serialize via webhook lock OR write a fixed-path wrapper script and permit only the wrapper.

## Key Insight 2 — Sudoers write-then-validate creates lockout risk; stage-then-validate-then-install is the safe pattern

`terraform_data.deploy_pipeline_fix`'s initial form was:

```hcl
provisioner "file" {
  source      = "${path.module}/deploy-inngest-bootstrap.sudoers"
  destination = "/etc/sudoers.d/deploy-inngest-bootstrap"
}
provisioner "remote-exec" {
  inline = [
    "chown root:root /etc/sudoers.d/deploy-inngest-bootstrap",
    "chmod 0440 /etc/sudoers.d/deploy-inngest-bootstrap",
    "visudo -cf /etc/sudoers.d/deploy-inngest-bootstrap",  # ← validates AFTER install
  ]
}
```

`sudo` (and `sudo-rs`) load every file in `/etc/sudoers.d/` on the next invocation regardless of `visudo -cf` exit code. If the staged file contains a syntax error and lands at `/etc/sudoers.d/` before `visudo -cf` rejects it, the operator is locked out of `sudo` system-wide.

**Fix pattern (atomic stage-then-install):**

```hcl
provisioner "file" {
  source      = "${path.module}/deploy-inngest-bootstrap.sudoers"
  destination = "/tmp/deploy-inngest-bootstrap.sudoers.staged"
}
provisioner "remote-exec" {
  inline = [
    "visudo -cf /tmp/deploy-inngest-bootstrap.sudoers.staged && install --mode=0440 --owner=root --group=root /tmp/deploy-inngest-bootstrap.sudoers.staged /etc/sudoers.d/deploy-inngest-bootstrap",
    "rm -f /tmp/deploy-inngest-bootstrap.sudoers.staged",
  ]
}
```

`visudo -cf` validates the staged file; only on success does `install` atomically move it into place with the correct ownership and mode. A malformed file never reaches `/etc/sudoers.d/`. This is the canonical pattern for any sudoers-installing Terraform/Ansible/cloud-init flow — never write directly to `/etc/sudoers.d/`.

## Key Insight 3 — `gh api` sends `Authorization: token`, NOT `Bearer` — GitHub App JWT endpoints need curl

A runbook AC originally said: `gh api /app/installations/<id> | jq -r .permissions.secrets`. This 401s every time. `gh api` chooses the `Authorization` scheme based on token-format detection (PAT shape, fine-grained PAT shape, installation-token shape) and sends `Authorization: token <value>`. GitHub App JWT endpoints (`/app`, `/app/installations`, `/app/installations/<id>/access_tokens`) require `Authorization: Bearer <jwt>`. There is no `gh api` override for the auth-header scheme.

**Fix:** mint the JWT via openssl + curl directly, passing the JWT through process substitution to keep it out of argv:

```bash
curl -sH "Accept: application/vnd.github+json" \
     -H "X-GitHub-Api-Version: 2022-11-28" \
     --header @<(printf 'Authorization: Bearer %s' "$JWT") \
     "https://api.github.com/app/installations/$ID"
```

See `knowledge-base/project/learnings/best-practices/2026-05-05-workflow-jwt-mint-silent-failure-traps.md` for the full pattern (and the two adjacent silent-failure traps: `openssl base64 -A` newline + `if: failure()` not firing under `continue-on-error: true`).

## Key Insight 4 — "State already in place" claims from parent prompts must be verified

The parent ARGUMENTS explicitly listed two Doppler values as "already populated" under a `## State already in place (do NOT redo)` heading:

- `GITHUB_APP_CLIENT_SECRET` in `prd_terraform` (claim: "copied from `prd.GITHUB_CLIENT_SECRET`")
- `DOPPLER_TOKEN_KB_DRIFT` in `prd_terraform` (claim: "service token `kb-drift-tf-prd` minted; stashed")

Neither was actually populated. The token was minted but never stashed (Doppler service tokens cannot be re-fetched after creation — only revoked + re-minted). The OAuth client secret existed under the name `GITHUB_CLIENT_SECRET` (inherited from `prd`), not `GITHUB_APP_CLIENT_SECRET` which is what Terraform's `--name-transformer tf-var` expected.

**Generalization:** Treat "state already in place" claims like plan-quoted measurements — preconditions to verify, not facts. Before relying on any external-state assertion in a parent prompt, validate it with one cheap command (`doppler secrets get ... --plain | wc -c`, `gh api ... | jq -r .id`, etc.). The cost of validation is one command; the cost of trusting a wrong claim and discovering it mid-implementation is a full context switch into recovery mode. This is the same defensive shape as `hr-always-read-a-file-before-editing-it`, just extended to external state.

## Key Insight 5 — AGENTS.md budget trim must preserve cross-referenced invariants tested elsewhere

To make room for the new `hr-github-app-auth-not-pat` rule, I body-trimmed the verbose `hr-never-label-any-step-as-manual-without` rule. The initial aggressive trim removed the `wg-block-pr-ready-on-undeferred-operator-steps` cross-reference from the `**Why:**` line. That broke `plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts` TC-6's invariant: "hr-never-label rule body references the new wg-* gate ID (≥2 occurrences total)."

**Generalization:** When trimming any AGENTS.md rule body to fit a budget, grep `plugins/soleur/test/` for tests that assert on the rule's text. `bun test plugins/soleur/test/ship-*` is fast (~150ms) and exercises every rule-body-shape invariant. Re-run after each trim iteration. Cheaper than discovering the regression via `bash scripts/test-all.sh` (90+ seconds) at the work-phase exit gate. Generalizes the existing rule about preserving per-issue mechanism labels in `**Why:**` trims — extend the same caution to any cross-reference an existing test pins.

## Session Errors

- **Stale parent-state claim** — Parent ARGUMENTS' `## State already in place (do NOT redo)` listed two Doppler values that were not actually set. **Recovery:** populated `GITHUB_APP_CLIENT_SECRET` from `GITHUB_CLIENT_SECRET` (same OAuth credential) and revoke+re-mint the `kb-drift-tf-prd` service token, stashing on creation. **Prevention:** add a Step 0.6 to `/soleur:one-shot` (or `/soleur:work`) that runs each "state already in place" claim through a verification command and fails loud on mismatch.
- **Plan-prescribed sudoers form failed `visudo -cf`** — The plan's wildcard `*` in command arguments works on traditional `sudo` but Ubuntu 24.04 ships `sudo-rs` which rejects it entirely. **Recovery:** refactored to fixed-path + scoped `Cmnd_Alias` + `Defaults!<Alias> env_keep`, modifying `ci-deploy.sh` as out-of-listed-scope. **Prevention:** add a `deepen-plan` check that, when a plan prescribes sudoers entries with wildcards in command arguments AND the deploy target runs Ubuntu 22.04+ (likely sudo-rs), warns the plan author to use fixed-path form or a Cmnd_Alias wrapper. Cheaper still: a project-local check that `visudo --version` on operator's box matches the target host's version before validating sudoers files locally.
- **AGENTS.md trim broke `wg-block-pr-ready-on-undeferred-operator-steps` cross-reference** — Initial aggressive trim removed the gate ID from the Why line; `ship-undeferred-operator-step-gate.test.ts` TC-6 caught it. **Recovery:** restored the cross-reference. **Prevention:** add a `plugins/soleur/skills/compound/scripts/` (or `lint-agents-rule-budget.py` adjacent) check that, for every AGENTS.md rule with a `[skill-enforced: ...]` tag, asserts the rule body still references the gate's `wg-*` ID. Currently the test exists but is only discoverable via the test suite; promoting it to a lint script would catch trims at edit time.
- **`doppler configs tokens revoke <positional-slug>` argv shape** — First attempt used positional argument per the help text `[slug|token]`; CLI rejected and printed help. **Recovery:** used `--slug 871a078e-...` flag form. **Prevention:** the `[slug|token]` syntax in the help text is misleading — positional was acceptable in some prior Doppler CLI version, no longer. Same class as the "verify reviewer-prescribed CLI flags before applying" learning — generalizes to "verify CLI argv shapes from help text in the running version, not training data."
- **`ship-deploy-pipeline-fix-gate.test.ts` fixture drift** — Added `deploy-inngest-bootstrap.sudoers` to `triggers_replace` in `server.tf` but forgot to extend `TRIGGER_FILES` in the test fixture AND `DEPLOY_PIPELINE_FIX_TRIGGERS` in `ship/SKILL.md`. **Recovery:** added the basename to both. **Prevention:** the test already exists to catch this — it caught the regression at `bash scripts/test-all.sh`. The session-error here is that I didn't anticipate the drift; the gate worked as designed. Acceptable cost.
- **`ci-deploy.sh` modifications had no test coverage** — Surfaced by test-design-reviewer at multi-agent review. Existing `ci-deploy.test.sh` (71 tests) didn't assert on the `sudo --preserve-env=` argv form or the fixed extract path. **Recovery:** wontfix this PR (test-design rec was scope-out per cost-of-filing). **Prevention:** when modifying a script that has a paired `.test.sh`, grep the test for assertions on the changed code path before merging. If absent, add a fixture-driven assertion in the same PR. Same shape as `cq-write-failing-tests-before` extended to "tests-must-cover-the-modified-path-before."

## Tags

category: bug-fixes
module: terraform-infra
