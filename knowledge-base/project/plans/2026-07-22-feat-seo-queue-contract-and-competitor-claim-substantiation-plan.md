---
feature: seo-refresh-queue producer/consumer contract + competitor-claim substantiation
issue: 6827
branch: feat-6827-seo-queue-consumer-tier3-positioning
pr: 6830
worktree: .worktrees/feat-6827-seo-queue-consumer-tier3-positioning
spec: knowledge-base/project/specs/feat-6827-seo-queue-consumer-tier3-positioning/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-07-22-seo-queue-contract-and-tier3-positioning-brainstorm.md
learning: knowledge-base/project/learnings/2026-07-22-no-consumer-claim-is-a-producer-consumer-contract-mismatch.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: feat
date: 2026-07-22
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# Plan — SEO Queue Contract + Competitor-Claim Substantiation

## Overview

Repair the `seo-refresh-queue.md` producer/consumer contract (FR3–FR5), close the residue of the
2026-07-20 comparison-page correction (FR1–FR2), make a silently non-draining queue self-report
(FR6), and separate verified from unsubstantiated competitor claims at the source of truth (FR7)
and at the review gate (FR8).

The consumer cron is **live at 2x/week** (`0 10 * * 2,4`, audit issue #6818 open); the producer is
dark ~90d (#4375, out of scope per NG4). FR4 + FR5 therefore change observed behaviour on the next
Tuesday/Thursday fire. That blast radius is the reason this plan is written at
`brand_survival_threshold: single-user incident`.

**Eight functional requirements, four of which the plan-time research materially re-shaped.** The
Research Reconciliation table below is load-bearing: two spec Technical Requirements rest on
artifacts that no longer exist, one FR names the wrong file, and one FR under-enumerates its own
write-sites. None of these were catchable from the spec text alone.

---

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified 2026-07-22) | Plan response |
|---|---|---|
| **TR1** — "FR3 and FR4 must be applied in lockstep with their verbatim mirrors in `.github/workflows/*.yml`" | **FALSE — the mirrors do not exist.** `.github/workflows/scheduled-content-generator.yml` was deleted by PR #4483 and `scheduled-competitive-analysis.yml` by PR #4443 (TR9 Inngest migration, ADR-030/ADR-033). `grep -rln "seo-refresh-queue" .github/workflows/` returns **zero**. The in-code comments citing those YAML paths are historical provenance notes, not live mirrors. | **TR1 is retired.** There is no second side to edit. Recorded as a spec correction; the `Verbatim prompt extracted from …` comments get a `[superseded]` note so the next reader is not sent hunting. |
| **TR1/TR2** — "Both prompts are anchor-tested … editing one side alone breaks the parity test" | **Half true.** The tests are NOT cross-artifact parity tests — they `readFileSync` the TS source and assert anchor substrings (`cron-content-generator.test.ts:54-60, 76-115`). No YAML is read. The consumer's asserted anchors are `seo-refresh-queue`, `content-writer`, `social-distribute`, `validate-blog-links`, `PERSISTENCE: Do NOT run git add`, `Do NOT push directly to main`, `opens a PR for your changes`, `scheduled-content-generator`, `MILESTONE RULE:`, `@11ty/eleventy`. **None sits on the STEP 1 predicate line.** | **TR2 survives and is honoured.** FR4's edit is confined to the STEP 1 sentence and touches no asserted anchor. A **new** anchor test is added for the positive predicate so the fix itself becomes regression-guarded. |
| **FR3** — "amend the producer prompt in `cron-competitive-analysis.ts` (`:166`)" | **Wrong file.** `COMPETITIVE_ANALYSIS_PROMPT` (`:137-152`) contains **no** queue-write instruction at all — it only runs `/soleur:competitive-analysis --tiers 0,3` and lists persistence paths. `:166` is a line inside the `COMPETITIVE_ANALYSIS_ALLOWED_PATHS` const. The append-format instruction lives in the **Cascade Delegation Table** at `plugins/soleur/agents/product/competitive-intelligence.md:54` — *"Append stale pages list to knowledge-base/marketing/seo-refresh-queue.md"*. | **FR3 re-targets** to the cascade table (the sole write-format instruction). `programmatic-seo-specialist.md` carries no queue instruction — it receives its write target from that table's column at spawn time, so editing the table is sufficient **and** necessary. `cron-competitive-analysis.ts` is **not** edited. |
| **FR1** — "all six stale star-count occurrences (`:13, :25, :45, :76, :98, :136`)" | **Seven, not six.** Line **53** carries `14,600+ GitHub stars` — the comma form, which the six-line enumeration misses. | **FR1 is corrected to seven sites**, `:13, :25, :45, :53, :76, :98, :136`. |
| **AC1** — `grep -rn "14\.6k" knowledge-base/marketing/` returns zero | **Structurally cannot catch `:53`.** `14,600+` does not match `14\.6k`. A green AC1 would certify a still-stale file. **Also unachievable as scoped** — see the two rows below. | **AC1 is widened** to `14\.6k\|14,600\|14600` (the claim family, not one spelling) **and carved out** to exclude dated audit records. |
| *(deepen-plan finding)* FR1/FR2 reach every stale write-site | **FALSE — an eighth live site exists.** `knowledge-base/marketing/content-strategy.md:154` says `Paperclip (14.6k GitHub stars, MIT-licensed)`. It is a **live** doc (`review_cadence: weekly`, `owner: CMO`), not an archive — and it has **no `docs/blog` twin**, so FR2's twin-diff method **structurally cannot reach it**. | **Folded in.** `content-strategy.md` is added to Files to Edit and to Phase 1. The sweep method is corrected to **claim-family-first** (grep the *claim*), with twin-diff as the narrower second pass — exactly the learning file's prescription: *"enumerate write-sites by grepping for the claim, never by grepping for the rendered page."* |
| *(deepen-plan finding)* AC1's scope is clean | **FALSE — 4 legitimate hits under `knowledge-base/marketing/audits/`** (`2026-03-25-growth-audit.md:52,178`, `2026-03-30-growth-audit.md:77`, `2026-04-13-content-audit.md:309`). These are **dated point-in-time audit records** that correctly state the figure as of their own date. | **AC1 carves out `knowledge-base/marketing/audits/`** — the same carve-out class as `**/archive/**` and a feature's own planning artifacts. Rewriting a dated audit would falsify the record, not fix it. |
| **TR5** — `cron-growth-execution.ts:126` reads a third predicate | **Confirmed.** The prompt reads `Priority 1 ("Update immediately") stale pages`, which binds to the literal heading `## Priority 1: Stale Pages (Update Immediately)` (`seo-refresh-queue.md:21`). | **TR5 honoured** — §1's heading and §1.1–§1.7 subsection structure are **not** touched. Guarded by a new AC. |
| **TR3 / FR6** — "must not reuse the issue-gated heartbeat" | **Confirmed, and a better layer already exists.** `scripts/cron-artifact-age.sh` + `.github/workflows/scheduled-cron-artifact-age.yml` (ADR-126, #6737) is an **external** detector — GitHub-scheduled, reads default-branch git history, shares no process/host/queue with Inngest. Its deliberate design constraint is *"the reporter must not be the subject."* | **FR6 extends that layer** rather than inventing one. See §Observability for why age alone is insufficient and a delta probe is required. |
| Brainstorm OQ4 — "repo research found `founder-in-the-loop` only in polsia + paperclip" | **Falsified by direct grep.** See §Open Question (c). | Resolved; affects **NG2 scoping only**. No page is rewritten. |

---

## User-Brand Impact

- **If this lands broken, the user experiences:** the live `cron-content-generator` (Tue/Thu 10:00 UTC)
  auto-generating a **published blog article plus social distribution content** from a mis-selected
  or stale queue row — the same class of artifact as the 2026-07-20 incident, under the founder's
  byline, on `soleur.ai`.
- **If this leaks, the user's brand credibility is exposed via:** a stale, unattributed, or
  unsupportable factual claim about a **named competitor** reaching a published page or a social
  channel. `distribution-content/2026-04-15-soleur-vs-paperclip.md` carries `status: published` and
  already shipped a ~5x-wrong figure to Discord/X/Bluesky/LinkedIn.
- **Brand-survival threshold:** `single-user incident`.

**CPO sign-off required at plan time.** Carried forward from the brainstorm's own
`## User-Brand Impact` framing (identical artifact/vector/threshold), which was produced with CPO
participation in Phase 0.5 — see brainstorm `## Domain Assessments → Product`. No re-authoring.
`user-impact-reviewer` will be invoked at review time per `review/SKILL.md`'s conditional block.

---

## Open Questions — Decided

### (a) Canonical queue section — **CONFIRM the brainstorm's position: reuse §2.1 / §2.2**

Not overruled. Four reasons, in order of weight:

1. **The consumer's ordering language already names them.** STEP 1 says *"Priority 1 first, then
   Priority 2 pillar, then Priority 2 comparison"* — that is §1 / §2.2 / §2.1. Reusing them means
   FR4 edits **one sentence** and the ordering clause survives verbatim. A new section would force
   a rewrite of the ordering clause *and* re-education of a third reader (`cron-growth-execution`).
2. **The metric FR6 keys on already lives there.** `generated_date` is carried inline in the §2.1 /
   §2.2 `Status` column on 13 of 15 rows. A new section would either duplicate that field or
   orphan it.
3. **TR5 constrains the alternative.** `cron-growth-execution` binds to §1's literal heading. A new
   canonical section adjacent to §1 raises the risk of a heading edit regressing a dark-but-live
   consumer for no gain.
4. **No migration of historical blocks.** The two dated blocks stay in place as an audit trail
   (marked superseded), rather than being deleted or restructured.

**One consequence the brainstorm did not name, and it is load-bearing.** §2.1 / §2.2 `Status`
cells currently read `**PUBLISHED** (2026-03-16). …` — they contain **neither `Stale` nor
`Create`**. FR4's positive predicate therefore matches **nothing** until FR5 writes those tokens
in. **FR4 and FR5 must ship in the same commit.** FR4 alone is not "safe but inert": it silently
routes every fire to STEP 1b (`/soleur:growth plan`), which is a *different* behaviour, not a
no-op. This coupling is encoded as a phase-ordering constraint and as AC9.

### (b) Backfill scope — **2026-06-08 fully; 2026-03-12 by exception only**

Backfill the **7 undrained 2026-06-08 rows**, and from 2026-03-12 carry forward **only rows with no
2026-06-08 successor and no §2.1 row**. Reasoning from the actual file:

- The 2026-03-12 block's Polsia and Paperclip rows are already explicitly marked
  `**SUPERSEDED**` and point at the 2026-06-08 block (`:208`, `:210`). Migrating them would
  resurrect retired figures — the precise defect `review/SKILL.md:1055` (half-swept sibling) warns
  about.
- Cursor, Notion, and OpenAI Codex appear in **both** blocks; the 2026-06-08 row is strictly newer
  (Composer 2.5, the completed paywall, Codex Sites). Migrating the 03-12 variants would write
  **older** facts over newer ones.
- **Anthropic Cowork** (`:209`) has a published §2.1 row with `generated_date: 2026-05-21`,
  i.e. it was drained after the flag. No action.
- **Replit Agent** (`:213`) is the only genuinely-uncovered row: no 2026-06-08 successor and **no
  §2.1 row at all**. It is carried forward as a new §2.1 row — but marked won't-do-for-now with
  rationale, not made eligible (see the Phase 3 disposition table).

Both dated blocks are then annotated `[SUPERSEDED — migrated to §2.1/§2.2 on 2026-07-22; retained
as audit trail]` and **left in place**. Not deleted: deletion would destroy the provenance the
learning file cites, and retention costs nothing now that the consumer no longer reads below
`## Refresh Schedule`.

### (c) Tier-3 thesis page set — **RESOLVED by direct grep; the CMO's report was right**

`grep -rn "founder-in-the-loop\|founder in the loop"` over the repo (2026-07-22):

| File | Sites | Note |
|---|---|---|
| `plugins/soleur/docs/blog/2026-05-12-company-as-a-service-platform.md` | L128 (FAQ prose), **L172 (JSON-LD `FAQPage` answer)**; same thesis unhyphenated at L60–62, L86 | **The earlier repo research missed this.** It surveyed only the 8 comparison pages; this is an evergreen pillar page. |
| `plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md` | L129, **L165 (JSON-LD)** | |
| `plugins/soleur/docs/pages/ai-cto.njk` | L89, **L165 (JSON-LD)** | Unhyphenated *"founder in the loop"* — a literal-token grep for the hyphenated form misses it. |
| `knowledge-base/marketing/distribution-content/soleur-vs-polsia.md` | L85, L105 | Not Eleventy-compiled. |
| `knowledge-base/marketing/distribution-content/what-is-company-as-a-service.md` | L84 | Not Eleventy-compiled. |

**Verdict:** the superseded thesis carries on **5 files / 3 rendered surfaces**, two of which are
JSON-LD (which answer engines quote verbatim with no page context — the exact TR4 hazard). The
prior "only polsia and paperclip" finding was a false negative from a comparison-pages-only survey
plus a hyphenated-only pattern.

**This affects NG2 scoping only. No page is rewritten in this plan.** The finding is recorded
here and appended to the NG2 follow-up so the deferred rewrite starts from the true page set
rather than re-deriving a wrong one.

---

## Architecture Decision (ADR/C4)

### ADR

**Create `ADR-133` — "seo-refresh-queue: canonical section + positive selection predicate".**

Detection fires on *"a new cross-cutting invariant every consumer must honour"*. After this plan,
the queue has three declared properties that **three** readers/writers must honour
(`cron-competitive-analysis` via the cascade, `cron-content-generator`, `cron-growth-execution`):
§2.1/§2.2 are the only place actionable rows may live; selection is positive
(`Status ∈ {Stale, Create}` **and** no `generated_date`); §1's heading is load-bearing for a third
reader. Without a decision record, the next cascade change re-appends a dated block and silently
re-breaks the contract — **which is literally the failure being fixed**. `grep -rln
"seo-refresh-queue" knowledge-base/engineering/architecture/decisions/` returns **NONE**, so this
is a new decision, not an amendment.

ADR-133 cites ADR-126 (cron liveness must assert the consumed artifact) for the FR6 extension, and
supersedes nothing. **Ordinal is provisional** — highest on `main` is ADR-132; `/ship`'s
ADR-Ordinal Collision Gate re-verifies against `origin/main`. On renumber, sweep
`grep -rn 'ADR-133' knowledge-base/project/{plans,specs}/feat-6827-*/` — this plan, `tasks.md`,
and AC13 all name the ordinal.

### C4 views

**No C4 impact.** Enumerated against all three model files
(`diagrams/{model.c4,views.c4,spec.c4}`), not a keyword grep:

- **(a) External human actors** — `founder`, `emailSender`, `betaContact`, `contributor` are the
  four modelled actors (`model.c4:8,14,22,31`). This change introduces no new correspondent,
  reviewer, or recipient. Social-channel audiences are not modelled today and this change adds no
  distribution surface (`status: published` files are never re-sent).
- **(b) External systems / vendors** — the change's runtime edges are `anthropic` (spawned
  `claude`), `github` (issue + PR), and `betterstack`/`sentry` (heartbeat), all already modelled
  (`model.c4:226,230,283,290`) with existing edges. No new vendor. *Noted, deliberately not
  folded in:* the competitive-analysis cron already holds `WebSearch,WebFetch` and fetches
  competitor sites at runtime, an unmodelled edge — but that is **pre-existing**, not introduced
  here, so modelling it belongs to its own change rather than riding this diff.
- **(c) Containers / data stores** — `platform.infra.inngest` (runs both crons) and
  `platform.plugin.kb` (holds `seo-refresh-queue.md`) are both modelled. No new container, no new
  store.
- **(d) Access relationships** — none change. The queue is a repo file with no workspace-grain,
  ownership, or multi-Owner sharing semantics; nothing moves from single-owner to shared.

No `.c4` element description is falsified by this change, so no correctness edit is required
either. `views.c4` needs no new `include` line because no element is added.

### Sequencing

ADR-133 is authored in this cycle at `status: accepted` — the decision is true the moment
FR3+FR4+FR5 merge, with no soak gate on the decision itself. (The *verification* of drain behaviour
is soak-gated; see §Follow-Through Enrollment. Those are different things and must not be
conflated.)

---

## Open Code-Review Overlap

One match across 61 open `code-review` issues:

- **#3649** — *"marketing: PR-A2 #3603 content brief — schedule for PR-C merge (coordinated
  launch)"*, matched on `knowledge-base/marketing/distribution-content`.
  **Disposition: Acknowledge.** Different concern — it schedules a *new* content brief for a
  coordinated launch; it neither touches the paperclip twin nor the numeric-drift class. This plan
  does not fix it and it remains open. No re-evaluation note needed (no ordering dependency
  either way).

