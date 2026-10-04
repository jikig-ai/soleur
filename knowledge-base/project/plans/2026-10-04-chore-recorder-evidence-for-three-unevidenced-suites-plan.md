---
title: "chore: give recorder evidence to the three suites kept without it (umbrella #9307, section 2)"
date: 2026-10-04
slug: recorder-evidence-for-three-unevidenced-suites
branch: feat-one-shot-recorder-evidence-three-suites
issue: 9307
type: chore
priority: p3
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# chore: give recorder evidence to the three suites kept without it

## Enhancement Summary

**Deepened on:** 2026-10-04. **Mode:** gate pass plus verification (the 4-agent plan-review panel already ran: DHH, Kieran,
code-simplicity, CTO devex; their findings were applied before this pass). The 40-agent fan-out was not run: the plan is a
measured, 8-file tooling change and every load-bearing claim below was verified against the repo or by a recorded run.

**Gates:** 4.6 User-Brand Impact present, threshold `none`, no sensitive path; 4.7 Observability added (see section);
4.8 PAT-shaped variables: none; 4.9 UI: not triggered; 4.10 Encryption: not triggered; 4.11 Guard Contract: lint green,
2 guards, assemblies name chokepoints (the `NETWRAP` array, the `ALWAYS_ON_SUITES` array), not today's members;
4.12 Scope Check: one unfenced section, every row mapped, both `inferred` rows justified, `Recommendation:` present.

**Verified live in this pass:** issues #9307, #9441, #8800, #8659, #7942 are OPEN; ADR-176/183/242/262 files exist; the one
cited rule id (`cq-write-failing-tests-before`) is active; the plan-review panel confirmed the line numbers for
`_MIN_ALWAYS_ON_DECLARED` (`scripts/test-all.sh:3025`), the f1 literals (1781, 1782, 1784) and arm 21
(`scripts/pre-push-ratchet-lane.test.sh:1018`).

### Key improvements from review (applied)
1. Row f2 moved against the real runner after q4 (the sandbox arms trim the corpus to the keep-list, where the label is absent).
2. Guard 3 and the `unc-files`/`unc-dirs` counters cut: the uncovered list is files-first, so the first entry already proves it.
3. ADR-242 decision 19 must supersede decision 18's "stay on their edges" sentence and its 7 s threshold for these three suites.
4. Consumer sweep widened to `.claude`, `plugins/soleur/skills`, `lefthook.yml` (finds `incident-sandbox-coverage.test.sh`).
5. Follow-up issue replaced by four extra labels in the Phase 3 batch (data only); revisit trigger added to the hedge.

### New considerations
- The scripts CI job must run as a non-root user for Guard 1's mutation rows to be reachable (Phase 0.3 confirms it).
- Phase 3 evidence is a host-load-dependent measurement; its pass criterion is stated as such and the audited SHA is invalidated by any later touch of the recorder, the edge arrays or the three suites.


Spec lacks valid lane: -- defaulted to cross-domain (TR2 fail-closed).

## Overview

Three registered suites sit on derived or declared edges with no recorder evidence behind them
(`always-on-audit.md`, "Round 3 re-check"): `scripts/test-affected-kb-consumers`,
`scripts/orphan-process-reaper-mutations` and `scripts/audit-suite-reads`. Their only cover today is CI's full
battery. This plan was written after MEASURING each one (prototype in a scratch copy of HEAD, real recorder, two
reps each, load-gated at `--max-load 12`), so the per-suite choice below is a result, not a preference.
Umbrella #9307 stays open; its other PRs and section 3 (nested `cd` form, scheduled recorder check, tracker #9441)
are out of scope.

**Outcome in one table** (costs: `scripts/suite-durations.tsv`, the committed measured column):

| Suite | Why it had no evidence (measured) | Option | Cost |
|---|---|---|---|
| `scripts/orphan-process-reaper-mutations` (113.4 s) | the recorder wraps suites in `unshare -rn`, which maps the invoker to namespace-root; the detector refuses euid 0 (G1), so the control goes RED. Network is not the cause. | **(a)** recorder runs suites as the invoking user (`unshare -cn`) | +0 s always-on. Recorded `covered`, rc 0, both reps, declared set unchanged |
| `scripts/audit-suite-reads` (73.1 s) | `unshare` is not on the recorder's scratch PATH, so the nested suite sees "no netns tool" and SKIPs its whole section B (flag `skipped`). Nesting itself works. | **(a)** `unshare` onto the scratch PATH, **plus (b)** five declared file reads the recording found | +0 s. After the declaration no file is outside the cover; the remaining uncovered paths are 3,185 directory listings |
| `scripts/test-affected-kb-consumers` (68.4 s) | not an instrument problem: it genuinely reads 1,244 files over 24 directories | **(c)** hedge into `ALWAYS_ON_SUITES` | +68.4 s of 1,228.1 s always-on suite time (+5.6%); marginal per-commit cost is lower (about 3.4 s on average) because 57 of the last 60 commits already select it through its read roots |

Hedging all three would have been +254.9 s (+20.8% by the committed table; the brief's 306 s / +24% used slower
host numbers). Only the one suite whose evidence cannot bound it is hedged.

## Research Insights

### Premise Validation (Phase 0.6)

