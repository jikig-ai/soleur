---
title: "chore(ci): re-price the cloudflare-readonly suite weight from floor to measured (#12441 P.2)"
type: chore
date: 2026-11-15
slug: chore-reprice-cloudflare-readonly-suite-weight
branch: feat-one-shot-12441-p2-reprice-cf-readonly
issue: 12441
closes: none   # Ref #12441 only. #12441 stays open (P.1 and the epic cleanup remain)
pr: 12778
priority: p3
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# chore(ci): re-price the cloudflare-readonly suite weight (#12441 P.2)

Spec lacks valid lane: defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch.

## Enhancement Summary

**Deepened on:** 2026-11-15.
**Research:** kept proportionate to a one-row data change, per the pipeline brief.
- Before deepening, the plan-review panel ran: DHH, Kieran, code-simplicity and the CTO devex lens. Its findings were applied.
- The deepen pass ran the mechanical halts and live citation checks inline. It did not run the 40-agent fan-out.

### Key Improvements

1. Added an `## Observability` section with a 3 ms grep probe. Phase 4.7 Step 1 triggers on any
   path outside the docs set.
2. Checked live:
   - #12441, #10479, #10205, #11679 and #12780 are OPEN; #12515 is MERGED.
   - #12515 is commit `8dad4ed240` on main and touches the suite.
   - #11679 does mention the replay re-price.
   - `wg-when-deferring-a-capability-create-a` is active in AGENTS.md.
   - The labels `semver:patch` and `meta/machinery` exist.
3. Halts: 4.6 passes (threshold `none`, no sensitive path). 4.8 found 0 PAT-shaped tokens. 4.12
   passes: one unfenced Scope Check, all three subsections present, no `unmapped` row.
   - 4.9, 4.10, 4.11 and 4.13 do not trigger: no UI surface, no store or connection, no guard
     deliverable and no new autonomous task. The drift gate named here is existing machinery, not
     a deliverable.

### New Considerations Discovered

- The discoverability probe prints `0` before the edit and `1` after it, verified on a scratch
  copy, so it can fail.

Change one data row in `scripts/suite-durations.tsv`:

```text
- plugins/soleur/test/cloudflare-readonly.test.sh<TAB>1261<TAB>floor
+ plugins/soleur/test/cloudflare-readonly.test.sh<TAB>155229<TAB>measured
```

The suite has had real CI timings since #12515 merged, but the committed table still prices it at the
1261 ms floor. That is about 120 times lower than what it measures, so the light-leg packer and the
#8231 local scheduler both under-weigh it. Post-merge item P.2 of #12441 (follow-up of #10479, epic
#10205) is the re-price. The value and `src` are set by the CTO ruling below and match the line in
open PR #12698 byte for byte.

Edit no other file. Do not touch the header, the manifest or any other row. PR #12778 (already open
as a draft on this branch) carries the change. Its body says `Ref #12441`, with no closing keyword
anywhere. `closingIssuesReferences` must stay `[]`.

## Rulings carried in (not re-opened)

- **Ruled by CTO agent, 2026-11-15:** open a row-only PR now from `origin/main`. #12698, another
  session's full Lever-A re-price, carries the same `155229 measured` row. That PR is
  `CONFLICTING`, has auto-merge off and has not been updated since 2026-11-13T16:48Z. Use
  155229 ms, `src=measured`, byte-identical to #12698's line. If
  `scripts/regenerate-shard-manifest.py` would rewrite rows other than this one, make a single-row
  edit instead. Never edit or push to #12698.
- **Evidence:** the `suite-timings` artifacts of three green `merge_group` runs on 2026-11-12
  (43325786672, 43324336862, 43315786965) gave 192026, 186106 and 129838 ms for this suite.
  #12698's 5-run median is 155229. Re-checked today: all three runs are `merge_group` / `success`.
- **Ruled by CTO agent, 2026-11-15 (plan-review devex panel):**
  - Do not run an `--incremental --durations` header-refresh pass after the edit. It would add
    two `suite-shard-legs.tsv` header lines, which breaks "edit no other file". Row-only wins.
  - Do not file an issue for a new single-row re-price flag: the two-step recipe already exists.
  - Track the "never hand-edited" docs wording as follow-up **#12780**, not in this PR.

## Research Insights

**Premise validation.**
- #12441 is OPEN and has no closing PR.
- #12698 is OPEN and `CONFLICTING`, with `autoMergeRequest: null`, `updatedAt`
  2026-11-13T16:48:44Z and `headRefOid` 3f9923a5a3837bdf204d5d9236d9ddf5c3d3e609.
