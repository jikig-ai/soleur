---
title: "fix: operator-stage gate: OpenCode is not recognised as an agent harness, and SKILL.md states the receipt path unqualified"
type: fix
date: 2026-10-23
slug: fix-opencode-operator-stage-gate
branch: feat-one-shot-10877-opencode-operator-stage-gate
issue: 10877
closes: 10877
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: operator-stage gate: OpenCode is not recognised as an agent harness, and SKILL.md states the receipt path unqualified

## Enhancement Summary

**Deepened on:** 2026-10-23
**Sections enhanced:** 6 (`Overview`, `Research Reconciliation`, `Implementation Phases`, `Observability`, `Guard Contract`, `Acceptance Criteria`)
**Research agents used:** `repo-research-analyst`, `learnings-researcher`, `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `security-sentinel`, `test-design-reviewer`, `observability-coverage-reviewer`, `user-impact-reviewer`, `cto`, `cpo` (executed inline at depth 1 on OpenCode; `Reviewed-Coverage: sequential-fallback`).

### Key Improvements

1. **Cross-suite ambient `OPENCODE=1` audit (`operator-script.test.sh` vs `operator-ack-guard.test.sh`):** Verified that `operator-ack-guard.test.sh` runs under `env -i` with an explicit `envv` allowlist (`g2_hostile_env` scans `_?SOLEUR_*` and `*_ACK*` only, never `OPENCODE`), so it is unaffected by ambient `OPENCODE=1`, whereas `operator-script.test.sh`'s `pty_drive` and `g11_pty` inherit the process environment and require `-u OPENCODE` alongside `-u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT`.
2. **Guard 4 (`g4_class2_body_ok`) & Guard 5' (`g5_check`) compatibility verification:** Confirmed that `g4_class2_body_ok` scans `soleur_op_ack_or_die`'s own function body (not `soleur_op_in_agent_harness`), and `g5_check` rejects `_(TOKEN|KEY|SECRET|PASSWORD|PAT)` and `${!`, which `OPENCODE` does not match; also verified `fixture-relative-assert.test.sh` is line-count-invariant for this edit.
3. **Observability Layer 7 (`cli-stdout-artifact`) and Guard Contract tightening:** Added explicit `cli-stdout-artifact` layer citations in `failure_modes` and a non-comment `discoverability_test` probe (`grep -c 'OPENCODE:-' plugins/soleur/scripts/lib/operator-script.sh` expecting `"1"`), plus a dual-guard mutation row (`m14b` driving both `g11_check` and `gagent_check` RED, raising `FLOOR` from `208` to `211`).

### New Considerations Discovered

- In `operator-script.test.sh`, `pty_drive_agent` currently hardcodes `env CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli`. Adding a second check in `gagent_check` that passes `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT OPENCODE=1` tests the legacy class-2 ack (`soleur_op_ack_or_die`) under OpenCode's exact environment, and asserting `assert_red gagent_check` on mutant `m14b` proves both `soleur_op_ack_or_die` and `soleur_op_stage_gate` fail closed on `OPENCODE=1`.

## Overview

Close issue #10877 across two surfaces left open after #10819–#10822:

1. **Agent-harness detection in `plugins/soleur/scripts/lib/operator-script.sh`:** `soleur_op_in_agent_harness()` currently checks only `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT`. OpenCode sets `OPENCODE=1` in every spawned `shell` child and sets neither Claude Code marker. While OpenCode's `shell` tool does not allocate a PTY by default (`[[ -t 0 ]]` and `[[ -t 1 ]]` are false), any child command that wraps a staged operator script in a PTY allocator (`script -qec`, `python3 -c 'import pty...'`, `expect`) satisfies `-t 0 && -t 1` inside the child process, opening the `tty-ack` fallback in both `soleur_op_stage_gate` (v2 staged scripts) and `soleur_op_ack_or_die` (legacy class-2 ack) without any deliberate `env -u` step. Widening `soleur_op_in_agent_harness()` to also test `-n "${OPENCODE:-}"` closes this gap and brings the shell helper into parity with `plugins/soleur/lib/harness.ts` (`detectHarness`) and `plugins/soleur/scripts/emit-decision.sh`.
2. **Harness-qualified receipt documentation in `plugins/soleur/skills/operator-bootstrap/SKILL.md` and `plugins/soleur/scripts/sync-opencode-adapter.ts`:**
   - `plugins/soleur/skills/operator-bootstrap/SKILL.md` (§"The staged contract in one screen" and §"Running a generated script" → **Surfaces**) describes the PreToolUse receipt hook unqualified at the `The receipt:` bullet and omits OpenCode from the non-hook harness list (`(Codex, Devin cloud, Grok)`). Add the harness qualifier at the receipt bullet and add `OpenCode` to the non-hook harness list.
   - `plugins/soleur/scripts/sync-opencode-adapter.ts` (and its generated `plugins/soleur/opencode/INSTRUCTIONS.md`) currently states that `soleur_op_in_agent_harness` recognises only `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT` and that the `tty-ack` arm is open under OpenCode whenever a spawned shell has a tty. Update the generator and regenerate `plugins/soleur/opencode/INSTRUCTIONS.md` so the matrix reflects that `soleur_op_in_agent_harness` now recognises `OPENCODE` and refuses a PTY `yes` on OpenCode as well.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| `#10877`: "Whether OpenCode's `shell` allocates a pty is **not measured**. That measurement decides how severe this is." | Measured live on `opencode v2.1.2`: direct `shell` tool calls have `fd0_tty=false`, `fd1_tty=false`, `fd2_tty=false` (`isatty() == False` on stdin/stdout/stderr), and environment carries `OPENCODE=1`, `OPENCODE_SESSION_ID=ses_...`, `OPENCODE_TERMINAL=1`, `AI_AGENT=opencode`. However, a child that allocates a PTY (`script -qec`, `python3 pty`) makes `-t 0 && -t 1` true inside the script while `OPENCODE=1` remains set. | Record the live measurement in `## Research Insights`; widen `soleur_op_in_agent_harness()` to test `OPENCODE` so a PTY wrapper inside OpenCode is refused without needing an explicit `env -u OPENCODE`. |
| `#10877`: "`skills/operator-bootstrap/SKILL.md` Line 67 describes the receipt as *the* mechanism for `--apply` with no harness qualification" | Confirmed at the `- The **receipt**:` bullet in `## The staged contract in one screen`. In addition, the `**Surfaces.**` paragraph in `## Running a generated script` lists `Harnesses without the hook (Codex, Devin cloud, Grok)` and omits `OpenCode`. | Qualify `- The **receipt**:` in `## The staged contract in one screen` AND add `OpenCode` to the `Harnesses without the hook` parenthetical in `**Surfaces.**`. |
| `#10877`: "Filed from `2026-10-22-fix-opencode-harness-followups-plan.md` (Phase 2.5/2.6)" | That PR also added a paragraph to `plugins/soleur/scripts/sync-opencode-adapter.ts` (and generated `plugins/soleur/opencode/INSTRUCTIONS.md`) stating `soleur_op_in_agent_harness, which recognises only CLAUDECODE/CLAUDE_CODE_ENTRYPOINT — neither is set under OpenCode — so that arm is open here whenever the spawned shell has a tty`. | Updating `soleur_op_in_agent_harness()` without updating `sync-opencode-adapter.ts` + `opencode/INSTRUCTIONS.md` would leave the generated OpenCode instructions making a newly-false claim about the library. Include both in `## Files to Edit`. |
| Test harness environment isolation in `plugins/soleur/test/operator-script.test.sh` | `pty_drive` and `g11_pty` simulate a human's own terminal via `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT script -qec ...`. When the test suite itself runs inside an OpenCode session (`OPENCODE=1` in the ambient environment), adding `OPENCODE` to `soleur_op_in_agent_harness()` without adding `-u OPENCODE` to `pty_drive` and `g11_pty` causes the human-terminal control rows (`gdecline_check`, `gagent_check` control, `g11_check` N2 control) to fail with exit 64 / 75! | Update `pty_drive` and `g11_pty` in `plugins/soleur/test/operator-script.test.sh` to pass `-u OPENCODE` alongside `-u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT`, and add explicit `OPENCODE=1` agent-harness refusal assertions to both `gagent_check` and `g11_check` (plus a dedicated mutation row). |

## Research Insights

### Premise Validation (Phase 0.6)

- **Issue state:** `gh issue view 10877 --json state,title,closedByPullRequestsReferences` confirmed `#10877` is `OPEN` with zero closing PR references.
- **Cited files and symbols:** `git grep -n "soleur_op_in_agent_harness" -- plugins/soleur/scripts/lib/operator-script.sh` confirmed the definition at `soleur_op_in_agent_harness()` and its two call sites (`soleur_op_ack_or_die` and `soleur_op_stage_gate`). `plugins/soleur/skills/operator-bootstrap/SKILL.md` confirmed the unqualified `- The **receipt**:` bullet and the `(Codex, Devin cloud, Grok)` list in `**Surfaces.**`.
- **ADR corpus check:** Read [ADR-264](../../engineering/architecture/decisions/ADR-264-generated-operator-scripts-are-agent-run-in-stages.md). ADR-264 §Decision and §Threat model and residual explicitly establish that a terminal inside an agent harness is not evidence of a person because an agent can allocate a pseudo-terminal (`script`, `python pty`, `expect`), and that an instruction-following agent must not be able to satisfy `tty-ack` without deliberately unsetting the harness marker. Recognising `OPENCODE` in `soleur_op_in_agent_harness()` directly implements ADR-264's invariant for OpenCode.

### Live Measurement Record (OpenCode `v2.1.2`)

Measured in the OpenCode `shell` tool child process on `opencode v2.1.2`:

- **Direct `shell` tool stdio:** `[[ -t 0 ]]` is false (`fd0_tty=false`), `[[ -t 1 ]]` is false (`fd1_tty=false`), `[[ -t 2 ]]` is false (`fd2_tty=false`); `sys.stdin.isatty() == False`, `sys.stdout.isatty() == False`, `sys.stderr.isatty() == False`.
- **Environment markers injected by OpenCode:** `OPENCODE=1`, `OPENCODE_SESSION_ID=ses_...`, `OPENCODE_TERMINAL=1`, `AI_AGENT=opencode`. Neither `CLAUDECODE` nor `CLAUDE_CODE_ENTRYPOINT` is set.
- **PTY wrapper behavior:** Because `[[ -t 0 && -t 1 ]]` is evaluated inside the child script, any PTY-allocating wrapper invoked by an agent (`script -qec`, `python3 -c 'import pty...'`, `expect`) makes `-t 0` and `-t 1` true inside the script while inheriting `OPENCODE=1`. That is the exact vector `soleur_op_in_agent_harness` exists to block.
- **Surface telemetry (`soleur_op_stage_gate`):** `soleur_op_stage_gate` records `surface="${CLAUDE_CODE_ENTRYPOINT:-${OPENCODE:+opencode}}"` (currently `${CLAUDE_CODE_ENTRYPOINT:-unknown}`, which logs `surface=unknown` on OpenCode). Updating `surface` fallback to `${CLAUDE_CODE_ENTRYPOINT:-${OPENCODE:+opencode}}` (falling back to `unknown` when empty: `surface="${CLAUDE_CODE_ENTRYPOINT:-${OPENCODE:+opencode}}"`, `surface="${surface:-unknown}"`) makes `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED` and the run ledger identify `surface=opencode` instead of `surface=unknown` when run under OpenCode. Let's check whether any existing test pins `surface=unknown` when `OPENCODE` is unset: when `CLAUDE_CODE_ENTRYPOINT` and `OPENCODE` are both unset, `surface` remains `unknown`. Wait — let's check if issue #10877 asks for `surface` or if we should keep `surface` untouched per Mechanism Minimality Gate (Phase 0.6b) and Scope Check (Phase 2.4)!
  - Checking Phase 0.6b & 2.4: `#10877` does NOT ask to change `surface=`; changing `surface` would be an unrequested behavior change and could interact with `g11` if `OPENCODE=1` leaks into `g11_run`. Keeping `soleur_op_stage_gate`'s `surface` line unchanged and scrubbing `OPENCODE` in `g11_pty` / `pty_drive` is strictly minimal and avoids invented scope.

### Property List (Phase 0.6b)

- **P1:** When `OPENCODE` is non-empty in the environment, `soleur_op_in_agent_harness` returns `0` (true), so both `soleur_op_ack_or_die` (exit 64 `SOLEUR_BOOTSTRAP_INPUT_REQUIRED`) and `soleur_op_stage_gate` (exit 75 `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED`) refuse a typed `yes` on a pseudo-terminal inside OpenCode.
- **P2:** `plugins/soleur/test/operator-script.test.sh` passes deterministically both outside an agent harness and when invoked from inside an OpenCode session (`OPENCODE=1` in the ambient environment), and drives RED if the `OPENCODE` check is removed from `soleur_op_in_agent_harness`.
- **P3:** `plugins/soleur/skills/operator-bootstrap/SKILL.md` states at the receipt definition (`## The staged contract in one screen`) and in `**Surfaces.**` (`## Running a generated script`) which harnesses have the PreToolUse receipt hook (Claude Code interactive) and what happens where the hook is absent (OpenCode, Codex, Devin cloud, Grok, and the web app: `--apply` exits 75 `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED` with nothing written).
- **P4:** `plugins/soleur/scripts/sync-opencode-adapter.ts` and the generated `plugins/soleur/opencode/INSTRUCTIONS.md` accurately state that `soleur_op_in_agent_harness` recognises `OPENCODE` (alongside `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT`) so the `tty-ack` fallback is refused on OpenCode even if a child allocates a tty, and `sync-opencode-adapter.ts --check` exits 0.

### Cut List (Phase 0.6b)

- **Checking `AI_AGENT=opencode` or `OPENCODE_TERMINAL` in `soleur_op_in_agent_harness()`** → Cut. `plugins/soleur/lib/harness.ts` (`detectHarness`) documents that `OPENCODE` is injected by OpenCode into every tool child and deliberately avoids `AI_AGENT` as a primary predicate because the name is generic. `[[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" || -n "${OPENCODE:-}" ]]` is sufficient and matches `lib/harness.ts`.
- **Changing `surface=` in `soleur_op_stage_gate`** → Cut. Not requested in `#10877` (would be an `inferred` scope expansion with no ask mapping).
- **Adding a new test file** → Cut. `plugins/soleur/test/operator-script.test.sh` already owns Guard 8 (`gagent_check`) and Guard 11 (`g11_check` row N + mutation rows) and `plugins/soleur/test/opencode-adapter-drift.test.ts` already tests `INSTRUCTIONS.md`. Extending those existing suites keeps test registration and runtime overhead minimal.

### Institutional Learnings

- [`knowledge-base/project/learnings/2026-10-01-an-operator-script-that-needs-a-terminal-cannot-serve-a-user-without-one.md`](../learnings/2026-10-01-an-operator-script-that-needs-a-terminal-cannot-serve-a-user-without-one.md): A second approval source (`tty-ack`) kept for a human at a terminal is reachable by an agent via `script(1)` or Python `pty` unless gated by `! soleur_op_in_agent_harness`. Every mutation row in `operator-script.test.sh` must prove it landed (`md5` against pristine + `bash -n`) and drive the guard RED for the named reason.
- [`knowledge-base/project/learnings/2026-10-20-docs-edits-regressed-a-guarded-prose-gate.md`](../learnings/2026-10-20-docs-edits-regressed-a-guarded-prose-gate.md): `plugins/soleur/opencode/INSTRUCTIONS.md` is owned by `plugins/soleur/scripts/sync-opencode-adapter.ts`; never hand-edit the generated file without updating `instructions()` in the generator and running `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check`. Also grep `plugins/soleur/test/` for any suite asserting on the edited files (`operator-script.test.sh`, `operator-agent-runnable.test.sh`, `operator-ack-guard.test.sh`, `opencode-adapter-drift.test.ts`, `harness-claim-parity.test.ts`, `invocation-axis.test.ts`).

## Technical Considerations

- **Ambient `OPENCODE=1` in test suites:** When `plugins/soleur/test/operator-script.test.sh` runs under OpenCode, `OPENCODE=1` is present in the test runner's environment. `pty_drive` (Guard 8) and `g11_pty` (Guard 11) currently strip only `-u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` when simulating a person's own terminal outside any harness. They must also pass `-u OPENCODE` so the control rows ("a person's own terminal answering yes") genuinely run with no harness variables set.
- **Per-variable mutation coverage in Guard 11:** In `plugins/soleur/scripts/lib/operator-script.sh`, `soleur_op_in_agent_harness()` will check `[[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" || -n "${OPENCODE:-}" ]]`. If Guard 11 only mutated the call site `&& ! soleur_op_in_agent_harness` (`m14`), a regression that dropped `|| -n "${OPENCODE:-}"` inside `soleur_op_in_agent_harness()` would not have its own mutation row. Adding an `OPENCODE=1` PTY refusal check to `gagent_check` (Guard 8) and `g11_check` row N (Guard 11), plus a mutation row `m14b` that strips `|| -n "${OPENCODE:-}"` from `soleur_op_in_agent_harness()`, ensures the new branch is non-vacuously pinned.
- **Anti-vacuity floor in `plugins/soleur/test/operator-script.test.sh`:** `FLOOR=208` is at the bottom of `operator-script.test.sh`. Adding `m14b` (2 assertions via `g11_mutant`: `mutate` landing + `g11_check` RED for the named reason, plus 1 assertion via `assert_red gagent_check` on the same mutant = +3 assertions) increases `ASSERT_TOTAL` from `208` to `211`; raise `FLOOR=211` in lockstep so neither guard's `OPENCODE` assertion can be silently dropped.
- **Guard 4 (`g4_class2_body_ok`), Guard 5' (`g5_check`), and `operator-ack-guard.test.sh` interaction (Deepen-Plan audit):**
  - `g4_class2_body_ok` inspects `soleur_op_ack_or_die`'s own function body (`g3_fn_body "$lib" soleur_op_ack_or_die`), which remains unchanged (`soleur_op_in_agent_harness` is a separate function).
  - `g5_check` rejects `_(TOKEN|KEY|SECRET|PASSWORD|PAT)` and `${!` in `operator-script.sh`; `${OPENCODE:-}` matches neither.
  - `operator-ack-guard.test.sh` drives `g2_run` under `env -i` with an explicit `envv` allowlist (`g2_hostile_env` matches `_?SOLEUR_*` and `*_ACK*` only, never `OPENCODE`), so its positive-control PTY runs are already isolated from ambient `OPENCODE=1`.

## Implementation Phases

### Phase 1: Widen `soleur_op_in_agent_harness()` and pin with Guard 8 + Guard 11 (`operator-script.sh`, `operator-script.test.sh`)

1. **`plugins/soleur/scripts/lib/operator-script.sh`** (around `soleur_op_in_agent_harness`):
   - Update the comment above `soleur_op_in_agent_harness` to note that Claude Code sets `CLAUDECODE` / `CLAUDE_CODE_ENTRYPOINT` and OpenCode sets `OPENCODE` in every tool call's environment.
   - Update `soleur_op_in_agent_harness()`:
     ```bash
     soleur_op_in_agent_harness() {
       [[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" || -n "${OPENCODE:-}" ]]
     }
     ```
2. **`plugins/soleur/test/operator-script.test.sh`**:
   - In `pty_drive` (Guard 8), add `-u OPENCODE` to `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u OPENCODE` so the human-terminal simulation is hermetic when the test suite itself runs inside OpenCode.
   - In `pty_drive_agent` / `gagent_check` (Guard 8), add `pty_drive_opencode` (or parameterize `pty_drive_agent`) that runs `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT OPENCODE=1 script -qec "$cmd" /dev/null` and assert in `gagent_check` that `soleur_op_ack_or_die` exits `64` with `SOLEUR_BOOTSTRAP_INPUT_REQUIRED`.
   - In `g11_pty` (Guard 11), add `-u OPENCODE` to `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u OPENCODE`.
   - In `g11_check` row `N` (Guard 11), add world `n1b`: run `g11_pty "$lib" OPENCODE=1 -- "${argv[@]}"` and assert `g11_expect "N pty yes inside OpenCode harness" 75 'SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED' 0`.
   - Add mutation row `m14b`: strip ` \|\| -n "\$\{OPENCODE:-\}"` from `soleur_op_in_agent_harness()` via `g11_mutant "m14b a pty yes inside OpenCode harness is accepted" 'N pty yes inside OpenCode harness'` AND run `assert_red gagent_check "m14b gagent_check catches OPENCODE stripped from soleur_op_in_agent_harness" "$SB/mut/g11-m14b-a-pty-yes-inside-OpenCode-harness-is-accepted.sh"`.
   - Bump `FLOOR=208` to `FLOOR=211` to match the new exact assertion count (`211`).

### Phase 2: Qualify the receipt path in `operator-bootstrap/SKILL.md` and update `sync-opencode-adapter.ts` + `opencode/INSTRUCTIONS.md`

1. **`plugins/soleur/skills/operator-bootstrap/SKILL.md`**:
   - In `## The staged contract in one screen`, update the `- The **receipt**:` bullet so it names the harness qualification up front:
     > - The **receipt** (Claude Code interactive only): a plugin PreToolUse hook (`plugins/soleur/hooks/operator-stage-approval.sh`) mints a one-time record when the harness shows the person the exact command, and rewrites the command to carry `SOLEUR_APPROVAL_NONCE`. The script consumes the record before its first write. An environment variable or a flag set by the agent is never an approval. On harnesses without that hook (OpenCode, Codex, Devin cloud, Grok) and on the web app, no receipt can be minted: `--apply` exits 75 (`SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED`) with nothing written (see **Surfaces** below).
   - In `## Running a generated script` → `**Surfaces.**`, include `OpenCode` in the non-hook harnesses list:
     > Harnesses without the hook (OpenCode, Codex, Devin cloud, Grok) and the web app: the script exits 75 and writes nothing; say "this surface cannot make production changes yet" and **never** tell the person to open a terminal (the web approval adapter is #9388; per-harness adapters are #9389).
2. **`plugins/soleur/scripts/sync-opencode-adapter.ts` and `plugins/soleur/opencode/INSTRUCTIONS.md`**:
   - In `instructions()` in `plugins/soleur/scripts/sync-opencode-adapter.ts`, update the operator-stage-approval paragraph under `## Hooks and completion` so it reflects that `soleur_op_in_agent_harness` recognises `OPENCODE` (alongside `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT`):
     - State that `soleur_op_stage_gate` finds no receipt and exits **75** (`SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED`).
     - State that the typed-`yes` fallback (`-t 0`/`-t 1` **and** `! soleur_op_in_agent_harness`) is also closed here because `soleur_op_in_agent_harness` recognises `OPENCODE` (which OpenCode sets on every `shell` child): direct `shell` calls have no tty (`fd 0/1/2` are pipes, measured on OpenCode 2.1.2), and even if a child allocates a pseudo-terminal (`script`, `python pty`), `OPENCODE` keeps the fallback refused because a terminal inside an agent harness is not evidence of a person.
     - Keep the required anchors (`hooks/operator-stage-approval.sh` and `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED`) and the closing sentence (`**No receipt can be minted on this harness**, so a staged \`--apply\` refuses rather than approving. Nothing is approved silently.`).
   - Run `bun plugins/soleur/scripts/sync-opencode-adapter.ts` to regenerate `plugins/soleur/opencode/INSTRUCTIONS.md`, then verify with `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check`.

## Files to Edit

- `plugins/soleur/scripts/lib/operator-script.sh`
- `plugins/soleur/test/operator-script.test.sh`
- `plugins/soleur/skills/operator-bootstrap/SKILL.md`
- `plugins/soleur/scripts/sync-opencode-adapter.ts`
- `plugins/soleur/opencode/INSTRUCTIONS.md` (regenerated via `sync-opencode-adapter.ts`)

## Files to Create

- `knowledge-base/project/plans/2026-10-23-fix-opencode-operator-stage-gate-plan.md`
- `knowledge-base/project/specs/feat-one-shot-10877-opencode-operator-stage-gate/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10877-opencode-operator-stage-gate/decision-challenges.md`

## Open Code-Review Overlap

None — queried all open `code-review`-labeled issues via `gh issue list --label code-review --state open --json number,title,body --limit 200` and checked against all five planned files to edit (`plugins/soleur/scripts/lib/operator-script.sh`, `plugins/soleur/test/operator-script.test.sh`, `plugins/soleur/skills/operator-bootstrap/SKILL.md`, `plugins/soleur/scripts/sync-opencode-adapter.ts`, `plugins/soleur/opencode/INSTRUCTIONS.md`); zero matches.

## User-Brand Impact

- **If this lands broken, the user experiences:** On OpenCode, an agent running a generated `bootstrap.sh` (or a legacy class-2 script calling `soleur_op_ack_or_die`) that wraps the invocation in a PTY allocator (`script -qec`, `python3 -c 'import pty...'`) can pipe its own `yes` into the `tty-ack` fallback and execute a production write (Doppler secret write, GitHub secret write, token rotation) without human approval and without deliberately unsetting harness variables. Conversely, if the `SKILL.md` qualification is missing or wrong, an OpenCode session plans a write stage assuming a PreToolUse receipt will be minted and dead-ends at exit 75 without knowing why or what to tell the founder.
- **If this leaks, the user's workflow is exposed via:** Unapproved production secret/configuration mutations executed by an instruction-following agent on OpenCode via a PTY wrapper (`approval=tty-ack` in `bootstrap-runs.jsonl`), bypassing the human approval boundary promised by ADR-264.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** Chosen `single-user incident` (matching ADR-264's own `brand_survival_threshold: single-user incident`) because an unapproved production write on a founder's machine violates the human-acknowledgement trust boundary on a single occurrence.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED stage=<s> approval_digest=<hex> surface=<surface> (for v2 staged scripts) and SOLEUR_BOOTSTRAP_INPUT_REQUIRED var=destructive-write-ack(agent-harness-no-typed-ack) tty=0 (for class-2 ack) on stdout, paired with event:run_halt reason:approval_required|input_required in bootstrap-runs.jsonl"
  cadence: "per staged --apply or class-2 ack invocation inside an agent harness"
  alert_target: "founder-local stdout and bootstrap-runs.jsonl beside the script (Observability Layer 7 cli-stdout-artifact; no Soleur-hosted sink per ADR-264)"
  configured_in: "plugins/soleur/scripts/lib/operator-script.sh (soleur_op_in_agent_harness, soleur_op_ack_or_die, soleur_op_stage_gate)"

error_reporting:
  destination: "stdout refusal markers (SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED / SOLEUR_BOOTSTRAP_INPUT_REQUIRED) plus plain-language founder sentence and bootstrap-runs.jsonl run_halt record (Layer 7 cli-stdout-artifact)"
  fail_loud: "exit 75 with SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED on v2 staged scripts; exit 64 with SOLEUR_BOOTSTRAP_INPUT_REQUIRED on legacy class-2 ack"

failure_modes:
  - mode: "Agent in OpenCode invokes --apply without a receipt (or wraps --apply in a PTY and pipes yes)"
    detection: "soleur_op_in_agent_harness sees OPENCODE non-empty, skips tty-ack, emits SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED on stdout, writes run_halt reason=approval_required to bootstrap-runs.jsonl, and exits 75 (Layer 7 cli-stdout-artifact; on the hosted web-platform path, SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK=1 opts out the hook and agent-runner-query-options.ts extracts SOLEUR_* Bash markers into Layer 2 pino/Sentry breadcrumbs)"
    alert_route: "founder session stdout + local bootstrap-runs.jsonl artifact (Layer 7 cli-stdout-artifact)"
  - mode: "Agent in OpenCode invokes a legacy class-2 script calling soleur_op_ack_or_die through a PTY"
    detection: "soleur_op_in_agent_harness sees OPENCODE non-empty, emits SOLEUR_BOOTSTRAP_INPUT_REQUIRED var=destructive-write-ack(agent-harness-no-typed-ack) tty=0 on stdout, writes run_halt reason=input_required to bootstrap-runs.jsonl, and exits 64 (Layer 7 cli-stdout-artifact)"
    alert_route: "founder session stdout + local bootstrap-runs.jsonl artifact (Layer 7 cli-stdout-artifact)"

logs:
  where: "knowledge-base/project/specs/feat-<name>/bootstrap-runs.jsonl beside the generated script"
  retention: "founder repository lifecycle (copied to bootstrap-runs-<issue>.jsonl on close)"

discoverability_test:
  command: grep -c 'OPENCODE:-' plugins/soleur/scripts/lib/operator-script.sh
  expected_output: "1"
```

## Guard Contract

### Guard 1 — Agent-harness PTY refusal covers OpenCode (`gagent_check` and `g11_check`)

**Property.** Whenever `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, or `OPENCODE` is non-empty in the environment, `soleur_op_in_agent_harness` returns true (`0`), so a typed `yes` delivered over a pseudo-terminal (`[[ -t 0 && -t 1 ]]`) is refused by both `soleur_op_ack_or_die` (exit `64`, `SOLEUR_BOOTSTRAP_INPUT_REQUIRED`, zero mutating calls) and `soleur_op_stage_gate` (exit `75`, `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED`, zero mutating calls), while a pseudo-terminal with all three unset (`-u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u OPENCODE`) is accepted as the positive control.

**Assembly.** Every terminal-fallback acknowledgement in `plugins/soleur/scripts/lib/operator-script.sh` flows through the single predicate `soleur_op_in_agent_harness()`:
1. `soleur_op_ack_or_die()` calls `if soleur_op_in_agent_harness; then soleur_op_input_required "destructive-write-ack(agent-harness-no-typed-ack)" ack; fi` before `[[ -t 0 ]]` and `read`.
2. `soleur_op_stage_gate()` gates step 3 (the `tty-ack` fallback) on `if [[ -t 0 && -t 1 ]] && ! soleur_op_in_agent_harness; then` before calling `soleur_op_ack_or_die`.
There are no other `tty-ack` or class-2 prompt sites in `operator-script.sh` (enforced by Guard 4's prompt census in `plugins/soleur/test/operator-script.test.sh`).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `if soleur_op_in_agent_harness; then ... fi` block from `soleur_op_ack_or_die` (`gd4.sh` in Guard 8) | RED (`gagent_check` fails because PTY `yes` inside Claude Code / OpenCode exits 0 instead of 64) |
| 2 | Remove `&& ! soleur_op_in_agent_harness` from `soleur_op_stage_gate` (`m14` in Guard 11) | RED (`g11_check` fails with `'N pty yes inside an agent harness'`) |
| 3 | Remove `\|\| -n "${OPENCODE:-}"` from `soleur_op_in_agent_harness()` (second/third member stripped after compliant first, `m14b` in Guard 11) | RED (`g11_check` fails with `'N pty yes inside OpenCode harness'` and `gagent_check` fails on the `OPENCODE=1` PTY probe) |
| 4 | Own-dispatch check (`J` in `g11_check` and positive control `N2` in `g11_check` / `gagent_check`): stub sees `>= 1` mutating call on valid receipt and on un-harnessed PTY control | RED if the driver or stub fails to execute |

**Harness rows.**

| # | Edit to the suite or must-PASS input | Expected |
|---|---|---|
| H1 | Run `operator-script.test.sh` with `OPENCODE=1` exported in the caller's environment (the live OpenCode `shell` tool environment) | PASS (because `pty_drive` and `g11_pty` scrub `-u OPENCODE` for the un-harnessed control rows; without `-u OPENCODE` in the harness helpers, the control rows fail) |
| H2 | Must-PASS non-canonical input: `g11_pty` with `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, and `OPENCODE` all unset (`n2` control row) | PASS (`rc=0`, `GATE_PASSED`, `1` mutating call) |

**Anchor.** `plugins/soleur/test/operator-script.test.sh` runs in CI and enforces `FLOOR=211` via direct `printf` + `exit 1` (ADR-193 instrument self-test + anti-vacuity floor), and `plugins/soleur/test/opencode-adapter-drift.test.ts` (`sync-opencode-adapter.ts --check`) pins byte parity between `sync-opencode-adapter.ts` and `plugins/soleur/opencode/INSTRUCTIONS.md`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | `[issue #10877]` "1. `soleur_op_in_agent_harness()` does not recognise OpenCode ... `plugins/soleur/scripts/lib/operator-script.sh` gates the typed-`yes` fallback on `[[ -t 0 && -t 1 ]] && ! soleur_op_in_agent_harness` and the detector tests only `CLAUDECODE` / `CLAUDE_CODE_ENTRYPOINT`. OpenCode sets `OPENCODE`" | Phase 1 (`plugins/soleur/scripts/lib/operator-script.sh`, `plugins/soleur/test/operator-script.test.sh`) | mapped |
| 2 | `[issue #10877]` "Measurement to take: does a `shell` call's child process get a tty on OpenCode 2.1.x?" | Research Insights §Live Measurement Record (measured on `opencode v2.1.2`: `fd 0/1/2` are not TTYs by default, `OPENCODE=1` is set; PTY wrappers inside `shell` make `-t 0 && -t 1` true) | mapped |
| 3 | `[issue #10877]` "2. `skills/operator-bootstrap/SKILL.md` states the receipt path unqualified ... Needs one qualifier naming the harnesses where the hook exists, and what happens where it does not." | Phase 2.1 (`plugins/soleur/skills/operator-bootstrap/SKILL.md`) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/scripts/lib/operator-script.sh` (`soleur_op_in_agent_harness` checks `OPENCODE`) | ask 1: "`soleur_op_in_agent_harness()` does not recognise OpenCode ... OpenCode sets `OPENCODE`" | asked |
| `plugins/soleur/test/operator-script.test.sh` (`-u OPENCODE` in `pty_drive`/`g11_pty`, `OPENCODE=1` refusal assertions, mutant `m14b`, `FLOOR=211`) | ask 1: "`soleur_op_in_agent_harness()` does not recognise OpenCode" | inferred — justification: `cq-write-failing-tests-before` and Guard Contract §2.12 require a RED/GREEN test and mutation row for the new `OPENCODE` predicate arm, and `-u OPENCODE` is required so the suite's own human-terminal control rows pass when run inside OpenCode |
| `plugins/soleur/skills/operator-bootstrap/SKILL.md` (qualify receipt bullet + add OpenCode to Surfaces non-hook list) | ask 3: "`skills/operator-bootstrap/SKILL.md` states the receipt path unqualified ... Needs one qualifier naming the harnesses where the hook exists, and what happens where it does not." | asked |
| `plugins/soleur/scripts/sync-opencode-adapter.ts` + regenerated `plugins/soleur/opencode/INSTRUCTIONS.md` | — | inferred — justification: `opencode/INSTRUCTIONS.md` currently states "`soleur_op_in_agent_harness`, which recognises only `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT` — neither is set under OpenCode — so that arm is open here whenever the spawned shell has a tty"; leaving that sentence after Phase 1 makes the shipped OpenCode instructions factually false |
| `knowledge-base/project/plans/2026-10-23-fix-opencode-operator-stage-gate-plan.md`, `tasks.md`, `decision-challenges.md` | — | inferred — justification: required `soleur:plan` and `soleur:one-shot` pipeline artifacts |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 8 (5 edit + 3 create) | Estimated changed lines: ~60
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** Inline CTO/Architecture assessment (depth-1 subagent on OpenCode). No technical fork requires an operator question. Two engineering points folded into the plan:
1. `soleur_op_in_agent_harness()` tests `[[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" || -n "${OPENCODE:-}" ]]` — matching `detectHarness()` in `plugins/soleur/lib/harness.ts` without matching generic `AI_AGENT`.
2. `pty_drive` and `g11_pty` in `plugins/soleur/test/operator-script.test.sh` must unset `OPENCODE` (`env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u OPENCODE`) when simulating an un-harnessed human terminal, because running the test suite inside an OpenCode session exports `OPENCODE=1` into the test process and would otherwise cause the positive-control TTY rows to fail closed.

### Product

**Status:** reviewed
**Assessment:** Inline CPO/Spec-Flow assessment (depth-1 subagent on OpenCode). Sign-off granted for `single-user incident` threshold (matching ADR-264). Both places in `plugins/soleur/skills/operator-bootstrap/SKILL.md` where an agent reads the receipt/surface contract (`## The staged contract in one screen` → `- The **receipt**:` and `## Running a generated script` → `**Surfaces.**`) must name OpenCode alongside Codex, Devin cloud, and Grok so an OpenCode agent neither expects a PreToolUse receipt nor tells the founder to open a terminal. No UI surface is touched (`Pencil available: N/A (no UI surface)`).

## Acceptance Criteria

- [x] **AC1 (`operator-script.sh` harness detection):** `soleur_op_in_agent_harness()` in `plugins/soleur/scripts/lib/operator-script.sh` returns `0` (true) when `OPENCODE` is non-empty, alongside `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT`. Verified by:
  `bash -c 'source plugins/soleur/scripts/lib/operator-script.sh; env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT OPENCODE=1 bash -c "source plugins/soleur/scripts/lib/operator-script.sh; soleur_op_in_agent_harness" && env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u OPENCODE bash -c "source plugins/soleur/scripts/lib/operator-script.sh; ! soleur_op_in_agent_harness"'` exiting `0`.
- [x] **AC2 (`operator-script.test.sh` Guard 8 + Guard 11 + mutation row):** `plugins/soleur/test/operator-script.test.sh` passes (`bash plugins/soleur/test/operator-script.test.sh` exits `0` with `211 assertions, 0 failed` and `FLOOR=211`), including when `OPENCODE=1` is exported in the caller's environment (`OPENCODE=1 bash plugins/soleur/test/operator-script.test.sh`), and includes:
  - `gagent_check` verifying that a PTY `yes` under `OPENCODE=1` (with `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT` unset) exits `64` with `SOLEUR_BOOTSTRAP_INPUT_REQUIRED`;
  - `g11_check` row `N` verifying that a PTY `yes` under `OPENCODE=1` exits `75` with `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED` and `0` mutating calls;
  - mutation row `m14b` proving that removing `|| -n "${OPENCODE:-}"` from `soleur_op_in_agent_harness()` drives both `g11_check` (for `'N pty yes inside OpenCode harness'`) and `gagent_check` RED.
- [x] **AC3 (`operator-bootstrap/SKILL.md` qualification):** `plugins/soleur/skills/operator-bootstrap/SKILL.md` qualifies the `- The **receipt**` bullet in `## The staged contract in one screen` (naming Claude Code interactive for the PreToolUse hook and stating that harnesses without the hook — OpenCode, Codex, Devin cloud, Grok — and the web app exit 75 `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED` with nothing written) and includes `OpenCode` in the `Harnesses without the hook` parenthetical in `## Running a generated script` → `**Surfaces.**`. Verified by `grep -c "OpenCode" plugins/soleur/skills/operator-bootstrap/SKILL.md` returning `2`.
- [x] **AC4 (`sync-opencode-adapter.ts` + `opencode/INSTRUCTIONS.md` parity):** `plugins/soleur/scripts/sync-opencode-adapter.ts` and regenerated `plugins/soleur/opencode/INSTRUCTIONS.md` state that `soleur_op_in_agent_harness` recognises `OPENCODE` (so the `tty-ack` fallback is closed on OpenCode even if a child allocates a tty, while direct `shell` calls have no tty as measured on OpenCode 2.1.2) and retain the `hooks/operator-stage-approval.sh` and `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED` anchors. Verified by `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` exiting `0` (`opencode-adapter ok`) and `! grep -q "recognises only" plugins/soleur/opencode/INSTRUCTIONS.md`.
- [x] **AC5 (Regression & Guard suites):** All related test suites and linters pass:
  - `bash plugins/soleur/test/operator-script.test.sh`
  - `bash plugins/soleur/test/operator-agent-runnable.test.sh`
  - `bash plugins/soleur/test/operator-ack-guard.test.sh`
  - `cd plugins/soleur && bun test test/opencode-adapter-drift.test.ts test/opencode-plugin.test.ts test/harness-claim-parity.test.ts test/harness-tool-map.test.ts test/components.test.ts test/invocation-axis.test.ts`
  - `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-23-fix-opencode-operator-stage-gate-plan.md`

## Test Scenarios

- **Scenario 1 (`unit`, `operator-script.test.sh` Guard 8):** Given `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT` are unset and `OPENCODE=1` is set, when `soleur_op_ack_or_die` is invoked inside a pseudo-terminal (`script -qec`) with `yes\n` piped to stdin, then it exits `64` and prints `SOLEUR_BOOTSTRAP_INPUT_REQUIRED var=destructive-write-ack(agent-harness-no-typed-ack) tty=0`.
- **Scenario 2 (`unit`, `operator-script.test.sh` Guard 11 row N):** Given `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT` are unset and `OPENCODE=1` is set, when `soleur_op_stage_gate` is invoked inside a pseudo-terminal (`script -qec`) with `yes\n` piped to stdin and no receipt nonce, then it exits `75`, prints `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED`, and performs `0` mutating calls.
- **Scenario 3 (`unit`, `operator-script.test.sh` positive control under ambient `OPENCODE=1`):** Given the test suite is invoked from an OpenCode session (`OPENCODE=1` in the parent environment), when `pty_drive` and `g11_pty` run the un-harnessed human-terminal control rows (`env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u OPENCODE`), then `soleur_op_in_agent_harness` returns `1` (false) and the typed `yes` is accepted (`rc=0`).
- **Scenario 4 (`unit`, `operator-script.test.sh` mutation `m14b`):** Given a mutant copy of `operator-script.sh` with `|| -n "${OPENCODE:-}"` stripped from `soleur_op_in_agent_harness()`, when `g11_check` runs against the mutant, then `g11_check` exits non-zero naming `'N pty yes inside OpenCode harness'`.
- **Scenario 5 (`unit`, `opencode-adapter-drift.test.ts` + `--check`):** Given `sync-opencode-adapter.ts` is updated and `opencode/INSTRUCTIONS.md` is regenerated, when `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` and `bun test plugins/soleur/test/opencode-adapter-drift.test.ts` run, then both exit `0`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- **Unset `OPENCODE` in `pty_drive` and `g11_pty`:** Both helpers in `plugins/soleur/test/operator-script.test.sh` simulate a person's own terminal outside any harness. Because this pipeline runs on OpenCode (`OPENCODE=1` in the environment), omitting `-u OPENCODE` from those two `env -u ...` lines will cause the un-harnessed control rows in Guard 8 and Guard 11 to fail!
- **Never hand-edit `plugins/soleur/opencode/INSTRUCTIONS.md`:** Edit `instructions()` in `plugins/soleur/scripts/sync-opencode-adapter.ts`, run `bun plugins/soleur/scripts/sync-opencode-adapter.ts`, and verify with `--check`.
- **Preserve the `opencode/INSTRUCTIONS.md` anchor tokens:** The #10820 plan and tests check for `operator-stage-approval` and `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED` in both `sync-opencode-adapter.ts` and `opencode/INSTRUCTIONS.md`. Keep both tokens intact when updating the `soleur_op_in_agent_harness` explanation.

## References

- Issue: #10877
- Prior plan: `knowledge-base/project/plans/2026-10-22-fix-opencode-harness-followups-plan.md`
- Decision record: `knowledge-base/engineering/architecture/decisions/ADR-264-generated-operator-scripts-are-agent-run-in-stages.md`
- Related issues: #9321, #9388, #9389, #10819, #10820