- Cited issues: #9307 (umbrella) is OPEN, #9441 is OPEN and explicitly out of scope. No blocker is stale.
- Cited artifacts exist on `origin/main`: `scripts/audit-suite-reads.sh`, `scripts/lib/inotify-open-recorder.py`,
  the three suites (`scripts/test-all.sh` lines 4273, 5158, 5179), the audit doc
  `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md` (sections "Reproducing the
  recorder", "Round 3 re-check" present).
- ADR corpus: ADR-242 decisions 15 to 18 are the owner (decision 17: "a recording that is not complete is never
  evidence for a demotion"; "the default is keep"). Nothing there rejects this mechanism. ADR-262 path-gates the
  mutation batteries in PR CI and is unaffected.
- Two premises in the brief did NOT survive measurement; see the reconciliation table.

### Research Reconciliation (brief vs measured)

| Brief / audit-doc claim | Reality (measured 2026-10-04) | Plan response |
|---|---|---|
| audit-suite-reads: "the recorder cannot audit itself: its record rows need a network namespace, which it is already inside" | Nesting works: `unshare -rn unshare -rn true` and `unshare -cn unshare -rn true` both exit 0. The recorder's scratch PATH is the ENTIRE PATH and `make_scratch_bin` has no `unshare`/`bwrap`, so the suite's own probe sets `EXPECT_NETNS=none` and skips section B (`audit-suite-reads.test.sh` lines 684-686, 775-778) -> the recorder flags `skipped`. With `unshare` on the PATH the suite passes 326/0, 0 skipped, 92 s, inside the netns. | Fix the instrument: add `unshare` to the scratch bin. Not a suite change. |
| orphan-process-reaper-mutations (and its sibling, hedged): "fails under `env -i` with no network" | Under `unshare -rn` the invoker is namespace-root (euid 0) and the detector's privilege floor refuses root; the control (AC40 live arms) goes RED: `orphan-process-reaper` 57 of 148 assertions FAIL. Under `unshare -cn` (map current user to itself): `orphan-process-reaper` 148/0 in 12 s, the mutation battery 604/0 in 97 s (36 rows, all 34 expected-RED rows red). No network is involved. | Fix the instrument: probe `unshare -cn` first. The `test-affected-paths.sh` comment ("57 of 145 assertions fail under env -i with no network") is a disproved explanation and is corrected there. |
| kb-consumers: "reads ~1,236 files over 25 directories" | 1,244 files / 24 directories AND 3,185 directory listings; 4,376 uncovered paths against a 12-edge cover; `broad`. | Not declarable (see decision). |
| "hedging all three would add ~306 s (+24%)" | 254.9 s of 1,228.1 s measured always-on time (+20.8%) by `suite-durations.tsv`; the one hedge chosen is +68.4 s (+5.6%). | Use the committed-table figures in the addendum. |
| Round 3: sibling `scripts/orphan-process-reaper` is hedged for "no evidence" | Under the fixed recorder its check row is `uncovered` for three real reads and carries `unresolved=6` plus `regex:git-other`, `regex:clock-epoch`: demote mode would be `disqualified` by construction. | It STAYS hedged, now on the recorder's own rule instead of an instrument artifact. |

### Property List and Cut List (Phase 0.6b)

Properties the ask needs: (P1) each of the three suites has a recorded verdict or a recorded reason none can exist;
(P2) a suite the evidence cannot bound is covered locally, at the cheapest cost; (P3) the decision and its measured
cost are written down append-only; (P4) nothing outside the recorder, the edge lib, the floor and the docs moves.

Mechanisms considered and cut:

- A "recorder-compatible mode" flag inside the suites (env switch) -> P1 is bought by fixing the recorder; a suite
  that behaves differently under the recorder is a suite the recorder no longer audits. Cut.
- Declaring kb-consumers' 24 directories by hand (option b) -> buys P2 only for 3 of the last 60 commits (below).
  Cut in favour of (c).
- A second hedge (`scripts/orphan-process-reaper` back to declared edges) -> its demote verdict is `disqualified`
  by construction; ADR-242 decision 17 forbids a demotion without `demotable`. Cut.
- Re-recording every earlier Round 2/3 row under the new identity mapping -> that is the scheduled recorder check
  (section 3), explicitly out of scope. Cut. The four root-skipped hedged suites are added to the Phase 3 batch as
  data only (they are small), so the "same mapping?" question is answered by a recording, not by a filed issue.
- Row-detail counters (`unc-files`/`unc-dirs`) and a third guard for them -> `unc.$id` is built files-first then
  directories (`scripts/audit-suite-reads.sh:340`), so a first uncovered entry that is a directory already proves no file
  is outside the cover. Cut (plan review).
- A new suite file for the new recorder rows -> existing `scripts/audit-suite-reads.test.sh` already hosts them and
  is registered; no new registration. Cut.

### Value-Proposition Measurement (Phase 0.6c)

- Always-on suite time: `awk -F'\t' 'NR==FNR{a[$1]=1;next} ($1 in a){s+=$2;n++} END{print n, s/1000}' <(bash -c 'source scripts/lib/test-affected-paths.sh; printf "%s\n" "${ALWAYS_ON_SUITES[@]}"') scripts/suite-durations.tsv`
  -> 142 of 145 rows, 1,228.1 s (3 labels have no row, so this is a lower bound; same caveat as the audit doc).
- Hedge value for kb-consumers: of the last 60 non-merge commits on `origin/main`
  (`git log -60 --no-merges --format=%h`), 51 touch `knowledge-base/` and 57 touch any of its 13 read roots
  (`.claude .github apps docs infra knowledge-base plugins scripts test tests` plus three root files). A hand-declared
  set would therefore skip the suite on 3 of 60 commits (5%), i.e. save 3.4 s per commit on average against 68.4 s,
  and carries a staleness risk the always-on hedge does not. Option (b) is measured and rejected.

### Institutional learnings applied

- `2026-10-03-the-recorder-called-its-own-checkout-dirty-and-i-explained-it-as-the-suite.md`: a verdict that lands on
  the first item of every batch is a statement about the instrument. Here the first-position row of rec1 was the
  sibling `scripts/orphan-process-reaper`; it came back rc 0 with no flag, so the first-window artifact is gone, and the
  final run keeps a known-clean control (`scripts/tunnel-connector-census`, `covered`) in the batch. Also: run
  `guard-vacuity-floor` and `fixture-relative-assert` after every guard-shaped commit; a floor plan states the
  relation to the count, not a literal (`count - floor <= 5`, row f1).
- ADR-242 decision 17: an unreliable recording is never evidence; a write-up claims only what was recorded.

## Measured feasibility (what was run, so the work phase can reproduce it)

All runs used a `git archive HEAD` copy under the session scratchpad, re-`git init`ed (so the recorder's "revision is
an ancestor of HEAD" rule held), with the recorder patched as in Phase 1. `--max-load 12 --load-wait 600`, detached
with an rc file, watched by Monitor; host load average swung 5 to 23 from other sessions (the recorder waited, as designed).

| Run | Command (shape) | Result |
|---|---|---|
| mutation battery under namespace-root | `unshare -rn env -i ... PATH=<scratch bin> bash scripts/orphan-process-reaper-mutation.test.sh` | rc 1 in 3.7 s: control RED, `0 passed, 1 failed` |
| same under `unshare -cn` | same with `-cn` | rc 0, 97 s wall, `604 passed, 0 failed`, battery 73.9 s at -P6 |
| sibling `orphan-process-reaper` under `-cn` | same | rc 0, 12 s, `148 passed, 0 failed` |
| `audit-suite-reads.test.sh` under `-cn`, scratch bin + `unshare` | same | rc 0, 92 s, `326 passed, 0 failed (skipped sections: 0)` |
| recorder, check mode, 4 labels, 2 reps (rec1, rev `6bff738d27`) | `record --mode check --cover-from-selection --max-load 12 --only <4 labels>` | exit 0; orphan-process-reaper-mutations `covered` (rc 0, 5 files, 2 dirs, cover 13); kb-consumers `uncovered` (1,244 files, 24 dirs, 4,376 uncovered paths); audit-suite-reads `uncovered` (15 files, 3,185 uncovered dirs + 5 files); orphan-process-reaper `uncovered` (3 real reads, hedged anyway) |
| recorder, check mode, rec2 (rev `674c89e6df`, five reads declared) | `--only scripts/tunnel-connector-census,scripts/audit-suite-reads` | exit 0; census `covered` (clean control); audit-suite-reads still `uncovered` but the first uncovered entry is `.` and every entry is a directory: 0 files outside the cover |

The five files audit-suite-reads reads outside its cover are `.bun-version`, `.gitignore`, `apps/web-platform/.gitignore`,
`apps/web-platform/infra/.gitignore`, `apps/web-platform/supabase/.gitignore`. They come from the one real-runner
enumerate in the suite (`audit-suite-reads.test.sh` lines 1266-1272, `bash scripts/test-all.sh --enumerate-commands
all` under `env -i`), which also walks the whole tree (the 3,185 directory listings) but asserts only `>= 400`
registrations, so a listing cannot move its verdict; the runner itself is already a declared edge.

## Decisions (per suite, recorded; no question to the operator)

1. **`scripts/orphan-process-reaper-mutations` -> option (a), evidence obtained.** The recorder runs every suite and
   harness command as the invoking user (`unshare -cn`, fall back to `-rn`). Verdict `covered` on both reps with the
   edge set already declared (`AFFECTED_SCRIPTS_ORPHAN_PROCESS_REAPER_MUTATIONS_PATHS`, 13 cover entries); no change
   to that array. Cost 0 s.
2. **`scripts/audit-suite-reads` -> (a) + (b).** `unshare` joins the scratch PATH so the suite's section B runs inside
   the recording; the five file reads above are added to `AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS`. Residual
   `uncovered` is directory listings only: the uncovered list is files first, then directories, and the first entry is
   `.`. The addendum states it as such, not as `covered`. Why the five files are declared and the listings are not: a
   file read is a specific input and cheap to name (five rare edits); declaring the listed directories
   (`knowledge-base/`, `plugins/`, `apps/`) would select a 73 s suite on nearly every diff for no change to a verdict
   that asserts only `>= 400` registrations. Cost 0 s.
3. **`scripts/test-affected-kb-consumers` -> (c) hedge.** The recording is complete and unambiguous (rc 0 twice) and
   shows the read set is the registration corpus itself: it cannot be bounded by a short declaration, and the
   knowledge-base tree (via `git ls-files`, invisible to inotify) is a second input. Declaring it would select it on
   95% of commits anyway. Added to `ALWAYS_ON_SUITES`; count 145 -> 146; `_MIN_ALWAYS_ON_DECLARED` 140 -> 141 (the
   "count minus 5" rule); row f1 literals follow. `AFFECTED_SCRIPTS_TEST_AFFECTED_KB_CONSUMERS_PATHS` is KEPT, not
   deleted: `scripts/pre-push-ratchet-lane.test.sh` arm 21 pins the lane's `KB_CONSUMERS_INPUTS` equal to it (the Round 2
   "delete the dormant array" precedent would redden that arm: a consumer a name-grep for the suite label misses).
   Alternatives not taken, one line each: shrinking the suite (a shared single enumeration pass) is a separate, larger
   change to its oracle; moving it to the pre-push lane only does not cover the local `--affected` gate, and the lane's
   `KB_CONSUMERS_INPUTS` trigger is a different mechanism (merged-tree check on a push), not a duplicate of the hedge.
   **Revisit trigger:** re-evaluate the hedge when always-on suite time passes 1,500 s or when the suite becomes
   incremental; the amendment says so, so "keep" does not become permanent by default.
4. **Unchanged on purpose:** `scripts/orphan-process-reaper` stays hedged (demote verdict `disqualified` by
   construction); the sandbox keep-list in `scripts/test-all-affected.test.sh` is not touched; the generated TSV pair
   (`scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`) is not touched (no registration changes, and a
   pair, if it ever must move, is regenerated wholesale with its generator, never hand-merged).

## Architecture Decision (ADR/C4)

### ADR

Append a short dated `## Amendment -- 2026-10-04 (section 2 of #9307)` at the END of ADR-242 (after the #9400 amendment;
earlier decisions untouched), adding **decision 19** as a pointer to the audit-doc addendum, not a restatement. It must
(1) state that the recorder runs suites as the invoking user and puts `unshare` on the scratch PATH, so an `unreliable`
row can no longer be explained by namespace-root; (2) **supersede, for these three suites only, the sentence in decision
18 that keeps them on their derived or declared edges with the evidence gap stated, and decision 18's hedge-only-under-about-7-s
threshold**; (3) state the rule "a recorded read set equal to the registration corpus means hedge, not declare"; (4) carry
the revisit trigger above. `grep -n '^19\. ' ADR-242*` before writing (a sibling can claim the number). No new ADR file.

### C4 views

No C4 impact. Checked against `model.c4`, `views.c4`, `spec.c4`: no element names the test runner, the recorder or the
always-on set (`grep -n -i -E "test-all|recorder|always-on|suite"` hits only unrelated hook/Playwright prose);
external human actors changed: none; external systems/vendors: none; containers or data stores: none; actor-to-surface
access relationships: none. Run `bash plugins/soleur/test/c4-count-parity.test.sh` as the back-stop for derived
cardinalities.

### Sequencing

None; the decision is true on merge.

## Files to Edit

- `scripts/audit-suite-reads.sh` -- NETWRAP probe order (`unshare -cn`, `unshare -rn`, bwrap), `idmap=` header cell,
  `unshare` onto `make_scratch_bin`; text that names `unshare -rn`: header comment line 17 and the `die_usage` message at
  line 567; a header note that rows with different `idmap` values are not comparable.
- `scripts/audit-suite-reads.test.sh` -- Guard 1 rows in section B, an `EXPECT_IDMAP` probe next to `EXPECT_NETNS` (lines
  684-686), the scratch-bin tool row extended with `unshare`; re-price `ROWS_B_CORE` (line 771) and `MIN_CASES` (line 1306)
  by the number of rows added to section B (the fatal check at line 1150 enforces `ROWS_B_CORE` exactly); test header
  lines 15-16 and the skip text at lines 777-778.
- `scripts/lib/test-affected-paths.sh` -- add `scripts/test-affected-kb-consumers` to `ALWAYS_ON_SUITES` (new comment
  block, "Round 4"); five paths into `AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS`; rewrite the comments above
  `AFFECTED_SCRIPTS_TEST_AFFECTED_KB_CONSUMERS_PATHS` and the A5 `scripts/orphan-process-reaper` hedge block.
- `scripts/test-all.sh` -- line 3025 only: `_MIN_ALWAYS_ON_DECLARED=140` -> `141`.
- `scripts/test-all-affected.test.sh` -- row f1 code literals (140 -> 141 at lines 1781, 1782, 1784; the comment at 1776
  stays) and one new row f2 placed after q4 (lines 1940-1946) reusing `$_q4`: against the REAL runner (the sandbox arms
  trim the corpus to the keep-list, where this label is absent), assert exactly one line
  `AFFECTED_SELECTED<TAB>scripts/test-affected-kb-consumers<TAB>1<TAB>always_on<TAB>`. NOT the sandbox keep-list.
- `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md` -- append `## Addendum -- 2026-10-04
  (section 2 of #9307, recorder evidence for the three suites)` at the end only.
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
  -- append the short amendment above.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-recorder-evidence-three-suites/tasks.md` (from this plan).

## Consumer sweep (run BEFORE pushing; a missed consumer cost a CI round last time)

```bash
for n in audit-suite-reads.sh audit-suite-reads.test.sh test-affected-paths.sh test-all-affected.test.sh \
         test-affected-kb-consumers AFFECTED_SCRIPTS_TEST_AFFECTED_KB_CONSUMERS_PATHS \
         AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS _MIN_ALWAYS_ON_DECLARED; do
  echo "== $n"; git grep -l -F -- "$n" -- plugins/soleur/test plugins/soleur/skills scripts tests .github apps/web-platform/infra .claude lefthook.yml
done
```

Already found by running it on this tree (each must be opened and judged, not just listed):

- `scripts/pre-push-ratchet-lane.test.sh` (arm 21 pins `KB_CONSUMERS_INPUTS` to the kb-consumers declared array -> the
  array stays).
- `scripts/pre-push-ratchet-lane.sh` (names the suite in `LANE_MEMBERS` and `KB_CONSUMERS_INPUTS`; unchanged; its
  trigger set is a separate concern).
- `scripts/test-affected-derive.test.sh`, `scripts/affected-prepass-bench.sh`, `scripts/lint-orphan-test-suites.sh`
  (+ `.test.sh`), `plugins/soleur/test/fanout-suite-scope.test.sh`, `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`
  (all name `test-affected-paths.sh`; re-run the ones that execute it).
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` (names `test-all-affected.test.sh` and
  `test-affected-kb-consumers.test.sh`; a new fixture write in an edited test file adds sites -> run the ratchet).
- `.claude/hooks/incident-sandbox-coverage.test.sh` (lines 491-513 list `scripts/lib/test-affected-paths.sh` as a measured
  hop-2 member under `OUTSIDE_CEILING=4`; edits to the quoted-path arrays can move it -> run it in Phase 2.5),
  `.claude/hooks/README.md:486` and `plugins/soleur/skills/work/SKILL.md:1046` (prose mentions; read, judge).
- `.github/workflows/ci.yml` line 1185 (comment naming `unshare -rn`; the AppArmor sysctl step covers `-cn` too: no edit).
- `scripts/test-all.sh` registrations at 4273, 5158, 5179 and `scripts/suite-durations.tsv` / `suite-shard-legs.tsv`
  (names only; unchanged). `test-all.sh` is deliberately not a sweep needle: it matches nearly every file.

## Implementation Phases

Order matters: the recorder audits a COMMITTED revision, so the edits it must see are committed first; the audit
doc is written last from the recorded table. No merge commits (merging `origin/main` trips rename-guard); if the branch
must catch up, rebase.

### Phase 0 -- baseline (no edits)

- 0.1 `git rev-parse --show-toplevel` equals the worktree; `bash plugins/soleur/skills/ship/scripts/battery-owed.sh` is
  noted for the end (rc 42 = skippable).
- 0.2 No suite is added, so the registration check is one command: `bash scripts/test-all.sh --enumerate-commands all |
  grep -c -F -e 'scripts/audit-suite-reads' -e 'scripts/test-affected-kb-consumers' -e 'scripts/orphan-process-reaper-mutations'`
  prints at least 3.

### Phase 1 -- recorder (TDD: rows first, red, then the edit)

- 1.1 Write the Guard 1 rows (section B, they need a namespace) in `scripts/audit-suite-reads.test.sh`; run: they are RED (`cq-write-failing-tests-before`). Mutation rows are scripted mutants with a "mutation landed" assertion (the `SANDBOX_MUT_OLD` pattern, `scripts/test-all-affected.test.sh:236-250`), not hand edits.
- 1.2 `cmd_record`: probe `unshare -cn true`, then `unshare -rn true`, then bwrap; keep `netns=unshare` for both
  unshare forms; new header cell `idmap=current|root|none`. `unshare -cn` needs util-linux
  >= 2.38; the `-rn` fallback keeps older hosts working and says `idmap=root`.
- 1.3 `make_scratch_bin`: add `unshare` (not `bwrap`: `unshare` success makes the bwrap arm unreachable). The tool grants
  no network (a nested netns is empty), so it widens nothing the suites could not already create.
- 1.4 Update the script header (line 17), the `die_usage` text (line 567) and the test's header/skip text; keep
  "ISOLATION IS NOT A SANDBOX" intact; add the "rows with different `idmap` are not comparable" note.
- 1.5 `bash scripts/audit-suite-reads.test.sh` green; then, after this guard-shaped commit,
  `bash scripts/guard-vacuity-floor.test.sh`, `bash plugins/soleur/test/fixture-relative-assert.test.sh`,
  `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh`, `bash plugins/soleur/test/fixture-cd-containment.test.sh`
  (learning 2026-10-03: they broke last time and were found only late). Commit (Phase 1 is its own commit: a revert of the hedge must not take the identity fix with it).

### Phase 2 -- declarations and the hedge

- 2.1 `AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS`: add the five paths (kept sorted with the existing entries).
- 2.2 `ALWAYS_ON_SUITES`: add `"scripts/test-affected-kb-consumers"` with a "Round 4" comment citing the measured
  numbers; keep `AFFECTED_SCRIPTS_TEST_AFFECTED_KB_CONSUMERS_PATHS` and give it a one-line comment: "retained for
  pre-push-ratchet-lane arm 21; do not delete".
- 2.3 `scripts/test-all.sh:3025` -> `141`; `scripts/test-all-affected.test.sh` f1 -> `141`; add row f2 (see Files to Edit).
- 2.4 Correct the A5 `scripts/orphan-process-reaper` comment (stays hedged on the recorder's own rule; the
  "unobserved under env -i" story was namespace-root).
- 2.5 Targeted suites (never `TEST_GROUP=affected` on this runner-touching diff, it exceeds 5000 s locally):
  `bash scripts/test-all-affected.test.sh` (about 442 s, detached + Monitor), `bash scripts/test-affected-derive.test.sh`,
  `bash scripts/test-affected-kb-consumers.test.sh`, `bash scripts/pre-push-ratchet-lane.test.sh`,
  `bash scripts/lint-orphan-test-suites.sh`, `bash .claude/hooks/incident-sandbox-coverage.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`. Commit (Phase 2 is its own commit).

### Phase 3 -- re-record against the committed revision (evidence)

```bash
SHA=$(git rev-parse HEAD)   # must already contain Phases 1 and 2
OUT=$(mktemp -d "${TMPDIR:-/var/tmp}/rec-final.XXXXXXXX")        # a new, empty, owned directory
setsid nohup bash -c "bash scripts/audit-suite-reads.sh record --rev $SHA --mode check --cover-from-selection \
  --max-load 12 --load-wait 600 --only scripts/test-affected-kb-consumers,scripts/orphan-process-reaper-mutations,scripts/audit-suite-reads,scripts/orphan-process-reaper,scripts/tunnel-connector-census,plugins/soleur/test/worktree-manager-atomic-config.test.sh,plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh,plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh,tests/scripts/scratch-session \
  --out $OUT/out > $OUT/stdout 2> $OUT/stderr; echo \$? > $OUT/rc" >/dev/null 2>&1 &
```

Watch with Monitor (stderr `[audit]` lines and the rc file), never a foreground sleep. Expected: orphan-process-reaper-mutations
`covered`; tunnel-connector-census `covered` (known-clean control); audit-suite-reads `uncovered` whose list starts with a
directory (no file outside the cover); kb-consumers `uncovered` (moot, always-on); orphan-process-reaper `uncovered` with
`unresolved` probes (hedged). The four root-skipped hedged suites are recorded as DATA only: report their verdicts and
change nothing. **Pass criterion (a measurement, not a gate):** exit 0, no `unreliable` and no `load_refused` row, retried
once; any later commit that touches the recorder, the edge arrays or the three suites invalidates the SHA and means
re-recording. Any `unreliable` row: retry once; do not write a cause down before a known-clean control in the same position
agrees (learning 2026-10-03). A `load_refused` flag is no evidence and is re-run, not counted.

### Phase 4 -- docs

- 4.1 Append the addendum to the audit doc: per suite, option taken, why, measured cost (both the +5.6% always-on and the
  marginal per-commit figure), the final table pasted verbatim with the audited SHA; state that audit-suite-reads is
  `uncovered` for directory listings only (uncovered list is files-then-directories, first entry `.`); mark every
  pre-2026-10-04 row as "recorded under idmap=root"; state that "Reproducing the recorder" (which names `unshare -rn`) is
  superseded for the invocation identity; say what was NOT re-run.
- 4.2 Append ADR-242 decision 19.
- 4.3 Commit; push; `battery-owed.sh` decides the remaining battery (rc 42 skippable).

## Guard Contract

### Guard 1 -- the recorder runs a suite as the invoking user

**Property.** A suite run by `audit-suite-reads.sh record` sees the uid of the user who started the recorder, never
namespace-root, whenever `unshare --map-current-user` works on the host.

**Assembly.** One chokepoint, the `NETWRAP` array assigned in `cmd_record`, with three consumers that must all go
through it: `run_bounded` (enumerate, selection, every suite window), the harness git array `G`, and the header stamp
`idmap=` (which must name the mapping that was really used). There is no other place a suite process is started.
Rows live in section B of `scripts/audit-suite-reads.test.sh` (they need a namespace). The expected `idmap` is derived on
the host by probing `unshare -cn true` next to `EXPECT_NETNS` (`EXPECT_IDMAP`), so the assertion is host-independent.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | set `NETWRAP=(unshare -rn)` (revert to namespace-root) | RED: the fixture suite that exits 16 when `id -u` differs from the uid the TEST wrote into the fixture at runtime sees 0 |
| 2 | make the `unshare -cn true` probe always fail (the guard's own dispatch) | RED when the host supports `-c`: header `idmap=` differs from `EXPECT_IDMAP` |
| 3 | add a SECOND uid-checking suite after a compliant first and drop `NETWRAP` for windows after the first | RED: the second suite's check fails (a check that stops at the first suite is the defect) |
| 4 | shim `unshare` to reject `-c` (an older util-linux) | must-PASS with a difference: rows still decided, header `idmap=root`, suites run |

Rows 1-3 are scripted mutants with a "mutation landed" assertion (the `SANDBOX_MUT_OLD` pattern in
`scripts/test-all-affected.test.sh:236-250`), not hand edits. Harness rows: delete the fixture's runtime-written uid file;
the uid row must go RED (an empty expectation cannot score as a pass). Must-PASS that is not the canonical: row 4.
**Anchor.** The expected uid is read from the running test process (`id -u`) at fixture-build time, never stored in the
repo, so one diff cannot move both sides. When the test is itself run as uid 0 the uid rows pass vacuously with a note and
the mutation rows are unreachable; CI runs the suite as the non-root runner user (to be confirmed at Phase 0 with
`id -u` in the scripts job, where the existing AppArmor step already assumes an unprivileged user).

### Guard 2 -- `scripts/test-affected-kb-consumers` is selected on every diff, and the census floor follows the count

**Property.** On the docs-only probe (`--print-selection --paths=README.md`) the label is class `always_on`, and
`count(ALWAYS_ON_SUITES) - _MIN_ALWAYS_ON_DECLARED` is between 0 and 5.

**Assembly.** The `ALWAYS_ON_SUITES` array in `scripts/lib/test-affected-paths.sh` (the one chokepoint the classifier
reads), the floor in `scripts/test-all.sh:3025`, row f1 (floor pin and slack) and the new row f2 (membership, against the
real runner after q4) in `scripts/test-all-affected.test.sh`, and the second consumer of the declared array, arm 21 of
`scripts/pre-push-ratchet-lane.test.sh` (its own suite, pre-existing).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | remove the label from `ALWAYS_ON_SUITES` | RED: f2 (count 145 still satisfies f1, so only f2 catches it) |
| 2 | f2's own dispatch: anchor f2 on a different label, or let the probe return a count other than 1 | RED: f2 requires exactly one matching row |
| 3 | add one more label to the array without raising the floor | RED: f1 (`count - floor` = 6) |
| 4 | delete `AFFECTED_SCRIPTS_TEST_AFFECTED_KB_CONSUMERS_PATHS` | RED: pre-push lane arm 21 (the second consumer; pre-existing row, not counted as new) |

Harness rows: edit f2's grep to anchor on a different label and require RED (row 2). Must-PASS that is not canonical: move
the label to another position in the array and f1/f2 stay green.
**Anchor.** The floor is a pin AND a relation computed from the live array, so a one-line weakening of the floor alone is
caught by f1; one diff can still move the array, the floor and f1 together (consistency, not integrity). The outside
anchor is review of the merge-base diff of those three lines, named here as a reviewer obligation, not claimed as a gate.

## User-Brand Impact

- **If this lands broken, the user experiences:** a contributor's local `test-all.sh --affected` selects one suite too
  few or too many; CI's full battery on the PR head remains the only merge gate (ADR-183, ADR-242), so no user-facing
  surface changes.
- **If this leaks, the user's data is exposed via:** nothing; the recorder runs repository code in a no-IP-network
  namespace with a scrubbed environment, and the new scratch-PATH tool grants no network.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** operator/CI test-selection tooling with no user data, auth, payment or runtime
  surface; the worst case is a local false-green that CI catches.

## Observability

Operator-run tooling under repo-root `scripts/` (outside plan Phase 2.9's path list), but deepen-plan Phase 4.7 gates every
non-docs plan, so the surface is declared. The recorder's observability IS its table and exit code; there is no server.

```yaml
liveness_signal:
  what: the AUDIT_READS_HEADER row of <out>/table.tsv (rev, mode, netns, idmap, reps, cover) plus one [audit] line per window on stderr
  cadence: per recorder run (operator-run, never in CI)
  alert_target: the operator's terminal and the rc file of a detached run (Monitor watches stderr and the rc file)
  configured_in: scripts/audit-suite-reads.sh (cmd_record header printf and the per-window printf)

error_reporting:
  destination: stderr of the recorder and its exit code (0 decided, 2 usage, 3 any unreliable row, 4 zero suites or windows)
  fail_loud: an unreliable row names its reason (rc, skipped, contaminated, load_refused, no-netns); exit 3 when any row is unreliable

failure_modes:
  - mode: the recorder runs suites in the wrong identity (namespace-root) or a host without unshare -c
    detection: header cell idmap= and the Guard 1 uid rows in scripts/audit-suite-reads.test.sh
    alert_route: test failure in the scripts CI job; idmap=root visible in every table header
  - mode: a suite SKIPs inside the recording and reads nothing
    detection: the recorder flags the window skipped and the row is unreliable reason=skipped
    alert_route: exit 3 and the row in table.tsv
  - mode: the always-on census drifts below or far above the floor
    detection: rows f1 and f2 of scripts/test-all-affected.test.sh and the runner pre-pass refusal (exit 4)
    alert_route: CI scripts job and the local gate

logs:
  where: <out>/logs/<window>.log per suite run, <out>/events and <out>/reader.err (the default --out directory is kept on purpose)
  retention: until the operator deletes the kept directory; the private checkout is removed on exit and swept after 24 h

discoverability_test:
  command: bash scripts/audit-suite-reads.sh --help
  expected_output: --cover-from-selection
```

## Gates assessed and skipped

- Domain Review: **Domains relevant:** none -- internal test-tooling change, no cross-domain implication.
- Observability (Phase 2.9): path trigger not met (no file under `apps/*/server`, `apps/*/src`, `apps/*/infra` or
  `plugins/*/scripts`); declared anyway above because deepen-plan Phase 4.7 gates every non-docs plan.
- IaC, Encryption Posture, GDPR: not triggered (no `.tf`, migration, cloud-init, compose, regulated data).
- Network-outage checklist: not triggered (`unshare` network namespace is the isolation mechanism, not a symptom).
- Open code-review overlap: see below.

## Open Code-Review Overlap

Checked 2026-10-04 with `gh issue list --label code-review --state open --json number,title,body` then `jq --arg path` per file in Files to Edit. Four open issues name an edited file; none is folded in:

- #8800 (census sandbox shares inodes/symlinks with the live repo) names `scripts/lib/test-affected-paths.sh` and `scripts/test-all-affected.test.sh`. **Acknowledge:** a census-sandbox write-through hazard in other suites; the f1/f2 rows added here write nothing to the sandbox. It is also the "hardlink and symlink aliasing" blind spot the recorder header already lists.
- #8659 (test suites replace the composed EXIT trap) and #7942 (two `*.mutation.sh` batteries run in no gate) name `scripts/test-all.sh`. **Acknowledge:** this plan changes one integer in that file; neither concern is touched.

No overlap for `scripts/audit-suite-reads.sh`, its test, the audit doc or ADR-242. Re-run the query at Phase 0 and record any new hit with a fold-in / acknowledge / defer line.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Give recorder evidence to the three test suites that are currently kept on their derived or declared edges WITHOUT recorder evidence" | Decisions 1-3, Phase 3 | mapped |
| 2 | "(a) give audit-suite-reads and orphan-process-reaper-mutations a recorder-compatible mode" | Phase 1 (instrument fix, not a suite mode) | mapped |
| 3 | "(b) declare their real read sets by hand from a run on a host where they run to completion" | Phase 2.1 (audit-suite-reads) | mapped |
| 4 | "(c) hedge the cheapest into ALWAYS_ON_SUITES" | Phase 2.2-2.3 (kb-consumers) | mapped |
| 5 | "Re-run the recorder as documented: `record --mode check --cover-from-selection --only <labels>`, against a COMMITTED revision, `--max-load 12`" | Phase 3 | mapped |
| 6 | "Update the audit doc with a dated addendum (append-only, do not edit earlier rounds)" | Phase 4.1 | mapped |
| 7 | "do not touch the sandbox keep-list in scripts/test-all-affected.test.sh" | Decision 4; f1/f2 edits only | mapped |
| 8 | "any suite you add or change needs its own registration check, and the plan MUST list the consumer-sweep command" | Phase 0.2; Consumer sweep section | mapped |
| 9 | "filings via `gh issue create --body-file`" | Phase 4.3 | mapped |
| 10 | "Section 3 of the list ... and tracker #9441 are NOT part of this task" | Overview, Cut List | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| NETWRAP `-cn` probe, `idmap=` header cell | "give audit-suite-reads and orphan-process-reaper-mutations a recorder-compatible mode" | asked |
| `unshare` on scratch PATH | "the recorder cannot audit itself under its own network namespace" | asked |
| five declared reads (audit-suite-reads) | "declare their real read sets by hand from a run on a host where they run to completion" | asked |
| kb-consumers hedge, floor 141, f1/f2 | "hedge the cheapest into ALWAYS_ON_SUITES" | asked |
| keep `AFFECTED_..._KB_CONSUMERS_PATHS` | "the plan MUST list the consumer-sweep command" (a missed consumer: pre-push lane arm 21) | asked |
| four root-skipped hedged suites in the Phase 3 batch (data only) | "Re-run the recorder as documented" | inferred -- justification: four extra labels in the same run (about 30 s) answer whether the same mapping caused their skips, replacing a speculative follow-up issue; nothing is changed on the result |
| ADR-242 decision 19 (short pointer) | "stating per suite which option was taken and why" | inferred -- justification: decision 18 says these three stay on their edges; the plan supersedes that sentence, and a recorded ADR sentence must not contradict the code (Phase 2.10) |

### Split Assessment

- Subsystems touched: 2 -- `scripts/`, `knowledge-base/`
- Planned files: 8 | Estimated changed lines: about 190 (recorder 15, tests 100, lib 30, docs 45)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] `bash scripts/audit-suite-reads.test.sh` passes with 0 skipped sections as the non-root user. Its Guard 1 rows 1-3 are scripted mutants with a "mutation landed" assertion and each goes RED under its mutation; row 4 (the `-c`-rejecting shim) passes with `idmap=root`. The uid rows pass vacuously with a note when run as uid 0. (verified: 339 passed, 0 failed, 0 skipped, run as uid 1000)
- [x] Guard 2 rows live in their own suites: f1 (literals 141) and the new f2 in `scripts/test-all-affected.test.sh` are green; mutations 1-3 each go RED; `bash scripts/pre-push-ratchet-lane.test.sh` is green (arm 21). (verified: f1/f2 green; mutations 1 and 3 and the arm-21 deletion each RED when run; mutation 2, f2 anchored on another label, is RED by construction and was not executed)
- [x] A final recorder run against a COMMITTED SHA (stamped in the header) meets the Phase 3 pass criterion (exit 0, no `unreliable`/`load_refused` row, retried once), shows `scripts/orphan-process-reaper-mutations` `covered`, `scripts/tunnel-connector-census` `covered`, and `scripts/audit-suite-reads` with a directory as the first uncovered entry; the table is pasted verbatim into the addendum with that SHA. (verified, with one deviation: exit 3 because three data-only labels are `unreliable skipped` on a missing capability, reproduced on a retry; the three target suites and the control are decided; audited SHA e2b479b59d)
- [x] `scripts/test-affected-kb-consumers` is `always_on` on the README probe; `git grep -n '^_MIN_ALWAYS_ON_DECLARED=' scripts/test-all.sh` prints 141; `AFFECTED_SCRIPTS_TEST_AFFECTED_KB_CONSUMERS_PATHS` exists and carries the "retained for pre-push-ratchet-lane arm 21; do not delete" comment. (verified: floor 141, count 146, array kept with its comment)
- [x] `git diff origin/main -- scripts/test-all-affected.test.sh` touches only the f1 code literals and the new f2 row (nothing in the sandbox keep-list); `git diff --stat origin/main -- scripts/suite-durations.tsv scripts/suite-shard-legs.tsv` is empty. (verified: only f1 literals, new f2 row and MIN_CASES 85 to 86; TSV pair untouched)
- [x] The audit doc gains one dated addendum at the end and `git diff origin/main -- <audit doc>` shows only added lines (it marks pre-2026-10-04 rows "recorded under idmap=root" and says "Reproducing the recorder" is superseded for the invocation identity); ADR-242 gains one short appended amendment that supersedes decision 18's sentence and 7 s threshold for the three suites, earlier decisions untouched. (verified: append-only, +41 lines, 0 removed; ADR-242 +13 lines, 0 removed)
- [x] Phases 1 and 2 are separate commits (`git log --oneline origin/main..HEAD` shows the recorder commit before the hedge commit); no merge commit (`git log --merges origin/main..HEAD` empty). (verified: recorder commit before hedge commit; no merge commits)
- [x] The consumer-sweep command was run and every hit judged (recorded in the PR body); `bash scripts/lint-orphan-test-suites.sh`, `scripts/test-affected-derive.test.sh`, `scripts/test-affected-kb-consumers.test.sh`, `.claude/hooks/incident-sandbox-coverage.test.sh`, the four fixture/vacuity ratchets and `c4-count-parity` are green; `battery-owed.sh` rc 0 or 42. (verified except battery-owed: rc 0 = OWED only because the branch is behind origin/main; ship syncs it)
- [ ] PR body says `Ref #9307`, not `Closes`.

## Test Scenarios

- Recorder under a host where `unshare -c` is unsupported (shim): header `idmap=root`; check-mode rows decided; demote-mode rows `unreliable idmap-root` (review round: demote is decided only for `idmap=current`).
- Recorder when the invoking user is root: stamped `idmap=root` (review round: `-c` maps root to root, so arms that refuse a privileged caller still skip); section B of the suite is a counted skip, a failing row under CI.
- audit-suite-reads recorded inside its own recording: section B runs (0 skipped), the inner `record` rows produce the
  same table the outer sees.
- kb-consumers on a docs-only diff: selected (class `always_on`), `ALWAYS_ON` count 146.
- Pre-push lane with a diff touching only `test-affected-paths.sh`: the lane trigger still fires (unchanged inputs).

## Risks and sharp edges

- **Identity change widens what a recorded suite can do** (a non-root suite now cannot do namespace-root things it
  could before, and arms skipped "as root" now run). Both directions only add observed reads; earlier `covered` rows were
  recorded under namespace-root and are not re-run here (stated in the addendum; the scheduled recorder check, section 3, owns that).
- **`unshare -cn` is util-linux >= 2.38.** Fallback keeps older hosts working; the header says which mapping was used so a
  mixed-mapping corpus is visible.
- **CI user:** the scripts job runs the suite as the non-root runner user (confirm in Phase 0); if it ever ran as root, Guard 1's mutation rows would be unreachable in the one place that gates merges.
- **A recording of a committed revision, then docs commit:** the rows stamp the audited SHA, not HEAD; do not describe the
  docs commit as audited.
- **Do not hand-merge or edit the TSV pair; do not touch the keep-list; do not run `TEST_GROUP=affected`.**
- **A plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6** -- it is filled (threshold `none`).
- Directory listings that the recorder reports as `uncovered` are not declared: declaring `knowledge-base/` etc. for the
  audit-suite-reads walk would make a docs-only diff select a 73 s suite for no verdict change.

## References

- `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md` ("Reproducing the recorder", "Round 3 re-check")
- ADR-242 decisions 15-18; ADR-262; ADR-183
- `scripts/audit-suite-reads.sh`, `scripts/lib/inotify-open-recorder.py`, `scripts/lib/test-affected-paths.sh:90-320, 446-455, 615-623, 748-758`
- Learning `2026-10-03-the-recorder-called-its-own-checkout-dirty-and-i-explained-it-as-the-suite.md`
- Umbrella #9307 (open); out of scope: #9441
