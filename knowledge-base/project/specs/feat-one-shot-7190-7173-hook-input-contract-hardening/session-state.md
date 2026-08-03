# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-03-feat-hook-input-exit-codes-and-trust-boundary-extension-plan.md`
- Status: complete

### Errors
None. CWD verified on first call. All halt gates (4.5–4.10) passed. Every path citation
resolves except `ADR-158-*.md`, which this plan creates.

### Decisions
- **Item 1 reframed from the issue's premise.** The Claude Code hooks reference shows `exit 2`
  blocks *and discards stdout JSON*, and `exit 1` discards it while the tool proceeds — so
  `exit 0` is the precondition for the whole ADR-157 posture, not a convention. Measured: all
  20 hooks exit 0 today, asserted nowhere.
- **ADR-158 replaced three defective v1 clauses.** The auxiliary jq program was cut (two
  migration targets sit on `Write`, so it would take a call from 5 forks to 9); the boolean
  group was cut (`durable-reminder` already reads booleans safely); per-matcher responder
  election *in the helper* was cut (a hook never receives its matcher, and `.tool_name` is
  empty on the failure path) in favour of a static settings-derived responder set.
- **#7190 sequenced before #7173** so the new assertions police the migrations on arrival.
- **Two issue sub-items deliberately declined with recorded justification:** the jq hard-fail
  (unreachable in CI either way; 21 sibling suites still skip silently), and full OpenHands
  convergence — though F1 means the mirror is now *fixed* in-scope rather than merely
  documented.
- **The PR-split recommendation was persisted, not applied.** Three reviewers converged on
  splitting at the Phase 3/4 boundary; that contradicts the stated one-PR direction, so it went
  to `decision-challenges.md` as a User-Challenge for `/ship` to surface.

### Blocking defects found by the deepen pass
- **F1** — `.openhands/hooks/guardrails.sh:19` dies under `set -euo pipefail` on any document
  jq rejects, *before* its ADR-156 type check: rc 5, no deny, no incident row. A lone surrogate
  in a sibling field induces it while `.tool_input.command` stays a clean `rm -rf $HOME`.
  #7173's premise that the mirror only needs de-duplication is false — it has a live bypass and
  (via an unsatisfiable `$t == null` conjunct) also hard-denies every payload with no
  `tool_input`.
- **F2** — the widened-slot design as drafted would let a non-string `.tool_input.content`
  disarm the skill-security scanner *silently*, which is ADR-157's explicitly rejected
  fail-open and a regression against that hook's current posture.

### Components Invoked
- `Skill: soleur:plan`, `Skill: soleur:deepen-plan`
- `Explore` x2 (10 advisory hooks; OpenHands mirror)
- `claude-code-guide` (hook exit-code semantics, official docs)
- `soleur:engineering:review:architecture-strategist`, `code-simplicity-reviewer` (plan-review)
- `soleur:engineering:review:test-design-reviewer`, `security-sentinel` (deepen)
- `gh` CLI (premise validation, code-review overlap across 62 open issues); direct empirical
  probes of hook exit codes, jq type semantics, and the OpenHands mirror

## Work Phase
- Status: pending
