# PermissionDenied event payload shape — empirical probe

**Date:** 2026-05-15
**CC version:** 2.1.142 (Claude Code)
**Probe mechanism:** `CLAUDE_CONFIG_DIR=/tmp/cc-probe-0.1 claude --print` with stub `PermissionDenied` hook that captures stdin to `/tmp/perm-denied-payload.json`.

## Outcome: event does NOT fire

Across four permission-mode configurations (`default`, `auto`, `dontAsk`, with both narrow `--allowedTools "Bash(echo *)"` and broad/no allowlist), no `PermissionDenied` hook invocation was observed. In every run:

- `PreToolUse:Bash` fired with full payload (`tool_name`, `tool_input.command`, `session_id`, `tool_use_id`, `hook_event_name`, `permission_mode`).
- The denial happened (Bash command blocked by sandbox / permission kernel) — and the agent's user-facing text described it as such.
- The stub `PermissionDenied` hook captured **zero invocations**: `/tmp/perm-denied-payload.json` was never created.
- A `stream-json --include-hook-events --verbose` run surfaced only `SessionStart`, `PreToolUse:Bash` events.

The official Claude Code docs (`anthropics/claude-code` plugin-dev hook-development skill, context7 query 2026-05-15) enumerate hook events as `PreToolUse`, `PostToolUse`, `Stop`, `UserPromptSubmit`, `SessionStart`, `SubagentStop`, `Notification`, `PreCompact`. **`PermissionDenied` is not in the documented event set in CC 2.1.142.**

## Plan-mandated consequence

Per `2026-05-15-feat-deterministic-permissions-plan.md` BLOCKING gate (Phase 0 §0.1):

> if `PermissionDenied` event does not fire OR payload lacks tool_name/tool_input/reason fields, F1 collapses to roadmap entry; this PR proceeds with F2-only.

**F1 is collapsed to roadmap entry.** This PR ships F2 (prod-write defer gate) only. The `emit_incident` `kind` extension (Phase 1.1–1.3) still lands because F2 depends on it (`kind: "would_defer"`, `kind: "defer_requested"`, `kind: "bypass"`, `kind: "hook_self_fault"`).

## Follow-up roadmap entry

F1 (kernel-decided-denial telemetry) is deferred until either:

1. CC introduces a `PermissionDenied` (or analogous) event in a future release. Re-run this probe with the same `CLAUDE_CONFIG_DIR` mechanism to validate before un-collapsing F1; OR
2. A `PreToolUse`-based approximation is designed that fires only when the *kernel* would deny (not when an earlier `PreToolUse` hook denies — F2 already covers that surface). Note this conflates F1+F2 capture and requires care to keep their event sets disjoint per the plan's design intent.

## Probe artifacts

- Probe directory: `/tmp/cc-probe-0.1/` (mirrors `~/.claude/` with stub `settings.json`, copied `.credentials.json`, stub hook scripts under `hooks/`).
- Stub `PermissionDenied` hook: writes stdin to `/tmp/perm-denied-payload.json` and appends a timestamped record to `/tmp/perm-denied-payload-debug.log`.
- Sentinel `PreToolUse:Bash` hook (added during diagnosis): writes to `/tmp/cc-probe-0.1/hook-firings.log`. This hook DID fire — proving the probe scaffolding loaded settings.json correctly and is not itself broken.
- Disposable; safe to `rm -rf /tmp/cc-probe-0.1/` after this PR ships.
