---
title: "Add NanoCorp (nanocorp.so) to tracked competitors"
type: docs
date: 2026-06-08
branch: feat-one-shot-add-nanocorp-competitor
lane: procedural
brand_survival_threshold: none
status: ready
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# 📚 Add NanoCorp (nanocorp.so) to the Competitive Landscape

## Enhancement Summary

**Deepened on:** 2026-06-08

**Hard gates run (all PASS):**
- **Phase 4.6 User-Brand Impact halt** — section present; threshold `none` with a non-empty reason; Files-to-Edit are both under `knowledge-base/` (not in the preflight Check 6 sensitive-path set), so no scope-out bullet is required.
- **Phase 4.7 Observability gate** — skipped (pure-docs: every Files-to-Edit path is `knowledge-base/product/*.md`; zero code/infra paths).
- **Phase 4.8 PAT-shaped-variable halt** — no match (no Terraform/env/token literals).
- **Phase 4.9 UI-wireframe halt** — skipped (no UI-surface file in Files-to-Edit/Create).

**Verification applied (no full agent fan-out — scope is a 2-row docs addition, and a 40-agent review of a markdown table would contradict the task's explicit scope discipline):**
- Live WebFetch/WebSearch grounding for every NanoCorp fact (homepage, `/pricing`, YC profile, third-party review). The self-reported `$740k ARR` figure is flagged as marketing/unverified in both planned entries.
- Same-named-entity disambiguation verified: `nanocorp.so` (target) vs `nanocorp.ai` (unrelated Paris network-security co.). All entry hyperlinks use `.so`.
- Table-format claims verified against the live files: business-validation.md Tier 3 = 3-column; competitive-intelligence.md Tier 3 = 5-column. Pipe counts and the Polsia-row template confirmed.
- All `knowledge-base/` citations in the plan resolve on disk (only the spec.md absence-claim is intentionally non-existent).
- Relevant learning scan: `2026-03-13-stale-cross-references-after-kb-restructuring.md` reviewed — not applicable (this adds rows, does not move files; no new cross-references introduced).

### Key Improvements over the base plan
1. Recorded the gate-pass evidence inline so `/work` and review can confirm the docs-only classification without re-deriving it.
2. Pinned the marketing-vs-verified hedge on `$740k ARR` as a load-bearing AC, matching the existing Polsia/Viktor self-reported-metric convention.

## Overview

Add one new competitor — **NanoCorp** (`nanocorp.so`) — to Soleur's tracked competitive landscape. NanoCorp is a Y Combinator (W24) autonomous-AI-company platform: from a single prompt, an AI agent names a product, defines the ICP, writes conversion copy, deploys a Vercel landing page, creates Stripe products with pricing tiers, runs Google Search Ads, and queues an outreach task list — all toward one objective ("maximize revenue, avoid bankruptcy") with **no human in the loop**.

This is a **docs-only, single-competitor addition**. Scope is strictly limited: classify NanoCorp into the correct tier, write one table row matching the existing format with an `[Added 2026-06-08]` annotation, and mirror it into `competitive-intelligence.md` because that report's tier tables cover the chosen tier. **Do not re-run a full landscape scan**, do not re-classify or re-word any existing competitor, and do not touch the Assessment/Vulnerabilities/Structural-advantages prose.

**Tier classification: Tier 3 (Company-as-a-Service / full-stack business platforms).** NanoCorp is a near-twin of Polsia (already in Tier 3 of both files): a hosted, fully-autonomous "AI runs your company while you sleep" platform that even shares Polsia's revenue-share monetization wedge (NanoCorp charges a 20% withdrawal fee on revenue the autonomous company earns). It is not a Claude Code plugin (rules out Tier 1), not a no-code agent builder (Tier 2), not a framework (Tier 4), not a DIY coding tool (Tier 5), and not platform-native first-party competition from a model vendor (Tier 0). Tier 3 is unambiguous.

**Mirror decision: YES, mirror required.** `competitive-intelligence.md`'s tier tables cover exactly two tiers — Tier 0 (Platform Threats) and Tier 3 (CaaS / Agent-Plugin Competitors). Because NanoCorp lands in Tier 3, the mirror condition in the task ("if that report's tier tables cover the chosen tier") is satisfied. The mirror row uses that file's richer 5-column matrix.

## Research Insights

All facts below are WebFetch/WebSearch-sourced (2026-06-08). Two same-named entities exist — disambiguate carefully:

- **`nanocorp.so`** — the target. Autonomous AI companies. (NOT `nanocorp.ai`, which is "NANO Corp", an unrelated Paris-based network-security company founded 2019. The plan and both entries cite the `.so` domain explicitly to prevent confusion.)

**Verified product / positioning facts (cite-ready):**

- **Tagline:** "Autonomous Companies Run by AI Making Money While You Sleep." (`nanocorp.so` homepage)
- **Core loop:** one prompt → agent names the product, defines the target-customer profile, writes conversion copy, deploys a landing page on **Vercel**, creates **Stripe** products with pricing tiers, builds an outreach task list, and can run **Google Search Ads** (set a budget; the tool handles ad copy, keywords, optimization). Goal framing: "maximize revenue and prevent bankruptcy," **no human in the loop**. (homepage + blog "What Is an Autonomous AI Company?" + Alexis Bouchez review 2026-03-30)
- **ICP:** entrepreneurs / solo founders wanting passive-income ventures with minimal hands-on management — overlaps Soleur's solo-founder ICP, but pitched as "money while you sleep" passive ownership rather than founder-operated workflow.
- **Pricing:** Free ($0, "free forever") = 3 lifetime credits, 1 active company, `nanocorp.app` domain + `@nanocorp.app` email, **20% withdrawal fee** on earned revenue. **Founder $30/mo** = 30 monthly credits (scalable to higher credit tiers up to ~2000/mo), credit rollover, unlimited companies, custom domains, same 20% withdrawal fee. (`nanocorp.so/pricing`)
- **Company / stage:** YC **Winter 2024** batch, founded 2023, **team size 1**, San Francisco. Founder Pierre-Louis Biojout (ex-CTO of phospho, which raised ~€1.7M). (YC company profile)
- **Self-reported traction:** "$740k ARR in 33 days" (founder LinkedIn, ~April 2026). **Treat as marketing, not verified** — consistent with how the existing tables flag self-reported Polsia/Viktor metrics. The entries must hedge this figure ("self-reported", "claimed") rather than state it as fact.

**Differentiation-from-Soleur axes (drawn from `brand-guide.md` positioning + existing Polsia row conventions):**

1. **Founder-in-the-loop vs. no-human-in-the-loop** — Soleur is operator-driven (brainstorm→plan→work→review→compound with human gates); NanoCorp removes the founder entirely.
2. **8-domain breadth vs. narrow revenue-engine scope** — NanoCorp covers landing-page + Stripe + ads + outreach (a go-to-market revenue engine). No engineering code-review/deploy pipeline, no legal, no finance, no product-strategy, no support domains.
3. **Compounding git-tracked knowledge base vs. cloud-hosted proprietary state** — Soleur's memory is founder-readable git files; NanoCorp is a closed hosted SaaS.
4. **No revenue lock-in vs. 20% withdrawal fee** — NanoCorp's 20% revenue-withdrawal fee is an aggressive monetization wedge (same class as Polsia's 20% revenue share) that Soleur has not matched. Note it as a competitive wedge, mirroring how the Polsia row treats it.
5. **Shared Anthropic-platform dependency / convergence** — like Polsia, NanoCorp is another hosted autonomous-CaaS entrant validating the category while pressuring Soleur's hosted-platform revenue plan.

