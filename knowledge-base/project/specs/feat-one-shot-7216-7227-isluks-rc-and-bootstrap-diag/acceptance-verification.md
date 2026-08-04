# Acceptance verification — #7216 / #7227

Each row records the command that decided it and what that command printed. Suite totals are
from the as-written files, not from the plan (all four floors were re-derived).

## Measured baselines vs. final

| measurement | baseline (plan Phase 0) | final | command |
| --- | --- | --- | --- |
| git-data-luks | 113 passed, 0 failed | **129 passed, 0 failed** | `bash apps/web-platform/infra/git-data-luks.test.sh` |
| git-data-runcmd-rehearsal | 36 assertions | *(see below)* | `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` |
| evidence-capture | 30 passed, 0 failed | **33 passed, 0 failed** | `bash tests/scripts/test-git-data-rung2-evidence-capture.sh` |
| git-data-rung2-rehearsal | 70 passed, 0 failed | **71 passed, 0 failed** | `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` |
| user_data `stored` | 25,968 B (headroom 6,800) | *(final below)* | `bash apps/web-platform/infra/git-data-userdata-budget.sh` |
| encryption-posture | 16 stores, 3 connections, 0 unledgered, 0 failing → PASS | **unchanged** | `python3 scripts/lint-encryption-posture.py [--repo-sweep]` |

## Phase 0.4 — `isLuks` exit codes, re-taken on this branch (AC17)

```
cryptsetup 2.7.0 flags: UDEV BLKID KEYRING FIPS KERNEL_CAPI HW_OPAL
rc_nonluks=1
rc_missing=4
rc_notfound=127
```

`rc_nonluks=1` is the STOP condition and it holds, so rc 1 is the only "genuinely not LUKS"
and the `case` arms are correctly keyed.

## The two measurements the fix rests on

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
| AC2 exactly one arm reaches luksFormat; catch-all exits 1 | PASS | B18 (d)(e) + mutation arms "rc 0 also formats" / "catch-all no longer exits" |
| AC3 naked-capture and `2>>`-on-probe are DETECTED | PASS | B18 mutation arms; `assert_mutation` fails loud if a mutation does not flip |
| AC4 `p_isluks` reads `_luks_slice`, not the raw file | PASS | re-pointed; measured that `cryptsetup isLuks` occurs only on the code line today, so the re-point forecloses the vacuity this PR's own comment would introduce |
| AC5 every fatal emit passes a window-guarded, pairwise-distinct variable | *(runcmd)* | R3(3b)(ii)(iii) + R3(3d) UNGUARDED control |
| AC6 no emit site at any level passes the cloud-init log | *(runcmd)* | R3(3b)(v), emitter-relative indexing |
| AC7 seed precedes `trap on_err EXIT` and the first `2>>` | *(runcmd)* | R3(2d) + relocation mutation |
| AC8 capture refuses production, accepts rehearsal, still refuses a quote | PASS | 33 passed, 0 failed |
| AC9 arm 10 includes the capture script's prefix literal | PASS | 71 passed, 0 failed |
| AC10 `paths:` parsed as YAML contains the capture script | PASS | `present in parsed paths: True` (18 entries) |
| AC11 budget prints `stored=<n> B` and n < 32768 | PASS | see final budget below |
| AC12 `lint-encryption-posture.py` + `--repo-sweep` PASS at baseline | PASS | both `16 stores, 3 connections, 0 unledgered, 0 failing checks -> PASS` |
| AC13 evidence env absent and not in the diff | PASS | `ABSENT ok`; `git diff --name-only origin/main...HEAD` has 0 matches |
| AC14 bootstrap `log()` writes fd 2, asserted by an arm | PASS | B20, region-scoped to the `log()` body |
| AC15 clause B mechanized | PASS | B19a `special = false`, B19b/c no `set -x`, B19d `--key-file -` in the bootstrap payload |
| AC16 each RED observed and quoted | PASS | table above |
| AC17 rc measurement re-taken on the branch | PASS | `rc_nonluks=1` |
| AC18 all four floors re-derived with an itemised sum | PASS | luks 113→129, capture 30→33, rung2 70→71, runcmd 36→(below) |
| AC19 ADR-147 addendum exists, records cost + headroom | PASS | also corrects that ADR's now-false "three arming sites" claim |

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
