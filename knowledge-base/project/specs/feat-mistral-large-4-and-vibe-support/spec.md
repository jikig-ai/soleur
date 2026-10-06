---
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-06-mistral-large-4-vibe-support-brainstorm.md
issue: 9648
draft_pr: 9640
---

# Feature: Mistral Large 4 + Mistral Vibe support (staged)

## Problem Statement

Soleur has no Mistral support. The operator wants Soleur users to be able to use Mistral Large 4 (API now, open weights ~Oct 27, licence unpublished) and the Mistral Vibe CLI harness, as part of an EU-sovereignty positioning that is not yet documented or validated. The three possible surfaces (plugin-in-Vibe, Mistral as hosted model backend, self-hosted weights) have different effort, legal gates and blast radius, and public claims must not outrun shipped, tested capability.

## Goals

- G0 *(added in second session)*: Mistral models (ML4 preview API and/or Devstral) are dogfooded through vehicles that need no new harness — Codex custom `model_providers` (OpenAI-compatible) and/or the #1215 Ollama+proxy BYOM path — measured with the `grok-measure.sh` classes inside the Oct 6→27 preview window.
- G1: Soleur plugin runs in Mistral Vibe as a fifth harness (skills-only v1), proven by a measured eval table; sequencing prefers after #9608's slice-1 lands so the #9609 adapter checklist is stable.
- G2: A BYOK `mistral` provider exists on one non-agentic path behind a default-off flag, priced so BYOK caps cannot bill $0. A bundled Soleur-paid option is a follow-up decision gated on usage data.
- G3: An honest "harness-neutral, evaluating Mistral" content piece ships inside the news window.
- G4 *(amended in second session)*: Small-class self-host (Devstral Small 2 / Mistral Small 4, single GPU, GEX44-class runbook shape, operator-spend gate) is a live dogfood stage; ML4 frontier self-host stays a tracked re-evaluation item.

## Non-Goals

- Hosted Concierge on Mistral (replacing the Claude Agent SDK) — parked with #6547's criteria.
- Self-hosting ML4 now (small-class models — Devstral Small 2, Mistral Small 4 — are IN scope per G4).
- "EU-sovereign", "data never leaves the EU", "GDPR-compliant Mistral", or Claude-parity claims.
- Porting Claude hook guardrails to Vibe in v1.
- Generating Vibe TOML agents in v1 (follow-up).

## Functional Requirements

### FR0 *(added in second session)*: Model dogfood via existing vehicles

Before any adapter work, run Mistral models through Soleur on paths needing no new harness: (a) Codex custom `model_providers` pointing at the Mistral API (verify its OpenAI-compatibility first — Open Questions), and/or (b) the #1215 Ollama+`claude-code-proxy` BYOM path. Measure with the `grok-measure.sh` dogfood classes; publish the eval table on #9648. This signal gates FR1/FR3 spend.

### FR1: Vibe harness (skills-only)

Add `vibe` to the `Harness` union with a detector, `harness.ts` adapter functions, `plugins/soleur/vibe/INSTRUCTIONS.md`, and an `inherit` tier map. Skills load via Vibe's native `.agents/skills`/`SKILL.md`; no hand-copied tree (ADR-245). Skills that fan out to agents run sequentially inline with a disclosed `Reviewed-Coverage: sequential-fallback`. The harness README states hooks/guardrails are unsupported. The adapter consumes the #9609 new-harness checklist once #9608 (Cursor) slice-1 measures which rows are stable — Vibe is its second consumer *(second session)*.

### FR2: Vibe eval and dogfood

Run `soleur:eval-harness` (or a measured brainstorm/plan/work smoke) on Vibe with Mistral Large 4 via API; publish a pass/fail table. Operator-only dogfood first.

### FR3: BYOK `mistral` provider spike (flagged)

Add `mistral` to `PROVIDER_CONFIG`/`Provider`, a priced `MODEL_PRICING` entry (unknown model must fail closed, not bill zero), and one non-agentic call path, behind a default-off runtime flag (`soleur:flag-create`). Concierge stays on the Claude SDK.

### FR4: Legal train (blocks flag-on for FR3)

Mistral DPA snapshot under `knowledge-base/legal/data-processing-agreements/`; update Privacy Policy §5.1, DPD §2.3 + sub-processor table, GDPR Policy §4.2 + balancing entry, T&C §3a.5/AUP, Art. 30 PA-22/PA-23 + Vendor Mapping row, `compliance-posture.md` row; both doc mirrors, SHA re-pins, T&C version bump, CLO attestation. Transfer analysis per PA-7.

### FR5: Hedge content

CMO-owned post/thread: harness-neutral, evaluating Large 4 + Vibe, sovereignty framed as the user's choice of model/key. No "runs on Mistral" or "EU-sovereign" wording until FR2/FR3+FR4 ship. Needs CLO review of any sovereignty phrasing.

### FR6: Deferred tracking

Issues for: C2 ML4 self-host (re-evaluate when weights + licence + hardware publish; fold into #6546; #9649), Vibe TOML agent generator + hook portability (#9650), `sovereignty` demand validation (business-validator + 4.2 interviews; #9651), bundled Soleur-paid Mistral keys (post-usage-data decision — session 2), `model-dogfood` vendor-neutral eval skill (productize candidate — session 2). C1 small-class self-host is a LIVE stage, not deferred.

## Technical Requirements

### TR1: Measure before asserting

Vibe env markers, hook-blocking support, skill-frontmatter compatibility, and ML4 API compatibility (OpenAI/Anthropic) are unmeasured — measure on a real install before the detector/provider ships.

### TR2: Harness gates

Extend ADR-226 parity ("FOUR harnesses"), `harness-discovery` CI (version-pinned vendor CLI, sha256-pinned scripts, non-required until soak per ADR-245), and `harness-model-map` parity test. New ADR required (5th harness + provider decision).

### TR3: Pricing fail-closed

`MODEL_PRICING` lookup for an unknown model must error or cap-block, never return zero cost.

### TR4: Telemetry

If Soleur ships any Vibe config, set `enable_telemetry = false` by default and disclose; measure what Vibe sends before claiming anything.

### TR5: Licence gate

No open-weight pull before the LICENSE/AUP is read live and checked (field-of-use, revenue/MAU caps, EU AI Act GPAI duties).
