# Code-Quality Review — PR #10953 (feat-one-shot-10921-corrupt-ancestry-flake)

Seat: `soleur:engineering:review:code-quality-analyst` · report-only · reviewed
`git diff origin/main...HEAD` (5403f5b30e) on worktree
`.worktrees/feat-one-shot-10921-corrupt-ancestry-flake`.

Lens: bash code smells, quoting/expansion hygiene, duplication vs the plan's
one-spelling mandate (#7849), dead code, comment accuracy
(`cq-cite-content-anchor-not-line-number`).

## Executive summary

- Findings: **P0: 0 · P1: 1 · P2: 6 · P3: 9**
- Overall quality: **8/10**. The diff is unusually well-commented, the charge
  arithmetic checks out against the counted-assertion helpers, and the
  chokepoint lib honours the one-spelling mandate for both the construction and
  the counted SKIP verdict. Findings are concentrated in three places: a leaked
  env knob in both selftest blocks (P1), latent holes in the new lib's own
  validation (`corrupt_skip` octal, `_corrupt_maybe_repack` rc), and
  stale/weak spots in the extended probe (header contract, banner-based
  positive control, single-quote-only roster grep).
- Top priorities: (1) scope `CORRUPT_WALK_PROBE_FORCE=skip` so it cannot leak
  past the selftest block; (2) harden `corrupt_skip`'s arithmetic
  (`10#$cost`) and `_corrupt_maybe_repack`'s ignored rc — both are the same
  silent-environment-degradation class this PR exists to kill; (3) align the
  probe's source-2 positive control and header contract with what the code
  actually does.

Settled rulings (CTO 2026-10-23) were checked, not re-litigated: forged-oid
over repack-aware `rm` ✓ implemented; only walk-contract probes are
skip-eligible ✓ (B7a peel failure correctly classified construction-invariant);
probe extended in this PR ✓; `aggregate pattern` tier consistent with a
test/monitor-only diff (SUT scripts untouched — verified by diff scope).

## Detailed findings

### P1 — should fix before merge

**P1-1. `CORRUPT_WALK_PROBE_FORCE=skip` leaks globally after the selftest
block** (latent coverage poisoner)
`test-bump-inngest-bootstrap-pin.sh:2941`, `test-mint-inngest-bootstrap-tag.sh:1178`

Both suites write:

```bash
{ CORRUPT_WALK_PROBE_FORCE=skip
  corrupt_probe_forced_skip && corrupt_skip '...selftest-forced-skip' 5 '...'
} > "$LAST_OUT" 2>&1
```

`CORRUPT_WALK_PROBE_FORCE=skip` on its own line inside `{ }` is a **standalone
assignment**, not a command prefix — it persists in the suite's shell after the
block (verified: `{ Y=7; }` then `echo $Y` → `7`; by contrast `VAR=x funcname`
prefix assignments on shell functions are correctly temporary — the
`_st_force_bogus` wrapper is fine). Nothing calls `corrupt_probe_forced_skip`
downstream today, so it is inert — but the selftest now leaves the force knob
armed for the rest of the process. A corrupt-walk row added *below* the
selftest, or a future refactor that reorders, silently force-skips on every
runner: the row reports an environment decline that does not exist, charges
into TOTAL, and stays green — the exact silent-environment-gate deletion the
knob's own comment warns about. Fix: wrap in a subshell `( ... )` or add
`unset CORRUPT_WALK_PROBE_FORCE` immediately after the block (subsidiary
check: mint's `(c)` uses the prefix form `CORRUPT_WALK_PROBE_FORCE=present
corrupt_probe_forced_skip`, which is safe — the inconsistency of styles makes
the leak easier to miss).

### P2 — medium-severity defects / debt

**P2-1. `corrupt_skip` charge is octal-unsafe; a leading-zero cost emits
markers without charging**
`plugins/soleur/test/lib/git-corrupt-graph.sh:225-240`

`case "$cost" in ''|*[!0-9]*)` admits `08`/`09`, then
`SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + cost))` hits bash's
"value too great for base" arithmetic error (verified: `$((x + 08))` → error,
assignment fails, execution continues). With no `set -e` in the suites the
function then emits `SKIP (loud):` + `::warning::` anyway — a skip that is
visible to the monitor but never charged, under-counting the floor AND evading
`SKIP_CAP`. This is verbatim the bug class the probe file documents at
`t5-skip-persistence-bound-7510.sh`'s base-10 paragraph (`10#$streak`,
measured fail-open). Fix: `SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + 10#$cost))`.
All current call sites pass plain digits, so latent — but the guard exists
precisely for the call that isn't.

