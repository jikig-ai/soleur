---
title: "fix: zot-pull mutation battery mis-scores rows under load — two early-exit pipe consumers under pipefail"
type: fix
date: 2026-09-25
slug: fix-zot-pull-mutation-harness-row-misroute
branch: feat-one-shot-8664-zot-pull-mutation-misroute
issue: 8664
closes: 8664
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: zot-pull mutation battery mis-scores rows under load — two early-exit pipe consumers under pipefail

## Overview

The spec has no valid `lane:`, so it defaults to cross-domain (TR2 fail-closed).

The mutation battery for the dedicated Inngest host's bootstrap pull arm
(`apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh`, 60 rows today) sometimes
reports one row as not KILLED when it runs inside the parallel infra runner. It never does this when
it runs alone. This plan reproduces the flake, names the mechanism with measurements, and makes every
row's verdict depend only on the bytes of that row's log, not on how the machine schedules processes.

The cause is **not** a shared `TMPDIR`, a fixed-path fixture, or row ordering. Every scratch path in
the battery, its guard and the render helper comes from `mktemp`. The cause is one class, found at
two sites: a pipeline under `set -o pipefail` whose **last stage stops reading before the first stage
has finished writing**. Under CPU contention the first stage then takes SIGPIPE and exits 141, and
`pipefail` makes the whole pipeline report that failure.

| Site | Shape | What 141 does | Measured under load |
|---|---|---|---|
| **A**: battery scorer, `case_mutate` (`cloud-init-inngest-zot-pull-mutation.test.sh:205`) | `grep -E '^  FAIL' "$log" \| grep -qF "$expect"` | A row that WAS killed on its named assertion is scored **MISROUTED** | 64/3000 false negatives (2.1%) on the real 5,075-byte FAIL stream of `row6` |
| **B**: guard's Guard 1b arm splitter (`cloud-init-inngest-bootstrap.test.sh`, the `sed -E '/^[[:space:]]*#/d' "$DED_BLOCK_FILE" \| awk … exit` pipeline under the `--- Guard 1b (#6500)` header) | `awk` `exit`s at the missed arm's closing `fi`, while `sed` still has ~6 KB to write | The guard (`set -euo pipefail`) **dies silently** before any Guard 1b assertion runs: rc≠0, zero `^  FAIL` lines | 33/3000 (1.1%) per guard run. The battery runs the guard about 62 times, so P(at least one hit per battery run) is about 50% at this load |

## Enhancement Summary

**Deepened on:** 2026-09-25. **Passes run:** plan-review panel (DHH, Kieran, code-simplicity, CTO
devex), the deepen-plan halt gates (4.6 user-brand, 4.7 observability, 4.8 PAT, 4.11 guard
contract; 4.5, 4.55, 4.9 and 4.10 do not trigger), an implementation-realism prototype, and a
test-design review.

### Key improvements

1. **The prototype executed both fixes in scratch, not just reasoned about them.** `failed_on` with
   the needle-first fixture: the self-test passes, and the old piped form false-negatives **50/50**
   on the same 1,260,054-byte fixture. A directory passed as the log makes it `die` with rc 2. A
   metacharacter-laden expected string (`[x] (a*b)?`) matches literally. The three `wf_block`
   herestring asserts, written in the variables-first form under the guard's own `eval`-based
   `assert()`, give 3 PASS, and a mutated-permissions negative control FAILs. That proves the
   quoting (Kieran P1-1) and yields zero drift-guard pattern hits.
2. Plan review cut ceremony: the causal-floor awk pass, the `SCORER_PROBES` floor, the rc-2 arm with
   its probe, the padded-row self-checks, and 20 of the 30 AC3 runs. It kept Kieran's two
   one-line fixture-shape checks as the #8644 guard.
3. The test-design review added six cheap hardenings:
   - an empty-expected-string `die` in `failed_on`;
   - a PASS-only probe line that also contains `FAIL`;
   - a `tail -1` diagnostic when BROKE has no FAIL lines;
   - a one-property comment on the padded row;
   - a `git ls-files --error-unmatch` check in the drift-guard pass;
   - an AC3 rule that every copy exits rc=0 with `61/61` and `OK`.
4. The Observability probe now expects a literal Check 10 can match
   (`grep-q-zero-8664-pass`), and `configured_in` cites suite paths rather than the step names that
   #8763 restructures.

### New considerations discovered

- Four sibling batteries carry the same scorer bug in six places. They are deferred, with a
  tracking issue and a `decision-challenges.md` entry, because one of them is in #8763's diff.
- The issue named the wrong row: `grep MISROUTED` matches the harness row's PASS line.
- The SIGPIPE exposure floor is the producer's write size (~4 KiB), not the 64 KiB pipe capacity,
  which corrects the framing in #7005.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (measured 2026-09-25) | Plan response |
