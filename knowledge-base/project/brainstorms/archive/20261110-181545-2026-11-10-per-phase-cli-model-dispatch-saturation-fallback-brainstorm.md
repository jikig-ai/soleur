---
date: 2026-11-10
topic: per-phase-cli-model-dispatch-saturation-fallback
issue: 12529
lane: cross-domain
user_brand_critical: true
---

# Brainstorm: Per-Phase CLI/Model Dispatch & Saturation Fallback (#12529)

**Date:** 2026-11-10  
**Issue:** [#12529](https://github.com/jikig-ai/soleur/issues/12529) (`OPEN`)  
**Context:** Peer-framework comparison vs `hmuhlestein/HephaestusNG` (2026-11-09)  
**Branch:** `feat-12529-per-phase-cli-dispatch`  
**PR:** [#12568](https://github.com/jikig-ai/soleur/pull/12568)  

---

## 1. User-Brand Impact (Mandated per #5175 / hr-weigh-every-decision-against-target-user-impact)

- **Artifact:** Per-phase model dispatch and saturation fallback wrapper (`plugins/soleur/lib/harness-model-map.ts` and `*.workflow.js` execution environment).
- **Vector:** Silent or unvalidated model downgrades on judgment-heavy tasks (security scans, legal audits, architecture reviews) degrade inspection rigor and produce undetected security or compliance vulnerabilities. Cross-vendor fallbacks without explicit opt-in risk confidential code leakage to unvetted AI provider endpoints.
- **Threshold:** `Brand-survival threshold: single-user incident`.

---

## 2. Problem Statement & Motivation

Soleur currently controls model selection per-session, supplemented by ADR-053 / ADR-110 `opts.model` semantic tier pins (`'standard'` / `'cheap'`) in `*.workflow.js` and `haiku` frontmatter on research agents. When a provider encounters rate limits (HTTP 429), capacity degradation, or token quota cliffs, execution stalls completely, aborting long-running autonomous pipelines (e.g. `soleur:one-shot`, `soleur:review`).

Peer framework `HephaestusNG` uses a `workflow.yaml` file mapping session roles to `cli_tool` + `model` with fallback tools (`fallback_cli_tool`) across multiple CLIs (`claude`, `codex`, `opencode`, `pi`, `droid`, etc.). 

While full multi-CLI orchestration is an interesting paradigm, a complete multi-CLI dispatch model imposes a severe "multi-harness tax" on solo founders (requiring 4+ local CLI tools installed, authenticated, and maintained), introduces cross-CLI tool/prompt incompatibilities, and risks violating enterprise data confidentiality.

Instead, this brainstorm adapts the core resilience benefit into Soleur via **Intra-Harness Resilient Model Fallback & Retry**:
1. Automatic exponential backoff on transient 429/overload errors.
2. Graceful downgrade of mechanical steps (`standard` -> `cheap`) on sustained saturation.
3. Strict enforcement of the "never-downgrade" boundary for judgment tiers (`strong` / `advisor`).
4. Strict clean-room implementation ensuring zero copyright or license contamination from AGPL-3.0 sources into Soleur's BSL 1.1 codebase.

---

## 3. Domain Leader Assessments (Phase 0.5)

### 3.1 Chief Product Officer (CPO)
- **Positioning:** Solo founders buy business outcomes ("Company-as-a-Service"), not pipeline harness micro-optimization. Chasing multi-CLI configuration pulls Soleur away from founder adoption.
- **Operator Burden:** Requiring operators to install multiple competing CLIs creates massive friction.
- **Failure Modes:** Silent degradation of critical phases (legal/security) violates brand safety. Fallback must never silently downgrade `strong`/`advisor` tiers.
- **Recommendation:** Scope to intra-harness model fallback; keep full cross-CLI dispatch parked in Milestone 6 (Post-MVP).

### 3.2 Chief Legal Officer (CLO)
- **License Boundary (BSL 1.1 vs AGPL-3.0):** HephaestusNG is licensed under AGPL-3.0; Soleur is BSL 1.1. They are legally incompatible. The functional ideas (per-phase routing, saturation fallback) are uncopyrightable (17 U.S.C. § 102(b)), but zero code, data structures, or expressive YAML schemas may be copied. A strict clean-room protocol derived solely from Soleur's pre-existing ADR-110 and `lib/harness.ts` is required.
- **Data Privacy & ToS (Posture A - Local Plugin):** Silent cross-vendor fallback creates catastrophic compliance liabilities (violating customer NDAs, DPAs, and zero-data-retention terms). Cross-vendor fallback must never occur silently. Intra-harness fallback (within the user's active, authenticated provider) is compliant and safe.
- **PR Provenance Requirement:** PR must include a clean-room attestation trailer.

### 3.3 Chief Marketing Officer (CMO)
- **Value Proposition:** "Unstoppable Autonomous Velocity." Autonomous pipelines that never stall overnight due to provider quota cliffs.
- **Loss Aversion:** Developers fear losing 2 hours of autonomous progress to a 429 cliff far more than they value marginal speed gains.
- **Observability:** Emit clear, perceptible sentinel logs (`[SOLEUR_SATURATION_FALLBACK]`) so resilience is visible to the operator as platform value.

### 3.4 Chief Technology Officer (CTO)
- **Architecture Invariants:** ADR-053 allowlists 12 call sites for mechanical model pins (`standard`/`cheap`); all judgment steps inherit the session model or use `strong`/`advisor`.
- **Runtime Surface:** In `*.workflow.js`, `agent(prompt, opts)` is already wrapped by an IIFE calling `resolveWorkflowModel(opts.model)`. Enhancing this wrapper with retry and fallback preserves existing workflow code without invasive refactoring.
- **Tool Parity:** Cross-CLI spawning fails because subagents depend on harness-specific tools (`Skill`, `Task`, `invoke_subagent`). Intra-harness fallback guarantees 100% tool parity.

---

## 4. Key Decisions & Agreed Architecture

1. **Scope: Intra-Harness Saturation Fallback (Approach 1):**
   - Implemented within the active harness (Claude Code, Grok Build, OpenCode, Antigravity).
   - No external CLI dependencies or multi-CLI installation prerequisites.

2. **Strict Never-Downgrade Invariant (ADR-110 & Brand Safety):**
   - **Mechanical Steps (`standard`, `cheap`):** May retry with backoff, and on sustained 429, `standard` falls back to `cheap`.
   - **Judgment Tiers (`strong`, `advisor`, `inherit`):** Retry with exponential backoff (e.g. 2 attempts), but **NEVER downgrade** to a weaker tier. If saturation persists, fail loudly with an informative error rather than silently degrading review or security quality.

3. **Retry & Backoff Policy:**
   - Detect 429 status codes, `rate_limit_exceeded`, `resource_exhausted`, `overloaded_error`, or CLI quota messages.
   - Jittered exponential backoff (e.g., attempt 1: 2s delay, attempt 2: 5s delay).

4. **Observability & Sentinels:**
   - Emit structured stderr / stdout marker:
     `SOLEUR_SATURATION_FALLBACK phase=<phase> label=<label> from=<from_tier> to=<to_tier> reason=<reason>`
   - Summary of fallbacks included in workflow exit status.

5. **Clean-Room Attestation:**
   - All code derived independently from ADR-110 (`plugins/soleur/lib/harness-model-map.ts`) and `plugins/soleur/lib/harness.ts`.
   - Zero inspection or ingestion of `hmuhlestein/HephaestusNG` code.

---

## 5. Approaches Considered & Compared

| Dimension | Approach 1: Workflow Runner Wrapper (Selected) | Approach 2: Centralized Adapter Circuit Breaker | Approach 3: Two-Tier Hybrid (CLI Subprocess) |
|---|---|---|---|
| **Scope** | `*.workflow.js` agent wrapper + `harness-model-map.ts` | Orchestrator layer in `lib/harness.ts` | Intra-harness + optional external CLI binary |
| **Dependencies** | None (uses active harness) | None | Requires external CLIs (`codex`, `opencode`) |
| **Complexity** | Low / Minimal diff | Medium / High | Very High |
| **Tool Parity** | 100% guaranteed | 100% guaranteed | Low (tools vary across CLIs) |
| **Compliance Risk** | Zero (same vendor) | Zero | High (unvetted vendor data egress) |
| **Recommendation** | **SELECTED** | Viable future enhancement | Deferred to Post-MVP (Milestone 6) |

---

## 6. Open Questions & Parked Branches

- **Parked (Out of Scope):** Cross-CLI subprocess execution (launching separate CLI binaries like `codex exec` or `opencode run` from a Claude session). Parked in Milestone 6 per CPO recommendation; will only be revisited if multi-vendor hosted execution becomes a product requirement.
- **Circuit Breaker Persistence:** In-session memory circuit breaker across workflow phases will be evaluated during planning; initial scope focuses on per-call retry with fallback.

---

## 7. Next Steps

1. Create Feature Specification (`knowledge-base/project/specs/feat-12529-per-phase-cli-dispatch/spec.md`).
2. Hand off to `soleur:plan` to design the concrete test cases and implementation steps for `harness-model-map.ts` and `*.workflow.js` templates.
