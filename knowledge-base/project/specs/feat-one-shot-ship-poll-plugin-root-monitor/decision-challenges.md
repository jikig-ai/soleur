# Decision challenges: feat-one-shot-ship-poll-plugin-root-monitor

These come from a headless planning run (one-shot), recorded per ADR-084. `ship` adds this file to the
PR body.

## DC-1: The Phase 7 fence stays byte-identical; the fix is prose

**Date:** 2026-09-27
**Classification:** User-Challenge (the planner and the plan-review panel agree the brief's stated
direction should change)

**Brief's direction:** fix the fence between the `phase-7-poll-block` markers so the poll resolves
the plugin root reliably under Monitor. The suggested way was to bind a local variable once, from the
substituted token, at the top of the fence.

**What the plan does instead:** it leaves both fences byte-identical. It adds a prose notice in
`ship/SKILL.md` that prints this session's loader-substituted root, a matching pointer sentence in
`merge-pr/SKILL.md` §5.2, and fixture rows (the delivered-text decoy row 17b and prose pins).

**Why:**

- **The fence already does what the brief asks.** It binds `SYNC_ROOT` once, from the exact
  `${CLAUDE_PLUGIN_ROOT}` token, and ADR-179 measured that token as SUBSTITUTED in delivered text.
  The failure was the fence being *extracted raw from SKILL.md on disk*: the token was
  unsubstituted, and the variable is not exported in a Monitor shell. That is item 4 of
  `knowledge-base/project/learnings/2026-09-27-a-log-line-is-evidence-about-the-step-that-printed-it.md`.
- **Nothing inside the fence can fix a raw extraction.** `plugin-root-anchoring.test.ts` checks W1
  and W1b, which ban every root read except the exact token and every assignment. ADR-179 bans CWD
  defaults and cache arms. What is left is the launching agent's environment, which only prose can
  steer.
- **The fence's first event already names the cause and the remedy**
  (`CLAUDE_PLUGIN_ROOT is unset … export CLAUDE_PLUGIN_ROOT=<the installed soleur plugin root>`).
  Rewording it would have been wrong for Devin/Codex, and in the merge-pr mirror.
- **An in-checkout refusal was considered and cut.** `event-ship-merge.ts` runs headless ship with
  `--plugin-dir plugins/soleur`, the PR clone's own tree. There the loader's root is inside the
  checkout, so the refusal would disable BEHIND auto-sync on every auto-ship run.

**Default if not revisited:** ship the prose-plus-fixture fix as planned.

**Reopen if:** an agent still starts the poll with an empty root after this lands. The next step
would then be the ADR-179 A17 route: move the fence into a `BASH_SOURCE`-anchored script that both
skills call.
