---
title: Phase 2 — Open-weight Grok Build dogfood on Hetzner Robot GPU
issue: 6546
# Close only after post-merge soak: comparison table + ledger + destroy/re-approve.
# Pre-merge PR body must use Ref #6546 (not Closes) — artifacts-only until operator gates.
closes_after: comparison-table-and-ledger
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
date: 2026-07-17
brainstorm: knowledge-base/project/brainstorms/2026-07-17-grok-phase2-open-weight-gpu-brainstorm.md
plan: knowledge-base/project/plans/2026-07-17-feat-phase2-open-weight-gex-gpu-dogfood-plan.md
branch: feat-grok-phase2-open-weight-gpu
draft_pr: 6597
---

# Spec — Phase 2 open-weight GPU dogfood (#6546)

## Problem Statement

Phase 1 proved headless Grok Build on Hetzner CX33 against **xAI API** (Grok 4.5). We still lack a measured **open-weight, self-hosted** cost/latency comparison on the same harness. Grok 4.5 weights are not self-hostable. Hetzner **GEX** GPUs are **Robot dedicated**, not Cloud `hcloud` types — so Phase 2 is a new substrate class, not a server_type flip on `grok-dogfood.tf`.

## Goals

1. Run open-weight inference (Ollama default) on a **separate** Robot GEX44-class host with loopback OpenAI-compatible endpoint.
2. Point Grok Build `[model.local-open]` at that endpoint; re-run the **same** three measure prompt classes.
3. Publish comparison table (TTFT, tok/s, host monthly, batch $) vs Phase 1 API baseline on #6546.
4. Expense ledger + kill/destroy path **before** long-lived bill.
5. Preserve Phase 1 CX33 and isolation posture (no private-net, YOLO off default, no prd secrets).

## Non-Goals

- Product Concierge / ACP runtime (#6547)
- Self-hosting Grok 4.5 or marketing that claim
- Dual-host measure over a public inference port (Approach B)
- Full Robot Terraform provider / Cloud TF parity for GEX
- Joining `10.0.1.0/24` trust plane
- Always-on GPU without a time-box / re-approval

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Capacity gate recorded: Cloud fleet inventory, confirmation GEX is Robot (not Cloud type), live stock check at order time. |
| FR2 | License memo for chosen model (OK / OK-with-conditions / Reject) recorded before first model pull. |
| FR3 | Separate GPU host from Phase 1 CX33; inference bound to **127.0.0.1** when Grok co-located. |
| FR4 | Runtime: Ollama (or equivalent OpenAI-compatible) serving chosen open weights fitting **≤20 GB VRAM**. |
| FR5 | Grok Build config: `[model.local-open]` with `base_url` to local `/v1`; measure via `scripts/dogfood/grok-measure.sh --model local-open` (YOLO default off). |
| FR6 | Same three prompt classes as Phase 1 (read, scoped /tmp edit, multi-tool). |
| FR7 | Report on #6546: TTFT, tok/s, exit codes, host monthly, setup fee, comparison narrative (not quality-parity claim). |
| FR8 | Expense rows: GEX (+ setup, IPv4 if any) `approved-not-billing` before order; `active` when live; `retired` on cancel. |
| FR9 | Runbook Phase 2 updated with actual SKU, model id, pin versions, destroy (Robot cancel), kill criteria. |
| FR10 | Default spend: time-box **1-week soak** then destroy unless operator re-approves; hard stop if no comparison table within **14 days** of first billable hour. |
| FR11 | No customer data, no prd secrets, no private-net attach, SSH admin_ips only. |
| FR12 | Brand: artifacts and comments never claim self-hosted Grok 4.5. |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Do **not** extend `hcloud_server.grok_dogfood` / `grok_dogfood_server_type` to fake GEX Cloud types. |
| TR2 | Provision path: operator Robot console (or documented webservice later) + bootstrap script; not per-PR Cloud apply birth. |
| TR3 | Prefer Apache-2.0/MIT models; document Llama-class conditions if used. |
| TR4 | Confirm Hetzner processor terms cover Robot dedicated at order; note in compliance posture if needed. |
| TR5 | Measure logs: metrics JSONL only; no secrets; retention ≤ trial + 14d; assume wipe on Robot cancel. |
| TR6 | Optional Approach C (third-party GPU) only if GEX stock blocks and operator accepts egress ToS — not default. |
| TR7 | Architecture decision: document Robot-out-of-Cloud-TF exception for operator dogfood (plan may create ADR). |

## Acceptance Criteria

1. Comparison table for three classes posted on #6546 (or linked artifact).
2. Runbook Phase 2 reflects live host type, model, versions, destroy path.
3. Ledger matches live billing state (no phantom active; no silent birth).
4. Kill criteria and brand ban documented and applied.
5. Phase 1 CX33 still available unless operator explicitly consolidates.
6. #6547 remains unblocked only by product decision — not auto-unparked by Phase 2.

## Brand-survival threshold

`single-user incident` — operator dogfood only.

## Lane

`cross-domain` (CPO + CLO + CTO + COO + CFO).

## Risks

| Risk | Mitigation |
|------|------------|
| GEX stock OOS | Live check before order; optional C filler |
| Setup fee sunk | Time-box; don’t order until measure plan ready |
| License surprise | Pre-pull memo |
| Brand mislabel | Explicit ban in runbook/report |
| Fake Cloud TF path | TR1 |
| Cost never beats API | CFO honesty — learning only |

## Dependencies

- Phase 1 host + measure suite (done)
- Operator Robot account access
- Open-weight license choice
- Expense approval before order