No open scope-out touches `cron-content-generator`, `cron-competitive-analysis`,
`seo-refresh-queue`, `cron-artifact-age`, `review/SKILL.md`, `competitive-intelligence.md`, or
`test-all.sh`.

---

## Files to Edit

| File | FR | Change |
|---|---|---|
| `knowledge-base/marketing/distribution-content/2026-04-15-soleur-vs-paperclip.md` | FR1 | 7 sites → `74,000+` soft-floor form (`:13,:25,:45,:53,:76,:98,:136`) |
| `knowledge-base/marketing/content-strategy.md` | FR1/FR2 | **(deepen-plan finding)** `:154` `14.6k GitHub stars` → `74,000+`. Live weekly-reviewed CMO doc with **no blog twin** — reachable only by the claim-family sweep |
| `knowledge-base/marketing/seo-refresh-queue.md` | FR5 | Backfill §2.1/§2.2; annotate both dated blocks superseded; refresh frontmatter dates |
| `apps/web-platform/server/inngest/functions/cron-content-generator.ts` | FR4 | STEP 1 predicate → positive; `[superseded]` note on the dead YAML-provenance comment |
| `apps/web-platform/test/server/inngest/cron-content-generator.test.ts` | TR2 | **Add** positive-predicate anchor test + §1.x-exclusion assertion |
| `plugins/soleur/agents/product/competitive-intelligence.md` | FR3 | Cascade Delegation Table write-target: append-block → in-place §2.1/§2.2 row update |
| `knowledge-base/product/competitive-intelligence.md` | FR7 | Takeaway #7 verified/unsubstantiated split + retrieval date |
| `plugins/soleur/skills/review/SKILL.md` | FR8 | New conditional-agent path-trigger block binding the existing substantiation criterion |
| `scripts/test-all.sh` | FR6 | Register the new `.test.sh` explicitly (**no glob covers `scripts/*.test.sh`** — see `:141-144`) |
| `.github/workflows/scheduled-cron-artifact-age.yml` | FR6 | Add the drain-delta detector as a second step in the existing external job |

