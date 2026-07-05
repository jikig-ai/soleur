---
title: "feat(wave2): fail-closed delete guards + freeze edit-lock (guardrails.sh)"
date: 2026-07-05
issue: 5988
epic: 5983
branch: feat-one-shot-5988-delete-guards-freeze-lock
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: feature
status: plan
---

# 🛡️ feat(wave2): fail-closed delete guards + freeze edit-lock (guardrails.sh)

## Overview

Wave 2 · FR5 of the gstack-capability-adoption epic (#5983). Two hardening
capabilities land in **one PR**, both on the PreToolUse hook surface
`.claude/hooks/guardrails.sh` (brainstorm D6 — bundled to avoid two conflicting
rewrites of the same file):

- **(a) Fail-closed recursive-delete ownership proof** (gstack `staging-guard`,
  T2-8). Hardens the existing `guardrails:block-rm-rf-worktrees` gate — today a
  literal-`.worktrees/` substring grep — into a **realpath-resolved, `.git`-tripwire,
  structural-name + minted-marker** ownership proof, so a symlink- or relative-path-
  obfuscated `rm -rf` that resolves onto the repo root, a worktree root, `$HOME`,
  `/`, or any `.git`-bearing checkout is DENIED, while genuinely disposable
  tool-created staging dirs remain deletable.

- **(b) `freeze` directory-scoped edit-lock** (gstack `freeze`, T3-11). When a
  freeze is active, any `Write`/`Edit` whose `file_path` resolves OUTSIDE the
  allowed path prefix is DENIED at PreToolUse. guardrails.sh becomes a
  multi-tool hook (Bash **and** Write|Edit), mirroring the established
  `worktree-write-guard.sh` Write|Edit-guard precedent.

**TR3 (hard):** the `freeze`-deny MUST NOT shadow the existing Bash sentinel
checks in guardrails.sh; a regression test proves the delete guards (and the
other five sentinels) still fire after the freeze branch is added.

This is dev-harness safety tooling. There is no product code, no schema, no
migration, no UI, no new infrastructure, and no external data egress. The
brand-survival threshold is `single-user incident` because a regression in this
shared hook surface can, for one operator mid-session, either **disarm a delete
guardrail** (irrecoverable branch/worktree loss) or **fail-closed every edit**
(brick the session).

## Research Reconciliation — Spec/Issue vs. Codebase

| Issue/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "Recursive-delete ownership proof: **realpath** + …" | constitution.md:209 hook-enforces `block-rm-rf-worktrees` via a **literal `.worktrees/` grep** (no realpath). Separately, constitution.md:306 says a bulk-cleanup **executor** must **never `realpath`/follow symlinks before deleting** (a symlink into an allowed root would be followed and the real target destroyed — CWE-59; see `2026-03-20-symlink-escape-cwe59-workspace-sandbox.md`, `2026-04-07-symlink-escape-recursive-directory-traversal.md`). | **No contradiction, but must be stated precisely.** The guardrails realpath is used to make a **DENY decision** (resolve the target and refuse if it lands on a protected location) — the *safe* direction: resolving symlinks makes the guard STRONGER (catches obfuscated `rm -rf ./link` → repo root). constitution.md:306 forbids realpath in the *delete executor* (resolving before removal weakens it). Plan §Phase 2 + Sharp Edges call this out so a reviewer does not read them as the same anti-pattern. |
| "…+ **minted marker** (gstack `staging-guard`)" | Learning `2026-06-15-runtime-guardrail-observable-signal-not-cooperative-marker.md`: a guardrail must key on an **observed side-effect, never a cooperative signal the actor can emit on demand**. A marker the agent can `touch` in any dir and then `rm -rf` is a forgeable bypass. | The minted marker is **one AND-clause in a conjunction dominated by observable structural checks**, never independently sufficient. A delete is ALLOWED past the tripwire only if ALL hold: realpath under a known staging root ∧ structural-name match ∧ no-`.git` ∧ marker present. The marker alone (in the repo root) never unlocks a protected target. |
| "guardrails.sh" is the hook surface | guardrails.sh is registered **only** on `matcher: "Bash"` (`.claude/settings.json:33`) and extracts `.tool_input.command` only. | Add a **second registration** on `matcher: "Write|Edit"` and branch on presence of `file_path`. Precedent: `worktree-write-guard.sh` is a registered Write|Edit fail-closed guard. |
| (implicit) single hook file | guardrails.sh is **mirrored** to `.openhands/hooks/guardrails.sh` (OpenHands protocol: `exit 2` + `{"decision":"deny","reason":…}`), and `worktree-write-guard.sh` is mirrored to `.openhands/hooks/worktree-write-guard.sh`. `.openhands/hooks.json` registers `terminal` + `file_editor`. There is **no automated parity test** (grep found none) — parity is by-convention. | **Sweep obligation.** The delete-guard hardening MUST be mirrored to `.openhands/hooks/guardrails.sh` (safety-critical; an OpenHands session must be equally protected). The freeze edit-lock is mirrored via `.openhands/hooks.json` `file_editor` matcher. See §Files to Edit. |
| #5988 open, epic #5983 | `gh issue view 5988` → OPEN, milestone "Post-MVP / Later". Epic ref valid. | Premise holds — build, not fix. |

**Premise Validation:** Cited artifacts verified against the worktree HEAD.
`#5988` is OPEN (build). `guardrails.sh` exists and is Bash-only. The
brainstorm exists and is `brainstorm-complete`. ADR corpus grepped for
`staging-guard`/`freeze`/delete-guard mechanism — no existing ADR decides or
rejects this mechanism (nearest is the worktree-write-guard pattern, which this
extends, not reverses). No external premises were stale.

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) a **disarmed delete
guard** — a `rm -rf` that should have been blocked proceeds and destroys a
worktree/branch or the repo root irrecoverably; or (b) a **bricked session** —
the freeze branch or a malformed freeze-state read denies *every* `Write`/`Edit`,
halting all work mid-session for one operator.

