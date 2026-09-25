---
title: "marketing(brand-guide): blog posts target non-technical solo founders — problem-first, not mechanism-first"
date: 2026-09-25
slug: chore-blog-posts-target-non-technical-founders
branch: feat-one-shot-8774-blog-founder-audience
issue: 8774
closes: 8774
type: chore
priority: p2-medium
domain: marketing
brand_survival_threshold: none
lane: cross-domain
---

# Blog posts target non-technical solo founders

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The founder turned down a blog draft (#8548, PR #8649 closed unmerged) because it was written for engineers. The brand guide currently sends blog posts to technical builders and has no blog channel note, and the article-drafting skill defaults blog posts to the technical register. This plan changes the brand guide so the blog's reader is the non-technical solo founder, adds a blog channel note, and wires the drafting pipeline to apply it.

## Research Insights

### Premise Validation (Phase 0.6)

- #8774 is OPEN (labels `domain/marketing`, `type/chore`, `priority/p2-medium`, milestone `Post-MVP / Later`). Nothing has resolved it.
- #8548 is OPEN and blocked by #8774. The founder's comment of 2026-09-24 gives two options: re-angle the post for founders ("I lose track of what I decided and what I just forgot") or replace it.
- PR #8649 is CLOSED with `mergedAt: null` (closed 2026-09-24T20:26Z). Its branch `origin/feat-content-8548-roadmap-undecided-vs-forgotten` exists and touches three files: `plugins/soleur/docs/blog/2026-09-24-roadmap-undecided-vs-forgotten.md` (136 lines), `knowledge-base/marketing/distribution-content/2026-09-24-roadmap-undecided-vs-forgotten.md` (25 lines), and one line in `apps/web-platform/infra/seo-bulk-redirects.tf` (the dated-slug redirect entry).
- Claims in the issue, checked against the files:
  - `knowledge-base/marketing/brand-guide.md` `### Who Is Soleur For?` sends "technical blog posts" to the *Technical builders* row. **Holds.**
  - There is no `### Blog` under `## Channel Notes`. **Holds.** The existing subsections are Discord, GitHub, X/Twitter, LinkedIn Personal, LinkedIn Company Page, Bluesky, Hacker News, and Website / Landing Page.
  - A second routing site the issue does not name: `### Audience Voice Profiles` says the Technical register is the default for "HN, GitHub, Discord, technical blog posts". It gets the same fix.
  - `plugins/soleur/skills/content-writer/SKILL.md` Phase 2 step 2 already reads `## Channel Notes > ### Blog` "if the section exists". Its Important Guidelines fall back silently to `## Voice` when the section is missing. So the reading is already wired, and today it reads nothing. **The live defect is the default:** Phase 1 `--audience` says "Defaults to channel-appropriate (blog → technical, …)", and Phase 2 step 4 says "blog posts default to `technical`".
- ADR corpus: grepped `knowledge-base/engineering/architecture/decisions/` for `content-writer|brand-guide|audience register|blog audience`. There were 3 hits (ADR-013, ADR-086, ADR-126). None decides or rejects anything about the blog audience or the content-writer default. ADR-086 names `brand-guide.md` only as the pilot artifact for `context_queries`, which is a way of loading files, not a rule about audience.

### Property List (Phase 0.6b)

- **P1**: An agent or person reading the brand guide learns that the blog's reader is the non-technical solo founder, and that technical write-ups go elsewhere (docs, GitHub, HN).
- **P2**: The brand guide has one place, `### Blog`, that says how a blog post is framed: who the reader is, that it opens with the founder's problem, the jargon limits, where technical detail goes, and a check to run before drafting.
- **P3**: A blog draft from `soleur:content-writer` follows P2 by default. This covers an interactive run with no `--audience` and the headless cron run in `apps/web-platform/server/inngest/functions/cron-content-generator.ts`, which calls `/soleur:content-writer <topic> --headless` with no `--audience`.
- **P4**: A content brief for a blog post, which is where an angle is born, is written against P2. #8548's mechanism-first angle came from a brief filed by `soleur:ship` Phase 5.5's CMO Content-Opportunity Gate for PR #8536.
- **P5**: #8548 can be picked up right after this lands, and drafted against the merged guide with a recommended angle already on the issue.

### Cut List (Phase 0.6b)

- A **new deterministic CI lint over `plugins/soleur/docs/blog/*.md`** for jargon (P3). Cut. Six of the recent posts are mechanism-first or technical by design (see the classification below), so a repo-wide lint needs a date-cutoff exemption on day one. A new-posts-only lint also duplicates the in-skill scan. The skill scan (content-writer Phase 2.4 below) is the one place every draft passes through, including the cron.
- A **`--audience` flag in the cron prompt** (`cron-content-generator.ts`), for P3. Cut. Changing the skill's default covers the headless path without touching server code, the prompt-canary test (`apps/web-platform/test/server/inngest/cron-content-generator.test.ts`), or the observability gate.
- **`context_queries:` frontmatter on content-writer** (ADR-086), for P3. Cut. content-writer already reads the brand guide in Phase 0 and Phase 2. A pointer injection adds nothing.
- A **new "blog audience" section in the CMO agent** (`plugins/soleur/agents/marketing/cmo.md`), for P4. Cut. The brief that produced #8548 is the ship Phase 5.5 prompt, so a one-sentence edit there covers P4. The CMO agent already reads the brand guide's Voice and Identity (`cmo.md` line 18). Once the Target Audience table changes, that read carries the new routing.
- **Rewriting existing technical blog posts.** Cut. The note applies to new drafts. Refreshing or retiring old posts is a separate SEO decision. See Non-Goals.
- **Plan-review cuts:**
  - content-writer Phase 1.5 and slug-based refresh detection;
  - A5, the CaaS sentence;
  - the `soleur:` scan pattern;
  - the Guard 1 table parse;
  - the #8548 row annotations.
  See [Plan Review Revisions](#plan-review-revisions).

### Relevant files (verified on this branch)

- `knowledge-base/marketing/brand-guide.md`, 488 lines, `last_updated: 2026-05-05`. Sections: `### Target Audience`, `### Who Is Soleur For?`, `### Audience Voice Profiles`, `## Channel Notes` (ends with `### Website / Landing Page`).
- `plugins/soleur/skills/content-writer/SKILL.md`, 14,024 bytes. The routing lives in the Phase 1 `--audience` bullet, Phase 2 step 2 (`### Blog` read), Phase 2 step 4 (the default), and the Important Guidelines bullet "If the brand guide's `## Channel Notes > ### Blog` section is missing…".
- `plugins/soleur/skills/ship/SKILL.md` §CMO Content-Opportunity Gate, prompt item 1. It is 270,963 bytes against a **274,000-byte ceiling** in `plugins/soleur/test/skill-body-budget.json`. That ceiling is enforced by `scripts/lint-skill-body-budget.py` against the merge base (lefthook `skill-body-budget-lint` plus the CI `rule-body-lint` job). **Headroom is 3,037 bytes**, so keep the ship edit at or under 400 bytes. content-writer is not in the ceiling set.
- `apps/web-platform/server/inngest/functions/cron-content-generator.ts` `CONTENT_GENERATOR_PROMPT` STEP 2 runs `/soleur:content-writer <topic> --headless` (no `--audience`), and only handles "aborts due to FAIL citations". **A new content-writer abort path would be unhandled in the cron**, so the headless audience check must re-angle and never abort.
- `knowledge-base/overview/vision.md` `### Primary: Technical Builders (Beachhead)`: `**Channels:** Hacker News, GitHub, Discord, technical blog posts`. This is the same routing claim in a sibling document.
- `knowledge-base/marketing/content-strategy.md`: Pillar 2 `**Audience:** Technical builders looking for structured AI development workflows.`, the Pillar 2 table row for #8548 ("Audience: solo founders and technical PMs who plan in GitHub Issues"), and the calendar row "Within 2 weeks of PR #8536 merging".
- `apps/web-platform/test/server/inngest/cron-weekly-release-digest.test.ts` "RELEASE_DIGEST_RULES brand-guide lockstep" slices `#### Release Digest` up to the next `\n#`. A new `### Blog` placed **after** `### Website / Landing Page` does not touch that slice. Do not edit `#### Release Digest`.
- Precedent for a bun test that guards a knowledge-base document contract: `plugins/soleur/test/distribution-content-format.test.ts`.

### Blog corpus today (repo-research sample of recent posts)

Seven are founder-problem-first: the five case studies, `why-most-agentic-tools-plateau`, and `best-ai-tools-for-solo-founders-2026`. Three are mechanism-first: `claude-code-plugin-vs-skill-vs-mcp`, `skill-libraries-vs-workflow-plugins`, and `loop-engineering-for-your-whole-company`. So the rule mostly formalizes existing practice. The #8548 draft (a CLI command in the CTA, `gh --limit`, issue numbers, and a mattpocock audit bundle list) is the outlier the founder rejected.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-02-12-brand-guide-contract-and-inline-validation.md`: brand-guide headings are a contract that downstream skills read by name, and a skill checking its own draft against the guide beats a separate reviewer. This is why the note is named exactly `### Blog`, the heading content-writer already reads, and why the jargon scan lives inside content-writer.
- `knowledge-base/project/learnings/2026-02-21-marketing-audit-brand-violation-cascade.md`: grep a brand rule across the whole repo before fixing it. Done: the routing claim appears in the brand guide (two places), `vision.md`, and `content-strategy.md`. Audit files under `knowledge-base/marketing/audits/` are dated snapshots and are not edited.
- `knowledge-base/project/learnings/2026-03-16-scheduled-skill-wrapping-pattern.md`: headless mode resolves interactive gates automatically. It must never introduce an abort the caller does not handle.
- The 2026-03-29 brainstorm (`knowledge-base/project/brainstorms/2026-03-29-non-technical-founder-voice-brainstorm.md`, #1004) created the two registers and `--audience`, and routed the blog to technical. This plan reverses that one routing decision on the founder's direction. The two registers themselves stay.

### Functional overlap (Phase 1.5b)

functional-discovery searched 3 registries and installed nothing. It found no meaningful overlap. The closest were generic brand-voice and blog-SEO plugins (anthropics/knowledge-work-plugins `brand-voice`, `claude-blog`, `ai-copywriter`), and none of them applies a channel-level audience rule inside an existing drafting skill. Community discovery (Phase 1.5) was skipped because no uncovered stack was detected.

### External research decision (Phase 1.6)

Skipped. This is a brand-voice decision the founder already made, and the codebase has strong local precedent (two registers, a Channel Notes contract, content-writer phases). There is no security, payments, or external API surface.

### CLAUDE.md / AGENTS.md conventions in play

- `hr-weigh-every-decision-against-target-user-impact`: the target user here is the reader of the blog.
- `cq-cite-content-anchor-not-line-number` and `cq-assert-anchor-not-bare-token`: the new test anchors on headings, not on line numbers or bare tokens.
- `wg-use-closes-n-in-pr-body-not-title-to`: the PR body carries `Closes #8774` and `Ref #8548`. It must not say `Closes #8548`.
- `wg-when-deferring-a-capability-create-a`: the #8548 rework is not deferred-without-tracking. #8548 is already an open issue and is the tracker.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "Check whether `soleur:content-writer` and its brief template read the brand guide's audience fields." | content-writer already reads `## Channel Notes > ### Blog` when it exists (Phase 2 step 2). It reads `### Audience Voice Profiles` only when `--audience` is passed (Phase 2 step 4), and it hard-codes "blog → technical" as the default (Phase 1 and Phase 2 step 4). There is no separate brief template. The brief is the free-form CMO output from `soleur:ship` Phase 5.5 (§CMO Content-Opportunity Gate, prompt item 1). | Make the blog default resolve through the `### Blog` note (the prior `technical` default is kept only for brand guides without a note). Always read the voice profiles. Make Phase 2 apply every rule in the note, including its pre-draft check, and add a jargon scan. Add a one-sentence pointer to the ship Phase 5.5 CMO prompt. |
| "Target Audience table (line ~28)." | The table is `### Who Is Soleur For?`, not `### Target Audience`, which is a prose paragraph. The same routing also sits in `### Audience Voice Profiles`, `vision.md`, and content-strategy Pillar 2. | Fix all four places. Leave the `### Target Audience` paragraph and the "beachhead" wording alone. Those are positioning statements, not channel routing. |
| "jargon limits (no CLI flags, API limits or internal skill names in the body)." | Any repo-wide lint would fail on existing posts: the five case studies name agents in backticks, and `why-most-agentic-tools-plateau` has code fences. | The limits apply to new posts. The scan runs inside content-writer on the draft only, and existing posts are grandfathered by the note's `Scope` bullet. |

## Problem Statement

The brand guide tells every agent that blog posts are for technical builders. The one skill that writes blog posts defaults them to the technical register. The ship-time gate that proposes posts builds angles from engineering pull requests. A post drafted today through any of these paths comes out mechanism-first. This happened with #8548: its hook was a `gh issue list` default limit, and its CTA was a terminal command. The founder rejected it because the reader, a non-technical solo entrepreneur, doesn't know the technical parts and doesn't want to care about them. Unless the guide and the pipeline change, the next post repeats the problem. Issue #8774 says to pick this up "before the next blog post is drafted".

## Proposed Solution

This change has four parts:

- edits to three knowledge-base documents: the brand guide, `vision.md` and `content-strategy.md`;
- edits to two skills: content-writer and the one-sentence ship edit;
- one small skill-local script;
- one bun test.

No product or server code changes. Plan review shrank this section (see [Plan Review Revisions](#plan-review-revisions)).

### A. Brand guide: `knowledge-base/marketing/brand-guide.md`

1. **`### Who Is Soleur For?` table.**
   - Technical builders row, channels cell: `HN, GitHub, Discord, technical blog posts` becomes `HN, GitHub, Discord, docs`.
   - Non-technical founders row, channels cell: `Website, LinkedIn, X/Twitter, onboarding content` becomes `Blog, website, LinkedIn, X/Twitter, onboarding content`.
   - Add one sentence under the table: "The blog is written for non-technical founders by default (see `### Blog` under Channel Notes). Technical write-ups live on GitHub or in the docs, not on the blog."
   - The "beachhead audience" wording stays in this PR. The CPO flagged that it is already stale against `business-validation.md`; that point is routed to `decision-challenges.md` (T-3).
2. **`### Audience Voice Profiles`.**
   - `**Technical register** (default for HN, GitHub, Discord, technical blog posts)` becomes `(default for HN, GitHub, Discord, docs)`.
   - `**General register** (default for website, LinkedIn, X/Twitter, onboarding content)` becomes `(default for the blog, website, LinkedIn, X/Twitter, onboarding content)`.
3. **New `### Blog`** as the last subsection of `## Channel Notes`, after `### Website / Landing Page`. Putting it last keeps the `#### Release Digest` lockstep slice untouched.
   - Put one HTML comment directly above the heading, from the CTO review, so the next editor knows why renaming it reds a test: `<!-- Heading read by name by plugins/soleur/skills/content-writer/SKILL.md; pinned by plugins/soleur/test/blog-audience-contract.test.ts. -->`
   - Use the text under [The `### Blog` note](#the--blog-note-target-text) below.
4. **Frontmatter:** `last_updated: 2026-09-25`. Leave `last_reviewed` alone, since this is not the quarterly review.

**Deliberately left unchanged:**

- `### Target Audience` paragraph, `### Mission`, `**Thesis:**`, the Do's "concrete numbers (60+ agents…)" bullet, and the `**CaaS framing**` paragraph. The note's `Reader` and `Open` bullets already tell blog posts to use the general thesis and "your AI team", and to put the founder's problem first. That is the one place P2 asks for. Positioning prose is out of scope.

### B. `plugins/soleur/skills/content-writer/SKILL.md`

This skill is plugin-generic. Other projects run it against their own brand guides, so it must not hard-code Soleur's audience or jargon list. It applies **whatever the `### Blog` note says**.

**When a brand guide has no `### Blog` note, behavior is unchanged:** the default stays `technical`, and no scan runs.

1. **Phase 1 `--audience` bullet.** Replace "Defaults to channel-appropriate (blog → technical, landing page → general)." with:

   > Blog posts use the register the brand guide's `## Channel Notes > ### Blog` note names. Without a Blog note they default to `technical`, as before. Landing pages and onboarding content default to `general`. An explicit `--audience` is honored as given.

2. **Phase 2.**
   - **Step 2.** Replace "apply blog-specific guidelines (if the section exists)" with "apply every rule in it, including any check it asks for before drafting and any rule for unattended runs (if the section exists)".
     - Soleur's note carries the founder sentence and "in an unattended run, always re-angle; never skip or abort". Phase 2 applies both.
     - The skill gains no new abort path. That matters because the scheduled content generator (`CONTENT_GENERATOR_PROMPT` STEP 2) handles only citation-failure aborts.
   - **Step 4.** Resolve the register first: the flag, else the Phase 1 default, which is the Blog-note register or `technical` without a note. Then always read `### Audience Voice Profiles` for that register. Today the profiles are read only when `--audience` is set. Replace "(blog posts default to `technical`, …)" to match Phase 1.
3. **New `## Phase 2.4: Blog Note Scan`.**
   - **When it runs.** Only when the output is a blog post (the default path, or a `--path` under a `blog/` directory) **and** the `### Blog` note contains the literal label `**Jargon limits.**`. The trigger is deterministic, from the CTO and simplicity reviews. A project whose note sets no jargon limits gets no scan.
   - **Linking.** Link the script from SKILL.md as a markdown link, `[blog-jargon-scan.sh](./scripts/blog-jargon-scan.sh)`, per the plugin's Skill Compliance Checklist.
   - **Temp file.** Write the draft to a `mktemp` file. Never use a literal `/tmp/...` path: `plugins/soleur/test/scratch-path-collision.test.ts` rejects it.
   - **Invocation.** Run `bash "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/content-writer/scripts/blog-jargon-scan.sh" "$DRAFT"`.
     - The `:-plugins/soleur` fallback is from the CTO review. The cron registers the plugin with `--plugin-dir plugins/soleur` from the repo root, and cloud exec shells do not export `CLAUDE_PLUGIN_ROOT`.
   - **Exit 1.** Rewrite each listed line in plain words, or move the detail into the single closing technical link, whose URL carries any number. Re-scan, for at most 2 cycles. For hits left after that:
     - interactive: show them in Phase 3;
     - headless: list them in the Phase 4 report.
   - **Any other non-zero exit** (usage error, script missing, exit 127): warn, list it in the Phase 4 report, and continue. Never block a draft on a broken scan.
4. **Important Guidelines.** Keep the "`### Blog` missing → use `## Voice` only (no error)" bullet. Add: "and keep the `technical` blog default; the scan runs only when the note sets jargon limits."

### C. New `plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh`

A deterministic scan of what a reader sees in a post. That is two things:

- the reader-visible frontmatter values `title:`, `seoTitle:` and `description:`, since the rejected draft carried jargon in its SEO title as well;
- the **body**: everything after the YAML frontmatter and before any `<script type="application/ld+json">` block, so headings and FAQ answers inside `<details>` are included.

All other frontmatter keys (`tags`, `ogImage`, `date`, …) are ignored.

It prints `<line>: <text>` for each line matching any of these:

- a backtick, meaning inline code or a code fence;
- a `--flag` token: two hyphens followed by a letter. A double-hyphen used as a dash is followed by a space and does not match.
- a `#NN` issue or PR number in visible text. A URL path like `/pull/8536` and a markdown heading do not match.

There is **no project-specific name pattern**. An earlier draft matched `soleur:`, but DHH and the CTO cut it: in a plugin-generic script it would impose Soleur's namespace on every project, and backticked names are already caught by the backtick pattern.

Exit codes: `0` for a clean body, `1` for hits, `2` for a usage error (no argument, or a missing or unreadable file).

**Calibration, measured at plan time** with the prototype. The prototype still had the `soleur:` alternative, but no hit below depended on it:

| File | Hits |
|---|---|
| The rejected #8548 draft | 24 |
| `2026-06-15-best-ai-tools-for-solo-founders-2026.md` | 0 |
| The five case studies | 1–4 each |
| `why-most-agentic-tools-plateau.md` | 3 |

Every hit on the case studies is a backticked internal agent name, which the new note forbids anyway.

Candidate implementation. The work phase may tighten it, but the three patterns and the three exit codes are the contract:

```bash
#!/usr/bin/env bash
# blog-jargon-scan.sh <post.md> - flag reader-visible jargon a brand guide's Blog note bans.
set -euo pipefail
[[ $# -eq 1 && -r "$1" ]] || { echo "usage: blog-jargon-scan.sh <post.md>" >&2; exit 2; }
hits=$(awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next}
            fm && /^---[[:space:]]*$/ {fm=0; next}
            fm { if ($0 ~ /^(title|seoTitle|description):/) print NR": "$0; next }
            /<script type="application\/ld\+json">/ {exit}
            {print NR": "$0}' "$1" \
  | grep -E '`|(^|[[:space:](])--[a-z][a-z-]+|(^|[^[:alnum:]&/#])#[0-9]{2,}' || true)
[[ -z "$hits" ]] && exit 0
printf '%s\n' "$hits"; exit 1
```

The script uses only `bash`, POSIX `awk` character classes and `grep -E`, so it runs on macOS as well as Linux (Sharp Edges: portability).

### D. `plugins/soleur/skills/ship/SKILL.md` §CMO Content-Opportunity Gate, prompt item 1

Append this sentence inside the quoted CMO prompt: `For any blog post, apply the brand guide's Channel Notes > Blog note.`

- **Size.** About 70 bytes, against 3,037 bytes of headroom.
- **Why a pointer, not the rules.** The sentence points at the note instead of restating its rules, so the two cannot drift. This answers the simplicity review.
- **Why keep it at all.** The simplicity review asked whether the CMO's own Identity read already covers this. It does not. The CMO agent reads Voice and Identity (`cmo.md` line 18), and neither carries the note's "open with the founder's problem; route mechanism-only stories to GitHub or the changelog" rules. Those live in Channel Notes. This prompt is where #8548's mechanism-first angle was born (P4).

### E. Sibling documents

- **`knowledge-base/overview/vision.md` `### Primary: Technical Builders (Beachhead)`.**
  - `**Channels:** Hacker News, GitHub, Discord, technical blog posts` becomes `Hacker News, GitHub, Discord, docs`.
  - The `### Secondary: Non-Technical Founders` channels become `Blog, website, LinkedIn, X/Twitter, onboarding content`.
- **`knowledge-base/marketing/content-strategy.md` Pillar 2.** Add one dated line under `**Audience:** Technical builders…`, in the file's existing `> **[date …]**` style:

  > **[2026-09-25, #8774]** New blog posts in every pillar follow brand-guide `### Blog`. This pillar's technical depth moves to GitHub and the docs.

  Leave the #8548 table and calendar rows alone. #8548's own PR rewrites them.
- **Bump `last_updated:` on both files.** Check first that each file has the key; `content-strategy.md` has `last_updated: 2026-07-22`.

### F. New `plugins/soleur/test/blog-audience-contract.test.ts`

This bun test runs under `bun test plugins/soleur/`, which `scripts/test-all.sh` already registers.

- **Validators.** They are pure functions over a string, so each runs on the real file and on inline synthesized fixtures.
- **Failure messages.** Every assertion message names the file and heading to edit.
- **Scope.** The suite pins the cross-file heading contract and the scan's three behaviors, and nothing about the note's wording (see [Guard Contract](#guard-contract)).

### The `### Blog` note (target text)

This is the `soleur:marketing:copywriter` correction of the planner's draft, plus the `soleur:marketing:growth-strategist` `Search` bullet and the narrower refresh `Scope` bullet (see Domain Review). The work phase copies it verbatim and may change only wording, not bullets. The labelled bullets are: Reader, founder sentence, Open, Outcome before mechanism, Jargon limits, Proof points, Search, Where technical detail goes, Call to action, Distribution, Scope, plus the example-opening pair.

```markdown
### Blog

The blog is written for the non-technical solo founder. Every post starts from a problem that founder has in running their company and shows what changes once it is solved. How Soleur solves it comes second.

- **Reader.** A solo founder who uses AI tools (ChatGPT, Notion) but does not code. Write in the General register (see `### Audience Voice Profiles`): explain, don't dumb down. Use the general thesis ("Running a company alone shouldn't mean doing everything alone"), not the engineering-problem thesis, and "your AI team" rather than agent or skill counts. A technical founder loses nothing reading the same post; the reverse is not true.
- **Before drafting, write the founder sentence.** Put it in your working notes, not in the post: "A solo founder has this problem: ___. After reading, they can ___." If the sentence needs a technical term, or the problem is ours rather than theirs (a bug we fixed, a tool we built, an audit we ran), re-angle the story to the founder's problem underneath it. Our own story can illustrate that problem, but it is never the subject. In an unattended run, always re-angle; never skip or abort. In an interactive run, the author may instead send the story to GitHub or the changelog.
- **Open with their problem, in their words.** The title, SEO title, meta description and first paragraph name the founder's problem or the outcome, never the mechanism. The founder should recognize their own week in the first two sentences.
- **Outcome before mechanism.** Show what changes for the founder's company: time back, a decision kept, a mistake avoided. Say what the founder still decides and what Soleur does. Then explain the mechanism in plain sentences, only as far as the reader needs to trust the outcome. Section headings follow the same rule.
- **Jargon limits.** Nothing a reader sees (title, headings, body, FAQ answers) contains backticks or inline code, code blocks, terminal commands or flags, file paths, API names or system limits, internal skill, agent or command names (with or without the `soleur:` prefix), or issue or PR numbers (including the `#1234` shorthand). Define any other unavoidable term in the same sentence, using the General-register glossary. Test: a reader who has never opened a terminal can repeat each paragraph back.
- **Proof points.** Use numbers a founder cares about (hours back, departments covered, decisions kept), never engineering metrics (PR, issue, commit or test counts). Use only numbers from a real source you can check; never estimate hours saved. "It was looking at a quarter of our plan" beats "30 of 118 open issues."
- **Search.** Target the words a founder types when they have the problem ("how to handle contracts as a solo founder", "AI to run my marketing"), not developer queries ("Claude Code plugins", "MCP", "agentic engineering"). Comparison posts keep "Soleur vs X" or "X alternative" in the title and meta description, because that is the query, and name the founder's problem in the first paragraph.
- **Where technical detail goes.** The technical half of a story lives on GitHub (the pull request, the architecture decision record, or the README) or in the docs. The post may link it once, at the end, as a full URL behind plain words: "For the technical write-up, see [how we fixed it](<full GitHub URL>)." That URL is the only place a PR or issue number may appear. Do not add an inline technical appendix.
- **Call to action.** One next step a non-technical founder can take: try Soleur (the signup page) or read a related founder post. Never a terminal command or an install step.
- **Distribution.** Distribute as usual, each channel following its own note, except Hacker News: skip it, or submit the technical write-up there instead of the post (see `### Hacker News`).
- **Scope.** Applies to every new post. A refresh of an existing post updates facts only and keeps its title, slug, H1, meta description and target keywords; re-angling an existing post means writing a new one. Posts published before this note keep their register; do not rewrite, rename or redirect them to match.
- **Example opening.**
  - Don't: "Our own `product-roadmap next` saw 30 of 118 open issues and recommended the wrong phase."
  - Do: "You keep a list of everything your business needs. Somewhere in it are ideas you chose to park and ideas you forgot, and from the outside they look exactly the same."
```

- **Backticks in the note.** The "Don't" example and the `soleur:` mention contain backticks by design. They live in the brand guide, not in a post, so the scan never reads them.
- **No "simply" in the "Do" example.** The copywriter removed it because the brand guide's `### Do's and Don'ts` bans the word, and a model copies examples.

## Decision: part (4), the #8548 rework, ships in #8548's own PR, not here

**Chosen: a separate PR under #8548, started once this one merges.** This PR does the cheap half that unblocks it: a handoff comment on #8548 carrying the founder-sentence result and a recommended angle.

Reasons:

1. **The issue sets the order.** #8774 says: "Do this only after (1) lands, so the draft is written against the updated guide." "Lands" means on `main`. content-writer, the cron, and any fresh session read the guide from the checked-out tree. A draft written in the same PR is written against a guide nobody has approved yet.
2. **Founder taste gate.** The founder rejected the last draft personally. Re-angle versus replace, and the new draft itself, need the founder's review. Bundling them would either hold this rule change (p2) until a content approval (p3) comes back, or ship a post without that review.
3. **A different ship lifecycle.** A post PR carries a new blog file, an OG image, a `distribution-content/` file with a publish date, and a dated-slug entry in `apps/web-platform/infra/seo-bulk-redirects.tf`. PR #8649 had that entry, and it is an infra path that `SENSITIVE_PATH_RE` matches (`apps/[^/]+/infra/`). It also needs a fact-check pass. None of that belongs in a brand-guide PR, and keeping it out keeps this PR's User-Brand threshold at `none`.
4. **The time window holds.** The #8548 window is 2026-10-06, per the 2026-09-23 triage comment. This PR is docs plus one small script, so it merges well before then.
5. **Merging this PR unblocks #8548 automatically.** `Closes #8774` resolves the GitHub blocked-by edge.

**What this PR does for #8548** (Phase 4 below) is a short handoff comment. The comment says three things:

- The guide has landed.
- The recommended option is the founder's own option 1, **re-angle, not replace**. Sorting work into four places (doing now, later, not yet defined, decided against) is something any founder does, and only the technical telling of it failed.
- The draft should open on the founder's words: "I lose track of what I decided and what I just forgot."

The fuller outline, the list of what to drop, and the file list stay in this plan file, which the comment links. The comment does not repeat them. The final call on the angle stays with the founder, in #8548.

## Files to Edit

- `knowledge-base/marketing/brand-guide.md`: sections A1–A4.
- `plugins/soleur/skills/content-writer/SKILL.md`: B1–B4. Body only; the `description:` is unchanged, so `SKILL_DESCRIPTION_WORD_BUDGET` is unaffected.
- `plugins/soleur/skills/ship/SKILL.md`: D, one sentence of about 70 bytes.
- `knowledge-base/overview/vision.md`: E, two channel lines.
- `knowledge-base/marketing/content-strategy.md`: E, one Pillar 2 line.

## Files to Create

- `plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh` (C). Make it executable (`git add --chmod=+x`). The skill still calls it through `bash`, so a lost exec bit on a customer checkout cannot break it.
- `plugins/soleur/test/blog-audience-contract.test.ts` (F).

## Implementation Phases

### Phase 1: Tests first (RED)

Write `plugins/soleur/test/blog-audience-contract.test.ts` from the Guard Contract. Use fixtures synthesized inline, per `cq-test-fixtures-synthesized-only`, and do not copy the #8548 draft. Run `bun test plugins/soleur/test/blog-audience-contract.test.ts` and confirm it is RED for the right reasons:

- there is no `### Blog` heading;
- `technical blog posts` is still present;
- the old `--audience` default is still present;
- the script is missing.

### Phase 2: Brand guide and sibling documents

Make edits A1–A4 and E.

### Phase 3: content-writer, scan script, ship sentence

Make edits B1–B4, C and D. The new test is now GREEN.

### Phase 4: #8548 handoff (a GitHub write, not a file)

1. Check idempotency first. Look for a comment on #8548 that already carries the marker `<!-- 8774-handoff -->`; if one exists, skip posting, so a re-run of the pipeline does not post twice: `gh issue view 8548 --json comments --jq '[.comments[].body | select(contains("8774-handoff"))] | length'` returns `0`.
2. Otherwise write the body to a `mktemp` file and post it with `gh issue comment 8548 --body-file "$F"`.
3. The body is the marker plus about three sentences:
   - the guide landed, naming this PR;
   - the recommendation, re-angle on "I lose track of what I decided and what I just forgot";
   - a link to this plan's [Handoff notes for #8548](#handoff-notes-for-8548).

### Phase 5: Verify

Run the Acceptance Criteria commands. That is the verification step, with no separate list.

## Handoff notes for #8548

These notes are for #8548's own PR. This PR does not act on them.

### Opening and outline

- **Opening** (founder's words, no "simply"): "I lose track of what I decided and what I just forgot. From the outside, a parked idea and a forgotten one look exactly the same."
- **Outline**, from the CMO and reordered after CPO review so our own tool is not the subject:
  1. The cost: settled decisions re-debated, or parked ideas lost.
  2. The idea: every piece of work sits in one of four places, and anything outside them is forgotten.
  3. A 20-minute sort any founder can run this week, with any tool.
  4. One line of our own story, as illustration: our planning assistant once pointed at the wrong priority because it could see only a quarter of our list.
  5. What changed for us.
  6. CTA: ask Soleur what is next.

### What to drop and what to keep

- **Drop from the body:** the `gh`/`--limit` mechanics, the audit-bundle list, the terminal command in the CTA, and every issue number.
- **Keep, in plain words:** the Matt Pocock credit by name with a link, which the 2026-09-23 triage comment requires. Put the technical write-up (PR #8536) in the one closing link.

### What the post PR carries

- the blog file;
- an OG image;
- the distribution file;
- the `apps/web-platform/infra/seo-bulk-redirects.tf` dated-slug entry;
- a rewrite of the content-strategy row and calendar entry.

Run `blog-jargon-scan.sh` on the draft before asking for founder review.

## Non-Goals

- **Rewriting or retiring existing technical posts.** The note's `Scope` bullet grandfathers them by decision, so this is not a deferral. Examples: `claude-code-plugin-vs-skill-vs-mcp`, `skill-libraries-vs-workflow-plugins`, `loop-engineering-for-your-whole-company`.
- **Changing the "beachhead" designation, the thesis, or positioning.** These are product-strategy calls and out of scope for this PR.
  - The CPO's review found the beachhead already stale against `business-validation.md`, which redefined it problem-first in March 2026. The founder's objection may be a symptom of that.
  - The CPO proposes a positioning revalidation, which is a User-Challenge item (T-3). It is not decided here.
- **Building a separate "engineering notes" home for technical long-form.** This PR decides the home is GitHub (the PR, ADR or README) and the existing docs site, so no new surface is needed. If the founder later wants a published technical outlet, that is a new product decision.
- **Adding an HN skip rule to `social-distribute`.** HN is manual-only today: `social-distribute` Phase 10 lists "Hacker News: Manual (content in file)", and the cron's channels are `discord, x, bluesky, linkedin-company`. The note's `Distribution` bullet tells the human who posts. No automated path undoes it.
- **Changing the cron prompt** in `cron-content-generator.ts`. The skill default covers the audience. Surfacing scan residue in the cron's audit issue would add a production deploy to this PR, so it is routed to T-5.
- **Writing, fact-checking or publishing the #8548 post.** That happens in #8548's own PR. See the Decision above.

## Open Code-Review Overlap

1 open code-review issue mentions a file this plan edits.

- **#3649** (marketing: PR-A2 #3603 content brief, schedule for PR-C merge) mentions `knowledge-base/marketing/content-strategy.md`. **Acknowledge.** It is a content brief waiting on a different PR's merge and touches a different row. This plan's edit to that file is one dated Pillar 2 line.

No open code-review issue mentions `brand-guide.md`, `content-writer/SKILL.md`, `ship/SKILL.md` or `vision.md`. This was checked with `gh issue list --label code-review --state open --json number,title,body --limit 200` and a `jq contains` match per path.

## User-Brand Impact

- **If this lands broken, the user experiences:** the next Soleur blog post, whether drafted by the headless content generator or a session, still opens with a CLI command or an internal bug. A non-technical founder landing from LinkedIn or X decides "this isn't for me" and leaves. That is the exact bounce the 2026-03-22 business validation measured. A broken scan could instead block nothing but flood a draft with false hits, and the skill contains that by treating exit 2 as warn-and-continue.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The diff is brand-voice prose, a read-only text scan of a local markdown file, and a test. It adds no new data flow, credential, network call or storage.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: every edited path is marketing prose, a skill body, or a read-only local text scan, and none matches SENSITIVE_PATH_RE. The one sensitive-path edit a post needs (seo-bulk-redirects.tf) is deliberately left to #8548's PR.`

## Observability

Not required. No Files-to-Edit entry sits under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/` or `plugins/*/scripts/`, and no infrastructure surface is added.

The new script does run on a customer's CLI (observability layer 7), since it ships in the plugin. Layer 7 is N/A for it: the drafting skill consumes its exit codes in-process, and any exit other than 0 or 1 is warned and listed in the skill's own report. It never fails silently or blocks.

The headless cron's existing liveness signal and audit-issue signal in `cron-content-generator.ts` are unchanged. That the cron's audit issue does not surface scan residue is a known gap, routed to `decision-challenges.md` (T-5).

## Guard Contract

### Guard 1 — Blog-note heading contract (brand guide ↔ content-writer)

**Property.** content-writer resolves a blog post's register through a `### Blog` note that exists exactly once inside the brand guide's `## Channel Notes`, and no brand-guide or vision routing line sends the blog to the technical register.

**Assembly.** Three files and one chokepoint each:

- `brand-guide.md`: the `## Channel Notes` slice (from that heading to the next level-2 heading) and a whole-file count of `^### Blog$`;
- `brand-guide.md` and `vision.md`: every line, for the `technical blog` phrase (case-insensitive);
- content-writer `SKILL.md`: the Phase 1 `--audience` bullet, the one line that starts with `` - `--audience` ``.

Plan review cut the per-row table parse. The phrase `technical blog` is the only routing phrase the old guide used, and DHH and the CTO argued that parsing prose tables makes every future edit to the brand guide a test edit.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Rename `### Blog` to `### Blog Posts` in brand-guide.md | RED: the message names the heading content-writer reads and the test file |
| 2 | Add a **second** `### Blog` heading elsewhere in the guide, after a compliant first one | RED: the whole-file count must equal 1 |
| 3 | Put `technical blog posts` back in the Technical builders row, or in the Technical register line, or in `vision.md` | RED |
| 4 | Revert the content-writer `--audience` bullet to `(blog → technical, landing page → general)` | RED: the bullet must contain `## Channel Notes > ### Blog` |
| 5 | Guard dispatch: point the brand-guide path at a missing file, or make the Channel Notes slice come back empty | RED: the test asserts the file read succeeds and the slice is non-empty before counting |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | Replace the heading validator with `() => true` | RED: the inline fixture guide without `### Blog` must fail the validator |
| H2 | must-PASS: an inline fixture guide where `### Blog` sits between two other Channel Notes subsections, not last | PASS: position is a permitted variation |

### Guard 2 — `blog-jargon-scan.sh` flags reader-visible jargon only

**Property.** The script exits 1 and prints every matching line if and only if a reader-visible line has a backtick, a `--letter` flag or a visible `#NN` number. Reader-visible means frontmatter `title:`, `seoTitle:` and `description:`, plus body lines before any JSON-LD block. It exits 0 otherwise, and 2 on a usage error.

**Assembly.** One chokepoint: the `awk` extractor, with three arms, feeding one `grep -E`. The exit code is derived from whether `hits` is empty. The test covers it with three fixtures (DHH and the simplicity review): RED, must-PASS and usage.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `--[a-z]` alternative from the regex | RED: the RED fixture's `title: "Fixing the --limit bug"` line must be printed |
| 2 | Drop the `exit` on the JSON-LD opener, or drop the frontmatter key filter | RED: the must-PASS fixture carries `#123` inside JSON-LD and in a non-reader frontmatter key |
| 3 | Stop after the first hit (`grep -m1`) | RED: the RED fixture asserts all three hit line numbers are printed |
| 4 | Guard dispatch: `exit 0` unconditionally, or an awk that prints nothing | RED: the RED fixture asserts exit 1 **and** non-empty stdout |
| 5 | Remove the usage check | RED: running with no argument asserts exit 2 |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | Swap the RED fixture for the must-PASS fixture | RED: the suite asserts exit 1 on the RED fixture |
| H2 | must-PASS content: founder prose using a double-hyphen as a dash, a link to `https://github.com/org/repo/pull/8536`, a markdown heading, a `<details>` FAQ answer, a `ref: "#123"` non-reader frontmatter key, and `#123` plus a backtick inside JSON-LD | exit 0 |

## Acceptance Criteria

- [ ] **AC1.** The guide has exactly one `### Blog` heading, and it is inside `## Channel Notes`.
  - `grep -c '^### Blog$' knowledge-base/marketing/brand-guide.md` prints `1`.
  - `awk '/^## Channel Notes/{c=1;next} /^## /{c=0} c && /^### Blog$/' knowledge-base/marketing/brand-guide.md | wc -l` prints `1`. Checked at plan time: the same awk prints `1` for `### Discord` today.
  - The line above the heading is the A3 HTML comment naming the test file.
- [ ] **AC2.** The note carries the eleven labelled bullets from the target text, plus the example-opening pair. The labels are: Reader, Before drafting, Open, Outcome before mechanism, Jargon limits, Proof points, Search, Where technical detail goes, Call to action, Distribution, and Scope. The "Do" example does not contain "simply". This is a one-time check at the work phase; the test does not pin these labels.
- [ ] **AC3.** `grep -niE 'technical blog' knowledge-base/marketing/brand-guide.md knowledge-base/overview/vision.md` prints nothing. The `**General register**` parenthetical and the Non-technical founders channels cell both name the blog.
- [ ] **AC4.** content-writer's blog default resolves through the note, with no unconditional technical default left.
  - `grep -c 'blog → technical, landing page → general' plugins/soleur/skills/content-writer/SKILL.md` prints `0`.
  - `grep -c 'blog posts default to .technical.' plugins/soleur/skills/content-writer/SKILL.md` prints `0`.
  - `grep -c '## Channel Notes > ### Blog' plugins/soleur/skills/content-writer/SKILL.md` prints at least `3`: the `--audience` bullet, Phase 2 step 2, and the Important Guidelines bullet.
  - The file contains `## Phase 2.4: Blog Note Scan`. Its trigger names the literal `**Jargon limits.**` label, and its non-zero-exit branch says warn, list in the report, and continue.
- [ ] **AC5.** content-writer gains no new interactive gate: `git diff origin/main -- plugins/soleur/skills/content-writer/SKILL.md | grep -c '^+.*AskUserQuestion'` prints `0`, and `grep -c '^
- [ ] **AC6.** The scan behaves the same on real files as on the fixtures:
  - on the rejected #8548 draft: `D=$(mktemp); git show origin/feat-content-8548-roadmap-undecided-vs-forgotten:plugins/soleur/docs/blog/2026-09-24-roadmap-undecided-vs-forgotten.md > "$D"; bash plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh "$D" | wc -l` prints 20 or more, and exits 1;
  - on `plugins/soleur/docs/blog/2026-06-15-best-ai-tools-for-solo-founders-2026.md`: exits 0;
  - with no argument: exits 2.
- [ ] **AC7.** `bun test plugins/soleur/test/blog-audience-contract.test.ts` passes.
- [ ] **AC8.** `grep -c "apply the brand guide's Channel Notes > Blog note" plugins/soleur/skills/ship/SKILL.md` prints `1`, and `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` exits 0.
- [ ] **AC9.** `vision.md` has no "technical blog posts", and `content-strategy.md` Pillar 2 carries the dated #8774 line.
- [ ] **AC10.** These suites still pass:
  - `bun test apps/web-platform/test/server/inngest/cron-weekly-release-digest.test.ts`, the Release Digest lockstep;
  - `bun test plugins/soleur/test/marketing-content-drift.test.ts plugins/soleur/test/scratch-path-collision.test.ts plugins/soleur/test/components.test.ts`;
  - `bun test plugins/soleur/`.
- [ ] **AC11.** Exactly one handoff comment exists on #8548: `gh issue view 8548 --json comments --jq '[.comments[].body | select(contains("8774-handoff"))] | length'` prints `1`. The check scans every comment and counts the marker, so neither a later comment by someone else nor a pipeline re-run can flip it.
- [ ] **AC12.** The PR body uses `Closes #8774` and `Ref #8548`, never `Closes #8548`. It pre-records the expected CMO Website Framing Review result: "the website already uses the General register; no copy change expected."

## Domain Review

**Domains relevant:** Marketing

### Marketing

**Status:** reviewed

**Assessment:** The CMO ran as `soleur:marketing:cmo` and agrees with moving the blog wholesale to the non-technical founder, grandfathering existing technical posts, and re-angling (not replacing) #8548. Its findings and dispositions:

- **HN distribution.** The CMO rated this high risk. **Disposition:** down-rated after checking. HN is manual-only in `social-distribute`, and the cron channels exclude it. The note's `Distribution` bullet covers the human who posts.
- **No home for technical long-form.** **Disposition:** decided that GitHub (the PR, ADR or README) and the docs are the home. See Non-Goals.
- **Exempt comparison and developer-query formats.** **Disposition:** no register exemption. The founder's direction covers every new post. The growth-strategist's narrower carve-out is adopted instead: a comparison post keeps "Soleur vs X" in its title and meta description, but its body is founder-register. That is the `Search` bullet. Recorded as a taste call in `knowledge-base/project/specs/feat-one-shot-8774-blog-founder-audience/decision-challenges.md`.
- **Glossary pointer and readability test.** **Disposition:** folded into the note's `Jargon limits` bullet.
- **Allow PR numbers in the closing link.** **Disposition:** folded in, with the number in the URL only so it agrees with the scan.
- **Keep one do/don't pair.** **Disposition:** folded in.
- **The Website Framing gate will fire** on the `## Voice` edit, and the website already uses the General register. **Disposition:** pre-record the expected no-op in the PR body (AC12).

**Copywriter** (`soleur:marketing:copywriter`, Content Review Gate). It rewrote the note, and the target text above is its version. Changes:

- It removed a banned "simply" from the "Do" example.
- It gave the founder-sentence bullet an unattended branch: always re-angle, never abort. content-writer's Phase 2 applies it.
- It aligned the jargon limits with the scan: backticks, `#1234`, and names with or without `soleur:`, with PR numbers only inside the closing link's URL. The limits now also cover titles, headings and FAQ answers.
- It added the trust-scaffolding clause ("what the founder still decides") and a real-source-only rule for numbers.
- It changed Distribution to "all channels except HN", and pointed the CTA at the signup page.

It also listed four conflicts elsewhere in the guide:

- #1, the routing table and voice profiles: fixed by A1 and A2.
- #2, the CaaS framing reserved for blog posts: A5 proposed a fix and plan review cut it. The note's `Open` bullet already puts the problem first (taste item T-6).
- #3 and #4, the thesis and the Do's "60+ agents": handled inside the note's `Reader` bullet. Positioning prose is left unchanged.

**Growth strategist** (`soleur:marketing:growth-strategist`, one SEO pass):

- **Keyword sentence plus a comparison-title carve-out.** Adopted as the `Search` bullet.
- **Refresh-only-updates-facts.** Adopted as the `Scope` bullet. A deterministic refresh detector was built into content-writer and then deleted in plan review (see Plan Review Revisions).
- **Never unpublish, rename or redirect existing technical posts.** Adopted in `Scope`.
- **Seven queued `seo-refresh-queue.md` topics would fail the founder check** (Codex, Replit, Cursor, Best Claude Code Plugins, CrewAI, Tanka, NanoCorp). The "Create" rows are re-angled when content-writer applies the note in Phase 2. The "Update" rows follow the note's `Scope` bullet. No queue edit is made here. The CPO's suggestion to flag them for a founder keep-or-drop call is taste item T-1.
- **Internal-link weakening of technical posts.** Left alone and watched in the monthly ranking check.

### Product/UX Gate

Not applicable. No UI-surface file is in the Files to Edit or Files to Create lists: all are `.md`, one `.sh` and one `.test.ts` under `knowledge-base/` and `plugins/soleur/`. The mechanical UI-surface override did not fire, and the sweep judged Product not relevant because the ICP segments are unchanged and only the blog's channel routing moves.

**Brainstorm-recommended specialists:** none. No brainstorm ran; this is a one-shot path. The CMO recommended specialists in its assessment:

- `soleur:marketing:copywriter`: invoked by the Content Review Gate on the `### Blog` note text.
- `soleur:marketing:growth-strategist`: invoked for one SEO pass.

**Agents invoked:** soleur:marketing:cmo, soleur:marketing:copywriter, soleur:marketing:growth-strategist
**Skipped specialists:** none

## Test Scenarios

- **Heading contract.**
  - Given brand-guide.md with exactly one `### Blog` inside `## Channel Notes`, when the contract test runs, then it passes.
  - When the heading is renamed or duplicated, then it fails and names the file and heading to edit.
- **Routing phrase.** Given `technical blog` anywhere in brand-guide.md or vision.md, when the test runs, then it fails.
- **Skill default.** Given the content-writer `--audience` bullet without `## Channel Notes > ### Blog`, when the test runs, then it fails.
- **No-note behavior (other projects).** Given a brand guide with no `### Blog` note, content-writer keeps `technical` and runs no scan. This is checked by reading SKILL.md and the Important Guidelines bullet (AC4).
- **Headless draft.** Given `soleur:content-writer "<a mechanism-first topic>" --headless` against the updated guide, Phase 2 applies the note's founder sentence and unattended re-angle rule, drafts, and never aborts on audience grounds. This is checked by reading SKILL.md (AC5): the skill has no new abort or ask path, and an end-to-end LLM run is not a deterministic test.
- **Scan, RED.** Given a synthesized post with `title: "Fixing the --limit bug"` and body lines containing `` `next` `` and `issue #1423`, when the scan runs, then it exits 1 and prints all three lines with their line numbers.
- **Scan, PASS.** Given founder prose with double-hyphen dashes, a link to `.../pull/8536`, headings, `#123` only in a non-reader frontmatter key, and `#123` plus a backtick only inside JSON-LD, when the scan runs, then it exits 0.
- **Scan, usage.** Given no argument or a missing file, when the scan runs, then it exits 2 with a usage line on stderr.
- **Regression.** Given the Release Digest lockstep test, when the brand guide is edited, then it still passes because `#### Release Digest` is byte-identical.

## Advisor Consult (plan Step 4.5)

A scoped `advisor`-tier consult (ADR-083) reviewed the overview, the phases, and Phase B, which it agreed is the riskiest phase.

1. **Keep content-writer project-agnostic.** **Applied.**
   - With no note, the skill keeps its prior behavior (B1, B4).
   - The scan runs only on the literal `**Jargon limits.**` label (B3).
   - Plan review also removed the `soleur:` pattern.
2. **The refresh guard must work before a draft exists.** It was first applied as slug-based detection in a new Phase 1.5. **Plan review then deleted it rather than fixing it.** Kieran found a P0 (a detected refresh still wrote a new dated file that collides on `fileSlug`), and the simplicity review found it bought no listed property. Both panels firing on the same scope means delete over fix.
   - What remains is the note's `Scope` bullet: refreshes update facts only. content-writer applies it in Phase 2.
   - The pre-existing duplicate-write behavior for "Update" topics is untouched and out of scope.
   - The advisor's end-to-end cron test is not deterministic, so it is not added (see Test Scenarios).

## Plan Review Revisions

Plan review ran headless, with five seats: `soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`, `soleur:engineering:review:code-simplicity-reviewer`, and the named panel `soleur:engineering:cto` (devex lens) and `soleur:product:cpo`.

**Mechanical items (auto-applied):**

- **Phase 1.5 deleted, with its slug-based refresh detection.** Simplicity: the note, read in Phase 2, already carries the check. Kieran P0: the detected refresh still wrote a duplicate file. DHH agreed that Phase 1.5 restated the note. Kieran's P1s about the `$SLUG`/`$BLOG_DIR` definitions and the missing headless-defaults entry went away with it.
- **AC2b removed.** It contradicted B2 (DHH P0, Kieran P1).
- **Guard 1 cut from 8 mutations plus a table parse to 5 heading and phrase rows** (DHH, CTO, simplicity). The pure-function validators and an HTML comment above `### Blog` naming the test come from the CTO review.
- **Guard 2 cut to three fixtures and five mutation rows** (DHH, simplicity). The `soleur:` pattern was removed from the plugin-generic script (DHH, CTO).
- **Scan trigger is the literal `**Jargon limits.**` label, not a judgment call** (CTO, simplicity).
- **`${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` fallback, with any exit other than 0 or 1 treated as warn-and-report** (CTO P1-b).
- **AC6 captures the `mktemp` path** (Kieran P2). **AC1 adds the whole-file count** (Kieran P2). **AC4 adds the step-4 phrase** (Kieran P2).
- **AC7 no longer asks for per-row observations in the PR body** (DHH, CTO).
- **The Observability reasoning now names layer 7** (Kieran P2).
- **Phase 5 is folded into the ACs** (DHH).
- **The #8548 content-strategy row annotations are cut** (DHH, simplicity). #8548's PR rewrites those rows.
- **The #8548 comment is shrunk to about three sentences plus an idempotency marker** (DHH, simplicity, CTO P2-c). AC11 now counts the marker. The outline moved to [Handoff notes for #8548](#handoff-notes-for-8548), with CPO F2's fixes: the founder's own words, no "simply", and our tool demoted to a one-line illustration.
- **P5 reworded**, so the plan no longer claims to settle the question the founder still decides in #8548 (simplicity).

**Kept, with a rebuttal:**

- **D, the ship sentence.**
  - Simplicity said to cut it by the plan's own cut-list argument. That argument does not transfer. The CMO reads Voice and Identity, and the founder-first and route-mechanism-elsewhere rules live in Channel Notes.
  - The sentence is now a roughly 70-byte pointer, so it cannot drift from the note.
- **Skill-mandated sections**: Open Code-Review Overlap, Domain Review, User-Brand Impact, Observability, and Research Insights.
  - DHH asked to cut them, but each is required by `soleur:plan` or checked by `deepen-plan` and `preflight`.

**Taste and User-Challenge items** are persisted to `knowledge-base/project/specs/feat-one-shot-8774-blog-founder-audience/decision-challenges.md`:

- **A5, the CaaS sentence, is cut.** The copywriter proposed it, and DHH and the simplicity review said cut. The default applied is the cut, recorded as taste T-6.
- **CPO F1 and F4: positioning revalidation and topics drawn from founder problems.** These are User-Challenge items, added to T-3.
- **CPO F3: flag the developer-query "Create" rows in the SEO queue for a founder keep-or-drop call.** Added to T-1.
- **CTO P1-a: the cron audit issue does not carry scan residue.** Recorded as T-5. The default is no cron edit in this PR.

## Dependencies & Risks

- **Ship byte ceiling.** There are 3,037 bytes of headroom, and the edit is about 70 bytes. If the lint reds anyway, shorten the sentence. Never raise the ceiling in this PR (ADR-229).
- **Headless drift.** The cron runs `main`'s plugin tree, so the new default applies from the first run after merge.
  - Cron posts auto-merge once CI is green, so re-angled posts go live without founder review. That is today's behavior for every cron post too.
  - Scan residue reaches only the skill's in-run report, not the cron's audit issue (T-5).
- **Over-strict scan.** It is advisory inside the skill (two fix cycles, then report) and never a CI gate on posts.
- **Two readers of one note.** Humans and the LLM both read the `### Blog` note, so each bullet is imperative and single-purpose.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled.
- Do not put `### Blog` before `### Discord` or anywhere between `### Discord` and `#### Release Digest`'s end. Placement does not break the lockstep slice, which stops at the next `\n#`. But an edit adjacent to `#### Release Digest` invites an accidental byte change to it. Append after `### Website / Landing Page`.
- `scratch-path-collision.test.ts` scans every SKILL.md and every `skills/*/scripts/*.sh`. Use `mktemp` in both the Phase 2.4 prose and the script. Never write a literal `/tmp/...`.
- `components.test.ts` scans skill `.md` and `scripts/*.sh` files for `gh` search-probe hazards (`EXEC_SURFACE_GLOBS`). The new script calls no `gh`, so it stays clean.
- `components.test.ts` also has a "uses markdown links, not backticks" test per skill, with the regex `` `(?:references|assets|scripts)\/[^`]+` ``. In content-writer SKILL.md, reference the script as the markdown link `[blog-jargon-scan.sh](./scripts/blog-jargon-scan.sh)`. Never write an inline code span that starts with `scripts/`. The `bash "${CLAUDE_PLUGIN_ROOT}/skills/content-writer/scripts/…"` invocation form is safe, because the backtick does not immediately precede `scripts/`.
- The ship SKILL.md edit goes **inside** the existing quoted CMO prompt string on the prompt item 1 line of §CMO Content-Opportunity Gate. Anchor on the text `Assess content and distribution opportunities from this PR`, not on a line number.
- The content-writer skill is plugin-generic. Nothing in its body may hard-code "non-technical solo founder". It defers to the `### Blog` note, so that other projects' brand guides keep working.
