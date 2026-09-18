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

- Recommend a fresh session only when the evidence says so (FR2's rule), delivered at the next phase boundary, never mid-`one-shot`.
- After every compaction, re-prime the model with a re-read directive naming the branch and plan path.
- Make the compaction summary preserve the identifiers a resume depends on (branch, worktree, PR/issue, plan path, unchecked ACs, operator holds, file paths).
- Ship in `plugins/soleur/hooks/hooks.json` so marketplace installs get it, without affecting a non-Soleur repo.
- *(Deleted at review: "keep `session-state.md` never older than the last compaction" — see #8328.)*

> **Revised 2026-09-18 (second revision) after the Phase 0 payload probe.** The probe falsified
> the mechanism this spec was written around. At `SessionStart:compact` the just-fired
> compaction's `compact_boundary` is **not yet on disk** (measured twice: 0-of-1, then 1-of-2),
> and the `SessionStart` envelope carries no `trigger`, so the transcript can supply neither the
> count nor the current trigger at the moment they are needed. `PreCompact` also fires on
> **no-op** compactions (3 fires, 2 boundaries), so counting those over-counts. What ships is the
> plan's pre-authorized `TMPDIR` ledger, corrected to **pending-then-commit**, with the
> `SessionStart` matcher widened to `startup|resume|clear|compact` so the window reset is exact.
> Full measurements: the plan's `## Addendum — 2026-09-18`. The FR/TR text below is corrected in
> place; where this spec and the plan's addendum disagree, the addendum wins.

> **Revised 2026-09-18 after a six-agent plan review.** Four mechanisms in the original spec are **deleted**: the `PostCompact` checkpoint writer + its gitleaks guard (FR4/TR6's guard — deferred to **#8328**), the token-ratio clause in FR2, the phase-derivation mechanism in FR1, and the `one-shot` Step 8 edit in FR5. The canonical scope is the plan's `## Review Cuts` section; where this spec and the plan disagree, the plan wins.

## Non-Goals

- **NG1.** No telemetry leaving the machine. A local-ledger `SOLEUR_COMPACTION` metric is a deferred follow-up.
- **NG2.** No Devin/Grok/Codex compaction hooks — documented as a Claude-only capability with honest degradation.
- **NG3.** No blocking of compaction (`PreCompact` never exits 2).
- **NG4.** No user-facing setting; thresholds are `SOLEUR_COMPACTION_*` env overrides.
- **NG5.** No transcript prose, `compact_summary` prose, user prompts, or `tool_result` bodies ever written to a tracked file.
- **NG6.** No changes to the SOC 2 session-manifest schema or `session-rules-loader.sh`.
- **NG7 (added at review).** No `PostCompact` binding ships in this slice — the checkpoint writer is #8328.
- **NG8 (added at review).** No token-ratio heuristic; the rule is a single integer count.
- **NG9 (added at review).** No phase derivation from transcript `Skill` records.

## Functional Requirements

### FR1: Post-compaction directive (`SessionStart`, matcher `startup|resume|clear|compact`)

`compaction-state.sh` derives `count_auto` and the current compaction's `trigger` from a
**per-session ledger under `TMPDIR`**, written by the same hook across its two bindings
(pending-then-commit; see the second revision note above). It does **not** read them from the
transcript — measured, the transcript answers too late. The non-`compact` arm of the
`SessionStart` matcher resets that ledger, which is what makes TR2's window scoping exact.
The transcript is read once, for a single corroboration field (`prior_boundaries`), which does
not feed the rule. Token counts are not reported: `preTokens`/`postTokens` on disk belong to the
*previous* compaction. It emits `hookSpecificOutput.additionalContext` (truncated at 8,000 chars, under the 10,000 cap) containing: compaction number, trigger, branch, plan path, the `claude --version` string, the re-read directive (`hr-always-read-a-file-before-editing-it`), and the `SOLEUR_COMPACTION_*` marker. stdout carries the JSON envelope and nothing else. **Phase derivation was deleted at review** — the last `Skill` record is not the current phase (measured: `soleur:preflight`), and inside `/soleur:one-shot` it is the child skill.

### FR2: Fresh-session recommendation *(revised — ratio clause deleted)*

When `trigger == auto` AND `count_auto >= SOLEUR_COMPACTION_COUNT_THRESHOLD` (default 2), with `count_auto` scoped to the current session window rather than all-time (boundaries accumulate across `--resume`), FR1's directive additionally instructs: at the next phase boundary, emit the resume prompt per `wg-end-of-work-emit-resume-prompt` and recommend continuing in a fresh session; inside `/soleur:one-shot`, never pause — carry the recommendation into the final resume prompt. Manual compaction never satisfies the rule.

### FR3: Summary shaping (`PreCompact`, matcher `manual|auto`)

Plain-text stdout instructing the summarizer to preserve verbatim: branch, worktree path, PR #, issue #, plan path, active skill/phase, unchecked acceptance criteria, `## Operator Holds`, all file paths mentioned. Paths only, never file bodies. Exit 0 always.

### FR4: Checkpoint — **DELETED at review, deferred to #8328**

Nothing reads `session-state.md` on resume (`work/SKILL.md` Phase 0 loads `constitution.md`, `tasks.md`, `spec.md` only), and `one-shot/SKILL.md` writes that file from a whole-file template that would destroy any hook-owned block. Original text retained below for #8328's benefit.

<details><summary>Original FR4 (not implemented)</summary>

### FR4 (original): Checkpoint (`PostCompact`, matcher `manual|auto`)

Writes/replaces a `<!-- compaction-checkpoint:start -->…<!-- compaction-checkpoint:end -->` block in `knowledge-base/project/specs/<branch>/session-state.md` (creating the file if absent, inside a git worktree only) containing allowlisted fields: branch, worktree path, PR #, issue #, plan path, phase, compaction count, last `compactMetadata`, ISO timestamp, provenance comment. Runs gitleaks (`.gitleaks.toml`) on the rendered block before writing; refuses on a hit, warns to stderr if gitleaks is absent and skips the write. All other sections of the file are untouched.

</details>

### FR7 (added at review): Transcript-format drift canary

A scheduled script reads the operator's **real** `~/.claude/projects/**/*.jsonl` and asserts at least one `"subtype":"compact_boundary"` across N recent transcripts. Synthesized fixtures pin the shape Soleur wrote, not the shape Claude Code emits, so they structurally cannot detect an upstream rename; this is the only mechanism that can see such a rename. Its value is narrower than an earlier draft claimed, and the correction is load-bearing: since `count_auto` and `trigger` come from the ledger, a rename degrades only the `prior_boundaries` marker. The canary reports that the recorded measurements have gone **stale**, not that the feature has stopped working. Every marker also carries the `claude --version` string so drift is attributable to a CLI bump.

### FR5: Prose retirement

`plan/SKILL.md` "run `/clear` before `/soleur:work`" and `work/SKILL.md` "Tip: after shipping run `/clear`" become conditional: "if a compaction directive recommended a fresh session, …". `one-shot/SKILL.md` gains one line: carry any fresh-session recommendation into the final resume prompt.

### FR6: Harness documentation

`plugins/soleur/devin/INSTRUCTIONS.md` and `codex/INSTRUCTIONS.md` state the degradation: no compaction hooks fire; the skill-prose fallback applies. `lib/harness.ts` unchanged.

## Technical Requirements

- **TR1 (revised).** Scope guard is the `welcome-hook.sh` sentinel (a `plugins/soleur` directory check) **plus** a Soleur plan/spec artifact — never `git rev-parse --is-inside-work-tree`, which is true in every customer repo and would let `PreCompact` degrade a stranger's compaction summary.
- **TR2 (revised twice).** `count_auto` is scoped to the current session window. Boundaries accumulate within one transcript across `--resume`, which is why an all-time count is wrong; the scoping is implemented as a ledger **truncation** on any non-`compact` `SessionStart`, so it is exact rather than inferred from transcript positions.
- **TR3 (revised twice).** One script, `plugins/soleur/hooks/compaction-state.sh`, dispatching on `hook_event_name`; hooks.json binds it **twice** — `PreCompact` (matcher `manual|auto`) and `SessionStart` (matcher `startup|resume|clear|compact`, not `compact` alone: the other three sources are what reset the window). Bash + jq only, matching existing plugin hooks.
- **TR4 (revised).** Fail-open: no `set -e`, **`trap 'exit 0' ERR EXIT`** (the `EXIT` arm is load-bearing — `set -u` terminates without firing `ERR`), exit 0 on every path, `SOLEUR_DISABLE_COMPACTION_HOOKS=1` kill-switch; envelope built with `jq -n --arg`, with a static `printf`'d JSON literal when `jq` is unavailable; nothing read from the transcript is echoed raw.
- **TR5 (revised).** Transcript reads are cheap, not bounded: `grep -c` and `grep | tail -1` both scan to EOF, measured **~25 ms on 31 MB** (`tac` is slower — it buffers). The earlier "<200 ms" budget and the "bounded reads" framing are retracted.
- **TR6.** Empirical payload verification before implementation: capture real `PreCompact` and `SessionStart:compact` envelopes on CLI 2.1.273, record them dated in the hook header, and confirm whether the boundary count observed at `SessionStart:compact` includes the compaction that just fired (the load-bearing unknown).
- **TR7 (revised).** Tests: `plugins/soleur/test/compaction-state-hook.test.sh` (that path is globbed by `scripts/test-all.sh`; `plugins/soleur/hooks/` is not) with stdin fixtures for both events, 3 synthesized transcript fixtures (`cq-test-fixtures-synthesized-only`), the threshold boundary cases, the scope-guard case, the `jq`-absent case, and the 8k cap. The hooks.json binding assertion lives here, not in `components.test.ts` (which does not read `hooks.json`).
- **TR8 (revised).** ADR-227: "The compaction signal is read from the transcript, not from a counter file", recording all seven alternatives including the checkpoint writer deleted at review (#8328).
- **TR9 (added at review, corrected at implementation).** A drift canary (FR7), never a suite case — a suite case would break CI on a clean box. It is **not** a GitHub Actions schedule either: measured, a runner has no `~/.claude/projects`, so that registration yields a probe that can only ever report TRANSIENT. It is bound to the repo-side `SessionStart` surface (`.claude/hooks/compaction-drift-canary.sh`), stamp-gated to once per 7 days, always exit 0.

## Success Criteria

- SC1. On a session with 0 compactions, no `/clear` nudge is emitted at `plan`/`work` end.
- SC2. On the 2nd auto-compaction, the next phase boundary emits a resume prompt with branch/worktree/PR/issue/plan path and the fresh-session recommendation.
- SC3. In a git repo with no `plugins/soleur` directory, both events emit nothing — a non-Soleur user's compaction summary is never touched.
- SC4. On every `SessionStart` fixture, stdout parses as JSON in full, including the failure paths.
- SC5. Hook script exits 0 on malformed stdin, missing transcript, non-Soleur repo, kill-switch, and a `set -u` unbound-variable fault.
- SC6. The drift canary exits non-zero when zero `compact_boundary` records are found across N recent **real** transcripts, and exits 2 — not 1 — when it cannot measure at all, so "could not check" never renders as "bad".
- SC7 (added at implementation). A `PreCompact` that is never followed by a `SessionStart:compact` contributes nothing to `count_auto`. This is the measured no-op-compaction case; without it the recommendation fires one compaction early.
- *(SC on the checkpoint block moved to #8328 with the writer.)*
