---
title: "content: 'We Audited 102 Guardrails. Only Four Belong in Every Repository.' — verification-scaffold spoke (Pillar 2 methodology)"
type: content
date: 2026-10-24
slug: content-guardrail-audit-spoke
branch: feat-one-shot-10903-guardrails-audit
issue: 10903
closes: 10903
priority: p2-medium
domain: marketing
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# Content: "We Audited 102 Guardrails. Only Four Belong in Every Repository." — verification-scaffold spoke (#10903)

## Overview

Write and ship the Pillar-2 methodology article for the verification-scaffold corpus audit
(PR #10744, issue #10404): we classified all 102 members of our own hook/lint corpus
(56 pre-commit hooks + 46 repository lints, census dated 2026-10-21) as generic /
generic-after-extraction / soleur-coupled, and exactly four guards shipped to user
repositories as self-contained, advisory-first, bite-proof templates. The post is a linked
spoke of the arc synthesis (#10902, published at
`plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`): it publishes
after the hub and retro-links to it, and the hub gains one spoke link back per the arc brief's
hub-and-spoke design.

The brief is retroactive — PR #10744's ship tail skipped the Phase 5.5 CMO gate (manual merge
drive after a runner failure), so the content machinery catches up now.

## Problem Statement / Motivation

The 102-file census is the strongest single data point in the agentic-verification arc: the
portable fraction of a mature guardrail corpus is far smaller than anyone assumes, and the
audit methodology (classification, advisory-first contract, bite-proof install, refusal
matrix) is the story. The article converts an internal engineering artifact into a Pillar-2
methodology post for the blog's actual reader — a non-technical solo founder — and gives the
X thread its payload (the 0-of-56 / 9-of-46 census split). Timing: slot after the arc
synthesis so it can be a linked spoke; not with-merge distribution.

## Proposed Solution

Produce one PR containing:

1. The blog post (1,500–2,000 words, General register per the brand-guide Blog note) at
   `plugins/soleur/docs/blog/2026-10-27-audited-102-guardrails-four-portable.md`, generated
   through the `soleur:content-writer` conventions (frontmatter, FAQ + FAQPage JSON-LD,
   Blog-note jargon limits, founder re-angle).
2. A bespoke OG image at
   `plugins/soleur/docs/images/blog/og-audited-102-guardrails-four-portable.png`
   (1200×630, `#1a1a1a` background, `#c4a35a` gold, textless) generated with the Pillow
   fallback — `soleur:gemini-imagegen` is unavailable (stored `GEMINI_API_KEY`s dead;
   rotation tracked in #10940; #10939 shipped the arc post's card via Pillow for the same
   reason).
3. A dated→canonical redirect pair in `apps/web-platform/infra/seo-bulk-redirects.tf`
   `local.blog_redirect_pairs` (Guard-1 parity — every date-prefixed post needs an edge 301
   entry; enforced by `scripts/validate-blog-links.sh` and
   `plugins/soleur/test/lib/bulk-redirect-pairs.ts`).
4. A social-distribution draft at
   `knowledge-base/marketing/distribution-content/2026-10-27-audited-102-guardrails-four-portable.md`
   (`status: draft`, channels `x, bluesky, discord, linkedin-personal`; the X thread carries
   the census split as its payload).
5. A one-sentence spoke link edit inside the published arc post
   (`plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md`, in the
   "Safety rails you can install" section where the 102-audit is already summarized) —
   the hub→spoke direction of the arc brief's hub-and-spoke design.
6. Regenerated `knowledge-base/marketing/campaign-calendar.md` via the
   `soleur:campaign-calendar` skill (auto-generated from `distribution-content/` frontmatter
   — the regen-by-inventory habit from the cited learning).

## Technical Considerations

- **Filename date coherence (one source of truth).** The blog filename date, frontmatter
  `date:`, the distribution file's `publish_date:`-to-be, and the redirect pair's key must
  all carry `2026-10-27`. The publish date is an assumed scheduling default (recorded in
  `decision-challenges.md`): the first Tue–Thu day of the arc's publish week, after the arc
  post is live. There is no future-date exclusion in `eleventy.config.js` — the post goes
  live on merge-to-deploy regardless of `date:`, so if the operator wants a different slot,
  the filename + frontmatter + redirect key move together.
- **Jargon limits are mechanical, not stylistic.** `blog-jargon-scan.sh` flags backticks,
  code/pre tags, `--flags`, and `#NN` tokens in reader-visible text; the Blog note bans file
  paths, commands, API/tool names, and internal skill/agent names outright. All corpus
  internals must render in founder terms: hooks → "checks that run before work is saved";
  `gitleaks` → "a widely used secrets scanner"; `TMPDIR` worktree → "a throwaway copy of the
  repository"; exit 69 → "it refuses out loud"; `guards.tsv`/manifest → "a written inventory
  the build re-checks"; issue/PR numbers → omitted (allowed only inside the one closing
  GitHub URL).
