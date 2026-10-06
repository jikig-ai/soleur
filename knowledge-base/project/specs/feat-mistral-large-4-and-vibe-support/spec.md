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

- G1: Soleur plugin runs in Mistral Vibe as a fifth harness (skills-only v1), proven by a measured eval table.
- G2: A BYOK `mistral` provider exists on one non-agentic path behind a default-off flag, priced so BYOK caps cannot bill $0.
- G3: An honest "harness-neutral, evaluating Mistral" content piece ships inside the news window.
- G4: Self-hosting open weights is tracked with explicit re-evaluation criteria.

## Non-Goals

- Hosted Concierge on Mistral (replacing the Claude Agent SDK) — parked with #6547's criteria.
- Self-hosting ML4 now.
- "EU-sovereign", "data never leaves the EU", "GDPR-compliant Mistral", or Claude-parity claims.
- Porting Claude hook guardrails to Vibe in v1.
- Generating Vibe TOML agents in v1 (follow-up).

## Functional Requirements

### FR1: Vibe harness (skills-only)

Add `vibe` to the `Harness` union with a detector, `harness.ts` adapter functions, `plugins/soleur/vibe/INSTRUCTIONS.md`, and an `inherit` tier map. Skills load via Vibe's native `.agents/skills`/`SKILL.md`; no hand-copied tree (ADR-245). Skills that fan out to agents run sequentially inline with a disclosed `Reviewed-Coverage: sequential-fallback`. The harness README states hooks/guardrails are unsupported.

### FR2: Vibe eval and dogfood

Run `soleur:eval-harness` (or a measured brainstorm/plan/work smoke) on Vibe with Mistral Large 4 via API; publish a pass/fail table. Operator-only dogfood first.

### FR3: BYOK `mistral` provider spike (flagged)

Add `mistral` to `PROVIDER_CONFIG`/`Provider`, a priced `MODEL_PRICING` entry (unknown model must fail closed, not bill zero), and one non-agentic call path, behind a default-off runtime flag (`soleur:flag-create`). Concierge stays on the Claude SDK.

### FR4: Legal train (blocks flag-on for FR3)

Mistral DPA snapshot under `knowledge-base/legal/data-processing-agreements/`; update Privacy Policy §5.1, DPD §2.3 + sub-processor table, GDPR Policy §4.2 + balancing entry, T&C §3a.5/AUP, Art. 30 PA-22/PA-23 + Vendor Mapping row, `compliance-posture.md` row; both doc mirrors, SHA re-pins, T&C version bump, CLO attestation. Transfer analysis per PA-7.

### FR5: Hedge content

CMO-owned post/thread: harness-neutral, evaluating Large 4 + Vibe, sovereignty framed as the user's choice of model/key. No "runs on Mistral" or "EU-sovereign" wording until FR2/FR3+FR4 ship. Needs CLO review of any sovereignty phrasing.

### FR6: Deferred tracking

Issues for: C self-host (re-evaluate when weights + licence + hardware publish; fold into #6546), Vibe TOML agent generator, Vibe hook portability, `sovereignty` demand validation (business-validator + 4.2 interviews).

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
