---
title: "fix: lint-diagnosis-claims does not scan apps/web-platform/infra"
date: 2026-08-06
type: fix
issue: 7310
closes: [7310]
branch: feat-one-shot-7310-lint-diagnosis-claims-infra-scope
pr: 7315
lane: cross-domain
brand_survival_threshold: none
---

# fix: `lint-diagnosis-claims` does not scan `apps/web-platform/infra`

## Overview

`scripts/lint-diagnosis-claims.sh` (ADR-166 — *an operator-facing CI message may not name a
cause the job did not measure*) does not scan `apps/web-platform/infra/`. It should. The
directory is where `registry-userdata-budget.sh:131` told operators that
`#7280's registry_rationale_strip is the fix` — a causal claim the job never measured, and
one that was **wrong**: #7280 had merged 6 h 22 m earlier so the strip was already applied,
and the real defect was in the gate's own render. The claim stood on `main` ~10.5 h (#7283
14:40Z → #7300 01:16Z) and reached the recut runbook, which is why unwinding it took two PRs
(#7300, #7303).

**Deliberately not claimed:** that any operator acted on it. #7287 was opened at 08:38Z, six
hours *before* the message reached `main`, so it cannot have been mis-steered by it — and
the earlier draft of this paragraph asserted exactly that, along with a sentence presented in
quote marks that appears nowhere in #7287. Both were unmeasured causal claims, written into
the plan for the lint that exists to stop unmeasured causal claims; review caught them.

That is precisely the class ADR-166 and this lint exist to stop, and the lint could not see
it because the directory was out of scope.

The change is two parts, and **both must ship together**. Part 1 alone demonstrably does not
close the gap — this plan re-measured that independently rather than inheriting the claim
(see *Measurements*, variant B).

`lane:` is set to `cross-domain` because no `spec.md` exists for this branch — the
fail-closed default per the plan skill's lane rule, not a judgement that the change is
cross-domain. It is a single-domain engineering-tooling change.

## Premise Validation

Every premise this plan inherits was re-verified in-worktree rather than trusted from the
routing summary or the issue body.

| Premise (as cited) | Probe | Result |
|---|---|---|
| #7310 is OPEN and unclaimed | `gh issue view 7310` + `linked:issue` / `in:body` / `in:title` / `git log` probes | **Holds.** OPEN, `closedByPullRequestsReferences` empty. #7300 and #7303 surfaced as body-probe candidates; both are citations — #7300 closes #7299 and its diff touches neither `lint-diagnosis-claims.sh` nor its test |
| Prerequisite: the `"…is the fix"` message is gone from `main` | `grep -n "is the fix" apps/web-platform/infra/registry-userdata-budget.sh` in-worktree | **Holds.** Absent. The line now reads `OVER CAP by N bytes — hcloud would reject the CREATE *after* the DESTROY succeeded, stranding the sole pull path` (`registry-userdata-budget.sh:280`) — an observation, not a cause |
| The work is not already done | `git show main:scripts/lint-diagnosis-claims.sh` | **Holds.** `DIRS` is still the 3-entry list; the `CLAIM` regex has no fix/cause alternative |
| Baseline is 1 and the suite is BLOCKING | read `.highwater`; `grep -n lint-diagnosis-claims scripts/test-all.sh` | **Holds.** Baseline `1` (`scripts/followthroughs/zot-soak-6122.sh`); registered at `scripts/test-all.sh:486` |

## Measurements

Every number below was produced by running the **real scanner**, patched at its `DIRS` /
`CLAIM` anchors and driven through its own `--census` mode via the `LINT_DIAGNOSIS_ROOT`
test seam. No reimplementation of the scan logic was used, because a reimplementation would
measure my model of the lint rather than the lint.

### Variants

| | `DIRS` widened | `CLAIM` alternative added |
|---|---|---|
| **A** baseline | — | — |
| **B** scope only | ✅ | — |
| **C** claim only | — | ✅ |
| **D** both | ✅ | ✅ |

### Against the live repo

| Variant | census | files walked |
|---|---|---|
| A baseline | 1 | 220 |
| B scope only | 1 | **291** |
| C claim only | 1 | 220 |
| D both | **1** | **291** |

Census is unchanged at **1** (baseline 1) in every variant, so **no `.highwater` edit is
needed** and the change lands green.

The `files walked` column is load-bearing and is why this is evidence rather than silence:
the widening actually reaches **71 new files** (220 → 291). A zero-new-hits result from a
walk that never entered the directory would be byte-identical to a clean one. (171 files in
the tree match `SCAN_EXTS`; exactly 100 are `.test.sh`/`.test.yml` and correctly excluded.)

The shipped figure is **290**, not 291: review added `.bench.sh` to the exclusion set, which
removes `credential-persist-home-guard.bench.sh` — a benchmark harness narrates causes and
is not an operator-facing CI message.

### Against a fixture carrying the verbatim offending message

This is the measurement that decides whether part 2 can be skipped. Fixture: a synthesized
`apps/web-platform/infra/registry-userdata-budget.sh` carrying the historical line
`OVER CAP by $((size - CAP)) bytes — … #7280's registry_rationale_strip is the fix.`

| Variant | census | why |
|---|---|---|
| A baseline | 0 | directory out of scope |
| **B scope only** | **0** | **in scope, and still not flagged** |
| C claim only | 0 | phrase matches, directory out of scope |
| **D both** | **1** | flagged |

**Variant B is the whole point.** Widening the scope reads like it closes the gap, and on
its own it demonstrably does not. Shipping only part 1 would ship a lint that looks enforced
and is not — the exact failure mode named in this lint's own file header. Confirmed
separately: the existing `CLAIM` regex does **not** already match the offending line, so the
new alternative is necessary, not redundant.

### Word-boundary behaviour

These figures are for the form as originally planned, `\bis the (?:fix|cause)\b`. Review
widened it to a closed adjective enumeration (`is|was|are|were`, optional
`root|actual|real|only|underlying|true`, `fix|cause|culprit`, `\s+` for the gaps) after
measuring that one intervening word defeated the original and that the wider form still
costs **+0 hits**. Both `\b` anchors survive unchanged and every row below still holds.

Both anchors are load-bearing. 10/10 cases behave as intended:

| Input | Matches | Note |
|---|---|---|
| `registry_rationale_strip is the fix.` | ✅ | the verbatim offender |
| `the rotated token is the cause here` | ✅ | `cause` variant |
| `IS THE FIX` | ✅ | `re.IGNORECASE` |
| `is the fix-forward path` | ✅ | hyphen is a non-word char, so `\b` holds |
| `This the fix was applied` | ❌ | `This` ends in `is`; the **leading** `\b` blocks it |
| `Analysis the fix landed` | ❌ | same class |
| `this is the fixture we use` | ❌ | the **trailing** `\b` blocks it |
| `that is the fixed value` | ❌ | same |
| `it is the causes we list` | ❌ | same |
| `what is the cause of this?` | ✅ | interrogative — a theoretical false positive; see Risks |

### Escape-hatch interaction

The new alternative composes correctly with all three existing exemptions — it widens what
counts as a *claim*, and changes nothing about what counts as *measured*:

| Fixture | census | want |
|---|---|---|
| bare claim | 1 | 1 |
| `+ # MEASURED-BY:` marker | 0 | 0 |
| `+ verdict=` variable in the window | 0 | 0 |
| claim appearing only inside a comment | 0 | 0 |

### Every line in the widened scope carrying the new phrase

Six lines match `\bis the (fix|cause)\b` **on `origin/main`**. All are exempt for principled
reasons, which is why the census does not move. (The shipped tree has more: this PR's own
comments add further occurrences, all of them comments and so correctly skipped.)

| Line | Disposition |
|---|---|
| `.github/workflows/infra-validation.yml:748` | comment — documentation, correctly skipped |
| `scripts/followthroughs/inngest-watchdog-functions-query-6407.sh:16` | comment |
| `scripts/cutover-inngest.sh:220` | comment |
| `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh:8` | comment |
| `apps/web-platform/infra/ci-deploy.sh:1728` | comment |
| `.github/workflows/reusable-release.yml:1289` | **not a comment** — see *Deferred* below |

## Research Reconciliation — issue vs codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| Add `apps/web-platform/infra` to `DIRS`; zero new hits | Confirmed: 0 new hits, +71 files walked | Adopt as written |
| Add the `CLAIM` alternative; zero new hits | Confirmed: 0 new hits | Adopt as written |
| `.highwater` must not be raised | Confirmed: census stays 1 | No edit to `.highwater` |
| **AC: `lint-diagnosis-claims.test.sh` → 11 passed** | The suite was at **11** assertions | **AC amended — and the conflict is this plan's, not the issue's.** #7310 is internally consistent: it asks for 11/11 and never asks for a committed fixture, mentioning one only as a scratch measurement it had already run. Committing the regression assertion is a deliberate DEVIATION from its AC, taken because this lint's own header argues that a guard never observed failing is indistinguishable from one that cannot fail. An earlier draft of this row called the issue's AC set "mutually exclusive"; that was false and is corrected here — mischaracterizing the source is the wrong error to make in the table whose job is recording deviations honestly. Final count is **17** after review-driven additions |
| `MIN_ASSERTIONS = 9  # derived from a green run (11 at time of writing)` | Stays valid at 12 (9 < 12), but the parenthetical becomes stale | Update the comment to `12`. A stale comment about measurement, inside the suite for a lint about unmeasured claims, is the defect class this PR exists to remove |
| Issue names only `DIRS` and `CLAIM` as edits | The file's `SCOPE.` header and the `DIRS` inline comment both **enumerate the scanned directories in prose** | Both updated in the same edit, or the file's own documentation lies about its scope |
| — | **The sweep above stopped at the file boundary, which review caught.** Two artifacts *outside* the lint also enumerate the three-directory scope and were left false: `ADR-166:93` (the normative document the lint enforces) and the 2026-08-03 zot-mirror post-mortem | Both corrected in this PR. The principle was right and applied too narrowly — the unit of the sweep is the **claim**, not the file |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is a CI lint with no
runtime surface. The realistic failure is indirect and is the one this PR removes: a future
operator-facing CI message under `apps/web-platform/infra/` names an unmeasured cause, the
operator follows it and spends a recovery window on a defect that does not exist — the #7242
shape, where production sat three releases behind for four hours chasing a credential the
same job had already verified live.

**If this leaks, the user's data/workflow/money is exposed via:** no exposure vector. The
change adds no data flow, no credential handling, and no network call; it widens a static
scanner's directory list.

**Brand-survival threshold:** `none` — reason: the diff touches only `scripts/` and
knowledge-base artifacts, matches no path in the canonical sensitive-path regex (verified:
`apps/[^/]+/infra/` is not touched — the infra directory is *scanned* by this change, not
*edited*), and has no user-facing or data surface.

## Files to Edit

| File | Change |
|---|---|
| `scripts/lint-diagnosis-claims.sh` | `DIRS` (`:61`); `CLAIM` (`:75-80`); `SCOPE.` header prose (`:18-23`); `DIRS` inline comment (`:54-60`) |
| `scripts/lint-diagnosis-claims.test.sh` | add `apps/web-platform/infra` to the fixture tree; add the regression assertion; update the `MIN_ASSERTIONS` parenthetical (`:201`) |

**Not edited:** `scripts/lint-diagnosis-claims.highwater` — the census does not move, and the
file ratchets down only.

## Implementation Phases

Ordered so the contract change lands before the test that consumes it.

### Phase 1 — RED: the regression fixture

Add to `scripts/lint-diagnosis-claims.test.sh`, in ARM 1 (the fixtures that MUST trip):

- extend the fixture-tree `mkdir -p` to include `"$FIX/apps/web-platform/infra"`;
- write a synthesized `registry-userdata-budget.sh` fixture carrying the verbatim historical
  message. (`cq-test-fixtures-synthesized-only` is secrets hygiene and does not itself
  mandate this shape; the practice is adopted by analogy.) The surrounding script is synthesized;
  only the offending sentence is quoted, exactly as ARM 1 already does for the two historical
  offenders;
- assert `census_of "$FIX"` is `1`, then `rm` the fixture.

Run the suite. It **must fail** here — that is the proof the fixture is load-bearing. A
fixture that passes before the fix would be testing nothing.

This single assertion pins **both** parts: the fixture lives in the new directory (reverting
part 1 makes it fail) and carries the new phrasing (reverting part 2 makes it fail).

### Phase 2 — GREEN: scope

`scripts/lint-diagnosis-claims.sh:61`:

```python
DIRS = [".github/workflows", ".github/actions", "scripts", "apps/web-platform/infra"]
```

Update the `SCOPE.` header (`:18-23`) and the `DIRS` inline comment (`:54-60`) so the prose
names the fourth directory and says why: it is where the `registry_rationale_strip is the fix`
message shipped, and it was invisible to this lint for the same reason `.github/actions/` was
invisible to `lint-workflows.sh` — nobody had pointed a scanner at it.

### Phase 3 — GREEN: the `CLAIM` alternative

`scripts/lint-diagnosis-claims.sh:75-80`:

```python
CLAIM = re.compile(
    r"most likely cause|likely cause|the cause is|"
    r"which is the [a-z]+(?:-[a-z]+)+ shape\b|"
    r"serving is fine|not an outage|= the EDGE|which means the|"
    r"this means (?:a|the|that)|indicates (?:a|the|that)|caused by|"
    r"\bis the (?:fix|cause)\b",
    re.IGNORECASE)
```

The phrasing asserts a cause by prescribing its remedy — *"X is the fix"* — which is why it
matched none of the existing alternatives. Both `\b` anchors are load-bearing; keep them.

### Phase 4 — Verify

Run the acceptance criteria below, then `bash scripts/test-all.sh` for the `scripts` shard.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** `DIRS` in `scripts/lint-diagnosis-claims.sh` contains all four directories.
      `grep -c 'apps/web-platform/infra' scripts/lint-diagnosis-claims.sh` → **4** (≥ 1 ✓).
- [x] **AC2** The `CLAIM` regex carries the new alternative, anchored on the regex line:
      `grep -cE '^\s*r"\\bis the \(\?:fix\|cause\)\\b"' scripts/lint-diagnosis-claims.sh` = 1.

      *Amended during /work.* The original form was `grep -cF 'is the (?:fix|cause)' … = 1`.
      Run literally against the implementation it returned **2**, because the change also
      documents the alternative in a comment above the regex. Re-anchoring rather than
      relaxing to `= 2` is the point: measured, the bare-literal form still returns **1** on
      a file with the regex line **deleted** and the comment retained — it would have passed
      on a broken lint. Comment lines begin with `#`, so the `^\s*r"` anchor cannot match one
      (`cq-assert-anchor-not-bare-token`; the "narrowing is not anchoring" sharp edge).
- [x] **AC3** `bash scripts/lint-diagnosis-claims.sh` exits 0 and its **stdout** reads
      `lint-diagnosis-claims: OK — 1 unmeasured causal claims (baseline 1).` — verified by
      reading the printed verdict, not `$?` (the script also exits 0 on the `--census` path
      and prints a distinct `note:` line when it sits *below* baseline).
- [x] **AC4** `bash scripts/lint-diagnosis-claims.sh --census` printed **1**.
- [x] **AC5** `bash scripts/lint-diagnosis-claims.test.sh` → **17 passed, 0 failed**
      (the issue's `11`, +1 for the committed regression fixture, +5 from review: hit-identity,
      the near-miss far-side fixture, the `tests/` scope fixture, the scope-loss case, and the
      harness self-check). `MIN_ASSERTIONS` raised 9 → 17 in lockstep.
- [x] **AC6** The `.highwater` **baseline value** is unchanged at `1`:
      `git show origin/main:scripts/lint-diagnosis-claims.highwater | sed 's/#.*//' | tr -d '[:space:]'`
      and the same on the branch both yield `1`, and the file's diff is comment-only
      (`git diff --unified=0 … | grep -E '^[+-][^+-]' | grep -vE '^[+-]\s*#'` is empty).

      *Amended during review.* The original form asserted the file was untouched
      (`grep -c highwater` → 0). Review added a comment to it resolving the
      "ratchets down only" vs scope-widening contradiction, so the literal command now
      returns 1. Reverting a useful fix to satisfy a proxy would be the wrong repair, and
      so would silently relaxing the AC — what the criterion actually protects is the
      **number**, which is asserted directly above.
- [x] **AC7** The regression fixture is load-bearing in **both** directions, verified by
      mutation rather than inspection — each mutant applied to a working copy with the
      anchor asserted present first, then reverted and the baseline re-confirmed:

      | Tree | Suite |
      |---|---|
      | baseline | 12 passed, 0 failed |
      | mutant A — `DIRS` entry reverted, `CLAIM` intact | **11 passed, 1 failed** |
      | mutant B — `CLAIM` alternative reverted, `DIRS` intact | **11 passed, 1 failed** |
      | restored baseline | 12 passed, 0 failed |

- [x] **AC8** The file's own scope documentation is truthful: the `SCOPE.` header names
      `apps/web-platform/infra/` and says why it was added.
- [x] **AC9** `bash scripts/test-all.sh` green: **rc=0**, `=== 267/267 suites passed ===`,
      zero `[FAIL]` lines, and `[ok] scripts/lint-diagnosis-claims (1085ms)` in the run.
      Read as the whole report, not just the exit code:

      - **Preamble:** `siblings: 0`, `LOCK_ACQUIRED`, `/tmp` 28% used — a clean run, so the
        green is not a contention artifact.
      - **Coverage epilogue:** `apps/web-platform/infra/ is NOT covered above (diff does not
        touch it)`. Correct and expected — this change *scans* that directory, it does not
        *edit* it, so the infra runner is not the gate for this diff. Recorded rather than
        skipped past, per the definite-article trap (#6969).
      - The one `[contention] BANNER`-shaped grep hit was `[ok] AC4: the advisory banner
        names LOCK_CONTENDED_PROCEEDING` — an assertion *label* inside the contention suite,
        not a fired banner.
- [x] **AC10** Follow-up filed as **#7318**, extended after review with the baseline-semantics
      and scope-default findings plus their measured data. Net issue flow: filing **1**
      (#7318), closing **1** (#7310) — **net 0**, contingent on `ship` writing `Closes #7310`
      into the PR body, which is the phase that establishes it. Recorded as contingent rather
      than done, because at review time the body was still the pipeline stub.

There are no post-merge operator steps. Nothing here requires a deploy, a dispatch, or a
dashboard.

## Deferred

**`OPERATOR_LINE`'s helper-call alternative is `^\s*`-anchored, so it misses continuation
lines.** `.github/workflows/reusable-release.yml:1289` is a real operator-facing helper call
(`degraded sign "$?" "…"`) whose message contains *"waiting and re-running is the fix"*. It
does not trip, because the line begins with `||` and the anchor fails.

Measured, not assumed: un-anchoring that alternative to `(?:^|\|\||&&|;)` takes the census to
**2** against a baseline of **1** — a red required check on `main`. That is the *same* shape
that blocked #7310 until #7300 merged, and resolving it means first deciding whether that
message is a genuine unmeasured claim (it is hedged — *"a plausible cause"* — and passes an
exit code to its helper) or a false positive.

That is its own analysis with its own baseline consequences, and folding it in here would
turn a green two-line change into a red one. Filed as a follow-up rather than absorbed, per
`wg-when-an-audit-identifies-pre-existing`. **This is a pre-existing gap surfaced by this
work, not a regression introduced by it** — the census is unchanged at 1 either way.

## Open Code-Review Overlap

**None.** All 64 open `code-review` issues were queried; none names
`scripts/lint-diagnosis-claims.sh`, `.test.sh`, or `.highwater` in its body.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change — a CI lint's directory list and one regex alternative. No
user-facing surface, no data model, no vendor, no cost.

**Product/UX Gate:** not applicable. The mechanical UI-surface override does not fire — no
path in `Files to Edit` matches the UI-surface term list or glob superset.

## Gate Dispositions

| Gate | Disposition |
|---|---|
| 2.7 GDPR / Compliance | **Skip.** No regulated-data surface; no schema, auth flow, API route, or `.sql`. None of the (a)–(d) expansion triggers fire — no LLM processing, threshold is `none`, no new cron reading `knowledge-base/`, no new distribution surface |
| 2.8 Infrastructure-as-Code | **Skip.** No new infrastructure. The change *scans* `apps/web-platform/infra/`; it provisions nothing |
| 2.9 Observability | **Skip.** `Files to Edit` contains no path under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no new infrastructure surface. The changed surface is a CI lint whose entire output is its own stdout, already read by a required check |
| 2.9.1 Soak follow-through | **Skip.** No time-gated close criterion |
| 2.10 ADR / C4 | **Skip.** No architectural decision. This *implements* ADR-166's existing decision over a directory it already covered in spirit; it neither extends nor reverses it. No external actor, system, container, or access relationship changes — checked against `model.c4`, `views.c4`, `spec.c4`: the lint is not a modelled element and introduces no new edge |
| 2.11 Encryption Posture | **Skip.** No persistent store, no new cross-component connection |
| 4.5 Scoped advisor consult | **Skipped, recorded.** The plan is mechanical — two files, no architecture choice — and every claim in it is backed by a measurement run against the real scanner rather than by judgement. A curated second opinion has nothing to arbitrate here |
| Plan-review panel | **Skipped, recorded.** Same rationale; the change receives full multi-agent review at the `/review` step of this one-shot run, which reads the actual diff rather than the plan text |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `is the fix` over-matches in future prose (e.g. an interrogative *"what is the cause of X"*) | Accepted by design. This lint's own header states the calibration: on this corpus false positives are cheap (a claim phrase must *also* sit on an operator line, and the `# MEASURED-BY:` escape hatch is one comment away) while the false negative is the entire point. Measured: 0 false positives across 291 files |
| The widened walk pulls in `.test.sh` fixtures that quote causal prose | Already handled upstream: the scanner skips `*.test.sh`, `*.test.yml`, and any path containing `/test/`. 100 of the 171 matching files in the directory are excluded on this rule |
| A symlink in the new directory becomes a read primitive | Already handled: `os.path.islink` is skipped, and `os.walk` does not recurse symlinked directories. Verified: the directory contains no symlinks |
| The `MIN_FILES` vacuity floor (40) interacts badly with the wider walk | **Corrected at review — the original entry here verified the wrong proposition.** It cited the floor firing on an *empty* root and concluded "no interaction". Empty-root is not the case that matters: the floor is over the TOTAL, so any single directory can vanish while the rest clear it. Measured — renaming the infra entry to `infras` drops all 71 files and still prints `OK — 1 unmeasured causal claims`. Fixed in this PR by a per-entry `os.path.isdir` hard-error, which is strictly stronger than any floor value, plus a `partial_root` test case (carrying a real file, so exit 2 there can only come from the missing directory and not from vacuity) |
| Census moves under a future merge and the PR lands red | AC3 reads the printed verdict rather than `$?`, so a `note:`/`FAIL` line cannot be mistaken for `OK` |

## Test Scenarios

1. **The offender is caught.** Synthesized fixture under `apps/web-platform/infra/` carrying
   the verbatim historical message → census 1.
2. **Both parts are required.** Reverting `DIRS` → fixture not flagged. Reverting the `CLAIM`
   alternative → fixture not flagged. (This is AC7's mutation test.)
3. **The escape hatches still exempt.** Same fixture plus `# MEASURED-BY:` → 0; plus a
   `verdict=` variable in the evidence window → 0; claim inside a comment → 0.
4. **The live repo is unchanged.** Census 1, baseline 1, exit 0.
5. **The ratchet mechanics are untouched.** Missing baseline → exit 2; regression above
   baseline → exit 1; empty walk → exit 2. All pre-existing suite cases still pass.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before
  requesting deepen-plan or `/work`.
- **Do not read `$?` from `lint-diagnosis-claims.sh` as the verdict.** It exits 0 both when
  the census is at baseline and when it is *below* baseline (printing a `note:` asking you to
  lower the file), and `--census` exits 0 unconditionally. Read stdout. This is the same
  exit-code-vs-message trap that `registry-userdata-budget.sh` set for #7287's precondition (c).
- **`.highwater` ratchets down only.** If a future change moves the census up, the fix is the
  message, never the baseline.

## Review Outcome

Five agents, report-only, pinned to `f3f419f43`; all edits applied by the orchestrator from
that SHA. `shellcheck` clean (substituting semgrep, whose bash parser matches ~0 rules and
would have returned a vacuous "0 findings"). Every finding below was **fixed inline** — the
cost-of-filing gate auto-flips at ≤100 lines / ≤4 files, and `pr-introduced` findings are
never eligible for scope-out regardless.

**The headline: this PR shipped unmeasured causal claims in its own comments.** The lint's
SCOPE header asserted the message "spent a production-recovery window"; measured, #7287 was
opened six hours *before* that message reached `main`, so it cannot have been mis-steered by
it. The same header claimed the directory was read by "no lint" — `lint-trap-tempfile-ownership.py`
walks all 166 tracked `.sh` there via `git ls-files "*.sh"`. Both corrected.

| # | Finding | Severity | Fix |
|---|---|---|---|
| 1 | A `DIRS` typo drops 71 files and still prints `OK` — `MIN_FILES` is a floor over the total and cannot see one entry vanish | **P1** | Per-entry `os.path.isdir` hard-error + a `partial_root` case carrying a real file, so its exit 2 can only come from the missing directory |
| 2 | The plan's risk row verified the floor on an *empty* root and concluded "no interaction" — the wrong proposition | **P1** | Row rewritten with the measured partial-loss result |
| 3 | The regression assertion pinned cardinality, not identity — relocating the fixture out of `infra/` stayed green 12/12 | P2 | New `--detail` mode + an assertion on the hit path |
| 4 | No far-side fixture: all four boundary-loosening mutations of the new alternative survived | P2 | `nearmiss.yml` fixture; all four now red |
| 5 | One intervening word defeated the alternative (`is the root cause`), so the *hedged* form was caught and the *confident* forms were not | P2 | Closed adjective enumeration + `\s+`; measured +0 hits. The open slot `(?:[a-z]+ )?` was measured at +2 and rejected |
| 6 | `MIN_ASSERTIONS=9` against a 12-assertion suite — this PR's own new assertion was deletable unnoticed | P2 | Raised to the full count (17), still a `-lt` floor |
| 7 | The count floor cannot see an always-pass `assert_eq` (`if true` → 12 passed, exit 0) | P3 | Harness self-check proving the comparator still discriminates both ways |
| 8 | `"/test/" in path` matched **nothing** — the tree uses `tests/`, `test-fixtures/`, `fixtures/` | P3 | `/tests?/`, plus a fixture making it load-bearing (reverting it now reds) |
| 9 | `.bench.sh` walked as operator prose | P3 | Added to the exclusion set |
| 10 | `.terraform/` is gitignored but `os.walk` descends it — local-vs-CI divergence after `terraform init` | P3 | Pruned in-walk |
| 11 | The ratchet windows `mv` the committed baseline with no trap coverage | P3 | `EXIT` trap restores it |
| 12 | `ADR-166:93` and the 2026-08-03 post-mortem still enumerated the old three-directory scope | P2 | Both corrected — the sweep's unit is the claim, not the file |
| 13 | Plan prose: `11/11` (table has 10 rows), `#7247` (should be #7242), a sentence in quote marks absent from #7287, `~99` (exactly 100), `cq-test-fixtures-synthesized-only` miscited, and the issue's AC set called "mutually exclusive" when the deviation was this plan's | P3 | All corrected above |

**Second mutation battery**, over the axes the first one never touched (control green, every
mutation diff-verified to land, sandbox copy):

| Mutation | Before review | After |
|---|---|---|
| relocate fixture out of `infra/` | survived 12/12 | **killed** |
| drop leading `\b` / trailing `\b` / both | survived ×3 | **killed** ×3 |
| open the adjective slot | survived | **killed** |
| delete the scope-loss guard | n/a (guard did not exist) | **killed** |
| neuter `assert_eq` to always-pass | survived 12/12 | **killed** |
| delete either new assertion | survived | **killed** by the raised floor |
| revert `/tests?/` → `/test/` | equivalent (no observable change) | **killed** after adding the `tests/` fixture |
