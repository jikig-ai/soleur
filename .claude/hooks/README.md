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

## Change-class loader (#3493)

`session-rules-loader.sh` is a **SessionStart** hook (matchers
`startup|resume|clear|compact`) — it does not block tool calls. It computes
the session's change-class from `git diff --name-only origin/main...HEAD ∪
git status --porcelain` and injects the matching `AGENTS.<class>.md`
sidecar(s) into `hookSpecificOutput.additionalContext`. See spec at
`knowledge-base/project/specs/feat-agents-md-change-class-loader/spec.md`.

### Operator commands

Inspect what the loader picked for the active session:

```bash
cat .claude/.session-manifests/$(ls -t .claude/.session-manifests/ | head -1)
```

Force a full re-load when scope shifts mid-session (e.g., a docs-only session
that pivots into code):

```bash
LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh \
  < <(printf '{"cwd":"%s"}' "$PWD")
```

### Default class

- Empty diff (fresh worktree, on main, no uncommitted) → `mixed` → all
  sidecars loaded (fail-closed).
- Multi-class diff → `mixed` → all sidecars loaded.
- Missing sidecar file at runtime → all available sidecars loaded with a
  `(fail-safe: sidecar missing)` annotation in the stamp.

### Manifests

Per-session manifests at `.claude/.session-manifests/<session_id>.json` carry
the three fields `{timestamp, change_class, rule_ids_loaded}` — sufficient for
SOC 2 CC6.1/CC7.2 evidence ("which rules were in context at session X").
The directory is gitignored.

### Sharp Edges (SessionStart hook design)

- **`set -e` between classifier and emit is a `single-user incident` vector.**
  Any SessionStart hook that emits `hookSpecificOutput.additionalContext`
  MUST guarantee non-empty output on every error path. A non-zero exit from
  `mkdir -p`, `jq`, `git`, or a disk-full manifest write makes Claude Code
  inject zero additional context — the agent boots with only the pointer
  index and NO rule bodies, including compliance-tier rules.
  `session-rules-loader.sh` uses `set -uo pipefail` + `trap ERR
  emit_core_only_fallback` to keep the agent in a safe-degraded state
  instead of a no-rules state.
- **Envelope `cwd` is untrusted.** Assert
  `git rev-parse --is-inside-work-tree` against the resolved `REPO_ROOT`
  before writing files relative to it; otherwise a crafted envelope
  redirects manifest writes to any operator-writable directory.
- **Envelope `session_id` is untrusted as a filename component.** Sanitize
  to `[A-Za-z0-9._-]` and reject `.`/`..`/empty. Substring matching against
  the parent directory is insufficient.
- **Symlinked sidecars are an injection vector.** Reject `[[ -L ]]` reads
  before concatenating into `additionalContext`.