- **Fact-check pin.** The authoritative census is **102 files at census date 2026-10-21**
  (56 hooks + 46 lints), not ~121 (a count including test files) and not the live 104
  (two corpus members merged after the census — `lib/commit-target-roots.sh` on 2026-10-22,
  `lint-hcloud-token-readonly-no-fallback.sh` on 2026-10-23; both classified
  `soleur-coupled`, neither changes any verdict). The post says "102" and the census verdicts
  exactly as the audit records them.
- **OG image is a hard CI gate** (`seo-aeo-drift-guard.test.ts` threads `ogImage` into
  BlogPosting.image; content-writer treats it as mandatory). Pillow fallback is the plan —
  do not block on Gemini key rotation.
- **No Liquid in distribution bodies** (`lint-distribution-content.sh`); distribution links
  must be absolute `https://soleur.ai/…` URLs (`distribution-content-format.test.ts`), each
  declared channel needs its exact section heading (`## X/Twitter Thread`, `## Bluesky`,
  `## Discord`, `## LinkedIn Personal`), labeled tweets ≤ 280 chars, `status: draft` for the
  tweet-draft validator.
- **FAQ parity.** If the post carries a visible `## Frequently Asked Questions` section, its
  questions and answers must match the FAQPage JSON-LD `mainEntity` twins verbatim
  (`seo-aeo-drift-guard.test.ts` parity tests). Follow the arc post's format: `###` question
  headings + plain answers + trailing JSON-LD block.
- **Merging this PR mutates production (first line of the PR body).** `apply-web-platform-infra.yml`
  auto-applies `apps/web-platform/infra/**` on push to main — the bulk-redirect list gains the
  new pair at merge. Deploy of the post itself goes through `deploy-docs.yml` (push to main,
  `plugins/soleur/docs/**`). Both are the existing IaC/deploy paths; no manual step.
- **Brand/subject claims.** `marketing-content-drift.test.ts` bans Soleur-subject
  Apache-2.0/open-source claims and "Spark"-tier references, and soft-floor rules apply to
  agent/skill counts in prose ("60+ agents", never exact counts).
- **Pillar frontmatter** must resolve to a `_data/pillars.js` series key; use
  `pillar: billion-dollar-solo-founder` (the arc post's series). Do not add a `members[]` row —
  the arc post itself declares the key without membership, and a member row would be the
  series-edit decision, not this PR's.
- **No guard ships — the article is ABOUT guards.** The deliverable is prose + a PNG + a
  map entry; no `lint-*`, `*.test.sh`, hook, CI gate, or `lifecycle.precondition` is created
  or modified. Plan Phase 2.12 (Guard Contract) assessed and skipped on that basis; the word
  "guardrail" in the prose is subject matter, not a deliverable shape.
- **Precedent-diff:** the only code-shaped edit is a one-line map append in
  `seo-bulk-redirects.tf` — the file's own `blog_redirect_pairs` convention is the precedent
  (most recent entry added by PR #10922 / commit `1bc951094c` for the arc post); the diff is
  identical in shape, differing only in the slug strings.

## Research Insights

**Premise validation (Phase 0.6).** Every cited reference verified live:

- Issue #10903 OPEN; issue #10404 CLOSED; PR #10744 MERGED on `origin/main`
  (`93583f8d27`); review findings issue #10759 CLOSED; sibling #10904 OPEN (no overlap);
  arc issue #10902 OPEN with its post already merged via PR #10922 (publish/distribution
  tail pending — the hub file exists on main, so the spoke's link target resolves at the
  next docs deploy).
- Cited sources all exist: `plugins/soleur/skills/verification-scaffold/SKILL.md`,
  `references/guardrail-audit.md`, `references/guards.tsv`,
  `knowledge-base/project/learnings/2026-10-21-one-regen-gap-three-committed-state-reds.md`.
- **One staleness found:** the audit doc's hooks header says "**56 files**" while its own
  census table holds 57 rows — the census (dated 2026-10-21) predates
  `.claude/hooks/lib/commit-target-roots.sh` (merged 2026-10-22); #10891 later bumped the
  lint header 46→47 on the same pattern. The article uses the dated-census figure (102),
  which is correct as stated; the header nit is out of scope here (recorded under
  Findings below).
- The issue's own parenthetical is slightly stale too — it says `9/8/29` lints (sums to
  46, the census value); the doc now reads `9/8/30` (47). Both are honest at their dates;
  the post publishes the census-date numbers.
- Proposed mechanism check vs ADR corpus: the delivery mechanism (blog post + Cloudflare
  bulk-redirect pair + distribution draft) follows the conventions ADR-194 (docs site on
  Cloudflare Pages) and the #3328 redirect migration already established; no ADR's
  rejected-alternatives table is re-entered. ADR-130/136 govern Cloudflare apply safety —
  we add an item to an existing list resource, not a new ruleset phase.

