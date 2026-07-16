---
title: Headless Grok Build Hetzner trial (Grok 4.5 API)
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-grok-build-hetzner-trial
pr: 6544
date: 2026-07-16
brainstorm: knowledge-base/project/brainstorms/2026-07-16-grok-build-hetzner-trial-brainstorm.md
---

# Spec — Headless Grok Build on Hetzner (Phase 1 trial)

## Problem Statement

We want to trial **Grok Build headless** against the Soleur monorepo from a Hetzner host, using **Grok 4.5** for inference, and understand **machine sizing, tok/s, TTFT, and monthly cost** before any product integration. Grok 4.5 cannot be self-hosted; the trial must separate **harness host** cost from **API** cost, and leave a clean path to **open-weight self-host** later.

## Goals

1. Provision a **dedicated EU Hetzner CPU VM** (CX33-class) for operator dogfood only.  
2. Run **Grok Build headless** (`grok -p`, structured output, spend/turn caps) with **Grok 4.5 via xAI API**.  
3. Produce a **measured report**: TTFT, tok/s, $/run, host monthly cost, reliability.  
4. Keep **Phase 2** (open model on GPU via `config.toml`) as a documented model-swap path, not in-scope implement.  
5. Enforce **brand-survival** controls: no customer data, no prod secrets, no false “self-hosted Grok 4.5” claims.

## Non-Goals

- Self-hosting Grok 4.5 weights  
- Concierge / multi-tenant product agent runtime  
- Co-locating agent on web/inngest/registry hosts  
- Phase 2 GPU provision in the same change set (document only)  
- Raising Hetzner account limits as part of this feature code (ops prereq; may be a dependency issue)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Dedicated Hetzner Cloud server of type **cx33** (or documented equivalent if stock forces upgrade), location **EU** (prefer **hel1** for fleet affinity). |
| FR2 | Host runs Linux amd64, Docker optional; **Grok Build CLI** installed and version-pinned for the trial. |
| FR3 | Auth via **`XAI_API_KEY`** (or equivalent) from **operator-scoped** secret store — not `prd` customer/workspace credentials. |
| FR4 | Headless invocation supports: `-p`, `--yolo` or equivalent always-approve **with** deny/allow rules, `--max-turns`, `--output-format json` and `streaming-json`. |
| FR5 | Soleur repo available on host (clone or deploy path) with **no tenant workspace git** and **no production `.env` / Doppler prd dump**. |
| FR6 | Measurement suite captures TTFT, approximate tok/s, per-run usage/cost when available, and wall-clock for a fixed prompt set (minimum 3 prompt classes: read-only review, small edit, multi-tool task). |
| FR7 | Network posture: **no public application ingress** required for the agent; outbound as needed for xAI + GitHub + package mirrors. SSH admin access restricted (admin IP allowlist pattern). |
| FR8 | Cost controls: documented soft budget, xAI billing alert recommendation, default `--max-turns` for unattended runs. |
| FR9 | Spec/docs state **Phase 2** path: custom `[model.*]` pointing at local OpenAI-compatible endpoint on a future GPU host — out of Phase 1 implement scope. |
| FR10 | **Server-slot gate:** plan/apply refuses additive create when account free slots are 0; documents reclaim/limit-raise dependency. |
| FR11 | Phase 1 design is **substrate-first**: model selection only via config/env (no xAI-only hardcode in provision scripts); headless flags and measurement scripts work with any configured model id; document how the same host/pattern would feed a future **Soleur Web → Grok Build (ACP/headless)** product path (implementation of that product path is out of scope). |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Prefer **Terraform** provision consistent with Soleur infra rules (`hr-all-infrastructure-provisioning-servers`, immutable redeploy posture). Exact root path chosen at plan time. |
| TR2 | Record vendor expense in ops expense ledger before ready-for-merge if the host is long-lived (`wg-record-recurring-vendor-expense-before-ready`). |
| TR3 | Observability: host health + agent run results must not depend on SSH as the primary diagnostic path for failures in runbooks (`hr-no-ssh-fallback-in-runbooks` where applicable). |
| TR4 | Secrets never committed; no secrets via bang-prefix patterns. |
| TR5 | Disk: ≥ local capacity for monorepo + deps (~3+ GB working set; prefer ≥40–80 GB disk class as on CX33). |
| TR6 | Concurrency hard-cap 1–2 simultaneous headless runs for Phase 1. |
| TR7 | Git identity policy documented: default **no push** as product bot; optional operator PAT only if explicitly enabled. |

## Acceptance Criteria

1. Host exists (or plan blocked with explicit slot/stock reason).  
2. `grok -p "…"` completes with Grok 4.5 from the host using API key auth.  
3. Measurement doc or log artifact includes TTFT, tok/s estimate, and cost sample for ≥3 runs.  
4. Checklist confirms no `prd` secrets and no tenant data on host.  
5. Phase 2 model-swap documented in the same trial doc.  
6. Expense ledger row for the host (if retained beyond trial week).

## Dependencies / Risks

| Risk | Mitigation |
|------|------------|
| Hetzner **server account cap** (#6453) | Free slot or limit raise before apply |
| hel1 **stock** for cx33 | Stock preflight; alternate type/location only if EU |
| API spend spike | max-turns, scoped prompts, billing alerts |
| Agent touches secrets/prod | Deny rules, no prd secrets on disk, sandbox |
| Miscommunication “we run Grok 4.5 on Hetzner” | Spec language: harness local, model API |

## Success metrics (operator)

- Median TTFT and tok/s from Hetzner EU over N≥10 samples  
- p50/p95 task wall-clock for the fixed suite  
- Monthly projected cost = host + 30× mean $/day API  

## Out of scope follow-ups (deferred issues)

- Phase 2 GPU host + open-weight model dogfood  
- Product Concierge integration with Grok Build ACP  
- Always-on CI worker fleet for PR automation  

## Domain Review (carry-forward)

- **CPO:** operator-only; kill criteria; expense owner  
- **CLO:** no customer PII; xAI outbound for R&D content only  
- **CTO:** dedicated CX33; slot gate; no co-location; Phase 2 = config swap  
