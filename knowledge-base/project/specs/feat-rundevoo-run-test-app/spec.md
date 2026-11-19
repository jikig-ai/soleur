---
title: "rundevoo.run — domain purchase + safe-DNS Terraform onboarding (phase 1)"
issue: 12971
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spec: rundevoo.run domain purchase + zone onboarding

## Overview

Purchase `rundevoo.run` (confirmed available via RDAP 404, 2026-11-19) at
Cloudflare Registrar and onboard its auto-created zone to Terraform under a new
root `infra/rundevoo-run/` with a safe-by-default DNS posture. The domain backs
a future Jikigai product; phase 1 deliberately ships no site and no app — the
product shape is a later brainstorm.

See brainstorm:
`knowledge-base/project/brainstorms/2026-11-19-rundevoo-run-test-app-brainstorm.md`.
Authoritative zone-onboarding checklist: the deferred jikigai plan
`knowledge-base/project/plans/archive/20261013-051752-2026-09-09-feat-jikigai-cloudflare-zone-terraform-plan.md`
— rundevoo.run skips its hard parts (Cloudflare Registrar auto-creates the zone
in-account: no NS cutover, no 28-day pending clock, no mail continuity).

## User-Brand Impact

- **Artifact:** the rundevoo.run domain + DNS/zone posture — the public surface
  a future Jikigai product is published under.
- **Vector:** email spoofed as @rundevoo.run, or arbitrary content served to
  third parties on a company-owned domain attributable to Jikigai SARL.
- **Threshold:** `single-user incident`.

## Problem Statement

Jikigai needs to own `rundevoo.run` before the name is taken, and own it
*safely*: a company domain that can send or be spoofed as email, or that drifts
unmanaged outside IaC, is the documented jikigai.com failure mode (#7995 — zone
died unobserved on the 28-day pending clock). Phase 1 secures the asset: the
purchase (operator payment step) plus full Terraform management of the zone
with mail-spoof hardening.

## Goals

- G1: `rundevoo.run` registered to Jikigai SARL at Cloudflare Registrar, 1-yr,
  auto-renew ON, WHOIS privacy, org registrant email (operator-only step).
- G2: Zone fully Terraform-managed in a new root `infra/rundevoo-run/` —
  `terraform apply` from empty state reproduces it with zero operator steps.
- G3: Mail-spoof hardening live: null MX (RFC 7505), `v=spf1 -all`, DMARC
  `p=reject`, DNSSEC enabled.
- G4: Repo machinery wired: apply workflow, drift-detection matrix leg,
  destroy-guard triple, encryption-posture-ledger `non_store_types` entry.
- G5: Ledgers recorded: `domains.md` row, `expenses.md` dual entries, Article
  30 register amendment/PA.

## Non-Goals

- Product shape for rundevoo.run (dev tool / content / API) — follow-up
  brainstorm.
- Any site, app scaffold, deploy loop, or hosting substrate — none in phase 1.
- App repo placement (`apps/` vs separate repo) — decided with the product.
- Legal pages, trademark filing — conditional on the product going public.
- Email sending capability — explicitly never on the apex (null MX posture).

## Functional Requirements

- FR1: Operator purchases the domain at Cloudflare Registrar (payment entry —
  the only operator step); agent verifies registration + zone creation via the
  Cloudflare API.
- FR2: New TF root `infra/rundevoo-run/` with R2 backend
  (`soleur-terraform-state`, key `rundevoo-run/terraform.tfstate`) copied from
  `apps/cla-evidence/infra/main.tf` precedent.
- FR3: `cloudflare_zone` imported (zone pre-exists via Registrar); provider
  `~> 4.0` schema dumped locally before authoring resources.
- FR4: `Zone:DNS:Edit`-scoped `cloudflare_api_token` for the rundevoo.run zone
  only, minted via the bootstrap ephemeral-admin pattern
  (`apps/cla-evidence/infra/bootstrap.sh` precedent); no standing
  account-scoped credential in Doppler.
- FR5: DNS records: null MX (`MX 0 .`), `TXT "v=spf1 -all"`, DMARC
  `v=DMARC1; p=reject`, `cloudflare_zone_dnssec` enabled.
- FR6: `apply-rundevoo-infra.yml` (or equivalent) mirroring
  `apply-sentry-infra.yml` (full-root apply, destroy gate, `[skip-*]` kill
  switch, dispatch escape hatch).
- FR7: `scheduled-terraform-drift.yml` matrix entry for the new root;
  `destroy-guard-filter-rundevoo.jq` + counter test + CODEOWNERS rows.
- FR8: `cloudflare_zone` added to `scripts/encryption-posture-ledger.json`
  `non_store_types` (lint-encryption-posture is fail-closed).
- FR9: `domains.md` row + `expenses.md` Recurring ($21.20/yr) + One-Time
  registration rows; Article 30 register dated amendment naming the surface.
- FR10: Any `TF_VAR_*` the new root needs exists in Doppler (`prd_terraform`)
  before the IaC merges (ADR-065 sequencing).

## Technical Requirements

- TR1: No new no-default variable in `apps/web-platform/infra` — its
  merge-apply resolves every root variable before `-target` pruning.
- TR2: `hr-every-new-terraform-root-must-include-an` — R2 backend, no state
  locking (`use_lockfile=false`), secrets mirrored to Doppler.
- TR3: `hr-all-infrastructure-provisioning-servers` — every DNS/zone change via
  Terraform; no dashboard click-paths.
- TR4: `hr-tf-variable-no-operator-mint-default` — provider-side mint
  (bootstrap pattern) for all credentials.
- TR5: `infra-validation.yml` auto-discovers `infra/rundevoo-run/` (find glob);
  `.pr-plan-skip` census test must not be tripped (no sentinel file).
- TR6: Observability block required at plan time
  (`hr-observability-as-plan-quality-gate`): drift leg + apply workflow are the
  discoverability path.

## Deferred Follow-ups

- Product-shape brainstorm for rundevoo.run (filed at brainstorm close).
- Optional: trademark knock-out search on "rundevoo" (operator homework).
- Housekeeping: verify soleur.ai registrant entity is Jikigai SARL.

## Acceptance Criteria

Mirrors issue #12971: purchased + auto-renew + Jikigai SARL registrant;
`terraform apply` reproduces zone + hardening from empty state; `dig MX`
returns null MX, SPF `-all`, DMARC `p=reject`, DNSSEC on; drift matrix +
destroy-guard + ledger entries present and `lint-encryption-posture.py` green.
