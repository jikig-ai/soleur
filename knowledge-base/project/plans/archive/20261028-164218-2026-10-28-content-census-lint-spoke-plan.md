---
title: "content(blog): spoke — 'A Lint That Enumerates Every Place an Error Can Be Swallowed' (#8764 retro-brief)"
date: 2026-10-28
slug: content-census-lint-spoke
branch: feat-one-shot-11364-census-lint-spoke
issue: 11364
closes: 11364
type: content
lane: cross-domain
---

# Content: spoke — the step-boundary error census (#11364)

## Overview

Write and ship a non-technical-founder blog spoke about the step-boundary error census
(`scripts/lint-inngest-step-boundary.py`, merged in #11278 as child 11 of epic #10971; deferred
from #8764, born of the #8717/#8726 defect). It is the zoomed-in companion to one paragraph of the
arc hub (`plugins/soleur/docs/blog/2026-11-19-first-we-made-green-mean-something.md`, PR #11378):
the hub says "an error handler could pass every rehearsal and never fire in production"; the spoke
shows what that cost, how it hid, and how counting every place an error can be swallowed makes the
lie impossible to reintroduce silently.

One PR contains: the post, a deterministic-PIL OG card, a dated→canonical redirect pair, a
facts-only retro-link sentence in the hub, a distribution file (`status: scheduled`), a
content-strategy row, and a regenerated campaign calendar. No follow-through probe (see Cut List).

> Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed); no `spec.md` exists for
> this branch at plan time.

## Research Reconciliation — Brief vs. Codebase

| Brief / spec claim | Reality (verified 2026-10-28) | Plan response |
|---|---|---|
| "the lint is Inngest-specific in implementation; the technique generalizes" | True and narrower than it sounds: the script scans only `apps/web-platform/server/inngest/functions/*.ts` (82 files, 72 contain `step.run(`), matches `step.run(` literally, uses comment-stripping + brace/paren matching (a source scan, not an AST), flags three identity reads on a catch (`instanceof <Class>` except bare `Error`, `<p>.name ===`, `<p>.status`), keeps a 5-file `STEP_INTERNAL_ALLOWLIST`, exits clean today, and has a 9-arm self-test (`scripts/lint-inngest-step-boundary.test.sh`) | Honest-limits section states: one tool's hand-off, pattern-matching not full understanding, three kinds of label reads, proves one lie cannot recur silently — not that handlers are correct |
| "census every catch, classify by whether the error crossed the boundary" | Matches the script: shape A (own `try` contains `step.run(` → error crossed → never exempt) vs shape B (catch nested inside a `step.run` callback → error is live → legal only for allowlisted files; adding to the allowlist is the "conscious registration point") | Post explains the two piles in plain words (crossed / still live) and the visible-registration step; no file names |
| "#8764/#11278 record" | #8764 (CLOSED) was filed as a deferral from #8726's plan review; #11278 (MERGED 2026-10-27) delivered both parts (38 suites onto the shared step harness + the census). The original defect: #8717 review found 18 `instanceof DeployInProgressError` sites in 9 cron files + `instanceof LeakDetectedError` in the drift guard (#8726); fix #8758 returned tagged results | Fact pins below; counts of suites/PRs/issues never appear in the body (Blog note) |
| "link to the hub; the spoke retro-links" | Hub is merged, dated 2026-11-19, mentions the census in one paragraph and links nothing to it; Eleventy has no future-date filter (hub and spoke both go live at merge) | Spoke links hub once; hub gains one facts-only sentence linking the spoke (CTO R3) |
| Title 'A Lint That Enumerates Every Place…' | Names the mechanism; brand-guide `### Blog` requires the title/SEO title/meta to name the founder's problem | Founder-problem headline (CTO R5, taste) |
| "followthrough probe if the plan prescribes one" | Not prescribed — fixed date, `status: scheduled` fires on its date; the publisher flags a missed day as `stale` | Cut (CTO R1) |
| Timing "~Dec", hub Nov 19–26 | Hub's social wave is parked until 2026-11-19; nothing is scheduled past that; Thu 2026-12-03 is two weeks after the hub, avoids US Thanksgiving week | Proposed `2026-12-03` (operator schedule row; AC keeps all date sites coherent if moved) |

## Research Insights

**Premise Validation.** Checked: #8764 CLOSED / #11278 MERGED (the census exists on main, script
present, runs clean); #11362 OPEN (hub issue) but PR #11378 MERGED 2026-10-28 and the hub file is on
main; #10971 CLOSED (epic); #8726 CLOSED, #8717 MERGED; collision-precheck hit on #11364 is this
branch's own draft PR #11421 (not foreign — advisory only). ADR corpus: no ADR forbids a
scheduled-with-future-date distribution file; the hold-lever learning
(`knowledge-base/project/learnings/best-practices/2026-10-28-parked-distribution-hold-for-future-dated-posts.md`)
applies only to a *window*, not a fixed day. Held: all premises. Stale: none.

