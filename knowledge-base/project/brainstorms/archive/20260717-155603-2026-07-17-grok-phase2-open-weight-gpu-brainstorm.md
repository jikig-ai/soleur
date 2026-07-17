---
date: 2026-07-17
topic: grok-phase2-open-weight-gpu
issue: 6546
lane: cross-domain
brand_survival_threshold: single-user incident
draft_pr: 6597
---

# Phase 2 — Open-weight model on Hetzner GPU (Grok Build dogfood)

## What We're Building

Operator-only dogfood: run an **open-weight** model (not Grok 4.5 — closed weights) on a **separate Hetzner Robot GEX44-class dedicated GPU host**, serve an OpenAI-compatible endpoint (Ollama default), point Grok Build `~/.grok/config.toml` at loopback, and re-run the **same** three-class measure suite (`scripts/dogfood/grok-measure.sh`) for TTFT / tok/s / host monthly cost vs Phase 1 xAI API baseline (measured 2026-07-16).

Success is a **filled comparison table + short report on #6546**, then destroy or re-approve — not a permanent GPU line item and not product Concierge (#6547 stays parked).

## User-Brand Impact

| Field | Value |
|-------|--------|
| **Artifact** | Grok Build Phase 2 open-weight GPU dogfood host |
| **Vector** | Mislabeling as “self-hosted Grok 4.5,” exposed inference endpoint, or operator secrets/compromise on a YOLO-capable agent host |
| **Threshold** | `single-user incident` (operator-only; escalates if customer data or product traffic appears) |
| **Guards** | Never market as Grok 4.5 on Hetzner; no private-net; no prd secrets; YOLO off by default; license before pull; time-boxed spend |

