# Test Design Review — PR #10953 (#10921 corrupt-ancestry flake)

**Seat:** `soleur:engineering:review:test-design-reviewer` · report-only · diff `origin/main...HEAD`
**Scope reviewed:** `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`, `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`, `scripts/followthroughs/t5-skip-persistence-bound-7510.{sh,test.sh}`, new lib `plugins/soleur/test/lib/git-corrupt-graph.sh`, `.github/workflows/scheduled-rehearsal-skip-monitor.yml`.

## Verdict

**PASS** — exemplary determinism engineering. Five copies of a measured-flaky `rm -f .git/objects/<fanout>` construction are collapsed into ONE forge-the-never-written-object chokepoint, each corrupt-walk row gains an environment gate with a counted, capped, monitor-visible SKIP rung, and both the suites and the standing probe carry self-checks against regression of every part of the machinery (construction invariant, charge convention, stream capture, census, roster parity both directions).

**Test Quality Score: 8.8 / 10 (Grade: B — top of band)**

| Property | Score | Notes |
|----------|-------|-------|
| Understandable | 9/10 | The lib header (`git-corrupt-graph.sh:1-64`) is a model root-cause + contract doc; per-row comments explain branch order and which contract each probe mirrors. Dense census regex is the only read-cost. |
| Maintainable | 8/10 | One-spelling chokepoint kills five divergent copies; census + roster parity guard drift in both directions. Deductions: header-harvest sed scans the whole commit incl. message body (P2-2); census is spelling-based, bypassable via indirection/gc (P2-3); roster parity satisfied by captured selftest producers (P2-4). |
| Repeatable | 10/10 | The PR's entire purpose. `dead_oid` absence is a construction invariant, not a race (constant nonce, `hash-object --stdin` without `-w`, lib:94-97); packed-store arm (`SOLEUR_FIXTURE_PACKED`, lib:102-106) and forced-divergence arm (`CORRUPT_WALK_PROBE_FORCE=skip`, lib:200-208) cover both layouts and both verdict paths deterministically. `$RANDOM` in `run_probe` is filename-only, never asserted. |
| Atomic | 9/10 | Invariants are fail-only/zero-counted — cleanly separated rung from the skip rung; each row = one contract probe + one verdict. |
| Necessary | 10/10 | Fixes a measured CI flake: `rm -f` no-oped on packed stores → five broken-fixture FAILs on a REQUIRED check. Census prevents re-introduction. |
| Granular | 9/10 | Named row-ids, captured output embedded in failure text (mint selftest `skip.st2` paste), per-source and per-unit verdict lines in the probe, itemised floor arithmetic. |
| Fast | 8/10 | Real git ops on tmp repos — sub-second per forge. t5 `mkcase` now writes 2×6000-line pads per case (pre-existing pattern, bounded, declared `*.test.sh` exception). |
| First (TDD) | 7/10 | Fixture lib, suite rewrites, and self-checks landed together; cannot confirm tests-before-implementation ordering, and the artifact under test IS the test machinery. |

## Findings

### P0 — none

Verified directly: zero residual `.git/objects/` deletion sites inside `.github/scripts/test/` (the census would pass today); selftest `SKIP (loud):`/`::warning::` lines are captured to files, not suite streams (no monitor self-poisoning); `SKIPPED_ASSERTIONS` is folded into `TOTAL` at both suite tails with itemised floor math (696/673) and bounded by `SKIP_CAP` (28 bump / 3 mint).

### P1 — none

### P2

