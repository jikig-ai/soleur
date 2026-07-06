# Learning: an issue that says "the bug is not in this repo" is a claim to verify, not a fact to route on

## Problem

`/soleur:go 6132` received a `type/bug` issue whose body was emphatic and
specific: "The monitor is **not in this repo** … it runs in the external
`soleur-ai` GitHub App / bot backend. This issue tracks the fix there." It even
offered a "Proposed fix (in the bot service)". Taken at face value, the correct
route would have been to close/deflect (nothing to fix here) or to route to a
non-existent external service — a no-op dispatch.

The claim was **false**. `git grep "Maximum polling period reached"` (a literal
string quoted verbatim in the issue's own evidence) resolved immediately to
`apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts` — an
in-repo Inngest cron. `soleur-ai[bot]` is not an external service; it is the
**GitHub App identity** that in-repo cron authenticates as (it mints an
installation token and injects it as `GH_TOKEN`). The bug (a bare `gh issue
close` recording `state_reason: COMPLETED` on a timed-out issue) lived in that
file's `FOLLOW_THROUGH_PROMPT`, and the fix was a clean in-repo prompt edit.

## Solution

At the routing step, before honoring an issue-body claim that a bug lives
outside the repo (or that "there is no code here / it's a vendor/bot problem"),
run a literal-string grep of the issue's own quoted evidence against the tree:

```bash
git grep -l "<verbatim string quoted in the issue>" main
```

If it resolves, the "external" framing is wrong — route to `one-shot` with a
correction, and have the plan/PR body correct the misframing so the record is
accurate. This is the `/soleur:go` application of
`hr-verify-repo-capability-claim-before-assert`: a claim *about the repo's
capabilities/boundaries* (including "this isn't ours") must be verified against
the tree before it drives a decision.

Key discriminator that recurs: a "**bot**" or "**GitHub App**" named in an issue
is frequently an *identity* an in-repo automation authenticates as, not a
separate codebase. The bot's user-visible comment strings ("Maximum polling
period reached", "manual intervention required") are the cheapest grep anchors —
they are quoted in the issue and are string literals in the prompt/code that
emits them.

## Key Insight

An issue body is untrusted input about *where* a bug lives, exactly as much as
it is untrusted about *what* the bug is. The author's mental model ("must be the
external bot") is a hypothesis; the quoted symptom strings are the falsifier.
One grep converts a would-be misroute (deflect-as-external, or dispatch to a
non-existent service) into a correctly-scoped in-repo fix — and flags that the
PR body must correct the misframing rather than propagate it.

## Session Errors

- **Edit "String to replace not found"** — the first RED-test Edit's
  `old_string` duplicated a comment line that appears only once in the file.
  Recovery: matched the real (single) text. **Prevention:** one-off authoring
  slip; when an `old_string` includes a repeated-looking comment, copy it from a
  fresh Read rather than reconstructing it.
- **`EXIT=127` (vitest binary not found), twice** — the Bash tool does not
  persist CWD across calls, so `./node_modules/.bin/vitest` ran from the wrong
  directory. Recovery: chained `cd <worktree-abs>/apps/web-platform && …` in a
  single call. **Prevention:** already covered by work/SKILL.md and the
  constitution ("chain `cd <abs> && cmd` in one Bash call"); no new rule — this
  is a known recurring class, not a novel gap.

## Tags
category: workflow-patterns
module: soleur-go-routing
