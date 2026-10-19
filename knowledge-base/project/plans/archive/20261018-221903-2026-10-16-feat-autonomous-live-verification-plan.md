---
title: "feat: Soleur stops handing live verification to the operator"
date: 2026-10-16
slug: autonomous-live-verification
branch: feat-qa-autonomous-live-verification
issue: 10449
lane: cross-domain
type: feature
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-10-16-autonomous-live-verification-brainstorm.md
spec: knowledge-base/project/specs/feat-qa-autonomous-live-verification/spec.md
---

# feat: Soleur stops handing live verification to the operator

## Overview

After a flag flip or deploy, an agent must not tell the operator to "start a Concierge session in the web app."
This plan makes the existing ADR-064 live-verify harness safe to rely on (a run-time I-cannot-spend gate), corrects
the skills that misdescribe it, and replaces the operator hand-off with a defined verification ladder. It adds no QA
agent.

Plan review (5 agents) and plan-time investigation cut v1 well below the brainstorm. What v1 can and cannot do:

- **Can:** verify LLM-free behaviour in prod through the existing blocking gate; refuse to run if the synthetic
  principal could ever spend; stop skills from routing live steps to the operator.
- **Cannot (needs an operator authorisation, OD1):** generate real Concierge traffic in prod. The principal's Anthropic
  key is a decrypt-poisoned dummy by design, and a funded key breaks ADR-064's cannot-spend property.
- **Deferred with its prerequisites named:** a passive verification path for traffic-dependent flags (read-only
  credential path, positive-observation semantics, deadline escalation, post-flip trigger).

## Research Insights

