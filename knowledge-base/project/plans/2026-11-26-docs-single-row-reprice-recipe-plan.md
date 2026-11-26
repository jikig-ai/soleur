---
title: "docs(shards): one-row re-price recipe and the sanctioned one-row re-seat wording (#12780 docs half)"
date: 2026-11-26
slug: docs-single-row-reprice-recipe
branch: feat-one-shot-12780-single-row-reprice-docs
issue: 12780
closes: none
type: docs
lane: single-domain
domain: engineering
brand_survival_threshold: none
---

# docs(shards): one-row re-price recipe (#12780, docs half)

## Enhancement Summary

**Deepened on:** 2026-11-26 (inline, after the planning subagent stopped on a network error)
**Sections enhanced:** Scope Check, Observability (added), Phase 1.1 recipe, Phase 1.2, Phase 2 amendment, Research Insights, AC7
**Agents used:** soleur:engineering:review:architecture-strategist (scratch-verified review), soleur:engineering:cto (re-ruling)

### Key Improvements
1. Heavy-table variant stated once for steps 1, 3 and 4, with the measured consequence of omitting `--group heavy` (the gate passes a bad heavy edit; step 4 rewrites the light manifest).
2. Growth-ack path corrected: a hand-edited table can carry a generator-stamped `# growth-acked=` digest; CTO re-ruled to allow it when every violation names the re-seated row.
3. #12778 recast: it was a floor-to-measured flip, which the recipe now rules out; #12419 is the only precedent.
4. Citations fixed: `floor` rule from ADR-240, `estimate` from ADR-313 Consequences; "one further exception" beside the ADR-313 estimate seed.
5. Scope Check rebuilt in the Ask Mapping / Plan-Item Provenance / Split Assessment schema; Observability section added (test-all.sh is non-docs).

### New Considerations Discovered
- Step 4 refreshes only the manifest's headers; the table's `generated-from-runs` stops covering the re-seated row, so run ids live in the commit message.
- The drift-watch "same invocation" is the read-only `--drift-report`; the reworded sentence names the `--write` form.

## Overview

Docs- and comments-only half of #12780. The sharding runbook gains a recipe for re-pricing one
existing row of a committed shard durations table from CI `merge_group` medians. Four places that
say the table is never edited by hand are brought in line, so that a one-row re-seat to a CI
median that the drift gate accepts is a sanctioned edit: the runbook's "To re-price by hand"
passage, two ADR-242 sentences (superseded by name in a new amendment, per that ADR's own
convention), and one `scripts/test-all.sh` comment. Resolving a merge conflict by regeneration
stays absolute ("never hand-merge").

The code half of #12780 stays open and belongs to draft PR #12964: the `green_main_runs()` /
`--event merge_group` selector change in `scripts/regenerate-shard-manifest.py`, the die-on-empty
`--write` guard and its test, and the runbook's "Full regen" block. This plan edits none of them.
The PR body uses `Ref #12780`, never a closing keyword.

Spec lacks valid lane: — defaulted to single-domain from the plan's own scope (no spec.md exists
for this branch; the change touches one domain, engineering docs).

## Research Reconciliation — Spec vs. Codebase

