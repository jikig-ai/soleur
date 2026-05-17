---
title: cc-soleur-go Stage 6 — post-cutover regression net (smoke + visual QA)
date: 2026-05-13
issue: 2939
related_prs: [2925, 3270, 3720]
related_issues: [2886, 3722]
brand_survival_threshold: single-user incident
lane: cross-domain
status: brainstorm-complete
tags: [cc-soleur-go, playwright, smoke, regression, visual-qa, stage-6]
---

# Stage 6 cc-soleur-go — post-cutover regression net

## What We're Building

A Playwright e2e smoke suite plus a one-time manual visual-QA rubric that pins the chat-UI surface of cc-soleur-go against the **regression classes** that have already shipped post-cutover. Layered into 3 PRs:

- **PR-A** — `DEV_ORIGINS` fix (port-portable for ports 3099/3100) + WS-injector helper + 4 per-bubble Playwright assertions (subagent-group, interactive-prompt-card, workflow-lifecycle-bar, tool-use-chip).
- **PR-B** — Routing/cost/UX smoke (plan §369-386 tasks 6.1-6.7 + 6.5.2-6.5.4): workflow routing, sticky workflow, mid-workflow leader switch, cost circuit breaker, chip-render-in-8s, narration-before-Skill, subprocess-reuse, ended-state UX, container-restart pending-prompts drop.
- **PR-C** — Security smoke (plan §6.8-6.11): prompt-injection drain, bash review-gate, cross-user prompt-response, 11-conversation rate limit. Plus the one-time visual-QA rubric in PR description.

Each PR closes a slice of #2939; the issue is the umbrella.

## Why This Approach

The issue's original framing — "smoke tests before flipping `FLAG_CC_SOLEUR_GO` on" — is **stale**. PR #3270 retired the flag ~6 weeks ago; cc-soleur-go has been the unconditional production path since then. Stage 6 is no longer a pre-flip gate; it's a **post-cutover regression net** that catches what has been shipping unguarded.

That reframe sharpens the design: the smoke suite asserts the regression classes already-observed in the wild (stream_end omission, document-context drop, chip-removal contract, expand-boundary, leader-id avatar map), not hypothetical pre-flip behavior. Mock at the WebSocket message boundary — there is an existing pattern in `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` (replay recorded WS events through `applyStreamEvent`) — promote that pattern to Playwright via a 30-LoC WS injector that calls `page.evaluate()` to push frames into the chat client. No real SDK in CI (quota burn + flake); a nightly real-SDK canary off the PR-blocking path is the fallback.