**Property list (Phase 0.6b).**

1. A Pillar-2 spoke post exists and reads to the blog's founder audience (Blog note).
2. It retro-links the arc hub and is linked back (hub-and-spoke from the #10902 brief).
3. Its URL is stable/canonical — dated→canonical redirect pair present.
4. Social payloads exist for the declared channels (X thread = census payload).
5. All existing content gates stay green (ogImage, jargon scan, tweet-draft structure,
   redirect parity, content-drift, FAQ parity).

**Cut list.** No new machinery proposed or needed:

- content-writer conventions + `blog-jargon-scan.sh` + `validate-tweet-draft.sh` +
  `validate-blog-links.sh` already cover every property — no new validator.
- content-strategy.md rows for #10903 already exist (written by PR #10922) — do not re-edit.
- `pillars.js` membership row — not needed (arc precedent: declare the key only).
- Campaign-calendar regeneration uses the existing `soleur:campaign-calendar` skill — not a
  new script.

**Relevant file paths.**

- `plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md` — arc hub;
  format + voice + FAQ/JSON-LD convention; also the retro-link target.
- `plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md` — the census
  (the story's source of truth and the technical write-up the post links).
- `plugins/soleur/skills/verification-scaffold/SKILL.md` + `references/guards.tsv` — the four
  v1 guards, advisory-first contract, bite-proof description.
- `knowledge-base/marketing/brand-guide.md` §Channel Notes > ### Blog (lines 500–517) —
  register, founder-sentence rule, jargon limits, one-closing-link rule, CTA rule.
- `plugins/soleur/skills/content-writer/SKILL.md` — frontmatter schema, unquoted `date:`,
  ogImage mandate, jargon-scan phase, fact-checker phase.
- `knowledge-base/marketing/distribution-content/2026-10-23-agentic-verification-arc.md` —
  distribution file precedent (frontmatter shape, section headings, UTM link style).
- `apps/web-platform/infra/seo-bulk-redirects.tf` (locals `blog_redirect_pairs`) — append
  one pair at the end of the ascending-date map.
- `scripts/validate-blog-links.sh`, `scripts/lib/validate-tweet-draft.sh`,
  `plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh` — the three local
  verification commands (all executed once during planning to confirm they exist and run).

**Institutional learnings applied.**

- `2026-10-21-one-regen-gap-three-committed-state-reds.md` (cited by the brief) —
  regenerate derived artifacts by inventory, not by plan list: the new distribution file is
  enumerated by `campaign-calendar.md` (regenerated via the campaign-calendar skill), the
  dated post filename is enumerated by `blog_redirect_pairs` (the .tf edit), the OG image is
  enumerated by `ogImage` frontmatter (the .png file).
- `2026-10-21-sibling-session-owned-commits-on-my-branch.md` — stage only this feature's
  paths.
- The audit-doc header nit (56-header vs 57-row table) is itself the measured-census class —
  surfaced, not silently edited inside a content PR.

**CLAUDE.md / constitution conventions.** kebab-case filenames; `YYYY-MM-DD-<type>-<slug>-plan.md`;
plan review precedes tasks.md; no version bumps; General register for blog content.

**Findings (surfaced, not folded).**

- `guardrail-audit.md` hooks header "56 files" predates the post-census addition of
  `lib/commit-target-roots.sh` — a one-line header bump (56→57) on main is the fix; out of
  scope for a content PR (recorded for the operator in decision-challenges).
- HN submission is conditional ("if the fortnight's slot is free") and submits the technical
  write-up (the public audit doc), never the post (Blog note's HN rule); tracked as a
  distribution note, not a deliverable.

### Open Code-Review Overlap

One hit: **#3649** (`marketing: PR-A2 #3603 content brief — schedule for PR-C merge`) mentions
`knowledge-base/marketing/distribution-content/` in its body. **Disposition: acknowledge** —
it concerns a different content piece's scheduling and touches no file this plan creates or
edits; our distribution file is new.

## Files to Create

- `plugins/soleur/docs/blog/2026-10-27-audited-102-guardrails-four-portable.md` — the spoke post
- `plugins/soleur/docs/images/blog/og-audited-102-guardrails-four-portable.png` — OG card (Pillow)
- `knowledge-base/marketing/distribution-content/2026-10-27-audited-102-guardrails-four-portable.md` — social draft

## Files to Edit

- `apps/web-platform/infra/seo-bulk-redirects.tf` — append one `blog_redirect_pairs` entry
- `plugins/soleur/docs/blog/2026-10-23-agentic-verification-checklist-shipped.md` — one-sentence spoke link
- `knowledge-base/marketing/campaign-calendar.md` — regenerated by the campaign-calendar skill

## Implementation Phases

### Phase 1 — Draft + image

- 1.1 Run `soleur:content-writer` conventions against this plan's **Draft Spec** below:
  founder sentence first (working notes), General register, outline, redaction list.
- 1.2 Write `plugins/soleur/docs/blog/2026-10-27-audited-102-guardrails-four-portable.md`
  (frontmatter + 1,500–2,000-word body + FAQ section + parity-matched FAQPage JSON-LD).
- 1.3 Generate `plugins/soleur/docs/images/blog/og-audited-102-guardrails-four-portable.png`
  with Pillow: 1200×630 RGB PNG, `#1a1a1a` background, `#c4a35a` gold accent, textless
  abstract motif (suggested: a dense grid of ~102 cells with exactly four highlighted —
  the census visual), metadata-clean. If Pillow generation is somehow unavailable, reuse
  `og-agentic-verification-checklist.png` (nearest on-theme card, #10939 precedent) rather
  than omit the field.

### Phase 2 — Site wiring

- 2.1 Append to `local.blog_redirect_pairs` in
  `apps/web-platform/infra/seo-bulk-redirects.tf` (end of the ascending-date map, matching
  the column-aligned `=` style):
  `"2026-10-27-audited-102-guardrails-four-portable" = "audited-102-guardrails-four-portable"`.
- 2.2 Edit `2026-10-23-agentic-verification-checklist-shipped.md` — in the
  "Safety rails you can install" section, append one plain-words sentence linking the spoke:
  `[the audit's full story]({{ site.url }}/blog/audited-102-guardrails-four-portable/)`.
  Facts-only update of a published post; title/slug/H1/meta/keywords untouched (Blog note's
  refresh rule).

### Phase 3 — Distribution draft + calendar

- 3.1 Write
  `knowledge-base/marketing/distribution-content/2026-10-27-audited-102-guardrails-four-portable.md`:
  frontmatter `title` (post title), `type: pillar`, `publish_date:` empty, `channels: x,
  bluesky, discord, linkedin-personal`, `status: draft`, `issue_reference: "#10903"`; body
  sections `## X/Twitter Thread` (labeled `**Tweet N**`, each ≤ 280 chars, census table as
  the payload tweet, closing tweet links `https://soleur.ai/blog/audited-102-guardrails-four-portable/`
  with utm params per arc precedent), `## Bluesky`, `## Discord`, `## LinkedIn Personal`.
  No Liquid markers anywhere in the body; absolute URLs only.
- 3.2 Regenerate `knowledge-base/marketing/campaign-calendar.md` (campaign-calendar skill,
  `--headless`) so the new draft is enumerated.

### Phase 4 — Verification

- 4.1 `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh <post>` → rc 0.
- 4.2 `bash scripts/lib/validate-tweet-draft.sh <distribution file>` → rc 0.
- 4.3 `npm run docs:build` clean; `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts
  plugins/soleur/test/marketing-content-drift.test.ts
  plugins/soleur/test/distribution-content-format.test.ts
  plugins/soleur/test/blog-audience-contract.test.ts` green.
- 4.4 `bash scripts/validate-blog-links.sh` Guard-1 parity green (post ↔ redirect pair).
- 4.5 Word count check: body (frontmatter + JSON-LD excluded) inside 1,500–2,000.
- 4.6 Read-through pass against the **Redaction & claim list** below — every claim traces
  to a cited source.

## Draft Spec (contract for the writer step)

- **Title (default):** "We Audited 102 Guardrails. Only Four Belong in Every Repository."
  — keep the census hook but re-angle per the Blog note if the draft's title/SEO/first
  paragraph can name the founder's problem more directly (taste call; recorded in
  decision-challenges).
- **Founder sentence (working notes, not the post):** "A solo founder has this problem: their
  AI writes code faster than they can check it, and they have no way to know whether the
  safety checks around that code actually work. After reading, they know only a small set of
  safety checks belong in every codebase — and that a check which cannot prove it catches
  anything is a document, not a guard."
- **Frontmatter:** `title` (above), `seoTitle` ≈ "102 Guardrails Audited: Only Four Belong in
  Every Repo", `date: 2026-10-27` (unquoted), `description` 120–160 chars carrying the census
  hook, `ogImage: "blog/og-audited-102-guardrails-four-portable.png"`,
  `pillar: billion-dollar-solo-founder`, `tags: [agentic-verification, methodology,
  guardrails, solo-founder, build-in-public]`.
- **Outline (mapped to the brief's data points):**
  1. Opening — the founder's problem in their words: AI produces work faster than you can
     check it; you lean on automated checks you never wrote and cannot see.
  2. The audit — to ship safety checks into other people's repositories we first had to
     count our own: 102 checks, in two families (56 that fire before work is saved, 46 that
     sweep the whole codebase). Three verdicts: portable now / portable after repackaging /
     welded to our machinery.
  3. The result — zero of the 56 were portable as they stood; nine of the 46 were; the
     honest table (0/10/46 and 9/8/29 in founder-legible phrasing — see the number note
     below). Almost everything a mature safety practice accumulates is coupled to the repo
     it grew in. The audit is the story: most teams would have promised a hundred and shipped
     four quietly.
  4. The four that shipped — a scan for secrets accidentally committed; a check that work
     never lands straight on the main line; a check that unfinished work is never stashed
     and forgotten; a check that a test suite nothing runs cannot pass silently. Each in one
     founder-register sentence.
  5. Advisory-first — every check arrives warning, not blocking; identical tests, a different
     verb; promotion to blocking requires one clean observed run first.
  6. Proven before it activates — each install rehearses on a throwaway copy: the check must
     catch a planted violation, then go quiet when it's removed; it refuses to install over
     anything you already have (no force flag), and it refuses to rehearse inside the repo
     it's meant to protect.
  7. What review found — the honest build log (the escape-handling edge, the truncated log,
     the misreported removal, the unpinned acceptance surfaces — all filed and fixed), plus
     the structural find: three red surfaces, one regeneration gap, one commit.
  8. The lesson — the portable fraction of a real safety corpus is smaller than anyone
     assumes; measure it before promising it. A check that cannot be proven to fire is a
     document, not a guard.
  9. Close — retro-link the arc post once inline ("the build log this expands"), then the
     single closing technical link: the public audit on GitHub
     (`https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md`),
     then the waitlist CTA (`https://soleur.ai/pricing/#waitlist`).
- **FAQ (2–4 questions, parity JSON-LD):** e.g. "What is a guardrail for AI-written code?",
  "Why did only four of 102 checks qualify?", "Can an automated check itself be wrong?",
  "Do these checks replace a human reviewing the work?" — founder-readable answers only.
- **Numbers note for the draft:** the census-date split is 56+46=102 with verdicts
  hooks 0 generic / 10 repackagable / 46 welded-shut and lints 9 / 8 / 29 — the issue body
  prints "0/10/47" for hooks which sums to 57; the census-date soleur-coupled hook count is
  46 (the 47th, `lib/commit-target-roots.sh`, is post-census). Publish the dated-census
  numbers; if the draft prefers rounder honesty, "of the 56 pre-commit checks, none was
  portable; of the 46 repo-wide checks, nine were" is the load-bearing sentence either way.

## User-Brand Impact

- **If this lands broken, the user experiences:** a published post on soleur.ai that
  misstates the audit's numbers, reads as jargon-walled engineering content to the founder
  audience, or 404s its social card — a public, durable artifact carrying a wrong or
  embarrassing claim.
- **If this leaks, the user's data/workflow/money is exposed via:** nothing — the post
  re-publishes an already-public engineering record (merged PR, public audit doc) in
  founder language; no user data, credentials, or internal-only detail ships in it.
- **Brand-survival threshold:** `aggregate pattern` — one wrong blog post is correctable
  (edit + redeploy); the risk class is a pattern of unreviewed public claims, which the
  fact-checker/jargon-scan/drift-test gauntlet already covers.
- **Threshold decision (challengeable):** public copy with verifiable internal claims and
  no user-data surface — above `none` because the artifact is durable and brand-bearing,
  below `single-user incident` because no user action or data hangs on it.

## Observability

```yaml
liveness_signal:
  what: "Docs deploy + redirect apply are both push-triggered on main: deploy-docs.yml publishes the post; apply-web-platform-infra.yml applies the new bulk-redirect pair"
  cadence: "per merge to main"
  alert_target: "GitHub Actions run status on main (red run = failed publish or apply)"
  configured_in: ".github/workflows/deploy-docs.yml, .github/workflows/apply-web-platform-infra.yml"
error_reporting:
  destination: "GitHub Actions run logs + PR check status"
  fail_loud: "deploy-docs or apply-web-platform-infra red run; validate-blog-links Guard-1 FAIL line pre-merge"
failure_modes:
  - mode: "post file missing/malformed frontmatter"
    detection: "Eleventy build fails or seo-aeo-drift-guard reds in CI"
    alert_route: "required-check red on the PR"
  - mode: "dated slug has no redirect pair"
    detection: "validate-blog-links.sh Guard-1 parity check"
    alert_route: "CI blog-link-validation suite red"
  - mode: "social card 404"
    detection: "ogImage frontmatter must point at a committed png; seo-aeo-drift-guard threads it into BlogPosting.image"
    alert_route: "CI red; link-preview inspection on share"
logs:
  where: "GitHub Actions run logs for ci.yml, deploy-docs.yml, apply-web-platform-infra.yml"
  retention: "GitHub-hosted run retention"
discoverability_test:
  command: "grep -c 2026-10-27-audited-102-guardrails-four-portable apps/web-platform/infra/seo-bulk-redirects.tf"
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  - store: "cloudflare_list bulk-redirect list item (existing resource; Terraform state on the existing encrypted R2 backend)"
    mechanism: "provider-managed: Cloudflare account-level list; no new store introduced — one map entry appended to an existing committed list"
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
    does_not_defend: "n/a — no new connection is introduced; the redirect target is an https URL that already exists in the same map"
    disclosed_as: "not-publicly-claimed"
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/seo-bulk-redirects.tf`: one entry in `local.blog_redirect_pairs`.
  No new resources, providers, variables, or secrets; no `terraform import`.

### Apply path

- `apply-web-platform-infra.yml` auto-applies `apps/web-platform/infra/**` on push to main
  (its only other entry point is `workflow_dispatch` with a `reason` input). Merging this PR
  therefore mutates production exactly once: the account-level bulk-redirect list gains one
  item. **PR body line 1 must state this.** Expected blast radius: one added edge 301; no
  resource replacement; no downtime.

### Host fan-out

- N/A — no `terraform_data` SSH provisioner and no host is touched.

### Distinctness / drift safeguards

- Redirects are edge config, identical dev/prod semantics; no `lifecycle.ignore_changes`
  interplay. State already contains `cloudflare_list` items of the same shape.

### Vendor-tier reality check

- Cloudflare bulk-redirect list items are within existing account quotas (the map already
  carries ~25 pairs); no free-tier gate needed.

## Domain Review

**Domains relevant:** Marketing

### Marketing

**Status:** reviewed
**Assessment:** (inline — domain-leader Task spawn unavailable in this subagent context;
assessment performed against `brand-guide.md` + `content-strategy.md` directly.) This IS the
marketing deliverable: a Pillar-2 methodology spoke of the agentic-verification arc.
Binding constraints are mechanical and already enforced: General register, founder-first
opening, jargon limits (blog-jargon-scan), absolute-URL distribution rules, one closing
technical link, waitlist CTA, HN submits the write-up not the post. The brief's own channels
list maps cleanly onto the distribution file's channel enum (`hackernews` is not an
automated channel — noted, not emitted). Content-strategy rows for #10903 already exist
(PR #10922); nothing further to add there.

**Brainstorm-recommended specialists:** none (no brainstorm ran; the brief is the CMO gate's
own output). `soleur:marketing:copywriter` coverage is inherent — the draft step IS the
content pipeline (content-writer + jargon scan + fact-checker at work time).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "content brief 'We Audited 102 Guardrails. Only Four Belong in Every Repository.' (Pillar-2 methodology article, 1,500–2,000 words)" [pipeline args / issue #10903 "**Length:** 1,500–2,000 words. **Type:** engineering deep-dive / methodology."] | Phase 1 → blog post file; Draft Spec | mapped |
| 2 | "Timing: blog scheduled (not with-merge); slot AFTER the arc synthesis (#10902) publishes so it can be a linked spoke" [issue #10903] | publish date 2026-10-27 after the arc post is live; spoke→hub retro-link + hub→spoke edit (Phase 2.2) | mapped |
| 3 | "Channels: blog primary → social-distribute; X thread (the 0/56-generic census table is the thread's payload); HN Tue–Thu via technical write-up if the fortnight's slot is free" [issue #10903] | Phase 3.1 distribution file (X/Bluesky/Discord/LinkedIn); HN noted as conditional write-up submission (not an automated channel) | mapped |
| 4 | "**Fact-check pin:** authoritative census is 102 files (test files excluded), not ~121" [issue #10903] | Technical Considerations number-pin + Draft Spec numbers note | mapped |
| 5 | "**Hook:** … the census is the story" + key data points + lesson + founder re-angle [issue #10903 body] | Draft Spec outline items 1–9 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/docs/blog/2026-10-27-audited-102-guardrails-four-portable.md` | "Pillar-2 methodology article, 1,500–2,000 words" | asked |
| `plugins/soleur/docs/images/blog/og-audited-102-guardrails-four-portable.png` | — | inferred — justification: `ogImage` is mandatory for every post (seo-aeo-drift-guard + content-writer Phase 4.5); a new post cannot land without it |
| `apps/web-platform/infra/seo-bulk-redirects.tf` pair | — | inferred — justification: validate-blog-links Guard 1 fails CI for any date-prefixed post with no `blog_redirect_pairs` entry ("every date-prefixed post has a redirect" property) |
| arc-post spoke link edit | "slot AFTER the arc synthesis (#10902) publishes so it can be a linked spoke" [issue #10903] + "the arc post links each child post per the one-link rule" [#10902 brief] | asked |
| `distribution-content/2026-10-27-…md` | "Channels: blog primary → social-distribute; X thread …" | asked |
| `campaign-calendar.md` regen | — | inferred — justification: the file is auto-generated from distribution-content frontmatter; adding a file without regen repeats the cited regen-gap learning's defect class |
| Pillow OG generation (not gemini-imagegen) | — | inferred — justification: GEMINI keys dead (#10940, unrotated); Pillow is the documented fallback and shipped the sibling card in #10939 |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur` (docs blog+images), `apps/web-platform` (infra tf),
  `knowledge-base` (marketing files)
- Planned files: 5–6 (post, png, tf, distribution md, calendar regen, +1-line arc edit)
- Estimated changed lines: ~350 (mostly the post body)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `plugins/soleur/docs/blog/2026-10-27-audited-102-guardrails-four-portable.md`
      exists; frontmatter carries `title`, `seoTitle`, `date: 2026-10-27` (unquoted),
      `description` (120–160 chars), `ogImage`, `pillar: billion-dollar-solo-founder`,
      `tags`; no `layout`/`ogType` keys (inherited from `blog.json`).
- [ ] AC2 — Post body word count is 1,500–2,000 (frontmatter and the JSON-LD block
      excluded).
- [ ] AC3 — `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh <post>`
      exits 0; no issue/PR numbers, no backticks/code/paths/commands/tool names appear in
      reader-visible text (Blog note).
- [ ] AC4 — Census numbers in the post read 102 files at the stated census split
      (56+46; "only four shipped"), never ~121 and never the post-census 104.
- [ ] AC5 — `plugins/soleur/docs/images/blog/og-audited-102-guardrails-four-portable.png`
      exists (1200×630) and `ogImage: "blog/og-audited-102-guardrails-four-portable.png"`
      references it.
- [ ] AC6 — `local.blog_redirect_pairs` contains
      `"2026-10-27-audited-102-guardrails-four-portable" = "audited-102-guardrails-four-portable"`;
      `grep -c 2026-10-27-audited-102-guardrails-four-portable
      apps/web-platform/infra/seo-bulk-redirects.tf` prints `1`.
- [ ] AC7 — The post retro-links the arc post once (`{{ site.url
      }}/blog/agentic-verification-checklist-shipped/`), and the arc post gains exactly one
      sentence linking `{{ site.url }}/blog/audited-102-guardrails-four-portable/`; the post
      carries exactly one closing technical link (the public audit doc on GitHub) and one
      CTA link.
- [ ] AC8 — `knowledge-base/marketing/distribution-content/2026-10-27-audited-102-guardrails-four-portable.md`
      exists with `status: draft`, `issue_reference: "#10903"`, channels
      `x, bluesky, discord, linkedin-personal`, and the four matching section headings;
      `bash scripts/lib/validate-tweet-draft.sh <file>` exits 0; the X thread states the
      0-of-56 / 9-of-46 census split within the 280-char limit.
- [ ] AC9 — `knowledge-base/marketing/campaign-calendar.md` regenerated to enumerate the new
      distribution file.
- [ ] AC10 — `bun test` suites `seo-aeo-drift-guard`, `marketing-content-drift`,
      `distribution-content-format`, `blog-audience-contract` green; `npm run docs:build`
      clean; `bash scripts/validate-blog-links.sh` Guard-1 green.
- [ ] AC11 — Filename date, frontmatter `date:`, and redirect-pair key all carry the same
      publish date; if the date shifts at ship time, all three move together.
- [ ] AC12 — PR body line 1 states the merge-mutates-production answer (bulk-redirect list
      gains one item via auto-apply; post publishes via deploy-docs).

## Test Scenarios

- `bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh
  plugins/soleur/docs/blog/2026-10-27-audited-102-guardrails-four-portable.md` → rc 0
  (verified against the published arc post during planning; it exits 0 on clean text).
  *(integration — the CI surface that enforces the Blog note's mechanical half)*
- `bash scripts/lib/validate-tweet-draft.sh
  knowledge-base/marketing/distribution-content/2026-10-27-audited-102-guardrails-four-portable.md`
  → rc 0 (verified against an existing `status: draft` file during planning).
  *(integration)*
- `npm run docs:build` → clean build including the new post; then
  `bash scripts/validate-blog-links.sh` → Guard-1 parity PASS (the dated slug is covered by
  the new pair; distribution URLs resolve against `_site/`). *(integration; suite name
  `blog-link-validation` in test-all.sh)*
- `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts
  plugins/soleur/test/marketing-content-drift.test.ts
  plugins/soleur/test/distribution-content-format.test.ts
  plugins/soleur/test/blog-audience-contract.test.ts` → green; specifically: ogImage→
  BlogPosting.image thread, pillar key resolves, FAQ↔JSON-LD parity if a visible FAQ ships,
  distribution channel/section parity + absolute-URL rule, brand-claim bans.
  *(unit/integration)*
- Word count: `awk`/`wc -w` over the body region (exclude frontmatter and the `<script>`
  JSON-LD) lands in [1500, 2000]. *(unit)*
- Mutation-minded spot checks (manual at work time, not new code): deleting the ogImage file
  or the redirect pair must red the corresponding suite — both are already-instrumented
  repo guards, not new machinery.

## Success Metrics

- Post live at `https://soleur.ai/blog/audited-102-guardrails-four-portable/` after the
  next docs deploy; dated-slug URL 301s to it.
- Distribution draft promotable by the existing cron publisher (status flip +
  publish_date) with no further authoring.
- The arc hub visibly links the spoke (second distribution wave per the hub-and-spoke
  design).

## Dependencies & Risks

- **Publish-date assumption.** 2026-10-27 is assumed (first Tue–Thu day inside the arc's
  publish week, after the arc post is live). Recorded in decision-challenges as an
  operator-schedule item; coherent-renaming rule is AC11.
- **Gemini image generation unavailable** — Pillow fallback is planned; quality bar matched
  to #10939's shipped card.
- **Arc post edit scope.** Editing a published post is a facts-only refresh (one link
  sentence); the Blog note permits fact updates and pins title/slug/H1/meta.
- **Census-number ambiguity risk** is retired by the dated-census framing (102 at
  2026-10-21); the Draft Spec pins the sentence shapes.
- **HN submission** stays conditional on the fortnight slot and submits the technical
  write-up — no action in this PR beyond noting it.

## References & Research

- Issue: #10903 (this brief), #10404 (closed), #10902 (arc), #10904 (sibling), #10759
  (review findings, closed), #10940 (GEMINI rotation — OG fallback reason).
- PRs: #10744 (merged — the shipped feature), #10922 (arc post + distribution precedent),
  #10939 (OG image via Pillow precedent).
- Source docs: `plugins/soleur/skills/verification-scaffold/SKILL.md`,
  `plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md`,
  `plugins/soleur/skills/verification-scaffold/references/guards.tsv`,
  `knowledge-base/project/learnings/2026-10-21-one-regen-gap-three-committed-state-reds.md`,
  `knowledge-base/marketing/brand-guide.md` (### Blog),
  `plugins/soleur/skills/content-writer/SKILL.md`.
- Workflow refs: `.github/workflows/apply-web-platform-infra.yml` (push-triggered apply),
  `.github/workflows/deploy-docs.yml` (docs publish).

### Sharp-edge note

A plan whose `## User-Brand Impact` section is empty or placeholder-only fails deepen-plan
Phase 4.6; it is filled above. Commands prescribed in Test Scenarios were executed once
during planning where their green state is pre-change-independent (jargon scan on the arc
post rc 0; tweet-draft validator on a draft file rc 0; the redirect grep prints `0`
pre-change by construction and `1` post-change).

## Enhancement Summary

Deepen-plan pass applied inline (no Task/Agent tool in this subagent context — the
per-section research and review fan-outs were substituted by direct reads of every cited
source and mechanical runs of every gate that has a script):

- **4.6 User-Brand Impact** — section present, threshold `aggregate pattern`, concrete
  artifact + exposure lines. PASS.
- **4.7 Observability** — triggered by the `apps/*/infra/` `.tf` edit; section present with
  all five fields populated; `discoverability_test.command` starts with `grep` (allowlisted),
  no `ssh`, finishes in <1s, `expected_output` is the literal `1`. PASS.
- **4.8 PAT-shaped variable sweep** — zero hits. PASS.
- **4.9 UI-wireframe halt** — no Files-to-Create/Edit path matches the UI-surface glob
  superset (.md/.png/.tf only). SKIP.
- **4.10 Encryption posture** — `.tf` match fires the trigger; section present with full
  at_rest/in_transit fields and no boilerplate ("provider handles it" / "supports TLS"
  absent); no exception needed (no plaintext/no cert-off). PASS.
- **4.11 Guard contract** — deliverable is prose about guards, not a guard; no `lint-*`,
  hook, CI gate, or precondition created (explicitly noted in Technical Considerations to
  disarm the prose keyword hit). SKIP.
- **4.12 Scope check** — exactly one unfenced `## Scope Check`; Ask Mapping 5 rows all
  `mapped`; Provenance inferred rows all carry justifications; `Recommendation: single PR`
  present; no `status: BLOCKED`. PASS.
- **4.4 Precedent-diff** — the only code-shaped change (redirect map append) follows the
  file's own convention; recorded in Technical Considerations.
- **4.45 realism passes** — verify-the-negative: the plan's negative claims ("no force
  flag", "cannot be proven to fire is a document") are claims ABOUT the shipped feature
  restated from the merged SKILL.md/audit doc — verified by direct read, not extrapolated.
- **4.5 network-outage / 4.55 downtime / scheduled-work checks** — no trigger words, no
  downtime-inducing or scheduled-resource change. SKIP.

### Residual findings (no new plan changes)

- `technical-ruling-gate.sh --branch` reports `unruled-technical` on the pending-assumed
  rows in `decision-challenges.md` — the sanctioned state when the Agent tool is absent;
  the parent pipeline/operator resolves them (census figure, pillar membership).
- The audit doc's stale hooks header (56 vs its own 57-row table) is a pre-existing main
  defect, recorded in decision-challenges for a follow-up docs fix — not this content PR.
