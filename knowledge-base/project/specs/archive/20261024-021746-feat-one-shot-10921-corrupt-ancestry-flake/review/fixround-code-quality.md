# FIX-ROUND report — code-quality-analyst — PR #10953

Base: `git diff 5403f5b30e..HEAD`. Scope: the six named fixes plus their blast radius.
Method: full diff read of every touched `.sh`/`.yml` file, `bash -n` on all six,
`shellcheck -S warning` on all five scripts (clean, exit 0), live replay of the census
regex over both swept dirs (zero hits — no self-match), live replay of the roster
extractor over both suites, and bash spot-checks of `10#$cost`, `[[:cntrl:]]`, and
`$'\u2028'` stripping.

## Verdict: SHIP

Every fix closes its finding. No new defect above P3.

## Per-fix verification

| Fix | Closes | Notes |
|---|---|---|
| Env-prefix force knob | P1-5 (leak) + P3-23 (SC2034) | `{ CORRUPT_WALK_PROBE_FORCE=skip corrupt_probe_forced_skip && corrupt_skip …; }` scopes the knob to the probe call only; `corrupt_skip` does not read the knob (lib:269-290), so the `&&`-arm needs no env. Shellcheck now clean — the two standalone-assignment SC2034s are gone. Both suites (bump ~2960, mint ~1182). |
| Octal-safe charge | P2-10 | `SKIPPED_ASSERTIONS + 10#$cost` (lib:283). Verified live: `08`→8, `09`→9, `5`→5. Guard `''\|*[!0-9]*` (lib:270) still rejects non-numerics before the arithmetic. |
| sed header-bound harvest | P2-13 | `sed -n '/^$/q; /^author /p; /^committer /p'` (lib:154) and `/^$/q; s/^committer //p` (lib:190) bound the scan to the commit header block; `-n` keeps the `q`-line unprinted. New empty-harvest FATAL in `corrupt_walk_break` mirrors `corrupt_dead_tag`'s tagger guard — a non-commit `cat-file` failure can no longer forge a headerless commit. `head -1` removal in dead_tag is correct (one committer per commit object). |
| Roster, all quoting forms | P2-7 | Extractor ERE decodes to `('[^']*'\|"[^"]*"\|\$[A-Za-z_{][^[:space:]#]*\|[A-Za-z0-9_.-]*\.[A-Za-z0-9_.-]*)`; replayed on both suites — bump yields g1b.B7/B7c/B7a/g2b.I6 (×2 each: real forced+environment call sites, not double-extraction) plus three selftest rows; mint yields fl.walk ×2 + selftest. Per-prefix non-selftest producer gates added in both suites; the dotted-token requirement correctly ignores prose mentions of `corrupt_skip`. `$var` operands extract and fail the prefix check deliberately (unauditable = unregistered). Suite-source lines do not self-match (`corrupt_skip[` has no literal whitespace after the name). |
| Census broadened | P2-15 + P3-24 | `\.git(/objects)?(/\|[^[:alnum:]_.-]\|$)` — `.git-hooks`/`.gitignore` correctly rejected (hyphen/alnum excluded), `.git/`, bare `.git`, `.git ` all match. Verb set now rm/unlink/mv/chmod/truncate + find -delete/-exec both orders + `git … prune`; `[^#]*` mid-line-`#` stop dropped, `-I` dropped, scope extended to `plugins/soleur/test/lib/`. Replayed: zero hits over both dirs. |
| Done-banner | P2-8 | run-all.sh:200 prints `=== <basename> done ===` for every class except `killed` (suite_exit_class run-all.sh:140-156 returns ok/killed/failed). Literal matches GUARD_UNITS `=== test-….sh done ===` (probe:199-200) byte-for-byte via `basename "$t"`. Killed-suite suppression is exactly the completion discriminator the finding required. |

Supporting fixes also verified closed: mint selftest verdict now lands on live counters (`fl_pass` flag, counters restored BEFORE the verdict — P1-1; floor comment re-derived 673→674 is internally consistent); `_corrupt_maybe_repack` rc fatal + propagated via `|| return` at all 5 forge call sites (P1-2, P1-4); sanitizer breadth C0+\x7f+U+2028/9 on BOTH row and reason (P1-3; `[[:cntrl:]]` and `\u2028` strips verified live); forced-arm reason label distinguishes captured exercises (P2-19); packed-arm CI leg added to `guard-script-fixture-tests` with env-prefix per suite (P2-6; "all sixteen" is accurate — 16 `test-*.sh` files exist); `--status completed` + `_pg_list_rc` distinguishes gh-failure vs empty-window (P2-17, P3-27); `g_observed` denominator (P2-9); I6 contract = rc∉{0,1} OR stderr non-empty, exactly as specced (P2-11); alert dedupe on stable `<!-- soleur-skip-persistence-monitor-alert -->` body marker + legacy-title transition loop (P2-12); probe header/close-criteria/exit-table rewritten for source 2 (P2-16, P2-14 workflow comment refreshed); `_obs_parts` derives keys under `set -u` (P2-18); `SKIP (loud):` literal pinned by new (q) check, floor raised 27→28 itemised (P2-21); plan scope-out line for #10956 added (P2-20); merge_group starvation documented (P3-25); banner-forgeability documented (P3-26); `CORRUPT_DEAD_NONCE` constant replaces triplicated literal (P3-22 — lib, both selftests).

## New defects introduced: none blocking

P3 residuals (all fail-safe or cosmetic — no silent-green path):

1. **`${rpfx%.}` label prints `g1b\`/`g2b\`** — test-bump ~3025: `_rpfx='g1b\.'`; `%.` strips the trailing `.` leaving the backslash → fail label reads `roster:g1b\-needs-live-producer`. Cosmetic, fail-path only.
2. **`git[[:space:]].*prune` over-broad** — also matches `git fetch --prune`, `git worktree prune`, `git remote prune` (ref/metadata prunes, not object deletion). Zero current hits; a future legit use trips the census — fail-safe but will confuse. Consider `gc[[:space:]].*--prune\|prune$`-style narrowing later.
3. **Probe (p) greps single-quoted producers only** while the in-suite roster accepts all four spellings — asymmetric (a `"g1b.x"` live producer passes its suite's roster, fails (p)). Fail-safe direction; note, don't fix.
4. **Line-continued `corrupt_skip \` call sites evade both rosters** (operand on next line). Same class as the documented third-suite residual; one comment clause would close it.
5. **`_pg_list_rc` only differentiates on zero ids** — a failed merge_group `gh run list` masked by successful pull_request ids proceeds silently. Bounded (mg bias is deliberate); comment already discloses the bias, not the masked-failure case.
6. **rc-124/timeout-killed suites earn the done-line** (class `failed`, not `killed`) — documented "already red" residual; harmless to hit-detection since markers in the log are still counted; only dilutes the TRANSIENT positive control.

No dead code found (`_pg_list_rc`, `g_observed`, `_log_observed`, `b7_ok`/`flw_ok`/`i6_ok`, `st_ms`, `fl_pass`, `ALERT_MARK`, `_obs_parts`, `CORRUPT_DEAD_NONCE` all consumed). Comments audited against the code they describe — all accurate. `st_moved`'s new `ds==0` term is safe: all 13 call sites are adjacent helper exercises before any corrupt row.
