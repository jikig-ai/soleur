---
title: "Provision RESEND_RECEIVING_API_KEY (IaC only) — follow-up to #5468"
issue: 5480
branch: feat-one-shot-5480-resend-receiving-key
type: chore
lane: single-domain
brand_survival_threshold: aggregate pattern
adr: ADR-065
date: 2026-06-17
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Phase 2.8 reviewed: the operator-gated step is the INPUT to the
`doppler_secret.resend_receiving_api_key` Terraform resource — an operator-minted Resend dashboard key
(no creation API — vendor limit) placed into Doppler prd_terraform as TF_VAR_resend_receiving_api_key.
It cannot itself be Terraform-routed (circular: it is the var the resource reads), and per ADR-065 +
hr-tf-variable-no-operator-mint-default it must land in prd_terraform BEFORE this IaC merges. The
actual prd-config secret IS Terraform-managed (the doppler_secret resource). No server provisioning,
no SSH, no other manual infrastructure write.
-->

# Provision RESEND_RECEIVING_API_KEY (IaC only) — follow-up to #5468

🔧 **chore / infrastructure** · single-domain (Engineering) · ≈30 lines, IaC only, no app code.

## Enhancement Summary

**Deepened on:** 2026-06-17
**Sections enhanced:** Precedent-Diff (4.4), verify-the-negative (4.45), provider-pin grounding.
**Gates passed:** 4.6 User-Brand Impact (threshold `aggregate pattern`), 4.7 Observability (ssh-free
discoverability_test), 4.8 PAT-shaped variable (no hits), 4.9 UI-wireframe (no UI surface — skip).

### Key Improvements
1. **Precedent-Diff verified (no novel attribute).** Every attribute the new `doppler_secret` uses —
   `project`, `config`, `name`, `value`, `visibility`, `lifecycle { ignore_changes = [value] }` — is in
   active use by the precedent `github-app.tf:40-80` and `inngest.tf:63-107` resources under the same
   pinned provider `DopplerHQ/doppler ~> 1.21` (lock: `1.21.2`). The plan's resource shape is correct
   by repo precedent, not by Context7-latest docs (which would not be version-pinned).
2. **Negative claim confirmed by grep (least-privilege holds).** The load-bearing
   "NOT threaded into the cloud-init monitor env files" claim was verified:
   `grep -rn RESEND_RECEIVING_API_KEY apps/web-platform/infra/*.sh cloud-init.yml server.tf` returns
   **zero** — the 3 send-only alert monitors read only `RESEND_API_KEY`. The sole receiving-key
   consumer is `apps/web-platform/server/email-triage/fetch-received-email.ts:37` (Next.js app,
   Doppler-injected runtime env). No blast-radius widening.
3. **Sequencing gate (ADR-065) re-affirmed.** The two operator prerequisites correctly block merge (not
   post-merge); the no-default variable is correct per `hr-tf-variable-no-operator-mint-default`.

### New Considerations Discovered
- None that change the plan. The change is exactly the ≈30 lines of IaC prescribed by #5480 + ADR-065;
  deepen-plan grounded the precedent and confirmed the least-privilege negative claim, but surfaced no
  new scope.

## Overview

