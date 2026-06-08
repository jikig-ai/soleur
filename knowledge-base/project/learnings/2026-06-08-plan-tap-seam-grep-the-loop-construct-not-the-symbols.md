# Learning: When a plan designates a "tap seam"/"the loop", grep the loop CONSTRUCT, not the symbols near it — and at single-user threshold run the security/data-integrity deepen pass, not just plan-review

## Problem

Planning the `feat-debug-mode-stream` tap point (where to emit a new `debug_event` from the
Claude Agent SDK message stream), I grepped `cc-dispatcher.ts` for `for await|message.type|
dispatchSoleurGo|sendToClient|command_stream`, saw many hits, and wrote a plan that emitted
"from the `dispatchSoleurGo` loop in `cc-dispatcher.ts`" and (for symmetry) "from the
`agent-runner.ts:1842` loop." Both framings were wrong:

1. **`cc-dispatcher.ts` has ZERO `for await` loops.** It is **callback-based** — it implements
   the `DispatchEvents` callbacks (`onText`/`onToolUse`/`onResult`/`onToolResult`) that the
   real SDK iteration loop in `soleur-go-runner.ts:2158` (`consumeStream`) invokes. The symbols
   I matched (`message.type`, `dispatchSoleurGo`, `sendToClient`) appear in comments and
   callback bodies *near* where a loop would be, not in a loop. My grep `for await` count was
   buried in the combined output and I misread comment mentions of "the loop" as the loop.
2. **`command_stream` (the pattern I was cloning) emits from `cc-dispatcher.ts` only, never
   `agent-runner.ts`** — so "emit from both loops for symmetry" was speculative coverage of a
   non-default legacy path the template itself never instrumented.

A 6-agent review (DHH/Kieran/spec-flow/simplicity, then security-sentinel/data-integrity)
caught **8 P0s** my grep-grounded plan missed — 4 structural (tap seam, missing callbacks,
ClientSession-not-in-scope gate, the `StreamEvent` allowlist that silently drops frames while
`tsc` stays green) and 4 security (the DROP-first redaction "backstop" covered only 4 of ~14
secret shapes; `JSON.stringify` broke the redactor's `=`/header anchors; the DROP placeholder
leaked the raw tool name in violation of #2138; eligibility was fail-OPEN on a Flagsmith outage).

## Solution

1. **To locate "the loop"/"the tap seam", grep the loop CONSTRUCT at the candidate file in
   isolation** — `grep -c "for await" <file>` — before asserting the loop lives there. A count
   of 0 is dispositive regardless of how many related symbols match. If 0, the file is a
   *consumer* of events (callbacks), and the producer loop is elsewhere; find it with
   `git grep -n "for await" server/` across the directory.
2. **Distinguish callback-based from loop-based event flow.** A file that calls `sendToClient`
   inside `onToolUse: (block) => {…}` is a callback implementer; the loop that drives those
   callbacks is the real iteration site. Tapping new event kinds may require either (a) new
   callbacks on the producer (`DispatchEvents`) — net-new plumbing — or (b) reusing callbacks
   the consumer already implements (cheap). Verify which BEFORE sizing the work.
3. **At `single-user incident` brand-survival threshold, run BOTH waves:** the style/scope/
   correctness panel (DHH/Kieran/spec-flow/simplicity) AND the substance panel
   (security-sentinel + data-integrity-guardian). The second wave caught the leak-path P0s the
   first wave structurally cannot — e.g. that a "DROP-first redaction" backstop is only as good
   as the probe's shape-coverage, and that feeding `JSON.stringify(input)` to a *command-string*
   redactor silently defeats its `KEY=value`/`Authorization:` anchors. These are invisible to
   reviewers reading plan prose; they require reading the redactor's regex set + the probe array.

## Key Insight

**Symbol-presence is not construct-presence.** A grep that returns hits for the symbols you
*expect near* a construct (a loop, a transaction, a guard) is not evidence the construct is
there — only a grep for the construct itself is. The cheapest disambiguator is the narrowest
grep (`for await`, `BEGIN`, the exact predicate), run in isolation and read as a count, not
buried in a multi-pattern alternation whose output you skim. And the more brand-critical the
surface, the more the *substance* lenses (security, data-integrity) earn their cost over the
*form* lenses — they read the code the plan only describes.

## Tags
category: workflow-patterns
module: plan, web-platform/server, cc-dispatcher, soleur-go-runner
