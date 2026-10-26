---
title: "ci: S4 PR4c, the remaining held-back edges of the code-edge drain and their revealed mentions"
date: 2026-10-26
slug: ci-s4-affected-index-pr4c-held-back-edges
branch: feat-one-shot-s4-affected-index-pr4c-held-back-edges
issue: 10959
type: chore
lane: cross-domain
refs: [10959, 10448, 9729]
brand_survival_threshold: aggregate pattern
---

# ci: S4 PR4c, the remaining held-back edges of the code-edge drain and their revealed mentions

Ref #10959. Ref #10448 (series tracker, stays open). Ref #9729 (epic). PR text uses `Ref` only, never a closing keyword.
Draft PR #11131 (label `s4-drain`, branch `feat-one-shot-s4-affected-index-pr4c-held-back-edges`) already exists and the claim comment on #10448 is posted.
Spec lacks a valid `lane:` (there is no spec.md for this branch), so it defaults to `cross-domain` (fail-closed).

## Overview

PR4b (merged 2026-10-26 as `b97c1d275e`, baseline 1,640 to 1,629 lines) declared 11 of the 117 held-back real-read edges of the PR4 code-edge drain and accepted 18 mention pairs. PR4c continues from the worklist section of #10959 (105 edges still baselined, 104 declarable): it re-tests the held edges whose hold reason PR4b handed to it, declares the edges that pass the series bar and accepts the mentions they reveal with anchor-keyed accept rows, under the unchanged CTO stop line (round 1 under 60 pairs per chain and at most 130 summed, later rounds under 30 and strictly shrinking, at most 4 rounds, cumulative at most 150).

What it does, in order: (1) re-measures the base and recomputes every numeric hold on current `origin/main`; (2) re-tests the 11 `recorder-unreliable` / `declared-F-never-opened` edges with one recorder attempt or a suite-text proof each (CTO row 1, PR4b rows 15C and 15E); (3) cuts one ascending pool of {re-tested edges that pass} U {PR4b's out-of-slice suites} at a round-1 sum of 130 (measured cut: the 42 re-test pairs, then `boundary-prefix`, `required-checks-merge-group-coverage`, `preflight-check10-suite-integrity`, `scratch-residue`, `plugins/soleur`, cumulative 117, 34 edges; the next suite, `t5-skip-persistence-bound-7510`, would make 135); (4) per chain declares the edges, saves the first report, pre-classifies every revealed pair from a cited line and recorder evidence (real read: declared next round; mention: accept row; doubt: the whole edge is held) and repeats to a fixpoint; (5) regenerates the baseline only with the prune-only `ratchet --print-baseline`; (6) leaves the rest by name to PR4d (at most one, only if PR4c declares at least 10 edges) and PR5 (#10861).

Expected yield is a range, stated so nobody reads PR4c as the series' end: PR4b converted 11 of 36 slice edges (31 percent), so the 34-edge slice predicts about 10 declared edges (range 1 to 20), a baseline of about 1,619 lines after, and on the order of 20 to 60 new accept rows (PR4b's trial ratio was 748 boundary lines per 501 pairs; Phase 1 measures it). The PR body states the measured count (declared N; N at least 10 makes PR4d eligible) and promises no PR4d scope. The floor is one declared edge (CTO row 5); with zero survivors no baseline change merges and everything moves to PR5 by name. The value is retiring the cheapest real reads, applying the accept-row flow once more at the stop line, and fixing the end of the drain series (PR4d is the last drain PR; anything left goes to PR5).

## Research Insights

### Premise validation (Phase 0.6)