|---|---|---|
| The flaking row is `ng1-harness-row1-self-compare` | That row's **passing** line is `KILLED: ng1-harness-row1-self-compare — … flips row 1 off KILLED (MISROUTED)`. The `(MISROUTED)` suffix is the expected inner verdict, by design (`cloud-init-inngest-zot-pull-mutation.test.sh`, the `NIC-G1 harness row` block). No code path in the battery prints `MISROUTED: ng1-harness-row1-self-compare`. Round 1 (10 concurrent runs): 5/10 runs failed with exactly one non-KILLED row, and **none** was the harness row: `g1-row4-served-call-in-missed-arm`, `g1-extra-backgrounded-emit`, `g1-row16-dead-heredoc`, `ng1-escape-wget` (all mechanism B: empty failure list, log ends at the Guard 1b header) and `row6-guard-checks-zero-content` (mechanism A: the expected `Row6 anti-vacuity` FAIL line **is** in the printed list). | Fix the mechanism, not a row. Correct the issue's framing in the PR body. A `grep MISROUTED` over a run log matches the harness row's PASS line, and that is how the issue named the wrong row. |
| Candidate causes: shared `TMPDIR`, a fixture at a fixed path, or ordering between rows | Every scratch path is `mktemp`-unique: the battery's `$WORK` (`mktemp -d -t inngest-zot-mut-XXXXXX`), the guard's `nicg1-`/`g4pull-`/`inngest-arm-*`/`inngest-ci-*` temps, and the render helper's `inngestbudget.XXXXXXXX`. The guard's one literal-`/tmp` template (`mktemp /tmp/inngest-runcmd-XXXXXX.sh`) is still unique. No row reads another row's state. | None of these needs a change. They are out of scope. |
| "not in isolation" | Isolation 60/60, 3m13s wall-clock on 16 cores. Under 10 concurrent copies with a shared `TMPDIR=/var/tmp/…`, load average 30-45 | The concurrent repro is the RED for AC3, and the synthetic drivers below are the deterministic RED |
| Prior art (#7005, #6992): "the threshold is the 64 KiB pipe buffer: 0/30 below it, 30/30 at 128 KB" | That holds for a **single-write** producer. `grep` and `sed` writing to a pipe are stdio-buffered. A **5,075-byte** `grep` output took SIGPIPE 64/3000 under load, and a **7,380-byte** `sed` output 33/3000. A 2,824-byte `awk` output took 0/6000. That is consistent with a write granularity of about 4 KiB, not the 64 KiB pipe capacity. | The Sharp Edges section records this, the fix does not rely on any size threshold, and the compound step captures it as a learning |

## Problem Statement / Motivation

`run-registered-suites.sh` is the only **blocking local gate** for `apps/web-platform/infra/`. No
required status check covers that shard (#6480). A row whose verdict changes with scheduling makes
that gate red, at random, for changes that cannot have caused it. People then learn to ignore it,
and a gate people ignore is worse than no gate. Mechanism B also affects the guard suite on its own:
`cloud-init-inngest-bootstrap.test.sh` is registered by itself too, and it dies at about 1.1% per run
under the same load, with no FAIL line to show why. (This may explain part of #7376's "three
different suites across two of six executions". This plan does not claim that. See Non-Goals.)

## Proposed Solution

Remove the pipe at both live sites, so no verdict can depend on when the reader exits. Pin both
files at zero `| grep -q` in the repo's existing drift guard. Add two deterministic regression
inputs that make each old shape fail every time rather than 1-2% of the time.

### Files to Edit

1. **`apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh`** (the battery)
   - Extract the named-assertion check into one scorer function:
     `failed_on() { [[ -n "$2" ]] || die "failed_on: empty expected string"; local fails rc; fails="$(grep -E '^  FAIL' "$1")"; rc=$?; (( rc > 1 )) && die "scorer could not read $1 (grep rc=$rc)"; [[ "$fails" == *"$2"* ]]; }`.
     The empty-`$2` guard matters because `*""*` matches anything. Without it, an empty expected string
     would score KILLED on a log with zero FAIL lines, where the old `grep -qF ""` returned 1
     (test-design review, finding 6).
     It captures once (bash reads to EOF, so nothing is left for SIGPIPE to hit) and matches with a
     pure-bash glob (no second process). The quoted `"$2"` inside the pattern is literal: Kieran
     verified this with `a[b]*?c`. It is equivalent to the old pipeline for every non-empty,
     newline-free expected string, which covers every row. grep's rc 1 ("no FAIL lines") is a
     normal not-found. rc ≥ 2 (an I/O error, or a directory) is a harness abort, not a silent
     "not found" (plan review, Kieran P2-7). `case_mutate` calls it in place of the pipeline. The
     `MISROUTED` display keeps its existing file re-grep (`grep … | head -5 | sed`). That is a
     display-only pipe in a file without `set -e`, and it never decides a verdict. There is no separate "unreadable log"
     arm: a missing log already scores MISROUTED, which fails the battery, so the negative verdict
     here fails closed. That is the opposite of #8644's fail-open decoy (plan review, simplicity).
   - **Scorer self-test** (one fixture, two probes, `die` → exit 2, per this file's "HARNESS
     FAILURES ABORT" contract). It sits directly after `failed_on`'s definition. The fixture is
     `$WORK/scorer-selftest.log`, which the existing EXIT trap owns (no new trap). Line 1 is
     `^  PASS: SELFTEST-ONLY-ON-PASS would FAIL if unscoped`. The word `FAIL` is on that PASS line
     so that a scope loosened to an unanchored `FAIL` is also caught (test-design review, finding 5). line 2 is `^  FAIL: SELFTEST-TARGET`, and after that come
     about 20,000 `^  FAIL: filler NNNNNN yyyy…` lines (≥1 MiB). Throughout this plan, `^` marks the
     start of a line: each literal line begins with two spaces, as `assert()` prints it. Generate the fixture with ONE
     `awk 'BEGIN{…}' > "$f"`, never `yes | head` or `seq | sed`, since those would recreate an
     early-exit pipe under pipefail (plan review, CTO F4). Right after generating it, pin the fixture's
     SHAPE with two cheap checks, each ending in `|| die` (Kieran P2-3, the #8644 lesson): line 2 is
     exactly `^  FAIL: SELFTEST-TARGET` (the needle is first), and `grep -c '^  FAIL: filler'` is
     ≥ 20000 (the bulk after the needle carries the `^  FAIL` prefix). Without them, moving the needle
     last or de-listing the filler disarms the probe silently.
     - `failed_on "$f" SELFTEST-TARGET` must return 0. This is the deterministic RED for the old
       shape: the needle comes before about 1 MiB of FAIL output. Measured: the piped scorer
       false-negatives **200/200** on a 1,260,025-byte log of this shape, and the captured form 0/200.
     - `failed_on "$f" SELFTEST-ONLY-ON-PASS` must return 1. This pins the FAIL-line scoping that
       `failed_on` re-implements ("`assert()` echoes the description on PASS as well as FAIL …").
       The first probe on the same file is its positive control.
   - **New must-PASS row `g1b-mustpass-padded-pull-item`** (`case_must_pass "$SRC"`). Insert 2,400
     no-op lines (4-space-indented `: pad-NNNNN xxxx…`, about 150 KB, more than twice the 64 KiB
     pipe capacity) directly after the exactly-once anchor, the 4-space-indented
     `docker create --name soleur-inngest-bootstrap-extract "$IREF"` line. That line sits inside the
     bootstrap pull item and after the zot `if/else/fi`, so the pad is exactly the output the
     splitter's producer still has to write when awk exits. The mutator keeps the file's standard
     `assert s.count(anchor)==1`. `case_must_pass`'s existing landing check covers the rest. Measured
     on a scratch sandbox: the **unfixed** guard on the padded tree exits **non-zero (rc=141 here)
     with 0 FAIL lines**, and the log ends at the `--- Guard 1b (#6500)` header. That is the exact
     flake signature, reproduced deterministically. The **fixed** guard exits rc=0 with
     `BOOTSTRAP_SUITE_OK unconditional=153 floor=153 total=230`. The pad comes after the G4 slice's
     `docker create` end-line and after the arm split, and it carries no `docker`/`curl`/`10.0.x`
     token, so it changes no other verdict. A comment on the row names the single property it
     guards: the Guard 1b splitter must survive a producer that is still writing. That keeps a
     future size or line budget from being misread as a splitter regression (test-design review,
     finding 2).
   - **`case_must_pass`'s BROKE display:** when the log has no `^  FAIL` lines, print
     `tail -1 "$log"` in their place. The splitter regression this PR guards against dies silently
     at the `--- Guard 1b (#6500)` header, and today that shows up as an empty list under a
     misleading "the guard is over-fitted" line (test-design review, finding 1).
   - Floor: `BATTERY_MIN_ROWS=60` → `61`, with a history line (`61 (#8664): +1 must-PASS
     padded-pull-item row`). Keep the literal on the line directly above its `if`, as
     `scripts/guard-vacuity-floor.test.sh` requires.

2. **`apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`** (the guard)
   - **Guard 1b splitter**: remove the `sed -E '/^[[:space:]]*#/d' "$DED_BLOCK_FILE" |` stage and add
     `/^[[:space:]]*#/ { next }` as the awk program's **first** rule. awk then reads
     `"$DED_BLOCK_FILE"` as a file operand, so its `exit` has no producer to kill. This is
     equivalent: sed deleted exactly the lines awk now skips, before any other rule saw them.
     Measured: the arm files were byte-identical (3/4 lines) on the real block and on the padded
     block, and the fixed splitter failed 0/200 on the padded input.
   - **Three latent `wf_block … | grep -qxF` asserts** (the `G1b: write_files delivers …` conditions):
     **compute the blocks into variables BEFORE the asserts** (`WF_EMIT="$(wf_block /usr/local/bin/soleur-boot-emit)"`,
     `WF_DSN="$(wf_block /etc/default/soleur-sentry-dsn)"`), then assert with an escaped herestring:
     `assert "…" "grep -qxF \"    permissions: '0755'\" <<<\"\$WF_EMIT\""`. The conditions are
     double-quoted strings that `assert()` `eval`s, so a literal `$(wf_block …)` inside one would
     expand at the call site and splice block text containing `'0755'` and `${sentry_dsn}` into the
     eval string, which breaks its quoting (plan review, Kieran P1-1). They are latent today (outputs
     ≤2,824 B, measured 0/6000 false negatives), but they break this file's own header rule ("NO
     `producer | grep -q` ANYWHERE IN THIS FILE"). They also block item 3.
   - **Header comment**: one sentence. The rule covers any consumer that can stop before EOF
     (`grep -q`, `awk … exit`, `head`), and #8664 is cited. The ~4 KiB analysis goes to the learning
     file, not here.

3. **`.claude/hooks/grep-q-pipe-guard.test.sh`**: add both files to the named-file, comment-stripped
   zero pass. This is the one #7024 established, and its scope note says: "Growth happens by adding
   a named file, never by widening a glob." Give the two files their own labelled pass (`hits_8664`).
   Its PASS line must carry the literal `grep-q-zero-8664-pass` (the Observability probe's expected
   output), and its FAIL line must not. Before the pass, check each named file with
   `git ls-files --error-unmatch <file> || FAIL=1`. `git grep` on a renamed or deleted path returns
   nothing and would PASS, which would silently switch off the zero pin (test-design review,
   finding 3). This
   is the residual control for a *second* verdict site that reintroduces the `| grep -q` spelling,
   anywhere in either file.

4. **`plugins/soleur/test/fixture-relative-assert.baseline.txt`**: this file has rows for both suites
   (one row each, `1<TAB>…zot-pull-mutation.test.sh` and `1<TAB>…inngest-bootstrap.test.sh`). Run
   `bash plugins/soleur/test/fixture-relative-assert.test.sh`. Only if it reds on these two rows,
   regenerate with `--write-baseline` in the same commit, and confirm the baseline diff touches only
   those two rows.

### Files to Create

None.

## Non-Goals / Out of Scope

- **`run-registered-suites.sh` / `suite-shard-legs.tsv`**: the cause is not in the runner. They are
  owned by sibling draft PR #8763 (#8736) and are not touched here.
- **`inngest-userdata-budget.sh` / `registry-userdata-budget.sh` `printf '%s' "$TF_JOINED" | grep -q`
  sites**: these are **immune by construction**. `TF_JOINED` is `tr '\n' ' '`-joined into ONE line,
  and `grep` matches whole lines, so `grep -q` must read to EOF before it can match. There is no
  early exit and nothing left to write (measured 0/4000 under load). No change, no issue.
- **The guard's `… | head -1` pipelines** (7 unguarded plus 12 `|| true`-guarded; the census is in
  Guard 2): the unguarded producers are ≤135 B (single write), so they are unreachable. Converting
  all 19 to `grep -m1` was proposed in plan review (DHH) and declined: 19 edits to a 2,015-line
  guard for zero measured exposure is scope growth in a p3 fix. The widened header sentence names
  the class for future edits.
- **The same scorer shape in sibling batteries** (plan review, CTO F1): `apex-single-node-replace-mutation.test.sh:178`,
  `ssl-full-mitigation-mutation.test.sh:365`, `web-host-provisioner-parity-mutation.test.sh:289,875,1203`
  and `www-apex-canonicalizer-mutation.test.sh:560` pipe `grep … "$log"` into `grep -qF -- "$expect"`.
  They are not folded in. The operator asked for a small one-PR fix, and
  `apex-single-node-replace-mutation.test.sh` is in sibling #8763's diff. The work phase files ONE
  tracking issue listing these six sites, the capture-and-glob remedy, and the option of a shared
  `infra/lib/mutation-scorer.sh` (CTO F6). The same choice is recorded in `decision-challenges.md`
  for the operator.
- **The repo-wide early-exit-consumer class** (#6601, #7005, #7432's linter): tracked there. At ship,
  post one comment on #7005 with the ~4 KiB refinement of its "64 KiB threshold" claim.
- **Claiming #7376 is fixed**: mechanism B is a plausible contributor, but no CI evidence attributes
  #7376's failures to it. Cross-link only.

## Technical Considerations

- **Why capture-and-glob, not a herestring, at site A:** both remove the pipe. The glob needs no
  subprocess and no temp file, and the input is already in memory. The repo precedents are
  `infra-config-repush-mutation.test.sh`'s "Filtered through a variable" note and
  `workspaces-luks-g4-mutation.test.sh`'s HARNESS DISCIPLINE list.
- **Why a file operand, not `|| true`, at site B:** `|| true` would make the guard survive a 141,
  but awk's output would then depend on whether it ran to the `fi` before the producer died. With a
  file operand there is nothing to race.
- **Performance:** +1 guard run (about 3 s) and +1.26 MB of synthetic log written once to `$WORK`.
  This is negligible next to a 3-minute battery.
- **No production surface:** both files are CI test harnesses. No template, Terraform or runtime byte
  changes.
- **Does merging this PR alone change production? No.** A push to `main` touching
  `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml`, and one touching
  `apps/web-platform/infra/*.sh` fires `validate-vector-config.yml`. No `.tf`, template or deployed
  script byte changes, though, and no `.tf` reads these test files: `grep -nE
  'fileset\(|filesha256\(' apps/web-platform/infra/*.tf` finds no reference to them. The targeted
  plan therefore has nothing to apply. The PR body's first line should say so.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The change is confined to CI test
  harnesses. The indirect risk is a battery that under-detects: a scorer made always-KILLED would
  certify the zot-pull guard while it has a hole, and a later regression in the dedicated Inngest
  host's bootstrap pull arm could then ship unguarded. The scorer self-test's two probes and the drift guard exist to
  prevent exactly that.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. No
  credential, user data or network surface is read or written. The synthetic logs are fabricated
  strings in a `mktemp` scratch dir.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the touched apps/web-platform/infra/ files are CI test harnesses (a mutation battery and its guard) that never render into user_data or run on a host, so no user-facing path changes.`

## Observability

```yaml
liveness_signal:
  what: "the battery's closing lines '=== Results: 61/61 mutants killed ===' and 'OK', plus the grep-q-pipe-guard PASS lines for the two named files"
  cadence: "per infra-validation run (PRs and pushes touching apps/web-platform/infra/**) and per local run-registered-suites.sh invocation"
  alert_target: "the infra-validation check run on the PR/commit (red check) and the local runner's 'RED <path>' line"
  configured_in: "the suite files themselves (apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh, cloud-init-inngest-bootstrap.test.sh), registered for CI in .github/workflows/infra-validation.yml and run locally by apps/web-platform/infra/run-registered-suites.sh; cite the suite paths, not step names, because sibling #8763 restructures those steps"
error_reporting:
  destination: "GitHub Actions check-run log for infra-validation (test harness; no runtime Sentry surface)"
  fail_loud: "'HARNESS ABORT: scorer self-test' (exit 2), 'BROKE:    g1b-mustpass-padded-pull-item', '[FATAL] anti-vacuity floor', 'FAIL: pipe-into-grep-q found'"
failure_modes:
  - mode: "scorer regresses to a piped early-exit match (site A)"
    detection: "the scorer self-test's needle-first probe aborts the battery with exit 2 on every run (deterministic, ~1 MiB filler)"
    alert_route: "infra-validation red check on the PR"
  - mode: "guard's Guard 1b splitter regresses to a producer pipe (site B)"
    detection: "must-PASS row g1b-mustpass-padded-pull-item reports BROKE (guard rc non-zero, 0 FAIL lines) on every run"
    alert_route: "infra-validation red check on the PR"
  - mode: "a new '| grep -q' verdict site appears in either file"
    detection: ".claude/hooks/grep-q-pipe-guard.test.sh named-file pass FAILs"
    alert_route: "the CI job that runs .claude/hooks/*.test.sh (red check)"
  - mode: "a different early-exit consumer (head, sed q, awk exit) is added elsewhere in either file"
    detection: "not mechanically detected (declared under-approximation); surfaces as an intermittent RED in run-registered-suites.sh, the class #7376 diagnoses"
    alert_route: "the local runner's 'RED <path>' line and #7376's per-suite diagnostics"
logs:
  where: "GitHub Actions run logs for infra-validation; locally the runner's per-suite log dir (SOLEUR_SUITE_LOGDIR)"
  retention: "GitHub Actions log retention for the repository (90-day default); local logs until the runner's scratch root is reaped"
discoverability_test:
  command: "bash .claude/hooks/grep-q-pipe-guard.test.sh"
  expected_output: "grep-q-zero-8664-pass"
```

The literal `grep-q-zero-8664-pass` is a token that item 3 of Files to Edit requires the new
named-file pass to print on its PASS line **only**, never on its FAIL line. The earlier value,
`PASS: no pipe-into-grep-q in`, is one token that contains whitespace. deepen-plan Phase 4.7 rejects
that shape, and it would also match the unrelated hooks-tree PASS line. Phase 4.7's "suite-shaped
command" proxy matches `grep-q-pipe-guard.test.sh`, and that is a false hit: the file is a
0.24-second `git grep` drift check (measured), not a suite, and it finishes well inside Check 10's
15-second cap. It is also shell-metacharacter-free, and its first token `bash` is on the allowlist.

## Guard Contract

### Guard 1 — battery scorer: a row's verdict is a function of its log's bytes

**Property.** For every case log, the battery scores row R KILLED exactly when some `^  FAIL`-prefixed
line of that log contains R's expected substring, regardless of process scheduling or the producer's
write granularity.

**Assembly.** Every verdict-bearing read of a case log in `cloud-init-inngest-zot-pull-mutation.test.sh`:
(a) `case_mutate`'s named-assertion check, which after this change goes only through `failed_on`,
the single chokepoint; (b) the G4 liveness read `grep -qF "  PASS: $_live" "$log"`, a file operand
with no pipe, unchanged; (c) `case_must_pass` and the baseline, which read `rc` only; (d) the harness
rows (`ng1-harness-row1-self-compare`, `g1-row13-harness-probe`, `g4-harness-syntax-error-not-killed`),
which match captured `$(…)` text with `[[ == ]]`. Nothing enforces the chokepoint structurally, so the
second-member control is the `grep-q-pipe-guard` named-file zero pass over the whole file.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `failed_on`'s body to `grep -E '^  FAIL' "$1" \| grep -qF "$2"` | RED: the needle-first probe reports not-found and the battery aborts with exit 2 (measured 200/200 with the piped form on a 1.26 MB log of this shape) |
| 2 | `failed_on` → `return 0` (always found) | RED: the `SELFTEST-ONLY-ON-PASS` probe reports found, abort exit 2 |
| 3 | Drop the `^  FAIL` scope (`grep -F` over the whole log) | RED: the `SELFTEST-ONLY-ON-PASS` probe reports found, abort exit 2 |
| 4 | Add a SECOND verdict site after the compliant first, e.g. a new row scored with `grep … "$log" \| grep -qF …` | RED: `grep-q-pipe-guard.test.sh` named-file pass FAILs |
| 5 | Disarm the self-test by editing its FIXTURE: write the needle last, or drop the `^  FAIL` prefix from the filler | RED: the fixture-shape checks (line 2 is the needle; ≥20000 `^  FAIL: filler` lines) `die`, exit 2 |

**Harness rows.** Suite edit that must red it: row 2 targets the scorer the self-test dispatches
through, and a stubbed `failed_on` is exactly the "guard that asserts nothing" shape. Must-PASS
non-canonical input: the needle-first fixture, which requires a KILLED-direction verdict on a log
shaped like no real guard run (20,000 filler FAIL lines), and every existing KILLED row. RED-only rows
cannot detect an always-MISROUTED scorer, but these rows do. Declared under-approximation: deleting
the self-test block outright is caught only by review. Plan review cut a probe-counter floor as a
test of a test.

**Anchor.** The self-test's expected verdicts are literals in the same file as `failed_on`, so one
diff can change both. The drift guard lives in `.claude/hooks/`, a separate reviewed file. Review is
the anchor, and this is declared, not claimed away.

### Guard 2 — the guard's Guard 1b arm splitter cannot be killed by scheduling

**Property.** No pipeline in `cloud-init-inngest-bootstrap.test.sh` that can terminate the guard under
`set -euo pipefail` has a last stage that may stop reading before its producer finishes.

**Assembly.** Every pipeline in the guard whose last stage can exit before EOF. Census (measured
2026-09-25, `grep -nE '\|[[:space:]]*(head|grep -[A-Za-z]*[qm]|awk|sed -n[^|]*q)'` over the file):
**live**: the Guard 1b `sed … | awk … exit` splitter (7,380 B producer, 33/3000 under load);
**latent**: the three `wf_block … | grep -qxF` asserts (≤2,824 B, 0/6000); **unreachable**: the
seven unguarded `X=$(grep … | head -1 …)` assignments (`BOOTSTRAP_LINE`, `WEBPLATFORM_LINE`,
`IF_LINE`, `COMMENT_LINE`, `TRAP_DISARM_LINE`, `NG1_TF_IP`, `NG1_STUB_IP`), whose producers are
≤135 B and so are written in one call; **harmless**: the twelve `… | head -1 … || true` forms
(`PIN`, `DED_PIN`, `NIC_IDX`, `INS_IDX`, `zg_line`, `ZG_GHCR_REF`, `ZG_ZOT_LINE`, `ZG_ZOT_DIGEST`,
the two Guard B reads, `GA_PIN_TAG`, `g4_at`). There, a late 141 cannot change the captured first
line, and `|| true` cannot kill the guard. There is no single chokepoint. The per-site conversion is
backed by the drift guard (the `grep -q` spelling) and the padded must-PASS row (the live `awk exit`
instance).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `sed -E '/^[[:space:]]*#/d' "$DED_BLOCK_FILE" \| awk …` | RED: `g1b-mustpass-padded-pull-item` BROKE (guard rc non-zero, 0 FAIL lines) on every run (measured deterministic on the scratch sandbox: rc=141) |
| 2 | Drop the new first rule `/^[[:space:]]*#/ { next }` | RED: the guard's baseline reds on `G1b: each arm carries exactly ONE soleur-boot-emit call`, because the missed arm's comment block mentions `soleur-boot-emit`, and the battery aborts on the unmutated baseline (verify at work time) |
| 3 | Reintroduce a SECOND early-exit site after the compliant first: `wf_block … \| grep -qxF …` | RED: `grep-q-pipe-guard.test.sh` named-file pass FAILs |
| 4 | Make the padded row's mutator a no-op (anchor miss) | RED: `case_must_pass` dies "must-PASS edit did not change … tested NOTHING" (the existing landing assertion) |

**Harness rows.** Suite edit that must red it: row 4 (the regression row's own dispatch). Must-PASS
non-canonical input: the padded pull item itself, a compliant tree whose bytes differ from canonical
in a way the property allows.

**Anchor.** The padded row and the splitter both live in this PR's two files. Nothing outside the
commit pins them. Review is the anchor, and this is declared.

## Acceptance Criteria

- [x] **AC1 (RED before GREEN, `cq-write-failing-tests-before`, two ordered cycles).**
  (a) Extract the scorer **as-is** (still piped) into `failed_on` and add the self-test. The battery
  aborts with exit 2 on the needle-first probe. Then switch `failed_on` to capture-and-glob, and the self-test passes.
  (b) Add the padded must-PASS row against the **unfixed** guard. It reports
  `BROKE:    g1b-mustpass-padded-pull-item` (guard rc non-zero, no FAIL lines; quote the observed rc). Then fix the splitter,
  and it reports `HELD`. Quote all four outputs in the PR body.
- [x] **AC2.** After the fixes: `bash apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh`
  ends `=== Results: 61/61 mutants killed ===` / `OK`, and
  `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` ends
  `BOOTSTRAP_SUITE_OK unconditional=153 floor=153 total=230 rendered=ran`. This is on a host with
  terraform, as CI's `setup-terraform` provides. Without terraform the line reads
  `rendered=SKIPPED-no-terraform` and the total differs, so the AC pins `rendered=ran` (Kieran P2-5).
- [ ] **AC3 (the issue's acceptance; equivalent concurrent load).** One round of 10 concurrent battery
  copies with a shared `TMPDIR=/var/tmp/<dir>` produces **0 non-KILLED rows across 10 runs**. Every
  copy must also exit rc=0 and end with `=== Results: 61/61 mutants killed ===` followed by `OK`. A
  copy that aborts with exit 2 (a non-green baseline under load, a self-test abort, or an OOM) prints
  no verdict lines, so counting verdict lines alone would score it clean (test-design review,
  finding 4). The
  pre-fix baseline on the same harness and machine was **6/20** runs failing, one non-KILLED row each:
  round 1 had 5/10 at load 30-45, and round 2 had 1/10 at load 27-30. That gives an unfixed per-run
  rate of about 0.3, so P(0/10 | unfixed) ≈ 0.03. The deterministic drivers in AC1 are the primary
  evidence, and AC3 is the issue's literal acceptance, run as a smoke test. Plan review (DHH,
  simplicity, CTO) cut this from 30 runs. **Non-gating and machine-bound** (Kieran P2-6): record
  `nproc` and the peak load average next to the result. On a machine that cannot reach load ≥ 25, AC1
  alone carries the proof.
- [x] **AC4.** Before the fix, the drift guard's own pattern with its comment filter
  (`git grep -nE '\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q' -- <both files> | grep -vE ':[0-9]+:[[:space:]]*#'`)
  reports **4** hits: the guard's three `wf_block` asserts and the battery's scorer. After the fix it
  reports **0**. `bash .claude/hooks/grep-q-pipe-guard.test.sh` PASSes and names both files. With
  `| grep -qF` temporarily reinserted at `failed_on`, it FAILs (Guard 1 row 4). Revert.
- [x] **AC5.** Guard 1 rows 1-3 and 5, and Guard 2 rows 1-2, are each driven once at work time (scratch edits,
  reverted) and red as stated, with the one-line observed output quoted in the PR body. Guard 1 row 4
  and Guard 2 rows 3-4 are covered by AC4 and by the existing landing check. Plan review trimmed this
  from all rows.
- [x] **AC6.** `bash plugins/soleur/test/fixture-relative-assert.test.sh` and
  `bash scripts/guard-vacuity-floor.test.sh` PASS (baseline regenerated only on the two rows, if
  needed).
- [x] **AC7 (CI-form lints, per the one-shot brief).**
  `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"` passes (no
  SKILL.md is touched, so this is a no-op, and that is confirmed rather than assumed). No `.ts` is
  touched, so eslint has nothing to lint: confirm with `git diff --name-only origin/main... | grep -c '\.ts$'` → `0`.
  `shellcheck` is clean on the three touched `.sh` files, at the severity CI uses.
- [x] **AC8.** `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-25-fix-zot-pull-mutation-harness-row-misroute-plan.md` exits 0.
- [x] **AC9.** The diff touches no file in #8763's set (`run-registered-suites.sh`, `suite-shard-legs.tsv`, …):
  `git diff --name-only origin/main... | grep -cE 'run-registered-suites|suite-shard-legs'` → `0`.
- [ ] PR body: `Closes #8664`, the reconciliation of the misnamed row, and the ~4 KiB threshold note.

## Test Scenarios

- Given a case log whose target FAIL line is followed by ≥1 MiB of FAIL lines, when the scorer runs,
  then it reports found, every time.
- Given a log whose target appears only on a PASS line, when scored, then not found (MISROUTED).
- Given a tree whose bootstrap pull item carries ~150 KB of no-op lines after `docker create`, when
  the guard runs, then it exits 0 with 230 assertions and the battery row reports HELD.
- Given 10 concurrent battery copies sharing `TMPDIR`, when all finish, then every copy ends
  `61/61 mutants killed` and `OK`.
- Regression: all 60 existing rows keep their verdict in isolation.

Verification commands (local; CI runs the full battery in infra-validation):

```bash
bash apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh   # 61/61, OK
bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh           # BOOTSTRAP_SUITE_OK
bash .claude/hooks/grep-q-pipe-guard.test.sh
bash plugins/soleur/test/fixture-relative-assert.test.sh
bash scripts/guard-vacuity-floor.test.sh
python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"
python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-25-fix-zot-pull-mutation-harness-row-misroute-plan.md
```

Concurrent-load repro for AC3 (the scratch helper is not committed). Run N copies in the background
with `TMPDIR=/var/tmp/zotrepro-8664`, wait, and count `^  (SURVIVED|MISROUTED|UNRESOLVED|BROKE)`
lines. To diagnose, keep each run's `$WORK` by exporting a bash `rm` function that no-ops on the
`inngest-zot-mut-*` root.

## Research Insights

**Premise validation.** #8664 is OPEN, and no PR closes it. The cited files exist on `origin/main`
(merge-base `6169164d7c`). The battery has grown from 46 to 60 rows since the issue was filed
(#8708, 2026-09-24), which is why the issue's `45/46` now reads as `59/60`. Sibling #8763 touches the
runner and the shard manifest but neither suite file (checked `gh pr view 8763 --json files`). No
open `code-review` issue names any planned file.

**Property list (Phase 0.6b).**

1. A row's verdict is a function of that row's log bytes only.
2. The guard's run never ends because of how a pipe reader was scheduled.
3. Reintroducing the defect is caught deterministically, not at 1-2%.

**Cut list.** Mechanism the issue proposed, then the property it would buy, then what covers it:

- "serialize what it depends on": property 1/2 are already bought by removing the pipe. Serializing
  would only lower the probability.
- "isolate `TMPDIR` / fixed-path fixtures": no property. Every path is already `mktemp`-unique
  (verified).
- A new ad-hoc `| grep -q` lint inside the battery: property 3 for the `grep -q` spelling is already
  covered by `.claude/hooks/grep-q-pipe-guard.test.sh`'s named-file pass. Add the files there instead.

**Measurements (all on this worktree, 16 cores).** Isolation: 60/60 in 3m13s. Concurrent round 1
(10 copies, load 30-45): 5/10 runs failed, with the rows listed in the Reconciliation. Round 2 (load
27-30): 1/10 failed (`g1-row4-served-call-in-missed-arm`, mechanism B). Pipeline loops under
that load: site A 64/3000 → 141, site B 33/3000 → 141, `wf_block|grep -q` 0/6000,
`printf "$TF_JOINED"|grep -q` 0/4000. Deterministic drivers: the piped scorer on 1.26 MB 200/200
wrong and the captured form 0/200. The unfixed guard on the padded tree rc=141 with 0 FAILs, and the
fixed guard rc=0 with 230 assertions.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-07-15-a-reproduced-symptom-does-not-validate-the-mechanism-you-attached-to-it.md`.
  A SIGPIPE story was once reasoned and wrong (48 KB < 64 KiB). Here each mechanism was **executed**
  (the loops above), not inferred from the symptom. The execution also showed that the 64 KiB bound
  in that learning applies only to single-write producers.
- `knowledge-base/project/learnings/test-failures/2026-09-23-my-sigpipe-regression-guard-pinned-the-file-size-not-the-cause.md`
  (#8644). It gave this plan the needle-first fixture with the needle placed ahead of the bulk of
  the output, a positive control on the same file as the negative probe, and the "never pin 141"
  rule. Its causal-floor and rc-2 remedies were weighed and cut in plan review: here a negative
  verdict fails the battery, so it is not fail-open. Its note that `grep-q`-style regexes miss
  `grep -F -q`, `--quiet`, a trailing `|` and `head` is why this plan declares the drift guard's
  pattern an under-approximation, not a proof.
- `.claude/hooks/grep-q-pipe-guard.test.sh` (#6992/#7024): the canonical zero-pin, "growth by naming a
  file". `scripts/test-all.sh` runs it through its `.claude/hooks/*.test.sh` entry.
- The prior-art idioms `infra-config-repush-mutation.test.sh` ("Filtered through a variable") and
  `workspaces-luks-g4-mutation.test.sh` (HARNESS DISCIPLINE: "NEVER `producer | grep -q` under
  pipefail").
- The guard's own header already bans `producer | grep -q`, and it records one earlier instance that
  "surfaced as the mutation battery's sandbox baseline going RED". The rule was right, but its
  spelling was too narrow (`grep -q` only, not `awk … exit`), and three sites had crept back.

**Related issues.** #7376 (runner flaky, three suites; cross-link), #7432 (JOBS=1 stopgap + a grep-q
linter), #7005 / #6601 (repo-wide SIGPIPE class; post the threshold refinement on #7005), #6480
(no required check covers the infra shard).

**CLAUDE.md / AGENTS.md conventions.** `cq-write-failing-tests-before` (AC1),
`hr-never-run-commands-with-unbounded-output` (repro logs go to files, and only summaries are read),
`hr-when-a-command-exits-non-zero-or-prints` (a 141 is investigated, never retried away),
`cq-assert-anchor-not-bare-token` (the padded row anchors on the code line, not on the comment
mentioning `docker create`, which is the first occurrence in the file).

## Open Code-Review Overlap

None. Checked `gh issue list --label code-review --state open` against all four planned paths.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: this is a change to test-harness and CI tooling only.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled here.
- **The first `docker create --name soleur-inngest-bootstrap-extract` in `cloud-init-inngest.yml` is a
  COMMENT** (the line starting `# cloud-init.yml opened by …`). A pad anchored on the bare token
  lands in a comment block and breaks the YAML render. That happened in the first scratch attempt:
  33 FAILs, all NIC-G1/G4 dispatch. Anchor on the full code line with its 4-space indent and `"$IREF"`,
  exactly once.
- **`grep MISROUTED` over a battery log matches a PASSING line** (the harness row's `(MISROUTED)`
  suffix). Read verdict prefixes (`^  (SURVIVED|MISROUTED|UNRESOLVED|BROKE):`), never bare tokens.
  This is how #8664 named the wrong row.
- **Never pin rc=141 in an assertion.** Where SIGPIPE is IGNORED (the disposition #8644 measured on
  CI), the producer gets EPIPE and exits 2 instead of dying with 141. The padded row therefore
  reports BROKE on any non-zero guard rc, and AC1 quotes whatever rc it observed.
- **Put the needle first and the bulk after it** (`knowledge-base/project/learnings/test-failures/2026-09-23-my-sigpipe-regression-guard-pinned-the-file-size-not-the-cause.md`).
  What makes the old shape fail is the output the producer still has to write AFTER the match: the
  FAIL filler after `SELFTEST-TARGET`, and the non-comment pad after the arm split. A fixture that
  puts the needle last, or writes the pad as `#` lines (which the comment filter deletes), is
  harmless to the old shape. It would pass while proving nothing. The negative probe carries a
  positive control on the same file.
- **No CODE line in either file may spell the old pipe shape**, even in a string or a trailing comment.
  That rules out a `die "… | grep -q …"` message and `cmd  # was: … | grep -qF`.
  `grep-q-pipe-guard.test.sh` strips only whole-line comments, so either would FAIL it (Kieran P2-4).
  Write explanations on their own `#` lines.
- **`scripts/guard-vacuity-floor.test.sh:603` still cites `BATTERY_MIN_ROWS=46`** (stale since #8708).
  It is left alone on purpose: it is prose inside another suite's promotion note, and nothing parses
  it (Kieran P2-9).
- **Size does not make a pipe safe.** For stdio-buffered producers (`grep`, `sed`, `awk`) the exposure
  starts at the first write after the reader has matched, which is about 4 KiB, not 64 KiB. The fix
  removes the pipe, and no AC may be phrased as "the output is small enough".
- The scratch sandbox for AC5 needs the Guard A git fixture (a loose `refs/tags/vinngest-<pin>` ref
  pointing at a pristine commit). Without it, Guard A reds, the baseline is not green, and every
  verdict is meaningless. Reuse the battery's own sandbox (run the battery) rather than hand-building
  one.
- Editing `.claude/hooks/*.test.sh` may trip a hooks-protection PreToolUse guard. If it does, follow
  the guard's instruction and do not bypass it.

## Implementation Notes (2026-09-25)

Observed outputs, as captured by the work phase:

- **AC1a**, piped `failed_on` with the self-test in place: rc=2, `HARNESS ABORT: scorer self-test: a FAIL line followed by 1 MiB of FAIL output scored NOT found`. Capture-and-glob: the self-test passes.
- **AC1b**, padded row against the unfixed guard: `BROKE: g1b-mustpass-padded-pull-item … (rc=141)`, no FAIL line, and the log ends at `--- Guard 1b (#6500): per-arm Sentry stage emits (dedicated host) ---`. Battery `60/61`. Against the fixed guard: `HELD`.
- **AC2**: `=== Results: 61/61 mutants killed ===` / `OK`, and `BOOTSTRAP_SUITE_OK unconditional=153 floor=153 total=230 rendered=ran`.
- **AC4**: the pattern count over both files is 4 on `origin/main` and 0 on the branch. Reinserting a `| grep -qF` into `failed_on` produces `FAIL: pipe-into-grep-q found in a file #8664 took to zero`.
- **AC5**. Every row exits with rc=2 unless noted:
  - Guard 1 row 1 (piped body) → `… scored NOT found`.
  - Row 2 (`return 0`) and row 3 (unscoped `FAIL`) → `a string present only on a PASS line scored found`.
  - Row 5a (needle last) → `the needle is not line 2 of its fixture`.
  - Row 5b (unprefixed filler) → `the fixture lost its FAIL filler after the needle`.
  - Guard 2 row 1 is the AC1b run.
  - Guard 2 row 2 (comment rule dropped) → rc=1 `FAIL: G1b: each arm carries exactly ONE soleur-boot-emit call (served 1, missed 2)`.
- **AC6**: `fixture-relative-assert` 62/62 (no baseline change needed) and `guard-vacuity-floor` 23/23.
- **AC7**:
  - `lint-skill-body-budget --base <merge-base>` OK.
  - 0 `.ts` files.
  - `shellcheck -S warning` over the three files emits 22 findings, the same count as `origin/main`. All are pre-existing SC2034 on variables read inside `assert`'s eval strings. The two new `WF_*` variables carry a disable annotation.
- **Sibling scorer sites**: tracked in #8855. `web-host-provisioner-parity-mutation.test.sh` scores on `grep -F "[FAIL]" "$OUT"`. A work-time re-census keyed on `"$log"` missed its three sites, and the plan's list is what caught them.
