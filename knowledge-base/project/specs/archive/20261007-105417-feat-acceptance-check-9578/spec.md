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
- FR6: The result shows the exact command, the time and the output, shows passes and fails equally, and uses the pinned `pass` wording ("Your check passed. This shows only that the check you wrote ran against <sha>, finished without an error and, if you set an expected result, printed it. It does not show that the work is correct or complete, or free of problems this check does not look for. Review the result before relying on it."). It never says "verified", "proven" or "safe".
- FR7: A first-use notice tells the founder that a vague, wrong or risky check can pass broken work or run actions they did not intend, and to read what will run before it runs.

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
- FR2: the block also carries `kind`, `pins` and `approved_at`; `hash` is an identity and the freeze copy in git history is the control. (A `creates` field was added at plan time and cut in the review round.)
- FR5: retries are uncapped and logged; accept-anyway is the only override and is interactive only. Multiple checks, headless capture and PR-body surfacing are deferred (#9657).

## Addendum — 2026-10-06 (#9578, CLO wording review of the built text)

> **Supersedes the wording quoted above where it differs.** The CLO ruled the pass sentence's "complete or safe" negation out (no founder-facing string may contain "verified", "proven" or "safe", with no exemption), and edited the first-use notice (network access, public repository, no secrets), the no-sandbox sentences ("did not run on this computer, so nothing was checked"), the prompts for INVALID, UNTRUSTED, OVERRIDDEN and headless stops, and the roll-up lines. The authority is the `WORDING` constants in `plugins/soleur/skills/preflight/scripts/founder-check.py` (`text --list` names every key), pinned by `plugins/soleur/test/preflight-founder-check.test.ts`. Decision-challenge item 7 is resolved by rewrite, not by exemption.

## Addendum — 2026-10-06 (review round; append-only)

- FR2/TR1 unchanged: `hash:` stays in the block and is computed by `founder-check.py`; the canonical fields are now `kind`, `text`,
  `command`, `expected`, `pins`, `approved_by`, `approved_at`. `creates:` is removed.
- The script's interface is file-based (`verify --out/--command-out`, `classify --verify-json`, `log --verify-json`, reason on
  stdin) so no plan-authored value is typed into a shell word.
- UNTRUSTED is a FAIL that shows the command and its author and never runs it; a forged operator email is not trusted without both PR
  logins (or `--no-pr`).
- Archival (`plans/archive/<ts>-name.md`) and renames keep the freeze; a re-freeze is an operator commit whose subject starts
  `plan: re-freeze founder-stated check`.
- Pins fix the named script only, not what it loads.

## Addendum — 2026-10-07 (second review round; append-only)

- `log` records a measurement, not a choice: `classify` binds the verify record (hash, head sha, digest) and the command that ran;
  an outcome the records do not support is refused.
- A re-freeze is loud and interactive-only: it needs an earlier freeze and a changed block, headless stops on it, and its baseline
  reports PASSED or FAILED, never VACUOUS.
- A plan main already archived is compared with main's freeze, not self-frozen by an unrelated edit.
- Wording changed after the second CLO review (untrusted-fail, untrusted-unmeasured, changed-ask, headless-stop, rejected-ask,
  approval-ask, eyes-ask, reason-prompt, first-use, baseline-ok, no-block, and the `opt-*` answer descriptions). The pinned text is
  `founder-check.py text <key>`; this spec quotes none of it.
