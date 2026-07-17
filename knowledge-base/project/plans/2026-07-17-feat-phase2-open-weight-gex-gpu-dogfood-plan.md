---
title: "feat: Phase 2 open-weight Grok Build dogfood on Hetzner Robot GEX44"
date: 2026-07-17
type: feat
issue: 6546
product_epic_issue: 6547
pr: 6597
branch: feat-grok-phase2-open-weight-gpu
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: plan-reviewed
brainstorm: knowledge-base/project/brainstorms/2026-07-17-grok-phase2-open-weight-gpu-brainstorm.md
spec: knowledge-base/project/specs/feat-grok-phase2-open-weight-gpu/spec.md
approach: A
classification: ops-remediation
plan_review: 2026-07-17
---

# Plan — Phase 2 open-weight on Hetzner Robot GPU (#6546)

## Overview

Deliver the **HOW** for Phase 2 of Grok Build dogfood: run an **open-weight** model (not Grok 4.5 — closed weights) on a **separate Hetzner Robot GEX44-class** dedicated GPU host, serve **Ollama** on **loopback** OpenAI-compatible `/v1`, point Grok Build `[model.local-open]` at `http://127.0.0.1:11434/v1`, re-run the **same three** measure classes via `scripts/dogfood/grok-measure.sh --model local-open`, publish a **comparison table vs Phase 1 xAI API** on #6546, then **destroy or re-approve**.

**Co-location (load-bearing):** Grok CLI + measure script + Ollama **all run on the GEX44**. Loopback `base_url` is valid only because of co-location. Phase 1 CX33 stays the **API baseline host** — never the client for remote Ollama on GEX (that would recreate Approach B).

**Approach A is locked** (brainstorm 2026-07-17): Grok + Ollama co-located on GEX44; loopback only. **Approach B rejected** (public inference port; also forbidden as CX33→GEX public `base_url`). **Approach C** (third-party GPU) is stock-delay filler only — not default.

**Control plane (decided Phase 0, not deferred):** Robot console order + bootstrap script + runbook + expense ledger — **not** Cloud `hcloud` / not per-PR TF birth. Do **not** widen `grok_dogfood_server_type` to fake GEX. ADR-119 records the exception; C4 for ephemeral 1-week host is **deferred** (revisit on second durable Robot host).

**Hard gate (this plan + /work + post-merge):** **Do not order a GPU host without operator spend ack + live stock check + license memo.** Implementation in this PR ships artifacts only (runbook, thin bootstrap, expense `approved-not-billing`, comparison table skeleton in runbook, short ADR, destroy/kill). Order + measure soak are **post-merge operator follow-through** gated by those three.

Success is a **filled comparison table on #6546**, not a permanent GPU line item and not product Concierge (#6547 stays parked).

### Plan-review adjustments (2026-07-17)

Mechanical: measure-time loopback + loopback-only `base_url`; `billable_from` T0; smoke AC + fail disposition; workspace clone; runbook expenses path fix; spec `closes` → post-soak; FR1 Robot-not-Cloud gate line; tasks.md create. Taste consensus: demote C4 pre-merge; fold report template into runbook; defer cost-model until expense `active`.

## Premise Validation

| Premise | Check | Result |
|---------|-------|--------|
| #6546 open | `gh issue view 6546` | **OPEN** — `feat: Phase 2 — Grok Build headless with open-weight model on Hetzner GPU` |
| #6597 draft PR | `gh pr view 6597` | **OPEN draft** WIP on `feat-grok-phase2-open-weight-gpu` |
| #6547 product epic | `gh issue view 6547` | Still the parked ACP epic — **not** auto-unparked by this plan |
| Phase 1 host + measure | expenses + brainstorm | CX33 `soleur-grok-dogfood` **active** (89.167.98.209); Phase 1 baseline table exists (2026-07-16) |
| GEX is Cloud type | brainstorm live probe 2026-07-17 | **False** — 25 Cloud types, no `gex*`; GEX is **Robot dedicated** |
| `ROBOT_*` in Doppler | brainstorm | **Absent** — order is console/Robot webservice later |
| Paths on disk | worktree | Runbook, measure script, `grok-dogfood.tf`, expenses.md all present |
| ADR mechanism conflict | grep ADR corpus | No ADR *rejects* Robot dogfood; ADR-019-class TF-default still applies — this plan **documents an explicit exception** (ADR-119) |
| Spec vs Phase 2 runbook depth | read runbook | Phase 2 is a **config stub** (~15 lines) — plan fills operational HOW |

**Premise holds.** Not stale; not already closed by a merged PR.

## Research Reconciliation — Spec vs Codebase

