# Tasks — fix: operator-stage gate: OpenCode is not recognised as an agent harness, and SKILL.md states the receipt path unqualified (#10877)

Plan: `knowledge-base/project/plans/2026-10-23-fix-opencode-operator-stage-gate-plan.md`
Branch: `feat-one-shot-10877-opencode-operator-stage-gate`
Issue: #10877

## Phase 1: Setup & RED Tests (`operator-script.test.sh`)

- [x] 1.1 Update `pty_drive` and `g11_pty` in `plugins/soleur/test/operator-script.test.sh` to include `-u OPENCODE` (`env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u OPENCODE`) so un-harnessed human-terminal control rows are hermetic when run inside an OpenCode session.
- [x] 1.2 Add `OPENCODE=1` PTY refusal check to `gagent_check` (Guard 8) in `plugins/soleur/test/operator-script.test.sh` (asserting exit `64` + `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` when `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT` are unset and `OPENCODE=1` is set).
- [x] 1.3 Add `OPENCODE=1` PTY refusal check to `g11_check` row `N` (`n1b`, Guard 11) and add mutation row `m14b` (stripping `|| -n "${OPENCODE:-}"` from `soleur_op_in_agent_harness()`, asserted RED against both `g11_check` and `gagent_check`) in `plugins/soleur/test/operator-script.test.sh`, bumping `FLOOR=211`.
- [x] 1.4 Run `bash plugins/soleur/test/operator-script.test.sh` and confirm it fails RED on the new `OPENCODE=1` refusal checks before `operator-script.sh` is edited.

## Phase 2: Core Implementation (`operator-script.sh`, `SKILL.md`, `sync-opencode-adapter.ts`, `INSTRUCTIONS.md`)

- [x] 2.1 Update `soleur_op_in_agent_harness()` and its comment in `plugins/soleur/scripts/lib/operator-script.sh` to check `[[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" || -n "${OPENCODE:-}" ]]`.
- [x] 2.2 Run `bash plugins/soleur/test/operator-script.test.sh` and confirm all `211` assertions pass GREEN (`0 failed`).
- [x] 2.3 Update `plugins/soleur/skills/operator-bootstrap/SKILL.md`:
  - Qualify `- The **receipt**` in `## The staged contract in one screen` (naming Claude Code interactive for the PreToolUse hook and stating that harnesses without the hook — OpenCode, Codex, Devin cloud, Grok — and the web app exit 75 `SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED` with nothing written).
  - Add `OpenCode` to `Harnesses without the hook (OpenCode, Codex, Devin cloud, Grok)` in `## Running a generated script` → `**Surfaces.**`.
- [x] 2.4 Update `instructions()` in `plugins/soleur/scripts/sync-opencode-adapter.ts` so `## Hooks and completion` reflects that `soleur_op_in_agent_harness` recognises `OPENCODE` (alongside `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT`), closing the `tty-ack` fallback on OpenCode even if a child allocates a tty (while direct `shell` calls have no tty as measured on OpenCode 2.1.2).
- [x] 2.5 Regenerate `plugins/soleur/opencode/INSTRUCTIONS.md` via `bun plugins/soleur/scripts/sync-opencode-adapter.ts` and verify `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` outputs `opencode-adapter ok`.

## Phase 3: Testing & Verification

- [x] 3.1 Verify AC1: `soleur_op_in_agent_harness` returns `0` under `OPENCODE=1` and `1` when all three markers are unset.
- [x] 3.2 Verify AC2: `bash plugins/soleur/test/operator-script.test.sh` and `OPENCODE=1 bash plugins/soleur/test/operator-script.test.sh` both pass with `211 assertions, 0 failed`.
- [x] 3.3 Verify AC3: `grep -c "OpenCode" plugins/soleur/skills/operator-bootstrap/SKILL.md` returns `2`.
- [x] 3.4 Verify AC4: `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` exits `0` and `! grep -q "recognises only" plugins/soleur/opencode/INSTRUCTIONS.md`.
- [x] 3.5 Verify AC5: Run `bash plugins/soleur/test/operator-agent-runnable.test.sh`, `bash plugins/soleur/test/operator-ack-guard.test.sh`, `cd plugins/soleur && bun test test/opencode-adapter-drift.test.ts test/opencode-plugin.test.ts test/harness-claim-parity.test.ts test/harness-tool-map.test.ts test/components.test.ts test/invocation-axis.test.ts`, and `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-23-fix-opencode-operator-stage-gate-plan.md`.
