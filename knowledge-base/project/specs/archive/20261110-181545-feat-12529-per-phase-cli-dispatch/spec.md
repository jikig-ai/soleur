---
title: "feat(engineering): per-phase CLI/model dispatch with saturation fallback within one pipeline"
date: "2026-11-10"
lane: cross-domain
status: draft
closes: 12529
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# Feature Specification: Per-Phase Model Dispatch & Saturation Fallback

**Feature Directory:** `knowledge-base/project/specs/feat-12529-per-phase-cli-dispatch`  
**Brainstorm Reference:** `knowledge-base/project/brainstorms/2026-11-10-per-phase-cli-model-dispatch-saturation-fallback-brainstorm.md`  
**Tracking Issue:** [#12529](https://github.com/jikig-ai/soleur/issues/12529)  
**Branch:** `feat-12529-per-phase-cli-dispatch`  
**Draft PR:** [#12568](https://github.com/jikig-ai/soleur/pull/12568)  

---

## 1. Problem Statement

Autonomous multi-phase pipelines in Soleur (e.g. `soleur:review`, `soleur:one-shot`, `soleur:deepen-plan`, `soleur:resolve-parallel`) currently pin model tiers at mechanical steps via ADR-053 / ADR-110 (`'standard'`, `'cheap'`). However, if an AI provider encounters rate limits (HTTP 429), token capacity saturation, or temporary downtime, the workflow crashes, aborting long-running autonomous runs and forcing manual restarts.

While peer tools like `HephaestusNG` map each session role to arbitrary CLI tools and fallback CLIs, requiring developers to install and maintain multiple competing CLIs is impractical and fragile. Furthermore, uncoordinated cross-vendor failovers risk data leakage and client NDA/DPA violations.

Soleur requires a robust, zero-dependency **Intra-Harness Saturation Fallback** mechanism that retries with exponential backoff and automatically downgrades mechanical steps (`standard` -> `cheap`) while strictly protecting judgment tiers (`strong` and `advisor`) from quality degradation.

---

## 2. Goals & Non-Goals

### Goals
1. **Pipeline Resilience:** Prevent 429 rate-limit cliffs and transient overloads from aborting autonomous workflow runs.
2. **Never-Downgrade Invariant:** Strictly guarantee that judgment-heavy tasks (`strong` and `advisor` tiers: security, legal, architecture, review verify/concur) NEVER silently downgrade to a weaker model tier.
3. **Mechanical Failover:** Allow mechanical tasks (diff classification, issue filing, report assembly) to fall back from `standard` to `cheap` upon sustained saturation.
4. **Transparent Observability:** Emit structured `SOLEUR_SATURATION_FALLBACK` sentinels when fallback occurs so developers see exactly when resilience saves their pipeline.
5. **Clean-Room Derivation:** Implement 100% independently from Soleur's pre-existing ADR-110 and `lib/harness.ts` with zero code or schema copied from AGPL-3.0 sources.

### Non-Goals
1. **Cross-CLI Subprocess Spawning:** Launching separate CLI binaries (e.g. shelling out to Codex, OpenCode, or Droid from a Claude Code session) is explicitly out of scope for this release and deferred to Milestone 6 (Post-MVP).
2. **Dynamic Cross-Vendor Billing / Credit Negotiation:** Automatic billing routing across independent paid subscriptions is out of scope.
3. **UI / Dashboard Visualizers:** No frontend UI changes; this is an infrastructure and workflow execution layer enhancement.

---

## 3. User-Brand Impact (Single-User Incident Threshold)

- **Artifact:** Model dispatch wrapper and tier resolution helpers in `plugins/soleur/lib/harness-model-map.ts` and `*.workflow.js`.
- **Vector:** If a security audit or legal review silently downgrades to a cheaper, lower-capability model during a rate-limit event, subtle vulnerabilities or regulatory non-compliance will pass undetected.
- **Threshold:** `single-user incident`. A single missed critical vulnerability caused by unauthorized tier downgrade constitutes an unacceptable failure.

---

## 4. Functional Requirements

### FR1: Saturation & Rate-Limit Detection
- The workflow execution layer must detect rate limit and saturation conditions, including HTTP status `429`, error code `rate_limit_exceeded`, `resource_exhausted`, `overloaded_error`, or provider-specific capacity error messages.

### FR2: Jittered Exponential Backoff
- When saturation is detected, the execution layer must retry the invocation with jittered exponential backoff (up to 2 retry attempts) before triggering tier failover or throwing an error.

### FR3: Mechanical Step Fallback
- If a mechanical step pinned to `standard` continues to fail after retries, the execution layer must automatically fall back to the `cheap` tier for that harness and re-attempt the task.

### FR4: Strict Never-Downgrade Invariant for Judgment Tiers
- Tasks assigned to `strong` or `advisor` tiers (or inheriting session judgment) must **never** be downgraded to `standard` or `cheap`. If retries fail under saturation, execution must throw an error loudly with diagnostic context, preserving audit rigor.

### FR5: Fallback Sentinel Telemetry
- Whenever a fallback is triggered, emit a structured log line:
  `SOLEUR_SATURATION_FALLBACK phase=<phase> label=<label> from=<from_tier> to=<to_tier> reason=<reason>`
  and display a visible warning in the workflow run summary.

---

## 5. Technical Requirements

### TR1: Semantic Fallback Mapping (`harness-model-map.ts`)
- Extend `plugins/soleur/lib/harness-model-map.ts` to export:
  - `resolveFallbackTier(tier: SemanticTier, harness: Harness): SemanticTier | null`
  - Defines the legal fallback graph:
    - `standard` -> `cheap`
    - `cheap` -> `null` (no downgrade)
    - `strong` -> `null` (strict never-downgrade)
    - `advisor` -> falls back to `strong` (existing ADR-083 Fable -> Opus path) or `null`
    - `inherit` -> `null`

### TR2: Workflow Runner Wrapper (`*.workflow.js`)
- Update the workflow wrapper IIFE in allowlisted workflows (e.g. `review.workflow.js`, `plan-review.workflow.js`, etc.) to wrap `agent(...)` calls in a resilient execution loop implementing backoff and mechanical fallback.

### TR3: Unit & Parity Tests
- Add comprehensive Bun tests in `plugins/soleur/test/harness-model-map.test.ts` asserting:
  - Correct fallback tier mapping across all supported harnesses (`claude`, `grok`, `opencode`).
  - Strict refusal to downgrade `strong` and `cheap`.
  - Resilience wrapper correctly retries and falls back on simulated 429 errors.
  - Byte-parity between canonical definitions and workflow inlined fences.

---

## 6. Intellectual Property & Clean-Room Attestation

- **Provenance:** Clean-room implementation independently derived from ADR-110 (`plugins/soleur/lib/harness-model-map.ts`) and `plugins/soleur/lib/harness.ts`.
- **License Boundary:** Zero source code, AST definitions, or expressive YAML schemas were inspected, copied, or ingested from `hmuhlestein/HephaestusNG` (AGPL-3.0), preserving the purity of Soleur's BSL 1.1 codebase.
