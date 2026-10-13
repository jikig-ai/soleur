# Tasks — #6497 drain the `unclassified` dead-end in the docker-login gate

Derived from `knowledge-base/project/plans/2026-07-16-fix-login-gate-unclassified-dead-end-plan.md`.
Threshold: `single-user incident` → CPO sign-off + `user-impact-reviewer` at review.

**Prime directive (learning §9):** every catch in this class has been an **execution**, not a
reading. Measure; do not derive. Prove each new assertion RED before green.

---

## Phase 0 — Preconditions (measure before building)

- [x] 0.1 Determine the docker version actually on web-1 (deploy-status webhook payload, or the
      `docker-ce` apt candidate inside `docker run --rm ubuntu:24.04`). Record it in the PR body.
- [x] 0.2 Re-run the discrimination battery on that version: live `registry:2` on
      `localhost:15999`, then for each mode capture rc / stdout_chars / stderr_chars / stderr:
      unroutable host · real 401 · broken `credsStore` helper · unwritable config dir ·
      corrupt config.json · disk-full cred write · non-TTY · dead `DOCKER_HOST`.
- [x] 0.3 Feed every captured string through the **real** `_zot_login_failure_class`
      (`ci-deploy.sh:661-676`). Diff the result against the plan's table.
      **Any divergence amends the plan, not the test.**
- [x] 0.4 Confirm harness extension points: `run_deploy_zot_login_stderr` (`ci-deploy.test.sh:3437`),
      `assert_zot_login_class` (`:3455`), the `MOCK_ZOT_LOGIN_FAIL_STDERR` docker-mock arm
      (`:289-296`), `MOCK_SENTRY_CAPTURE_FILE` (`create_curl_mock` `:433-460`),
      `MOCK_LOGGER_CAPTURE_FILE`, and the leak-canary precedent T-5B-8 (`:3583`) / T-5B-8b (`:3600`).
