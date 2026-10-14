# Learning: a guard parsed under one awk, and a review fix inherited an ignored signal; only a second interpreter and a fresh seat saw either

## Problem

S7c (#9217, PR #10085) widened the producer-side join in `.claude/hooks/grep-q-pipe-guard.test.sh` (any-producer arm, stub-name arm, helper arguments, loop-built stubs) and edited six owner suites. The guard was green under the author's host at every step. Four things were not visible from there.

1. **A parse error that only one awk raises.** `anybar` took a parameter named `base`, which is also a function in the same program. gawk accepts it; mawk stops (`awk: line 56: syntax error at or near base`), the join derived zero pairs, and the guard exited 3. The host has gawk only, the plan recorded "mawk unmeasured" and the evidence said "CI is the only mawk reading". Five of nine review seats found it in minutes by running the interpreter from a docker image (`docker create node:22-slim` plus `docker cp` of `/usr/bin/mawk`, no network or install). A second mawk-only defect sat behind it: `m[k] = m[k] ", " $3` built a leading comma because mawk creates `m[k]` first.
2. **A fix written during review introduced a P1, and only a fresh verifier found it.** Fix round C added a dynamic control that runs a stub that never reads under SIGPIPE `ignore` and SIGPIPE `default` and wanted rc 141 for `default`. A CI runner starts jobs with SIGPIPE already ignored, an ignored disposition is inherited and cannot be reset from bash (`trap - PIPE` is refused), so under `( trap '' PIPE; bash guard )` the `default` run is ignored too and reads rc 1. The guard went red (rc 1 at `14add998c3`, rc 0 at `8b43c9df5d`). Every run the author made had the default disposition. The same round's `squeeze` also dropped the intermediate consumers of a three-line chain behind a 9000-byte line, a recall loss against the pre-fix awk (decision-challenges item 76).
3. **A merge changed the population under every "final" figure.** `8b43c9df5d` merged main, which retired three suites; four exempt rows had to be dropped by hand and `PJ_TRIPLES` moved 263 to 258. Every figure the spec directory called final (153 pairs, 263 triples, 154 rows, 133 exempt) became the state of an earlier head, and two arithmetic lines in the decision record were already one short each.
4. **A claim about a shell written twice before it was measured.** Comments said a top-level `return` in a bash invoked as `sh` "reports an error and goes on"; the first correction said it exits 2. Measured on `bash:3.2` and the host's bash 5: bash 5 as `sh` is in POSIX mode and exits 2, bash 3.2 as `sh` goes on, a bash not named `sh` goes on on every version.

## Solution

- Rename the colliding parameter (`bs0`) and add a lint for the class (`pj_collide`, check `awk-param-collision`): it reads each program as one text, compares parameters with function names, has a positive control, a must-pass control and a two-collision control, and its dispatch is pinned per program NAME (a count alone passed `for _pn in PJ_AWK PJ_AWK`). Run the WHOLE guard with mawk 1.3.4 20200120, mawk 20240123 and busybox awk first on `PATH` as `awk`; the derived pairs and triples must be equal across all of them (sorted `cmp`).
- Make the SIGPIPE control know the disposition it was started with: read `trap -p PIPE` once, cross-check it against bit 12 of `SigIgn` in `/proc/$$/status` where that exists, and let `pj_disp_ok` accept rc 1 or 141 for `default` only when SIGPIPE was inherited ignored (rc 1 always for `ignore`). Drive the verdict both ways in fixtures: the relaxation must not become unconditional (`1 1 0` refused, `1 1 1` accepted). Run the guard under `( trap '' PIPE; ... )` and under `env -i PATH=/usr/local/bin:/usr/bin:/bin` with dash absent as part of every round that touches a control.
- Keep the text joined after a long line until it passes the cap again (`sqlen`) instead of squeezing on every feed, and prove it with chains of three and four lines and the backslash form.
- After a merge, re-derive every figure on the tree the section is committed on; append a "which figure belongs to which head" section and corrections that name the old sentence; never edit the old body. For rows whose suite main retired, drop the row, move the pin by exactly the triples the row's pair held, and say so.
- Measure a behavioural claim about a shell in a comment before writing it, on the versions the claim names.

## Key Insight

A verifier that runs on one interpreter, with one signal disposition, on one tree, certifies a property of that configuration. The cheap way out is to change the configuration, not to think harder: put a second awk first on `PATH` (one `docker cp`), start the guard with SIGPIPE ignored, with a stripped environment, and on the tree merged with current main. And a fix written inside a review round is new code under the same hazard as the code it fixes, so it needs the fresh-eyes verification pass the review skill already schedules after the last round (`risk-tier-and-fix-rounds.md` step 5): here that pass, not any author run, found the one defect that turned the guard red under a CI-shaped parent.

## Session Errors

1. **Shipped a gawk-only construct (function parameter named like a function) and a mawk-order-dependent string build** — Recovery: renamed, made the join order-independent (`if (k in m) ... else ...`), added `awk-param-collision` — Prevention: run the whole guard under mawk and busybox awk before the first push of any change to an embedded awk program; "unmeasured" in a plan is a task with a one-minute recipe, not a stated limit.
2. **A round-C control wanted rc 141 where CI inherits SIGPIPE ignored (P1, guard red at `14add998c3`)** — Recovery: `pj_disp_ok` plus the inherited-disposition probe and both-direction fixtures — Prevention: run each new control under `( trap '' PIPE; ... )` and `env -i` before calling a round done; the fresh verifier pass is the backstop and it worked.
3. **`squeeze` ran on every feed and dropped intermediate consumers of a chain behind a long line (recall loss)** — Recovery: `sqlen`, seven fixtures — Prevention: when a bound is added to a derivation, compare derived triples with the pre-change program on chains, not only on single lines.
4. **Bash 3.2-safe replacement of an associative array was 30 times slower (45 to 67 s guard)** — Recovery: one awk join in `pj_judge` — Prevention: time a rewrite on the real corpus before committing it.
5. **A fixture appended with `+=(` to a string variable was vacuous (14 shellcheck findings at an intermediate head)** — Recovery: fixed, proven by two count-line mutants — Prevention: shellcheck every edit of the guard; a finding count that moves is a vacuity signal.
6. **`set -e` ended the guard silently (rc 1, no FAIL text) when the checker's count line was missing** — Recovery: kept the `|| true` on the `read` and pinned the call shape — Prevention: a mutant that is red but prints no text of its own is a defect in the diagnostics, grade it as one.
7. **The guard's own awk comment carried the text `> "$d/jq"; chmod`, which `fixture-relative-assert` read as a relative redirect (one site over the baseline of 2067)** — Recovery: reworded the comment instead of regenerating the baseline — Prevention: pre-push ratchet lane before the first push of a guard edit; never baseline a new site a rewording removes.
8. **`ci-deploy.test` hit the lane's own 300 s member cap (295 s on the rerun)** — Recovery: recorded as cap-flaky at this host's load, no FAIL line — Prevention: none in this slice (the lane script is outside it); noted in the evidence.
9. **Main's retirement of three suites left four dead rows and every "final" figure stale; two arithmetic lines were one short each; `session-state.md` said twelve P2 findings where the review table sums to fourteen** — Recovery: decision-challenges items 59, 60, 69, 82 and the evidence section "which figure belongs to which head" — Prevention: derive every number on the tree the section is committed on and name its head.
10. **Wrote a bash-as-`sh` behaviour into comments, then into a correction, before measuring it** — Recovery: measured on bash 3.2 and 5, control asserts rc 2 (or 0 on bash 3.2) — Prevention: a claim about a shell version is a claim to run.
11. **QA session: a `git clone --local` into `/var/tmp` failed on a cross-device hardlink, and a 7-file `shellcheck` loop outran the 120 s tool timeout** — Recovery: `--no-hardlinks`, background run — Prevention: one-offs; clone scratch copies with `--no-hardlinks` when the scratch root is on another filesystem.

## Related

- `2026-10-12-a-text-pipe-derivation-read-an-annotation-echo-as-a-pipe-and-a-stub-drain-called-a-binary-its-sandbox-lacked.md` (S7b; its two corrections are S7c's R8 measurements)
- `test-failures/2026-10-04-a-forced-test-condition-needs-a-negative-control-and-proc-status-is-read-once.md` (the CI runner starts jobs with SIGPIPE ignored; `/proc/status` as the probe)
- `2026-09-04-every-defect-the-panel-found-was-in-my-verification-not-my-fix.md`, `best-practices/2026-07-04-bash-yaml-drift-guard-must-mutation-test-fail-open-and-allow-trailing-comments.md` (earlier mawk-only failures: the class has now recurred three times)

## Tags

category: test-failures
module: grep-q-pipe-guard