| Spec / brainstorm claim | Reality | Plan response |
|-------------------------|---------|---------------|
| FR9 runbook Phase 2 complete | Stub: config.toml flip + one GEX line; destroy is **TF-only** | Expand Phase 2: order checklist, bootstrap, license, loopback verify, measure, kill, **Robot cancel** destroy; keep Phase 1 TF destroy separate |
| FR8 GEX expense rows | Only CX33 + xAI for dogfood | Add GEX (+ setup one-time, IPv4 if separate) as `approved-not-billing` **before** order |
| Bootstrap for NVIDIA/Ollama | No GPU bootstrap; Phase 1 never shipped `grok-dogfood-bootstrap.sh` | Create `scripts/dogfood/grok-gpu-bootstrap.sh` (T0/T1 idempotent install) + structure tests |
| TR1 no fake Cloud GEX | `variables.tf` regex `^(cax\|cpx\|cx\|ccx)` | **Do not edit** type validation to accept GEX |
| Measure suite reusable | `grok-measure.sh` substrate-agnostic (`--model`) | Reuse as-is; same three classes; measure-time loopback preflight |
| Comparison report in-repo | Baseline lives in brainstorm + host JSONL | Table skeleton **in runbook** Phase 2; filled table posted on #6546 |
| hermes-agent lesson | Non-TF host never ledgered → shadow spend | Ledger **before** birth; retire on cancel |
| Runbook expenses path | L59 cites `knowledge-base/engineering/operations/expenses.md` (**missing**) | Fix to `knowledge-base/operations/expenses.md` while expanding Phase 2 |
| Spec `closes: 6546` | Would close on merge before soak | Spec: post-soak close only; PR uses `Ref #6546` |

## User-Brand Impact

*(Carried from brainstorm 2026-07-17.)*

- **If this lands broken, the user experiences:** Operator dogfood only — a mislabeled “self-hosted Grok 4.5” narrative, exposed OpenAI-compatible port, or YOLO/agent compromise on a high-privilege host. No customer product surface in scope.
- **If this leaks, the user's [data / workflow / money] is exposed via:** Operator monorepo + any secrets mistakenly on host; prompts to open-weight runtime; runaway Robot monthly + setup fee; public inference if loopback bind fails.
- **Brand-survival threshold:** `single-user incident`

**CPO sign-off:** Required at plan time. Brainstorm CPO = **PROCEED-WITH-GUARDS** (R&D learning only; time-box + naming ban; kill if table does not change a decision). Carried forward — `requires_cpo_signoff: true`. Review-time: `user-impact-reviewer`.

**Sharp edge:** Empty / TBD User-Brand Impact fails deepen-plan Phase 4.6.

## Sizing & cost (planning defaults — verify at order)

| Item | Planning value | Source |
|------|----------------|--------|
| SKU | GEX44 (Robot), FSN1 | Hetzner GPU matrix / product page |
| GPU | NVIDIA RTX 4000 SFF Ada, **20 GB** VRAM | Product page |
| Host monthly | **~€184/mo** excl. VAT (IPv4 typically included on GEX44) | Hetzner news / product (~2024 list; **re-verify configurator at order**) |
| Setup fee | **~€79–€114 once** (sources disagree — use live configurator) | Product/configurator |
| Hourly option | Site shows per-hour pricing — **confirm pro-ration for 1-week kill** at order | Open Q |
| Model class | ≤20 GB VRAM (7B–32B quant); **70B out** | Brainstorm |
| Preferred license | Apache-2.0 / MIT | CLO |
| Default soak | **1 week then destroy** unless re-approve | CFO |
| Hard stop | No comparison table within **14 days** of first billable hour | FR10 |
| Pure-$ vs API | Not a savings play at 1–5 runs/day (~4k runs/mo break-even class) | CFO honesty |

**Model shortlist (license memo before pull — pick one OK at order time):**

| Candidate (planning) | License class | VRAM fit (Q4–Q5 class) | Notes |
|----------------------|---------------|------------------------|-------|
| `qwen2.5:32b` / `qwen2.5-coder:32b` | Apache-2.0 (verify card) | Target fit on 20 GB | Prefer coding + tool use |
| `mistral-small` / similar Apache | Apache-2.0 (verify card) | Fit | Alt if Qwen pull fails |
| Llama-class 70B | Llama community | **Out on GEX44** | Reject for this SKU |
| Any NC / field-of-use | Reject | — | Do not pull |

Exact `ollama` tag + SPDX recorded in license memo on #6546 **before** `ollama pull`.

## Proposed Solution

### Deliverables (this PR / pre-order)

