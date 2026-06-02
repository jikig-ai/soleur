---
title: "marketing: update all public surfaces for cloud platform positioning"
type: chore
issue: 1051
branch: feat-one-shot-1051-cloud-platform-positioning
lane: single-domain
brand_survival_threshold: aggregate pattern
date: 2026-06-01
owner: CMO
status: planned
---

# 📣 marketing: update all public surfaces for cloud platform positioning

## Enhancement Summary

**Deepened on:** 2026-06-01
**Sections enhanced:** Overview, Research Reconciliation, Research Insights (new), Acceptance Criteria

### Key Improvements

1. **Corrected a false premise** caught by the verify-the-negative pass: the CMO's cited quote
   *does* exist (one non-rendered #1142 spec copy-deck), not "nowhere". The initial grep was
   docs+README-scoped and missed `knowledge-base/project/specs/`. Reconciled in-place.
2. **Grounded every positioning edit in the canonical authority** — `brand-guide.md` Prohibited
   Terms (lines 90/91/96/437). Line 96's three-part exception (CLI commands, legal defined-term,
   technical install docs) independently ratifies this plan's Non-Goals.
3. **Sharpened the M3 AC** — "terminal-first" must be reframed at *two* strategy sites
   (`:78` Moat, `:387` advocacy), not one; the rationale review-note may remain.

### New Considerations Discovered

- Prohibited-terms list extends beyond "plugin" ("copilot", "assistant", "terminal-first",
  "AI-powered", "just", "simply") — implementer must not introduce these while rewriting.
- All three deepen-plan gates pass: 4.6 User-Brand Impact (threshold `aggregate pattern`),
  4.7 Observability (correct skip — no code-class paths; `skills.js` is build-data not a
  `plugins/*/scripts/` runtime surface), 4.8 no PAT-shaped variables.

## Overview

Issue #1051 (Pre-Phase 4 Marketing Positioning Gate, CMO review) asserts that every public
surface says "Claude Code plugin" while the roadmap positions Soleur as a cross-platform cloud
service, and that recruiting beta founders must not begin until the contradiction is resolved.

