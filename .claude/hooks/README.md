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

## Parsing hook input

**That stdin envelope is model-controlled and untrusted** ([ADR-156][adr155]).
It is assembled from the model's own tool-call output; nothing a hook can see
validates it. Parse it with the shared extractor — never by hand, and never with
`eval`:

```bash
# shellcheck source=lib/hook-input.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"   # FAIL-HARD

INPUT=$(cat)
if ! hook_parse_input "$INPUT"; then
  hook_input_report "<hook-basename>"
  hook_input_should_ask && { hook_input_emit_ask "<hook-basename>"; exit 0; }
  exit 0
fi
CMD="$HOOK_CMD"          # also: HOOK_TOOL_NAME HOOK_CWD HOOK_SESSION_ID HOOK_FILE_PATH
```

`hook_parse_input` returns 0 only when the document parses **and** every
contracted field is a string; the values are then byte-exact. Any other outcome
returns 1 and classifies via `HOOK_INPUT_REASON` (`nonstring`, `unparseable`,
`separator`, `jq_missing`, `internal`). **The return code is normative; the
reason is diagnostic.**

Four rules, each of which was a real defect in #7164:

1. **Source it fail-hard.** No `|| true`, no `|| :`, no `2>/dev/null`. A
   fail-soft source leaves `hook_parse_input` undefined, the hook dies at the
   call under `set -e`, prints nothing, exits non-zero — and the tool proceeds.
2. **The `exit` lives at the call site**, never in the library. A sourced
   library that exits terminates its caller invisibly, is untestable without a
   subshell, and silently no-ops inside `$( )` or a pipeline.
3. **Never coerce a non-string.** Coercion (`tojson`) closes the code execution
   and leaves every anchored guard evaded — `["git","stash"]` matches no guard
   regex. Same for scrubbing: a normalized value is a *different* value than the
   matcher was written against.
4. **A hook that cannot parse its input asks** ([ADR-157][adr156]). It never
   continues silently and it never denies.

`guardrails.sh` is the **designated responder**: it emits the `ask`, the other
19 report and exit 0, so a persistent fault produces one prompt per tool call
rather than 18. That makes `guardrails.sh` load-bearing for the others, and
`hook-input-contract.test.sh` asserts against `.claude/settings.json` that every
tool triggering a migrated hook also triggers `guardrails.sh`.

`SOLEUR_DISABLE_HOOK_INPUT_ASK=1` suppresses **escalation only** — parsing, the
type assertion and the telemetry still run. It is the in-band escape hatch if
the posture ever proves noisy.

### Verifying the fault path end to end

One command, no SSH, no dashboard. It proves both halves: the operator is told
**synchronously** (the `ask`), and the fault reaches the surface a human reads
**later** (the aggregate counter).

```bash
R=$(mktemp -d)
cp AGENTS.md AGENTS.rules.md "$R/"          # the aggregator resolves rules from this root
printf 'not-json' | INCIDENTS_REPO_ROOT="$R" bash .claude/hooks/guardrails.sh \
  | jq -r '.hookSpecificOutput.permissionDecision'          # -> "ask"
INCIDENTS_REPO_ROOT="$R" bash scripts/rule-metrics-aggregate.sh --dry-run \
  | jq '.summary.hook_input_fault_count'                    # -> 1
rm -rf "$R"
```

The `cp AGENTS.md AGENTS.rules.md` line is load-bearing and was **missing from
the original plan's version of this probe**: `INCIDENTS_REPO_ROOT` is read by
*both* the incident emitter (for the ledger path) and the aggregator (for the
rule corpus), so a bare `mktemp -d` makes the aggregator exit 2 with
`AGENTS.md not found` and the count comes back empty. The probe reported a
failure that was its own, not the code's — the same "declared-verifiable but
never executed" gap that #7164's `@sh`-is-safe comment belongs to. Corrected
here after running it.

### Scope of the mandate