| Claim (operator brief / issue #12780) | Reality (verified 2026-11-26) | Plan response |
|---|---|---|
| "never hand-edited" appears in three places | Four places. The fourth is ADR-242's 2026-11-04 pricing-ledger sentence: "`suite-durations.tsv` is a CI-leg table and is not edited by hand." | Supersede both ADR-242 sentences by name in one new amendment. |
| ADR-240 may carry the same wording | It does not. ADR-240 says "committed, regenerated on conflict, never hand-merged" (Context) and "resolves by regeneration, not hand-merge" (decision 5). ADR-242's parenthetical "(ADR-240: generated, never hand-edited)" misattributes the wording. | ADR-240 untouched (CTO ruling); the ADR-242 amendment corrects the citation. |
| "Edit the one row by hand" is the whole recipe | ADR-313 and runbook arm-split item 6 already sanction one other hand edit: seeding an arm price as `src=estimate`. Learning 2026-11-25 shows a hand-ADDED row breaks `infra-suite-registration` (no shard placement). | The recipe covers existing `src=measured` rows only, ms field only (CTO ruling). |
| Drift-gate confirm is optional | CTO ruling: mandatory. It is the only check on drift; `scripts-shard-manifest.test.sh` checks shape only. | Step 3 of the recipe is mandatory. |
| The seed path is the single-row tool (learning `workflow-patterns/2026-10-31-shard-reprice-checkpoint-mechanics.md` step 3) | #12778's planning (plan archive 20261115-233154) measured that `--durations seed --write` re-aggregates the whole table (140 floor rows plus headers rewritten, 45 manifest legs moved). Re-measured 2026-11-26 on the current table (20 floor rows) with a one-row edit: 4 floor rows re-derived (1800 → 1802 ms), 2 header lines, 14 legs moved. | Add a one-line dated pointer to that learning (inferred scope, see Scope Check). |
| A runbook `gh run list` command is free text | `plugins/soleur/test/components.test.ts` "unbounded gh enumerations carry an explicit sufficient bound (#8593)" scans this runbook; a consumed `gh run list` needs `-L`/`--limit` of at least 100 or `--paginate`. | The recipe's `gh run list` carries `-L 100`. |

## Research Insights

**Premise validation.** #12780 is OPEN (`gh issue view 12780`), titled "ci(shards): fix
green_main_runs to sample merge_group runs for ci.yml; document single-row re-price". Its body
and its 2026-11-15 comment were read; the docs half is unimplemented on `origin/main`. PR #12964
is an OPEN draft; its runbook hunks are lines 74-120 (the regen block, `--runs` prose, floor
rule) and a new Measured-history entry near line 480. This plan's edits sit at lines 152-187 and
at a new subsection inserted before `## The drift watch`, so they do not overlap. The collision
pre-check hit PR #13071, which is this branch's own draft PR (not a duplicate), and two
`test-all.sh` processes owned by an unrelated worktree.

**Property list.**

1. A reader can re-price one stale row of a committed durations table without moving any other
   row or leg.
2. A reader can tell, offline and before committing, whether their re-price is sanctioned.
3. Every statement in the repo about hand-editing these tables agrees with property 1, and none
   weakens "a merge conflict resolves by regeneration, never by hand-merge".
4. The ADR record says why the exception exists and cites ADR-240 accurately.

**Cut list.**

- A new generator mode (`--reprice <label>`) for property 1: cut. The existing generator already
  computes the median in scratch (`--timings-dir` emission) and gates the result (`--baseline-durations`);
  a new mode is a code change and the generator is in flight in #12964.
- Amending ADR-240 for property 4: cut. ADR-240 never said "never hand-edited"; the ADR-242
  amendment carries the corrected citation (CTO ruling).
- A new lint pinning the new wording for property 3: cut. The sweep is a one-time grep recorded as
  an acceptance criterion; no existing test pins any of these strings (`git grep` over `*.test.*`,
  `*.sh`, `*.py`, `*.ts`, `.github/` found only the `scripts/test-all.sh` comment itself).

**Verified generator behavior (scratch runs, 2026-11-26, tracked tree untouched).**
Scratch dir: one subdirectory of the session scratchpad.

- Median in scratch: `--timings-dir t1 --timings-dir t2 --timings-dir t3 --manifest <scratch legs>
  --durations-out <scratch fresh.tsv> --registered-file <labels> --write` exited 0; three synthetic
  runs timed one label at 200000 / 210000 / (999999 FAIL, 190000) ms and `fresh.tsv` carried
  `200000 measured`. The FAIL row was skipped and the median taken, as `merge_tsv` documents.
- Drift gate, downward re-price (250950 → 83650 ms on `.claude/hooks/git-commit-secret-scan.test.sh`):
  `--incremental --durations <edited> --baseline-durations <origin/main copy> --manifest <scratch>
  --durations-out <scratch> --write` exited 0, `0 moved`.
- Drift gate, 3x upward re-price (250950 → 752850 ms): exit 2, `weight drift refusal — ... per-suite
  drift ... (>1.5x AND >10000ms delta) ... re-run with --allow-growth`.
- Header-refresh pass simulated in scratch (`--incremental --durations <edited copy> --manifest
  <copy> --write`): "durations table ... already in parity — untouched"; the manifest diff was one
  header line (`generated-at`). `default-weight-ms` also moves when the measured median moves.
- Gate thresholds (`scripts/regenerate-shard-manifest.py`, `DRIFT_SUITE_FACTOR = 1.5`,
  `DRIFT_ABS_MS = 10000`, `DRIFT_TOTAL_PCT = 0.10`): a per-suite violation needs both factor and
  delta; total measured growth over 10 percent is a violation; a decrease never violates.
- CLI tokens checked with `--help`: `gh run list` has `-w/--workflow`, `-e/--event`,
  `-s/--status`, `-L/--limit`; `gh run download` has `-p/--pattern`, `-D/--dir`, `-R/--repo`.
  Generator flags `--incremental`, `--durations`, `--durations-out`, `--manifest`,
  `--baseline-durations`, `--allow-growth`, `--timings-dir`, `--group {light,heavy,infra}` are
  read from its `argparse` block. Artifact names: `suite-timings-scripts-<N>` (light),
  `suite-timings-scripts-heavy-<N>` (heavy), `suite-timings-infra-<N>` (infra).

**What "never hand-edited" was bounding (relaxed defense, enumerated).** Each threat the old
wording blocked, and what still blocks it after the exception:

| Threat | Still blocked by |
|---|---|
| An unmeasured or local price enters the table | Recipe step 1 (generator median over 3 to 5 green merge_group runs); the ADR-242 2026-11-04 sentence still bars local walls |
| Growth past the drift thresholds with no recorded ack | Step 3 refuses it; it proceeds only when every violation names the re-seated row, and then step 4's `--incremental --allow-growth --write` stamps a `# growth-acked=` digest scoped to exactly those violations (CTO re-ruling 2026-11-26); the in-tree step 4 write re-runs the gate against the merge-base |
| A new label without a shard placement | Out of bounds: new rows only via `--incremental --write` (learning 2026-11-25) |
| A `floor`/`estimate` row laundered into `measured` | Out of bounds: existing `src=measured` rows only (ADR-313) |
| A hand-resolved merge conflict | Unchanged: regenerate, never hand-merge (ADR-240 decision 5) |
| A price over the 600000 ms cap or a stale exemption row | Step 5 runs `test-all-corpus-weight-budget` and reconciles `suite-weight-exemptions.tsv` |
| Stale provenance headers | Step 4 in-tree `--incremental --durations` refresh |

**Precedents for the one-row re-seat.** PR #12419 (commit `404e4c626f`) re-seated
`ci-pr-affected-replay-a` 1033094 → 160004 ms from three green merge_group runs, run ids in the
commit message, headers refreshed by an `--incremental --durations` pass. PR #12778 (commit
`88d61dd0da`) is not a precedent for this recipe: it changed
`plugins/soleur/test/cloudflare-readonly.test.sh` from `1261 floor` to `155229 measured`, a
floor-to-measured flip the recipe puts out of bounds (architecture review, 2026-11-26).

