# FIX-ROUND review — data-integrity-guardian — PR #10953

Scope: `git diff 5403f5b30e..HEAD` only (4 commits: a62f8a0e07, 807e3e78c6, 0df83e9ea5, 80bc9370f4). Report-only; no test gate run.

## Verdict: PASS — both P1s verified fixed; no new P1/P2 findings. Three P3 residuals.

## P1-1 — mint selftest verdict lands on live counters: VERIFIED

`.github/scripts/test/test-mint-inngest-bootstrap-tag.sh:1197-1207` — `fl_pass` is computed inside the snapshot window, `PASS=$fl_p0 FAIL=$fl_f0 SKIPPED_ASSERTIONS=$fl_s0` (line 1205) executes BEFORE the `pass/fail 'selftest:skip-machinery-both-directions'` verdict (1206-1207). The verdict now counts +1 on live counters; `MIN_ASSERTIONS` bumped 673→674 (line 99) with the +1/-1 derivation itemised. Expected deltas `fl_fd==2` (block a readable-dead-oid + block c unwired-force) and `fl_sd==5` are measured pre-restore; a shortfall yields `fl_pass=0` → a counted FAIL — fail-safe direction.

## P1-2 — all 5 forge call sites gate rc → harness FAIL: VERIFIED

Bump suite: `corrupt_walk_break` gated at 1624-25 (`b7_ok`), 1667-68 (`b7c_ok`), 2670-71 (`i6_ok`); `corrupt_dead_tag` at 1694-95 (`b7a_ok`). Mint suite: `corrupt_walk_break` at 1151-52 (`flw_ok`). Every site spells `|| { fail '<row>:invariant-forge-applied' "…a harness defect, never a skip"; <x>_ok=0; }` — fail-only, zero-counted, and the `_ok` gate keeps the row's skip/else branch unreachable after a forge failure. `_corrupt_maybe_repack` is now FATAL (`git-corrupt-graph.sh:127-132`) and both helpers propagate via `|| return` (144, 185). `corrupt_invariant_dead_absent` returns 2 on internal failure — call-site `||`/`&&` treats any non-zero uniformly, still fail-safe.

## Named checks

- **g_observed vs g_sampled** (`t5-skip-persistence-bound-7510.sh:311-365`): `g_sampled` counts fetched logs; `g_observed` counts logs with ≥1 unit discriminator (`_log_observed` set only inside the `grep -qF "$_disc"` gate). FAIL and PASS denominators use `g_observed` (350, 365), matching source 1's observed-over-sampled convention; per-unit `unit_obs<1` → TRANSIENT + `g_all_observed=0`; `any_fail` dominates `transient_reasons` at verdict (372-390). Correct.
- **unit_obs literal keys**: PASS line derives `_obs_parts` from GUARD_UNITS dynamically (360-363); no literal `unit_obs[bump]`/`unit_obs[mint]` under `set -u` (75). All keys initialised from the same array (277-280). Fixed.
- **done-banner vs killed/failed** (`run-all.sh:181-208`): done-line suppressed only for `killed` (signal-shaped rc ≤192 resolvable via `kill -l`); `failed`/`ok`/unrecognised classes still print it — a failed suite's log reads "observed", bounded because that run is already red (documented residual, 201-207). A killed suite yields no done-line → unit unobserved → TRANSIENT, never green. run-all exits non-zero on either class, so the packed-arm step is correctly skipped. Signal rc 193-255 classifies `failed` (no such signals on Linux) — corner noted, acceptable.
- **SKIPPED_ASSERTIONS snapshot/restore**: mint 1179-1205 restores all three counters before the verdict; the `corrupt_skip` charge (+5) lands because `{ }` groups run in the suite shell — captured, measured, rewound. Bump `_sk0` block (2960-2972) and `st_run`'s `sk0` restore (2903-2904) intact; bump's forced-skip verdict emits before `SKIPPED_ASSERTIONS=$_sk0` restore — the live-counter shape mint now mirrors. Env-prefix fix (`CORRUPT_WALK_PROBE_FORCE=skip corrupt_probe_forced_skip` at mint 1189, bump 2963) eliminates the `{ VAR=x; }` persistence that armed force-skip for all later rows — the real P1-adjacent leak is closed; `{ CORRUPT_WALK_PROBE_FORCE=present …; }` at mint 1194 is env-prefix on a subshell-context group too. `st_moved` now asserts `ds==0` (mint 440-444); no st_moved window surrounds 1178+ and restore leaves net ds=0 regardless.
- **Roster/census**: roster extracts all quoting forms incl. bare-word-with-dot and `$var` (bump 3029, mint 2034); non-`fl.`/`g1b.`/`g2b.` operands fail, and each prefix requires ≥1 non-selftest producer (mint 2042-2045, bump 3036-3043). Broadened census grep executed against current swept dirs: **0 hits** — no false-positive on existing content.
- **Forced-skip labelling**: all 5 sites emit "forced-divergence exercise (CORRUPT_WALK_PROBE_FORCE=skip)…" — the monitor still greps the `SKIP (loud): <pfx>` prefix, so a forced-marker leak still alerts (fail-safe), now self-describing.
- **Monitor dedupe** (`scheduled-rehearsal-skip-monitor.yml:268-297`): `<!-- soleur-skip-persistence-monitor-alert -->` written first into every `body_file` branch; marker `in:body` search precedes a legacy-title loop covering current + 3 historical titles; `gh` failure stays fatal. Old alerts never acquire the marker, so the legacy loop re-walks every run and comments on the found issue — same comment-on-existing semantics as before, no regression.
- **I6 contract**: `elif [[ "$i6_rc" == 0 || "$i6_rc" == 1 ]] && [[ -z "$i6_err" ]]` (2679-2681) — skip only when rc∈{0,1} AND stderr empty; the old `|| -z` shape over-skipped a fully exercisable row. Direction now matches the comment.
- **Packed-arm leg** (`pr-quality-guards.yml:101-111`): direct `bash` invocation emits no done-lines of its own, but the same job log carries run-all's — packed-leg `SKIP (loud):` markers are grepped from the whole log and correctly attributed as hits in an observed log. `bash -e` semantics: a packed bump failure skips packed mint — already red, acceptable.
- **`--status completed`**: samples all conclusions; cancelled/early-failed runs pad `g_sampled` without `g_observed` — fail-safe toward TRANSIENT, and failed runs that still print done-lines extend coverage (deliberate density).

## P3 residuals (non-blocking)

1. `t5-skip-persistence-bound-7510.sh:290-296` — `_pg_list_rc` is only surfaced when `pg_ids` is EMPTY. A one-sided `gh run list` failure (e.g. merge_group list fails, pull_request returns ids) silently shrinks the sample to one event class with no transient reason — silently inverting the documented mg-first bias for that run.
2. `t5-skip-persistence-bound-7510.test.sh:73-87,465-477` — no fed-log fixture exercises "start banner present, `done ===` absent" (the killed-suite shape). (n) covers zero-banner only, and since `BUMP_BANNER`/`MINT_BANNER` are derived from the probe's own literals, a discriminator revert to the start banner would move the fixture in lockstep and stay green.
3. `git-corrupt-graph.sh` `corrupt_skip` — the numeric cost guard admits `0`/`00`; a zero-cost loud skip would emit a marker while charging 0 to the floor. Pre-existing case shape (unchanged by this diff); all call sites use 3/5/8/9.

## Non-verifiable headlessly

- `MIN_ASSERTIONS=674` re-measurement and the probe test floor `28` — derivations are itemised in comments and internally consistent, but the counts were not re-executed (no full test gate per contract).
