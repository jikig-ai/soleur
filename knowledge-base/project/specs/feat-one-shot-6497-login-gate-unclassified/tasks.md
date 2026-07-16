# Tasks — #6497 drain the `unclassified` dead-end in the docker-login gate

Derived from `knowledge-base/project/plans/2026-07-16-fix-login-gate-unclassified-dead-end-plan.md`.
Threshold: `single-user incident` → CPO sign-off + `user-impact-reviewer` at review.

**Prime directive (learning §9):** every catch in this class has been an **execution**, not a
reading. Measure; do not derive. Prove each new assertion RED before green.

---

## Phase 0 — Preconditions (measure before building)

- [ ] 0.1 Determine the docker version actually on web-1 (deploy-status webhook payload, or the
      `docker-ce` apt candidate inside `docker run --rm ubuntu:24.04`). Record it in the PR body.
- [ ] 0.2 Re-run the discrimination battery on that version: live `registry:2` on
      `localhost:15999`, then for each mode capture rc / stdout_len / stderr_len / stderr:
      unroutable host · real 401 · broken `credsStore` helper · unwritable config dir ·
      corrupt config.json · disk-full cred write · non-TTY · dead `DOCKER_HOST`.
- [ ] 0.3 Feed every captured string through the **real** `_zot_login_failure_class`
      (`ci-deploy.sh:661-676`). Diff the result against the plan's table.
      **Any divergence amends the plan, not the test.**
- [ ] 0.4 Confirm harness extension points: `run_deploy_zot_login_stderr` (`ci-deploy.test.sh:3434`),
      `assert_zot_login_class` (`:3458`), `MOCK_ZOT_LOGIN_FAIL_STDERR` (`:3445`),
      `MOCK_SENTRY_CAPTURE_FILE`.
- [ ] 0.5 Confirm registration: `infra-validation.yml:344` runs `bash apps/web-platform/infra/ci-deploy.test.sh`.

## Phase 1 — RED: write the failing tests first (`cq-write-failing-tests-before`)

- [ ] 1.1 `assert_ghcr_login_class` — mirror `assert_zot_login_class`; add a
      `MOCK_GHCR_LOGIN_FAIL_STDERR` arm to the docker mock. **Body-scoped** to the GHCR payload
      (precedent: `assert_pull_failure_host_id` `:1076`).
- [ ] 1.2 RED: empty stderr → `class=unclassified stderr_len=0`; unmatched non-empty stderr →
      `class=unclassified stderr_len=<true len>`; assert the two payloads **differ** (AC4).
- [ ] 1.3 RED: >400-byte stderr → `stderr_len` > 400 (AC5 — true length, not `tail -c 400`).
- [ ] 1.4 RED: measured EACCES string → `cred_store`, not `transport` (AC6).
- [ ] 1.5 RED: stderr carrying a synthetic credential-shaped token + username → payload contains
      neither; every `kw`/`tok` value ∈ closed allow-list (AC3).
- [ ] 1.6 RED: GHCR class rides both PRELUDE lines + the Sentry event (AC8).

## Phase 2 — GREEN: implement

- [ ] 2.1 Rename `_zot_login_failure_class` → `_docker_login_failure_class` (registry-neutral);
      sweep every call site. Same for `_zot_login_http_status` naming if it reads zot-specific.
      **Do not fork a second classifier.**
- [ ] 2.2 Add the `cred_store` arm — literals `error saving credentials|error storing
      credentials|error getting credentials` **only** (measured). Place **before** `transport`.
- [ ] 2.3 `stderr_len` from `wc -c < "$zerr"` (**true** length); `tok` from `head -c` on the
      file (**not** the `tail -c 400` string); `kw` from fixed `grep -q` probes each emitting a
      hardcoded literal.
- [ ] 2.4 `tok` closed allow-list (`error|Error|time|Cannot|WARNING|failed|denied|unauthorized`),
      default `other`. **Never a raw first token.**
- [ ] 2.5 Escape hatch fires **only** when `class=unclassified`, at **both** sites.
- [ ] 2.6 GHCR sites `:803` + `:746`: capture stderr to a `0600` temp, classify, emit; `rm -f` on
      **both** branches. Keep `--password-stdin`; keep the token out of argv and child env.
