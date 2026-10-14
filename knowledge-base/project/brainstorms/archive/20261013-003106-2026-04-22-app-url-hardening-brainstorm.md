---
date: 2026-04-22
topic: APP_URL hardening (PR #2767 follow-up bundle)
status: complete
---

# Brainstorm: APP_URL Hardening

Bundled scoping for the 3 deferrals and 2 follow-throughs that were filed during PR #2767 (the Doppler `prd` `NEXT_PUBLIC_APP_URL` missing-secret fix).

## What We're Building

A coherent cleanup of the `NEXT_PUBLIC_APP_URL` surface area:

1. **Close verification follow-throughs** for PR #2767 (`#2773`, `#2774`) based on post-deploy Sentry silence.
2. **Harden the two remaining silent `??` fallbacks** in billing and checkout routes so future misconfig fires to Sentry instead of degrading silently (`#2770`).
3. **Consolidate `NEXT_PUBLIC_APP_URL` and `NEXT_PUBLIC_SITE_URL`** into a single canonical var; remove the duplicate from Doppler `prd` (`#2768`).
4. **Add a pre-deploy CI guard** asserting every required `NEXT_PUBLIC_*` secret is present in Doppler `prd` (`#2769`).

## Why This Approach

PR #2767 fixed one symptom (one missing secret). These five issues together neutralise the **class of bug** — silent URL fallbacks that degrade payment-critical flows without a Sentry signal, and secrets missing from Doppler `prd` with no pre-deploy gate. The same configuration smell (two vars for one concept) is also what let the drift happen in the first place.

Shipping this as two PRs keeps blast radius small while avoiding three separate deploy cycles:

- **PR-A = `#2770` + `#2768`**: both touch URL env handling, coherent scope, one Doppler `prd` write (delete `NEXT_PUBLIC_SITE_URL`).
- **PR-B = `#2769`**: workflow-level guard, orthogonal to app code, warrants isolated review.

Verification issues `#2773` / `#2774` close immediately based on the passive Sentry result (see Pre-Work Findings below) — no code change needed.

## Pre-Work Findings (Sentry passive verification)

Sentry issue `114137538` (`SOLEUR-WEB-PLATFORM-H`) queried at `2026-04-22T17:01:54Z`, 8h38m post-deploy (`08:23Z`):

- `count`: 1 (unchanged from pre-deploy baseline)
- `firstSeen` == `lastSeen` == `2026-04-22T07:44:03Z` (pre-deploy firing, the one that motivated PR #2767)
- `status`: unresolved

Zero new events in ~9 hours with normal traffic. Passive signal is load-bearing. `#2773`'s "active trigger" step (login + start agent session) can ride on top of the next authenticated session an operator happens to run; if no event fires, close. `#2774` (docker exec printenv) is redundant per its own issue body ("if `#2773` confirms silence, this check is redundant and can be closed").

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Split into two PRs: PR-A = `#2770`+`#2768`, PR-B = `#2769` | Blast-radius isolation — app code + Doppler write together, CI workflow separate |
| 2 | Canonical var is `NEXT_PUBLIC_APP_URL`; migrate `github-resolve` away from `NEXT_PUBLIC_SITE_URL` | More consumers already on `APP_URL`; avoids a 2-step rename for the majority |
| 3 | Deleting `NEXT_PUBLIC_SITE_URL` from Doppler `prd` requires explicit per-command ack | Per `hr-menu-option-ack-not-prod-write-auth`. No `--force` / menu-option shortcut. |
| 4 | `#2770` Sentry mirror follows the `agent-runner.ts:675` pattern via `reportSilentFallback` | Matches `cq-silent-fallback-must-mirror-to-sentry`, consistent with 15 prior remediations (PR #2480/#2484) |
| 5 | `#2769` required-secrets list is a **hand-maintained array** in the workflow, not auto-computed | YAGNI — auto-compute from Dockerfile ARGs + code grep is ~2x the code for zero detection-speed gain. The next missing secret still reveals the drift. |
| 6 | `#2773` / `#2774` close on passive Sentry signal + opportunistic active trigger | Strong 9h zero-event baseline. Avoids burning a separate session on a login handoff for a redundant check. |
| 7 | PR-A migration sequence: merge code → Doppler `secrets delete NEXT_PUBLIC_SITE_URL -c prd` as post-merge step, not pre-merge | Code must first stop reading the var, else the delete fires a 500. Runtime injection via `--env-file` rebuilds on deploy, so ordering is: ship code → wait for container restart → delete secret → verify env absent. |

## Non-Goals

- **No preview/per-branch URL handling.** `#2768`'s re-evaluation criterion explicitly calls out "when a preview env needs per-branch URLs" as the trigger to rethink. Not in scope.
- **No migration away from `NEXT_PUBLIC_*` to runtime env.** Keep build-time injection; the Dockerfile `ARG` + runtime `--env-file` dual-path is intentional.
- **No expansion of the CI guard to cover non-`NEXT_PUBLIC_*` secrets.** Scope is browser-exposed secrets only — the class that bit us in PR #2767.
- **No auto-compute of required list for `#2769`.** Deferred indefinitely; re-evaluate only if the hand-maintained list drifts twice.

## Open Questions

None blocking. The following resolve during the plan phase:

- Exact CI workflow to wire `#2769` into (candidate: new job in `.github/workflows/reusable-release.yml` gating the existing deploy job).
- Whether to add a unit test for `#2770` that asserts `reportSilentFallback` is called when env is unset, or rely on the existing Sentry-mirror sweep tests.

## Scope & Issue Map

| Issue | Priority | Target PR | Closes via |
|---|---|---|---|
| `#2770` mirror `??` fallbacks to Sentry | p2 | PR-A | `Closes #2770` in PR-A body |
| `#2768` consolidate `APP_URL`/`SITE_URL` | p3 | PR-A | `Closes #2768` in PR-A body |
| `#2769` CI guard for required secrets | p2 | PR-B | `Closes #2769` in PR-B body |
| `#2773` verify Sentry silence post-deploy | follow-through | none | Manual close with comment citing passive signal (this doc) |
| `#2774` verify prod container env | follow-through | none | Manual close with comment citing redundancy per issue body |

## Risks

- **R1 — Doppler `prd` delete fires a 500 if any consumer still reads `NEXT_PUBLIC_SITE_URL`.** Mitigation: Decision #7 sequencing. Grep after merge to confirm zero remaining readers before the delete.
- **R2 — The CI guard itself depends on a `DOPPLER_TOKEN_PRD` service token that must be scoped to `prd` config.** Per `cq-doppler-service-tokens-are-per-config`. The existing deploy job already has this wired; reuse it.
- **R3 — The hand-maintained required-list in `#2769` will drift if a future PR adds a new `NEXT_PUBLIC_*` without updating the array.** Accepted — the first missing-secret firing is the drift signal, same detection speed as auto-compute.

## Domain Assessments

**Assessed:** Engineering (inline). No other domain consulted — this is a scoped infra/observability chore bundle, no user-facing capability, no marketing/product/legal/sales/finance/support implications (per `hr-new-skills-agents-or-user-facing`, CPO/CMO gates apply to user-facing capabilities, which this is not).

### Engineering (inline assessment)

**Summary:** Three well-scoped hardening changes with small code footprint and established patterns (`reportSilentFallback`, Doppler CI checks). Primary architectural risk is the Doppler `prd` delete ordering — addressed via Decision #7. No new dependencies, no schema changes, no migrations.

## Artifacts

- Brainstorm: this file
- Spec: `knowledge-base/project/specs/feat-app-url-hardening/spec.md`
- Prior session context: `knowledge-base/project/specs/feat-one-shot-next-public-app-url-unset/session-state.md` (PR #2767 deferrals)
- Relevant rules: `cq-silent-fallback-must-mirror-to-sentry`, `hr-menu-option-ack-not-prod-write-auth`, `cq-doppler-service-tokens-are-per-config`, `hr-exhaust-all-automated-options-before`
