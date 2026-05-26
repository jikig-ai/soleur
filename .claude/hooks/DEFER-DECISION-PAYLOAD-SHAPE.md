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
