---
title: "feat: Headless Grok Build dogfood trial on Hetzner (Grok 4.5 API)"
date: 2026-07-16
type: feat
issue: 6545
phase2_issue: 6546
pr: 6544
branch: feat-grok-build-hetzner-trial
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: plan-draft
brainstorm: knowledge-base/project/brainstorms/2026-07-16-grok-build-hetzner-trial-brainstorm.md
spec: knowledge-base/project/specs/feat-grok-build-hetzner-trial/spec.md
---

# Plan — Headless Grok Build Hetzner trial (Phase 1)

## Overview

Stand up a **dedicated Hetzner CX33-class EU host** that runs **Grok Build headless** against the Soleur monorepo, with **Grok 4.5 inference via xAI API**. Measure **TTFT, tok/s, $/run, host monthly cost**, and document the path to **Phase 2 open-weight GPU** and a later **product agent runtime** that replaces Soleur Web’s Claude Agent SDK path with Grok Build (ACP/headless).

### Is Phase 1 throwaway?

**No — if we implement it as substrate.** Operator concern (2026-07-16): API dogfood must not be wasted when moving to open models and when Soleur Web adopts Grok Build instead of `@anthropic-ai/claude-agent-sdk`.

| Keep (substrate) | Swap later | Product epic (out of this plan) |
|------------------|------------|----------------------------------|
| Grok Build CLI/harness install + version pin | Default model endpoint (xAI → Ollama/vLLM) | Wire Concierge/`agent-runner` to Grok ACP or headless worker |
| `config.toml` model routing (`[model.*]`, `default`) | Model id string | Multi-tenant session mapping, billing, UX |
| Headless flags + measurement scripts | Prompt suite content | Product SLAs |
| Secrets/sandbox/spend gates | API key vs local endpoint auth | Customer data policies |
| Terraform host pattern (CPU now; GPU later as second type) | `server_type` | Fleet autoscaling |

**Product trajectory (documented only here):** Soleur Web today uses `@anthropic-ai/claude-agent-sdk` in `apps/web-platform/server/agent-runner.ts`. A future epic would treat a Grok Build host (or sidecar) as the agent backend via **ACP** (`grok agent stdio` / `serve`) or headless job dispatch — **not** re-implementing the tool loop in TypeScript. Phase 1 proves host + harness + model-swap + cost; it does **not** replace Claude SDK in product code.

### Premise validation

| Premise | Status |
|---------|--------|
| #6545 open tracking | OPEN |
| Grok 4.5 self-hostable | **False** — API only; Phase 2 = open weights |
| #6453 server cap | CLOSED 2026-07-15; **still verify live free slots** before additive create (cap may still be 5; hermes reclaim may have freed one) |
| Existing agent runtime | Claude Agent SDK on web-platform — product swap is later epic |

## Research Reconciliation — Spec vs Codebase

| Spec claim | Reality | Plan response |
|------------|---------|---------------|
| Dedicated dogfood host TF | No `grok-agent` resource in `apps/web-platform/infra/` | Add TF resources (or thin separate root if cleaner — prefer extend existing root with R2 backend) |
| Free server slot | #6453 closed; live count unknown | Phase 0 live `hcloud` inventory gate |
| Operator expense ledger | `knowledge-base/engineering/operations/expenses.md` | Row before long-lived host ready |
| Product uses Claude SDK | `agent-runner.ts` imports `@anthropic-ai/claude-agent-sdk` | Document trajectory; **no product code change in this plan** |

## User-Brand Impact

**If this lands broken, the user experiences:** N/A for customers — this is operator-only. Operator experiences a compromised dogfood host, runaway xAI bill, or accidental production-touching agent actions.

**If this leaks, the user's [data / workflow / money] is exposed via:** Operator API key + any secrets mistakenly placed on the host; prompts sent to xAI; autonomous shell on monorepo.

**Brand-survival threshold:** `single-user incident`

Requires CPO sign-off at plan time (carried from brainstorm PROCEED-WITH-GUARDS).

## Sizing & cost (planning defaults)

| Item | Value |
|------|--------|
| Host | `cx33` (4 vCPU / 8 GB), location `hel1` preferred |
| Disk | CX33 local (~160 GB class) — monorepo ~2.4 GB hydrated |
| Grok binary | ~155 MB (`linux-x86_64`) |
| Tok/s (Grok 4.5) | ~80–90 (API-bound) |
| TTFT | ~1.0–1.5 s from EU (measure) |
| Host $/mo | ~€6–12 (verify console) |
| API $/mo @ 1–5 runs/day | ~$30–120 (skew high with fat context) |
| Soft API ceiling | $100/mo default for trial kill-switch (operator can raise) |

## Implementation Phases

### Phase 0 — Capacity & secrets gates (no create yet)