### Premise Validation

No external premises cited by reference (no `#N` issues/PRs, no in-repo file/symbol the task depends on existing beyond the two named KB files, both confirmed present at `knowledge-base/product/business-validation.md` and `knowledge-base/product/competitive-intelligence.md`). The competitor URL was validated by live WebFetch. The two named-entity collision (`nanocorp.so` vs `nanocorp.ai`) was checked and disambiguated. No stale premise; proceed.

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch (`knowledge-base/project/specs/feat-one-shot-add-nanocorp-competitor/spec.md` absent — verified). Table-format claims were verified directly against the live files (see Sharp Edges for the exact column shapes). No reconciliation gaps.

## User-Brand Impact

**If this lands broken, the user experiences:** a malformed markdown table row (broken pipe count) or a mis-tiered competitor in the two internal strategy documents the founder reads to make positioning decisions. Worst case is an internal-doc rendering glitch or a slightly-wrong competitive placement — not a user-facing product surface.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — no user data, no secrets, no regulated surface. The change is public-competitor information added to internal markdown files already in the repo.

**Brand-survival threshold:** none — reason: docs-only addition of public competitor information to internal knowledge-base markdown; no user data, no product surface, no regulated-data path, no infrastructure. Both edited paths are under `knowledge-base/` and are not in the preflight Check 6 sensitive-path set.

