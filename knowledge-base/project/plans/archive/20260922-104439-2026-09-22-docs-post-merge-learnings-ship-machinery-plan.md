---
title: "docs: post-merge learnings from the ship-machinery refactor (PR #8474)"
date: 2026-09-22
slug: docs-post-merge-learnings-ship-machinery
branch: feat-one-shot-post-merge-learnings-ship-machinery
issue: none
closes: none
type: docs
priority: p3
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# docs: post-merge learnings from the ship-machinery refactor (PR #8474)

## Enhancement Summary

**Deepened on:** 2026-09-22
**Sections enhanced:** 4 (Research Reconciliation, Observability (new), Sharp Edges, Acceptance Criteria cross-check)
**Research agents used:** git-history-analyzer (attribution), a verify-the-negative / self-audit sweep
(standard tier), plus the Phase 4.5-4.11 gates run directly.

### Key Improvements

1. **Phase 4.7 fired and is now satisfied.** `plugins/soleur/skills/ship/SKILL.md` counts as a plugin
   surface, not pure docs, so the plan now carries an `## Observability` block. Its probe
   (`grep -c -e 're-test by consumer, not by conflict' plugins/soleur/skills/ship/SKILL.md`) passes
   `plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh` (rc 0), contains no shell-active
   character, and prints `0` today and `1` after the edit.
2. **Every attribution was re-verified live.** #8384 added the test file (`9daf9f4683`). `3b1e46aa9`
   merged #8488 and `5d65dad50` merged #8484. `kind=wrong_branch` first appears in #8474's review
   commit `7d11be0f22`. #8500, #8502, #4856, #5840 and #8450 are all OPEN. The merge time is
   23:48:20Z. The transcript holds exactly one `gh pr merge 8474`, and it is `--squash --auto`.
3. **One citation corrected.** `e9c6ee9a4` is a PR-branch commit squashed into `97633e8e`, not an
   ancestor of `main`. The learning must cite it as "`e9c6ee9a4` on the PR branch (squashed into
   `97633e8e`)" so `git merge-base --is-ancestor` readers are not misled.
4. **"Four syncs" was ambiguous and is now "four cancelled heads"** throughout.

### New Considerations Discovered

- Halt gates 4.5 (network), 4.55 (downtime), 4.8 (PAT), 4.9 (UI), 4.10 (encryption) and 4.11 (guard)
  do not fire: no trigger tokens, no infra, no UI and no guard deliverable. 4.6 passes (threshold
  `none` with a scope-out; no sensitive path).
- No AGENTS.md rule IDs are cited, so there is no fabricated or retired ID risk.
- AC6's fence extraction yields 16 lines today, and AC7's grep lists exactly the 6 suites, both
  confirmed before implementation.

## Overview

PR #8474 (merged 2026-09-21T23:48:20Z as `97633e8e`) closed its session with three things it had
learned while getting merged, but had not written down: how a hand-resolved merge with a sibling PR
went wrong, how the resulting test break was caught late, and how the PR sat in a sync-and-retest
loop for most of an evening. This plan records them in the knowledge base.

Deliverables, all docs or single-bullet skill prose:

1. **One new learning** covering items 1 and 2 of the brief (they are one incident: the merge that
   broke the test, and why the break was found late).
2. **An addendum to the existing livelock learning** (`2026-06-02-auto-merge-livelock-fast-moving-main.md`)
   covering item 3, rather than a third livelock file.
3. **Two one-bullet skill sharp edges**, one per lesson, at the point where an agent would act:
   the ship Phase 7 DIRTY-exit bullet list (run every consumer suite after a hand-resolved merge) and
   the settle-then-admin-merge reference (what to do when the diff is NOT hatch-eligible).

No product code, no new rule in `AGENTS.md`, no new test or lint. #8500 is referenced only.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Reconciliation — Brief vs. Evidence

The brief was written from the session's closing summary. The transcript, the PR's commit list,
and the GitHub check-run API disagree with it in four places. The learnings must record what
happened, so the plan takes the evidence side.

