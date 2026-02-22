# Tasks: Domain Leader Capability Gap Detection

**Plan:** [2026-02-22-feat-domain-leader-gap-detection-plan.md](../../plans/2026-02-22-feat-domain-leader-gap-detection-plan.md)
**Issue:** #234

## Phase 1: Implementation

- [x] 1.1 Add identical Capability Gaps block to all 5 domain leader agents (cto.md, cmo.md, coo.md, cpo.md, clo.md)
- [x] 1.2 Update brainstorm command Phase 3.5 template with optional Capability Gaps section
- [x] 1.3 Update plan command Phase 1.5b to pass brainstorm gap context to functional-discovery
- [x] 1.4 Fix spec.md FR4 to reference only functional-discovery (not agent-finder)

## Phase 2: Validation

- [x] 2.1 Verify cumulative agent description word count stays under 2500 words (2613 -- unchanged, body-only edits)
- [x] 2.2 Run `bun test` -- 818 pass, 0 fail
- [ ] 2.3 Version bump (PATCH)
