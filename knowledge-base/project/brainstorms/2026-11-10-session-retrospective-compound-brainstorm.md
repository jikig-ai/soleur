# Brainstorm: session-retrospective-compound

**Date:** 2026-11-10
**Issue:** #12532 (renamed from "degraded-run forensics mode for compound")
**Worktree:** feat-12532-degraded-run-forensics
**Draft PR:** #12565
**Lane:** cross-domain
**USER_BRAND_CRITICAL:** true (auto, per #5175)

## User-Brand Impact

- **Artifact:** the session-retrospective-compound skill and its forensic analysis agent (new component surface)
- **Vector:** worst-case data exposure / silent failure / trust breach for the named artifact — a retrospective that leaks prompt/secret content into proposals, or silently mutates skills without operator approval
- **Threshold:** single-user incident

## What We're Building

A new skill, `session-retrospective-compound`, that runs at session end (or at pipeline completion) and spawns a **fresh-context agent** to analyze the session's raw transcript. The agent produces:

1. **Workflow/agent/skill improvement proposals** — pending-operator review items (heal-skill approve-before-apply contract), never auto-applied.
2. **New-component proposals** — filed as GitHub issues labeled `forensics-proposal` for separate scoping and implementation.
3. **Learning captures** — compound-style institutional knowledge, but produced by a fresh context (not the executing context).
4. **Glossary entries** — sharpened term definitions (kb-glossary).
5. **Test additions** — for failures that lacked tests.

The skill replaces and supersedes the narrow "degraded-run forensics" scope originally filed as #12532. The broader vision: mine the full session transcript for institutional knowledge, structural improvements, operator guidance, and new component ideas — not just errors on degraded runs.

### Trigger (tiered, cross-harness)

- **Claude Code:** Stop hook (`hooks/stop-hook.sh`) auto-fires at true session end.
- **All harnesses:** Pipeline skills (one-shot, brainstorm→plan→work→review→ship) invoke it as their final step.
- **All harnesses:** Manual invocation (`/session-retrospective-compound`) anytime.

No deferred tracking, no stale-marker machinery — the retrospective either fires at exit/pipeline-completion or is invoked manually.

### Input & cost control

- **Two-tier trigger:** Every session end (or pipeline completion) runs a cheap triage agent (standard tier) that decides whether deep analysis is warranted (signals: errors, operator corrections, tool failures, abandoned approaches, long duration). Deep forensic analysis runs only if triage flags value.
- **Input:** Raw transcript for maximum signal fidelity (accepted because executing agents already saw the same data during the session).
- **Output:** Scrubbed by a fail-closed redaction gate before persistence (raw in, scrubbed out). Agent sees raw; proposals are scrubbed.

### Phased delivery

- **Phase 1 (#12532 narrow):** Degraded-run forensics — fresh-context agent + run-health ledger + pending-operator proposals on errored runs. Builds the forensic agent + approval infrastructure.
- **Phase 2 (broader):** Every session end (tiered trigger), raw transcript, workflow/agent/skill proposals + new-component issues + learnings/glossary/tests. Reuses Phase 1 infrastructure.

## Why This Approach

1. **Fresh context eliminates self-report bias.** `compound`'s Phase 0.5 exists because the executing context under-reports its own errors. A separate agent reading the raw transcript closes this loop.
2. **Tiered trigger bounds cost.** Raw transcripts are large; running deep analysis on every trivial session is wasteful. Cheap triage first, deep analysis only when warranted.
3. **Cross-harness honesty.** True auto end-of-session only works on Claude Code (Stop hook). Pipeline final-step + manual invocation covers all other harnesses without pretending parity.
4. **No deferred tracking.** By firing at exit or pipeline-completion (not deferring to next session), we avoid stale-marker machinery entirely.
5. **New components as issues, not in-session scaffolding.** Proposing new agents/skills is a commitment (README counts, tests, harness-parity census). Filing issues keeps them properly scoped.
6. **Raw in, scrubbed out.** Input fidelity is preserved (executing agents already saw raw data); output is scrubbed before persistence, addressing the new retention surface.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | New skill `session-retrospective-compound` (not a `compound` mode) | Discoverability; matches the "new skills" theme; cleaner surface |
| 2 | Tiered trigger: Stop hook (Claude Code) + pipeline final-step (all) + manual (all) | Honest cross-harness; no deferred tracking |
| 3 | Two-tier analysis: cheap triage first, deep only if flagged | Bounds cost while keeping "every session" contract |
| 4 | Raw transcript input, scrubbed output | Signal fidelity (agents already saw raw); output scrubbing addresses retention surface |
| 5 | All structural changes → pending-operator review items (heal-skill contract) | Never auto-apply, including under `--headless` |
| 6 | New agents/skills → `forensics-proposal`-labeled GitHub issues | Proper scoping; not implemented in-session |
| 7 | Scope includes learnings, glossary entries, test additions | Core value beyond error prevention |
| 8 | Per-session surfacing first; clustering/dedup deferred to Phase 2 | Measure noise before adding dedup machinery |
| 9 | Phased: Phase 1 = degraded-run forensics; Phase 2 = broader session-mining | Shippable Phase 1; Phase 2 reuses infrastructure |
| 10 | New label `forensics-proposal` for filed issues | Clean triage separation |
| 11 | Ad-hoc sessions on non-Claude-Code harnesses won't auto-trigger | Acceptable gap; manual invocation covers it |

## Open Questions

- **Triage threshold:** What signals definitively warrant deep analysis? Proposed: errors occurred, operator corrections, tool failures, abandoned approaches, session duration > N minutes. Needs calibration.
- **Redaction gate implementation:** Fail-closed scrubbing of proposals before persistence. Reuse existing secret-scanning/redaction infrastructure (ADR-095 pattern).
- **Proposal queue storage:** Where do pending-operator review items live? Markdown files? GitHub issues? Learning frontmatter? Must align with heal-skill's diff + approve flow and eval-harness gating.
- **Fresh-context agent identity:** New agent (e.g., `engineering/review/session-forensics-analyst`) or reuse an existing reviewer with a curated prompt? Model tier (ADR-053)?
- **Eval/validation:** How to measure that forensics proposals actually improve workflow/agent/skill quality? Link to eval-harness baselines.
- **Cost budget:** Per-session cap for triage + deep analysis. Circuit breaker if spend exceeds value.
- **Licensing:** AGPL-3.0 clean re-implementation (HephaestusNG). Confirm no source lifting; clean-room spec-driven implementation.
- **Cloud mode:** In cloud sessions (sequential fallback), does the retrospective still run? With what disclosure?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Self-report unreliability is the whole point — need sealed, append-only run-health artifacts. AGPL clean re-implementation required. Must carve out forensics proposals from compound's headless auto-promote path (never auto-apply). Hidden prerequisite: instrument one-shot/test-fix-loop to emit structured run-health artifacts first. Recommends two-stage: (a) instrument run-health emission, (b) then add forensic analysis.

### Product (CPO)

**Summary:** Internal tooling, not customer-facing. ~80% overlap with existing compound/heal-skill/eval-harness — two remaining mechanics must prove marginal value. No baseline measurement exists. Cost surface: fresh-context agent per session on already-expensive pipelines. Recommends: establish baseline + success metric + cost budget + redaction requirements before implementation; likely Post-MVP/Later milestone.

### Legal (CLO)

**Summary:** Prompts are unbounded PII/secrets vector. Staging to scratch dir creates retention + breach surface. Fresh-context agent = third-party processing scope change (Anthropic DPA). Prompt-rewrite proposals persist PII. Recommends invoking `soleur:gdpr-gate` at plan Phase 2.7 and work Phase 2 exit. Open questions: retention period, redaction gate, raw vs. minimised payload, access controls, DSAR/erasure coverage, Article 30 amendment.

### Marketing (CMO) — omitted with rationale

Operator-facing engineering capability (internal dev tooling). No public-facing messaging or GTM needed at brainstorm stage. CMO omitted per hr-new-skills-agents-or-user-facing.

## Capability Gaps

- **Run-health artifact emission in one-shot/test-fix-loop:** Neither skill currently emits a structured `run_health.json` or `phase_prompts/` snapshot. This is a hidden prerequisite for Phase 1 (degraded-run forensics). Evidence: issue #12532 CTO assessment; grep of `plugins/soleur/skills/one-shot/` and `plugins/soleur/skills/test-fix-loop/` for `run_health` / `phase_prompts` returned no matches.
- **Fail-closed redaction gate for proposal output:** Existing secret-scanning infrastructure (ADR-095 pattern) must be extended to scrub proposals before persistence. Evidence: CLO assessment identified this gap; no existing redaction gate covers free-form proposal text.
- **Cross-harness session-end trigger:** Only Claude Code has a Stop hook. Pipeline final-step invocation + manual fallback cover other harnesses, but there is no universal session-end mechanism. Evidence: harness INSTRUCTIONS.md (OpenCode: "no Stop hook"); go.md harness table.

## Non-Goals (Phase 1)

- Clustering/dedup across sessions (deferred to Phase 2)
- Auto-application of any proposal (always pending-operator)
- In-session scaffolding of new agents/skills (filed as issues instead)
- Real-time session-end firing on non-Claude-Code harnesses (pipeline final-step + manual only)