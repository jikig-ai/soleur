# Tasks — feat-one-shot-6768-polsia-figure-unverified

Derived from `knowledge-base/project/plans/2026-07-20-fix-polsia-unverified-figure-on-published-comparison-pages-plan.md` (v2, post-7-agent review).

**Closes #6768.**

Edit by **quoted content anchor**, never line number — the first rewrite in a file invalidates every subsequent line number (`cq-cite-content-anchor-not-line-number`). Line numbers in the plan are cross-references only.

**Copy rule for every rewrite task below (deepen-plan finding 2): prefer attribution over vague hedging.** Write *"third-party reports cite figures ranging from ~$689K to ~$10M ARR"*, not *"figures are contradictory across sources"*. Attributed, bounded, quantitative claims extract well; vague hedging degrades extraction fidelity and reads as mush. Accepted tokens for AC2: `reported`, `vendor-reported`, `claimed`, `contradictory`, `unverified`, `attributed`, `according to`.

**Why the JSON-LD matters (corrected rationale):** Google's FAQPage rich results were deprecated 2026-05-07 — there is no rich result and no penalty for divergence. The `acceptedAnswer` is still load-bearing because answer engines **tokenize the `<script>` block as raw text** rather than parsing it semantically, so a wrong `acceptedAnswer` remains directly quotable by an LLM. Tasks 2.5/2.7/3.2 and ACs 6.4/6.5 are unchanged; only the justification changed.

---

## Phase 0 — Preconditions (no edits)

- [x] **0.1** Confirm `knowledge-base/product/competitive-intelligence.md` Tier-3 Polsia row still reads `last_updated: 2026-07-04`. If a newer scan landed, re-derive the canonical framing **and** update AC6's hardcoded tokens in the same commit; note in PR body.
- [x] **0.2** `curl -sS -o /dev/null -w '%{http_code}\n' --max-time 15 -L https://aiweekly.co/alerts/polsia-solo-founder-raises-30m-at-250m-valuation`. **403 is expected and acceptable** (bot-gated CDN, already canonical at `competitive-intelligence.md:98`). Fallback only on `404`/`410`/DNS failure → cite `https://polsia.com/` with an unlinked "reported May 2026". Record the code.
- [x] **0.3** Verify the Paperclip star count **and canonical repo** (`paperclipai/paperclip` vs `agencyenterprise/paperclip-ai` — ambiguity flagged at `competitive-intelligence.md:199`). **If unconfirmed, drop the count** rather than update it.
- [x] **0.4** Informational baseline: `grep -rn "1\.5M" --include="*.md" . | wc -l` → 54 (16 files). Do **not** gate on this.
- [x] **0.5** Re-read the plan's LEAVE list. Edit only the 6 FIX paths, by explicit path. **No `sed -i` across grep hits** — it would overwrite the two E1 records that report this defect.

## Phase 1 — `knowledge-base/marketing/seo-refresh-queue.md` (FIRST — regeneration clock)

`cron-content-generator` fires **Tue 2026-07-21 10:00 UTC** and selects the highest-priority row **without a `generated_date`**. Two contradictory un-annotated P1 "Soleur vs. Polsia" rows currently exist.

- [x] **1.1** Row in the **2026-03-12** block (`Polsia at $450K+ ARR (revised down from $1.5M), 500+ managed companies`): annotate `generated_date: 2026-07-20` + mark superseded by the 2026-06-08 block.
- [x] **1.2** Row in the **2026-06-08** block (`Soleur vs. Polsia | Stale — Update`): mark done/annotated — corrected by this PR.
- [x] **1.3** §3.1 monitoring row: refresh to `$30M @ $250M`; ARR/customer counts contradictory/unverified; `$49/mo + 20% rev-share`. **Keep** the `revised down from $1.5M` provenance clause.
- [x] **1.4** **Do not touch** the `[2026-06-02 Review note]` line.

## Phase 2 — `plugins/soleur/docs/blog/2026-03-26-soleur-vs-polsia.md`

