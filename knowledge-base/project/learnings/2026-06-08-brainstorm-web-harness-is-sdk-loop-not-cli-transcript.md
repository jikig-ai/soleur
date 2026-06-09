# Learning: The web-platform harness is an in-process SDK loop, not a CLI with readable transcripts — reconcile CLI-framing before accepting "just read the logs"

## Problem

During the `feat-debug-mode-stream` brainstorm (a workspace-scoped "Debug mode" that
streams harness instructions into the web conversation UI), three framings that sound
obviously-true from the Claude Code **CLI** mental model were wrong or incomplete for
the **web-platform** surface. Each would have shaped a worse spec if accepted uncritically:

1. **CPO recommended an "out-of-band log viewer"** reading "the JSONL transcripts the
   harness already produces, like CLI sessions are recorded." This is the cheapest
   option *if those transcripts exist*. They don't: the web harness is the Claude Agent
   SDK `query()` loop in `apps/web-platform/server/cc-dispatcher.ts` /
   `agent-runner.ts:1842`, which **down-selects the SDK message stream into a few
   curated WS frames and drops the rest in-process**. There is no per-conversation
   `.jsonl` on disk, and even if there were, a *web* operator is in a browser, not on
   the server box. The "free alternative" did not exist for this surface.

2. **"Stream every instruction" overpromised against the SDK.** The web harness only
   surfaces `assistant` text, `tool_use` blocks, `tool_progress`, and `result`. True
   CLI-style **system-reminders** and **sub-agent internal transcripts are captured
   nowhere** in the web backend — delivering them is a net-new SDK `system`-message
   handler + sub-agent stream-plumbing lift, not a presentation tweak.

3. **Per-workspace feature gating does not exist in Flagsmith.** Flag targeting grain is
   role (`prd`/`dev`) and org (`<flag>-orgs` EQUAL-orgId segments) only — there is no
   `workspaceId` trait. "Soleur Workspace only" is not natively expressible as a flag.

## Solution

Verify the *actual* event source and gating substrate by reading the dispatcher loop
and the flag layer before letting a leader's framing bound the options:

1. **Out-of-band-vs-in-product**: grep for `jsonl`/`transcript` capture in the web
   backend before accepting "read the logs." Here it returned only unrelated hits —
   confirming the SDK stream is ephemeral in-process and the only tap point is the
   `for await (const message of q)` loop. Debug mode therefore *must* tap that loop;
   there is no cheaper external path.

2. **Scope honesty**: scope v1 to "the uncurated SDK stream" (what the loop already
   sees) and explicitly defer system-reminders + sub-agent transcripts as Non-Goals,
   rather than promising CLI parity the SDK can't currently deliver.

3. **Per-workspace gating**: use the battle-tested `workspaces.<column>` pattern —
   `workspaces.bash_autonomous` (migration `097`) + member/owner SECURITY-DEFINER RPCs
   + a fail-closed resolver (`server/resolve-bash-autonomous.ts`) cached on the
   `ClientSession` at WS handshake — with Flagsmith only as the **availability
   kill-switch** (dev cohort). Not a Flagsmith flag.

The whole feature then reduces to: generalize the existing `command_stream` frame (a
scoped, gated exception to the #2138 "no raw tool inputs on the wire" invariant) to all
tool-uses, behind the workspace toggle, redacted at the construction site, ephemeral.

## Key Insight

**A fast-returning domain leader reasons from a general mental model; the codebase is
the authority on which substrate actually exists.** When a leader (or you) prescribes
"reuse the existing X" or "just read the Y that's already produced," grep for X/Y's
*diagnostic symbol* before it bounds the option space — especially when the mental
model is the CLI and the target is the web-platform. The CLI and the web app share a
harness *family* (Claude Agent SDK) but not its *I/O surface*: the CLI persists jsonl
transcripts a human reads; the web app streams curated frames over a WebSocket and
discards the rest. Three of three CLI-shaped assumptions were wrong here.

This extends the existing "cross-check leader infra/substrate claims against
repo-research" brainstorm rule to the specific CLI→web-harness translation gap.

## Session Errors

- **`Edit` on spec FR2 failed with `String to replace not found`** — a line-wrap /
  whitespace mismatch between my remembered text and the file. Recovery: `grep -n` the
  exact line, then retry the Edit against the verbatim string. Prevention: when an Edit
  targets prose I wrote earlier in the same session across a soft-wrapped line, grep the
  anchor substring first rather than reconstructing the full line from memory. One-off;
  no workflow change warranted.

## Tags
category: workflow-patterns
module: brainstorm, web-platform/server, feature-flags