1. Live Hetzner inventory: list servers, count, compare to account limit; confirm free slot **or** block with explicit next step (limit raise / reclaim).  
2. Stock check: `cx33` orderable in `hel1` (else EU alternative of equal RAM).  
3. Confirm operator Doppler path for `XAI_API_KEY` (new config vs `dev` — prefer dedicated `dogfood_grok` or similar; **never** dump `prd`).  
4. Record planned monthly host cost intent in expense notes (row when host exists).

### Phase 1 — Terraform host (IaC only)

1. Extend `apps/web-platform/infra/` (preferred) with resources for `grok-dogfood` host: server, firewall (SSH admin IPs only + outbound), optional private net attachment if fleet pattern requires it, labels `app=grok-dogfood`, `role=operator-dogfood`.  
2. Cloud-init: install `grok` binary (pinned version), git, base build tools; create `/opt/soleur-dogfood` workspace user (non-root for agent runs if practical).  
3. Variables: `grok_dogfood_server_type` default `cx33`, `grok_dogfood_location` default `hel1`, `enable_grok_dogfood` bool default `false` so merge without free slot does not force create — flip true when slot free.  
4. Outputs: IPv4, labels, server id.  
5. Apply path: existing `apply-web-platform-infra.yml` with careful `-target` if root uses target allowlists; **do not** co-locate on web/inngest.

### Phase 2 — Bootstrap dogfood environment (idempotent script)

1. Clone Soleur (read-only deploy key or HTTPS) into workspace; **no** workspace tenant git.  
2. Write `~/.grok/config.toml` with model default = Grok 4.5 id; structure allows later `[model.local]` without reinstall.  
3. Inject API key via Doppler/cloud-init secret file with 0600 perms (not in git).  
4. Measurement wrapper script: `scripts/dogfood/grok-measure.sh` (or under infra) wrapping `grok -p … --output-format streaming-json --max-turns N` and emitting TTFT / tok/s / cost fields to a JSONL log.

### Phase 3 — Measurement suite (1–5 runs/day design)

Fixed prompt classes (no prod secrets):

1. Read-only: summarize a small known file.  
2. Scoped edit: create a file under `/tmp` or dogfood-only path.  
3. Multi-tool: `git status` + list dir (no push).

Capture ≥3 runs of each over ≥2 days when possible; document medians in `knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md`.

### Phase 4 — Guards & kill criteria

1. Default `--max-turns` (e.g. 30) for unattended.  
2. Deny rules for sensitive globs if present.  
3. Document kill: API spend > soft ceiling, any customer data touch, host compromise → disable `enable_grok_dogfood` / destroy.  
4. No `git push` credentials by default.

### Phase 5 — Phase 2 & product trajectory docs

1. Runbook section: swap to open model (`base_url`, `model`, no `XAI_API_KEY` required).  
2. Runbook section: future Soleur Web integration via ACP (`grok agent serve` / stdio) — explicitly **not** implemented; points at `agent-runner.ts` as current Claude path.  
3. Expense ledger row for host if retained.

## Infrastructure (IaC)

### Terraform changes

- Files (expected): `apps/web-platform/infra/grok-dogfood.tf` (new), `variables.tf`, `outputs.tf`, possibly `firewall.tf` ruleset extension, `network.tf` if private IP assigned.  
- Provider: existing `hcloud`.  
- Sensitive: no API keys in TF state — keys via Doppler/runtime only.  
- Feature flag: `enable_grok_dogfood` (bool, default false).

### Apply path

- **cloud-init + optional bootstrap script** for already-running host config updates.  
- First provision: enable flag + apply when free slot confirmed.  
- Blast radius: one new host; no web traffic; destroy is clean.

### Distinctness / drift safeguards

- Labels distinguish from product fleet.  
- `lifecycle` only if needed; prefer pure create/destroy for dogfood.  
- State: existing R2 backend.

### Vendor-tier reality check

- Hetzner bills per server; account **server count limit** is free to raise but latency-bound.  
- xAI API pay-as-you-go — soft ceiling outside TF.

## Observability

```yaml
liveness_signal:
  what: host uptime + last successful grok-measure JSONL line age
  cadence: daily operator or cron check of log mtime
  alert_target: operator (Better Stack optional heartbeat if cheap)
  configured_in: runbook + optional heartbeat file
error_reporting:
  destination: JSONL on host + optional Sentry only if agent run fails critically (operator dogfood — keep minimal)
  fail_loud: non-zero exit from measure script is the signal
failure_modes:
  - mode: no free Hetzner slot
    detection: hcloud inventory / apply resource_limit_exceeded
    alert_route: plan Phase 0 gate fails closed
  - mode: API auth failure
    detection: grok exit + log error
    alert_route: JSONL + operator
  - mode: spend runaway
    detection: xAI console / cumulative usage in JSONL
    alert_route: soft ceiling kill in runbook
logs:
  where: /var/log/grok-dogfood/*.jsonl (or under workspace)
  retention: 30 days local then delete
discoverability_test:
  command: 'test -f knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md && grep -q TTFT knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md'
  expected_output: runbook present with measurement section
```

