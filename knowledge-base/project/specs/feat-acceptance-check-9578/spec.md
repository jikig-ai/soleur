---
feature: acceptance-check-9578
lane: cross-domain
brand_survival_threshold: single-user incident
refs: [9578, 9577, 9620, 9588]
brainstorm: knowledge-base/project/brainstorms/2026-10-06-founder-acceptance-check-brainstorm.md
status: draft
created: 2026-10-06
---

# Spec: founder-defined acceptance check in the brief

## Problem Statement

The founder never states or approves what proves the work is done. Acceptance criteria are engineer-facing plan prose; `qa` runs only the plan's Test Scenarios; `ship` has no acceptance-run gate; and an agent that writes and runs its own check can only certify its own confidence (ADR-175 names this self-certification).

## Goals

- Let the founder state, in plain words, what proves a piece of work is done, before work starts.
- Run that check in a step separate from the work and block ship when it fails, stopping to ask the founder.
- Make a "passed" result say only what is true: the founder's own check ran and returned success.

## Non-Goals

- No new workflow engine, no new agent, and no new ADR-229 workflow edge unless a back-edge is separately justified.
- No hosted Command Center capture and no hosted copy in the first slice (waitlist-only; #9620).
- No marketing claim before the feature ships.
- No claim that checks verify correctness.
- No execution of founder text that the founder has not approved as a literal command.

## Functional Requirements

- FR1: The self-hosted brainstorm and plan prompts ask "What would you check to know this is done?" and carry the answer verbatim into the plan's acceptance field as a `founder_check` block, labelled "founder-stated".
- FR2: The agent proposes the literal runnable check (in the existing `Browser:` / `API verify:` / `discoverability_test.command` shape) and the founder approves that exact text before work starts; the block records `text`, `command`, `expected`, `approved_by` and a `hash`.
- FR3: A check that already passes before work starts is rejected as vacuous (must-fail baseline). A check too vague to observe is rewritten with the founder or marked "needs your eyes".
- FR4: Judgement checks are routed to the founder as a yes/no with evidence; an agent never decides them.
- FR5: A separate step runs the approved check from the committed text, never from agent memory and never in `work`. A failure stops and asks the founder with retry, change the check, or accept anyway; "accept anyway" is recorded as a founder override, never as passed.
- FR6: The result shows the exact command, the time and the output, shows passes and fails equally, and uses the wording: "Your check passed. This shows only that the check you wrote ran and returned success. It does not confirm the work is correct, complete or safe. Review the result before relying on it." It never says "verified", "proven" or "safe".
- FR7: A first-use notice tells the founder that a vague, wrong or unsafe check can pass broken work or run actions they did not intend, and to read what will run before it runs.

## Technical Requirements

- TR1: Extend plan's `## Acceptance Criteria` template (`plugins/soleur/skills/plan/references/plan-issue-templates.md`) with the `founder_check:` sub-field; `work` must not edit the frozen block; the hash is re-verified by the gate.
- TR2: Reuse the preflight Check 10 parser and bubblewrap sandbox (a new check or a generalised Check 10). The sandbox and verb allowlist bound legibility, not authority; do not describe them as a security boundary; the check skips where bwrap is absent and says so.
- TR3: Tests extend `plugins/soleur/test/preflight-discoverability-test.test.ts`, its fixtures under `fixtures/preflight-check-10/`, `plan-skeleton-checkpoint.test.ts` and `preflight-check10-suite-integrity.test.sh`, with mutation proof that a founder-approved check cannot be edited, weakened or satisfied vacuously.
- TR4: An ADR, "Founder-stated acceptance check: frozen, separately executed", with an amendment note to ADR-175.
- TR5: The skill-description word budget is measured before the prompt text is added.

## Acceptance Criteria

- The CLO has reviewed the final UI and result wording.
- No marketing, changelog or demo copy claims the feature before it ships.
- The spec-flow analysis of the fail, retry and override flow is done at plan time.

## Plan-stage amendments (2026-10-06)

Recorded by `knowledge-base/project/plans/2026-10-06-feat-founder-acceptance-check-plan.md`:

- FR1: the prompt is asked in the plan skill only in v1; the brainstorm half is deferred (#9658, brainstorm body ceiling).
- TR2: a new preflight Check 13 reusing Step 10.5, not a generalised Check 10.
- TR3: a new suite `preflight-founder-check.test.ts` with fixtures under `fixtures/founder-check/`, registered in the suite-integrity gate; `plan-skeleton-checkpoint.test.ts` gets a compatibility case; `preflight-discoverability-test.test.ts` is not edited.
- FR2: the block also carries `kind`, `creates` and `pins`; `hash` is an identity and the freeze copy in git history is the control.
- FR5: retries are uncapped and logged; accept-anyway is the only override and is interactive only. Multiple checks, headless capture and PR-body surfacing are deferred (#9657).
