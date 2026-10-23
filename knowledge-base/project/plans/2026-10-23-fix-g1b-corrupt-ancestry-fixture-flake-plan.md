---
title: "flake(ci): g1b.B7 corrupt-ancestry fixture preconditions intermittently false on CI runners"
type: fix
date: 2026-10-23
slug: fix-g1b-corrupt-ancestry-fixture-flake
branch: feat-one-shot-10921-corrupt-ancestry-flake
issue: 10921
closes: 10921
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# flake(ci): g1b.B7 corrupt-ancestry fixture preconditions intermittently false on CI runners

## Overview

The g1b.B7 fixture in `test-bump-inngest-bootstrap-pin.sh` builds its corrupt tag-ancestry graph
by deleting a loose git object file with `rm -f`. That construction is silent when the object is
not at that loose path — a runner whose git stores the fixture's objects in a pack makes the
deletion a no-op, the graph stays readable, and the suite reports five broken-fixture FAILs on a
required check that gates every PR. The fix replaces the delete-a-file construction with a
deterministic never-written-object construction (`git hash-object` + `update-ref`) and gives the
one remaining environment-dependent precondition a counted, named SKIP verdict in the shape
ADR-188 prescribes.

## Research Insights

Consolidated 2026-10-23. Local research ran inline (subagent context — no Task tool; the
repo-research-analyst and learnings-researcher equivalents were executed in-process).

**Premise Validation (Phase 0.6):** #10921 is OPEN. The observing PR #10887 is MERGED
(2026-10-23) — the flake blocked one CI run, a retry passed, and the PR landed; the premise
(intermittent fixture, not a merged fix) holds. Epic #10397 is CLOSED; #10403 (flake-quarantine +
deterministic-loop guidance for **user** repos) is CLOSED — its deliverable was plugin-skill
guidance, not this repo's internal suite, so it is precedent, not a dependency. The issue's bare
filenames resolve to `.github/scripts/bump-inngest-bootstrap-pin.sh` and
`.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`; both exist on `origin/main`. The
proposed mechanism (counted SKIP + deterministic construction) instantiates ADR-188 rather than
contradicting any ADR — the mechanism-grep found no rejected-alternative collision.

**Root cause, measured on git 2.56.0 this session (four arms):**

- Arm A (current construction, loose store): `rm -f .git/objects/<fanout>` works as written —
  `git tag --merged HEAD` exits 0, empty list, `error: Could not read <sha>` on stderr. This is
  the green shape the fixture pins.
- Arm B (`git repack -ad` first, then the same `rm`): the deletion is a silent no-op, `cat-file -e`
  still reads the object — **the exact observed CI signature** (`precondition-c2-absent` FAIL,
  `precondition-merged-set-empty` FAIL, downstream refusal assertions cascade). The mechanism is
  confirmed: the construction assumes loose-object layout and `rm -f` fails open when the object
  lives in a pack. `ubuntu-latest` is a moving label, so which git version / maintenance behavior
  a run gets is not controllable; `git_fixture_env` pins config hermetically
  (`GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`), so only binary defaults vary.
- Arm C (forged commit object, `git hash-object -w -t commit --stdin` with a parent that was never
  written, `update-ref`): identical refusal shape — rc 0, empty list, same `Could not read`
  stderr — and **survives `git repack -ad`**. Deterministic.
- Arm D (forged tag object, `git hash-object -w -t tag --stdin` targeting a never-written commit):
  tag listed by `git tag --list`, `^{commit}` peel fails, `--merged` returns exactly the healthy
  tag — the B7a shape, deterministic.

**Defect census (same latent construction, grep `rm -f.*objects/`):** FIVE sites, not one —
`.github/scripts/test/test-bump-inngest-bootstrap-pin.sh:1604` (g1b.B7), `:1635` (g1b.B7c),
`:1649` (g1b.B7a), `:2608` (g2b.I6), and
`.github/scripts/test/test-mint-inngest-bootstrap-tag.sh:1132` (fl.walk). The issue names only
g1b.B7 because that is the row that flaked; the other four share the identical fail-open
construction and would flake the same way under the same runner condition.

**Relevant paths:**

- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — suite under repair; B7 block at
  ~1593–1614, B7c ~1627–1640, B7a ~1642–1661, g2b.I6 ~2602–2614; `pass`/`fail` counters +
  `MIN_ASSERTIONS=699` floor at ~66–71; tail tally `TOTAL=$((PASS + FAIL))` vs floor at EOF.
- `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` — sibling suite; fl.walk row at
  ~1127–1138; same harness (`MIN_ASSERTIONS=665`, `TOTAL=$((PASS + FAIL))` at ~1954).
