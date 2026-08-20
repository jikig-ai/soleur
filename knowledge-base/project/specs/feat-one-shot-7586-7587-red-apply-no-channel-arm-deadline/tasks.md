# Tasks — feat-one-shot-7586-7587-red-apply-no-channel-arm-deadline

Derived from
[`knowledge-base/project/plans/2026-08-20-fix-apply-infra-failure-channel-and-arm-deadline-plan.md`](../../plans/2026-08-20-fix-apply-infra-failure-channel-and-arm-deadline-plan.md),
**post-deepen**. Closes **#7586** and **#7587**. Incident **#7228** is context only and is **not** a
work target — do not close it.

`lane: cross-domain` (no `spec.md` on this branch; fail-closed default per TR2).

**Phase order is load-bearing.** Phase 1 changes contracts the later phases assert on; the guards in
Phase 5 are written from the design, not from whatever the code ends up looking like.

---

## Phase 0 — Preconditions and the mutation matrices

- [ ] **0.1** Re-read the plan's `## Guard Contract` and write both mutation matrices down before
      touching the workflow. A matrix derived from finished code tests the code that exists; one
      derived from the design tests the property.
      **NOT DONE AS SPECIFIED, recorded honestly.** The `## Guard Contract` was read in full before
      the first edit (its Assembly notes are what put the `arm_one` extraction and the
      identify-the-sweep-by-`always()`-plus-state-file-literal rule into the design), but the two
      matrices were not written to a separate artifact *first* — they were transcribed into
      `measurements.md` at 5.7 and executed there. The risk this task exists to prevent (a matrix
      derived from the finished code) is therefore mitigated by the matrices being copied verbatim
      from the plan rather than re-invented, but the ordering the task asks for was not followed.
- [x] **0.2** Confirm issue states are unchanged: `gh issue view 7586 7587 7228 7462 --json state`.
- [x] **0.3** Re-derive the two sizing terms from the jobs API — do **not** carry this plan's
      literals: (a) the reachable deadline sum, (b) the **p95 pre-gate duration** (job start → ARM
      step start). The plan measured 57/58/64/81/91/111 s across six runs (p95 111 s) via
      `gh api repos/:owner/:repo/actions/runs/<id>/jobs`. Record both in `measurements.md` with the
      command.
- [x] **0.4** Verify the errexit premise directly: confirm the ARM step declares no `shell:` key, so
      GitHub invokes it as `/usr/bin/bash -e {0}`. An earlier plan draft got this backwards; do not
      proceed on memory.
- [x] **0.5** Run the bound suites GREEN before any edit, so a later red is attributable:
      `bun test plugins/soleur/test/terraform-target-parity.test.ts`,
      `bun test plugins/soleur/test/stock-preflight-coverage.test.ts`,
      `bash tests/scripts/test-preapply-entrypoint-gate.sh`,
      `bash tests/scripts/test-vector-redeliver-wiring.sh`,
      `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`.
- [x] **0.6** Re-confirm the two claims the deepen pass flagged as unverifiable from the repo, both
      load-bearing for the sweep: (a) `git_data_prd` is absent from the merge-path tfstate — read it
      from a run's ARM-step log, not a committed file; (b) `$RUNNER_TEMP` persists across steps
      within a job — GitHub Actions platform semantics with no in-repo citation, so confirm it
      empirically. **If (b) does not hold, the state file must move to a step output or an artifact
      and the sweep design changes.**
- [x] **0.7** Measure observed queue depth / wait on the shared
      `terraform-apply-web-platform-host` group before relying on the budget raise. The plan states
      the true worst case as 35 min run-level (apply 30 + notify 5, summed because the group is
      workflow-level); per-merge queue wait is the binding constraint and is **not** yet measured.
      **MEASURED** (`measurements.md` §0.7): 80 completed runs of the shared group over 35 days —
      observed queue depth never exceeded **1**, longest run **23.7 min**, worst wait-to-first-job
      **492 s**, and the sibling sharing this mutex already runs a 90-minute apply. The raise is
      therefore safe; the honest run-level worst case is **45 min** (preflight 1 + apply 39 +
      notify 5), not the plan's 35. Two corrections rolled in at review-resolution (#7657 D6):
      `preflight` is chained by `needs:` and was uncounted, and the ladder was re-derived (1.2/1.3).
      The overlap histogram over the same 80 runs is `{0 concurrent: 69, 1: 11}` — 11 of 80 DID
      queue — so "dispatch jobs do not queue behind merges in practice" is retired: worst-case wait
      for an emergency dispatch behind a routine merge apply is now 45 min.

## Phase 1 — Extract the ARM gate, then change its contracts