Rendered copy and JSON-LD twin are **matched pairs** — same commit, textually equivalent.

- [x] **2.1** **P0** — frontmatter `description:` (`Polsia runs your company autonomously for $29/month`): drop the price or state `$49/mo + 20% revenue share`. This is the SERP snippet and `og:description`.
- [x] **2.2** Lede (`Polsia hit [$1.5M ARR with 2,000+ managed companies](…)`): funding-round framing + new citation URL.
- [x] **2.3** Insert the correction-note template verbatim immediately after the lede.
- [x] **2.4** FAQ `**Q: Polsia reached $1.5M ARR…**` → *"Polsia raised $30M at a $250M valuation. Doesn't that prove autonomous CaaS works?"*
- [x] **2.5** JSON-LD `Question.name` → byte-identical to 2.4.
- [x] **2.6** FAQ rendered answer: concede the round validates the category; keep the output-quality/trajectory/stakes argument; add the **one-clause** hedge.
- [x] **2.7** JSON-LD `acceptedAnswer.text`: semantically identical to 2.6, self-contained (no page context), em-dashes per existing block style.
- [x] **2.8** Body pricing (`$29-59/month`, ~3 sites) → `$49/mo base`. **Keep** the 20% rev-share arithmetic (`$2,000/month on $10k revenue`) — still accurate.
- [x] **2.9** `BlogPosting` JSON-LD: add/set `dateModified: 2026-07-20`; leave `datePublished` at the March date. **Do NOT add schema.org `correction`/`CorrectionComment`** — defined but consumed by nothing (deepen-plan finding 3); the visible note does the real work.
- [x] **2.10** Confirm the JSON-LD block terminator stays a literal `</script>` and the new text introduces no raw `"` or control characters.

## Phase 3 — `plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md`

- [x] **3.1** Rendered "main open-source AI company platforms" answer: replace the Polsia `$1.5M / 2,000+` clause + anchor; re-ground *"fastest-growing proprietary alternative"* on the $30M round.
- [x] **3.2** JSON-LD `acceptedAnswer.text`: mirror 3.1.
- [x] **3.3** `14,600+ GitHub stars` (both surfaces): update per 0.3, or hedge to count-free phrasing if the repo is unconfirmed.
- [x] **3.4** Correction note + `dateModified: 2026-07-20`.
- [x] **3.5** Preserve `{{ stats.agents }}` / `{{ site.url }}` interpolations and the intentional rendered-vs-JSON-LD asymmetry (`{{ stats.agents }} agents` vs literal `purpose-built domain agents`).

## Phase 4 — `knowledge-base/marketing/distribution-content/soleur-vs-polsia.md`

Unpublished draft — correct outright, **no** correction note.

- [x] **4.1** Rewrite all **7** figure sites per the canonical framing.
- [x] **4.2** Rewrite all **4** `$29` sites, including the two pricing-math lines that argue against a `$29` headline now `$49`.
- [x] **4.3** **Channel-differentiated framing.** Discord/LinkedIn (long-form): lead with the round. **X/Bluesky (short-form): do NOT lead with the round** — the architecture question carries the hook, the round is setup in tweet 2; **omit revenue/customer figures entirely** rather than hedging (a proper hedge costs 40+ chars a 280-char tweet cannot spare).
- [x] **4.4** Hard-coded `63 agents` / `9 departments` → soft floors per `brand-guide.md:79`; reconcile the department count against "8 Departments" elsewhere in the same file and `competitive-intelligence.md`'s 8-domain.
- [x] **4.5** **Hard constraint (silent-failure risk):** introduce **no** `{{`, `}}`, `{%`, `%}` anywhere in the body; keep the four channel headings exact (`## Discord`, `## X/Twitter Thread`, `## LinkedIn Company Page`, `## Bluesky`); keep every mapped section non-empty. Any violation silently drops the file to `gateFailedDrafts` and it never publishes.
- [x] **4.6** Do **not** change `status:` or `publish_date:`.

## Phase 5 — Live internal surfaces