1. **Runbook** Phase 2 operational path (order → bootstrap → config → measure → report → kill/cancel) including comparison-table skeleton + brand ban + forbidden configs.
2. **Thin bootstrap** `scripts/dogfood/grok-gpu-bootstrap.sh` (+ tests): NVIDIA detect/install if needed, Ollama, **loopback bind assert**, license-gated pull, Grok CLI, `config.toml` `[model.local-open]`, shallow Soleur clone for measure cwd, health checks.
3. **Expense rows** GEX (+ setup one-time note, IPv4 if billed separate) = `approved-not-billing` with #6546 + kill criteria; flip guidance to `active` / `retired`.
4. **Provisional short ADR-119** — Robot dogfood outside Cloud TF (exception + destroy/ledger; isolation non-edges in prose). C4 deferred.
5. **Kill/destroy** criteria and Robot cancel path (not `enable_grok_dogfood=false`).

### Explicit non-deliverables

- Ordering the GPU in /work without spend ack + stock + license.
- Extending `hcloud_server.grok_dogfood` or `grok_dogfood_server_type` for GEX.
- Approach B public port; product #6547; self-hosted Grok 4.5 claims.
- Full Robot Terraform provider (T3) — deferred until second durable Robot host.

## Technical Considerations

- **Architecture:** Separate host from Phase 1 CX33 (keep API baseline). No `10.0.1.0/24` private-net. SSH admin_ips / Robot firewall equivalent — L3 before L7 on connect failures.
- **Security:** Ollama **must** bind `127.0.0.1` only (`OLLAMA_HOST=127.0.0.1:11434` or equivalent). Verify with `ss`/`curl` from host that `0.0.0.0:11434` is **not** listening. YOLO off default; no passwordless sudo; no prd secrets.
- **Compatibility:** Ollama documents OpenAI Chat Completions at `http://localhost:11434/v1` (api_key required-but-ignored). **Smoke (AC11):** Grok→Ollama `/v1` must pass before multi-day soak. On fail: disposition within **48h** — fix adapter, kill host, or re-approve burn with written reason on #6546 (do not leave host billing without disposition).
- **Loopback every measure (not only bootstrap):** Refuse campaign if Ollama listens on non-loopback **or** `base_url` host is not `127.0.0.1`/`localhost` (blocks Approach B config drift).
- **CLI honesty (#2550):** Every `ollama` / `nvidia-smi` / Robot cancel command in the runbook must be verified against `--help` or vendor docs at write time (`<!-- verified: date source: … -->`).
- **NFR:** Availability not product SLA; R&D cost class in cost-model; data retention ≤ trial + 14d on host logs; assume wipe on Robot cancel.

### Attack surface (operator dogfood)

| Surface | Guard |
|---------|--------|
| Public OpenAI-compatible port | Loopback only + post-bootstrap listen check |
| SSH | Admin IP / Robot firewall; key-only; L3-first diagnosis |
| Agent YOLO | Default off in measure script |
| Brand mislabel | Runbook + report ban strings |
| Customer/PII on host | Forbidden — kill criterion |
| Silent birth (hermes) | Expense before order |

## Research Insights

### Local (repo-research + learnings)

- Phase 1 substrate: `apps/web-platform/infra/grok-dogfood.tf`, `cloud-init-grok-dogfood.yml`, `scripts/dogfood/grok-measure.sh`, runbook `grok-build-hetzner-dogfood.md`.
- Expense status machine: `approved-not-billing` → `active` on live → `retired` on destroy; hermes-agent never-ledgered lesson.
- Bootstrap precedent: prefer thin `scripts/dogfood/` script over heavy product-host OCI bootstraps; idempotent `set -euo pipefail` + fail-loud service checks (`inngest-redis-bootstrap.sh` style).
- Isolation learning: `workflow-patterns/2026-07-16-grok-dogfood-host-no-private-net-yolo-off.md`.
- IaC default vs exception: `2026-05-18-plan-baked-in-operator-ssh-violated-iac-rule.md` — Robot path requires `## Infrastructure (IaC)` + explicit ack, not silent SSH folklore.
- Ship gate: `wg-record-recurring-vendor-expense-before-ready` — GEX rows must exist before PR ready if claiming spend readiness.

### External (vendor)

- GEX44: RTX 4000 SFF Ada 20 GB; ~€184/mo; setup fee live-verify; FSN1; Robot not Cloud.  
  Sources: [Hetzner GPU matrix](https://www.hetzner.com/dedicated-rootserver/matrix-gpu/), [GEX44 product](https://www.hetzner.com/dedicated-rootserver/gex44/).
- Ollama OpenAI compat: `base_url=http://localhost:11434/v1`, dummy API key.  
  Source: [Ollama OpenAI compatibility docs](https://docs.ollama.com/api/openai-compatibility).

### Community discovery

- No uncovered language stacks for this feature.
- Functional-discovery: **skip all** community Ollama/NVIDIA/Hetzner plugins — none cover Robot GEX + ledger + measure report.

### Research decision

External vendor facts (price, OpenAI compat) researched; no further framework-docs pass needed for a T0/T1 runbook+script campaign. Strong Phase 1 local patterns.

## Hypotheses (SSH / network — L3→L7)

When first connecting to a new Robot GEX host fails, verify in order (plan network-outage checklist + `hr-ssh-diagnosis-verify-firewall`):

| Layer | Hypothesis | Verification (at connect time) |
|-------|------------|--------------------------------|
| L3 firewall | Robot/Hetzner firewall or rescue mode blocks operator egress | Record operator egress IP; check Robot firewall rules for :22; **not verified until host exists** |
| L3 DNS/routing | Wrong IP pasted / stale Rescue IP | Compare Robot console IP to `ssh` target; traceroute last hop |
| L7 TLS | N/A for raw SSH dogfood | Skip |
| L7 service | sshd down / fail2ban | Only after L3 passes — journal / Robot VNC/KVM if available |

**Do not** open with “fix fail2ban / reinstall sshd” as first remediation.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

**Why not Cloud TF for GEX:** Live Hetzner Cloud has no GEX server type; `grok_dogfood_server_type` validates Cloud families only; extending `hcloud_server.grok_dogfood` would **lie**. Robot order requires console (no `ROBOT_*` today). This is a **documented exception** for time-boxed operator R&D dogfood, not a general “SSH is fine” waiver.

### Terraform changes

| Action | Detail |
|--------|--------|
| **No** new `hcloud_server` for GEX | Explicit non-goal |
| **No** widen `grok_dogfood_server_type` regex | TR1 |
| **Optional comment only** in `grok-dogfood.tf` | Point to ADR-119 + runbook Phase 2 — optional one-line, not required if ADR + runbook suffice |
| Phase 1 CX33 TF | **Unchanged** — keep API baseline host |

### Apply path

- **Host birth:** Robot console order (after gates) — not `terraform apply`.
- **Software:** Idempotent `scripts/dogfood/grok-gpu-bootstrap.sh` run as root over SSH **after** OS image is up (Robot rescue/install as needed per Hetzner docs).
- **Cloud-init:** Robot may offer images; bootstrap script is the source of truth for NVIDIA/Ollama/Grok so reinstalls are repeatable without tribal knowledge.

### Distinctness / drift safeguards

- Cloud fleet cap (5 servers) **does not** block Robot GEX — separate product class (brainstorm capacity table).
- Ledger status must match live Robot inventory (no hermes-class invisible host).
- Phase 1 destroy remains TF `enable_grok_dogfood=false`; Phase 2 destroy is **Robot cancel** — never mix the two procedures.

### Vendor-tier reality check

- GEX stock can be OOS — live stock check at order; optional Approach C only with operator + CLO ToS ack (not default).
- Setup fee is sunk — do not order until measure path ready (this PR).

## Architecture Decision (ADR/C4)

### ADR

- **Provisional ADR-119** (re-verify free ordinal at ship vs `origin/main`): *Operator R&D GPU dogfood on Hetzner Robot may live outside Cloud Terraform when no Cloud SKU exists; lifecycle = runbook + expense ledger + bootstrap script + explicit destroy; never fake Cloud types; loopback-only inference; no product Concierge edge; no private-net join.*
- Status: **accepted** for time-boxed dogfood; revisit if second durable Robot host → T2 automation **and** C4.

### C4 views

Actors/systems checked against all three `.c4` files (completeness mandate):

| Element | Already modeled? | Plan action |
|---------|------------------|-------------|
| Operator | Yes | No change |
| Hetzner Cloud hosts | Yes / partial | Phase 1 CX33 remains Cloud TF |
| Robot GEX + Ollama | **Not modeled** | **Deferred this PR** (ephemeral 1-week host; invariants in ADR + runbook non-edges) |
| Product agent-runner | Yes | **Forbidden non-edge** to GEX — documented in ADR Decision |
| Private-net `10.0.1.0/24` | Yes | **Forbidden non-edge** from GEX — documented in ADR |

**Why defer C4:** Spec TR7 is soft (“plan may create ADR”); host is intentionally cancelled ≤1 week; same deferral bar as T2 Robot TF. On second durable Robot host, add C4 external + isolation non-edges.

### Sequencing

Short ADR ships with runbook/bootstrap/ledger PR; host order remains post-merge.

## Implementation Phases

### Phase 0 — Pre-order gates + exception decision (docs only; no order)

- [ ] Encode **order checklist** on runbook / #6546:
  0. **GEX is Robot dedicated** (not Cloud type; Cloud fleet inventory does not block Robot birth — record N/A for Cloud free-slot).
  1. Operator **spend ack** on #6546.
  2. Live GEX44 **stock/price/setup** from Robot configurator.
  3. **License memo** OK for chosen model id.
- [ ] Explicit **STOP**: artifacts may merge; **order forbidden** until 0–3 true.
- [ ] Record Robot-out-of-Cloud-TF exception in runbook (ADR body lands Phase 4 — decision is not deferred).
- [ ] Billing pro-ration open Q — answer at order or plan full-month worst case.

### Phase 1 — Expense ledger (pre-order)

- [ ] Add rows to `knowledge-base/operations/expenses.md`:
  - `Hetzner GEX44 (grok-dogfood-gpu)` — ~€184 → USD at ledger FX, status **`approved-not-billing`**, notes: #6546, Approach A, 1-week soak, kill criteria, R&D.
  - Setup fee one-time note; IPv4 only if billed separate (do not double-count).
- [ ] Status flip rules in runbook: live → `active` same day + `billable_from:` ISO on #6546; cancel → `retired` same day.
- [ ] **Do not** edit `cost-model.md` until expense flips `active` (post-order).

### Phase 2 — Runbook Phase 2 expansion

Edit `knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md`:

- [ ] Fix expenses path: `knowledge-base/operations/expenses.md` (remove bogus `engineering/operations/expenses.md`).
- [ ] Phase 2 architecture: GEX separate from CX33; **co-located** Grok+Ollama; loopback only.
- [ ] **Forbidden configs:** (a) Ollama on `0.0.0.0`; (b) any host’s `base_url` pointing at GEX **public** IP (Approach B); (c) product Concierge/`agent-runner` → GEX.
- [ ] Order procedure: SKU, FSN1, Ubuntu 24.04 preferred, SSH keys, :22 admin; record **IP + order id + `billable_from:`** on #6546.
- [ ] Bootstrap invoke docs; license memo 5 steps; config.toml live block.
- [ ] Workspace: shallow clone Soleur for `--cwd` measure path.
- [ ] Measure: three classes, `--model local-open`, YOLO off; **preflight loopback listen + loopback base_url**.
- [ ] Comparison table skeleton (Phase 1 baseline pre-filled + empty Phase 2 rows + narrative rules + brand ban footer) — paste to #6546 when filled.
- [ ] Kill criteria + smoke-fail disposition (48h).
- [ ] Destroy: Robot cancel + ledger retired; contrast Phase 1 TF destroy.
- [ ] CLI tokens verified with `<!-- verified: date source: … -->`.

### Phase 3 — Thin bootstrap script + tests

Create `scripts/dogfood/grok-gpu-bootstrap.sh` + `grok-gpu-bootstrap.test.sh`:

- [ ] `set -euo pipefail`; root preflight; NVIDIA detect first, install only if missing.
- [ ] Ollama install; `OLLAMA_HOST=127.0.0.1:11434`; **assert listen is loopback** (fail if `0.0.0.0:11434`).
- [ ] Pull only with `--model` **and** `--license-ok` (human memo already on #6546).
- [ ] Grok CLI + seed config local-open; dogfood user no passwordless sudo; log dir.
- [ ] Shallow clone `/home/dogfood/soleur` (or flag to skip if present).
- [ ] Health curl loopback; end marker `bootstrap complete: …`.
- [ ] Tests: `bash -n`; grep loopback + `--license-ok`; existing `grok-measure.test.sh` still green.

### Phase 4 — ADR-119 (no C4 this PR)

- [ ] Author `knowledge-base/engineering/architecture/decisions/ADR-119-robot-gpu-dogfood-outside-cloud-tf.md` (~1 screen): Decision, isolation non-edges (no product, no private-net, loopback-only), ledger before birth, destroy = Robot cancel, revisit at second durable Robot host for T2 + C4.
- [ ] **C4 deferred** (ephemeral 1-week host; same bar as T2 Robot automation). Isolation invariants live in ADR + runbook.
- [ ] Ordinal provisional — ship re-verifies free number vs `origin/main`.

### Phase 5 — Spec close-semantics + tasks

- [ ] Edit `knowledge-base/project/specs/feat-grok-phase2-open-weight-gpu/spec.md`: remove/`Ref` `closes: 6546`; note close only after comparison table + ledger + destroy/re-approve.
- [ ] `tasks.md` created by this plan skill (not “edit missing file”).

### Phase 6 — Post-merge operator follow-through (NOT auto-merge close)

**Classification:** ops-remediation. PR body **`Ref #6546`**, not `Closes #6546`.

Only after gates 0–3:

1. Order GEX44; expense → `active`; stamp **IP + order id + `billable_from:`** on #6546.
2. Bootstrap; license pull; **smoke** Grok→Ollama `/v1` (AC11) with 48h fail disposition.
3. Measure preflight loopback; three classes; post filled table on #6546.
4. Default cancel ≤1 week unless re-approve on #6546; expense → `retired`; update cost-model if was active.
5. Close #6546 only when table + ledger + destroy/re-approve recorded.

**Automation:** Robot order `automation-status: UNVERIFIED` — console/MFA expected; bootstrap after SSH is scripted.

## Files to Create

| Path | Purpose |
|------|---------|
| `scripts/dogfood/grok-gpu-bootstrap.sh` | Thin idempotent GPU host software install |
| `scripts/dogfood/grok-gpu-bootstrap.test.sh` | Structure/guard tests |
| `knowledge-base/engineering/architecture/decisions/ADR-119-robot-gpu-dogfood-outside-cloud-tf.md` | Short architecture exception (provisional ordinal) |
| `knowledge-base/project/specs/feat-grok-phase2-open-weight-gpu/tasks.md` | Task breakdown |

## Files to Edit

| Path | Purpose |
|------|---------|
| `knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md` | Full Phase 2 HOW, expenses path fix, table skeleton, kill/destroy |
| `knowledge-base/operations/expenses.md` | GEX rows `approved-not-billing` |
| `knowledge-base/project/specs/feat-grok-phase2-open-weight-gpu/spec.md` | Close semantics: no merge-close of #6546 |

## Files explicitly NOT to edit (this PR)

- `variables.tf` `grok_dogfood_server_type` validation (do not add GEX).
- `knowledge-base/finance/cost-model.md` until expense is `active`.
- C4 `model.c4` / `views.c4` / `spec.c4` (deferred).
- Product `agent-runner.ts` / #6547 paths.
- `apps/web-platform/infra/grok-dogfood.tf` resources (no comment required).

## Open Code-Review Overlap

Queried open `code-review` issues against planned paths (runbook, expenses, dogfood scripts, ADR). **None** matched.

**Result:** None.

## Functional Requirements (plan-level)

| ID | Requirement |
|----|-------------|
| P-FR1 | Order checklist: Robot-not-Cloud + spend + stock + license. |
| P-FR2 | Bootstrap enforces loopback Ollama + license gate for pull; measure re-asserts loopback. |
| P-FR3 | Expense GEX rows `approved-not-billing` before order is considered ready. |
| P-FR4 | Runbook comparison-table skeleton: Phase 1 baseline + empty Phase 2 + brand ban. |
| P-FR5 | Destroy = Robot cancel + ledger retired (≠ Phase 1 TF). |
| P-FR6 | ADR-119 documents Robot-out-of-Cloud-TF exception + isolation non-edges. |
| P-FR7 | Artifacts never claim self-hosted Grok 4.5. |
| P-FR8 | No Cloud TF fake GEX type. |
| P-FR9 | Forbidden Approach B configs documented + measure-time base_url/loopback gate. |

## Acceptance Criteria

### Pre-merge (PR #6597)

- [ ] **AC1:** Runbook Phase 2 documents order → bootstrap → measure → report → kill → Robot cancel; expenses path fixed; CLI tokens verified with source dates.
- [ ] **AC2:** `scripts/dogfood/grok-gpu-bootstrap.sh` exists; `bash -n` clean; tests assert loopback + `--license-ok`.
- [ ] **AC3:** `knowledge-base/operations/expenses.md` has GEX (+ setup notes) at **`approved-not-billing`** with #6546 and kill criteria.
- [ ] **AC4:** Runbook contains comparison-table skeleton with Phase 1 baseline + three empty Phase 2 class rows + brand ban.
- [ ] **AC5:** ADR-119 (or renumbered) exists; Decision forbids fake Cloud GEX types + product/private-net non-edges.
- [ ] **AC6:** `git grep -nE 'gex44|GEX44' apps/web-platform/infra/variables.tf` does **not** accept GEX in type validation (regex Cloud-only).
- [ ] **AC7:** Spec no longer claims merge-closes #6546; PR body uses **`Ref #6546`**.
- [ ] **AC8:** Runbook forbids public Ollama bind and remote `base_url` to GEX public IP.
- [ ] **AC9:** Existing `scripts/dogfood/grok-measure.test.sh` still passes.
- [ ] **AC10:** Bootstrap documents/clones measure workspace path for `--cwd`.

### Post-merge (operator — after gates)

- [ ] **AC11:** Host ordered only after checklist 0–3 on #6546; expense → `active`; **`billable_from:`** ISO + order id + IP stamped on #6546.
- [ ] **AC11b (smoke):** Grok→Ollama `/v1` smoke passes before multi-day soak; on fail, 48h disposition (fix / kill / re-approve written on #6546).
- [ ] **AC12:** Measure preflight loopback; three-class measure; comparison table posted on #6546.
- [ ] **AC13:** Default ≤1-week destroy or documented re-approval; expense `retired` on cancel; cost-model if was active.
- [ ] **AC14:** Phase 1 CX33 still available unless operator consolidates.
- [ ] **AC15:** #6547 still parked.

## Observability

```yaml
liveness_signal:
  what: "Phase 2 measure success = filled comparison table on #6546 + optional host JSONL summary committed or pasted; not a product heartbeat"
  cadence: "per measure campaign (1–5 runs/day during soak); hard stop at 14 days without table"
  alert_target: "operator via GitHub issue #6546 comments; expense ledger active burn"
  configured_in: "knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md Phase 2 (comparison table skeleton + kill); knowledge-base/operations/expenses.md GEX rows"

error_reporting:
  destination: "Host /var/log/grok-dogfood/runs.jsonl (metrics only); GitHub #6546 for campaign failures; no Sentry product project required for operator dogfood"
  fail_loud: "Measure non-zero exit in report table; bootstrap non-zero exit; expense active with no table after 14 days = kill criterion"

failure_modes:
  - mode: "Ollama bound to 0.0.0.0 (public OpenAI-compatible surface)"
    detection: "Bootstrap post-check fails if listen address not loopback; runbook verify step"
    alert_route: "operator kill criterion + immediate service stop"
  - mode: "Silent birth without ledger (hermes class)"
    detection: "Pre-order AC requires approved-not-billing rows; ship expense gate"
    alert_route: "block PR ready / #6546 comment"
  - mode: "No comparison table within 14 days of first billable hour"
    detection: "Issue timeline + expense active since date"
    alert_route: "kill: Robot cancel + retire ledger"
  - mode: "Brand mislabel self-hosted Grok 4.5"
    detection: "grep ban in report/runbook; human review of #6546 wording"
    alert_route: "edit + CLO if public"

logs:
  where: "Host /var/log/grok-dogfood/ (JSONL metrics); GitHub issue #6546 report; assume wiped on Robot cancel"
  retention: "trial duration + 14 days max; no customer data"

discoverability_test:
  command: "grep -c 'Phase 1 baseline' knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md && grep -E 'approved-not-billing|active|retired' knowledge-base/operations/expenses.md | grep -i GEX | head -3 && test -f knowledge-base/engineering/architecture/decisions/ADR-119-robot-gpu-dogfood-outside-cloud-tf.md"
  expected_output: "runbook baseline section present (≥1); GEX expense row with status token; ADR-119 file exists"
```

No `ssh` in discoverability_test. **This test is artifact liveness only** — it can pass while a live host is misbound; bind safety is bootstrap + every measure preflight (AC12), not this command.

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Operations, Finance  
*(Carried from brainstorm Domain Assessments 2026-07-17 — no UI Files to Create/Edit → Product/UX Gate tier **NONE** for wireframes.)*

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)  
**Assessment:** PROCEED-WITH-GUARDS. R&D learning only; time-box + naming ban; kill if table changes no decision. Sign-off for single-user threshold carried.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)  
**Assessment:** License memo before pull; brand ban; Robot AVV confirmation at order; gdpr only if customer/PII path appears (kill).

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)  
**Assessment:** Approach A; reject B; no fake Cloud TF; T0/T1; success = comparison table.

### Operations (COO)

**Status:** reviewed (brainstorm carry-forward)  
**Assessment:** PARK order until gates; ledger before birth; destroy = Robot cancel.

### Finance (CFO)

**Status:** reviewed (brainstorm carry-forward)  
**Assessment:** 1-week default soak; honest non-break-even; no silent renewal.

### Product/UX Gate

**Tier:** none (no UI surfaces)  
**Decision:** N/A  
**Pencil available:** N/A (no UI surface)  
**Brainstorm-recommended specialists:** none beyond domain leaders already assessed.

## GDPR / Compliance

Triggered by brand-survival `single-user incident` and operator LLM processing on dogfood host.

- **Lawful basis:** Operator R&D; **no customer personal data** on host (FR11 / kill if broken).
- **Data:** Measure prompts + model outputs + metrics JSONL; retention ≤ trial + 14d; wipe on cancel.
- **Sub-processor:** Hetzner Robot (same org relationship as Cloud; confirm AVV covers dedicated at order). Open-weight runs **local** — no third-country model API for Phase 2 default.
- **Action:** No new PA required if strictly operator prompts with no customer data; if kill criteria break (customer data), stop and invoke gdpr-gate / compliance-posture update.
- **Disclaimer:** Advisory only — not legal advice.

## Alternative Approaches Considered

| Approach | Verdict |
|----------|---------|
| A — GEX44 + Ollama loopback + Grok co-located | **Chosen** |
| B — GPU public port; measure on CX33 | Rejected (trust surface) |
| C — Third-party GPU burst | Optional stock filler only |
| Fake Cloud TF GEX type | Rejected (lies; type validation) |
| Park all spend | Valid if gates fail — operator chose plan continue |

### Deferred (tracking)

| Item | Tracking |
|------|----------|
| Product ACP / Concierge | **#6547** (parked) |
| Approach C first | Only if GEX OOS; no new issue until chosen |
| Robot webservice / TF (T2+) | Defer until second durable Robot host |

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Order without spend ack | Three-gate STOP; expense approved-not-billing first |
| Public Ollama | Bootstrap loopback assert |
| Setup fee sunk, no table | Ready measure path before order; 14-day kill |
| License surprise | Memo before pull; Apache/MIT preferred |
| Grok≠Ollama tool/stream quirks | Pre-measure smoke; document adapter gap |
| Brand mislabel | Ban strings in runbook/report |
| hermes-class shadow host | Ledger before birth; retire on cancel |
| Pro-ration worse than 1-week | Verify at order; plan envelope full month |

## Test Scenarios

- **Given** bootstrap script, **when** grepped for bind, **then** loopback enforced and license gate present.
- **Given** expenses.md, **when** GEX row added, **then** status is `approved-not-billing` not `active`.
- **Given** runbook, **when** destroy section read, **then** Robot cancel ≠ TF enable false for Phase 2.
- **Given** report template, **when** filled later, **then** three classes present and brand ban footer exists.
- **Given** variables.tf, **when** type regex checked, **then** GEX not accepted.

## Success Metrics

1. Comparison table for three classes on #6546 (or linked artifact).
2. Ledger matches reality (no phantom active; no silent birth).
3. Kill/destroy executed or re-approval recorded.
4. Zero brand claims of self-hosted Grok 4.5.
5. Phase 1 CX33 retained unless explicit consolidate.

## Dependencies

- Phase 1 host + measure suite (done).
- Operator Robot account access.
- Operator spend ack (human).
- Open-weight license choice.
- Live stock at order time.

## MVP Pseudo-structure

### scripts/dogfood/grok-gpu-bootstrap.sh (sketch)

```bash
#!/usr/bin/env bash
# #6546 — thin idempotent GEX GPU dogfood bootstrap (Approach A, co-located).
set -euo pipefail
LICENSE_OK=0
MODEL=""
# parse --license-ok --model …
require_root
ensure_nvidia_or_detect
ensure_ollama_loopback   # OLLAMA_HOST=127.0.0.1:11434; fail if 0.0.0.0
ensure_grok_cli
seed_config_local_open   # base_url must be 127.0.0.1
ensure_soleur_workspace  # shallow clone for measure --cwd
if [[ -n "$MODEL" ]]; then
  [[ "$LICENSE_OK" -eq 1 ]] || die "refuse pull without --license-ok"
  ollama pull "$MODEL"
fi
healthcheck_loopback
echo "bootstrap complete: …"
```

## References

- Issue: #6546 · Draft PR: #6597 · Product epic: #6547 · Phase 1: #6545
- Brainstorm: `knowledge-base/project/brainstorms/2026-07-17-grok-phase2-open-weight-gpu-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-grok-phase2-open-weight-gpu/spec.md`
- Runbook: `knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md`
- Measure: `scripts/dogfood/grok-measure.sh`
- Learning: `knowledge-base/project/learnings/workflow-patterns/2026-07-16-grok-dogfood-host-no-private-net-yolo-off.md`
- Hetzner GEX: https://www.hetzner.com/dedicated-rootserver/matrix-gpu/
- Ollama OpenAI compat: https://docs.ollama.com/api/openai-compatibility

## Sharp Edges (plan-specific)

1. **Do not order GPU in /work** without spend ack + stock + license — artifacts only.
2. **Destroy path split brain** — Phase 1 TF vs Phase 2 Robot cancel; document both.
3. **hermes-agent** — non-TF host without ledger is a known failure mode.
4. **Fabricated Ollama CLI** — verify every command (#2550 class).
5. **User-Brand Impact** must stay complete for deepen-plan 4.6.
6. **ADR ordinal collision** — re-verify free ordinal at ship; sweep plan/tasks if renumbered.
7. **SSH diagnosis** — L3 firewall before sshd/fail2ban on new Robot host.