Checked live with `gh`/`git` on 2026-10-26: #10959, #10448, #9729, #10860, #10861, #10865, #10414, #10859, #10949, #10862 are all OPEN; draft PR #11131 is OPEN, is the only `s4-drain` PR and has no commits beyond the branch init (`gh pr view 11131 --json files` reports 0 files); PR4b merged as `b97c1d275e` and `origin/main` is `81192540bf` (two infra pin bumps later, none touching the index, baseline or accept file). Baseline `wc -l` = 1,629; accept file = 74 lines; the brief's "1,629" holds.
Worklist: the archived PR4b `receipts/edges-decisions.tsv` has 106 non-`declare` rows; 105 are still exact lines of the baseline (the 106th, `scripts/inngest-probe-heartbeat-feeder` -> `scripts/lib/inngest-probe-row.sh`, is `already-undrained`), of which `tests/scripts/inngest-host-dark-gate` -> `scripts/lib/inngest-probe-row.sh` is `kept-for-census` (CTO row 5 of the PR4b log: no test edit in a drain PR). So 104 edges are declarable candidates. The PR4b archive is under `knowledge-base/project/specs/archive/20261025-222836-feat-one-shot-s4-affected-index-pr4b-held-back-edges/` (the brief's path holds).
STALE-premise check: the runbook already carries the PR4b/PR4c accept-row allowance (section 7, "Never in a drain PR", "Reveal and hold-back", "Ambiguous pairs and big files"), so unlike PR4b no rubric edit is owed; only the "PR4b worklist" bullet needs a PR4c pointer. ADR corpus: ADR-276 amendment item 2 is the drain tool and already authorizes accept rows; no ADR lists accept rows or per-chain drains as a rejected alternative (PR4b grep, nothing changed since).

### Measurements (this planning session, read-only, local)

- Trial (throwaway detached worktree of `81192540bf`, removed afterwards; the 104 candidate edges declared at once in 27 existing arrays plus 5 new blocks, NO accept rows): `exit=1 reason=new-pair live=2000 baseline=1629` => 475 new pairs, 104 `stale-line` (exactly the declared edges), wall 192 s. No suite outside the declared set gained a pair. Receipts: `receipts/trial-all-edges-reveal-by-suite.tsv`, `receipts/trial-all-edges-new-pairs.tsv`, `receipts/ratchet-trial-all-edges-81192540bf.out`, `receipts/worklist-edges.tsv`.
- Shape (suite: edges, round-1 reveal): 25 small suites reveal 1 to 12 each (cumulative 105, 25 edges; these are PR4b's `held-*` suites plus `scripts/compound-promote`); PR4b's `out-of-slice` suites: `boundary-prefix` 5/13, `required-checks-merge-group-coverage` 1/14, `preflight-check10-suite-integrity` 3/15, `scratch-residue` 9/16, `plugins/soleur` 5/17, `t5-skip-persistence-bound-7510` 1/18, `battery-tag-authorship` 5/29 (these seven: 29 edges, cumulative 122), `betterstack-emitter-read` 18/29 (cumulative 151, past the 130 line), `grep-q-pipe-guard` 31/68, `git-data-birth-readiness-gate` 1/151 (never a drain-PR edge, ruled to PR5).
- The reveal numbers agree with PR4b's trial for the out-of-slice suites to within 1 pair, so PR4b's real reads did not move them. 151 of the 475 first-ref files are `grep-q-pipe-guard.test.sh` itself (the 151 pairs of the birth-readiness edge) and 37 are `apps/web-platform/infra/run-registered-suites.sh` (31 commits in 90 days: hot; shared by `battery-tag-authorship` and `t5-skip-persistence-bound-7510`).
- Hot declared files among the 34 slice edges' F (`git log --since=90.days --oneline origin/main -- F | wc -l`, measured at planning, 2026-10-26): `apps/web-platform/test/plugin-root-anchoring.test.ts` 11, `scripts/followthroughs/git-data-rung2-evidence-capture.sh` 15, `scripts/sweep-followthroughs.sh` 10, `.claude/hooks/guardrails.sh` 13, `plugins/soleur/scripts/grok-pre-push-gate.sh` 9, `tests/scripts/test-infra-privileged-tier-census.sh` 19; `scripts/betterstack-query.sh` is at 8 (not hot, but any commit in the window makes it hot) and is F for three re-test edges; every other F is at or under 8 (`ship-unpushed-commits-gate.test.sh` is exactly 8). `apps/web-platform/infra/run-registered-suites.sh` (31) belongs to `t5-skip` and `battery-tag-authorship`, which are PR4d. Any accept row on a hot F holds the whole edge; these are the hot-F exception candidates of CTO row 4 and the counts are re-run in Phase 0.3.

### Institutional learnings applied

All of the PR4b list still applies (see the archived PR4b plan, "Institutional learnings applied": regenerate the baseline from `git checkout origin/main -- <baseline>`, audit WITH main's accept file, duplicate `AFFECTED_*_PATHS` check after each merge of main, `grep -q P < <(producer)`, kill own stale suite runs, stage by explicit pathspec). New or sharpened for PR4c:
- `knowledge-base/project/learnings/2026-10-25-a-read-recorder-classifies-revealed-pairs-and-an-all-edges-trial-sizes-a-drain.md`: run the recorder over the slice suites BEFORE classifying by eye (two recordings, about 15 s per suite); opened in both = real read, not opened = mention only if the line kind is in the closed list; recorder-unreliable and bulk readers hold; the yield is bounded by the holds, not the cap (PR4b: 11 of 36 slice edges declared).
- `knowledge-base/project/learnings/2026-10-18-ratchet-guards-must-pin-the-scan-population-and-their-own-registrations.md`: a comment added to `scripts/lib/test-affected-paths.sh` can be an INDEX-ANCHOR finding; add only array entries and the existing `# THIS FILE` marker, no new comment lines.
- `knowledge-base/project/learnings/2026-10-25-a-fix-round-reintroduced-the-pipe-it-was-fixing-and-the-worktree-vanished-under-it.md` and `plugins/soleur/skills/git-worktree/SKILL.md` (manual-worktree lease note): the worktree was reaped last time while the lead waited on background suites. The lease is a time-boxed reservation (default 240 minutes, window clamped to 4-24 h, `acquire_lease` in `plugins/soleur/scripts/lib/session-state.sh`) with no automatic renewal; a lease file for this worktree exists now. Commit and push a WIP before every long wait and re-acquire the lease before each wait and again while the PR sits in the merge queue.
- `plugins/soleur/skills/ship/references/queue-mode.md`: a BEHIND armed PR must not be synced and a push dequeues it, so the only window to merge `origin/main` (the accept file conflicts when siblings append rows) is BEFORE arming.
- `knowledge-base/project/learnings/2026-09-22-one-shared-json-leaf-made-every-pair-of-prs-conflict.md`: the accept file is a shared tail; insert rows in the file's existing order and re-derive them from the audit after the merge instead of resolving a conflict by hand.

### Property List and Cut List (Phase 0.6b)

Properties (observable outcomes): (1) a held-back edge is declared only where the suite really reads or executes the file, and a revealed pair is accepted only as a classified mention; (2) the baseline only loses lines, only through the prune-only `ratchet --print-baseline`, run to a fixpoint; (3) every revealed pair is classified from a cited line and recorder evidence BEFORE the commit and the CTO stop line holds; (4) every commit leaves `ratchet` at exit 0 and the final audit shows zero stale or unused accept rows; (5) what PR4c did not take is tracked by name on #10959 with the reason code; (6) the window consequence is recorded on #10865 with the merge SHA; (7) the PR survives the merge queue (merged with `origin/main`, lease alive, no sync after arming).
Mechanisms the ask names, and what on `origin/main` already buys each property (grepped: `scripts/ci-pr-affected-replay.py --help`, the runbook section 7, the accept file, `scripts/audit-suite-reads.sh --help`): declaration (`AFFECTED_*_PATHS`), prune-only baseline, anchor-keyed accept rows with a validator (`load_accept`, `judge_rules`), the read recorder, the stop line (a CTO ruling, not code) and the worktree lease (`acquire_lease`) all exist.
Cut list: no new script or lint (receipts are data; the helper scripts of the work phase stay in the scratchpad); no change to `ratchet`, the audit reach, the replay suite or the recorder; no new `_CLOSURE_LEAF_*` array unless 3 or more labels spread the same helper; no ADR edit; no accept-file schema change; no new issue (the continuation is #10959); no lease-renewal tooling (`acquire_lease` re-acquire is the existing mechanism); no sibling-conflict automation (merge `origin/main`, regenerate, push before arming is the existing recipe).

### Value-proposition measurement (Phase 0.6c)

No CI-cost saving is claimed (the lever `CI_PR_AFFECTED` is unset and locked). The measurable output is baseline lines drained: `wc -l scripts/ci-pr-affected-audit.baseline.tsv` before (1,629) and after, upper bound 34 of 1,629 for the 34-edge slice (2.1 percent, before the hold rules), and accept rows added (`wc -l` of the accept file; estimate from the trial's mention share). PR4b's measured conversion was 11 declared of 36 slice edges (31 percent); the plan states that expectation and does not argue the yield.

## Research Reconciliation: Spec vs. Codebase

| Claim (issue #10959, the brief, the archived rulings, the runbook) | Reality on `origin/main` `81192540bf` | Plan response |
|---|---|---|
| "baseline is now 1,629 lines" | `wc -l` = 1,629 | Quoted in the PR body as `wc -l` output; Phase 0.2 re-measures with `ratchet` |
| #10959 worklist: 79 out-of-slice + 7 + 6 + 4 + 4 + 2 + 1 + 1 + 1 + 1 edges (about 106) | 106 non-`declare` rows in the archived `edges-decisions.tsv`; 105 are exact baseline lines; `scripts/inngest-probe-heartbeat-feeder` -> `scripts/lib/inngest-probe-row.sh` is `already-undrained`; the `kept-for-census` row is still baselined and stays so | Worklist `receipts/worklist-edges.tsv` (106 rows), 104 declarable candidates; the 2 retired rows keep their outcome |
| Brief: "round 1 under 60 pairs per chain and at most 130 summed ... reveals pre-classified" | The out-of-slice suites alone sum to 151 (without `grep-q-pipe-guard` and the birth-readiness edge); the re-testable held suites add 42 | CTO row 1: one ascending pool cut at 130 (34 edges, 117 pairs); CTO row 3 hands `t5-skip`, `battery-tag-authorship`, `betterstack-emitter-read` to PR4d |
| #10959: "`grep-q-pipe-guard` (31 edges) is PR4c or PR5" and "152-pair `git-data-birth-readiness-gate` goes to PR5" | Trial: `grep-q-pipe-guard` 68 pairs (35 code), the birth-readiness edge 151 pairs | CTO row 2: PR5 by name; the 151-pair edge is above the 60 per-edge ceiling (PR4b row 3) and also PR5 |
| #10959 step 3 (PR4b text): the 43 whole-tree-read pairs need a selection-policy call | Ruled as policy only in PR4b row 6; the worklist section of the #10959 body lists none of the 43 | Out of PR4c (decision-challenges row 7); PR5 by name |
| Runbook (PR4b edits): accept rows allowed "in PR4b and PR4c" | CTO row 3 of this PR extends the allowance to a single PR4d | Runbook wording edit (Phase 4.1); no other rubric change owed |
| Brief: "keep the worktree lease alive while waiting in the merge queue (it was reaped last time)" | The lease is time-boxed (240 minutes default, no automatic renewal, no heartbeat in `session-state.sh`); `acquire_lease` re-acquires; a PR in the merge queue holds only the creation-time grant | Phase 0.1/5.1: re-acquire before every long wait and while queued, plus a WIP commit and push before each wait |

## Technical Rulings (CTO agent, 2026-10-26; the full text of each row is in `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4c-held-back-edges/decision-challenges.md`, rows 1-6)

Every row is `Ruled by CTO agent, 2026-10-26`; the PR4b rulings (archived log rows 1-16) still bind where not amended. One line each, the log is the single copy: (1) one ascending pool of out-of-slice suites and re-testable held edges, cut once at a round-1 sum of 130; (2) `grep-q-pipe-guard` goes to PR5; (3) at most one PR4d, only if PR4c declares at least 10 edges, the last drain PR, accept-row allowance extended to it; (4) the hot-file test covers the mention-line file and the real-read file, with a zero-accept-row hot-F exception (every pair a real read, `commits_90d x declaring suites <= about 72`); (5) floor of one declared edge, zero survivors means no baseline PR merges; (6) caps judged after pre-classification holds and before accept rows, counts and re-test evidence copied into `receipts/`.

## Implementation Phases

Process rules for the work phase: run every long command detached (a script file started with `setsid nohup bash <file>` or the Bash tool's `run_in_background`, an rc file, one `until` loop or Monitor); `grep -q P < <(producer)`, never `producer | grep -q`; no `git stash`; stage by explicit pathspec; `CI_PR_AFFECTED` unset in every shell used (receipt: `env | grep -c '^CI_PR_AFFECTED='` prints 0).
Hook denials seen in PR4b: a recursive delete with an unexpanded variable, a process-pattern search or kill (`-f` forms), and any Bash call whose TEXT contains such a pattern, even inside a heredoc or a commit message: use literal absolute paths, `git worktree remove --force <literal path>` for scratch worktrees, kill by PID read from an rc/pid file, and write the helper scripts to the scratchpad directory with the Write tool rather than a heredoc that quotes a blocked flag.
Lease and survival: before every long wait (a detached suite, a review seat, the merge queue) commit and push a WIP, and re-acquire the lease: `source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/session-state.sh" && acquire_lease "$(basename "$PWD")" work 240`, then assert the file `$(git rev-parse --git-common-dir)/soleur-session-state/leases/<key>.lease` exists. A manual-worktree lease expires and nothing renews it.
No new comment lines in `scripts/lib/test-affected-paths.sh` (an INDEX-ANCHOR finding degrades `--affected`): only array entries, new array blocks with the existing `# THIS FILE` marker.

### Phase 0 - claim, base, lease, calibrate (no index edit)

- 0.1 `gh pr list --label s4-drain --state open` returns only #11131 and the mirror comment on #10448 names #11131 (a lost or duplicated claim: STOP and report). `git fetch origin main`; `git merge origin/main` if it moved; run the Sibling PR Overlap loop; acquire the lease (above) and commit the receipts directory as a WIP.
- 0.2 Measure the base on a detached worktree of `origin/main`: `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main --report <file>` (expect exit 0, `live == baseline`) and `audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv`; record both summary lines and `wc -l` of the baseline and the accept file. In every case run the base `ratchet --base origin/main` once on the detached `origin/main` worktree and save it as `receipts/ratchet-base-<sha12>.out` (exit, `live`, `baseline`, wall): the planning trial `receipts/ratchet-trial-all-edges-81192540bf.out` is a trial (`exit=1 live=2000 wall=192`), not the base, and is cited only as the sizing source.
- 0.3 Build `receipts/edges-decisions.tsv` (columns `suite, F, outcome, reason, accept_rows, commits_90d_F, declaring_suites`) from `receipts/worklist-edges.tsv`: confirm every non-retired pair is still a baseline line (`cut -f1,2` of the worklist, minus the header, against `scripts/ci-pr-affected-audit.baseline.tsv` with `grep -Fxcf`; expect 105 including the `kept-for-census` line, pin that line by content); recompute `commits_90d` for every F with `git log --since=90.days --oneline origin/main -- F | wc -l` and copy the output into `receipts/commits-90d.txt` (CTO row 6.2); list the AFFECTED array name of each suite via `_aff_label_map` and which are new (the trial needed 5 new blocks over all 104 edges; the slice needs at most 3: `ccla-representative-icla-7922`, `followthrough-varq-ban`, `tmpfs-guard`); check each is a registered label and no other live label maps to the same array name. Carry the numeric holds forward (`held-hot`, `held-brittle`) unless the recomputed number crossed 8 downwards. Pre-flag the hot-F exception candidates (the list under Research Insights, Measurements) and compute `declaring_suites` over ALL suites that would declare F including the PR4d consumers (for example `scripts/betterstack-query.sh` is also read by `betterstack-emitter-read`), so PR4d cannot break the 72 budget retroactively.
- 0.4 Recorder pass and re-tests (CTO row 1 and PR4b row 15A, one attempt each, no retry loop; evidence copied into `receipts/retest/`). The recording does not depend on the declared edges, so ONE recorder pass covers every candidate slice suite (the nine re-test suites and `boundary-prefix`, `required-checks-merge-group-coverage`, `preflight-check10-suite-integrity`, `scratch-residue`, `plugins/soleur`) and is the evidence 1.3 uses; there is no second post-commit pass. The re-test edges are the 11 edges of `ccla-representative-icla-7922`, `tmpfs-guard`, `redact-sentinel`, `ccla-add`, `fanout-suite-scope`, `git-data-rung2-evidence-capture` (2 edges), `gdpr-gate-self-test`, `followthrough-varq-ban` (2 edges), `zot-log-channel-probe`. The pass: `bash scripts/audit-suite-reads.sh record --mode check --only <labels> --max-load <N> --load-wait <S>` on the committed HEAD (the script requires a trusted ancestor of HEAD or `origin/main`; exit 3 means an unreliable row, 4 nothing recorded; `load_refused` is not a verdict, wait and run once more only if the load gate refused it, not otherwise); a clean recording (rc 0) in which F is opened in both recordings makes it a real read candidate. For the `declared-F-never-opened` ones, a suite-text proof: cite the `file:line` where the suite reads F at run time. An edge that stays unreliable or unproven is `held-unsure` with reason `recorder-unreliable-2` or `declared-F-never-opened-2`, goes to PR5 by name and is never re-tried.
- 0.5 Cut the slice once, after the 0.4 re-tests (the chain table lives in `receipts/edges-decisions.tsv`, column `chain`, with `suite_reveal` from `receipts/trial-all-edges-reveal-by-suite.tsv`; no separate slice file): sort the surviving re-tested edges and the out-of-slice suites ascending by the suite's round-1 reveal and cut at a running sum of 130 without skipping ahead. This is the only point where the line moves: a lost re-test frees headroom that the same ascending re-sort may fill in order (CTO row 6.6), and after Phase 1 starts there is no refill (a chain hold frees headroom that stays unused). Measured cut if all 11 re-tests survive: the 42 re-test pairs, `boundary-prefix` 13 (55), `required-checks-merge-group-coverage` 14 (69), `preflight-check10-suite-integrity` 15 (84), `scratch-residue` 16 (100), `plugins/soleur` 17 (117); the next suite makes 135 and goes to PR4d. Chains (re-measured, at most 59 each; suites sharing a revealed ref file share a chain, so `fanout-suite-scope` and `preflight-check10-suite-integrity`, which both reveal through `grok-pre-push-gate.sh`, are together; add a `shared_ref` check across chains before Phase 1 and assert it is empty): C1 = the eight other re-test suites (33) + `fanout-suite-scope` (9) + `preflight-check10-suite-integrity` (15) = 57; C2 = `boundary-prefix` 13 + `plugins/soleur` 17 = 30 (both reveal `scripts/lib/rule-metrics-constants.sh` through `.claude/hooks/lib/incidents.sh:71`); C3 = `required-checks-merge-group-coverage` 14 + `scratch-residue` 16 = 30. The trial's first-ref files were cross-checked at planning: `incidents.sh` is the only referencing file shared across the suggested chains, and merging its two suites into the CTO's suggested C2 + C3 would make 60, so the grouping above is the one that keeps every chain at 59 or less; re-run the check on the Phase 1 reports. Mark `held-ceiling` for any single edge that alone reveals 60 or more pairs and `held-pr5` for `grep-q-pipe-guard` and the birth-readiness edge; their measurement (31 edges, 68 pairs, 35 code; 1 edge, 151 pairs) is already in the committed trial tables, which `held-pr5` rows of `edges-decisions.tsv` point to.

### Phase 1 - chain by chain: declare, first report, pre-classify (RED for the chain)

For chain k (re-measure; do not trust the trial for the cut):
- 1.1 In a scratch worktree add the chain's edges as exact entries to the right `AFFECTED_<LABEL>_PATHS` (existing array: keep its order and keep `scripts/lib/test-affected-paths.sh` in it; new array (at most 3): a new block appended at EOF in name order as PR4b did, entries sorted, self entry `# THIS FILE`; a sibling's EOF append is resolved additively in 5.1; decision-challenges row 10). Do NOT add accept rows for THIS round; keep main's accept file and every accept row of earlier rounds. Run `ratchet --base origin/main --report <file>` (its exit is EXPECTED to be 1 `new-pair`, because no accept rows exist for this round yet; the criterion is the report content, not the exit); assert the suites with `new-pair` or `stale-line` are a subset of the chain's suites (a leaf-array spread or a label-map collision that touches a non-slice suite means the edge is held). Save the summary line and the counted `new-pair` total as `receipts/chain-<k>-round-<n>-first-report.txt` (one file per final shape; log a pre-hold number as one line inside it); the cap is judged on the post-pre-classification-hold shape (CTO row 6.1). If the total is 60 or more, bisect and move the other half to the next chain or to PR4d; if the running round-1 sum would pass 130, drop the highest-reveal suite from the slice.
- 1.2 Boundary lines come from `python3 -I scripts/ci-pr-affected-replay.py audit --root <scratch git worktree> --all-refs --accept <main's accept file>`, NOT from the ratchet report (it prints at most 3 `ref` lines per pair and a gap is accepted only when EVERY boundary line that names it has a row). Format: `ref<TAB>suite<TAB>path<TAB>file:line<TAB>anchor/ordinal<TAB>text`.
- 1.3 Pre-classify EVERY revealed pair in `receipts/reveals-decisions.tsv` (columns `suite, edges, path, ref file:line, anchor12, ref line text as of the base SHA, class (real-read|mention), line_kind, ref_commits_90d, evidence`); after every rebase or merge of main re-match each ref by `(suite, path, file, anchor12)` and re-derive only the ordinal. Bar (PR4b rows 4, 15A-15G, unchanged): real read = the line is in a file the suite executes or sources at run time and is an operand of source, exec, open, read, cat, grep, jq or a stat test, or sits in a sourced library; class b/c/d edges default to mention unless the suite extracts and re-reads the path; class a edges: read every ref line; the recorder is evidence only (opened in both recordings = real read, opened in one = hold, not opened in both = mention only if the static line kind is in the closed list, `code line in a file read only as text` needs the three conditions of row 15B); unsure holds the whole edge.
- 1.4 Hold rules per edge, after classification, written to `receipts/edges-decisions.tsv`: more than 10 accept rows for the edge (counted from the all-refs boundary lines); any accept row on a hot file (more than 8 commits in 90 days), evaluated on F, on the file that holds the mention line and on the chain's real-read file; or any unsure pair. The one exception (CTO row 4): a hot F with ZERO accept rows is declared if every revealed pair is a real read and `commits_90d(F) x declaring suites <= about 72` (with `scripts/cutover-inngest.sh` at 31 commits, at most two declaring suites); each real read the chain reveals gets the same test. Outcome values: `declare`, `held-brittle`, `held-hot`, `held-unsure`, `held-ceiling`, `held-pr5`, `out-of-slice-pr4d`, `held-cap`, `held-breaks-suite`, `kept-for-census`, `already-undrained`. If ZERO edges are `declare`, the index, baseline, accept file and runbook stay byte-identical to `origin/main`: skip 2.1-3.5 except the doc lint, commit only the receipts, plan and spec docs, post the holds table on #10959, skip the #10865 comment, and PR #11131 merges as docs-only (it is not a baseline PR; CTO row 5). Dry-run both numeric holds and the hot-F exception on the table once before building rows. Never accept a real read; never declare a prefix or glob.
- 1.5 Round n+1 (only if round n had real reads): add the real-read files as exact entries, re-run, save the receipt; the new-pair total must be under 30 and smaller than the previous round; at most 4 rounds; PR-wide cumulative (round 1 of every chain plus every later round, accepted mentions included) at most 150, with the later-round allowance `min(29, 150 - running)` checked as a running total in ascending chain order; round 1 summed over chains at most 130. A violation stops the chain: remove every edge whose real-read chain contributes an unresolved pair (trace by the `edges` column), re-run the chain from round 1 (only the final surviving shape counts), drop the highest-reveal chain first, and never refill the freed headroom; the leftover edges are `held-cap` or `out-of-slice-pr4d`.
- 1.6 Shared helpers: if 3 or more labels spread the same helper read, use the existing `_CLOSURE_LEAF_SCRATCH_ROOT` or `_CLOSURE_LEAF_INCIDENTS_LIBS`; otherwise literal entries; multiply a shared-array reveal by the number of spreaders for the cap; never edit a `_CLOSURE_LEAF_*` array; a label whose array name is shared with a non-slice label is held.

### Phase 2 - one green commit per merged cycle on the final base

- 2.0 The stop-line number of record is the sum over chains of the post-hold round-1 totals of 1.1 (at most 130, every suite named in a report a slice suite); no combined re-run. The chain commits go in ascending chain id; chains share no ref file (0.5), so a later chain's reveal does not depend on an earlier commit.
- 2.1 Generate the accept rows from the all-refs output of the LAST round's audit (ordinals can shift when a declared file is read): suite, path, anchor, ordinal, `false-positive: <line kind>: <one clause naming the file:line>`; rows per pair equal that pair's `ref` line count; insert in the accept file's existing order (check `sort -c` before relying on an order); no TAB in the reason.
- 2.2 GREEN: `git checkout origin/main -- scripts/ci-pr-affected-audit.baseline.tsv`, then `python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > scripts/ci-pr-affected-audit.baseline.tsv.new && mv scripts/ci-pr-affected-audit.baseline.tsv.new scripts/ci-pr-affected-audit.baseline.tsv` (on a non-zero exit remove the `.new` file: `census-degraded` is rc 2 and leaves it empty), then `git add -- <baseline> <accept file> <index> <every new tracked file>` (the checkout staged main's copy, and the audit census is `git ls-files`), then `ratchet --base origin/main` exits 0 with `live == baseline`; print its wall time. After each commit re-run `ratchet` from a detached clean worktree of that commit and `git diff --exit-code HEAD -- <baseline>`.
- 2.3 Per commit: `ratchet`, `bash scripts/test-affected-kb-consumers.test.sh` and `bash scripts/lib/inngest-probe-row.test.sh`; an edge that breaks another suite is held like a revealing edge.
- 2.4 A tree is committed only if `ratchet` exits 0 on it: a chain whose round n reveals real reads is committed once, at its fixpoint: one commit per surviving chain (at most 3) plus the docs commit of 4.1, never a red intermediate commit; WIP commits before a long wait contain receipts and docs only, never an index, baseline or accept edit that is not ratchet-green; "additions only" for the accept file holds against `origin/main`; commit by explicit pathspec; the message records real vs accepted vs held counts and the running PR-wide totals. On a conflicting rebase rebuild from the saved edge and accept lists on current main, commit once, record the deviation in `decision-challenges.md`.

### Phase 3 - fixpoint and verification

Commit the last round first: the three-dot diffs read HEAD only. Use files, not `grep -c < <(...)` forms.
- 3.1 Fixpoint: the post-final `audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv` equals the last cycle (`refs`, `files_read`, `gap_refs`, `accepted`, `stale`), `gap_refs` equals `wc -l` of the baseline, `stale=0`, the last ratchet marker reads `exit=0 reason=pass`, the final reveal is 0.
- 3.2 Prune-only: `git diff origin/main...HEAD -- scripts/ci-pr-affected-audit.baseline.tsv > <scratch>/bdiff`, at least one `-` line and no `+` line; the removed lines (`LC_ALL=C comm -23 <(git show origin/main:scripts/ci-pr-affected-audit.baseline.tsv | sort) <(sort scripts/ci-pr-affected-audit.baseline.tsv)`) equal the `declare` rows, any extra drained line (a shared-array spread or the non-injective label map) is explained; `scripts/lib/inngest-probe-row.test.sh` untouched and the kept-for-census pair present by content.
- 3.3 Scope: `git diff --name-only origin/main...HEAD` lists no test file, workflow, `scripts/test-all.sh`, ADR, `required-checks.txt`; the added lines of the index contain no `glob:`, no `ALWAYS_ON`, no entry ending in `/"` and no new comment line; the accept diff is additions only.
- 3.4 Replay suite detached: `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` (about 17 minutes); it hard-codes no count of the real baseline.
- 3.5 Full gate detached (non-blocking, started before the PR leaves draft; bound by PR4b row 7 and runbook section 7, and not cut on review: CI's `test` context is the merge gate): kill own stale runs by PID first, `bash scripts/test-all.sh --capacity`, then `SOLEUR_ALLOW_FULL_GATE=1 TC_LOCK_TIMEOUT=14400 TC_RUNTIME_CEILING_S=39600 bash scripts/test-all.sh --affected` (touching the index is a runner change: it degrades to the full battery and queues behind sibling sessions for hours, `AFFECTED_FALLBACK reason=runner-changed`). Record the rc from the run's own rc file (rc 0, not rc 6 a deferral). CI's required `test` context on the PR is the merge gate (runbook section 7); if the local gate has not finished when CI is green, the PR body says `local full gate: not finished at <time>, CI test context is the gate`. Re-run after a rebase that moved the index, `test-all.sh` or a suite.
- 3.6 `bash scripts/test-all-affected.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, shellcheck on the index and `scripts/markdown-lint.sh` on the changed docs, on the final tree.
- 3.7 Quote the final local `ratchet` wall time (2.2) next to the base wall of `receipts/ratchet-base-<sha12>.out` (hosted job cap 5 minutes, provisional ceilings 210 s and 270 s). No hosted-job lookup.

### Phase 4 - documentation and handoff

- 4.1 Runbook section 7 (`knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`), committed as the last docs commit, after the final declared count is known and before Phase 3 verification (so the verified HEAD is the merged HEAD). With zero declared edges the runbook is NOT edited (CTO row 5: only receipts and docs). With N declared edges: (a) the accept-row scope statements `PR4b and PR4c` (today at the PR4 paragraph under "Ratchet red on a PR or queue entry", the baseline-conflict recipe, the rubric bullets "A mention is not declared" and "Never in a drain PR") read "PR4b, PR4c and at most one PR4d" only if N is at least 10, otherwise they stay and the sentence "anything left goes to PR5 (#10861)" is added; (b) the "The drain claim" sentence "its continuations PR4b and PR4c (both tracked on #10959)" and the "take them first" sentence of the PR4 paragraph name the same set; the rubric's "leave it for PR4c or PR5" reads "PR4c, PR4d or PR5" under the same condition; (c) "Ambiguous pairs and big files" gains the hot-F-with-zero-rows exception and its 72 budget; (d) the "PR4b worklist" bullet gains a pointer to the PR4c outcome table (`receipts/edges-decisions.tsv` under the archived PR4c spec directory), the reason codes `recorder-unreliable-2`, `declared-F-never-opened-2`, `held-pr5`, `out-of-slice-pr4d` and the series end ("PR4d is the last drain PR; anything left goes to PR5"). Counts via `wc -l`, never a dated prose number. Check with `grep -nE 'PR4b and PR4c|PR4c or PR5' <runbook>` printing nothing when N is at least 10.
- 4.2 Update the body of #10959 (remaining-edge list by reason code, PR4d eligibility, the series end) and comment on #10861 (PR5 receives by name: `grep-q-pipe-guard` with its measurement, `git-data-birth-readiness-gate`, the 43 whole-tree readers with the PR4b row 6 policy, every `bulk-reader` and still-unproven recorder hold, any PR4d leftover). 
- 4.3 PR body (`Ref #10959`, `Ref #10448`, `Ref #9729`; no closing keyword): counts via `wc -l`, the chain table and per-chain first-report totals and the stop-line outcome, accept rows by line kind, held edges by reason code, re-test results, recorder suites and results (or `recorder: not run`), yield, the window consequence, the local gate state (3.5), the series end, the holds.

### Phase 5 - ship (no operator step)

- 5.1 Before arming merge: `git fetch origin main` and `git merge origin/main` (the accept file and the index conflict when sibling PRs append rows; resolve additively for the index, and for the baseline and the accept file take main's copy, regenerate the baseline with the prune-only tool, re-derive accept rows from the audit and re-insert in order, never hand-merge); re-run 2.2, 3.1 and the two edge-batch suites (a rebase that touched the index, `test-all.sh` or a suite also needs 3.4 and 3.5); list duplicate `AFFECTED_*_PATHS` names (`grep -oE '^AFFECTED_[A-Z0-9_]+_PATHS=\(' scripts/lib/test-affected-paths.sh | sort | uniq -d` prints nothing); re-acquire the lease; push; mark ready; `gh pr merge 11131 --squash --auto`. After arming, NEVER push, sync or update the branch (a push dequeues it, `ship/references/queue-mode.md`); while queued, re-acquire the lease at intervals shorter than its window and keep the branch pushed. One re-enqueue on a flaky e2e dequeue, a second reported with the run URL.
- 5.2 After merge: post on #10865 the merge SHA, `merged_at`, the oracle inputs this PR touched (index, baseline, accept file), and the sentence "units before this SHA ran against the pre-drain oracle; the window count restarts here", plus the instruction that the closer recomputes the merge_group count and the wall p95 and maximum over units created after `merged_at` (the probe excludes oracle-touching PRs from pull_request counts but not merge_group units and does not enforce the restart, #10949). Skip the comment in the zero-edge case. `gh pr list --label s4-drain --state open` is empty (claim released); #10959, #10448, #9729 stay open. If PR4c declared at least 10 edges, PR4d may be filed as the last drain PR (a new draft PR under the same claim, tracker #10959); otherwise #10959 gets the closing handoff to PR5. The compound step (the re-test pattern, accept-row churn, lease reaping in the queue) runs at ship via `soleur:compound`.

## Files to Edit

- `scripts/lib/test-affected-paths.sh` (runner trigger: exact entries in existing `AFFECTED_*_PATHS` arrays and up to 3 new blocks appended at EOF; no comment lines; no `_CLOSURE_LEAF_*` edit).
- `scripts/ci-pr-affected-audit.baseline.tsv` (shrinks only, via `ratchet --print-baseline`, in the same commit as each round).
- `scripts/ci-pr-affected-audit.accept.tsv` (additions only; an oracle input, so the job prints the non-blocking `oracle-inputs-changed` notice).
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (section 7, 4.1).
- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4c-held-back-edges/decision-challenges.md` (exists; extended only if the work phase needs a new ruling).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4c-held-back-edges/tasks.md`.
- In `receipts/` of that directory: `edges-decisions.tsv` (with `chain`, `shared_ref`, `extra_drained` columns), `reveals-decisions.tsv`, `commits-90d.txt`, `ratchet-base-<sha12>.out`, `retest/` (recorder output and suite-text proofs), `chain-<k>-round-<n>-first-report.txt`; archived at ship.
- Already created by this planning run: `receipts/worklist-edges.tsv`, `receipts/trial-all-edges-reveal-by-suite.tsv`, `receipts/trial-all-edges-new-pairs.tsv`, `receipts/ratchet-trial-all-edges-81192540bf.out`.
- NOT edited: any test file (including `scripts/lib/inngest-probe-row.test.sh`), `scripts/test-all.sh`, `scripts/ci-pr-affected-replay.py`, `scripts/audit-suite-reads.sh`, any workflow, probe, ADR, `required-checks.txt`, ruleset or variable.
Files verified: every path above exists on `origin/main` (`git ls-files`) except the ones listed under Create and the planning-run receipts.

## Consumer of the declared lists

A declared entry is inert unless something reads it for the diff shape in question. The per-label array is resolved by name in `scripts/test-all.sh` through `_m="AFFECTED_$(_aff_label_map "$_l")_PATHS"`, each entry is minted into an anchored edge by `_affected_add_edge` and unioned with the derived edges, and the selector's `AFFECTED_SELECTED` rows (`--print-selection --paths=<path>`) are what the audit and the ratchet read. An accept row is read only by `load_accept` / `judge_rules` in `scripts/ci-pr-affected-replay.py` (`--accept FILE`; the ratchet passes the tracked accept file), which exempts a pair when EVERY boundary line that names it has a row and marks a row stale when the pair is no longer a gap, the anchor is not live, or the path is untracked. No suite reads the accept file.

## Sibling PR Overlap

Open PRs touching the same files (`gh pr list --state open --json number,title,files`, filtered on `test-affected-paths|ci-pr-affected-audit`, 2026-10-26): #11124 (WIP gitleaks pre-push), #11119 (shard the main-health-monitor tests step), #10926 (npm-publish SIGPIPE), #10893 (git-commit-secret-scan) each edit the index and/or the baseline or accept file, so they move the live set and conflict on the accept file's tail and the index's EOF. Mitigation: one drain PR at a time (the `s4-drain` claim); new array blocks are appended at EOF as in PR4b; resolve index conflicts additively; take main's baseline and regenerate with the prune-only tool; insert accept rows in order; list duplicate `AFFECTED_*_PATHS` names after every merge of main; re-run the overlap loop and `git merge-tree` right before the push in 5.1.

## Open Code-Review Overlap

#8800 (test fixture: census sandbox shares inodes/symlinks with live repo) names `scripts/lib/test-affected-paths.sh`: Acknowledge, a different concern (a census-sandbox write-through hazard; the planning trial ran in a detached scratch worktree and removed it). No open code-review issue names the baseline, the accept file, the runbook, `scripts/audit-suite-reads.sh` or `scripts/ci-pr-affected-replay.py`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Next unit: PR4c (work issue #10959), the remaining held-back edges listed in the PR4c worklist section of the #10959 body" | Phases 0-3; slice per CTO row 1 | mapped (partial by ruling: the slice is a subset at the 130 line, the rest is PR4d/PR5 by name) |
| 2 | "declare exact-file edges only where a suite really reads or executes the file" | 1.3, 1.4 | mapped |
| 3 | "shrink the baseline only via `ratchet --print-baseline`, run to a fixpoint" | 2.2, 3.1, 3.2 | mapped |
| 4 | "honour the CTO stop line (round 1 under 60 pairs per chain and at most 130 summed, later rounds under 30 and strictly shrinking, at most 4 rounds, cumulative at most 150) with reveals pre-classified" | 1.1-1.5, 2.0 | mapped |
| 5 | "use the read recorder (scripts/audit-suite-reads.sh) as classification evidence only" | 0.4, 1.3 | mapped |
| 6 | "take every technical fork to the CTO agent (soleur:engineering:cto) and record `Ruled by CTO agent`" | decision-challenges.md rows 1-6 | mapped |
| 7 | "Use `Ref`, not `Closes`" | 4.3 | mapped |
| 8 | "Before arming merge, merge origin/main ... keep the worktree lease alive while waiting in the merge queue" | process rules, 5.1 | mapped |
| 9 | "Holds stay in force: no CI_PR_AFFECTED, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no flip PR" | Non-Goals, row 9 | mapped (held) |
| 10 | "On merge, comment the merge SHA on #10865 (window restarts)" | 5.2 | mapped |
| 11 | "Practical notes from PR4b: ... the full local affected gate queues for hours ... CI is the real gate; ... hooks deny ..." | process rules, 3.5 | mapped |
| 12 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/<branch>/decision-challenges.md" | decision-challenges.md | mapped |
| 13 | "draft PR already open: #11131, label s4-drain claimed, mirror comment posted on #10448" | 0.1 (verify, no re-claim) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| the slice, chains and the 130 line | "round 1 under 60 pairs per chain and at most 130 summed" | asked |
| the re-test phase 0.4 for the 11 held edges | "the remaining held-back edges listed in the PR4c worklist section of the #10959 body" | asked (CTO row 1 + PR4b rows 15C/15E assign the re-tests to PR4c) |
| accept rows with the edge | "declare exact-file edges only where a suite really reads or executes the file" (mentions are the complement the stop line pre-classifies) | asked (PR4b row 1 amendment, scope extended by CTO row 3) |
| hot-F-with-zero-rows exception | — | inferred — justification: CTO row 4; a declaration is not anchor-keyed, and without it every hot real-read edge stays baselined |
| PR4d gate (10 declared edges) and the series end | — | inferred — justification: CTO row 3; the brief asks for the remaining edges, which do not fit one PR under the stop line |
| WIP commit + lease re-acquire before waits | "keep the worktree lease alive while waiting in the merge queue (it was reaped last time)" | asked |
| runbook wording edits | "Spec and rubric: runbook ... section 7" (the rubric's home; five statements name the accept-row scope) | asked |

### Split Assessment

- Subsystems touched: 2 (CI machinery under `scripts/`, knowledge-base docs).
- Planned files: 4 edited + 5 to 8 created; estimated changed lines: about 34 index lines plus up to 3 new blocks, up to 34 baseline lines removed, an estimated 20 to 60 accept rows.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines. None met.
- Recommendation: single PR; the CTO line at 130 is the split of PR4c from PR4d and PR5.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing today, because the lever (`CI_PR_AFFECTED`) is unset and locked and the ratchet job is advisory; after a later, separately authorized flip, a pull request that changes a file a test suite reads could merge without that suite having run when a revealed pair was wrongly accepted as a mention (a false negative: an accept row on a file the suite really reads), or every PR could pay for suites it does not need (an over-declared edge).
The accept rows are the risk of this PR: the ratchet does not verify them and no required review exists, so the classification table with the cited line per row, the recorder evidence on the suites with the most rows, the hot-file and 10-row holds, and hold-on-doubt are the controls.
**If this leaks, the user's [data / workflow / money] is exposed via:** no data path: the work reads tracked repository text and runs local suites under a scrubbed environment with no network namespace; the exposure is CI minutes (money) if edges are over-declared once the lever flips.
**Brand-survival threshold:** aggregate pattern

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** five technical forks and the extra acceptance criteria ruled on 2026-10-26 (slice composition, `grep-q-pipe-guard`, leftover disposition and the PR4d gate, the hot-file clarification, the yield floor); see Technical Rulings. No product, marketing, legal, finance, operations, sales or support implication: internal CI index maintenance, no user-facing surface, no data processing change, no new vendor or spend. Product/UX gate: none (no `components/`, `app/**/page.tsx` or layout file in Files to Edit/Create).

## Architecture Decision (ADR/C4)

No new architectural decision: the drain is ADR-276's own tool (amendment item 2 already authorizes accept rows in a drain); the extension of the accept-row allowance to a single PR4d (CTO row 3) is a scoped operating rule recorded in the decision log and the runbook, not an architecture change, and ADR-276 is not edited (PR5 appends the closing Stage-status line).
C4: no impact. Checked against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: no external human actor, external system, data store or actor-to-surface access relationship changes (the index, the baseline, the accept file and the audit script are repository-internal CI machinery inside the CI container); derived cardinalities in edge prose do not move because no workflow, job, monitor or heartbeat is added or removed (`plugins/soleur/test/c4-count-parity.test.sh` is part of the full battery in 3.5 and must stay green).

## Observability

The change is CI index data under `scripts/`; it adds no emitter. The signal is the existing advisory job's marker line.

```yaml
liveness_signal:
  what: the marker line SOLEUR_PR_AFFECTED_RATCHET exit/reason/live/baseline printed last by the affected-index-ratchet job (exit 0 reason pass means live equals baseline)
  cadence: every pull_request and merge_group run, drafts and bots included
  alert_target: the job's own ::error annotation and a red check on the PR check list (advisory until PR3b; no pager)
  configured_in: .github/workflows/ci.yml job affected-index-ratchet (unchanged by this PR)

error_reporting:
  destination: GitHub Actions job log, step summary and the ::error title=affected-index-ratchet annotation
  fail_loud: exit 1 (a verdict about the tree) or exit 2 (infrastructure) renders the job red with the reason token; no silent path

failure_modes:
  - mode: an accept row goes stale or an accepted pair re-appears after an edit of the mention line in the revealed file, or after a sibling merge or a rebase
    detection: the marker reads exit=1 reason stale-accept or new-pair on the next pull_request or merge_group run; merge_group fails closed with max_entries_to_merge 1
    alert_route: red check on the PR and the queue entry; fix-forward owner is the author who changed the line, due within one working day (ADR-276 item 8)
  - mode: a revealed pair accepted as a mention that the suite really reads (false negative once the lever flips)
    detection: not visible to the ratchet (declared limit); bounded before merge by the line-cited classification table, hold-on-doubt, the 10-row and hot-file holds and the recorder pass
    alert_route: PR review of receipts/reveals-decisions.tsv; PR5 demotion of any accept row with evidence
  - mode: job wall time grows because more declared edges raise files_read
    detection: marker exit=2 reason timeout or a wall above the 210 s p95 and 270 s maximum ceilings of the observation window probe
    alert_route: Phase 3.7 timing check in the PR body and the ceiling re-rule owed to the CTO agent at the close of the window

logs:
  where: GitHub Actions run logs of the affected-index-ratchet job, plus the --report file in the step summary
  retention: the repository's Actions log retention (default 90 days); the classification table and the receipts persist in the spec directory

discoverability_test:
  command: grep -o -e 'SOLEUR_PR_AFFECTED_RATCHET exit' scripts/ci-pr-affected-replay.py
  expected_output: SOLEUR_PR_AFFECTED_RATCHET exit
```

## Test Scenarios

The Acceptance Criteria are the single list of checks; the scenarios name only the controls that are not restated there.

1. Hold rules (1.4), dry-run once on the table before building rows: an edge with 11 accept rows, an edge with one accept row on a file with 9 commits in 90 days, and a hot F with zero accept rows (`commits_90d x declaring suites` at 73 held, at 62 declared) are classified as the CTO rows say.
2. The RED report of 1.1 (the uncapped `--report` lists `new-pair` for the revealed pairs and `stale-line` for exactly the declared edges' pairs) is the control that each edge is what drains its pair; the audit's own `not-a-gap` / `anchor-not-live` / `stale` verdicts and the replay suite already prove that an unreachable accept row is refused, so no scratch experiment re-tests it.

## Acceptance Criteria

### Pre-merge

- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` exits 0 with `live == baseline`; the baseline's line count is smaller than on the merge base by the number of `declare` rows plus the explained extra drained lines (column `extra_drained` of `receipts/edges-decisions.tsv`; a shared-array spread, the non-injective label map, or a later-round real read that coincides with an already-baselined pair) (quote the four numbers: `git show origin/main:scripts/ci-pr-affected-audit.baseline.tsv | wc -l`, the branch count, the `declare` count, the `extra_drained` count). With zero `declare` rows the index, baseline and accept file are byte-identical to `origin/main`.
- [ ] The baseline diff is prune-only by the file-based check of 3.2 (at least one removed line, no added line); the file is C-locale sorted with a final newline.
- [ ] The first report of each cycle, after pre-classification holds and before accept rows, is saved as a receipt; each chain's round 1 is under 60, later rounds under 30 and strictly shrinking, at most 4 rounds, round 1 summed over chains at most 130, the PR-wide cumulative (accepted mentions included) at most 150; the chain table (suite, edges, measured round 1, chain id) and the stop-line outcome are in the PR body.
- [ ] The final audit (`audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv`) equals the last cycle: zero new pairs, zero stale baseline lines other than the drained pairs, zero stale or unused accept rows; audit line and last ratchet marker pasted.
- [ ] `receipts/reveals-decisions.tsv` lists each revealed pair as `real-read` or `mention` with the `file:line` cited; accept rows equal the `mention` rows, one row per boundary line (rows per pair equal that pair's `ref` lines); no accepted pair is a real read; held edges are in `receipts/edges-decisions.tsv` with the deciding count and reason code; `receipts/commits-90d.txt` carries the recomputed counts; each re-test of 0.4 has its evidence in `receipts/retest/` and a failed one the code `recorder-unreliable-2` or `declared-F-never-opened-2`; the 0.4 recorder pass and its results are listed (or `recorder: not run, <reason>`).
- [ ] Every new accept row has a reason naming the line kind from the closed list; no edge has more than 10 accept rows; no accept row sits on a hot file (more than 8 commits in 90 days: F, the mention-line file and the chain's real-read file); any hot declared F has zero accept rows, only real reads and `commits_90d x declaring suites <= about 72`; the accept-file diff is additions only.
- [ ] The PR touches no test file, adds no `glob:`, no directory prefix, no `ALWAYS_ON_SUITES` entry, no whole-tree reader edge and no new comment line in the index; `scripts/lib/inngest-probe-row.test.sh` is untouched and the `tests/scripts/inngest-host-dark-gate` -> `scripts/lib/inngest-probe-row.sh` baseline line is still present (`grep -Fx`); no `grep-q-pipe-guard` or birth-readiness edge is declared.
- [ ] `git diff --name-only origin/main...HEAD` (three dots) lists only the index, the baseline, the accept file, the runbook, this plan and files under `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4c-held-back-edges/`; no variable, lock, ruleset, `required-checks.txt`, workflow, probe or ADR file.
- [ ] CI's `test` context green; the replay suite rc 0 (local, detached); the local full affected gate state is stated (rc 0 from its rc file, or `not finished at <time>, CI test context is the gate`); orphan census, `test-all-affected.test.sh`, shellcheck and `scripts/markdown-lint.sh` rc 0; `grep -oE '^AFFECTED_[A-Z0-9_]+_PATHS=\(' scripts/lib/test-affected-paths.sh | sort | uniq -d` prints nothing.
- [ ] Runbook section 7 edited as in 4.1 (`grep -n 'PR4b and PR4c' <runbook>` prints nothing); #10959 body updated with the remaining-edge list by reason code, PR4d eligibility and the series end; #10861 commented with the PR5 handoff; the PR body uses `Ref #10959`, `Ref #10448`, `Ref #9729` only (not `Closes`), lists yield and holds by reason, names what moves to PR4d or PR5 and why, states "PR4d is the last drain PR; anything left goes to PR5 (#10861)", restates the holds and the window consequence, and reports the final local ratchet wall.
- [ ] `origin/main` was merged into the branch immediately before arming merge (`git merge-base --is-ancestor origin/main HEAD` exits 0 at arm time), the lease file for this worktree existed at arm time, and no push followed the arming.

### Post-merge

- [ ] The merge SHA is commented on #10865 with the window-restart sentence (skipped in the zero-edge case).
- [ ] `gh pr list --label s4-drain --state open` is empty; #10959, #10448 and #9729 stay open.

## Rollback

The change is data (index entries, a pruned baseline, accept rows, docs). A plain revert is NOT a clean rollback: it re-adds the drained baseline lines, which the growth rule reads as `grown` on the revert PR itself (advisory red until PR3b, blocking after it), and it removes the accept rows together with the edges, which is consistent. The supported correction is forward: keep the edge (an extra edge only costs suite runs once the lever flips), or remove an edge together with its accept rows and re-baseline nothing. A wrongly accepted pair is corrected by declaring the edge (the accept row then reads `not-a-gap` stale and is deleted in the same PR). The lever is off, so no production behavior depends on the edges or the rows.

## Non-Goals

CI_PR_AFFECTED, the activation lock, PR D (#10414), PR3b (#10859), the evidence re-run, criterion (c), the flip PR, #10862, any `ratchet`, audit-reach or recorder change, any probe change (#10949), any `scripts/test-all.sh` edit, any test-file edit, any `glob:` or `ALWAYS_ON_SUITES` entry, the 43 whole-tree sweeps (PR5), `grep-q-pipe-guard` and `git-data-birth-readiness-gate` (PR5), `t5-skip-persistence-bound-7510`, `battery-tag-authorship` and `betterstack-emitter-read` (PR4d, or PR5), the remaining non-code pairs and mentions of PR5 (#10861), baseline deletion, a lease-renewal tool.
Deferred items are tracked: #10959 (PR4d eligibility, stays open), #10861 (PR5), #10949, #10862, #10859, #10414.

## Risks and Sharp Edges

- The `## User-Brand Impact` section is filled with a concrete artifact, vector and threshold; an empty or unfilled one fails `deepen-plan` Phase 4.6.
- A wrong accept is a false negative once the lever flips and no automated control checks it: the controls are the cited-line table, hold-on-doubt, the recorder, the 10-row and hot-file holds, and PR5's review of every accept row.
- Accept rows are brittle by design: an edit of a mention line turns the row stale AND the pair new on the editing PR (red until re-accepted); that is why hot files and edges with more than 10 rows are held.
- The trial total (475) is an all-at-once estimate: reveals deduplicate across suites that share a file and chain through real reads, so each chain is re-measured; do not cite the trial as a declared number. The trial attributes a shared ref file (for example `run-registered-suites.sh`) to each suite separately, and a pair counts once per (suite, path).
- The re-test pool depends on a recorder that already failed once for these suites: if every `recorder-unreliable` re-test fails, the slice shrinks (to about 25 edges and 75 pairs) and the one 0.5 re-sort may pull the next suites in ascending order (`t5-skip`, then `battery-tag-authorship`) up to the 130 line; nothing refills after Phase 1 starts.
- `plugins/soleur` is registered as `bun test plugins/soleur/` (`scripts/test-all.sh --enumerate-commands all`: `SUITE_COMMAND plugins/soleur bun test plugins/soleur/`), a whole-plugin test run. Its recorder pass may exceed `--timeout 600` or open more than 1000 files; either is a `bulk-reader`/unreliable verdict (PR4b rows 15C/15D) that holds its 5 edges (17 pairs) and shrinks the cut, after which the one 0.5 re-sort pulls the next suite in ascending order. Its edges are also the most likely to be hot (`test-infra-privileged-tier-census.sh` 19 commits).
- Duplicate `AFFECTED_*_PATHS` names after a merge of main silently re-open drained pairs (bash keeps the last assignment); the label-map is not injective (check collisions before adding a block).
- The audit scans every TRACKED file (`git ls-files`): stage the plan, tasks, receipts and runbook before the final `--print-baseline`, `ratchet` and audit runs; run the audit with main's accept file.
- A recorder run on a loaded host is refused (`load_refused`), not wrong; the recorder needs a committed HEAD (trusted ancestor).
- The probe does not enforce the window restart (#10949); do not claim it does.
- A reach-widening change is out; a read-set question is a different PR.
- Guard-contract and encryption-posture gates are not triggered: no check, lint, hook or workflow is added (the classification table is data) and no store or connection is introduced.
