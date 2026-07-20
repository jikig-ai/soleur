---
title: "fix: replace the unverified Polsia figure asserted as fact on published comparison pages, queued social copy, and the live regeneration queue"
date: 2026-07-20
type: fix
issue: 6768
branch: feat-one-shot-6768-polsia-figure-unverified
lane: cross-domain
plan_version: 2
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix: Polsia's unverified figure is asserted as fact on indexed pages, queued social copy, and the agent work queue

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec directory exists for this branch.

## Enhancement Summary

**Deepened:** 2026-07-20 · **Gates:** 4.5 (no network trigger), 4.6 PASS (`aggregate pattern`), 4.7 SKIP (pure-docs), 4.8 PASS (no PAT shapes), 4.9 SKIP (no UI surface), 4.55 (no downtime trigger). Both cited rule IDs verified active in `AGENTS.md` and absent from the retired registry.

**Key improvements**

1. **A v2 rationale was falsified and corrected.** The plan justified its rendered↔JSON-LD parity requirement on "Google's FAQPage policy requires visible content." Google **deprecated FAQPage rich results on 2026-05-07** — no rich result, no penalty. The requirement survives on stronger ground (answer engines tokenize the `<script>` block as raw quotable text), but shipping the dead rationale would have been the same paraphrase-without-verification defect this PR fixes.
2. **Canonical framing refined: attribution beats hedging.** Current AEO evidence shows hedged language *reduces* extraction fidelity; attributed, bounded, quantitative claims perform best. Converges with the CMO's independent "one clause" note. AC2's token set widened accordingly.
3. **`dateModified` confirmed; `CorrectionComment` explicitly rejected** — defined in schema.org, consumed by nothing.
4. Corrections propagated to `tasks.md` in the same pass.

**Prior round (v2, 7-agent panel)** corrected three false v1 claims, folded in a stale Paperclip star count, and rewrote a structurally vacuous parity AC — detail below.

---

