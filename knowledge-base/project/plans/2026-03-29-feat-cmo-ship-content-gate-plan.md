# feat: CMO Ship Content Gate Multi-Signal Trigger + Plan Domain Assessment

**Issue:** #1265
**Branch:** cmo-ship-content-gate
**Spec:** [spec.md](../specs/feat-cmo-ship-content-gate/spec.md)
**Brainstorm:** [2026-03-29-cmo-ship-content-gate-brainstorm.md](../brainstorms/2026-03-29-cmo-ship-content-gate-brainstorm.md)

## Problem

PR #1256 (PWA) shipped as a Phase 1 milestone feature without content consideration because:

1. Ship Phase 5.5 CMO gate uses file-path-only triggers — PWA only touched `apps/web-platform/`, so the gate never fired
2. The CMO assessment question in `brainstorm-domain-config.md` doesn't mention "new product features" or "feature launches" — so plan Phase 2.5 domain sweeps also miss PWA-type features

## Changes

### 1. Ship SKILL.md — Phase 5.5 CMO Content-Opportunity Gate

**File:** `plugins/soleur/skills/ship/SKILL.md`

**a)** Fix intro text (line 249): "two conditional gates" → "three conditional gates" (pre-existing bug — three gates already exist).

**b)** Replace trigger (line 253) with expanded OR-list:

> **Trigger:** PR matches ANY of: (a) touches files in `knowledge-base/product/research/`, `knowledge-base/marketing/`, or adds new workflow patterns (new AGENTS.md rules, new skill phases); (b) has a `semver:minor` or `semver:major` label; (c) title matches `^feat(\(.*\))?:` pattern.

**c)** Replace detection (line 255) to include label/title checks:

> **Detection:** Run `git diff --name-only origin/main...HEAD` and check file paths against trigger (a). Run `gh pr view --json labels,title` and check against triggers (b) and (c). If any trigger matches, proceed to "If triggered."

The existing "If triggered" section (lines 257-265) stays unchanged — the CMO agent already has the judgment to say "no content opportunity" for false positives.

### 2. brainstorm-domain-config.md — CMO Assessment Question

**File:** `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` (line 7)

Add to end of CMO Assessment Question: ", or new user-facing product capabilities that could warrant content amplification or feature announcements?"

### 3. AGENTS.md — Phase 5.5 Rule Update

**File:** `AGENTS.md` (line 29)

Change:

> triggers when PRs touch `knowledge-base/product/research/`, `knowledge-base/marketing/`, or add new workflow patterns

To:

> triggers on file-path matches (`knowledge-base/product/research/`, `knowledge-base/marketing/`, new workflow patterns) or feature signals (`semver:minor`/`major` label, `feat:` title)

## Acceptance Criteria

- [x] Phase 5.5 CMO gate fires on `semver:minor`/`major` labels and `feat:` titles
- [x] CMO produces content brief + updates `content-strategy.md` immediately (existing behavior, unchanged)
- [x] "Skip for code-only PRs, bug fixes, and pure infrastructure changes" removed
- [x] CMO assessment question in domain config includes "new user-facing product capabilities"
- [x] AGENTS.md Phase 5.5 description reflects new trigger conditions
- [x] Intro text says "three" not "two" conditional gates

## Test Scenarios

**Scenario 1 — PWA-like feature PR (should fire):** PR with `semver:minor` label and `feat(web-platform): ...` title, only touching `apps/web-platform/`. File paths don't match, but `semver:minor` label triggers CMO → CMO assesses content opportunity.

**Scenario 2 — Patch bug fix (should not fire):** PR with `semver:patch` label and `fix: ...` title. No file-path match, no `semver:minor`/`major`, no `feat:` title → gate does not fire.

**Scenario 3 — Marketing file change:** PR touching `knowledge-base/marketing/content-strategy.md`. File path matches → fire CMO.

**Scenario 4 — Plan without brainstorm:** `/plan` runs directly from issue. Phase 2.5 fresh domain sweep with updated CMO assessment question → CMO flagged as relevant for product features.

## Domain Review

**Domains relevant:** Marketing

### Marketing (CMO)

**Status:** reviewed (carried forward from brainstorm)
**Assessment:** PWA has high content potential. Root cause is file-path-only trigger. All needed agents already exist — no capability gaps.

## Plan Review

**Reviewers:** DHH, Kieran, Code Simplicity (run 2026-03-29)

**Consensus:** Original plan was overengineered (two-tier system, skip conditions, embedded LLM evaluation prompt). Simplified to flat OR-list of trigger conditions. The CMO agent already handles "no content opportunity" responses — no need for a pre-evaluation step.

**Applied:** All reviewer feedback incorporated. ~5 lines of diff across 3 files.
