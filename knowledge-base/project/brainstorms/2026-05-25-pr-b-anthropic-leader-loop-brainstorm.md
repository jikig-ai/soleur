---
title: "PR-B (#4124) — Anthropic SDK leader-prompt loop replacing PR-A deterministic stub"
date: 2026-05-25
issue: 4379
umbrella: 4124
substrate_pr: 4378
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# PR-B Brainstorm — Anthropic SDK leader-prompt loop

Replaces the deterministic acknowledgment stub shipped in PR-A (#4378, commit `7d5620a5`) inside `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` with a real Anthropic Messages API leader-prompt loop. Tracking issue: #4379. Umbrella: #4124.

## What We're Building

For each operator click on a GitHubCard or KbDriftCard in the Today section, drive an autonomous LLM loop (Anthropic `messages.create` with tool_use rounds, prompt caching ON, per-class model routing) that produces an action-class-specific GitHub artifact: a substantive review comment for `engineering.pr_review_pending`, a triage comment for `engineering.ci_failed`, a severity-labeled triage comment for `triage.p0p1_issue`, a CVE-bump draft PR for `security.cve_alert`, a fix-the-link draft branch for `knowledge.kb_drift`. The Today card surfaces in-flight progress (current turn N/M), per-spawn cost ($X.XX), and per-output undo affordances; on failure the card renders an inline "Failed — retry" pill instead of forcing the operator to hunt Sentry.

## Why This Approach

**PR-A established the substrate** — `agent.spawn.requested` event, `action_sends` WORM ledger with `acknowledged_at`/`artifact_url`/`failure_reason`, `createGitHubAppClient` factory with per-Octokit-call audit, `persistFailure` helper with classified `failure_reason` taxonomy, idempotency key `actionSendId`, retries=3. PR-B replaces ONLY the `post-acknowledgment` step body — every load-bearing invariant (I1 type-omit installationId / I2 createGitHubAppClient-only / I3 idempotency / I4 GitHub-only-on-`mark-acknowledged` / I5 service-role UPDATE on the 3 new columns) is inherited from PR-A and asserted by the existing sentinel tests.

**Per-class model routing + prompt caching ON** is the cost-correct shape per CFO. Without prompt caching, cumulative input across 8 turns hits 100-200K tokens (5-10x worse cost). Routing `kb_drift` + `triage.p0p1_issue` to Haiku saves ~4x on classification-shaped tasks; `cve_alert` / `ci_failed` / `pr_review_pending` keep Sonnet for reasoning depth. Operator pays via BYOK; the per-spawn cost ceiling ($2.00) is the primary fence (max-turns=8 is the secondary backstop).

**Per-turn `step.run` topology** is mandatory per Inngest replay semantics — one `step.run` per Anthropic call, deterministic step names. On retry, cached prior-turn outputs are reused; only the failing turn re-runs (no billing double-count). The BYOK lease is re-acquired inside every per-turn `step.run` (AsyncLocalStorage cannot escape step boundaries; matches `cfo-on-payment-failed.ts:199` precedent).

**Cap enforcement BEFORE the Anthropic call** (not after). `record_byok_use_and_check_cap` returns `kill_tripped`; PR-B checks this at the top of each per-turn `step.run` and short-circuits the loop with `failure_reason = "byok_cap_exceeded"` on trip. The existing CFO/GitHub Inngest stubs use a `"byok-audit-writer-sweep: out-of-scope"` marker; PR-B replaces those markers with real `persistTurnCost` calls (per the `byok-audit-writer-sweep` lint contract).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Scope** | All 5 action classes in PR-B (engineering.pr_review_pending / engineering.ci_failed / triage.p0p1_issue / security.cve_alert / knowledge.kb_drift) | User override of CPO tiered recommendation. PR-B ships the full substrate; operator dogfood will surface per-class quality gates that can throttle behind feature flags if needed. |
| **ADRs** | Two: ADR-040 (Anthropic-SDK-inside-Inngest pattern) + ADR-041 (BYOK cap enforcement model) | Cleaner reversibility for cap-policy changes. Note: issue #4379 cites "ADR-039" — STALE (taken by departed-member-removal-ledger). Pre-merge guard greps INDEX.md for next free ordinal (collisions exist on 027/030/031/033). |
| **Loop topology** | One `step.run` per Anthropic call + one `step.run` per tool invocation; deterministic step names keyed off `actionSendId` + turn index | Inngest replay semantics: cached outputs reused on retry, only failing turn re-runs. Per CTO I3 + learnings `2026-05-12-stub-handlers-as-silent-undercount-vectors.md`. |
| **BYOK lease scope** | Per-turn re-acquisition inside each `step.run` callback | AsyncLocalStorage cannot escape step boundaries. Matches `cfo-on-payment-failed.ts:199` precedent. ADR-040 documents. |
| **Cap enforcement model** | Pre-call check via `record_byok_use_and_check_cap` returning `kill_tripped`; loop short-circuits with `failure_reason = "byok_cap_exceeded"` | Per learnings: BEFORE call, fail-closed. ADR-041 documents. |
| **Max-turns ceiling** | Flat 8 (uniform across classes) | User override of CFO per-class recommendation. The per-spawn cost ceiling ($2.00) is the primary gate; max-turns is the secondary backstop. |
| **Per-spawn cost ceiling** | $2.00 (primary gate; loop terminates before max-turns if hit) | CFO recommendation; bounds worst-case operator-side spend. Distinct from BYOK daily/monthly caps. |
| **BYOK caps (operator `ops@jikigai.com`)** | Daily soft $20 / daily hard $50 / monthly hard $500 | CFO recommendation; tracked via existing `record_byok_use_and_check_cap` workspace-id RPC. |
| **Model routing** | `kb_drift` + `triage.p0p1_issue` → Haiku (`claude-haiku-4-5-20251001`); `cve_alert` + `ci_failed` + `pr_review_pending` → Sonnet (`claude-sonnet-4-6`) | ~70% cost reduction on classification-shaped classes. Per-class model selection lives in the class registry alongside max-turns. |
| **Prompt caching** | ON for all classes; `cache_read_input_tokens` + `cache_creation_input_tokens` MUST flow through `persistTurnCost` | Per `2026-05-12-stub-handlers-as-silent-undercount-vectors.md` — dashboard understates ~90% without these fields persisted. |
| **In-flight progress channel** | Supabase Realtime subscription on `action_sends` row; Inngest function writes `current_turn` + `current_turn_started_at` per turn | Existing pub/sub infrastructure; ~100ms latency. New columns in migration 065. |
| **Cancellation** | Today card "stop" button → server sets `action_sends.cancellation_requested_at`; Inngest function inspects column at start of each turn and short-circuits with `failure_reason = "cancelled_by_operator"` | Avoids Inngest function-cancel API coupling; column-driven is testable. Migration 065 adds the column. |
| **Per-output undo** | New `reversal_handle jsonb` column on `action_sends`; per-class shape (comment_id, label_name+issue_number, branch_ref); Today card "undo" button → server route reverses via stored handle | Single nullable JSONB column. Migration 065 adds + COMMENT documents per-class shapes. WORM trigger admit-list extended. |
| **Per-spawn cost visibility** | Today card surfaces cumulative cost from `byok_audit` rows joined on `actionSendId` | Pull from existing audit table. No new infrastructure. |
| **Brand-survival threshold** | `single-user incident` (matches PR-A) | Operator is still sole dogfooder; cross-tenant guard inherited; cost runaway is operator-funded (BYOK). |
| **Legal lift scope** | Pre-merge blockers in PR-B: PA-22 entry, Vendor Mapping amendment (line 412 `article-30-register.md`), Anthropic Zero-Retention verification, PII-scrub TOM (commit-author email redaction), ADR-040 + ADR-041. Deferred to parallel issues: full DPIA, consent banner, ToS clause, Art. 22 analysis | User override on PII-scrub (added to PR-B vs deferred). The PII-scrub TOM avoids retroactive prompt-shape change later. |
| **PII-scrub TOM** | Commit-author email redaction in the prompt-assembly step before any Anthropic call | Added to PR-B per user override. PR diffs piped to Anthropic regularly contain third-party PII. |
| **Anthropic Zero-Retention** | Verify status against Anthropic dashboard pre-merge; if not signed, document gap in PA-22 (f) and surface as parallel issue | Default Anthropic retention is 30 days; signed Zero-Retention amendment is the canonical answer. |
| **Tool surface allowlist** | Per-class enumerated tool set (createComment / addLabels / createPullRequest / createBranch / createRef / createBlob / createCommit); NO shell, NO arbitrary repo writes outside enumerated paths | ADR-040 documents. Tool definitions live alongside per-class prompts in the registry. |
| **`recordByokUseAndCheckCap` TS wrapper** | Build the wrapper (none exists). Returns `{ cumulativeCents, killTripped }`. Service-role-only. | Greenfield per repo research. Lives at `apps/web-platform/server/byok-cap-rpc.ts` (proposed). |
| **`failure_reason` enum expansion** | Adds: `byok_cap_exceeded`, `byok_lease_unavailable`, `anthropic_timeout`, `anthropic_rate_limited`, `leader_max_turns_exceeded`, `cost_ceiling_exceeded`, `leader_tool_invalid`, `cancelled_by_operator` | Today card failure UX (GAP #3 from PR-A) renders per-reason copy. |
| **Reality-check** | Pre-implementation grep `main` for any in-flight follow-ups touching `action_sends` / today-card / `agent-on-spawn-requested.ts` since PR-A merged | Per `2026-05-20-plan-vs-shipped-reality-check-and-octokit-factory-audit.md`. PR-A landed recently; #4124 is an umbrella so sibling PRs may already be in-flight. |

## Out of Scope (Filed as Follow-ups)

| Item | Why Deferred |
|---|---|
| Full DPIA on PA-22 (autonomous AI-driven decisioning affecting third-party data subjects in PR diffs) | Pre-merge blockers only in PR-B. Filed as parallel issue. |
| One-time consent banner + ToS clause for AI-generated GitHub artifacts | Pre-merge blockers only. Filed as parallel issue. |
| Art. 22 automated-decisioning analysis | Pre-merge blockers only. Filed as parallel issue. |
| Cross-installation spawn (one founder, multiple installations) | V2; not relevant for single-user dogfood. |
| Per-founder spawn quota / rate-limit | V2. |
| Transactional outbox between `action_sends` INSERT and `inngest.send` | Carried over from PR-A; accept ~50ms partial-failure window. |
| Real-time channel beyond Supabase Realtime (e.g., WS push) | PR-B uses Supabase Realtime; WS push deferred unless latency proves inadequate. |
| Per-class brand-survival tiering (CPO's Tier 1/2/3 staged ship) | User chose all-at-once; staged-ship deferred to per-class feature flags if dogfood surfaces per-class quality issues. |
| Per-class max-turns caps (CFO's kb_drift=3, triage=4, cve=5) | Cost ceiling is the primary gate; per-class max-turns deferred unless cost-ceiling proves insufficient. |
| Per-class quality eval suite (snapshot-test on leader prompts) | Filed as follow-up; "Cache LLM outputs flag for rerunnable benches" per `2026-05-19-cache-llm-outputs-flag-for-rerunnable-benches.md`. |

## Open Questions

1. **Anthropic Zero-Retention status** — must be verified against the Anthropic account dashboard before merge. If not signed, ADR-040 + PA-22 (f) document the 30-day default retention; consent banner copy in the parallel ToS issue reflects.
2. **`conversationId` for `action_sends`-scoped `persistTurnCost`** — `persistTurnCost` requires a `conversationId` UUID. PR-A's `action_sends` has no native conversation column. Proposal: mint a deterministic UUIDv5 from `actionSendId` (namespace `agent.spawn.requested.conversation`). To resolve at plan-time.
3. **Inngest function timeout vs 8 turns × 60s = 8 min wall-clock** — Inngest default function execution caps vary by tier. Verify against current Inngest config; raise if needed.
4. **Tool-use loop termination** — `stop_reason === "end_turn"` is the natural exit; `stop_reason === "tool_use"` triggers next turn. Confirm Anthropic SDK behavior on `max_tokens` hit (does it trip a third stop_reason worth handling?).
5. **Realtime subscription auth** — `action_sends` is RLS-owner-only SELECT. Confirm Supabase Realtime respects RLS on subscribed columns; if not, scope the subscription to an authed channel.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO confirms PR-A's invariant scaffolding is reusable; ADR-040 must lock loop topology (per-turn `step.run`) + BYOK lease scope (per-turn re-acquisition) + tool-surface allowlist before any code lands. Reference impls exist at `cfo-on-payment-failed.ts:199` (lease-per-step pattern) and `github-on-event.ts:208`. The `recordByokUseAndCheckCap` TS wrapper is greenfield. Critical: `cache_read_input_tokens` + `cache_creation_input_tokens` MUST flow through `persistTurnCost` or dashboard understates ~90%. ADR-039 is taken; next ordinal is ADR-040+. Complexity rating: LARGE.

### Product

**Summary:** CPO flagged ship-all-5-at-once as highest brand-trust risk for first autonomy impression and strongly recommended tiered ship; user override accepted with the substrate-completion trade-off documented. Operator UX gaps identified (in-flight progress, cancellation, per-output undo, per-spawn cost visibility) — ALL four go in PR-B per user choice. Per-class operator UX matrix carries to spec/plan: success looks like / failure looks like / recovery path per class. Spec-flow-analyzer GAPs encoded as plan ACs.

### Legal

**Summary:** CLO flagged PR-B as materially expanded vs PR-A. PA-22 register entry required; Vendor Mapping row (`article-30-register.md:412`) must be amended to add PA-22 to Activities. Anthropic Zero-Retention status must be verified pre-merge (default 30-day retention). PII-scrub TOM added to PR-B per user override (commit-author email redaction). Full DPIA, consent banner, ToS clause, Art. 22 analysis deferred to parallel work per scope choice. DPA scaffold path `knowledge-base/legal/data-processing-agreements/anthropic.md` does NOT exist — Anthropic coverage is the Vendor Mapping row only; consider scaffolding per-vendor DPA files as follow-up.

### Finance

**Summary:** CFO modeled per-spawn unit economics by class: $0.005-$0.14 with optimal routing (Haiku for classification, Sonnet for reasoning, caching ON); $0.02-$1.00 worst-case at flat 8 + no caching. Worst-case monthly exposure for 50 spawns/day mixed workload: $150-$1500/month operator-funded BYOK. Per-class max-turns recommended (overridden by user; flat 8 + $2.00 per-spawn ceiling chosen). BYOK caps for `ops@jikigai.com`: daily soft $20 / hard $50, monthly hard $500. Three distinct failure modes needed: `max_turns_reached` / `cost_ceiling_exceeded` / `byok_cap_exceeded`.

## Capability Gaps

| Gap | Domain | Why Needed |
|---|---|---|
| Prompt fixture/regression infrastructure | Engineering | No current pattern for snapshot-testing leader prompts. Recommend golden-file tests treating prompt files as code artifacts. Filed as follow-up. |
| Per-vendor DPA file scaffolding | Legal | The DPA-by-file pattern referenced in #4379 doesn't exist; Anthropic DPA is only a row in Vendor Mapping. Filed as legal-substrate follow-up. |
| Anthropic-SDK observability boundary (per-turn token/cost telemetry to operator dashboard) | Engineering | `reportSilentFallback` covers Sentry but operator-facing observability is missing. Partial coverage in PR-B via per-spawn cost visibility (Today card). |
| CVSS classification source-of-truth for `cve_alert` severity-aware prompts | Security (via Engineering) | The CVE-class leader prompt needs CVSS lookup; current substrate has no classification source. Filed as follow-up; PR-B uses GitHub Advisory `severity` field as a v1 substitute. |
| Prompt versioning across in-flight runs | Engineering | When a leader prompt is edited, do in-flight runs use old or new? Affects reproducibility. Plan-time ADR-040 must resolve: snapshot prompt-hash to `action_sends.prompt_version` (migration 065 column) so in-flight runs are deterministic against the prompt-version they started with. |

## Sharp Edges

- **ADR-039 stale:** issue #4379 cites this; ADR-040 + ADR-041 are the real ordinals. INDEX.md has known number collisions (027/030/031/033) — pre-merge guard needed.
- **No raw `@anthropic-ai/sdk` calls in `apps/web-platform/server/` today:** PR-B introduces the first `anthropic.messages.create` site. All current Anthropic traffic flows through `@anthropic-ai/claude-agent-sdk` `query()` (sub-process). The closest reference is `scripts/spike/cache-control-forwarding.ts` (SDK wrapper, not bare).
- **Stub handlers = silent telemetry undercount:** `cfo-on-payment-failed.ts:198-217` and `github-on-event.ts:207-219` return `{tokenCount:0, unitCostCents:0}` placeholders. PR-B replaces these with real `persistTurnCost` calls; the substrate-uniform replacement shape must persist `cache_read_input_tokens` + `cache_creation_input_tokens` per the cost-writer contract.
- **Per-turn lease re-acquisition is counterintuitive:** the lease CANNOT span turns. ADR-040 must explicitly spell out that only the failing turn re-acquires on retry; cached prior turns return without lease.
- **Cap enforcement: pre-call, NOT post-call.** Per learnings, fail-closed.
- **`onText` is cumulative, not delta.** If PR-B streams partial-turn output, treat as replace-not-append per `2026-05-12-pr-a1-implementation-and-multi-reviewer-convergence.md`.
- **Baseline prompt MUST enumerate available tools** or the model fabricates calls per `2026-05-05-baseline-prompt-must-declare-capabilities-or-model-fabricates-missing-tools.md`. Per-class system prompt declares the exact tool surface.
- **Inngest five-bug-cascade risk:** smoke-test end-to-end on dev Inngest, not just unit tests. Verify function registers via `/api/inngest`; signing-key parse rules match consumer expectations per `2026-05-19-inngest-substrate-five-bug-cascade.md`.
- **Migration 065 WORM trigger admit-list extension:** PR-A's migration 064 reshapes `action_sends_no_update` to admit UPDATEs on `acknowledged_at` / `artifact_url` / `failure_reason`. Migration 065 extends admit-list to include `reversal_handle`, `current_turn`, `current_turn_started_at`, `cancellation_requested_at`, `prompt_version`. Down-migration restores the prior admit-list.

## Next: `skill: soleur:plan`

Brainstorm complete. Move to plan via `skill: soleur:plan` (will auto-detect this brainstorm and load it for Phase 1 context).
