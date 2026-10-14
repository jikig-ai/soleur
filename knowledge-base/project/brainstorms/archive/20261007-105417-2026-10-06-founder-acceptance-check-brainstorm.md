# Founder-defined acceptance check in the brief (#9578)

Date: 2026-10-06. Lane: cross-domain. Brand-survival threshold: single-user incident. Issue: #9578 (OPEN, no comments). Sibling #9577 (homepage demo) was brainstormed first.

## What We're Building

A way for the founder to state "what proves this is done" in plain words before work starts, and a gate that runs that check, in a step separate from the work, before the work counts as done. First slice: self-hosted only, inside the existing plan, qa and preflight machinery. A failure stops and asks the founder; nothing is auto-passed.

## Why This Approach

Six read-only reports (CPO, CTO, CLO, CMO, repo research, learnings research) agree on the shape.

Today acceptance criteria are engineer-facing prose in the plan (`## Acceptance Criteria`, qa's `## Test Scenarios` with `Browser:`, `API verify:` and `Cleanup:` steps). `qa` runs only the Test Scenarios; `ship` has no acceptance-run gate; `work` self-checks and already says to run an acceptance command's literal text, not a normalized variant. The founder never states or approves a check, and the hosted web app has no brief capture (the "accept" matches in `apps/web-platform` are terms and delegation acceptance).

The central risk is self-certification. ADR-175 says it directly: in one-shot the same agent authors the declaration and runs the gate, which converts a verification gate into self-certification, and it names three mechanical counterweights. A check written and run by the agent that did the work measures that agent's confidence. So the design question is authority over the verdict, not just where the field lives.

Rejected: the founder confirms by hand only (honest but not "an agent runs the check"), and the agent proposes and runs its own check (self-certification).

## Key Decisions

| Decision | Choice | Source |
|---|---|---|
| Who authors and judges | The founder states the check in plain words. The agent proposes the literal runnable check; the founder approves that exact text before work starts. It is frozen with a hash and a must-fail baseline (a check that already passes is rejected). A separate step (qa, or a preflight-style gate) runs it, never `work`. Judgement checks go to the founder as a yes/no with evidence | Operator, on CPO + CTO + learnings convergence |
| First surface | Self-hosted: one question in the brainstorm and plan prompt ("What would you check to know this is done?"), carried verbatim into the plan's acceptance field as `founder_check`, labelled "founder-stated". Hosted Command Center capture is later and out of scope (no brief capture exists, waitlist-only, #9620) | CPO, CTO, CLO |
| Failure behaviour | Stop and show the founder, in plain words, what failed, with retry, change the check, or accept anyway. "Accept anyway" is recorded as a founder override with its own marker, never as passed | CPO, CLO |
| What "passed" says | "Your check passed. This shows only that the check you wrote ran and returned success. It does not confirm the work is correct, complete or safe. Review the result before relying on it." Never "verified", "proven" or "safe to ship". Show the exact command, the time and the output, and show passes and fails equally | CLO |
| Running founder text | Never execute founder text directly. The check runs through the existing preflight Check 10 path (bubblewrap sandbox, verb allowlist). That path bounds legibility, not authority; it keeps network egress and arbitrary in-sandbox code, and it skips when bwrap is absent (macOS). Do not call it a security boundary; show the derived command to the founder | CTO, CLO |
| Mechanics | Plan template gains a `founder_check:` sub-field (`text`, `command`, `expected`, `approved_by`, `hash`); preflight reuses the Check 10 parser and sandbox (a new check or a generalised Check 10); qa runs it; work may not edit the frozen block; ship gets the gate | CTO |
| ADR | Yes: "Founder-stated acceptance check: frozen, separately executed", with an amendment note to ADR-175. No ADR-229 change unless a back-edge ("check failed, back to work") is added as a new workflow edge | CTO |
| Marketing | No claim of any kind before it ships. After ship, self-hosted only and factual: "Write the check that defines done. Soleur runs it and shows you the result." Hold content until then; no hero change (hero CTA test review 2026-11-03) | CMO, CLO |
| Wireframe | None needed: the first slice is prompt text in a CLI, not a page, component or flow. A Command Center capture would need one | Orchestrator |

Productize candidate: none.

## User-Brand Impact

- **Artifact:** the founder-check capture, the frozen check record, and the "check passed" result wording.
- **Vector:** a vague or self-written check is marked passed and the founder believes a verified result (single-user incident); executing founder text is an execution surface.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Build now, narrowly: the founder never defines engineering "done" today, and this is what would make an illustrated "stopped, the check did not pass" state real. Start with the self-hosted prompt; judgement checks route to the founder; a failure stops and asks.

### Engineering

**Summary:** Small to medium. Freeze the founder's check text and hash it before work, run it in a different step from the work, reject a check that already passes, reuse the Check 10 sandbox without calling it a security boundary. Needs an ADR.

### Legal

**Summary:** Go with conditions: a "passed" label may claim only that the founder's check ran and returned success; show the derived command; the first-use notice says a vague or wrong check can pass broken work; a hosted data-reading path triggers the GDPR gate; no marketing claim before ship; hosted copy waits for #9620.

### Marketing

**Summary:** Position as "your standard, checked", never "verified"; no claim before it exists; a short factual changelog entry at ship and a blog only if re-angled to "how do I know it is actually finished?".

## Capability Gaps

- No founder-facing capture of a check exists in the self-hosted flow or the web app (evidence: repo research checked `plugins/soleur/skills/{plan,work,qa,ship,review,one-shot,brainstorm}/SKILL.md` and `apps/web-platform` for acceptance capture; none found).
- No step runs a founder-stated check before ship: `qa` runs `## Test Scenarios`, `ship` has no acceptance-run gate.

## Reconciliation Notes

- The repo researcher proposed a new agent, a new workflow edge, a web-app schema field and a new phase. That contradicts the issue ("extend the plan-phase acceptance field, do not build a new engine") and the CTO's finding that a gate inside qa or ship adds no edge, so it is not adopted. The CTO read only part of ADR-229, so "no new edge needed" is unverified until the plan stage.
- #9577 tension: the CMO says to keep the demo's "stopped, the check did not pass" line out until this ships. The operator approved the labelled-illustration demo (CLO conditions) with that line. This is recorded for the #9577 plan stage; shipping this feature first would make the state real.

## Open Questions

- Does the check run from `qa` (extending its Test Scenarios) or from a new preflight-style check, and how is "founder-approved before work" enforced when a plan is amended during work (plan stage).
- How vague checks are rewritten into something observable or flagged "needs your eyes" (plan stage; needs the spec-flow analysis of the fail/retry flow).
- Whether the skill-description budget allows the new brainstorm and plan prompt text (plan stage, unverified).
- (out of scope) Command Center capture of the check in the hosted app, and any hosted marketing, until #9620 is decided.

## Addendum — 2026-10-06 (#9578, CLO wording review of the built text)

> **Supersedes the wording quoted above where it differs.** The CLO ruled the pass sentence's "complete or safe" negation out (no founder-facing string may contain "verified", "proven" or "safe", with no exemption), and edited the first-use notice (network access, public repository, no secrets), the no-sandbox sentences ("did not run on this computer, so nothing was checked"), the prompts for INVALID, UNTRUSTED, OVERRIDDEN and headless stops, and the roll-up lines. The authority is the `WORDING` constants in `plugins/soleur/skills/preflight/scripts/founder-check.py` (`pass`, `first-use`, `no-sandbox`, `no-sandbox-ask`, `invalid-ask`, `aggregate-judgement`, `overridden-line`, `nosandbox-continued`, `headless-stop`, `untrusted-ask`), pinned by `plugins/soleur/test/preflight-founder-check.test.ts`. Decision-challenge item 7 is resolved by rewrite, not by exemption.