**If this leaks, the user's data/workflow is exposed via:** N/A for data leakage
(no data surface). The workflow-integrity exposure vector is the shared hook
surface itself: a regression silently disarms a guardrail (fail-open) or
fail-closes all edits (fail-shut) for the single operator whose session loads it.

**Brand-survival threshold:** single-user incident.

Per the threshold, `requires_cpo_signoff: true` is set in frontmatter and
`user-impact-reviewer` runs at review-time (review/SKILL.md conditional-agent
block). CPO framing was carried forward from the brainstorm `## User-Brand
Impact` section (threshold + artifact/vector declared there for the
T2-6/T2-8/T3-11 shared-surface class).

## Domain Review

**Domains relevant:** Engineering (carried forward from brainstorm `## Domain
Assessments`). Legal assessed at brainstorm but its concern (redaction/egress,
T2-7) does not touch this delete-guard/edit-lock slice — no regulated-data
surface, no egress. Product/Marketing/Ops/Sales/Finance/Support: none (internal
plugin tooling, no user-data product surface).

### Engineering (CTO) — carried forward from brainstorm

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** CTO flagged three top risks for this bundle; risk (3) is exactly
TR3: "T2-8/T3-11 both edit the shared PreToolUse `guardrails.sh` — freeze-deny
can shadow existing sentinel checks." Build order places this bundle after T2-6
(context-injection) and before T2-7 (redaction). The freeze loader must **fail
open on a malformed/absent state read** (OQ2 blast-radius principle: a parse bug
must not fail-closed all skills) while the enforcement decision within an active,
well-formed freeze is fail-closed.

### Product/UX Gate

**Not triggered.** Mechanical UI-surface override scanned Files to Create/Edit
(`.sh`, `.json`, `.md`, `.gitignore`) — no `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`, or UI-surface term match. Product = NONE.

## Observability