- `.github/scripts/bump-inngest-bootstrap-pin.sh` — the guard under test; ancestry walk-stderr
  refusal at ~278–294 (`walk_err` → `die ancestry "…reported an unreadable history…"`). NOT
  edited — the fix is test-side only.
- `.github/scripts/mint-inngest-bootstrap-tag.sh` — the sibling guard under test. NOT edited.
- `.github/scripts/test/run-all.sh` — nested runner; invokes `bash "$t"` per suite, so a suite's
  stdout reaches the Actions log directly (no capture layer) — `SKIP (loud):` and `::warning::`
  lines are log-visible for free.
- `.github/workflows/pr-quality-guards.yml` — `guard-script-fixture-tests` job (~94–100) runs
  `bash .github/scripts/test/run-all.sh` on `ubuntu-latest`; it is a REQUIRED check
  (`scripts/required-checks.txt:82`) with no path filter — it gates every PR.
- `plugins/soleur/test/lib/` — shared fixture-lib home (`git-fixture-env.sh` precedent: the
  #7849 "one spelling of one idea" chokepoint). A new `git-corrupt-graph.sh` fits here; no census
  pins the directory's file set.
- `plugins/soleur/test/lib/git-fixture-env.sh` — pins the hermetic git env; confirmed the runner
  cannot vary git behavior via config, only via the binary.
- `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` — the standing skip-persistence
  probe: `WF="infra-validation.yml"` + `SUITE_TERMINAL='git-data-runcmd-rehearsal:'` +
  `SKIP_MARKERS` arm-name enumeration, sampled daily by
  `.github/workflows/scheduled-rehearsal-skip-monitor.yml`. Its own comments state the invariant
  this plan must honor: "a probe that goes quiet on the arm the fix creates is worse than no
  probe" — a new `SKIP (loud):` producer needs observer coverage or the ADR-188 residual it was
  built to bound re-opens unobserved.

**Institutional learnings applied:**

- ADR-188 (a transient environment decline is reachable under CI, must corroborate rather than
  infer) — the canonical four-property shape this plan ports: skip turns on a discriminating
  absence; harness defects outside the measured environment classes are FAIL, never skip; branch
  order load-bearing and commented; skip counted in assertion cost and capped.
- `2026-09-07-my-instruments-reported-green-while-measuring-nothing` + T5 probe positive control —
  a monitor must see a run-level discriminator, not merely count marker absence.
- `2026-08-13-making-a-red-gate-green-arms-everything-it-was-silently-gating` — the reason this is
  a required-check fix, not a quarantine: softening the suite degrades coverage for every PR.
- `hr-type-widening-cross-consumer-grep` — the five-site census above exists because of it.

**Property List (Phase 0.6b):**

1. The corrupt-ancestry construction produces the broken graph on every runner, regardless of
   object-store layout — the fixture can never silently build a healthy graph.
2. When the environment cannot exhibit the `--merged` corrupt-walk contract the row validates
   (git-version behavioral divergence), the suite reports an explicit named SKIP, not a
   broken-fixture FAIL.
3. The refusal contract under test (walk-stderr → `::error::ancestry:` before crane/gh) keeps
   full assertion coverage — no softening.
4. Skipped assertions stay counted: the anti-vacuity floor cannot be eroded by skips (ADR-188
   counted ceiling).

**Cut List (Phase 0.6b):**

- `git fsck` full-store probe → property 2 → `cat-file -e` per-object probe plus the `--merged`
  stderr-shape check covers it at a fraction of the cost; fsck also measures store integrity, a
  different property than the walk contract.
- Repack-aware deletion (`git prune-packed` + `rm`, or repack-then-delete-pack) → property 1 →
  strictly weaker than the never-written construction: it still reasons about store layout, which
  is the assumption that failed. Cut.
- Skip-only fix (issue's second candidate alone) → property 1 → makes skips routine on every
  runner whose layout diverges — coverage silently off; kept as the residual-environment backstop
  only, per the issue's own "or".
- Quarantine / soft-fail the suite → property 3 → degrades a required check's coverage for all
  PRs; rejected.

**Gate evaluation:** Observability (2.9) — skipped, no Files-to-Edit under
`apps/*/server|src|infra` or `plugins/*/scripts` and no new infra surface (a `scripts/` top-level
test/probe file does not match the trigger set). Encryption Posture (2.11) — skipped, no
persistent store or new connection. IaC (2.8) — skipped, no provisioning. GDPR (2.7) — skipped,
no regulated-data surface and none of the (a)–(d) extended triggers. ADR/C4 (2.10) — skipped, no
new architectural decision; the plan instantiates ADR-188 (a future reader of the ADR corpus is
not misled). External research (1.6) — skipped, repo-internal fixture with mechanism already
verified empirically and precedent in-repo. Community discovery (1.5) — skipped, no uncovered
stack. Functional overlap (1.5b) — no community artifact governs a repo-internal bash fixture;
the functional-discovery agent is unspawnable in this context and discovery never blocks
planning. Skill-description budget (1.8) — no `SKILL.md` description edits.

## Problem Statement / Motivation

Observed on PR #10887's CI run 39944137441 (job `Bash fixture tests for guard scripts`,
2026-10-23): five assertions in the g1b.B7 row failed because both fixture preconditions were
false — the "corrupt" graph was fully readable on that runner, so the script under test reached
`crane digest` instead of the `::error::ancestry:` refusal the row exists to pin. The same suite
passed twenty minutes later on a different branch against identical code, and the failing PR's
diff (`plugins/soleur/test/ci-pr-affected-replay.test.sh`) was disjoint from this fixture.

`guard-script-fixture-tests` is a required check with no path filter: it runs on every PR and
every merge_group attempt. A flake here costs a retry cycle on arbitrary PRs — and worse, it
trains the reflex that red fixture output is environment noise, which is how a genuinely broken
fixture gets waved through. The g1b.B rows pin the #8747/#8782 incident class (an off-main tag's
pin bump merging unreviewed bytes); their coverage must be deterministic, never best-effort.

