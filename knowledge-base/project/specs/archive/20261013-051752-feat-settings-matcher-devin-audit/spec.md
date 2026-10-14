---
feature: settings-matcher-devin-audit
issue: 8205
branch: feat-settings-matcher-devin-audit
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-15-settings-matcher-devin-audit-brainstorm.md
created: 2026-09-15
---

# Feature: Audit `.claude/settings.json` tool-name matchers — dead under Devin CLI

## Problem Statement

Devin CLI loads `.claude/settings.json` hooks (and `.devin/config.json`) but its shell tool_name is `exec`, not `Bash`. The repo's 22 `Bash` matcher objects (covering 23 hook registrations — credential guards, secret scans, prod-write deferral, ship gates) are dead under Devin: loaded, but never dispatched. The same defect class covers Write-family matchers, `AskUserQuestion`, `permissions.allow/deny` tool prefixes, and ~10 in-body `tool_name == "Bash"` gates that would still no-op even if the matcher fired. Meanwhile `.devin/config.json` partially binds `guardrails.sh`, producing cross-registry double-fire risk, and the Grok-added lowercase `write` twins over-bind `todo_write`. A published doc (`devin/INSTRUCTIONS.md:91`) asserts a credential-guard control that does not exist on Devin.

## Goals

- A checked-in per-hook disposition matrix (hook → per-harness disposition: bind / register in `.devin/config.json` / documented skip with reason) covering every tool-name matcher in every registry plus `permissions.allow/deny`.
- `.devin/config.json` expanded to the triaged Devin subset with anchored matchers; coincidental settings.json twins reconciled (anchor `write` → `^write$`) so nothing double-fires or over-binds.
- In-body `tool_name` gates normalized through a single mapping point (`hook-input.sh` tool-kind canonicalization).
- Executable parity test asserting the disposition matrix, with non-vacuity controls; the four coupled gates (`hookeventname-coverage`, `hook-input-contract` A9, `ship-unpushed-commits-gate` ordering check, `settings-hook-exec-bit`) updated in the same PR.
- Doc corrections: `INSTRUCTIONS.md` credential-guard claim; ADR-213 addendum; PA-8/PA-31 dated scope clarification (conditioned on merge); `compliance-posture.md` dead-window note.
- Flag the `browser-snapshot-credential-guard.sh:90` body gap to PR #8155.

## Non-Goals

- Devin Cloud sessions — measured to dispatch no repo-level hooks at all (#8159's capability matrix covers the disclosure; cloud hook support is a separate follow-up).
- Devin→Cognition transcript-path measurement (tracked via #8119's re-attestation trigger; filed as deferred issue).
- Mechanical sweep without per-hook review — explicitly rejected by #8205 and by this spec.
- Grok/Codex/OpenHands matcher changes beyond what the parity test requires.

## Functional Requirements

### FR1: Disposition matrix

A checked-in table enumerating every registry entry (settings.json PreToolUse/PostToolUse/SessionStart, plugin hooks.json, `.devin/config.json`) with columns: hook, current matcher, in-body gate, Devin tool analog, disposition (bind / devin-registry / skip `reason=no-tool`), and evidence.

### FR2: `.devin/config.json` expansion

For each hook dispositioned "bind", register it under the anchored Devin matcher (`^exec$`, `^(write|edit|multi_edit|notebook_edit)$`, etc.) using `$(git rev-parse --show-toplevel)`-anchored commands. Remove/anchor settings.json entries that would double-fire.

### FR3: In-body gate normalization

`hook-input.sh` exports a canonical tool-kind mapping; each of the ~10 in-body `tool_name` gates is rewritten to consume it, per-hook, with the hook's own test extended.

### FR4: Permissions audit

Document `permissions.allow`/`deny` tool-prefix disposition under Devin; rewrite to Devin's syntax if the platform supports repo-level permission rules, else record `reason=no-analog`.

### FR5: Parity contract test

Test asserts: every hook has a declared disposition; every "bind" disposition has a registry entry whose matcher regex-evaluates true on the Devin tool name; no hook is bound in two registries for the same Devin tool name; `write` matchers are anchored. Regex-evaluating assertions per the #8155 `test($m)` pattern.

## Technical Requirements

### TR1: Empirical envelope capture first

Before finalizing bind dispositions, capture a real Devin `exec`/`write`/`edit` PreToolUse envelope (stub hook + fresh child session, per the 2026-05-10 hook-input-shape learning) and verify `.tool_input.command`/`.tool_input.file_path`/`CLAUDE_PROJECT_DIR`. Dispositions citing envelope fields must cite the measured shape.

### TR2: No regression of Claude behavior

Every change must keep Claude-side matcher semantics identical; the four coupled test files updated deliberately (not worked around).

### TR3: Sequencing

Separate PR after #8155 merges; comment the body-check gap on #8155 before this PR opens.

### TR4: Fail-closed posture

Safety-class hooks (credential guard, secret scans, prod-write deferral, doppler redirect) get "bind" dispositions by default per ADR-089's third-harness clause; skips require per-hook reasons.