**Property List** (what the work must buy):

1. A non-technical founder can read the post, recognise their own problem (alarms that pass practice but go silent in real life), and leave with a question to ask their builders.
2. Every factual claim traces to a checkable source; the post never claims "Inngest is broken" or that the technique is proven outside this one tool.
3. The post is reachable (sitemap, canonical URL, dated→canonical 301, social card) and cross-linked with its hub in both directions.
4. The social wave fires exactly once, on the chosen date, after the hub's wave.
5. The marketing inventory (content-strategy row, campaign calendar) reflects the piece.

**Cut List.**

- Notify-only follow-through probe + test + `test-all.sh`/`test-affected-paths.sh` registration → buys "social wave not silently skipped" → already covered by `scripts/content-publisher.sh:884-896` (fires `scheduled` on `publish_date`, flips past-dated to `stale` with an event). Ruled by CTO (R1).
- Committed OG generator script → buys nothing the PNG doesn't; `git ls-files` shows zero `.py` in the images dir. Generate inline, commit the PNG only (CTO R4).
- Independent HN submission → the hub carries the front-door claim (brief) and the Blog note says to submit the technical write-up or skip.
- LinkedIn T+4–7d stagger → one `publish_date` per file contract (hub CTO ruling); all four channels same day.

**Institutional learnings applied.**

- `2026-09-24-a-thrown-error-loses-its-status-at-the-inngest-step-boundary-so-return-the-verdict.md` — the primary fact source (serializer keeps message/stack/string cause, drops status and custom name; mock re-throws the raw error in-process; 9 crons + drift guard; a deterministic 400 re-sent under `retries: 3`).
- `2026-09-24-changing-a-step-return-shape-strands-in-flight-runs-…md`, `2026-09-25-onfailure-never-sees-a-cancel-…md` — corroborating context; read at write time, not cited in the body.
- `best-practices/2026-06-02-blog-og-images-deterministic-pil-not-gemini-and-audit-all-references.md` — OG method.
- `best-practices/2026-10-28-parked-distribution-hold-for-future-dated-posts.md` — date-site coherence list (filename, `date:`, redirect key, `publish_date:`) and the seo-aeo-drift-guard blind spot (asserts `ogImage` key present, not file exists).

**Convention sources.** `knowledge-base/marketing/brand-guide.md` `### Blog` (General register, jargon limits, one closing technical URL, one CTA); `plugins/soleur/skills/content-writer/SKILL.md`; hub plan `knowledge-base/project/plans/archive/20261028-112214-2026-10-28-content-testsuite-arc-synthesis-plan.md` (template).

### Open Code-Review Overlap

- #10240 (campaign-calendar refresh review on PR 10140) touches `campaign-calendar.md` / `content-strategy.md` — **Acknowledge:** different concern (a calendar-refresh review nit from an earlier PR); this PR only regenerates the calendar by skill and appends one row.
- #3649 (PR-A2 content brief schedule) touches `content-strategy.md` — **Acknowledge:** unrelated brief; remains open.

## Proposed Solution

1. **Post** at `plugins/soleur/docs/blog/2026-12-03-alarm-passed-every-rehearsal-never-rings.md` (1,500–2,000 words, General register), drafted through `soleur:content-writer` conventions with a `soleur:marketing:fact-checker` pass.
2. **OG card** `plugins/soleur/docs/images/blog/og-alarm-passed-every-rehearsal-never-rings.png` — deterministic PIL, 1200×630, `#1a1a1a` + gold `#c9a962`/`#dcbe6e`, textless, 3× supersample + LANCZOS, metadata-clean; generated inline from `/tmp`, generator not committed.
3. **Redirect pair** appended last in `local.blog_redirect_pairs` (`apps/web-platform/infra/seo-bulk-redirects.tf`), ascending-date order after the `2026-11-19` entry, `=` column-aligned:
   `"2026-12-03-alarm-passed-every-rehearsal-never-rings"           = "alarm-passed-every-rehearsal-never-rings"` (pad to the existing `=` column).
