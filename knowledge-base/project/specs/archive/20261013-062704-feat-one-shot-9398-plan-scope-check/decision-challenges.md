# Decision Challenges — feat-one-shot-9398-plan-scope-check

Recorded headless (plan ran inside a one-shot subagent; no operator gate available).

## Challenge 1 — New gate vs ADR-131 gate-moratorium proposal

- **Context:** This plan adds an always-on plan-time gate (Scope Check) plus a deepen-plan
  halt and a contract test. `ADR-131` (`status: proposed`, undecided) proposes a moratorium
  on new gates/linters/probes, arguing each gate is a permanent issue generator.
- **Decision taken (default = operator's stated direction):** proceeded — the issue (#9398)
  is itself the operator's filed remedy for a measured cost incident (#9339), i.e. this gate
  exists to *reduce* review spend, and the moratorium proposal is unadopted.
- **Mitigations applied:** enforcement is a prose halt + one bun test — no new lint script,
  CI job, or scheduled check (the moratorium's named class); the ADR-131 tension is recorded
  in the ADR (provisional 265) Alternatives Considered.
- **For ship:** surface this under the 5-line user-challenge frame if `ship` renders
  decision-challenges into the PR body.

## Challenge 2 — plan/SKILL.md is at its byte ceiling (14 B headroom)

- **Context:** `skill-body-budget.json` ceiling for `plan` is 120000 B; the file is 119986 B.
  Any addition requires a compensating trim; raising the ceiling is a separate reviewed PR.
- **Decision taken:** gate spec lives in `references/plan-scope-check.md` (uncapped) with a
  ~340 B pointer phase; compensating trim targets decorative `<thinking>` scaffolding blocks
  (no load-bearing conditions) rather than compressing conditional prose (#8647 edge).
- **Alternative the reviewer may prefer:** bump the `plan` ceiling in this PR anyway — but
  the ratchet rule says ceiling-raises are a separate reviewed PR; flagged so review can
  consciously override if it disagrees.