Visual regression baselines (`toHaveScreenshot()`) are explicitly rejected for now — theme PRs (#3308, #3585, #3587, #3656) churn ~12 baselines per touch and the resulting "rebaseline" PRs would degrade reviewer signal. Manual screenshots in the PR description cover the one-time pre-merge gate; promote to automated baselines only if a visual regression actually ships.

## User-Brand Impact

**Artifact:** cc-soleur-go chat-UI router path, currently shipping to every conversation.

**Vector(s) endorsed by operator (both):**
- **Trust breach:** false-negative smoke green-lights a regression. Every cc-soleur-go-routed conversation degraded (broken bubbles, stuck spinners, dropped tool blocks, silent stream-end failures).
- **Data loss / corruption:** silent drop of tool-use blocks or conversation history. User loses work or sees inconsistent state.

**Threshold:** single-user incident (default for user-brand-critical). One affected user is enough to ship a fix.

**Why this matters for #2939 specifically:** since the flag is retired, false-negative smoke does not "gate" a future rollout — the cutover already happened. The smoke is the regression net for **post-cutover changes**: every cc-soleur-go-adjacent PR after Stage 6 lands rides on the assertions Stage 6 introduces. A weak suite degrades the brand-survival floor for every subsequent change to this surface (#2954, #3270, #3603, #3608, #3639-42, #3648, #3670 already touched it post-Stage-4).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Issue framing | **Edit #2939 in-place** with Reconciliation block; drop "flag-on" language | Preserves inbound links from #3722 (blocked-by), #2925, plan §369-386 |
| Mock layer | **WS message boundary** via `applyStreamEvent` replay | Hermetic, deterministic; pattern already exists. SDK-level mock = test asserts a fiction; real SDK = CI quota burn + flake |
| Visual regression | **No `toHaveScreenshot()` infra.** Manual screenshots in PR body | Theme-PR churn would degrade reviewer signal-to-noise. Promote later only if a regression slips |
| Security smoke (6.8-6.11) | **Elevate all to Playwright** | Recurring regression class; operator chose full automation over manual checklist |
| `DEV_ORIGINS` port hardcoding | **Fix in PR-A** | ~5 LoC; unblocks every future e2e POST flow. Constraining Stage 6 to WS-only would mask the underlying gap |
| Empty MCP allowlist | **Assert degraded UX explicitly** in tool-use-chip golden path | The "unregistered tool" affordance is the actually-shipping behavior. Allowlist seeding waits for #3722's documented-demand gate |
| Empirical-demand telemetry (#3722) | **Separate concern** | Smoke does NOT exercise denied tools (that would mask the Sentry signal). #3720's mirror runs passively |
| PR layering | **3 PRs (A: bubbles + DEV_ORIGINS, B: routing/UX, C: security + visual QA)** | Each ~250-300 LoC; reviewable independently; each closes a slice of #2939 |
| Manual QA rubric scope | **One-time, retire post-merge** | Per-release manual walks decay into theater (CPO). Re-introduce only if visual regression actually ships |
| Three invisible contracts | **Cover in manual rubric** (avatar renders, markdown renders post `stream_end`, document/PDF context-aware reply) | Surfaced regression class per 2026-05-04 learning |
| AC11 (Continue-Thread tab reload) | **Cover in manual rubric** | Regression check from transcript-hardening brainstorm (2026-05-11) |
| Screenshot redaction | **AC: redact test-user identifiers** if screenshots committed to PR | CLO ask; covers PA 2 incidental-personal-data risk |
| `errorClass` slugs for any new Sentry mirror | **Globally unique, registered in observability.ts:223-237** | Per 2026-05-13 mirror-debounce learning; prevent TTL bucket collisions |

## Open Questions

- **Q1: PR-A → PR-B → PR-C ordering vs parallel work?** Sequential ordering keeps the WS-injector helper from PR-A available to PR-B/C, but PR-B and PR-C are independent of each other once PR-A lands. Recommend: ship PR-A first; PR-B and PR-C land in parallel after.
- **Q2: Nightly real-SDK canary scope?** CTO recommended one prompt off the PR-blocking path. Should Stage 6 land the canary or defer to a follow-up issue? Recommend defer — Stage 6 PRs are already large; canary is a separate ops surface.
- **Q3: 6.5.1 CFO gate** — the operator chose to elevate 6.8-6.11 security to Playwright but the question didn't reaffirm 6.5.1 (CFO cost-circuit-breaker gate). Treat as in-scope for PR-B with the rest of 6.1-6.7? Recommend yes.
- **Q4: Visual-QA rubric storage.** CLO said "ephemeral on operator workstation, not committed to repo" by default. If PR-C ships the rubric as `knowledge-base/project/specs/feat-cc-soleur-go-smoke-2939/visual-qa-rubric.md`, that's spec text not screenshots — OK to commit. Screenshots themselves go inline in PR-C description.
- **Q5: How do we re-validate the regression net after Stage 6 closes?** Plan §485 AC3 + §497 AC15 + §543 (sandbox audit gap) + §802 all gate on Stage 6. After Stage 6 closes those slots, what's the standing assertion that the suite catches future regressions? Recommend: a `cc-router-stage-6-smoke` GitHub Actions job runs on every PR touching `apps/web-platform/server/cc-dispatcher.ts` or `apps/web-platform/components/chat/**`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Smoke is a kill-switch event, not a graded rollout — operator endorsed both trust + data-loss thresholds, so smoke passes only at 0 regressions on the 4 golden paths. Per-bubble golden assertions identified (subagent-group expand-boundary, interactive-prompt-card resolved-state, lifecycle-bar monotonic + no stuck spinner, tool-use-chip no-silent-drop). Manual visual QA is a one-time gate, not recurring (per-release walks decay into theater). CPO flagged a product risk: empty MCP allowlist means tool-use-chip golden path certifies the degraded UX — operator chose to assert that explicitly rather than seed an allowlist, which keeps Stage 6 honest about what actually ships.

### Legal (CLO)

**Summary:** GO with one AC addition. Existing `cq-test-fixtures-synthesized-only` rule covered by mock-Supabase fixtures (PA 2 doesn't apply to synthesized data). RoPA already covers cc-router (PA 9) and Sentry telemetry (PA 6) — no DPA delta for Stage 6. The soft spot is visual-QA screenshots: if committed to repo or PR, test-user identifiers must be redacted (PA 2 incidental personal data). Add one-line AC: "Screenshots committed to PR or repo: redact test-user identifiers." Phase 2 (#3722) is where per-tool TOMs land; Stage 6 doesn't promote tools so no compliance gap.

### Engineering (CTO)

**Summary:** Surfaced the FLAG_CC_SOLEUR_GO retirement (#3270) — issue body is stale and reframes Stage 6 from "pre-flip gate" to "post-cutover regression net." Recommend mock-at-WS-boundary (pattern already exists at `test/cc-soleur-go-end-to-end-render.test.tsx`), no `toHaveScreenshot()` infra (theme-PR baseline churn degrades signal), and the smallest PR shape: ~150 LoC e2e + ~30 LoC injector + 4 bubble assertions + manual rubric. Operator chose to expand scope to full 6.1-6.11 automation + DEV_ORIGINS fix, so total LoC budget ≈ 600-900 across 3 layered PRs. Binding constraints brought forward: `DEV_ORIGINS` port-hardcoding (learning 2026-04-13), `stream_end` load-bearing for bubble state transitions (learning 2026-05-04), `.e2e.ts` extension + `tsx` dev-mode + URL-shaped dummy Supabase env (learning 2026-03-29).

## Capability Gaps

None reported. All required substrates exist:
- Playwright config with `chromium` + `authenticated` projects (`apps/web-platform/playwright.config.ts`)
- Mock-Supabase harness on port 54399 (`apps/web-platform/e2e/mock-supabase.ts`, `global-setup.ts`)
- `applyStreamEvent` WS-replay pattern (`apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx`)
- `data-*` selector convention on chat-UI bubbles (per `cq-jsdom-no-layout-gated-assertions`)
- `mirrorWithDebounce` + globally-unique `errorClass` registry (`apps/web-platform/server/observability.ts:223-237`) for any new Sentry mirrors

The DEV_ORIGINS fix is a code change, not a missing capability — `validate-origin.ts` exists and just needs to honor `NEXT_PUBLIC_APP_URL` (verified via `git grep DEV_ORIGINS apps/web-platform/server/`).

## Cross-references

- Issue: #2939
- Source PR (Stage 4): #2925 (merged 2026-04-27)
- Flag retirement: #3270
- Unblocks: #3722 (Phase 2 MCP promotion, blocked-by Stage 6)
- Parent plan: `knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md` §369-386 (Stage 6 tasks 6.1-6.12)
- Brand-survival learnings:
  - `knowledge-base/project/learnings/2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md` (stream_end + document-context regression class)
  - `knowledge-base/project/learnings/2026-04-13-local-qa-auth-csrf-playwright-gaps.md` (DEV_ORIGINS port-hardcoding)
  - `knowledge-base/project/learnings/2026-04-18-auth-gate-smoke-tests-enumerate-patterns.md` (enumeration-extend in same PR pattern)
  - `knowledge-base/project/learnings/2026-03-29-playwright-e2e-test-setup-for-nextjs-custom-server.md` (.e2e.ts + tsx + dummy Supabase env)
  - `knowledge-base/project/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md` (absolute worktree paths for screenshots)
  - `knowledge-base/project/learnings/2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces.md` (any new Sentry mirror: debounce + unique errorClass)
- Adjacent in-flight: #3720 (Phase 1 MCP tier-classify, merged 2026-05-13) — `readCcMcpAllowlist()` wired at `cc-dispatcher.ts:1044`
