# Acceptance verification — #7216 / #7227

Each row records the command that decided it and what that command printed. Suite totals are
from the as-written files, not from the plan (all four floors were re-derived).

## Measured baselines vs. final

| measurement | baseline (plan Phase 0) | final | command |
| --- | --- | --- | --- |
| git-data-luks | 113 passed, 0 failed | **133 passed, 0 failed** | `bash apps/web-platform/infra/git-data-luks.test.sh` |
| git-data-runcmd-rehearsal | 36 assertions, 0 failed | **44 passed, 0 failed** | `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` |
| evidence-capture | 30 passed, 0 failed | **33 passed, 0 failed** | `bash tests/scripts/test-git-data-rung2-evidence-capture.sh` |
| git-data-rung2-rehearsal | 70 passed, 0 failed | **71 passed, 0 failed** | `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` |
| user_data `stored` | 25,968 B (headroom 6,800) | **30,148 B (headroom 2,620)** | `bash apps/web-platform/infra/git-data-userdata-budget.sh` |
| encryption-posture | 16 stores, 3 connections, 0 unledgered, 0 failing → PASS | **unchanged** | `python3 scripts/lint-encryption-posture.py [--repo-sweep]` |

## Phase 0.4 — `isLuks` exit codes, re-taken on this branch (AC17)

```
cryptsetup 2.7.0 flags: UDEV BLKID KEYRING FIPS KERNEL_CAPI HW_OPAL
rc_nonluks=1
rc_missing=4
rc_notfound=127
```

`rc_nonluks=1` is the plan's STOP condition and it holds.

**But rc=1 is NOT sufficient to authorise a format, and the first cut of this PR wrongly said it
was.** Multi-agent review refuted it and the refutation was reproduced on the pinned image:

| device state | `isLuks` rc | stderr | `blkid TYPE` |
| --- | --- | --- | --- |
| blank | 1 | *(empty)* | *(empty)* |
| real LUKS2 | 0 | — | `crypto_LUKS` |
| **LUKS2, both header JSON areas corrupted** | **1** | **empty** | **`crypto_LUKS`** |
| zero-length device | 1 | — | — |

