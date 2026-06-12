# Learning: restoring a hook-contained cron needs LITERAL allowlist forms in the prompt + a decide()-paired test

## Problem

Restoring the 7 `mergeMode:"auto"` Tier-2 crons (#5199) under the deny-by-default
containment hook surfaced two recurring traps that a config-only "parity" test
does NOT catch — both would have shipped a cron that fail-closes on its first
real call in prod, caught only by post-merge `/soleur:trigger-cron`.

## Trap 1 — the prompt must write the LITERAL allowlisted command, never a shell var

The `cron-community-monitor` prompt used `ROUTER="…/community-router.sh"; bash
$ROUTER discord …`. Both forms are denied by `cron-bash-allowlist-hook.mjs`:
- `ROUTER="…"` is a leading `NAME=value` **env-assignment prefix** → denied
  (`argumentInjectionReason`).
- `bash $ROUTER discord` does NOT match the allowlist entry
  `bash plugins/soleur/skills/community/scripts/community-router.sh` — the hook
  matches a **literal leading-verb prefix**, and `$ROUTER` ≠ the literal path → denied.

So the cron's core data-collection calls would ALL be hook-denied → deny-storm →
the cron self-reports FAILED. **Fix:** rewrite the prompt to write the full
literal router path in every invocation (no `$VAR`, no `NAME=` assignment); `;`-
chaining is fine (the hook `splitSegments` on `;` and prefix-matches each segment).

**Generalizable:** when an allowlist entry is a literal path/command, the cron
prompt MUST emit that literal form verbatim. Any indirection (shell var,
`NAME=` assignment, `$(...)`, `${...}`, bare metachar) is hook-denied. `$(date)`
in `cron-growth-audit` was the same class (command substitution → denied →
hardened to an agent-computed literal date).

## Trap 2 — a parity/membership test is NOT enough; add a decide()-paired test

The new tests asserted each cron IS a key in `CRON_BASH_ALLOWLISTS` and is a
member string — i.e. the config *declares* the right thing. They never fed the
prompt's ACTUAL command through `decide(cmd, allowlist)` to prove the hook
*accepts* it. So the `$ROUTER`-class break above was 100% test-invisible (every
parity/string test stayed green). The in-repo precedent
(`cron-claude-eval-substrate.test.ts` roadmap-review + #5046 blocks) already
establishes the bar: run the prompt's representative command (and the exfil
forms) through the pure `decide()` and assert ALLOW/DENY.

**Generalizable:** restoring/adding a contained cron's allowlist requires a
`decide()`-paired test — for the cron's real prompt command(s) assert `allow`,
for `gh api` / `$(...)` / pipe / `cat /proc/self/environ` assert `deny`, and
for a sibling cron WITHOUT a bespoke verb assert it `deny`s that verb (proves
scoping). A membership/parity test alone is vacuous-green against a runtime DENY.

## Key insight

For this cron class, persistence is NODE-side (`safeCommitAndPr` via execFile/
Octokit, OUTSIDE the hook), so the prompts FORBID git/gh-pr bash — the bash
allowlist is issue-creator-shaped, NOT roadmap-review's self-commit shape. The
orchestrator's "they need git add/commit/push + gh pr create" recipe assumption
was wrong; the planner ground-truthed it from each prompt. Always enumerate the
allowlist from the cron's ACTUAL prompt + the SKILL it invokes, never from a
recipe template — and then PROVE the hook accepts the enumerated forms via
`decide()`.

## Session Errors

1. **Implementation subagent left the `$ROUTER`/`NAME=` containment break** — Recovery: caught it from the subagent's flagged note, rewrote the prompt to literal paths + updated the prompt-anchor tests. Prevention: Trap 1 above; the decide()-paired test (Trap 2) makes it fail loudly at test-time.
2. **Orchestrator recipe assumed git/gh-pr bash verbs** — Recovery: the plan subagent ground-truthed node-side persistence and used issue-creator allowlists. Prevention: enumerate from the prompt, not a recipe (Key insight).
3. **Empty `git diff origin/main...HEAD`** (uncommitted impl + stale bare-worktree origin/main) — Recovery: on-disk grep verification + commit. Prevention: already covered (`hr-when-in-a-worktree-never-read-from-bare`); verify changes on disk, not via the three-dot diff, when work is uncommitted.
4. **Review agents read stale pre-commit origin/main** — Recovery: agents re-verified against `git show HEAD:<path>`. Prevention: documented review sharp-edge (verify against committed HEAD).
5. **decide()-test gap** — Recovery: added the decide()-paired block. Prevention: Trap 2 above.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest (cron containment)
