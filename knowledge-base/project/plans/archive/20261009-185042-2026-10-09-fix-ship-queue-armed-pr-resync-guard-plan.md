---
title: "fix: sync-pr-behind.sh refuses to resync a BEHIND PR that is armed on a merge-queue repo"
date: 2026-10-09
slug: ship-queue-armed-pr-resync-guard
branch: feat-one-shot-ship-queue-armed-no-resync
issue: 9862
type: fix
priority: p2
domain: engineering
brand_survival_threshold: none
refs: [9066, 9377, 8609, 9710, 9454, 8683, 9868, 9869]
deepened: 2026-10-09
---

# fix: sync-pr-behind.sh refuses to resync a BEHIND PR that is armed on a merge-queue repo

## Enhancement Summary

**Deepened on:** 2026-10-09. **Reviewers:** spec-flow-analyzer, code-simplicity-reviewer, test-design-reviewer, architecture-strategist (read-only, against the live script, tests and fences); mechanical halts 4.6/4.7/4.8/4.11/4.12 and citation checks run by hand.

Changes folded in (full list under `## Deepen-Pass Findings`):
1. Unreadable rules read while armed now FAILS CLOSED (`kind=gh`, exit 4), matching `queue_gate` ("a failed read is never not-queued"); was fail-open.
2. Refusal text no longer claims a queue is working; it names the escape for a PR that is armed but never enqueued (`merge-queue-dequeue.md` "Armed and green but never enqueued").
3. Test design fixed: the rules stub emits the raw live-shape JSON and runs the SUT's own `--jq` (mutation 7 was uncatchable), R6 needs `BEHIND`/`BEHIND` reads and a `rules-calls` line count, R8 asserts an empty non-graphql call log, hard-coded `PASS -eq 95` bump, anchored shim regex, three in-suite mutant rows.
4. Text surfaces widened: `harness.ts` (4 lines), `codex`/`devin` `INSTRUCTIONS.md`, `drain-prs/SKILL.md` line 88 (`gh pr update-branch` bypassed the script), `merge-queue-dequeue.md`; one canonical state-based phrase and one iterating test.
5. Cut: `queue_rule_unread` info line (fail-closed instead), retry loop on the rules read, R9; mutation battery trimmed to distinct mutants. Follow-on #9869 filed for `--step` and the `pre-merge-rebase.sh` hook (the plan's earlier reason for excluding the hook was wrong).

## Overview

2026-10-09, PR 9839 (armed, merge queue on `main`, strict up-to-date checks): an agent skipped the ship skill's Phase 7 loop,
armed a hand-written Monitor loop, and that loop ran `plugins/soleur/scripts/sync-pr-behind.sh 9839` twice (pushes `5d1312cee4`,
`50e351946e`). Each push restarted PR CI for nothing; the queue would have made the PR current by itself (ADR-270 addendum
2026-10-07, measured on #9697). The skill already forbids this (ship/SKILL.md "Merge -> deploy protocol" item 6, "Exception (queue
mode)"), and Phase 7's fence already waits. The prose did not stop the agent, so the script has to.

Fix, strongest enforcement first: (1) `sync-pr-behind.sh` standalone mode returns `kind=queue_wait` (exit 0, no fetch, no merge,
no push) when GitHub reports the PR BEHIND, auto-merge is armed, and the base branch has a `merge_queue` rule; (2) a hermetic
test with a fixtured `gh` and a recording `git` shim; (3) ship/SKILL.md item 6 reordered (queue exception first, stated on facts
not on a marker only Phase 7 prints) with the "Grok/ad-hoc polls: run sync-pr-behind.sh" invitation replaced by "use the Phase 7
loop; never write your own"; (4) the same invitation removed from `pr-merge-poll.ts`; (5) ADR-270 addendum.

## Research Reconciliation — brief vs codebase