## Files to Create

| File | FR | Purpose |
|---|---|---|
| `scripts/seo-queue-drain-delta.sh` | FR6 | Artifact-**delta** detector — `generated_date` count over default-branch history |
| `scripts/seo-queue-drain-delta.test.sh` | FR6 | Unit tests, mirroring `scripts/cron-artifact-age.test.sh` |
| `knowledge-base/engineering/architecture/decisions/ADR-133-seo-refresh-queue-canonical-section-and-positive-predicate.md` | — | Decision record |
| `scripts/followthroughs/seo-queue-drain-6827.sh` | — | Soak probe (see §Follow-Through Enrollment) |

**Not edited, deliberately:** `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts`
(carries no queue-write instruction — see Research Reconciliation),
`apps/web-platform/server/inngest/functions/cron-growth-execution.ts` (TR5: must not regress; its
predicate is unchanged and its heading is preserved), and every file under
`plugins/soleur/docs/blog/` (NG2).

---

## Implementation Phases

Phase order is load-bearing: the **contract** change (FR3) precedes its **consumers** (FR4/FR5),
and FR4+FR5 are a single atomic commit for the reason given in Open Question (a).

### Phase 0 — Preconditions (verify, do not assume)

1. `bash scripts/cron-artifact-age.sh --all; echo "rc=$?"` — capture the pre-change baseline so the
   FR6 addition is measured against a known state (per the "run the un-mutated baseline first and
   require it interpretable" discipline).
2. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-content-generator.test.ts`
   — confirm green before editing. **Runner is vitest, not `bun test`**
   (`apps/web-platform/bunfig.toml` blocks bun discovery); path must match
   `vitest.config.ts`'s `test/**/*.test.ts` include glob.
3. `grep -c 'generated_date' knowledge-base/marketing/seo-refresh-queue.md` — record the baseline
   count. This is the exact metric FR6 keys on; the number is needed to seed the detector's test
   fixtures and to make AC10 checkable.
4. Re-confirm `ls knowledge-base/engineering/architecture/decisions/ | grep -c ADR-133` returns 0.

### Phase 1 — FR1 + FR2: correction sweep (docs-only, no behavioural risk)

**Sweep method is claim-family-first.** Grep the *claim* (`14\.6k|14,600|14600`), not the rendered
page and not the twin — the twin-diff is the narrower second pass. The eighth site
(`content-strategy.md:154`) has no blog twin and is reachable **only** this way; a twin-diff-only
sweep would repeat the exact miss this cycle exists to close
(`hr-write-boundary-sentinel-sweep-all-write-sites`).

1. Replace all **seven** paperclip sites in the distribution twin with the soft-floor form. Match
   the blog twin's register: `74,000+ GitHub stars`, and preserve each sentence's surrounding
   clause — **do not** re-point a dependent clause onto a new head (the `#6538` additive class
   called out at `review/SKILL.md:1055`).
