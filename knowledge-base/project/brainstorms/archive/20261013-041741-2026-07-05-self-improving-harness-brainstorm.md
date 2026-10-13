---
date: 2026-07-05
topic: Apply Self-Harness / HarnessX self-improving-harness techniques to Soleur — audit + close the weakness-mining gap
issue: 6037
deferred_issues: [6038, 6039]
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Self-Improving Harness — Audit + Close the Weakness-Mining Gap

## What We're Building

A **read-only weakness-miner**: a weekly cron that clusters Soleur's own execution-failure
signal (session-error learnings + raw `.claude/.rule-incidents.jsonl` telemetry) into a
**ranked "recurring failure pattern" digest**, which a human triages into the *existing*
`/compound` → `cron-compound-promote` → `eval-gate` pipeline.

This is **Layer 2 of the 2026-03-03 self-healing-workflow (#397), scoped to detection only** —
the one loop-stage that is still 100% human. **Zero mutation surface**: it emits signal, never
edits the harness. Auto-proposal (B) and the user-facing legibility changelog (C) are filed as
deferred follow-up issues.

Origin: the "Why self-improving harnesses are the next frontier" article (Self-Harness arXiv
2606.09498; HarnessX arXiv 2606.14249 — both verified real). The audit below shows Soleur already
implements ~70% of both frameworks.

## Why This Approach

**Soleur is not greenfield — it is open at exactly one place.** The gap audit:

| Loop stage | Soleur primitive | Status |
|---|---|---|
| Weakness mining | `every-session-error→learning` gate, `/compound`, `rule-metrics-aggregate.yml` | ⚠️ **Half-open — the gap.** Recurring-failure-pattern *clustering* is human-only. |
| Harness proposal | `cron-compound-promote.ts` (draft-PR auto-proposer, `enabled:false`) | ✅ Built, guardrailed (PR #3559). |
| Proposal validation | `eval-harness`, `eval-gate.cjs`, `gated-skills.json`, ADR-069 | ✅ Most-built stage. |
| Processor composability (HarnessX) | change-class `session-rules-loader.sh` + ToolSearch MCP deferral + L3 (#5768) | ✅ Typed fail-open router. Full AEGIS combo-search = over-engineering for markdown-scale. |

**Two hard findings that shaped the scope:**

1. **`rule-metrics.json` shows 97 rules with 0 fires over 8 weeks** — `.rule-incidents.jsonl`
   telemetry exists but is never read by automation. So *rule-fire counts are not a usable
   weakness signal today*; the miner's substrate must be the **session-error learnings corpus +
   raw incident telemetry**, and the all-zero-fires state is itself a broken-telemetry finding
   the digest should surface.
2. **The dangerous stage is the next one you'd automate: auto-editing AGENTS.md.** The eval-gate
   does NOT contain the worst failure — an edit that silently *narrows an `hr-*` guardrail* while
   still passing the eval (reward-hacking / Goodhart). Containment needs a **policy** (additive-
   only auto-flow; deletions/weakenings never auto-merge), not just the gate. Hence the first
   increment must have zero mutation surface. This is the article's "loopmaxxing" warning made
   concrete.

**Why A over B/C:** A closes the actual open stage with the lowest possible risk, reuses
everything downstream, and avoids the unguided-loop trap. B is the fuller Layer 2 but needs a new
ADR (auto-edit policy for hard rules) first. C is a product/CMO moat play, orthogonal to the gap.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Increment | **A — read-only weakness-miner**; B & C → deferred issues | Closes the one open loop-stage; zero mutation risk. |
| Mutation surface | **None** — emit ranked digest artifact only | Dodges the auto-edit reward-hacking failure mode entirely. |
| Weakness substrate | **session-error learnings corpus + raw `.rule-incidents.jsonl`** (NOT rule-fire counts) | Rule-fire counts are all-zero (broken telemetry); learnings corpus is the real failure record. |
| Clustering | Deterministic aggregation **+ one classification pass** | One bounded LLM pass, no inference loop. |
| Cadence | **Weekly cron** (extend `rule-metrics-aggregate` cadence, own workflow) | No hot-path write, no WAL cost. |
| Triage handoff | Human triages digest → existing `/compound` pipeline | Reuses the guardrailed promotion path; no new trust boundary. |
| Secondary output | Surface **unused-rule / obsolescence candidates** (97@0 fires) | Serves #397's deferred rule-retirement trigger cheaply. |
| Visual design | N/A — no UI surface (pure cron/CI/harness infra) | Phase 3.55 trigger boundary. |

## Open Questions (resolve at plan time)

- **Digest destination:** committed markdown artifact (like `rule-metrics.json`) vs. a GitHub
  issue opened weekly vs. a section in the operator-digest. Lean: committed artifact + link from
  operator-digest.
- **`.rule-incidents.jsonl` all-zero root cause:** is emit coverage broken, or are rules genuinely
  never firing? Miner should report the distinction, not silently treat zero as "healthy."
- **Clustering key:** what makes two session-errors "the same pattern" — error string, touched
  file/skill, rule-id, or LLM-judged theme? Start deterministic (file/skill + rule-id), add the
  single classification pass for theme.
- **Recurrence threshold:** #397 used "3+ similar." Re-confirm against current corpus volume
  (~3–5 learnings/week).
- **Reuse vs. new:** extend `scripts/rule-metrics-aggregate.sh` vs. a sibling `weakness-miner`
  script sharing the same weekly workflow. Lean: sibling script, shared workflow.

## User-Brand Impact

- **Artifact:** the weekly read-only weakness-miner digest (cron + aggregation script + digest
  artifact).
- **Vector:** a mis-clustered or hallucinated digest steers a human to promote a bad rule — but
  only *via* the existing human-gated `/compound` + eval-gate path, so the miner cannot itself
  mutate the harness or reach a user workspace.
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per #5175). The zero-mutation design is the primary control:
the miner emits signal only; every downstream edit still passes the battle-tested compound-promote
guardrails (target-path allowlist, hard-rule-removal block, byte-budget, PII filter) and eval-gate
regression. The one residual risk (misleading digest → bad human triage) is bounded by keeping the
human and the eval-gate in the loop — exactly the stages A leaves untouched.

## Domain Assessments

**Assessed:** Engineering (CTO + repo-research + learnings, full fan-out), Product (CPO). Marketing
(flagged for C), Operations, Legal, Sales, Finance, Support — not relevant (internal harness infra,
no external/data/credential/legal surface).

### Engineering

**Summary:** Weakness-mining is the only loop-stage that is read-only and thus structurally cannot
cause a user-brand incident — it is the correct first increment. Proposal-validation is already
built (ADR-069 + eval-gate); auto-proposal of rules is the highest-risk stage and must be deferred
behind an additive-only policy + new ADR. Full HarnessX processor-combo search is over-engineering
at markdown scale. Known landmines from shipping v1 (compound-promotion, PR #3559): never trust
LLM-supplied hashes/diffs, bind all security-gated fields, track-don't-gitignore CI config,
gate destructive ops on runtime state, and "looks gated ≠ is gated" (exercise the operative path).
Complexity: small.

### Product

**Summary:** The brand already commits "self-improves" as core identity and names compounding
knowledge as the structural moat (roadmap T3) — this makes an already-promised capability legible
rather than a net-new pitch. Surface improvement as *outcome* ("your workspace got smarter this
week"), never mechanism. Required guardrails before any self-modification reaches a user workspace:
regression gate (non-negotiable), human-legible changelog, one-click rollback, shadow-first. The
"cheaper model at same quality" lever is real but positioning-sensitive (Phase 4/5 margin play,
gated on eval parity). Both are captured as deferred issue C (legibility) — A itself never reaches
a user workspace.

## Capability Gaps

- **No weakness-miner skill/agent exists** (engineering domain). Evidence: repo-research grep of
  `.github/workflows/`, `.claude/hooks/`, `plugins/soleur/skills/` found telemetry producers
  (`.rule-incidents.jsonl`, `rule-metrics-aggregate.yml`) and consumers of *learnings*
  (`cron-compound-promote.ts`) but **no primitive that clusters failure signal into recurring
  patterns**. That missing primitive *is* increment A.
- **No agent owns "harness evolution safety"** (Product + CTO) — the regression-gate + rollback
  surface for B/C spans domains; assign ownership before B is built. (Deferred with issue B.)

## Session Errors

- **Article framing implied greenfield; Soleur is ~70% there.** Corrected before scoping — the
  brainstorm re-framed from "adopt Self-Harness/HarnessX" to "audit the existing loop + close the
  one open stage." Prior art: #397 self-healing-workflow (Layer 2 deferred), `cron-compound-promote`,
  `rule-metrics-aggregate`, ADR-069, #5768 harness-L3.
- **`rule-metrics.json` = 97 rules @ 0 fires over 8 weeks** surfaced during research — a latent
  broken-telemetry / dead-rule signal independent of this feature. Folded into the miner's
  secondary output (obsolescence candidates) rather than spun out, since it is the same substrate.
