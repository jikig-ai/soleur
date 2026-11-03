---
title: "test: make the inngest-luks-key-probe G4-2 mutant deterministic"
date: 2026-11-03
slug: g4-2-mutant-deterministic-sigpipe
branch: feat-one-shot-11752-g4-2-mutant-deterministic
issue: 11752
type: fix
lane: single-domain
requires_cpo_signoff: false
---

# test: make the inngest-luks-key-probe G4-2 mutant deterministic

Ref #11752 (never `Closes`; the issue's own re-evaluation trigger is verified on `main` CI after merge). Draft PR: #11992.

## Overview

`apps/web-platform/infra/inngest-luks-key-probe.test.sh` row **G4-2** ("without the allowance an early
cryptsetup exit reads as rc=141 at=key") removes the `0:0:141` arm from the PIPESTATUS allowance in
`apps/web-platform/infra/inngest-cutover-flip.sh` and expects `pred_early_exit_rc` to go RED. That
predicate only goes RED if, in at least one of its 20 runs, the real `tr -d '\n'` stage writes after the
cryptsetup stub has already exited and takes SIGPIPE (PIPESTATUS `0 0 141 4`). That is a pure race whose
hit rate is host dependent. On the reporting host the exact pipeline hits it in about 1 of 200 runs, so
20 runs miss it about 90% of the time, the G4-2 `expect_red` records a `fail()` instead of a `pass()`,
and the exact assertion pin then reads 157 instead of 158 (rc=1, 3 of 3 local runs; green on CI where the
hit rate is far higher). The `deploy-script-tests (2/4)` shard is red for every PR that runs it.

The fix keeps the natural-race runs and adds ONE forced run inside the same predicate that makes the
tr SIGPIPE status exist by construction, so the mutant is RED on every host, the pristine predicate stays
the must-PASS partner, and the assertion count stays exactly 158.

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Reality (measured) | Plan response |
|---|---|---|
| "cause looks environmental (SIGPIPE-timing dependence, or a runner/coreutils change), not a source edit" | Confirmed as a timing dependence, not a source edit. A micro-repro of the exact `sed \| head \| tr \| timeout cryptsetup` pipeline under `env --default-signal=PIPE` (200 runs, this host, coreutils tr 9.12, bash 5.3) gave `0 0 141 4` in 1/200 runs; P(at least one in 20) is about 10% | Remove the dependence rather than raise the run count (raising it to a safe margin on a 0.5% event would cost minutes) |
| "the same suite passed on an earlier head the same night" | The CI hit rate is about 40% per run (suite comment, line 127), so 20 runs almost always hit; a runner scheduling change moves that rate | Do not chase the runner; make the property independent of the rate |
| "keep the assertion count at exactly 158" | `EXPECTED_ASSERTIONS=158` pin at line ~1307; the G4-2 `expect_red` currently contributes to it only when it reads RED | Fold the forced run INTO `pred_early_exit_rc`: no assertion line is added or removed |
| (implicit) a test-only shim is free | `.claude/hooks/grep-q-pipe-guard.test.sh` derives (suite, verb, producer file) triples (`PJ_TRIPLES=317`, `PRODUCER_JOIN` rows; the suite's existing `head` shim has a row). A new `tr` shim creates new triples | Plan the `PRODUCER_JOIN` row and the `PJ_TRIPLES` bump as in-scope tasks; the guard is not selected by the pre-push affected gate for every producer, so it is run by hand |

## Research Insights

**Premise Validation.** #11752 is OPEN and unfixed on `origin/main` (0 commits behind; neither the suite
nor `inngest-cutover-flip.sh` changed since). Reproduced locally on this branch with
`bash apps/web-platform/infra/inngest-luks-key-probe.test.sh`: rc=1, `FAIL: assertion-count mismatch: 157
assertions ran, expected exactly 158`, 57 s wall. Cited refs #11704 and #8211 are OPEN and unrelated
to the fix. Collision pre-check: only the draft PR #11992 (this branch) names #11752; three foreign
`test-all.sh` processes run in another worktree (a reason to run suites strictly one at a time).

**Property List.**
1. The G4-2 mutant (the `0:0:141` allowance dropped) is detected on every host and every run, not only on a host where the tr-SIGPIPE race fires.
2. The pristine probe stays GREEN for an early cryptsetup exit, with and without SIGPIPE ignored.
3. The suite's assertion inventory stays exactly 158.
4. The forced path cannot pass vacuously (the shim demonstrably fired).

**Cut List.**
- Raise the 20-run loop to N runs (buys property 1 only probabilistically; a 0.5% event needs about 1500 runs for 99.9%, minutes of wall time): cut.
- New separate predicate plus new `assert_true`/`expect_red` pair (buys property 1, but moves the pin to 159/160 against the stated constraint and leaves no must-PASS partner unless it adds a second line): cut.
- Real-`tr` pid-synchronized shim (CTO Option B) and sleep-delay shim (Option C): cut by the CTO ruling (still a race, extra failure modes).
- Editing `inngest-cutover-flip.sh` (the production probe): cut. The allowance is correct; only its detection is flaky. No production file changes.

**Learnings applied.**
- `knowledge-base/project/learnings/2026-07-28-a-ten-run-sample-said-unreachable-and-the-defect-was-live-at-two-percent.md`: a sampled SIGPIPE race says nothing at 10-20 runs; make the status exist by construction and re-measure instead of reasoning from a sample. The rates quoted above were measured, not assumed.
- `knowledge-base/project/learnings/best-practices/2026-07-18-deploy-script-tests-at-budget-timeout-and-infra-pr-ci-gotchas.md` and the 2026-10-08 pipe-tail learning: CI harnesses start steps with SIGPIPE ignored; every forced-SIGPIPE run must pin `env --default-signal=PIPE` (the suite already does for this predicate).
- Suite precedent for a PATH-prepended shim: `pred_upstream_fail` (the `head` shim, `PATH="$WORK/shim:$PATH"`).

**Mechanism (verified in source).** `inngest-cutover-flip.sh` lines ~1117-1140: `sed | timeout head | timeout tr -d '\n' | timeout cryptsetup`, then `pst=("${PIPESTATUS[@]}")` and `case "${pst[0]}:${pst[1]}:${pst[2]}" in 0:0:0|141:0:0|0:0:141) ;;`. `timeout` re-raises the child's fatal signal on itself, so a tr that dies by SIGPIPE reads 141 in `pst[2]`.

**Prototype (scratchpad micro-repro, not source).** A `tr` shim gated on `"$*" = '-d \n'` that drains stdin then runs `kill -s PIPE $$`, forwarding every other invocation to the real `/usr/bin/tr`, produced `0 0 141 4` in 300/300 runs of the exact pipeline under `env --default-signal=PIPE`, and a marker file proved it fired. The unrelated `tr` calls in the script (`tr -d '[:space:]'` at line ~258 and `tr '\n' ' '` at line ~590) passed through.

**CTO ruling (2026-11-03):** Option A, folded in, argv-gated, marker-checked, with a `PRODUCER_JOIN` row and a `PJ_TRIPLES` bump. Recorded in `knowledge-base/project/specs/feat-one-shot-11752-g4-2-mutant-deterministic/decision-challenges.md`.

## Open Code-Review Overlap

None. Checked open `code-review` issues against `apps/web-platform/infra/inngest-luks-key-probe.test.sh`, `apps/web-platform/infra/inngest-cutover-flip.sh` and `.claude/hooks/grep-q-pipe-guard.test.sh`: no body names any of them.

## Scope Check

- Ask mapping: "make the mutant deterministic" -> Phase 1; "keep 158" -> AC1; "keep the mutant's intent" -> Guard Contract; "run the suite at least 5 times green, one at a time" -> Phase 3; "show the mutant row RED against the mutant and GREEN against the real code" -> Phase 3 evidence step; "Ref only" -> AC9.
- Item provenance: the `PRODUCER_JOIN` row and the `PJ_TRIPLES` bump are `derived` (a consequence of adding a `tr` shim to a suite, enforced by a repo ratchet); the comment and description rewording is `derived` (the old text says "about 4 of 10 runs").
- Split assessment: one PR, two files plus planning artifacts.

## Files to Edit

- `apps/web-platform/infra/inngest-luks-key-probe.test.sh`: extend `pred_early_exit_rc` (anchor: `pred_early_exit_rc() {`) with one forced run; reword the stub comment above `[ -n "${STUB_EARLY_RC:-}" ]` and the pristine assertion description (anchor: `pristine: a cryptsetup that exits before reading`). Do NOT touch `EXPECTED_ASSERTIONS=158`.
- `.claude/hooks/grep-q-pipe-guard.test.sh`: add the `PRODUCER_JOIN` row for (`apps/web-platform/infra/inngest-luks-key-probe.test.sh`, `tr`), set `PJ_TRIPLES` to the measured value and extend its comment (anchor: `PJ_TRIPLES=317`).
- `plugins/soleur/test/fixture-relative-assert.baseline.txt`: ONLY if `bash plugins/soleur/test/fixture-relative-assert.test.sh` reports a row delta for the suite (the shim is written under `$WORK`, which the scanner resolves, so none is expected). Regenerate with `--write-baseline` in that case.

## Files to Create

None (planning artifacts only: this plan, `tasks.md`, `decision-challenges.md`).

## Implementation Phases

### Phase 0 — Baseline (before any edit)

0.1 Reconfirm the failure once: `bash apps/web-platform/infra/inngest-luks-key-probe.test.sh` (one suite at a time; about 57 s). Expect rc=1 and the 157/158 line.
0.2 Record the guard baseline: `bash .claude/hooks/grep-q-pipe-guard.test.sh` green on the unedited tree (so any later red is attributable).

### Phase 1 — Forced SIGPIPE run in `pred_early_exit_rc`

Write the failing check first (cq-write-failing-tests-before): the suite itself is the test. With Phase 1's shim in place but the G4-2 mutant applied, the forced run must read RED.

Add, after the existing 20-run loop and before `end_case`, within `pred_early_exit_rc`:

```bash
  # Forced run (#11752): the 20 runs above only see tr take SIGPIPE when it writes after the reader
  # exited (about 4 in 10 on CI, about 1 in 200 on a fast local host), so on their own they cannot
  # prove the 0:0:141 allowance is exercised. This run makes PIPESTATUS read "0 0 141 4" by
  # construction: a tr shim, gated on the probe's exact argv, drains its stdin (so sed and head do not
  # take SIGPIPE) and then dies by SIGPIPE; every other tr call goes to the real tr.
  local real_tr
  real_tr="$(command -v tr)"
  [[ "$real_tr" == /* ]] || bad=$((bad + 1))
  mkdir -p "$WORK/shim"
  cat > "$WORK/shim/tr" <<SHIM
#!/bin/sh
if [ "\$*" = '-d \\n' ]; then
  : > "$WORK/tr-fired"
  cat >/dev/null
  kill -s PIPE \$\$
fi
exec $real_tr "\$@"
SHIM
  chmod +x "$WORK/shim/tr"
  rm -f "$STAMP" "$WORK/tr-fired"
  : > "$LOGTRACE"
  : > "$PHONETRACE"
  RUN_PREFIX="env --default-signal=PIPE"
  run_tick "done" STUB_EARLY_RC=4 PATH="$WORK/shim:$PATH"
  RUN_PREFIX=""
  [[ -e "$WORK/tr-fired" ]] || bad=$((bad + 1))   # the shim must have fired, or the run proves nothing
  [[ "$(probe_summary)" == "$(expect_summary 'verdict=indeterminate rc=4 at=kdf' indeterminate)" ]] || bad=$((bad + 1))
```

Constraints (from the CTO ruling; each is also an acceptance criterion):
1. The shim misbehaves ONLY for argv exactly `-d \n`; the script also runs `tr` at lines ~258 and ~590 and the shim is on `PATH` for the whole tick. Everything else `exec`s the absolute real `tr`, resolved BEFORE `PATH` is prepended.
2. The marker file is the anti-vacuity control: a missing marker adds to `bad`. No new assertion line.
3. The shim drains stdin before dying: without the drain, `head` takes SIGPIPE too (`0 141 141 4`), the pristine run would read rc=141 at=key, and the predicate would be RED on the real code.
4. Pin `env --default-signal=PIPE` (CI inherits SIGPIPE ignored).
5. The heredoc is unquoted so `$WORK` and `$real_tr` bake in; the `\\n` yields the two characters backslash-n in the shim (verify by `cat`ing the generated shim once during the work phase).
6. Rewording only: the stub comment (line ~127) and the assertion description lose the "about 4 of 10" claim and say "20 natural-race runs plus one forced tr SIGPIPE run". Keep the G4-2 `expect_red` description unchanged.

### Phase 2 — Bookkeeping ratchet

2.1 `bash .claude/hooks/grep-q-pipe-guard.test.sh` (stage the edited suite first: the guard reads only tracked files, so a new untracked file is invisible; the edit here is to a tracked file, so `git add` is only needed for the guard file's own derivation of the new stub). Expect an `unlisted pair` FAIL naming the suite, `tr`, and its producer file(s).
2.2 Add `'apps/web-platform/infra/inngest-luks-key-probe.test.sh | tr | exempt | deliberate-fault never drains first: the shim gates on argv exactly "-d \n", drains stdin, then dies by SIGPIPE on purpose (the G4-2 forced run); every other call execs the real tr'` next to the existing `head` row. Reason word must be in `PJ_VOCAB` (`deliberate-fault`). If the guard rejects the `exempt` row, fall back to a `drains` row only if the shim can be restructured so its first statement is the drain without draining unrelated `tr` calls (for example, dispatch on argv first via a second wrapper file); otherwise keep `exempt` and record the guard's message in the PR.
2.3 Recompute `PJ_TRIPLES` with the documented command (`PJ_ALL="$(git ls-files)"; . <(sed -n '/^# PJ-DERIVE-BEGIN/,/^# PJ-DERIVE-END/p' .claude/hooks/grep-q-pipe-guard.test.sh); pj_join_pairs | LC_ALL=C sort -u | wc -l`), set it, and append a `+N at #11752: ...` clause to the comment.
2.4 Run `bash plugins/soleur/test/fixture-relative-assert.test.sh` once; regenerate the baseline only on a delta.

### Phase 3 — Proof (one suite at a time; host is low on memory)

3.1 Run the edited suite 5 times in sequence (never in parallel): each must print `=== Results: 158 passed, 0 failed ===` and exit 0. Capture the `PASS: G4-2 without the allowance an early cryptsetup exit reads as rc=141 at=key: RED against the mutant` line and the `PASS: pristine: ... early ...` line from every run.
3.2 Mutant RED / real GREEN, shown directly: (a) the pristine row line above is the GREEN-against-real-code evidence; the G4-2 line is the RED-against-mutant evidence, 5 of 5. (b) One extra run with `PROBE_SUITE_TARGET` pointing at a scratch copy of `inngest-cutover-flip.sh` with `0:0:141` removed (made under `mktemp -d`, never the tracked file): the pristine early-exit row must FAIL (`rc=141 at=key`) on that run, confirming the forced run reads the mutant on this host regardless of the race.
3.3 Control: show the unmodified predicate is flaky on this host (the Phase 0.1 reproduction is the before-evidence).
3.4 Do not dispatch `inngest-key-rotate` or `key-rotate` workflows, write no owner marker, no production writes, and print no secret values (the suite uses a synthesized sentinel only).

### Phase 4 — Ship

Commit the suite, the guard file, and (if regenerated) the baseline; push; wait for CI (`deploy-script-tests (2/4)` green; CI is the authority). PR body uses `Ref #11752`, never `Closes`. After merge, verify `main` CI is green for the shard and then close #11752 against its own re-evaluation trigger (the mutant is deterministic and the count is unchanged).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `grep -c '^EXPECTED_ASSERTIONS=158$' apps/web-platform/infra/inngest-luks-key-probe.test.sh` prints `1` and the suite prints `=== Results: 158 passed, 0 failed ===` (no new `assert_*`/`expect_red`/`pass` line is added or removed).
- [ ] AC2: five consecutive local runs of `bash apps/web-platform/infra/inngest-luks-key-probe.test.sh`, one at a time, all exit 0 with 158 passed, and each contains the G4-2 `RED against the mutant` PASS line.
- [ ] AC3: a run against a mutant target (`0:0:141` removed) fails the pristine early-exit row, proving the forced run sees the mutant; a run against the real target passes it.
- [ ] AC4: the forced run cannot pass vacuously: the shim writes `tr-fired`, and the predicate counts a missing marker as `bad` (verified by temporarily changing the shim's argv gate in a scratch copy and seeing the pristine row go RED).
- [ ] AC5: the shim forwards every `tr` invocation whose argv is not exactly `-d \n` to the absolute real `tr`.
- [ ] AC6: `bash .claude/hooks/grep-q-pipe-guard.test.sh` is green with the new `PRODUCER_JOIN` row and the recomputed `PJ_TRIPLES`.
- [ ] AC7: `bash plugins/soleur/test/fixture-relative-assert.test.sh` is green (baseline regenerated only if it reported a delta).
- [ ] AC8: no change to `apps/web-platform/infra/inngest-cutover-flip.sh` or any other production file (`git diff --stat origin/main` lists only the suite, the guard file, optionally the baseline, and planning artifacts).
- [ ] AC9: the PR body says `Ref #11752` and never `Closes`/`Fixes`/`Resolves #11752`.
- [ ] AC10: `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-11-03-fix-g4-2-mutant-deterministic-sigpipe-plan.md` passes.

### Post-merge (operator-free, agent-verifiable)

- [ ] AC11: `gh run list` for the `infra-validation.yml` workflow on `main` shows `deploy-script-tests (2/4)` green after merge; then close #11752 citing its re-evaluation trigger.

## Test Scenarios

| # | Input | Expected |
|---|---|---|
| T1 | Pristine probe, forced run (tr shim dies by SIGPIPE, cs stub exits 4) | `0 0 141 4` -> allowance arm -> `verdict=indeterminate rc=4 at=kdf` |
| T2 | G4-2 mutant (`0:0:141` removed), forced run | default arm -> `rc=141 at=key` -> predicate RED on every host |
| T3 | Pristine probe, 20 natural-race runs | unchanged: all `rc=4 at=kdf` whether or not tr wins the race |
| T4 | Pristine probe, `env --ignore-signal=PIPE` row (existing) | unchanged: indeterminate, never a key verdict |
| T5 | Shim argv gate broken (scratch edit) | marker missing -> `bad` -> pristine row RED (not vacuous) |
| T6 | Other `tr` calls in the tick (`-d '[:space:]'`, `'\n' ' '`) while the shim is on PATH | forwarded to the real `tr`; no behavior change |

## Guard Contract

### Guard 1 — G4-2: the tr-SIGPIPE allowance is blind-detectable

**Property.** If the probe's `tr` stage dies by SIGPIPE because cryptsetup exited before reading, the verdict keeps cryptsetup's own exit code at=kdf and is never reported as a key verdict, and a probe that stops allowing that status is detected on every host and every run.

**Assembly.** The PIPESTATUS allowance is one `case "${pst[0]}:${pst[1]}:${pst[2]}"` arm list in `inngest-cutover-flip.sh` (single chokepoint: `0:0:0|141:0:0|0:0:141`), exercised through one pipeline (`sed | head | tr | cryptsetup`); the stages that can take SIGPIPE are sed (141 once head has its line), head, and tr. Detection is assembled from `pred_early_exit_rc` (20 natural-race runs plus the forced run), the existing `pred_early_exit_sigpipe_ignored` (EPIPE spellings), and `pred_upstream_fail` (G4-1, the `*)` neutering). Only the tr stage's 141 is forced; the sed-141 arm (`141:0:0`) cannot be reached by a fixture file with one line and stays covered by pred_upstream_fail's neutering mutant, not by this guard.

**Mutation matrix.**

| # | Edit | Must drive RED | Why |
|---|---|---|---|
| M1 | Drop `0:0:141` from the arm list (the G4-2 mutant, as it stands) | `expect_red G4-2` PASS line on every run | the allowance's own dispatch |
| M2 | Replace `0:0:141` by `0:0:1` (the EPIPE spelling) | pristine early-exit row RED (forced run reads rc=141) | a second, wrong member after a compliant first: the SIGPIPE-ignored row passes with `0:0:1` while the default-signal row does not |
| M3 | Neuter the arm to `*) ;;` (the G4-1 mutant) | `expect_red G4-1` (pred_upstream_fail) RED | the allowance must stay an enumeration, not a wildcard |
| M4 | Change the shim's argv gate so it never fires (harness mutation, scratch copy of the suite) | pristine early-exit row RED via the marker check | the forced run cannot pass vacuously |
| M5 | Remove the `cat >/dev/null` drain from the shim (scratch copy) | pristine early-exit row RED (`0 141 141 4`) | the forced status must be tr's alone |

**Harness rows.** M4 and M5 edit the suite, not the guard, and must drive it RED. Must-PASS inputs that differ from the canonical: the existing `pred_early_exit_sigpipe_ignored` row (SIGPIPE ignored, EPIPE exits) and the natural-race loop on a host where tr wins the race (all `0 0 0 4`).

**Anchor.** The stored value is `EXPECTED_ASSERTIONS=158`. It is a count floor, so by itself it survives a swap that keeps 158. What outside the commit must also move for a weakening to pass: the pristine/G4-2 pair is identified by its description strings (`pristine: a cryptsetup that exits before reading` and `G4-2 without the allowance ...`), and CI's `deploy-script-tests` shard plus PR review are the independent anchor. Residual, stated plainly: deleting the forced run from `pred_early_exit_rc` reverts to the race and is caught only probabilistically (the very defect fixed here); no in-suite control can make that deletion deterministic without adding an assertion line.

## Observability

Test-only change on a CI surface; no runtime code, no new infrastructure, no logs.

```yaml
liveness_signal:
  what: the infra-validation.yml job deploy-script-tests (2/4) result on every PR and on main
  cadence: every PR and push to main that runs infra-validation.yml
  alert_target: GitHub Actions check status, and the main-health-monitor.yml workflow for main
  configured_in: .github/workflows/infra-validation.yml
error_reporting:
  destination: the suite prints FAIL lines and exits non-zero; CI marks the shard red
  fail_loud: true (the exact assertion-count pin exits 1 on any drift)
failure_modes:
  - mode: the forced shim did not fire (argv gate drift)
    detection: the tr-fired marker check adds to bad, so the pristine early-exit row reads FAIL
    alert_route: red deploy-script-tests (2/4)
  - mode: the G4-2 mutant is not detected
    detection: expect_red prints FAIL and the count pin reads 157
    alert_route: red deploy-script-tests (2/4)
logs:
  where: GitHub Actions job log for deploy-script-tests (2/4)
  retention: GitHub Actions default retention
discoverability_test:
  command: grep -c '^EXPECTED_ASSERTIONS=158$' apps/web-platform/infra/inngest-luks-key-probe.test.sh
  expected_output: "1"
```

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; a broken test suite blocks merges of unrelated infra PRs (the `deploy-script-tests (2/4)` shard stays red), delaying fixes that users are waiting for.
**If this leaks, the user's data is exposed via:** no exposure vector; the change adds a test shim and a bookkeeping row, reads no secret, and the suite uses a synthesized sentinel key only.
**Brand-survival threshold:** none

threshold: none, reason: the diff is test-only (a PATH-scoped shim inside a scratch case directory plus a ratchet row), touches no production script, and moves no credential, schema, or user data.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Sharp Edges

- The shim must drain stdin BEFORE dying and must only act on argv `-d \n`; both were measured. Dropping either turns the pristine row RED (`0 141 141 4`) or alters unrelated `tr` calls.
- `grep-q-pipe-guard.test.sh` reads only tracked files and is not selected by the pre-push affected gate for every producer: run it by hand; CI runs it in its full battery.
- Run the proof suites strictly one at a time (foreign `test-all.sh` processes are live on this host; free memory is low). Each suite run is about 57 s.
- A plan that tests only the mutated predicate would miss that the pristine run could go RED if the shim leaks into other `tr` calls: AC5 and T6 cover it.
- Do not let the PR body, commit message, or any trailer say `Closes #11752`.