2. **(deepen-plan finding)** Correct `knowledge-base/marketing/content-strategy.md:154`
   (`Paperclip (14.6k GitHub stars, MIT-licensed)` → `74,000+`). Live doc, `review_cadence: weekly`,
   `owner: CMO`. Bump its `last_updated` / `last_reviewed`.
3. **Do NOT edit `knowledge-base/marketing/audits/`.** The four hits there
   (`2026-03-25-growth-audit.md:52,178`, `2026-03-30-growth-audit.md:77`,
   `2026-04-13-content-audit.md:309`) are dated point-in-time audit records; rewriting them would
   falsify the record rather than fix it. AC1 carves this directory out.
4. Add a correction note to the distribution twin mirroring the blog twin's `:17`
   `**Updated 2026-07-20:**` disclosure pattern, dated 2026-07-22, naming the figure and the
   verification source. This satisfies FR8's own criterion on the very diff FR8 governs.
5. **Record the completed FR2 sweep in the PR body.** The sweep was executed at plan time; the
   result table is in §FR2 Sweep Result below. `/work` re-runs the same commands and reports any
   delta — it does not re-derive the method.

### Phase 2 — FR3: producer write-target (the contract side, first)

Edit the Cascade Delegation Table row at `plugins/soleur/agents/product/competitive-intelligence.md:54`.

- **From:** `Append stale pages list to knowledge-base/marketing/seo-refresh-queue.md`
- **To:** an instruction to update the matching **§2.1 / §2.2 row in place** — set `Status` to
  `Stale — Update` or `Create`, clear any `generated_date`, and fold the reason into the row's
  `Status` cell; **add a new §2.1 row** when no row matches; and **never** append a new
  `## Stale Comparison Pages Flagged for Regeneration (…)` block below `## Refresh Schedule`.
- Add a one-line pointer to ADR-133 so the next editor sees the rationale, not just the rule.

No test guards this table today (`grep -rln "Cascade Delegation\|programmatic-seo-specialist"
plugins/soleur/test/ apps/web-platform/test/` → none), so Phase 5 adds one.

### Phase 3 — FR4 + FR5: consumer predicate + backfill (**one atomic commit**)

**FR4** — replace the STEP 1 selection sentence in `CONTENT_GENERATOR_PROMPT`:

- **From:** `identify the highest-priority item without a "generated_date" annotation`
- **To:** a positive predicate — select the highest-priority row **whose `Status` contains `Stale`
  or `Create` AND which has no `generated_date`**, drawn from §2.1 / §2.2 only, with an explicit
  instruction that §1.1–§1.7 are prose subsections and are **never** selectable.

Keep the `Priority 1 first, then Priority 2 pillar, then Priority 2 comparison` ordering clause
verbatim (it is not an asserted anchor, but it is correct and its churn buys nothing). Do not
touch any of the ten asserted anchors listed in the Research Reconciliation row for TR2.

Also update the stale `// Verbatim prompt extracted from .github/workflows/…` comment to note the
workflow was removed in #4483 and the TS file is now the sole source.

**FR5** — backfill per the disposition table. **NG3 boundary:** this writes *row metadata* only.
It does not write article content — that is exactly what the repaired pipeline is meant to do.

| 2026-06-08 row | §2.1 row exists? | Disposition | Rationale |
|---|---|---|---|
| Soleur vs. Polsia | yes (`gd: 2026-03-26`) | **Update `generated_date` → 2026-07-20** | Drained; page corrected 2026-07-20. Not eligible. |
| Soleur vs. Paperclip | yes (`gd: 2026-03-31`) | **Update `generated_date` → 2026-07-20** | Drained; page corrected 2026-07-20. Not eligible. |
| Soleur vs. Notion Custom Agents | yes (`gd: 2026-06-05`) | **Migrate → eligible** (`Stale — Update`, clear `gd`) | CMO ranked worth doing — paywall/ICP-eviction window. |
| Soleur vs. Cursor | yes (**no `gd`** already) | **Migrate → eligible** (`Stale — Update`) | CMO ranked worth doing — Composer 2.5, dead pricing table. |
| Best Claude Code Plugins 2026 | yes (`gd: 2026-04-30`) | **Migrate → eligible** (`Stale — Update`, clear `gd`) | Pillar row, materially stale (marketplace 100+ → 186). |
| Soleur vs. NanoCorp | **no** | **Won't-do**, row added to §2.1 with `Status: Won't do (2026-07-22)` + rationale | CMO: close won't-do. All NanoCorp metrics contradictory/unverified. |
| Soleur vs. OpenAI Codex | **no** | **Won't-do**, row added with rationale | CMO: close won't-do. |
| Soleur vs. Tanka | yes (`gd: 2026-05-05`) | **Won't-do**, rationale in `Status`; `gd` retained | CMO: close won't-do. |
| Soleur vs. CrewAI | yes (`gd: 2026-05-07`) | **Won't-do**, rationale in `Status`; `gd` retained | CMO: close won't-do. |
| *(2026-03-12 only)* Soleur vs. Replit Agent | **no** | **Won't-do**, row added with rationale | Only uncovered 03-12 row; not CMO-ranked. Recorded so it stops being invisible. |

Net: **3 rows become eligible** (Notion, Cursor, Best-Plugins). Won't-do rows carry an explicit
`Won't do (2026-07-22) — <reason>` string that the positive predicate does **not** match, so
they are recorded without being selectable.

Then annotate both dated blocks `[SUPERSEDED — migrated to §2.1/§2.2 on 2026-07-22; retained as
audit trail]` and bump `last_updated` / `last_reviewed` to `2026-07-22`.

**TR5 guard:** do not touch `## Priority 1: Stale Pages (Update Immediately)` (`:21`) or the
§1.1–§1.7 headings.

### Phase 4 — FR6: artifact-delta observability

**Why age is not enough (the TR3 gap, one layer up).** `cron-artifact-age.sh` asks *"did the cron's
own commit land?"* After Phase 3, `cron-content-generator` can commit
`feat(content): auto-generate article` — turning artifact-age **GREEN** — while annotating a §1.x
prose subsection and draining **zero** §2.1/§2.2 rows. Age is necessary and insufficient; the
delta is the invariant.

**Layer citation (`hr-observability-layer-citation`).** The signal surfaces in
**GitHub Actions — `.github/workflows/scheduled-cron-artifact-age.yml`**, daily `0 6 * * *`,
reporting via that workflow's existing issue-creation step. Chosen because ADR-126's constraint —
*the reporter must not be the subject* — is satisfied only outside Inngest: it runs on GitHub's
scheduler, reads GitHub's git history, and shares no process, host, queue, or dependency with the
cron under observation. **Not** Sentry Crons (that is the issue-gated heartbeat TR3 forbids) and
**not** a handler-local flag (authored by the suspect).

**Design.** New `scripts/seo-queue-drain-delta.sh`:

- Walk default-branch commits authored by `cron-content-generator` (anchor regex
  `^feat\(content\): auto-generate article`, the same content-anchor the age detector uses).