**v2 — rewritten after a 7-agent review panel.** Three v1 claims were **false** and are corrected below (grep baseline, `seo-refresh-queue.md:208` disposition, `business-validation.md:124` hedging), one v1 instruction would have **shipped a known-stale figure** (Paperclip stars), and one v1 fallback rule would have **degraded a good citation** (403 ≠ dead). Ceremony trimmed per DHH/simplicity; verification strengthened per spec-flow (v1's AC5 was structurally vacuous).

## Overview

Two published, indexed Eleventy blog pages assert **"Polsia at $1.5M ARR / 2,000+ managed companies"** as settled fact — in rendered copy *and* inside a `FAQPage` JSON-LD `acceptedAnswer`. Because the claim sits in machine-ingested structured data, it is an AEO/trust defect: answer engines lift `acceptedAnswer.text` verbatim with no page context and no temporal qualifier.

`knowledge-base/product/competitive-intelligence.md` (Tier-3 Polsia row, `last_updated: 2026-07-04`) records a materially different picture: **$30M raised at a $250M valuation (Sound Ventures lead, True Ventures participating, May 2026)** — the verifiable signal — while **every revenue/customer figure is contradictory across sources** (~$10M ARR / 7,600 customers / 85% month-two retention in newer third-party reports; ~$689K run-rate implied by a Feb 2026 Mixergy interview; earlier scans citing $1.5M then ~$450K).

The fix is **not** to swap `$1.5M` → `$10M` — that reproduces the defect with a fresher unverified number. The fix is to **cite the verifiable signal and mark revenue/customer counts as vendor-reported and contradictory**, mirroring how `competitive-intelligence.md`, `business-validation.md:81`, and `battlecards/tier-3-polsia.md:25` already hedge.

Correcting the figure also *strengthens* the page. The issue notes the error "runs in the direction that flatters Soleur"; replacing a weak steelman ($1.5M ARR) with a much harder one (**a $30M round at a $250M valuation**) concedes the category is venture-validated and leaves the architecture argument — which turns on output quality and stakes, not capital — fully intact.

### Finding 1 — a queued social post carries the figure to four channels

`knowledge-base/marketing/distribution-content/soleur-vs-polsia.md` carries the figure **7 times** and is `status: draft` with `channels: discord, x, bluesky, linkedin-company`. `content-promotion.ts` `isReadyDraft()` gates on **four** conditions — `status === "draft"`, ≥1 channel, **no Liquid marker (`{{`, `}}`, `{%`, `%}`) anywhere in the body**, and ≥1 non-empty mapped section. This file passes all four. The live Inngest cron `cron-content-publisher` (`cron-manifest.ts:41`; `routine-metadata.ts:57` → **Daily 14:00 UTC**, Discord/X/LinkedIn/Bluesky) promotes ready drafts onto the next free Tue/Thu slot, then `scripts/content-publisher.sh` posts verbatim.

**Timing, measured not assumed:** the 28-day horizon from 2026-07-20 has **zero free Tue/Thu slots**, and `planPromotions` sorts filename-ascending, placing `soleur-vs-polsia.md` last of 7 ready drafts. Earliest realistic promotion **2026-08-11**, publish **2026-09-08**. **There is no publish race** — v1's "highest urgency / merge promptly" framing was wrong. Correct the payload; do not block promotion.

*Verified-not-assumed:* `promotion-config.yml` (`enabled: true`) governs the **compound** promotion loop (learnings → skills), a different subsystem. It neither gates nor arms the content publisher.

### Finding 2 — the real deadline is the regeneration queue, not the publisher

`cron-content-generator.ts:103` instructs: *"Read `knowledge-base/marketing/seo-refresh-queue.md` and identify the highest-priority item **without a `generated_date` annotation**. Priority order: Priority 1 first…"* — then writes a blog page and cascades through `/soleur:social-distribute`, which **overwrites** `distribution-content/<slug>.md` from the blog post (headless auto-selects Overwrite).

That file contains **two contradictory, un-annotated, P1 "Soleur vs. Polsia" rows**:

| Row | Says | v1 disposition |
|---|---|---|
| `:208` (2026-03-12 block) | `Polsia at $450K+ ARR (revised down from $1.5M), 500+ managed companies` | **LEAVE — wrong** |
| `:222` (2026-06-08 block) | `Stale — Update … raised $30M at $250M … Do not imply Polsia is shrinking` | untouched |

`_Updated:` footers and block-date headings are **human** supersession cues with **no machine semantics**. The generator selects by priority, not by block date. **v1 explicitly instructed "Do not touch L208" while claiming Phase 4 prevented regeneration — the mitigation named the wrong line.** Next `cron-content-generator` fire: **Tue 2026-07-21 10:00 UTC**, ~18 hours out. This, not the publisher, is the clock.

### Finding 3 — the derived-artifact direction makes v1's pricing split incoherent

`distribution-content/soleur-vs-polsia.md` is **generated from** the blog post. v1 corrected pricing in the derived file (`$49/mo + 20% rev-share`) while deferring blog-body pricing — so the next generation run re-derives `$29` into the file the AC just certified clean. **Fix pricing upstream too, or not at all.** This plan fixes it upstream.

The frontmatter `description:` at `2026-03-26-soleur-vs-polsia.md:5` — *"Polsia runs your company autonomously for $29/month"* — is the **SERP snippet and `og:description`**, carries no temporal qualifier, and is not body prose. It ships under a fresh "Updated 2026-07-20" stamp. **P0 regardless of the body-pricing decision.**

## Research Reconciliation — v1 claims corrected

| v1 claim | Reality (verified) | Response |
|---|---|---|
| `grep -rn "1.5M" --include="*.md" .` → 24 lines / 14 files | **54 lines / 16 files** (32/15 excluding this plan, which itself contains 22 hits) | Phase 0 gate restated; v1's gate would have hard-stalled |
| `seo-refresh-queue.md:208` is historical | **Live P1 input to `cron-content-generator`** (Finding 2) | Moved LEAVE → FIX |
| `business-validation.md:124` already hedged | **False.** Reads `Polsia ($29-59/month, 2,000+ companies)` — a bare assertion of count *and* stale price | Moved to LEAVE with an honest reason (dated `**Delivery format shift (2026-03-22):**` block) |
| Preserve Paperclip's `14,600+ GitHub stars` as unrelated | **Same defect class, ~3.6× stale** — `competitive-intelligence.md` records 53k+; sits in the same sentence *and* the same `acceptedAnswer` being rewritten | Folded in, with verify-before-cite |
| Citation URL returns 200; non-200 → fallback | **Returns 403** (bot-gated CDN, not dead). `competitive-intelligence.md:98` already cites it as canonical | Rule amended: `401/403/405/429` → cite and note; only `404/410`/DNS → fallback |
| AC5 guards rendered↔JSON-LD parity | **Structurally vacuous** — the JSON-LD literal lives *inside* the same `.md`, so `name in md` is always true | Rewritten to extract `**Q:**` lines and assert bidirectional set equality |
| Two published pages; figure in `acceptedAnswer` | Confirmed; **also in `Question.name`** on the Polsia page | Scope widened to the Q/A pair — but see the corrected rationale in Research Insights below; v1's "Google policy requires visibility" justification is **deprecated** |
| — | Atom feed `_site/blog/feed.xml` embeds full post content incl. JSON-LD: **7× `1.5M`, 5× `2,000+`** | Added to AC targets (self-heals on rebuild; AC coverage gap only) |
| — | Non-`.md` sweep (`.njk/.html/.json/.ts/.js/.yml`) → **zero**. OG images are textless line-art. `llms.txt` never enumerates posts | No further surfaces |

## User-Brand Impact

**If this lands broken, the user experiences:** an answer engine quoting Soleur's own `FAQPage` structured data to state a false, self-flattering figure about a named competitor — sourced to us, with our URL attached. A founder evaluating Soleur finds the discrepancy against Polsia's public $30M round and concludes Soleur's competitive claims are unreliable generally.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no user data, credentials, or money. Public-copy correctness defect.

**Brand-survival threshold:** `aggregate pattern` — harm compounds through repeated unverified assertions rather than any single-user incident. Now demonstrable, not projected: **nine pages were flagged stale on 2026-06-08; all nine remain stale six weeks later.** No per-PR CPO sign-off required.

## Sweep disposition

Swept by grep, then each hit classified by **decisive evidence** of live-vs-record. Do not rewrite history; do not leave a live surface uncorrected because it superficially resembles a record.

### FIX — live surfaces (6 files)

| File | Sites | Why live |
|---|---|---|
| `plugins/soleur/docs/blog/2026-03-26-soleur-vs-polsia.md` | frontmatter `description` (`$29`); lede; FAQ Q + A; JSON-LD `Question.name` + `acceptedAnswer.text`; `BlogPosting.dateModified`; body pricing | Published + in `sitemap.xml` + Atom feed |
| `plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md` | rendered platforms answer + its JSON-LD twin (Polsia figure **and** Paperclip star count); `dateModified` | Same |
| `knowledge-base/marketing/distribution-content/soleur-vs-polsia.md` | 7 figure sites + `$29` at 4 sites | Auto-promotes + posts to 4 channels (Finding 1) |
| `knowledge-base/marketing/seo-refresh-queue.md` | **`:208` row** (annotate/strike) + **`:222` row** (mark done) + `:152` monitoring row | Live P1 generator input (Finding 2) |
| `knowledge-base/marketing/marketing-strategy.md` | `:219` | Live CMO-owned directive; the figure is the load-bearing P-Critical justification |
| `knowledge-base/product/competitive-intelligence.md` | `:222` cascade note | Asserts `business-validation.md` "still cites $1.5M"; it was corrected 2026-06-08 |

### LEAVE — dated records (do not edit)

`seo-refresh-queue.md:17` (framed `[2026-06-02 Review note]`) · `todos/016-*` (`status: complete`) · `audits/soleur-ai/2026-03-25-growth-audit.md` · `audits/soleur-ai/2026-04-13-content-audit.md` · `audits/soleur-ai/2026-04-13-aeo-audit.md` · `audits/soleur-ai/2026-03-17-content-audit.md` (holds the old teamday URL) · `brainstorms/2026-05-05-command-center-runtime-brainstorm.md` · `business-validation.md:124` (dated `Delivery format shift (2026-03-22)` block — **not** hedged, but legitimately point-in-time) · **`plans/2026-07-20-chore-tempfile-…-plan.md:136` and `specs/feat-one-shot-6734-…/decision-challenges.md:104`** — the **E1 escalation records reporting this defect**; `:108` states *"Not fixable here … this is copy work on published pages."*

> **Sharp edge:** a naive `sed -i` across grep hits overwrites the two records that *report* this defect. Edit only the 6 FIX paths, by explicit path. `business-validation.md:81` and `battlecards/tier-3-polsia.md:25,27` are already correct — mirror their wording, don't touch them.

## Canonical replacement framing

Source of truth: `competitive-intelligence.md` Tier-3 Polsia row (`last_updated: 2026-07-04`).

- **Verifiable signal:** Polsia raised **$30M at a $250M valuation** (Sound Ventures lead, True Ventures participating, **May 2026**). Pricing **$49/mo base + 20% revenue share**.
- **Vendor-reported and contradictory — never state as fact:** ~$10M ARR / 7,600 customers / 85% month-two retention; ~$689K run-rate (Feb 2026 Mixergy); earlier $1.5M, then ~$450K.
- **Prohibited:** any single ARR or customer count as settled fact — **including `$10M`**.
- **Preferred form: attribution, not vague hedging** (see Research Insights). Write *"third-party reports cite figures ranging from ~$689K to ~$10M ARR"* — attributed, specific, and bounded — rather than *"figures are contradictory"*. Attribution carries the same epistemic honesty while remaining extractable; vague hedging degrades both.
- **Accepted hedge/attribution tokens** (AC2 keys on these): reported / vendor-reported / claimed / contradictory / unverified / attributed / *according to*.

**Brand-voice reconciliation (load-bearing).** `brand-guide.md` forbids hedging with *might/could/potentially*. That rule governs **Soleur's claims about itself**; attribution hedges on a third party's unverified metrics are a different move and are required here. Keep the hedge to **one clause** — *"reported figures vary widely across sources"* beats a three-source reconciliation in marketing copy.

**Do not import** `competitive-intelligence.md`'s internal line *"reviews describe Polsia output as basic"* — an unverified disparaging claim about a named competitor is the same defect class this PR fixes, pointed the other way. The page's existing conditional framing (*"only if the autonomous decisions are reliably good"*) stays conditional.

**Citation swap.** The current anchor `teamday.ai/ai/polsia-solo-founder-million-arr-self-running-companies` bakes the disputed figure into its slug. Replace with `https://aiweekly.co/alerts/polsia-solo-founder-raises-30m-at-250m-valuation` (already canonical at `competitive-intelligence.md:98`). **Measured 403** — bot-gated, not dead; cite it and record the code.

**Dated-post honesty.** Both posts are dated March 2026. Correct the standing claims inline, add **one** visible correction note per page immediately after the lede, and set `dateModified` in the `BlogPosting` JSON-LD. Template (use verbatim, substituting nothing but the date):

> `**Updated 2026-07-20:** This post originally cited vendor-reported ARR and customer figures for Polsia as fact. Those figures are contradictory across sources; the verifiable signal is Polsia's May 2026 raise. Revenue and customer counts below are attributed, not asserted.`

A page whose prose says "Updated 2026-07-20" while its structured data claims nothing changed since March is the same rendered-vs-JSON-LD incoherence this PR exists to remove.

## Research Insights (deepen-plan, 2026-07-20)

Three findings changed plan decisions. The first **invalidates a v2 rationale**; the second **refines the canonical framing**; the third confirms a choice.

### 1. Google FAQPage rich results are DEPRECATED — the parity rationale was wrong, the requirement survives

Google deprecated FAQPage rich results **2026-05-07** (docs removed June 2026, API support ending August 2026), after restricting them to authoritative government/health sites in August 2023. **No rich result renders, and there is no penalty or manual-action risk for markup that diverges from visible copy.**

So v2's stated justification — *"Google's FAQPage policy requires marked-up content be visible, so the pair must move together"* — **no longer holds.** That is a paraphrase-without-verification defect of exactly the class this PR exists to fix, and it is corrected here rather than shipped.

**The parity requirement itself still stands, for a stronger reason.** A Feb 2026 controlled experiment (Williams-Cook) showed ChatGPT and Perplexity extracting data from *intentionally invalid* schema — answer engines **do not parse JSON-LD semantically; they tokenize the `<script>` block as raw text.** A wrong `acceptedAnswer` is therefore still directly quotable by an LLM, independent of any Google feature. The defect is real; only the cited authority was wrong.

**Net effect on the plan:** AC3 and AC4 stay exactly as written. Their rationale changes from *"Google policy compliance"* to *"the JSON-LD string is LLM-extractable raw text."* If anything this raises AC4's importance — the `acceptedAnswer` is not decorative metadata, it is quotable prose.

- <https://developers.google.com/search/blog/2023/08/howto-faq-changes>
- <https://developers.google.com/search/docs/appearance/structured-data/faqpage>

### 2. Attribution beats hedging for answer-engine extraction

Current AEO consensus: **hedged language reduces extraction fidelity** — engines build uncertainty around qualified claims and quote them less. What performs best is *explicit source attribution with quantitative data in the same sentence* (`according to [Source] ([Year]), [figure]`). Where sources genuinely conflict, the guidance is to attribute each side rather than collapse to "contradictory".

This does **not** reverse the plan — leading with the verifiable $30M round is exactly the recommended shape (clean, attributable, quantitative). It **refines the hedge form**, and happily converges with the CMO's independent "keep it to one clause" note:

| Avoid | Prefer |
|---|---|
| "figures are contradictory across sources" | "third-party reports cite figures ranging from ~$689K to ~$10M ARR" |
| "unverified vendor metrics" | "Polsia has not published audited figures" |

Canonical framing updated accordingly; AC2's token set widened to include `attributed` / `according to`.

- <https://ziptie.dev/blog/faq-schema-for-ai-answers/>
- <https://phantom-iq.com/insights/how-perplexity-claude-and-chatgpt-choose-sources>

### 3. `dateModified` + a visible dated note is the right pair — skip `CorrectionComment`

Confirmed: update `dateModified` to the correction date, leave `datePublished` at the March date. schema.org does define a `correction` property and a `CorrectionComment` type (v30.0+), but **there is no evidence any engine consumes them** — they are markup for its own sake here.

Because engines tokenize rendered HTML rather than parsing metadata, the **visible** correction note is doing the real work; `dateModified` is the machine-side freshness signal. Plan v2 already prescribes exactly this pair. **No change** — and explicitly do *not* add `CorrectionComment`.

- <https://schema.org/correction> · <https://schema.org/datePublished>

### Out-of-scope observation

The FAQPage deprecation applies site-wide, not just to these two pages. Whether Soleur should keep investing in FAQPage blocks at all is a real question — but it is a site-wide AEO strategy decision, not a figure correction. **Not folded in.** Worth raising alongside the follow-up issues if the operator wants it.

## Implementation Phases

Edit instructions anchor on **quoted content**, never line numbers (`cq-cite-content-anchor-not-line-number`) — the first rewrite in a file invalidates every subsequent line number. Line numbers below are cross-references only, accurate at plan time.

### Phase 0 — Preconditions

1. Confirm `competitive-intelligence.md`'s Tier-3 Polsia row still reads `last_updated: 2026-07-04`. **If a newer scan landed, re-derive the canonical framing AND update AC6's hardcoded tokens in the same commit**, noting it in the PR body (v1's fallback contradicted its own AC).
2. `curl -sS -o /dev/null -w '%{http_code}\n' --max-time 15 -L <citation-url>`. **403 measured at plan time — expected and acceptable.** Fallback fires only on `404`/`410`/DNS failure; then cite `https://polsia.com/` with an unlinked "reported May 2026". Record the code in the PR body.
3. Verify the Paperclip star count and **canonical repo** (`paperclipai/paperclip` vs `agencyenterprise/paperclip-ai` — `competitive-intelligence.md:199` and the queue both flag the ambiguity). **If the repo cannot be confirmed, drop the count** rather than update it; "one of the most-starred" costs the sentence nothing.
4. Baseline: `grep -rn "1\.5M" --include="*.md" . | wc -l` → **54** (16 files). Informational only; do not gate on it.

### Phase 1 — `seo-refresh-queue.md` (do first — Finding 2's clock)

- **`:208`** (2026-03-12 block, `Polsia at $450K+ ARR … 500+ managed companies`): annotate `generated_date: 2026-07-20` and mark superseded by the 2026-06-08 block. This removes it from the generator's candidate set.
- **`:222`** (2026-06-08 block, `Soleur vs. Polsia | Stale — Update`): mark done/annotated — the page is corrected by this PR.
- **`:152`** (§3.1 monitoring row): refresh to `$30M @ $250M`; ARR/customer counts contradictory/unverified; `$49/mo + 20% rev-share`. **Keep** the `revised down from $1.5M` provenance clause — legitimate history inside a live row.
- **Do not touch `:17`.**

### Phase 2 — `2026-03-26-soleur-vs-polsia.md`

Rendered copy and its JSON-LD twin are **matched pairs** — same commit, textually equivalent.

| Anchor | Change |
|---|---|
| frontmatter `description:` (`$29/month`) | **P0.** Drop the price or state `$49/mo + 20% revenue share`. SERP + `og:description`. |
| Lede (`Polsia hit [$1.5M ARR with 2,000+ managed companies](…)`) | Funding-round framing + new citation |
| Correction note | Insert the template verbatim after the lede |
| FAQ `**Q: Polsia reached $1.5M ARR…**` | → *"Polsia raised $30M at a $250M valuation. Doesn't that prove autonomous CaaS works?"* |
| JSON-LD `Question.name` (same text) | Byte-identical to the rendered `**Q:**` |
| FAQ answer + JSON-LD `acceptedAnswer.text` | Concede the round validates the category; keep the output-quality/trajectory/stakes argument; add the one-clause hedge. JSON-LD version self-contained (no page context), em-dashes per existing block style |
| Body pricing (`$29-59/month` at ~`:24,76,82`) | → `$49/mo base`. **Keep** the 20% rev-share arithmetic (`$2,000/month on $10k revenue`) — still correct per `competitive-intelligence.md:98` |
| `BlogPosting` JSON-LD | Add/set `dateModified: 2026-07-20`; leave `datePublished` at the March date |

JSON-LD constraints: block terminator stays a literal `</script>` (only a `</script>` *inside* a string value needs `<\/script>`); new text introduces no raw `"` or control characters. These blocks are hand-written literals — `jsonLdSafe` does not apply.

### Phase 3 — `2026-03-31-soleur-vs-paperclip.md`

| Anchor | Change |
|---|---|
| Rendered platforms answer + JSON-LD `acceptedAnswer.text` | Replace the Polsia `$1.5M / 2,000+` clause + anchor. Polsia's role here is *"the fastest-growing proprietary alternative"* — re-ground on the $30M round, which supports it better than a contested ARR figure |
| `14,600+ GitHub stars` (both surfaces) | Update per Phase 0 step 3, or hedge to a count-free phrasing if the repo is unconfirmed |
| Correction note + `dateModified` | As Phase 2 |

Preserve the `{{ stats.agents }}` / `{{ site.url }}` interpolations and the existing intentional asymmetry (rendered uses `{{ stats.agents }} agents`; JSON-LD uses the literal `purpose-built domain agents`).

### Phase 4 — `distribution-content/soleur-vs-polsia.md`

Unpublished draft — correct outright, **no** correction note. Rewrite all 7 figure sites and all 4 `$29` sites (`:30,67,83,116`; the `:67`/`:116` pricing-math lines argue against a `$29` headline that is now `$49`).

**Channel-differentiated framing** — the correct move inverts by length:
- **Discord / LinkedIn (long-form):** lead with the round; the concession buys credibility.
- **X / Bluesky (short-form):** **do not lead with the round** — a tweet opening *"Polsia raised $30M at a $250M valuation"* is a competitor funding announcement from Soleur's handle. The architecture question carries the hook; the round is setup in tweet 2. **Omit revenue/customer figures entirely** rather than hedging — a proper hedge costs 40+ chars a 280-char tweet cannot spare, and a truncated hedge is worse than no figure.

Also fix, in the same file: hard-coded `63 agents` / `9 departments` → soft floors per `brand-guide.md:79`, and reconcile the department count (the same file says "8 Departments" elsewhere; `competitive-intelligence.md` says 8-domain).

**Hard constraint (silent-failure risk):** introduce **no** `{{`, `}}`, `{%`, or `%}` anywhere in the body, keep the four channel headings exact (`## Discord`, `## X/Twitter Thread`, `## LinkedIn Company Page`, `## Bluesky`), and keep every mapped section non-empty. Any violation drops the file to `gateFailedDrafts` and it silently never publishes — quietly achieving the "block the post" outcome this plan rejects. Do **not** change `status:` or `publish_date:`.

### Phase 5 — Live internal surfaces

- `marketing-strategy.md:219` — re-ground the content-gap justification on the $30M round; preserve the P-Critical ranking (a $30M-funded direct competitor justifies it at least as strongly).
- `competitive-intelligence.md:222` — strike the stale *"business-validation.md Tier 3 still cites $1.5M"* clause.

## Acceptance Criteria

> All commands verified against a real build at plan time. Baselines are **non-zero**, proving these ACs detect the defect rather than passing vacuously. `grep -c` exits 1 on zero matches, so every zero-assertion below uses `|| true` and asserts the printed count — a passing AC must not read as a command failure (`hr-when-a-command-exits-non-zero-or-prints`).

**AC1 — old figures gone from every rendered surface.** For `_site/blog/soleur-vs-polsia/index.html`, `_site/blog/soleur-vs-paperclip/index.html`, **and `_site/blog/feed.xml`** (the Atom feed embeds full post content including JSON-LD):
`npx @11ty/eleventy && for f in <3 paths>; do echo "$f $(grep -cE '1\.5M|2,000\+' "$f" || true)"; done` → **0** for all three.
*Verified pre-fix baselines:* polsia `5`+`3`, paperclip `2`+`2`, feed `7`+`5`.

**AC2 — no fresh unverified figure, anywhere in scope.** Runnable, and covering the distribution file (v1 omitted the highest-urgency surface):
```bash
FIGS='\$10M|7,?600|689K|85% (month-two )?retention|\$1\.5 ?million|thousands of (managed )?companies'
HEDGE='reported|vendor-reported|claimed|contradictory|unverified|attributed'
for f in plugins/soleur/docs/blog/2026-03-26-soleur-vs-polsia.md \
         plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md \
         knowledge-base/marketing/distribution-content/soleur-vs-polsia.md; do
  while IFS= read -r n; do
    grep -nE "$HEDGE" "$f" | awk -F: -v L="$n" '$1>=L-1 && $1<=L+1' | grep -q . \
      || { echo "UNHEDGED $f:$n"; FAIL=1; }
  done < <(grep -nE "$FIGS" "$f" | cut -d: -f1)
done; [ -z "$FAIL" ] && echo "AC2 PASS"
```

**AC3 — rendered↔JSON-LD question parity (bidirectional).** v1's version compared against the whole `.md`, which *contains* the JSON-LD, so it could never fail. Extract `**Q:**` lines specifically and assert set equality against the built `FAQPage` `Question.name` values, normalizing `—`→`--` and `’`→`'`. Filter on `@type == "FAQPage"` — **each page emits 3 JSON-LD blocks** (`BlogPosting` + `BreadcrumbList` + `FAQPage`).
*Verified: 4 FAQ questions on Polsia, 5 on Paperclip.*

**AC4 — `acceptedAnswer.text` agrees with the rendered answer.** The `acceptedAnswer` is the only machine-ingested string and was v1's sole unverified surface. For every changed Q/A: each figure token (`$30M`, `250M`, `May 2026`) and ≥1 hedge verb present in the JSON-LD `acceptedAnswer.text` must also appear in the rendered answer paragraph, and the prohibited set must appear in neither.

**AC5 — structured data valid and current.** Every `<script type="application/ld+json">` block in both built pages parses via `json.loads` (*verified: 3 blocks each, all 6 parse clean today*), **and** each page's `BlogPosting` carries `dateModified` equal to the correction-note date.

**AC6 — the verifiable signal is present and attributed.** Both built pages contain `$30M`, `250M`, `May 2026`, and the new citation URL; the old `teamday.ai/…million-arr` URL appears **0** times under `plugins/soleur/docs/`. (Built-scoped throughout, per "grep the built HTML, never only the source".)

**AC7 — correction notes.** Exactly one `**Updated 2026-07-20:**` per blog page, matching the template, positioned within the first 25 lines of body content; **zero** in the distribution file.

**AC8 — social draft correct AND still cron-eligible.** In `distribution-content/soleur-vs-polsia.md`: `1.5M`, `2,000+`, `$29` → 0; `$49` present; ≥1 hedge verb present; **zero Liquid markers (`{{`/`}}`/`{%`/`%}`)**; the four channel headings present; every mapped section non-empty; `status: draft` and `channels` unchanged. Preferably by running `isReadyDraft` against the edited file directly.

**AC9 — regeneration queue drained (Finding 2).** In `seo-refresh-queue.md`: no un-annotated P1 "Soleur vs. Polsia" row remains in **either** block; `450K` and `500+` no longer appear as live assertions; **the `:17` review note survives verbatim** (line-scoped — the file is legitimately in the diff, so a path-level assertion cannot express this).

**AC10 — diff scope.** Changed paths ⊆ the 6 FIX paths + this plan + `tasks.md` + `decision-challenges.md`. Asserts, in particular, that no LEAVE path — especially the two E1 escalation records and `audits/soleur-ai/2026-03-17-content-audit.md` — appears in the diff.

**AC11 — site gates.** `validate-seo.sh _site` and `validate-csp.sh _site` both exit 0. *Verified passing today (60 pages).*

### Post-merge (operator)

None. `deploy-docs.yml` deploys on merge; social publication is handled by the existing cron. No human step.

## Observability

**Skipped — pure-docs change.** No file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`; no new code path, failure mode, or alert route (Phase 2.8 triggers do not fire). The plan changes a live cron's *payload*, never its code, schedule, or gating — which is why AC8's `isReadyDraft` assertion carries the eligibility postcondition instead.

## Architecture Decision (ADR/C4)

**No ADR; no C4 impact.** No data-model, tenancy, substrate, dispatch, or trust-boundary decision; no ADR diverged from. All three `.c4` files reviewed: no external human actor, external system/vendor, container/data-store, or actor↔surface access relationship changes. Polsia is a market participant named in prose, not an integration — correctly absent from `model.c4`'s `#external` set (which covers integration dependencies). The social publishing edges already exist; only the payload changes.

## Domain Review

**Domains relevant:** Marketing, Product, Legal

**Marketing (reviewed).** Owns the primary surface. The correction is net-positive for positioning: conceding a $30M round is the credibility purchase that makes the rest of the page believable, and visible hedging is itself an AEO trust signal. Channel-differentiated framing (Phase 4) and the brand-voice reconciliation are CMO conditions carried into the plan.

**Product (reviewed).** A cascade-**completion** defect: the source of truth updated (2026-06-08, 2026-07-04) and published downstream surfaces did not follow. Scope note, corrected from v1: the *figure fix* is posture-neutral, but the *page's positioning frame* is one CI revision behind — `competitive-intelligence.md:120` holds that "founder-in-the-loop + breadth + no-lock-in" no longer carries the headline contrast at this tier post-Cofounder. Deliberately **not** folded in (a positioning revision across all Tier-3 pages, CMO-owned); tracked as a follow-up so the "Updated 2026-07-20" stamp is not read as a clean bill of health on the thesis.

**Legal (advisory, low).** Publishing unverified financial figures about a **named competitor** as fact carries a small commercial-disparagement exposure that this fix reduces. The corrected posture — cite the verifiable round, attribute contested metrics, hedge explicitly — is the defensible one, and the direction of the current error (understating a competitor in a way that flatters us) is the direction that attracts scrutiny. No personal data: GDPR gate does not fire.

**Product/UX Gate:** Tier NONE — no UI-surface path in Files to Edit.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A naive `sed -i` sweep overwrites the two E1 records that report this defect | Explicit-path edits only; AC10 |
| Corrected social copy silently fails `isReadyDraft` (stray `{{` from copy-pasting blog text) and never publishes | Phase 4 hard constraint + AC8 runs the predicate |
| `cron-content-generator` fires Tue 2026-07-21 10:00 and regenerates from a stale P1 row | Phase 1 sequenced first; AC9 |
| Blog pricing left stale while the derived social file is corrected → next generation re-derives `$29` | Phase 2 fixes pricing upstream (Finding 3) |
| Paperclip star count unverifiable (repo ambiguity) | Phase 0 step 3: drop the count rather than guess |

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Swap `$1.5M` → `$10M` | **Rejected** — forbidden by fix requirement 1; reproduces the defect with a fresher unverified number |
| Delete the Polsia FAQ entry | **Rejected** — the load-bearing rebuttal on a page whose purpose is that comparison; removes the AEO surface instead of correcting it |
| Silently revise the dated posts | **Rejected** — the same trust defect in a different form, and the one that gets screenshotted. No SEO penalty for correction notes; AEO-positive |
| Block/unschedule the queued post (`status: hold`) | **Rejected on measurement, not principle** — no publish race exists (earliest publish 2026-09-08), and `status: parked` would feed the starvation detector and require an unpark follow-up |
| Build a published-surface drift detector | **Rejected** — the cascade detector already works and already caught this on 2026-06-08; the missing piece is a *drain*, not detection. Filed as a follow-up |
| Fold in the Tier-3 positioning refresh (post-Cofounder) | **Deferred** — a positioning revision across all Tier-3 pages, CMO-owned; smuggling it into a fix PR is the wrong vehicle. Tracking issue required |

## Follow-Up Issues (file with the PR)

1. **Drain `seo-refresh-queue.md`** — the 2026-06-08 cascade flagged 9 stale comparison pages; 8 remain after this PR. Give the queue a consumer (cascade opens one issue per flagged page; `product-roadmap validate` reports undrained P1s). The undrained queue is the root cause of this issue.
2. **`soleur-vs-cofounder` comparison page + Tier-3 positioning refresh** — Cofounder is rated *Critical — closest product match* in CI and has no page; the 2026-06-08 queue predates its 2026-06-14 addition, so nothing has flagged it.

## PR Body Reminder

`Closes #6768` in the body (not the title). Record: the Phase 0 curl status code, the Paperclip repo/star verification outcome, that OG images were verified textless, and the two follow-up issue numbers.
