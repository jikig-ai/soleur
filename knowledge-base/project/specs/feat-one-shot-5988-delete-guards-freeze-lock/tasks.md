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

- [ ] 0.1 Run `bash .claude/hooks/guardrails.test.sh` — baseline green.
- [ ] 0.2 Run `bash .claude/hooks/hookeventname-coverage.test.sh` — baseline green.
- [ ] 0.3 `git grep -n 'guardrails-' scripts/rule-metrics-aggregate.sh scripts/rule-metrics-aggregate.test.sh` — confirm `guardrails-*` rule_ids pass the orphan-gate.
- [ ] 0.4 Read `.openhands/hooks/guardrails.sh` (exit-2 protocol) + `.openhands/hooks.json` (`terminal`/`file_editor` matchers).

## Phase 1 — Freeze-lock control helper (RED → GREEN)

- [ ] 1.1 Write failing `.claude/hooks/lib/freeze-lock.test.sh` (set/status/clear round-trip; malformed→fail-open; absent→inactive).
- [ ] 1.2 Implement `.claude/hooks/lib/freeze-lock.sh` — state file `<repo-root>/.claude/.freeze-lock` (worktree-local via `cd -P && pwd -P`); `set <path>|status|clear`; `freeze_active_prefix` reader (absent/empty/malformed → echo nothing = fail-open).
- [ ] 1.3 Tests green.

## Phase 2 — Hardened recursive-delete ownership proof

- [ ] 2.1 In `.claude/hooks/guardrails.sh`, parse `rm -rf`/`-fr` targets from `$COMMAND`.
- [ ] 2.2 realpath-resolve each target (DENY-decision only — NOT an executor; contrast constitution.md:306).
- [ ] 2.3 `.git`-tripwire / structural protection: DENY on repo root, any `git worktree` root, `$HOME`, `/`, or `.git`-bearing dir; fail-closed on unresolvable protected-shape target.
- [ ] 2.4 Staging ALLOW conjunction: realpath-under-staging-root ∧ structural-name ∧ no-`.git` ∧ minted marker (marker never independently sufficient).
- [ ] 2.5 `emit_incident guardrails-block-recursive-delete deny …` + deny JSON with `hookEventName: "PreToolUse"`.

## Phase 3 — Freeze edit-lock branch (Write|Edit)

- [ ] 3.1 Add `FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')` to the extraction block; source `freeze-lock.sh`.
- [ ] 3.2 Add the `[[ -n "$FILE_PATH" ]]` branch ABOVE the Bash sentinels: active freeze + resolved path outside allowed prefix → deny; else allow; `exit 0` inside the branch only (never on a Bash-reachable path — TR3).
- [ ] 3.3 `emit_incident guardrails-freeze-edit-lock deny …` + deny JSON with `hookEventName: "PreToolUse"`.

## Phase 4 — Registration + mirrors + gitignore

- [ ] 4.1 `.claude/settings.json`: add `"matcher": "Write|Edit"` registration for `guardrails.sh`.
- [ ] 4.2 `.openhands/hooks/guardrails.sh`: mirror the delete-guard hardening in the OpenHands `exit 2` protocol (required in-PR).
- [ ] 4.3 `.openhands/hooks.json`: wire freeze into `file_editor` if payload shape supports it; else file a tracking issue for the freeze mirror (delete-guard mirror is non-negotiable).
- [ ] 4.4 `.gitignore`: add `.claude/.freeze*`.

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