#5468 (the inbound-mail-finalize bug) was split per **ADR-065**. The **code-resilience half** already
merged (PR #5475): `apps/web-platform/server/email-triage/fetch-received-email.ts:37` now reads
`process.env.RESEND_RECEIVING_API_KEY` and throws `RESEND_RECEIVING_API_KEY must be set` if absent
(no silent fallback), and `.env.example:111` documents the key. This PR ships the **config half** —
the IaC that publishes a least-privilege receiving-scoped Resend key to Doppler `prd` so the live
prd consumer stops failing the inbound body fetch and inbound mail gets *full* classification (not
just a visible degraded row).

Three files, exact text below:
1. `apps/web-platform/infra/variables.tf` — `variable "resend_receiving_api_key"` (string, sensitive, **no default**).
2. `apps/web-platform/infra/resend.tf` — **new file** — `resource "doppler_secret" "resend_receiving_api_key"` (`config = "prd"`, `name = "RESEND_RECEIVING_API_KEY"`, `value = var.resend_receiving_api_key`, `visibility = "masked"`, `lifecycle { ignore_changes = [value] }`), mirroring the `github-app.tf` operator-supplied-secret pattern.
3. `.github/workflows/apply-web-platform-infra.yml` — append `-target=doppler_secret.resend_receiving_api_key` to the non-SSH plan/apply allowlist (per the workflow's own line-253 ALLOW-LIST MAINTENANCE instruction).

**Hard sequencing gate (ADR-065 / `hr-tf-variable-no-operator-mint-default`):** this PR adds a
no-default TF variable to the auto-applied `apps/web-platform/infra/` root. Terraform resolves **all**
root variables *before* `-target` pruning, so the merge-triggered `apply-web-platform-infra.yml` apply
will fail with `Error: No value for required variable` until `TF_VAR_resend_receiving_api_key` exists
in Doppler `soleur` / `prd_terraform`. The two operator prerequisites below are **genuinely
operator-gated** (Resend dashboard key mint) and **MUST complete before this PR merges**. Block
PR-ready / auto-merge on them per `wg-block-pr-ready-on-undeferred-operator-steps`.

## Premise Validation

Checked before drafting (all held): Issue **#5480 OPEN**. Parent bug **#5468 CLOSED** by merged
code-half **PR #5475**. **ADR-065** exists (`knowledge-base/engineering/architecture/decisions/ADR-065-operator-mint-tf-var-secret-before-iac-merge.md`)
and explicitly ratifies the IaC+mint split and defers it to #5480. Source plan
`knowledge-base/project/plans/2026-06-17-fix-inbound-mail-finalize-tail-plan.md` exists with the exact
IaC text in its `## Infrastructure (IaC)` section (lines 298–330). `github-app.tf:40-80` confirmed as
the operator-supplied `doppler_secret` precedent (also `inngest.tf:63-107`). `resend.tf` does **not**
yet exist (new file). The runtime consumer is **live on origin/main**
(`fetch-received-email.ts:37`, throws if key unset) — confirming prd is currently degrading until this
PR + mint land. No external premises remain unvalidated.

**Issue-vs-plan deviation (resolved in this plan's favor):** the source plan Phase 1b (lines 306-307,
382) prescribed threading `${resend_receiving_api_key}` into `server.tf` + `cloud-init.yml` monitor
env files. The **#5480 issue body explicitly overrides this**: "NOT threaded into cloud-init monitor
env files (those send-only scripts must not carry the receiving key — least-privilege)." This plan
follows the issue. Verified rationale: `RESEND_API_KEY` (the *send* key) flows
`var.resend_api_key` → `server.tf:106/146/200` → `/etc/default/<monitor>` env files consumed by the
3 alert-monitor shell scripts (`disk-monitor.sh`, `resource-monitor.sh`,
`container-restart-monitor.sh`) — those are **send-only** alerting scripts. The *receiving* key is
consumed by the **Next.js app process** (`fetch-received-email.ts`) which reads Doppler-injected env
at runtime; publishing it via `doppler_secret` to `prd` is sufficient, and the next container restart
(`web-platform-release.yml` on merge to `apps/web-platform/**`) picks it up. Threading it into the
monitor env files would *widen* the receiving key's blast radius onto send-only scripts for zero
functional gain — exactly the least-privilege violation the issue forbids.

## Operator Prerequisites — BLOCKING (must complete before merge)

> **These block PR-ready and auto-merge** (`wg-block-pr-ready-on-undeferred-operator-steps`,
> `hr-tf-variable-no-operator-mint-default`). The mint is the one genuinely operator-gated step
> (Resend dashboard, no API for key creation — vendor limit). Do NOT silently defer; do NOT
> auto-merge until both are confirmed.

- [ ] **Mint a receiving / full-access Resend API key** at resend.com/api-keys, distinct from the
      send-scoped `RESEND_API_KEY`. `Automation: not feasible because` Resend API-key creation is a
      console-gated human-session action (no creation API).
- [ ] **Place the minted value into Doppler `soleur` / `prd_terraform` as `TF_VAR_resend_receiving_api_key`**
      (stored as a `TF_VAR_*` so `--name-transformer tf-var` injects it as the `resend_receiving_api_key`
      root variable, like every other `resend_*`/secret TF var). This single write is the operator-gated
      INPUT to the Terraform `doppler_secret` resource — it cannot be Terraform-routed; the prd-config
      secret it feeds IS Terraform-managed (see the `iac-routing-ack` note at the top of this plan).

**Why these block merge, not post-merge:** `apply-web-platform-infra.yml` fires on any
`apps/web-platform/infra/*.tf` change merged to `main`. Its plan step runs
`doppler run -c prd_terraform --name-transformer tf-var -- terraform plan -out=tfplan -target=…`.
Terraform resolves the new no-default `resend_receiving_api_key` variable *before* `-target` pruning;
absent its `TF_VAR_*`, the **entire** merge-triggered apply fails (not just this resource). Classifying
the mint as "post-merge" is the exact ADR-065-rejected mistake.

## User-Brand Impact

**If this lands broken, the user experiences:** inbound statutory mail (e.g., a GDPR Art. 12 request
arriving as a body-only letter) continues to land as a *visibly degraded* `email_triage_items` row
(`mail_class`/`statutory_class` NULL with a degraded summary) instead of a fully classified row —
the operator still sees it in the inbox but without auto-classification. (The prior silent-permanent-NULL
failure is already fixed by the merged degraded-finalize tail, so this is a degraded-but-visible state,
not a silent loss.)

**If this leaks, the user's mailbox access is exposed via:** the receiving/full-access Resend key is a
high-privilege credential; a logged or committed value could read inbound mail. Mitigations: `sensitive
= true` on the variable, `visibility = "masked"` on the `doppler_secret`, value lands only in
`terraform.tfstate` (encrypted R2 backend) and Doppler `prd` (masked) — never in monitor env files
(least-privilege per the issue) and never in app logs (`fetch-received-email.ts` reads it, never logs it).

**Brand-survival threshold:** aggregate pattern. (The single-user silent-loss window was closed by the
already-merged resilience half; what remains is the aggregate quality of classification, which degrades
visibly rather than failing silently. No per-PR CPO sign-off required.)

## Files to Edit

### 1. `apps/web-platform/infra/variables.tf` — add after the `resend_api_key` block (after line 156)

```hcl
variable "resend_receiving_api_key" {
  description = "Resend receiving/full-access API key for inbound-mail body fetch (RESEND_RECEIVING_API_KEY). Distinct from the send-scoped resend_api_key — least-privilege per #5480. Operator-minted at resend.com/api-keys; value from Doppler prd_terraform via TF_VAR_resend_receiving_api_key. No default (hr-tf-variable-no-operator-mint-default)."
  type        = string
  sensitive   = true
}
```

### 2. `apps/web-platform/infra/resend.tf` — NEW FILE

```hcl
# #5480 — receiving-scoped Resend key for inbound-mail body fetch.
# Follow-up to #5468 (degraded-finalize tail merged in PR #5475); split per
# ADR-065 (operator-mint no-default TF var must be provisioned in prd_terraform
# BEFORE this IaC merges, else the auto-applied apply fails resolving the var
# before -target pruning).
#
# Operator-supplied-secret pattern — mirrors github-app.tf:40-80 (and
# inngest.tf:63-107). The key is minted in the Resend dashboard (no creation
# API — vendor limit) and set as TF_VAR_resend_receiving_api_key in Doppler
# prd_terraform; this resource publishes it to the `prd` Doppler config where
# the Next.js app reads it at runtime (fetch-received-email.ts).
#
# NOT threaded into the cloud-init monitor env files (disk/resource/container
# monitors are send-only and must not carry the receiving key — least-privilege,
# #5480). Those scripts continue to read only RESEND_API_KEY.
#
# Why ignore_changes on value: rotation via the Resend dashboard + Doppler is
# invisible to subsequent `terraform plan` (the provider skips the value
# read-back), so without ignore_changes every apply would churn this secret.
# Same policy as the operator-supplied secrets in github-app.tf / inngest.tf.

resource "doppler_secret" "resend_receiving_api_key" {
  project    = "soleur"
  config     = "prd"
  name       = "RESEND_RECEIVING_API_KEY"
  value      = var.resend_receiving_api_key
  visibility = "masked"

  lifecycle {
    # dev/prd isolation: config = "prd" pinned explicitly; cannot land in dev
    # without an edit to this file (caught at PR review). Mirrors github-app.tf.
    ignore_changes = [value]
  }
}
```

### 3. `.github/workflows/apply-web-platform-infra.yml` — append one `-target` line

Append to the **non-SSH plan allowlist** (the `terraform plan -out=tfplan` step, after
`-target=hcloud_firewall_attachment.web` at **line 350** — the current last `-target` of that block).
The matching `terraform apply ... tfplan` step (line ~401) replays the saved plan, so it needs **no**
separate edit. The line-526 SSH-apply block is `terraform_data.*`-only and is NOT touched.

```diff
               -target=hcloud_firewall.web \
-              -target=hcloud_firewall_attachment.web
+              -target=hcloud_firewall_attachment.web \
+              -target=doppler_secret.resend_receiving_api_key
```

## Files to Create

- `apps/web-platform/infra/resend.tf` (the new file in §2 above).

## Open Code-Review Overlap

None. (No open code-review issues touch `variables.tf`, `resend.tf` (new), or
`apply-web-platform-infra.yml` for this change class.)

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/variables.tf` — new `variable "resend_receiving_api_key"` (string,
  sensitive, **no default**; value from Doppler `prd_terraform` via `TF_VAR_resend_receiving_api_key`).
- `apps/web-platform/infra/resend.tf` — **new file** — `resource "doppler_secret"
  "resend_receiving_api_key"` (`config = "prd"`, `name = "RESEND_RECEIVING_API_KEY"`,
  `value = var.resend_receiving_api_key`, `visibility = "masked"`, `lifecycle { ignore_changes = [value] }`).
- Required providers: existing `doppler/doppler` pin only (no new provider; `.terraform.lock.hcl`
  already has it via `github-app.tf` / `inngest.tf`).
- Sensitive vars: `resend_receiving_api_key` — sourced from Doppler `prd_terraform` as
  `TF_VAR_resend_receiving_api_key`.

### Apply path
- **(b) cloud-init + idempotent — auto-apply-on-merge.** The merge-triggered
  `apply-web-platform-infra.yml` runs `doppler run -p soleur -c prd_terraform --name-transformer
  tf-var -- terraform apply -auto-approve tfplan`, where `tfplan` was produced with
  `-target=doppler_secret.resend_receiving_api_key` (the appended allowlist line). It creates the one
  new Doppler secret in `prd`. The Next.js container picks up the new Doppler-injected env on its next
  restart (`web-platform-release.yml` on merge touching `apps/web-platform/**`). **Blast radius:** a
  single new `doppler_secret` create + env-only container pickup; no resource replacement, no destroy.
- Manual fallback (only if the auto-apply is unavailable), canonical per
  `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`:
  `export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)`
  (+ `AWS_SECRET_ACCESS_KEY` likewise), `terraform init -input=false`, then
  `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply
  -target=doppler_secret.resend_receiving_api_key`.

### Distinctness / drift safeguards
- `dev != prd`: the `doppler_secret` pins `config = "prd"` explicitly. dev leaves
  `RESEND_RECEIVING_API_KEY` set equal to the send key in `.env.example` (dev receives no real inbound
  mail) — no dev `doppler_secret` resource is created by this plan.
- `lifecycle { ignore_changes = [value] }`: dashboard/Doppler rotation does not churn the resource on
  subsequent applies (provider skips value read-back) — same posture as `github-app.tf` /
  `inngest.tf` operator-supplied secrets.
- The new var is `sensitive`; its value lands in `terraform.tfstate` (encrypted R2 backend) — same
  posture as the existing `resend_api_key`.
- **Destroy-guard:** the `apply-web-platform-infra.yml` destroy-guard filter
  (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`) is Cloudflare-resource-only; a new
  `doppler_secret` **create** (not a destroy/nested-removal) is not counted, so no `[ack-destroy]` is
  required and the guard does not block this PR.

### Vendor-tier reality check
- Resend tiers allow multiple API keys with per-key permission scoping; minting a receiving/full-access
  key is within the existing plan. No tier gate (`count = ... ? 1 : 0` not needed).

### Research Insights (deepen-plan)

**Precedent-diff (4.4) — provider-pin grounded:**
- Provider: `DopplerHQ/doppler ~> 1.21` (declared in `main.tf` `required_providers`; locked to
  `1.21.2` in `.terraform.lock.hcl`). No new provider; no `.terraform.lock.hcl` change.
- The `doppler_secret` resource shape is **identical** to the two precedent operator-supplied secrets
  in `github-app.tf` (`github_app_id`, `github_app_private_key`) — same `project = "soleur"`,
  `config = "prd"`, `visibility = "masked"`, and `lifecycle { ignore_changes = [value] }`. Verified by
  `grep -E 'project|config|name|value|visibility|ignore_changes' apps/web-platform/infra/github-app.tf`.
  No novel attribute is introduced, so no version-pinned schema risk.

**Verify-the-negative (4.45) — least-privilege confirmed:**
- `grep -rn 'RESEND_RECEIVING_API_KEY' apps/web-platform/infra/*.sh apps/web-platform/infra/cloud-init.yml apps/web-platform/infra/server.tf`
  returns **zero** matches → the 3 send-only alert monitors (`disk-monitor.sh`, `resource-monitor.sh`,
  `container-restart-monitor.sh`) never read the receiving key. CONFIRMS the plan's negative claim.
- `grep -rn 'RESEND_RECEIVING_API_KEY' apps/web-platform/server/` → sole consumer is
  `email-triage/fetch-received-email.ts:37` (reads `process.env.RESEND_RECEIVING_API_KEY`, throws if
  unset). The key reaches the app via Doppler-injected runtime env, not via the monitor env files.

## Architecture Decision (ADR/C4)

No new architectural decision. The split decision is **already recorded in ADR-065** (Accepted,
2026-06-17). This PR is the IaC *implementation* of that ADR's "IaC half (follow-up #5480)", not a new
or reversed decision. A reader of the existing ADRs + C4 is not misled. Skip — no `## Architecture
Decision` deliverable beyond this citation.

## Observability

```yaml
liveness_signal:
  what: "Inbound mail finalizes with non-NULL mail_class/statutory_class for mail received after apply"
  cadence: "per inbound email (event-driven, email-on-received Inngest function)"
  alert_target: "Sentry (email-triage finalize errors already mirrored) + operator inbox (degraded rows are visible)"
  configured_in: "apps/web-platform/server/email-triage/fetch-received-email.ts (throws on missing key); email-on-received degraded-finalize tail (PR #5475)"
error_reporting:
  destination: "Sentry — fetch-received-email throws 'RESEND_RECEIVING_API_KEY must be set' if the key is absent/unset; the degraded-finalize tail captures body-fetch failures as a visible degraded row + Sentry event"
  fail_loud: true
failure_modes:
  - mode: "TF_VAR_resend_receiving_api_key absent at merge -> whole apply-web-platform-infra apply fails"
    detection: "apply-web-platform-infra.yml plan step errors 'No value for required variable resend_receiving_api_key' in the GH Actions run log"
    alert_route: "GitHub Actions failed-run notification on main (loud, blocking); the ADR-065 sequencing gate prevents this by requiring the mint before merge"
  - mode: "Key minted with wrong (send-only/restricted) scope -> inbound body fetch still 403s"
    detection: "fetch-received-email continues to produce degraded rows; restricted_api_key in Sentry"
    alert_route: "Sentry email-triage error + the verification query below trending non-zero"
  - mode: "doppler_secret created but container not yet restarted -> app still reads old/empty env"
    detection: "RESEND_RECEIVING_API_KEY present in Doppler prd but app still degrading"
    alert_route: "web-platform-release.yml restarts the container on merge to apps/web-platform/**; no separate operator step"
logs:
  where: "Sentry (app errors); GitHub Actions run log (terraform apply); Supabase email_triage_items table (degraded-row evidence)"
  retention: "Sentry default project retention; GH Actions 90d; Supabase row-level (WORM, retained)"
discoverability_test:
  command: "doppler secrets get RESEND_RECEIVING_API_KEY -p soleur -c prd --plain | head -c 4"
  expected_output: "Non-empty prefix of the minted key (e.g. 're_...') confirming the doppler_secret published to prd. NO ssh required."
```

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)
**Status:** reviewed (carry-forward from source plan `2026-06-17-fix-inbound-mail-finalize-tail-plan.md`
+ ADR-065)
**Assessment:** Least-privilege key split avoids widening the send key's blast radius; the
`doppler_secret` IaC route reuses the established operator-supplied-secret pattern (`github-app.tf` /
`inngest.tf`). The ADR-065 sequencing gate (mint + `TF_VAR_*` before IaC merge) is the load-bearing
correctness invariant — the no-default variable is correct (`hr-tf-variable-no-operator-mint-default`)
precisely because an empty default would silently ship a broken/empty credential to prd. NOT threading
into the send-only monitor env files is the correct least-privilege reading of the issue (the receiving
key reaches the app via Doppler-injected runtime env, not the alert-monitor scripts).

No Product/UX surface (no `components/`, `app/**/page.tsx`, or UI files). No GDPR-gate regulated-data
*surface* added (this is a credential-provisioning IaC change; the regulated-data processing it enables
was assessed in the source plan / #5468). No Legal re-sign needed at plan time.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** `apps/web-platform/infra/variables.tf` declares `variable "resend_receiving_api_key"` with
  `type = string`, `sensitive = true`, and **no `default`**. Verify:
  `grep -A4 'variable "resend_receiving_api_key"' apps/web-platform/infra/variables.tf` shows
  `sensitive = true` and contains no `default` line.
- **AC2** `apps/web-platform/infra/resend.tf` exists and declares
  `resource "doppler_secret" "resend_receiving_api_key"` with `config = "prd"`,
  `name = "RESEND_RECEIVING_API_KEY"`, `value = var.resend_receiving_api_key`,
  `visibility = "masked"`, and `lifecycle { ignore_changes = [value] }`. Verify:
  `grep -E 'config|name|value|visibility|ignore_changes' apps/web-platform/infra/resend.tf`.
- **AC3** `RESEND_RECEIVING_API_KEY` is **NOT** present in any cloud-init / monitor env write site.
  Verify: `grep -rn 'resend_receiving_api_key\|RESEND_RECEIVING_API_KEY' apps/web-platform/infra/cloud-init.yml apps/web-platform/infra/server.tf`
  returns **zero** matches (least-privilege per #5480).
- **AC4** `.github/workflows/apply-web-platform-infra.yml` contains exactly one new allowlist line
  `-target=doppler_secret.resend_receiving_api_key`, in the non-SSH plan step (NOT the line-526
  `terraform_data` SSH block). Verify:
  `grep -c -- '-target=doppler_secret.resend_receiving_api_key' .github/workflows/apply-web-platform-infra.yml`
  returns `1`, and the line sits between `-target=hcloud_firewall_attachment.web` and the
  `terraform show` step.
- **AC5** `terraform fmt -check` passes for the changed `.tf` files (run
  `cd apps/web-platform/infra && terraform fmt -check variables.tf resend.tf`). `terraform validate`
  is NOT runnable pre-merge without the `TF_VAR_*` provisioned (it would error on the no-default var —
  expected; that error IS the ADR-065 gate), so validate is deferred to the post-merge auto-apply.
- **AC6** PR body uses `Closes #5480` (this IaC PR fully resolves the tracking issue; the parent #5468
  was already closed by PR #5475). PR body restates the two BLOCKING operator prerequisites and is
  **not** marked ready / auto-merge until both are confirmed
  (`wg-block-pr-ready-on-undeferred-operator-steps`).

### Post-merge (operator / automated)
- **AC7** (automated, on merge) `apply-web-platform-infra.yml` apply succeeds and creates
  `doppler_secret.resend_receiving_api_key` in Doppler `prd`. Detection: green GH Actions run; the
  `Plan:` line shows `1 to add` for this resource.
- **AC8** (read-only verification — automatable via Doppler CLI / Supabase MCP, NOT a dashboard
  eyeball) `doppler secrets get RESEND_RECEIVING_API_KEY -p soleur -c prd --plain | head -c 4`
  returns a non-empty key prefix. Then confirm fresh inbound mail finalizes:
  `select id, mail_class, summary from email_triage_items where mail_class is null and statutory_class
  is null and created_at > now() - interval '7 days';` (Supabase MCP read) trends to zero. **Never a
  manual UPDATE** — `email_triage_items` is WORM-triggered.

## Test Scenarios

This is an IaC-only change with no bun/vitest-testable application code. Verification is the AC grep
suite (pre-merge) + the green auto-apply and read-only Doppler/Supabase probes (post-merge). No new
test file is warranted; the existing `tests/scripts/test-destroy-guard-counter-web-platform.sh` already
covers the destroy-guard filter and is unaffected (a `doppler_secret` create is not in its
Cloudflare-only scope).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6 — this section is filled (threshold: aggregate
  pattern).
- **The two operator prerequisites are BLOCKING, not post-merge.** The natural temptation (and the
  exact ADR-065-rejected mistake) is to classify the Resend mint as a post-merge step. It cannot be —
  Terraform resolves the no-default `resend_receiving_api_key` variable *before* `-target` pruning, so
  an unprovisioned `TF_VAR_*` fails the **whole** merge-triggered apply, not just this resource. Do not
  mark the PR ready or enable auto-merge until both prerequisites are confirmed.
- **`-target` line goes in the non-SSH plan block (line ~350), not the SSH apply block (line ~526).**
  The SSH block is `terraform_data.*`-only and runs a separate apply over the CF tunnel bridge. The
  saved-`tfplan` apply (line ~401) replays the plan, so only the plan step's allowlist needs the new
  line.
- **Do NOT thread the receiving key into `server.tf` / `cloud-init.yml`.** The source plan's Phase 1b
  prescribed this; the #5480 issue overrides it for least-privilege. The receiving key reaches the
  Next.js app via Doppler-injected runtime env (the `doppler_secret` → `prd` path), never the send-only
  monitor scripts. AC3 enforces zero matches in those files.
- `terraform validate` will error pre-merge on the unprovisioned no-default var — that is expected and
  is the gate working, not a defect. Use `terraform fmt -check` for pre-merge format validation; defer
  `validate` to the post-merge auto-apply (which runs after the operator has set the `TF_VAR_*`).