- For each, compute `git show <sha>:knowledge-base/marketing/seo-refresh-queue.md | grep -c generated_date`.
- **STALE** when the last *N* such commits show no increase in the count, or when no such commit
  exists inside the cadence window. Threshold derived from the cron's **own** schedule
  (`0 10 * * 2,4` → 2 fires/week), never a flat constant — the cadence-blindness error ADR-126
  records.
- Exit 0 = PASS, 1 = STALE. No SSH, no credentials, no dashboard (`hr-no-ssh-fallback-in-runbooks`,
  `hr-no-dashboard-eyeball-pull-data-yourself`).

**Wiring.** Add as a second step in the *existing* job — no new workflow, no new cron surface, and
it inherits the ADR-126 external-reporter guarantee. Register in `scripts/test-all.sh` **by name**:
`scripts/*.test.sh` is explicitly **not** covered by any glob (`test-all.sh:141-144` says so
outright), so an unregistered test is a silent no-op.

### Phase 5 — FR8: bind the substantiation rule + guard the contract

**FR8 — bind, do not reinvent.** The criterion already exists verbatim at
`plugins/soleur/skills/review/SKILL.md:1055`: *"every third-party claim the diff ADDS traces to a
named line in the cited source of truth"*, and the brand-guide Never-do at
`knowledge-base/marketing/brand-guide.md:97` (added 2026-07-20 per #6768). Neither is mechanically
triggered.

Add a conditional-agent path-trigger block to `review/SKILL.md`, mirroring the existing
`#5871` / anti-slop block form (`:274`, `:284`), keyed on:

```
(^|/)plugins/soleur/docs/blog/.*vs-.*\.md$
(^|/)knowledge-base/marketing/distribution-content/.*vs-.*\.md$
```

The block cites `:1055` and `brand-guide.md:97` as the criterion source — it does not restate them
(restating creates the replicated-literal drift class `review/SKILL.md:965` warns about) — and
requires a retrieval date on every added third-party claim.

**Glob verification (`hr-when-a-plan-specifies-relative-paths-e-g`).** Both globs verified to match
≥1 real file: `docs/blog/*vs-*` → 8 files; `distribution-content/*vs-*` → 9 files.

**Contract guard.** Add to `cron-content-generator.test.ts`: (i) the STEP 1 block contains the
positive tokens (`Stale`, `Create`) and a §1.x exclusion; (ii) the STEP 1 block no longer contains
the negative-predicate phrasing. Scope both to the STEP 1 block via a bounded
`SUT_SOURCE.match(/STEP 1 —[\s\S]*?\nSTEP 2 —/)` capture — the same block-scoping discipline the
existing STEP 4 tests use (`:171`), so the assertion binds to the region the AC names rather than
to the whole file.

### Phase 6 — FR7: substantiate takeaway #7

Rewrite `knowledge-base/product/competitive-intelligence.md` Tier-3 takeaway #7 (`:120`) to mark
each Cofounder convergence claim, with `Retrieved 2026-07-22 from cofounder.co`:

- **Verified on the vendor site:** human-in-the-loop approval gates (*"nothing ships without your
  approval"*); multi-department breadth (11 domains listed).
- **Not stated anywhere on the vendor site — treat as unsubstantiated:** pricing, revenue-share
  terms, memory/knowledge-base architecture, data ownership / "graduation".

**TR4 applies even here.** The takeaway currently asserts `$8.7M seed led by Union Square Ventures`
and `Pro $20/mo`. The funding round is a verifiable third-party signal (keep, with its citation);
the pricing is now flagged unsubstantiated. Because the same claims appear in
`knowledge-base/product/business-validation.md:83` and the Tier-3 table row at `:100`, add a
one-line pointer from those rows to takeaway #7 rather than duplicating the annotation — a
**half-swept sibling** here would reproduce the exact defect this cycle exists to close.

### Phase 7 — Verification

Run the full gate: the vitest suite for both cron tests, `bash scripts/seo-queue-drain-delta.test.sh`,
`bash scripts/cron-artifact-age.test.sh` (regression — the workflow it shares is edited), and
`bash scripts/test-all.sh` for the exit gate. Then walk every AC.

---

## FR2 Sweep Result (executed at plan time — TR6 gate)

Method: extract numeric competitor claims (`stars`, `$X`, `N plugins/skills/downloads/customers`,
`N% revenue`) from every file in `knowledge-base/marketing/distribution-content/`, then diff
against the `plugins/soleur/docs/blog/` twin resolved by slug. **17 of 46 files have a blog twin
and carry a numeric competitor claim; the remainder are launch/feature posts with no competitor
figure and no twin.**

| Twin pair | Verdict |
|---|---|
| `2026-04-15-soleur-vs-paperclip` ↔ `2026-03-31-soleur-vs-paperclip` | **DIVERGENT** — `14.6k` / `14,600+` (×7) vs `74,000+`. **The only true divergence.** Fixed by FR1. |
| `2026-03-19-soleur-vs-cursor` ↔ same | AGREE — both `Pro $20/month`. Dist omits Pro+/Ultra/Teams tiers; omission ≠ contradiction. |
| `soleur-vs-crewai` ↔ `2026-05-07-soleur-vs-crewai` | AGREE — `45,000+` vs `45,000` GitHub stars (soft-floor form). |
| `soleur-vs-polsia` ↔ `2026-03-26-soleur-vs-polsia` | AGREE — both funding-first (`$30M` / `$250M valuation`, `$49` + `20% revenue`). Dist carries **no** unattributed ARR figure. |
| `soleur-vs-devin` ↔ `2026-04-21-soleur-vs-devin` | AGREE — `$20`. |
| `2026-05-05-soleur-vs-tanka` ↔ same | AGREE — `free <50 users, $29–199/mo`. Dist omits the `$299` team tier; omission only. |
| `2026-03-17` + `2026-06-05-soleur-vs-notion-custom-agents` ↔ `2026-03-17-…` | AGREE — `$10/1,000 credits`, `$20`. |
| `2026-03-16-soleur-vs-anthropic-cowork` ↔ same | AGREE — `$99`. |
| `best-claude-code-plugins-2026` ↔ `2026-04-30-…` | AGREE — both `100+ plugins`, `4,200+ skills`. |
| `what-is-company-as-a-service` ↔ `2026-05-12-company-as-a-service-platform` | AGREE — no competitor numerics. |
| `06-why-most-agentic-tools-plateau`, `ai-agents-for-solo-founders`, `knowledge-compounding-…`, `loop-engineering-…`, `how-to-run-every-department-…`, `2026-04-21-one-person-billion-dollar-company`, `2026-04-07-vibe-coding-…` | AGREE — no competitor numerics (self-claims only). |

**Two explicit scope-outs, recorded rather than silently dropped:**

1. **Twin-agreeing but upstream-stale figures.** `45,000+` CrewAI stars (queue says **47.8k**) and
   `100+` marketplace plugins (queue says **186**). Both twins agree, so FR2 (scoped to *twin
   divergence*) does not reach them, and gate #6838 would not either. They are **content-drain
   work (NG3)** — the rows are among those Phase 3 marks eligible/won't-do, so the repaired
   pipeline is the correct remedy. Flagged in the PR body so the next reader does not mistake
   "swept" for "current".
2. **Soleur self-claim drift.** `8 departments` vs `9 departments` vs `8 domains` vs `10 domains`,
   and `62`/`67`/`70 skills`, `63`/`66 agents` across distribution files. These are **first-party**
   claims, outside FR2's "competitor claims" scope and outside FR8's "third-party claim" trigger.
   Genuinely inconsistent and worth its own cycle; **not** folded in — it would double this diff
   with a distinct concern and no brand-survival coupling. Noted in the PR body.

---

## Observability

```yaml
liveness_signal:
  what: "seo-refresh-queue generated_date count increases across cron-content-generator's own default-branch commits"
  cadence: "daily 0 6 * * * (sampling rate); threshold derived from the cron's own 0 10 * * 2,4 schedule"
  alert_target: "GitHub issue opened by scheduled-cron-artifact-age.yml's existing report step"
  configured_in: ".github/workflows/scheduled-cron-artifact-age.yml + scripts/seo-queue-drain-delta.sh"

error_reporting:
  destination: "GitHub Actions job annotation + the workflow's issue-creation step"
  fail_loud: true   # detector exits 1 on STALE; the report step is gated on rc != 0

failure_modes:
  - mode: "Consumer fires but drains zero rows (selects a §1.x prose subsection, or the predicate matches nothing)"
    detection: "generated_date count unchanged across the last N cron-authored commits"
    alert_route: "scheduled-cron-artifact-age issue"
  - mode: "Consumer stops firing entirely"
    detection: "no commit matching ^feat\\(content\\): auto-generate article inside the cadence window"
    alert_route: "existing cron-artifact-age.sh row (unchanged) + Sentry Crons monitor"
  - mode: "Producer re-appends a dated block below ## Refresh Schedule (FR3 regression)"
    detection: "cascade-table anchor test in the plugins test suite"
    alert_route: "CI required check on the PR"
  - mode: "Consumer prompt silently paraphrased back to the negative predicate"
    detection: "STEP 1 block-scoped anchor test in cron-content-generator.test.ts"
    alert_route: "CI required check on the PR"

logs:
  where: "GitHub Actions run logs for scheduled-cron-artifact-age (public repo, 90-day retention)"
  retention: "90 days (GitHub Actions default)"

discoverability_test:
  command: "bash scripts/seo-queue-drain-delta.sh --report"
  expected_output: "one line per sampled cron commit — <sha> <date> generated_date=<n> — then PASS or STALE, exit 0/1"
```

No remote-shell step appears anywhere in the discoverability path.

### Follow-Through Enrollment

AC16 (*"the next consumer fire increases the `generated_date` count"*) is **soak-gated** — it
cannot be verified at merge time, because the consumer next fires on the following Tue/Thu 10:00
UTC. Per §2.9.1 this must be enrolled, not left to memory:

- **Script:** `scripts/followthroughs/seo-queue-drain-6827.sh` — exit 0 once a post-merge
  `cron-content-generator` commit shows a `generated_date` count strictly greater than the Phase 0
  baseline. Mirrors `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh`, with the sample
  window pinned strictly **after** the merge commit.
- **Directive** on the tracker (#6827) plus the `follow-through` label:
  `<!-- soleur:followthrough script=scripts/followthroughs/seo-queue-drain-6827.sh earliest=<merge+8d> -->`
  — 8 days spans **two** fires, so a single skipped fire does not produce a false STALE.
- **Secrets:** none (git history only) — no `secrets=` addition to
  `.github/workflows/scheduled-followthrough-sweeper.yml`.

**Exit-code semantics, stated because the sweeper acts on them:** this probe returns `1` for
*"still soaking"*, which is **not** *"the work was done prematurely"*. It must not be wired to any
issue-closing path that treats exit 1 as a failure verdict.

---

## Infrastructure (IaC)

**Skipped — this plan introduces no infrastructure.** Phase 2.8's routing gate was reviewed and
does not apply: there is no new server, systemd unit, vendor account, DNS record, TLS cert,
secret, firewall rule, or monitoring webhook. FR6 adds a **step to an already-existing GitHub
Actions workflow** plus a repo-local bash script — no new scheduled surface, no new persistent
runtime process, no credential of any kind. The detection scan over this plan draft finds no
remote-shell invocation, no secret-write command, no `systemctl`, no `terraform import`, and no
vendor-console instruction. Every change is a file in this repository, applied by merge.

## GDPR / Compliance Gate

**Trigger (b) fired** (`brand_survival_threshold: single-user incident`); the canonical
regulated-data regex did **not** match (no schema, migration, auth flow, API route, or `.sql`).

**Assessment: no finding.** The diff processes no personal data. Its subjects are corporate facts
about competitor *companies* (star counts, pricing, funding), which are not personal data. Named
individuals appearing in adjacent already-published CI rows (e.g. a competitor CEO) are
public-figure business-role facts already recorded and unchanged by this diff. No new processing
activity, no new data flow, no Art. 30 RoPA entry, no lawful-basis change. Triggers (a), (c), (d)
do not fire: the crons already hold `WebSearch`/`WebFetch` (no new LLM/external-API processing is
introduced), nothing new reads `learnings/` or `specs/`, and no new distribution surface is added
(`status: published` files are never re-sent).

**Advisory only — this is not legal advice.**

---

## Domain Review

**Domains relevant:** Marketing, Engineering, Product, Legal — carried forward from the brainstorm's
`## Domain Assessments` section (Phase 0.5 leader spawns). No fresh assessment; no leader
recommended a named specialist for invocation.

### Marketing
**Status:** reviewed (carry-forward)
**Assessment:** Ranked the 7 undrained rows — Notion (paywall/ICP-eviction) and Cursor (Composer 2.5,
dead pricing table) worth doing; NanoCorp, Codex, Tanka, CrewAI close won't-do. **Directly consumed
by this plan** as the FR5 disposition table in Phase 3. Recommended against publishing
`soleur-vs-cofounder` (NG1, honoured).

### Engineering
**Status:** reviewed (carry-forward)
**Assessment:** Confirmed Bug A/Bug C by file read; corrected Bug B from "nothing eligible" to "the
wrong things are permanently eligible". Minimal correct fix = reconcile the producer write target
with a positive consumer predicate; issue-fanout and the `product-roadmap` bolt-on both rejected
(NG6/NG7, honoured). Flagged that no observability signal fires today — the heartbeat is
issue-gated. **Plan-time research extended this:** the producer instruction is not where the spec
said it was, and the YAML mirrors TR1 assumes no longer exist.

### Product
**Status:** reviewed (carry-forward)
**Assessment:** Originally recommended cutting the pipeline work on the premise that all three
layers were stale; that premise was corrected in-session (the consumer is live). The
operator-selected scope stands. **`requires_cpo_signoff: true`** is set per §2.6.

### Legal
**Status:** reviewed (carry-forward)
**Assessment:** Binding standard is EU 2006/114/EC Art. 4 — objective, verifiable, material,
non-denigrating, substantiation held **before** publishing. Attribution defeats a falsity claim but
not the Art. 4(c) verifiability bar for an unaudited self-report. **Directly consumed** as TR4 and
as FR7's verified/unsubstantiated split. No outside-counsel threshold met. NG5 (non-affiliation
disclaimer) remains #6837 and is **not** re-filed.

### Product/UX Gate
**Not applicable — Product tier NONE.** The mechanical UI-surface override was evaluated against
both `## Files to Edit` and `## Files to Create`: **zero** paths match `components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`, or any UI-surface glob. The diff is markdown, a TS prompt
string constant, bash, and YAML. No wireframe is required (`wg-ui-feature-requires-pen-wireframe`
does not fire).

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `grep -rniE '14\.6k|14,600|14600' knowledge-base/marketing/ --exclude-dir=audits`
  returns **zero**. *(Widened from the spec's `14\.6k`-only form, which cannot see `:53`; carved
  out for `audits/`, whose four hits are dated point-in-time records that must NOT be rewritten.)*
- **AC1b** — `grep -rniE '14\.6k|14,600|14600' knowledge-base/marketing/audits/ | wc -l` returns
  **4** — i.e. the historical audit records were left intact, not silently swept.
  *(A carve-out that is never asserted is indistinguishable from an oversight.)*
- **AC2** — Every `distribution-content/` file agrees with its `docs/blog/` twin on numeric
  competitor claims; the full sweep table (including no-divergence files and the two explicit
  scope-outs) appears in the PR body. **The sweep is claim-family-first**: the PR body states that
  `content-strategy.md:154` was found by the claim grep and is invisible to twin-diff.
- **AC3** — `cron-content-generator.test.ts` asserts the **STEP 1 block** (bounded
  `/STEP 1 —[\s\S]*?\nSTEP 2 —/`) contains `Stale`, `Create`, and a §1.x exclusion, and does **not**
  contain the phrase `without a "generated_date" annotation`.
- **AC4** — A test asserts the Cascade Delegation Table row at
  `plugins/soleur/agents/product/competitive-intelligence.md` names an in-place §2.1/§2.2 update and
  does **not** contain `Append stale pages list`.
- **AC5** — All ten pre-existing anchor assertions in `cron-content-generator.test.ts` still pass
  unmodified; `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` is green.
- **AC6** — `bash scripts/seo-queue-drain-delta.sh --report` runs with no remote-shell step and
  prints a per-commit `generated_date` count plus a PASS/STALE verdict; the marker surfaces in
  `.github/workflows/scheduled-cron-artifact-age.yml` (named in the PR body with its layer).
- **AC7** — `knowledge-base/product/competitive-intelligence.md` takeaway #7 contains
  `Retrieved 2026-07-22` and separates verified (HITL gates, 11-domain breadth) from unsubstantiated
  (pricing, revenue-share, memory architecture, data ownership).
- **AC8** — `grep -c 'seo-queue-drain-delta.test.sh' scripts/test-all.sh` returns **≥1**
  *(the glob does not cover `scripts/*.test.sh` — an unregistered test is a silent no-op)*.
- **AC9** — **Coupling gate.** The commit that edits the STEP 1 predicate also edits
  `seo-refresh-queue.md`. Verified per-commit, not by union:
  for each `sha` in `git rev-list origin/main..HEAD -- <both paths>`, `git show $sha --name-only`
  contains **both** `cron-content-generator.ts` and `seo-refresh-queue.md`, or **neither**.
  *(`git log -- A B` is a UNION filter and would pass on an asymmetric commit.)*
- **AC10** — `grep -c 'generated_date' knowledge-base/marketing/seo-refresh-queue.md` is **≥** the
  Phase 0 baseline, and exactly **3** rows in §2.1/§2.2 match the positive predicate
  (`Status` contains `Stale`/`Create` **and** no `generated_date`): Notion, Cursor, Best-Plugins.
- **AC11** — **TR5 non-regression.** `grep -c '^## Priority 1: Stale Pages (Update Immediately)$'
  knowledge-base/marketing/seo-refresh-queue.md` returns **1**, and all seven `### 1.x` headings are
  byte-identical to `origin/main`.
- **AC12** — `review/SKILL.md` contains a conditional block whose trigger regex matches both
  `plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md` and
  `knowledge-base/marketing/distribution-content/2026-04-15-soleur-vs-paperclip.md`, and which
  **cites** `:1055` / `brand-guide.md:97` rather than restating the criterion.
- **AC13** — `ADR-133-seo-refresh-queue-canonical-section-and-positive-predicate.md` exists with
  `## Decision` and `## Alternatives Considered` (recording the rejected "new machine-readable
  section" option from Open Question (a)).
- **AC14** — `bash scripts/test-all.sh` is green (exit gate), including
  `scripts/cron-artifact-age.test.sh` (regression on the shared workflow).
- **AC15** — Issue #6827's checklist reflects shipped vs. deferred, linking #6837 / #6838 / #6840 /
  #4375. PR body says **`Ref #6827`**, **not** `Closes` — the issue stays open for the two deferred
  checklist items.

### Post-merge (soak — enrolled, not operator-driven)

- **AC16** — After the first post-merge Tue/Thu fire, `generated_date` count is strictly greater
  than the Phase 0 baseline. **Automated** via `scripts/followthroughs/seo-queue-drain-6827.sh`
  with `earliest=<merge+8d>`; swept by `scheduled-followthrough-sweeper.yml`. No human step.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **FR4 without FR5 routes every fire to STEP 1b.** The predicate would match nothing, silently changing behaviour rather than no-op'ing. | Atomic commit enforced by **AC9** (per-commit intersection, not `git log` union). |
| **The live consumer drains a row on the next fire and publishes an article.** This is the designed outcome but it is a real write to a public surface. | Bounded by construction: the prompt selects **one** row per fire; the platform opens a **PR** (`PERSISTENCE: Do NOT run git add…`), and auto-merge is gated on the Eleventy build + `validate-blog-links.sh` required checks. FR8's new review trigger fires on exactly these paths. Only 3 rows are made eligible, all CMO-ranked. |
| **FR3's cascade-table edit is unguarded today** — no test reads that table. | AC4 adds one. |
| **Editing `scheduled-cron-artifact-age.yml` could regress the ADR-126 detector** it shares a job with. | AC14 runs `scripts/cron-artifact-age.test.sh`; the new step is additive and the existing step's `rc` capture is untouched. |
| **The `[superseded]` YAML-provenance comments could be read as license to delete the anchor tests.** | ADR-133 states the tests are now the sole regression guard; TR2 is preserved, not retired. |
| **FR7's annotation could half-sweep** — takeaway #7 corrected while `business-validation.md:83` and the Tier-3 table row `:100` keep the unqualified claims. | Phase 6 adds pointers from both siblings; this is the exact `review/SKILL.md:1055` half-swept-sibling class. |
| **ADR-133 ordinal collision** with a sibling PR merging first. | `/ship`'s collision gate re-verifies; renumber sweep command given in §Architecture Decision. |

---

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| New machine-readable canonical section both crons name | **Rejected** — Open Question (a). Larger diff, forces historical-block migration, risks TR5 regression, and re-educates three readers for no gain. Recorded in ADR-133's `## Alternatives Considered`. |
| Reuse the existing Sentry Crons heartbeat for FR6 | **Rejected** — TR3. It is issue-gated and returns GREEN at zero rows drained; it is also authored by the subject. |
| A new dedicated workflow for the drain-delta detector | **Rejected** — a second scheduled surface with the same guarantee the existing ADR-126 job already provides. Added as a step instead. |
| Delete the two historical flagged blocks after backfill | **Rejected** — destroys the provenance the learning file cites; retention is free now that nothing reads below `## Refresh Schedule`. |
| Fold in the Soleur self-claim drift (8 vs 9 departments) | **Rejected** — distinct concern, no brand-survival coupling, would roughly double the diff. Recorded as a scope-out in the PR body. |
| Fold in the twin-agreeing-but-upstream-stale figures (CrewAI 47.8k, 186 plugins) | **Rejected** — that is content-drain work (NG3); the repaired pipeline is the correct remedy. Recorded in the PR body. |
| Edit `cron-competitive-analysis.ts` per FR3 as written | **Rejected** — it contains no queue-write instruction. Editing it would be a no-op that *looks* like the fix. |

**Deferral tracking:** every deferred item already has an OPEN issue — #6837 (NG5 disclaimer),
#6838 (NG2/twin-drift gate), #6840 (workflow-gate conflict), #4375 (NG4 dark producer), and #6827
itself (NG1 cofounder page, NG2 positioning rewrite). **Nothing new is filed.** The Open Question (c)
page-set finding is appended to the existing NG2 follow-up rather than becoming its own issue.

---

## Research Insights (deepen-plan, 2026-07-22)

Deepen ran without the Task tool available in this agent context, so the fan-out research agents
and the `plan-review` panel could not be spawned. The pass was executed instead as the **full
verification checklist**, run directly. That checklist is the part that catches the defects this
repo's learnings actually record, and it produced two material corrections.

### Gate results

| Gate | Result |
|---|---|
| 4.5 Network-outage deep-dive | **Skip** — the two keyword hits are *negative assertions* ("No SSH…", "no firewall rule"), not a connectivity diagnosis. |
| 4.55 Downtime & cutover | **Skip** — no reboot/replace, no lock-taking DDL, no deploy-router restructure. |
| 4.6 User-Brand Impact halt | **PASS** — section present, 14 non-blank lines, threshold `single-user incident`. |
| 4.7 Observability halt | **PASS** — all 5 fields present with children, no placeholder values, `discoverability_test.command` contains no remote-shell verb. |
| 4.8 PAT-shaped variable halt | **PASS** — zero matches. |
| 4.9 UI-wireframe halt | **Skip** — 0 UI-surface paths in Files to Edit/Create. |

### Verification checklist — findings

1. **Eighth live write-site found (material).** `knowledge-base/marketing/content-strategy.md:154`
   carries `14.6k GitHub stars`. It has **no `docs/blog` twin**, so FR2's twin-diff method could
   never reach it. Folded into Files to Edit + Phase 1; the sweep method is corrected to
   claim-family-first. This is the same defect class as the original incident.
2. **AC1 was unachievable (material).** Four legitimate hits live under
   `knowledge-base/marketing/audits/` in dated audit records. AC1 now carves that directory out,
   and **AC1b asserts the carve-out held** — an unasserted carve-out reads identically to an
   oversight.
3. **FR4 has zero test blast radius.** `grep -rn 'highest-priority item\|generated_date" annotation'`
   over `apps/web-platform/test/`, `.github/`, and `plugins/` returns **nothing**. No existing test
   pins the negative predicate, confirming the TR2 analysis: the STEP 1 edit breaks no assertion.
4. **Citations resolved live.** #4483 / #4443 MERGED — `git log --diff-filter=D` confirms they are
   the commits that deleted the two workflow mirrors, so the TR1 falsification rests on attribution,
   not inference. #6737, #6768, #5871, #6538 all resolve as CLOSED issues. #6827, #6818, #4375,
   #6837, #6838, #6840 all OPEN. #3649 OPEN (the one review overlap).
5. **All 5 AGENTS.md rule IDs cited in the plan are ACTIVE** — verified against `[id: …]` in
   `AGENTS.md`. No retired or fabricated IDs.
6. **ADR-133 re-derived from freshly-fetched `origin/main`** (`git fetch origin main` first, then
   `git ls-tree origin/main`): highest is **ADR-132**, so 133 is free. Still provisional.
7. **`follow-through` label exists** (`External dependency awaiting verification`) — the
   enrollment directive will not fail on a missing label.
8. **Precedent-diff (Phase 4.4).** The new bash detector has a direct sibling precedent —
   `scripts/cron-artifact-age.sh` (197 lines) + `scripts/cron-artifact-age.test.sh` (211 lines).
   Adopt its shape verbatim: `set -euo pipefail`, a pipe-delimited producer table, thresholds
   derived per-cron from the cron's own schedule, `--all`/`--help` flags, exit 0/1 as a verdict.
   **No new scheduled job is introduced**, so the ADR-033 Inngest-vs-GH-Actions check does not
   fire; the existing workflow's `gate-override: new-scheduled-cron-prefer-inngest` header already
   justifies why this detector class lives on GitHub Actions.

### Bash strict-mode note for the detector

`scripts/seo-queue-drain-delta.sh` compares `generated_date` counts numerically. Under
`set -euo pipefail`, `[[ $a -gt $b ]]` **crashes** rather than returning false when either side is
non-numeric — and `grep -c` on a path missing from an old commit yields empty, not `0`. Guard both:
default the count (`n=${n:-0}`) and regex-check (`[[ "$n" =~ ^[0-9]+$ ]]`) before any comparison.

---

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled and
  carried forward from the brainstorm.
- **`scripts/*.test.sh` is not glob-covered** by `scripts/test-all.sh` (`:141-144` says so in
  prose). A new detector test that is not named explicitly runs **never** and reads as green.
- **The runner is vitest, not bun.** `apps/web-platform/bunfig.toml` sets
  `[test] pathIgnorePatterns = ["**"]`; `bun test <file>` reports "filter did not match" even when
  the file exists. Use `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`.
  Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — **not**
  `npm run -w apps/web-platform typecheck` (the repo root declares no `workspaces` field).
- **`git log -- A B` is a UNION filter.** It cannot detect the asymmetric-commit failure AC9 exists
  to catch. Use `git rev-list` + per-`sha` `git show --name-only`.
- **An absence-grep must cover the claim family, not one spelling.** `grep "14\.6k"` returns clean
  on a file that still says `14,600+`. This is how FR1 lost a site, and it is the same class as
  the write-site sweep the learning file records.
- **A write-site sweep keyed on the TWIN cannot find a site that has no twin.** `content-strategy.md`
  carried the stale figure and has no `docs/blog/` counterpart, so the twin-diff FR2 prescribes is
  structurally blind to it. Grep the **claim**; use twin-diff only as the narrower second pass.
- **A carve-out that is never asserted is indistinguishable from an oversight.** AC1 excludes
  `knowledge-base/marketing/audits/`; AC1b asserts the 4 hits are still there. Without AC1b, a
  reviewer cannot tell "deliberately preserved historical record" from "missed four sites".
- **Bash numeric comparison crashes under `set -euo pipefail` on non-numeric input.** The detector
  reads `grep -c` output from historical commits where the queue file may not exist — that yields
  empty, not `0`, and `[[ $n -gt $m ]]` then aborts the whole script. Default (`${n:-0}`) and
  regex-guard (`[[ "$n" =~ ^[0-9]+$ ]]`) before comparing.