| Brief says | Evidence | Plan response |
|---|---|---|
| "Breaking the loop took an admin-merge, which needs operator approval." | No admin-merge of #8474 happened. The agent offered one from cycle 5 onward (transcript: "The admin-merge option to break the livelock still needs your approval"), the operator never replied to it, and GitHub's queued auto-merge fired at 23:48:20Z, 5 s after the required `test` context concluded `success` on head `b93f5ad63` (23:48:15Z). The only `gh pr merge 8474` in the transcript is `--squash --auto`. | Record that the loop ended when a quiet window let one CI run finish, after ~8.5 h. The admin-merge was the available way out, and it was gated on operator approval because the diff carried code, so the hatch did not apply. |
| "Two sibling PRs ... needed real merges." | Three hand-resolved merges: `3b1e46aa9` (#8488: `rule-metrics.json`, `plan-sharp-edges.md`), `7c8a60222` (#8384 / ADR-235: `sync-pr-behind.sh`, `ship/SKILL.md`, the Phase 7 fixture, `INDEX.md`, `kb-tags.txt`), `5d65dad50` (#8484: `plan-sharp-edges.md` append). | Name all three; the incident is the #8384 one. |
| "Only the PR's own test file had been run." | After `7c8a60222` the agent ran the Phase 7 fixture (392/0) and **its own** `plugins/soleur/test/sync-pr-behind.test.sh` (29/0). Those are the suites of the conflicted files. The broken file, `plugins/soleur/scripts/sync-pr-behind.test.sh`, was **added by #8384 and merged cleanly**, so it was never in the conflict list (`git merge-tree --write-tree --name-only 3b1e46aa9 9daf9f468`). Both files share the basename `sync-pr-behind.test.sh`. | This is the sharper lesson for item 1: the conflict list is the wrong work-list. The consumer set is found with `git grep -l`, not from the conflicts. |
| "The fix cost one extra CI cycle." | The defect was pushed at 19:24:08Z (`7c8a60222`). `test-scripts (3/3)` was **cancelled** on that head and the next three (`922808ff6`, `5d65dad50`, `94b940efb`) because each sync push cancels the in-flight PR run (`ci.yml` `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`). It first concluded `failure` on `1e198ac00` at 23:10:37Z: **3 h 46 min after the push, with the shard cancelled on four heads**. The aggregate `test` context reported `failure` on every one of those heads anyway, because it runs `if: always()` and counts a cancelled shard as not-success. | Record that the livelock hid the red across four cancelled heads, and that a red `test` on a head whose shards were cancelled says nothing either way. The fix (`e9c6ee9a4`) itself took one more cycle. |

Held as stated: `e9c6ee9a4` is a 3-line change to `plugins/soleur/scripts/sync-pr-behind.test.sh`
that answers the `headRefName` query with the fixture branch, uncounted; the stub prints
`STUB-MISS: unexpected gh invocation` and exits 64 on anything else. The refactor added the head-branch
check (`kind=wrong_branch`, exit 12) to `sync-pr-behind.sh`. Issue #8500 is OPEN.

## Research Insights

**Premise Validation.** Checked every reference the brief cites. Held: merge `97633e8e` (merged
2026-09-21T23:48:20Z by `deruelle`); fix commit `e9c6ee9a4` (3 lines, `plugins/soleur/scripts/sync-pr-behind.test.sh`);
#8384 is ADR-235 and added that test file (`git log --diff-filter=A`); #8500 is OPEN; the
`kind=wrong_branch` head-branch check is in `sync-pr-behind.sh`. Stale or imprecise: the
admin-merge claim, the sibling count, "only the PR's own test file", and "one extra CI cycle". All
four are resolved in the Research Reconciliation table above, from the GitHub timeline and
check-run APIs plus a bounded `jq` read of the transcript.

**Property List** (what the PR must leave true):

- P1. An agent resolving a merge with `main` learns that a sibling-added test can break without
  conflicting, and has a command that finds it.
- P2. After changing a script, or merging `main` into a branch that changed one, an agent runs every
  test that references it before pushing.
- P3. An agent in a BEHIND livelock on a code-bearing PR knows the hatch does not apply, that the
  admin-merge is the operator's call, that cancelled shards hide failures, and how this one actually
  ended.
- P4. The #8458 absent-required-check merge is referenced (post-mortem, #8500) and not re-fixed.

**Cut List:**

- New `AGENTS.md` rule → P2 → already covered by the sweep class in
  `2026-06-03-dispatcher-factory-new-import-sweep-all-exercising-test-files.md`; the missing piece is
  the trigger point (Phase 7 hand-resolution), which a skill bullet reaches without always-loaded cost.
- A third learning file for the livelock → P3 → `2026-06-02-auto-merge-livelock-fast-moving-main.md`
  already owns the class; extend it.
- Separate files for brief items 1 and 2 → P1, P2 → one incident, one causal chain; one file.
- A test/lint enforcing the sweep → P2 → out of scope (docs-only brief); no mechanism proposed.
- Any change to the `ADMIN-MERGE-READY` block → P4 → #8500 owns it.

**Relevant files:**

- `plugins/soleur/scripts/sync-pr-behind.sh` (the changed script), and its six consumer suites:
  `plugins/soleur/scripts/sync-pr-behind.test.sh`, `plugins/soleur/test/sync-pr-behind.test.sh`,
  `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, `plugins/soleur/test/harness.test.ts`,
  `plugins/soleur/test/pr-merge-poll.test.ts`, `plugins/soleur/test/workflow-fidelity.test.ts`.
- `lefthook.yml` `bun-test` (`skip: - merge`, full gate `scripts/test-all.sh`, which does register
  `plugins/soleur/scripts/*.test.sh`, so the suite was discoverable, just not run on a merge commit).
- `.github/workflows/ci.yml`: `concurrency.cancel-in-progress` true for `pull_request`; `test`
  aggregator `needs: [test-webplat, test-bun, test-scripts, web-platform-build]`, `if: always()`.
- `plugins/soleur/skills/ship/SKILL.md:2448-2450` (DIRTY exit + recurring-DIRTY bullet);
  `plugins/soleur/skills/ship/references/settle-then-admin-merge.md:18-26` (hatch classifier).
- `plugins/soleur/test/skill-body-budget.json`: ship ceiling 274000 bytes, current 261814.

**Institutional learnings (extend, don't duplicate):**

- `2026-06-02-auto-merge-livelock-fast-moving-main.md`: the livelock class, settle-then-admin-merge,
  docs-only case. Extended by Deliverable 2.
- `workflow-issues/kb-index-dirty-livelock-20260921.md`: DIRTY variant (INDEX.md); ADR-235 closed it.
- `2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md`: recurring DIRTY.
- `2026-06-03-dispatcher-factory-new-import-sweep-all-exercising-test-files.md`: consumer-sweep class (TS).
- `2026-09-21-every-gate-this-pr-added-failed-open-on-the-input-it-could-not-measure.md`: #8474's own
  compound learning. Covers the review findings, not the post-merge events; no overlap.
- `2026-09-21-a-conflict-starved-merge-ref-reads-as-ci-never-ran.md` and
  `2026-09-19-githubs-merge-ref-runs-your-prs-own-defect-against-it.md`: merge-ref CI surprises;
  neither covers a cleanly-merged sibling test.
- `knowledge-base/project/learnings/2026-08-02-the-retraction-pr-was-itself-over-claiming-and-its-counsel-signoff-certified-a-diff-that-no-longer-existed.md` §"A cancelled CI job is not automatically suspicious":
  the opposite reading error (treating a superseded cancel as a failure). Deliverable 2 must be
  consistent with it: a cancelled shard is *unobserved*, neither pass nor fail.
- Loose-stub learnings (`knowledge-base/project/learnings/2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success-and-my-stubs-were-looser-than-the-code.md`,
  `knowledge-base/project/learnings/2026-09-19-the-one-defect-lived-in-the-only-code-path-with-no-test-and-my-stub-answered-every-question.md`, `knowledge-base/project/learnings/2026-09-21-my-escrow-suite-stubbed-the-one-tool-that-would-have-refused-it.md`):
  the contrast case; here the strict stub did its job.

**Related issues:** #8500 (open, reference only), #8502 (open), #4856 and #5840 (merge queue),
#8450 (runner concurrency ceiling). No open `code-review` issue overlaps.

**Research decision:** strong local context; no external research. Transcript facts were read with
bounded `jq` extraction to a scratch file, never dumped.

## Proposed Solution

### Deliverable 1 — new learning (brief items 1 and 2)

**Path:** `knowledge-base/project/learnings/workflow-issues/2026-09-22-the-test-my-merge-broke-merged-cleanly-so-it-was-never-in-my-conflict-list.md`
(the date prefix is the day the file is written, not this plan's date; the slug is fixed).

Frontmatter follows the sibling `workflow-issues/` shape (`title`, `date`, `category`, `tags`,
`pr: 8474`, `issues`, `module`). Body sections: Problem, What happened (timeline table with the SHAs
and times from the reconciliation above), Root cause, Key insight, Prevention, Session Errors,
Related.

Content that must be in it, each tied to evidence already gathered:

- **The conflict list is the wrong work-list after a sibling merge.** A sibling PR can add a new
  consumer of a script your branch changed. That file merges cleanly, so it never shows up among the
  conflicts, and a re-test scoped to the conflicted files skips it. The consumer set is
  `git grep -l '<script-basename>' -- '*.test.*' '*test*.sh'` on the merged tree (the same command the
  skill bullet quotes). For
  `sync-pr-behind` that command lists six suites today (two `sync-pr-behind.test.sh` files with the
  same basename in `plugins/soleur/scripts/` and `plugins/soleur/test/`, `ship-phase-7-poll-fixtures.test.sh`,
  `harness.test.ts`, `pr-merge-poll.test.ts`, `workflow-fidelity.test.ts`).
- **The strict stub was right; the merge was wrong.** #8384's stub refuses any `gh` call it does not
  expect, which is what made the new `headRefName` lookup visible at all. A permissive stub would have
  answered it and hidden the contract change. Contrast with the loose-stub learnings
  (`knowledge-base/project/learnings/2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success-and-my-stubs-were-looser-than-the-code.md`,
  `knowledge-base/project/learnings/2026-09-19-the-one-defect-lived-in-the-only-code-path-with-no-test-and-my-stub-answered-every-question.md`).
  The fix taught the stub the new query and kept it out of `GH_CALLS`, so the call-count assertions
  kept their meaning.
- **No local net exists for a merge commit.** lefthook's `bun-test` full gate has `skip: - merge`
  (`lefthook.yml`, pinned by `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh`, ADR-183: no
  local run is the merge gate). After a hand-resolved merge, CI is the first thing that runs the
  suites, unless the agent runs them.
- **Under a BEHIND livelock, CI is not a working net either.** One sentence plus a link to the
  livelock addendum (Deliverable 2), which owns the detail: the shards were cancelled on four heads
  and the red went unobserved for 3 h 46 min.
- **What the bullet does not cover.** A clean automatic BEHIND sync can pull in a sibling's new
  consumer the same way, and no step re-tests it; say so, so the skill bullet is not read as full
  coverage.
- **Prevention (the rule the learning states):** after changing a script, or after merging `main`
  into a branch that changed one, grep for every test that references the script and run all of
  them before pushing. This is the merge-time case of the existing sweep class in
  `2026-06-03-dispatcher-factory-new-import-sweep-all-exercising-test-files.md`; the learning cites
  it rather than restating it, and the plan-time twin in
  `plugins/soleur/skills/plan/references/plan-sharp-edges.md` ("enumerate its consumers as everything
  that EXECUTES these bytes", #8028).

### Deliverable 2 — addendum to the existing livelock learning (brief item 3)

**Path:** `knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md`
(edit; insert one dated `## Recurrence: PR #8474, 2026-09-21` section before `## Session Errors`.
Frontmatter is left unchanged: its `related_pr: 4774` is scalar and #8474 is a PR, not an issue, so
the new section's body carries the reference instead of a new key).

Content:

- **Scale:** ready at ~14:02Z, merged at 23:48:20Z. Ten `origin/main` merges into the branch after
  review (15:14Z to 23:17Z), about eight of them forced by BEHIND/DIRTY during the merge poll. CI took
  60 to 70 minutes a run under a saturated runner queue (#8450 measures the ceiling: one PR's 67
  queued jobs against the org's 20-job budget). The 2026-06-02 case had an ~8-minute cycle.
- **What differed from 2026-06-02:** the diff carried code, so the settle-then-admin-merge hatch was
  not eligible, and an admin-merge needed the operator's approval. The agent offered it from cycle 5
  onward and kept syncing. No approval came. The loop ended when one run finished inside a quiet
  window and auto-merge fired.
- **New failure the livelock caused:** the `test-scripts (3/3)` shard was cancelled on four heads
  (`7c8a60222` and the next three), so a real red test went unobserved for 3 h 46 min (link
  Deliverable 1). A cancelled shard is unobserved, neither passed nor failed, and the aggregate
  `test` context reads `failure` on such a head whatever the code does; read the shard conclusions.
  This is consistent with `knowledge-base/project/learnings/2026-08-02-the-retraction-pr-was-itself-over-claiming-and-its-counsel-signoff-certified-a-diff-that-no-longer-existed.md`
  ("a cancelled CI job is not automatically suspicious") and with ship Phase 7, which already lists
  `cancelled` jobs beside failures.
- **The separate admin-merge:** earlier the same day, #8458 was admin-merged while the ruleset-required
  `test` context did not yet exist. That is the post-mortem
  `knowledge-base/engineering/operations/post-mortems/admin-merge-required-check-absent-postmortem.md`
  and open issue #8500. Reference only; do not restate or re-fix.

### Deliverable 3 — two one-bullet skill sharp edges

a. `plugins/soleur/skills/ship/SKILL.md`, Phase 7 **DIRTY exit** bullet list. Anchor on the text,
   not a line number: insert directly after the bullet that begins
   `- **A DIRTY that recurs on every landing` and before the paragraph that begins
   `This complements the PreToolUse hook`. One bullet, under 450 bytes:

   > - **After a hand-resolved merge, re-test by consumer, not by conflict.** A sibling's new test
   > merges cleanly, so it is not in the conflict list, and the pre-commit full gate skips merge
   > commits (`lefthook.yml` `bun-test` `skip: merge`). For every script your branch changes
   > (`git diff --name-only origin/main...HEAD`), run each suite
   > `git grep -l '<script-basename>' -- '*.test.*' '*test*.sh'` lists before pushing. **Why:** #8474 —
   > see `<Deliverable 1 path>`.

b. `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`, one sentence appended to the
   paragraph "It fails closed: a failed fetch or diff, or an empty diff, prints `NOT eligible`."
   (anchor on that text):

   > On a `NOT eligible` diff, an admin-merge is a merge-authority decision that only the operator
   > makes, never the agent; stay on the normal path meanwhile (#8474 ran about eight syncs this way;
   > see `2026-06-02-auto-merge-livelock-fast-moving-main.md` §Recurrence).

   Plan review cut the earlier draft's "ask the operator once, with CI time and `main` velocity"
   policy and its cancelled-shard sentence: the ask is new admin-merge policy for code diffs that the
   brief did not request (and the #8474 agent already offered the choice unprompted), it needed
   once-per-PR and headless arms to avoid becoming an hourly nag, and the cancelled-shard reading
   rule belongs to the livelock addendum, since this reference only loads at `hatch_check`.

   The `ADMIN-MERGE-READY` block (#8474's fix for the #8458 incident) is the existing mechanism; the
   paragraph points at it and changes nothing in it (#8500 owns the shared script).

## Files to Edit

- `knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md` (append a section)
- `plugins/soleur/skills/ship/SKILL.md` (one bullet in Phase 7 DIRTY exit)
- `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` (one sentence appended to the `NOT eligible` paragraph)

## Files to Create

- `knowledge-base/project/learnings/workflow-issues/2026-09-22-the-test-my-merge-broke-merged-cleanly-so-it-was-never-in-my-conflict-list.md`

## Open Code-Review Overlap

None. Checked the 71 open `code-review` issues against `plugins/soleur/skills/ship/SKILL.md`,
`settle-then-admin-merge.md`, `2026-06-02-auto-merge-livelock-fast-moving-main.md` and `sync-pr-behind`.

## Non-Goals

- Re-fixing the #8458 absent-required-check admin-merge. #8500 tracks the shared script.
- A new `AGENTS.md` rule. The consumer-sweep class already exists in learnings, and the trigger point
  is the Phase 7 DIRTY path, which the skill bullet covers without spending always-loaded budget.
- A test or lint that enforces the consumer sweep, a merge queue (#4856), or CI concurrency changes
  (#8450). All exist as their own issues.
- Changing `ci.yml`'s aggregate `test` job so a cancelled shard reads differently. Out of scope for a
  docs PR; the addendum records the reading rule instead.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The worst case is an agent
  following a wrong prose instruction in ship Phase 7 (for example running a grep that misses a
  consumer suite) during a later PR's merge, which is the status quo this plan improves.
- **If this leaks, the user's data is exposed via:** no vector. The diff is learnings and skill prose;
  it quotes SHAs, PR numbers and CI timings from a public repo, and no transcript content beyond
  those.
- **Brand-survival threshold:** `none`

`threshold: none, reason: the diff is knowledge-base prose and two skill-instruction paragraphs; it touches no code path, schema, credential or user data.`

## Observability

The Files-to-Edit list includes `plugins/soleur/skills/ship/SKILL.md` and a ship reference, which
count as plugin surfaces for deepen-plan Phase 4.7. The change is instruction prose read by an
agent. It runs no process and emits no events, so its only observable state is whether the text is
present in the files agents load.

```yaml
liveness_signal:
  what: "the new DIRTY-exit bullet is present in the ship skill an agent loads at Phase 7"
  cadence: "per ship run (the skill is read fresh each session)"
  alert_target: "CI test-scripts shard (ship-phase-7-poll-fixtures, workflow-fidelity) and markdown-lint on the PR"
  configured_in: "plugins/soleur/skills/ship/SKILL.md (DIRTY exit bullet list)"
error_reporting:
  destination: "GitHub Actions check runs on the PR (required `test` context)"
  fail_loud: "a red test-scripts or test-bun shard naming the suite that reads the edited prose"
failure_modes:
  - mode: "the bullet is dropped or rewritten by a later sibling merge in ship/SKILL.md"
    detection: "discoverability_test below returns 0 instead of 1"
    alert_route: "the reviewer of the PR that drops it (diff shows the removed line)"
  - mode: "the edit pushes ship/SKILL.md past its byte ceiling"
    detection: "scripts/lint-skill-body-budget.py --base origin/main exits non-zero in CI"
    alert_route: "PR author, via the failing check"
logs:
  where: "git history of plugins/soleur/skills/ship/SKILL.md and the PR's check-run logs"
  retention: "git history is permanent; GitHub Actions logs 90 days"
discoverability_test:
  command: "grep -c -e 're-test by consumer, not by conflict' plugins/soleur/skills/ship/SKILL.md"
  expected_output: "1"
```

## Acceptance Criteria

- [ ] AC1: the new learning exists at the Files-to-Create path, has YAML frontmatter with `title`,
  `date:` (the write date), `category`, `tags`, `pr: 8474`, and covers each content point under
  Deliverable 1. Verify, expecting no output:
  `for p in 'merged cleanly' STUB-MISS 'skip: merge' cancel 'git grep -l' 3b1e46aa9 7c8a60222 5d65dad50 '3 h 46'; do grep -q -- "$p" <path> || echo "MISSING:$p"; done`.
- [ ] AC2: the livelock learning has exactly one new `## Recurrence: PR #8474` section and nothing
  else changes. Verify: the deletions column of `git diff --numstat origin/main -- <path>` is `0`, and
  `grep -c '^## Recurrence: PR #8474' <path>` prints 1.
- [ ] AC3: no sentence in either learning says #8474 was admin-merged. Verify:
  `grep -n -iE 'admin[- ]?merg|--admin' <both paths>` and review every hit; each must be about #8458,
  the offered-but-unapproved option, or the pre-existing 2026-06-02 text. AC1's positive greps cover
  the three hand merges and the 3 h 46 min figure.
- [ ] AC4: the addendum references #8500 and proposes no fix for it. Verify:
  `awk '/^## Recurrence: PR #8474/,/^## Session Errors/' <livelock path> | grep -c '#8500'` ≥ 1.
- [ ] AC5: `ship/SKILL.md` gains exactly one line, the bullet: `git diff --numstat origin/main -- plugins/soleur/skills/ship/SKILL.md`
  prints `1	0`, and `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0 (ship ceiling
  274000; 261814 before this PR).
- [ ] AC6: `settle-then-admin-merge.md` changes only the `NOT eligible` paragraph, and the
  `ADMIN-MERGE-READY` fenced block is byte-identical. Verify: `git diff --numstat` prints `1	1`, and
  with `X='/^   ```bash/{f=1} f{print} f&&/^   ```$/{exit}'` (the file's only indented fence, 16 lines
  today), `diff <(git show origin/main:<ref path> | awk "$X") <(awk "$X" <ref path>)` prints nothing.
- [ ] AC7: the grep command quoted in the new bullet actually lists all six `sync-pr-behind` consumer
  suites when run from the repo root with `sync-pr-behind` substituted. (True before the edit too;
  it checks the quoted command, not the new prose.)
- [ ] AC8: every suite that
  `git grep -l -e 'settle-then-admin-merge' -e 'ship/SKILL.md' -- 'plugins/soleur/test/*.test.*'`
  lists passes (`bun test <file>` for `.ts`, `bash <file>` for `.sh`), and
  `bash scripts/markdown-lint.sh <the four changed markdown files>` exits 0.
- [ ] AC9: `git diff --name-only origin/main...HEAD` lists only the four Files-to-Edit/Create paths plus
  the pipeline's own artifacts: this plan, `knowledge-base/project/specs/feat-one-shot-post-merge-learnings-ship-machinery/{tasks.md,session-state.md}`,
  and `decision-challenges.md` in the same directory if one is written. (`knowledge-base/INDEX.md` is
  untracked since ADR-235 and cannot appear.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (engineering learnings and
workflow-skill prose only).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- The brief's "admin-merge broke the loop" is false (see Research Reconciliation). A writer working
  from the brief rather than this plan will reproduce it; AC3 exists to catch that.
- Two different files are named `sync-pr-behind.test.sh`. Every mention in the learning must use the
  full path.
- `ship/SKILL.md` is 12 KB under its ceiling. The bullet must stay one bullet; do not add a second
  "Why" paragraph.
- "Four syncs" is ambiguous; the evidence is four cancelled heads (`7c8a60222` and the next three).
  Write "four heads".
- `e9c6ee9a4` is not on `main`: PR #8474 was squash-merged, so the fix commit lives only on the PR
  branch and is folded into `97633e8e`. Cite it that way. `git merge-base --is-ancestor e9c6ee9a4
  origin/main` is false by construction.

## Plan Review Revisions

Panel: DHH, Kieran, code-simplicity (eng) and CTO (devex; named panel activated by the tooling
Files-to-Edit). No P0. Applied as Mechanical:

- Bullet 3a scoped to scripts the branch changes, not scripts the resolution touched (Kieran P1, CTO);
  its Why cut to a pointer; anchored on text, not line 2450.
- 3b cut to one sentence (DHH P1, simplicity; both simplification reviewers fired, so delete over
  fix). The CTO's once-per-PR / headless arms dissolve with the ask. Recorded as a taste call in
  `knowledge-base/project/specs/feat-one-shot-post-merge-learnings-ship-machinery/decision-challenges.md`.
- Cancelled-shard point written once (Deliverable 2), linked from Deliverable 1.
- AC1 per-pattern loop plus positive SHA greps; AC2 via `--numstat`; AC3 widened regex; AC4-AC6 given
  commands; AC8's hard-coded suite list removed; Test Scenarios cut; "Longer-term candidates" cut
  from the addendum; redundant `'*.test.ts'` glob removed.
- Deliverable 1 now states the automatic-BEHIND-sync gap the bullet does not cover (CTO).

## References

- PR #8474 (`97633e8e`), fix commit `e9c6ee9a4`, sibling PRs #8384 (ADR-235), #8488, #8484.
- Issue #8500 (open): shared admin-merge-ready script. Issue #8502 (open): decision-challenge digest.
- Post-mortem: `knowledge-base/engineering/operations/post-mortems/admin-merge-required-check-absent-postmortem.md`.
- Issues #4856, #5840 (merge queue), #8450 (runner concurrency ceiling).
- Source: the #8474 session transcript (local, not committed; read bounded with `jq`).

## Review Revisions (post-implementation)

A 5-agent review (no P1) changed four things relative to the deliverables above:

- The CI-time figure "60 to 70 minutes" was inherited from the session summary and was wrong.
  Measured from the check-run API, the two runs that finished took 36 and 31 minutes. The addendum
  now states the measured values.
- The ship bullet no longer carries its own `git grep` recipe; it points at the existing
  `work/SKILL.md` consumer derivation, and the same one-line pointer is added to ship Phase 6.5
  (the numbered hand-resolution steps) and `merge-pr/SKILL.md` §3.4. AC5 and AC7 are superseded:
  `ship/SKILL.md` gains 3 lines, and `merge-pr/SKILL.md` is a fifth changed file.
- The livelock Corollary gains a scope line (hatch-eligible diffs only), and the admin-merge
  sentence says steps 2 to 5 still apply when the operator authorizes one.
- The learning's "two of the six were run" now accounts for the `plugin-component-test` hook, which
  most likely ran the three `.ts` consumers; the one suite nothing ran was the one that broke.
- AC8: `knowledge-base/project/` is markdownlint-ignored, so only the plugin files are linted.