**Root cause (measured, Research Insights §arms):** the fixture corrupts the object graph by
`rm -f` on a loose-object fanout path. `rm -f` exits 0 when there is nothing to delete — so on
any runner whose git keeps the object in a pack rather than at that loose path, the deletion is a
silent no-op and every downstream assertion fails. Reproduced deterministically this session by
repacking before the delete (Arm B).

## Proposed Solution

Three mechanisms, mapped to the Property List in `## Research Insights`:

**1. Deterministic corrupt-graph construction (property 1).** A new shared lib,
`plugins/soleur/test/lib/git-corrupt-graph.sh`, sources three helpers used by every corrupt-walk
row — the same "one spelling of one idea" chokepoint `git-fixture-env.sh` was created for (#7849),
because the defect census found FIVE sites across TWO suites spelling it independently:

- `dead_oid <repo>` — compute a sha that is guaranteed absent from the object store:
  `printf 'soleur-corrupt-graph %s\n' "<nonce>" | git -C <repo> hash-object -t commit --stdin`
  (NO `-w` — computed, never persisted; absence is a construction invariant, not a race).
- `corrupt_walk_break <repo> <ref>` — write a commit object via `hash-object -w -t commit`
  whose parent is a `dead_oid`, then `update-ref <ref>` to it. The ref's ancestry now traverses a
  never-written object; `git tag --merged`/`merge-base` emit `error: Could not read` on stderr
  and exit 0 on every store layout (verified loose AND packed, Arm C).
- `corrupt_dead_tag <repo> <tag>` — write a tag OBJECT via `hash-object -w -t tag` whose
  `object` field names a `dead_oid`, `update-ref refs/tags/<tag>` — tag resolves, `^{commit}`
  peel fails deterministically (Arm D, the B7a shape).

Site-by-site mapping (each keeps its existing expected semantics — only the construction changes):

| Site | Shape needed | Construction |
|---|---|---|
| g1b.B7 (~1604) | merged set EMPTY + walk stderr | `corrupt_walk_break` on `refs/heads/main` (forged tip, dead parent) |
| g1b.B7c (~1635) | merged set = exactly the tag + walk stderr | `seed_tag vinngest-v1.1.37` first, then `corrupt_walk_break` on main, then `seed_tag_at vinngest-v1.1.38` on the forged tip — verified on git 2.56: merged = exactly {v1.1.38} + `Could not read` stderr |
| g1b.B7a (~1649) | tag listed, peel fails, merged set = v1.1.37 | `corrupt_dead_tag` |
| g2b.I6 (~2608) | `merge-base` exits 128 → "could not decide" | `corrupt_walk_break` on `refs/remotes/origin/main` in `$H` |
| fl.walk (mint, ~1132) | walk reports unreadable history | `corrupt_walk_break` on main, tag on the forged tip |

The `rm -f .git/objects/…` lines are deleted at all five sites; the `main_commit c2`/`c3` commits
that existed only to be deleted are removed where they served no other purpose, keeping each
row's graph narrative in its comment.

**2. Counted, named SKIP for the residual environment dependency (property 2, ADR-188 shape).**
Deterministic construction removes the *storage-layout* variance but not the *walk-contract*
variance: the guard under test (and therefore the row) relies on `git tag --merged`/`merge-base`
printing `Could not read` on stderr while exiting 0 — a git-version behavior `ubuntu-latest` can
change. Each skip-eligible row gains a probe before `run_bump`/`run_mint`/`run_step`:

- Probe: run the walk on the constructed graph; contract = `Could not read` (or `error:`) present
  on stderr with the expected list/exit shape.
- Probe satisfied → run the row normally.
- Probe absent → `corrupt_skip <row-id> "runner git does not exhibit the rc0+stderr corrupt-walk
  contract (<observed>)"` — emits `SKIP (loud): <row> <reason>` AND `::warning::<row> skipped:
  <reason>` (annotation renders on the run's summary page), and charges `SKIPPED_ASSERTIONS` by
  the row's declared assertion cost. Any `<observed>` evidence echoed into either line is
  sanitized first — `%`→`%25`, CR/LF stripped via `${var//[$'\n\r']/}` — a raw stderr echo can
  forge a second annotation line (the mint suite already pins this percent-encode contract at
  its `fl-encode` row).

ADR-188's four properties, ported:

1. **Discriminating condition.** The skip turns on the walk-contract probe — a distinct, earlier
   measurement — never on "the row failed".
2. **Harness-bug rung above the skip.** A construction invariant failing (a `dead_oid` that
   `cat-file -e` can read, a forge whose `update-ref` did not take) is a harness defect and FAILs
   — never a skip. Only the enumerated environment class (walk-contract divergence) is
   skip-eligible.
3. **Branch order is load-bearing and commented:** construction-invariant check → walk-contract
   probe (skip) → run row, evaluated once.
4. **Counted and capped.** Each suite declares `SKIPPED_ASSERTIONS=0`; the tail floor becomes
   `TOTAL=$((PASS + FAIL + SKIPPED_ASSERTIONS))` against `MIN_ASSERTIONS`, plus a ceiling
   assertion `SKIPPED_ASSERTIONS <= <cap>` where `<cap>` equals the assertion cost of that
   suite's skip-eligible rows (bump suite: the B7/B7a/B7c/I6 rows' cost; mint suite: fl.walk's
   cost). The `SKIP (loud):` marker vocabulary matches the standing monitor's grammar.

**3. Cross-run persistence observer for the new skip producers (ADR-188 residual bound).**
`SKIP (loud):` lines from `guard-script-fixture-tests` are already in the job's Actions log
(`run-all.sh` invokes `bash "$t"` — no capture layer), but the standing probe
(`scripts/followthroughs/t5-skip-persistence-bound-7510.sh`) samples only
`infra-validation.yml` runs gated on the rehearsal suite's terminal line. Extend it so the new
producers are observed: add `SKIP (loud): g1b.`, `SKIP (loud): g2b.`, and `SKIP (loud): fl.`
markers plus a second run-source (`pr-quality-guards.yml` runs — sampled across events since the
suite runs identically on PR and merge_group legs) with its own positive-control discriminator (a
line unique to these suites' output, e.g. the `Results: N pass` terminal emitted inside the
fixture-tests step — verified at implement time that `gh run view --log` carries it unrelayed).
Mirror the marker additions in `t5-skip-persistence-bound-7510.test.sh`'s fed-log rows.
`scheduled-rehearsal-skip-monitor.yml` needs no edit if the probe's invocation stays unchanged —
the workflow calls the script; only its internals widen.

## Technical Considerations

- **`update-ref` + `hash-object -w` are plumbing-stable.** No porcelain behavior, no config
  dependency — the construction is immune to the binary-variance class that produced the flake
  (pack layout, gc defaults, maintenance tasks). The forged commit carries a valid `tree` (HEAD's
  own), well-formed author/committer headers, and only its `parent` is dangling.
- **A `dead_oid` is deterministically absent** because it is computed and never written — no
  store layout can surface it. Collision with a real object is a sha1-preimage event.
- **Test-only diff.** `bump-inngest-bootstrap-pin.sh`, `mint-inngest-bootstrap-tag.sh`, and every
  workflow that invokes them are untouched; the SUT's refusal logic is what the fixture validates,
  not what changes.
- **MIN_ASSERTIONS comments** (`:68` bump, `:86` mint) carry the "raise when adding rows, never
  lower it silently" contract — the counted-skip math keeps `TOTAL` unchanged on green runs and
  the floor comments get re-derived counts when assertion rows move.
- **Suite selftest tail** (the `st_run` harness at the bump suite's EOF and the mint suite's
  `mut_row` battery) gains rows driving the new machinery in both directions — a helper rewritten
  to always-pass or always-skip must red.
- **NFR:** none of the nfr-register classes are touched (no runtime code, no perf path, no data).
- **Sequencing trap (measured).** Tags/refs that must exist *below* the break are seeded BEFORE
  `corrupt_walk_break`: a rev walk from the forged tip cannot reach pre-break commits
  (`rev-list`/`rev-parse name~N` fail through the dead parent — measured: "Failed to traverse
  parents"). `git tag <name> <sha>` by literal sha still works afterwards because it only needs
  the object, not ancestry.

### Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Deterministic never-written construction (chosen) | Removes the store-layout dependency entirely; verified on git 2.56 loose and packed |
| Repack-aware deletion (`prune-packed`/`repack` + rm, or delete from pack) | Rejected — still reasons about store layout, the assumption that failed |
| SKIP-only (probe existing rm construction, skip when unreadable) | Rejected as primary — turns skips routine on divergent runners; kept as the backstop verdict |
| `git fsck` as the probe | Cut — measures store integrity, not the walk contract; heavier and noisier |
| Quarantine / soft-fail the suite or the row | Rejected — degrades a required check's coverage for every PR (the #8747 refusal rows are the point) |
| Per-suite duplicated forge helpers | Rejected — five sites across two suites is exactly the "four spellings of one idea" drift class #7849 closed |

## User-Brand Impact

- **If this lands broken, the user experiences:** CI friction if the suite false-reds (a required
  check blocks PRs), or — the worse arm — silent loss of the g1b refusal coverage: a future
  off-main-tag bump could proceed unrefused the next time a real tag anomaly occurs (the #8747
  incident shape), affecting the inngest bootstrap image tenants run on.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the change is
  CI-internal — fixture construction and a skip verdict; it does not move user data. The exposure
  is indirect and conditional: weakened detection of a supply-chain-adjacent mis-pin.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the diff itself reaches no user data, workflow, or
  money — realized harm requires BOTH this change weakening coverage AND a subsequent real tag
  anomaly; that is a coverage-regression pattern across runs, not a single merge's breach (see
  decision-challenges.md for the pending-assumed ruling).

## Guard Contract

### Guard 1 — deterministic corrupt-graph construction

**Property.** Every corrupt-ancestry row's break exists in the object graph by construction —
never by deleting a file that might not be there — so no runner store layout can leave the graph
readable.

**Assembly.** All corrupt-walk construction flows through ONE chokepoint:
`plugins/soleur/test/lib/git-corrupt-graph.sh` (`dead_oid`, `corrupt_walk_break`,
`corrupt_dead_tag`). The five call sites (g1b.B7, g1b.B7a, g1b.B7c, g2b.I6, fl.walk) are its only
consumers today; the zero-`objects/`-rm census AC pins the no-bypass invariant over the whole
`.github/scripts/test/` directory, not over the five known members — a sixth site written the old
way is itself the defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `dead_oid` gains `-w` (writes the "dead" object) | RED — the dead-oid `cat-file -e` invariant reads it back → harness-bug FAIL |
| 2 | `corrupt_walk_break` writes the forged commit but `update-ref` targets the wrong ref | RED — walk completes unbroken; the walk-contract probe or merged-set precondition fails |
| 3 | A sixth corrupt-walk site added with the old `rm -f objects/` construction after the compliant five | RED — the zero-`objects/`-rm census assertion in the suite/CI fails |
| 4 | Reorder: the forge moved to AFTER `run_bump`/`run_mint`/`run_step` in a row | RED — the SUT walks a healthy graph and the row's refusal assertions fail (order is the property) |
| 5 | Harness: `corrupt_skip` emits SKIP but omits the `SKIPPED_ASSERTIONS` charge | RED — a skipping run under-counts `TOTAL` below `MIN_ASSERTIONS` |
| 6 | Must-PASS (non-canonical input): the entire suite run with all fixture objects packed (`git repack -ad` injected into fixture setup) | PASS — construction is layout-agnostic; identical assertions |

### Guard 2 — counted, capped SKIP verdict

**Property.** A corrupt-walk row whose environment cannot exhibit the rc0+stderr walk contract
reports exactly one SKIP verdict, denominated in assertion cost and capped — never a
broken-fixture FAIL, and never a construction failure.

**Assembly.** The verdict predicate (the walk-contract probe) sits at the head of each
skip-eligible row; `SKIPPED_ASSERTIONS` plus the tail `TOTAL` arithmetic and the ceiling
assertion form the counting chokepoint in each suite; `corrupt_skip` is the single
emission/charge site; `SKIP_MARKERS`-class enumeration in the monitor probe is the cross-run
chokepoint.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Ceiling `SKIPPED_ASSERTIONS <= <cap>` lowered below one row's skip cost while a skip fires | RED |
| 2 | Tail floor reverts to `PASS + FAIL` (dropped `SKIPPED_ASSERTIONS` from `TOTAL`) | RED — a skipping run under-counts and the anti-vacuity floor fires |
| 3 | Probe widened so a construction-invariant failure also routes to skip | RED — the selftest row forcing a readable dead-oid must still FAIL, not SKIP |
| 4 | Two skip-eligible rows but `corrupt_skip` charges only the first | RED — ceiling/arithmetic catches the asymmetric charge |
| 5 | Harness: probe hard-coded "contract present" (skip unreachable) | RED on a divergent-git runner (the row FAILs instead of skipping — the skip's existence is asserted by the forced-skip selftest row) |
| 6 | Must-PASS (non-canonical input): probe forced to see a divergent walk (stub git emitting no stderr) | PASS — verdict is SKIP, warning emitted, suite exits 0 |

**Anchor.** The cap/floor numbers are stored constants; a weakening that keeps the arithmetic
green requires editing the constant in the same diff as the row costs it covers — the diff is
reviewed as one unit, and the marker/discriminator literals are enumerated strings the probe's
own test file re-derives from the suite's emitted lines.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Make the corrupt-graph construction deterministic (e.g., write the corrupt object with `git hash-object -w` + ref update rather than whatever currently races)" | `git-corrupt-graph.sh` + the five-site construction rewrite (Phase 1–2) | mapped |
| 2 | "or gate the fixture's precondition with a `git fsck`/cat-file probe that skips with a named reason when the environment refuses to reproduce the corruption — a precondition that cannot be established should be an explicit `SKIP`, not a broken-fixture `FAIL`" | Counted-skip plumbing + walk-contract probe (Phase 1–2) | mapped |
| 3 | "Ref #10887 …, epic #10397 line (flake-quarantine guidance shipped via #10403 — this is a live case for it)" | ADR-188-shape skip + `SKIP (loud):`/`::warning::` emission + monitor coverage (Phase 3) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `plugins/soleur/test/lib/git-corrupt-graph.sh` (new shared lib) | "write the corrupt object with `git hash-object -w` + ref update" | inferred — justification: five sites across two suites spell the same construction; one chokepoint is the #7849 drift fix |
| g1b.B7a / g1b.B7c / g2b.I6 / fl.walk rewrites | — | inferred — justification: identical fail-open construction in the same required job; fixing only B7 leaves the same flake live four more times (census in Research Insights) |
| `SKIPPED_ASSERTIONS` + ceiling + floor arithmetic | "an explicit `SKIP`, not a broken-fixture `FAIL`" | inferred — justification: ADR-188 property 4 is the repo's binding shape for a skip verdict |
| `SKIP (loud):` + `::warning::` emission | — | inferred — justification: the repo's loud-skip vocabulary (#7574 relay grammar) so the monitor and run pages can see it |
| `t5-skip-persistence-bound-7510.sh` + `.test.sh` monitor extension | — | inferred — justification: "a probe that goes quiet on the arm the fix creates" (the probe's own comment); a new skip producer with no observer re-opens ADR-188's accepted residual unbounded |
| MIN_ASSERTIONS comment/count updates | — | inferred — justification: the floor contract ("raise when adding rows, never lower it silently") |

### Split Assessment

- Subsystems touched: 3 — `.github`, `scripts`, `plugins`
- Planned files: 6 | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `grep -rn 'rm .*objects/' .github/scripts/test/` returns zero hits for loose-object
  fanout deletions in `test-bump-inngest-bootstrap-pin.sh` and
  `test-mint-inngest-bootstrap-tag.sh` (census, not a spot-check).
- [ ] AC2 — `plugins/soleur/test/lib/git-corrupt-graph.sh` exists and both suites source it;
  `bash -n` clean and shellcheck clean per the suites' own lint conventions.
- [ ] AC3 — `bash .github/scripts/test/run-all.sh` exits 0 locally; the bump suite prints
  `Results:` with all g1b.B7/B7a/B7c and g2b.I6 rows PASS; the mint suite's fl.walk rows PASS.
- [ ] AC4 — Packed-store proof: a fixture-setup arm injecting `git repack -ad` before the corrupt
  construction produces identical row outcomes (preconditions hold, refusals asserted) — the
  observed flake class is closed, not just worked around.
- [ ] AC5 — Forced-divergence proof: with the walk-contract probe made to observe no stderr
  marker (stub git or forced probe flag), each affected row emits exactly one
  `SKIP (loud): <row>` line, one `::warning::` annotation, charges its declared assertion cost,
  and both suites still exit 0.
- [ ] AC6 — Construction-invariant proof: forcing a readable dead-oid (e.g., the `-w` mutation
  from Guard 1 row 1) produces FAIL — never SKIP.
- [ ] AC7 — Tail accounting: `TOTAL=$((PASS + FAIL + SKIPPED_ASSERTIONS))` and a
  `SKIPPED_ASSERTIONS <= <cap>` ceiling assertion exist in both suites; a skip beyond cap reds.
- [ ] AC8 — `SKIP_MARKERS`/run-source coverage: the standing probe (or a sibling it invokes)
  samples `pr-quality-guards.yml` runs and greps `SKIP (loud): g1b.`/`g2b.`/`fl.` markers, with a
  suite-level positive-control discriminator so marker-absence can never read as clean.
- [ ] AC9 — `MIN_ASSERTIONS` floor comments carry re-derived counts where assertion rows moved;
  floors were not lowered silently.
- [ ] AC10 — `git diff origin/main` touches no file under `.github/scripts/` outside
  `.github/scripts/test/` — the SUT scripts are byte-identical.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI test-infrastructure change. All eight
domains assessed semantically against the plan (Marketing, Engineering, Operations, Product,
Legal, Sales, Finance, Support): the work is a test-fixture correction plus a monitor-probe
widening; it creates no user-facing surface, no architectural decision, no vendor/procurement
step, no regulated-data surface, no revenue/support touch. The Engineering assessment question
asks for "significant architectural decisions … beyond normal implementation" — this is a
measured bug fix instantiating an existing ADR-188 pattern, not an architecture change. The
mechanical UI-surface override did not fire (no `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx` in Files to Create/Edit). Domain-leader agents were not spawnable in this
subagent context (no Task tool); the sweep above is the orchestrator's own semantic assessment.
Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Test Scenarios

- Given a loose-object fixture store, when the g1b.B7 row runs, then the dead-oid invariant
  holds, `--merged` is empty with the stderr marker, and the full `assert_refused` block passes —
  `integration`.
- Given a packed fixture store (`git repack -ad` in fixture setup), when every corrupt-walk row
  runs, then every row produces identical outcomes to the loose-store run — `integration` —
  this is the regression scenario for the reported flake.
- Given a stub git that suppresses the walk's stderr error, when a skip-eligible row runs, then
  exactly one `SKIP (loud):` line and one `::warning::` annotation emit, `SKIPPED_ASSERTIONS`
  gains the row's declared cost, and the suite exits 0 — `integration`.
- Given a `dead_oid` that is readable (mutation), when the construction invariant check runs,
  then the row reports FAIL with a harness-bug message — never SKIP — `unit`.
- Given `SKIPPED_ASSERTIONS` exceeding the declared cap, when the tail accounting runs, then the
  ceiling assertion fails — `unit`.
- Given `TOTAL` computed without `SKIPPED_ASSERTIONS`, when a run skipped rows, then the
  anti-vacuity floor fails — `unit`.
- Given probe run-logs containing `SKIP (loud): g1b.B7` and the suite discriminator, when the
  persistence probe samples them, then the marker is counted as a hit (FAIL verdict) — `integration`.
- Given probe run-logs carrying the suite discriminator but no skip markers, when the probe
  samples them, then PASS — `integration`.
- Given run-logs with NEITHER discriminator nor markers, when the probe samples them, then
  TRANSIENT (un-run instrument, never a clean bill) — `integration`.

## Success Metrics

- `guard-script-fixture-tests` posts zero `fixture broken: c2 still readable` / corrupt-walk
  precondition failures across subsequent CI runs — the flake signature is gone, not retried.
- Any `SKIP (loud):` occurrence on the suite's markers surfaces via the standing monitor within
  its daily cadence, and is visible as a `::warning::` annotation on the run summary the same day.
- Both suites' `Results:` lines stay at or above their `MIN_ASSERTIONS` floors on green runs.

## Dependencies & Risks

- **Runner-image git drift (the residual risk).** A future `ubuntu-latest` git that changes
  `tag --merged`/`merge-base` corrupt-walk behavior flips rows to SKIP instead of FAIL — the
  intended, louder outcome — observed by the monitor within a day.
- **Probe widening risk.** Sampling `pr-quality-guards.yml` adds a second workflow source to a
  probe written single-source; the discriminator must be suite-scoped (a `Results:` line is
  ambiguous across suites — use a suite-unique line such as the `=== Guard 1b:` header emitted
  inside the step's log, verified at implement time), or the positive control reads the wrong
  suite's silence as clean.
- **Assertion-count drift.** Rows whose assertion counts change (precondition renames, skip-eligible
  blocks) must re-derive `MIN_ASSERTIONS` comments and the skip cap — the ceilings are asserted,
  but the comments are prose.
- **`hash-object -w` writes objects permanently** into the fixture repo — intended; the forged
  objects are scenario-local under `$TMP` and die with the suite's `rm -rf "$TMP"` trap.
- **Deferred:** extending the monitor is an inferred scope item — recorded in
  decision-challenges.md as pending-assumed; if deferred at review, file the tracking issue
  before merge (a deferral without a tracking issue is invisible).

## Open Code-Review Overlap

None — queried 95 open `code-review` issues for both
`.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` and
`.github/scripts/bump-inngest-bootstrap-pin.sh`; zero matches.

## Files to Create

- `plugins/soleur/test/lib/git-corrupt-graph.sh` — `dead_oid`, `corrupt_walk_break`,
  `corrupt_dead_tag`, `corrupt_skip` (emission + charge); sourced by both suites. Header comment
  carries the root cause and the "one spelling" rationale.

## Files to Edit

- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — source the lib; rewrite the B7,
  B7a, B7c and g2b.I6 constructions; add `SKIPPED_ASSERTIONS` plumbing, walk-contract probes,
  ceiling + floor arithmetic, selftest rows for both directions; re-derive `MIN_ASSERTIONS`
  comment.
- `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` — source the lib; rewrite the
  fl.walk construction; same skip plumbing and tail arithmetic; re-derive `MIN_ASSERTIONS`
  comment.
- `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` — widen run-source to also sample
  `pr-quality-guards.yml` runs; extend the marker enumeration with `g1b.`/`g2b.`/`fl.` skip
  producers; add the suite-scoped positive-control discriminator.
- `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` — fed-log rows covering the
  new markers and the second workflow source.

## Implementation Phases

### Phase 1 — shared lib + bump suite

1. Write `plugins/soleur/test/lib/git-corrupt-graph.sh` with the four helpers, header comment
   citing this issue and the Arm-B reproduction.
2. Source it from `test-bump-inngest-bootstrap-pin.sh`; rewrite g1b.B7, g1b.B7a, g1b.B7c and
   g2b.I6 to the deterministic constructions per the site-mapping table.
3. Add `SKIPPED_ASSERTIONS` + `corrupt_skip` plumbing, the walk-contract probe, ceiling and the
   `TOTAL` arithmetic; re-derive the `MIN_ASSERTIONS` comment.
4. Add selftest/`st_run` rows for the skip machinery (forced-skip → SKIP counted; invariant
   break → FAIL; charge-omission → floor fires).

### Phase 2 — mint suite

5. Source the lib from `test-mint-inngest-bootstrap-tag.sh`; rewrite fl.walk to the forged-tip
   construction; add the same skip plumbing and tail arithmetic; re-derive its `MIN_ASSERTIONS`
   comment.

### Phase 3 — cross-run observer

6. Extend `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` (second workflow source,
   new markers, suite-scoped discriminator) and its `.test.sh` fed-log rows.
7. Re-check `scheduled-rehearsal-skip-monitor.yml` — confirm the probe invocation needs no
   change; edit only if the contract moved.

### Phase 4 — verification

8. `bash .github/scripts/test/run-all.sh` locally → rc 0; run the packed-store arm and the
   forced-divergence arm (AC4/AC5); `git diff` census (AC1/AC10).
9. Confirm CI green on the PR for `Bash fixture tests for guard scripts`; leave the monitor to
   observe the first sampled window.

## References & Research

- Issue: #10921 (this plan's `closes:`); observed on PR #10887 run 39944137441, job
  `Bash fixture tests for guard scripts` (2026-10-23).
- Precedent ADR: `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`
  (counted-skip verdict shape; amendment noting ADR-262's third carve-out).
- Guard under test: `.github/scripts/bump-inngest-bootstrap-pin.sh` (~278–294 walk-stderr
  refusal); sibling `.github/scripts/mint-inngest-bootstrap-tag.sh`.
- Monitor: `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` + `.test.sh`,
  `.github/workflows/scheduled-rehearsal-skip-monitor.yml`, relay
  `apps/web-platform/infra/run-registered-suites.sh` (#10786).
- Fixture env: `plugins/soleur/test/lib/git-fixture-env.sh` (hermetic git env; #7833/#7849).
- Incident pinned by these rows: #8747 (off-main tag bump), #8782 (merged-into-main selection).
- Related closed context: epic #10397, guidance issue #10403 (user-repo flake-quarantine
  guidance — precedent, not dependency).
- Measured evidence: four construction arms this session on git 2.56.0 (Research Insights).