Tagged user-brand-critical (auto, #5175). CPO + CLO + CTO mandatory; COO + CFO also assessed (procurement + burn envelope).

## Capacity / stock gate (2026-07-17 live)

| Check | Result |
|-------|--------|
| Phase 1 measure report | **Yes** — API Grok 4.5, YOLO off; batch ≈ $0.14; host CX33 `soleur-grok-dogfood` 89.167.98.209 retained |
| Operator wants comparison | **Yes** (session 2026-07-17) |
| Hetzner Cloud fleet | **5 servers** (web-1, web-2, grok-dogfood, registry, inngest) — Cloud slot full |
| Cloud GPU types (`hcloud server-type`) | **None** — `gex44` / `gex130` **not found** among 25 Cloud types |
| GEX product class | **Robot dedicated rootserver** (not Cloud TF) — GEX44 ~€184/mo + setup, RTX 4000 SFF Ada **20 GB VRAM**, FSN1 |
| Doppler `ROBOT_*` | **Absent** — only `HCLOUD_TOKEN`; order is console/Robot |
| Cloud server cap vs Robot | **Separate** — Cloud free-slot gate does **not** block Robot GEX order |

**Do not provision in this brainstorm.** Order only after plan + expense `approved-not-billing` + live stock check + license memo.

### Phase 1 baseline (API, 2026-07-16)

| class | ttft_ms | tok/s | cost USD | exit |
|-------|---------|-------|----------|------|
| read | 2648 | 49.4 | 0.046 | 0 |
| scoped /tmp edit | 2344 | 12.6 | 0.045 | 0 |
| multi-tool | 5239 | 104 | 0.046 | 0 |

Host ~€8.49/mo CX33 + IPv4. Logs: `/var/log/grok-dogfood/runs.jsonl`.

## Why This Approach

### Approaches considered

| Opt | Shape | Verdict |
|-----|--------|---------|
| **A** | Robot GEX44; Ollama + Grok **on GPU host**; `base_url = http://127.0.0.1:…/v1` | **Recommended deliverable** for #6546 / Hetzner story |
| **B** | GEX GPU only; measure stays on CX33 → GPU over public IP | **Rejected** — recreates public OpenAI-compatible trust surface Phase 1 avoided |
| **C** | Short-lived third-party GPU (RunPod/Vast/etc.) from CX33 config | **Optional accelerator** if GEX stock delays; not the issue’s named deliverable |
| **D** | Park all spend | Valid if budget/stock/license fail; operator chose continue |

**Locked recommendation (operator declined multi-choice; leaders + capacity facts):** **Approach A** as the Phase 2 success shape. Optional **C** only as a stock-delay filler. **B out.** Provision not yet.

**Why A:** Matches issue goal (Hetzner GPU + open weights); loopback minimizes trust plane; reuses Phase 1 measure + config placeholder; quality vs Grok 4.5 is **not** the claim — harness + cost curve is.

**Why not Cloud TF parity:** Live API has no GEX Cloud type; `grok_dogfood_server_type` validates `cax|cpx|cx|ccx` only; extending `hcloud_server.grok_dogfood` would lie. Lifecycle = **runbook + expense ledger + bootstrap script (T0/T1)**, not “another `enable_*` on Cloud TF.” Optional Robot API automation is a later deferred item.

**Why Ollama default:** Dogfood simplicity at 1–5 runs/day; vLLM only if Ollama is the measured bottleneck.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Host topology | **Separate Robot GEX44** from Phase 1 CX33 | Keep API baseline host; don’t join private-net; don’t mutate live CX33 into GPU mid-trial |
| Control plane | **Robot console order** (not `hcloud` / not per-PR apply) | GEX is dedicated; no `ROBOT_*` today; host_creates tripwire is Cloud-only |
| Runtime | **Ollama** OpenAI-compatible on loopback | Lowest ops for comparison table |
| Model class | **Apache-2.0 / MIT preferred**; Llama-class only with AUP/MAU awareness; fit **≤20 GB VRAM** (7B–32B quant); **70B out** on GEX44 | License gate before pull (CLO); VRAM bound |
| Measure | Same three prompt classes via `grok-measure.sh --model local-open` | Fair vs Phase 1 table |
| Spend envelope | Default **1-week soak then destroy** (~€130 all-in if pro-rata/hourly OK — **verify at order**); hard month-1 ≤ ~€270; **no auto month-2** | CFO; pure-$ break-even ~4k runs/mo — not a savings play |
| Ledger | GEX + setup (+ IPv4 if any) as `approved-not-billing` **before** order; flip `active` only when live | hermes-agent / expense gate lessons |
| Secrets | Operator-only on host; **never** prd dump / private trust plane | Phase 1 posture |
| Brand | Operator dogfood only; **forbid** “self-hosted Grok 4.5” / “Grok on our GPU” | CPO + CLO |
| Product | **#6547 parked** | Separate epic + CPO/CLO |
| Kill | Spend ceiling, license fail, compromise, customer data, no filled table within **14 days** of first billable hour, stock-forced SKU jump without re-approval | Runbook + destroy = **Robot cancel** |
| TF / IaC | Do **not** widen `hcloud` type regex to fake GEX; document Robot exception as operator R&D dogfood | CTO; optional ADR “Robot dogfood out of Cloud TF” at plan |
| Automation tier | **T0/T1** (runbook + ledger + install script); **not** full Robot-in-TF (T3) | YAGNI for measure campaign |

## License gate (pre-pull)

1. Name exact model id + source (HF/Ollama tag).
2. Read model card license (SPDX or custom URL/date).
3. Classify: OK (Apache/MIT/BSD) / OK-with-conditions (e.g. Llama community) / Reject (NC / field-of-use).
4. Record one-line + link on #6546 or runbook **before** `ollama pull`.
5. Confirm Hetzner AVV covers **Robot dedicated** when ordering (Cloud AVV signed 2026-03-19; document Robot inventory note).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support  
**Spawned:** Product (CPO), Legal (CLO), Engineering (CTO), Operations (COO), Finance (CFO). Marketing/Sales/Support not load-bearing for operator-only R&D.

### Product (CPO)

**Summary:** PROCEED-WITH-GUARDS. R&D learning only (model-portability / harness economics); not product progress or COGS. Time-box + naming ban mandatory. Kill if no decision the table changes.

### Legal (CLO)

**Summary:** PROCEED-WITH-GUARDS. Prefer Apache/MIT; license memo before pull; brand ban; Robot AVV confirmation; gdpr-gate only if kill criteria break (customer/PII path).

### Engineering (CTO)

**Summary:** PROCEED-WITH-GUARDS. A or optional C; reject B; Ollama default; do not pretend Cloud TF mints GEX; T0/T1 lifecycle; loopback inference; success = comparison table not “host exists.”

### Operations (COO)

**Summary:** PARK **order** until plan + stock + license + spend ack; Cloud slot is a red herring for Robot; ledger before birth; destroy = Robot cancel; operator-only order.

### Finance (CFO)

**Summary:** PROCEED-WITH-GUARDS. Default 1-week soak; honest non-break-even vs API at dogfood volume; no silent renewal.

## Open Questions (plan-time)

1. Exact open-weight id + license memo (shortlist at plan; pick one OK license).
2. Live GEX44 stock/price/setup at order time (FSN1 configurator).
3. Confirm dedicated billing pro-ration (hourly vs month minimum) for 1-week kill.
4. Smoke: does Grok Build OpenAI client work against Ollama `/v1` without extra headers?
5. Optional C: if GEX OOS, which EU-friendly short rental and CLO ToS for prompt egress?
6. Whether to file a short ADR for “operator dogfood GPU on Robot outside Cloud TF.”

## Non-Goals

- Product Concierge / ACP / `agent-runner.ts` swap (#6547)
- Joining `10.0.1.0/24` private trust plane
- Self-hosting Grok 4.5 weights (impossible)
- Dual-host measure over public OpenAI-compatible port (Approach B)
- Full Robot Terraform provider parity for this trial
- Marketing or customer-facing claims
- Replacing Phase 1 CX33 unless operator later chooses destroy+consolidate

## Deferred items (already tracked or new)

| Item | Tracking |
|------|----------|
| Product agent runtime via Grok Build ACP | **#6547** (parked) |
| Optional third-party GPU burst (Approach C) | Re-eval if GEX stock blocks; no new issue unless plan chooses C-first |
| Robot webservice / TF automation (T2+) | Defer until second durable Robot host justifies it |

## Capability Gaps (evidenced)

| Gap | Evidence |
|-----|----------|
| No GEX in Cloud API | `hcloud server-type list` / API `server_types` — 25 types, no gex* (2026-07-17) |
| No Robot credentials automation | Doppler `prd_terraform` has `HCLOUD_TOKEN` only |
| No GPU cloud-init | `cloud-init-grok-dogfood.yml` — no NVIDIA/Ollama; Phase 2 config comments only |
| Type validation rejects non-Cloud | `variables.tf` `grok_dogfood_server_type` `^(cax\|cpx\|cx\|ccx)` |
| No GEX expense rows | `knowledge-base/operations/expenses.md` has CX33 + xAI only |

## Prior art

- Brainstorm/spec/plan archive: `20260716-164259-*grok-build-hetzner-trial*`
- Runbook: `knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md` §Phase 2
- Substrate: `apps/web-platform/infra/grok-dogfood.tf`, `cloud-init-grok-dogfood.yml`, `scripts/dogfood/grok-measure.sh`
- Learning: `workflow-patterns/2026-07-16-grok-dogfood-host-no-private-net-yolo-off.md`

## Next Steps

→ `/plan #6546` for HOW (runbook extension, bootstrap script, expense rows, measure report template, destroy path). **No GPU order in plan work without operator spend ack.**