## Architecture Decision (ADR/C4)

**No new architectural product decision in Phase 1** (dogfood host only).  

- **ADR:** None required for a labeled operator host.  
- **C4:** Optional future epic will add external system “Grok Build agent host” when product wires ACP — **not** this plan. Completeness check: product agent container remains Claude SDK; no C4 edge change until product epic. Checked actors/systems: operator, xAI API (external), Hetzner host (infra), Soleur monorepo clone (non-tenant).

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Operations, Finance  

### Product

**Status:** reviewed (brainstorm carry-forward)  
**Assessment:** PROCEED-WITH-GUARDS; operator-only; kill criteria; no Concierge traffic; Phase 1 substrate for later Grok product path.

### Legal

**Status:** reviewed (brainstorm carry-forward)  
**Assessment:** R&D processing; no customer PII; xAI outbound for operator prompts/code only; EU host.

### Engineering

**Status:** reviewed (brainstorm carry-forward)  
**Assessment:** Dedicated CX33; no co-location; config-driven model; slot gate; product Claude→Grok is separate epic.

### Product/UX Gate

**Tier:** none (no UI surface files)  
**Decision:** N/A  
**Pencil available:** N/A (no UI surface)

## Open Code-Review Overlap

None (plan targets new infra/runbook paths; no open code-review issues expected on non-existent `grok-dogfood.tf` — re-check at /work).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `enable_grok_dogfood` flag exists; default **false**  
- [ ] TF resources for dogfood host valid (`terraform validate`)  
- [ ] Bootstrap/measure scripts use **model from config**, not hard-coded xAI-only paths beyond default model id  
- [ ] Runbook documents TTFT/tok/s/cost method + Phase 2 swap + product ACP trajectory  
- [ ] No `prd` secrets referenced  
- [ ] Expense ledger update path documented  
- [ ] Tests: unit/shell checks for measure script parsing if added  
- [ ] `Ref #6545` (not Closes until host measured live if apply is post-merge)

### Post-merge (operator) — automation preference

- [ ] Live slot check via `hcloud` CLI/API (`Automation: CLI`)  
- [ ] Flip enable + apply when slot free (`Automation: TF apply via existing pipeline / targeted apply`)  
- [ ] First measure suite run; paste results into runbook or issue comment (`Automation: SSH once for dogfood — prefer remote script over interactive`)  
- [ ] Soft API budget alert set in xAI console (`automation-status: UNVERIFIED — /work MUST attempt Playwright on xAI console before handoff`)

## Test Scenarios

1. Measure script parses streaming-json TTFT correctly on fixture NDJSON.  
2. TF with `enable_grok_dogfood=false` plans zero dogfood server create.  
3. Config documents second model block for local OpenAI-compatible endpoint.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Server cap | Phase 0 gate; #6453 reclaim/limit work |
| API cost spike | max-turns, soft ceiling, scoped prompts |
| Throwaway fear | FR11 substrate design; product epic deferred with trajectory doc |
| Agent damages monorepo | no push creds; workspace isolation |
| Stock unavailability | alternate EU type with ≥8 GB |

## Alternative Approaches Considered

| Approach | Why not |
|----------|---------|
| Co-locate on web host | Blast radius / brand |
| GPU first | Cost; Grok 4.5 not local |
| Product Claude→Grok in same PR | Too large; needs product design |
| Time-boxed destroy after week | Weaker dogfood habit (brainstorm rejected B) |

## Deferred (tracked)

- **#6546** Phase 2 open-weight GPU  
- Product epic (unfiled): Soleur Web agent-runner → Grok Build ACP — file at plan handoff if operator wants number now

## Files to Create

- `apps/web-platform/infra/grok-dogfood.tf`  
- `apps/web-platform/infra/scripts/grok-dogfood-bootstrap.sh` (if not pure cloud-init)  
- `scripts/dogfood/grok-measure.sh` (or under infra/scripts)  
- `knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md`  
- optional unit test for measure parser

## Files to Edit

- `apps/web-platform/infra/variables.tf`  
- `apps/web-platform/infra/outputs.tf`  
- `apps/web-platform/infra/firewall.tf` (if SSH rules centralized)  
- `knowledge-base/engineering/operations/expenses.md` (when host live)  
- possibly apply workflow target allowlist if present

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty fails deepen-plan 4.6.  
- Do not claim Grok 4.5 runs on Hetzner GPUs.  
- Additive host needs free slot even after #6453 closed — verify live.  
- Do not put product Concierge migration into this PR.  
- Prefer `enable_*` flag so merge does not force provision against cap.