- #12778 is an OPEN draft on this branch with `closingIssuesReferences: []`.
- The row on `origin/main` (8a2e510739) is still `1261 floor`.
- Byte-identity, checked at plan time:
  `gh pr diff 12698 | grep -cxF "$(printf '+plugins/soleur/test/cloudflare-readonly.test.sh\t155229\tmeasured')"`
  returns `1`.
- `collision-precheck.sh 12441` reported only #12778, which is this PR, plus `test-all.sh`
  processes in two unrelated worktrees (12656, 12008). Those matter only for local suite runs:
  `dev-suite-mutex` serialises them.

**How the generator and its consumers work** (this answers the three questions in the brief).

1. **Is `scripts/suite-durations.tsv` the only file that changes? Yes.** The derived manifest
   `scripts/suite-shard-legs.tsv` maps label to leg (this row: leg 5). It holds no weights.
   - **No gate re-derives legs from weights.** `scripts-shard-manifest.test.sh` `check_durations`
     checks only:
     - row shape: `label<TAB>ms<TAB>src`, with `src` in {measured, floor, estimate};
     - that rows are label-sorted;
     - durations keys == manifest keys;
     - every label is registered;
     - the three provenance headers are present (presence only, not their values).
   - **The CI runner reads only the manifest.** `scripts/test-all.sh` `_shard_selects` does a
     manifest lookup.
   - **The drift gate (#11662 G1) runs only inside the script.** It fires on a
     `regenerate-shard-manifest.py --write` to the committed table, or when
     `--baseline-durations` is passed. No CI job compares the committed table to the merge-base.
     No CI job checks a `measured` row against an artifact.
   - `shard-balance-watch.yml` (weekly `--drift-report`) and `wallclock-p90-watch.yml` are
     scheduled advisories, not PR gates.
   - **Other readers of the table:**

     | Reader | What it does with the table | Effect of this row |
     |---|---|---|
     | `scripts/ci-oracle-lane.test.sh` `check_legs` | Sums leg loads (`LEG-OVER-BUDGET` > 1500000) | None: only members of `scripts/ci-oracle-lane-legs.tsv` count, and this label is not one |
     | `scripts/test-all.sh` `_aff_full_cost_min` | Sums every row for the runner-changed banner | Cosmetic: about +2.6 min |
     | `plugins/soleur/test/pr-overlap-preflight.test.sh` | Matches the filename only | None |
2. **Does a hand edit pass, and is there a single-row mode? A hand edit passes. No mode re-prices one row on its own.**

   | Mode | What it does | Result for this row |
   |---|---|---|
   | `--incremental` against the committed table | Pins incumbent rows verbatim and fetches no timings | No-op. Dry run: `0 moved, 0 new`, `+0 floor row(s)`, leg 5 still priced at 1373887 ms |
   | `--incremental --durations <hand-edited table>`, scratch copies | Same pinning, priced from the edited table | Durations table "already in parity — untouched". Manifest: `0 moved`, and only 2 header lines change (`default-weight-ms` 1272→1275, `generated-at`). It confirms the hand edit is in parity; it does not price anything. Not used (CTO ruling above) |
   | `--runs N` / `--run` / `--timings-dir` | Full re-aggregation of every row | Rewrites the whole table (that is #12698's Lever-A). Learning `2026-10-30-…regen-pricing-can-break-committed-invariants.md` records that a full re-price reds `test-all-fast-tier-budget` on drift already on main |
   | Seed path (learning `2026-10-31-shard-reprice-checkpoint-mechanics.md`): `--durations seed.tsv --write` without `--incremental` | Same full pass, fed a seed table | Simulated on scratch copies, with no repo writes: rewrites 140 floor rows (1222 → 1275), rewrites the headers, drops `# growth-acked=` and a free-text comment line, and moves 45 manifest legs |

   So the hand edit is the only way to change this row without touching others, which meets the
   ruling's condition.

   **Drift-gate equivalence.** The seed-path simulation, run with
   `--baseline-durations <origin/main blob>`, exits 0 with zero violations. It prints one note:
   `floor→measured 'plugins/soleur/test/cloudflare-readonly.test.sh': 155229ms (exempt per-suite,
   counts toward total)`. The verdict carries over to the hand-edited table for two reasons:
   - `drift_violations` reads only `src=measured` rows and src transitions. It never reads
     floor-row values, so the 140 re-floored rows do not change the result.
   - The measured set is identical in both tables.

   The measured total rises from 9446707 to 9601936 ms (+1.6%). The gate's limit is 10%. So no
   `--allow-growth` is needed, and the existing `# growth-acked=` stamp stays as it is.
3. **P.2's original wording** (archived `…cf-analytics-reader-12441/tasks.md`, items 6.4 and P.2)
   says to re-price "through `scripts/regenerate-shard-manifest.py`". It says `--incremental` would
   re-price the row and that "the tsv is never hand-edited". The code shows `--incremental` cannot
   re-price a row, so that premise was wrong. See the reconciliation below; the docs fix is #12780.

**Committed-weight gates checked against the new value.**
- `test-all-fast-tier-budget`: this label is not in `ALWAYS_ON_SUITES`, so its 10 s per-suite cap
  does not apply.
- `test-all-corpus-weight-budget` (always-on): per-suite cap 600000 ms. 155229 is under it, and no
  exemption row exists or is needed.
- `regenerate-shard-manifest.test.sh` Z3 pins `DRIFT_ROW light <first floor label> 1222 …`. The
  first floor row is still `.claude/hooks/bare-head-self-heal.test.sh` at 1222. The floor count is
  computed dynamically (141 → 140). It stays green.
- Light-leg priced loads: leg 5 goes from 1373887 to 1527855 ms. Leg 6 is already 1796500, so
  the maximum leg is unchanged. Nothing gates this.

**Property List.**
- P1: the committed weight for `plugins/soleur/test/cloudflare-readonly.test.sh` is the CI-measured
  `155229 measured`.
- P2: no other row, header or file changes, so #12698 can still be rebased onto this.
- P3: the PR references #12441 and does not close it.

**Cut List.**
- Regenerating through the script → buys P1 but breaks P2 (shown above) → cut.
- The `--incremental --durations` header-refresh pass → buys nothing listed and breaks P2 → cut by
  the CTO ruling.
- A `# … re-priced …` header comment (there is a precedent comment line for `replay-a`) → buys no
  listed property and breaks P2 → cut. Provenance goes in the commit message and PR body instead.
- Re-running the drift gate during work → it repeats the recorded simulation, and running the
  generator with `--write` near committed paths is the risk Sharp Edges names → cut (plan review).
- Re-pulling the artifacts and recomputing the median → buys nothing; the value is fixed by the ruling → cut.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| P.2 / 6.4: re-price "through `scripts/regenerate-shard-manifest.py`"; "`--incremental` … re-prices it"; "the tsv is never hand-edited" | `--incremental` pins incumbent rows verbatim (docstring §INCREMENTAL REGEN; dry run: 0 moved, +0 floor rows). Every pricing mode re-aggregates the whole table | Single-row edit per the CTO ruling's explicit fallback. The drift gate's verdict carries over (see equivalence above). Docs fix: #12780 |
| `scripts/test-all.sh` run_suite comments and ADR-242's amendment text say "suite-durations.tsv are NOT hand-edited" / "never hand-edited" | Doctrine text, not a gate. The runbook's replay-a re-seat is a precedent for a single-row re-seat | The CTO ruling overrides it for this row. The wording fix is tracked in #12780 and is out of scope here |
| Runbook: "merge conflict on the TSV → regenerate, never hand-merge" | This PR does not resolve a conflict | Not triggered. If main moves the TSV before merge, rebase. A textual conflict on a *different* row is resolved by keeping both sides' rows, since rows are independent and label-sorted. Then re-run the gates |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The worst case is an
  operator-visible red `test-scripts` CI leg (for example a malformed row, or keys-parity drift
  failing `scripts-shard-manifest.test.sh`) that blocks the merge queue until reverted.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The row
  is a public test label and a duration in milliseconds.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** a CI scheduling weight for an internal test suite touches
  no user data or product surface. The diff touches no path matching the preflight
  `SENSITIVE_PATH_RE`.

## Observability

This section is here because deepen-plan Phase 4.7 Step 1 triggers on any path outside the docs
set. The change adds no runtime surface; the signals below already exist.

```yaml
liveness_signal:
  what: the committed row reads `155229 measured`, and the CI `test-scripts` legs that consume the table/manifest pass
  cadence: every PR and merge_group run
  alert_target: the PR's and merge queue's required checks
  configured_in: .github/workflows/ci.yml (test-scripts matrix -> bash scripts/test-all.sh scripts)
error_reporting:
  destination: red CI check on #12778 / the merge_group run (GitHub Actions)
  fail_loud: true — scripts-shard-manifest.test.sh exits 1 with a named FAIL line on a malformed, unsorted or key-divergent row
failure_modes:
  - mode: malformed or unsorted row, or durations keys != manifest keys
    detection: plugins/soleur/test/scripts-shard-manifest.test.sh check_durations (CI test-scripts leg)
    alert_route: required check red on the PR / merge queue
  - mode: the weight later goes stale (the suite's real time drifts >= 4x and >= 120 s)
    detection: shard-balance-watch.yml weekly --drift-report PRICE_DRIFT_ROW
    alert_route: the watch-owned tracker issue "ci-shard-balance-watch: manifest drift findings"
  - mode: the weight breaches the per-suite corpus cap (600000 ms)
    detection: scripts/test-all-corpus-weight-budget.test.sh (always-on)
    alert_route: required check red on the PR / merge queue
logs:
  where: GitHub Actions job logs plus the suite-timings-scripts-* artifacts of each run
  retention: 14 days for artifacts; job logs per the repo's Actions retention
discoverability_test:
  command: grep -c 'cloudflare-readonly.*155229.measured$' scripts/suite-durations.tsv
  expected_output: "1"
```

## Files to Edit

- `scripts/suite-durations.tsv`: the single row whose content is
  `plugins/soleur/test/cloudflare-readonly.test.sh<TAB>1261<TAB>floor` becomes
  `plugins/soleur/test/cloudflare-readonly.test.sh<TAB>155229<TAB>measured`.

## Files to Create

- None. The plan artifacts are under `knowledge-base/project/{plans,specs}/` only.

## Open Code-Review Overlap

None. The bodies of the 95 open `code-review` issues were searched for
`scripts/suite-durations.tsv`, with no match.

## Implementation

1. From the worktree root, use the Edit tool to make an exact-match replacement of that one row.
   Keep the tabs and the trailing newline.
2. Run the four local gates (next section). If a gate fails, stop and diagnose. Do not regenerate
   as a fix.
3. Commit using the message `chore(ci): re-price cloudflare-readonly suite weight to measured (Ref #12441)`. The body names the ruling, the three run ids, the per-run values and #12698's 5-run median.
   - No closing keyword (close/fix/resolve in any form) may appear in any commit message, the PR title or the PR body.
   - Hand the PR-body mechanics (title, `## Changelog`, semver label) to `soleur:ship`.
   - The one plan-specific constraint is that the body says `Ref #12441`.
   - A compound learning file under `knowledge-base/project/learnings/` is allowed; AC1 excludes that path.

## Gates

**CI (automatic on the PR and merge_group).** The `test-scripts` matrix runs
`bash scripts/test-all.sh scripts` across 8 legs, which is the full light group. That covers every
suite that reads this file:

- the edge-set members in `scripts/lib/test-affected-paths.sh` (`scripts-shard-manifest`,
  `regenerate-shard-manifest`, `scripts-shard-totality`, `test-all-fast-tier-budget`,
  `test-all-weight-drift`, `test-pyramid-fixtures`, `ci-oracle-lane`, `betterstack-incident-mirror`,
  the followthrough registry suite);
- the always-on `test-all-corpus-weight-budget`.

No separate manifest-drift job exists.

**Local fast check** (from the worktree root; each suite returns non-zero on failure). These four
read the committed row's shape or weight, so they are the ones this edit can break:

```bash
bash plugins/soleur/test/scripts-shard-manifest.test.sh      # shape, src enum, sort, keys==manifest, registered, headers
bash plugins/soleur/test/regenerate-shard-manifest.test.sh   # generator fixtures + Z3 committed-table arm
bash scripts/test-all-corpus-weight-budget.test.sh           # 600 s per-suite cap / exemption ledger
bash scripts/test-all-fast-tier-budget.test.sh               # always-on tier caps (label not in tier)
```

The rest run in CI (AC3).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "re-price the `plugins/soleur/test/cloudflare-readonly.test.sh` row in scripts/suite-durations.tsv from `1261 floor` to `155229 measured`" | Files to Edit; Implementation step 1 | mapped |
| 2 | "The PR must say Ref #12441 only, never Closes/Fixes, and closingIssuesReferences must be []." | Implementation step 3; AC2 | mapped |
| 3 | "Use 155229 ms, src `measured`, byte-identical to #12698's line" | AC1; premise-validation byte check | mapped |
| 4 | "If scripts/regenerate-shard-manifest.py would rewrite rows other than this one, make a single-row edit instead." | Research Insights item 2 (mode table); AC1 | mapped |
| 5 | "Never edit or push to #12698." | Sharp Edges (process constraint) | mapped |
| 6 | "Name the exact gates CI runs for this change … and the local commands to run them." | Gates | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| One-row TSV edit | "re-price the … row … from `1261 floor` to `155229 measured`" | asked |
| Gate list + local commands | "Name the exact gates CI runs for this change" | asked |
| Mode table + drift-gate equivalence | "Whether a hand edit of one row passes those gates, or whether the script has a mode for single-row re-pricing" | asked |
| `Ref`-only PR checks | "The PR must say Ref #12441 only" | asked |
| Follow-up #12780 | — | inferred. Justification: `wg-when-deferring-a-capability-create-a`. The CTO panel found the "never hand-edited" doctrine stale, and this PR is ruled row-only |

### Split Assessment

- Subsystems touched: 1 (`scripts/`)
- Planned files: 1 | Estimated changed lines: 2 (1 removed, 1 added)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: the diff outside plan, spec and learning artifacts is exactly this row.
      `git diff --numstat origin/main...HEAD -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings'`
      prints exactly `1	1	scripts/suite-durations.tsv`.
      `git diff origin/main...HEAD -- scripts/suite-durations.tsv | grep -E '^[-+][^-+]'` prints exactly
      `-plugins/soleur/test/cloudflare-readonly.test.sh	1261	floor` and
      `+plugins/soleur/test/cloudflare-readonly.test.sh	155229	measured`.
- [ ] AC2: no closing reference anywhere.
      This command prints `true`:
      `gh pr view 12778 --json title,body,closingIssuesReferences --jq '(.closingIssuesReferences|length==0) and (.body|test("Ref #12441")) and (((.title+"\n"+.body)|test("(?i)\\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\\b:?\\s+(jikig-ai/soleur)?#[0-9]+"))|not)'`
      This command prints `0`:
      `git log --format=%B origin/main..HEAD | grep -ciE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b:?\s+#[0-9]+'`
- [ ] AC3: the four local gates in §Gates exit 0, and the CI `test-scripts` legs are green on #12778.

## Test Scenarios

No new tests: this is a data row. The existing `check_durations` arms and Z3 cover it, through the
AC3 gates.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is a CI tooling data change (one scheduling weight).
There is no UI surface, no new runtime surface (the Observability section only names existing
signals) and no new infrastructure. There is no architectural
decision either: the row's value is the generator's own merge_group median, and the generator's
drift-gate verdict carries over.

## Sharp Edges

- **Byte-identity does not mean no textual conflict.** #12698 also rewrites the neighbouring rows
  `claude-code-action-auth`, `cloud-init-strip-helpers-mutation`,
  `codeql-main-alert-gate-workflow-wiring` and `codeql-main-alert-gate`, so a 3-way merge still
  overlaps this hunk. Byte-identity means #12698 can take its own side of that hunk and get the
  same value for this row. #12698 is already `CONFLICTING` and must regenerate anyway.
- **Process constraint:** no `gh`/`git push` command in this session targets #12698 or its head ref
  `feat-one-shot-11556-epic-ac-chain`. Its baseline `headRefOid` was 3f9923a5 at plan time; that is
  for reference only, since its owner may push to it.
- **Do not "fix" a red gate by running the generator with `--write` to the committed paths.** That
  rewrites 140 floor rows, the headers and 45 manifest legs, which breaks P2 and the ruling.
- **Local suite runs may wait on `dev-suite-mutex`** while the two foreign `test-all.sh` processes
  from collision-precheck are running. Waiting is expected. Do not kill another worktree's processes.

## References

- #12441 (P.2), #10479, epic #10205, #12515 (the merge that made the suite heavier), #12698 (full
  Lever-A re-price, not touched), #12778 (this PR), #12780 (docs follow-up).
- `scripts/regenerate-shard-manifest.py` (§INCREMENTAL REGEN, `drift_violations`, `drift_gate`).
- `plugins/soleur/test/scripts-shard-manifest.test.sh` (`check_durations`).
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`.
- `knowledge-base/project/specs/archive/20261110-130556-feat-one-shot-cf-analytics-reader-12441/tasks.md` (6.4, P.2).
- ADR-240, ADR-235, ADR-242.
