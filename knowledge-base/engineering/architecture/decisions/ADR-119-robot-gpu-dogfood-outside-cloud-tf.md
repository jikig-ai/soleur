---
title: Operator R&D GPU dogfood on Hetzner Robot may live outside Cloud Terraform
status: accepted
date: 2026-07-17
issue: 6546
supersedes: null
---

# ADR-119: Robot GPU dogfood outside Cloud Terraform

## Context

Phase 2 open-weight Grok Build dogfood (#6546) needs a Hetzner **GEX44** GPU host (RTX 4000 SFF Ada, 20 GB VRAM). Live Hetzner **Cloud** has no GEX server type; `apps/web-platform/infra` `grok_dogfood_server_type` validates only Cloud families (`cax|cpx|cx|ccx`). Extending `hcloud_server.grok_dogfood` to “fake GEX” would lie. Doppler has `HCLOUD_TOKEN` only — no `ROBOT_*` automation today.

Default infra policy prefers Terraform for servers. A one-week operator R&D soak on Robot dedicated is a deliberate exception, not a general SSH waiver.

## Decision

1. **Time-boxed operator R&D GPU dogfood on Hetzner Robot may be provisioned outside Cloud Terraform** when no Cloud SKU exists.
2. **Lifecycle (required):** runbook + expense ledger (`approved-not-billing` before order → `active` when live → `retired` on cancel) + idempotent bootstrap script + explicit **Robot cancel** destroy path.
3. **Never fake Cloud types** — do not widen `grok_dogfood_server_type` or invent `hcloud` GEX resources.
4. **Isolation non-edges (Approach A):**
   - Ollama inference **loopback only** (`127.0.0.1`); no public OpenAI-compatible port.
   - Grok CLI + measure + Ollama **co-located** on the GEX host; Phase 1 CX33 is API baseline only — not a remote client of GEX.
   - **No** private-net join (`10.0.1.0/24`).
   - **No** product Concierge / `agent-runner` edge to GEX (#6547 stays parked).
5. **Second durable Robot host** triggers revisit: T2 Robot automation and C4 model update. Ephemeral ≤1-week hosts need not land in C4.

## Consequences

- Operators must pass spend ack + stock + license before order; shadow hosts without ledger are a known failure mode (hermes-agent).
- Destroy path for Phase 2 is **Robot cancel**, not `TF_VAR_enable_grok_dogfood=false` (that remains Phase 1 only).
- Measure campaigns re-assert loopback every run; bootstrap-once is insufficient.

## Alternatives considered

| Alternative | Why not |
|-------------|---------|
| Fake Cloud GEX type in TF | Lies; validation forbids |
| Approach B public port + CX33 client | Rejected trust surface |
| Full Robot TF provider now | YAGNI until second durable host |
| Park all GPU spend | Valid if gates fail; operator chose continue with gates |
