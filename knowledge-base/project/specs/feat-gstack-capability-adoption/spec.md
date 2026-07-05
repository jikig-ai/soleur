---
feature: gstack-capability-adoption
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
pr: 5982
brainstorm: knowledge-base/project/brainstorms/2026-07-04-gstack-capability-adoption-brainstorm.md
---

# Spec: gstack Capability Adoption (epic)

## Problem Statement

gstack demonstrates engineering-craft-depth mechanisms Soleur lacks or covers
only partially. A gap analysis surfaced 12 adaptable candidates. Adopting them
wholesale would import gstack's per-machine (`~/.gstack`) and multi-host machinery,
which contradicts Soleur's repo-committed-knowledge constitution and all-Claude
model policy (ADR-053). This epic adapts the *mechanisms* into Soleur's frame,
sequenced by dependency and shared surface.

## Goals

- Adopt the 12 candidates as a wave-sequenced epic, dependency-ordered.
- Reuse existing Soleur surfaces where possible (agents, hooks, ADR-083 consult).
- Add net-new capability only where genuinely ABSENT (web-vitals, canary, taste
  model, Diataxis, MD→PDF).
- Keep the all-Claude model policy intact; substitute a two-Claude-persona
  review for gstack's cross-vendor OpenAI dependency.

## Non-Goals

- **No cross-vendor (OpenAI/Gemini) model calls.** Conflicts with ADR-053; the
  User-Challenge substitute uses `fable`→`opus` via the existing ADR-083 consult.
- No compiled browser daemon, anti-bot stealth, iOS StateServer suite, pair-agent
  ngrok tunnel, 10-host adapters, gbrain home-dir storage, voice triggers, or
  home-dir telemetry (all off-mission, explicitly skipped).
- No new second browser-automation stack in Waves 1–3 (Playwright deferred to Wave 4).

## Functional Requirements (by wave)

**Wave 1 — cheap engine wins**
- FR1 (T1-3) Decision-principles engine: classify intermediate decisions
  Mechanical / Taste / User-Challenge; auto-answer Mechanical, surface
  User-Challenge with "what you said / what models recommend / cost if we're
  wrong". Extend the ADR-083 consult; wire into `one-shot`/`plan`/`brainstorm-techniques`.
- FR2 (T1-4) Named multi-dimensional plan panel: wire existing `cpo`/`cmo`/`cto`/
  `ux-design-lead` agents into `plan-review` as CEO/design/devex reviewers
  alongside the eng reviewers. Depends on FR1's classifier.
- FR3 (T3-12) Operator velocity metrics: enhance `operator-digest` with legible
  shipping-cadence/cost-trend metrics (OQ3 — **RESOLVED**, see below).

  **OQ3 (which velocity metrics are legible for a single non-technical operator vs.
  noise?) — RESOLVED** (#5986,
  `knowledge-base/project/plans/2026-07-04-feat-operator-velocity-metrics-plan.md`
  §OQ3 Resolution). **Legible:** shipping cadence (qualitative band vs recent weeks)
  and cost trend (this-week direction + a coarse run-rate anchor). **Noise (excluded):**
  per-contributor/per-author velocity, context-switching, raw counts/percentages/arrows,
  cycle-time/DORA jargon, lines-of-code. True month-over-month cost baseline deferred
  (allowlist + false-precision reasons in the plan's resolution table).

**Wave 2 — safety + memory spine**
- FR4 (T2-7) Redaction hardening: NFKC-normalize + zero-width-strip before
  matching; ReDoS-safe input cap emitting a synthetic HIGH so callers fail-closed.
  Apply to `incident`/`code-to-prd`/legal redaction paths.
- FR5 (T2-8 + T3-11, bundled) Guard hardening: fail-closed recursive-delete
  ownership proof (realpath + structural-name + no-`.git` tripwire + minted marker)
  and a `freeze` directory-scoped edit-lock — both on the shared PreToolUse
  `.claude/hooks/guardrails.sh` surface, one PR.
- FR6 (T2-6) Declarative context-injection: skill-frontmatter `context_queries`
  that auto-load committed `knowledge-base/` artifacts. Fail-open on parse error
  (must not fail-closed all skills). Unblocks FR7.

**Wave 3 — build on the spine**
- FR7 (T2-5) Taste-learning: multi-variant design fan-out + committed
  `taste-profile` (decaying confidence, contradiction-flagging) loaded via FR6.
  Extend `frontend-design`/`ux-design-lead`.
- FR8 (T3-9 + T3-10, bundled) Diataxis doc structuring for `docs-site`/
  `content-writer` + a Markdown→PDF skill for operator deliverables.

**Wave 4 — deferred, gated on ADR**
- FR9 (T1-1 + T1-2, one harness) Playwright runtime-measurement harness: pre-deploy
  baseline manifest (screenshot + console-error count + load-time per page),
  post-deploy polling with severity classification, and Core Web Vitals
  (LCP/CLS/INP) + bundle-size before/after. Gated on FR-ADR below.

## Technical Requirements

- TR1: **New ADR** — "Playwright runtime-measurement harness alongside the
  agent-browser CLI convention" — documenting the deliberate second-dependency
  decision, the deployed-URL/auth story, and baseline-stability mitigations. Blocks FR9.
- TR2: FR6 loader change must be covered by a parse-failure test asserting
  fail-open across all skills (blast-radius mitigation).
- TR3: FR5 must not let `freeze`-deny shadow existing sentinel checks in
  `guardrails.sh`; add a regression test proving delete guards still fire.
- TR4: FR1 must not be frontmatter-pinned in a way that violates ADR-053 tiering;
  the User-Challenge consult stays on the ADR-083 `fable`→`opus` path.
- TR5: All new skills/agents follow `plugins/soleur/AGENTS.md` versioning +
  description-budget rules; run `skill-security-scan` before ready.

## Dependency Graph

```
FR1 ──▶ FR2
FR6 ──▶ FR7
FR4 ──(egress precedence)──▶ any future egress feature
TR1(ADR) ──▶ FR9
```