4. **Hub retro-link**: one sentence appended to the hub's census paragraph, `[…]({{ site.url }}/blog/alarm-passed-every-rehearsal-never-rings/)`; no title/slug/meta change; no date promise in the wording.
5. **Distribution file** `knowledge-base/marketing/distribution-content/2026-12-03-alarm-passed-every-rehearsal-never-rings.md`: `type: pillar`, `publish_date: 2026-12-03`, `channels: x, bluesky, discord, linkedin-personal`, `status: scheduled`, `issue_reference: "#11364"`; sections `## X/Twitter Thread`, `## Bluesky`, `## Discord`, `## LinkedIn Personal`; new prose (not a copy of the post), UTM'd absolute URLs per sibling precedent, every `-- NNN chars` label computed; run `validate-tweet-draft.sh`; fact-check each factual sentence.
6. **Content-strategy row** appended to the Pillar-2 table after the hub row (real 5-column schema `| Piece | Type | Words | Priority | Status |`; hub row already notes "census-lint spoke brief #11364 drafts after this hub").
7. **Campaign calendar** regenerated via `soleur:campaign-calendar` (headless).

## Files to Create

- `plugins/soleur/docs/blog/2026-12-03-alarm-passed-every-rehearsal-never-rings.md`
- `plugins/soleur/docs/images/blog/og-alarm-passed-every-rehearsal-never-rings.png`
- `knowledge-base/marketing/distribution-content/2026-12-03-alarm-passed-every-rehearsal-never-rings.md`

## Files to Edit

- `apps/web-platform/infra/seo-bulk-redirects.tf` — one map entry
- `plugins/soleur/docs/blog/2026-11-19-first-we-made-green-mean-something.md` — one sentence (census paragraph)
- `knowledge-base/marketing/content-strategy.md` — one Pillar-2 row
- `knowledge-base/marketing/campaign-calendar.md` — regenerated
- pipeline-written: `knowledge-base/project/specs/feat-one-shot-11364-census-lint-spoke/{tasks.md,decision-challenges.md,session-state.md}`

(Glob check: all paths verified against `git ls-files` / sibling files at the same depth in this plan session.)

## Implementation Phases

### Phase 1 — Draft + image (prescribed skill checkpoint: `soleur:content-writer`, run inline)

- 1.1 Write the founder sentence in working notes (below), then draft per the Draft Spec.
- 1.2 Write the post (frontmatter + body + FAQ section + parity-matched FAQPage JSON-LD, mirroring `2026-11-17-flaky-test-passed-on-retry-quarantine.md`).
- 1.3 Generate the OG PNG with PIL from `/tmp`; verify 1200×630 RGB, no EXIF/text chunks; commit the PNG only. Motif suggestion: a row of gold cells with one fainter cell flagged by a thin gold ring (a counted set with one registered exception).

### Phase 2 — Site wiring

- 2.1 Redirect pair (item 3). 2.2 Hub sentence (item 4). 2.3 Content-strategy row (item 6).

### Phase 3 — Distribution + calendar

- 3.1 Distribution file (item 5), authored `status: draft` → `validate-tweet-draft.sh` green → flip to `status: scheduled` as the last edit (publisher fires it on 2026-12-03; no `parked`, no probe).
- 3.2 Regenerate the campaign calendar (item 7).

### Phase 4 — Verification (prescribed agent checkpoint: `soleur:marketing:fact-checker`, run inline)

- 4.1 Fact-check every pin below; UNSOURCED claims are cut or sourced.
- 4.2 `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh <post>` → rc 0; then read-through for what the scan can't detect (paths, tool names, bare numbers, "lint"/"census" defined on first use).
- 4.3 `npm run docs:build` clean; `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts plugins/soleur/test/marketing-content-drift.test.ts plugins/soleur/test/distribution-content-format.test.ts plugins/soleur/test/blog-audience-contract.test.ts` green; `bash scripts/validate-blog-links.sh` green.
- 4.4 Mutation sanity (cheap, in-session): delete the PNG → confirm `ls` check (AC5) reds even though the drift guard stays green; drop the redirect entry → `validate-blog-links.sh` reds.