**Mandatory** for hooks on the `Bash` matcher and for blocking write guards —
the 20 hooks that can change whether a tool call proceeds:

`guardrails` · `cla-signed-author-gate` · `context-reviewed-gate` ·
`follow-through-directive-gate` · `prod-write-defer-gate` ·
`ship-net-issue-flow-gate` · `ship-operator-step-gate` · `ship-runbook-ssh-gate` ·
`ship-soak-followthrough-gate` · `ship-unpushed-commits-gate` ·
`background-poll-prefer-monitor` · `brand-hex-commit-gate` ·
`doppler-secrets-delete-redirect` · `git-commit-secret-scan` ·
`kb-domain-allowlist-guard` · `no-memory-write` · `pre-merge-auto-close-scan` ·
`pre-merge-rebase` · `worktree-write-guard` · `iac-plan-write-guard`

**Not yet migrated** — 10 hooks, in two groups. All remain bound by ADR-156
clause 1 (no `eval`), which the contract test enforces repo-wide.

*Genuinely advisory* (6) — they emit no `permissionDecision` at all, so a
mis-parsed field costs a hint rather than a guard:

`agent-token-tee` · `docs-cli-verification` · `pencil-collapse-guard` ·
`phase-surface-hint` · `skill-context-queries` · `skill-invocation-logger`

*Gating, but deferred* (4) — **these DO decide whether a tool call proceeds** and
are in ADR-156's binding scope. They are not exempt on principle; they are
blocked on two concrete things, and they are the priority set in the follow-up:

| Hook | Matcher | Emits |
|---|---|---|
| `durable-reminder-prefer-inngest` | `CronCreate` | `deny`, `allow` |
| `new-scheduled-cron-prefer-inngest` | `Write\|Edit` | `deny`, `allow` |
| `pencil-open-guard` | `mcp__pencil__open_document` | `deny` |
| `skill-security-scan-write` | `Write` | `deny`, `ask`, `allow` |

The two blockers, both real:

1. **Every one needs a field the extractor does not publish** — `filePath`
   (camelCase), `.tool_input.skill`, `.tool_input.content`, `.tool_input.new_string`,
   and — for `durable-reminder-prefer-inngest` — `.durable` / `.recurring`, which
   are legitimately **booleans**. `all(type == "string")` structurally cannot
   express a boolean field, so migrating these widens the fixed-slot contract.
   That is exactly what ADR-157 rejected a variadic API to avoid, so it is a
   design decision, not a paste.
2. **Three of their matchers have no designated responder.** `guardrails.sh` is
   wired on `Bash` and `Write|Edit|MultiEdit|NotebookEdit` only, so `CronCreate`,
   `Skill` and `mcp__*` payloads have nothing to emit the `ask`. Migrating them
   fails the designated-responder invariant (AC14) until that is resolved.

`skill-security-scan-write` is the sharpest of the four: it can emit an explicit
`allow`, which skips the permission prompt outright, and an array
`.tool_input.content` renders multi-line under `jq -r` so it matches no
HIGH-RISK pattern. `pencil-open-guard` is the clearest ADR-156 case — an `mcp__*`
matcher is precisely the "other tool shapes" whose envelope this repo does not
define — but it is one of the *harder* migrations, not the easiest, because it
needs the unpublished camelCase `filePath` **and** has no responder.

Tracked in **#7173**.

`.openhands/hooks/` mirrors carry a **minimal in-place** type assertion instead
of this helper: a different envelope (`.working_dir`, `.tool_input.path`) and a
different protocol (`exit 2` + `{"decision":"deny"}`, with no `ask`).
Convergence is a tracked follow-up.

[adr155]: ../../knowledge-base/engineering/architecture/decisions/ADR-156-hook-stdin-is-model-controlled-and-untrusted.md
[adr156]: ../../knowledge-base/engineering/architecture/decisions/ADR-157-a-hook-that-cannot-parse-its-input-asks.md

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

