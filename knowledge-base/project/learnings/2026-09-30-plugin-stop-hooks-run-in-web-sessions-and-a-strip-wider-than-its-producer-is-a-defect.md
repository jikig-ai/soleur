# Learning: plugin Stop hooks run in web sessions, and a strip wider than its producer is a defect

## Problem

In the web Concierge the user typed "I want to enter a new CRM lead". The agent composed the intake
question list, and the chat bubble showed `<stop>OPERATOR-GATE: I need the lead's details …</stop>`
instead. The list survived only in the Debug stream, and the chat stayed on "Still working…".

Nothing in `apps/` emitted that text. It is the escape-hatch vocabulary of the plugin Stop hook
`plugins/soleur/hooks/unkept-promise-hook.sh`, an operator-CLI guard. The web runtime loads the
platform-deployed plugin (`plugins:[{type:"local"}]`), and `settingSources:[]` blocks only
`.claude/settings.json` hooks, not the plugin's own `hooks.json`. The question list closed with
"I'll show you a review before saving", which the hook reads as an unkept promise, so it blocked the
stop and told the model to write the `<stop>` tag. That second assistant message replaced the first
(text is replaced per block, W8), and the persisted row held the tag.

## Solution

Four layers, in order of leverage (PR #9279):

1. **Root cause:** the hook exits on `SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK=1`, which `buildAgentEnv`
   sets through `AGENT_ENV_OVERRIDES` so an ambient value cannot re-enable it.
2. **Boundary:** the cc runner drops the hook's own sentinel span from each text block
   (`stripStopGateMarkup`), and the history API hides pre-fix rows on read.
3. **Client:** `chatReducer` returns `streamState` to idle on a drained cc `stream_end`
   (the cc path emits no per-turn `session_ended{turn_complete}`), and releases `stopping` there too.
4. **Guard:** a parity test derives the plugin's `Stop` hooks from `hooks.json` and requires each to
   be `web-disabled` (proven by behaviour under the real `buildAgentEnv`) or `deferred` with an issue.

## Key Insight

A matcher written for a producer's output must mirror that producer's exact vocabulary and must be
linear. My first strip matched any `<stop …>`: it truncated SVG answers carrying
`<stop offset=… />` and cost seconds on 100 KB of repeated openers, because a lazy `[\s\S]*?` rescans
to the end for every opener. The hook's real sentinel is `<stop>` followed by `OPERATOR-GATE` or
`BLOCKED`; anything wider corrupts legitimate replies. Four review seats found the breadth and the
cost independently; none of my own tests did, because every fixture was the shape I was thinking of.

Corollaries worth carrying:

- **Registering something safe from an empty fixture proves nothing.** `stop-hook.sh` was labelled
  `web-safe` because a clean temp repo did not block, but in a web session it reads repo-controlled
  state files. The class was removed.
- **An interlock a comment claims and a client never releases is a stuck state.** "Only
  `session_ended:user_aborted` releases stopping" was false for cc: `abort_turn` only aborts sessions in
  `activeSessions`, and a live cc turn is never registered there.
- **Ticked acceptance criteria go stale in the review round.** Two became false; amend them with a
  dated superseded note rather than leaving them ticked.

## Session Errors

- **Scheme literal `oauth` where the type says `oauth_token`.** Recovery: vitest failed on the unhandled
  scheme. **Prevention:** read the union (`AgentCredential["scheme"]`) before writing a fixture literal.
- **First Phase 1 commit interrupted while lefthook ran the affected battery for ~15 minutes.**
  Recovery: killed the hook tree after the operator authorised bypassing it, then committed with
  `LEFTHOOK_EXCLUDE=bun-test,web-platform-typecheck`. **Prevention:** none new; ADR-183 already says the
  pre-commit battery is not the merge gate.
- **`tsc` heap abort under load, then two real type errors only tsc reports.** Recovery:
  `NODE_OPTIONS=--max-old-space-size=6144`, then double-cast the spawn envs. **Prevention:** run tsc after
  writing any test that builds a `NodeJS.ProcessEnv`; vitest does not type-check test files.
- **Parity floor assumed every hook writes the trace marker.** Recovery: only the unkept-promise hook does;
  the floor now counts per web-disabled script. **Prevention:** derive a floor from the hooks that write
  the marker, not from the total spawn count.
- **Strip regex too broad and quadratic (found by review, not by my tests).** Recovery: rewritten as a
  linear scanner limited to the hook's sentinel, with SVG and 200 KB-budget fixtures. **Prevention:**
  before shipping any matcher for a producer's markup, list the producer's real emissions and the other
  documents that legitimately contain the same tag, and fixture both.
- **Plan premise stale: the dispatcher already dropped empty-text rows.** Recovery: grepped
  `saveAssistantMessage`, dropped the task, recorded it in `tasks.md`. **Prevention:** grep the existing
  guard before writing a test for its absence.
- **Ten acceptance criteria ticked, two false after the review round.** Recovery: dated superseded notes
  plus an addendum. **Prevention:** re-read the ticked ACs after the final review fix commit.
- **Hook suite failed 31 of 66 when the opt-out variable was exported.** Recovery: `unset` at the top plus
  value-semantics rows. **Prevention:** a suite for an env-gated script clears every variable the script
  branches on, in the suite itself.
- **Unkept-promise hook fired on my closing messages.** Recovery: one closing was a real wait and was
  declared with the sentinel; the other named an action and should have been taken. **Prevention:** none
  needed; the hook worked as designed on the CLI, which is the point of scoping it out of web only.

## Routing note

The matcher-breadth lesson belongs in `plugins/soleur/skills/work/SKILL.md` Common Pitfalls, but that file
is at its 362,000-byte body ceiling (`lint-skill-body-budget`), so a one-bullet append is refused. Moving it
there needs a block extracted into `references/` first; that is a separate reviewed change.

## Tags
category: logic-errors
module: web-platform concierge, plugin hooks
