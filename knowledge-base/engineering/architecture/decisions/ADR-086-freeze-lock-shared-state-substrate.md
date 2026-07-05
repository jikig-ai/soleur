# ADR-086: Freeze edit-lock — one cross-harness state substrate, fail-open on read / fail-closed on enforce

- **Status:** Accepted
- **Date:** 2026-07-05
- **Issue:** [#5988](https://github.com/jikig-ai/soleur/issues/5988) (gstack-capability-adoption epic [#5983](https://github.com/jikig-ai/soleur/issues/5983), Wave 2 · FR5)
- **Relationship to the PreToolUse Guards pattern:** the `freeze` edit-lock is a routine extension of the modeled `platform.engine.hooks` container (C4 `model.c4` "Hook Engine", technology "PreToolUse Guards"). It is the *same class* as the shipped `worktree-write-guard.sh` fail-closed edit-guard — it does NOT reverse it. This ADR does **not** record the guard's existence (that is routine); it records the two decisions the guard's new **mutable, cross-harness control-plane state substrate** forced, which prior edit-guards (all stateless, derived from git) never had.

## Context

The `freeze` capability (`.claude/hooks/lib/freeze-lock.sh` + the `guardrails:freeze-edit-lock` branch) lets an operator or agent scope every file-editing tool call to a single allowed path prefix. Unlike `worktree-write-guard.sh` (stateless — it derives its decision from `git worktree list`), freeze needs **persistent runtime state**: a single line at `<repo-root>/.claude/.freeze-lock` holding the active allowed prefix, mutated via `freeze-lock.sh {set|clear}`.

Two design questions had no precedent in the existing (stateless) guard corpus:

1. **One shared freeze state, or one per harness?** The repo runs guards under two harnesses — Claude Code (`.claude/hooks/`, `Write|Edit|MultiEdit|NotebookEdit` matchers) and OpenHands (`.openhands/hooks/`, `file_editor` matcher). Each mirror could own its own state file, or both could read one.

2. **What is the failure posture of a corrupt/absent state read vs. an in-freeze enforcement decision?** A parse bug in the reader must not become a session-wide outage; but an active, well-formed freeze must actually deny.

## Decision

1. **One shared freeze state across both harnesses.** `freeze-lock.sh` resolves the state file from its OWN `BASH_SOURCE` (three dirs up from `.claude/hooks/lib/` = repo root), so it returns the same `<repo-root>/.claude/.freeze-lock` regardless of caller. The OpenHands mirror **cross-tree-sources** the canonical `.claude/hooks/lib/freeze-lock.sh` (`../../.claude/hooks/lib/freeze-lock.sh`) rather than owning a second state file. Rationale: a freeze is a property of the **working tree** ("edits restricted to X"), not of the harness. Per-harness state would let an operator bypass a safety lock by switching harness — strictly worse for a lock. The state file is gitignored runtime state (`.claude/.freeze*`, mirroring the `.rule-incidents*` precedent), never committed.

2. **Fail-OPEN on read, fail-CLOSED on enforce (two-tier).** `freeze_active_prefix` echoes nothing — i.e. *no active freeze* — on any absent / empty / multi-line / non-absolute / whitespace-or-CRLF-malformed state (OQ2 blast-radius: a corrupt state file, or a missing/broken helper, must NEVER brick every edit). Only a single well-formed absolute-path line activates enforcement, and within an active freeze the out-of-prefix decision is fail-CLOSED (deny). The safety-critical delete/commit/stash guards are deliberately **decoupled** from freeze availability: the helper is sourced fail-soft (`|| true`) and the freeze branch is additionally gated on `declare -f freeze_active_prefix`, so a missing/broken freeze helper degrades to "no freeze," never to a disarmed delete guard.

## Consequences

- **Positive:** a single lock an agent freezes/clears exactly as an operator does (agent-native, AP-004); consistent enforcement across harnesses; no split-brain state; a corrupt state file is inert, not catastrophic.
- **Negative / accepted:** the shared substrate lives under one harness's tree (`.claude/hooks/lib/`), making `.openhands` a *soft* dependency on `.claude` (mitigated by the fail-soft source + the canonical/mirror convention already in place). If a third harness is ever added, promote `freeze-lock.sh` to a harness-neutral shared location rather than adding a second cross-tree reach-in.
- The mirror pair has **no automated parity test** by convention; `tests/hooks/test_openhands_guardrails.sh` (added with this ADR) smoke-tests the OpenHands port's deny protocol, delete guard, and freeze branch so a break in the cross-tree source or `deny()` wiring fails CI.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| **Per-harness freeze state** (each mirror owns its file) | A lock a user can bypass by switching harness is not a lock; the freeze semantic is working-tree-scoped, not harness-scoped. |
| **Fail-closed on a malformed read** | A parse bug would deny *every* edit for the session (single-user brick) — the exact OQ2 blast-radius the two-tier posture exists to prevent. |
| **Freeze as a separate hook file** (not in `guardrails.sh`) | Issue + TR3 name `guardrails.sh`; brainstorm D6 bundles both capabilities into one file to avoid two conflicting rewrites. The multi-tool (Bash + edit) hook is precedented by `no-memory-write.sh` / `kb-domain-allowlist-guard.sh`. |
| **No ADR** (treat as routine guard extension) | Correct for the guard mechanics, but the mutable cross-harness state substrate + the fail-open/fail-closed tiering are durable decisions future readers will want traced — comparable granularity to ADR-070 (two-tier fail-open tool-scoping) and ADR-081 (config-lock substrate). |
