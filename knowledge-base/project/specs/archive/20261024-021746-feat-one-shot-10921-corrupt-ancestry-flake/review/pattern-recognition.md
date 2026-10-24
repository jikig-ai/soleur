# Pattern Recognition Review — PR #10953 (closes #10921)

Reviewer: `soleur:engineering:review:pattern-recognition-specialist`
Scope: `git diff origin/main...HEAD` on `feat-one-shot-10921-corrupt-ancestry-flake`
Diff shape: new shared lib `plugins/soleur/test/lib/git-corrupt-graph.sh` (+241);
two guard-script suites rewired (bump +257, mint +103); counted-skip machinery
(`corrupt_skip`, `SKIPPED_ASSERTIONS`, floor+ceiling); census + roster-parity
self-checks; t5 probe gains a second run-source (`pr-quality-guards.yml` by event)
with per-suite discriminators and per-source observed accounting; monitor alert
text generalized; plan/spec bookkeeping.

## Verdict: PASS — no P0, no P1. P2 findings are consolidation/doc-fidelity notes, none blocking.

## Empirical verification performed (affected suites only)

| Command | Result |
|---|---|
| `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` | 696 pass, 0 fail, 0 skipped — equals floor 696 exactly |
| `SOLEUR_FIXTURE_PACKED=1` (same) | identical 696/0/0 — packed arm works when invoked |
| `CORRUPT_WALK_PROBE_FORCE=skip` (same) | 668 pass + 28 skipped (= SKIP_CAP exactly: 8+9+8+3); 4 `SKIP (loud):` + 4 `::warning::` lines |
| `bash .github/scripts/test/test-mint-inngest-bootstrap-tag.sh` | 673 pass, 0 fail, 0 skipped — equals floor 673 |
| `SOLEUR_FIXTURE_PACKED=1` (mint) | identical 673 |
| `CORRUPT_WALK_PROBE_FORCE=skip` (mint) | 670 pass + 3 skipped (= cap 3) |
| `bash scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` | 27 passed, 0 failed (floor 27) |
| `bash -n` on all 5 touched shell files | clean |
| `shellcheck -x` | lib: SC2317 info only (source-guard `return||exit` idiom — false positive); suites: 1 SC2034 warning each (see P3-8) |
| `python3 yaml.safe_load` on monitor workflow | parses |

Skip-cost math verified by hand against helper assertion counts:
`assert_refused` = 7 asserts → B7/B7c rows = 1 precondition + 7 = **8**;
`assert_excluded` = 9 (`assert_all_pins` = 3) → B7a = **9**; I6 =
`step_rc`+`step_has`+grep-row = **3**; `fl.walk` = `a_eq`+`a_eq`+`a_out_has` =
**3**. Caps (28, 3) equal the sums. Floor deltas consistent: bump 699 → 696
(−5 preconditions turned fail-only, +2 selftest rows), mint 665 → 673
(floor re-derived after 8-count drift, net 0 from this PR).

## Settled rulings — all honored, none contradicted

- **Forged-oid over repack-aware `rm`**: `dead_oid` uses `hash-object --stdin`
  (blob type, no `-w`) — absence is a construction invariant. `corrupt_walk_break`
  /`corrupt_dead_tag` forge then `update-ref`. No deletion anywhere.
- **Only walk-contract skip-eligible**: construction invariants route to `fail()`
  with zero counted assertions (`corrupt_invariant_dead_absent`,
  `g1b.B7a:invariant-peel-fails`); only the `--merged`/`merge-base` walk-contract
  probe gates `corrupt_skip`.
- **Probe extended in this PR**: second run-source added in place, not a sibling
  probe (per CTO ruling).
- **Tier aggregate**: diff is CI-internal only — no SUT or gating-logic edits.

## Pattern observations (positive)

- **Chokepoint done right**: `_SOLEUR_GIT_CORRUPT_GRAPH_SOURCED` guard mirrors
  `git-fixture-env.sh` byte-for-byte idiom (`return 0 2>/dev/null || exit 0`);
  `_corrupt_*` internal prefix vs `corrupt_*` public prefix is consistent.
- **Caller contract is duck-typed and documented**: lib requires caller-defined
  `pass()`/`fail()`/`SKIPPED_ASSERTIONS`; `_corrupt_assert_repo` delegates to the
  suite's stronger `assert_fixture_dir` when present — consistent with the
  existing lib convention.
