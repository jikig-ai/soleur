# Phase 0 delivery probe: PostToolUse `additionalContext` under `claude --print`

Date: 2026-11-13. Ref #11076, Ref #9601. Plan: `knowledge-base/project/plans/2026-11-12-feat-cron-gh-output-framing-hook-plan.md`
(Phase 0).

## Result

**Delivery verified at 2.1.321; effect unmeasured.** Run 1 returned the exact nonce, and the negative control returned `NONE`.
The CTO's recorded dissent (switch to the KB Read hook) does not trigger.

This shows only that the CLI delivers the hook's `additionalContext` to the model in print mode. It does not show that the
GitHub preamble changes model behaviour, and no claim about that follows from it.

## Setup

- Scratch directory outside the repo, on the developer's own Claude auth. No production system was touched.
- CLI: `npx -y @anthropic-ai/claude-code@2.1.321`. `--version` printed `2.1.321 (Claude Code)` in each run directory.
- Flags: `--print --strict-mcp-config --output-format json --setting-sources project --model haiku --append-system-prompt <UNTRUSTED_PREAMBLES.github>`.
  `--setting-sources project` keeps the developer's own user hooks out. Production does not pass it.
- `.claude/settings.json` was shaped like `buildCronEvalSettings` output: the same `permissions` and `sandbox` blocks, and the
  `*` PreToolUse containment hook (a copy of `cron-bash-allowlist-hook.mjs` under its own file name, with a `cron-allow.txt`
  admitting only `echo`).
- Run 1 added one PostToolUse entry, matcher `Bash`, running a stub. The stub wrote its stdin to a capture file and printed
  `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<nonce>"}}`. Run 2 had no PostToolUse entry.
- Nonce: `PROBE-NONCE-ff20d2ca2b395211`, 8 bytes from `/dev/urandom`. It was in no prompt, no system prompt and no repo file.
- Prompt: "Run the shell command `echo hello` with the Bash tool exactly once. Then reply with ONLY one line: if any context
  you received after running it contained a token starting with PROBE-NONCE, reply with that exact token; otherwise reply
  with exactly NONE."

## Runs

| Run | CLI | PostToolUse entry | exit | `result` | `num_turns` | cost (USD) |
|---|---|---|---|---|---|---|
| 1, delivery | 2.1.321 | nonce stub | 0 | `PROBE-NONCE-ff20d2ca2b395211` | 2 | 0.0019 |
| 2, negative control | 2.1.321 | none | 0 | `NONE` | 2 | 0.0019 |

## Captured PostToolUse stdin (run 1), keys and value types only

```json
{"session_id": "str", "transcript_path": "str", "cwd": "str", "prompt_id": "str", "permission_mode": "str",
 "effort": {"level": "str"}, "hook_event_name": "str", "tool_name": "str",
 "tool_input": {"command": "str", "description": "str"},
 "tool_response": {"stdout": "str", "stderr": "str", "interrupted": "bool", "isImage": "bool", "noOutputExpected": "bool"},
 "tool_use_id": "str", "duration_ms": "int"}
```

`hook_event_name` was `PostToolUse`, `tool_name` was `Bash` and `tool_input.command` was `echo hello`. The hook reads only
those three fields, and the pinned CLI sends all three.

## Not probed

- A real framing hook run: the AC2 binary rows already cover that, and the model repeating the real preamble would prove
  nothing because the same text is in the system prompt (CTO F5').
- A Bash command with a non-zero exit (whether that fires PostToolUse or PostToolUseFailure), subagent tool calls, and large
  outputs. All three are named gaps in the ADR-287 addendum.
