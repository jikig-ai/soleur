# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-09-25-feat-ci-concurrency-cancel-plan.md`
- Tasks file: `knowledge-base/project/specs/feat-one-shot-ci-concurrency-cancel/tasks.md` (this directory)
- Status: plan + deepen completed in one pass. No errors.

### Decisions

- **Final scope is 2 workflows, not the brief's 6 candidates.** IN: `infra-validation.yml`, `constraint-gates.yml`. OUT: `cla.yml` + `cla-evidence.yml` (privileged `pull_request_target`; ledger already codifies `no cancel: privileged trigger`; the reaper deliberately never cancels in-flight privileged runs — SELECT_JQ rule 9b; cla-evidence drops per-event content-addressed R2 records on cancel), `dev-ledger-reconcile.yml` (closed-only + documented no-concurrency decision), `cleanup-unmerged-bot-branches.yml` (closed-only, cannot be superseded, outside ledger generator), `apply-sentry-infra.yml` / `tenant-integration.yml` / `vendor-pin-verify.yml` (required-check always-run aggregators behind deliberate `cancel-in-progress: false`, #5585 R3 / #7986 / #8048 / #8203), `fix-constraints-stage-a/b` (per-head-SHA fan-out cap / workflow_run-chained, both deliberate).
- **Group expression: ci.yml's ADR-217 block byte-for-byte** (`group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}`, `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`). The brief's suggested group (`github.event.pull_request.number || github.ref`) was rejected: it resolves to `refs/heads/main` on push → one shared group would serialize/cancel main (the #7931 class), and ledger test A6 pins ternary blocks to ci.yml's group anyway.
- **constraint-gates is parity-locked.** Editing `.github/workflows/constraint-gates.yml` alone reds `constraint-scaffold/test/parity.test.sh` — the template and `apps/web-platform/.github/workflows/constraint-gates.yml` must change in the same commit. Side benefit: future scaffolded repos inherit cancellation.
- **`cancel-superseded-pr-runs.yml` overlap quantified:** the reaper already covers both workflows (ledger rows) — this change moves cancellation to enqueue time and extends it to fork/dependabot PRs the reaper's job `if:` skips.
- **No workflow_run coupling:** no `workflow_run: workflows:` consumer names either touched workflow. Consumers only watch "CI", "Version Bump and Release", "Apply web-platform infra", "fix-constraints-stage-a".
- **Measurements captured** (Sep 20–25 window, in plan §Observability): infra-validation 590 PR runs / 513 superseded / 313 in-flight at supersede (~14 job-min each); constraint-gates 1000 PR runs / 865 superseded / 195 in-flight (~1 job-min each).

### Gotchas for /work

- `gh api .../runs?event=pull_request` returned stale data (Aug-20 newest while unfiltered shows Sep-25); use `--paginate` + `created=<range>` + client-side `event` filter, or `gh run list`.
- Do NOT add `merge_group` or touch `on:` in either file.
- infra-validation job-level `terraform-plan-*` group stays untouched — it composes with the workflow-level group.