- [x] **1.1** Extract the ARM gate's bash from the workflow into
      `apps/web-platform/infra/arm-heartbeats.sh`, following the house precedent
      (`web-private-nic-guard.sh`). Parameterise the clock and the HTTP call so a test can inject
      fakes. Keep behaviour identical in this step — extraction first, changes after.
- [x] **1.2** *(implemented as **39**, not 30. Superseded twice: to 35 at implementation, because
      the plan sized its ladder from the reachable Σ while writing AC3's guard against the nominal Σ
      (`measurements.md` §0.3(a)); then to 39 at review-resolution, because the INEQUALITY itself
      was the wrong shape — see 1.3.)*
      Raise the `apply` job's `timeout-minutes` from 15 and rewrite the adjacent
      comment: it currently claims the 15 "matches `apply-deploy-pipeline-fix.yml`", whose apply job
      is actually **90**. Cite the two-part inequality and the measured pre-gate instead.
- [x] **1.3** Add a step-level `timeout-minutes` to the ARM gate satisfying
      `arm_step_timeout ≥ Σdeadlines × 1.1` and
      `job_timeout − arm_step_timeout ≥ p95 pre-gate` (≈27 min against a 30 min job).
      *(implemented as **33 min against a 39 min job**, with BOTH terms re-derived at
      review-resolution (#7657 D1/D3/D4):*
      *(1) `Σ × 1.1` was a multiplier applied to per-CALL-SITE additive overhead — four
      `curl --max-time 15` round-trips plus one poll interval, 70 s per arm whatever the deadline —
      and it broke at ≥ 9 s of vendor round-trip. Now `step ≥ Σ(deadline_i + 70)`:
      1980 ≥ 1510 + 6 × 70 = 1930.*
      *(2) the old term budgeted only the PRE-gate window, leaving 129 s for the re-pause sweep,
      the bridge teardown and the post-apply summary combined — on the one step whose work
      correlates with the ARM step having been cut. Now `job − step ≥ pre-gate + post-gate`:
      2340 − 1980 = 360 ≥ 111 + 180 = 291. The sweep also gained its own `timeout-minutes: 3`.*
      *`111` is the pre-gate MAXIMUM over n = 42, not a p95 — the earlier "p95 = 111" was a
      max-of-6 mislabelled — and it is machine-pinned in `measurements.md` so the guard and the
      measurement cannot drift. The inequality is what the guard asserts, and it now reads every
      term out of the script rather than restating literals.)*
- [x] **1.3b** *(added at review-resolution, #7657 D5.)* Correct the deadline formula's rollback
      reserve from 10 s to 40 s (`ARM_POLL_INTERVAL_S + 2 × ARM_CURL_MAX_TIME_S`): at ≥ 2 s of
      Better Stack round-trip the old reserve re-paused the monitor AFTER its first absence alert
      had fired. `web_zot_consumer` 230 → **200**, `web_nic_guard` 470 → **440**, `git_data_prd`
      230 → **200**. ADR-117's formula amended; the guard re-derives each deadline from the
      monitor's own `period` + `grace` in the `.tf` source.
- [x] **1.4** Fix the wall-clock accounting inside `arm-heartbeats.sh`: the loop counter must advance
      by measured elapsed time, not by its `sleep 10` alone. Today the per-iteration
      `curl --max-time 15` is uncounted, so a 230 s nominal deadline can consume up to 575 s.
- [x] **1.5** Resize the `inngest_consumer` deadline from 230 to **exactly 30**. Change no other
      deadline.
- [x] **1.6** Rewrite the `arc == 2` warning — do **not** retain it. Its text says "no beat within
      230s" and "the probe or the private-net path is broken"; after the resize both are false and a
      *healthy* feeder emits it ~5 runs in 6. Carry the deadline from the variable, drop the
      probe-is-broken instruction, and emit the monitor's `status` and last-beat timestamp so
      *never beat* and *beat not due in-window* are distinguishable from one event.
- [x] **1.7** Add the state file: append `<id>` to `$RUNNER_TEMP/armed-unconfirmed` immediately after
      a successful `PATCH {paused:false}`; remove it **only** on a 2xx rollback `PATCH` or on
      reaching `up`. Removing on "rollback attempted" drops a failed rollback's id and defeats the
      sweep.
- [x] **1.8** Declare `set +e` explicitly, guard every rollback `PATCH` with `|| true`, and use
      `x=$(( … ))` never bare `(( … ))`. Errexit is inherited and `set -uo pipefail` does not clear
      it; an unguarded `rollback_all` aborts at the first 5xx and silently truncates.
- [x] **1.9** Do **not** add a `trap` (Cut List C6): bash keeps only the last `EXIT` handler, an
      `INT`/`TERM` handler returns and then fires `EXIT` too, and the handler is deferred until the
      foreground `sleep` returns.

## Phase 2 — The rollback sweep

- [x] **2.1** Add a named step `- name: Re-pause any monitor left unconfirmed`, gated
      `if: always()`, after the ARM gate and before `Tear down cloudflared SSH bridge`.
- [x] **2.2** First line, **before** any Doppler read:
      `[[ -s "$RUNNER_TEMP/armed-unconfirmed" ]] || exit 0`. The step runs on every apply including
      `ssh_apply_skip` runs; without this it re-mints a credential it does not need and raises a
      mint-failure alarm on runs with no work — a false alarm wired into the new email channel.
- [x] **2.3** Give it `env: { DOPPLER_TOKEN_WEB_ARM: … }`, re-mint `BETTERSTACK_API_TOKEN`, and
      `printf '::add-mask::%s\n'` the result. `BS_TOKEN` is derived inside the ARM step and is
      invisible to a sibling step. Keep the mint and the mask adjacent; never `set -x`.
- [x] **2.4** Re-PATCH `paused:true` idempotently for every listed id, with `set +e` and `|| true`.
- [x] **2.5** **`exit 1`** when the state file is non-empty AND (the mint failed OR any re-pause
      `PATCH` was non-2xx). `::error::` does not fail a step — an annotating sweep leaves the job
      green, the notify predicate false, and nobody emailed.
- [x] **2.6** On a successful fire, write armed / fired / outcome counts where the notify body reads
      them. Re-pausing a production uptime monitor on an otherwise-green run must reach the
      operator, not just a run log.

## Phase 3 — The failure channel

- [x] **3.1** Add `notify-apply-failure` with `needs: [preflight, apply]` and `timeout-minutes: 5`.
- [x] **3.2** Predicate: true unless everything is fine. It must cover a failed `preflight` (which
      leaves `apply` **skipped** on a red run) and must admit
      `inputs.apply_target == 'manual-rerun'` (the recovery path the email itself prescribes). A
      `push`-only, `needs.apply.result`-only predicate misses both.
- [x] **3.3** Job-level `permissions: { contents: read, actions: read }` — a job-level block
      **replaces** the workflow-level one, so `contents: read` must be re-declared. `actions: read`
      is the minimum for `…/actions/runs/<id>/jobs`.
- [x] **3.4** Named `cause` step resolving the failing step's name from the jobs API. Do **not** read
      `apply` step outputs — that job declares no `outputs:`, and job outputs are unreliable on the
      cancelled path anyway.
- [x] **3.5** Sanitize the cause token: strip `\r`/`\n`, reject outside
      `[A-Za-z0-9 ._:()/-]{1,80}`, HTML-escape `&`/`<`/`>`, and use a random `$GITHUB_OUTPUT`
      heredoc delimiter (a newline otherwise forges outputs and spoofs annotations).
- [x] **3.6** Named `notify-ops-email` step with `continue-on-error: true`.
- [x] **3.7** Body to the `#7539` bar: plain-language blast radius; a branch on
      `needs.apply.result == 'cancelled'` with per-outcome guidance for **both** arms; the failing
      step's name; whether uptime alerting may be paused; that the previously-applied infrastructure
      is still serving; the sweep's counts when it fired; and a fenced
      `gh workflow run … -f apply_target=manual-rerun` block.
- [x] **3.8** Keep the body in `with: body:` — **no `run:` body in this job may contain
      `terraform apply` or `-target=`**. The predicate names `manual-rerun`, so
      `stock-preflight-coverage.test.ts`'s `jobFor("manual-rerun")` returns two hits and
      disambiguates by `appliesTerraform`; either token makes that suite red.
- [x] **3.9** Enforce the interpolation allow-list: workflow-context scalars plus the `cause` token
      only. Never raw step logs, `curl` output or a shell trace.
- [x] **3.10** Add a one-line comment in the workflow pointing at the guard suite.

## Phase 4 — Records

- [x] **4.1** Amend `ADR-117` with a dated section covering (a) the deliberate departure from
      `period + grace − 10` for `inngest_consumer` and its bounded cost, and (b) the already-shipped
      `arc == 2` soft-landing. Do **not** fold in the unrelated `triggers_replace` divergence.
- [x] **4.2** Update `model.c4`'s `github -> betterstack` edge to name the ARM gate's
      `PATCH /api/v2/heartbeats/<id>` write under `DOPPLER_TOKEN_WEB_ARM`. Leave `github -> resend`
      alone (C10). Run the c4 syntax + render suites.
- [x] **4.3** Extend `plugins/soleur/lib/heartbeat-manifest.ts`'s `arming_pending` comment on the
      `inngest_consumer` row to record the probabilistic arming window and to state that removal
      must follow **observed** arming. The row stays — removing it is #7462 step 6.
- [x] **4.4** Update the `registry_luks_recut` mutex-accounting comment for the new 35-min run-level
      worst case.

## Phase 5 — Guards (written from the design, not the code)

- [x] **5.1** Add `apps/web-platform/infra/arm-heartbeats.test.sh` with an injected fake clock and
      fake `curl`, driving Guard 2 rows 6-9 behaviourally.
- [x] **5.2** **Register it** in `apps/web-platform/infra/run-registered-suites.sh`.
      `scripts/lint-orphan-test-suites.sh` enumerates `git ls-files '*.test.sh'` repo-wide, so an
      unregistered new `.test.sh` is an orphan by construction.
      *(PATH CORRECTED at implementation — the plan is authoritative for intent, never for paths.
      `run-registered-suites.sh` does not carry a suite list: it DERIVES one by grepping
      `run: bash apps/web-platform/infra/*.test.sh` out of `.github/workflows/infra-validation.yml`.
      Registering it in the runner is therefore impossible; the step was added to
      `infra-validation.yml` (job `deploy-script-tests`) instead, which is the single surface the
      orphan lint recognises. Registering it in BOTH would also be an error — that linter treats a
      suite covered by more than one surface as a finding. Verified: `--list` now derives 101
      suites including this one, and `lint-orphan-test-suites.sh` reports
      `walked 363 tracked *.test.sh … 363 covered, 0 orphaned`.)*
- [x] **5.3** In `plugins/soleur/test/terraform-target-parity.test.ts`: add the shared
      `expectNonEmptyDispatch` helper and a header note that this suite also owns the apply
      workflow's channel and budget invariants.
- [x] **5.4** Guard 1 — `describe("apply-web-platform-infra has a failure channel")`. Extract the
      `if:` expression and **evaluate** it over `{success,failure,cancelled,skipped}² ×
      {push,manual-rerun,other}`, asserting the truth table. Do not string-match: a canonical-string
      match makes H2 fail by construction, a token-presence check passes rows 1/3/4 over a broken
      predicate. Pin `needs` to equal `["preflight","apply"]` **in the same test** — otherwise
      dropping `preflight` from both `needs:` and the predicate reds neither guard (row 5).
- [x] **5.5** Guard 2 — `describe("the ARM gate's deadlines fit its job")`. Assert the two-part
      inequality, the step timeout strictly below the job's, and the sweep identified by
      `if: always()` co-located with the state-file literal (**not** by step name — a rename would
      false-RED).
- [x] **5.6** Leave `describe("the ssh_token_gate green-skip has a channel (#7539)")`
      **byte-identical**. Its passing untouched is the regression signal that the new job did not
      disturb the old arm.
- [x] **5.7** Execute every row of both mutation matrices and both harness tables against the real
      implementation; record each verdict in `measurements.md`. A guard that cannot be driven RED is
      vacuous.

## Phase 6 — Verification

- [x] **6.1** Run the full bound set from AC8, naming each suite explicitly because a touched-file
      selection reaches only the first: `terraform-target-parity`, `stock-preflight-coverage`,
      `test-preapply-entrypoint-gate.sh`, `test-vector-redeliver-wiring.sh`,
      `web-1-swap-concurrency-parity.test.sh`, `arm-heartbeats.test.sh`, the c4 suites,
      `lint-workflow-errexit-capture.py`, `lint-orphan-test-suites.sh`, and
      `lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own invocation over
      the changed set, never a hand-enumerated path list).
- [x] **6.2** `actionlint` the workflow; check each new/edited `run:` snippet with
      `bash -c '<snippet>'` — never `bash -n` on the `.yml`.
- [x] **6.3** Walk every acceptance criterion (AC1-AC10 incl. AC2b/AC2c/AC4b/AC6b) and record its
      evidence in `measurements.md`.
- [ ] **6.4** PR body carries `Closes #7586` and `Closes #7587`, no `Closes` for #7228, and names
      **both** observability layers (job conclusions → `notify-ops-email` → Resend → ops@; and
      Better Stack heartbeat armed/paused state).
- [ ] **6.5** Confirm `/ship` renders `decision-challenges.md` into the PR body and files the
      `action-required` issue, and that the Deferrals tracking issue (default notification posture +
      the deferred de-duplication) is filed with its re-evaluation criterion.

## Phase 7 — Post-merge (automated)

- [ ] **7.1** `/ship` dispatches
      `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun
      -f reason='verify #7586/#7587 fix'` and asserts the resulting `apply` job's ARM step ran
      **< 60 s**, read from `gh api repos/:owner/:repo/actions/runs/<id>/jobs`. No human step.
