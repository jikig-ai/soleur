---
plan: knowledge-base/project/plans/2026-06-17-feat-resend-receiving-key-iac-plan.md
issue: 5480
branch: feat-one-shot-5480-resend-receiving-key
lane: single-domain
adr: ADR-065
---

# Tasks — Provision RESEND_RECEIVING_API_KEY (IaC only)

> **BLOCKING operator prerequisites (must complete before merge — ADR-065 /
> `hr-tf-variable-no-operator-mint-default` / `wg-block-pr-ready-on-undeferred-operator-steps`):**
> P-1. Mint a receiving/full-access Resend API key at resend.com/api-keys (distinct from the
>      send-scoped RESEND_API_KEY). Operator-gated — no creation API.
> P-2. Place the minted value into Doppler `soleur` / `prd_terraform` as
>      `TF_VAR_resend_receiving_api_key`.
> Do NOT mark the PR ready / enable auto-merge until BOTH are confirmed.

## Phase 1 — IaC (the three prescribed edits)

- [ ] 1.1 `apps/web-platform/infra/variables.tf` — add `variable "resend_receiving_api_key"`
      (`type = string`, `sensitive = true`, **no `default`**) after the `resend_api_key` block
      (~line 156). Verbatim text in plan §Files to Edit #1.
- [ ] 1.2 Create `apps/web-platform/infra/resend.tf` (NEW FILE) with
      `resource "doppler_secret" "resend_receiving_api_key"` (`project = "soleur"`, `config = "prd"`,
      `name = "RESEND_RECEIVING_API_KEY"`, `value = var.resend_receiving_api_key`,
      `visibility = "masked"`, `lifecycle { ignore_changes = [value] }`). Verbatim text + header
      comment in plan §Files to Edit #2. Mirror `github-app.tf:40-80`.
- [ ] 1.3 `.github/workflows/apply-web-platform-infra.yml` — append exactly one line
      `-target=doppler_secret.resend_receiving_api_key` to the **non-SSH plan allowlist**, after
      `-target=hcloud_firewall_attachment.web` (line 350) and before the `terraform show` step. Add a
      trailing `\` to the prior line. Do NOT touch the line-526 `terraform_data` SSH apply block.

## Phase 2 — Pre-merge verification (read-only / format-only)

- [ ] 2.1 `cd apps/web-platform/infra && terraform fmt -check variables.tf resend.tf` passes (AC5).
      (`terraform validate` is NOT runnable pre-merge — the no-default var errors until the operator
      sets `TF_VAR_*`; that error IS the ADR-065 gate. Defer validate to the post-merge auto-apply.)
- [ ] 2.2 AC1: `grep -A4 'variable "resend_receiving_api_key"' apps/web-platform/infra/variables.tf`
      shows `sensitive = true`, no `default` line.
- [ ] 2.3 AC2: `grep -E 'config|name|value|visibility|ignore_changes' apps/web-platform/infra/resend.tf`
      shows all five.
- [ ] 2.4 AC3 (least-privilege): `grep -rn 'resend_receiving_api_key\|RESEND_RECEIVING_API_KEY'
      apps/web-platform/infra/cloud-init.yml apps/web-platform/infra/server.tf` returns **zero**.
- [ ] 2.5 AC4: `grep -c -- '-target=doppler_secret.resend_receiving_api_key'
      .github/workflows/apply-web-platform-infra.yml` returns `1`, in the non-SSH plan step.

## Phase 3 — Ship

- [ ] 3.1 PR body: `Closes #5480` (the parent #5468 was already closed by PR #5475). Restate the two
      BLOCKING operator prerequisites in the PR body. Reference ADR-065.
- [ ] 3.2 Confirm both operator prerequisites (P-1, P-2) are done BEFORE marking ready / enabling
      auto-merge (`wg-block-pr-ready-on-undeferred-operator-steps`).

## Phase 4 — Post-merge verification (automated + read-only)

- [ ] 4.1 AC7: `apply-web-platform-infra.yml` apply is green; `Plan:` shows `1 to add` for
      `doppler_secret.resend_receiving_api_key`.
- [ ] 4.2 AC8: `doppler secrets get RESEND_RECEIVING_API_KEY -p soleur -c prd --plain | head -c 4`
      returns a non-empty prefix; then the Supabase MCP read
      `select id, mail_class, summary from email_triage_items where mail_class is null and
      statutory_class is null and created_at > now() - interval '7 days';` trends to zero. Never a
      manual UPDATE (WORM trigger).