## Draft Spec (contract for the writer step)

- **Title (primary, CTO R5):** "Your Alarm Passed Every Rehearsal. In Real Life It Never Rings." **Fallback:** "Your Error Alerts Can Pass Every Test and Still Never Fire." Issue title stays the working title in notes/PR body only. `seoTitle` ≤ 60 chars carrying the founder problem; `description` 120–160 chars.
- **Founder sentence (notes only):** "A solo founder has this problem: the alarms their business leans on can pass every practice run and still stay silent when something real goes wrong. After reading, they know the one question to ask whoever builds their systems — 'was this alarm ever tested against the real hand-off, and has anyone counted every place an error can be swallowed?'"
- **Frontmatter:** `title`, `seoTitle`, `date: 2026-12-03` (unquoted), `description`, `ogImage: "blog/og-alarm-passed-every-rehearsal-never-rings.png"`, `pillar: billion-dollar-solo-founder`, `tags: [methodology, ai-trust, solo-founder, build-in-public]`; no `layout`/`ogType` (inherited from `blog.json`).
- **Outline (outcome before mechanism):**
  1. Open in the founder's week: you were told "we tested the alarm" — and it passed. What if the test could not have failed?
  2. The shape of the lie, in plain words: when work is handed from one worker to the next, an error arrives rebuilt — the message survives, the label and details don't (a note passed through a translator who keeps the words and strips the stamp). Practice stages hand the note over directly, so the stamp survives and every rehearsal passes.
  3. What it cost (three real cases, outcome-first): a "a deploy is in progress, wait and retry" signal read as a failure, producing a false alarm; a detected secret leak filed as a routine "guard broken" notice; every error from an outside service read as a timeout, so a request that could never succeed was re-sent three more times.
  4. Why we didn't just fix the nine places: finding them one at a time is how the next one slips in. We counted instead — every place that catches an error, sorted into two piles: error already crossed the hand-off (reading its label there is always wrong — flagged, never excused) vs still live inside the task (reading is fine, but only on a short named list; adding to it is a visible, deliberate act).
  5. The other half: the rehearsal stage was rebuilt to hand errors over the way the real one does, so the practice run can finally fail.
  6. The honest limits: the counter knows one tool's hand-off by name; it reads code by pattern, not understanding; it checks three kinds of label reads; it proves one lie cannot return silently, not that every handler is right. The idea transfers — anywhere work changes hands (queues, workflow engines, calls between services): list every catcher, sort by crossed/not crossed; your builders' version will look different.
  7. What you do: the question to ask; hub retro-link once ("this is one repair of seven in [the story of making green mean something]"); closing technical link (PR #11278 URL, CTO R2) behind plain words; waitlist CTA.
- **FAQ (2–4, parity JSON-LD):** e.g. "Can an alert pass every test and still never fire?", "What does it mean for an error to cross a hand-off?", "Does this problem only affect one tool?", "How do I ask my developer whether this applies to me?"
- **Fact-check pin list** (each must map to a source; sources in parentheses): serializer keeps message/stack/string cause and drops status + custom name (learning 2026-09-24; verify against `apps/web-platform/test/helpers/inngest-step-harness.ts` and installed `inngest` `serializeError`); "mock stage re-throws raw error in-process" (same); nine scheduled jobs / one leak-detector affected (#8726 body); deploy-in-progress → false alarm + failed heartbeat (#8726 body: "reported setup failure plus a failed heartbeat"); leak path taken as routine failure (#8726); deterministic API 400 read as timeout and re-sent three more times under `retries: 3` (learning 2026-09-24 — note the *fix* in #8717 is a different handler from the nine crons; keep the three cases attributed to distinct places, never "all of our alarms"); census two shapes + 5-name allowlist + "currently clean" (script); "reads code by pattern" (script uses regex + brace matching); generalization sentence — **sourced and scoped (verified at deepen time)**: Temporal documents that an activity's error reaches the workflow wrapped in an `ActivityFailure` with the original kept as its `cause` (<https://docs.temporal.io/encyclopedia/application-failures>, <https://docs.temporal.io/references/failures.md>). So the shape is *similar but not identical*: some systems drop the label, others keep the original underneath a wrapper — in both the code that catches sees the wrapper, not the original type. The post must say "the same trap shows up in other tools in different forms" and name no vendor in the body; never "Inngest is broken", never "every tool strips the details". Dates: census merged 2026-10-27.
- **Redaction & claim list:** no issue/PR numbers in reader-visible text (the one closing GitHub URL excepted); no file/script names, no backticks, no tool or vendor names in the body beyond what the fact-checker approves for the generalization (prefer none); never counts of test suites/PRs/issues (the 38 suites, the 12 merges belong to the hub); "lint" and "census" each defined in the sentence where first used; do not restate the hub's four-lies taxonomy — link, don't repeat.

## User-Brand Impact

- **If this lands broken, the user experiences:** a public post on soleur.ai that misstates the engineering record (e.g. implies a whole fleet of alarms was silent when it was nine scheduled jobs and one leak path), reads as jargon to the founder audience, shows a broken social card, or posts its social wave on the wrong day.
- **If this leaks, the user's data/workflow/money is exposed via:** nothing — it re-tells an already-public engineering record (merged PRs, closed issues) in founder language; no user data, credentials, or internal-only detail ships.
- **Brand-survival threshold:** `aggregate pattern` — one wrong post is correctable (edit + redeploy); the risk class is a pattern of unreviewed public claims, covered by fact-checker + jargon scan + drift tests.
- **Threshold decision (challengeable):** public, durable, brand-bearing copy with verifiable claims and no user-data surface — above `none`, below `single-user incident`.

## Observability

```yaml
liveness_signal:
  what: "deploy-docs.yml publishes the post on merge; apply-web-platform-infra.yml applies the new bulk-redirect pair; the daily publisher cron fires the scheduled distribution file on 2026-12-03 or flips it to stale with an event"
  cadence: "per merge to main / daily publisher run"
  alert_target: "GitHub Actions run status on main; campaign-calendar overdue/stale flag; publisher stale event"
  configured_in: ".github/workflows/deploy-docs.yml, .github/workflows/apply-web-platform-infra.yml, scripts/content-publisher.sh"
error_reporting:
  destination: "GitHub Actions run logs + required PR checks + publisher stale event"
  fail_loud: "deploy-docs or apply-web-platform-infra red run; validate-blog-links.sh FAIL pre-merge; publisher emits a stale event and flips status: stale if the date is missed"
failure_modes:
  - mode: "post file missing/malformed frontmatter"
    detection: "Eleventy build fails or seo-aeo-drift-guard reds in CI"
    alert_route: "required-check red on the PR"
  - mode: "dated slug has no redirect pair"
    detection: "validate-blog-links.sh Guard-1 parity check"
    alert_route: "CI blog-link-validation suite red"
  - mode: "social card 404 (ogImage key present, file absent)"
    detection: "AC5 on-disk existence check — seo-aeo-drift-guard asserts only key presence (known blind spot, learning 2026-10-28)"
    alert_route: "PR verification step red; link-preview inspection on share"
  - mode: "social wave misses 2026-12-03"
    detection: "scripts/content-publisher.sh:884-896 flips past-dated scheduled files to stale and emits a stale event; campaign-calendar surfaces stale rows"
    alert_route: "stale event + calendar Stale section"
logs:
  where: "GitHub Actions run logs for ci.yml, deploy-docs.yml, apply-web-platform-infra.yml; publisher cron run logs"
  retention: "GitHub-hosted run retention"
discoverability_test:
  command: "grep -c 2026-12-03-alarm-passed-every-rehearsal-never-rings apps/web-platform/infra/seo-bulk-redirects.tf"
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  - store: "cloudflare_list bulk-redirect list item (existing resource; Terraform state on the existing encrypted R2 backend)"
    mechanism: "provider-managed: Cloudflare account-level list; no new store — one map entry appended to an existing committed list"
    evidence: "apps/web-platform/infra/seo-bulk-redirects.tf local.blog_redirect_pairs (entry appended in this diff)"
    defends_against: "n/a — a redirect map entry is public routing metadata, not a data store"
    does_not_defend: "anything; the entry is not sensitive material"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available — post-merge, curl the dated URL shape and observe the 301 to the canonical slug"
in_transit:
  - connection: "visitor -> soleur.ai edge redirect -> canonical post URL"
    enforced_at: "apps/web-platform/infra/seo-bulk-redirects.tf (existing cloudflare_ruleset wiring; unchanged by this diff)"
    tls: "https at the Cloudflare edge — pre-existing, unchanged"
    cert_verification: "on (vendor edge; unchanged)"
    does_not_defend: "n/a — no new connection; the redirect target is an https URL already in the same map"
    disclosed_as: "not-publicly-claimed"
```

## Domain Review

**Domains relevant:** Marketing

### Marketing

**Status:** reviewed
**Assessment:** Carried forward from the issue brief (CMO arc assessment executed at epic close per `epic-close-sweep.md`) and the hub plan's Marketing review; this IS the marketing deliverable — a P3 Pillar-2 spoke. Binding constraints are mechanical and enforced by tests: General register, founder-first opening, jargon limits (`blog-jargon-scan.sh`, `blog-audience-contract.test.ts`), absolute-URL distribution rules, one closing technical link, one CTA, no independent HN submission. The central editorial risk is the generalization claim (over-claiming beyond the one tool) — handled by the honest-limits section and a sourced-or-scoped fact pin.

**Brainstorm-recommended specialists:** none (no brainstorm ran). The brief prescribes `soleur:content-writer` + `soleur:marketing:fact-checker`; both are encoded as inline work-time checkpoints (Phases 1 and 4), not spawns this plan can perform.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "content(blog) spoke post titled 'A Lint That Enumerates Every Place an Error Can Be Swallowed'" | Post (title treatment per brand guide, CTO R5) | mapped |
| 2 | "Route: soleur:content-writer (Blog register — General register…) + fact-checker pass" | Phase 1 + Phase 4.1 checkpoints | mapped |
| 3 | "link to [the hub] per hub-and-spoke rule; the spoke retro-links" | Post→hub link; hub sentence | mapped |
| 4 | "keep the post honest about [Inngest-specific vs. generalizing]" | Honest-limits outline item 6 + sourced-or-scoped fact pin | mapped |
| 5 | "deterministic-PIL OG image (1200×630, #1a1a1a + gold…, textless)" | Phase 1.3 | mapped |
| 6 | "redirect pair in seo-bulk-redirects.tf (ascending-date order, column-aligned =)" | Phase 2.1 | mapped |
| 7 | "distribution file modeled on …2026-11-19-first-we-made-green-mean-something.md (publish_date lands after 2026-11-19 — you decide)" | Phase 3.1; date 2026-12-03 (operator schedule row) | mapped |
| 8 | "content-strategy row, campaign-calendar regen, and a followthrough probe if the plan prescribes one" | Phases 2.3, 3.2; probe cut with reason | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Post / OG / redirect / distribution / strategy row / calendar | the ask lines above | asked |
| Hub retro-link sentence | "the spoke retro-links" / "link to it per hub-and-spoke rule" | asked |
| `status: scheduled` (not parked) + no probe | "a followthrough probe if the plan prescribes one" | asked — plan declines to prescribe (CTO R1) |
| On-disk `ogImage` existence check (AC5) | — | inferred — justification: seo-aeo-drift-guard asserts key presence only; a deleted PNG leaves it green (learning 2026-10-28) |

### Split Assessment

- Subsystems touched: 3 (`plugins/soleur` docs, `apps/web-platform/infra` tf, `knowledge-base` marketing)
- Planned files: 3 created + 4 edited
- Estimated changed lines: ~350 (mostly post + distribution)
- Thresholds: ≥ 4 subsystem roots OR > 25 files OR > 800 lines — none met
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — Post exists at `plugins/soleur/docs/blog/2026-12-03-alarm-passed-every-rehearsal-never-rings.md` with `title`, `seoTitle`, `date: 2026-12-03` (unquoted), `description` (120–160 chars), `ogImage`, `pillar`, `tags`; no `layout`/`ogType`.
- [ ] AC2 — Body word count 1,500–2,000 (frontmatter + JSON-LD excluded).
- [ ] AC3 — `blog-jargon-scan.sh <post>` exits 0; no issue/PR numbers, backticks, code, paths, commands or tool/vendor names in reader-visible text; "lint"/"census" defined where first used; title/SEO title/description name the founder's problem.
- [ ] AC4 — Fact pins all sourced (fact-checker pass recorded in the PR); the generalization sentence is sourced or scoped; the three cost cases are attributed to distinct places; no suite/PR/issue counts in the body; no restatement of the hub's four-lies taxonomy.
- [ ] AC5 — `plugins/soleur/docs/images/blog/og-alarm-passed-every-rehearsal-never-rings.png` exists, is 1200×630 (`python3 -c 'from PIL import Image;print(Image.open(p).size)'` prints `(1200, 630)`), and `ogImage` references it; no generator script committed.
- [ ] AC6 — `grep -c 2026-12-03-alarm-passed-every-rehearsal-never-rings apps/web-platform/infra/seo-bulk-redirects.tf` prints `1`; the entry is last, after the `2026-11-19` line, `=` column-aligned with its neighbours; `bash scripts/validate-blog-links.sh` green.
- [ ] AC7 — Post links the hub once (`{{ site.url }}/blog/first-we-made-green-mean-something/`); hub gains exactly one sentence linking the spoke, title/slug/meta/date untouched, no date promise; post carries exactly one closing technical link (`https://github.com/jikig-ai/soleur/pull/11278`) and one CTA (`https://soleur.ai/pricing/#waitlist`).
- [ ] AC8 — Distribution file has `status: scheduled`, `publish_date: 2026-12-03`, `issue_reference: "#11364"`, channels `x, bluesky, discord, linkedin-personal`, the four section headings; `validate-tweet-draft.sh` green; every `-- NNN chars` label computed; Bluesky ≤ 300 chars including URL; tweets ≤ 280; UTM'd absolute URLs; no `parked`/`draft` left.
- [ ] AC9 — Content-strategy Pillar-2 table gains the spoke row after the hub row (5-column schema, naming title, 2026-12-03, #11364, "hub: #11362"); `campaign-calendar.md` regenerated and enumerates the new file in the Upcoming section.
- [ ] AC10 — Date coherence: `2026-12-03` is identical across the blog filename, frontmatter `date:`, redirect key, distribution filename + `publish_date:`, and content-strategy row; if the slot moves at review/ship, all move together (`grep -rn 2026-12-03` returns the same set of sites and no stale `2026-12-0` variants).
- [ ] AC11 — `bun test` for `seo-aeo-drift-guard`, `marketing-content-drift`, `distribution-content-format`, `blog-audience-contract` green; `npm run docs:build` clean.
- [ ] AC12 — PR body line 1 states the merge-mutates-production answer: the bulk-redirect list gains one item via auto-apply, and deploy-docs makes **both the spoke and the edited hub** live at merge (no future-date filter); only the social wave is date-gated. Body carries `Closes #11364`.

### Post-merge

- [ ] AC13 — `curl -sI https://soleur.ai/blog/2026-12-03-alarm-passed-every-rehearsal-never-rings/` shows a 301 to the canonical slug; canonical URL returns 200; OG image URL returns 200 `image/png`.
- [ ] AC14 — On 2026-12-03 the publisher posts the file and flips it to `published` (observable in the campaign calendar's Published section); no manual lever required.

## Test Scenarios

- Jargon scan on the draft returns rc 0; deliberately adding a backtick or `#8726` to a scratch copy returns non-zero (scan not vacuous).
- Removing the redirect entry reds `validate-blog-links.sh`; restoring it greens it.
- Deleting the PNG leaves `seo-aeo-drift-guard` green but AC5's size check fails (documents the known blind spot).
- Setting the distribution file's `publish_date` to a past date and running the publisher in dry mode flags stale (no probe needed to prove the safety net).

## Dependencies & Risks

- **Blog is live at merge, social wave Dec 3.** Eleventy has no future-date filter; the post is reachable (and in the sitemap) from merge, as the hub and the Nov 17 spoke are. Accepted by precedent; flagged in the PR body.
- **Hub wave is parked until 2026-11-19.** If the operator moves the hub's slot past 2026-12-03, the spoke's wave would precede the hub's: re-date the spoke (AC10 lists the sites).
- **Over-claiming the generalization** is the one editorial risk — gated by the sourced-or-scoped fact pin.
- **Fact drift:** the censused file count (82/72) and allowlist size (5) are point-in-time; the post uses neither number.
- **seo-aeo-drift-guard blind spot** (ogImage presence only) — covered by AC5; a hardening follow-up was already filed at the hub PR.

## References & Research

- Brief: #11364 (child #8764 of epic #10971); hub issue #11362; hub PR #11378; census PR #11278; defect #8717/#8726; fix #8758.
- Script: `scripts/lint-inngest-step-boundary.py`, `scripts/lint-inngest-step-boundary.test.sh`, `scripts/test-all.sh:5653-5655`.
- Publisher: `scripts/content-publisher.sh:884-896`; promotion gate `apps/web-platform/server/inngest/functions/content-promotion.ts` (`isReadyDraft`).
- Siblings: `knowledge-base/marketing/distribution-content/2026-11-17-flaky-test-passed-on-retry-quarantine.md` (scheduled, no probe), `…/2026-11-19-first-we-made-green-mean-something.md` (hub, parked).

## Enhancement Summary

**Deepened on:** 2026-10-28. Method: mechanical halt gates run by hand against the finished plan; targeted source verification of the two riskiest fact pins (no generic per-section fan-out — the plan is content/wiring with no code-design surface).

### Halt gates

| Gate | Result |
|---|---|
| 4.6 User-Brand Impact | present, concrete, threshold `aggregate pattern` — pass |
| 4.7 Observability | 5-field block present; `discoverability_test.command` first token `grep` (allowlisted), no ssh verb, finishes < 1s; `expected_output` is the literal `1` (prints `0` until the redirect entry lands — expected pre-implementation) — pass |
| 4.8 PAT / 4.9 UI wireframe | not applicable (no workflow/credential, no UI surface) |
| 4.10 Encryption Posture | `.tf` edit triggers detection; section present with named evidence and non-empty `does_not_defend` — pass |
| 4.11 Guard Contract / 4.13 Task Design | not triggered — probe cut, no guard or autonomous-task surface added |
| 4.12 Scope Check | Ask Mapping + Provenance + Split Assessment present; every `inferred` item justified — pass |

### Key improvements applied

1. **Generalization pin corrected.** Verified Temporal's documented behaviour: errors arrive wrapped in an `ActivityFailure` with the original preserved as `cause`. That differs from the Inngest case (label and custom fields lost). The brief's "same shape in Temporal" is true of the *catch-sees-a-wrapper* shape, not of *details are stripped* — pin and outline item 6 now say "similar, in different forms" and forbid a blanket claim.
2. **Primary fact source tightened.** The "label and fields are dropped, rehearsal mock re-throws raw" claim is recorded in the repo's own pinned-SDK harness header (`apps/web-platform/test/helpers/inngest-step-harness.ts:5-17`, built on the real `serializeError` + `StepError` from `inngest` 3.54.2) and in the 2026-09-24 learning; the fact-checker cites these rather than vendor marketing.
3. **Jargon-scan reality check.** `blog-jargon-scan.sh` flags only backticks, `<code>/<pre>`, `--flag` tokens and `#NN` — it will NOT catch "lint", "census", "serialization" or vendor names; Phase 4.2's manual read-through is the real gate for those and is kept.
4. **Hub overlap guard.** The hub already carries one paragraph on this census; the spoke must not restate the hub's four-lies taxonomy (AC4) — the spoke earns its slot by the three cost cases + the crossed/live sorting + the honest limits.

### Open items carried to work phase

- Operator may move 2026-12-03 (schedule row in `decision-challenges.md`); AC10 is the single date-coherence sweep.
- Fact-checker must also run on the distribution variants (social-distribute guidance: variants are new prose).

### Sharp-edge note

A plan whose `## User-Brand Impact` section is empty or placeholder text fails `deepen-plan` Phase 4.6; this plan fills it (threshold `aggregate pattern`). The headings `## Guard Contract` and `## Task Design` are intentionally absent: this change adds no guard, gate or autonomous-task surface (the probe was cut); the existing drift/jargon/link tests are reused unmodified.