### Bypass detection

`detect_bypass "<tool_name>" "<command>"` returns a rule_id when the command
uses a known skip flag (telemetry-only, not block):

- `--no-verify`               → `cq-never-skip-hooks` (skip pre-commit/commit-msg hooks)
- `-c core.hooksPath=…`       → `cq-never-skip-hooks` (redirect hooks dir, commonly to /dev/null)
- `HUSKY=0`                   → `cq-never-skip-hooks` (disable Husky pre-commit)
- `--no-gpg-sign`             → `cq-never-skip-hooks` (bypass commit signing)
- `-c commit.gpgsign=false`   → `cq-never-skip-hooks` (bypass signing via inline config)
- `LEFTHOOK=0`                → `cq-when-lefthook-hangs-in-a-worktree-60s`

Deferred until the dataset shows it: `--force` on main, `--amend` after a
same-session deny.

`core.hooksPath`, `HUSKY=0`, `--no-gpg-sign`, `commit.gpgsign=false` added
2026-05-12 after a self-corrected anticipatory bypass; see
`knowledge-base/project/learnings/2026-05-12-anticipatory-hook-bypass-and-leader-substrate-cross-check.md`.

## Rotation

Four telemetry sinks under `.claude/` rotate via a shared helper at
`.claude/hooks/lib/log-rotation.sh`:

