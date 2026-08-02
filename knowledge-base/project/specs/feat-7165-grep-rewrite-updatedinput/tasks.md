---
title: Tasks — rewrite grep to command grep via PreToolUse updatedInput
feature: feat-7165-grep-rewrite-updatedinput
issue: 7165
pr: 7167
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-08-02-feat-grep-rewrite-command-grep-plan.md
---

# Tasks: `grep` → `command grep` rewrite hook

Phase order is load-bearing: the masking helper (Phase 2) is a contract the hook
(Phase 3) consumes. Do not reorder.

## Phase 1 — Preconditions (no code)

- [ ] 1.1 Re-run the `updatedInput` probe in an **isolated** `claude -p` subprocess
      with a throwaway `--settings` JSON. Never modify the live session's settings.
      Confirm the rewritten command executes.
- [ ] 1.2 Confirm the rewrite applies with **no** `permissionDecision` key.
- [ ] 1.3 Re-run the two-hook probe: a sibling `deny` must still win.
- [ ] 1.4 Confirm installed GNU grep accepts `-I` and all six `--exclude-dir`
      values, and still exits 2 on `-G` + `-E`.
- [ ] 1.5 Record all four results in the PR body.

## Phase 2 — `mask_command_bodies` (TDD)

- [ ] 2.1 RED: test asserting `${#masked} == ${#original}` for a payload carrying a
      double-quoted region, a single-quoted region, and a heredoc body.
- [ ] 2.2 RED: test asserting no `grep` token survives inside a masked region.
- [ ] 2.3 GREEN: implement `mask_command_bodies` in `.claude/hooks/lib/incidents.sh`,
      beside `strip_command_bodies`. Same regex family; equal-length filler.
- [ ] 2.4 Comment why the existing stripper cannot be reused (length-destroying,
      42 → 29 measured).

## Phase 3 — the hook (TDD)

- [ ] 3.1 RED: fixture suite `.claude/hooks/grep-rewrite-guard.test.sh` covering the
      full matrix in the plan's Test Scenarios. Mirror `guardrails.test.sh`'s harness
      (stdin payloads, `INCIDENTS_REPO_ROOT` redirect, non-git CWD isolation).
- [ ] 3.2 GREEN: create `.claude/hooks/grep-rewrite-guard.sh`.
  - [ ] 3.2.1 Extract `.tool_input.command` forcing a scalar
        (`| if type=="string" then . else tojson end`). Do **not** reproduce the
        `eval` + `jq @sh` RCE.
  - [ ] 3.2.2 Return early (no rewrite) when the shim's own bypass predicate matches.
  - [ ] 3.2.3 Mask, match at command position, substitute right-to-left in the original.
  - [ ] 3.2.4 Emit `updatedInput` only — **never** `permissionDecision`.
  - [ ] 3.2.5 Emit nothing and `exit 0` when nothing matched.
  - [ ] 3.2.6 Fail-open on malformed input, but `emit_incident "grep-rewrite-disarm"`.
  - [ ] 3.2.7 `emit_incident "grep-rewrite-residual"` when a residual form is detected.
- [ ] 3.3 `chmod +x` and confirm the **index** mode is 100755.
- [ ] 3.4 Register on the `Bash` matcher in `.claude/settings.json`.

## Phase 4 — exec-bit gate

- [ ] 4.1 Create `.claude/hooks/hook-exec-bit.test.sh`.
- [ ] 4.2 Derive hook paths from `.claude/settings.json` (strip the
      `$CLAUDE_PROJECT_DIR` prefix) — **not** from a glob. Six tracked hook `.sh`
      files are legitimately 100644 (libs + tests); a glob goes RED on two of them.
- [ ] 4.3 Assert each derived path is 100755 via `git ls-files -s`.
- [ ] 4.4 Add a minimum-cardinality guard so a broken derivation cannot pass vacuously.

## Phase 5 — ADR + C4

- [ ] 5.1 Author `ADR-155-rewrite-not-classify-for-shim-reaching-grep.md` (ordinal
      provisional — highest on `origin/main` is 154). `## Alternatives Considered`
      carries the three refuted cost models plus the recursive carve-out.
- [ ] 5.2 Update `model.c4`: the `hooks` container technology/description now
      includes input rewriting, not only guarding.
- [ ] 5.3 Update `model.c4`: the `hooks -> claude "Guards tool calls"` relationship
      label likewise.
- [ ] 5.4 Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 5.5 If the ADR ordinal moves at ship time, sweep plan + tasks + AC12 in the
      same edit.

## Phase 6 — Mutation battery

- [ ] 6.1 Delete the rewrite → suite RED.
- [ ] 6.2 Mutate the anchor to also match `git grep` → suite RED.
- [ ] 6.3 Restore; suite GREEN.

## Phase 7 — Verification

- [ ] 7.1 AC1 reproducer probe under `ulimit -v 2000000` + `timeout`.
- [ ] 7.2 Full `bash scripts/test-all.sh`; assert the two new suites appear **by name**.
- [ ] 7.3 Walk every AC1–AC12 and paste evidence into the PR body.
