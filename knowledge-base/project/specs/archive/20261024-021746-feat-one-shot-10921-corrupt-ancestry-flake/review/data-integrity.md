# Data Integrity Review — PR #10953 (feat-one-shot-10921-corrupt-ancestry-flake)

Seat: `soleur:engineering:review:data-integrity-guardian`
Scope: `git diff origin/main...HEAD` — test-fixture lib (`plugins/soleur/test/lib/git-corrupt-graph.sh`), two guard suites (bump, mint), skip-persistence probe + its test, monitor workflow, KB artifacts. No DB surface.
Lens: state integrity of `SKIPPED_ASSERTIONS` accounting (snapshot/restore, floor/ceiling), monitor streak-state artifact semantics (per-source observed accounting), forge ordering invariants.
CI ground truth used: `guard-script-fixture-tests` job 120703423589 — bump `Results: 696 pass, 0 fail, 0 skipped`; mint `Results: 673 pass, 0 fail, 0 skipped (673 assertions, floor 673)` — both green, `skipped=0` arm unexercised in CI.

## Verdict

**CHANGES REQUESTED** — two P1 defects in the counted-skip state accounting: (1) the mint selftest emits its verdict then restores the counters, so a machinery failure prints a FAIL line and exits 0; (2) all five forge-helper call sites discard the helper's exit status, so a forge failure reads as "contract absent" and is charged into `SKIPPED_ASSERTIONS` — a harness defect routed onto the skip rung, contradicting the settled "only walk-contract skip-eligible" ruling and the lib's own header contract.

---

## P0 — none

The happy-path accounting is internally consistent: declared costs match measured taken-branch assertion counts (B7=8 = 1 precondition + `assert_refused`(7); B7a=9 = `assert_excluded`(9: exit+result+target+off-main+3 pins+gh+branch); B7c=8; I6=3; fl.walk=3); `SKIP_CAP=28` and `SKIP_CAP=3` are the exact sums of the skip-eligible rows' declared costs; `MIN_ASSERTIONS` re-derivations match measured green-run totals (696/673, verified against the CI log).

## P1

### P1-1 — Mint selftest verdict is emitted then unwound: a machinery failure exits 0

`.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` ~L1170–1191:

```sh
fl_p0=$PASS fl_f0=$FAIL fl_s0=$SKIPPED_ASSERTIONS
# (a)/(b)/(c) helpers run inside { } > "$TMP/skip.stN" 2>&1 — their fail()
# calls still increment the REAL global FAIL counter.
fl_fd=$((FAIL - fl_f0)); fl_sd=$((SKIPPED_ASSERTIONS - fl_s0))
[[ "$fl_fd" == 2 && "$fl_sd" == 5 && ... ]] \
  && pass 'selftest:skip-machinery-both-directions' \
  || fail 'selftest:skip-machinery-both-directions' "..."
PASS=$fl_p0 FAIL=$fl_f0 SKIPPED_ASSERTIONS=$fl_s0
```

The snapshot/restore unwinds the (a)+(c) pollution — required — but it is placed **after** `pass`/`fail` emits the selftest's own verdict, so the verdict is erased too:

- On failure, `FAIL [selftest:skip-machinery-both-directions]` prints, `FAIL` goes `fl_f0 → fl_f0+1 → fl_f0`, and the suite tail `[[ "$FAIL" -eq 0 ]]` exits 0. A real regression in the counted-skip machinery (e.g. `corrupt_skip` ceasing to charge, an unwired `CORRUPT_WALK_PROBE_FORCE` value no longer flagged) is reported in the log and then silently absorbed — the un-run-instrument failure shape this PR exists to close, applied one level down to the guard itself. The suite's older selftest block (L437–468) reports structural failures via `st_die` → `exit 2` precisely so they red the run; this block bypasses that convention.
- On success, the emitted PASS contributes 0 to `TOTAL`. The `MIN_ASSERTIONS` comment (L93) claims the block adds "+1" — the arithmetic narrative (−1 precondition +1 selftest = net 0) is therefore wrong; measured TOTAL 673 reconciles only because the pre-PR real count was 674 (drift +9, not the stated +8). The floor happens to be right today; the narrative that produced it is not.

Asymmetry: the bump suite's counterpart rows (`selftest:forced-skip-emits-and-charges`, `selftest:skip-machinery-both-directions`, L2940–2969) DO land in the counters (+2, matching its floor comment) — identical machinery, opposite accounting outcome.

