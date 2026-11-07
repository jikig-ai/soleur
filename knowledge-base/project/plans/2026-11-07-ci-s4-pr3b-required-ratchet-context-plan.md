---
title: "ci: S4 PR3b, make the affected-index ratchet a required context"
type: ci
date: 2026-11-07
slug: ci-s4-pr3b-required-ratchet-context
branch: feat-one-shot-10859-pr3b-required-context
issue: 10859
closes: 10859
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# ci: S4 PR3b, make the affected-index ratchet a required context

## Overview

Promote the `affected-index-ratchet` CI job from advisory to a required merge-gate
context, exactly as scoped by issue #10859 and the archived PR3 plan's
"PR3b - make the context required" section
(`knowledge-base/project/plans/archive/20261023-144502-2026-10-22-feat-s4-affected-index-pr3-required-ratchet-plan.md`).

In **one commit**: delete the job-level `continue-on-error: true` in
`.github/workflows/ci.yml` AND enroll the name `affected-index-ratchet` in every
required-context registry — `scripts/required-checks.txt`,
`scripts/ci-required-ruleset-canonical-required-status-checks.json`,
`infra/github/ruleset-ci-required.tf`, the count pin in
`plugins/soleur/test/required-checks-canonical-parity.test.sh`, the
`admin-merge-ready` fixtures, `tests/scripts/test-audit-ruleset-bypass.sh`, and
`scripts/pr-fanout-ledger.txt` — plus a committed bot-synthetic unreachability
assertion. Run `scripts/probe-merge-group-coverage.sh` before merging. Re-examine
draft-light participation with the measured draft-push minutes.