## Files to Edit

1. **`knowledge-base/product/business-validation.md`** — add ONE row to the **Tier 3** table (the table under `**Tier 3: Company-as-a-Service / full-stack business platforms**`, header `| Competitor | Approach | Differentiation from Soleur |`, delimiter `|---|---|---|`). Insert the NanoCorp row in the existing Tier 3 table body (alongside Polsia, Tanka, SoloCEO, etc.). The 3 columns are:
   - **Competitor:** `[NanoCorp](https://nanocorp.so) [Added 2026-06-08]`
   - **Approach:** product loop + pricing summary (1-prompt autonomous company → Vercel landing page + Stripe + Google Ads + outreach; YC W24, solo founder; Free $0 / Founder $30/mo, credit-based, 20% revenue-withdrawal fee; self-reported $740k ARR in 33 days).
   - **Differentiation from Soleur:** founder-in-the-loop vs. no-human-in-the-loop; narrow revenue-engine scope vs. 8 domains (no engineering/legal/finance/product/support); cloud-hosted proprietary vs. git-tracked compounding knowledge base; 20% withdrawal-fee monetization wedge; shares Soleur's Anthropic-platform dependency. Closest existing analog: Polsia.

   **Annotation placement:** existing per-tier additions annotate at the tier header (`**Tier 0: ... ** [Added 2026-02-25]`). Because Tier 3 already exists and only one row is added, place `[Added 2026-06-08]` **inline in the Competitor cell** (after the link), which matches the row-level granularity the task specifies and avoids re-dating the whole tier. Do NOT add a tier-header date.

