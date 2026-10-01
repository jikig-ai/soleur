# Tasks — fix(ci): bound the in-container apt wall-clock in the git-data suites (#9379)

Plan: knowledge-base/project/plans/2026-10-01-fix-git-data-suites-bound-apt-wallclock-route-expiry-to-skip-plan.md

## Phase 0 — Evidence capture (read-only)
- 0.1 Record `.meta` rc/seconds for rehearsal and ownership from run 36885018496 and the next failing run on this branch
- 0.2 Derive (do not carry) the in-container apt site count and the worst-case serial container count in the rehearsal suite (12 expected)
- 0.3 Re-derive total declared-skip cost on a total stall vs `_SKIP_CEILING=10` (four `did-not-run) arm_skip` arms are invisible to the call-site grep)

## Phase 1 — RED: host unit suite
- 1.1 Create `apps/web-platform/infra/apt-bounded.test.sh` with stub `apt-get` modes (ok, fail, hang with child, slow, fail-then-ok, oom)
- 1.2 Rows: healthy, hang bounded + no orphan + marker last, pre-expired deadline invokes no apt, retry kept, slow passes, oom keeps rc, credential scrub, unset deadline is loud
- 1.3 One derived assembly row: lib-mounting docker sites == `GD_APT_DEADLINE`-passing sites; no raw apt-get in command position
- 1.4 Floor emitted by `printf` + `exit 1` (ADR-193); observe every row RED against the missing helper

## Phase 2 — GREEN: helper
- 2.1 Create `apps/web-platform/infra/lib/apt-bounded.sh` (`gd_apt_deadline_arm`, `gd_apt_install_bounded`: one `timeout -k 5` per attempt, dpkg repair after a kill, scrub, cause line, marker; return not exit, explicit rc capture)
- 2.2 Drive the seven Guard Contract mutations RED and record each in the PR body

## Phase 3 — Wire the two suites
- 3.1 Ownership: two-statement helper call (`|| exit 97` on source), mount, `-e GD_APT_DEADLINE`, existence guard, arm 150; leave `_runtime_skip` and the FIXTURE_APT_FAILED branch untouched (fail-closed, #8744)
- 3.2 Rehearsal `run_case`, T5 mutation, T17 mutation `bash -c` blocks (`|| exit $?`)
- 3.3 Rehearsal S1 `sshd-drive.sh` and R4 `r4-drive.sh` (keep INJECT lines and FIXTURE-FAIL messages), `_s1_run` and R4 docker sites, mount-source guards for every site
- 3.4 Rehearsal: arm 300 at the first docker site; run the suite after each site

## Phase 4 — Real-docker stall reproduction
- 4.1 Throwaway docker shim inserting an unroutable `http_proxy` after `run`; `GD_APT_SUITE_BUDGET` for a quick pass
- 4.2 Measure before/after wall-clock for ownership (expect a fast named failure) and rehearsal under `CI=true`; record skip-ceiling outcome; healthy run apt elapsed per container; paste into PR body

## Phase 5 — Decision record and verification
- 5.1 Append ADR-188 amendment (2026-10-01, #9379)
- 5.2 Run edited suites, `apt-bounded.test.sh`, render-strip-parity, guard-vacuity-floor, c4-count-parity; re-derive rehearsal totals
- 5.3 File the two deferral issues separately (primary-arm eligibility; provision-unit and cutover-access siblings); link in PR body
