# `permissionDecision: "defer"` empirical verification

**Date:** 2026-05-15
**CC version:** 2.1.142 (Claude Code)
**Probe mechanism:** `CLAUDE_CONFIG_DIR=/tmp/cc-probe-0.2 claude --print` with stub `PreToolUse(Bash)` hook returning wrapped permission envelope; `PostToolUse(Bash)` sentinel to detect whether the call executed.

## Outcome

`permissionDecision: "defer"` is **accepted and honored** by CC 2.1.142 — but only when wrapped in the full envelope shape with `hookEventName: "PreToolUse"` at the same level as `permissionDecision`.

## Chosen value

```
DEFER_VALUE="defer"
```

This matches the plan's stated intent (silent pause, operator resumes via `claude --resume <session_id>`).

## Envelope shape (mandatory)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "defer",
    "permissionDecisionReason": "<rule_id>: <prose>"
  }
}
```

**Gotcha discovered during probe:** without `hookEventName: "PreToolUse"` in the inner object, CC silently ignores the entire `hookSpecificOutput` and the tool proceeds (probed: same envelope minus `hookEventName` → bash executed). The Soleur learning `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` mentions `hookSpecificOutput.permissionDecision[Reason]` but does not call out the `hookEventName` requirement. Recording it here as the load-bearing detail; `prod-write-defer-gate.sh` MUST include it.

## Comparison table (probed)

| `permissionDecision` value | hook stdin reached | Bash executed (PostToolUse fired) | Agent-visible message |
|---|---|---|---|
| `defer` + `hookEventName` | yes | NO | (empty — silent pause) |
| `ask` + `hookEventName` | yes | NO | "blocked by a hook returning `<reason>`" |
| `deny` + `hookEventName` | yes | NO | "denied by a hook (`<reason>`)" |
| `allow` (any shape) | yes | YES | (allowed silently) |
| (no JSON, `exit 2` + stderr) | yes | NO | "blocked by a PreToolUse hook (`<path>`) which denied execution via exit code 2 with the message `<stderr>`" |
| `defer` WITHOUT `hookEventName` (control) | yes | YES | (envelope silently ignored, bash ran) |

## Implementation directives for `prod-write-defer-gate.sh`

1. Set `DEFER_VALUE="defer"` (no fallback to `"ask"` needed in CC 2.1.142).
2. Always emit the wrapped envelope with `hookEventName: "PreToolUse"`. Bare `{"permissionDecision":"defer",...}` is silently ignored.
3. In enforce mode (`SOLEUR_DEFER_DRYRUN=0`): emit the wrapped `defer` envelope and ALSO print the resume hint (`claude --resume <session_id>`) to stderr. CC's own user-facing rendering of `defer` is silent — the operator needs the resume hint somewhere visible.
4. In dry-run mode (`SOLEUR_DEFER_DRYRUN=1`): output `{}` (no envelope, no decision). Tool falls through to default permission flow.

## Re-probe trigger conditions

Repeat this probe if any of:

- CC version major bump (2.x → 3.x), OR
- Docs migrate `permissionDecision` to a different field, OR
- The agent sees user-reports of `defer` no longer pausing the session (would manifest as production traffic that the gate "deferred" but the tool ran anyway).

## Probe artifacts

- Probe directory: `/tmp/cc-probe-0.2/` (mirrors `~/.claude/` with stub `settings.json`, copied `.credentials.json`, stub hook scripts).
- Stub `PreToolUse(Bash)` hook: returns the wrapped envelope and writes stdin to `/tmp/defer-probe-stdin.json`.
- Sentinel `PostToolUse(Bash)` hook: appends to `/tmp/defer-probe-bash-fired.log` — its absence is the "Bash did not execute" signal.
- Disposable; safe to `rm -rf /tmp/cc-probe-0.2/` after this PR ships.

---

## Operator stage approval (ADR-264), measured 2026-10-01

**Date:** 2026-10-01
**CC version:** 2.1.287 (Claude Code)
**Decision record:** `knowledge-base/engineering/architecture/decisions/ADR-264-generated-operator-scripts-are-agent-run-in-stages.md`
**Consumer:** `plugins/soleur/hooks/operator-stage-approval.sh`

**Probe mechanism.** A nested `claude -p` (headless) and an interactive `claude` session driven in
tmux, each with a stub `PreToolUse(Bash)` hook and a sentinel `PostToolUse(Bash)` hook in a
throwaway `--settings` file. The stubs wrote their stdin to a scratch file and answered a fixed
envelope; the sentinel recorded the command PostToolUse received. Nothing touched production, no
real credential was read, and the stub never minted a receipt.

`updatedInput` REPLACES `tool_input` (it does not merge): that is already measured in
`UPDATED-INPUT-PAYLOAD-SHAPE.md`, section "`updatedInput` REPLACES `tool_input`. It does not
merge.", and is cited here, not re-measured. The rows below are what is new.

| # | Question | Result (2.1.287) |
|---|---|---|
| 1 | `permissionDecision: "ask"` together with `updatedInput`: what does the interactive prompt show, and what runs? | The prompt shows the REWRITTEN command and the hook's `permissionDecisionReason` ("Hook PreToolUse:Bash requires confirmation for this command"). PostToolUse receives the rewritten command, and the rewritten command executes after approval |
| 2 | Does the hook's `ask` hold against an allow rule and under `bypassPermissions`? | Yes. With an allow rule `Bash(echo:*)` matching the ORIGINAL command, and under `--permission-mode bypassPermissions`, the hook's `ask` still prompts (the hook decision holds). The PreToolUse payload carries `permission_mode` (`default` versus `bypassPermissions`) |
| 3 | Headless `claude -p`: what does `defer` do, and does `--resume` re-run the hook? | `defer` ends the turn with terminal_reason `tool_deferred`; the deferred input shows the ORIGINAL command. `claude -p --resume <session>` re-runs the hook, and an environment variable set on the RESUMED process (`SOLEUR_RESUME_APPROVED_DIGEST=abc123`) is visible to the hook. A hook answering `allow` plus `updatedInput` on resume executes the rewritten command. **Not relied on (review, 2026-10-02):** a settings-file `env` block written through an ordinary Bash call reaches the hook of a fresh process, so an environment marker is agent-writable; ADR-264 therefore resumes interactively and approves at the prompt |
| 4 | Is there an interactive versus headless discriminator? | `CLAUDE_CODE_ENTRYPOINT` is `cli` in an interactive session and `sdk-cli` under `claude -p`. The PreToolUse payload also carries `permission_mode`, `session_id`, `cwd`, `tool_use_id`, `prompt_id` |
| 5 | Does the tool_use input the model sees afterwards leak the nonce? | No. The input the model sees is the ORIGINAL command (no nonce). The nonce appears in the transcript's hook_success attachment (the hook's stdout; a file the agent can read), in the human-visible prompt, and in a headless permission_denials result record. It is single-use, bound to the exact command digest and the script's bytes, and live for at most five minutes; a replay of a nonce from a declined prompt is a deliberate act (ADR-264 residual list) |
| 6 | What is the first line of the interactive prompt above the command? | The model-authored `description` field, not the real command. The real command is the line below it |

**What the hook relies on, by row.** Row 1 is the load-bearing one: if `ask` plus `updatedInput`
stops showing the rewritten command, the human approves a string that is not the one that runs,
and the write path must stop. Rows 2 and 4 decide the deny and `defer` branches: an unknown mode
or an undeterminable entrypoint never reaches `allow`. Row 3 is the headless resume path. Row 5
is why the nonce can ride in the command at all.

## Re-probe trigger conditions (operator stage approval)

Repeat rows 1 to 5 if any of:

- the Claude Code version changes (the numbers above are for 2.1.287; a minor bump counts, because
  the prompt rendering, `permission_mode` values and `CLAUDE_CODE_ENTRYPOINT` values are not a
  documented contract), OR
- a user report that the permission prompt shows the original command rather than the rewritten
  one, or that a deferred command ran without a resume, OR
- a new permission mode is added (the hook denies an unknown mode today, so a new one fails
  closed, but a re-probe confirms it is neither silently allowed nor silently denied).

Probe artifacts: the throwaway `--settings` file and stub hooks live in the probe's scratch
directory and are disposable.
