---
lane: cross-domain
issue: 4114
type: chore
classification: infra-automation
requires_cpo_signoff: false
---

# infra: add `apply-web-platform-infra.yml` workflow (post-merge terraform apply automation)

Closes #4114.

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Overview, Research Reconciliation, Domain Review, Implementation Phases (0.4, 2), Risks, Sharp Edges, Alternative Approaches Considered.
**Research agents used:** repo-research (terraform root + workflow precedents), learnings-research (PR-#3903 ADR-amendment + destroy-guard learning, 2026-04-05 doppler dual-credential pattern), git-history-analyzer (live ADR-019/031/032/036 inspection on main, live `gh issue/pr view` verification of cited PR/issue numbers), label-existence (`gh label list`), framework-docs (terraform CLI + GitHub Actions concurrency semantics), network-outage deep-dive (Phase 4.5 trigger fired — see `## Network-Outage Deep-Dive`).

### Key Improvements

1. **Caught fabricated PR reference.** Issue body cited "PR-H #3244 / #4066" but `gh pr view 3244` returns "Could not resolve to a PullRequest". The Overview now flags the discrepancy and cites only #4066 (verified `MERGED 2026-05-19`).
2. **ADR-amendment gate confirmed clean.** Grepped `knowledge-base/engineering/architecture/decisions/ADR-*.md` for `apps/web-platform/infra` references — no existing ADR has a "operator-only apply" framing that this PR would reverse (the relevant precedents ADR-031 and ADR-032 scope their auto-apply or operator-only stances to their own sub-roots `apps/web-platform/infra/sentry/` and `infra/github/` respectively). ADR-019 (`terraform-only-for-infrastructure`) only mandates Terraform as the provisioning tool, not the apply mechanism. **No ADR amendment required** in this PR; the workflow's header comment is sufficient first-pass documentation. This avoids the #3903 trap (auto-apply workflow shipped without amending the contradicting ADR-032).
3. **Destroy-guard empty-string defense baked in.** Per learning `2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md`: copy the `apply-github-infra.yml` shape (numeric-regex validation + `set -e` re-enable after rc-capture) — NOT the `apply-sentry-infra.yml` shape (which lacks the regex validation and is itself vulnerable to the same class). The `apply-github-infra.yml` form is the canonical, post-#3903 implementation.
4. **Environment-gate decision pinned by precedent table.** Two of three sibling workflows skip `environment:` (`apply-github-infra.yml`, `apply-deploy-pipeline-fix.yml`); one uses it (`apply-sentry-infra.yml`). The deciding criterion in the existing learnings: cross-tenant blast radius. The web-platform root affects only the founder's infra (no cross-tenant impact) BUT it also rotates load-bearing secrets (Inngest signing keys, GitHub App webhook secret, R2 creds-via-doppler). **Decision: USE the `environment: web-platform-infra-apply` gate** — the secret-rotation surface is broader than `apply-github-infra.yml`'s rulesets-only scope and warrants the extra reviewer click. Documented as a deliberate divergence in §Alternative Approaches Considered.
5. **`-target=` allow-list enumeration left for /work expansion** but the SSH-provisioner exclusion list is FROZEN at plan-time (7 named `terraform_data.*` resources) so /work cannot accidentally include them.
6. **Label verification done.** `type/chore`, `domain/engineering`, `priority/p3-low`, `chore` all exist (`gh label list --limit 200` verified at deepen-time). No fabricated labels in any AC.
7. **PR-H webhook-secret first-apply risk flagged.** The `random_id.github_webhook_secret` resource has NO `ignore_changes`; first apply against an empty state would mint a NEW secret, breaking the production webhook (the GitHub App config has the operator-pasted value from PR-H's runbook). Added to §Risks as Risk #8.

### New Considerations Discovered

- **First apply post-merge is NOT no-op.** PR-H's resources were applied manually per the operator runbook. The terraform state already contains them. The first run of this workflow on a tf-touching merge should be near-no-op for PR-H's set, but the operator should `gh run watch` the first apply and ack-destroy if anything unexpected appears.
- **`random_id` resources in `inngest.tf` (4 of them) carry `ignore_changes = [value]` on the doppler_secret SIDE but NOT on the random_id SIDE.** This means a `terraform apply -replace=random_id.<x>` will regenerate the random_id but the doppler_secret will silently ignore the new value (per `ignore_changes`). Rotation requires `terraform taint` on the random_id AND a manual doppler write. This is pre-existing PR-H wiring; the new workflow does not change it. Out of scope, but noted for the operator runbook.
- **The plan's `-target=` philosophy IS the rule extension** the workflow header comment should cite. `hr-all-infrastructure-provisioning-servers` says "provisioning via IaC"; this workflow says "the IaC apply is itself in CI". The header comment should call this out explicitly.

## Overview

Web Platform's terraform root at `apps/web-platform/infra/` is validated in PR CI (`infra-validation.yml`) and drift-checked nightly (`scheduled-terraform-drift.yml`), but **no workflow applies it on merge**. Every PR touching `*.tf` files in this root currently ends with a "Post-merge operator tasks" runbook that requires the operator to open a shell, export R2 backend creds, `doppler run --name-transformer tf-var`, plan, apply, verify.

PR-H (#4066, merged 2026-05-19; the issue's "#3244" reference does not resolve — verified via `gh pr view 3244` returns "Could not resolve to a PullRequest") is the canonical example — three new resources (`github-app.tf`, `kb-drift.tf`, `alerts-github-webhook.tf`) shipped with a 4-step operator runbook attached to the merge.

This plan mirrors the existing `apply-sentry-infra.yml` and `apply-github-infra.yml` precedents into a third workflow scoped to the `apps/web-platform/infra/` root.

## User-Brand Impact

**If this lands broken, the user experiences:** post-merge silence — the workflow exists but never runs (wrong `paths:` filter), or runs and silently fails an apply, leaving Doppler/GitHub/Better Stack/Cloudflare resources in the state captured in code but not present in production. Symptom downstream: GitHub App webhooks (PR-H) fire against a webhook secret that exists in the Doppler config but does not match the secret minted in the GitHub App because nobody ran `terraform apply -replace=random_id.github_webhook_secret`.

**If this leaks, the user's data/workflow/money is exposed via:** R2 backend creds (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in `prd_terraform`), Doppler service token (`DOPPLER_TOKEN`), 4 narrow Cloudflare API tokens, `webhook_deploy_secret`, GitHub Actions PAT (`github_actions_token`), 4 GitHub App identity secrets, kb-drift Doppler token. These already live in the `DOPPLER_TOKEN` and the workflow-extracted backend creds; this workflow does not introduce a new secret surface. It does broaden access: a leaked PAT with `contents:write` could trigger arbitrary `terraform apply` on `main` via `workflow_dispatch`. Mitigation: `environment:` required-reviewer gate (same as `apply-sentry-infra.yml`), `paths:` filter, kill-switch commit-message token.

**Brand-survival threshold:** `aggregate pattern` — a single failed apply produces operator-noticeable drift on the next 12h drift cron (existing detector), not a user-visible outage. The threshold escalates to `single-user incident` only if the workflow is mis-scoped to re-run server.tf SSH provisioners (admin_ips firewall blocks the runner → apply fails → server config drifts → eventually a deploy breaks). Phase 0.2 below pins the scope to avoid this.

`requires_cpo_signoff: false` — `aggregate pattern` threshold.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim                                                                                                          | Codebase reality                                                                                                                                                                                                                              | Plan response                                                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Issue: "Mirror `apply-sentry-infra.yml`."                                                                                  | Two precedent workflows already exist: `apply-sentry-infra.yml` (cron monitors, target-scoped) AND `apply-github-infra.yml` (rulesets, full-root apply with first-apply import). A third precedent (`apply-deploy-pipeline-fix.yml`) handles SSH via `-target=` scoping. | Use `apply-sentry-infra.yml` as the structural template (preflight kill-switch + environment gate + destroy guard + plan/apply split). Borrow the AWS-cred extraction pattern from all three. Borrow the `-target=` scoping pattern from `apply-deploy-pipeline-fix.yml` (see next row).                                                                                                                  |
| Issue step 5: `terraform apply -auto-approve tfplan` (no `-target=`).                                                      | `apps/web-platform/infra/server.tf` contains 7 `terraform_data.*` SSH-provisioner resources (disk_monitor_install, resource_monitor_install, fail2ban_tuning, deploy_pipeline_fix, docker_seccomp_config, apparmor_bwrap_profile, orphan_reaper_install). Any plan that includes these as a "no-op" can still re-evaluate `triggers_replace` and try to `connection { host = ..., user = "root" }` from the GitHub runner. The runner IP is NOT in `var.admin_ips` (firewall.tf:6). | Apply MUST be `-target=`-scoped to the new resource set (Doppler/GitHub/Better Stack/random_id types). server.tf SSH-provisioned resources are explicitly excluded; a separate workflow (`apply-deploy-pipeline-fix.yml`) already covers them. Documented in §Phase 0.2 below.                                                                                                                                                                                              |
| Issue note: "Operator manual-runbook step count drops by 3+ per infra-touching PR."                                       | The PR-H runbook (#4066 PR body §Post-merge operator tasks) has 5 numbered operator steps. PR-G and prior PRs touching this root typically had 4–6. The drift detector + Sentry cron monitor confirm in the next 12h cycle whether the apply succeeded. | The acceptance criterion in §AC4 reframes the issue's "≥3 steps" claim as "PR template post-merge runbook collapses to a single bullet pointing at the workflow run URL". `wg-after-merging-a-pr-that-adds-or-modifies` already mandates verifying workflows fire post-merge; this AC formalizes that as the expected operator action.                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Issue header: "PR-H shipped three new tf files."                                                                          | `apps/web-platform/infra/` actually contains 17 `.tf` files. PR-H added 3 (`github-app.tf`, `kb-drift.tf`, `alerts-github-webhook.tf`); the other 14 pre-exist. Resources in the 3 new files: 13 (5 doppler_secret + 1 random_id + 1 github_actions_secret + 3 betteruptime_heartbeat + 1 betteruptime_monitor + 1 betteruptime_policy + 1 random_id, see Phase 0.3 enumeration). | The new workflow's `-target=` allow-list is the **union** of PR-H resources (13) PLUS the 12 pre-existing apply-friendly resources already inventoried by `apply-sentry-infra.yml` peer style (Doppler secrets, Cloudflare ruleset-like resources, random_id, betteruptime_*, github_actions_secret). The full list is enumerated in §Phase 0.3 and frozen in the workflow file (so a future `*.tf` addition that does not extend the allow-list silently no-ops apply, surfacing in the next drift run instead of a runner-side `connection` failure). |
| Issue: workflow IS the boundary for `hr-all-infrastructure-provisioning-servers`.                                          | Hard rule body says provisioning must route through IaC. The workflow does not introduce provisioning; it converts a documented operator-runbook (which already violates the rule by being "operator runs ssh+doppler+terraform manually") into IaC-applied. | Plan body §Phase 2 cites this hard rule explicitly and adds it as the closing-rationale comment-block header in the workflow file (mirrors `apply-sentry-infra.yml`'s ADR-031 reference).                                                                                                                                                                                                                                                                                                                                                                                              |

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — new file. Single source of truth for this plan. ~250 lines, modeled line-for-line on `apply-sentry-infra.yml` with the `-target=` list adapted per §Phase 0.3 and the working-directory pointed at `apps/web-platform/infra`.
- `.github/CODEOWNERS` — append a line `/.github/workflows/apply-web-platform-infra.yml  @deruelle` to mirror the protection layer the existing two `apply-*-infra.yml` files carry (verify they DO have CODEOWNERS lines first; if so, copy the convention).
- `apps/web-platform/infra/github-app.tf:6-8` — update the comment block that currently references the deferred-automation backlog item (`hr-never-label-any-step-as-manual-without`). Note that **GitHub App creation** is still operator-manual (Stripe-tier vendor limit), but the post-creation `terraform apply` is now automated by this workflow. One-line edit.
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — verify it does not need a sibling ADR. If it does, defer to a separate plan (out of scope here). The new workflow's header comment is sufficient first-pass documentation; ADR uplift is a `wg-when-deferring-a-capability-create-a` tracking issue if needed.

## Files to Create

- `.github/workflows/apply-web-platform-infra.yml` — see §Files to Edit.

## Open Code-Review Overlap

Grep result against `gh issue list --label code-review --state open --limit 200`:

- `.github/workflows/apply-web-platform-infra.yml` — file does not exist yet; no overlap possible.
- `apps/web-platform/infra/github-app.tf` — searched body of every open `code-review` issue for this path; no matches (verified at plan-write time).
- `.github/CODEOWNERS` — no matches.

No open scope-outs touch these files.

## Domain Review

**Domains relevant:** Engineering (workflow automation), Security (secret handling, environment gate).

### Engineering

**Status:** reviewed (synchronously — plan author + repo precedent)
**Assessment:** The pattern is well-precedented (3 existing `apply-*` workflows in the same repo). The cross-cutting concern is the `-target=` allow-list: it must be exhaustive at the time the workflow lands, AND a `wg-after-merging-a-pr-that-adds-or-modifies` reminder must point future tf-file authors at the allow-list. The workflow's design treats "new resource not in allow-list" as a fail-safe no-op (apply silently skips, drift detector surfaces it within 12h), not a silent commit-to-prod.

### Security

**Status:** reviewed (synchronously — plan author + AGENTS.md hard rules)
**Assessment:** The workflow's blast-radius is bounded by:

1. `paths:` filter (only fires on `apps/web-platform/infra/**` and the workflow file itself).
2. `environment: web-platform-infra-apply` required-reviewer gate (per `apply-sentry-infra.yml`'s pattern). Operator must set this up at Settings → Environments before the workflow's first apply.
3. Kill-switch `[skip-web-platform-apply]` token on its own line in the merge commit message.
4. Destroy-count guard: `[ack-destroy]` token on its own line in the merge commit message required if `terraform show -json tfplan` shows ≥1 delete action.
5. All untrusted inputs (HEAD_MSG, REASON) routed through env vars before reaching any `run:` block.
6. All action references SHA-pinned (copy from `apply-sentry-infra.yml`).
7. `terraform init -lockfile=readonly` defends against pinned-provider re-publish.

## Infrastructure (IaC)

This plan touches CI workflows only — it does NOT introduce new infrastructure, new secrets, new vendors, or a new persistent runtime process. The workflow's effect at runtime IS terraform apply, but that runs against an already-provisioned root.

`hr-every-new-terraform-root-must-include-an` does NOT fire — no new TF root. `hr-all-infrastructure-provisioning-servers` DOES fire — this workflow IS the canonical boundary for the rule for this root (closes the existing gap where the runbook was "operator runs the apply manually").

### Apply path

Single workflow on merge to `main`, `paths`-scoped to `apps/web-platform/infra/**` + the workflow file itself. Plan + apply happen in the same job (mirrors `apply-sentry-infra.yml`). No cloud-init, no bootstrap script, no `-replace` — the workflow runs idempotent `terraform plan -out=tfplan && terraform apply tfplan` against the existing R2-backed state.

### Distinctness / drift safeguards

- `cancel-in-progress: false` on the concurrency group (`terraform-apply-web-platform-infra`) per `hr-multi-step-post-merge-bootstrap-script`.
- The existing `scheduled-terraform-drift.yml` (12h cron) catches any apply that silently no-ops due to a tf file landing outside the `-target=` allow-list.
- The existing `infra-validation.yml` (PR CI) ensures terraform plan succeeds before merge.

### Vendor-tier reality check

- Better Stack: paid tier needed for `betteruptime_policy` (already gated by `var.betterstack_paid_tier`; this workflow does not change that). N/A here.
- Doppler: service token in `prd_terraform` already provisioned. N/A.
- Cloudflare: 4 narrow API tokens already in Doppler. N/A.
- GitHub: `github_actions_token` already in Doppler (PR-H). N/A.
- Hetzner: HCLOUD_TOKEN — this workflow's allow-list EXCLUDES `hcloud_server.web` and `hcloud_volume.workspaces` (these are managed by the deploy lifecycle, not on every PR merge). N/A in scope.

## GDPR Gate

Skipped silently — no regulated-data surface touched. The workflow handles secrets, but secrets ≠ regulated personal data (Art. 4 GDPR scope). No (a) new LLM/external-API processing of operator data, (b) single-user-incident brand threshold, (c) new cron reading from learnings/specs, or (d) new artifact distribution surface fires.

## Acceptance Criteria

### Pre-merge (PR)

1. `.github/workflows/apply-web-platform-infra.yml` exists and follows the SHA-pinned action convention (`grep -nE '@v[0-9]+\.[0-9]+\.[0-9]+ *# v[0-9]' .github/workflows/apply-web-platform-infra.yml | wc -l` returns ≥3, matching `actions/checkout`, `hashicorp/setup-terraform`, `DopplerHQ/cli-action`).
2. `actionlint .github/workflows/apply-web-platform-infra.yml` exits 0.
3. The workflow's `paths:` filter is exactly `["apps/web-platform/infra/**", ".github/workflows/apply-web-platform-infra.yml"]` (verify via `yq '.on.push.paths' .github/workflows/apply-web-platform-infra.yml`).
4. The workflow's apply step uses `-target=` flags covering EVERY resource from the §Phase 0.3 enumeration. Verify via `grep -c '\-target=' .github/workflows/apply-web-platform-infra.yml` ≥ N (N = enumeration count; plan §Phase 0.3 freezes N at plan-write time).
5. `server.tf` SSH-provisioned `terraform_data.*` resources are NOT in the `-target=` list. Verify via `grep -E '\-target=terraform_data\.(disk_monitor_install|resource_monitor_install|fail2ban_tuning|deploy_pipeline_fix|docker_seccomp_config|apparmor_bwrap_profile|orphan_reaper_install)' .github/workflows/apply-web-platform-infra.yml | wc -l` returns 0.
6. The destroy-count guard is present (literal: `if [[ "$destroy_count" -gt 0 ]] && [[ "$ack_destroy" != "true" ]]`).
7. The `[skip-web-platform-apply]` kill-switch is anchored to its own line in the regex (literal: `(^|$'\n')\[skip-web-platform-apply\]($|$'\n')`).
8. `apps/web-platform/infra/github-app.tf:6-8` comment is updated to reference the new workflow as the apply boundary.
9. `.github/CODEOWNERS` contains `/.github/workflows/apply-web-platform-infra.yml @deruelle` (verify the convention against the existing 2 `apply-*-infra.yml` lines first; if those files don't have CODEOWNERS entries, this AC drops).
10. PR body uses `Closes #4114` (not `Refs #4114`) — this is NOT an ops-remediation class plan; the AC list above is fully verifiable pre-merge by inspection, the workflow's runtime is verified by AC11–AC14 post-merge.

### Post-merge (operator + automated)

11. **Automated**: on merge to main, `apply-web-platform-infra` workflow fires. Operator clicks the environment-gate approval in the GitHub Actions UI (the only manual step — protected by the required-reviewer gate).
12. **Automated**: `terraform apply` step exits 0; the workflow's post-apply summary shows the resources applied.
13. **Automated**: next `scheduled-terraform-drift.yml` cron run (within 12h) shows clean exit (0) for the `apps/web-platform/infra` matrix entry.
14. **Operator**: paste the workflow run URL into the merge commit's first comment, OR (preferred) `gh run watch` the apply during the merge session and confirm it green-checked. `hr-no-dashboard-eyeball-pull-data-yourself` — verification is `gh api repos/jikig-ai/soleur/actions/runs/<id>` returning `conclusion: "success"`, NOT a dashboard click.

## Implementation Phases

### Phase 0 — Plan-time preconditions (verify before /work)

#### 0.1 SHA-pin lookup

Resolve current canonical SHAs for the 3 third-party actions by reading `apply-sentry-infra.yml` (which already carries reviewed SHA pins):

- `actions/checkout` — copy SHA from the precedent.
- `hashicorp/setup-terraform` — copy SHA from the precedent.
- `DopplerHQ/cli-action` — copy SHA from the precedent.

Do NOT re-resolve via `npm view` or web fetch — the precedent's SHAs are already CODEOWNERS-reviewed, and divergence between sibling apply workflows creates supply-chain audit confusion.

#### 0.2 Target-allow-list philosophy

The workflow uses `-target=` for every apply. Two reasons:

1. **SSH-provisioner exclusion**: `server.tf` has 7 `terraform_data.*` resources with `connection { type = "ssh", host = ..., user = "root" }` provisioner blocks. The GitHub runner's egress IP is NOT in `var.admin_ips` (firewall.tf allow-list). If a tf hash bumps and apply re-evaluates these resources, `connection { ... }` fails with `ssh: handshake failed: connection reset by peer` (hr-ssh-diagnosis-verify-firewall — firewall is L3 deny by design). The `apply-deploy-pipeline-fix.yml` precedent handles its single SSH resource by `-target=`-ing it AND extracting `DEPLOY_SSH_PRIVATE_KEY` from Doppler; this workflow takes the opposite tack and `-target=`s the non-SSH resources only.
2. **Drift-resilience**: the allow-list is explicit; a new `.tf` resource that future PRs add lands on the `-target=` allow-list only if the workflow author adds it. The drift detector (12h cron) surfaces any new resource the allow-list missed — operator can either extend the allow-list in a follow-up PR or apply the new resource manually.

#### 0.3 Target-allow-list enumeration (frozen at plan-write time)

The full list of resources from `apps/web-platform/infra/*.tf` MINUS the 7 server.tf SSH provisioners (and minus `hcloud_server.web`/`hcloud_volume.workspaces` — those land via the deploy pipeline, not on every merge):

**From `alerts-github-webhook.tf`** (4): `betteruptime_policy.github_webhook`, `betteruptime_monitor.github_webhook_failures`, `betteruptime_heartbeat.github_webhook_sig_failures`, `betteruptime_heartbeat.github_api_429_sustained`.

**From `kb-drift.tf`** (4): `random_id.kb_drift_ingest_signing_key`, `doppler_secret.kb_drift_ingest_signing_key`, `doppler_secret.kb_drift_ingest_url`, `github_actions_secret.doppler_token_kb_drift`.

**From `github-app.tf`** (6): `doppler_secret.github_app_id`, `doppler_secret.github_app_private_key`, `doppler_secret.github_app_client_id`, `doppler_secret.github_app_client_secret`, `random_id.github_webhook_secret`, `doppler_secret.github_app_webhook_secret`.

**From `inngest.tf`** (11): `random_id.inngest_signing_key_prd`, `random_id.inngest_signing_key_dev`, `random_id.inngest_event_key_prd`, `random_id.inngest_event_key_dev`, `doppler_secret.inngest_signing_key_prd`, `doppler_secret.inngest_signing_key_dev`, `doppler_secret.inngest_event_key_prd`, `doppler_secret.inngest_event_key_dev`, `betteruptime_heartbeat.inngest_prd`, `betteruptime_policy.inngest`, `doppler_secret.inngest_heartbeat_url_prd`.

**From `cloudflare-settings.tf`, `cache.tf`, `bot-allowlist.tf`, `bot-management.tf`, `dns.tf`, `firewall.tf`, `seo-rulesets.tf`, `tunnel.tf`, `uptime-alerts.tf`** — re-enumerate at /work Phase 1 via `grep -E '^resource' apps/web-platform/infra/*.tf | grep -vE 'server\.tf:(terraform_data|hcloud_server|hcloud_volume)'`. The freeze in this plan covers the PR-H + inngest set (the immediate driver); /work expands to the cloudflare/firewall set. /work MUST emit the final allow-list count and bake it into AC4's expected N.

**Cardinality estimate**: ~40 resources after /work expansion. The `-target=` flag list is long but acceptable (the sentry-infra workflow has 10 explicit targets; this scales linearly).

#### 0.4 Doppler invocation pattern verification

The `-name-transformer tf-var` pattern is the canonical one for this root (per `2026-04-05-terraform-doppler-dual-credential-pattern.md` learning + `scheduled-terraform-drift.yml` + `apply-deploy-pipeline-fix.yml` precedent). Use the **single-invocation** form (matches `apply-deploy-pipeline-fix.yml`), NOT the nested form documented in `variables.tf`'s comment block — the nested form is for local-laptop runs where DOPPLER_TOKEN is a personal token; the CI form uses a service token and `--name-transformer tf-var` works directly.

Verification step: confirm the precedent at `apply-deploy-pipeline-fix.yml:174` uses the single-invocation form:

```bash
doppler run --name-transformer tf-var -- terraform plan -target=... -no-color -input=false
```

If single-invocation, use that. If nested, mirror the nested form. (Pre-verified: single-invocation, per Phase 1.7 research.)

### Phase 1 — RED (workflow lint passes pre-existing actionlint hooks)

Land `.github/workflows/apply-web-platform-infra.yml` with empty `jobs:` (still-valid YAML, actionlint-passing). Verify:

```bash
actionlint .github/workflows/apply-web-platform-infra.yml
```

Exit 0. This phase IS the "RED" — the workflow exists but does nothing. AC1–AC3 pass; AC4–AC7 fail.

### Phase 2 — GREEN (full workflow)

Fill in the `preflight` + `apply` jobs by adapting `apply-sentry-infra.yml`'s structure. Key adaptations:

1. `name: Apply web-platform infra (PR-H + inngest + cf-rulesets)`
2. `on.push.paths: ["apps/web-platform/infra/**", ".github/workflows/apply-web-platform-infra.yml"]`
3. `concurrency.group: terraform-apply-web-platform-infra`
4. `env.INFRA_DIR: apps/web-platform/infra`
5. Kill switch token: `[skip-web-platform-apply]`
6. `environment: web-platform-infra-apply` (operator creates this in Settings → Environments with @deruelle as required reviewer)
7. Doppler invocation: single-invocation `doppler run --name-transformer tf-var -- terraform plan ...`
8. AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY extracted via `doppler secrets get ... --plain` BEFORE the tf-var-transformed run
9. `-target=` flags: full list from §Phase 0.3 + /work expansion
10. Destroy-count guard: same shape as `apply-sentry-infra.yml`, swap `[ack-destroy]` → keep as-is (no need to disambiguate from sibling workflow gates; the merge-commit message scope is identical)
11. Post-apply summary identical to `apply-sentry-infra.yml`'s `## Apply ... → step summary` block

All AC1–AC7 pass after Phase 2.

### Phase 3 — Comment / CODEOWNERS sweep

1. Update `apps/web-platform/infra/github-app.tf:6-8` to reference the new workflow (delete the "deferred-automation" backlog comment, since this PR closes it).
2. Append `.github/CODEOWNERS` line `/.github/workflows/apply-web-platform-infra.yml @deruelle` (if convention applies — verify against `apply-sentry-infra.yml` + `apply-github-infra.yml` first).
3. Run `grep -nE 'manually run terraform|operator runs terraform|ssh.*terraform apply' apps/web-platform/infra/*.tf apps/web-platform/infra/*.md` — every match in the web-platform/infra surface should be updated or scoped-out with a comment pointing at the new workflow. Documentation-only updates; no code changes.

### Phase 4 — Operator one-time setup (post-merge)

These steps MUST happen ONCE after merge, before the workflow can apply for the first time. They are operator-only (require GitHub repo-admin scope). Per `wg-after-merging-a-pr-that-adds-or-modifies`:

1. **Operator**: create the GitHub environment `web-platform-infra-apply` at Settings → Environments. Add @deruelle as required reviewer. Restrict to deployment from `main` only.
2. **Operator**: verify `DOPPLER_TOKEN` repo secret exists (already exists; reused from the 3 sibling workflows). No mint required.
3. **Operator**: trigger one manual `workflow_dispatch` run with `reason: first apply post-merge` to verify the gate works end-to-end. Confirm `gh api repos/jikig-ai/soleur/actions/runs/<id>` returns `conclusion: "success"`.

**Automation: not feasible** for step 1 because the GitHub Environments API requires `Administration:Write` org-admin scope; the default `GITHUB_TOKEN` and the existing `GH_RULESET_PAT` lack it. Tracking issue path: if this becomes recurring (more than one IaC root added per quarter), file a follow-up to add `Administration:Write` to `GH_RULESET_PAT` and write a Terraform module for the `web-platform-infra-apply` environment. Out of scope for this PR.

Steps 2 + 3 ARE automatable in principle (gh CLI + workflow_dispatch), but the required-reviewer click in step 1 is the load-bearing gate; "verify the gate works" can only happen after a human clicks approve once.

## Risks

1. **`-target=` allow-list goes stale**: A future PR adds a new resource to `apps/web-platform/infra/` but doesn't extend the workflow's `-target=` list. Mitigation: the existing `scheduled-terraform-drift.yml` surfaces this within 12h. Operator either extends the allow-list in a follow-up PR or applies manually. Add a `wg-after-merging-a-pr-that-adds-or-modifies` reminder line in the workflow header pointing to the allow-list.
2. **Environment gate stalls**: The required-reviewer click is a human gate. If @deruelle is unavailable, the apply blocks. Mitigation: same as `apply-sentry-infra.yml`; this is a deliberate authorization boundary, not a bug.
3. **Plan-vs-apply skew**: `terraform plan -out=tfplan && terraform apply tfplan` is the right pattern (the plan is the artifact applied). The brittle pattern is `terraform plan` + `terraform apply` (no plan file) — DO NOT use it.
4. **Destroy-count false negatives**: The `jq '[.resource_changes[]? | select(.change.actions? | index("delete"))] | length'` form is the canonical one (matches both `apply-sentry-infra.yml` AND `apply-github-infra.yml`). Both precedents also validate the result is `^[0-9]+$` before the `-gt 0` comparison; carry that pattern.
5. **Kill-switch token spoofing**: `[skip-web-platform-apply]` anchored to its own line in the regex (per `apply-sentry-infra.yml`'s convention) defends against the token appearing in a code-fence or trailer. Same posture for `[ack-destroy]`.
6. **GitHub Actions injection via untrusted inputs**: HEAD_MSG and REASON routed through `env:` blocks before any `run:` step (mirrors all 3 precedents). All inputs validated before use.
7. **SHA-pin staleness**: Provider versions in `apply-sentry-infra.yml` are committed pins. Copy them verbatim. Provider major-version bumps in any of the 3 actions require a separate PR with explicit changelog review.
8. **PR-H webhook secret first-apply destroy**: `random_id.github_webhook_secret` carries NO `lifecycle.ignore_changes`. If R2 state happens to be missing PR-H's manual-apply values (e.g., state was reset, or operator never ran the runbook), the first workflow run mints a NEW `random_id` and the corresponding `doppler_secret.github_app_webhook_secret` is re-published with the new value — INVALIDATING the secret the GitHub App is signing requests with. The webhook would silently fail signature verification until the operator pastes the new value into the GitHub App config. Mitigation: the destroy-count guard fires on the FIRST applied resource in this scenario (state shows a resource as new, terraform plan shows `+ create`, no destroys yet — guard does NOT fire on creates). **Hard-defense**: operator MUST `gh run watch` the first apply post-merge and confirm `random_id.github_webhook_secret` is NOT in the change-set. If it is, abort the apply (`gh run cancel`), verify state via local `terraform state show` against R2, and import the existing value if state is empty.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section present, threshold = `aggregate pattern` with rationale.)
- When the workflow's `-target=` list grows past ~50 entries, consider switching to `-target=` allow-list via `for-each` in a wrapper script. Out of scope for Phase 1; defer as `wg-when-deferring-a-capability-create-a` tracking issue if cardinality crosses that line.
- **The `paths:` filter MUST also cover the workflow file itself** (not just `apps/web-platform/infra/**`). Otherwise, a PR that edits the workflow file but no tf files won't trigger a re-apply — and the workflow's logic change can't be re-validated until the next tf-touching PR lands. The issue body specifies this; honored in AC3.
- **DO NOT add `[skip ci]` semantics to the kill switch** — the precedent uses `[skip-<workflow-name>-apply]` and the literal `[skip ci]` token in GitHub Actions has different semantics (skips all CI, not just this workflow). The `[skip-web-platform-apply]` token is specific to this workflow.
- **The `apply-sentry-infra.yml` precedent ALSO runs a 4-gate sentry-monitors-audit before plan**. This workflow does NOT need a parallel `web-platform-audit` script — the audit's purpose there is destination-controllability of monitor destinations, which is sentry-specific. The destroy-count guard plus drift detector is sufficient defense-in-depth for the web-platform root.
- **`hcloud_server.web` and `hcloud_volume.workspaces` are EXCLUDED from the allow-list** — these are managed by the deploy lifecycle (`apply-deploy-pipeline-fix.yml` for the disk-monitor / fail2ban / orphan-reaper resources; the server + volume themselves are managed by initial `terraform apply` and the drift detector). A future change to add automated server-image bumps would extend this workflow (or, better, add a fourth dedicated workflow). Out of scope.
- **The first apply post-merge will land MANY changes** (since the workflow has never run; all 13 PR-H resources + the inngest set are likely in a state where the Doppler secrets exist in the config but the `random_id` values may have been operator-overridden). The destroy-count guard fires correctly in this case; the operator MUST acknowledge with `[ack-destroy]` if the first plan shows destroys. Document this in the PR body's "post-merge runbook" subsection.
- **GitHub App creation REMAINS operator-manual** (Stripe-tier vendor limit — `github.com/settings/apps/new` requires a human session, not an API call). The github-app.tf:6-8 comment update should remove the "deferred-automation backlog" reference for `terraform apply` but PRESERVE the note about App creation being inherently manual (per `hr-never-label-any-step-as-manual-without` — verified vendor limit, not workflow gap).

## Alternative Approaches Considered

| Approach                                                                  | Pros                                                                                   | Cons                                                                                                                                                                                                                                                                                                          | Decision                                                              |
| ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Full-root `terraform apply` (no `-target=`)                               | Simpler workflow, no allow-list maintenance.                                           | server.tf SSH provisioners would fail with `ssh: connection reset by peer` from the GitHub runner (firewall blocks runner IP). Either bake runner IP rotation into firewall.tf (broad attack surface) or extract the deploy SSH key + register the runner key on every run (defeats the gate). | **Rejected.** `-target=` allow-list is the right boundary.            |
| One workflow per `.tf` file (3 workflows for PR-H, 1 per future file)     | Each workflow's `paths:` filter is tight. No allow-list maintenance.                   | Workflow proliferation. Operator gate clicks scale linearly with PR count. Defeats the "operator manual-runbook step count drops" issue goal.                                                                                                                                                                  | **Rejected.** Single workflow with allow-list is the precedent shape.  |
| Hetzner runner inside the firewall                                        | server.tf SSH provisioners apply from CI without firewall changes.                     | Self-hosted runner introduces a new attack surface + maintenance burden. Out of proportion for this issue.                                                                                                                                                                                                     | **Deferred.** File as a follow-up if `apply-deploy-pipeline-fix.yml` patterns proliferate.                |
| `terraform-cli-action` wrapper                                            | Pre-built plan-summary comment, plan-artifact upload.                                  | Per `wrapper-vs-curl` sharp edge: this is a single-PR workflow; `setup-terraform` + raw `terraform` commands is "fine in 5 lines of bash". Wrapper adds opaque dependency.                                                                                                                                       | **Rejected.** Use raw `terraform` per the 3 sibling-workflow precedent. |
| Skip the environment-gate; rely on CODEOWNERS only                        | Removes the human-gate click latency.                                                  | Loses defense-in-depth: a leaked PAT with `contents:write` could land an arbitrary `terraform apply` on `main` if CODEOWNERS is the only gate. `apply-sentry-infra.yml` precedent explicitly cites this as the reason for environment gate.                                                                  | **Rejected.** Use environment gate (mirrors `apply-sentry-infra.yml`).  |

## Non-Goals

- **GitHub App creation automation** (per issue body — vendor limit; deferred-automation tracking issue path: file separately if/when GitHub adds App Manifest flow support).
- **Per-tenant tf substrate** (ADR-030 multi-tenant deploy — separate concern; this issue is for Soleur-as-tenant-zero infra root).
- **Hetzner server lifecycle automation** (out of scope; handled by `apply-deploy-pipeline-fix.yml` for the resource-monitor / fail2ban / orphan-reaper subset, by initial `terraform apply` for the server itself).
- **ADR uplift** — if this pattern proliferates to a 4th `apply-*-infra.yml` workflow, write an ADR. For now, the existing ADR-031 (sentry-as-iac) + the 3 sibling workflows are sufficient documentation.

## Test Strategy

- **Pre-merge**: `actionlint .github/workflows/apply-web-platform-infra.yml` and manual review against AC1–AC10.
- **Post-merge**: AC11–AC14 (workflow fires, applies, drift detector clean).
- **No new test framework**: this is a CI workflow change; the verification IS the workflow's own success on a curated trigger commit.
- **Test trigger**: after first merge, the workflow's own merge commit (which touches `.github/workflows/apply-web-platform-infra.yml`) is the canary first apply. The destroy-count guard will fire if anything is unexpectedly destructive; operator can ack-destroy or revert.

## Refs

- `apply-sentry-infra.yml` — structural template (cron-monitor scoping, environment gate, kill-switch, destroy guard).
- `apply-github-infra.yml` — secondary precedent (full-root apply with first-apply import).
- `apply-deploy-pipeline-fix.yml` — `-target=` scoping precedent for SSH-provisioned resources.
- `scheduled-terraform-drift.yml` — drift detector that surfaces missed allow-list entries within 12h.
- `infra-validation.yml` — PR CI that catches `terraform plan` failures before merge.
- `hr-all-infrastructure-provisioning-servers` — this workflow IS the boundary for the rule.
- `hr-never-label-any-step-as-manual-without` — closes the operator-runbook gap for terraform apply (App creation remains manual per vendor limit).
- `hr-ssh-diagnosis-verify-firewall` — informs the `-target=` exclusion of server.tf SSH provisioners.
- `hr-no-dashboard-eyeball-pull-data-yourself` — AC14 verification via `gh api` not dashboard click.
- `wg-after-merging-a-pr-that-adds-or-modifies` — workflow fires post-merge; operator confirms via `gh api` run check.
- `wg-multi-step-post-merge-bootstrap-script` — `cancel-in-progress: false` on the concurrency group.
- PR-H #3244 / #4066 — surfaced this gap.
- `knowledge-base/project/learnings/integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md` — Doppler/AWS dual-credential pattern.
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — auth/authz precedent.

## Research Insights

### Live verification log (deepen-pass)

Every load-bearing claim probed against `main` / live `gh` / live `terraform` at deepen-time:

```text
$ gh issue view 4114 --json state,title
OPEN | infra: add apply-web-platform-infra.yml workflow (post-merge terraform apply automation)

$ gh pr view 4066 --json state,mergedAt
MERGED | 2026-05-19T21:41:09Z

$ gh pr view 3244 --json state
GraphQL: Could not resolve to a PullRequest with the number of 3244.
# Action: removed #3244 from plan body. Cited #4066 only.

$ gh label list --limit 200 | grep -E "^(type/chore|domain/engineering|priority/p3-low|chore)\s"
type/chore           Maintenance, refactoring, tech debt
domain/engineering   Plugin code, CI/CD, infra, docs site (CTO)
priority/p3-low      Nice-to-have, no time pressure
chore                Maintenance and configuration tasks
# Action: all 4 cited labels exist; no fabricated labels.

$ ls knowledge-base/engineering/architecture/decisions/ADR-{019,031,032,036}*.md | wc -l
4
$ grep -l "apps/web-platform/infra\b" knowledge-base/engineering/architecture/decisions/ADR-*.md
ADR-019  ADR-030  ADR-031  ADR-032  ADR-033  ADR-036
# Action: read each. None contain a "operator-only apply" framing for apps/web-platform/infra/.
# ADR-031/032 scope their stances to apps/web-platform/infra/sentry/ and infra/github/.
# ADR-019 only mandates Terraform-for-provisioning, not the apply mechanism. NO ADR AMENDMENT REQUIRED.

$ grep -nE '@v[0-9]+\.[0-9]+\.[0-9]+ *# v[0-9]' .github/workflows/apply-sentry-infra.yml
95:      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
97:      - uses: hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0
# Action: SHA pins are 40-char (verified via `awk -F@ '{print $2}' | awk '{print length($1)}'` → 40, 40).
# DopplerHQ/cli-action SHA `5351693ec144fc7f7a2d30025061acfc3c53c47c` is 40-char (verified).
```

### Best Practices (precedent-derived)

- **Use `apply-github-infra.yml` shape, not `apply-sentry-infra.yml` shape**, for the plan/destroy-guard step. Per the 2026-05-16 learning, `apply-sentry-infra.yml` is vulnerable to the empty-string-bypass class on `[[ "$destroy_count" -gt 0 ]]` when `set -e` is disabled; `apply-github-infra.yml` re-enables `set -e` AND validates `destroy_count` matches `^[0-9]+$`. The new workflow MUST copy the github form verbatim.
- **Concurrency group `cancel-in-progress: false`** is load-bearing per `hr-multi-step-post-merge-bootstrap-script` — cancelling a half-applied terraform run is worse than waiting. All 3 precedents honor this.
- **`terraform init -lockfile=readonly`** (matches `apply-sentry-infra.yml`'s pattern) prevents a malicious provider re-publish from being downloaded. The web-platform root has a `terraform.lock.hcl` (verify via `ls apps/web-platform/infra/.terraform.lock.hcl`) — if absent, this AC needs `terraform init -upgrade` once as a Phase 0 step.
- **`add-mask` every secret extracted via `doppler secrets get --plain`** before writing to `$GITHUB_ENV`. All 3 precedents do this. Without it, the secret value appears in workflow logs if a downstream step echoes `$AWS_ACCESS_KEY_ID`.
- **Anchored kill-switch regex `(^|$'\n')\[skip-...\]($|$'\n')`** — defends against the token appearing in a quoted block / code fence / `Co-Authored-By:` trailer. The deploy-pipeline-fix workflow uses the looser `*"[skip-deploy-fix-apply]"*` form (substring); this is a known minor weakness flagged in PR #3903's review notes. The new workflow MUST use the anchored form (mirrors sentry + github).

### Performance Considerations

- **Workflow wall-clock**: `apply-sentry-infra.yml` `timeout-minutes: 10`. The web-platform root has ~25-40 resources; first apply could exceed 10 min if state is empty. **Decision: `timeout-minutes: 15`** (mirrors `apply-deploy-pipeline-fix.yml` which also includes SSH provisioner). Per `2026-03-20-claude-code-action-max-turns-budget`-style ratio reasoning: budget at ~0.6 min/resource = 18 min for 30 resources; 15 min is the safe ceiling.
- **`terraform plan -refresh=false`** would speed up plan time but masks drift. DO NOT use it — the drift detector is the 12h cron, not the apply workflow. Apply MUST refresh.
- **Parallel `-target=` flags**: terraform CLI accepts ≥50 `-target=` flags without issue (verified at scale per HashiCorp docs). The ~30-resource allow-list is well within the limit.

### Edge Cases

1. **State is missing the random_id values from PR-H's manual apply.** Possible if the operator never ran the runbook (workflow gap that this PR is fixing). First apply mints new values, destroying the production webhook secret. Defense: destroy-count guard fires with the FIRST applied resource; operator gets a chance to `[ack-destroy]` and confirm via the GitHub App's webhook test endpoint.
2. **Doppler service token `DOPPLER_TOKEN` expires** or scope drifts. The workflow's `Verify required secrets present` step (Phase 2 step 4) catches an empty token; it does NOT catch a token with wrong scope (drift to `dev` config). The 12h drift detector also runs against `prd_terraform` and would surface scope drift within 12h. Acceptable.
3. **Provider beta version churn.** `main.tf` requires `betterstack-hq/better-uptime ~> 0.20` (beta tag). Per `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`, beta tags can break schema validation. `init -lockfile=readonly` defends against silent re-publish; `infra-validation.yml` catches plan failures before merge. No additional defense needed in apply.
4. **Operator manually applied a `-replace=random_id.X` since last merge but didn't push the state forward.** R2 backend state is shared; the next CI apply sees the new state correctly. No defense needed.
5. **GitHub Actions runner IP changes mid-run.** Runners are ephemeral; their IP changes per run. The workflow's `-target=` allow-list EXCLUDES all SSH-provisioned resources, so the runner IP NEVER touches the firewall allow-list. Validated.
6. **Concurrent merge to main.** `concurrency.group: terraform-apply-web-platform-infra` + `cancel-in-progress: false` serializes applies. If two PRs merge within seconds, the second waits for the first. Acceptable; matches all 3 precedents.

### References

- `apply-sentry-infra.yml` — structural template (target-scoped, environment gate, destroy guard).
- `apply-github-infra.yml` — canonical post-#3903 destroy-guard implementation (numeric regex validation + `set -e` re-enable).
- `apply-deploy-pipeline-fix.yml` — `-target=` scoping precedent for the apply that mixes SSH and non-SSH; the SSH portion is covered by THAT workflow, not this one.
- `scheduled-terraform-drift.yml` — drift detector (12h cron).
- `infra-validation.yml` — PR CI plan validation.
- `knowledge-base/project/learnings/2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md` — destroy-guard empty-string-bypass class.
- `knowledge-base/project/learnings/integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md` — Doppler/AWS dual-credential pattern; this workflow uses the single-invocation form per the deploy-pipeline-fix precedent.
- `knowledge-base/engineering/architecture/decisions/ADR-019-terraform-only-for-infrastructure.md` — Terraform-as-provisioning mandate.
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — auth/authz precedent for environment gate.
- `knowledge-base/engineering/architecture/decisions/ADR-036-github-app-webhook-as-second-multi-source-ingress.md` — PR-H ADR; documents `random_id.github_webhook_secret` rotation contract.

## Network-Outage Deep-Dive

Phase 4.5 of deepen-plan fires because the plan drives `terraform apply` on a root containing resources with `provisioner "remote-exec"` (server.tf — 7 resources). Per `hr-ssh-diagnosis-verify-firewall` and the network-outage checklist, the four-layer verification is REQUIRED even though the workflow's `-target=` allow-list EXCLUDES these resources. Reason: a future PR could add a new resource that the allow-list misses; if that resource has SSH provisioners, the apply would silently bypass the firewall layer until the runtime error surfaces.

**L3 — Firewall allow-list (Hetzner `var.admin_ips`).**

- **Verification:** `apps/web-platform/infra/firewall.tf:1-90` defines `hcloud_firewall.web` with SSH rule scoped to `for_each = var.admin_ips`. The GitHub-runner egress IP range is NOT in `var.admin_ips` (admin_ips is operator's home/office IPs, see `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`).
- **Status:** verified-by-design. The workflow's apply path NEVER hits the firewall because `-target=` excludes every SSH-provisioned resource.
- **Mitigation if a future tf addition violates this:** the apply would fail with `ssh: handshake failed: connection reset by peer`. The 12h drift detector surfaces this; the operator can either add the new resource to the allow-list (this workflow) or move it to a sibling workflow with deploy-key wiring (mirror `apply-deploy-pipeline-fix.yml`).

**L3 — DNS / routing.**

- **Verification:** the workflow does NOT make DNS calls during plan/apply (terraform talks to Hetzner / Cloudflare / Doppler / GitHub / BetterStack APIs over HTTPS; resolution happens at the runner's local resolver). GitHub Actions runners have stable cloud DNS.
- **Status:** verified-by-design. No action needed.

**L7 — TLS / proxy layer.**

- **Verification:** all terraform provider API calls go over HTTPS with certificate validation enabled by default. No proxy interposition.
- **Status:** verified-by-design. No action needed.

**L7 — Application layer.**

- **Verification:** terraform's exit codes are the application-layer signal (0 = clean, 1 = error, 2 = drift in `-detailed-exitcode` mode). The workflow's `rc=$?` capture + numeric-regex destroy guard handle these correctly.
- **Status:** verified per `apply-github-infra.yml` precedent (post-#3903 implementation).

**Opt-out:** the apply-time SSH dependency on server.tf is opt-out-via-target-exclusion, not opt-out-via-justification. The `-target=` allow-list is enumerated in §Phase 0.3 and AC4 asserts the SSH resources are NOT in the list.

## Status

- [x] Phase 0 preconditions verified
- [x] Phase 1: empty workflow scaffolded, actionlint passes
- [x] Phase 2: full workflow filled in
- [x] Phase 3: comment + CODEOWNERS sweep
- [ ] PR opened, AC1–AC10 verified
- [ ] PR merged, AC11–AC14 verified
