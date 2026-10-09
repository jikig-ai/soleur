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
refs: [9066, 9377, 8609, 9710, 9454, 8683, 9868]
---

# fix: sync-pr-behind.sh refuses to resync a BEHIND PR that is armed on a merge-queue repo

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
- Guard in `--step` -> P1/P2 -> the fence owns the queue decision there (`QUEUE_RULE`, 6-idle-tick expiry, DIRTY-derived BEHIND, `QUEUE_RULE=0` when no required checks). A script-side refusal would need an override at each of those arms plus edits to ship + merge-pr fences and a 973-assertion fixture. `--step`'s contract is "its only gh call is the queue read" (pinned by `install_gh_forbidden`/`no_gh`). Accepted residual below.
- PreCompact summary line -> P5 -> covered by the script guard (enforced at the action, not carried).
- New AGENTS rule / `wg-after-marking-a-pr-ready-run-gh-pr-merge` body edit -> P4/P5 -> `cq-agents-md-tier-gate`: a script carries it, so no rule; hard-rule edits are an operator gate (#9868).
- PreToolUse hook denying `git push` / `gh pr update-branch` on queue-armed PRs -> P1 -> new mechanism with its own false-positive surface; the script is the single sync implementation (#8383). Not needed to close the reported class.
- `pre-merge-rebase.sh` queue-armed skip -> not in scope: it fires before the first arm (no CI to waste), and it already skips an in-queue PR.

**Accepted residual.** A hand-rolled loop that calls `sync-pr-behind.sh <PR> --step` directly is not refused. Mitigations in this
PR: `--help` marks `--step` as the fence's call, item 6 no longer names `--step` (removes the teaching), and "never write your
own" is stated in the skill and in both harness texts. Guarding `--step` is the follow-on if this recurs.

**Institutional learnings applied.** 2026-10-07 queue-wait learning (bounded wait, a deleted read can take its reset with it:
keep the fence untouched), 2026-09-23 compress-prose learning (reordering must not drop conditions: every clause of item 6 is
kept and ACs assert them by anchor), 2026-06-30 merge-queue rule reader (select by `.type`, never position).

## Open Code-Review Overlap

None (queried `code-review` open issues for every file in Files to Edit; no matches).

## Implementation Phases

**Phase 0 — RED first (`cq-write-failing-tests-before`).** Add the new rows to `plugins/soleur/test/sync-pr-behind.test.sh`
(Test Scenarios below) and confirm Q1 and Q4 fail against the current script before touching it.

**Phase 1 — script guard** in `plugins/soleur/scripts/sync-pr-behind.sh`:
1. New function `queue_wait_gate`, defined beside `queue_gate`. Inputs: `$state_line` (must contain `BEHIND`, must NOT contain
   `DIRTY`), and `QS_OUT` already set by the preceding `queue_gate` (its third field is `armed|disarmed`, so "armed" costs no extra call).
2. Order inside it: armed? (free) -> else return. Then one rules read: `gh api repos/{owner}/{repo}/rules/branches/main --jq
   '[.[] | select(.type == "merge_queue")] | length'`, run exactly like `queue_state_read`'s call (`bash -c`, `timeout`/`gtimeout`
   when present, `PR_QUEUE_TIMEOUT`, `PR_QUEUE_REPO` owner/repo override, one retry via `PR_QUEUE_ATTEMPTS`/`PR_QUEUE_RETRY_SLEEP`).
   Base is `main`, as everywhere else in this script (`fetch ... refs/heads/main`) and in the fence.
3. Verdict: numeric >= 1 -> `tag queue_wait 0 "PR #N is BEHIND, auto-merge is armed and main has a merge queue: not syncing (a push
   restarts every required check; the queue makes the PR current). Wait for MERGED or a dequeue; if no Phase 7 poll is running,
   re-arm it - its expiry fallback is the only sanctioned sync for an armed PR."` then `exit 0`. Numeric 0 -> return (sync as today).
   Unreadable after retry -> `tag queue_rule_unread 0 "..."` (non-terminal info line) and return: fail toward today's sync, matching
   the fence ("Every unreadable answer falls toward today's sync") so an API outage cannot strand a BEHIND PR.
4. Call site: in the standalone loop, immediately after `queue_gate` and BEFORE `tag behind` (so it precedes the DIRTY block, the
   resolver and `sync_step`, the only writers). Runs every attempt (a `--max-attempts N` run re-evaluates after each push).
5. `usage()`: exit 0 text gains "or BEHIND + armed on a merge-queue repo (kind=queue_wait)"; `--step` line gains "the Phase 7 fence's
   call: the fence owns the queue-mode decision (rule, armed, expiry); do not call it from your own loop". Update the header
   comment block (callers list, new "Before 1" paragraph). `--step` and `--queue-state` code paths are not modified.

**Phase 2 — test harness.** `install_gh` (not `install_gh_forbidden`) gains a `gh api repos/*/rules/branches/*` arm placed before the
`gh-n` counter, answering from a `rules-mode` file (`none` -> `0`, `queue` -> `1`, `fail` -> exit 1, `flip` -> `0` first call then `1`),
default `none`, and logging argv to `rules-calls`. Without it the real stub's fall-through would return a state line and bump `gh-n`.
A `git` PATH shim (`git-calls` log of argv, then `exec` the real git) is installed per fixture. A `rules` fixture payload uses the
live shape captured above (merge_queue second).

**Phase 3 — instruction text.**
- `plugins/soleur/skills/ship/SKILL.md` item 6 (line 30): replace with the 621-byte text recorded under Files to Edit (680 B now: net
  -59 B; the file is 273996 of a 274000-byte ceiling, `plugins/soleur/test/skill-body-budget.json`, so the edit MUST be net <= +4 B).
- `plugins/soleur/lib/pr-merge-poll.ts` `behindSyncInstructions`: claude line drops "outside that loop run ..." for "never write your
  own poll loop - use that one"; keeps the `sync-pr-behind.sh <PR-number> --step`, `bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh"`
  and `unless the script reported \`kind=queued\`` substrings existing tests pin; grok and default gain the state-based exception
  ("main has a merge queue and the PR is armed") and "a standalone `kind=queue_wait` exit 0 is a wait, not a failure; do not wrap
  the script in your own loop".
- `plugins/soleur/skills/ship/references/queue-mode.md`: one paragraph, "Standalone guard (2026-10-09)", states the script refuses
  BEHIND+armed on its own, the `--step` exclusion and why (fence owns expiry). No byte ceiling on references.

**Phase 4 — ADR.** Amend ADR-270 with `### Addendum 2026-10-09: the sync script refuses an armed BEHIND PR on a merge-queue repo`
(decision, the `--step` exclusion, accepted residual). C4: none (see section below).

**Phase 5 — verify (targeted suites only, `wg-when-a-test-runner-crashes...` not triggered).** See Acceptance Criteria.

## Guard Contract

### Guard 1 — standalone refusal to sync a BEHIND, armed PR on a merge-queue repo

**Property.** `sync-pr-behind.sh <PR>` (loop mode) performs no fetch, merge or push for a PR GitHub reports BEHIND while the PR has auto-merge armed and `main` has a `merge_queue` rule.

**Assembly.** Writers reachable in loop mode: `sync_step` (fetch, merge, push), called from exactly one site in the attempt loop; the DIRTY block (`resolve-regenerable-conflicts.sh`, a local merge commit) which sits above that call and is reachable only when the state line contains DIRTY, outside the property by design. Chokepoint: the top of each attempt, after `queue_gate` and before `tag behind`; every writer is below it. Other entry points and why they are outside the guard: `--step` (fence-owned decision; characterization row R8 pins that it still syncs), `--queue-state` (read-only), `--help`. The decision inputs are two live reads (armed via the queue GraphQL read, rule via the rules endpoint); nothing is cached across attempts.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `queue_wait_gate` call | RED: Q1 (push recorded by the git shim, remote ref moved) |
| 2 | Dispatch: gate returns before reading anything (always "not queue") / or prints `queue_wait` but falls through to `sync_step` (exit removed) | RED: Q1 (no-push assertion) and R1 positive control (a `queue_wait` line must come with zero git writes) |
| 3 | Second member: evaluate the gate once before the attempt loop instead of per attempt | RED: R6 (`--max-attempts 2`, rules flip `none` -> `queue`: exactly one push, second attempt refuses) |
| 4 | Reorder: move the gate below `sync_step` | RED: Q1 (push recorded) - a delete-only matrix cannot see this row, the reorder can |
| 5 | Drop the armed condition (rule only) | RED: R3 (rule present, disarmed: must still sync) |
| 6 | Drop the rule condition (armed only) | RED: R2 (armed, no rule: must still sync) |
| 7 | Rule read selects `.[0].type` instead of `.type == "merge_queue"` | RED: Q1 (live shape has `merge_queue` second) |
| 8 | Gate also fires for DIRTY | RED: R4 (DIRTY + rule + armed: merge-tree clean path must still sync) |
| 9 | Unreadable rules read exits non-zero / treated as queue | RED: R5 (rules fail: syncs + `kind=queue_rule_unread`) |

**Harness rows.** H1: the `git` shim must record a push in the Q2 positive row (`git-calls` contains `push`); a shim that records nothing turns every "no push" assertion vacuous, so Q2 asserts the log is non-empty and contains `push` (mutate the shim to `exec` without logging -> Q2 RED). H2: must-PASS non-canonical inputs - PR number `4242` (not the suite default 1, so a hard-coded `-F number=1` cannot pass), a rules payload with extra unrelated rule types and a `merge_queue` entry carrying `parameters` fields, and `PR_QUEUE_REPO=o/r` set. H3: positive control that the suite's `fail()` counter moves (existing pattern, kept).

**Anchor.** The guard compares live GitHub state, not a stored value, so there is no hash/registry to weaken. The rules fixture payload is the shape captured read-only from `gh api repos/jikig-ai/soleur/rules/branches/main` on 2026-10-09; the type list is recorded in Research Insights so a reviewer can re-capture it.

## Test Scenarios

New rows in `plugins/soleur/test/sync-pr-behind.test.sh` (targeted; synthesized `file://` repos, PATH-shimmed `gh`/`git`, no network). Common: PR `4242`, state `OPEN BEHIND`, queue read mode `notqueued` (armed), `advance_main` so a sync would really move HEAD.

| Row | Rules | Armed | State | Expect |
|---|---|---|---|---|
| Q1 queue-armed | queue (live shape) | yes | BEHIND | rc 0; stdout `[pr-behind-sync] kind=queue_wait rc=0 — `; HEAD and `origin/feat` unchanged; `git-calls` has NO `push`, `fetch`, `merge`; no `auto-sync N pushed` line |
| Q2 queue-absent | none | yes | BEHIND | still syncs: `kind=pushed`, remote moved, `git-calls` contains `push` (shim positive control H1) |
| R2 armed, no queue rule | none (other rule types only) | yes | BEHIND | same as Q2 (named separately: the brief's third arm) |
| R3 rule, not armed | queue | no (`dequeued`-style disarmed read) | BEHIND | syncs |
| R4 DIRTY + rule + armed | queue | yes | DIRTY, merge-tree clean | syncs via the resolver/`sync_step` path (guard does not fire) |
| R5 rules read fails | fail | yes | BEHIND | syncs; stdout has `kind=queue_rule_unread rc=0`; rules read retried once (2 calls) |
| R6 second attempt | flip none -> queue | yes | BEHIND, `--max-attempts 2` | exactly one push, then `kind=queue_wait` |
| R7 in queue | queue | queued | BEHIND | unchanged `kind=queued` (guard not reached; rules NOT read: `rules-calls` empty) |
| R8 `--step` unchanged | queue | yes | n/a | `--step` on the same fixture still syncs (characterization: fence owns the decision); `install_gh_forbidden` still sees zero non-graphql gh calls |
| R9 tag shape | - | - | - | existing end-of-suite tag-shape contract passes over the new lines |

Mutation battery: rows 1-9 of the Guard Contract run from an immutable snapshot of the SUT (learning 2026-10-07 session error 6), result rows counted against the row list before accepting a done marker (error 7). Positive control first (unmutated = all green).

Text tests (`plugins/soleur/test/pr-merge-poll.test.ts`): claude text no longer contains `outside that loop`; claude and grok texts contain `never write your own` and `kind=queue_wait`; existing pinned substrings (listed in Phase 3) still match. `ship/SKILL.md` item 6 anchor test: the queue-exception clause appears BEFORE the `**Otherwise**` / `stop` clause, contains `merge queue` and `armed` (state-based), still names `[ship.phase7.queue_wait_expired]`, and no longer contains `Grok/ad-hoc polls` (anchor on content, `cq-assert-anchor-not-bare-token`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash plugins/soleur/test/sync-pr-behind.test.sh` exits 0 with Q1, Q2, R2-R9 present and passing; row count asserted against the planned list.
- [ ] In Q1 the `git` shim log contains no `push`, `fetch` or `merge` and `origin/feat` is byte-identical before and after (negative asserted, not inferred).
- [ ] Mutation battery of 9 rows plus H1: each row RED, unmutated control GREEN (recorded in the PR body).
- [ ] `bash plugins/soleur/scripts/sync-pr-behind.test.sh` and `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` still green (the fence and `--step` are unmodified; their counts unchanged).
- [ ] `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/harness.test.ts plugins/soleur/test/workflow-fidelity.test.ts` green.
- [ ] `wc -c plugins/soleur/skills/ship/SKILL.md` <= 274000 and the edit is net negative (target 273937); `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0. No `description:` frontmatter edit anywhere, so the `SKILL_DESCRIPTION_WORD_BUDGET` headroom check (`cq-skill-description-budget-headroom`) is not triggered (record: not applicable).
- [ ] `git diff origin/main...HEAD --name-only` contains no path under `.github/workflows`, `.github/actions`, `infra/`, `AGENTS.md`, `AGENTS.rules.md`.
- [ ] `bash plugins/soleur/scripts/sync-pr-behind.sh --help` lists `queue_wait` and marks `--step` as the fence's call.
- [ ] PR body uses `Refs #9066, #9377, #8609, #9868` (never `Closes`); mentions follow-up #9868 and the accepted `--step` residual; branch of PR 9839, parked PR 9466 and its worktree untouched.
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
| `queue-mode.md` paragraph | — | inferred — justification: the reference already holds the queue-mode rationale and is where a maintainer looks; not byte-capped, one paragraph |
| ADR-270 addendum | — | inferred — justification: `plan` Phase 2.10 (`wg-architecture-decision-is-a-plan-deliverable`) requires the ADR update to ship with a change to a recorded decision; ADR-270 already carries the #9710 addendum |
| follow-up issue #9868 | "Only add an AGENTS rule if a hook or script cannot carry it" | asked (deferral tracking for the rule line the script makes harmless) |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur/{scripts,test,lib,skills}`, `knowledge-base/engineering/architecture`
- Planned files: 8 | Estimated changed lines: ~280
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
  what: "stdout tag line [pr-behind-sync] kind=queue_wait rc=0 (and kind=queue_rule_unread rc=0 on an unreadable rules read), emitted by every guarded invocation"
  cadence: "per invocation of sync-pr-behind.sh in loop mode"
  alert_target: "the invoking agent's Monitor (Claude) or AwaitShell (Grok); both already match the pattern \\[pr-behind-sync\\] kind="
  configured_in: "plugins/soleur/scripts/sync-pr-behind.sh (tag), plugins/soleur/lib/pr-merge-poll.ts (AwaitShell pattern)"

error_reporting:
  destination: "stdout tag lines only (the script runs on developer and customer hosts; no Sentry client)"
  fail_loud: "a refused sync exits 0 with a kind=queue_wait line naming the reason and the recovery; unreadable rules print kind=queue_rule_unread and fall toward today's sync"

failure_modes:
  - mode: "guard refuses a PR that needed a sync (queue never enqueues it)"
    detection: "Phase 7 fence prints [ship.phase7.queue_wait_expired] after 6 idle ticks and syncs through --step (unguarded); merge-queue-dequeue.md procedure"
    alert_route: "the polling agent's Monitor stream"
  - mode: "rules endpoint unreadable, sync proceeds on an armed queue PR"
    detection: "kind=queue_rule_unread line on stdout; --queue-state still guards an in-queue PR"
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
- `plugins/soleur/test/sync-pr-behind.test.sh` — rules arm in `install_gh`, `git` shim, rows Q1/Q2/R2-R9, mutation battery notes.
- `plugins/soleur/skills/ship/SKILL.md` — line 30 only. Exact replacement (621 B):
  `6. **BEHIND stop-and-sync:** **Queue mode first:** when \`main\` has a merge queue and the PR is armed (the Phase 7 loop prints \`[ship.phase7.queue_wait]\`), BEHIND is expected until GitHub enqueues it — keep polling and never sync, update-branch or merge it by hand until \`[ship.phase7.queue_wait_expired]\`, a push line, MERGED, a dequeue or any poll exit; \`sync-pr-behind.sh\` itself refuses it (\`kind=queue_wait\`). **Otherwise** when \`mergeStateStatus\` is \`BEHIND\`, **stop** CI-only polling and resync before continuing: use the Phase 7 loop, never write your own. Canonical spec: \`plugins/soleur/lib/pr-merge-poll.ts\`.`
  (Substrings other tests pin — `sync-pr-behind.sh`, `pr-merge-poll.ts` — are kept.)
- `plugins/soleur/lib/pr-merge-poll.ts` — `behindSyncInstructions` claude, grok, default.
- `plugins/soleur/test/pr-merge-poll.test.ts` — new/updated text assertions.
- `plugins/soleur/skills/ship/references/queue-mode.md` — "Standalone guard" paragraph.
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` — addendum.

## Files to Create

- None in source. Planning artifacts only: this plan and `knowledge-base/project/specs/feat-one-shot-ship-queue-armed-no-resync/tasks.md`.

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
