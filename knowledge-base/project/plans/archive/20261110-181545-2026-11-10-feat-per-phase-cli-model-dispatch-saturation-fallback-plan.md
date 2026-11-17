---
title: "feat(engineering): per-phase CLI/model dispatch with saturation fallback within one pipeline"
date: "2026-11-10"
slug: feat-per-phase-cli-model-dispatch-saturation-fallback
branch: feat-12529-per-phase-cli-dispatch
issue: 12529
closes: 12529
lane: cross-domain
type: feature
priority: p3-low
domain: engineering
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# Implementation Plan: Per-Phase Model Dispatch & Saturation Fallback (#12529)

**Tracking Issue:** [#12529](https://github.com/jikig-ai/soleur/issues/12529)  
**Spec Reference:** [`knowledge-base/project/specs/feat-12529-per-phase-cli-dispatch/spec.md`](../specs/feat-12529-per-phase-cli-dispatch/spec.md)  
**Brainstorm Reference:** [`knowledge-base/project/brainstorms/2026-11-10-per-phase-cli-model-dispatch-saturation-fallback-brainstorm.md`](../brainstorms/2026-11-10-per-phase-cli-model-dispatch-saturation-fallback-brainstorm.md)  
**Branch:** `feat-12529-per-phase-cli-dispatch`  
**Draft PR:** [#12568](https://github.com/jikig-ai/soleur/pull/12568)  

---

## Overview

Issue #12529 proposes adapting a key resilience capability observed in peer frameworks (`HephaestusNG`): handling rate-limit saturation and model routing dynamically across execution phases. 

Following cross-domain leader review (CPO, CLO, CMO, CTO) and operator confirmation during brainstorming, the scope is focused on **Intra-Harness Resilient Saturation Fallback**:
1. Automatic exponential backoff and retry on transient HTTP 429 / quota / overload errors.
2. Dynamic fallback of mechanical workflow steps from `standard` to `cheap` upon sustained saturation.
3. Strict enforcement of the ADR-110 **never-downgrade invariant** for judgment tiers (`strong` and `advisor` tiers fail loudly after retries rather than degrading review or security rigor).
4. Transparent sentinel telemetry (`SOLEUR_SATURATION_FALLBACK`) for operator observability.
5. Strict clean-room implementation ensuring zero intellectual property contamination from AGPL-3.0 sources into Soleur's BSL 1.1 codebase.

---

## User-Brand Impact (Mandated per #5175 / hr-weigh-every-decision-against-target-user-impact)

- **Artifact:** Model dispatch wrapper and tier resolution helpers in `plugins/soleur/lib/harness-model-map.ts` and `*.workflow.js` files.
- **Vector:** If a security audit, legal review, or code verification silently downgrades to a cheaper, lower-capability model during provider saturation, critical flaws or compliance violations will slip into production undetected. Similarly, silent cross-vendor fallback without explicit operator opt-in risks confidential user code leakage to third-party providers.
- **Threshold:** `single-user incident`. A single critical vulnerability or privacy leak caused by an unauthorized tier downgrade constitutes an unacceptable failure.

---

## Scope Check

- **Ask Mapping:**
  - Issue #12529 asks for per-phase CLI/model dispatch with saturation fallback adapted from `HephaestusNG`.
  - Addressed: Model tier dispatch and automated saturation fallback within the active harness; clean-room implementation; integration with ADR-110 semantic tiers.
  - Parked / Out of Scope: Cross-CLI subprocess orchestration (spawning external CLI binaries like Codex/OpenCode from Claude) is deferred to Milestone 6 (Post-MVP) per CPO strategic guidance.
- **Item Provenance:**
  - `standard` -> `cheap` mechanical fallback: directly addresses Issue #12529 "fallback when primary is rate-saturated".
  - Strict refusal on `strong`/`advisor`: mandated by ADR-110 and CPO/CLO risk assessment.
  - Jittered exponential backoff: standard cloud resilience pattern to avoid thrashing on transient 429s.
- **Split Assessment:** Single self-contained PR touching `plugins/soleur/lib/harness-model-map.ts`, `*.workflow.js`, and associated test suites.

---

## Domain Review

**Domains relevant:** engineering, product, legal, marketing

### Engineering (CTO)
**Status:** reviewed  
**Assessment:** The existing `agent(prompt, opts)` wrapper in `*.workflow.js` is the natural interception point. Inlined workflow fences execute in an isolated VM where `resolveWorkflowModel` already binds. Extending this wrapper with retry logic and mechanical fallback keeps workflow call sites unchanged while adding resilience. 100% tool parity is preserved by staying intra-harness.

### Product (CPO)
**Status:** reviewed  
**Assessment:** Restricting scope to intra-harness fallback avoids the "multi-harness installation tax" for solo founders. Never downgrade `strong` or `advisor` tiers silently. Visible sentinel logging turns invisible resilience into a perceptible value moment. Full cross-CLI dispatch stays in Milestone 6.

### Legal (CLO)
**Status:** reviewed  
**Assessment:** Conditional approval. Clean-room protocol strictly enforced: zero code or schema from AGPL-3.0 `HephaestusNG` may be copied or referenced. Implementation is independently derived from Soleur's ADR-110 and `lib/harness.ts`. PR must include a clean-room provenance trailer.

### Marketing (CMO)
**Status:** reviewed  
**Assessment:** Value proposition is "Unstoppable Autonomous Velocity". Highlight resilience against overnight pipeline failures. Keep syntax ergonomic and declarative.

### Product/UX Gate
**Tier:** none (no UI surface touched)  
**Pencil available:** N/A  

---

## Research Insights

### Relevant Files & References
- `plugins/soleur/lib/harness-model-map.ts`: Central semantic model tier resolver (ADR-110).
- `plugins/soleur/test/workflow-model-pins.test.ts`: Standing allowlist enforcing where `opts.model` can be pinned.
- `plugins/soleur/test/harness-model-map.test.ts`: Unit test suite asserting tier mappings and byte parity with workflow fences.
- `plugins/soleur/skills/review/workflows/review.workflow.js`: Canonical workflow implementation utilizing the inlined model map.
- `knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md`: Governing decision for semantic tiers.
- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md`: Mechanical vs judgment step separation.

### Premise Validation (Phase 0.6)
- **Check 1:** ADR-110 is accepted and live on `main`. Confirmed that semantic tiers are `cheap`, `standard`, `strong`, `advisor`, `inherit`.
- **Check 2:** Workflow scripts use an inlined IIFE wrapping `hostAgent` (`resolveWorkflowModel`). Confirmed in `review.workflow.js:498-504`.
- **Check 3:** Peer framework `HephaestusNG` is AGPL-3.0. Confirmed clean-room requirement with CLO.

### Property List (Phase 0.6b)
1. *Resilience:* A workflow step encountering an HTTP 429 or transient provider saturation retries with exponential backoff rather than immediately crashing.
2. *Mechanical Degradation:* If rate limits persist on a mechanical step (`standard`), it automatically fails over to `cheap` tier.
3. *Audit Rigor:* Judgment steps (`strong`, `advisor`, `inherit`) are never downgraded under any saturation event.
4. *Observability:* Every fallback emits a structured diagnostic line `SOLEUR_SATURATION_FALLBACK`.

### Cut List (Phase 0.6b)
- *Multi-CLI subprocess execution:* Cut. Buys cross-CLI redundancy at the cost of high configuration burden, missing tool parity, and potential data leaks. Existing single-harness model fallback covers the resilience property at ~10% of the complexity.

---

## Open Code-Review Overlap

**Matches:** None  
(Queried open `code-review` labeled issues via GitHub API; none touch `lib/harness-model-map.ts` or `*.workflow.js` execution files.)

---

## Architecture & Implementation Details

### 1. Fallback Tier Graph (`lib/harness-model-map.ts`)
Add fallback resolution functions to `harness-model-map.ts`:

```typescript
export const FALLBACK_TIER_GRAPH: Record<SemanticTier, SemanticTier | null> = {
  cheap: null,         // Cannot downgrade further
  standard: "cheap",   // Mechanical downgrade path
  strong: null,        // Strict never-downgrade invariant
  advisor: "strong",   // Scoped consult fallback (Fable -> Opus per ADR-083)
  inherit: null,       // Session judgment never downgraded
};

export function resolveFallbackTier(tier: SemanticTier): SemanticTier | null {
  return FALLBACK_TIER_GRAPH[tier] ?? null;
}
```

### 2. Error Classifier for Saturation / Rate Limits
Define a deterministic error detector:
```typescript
export function isSaturationError(err: unknown): boolean {
  if (!err) return false;
  const msg = typeof err === "string" ? err : (err as any).message || String(err);
  const status = (err as any).status || (err as any).statusCode;
  if (status === 429 || status === 529 || status === 503) return true;
  return /rate[-_ ]?limit|resource[-_ ]?exhausted|overloaded|quota[-_ ]?exceeded|capacity/i.test(msg);
}
```

### 3. Resilient Agent Execution Wrapper
In `*.workflow.js` files (and shared runner helper):
```javascript
;(function (hostAgent) {
  agent = async function resilientAgent(prompt, opts) {
    const tier = opts && typeof opts.model === 'string' ? opts.model : null
    let activeModel = tier ? resolveWorkflowModel(tier) : undefined
    const maxRetries = 2
    let currentTier = tier

    while (true) {
      try {
        const callOpts = activeModel ? { ...opts, model: activeModel } : opts
        return await hostAgent(prompt, callOpts)
      } catch (err) {
        if (!isSaturationError(err)) throw err

        // Check if mechanical fallback is permitted
        const fallbackTier = currentTier ? resolveFallbackTier(currentTier) : null
        if (fallbackTier && fallbackTier !== currentTier) {
          const fallbackModel = resolveWorkflowModel(fallbackTier)
          console.warn(
            `SOLEUR_SATURATION_FALLBACK phase=${opts?.phase || 'unknown'} label=${opts?.label || 'unknown'} from=${currentTier} to=${fallbackTier} model=${fallbackModel}`
          )
          currentTier = fallbackTier
          activeModel = fallbackModel
          // Continue immediately with fallback model
          continue
        }

        // For non-downgradable tiers or already-downgraded, retry with backoff
        // If max retries exceeded, throw to fail loudly
        throw err
      }
    }
  }
})(agent)
```

---

## Files to Edit & Files to Create

### Files to Edit
1. `plugins/soleur/lib/harness-model-map.ts`
   - Add `FALLBACK_TIER_GRAPH`, `resolveFallbackTier()`, and `isSaturationError()`.
2. `plugins/soleur/test/harness-model-map.test.ts`
   - Add unit tests verifying `resolveFallbackTier()` and `isSaturationError()`.
3. `plugins/soleur/skills/review/workflows/review.workflow.js`
   - Update the inlined model map fence and resilient agent wrapper.
4. `plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js`
   - Update inlined model map fence and resilient agent wrapper.
5. `plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js`
   - Update inlined model map fence and resilient agent wrapper.
6. `plugins/soleur/skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js`
   - Update inlined model map fence and resilient agent wrapper.
7. `plugins/soleur/skills/resolve-parallel/workflows/resolve-parallel.workflow.js`
   - Update inlined model map fence and resilient agent wrapper.
8. `plugins/soleur/skills/resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js`
   - Update inlined model map fence and resilient agent wrapper.
9. `plugins/soleur/skills/resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js`
   - Update inlined model map fence and resilient agent wrapper.
10. `knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md`
    - Add Addendum documenting the saturation fallback graph and never-downgrade invariant.

### Files to Create
1. `plugins/soleur/test/saturation-fallback.test.ts`
   - Test suite verifying simulated 429 retries, standard->cheap fallback, never-downgrade enforcement on strong/advisor, and sentinel emission.

---

## Implementation Phases

### Phase 1: Setup & Fallback Logic (`lib/harness-model-map.ts`)
- [ ] 1.1 Implement `FALLBACK_TIER_GRAPH` and `resolveFallbackTier()` in `harness-model-map.ts`.
- [ ] 1.2 Implement `isSaturationError()` helper matching HTTP 429, 529, 503, and quota/overload error strings.
- [ ] 1.3 Add unit tests in `plugins/soleur/test/harness-model-map.test.ts` testing the fallback graph for all semantic tiers.

### Phase 2: Resilient Workflow Runner Wrapper
- [ ] 2.1 Author the resilient execution IIFE with exponential backoff and mechanical fallback logic.
- [ ] 2.2 Update inlined model map fences in allowlisted `*.workflow.js` files (`review`, `plan-review`, `deepen-plan`, `drain-labeled-backlog`, `resolve-parallel`, `resolve-todo-parallel`, `resolve-pr-parallel`).
- [ ] 2.3 Verify fence byte-parity across all workflow files using `bun test plugins/soleur/test/harness-model-map.test.ts`.

### Phase 3: Comprehensive Testing & Verification
- [ ] 3.1 Create `plugins/soleur/test/saturation-fallback.test.ts` with mock agent runners.
- [ ] 3.2 Test that mechanical step (`standard`) retries and successfully falls back to `cheap` upon simulated 429.
- [ ] 3.3 Test that judgment step (`strong`/`advisor`) retries but strictly refuses to downgrade, throwing an error.
- [ ] 3.4 Test that `SOLEUR_SATURATION_FALLBACK` sentinel is emitted to stderr.
- [ ] 3.5 Run `bun test plugins/soleur/test/workflow-model-pins.test.ts` to ensure zero pin allowlist violations.

### Phase 4: Documentation & Clean-Room PR Attestation
- [ ] 4.1 Update ADR-110 with the Saturation Fallback Addendum.
- [ ] 4.2 Run precommit guards and tests (`bun test`).
- [ ] 4.3 Commit changes and push to PR #12568 with the mandatory Clean-Room Provenance trailer:
  `Provenance: Clean-room implementation independently derived from ADR-110 and lib/harness.ts; zero source code copied or referenced from hmuhlestein/HephaestusNG.`

---

## Acceptance Criteria

1. **AC1 (Fallback Graph):** `resolveFallbackTier('standard')` returns `'cheap'`. `resolveFallbackTier('strong')`, `resolveFallbackTier('cheap')`, and `resolveFallbackTier('inherit')` all return `null`.
2. **AC2 (Mechanical Fallback):** When a workflow call with `model: 'standard'` encounters an HTTP 429 error, it retries and falls back to `model: 'cheap'`, allowing the workflow to complete.
3. **AC3 (Never-Downgrade Invariant):** When a workflow call with `model: 'strong'` or `model: 'inherit'` encounters an HTTP 429 error, it never downgrades to `standard` or `cheap`, failing loudly after retries.
4. **AC4 (Sentinel Emission):** Any fallback event emits `SOLEUR_SATURATION_FALLBACK` with `from`, `to`, and `phase` fields.
5. **AC5 (Fence Parity):** All inlined workflow fences in `*.workflow.js` remain byte-identical and pass `harness-model-map.test.ts`.
6. **AC6 (Clean-Room Provenance):** PR #12568 description carries the exact CLO-mandated clean-room attestation trailer.
