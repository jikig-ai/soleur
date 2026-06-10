# ADR-051: Per-call model tiering for workflow subagent spawns

- **Status:** Accepted
- **Date:** 2026-06-10
- **Issue:** #3791 (re-opened by the Fable 5 pricing trigger; deferred 2026-05-15)
- **Supersedes (partially):** the "no exceptions" clause of the Model Selection Policy (PR #295, 2026-02-25) — frontmatter inheritance is unchanged; the workflow call-site tier is new.

## Context

Fable 5 prices at $10/$50 per MTok — 2× Opus 4.8, 3.3× Sonnet 4.6, 10× Haiku 4.5. All 66 plugin agents use `model: inherit` and no workflow script passed `opts.model`, so a Fable 5 session ran every mechanical subagent step (diff classification, GitHub-issue filing, comment fetching, commit-message generation, report assembly) at top-tier rates. Anthropic's agent-design guidance endorses cheaper-model subagents for sub-tasks, and the web platform already tiers in production (Sonnet crons, Haiku routing, deliberate sonnet→opus upgrades for scoring workloads).

## Decision

1. **Frontmatter stays `inherit` for all agents** (operator session-model agency preserved; overrides still need written justification).
2. **Workflow scripts MAY pin `opts.model` at mechanical steps only** — 12 allowlisted call sites at adoption (see `plugins/soleur/test/workflow-model-pins.test.ts`, the mechanical gate). Each pin carries a one-line justification comment. Pin style is single-quoted inline literals (`model: 'sonnet'`) — workflow scripts are self-contained by design, so no shared map or import.
3. **Never-downgrade exemption list** (judgment paths): review dimensions, verify/concur adjudication, synthesis/merge, resolvers/implementers, per-cluster `one-shot`, `agent-native-audit` enumeration scoring, plan-review reviewers/consolidate, deepen-plan research/merge, `resolve-parallel` `plan`. Changing the allowlist is a clo-attestation-class change.

## Semantics

- **Pins are absolute, not session-relative.** A pinned step always runs the pinned tier. Consequence: a pin can run ABOVE a cheaper session (Haiku session + `sonnet` pin = Sonnet, a cost upgrade over the operator's chosen tier). The per-run tier `log()` line in each pinned workflow is the disclosure. Session-relative ("one tier below session") was rejected: the runtime only supports absolute values, and relative tiers make cost/quality non-deterministic per session.
- **No fallback on rejection.** If a pinned model is rejected/rate-limited, `agent()` returns null after retries; fan-outs `.filter(Boolean)`, single steps follow each workflow's existing null-handling (a failed `classify` aborts the review run — pre-existing behavior).

## Telemetry and verification (empirical findings, 2026-06-10 capture)

Phase 0 of the adoption PR captured ground truth with a one-spawn probe workflow:

1. **The PostToolUse `Task` hook does NOT fire for Workflow-runtime `agent()` spawns.** `.claude/.session-tokens.jsonl` (agent-token-tee, #3494) gains no row for workflow spawns; its coverage is direct Agent-tool spawns only. The tee hook's new `model` field (`.tool_input.model // "inherit"`) therefore attributes DIRECT spawns only.
2. **The executed model for workflow spawns IS recorded in the workflow run's transcript** — `<session-transcript-dir>/subagents/workflows/<run-id>/agent-<id>.jsonl` assistant messages carry `"model":"claude-haiku-4-5-20251001"` (probe evidence). This is execution-side evidence, stronger than request-side `tool_input.model`.
3. **Verification recipe (workflow pins):** after a run, `grep -ho '"model":"[^"]*"' <run-transcript-dir>/agent-*.jsonl | sort | uniq -c` — pinned spawns show the pinned tier's concrete ID; judgment spawns show the session model.
4. **Rejected-pin signature:** for direct spawns, absence-of-row (the tee hook drops zero-token envelopes), never `model:"inherit"`; for workflow spawns, the workflow's own null-handling log line.

## Pin-surface lifecycle (three surfaces age differently)

| Surface | Form | At model deprecation |
|---|---|---|
| Plugin workflow pins | harness enum alias (`'sonnet'`, `'haiku'`) | Zero repo maintenance — but subject to **silent retargeting**: the harness re-aiming an alias to a successor generation changes every pin's cost/behavior contract with no repo diff and no CI signal. The transcript grep (above) is the only way to observe which concrete model an alias resolved to. |
| CI pins (`claude_args: '--model claude-sonnet-4-6'`) | concrete ID | Hard-fails loudly (404) at retirement; re-pin is a one-line edit + action-pin sync (learning 2026-04-18). |
| Inngest cron constants (web platform) | concrete IDs, partly dated | Hard-fail loudly; registry consolidation deferred to #5106. |

#5100 (`model-launch-review` skill) is the re-pin trigger for all three surfaces at each model release.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Frontmatter tiering (pin research agents to `sonnet`) | Context-blind (applies in every spawn context), silently upgrades cheap sessions, re-fights the deliberate 2026-02-24 reversal of the one prior tiering attempt |
| Session-relative tiers ("one below session") | Runtime supports absolute values only; non-deterministic cost contract |
| `TIER_PINS` per-workflow map (single source for pins + disclosure log) | Contradicted the allowlist-test/grep gates (map reference vs inline literal); deleted at 5-agent plan review — inline literals + adjacent log line + the standing allowlist test cover the same drift risk mechanically |
| Tee-hook-only telemetry attribution | Empirically impossible for workflow spawns (finding 1 above) |

## Consequences

- BYOK operators save ~65-80% per mechanical fan-out run (CFO estimate); flat-rate operators gain quota headroom.
- The review layer (never pinned) remains the quality safety net for the execution layer — the brand-survival invariant at `single-user incident` threshold.
- The allowlist test converts the prose never-downgrade policy into a CI-blocking gate.
