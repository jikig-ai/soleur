---
title: "Promote encryption-posture Layer A repo-sweep to a required check (measure-then-arm)"
issue: 6901
branch: feat-one-shot-6901-encryption-posture-required-check
date: 2026-07-24
type: feat
lane: cross-domain  # no spec.md present — defaulted to cross-domain (fail-closed)
brand_survival_threshold: none
verdict: DEFER-ARM  # measurement below threshold; stand up the standalone context to soak, arm in a tracked follow-up
adr: ADR-140 (amended by this PR)
deepened: 2026-07-24  # architecture-strategist + code-simplicity + spec-flow review applied
---

# Promote encryption-posture Layer A repo-sweep to a REQUIRED check — measure-then-arm

## Deepen-Plan Revisions (2026-07-24)

Three review agents (architecture-strategist, code-simplicity-reviewer, spec-flow)
reviewed this plan. Applied:

- **R1 (simplicity + spec-flow) — CUT the soak follow-through probe.** The
  original plan enrolled a `scripts/followthroughs/*.sh` probe. Both reviewers
  showed it is degenerate: arming is a 4-file byte-consistent coupling + a
  terraform apply that the sandboxed sweeper substrate *cannot* author (only
  `contents:read`+`issues:write`, path-restricted), so the probe never *drives*
  arming — its exit-0 only self-closes *after* a human/agent already armed. It
  would post a daily "### Sweeper run: FAIL" comment for 1–3 weeks that masks the
  one ready-flip day (cry-wolf), and its exit-0 query risks a permanent-TRANSIENT
  permission trap. **Replaced with** a plain tracking issue carrying a runnable
  re-eval one-liner. The architecture reviewer's "keep it (never-defer mandate)"
  was overridden: `wg-when-deferring-a-capability-create-a` mandates a tracking
  *issue* + re-eval criteria, not a probe, and arming is *engineering* work, not
  a non-technical-founder operator action, so never-defer-operator-actions does
  not apply.
- **R2 (simplicity) — defer the exact N.** "20 consecutive green + reset-on-any-
  red" on a *whole-repo* drift-sensitive sweep may never converge. Replaced the
  hard number with a directional criterion; the exact N is set at arm time when
  false-positive behavior can actually be observed. Removed the number from the
  ADR amendment (an ADR records decision *shape*, not a tunable).
- **R3 (architecture) — refreshed the stale measurement prose.** `51d2646bc` is
  no longer HEAD of `origin/main` (main advanced). The load-bearing argument is
  "the standalone context has 0 runs," which is independent of merge count.