1. **I6 probe gate is stricter than the SUT it mirrors** — `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh:2660-2662`. The shipped step (`build-inngest-bootstrap-image.yml:212-219`) discards stderr (`2>/dev/null`) and keys `*)` → "could not decide" on rc outside `{0,1}` ALONE. The probe additionally requires non-empty stderr: a runner git that exits ≥2 silently would skip a row that is fully exercisable and would PASS. This contradicts the "probe contract is the SUT's own acceptance" principle the B7 rows correctly implement (the bump/mint scripts DO key on `walk_err` text — `bump-inngest-bootstrap-pin.sh:292-294`, `mint-inngest-bootstrap-tag.sh:303-305`). Fix: gate I6 on `rc ∉ {0,1}` only, or document why stderr is load-bearing here.
2. **Header harvest in `corrupt_walk_break` over-matches into the commit message** — `plugins/soleur/test/lib/git-corrupt-graph.sh:127`. `sed -n '/^author /p;/^committer /p'` scans the whole `cat-file commit` output; an `author `/`committer ` line in the seeded commit's MESSAGE is copied as a duplicate header → malformed forged commit (loud failure, not silent, but a spurious harness defect on an unrelated edit). `corrupt_dead_tag` (lib:154) is saved by `head -1`. Fix: bound to the header block, e.g. `sed -n '1,/^$/p' | grep -E '^(author|committer) '`.
3. **Census is spelling-based** — bump:2978-2982. Covers `rm|unlink <path>` and `find -delete` literals but not `git gc --prune=now`/`git prune`/`git repack`-with-deletion or `rm "$OBJ"` indirection — the same latent defect could re-enter in a spelling the regex can't see. Acceptable as a first-line guard (the two known external sites are deferred to #10956 and disclosed at lib:23); worth a comment acknowledging the bypass class.
4. **Roster parity can be satisfied by captured selftest producers** — bump:2987-2992, mint:2009-2014, t5.test.sh:498-505. `corrupt_skip 'g1b.selftest-*'`/`'fl.selftest-*'` emit only into captured files (never the monitor's view), yet they satisfy both the suite-side prefix check and probe row (p)'s prefix→producer grep. If every real corrupt-walk row were deleted while selftests remained, parity stays green while the prefix has no observable producer. Fix: require ≥1 producer whose name does NOT match `*.selftest-*`, or scope the probe-side check to non-selftest call sites.
5. **Monitor now files on pull_request legs** — probe (`t5-…sh` source-2 block). Any PR that emits a guard-suite `SKIP (loud): g1b./g2b./fl.` marker (e.g., one exercising skip arms, or a fork PR) trips the standing FAIL alert against main's health. Disclosed as intentional ("real evidence, labelled by source") — flagging the false-positive channel so it is a conscious acceptance, not a surprise; also `head -n 20` over the merge_group-first union can starve pull_request ids when the union exceeds the sample window.

## Top 3 Recommendations

1. **Necessary/Granular** — `test-bump-inngest-bootstrap-pin.sh:2660`: drop the `-z "$i6_err"` disjunct (or document it) so the I6 gate matches the workflow's rc-only acceptance. Expected +0 on score; removes an over-skip edge the monitor would otherwise have to explain.
2. **Maintainable** — `git-corrupt-graph.sh:127`: bound the author/committer harvest to the header block. Small fix, removes a latent whole-fixture failure mode. M 8→9.
3. **Necessary (of the guard)** — roster parity at bump:2987 / mint:2009 / t5.test.sh:498: exclude `*.selftest-*` names so parity cannot be held green by captured-only producers. M 8→9, N margin.

## Patterns Observed

**Worth keeping:**
- *Probe-parity discipline*: each skip gate mirrors the SUT's own acceptance signal (walk_err text for bump/mint; rc-class for I6 — see P2-1 for the one place it drifted), not a hand-picked proxy.
- *Captured-marker hygiene*: every exercised `SKIP (loud):`/`::warning::` is redirected to a file before grep — the selftest cannot poison the standing monitor.
- *Derived fixtures*: `BUMP_BANNER`/`MINT_BANNER` are extracted from the probe's own literals (t5.test.sh:74-77), so a discriminator edit moves the fixture instead of silently desynchronising it; absence exits 2 (broken instrument), never a green vacuity.
- *Two-directional registration*: suites check producer→prefix, probe test checks prefix→producer; the gap each leaves is different (P2-4).
- *Itemised floor accounting*: every MIN_ASSERTIONS/_FLOOR change carries the arithmetic and the green-run measurement in the comment.
- *Fail-only invariants*: construction guarantees are a distinct rung — zero counted, can never route to the skip — matching the settled "only walk-contract skip-eligible" ruling.

**Anti-patterns to watch:** pattern-matched census guards read as stronger than they are (P2-3); selftest fixtures that share the production emission path can satisfy registration checks vacuously (P2-4).

**Settled rulings (CTO 2026-10-23) — all honoured:** forged-oid over repack-aware `rm` ✓ (all five sites rewritten, zero residual); only walk-contract skip-eligible ✓ (invariants fail-only, zero-charged); probe extended in this PR ✓ (GUARD_UNITS source-2, per-suite discriminators, per-source accounting, FAIL-dominates verdict); tier-aggregate floor+ceiling pattern ✓ (TOTAL folds SKIPPED_ASSERTIONS, SKIP_CAP itemised).

## Mutation/self-check battery audit

The diff ships no independent mutation battery; its self-checks ARE the instrument rows. Spot-audited against the battery axes: the negative rows are non-vacuous — mint/bump selftests write the nonce blob for real (readable dead oid → invariant FAIL, exact FAIL-delta pinned at 2/1 via `st_run`/`fl_fd`); the bogus-force row drives `CORRUPT_WALK_PROBE_FORCE=present` through a wrapper because `env` cannot invoke a function; the captured-output assertions count exact marker lines (1 SKIP + 1 `::warning::`) and exact charge delta (5), not just exit codes; t5 rows (l)-(o) pin exit codes AND the reason embedded in `expect` failure text distinguishes FAIL-dominate from TRANSIENT-escalate (per-case streak files make escalation unreachable in one run). The (p) roster row is the one row whose refusal arm could stay green for a wrong reason (P2-4).

### Pyramid

PR body fetched via `gh pr view 10953 --json body`: draft placeholder only ("Draft PR created automatically…") — no `## Test Pyramid` block. Not needed: no e2e-layer tests added.

| File | Layer | Signals | Verdict | Confidence |
|------|-------|---------|---------|------------|
| `plugins/soleur/test/lib/git-corrupt-graph.sh` | n/a (fixture lib, no test cases; sourced by unit suites) | bash helpers only | PASS — out of scope (helper/fixture, not a test file) | high |
| `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` | unit | `test-*.sh` path signal; vitest/pytest absent; real git subprocesses — declared `*.test.sh` exception | PASS (modified unit suite; no layer change, no new cost signals beyond existing subprocess pattern) | high |
| `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` | unit | same as above | PASS | high |
| `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` | unit | `*.test.sh` path signal; stubbed `gh` binary (no server/port/network); deterministic awk-generated pads | PASS (modified, not new — weight-row WARN is new-suite only; also exempt: `.github/scripts/test/` aggregate-priced family pattern applies to this followthrough suite's registered label) | high |
| `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` | n/a (probe under test, not a test file) | — | PASS — out of scope | high |
| `.github/workflows/scheduled-rehearsal-skip-monitor.yml` | n/a (workflow text changes only) | — | PASS — out of scope | high |

No e2e-layer additions → no FAIL. No WARN: no fixed sleeps/network in new test code; `gh` fully stubbed in the probe test; the `pull_request`-leg sampling concern is behavioural, not a cost signal (recorded as P2-5).
