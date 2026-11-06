# Learning: the Paused:/Blocked: exit became a parking lot for agent-owned pipeline steps

## Problem

A finished `soleur:work` run closed with `Paused: waiting for your go to ... mark the PR ready`. Marking a PR ready, editing its body, filing a follow-up and running review/compound/ship are agent-owned steps. The Stop hook (`plugins/soleur/hooks/unkept-promise-hook.sh`) offers `Paused:`/`Blocked:` as its exit, and its parked-deliverable arm only knew the objects merge, review and ship, so a `go` for "mark ready" matched nothing and the label parked finished work on the operator. A draft PR whose CI skipped the test legs (draft-light) made the stall feel justified.

## Solution

- Parked arm: a CLOSED list of agent-owned acts (`PARKED_GO_RE`: a go/approval/permission for mark-ready, PR body, follow-up issue, remaining items, compound, ship). Deliberately not a wider object set: the header records that decision/approval/go-ahead blocked 13 of 15 rule-mandated gates.
- Exemptions in `PARKED_AUTH_RE`: agent spawn (`wg-zero-agents-until-user-confirms`; the existing `PARKED_RE` already blocked `pending your go before I spawn the review agents`, a pre-existing false positive) and outward-facing sends (invoice, customer).
- Guidance text now says a stop is legitimate only for an external event the agent cannot advance or an operator-reserved act.
- One sharp-edge bullet each in work Phase 4, ship Important Rules, and a clause in one-shot Step 8; ship's "confirm the PR title/body with the user" gate removed.

## Key Insight

An escape hatch that the enforcement itself names becomes the default parking spot unless the hook says what it is for. State the legitimate set (external event, operator-reserved act) next to the label, and block the agent-owned act vocabulary by a closed list rather than by widening a regex.

## Session Errors

1. **First drafts of the bullets exceeded the lifecycle SKILL.md body ceilings** (`scripts/lint-skill-body-budget.py`: one-shot +104, ship +423, work +293 over). Recovery: trimmed to one-shot +14, ship +14, work +438 against 18/47/465 headroom. Prevention: before writing prose into work/ship/one-shot, compute headroom from `plugins/soleur/test/skill-body-budget.json` against `git show origin/main:<file> | wc -c`.
2. **Pre-existing false block** of the agent-spawn gate by `PARKED_RE` surfaced only when I added an ALLOW row for it. Prevention: every new arm ships ALLOW rows for the rule-mandated gates (cost, spawn, outward send).
3. **Mutation survivor**: widening `PARKED_GO_RE` with a bare `review` survives and is equivalent (`PARKED_RE` already blocks it); recorded in the suite rather than left unlabelled.
4. **The command-line process-match hook denied a process-pattern lookup**; used `proc.sh list_runs/kill_mine`. The same hook then denied a heredoc that merely QUOTED the denied command, so quoting a denied command in prose inside a Bash call trips it.
5. **A backgrounded command reset the Bash cwd to the other worktree**; every later call used an absolute `cd`.
6. **No agent panel**: the run was a fork that may not spawn agents, so review was inline with `Reviewed-Coverage: inline-fallback 0/8`.

## Tags
category: workflow-patterns
module: unkept-promise-hook, work, ship, one-shot