**Consumers of the committed tables** (`grep -l 'suite-durations' scripts/*.test.sh
plugins/soleur/test/*.sh`): `scripts-shard-manifest`, `regenerate-shard-manifest`,
`test-all-corpus-weight-budget` (ADR-312: 600000 ms cap plus `scripts/suite-weight-exemptions.tsv`
ledger), `test-all-fast-tier-budget`, `test-all-weight-drift`, `test-all-affected`,
`ci-oracle-lane`, `secret-scan-smoke-gate`, `pr-overlap-preflight`, `test-pyramid-fixtures`.

**Institutional learnings applied.**

- `2026-11-15-byte-identical-row-is-not-a-clean-hunk-and-push-runs-carry-no-timings.md`: main push
  runs carry no suite timings (merge_group is the source); a prose pairing of a closing verb with
  `#12780` closed-parses on GitHub three times in one session. The PR body, commits, and this plan
  use `Ref #12780` only.
- `2026-11-25-i-fixed-the-gate-instead-of-the-workflow-and-shipped-an-empty-token.md` §2: a
  hand-added row reds `infra-suite-registration`; new rows go through `--incremental --write`.
- `2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`: any `scripts/test-all.sh` edit,
  comment-only included, degrades the local `--affected` gate to the full battery.
- `2026-10-30-audit-accept-rows-...`: before any committed write, run every consumer of
  `suite-durations`.
- `2026-10-31-anti-regrow-guards-totality-not-floors.md`: a `# growth-acked=` stamp is scoped to one
  violation set; a hand edit cannot carry one.

**CLAUDE.md / AGENTS conventions.** `cq-cite-content-anchor-not-line-number` (cite headings, not
line numbers, in the shipped text); `wg-use-closes-n-in-pr-body-not-title-to` (here inverted on
purpose: `Ref`, not `Closes`); `hr-never-run-commands-with-unbounded-output` (the recipe bounds its
`gh run list`).

## Scope Check