- **`corrupt_skip` annotation sanitization order is correct**: `%`→`%25` *before*
  CR/LF stripping — a literal `%0A` in echoed walk-stderr cannot forge a second
  annotation line.
- **Selftest-poisoning prevented**: every exercised `SKIP (loud):`/`::warning::`
  line is captured to a file and grepped there — none reach suite streams
  (verified in both suites' green runs: zero SKIP lines on a clean run).
- **`st_run` extended to snapshot `SKIPPED_ASSERTIONS`** (bump:2883) so selftest
  skip charges cannot leak into TOTAL; mint's snapshot driver restores all three
  counters.
- **Census verified real**: zero residual `rm … .git/objects/` hits under
  `.github/scripts/test/`; the regex does fire on the original spelling (tested:
  `rm -f "$F_REPO/.git/objects/${c2:0:2}/${c2:2}"` matches). Two out-of-scope
  sites confirmed at `scripts/ci-pr-selection.test.sh:432` and
  `apps/web-platform/infra/workspaces-luks-loopback.test.sh:868` — both outside
  `.github/scripts/test/`, tracked in **#10956 (verified OPEN)**.
- **Roster parity is bidirectional**: suites check call-site prefixes ⊆ probe
  prefixes; the t5 test's row (p) checks probe prefixes ⊆ call sites.
- **FAIL dominates TRANSIENT across sources** (probe:317); transient streak
  cleared on any real verdict, incremented only via `_transient`.
- **Probe discriminators are real**: `=== test-<name>.sh ===` emitted by
  `run-all.sh:176`; suite stderr (`SKIP (loud):` channel) flows through
  `bash "$t"` into the job log unfiltered — `gh run view --log` sees both.
- **Bogus `CORRUPT_WALK_PROBE_FORCE` degrades to the loud arm** (fail + skip),
  never silently to "contract present" — the fail-safe direction.

## Findings

### P2

**P2-1. The self-check machinery itself is duplicated, against the PR's own
one-spelling goal.** The roster-parity block is verbatim-duplicated between
`test-bump-inngest-bootstrap-pin.sh:2984-2992` and
`test-mint-inngest-bootstrap-tag.sh:2005-2014` — identical grep/sed/grep-v/fail
shape, differing only in the prefix regex (`g1b\.|g2b\.` vs `fl\.`). The tail
floor+ceiling block (`TOTAL` fold, `SKIP_CAP` compare) is likewise near-verbatim.
The PR exists to collapse five spellings of one construction into a lib; the
new *checks* reintroduce the same copy-and-vary pattern. A
`corrupt_roster_check <file> <prefix-ere>` in the lib would keep one spelling.
Not blocking: both copies are self-grepping and the semantics are identical.

**P2-2. `SOLEUR_FIXTURE_PACKED` has no in-repo driver.** The knob exists only in
`git-corrupt-graph.sh:103` (`_corrupt_maybe_repack`); no suite, selftest, or CI
step sets it. I ran both suites under it — identical counts, so the arm works —
but AC4's "permanent selftest arm" and tasks.md 5.2 ("selftest arm repacks
between seed+forge") read as if an automated exercise exists; it does not. The
packed-store regression class this PR fixes is therefore verified only by a
human remembering to set the env var. Mitigating: the forge is layout-immune
*by construction* (verified), so the arm is belt-and-suspenders. If AC4 intended
an automated arm, it's absent; if the knob alone satisfies it, the tasks.md
phrasing overstates.

**P2-3. Per-suite discriminator is a start-banner, not a completion marker.**
Source 1's positive control keys on `git-data-runcmd-rehearsal:` — a *terminal*
summary line proving the suite ran to completion. Source 2 keys on
`=== test-<name>.sh ===`, which `run-all.sh:176` prints *before* `bash "$t"` —
a suite that dies before reaching its corrupt-walk rows still counts as
"observed", and 0 markers read clean. Impact is bounded (a crashed suite reds
the required check anyway, and `MIN_ASSERTIONS` catches row deletion), but a
completion-line discriminator (e.g. the suite's `Results:` tail) would match
source 1's strength. Worth a comment noting the asymmetry even if kept.

**P2-4. Probe header docs describe only the first source.** The "Close
criteria" block (`t5-skip-persistence-bound-7510.sh:41-48`) still says "Sample
the most recent successful post-merge runs of infra-validation.yml" — now half
the story. The exit-code table (line 20) attributes FAIL solely to "the
deferred pre-bake / S1 extension", while FAIL now also means guard-suite hits
(the tail message at :319-324 does cover both). Header drift on the file whose
whole job is not-drifting.

**P2-5. `pg_ids` composition: merge_group crowds out pull_request regardless of
recency.** The two `gh run list` results are concatenated mg-first, deduped,
`head -20` — so when ≥20 merge_group runs exist, zero pull_request legs are
sampled, and the merged list is not globally time-ordered. The comment claims
pull_request legs "add density" and give pre-merge detection; under an active
queue they contribute nothing. If the intent is a window of the 20 *most recent*
runs across both events, interleave or split the quota. Defensible as-is
(merge_group legs are the required evidence) but the crowding-out is unstated.

### P3

- **P3-6. Census regex nits** (`test-bump:2978-2980`): the `.` in
  `_census_obj='.git/objects/'` is an unescaped ERE metachar (matches any char —
  harmless given the `rm`/`find` prefix requirement); the `rm -rf` alternative
  is subsumed by the first alternative (dead pattern); and a *comment* spelling
  like `# rm -f .git/objects/…` would false-positive (`[^#]*` does not exclude
  a `#` *before* `rm`).
- **P3-7. `dead_oid` nonce literal triplicated**: `'soleur-corrupt-graph
  dead-parent\n'` appears in the lib and is hand-copied into both suites'
  readable-dead-oid selftests. Drift is self-revealing (the selftest writes the
  literal blob and expects FAIL — a nonce change breaks the exercise loudly), so
  the duplication is pinned by its own test; a `_corrupt_dead_nonce` export
  would still remove a third spelling of a load-bearing literal.
- **P3-8. Two new SC2034 warnings** (`CORRUPT_WALK_PROBE_FORCE appears unused`)
  — one per suite, on the `{ VAR=skip fn; }` idiom; main's suite was
  warning-clean. No `.sh`-file shellcheck gate found in CI (shellcheck enters
  only via actionlint on workflow `run:` bodies), so non-blocking; the repo's
  disable-comment precedent (`# shellcheck disable=SC2034`, used in
  `apply-deploy-pipeline-fix.yml`) applies if the suites want warning-clean.
- **P3-9. pg run list doesn't filter `--status`/`conclusion`**: in-progress or
  cancelled runs can be sampled with partial logs — they count toward
  `g_sampled` without banners, degrading to TRANSIENT only if *all* sampled logs
  lack discriminators. Marginal.
- **P3-10. Forced-skip reason quotes measured stderr**: under
  `CORRUPT_WALK_PROBE_FORCE=skip` the message says "runner git does not exhibit
  the … contract" while quoting non-empty stderr (observed: `walk stderr:
  'error: Could not read c63a88d8…'` — the dead sha `c63a88d81206…`). Cosmetically
  confusing monitor text; also the sanitizer concatenates multi-line stderr with
  no separator.
- **P3-11. Census scope excludes the lib dir**: `plugins/soleur/test/lib/` is
  not swept — a deletion spelling added inside the lib itself would evade the
  census (the lib's own header is the only guard). Negligible today since the
  lib contains no deletion.
- **P3-12. Monitor `name:`/`STREAK_ARTIFACT_NAME` still say "rehearsal"** —
  deliberate per tasks.md 4.3 ("keep streak artifact name" — renaming orphans
  the persisted streak); the workflow display-name generalization is optional.

## Naming / duplication / boundary summary

- Naming: `corrupt_*` public / `_corrupt_*` private, `SKIP (loud):` marker,
  `SKIPPED_ASSERTIONS`/`SKIP_CAP`/`MIN_ASSERTIONS`, row ids `g1b./g2b./fl.` —
  all consistent with existing conventions (`arm_skip`, `git-fixture-env.sh`).
- Duplication: the call-site probe block (probe → force-check → skip-or-run) is
  repeated 5× but each row's contract genuinely differs (non-empty stderr /
  silent-drop / merge-base rc∉{0,1}); not refactorable without obscuring the
  per-row contract. The *check* blocks are the refactorable duplication (P2-1).
- No TODO/FIXME/HACK introduced. No layering violations — lib is a leaf consumed
  by suites; lib never reaches back into suite internals beyond the documented
  `pass/fail/assert_fixture_dir` contract.