- [x] 0.5 Confirm registration: `infra-validation.yml:344` runs `bash apps/web-platform/infra/ci-deploy.test.sh`.
      Note the job is **advisory, not a required check** (`:339`, tracked by #6480) — a green suite
      does not block merge, which is why the Phase 3 mutation battery carries the weight here.
- [x] 0.6 Record the green baseline: the suite is currently **153/153**. Any new test must move
      that denominator.

## Phase 1 — RED: write the failing tests first (`cq-write-failing-tests-before`)

- [x] 1.1 `assert_ghcr_login_class` — mirror `assert_zot_login_class` (`:3455`). Add a
      `MOCK_GHCR_LOGIN_FAIL_STDERR` arm to the docker mock (`:289-296`), **registry-scoped to
      `_lreg == "ghcr.io"`** — the zot arm's scoping is load-bearing and must not be perturbed.
      Body-scoped to the GHCR sink (precedent: `assert_pull_failure_host_id` `:1076`).
- [x] 1.2 RED: `stderr_chars=0 stdout_chars>0` (H-B-stdout) vs `stderr_chars=0 stdout_chars=0`
      (H-B-nowhere) vs `stderr_chars>0` — assert all three emit **distinct** shapes (AC4).
- [x] 1.3 RED: `rc` rides every failed login; `rc=127` on a docker-absent fixture (AC4).
- [x] 1.4 RED: measured EACCES → `cred_store` not `transport`; measured `504` → `server_error`
      not `transport` (AC6). **Shipped as T-5B-12**, both cases proven RED by AC9 M1/M2
      (relocate the arm after `transport` → 161/164 and 163/164). The `cli_daemon` clause is
      VOID: the arm was retired at Phase 0 when measurement showed `docker login` never contacts
      the daemon socket, so there is no shape to assert (plan Research Reconciliation 10).
- [x] 1.5 RED: **through the `unclassified` path** — stderr carrying a synthetic credential +
      username reaches **neither** the Sentry capture **nor** the whole journald capture; every
      `kw`/`tok` ∈ the closed set (AC3b). Extends T-5B-8/8b, which drive a **401** and therefore
      **never execute the hatch**.
- [x] 1.6 RED (structural): no parameter expansion in any `printf` argument in the emitter —
      `grep -nE 'printf[^#]*\$'` over the emitter body → zero (AC3a).
- [x] 1.7 RED: fuzz — 200 fixtures with high-entropy random **first tokens**; emitted `tok` ∈ the
      closed set on every one (AC3b). This is what makes the AC9 passthrough mutation reliably
      RED; against a single fixture it is vacuous.
- [x] 1.8 RED: GHCR class rides **both** PRELUDE lines (`:803` baked-cred AND `:746`
      post-refetch) (AC8).
- [x] 1.9 RED: `refetch_ghcr_and_relogin`'s stdout is byte-exactly one of
      `recovered|refetch_unavailable|relogin_failed` **with the hatch firing** — and the rendered
      `logger` line contains no byte of the stderr (Phase 3 P0).

## Phase 2 — GREEN: implement

- [x] 2.1 Rename `_zot_login_failure_class` → `_docker_login_failure_class` and
      `_zot_login_http_status` → `_docker_login_http_status`; sweep every call site.
      **Do not fork a second classifier.**
- [x] 2.2 Arms, **each anchored only on AC1-measured literals**, ordered so every precedence
      relation is test-pinned: `cred_store` (`error saving|storing|getting credentials`) and
      `cli_daemon` (`docker.sock|unix://|_ping`) both **before** `transport`; `server_error`
      **before** `transport` (or anchor transport's timeout terms) so `504` stops landing in
      `transport`. **If AC1 cannot reproduce a string, no arm ships for it** — it stays a `kw` probe.
- [x] 2.3 **Variable capture, not `mktemp`** (Phase 2b): `zerr="$( ( … 2>&1 >/dev/null ) )" || zrc=$?`
      at all 3 sites. `local` and the assignment are **separate statements**. `2>&1 >/dev/null` in
      **that order**. Field is `stderr_chars` (`${#zerr}` counts chars, not bytes, under UTF-8).
- [x] 2.4 `tok` = **Form B** `case` with hardcoded-literal arms and **pattern** matches
      (`error*`, `time=*`, `WARNING*`, `Cannot*`, …), default `other`. **Never Form A** (a regex
      filter that emits `$t`) — same output set, but degrades to disclosure instead of a wrong label.
- [x] 2.5 `kw` probes enumerated from the **measured** table: `no space left on device`,
      `executable file not found`, `docker-credential`, `permission denied`, `error saving/storing
      credentials`, plus the three falsified tokens (free under Form B).
- [x] 2.6 **Hatch fires on EVERY failed login**, both sites — not `unclassified`-only (UC-3).
- [x] 2.7 **Emit the hatch from a subshell** — `( … ) || true` — the only construct that contains
      **both** abort classes. Plus `${x:-}` at every new expansion site (discipline, not mechanism).
- [x] 2.8 GHCR class → **journald only** (no new Sentry emit source; quota). Zot beacon keeps its
      Sentry event; rename its tags `login_class`/`login_http` + add a `registry: zot|ghcr`
      discriminator. `stderr_chars` goes in `extra`/context, **not** `tags` (cardinality).
- [x] 2.9 Nothing inside `refetch_ghcr_and_relogin` may write to stdout except the three stage
      literals; class returns via a named global (mirror `RECOVERY_STAGE`). **Never `2>&1` at the
      function level.**

## Phase 3 — Mutation battery (AC9 — relocation, not deletion)

- [x] 3.1 Move `cred_store` after `transport` → 1.4 RED.
- [x] 3.2 Move `server_error` after `transport` → the 504 case in 1.4 RED.
- [x] 3.3 Swap `tok` Form B → Form A raw passthrough → 1.6 (structural) **and** 1.7 (fuzz) RED.
- [~] 3.4 Remove the Phase 2b subshell → AC2(b) RED. **RUN, AND THE FALSIFIER IS FALSE — 164/164
      GREEN.** Two measurements say why: (i) the emitters ship on `case`, which returns 0 on a
      no-match, so the plan's `grep -q` abort vector does not exist — designed out at the root
      rather than contained; (ii) the plan's abort is real but TOP-LEVEL only — the same code
      inside a function invoked through `$( )` does not abort, which is how all 3 sites call it.
      An unreachable failure mode cannot be observed behaviourally, so the gap the battery
      exposed (deleting the subshell was INVISIBLE) is closed structurally by **T-5B-19**, which
      goes RED on this exact mutation (164/165, `wrapped=2`).
- [x] 3.5 Emit the GHCR class on `refetch_ghcr_and_relogin`'s **stdout** → the existing
      `recovered` stage assertions RED.
- [x] 3.6 Point `assert_ghcr_login_class` at the zot payload → 1.8 RED (proves body-scoping).
- [x] 3.7 Revert every mutation; confirm 153/153 + the new cases green.

## Phase 4 — Behavioural verification (AC2)

- [ ] 4.1 **Surface: the existing `ubuntu-24.04` GH runner** (`infra-validation.yml`
      `deploy-script-tests`), which already matches `server.tf:111`'s host image. **Do NOT add a
      `docker run --rm ubuntu:24.04` leg** — zero repo precedent; the runner is the sanctioned
      surface. (AC1's docker-version measurement is the exception and keeps its own reading.)
- [~] 4.2 Inject **both** abort classes. **Premise retired by the implementation, same as 3.4.**
      (b) has no injection site: there is no `grep -q` and no `wc` in the emitter path (`case` +
      `${#var}` only). (a) has none either: every new expansion is `${x:-}`-defaulted, verified
      by grep. Containment is pinned by T-5B-19 instead; the CONTRACT it protects ("a telemetry
      failure must never abort a deploy") is stated at `ci-deploy.sh` › `_login_hatch()`.
- [ ] 4.3 Not by inspection. The 2026-07-15 #1 P1 was an expansion that killed the line it rode
      on while its guards sat 8 lines below, unreachable.

## Phase 5 — Comment truth-up (learning §Session-Error-13)

- [x] 5.1 `ci-deploy.sh:652-655` — "ordering is NOT load-bearing" is falsified by 2.2. State the
      measured overlap; name the test that pins it.
- [x] 5.2 `ci-deploy.sh:648-650` — re-point the H4 note at this plan.
- [x] 5.3 `ci-deploy.sh:725-750`, `:762-763` — refetch/prelude headers assert stderr handling that
      2.6 changes.
- [x] 5.4 `zot-registry.tf:108-109` + `:332` — **comment-only.** Delete the falsified claim that the
      htpasswd edge was WEB-PLATFORM-5B; keep the true rotation-convergence rationale. Do not
      contradict it in an adjacent sentence — delete it.
- [x] 5.4b `ci-deploy.sh:636-647` — **falsified by the RENAME, not by the diff's logic.** The
      zot-measured *"NEVER 403 → `authz_denied` unreachable → defensive tripwire"* claim is false
      for GHCR, which **does** 403 (SAML/SSO, org policy, IP allow-lists). Split into a
      registry-neutral preamble + a `## Per-registry measured behaviour` subsection; the `ghcr.io:`
      paragraph says **`unmeasured`** unless AC1 measures it.
- [x] 5.4c `ci-deploy.sh:643-644` — conflates ICMP-admin-prohibited EACCES with **unix-socket**
      EACCES (both render `connect: permission denied`); `cli_daemon` makes it false.
- [x] 5.4d Any comment about `$zerr`'s mode: say *"`mktemp` creates it 0600"*, never *"we chmod
      it"* — there is no `chmod` there. Moot if Phase 2b's variable capture lands (no file at all).
- [ ] 5.5 3-line dated addendum to `2026-07-15-false-comment-…-restated-it.md`: root cause
      falsified by run 29482827061; the lesson stands.
- [x] 5.6 Sweep: for every comment in the diff's hunks asserting a behaviour/security property,
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

- [x] 7.1 `bash apps/web-platform/infra/ci-deploy.test.sh` fully green (AC12).
- [x] 7.2 AC7: `git grep -n 'docker login' apps/web-platform/infra/ci-deploy.sh | grep -c '2>&1'` → `0`.
- [ ] 7.3 PR body states: `ci-deploy.sh` applies on merge via `apply-deploy-pipeline-fix.yml`
      (`on: push`, `paths:` `:66`, apply job `:183`); the `zot-registry.tf` comment-only edit
      triggers `apply-web-platform-infra.yml` and **applies nothing** (per-PR `-target` excludes
      every zot resource; comments yield no plan diff).
- [ ] 7.4 `/ship` renders `decision-challenges.md` (UC-1, UC-2) into the PR body + files
      `action-required`.
