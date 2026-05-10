# Claude Code Hooks

PreToolUse hooks enforce AGENTS.md rules and constitutional guards. They also
emit **rule-incident telemetry** so the repo can tell which rules earn their
keep (see
`knowledge-base/project/plans/2026-04-14-feat-rule-utility-scoring-plan.md`).

## Hook contract

Every hook reads a JSON envelope from stdin, decides allow/deny, and (for
denies) emits a `hookSpecificOutput` payload then `exit 0`:

```bash
jq -n '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: "BLOCKED: ..."}}'
exit 0
```

Claude Code reads that JSON from stdout and blocks the tool call. Any deviation
from this shape is treated as a pass-through.

## Incident telemetry (ADR-2)

Hooks call `emit_incident` **before** the deny payload to record one JSON line
in `.claude/.rule-incidents.jsonl`. This write is:

- **Side-effect only** — the CC hook response payload is unchanged.
- **Fire-and-forget** — every jq / flock call is wrapped in `2>/dev/null || true`,
  so a hiccup in telemetry never blocks the hook's actual decision.
- **flock-guarded** — concurrent hook invocations serialize on the file itself;
  `jq -c` emits one-line JSON so lines never interleave.

### API

```bash
# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

emit_incident "<rule_id>" "<event_type>" "<rule_text_prefix>" ["<command_snippet>"]
```

| Field | Meaning |
|---|---|
| `rule_id` | Stable slug from `AGENTS.md` (`hr-*`, `wg-*`, `cq-*`, `rf-*`, `pdr-*`, `cm-*`) or a `guardrails-*` sentinel for constitution-only rules. |
| `event_type` | `deny` (hook blocked the action) or `bypass` (user used a skip flag). |
| `rule_text_prefix` | First ~50 chars of the rule's prose, for forensic context. |
| `command_snippet` | Optional: the full command (or file path) that triggered the event. |

`BASH_SOURCE[0]` is used to resolve the repo root — `$0` returns the caller of
the sourced file, not the library itself.

### v1 bypass detection

`detect_bypass "<tool_name>" "<command>"` returns a rule_id when the command
uses a known skip flag:

- `--no-verify` → `cq-never-skip-hooks`
- `LEFTHOOK=0`  → `cq-when-lefthook-hangs-in-a-worktree-60s`

Deferred to v2 until the dataset shows it: `--force` on main, `--no-gpg-sign`,
`--amend` after a same-session deny.

## Rotation

Three telemetry sinks under `.claude/` rotate via a shared helper at
`.claude/hooks/lib/log-rotation.sh`:

| Sink | Owner |
|---|---|
| `.claude/.rule-incidents.jsonl` | `lib/incidents.sh::emit_incident` (#2213) |
| `.claude/.skill-invocations.jsonl` | `skill-invocation-logger.sh` (#3122) |
| `.claude/.session-tokens.jsonl` | `agent-token-tee.sh` (#3494) |

### Per-write rotator (primary)

Each writer calls `rotate_if_needed "$file"` immediately before acquiring its
own write flock. The rotator:

1. Pre-checks size and mtime without holding a lock (>99% of calls exit here).
2. Acquires `flock -w 5 -x 9` against `$file`.
3. Re-checks inside the lock (TOCTOU defense — a peer writer may have rotated
   between the pre-check and the acquire).
4. `cat "$active" >> "$archive"` then `: > "$active"` — copy-then-truncate,
   NOT atomic-rename. Inode is preserved so concurrent writers' flocks remain
   valid; truncate is gated on cat success so disk-full leaves data intact.
5. `gzip -f "$archive"` outside the lock.

Defaults: 5 MB size threshold, 30-day age threshold, 5-second flock timeout.
Per-call override:

```bash
rotate_if_needed "$file" 1048576 7   # 1 MB / 7 days
```

Per-process env overrides:

| Var | Default | Purpose |
|---|---|---|
| `LOG_ROTATION_SIZE_BYTES` | 5242880 | Size threshold in bytes |
| `LOG_ROTATION_AGE_DAYS` | 30 | Age threshold in days |
| `LOG_ROTATION_FLOCK_TIMEOUT_S` | 5 | flock acquire timeout (seconds) |
| `LOG_ROTATION_DISABLE` | _(unset)_ | Set to `1` to short-circuit all rotation |
| `LOG_ROTATION_UNIQ_SUFFIX` | `$(date +%H%M%S%N)` | Test-only collision suffix override |

On archive-write failure (disk full, permission denied), the helper preserves
the active file, removes the partial archive, and emits ONE stderr warning
per process — `[log-rotation] warning: failed to archive <path> ...`. Mirrors
the warn-once pattern at `incidents.sh:130-138`.

### Aggregator rotator (defense-in-depth)

`scripts/rule-metrics-aggregate.sh` retains its weekly `AGGREGATOR_ROTATE=1`
block. In steady state it sees an already-rotated empty file — its
`[[ -s "$INCIDENTS" ]]` guard skips quietly. Kept as a CI-side safety net for
operator scenarios where the per-write rotator never fires (long-idle
machines that never trigger a hook between aggregations).

All active and archived files are gitignored under wildcards
(`.claude/.rule-incidents*`, `.claude/.skill-invocations*`,
`.claude/.session-tokens*`).

### Library API

```bash
# shellcheck source=lib/log-rotation.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/log-rotation.sh"

rotate_if_needed <jsonl-path> [size-bytes] [age-days]
```

Always exits 0. Fire-and-forget — never blocks the calling hook even if the
helper itself errors.

## Hook roster

| Hook | Denies | Rule IDs emitted |
|---|---|---|
| `guardrails.sh` | 6 | `guardrails-block-commit-on-main`, `guardrails-block-rm-rf-worktrees`, `guardrails-block-delete-branch`, `guardrails-block-conflict-markers`, `guardrails-require-milestone`, `hr-never-git-stash-in-worktrees` |
| `pencil-open-guard.sh` | 1 | `cq-before-calling-mcp-pencil-open-document` |
| `worktree-write-guard.sh` | 1 | `guardrails-worktree-write-guard` |

### Telemetry-only hooks (PostToolUse, no deny semantics)

| Hook | Sink | Purpose |
|---|---|---|
| `skill-invocation-logger.sh` | `.claude/.skill-invocations.jsonl` | Records every Skill tool call (session_id + skill name) for the monthly skill-freshness aggregator. |
| `agent-token-tee.sh` | `.claude/.session-tokens.jsonl` | Records every Task/Agent invocation envelope (session_id + subagent_type + total_tokens + duration) for compound Phase 1.6 token-efficiency analysis. Kill-switch: `SOLEUR_DISABLE_AGENT_TOKEN_TEE=1`. Issue #3494. |

## macOS note

`flock` is not installed by default on macOS. Dev machines need:

```bash
brew install flock
```

Without `flock`, the `emit_incident` helper still exits cleanly (the `|| true`
guard) — you just won't get telemetry locally. CI (Ubuntu) always has `flock`.
