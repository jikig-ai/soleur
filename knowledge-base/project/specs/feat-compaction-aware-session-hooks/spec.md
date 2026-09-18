---
feature: compaction-aware-session-hooks
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-18-compaction-aware-session-hooks-brainstorm.md
branch: feat-compaction-aware-session-hooks
---

# Feature: Compaction-Aware Session Hooks

## Problem Statement

Soleur tells the operator to "run `/clear` and resume" at fixed points (`plan` end, `work` end) regardless of whether context compaction ever happened. On a 1M-context session with zero compactions the nudge is noise; on a session that auto-compacted twice mid-`/work` it arrives too late, after the model has already lost branch/PR/plan state. Claude Code 2.1.76+ exposes the compaction lifecycle (`PreCompact`, `PostCompact`, `SessionStart` matcher `compact`), and the session transcript records every compaction with exact token counts. Nothing in the plugin uses any of it.

## Goals

- Recommend a fresh session only when the evidence says so (Key Decision 1 rule), delivered at the next phase boundary, never mid-`one-shot`.
- After every compaction, re-prime the model with the phase-specific re-read directive and a refreshed resume prompt.
- Make the compaction summary preserve the identifiers a resume depends on (branch, worktree, PR/issue, plan path, phase, unchecked ACs, operator holds, file paths).
- Keep `session-state.md` never older than the last compaction, with zero secret/PII risk.
- Ship in `plugins/soleur/hooks/hooks.json` so marketplace installs get it.

## Non-Goals

- **NG1.** No telemetry leaving the machine. A local-ledger `SOLEUR_COMPACTION` metric is a deferred follow-up.
- **NG2.** No Devin/Grok/Codex compaction hooks — documented as a Claude-only capability with honest degradation.
- **NG3.** No blocking of compaction (`PreCompact` never exits 2).
- **NG4.** No user-facing setting; thresholds are `SOLEUR_COMPACTION_*` env overrides.
- **NG5.** No transcript prose, `compact_summary` prose, user prompts, or `tool_result` bodies ever written to a tracked file.
- **NG6.** No changes to the SOC 2 session-manifest schema or `session-rules-loader.sh`.

## Functional Requirements

### FR1: Post-compaction directive (`SessionStart`, matcher `compact`)

`compaction-state.sh` reads the envelope's `transcript_path`, derives `count` (number of `compact_boundary` records), the last record's `compactMetadata.{trigger,preTokens,postTokens}`, and the current phase (last `soleur:*` Skill invocation in the transcript → phase via the same mapping as `.claude/phase-surface-map.json`, shipped plugin-side). It emits `hookSpecificOutput.additionalContext` (≤10,000 chars) containing: compaction number + trigger + token delta, branch, worktree path, current phase, the re-read directive (plan path, `session-state.md`, `hr-always-read-a-file-before-editing-it`), and an instruction to refresh the resume prompt.

### FR2: Fresh-session recommendation

When `trigger == auto` AND (`count_auto >= SOLEUR_COMPACTION_COUNT_THRESHOLD` (default 2) OR `postTokens/preTokens > SOLEUR_COMPACTION_RATIO_THRESHOLD` (default 0.15)), FR1's directive additionally instructs: at the next phase boundary, emit the resume prompt per `wg-end-of-work-emit-resume-prompt` and recommend continuing in a fresh session; inside `/soleur:one-shot`, never pause — carry the recommendation into the final resume prompt. Manual compaction never satisfies the rule.

### FR3: Summary shaping (`PreCompact`, matcher `manual|auto`)

Plain-text stdout instructing the summarizer to preserve verbatim: branch, worktree path, PR #, issue #, plan path, active skill/phase, unchecked acceptance criteria, `## Operator Holds`, all file paths mentioned. Paths only, never file bodies. Exit 0 always.

### FR4: Checkpoint (`PostCompact`, matcher `manual|auto`)

Writes/replaces a `<!-- compaction-checkpoint:start -->…<!-- compaction-checkpoint:end -->` block in `knowledge-base/project/specs/<branch>/session-state.md` (creating the file if absent, inside a git worktree only) containing allowlisted fields: branch, worktree path, PR #, issue #, plan path, phase, compaction count, last `compactMetadata`, ISO timestamp, provenance comment. Runs gitleaks (`.gitleaks.toml`) on the rendered block before writing; refuses on a hit, warns to stderr if gitleaks is absent and skips the write. All other sections of the file are untouched.

### FR5: Prose retirement

`plan/SKILL.md` "run `/clear` before `/soleur:work`" and `work/SKILL.md` "Tip: after shipping run `/clear`" become conditional: "if a compaction directive recommended a fresh session, …". `one-shot/SKILL.md` gains one line: carry any fresh-session recommendation into the final resume prompt.

### FR6: Harness documentation

`plugins/soleur/devin/INSTRUCTIONS.md` and `codex/INSTRUCTIONS.md` state the degradation: no compaction hooks fire; the skill-prose fallback applies. `lib/harness.ts` unchanged.

## Technical Requirements

- **TR1.** One script, `plugins/soleur/scripts/compaction-state.sh`, dispatching on `hook_event_name`; hooks.json binds it three times. Bash + jq only (no Python), matching existing plugin hooks.
- **TR2.** Fail-open: no `set -e`, `trap 'exit 0' ERR`, exit 0 on every path, `SOLEUR_DISABLE_COMPACTION_HOOKS=1` kill-switch, scope-guard `git rev-parse --is-inside-work-tree`; envelope built with `jq -n --arg`; nothing read from the transcript is echoed raw (per-key control-char clamp).
- **TR3.** Bounded transcript reads only: `grep -c`/`grep | tail -1` on the JSONL; never load the file. Budget: <200 ms on a 30 MB transcript (measure, record in the test).
- **TR4.** Empirical payload verification before implementation: capture real `PreCompact`, `PostCompact`, and `SessionStart:compact` envelopes on CLI 2.1.273 (one forced `/compact`), record them dated in the hook header (learning 2026-05-10 pattern), and confirm `SessionStart:compact` fires on `auto` compaction (Open Question 1).
- **TR5.** Ordering probe: both `PostCompact` and `SessionStart:compact` log a timestamp on the same forced compaction; FR4 is sequenced after the result is recorded in the plan.
- **TR6.** Tests: `plugins/soleur/hooks/compaction-state.test.sh` with stdin fixtures for all three events, a synthetic transcript fixture (`cq-test-fixtures-synthesized-only`), the threshold boundary cases, the gitleaks refusal path, the missing-gitleaks warn path, and the ≤10k-char cap; a `components.test.ts` case asserting hooks.json binds the three events to the script; `settings-hook-exec-bit`-style mode check.
- **TR7.** `/soleur:gdpr-gate` run manually on FR4's writer at plan Phase 2.7 (path regex does not cover `plugins/soleur/hooks/**`).
- **TR8.** ADR: "Stateless compaction signal from the transcript; PostCompact writes only allowlisted checkpoint fields" (`/soleur:architecture create`).

## Success Criteria

- SC1. On a session with 0 compactions, no `/clear` nudge is emitted at `plan`/`work` end.
- SC2. On the 2nd auto-compaction, the next phase boundary emits a resume prompt with branch/worktree/PR/issue/plan path and the fresh-session recommendation.
- SC3. After any compaction, `session-state.md` carries a checkpoint block whose timestamp is newer than the last `compact_boundary`.
- SC4. gitleaks on the rendered checkpoint block is part of the test suite and a seeded fake secret is refused.
- SC5. Hook script exits 0 on malformed stdin, missing transcript, non-git CWD, and kill-switch.
