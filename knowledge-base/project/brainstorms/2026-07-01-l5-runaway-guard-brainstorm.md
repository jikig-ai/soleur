# Brainstorm: L5 Runaway Guard — Doom-Loop Detection + Token/Cost Circuit Breaker

**Date:** 2026-07-01
**Issue:** [#5767](https://github.com/jikig-ai/soleur/issues/5767)
**Branch:** feat-l5-runaway-guard · **Draft PR:** #5881
**Lane:** cross-domain · **Brand-survival threshold:** single-user incident

## What We're Building

An L5 "agent-as-process safety" layer that stops an autonomous agent run from silently burning
a non-technical founder's own Anthropic (BYOK) credits, unattended. Six gaps, staged as a
dependency-ordered multi-PR train (operator chose **full scope**):

- **PR-A — Safety floor (MVP):** turn today's *per-spawn, hardcoded, silent* cost ceiling into a
  **rolling-24h-per-founder, operator-tunable, notified** ceiling; wire `persistFailure` to an actual
  operator notification; amend ToS §3a.5/§11 + Article 30 register; run `/soleur:gdpr-gate`.
- **PR-B:** pre-run **cost estimate** (always shown, informational) + **opt-in HITL** approval for
  routines the founder explicitly arms as high-cost.
- **PR-C:** **doom-loop detector** — nudge-then-halt on repeated no-progress edits, on the web
  leader loop and the CC plugin, reusing the hash+Jaccard math already in `stop-hook.sh`.
- **PR-D:** **cron-substrate token metering** — bring the opaque `claude --print` heavy crons under
  the ceiling by switching to `--output-format stream-json --verbose` + a JSONL usage parser.
- **Cross-cutting:** an **ADR** for the enforcement topology (web = pre-emptive hard kill; CC =
  best-effort at tool/Stop boundaries).

## Why This Approach — the reconciliation that reshaped the feature

The issue's premise ("no run-wide ceiling exists"; "each journaled Inngest step checks cumulative
tokens") is **partially obsolete**. The durable agent-run supervisor (#5866/#5868) **merged
2026-07-01**, and two research agents surfaced a contradiction that direct code reading resolved:

| Surface | File | Cost guard today | Doom-loop today |
|---|---|---|---|
| Web Concierge / leader loop (the #5868 supervisor) | `agent-on-spawn-requested.ts` | ✅ 3 layers: BYOK `killTripped` cap, `PER_SPAWN_COST_CEILING_CENTS=260¢`, `LEADER_MAX_TURNS=8` — **per-spawn, hardcoded, silent** | ❌ none |
| Heavy autonomous crons | `_cron-claude-eval-substrate.ts` | ❌ wall-clock + `--max-turns` only; opaque `claude --print`, **no token metering** | ❌ none |
| CC plugin (local) | `stop-hook.sh` | ❌ none | ⚠️ hash+Jaccard *math* exists, not wired to cost |

So the work is **extend + fill**, not build-from-scratch. The genuine deltas: per-spawn→rolling-window,
hardcoded→tunable, silent→notified, +estimate/opt-in-HITL, +doom-loop (net-new), +cron metering (large).
Safety-floor-first sequencing ships the highest-value/lowest-cost slice (PR-A extends shipped code and
closes a live ToS drift) and isolates the expensive stream-json build (PR-D) last.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Full scope**, staged as a 4-PR train (A→D) + ADR | Operator chose everything; a single PR spanning two execution models + ToS + UX is unreviewable |
| D2 | **Safety-floor first** (PR-A = ceiling upgrade + notify + ToS + register) | Highest value/lowest cost; extends shipped code; closes existing §3a.5 drift |
| D3 | Ceiling scope = **rolling 24h per founder** (not per-run) | Catches death-by-many-runs; *cheaper* to build — existing `audit_byok_use` query already sums by `founder_id`, just add a time filter |
| D4 | HITL = **estimate-only, no gate by default**; opt-in per high-cost routine | Honors `wg-verified-work-ships-without-asking`; ceiling+notification is the real guardrail; avoids reintroducing approval fatigue for non-technical users |
| D5 | Default ceiling value = **CFO deliverable at plan time** | Finance/cost-model decision vs `knowledge-base/finance/cost-model.md`; brainstorm settles WHAT not the number |
| D6 | Notification reuses **`notifications.ts` WS→Push→Email** hierarchy | Channel already exists (`usage_update` WS, branded Resend email, VAPID push); no new channel |
| D7 | Doom-loop halt must **return terminal `ok:false`, never throw** | A throw triggers Inngest retry/replay → re-enters `spawnClaudeEval` and *replay-loops the very runaway*. Durable counter checked on entry (CTO) |
| D8 | Doom-loop counter folds into **existing `routine_run_progress`/`action_sends` row**, not a new per-edit table | A per-edit INSERT on a hot path is the WAL-budget class #5736 caught |
| D9 | **ToS §3a.5/§11 + Art.30 register amended in PR-A** (clo-attestation) | §3a.5 ("no Jikigai-provided cost ceiling") is **already contradicted** by the shipped 260¢ ceiling; feature makes the ceiling relied-upon |
| D10 | Shared **policy schema + hash helper** across surfaces; enforcement diverges | Web = pre-emptive kill; CC = best-effort at tool/Stop boundaries — a single runtime primitive would be a forced abstraction (CTO) |
| D11 | Visual design | Wireframes: `knowledge-base/product/design/runaway-guard/l5-runaway-guard-surfaces.pen` (screenshots/ 01-estimate, 02-hitl-modal, 03a/03b halt-banner, 03c halt-email) — pre-run estimate, opt-in HITL modal, breaker-tripped banner + email |
| D12 | UI uses **sharp 0px corners** (brand guide), not the drifted `rounded-lg` current web CTAs | Wireframes flagged the drift; email scaffold already uses `border-radius:0`. Implementation follows brand, not existing drift |

## Open Questions

1. **Default ceiling dollar value** — CFO consult at plan time (D5). Anchor candidate: `260¢ × typical spawns/24h`.
2. **Cron stream-json go/no-go (PR-D)** — is switching heavy crons to `--output-format stream-json --verbose`
   acceptable? It touches redaction + bounded-tail logic. If "no," cron cost control stays coarse
   (wall-clock + `--max-turns`) and PR-D degrades to a documented limitation (CTO open-Q #1).
3. **Budget-check granularity** — per-turn (tight, needs stream-json) vs per-heartbeat-tick (~30s, cheaper,
   coarser overshoot). Overshoot tolerance is a product/cost call (CTO open-Q #2).
4. **Resume semantics after raising the ceiling** — resume from journaled state vs restart; must not re-bill
   completed work (CPO). Durable-supervisor mechanics = CTO at plan time.
5. **Doom-loop "no-progress" signal** — identical-action hash `(file_path+diff)` (most reliable) vs
   edit-count-per-target vs test-exit-stall (narrow — leave to `test-fix-loop`, don't generalize).

## User-Brand Impact

- **Artifact:** the L5 runaway-guard enforcement layer on the web agent-run supervisor
  (`agent-on-spawn-requested.ts`) + its operator-facing halt notification.
- **Vector:** an unattended autonomous run silently burns a founder's own Anthropic credits (hundreds/
  thousands of dollars overnight) with no artifact to show for it and no notice — a direct real-dollar
  loss on money the founder controls, plus a churn-and-warn event in the exact channels (IndieHackers,
  Claude Discord, X) Phase-4 validation recruits from.
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per #5175). CPO + CLO + CTO spawned in parallel at Phase 0.5.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Table-stakes, not nice-to-have — every autonomous product that spends unattended has this
guardrail; its absence is a conspicuous gap. This is a **prerequisite** for the Phase-4 unattended-usage
cohort (#1442), yet filed as p2 alongside it — **roadmap gap: elevate and sequence ahead of #1439/#1442**.
Ceiling should be conservative-default-on + tunable; halt notification via both in-product banner and email,
in dollars not tokens, never implying the run completed. Default ceiling value → CFO.

### Engineering (CTO)

**Summary:** The issue's "each journaled Inngest step checks cumulative tokens" rests on a misconception
for the *cron* surface (opaque `claude --print`, no per-turn usage stream — real metering needs stream-json,
the largest build item). But the *leader* surface already meters per-turn and has a per-spawn ceiling. Hard
halt is safe **only** via the existing `AbortController` SIGTERM→SIGKILL seam and a terminal `ok:false`
return — **never a throw** (replay-loops the runaway). Fold counters into the existing live-state row, not a
new table (WAL-budget). Surfaces diverge on enforcement; share policy schema + the `stop-hook.sh` hash math.
Recommends an ADR for the enforcement topology.

### Legal (CLO)

**Summary:** **P0 blocking** — ToS §3a.5 currently represents "no Jikigai-provided cost ceiling," which the
feature (and the already-shipped 260¢ ceiling) falsify; amend §3a.5 + confirm §11 overage carve-out **in the
same PR train**, modeled on the existing best-effort "Stop-control" clause (operator bears BYOK overage;
breaker is best-effort). The pre-run estimate + opt-in HITL is the legally-prudent spend-consent surface and
the runtime enforcement the prose rule `hr-autonomous-loop-skill-api-budget-disclosure` anticipated (keep
both — enforcement ≠ disclosure). Cost-meter/halt-log/notification must be checked against the Article 30
register + DPD + GDPR Policy (the GDPR-Policy entry is the most-often-missed); notification payload minimized
to cost/token aggregates + run-id, no prompt/response content. Run `/soleur:gdpr-gate` at plan 2.7 / work
Phase-2 exit (regulated-data surface: billing/cost records + BYOK path). Document edits pass the v1
counsel-review CLO-attestation gate.

### Finance (CFO)

**Summary:** Not spawned at Phase 0.5; flagged by CPO. **Consult at plan time** to set the conservative
default ceiling value against `knowledge-base/finance/cost-model.md` (roadmap note: "BYOK eliminates per-user
LLM cost" — the runaway burn is the founder's own bill, so the default must protect the founder, not Soleur
margin).

## Capability Gaps

None. Engineering (durable-runtime work on the existing web-platform surface), `data-integrity-guardian`
(migration review), `observability-coverage-reviewer` (halt/notify path gating per
`hr-observability-as-plan-quality-gate`), CFO/`budget-analyst` (default value), and the legal agents
(`legal-document-generator` → `legal-compliance-auditor` → `gdpr-gate`) cover the full scope. Evidence:
verified `agent-on-spawn-requested.ts:319-418` (existing 3-layer guard), `constants.ts:19-22`
(`PER_SPAWN_COST_CEILING_CENTS=260`, `LEADER_MAX_TURNS=8`), `persistFailure` at `:913-961` (silent, no
notify), `notifications.ts` (WS→Push→Email channel), `stop-hook.sh:149-258` (portable loop math),
`_cron-claude-eval-substrate.ts` (opaque `--print` spawn).

## Session Errors

1. **Premise reconciliation (caught pre-Phase-2).** The issue framed the token circuit breaker as net-new
   and enforceable "in each journaled Inngest step." Two research agents returned contradicting surface
   findings (CTO: opaque `--print`, no hook; repo-research: per-turn ceiling already exists). Direct code
   reading (`agent-on-spawn-requested.ts`, `constants.ts`, `persistFailure`, ToS §3a.5) resolved it: **two
   distinct execution surfaces**, and a per-spawn ceiling **already ships** on the primary one. Reframed to
   extend+fill rather than build-from-scratch before presenting approaches. Lesson: when two agents disagree
   on infra state, the orchestrator must read the code itself — neither summary was wholly right.
2. **Live ToS drift discovered.** ToS §3a.5's "no Jikigai-provided cost ceiling" is already false in prod
   (260¢ ceiling shipped). Recorded so the PR-A author treats the amendment as fixing existing drift, not
   just adding wording for a new feature.
