---
title: 'The agent runs terraform apply autonomously — never route infra provisioning to a Soleur operator'
date: 2026-07-07
category: engineering
tags: [terraform, provisioning, soleur-principle, doppler, hetzner, automation, apply-path]
problem_type: workflow_gap
resolution_type: workflow_fix
severity: high
issues: ['#6122', '#6167']
---

# The agent runs `terraform apply` — never ask a Soleur user to

## The mistake

While provisioning the zot registry host (#6122), a spec/runbook framed the step as
*"the **operator's** full `terraform apply`; the interactive yes-prompt is the authorization; do
NOT `-auto-approve`"* — so the agent handed the CLI to the founder and asked him to run it.

**That violates the Soleur principle** (non-technical users act only through the product) AND the
existing hard rules: `hr-fresh-host-provisioning-reachable-from-terraform-apply` already says every
prod service must come up on `terraform apply` "from empty state, **zero operator actions**," and
`hr-menu-option-ack-not-prod-write-auth` says the **agent** runs the apply (with `-auto-approve`)
after a go-ahead. The operator's authorization is **product-level intent** ("provision the registry"),
NOT a request to run terraform at a CLI.

**Correct pattern:** the agent runs `terraform apply` itself — reviews the plan (0 destroy, scoped),
then applies. The `lint-infra-no-human-steps` gate flags `operator|you|founder … terraform/ssh/apply`
in specs/runbooks; when it fires on a provisioning step, the fix is to **reframe the step as agent-run**
(the `agent` token is not a human actor), NOT to suppress it with a `lint-infra-ignore` region. Wrapping
a "operator runs the apply" line in `lint-infra-ignore` hides a correct guardrail.

## How the agent runs the web-platform apply (cred pattern)

The R2 (S3-compatible) backend needs `AWS_*` **unprefixed**; the TF vars need the `TF_VAR_` prefix.
A single blanket transformer breaks one or the other. Do both:

```bash
cd apps/web-platform/infra
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
doppler run -p soleur -c prd_terraform -- terraform init                          # backend (AWS_* unprefixed)
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -out=tfplan [targets]
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply tfplan   # apply the reviewed plan
```

Review the plan before applying: `Plan: N to add, 0 to change, 0 to destroy` and no surprise
`git_data`/foreign resources (see below).

## Three provisioning traps this surfaced

1. **A TF-created `doppler_project` is BARE — no default configs.** Unlike `doppler projects create`
   (CLI) which auto-adds dev/stg/prd, the terraform `doppler_project` resource creates an empty project,
   so `doppler_secret{config="prd"}` fails at apply with *"Could not find requested config 'prd'"*. Add a
   `doppler_environment` resource (slug=`prd`) so the config exists — this is required for true
   zero-operator provisioning. `doppler_environment` is a basic Project-Structure resource (does NOT need
   the paid config-inheritance feature that sank `doppler_config.prd_ghcr` in #6067).

2. **A full untargeted apply co-provisions OTHER unprovisioned `OPERATOR_APPLIED_EXCLUSIONS`.** The zot
   plan said "full untargeted apply." But the plan showed **48 adds, not 24** — the extra ~24 were the
   still-unprovisioned `git_data` host (`hcloud_server.git_data`, `doppler_service_token.git_data`, proxy
   TLS, git SSH keys). `git_data` carries the SAME unfixed branch-config isolation over-read this cutover
   filed as #6167 — so a blanket apply would ship the exact defect just fixed for zot. **Scope the apply
   `-target`ed to the intended resource set**, and always diff the plan's create-list against the task's
   expected count before applying.

3. **Hetzner ARM (`cax11`) capacity is a real provisioning gate.** The host is ARM-pinned (zot ARM image).
   All CAX types were out of stock across every eu-central datacenter, and the private network is zonal
   (eu-central), so the host can't relocate out. Check availability via the API
   (`GET /v1/datacenters` → `.server_types.available` contains the type id; `cax11` id=45) and auto-retry
   the targeted host apply when stock returns — never ask the operator to "try again later."

## The permanent fix

`apps/web-platform/infra/zot-registry.tf` now includes `doppler_environment.registry_prd`, and the
provisioning docs/tasks are reframed agent-run. See [[2026-07-07-doppler-branch-config-does-not-isolate-secrets]]
for the isolation fix this provisioning validated live (a scoped `soleur-registry/prd` token reads exactly
the 2 ZOT tokens).
