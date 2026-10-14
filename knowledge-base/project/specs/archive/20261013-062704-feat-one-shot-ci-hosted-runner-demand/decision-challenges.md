# Decision challenges: feat-one-shot-ci-hosted-runner-demand

## 2026-10-07 plan review (headless)

### User-Challenge 1: write ADR-276 only when stage 3 lands, or cut it

- Operator direction (default, kept): "New ADR must use the next free ADR number ... status Proposed." The brief asks for an ADR proposal as a deliverable of this plan.
- Challenge (DHH): ADR-276 is a plan wearing an ADR costume; Decision 7 (measurement protocol) belongs in the script header, Decision 8 (supply gate) governs a runner nobody is building, and the measured table will rot. Write it when S3 lands with only the authority, fail-closed, draft-light and affected-only decisions.
- Applied: none. ADR-276 stays `proposed`, as asked. Decide at ship time whether to trim Decisions 7 and 8 before the proposal is accepted.

### Taste notes (not applied)

- Shrink the lever-5 memo (simplicity): kept; it is the asked deliverable and was CTO-reviewed.
- Drop the Observability block and tasks.md (DHH): kept; both are plan-skill outputs.
