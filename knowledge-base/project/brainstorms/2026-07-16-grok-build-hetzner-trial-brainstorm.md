---
date: 2026-07-16
topic: grok-build-hetzner-trial
issue: 6545
phase2_issue: 6546
pr: 6544
branch: feat-grok-build-hetzner-trial
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm — Headless Grok Build trial on Hetzner (Grok 4.5 API first)

## User-Brand Impact

- **Artifact:** Operator dogfood host running Grok Build headless with `XAI_API_KEY` and a Soleur monorepo checkout
- **Vector:** API-key leak, runaway spend, accidental prod-secret or customer-data exposure in prompts/tools, autonomous `--yolo` damage, false marketing claim that “Soleur self-hosts Grok 4.5”
- **Threshold:** `single-user incident`

Tagged **user-brand-critical** (auto, per #5175). Domain leaders (CPO/CLO/CTO composite) assessed **PROCEED-WITH-GUARDS**.

## What We're Building

A **Phase 1 operator dogfood trial**: install and run **Grok Build** in **headless** mode on a **dedicated Hetzner Cloud CPU VM** (CX33-class, EU), pointed at **Grok 4.5 via the xAI API**. Workload is **1–5 agent runs/day** against the **Soleur monorepo** (reviews, scoped tasks) — not Concierge/product traffic.

**Phase 2 (deferred):** same harness, swap brain to an **open-weight model on Hetzner GPU** via Grok Build `[model.*]` / Ollama-or-vLLM `base_url` — not Grok 4.5 weights (closed).

### Explicit non-goals (Phase 1)

- Self-hosting Grok 4.5 weights (impossible / not offered)
- Product agent backend for Soleur Web / Concierge
- Co-locating the agent on web / inngest / registry hosts
- Marketing “Grok 4.5 runs on our Hetzner”
- Customer/workspace git or PII on the dogfood host

## Why This Approach

| Layer | Where it runs | Implication |
|-------|---------------|-------------|
| Grok Build harness (CLI, tools, sessions) | Hetzner VM | Needs CPU/RAM/disk for monorepo + tool loops |
| Grok 4.5 inference | xAI API | Tok/s, TTFT, quality are mostly **API + network** |
| Open model (Phase 2) | Hetzner GPU | Host cost dominates; quality varies by model |

**Recommended shape: Approach A — dedicated CX33 always-on dogfood host**, after a free server slot exists.

Prior art: fleet already uses small CPU boxes (`cx33` web, `cpx22` inngest, `cax11`/`cx23` registry). Grok binary ~155 MB; hydrated Soleur worktree ~2.4 GB (web-platform `node_modules` heavy). #6453 headroom brainstorm: **additive** hosts can hit account **server cap** — prereq before provision.

## Performance & cost model (Phase 1)

| Metric | Phase 1 estimate | Driver |
|--------|------------------|--------|
| Host type | **CX33** (4 vCPU / 8 GB / ~160 GB disk) EU (hel1 preferred) | Monorepo + tooling; 4 GB RAM too tight |
| Tok/s | ~**80–90** gen tps (public ~86 for Grok 4.5) | **xAI**, not Hetzner CPU |
| TTFT | ~**1.0–1.5 s** from EU | Network + API queue; measure with `streaming-json` |
| Host cost | ~**€6–12/mo** (+ IPv4 if billed) | Verify live Hetzner console (post–Jun 2026 CX pricing) |
| API cost | ~**$30–120/mo** at 1–5 runs/day | Dominates; context size and turns skew heavily |
| All-in | ~**$40–140/mo** | API >> host |

**Host-bound:** tool wall-clock (git, npm, tests), disk, concurrency.  
**Not host-bound:** generation tok/s, TTFT, model quality.

### Phase 2 (later) rough

| Item | Estimate |
|------|----------|
| Host | GEX44-class GPU ~€184+/mo (20 GB VRAM) entry; larger for 70B-class |
| Tok/s / TTFT | Model- and quant-dependent |
| API inference $ | Near zero if fully local |

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Phase 1 = headless Grok Build + Grok 4.5 API** on dedicated Hetzner CPU | Matches “try Grok 4.5” without false self-host claim; lowest infra cost |
| 2 | **Phase 2 = open model on GPU later** via `config.toml` custom model | Path open without overbuilding Phase 1 |
| 3 | **Primary goal = operator dogfood** on Soleur repo (1–5 runs/day) | Not product Concierge; smallest brand blast radius |
| 4 | **Approach A: dedicated CX33-class always-on host** | Isolation; enough RAM/disk; TF-managed like rest of fleet |
| 5 | **Server-slot prereq before create** | #6453: additive create may `resource_limit_exceeded`; reclaim/limit-raise first — do not sacrifice prod fleet |
| 6 | **No co-location** with web/inngest/registry | Brand + resource contention |
| 7 | **Operator-only secrets** — no `prd` customer/workspace keys; no tenant git/PII | CLO: controller R&D purpose; xAI sees only non-customer code/prompts |
| 8 | **Hard spend + turn caps** as first-class trial controls | API dominates bill; `--max-turns`, billing alerts, per-run JSON usage |
| 9 | **Success = measured harness fidelity + cost ledger**, not feature ship velocity | CPO: dogfood metrics, kill criteria pre-declared |
| 10 | **Do not market as self-hosted Grok 4.5** | Accuracy / brand |

## Measurement plan (trial success criteria)

1. **TTFT** — first `streaming-json` text event after prompt start  
2. **Tok/s** — output tokens / generation wall time (from usage + timestamps)  
3. **$/run** and **$/mo** — from headless `usage` / `total_cost_usd` when stamped; else xAI console  
4. **Task wall-clock** — end-to-end including tools  
5. **Reliability** — exit codes, max-turns hits, auth failures  
6. **Security** — zero prod secret files on host; outbound allowlist sanity

## Open Questions

1. Exact live CX33 monthly price + hel1 stock at provision time (console-verify).  
2. Is a free server slot available **now**, or is limit-raise / reclaim still open from #6453?  
3. Operator API budget ceiling (soft default ~$100/mo suggested; not locked).  
4. Git identity on the host: read-only clone only vs ability to open draft PRs.  
5. Doppler project/config name for the dogfood host (new config vs reuse `dev`).  
6. Whether trial TF lives under `apps/web-platform/infra` or a small separate root (plan-time).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support  

*(Named subagent types `soleur:product:cpo` / `soleur:legal:clo` / `soleur:engineering:cto` failed to register in this harness session; assessments produced via a single general-purpose triad pass with the same prompts.)*

### Product (CPO)

**Summary:** PROCEED-WITH-GUARDS. Pure operator R&D; never Concierge or customer workspaces. Success = cost/quality/fidelity of headless Grok dogfood, not product roadmap. Kill criteria and expense row required before first billable run.

### Legal (CLO)

**Summary:** PROCEED-WITH-GUARDS. Purpose = controller’s own R&D on Soleur code + operator prompts. No end-user personal data. xAI is outbound processor for agent payloads — allow only non-customer content. Host EU under existing Hetzner DPA. Privacy/TOU change only if this becomes product-facing.

### Engineering (CTO)

**Summary:** PROCEED-WITH-GUARDS. Dedicated TF VM (CX33), not co-located. Operator-scoped secrets, deny public app ingress, concurrency hard-cap 1–2. **Hard blocker:** free Hetzner server slot or limit raise before additive create. Keep Phase 2 as model swap via config.

## Capability Gaps

| Gap | Evidence | Domain |
|-----|----------|--------|
| Free server slot for additive dogfood host | #6453 brainstorm: account cap blocks *additive* creates; hermes-agent reclaim / limit→10 path | Ops / Engineering |
| Dedicated TF root for “agent dogfood” host | `apps/web-platform/infra/` has web/inngest/registry/git-data — no grok-agent host resource yet | Engineering |
| Operator-only Doppler config for `XAI_API_KEY` on remote host | Pattern exists for other hosts; not yet specified for this trial | Ops / Security |

## Approaches considered

| Approach | Outcome |
|----------|---------|
| A Dedicated CX33 always-on | **Chosen** |
| B Time-boxed benchmark then destroy | Rejected for this pass (weaker ongoing dogfood) |
| C Co-locate on existing host | Rejected (blast radius / contention) |
| Self-host Grok 4.5 on GPU | Impossible — closed weights; Phase 2 uses *open* models only |

## Lane

`cross-domain` (USER_BRAND_CRITICAL always-on).

## Session Errors

- Named domain leader `subagent_type` values failed registration in Grok Build session (`Unknown subagent type` despite appearing in available list); fell back to general-purpose triad assessment.
