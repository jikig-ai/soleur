# Brainstorm: should git-data primary apt arms skip during a sustained apt archive outage? (#9394)

Date: 2026-10-22 · Lane: cross-domain · Ruled by CTO agent (hr-technical-fork-is-not-an-operator-question)

## What We're Building

Nothing new in code. This is a decision record for #9394: after the bounded-apt change (PR #9383, merged 2026-10-01, ADR-188 amendment), should T17 healthy, R4, the `git-data-ownership.test.sh` runtime arm (counted skip on TIMEOUT) or T5 primary become skip-eligible?

## Key Decisions

| Sub-question | Decision | Why |
|---|---|---|
| T17 healthy, R4 skip-eligible? | No, stay hard | ADR-188 requires >=1 container-dependent arm that cannot decline; with T5 primary, T17 and R4 the only ones left during an apt failure, removing two leaves only the weakest. |
| Ownership counted skip on TIMEOUT? | No | `_runtime_skip` is already a skip locally and a FAILURE under `CI=true` (#8744). A CI skip reverses #8744 for no measured gain. |
| T5 primary? | Stay hard, permanently | Supply-chain checksum guard; a guard skippable on a transient fault loses anti-vacuity value (ADR-180). |
| Act now vs wait? | Wait for triggers; no code change | Neither trigger has fired (evidence below). |

## Evidence (re-derived by the CTO agent, 2026-10-22)

- `gh run list --workflow infra-validation.yml --branch main -L 20`: 18/20 success; the 2 failures (2026-10-19) were an inngest-bootstrap byte-drift assertion and a cron-egress-ghcr-probe assertion, not apt.
- Full logs of those 20 runs: 0 hits for `FIXTURE_APT_CAUSE:`, `FIXTURE_APT_FAILED`, `SKIP (loud)`. Ownership PASSED with `GD_APT: spent=3s of budget=150s`.
- Trigger 2 (two consecutive red main runs on a primary-arm cause line): not fired.
- Trigger 1 (#8856 skip streak): not fired, and cannot fire right now. The probe returned `TRANSIENT` on 2026-10-18 (no `git-data-runcmd-rehearsal:` marker in 8 sampled logs). Last real reading 2026-09-26: 1 loud skip (S1) in 13 runs.
- Bound already exists: 420 s (rehearsal) / 180 s (ownership) apt cap, below the 600 s suite bound, never `rc=124`.

## Residual risk

During a sustained archive outage the `deploy-script-tests (1/4)` leg is red for unrelated PRs, bounded and attributable. The #8856 probe being dead makes "wait for triggers" weaker than it looks; only trigger 2 works until the probe is repaired.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering
**Summary:** CTO ruled no change; keep all four arms hard; flip condition is two consecutive red main runs on a primary-arm cause line plus a confirmed outage, first response a per-arm hold.

### Product
**Summary:** CPO: no end-user-visible change either way; hard-fail is safer for the single-user-incident threshold. A skip would be acceptable only if the deploy path refuses to proceed while an integrity or ownership arm is skipped. No objection to the CTO ruling without the operator.

### Legal
**Summary:** CLO: one narrow dependency. Article 30 register row PA-36 (DRAFTED, not yet active) lists `git-data-ownership.test.sh` as backing the ownership control; keep the wording at "suite exists", never "enforced in CI". Re-check before git-data holds customer repos. Draft analysis, not legal advice.

## User-Brand Impact

- **Artifact:** the git-data CI guard arms (T5 primary, T17 healthy, R4, ownership runtime arm) that gate deploys of per-workspace encrypted git storage.
- **Vector:** a skippable integrity or ownership guard could let an unverified supply-chain or permissions change reach production storage holding customer repos.
- **Threshold:** single-user incident

## Open Questions

- Repair the #8856 skip-persistence probe so trigger 1 can fire (follow-up issue).
- Parked (out of scope): whether a per-arm hold mechanism for sustained outages should be designed ahead of need; only worth doing if trigger 2 fires.

## Session Errors

None.