```yaml
liveness_signal:
  what: "Each delete-guard deny and freeze-deny appends one JSONL incident line
         (rule_id, event_type:deny) to <repo-root>/.claude/.rule-incidents.jsonl
         via emit_incident (lib/incidents.sh)."
  cadence: "Per deny event (fire-and-forget)."
  alert_target: "scripts/rule-metrics-aggregate.sh (rule-utility scoring, weekly);
                 operator-legible via the rule-metrics report."
  configured_in: ".claude/hooks/guardrails.sh (emit_incident calls) +
                  scripts/rule-metrics-aggregate.sh"
error_reporting:
  destination: ".claude/.rule-incidents.jsonl (deny/bypass telemetry). Hook
                internal jq/flock/rotation failures emit in-band drop sentinels
                (lib/incidents.sh _emit_drop_sentinel)."
  fail_loud: "Deny decisions are emitted to Claude Code stdout (permissionDecision).
              Telemetry write is fail-soft by design (never blocks the hook)."
failure_modes:
  - mode: "New guardrails-* rule_id trips the aggregator orphan-gate"
    detection: "scripts/rule-metrics-aggregate.test.sh (run in test-all.sh)"
    alert_route: "CI red on the test suite"
  - mode: "Freeze state file malformed/unreadable"
    detection: "guardrails.test.sh fixture: malformed freeze file → edit ALLOWED
                (fail-open), asserted green"
    alert_route: "CI red if fail-open regresses to fail-closed"
  - mode: "Delete guard disarmed (rm -rf on protected target allowed)"
    detection: "guardrails.test.sh regression fixtures (worktree path, repo root,
                symlink-to-root, .git-bearing dir) assert deny"
    alert_route: "CI red"
logs:
  where: "<repo-root>/.claude/.rule-incidents.jsonl (gitignored; rotated by
          log-rotation.sh)"
  retention: "Rotated by size; aggregated weekly."
discoverability_test:
  command: "printf '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf ./.worktrees/foo\"}}' | bash .claude/hooks/guardrails.sh | jq -r .hookSpecificOutput.permissionDecision"
  expected_output: "deny"
```

## Architecture Decision (ADR/C4)

**No ADR required; no C4 edit required.** Reasoning, with the completeness
mandate satisfied:

- **ADR:** This is a routine extension of the established "PreToolUse Guards"
  pattern — hardening an existing guard's predicate and adding a second
  Write|Edit guard that mirrors the existing `worktree-write-guard.sh`
  fail-closed edit-guard. It introduces **no new substrate, no ownership/tenancy
  boundary move, no resolver/dispatch trust-boundary reversal, and reverses no
  existing ADR** (grep of the decisions corpus for `staging-guard`/`freeze`/
  delete-guard mechanism found none deciding or rejecting it). The freeze
  edit-lock is a new cross-cutting invariant, but it is the *same class* as the
  already-shipped worktree-write-guard invariant — precedent, not novelty.
