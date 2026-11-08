---
date: 2026-11-08
category: workflow-patterns
---
# Parallelizing a serial gate changes its resource BOUND, not just its speed — recount the preflight model and re-sweep the dependency guard

Restructuring `scripts/followthroughs/pr-battery-gate-saving-9323.sh` (#12360) from four serial read
phases to a bounded `&`-worker pool kept the verdict path bit-identical — the parent replays per-unit
result files in candidate order — but silently moved three surfaces the serial version's own guards
modeled. Review (sequential-fallback panel) caught all four as P3s; none were in the test plan
because each is a property of the *budget model*, not the verdict.

**1. Prefetching widens the worst-case the quota floor was computed on.** Serial artifact reads were
bounded by `ART_READ_CAP` (260): a run past the cap was `evidence_absent` *without its listing ever
being fetched*. The parallel Stage-A wave lists ALL qualifying runs unconditionally — the cap is
replayed on a virtual counter after the fact — so the true worst case is `CAP + ≤MAX_RUNS` extra
listing reads. `need_min` under-counted by up to 40 (~4% of the 1026 floor). The fix was one operand
(`+ MAX_RUNS`) plus a comment naming the prefetch. **Check:** whenever a restructure makes a fetch
unconditional where the serial version gated it, re-derive every resource bound that was computed
from the serial call graph — the invariant the bound encoded ("serial never fetched it") no longer
holds.

**2. `^[0-9]+$` acceptance is not arithmetic safety.** `PBG_JOBS` was validated with the same
integer regex shape as `PBG_BUDGET_S` — but `PBG_BUDGET_S` uses `^[1-9][0-9]*$` (leading zeros
refused) while `PBG_JOBS` accepted `^[0-9]+$`. `PBG_JOBS=08` passed validation, then every `(( ))`
comparison hit the octal trap ("value too great for base"), silently degrading to the serial path
with stderr noise. Fix: `JOBS=$((10#$JOBS))` after the regex — accept-then-normalize. Two test rows
now pin `08` → width 8 with no `serial fallback` banner and no octal error. **Check:** for every
integer env knob, ask which of the two existing shapes it should mirror — refuse-leading-zeros or
`10#`-normalize — and add the malformed-but-accepted input (`08`, `09`, `000`) to the validation
rows, not just the non-integer one.

**3. A restructure imports new commands the dependency guard never vetted.** The probe's
`for need in gh jq unzip …` refusal list predated the parallel code; the pool brought `seq`
(page tail wave), `head` (row-kind read), `xargs` (per-run tsv cat) and `mv` (atomic row write).
All are coreutils and present on every runner, but the guard exists so a missing dep is CANNOT
ESTABLISH, never a mid-sweep surprise. **Check:** after any restructure, `comm -23 <(grep -oE
for each command word used) <(the need list)` — or at minimum grep the new code for commands absent
from the guard. The same sweep applies to shellcheck's unused-variable warnings on new locals.

**What held up:** the serial-exact replay discipline — workers write per-unit row FILES under
`$WORK`, the parent consumes rows in the serial order and replays the cap on a virtual counter —
made every one of these divergences *quota-only*, never verdict-relevant. The tests that mattered
most were the equivalence rows (forced-serial `PBG_JOBS=1` aggregates identically to the pool) and
the worker-killed-mid-unit row (missing result file → CANNOT ESTABLISH, never a skipped unit). Also
verified empirically: `( fn ) &` subshell workers do **not** run the parent's `EXIT` trap — the
`rm -rf $WORK` cleanup is safe beside the pool.

## Session Errors

1. Called `fix-round-seats.sh --files` with a space-separated file list (the script splits on
   newline/comma only); it mis-resolved to two seats instead of four. **Prevention:** the usage
   header documents the input shape — read the helper's `--help`/header before composing an
   invocation, especially for comma-vs-space conventions.
2. Invoked `prepush-secret-scan.sh` at `$PLUGIN_ROOT/scripts/` — it lives under
   `$PLUGIN_ROOT/skills/ship/scripts/`; the bare-path error was masked by `| tail` (rc 0).
   **Prevention:** when a `${CLAUDE_PLUGIN_ROOT}`-relative path 404s, `find` the plugin root for the
   basename before concluding anything; never let `| tail` stand in for an exit code.
3. Left a stray duplicate probe-invocation line in the test-file edit and removed it in a follow-up
   edit before commit. **Prevention:** `git diff` the hunk immediately after an `edit` lands, not
   just before commit.
4. `python3` heredoc `re.sub` misuse (lambda passed as the string argument) → TypeError; re-did the
   checkbox tick with `sed`. **Prevention:** for a two-pattern line edit, `sed -i` is the cheaper
   tool than a heredoc script.
