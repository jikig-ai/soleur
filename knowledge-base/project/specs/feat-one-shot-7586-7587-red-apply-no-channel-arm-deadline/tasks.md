# Tasks — feat-one-shot-7586-7587-red-apply-no-channel-arm-deadline

Derived from
[`knowledge-base/project/plans/2026-08-20-fix-apply-infra-failure-channel-and-arm-deadline-plan.md`](../../plans/2026-08-20-fix-apply-infra-failure-channel-and-arm-deadline-plan.md)
after plan review. Closes **#7586** and **#7587**. Incident **#7228** is context only and is **not**
a work target — do not close it.

`lane: cross-domain` (no `spec.md` on this branch; fail-closed default per TR2).

**Phase order is load-bearing.** Phase 1 changes contracts the later phases assert on; the guard in
Phase 4 is written from the design in Phase 0, not from whatever the code ends up looking like.

---

## Phase 0 — Preconditions and the mutation matrix

- [ ] **0.1** Re-read the plan's `## Guard Contract` and write both mutation matrices down before
      touching the workflow. A matrix derived from finished code tests the code that exists; one
      derived from the design tests the property.
- [ ] **0.2** Confirm the four issue states are unchanged since planning:
      `gh issue view 7586 --json state`, `7587`, `7228`, `7462`. If #7228 has closed, revisit the
      §4 deadline resize — the reasoning still holds but the framing changes.
- [ ] **0.3** Capture the pre-change baseline for the AC10 comparison:
      `gh api repos/:owner/:repo/actions/runs/32356859661/jobs` — record the `apply` job duration
      (302 s) and the ARM step duration (240 s) into `measurements.md`.
- [ ] **0.4** Verify the errexit premise directly rather than inheriting it: confirm the ARM step
      declares no `shell:` key, so GitHub invokes it as `/usr/bin/bash -e {0}`. This is the claim
      the plan's first draft got backwards; do not proceed on memory.
- [ ] **0.5** Run the bound suites GREEN before any edit, so a later red is attributable:
      `bun test plugins/soleur/test/terraform-target-parity.test.ts`,
      `bash tests/scripts/test-preapply-entrypoint-gate.sh`,
      `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`.

## Phase 1 — Contract changes in the workflow (before their consumers)

- [ ] **1.1** Raise the `apply` job's `timeout-minutes` from 15 to 30, and rewrite the adjacent
      comment: it currently claims the 15 "matches `apply-deploy-pipeline-fix.yml`", whose `apply`
      job is actually `timeout-minutes: 90`. Cite the in-file mutex-holding precedent (job ceiling
      above, in-script bound strictly below) instead.
- [ ] **1.2** Add a step-level `timeout-minutes` to the ARM gate, strictly below the job's.
- [ ] **1.3** Fix `arm_one`'s wall-clock accounting: the loop counter must advance by measured
      elapsed time, not by its `sleep 10` alone. Today the per-iteration `curl --max-time 15` is
      uncounted, so a 230 s nominal deadline can consume up to 575 s.
- [ ] **1.4** Resize the `inngest_consumer` `arm_one` deadline from 230 to ~30. Change **no other**
      deadline. Retain the `arc == 2` soft-landing branch and its `::warning::`.
- [ ] **1.5** Add the state file: `arm_one` appends `<id>` to `$RUNNER_TEMP/armed-unconfirmed`
      immediately after a successful `PATCH {paused:false}`, and removes it **only** on a 2xx
      rollback `PATCH` or on reaching `up`. Removing on "rollback attempted" would drop a failed
      rollback's id and defeat the sweep.
- [ ] **1.6** Declare `set +e` explicitly in the ARM step, guard every rollback `PATCH` with
      `|| true`, and replace any bare `(( … ))` with `x=$(( … ))`. Errexit is inherited and
      `set -uo pipefail` does not clear it.

## Phase 2 — The rollback sweep

- [ ] **2.1** Add a **named** step `- name: Re-pause any monitor left unconfirmed`, gated
      `if: always()`, positioned after the ARM gate and before `Tear down cloudflared SSH bridge`.
- [ ] **2.2** Give it its own `env: { DOPPLER_TOKEN_WEB_ARM: ${{ secrets.DOPPLER_TOKEN_WEB_ARM }} }`,
      re-mint `BETTERSTACK_API_TOKEN`, and `printf '::add-mask::%s\n'` the result. `BS_TOKEN` is
      derived inside the ARM step and is invisible to a sibling step — without this the sweep runs,
      finds ids, and can PATCH none of them.
- [ ] **2.3** Re-PATCH `paused:true` for every id still listed, idempotently, with `set +e` and
      `|| true` per 1.6. Emit `::error::` naming the credential when the re-mint fails, rather than
      exiting quietly.
- [ ] **2.4** Do **not** add a `trap`. Cut List C6 records why: bash keeps only the last `EXIT`
      handler, an `INT`/`TERM` handler returns and then fires `EXIT` too (double-PATCH), and the
      handler is deferred until the foreground `sleep` returns.

## Phase 3 — The failure channel

- [ ] **3.1** Add the `notify-apply-failure` job with `needs: [preflight, apply]` and
      `timeout-minutes: 5`.
