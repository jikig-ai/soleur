# Structurizr Diagrams Brainstorm

**Date:** 2026-05-13
**Status:** **PAUSED — awaiting deployment-option decision (Phase 2)**
**Participants:** Founder, CTO, CPO, CLO, COO
**Worktree:** `.worktrees/feat-structurizr-diagrams`
**Branch:** `feat-structurizr-diagrams`
**Draft PR:** #3729
**Resume at:** Phase 2 — final deployment-option pick (see "Open Decision" below)
**Supersedes (partial):** `knowledge-base/project/brainstorms/2026-03-27-architecture-as-code-brainstorm.md` Open Question 5 (Structurizr deferral)

## User-Brand Impact

**Threshold:** `single-user incident` (carry forward to plan).

**Artifact at risk:** The 3 C4 diagram source files under `knowledge-base/engineering/architecture/diagrams/` (system-context.md, container.md, component-plugin.md). These describe Soleur's BYOK encryption boundary, Supabase project isolation, Cloudflare Tunnel topology, and Doppler injection paths.

**Failure vectors operator endorsed (Phase 0.1):**

- **Architecture / credential exposure** — a Structurizr instance hosted publicly (especially option b) is one Access-rule misconfiguration away from leaking the attack-surface map. CLO note: container.md already discloses this topology in Mermaid form, so the *exposure baseline* doesn't change for option (a); option (b) creates a new live-service exposure surface.
- **Diagram-data loss in migration** — hand-translating 3 Mermaid C4 diagrams to Structurizr DSL risks dropping a node/edge. Downstream effect: the `soleur:architecture assess` sub-command reads diagrams to identify affected containers; missing nodes = wrong NFR / principle assessments.
- **No direct user impact** — these are internal docs today; the brand-survival lens is on operator/contributor trust, not end-user data.

## What We're Building

**Goal:** Replace inline Mermaid C4 blocks in 3 architecture markdown files with **Structurizr** (the official C4 modeling tool), so the founder gets a single canonical DSL source and a clickable drill-down viewer across all 4 C4 levels.

**Confirmed decisions (Phase 1 dialogue):**

1. **Audience = all three tiers** — founder today; future contributors browsing the repo; eventually Soleur cloud users (architecture-as-code is a product feature per 2026-03-27 brainstorm). This validates the broader product-feature framing.
2. **Timing = now.** Founder explicitly overrode the CPO's "park it / fix Mermaid first" recommendation. Pain is real enough to spend brainstorm + multi-day implementation cycles ahead of Phase 3 P0 closure.
3. **Canonical source = DSL only.** After a side-by-side review confirms equivalence, the inline Mermaid blocks are deleted. The 3 `.md` files become thin wrappers embedding the CI-rendered SVG + link to the local viewer. No dual-write.

**Pending decision (Phase 2 — resume here):**

- **Deployment option** — founder initially picked (b) self-hosted multi-user, then paused after the CTO/CLO/COO pushback (see Open Decision below).

## Why This Approach

### Why now, after the 2026-03-27 deferral