2. **`knowledge-base/product/competitive-intelligence.md`** — add ONE row to the **Tier 3: CaaS / Agent-Plugin Competitors** Overlap Matrix (header `| Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk |`, delimiter `|---|---|---|---|---|`). The 5 columns:
   - **Competitor:** `**NanoCorp** [Added 2026-06-08]`
   - **Our Equivalent:** `Full agent organization, autonomous execution` (mirrors the Polsia row's "Our Equivalent" phrasing — closest sibling).
   - **Overlap:** `**High**` (same as Polsia — both are direct "AI runs your company" thesis competitors).
   - **Differentiation:** the full product/pricing/stage detail (YC W24, solo founder, 1-prompt loop, Vercel+Stripe+Google Ads+outreach, $0 Free / $30/mo Founder credit-based, 20% withdrawal fee, self-reported $740k ARR in 33 days — **flag as marketing, not verified**). Bold the standout facts as the sibling rows do.
   - **Convergence Risk:** `**High.**` + the Soleur-differentiator list (founder-in-the-loop, 8-domain breadth, git-tracked memory, no revenue lock-in) and the "another hosted autonomous-CaaS entrant validating the category" framing. Close with the source citation in the row's trailing-link style: `([NanoCorp](https://nanocorp.so), [YC](https://www.ycombinator.com/companies/nanocorp), [Pricing](https://nanocorp.so/pricing), [review](https://www.alexisbouchez.com/reviews/2026/03/30/nanocorp))`.

   **Optional (low-priority, include only if trivially clean):** append a one-line dated intake note at the bottom of `competitive-intelligence.md` mirroring the existing `_Targeted intake 2026-05-30: ..._` italic note convention (line 118), recording: "Targeted intake 2026-06-08: added **NanoCorp** (`nanocorp.so`, YC W24 autonomous-AI-company platform) to Tier 3. Single-competitor addition, not a full monthly scan." This is consistent with the file's own precedent for single-competitor additions. If it risks scope-creep or conflicts with the Executive Summary's "since 2026-04-01 scan" framing, omit it — the matrix row is the required deliverable; the intake note is nice-to-have.

## Files to Create

None.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` for the two edited file paths — no open scope-outs touch `knowledge-base/product/business-validation.md` or `knowledge-base/product/competitive-intelligence.md`. (If `gh` is unavailable at /work time, this is a docs-only KB change with no code surface; the overlap risk is negligible.)

## Implementation Phases

### Phase 1 — Edit business-validation.md (Tier 3 row)
- Read the file, locate the Tier 3 table (under `**Tier 3: Company-as-a-Service / full-stack business platforms**`).
- Insert the NanoCorp 3-column row into the table body. Match exact pipe count (3 columns → 4 pipes per row) and the existing escaping conventions (no literal unescaped `|` inside cells).
- Place `[Added 2026-06-08]` inline in the Competitor cell.

### Phase 2 — Mirror into competitive-intelligence.md (Tier 3 matrix row)
- Read the file, locate the Tier 3 Overlap Matrix.
- Insert the NanoCorp 5-column row (5 columns → 6 pipes per row).
- Use the Polsia row as the structural template for cell density and the trailing source-link style.
- Optionally append the dated intake note per the Files-to-Edit note above.

### Phase 3 — Verify
- Run the table-integrity check (see Acceptance Criteria) to confirm pipe counts and that NanoCorp appears exactly once per file.
- Confirm the two same-named-entity disambiguation holds (`.so` not `.ai` in every NanoCorp link).

## Acceptance Criteria

### Pre-merge (PR)
- [x] `knowledge-base/product/business-validation.md` Tier 3 table contains exactly one NanoCorp row; `grep -c 'NanoCorp' knowledge-base/product/business-validation.md` returns ≥ 1 and the row sits inside the Tier 3 table block (between `**Tier 3:` and `**Tier 4:`).
- [x] The business-validation NanoCorp row has exactly 3 columns (4 `|` chars): verify the row matches `^| \[NanoCorp\].*|.*|.*|$`.
- [x] The Competitor cell carries the `[Added 2026-06-08]` annotation inline.
- [x] `knowledge-base/product/competitive-intelligence.md` Tier 3 Overlap Matrix contains exactly one NanoCorp row with exactly 5 columns (6 `|` chars), placed between `## Tier 3:` and `### Tier 3 Key Takeaways`.
- [x] Every NanoCorp hyperlink in both files points at the `nanocorp.so` domain (NOT `nanocorp.ai`): `grep -o 'nanocorp\.[a-z]*' <both files>` returns only `nanocorp.so`.
- [x] The `$740k ARR` figure (if cited) is hedged as self-reported/claimed, not stated as verified fact.
- [x] No existing competitor row, tier classification, or surrounding prose (Assessment, Vulnerabilities, Structural advantages, Executive Summary) was modified — `git diff` shows only additions (lines beginning `+`), zero deletions/modifications to existing rows.
- [x] Both files still render as valid markdown tables (no broken pipe alignment): a quick `awk -F'|' 'NF{print NF}'` over each table block shows a consistent field count.

### Post-merge (operator)
- None. Docs-only; no deploy, migration, or external-service step.

## Domain Review

**Domains relevant:** Product (advisory)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — no UI surface (`ux-design-lead` N/A: no `.pen`/component/page file in Files-to-Edit; this is internal-doc content only)
**Pencil available:** N/A (no UI surface)

#### Findings

The change edits internal competitive-strategy documents (Product domain content), but creates/modifies zero user-facing surfaces — no `components/**`, no `app/**/page.tsx`, no marketing-site `.njk`. The mechanical UI-surface override does not fire (no path in Files-to-Edit matches the UI-surface glob set). Per the ADVISORY pipeline rule, auto-accept and proceed. The competitive placement itself (Tier 3, Polsia-sibling) is the product-judgment call and is justified in the Overview; no CPO escalation needed at `threshold: none`.

## Infrastructure (IaC)

Not applicable — this plan introduces no new infrastructure (no server, service, scheduled job, secret, vendor account, DNS record, or persistent runtime process). It is a pure markdown-content change under `knowledge-base/`. The Phase 2.8 routing-gate trigger scan found no provisioning, vendor-dashboard, or secret-write framing in the actual change; the only token matches were in this section's own negative prose, acknowledged via the `iac-routing-ack` comment in the frontmatter.

## Observability

Not applicable — pure-docs change with no Files-to-Edit under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no new infrastructure surface. Phase 2.9 skip condition (pure-docs) is met.

## GDPR / Compliance

Not applicable — no regulated-data surface (no schema, migration, auth flow, API route, `.sql`). No LLM processing of operator-session data, no new distribution surface beyond the in-repo docs. None of the (a)-(d) expanded triggers fire. Skipped.

## Test Scenarios

This is a content addition with no executable code path. "Tests" are the Acceptance-Criteria grep/awk integrity checks (pipe counts, single-occurrence, `.so`-domain, additions-only diff). No new test framework — no test runner is appropriate for a markdown-content change; the AC checks are the verification.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Classify NanoCorp into Tier 0 (Platform Threats) | NanoCorp is not a model/platform vendor; it is built on top of foundation models (a hosted product, not a platform surface Soleur depends on). Tier 0 is reserved for Anthropic Cowork / OpenAI Codex / Claude Code marketplace. |
| Classify into Tier 2 (No-code AI agent platforms) | Tier 2 (Lindy, Relevance) is horizontal agent-builders. NanoCorp is not a builder — it autonomously *runs whole companies*, which is the Tier 3 CaaS thesis. |
| Skip the competitive-intelligence.md mirror | Rejected: the task conditions the mirror on "if that report's tier tables cover the chosen tier." competitive-intelligence.md DOES cover Tier 3, so the mirror is required, not optional. |
| Re-run a full landscape scan via `/soleur:competitive-analysis` | Explicitly out of scope per the task. This is a single-competitor addition only. |

## Non-Goals / Out of Scope

- Re-running a competitive scan, re-classifying existing competitors, or refreshing stale figures (Polsia ARR, Paperclip stars, etc.).
- Editing the Assessment verdict, Structural advantages, Vulnerabilities, or Executive Summary prose.
- Filing capability-gap GitHub issues (the Viktor-style `#4670-#4674` treatment) — NanoCorp surfaces no new Soleur capability gap beyond what Polsia already represents; no deferral issues needed.
- Adding NanoCorp to `roadmap.md` or any marketing copy.

## Sharp Edges

- **Table format differs between the two files.** `business-validation.md` Tier 3 uses a **3-column** table (`Competitor | Approach | Differentiation from Soleur`, delimiter `|---|---|---|`). `competitive-intelligence.md` Tier 3 uses a **5-column** matrix (`Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk`, delimiter `|---|---|---|---|---|`). Do not cross-paste a row between them — the pipe counts differ. Verified against the live files at plan time.
- **Two companies named "NanoCorp."** `nanocorp.so` (target, autonomous AI companies, YC W24) vs `nanocorp.ai` (NANO Corp, Paris network-security, founded 2019). Every link MUST use `.so`. AC includes a `.so`-only grep gate.
- **Self-reported metrics.** "$740k ARR in 33 days" is founder-LinkedIn marketing. Hedge it exactly as the existing Polsia ("self-reported") and Viktor ("treat metrics as marketing, not verified") rows do. Do not state it as verified fact.
- **Annotation granularity.** Tier 0 in business-validation.md annotates `[Added ...]` at the *tier header* because the whole tier was new. NanoCorp is a single row in an existing tier, so the annotation goes *in the Competitor cell*, not on the tier header. Do not re-date the Tier 3 header.
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with `threshold: none` and a non-empty reason.

## References

- Target site: https://nanocorp.so (homepage, `/pricing`, `/blog/what-is-an-autonomous-ai-company`)
- YC profile: https://www.ycombinator.com/companies/nanocorp (W24, founded 2023, team 1, San Francisco)
- Third-party review: https://www.alexisbouchez.com/reviews/2026/03/30/nanocorp
- Self-reported traction: founder LinkedIn post ("$740k ARR in 33 days", ~April 2026) — marketing, unverified.
- Sibling competitor (closest analog): Polsia row in both `business-validation.md` Tier 3 and `competitive-intelligence.md` Tier 3.
- Positioning vocabulary: `knowledge-base/marketing/brand-guide.md` (founder-in-the-loop, 8 domains, compounding git-tracked knowledge base, CaaS tagline).
