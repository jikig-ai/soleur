# Tasks — fix(ci): bound the in-container apt cycle in the git-data suites (#9379)

Plan: knowledge-base/project/plans/2026-10-01-fix-git-data-suites-bound-apt-wallclock-route-expiry-to-skip-plan.md

## Phase 0 — Evidence capture (read-only)
- [x] 0.1 Record `.meta` rc/seconds for rehearsal and ownership from run 36885018496 and the next failing run on this branch
- [x] 0.2 Derive (do not carry) the in-container apt site count and the worst-case serial container count in the rehearsal suite (12 expected)
- [x] 0.3 Re-derive total declared-skip cost on a total stall vs `_SKIP_CEILING=10` (four `did-not-run) arm_skip` arms are invisible to the call-site grep)

## Phase 1 — RED: host unit suite
- [x] 1.1 Create `apps/web-platform/infra/apt-bounded.test.sh` with stub `apt-get` modes (ok, fail, hang with child, slow, fail-then-ok, oom)
- [x] 1.2 Rows: healthy, hang bounded + no orphan + marker last, pre-expired deadline invokes no apt, retry kept, slow passes, oom keeps rc, credential scrub, unset deadline is loud
- [x] 1.3 One derived assembly row: lib-mounting docker sites == `GD_APT_DEADLINE`-passing sites; no raw apt-get in command position
- [x] 1.4 Floor emitted by `printf` + `exit 1` (ADR-193); observe every row RED against the missing helper

## Phase 2 — GREEN: helper
- [x] 2.1 Create `apps/web-platform/infra/lib/apt-bounded.sh` (`gd_apt_deadline_arm`, `gd_apt_install_bounded`: one `timeout -k 5` per attempt, dpkg repair after a kill, scrub, cause line, marker; return not exit, explicit rc capture)
- [x] 2.2 Drive the seven Guard Contract mutations RED and record each in the PR body

## Phase 3 — Wire the two suites
- [x] 3.1 Ownership: two-statement helper call (`|| exit 97` on source), mount, `-e GD_APT_DEADLINE`, existence guard, arm 150; leave `_runtime_skip` and the FIXTURE_APT_FAILED branch untouched (fail-closed, #8744)
- [x] 3.2 Rehearsal `run_case`, T5 mutation, T17 mutation `bash -c` blocks (`|| exit $?`)
- [x] 3.3 Rehearsal S1 `sshd-drive.sh` and R4 `r4-drive.sh` (keep INJECT lines and FIXTURE-FAIL messages), `_s1_run` and R4 docker sites, mount-source guards for every site
- [x] 3.4 Rehearsal: arm 300 at the first docker site; run the suite after each site

## Phase 4 — Real-docker stall reproduction
- [x] 4.1 Throwaway docker shim inserting an unroutable `http_proxy` after `run`; `GD_APT_SUITE_BUDGET` for a quick pass
- [x] 4.2 Measure before/after wall-clock for ownership (expect a fast named failure) and rehearsal under `CI=true`; record skip-ceiling outcome; healthy run apt elapsed per container; paste into PR body

## Phase 5 — Decision record and verification
- [x] 5.1 Append ADR-188 amendment (2026-10-01, #9379)
- [x] 5.2 Run edited suites, `apt-bounded.test.sh`, render-strip-parity, guard-vacuity-floor, c4-count-parity; re-derive rehearsal totals
- [x] 5.3 File the two deferral issues separately (primary-arm eligibility; provision-unit and cutover-access siblings); link in PR body

## Outcome notes (work phase)
- Design deviated from the plan on measured evidence: a shared budget of APT SECONDS (state dir mounted at
  `/work/apt`) plus a 90 s per-attempt cap with retry, instead of one absolute wall-clock deadline. See the
  ADR-188 amendment and `decision-challenges.md` item 3.
- Budgets: rehearsal 420 s, ownership 180 s. Healthy real-docker run on a slow box: rehearsal 108/0/0 in 403 s
  (apt 386 s of 420); ownership 39/0/0 in 35-104 s.
- Stall reproduction (docker shim to an unroutable proxy, `CI=true`): ownership ends in a named failure at
  180 s (was killed at 300 s); rehearsal ends in its own verdict at 429 s (was killed at 600 s). The S1 and
  global skip ceilings fire on a total stall, as designed.
- Mutation battery: 12/12 killed; control green; each mutation confirmed landed.
- Deferrals filed: #9394 (primary-arm skip eligibility), #9395 (provision-unit and cutover-access siblings).