The prior brainstorm deferred Structurizr (Open Q #5) because Mermaid was already in use and Structurizr added a Docker dependency for marginal gain at that time. Six weeks later:

- The 3 Mermaid C4 diagrams are still hand-rendered and unreadable to the founder (overlapping arrows, indistinguishable boxes).
- The `soleur:architecture` skill emits Mermaid blocks — every new diagram inherits the same layout problem.
- The product-feature framing matured: cloud users will want clickable C4 drill-down, which Mermaid C4 fundamentally does not provide.

### Why DSL as canonical

- One source generates all 4 C4 levels (Context → Container → Component → Code) with clickable navigation — the actual C4 concept Mermaid cannot model.
- DSL is portable text. Migration away from Structurizr later (to PlantUML, to a JS renderer in the PWA) reuses the same source.
- Avoids Type-1 dual-write drift (DSL + Mermaid would diverge).

### Product-feature consistency (CTO note)

Option (a) keeps "architecture-as-code as a founder capability" alive — any founder using Soleur gets `.dsl` files + `docker compose up` for local preview, no Soleur-internal infra required. Option (b) silently scopes this back to "Soleur-internal tool" because it requires Cloudflare Tunnel + Supabase Auth.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Audience: all three tiers (founder + contributors + Soleur cloud users) | Founder confirmed; validates the 2026-03-27 product-feature framing. |
| 2 | Timing: ship now, ahead of Phase 3 close | Founder override of CPO recommendation. Logged for plan-time user-impact-reviewer attention. |
| 3 | DSL is canonical; Mermaid blocks deleted after side-by-side review | Avoid dual-write drift. CTO migration-safety note: hand-translate with diff aid; no automated equivalence check exists. |
| 4 | **Deployment option — OPEN** | See "Open Decision" below. |
| 5 | This adoption is an architectural decision; an ADR will be created (supersedes 2026-03-27 Open Q #5 deferral) | CTO: "technology choice + new runtime dependency + canonical-source-of-truth change." |

## Open Decision — Deployment Option (resume here)

The founder's initial pick was **(b) Self-hosted multi-user on Hetzner**, contrary to unanimous CTO + CLO + COO recommendation of **(a) Local Docker + CI static render**. Session paused before a final pick.

### Option (a) — Local Docker + CI static render — RECOMMENDED by all 3 leaders

- Devs run `docker compose up structurizr/lite` locally for interactive editing.
- CI renders the DSL to static SVG/HTML via `structurizr/cli export`, publishes via existing GH Pages / Eleventy pipeline.
- $0/mo incremental. Apache 2.0. No new attack surface. No PWA conflict (cloud users do the same on their machines).

### Option (b) — Self-hosted multi-user on Hetzner — founder's initial pick

- Run `structurizr/onpremises` long-running on the existing CX33 behind Cloudflare Tunnel + custom Supabase Auth bridge.
- Live concurrent editing in a hosted UI.
- **Concerns surfaced:**
  - **License (CLO):** Free for 1 user/workspace only. Multi-user requires paid commercial license. There is no free version of multi-user self-hosted Structurizr.
  - **OOM (COO):** JVM + persistence on the same CX33 (4 vCPU / 8 GB) that runs Next.js + Claude Code. OOM blast = production user-facing breakage for a docs tool.
  - **Architecture-disclosure (CTO):** Long-running instance is one Access-rule misconfig away from publicly exposing BYOK / Supabase / tunnel topology. Matches the operator's Phase 0.1 `credential leak / arch exposure` failure vector.
- The only thing (b) buys over (a) is **live concurrent editing in a hosted UI**. Contributors and cloud users only need to *read* diagrams; static SVG covers that.

### Option (c) — SaaS structurizr.com

- $5/user/mo. Vendor lock-in for canonical model. Confidentiality/trade-secret risk (architecture data on a third-party). Rejected on principle by CTO ("conflicts with version-controlled `knowledge-base/`").

### Hybrid

- Ship (a) now. If multi-user collaborative editing becomes a real need later (contributors arrive, beta users want it), open a follow-up brainstorm to add (b) on top. The DSL is portable, so this is reversible.

## Open Questions

1. **Final deployment option** — (a) / (b) / (c) / hybrid. **Blocks Phase 2 closure and spec.md generation.**
2. **GitHub markdown previews** — DSL has no native GitHub renderer (Mermaid does). CTO mitigation: commit the CI-rendered SVG alongside the DSL so GH UI readers still see the diagram inline. Re-test before deleting Mermaid blocks.
3. **DSL-validation gate** — needs a PreToolUse-or-CI gate running `structurizr-cli validate workspace.dsl` to prevent broken DSL shipping. Capability gap (see below).
4. **Mermaid→DSL equivalence diff** — capability gap. Migration safety needs a side-by-side review aid (node/edge count comparison).
5. **`soleur:architecture` skill rewrite scope** — the existing `diagram` sub-command (SKILL.md lines 169-225) hard-codes Mermaid C4 emission. New sub-commands proposed: `add-container`, `add-relationship`, `render`. Sequencing: migrate the 3 files first, then rewrite the skill? Or skill first?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Strong endorsement of option (a). Concrete migration design proposed — `workspace.dsl` as single source, CI render to SVG via `structurizr/cli`, the `.md` files become thin SVG wrappers. Skill rewrite needed: `architecture diagram` sub-command becomes a DSL patcher instead of a Mermaid emitter; `c4-reference.md` replaced by `structurizr-dsl-reference.md`. Flags option (b) as a user-brand-critical threshold violation. Recommends an ADR to formally supersede the 2026-03-27 Mermaid-only implicit decision.

### Product (CPO)

**Summary:** Recommends **parking** Structurizr. The founder's pain ("overlapping arrows") is a layout problem in 3 hand-written Mermaid files, not a tooling-class problem — fixable in hours with subgraphs and `linkStyle`. Phase 3 is in-progress with P0 issues (#2550, #2662) open; 0 beta users; AaC has no roadmap slot. **Critical constraint flagged:** Docker-rendered Structurizr cannot run inside the PWA, so it fails the future "AaC as product feature" use case for cloud users. Founder explicitly overrode this recommendation; the override is logged for plan-time user-impact-reviewer attention.

### Legal (CLO)

**Summary:** Option (a) is Apache 2.0 clean — no copyleft, no commercial restriction, no sub-processor relationship. Option (b) is licensed only for ≤1 user/workspace free; multi-user requires a paid commercial license (not open-source past free tier). Option (c) is legally usable; no GDPR sub-processor obligation triggered because diagrams contain no Personal Data, but does create a confidentiality/trade-secret exposure under standard commercial-contract risk. C4 container diagram is **operationally sensitive, not legally confidential** — should be treated as internal-confidential (private repo / authn-gated docs); the Mermaid version already discloses the same topology, so option (a) doesn't change the baseline. Recommends (a).

### Operations (COO)

**Summary:** Option (a) = $0/mo incremental, reuses GH Actions + GH Pages (already wired to soleur.ai per `domains.md`). Option (b) = $0 incremental dollars but real memory cost (~512MB-1GB JVM + persistence on the CX33 already shared with Next.js + Claude Code; OOM risk is non-zero, blast radius is production user-facing). Option (c) = ~$5/user/mo new ledger line. Recommends (a) for "minimize new surface area."

## Capability Gaps

| Gap | Domain | Evidence | Why Needed |
|-----|--------|----------|-----------|
| No `structurizr-dsl-reference.md` skill reference | Engineering | `ls plugins/soleur/skills/architecture/references/` shows only `c4-reference.md` + `adr-template.md`; no DSL reference exists. | Replaces `c4-reference.md` so the `soleur:architecture` skill can author DSL correctly. |
| No DSL-validation hook | Engineering | grep `.github/workflows/*.yml` returned zero `structurizr` / `.dsl` hits per CTO assessment. | A PreToolUse-or-CI gate running `structurizr-cli validate workspace.dsl` prevents broken DSL shipping (would render-fail opaquely). |
| No Mermaid→DSL equivalence-diff tool | Engineering | No tooling exists; CTO confirmed via repo grep. | User-brand-critical migration of 3 diagrams (~50 relations) needs a side-by-side review aid (node count, edge count) to prevent silent drift. |
| No `structurizr/lite` or `structurizr/cli` in any dev/CI config | Engineering | grep `.github/workflows/*.yml` + `package.json` + `docker-compose*.yml` — no hits. | Must be added to `deploy-docs.yml` (or a new workflow) and to a `compose.dev.yml` for local. |

## Resume Instructions

1. Pick a deployment option in Phase 2 (a / b / c / hybrid).
2. Update the "Open Decision" section above with the final pick + rationale.
3. Move Decision #4 in the Key Decisions table from "OPEN" to the picked option.
4. Generate `spec.md` at `knowledge-base/project/specs/feat-structurizr-diagrams/spec.md` from this brainstorm (Phase 3.6).
5. Update the linked GitHub issue with the final scope.
6. Use `skill: soleur:plan` to translate the brainstorm into an implementation plan.

**Resume prompt (copy-paste after `/clear`):**

```
/soleur:brainstorm resume the Structurizr diagrams brainstorm at Phase 2 deployment-option decision. Brainstorm: knowledge-base/project/brainstorms/2026-05-13-structurizr-diagrams-brainstorm.md. Worktree: .worktrees/feat-structurizr-diagrams. Branch: feat-structurizr-diagrams. Draft PR: #3729. CTO+CLO+COO recommend option (a) local Docker + CI static render; founder initially picked (b) self-hosted, paused after pushback on license/OOM/disclosure. Decide (a) / (b) / (c) / hybrid, then proceed to spec.md and plan.
```