- [ ] **3.2** Write the predicate so it is true unless everything is fine — it must cover a failed
      `preflight` (which leaves `apply` **skipped** on a red run) and must admit the
      `apply_target == 'manual-rerun'` dispatch (the recovery path the email itself prescribes).
      A `push`-only, `needs.apply.result`-only predicate misses both.
- [ ] **3.3** Declare job-level `permissions: { contents: read, actions: read }`. A job-level block
      **replaces** the workflow-level one, so `contents: read` must be re-declared.
- [ ] **3.4** Add a **named** `cause` step resolving the failing step's name from
      `gh api repos/:owner/:repo/actions/runs/${{ github.run_id }}/jobs`, reduced to a sanitized
      token. Do **not** read `apply` step outputs — the `apply` job declares no `outputs:`, and job
      outputs are unreliable on the cancelled path anyway.
- [ ] **3.5** Add the **named** `notify-ops-email` step with `continue-on-error: true`.
- [ ] **3.6** Write the body to the `#7539` arm's quality bar: plain-language blast radius, a branch
      on `needs.apply.result == 'cancelled'` with per-outcome guidance, the failing step's name, a
      line stating that uptime alerting may be paused, a line stating that the previously applied
      state is still serving, and a fenced copy-pasteable
      `gh workflow run … -f apply_target=manual-rerun` block.
- [ ] **3.7** Enforce the interpolation allow-list: workflow-context scalars plus the `cause` token
      only. Never raw step logs, `curl` output or a shell trace.
- [ ] **3.8** Add a one-line comment in the workflow pointing at the guard suite that owns these
      invariants, so the next editor can find it.

## Phase 4 — Guards (written from the design, not the code)

- [ ] **4.1** Add the shared `expectNonEmptyDispatch` helper to
      `plugins/soleur/test/terraform-target-parity.test.ts`, plus a header note that this suite also
      owns the apply workflow's channel and budget invariants.
- [ ] **4.2** Add `describe("apply-web-platform-infra has a failure channel")` implementing Guard 1:
      assert on the `if:` **line** (comment-stripped), the `needs:` array, `timeout-minutes`,
      `permissions`, and `continue-on-error`.
- [ ] **4.3** Add `describe("the ARM gate's deadlines fit its job")` implementing Guard 2: assert
      `sum(arm_one deadlines) < apply_timeout_seconds − 62`, the step-level timeout strictly below
      the job's, the sweep step's presence and `always()` gate, and the elapsed-time accounting.
- [ ] **4.4** Leave `describe("the ssh_token_gate green-skip has a channel (#7539)")`
      **byte-identical**. Its passing untouched is the regression signal that the new job did not
      disturb the old arm.
- [ ] **4.5** Execute every row of both mutation matrices and both harness tables against the real
      implementation; record each verdict in `measurements.md`. A guard that cannot be driven RED is
      vacuous.

## Phase 5 — Records

- [ ] **5.1** Amend `ADR-117-executable-heartbeat-arming.md` with a dated section covering (a) the
      deliberate departure from `period + grace − 10` for `inngest_consumer` and its bounded cost,
      and (b) the already-shipped `arc == 2` soft-landing. Do **not** fold in the unrelated
      `triggers_replace` doc/code divergence.
- [ ] **5.2** Update `model.c4`'s `github -> betterstack` edge description to name the ARM gate's
      `PATCH /api/v2/heartbeats/<id>` write under `DOPPLER_TOKEN_WEB_ARM`. Leave `github -> resend`
      alone. Run the c4 syntax + render suites.

## Phase 6 — Verification

- [ ] **6.1** Run the full bound set from AC8, naming each suite explicitly because a touched-file
      selection reaches only the first: `terraform-target-parity`, `stock-preflight-coverage`,
      `test-preapply-entrypoint-gate.sh`, `test-vector-redeliver-wiring.sh`,
      `web-1-swap-concurrency-parity.test.sh`, the c4 suites,
      `lint-workflow-errexit-capture.py`, and
      `lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own invocation over
      the changed set, never a hand-enumerated path list).
- [ ] **6.2** `actionlint` the workflow, and check each new/edited `run:` snippet with
      `bash -c '<snippet>'` — never `bash -n` on the `.yml`.
- [ ] **6.3** Walk every acceptance criterion and record its evidence in `measurements.md`.
- [ ] **6.4** Confirm the PR body carries `Closes #7586` and `Closes #7587`, no `Closes` for #7228,
      and names the observability layer (GitHub Actions job conclusions → `notify-ops-email` →
      Resend → `ops@jikigai.com`).
- [ ] **6.5** Confirm `/ship` will render
      `knowledge-base/project/specs/<branch>/decision-challenges.md` into the PR body and file the
      `action-required` issue, and that the Deferrals tracking issue (default notification posture
      + the deferred de-duplication) is filed with its re-evaluation criterion.

## Phase 7 — Post-merge (automated)

- [ ] **7.1** `/ship` dispatches
      `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun
      -f reason='verify #7586/#7587 fix'` and asserts the resulting `apply` job's ARM step ran
      **< 60 s**, read from `gh api repos/:owner/:repo/actions/runs/<id>/jobs`. No human step.
