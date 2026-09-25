# Plan: cancel-in-progress concurrency for uncovered PR workflows

Date: 2026-09-25
Branch: `feat-one-shot-ci-concurrency-cancel` · PR: #8891 (draft)
Arc: CI-efficiency item 2 of 5 (item 1 = #8854, merged). Prior art: #7931 part 1 / ADR-217 (per-SHA-on-push, per-ref-on-PR convention), ADR-216 + addendum 2026-09-24 (`cancel-superseded-pr-runs` reaper + `scripts/pr-fanout-ledger.txt`).

## Overview

Add workflow-level `concurrency` with PR-scoped `cancel-in-progress` to the two
synchronize-firing workflows that lack it: **`infra-validation.yml`** and
**`constraint-gates.yml`**. Both already have their stale-head runs reaped by
`cancel-superseded-pr-runs.yml` (they are ledger rows), so this is not a new
cancellation policy — it moves cancellation from "seconds after the reaper job
spins up" to "at enqueue time", and extends it to fork / dependabot PRs the
reaper's job-level `if:` skips.

The block to add is **ci.yml's ADR-217 block, byte-for-byte**:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

Five sibling workflows (`ci.yml`, `dependency-review.yml`,
`gdpr-gate-self-test.yml`, `legal-doc-cross-document-gate.yml`,
`pr-quality-guards.yml`) already carry exactly this. The ledger test (A6)
**mandates** the byte-for-byte group for any block using the ternary cancel
form, so there is no expression-design freedom to exercise — deviating fails
`plugins/soleur/test/pr-fanout-ledger.test.sh`.

The brief's suggested group `${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}`
is **rejected**: on a `push` to `main` it resolves to `…-refs/heads/main`, one
shared group for every main push — the exact serialization/cancellation defect
class ADR-217 fixed by keying push runs on `github.sha`.

## Verification-first premises (each re-verified on this branch)

| File | Verified state | Verdict |
|---|---|---|
| `infra-validation.yml` | push:main + pull_request (paths-filtered). **No** workflow-level concurrency. Job-level `terraform-plan-${{ github.event.number \|\| github.run_id }}-${{ matrix.directory }}` at line ~2177, no cancel flag (defaults false). `plan` job is pull_request-only, `-refresh=false`, R2 `use_lockfile=false` → no state lock held mid-flight. `infra-validate-required` is an `if: always()` aggregator that is **deliberately NOT a required context** (comment cites #6480). No `merge_group` trigger. | **INCLUDE** — workflow-level canonical block. Job-level group untouched. |
| `constraint-gates.yml` | pull_request `[opened, synchronize, reopened]` only. No concurrency. Informational — NOT a required check (promotion blocked on #5791). Body is **parity-locked** to `plugins/soleur/skills/constraint-scaffold/references/constraint-gates-workflow.template` (parity.test.sh rows 3–4 pin template ↔ `apps/web-platform/.github/workflows/constraint-gates.yml` ↔ repo-root copy). | **INCLUDE** — requires editing all 3 copies + the template carries the block to every future scaffolded repo. |
| `cla.yml` | pull_request_target `[opened, synchronize, reopened]` + issue_comment. No concurrency. Ledger row already records: `no cancel: privileged trigger, keep its run shape untouched`. `cla-check` is a CLA Required ruleset context. The reaper deliberately skips in-progress pull_request_target runs (SELECT_JQ rule 9b, "secrets, outside writes"). | **EXCLUDE** — privileged-trigger policy already codified; cancelling mid-flight risks interrupting the signature push to `cla-signatures` (lost signature → silent re-prompt). |
| `cla-evidence.yml` | pull_request_target + issue_comment `[created, edited, deleted]`. Concurrency exists, `cancel-in-progress: false`. `cla-evidence` is a CLA Required ruleset context. Each event produces a distinct content-addressed R2 evidence record; a cancelled comment-event run loses that record's upload (including `edited`/`deleted` tombstones under the R2 Lock Rule). | **EXCLUDE** — do not flip to `true`; the evidence layer must not drop events. Ledger `no cancel: privileged trigger, same as cla.yml`. |
| `dev-ledger-reconcile.yml` | pull_request_target `[closed]` + workflow_dispatch only. Documented decision at line 41: "No concurrency group: the dev-suite mutex serializes writers and the compare-and-set makes a repeated run a no-op." | **EXCLUDE** — closed-only events cannot be superseded; deliberate design comment. Not in the ledger generator (closed-only). |
| `cleanup-unmerged-bot-branches.yml` | pull_request `[closed]` only. No concurrency. | **EXCLUDE** — closed-only; a superseding push cannot exist; idempotent delete job. Outside the ledger generator. |
| `apply-sentry-infra.yml` | Has workflow-level per-ref group, `cancel-in-progress: false`. | **EXCLUDE** — ledger `no cancel:` protects required `sentry-destroy-required` aggregator (#5585 R3); R2 no state lock. |
| `tenant-integration.yml` | Job-level `dev-supabase-${{ github.ref }}` + `cancel-in-progress: false`, deliberate (#5585 R3, #7055, #7986, #8048). Required `tenant-integration-required` aggregator must stay outside any cancellable group. | **EXCLUDE** — a workflow-level group with cancel=true would conclude the required aggregator `cancelled` and reintroduce the measured eviction hazard. |
| `vendor-pin-verify.yml` | Same shape as tenant-integration (#8203): required `vendor-pin-required` aggregator, job-level per-ref cancel=false. | **EXCLUDE** — same reason. |
| `fix-constraints-stage-a.yml` | `cancel-in-progress: true` already, but group is per-head-SHA (`github.event.pull_request.head.sha`) — a deliberate fan-out cap ("one paid agent dispatch per head SHA"). | **EXCLUDE** — a per-PR key would let a push cancel an in-flight paid agent dispatch; per-SHA is the documented design. |
| `fix-constraints-stage-b.yml` | workflow_run-chained off stage-a; per-head-SHA group, cancel=false. workflow_run rows are never reaped. | **EXCLUDE** — ledger `no cancel:` reason recorded. |
| `board-status-sync.yml`, `claude-code-review.yml`, `pr-auto-close-scanner.yml`, `cancel-superseded-pr-runs.yml`, `secret-scan.yml`, `gdpr-gate-self-test.yml`, `dependency-review.yml`, `legal-doc-cross-document-gate.yml`, `pr-quality-guards.yml`, `rls-authz-fuzz.yml`, `sentry-audit-gate.yml`, `skill-security-scan-corpus.yml`, `skill-security-scan-pr-trailer.yml`, `validate-vector-config.yml`, `ci.yml` | Already carry qualifying concurrency (cancel=yes in the ledger, or cancel=false where deliberate and ledgered). | No change. |

Re-scan coverage: every workflow firing on `synchronize` is a row of
`scripts/pr-fanout-ledger.txt` (the ledger test enforces completeness — a
firing workflow with no row reddens CI). Enumerating that file is therefore a
complete scope derivation; the brief's candidate list is confirmed stale only on
`infra-validation.yml` (its concurrency block is job-level, not
workflow-level, and carries no cancel flag at all — the brief's "concurrency
block exists, NO cancel-in-progress" is accurate only at job level).

### workflow_run coupling

No `workflow_run: workflows:` list names either touched workflow. The only
consumers are `post-merge-monitor.yml` → "CI", `web-platform-release.yml` →
"CI" (both read main-push run conclusions of `ci.yml`, which we do not touch),
`deploy-docs.yml` → "Version Bump and Release", `git-data-pin-redeploy.yml` →
"Apply web-platform infra (…)", `fix-constraints-stage-b.yml` →
"fix-constraints-stage-a". **No downstream consumer reads a `cancelled`
conclusion for `infra-validation` or `constraint-gates`.**

## Proposed Change

### 1. `infra-validation.yml`

Insert at top level (between `permissions:` and `jobs:`), byte-for-byte:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

Semantics:
- `pull_request` → group `Infra Validation-refs/pull/<N>/merge`, cancel=true: a
  synchronize cancels queued + in-flight runs on the stale merge ref.
- `push` to main → group `Infra Validation-<sha>` (per-SHA), cancel=false:
  every main push gets its own group; nothing is cancelled and nothing is
  serialized — the ADR-217 invariant. `notify-main-failure` (push-only) and
  `deploy-script-tests` keep full per-push coverage.
- The job-level `terraform-plan-…-${{ matrix.directory }}` group stays as-is:
  matrix legs still serialize per directory within a run; it composes with, and
  is not replaced by, the workflow-level group.

### 2. `constraint-gates.yml` (three lockstep edits)

Add the identical block to:
- `plugins/soleur/skills/constraint-scaffold/references/constraint-gates-workflow.template`
  (before `permissions:`), then
- `apps/web-platform/.github/workflows/constraint-gates.yml` (the emitted copy —
  byte-identical after `__TARGET_DIR__` substitution; the block has no
  placeholder), and
- `.github/workflows/constraint-gates.yml` (repo-root dogfood — parity row 4
  strips comments, so the block must appear identically in the body).

Consequence for tenants: repos scaffolded by `constraint-scaffold` after this
lands inherit per-PR cancellation — a strict improvement (the emitted gate is
pull_request-only, so the ternary degenerates to always-cancel on PRs, which is
correct for an informational always-run gate).

### 3. `scripts/pr-fanout-ledger.txt`

Flip two rows `cancel` no → yes and replace each `no cancel: <reason>` tail with
the new standing reason (A5 still requires a consequence; the cancel column no
longer needs an excuse):
- `infra-validation.yml`: e.g. `… path-filtered; workflow-level ADR-217 ternary
  group cancels superseded PR runs (R2 use_lockfile=false — no state lock held);
  push arm keys per-SHA so main is never serialized or cancelled`
- `constraint-gates.yml`: e.g. `… body parity-locked to the constraint-scaffold
  template; workflow-level ADR-217 ternary group added to template and both
  emitted copies; pull_request-only so cancel resolves true on every fire`

## Guard Contract

- `plugins/soleur/test/pr-fanout-ledger.test.sh`:
  - **A6** — a ternary-form block MUST carry ci.yml's group byte-for-byte (the
    B6f mutant exists precisely to redden a divergence). Our block is copied
    verbatim → green.
  - **cancel-flag parity** — row `cancel=yes` requires a qualifying block
    (cancel form + group shape, no per-run token). `github.ref` satisfies the
    group-shape rule; the `github.sha` fallback is on the non-PR branch of the
    `&&`/`||` so it is the ci.yml pattern, which the enumerator accepts.
  - **jobs ceiling** — unchanged (no jobs added).
- `plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` rows 3–4 —
  template ↔ `apps/web-platform` copy ↔ repo-root copy; all three edits must
  land in one commit or the gate reds between them.
- Required checks untouched: `test`, `dependency-review`, `e2e`,
  `skill-security-scan PR gate`, gitleaks/guard fixtures, `cla-check`,
  `cla-evidence` — none of the edited files produce a required context, and no
  `pull_request_target` / merge_group / push-main behavior changes.
- UNTRUSTED-CI: no `--admin` merge; required checks must pass on the PR. The
  PR itself exercises the new constraint-gates group on every push to this
  branch (dogfood signal).

## Alternatives

| Alternative | Rejected because |
|---|---|
| Brief's group `${{ github.workflow }}-${{ github.event.pull_request.number \|\| github.ref }}` | On push:main resolves to `…-refs/heads/main` — one shared group serializes (or with a static `true`, cancels) main pushes. The ADR-217/#7931 defect class. Also violates ledger A6. |
| Job-level groups instead of workflow-level | A per-job group leaves `detect-changes`/`infra-validate-required` outside it; pending-run eviction could still drop a run before the aggregator reports. Workflow-level is what the convention standardizes. |
| Include cla.yml / cla-evidence.yml with cancel=true | Privileged `pull_request_target`; the repo's own reaper refuses in-flight privileged cancels (rule 9b); cla-evidence drops per-event evidence records on cancel. Ledger already codifies `no cancel`. |
| Exclude constraint-gates to avoid the 3-file parity edit | The parity machinery exists to force template↔dogfood lockstep; editing all three is the sanctioned path and also upgrades every future scaffolded repo. |
| Rely on `cancel-superseded-pr-runs.yml` alone | It already reaps these workflows, but (a) only same-repo, non-dependabot PRs (job `if:`), (b) only after a runner spins up the reaper job (~seconds of billed overlap each push), (c) as a queued job it is itself subject to runner availability. Concurrency groups act at enqueue, before billing starts. |

## Acceptance Criteria (testable)

- **AC1** `git grep -n 'cancel-in-progress' .github/workflows/infra-validation.yml`
  shows the workflow-level ternary; `git grep -c 'concurrency:'` = 2 (workflow +
  plan job).
- **AC2** `bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh`
  exits 0 — proves template + `apps/web-platform` copy + repo-root copy carry
  the identical block.
- **AC3** `bash plugins/soleur/test/pr-fanout-ledger.test.sh` exits 0 — rows
  flipped to `cancel=yes` and A6 byte-for-byte group holds.
- **AC4** Expression semantics verified on the PR itself: push two commits in
  quick succession → `gh api …/actions/workflows/constraint-gates.yml/runs`
  shows the earlier run `conclusion=cancelled`, the later run completes.
- **AC5** `git diff origin/main -- .github/workflows/cla.yml
  .github/workflows/cla-evidence.yml .github/workflows/dev-ledger-reconcile.yml
  .github/workflows/cleanup-unmerged-bot-branches.yml
  .github/workflows/tenant-integration.yml .github/workflows/vendor-pin-verify.yml
  .github/workflows/apply-sentry-infra.yml .github/workflows/fix-constraints-stage-*.yml`
  is empty — excluded files untouched.
- **AC6** Post-merge: two pushes to `main` within minutes → both
  `Infra Validation` runs proceed concurrently to completion (per-SHA groups),
  none `cancelled` — the do-not-cancel-main invariant, observable via
  `gh run list --workflow infra-validation.yml --branch main`.

## Test Scenarios

- **Given** an open PR touching `infra/**`, **when** a second push lands while
  the first `Infra Validation` run is mid-`plan`, **then** the first run
  concludes `cancelled` and the second runs to completion (the
  `terraform-plan-*` job group is orthogonal; the cancelled plan held no state
  lock — `use_lockfile=false`, `-refresh=false`).
- **Given** the same PR, **when** the run for the current head is the newest in
  its group, **then** nothing cancels it (the surviving run is the current-head
  one by construction of `github.ref` = `refs/pull/N/merge`).
- **Given** two merges to `main` three minutes apart, **when** the first
  `Infra Validation` push run is still in-flight, **then** the second push run
  starts immediately in its own per-SHA group and neither is cancelled —
  `cancel-in-progress` evaluated to `false` on `push`.
- **Given** a PR touching `apps/web-platform/**`, **when** a synchronize arrives
  mid-run of `constraint-gates`, **then** the stale run cancels and the new
  head's gate reports; a PR touching nothing under `apps/web-platform/` still
  exits 0 fast via `changed=false` on the surviving run.
- **Given** a contributor signing the CLA while a synchronize lands, **when**
  events interleave, **then** neither `cla.yml` nor `cla-evidence.yml` behavior
  changes — both files are untouched (AC5).
- **Given** the ledger mutant suite, **when** A6/B6 mutants run, **then** the
  new blocks are covered by the same enforcement as the five existing ternary
  workflows.

## Observability

brand_survival_threshold: none (internal CI surface; no user-facing SLO).

- Dogfood signal: this PR's own pushes demonstrate AC4 — cancelled runs appear
  under `conclusion=cancelled` on stale head SHAs of this branch.
- Post-merge verification step (in PR body checklist): re-run the measurement
  query below on a 7-day window and confirm `already_cancelled` rises toward
  `in-flight-at-supersede` for the two workflows and that `Infra Validation`
  push-to-main runs show zero `cancelled` conclusions.
- Ledger + parity tests are the standing guard — no new monitor is warranted
  for two YAML keys; `scheduled-actions-queue-health.yml` already watches
  runner starvation at the repo level.

### Before-measurements (for the PR body)

Window: `gh api …/actions/workflows/<wf>/runs?per_page=100&created=2026-09-20..2026-09-25`,
`pull_request` events grouped by `head_branch`; "superseded" = a later run
exists on the same branch; "in-flight" = `updated_at` > next run's
`created_at`. Job-min sampled via `/runs/<id>/jobs` (12-run sample each).

| Workflow | PR runs | branches | superseded | in-flight at supersede | truncatable wall-min | sampled avg job-min/run | already reaper-cancelled |
|---|---|---|---|---|---|---|---|
| constraint-gates.yml | 1000 | 135 | 865 (86%) | 195 | ~725 | ~1.0 | 26 |
| infra-validation.yml | 590 | 77 | 513 (87%) | 313 | ~6,297 | ~14.0 | 161 (3,726 wall-min burned pre-cancel) |

Reading: the reaper already catches a large share for infra-validation, but the
~5 days of window still show ~313 runs executing past their supersede point
(~14 job-min each ≈ up to ~4,400 job-min/5 days recoverable at enqueue-time
cancellation), plus fork/dependabot PRs the reaper skips entirely.
constraint-gates is ~195 × ~1 job-min — small but free.

## Deferred Follow-ups

- #6480 (promote `infra-validate-required` to a required context): when that
  lands, re-derive whether a `cancelled` aggregator conclusion on a stale SHA
  stays harmless — required contexts are evaluated on the current head, so it
  does, but the promotion PR must restate it.
- Reaper overlap is now intentional belt-and-suspenders: keep it — it covers
  the ledgered workflows that deliberately stay `cancel=no`, CodeQL dynamic
  runs, and anything GitHub's group evaluation misses (e.g., runs orphaned by a
  group-key rename mid-PR).
- Tenant repos scaffolded before this change keep the old emitted gate; the
  template improvement propagates only on the next `constraint-scaffold` run —
  no backfill planned (gate is informational everywhere).
- cla.yml / cla-evidence.yml remain non-cancelling by policy; revisit only with
  a signature-write idempotency analysis — not this arc.

## Blast radius (files changed)

- `.github/workflows/infra-validation.yml` — +3 lines (concurrency block).
- `.github/workflows/constraint-gates.yml` — +3 lines.
- `apps/web-platform/.github/workflows/constraint-gates.yml` — +3 lines.
- `plugins/soleur/skills/constraint-scaffold/references/constraint-gates-workflow.template` — +3 lines.
- `scripts/pr-fanout-ledger.txt` — 2 rows updated (cancel flag + reason text).

Total: 5 files, all additive except the ledger reason text. No jobs, triggers,
permissions, secrets, or required checks touched.