| Brief claim | Reality (read at `origin/main` 6b3e739a7e) | Plan response |
|---|---|---|
| RC1: item 6 states the rule first, the exception last | True (`ship/SKILL.md` line 30, 680 B). Worse: the exception is conditioned on "once the poll has printed `[ship.phase7.queue_wait]`", a marker only the Phase 7 fence emits. A hand-written loop never prints it, so the exception is vacuous for exactly the reader who needs it. `pr-merge-poll.ts` `behindSyncInstructions` (grok, default) repeats the same marker-conditioned exception. | Reorder AND restate the exception on facts (merge queue on `main` + PR armed); keep the marker as the fence's observable. |
| RC2: ad hoc `sync-pr-behind.sh` has no queue guard | Partly. `queue_gate()` (#9454) refuses a PR that IS in the queue (`isInMergeQueue`), in `--step` and in the loop. It does not cover the window between `gh pr merge --auto` and the enqueue (PR CI running, ~20-50 min, `not_queued OPEN armed`). The incident ran in that window. The fence's `QUEUE_RULE` + armed + expiry logic (#9710) lives in the SKILL.md fence, not in the script. | Add the rule+armed refusal to the script (standalone loop only, see Cut List). |
| RC3: "Grok/ad-hoc polls: run sync-pr-behind.sh" invites the ad-hoc call; can Phase 7's loop be invoked? | The fence is a pasted bash fence, not an invocable script: harness delivery substitutes `${CLAUDE_PLUGIN_ROOT}` into the fence text and the agent pastes it into Monitor/AwaitShell. The skill says "Use the Monitor tool with this shell loop" but nowhere forbids a hand-rolled one. The phase-7 fence header ("do NOT edit without updating the mirror") only constrains skill editors. Three texts invite the standalone call: ship item 6, `behindSyncInstructions("claude")` ("outside that loop run ..."), `behindSyncInstructions("grok")`. | Replace the invitation in item 6 and the claude line; add "never write your own" to all three. Paste-the-fence stays the invocation model; no new loop executable (YAGNI). |
| RC4: compaction dropped the "queue mode" fact; pointer in compaction context or wg rule? | The PreCompact hook preserves a fixed generic list (branch, PR #, plan path, active skill and phase, ACs, holds). `AGENTS.rules.md` is re-injected on `SessionStart:compact` (matcher `startup\|resume\|clear\|compact`) and its `hr-pipeline-skills-never-inline-after-go-route` says "BEHIND->resync main" with NO exception: that line is the one BEHIND statement that survives a summary. Editing hard rules is an operator gate (2026-10-07 learning, session error 8: a trial edit to that line was reverted). | Do not carry the fact: enforce at the point of action (script guard), so it no longer depends on survival. Rule-line wording filed as operator-gated follow-up #9868. No PreCompact edit, no new AGENTS rule. |

## Research Insights

**Premise validation.** #9710 MERGED (queue mode in fence + `merge-pr` mirror); #8683 CLOSED; #9066, #9377, #8609 OPEN (cited
only for `Refs`); #9394 OPEN (owner's, untouched); PR 9862 is this branch's draft. No stale premise. `gh api
repos/jikig-ai/soleur/rules/branches/main --jq '[.[]|.type]'` (read-only) returns
`["required_status_checks","merge_queue","required_status_checks","deletion","non_fast_forward"]`: `merge_queue` is NOT first, so
the rule read must select by `.type == "merge_queue"` (the fence already does; learning 2026-06-30).

**Property List.**
- P1: no `sync-pr-behind.sh` invocation an agent can reach from the skill text pushes a PR that is BEHIND + armed on a merge-queue repo.
- P2: Phase 7's own expiry fallback (`queue_wait_expired` -> `--step`) still syncs, and a DIRTY-derived BEHIND still syncs (no livelock regression).
- P3: queue-absent, armed-without-rule, and rule-without-armed behave exactly as today.
- P4: the instruction text states the queue exception before the rule, on facts, and does not invite a hand-rolled loop or an ad hoc call.
- P5: P1 does not depend on any fact surviving compaction.

**Cut List (mechanism -> property -> what already covers it).**
- Override flag (`--force-queue-sync` or similar) -> P2 -> not needed: expiry uses `--step`, which this change does not touch. Every override is a future bypass.
- Guard in `--step` (follow-on #9869) -> P1/P2 -> the fence owns the queue decision there (`QUEUE_RULE`, 6-idle-tick expiry, DIRTY-derived BEHIND, `QUEUE_RULE=0` when no required checks). A script-side refusal would need an override at each of those arms plus edits to ship + merge-pr fences and a 973-assertion fixture. `--step`'s contract is "its only gh call is the queue read" (pinned by `install_gh_forbidden`/`no_gh`). Accepted residual below.
- GraphQL `repository.mergeQueue(branch:)` instead of the REST rules read -> works (measured read-only: returns an id on `main`, null on an unknown branch) but appending a field to `queue_state_read`'s output would change the `QS_OUT` line that `pre-merge-rebase.sh` and `monitor-pr-checks.sh` parse (`read -r v st am rm` folds extra fields into `rm`), and the REST `.type == "merge_queue"` selector is the predicate the fence and ADR-270 already use. Kept REST, one attempt, no retry loop.
- `queue_rule_unread` info line (replaced by fail-closed `kind=gh`), retry loop, R9 -> cut by the simplicity/test reviews (below).
- PreCompact summary line -> P5 -> covered by the script guard (enforced at the action, not carried).
- New AGENTS rule / `wg-after-marking-a-pr-ready-run-gh-pr-merge` body edit -> P4/P5 -> `cq-agents-md-tier-gate`: a script carries it, so no rule; hard-rule edits are an operator gate (#9868).
- PreToolUse hook denying `git push` / `gh pr update-branch` on queue-armed PRs -> P1 -> new mechanism with its own false-positive surface; the script is the single sync implementation (#8383). Not needed to close the reported class.
- `pre-merge-rebase.sh` queue-armed skip -> not in scope here, tracked as #9869: it runs on EVERY resolvable `gh pr merge` (including a re-arm), skips only an in-queue PR, so it can merge+push an armed not-yet-queued PR (deepen-pass correction: the earlier note that it fires only before the first arm was wrong).

**Accepted residual.** A hand-rolled loop that calls `sync-pr-behind.sh <PR> --step` directly is not refused. Mitigations in this
PR: `--help` marks `--step` as the fence's call, item 6 no longer names `--step` (removes the teaching), and "never write your
own" is stated in the skill and in the harness texts. Guarding `--step` and the hook is tracked as #9869. Mitigation is textual at the point an agent reads `--step`: the claude `behindSyncInstructions` line keeps the pinned `sync-pr-behind.sh <PR-number> --step` substring and attaches "the Phase 7 fence's call, never yours; unguarded by design" in the same sentence.

**Institutional learnings applied.** 2026-10-07 queue-wait learning (bounded wait, a deleted read can take its reset with it:
keep the fence untouched), 2026-09-23 compress-prose learning (reordering must not drop conditions: every clause of item 6 is
kept and ACs assert them by anchor), 2026-06-30 merge-queue rule reader (select by `.type`, never position).

## Open Code-Review Overlap

None (queried `code-review` open issues for every file in Files to Edit; no matches).

## Implementation Phases

**Phase 0 — RED first (`cq-write-failing-tests-before`).** Add the new rows to `plugins/soleur/test/sync-pr-behind.test.sh`
(Test Scenarios below) and confirm Q1, Q1b and R6 fail against the current script before touching it.

**Phase 1 — script guard** in `plugins/soleur/scripts/sync-pr-behind.sh`:
1. New function `queue_wait_gate`, defined beside `queue_gate`. Inputs: `$state_line` (must contain `BEHIND`, must NOT contain
   `DIRTY`), and `QS_OUT` already set by the preceding `queue_gate` (third field `armed|disarmed`, so "armed" costs no extra call;
   at this point `removal=none` always, because a current removal event already exited 13 in `queue_gate`).
2. Order inside it: armed? (free) -> else return, no rules read. Then ONE rules read: `gh api
   'repos/{owner}/{repo}/rules/branches/main' --jq '[.[] | select(.type == "merge_queue")] | length'`, run like `queue_state_read`'s
   call (`bash -c`, `timeout`/`gtimeout` when present, `PR_QUEUE_TIMEOUT`, `PR_QUEUE_REPO` owner/repo override); one attempt, no
   retry loop. Base is `main`, as everywhere in this script (`fetch ... refs/heads/main`) and in the fence; a non-`main` base is out
   of contract (documented in queue-mode.md; `sync_step` merges `origin/main` regardless).
3. Verdict: numeric >= 1 (`-ge 1`, not `== 1`) -> `tag queue_wait 0 "PR #N is BEHIND, auto-merge is armed (not in the queue yet) and
   main has a merge queue: not syncing - a push restarts every required check and the queue makes the PR current. Wait for MERGED
   or a dequeue. Armed but red, or green and never enqueued? Do not sync from here: follow
   plugins/soleur/skills/ship/references/merge-queue-dequeue.md ('Armed and green but never enqueued'). With no poll running,
   re-arm the Phase 7 poll with CLAUDE_PLUGIN_ROOT exported - its expiry fallback is the sanctioned sync."` then `exit 0`.
   Numeric 0 -> return (sync as today). **Unreadable, empty or non-numeric answer -> `tag gh 4 "merge-queue rule read failed (cause=...) -
   not syncing; the PR is armed and a push to a queued PR would dequeue it"` and `exit 4`** (fail closed, same contract as
   `queue_gate`; deepen-pass change). Challengeable decision: a customer host whose token cannot read `rules/branches/main` gets a
   named `kind=gh` stop instead of a sync; `gh api` on a repo with no rulesets returns `[]` (200), which is the sync path, so only
   a genuine permission/outage failure stops.
4. Call site: in the standalone loop, immediately after `queue_gate` and BEFORE `tag behind` (so it precedes the DIRTY block, the
   resolver and `sync_step`, the only writers). Runs every attempt. The wording must not put `git push` at a line start nor
   contain the token `sync_step` (the suite's static checks at test lines ~1089 and ~1102 scan the script).
5. `usage()`: exit-0 text gains "or BEHIND + armed on a merge-queue repo (kind=queue_wait)"; exit 4 text gains the rules read; the
   `--step` line gains "the Phase 7 fence's call: the fence owns the queue-mode decision (rule, armed, expiry); do not call it from
   your own loop". Update the header comment (callers list at lines 4-8, new "Before 1" paragraph). `--step` and `--queue-state` code
   paths are not modified.

**Known asymmetries with the fence (documented, not closed; pinned by the parity test in Phase 3).** The fence sets `QUEUE_RULE=0`
when the repo has no required checks and exits on a red required check before any queue wait; the script checks neither, so an armed
BEHIND PR with a red required check or on a queue repo with no `required_status_checks` rule gets `queue_wait`, whose text routes to
`merge-queue-dequeue.md` instead of promising a merge. A DIRTY that is only GitHub's recompute lag after `main` moved still syncs
(R4 pins it); persistence-gating it is out of scope.

**Phase 2 — test harness** (`plugins/soleur/test/sync-pr-behind.test.sh`).
- `install_gh` (not `install_gh_forbidden`) gains a `gh api repos/*/rules/branches/*` arm placed BEFORE the `gh-n` counter (heredoc `\$`).
  It answers from a `rules-mode` file with the **raw live-shape JSON array and runs the SUT's own `--jq` over it** (the pattern
  `gql-stub` uses), so a selector mutation is catchable: modes `queue` (`required_status_checks`, `merge_queue`, ... - merge_queue
  second, with a `parameters` object), `queue2` (two `merge_queue` entries, pins `-ge 1`), `other` (live shape minus `merge_queue`),
  `none` (`[]`), `garbage` (rc 0, non-JSON), `empty` (rc 0, no output), `fail` (exit 1), `flip` (`[]` on the first call, `queue` after;
  the counter is the line count of `rules-calls` after appending the current call, NOT `gh-n`). Default `none`, so the existing rows
  keep their meaning. Every call appends argv to `rules-calls`; the path is asserted (`repos/o/r/rules/branches/main` under
  `PR_QUEUE_REPO=o/r`).
- `install_git_shim` (separate helper, used only by the new rows and R8, not inside `install_gh`): resolves the real git to an
  ABSOLUTE path before `$d/bin` is prepended, appends argv to `git-calls`, then `exec`s the real git. Forbidden-subcommand match is
  anchored, `^(push|fetch|merge)( |$)` (a bare `merge` would match `merge-tree` in R4).
- `install_gh_forbidden` gains a call log: every non-graphql argv is appended to `calls`; R8 asserts it is empty.
- The suite's hard-coded `"$PASS" -eq 95` (test line ~1123) is bumped to the new total; R9 was cut because the end-of-suite tag-shape
  check already runs over every collected line.
- Three in-suite mutant rows using the existing `consume_mutant`-style harness (test lines ~1000-1031) so the guard keeps regression
  protection after the one-off battery: delete the call, drop the armed condition, `.[0].type` selector. Each mutant proves the
  pristine tree exits 0 and counts only rc=1 as caught (rc >= 2 is "instrument, not evidence"), and each mutation lands inside
  `queue_wait_gate`, not on the first textual match elsewhere.

**Phase 3 — instruction text.** One canonical state-based phrase everywhere the marker-conditioned exception ("once the poll has
printed `[ship.phase7.queue_wait]`", which a hand-rolled loop never satisfies) appears: **"when `main` has a merge queue and the PR is
armed (the Phase 7 poll prints `[ship.phase7.queue_wait]`)"**. The marker stays (tests pin it); the condition becomes the fact.
- `plugins/soleur/skills/ship/SKILL.md` item 6 (line 30): replace with the 621-byte text under Files to Edit (680 B now: net -59 B;
  the file is 273996 of a 274000-byte ceiling, `plugins/soleur/test/skill-body-budget.json`, so the edit MUST be net <= +4 B).
- `plugins/soleur/lib/pr-merge-poll.ts` `behindSyncInstructions`: claude line drops "outside that loop run ..." for "never write your
  own poll loop - use that one", keeps the substrings tests pin (`sync-pr-behind.sh <PR-number> --step`,
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh"`, `unless the script reported \`kind=queued\``) and attaches "the Phase 7
  fence's call, never yours; unguarded by design" to the `--step` mention; claude FORBIDDEN line and grok/default exceptions use the
  canonical phrase; grok gains one clause "`kind=queue_wait` (exit 0) is a wait, not a failure; do not wrap the script in your own loop".
- `plugins/soleur/lib/harness.ts` lines ~339, 388, 429, 437 (`pollInstructions`), `plugins/soleur/codex/INSTRUCTIONS.md:87`,
  `plugins/soleur/devin/INSTRUCTIONS.md:306`: swap "except once the poll has printed" for the canonical phrase (mechanical).
- `plugins/soleur/skills/drain-prs/SKILL.md:88`: `gh pr update-branch <N>` for a PR "not in the queue" matches an armed PR before
  enqueue and bypasses the script; put the "armed on a merge-queue repo: leave it alone" clause FIRST in the bullet.
- `plugins/soleur/skills/ship/references/merge-queue-dequeue.md` ("Armed and green but never enqueued", line ~35): one clause naming
  the standalone `kind=queue_wait` refusal and that the escape is this procedure.
- `plugins/soleur/skills/ship/references/queue-mode.md`: one paragraph "Standalone guard (2026-10-09)": the script refusal, the
  `--step` exclusion and why, base=`main`, the required-checks / red-check asymmetry, the DIRTY-lag residual. This is the single home
  for the rationale (ADR addendum stays short and points here).
- Not edited (fence lines, byte-ceiling and mirror-parity cost; the `queue_wait` text covers them): the `behind_no_sync` line in the
  ship and merge-pr fences, `monitor-pr-checks.sh:353`, `review/SKILL.md:1493` (DIRTY class, outside the guard).
- Parity test (`plugins/soleur/test/pr-merge-poll.test.ts` or a small shell assertion): the literal selector `select(.type ==
  "merge_queue")` appears in the ship fence, the merge-pr fence and the script; every text surface above contains the canonical phrase
  and none still contains `once the poll has printed` without it.

**Phase 4 — ADR.** Amend ADR-270 (short; rationale lives in queue-mode.md) with `### Addendum 2026-10-09: the sync script refuses an armed BEHIND PR on a merge-queue repo`
(decision, the `--step` exclusion, accepted residual). C4: none (see section below).

**Phase 5 — verify (targeted suites only, `wg-when-a-test-runner-crashes...` not triggered).** See Acceptance Criteria.

## Guard Contract

### Guard 1 — standalone refusal to sync a BEHIND, armed PR on a merge-queue repo

**Property.** `sync-pr-behind.sh <PR>` (loop mode) performs no fetch, merge or push for a PR GitHub reports BEHIND while the PR has auto-merge armed and `main` has a `merge_queue` rule.

**Assembly.** Writers reachable in loop mode: `sync_step` (fetch, merge, push), called from exactly one site in the attempt loop; the DIRTY block (`resolve-regenerable-conflicts.sh`, a local merge commit) which sits above that call and is reachable only when the state line contains DIRTY, outside the property by design (GitHub's DIRTY outranks BEHIND, so a lagging recompute can route an armed PR through it; accepted residual, R4 pins it). Chokepoint: the top of each attempt, after `queue_gate` and before `tag behind`; every writer is below it. Other entry points and why they are outside the guard: `--step` (fence-owned decision; R8 pins that it still syncs and makes no non-graphql gh call; follow-on #9869), `--queue-state` (read-only), `--help`; non-script writers (`gh pr update-branch`, hand `git merge`, `pre-merge-rebase.sh`) are covered by text or tracked in #9869. The decision inputs are two live reads (armed via the queue GraphQL read, rule via the rules endpoint); nothing is cached across attempts.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `queue_wait_gate` call (in-suite mutant row) | RED: Q1 (`git-calls` shows push, remote ref moved) |
| 2 | Dispatch: gate prints `queue_wait` but falls through to `sync_step` (exit removed) | RED: Q1 (no-push assertion; `queue_wait` line must come with zero writes) |
| 3 | Second member: evaluate the gate once before the attempt loop instead of per attempt | RED: R6 (`--max-attempts 2`, reads BEHIND/BEHIND, rules flip `[]` -> queue: attempt 2 must print `kind=queue_wait`, never `kind=noop`, two lines in `rules-calls`) |
| 4 | Reorder: move the gate below `sync_step` | RED: Q1 (push recorded) - a delete-only matrix cannot see this row, the reorder can |
| 5 | Drop the armed condition (rule only) (in-suite mutant row) | RED: R3 (rule present, disarmed: syncs, and `rules-calls` empty pins armed-first ordering) |
| 6 | Drop the rule condition (armed only) | RED: R2 (armed, rules `other`: syncs) |
| 7 | Rule read selects `.[0].type` instead of `.type == "merge_queue"` (in-suite mutant row) | RED: Q1 (the stub runs the SUT's own `--jq` over the live shape, merge_queue second) |
| 8 | Gate also fires for DIRTY | RED: R4 (DIRTY + rule + armed: merge-tree clean path must still sync) |
| 9 | Unreadable rules read (`fail`, `garbage`, `empty`) treated as "queue" or as "no queue" | RED: R5 (exit 4, `kind=gh`, no push) for all three modes |
| 10 | `-ge 1` weakened to `== 1` | RED: Q1b (`queue2` payload: two `merge_queue` entries) |

**Harness rows.** H1: the `git` shim must record calls in the Q1 fixture itself (`git-calls` non-empty and contains `rev-parse`, which `queue_gate` runs), and in Q2 contain `push`; a shim that records nothing turns every "no push" assertion vacuous (mutate the shim to `exec` without logging -> Q1/Q2 RED). H2: must-PASS non-canonical inputs - PR number `4242` (not the suite default 1), a rules payload with extra unrelated rule types and a `merge_queue` entry carrying `parameters`, and `PR_QUEUE_REPO=o/r` (asserted in the `rules-calls` path). H3: the suite's `fail()` positive control (existing, kept).

**Anchor.** The guard compares live GitHub state, not a stored value, so there is no hash/registry to weaken. The rules fixture is the shape captured read-only from `gh api repos/jikig-ai/soleur/rules/branches/main` on 2026-10-09 (type list in Research Insights) so a reviewer can re-capture it.

## Test Scenarios

New rows in `plugins/soleur/test/sync-pr-behind.test.sh` (targeted; synthesized `file://` repos, PATH-shimmed `gh`/`git`, no network). Common: PR `4242`, state `OPEN BEHIND`, queue read mode `notqueued` (armed) unless stated, `advance_main` so a sync would really move HEAD, git shim installed.

| Row | Rules mode | Armed | State | Expect |
|---|---|---|---|---|
| Q1 queue-armed | `queue` (live shape) | yes | BEHIND | rc 0; stdout `[pr-behind-sync] kind=queue_wait rc=0 — `; HEAD, `origin/feat` and `origin/main` unchanged; `git-calls` non-empty with `rev-parse` and NO line matching `^(push\|fetch\|merge)( \|$)`; no `auto-sync N pushed` line |
| Q1b two entries | `queue2` | yes | BEHIND | same as Q1 (`-ge 1`) |
| Q2 queue-absent | `none` | yes | BEHIND | still syncs: `kind=pushed`, remote moved, `git-calls` contains `push` (shim positive control) |
| R2 armed, no queue rule | `other` | yes | BEHIND | syncs |
| R3 rule, not armed | `queue` | no (disarmed read) | BEHIND | syncs; `rules-calls` empty (armed is checked first) |
| R4 DIRTY + rule + armed | `queue` | yes | DIRTY, merge-tree clean | syncs via the resolver/`sync_step` path |
| R5 rules read fails | `fail`, `garbage`, `empty` | yes | BEHIND | rc 4, `kind=gh rc=4 — … merge-queue rule read failed`, nothing pushed |
| R6 second attempt | `flip` (`[]` then `queue`) | yes | BEHIND then BEHIND (`install_gh … "OPEN BEHIND" "OPEN BEHIND"`), `--max-attempts 2` | attempt 1 pushes; attempt 2 prints `kind=queue_wait`, rc 0, no `kind=noop`, `rules-calls` has 2 lines |
| R7 in queue | `queue` | queued | BEHIND | unchanged `kind=queued`; `rules-calls` empty |
| R8 `--step` unchanged | `queue` | yes | n/a | `--step` still syncs; `install_gh_forbidden`'s `calls` log (non-graphql argv) is empty |

Mutants: rows 1-10 of the Guard Contract. Three run in-suite (1, 5, 7); the rest as a one-off battery from an immutable snapshot of the SUT, result rows counted against the row list before accepting a done marker (learning 2026-10-07 errors 6-7). Positive control first (pristine tree green).

Text tests (`plugins/soleur/test/pr-merge-poll.test.ts`, `harness.test.ts`): claude text no longer contains `outside that loop`; claude and grok texts contain `never write your own` and `kind=queue_wait`; the claude `--step` mention carries "never yours"; the parity assertion in Phase 3 (selector literal in three places; canonical phrase on every surface). `ship/SKILL.md` item 6 anchor: the queue clause appears BEFORE the `**Otherwise**` clause, contains `merge queue` and `armed`, still names `[ship.phase7.queue_wait_expired]`, no longer contains `Grok/ad-hoc polls` (anchor on content, `cq-assert-anchor-not-bare-token`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash plugins/soleur/test/sync-pr-behind.test.sh` exits 0 with Q1, Q1b, Q2, R2-R8 present and passing; the hard-coded `PASS -eq` total is bumped to match; row count asserted against the planned list.
- [ ] In Q1 the `git` shim log is non-empty (contains `rev-parse`), has no `^(push|fetch|merge)( |$)` line, and `origin/feat` and `origin/main` are byte-identical before and after (negative asserted, not inferred).
- [ ] Mutation rows 1-10 plus H1: each RED, unmutated control GREEN; rows 1, 5, 7 are permanent in-suite rows.
- [ ] `bash plugins/soleur/scripts/sync-pr-behind.test.sh` and `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` still green (the fence and `--step` are unmodified; their counts unchanged).
- [ ] `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/harness.test.ts plugins/soleur/test/workflow-fidelity.test.ts` green; the canonical phrase is present on ship item 6, `behindSyncInstructions` (claude, grok, default), `pollInstructions` (all harnesses), `codex`/`devin` `INSTRUCTIONS.md`, `drain-prs/SKILL.md:88`.
- [ ] `wc -c plugins/soleur/skills/ship/SKILL.md` <= 274000 and the edit is net negative (target 273937); `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0. No `description:` frontmatter edit anywhere, so the `SKILL_DESCRIPTION_WORD_BUDGET` headroom check (`cq-skill-description-budget-headroom`) is not triggered (record: not applicable).
- [ ] `git diff origin/main...HEAD --name-only` contains no path under `.github/workflows`, `.github/actions`, `infra/`, `AGENTS.md`, `AGENTS.rules.md`.
- [ ] `bash plugins/soleur/scripts/sync-pr-behind.sh --help` lists `queue_wait` and marks `--step` as the fence's call.
- [ ] PR body uses `Refs #9066, #9377, #8609, #9868, #9869` (never `Closes`); mentions follow-ups #9868 and #9869 and the accepted `--step`/hook residual; branch of PR 9839, parked PR 9466 and its worktree untouched.
- [ ] `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-09-fix-ship-queue-armed-pr-resync-guard-plan.md` exits 0.

### Post-merge

- [ ] None (no deploy, no workflow, no production write). Residual live check, read-only and optional: on the next queue-armed BEHIND PR, `bash plugins/soleur/scripts/sync-pr-behind.sh <PR>` from its worktree prints `kind=queue_wait`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Script guard: `sync-pr-behind.sh` detects a `merge_queue` rule on the base branch AND auto-merge armed on the PR, prints `[pr-behind-sync] kind=queue_wait ...`, exits 0 without fetching or pushing." [brief] | Phase 1; Guard Contract | mapped |
| 2 | "Allow an explicit override flag only if the Phase 7 expiry path needs it." [brief] | Cut List (expiry uses `--step`, untouched) | mapped (no flag) |
| 3 | "Test: a targeted test with a fixtured `gh` that drives queue-armed (no push), queue-absent (still syncs), and armed-but-no-queue-rule (still syncs). Assert the negative: no `git push` call in the queue-armed arm." [brief] | Phase 2; Test Scenarios Q1, Q2, R2 | mapped |
| 4 | "in ship/SKILL.md, put the queue exception before the stop-and-sync rule, and replace the \"ad-hoc polls: run sync-pr-behind.sh\" sentence with \"use the Phase 7 loop; never write your own\"." [brief] | Phase 3 (item 6) | mapped |
| 5 | "Keep it within the skill byte ceiling and the description budget." [brief] | AC byte/lint lines | mapped |
| 6 | "Only add an AGENTS rule if a hook or script cannot carry it" [brief] | Cut List; #9868 | mapped (no rule; script carries it) |
| 7 | "Do not edit `.github/workflows`." / "PR body uses `Refs`, never `Closes`" [brief] | AC diff-scope + PR-body lines | mapped |
| 8 | "Root causes to confirm (read the code, don't assume): 1-4" [brief] | Research Reconciliation table | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `sync-pr-behind.sh` guard | asks 1 | asked |
| `sync-pr-behind.test.sh` rows + git shim | asks 3 | asked |
| `ship/SKILL.md` item 6 | asks 4 | asked |
| `pr-merge-poll.ts` + `pr-merge-poll.test.ts` | "replace the \"ad-hoc polls: run sync-pr-behind.sh\" sentence" - the same invitation in `behindSyncInstructions` is the second copy of that sentence | asked (same sentence, second location) |
| `queue-mode.md` paragraph | — | inferred — justification: single home for the rationale and the fence/script asymmetry (required checks, base=main, DIRTY lag); the SKILL.md byte ceiling leaves no room and the reference already holds the queue-mode design |
| ADR-270 addendum | — | inferred — justification: `plan` Phase 2.10 (`wg-architecture-decision-is-a-plan-deliverable`) requires the ADR update to ship with a change to a recorded decision; ADR-270 already carries the #9710 addendum |
| `harness.ts`, `codex`/`devin` `INSTRUCTIONS.md`, `drain-prs/SKILL.md`, `merge-queue-dequeue.md` text edits | "Check whether a reader or a context summary keeps the rule and drops the exception." (root cause 1; deepen-pass found the same marker-conditioned exception on these surfaces) | asked (root cause 1, same defect, other copies) |
| follow-up issues #9868, #9869 | "Only add an AGENTS rule if a hook or script cannot carry it" | asked (deferral tracking for the rule line the script makes harmless) |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur/{scripts,test,lib,skills,codex,devin}`, `knowledge-base/engineering/architecture`
- Planned files: 14 | Estimated changed lines: ~320
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** a PR that the ship skill cannot resync when it genuinely needs it (worst case a stuck BEHIND PR on a merge-queue repo until the Phase 7 expiry fallback runs, ~6 idle ticks); no end-user-facing artifact.
- **If this leaks, the user's workflow is exposed via:** nothing new: the guard adds one read-only `gh api` rules call and no data leaves the repo.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** developer-workflow script; failure costs CI minutes and merge latency, never user data, money or credentials; no sensitive path (auth, migrations, API routes) is touched, so no preflight Check 6 scope-out is needed.

## Observability

```yaml
liveness_signal:
  what: "stdout tag line [pr-behind-sync] kind=queue_wait rc=0 (kind=gh rc=4 when the rules read fails while armed), emitted by every guarded invocation"
  cadence: "per invocation of sync-pr-behind.sh in loop mode"
  alert_target: "the invoking agent's Monitor (Claude) or AwaitShell (Grok); both already match the pattern \\[pr-behind-sync\\] kind="
  configured_in: "plugins/soleur/scripts/sync-pr-behind.sh (tag), plugins/soleur/lib/pr-merge-poll.ts (AwaitShell pattern)"

error_reporting:
  destination: "stdout tag lines only (the script runs on developer and customer hosts; no Sentry client)"
  fail_loud: "a refused sync exits 0 with a kind=queue_wait line naming the reason and the recovery; an unreadable rules read exits 4 with kind=gh (fail closed)"

failure_modes:
  - mode: "guard refuses a PR that needed a sync (queue never enqueues it)"
    detection: "Phase 7 fence prints [ship.phase7.queue_wait_expired] after 6 idle ticks and syncs through --step (unguarded); merge-queue-dequeue.md procedure"
    alert_route: "the polling agent's Monitor stream"
  - mode: "rules endpoint unreadable while armed (outage, permission): sync refused fail-closed"
    detection: "kind=gh rc=4 line naming the rule read on stdout; exit 4"
    alert_route: "the polling agent's Monitor stream"
  - mode: "hand-rolled loop calls --step directly (accepted residual)"
    detection: "kind=pushed lines on a PR whose rules show merge_queue and autoMergeRequest set; none automated"
    alert_route: "none; follow-on is guarding --step"

logs:
  where: "stdout of the invoking Monitor/AwaitShell session"
  retention: "session transcript"

discoverability_test:
  command: grep -o 'kind=queue_wait' plugins/soleur/scripts/sync-pr-behind.sh
  expected_output: kind=queue_wait
```

## Architecture Decision (ADR/C4)

### ADR
Amend `ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` (via `soleur:architecture`): add `### Addendum 2026-10-09: the sync script refuses an armed BEHIND PR on a merge-queue repo` after the 2026-10-07 addendum. Decision: the BEHIND-sync executable carries the queue-mode refusal for its standalone entry (so the rule no longer lives only in a pasted fence); `--step` stays fence-owned. No new ADR ordinal (no collision risk). In-scope task in Phase 4, not a follow-up.

### C4 views
No C4 impact. Read in full: `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, `spec.c4`. Checked: external human actors (none new; agents and the founder already merge through GitHub), external systems (GitHub already modelled; the merge queue and rulesets are GitHub features; the `ship` component at `model.c4` already exists and its description "Full autonomous pipeline: plan, work, review, compound, ship" is not falsified), data stores (none; the guard keeps no state), actor-surface access relationships (unchanged). Derived cardinalities: run `bash plugins/soleur/test/c4-count-parity.test.sh` (no count moves; confirm green).

### Sequencing
Single slice; ADR addendum lands in the same PR.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to the plugin's own ship workflow (no UI, legal, marketing or finance surface; no Product/UX gate: no file matches the UI-surface term list).

## Files to Edit

- `plugins/soleur/scripts/sync-pr-behind.sh` — `queue_wait_gate`, call site, `usage()`, header comment.
- `plugins/soleur/test/sync-pr-behind.test.sh` — rules arm in `install_gh`, `git` shim, rows Q1/Q1b/Q2/R2-R8, three in-suite mutant rows, `PASS` total bump.
- `plugins/soleur/skills/ship/SKILL.md` — line 30 only. Exact replacement (621 B):
  `6. **BEHIND stop-and-sync:** **Queue mode first:** when \`main\` has a merge queue and the PR is armed (the Phase 7 loop prints \`[ship.phase7.queue_wait]\`), BEHIND is expected until GitHub enqueues it — keep polling and never sync, update-branch or merge it by hand until \`[ship.phase7.queue_wait_expired]\`, a push line, MERGED, a dequeue or any poll exit; \`sync-pr-behind.sh\` itself refuses it (\`kind=queue_wait\`). **Otherwise** when \`mergeStateStatus\` is \`BEHIND\`, **stop** CI-only polling and resync before continuing: use the Phase 7 loop, never write your own. Canonical spec: \`plugins/soleur/lib/pr-merge-poll.ts\`.`
  (Substrings other tests pin — `sync-pr-behind.sh`, `pr-merge-poll.ts` — are kept.)
- `plugins/soleur/lib/pr-merge-poll.ts` — `behindSyncInstructions` claude, grok, default.
- `plugins/soleur/lib/harness.ts` — `pollInstructions` lines ~339, 388, 429, 437 (canonical phrase).
- `plugins/soleur/codex/INSTRUCTIONS.md` (line ~87), `plugins/soleur/devin/INSTRUCTIONS.md` (line ~306) — canonical phrase.
- `plugins/soleur/skills/drain-prs/SKILL.md` — line 88, queue clause first.
- `plugins/soleur/test/pr-merge-poll.test.ts`, `plugins/soleur/test/harness.test.ts` — text assertions and the parity test.
- `plugins/soleur/skills/ship/references/queue-mode.md` — "Standalone guard" paragraph; `plugins/soleur/skills/ship/references/merge-queue-dequeue.md` — one clause.
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` — addendum.

## Files to Create

- None in source. Planning artifacts only: this plan and `knowledge-base/project/specs/feat-one-shot-ship-queue-armed-no-resync/tasks.md`.

## Deepen-Pass Findings

| Source | Finding | Disposition |
|---|---|---|
| spec-flow P1 | refusal could strand a PR (no `sync_ok` poll, hand-rolled loops never reach fence expiry) | Refusal text routes to `merge-queue-dequeue.md` "Armed and green but never enqueued" and "re-arm the poll with CLAUDE_PLUGIN_ROOT exported"; no override flag (still cut) |
| spec-flow P2 | unreadable rules read fell open while `queue_gate` fails closed | Changed to fail closed (exit 4), challengeable (customer-host permission caveat in Phase 1) |
| spec-flow P2 | script not equivalent to fence (no-required-checks, red required check) | Documented asymmetry + parity test; wording does not promise a merge |
| spec-flow P2/P3 | "armed" is necessary not sufficient; stale after dequeue marker consumed | Message says "not in the queue yet" and routes to the dequeue reference |
| spec-flow P2 | hook is an uncovered writer; plan's reason wrong | Reason corrected; tracked in #9869 |
| spec-flow P3 | DIRTY lag; base hard-coded to main; exit 0 read as synced | Documented residuals in queue-mode.md; callers key on `kind=` (clause in drain-prs) |
| simplicity | GraphQL for the rule; cut shim/R6/R8/R9, battery, poll.ts prose, queue-mode.md | GraphQL rejected (QS_OUT contract), R9/retry/info-line/long battery cut; shim kept (the brief asks for a `git push` negative), R6 kept (guard contract requires a second-member row), R8 kept (cheap, pins the loop-only decision), queue-mode.md kept as the single rationale home |
| test-design P1 | mutation 7 uncatchable with a bare 0/1 stub | Stub emits raw JSON through the SUT's `--jq` |
| test-design P1 | R6 flip row under-specified | BEHIND/BEHIND reads, `rules-calls` counter, `kind=noop` negative |
| test-design P2 | R8 vacuous; dangling Q4/R1; Q2==R2; `PASS -eq 95` | Forbidden-stub call log; row ids fixed; `other` mode; bump added |
| test-design P2/P3 | Q1 shim proof, anchored regex, absolute git path, `-ge` vs `==`, garbage/empty reads, in-suite mutants | All folded into Phase 2 and the matrix |
| architecture P2 | predicate in three places, unpinned | Parity test + documented asymmetry |
| architecture P2 | marker-conditioned exception on harness.ts, codex, devin | Added to Phase 3 with one canonical phrase |
| architecture P2 | drain-prs `gh pr update-branch` bypass | Added to Phase 3 |
| architecture P2/P3 | `--step` residual mitigation weaker than claimed; follow-on only "if recurs" | Clause attached to the pinned `--step` mention; #9869 filed |
| halts 4.6 / 4.7 / 4.8 / 4.11 / 4.12 | User-Brand Impact, Observability (5 fields, probe verb `grep`, literal expected output, no ssh), no PAT shapes, Guard Contract lint, Scope Check (1 unfenced) | all pass; rule ids cited exist (`wg-architecture-decision-is-a-plan-deliverable` is migrated, active in plan Phase 2.10); #9710/#8383/#8683 verified, #9454 is the OPEN adoption tracker |

## Risks and Sharp Edges

- **Byte ceiling.** `ship/SKILL.md` has 4 B of headroom. Reordering that adds a clause without removing the old invitation breaks `lint-skill-body-budget`. The replacement text above is already measured (-59 B); re-measure with `wc -c` after the edit and do not "compress" further (2026-09-23 learning: compression dropped the conditions that made the prose correct).
- **Stub fall-through.** Any `install_gh` caller that reaches the loop's BEHIND path now makes a `gh api repos/...` call; without the rules arm the stub answers a state line and shifts `gh-n`. Add the arm before touching rows; re-run the whole existing suite first.
- **Queue read already carries "armed".** Do not add a second `gh pr view --json autoMergeRequest` call: it would disturb the stub's counted state reads and duplicates `queue_state_read`'s field.
- **Hard-rule line.** Do not edit `AGENTS.rules.md` (operator gate; #9868). `workflow-fidelity.test.ts` pins `BEHIND` and `resync main` there.
- **`kind=queue_wait` exits 0.** A caller that treats exit 0 as "synced" must not print `pushed`; the standalone loop prints `pushed` only after `sync_step`, which the guard precedes. Row Q1 asserts no `auto-sync N pushed` line.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one is filled.

## References

- Incident: PR 9839 pushes `5d1312cee4`, `50e351946e`; ruleset "CI Required" id 14145388.
- `knowledge-base/engineering/operations/post-mortems/2026-10-07-ship-phase-7-behind-sync-livelock-under-merge-queue-postmortem.md`
- `knowledge-base/project/learnings/2026-10-07-a-sync-that-defers-to-a-queue-needs-a-bounded-wait-and-a-reset-that-a-deleted-read-took-with-it.md`
- ADR-270 (and addendum 2026-10-07), ADR-229 (skill body ceilings), #9710, #9454, #8383, #9868.
