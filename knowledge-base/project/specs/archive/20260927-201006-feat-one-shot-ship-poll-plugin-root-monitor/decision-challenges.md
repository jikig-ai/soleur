# Decision challenges: feat-one-shot-ship-poll-plugin-root-monitor

These come from a headless planning run (one-shot), recorded per ADR-084. `ship` adds this file to the
PR body.

## DC-1: The Phase 7 fence's logic is unchanged; the fix is prose plus one message

**Date:** 2026-09-27
**Classification:** User-Challenge (the planner and the plan-review panel agree the brief's stated
direction should change)

**Brief's direction:** fix the fence between the `phase-7-poll-block` markers so the poll resolves
the plugin root reliably under Monitor. The suggested way was to bind a local variable once, from the
substituted token, at the top of the fence.

**What the PR does instead:** it leaves the fence's logic unchanged. It adds a notice above ship's
fence, and a matching paragraph above the merge-pr §5.2 mirror. The notice prints this session's
loader-substituted root and follows the ADR-179 A20 shape: the root is only that path or the Skill
tool's `Base directory for this skill:` line, and the agent never guesses. The one fence change, made
identically in both blocks after review, extends the unset reason with the same recovery, because an
agent that extracts the fence with `awk` never sees the prose. Fixture rows 17b/17c/17d and prose pins
cover the delivered-text shape.

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
- **The fence's first event names the cause and, since review, the recovery**
  (`CLAUDE_PLUGIN_ROOT is unset (Claude Code/Grok: this fence was taken from disk — re-arm with the
  root from the Skill tool's Base directory line …)`). The wording is scoped to substituting
  harnesses and says nothing specific to ship, so it is correct in the merge-pr mirror; the existing
  tail still points Devin/Codex at their `INSTRUCTIONS.md`.
- **An in-checkout refusal was considered and cut.** `sync-pr-behind.sh` is not a trust gate the way
  `admin-merge-ready.sh` is, and a legitimate root can sit inside a checkout: this repo's directory
  marketplace, and `event-ship-merge.ts`'s `--plugin-dir plugins/soleur` clone. (That consumer cannot
  run Phase 7 today — no `Monitor` in its allowed tools, and it has no Bash allowlist — so the break
  would be latent rather than immediate.) The notice instead forbids a path *built from the working
  directory*, which the loader-printed path never is.

**Default if not revisited:** ship the prose-plus-fixture fix as planned.

**Alternatives rejected, not deferred:** a compaction hook re-supplying the root (re-invoking the
Skill tool already re-delivers the substituted text, so no new trusted carrier is needed), and the
ADR-179 A17 route (move the fence into a `BASH_SOURCE`-anchored script). The A17 route would make the
whole poll depend on the root, turning scenario 13b's deliberate degrade-open on Devin/Codex into a
hard failure; that trade-off is the reason, not the fixture restructure.
