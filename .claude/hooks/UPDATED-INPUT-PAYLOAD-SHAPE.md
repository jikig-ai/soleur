# `updatedInput` empirical verification

**Date:** 2026-08-03
**CC version:** 2.1.220 (Claude Code)
**Issue:** #7165 · **ADR:** [ADR-162](../../knowledge-base/engineering/architecture/decisions/ADR-162-pretooluse-hooks-may-rewrite-tool-input.md)
**Probe mechanism:** isolated `claude -p` with a throwaway `--settings` file in a temp dir (the live
session's settings were never touched). A `PreToolUse(Bash)` hook logged its raw stdin and emitted
`updatedInput`; a `PostToolUse(Bash)` hook logged its raw stdin. PostToolUse receives the
**effective** `tool_input`, which is what makes the merge-vs-replace question directly observable
rather than inferred.

## Outcome

`updatedInput` is **accepted and honored** by CC 2.1.220, with **no** `permissionDecision` present.

## Envelope shape (mandatory)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "updatedInput": { "command": "...", "...every other tool_input key...": "..." }
  }
}
```

`hookEventName` MUST ride in the **same object** as `updatedInput`. Without it Claude Code silently
ignores the envelope and the original command runs — the same failure mode documented in
[DEFER-DECISION-PAYLOAD-SHAPE.md](./DEFER-DECISION-PAYLOAD-SHAPE.md). A test asserting only that
`updatedInput` was emitted would pass while production was entirely unaffected.

## `updatedInput` REPLACES `tool_input`. It does not merge.

This is the load-bearing result and it is confirmed by execution, not by reading.

Submitted (PreToolUse stdin):

```json
{"tool_input":{"command":"sleep 1; echo ORIGINAL","timeout":45000,
               "description":"probe marker","run_in_background":true}}
```

Hook emitted:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"echo REWRITTEN"}}}
```

Received (PostToolUse stdin):

```json
{"tool_input":{"command":"echo REWRITTEN"}}
```

`timeout`, `description` and `run_in_background` were **all dropped**. The command additionally ran
in the **foreground** — stdout returned inline, no background task ID — independently confirming
that `run_in_background: true` was lost rather than merely absent from the log.

**Therefore:** build the envelope from the whole `tool_input` with only the changed key replaced:

```bash
jq -c --arg new "$NEW" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:(.tool_input | .command = $new)}}'
```

Emitting only the changed key is a silent data-loss bug: the call still succeeds, so nothing
surfaces except a background job that mysteriously ran in the foreground.

## Precedence and re-entrancy

| Question | Result |
|---|---|
| Sibling hook emits `deny`, this hook emits `updatedInput` | **`deny` wins** — nothing executed |
| Is the rewritten command re-submitted to PreToolUse? | **No.** One invocation per tool call |
| Do permission rules match the original or the rewritten command? | **The original** |

Re-entrancy being absent means an idempotency guard is defense in depth against a future runtime
change, not a live requirement. It is still implemented (ADR-162 clause 4).

Permission matching on the original means a rewrite can neither dodge a deny rule nor satisfy an
allow rule. Verified with an `allow: ["Bash(echo:*)"]`-only probe.

## Constraints on emitting it

See [ADR-162](../../knowledge-base/engineering/architecture/decisions/ADR-162-pretooluse-hooks-may-rewrite-tool-input.md)
for the full clause list. The two that are easiest to get wrong:

- **Never emit `permissionDecision` alongside `updatedInput`**, at any depth. An `allow` would
  bypass the permission system for every call the rewriter touches.
- **Exactly one hook may emit `updatedInput`.** Two rewriters for the same call have undefined
  precedence and one rewrite is silently discarded. Enforced in
  `hookeventname-coverage.test.sh`.