- [ ] 2.7 `${x:-}` at **every** new expansion site — a **precondition**, never a downstream
      correction. `||` does not catch an expansion error under `set -u`.
- [ ] 2.8 Thread the new fields into `zot_gate_degraded_event`'s `jq -n` payload + the PRELUDE
      log lines.

## Phase 3 — Mutation battery (AC9 — relocation, not deletion)

- [ ] 3.1 Move `cred_store` after `transport` → 1.4 must go RED.
- [ ] 3.2 Swap `stderr_len` for the truncated length → 1.3 must go RED.
- [ ] 3.3 Swap `tok` for a raw first-token passthrough → 1.5 must go RED.
- [ ] 3.4 Point `assert_ghcr_login_class` at the zot payload → 1.6 must go RED (proves
      body-scoping; an unscoped grep is satisfied by a sibling emit).
- [ ] 3.5 Revert every mutation; confirm green.

## Phase 4 — Behavioural verification on the shipped image (AC2)

- [ ] 4.1 `docker run --rm ubuntu:24.04` — run the gate with **each** new variable unset in turn;
      assert the telemetry line still renders and the script does not abort under `set -euo pipefail`.
- [ ] 4.2 Not by inspection. The 2026-07-15 #1 P1 was an expansion that killed the line it rode on
      while its guards sat 8 lines below, unreachable.

## Phase 5 — Comment truth-up (learning §Session-Error-13)

- [ ] 5.1 `ci-deploy.sh:652-655` — "ordering is NOT load-bearing" is falsified by 2.2. State the
      measured overlap; name the test that pins it.
- [ ] 5.2 `ci-deploy.sh:648-650` — re-point the H4 note at this plan.
- [ ] 5.3 `ci-deploy.sh:725-750`, `:762-763` — refetch/prelude headers assert stderr handling that
      2.6 changes.
- [ ] 5.4 `zot-registry.tf:108-109` + `:332` — **comment-only.** Delete the falsified claim that the
      htpasswd edge was WEB-PLATFORM-5B; keep the true rotation-convergence rationale. Do not
      contradict it in an adjacent sentence — delete it.
- [ ] 5.5 3-line dated addendum to `2026-07-15-false-comment-…-restated-it.md`: root cause
      falsified by run 29482827061; the lesson stands.
- [ ] 5.6 Sweep: for every comment in the diff's hunks asserting a behaviour/security property,
      confirm the property holds (AC10).

## Phase 6 — Issue hygiene

- [ ] 6.1 Re-title #6497 → `P1: zot/GHCR docker-login gate cannot name its own failure —
      class=unclassified is ≥4 modes (WEB-PLATFORM-5B)`; comment the falsification (AC10 green,
      **AC11 red**, exactly as the body predicted).
- [ ] 6.2 Comment on #6416: closure legitimate for its true scope (condition 2 of 3); **title**
      over-claimed "end-to-end" on a push-only gate. Point at #6497 + #6122. **Do not reopen.**
- [ ] 6.3 File the repair follow-up (blocked on this PR) carrying H-A..H-D + the measured table.
- [ ] 6.4 Keep #6500 distinct — do not fold in.
- [ ] 6.5 PR body: `Ref #6497` (**not** `Closes`) — the closure criterion is AC13, post-merge.

## Phase 7 — Exit

- [ ] 7.1 `bash apps/web-platform/infra/ci-deploy.test.sh` fully green (AC12).
- [ ] 7.2 AC7: `git grep -n 'docker login' apps/web-platform/infra/ci-deploy.sh | grep -c '2>&1'` → `0`.
- [ ] 7.3 PR body states: `ci-deploy.sh` applies on merge via `apply-deploy-pipeline-fix.yml`
      (`on: push`, `paths:` `:66`, apply job `:183`); the `zot-registry.tf` comment-only edit
      triggers `apply-web-platform-infra.yml` and **applies nothing** (per-PR `-target` excludes
      every zot resource; comments yield no plan diff).
- [ ] 7.4 `/ship` renders `decision-challenges.md` (UC-1, UC-2) into the PR body + files
      `action-required`.