Sources: issue #12780 body ("Proposed change") and the operator's 2026-11-26 brief for this run
(scope ruled "Docs half only").

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add a \"re-price one row from merge_group medians\" recipe to the runbook" | Phase 1.1 | mapped |
| 2 | "Edit the one row by hand to the CI median." | Phase 1.1 step 2 | mapped |
| 3 | "Optionally confirm with the drift gate (`--baseline-durations`, writes to scratch only)." | Phase 1.1 step 3 (made required by CTO ruling) | mapped |
| 4 | "Keep \"never hand-merge\" absolute." | Phase 1.1 last paragraph; AC2 | mapped |
| 5 | "Reword \"never hand-edited\" to allow a one-row re-seat to a CI median that the drift gate accepts." | Phases 1.2, 2, 3; AC3, AC4, AC5, AC8 | mapped |
| 6 | "Amend ADR-242's wording through `soleur:architecture`." | Phase 2 (new amendment superseding by name) | mapped |
| 7 | "check whether ADR-240 carries the same \"never hand-edited\" wording" | Research Reconciliation row 2; AC6 (unchanged) | mapped |
| 8 | "any test/lint that pins these exact strings must be found and updated" | Research Insights cut list (none pin them); AC8 | mapped |
| 9 | "fix green_main_runs to sample merge_group runs for ci.yml" (issue title, code half) | none | descoped — justification: owner ruled "Docs half only" on 2026-11-26; the code half is held by draft PR #12964 and editing `scripts/regenerate-shard-manifest.py` here would conflict with it |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1.1 recipe subsection | "Add a \"re-price one row from merge_group medians\" recipe to the runbook" | asked |
| Phase 1.2 drift-watch passage reword | "the runbook's \"To re-price by hand\" passage" | asked |
| Phase 2 ADR-242 amendment, first sentence (#9814 parenthetical) | "Amend ADR-242's wording through `soleur:architecture`." | asked |
| Phase 2 ADR-242 amendment, second sentence (2026-11-04 ledger "not edited by hand") | none | inferred — justification: found by the operator-asked grep (ask 8); leaving it would contradict the new amendment in the same file |
| Phase 3 `scripts/test-all.sh` comment | "the scripts/test-all.sh run_suite comments saying \"suite-durations.tsv are NOT hand-edited\"" | asked |
| Phase 4 learning pointer | none | inferred — justification: that learning prescribes the seed path for a row re-price, which #12778's planning measured as a whole-table rewrite; a re-pricer following it reproduces the churn this recipe avoids |

### Split Assessment

- Subsystems touched: 3 — `knowledge-base/engineering/`, `knowledge-base/project/learnings/`, `scripts/`
- Planned files: 4 | Estimated changed lines: ~110
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — all items are prose in four files and share one review question ("does every statement agree with the recipe?")

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`: new subsection and one reworded passage.
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`: new amendment at end of file plus an `amended_by:` entry.
- `scripts/test-all.sh`: comment lines above `run_suite "scripts/check-web-host-escrow-config"` only.
- `knowledge-base/project/learnings/workflow-patterns/2026-10-31-shard-reprice-checkpoint-mechanics.md`: one dated pointer line.

## Files to Create

None (besides this plan, `tasks.md` and `decision-challenges.md` under the branch spec dir).

Not edited, by scope: `scripts/regenerate-shard-manifest.py`, every `suite-durations*.tsv` and
`suite-shard-legs*.tsv`, ADR-240, the runbook's "Full regen" block and `--runs` prose (#12964).

## Implementation Phases

### Phase 1: Runbook

**1.1 New subsection.** Insert after the paragraph that begins
"**Merge conflict on the TSV → regenerate, never hand-merge.**" and before `## The drift watch
(\`shard-balance-watch\`, #11564)`:

````markdown
### Re-price one row from merge_group medians (#12780)

Use this to re-price ONE existing `src=measured` row of a committed durations table
(`scripts/suite-durations.tsv`, `scripts/suite-durations-heavy.tsv`) to its CI `merge_group`
median. It is a sanctioned hand edit only when the drift gate accepts the edited table (step 3),
either outright or with a generator-stamped growth ack whose violations name only this row. Why
by hand: every pricing mode of the generator re-aggregates the
whole table and repacks the legs, and `--incremental` pins incumbent rows verbatim and fetches
no timings, so neither can re-price one row. On a one-row edit of the 2026-11-26 table the seed
path `--durations seed --write` also re-derived 4 floor rows, rewrote 2 header lines and moved 14
manifest legs; during #12441 P.2 planning, on an older table, it rewrote 140 floor rows and moved 45. Precedent: #12419 (replay-a, `measured` 1033094 → 160004 ms
from three green merge_group runs). Decision record: ADR-242, amendment 2026-11-26.

Out of bounds for this recipe, use the generator instead: adding a row (`--incremental --write`
tables it with its shard placement), upgrading a `floor` row to `measured` (ADR-240: `src=floor`
is never laundered into a measurement; see the floor rule above) or an `estimate` row (ADR-313
Consequences: only a real timings pass upgrades it), and any re-price the drift gate refuses.

**Heavy table.** The commands below are for the light table. For
`scripts/suite-durations-heavy.tsv`, change every step: download `-p 'suite-timings-scripts-heavy-*'`,
copy `scripts/suite-shard-legs-heavy.tsv` wherever the light legs file is copied, use
`scripts/suite-durations-heavy.tsv` wherever the light table is named (including the `git show`
in step 3), and pass `--group heavy` to every generator call in steps 1, 3 and 4. Leaving out
`--group heavy` is not harmless: step 3 then gates the light set and passes a heavy edit it
should refuse, and step 4 rewrites the committed light manifest and writes light labels into the
heavy table.

1. **Measure in scratch.** List green merge_group runs, download each run's timings into its own
   dir, and keep the newest 5 that received artifacts (at least 3; artifacts live 14 days). Then
   let the generator take the median, writing to scratch only, and read the one row (repeat
   `--timings-dir` once per kept run):

   ```bash
   WORK="$(mktemp -d)"
   gh run list -R jikig-ai/soleur --workflow ci.yml --event merge_group \
     --status success -L 100 --json databaseId --jq '.[].databaseId'
   # per run id, newest first:
   gh run download <id> -R jikig-ai/soleur -p 'suite-timings-scripts-*' -D "$WORK/r<id>"
   cp scripts/suite-shard-legs.tsv "$WORK/legs.tsv"
   python3 scripts/regenerate-shard-manifest.py \
     --timings-dir "$WORK/r<id1>" --timings-dir "$WORK/r<id2>" --timings-dir "$WORK/r<id3>" \
     --manifest "$WORK/legs.tsv" --durations-out "$WORK/fresh.tsv" --write
   grep -F "<label>" "$WORK/fresh.tsv"
   ```

   The generator's median skips `FAIL`, `KILLED`,
   `TRIPWIRE` and `skip=` rows and takes the max across legs within a run, so do not compute
   the median by hand.