**Premise validation changed the shape of this work substantially.** Most of the homepage,
brand guide, marketing strategy, and `llms.txt` have *already* been migrated to
Company-as-a-Service platform positioning (the homepage hero, getting-started hero, and
`about.njk` carry a `2026-06-01` `last_updated`; the brand guide already states "We lead with
the ambitious platform vision, never the plugin description"). The CMO's cited quote
("orchestrated from a single Claude Code plugin") exists in exactly **one** place —
`knowledge-base/project/specs/feat-website-conversion-review/copy-deck.md:43`, a non-rendered
2026-03-26 spec draft (issue #1142) — and on **zero live public surfaces**. This is therefore a
**residual-cleanup + consistency** task, not a from-scratch pivot.

The genuine remaining work is:
1. A handful of surfaces that still *lead* with plugin framing where they should lead with the
   platform (e.g. `about.njk` "launched as a plugin", `community.njk` "is an open-source Claude
   Code plugin", `plugins/soleur/README.md`).
2. Count/term consistency cleanup (one stale `74 skills` comment; verify the auto-synced README
   exact counts; confirm prose soft-floors are uniform).
3. Marketing-strategy edits the strategy doc *itself* already flags as outstanding (remove
   "terminal-first workflow" qualifiers, refresh the plugin-registry channel lines, update the
   self-reported "What Is Broken" status row).

**What this plan deliberately does NOT do** (see Non-Goals): rewrite the SEO/AEO *pillar* pages
whose subject matter *is* "Claude Code plugin" (`claude-code-plugins.njk`, `glossary.njk`,
`company-as-a-service.njk`, `agentic-engineering.njk`); remove `claude plugin install soleur`
install commands (the correct, verified CLI form for the open-source path); or edit legal docs
that use "the Plugin" as a defined legal term.

## Research Reconciliation — Spec vs. Codebase

| Issue/spec claim | Codebase reality (verified 2026-06-01) | Plan response |
|---|---|---|
| "Every public surface says 'Claude Code plugin'" | Homepage hero, getting-started hero, `llms.txt`, brand guide, pricing all already lead with "Company-as-a-Service platform". Plugin framing survives only on a minority of surfaces. | Scope to the residual surfaces (M1/M2 mostly already done — verify-and-close; M5 partly done). |
| CMO quote: "orchestrated from a single Claude Code plugin" | Repo-wide `grep` finds it in exactly ONE non-rendered spec draft (`knowledge-base/project/specs/feat-website-conversion-review/copy-deck.md:43`, issue #1142, 2026-03-26); **zero** live public surfaces. [Corrected during deepen-plan — initial plan grep was scoped to `docs`+README and missed the spec dir.] | Do not chase the literal quote on live surfaces (none exist); treat it as illustrative of the *class* (lead-with-plugin) and fix the real lead-with-plugin surfaces. The stale copy-deck is a #1142 spec artifact, not this issue's surface — out of scope. |
| M6: "agent/skill counts: 4 different numbers" | README `67/82/3` (exact, **auto-synced & currently correct** via `scripts/sync-readme-counts.sh`); prose `60+ agents / 60+ skills` (soft floors, correct per content-plan SF-10); `skills.js:11` comment `74 skills` (**stale**); blog posts `63`/`65+` agents (allowlisted historical, frozen — OK). | Fix only the genuinely stale `skills.js` comment + run the canonical count-propagation grep. Do NOT replace soft floors with exact counts (would re-introduce drift and fail `marketing-content-drift.test.ts`). |
| M2: "Update homepage hero subtitle + meta description" | `index.njk` hero subtitle + `description` frontmatter already CaaS-platform-positioned, dated 2026-06-01. | Verify-and-close; no edit expected unless residual "plugin" found. |
| M1: "Update brand guide positioning paragraph (remove plugin framing)" | `brand-guide.md` Positioning already says "never the plugin description"; carries the 2026-03-22 Business Validation Review notes prescribing exactly this pivot. | Verify-and-close; confirm no plugin-led prose remains in Identity/Positioning/Voice. |
| M3: "Update marketing strategy for cloud pivot" | `marketing-strategy.md` self-documents the outstanding edits: line 58 "Plugin still appears…", line 78 "terminal-first workflow qualifier should be removed", lines 144/204-205/337 plugin-registry channel assumptions. | Real work: apply the strategy doc's own prescribed rewrites. |
| M4: "Draft recruitment messaging templates per channel" | **Separate open issue #1445 (M4)** owns this; roadmap row maps `#1051 = M3 only`. `validation-outreach-template.md` already exists (problem-interview outreach). | Coordinate, do not double-build. Recommend M4 be executed under #1445; this plan references it (no new deferral issue needed — #1445 already tracks it). See "Open Questions". |
| M5: "Getting Started page (cloud primary, CLI secondary)" | `getting-started.njk` already structures cloud-hosted as primary CTA ("Reserve access") and self-hosted as a `#self-hosted` secondary section, dated 2026-06-01. | Verify-and-close; minor copy polish only if a plugin-led line remains. |

## User-Brand Impact

**If this lands broken, the user experiences:** a recruited founder lands on a public surface
(About page, community page, plugin README) that pitches a "Claude Code plugin" instead of the
cloud platform they were recruited for, undercutting the pitch — OR inconsistent agent/skill
counts across surfaces that read as carelessness.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is
public-facing marketing copy only. No user data, auth, secrets, or money-handling surface is
touched.

**Brand-survival threshold:** `aggregate pattern` — a single residual "plugin" line is
cosmetic; the brand risk is the *aggregate* of inconsistent positioning across many surfaces at
once during recruitment. No per-PR CPO sign-off required; the section is present per the gate.

## Premise Validation

Checked all referenced premises: issue #1051 is OPEN (not already closed by a merged PR);
sibling issue #1445 (M4 recruitment templates) is OPEN; roadmap row 78 + line 239 authoritatively
scope `#1051 = M3`. Cited file/symbol paths verified to exist: `knowledge-base/marketing/brand-guide.md`,
`marketing-strategy.md`, `plugins/soleur/docs/index.njk`, `getting-started.njk`, `about.njk`,
`community.njk`, `README.md`, `scripts/sync-readme-counts.sh`,
`plugins/soleur/docs/_data/skills.js`, `plugins/soleur/test/marketing-content-drift.test.ts`.
**Stale premise found:** the CMO's literal quote does not exist and ~M1/M2/M5 are largely
already complete — surfaced in Research Reconciliation rather than planned against as-if-greenfield.

## Research Insights

**Canonical authority for the "lead-with-platform, plugin-secondary" rule** — `knowledge-base/marketing/brand-guide.md` Prohibited Terms (the load-bearing source; all M1-M3/M5 edits trace to it):

- **Line 96** — "Call it a 'plugin' or 'tool' in public-facing content -- it is a platform.
  **Exception:** 'plugin' is permitted in (a) literal CLI commands (`claude plugin install`),
  (b) legal documents where 'Plugin' is a defined term, (c) technical documentation describing
  the installation mechanism." → This *exactly* ratifies this plan's Non-Goals. The pillar/SEO
  pages, install commands, and legal docs are explicitly exception-permitted; touching them
  would violate the brand guide's own carve-out, not enforce it.
- **Line 90** — "Say 'assistant' or 'copilot' -- Soleur is an organization, not a helper" (avoid).
- **Line 91** — "Say 'terminal-first' or 'CLI-native' as a positioning advantage -- the delivery
  pivot requires device-agnostic language [added 2026-03-22, per business validation]" (avoid).
  → This is the canonical backing for the M3 `marketing-strategy.md` "terminal-first" removal
  (strategy line 78 / 387). Confirmed: "terminal-first" appears at `marketing-strategy.md:72`
  (review note — leave), `:78` (Moat #1 prose — **remove qualifier**), `:387` ("emphasize
  terminal-first vs workspace-first" — **reframe**, this is now a prohibited positioning advantage).
- **Line 437** — "the website CTA must shift from plugin installation to platform signup/login …
  Do not reference CLI installation as the primary CTA." → Already satisfied on
  `getting-started.njk` (primary CTA = "Reserve access"; self-host secondary). Verify-and-close.

**Verify-the-negative pass results (deepen-plan Phase 4.45):**

- "CMO quote does not exist" → **CONTRADICTED then corrected**: it exists in one non-rendered
  spec draft (see Research Reconciliation). Reconciled above.
- "lead-with-plugin lines exist on about.njk:51 + community.njk:47" → **CONFIRMED** (grep hits).
- "terminal-first exists in marketing-strategy" → **CONFIRMED** (`:78`, `:387`).
- "README counts in sync via script" → **CONFIRMED** (`sync-readme-counts.sh --check` exit 0;
  `67 agents, 3 commands, 82 skills`).
- "skills.js:11 comment stale (74 vs live 82)" → **CONFIRMED** (comment says 74; live = 82).

**Edge case discovered:** the prohibited-terms list also flags "AI-powered", "just", "simply",
"disrupt", "synergy" (per the #1142 copy-deck, mirroring brand-guide voice). Out of scope for
#1051 (plugin/cloud positioning), but the implementer should not *introduce* any of these while
rewriting — keep edits to platform-first phrasing without reaching for prohibited filler.

## Implementation Phases

> Each editing phase is a content edit. Order: low-risk verify-and-close first (M1/M2/M5),
> then the substantive strategy rewrite (M3), then consistency cleanup (M6). No phase has a
> code-contract dependency on another, so order is by risk, not by data flow.

### Phase 1 — M1/M2/M5 verify-and-close

For each of `brand-guide.md` (Identity/Positioning/Voice), `index.njk` (hero subtitle +
`description` frontmatter), `getting-started.njk` (hero + section ordering):

1. Re-grep each for any *lead-with-plugin* prose (`grep -niE "\bplugin\b" <file>`).
2. If a line *leads* with plugin framing as the primary identity, rewrite it platform-first
   (keep any factually-correct secondary "open-source, runs in Claude Code today" mention).
3. If no lead-with-plugin prose remains, record "verified — already platform-positioned
   (2026-06-01)" in the PR body; do **not** make cosmetic edits for the sake of a diff.

**Expected outcome:** likely zero or near-zero edits; the value is the documented verification.

### Phase 2 — M3 marketing-strategy rewrite (`knowledge-base/marketing/marketing-strategy.md`)

Apply the edits the strategy doc already prescribes for itself:

- **Line ~58** ("What Is Broken or Missing" → "Plugin still appears in homepage hero subtitle,
  FAQ texts, llms.txt, Getting Started meta description"): update to reflect current reality
  (hero + llms.txt + meta already fixed); narrow the open item to the genuine residual surfaces
  this PR addresses, or mark resolved.
- **Line ~78** (Moat #1): remove the "within a terminal-first workflow" qualifier per the
  2026-03-22 review note; the compounding-KB moat is delivery-agnostic.
- **Lines ~144 / ~204-205 / ~337** (channel strategy: "GitHub plugin discovery", "Optimize
  Claude Code plugin registry listing", "Plugin installs 50+" metric): reframe as
  *open-source / self-hosted acquisition channel feeding the cloud waitlist*, not the primary
  conversion surface. Keep plugin-registry as a P2 technical-discovery channel (it is real),
  but the primary funnel is cloud signup/waitlist.
- Bump `last_updated` / `last_reviewed` frontmatter to 2026-06-01.

### Phase 3 — M1 lead-with-platform residual surfaces

Rewrite the surfaces that still *lead* with plugin identity:

- `plugins/soleur/docs/pages/about.njk:33` — "The platform launched as an open-source Claude
  Code plugin and has grown to…" → lead with platform, keep launch-origin as secondary clause.
- `plugins/soleur/docs/pages/about.njk:51` — "Soleur is an open-source Claude Code plugin that
  turns a solo founder into a full AI organization. The cloud platform is in development." →
  lead with the Company-as-a-Service platform; self-host/open-source as the secondary access path.
- `plugins/soleur/docs/pages/community.njk:47` — "Soleur is an open-source Claude Code plugin
  with an active community…" → platform-first phrasing (community para can still note it is
  open source and built as a Claude Code plugin further down at line 104, which is a
  factual build-detail, not the lede).
- `README.md` "## What is Soleur?" + intro — already platform-first ("The Company-as-a-Service
  platform"); the installation section's `claude plugin install` commands stay (correct CLI).
  Verify the lede leads with platform; minimal/no change expected.
- `plugins/soleur/README.md` — plugin-developer-facing; leave install-centric framing but
  confirm the top-line description matches `plugin.json` ("A full AI organization…"). Low
  priority; this is the component-reference README, not a recruitment surface.

For each: keep the secondary, factually-correct "open source, runs in Claude Code" mention —
do not erase the delivery truth, just stop leading with it.

### Phase 4 — M6 count/term consistency

1. Fix the one genuinely stale comment: `plugins/soleur/docs/_data/skills.js:11`
   `// Last verified: 2026-05-21 (4 categories, 74 skills)` → update to current
   (`82 skills` as of 2026-06-01; the count is computed at build time, the comment is just a
   note). Re-verify the live count at edit time: `find plugins/soleur/skills -maxdepth 2 -name SKILL.md | wc -l`.
2. Run the canonical count-propagation grep (from learning
   `2026-02-22-skill-count-propagation-locations.md`) to confirm no other stale exact counts:
   ```bash
   grep -rn '\b[0-9]\+ \(agents\?\|skills\?\)\b' . --include='*.md' --include='*.js' --include='*.json' \
     | grep -vE 'node_modules|CHANGELOG|knowledge-base/project/(plans|specs|learnings)|knowledge-base/marketing/(audits|distribution-content|copy)|/blog/'
   ```
3. Confirm README exact counts (`67 agents / 82 skills / 3 commands`) are current by running
   `bash scripts/sync-readme-counts.sh --check` (exit 0 = in sync). Do **not** hand-edit
   README counts — the script owns them.
4. Confirm `marketing-content-drift.test.ts` Test 1 passes (no bare exact counts in the
   `59|61|62|63|65|66|67 agents/skills` window in swept prose) — this is the regression guard
   for M6.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Zero *lead-with-plugin* prose in primary positioning surfaces: `index.njk` hero,
      `brand-guide.md` Positioning, `about.njk` (lines 33 + 51), `community.njk:47`,
      README "What is Soleur?". (Secondary "open source / runs in Claude Code" mentions are
      permitted.) Verify: `grep -niE "is (an? )?(open-source )?claude code plugin" plugins/soleur/docs/pages/about.njk plugins/soleur/docs/pages/community.njk` returns no *lede* hits.
- [ ] `marketing-strategy.md`: "terminal-first" removed/reframed as a *positioning advantage*
      per brand-guide line 91 — at line ~78 (Moat #1 qualifier) and line ~387 ("emphasize
      terminal-first vs workspace-first"). The 2026-03-22 review *note* at line ~72 that
      explains the change may remain (it documents the rationale). Verify:
      `grep -n "terminal-first" knowledge-base/marketing/marketing-strategy.md` shows no
      *advocacy* of terminal-first as a differentiator (review-note mentions OK). Channel/metric
      lines (plugin registry, lines ~144/204-205/337) reframed as self-host→waitlist funnel;
      `last_updated: 2026-06-01`.
- [ ] `plugins/soleur/docs/_data/skills.js:11` comment count matches the live SKILL.md count.
- [ ] `bash scripts/sync-readme-counts.sh --check` exits 0 (README counts in sync).
- [ ] `bun test plugins/soleur/test/marketing-content-drift.test.ts` passes (or the project's
      `package.json scripts.test` runner equivalent — confirm runner before invoking).
- [ ] Eleventy build succeeds: `npm run docs:build` exits 0 (catches `.njk` syntax / JSON-LD
      breakage on edited pages).
- [ ] PR body documents the verify-and-close findings for M1/M2/M5 (which surfaces were already
      compliant) so the CMO gate reviewer can confirm coverage.
- [ ] PR body uses `Ref #1051` and `Ref #1445` (M4 coordination); does not `Closes #1051`
      unless M3 is fully satisfied here (it is, so `Closes #1051` is acceptable — M4 lives under #1445).

### Post-merge (operator)

- [ ] None. All verification is automatable via the test suite + Eleventy build in CI. No
      external-service state, deploy step, or manual browser action required.

## Domain Review

**Domains relevant:** Marketing (Product advisory)

### Marketing (CMO)

**Status:** reviewed (carry-forward — issue #1051 is itself a CMO-review artifact; brand-guide
and marketing-strategy already encode the 2026-03-22 Business Validation Review pivot direction)
**Assessment:** The pivot direction (platform-first, plugin-secondary, delivery-agnostic moat
framing) is already CMO-ratified in `brand-guide.md` and `marketing-strategy.md`. This plan
applies the residual edits those documents already prescribe. No new positioning *decision* is
made — only execution of an existing CMO-approved direction. Recommend no separate domain-leader
spawn; if the one-shot pipeline runs domain leaders, the CMO assessment is "execute as planned".

### Product/UX Gate

**Tier:** none
**Rationale:** No new user-facing pages, flows, or components. All changes are prose edits to
existing pages and knowledge-base docs. `index.njk` / `getting-started.njk` edits (if any) are
copy-only, not new interactive surfaces. Mechanical escalation does not fire — no new files
matching `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`.

## Observability

Skip — pure content/docs change. No Files-to-Edit under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/`, or `plugins/*/scripts/` (the one `.js` edit is a build-time data comment, not a
runtime code surface; the `sync-readme-counts.sh` invocation is read-only `--check`). The
regression surface is covered by `marketing-content-drift.test.ts` + the Eleventy build gate,
both of which run in CI with no SSH.

## Infrastructure (IaC)

Skip — no new infrastructure (server, service, cron, vendor account, DNS, cert, secret,
firewall rule, or persistent runtime process) is introduced. Pure content edits against an
already-provisioned static-docs surface.

## Files to Edit

- `knowledge-base/marketing/marketing-strategy.md` — M3 rewrites (moat qualifier, channel
  lines, status row, frontmatter date). **Substantive.**
- `plugins/soleur/docs/pages/about.njk` — lines 33 + 51, lead-with-platform. **Substantive.**
- `plugins/soleur/docs/pages/community.njk` — line 47, lead-with-platform. **Substantive.**
- `plugins/soleur/docs/_data/skills.js` — line 11 stale count comment. **Trivial.**
- `knowledge-base/marketing/brand-guide.md` — verify-and-close (likely no edit; bump
  `last_reviewed` to 2026-06-01 to record the review). **Verify.**
- `plugins/soleur/docs/index.njk` — verify-and-close (likely no edit). **Verify.**
- `plugins/soleur/docs/pages/getting-started.njk` — verify-and-close (likely no edit). **Verify.**
- `README.md` — verify lede leads with platform (likely no edit; counts script-owned). **Verify.**
- `plugins/soleur/README.md` — verify top-line matches `plugin.json` (low priority). **Verify.**

## Files to Create

- None.

## Open Code-Review Overlap

None. Queried 74 open `code-review`-labelled issues; zero reference any file in this plan's
Files-to-Edit list.

## Non-Goals / Out of Scope

- **SEO/AEO pillar pages whose subject IS "Claude Code plugin"** — `claude-code-plugins.njk`,
  `glossary.njk` (the "Claude Code Plugin" defined term), `company-as-a-service.njk`,
  `agentic-engineering.njk`, and the `best-claude-code-plugins-2026` / `plugin-vs-skill-vs-mcp`
  blog posts. These intentionally use "plugin" as their ranking topic. Editing them would harm
  AEO/SEO coverage and is not "primary positioning". (No deferral issue needed — these are
  permanent by design, not deferred work.)
- **`claude plugin install soleur` install commands** across pages — the correct, CLI-verified
  open-source install path. Keep verbatim (`<!-- verified: 2026-04-19 source: https://code.claude.com/docs/en/plugins -->` already present in getting-started).
- **Legal docs** (`terms-and-conditions.md`, `gdpr-policy.md`, `cookie-policy.md`) — use "the
  Plugin" as a *defined legal term* alongside "the Web Platform". Changing legal definitions is
  a CLO-domain change with its own review path; out of scope for a marketing-positioning PR.
- **M4 recruitment messaging templates** — owned by **open issue #1445** (already tracked; no
  new deferral issue required). This plan coordinates with it but does not author the templates,
  to avoid double-work. If the one-shot pipeline owner wants M4 folded in here, that is a scope
  decision to confirm with the user (see Open Questions).
- **Replacing prose soft-floors (`60+ agents`) with exact counts** — would re-introduce the
  drift `marketing-content-drift.test.ts` guards against. Soft floors are the correct pattern.

## Open Questions

1. **M4 scope:** the issue body lists M4 (recruitment templates) but the roadmap maps
   `#1051 = M3` and a dedicated issue #1445 owns M4. Default: execute M1-M3/M5/M6 here, leave M4
   to #1445. Confirm if the pipeline should instead fold M4 into this PR.

## Test Scenarios

- **Count consistency:** `bun test plugins/soleur/test/marketing-content-drift.test.ts` Test 1
  passes (no stale exact counts in swept prose); `scripts/sync-readme-counts.sh --check` exits 0.
- **Build integrity:** `npm run docs:build` exits 0 after `.njk` edits (no Nunjucks/JSON-LD
  breakage on `about.njk` / `community.njk`).
- **No-plugin-lede grep:** the AC grep commands return no lede hits on the edited primary surfaces.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled above
  (threshold: `aggregate pattern`).
- **Do not hand-edit README component counts** — `scripts/sync-readme-counts.sh` owns them and a
  CI `--check` will flag drift. Use the script.
- **Do not replace prose `60+` soft floors with exact counts** — `marketing-content-drift.test.ts`
  Test 1 rejects bare exact counts in the `59|61|62|63|65|66|67 agents/skills` window. The blog
  posts using `63`/`65+` agents are allowlisted historical files; leave them frozen.
- **Resist editing pillar/SEO pages** — they rank on "Claude Code plugin"; touching them trades
  the (already-done) positioning win for an AEO loss.
- Confirm the test runner before invoking an AC test command (`package.json scripts.test`);
  this repo uses `bun test` for `.test.ts` and `bash` for `.test.sh` — do not assume.
