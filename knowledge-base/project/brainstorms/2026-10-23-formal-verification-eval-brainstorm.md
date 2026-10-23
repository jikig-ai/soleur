---
date: 2026-10-23
topic: formal-verification-eval
lane: cross-domain
brand_survival_threshold: single-user incident
status: parked
---

# Formal verification for Soleur: evaluation (parked)

## What We're Building

Nothing yet. The question was whether Soleur could apply formal verification (FV) per PR or as a scheduled job, what it would cost, and whether it could let Soleur ship "bug-free" code to users. Triggered by Anthropic Frontier Red Team, "formal-verification" (2026-10-22). Decision: park, record findings, file a tracking issue with revisit triggers.

## Source article (fetched 2026-10-23, treated as data)

- Claude wrote Rocq proofs at RISC-V binary level that 239 OSS-Fuzz entry points in 123 C/C++ libraries never crash on inputs under 64 MB (single-threaded static musl binaries). Hundreds of bugs found.
- Cost: weeks of wall time, ~180M lines of Rocq, "hundreds of millions of tokens" per proof.
- Authors state "formally verified" does not mean "bug-free" (spec/model/trusted-base gaps, caller misuse) and warn of reward hacking when the agent may patch code.
- Tools: Rocq, Verus, Theorem's RISC-V/Linux semantics. Lean and Dafny were not used.

## Why This Approach (park)

- **Wrong target class.** Tracked files (re-derived two ways by repo research): 2,050 `.ts`, 528 `.tsx`, 1,680 `.sh`, 336 `.sql`, 90 `.tf`, 0 `.rs`. No mature verifier for TypeScript; Kani/Verus have nothing to verify.
- **Escaped-bug classes mostly aren't provable.** Learnings point to tests-pass-for-wrong-reason, vacuous gates, config drift, env leakage. Those need mutation testing, hermetic isolation or live checks, not proofs. (Keyword histogram from the learnings agent is noisy; treat as rough.)
- **Closest existing primitives:** fast-check property tests (ADR-293, 4 suites), RLS authz fuzz gate (ADR-111). No TLA+/Alloy/SMT/mutation testing anywhere.
- **Cadence:** nothing viable is cheap enough to gate PRs. If anything is built, it is scheduled/nightly.
- **Claims risk:** "bug-free"/"verified" conflicts with T&C §7/§10 and Disclaimer §1.1/§3.3 as-is language; CLO and CPO both flag overclaim risk.

## Key Decisions

| Decision | Choice |
|---|---|
| Scope | Park; findings recorded only (operator choice) |
| User-facing "verified"/"bug-free" claims | Do not make. Any future assurance wording needs CLO + CMO review |
| If revisited | Internal scheduled spike first, not a PR gate |

## Candidate spike (not committed to)

1. Model-based property tests (`fc.commands`) for `apps/web-platform/lib/chat-state-machine.ts` (2,302 lines, example-based tests only), nightly with high `numRuns`.
2. Per-PR check that every RLS-table migration has a fuzz case (extends ADR-111).
3. Mutation testing (Stryker) to grade existing tests: the cheapest answer to the vacuous-gate class.
4. Bounded TLA+ spike on the Inngest cutover state machine or session lifecycle.
5. Adjacent gap: Semgrep runs only via the review agent, not in any CI workflow.
Record bugs found per token spent, then decide.

## Revisit triggers (any one)

- At least 3 of the 10 alpha founders ask for correctness assurance, or a founder churns over a shipped bug (CPO).
- A spike shows a technique catches defects property tests missed at acceptable token cost (CPO/CTO).
- A Soleur component is written in Rust/C where the article's method applies.

## Open Questions

- Theorem's proof/semantics licence compatibility with Soleur's BSL: unverified (CLO).
- Whether PA-22 (BYOK) governs customer code sent to a third-party prover: unverified; a prover vendor would be a new Art. 30 recipient and needs a `gdpr-gate` run.
- Architecture decision on a verification tiering (property / model-check / SMT) would need an ADR if pursued.

## User-Brand Impact

- **Artifact:** any user-facing statement that Soleur-produced code is "verified" or "bug-free".
- **Vector:** overclaim that a user relies on, a shipped bug contradicting the claim, trust breach.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** No FV exists; method doesn't transfer to TS/SQL/bash. Property tests, RLS fuzz and mutation testing give most of the value at ~1% of cost; scheduled cadence only.

### Product

**Summary:** Demand unproven (PIVOT verdict, 1/10 alpha founders). Dogfood-only; if user-facing, an assurance report of what was and wasn't checked, never "verified".

### Legal

**Summary:** Marketing overclaim is the main exposure; as-is terms don't cleanly defeat express "verified" marketing. New prover vendor would be an Art. 30 recipient. Gate any claim through CLO + CMO.

## Capability Gaps

- No mutation-testing tool: `git grep -il stryker` returned nothing (CTO).
- No TLA+/Alloy/SMT tooling: strict-term grep across `knowledge-base/**` found only 2 incidental hits (repo research).
- Semgrep absent from CI: `grep -il semgrep .github/workflows/*.yml` returned 0 (repo research).
