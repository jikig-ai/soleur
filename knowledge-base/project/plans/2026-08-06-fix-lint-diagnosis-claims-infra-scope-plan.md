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
directory is where `registry-userdata-budget.sh` told every operator who hit it that
`#7280's registry_rationale_strip is the fix` — a causal claim the job never measured, and
one that was **wrong**: the strip had already been applied, and the real defect was in the
gate's own render. That claim then propagated into the recut runbook and into #7287's
precondition (c), where it read as *"the recut must not be dispatched at all"* — an
unmeasured cause reaching the procedure for re-provisioning the sole container-registry
pull path.

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
the tree match `SCAN_EXTS`; ~99 are `.test.sh` and correctly excluded.)

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

### Word-boundary behaviour of `\bis the (?:fix|cause)\b`

Both anchors are load-bearing. 11/11 cases behave as intended:

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

Six lines match `\bis the (fix|cause)\b`. All are exempt for principled reasons, which is
why the census does not move:

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
| **AC: `lint-diagnosis-claims.test.sh` → 11 passed** | The suite is at **11** assertions today. The issue also asks for a regression fixture so part 2 is *enforced*, not merely present — and adding one makes it **12** | **AC amended to 12.** The two halves of the issue's own AC set are mutually exclusive; the fixture is the half worth keeping, because this lint's file header argues at length that a guard never observed failing is indistinguishable from one that cannot fail. Recorded rather than silently resolved |
| `MIN_ASSERTIONS = 9  # derived from a green run (11 at time of writing)` | Stays valid at 12 (9 < 12), but the parenthetical becomes stale | Update the comment to `12`. A stale comment about measurement, inside the suite for a lint about unmeasured claims, is the defect class this PR exists to remove |
| Issue names only `DIRS` and `CLAIM` as edits | The file's `SCOPE.` header (`:18-23`) and the `DIRS` inline comment (`:54-60`) both **enumerate the scanned directories in prose** | Both must be updated in the same edit, or the file's own documentation lies about its scope |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is a CI lint with no
runtime surface. The realistic failure is indirect and is the one this PR removes: a future
operator-facing CI message under `apps/web-platform/infra/` names an unmeasured cause, the
operator follows it, and — as in #7247 — spends a production-recovery window on a defect that
does not exist.

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
  message, per `cq-test-fixtures-synthesized-only` — the surrounding script is synthesized;
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

- [ ] **AC1** `DIRS` in `scripts/lint-diagnosis-claims.sh` contains all four directories.
      `grep -c 'apps/web-platform/infra' scripts/lint-diagnosis-claims.sh` ≥ 1.
- [ ] **AC2** The `CLAIM` regex carries the new alternative.
      `grep -cF 'is the (?:fix|cause)' scripts/lint-diagnosis-claims.sh` = 1.
- [ ] **AC3** `bash scripts/lint-diagnosis-claims.sh` exits 0 and its **stdout** reads
      `lint-diagnosis-claims: OK — 1 unmeasured causal claims (baseline 1)`. Read the
      message, not `$?` — the script also exits 0 on the `--census` path and prints a
      distinct `note:` line when it sits *below* baseline.
- [ ] **AC4** `bash scripts/lint-diagnosis-claims.sh --census` prints `1`.
- [ ] **AC5** `bash scripts/lint-diagnosis-claims.test.sh` → **12 passed, 0 failed**
      (amended from the issue's `11`; see Research Reconciliation).
- [ ] **AC6** `scripts/lint-diagnosis-claims.highwater` is **unmodified**.
      `git diff --name-only origin/main...HEAD | grep -c highwater` = 0.
- [ ] **AC7** The regression fixture is load-bearing in **both** directions. Verified by
      mutation, not by inspection: reverting *either* the `DIRS` entry *or* the `CLAIM`
      alternative makes `lint-diagnosis-claims.test.sh` fail. Both arms must be exercised.
- [ ] **AC8** The file's own scope documentation is truthful: the `SCOPE.` header names
      `apps/web-platform/infra`.
- [ ] **AC9** `bash scripts/test-all.sh` `scripts` shard is green.
- [ ] **AC10** A follow-up issue exists for the `OPERATOR_LINE` anchor gap (see *Deferred*),
      carrying the measured census delta.

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
| The widened walk pulls in `.test.sh` fixtures that quote causal prose | Already handled upstream: the scanner skips `*.test.sh`, `*.test.yml`, and any path containing `/test/`. ~99 of the 171 matching files in the directory are excluded on this rule |
| A symlink in the new directory becomes a read primitive | Already handled: `os.path.islink` is skipped, and `os.walk` does not recurse symlinked directories. Verified: the directory contains no symlinks |
| The `MIN_FILES` vacuity floor (40) interacts badly with the wider walk | No interaction — it is a floor, not an equality, and the walk grows from 220 to 291. Confirmed the floor still fires correctly: the probe copies tripped `walked 0 files, expected >= 40` when pointed at an empty root |
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