1 is cryptsetup's DEFAULT errno bucket, so a DAMAGED header on a populated store is
indistinguishable from a blank volume by rc alone — and `isLuks` emits nothing on that path, so
the fatal would have carried no cause either. `apps/web-platform/infra/workspaces-luks.tf`
already ruled on this ("MUST use the `blkid -o value -s TYPE` discriminator … NEVER
`cryptsetup isLuks` — the documented data-destroyer on a populated device"), and its escape
clause ("safe on git-data only because its host is born fresh") stopped holding when
`git-data-cutover.sh` made this volume the rsync target. The `1)` arm now requires a positive
blankness proof, and `blkid`'s own rc is checked so "could not measure" never reads as "blank".

## The measurements the fix rests on

**Forged rc=1 from a failed redirect** (why the capture is a substitution, not `2>>`):

```
$ ( set -euo pipefail; _rc=0; /bin/true 2>>/proc/sys/nonexistent/x.log || _rc=$?; echo "rc=$_rc" )
rc=1
```

**`:` is a POSIX special builtin, so a failed redirect EXITS the shell** (why every per-stage
truncation is wrapped in a subshell). The parent runcmd shell is `/bin/sh` = dash:

| shell | form | reached the next statement? |
| --- | --- | --- |
| dash | `: > "" 2>/dev/null \|\| true` | **no — shell exited, rc=2** |
| dash | `( : > "" ) 2>/dev/null \|\| true` | yes, rc=0 |
| bash | `: > "" 2>/dev/null \|\| true` | yes, rc=0 |

bash tolerates it, so this hazard is invisible to any test that does not use the real
interpreter. It was caught by `git-data-runcmd-rehearsal.test.sh` S1, which runs the extracted
stage under dash in a real `ubuntu:24.04` container.

**Emitter-relative token indexing** (why `toks[4]` had to go), measured against the real
folded `gc_timer` line:

```
toks[0..5]            = ['systemctl', 'enable', '--now', 'git-data-gc.timer', '||', '/usr/local/bin/git-data-emit']
toks[4]               = '||'
emitter-relative arg4 = '/var/log/cloud-init-output.log'
```

## Phase 1 RED, observed before any fix (AC16)

| arm | observed |
| --- | --- |
| B18 | `FAIL: B18 isLuks-rc-branch: property does not hold on the real file` (113 passed, 1 failed) |
| R3(3b) | verdict set `{on_err: LITERAL, sshd_config: LITERAL, bootstrap_err: LITERAL, luks_err: VAR:GUARDED}` — an exact match to the plan's pre-measurement; plus `gc_timer\|warning\|LITERAL\|/var/log/cloud-init-output.log` |
| capture prefix | `FAIL the PRODUCTION host name soleur-git-data is refused (rc 64)` — i.e. it was ACCEPTED |
| arm 10 | `FAIL … does not pin the rehearsal prefix (got 'none', want 'soleur-git-data-rehearsal-')` |

## Acceptance criteria

| AC | verdict | evidence |
| --- | --- | --- |
| AC1 no `if ! cryptsetup isLuks`; substitution capture + `case` | PASS | B18 predicates (a)(b)(c), green |
| AC2 exactly one arm reaches luksFormat, **inside the `1)` arm**; catch-all exits 1 | PASS | B18 (d)(e)(g) — (d) alone is a COUNT and permitted the format on `*)`; (g) pins position, with a relocation mutation |
| AC3 naked-capture and `2>>`-on-probe are DETECTED | PASS | B18 mutation arms; `assert_mutation` fails loud if a mutation does not flip |
| AC4 `p_isluks` reads `_luks_slice`, not the raw file | PASS | re-pointed; measured that `cryptsetup isLuks` occurs only on the code line today, so the re-point forecloses the vacuity this PR's own comment would introduce |
| AC5 every fatal emit passes a window-guarded, pairwise-distinct variable | PASS | R3(3b)(ii)(iii) + R3(3d) UNGUARDED control |
| AC6 no emit site at any level passes the cloud-init log | PASS | R3(3b)(v), emitter-relative indexing |
| AC7 seed precedes `trap on_err EXIT` and the first `2>>` | PASS | R3(2d) + relocation mutation |
| AC8 capture refuses production, accepts rehearsal, still refuses a quote | PASS | 33 passed, 0 failed |
| AC9 arm 10 includes the capture script's prefix literal | PASS | 71 passed, 0 failed |
| AC10 `paths:` parsed as YAML contains the capture script | PASS | `present in parsed paths: True` (18 entries) |
| AC11 budget prints `stored=<n> B` and n < 32768 | PASS | see final budget below |
| AC12 `lint-encryption-posture.py` + `--repo-sweep` PASS at baseline | PASS | both `16 stores, 3 connections, 0 unledgered, 0 failing checks -> PASS` |
| AC13 evidence env absent and not in the diff | PASS | `ABSENT ok`; `git diff --name-only origin/main...HEAD` has 0 matches |
| AC14 bootstrap `log()` writes fd 2, asserted by an arm | PASS | B20, region-scoped to the `log()` body |
| AC15 clause B mechanized | PASS | B19a `special = false`, B19d `--key-file -` in the bootstrap payload, and pre-existing **A28a** for no-`set -x` — B19b/c were deleted as weaker duplicates of it |
| AC16 each RED observed and quoted | PASS | table above |
| AC17 rc measurement re-taken on the branch | PASS | `rc_nonluks=1` |
| AC18 all four floors re-derived with an itemised sum | PASS | luks 113→133, capture 30→33, rung2 70→71, runcmd 36→44 |
| AC19 ADR-147 addendum exists, records cost + headroom | PASS | also corrects that ADR's now-false "three arming sites" claim |

## Phase 5.1 — full-suite exit gate

`bash scripts/test-all.sh` → **rc=1, 258/259 suites passed**. The run's preamble confirms the
coverage boundary is on the right side of this diff:

```
NOTE: your diff touches apps/web-platform/infra/. The CI-registered infra runner
      (apps/web-platform/infra/run-registered-suites.sh) will be invoked below as a
      [nested suite]
```

and the nested runner reported **87 passed, 1 failed (of 88)**.

**The single RED is `cron-egress-firewall.test.sh`, and it is contention, not a regression.**
Not accepted as a flake — confirmed three ways, per the banner's own instruction:

1. **Isolated re-run on this branch: `216 passed, 0 failed` (rc=0).**
2. **No overlap.** `git diff --name-only <base>..HEAD` matches nothing cron/egress/firewall;
   that suite reads none of the files this PR touches.
3. **The run announced the contention itself:**

```
[contention] machine: 16 cores, load 10.09, MemAvailable 13736MB
[contention] siblings: 2 other worktree(s) running test-all.sh
[contention]   -> pid 2466210 in .worktrees/feat-one-shot-6808-luks-verify-schedule (running 2153s)
[contention]   -> pid 3585194 in .worktrees/feat-one-shot-7242-zot-mirror-error-misdiagnosis (running 578s)
[contention] BANNER SIBLING_RUN_DETECTED
```

The banner's third confirmation ("the matching CI gate") is CI on this PR, which runs the same
infra suites via `infra-validation.yml`. **Every suite this PR actually changes was green in
that same run**, including `git-data-runcmd-rehearsal.test.sh` under the nested runner.

## Corrections forced by multi-agent review

Ten agents reviewed this branch. They found **more defects in the guards this PR added than in
the fix itself**, and two claims recorded in an earlier revision of this very file were wrong.
Recorded here rather than silently overwritten, because the failure modes are the point.

| # | What the first cut claimed | What was measured |
| --- | --- | --- |
| 1 | "rc 1 is the ONLY genuinely-not-LUKS" | False. rc 1 is cryptsetup's default errno bucket; a corrupted-header LUKS2 device returns 1 with empty stderr while `blkid` still says `crypto_LUKS`. The `1)` arm would have formatted a populated store. |
| 2 | B18 pins the destructive branch | It pinned a COUNT. A tree with `1) : ;;` and `luksFormat` moved to the `*)` unknown-status arm satisfied every predicate. |
| 3 | The device wait protects the birth | It tested `-e` (present), which is true before the kernel sets capacity; a zero-length device also returns rc=1, feeding finding 1. Now `-b` + non-zero `getsize64`. |
| 9 | B18's `(h)`/`(i)` pin the blankness proof and the usability wait | They pinned TOKENS. Measured: `!=` → `==` INVERTS the refusal (blank volume bricked, damaged-header populated store formatted) and `-gt 0` → `-ge 0` breaks the wait on iteration 1 — both green at 128/0. Now the operator, branch and comparison are pinned; mutation arms perturb semantics, not their own anchor. |
| 10 | B20 pins the bootstrap's `log()` writer | Nothing pinned the PIPE. Deleting `2>>"$GIT_DATA_RUNCMD_DETAIL"` on the bootstrap `doppler run` returns to the pre-#7227 state, green in both suites. B18p added. |
| 11 | `R3(3b)(ii)` binds "every emit site" | It filtered `$2=="fatal"` — 3 of 7. The `gc_timer` WARNING, the site this PR's narrative names, was unbound. Widening it also surfaced that the fatal-only filter had been hiding a PARSE defect: the delivery assertion `if [ ! -x …git-data-emit ]` produced a bogus LITERAL row. The analyzer now emits a row only for a real call. |
| 4 | "129 passed, 0 failed" | True of the runs taken, but the suite was **non-deterministic** and determinism was never measured before asserting it. Predicates written `producer \| grep -q` under `set -uo pipefail` fail OPEN — grep exits on match, the producer takes SIGPIPE, the pipeline returns 141, and the `if` takes the ELSE branch. Measured 31/40 on the shape and 1 RED in 10 suite runs. Converted to herestrings; now **12/12 green**. |
| 5 | B19b/c mechanize no-`set -x` | Redundant with pre-existing **A28a**, which is strictly stronger (also catches `bash -x` and mid-flag `set -exuo`), covers every boot-path file, and greps the file directly so it cannot take the SIGPIPE path. Deleted rather than repaired. |
| 6 | Arm 10 pins the capture script's prefix | Satisfied by the refusal message that explains it — reverting the constraint left the arm GREEN. Re-anchored on the `=~` condition and demonstrated RED on that revert. |
| 7 | R3(2d) demonstrates ordering-vs-co-presence | Its mutation arm asserted only that its own `sed` landed and never re-ran the check. Now a function both arms call. |
| 8 | ADR: the model gap is "~2 kB, Node vs Go zlib" | The gap is kilobytes and the cause is a stale regex — the render module emits `replace(file(…))` **9 times** and `base64encode(file(` **0 times**, so all nine payloads model as 80-byte `x`-runs, and the test named for catching that asserts an obsolete shape. |

Also fixed: the shipped template still said "All THREE sites" after `bootstrap_err` was deleted;
`luks_err`'s middle-slot rationale described routing this PR had changed; a comment claimed "the
two probes above" where one exists; and the container capture-server's fixed `sleep 1` readiness
wait became a bounded poll, because under contention it fails `R3(3a)` and reads as a finding
about the emitter rather than a starved fixture.

## Deliberate deviations from the plan

1. **The restart warning does not reuse `_sshd_detail`.** The plan said to use it in all three
   `sshd_config` emits. Reaching the restart means `sshd -t` PASSED, so that file is empty and
   its literal fallback would blame the config check that succeeded — the misattribution
   per-stage truncation exists to prevent. It captures its own stderr instead.
2. **`gc_timer` and the restart use a substitution, not `2>>` on the command.** The plan
   prescribed `cmd 2>>"$FILE" || { emit }` for `gc_timer`. That shape cannot distinguish a
   failed REDIRECT from a failed command, so it emits a false warning; S1 demonstrated it for
   the restart. `2>>"$GIT_DATA_RUNCMD_DETAIL"` remains on exactly the four commands the plan
   scopes it to.
3. **The bootstrap stage's `trap - EXIT` + re-arm pair was deleted, not re-pointed at
   `on_err`.** It would have been a no-op: `trap luks_err EXIT` is inside the heredoc and binds
   the `doppler run` child, so the parent's `on_err` was never replaced.

## Not done in this run, by instruction

No rung-2 rehearsal dispatch and no git-data birth. Both are operator steps after merge, and
`git_data_rung2_rehearsal_gate` still HOLDs fail-closed with no evidence file (verified).