- **C4 views:** Read all three `.c4` files
  (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`).
  The CLI shell Hook Engine is already modeled as `platform.engine.hooks`
  (`model.c4:60-61`, container "Hook Engine", technology "PreToolUse Guards")
  and rendered in `views.c4:30,57`. Enumeration for this change:
  **(a) external human actors** — none new (the operator already interacts with
  the engine; no new correspondent/reviewer/recipient). **(b) external
  systems/vendors** — none (no webhook, no outbound API, no third-party store).
  **(c) containers/data-stores** — none new (freeze state is a runtime file
  *inside* the existing Hook Engine, not a modeled data store; `.rule-incidents.jsonl`
  is likewise unmodeled runtime state). **(d) access relationships** — unchanged.
  Therefore **no C4 impact**: the change lives entirely inside an
  already-modeled container and adds no element, edge, or `view include`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-5988-delete-guards-freeze-lock/tasks.md`
  — task breakdown (created by the Save-Tasks step).
- `.claude/hooks/lib/freeze-lock.sh` — freeze-state control + reader helper.
  Subcommands `set <path> | status | clear` write/read the single-line
  freeze-state file; a `freeze_active_prefix` reader function is sourced by
  guardrails.sh. Agent-native: Bash-invocable, so an agent can freeze/clear
  exactly as an operator can.
- `.claude/hooks/lib/freeze-lock.test.sh` — unit tests for the control helper
  (set/status/clear round-trip; malformed-file fail-open; absent-file inactive).

## Files to Edit

- `.claude/hooks/guardrails.sh` — (1) harden `block-rm-rf-worktrees` into the
  realpath + `.git`-tripwire + structural-name + minted-marker ownership proof;
  (2) add the freeze edit-lock branch (guarded on `file_path` presence, placed so
  it never short-circuits the Bash sentinels). Update the prose-rule comment block
  at the top (per the hook's own "update the corresponding prose rule comments"
  contract). New rule_ids: `guardrails-block-recursive-delete`,
  `guardrails-freeze-edit-lock`.
- `.openhands/hooks/guardrails.sh` — mirror the delete-guard hardening in the
  **OpenHands protocol** (`exit 2` + `{"decision":"deny","reason":…}`, no
  `emit_incident`). This is the safety-critical mirror.
- `.openhands/hooks.json` — add `.openhands/hooks/guardrails.sh` (or a mirrored
  freeze handler) to the `file_editor` matcher so freeze enforces under OpenHands
  too. **Verify at /work**: if the OpenHands `file_editor` payload shape differs
  from Claude's `file_path`, adapt; if freeze-under-OpenHands is non-trivial,
  scope the freeze mirror to a tracking issue (delete-guard mirror stays in-PR).
- `.claude/settings.json` — add a `"matcher": "Write|Edit"` registration block
  for `guardrails.sh` (alongside the existing `"matcher": "Bash"` block).
- `.claude/hooks/guardrails.test.sh` — extend with: (i) delete-guard regression
  fixtures proving all six existing sentinels + the hardened delete guard still
  fire (TR3); (ii) new delete-guard fixtures (repo root, worktree root,
  symlink-to-root, `.git`-bearing dir → deny; marked staging dir → allow);
  (iii) freeze fixtures (Edit inside allowed path → allow; Edit outside → deny;
  malformed/absent freeze file → allow/fail-open; freeze active but tool is Bash
  rm-rf → delete guard still denies).
- `.gitignore` — add `.claude/.freeze*` (freeze state is runtime, per the
  `.claude/.rule-incidents*` precedent at line 37).
- `knowledge-base/project/constitution.md` — add a one-line prose rule for the
  hardened delete guard and the freeze edit-lock (mirrors the existing
  `[hook-enforced: guardrails.sh …]` convention at lines 193, 209), keeping the
  hook's prose-rule/comment contract consistent.

**Open Code-Review Overlap:** None. (`gh issue list --label code-review --state
open` cross-referenced against the file list above — no open scope-out names
`guardrails.sh`, `.openhands/hooks/guardrails.sh`, `settings.json`, or the freeze
helper. Re-run at /work to confirm against live state.)

## Implementation Phases

### Phase 0 — Preconditions (grep/verify before editing)

1. `bash .claude/hooks/guardrails.test.sh` — confirm the current suite is green
   (baseline for the TR3 regression).
2. `bash .claude/hooks/hookeventname-coverage.test.sh` — confirm the hookEventName
   contract passes (the freeze deny JSON MUST carry `hookEventName: "PreToolUse"`;
   this meta-test enforces it per-file).
3. Confirm the aggregator orphan-gate accepts `guardrails-*` rule_ids:
   `git grep -n 'guardrails-' scripts/rule-metrics-aggregate.sh scripts/rule-metrics-aggregate.test.sh`
   (existing `guardrails-block-rm-rf-worktrees` already passes; the two new
   `guardrails-*` ids follow the same convention — verify, don't assume). See
   `2026-04-24-rule-metrics-emit-incident-coverage-session-gotchas.md`.
4. Confirm `.openhands` deny protocol by reading `.openhands/hooks/guardrails.sh`
   (`exit 2` + `{"decision":"deny","reason":…}`) and `.openhands/hooks.json`
   matchers (`terminal`, `file_editor`).

### Phase 1 — Freeze-lock control helper (TDD: RED first)

Write `.claude/hooks/lib/freeze-lock.test.sh` failing, then
`.claude/hooks/lib/freeze-lock.sh`:
- State file: `<repo-root>/.claude/.freeze-lock`, single line = absolute allowed
  path prefix (resolved via the incidents-style `cd -P && pwd -P` root
  resolution so it is worktree-local).
- `set <path>` writes the resolved absolute prefix; `status` prints active
  prefix or `inactive`; `clear` removes the file.
- Reader `freeze_active_prefix`: echoes the prefix ONLY if the file exists and
  contains a single well-formed absolute path; **absent/empty/malformed →
  echo nothing (fail-open, no active freeze)**. This is the OQ2 blast-radius
  guarantee — a corrupt state file must NOT brick all edits.

### Phase 2 — Hardened recursive-delete ownership proof (Bash gate)

Edit `.claude/hooks/guardrails.sh`, replacing the literal-`.worktrees/` grep with
the ownership proof. Parse the `rm` target(s) from `$COMMAND` when the command is
a recursive-force `rm` (`-rf`/`-fr`/`-r … -f` variants). For each target:
1. **Resolve** `realpath -m` on the target (and, when a trailing `/` is present on
   a symlink target, resolve the *contents* target). This realpath is for the
   DENY decision only — NOT a delete-executor (contrast constitution.md:306).
2. **`.git` tripwire / structural protection:** DENY if the resolved path IS or
   CONTAINS-at-root a `.git` entry, OR equals the repo root, any `git worktree
   list` root, `$HOME`, or `/`. Fail-closed: if realpath cannot resolve the
   target AND the raw target matches a protected shape, DENY.
3. **Ownership-proof ALLOW path (staging):** permit the delete only if ALL of —
   resolved path under a known staging root ∧ structural-name match (staging/
   scratch pattern) ∧ no `.git` ∧ minted marker file present. The marker is
   NEVER independently sufficient (anti-forgery per the cooperative-marker
   learning).
4. `emit_incident "guardrails-block-recursive-delete" "deny" …` then the
   `hookSpecificOutput` deny JSON with `hookEventName: "PreToolUse"`.

Keep the existing narrow `.worktrees/` behavior as a subset (regression-covered).

### Phase 3 — Freeze edit-lock branch (Write|Edit gate)

In `.claude/hooks/guardrails.sh`, add — near the top, AFTER the `COMMAND`/
`TOOL_NAME`/`FILE_PATH` extraction and BEFORE the Bash sentinels — a branch:

```
# Freeze edit-lock — only for file-editing tools. Placed so it NEVER
# short-circuits the Bash sentinels below (TR3): a Bash rm-rf carries no
# file_path, so this branch is skipped entirely for Bash calls.
if [[ -n "$FILE_PATH" ]]; then
  ALLOWED=$(freeze_active_prefix)          # empty => no active freeze (fail-open)
  if [[ -n "$ALLOWED" ]]; then
    RESOLVED=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    case "$RESOLVED" in
      "$ALLOWED"|"$ALLOWED"/*) : ;;        # inside allowed prefix => allow
      *) emit_incident "guardrails-freeze-edit-lock" "deny" … ; <deny JSON w/ hookEventName> ; exit 0 ;;
    esac
  fi
  exit 0                                    # Edit/Write: Bash gates do not apply
fi
# ... existing Bash sentinels unchanged below ...
```

Add `FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')` to the
extraction block. Source `freeze-lock.sh` alongside `incidents.sh`.

### Phase 4 — Registration + mirrors + gitignore

- `.claude/settings.json`: add the `Write|Edit` registration block for
  guardrails.sh.
- `.openhands/hooks/guardrails.sh`: mirror the delete-guard hardening (OpenHands
  protocol). Evaluate freeze-under-OpenHands feasibility; wire `file_editor` in
  `.openhands/hooks.json` if the payload shape supports it, else file a tracking
  issue for the freeze mirror (delete-guard mirror is non-negotiable in-PR).
- `.gitignore`: add `.claude/.freeze*`.

### Phase 5 — Tests (TR3 regression is load-bearing)

Extend `.claude/hooks/guardrails.test.sh` (add an Edit/Write payload builder
alongside `mk_payload`). Cover the fixtures listed in §Files to Edit. The TR3
regression is the pivotal one: with the freeze branch present (and even with a
freeze ACTIVE), a Bash `rm -rf ./.worktrees/foo` payload still returns `deny`,
and each of the six pre-existing sentinels still fires.

### Phase 6 — Prose + docs

Update the guardrails.sh top-comment prose-rule block and add the two
constitution.md prose rules. Run `bash scripts/test-all.sh` (or the scoped hook
suites) to confirm green.

## Acceptance Criteria

### Pre-merge (PR)

1. `bash .claude/hooks/guardrails.test.sh` exits 0 with new fixtures present.
2. **TR3 regression:** a Bash `rm -rf ./.worktrees/foo` fixture returns
   `permissionDecision == "deny"` **with a freeze active**, and all six existing
   sentinels (commit-on-main, rm-rf-worktrees, delete-branch, conflict-markers,
   require-milestone, stash) still return their expected decisions. Assert via
   the test suite, not prose.
3. Hardened delete guard: fixtures for repo root, a `git worktree` root, a
   symlink resolving onto the repo root, and a `.git`-bearing dir each return
   `deny`; a marked staging dir returns `<none>` (allow).
4. Freeze: Edit inside allowed prefix → `<none>`; Edit outside → `deny`;
   **malformed/absent freeze file → `<none>` (fail-open)**.
5. `bash .claude/hooks/hookeventname-coverage.test.sh` exits 0 (freeze +
   delete deny JSON both carry `hookEventName: "PreToolUse"`).
6. `bash .claude/hooks/lib/freeze-lock.test.sh` exits 0.
7. `.openhands/hooks/guardrails.sh` contains the mirrored delete-guard hardening
   (OpenHands `exit 2` protocol); `diff`-audit confirms the deny reasons match.
8. `scripts/rule-metrics-aggregate.test.sh` green — the two new `guardrails-*`
   rule_ids do not trip the orphan-gate.
9. `.gitignore` ignores `.claude/.freeze*`; `git status` shows no freeze state
   file staged.
10. `bash scripts/test-all.sh` green (full suite; hook `.test.sh` files are
    discovered at scripts/test-all.sh:189).

### Post-merge (operator)

None. This is a code-only hook change on an already-provisioned surface; no
migration, no infra apply, no vendor step.

## Test Scenarios

- Delete guard, obfuscated target: `rm -rf $HOME/../<user>/git-repositories/…/soleur`
  (relative path resolving to repo root) → deny.
- Delete guard, symlink: `ln -s <repo-root> /tmp/x && rm -rf /tmp/x/` → deny
  (realpath resolves to protected root).
- Delete guard, legitimate scratch: `rm -rf <staging-root>/scratch-abc123`
  (structural name + minted marker, no `.git`) → allow.
- Freeze active on `apps/web-platform/`: Edit `apps/web-platform/src/foo.ts` →
  allow; Edit `plugins/soleur/SKILL.md` → deny.
- Freeze active, Bash `rm -rf ./.worktrees/foo` → deny (delete guard, not freeze).
- Freeze state file corrupted (two lines / non-path) → any Edit allowed.

## Sharp Edges

- **realpath direction is opposite for guard vs. executor.** guardrails.sh
  realpath-resolves to DECIDE-DENY (safe — resolving symlinks strengthens the
  block). constitution.md:306 forbids realpath in a delete-EXECUTOR (resolving
  before removal weakens it, CWE-59). Do not "fix" the guard to match :306 — they
  are different code paths; a reviewer conflating them will file a wrong finding.
- **The minted marker must never be independently sufficient.** Per
  `2026-06-15-runtime-guardrail-observable-signal-not-cooperative-marker.md`, an
  agent can `touch` a marker; the allow-path is a conjunction gated by observable
  structural checks (realpath-under-staging-root ∧ no-`.git`). A marker in the
  repo root never unlocks a protected target.
- **Freeze fails OPEN on state-read, CLOSED on enforcement.** Absent/empty/
  malformed freeze file ⇒ no active freeze ⇒ allow (OQ2: a parse bug must not
  brick every edit). Only a VALID active freeze denies out-of-scope edits. An AC
  asserts the fail-open path.
- **TR3 placement.** The freeze branch keys on `file_path` presence and lives
  ABOVE the Bash sentinels; a Bash `rm -rf` (no file_path) skips it. Do NOT place
  a bare `exit 0` on any path a Bash command can reach, or the delete guard is
  shadowed. The regression test with a freeze ACTIVE is the proof.
- **hookEventName is mandatory on every deny.** Both new deny blocks MUST emit
  `hookEventName: "PreToolUse"` or Claude Code silently ignores the decision
  (the exact non-enforcement bug `hookeventname-coverage.test.sh` guards).
- **`.openhands` uses a DIFFERENT deny protocol** (`exit 2` +
  `{"decision":"deny","reason":…}`, no `emit_incident`) — do not copy the Claude
  JSON verbatim into the mirror.
- **A plan whose `## User-Brand Impact` section is empty or placeholder will fail
  deepen-plan Phase 4.6.** It is filled above.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Freeze as a **separate** hook file (not in guardrails.sh) | Issue + TR3 explicitly name guardrails.sh; brainstorm D6 bundles the two into one guardrails.sh rewrite to avoid conflicts. |
| Blanket **deny all `rm -rf`** (global fail-closed) | Would deny `rm -rf node_modules`/`dist`/`/tmp/*` — unusable for a solo operator. Fail-closed is scoped to the *protected-target class*, not global. |
| Freeze state via **env var** | Env vars do not propagate reliably into subsequent PreToolUse hook invocations; a state file (worktree-local, gitignored) is required, mirroring `.rule-incidents.jsonl`. |
| **New ADR** for the freeze invariant | Same class as the shipped worktree-write-guard; no substrate/ownership/trust-boundary reversal (see §Architecture Decision). |