2. **Edit the one row.** In the committed table, replace only the ms field of
   `<label><TAB><ms><TAB>measured` with the median from step 1. Leave the label, `src`, row
   order, headers and every other row as they are.

3. **Gate it (required, scratch only).**

   ```bash
   git show "$(git merge-base HEAD origin/main)":scripts/suite-durations.tsv > "$WORK/base.tsv"
   cp scripts/suite-shard-legs.tsv "$WORK/gate-legs.tsv"
   python3 scripts/regenerate-shard-manifest.py --incremental \
     --durations scripts/suite-durations.tsv --baseline-durations "$WORK/base.tsv" \
     --manifest "$WORK/gate-legs.tsv" --durations-out "$WORK/gate-out.tsv" --write
   ```

   Exit 0 with `0 moved` means accepted. The gate refuses (exit 2, `weight drift refusal`) a row
   that grows more than 1.5x and by more than 10000 ms, or a total measured growth above 10
   percent; a decrease never trips it. If it refuses, read each violation line it prints. Go on
   only if every line is about the row you re-seated (its `per-suite drift '<label>'` line, or
   the `total measured weight` line when only your row changed). Then re-run this step with
   `--allow-growth`, run step 4 as `--incremental --allow-growth --write` so the generator
   writes the `# growth-acked=` stamp into the in-tree table (never type the stamp by hand), and
   paste the violation lines into the commit message next to the run ids. If any line names
   another label, stop: this recipe does not acknowledge that growth, so use the full
   `--timings-dir … --write` regen instead.

4. **Refresh the manifest's provenance headers in the tree.**
   `python3 scripts/regenerate-shard-manifest.py --incremental --durations scripts/suite-durations.tsv --write`
   must print `already in parity — untouched` for the durations table and `0 moved`; the
   manifest diff is header lines only (`generated-at`, and `default-weight-ms` when the measured
   median moved). The table's own headers stay as they were, so its `generated-from-runs` no
   longer covers the re-seated row; that is why the run ids go in the commit message. This
   committed write runs the same drift gate against the merge-base.

