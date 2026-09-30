# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-30-fix-md-txt-upload-support-and-attach-icon-plan.md
- Status: complete

### Errors
None blocking (temp Tailwind probe file deleted; retired rule id replaced by constitution §Testing cite; lane defaulted to cross-domain).

### Decisions
- Icons "missing" = ADR-255 Button primitive hard-codes px-6 py-3, collapsing 36px icon buttons (also the send arrow). Fix via padding-free `.soleur-btn` + `.soleur-btn-pad` in @layer components.
- Single extension-first resolver in lib/attachment-constants.ts for .md/.txt; applied in validateFiles, presign, attachment pipeline; KB shares one extension list.
- Deepen-plan hardening: extension binding in pipeline, untrusted-content labelling, force-download for non-images, KB .md lowercase/1MB cap/reserved filename refusal.
- Tests: postcss compiled-CSS test, class-contract render test, Playwright bounding-box e2e, resolver truth table across surfaces.
- One PR, two revertable commits (operator asked for both).

### Components Invoked
soleur:plan, soleur:deepen-plan, plan-review panel, security-sentinel, architecture-strategist, spec-flow-analyzer, test-design-reviewer, research agents.