- **R4 (architecture) — named the direct precedent.** Phase 1 mirrors the
  `credential-path-guard` extraction from this *same* `lint-bot-statuses` job
  (#6882, `ci.yml:148-156`). Advisory-job shape precedent is
  `lint-conversations-update-callsites` (NOT `service-role-allowlist-gate`, which
  is a *required* check).
- **R5 (spec-flow) — recorded a residual risk:** the canonical-parity test
  validates internal agreement, *not* that 15368 is the correct id — a future
  arming PR that consistently used the wrong non-15368 shape in both files would
  pass parity and only wedge live. Carried into the arming issue + Sharp Edges.

## Overview

Issue #6901 asks to promote the encryption-posture **Layer A repo-sweep**
(`python3 scripts/lint-encryption-posture.py --repo-sweep`, ADR-140) from an
**advisory** CI step to a **required** branch-protection check. The issue is
explicit that this is **measure-then-arm**: arm only if the advisory job has run
GREEN for N consecutive PRs; otherwise **DEFER** and document the shortfall,
because a repo-sweep required check runs on *every* PR — a false positive would
wedge unrelated work (`Expected — Waiting`) across the whole repo.

**Measurement verdict: DEFER arming.** The load-bearing measurement is not the
merge count but the *existence of an attributable check-context*: the promotion
target — a **standalone `encryption-posture` check-context** — **does not yet
exist**. The sweep is a `run:` step buried inside the shared advisory
`lint-bot-statuses` job (`.github/workflows/ci.yml:185`, alongside
`lint-trap-tempfile-ownership`, its ratchet, and `lint-orphan-test-suites`), so
that job's green/red status is polluted by three unrelated advisory siblings and
carries **zero attributable green-streak signal** for the sweep. Standing up the
standalone context (Phase 1) is the *first* thing that makes any streak
measurable; it starts at **0 runs**, so any threshold N ≥ 1 is unmet by
construction. (The advisory step itself only merged 2026-07-24 09:15 UTC in
`51d2646bc` / PR #6885 — hours ago — so even the buried-step signal has no soak.)
Phase 0.1 re-measures at /work time.

So #6901 does the minimal DEFER: it **stands up a clean, standalone,
still-advisory `encryption-posture` job** (site 1 — the arm-time required-check
artifact, extracted now so it begins to soak and so the eventual arm is a pure
four-site byte-coupling over an already-de-risked context), **files an arming
tracking issue** carrying the corrected recipe + a runnable re-eval criterion,
and **amends ADR-140** (stale on the edit count and silent on the integration_id
shape). Sites (2)–(5) + test MB-10 are **deferred** to the mechanical arming PR.
Extracting the job now is parity-safe and non-arming (absent from all four
required-check SSOTs — AC2/AC3); the direct in-job precedent is
`credential-path-guard`, extracted from this *same* `lint-bot-statuses` job to a
standalone top-level job in #6882 (`ci.yml:148-156`).

This is the ADR-117 measure-then-arm pattern applied to a CI coupling: **stand
up the probe unarmed, let it soak, arm later** — never arm an unmeasured gate.

## Research Reconciliation — Issue Premise vs. Codebase Reality

| Issue claim / prescription | Reality (verified this session) | Plan response |
|---|---|---|
| "advisory **job** … has run GREEN for N consecutive PRs" — measure it | It is an advisory **step** inside the shared `lint-bot-statuses` job (`ci.yml:185`), not its own job. There is **no standalone context** to measure — the job status is polluted by 3 sibling advisory steps. | Extract to a standalone advisory `encryption-posture` job **now** (site 1) so the soak has a clean, attributable signal. |
| Green streak sufficient to arm? | The standalone context has **0 runs** (it does not exist yet). The advisory step merged hours ago. | **DEFER.** Threshold unmet by any N ≥ 1. |
| Site (2): "use CodeQL's shape: OMIT the name … and pin a **non-15368** integration_id" | **This shape wedges every PR.** A ci.yml `run:` job posts its check-run via the GitHub Actions app (`integration_id 15368`, `action.yml:6,277`). A `required_check` pinned to a *non*-15368 id is satisfied only by a check-run from that other integration — which never appears — so GitHub holds the PR at `Expected — Waiting` forever. This is the CodeQL match mechanism **in reverse** (`required-checks.txt:26–34`: a 15368 synthetic named `CodeQL` does not satisfy the 57789-pinned `CodeQL`). | **Correct the recipe:** 15368 + **ADD** the name to `required-checks.txt`, with the bot action fabricating a *sound-by-unreachability* green (the `rule-body-lint` / `sentry-destroy-required` precedent). Verified: the sweep scans only `*.tf` (`lint-encryption-posture.py:116`) + infra dirs (:129) + the ledger — disjoint from the action's `ALLOWED_PATHS = {weakness-digest.md, rule-metrics.json}` (`action.yml:161-164`), so a bot PR's real sweep verdict == main's. |
| ADR-140: "promoted … via **three** coupled edits" (line 123) | The #6049 drift-proof chain makes it **five** sites: the three **plus** `ci-required-ruleset-canonical-required-status-checks.json` (parity SSOT) **plus** `.github/actions/bot-pr-with-synthetic-checks/action.yml` (synthetic adjudication), bound byte-for-byte by `required-checks-canonical-parity.test.sh`. | **Amend ADR-140** in this PR (Phase 2): 3→5 edit count + the 15368-not-CodeQL shape. |
| "five-site byte-consistent coupling" | Correct as the **arm-time** recipe. With site (1) landing now, the arm-time coupling is **four** sites (2)–(5) over an already-stable, already-soaking context. | Arm-time recipe documented in the tracking issue (canonical); Phase 5 here is the source + the load-bearing corrections. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is a
CI/branch-protection tooling change with no user-facing surface. The failure
mode of *premature arming* is a wedged PR queue (`Expected — Waiting` on every
PR), which halts **engineering velocity**, not a user-facing artifact.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no user
data, secrets, or PII are read, written, or transported by this change.

**Brand-survival threshold:** `none` — reason: CI gate tooling; touches
`.github/workflows/ci.yml` (advisory job), an ADR amendment, and a tracking
issue. No sensitive path (per preflight Check 6 regex — `ci.yml` contains no
`doppler|secret|token|deploy|release|…` filename token), no user data, no
user-facing artifact. The encryption-posture *feature* protects users at
aggregate scale, but **this promotion PR** landing broken is a dev-velocity
concern, not a single-user incident.

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

- [ ] 0.1 Re-measure the standalone-context streak: it is 0 until site 1 lands.
  Confirm no sibling PR has already split the sweep out of `lint-bot-statuses`
  (`grep -n 'Encryption posture — Layer A repo-sweep' .github/workflows/ci.yml`).
- [ ] 0.2 `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 on
  current HEAD (paste the exit code). A red sweep would soak red and never arm.
- [ ] 0.3 `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`
  GREEN on HEAD (baseline — site 1 must not perturb it; a standalone *advisory*
  job touches none of the required-check parity SSOTs).

### Phase 1 — Site (1): standalone advisory `encryption-posture` job (measurement enablement, NON-arming)

- [ ] 1.1 In `.github/workflows/ci.yml`, **remove** the `Encryption posture —
  Layer A repo-sweep (ADR-140)` step from the `lint-bot-statuses` job.
- [ ] 1.2 Add a new **top-level advisory job** `encryption-posture` (stable
  check-context name = `encryption-posture`) mirroring the shape of the existing
  advisory job `lint-conversations-update-callsites` (`ci.yml:188` — checkout
  `@34e114876b0b11c390a56381ad16ebd13914f8d5`, no path filter since the sweep is
  whole-repo) and the `credential-path-guard` extraction precedent (`ci.yml:148-156`,
  #6882), running `python3 scripts/lint-encryption-posture.py --repo-sweep`.
- [ ] 1.3 Carry forward the ADVISORY/NOT-BLOCKING comment block verbatim and add:
  "Absent from `scripts/required-checks.txt`, the CI-Required ruleset, the
  canonical JSON, and the bot action `CHECK_NAMES` — a PR can merge with it red.
  It exists to SOAK an attributable green streak before promotion (#6901; ADR-117
  measure-then-arm). Promotion recipe: the arming tracking issue + the ADR-140
  Amendment."
- [ ] 1.4 **Non-arming invariant (must hold):** `git grep -n 'encryption-posture'
  scripts/required-checks.txt scripts/ci-required-ruleset-canonical-required-status-checks.json
  infra/github/ruleset-ci-required.tf .github/actions/bot-pr-with-synthetic-checks/action.yml`
  → **only** comment/pointer hits, never a required entry.
- [ ] 1.5 Re-run the parity test (Phase 0.3) — must stay GREEN and its 15368 set
  unchanged (site 1 is provably parity-neutral).

### Phase 2 — ADR-140 Amendment (authored in THIS PR, not deferred — Phase 2.10)

- [ ] 2.1 Add an `## Amendment (2026-07-24, #6901)` section to
  `ADR-140-encryption-posture-as-a-design-time-default.md` recording:
  (a) the promotion is a **five-site** coupling, not three edits — enumerate the
  two omitted sites (canonical JSON + bot action) and the parity test that binds
  them; (b) the arming integration_id shape is **15368 + add-to-required-checks.txt
  + sound-by-unreachability fabrication** (rule-body-lint / sentry-destroy-required
  precedent), **not** CodeQL's non-15368 shape (which wedges); (c) the promotion
  is measure-then-arm — soak the standalone context before arming; the concrete N
  lives in the arming tracking issue, **not** the ADR (a tunable, not a decision
  shape).
- [ ] 2.2 Update the line-123 alternatives-table cell ("three coupled edits") to
  cross-reference the Amendment.

### Phase 3 — Arming tracking issue (deferral bookkeeping — `wg-when-deferring-a-capability-create-a`)

- [ ] 3.1 Verify labels exist (`gh label list --limit 200 | grep -E
  '^(type/security|domain/engineering|priority/p2-medium)\b'`), then `gh issue
  create` titled `encryption-posture: ARM Layer A repo-sweep as required check
  (post-soak, sites 2–5 + MB-10)`, labels `type/security`, `domain/engineering`,
  `priority/p2-medium`, milestone `Phase 4: Validate + Scale`. **Not** labeled
  `follow-through` — there is no probe (R1); the issue is drained by the normal
  labeled-backlog process.
- [ ] 3.2 Issue body = the **canonical** arming recipe (sites 2–5 + MB-10, exact
  bytes, from Phase 5) + the re-eval criterion (Phase 4) + the runnable streak
  one-liner + the R5 residual risk (parity does not validate id-correctness). Use
  `Ref #6901` (not `Closes`) — #6901 closes when this DEFER PR merges; arming is
  separate. The arming PR itself will `Closes` this issue.

### Phase 4 — Re-eval criterion (no automation — R1/R2)

- [ ] 4.1 The arming issue's re-eval criterion is a **runnable one-liner** the
  drainer executes, not a probe:
  `gh run list --workflow=ci.yml --branch main --json conclusion,databaseId --limit 40`
  then inspect the `encryption-posture` job conclusion per run
  (`gh run view <id> --json jobs`). No follow-through script, no sweeper wiring.
- [ ] 4.2 **N — directional, not a hard number (R2):** arm once the standalone
  `encryption-posture` context has been GREEN across a *diverse* set of PRs
  (infra-, migration-, and docs-touching) over roughly **2 weeks**, with **no
  false-positive-attributable red** in the window — a longer soak than ADR-117's
  3-green/3-day because the sweep is *whole-repo* (any ledger/evidence drift trips
  it, so a naive "20 consecutive green" may never converge). Fix the exact N at
  arm time, when false-positive behavior can be observed. State this criterion in
  the arming issue body; do not bake a number into code or the ADR.

### Phase 5 — DEFERRED arming recipe (documented; copied into the Phase-3 issue; NOT executed here)

> The tracking issue holds the **canonical** copy. This section is the source for
> that copy and is NOT executed by #6901. It arms **only after** the Phase-4 soak.
> The check-context name (`encryption-posture`) is already stable + soaking, so
> the arm-time coupling is **four** sites (2)–(5) + MB-10.

- **Site (2) — `scripts/required-checks.txt`:** ADD `encryption-posture` under a
  new tier comment in the "CI Required ruleset" 15368 group. **Not** CodeQL's omit
  shape (see Research Reconciliation). Add a CODEOWNERS-note paragraph (mirroring
  the `rule-body-lint` / `sentry-destroy-required` blocks): the synthetic is
  FABRICATED-NOT-EARNED, sound only while the sweep's scan surface
  (`encryption-posture-ledger.json` + `*.tf`/infra evidence) stays disjoint from
  `ALLOWED_PATHS`; re-derive `ALLOWED_PATHS ∩ SCAN_DIRS` if either moves.
- **Site (3) — `infra/github/ruleset-ci-required.tf`:** add a `required_check`
  block `{ context = "encryption-posture"; integration_id = var.actions_integration_id }`
  (15368, **not** `var.codeql_integration_id`) + a tier comment. **Amend the
  ABI-count comment** (line 18: "the 20 `context` strings" → 21) and note the
  resource grows from 21 `required_check` blocks to 22. Apply path: merge triggers
  `apply-github-infra.yml` (first apply makes it LIVE-required).
- **Site (4) — `scripts/ci-required-ruleset-canonical-required-status-checks.json`:**
  append `{ "context": "encryption-posture", "integration_id": 15368 }`.
  `required-checks-canonical-parity.test.sh` Test 1 asserts set-equality (⊆ **and**
  ⊇) between the 15368 subset here and required-checks.txt — sites (2) and (4) must
  land byte-consistent or Test 1 reds.
- **Site (5) — `.github/actions/bot-pr-with-synthetic-checks/action.yml`:** no
  code edit needed if the fabrication stays sound-by-unreachability — `CHECK_NAMES`
  is DERIVED from `required-checks.txt` (site 2), so adding the name there
  auto-includes it. **Adjudication:** confirm `encryption-posture-ledger.json` and
  the sweep's evidence roots are NOT in `ALLOWED_PATHS`; if a future PR adds any
  encryption-surface path to `ALLOWED_PATHS`, the action MUST first reproduce
  `--repo-sweep` over the bot diff in its Phase-4 ceiling (the `credential-path-guard`
  EARNED pattern). Document the residual in the action.yml comment block.
- **Test MB-10 (arm-time):** a `continue-on-error: true` on the `encryption-posture`
  job must STILL red a known-bad fixture PR. If the promoted job carries job-level
  `continue-on-error: true`, a failing step lets the **job** conclude success, so
  the required check-run goes GREEN and the gate is toothless. MB-10 builds a
  fixture with a deliberately-broken ledger row (evidence that does not resolve)
  and asserts the **required check** reds despite `continue-on-error`. Hence the
  ARMED job must NOT set `continue-on-error: true` at the job level.
- **R5 residual (no CI-time id-correctness check):** `required-checks-canonical-parity.test.sh`
  validates that required-checks.txt and the canonical JSON *agree*, not that 15368
  is the *correct* id for this context. An arming PR that consistently used the wrong
  non-15368 shape in both files would pass parity and only wedge live, post-apply.
  Mitigation: the recipe pins 15368 explicitly; the arming PR must verify with a
  live check after `apply-github-infra.yml` (a real PR reaches the `encryption-posture`
  required check as satisfied, not `Expected — Waiting`).

## Files to Edit (this PR — DEFER)

- `.github/workflows/ci.yml` — remove the step from `lint-bot-statuses`; add the
  standalone advisory `encryption-posture` job (site 1).
- `knowledge-base/engineering/architecture/decisions/ADR-140-encryption-posture-as-a-design-time-default.md`
  — Amendment section (Phase 2).
- `knowledge-base/project/plans/2026-07-24-feat-encryption-posture-required-check-promotion-plan.md`
  — this plan.
- `knowledge-base/project/specs/feat-one-shot-6901-encryption-posture-required-check/tasks.md`
  — task breakdown.

## Files to Create (this PR — DEFER)

- None. (The soak follow-through probe was cut — R1.)

## Files NOT edited this PR (deferred to the tracked arming PR)

- `scripts/required-checks.txt`, `infra/github/ruleset-ci-required.tf`,
  `scripts/ci-required-ruleset-canonical-required-status-checks.json`,
  `.github/actions/bot-pr-with-synthetic-checks/action.yml` — sites (2)–(5),
  gated on the Phase-4 soak.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `ci.yml` has a top-level `encryption-posture` job running
  `python3 scripts/lint-encryption-posture.py --repo-sweep`; the step is **gone**
  from `lint-bot-statuses`. Verify: `awk '/^  encryption-posture:/{f=1} f&&/repo-sweep/{print;exit}' .github/workflows/ci.yml` returns the run line.
- [ ] AC2 — **Non-arming invariant:** `git grep -n 'encryption-posture'
  scripts/required-checks.txt scripts/ci-required-ruleset-canonical-required-status-checks.json
  infra/github/ruleset-ci-required.tf .github/actions/bot-pr-with-synthetic-checks/action.yml`
  returns **zero** required-entry hits (comment/pointer hits only).
- [ ] AC3 — `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`
  is GREEN and its 15368-context set is **unchanged** from HEAD (site 1 is
  parity-neutral); non-vacuity counts stay ≥ 16.
- [ ] AC4 — `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0
  (the standalone job is green on merge — soak starts green).
- [ ] AC5 — `actionlint .github/workflows/ci.yml` passes; extracted `run:` shell
  checked via `bash -c` (NOT `bash -n` on the yml).
- [ ] AC6 — ADR-140 contains an `## Amendment (2026-07-24, #6901)` section stating
  the 5-site count and the 15368-not-CodeQL shape. Verify: `grep -c 'Amendment (2026-07-24, #6901)' ADR-140*.md` == 1. (The section must NOT hard-code an N — R2.)
- [ ] AC7 — The arming tracking issue exists (`gh issue list --search
  'encryption-posture ARM'`), body carries the sites-2–5 recipe + the re-eval
  one-liner + the R5 residual, and references `#6901` via `Ref` (not `Closes`).

### Post-merge

- [ ] AC8 — The standalone `encryption-posture` context appears green on the next
  main push (`gh run view <id> --json jobs | jq '.jobs[]|select(.name=="encryption-posture").conclusion'` == `"success"`) — soak begins. No operator action.

## Domain Review

**Domains relevant:** engineering (CTO)

### Engineering (CTO)
**Status:** reviewed (architecture-strategist + code-simplicity + spec-flow ran in deepen-plan)
**Assessment:** Pure CI/branch-protection tooling + measure-then-arm sequencing.
The load-bearing decisions — DEFER on 0-run measurement, stand up a standalone
advisory context, correct the arming integration_id shape (15368, not CodeQL's
non-15368), and cut the degenerate soak probe — were all reviewed. No other domain
has implications (no user surface, no user data, no vendor/expense).

### Product/UX Gate
**Tier:** NONE — no Files-to-Edit/Create path matches a UI-surface term/glob
(`.github/`, `scripts/`, `knowledge-base/` only). Gate skipped.

## Infrastructure (IaC)

**Phase 2.8 gate: skip.** No new infrastructure (no server, secret, vendor, DNS,
cert, systemd unit, or runtime process). Edits a CI workflow (advisory job) + an
ADR. The **deferred** arming edits `infra/github/ruleset-ci-required.tf` (a GitHub
branch-protection ruleset, applied by `apply-github-infra.yml` on merge) — that
apply path is in the arming recipe and executed in the tracked follow-up, not here.

## Encryption Posture

**Phase 2.11 gate: skip.** This PR introduces no persistent data store and no new
cross-component connection. It touches no `.tf`, migration, cloud-init, or
docker-compose file in this PR. Prose references existing stores only to explain
the encryption-posture *tooling* (a CI gate), not to add a posture-bearing surface.
(The deferred arming's `.tf` edit is a branch-protection ruleset — neither a store
nor a connection — so even that is out of the encryption-posture schema scope.)

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-140** (in this PR — Phase 2): the Layer A promotion is a five-site
byte-consistent coupling (not the three edits line 123 states); the arming
integration_id shape is 15368 + add-to-required-checks.txt + sound-by-unreachability
fabrication (not CodeQL's non-15368 omit shape). No hard N in the ADR (R2). No NEW
ADR ordinal (amendment only).

### C4 views
**No C4 impact.** Checked against `model.c4`, `views.c4`, `spec.c4`. Enumeration:
(a) **external human actors** — none introduced (a CI required check adds no
correspondent/reviewer/recipient); (b) **external systems/vendors** — none (the
gate runs inside GitHub Actions, already modeled by the `github` software system;
no new inbound/outbound edge); (c) **containers/data-stores** — none (`model.c4`
references `encryption-posture-ledger.json` only inside existing *store
descriptions* as ledgered exceptions; this PR adds no store); (d) **access
relationships** — none change (branch-protection is internal to the already-modeled
repo boundary). A CI branch-protection rule is not a C4 element.

### Sequencing
The decision (promote-to-required) is only *true* after the soak; the ADR
Amendment describes the target state and the soak gate. Arming is the tracked
follow-up.

## Observability

```yaml
liveness_signal:
  what: "encryption-posture standalone check-context conclusion on every PR + on main pushes"
  cadence: "per-PR and per-merge (whole-repo sweep, no path filter)"
  alert_target: "advisory — visible in the PR checks list; no page (not yet required)"
  configured_in: ".github/workflows/ci.yml (standalone encryption-posture job)"
error_reporting:
  destination: "GitHub Actions run logs + PR checks UI (job conclusion)"
  fail_loud: "the sweep exits non-zero and reds the advisory job; visible, non-blocking"
failure_modes:
  - mode: "sweep flags a ledger row whose evidence no longer resolves (drift)"
    detection: "encryption-posture job red in the PR checks list"
    alert_route: "PR author sees the red advisory check; the soak window restarts"
  - mode: "soak never converges (recurring reds on a whole-repo sweep) — arming stays deferred"
    detection: "the re-eval one-liner shows non-green encryption-posture conclusions in the window"
    alert_route: "the drainer of the arming issue sees it; N is directional, not auto-gated"
logs:
  where: "GitHub Actions run logs (ci.yml)"
  retention: "GitHub default (90d)"
discoverability_test:
  command: "gh run list --workflow=ci.yml --branch main --json conclusion,databaseId --limit 40   # NO ssh"
  expected_output: "recent runs enumerable; encryption-posture job conclusion inspectable via gh run view <id> --json jobs"
```

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issue whose
title matches the files this plan edits (encryption/required-check/ruleset/ci.yml/
posture).

## Test Scenarios

- T1 — `required-checks-canonical-parity.test.sh` GREEN + 15368 set unchanged
  (site-1 parity-neutrality).
- T2 — non-arming grep (AC2) returns zero required entries.
- T3 — `--repo-sweep` exits 0 on HEAD (soak starts green).
- T4 — `actionlint` on ci.yml passes; the new job's `run:` shell is `bash -c`-valid.
- (deferred, arm-time) MB-10 — `continue-on-error: true` on the job still reds a
  known-bad fixture PR's **required** check.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Site 1 accidentally perturbs the required-check parity set | AC2 + AC3 grep/parity-test invariants; a standalone *advisory* job touches none of the four SSOTs. Precedent: the `credential-path-guard` extraction (#6882) did exactly this move. |
| The follow-up PR encodes the issue's wedge-prone CodeQL shape | Research Reconciliation + ADR-140 Amendment + the canonical recipe pin the 15368 shape; the arming issue body carries the correction + the R5 note that parity does NOT catch a wrong id. |
| Soak starts red (sweep broken on HEAD) → never arms | Phase 0.2 / AC4 gate: `--repo-sweep` must exit 0 before merge. |
| Soak never converges on a whole-repo sweep ("20 consecutive" is unsatisfiable) | R2: directional criterion (no false-positive-attributable red over ~2 weeks of diverse PRs), exact N fixed at arm time. |
| ABI-count comment in ruleset.tf goes stale at arm time (20→21 contexts) | Named explicitly in the deferred recipe (site 3). |

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| **Pure plan-only DEFER PR** (no site 1) | The buried-step signal is polluted by 3 sibling advisory steps — measure-then-arm needs an *attributable* streak. Site 1 is parity-safe, non-arming, and is the arm-time artifact anyway (pre-positions the atomic arm). |
| **Arm now** (issue's happy path) | Measurement is 0 runs; premature arming wedges every PR — the exact risk the issue names. |
| **Arm with the issue's CodeQL shape** (non-15368) | Wedges every PR (`Expected — Waiting`) — the required_check id must match the 15368 posting integration. Corrected in the recipe. |
| **Soak follow-through probe** (original plan) | CUT (R1): the sandboxed sweeper cannot author a 4-file coupling PR + terraform apply, so the probe never *drives* arming — it posts a daily "FAIL" comment that masks the ready-flip and risks a permanent-TRANSIENT permission trap. Replaced by a runnable re-eval one-liner in the tracking issue. |
| **Auto-arm via any GitHub Action** | The arm is a high-blast-radius branch-protection + terraform-apply change; the repo's agent-authored-PR precedent (`fix-constraints-stage-a.yml`) is purpose-built for narrow low-blast-radius lint fixes only. Manual/agent arm via the recipe is the right shape. |

## Deferrals & Tracking

- **Arming (sites 2–5 + MB-10)** → tracked in the Phase-3 issue; re-eval criterion
  = directional soak (Phase 4.2); milestone `Phase 4: Validate + Scale`.
  (`wg-when-deferring-a-capability-create-a`.)

## Sharp Edges

- **The issue's site-2 prescription (OMIT + non-15368 integration_id) is a wedge
  trap** — a ci.yml job posts under 15368, and a `required_check` pinned to a
  non-15368 id is never satisfied by it. The arm-time PR MUST use 15368 +
  add-to-required-checks.txt. This is the CodeQL match-condition mechanism in
  reverse (`required-checks.txt:26–34`).
- **Parity does NOT validate id-correctness (R5).** `required-checks-canonical-parity.test.sh`
  only asserts required-checks.txt and the canonical JSON *agree*; a future arming
  PR that used the wrong non-15368 id in both would pass parity and wedge live.
  The arming PR must verify with a live post-apply check that a real PR reaches the
  `encryption-posture` required check as satisfied.
- **The ARMED `encryption-posture` job MUST NOT carry job-level
  `continue-on-error: true`** — it would let a failing step conclude the job (and
  its required check-run) GREEN, defanging the gate. MB-10 catches exactly this.
- **Do not add any encryption-surface path to the bot action `ALLOWED_PATHS`**
  without first reproducing `--repo-sweep` over the bot diff in the Phase-4
  ceiling — the fabricated green is sound only by unreachability
  (`ALLOWED_PATHS ∩ SCAN_DIRS = ∅`; verified: the sweep reads `*.tf` + infra +
  the ledger, never `weakness-digest.md` / `rule-metrics.json`).
- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails `deepen-plan` Phase 4.6 — this plan's threshold is `none` with a stated
  reason; do not blank it.