**P2-2. `_corrupt_maybe_repack` rc is ignored by every caller — the packed
arm silently degrades to loose**
`plugins/soleur/test/lib/git-corrupt-graph.sh:102-106`; callers at 120, 151

`_corrupt_maybe_repack "$repo"` is invoked as a bare statement under
`SOLEUR_FIXTURE_PACKED=1`; its return status (repack's) is never checked and
the suites run without `set -e`. A failed `git repack -adq` (disk pressure, a
mid-run `gc` race) leaves the store loose and the forge proceeds — the
"packed-store arm" then reports green for a layout it never exercised. That is
the Arm-B flake's own shape one layer up. Fix: make it fatal on failure
(`git -C "$1" repack -adq || { printf 'FATAL ...' >&2; return 1; }`) and let
the caller's `|| return` propagate, which every caller already has on the
forge path.

**P2-3. Source-2 positive control keys on the suite *banner*, which prints
before the suite runs — weaker than source 1's terminal-line discriminator**
`scripts/followthroughs/t5-skip-persistence-bound-7510.sh:176-181, 278-288`;
`run-all.sh` prints `=== test-<name>.sh ===` at run-all.sh's per-suite loop
*before* `bash "$t"`.

`unit_obs[unit]++` fires on banner presence alone. If the bump suite is killed
or crashes mid-run (the guard suites have a measured crash/OOM history — that
is why this file's own suite exists), `run-all.sh` continues to the next suite,
*both* banners still appear in the log, `unit_obs` ≥ 1, hits 0 → the source
reads observed-clean → PASS over skip rows that never executed. Source 1
deliberately uses `SUITE_TERMINAL` — a line only printed on suite completion —
exactly because observed must mean "the arms ran", not "the suite started".
The comment at 173-176 acknowledges per-suite discriminators but picks the
weaker signal. The crash itself is loud in the job, so this is a strength gap
rather than a silent hole — but the positive control is the core mechanism of
this probe and it now certifies less than it claims. Fix direction: a
completion discriminator (e.g. the suite's `Results:` trailer text within the
log section after that banner), or at minimum a comment admitting the
banner-only bound.

**P2-4. Roster-parity self-check greps only single-quoted call sites — the
enforcement fails open on a differently-spelled producer**
`test-bump-inngest-bootstrap-pin.sh:~2973`, `test-mint-inngest-bootstrap-tag.sh:~2009`

`grep -oE "corrupt_skip[[:space:]]+'[^']+'"` extracts names only when the first
argument is single-quoted. A `corrupt_skip "zzz.x" 3 ...` (double quotes) or
`corrupt_skip $row ...` produces no match — `_roster_bad` stays empty and the
check reports green while the producer's name is outside the monitor's
enumerated prefixes. The check exists to catch exactly that case. Fix
direction: normalize before extracting (`grep -oE 'corrupt_skip[[:space:]]+["'"'"']?[^"'"'"' ]+'` then strip quotes), or a second pattern for the
double-quoted form. Related: the same `|| true` tail means an unreadable `$0`
also reads as clean — acceptable given suites always run as files, worth a
comment.

**P2-5. Probe header contract is stale after this PR**
`scripts/followthroughs/t5-skip-persistence-bound-7510.sh:9-16, 19-21, 41-48`

- Line 9: "It reads the ONE signal that already exists — the suite's own loud
  SKIP line in post-merge `infra-validation.yml` logs" — now two signals
  across two workflows and two sampling modes.
- Lines 19-21: `1 = FAIL ... "(>= 1 skip observed; the deferred pre-bake /
  S1 extension is now owed)"` — a guard-suite hit owes a different remediation
  (runner image or rows, per the file's own tail text), which the exit-code
  table does not reflect.
- Lines 41-48 "Close criteria": enumerates only the infra-validation sampling;
  the by-event second source is absent from the contract a reader diffs the
  code against.

The inline `SECOND RUN-SOURCE` block (161+) is excellent — the top-of-file
contract just wasn't brought with it. `cq-cite` note: the anchors themselves
(issue/ADR/row names) are compliant; this is *completeness* drift, the failure
mode the file's own stale-claim forensics exists to catch.

**P2-6. `corrupt_walk_break` can forge a malformed commit when `<ref>` isn't a
commit**
`plugins/soleur/test/lib/git-corrupt-graph.sh:127-133`

`rev-parse "${ref}^{tree}"` peels annotated tags (so a tag ref passes the
guard), but `cat-file commit "$ref"` then fails → `$headers` empty → the forged
commit is written with **no author/committer lines** and only `|| return` on
the *outer* `hash-object` call catches nothing (the pipeline's failure is
sed's, and `hash-object -w` doesn't validate). Callers pass branch/remote refs
so unreachable today, but the helper is a lib chokepoint — add
`[[ -n "$headers" ]] || FATAL` after the extraction (one line, mirrors the
`tagger` non-empty guard already in `corrupt_dead_tag` at 155).

### P3 — nits, latent fragility, style

1. **`corrupt_invariant_dead_absent` is vacuous-by-construction if `dead_oid`
   ever gains per-call uniqueness.** The invariant re-derives the dead sha via
   the same constant nonce; the check verifies "the *forged* parent is absent"
   only because both calls produce identical bytes. The header documents
   "CONSTANT on purpose" but nothing enforces the coupling — a plausible
   "improvement" to uniqueness silently turns the invariant into an
   always-true check on the wrong oid. Passing `<dead>` as an operand, or the
   forges exposing it, removes the assumption. (`git-corrupt-graph.sh:94-97,
   180-190`)

2. **Inconsistent `fail` guarding.** `corrupt_skip` guards `declare -F fail`
   with a printf fallback (228-233); `corrupt_probe_forced_skip` (204) and
   `corrupt_invariant_dead_absent` (185) call `fail` unconditionally. The
   caller contract requires `fail`, so both are fine — pick one posture.

3. **Census regex has a dead alternation and comment-line false positives.**
   `rm -rf[^#]*` is subsumed by `(rm|unlink)[[:space:]][^#]*` (the space after
   `rm` already matches); and `[^#]*` doesn't prevent matching
   *comment-leading* lines — `# rm -f .git/objects/x` still trips it
   (fail-safe direction, arguably deliberate, but undocumented either way).
   (`test-bump-inngest-bootstrap-pin.sh` census block)

4. **`${unit_obs[bump]}`/`${unit_obs[mint]}` hardcode unit names under
   `set -u`.** Renaming a `GUARD_UNITS` entry makes the PASS line die on an
   unbound subscript → rc 1 → reads as a FAIL verdict with a confusing log.
   Derive the names in the print loop. (`t5-skip-persistence-bound-7510.sh:310`)

5. **Source-2 `gh run list` rc unchecked — asymmetric with source 1.**
   `pg_ids` swallows `2>/dev/null` failures: a one-event API failure degrades
   sample density silently (empty overall still → TRANSIENT ✓). Source 1
   wraps the same call in `if ! runs=...`. (`:259-264`)

6. **`grep -oF ... | head -1` in the probe's own test file** — the
   SIGPIPE/pipefail shape the file's header exists to document. Benign today
   (single match, small file, no `set -e`) but self-undermining as an example;
   use `sed -n '1p'` or `awk 'NR==1{print;exit}'` on the grep output... or
   `grep -oF -m1` on GNU. (`t5-skip-persistence-bound-7510.test.sh` banner
   derivation)

7. **Roster-parity check duplicated across both suites** — same ~8-line
   grep/sed/grep-v pipeline, differing only in the prefix regex; the prefix
   set now lives in three places (`GUARD_UNITS`, bump `^(g1b\.|g2b\.)`, mint
   `^fl\.`). The plan's one-spelling mandate covers construction + verdict —
   this adjacent machinery is the next drift candidate; a lib helper taking a
   prefix list would collapse two of the three spellings.

8. **`head -1` on `sed -n 's/^committer //p'`** — a commit object has exactly
   one committer line; the `| head -1` is dead pipe (and under pipefail a
   SIGPIPE shape, benign here). (`git-corrupt-graph.sh:154`)

9. **`st_moved` doesn't ledger `SKIPPED_ASSERTIONS`.** The mint snapshot adds
   `st_s0`/restore but `st_moved` only measures PASS/FAIL drift — a helper
   under test that wrongly charged the counter would pass the battery
   unnoticed (the end-of-block restore hides it). (`test-mint-…:437-468`)

## Verified-clean checks (no findings)

- **Charge arithmetic**: `assert_refused` emits 7 counted assertions → row
  costs B7/B7c = 1 precondition + 7 = 8 ✓; `assert_excluded` = 9 (incl.
  `assert_all_pins`' 3) → B7a = 9 ✓; I6 = 3, fl.walk = 3 ✓. `SKIP_CAP` 28/3
  matches; ceiling fails *closed* on un-bumped cost raises. `MIN_ASSERTIONS`
  deltas reconcile (−5/+2 → 696; mint 673 re-derivation documented).
- **Quoting/expansion**: all new expansions quoted; `2>&1 >/dev/null` stream
  pins correct in all four probes; `${reason//'%'/'%25'}` + CR/LF strip order
  verified (`a%b\nc\rd` → `a%25bcd`); `IFS='|'/'；'` `read` splits safe
  (banners/markers contain no delimiters).
- **Ordering**: forge-last discipline held everywhere — B7 tags the side
  commit pre-forge; B7c/mint tag the forged tip *after* (tag-object write,
  no walk — safe per the header rule); I6 forges `refs/remotes/origin/main`
  with HEAD detached at the side sha; `side_commit` returns HEAD to main so
  `--merged HEAD` traverses the forged tip.
- **Census**: the standing grep finds zero hits in `.github/scripts/test/`;
  the two outside-dir sites named in the header (`scripts/ci-pr-selection.
  test.sh:432`, `apps/web-platform/infra/workspaces-luks-loopback.test.sh:868`)
  are exactly the pair #10956 tracks — comment accurate.
- **Marker reachability**: `run-all.sh` runs suites with inherited stdio, so
  `SKIP (loud):` (stderr) and `=== *.sh ===` banners (stdout) reach the job
  log the probe greps; the `gh` stub's arg parsing (`--workflow` via prev-arg,
  positional id via `[0-9]*`) is sound, and identical ids across the two
  `--event` lists exercise the dedupe for free.
- **Settled-ruling conformity**: forge-over-`rm`, walk-contract-only
  skip-eligibility (B7a peel failure correctly routed to construction-
  invariant FAIL, never `corrupt_skip`), probe extended not duplicated,
  aggregate-pattern tier consistent with a fixtures/monitor-only diff.
- **Conventions**: source-guard idiom byte-matches `git-fixture-env.sh`;
  shellcheck on the lib is clean except one SC2317-info on the standard
  guard line (same idiom, ignorable); comment anchors use issue/ADR/row
  identifiers, no line-number citations (`cq-cite` ✓); `Results:`/`TOTAL`
  plumbing consistent across both suites.

## Notes outside this seat's scope

- `SOLEUR_FIXTURE_PACKED` has no in-tree consumer (tasks.md 5.2 marks the AC4
  arm as a verification step, not a suite row) — correct per tasking, but the
  packed arm is reachable only by manual env invocation; no CI matrix leg
  pins it.
- Workflow filename/`STREAK_ARTIFACT_NAME`/`name:` retain "rehearsal" —
  deliberate per tasks.md ("keep streak artifact name"); the in-file scope
  comment at the top compensates.
- Workflow header still says "`gh run view --log` over 20 multi-MB logs" —
  source 2 doubles the fetch ceiling (~40).
- Draft-PR placeholder body: not raised, per the seat's sharp-edge rule —
  `soleur:ship` Phase 1 owns `Closes #N` population post-review.