5. **Verify and commit.** Run the table's consumers, at least
   `bash plugins/soleur/test/scripts-shard-manifest.test.sh`,
   `bash scripts/test-all-corpus-weight-budget.test.sh` and
   `bash scripts/test-all-fast-tier-budget.test.sh`
   (`grep -l 'suite-durations' scripts/*.test.sh plugins/soleur/test/*.sh` lists the rest). A
   price that crosses the 600000 ms per-suite cap, or makes a `scripts/suite-weight-exemptions.tsv`
   row stale, reconciles that ledger in the same commit (#12419 deleted one). Commit the row and
   the manifest header lines together, with the run ids and per-run values in the commit message.

This does not loosen the conflict rule above: a merge conflict on these rows is still resolved by
regeneration, never by hand-merge. A re-seat is a deliberate edit on your own branch.
````

**1.2 Reword the drift-watch passage.** In `## The drift watch (shard-balance-watch, #11564)`,
the paragraph beginning "Why `merge_group` and `--timings-dir`, not `--runs`:" currently says
"To re-price by hand: `gh run download <id> ... -D <dir>` per run, then the same `--timings-dir`
invocation — the probe's measurement path and the regen path are one generator." Replace that
sentence with:

> To re-price the whole table from the probe's population: `gh run download <id> -R
> jikig-ai/soleur -p 'suite-timings-scripts-*' -D <dir>` per run, then
> `--timings-dir <dir> … --write` (without `--drift-report`; the probe's measurement path and the
> regen path are one generator). That re-aggregates every row. To re-price one row, use
> [the one-row recipe](#re-price-one-row-from-merge_group-medians-12780) instead: a hand edit of
> that row, sanctioned only when the drift gate accepts it.

The rest of the paragraph (`--dry-run`, `--print-report`, retirement checklist) is unchanged.

### Phase 2: ADR-242 amendment

Conventions applied (CTO ruling, option B, the file's own pattern from the 2026-11-07 amendments):
append a new section at the end of the file, supersede by name, leave the old sentences as
written, and prepend one `amended_by:` entry. The soleur:architecture skill has no amend
sub-command; no new ADR ordinal is minted, so the ADR-ordinal gate is not involved.

**2.1 Frontmatter.** Prepend to `amended_by:` (first list item):

```yaml
  - "#12780 (2026-11-26) — a one-row re-seat of an existing src=measured row to its CI merge_group median, accepted by the drift gate (outright, or with a generator-stamped growth ack whose violations name only that row), is a sanctioned hand edit of a committed durations table; corrects the ADR-240 citation (never hand-merged, not never hand-edited); see ## Amendment — 2026-11-26 (#12780)"
```

**2.2 Section.** Append at the end of the file:

````markdown
## Amendment — 2026-11-26 (#12780)

Supersedes, by name, two sentences that stay as written. The 2026-10-11 (#9814) amendment says
the drift detector's "committed weight row is written only by `regenerate-shard-manifest.py
--incremental --write` (ADR-240: generated, never hand-edited)". The 2026-11-04 (#12013, #12025)
pricing ledger says "`suite-durations.tsv` is a CI-leg table and is not edited by hand." Both now
carry one further exception, beside the `src=estimate` arm seed that ADR-313 already sanctions:
re-seating one existing `src=measured` row to its CI `merge_group` median is a sanctioned hand
edit when the drift gate accepts the edited table, outright or with a generator-stamped growth
ack whose violations name only that row. The first sentence's
citation is also corrected. ADR-240 says a generated table is regenerated on conflict, never
hand-merged (decision 5; its Context restating ADR-235's artifact rule); it does not say "never
hand-edited". The 2026-11-04 sentence still holds for what it described: local standalone
walls are not CI-leg medians and never go into the table.

What stays absolute. A merge conflict on a shard TSV is resolved by regeneration, never by
hand-merge (ADR-240 decision 5). A new row is written only by the generator: `--incremental
--write` tables a new label at the floor together with its shard placement. A `floor` row
becomes `measured` only through a real timings pass (ADR-240: `src=floor` is never laundered into
a measurement), and so does an `estimate` row (ADR-313, Consequences).

Why the exception exists. Every pricing mode of `regenerate-shard-manifest.py` re-aggregates the
whole table and repacks the legs. On scratch copies during #12441 P.2 planning, the seed path
`--durations seed --write` rewrote 140 floor rows and the headers and moved 45 manifest legs;
re-measured on 2026-11-26 with a one-row edit of the current table (20 floor rows), it still
re-derived 4 floor rows, rewrote 2 header lines and moved 14 manifest legs. `--incremental` pins
incumbent rows verbatim and fetches no timings, so it cannot re-price a row. A stale price
therefore had no generator path that leaves the rest of the table alone. #12419 already took the
hand path for a `measured` row (replay-a, 1033094 → 160004 ms from three green merge_group runs).
#12778 hand-edited `cloudflare-readonly` from `floor` 1261 to `measured` 155229 ms; that
floor-to-measured flip is what this amendment now rules out.

The bar is the drift gate, run before the row is committed against the merge-base table
(`--baseline-durations`, writing to scratch only). A re-seat that trips the gate may still go
ahead when every violation it prints names the re-seated row: the in-tree `--incremental
--allow-growth --write` then stamps a `# growth-acked=` header scoped to the digest of exactly
those violations, so the acknowledgement is recorded, visible in the diff, and cannot carry over
to different drift. A violation naming any other label stops the recipe and routes to the full
`--timings-dir` regen. The procedure is the "Re-price one row from merge_group medians" recipe in
`knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`: measure in scratch
with the generator, edit the row, gate it, refresh the headers with an in-tree `--incremental
--durations` pass, and run the table's consumers.

Alternatives added by this amendment:

| Alternative | Why not |
|---|---|
| Keep "never hand-edited" and re-price through a full regeneration | Re-aggregates every row and moves unrelated legs (45 on the measured run); sibling PRs then conflict on rows they never meant to change. |
| Refuse every re-seat that trips the gate and send it to the full regen | The full regen re-derives unrelated rows and moves legs; the incremental write records the same scoped acknowledgement with a one-row diff. |
| A generator mode that re-prices one label | Not needed: the scratch median plus the gate already verify a one-row edit offline, and a new mode is a code change to a generator that #12964 is changing now. |
| Let a hand re-seat upgrade a `floor` or `estimate` row to `measured` | Contradicts ADR-240 (`src=floor` is never laundered into a measurement) and ADR-313 (an estimate upgrades only through a real timings pass); a flipped row would enter the measured-only floor median and drift accounting without one. |
````

### Phase 3: `scripts/test-all.sh` comment

Above `run_suite "scripts/check-web-host-escrow-config"`, the comment currently ends:

```bash
  # Registered explicitly: scripts/*.test.sh is NOT auto-globbed (the #5417 orphan class). The
  # generated suite-shard-legs.tsv / suite-durations.tsv are NOT hand-edited.
```

Replace those two lines with:

```bash
  # Registered explicitly: scripts/*.test.sh is NOT auto-globbed (the #5417 orphan class). The
  # generated suite-shard-legs.tsv / suite-durations.tsv are regenerated, never hand-merged; the
  # one hand edit sanctioned for an existing measured row is a one-row re-seat to its CI
  # merge_group median that the drift gate accepts (the test-scripts sharding runbook, #12780).
```

Comment lines only. No `knowledge-base/` path in the comment, so the kb-consumer scan
(`scripts/test-affected-kb-consumers.test.sh`) sees no new reader edge. Expect the local
`--affected` gate to fall back to the full battery for this branch (`runner-changed`), and the
PR-gated batteries to arm on the PR's CI run (`PR_GATE_MACHINERY_PATHS` lists `scripts/test-all.sh`).

### Phase 4: learning pointer

In `knowledge-base/project/learnings/workflow-patterns/2026-10-31-shard-reprice-checkpoint-mechanics.md`,
directly under step 3 of `## Solution`, add one indented line:

```markdown
   *Update 2026-11-26 (#12780):* the seed path re-aggregates the whole table and repacks the legs
   (a one-row seed edit on 2026-11-26 re-derived 4 floor rows, rewrote 2 header lines and moved 14
   manifest legs). To re-price one row, use the runbook's "Re-price one row from merge_group
   medians" recipe.
```

### Phase 5: Verify

Run the acceptance criteria below. Then `bash scripts/markdown-lint.sh` on the runbook and the
ADR (the learning sits under `knowledge-base/project/`, which `.markdownlintignore` excludes),
`bash -n scripts/test-all.sh`, and
`bun test plugins/soleur/test/components.test.ts` (the whole file: that is the gate's own
invocation; it includes the "unbounded gh enumerations carry an explicit sufficient bound (#8593)"
scan over this runbook).

## Open Code-Review Overlap

1 open scope-out touches these files: #7942 (two `*.mutation.sh` batteries in
`plugins/soleur/test/` run in no gate) names `scripts/test-all.sh`. Disposition: **Acknowledge**.
It concerns suite registration, not the sharding comment this plan rewords, and needs its own
registration change. No open code-review issue names the runbook, ADR-242, the learning, or the
durations tables.