Fix shape: restore `PASS/FAIL/SKIPPED_ASSERTIONS` to the pre-block snapshot **before** the `&& pass || fail` emit (so the pollution from (a)–(c) is unwound but the verdict lands), or report failure via `st_die`-style `exit 2` per the suite's existing convention.

### P1-2 — Forge-helper exit status discarded: a harness defect is charged as a counted SKIP

All five forge call sites invoke the helpers bare:

- `test-bump-inngest-bootstrap-pin.sh` L1619 `corrupt_walk_break "$F_REPO" refs/heads/main` (B7), L1659 (B7c), L1683 `corrupt_dead_tag "$F_REPO" vinngest-v1.1.38` (B7a — incidentally covered, see below), L2656 `corrupt_walk_break "$H" refs/remotes/origin/main` (I6)
- `test-mint-inngest-bootstrap-tag.sh` `corrupt_walk_break "$F_REPO" refs/heads/main` (fl.walk)

`corrupt_walk_break`/`corrupt_dead_tag` return non-zero on `_corrupt_assert_repo` refusal (rc 2), `dead_oid`/`rev-parse`/`hash-object -w`/`update-ref` failure, or the post-forge `rev-parse` verify — printing `FATAL:` to stderr. The suites run `set -uo pipefail` with **no `set -e`**, so the rc is dropped and the row proceeds on a healthy graph. The construction-invariant rung then passes vacuously (`corrupt_invariant_dead_absent` checks the dead oid is absent — true whether or not the forge landed; B7's `invariant-tag-resolves` checks the side tag peels — seeded independently of the forge), and the walk-contract probe measures `[[ -z "$walk_err" ]]` → contract "absent" → `corrupt_skip` charges the declared cost.

Net effect: a forge failure produces a counted SKIP + green run instead of a fail-only harness-defect verdict. That contradicts:

- the lib header contract ("a dead oid that reads back … a ref the forge did not move … are a DIFFERENT rung: they are harness defects, fail loudly via fail(), charge NOTHING, and never route to corrupt_skip"),
- the settled CTO ruling ("only the walk-contract … is skip-eligible"),
- the plan's Guard-1 mutation row 2, which claims a wrong-ref forge lands RED via "the walk-contract probe or merged-set precondition" — the stderr-only probe shape cannot see a forge that never landed.

B7a is incidentally covered (`invariant-tag-listed` fails when `corrupt_dead_tag` never created the tag); B7, B7c, I6 and fl.walk have no "the forge actually moved the ref" invariant. A persistent forge failure would also mischarge the bounded skip budget the `SKIP_CAP` exists to bound, and report to the monitor as an environment decline rather than a harness break.

Fix shape: `corrupt_walk_break ... || { fail '<row>:invariant-forge-applied' "..."; }` at every call site (cheap, matches the `b7_ok` idiom), or a `corrupt_invariant_forge_moved <row> <repo> <ref> <pre-forge-tip>` helper. Same for `corrupt_dead_tag` despite the incidental coverage.

## P2

### P2-1 — The packed-store arm has no driver; `_corrupt_maybe_repack` ignores repack's rc

`SOLEUR_FIXTURE_PACKED` is referenced only inside `git-corrupt-graph.sh` (grep over `.github/`, `scripts/`, `plugins/soleur/test/` — zero consumers). AC4/tasks 5.2 prescribe "a permanent selftest arm" repacking between seed and forge; what shipped is the knob alone — no CI leg, no suite selftest, no scheduled run sets it. The original defect was a **packed-store** silent no-op; the regression coverage for that exact store layout is therefore verified, at best, by one-off local invocation and is not exercised anywhere this diff lands. Separately, `_corrupt_maybe_repack` runs `git -C "$1" repack -adq` without checking its exit — a failed repack silently degrades the packed arm back to a loose-store run with no signal.

### P2-2 — Source-2 "observed" keys on the suite START banner, not completion

The probe's per-unit discriminator is `=== test-<name>.sh ===` (printed by `run-all.sh` L176 **before** the suite runs). Source 1's discriminator is the rehearsal suite's terminal line — proof of completion. A guard suite killed/timed-out/crashed before its corrupt-walk rows still counts as `unit_obs += 1` with 0 hits, pooling into the unit's clean reading; source 1's equivalent would read TRANSIENT. The run reds anyway via `run-all.sh`'s `[KILLED]`/failed accounting, so the leak is bounded — but the positive-control semantic ("this suite could have emitted the marker") is weaker than intended. A per-suite terminal anchor (e.g. the `Results:` line) would restore parity.

## P3

- **Silent partial-source degradation**: in the probe's source 2, the two `gh run list` calls are concatenated before dedup — if the `merge_group` fetch fails while `pull_request` succeeds, the source samples PR legs only with no transient flag (contrast source 1, where a list failure is TRANSIENT). Both failing does degrade to TRANSIENT correctly.
- **`head -n $SAMPLE` shadows pull_request legs**: merge_group ids are emitted first, so ≥20 merge_group runs drop every PR leg. The comments call PR legs "density," so the preference order is intended; the shadowing is total, not proportional.
- **Pooled streak counter**: one `T5_PROBE_STATE` file across both sources — `_transient` fires once per run with merged reasons, which keeps the seal contract (+1 per TRANSIENT verdict) correct, but an intermittently blind source alternates transient/clean and never accumulates consecutive streaks → escalation never fires on a flapping instrument (accepted-residual shape, now spanning two sources).
- **Census pattern gaps**: `[^#]*` stops at `#`, so `rm # note .git/objects/…` evades; the literal `.git/objects/` also misses whole-`.git` deletions (`rm -rf "$dir/.git"`). Scope-limited standing check; noted for future hardening.
- **`skip.st3` captured but never asserted**: the mint selftest writes the bogus-knob flag's output to `$TMP/skip.st3` and only counts the FAIL delta — the message naming the knob is unverified (the bump equivalent asserts via `st_run` rc only as well; parity-level nit).
- **`corrupt_invariant_dead_absent` rc2 path**: on an empty `<repo>` operand the helper returns 2 having neither `fail()`-ed nor charged — the caller treats it like an invariant failure for gating, so a row contributes 0 counted assertions and only a stderr FATAL (floor would catch a systemic version). Defensive-only edge.

## Verified clean (lens checklist)

- `st_run` snapshots/restores `SKIPPED_ASSERTIONS` alongside PASS/FAIL (bump L2883–2885); mint's `st_*` mark+restore pair extended symmetrically (L440, L468). Selftest skip charges cannot leak into suite totals.
- Forced-skip selftests capture both stream pins into files (`SKIP (loud):` → stderr, `::warning::` → stdout) — no exercised marker reaches suite streams (selftest-poisoning guard holds).
- Floor/ceiling: `TOTAL` folds `SKIPPED_ASSERTIONS` in both suites; `SKIP_CAP` is the exact declared-cost sum; `Results:` lines append the skipped count.
- Forge ordering: every below-break object (side commits, seeded tags, origin pushes, repack) precedes the forge at all five sites; `seed_tag_at ... HEAD` post-forge is safe (tag creation needs only the object, per lib header). Repack placement inside helpers is pre-forge, matching the measured reflog-traversal constraint.
- `corrupt_skip` validates cost numerically before charging; reason sanitized `%`→`%25` then CR/LF-stripped (correct order — the `%25` introducer is not re-escaped; nothing is inserted after the strip).
- Probe: per-source/per-unit `observed ≥ 1` accounting is real — no pooling (test rows n/o verify TRANSIENT-on-unobserved and FAIL-dominates-TRANSIENT); FAIL clears the streak; a single `_transient` call per run keeps the monitor's seal contract (+1) intact; roster parity is checked in both directions (suite → prefix; probe → producer).
- Monitor workflow: probe contract 0/1/2 preserved; `verdict` non-numeric discriminator intact; alert title/body generalized without losing the per-source naming; streak artifact name unchanged (task 4.3).
- Census self-check returns zero hits against current tree (verified by running the same pattern); roster prefixes in both suites (`g1b.`/`g2b.`/`fl.`, incl. selftest names) match the probe's `GUARD_UNITS` enumeration.
- Settled rulings: forged-oid construction as ruled; probe extended in-PR; tier `aggregate pattern` holds — no SUT or workflow-gating file touched (AC10). The one ruling this review contradicts is flagged in P1-2 (walk-contract-only skip eligibility is not enforced where forge failures can produce a counted skip).
