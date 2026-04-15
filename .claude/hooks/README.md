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

`scripts/rule-metrics-aggregate.sh` runs weekly (via
`.github/workflows/rule-metrics-aggregate.yml`). After a successful roll-up it
gzips `.claude/.rule-incidents.jsonl` to
`.claude/.rule-incidents-YYYY-MM.jsonl.gz` and truncates the active file.
Both the active and archived files are gitignored (see `.gitignore`).

## Hook roster

| Hook | Denies | Rule IDs emitted |
|---|---|---|
| `guardrails.sh` | 6 | `guardrails-block-commit-on-main`, `guardrails-block-rm-rf-worktrees`, `guardrails-block-delete-branch`, `guardrails-block-conflict-markers`, `guardrails-require-milestone`, `hr-never-git-stash-in-worktrees` |
| `pencil-open-guard.sh` | 1 | `cq-before-calling-mcp-pencil-open-document` |
| `worktree-write-guard.sh` | 1 | `guardrails-worktree-write-guard` |

## macOS note

`flock` is not installed by default on macOS. Dev machines need:

```bash
brew install flock
```

Without `flock`, the `emit_incident` helper still exits cleanly (the `|| true`
guard) — you just won't get telemetry locally. CI (Ubuntu) always has `flock`.