- [x] **5.1** `knowledge-base/marketing/marketing-strategy.md` content-gap item 3: re-ground on the $30M round; preserve the P-Critical ranking.
- [x] **5.2** `knowledge-base/product/competitive-intelligence.md` cascade note: strike the stale *"business-validation.md Tier 3 still cites $1.5M ARR / 2,000+ companies"* clause.

## Phase 6 — Verification

`grep -c` exits 1 on zero matches — use `|| true` and assert the printed count so a passing check never reads as a command failure.

- [x] **6.1** `npx @11ty/eleventy` from repo root.
- [x] **6.2** **AC1** — `1.5M` and `2,000+` → 0 in `_site/blog/soleur-vs-polsia/index.html`, `_site/blog/soleur-vs-paperclip/index.html`, **and `_site/blog/feed.xml`**. (Pre-fix: 5+3, 2+2, 7+5.)
- [x] **6.3** **AC2** — run the hedge-proximity script over the two blog `.md` files **and** the distribution file; no unhedged `$10M|7,600|689K|85% retention|$1.5 million|thousands of companies`.
- [x] **6.4** **AC3** — bidirectional set equality between extracted `**Q:**` lines and built `FAQPage` `Question.name` values (filter `@type == "FAQPage"` — 3 JSON-LD blocks per page; normalize `—`→`--`, `’`→`'`).
- [x] **6.5** **AC4** — each changed `acceptedAnswer.text` shares its figure tokens (`$30M`, `250M`, `May 2026`) and ≥1 hedge verb with the rendered answer; prohibited set in neither.
- [x] **6.6** **AC5** — all JSON-LD blocks parse via `json.loads` (3 per page); `BlogPosting.dateModified` present and equal to the correction-note date.
- [x] **6.7** **AC6** — both built pages contain `$30M`, `250M`, `May 2026`, and the new citation URL; old `teamday.ai/…million-arr` URL → 0 under `plugins/soleur/docs/`.
- [x] **6.8** **AC7** — exactly one `**Updated 2026-07-20:**` per blog page, within the first 25 lines of body content; zero in the distribution file.
- [x] **6.9** **AC8** — distribution file: `1.5M`/`2,000+`/`$29` → 0; `$49` present; ≥1 hedge verb; zero Liquid markers; four headings present; mapped sections non-empty; `status: draft` + `channels` unchanged. Preferably run `isReadyDraft` against the edited file.
- [x] **6.10** **AC9** — no un-annotated P1 "Soleur vs. Polsia" row in either `seo-refresh-queue.md` block; `450K`/`500+` gone as live assertions; the `[2026-06-02 Review note]` line survives verbatim.
- [x] **6.11** **AC10** — changed paths ⊆ the 6 FIX paths + plan + `tasks.md` + `decision-challenges.md`. No LEAVE path in the diff, especially the two E1 escalation records and `audits/soleur-ai/2026-03-17-content-audit.md`.
- [x] **6.12** **AC11** — `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` and `validate-csp.sh _site` both exit 0.

## Phase 7 — Ship

- [x] **7.1** PR body: `Closes #6768` (body, not title). Record the Phase 0 curl code, the Paperclip repo/star verification outcome, and that OG images were verified textless.
- [x] **7.2** File follow-up issue: **drain `seo-refresh-queue.md`** — the 2026-06-08 cascade flagged 9 stale comparison pages; 8 remain. Give the queue a consumer (cascade → one issue per flagged page; `product-roadmap validate` reports undrained P1s). This undrained queue is the root cause of #6768.
- [x] **7.3** File follow-up issue: **`soleur-vs-cofounder` page + Tier-3 positioning refresh** (Cofounder rated *Critical — closest product match*, no page; the 2026-06-08 queue predates its 2026-06-14 addition).
- [x] **7.4** Confirm `ship` renders `decision-challenges.md` into the PR body (UC-1 brand-guide rule, UC-2 positioning refresh, T-1/T-2 copy taste) and files the `action-required` issue.
