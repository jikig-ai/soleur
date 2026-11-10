# Tasks: Per-Phase Model Dispatch & Saturation Fallback (#12529)

**Specification:** [`spec.md`](spec.md)  
**Tracking Issue:** [#12529](https://github.com/jikig-ai/soleur/issues/12529)  
**Branch:** `feat-12529-per-phase-cli-dispatch`  
**PR:** [#12568](https://github.com/jikig-ai/soleur/pull/12568)  

---

## Phase 1: Setup & Fallback Tier Logic

- [ ] 1.1 Extend `plugins/soleur/lib/harness-model-map.ts` with `resolveFallbackTier(tier, harness)` and `FALLBACK_TIER_GRAPH`.
- [ ] 1.2 Add unit tests in `plugins/soleur/test/harness-model-map.test.ts` verifying fallback resolutions and strict refusal to downgrade `strong`/`cheap`.

## Phase 2: Resilient Workflow Runner Implementation

- [ ] 2.1 Implement `resilientAgent(hostAgent, prompt, opts)` with retry backoff (2 attempts) and mechanical fallback (`standard` -> `cheap`).
- [ ] 2.2 Wire structured sentinel emission `SOLEUR_SATURATION_FALLBACK` when fallback occurs.
- [ ] 2.3 Update inlined workflow fences across allowlisted `*.workflow.js` files (`review.workflow.js`, `plan-review.workflow.js`, etc.).
- [ ] 2.4 Verify fence byte-parity with `plugins/soleur/test/harness-model-map.test.ts`.

## Phase 3: Verification & Test Suite

- [ ] 3.1 Run `bun test plugins/soleur/test/harness-model-map.test.ts`.
- [ ] 3.2 Run `bun test plugins/soleur/test/workflow-model-pins.test.ts` to ensure no allowlisted pin violations.
- [ ] 3.3 Add simulated 429 mock test asserting exponential backoff and `standard` -> `cheap` failover.

## Phase 4: Documentation & Clean-Room PR Attestation

- [ ] 4.1 Update ADR-110 with an addendum documenting the saturation fallback mechanism.
- [ ] 4.2 Commit all artifacts and push to PR #12568 with Clean-Room Provenance Attestation.