**Premise validation.** `gh issue view 5463` is CLOSED; `.github/workflows/web-platform-release.yml` ("Enforce
live-verify gate") exits 1 on `BLOCK=1`, flipped 2026-06-18. `postmerge/SKILL.md:376` still says REPORT-ONLY. The
brainstorm's blocking question (zero `scope_grants` blocks Concierge fetch?) is resolved: `I-action-send-free` guards only
`apps/web-platform/app/api/dashboard/today/[id]/send/route.ts`, unrelated to web fetch.

**Property list.**
- P1: after a flag flip or deploy, no skill routes a live-session step to the operator.
- P2: where a check needs traffic the gate cannot lawfully generate, the agent files a tracker naming the exact missing
  capability, never a silent skip and never an operator-session request.
- P3: the synthetic principal can never spend: every `api_keys` row is the sentinel and no BYOK delegation exists.
- P4: skills describe the gate as blocking and cite the enforcing workflow step.

**Cut list (with the reviewer that cut it).** Runner/`flows/` split and zero-flow floor (DHH, simplicity: one flow exists;
the release workflow already blocks on a missing RESULT line). New QA agent. New prod route opening a sandbox session
(CTO). Per-run prod org (ADR-064). Funded Anthropic key (CTO; OD1). `qa-fixtures` contract ADR and parser (simplicity:
no consumer; one paragraph goes in the ADR-064 amendment, build deferred to #10450). Phase "measurement" (moves to
#10450). `ship`/`qa` edits (DHH: grep found no live-session hand-off there; scoped to `postmerge` and `flag-set-role`).

**Key files.** `apps/web-platform/scripts/live-verify/run.ts` (`verifyPrincipal` ~311-350 is the only
`VerifiedPrincipal` constructor), `apps/web-platform/scripts/seed-live-verify-user.sh:452-466`, tests in
`apps/web-platform/test/live-verify/` (`gate.test.ts`), `.github/workflows/web-platform-release.yml` (emit step BLOCK
classification, job `live-verify`), `plugins/soleur/skills/{postmerge,flag-set-role}/SKILL.md`.

**Learnings applied.** Re-derive gate state from the workflow, not the skill. ADR-064 one synthetic principal.
`hr-dev-prd-distinct-supabase-projects`. Raw `createUser` auto-creates org/workspace; WORM audit rows block `deleteUser`.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality | Plan response |
|---|---|---|
| Concierge URL-fetch flow asserted via Sentry/DB (FR2) | Principal key is a decrypt-poisoned dummy; no model turn runs; funded key rejected by CTO | FR2 deferred; OD1 asks the operator to authorise a funded key if wanted |
| CTO option C: post a synthetic bucket via ingest | `egress-audit-ingest.ts` rule 1 rejects non-loopback/proxied requests (401) | Infeasible from CI; dropped |
| Passive read-side probe via follow-through sweeper | Sweeper binds no Supabase service-role/URL, only `SUPABASE_ACCESS_TOKEN`; adding the service role contradicts `I-service-role-bootstrap-only`; probe passes vacuously when the gateway log shows no canary decision; sweeper never escalates a probe that stays NOT-YET; a flag flip does not trigger `live-verify` (diff-triggered) | Deferred to a new issue with these as its prerequisites |
| `--org <synthetic-org>` carries verification | Synthetic principal runs no model turn, so a flag on for that org yields no traffic | Dropped for traffic-dependent flags |
| `postmerge` gate is report-only until #5463 | CI blocking since 2026-06-18 | Fix wording (Phase 3), including the workflow step name at `web-platform-release.yml:1976` |
| Article 30 lacks the synthetic principal | Register lines 57, 232 already name `live-verify@soleur.ai`, `seed-live-verify-user.sh`, ADR-064; only `seed-qa-user.sh` is absent | Phase 1.3 narrowed to `seed-qa-user.sh` |
| New `runner.test.ts` beside the scripts | vitest `unit` project includes only `test/**` and `lib/**` | Tests go in `apps/web-platform/test/live-verify/gate.test.ts` |
| `CANT-RUN` blocks | The emit step sets `BLOCK=0` for CANT-RUN, so a safety breach would fail open | `cannot-spend-violated` gets explicit `BLOCK=1` (Phase 2.3) |

## Open Decisions (operator authorisation)

- **OD1 — Active Concierge traffic in prod.** A funded, spend-capped Anthropic key in the principal's `api_keys` row would
  let Soleur drive a real Concierge turn through Playwright (the original ask). CTO rejected it for v1: it breaks
  I-cannot-spend, a model turn is non-deterministic, and prompts reach Anthropic (CLO). Authorising it means a new key mint
  (operator-only), a separate ADR and CLO sign-off. Without it, traffic-dependent flags are verified only after deferred work.
- **OD2 — Rollback and flip stay operator-typed** (ADR-249; migration tracked #9387). The goal is "no verification
  hand-off", not "no flip hand-off". The flip still gates PR-ready under `wg-block-pr-ready-on-undeferred-operator-steps`.

## Implementation Phases

### Phase 1 — Records

- 1.1 Amend `ADR-064` via `soleur:architecture`: add `I-cannot-spend` (every `api_keys` row for the principal equals the
  sentinel across all providers; no `byok_delegations` row; zero rows fail closed), `I-no-model-turn-in-prod`,
  `I-egress-not-attested-by-gate` (the gate does not attest Squid `%un` attribution or the real CONNECT path), a one-paragraph
  `qa-fixtures` contract sketch (non-prod-only for extra personas; `I-allowlist` stays exactly one prod principal), and a note
  that an agent-filed tracker is a repo write, not a prod write.
- 1.2 Article 30: add `seed-qa-user.sh` to the synthetic-principal rows; run `soleur:gdpr-gate`.
- 1.3 C4: read `model.c4`, `views.c4`, `spec.c4`; edit only if an element or edge is missing; run `c4-code-syntax` and `c4-render`.

### Phase 2 — I-cannot-spend gate

- 2.1 Inside `verifyPrincipal` (`run.ts`), before the browser launch and also under `--dry-run`: read all of the principal's
  `api_keys` rows and any `byok_delegations` rows through its own RLS session; require each key row to equal the seed sentinel
  literals (`encrypted_key = "live-verify-dummy-not-real"` plus the seed's fixed `iv`/`auth_tag`).
- 2.2 Never log row contents; add the ciphertext fields to `redact.ts`.
- 2.3 Workflow emit step: classify `CANT-RUN:cannot-spend-violated` as `BLOCK=1` (a safety breach, unlike the environmental
  CANT-RUNs) and rename the step "(report-only)" at `web-platform-release.yml:1976`.
- 2.4 Tests first, in `apps/web-platform/test/live-verify/gate.test.ts`: non-sentinel anthropic row, extra-provider row,
  delegation row present, zero rows, dry-run still checks.

### Phase 3 — Skill corrections

- 3.1 `postmerge/SKILL.md` (lines 239, 376, 387-393, 593, 620): state the gate is blocking, cite the "Enforce live-verify gate"
  step, keep `DELEGATED-TO-LIVE-VERIFY`.
- 3.2 `flag-set-role/SKILL.md`: replace any operator-session verification hand-off with the ladder: (1) LLM-free behaviour in
  trigger paths is covered by the blocking live-verify gate; (2) traffic-dependent behaviour: the agent files a tracker issue
  naming the missing capability (OD1 / deferred passive path) and does not ask the operator to start a session; (3) genuinely
  operator-only set stays CAPTCHA, credential entry, 2FA, payment, admin-scoped mint, and the typed-yes flip itself.
- 3.3 Grep ADR-064 and the skills for `report-only|REPORT-ONLY`; each hit is decided.

### Phase 4 — Tracking

- 4.1 Passive-verification issue filed: #10461 (read-only credential path, positive observation, deadline escalation, post-flip trigger).
- 4.1b OD1 filed as #10460 (operator chose to pursue a funded prod key as a separate brainstorm after this PR merges).
- 4.2 Comment on #10450: runner/`flows/` split when flow #2 exists, contract ADR, and the dev/staging measurement question.

## Files to Edit

- `apps/web-platform/scripts/live-verify/run.ts`
- `apps/web-platform/scripts/live-verify/redact.ts`
- `apps/web-platform/test/live-verify/gate.test.ts`
- `.github/workflows/web-platform-release.yml`
- `plugins/soleur/skills/postmerge/SKILL.md`
- `plugins/soleur/skills/flag-set-role/SKILL.md`
- `knowledge-base/engineering/architecture/decisions/ADR-064-live-production-verification-harness.md`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (only if the C4 read finds a gap)

## Files to Create

None.

## Open Code-Review Overlap

None (re-run `gh issue list --label code-review` and match the file list above before work).

## Acceptance Criteria

- [x] `verifyPrincipal` fails for each case in 2.4, including under `--dry-run`: `CANT-RUN:cannot-spend-violated` for a non-sentinel row or an active delegation, `CANT-RUN:cannot-spend-unverified` (BLOCK=0, CTO ruling) for zero rows or an unreadable read.
- [x] The release workflow emit step sets `BLOCK=1` for `cannot-spend-violated` and no step is named "report-only".
- [x] `grep -rniE 'report-only' plugins/soleur/skills/postmerge/SKILL.md knowledge-base/engineering/architecture/decisions/ADR-064-live-production-verification-harness.md` returns only hits that describe history, each reviewed.
- [x] `flag-set-role/SKILL.md` contains the three-step ladder and no instruction to ask the operator to start a live session.
- [x] ADR-064 amendment lands in this PR with the three new invariants and the contract paragraph.
- [x] `seed-qa-user.sh` appears in the Article 30 register; `soleur:gdpr-gate` ran.
- [x] The ADR and skill text state plainly that prod verification does not attest the real CONNECT path and that the flip and rollback stay operator-typed.
- [x] The passive-verification issue exists (#10461) and names its four prerequisites; OD1 is tracked as #10460.
- [x] `python3 scripts/lint-guard-contract.py` passes.

## Test Scenarios

- Anthropic row differs from the sentinel → `CANT-RUN:cannot-spend-violated`, no browser launched.
- A second provider row (`openai`) with a non-sentinel value → same result.
- A `byok_delegations` row exists for the principal → same result.
- Zero `api_keys` rows → fail closed.
- `--dry-run` with a violating row → still reports the violation.

## User-Brand Impact

**If this lands broken, the user experiences:** a deploy verified as green while the live feature is broken, or a release
run reddened by a verifier fault.

**If this leaks, the user's data is exposed via:** a verifier that spends or decrypts a real key, mints or reuses a real
user's session, or persists unredacted prod captures.

**Brand-survival threshold:** single-user incident

## Domain Review

**Domains relevant:** Product, Engineering, Legal

### Product (CPO)

**Status:** reviewed (carried forward from brainstorm)
**Assessment:** Extend, do not add a QA agent. Soleur-own app is v1; user apps wait for demand. Add a roadmap row.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** No model turn in prod; no new prod route; one long-lived org. Plan correction: ingest is loopback-only, so the
CI-posted bucket option is infeasible. Ruled by CTO agent.

### Legal (CLO)

**Status:** reviewed (carried forward)
**Assessment:** Go for Soleur's own app behind ADR-064 guardrails; customer prod needs opt-in and a data-processing agreement;
register line and gdpr-gate before first ship.

### Product/UX Gate

**Tier:** none (no user-facing UI surface)

## Observability

```yaml
liveness_signal:
  what: gate=live-verify Sentry event per triggered release (result=PASS|FAIL|CANT-RUN:<reason>)
  cadence: every release whose diff touches trigger-paths.txt
  alert_target: release run status plus the Sentry gate=live-verify event
  configured_in: .github/workflows/web-platform-release.yml (emit and enforce steps)
error_reporting:
  destination: Sentry (gate=live-verify) and the release run status
  fail_loud: BLOCK=1 on FAIL, on a missing result line, and on cannot-spend-violated fails the release job
failure_modes:
  - mode: principal api_keys or delegation state is not the sentinel
    detection: RESULT CANT-RUN reason=cannot-spend-violated, BLOCK=1
    alert_route: release run red plus Sentry gate=live-verify
  - mode: dry-run skips the check
    detection: gate.test.ts dry-run case
    alert_route: CI unit job red
logs:
  where: GitHub Actions step output plus Sentry events (redacted)
  retention: Actions default plus Sentry project retention
discoverability_test:
  command: python3 scripts/lint-guard-contract.py
  expected_output: lint-guard-contract
```

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-064 via `soleur:architecture` in this PR: prod gate is LLM-free; the principal cannot spend (all providers, no
delegation); egress verification boundary; contract sketch.

### C4 views
All three `.c4` files are read in Phase 1.3. Actors checked: operator (typed flag flips), synthetic principal. Systems checked:
GitHub Actions runner, Sentry, Flagsmith, Anthropic (no prod edge added). Data store: Supabase prod (existing). Access
relationship: runner to deployed app as the synthetic principal (existing). Edit only if an element or edge is missing.

### Sequencing
The ADR text describes the target state now; the parser and passive path ship later (#10450 and the new issue).

## Guard Contract

### Guard 1 — I-cannot-spend gate

**Property.** The harness never launches a browser for a principal whose Anthropic key could decrypt or be delegated.

**Assembly.** The single chokepoint is `verifyPrincipal` (`run.ts` ~318), the only constructor of the branded
`VerifiedPrincipal` that `driveAndVerify` requires. Within it, the assembly is every `api_keys` row for the principal across all
providers (anthropic, anthropic_oauth, openai: migrations 096, 139) plus any `byok_delegations` row (migration 064 own-key
fallback). Members drift (new providers); the all-rows read does not. The read uses the principal's own RLS session, never the
service role.

**Mutation matrix.**

| # | Mutation (must go RED) |
|---|---|
| 1 | Make the anthropic row non-sentinel: gate returns `CANT-RUN:cannot-spend-violated` |
| 2 | Add a second-provider row after a compliant anthropic row: gate still fails (a check that stops at the first row is the class) |
| 3 | Add a `byok_delegations` row for the principal: gate fails |
| 4 | Make the read return zero rows: gate fails closed, not PASS |
| 5 | Run with `--dry-run`: the check still executes |

**Harness rows.** Edit the suite so a violating fixture expects `PASS`: the suite must go RED. Must-PASS input that is not the
canonical: a sentinel row with all fields equal to the seed literals but a different row id and `created_at`.

**Anchor.** A real encrypted key can never equal the plaintext literal `live-verify-dummy-not-real`, so weakening the stored
value cannot make a funded key pass; only removing the compare can, and mutation 1 catches that. The BLOCK=1 classification in
the workflow is independent of the harness code, so removing the harness check alone still leaves a missing RESULT line, which
already blocks.

## Scope Check

| Ask | Plan item |
|---|---|
| Soleur performs live tests itself, not via the operator | Phase 3 ladder; OD1 for real traffic |
| Autonomously create a test org | Reconciled: one long-lived org in prod (ADR-064); fresh orgs in dev (#10450); not v1 |
| Applies to all Soleur users | Contract paragraph in the ADR; parser deferred (#10450) |
| Consider a QA agent | Cut with reason |
| Update workflow gates, skills, rules | Phase 3; no AGENTS rule change (domain-scoped, placed in skills) |

No `inferred` items.

## Plan Review Revisions

Five agents reviewed v1 (DHH, Kieran, simplicity, architecture, spec-flow). Simplification and correctness panels both fired on
the runner, floor and passive-probe scope, so those were deleted rather than fixed.

- Mechanical, applied: tests moved to `test/live-verify/`; Article 30 premise corrected; chokepoint named as `verifyPrincipal`;
  BLOCK classification for `cannot-spend-violated`; all-provider and delegation coverage; ciphertext added to `redact.ts`; stale
  workflow step name added to Files to Edit; merge-base CI anchor, Guard 2 and the contract ADR dropped.
- User-Challenge, surfaced to the operator: the Concierge URL-fetch flow, the runner split and the passive probe were all in the
  brainstorm scope the operator chose; v1 now excludes them. OD1 is the decision that restores real-traffic verification.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty fails `deepen-plan` Phase 4.6; this one is filled.
- The ingest route is loopback-only; "post a bucket from CI" fails at rule 1 with a 401.
- The release `live-verify` job is diff-triggered: a flag flip never triggers it.
- `unit` vitest includes only `test/**` and `lib/**`; a test beside the script is never run.
- ADR ordinal and any new numbering are provisional; re-check against `origin/main` at ship.
