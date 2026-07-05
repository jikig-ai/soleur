---
title: "Tasks — fail-closed delete guards + freeze edit-lock (guardrails.sh)"
issue: 5988
epic: 5983
branch: feat-one-shot-5988-delete-guards-freeze-lock
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-05-feat-delete-guards-freeze-edit-lock-plan.md
---

# Tasks

Derived from the plan. Delete guard (a) + freeze edit-lock (b) ship in one PR.
TDD: write failing tests before implementation.

## Phase 0 — Preconditions

- [x] 0.1 Run `bash .claude/hooks/guardrails.test.sh` — baseline green (16/16).
- [x] 0.2 Run `bash .claude/hooks/hookeventname-coverage.test.sh` — baseline green.
- [x] 0.3 Confirmed `guardrails-*` is a documented sentinel namespace (README:43); orphan-gate test (`rule-metrics-aggregate.test.sh`) is synthetic/self-contained → new ids don't trip it. `tests/hooks/test_hook_emissions.sh:176` asserts `.worktrees/` case → `guardrails-block-rm-rf-worktrees`; so KEEP the narrow gate, ADD a new `guardrails-block-recursive-delete` gate.
- [x] 0.4 Read `.openhands/hooks/guardrails.sh` (exit-2 protocol) + `.openhands/hooks.json` (`terminal`/`file_editor` matchers).

## Phase 1 — Freeze-lock control helper (RED → GREEN)

- [x] 1.1 Wrote failing `.claude/hooks/lib/freeze-lock.test.sh`.
- [x] 1.2 Implemented `.claude/hooks/lib/freeze-lock.sh` (`FREEZE_LOCK_REPO_ROOT` override mirrors `INCIDENTS_REPO_ROOT`).
- [x] 1.3 Tests green (11/11).

## Phase 2 — Hardened recursive-delete ownership proof

Model: **default-allow-except-protected** (keep every non-protected `rm -rf`
allowed; ADD deny for the protected class only). Reuse the `realpath -m` +
prefix-containment precedent at `follow-through-directive-gate.sh:185-189`.

- [x] 2.1 Parse `rm -rf`/`-fr` targets from `$COMMAND` (quote-aware `xargs -n1`; reset at chain boundaries). Kept the narrow `.worktrees/` gate as a fast subset above.
- [x] 2.2 realpath-resolve each target from the command's cwd (DENY-decision only — NOT an executor; contrast constitution.md:306).
- [x] 2.3 `.git`-tripwire / structural protection: DENY on repo root, any `git worktree list --porcelain` root (+ ancestors), `$HOME`, `/`, or `.git`-bearing dir; fail-closed on unresolvable target (checks raw form). Non-protected targets pass through.
- [x] 2.4 Staging ALLOW: under default-allow-except-protected a non-protected scratch dir is ALREADY allowed with no marker; the forgeable minted-marker unlock stays a documented default-off scaffold (never unlocks a protected target). AC3 "marked staging → allow" satisfied via default-allow.
- [x] 2.5 `emit_incident guardrails-block-recursive-delete deny …` + deny JSON with `hookEventName: "PreToolUse"`.

## Phase 3 — Freeze edit-lock branch (Write|Edit)

Precedent: `no-memory-write.sh` (dual Bash+Write|Edit registration, fail-open on
malformed JSON). Freeze prefix check reuses the `realpath -m` containment pattern.

- [x] 3.1 Added `FILE_PATH` to the single `@sh` jq fork; source `freeze-lock.sh` FAIL-SOFT (`|| true`) so a missing freeze helper never disarms the delete/commit/stash guards.
- [x] 3.2 Added the `[[ -n "$FILE_PATH" ]] && declare -f freeze_active_prefix` branch ABOVE the Bash sentinels; `exit 0` reachable only for file-tool payloads (TR3 — payload-shape disjointness, proven with a freeze ACTIVE).
- [x] 3.3 `emit_incident guardrails-freeze-edit-lock deny …` + deny JSON with `hookEventName: "PreToolUse"`.

## Phase 4 — Registration + mirrors + gitignore

- [x] 4.1 `.claude/settings.json`: added `Write|Edit` registration for `guardrails.sh` (JSON validated).
- [x] 4.2 `.openhands/hooks/guardrails.sh`: mirrored the delete-guard hardening (OpenHands `exit 2` protocol); deny reasons match the Claude side (diff-audited). Manually verified deny on repo-root/.git-bearing, allow on scratch.
- [x] 4.3 `.openhands/hooks.json`: freeze IS wired into `file_editor` (payload shape supports it — `.tool_input.path`). guardrails.sh sources the shared `freeze-lock.sh` cross-tree; both harnesses read the same state. Manually verified deny-outside/allow-inside. No tracking issue needed.
- [x] 4.4 `.gitignore`: added `.claude/.freeze*`.

## Phase 5 — Tests (TR3 regression load-bearing)

- [ ] 5.1 Add an Edit/Write payload builder to `guardrails.test.sh`.
- [ ] 5.2 TR3 regression: with a freeze ACTIVE, Bash `rm -rf ./.worktrees/foo` → deny; all six sentinels still fire.
- [ ] 5.3 Delete-guard fixtures: repo root / worktree root / symlink-to-root / `.git`-bearing → deny; marked staging dir → allow.
- [ ] 5.4 Freeze fixtures: inside allowed → allow; outside → deny; malformed/absent file → allow (fail-open).
- [ ] 5.5 `bash .claude/hooks/hookeventname-coverage.test.sh` green.

## Phase 6 — Prose + docs + full suite

- [ ] 6.1 Update guardrails.sh top-comment prose-rule block.
- [ ] 6.2 Add constitution.md (`knowledge-base/project/constitution.md`) prose rules for the hardened delete guard + freeze edit-lock.
- [ ] 6.3 `bash scripts/test-all.sh` green.
