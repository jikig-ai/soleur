---
feature: feat-one-shot-pencil-collapse-recovery-4859
plan: knowledge-base/project/plans/2026-06-11-feat-pencil-collapse-guard-recovery-plan.md
issue: 4859
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — Pencil collapse-guard (auto-recover tracked .pen truncated by open_document)

## Phase 0 — Preconditions
- [ ] 0.1 Re-read `pencil-open-guard.sh` path-resolution + `git ls-files --error-unmatch` pattern.
- [ ] 0.2 Re-read `lib/incidents.sh` `emit_incident` signature (slot 5 = `PostToolUse`).
- [ ] 0.3 Choose a NEW non-retired rule-id (e.g. `cq-pencil-collapse-auto-recover`); confirm `grep -n '<id>' scripts/retired-rule-ids.txt` is empty.
- [ ] 0.4 Confirm the PostToolUse system-message field (`hookSpecificOutput.additionalContext`) against the installed Claude Code schema.

## Phase 1 — Tests first (TDD, cq-write-failing-tests-before)
- [ ] 1.1 Write `.claude/hooks/pencil-collapse-guard.test.sh` (mirror `iac-plan-write-guard.test.sh`): `git init` fixture per case, `INCIDENTS_REPO_ROOT` redirect, stdin payloads.
- [ ] 1.2 Cases: AC2 restore+message+incident; AC3 healthy no-op (bytes+mtime); AC4 HEAD-empty no-op; AC5 untracked no-op; AC6 empty/non-repo/malformed → exit 0 no write.
- [ ] 1.3 Confirm suite is RED (hook absent).

## Phase 2 — Hook implementation
- [ ] 2.1 Create `.claude/hooks/pencil-collapse-guard.sh` (`set -uo pipefail`, source incidents.sh, canonical rule body in header).
- [ ] 2.2 filePath resolve → repo root → relpath → tracked check (exit 0 on any miss).
- [ ] 2.3 Conservative on-disk collapse detection (only unambiguous empty-document shape).
- [ ] 2.4 HEAD-blob non-empty guard; restore via `git show HEAD:<rel> > file`.
- [ ] 2.5 `emit_incident <new-id> warn "<prefix>" "$REL_PATH" PostToolUse` + `additionalContext` system message (stderr fallback).
- [ ] 2.6 Every branch ends `exit 0`; `chmod +x`.
- [ ] 2.7 Suite GREEN: `bash .claude/hooks/pencil-collapse-guard.test.sh` → Fail: 0.

## Phase 3 — Wiring
- [ ] 3.1 Append PostToolUse block (`matcher: mcp__pencil__open_document`) to `.claude/settings.json`; verify valid JSON + `jq -e` selector (AC1).

## Phase 4 — Docs (owning-artifact placement, NO AGENTS sidecar)
- [ ] 4.1 pencil-setup SKILL §"Tracked .pen collapse recovery" + `[hook-enforced: pencil-collapse-guard.sh]` tag + new rule-id (AC9); SKILL `description:` unchanged.
- [ ] 4.2 README roster row for the new hook (AC10).
- [ ] 4.3 Verify AC11: no `AGENTS.{md,core,docs,rest}` in the diff.

## Phase 5 — Part B upstream + issue update
- [ ] 5.1 Draft report → `knowledge-base/project/specs/feat-one-shot-pencil-collapse-recovery-4859/upstream-pencil-report.md` (AC14, always written).
- [ ] 5.2 AskUserQuestion → file to `highagency/pencil-desktop-releases` via `gh issue create --body-file`; capture URL (AC13).
- [ ] 5.3 `gh issue comment 4859` with Part-A + Part-B outcome; note criterion (a) satisfied (AC15).

## Phase 6 — Ship
- [ ] 6.1 PR body `Closes #4859` (AC12); ensure CLA-signed author on any committed stub.
