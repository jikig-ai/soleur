---
title: Competitive-intelligence doc split + living-KB sharding convention
date: 2026-10-24
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 11032
worktree: .worktrees/feat-competitive-intel-doc-split
---

# Brainstorm: Split `competitive-intelligence.md` into index + shards

## What We're Building

`knowledge-base/product/competitive-intelligence.md` is 569 lines / ~134 KB (not 458 — it grew during the session) and is becoming unreadable for humans and agents. ~52% of it is two embedded peer-plugin audits (mattpocock/skills ~200 lines, humanlayer ~90); a second growth vector is the Executive Summary accumulating six dated "targeted addition" blocks — it is becoming a changelog.

The feature has three parts:

1. **Restructure the doc** into a stable-path index + a sibling `knowledge-base/product/competitive-intelligence/` shard directory (Option A below).
2. **Update every producer surface in lockstep** so the next monthly cron run and peer audits write the new structure instead of silently dropping shard writes.
3. **Ship a reusable "living KB doc sharding" convention** — an ADR in this repo plus a plugin-carried reference doc — so other Soleur users' growing curated docs get the same treatment.

## Why This Approach

All six consulted leaders/researchers (CPO, CLO, CTO, CMO, repo-research, learnings-research) independently converged on the same shape:

- **Keep `competitive-intelligence.md` as the index at its exact path.** ~15 live files carry `depends_on` / citation pointers to it (7 battlecards, roadmap.md, pricing-strategy.md, content-strategy.md, seo-refresh-queue.md, marketing-strategy.md, business-validation.md, research/pricing-findings.md); two test files assert the path verbatim; the strategy-review scanners (`strategy-review-check.sh`, `cron-strategy-review.ts`) read **top-level** `knowledge-base/product/*.md` only — moving the frontmatter-bearing index into a subdirectory silently stops the monthly Strategy Review issue stream. Git permits a file and same-stem directory as siblings, and the dashboard URL `/dashboard/kb/product/competitive-intelligence.md` stays live.
- **Shard the records, keep the living synthesis in the index.** The index retains: frontmatter (unchanged semantics incl. `last_reviewed`), a slim Executive Summary, all six tier **overlap matrices** (the cascade's machine-read schema — 4 specialist agents extract the competitor list from them), Key Takeaways, New Entrants, Recommendations, and Cascade Results. Shards hold dated/point-in-time records and per-competitor detail.
- **Reject per-competitor-everything (Option C).** Dissolving the matrix into per-competitor files destroys the doc's main analytical surface (side-by-side comparison) and breaks the cascade extraction contract outright. Per-tier shards (Option B) was the runner-up: thinnest index but forces product-roadmap (reads exec summary + tier-0 from one file) and all four cascade prompts to be retargeted for ~the same readability gain.

### Index layout (target ≈150–220 lines)

- Frontmatter: unchanged (`last_updated`, `last_reviewed`, `review_cadence`, `owner`, `depends_on`, `tiers_scanned`) — stays the single freshness surface.
- Executive Summary: narrative synthesis only; the six dated intake blocks move to their competitor shards, replaced by one-line links.
- Tier 0–5 sections: overlap matrix + Key Takeaways per tier; **Differentiation cells are slimmed to the key differentiator plus a `→ detail` link** for competitors that have shards (a style rule the agent contract must enforce).
- New Entrants, Recommendations, Cascade Results stay (Cascade Results regenerates monthly and is bounded).
- A short `## Detail files` map at the bottom listing the shard directory (human/agent routing).

### Shard layout (`knowledge-base/product/competitive-intelligence/`)

- `audits/<owner>-<repo>.md` — peer-plugin audits (the mattpocock and humanlayer sections move verbatim, including their dated addenda).
- `tier-<N>-<slug>.md` — per-competitor detail (battlecards naming precedent): positioning narrative, metrics history, dated targeted-addition blocks, full source list. Created only for competitors that have deep records (Cofounder, Multica, Omnigent, Sutra, HumanLayer, Polsia, NanoCorp…); matrix rows without detail stay link-free.
- Shard frontmatter is **minimal** — `title`, `competitor`/`target`, `tier`, `last_updated`, `publishable: internal|external` (CLO: formalizes the Sutra precedent). **No `review_cadence` / `owner` / `depends_on` on shards**: `review-reminder.yml` scans all depths and would mint a monthly issue per shard, while `strategy-review-check.sh` scans only top-level — keeping the review machinery pointed at the index only is both spam-free and correct.
- Shards back-link `../competitive-intelligence.md`; index links doc-relative (`competitive-intelligence/tier-3-polsia.md`). Both resolve in-app (catch-all `[...path]` route + verbatim `<a href>` rendering) and on GitHub.
- **No shard named `INDEX.md`** — `generate-kb-index.sh` excludes `INDEX.md` at any depth; shards otherwise auto-appear in the generated index with zero registration.

### Producer lockstep changes (required — the silent-persist-drop fix)

`COMPETITIVE_ANALYSIS_ALLOWED_PATHS` uses bare `startsWith` matching, so the hybrid layout needs **both** the existing `knowledge-base/product/competitive-intelligence.md` entry **and** a new `knowledge-base/product/competitive-intelligence/` trailing-slash entry (precedent: `knowledge-base/sales/battlecards/`). In the same commit: the verbatim PERSISTENCE prompt path list (`cron-competitive-analysis.ts` ~L157), the `toEqual` allowedPaths assert + prompt canary (`cron-competitive-analysis.test.ts`), and the cohort-dedup fixtures (`cron-cohort-dedup.test.ts`). Then the instruction surfaces: agent output contract (`agents/product/competitive-intelligence.md` — index+shard write contract, slim-cell rule, exclusive-write re-scoped to index+dir, cascade task prompts still hand specialists the index path), `competitive-analysis/SKILL.md` (L16/L58 + stale deleted-GHA reference at L67–69 fixed inline), and `peer-plugin-audit.md` (the biggest rewrite — "update in place in the right tier" becomes "upsert `audits/<owner>-<repo>.md` + update the index audit row"; the L207 "no parallel files" rule is superseded by this design and must be rewritten, not silently contradicted; its `last_reviewed`-bump instruction is an ADR-094 violation — fix to `last_updated` while there).

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Index stays at `competitive-intelligence.md`; sibling `competitive-intelligence/` dir | Zero consumer churn (~15 `depends_on` refs, test canaries, dashboard URL, top-level review scanners all preserved) |
| 2 | Option A: shard records + per-competitor detail; matrices stay in index (operator-approved) | Preserves the comparison surface + cascade contract; destroys nothing |
| 3 | Shards carry minimal frontmatter — no `review_cadence`/`owner`/`depends_on` | `review-reminder.yml` scans all depths → per-shard cadence = monthly issue spam; review machinery stays on the index |
| 4 | `publishable: internal|external` on shard template | CLO: formalizes the Sutra Art. 4(c) precedent; SEO cascade gets a machine-readable publication gate |
| 5 | Producer changes ship in the same PR as the split | Allowlist widening separate from the restructure = a window where shard writes are silently discarded while runs report green (ADR-126 class, one level down) |
| 6 | Convention ships as ADR + plugin reference doc (operator-approved); no new skill | `SKILL_DESCRIPTION_WORD_BUDGET` headroom is ~2 words; a `kb-shard` skill (~25-30 word description) needs sibling trims or a budget bump — premature while there's one consumer |
| 7 | Convention doc explicitly excludes append-only legal/compliance registers | CLO: `article-30-register.md`, `compliance-posture.md`, breach register rely on single-file `> **Superseded …**` in-cell corrections — sharding breaks that discipline |
| 8 | Dated intake blocks move into their competitor's shard; Cascade Results stays in the index | Intake blocks are per-competitor history; Cascade Results is a bounded per-run record the operator expects in the main doc |
| 9 | Convention doc home: `plugins/soleur/skills/competitive-analysis/references/living-kb-doc-sharding.md` linked from the agent contract + ADR | Plugin ships it to other users; producer contracts are the actual discovery mechanism for agents (plan may relocate if a shared `plugins/soleur/references/` home is preferred) |
| 10 | Orphan policy: index links are the live set; old audit/intake shards are append-only dated records, never regenerated | Monthly run regenerates index + touched shards; a competitor dropped from the landscape keeps its shard (dated record) and loses its index row |
| 11 | `context-reviewed-gate.sh` will trip on `last_reviewed` line moves | Work-phase note: restructure commits need a `Context-Reviewed:` trailer |

## Open Questions

- **Second consumer for the convention** — `content-strategy.md` (511 lines) and `seo-refresh-queue.md` (255 lines) are on the same growth curve (CMO). When a second doc crosses the threshold, re-evaluate whether the convention should move to a shared `plugins/soleur/references/` home or a `kb-shard` skill. `(parked — concrete trigger: second doc >~500 lines or a second sharding request)`
- **Per-shard staleness surfacing** — `last_updated` per shard is machine-readable; whether programmatic-seo-specialist should consume per-shard freshness for the seo-refresh queue is a cascade follow-up, not this PR. `(parked)`
- **`product/competitive-analysis.md` name proximity** — `DASHBOARD_FOUNDATION_KB_PATHS` contains that distinct doc; keep shard filenames clearly distinct to avoid confusion. `(verify at plan time)`
- **Liveness tightening** — handler liveness is GREEN if *any* allowlisted path commits; consider requiring the index path specifically so a run that produced only shard writes can't read as fully successful. `(decide at plan time — CTO)`

## User-Brand Impact

- **Artifact:** `knowledge-base/product/competitive-intelligence.md` + the `competitive-intelligence/` shard directory + the monthly cron's persistence surface.
- **Vector:** worst case — a restructure that drops shard writes silently (allowlist miss) or severs per-claim sources/verifiability qualifiers from the claims they qualify, propagating unverified competitor figures into public comparison pages.
- **Threshold:** `single-user incident`. Blast radius confirmed single-user: every failure mode lands in the operator's own KB; no production runtime, no user data, no multi-tenant surface.

## Lane

`cross-domain` (auto — `USER_BRAND_CRITICAL` set unconditionally per #5175).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Net-positive; keep the index at the existing path and shard records+detail only. The exec summary is becoming a changelog — a split that only extracts audits leaves the index re-bloating via intake blocks. `peer-plugin-audit.md` L207's "no parallel files" rule must be explicitly rewritten, not silently contradicted. Convention is a real product surface worth shipping (Gap 14 proof point).

### Legal (CLO)

**Summary:** No new GDPR processing activity (format change, not processing change). Primary legal risk is qualifier severance — per-claim source URLs and "unverified" flags must stay adjacent to claims inside each shard. Adopt a `publishable:` frontmatter field; exclude append-only legal registers from the convention. Repo is public — shards remain published artifacts. Soft-recommend a scoped manual `soleur:gdpr-gate` run at plan time (path regex won't auto-fire).

### Engineering (CTO)

**Summary:** Medium complexity, mostly mechanical; three contract decisions (index location, shard granularity, shard frontmatter) each have a silent-degradation wrong answer. `isPathAllowed` is bare `startsWith` — hybrid layout needs both allowlist entries; `toEqual` test asserts the array; `context-reviewed-gate.sh` will trip on `last_reviewed` moves. Recommend an ADR for the convention alongside ADR-126/ADR-235.

### Marketing (CMO)

**Summary:** Net-positive if the shard boundary matches cascade access patterns and producers update in the same PR. Per-shard freshness helps battlecards + seo-refresh precision. The convention itself is a marketable capability (named-artifact lifecycle proof point); marketing's own `content-strategy.md`/`seo-refresh-queue.md` are future beneficiaries.

## Capability Gaps

None. All work routes through existing agents/skills; the convention is a docs/ADR artifact, not a new component.

## Productize Candidates

- **Productize Candidate: `kb-shard` skill** — a mechanical "analyze a curated doc → classify living vs dated lines → propose + apply shard layout → rewire producer surfaces" skill. Deferred: description budget headroom is ~2 words and there is one consumer today. Re-evaluation trigger: a second curated doc crossing ~500 lines (content-strategy.md is at 511) or an operator request to shard a non-CI doc.