The merge auto-applies the ruleset via `apply-github-infra.yml`; the PR body must
state that and cite the budget-owner go-ahead comment
(https://github.com/jikig-ai/soleur/issues/10859#issuecomment-6710852889,
recorded 2026-11-07T17:45:10Z by deruelle, verbatim: "go ahead for 10859 and
10862").

## Premise Validation

Checked 2026-11-07:

- #10859 OPEN, not closed by any PR; last comment is the go-ahead receipt (above).
- #10865 (PR3a observation-window tracker) CLOSED 2026-11-07T10:12:25Z — entry
  condition (1) met. Entry conditions (2) rename-carry design and (3) the
  continue-on-error canary (PR #10899, run 39937846319) are recorded as met in
  the runbook observation log (`ci-pr-affected-activation.md` §The dark phase).
- All seven named registry files exist on the branch; so do
  `scripts/probe-merge-group-coverage.sh`,
  `.github/actions/bot-pr-with-synthetic-checks/action.yml`, and
  `scripts/required-check-wallclock-bounds.tsv`.
- Collision precheck: PR #12329 names #10859 — it is THIS branch's own pipeline
  draft PR (created 17:47Z, body "WIP"), not a duplicate. One foreign
  `test-all.sh` run in an unrelated worktree (pid 3651465) — unrelated to #10859.
- Corrected premise: the archived plan says the audit's read set is "exposed
  under `--all-refs`". It is NOT — `--all-refs` prints `ref` lines only for GAP
  pairs (files containing undeclared boundary lines), an under-approximation of
  `files_read` (a file read that names only declared paths prints nothing, yet a
  bot edit could add a boundary line to it). The disjointness assertion therefore
  requires a small read-set exposure added to `scripts/ci-pr-affected-replay.py`
  (`audit --print-files-read`), which this plan carries as a justified inferred
  item (see Scope Check).

## Property List (Phase 0.6b)

- P1: `affected-index-ratchet` blocks merge/queue when red — required context in
  the live ruleset after the auto-apply.
- P2: the job can no longer be run-conclusion-green while failing —
  `continue-on-error` deleted.
- P3: every registry that mirrors the required set carries the name in the same
  commit (parity guards stay green).
- P4: a bot-PR synthetic green for the new context is sound by UNREACHABILITY —
  proven by a committed test, not argued.
- P5: every committed consumer that pins the advisory state or the context count
  is updated in the same commit (no suite reds on merge).

## Cut List (Phase 0.6b)

- Draft-light gating of the ratchet (needs: draft-light + if:/step clause) → P? →
  CUT. See "Draft-light re-examination" below: it introduces either a needs edge
  on a required context (a failed/skipped need class the context never had) or a
  fabricated green on drafts — the class P4 exists to police.
- A new standalone `.test.sh` suite for the disjointness check → P4 → cut in
  favor of rows inside already-registered suites (no `scripts/test-all.sh`
  runner-trigger edit needed).
- Editing `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts`
  `SYNTHETIC_CHECK_NAMES` → P4 → deliberately absent, same disposition as the
  umbrella contexts it already excludes: the Inngest crons push with an App token
  that triggers real CI (#8166), so the ratchet check there is EARNED, never
  fabricated.

## Research Insights

- The job (`ci.yml:519-571`): `if: github.event_name == 'pull_request' ||
  github.event_name == 'merge_group'` at 520, `continue-on-error: true` at 521 —
  the single line to delete — plus its advisory comment block at ~505-518 to
  rewrite. The `if:` is already the positive `pull_request || merge_group` form
  `probe-merge-group-coverage.sh` accepts (its own test row 16 proves it).
- `scripts/required-checks.txt` (232 lines): names are parsed as non-comment
  lines before the `# CLA Required ruleset` header; every content-scoped gate
  carries a per-gate justification block (#6049/ADR-139 rule). The new entry
  goes immediately before `# CLA Required ruleset` with an
  `affected-index-ratchet` block modeled on `rule-body-lint` /
  `sentry-destroy-required`: CONTENT-SCOPED, sound by UNREACHABILITY, asserted by
  the new committed test — NOT merely argued (the digest IS named by pairs, but
  as a target, not a reader).
- `scripts/ci-required-ruleset-canonical-required-status-checks.json`: 10
  all-15368 rows → append an 11th `{"context": "affected-index-ratchet",
  "integration_id": 15368}`.
- `infra/github/ruleset-ci-required.tf`: 10 `required_check` blocks (grep -c
  `context *=` = 10) → append an 11th inside `required_status_checks`, with a
  dated #10859 comment; fix the stale header line "the 10 `context` strings
  below" → 11.
- Count pins that will RED if not edited in the same commit:
  - `tests/scripts/test-audit-ruleset-bypass.sh` T-rsc-7: `n == "10"` → `"11"`
    (deliberate literal; comment block above it already records the bump chain).
  - `plugins/soleur/test/required-checks-canonical-parity.test.sh` line ~180:
    `n_ci -ge 10 && n_canon -ge 10` non-vacuity floors → `-ge 11` (this is "the
    count pin" the issue names).
  - `plugins/soleur/test/required-checks-merge-group-coverage.test.sh`: 9
    literal `contexts=12 producers=11` expectations → `contexts=13 producers=12`
    (real-repo rows run against a sandbox copy of the live tree). Its
    `engine_green 12` floors stay ≥ — optionally bump to 13 for consistency.
  - `scripts/probe-merge-group-coverage.sh` `MIN_CONTEXTS_DEFAULT = 12` and its
    "12 = 10 CI + 2 CLA" comment → 13 / "13 = 11 CI + 2 CLA" (deliberate literal
    tracking the real count, same philosophy as T-rsc-7). The issue lists only
    "run before merging" for this file; the floor is a ≥ so it still passes —
    the bump keeps the anti-vacuity floor honest (justified inferred item).
- Advisory-state pins inside `plugins/soleur/test/ci-pr-affected-replay.test.sh`
  that MUST be rewritten (inferred — the issue does not name this file but the
  suite fails otherwise):
  - chk ~2944 `row_wf_coe`: asserts coe present → invert/remove (the biconditional
    `row_wf_bicond` at ~2717 already encodes "coe IFF not required" and stays
    green once both arms land).
  - chk ~2949 `row_wf_dark`: asserts the name absent from required-checks.txt →
    rewrite as a `row_wf_required` (name present, coe absent) or fold into the
    biconditional.
  - chk ~2954 `row_wf_dark_mutant` and ~2955 `coe-gone` wf_mut rows reference the
    deleted line/advisory shape → rewrite mutants against the required-state
    baseline (e.g., a mutant that re-adds coe while the name IS required must
    red the biconditional).
  - `row_wf_required_not_coe` floor `mapped >= 3` → the ratchet becomes the 4th
    mapped required ci.yml job (test, e2e, guards-ruleset + it) — keep or bump
    to 4.
- `admin-merge-ready` fixtures (`plugins/soleur/test/fixtures/admin-merge-ready/`):
  `rules-branches-main.json` ruleset 14145388 holds 11 contexts today
  (deliberately the PRE-adoption capture including `CodeQL`; README documents
  this) → append `affected-index-ratchet` to its `required_status_checks`;
  `check-runs.json` → append one green run `{name: affected-index-ratchet,
  head_sha: <fixture SHA 319c22bf…>, status: completed, conclusion: success,
  app: {id: 15368}, check_suite: {id: <consistent>}}`; README gets a dated
  2026-11-07 (#10859) note line like the #12276 one.
- `scripts/required-check-wallclock-bounds.tsv`: REQUIRED row — the TSV header
  itself states "a required context with no row here is itself a ratchet
  finding", and `scripts/watch-wallclock-p90-11774.sh` emits an `unbound`
  finding per missing row. Seed bounds from the job's measured wall clock
  (p95 240 s / max 285 s execution + acquisition): `affected-index-ratchet`
  420 / 420 / 0.30 is the conservative seed — the implementer should verify with
  `watch-wallclock-p90-11774.sh --dry-run` and round UP to the next minute per
  the file's seeding method (inferred item — the issue does not name it, the
  probe's own contract does).
- `scripts/pr-fanout-ledger.txt` ci.yml row: append a dated clause —
  "2026-11-07 PR3b (#10859): affected-index-ratchet's context became required
  (continue-on-error removed; job count unchanged at 21)". The jobs column is a
  declared-count ceiling and does not move.
- The audit read set: `files_read` = distinct real files in `index.raws` —
  suite input files (`suite_inputs`/`reach_texts`) plus their `source` closure
  to HOP_DEPTH. `knowledge-base/project/weakness-digest.md` is named BY 2 gap
  pairs and a data file as a *target* string; it is not a suite input and
  cannot be a `source` operand, so it is essentially certain NOT to be read —
  but "essentially" is what the committed test exists to prove, because reach
  widens silently.
- Draft-light facts (for the re-examination): `CI_DRAFT_LIGHT` repo variable is
  `on` (set 2026-10-11); `draft-light` job `if:` is pull_request-only, so it is
  skipped on merge_group; the gated-set shape is `needs: [push-dedupe,
  draft-light]` + `&& needs.draft-light.outputs.light != 'true'` enforced both
  directions by `scripts/ci-draft-light.test.sh` (`LIGHT_PINNED` already
  contains `affected-index-ratchet` in the ungated/light set). Runbook measured:
  ~3.4 billed min/run, ~4,400 min/wk total, ~2,250 min/wk on draft pushes
  (~+11% per draft push); p95 240 s / max 285 s wall (re-ruled final
  2026-11-03).
- Institutional learnings applied:
  - `2026-03-20-github-required-checks-skip-ci-synthetic-status.md` and
    `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md`: a required
    context needs the `merge_group` producer (present) and a synthetic for bot
    PRs (the composite action derives CHECK_NAMES from required-checks.txt —
    enrollment auto-covers it, and the unreachability test proves the green is
    sound).
  - ADR-032 paired-edit contract: the context name and the ruleset row land in
    the same commit — satisfied by the one-commit rule.
  - `2026-09-23-non-required-did-not-mean-decoupled-…`: "non-required" only
    governs the merge gate — the registries being enrolled are exactly the gate.

## Draft-light re-examination (recorded decision)

Measured inputs: `CI_DRAFT_LIGHT` is `on`; the job costs ~3.4 billed min/run;
runbook attributes ~2,250 billed min/week to draft pushes (~51% of the job's
~4,400).

Options weighed:

- **A — stay ungated (LIGHT_PINNED), run on every draft push.** Cost: ~2,250
  min/wk. The required context posts a real verdict on every push.
- **B — join the gated set** (`needs: [draft-light]` + `&&
  needs.draft-light.outputs.light != 'true'` on the job `if:`): skips the check
  on light draft runs. Defects: (i) a needs edge on a REQUIRED context adds a
  skipped/failed-need class it has never had — a draft-light failure on a
  pull_request run skips the ratchet → required context pending → merge blocked
  until re-run (the #5780 stall class, just smaller); (ii) breaks the
  `row_wf_no_needs` pin and puts the lever's liveness on the merge critical path.
- **C — step-level gate** (`needs: draft-light` + step `if:`): the job still
  starts, skips the audit, posts GREEN on a light draft run — a fabricated
  green from a required context, the exact class the unreachability assertion
  exists to police; dishonest telemetry on ~2,250 min/wk of runs.
- **D — event-payload draft flag in the job `if:`**: rejected by the draft-light
  design itself (re-runs reuse stale payloads; a stale `draft=true` on a
  now-ready PR would leave the required context unreported).

Ruled by planning agent, 2026-11-07 (no Task tool in this environment — could
not spawn soleur:engineering:cto; recorded for pipeline review): **Option A —
the job stays in `LIGHT_PINNED`, ungated.** The ratchet is not one of the "four
heavy families" the lever exists to skip; options B–D each buy ~2,250 min/wk at
the price of a merge-gate or telemetry defect. Revisit path: a dedicated issue
if the budget owner wants the ~2,250 min/wk back (the change is mechanical but
touches a required context's needs graph).

## User-Brand Impact

- **If this lands broken, the user experiences:** every open PR's merge gate
  stalls or reds — a required context that never reports (if the merge_group
  producer broke) or blocks everything (if the ratchet reds spuriously). For the
  plugin's end users, nothing directly — this is the repo's own merge gate.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  user data path — the change is repo-internal CI/ruleset configuration. Hosted
  runner spend is the money vector (a required job runs on every PR + queue
  entry, ~3.4 billed min each — the budget-owner go-ahead covers it).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal merge-gate configuration with
  no user-facing surface; a defect costs developer throughput and runner
  minutes, not user trust.
- `threshold: none, reason: the diff touches .github/workflows/, infra/github/,
  scripts/ and test files — repo-internal CI infrastructure only, no
  user-facing or regulated-data surface.`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (CI
required-context enrollment). The mechanical UI-surface scan over Files to
Create/Edit finds no `components/**/*.tsx`, `app/**/page.tsx`, or UI-surface
path, so the Product/UX gate does not fire.

## Infrastructure (IaC)

The change to `infra/github/ruleset-ci-required.tf` is an amendment to an
EXISTING Terraform root — no new resource, server, secret, or vendor.

### Terraform changes

- `infra/github/ruleset-ci-required.tf`: one new `required_check` block
  (`context = "affected-index-ratchet"`, `integration_id =
  var.actions_integration_id`) inside the existing
  `required_status_checks` rule of `github_repository_ruleset.ci_required`, plus
  a dated comment and the stale "10 `context` strings" header fix → 11.

### Apply path

- Automatic: `apply-github-infra.yml` fires on merge (paths:
  `infra/github/*.tf`) — a whole-payload ruleset replace that ADDS one
  `required_check` (no destroy; the `[ack-destroy]` merge-message ack is NOT
  required — it guards nested-block removals).
- Verification: the workflow's pre-apply by-value gate compares planned
  bindings with the committed canonical JSON; post-apply it re-reads the live
  ruleset. Operator-visible drift check before merge: read the live ruleset's
  `bypass_actors` and `conditions` before and after apply (the parent plan's
  instruction — folded into the ship checklist, not an operator step).
- Kill switch: `[skip-github-apply]` on its own line in the merge commit
  message skips the auto-apply (use only for a deliberately deferred apply).

### Distinctness / drift safeguards

- Canonical JSON ↔ tf parity is CI-enforced (T-rsc-9 in
  `tests/scripts/test-audit-ruleset-bypass.sh`), so both must land in this
  commit — an apply with mismatched canonical would flag `removed` drift in the
  daily ruleset audit.

## Observability

```yaml
liveness_signal:
  what: the `affected-index-ratchet` check itself — required context green/red per PR and merge_group run; the daily `scheduled-ruleset-bypass-audit.yml` verifies live ruleset == canonical JSON
  cadence: per-PR/per-queue-entry (the check); daily (the audit)
  alert_target: the PR's check list + queue entry state (check); `ci/auth-broken` issue label from the audit (audit)
  configured_in: .github/workflows/ci.yml (job), infra/github/ruleset-ci-required.tf (requirement), .github/workflows/scheduled-ruleset-bypass-audit.yml (drift audit)

error_reporting:
  destination: the check's ::error annotation `exit=<1|2> reason=<token>` in the job log + `### affected-index-ratchet` step summary
  fail_loud: a required-context red blocks merge — the failure IS the loud signal; a context that never reports surfaces as `Expected — Waiting` (queue stall) caught by merge-queue-stall-check.yml

failure_modes:
  - mode: context required in files but absent from live ruleset (apply failed or skipped)
    detection: daily ruleset-bypass audit + apply-github-infra.yml post-apply verify step
    alert_route: ci/auth-broken issue via the audit
  - mode: bot PR fabricates a green over a reachable surface (ALLOWED_PATHS widened to an audit-read file)
    detection: the new committed unreachability test (files-read disjointness)
    alert_route: CI red on the widening PR — before merge
  - mode: required context with no merge_group producer (queue pends forever)
    detection: scripts/probe-merge-group-coverage.sh run pre-merge + its committed suite
    alert_route: pre-merge probe + required-checks-merge-group-coverage.test.sh

logs:
  where: the job log + step summary on each ci.yml run; apply log inside apply-github-infra.yml runs
  retention: GitHub Actions retention (org default)

discoverability_test:
  command: bash scripts/probe-merge-group-coverage.sh
  expected_output: merge-group-coverage=OK
```

## Encryption Posture

```yaml
at_rest:
  mechanism: none — the diff introduces no persistent data store (a GitHub ruleset amendment is configuration, not storage); the Terraform state for this resource already lives in the established backend per infra/github/
  evidence: infra/github/ruleset-ci-required.tf contains no store resource
  defends_against: n/a
  does_not_defend: n/a — no new store
  disclosed_as: n/a
  live_verification: n/a
in_transit:
  mechanism: the ruleset change reaches GitHub via the Terraform provider's authenticated HTTPS API under apply-github-infra.yml — TLS with cert verification on (provider default); no new cross-component connection is created
  cert_verification: on
  does_not_defend: a compromised runner/App token could apply a different payload — bounded by the pre-apply by-value gate and the post-apply verify step
  disclosed_as: n/a
exception: absent — no plaintext mechanism, cert verification on
```

## Task Design

Not applicable — no new autonomous-task surface (no new workflow, cron, timer,
or registered check beyond an enrollment in an existing one).

## Architecture Decision (ADR/C4)

The promotion decision was already made and recorded (ADR-276 amendment
2026-10-22, S4 PR3a → PR3b staging; the staged ratchet shape ruled by the CTO).
This plan EXECUTES a recorded decision; it makes no new architectural decision.

- `### ADR` — amend, not create: append a dated line under ADR-276 `### Stage
  status` — "2026-11-07 PR3b (#10859): `affected-index-ratchet` became a
  required context (continue-on-error removed; ruleset applied via
  apply-github-infra.yml)". Consistent with the series' dated-line convention.
- `### C4 views` — **no C4 impact.** Enumerated per the completeness mandate:
  (a) external human actors: none new — the actors are PR authors and the merge
  queue, both already modeled; (b) external systems: GitHub Actions/rulesets
  API — already modeled as the CI infrastructure this series documents; (c)
  containers/data stores: none touched (no new store — see Encryption
  Posture); (d) access relationships: none change (the merge gate's shape is
  recorded in ADR prose, not C4 edges). model.c4, views.c4, spec.c4 all checked:
  no element names `affected-index-ratchet`, `required-checks`, or
  `ruleset-ci-required` — the C4 model does not render per-context CI detail.
- `### Sequencing` — n/a (the stage-status line is the record).

## Guard Contract

The deliverable includes one new assertion-based check (the bot-synthetic
unreachability assertion) plus the enrollment of an existing check as required.

### Guard 1 — bot-synthetic read-set disjointness (`affected-index-ratchet` green is sound by unreachability)

**Property.** No path the bot composite action may stage (`ALLOWED_PATHS` in
`.github/actions/bot-pr-with-synthetic-checks/action.yml`) is a file whose
content the audit reads, so a bot PR cannot change the ratchet's verdict and a
synthetic green asserts something true.

**Assembly.** Two inputs, both derived not enumerated: (a) `ALLOWED_PATHS`
parsed out of action.yml's array literal (the chokepoint every bot-staged path
must pass — the action exits 1 on any path outside it); (b) the audit's
files-read set = `index.raws` keys after `audit_census` — suite inputs plus
their `source` closure to HOP_DEPTH — exposed by the new
`audit --print-files-read` flag in `scripts/ci-pr-affected-replay.py` (added in
this PR because `--all-refs` exposes only gap-pair ref lines, an
under-approximation of files read: a file read that names only declared paths
prints nothing yet can gain a boundary line by edit).

**Mutation matrix** (each must drive the guard RED):

| # | Mutation | Why it must red |
|---|----------|-----------------|
| 1 | Append a suite input file (e.g. `scripts/ci-pr-affected-replay.py` or any file the census reads) to the ALLOWED_PATHS array | a member of the read set becomes bot-writeable → fabricated green over reachable surface |
| 2 | `--print-files-read` prints an empty/degenerate set (exposure broken: flag wired to a stub) | anti-vacuity floor on read-set size fails (read set is ~950 files today; floor ≥ 500) |
| 3 | required-checks.txt gains the name while canonical JSON does not (or vice versa) | the existing parity guard (Test 1, required-checks-canonical-parity.test.sh) reds — the enrollment's set-equality chokepoint |
| 4 | The unreachability justification block deleted from required-checks.txt while the name remains | the justification-presence anchor in the test's required-checks section must red (mention alone is not the assertion — the test also re-derives the disjointness live) |

**Harness rows.**

- RED-on-suite: a harness mutation that strips the `!= 'true'` … no —
  concretely: a mutant `audit --print-files-read` printing the literal string
  `ALLOWED_PATHS` member among its lines MUST red (the test greps intersection,
  not exit code).
- Must-PASS non-canonical: ALLOWED_PATHS = `{weakness-digest.md,
  knowledge-base/project/learnings/some-new-file.md}` where the added file is
  also outside the read set → still GREEN (the contract permits widening to any
  non-read path).
- Must-PASS canonical: today's real tree — digest not read → GREEN.

**Anchor.** The guard compares a live census output to the action's array —
both in this commit's tree; the weakening that escapes one diff (ALLOWED_PATHS
gains a read file) is caught because the read set is re-derived per run, never
pinned to a stored list. The `files_read ≥ 500` floor is set-identity-backed by
the census's own `files_read` count (the test asserts the printed list length
≥ floor AND each member is a tracked path under the root).

### Guard 2 — required-context registry parity (pre-existing, exercised)

Not new — asserted via ACs: canonical JSON ↔ required-checks.txt ↔
ruleset-ci-required.tf ↔ merge_group producer ↔ wallclock bounds row ↔
admin-merge-ready fixtures all carry the name in this commit (the parity guards
above are the enforcement).

## Scope Check

### Ask Mapping

| Issue-asked item | Plan item |
|---|---|
| delete job-level `continue-on-error` in ci.yml | Phase 1, Files to Edit #1 |
| add name to `scripts/required-checks.txt` | Phase 1, #2 (with justification block) |
| add name to canonical JSON | Phase 1, #3 |
| add name to `infra/github/ruleset-ci-required.tf` | Phase 1, #4 |
| count pin in `required-checks-canonical-parity.test.sh` | Phase 1, #5 (`-ge 10` → `-ge 11`) |
| admin-merge-ready fixtures | Phase 1, #6 (rules + check-runs + README note) |
| `tests/scripts/test-audit-ruleset-bypass.sh` | Phase 1, #7 (T-rsc-7 `10` → `11`) |
| `scripts/pr-fanout-ledger.txt` | Phase 1, #8 (dated clause; count unchanged) |
| bot-synthetic unreachability assertion | Phase 2 (flag + committed test) |
| run `probe-merge-group-coverage.sh` before merging | Phase 4 (pre-merge gate + AC) |
| re-examine draft-light participation | Draft-light re-examination (ruled: stay ungated) |
| PR body states auto-apply + cites go-ahead | Phase 4 / AC |

### Plan-Item Provenance

| Item | Provenance | Justification |
|---|---|---|
| Files #1-#8, #11 (assertion), pre-merge probe, draft-light re-exam, PR-body requirements | asked | direct map from issue #10859 + archived plan PR3b section |
| `plugins/soleur/test/ci-pr-affected-replay.test.sh` advisory pins | inferred | chks `row_wf_coe` (~2944), `row_wf_dark` (~2949), `row_wf_dark_mutant` (~2954), `coe-gone` (~2955) assert the advisory state — suite reds otherwise |
| `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` | inferred | 9 literal `contexts=12 producers=11` assertions break at 13/12 |
| `scripts/probe-merge-group-coverage.sh` MIN_CONTEXTS bump | inferred | deliberate literal floor tracking the count (T-rsc-7 philosophy); ≥ floor still passes — the bump keeps anti-vacuity honest |
| `scripts/required-check-wallclock-bounds.tsv` row | inferred | the TSV header: "a required context with no row here is itself a ratchet finding"; the probe emits `unbound` per missing row |
| `scripts/ci-pr-affected-replay.py` `--print-files-read` | inferred | the read set is NOT exposed today (Premise Validation correction); the parent plan's assertion needs it |
| `ci-pr-affected-activation.md` runbook "dark phase" rewrite | inferred | the section will actively lie post-merge ("Until PR3b … is advisory") |
| ADR-276 `### Stage status` dated line | inferred | series convention; the recorded decision's execution note |
| `infra/github/README.md` count mentions (10→11) | inferred | doc drift in the same directory as the edited tf |

### Split Assessment

No split — the issue prescribes one commit (name + coe deletion atomically, the
ADR-032 paired-edit contract). Splitting the ci.yml edit from the registry
edits would leave an interval where either an advisory job is named required
(probe red) or a required context still carries coe (biconditional red).

## Open Code-Review Overlap

None — queried 2026-11-07 (`gh issue list --label code-review --state open`);
no open issue body names any file in the plan's edit set.

## Implementation Phases

### Phase 1 — the one-commit registry enrollment

All in ONE commit (ADR-032 paired-edit contract):

1. `.github/workflows/ci.yml`: delete `continue-on-error: true` (line ~521);
   rewrite the advisory comment block (~505-518) to state the context is
   required as of this commit (#10859) — keep the measured canary note and the
   `if:` rationale; keep `if:` exactly `pull_request || merge_group`.
2. `scripts/required-checks.txt`: append (before `# CLA Required ruleset`) the
   name plus a `# #10859` justification block — CONTENT-SCOPED, UNREACHABLE:
   the guarded surface (the audit's files-read set) is disjoint from
   ALLOWED_PATHS, asserted live by the new test (Guard 1), not argued; name the
   residual trigger (any ALLOWED_PATHS member entering files-read → reproduce
   the check in the action's Phase-4 preflight before it lands).
3. `scripts/ci-required-ruleset-canonical-required-status-checks.json`: append
   `{"context": "affected-index-ratchet", "integration_id": 15368}`.
4. `infra/github/ruleset-ci-required.tf`: append the `required_check` block
   with a dated #10859 comment; fix the "the 10 `context` strings below"
   header → 11.
5. `plugins/soleur/test/required-checks-canonical-parity.test.sh`: bump the
   Test-1c non-vacuity floors `-ge 10` → `-ge 11` (the count pin).
6. `plugins/soleur/test/fixtures/admin-merge-ready/`: append the context to
   ruleset 14145388 in `rules-branches-main.json`; append a green
   `affected-index-ratchet` run (app.id 15368, fixture head_sha) to
   `check-runs.json`; dated note line in the fixture README (11 → 12 contexts
   on the CI Required fixture, PRE-adoption base note stands).
7. `tests/scripts/test-audit-ruleset-bypass.sh`: T-rsc-7 `n == "10"` → `"11"`
   plus the bump-chain comment line (10 → 11 by #10859).
8. `scripts/pr-fanout-ledger.txt`: dated clause on the ci.yml row —
   "context became required; declared job count unchanged at 21".

### Phase 2 — the unreachability assertion

1. `scripts/ci-pr-affected-replay.py`: `audit` gains `--print-files-read` —
   prints the sorted repo-relative real paths of `index.raws` after
   `audit_census`, one per line, exits 0 when the census ran (and 2 on
   census-degraded per the existing floor semantics). `--help`/docstring line
   in the audit epilog.
2. `plugins/soleur/test/ci-pr-affected-replay.test.sh`:
   - rewrite the advisory pins: `row_wf_coe` chk → remove or invert;
     `row_wf_dark` → `row_wf_required` (name present in required-checks.txt AND
     coe absent); `row_wf_dark_mutant`/`coe-gone` mutants → re-baseline on the
     required state (e.g., re-added coe while name is required reds the
     biconditional; name dropped from required-checks reds the required pin);
   - unit rows for `--print-files-read` on a synthetic fixture tree;
   - the disjointness row: parse `ALLOWED_PATHS=(...)` out of the real
     action.yml, run `audit --print-files-read` on the real repo root, assert
     intersection empty + read-set size ≥ 500 + every member tracked under
     root; a mutant injecting a read file into the parsed set must red.
   - suite-duration note: the real-census row adds roughly the audit's runtime
     (~200-300 s) to the c leg; place it last in the file (rows are sharded
     a/b/c by count — the leg assignments in test-all.sh need no edit since
     legs are row-count ranges; if the row count crosses a shard boundary the
     shard lines may need a bump — check `run_suite ".../ci-pr-affected-replay-c" ... --rows` lines).
3. `plugins/soleur/test/required-checks-merge-group-coverage.test.sh`:
   `contexts=12 producers=11` → `contexts=13 producers=12` (all 9 literals);
   `engine_green 12` floors → 13 (optional consistency bump).
4. `scripts/probe-merge-group-coverage.sh`: `MIN_CONTEXTS_DEFAULT = 12` → 13,
   comment "12 = 10 CI + 2 CLA" → "13 = 11 CI + 2 CLA".
5. `scripts/required-check-wallclock-bounds.tsv`: seed
   `affected-index-ratchet` row — bound = measured p90 of recent runs rounded
   UP to the next minute (verify via `watch-wallclock-p90-11774.sh --dry-run`;
   p95 240 s wall suggests pr/mq bounds ~420 s each; margin 0.30).

### Phase 3 — records and docs

1. `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`:
   rewrite §The dark phase → the required state (context required since
   2026-11-07 #10859; how a red reads as a required-check failure now — the
   marker/annotation reading stays), update §2 status line and line ~214
   ("While the job is advisory…"), keep the observation log.
2. ADR-276 `### Stage status`: dated line (see Architecture Decision).
3. `infra/github/README.md`: "10 contexts" → 11 in the two spots naming the CI
   count (pre-existing "23"/"12" staleness elsewhere may be corrected in the
   same edit where the same figure is named).
4. `knowledge-base/project/specs/<branch>/{tasks.md,decision-challenges.md}`:
   pipeline artifacts.

### Phase 4 — verify, ship

1. Run the touched suites locally: `required-checks-canonical-parity`,
   `required-checks-merge-group-coverage`, `tests/scripts/test-audit-ruleset-bypass.sh`,
   `plugins/soleur/scripts/admin-merge-ready.test.sh`,
   `ci-pr-affected-replay` (all legs), `ci-draft-light`, `ci-push-dedupe`.
2. `bash scripts/probe-merge-group-coverage.sh` → `merge-group-coverage=OK
   contexts=13 producers=12` before merging (issue-asked pre-merge gate).
3. Read live ruleset `bypass_actors` + `conditions` before merge (evidence for
   the post-apply comparison the parent plan requires).
4. PR body: `Closes #10859`, states the merge auto-applies the ruleset via
   apply-github-infra.yml (whole-payload replace; bypass_actors and conditions
   verified unchanged by read before/after), and cites the go-ahead comment
   URL (issuecomment-6710852889). No `[ack-destroy]` needed (addition only).
5. After the apply runs: verify the live ruleset shows 11 required contexts
   and `bypass_actors`/`conditions` unchanged; comment on #10448 (series
   tracker) and #10859.

## Acceptance Criteria

- [ ] `grep -n 'continue-on-error' .github/workflows/ci.yml` shows no
  job-level coe on `affected-index-ratchet` (the draft-light/harness-member
  spellings elsewhere stay).
- [ ] `grep -qxF affected-index-ratchet` matches a non-comment row in
  `scripts/required-checks.txt` (before the CLA section) WITH its justification
  block.
- [ ] `jq '[.[] | select(.context=="affected-index-ratchet")] | length == 1'`
  on the canonical JSON; all rows `integration_id == 15368`.
- [ ] `grep -c 'context *= *"' infra/github/ruleset-ci-required.tf` == 11 and
  includes `affected-index-ratchet` with `var.actions_integration_id`.
- [ ] `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`,
  `bash tests/scripts/test-audit-ruleset-bypass.sh`,
  `bash plugins/soleur/scripts/admin-merge-ready.test.sh`,
  `bash plugins/soleur/test/required-checks-merge-group-coverage.test.sh`,
  `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` (all legs),
  `bash scripts/ci-draft-light.test.sh`, `bash scripts/ci-push-dedupe.test.sh`
  all exit 0.
- [ ] `bash scripts/probe-merge-group-coverage.sh` prints
  `merge-group-coverage=OK contexts=13 producers=12`.
- [ ] `scripts/required-check-wallclock-bounds.tsv` has an
  `affected-index-ratchet` row (the probe emits no `unbound` finding for it).
- [ ] `python3 -I scripts/ci-pr-affected-replay.py audit --print-files-read`
  prints a non-empty sorted read set; the committed test asserts
  ALLOWED_PATHS ∩ read-set == ∅ and stays green on today's tree.
- [ ] The commit containing the ci.yml edit also contains every registry edit
  (single-commit atomicity — `git show --stat` of the merge commit lists them
  all).
- [ ] PR body cites the go-ahead comment URL and states the merge auto-applies
  the ruleset via apply-github-infra.yml.
- [ ] Post-merge: `gh api repos/jikig-ai/soleur/rulesets/14145388` shows
  `affected-index-ratchet` among required contexts with `bypass_actors` and
  `conditions` unchanged from the pre-merge read.

## Test Scenarios

- Mutant: re-added `continue-on-error` while the name is required →
  `row_wf_bicond` (and `row_wf_required_not_coe`) red.
- Mutant: name in required-checks.txt but not canonical JSON → parity Test 1
  red (and T-rsc-7 stays green — it is count-only).
- Mutant: canonical at 10 entries → T-rsc-7 red (`n==11`).
- Disjointness: inject a files-read member into the parsed ALLOWED_PATHS set →
  the new row red; add a non-read path → stays green.
- `--print-files-read` broken (empty output) → the ≥500 floor row red.
- Queue coverage: probe prints `contexts=13 producers=12` — no `::error` lines.

## Alternative Approaches Considered

| Option | Rejected because |
|---|---|
| Two PRs (delete coe, then enroll) | a required-but-coe job or a required-name-without-producer interval; the issue prescribes one commit (ADR-032 paired-edit) |
| Draft-light gating of the ratchet | see re-examination: needs-edge stall class or fabricated green; ruled Option A |
| Ref-line set as the read set (`--all-refs` as-is) | under-approximation: read-but-refless files invisible while still verdict-reachable |
| Adding the name to `_cron-safe-commit.ts` SYNTHETIC_CHECK_NAMES | Inngest PRs push with an App token → real CI runs → the check is EARNED; fabricating it is the #8203 defect class |

## Dependencies & Risks

- **Apply race**: between merge and the apply-github-infra.yml run completing,
  the file-level registries are ahead of the live ruleset — no stall (the live
  gate lags, never leads). The post-apply verify step + daily audit bound the
  window; the AC reads the live ruleset after apply.
- **A red ratchet post-promotion blocks everything**: that is the intended
  behavior; the runbook's exit/token table (already updated in Phase 3) is the
  operator's remedy path. Break-glass: ruleset bypass via admin merge or the DR
  script (`create-ci-required-ruleset.sh`) — documented in the tf header.
- **`oracle-inputs-changed:` warning on THIS PR**: expected — the PR edits
  ci.yml and the replay script (both oracle files); reviewers treat it as the
  oracle-review step the runbook names.
- **Fixture recapture note**: admin-merge-ready fixtures stay the
  PRE-adoption-shape base (CodeQL present); we append, not recapture (README's
  own convention).
- **Suite-duration drift**: the new real-census row lengthens
  `required-checks-canonical-parity.test.sh` (or the replay suite wherever the
  row lands) by ~200-300 s — acceptable; `suite-durations.tsv` rows are
  refreshed by the duration machinery, no hand edit.

## Files to Edit

1. `.github/workflows/ci.yml` (delete coe line ~521; rewrite advisory comment ~505-518)
2. `scripts/required-checks.txt` (name + justification block, before CLA section)
3. `scripts/ci-required-ruleset-canonical-required-status-checks.json` (11th row)
4. `infra/github/ruleset-ci-required.tf` (required_check block + header count)
5. `plugins/soleur/test/required-checks-canonical-parity.test.sh` (`-ge 10` → `-ge 11`)
6. `plugins/soleur/test/fixtures/admin-merge-ready/rules-branches-main.json` (add context to 14145388)
7. `plugins/soleur/test/fixtures/admin-merge-ready/check-runs.json` (add green run)
8. `plugins/soleur/test/fixtures/admin-merge-ready/README.md` (dated note)
9. `tests/scripts/test-audit-ruleset-bypass.sh` (T-rsc-7 `10` → `11` + comment)
10. `scripts/pr-fanout-ledger.txt` (dated clause on ci.yml row)
11. `scripts/ci-pr-affected-replay.py` (`audit --print-files-read` flag)
12. `plugins/soleur/test/ci-pr-affected-replay.test.sh` (advisory pin rewrites + new rows)
13. `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` (12/11 → 13/12 literals)
14. `scripts/probe-merge-group-coverage.sh` (MIN_CONTEXTS 12 → 13 + comment)
15. `scripts/required-check-wallclock-bounds.tsv` (new bound row)
16. `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (dark-phase rewrite)
17. `knowledge-base/engineering/architecture/decisions/ADR-276-*.md` (Stage-status dated line)
18. `infra/github/README.md` (context-count mentions 10 → 11)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10859-pr3b-required-context/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10859-pr3b-required-context/decision-challenges.md`

## Explicitly NOT edited (pinned by AC/test)

- `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`,
  `scripts/ci-pr-selection.sh`, `CI_PR_AFFECTED`, PR D (#10414) — the issue's
  hold boundary.
- `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts`
  SYNTHETIC_CHECK_NAMES — earned-by-real-CI disposition (see Cut List).
- The job's `if:`, `timeout-minutes: 5`, `fetch-depth: 2`, permissions — all
  pinned by existing `row_wf_*` chks and unchanged by this PR.