## User-Brand Impact

**If this lands broken, the user experiences:** an agent or the founder follows a runbook that
contradicts ADR-242 or the runner's comment, and either refuses a legitimate one-row re-price
(staying on a stale shard price, a slower or skewed `test` check) or hand-edits a row without the
drift gate and lets an unmeasured price into the committed table.

**If this leaks, the user's data / workflow / money is exposed via:** no data path. The change is
prose in four files; no credentials, workflows, or production surfaces are touched.

**Brand-survival threshold:** none

threshold: none, reason: docs and comment wording for an internal CI table; no user data, auth, payment, or production path is touched.

## Observability

The only non-docs file is `scripts/test-all.sh`, and its diff is comment lines only (AC5), so no
runtime signal, error path or log line changes. The fields below record that and name the one
check that shows the shipped wording.

liveness_signal:
  what: the runbook carries the one-row recipe heading on main after merge
  where: knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md
error_reporting:
  channel: none added; the diff adds no executable line (AC5 pins comment-only), so no new error path exists to report
failure_modes:
  - mode: a reader follows the stale "never hand-edited" wording and refuses a sanctioned re-seat
    detected_by: AC8 wording sweep (git grep over scripts/ and knowledge-base/engineering/)
  - mode: a recipe command drifts from the generator's real behavior
    detected_by: AC7 scratch drill and the existing regenerate-shard-manifest.test.sh drift-gate cases in CI
logs:
  stream: none added; CI logs of the existing suites are unchanged
discoverability_test:
  command: grep -c '^### Re-price one row from merge_group medians (#12780)$' knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md
  expected_output: "1"

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-242 (no new ordinal): new `## Amendment — 2026-11-26 (#12780)` that supersedes by name
the 2026-10-11 parenthetical and the 2026-11-04 ledger sentence, plus an `amended_by:` entry
(Phase 2). ADR-240 is unchanged (CTO ruling). ADR-313's estimate-seed rule is cited, not changed.

### C4 views

No C4 impact. Checked against `knowledge-base/engineering/architecture/diagrams/model.c4`,
`views.c4` and `spec.c4`: the change adds no external human actor, no external system or vendor,
no container or data store, and no actor-to-surface access relationship. It narrows a rule about
who may edit one committed CI data file; the only actors involved (the operator, agents, GitHub
Actions merge-queue runs) and the CI repository container are already modeled, and no model
element description mentions shard durations tables. `bash plugins/soleur/test/c4-count-parity.test.sh`:
13 passed, 0 failed (run 2026-11-26).

### Sequencing

None. The amendment describes behavior that is already true on `main` (the generator flags exist
and two precedents used the path).

## Acceptance Criteria

Let `RB=knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`,
`ADR=knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`,
`MB=$(git merge-base HEAD origin/main)`.

- [x] AC1: `grep -c '^### Re-price one row from merge_group medians (#12780)$' "$RB"` prints `1`,
      and the section lists five numbered steps whose step 3 contains `--baseline-durations` and
      the word `required`.
- [x] AC2: the conflict rule is intact: `grep -c 'Merge conflict on the TSV → regenerate, never hand-merge' "$RB"` prints `1`,
      and the new section's last paragraph contains `never by hand-merge`.
- [x] AC3: `grep -c 'To re-price by hand:' "$RB"` prints `0`, and
      `grep -c '(#re-price-one-row-from-merge_group-medians-12780)' "$RB"` prints `1`.
