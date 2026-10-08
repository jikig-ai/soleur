---
title: "feat: support Claude Haiku 5.5 (claude-haiku-5-5) across model IDs, pricing, CLI pin, docs and tests"
date: 2026-10-08
slug: haiku-5-5-support
branch: feat-one-shot-haiku-5-5-support
issue: none
type: feat
lane: cross-domain
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-10-08. **Mechanical gates run:** User-Brand Impact (present, `aggregate pattern`), Observability (5 fields, probe command valid), Scope Check (one live section, no unmapped asks), Guard Contract (`lint-guard-contract.py`: 2 entries), PAT-shaped variables (none), UI wireframe (no UI surface), Encryption Posture (no new store or connection: skipped), Downtime & Cutover (no trigger). **Agents used:** security-sentinel, architecture-strategist, data-integrity-guardian, observability-coverage-reviewer, test-design-reviewer, framework-docs-researcher, and a verify-the-negative / self-audit sweep; plus the earlier learnings, CTO, CFO and three plan-review seats.

### Key improvements

1. Accounting claim corrected: sub-cent quantization is "immune" only for short-card turns under half a cent; turns between half a cent and 1.5 cents count a full token-count each, and a long-card turn can contribute at least 500K points to the #6945 product. Disclosed explicitly, including that delegated caps never see 0-cent rows.
2. Supply-chain compensating checks added to the CLI bump (integrity equality between lockfile and the global install, provenance attestation, lockfile diff gate, override scoped to one command, rollback trigger).
3. Observability block rewritten with layer citations and the `err = null` message-path rule for tagged Sentry events (#8629); summarizer coverage widened to `max_tokens`, `refusal`, empty text.
4. ADR scope fixed: accounting semantics move to an ADR-041 addendum; ADR-053 gets append-only supersession notes plus a dated addendum, not rewritten tables; ADR-053's own claim about `claude-code-review.yml` is respected (row 10 reclassified).
5. Test design: literal dated/undated fixtures plus pair-count floor, four distinct token types per rate card, a `cache_creation`-only boundary crossing, a $0.005 rounding-edge pin, negative controls, and an adversarial email fixture.
6. Self-audit fixes: conditional leader `effort` wording made consistent, preflight third carve-out reflected in Guard 1 and `tasks.md`, the paid `plugin-root-propagation-gate` CI side effect of the lockfile change recorded, the `apps/web-platform/infra/sandbox-canary-argv.json` path corrected, `constants.ts:25` comment and the Console runbook added to the edit list.

### New considerations discovered

- Docs are silent on `output_config.effort` and `output_config.format` in one request; the Phase 0 router cell is the first evidence either way.
- Haiku-specific doc pages say there is no server-side fallback; the generic refusals page documents `fallbacks: "default"` without excluding Haiku 5.5. The plan follows the Haiku pages (send no `fallbacks`).
- The tier-selection input (`prompt length`) is undefined for cached tokens; the superset rule can only over-attribute.

## Overview

Anthropic shipped Claude Haiku 5.5 (`claude-haiku-5-5`, a fixed id with no date suffix and no separate
alias). Soleur's Haiku tier is a single SSOT constant, `HAIKU_MODEL` in
`apps/web-platform/server/inngest/leader-prompts/constants.ts`, currently
`claude-haiku-4-5-20251001`. This plan migrates that tier to 5.5 by following the
`soleur:model-launch-review` checklist (items 1 to 6), and records, per call site, where Haiku 5.5
would be a better fit than the model in use today.

The migration is **not** a string swap, for four verified reasons:

1. **The pinned CLI does not know the id.** `@anthropic-ai/claude-code` 2.1.284 (and the Agent SDK
   0.3.284 bundle) contain zero occurrences of `claude-haiku-5-5`
   (`grep -a -c` over the installed `node_modules/@anthropic-ai/claude-code-linux-x64/claude` = 0,
   positive control `claude-sonnet-5-5` = 10). The first CLI release carrying it is **2.1.293**
   (published 2026-10-07; 2.1.291 and 2.1.292 measure 0, 2.1.293/294/295 measure 8/8/10).
   `claude-cli-pin-knows-models.test.ts` harvests `HAIKU_MODEL` and would go red. Checklist item 2b
   says this **blocks the swap**.
2. **Haiku 5.5 changes request semantics.** Adaptive thinking is on by default with effort default
   `medium`; `budget_tokens`, non-default `temperature`/`top_p`, any `top_k`, and assistant prefill
   return 400; the tokenizer yields about 30% more tokens for the same text; thinking tokens count
   against `max_tokens`. Three call sites run with `max_tokens` of 200, 256 and 1 and would silently
   truncate before emitting a text block.
3. **Pricing has two rate cards by prompt length** ($0.10/$0.50 up to 100K prompt tokens, $0.50/$2.50
   above), while `MODEL_PRICING` is a flat per-token row that feeds a WORM ledger.
4. **Verification of pricing surfaced drift in the neighbouring Sonnet row** (cache read is
   $0.10/MTok on the official page, the repo carries $0.20).

## Research Insights

### Premise Validation (Phase 0.6)

Checked what the brief cites by reference:

- **PR #9236 (Sonnet 5.5 migration)**: merged (`6d27cd17da chore(models): migrate Claude Code to claude-sonnet-5-5 (#9236)`). Holds; used as the shape to mirror.
- **#8643 "agent-sdk bundled CLI model-id gate"**: the brief lists it as a prior launch to mirror. **It is OPEN, not merged** (`gh issue view 8643`: state OPEN, "ci(models): gate that the pinned claude-agent-sdk bundled CLI knows the Agent SDK model ids"). There is no SDK-bundle gate to mirror; the existing guard (`claude-cli-pin-knows-models.test.ts`) covers only `@anthropic-ai/claude-code`. Stale premise, handled in Phase A and the Open Code-Review Overlap section.
- **#6941 "haiku pricing row"** and **#6934 (unknown id halves max_tokens)**: both are historical fixes whose lessons apply; confirmed via learnings.
- **#8601 / #6934**: CLI-only bump precedent for the `sdk-bump-verified:` ack naming the hook control.
- **Cited code paths** (`model-tiers.ts`, `domain-router.ts`, `email-triage/summarize.ts`, `leader-prompts/*`, `.claude/hooks/agent-token-tee.sh`, `.github/actions/anthropic-preflight/action.yml`, `.github/workflows/ci.yml`, sandbox-canary scripts, `components/settings/api-usage-section.tsx`, ADR-053/083/110, `MODEL_PRICING`): all present on the branch. Two are corrected: `agent-token-tee.sh` only mentions the `haiku` alias in a comment (no id), and `api-usage-section.tsx` only says "Haiku" in prose (no id, no price). Neither needs an edit.
- **ADR corpus vs the proposed mechanism**: ADR-053 explicitly keeps founder-BYOK and operator-key crons out of re-tiering ("re-tiering a cron ... is a separate clo-attestation-class model-bump PR"). The "check for better-suited locations" half of the ask therefore produces a verdict table and tracked follow-ups, not silent re-tiering (see Phase E).
- **Pricing source**: verified live from `https://platform.claude.com/docs/en/about-claude/pricing.md` on 2026-10-08 and cross-checked with the bundled `claude-api` skill (`shared/model-migration.md` "Migrating to Claude Haiku 5.5").

### Coordinator-supplied launch facts, reconciled (2026-10-08)

The launch post facts passed in by the coordinator were checked against the pricing page and the bundled `claude-api` skill (`shared/models.md`, `shared/model-migration.md`). Agreement and gaps:

- **Model id, release date, tiered pricing (both cards), Haiku 4.5 comparison, Sonnet 5.5 cache read cut to $0.10 (and $2 / $10 / $2.50 write)**: all agree with the pricing page. The Sonnet cut is therefore not a possible drift but a confirmed repo discrepancy (the repo row says $0.20); Phase B item 4 applies it, gated only on the Phase 0 refetch. The post leaves batch pricing unstated; the pricing page states Haiku 5.5 batch at $0.05 / $0.25 (short card) and $0.25 / $1.25 (long card). No repo path uses the Batch API for Haiku, so no row is added.
- **Context window and max output (gap in the post)**: verified from `shared/models.md`: **1M context, 128K max output**, status Active (Haiku 4.5: 200K / 64K). Consequence: a leader or summarize prompt can now legally exceed 100K tokens, so the long-prompt card is reachable, not theoretical (Guard 2 covers it).
- **Effort setting**: first Haiku-class model with `low | medium | high | xhigh | max`, default `medium` (the bundled CLI row also reads `medium`). Used here as the thinking-budget control for small-`max_tokens` classification (Phase C). The effort/model router (#6000, open) is a future consumer and is out of scope; Phase E item 12 records it.
- **Tokenizer**: about 30% more tokens; covered in Risks and Phase 0.
- **Recommended uses** (summaries, compaction, DB queries, classification, subagent lookups, live support, browser/computer use) and **NOT for complex agentic coding**: applied as the fit test in Phase E. Complex agentic coding sites (`cron-bug-fixer`, the Concierge runtime, `fix-constraints-stage-a.yml`, the leader reasoning classes) are explicit "do not move" rows.
- **Safeguards**: Haiku 5.5 can return `stop_reason: "refusal"` with `stop_details.category` in `cyber | bio | frontier_llm | general_harms`; cyber safeguards are stricter than Haiku 4.5, looser than Sonnet 5.5, and pentest-style prompts stay blocked; there is **no server-side fallback** (do not send `fallbacks`). Consequence for the two Haiku leader classes: `triage.p0p1_issue` reads issue bodies that can be security-flavored, so a refusal on a legitimate vulnerability report is newly possible. The leader loop already ends non-`end_turn`/`tool_use` stops through `persistFailure` (the `refusal` branch at `agent-on-spawn-requested.ts` near line 810), which is the correct client-side handling; Phase C adds a regression test that a refusal turn on a Haiku class lands in that branch with the category in `extra`, and Phase E keeps `security.cve_alert` on Sonnet 5.5 (never-downgrade and cyber-flavored).
- **No deprecation of older Haiku models** is announced: the Haiku 4.5 swap is a migration for cost and support-currency reasons, not a forced retirement, which is why the SDK-path scripts can stay on 4.5 without urgency.
- **Platforms and SDKs**: the beta computer/browser-use SDK support does not touch Soleur (no computer-use callers; grep for `computer_20250124` and `browser_toolset` returns nothing in `apps/` and `plugins/`).

### Property List (Phase 0.6b)

- **P1** Every runtime caller that selects "Haiku" resolves to `claude-haiku-5-5` through the SSOT constant, and no config-class file carries a Haiku 4.5 id except an enumerated, documented carve-out.
- **P2** Each Haiku caller still returns usable output under Haiku 5.5's semantics: a text block is present at the call's output budget (the original, or the raised budget the Phase 0 probe justifies), with no silent empty-string fallback.
- **P3** Turn cost for Haiku 5.5 leader-loop turns is attributed from the correct rate card, and an unpriced model still fails closed.
- **P4** The pinned `claude-code` CLI knows the id, tier default efforts are unchanged or consciously re-reviewed, and the SDK-bump sandbox gate is satisfied honestly.
- **P5** The model-launch drift detector and its tests know the new tier, stay single-hop, and keep reporting real stragglers.
- **P6** Docs, ADR-053, the plugin tier-policy text, and the eval harness provider list reflect Haiku 5.5.
- **P7** Every other place that could use the cheap tier has a recorded verdict, and each non-adopted candidate has a tracked follow-up.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Verdict |
|---|---|---|
| Bump `@anthropic-ai/claude-agent-sdk` 0.3.284 to 0.3.293 | P1 for the two canary scripts only | **Cut.** The SDK bundle is the sandbox (bwrap) argv builder; a bump re-opens `sdk-bump-sandbox-gate` capture and the committed canary fixture (`apps/web-platform/infra/sandbox-canary-argv.json`, `sdkVersion 0.3.284`). The only gain is a cheaper paid turn on two rarely-run scripts. Carve those two scripts out of the audit instead (Guard 1). |
| Fold #8643 (SDK-bundle model-id gate) into this PR | P4 | **Cut, acknowledged.** The SDK path receives no new id in this PR (SDK stays 0.3.284), and the gate needs a named-constant refactor in the Concierge runtime. Re-evaluation note goes on #8643. |
| Bump `claude-code-action` pin (v1.0.236, tip v1.0.246) | pin freshness | **Cut.** #2540 invariant: bump only when coupled to a `--model` change in the same workflow. No workflow changes its `--model` here (all four pin `claude-sonnet-5-5`). Pin freshness stays reported flag-only by the audit. |
| Re-tier any cron, workflow pin or CI workflow to Haiku 5.5 in this PR | P7 | **Cut.** ADR-053 makes re-tiering a separately attested change; Phase E records verdicts and files follow-ups with an eval gate. |
| `Math.max(1, ceil())` interim in `cost-writer.ts` (CFO suggestion) | P3 | **Cut.** With #6945's dimensional bug (`token_count * unit_cost_cents` summed against a cents budget) a 1-cent floor makes every Haiku turn contribute its full token count, so a single 20K-token turn would trip a 2000-point cap. Fixing quantization without fixing the product is worse than the status quo. Handled by acknowledging #6945 with new numbers. |
| `LeaderPromptModule.effort` + `promptVersion` bump for the Haiku leader classes | P2 for the 4096-token leader loop | **Cut by default (plan review: two seats).** The budget is large and the prompt text is unchanged; kept only as a conditional activated by a probe showing truncation (Phase 0 item 3). |
| Per-message effort, task budgets, compaction, tool search on Haiku | none requested | **Cut.** Not needed for parity. |
| A generic rate-card registry | P3 | **Cut.** One optional field on `ModelPricing` is the minimum that expresses two cards. |

### Findings that shape the plan

- **CLI bundle, measured** (2026-10-08, `npm pack @anthropic-ai/claude-code-linux-x64@<v>` unpacked outside the repo, `grep -a`): id absent in 2.1.284/2.1.290/2.1.291/2.1.292; present from 2.1.293. In 2.1.293 the model-table rows read `default_effort:"medium"` for `claude-opus-5-5`, `claude-sonnet-5-5` and `claude-haiku-5-5`, so `REVIEWED_DEFAULT_EFFORT` (audit `medium`, execution `medium`) does not move and `AUDIT_EFFORT = "high"` needs no re-decision. The same 2.1.293 bundle resolves the `haiku` alias to `claude-haiku-5-5` (`haiku:"claude-haiku-5-5"`), so the five `model: haiku` research agents and every `'cheap'` workflow pin follow automatically on a CLI at or above 2.1.293. No repo edit; effect recorded in Phase E.
- **Capability flag to resolve live**: the bundled Haiku 5.5 row lists `rejects_disabled_thinking`, while the API migration guide says `thinking: {"type":"disabled"}` is accepted at effort `low`, `medium`, `high`. The plan does not depend on that question: Phase C uses `output_config.effort: "low"` with adaptive thinking (valid under both readings) and raises `max_tokens` headroom; a live probe then validates it.
- **Pricing, verified** (pricing page, 2026-10-08), USD per MTok:

| Card | Input | Output | 5m cache write | 1h cache write | Cache read |
|---|---|---|---|---|---|
| Haiku 5.5, prompt up to 100,000 tokens | 0.10 | 0.50 | 0.125 | 0.20 | 0.01 |
| Haiku 5.5, prompt over 100,000 tokens | 0.50 | 2.50 | 0.625 | 1.00 | 0.05 |
| Haiku 4.5 (being replaced) | 1.00 | 5.00 | 1.25 | 2.00 | 0.10 |
| Sonnet 5.5 (page) | 2.00 | 10.00 | 2.50 | 4.00 | **0.10** (0.05x; repo has 0.20) |

  The page does not define whether cached tokens count toward the 100,000. Resolution: select the card on `input + cache_read + cache_creation` tokens (a superset), which can only over-attribute (the safe direction for a cap input). The boundary follows the page literally ("over 100,000 tokens"): strictly greater than 100,000 selects the long card.

- **Quantization amplification (#6945)**: at the new rates a representative leader turn costs $0.0025 at 20K uncached input plus 1K output and about $0.0007 when mostly cache reads, and both round to 0 cents under `Math.round(x * 100)`. For short-card turns under half a cent this puts Haiku-class leader runs on the "structurally immune to the cap" side of the cliff described in #6945. That is not the whole picture: a turn between $0.005 and $0.015 (roughly 50K to 150K uncached input tokens on the short card) rounds to 1 cent and then contributes its full token count to the cents-times-tokens sum, and a long-card turn (prompt over 100K tokens, now reachable with a 1M window) costs at least 5 cents and contributes at least 500K points, which exceeds the default cap on a single turn. Both are low-likelihood (an 8-turn loop on bounded inputs) but real, and a 0-cent row is permanent in the WORM ledger, so delegated hourly and daily caps never see that Haiku spend. Layer 3 still bounds money: 8 turns x 4096 output tokens is about $0.016 of output on the short card and about $0.082 on the long card, plus input. Disclosed in the PR body and the #6945 comment; fixed there, not here.
- **Call-site audit of the Haiku callers**:

| Caller | Mechanism | Budget | Haiku 5.5 hazard |
|---|---|---|---|
| `server/domain-router.ts:154` | raw `fetch`, literal id, `output_config.format` json_schema | `max_tokens: 200` | thinking tokens can exhaust 200 before a text block; fallback silently returns `["cpo"]` |
| `server/email-triage/summarize.ts` | `@anthropic-ai/sdk`, `HAIKU_MODEL` | `max_tokens: 256` | same truncation; empty `raw` becomes an empty stored summary |
| leader loop `triage.p0p1_issue`, `knowledge.kb_drift` | SDK `messages.create` with tools, 8 turns | 4096 per turn | thinking at `medium` can end a turn at `max_tokens`, which `persistFailure`s the run; thinking blocks are echoed back unchanged by the loop (append-only, good) |
| `.github/actions/anthropic-preflight` | `curl` | `max_tokens: 1` | unknown whether a thinking-on 1-token request still returns 200; Sonnet 5.5 (thinking on) already works at `max_tokens: 1` in `cron-anthropic-credit-probe.ts`, which is encouraging but not proof |
| `scripts/learning-retrieval-bench.sh` | `curl`, parses first text block | per script | none known; reads by type already |
| `sandbox-canary.mjs`, `plugin-root-sandbox-propagation-probe.mjs` | Agent SDK `query()` (SDK-bundled CLI, 0.3.284) | not applicable | SDK bundle does not know the id: **keep `claude-haiku-4-5`** (carve-out) |

- **Institutional learnings applied** (from the learnings sweep): `2026-07-25-a-stale-presence-guard-fails-green-and-an-unknown-model-id-halves-max-tokens` (bundle grep needs `-a` with positive and negative controls; guards must derive ids from the SSOT, not restate literals), `2026-02-22-model-id-update-patterns` (grep every spelling, re-grep after editing), `2026-04-18-action-pin-sync-with-model-bump`, `2026-06-11-model-launch-review-skill-build-premise-corrections` (pricing is flag-only, hand-edited from the source), `2026-10-06-fail-closed-fix-must-sweep-all-writers-and-producers` (an unpriced model must be NaN, never 0, in a WORM ledger), `2026-09-23-my-guards-read-source-through-a-stripper-that-deleted-the-code` (no `/*` inside a `//` comment in `model-tiers.ts`), `workflow-patterns/2026-09-29-detached-precommit-watchdog-and-sdk-bump-attestation` (the `sdk-bump-verified:` trailer, orphan watchdog for background commits).

## Research Reconciliation: Brief vs Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "claude-code-action pins" need updating | Four workflows pin `claude-code-action@...# v1.0.236` (tip v1.0.246) and all four pass `--model claude-sonnet-5-5`; none uses Haiku. | No `--model` swap, so no pin bump (#2540). Report pin age in the PR body (flag-only). |
| "#8643 (agent-sdk bundled CLI model-id gate)" is a prior launch | Open, deferred issue; no SDK-bundle gate exists. | Acknowledge, keep SDK pinned, comment on #8643. |
| "Check the claude-agent-sdk / claude CLI pin knows claude-haiku-5-5" | Neither does (0 hits); CLI 2.1.293 and SDK 0.3.293 do. | Bump the CLI pin only (Phase A); carve out the SDK-path scripts. |
| `agent-token-tee.sh`, `api-usage-section.tsx` listed as Haiku references | Neither contains a model id or a price. | No edit. |
| "pricing/tier maps" | One tier map (`MODEL_PRICING`) plus prose tier tables in ADR-053 and `plugins/soleur/AGENTS.md`. | Phase B (code) and Phase D (prose). |

## Implementation Phases

Ordering follows the guard dependency: the CLI test forces the pin before the constant; tests are written red first (`cq-write-failing-tests-before`). Commit boundaries are the seams so each can be reverted alone.

### Phase 0: Evidence before edits (read-only)

1. Re-fetch the pricing page and confirm the Haiku 5.5 two-card table and the Sonnet 5.5 cache-read figure; paste the two lines into the PR body.
2. Live probe (only when an Anthropic key is reachable through the project secret store without printing it; otherwise record "unverified-live" and ship the conservative configuration below). Handling rules: use a dev or probe key, never the production BYOK or operator key; read it through the secret store's `run` wrapper into the child's environment, never as an argument, never echoed, no `set -x`, and pass headers from a 0600 file (`curl -H @file`) rather than on the command line where `ps` shows them; scripts live in the scratchpad with `umask 077`, are deleted afterwards, and log only status, `stop_reason`, block types and `usage`. Two cells per caller shape, N=5 each on synthesized inputs (`cq-test-fixtures-synthesized-only`): (a) the default request at the caller's original `max_tokens` (200 router, 256 summarizer, 1 preflight, 512 retrieval bench, 4096 with a tool definition for the leader loop), (b) the same with `output_config.effort: "low"`. The router cell (b) sends `effort` and `format` (json_schema) together, a combination the docs neither allow nor forbid. Add one security-flavored synthesized issue body (a described, non-exploit vulnerability report) to the `triage.p0p1_issue` leader cell to measure the refusal rate on legitimate security triage. Record per cell: HTTP status, `stop_reason`, `stop_details.category` when present, whether a `text` (or `tool_use`) block exists, `usage.output_tokens`.
3. Decision rule: the **router and summarizer ship with `effort: "low"`** and a budget raised to 1024 if cell (b) still truncates. The **leader loop ships with no extra field** (no `effort` plumbing, no `promptVersion` bump) unless cell (a) at 4096 shows truncation or a `max_tokens` stop on either Haiku class, in which case Phase C item 3 is activated. `thinking: {"type":"disabled"}` is not probed and not used (capability-flag ambiguity, see Risks). If the `effort` plus `format` combination is rejected (HTTP 400) the router drops `effort` and ships a raised budget alone. A non-zero refusal rate on the security-flavored leader cell is recorded in the PR body and the ADR addendum and becomes the lead item of follow-up (b); it does not change this PR's model assignment.
4. The preflight cell (`max_tokens: 1`, default thinking) decides its swap: HTTP 200 swaps the action to `claude-haiku-5-5`; anything else keeps it on its current id and adds it to the audit carve-out (Guard 1) with a dated reason. No request parameter is added to a liveness check.

### Phase A: CLI pin (RED then GREEN)

1. RED: change `HAIKU_MODEL` locally and run `./node_modules/.bin/vitest run test/server/inngest/claude-cli-pin-knows-models.test.ts`; expect the id-set guard to fail on 2.1.284. Revert; this is the proof the guard bites.
2. Bump `@anthropic-ai/claude-code` 2.1.284 to **2.1.293** in `apps/web-platform/package.json`, the `npm install -g` line in `apps/web-platform/Dockerfile` (currently line 62), and regenerate `package-lock.json` with `cd apps/web-platform && npx --yes npm@11 install --package-lock-only --min-release-age=0`. Leave `.npmrc` untouched. Leave `@anthropic-ai/claude-agent-sdk` at 0.3.284.
3. Release-age floor: 2.1.293 was published 2026-10-07T17:18Z, inside the 3-day floor until 2026-10-10T17:18Z. Using the one-off override is the documented model-launch-review flow; disclose it under a "Supply-chain floor override" heading in the PR body with evidence: the exact version, `npm view @anthropic-ai/claude-code@2.1.293 dist.integrity`, that 2.1.294 and 2.1.295 shipped afterwards without a deprecation notice, and that the override is one-off. If work resumes after the floor has lapsed, skip the override. Compensating checks, all recorded in the PR body: (i) `npm view @anthropic-ai/claude-code@2.1.293 dist.integrity` equals the `integrity` of that version's entry in the regenerated `package-lock.json`, and the same for the `claude-code-linux-x64` platform package, so the global install in the `Dockerfile` (which resolves independently of the lockfile) is pinned to bytes already reviewed; (ii) `npm audit signatures` (or `npm view ... dist.attestations`) reports a valid registry signature or provenance statement for both packages; (iii) a lockfile diff gate: the diff may touch only the `@anthropic-ai/claude-code*` entries, with no new `resolved` host, no new `hasInstallScript`, and no other dependency younger than 3 days; (iv) the override flag appears on that one regeneration command only, and `.npmrc` is untouched; (v) rollback trigger: any red cron smoke run, any new `hasInstallScript`, or a yanked 2.1.293 reverts the pin commit to 2.1.284 together with the constant. Lockfile churn also triggers the paid `plugin-root-propagation-gate` CI job (`ci.yml`, keyed on `package-lock.json`) through the unchanged SDK 0.3.284 on `claude-haiku-4-5`; that is expected and needs no edit.
4. Re-run the bundle table read for `REVIEWED_DEFAULT_EFFORT` (already measured medium/medium in 2.1.293) and extend the test's header comment with the 2026-10-08 date and the new version. Add no Haiku row to `REVIEWED_DEFAULT_EFFORT` (the Haiku id never reaches the cron CLI; it is covered by the id-set guard).
5. Satisfy `sdk-bump-sandbox-gate.sh` for a CLI-only bump: the commit trailer `sdk-bump-verified:` must name the control the CLI actually moves, per model-launch-review SKILL.md (#8601): probe `cron-bash-allowlist-hook.mjs` with `npx -y @anthropic-ai/claude-code@<v> -p --output-format json --model claude-sonnet-5-5` (an id **both** 2.1.284 and 2.1.293 know; 2.1.284 cannot resolve `claude-haiku-5-5`, so a Haiku 5.5 probe would make the old-version control fail on model resolution instead of on the hook) asking for a non-allowlisted `echo`, require the command in `.permission_denials[]`, with 2.1.284 as the control. Background commits need `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1 setsid`. Add one smoke run per tier on the new CLI so a CLI regression is not blamed on Haiku: `npx -y @anthropic-ai/claude-code@2.1.293 -p --output-format json --model <claude-sonnet-5-5 | claude-opus-5-5 | claude-haiku-5-5>` (Haiku 5.5 is new-version only) with a trivial prompt, requiring a result event with no `Unknown --effort` warning and non-empty `result`. The pin commit is not independently revertible once the constant depends on it; the PR body says so.
6. Sweep `git grep -n "2\.1\.284"`: the Dockerfile, `package.json` and the lock move; references to "vendored CLI 2.1.284" in `agent-runner-sandbox-config.ts` and sandbox tests describe the **SDK-bundled** builder (still 0.3.284) and stay; `c4-likec4-version-pin.test.ts` fixtures are synthetic strings and stay.

### Phase B: SSOT constant and pricing (billing constant, separate commits)

1. RED tests first in `apps/web-platform/test/server/inngest/model-tiers.test.ts`: `HAIKU_MODEL` equals `claude-haiku-5-5`; each Haiku card pinned with the source line and date, using a case that prices **all four token types with distinct values on each card** so a single-field swap on either card reds; boundary cases at exactly 100,000 (short card, with a nonzero cache split) and 100,001 reached once through `input_tokens` and once through `cache_creation_input_tokens` alone; the cache-heavy case (cache tokens push the prompt over 100K while `input_tokens` alone would not); an unpriced model returns NaN; the key set is compared to a literal list `[SONNET_MODEL, HAIKU_MODEL]`, not only to the type union; a $0.005 rounding-edge case pinning today's `Math.round(x * 100)` behaviour so a future fix to #6945 is a deliberate test change.
2. `constants.ts`: `HAIKU_MODEL = "claude-haiku-5-5" as const` (alias == id, like Sonnet 5.5 and Opus 5.5); update the doc comment (`LeaderPromptModule` changes only if the conditional Phase C item 3 activates).
3. `agent-on-spawn-requested.ts`: extend `ModelPricing` with an optional `longPrompt` card: `{ aboveTokens: 100_000, inputPerToken, outputPerToken, cacheReadPerToken, cacheCreatePerToken }`. `resolveTurnCostUsd` computes `promptTokens = input_tokens + cache_read_input_tokens + cache_creation_input_tokens` and uses the long card when `promptTokens > aboveTokens`. Replace the Haiku 4.5 row with the Haiku 5.5 row (short card 0.10/0.50/0.01/0.125 per MTok; long card 0.50/2.50/0.05/0.625), with the pricing page URL and 2026-10-08 in the comment. Remove the Haiku 4.5 row: the key set must equal the `AnthropicModelId` union (`model-tiers.test.ts`), and `leaderModule.model` is read per step so no in-flight turn can look up 4.5 after deploy. Keep the 5-minute cache-write assumption note (the call site passes no `ttl`).
4. **Sonnet 5.5 cache-read correction, own commit**: set `cacheReadPerToken` to 0.10/M only if the Phase 0 refetch still shows $0.10 **in both places on the page** (the model-pricing table footnote and the prompt-caching multiplier paragraph; the bundled `claude-api` skill still says $0.20, so two agreeing statements from the authoritative page are required, since the written value is permanent in the WORM ledger) (page footnote: "Cache hits ... on Claude Opus 5.5 and Claude Sonnet 5.5 are priced at 0.05x the base input price"). Record the change as a regime boundary by appending to the existing 2026-09-03 #7774 note in the row comment (and correcting its "~10% of input" cache-read wording, which is wrong for Sonnet 5.5) with the merge SHA and UTC time added at ship; the WORM ledger has no model column, so earlier rows are not restated and rolling cap windows will blend (safe direction: attribution only decreases). The bundled `claude-api` skill still lists $0.20 for Sonnet 5.5; the official pricing page is the authority, and the discrepancy is stated in the PR body. If the refetch disagrees with this plan, leave the Sonnet row untouched and file an issue instead.
5. Sweep other readers of the rate fields: `git grep -nE "inputPerToken|MODEL_PRICING|resolveTurnCostUsd"` (currently only `agent-on-spawn-requested.ts`, `model-tiers.ts` comments and tests); update the `constants.ts` line-25 comment mentioning `MODEL_PRICING` and the `model-tiers.ts` header comments (the "mixed alias/dated convention" paragraph now lists three aliases and no dated id; do not put `/*` inside a `//` comment).
6. `PER_SPAWN_COST_CEILING_CENTS` stays 260 (ADR-041; it is a dollar promise, not a token budget). Add one sentence to its docstring that Haiku 5.5 turns are far below it. ADR-041 lines 133 and 141 say Layer 2 bounds a misbehaving Haiku class; with sub-cent turns rounding to 0 cents only Layer 3 enforces that, which the ADR-041 addendum records.

### Phase C: Call-site adaptation

1. `domain-router.ts`: keep a literal `claude-haiku-5-5` (importing `HAIKU_MODEL` is not done: the module stays leaf-light) and add a parity assertion in the test comparing the literal with `HAIKU_MODEL`. Apply the Phase 0 configuration: `output_config: { effort: "low", format: ... }`, with `max_tokens` raised only if the probe requires it. Add a `reportSilentFallback` mirror on the **message path with `err = null`** (an `Error` argument is captured by the pino mirror first and the tagged event is deduplicated away, #8629), `feature: "domain-router"`, bare-verb op `no-text-block` (`feature` carries the module name), firing on an absent or empty text block, a `max_tokens` stop, or a `refusal`. Its `extra` carries exactly `stop_reason`, `stop_details.category` when present, and `model`; a test asserts the exact key set and plants a sentinel in the user message that must appear nowhere in the event. The existing `catch` `log.error` gains `stop_reason` too, so an `end_turn` with unparseable JSON is distinguishable. Import `reportSilentFallback` from `@/server/observability` (imports: `@sentry/nextjs`, the logger, PII helpers; none is the octokit graph `_cron-shared` pulls in); `anthropic-text-block-parity.test.ts` plus a check that `domain-router.ts` still reaches no `octokit` module guard this. This makes the existing silent `["cpo"]` fallback visible (`cq-silent-fallback-must-mirror-to-sentry`). Update the #8392 test comment, which says this path "emits no thinking block": it now does. Add one adversarial synthesized fixture (an email-like message saying to ignore the instructions and route elsewhere) and keep the leader-ID allowlist validation as the only path from model output to a leader.
2. `email-triage/summarize.ts`: the same effort handling and budget decision; mirror through `reportSilentFallback` on the message path (`err = null`, `feature: "email-triage"`, bare-verb op `no-text-block`) on an absent or empty text block, a `max_tokens` stop, or a `refusal`, with the same exact-key `extra` (`stop_reason`, `category`, `model`) and a sentinel test over subject, sender and body (TR3). Never pass the SDK error object (its message can embed request fragments); the existing credit-exhausted branch is untouched. Add the same adversarial synthesized fixture (a body instructing the summarizer to change its output) to `summarize.test.ts`.
3. Leader loop (**conditional**, only when the Phase 0 leader-shape cell shows truncation): add optional `effort?: "low" | "medium" | "high"` to `LeaderPromptModule`, set `"low"` on `triage.p0p1_issue` and `knowledge.kb_drift`, pass `output_config: { effort }` only when defined, bump both `promptVersion`s to `v1.1.0` (this labels new runs' `action_sends.prompt_version`; it does not change how an already-suspended run replays), and assert in `prompt-version-stability.test.ts` that the Haiku classes carry it. Otherwise the leader modules change only through `HAIKU_MODEL`, and `prompt-version-stability.test.ts` needs no edit beyond its existing model assertions (which already read the constant).
3b. Refusal handling (new on Haiku 5.5): send no `fallbacks` parameter on any Haiku request (the Haiku-specific doc pages say no server-side fallback exists; the generic refusals page documents `fallbacks: "default"` without naming Haiku 5.5, so any change to this stance needs a live cell). Add one assertion to the existing leader-loop test that a Haiku-class turn returning `stop_reason: "refusal"` ends in the existing `persistFailure` branch with `reason: "leader_refused"` and `category` in `extra`; that path already reaches Sentry through `reportSpawnDeadLetter`. For the router and summarizer a refusal takes the mirrored fallback from items 1 and 2. A legitimately security-flavored issue body refused on `triage.p0p1_issue` is therefore dead-lettered and visible, not silently dropped; any retry-on-Sonnet routing is a new mechanism and belongs to follow-up (b), informed by the Phase 0 refusal-rate cell.
4. `.github/actions/anthropic-preflight/action.yml`: swap the id to `claude-haiku-5-5` **only if** the Phase 0 preflight probe returns 200; else carve out per Phase 0 step 4.
5. `scripts/learning-retrieval-bench.sh` `MODEL_ID` to `claude-haiku-5-5` (reads the first text block by type already; add `output_config.effort: "low"` to its `jq` request body if the probe shows truncation at its `max_tokens`).
6. Test fixtures: `test/helpers/anthropic-stub.ts` default model, `test/sandbox-credential-deny-runtime.test.ts` literal (a runtime test; check whether it exercises a real CLI that needs a known id before editing), `test/domain-router.test.ts`.

### Phase D: Audit tooling, skill, docs, eval harness

1. `audit-models.sh`: add `claude-haiku-4-5-20251001=claude-haiku-5-5` and `claude-haiku-4-5=claude-haiku-5-5` to `AUTOFIX_PAIRS` (both spellings: the id boundary means the undated pair does not match the dated id). Both RHS are the current id, so `assert_single_hop` stays satisfied. Add the SDK-path carve-out for exactly `apps/web-platform/scripts/sandbox-canary.mjs` and `apps/web-platform/scripts/plugin-root-sandbox-propagation-probe.mjs` (plus `.github/actions/anthropic-preflight/action.yml` only when its Phase 0 probe fails; `EXCLUDE_RE` has no `.github` exemption today, so without that third entry `--detect` would exit 10 on the branch) to the exclusion pattern with a comment naming #8643 and the SDK pin, and update the `echo` guidance block in `[2b]`/`[3]` if it enumerates tiers. Rephrase the `scripts/lint-anthropic-content-position.py` docstring so it no longer carries a bare `claude-sonnet-5` token (the detector reports it today: `--detect` exits 10 on this branch for that file alone, a permanently red drift signal unrelated to Haiku).
2. `plugins/soleur/test/model-launch-review.test.ts`: `CURRENT_IDS` gets `claude-haiku-5-5` in place of the dated 4.5 id; the synthesized `[2b]` fixtures that embed `claude-haiku-4-5-20251001` as a "current" id move to `claude-haiku-5-5`; add the carve-out test and the two-spelling pair test (derived from the live pair table through `parseAutofixPairs`, not restated).
3. `model-launch-review/SKILL.md`: add "Haiku 5.5" to the lineage line (`Opus 4.6 -> ... -> Sonnet 5.5 -> Haiku 5.5`), update the `[2b]` probe example's `--model` from `claude-haiku-4-5` to an id that both the old and the new pin know (`claude-sonnet-5-5` today) and say why, and add two sharp edges learned here: (a) a model with a prompt-length-tiered price needs the tier boundary pinned, and the audit's pricing flag cannot see it; (b) a carve-out for SDK-bundled consumers must name the pin whose bump retires it.
4. `eval-harness`: run `bash plugins/soleur/skills/eval-harness/scripts/gen-models.sh` to regenerate `models.generated.json` (the generator is the sole writer; the file is excluded from the sweep by design); run `plugins/soleur/skills/eval-harness/test/gen-models.test.sh`. The README's dated delta record (haiku-4-5, 2026-06-15) is history and stays.
5. Docs prose, hand-edited next to each swapped id because the sweep fixes the id but not adjacent price text: `agent-native-architecture/references/{agent-execution-patterns,agent-native-testing,architecture-patterns,mobile-patterns}.md` (mobile-patterns line "claude-haiku-4-5: ~$1/1M input, $5/1M output" becomes ~$0.10/$0.50), `dspy-ruby/SKILL.md`, `dspy-ruby/references/providers.md` ("Haiku 4.5" lists and `anthropic/claude-haiku-4-5`).
6. `plugins/soleur/AGENTS.md` "Model Selection Policy": refresh only the Haiku figures in the pricing-basis paragraph (Haiku 5.5 is $0.10/$0.50 up to 100K prompt tokens) and add one clause that the `haiku` alias resolves to 5.5 on CLIs at or above 2.1.293.
7. ADR-053 amendment, append-only (its convention: recorded tables stay as recorded, supersession is a dated blockquote note, additions are dated addenda): a supersession note on surface row 5a (founder BYOK domain routing now on `claude-haiku-5-5`) and on the 2026-09-03 tier table (Haiku 4.5 row superseded by 5.5, with the cache-read comparison restated at cache-read rates because ADR-053 itself established that cache read dominates a multi-turn spawn), then a dated addendum "Haiku 5.5 launch re-evaluation" carrying the Phase E verdicts, the SDK-path carve-out (so the ADR does not say the tier is 5.5 while two scripts stay on 4.5), and the re-evaluation trigger. Correct the citation: re-tiering a cron as a separately attested change comes from the `model-tiers.ts` header comment, not ADR-053 text (ADR-053 line 19 applies clo-attestation to the workflow allowlist). Also record that the Sonnet cache-read correction makes ADR-053 lines 144 to 150 (Fable 5.1 at "1.25x Sonnet" cache-read), line 218 and the line-207 trigger stale in the same append-only way. No new ADR.
7b. ADR-041 addendum (the ledger semantics live there, not in ADR-053): the optional `longPrompt` rate card and the superset prompt-token rule, the Sonnet 5.5 cache-read regime boundary (appended to its 2026-09-03 amendment about the undated regime boundary), and the statement that with sub-cent turns rounding to 0 cents Layer 2 does not bound a Haiku class (lines 133 and 141), only Layer 3 does. ADR-053 keeps a one-line pointer.
8. The two launch-checklist items (re-read the `longPrompt` boundary for any prompt-length-priced model; re-verify each small-`max_tokens` caller's effort/thinking behaviour) live in `model-launch-review/SKILL.md` sharp edges only, not in the ADR. The compound learning is written at ship, not tracked here.
9. `knowledge-base/engineering/operations/runbooks/anthropic-console-workspace-key.md` (lines 48 and 77) mirrors the preflight probe with `claude-haiku-4-5-20251001` at `max_tokens: 1`; it follows the Phase 0 preflight verdict (swap to `claude-haiku-5-5` on 200, otherwise leave it and state why in one line). The audit excludes `knowledge-base/**`, so this surface is edited by hand and checked by AC15.

### Phase E: Where Haiku 5.5 fits better (evaluation deliverable)

Method: inventory by independent grep of every model-selecting site (`EXECUTION_MODEL`, `AUDIT_CLI_ARGS`, `SONNET_MODEL`, workflow `model:` pins, agent frontmatter, CI `--model`), then judge each against ADR-053's rule (mechanical, bounded, user-data-free steps may go cheap; never-downgrade list excluded). Price context: headline input is 20x cheaper than Sonnet 5.5 on short prompts and about 4x above 100K prompt tokens; on cache reads (the dominant component of a multi-turn spawn, per ADR-053's own correction) the gap is 10x on the short card ($0.01 vs $0.10) and about 2x on the long card ($0.05 vs $0.10). The tokenizer inflation (about 30% more tokens) is already inside per-token terms.

| # | Site | Today | Haiku 5.5 verdict | Reason / action |
|---|---|---|---|---|
| 1 | domain-router, email summarize, `triage.p0p1_issue`, `knowledge.kb_drift` | Haiku 4.5 | **Move to 5.5** (this PR) | Classification shape; same tier. |
| 2 | Five `engineering/research/*` agents (`model: haiku`) | alias | **Follows when the operator's own Claude Code resolves the alias to 5.5** | This repo's pin does not control it: the plugin runs in whatever Claude Code the user has, and a CLI at or above 2.1.293 resolves `haiku` to 5.5 (ADR-053 line 39 calls this silent retargeting). Expect thinking-on token growth per agent, offset by about 10x lower rates. Measure with the ADR-053 line-32 transcript-grep recipe in a real `/plan` run, not by assumption; no edit. |
| 3 | Workflow `'cheap'` pins (`file:${fid}`, `fetch:round-${round}`) | alias | **Follows with the same alias mechanism** | Same caveat and the same measurement recipe. |
| 4 | `cron-anthropic-credit-probe.ts` (hourly, `maxTokens: 1`, `EXECUTION_MODEL`) | Sonnet 5.5 | Fits, **immaterial** | Cost is about 0.00002 USD per call; the probe's value is key liveness, not model parity. No change; revisit only if it moves to the shared helper's tier. |
| 5 | `pdf-chapter-router.ts` (`ROUTING_MODEL`, Agent SDK `query()`) | Sonnet 5.5 | **Candidate** | Routing/classification shape and `AMBIGUOUS` sentinel. Blocked on the Agent SDK pin (0.3.284 does not know the id) and on #8643. Follow-up issue: re-evaluate at the next SDK bump with an eval over real chapter-routing prompts. |
| 6 | `cron-daily-triage`, `cron-follow-through-monitor`, `cron-campaign-calendar`, `cron-community-monitor` (CLI agentic crons on `EXECUTION_MODEL`) | Sonnet 5.5 | **Candidate, not adopted** | Triage/summarize-shaped, but they are multi-turn tool-using agents on the operator key with `--max-turns` up to 80; failure is silent (green monitors). ADR-053 requires a separately attested model-bump PR. Follow-up issue with an eval arm built on `eval-harness` (`models.generated.json` already includes the new id after this PR). |
| 7 | `cron-compound-promote` (clustering, 16K tokens, structured output) | Sonnet 5.5 | **Not a fit** | Reads operator-session learnings and writes PRs (GDPR gate trigger c); keep the stronger tier. |
| 8 | `cron-weekly-release-digest` | Sonnet 5.5 | **Not a fit** | Self-identified never-downgrade shape. |
| 9 | Workflow `'standard'` pins (`classify`, `parse`, `analyze`, `commit`, `report`, `cluster`, `detect-threshold`) | Sonnet 5.5 | **Candidate, not adopted** | Mechanical on paper; `workflow-model-pins.test.ts` `PIN_ALLOWLIST` is a clo-attestation-class invariant. Follow-up: per-label eval, start with `commit` and `detect-threshold` (smallest blast radius). |
| 10 | CI `claude-code-review.yml` (per-PR advisory review comment, `--model claude-sonnet-5-5`) | Sonnet 5.5 | **Candidate, not adopted (eval-gated)** | ADR-053 line 90 itself calls it "a supplementary advisory commenter, exactly the mechanical/advisory class this ADR pins DOWN" and "an unbounded per-PR spend surface"; the never-downgrade list (ADR-053 line 19) covers workflow scripts, not CI. Folded into follow-up (b). Not moved here: a `--model` swap requires the coupled `claude-code-action` pin check (#2540) and a review-quality eval. `fix-constraints-stage-a.yml` and `test-pretooluse-hooks.yml` are code-producing and stay (row 13). |
| 11 | Audit tier (Opus 5.5), Concierge/leader reasoning classes (`engineering.pr_review_pending`, `engineering.ci_failed`) on Sonnet 5.5 | mixed | **Not a fit** | Deep reasoning and agentic coding; the launch post says Haiku 5.5 is not for complex agentic coding. |
| 12 | Effort/model router (#6000, open) | none | **Future consumer** | Haiku 5.5's effort levels make a single tier-to-model table plus an effort column viable; out of scope, comment on #6000 with the verified effort facts (default `medium`, five levels, CLI row `medium`). |
| 13 | `cron-bug-fixer`, `fix-constraints-stage-a.yml`, `test-pretooluse-hooks.yml` (agentic coding with edit tools) | Sonnet 5.5 | **Not a fit** | Complex agentic coding; also merge-gating or code-producing, so on the never-downgrade list. |
| 14 | `security.cve_alert` leader class (Sonnet 5.5) | Sonnet 5.5 | **Not a fit** | Security-flavored; Haiku 5.5's cyber safeguards decline pentest-style prompts with no server-side fallback, and a refusal here would drop a real alert. |
| 15 | Compaction and context-summarization steps | none in this repo | **Not applicable today** | `git grep` finds no Soleur-owned compaction call with a model choice (the Claude Code harness owns compaction). If a server-side compaction is added later, Haiku 5.5 is the default candidate; record in the ADR amendment as a placement rule, not as work. |
| 16 | Advisor consults (`resolveAdvisorTier()`, ADR-083) and harness tier map (ADR-110) | Fable 5.1 / `cheap` = `haiku` alias | **Unchanged** | ADR-083 upgrades are judgment gates and stay on the advisor tier; ADR-110's `cheap` tier maps to the `haiku` alias on Claude (it now resolves to 5.5 on CLIs at or above 2.1.293) and to `grok-4.5` on Grok. `harness-model-map.ts` needs no edit; `harness-model-map.test.ts` pins the alias, not an id. |

Follow-up issues (deferral tracking gate; each with milestone from `knowledge-base/product/roadmap.md`, "what, why, re-evaluation criteria", labels verified with `gh label list --limit 200` before use): (a) pdf-chapter-router to Haiku 5.5 after the SDK bump; (b) one eval-gated re-tiering issue covering the triage/summarize-shaped execution crons (row 6) and the `'standard'` to `'cheap'` workflow pins (row 9), so the `eval-harness` arm is built once; plus comments on the existing #6945 (quantization numbers), #8643 (evaluation, self-expiring carve-out) and #6000 (effort facts). Issues are created at ship time; their numbers go into the ADR amendment.

### Phase F: Verification

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/model-tiers.test.ts test/server/inngest/claude-cli-pin-knows-models.test.ts test/server/inngest/leader-prompts test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts test/server/cost-writer-unpriced.test.ts test/domain-router.test.ts test/anthropic-text-block-parity.test.ts` plus `test/server/email-triage/summarize.test.ts`, and `./node_modules/.bin/tsc --noEmit` (the repo root declares no workspaces, so no `npm run -w` form).
- `bun test plugins/soleur/test/model-launch-review.test.ts plugins/soleur/test/components.test.ts plugins/soleur/test/harness-model-map.test.ts plugins/soleur/test/workflow-model-pins.test.ts`.
- `bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` (all groups) and `--detect` must print `model-drift: none (config model IDs current).` with rc 0; `[2b]` must print `ok      claude-haiku-5-5 present in the pinned CLI bundle`.
- `python3 scripts/lint-anthropic-content-position.py` exits 0; `bash plugins/soleur/test/c4-count-parity.test.sh` stays green.
- `bash plugins/soleur/skills/eval-harness/test/gen-models.test.sh`.
- Run the repo's deterministic lints on each guard-shaped commit before spawning any review panel (model-launch-review sharp edge).

## Files to Edit

- `apps/web-platform/server/inngest/leader-prompts/constants.ts` (HAIKU_MODEL and the line-25 comment; `LeaderPromptModule.effort` only if the conditional Phase C item 3 activates)
- `apps/web-platform/server/inngest/leader-prompts/triage.p0p1_issue.ts`, `knowledge.kb_drift.ts` (only if the conditional Phase C item 3 activates: effort, promptVersion)
- `apps/web-platform/server/inngest/leader-prompts/index.ts` (comment only, if it restates the Haiku id)
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` (MODEL_PRICING tier, Sonnet cache-read; effort pass-through only if Phase C item 3 activates)
- `apps/web-platform/server/inngest/model-tiers.ts` (comments)
- `apps/web-platform/server/domain-router.ts`, `apps/web-platform/server/email-triage/summarize.ts`
- `apps/web-platform/package.json`, `apps/web-platform/package-lock.json`, `apps/web-platform/Dockerfile`
- `apps/web-platform/test/server/inngest/model-tiers.test.ts`, `claude-cli-pin-knows-models.test.ts` (header only), the leader-loop test (one refusal assertion)
- `apps/web-platform/test/domain-router.test.ts`, `test/helpers/anthropic-stub.ts`, `test/sandbox-credential-deny-runtime.test.ts`, `apps/web-platform/test/server/email-triage/summarize.test.ts`, `apps/web-platform/test/anthropic-text-block-parity.test.ts` (selection-predicate parity; also the import-graph check for the router)
- `.github/actions/anthropic-preflight/action.yml` (conditional on the probe)
- `scripts/learning-retrieval-bench.sh`, `scripts/lint-anthropic-content-position.py` (docstring only)
- `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh`, `plugins/soleur/skills/model-launch-review/SKILL.md`, `plugins/soleur/test/model-launch-review.test.ts`
- `plugins/soleur/skills/eval-harness/models.generated.json` (regenerated, never hand-edited)
- `plugins/soleur/AGENTS.md`
- `plugins/soleur/skills/agent-native-architecture/references/{agent-execution-patterns,agent-native-testing,architecture-patterns,mobile-patterns}.md`, `plugins/soleur/skills/dspy-ruby/SKILL.md`, `plugins/soleur/skills/dspy-ruby/references/providers.md`
- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md` (append-only addendum and supersession notes)
- `knowledge-base/engineering/architecture/decisions/ADR-041-byok-cap-enforcement-model.md` (addendum: pricing tier, regime boundary, Layer 2 vs Layer 3)
- `knowledge-base/engineering/operations/runbooks/anthropic-console-workspace-key.md` (Haiku probe id, per the preflight verdict)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-haiku-5-5-support/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-haiku-5-5-support/decision-challenges.md` (supply-chain floor override; Sonnet cache-read correction timing)

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200`, then `jq --arg path` over each planned path.

- **#8643** (ci(models): gate that the pinned claude-agent-sdk bundled CLI knows the Agent SDK model ids) matches `claude-cli-pin-knows-models.test.ts`. **Acknowledge.** Its stated trigger is "next Anthropic model launch or next SDK bump"; this launch does not put a new id on the SDK path (SDK stays 0.3.284) and the gate requires routing the Concierge default through a named constant. Add a comment on #8643 recording the evaluation and that the carve-out in `audit-models.sh` retires when the SDK pin moves.
- **#9648** (Mistral Large 4 + Mistral Vibe support) matches `MODEL_PRICING` conceptually (its Stage 2 adds a priced row). **Acknowledge.** The optional `longPrompt` field is additive and does not constrain a flat row.
- **#6945** (BYOK cap compares cents x tokens to a cents budget; sub-cent turns quantize to 0) and **#7920** (same product defect at founder scope) are not file matches but are the accounting behaviour this change interacts with. **Acknowledge** with a comment on #6945 carrying the corrected picture from Findings (immune only below half a cent; the 1-cent band and the long card contribute full token counts; delegated caps never see 0-cent rows; Layer 3 bounds the money); the correct fix is the dimensional one, not a rounding floor (see Cut List).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Update Soleur everywhere it's needed to support this new model version" [brief] | Phases A to D | mapped |
| 2 | "model-ID references" [brief] | Phase B items 2, Phase C, Phase D items 1 to 5 | mapped |
| 3 | "pricing/tier maps" [brief] | Phase B items 3 to 5, Phase D items 6 to 7 | mapped |
| 4 | "claude-code-action pins" [brief] | Cut List and Research Reconciliation (evaluated; no `--model` swap so no bump); PR body reports pin age | mapped |
| 5 | "docs, tests" [brief] | Phase D items 2 to 7, tests in every phase | mapped |
| 6 | "check whether there are any locations where Haiku 5.5 would be better suited than the current model" [brief] | Phase E | mapped |
| 6b | "which call sites should NOT move" [coordinator message] | Phase E rows 7, 8, 10, 11, 13, 14 (explicit do-not-move rows) and the Cut List | mapped |
| 7 | "Use the soleur:model-launch-review skill's checklist as the baseline" [brief] | Phase A (item 2b), Phase B (item 4), Phase D (items 1, 5; item 3 thinking shape in Phase C), Phase E (item 5 tier map), Phase F audit run | mapped |
| 8 | "Pricing for Haiku 5.5 must be verified from Anthropic docs (context7 / claude-api skill / WebFetch), not guessed." [context hints] | Research Insights pricing table; Phase 0 item 1 | mapped |
| 9 | "Check the claude-agent-sdk / claude CLI pin knows claude-haiku-5-5" [context hints] | Phase A | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Constant, call-site and doc id swaps | "model-ID references" | asked |
| `MODEL_PRICING` Haiku 5.5 row | "pricing/tier maps" | asked |
| Optional `longPrompt` card + `resolveTurnCostUsd` tier selection | "Pricing for Haiku 5.5 must be verified from Anthropic docs" | asked (the verified page has two cards; a flat row cannot represent it) |
| CLI pin 2.1.284 to 2.1.293 | "Check the claude-agent-sdk / claude CLI pin knows claude-haiku-5-5" | asked |
| `audit-models.sh` pairs, test and SKILL updates | "Use the soleur:model-launch-review skill's checklist as the baseline" | asked |
| Phase E verdict table and follow-ups | "check whether there are any locations where Haiku 5.5 would be better suited" | asked |
| ADR-053 amendment, AGENTS.md pricing basis | "pricing/tier maps" | asked |
| Eval harness `models.generated.json` regeneration | "tests" | asked (generated artifact fed from the constant; stale otherwise) |
| Effort `low` on the router and summarizer (conditional leader-loop field) | — | inferred — justification: Haiku 5.5 turns thinking on by default; without it the 200- and 256-token routes can truncate to empty output (correctness dependency of the id swap) |
| Sentry mirrors on missing text block | — | inferred — justification: `cq-silent-fallback-must-mirror-to-sentry`; the existing fallbacks are silent and become reachable with thinking-on |
| Sonnet 5.5 cache-read correction | — | inferred — justification: found while verifying the pricing table the ask requires; same row table and regime comment, separate commit and gated on a live refetch so it can be dropped alone |
| `lint-anthropic-content-position.py` docstring rephrase | — | inferred — justification: it keeps `audit-models.sh --detect` red (rc 10) on the branch today, which would mask any real Haiku straggler the new pairs are meant to surface |
| Carve-out for the two SDK-path scripts | — | inferred — justification: without it the new pair would make `--fix` rewrite scripts whose SDK bundle does not know the id and make `--detect` permanently red |
| Supply-chain floor override disclosure | — | inferred — justification: required by the CLI bump per model-launch-review SKILL.md; keeps the waiver reviewable |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform`, `plugins/soleur`, `.github`, `scripts`, `knowledge-base`
- Planned files: about 34 | Estimated changed lines: about 650 (pin lockfile churn excluded)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **single PR, ordered commits** — thresholds exceeded on roots and file count, split considered and declined for a stated reason. Proposed seam if ever split: PR1 = Phase A (CLI pin, no model change), PR2 = Phases B to E. Declined because (i) the user asked for one end-to-end support change, (ii) roughly 14 of the files are mechanical doc/prose swaps with no behavioural risk, (iii) the seam is already commit-level (`git revert` of the Phase B/C commits restores 4.5 while the pin stays), and (iv) PR2 cannot be green before PR1 lands, so a split serialises two CI cycles with no isolated value for PR1 beyond a soak this pipeline cannot wait for. The soak risk that remains is recorded under Risks.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `grep -a -c 'claude-haiku-5-5' apps/web-platform/node_modules/@anthropic-ai/claude-code-linux-x64/claude` prints a number >= 1 after the lock regeneration, `node_modules/@anthropic-ai/claude-code-linux-x64/package.json` reports 2.1.293, `package.json`, `Dockerfile` and `package-lock.json` agree, and `@anthropic-ai/claude-agent-sdk` is still 0.3.284.
- [ ] AC2 `HAIKU_MODEL === "claude-haiku-5-5"`; `Object.keys(MODEL_PRICING)` equals the `AnthropicModelId` union; the Haiku row equals the committed short and long cards; `resolveTurnCostUsd("claude-haiku-5-5", {input_tokens: 100000, ...zeros})` uses the short card and `input_tokens: 100001` uses the long card; a usage with 60,000 `input_tokens` + 50,000 `cache_read_input_tokens` uses the long card; an unknown model returns NaN.
- [ ] AC3 `git grep -nE 'claude-haiku-4-5' -- . ':(exclude,glob)knowledge-base/**' ':(exclude,glob)**/test/**'` lists only: the two carve-out scripts (and the preflight action when its probe failed), the `AUTOFIX_PAIRS` left-hand sides in `audit-models.sh`, and explanatory comments that say the id is superseded; every other hit is a failure. (Expected-set assertion is written in `model-launch-review.test.ts`, not left to eyeball.)
- [ ] AC4 `bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh --detect` exits 0 and prints `model-drift: none (config model IDs current).`; the full audit prints `ok      claude-haiku-5-5 present in the pinned CLI bundle` in `[2b]`.
- [ ] AC5 Each Haiku caller has a test that feeds a response beginning with a `thinking` block and one with no text block (for the router and summarizer a `stop_reason: "refusal"` body is one such case; for the leader loop a refusal turn lands in `persistFailure`): the first yields the parsed result, the second produces a Sentry mirror (op `domain-router-no-text-block` for the router) and the documented fallback.
- [ ] AC6 Phase 0 probe results (or the explicit text "unverified-live: no reachable key") appear in the PR body with the chosen configuration per caller and the decision-rule outcome.
- [ ] AC7 The commit that bumps the lock carries a `sdk-bump-verified:` trailer naming the hook probe and its control (2.1.284), and `bash apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` passes against `origin/main`.
- [ ] AC8 Either the Phase 0 leader-shape cell showed no truncation and the leader modules are unchanged apart from the model constant (`prompt-version-stability.test.ts` passes as is), or the conditional Phase C item 3 landed and `prompt-version-stability.test.ts` passes with the two Haiku classes at `v1.1.0` carrying `effort: "low"` and the Sonnet classes carrying none.
- [ ] AC9 ADR-053 carries an append-only dated 2026-10-08 addendum (Phase E verdicts, SDK-path carve-out, re-evaluation trigger) plus supersession notes on row 5a and the Haiku tier table, with no rewritten historical table; ADR-041 carries the pricing-tier and regime-boundary addendum; `plugins/soleur/AGENTS.md` Haiku figures are refreshed.
- [ ] AC10 Follow-up issues (a) and (b) exist with milestone and re-evaluation criteria and are linked from the ADR amendment; comments are posted on #8643, #6945 and #6000.
- [ ] AC15 `knowledge-base/engineering/operations/runbooks/anthropic-console-workspace-key.md` and `.github/actions/anthropic-preflight/action.yml` name the same Haiku id (both swapped or both left on 4.5 with the carve-out), checked by `grep -c` on each.
- [ ] AC11 `python3 scripts/lint-anthropic-content-position.py`, `python3 scripts/lint-guard-contract.py` (over this plan), the vitest and bun suites listed in Phase F, `bash plugins/soleur/skills/eval-harness/test/gen-models.test.sh`, and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` all pass; `npx markdownlint-cli2` passes on this plan and `tasks.md`.
- [ ] AC12 The PR body's first line states that merging deploys the web-platform image (CLI pin and Haiku routing change); it also carries the "Supply-chain floor override" section (if the override was used) and states the Sonnet cache-read correction and its regime-boundary caveat.

### Post-merge

None to execute by hand. Merging touches `apps/web-platform/**`, so `web-platform-release.yml` rebuilds the image (CLI 2.1.293) and restarts the container as part of the normal release; nothing else mutates production. The PR body's first line states exactly that. The drift detector's next scheduled run (`rule-audit.yml`, step "model-drift") is the standing post-merge check; it is not a gate for this PR and is not polled here.

## Test Scenarios

1. Pricing: short card at exactly 100,000 prompt tokens; long card at 100,001; cache-heavy usage crossing the boundary; zero usage; unpriced model NaN; Sonnet row values (including the cache-read figure if corrected).
2. Parity: literal in `domain-router.ts` equals `HAIKU_MODEL`; `models.generated.json` equals the constants.
3. CLI pin: guard reds on 2.1.284 with `HAIKU_MODEL` at 5.5 (RED proof), greens on 2.1.293; Dockerfile and `package.json` disagreement reds; `REVIEWED_DEFAULT_EFFORT` unchanged (medium, medium).
4. Response shape: thinking block first; no text block with `stop_reason: "max_tokens"`; redacted thinking; two text blocks (first wins).
5. Leader loop: the Haiku class request is unchanged except for the model id (or carries `output_config.effort: "low"` when the conditional item activated); top-level `cache_control` unchanged; a tool-use turn echoes assistant content (including thinking) back unchanged; a `refusal` stop ends in `persistFailure`.
6. Audit: dated and undated Haiku 4.5 spellings are both detected and rewritten; a file in the carve-out is neither detected nor rewritten; a second stale file in the same directory as a carve-out is still detected; `assert_single_hop` exits 78 on a chained RHS.
7. Live (conditional): matrix from Phase 0 against the real API.

## Guard Contract

### Guard 1 — model-launch drift detector (audit-models.sh pairs and carve-out)

**Property.** After this change, `audit-models.sh --detect` exits 10 if and only if a config-class file outside the documented SDK-path carve-out carries a superseded Haiku id in either spelling, and `--fix` rewrites exactly the files `--detect` selected.

**Assembly.** The property quantifies over: the two new `AUTOFIX_PAIRS` entries (dated and undated spelling), the selection regex built by `autofix_match_re`, the `--fix` sed that must share the same `ID_BOUNDARY`, the exclusion pattern (including the new carve-out for exactly two files, or three when the preflight probe fails; the preflight entry is a `curl` caller the SDK pin never retires, so it expires by being swapped at the next launch or when the probe cell passes, and the test enumerates the carve-out list by value), `assert_single_hop`, the `[1]` re-scan, and the test-side `CURRENT_IDS` plus `parseAutofixPairs`. The chokepoint is `ID_BOUNDARY`; any second spelling of the boundary is the defect. There is more than one injection site (selection, rewrite, re-scan, exclusion) and the contract covers all four.

**Mutation matrix.**

| # | Mutation (edit that must drive the guard RED) | Expected failing check |
|---|---|---|
| 1 | Delete the dated pair `claude-haiku-4-5-20251001=claude-haiku-5-5` | pair-table-driven test: a fixture carrying the dated id is no longer detected |
| 2 | Widen the carve-out to the whole `apps/web-platform/scripts/` directory | a second stale-id fixture in that directory (added after the compliant first member) must still be detected, so the test reds |
| 3 | Make the scan dispatch zero files (point `--root` at an empty directory) | must exit non-zero or report zero scanned; a clean "none" with zero files examined reds the anti-vacuity test |
| 4 | Remove the carve-out entirely | the carve-out test (the carve-out paths must not be selected or rewritten) reds |
| 5 | Raise the `@anthropic-ai/claude-agent-sdk` pin to 0.3.293 or later while the carve-out remains | the self-expiring test reds with the instruction to delete the carve-out and swap the two scripts to `claude-haiku-5-5` |

Rows for a chained map (`assert_single_hop`, exit 78) and for dropping `|$` from `ID_BOUNDARY` are already pinned by existing tests in `model-launch-review.test.ts` (the NON-CONVERGENT test and the end-of-line boundary test); they are not restated here.

**Harness rows.** (a) Edit the suite, not the guard: make `parseAutofixPairs` return an empty list; the test must red through a literal floor on pair count (at least the number of pairs committed here), because a table-driven test over zero pairs passes vacuously; and keep literal dated and undated Haiku 4.5 fixtures so deleting a pair from the table cannot delete its own fixture (row 1 would otherwise survive). (b) Must-PASS input that is not the canonical: a config file containing `claude-haiku-5-5` plus a longer lookalike `claude-haiku-4-5-20251001-x` (a longer token is not the stale id) must report clean. (c) Instrument controls: a pristine-tree run exits 0 with `model-drift: none`, and the exit code (0 vs 10 vs 2) is asserted, not only stdout. Row 3 mutates the harness invocation rather than the script; the script-side anti-vacuity is the existing rc 2 scan-failed arm, which this row asserts still fires.

**Anchor.** The pair table and the files it scans live in the same commit, so the guard proves consistency, not integrity. The carve-out is self-expiring (row 5): a test reads the SDK pin from `apps/web-platform/package.json` and fails once it reaches 0.3.293, the first SDK release whose bundle carries the id, so the exemption cannot outlive the reason for it. This self-expiry test is a deliberately small piece of the same intent as #8643 (it does not add the SDK-bundle id gate #8643 asks for). The independent anchor is the live pricing/models page and the bundled `claude-api` skill table, re-fetched at work time and quoted in the PR body; no merge-base diff can supply it.

### Guard 2 — MODEL_PRICING value and prompt-length-card pin

**Property.** For every model reachable through `MODEL_PRICING[leaderModule.model]`, `resolveTurnCostUsd` returns the published per-token price for the card that the turn's prompt length selects, and never returns 0 for an unpriced model.

**Assembly.** The property quantifies over: every key of `MODEL_PRICING` against the `AnthropicModelId` union; every rate field of every card (input, output, cache read, cache create); the tier-selection expression (which token counts enter it, and the comparison operator); and the single consumer call site in `agent-on-spawn-requested.ts` plus the NaN contract tested in `cost-writer-unpriced.test.ts`. The chokepoint is `resolveTurnCostUsd`.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Expected failing check |
|---|---|---|
| 1 | Restore the Haiku 4.5 values (1/5/0.10/1.25) under the new key | committed-rates pin test |
| 2 | Change the comparison from `>` to `>=` at the boundary | the 100,000 exact case |
| 3 | Compute the tier from `input_tokens` only, or from `input_tokens + cache_read_input_tokens` without `cache_creation_input_tokens` | the cache-heavy case (60K input + 50K cache read) and the `cache_creation`-only crossing at 100,001 |
| 4 | Change the Sonnet row after a compliant Haiku row (second member), or swap one field (0.05 vs 0.625) on the long card | the Sonnet value pin and the four-distinct-values-per-card case, proving the check does not stop at the first row or the first field |
| 5 | Remove the Haiku key | key-parity test against the union |
| 6 | Replace the `!pricing` NaN arm with a zero-filled fallback | unpriced-model NaN test |

**Harness rows.** (a) Edit the suite: replace the exact `toEqual` pin with `toBeDefined`; a numeric end-to-end case (`resolveTurnCostUsd` result for fixed usage compared to a hand-computed dollar value) must still red. (b) Must-PASS non-canonical input: usage of exactly 100,000 prompt tokens with a nonzero cache-read split, which the contract explicitly permits (strictly-greater rule) and must price on the short card.

**Anchor.** The stored rates and the code reading them can be edited in one diff. The independent anchor is the official pricing page fetched during Phase 0 and the explicit regime-boundary note (merge SHA, UTC time) in the row comment; a Console invoice line is the only true external anchor and is not available to this pipeline.

## Observability

```yaml
liveness_signal:
  what: rule-audit.yml model-drift detection step (audit-models.sh --detect) plus the existing Sentry cron monitors for the Haiku-backed Inngest functions
  cadence: scheduled by rule-audit.yml; per-run for the Inngest functions
  alert_target: one idempotent model-drift GitHub issue; Sentry issues for the crons
  configured_in: .github/workflows/rule-audit.yml and apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts

error_reporting:
  destination: Sentry web-platform via reportSilentFallback on the message path (err = null, feature and op tagged), plus the pino mirror
  fail_loud: feature domain-router and feature email-triage emit op no-text-block when a Haiku response has no text block, ends at max_tokens, or is refused; the leader loop dead-letters through reportSpawnDeadLetter with reason leader_refused or leader_response_truncated. These create Sentry issues only; no alert rule routes them to a person, and this plan adds none (stated so the block does not imply paging).

failure_modes:
  - mode: Haiku 5.5 thinking consumes the small max_tokens budget and no text block is returned (router, summarizer)
    detection: layer 2 (pino to Sentry mirror) plus the message-path reportSilentFallback, with stop_reason, category and model as the only extra keys, asserted by a test
    alert_route: Sentry issue grouped by feature and op, read through the Sentry API
  - mode: a leader-loop Haiku turn stops at max_tokens or is refused (including a legitimate security-flavored issue body)
    detection: layer 1 (sentry-correlation middleware tags the Inngest run) and layer 2 via reportSpawnDeadLetter with the failure reason
    alert_route: Sentry issue with the reason tag; the existing spawn dead-letter alert rule
  - mode: a Haiku 4.5 id reappears in a config-class file
    detection: workflow run log (layer 6) of rule-audit.yml, audit-models.sh --detect exits 10
    alert_route: one idempotent model-drift GitHub issue
  - mode: pinned CLI loses knowledge of a tier id after a future bump
    detection: workflow run log (layer 6), claude-cli-pin-knows-models.test.ts in the CI test job
    alert_route: red required check on the PR
  - mode: a model is added to the leader loop without a pricing row
    detection: layer 2, resolveTurnCostUsd returns NaN and both cost writers fail closed and mirror an unpriced-model event to Sentry
    alert_route: Sentry issue tagged unpriced-model

logs:
  where: Sentry events and Inngest run logs for the web-platform app
  retention: per the Sentry plan retention window

discoverability_test:
  command: bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh --detect
  expected_output: none
```

The probe verifies drift mode 3 only (the standing config-drift signal). The primary Haiku 5.5 budget failure (mode 1) is discoverable through the Sentry API by feature and op, which needs a credential and is therefore not declared as the Check 10 probe.

## Domain Review

**Domains relevant:** Engineering, Finance

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Overall risk medium. Riskiest step: flipping the shared constant and the router literal before a live probe, because the failure is silent (truncated or empty classification, then a mis-route to the fallback leader). Adopted: probe first, configuration chosen by a decision rule, Sentry mirror on a missing text block, router adaptation validated by the Phase 0 probe before its flip. Recommended splitting the CLI pin from the flip for soak: considered and declined for the recorded reasons in the Split Assessment (commit-level seam retained). Recommended not bumping the Agent SDK for the canary scripts: adopted (Cut List). Flagged that the `domain-router.test.ts` #8392 comment becomes false: adopted. Suggested keeping the preflight on 4.5 or probing it: adopted as a conditional.

### Finance (CFO)

**Status:** reviewed
**Assessment:** Flat row cannot hold two cards; add an optional long-prompt card and select on the superset of input-side tokens so ambiguity can only over-attribute: adopted. Sonnet cache-read correction is a regime boundary in a WORM ledger, not a back-applied fix: adopted with merge SHA and UTC time, gated on a refetch, and a Console invoice line named as the only true external anchor. Ceiling stays 260 (ADR-041): adopted. Savings: 20x versus Sonnet 5.5 and about 10x versus Haiku 4.5 per token (about 7.7x after tokenizer inflation) at or below 100K prompt tokens; about 4x above 100K; no spawn-volume data exists in the repo, so no absolute dollar figure is claimed. Riskiest step named: integer-cent rounding (`Math.round(x * 100)`) storing 0 for sub-cent turns. Partially adopted: the rounding concern is real and pre-existing (#6945), but the proposed `Math.max(1, ceil())` interim is rejected because it interacts with the cents-times-tokens product in the cap SQL and would make single Haiku turns trip the cap (Cut List); disclosed and routed to #6945.

### Not relevant (assessed)

Product/UX (no UI surface; `api-usage-section.tsx` is prose only, no price or id), Marketing, Legal (same vendor, same data flows, no new processing activity or subprocessor; the GDPR gate is not triggered: no schema, auth, route or new LLM data movement), Operations, Sales, Support.

## User-Brand Impact

- **If this lands broken, the user experiences:** the domain-routing classifier silently falling back to the CPO leader for every message (wrong advisor on the first reply), or a triage/KB-drift leader run failing with a "max turns / max tokens" notification instead of an action.
- **If this leaks, the user's money is exposed via:** mis-attributed BYOK cost in the WORM `audit_byok_use` ledger (a wrong Haiku 5.5 rate card or tier selection would be permanent and feeds both cap layers); no credentials, content or personal data are newly exposed because the vendor, data flow and prompts are unchanged.
- **Added at review (2026-10-08, user-impact seat):**
  - **Sonnet 5.5 cache-read correction ($0.20 to $0.10) is the larger blast radius**: it touches every Sonnet turn, not only Haiku classes. It rests on the pricing page stating $0.10 twice; the repo cannot query a Console invoice, so the invoice line is a post-merge spot-check by whoever reads the next bill, not a merge gate. The error direction if wrong is under-attribution (caps trip late), so the commit is separable on purpose.
  - **A refused, truncated or empty summarizer turn** used to store an empty (or half-JSON) summary in a write-once column; it now stores an explicit placeholder and reports once. A refused `triage.p0p1_issue` turn dead-letters visibly with its category; a retry on Sonnet is a new mechanism, deferred to #9790.
  - **Visibility, not paging:** the `no-text-block` mirrors create Sentry issues; no alert rule routes them to a person (stated, not implied).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the failure shapes are uniform and fail-closed (unpriced model returns NaN, pricing pinned by tests, bounded Layer 3 spend of a few cents per run), so no single founder can suffer a distinct, irreversible harm, which rules out `single-user incident`; a systematic mis-attribution across founders is an aggregate pattern, which rules out `none`.

## Architecture Decision (ADR/C4)

### ADR

Append to **ADR-053** (per-call model tiering, append-only: supersession notes plus a dated addendum with the Phase E verdicts, the SDK-path carve-out and the re-evaluation trigger) and to **ADR-041** (ledger semantics: `longPrompt` card, superset prompt-token rule, Sonnet cache-read regime boundary, Layer 2 vs Layer 3 for sub-cent turns). Tasks in Phase D items 7 and 7b. No new ADR: no new substrate, boundary or ownership change; the decision extends the existing tier map.

### C4 views

No C4 impact. Read `model.c4`, `views.c4`, `spec.c4` (934/124/54 lines). Checked: (a) external human actors: none added or changed; (b) external systems: Anthropic API is modeled (`anthropic = system "Anthropic API"`) with edges `engine -> anthropic` (BYOK LLM calls), `claude -> anthropic`, `api -> anthropic` (admin cost report), `github -> anthropic` (CI turns), `evalharness -> anthropic`; the change swaps which model those edges call, and no model id, tier or price appears in any `.c4` file (grep for haiku, sonnet, opus, claude- finds only descriptions of unrelated components); (c) containers/data stores: none added (the WORM ledger is unchanged in shape); (d) actor-to-surface access relationships: unchanged. Run `bash plugins/soleur/test/c4-count-parity.test.sh` and the C4 syntax test to confirm no derived count moved.

### Sequencing

The decision is true immediately at merge; nothing is gated on a later slice.

## Downtime & Cutover

No downtime-inducing operation: there is no schema or lock-taking DDL, no host replace, and no router or tunnel change. The `Dockerfile` CLI pin and the application changes ship through the existing `web-platform-release.yml` image rebuild and container restart that every merge touching `apps/web-platform/**` already triggers; no new drain or maintenance window is introduced. Leader runs suspended across that restart resume per the in-flight note under Risks.

## Risks and Sharp Edges

- **Soak risk accepted.** One PR carries a CLI bump across nine versions (2.1.284 to 2.1.293) plus the flip. Mitigation: the CLI feeds only the operator-key crons (sandbox disabled there, containment is the allowlist hook, probed in AC7); the interactive sandbox builder is the SDK bundle, which does not move. Reverting the Phase B/C commits restores 4.5 without touching the pin.
- **Unknown `disabled` thinking semantics** (API docs say accepted at effort at or below high; the CLI row says `rejects_disabled_thinking`): avoided by design; do not add `thinking: {type: "disabled"}` without a green live cell.
- **Prompt-length definition is unspecified** on the pricing page. The superset rule only over-attributes. If a Console invoice later shows cache reads excluded from the threshold, narrowing is a one-line change plus a regime note.
- **In-flight leader runs across the deploy.** A run suspended mid-loop resumes on the new code: memoized turns keep their recorded cost, later turns use 5.5 pricing, and the replayed assistant content contains no Haiku 5.5 thinking blocks from before the deploy, so the history-editing check does not trigger. The `promptVersion` bump only affects new runs. No step return shape changes.
- **Tokenizer inflation** (about 30%) moves token-denominated budgets: re-check `max_tokens` on every small-budget route (Phase 0 covers 200, 256, 1) and `MAX_SUMMARIZE_BODY_BYTES` interplay (byte cap unchanged; token count rises).
- **Effort plus structured output is undocumented.** The docs name `output_config.effort` and `output_config.format` separately and never together. Phase 0's router cell is the first evidence; a 400 means the router ships a raised `max_tokens` without `effort`.
- **Fallback documentation conflict.** Haiku-specific pages say there is no server-side fallback; the generic refusals page documents `fallbacks: "default"` without naming Haiku 5.5. The plan sends none; changing that needs a live cell, not a doc reading.
- **Alias retargeting is outside this repo's control.** The `haiku` alias (research agents, `'cheap'` workflow pins) retargets when each user's Claude Code updates, independent of the pin bumped here (ADR-053 line 39).
- **Do not "fix" #6945 here.** Rounding up without fixing the cents-times-tokens product trips caps.
- **Comment hygiene in `model-tiers.ts`**: no `/*` inside a `//` comment (it blinds the guards that strip comments).
- **Plan fields that fail `deepen-plan` if left empty:** `## User-Brand Impact` and `## Observability` are filled; keep `discoverability_test.command` first token on the probe allowlist (`bash`).
- **Detector hygiene:** after editing `AUTOFIX_PAIRS`, re-run `--detect` and assert the file count moved from the baseline (1 stale file today); a zero exit alone is not evidence the new pairs are live.
- **Dated model-launch learnings recur:** resolve ids, prices and pins from the official page or `gh api` in-pass, never from memory.
