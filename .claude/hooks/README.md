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

### PostToolUse hooks (no deny semantics)

PostToolUse runs after the tool's write, so these cannot block. Most are telemetry-only; `pencil-collapse-guard.sh` additionally performs a file restore and injects `additionalContext` into the model.

| Hook | Sink | Purpose |
|---|---|---|
| `skill-invocation-logger.sh` | `.claude/.skill-invocations.jsonl` | Records every Skill tool call (session_id + skill name) for the monthly skill-freshness aggregator. |
| `agent-token-tee.sh` | `.claude/.session-tokens.jsonl` | Records every Task/Agent invocation envelope (session_id + subagent_type + total_tokens + duration) for compound Phase 1.6 token-efficiency analysis. Kill-switch: `SOLEUR_DISABLE_AGENT_TOKEN_TEE=1`. Issue #3494. |
| `pencil-collapse-guard.sh` | `.claude/.rule-incidents.jsonl` (`cq-pencil-collapse-auto-recover`, `warn`) | PostToolUse on `mcp__pencil__open_document`: auto-restores a tracked `.pen` collapsed to empty document state from `git HEAD` + emits an `additionalContext` warning. Fail-open, non-destructive. Issue #4859. |

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

Inverse of `ship-soak-followthrough-gate.sh` above: that one denies when a
tracker is *missing* enrollment, this one when an issue *has* the label. Both can
fire on a single `--auto` merge, so each deny names itself and its own override.

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
kill-switches), `SOLEUR_DEFER_TARGETS_OVERRIDE` (F2 manifest override).