- [x] AC4: `grep -c '^## Amendment — 2026-11-26 (#12780)$' "$ADR"` prints `1`; the first
      `amended_by:` list item starts with `"#12780 (2026-11-26)`; the ADR diff is additions only,
      so both superseded sentences stay as written:
      `git diff "$MB" -- "$ADR" | grep -cE '^-[^-]'` prints `0`. (Each superseded sentence now
      occurs twice in the file: the original and the amendment's quotation of it.)
- [x] AC5: `grep -c 'suite-durations.tsv are NOT hand-edited' scripts/test-all.sh` prints `0`;
      `bash -n scripts/test-all.sh` exits 0; the runner diff is comment-only:
      `git diff "$MB" -- scripts/test-all.sh | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*#'` prints nothing.
- [x] AC6: out-of-scope files unchanged:
      `git diff --quiet "$MB" -- scripts/regenerate-shard-manifest.py scripts/suite-durations.tsv scripts/suite-durations-heavy.tsv scripts/suite-shard-legs.tsv scripts/suite-shard-legs-heavy.tsv apps/web-platform/infra/suite-durations.tsv apps/web-platform/infra/suite-shard-legs.tsv knowledge-base/engineering/architecture/decisions/ADR-240-shard-assignment-is-checked-in-derived-data.md`
      exits 0.
- [x] AC7: the recipe's commands still behave as documented, re-run in a scratch dir with a
      positive and a negative control (no tracked file changes, `git status --short` lists only
      this branch's docs): a downward one-row edit through the step 3 command exits 0 with
      `0 moved`; a 3x upward edit of the same row exits 2 and prints `weight drift refusal`; the same
      3x edit re-run with `--allow-growth` exits 0, prints `violation(s) acknowledged` and writes a
      `# growth-acked=` line into the scratch output; a heavy-table row raised past the thresholds
      exits 2 only when `--group heavy` is passed (the recipe's heavy note).
- [x] AC8: wording sweep. Every remaining hit is inside ADR-242 (the originals kept as written
      plus the amendment quoting them):
      `git grep -n -E 'never hand-edited|NOT hand-edited|not edited by hand' -- scripts/ knowledge-base/engineering/ | grep -E 'durations|ADR-240' | grep -v '^knowledge-base/engineering/architecture/decisions/ADR-242-'`
      prints nothing. Positive control first (verified 2026-11-26): the first two stages run
      against `origin/main` (`git grep -n -E '…' origin/main -- scripts/ knowledge-base/engineering/ | grep -E 'durations|ADR-240'`)
      print three lines: ADR-242 at the #9814 parenthetical, ADR-242 at the #12025 ledger
      sentence, and `scripts/test-all.sh:5975`. The pipeline is live if the branch version drops
      exactly the `scripts/test-all.sh` line.
- [x] AC9: `bun test plugins/soleur/test/components.test.ts` passes
      (the recipe's `gh run list` carries `-L 100`); `bash scripts/markdown-lint.sh "$RB" "$ADR"` exits 0 and does not print `nothing to lint`
      (both files are in lint scope; the learning is excluded by `.markdownlintignore`).
- [ ] AC10: no closing reference to #12780 anywhere the PR carries:
      `gh pr view --json body --jq .body | grep -inE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]*:?[[:space:]]+#12780'`
      and `git log "$MB"..HEAD --format=%B | grep -inE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]*:?[[:space:]]+#12780'`
      both print nothing, and the PR body contains `Ref #12780`.
- [x] AC11: `bash plugins/soleur/test/c4-count-parity.test.sh` reports `Failed: 0`.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled eight technical forks (recorded in
`knowledge-base/project/specs/feat-one-shot-12780-single-row-reprice-docs/decision-challenges.md`):
gate must accept the edit, outright or with a generator-stamped ack whose violations name only the re-seated row (re-ruled 2026-11-26 after the architecture review); existing `src=measured` rows only; median from the
generator in scratch over 3 to 5 merge_group runs; ADR-242 amended by a new section that
supersedes by name; ADR-240 untouched; drift-gate step mandatory; in-tree header refresh
included; `scripts/test-all.sh` comment reworded despite the one-time full local battery.

No Product/UX gate: no UI surface in Files to Edit (docs and one shell comment).

## Test Scenarios

Docs-only: no new test. The behavioral claims in the recipe are pinned by AC7 (scratch drill,
positive and negative control) and by the existing `regenerate-shard-manifest.test.sh` drift-gate
cases. The string sweep is AC8, with a positive control on `origin/main`.

## Sharp Edges

- A closing verb next to `#12780` in the PR body, a commit message, or this plan's archived
  copy closes the issue on merge while its code half is open. Write `Ref #12780`; AC10 greps for it.
- The runbook recipe must not touch the "Full regen" block or the `--runs` prose (PR #12964 owns
  them); keep edits at the conflict paragraph, the new subsection, and the drift-watch passage.
- `gh run list` in the runbook needs `-L 100` (or more) or the #8593 enumeration scan in
  `components.test.ts` reds on this file.
- Editing `scripts/test-all.sh` makes the local `--affected` gate run the full battery and arms
  the PR-gated batteries in CI. That is expected; do not "fix" it by reverting the comment.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6.
- The ADR-242 amendment cites the runbook heading, not line numbers (`cq-cite-content-anchor-not-line-number`).

## Non-Goals

- The `green_main_runs()` / `--event merge_group` code change, the die-on-empty `--write` guard
  and its test, and the "Full regen" runbook block (all PR #12964).
- Re-pricing any actual row (for example replay-b/-c under #11679).
- A generator mode for one-row re-pricing (rejected in the ADR amendment, not deferred).
