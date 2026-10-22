---
title: Should git-data primary apt arms skip during a sustained apt archive outage?
date: 2026-10-22
issue: 9394
related_issues: [8744, 8856, 9379, 10786]
related_adrs: [ADR-188, ADR-180]
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: git-data primary apt arms during an apt archive outage (#9394)

Ruled by CTO agent (`hr-technical-fork-is-not-an-operator-question`).

## What We're Building

Nothing new in code. This is a decision record for #9394: after the bounded-apt change (PR #9383, merged 2026-10-01, ADR-188 amendment), should T17 healthy, R4, the `git-data-ownership.test.sh` runtime arm, or T5 primary become skip-eligible?

## Why This Approach

No change, because the two re-evaluation triggers in the issue have not fired and the current posture is bounded and attributable. Making a primary arm skippable removes the only failing direction that ADR-188 requires to stay non-declinable.

## Key Decisions

| Sub-question | Decision | Why |
|---|---|---|
| T17 healthy, R4 skip-eligible? | No, stay hard | ADR-188 (2026-08-20 amendment, #7572) requires at least one container-dependent arm that cannot decline. During an apt failure only T5 primary, T17 healthy and R4 remain; removing two leaves only the weakest. (T5 mutation, T17 mutation and the S1 family already reach `arm_skip`; this decision is about the primary arms.) |
| Ownership counted skip on a TIMEOUT cause? | No | A bounded-apt timeout emits `FIXTURE_APT_FAILED`, which takes `_runtime_skip`: a counted skip off CI and a FAILURE when `CI=true`. #8744 asks to keep that fail-closed behaviour. Changing it would reverse that request for no measured gain. |
| T5 primary? | Stay hard until the flip condition fires | Supply-chain checksum guard; a guard skippable on a transient fault loses its anti-vacuity value (ADR-180). |
| Act now vs wait? | Wait for triggers; no code change | Neither trigger has fired (evidence below). |
| What is a "hold"? | A time-boxed, issue-tracked, human-approved edit | Never an `arm_skip` and never a `CI` override. A hold is the first response to the flip condition; it does not weaken T5 primary. |

## Evidence (re-derived by the CTO agent, 2026-10-22)

- `gh run list --workflow infra-validation.yml --branch main -L 20`: 18 of 20 succeeded; the 2 failures (2026-10-19) were an inngest-bootstrap byte-drift assertion and a cron-egress-ghcr-probe assertion, not apt. The 20 runs span roughly 2026-10-19 to 2026-10-21, a thin window.
- Full logs of those 20 runs: 0 hits for `FIXTURE_APT_CAUSE:`, `FIXTURE_APT_FAILED`, `SKIP (loud)`. Ownership passed in run 39612112094.
- Trigger 2 (two consecutive red `main` runs on a primary-arm cause line): not fired.
- Trigger 1 (#8856 skip streak): not fired, and cannot fire right now. The probe returned `TRANSIENT` on 2026-10-18 (3 consecutive; no `git-data-runcmd-rehearsal:` marker in the sampled logs). Last real reading 2026-09-26: 1 loud skip (S1) in 13 runs.
- Bound already exists: 420 s (rehearsal) / 180 s (ownership) apt cap, below the 600 s suite bound, never `rc=124`.

## Residual risk

During a sustained archive outage the `deploy-script-tests (1/4)` leg is red for unrelated PRs, bounded and attributable. The #8856 probe being dead makes "wait for triggers" weaker than it looks; only trigger 2 works until the probe is repaired (#10786).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO ruled no change; keep all four arms hard; flip condition is two consecutive red main runs on a primary-arm cause line plus a confirmed outage, first response a hold (defined above), not a skip.

### Product

**Summary:** CPO: no end-user-visible change either way; hard-fail is safer for the single-user-incident threshold. A skip would be acceptable only if the deploy path refuses to proceed while an integrity or ownership arm is skipped. No objection to the CTO ruling without the operator.

### Legal

**Summary:** CLO: one narrow dependency. Article 30 register row PA-36 (declared, not live) lists `git-data-ownership.test.sh` as backing the ownership control; keep the wording at "suite exists", never "enforced in CI". Re-check before git-data holds customer repos. Draft analysis, not legal advice.

## User-Brand Impact

- **Artifact:** the git-data CI guard arms (T5 primary, T17 healthy, R4, ownership runtime arm) that run in the `deploy-script-tests` CI leg for the per-workspace encrypted git storage.
- **Vector:** a skippable integrity or ownership guard could let an unverified supply-chain or permissions change reach production storage holding customer repos.
- **Threshold:** single-user incident

## Open Questions

- Repair the #8856 skip-persistence probe so trigger 1 can fire: tracked in #10786.
- Parked (out of scope): whether a mechanism for the "hold" should be designed ahead of need; only worth doing if trigger 2 fires.

## Session Errors

None.
