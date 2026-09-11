# Decision challenges — feat-one-shot-8050-apply-sentry-infra-red-on-main

Taste / user-challenge items surfaced at plan review (headless; not auto-applied). `ship` Phase 6 renders these into the PR body and files an `action-required` issue.

## 1. Keep the #7997 fold-in in this PR (taste)

- **Finding (dhh-rails-reviewer, P1):** the curl transport-confinement + host/org pins are scope creep in a "main is red" fix; `lint-bot-statuses` is non-required, so leave it red and keep #7997 whole.
- **Counter (code-simplicity-reviewer, CTO):** editing `scripts/sentry-alert-live-fidelity.sh` pulls its 3 pre-existing Rule-D violations into the lint's `--changed` scope; the fix is ~6 lines with 2 suite rows, and a red status on the PR is noise the ship phase must explain.
- **Decision taken:** keep the fold-in (fidelity-script rows only; `sentry-monitors-audit.sh` rows stay in #7997). Reverse by dropping Phase 2.1's last bullet, 2.2, AC5, P6 and Guard 2 rows P5 + the shim must-PASS row.

## 2. Amend ADR-031 rather than open a new ADR (taste)

- **Finding (architecture-strategist, P2 advisory):** the reusable principle ("a post-write probe's reference is derived from the declared source and held equal to the plan pre-merge; live captures are adoption records") plus the trust-posture argument is decision-record content a blockquote cannot hold; a short new ADR fits better.
- **Decision taken:** dated amendment note on ADR-031 (Phase 6.2); the core decision (Terraform is the source of truth) is unchanged. Reverse by running `/soleur:architecture create` and pointing the ADR-031 note at the new ordinal.

## 3. Delete the pre-apply gate copy in the apply job (both-panels rule; simplicity dissented)

- **Simplification panel (dhh):** redundant once the apply job projects its reference from its own plan.
- **Correctness panel (spec-flow):** its red routes to a tracking issue whose remedy ("re-run") cannot fix a stale committed file.
- **Dissent (code-simplicity-reviewer):** keep both call sites — one line, matches the pattern of the sibling guards.
- **Decision taken:** deleted per "both panels fire → prefer delete". Reverse by adding the call after the adoption-assert in the `apply` job and restoring AC11's second count to `1`.

## 4. Keep the projection module in `on.push.paths`; the gate script is NOT there (taste, revised at review)

- **Finding:** a push touching only those files runs a prod-token 0-change plan and a no-op apply.
- **Decision taken at plan review:** keep both (precedent `destroy-guard-filter-sentry.jq`, #4419).
- **Revised at code review (architecture-strategist + code-simplicity-reviewer converged):** §3 above removed the apply job's gate call, so the apply job never executes `scripts/sentry-alert-reference-gate.sh` — a push touching only it would run a prod plan that exercises nothing. The gate stays in the `detect-changes` regex (PR-time, where it IS run); only `tests/scripts/lib/sentry-alert-projection.jq` stays in `on.push.paths` (the apply job runs it twice: plan-step projection and the probe's live side).