| Sink | Owner |
|---|---|
| `.claude/.rule-incidents.jsonl` | `lib/incidents.sh::emit_incident` (#2213) |
| `.claude/.skill-invocations.jsonl` | `skill-invocation-logger.sh` (#3122) |
| `.claude/.session-tokens.jsonl` | `agent-token-tee.sh` (#3494) |
| `.claude/.memory-backstop.jsonl` | `memory-backstop.sh` (#7166) |

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
`.claude/.session-tokens*`, `.claude/.memory-backstop*`).

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

### PostToolUse hooks (no deny semantics)

PostToolUse runs after the tool's write, so these cannot block. Most are telemetry-only; `pencil-collapse-guard.sh` additionally performs a file restore and injects `additionalContext` into the model.

| Hook | Sink | Purpose |
|---|---|---|
| `skill-invocation-logger.sh` | `.claude/.skill-invocations.jsonl` | Records every Skill tool call (session_id + skill name) for the monthly skill-freshness aggregator. |
| `agent-token-tee.sh` | `.claude/.session-tokens.jsonl` | Records every Task/Agent invocation envelope (session_id + subagent_type + total_tokens + duration) for compound Phase 1.6 token-efficiency analysis. Kill-switch: `SOLEUR_DISABLE_AGENT_TOKEN_TEE=1`. Issue #3494. |
| `memory-backstop.sh` | `.claude/.memory-backstop.jsonl` | **SessionStart** (`startup|resume|clear|compact`). Adopts the agent process tree into a memory-capped systemd transient scope `soleur-agent-<pid>.scope` under a shared `soleur-agents.slice` (ADR-159, #7166). Records the scope, the terminal scope it is bound to, the caps written, the caps the slice already had (`slice_*_before`, so a mixed-version fleet flapping the shared slice is visible), and `outcome`/`reason`. Never records the session id. Kill-switch: `SOLEUR_DISABLE_MEMORY_BACKSTOP=1` — **if you set it you are unprotected and nothing will tell you.** |
| `pencil-collapse-guard.sh` | `.claude/.rule-incidents.jsonl` (`cq-pencil-collapse-auto-recover`, `warn`) | PostToolUse on `mcp__pencil__open_document`: auto-restores a tracked `.pen` collapsed to empty document state from `git HEAD` + emits an `additionalContext` warning. Fail-open, non-destructive. Issue #4859. |

## macOS note

`flock` is not installed by default on macOS. Dev machines need:

```bash
brew install flock
```

Without `flock`, the `emit_incident` helper still exits cleanly (the `|| true`
guard) — you just won't get telemetry locally. CI (Ubuntu) always has `flock`.

## Rule-corpus loader (#3493 index/body split, ADR-151 unconditional corpus)

`session-rules-loader.sh` is a **SessionStart** hook (matchers
`startup|resume|clear|compact`) — it does not block tool calls. It injects the
whole rule corpus (`AGENTS.rules.md`, frontmatter-stripped) into
`hookSpecificOutput.additionalContext`, together with the `(N of M rules)` stamp,
the `[session-context]` snapshot, and the tmpfs-guard alarm block.

ADR-151 retired the change-class CLASSIFIER. There is no longer a per-session
class, no conditional sidecar selection, and no fail-closed escape-hatch env var
— every rule is in context from the first turn of every session. The measured
saving from conditionality was ~8% of session-start bytes against a majority
class (70% of sessions were multi-class and loaded everything anyway), and it
cost two silent-drop incidents where a rule was absent from exactly the sessions
it was written to fire on.

### Operator commands

Inspect what the loader recorded for the active session:

```bash
cat .claude/.session-manifests/$(ls -t .claude/.session-manifests/ | head -1)
```

Re-run the loader against a specific worktree:

```bash
bash .claude/hooks/session-rules-loader.sh < <(printf '{"cwd":"%s"}' "$PWD")
```

### Failure modes

- Corpus missing or symlink-rejected → `CONTEXT` is empty, the stamp reads
  `0 of N rules — fail-safe: <cause>`, and the numerator is the
  governance-blackout signal. The denominator comes from the `AGENTS.md` pointer
  count (a FIXED expected set), never from what actually loaded — otherwise it
  would degrade in lockstep and render a truncated corpus as 100%.
- Frontmatter over-strip → the RAW corpus is injected instead (rules preserved,
  frontmatter leaked) plus a loud `WARN` in the stamp.

### Manifests

Per-session manifests at `.claude/.session-manifests/<session_id>.json` carry
the three fields `{timestamp, change_class, rule_ids_loaded}` — sufficient for
SOC 2 CC6.1/CC7.2 evidence ("which rules were in context at session X").
Since ADR-151 the key is kept rather than dropped so the evidence schema stays
stable, and it carries `"all"` on the happy path. On a fail-safe path it carries
`"fail-safe:<cause>"` instead — a bare constant would be unfalsifiable, and a
blackout session would otherwise record `{"change_class":"all",
"rule_ids_loaded":[]}`, asserting "all" for a session that loaded zero rules.

**No manifest is written on the `emit_core_only_fallback` path**, and that is
deliberate rather than an oversight: the dominant reason that path fires is
`cwd` resolving OUTSIDE a git worktree, so writing there would let a crafted
envelope (`{"cwd":"/tmp/x"}`) plant files at an arbitrary location — the exact
vector the `is-inside-work-tree` guard exists to block. The evidence gap on that
path is accepted in exchange for the write guard; the FALLBACK stamp still
carries a `loaded: N of M` count.
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

## F2 prod-write defer gate (`prod-write-defer-gate.sh`)

A PreToolUse(Bash) hook that defers a hardcoded list of prod-write commands
for explicit operator approval. Position 4 in the PreToolUse(Bash) chain,
after `ship-unpushed-commits-gate.sh`.

### Starter manifest (3 entries, telemetry-driven expansion)

| `rule_id` | matches |
|---|---|
| `prod-write-defer-git-push-main` | `git push origin {main,master,HEAD:main,HEAD:master}` incl. `-f`, `--force-with-lease`, refspec, env-prefix, wrapped via `-- <cmd>`, chained `&&`/`;` |
| `prod-write-defer-terraform-apply` | `terraform apply` and `tofu apply` (same anchors) |
| `prod-write-defer-doppler-secrets-stdout` | `doppler secrets {set,delete} ... --config {prd,prd_terraform,prd_orchestration,dev,ci}` (rejects `prd-staging`, equals-form `--config=prd`, `--help`/`-h`); widened 2026-05-18 via #4029 — `delete` renders the post-deletion surviving-secrets table to stdout, leaking value chunks from sibling secrets; `prd_orchestration` added at PR review since tenant-* runbooks operate against it |

Regex engine: bash ERE with POSIX `[[:space:]]`. Anchor
`(^|&&|\|\||;|[[:space:]]--[[:space:]])` catches wrapped invocations per
`knowledge-base/project/learnings/2026-05-12-cross-session-lock-lease-bash-primitives.md`.

### Modes

- **`SOLEUR_DEFER_DRYRUN=1`** (dry-run; introduced in PR #3787, demoted from default to opt-in in PR #3800). Match → emit
  `kind: "would_defer"`, return `{}` (allow). Collects telemetry without
  blocking work.
- **`SOLEUR_DEFER_DRYRUN=0`** (DEFAULT, hardcoded fallback; enforce-flipped in
  PR #3800 after an 18-day dry-run review). Match → emit `kind: "defer_requested"`,
  append `.claude/logs/approvals.jsonl` row, return the wrapped defer
  envelope:
  ```json
  {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer","permissionDecisionReason":"..."}}
  ```
  CC pauses the session silently; the resume hint
  (`claude --resume <session_id>`) is emitted to stderr so the operator can
  see it. See `DEFER-DECISION-PAYLOAD-SHAPE.md` for the empirical decision
  on `"defer"` and the load-bearing `hookEventName` field requirement.

### Bypass policy

`CLAUDE_HOOK_BYPASS=1` allows the call **only when**
`CLAUDE_HOOK_BYPASS_REASON` is also set (authorial requirement; no
interactive TTY-prompt path). Missing reason → `kind: "hook_self_fault"`
and DENY (fail-CLOSED). Operator identity is resolved
`CLAUDE_HOOK_BYPASS_OPERATOR` → `SOLEUR_OPERATOR_EMAIL` → `GITHUB_ACTOR` →
`git config --global --get user.email` → `unknown@local`. Bypass entries
go to `.claude/.rule-incidents.jsonl` as `kind: "bypass"`, NOT to the
approvals log — approvals.jsonl only records `tty_resume`/`env_override`/
`ci_actor` per the approval-method enum.

### Approval log (`.claude/logs/approvals.jsonl`)

Append-only, flock-guarded, 1-year TTL via `LOG_ROTATION_AGE_SECONDS`.
Schema:

```json
{"timestamp":"...","tool":"Bash","args_hash":"<sha256>","resolved_command":"...","operator_email":"...","approval_method":"tty_resume|env_override|ci_actor","rule_id":"...","session_id":"..."}
```

GDPR boundary: operator email = operator's own data; operator is both
controller and data subject. No third-party data subject content flows.
**External-observability boundary:** piping `approvals.jsonl` (or any
`.claude/logs/*`) to Sentry, Datadog, Plausible, or any external service
requires a DPA review — out of scope for this PR.

**Secret-in-argv caveat:** `doppler secrets set FOO=<value> --config prd_terraform`
captures the secret VALUE verbatim in `resolved_command` (capped 1024B,
unredacted) and in `.claude/.rule-incidents.jsonl` `command_snippet`. The
gate exists to surface the call for explicit approval, NOT to scrub it —
the originally-planned F1 redaction sibling was deferred to roadmap (see
PERMISSION-DENIED-PAYLOAD-SHAPE.md). The widened rule (2026-05-18 / #4029)
also covers `doppler secrets delete X --config prd` — `delete` does not
take a value argv slot, but the post-deletion stdout render is the leak
surface; the gate still fires so the operator can opt into `--silent` +
`>/dev/null 2>&1` before approving. Until F1 lands, treat `doppler
secrets set FOO=<value>` as a sensitive command surface; do not paste
`approvals.jsonl` / `.rule-incidents.jsonl` contents into bug reports or
external services. The `.gitignore` exclusion prevents accidental commit;
this caveat covers the share-into-tracker surface.

### Audit-trail review cadence (2-week dry-run window)

Run weekly during the dry-run window:

```bash
jq -c 'select(.kind == "would_defer") | .rule_id' \
  .claude/.rule-incidents.jsonl \
  | sort | uniq -c | sort -rn
```

Top-rule-id offenders inform manifest refinement. Add a new TARGETS entry
only after observer-side telemetry shows the pattern in actual workflow —
the dry-run window does NOT include CI/scheduled-runs (their
`.rule-incidents.jsonl` is ephemeral). Candidates parked for telemetry-
gated addition: `wrangler secret put` (prod), `supabase --linked db push`,
`stripe ... --live`, `gh release create`, `gh pr merge --admin`.

The enforce-flip (`SOLEUR_DEFER_DRYRUN` default 1 → 0) shipped in PR #3800
after the 18-day dry-run review confirmed manifest hit-rate (real prod-write
demand on the terraform-apply and doppler-secrets rules; zero phantom-rule
noise). Enforce is now the hardcoded default; set `SOLEUR_DEFER_DRYRUN=1` to
opt back into dry-run telemetry mode.

### F1 PermissionDenied event hook (deferred)

A complementary kernel-decided-denial telemetry hook was planned but
**collapsed to a roadmap entry** at Phase 0.1 empirical probe: CC 2.1.142
does NOT fire a `PermissionDenied` hook event. See
`PERMISSION-DENIED-PAYLOAD-SHAPE.md` for the probe details. F1↔F2 were
designed to capture **disjoint** event sets — F1 for kernel-decided
denials, F2 for hook-decided defers; with F1 deferred, F2 is the
load-bearing piece.

## Soak-gated follow-through enrollment gate (`ship-soak-followthrough-gate.sh`)

A PreToolUse(Bash) hook that blocks `gh pr ready` / `gh pr merge --auto` when
the PR (or its linked plan/spec) declares a **post-deploy soak / time-gated
close criterion** for a tracker issue that is NOT enrolled in the follow-through
sweeper. Mechanical twin of `ship/SKILL.md` §"Soak-Gated Follow-Through
Enrollment Gate" (`wg-pm-class-followthrough-for-operator-dogfood`) and a sibling
of `ship-operator-step-gate.sh`. Wired in the PreToolUse(Bash) chain after
`ship-operator-step-gate.sh`.

- **Fail-open:** non-merge command, no PR, no soak signal in the corpus, a tracker
  that can't be resolved (gh error), an HTML-comment override
  `<!-- gate-override: soak-followthrough-enrollment -->`, or
  `SOLEUR_SKIP_SOAK_FOLLOWTHROUGH_GATE=1`.
- **Fail-closed (deny):** a soak signal is present AND ≥1 referenced **OPEN**
  tracker is definitively unenrolled (missing the `follow-through` label, the
  `<!-- soleur:followthrough … -->` directive, or its on-disk
  `scripts/followthroughs/*.sh`). Closed trackers are exempt.
- `SOAK_RE` is kept **byte-identical** to the SKILL gate's regex; the parity is
  asserted by `plugins/soleur/test/ship-soak-followthrough-enrollment-gate.test.ts`.
- **Why:** 2026-06-29 — PR #5671 (#5673) and PR #5675 (#5689) both shipped
  soak-gated closures in prose with no sweeper enrollment; both trackers were
  left to rot until caught manually. See
  `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.

## Merge-boundary auto-close guard (`pre-merge-auto-close-scan.sh`)

A PreToolUse(Bash) hook on `gh pr merge`. GitHub's issue-closing parser reads the
**PR title, the PR body and the squash commit body**, so a closing keyword in any
of the three auto-closes on merge. Two checks, evaluated in this order:

1. **follow-through label gate** — denies a close of any form (standalone or
   prose-embedded) when the target issue is **OPEN** and carries
   `follow-through`. Closing such a tracker makes the daily sweeper skip it — it
   evaluates only OPEN issues — so the soak verification it exists to enforce
   silently never runs. A closed tracker is exempt: the harm is already done and
   denying would be a pure false positive.
2. **prose-embedded arm** — denies a close-keyword appearing after prose on its
   line, for any issue. A standalone `Closes #N` stays allowed; that is the form
   every ordinary fix-PR uses.

The deny names the issue **and every surface it was found in**, because the
keyword often has to be scrubbed in more than one.

### The five follow-through / auto-close surfaces

The hook header points here for the authoritative map. In lifecycle order:

| Surface | Trigger | Role |
|---|---|---|
| `follow-through-directive-gate.sh` | `gh issue create --label follow-through` | denies **creating** a tracker without a valid sweeper directive |
| `/ship` Phase 6 | pre-`gh pr create` | blocks any auto-close match whose issue is outside the PR's intended set — **broader** than this hook's prose arm (it flags standalone closes too) |
| `pr-auto-close-scanner.yml` | `pull_request` events | **observational only** (always exits 0; its header says so) |
| `ship-soak-followthrough-gate.sh` | `gh pr ready` / `merge --auto` | denies when a referenced tracker is **missing** sweeper enrollment |
| **this hook** | plain `gh pr merge` | denies when a referenced issue **has** the `follow-through` label |

The last two read the same label with **inverse** intent and can both fire on
one `--auto` merge, so each deny names itself and its own override. No single
surface is authoritative for every bypass — `/ship` Phase 6 is the earliest and
broadest for the agent-driven path, but only an `on: issues.closed` reversal
layer covers the merges no PreToolUse hook sees (web UI, admin, CI-queued).

- **Fail-open** for the decision, **reported** for diagnosis. A failed
  `gh pr view`, an unresolvable scanner, a failed label lookup, or issues beyond
  the fan-out bound each emit a `systemMessage` (the operator-visible channel on
  an exit-0 hook — plain stderr is discarded there) plus a `rule-incidents.jsonl`
  row for the CI aggregator. The no-PR-found case is deliberately silent so
  pre-PR merge attempts do not cry wolf.
- **Best-effort, not a boundary.** Bypassed by merging from `main`, the web UI,
  an admin merge, a CI-queued `--auto` merge (title, body and labels can all
  change in the queue window — and `--auto` is the workflow's *mandated* merge
  form, so this is the common case), the OpenHands harness, and the
  `OWNER/REPO#N` / full-issue-URL reference forms the canonical scanner does not
  recognise. `main` **does** carry server-side rulesets with required status
  checks, so a durable backstop can be added there; none covers this class today.
  `follow-through-closure-guard.yml` (`on: issues.closed`) is *structurally* the
  right reversal layer but is currently scoped by its `if:` to the callback-URL
  class, so it does **not** yet back up this gate — widening it is tracked in
  #6791.
- **Why:** #6775 — the PR-body arm was dead code for 17 days. The hook built its
  own repo slug with a `sed` that leaves `.git` on SSH remotes, `gh` errored, and
  `|| true` swallowed it. Its test's `gh` stub ignored `argv`, so the body-path
  case passed against a path that never ran. `stub-argv-fidelity.test.sh` now
  makes that stub class un-shippable.

## Escape-hatch inventory

Every **denial override** for the merge/ship gates in this directory. Each
disarms exactly one check — none is a global bypass, and reaching for a broad one
to silence a narrow false positive is how a guard goes quietly dark.

| Env | Hook | Disarms |
|---|---|---|
| `SOLEUR_ACK_AUTOCLOSE=1` | `pre-merge-auto-close-scan.sh` | **Both** checks — it is read above corpus construction. Use only when the broad prose deny is a genuine false positive. |
| `SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1` | `pre-merge-auto-close-scan.sh` | The `follow-through` label gate only; the prose-embedded arm stays armed. The correct hatch when a PR genuinely resolves a tracker. |
| `SOLEUR_SKIP_SOAK_FOLLOWTHROUGH_GATE=1` | `ship-soak-followthrough-gate.sh` | The soak-enrollment deny on `gh pr ready` / `gh pr merge --auto`. |
| `SOLEUR_SKIP_OPERATOR_STEP_GATE=1` | `ship-operator-step-gate.sh` | The undeferred-operator-step deny. Reserved for the rare attestation case (`wg-block-pr-ready-on-undeferred-operator-steps`). |
| `SOLEUR_SKIP_RUNBOOK_SSH_GATE=1` | `ship-runbook-ssh-gate.sh` | The `hr-no-ssh-fallback-in-runbooks` deny on runbook edits. |
| `CLAUDE_HOOK_BYPASS=1` (+ `_REASON`) | `prod-write-defer-gate.sh` | The prod-write defer. Requires a reason and is audit-logged — see the F2 section above. |

Not denial overrides, documented elsewhere in this file: `SOLEUR_DEFER_DRYRUN`
(F2 mode switch), `SOLEUR_DISABLE_AGENT_TOKEN_TEE`, `SOLEUR_DISABLE_SKILL_LOGGER`,
`SOLEUR_DISABLE_CONTEXT_QUERIES`, `SOLEUR_DISABLE_PHASE_HINT` (telemetry
kill-switches), `SOLEUR_DISABLE_MEMORY_BACKSTOP` (memory backstop — see below), `SOLEUR_DEFER_TARGETS_OVERRIDE` (F2 manifest override).



## Memory backstop (ADR-159, #7166)

`memory-backstop.sh` is a **SessionStart** hook (matchers
`startup|resume|clear|compact`). It asks the operator's own systemd manager to
put this agent session's whole process tree into
`soleur-agent-<pid>.scope`, capped at `MemoryHigh=6 GiB` / `MemoryMax=7 GiB` /
`MemorySwapMax=0`, underneath a shared `soleur-agents.slice` capped at
`16 GiB` / `20 GiB` / swap `0`. It exists because on 2026-08-01 a single runaway
search reached 9.5 GB RSS, exhausted memory and swap, and took down six
concurrent agent sessions at once.

It **never blocks a session**: `exit 0` on every path, and every non-applied run
is logged with a machine-readable `reason` (`disabled`, `no_busctl`, `no_bus`,
`claude_pid_not_found`, `no_terminal_scope`, `cap_out_of_range`,
`concurrent_apply`, `adoption_unverified`). On a machine with no per-user systemd
bus (CI, Docker, macOS) it does nothing at all.

### If a session gets stopped

Remedies are listed **narrowest first** — the last one is fleet-wide and the
difference matters:

| Goal | Command |
|---|---|
| Stop just this one session | `systemctl --user stop soleur-agent-<pid>.scope` |
| Raise this one session's limits | `systemctl --user set-property --runtime soleur-agent-<pid>.scope MemoryHigh=infinity MemoryMax=infinity` |
| Change the limits for good | edit the four `readonly` values at the top of `memory-backstop.sh` |
| Stop **every** agent session on this machine | `systemctl --user stop soleur.slice` — **this kills them all**, including sessions with uncommitted work |

`--runtime` on the raise path is **mandatory**: without it, `set-property` writes
a permanent drop-in into `~/.config/systemd/user.control/`, which is exactly the
persistent mutation of the operator's own systemd configuration this hook is
designed never to make.

### Turning it off

`SOLEUR_DISABLE_MEMORY_BACKSTOP=1` disables it entirely. **If you set this you
are unprotected and nothing will tell you** — there is no periodic reminder, and
the only trace is `"reason":"disabled"` in `.claude/.memory-backstop.jsonl`.
