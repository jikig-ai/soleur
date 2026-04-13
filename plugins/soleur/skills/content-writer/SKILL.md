---
name: content-writer
description: "This skill should be used when generating full article drafts with brand-consistent voice, Eleventy frontmatter, and structured data. It requires a brand guide and existing blog infrastructure."
---

# Content Writer

Generate full publication-ready article drafts with brand-consistent voice, Eleventy frontmatter, JSON-LD structured data, and optional FAQ sections. Content is validated against the brand guide and presented for user approval before writing to disk.

## Headless Mode Detection

If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true` and strip `--headless` from `$ARGUMENTS`. The remainder is the topic/arguments.

**Argument format:** `<topic> [--outline <outline>] [--keywords <keywords>] [--audience <audience>] [--headless]`

**Headless defaults for interactive gates:**

- Phase 3 (User Approval): auto-selects **Accept** when all citations are PASS or SOURCED. When any citation is FAIL, auto-selects **Fix** — removes or replaces the failed claims, re-runs fact-checker, and accepts only when all claims pass (max 2 fix cycles, then accepts with UNSOURCED markers for any remaining failures).
- If citation verification was skipped (fact-checker unavailable), auto-selects **Accept** with a warning in the issue.

## Phase 0: Prerequisites

<critical_sequence>

Before generating content, verify both prerequisites. If either fails, display the error message and stop.

### 1. Brand Guide

Check if `knowledge-base/marketing/brand-guide.md` exists.

**If missing:**
> No brand guide found. Run the brand-architect agent first to establish brand identity:
> `Use the brand-architect agent to define our brand.`

Stop execution.

### 2. Blog Infrastructure

Check if an Eleventy config file exists (`eleventy.config.js` or `.eleventy.js`).

**If missing:**
> No Eleventy config found. Run the docs-site skill to scaffold blog infrastructure first.

Stop execution.

</critical_sequence>

## Phase 1: Parse Input

Parse the arguments provided after the skill name:

- `<topic>` (required): the article topic or title
- `--outline "..."` (optional): article structure as inline text (Markdown list format)
- `--keywords "kw1, kw2, kw3"` (optional): target keywords, comma-separated
- `--path <output-path>` (optional): where to write the file
- `--audience "technical|general"` (optional): audience register from brand guide. `technical` uses engineering vocabulary and developer proof points. `general` uses plain language and business-outcome proof points. Defaults to channel-appropriate (blog → technical, landing page → general).

**Default output path** (if `--path` not provided): auto-generate from topic slug as `plugins/soleur/docs/blog/YYYY-MM-DD-<slug>.md`.

## Phase 2: Generate Draft

Read the brand guide sections that inform content generation:

1. Read `## Voice` -- apply brand voice, tone, do's and don'ts
2. Read `## Channel Notes > ### Blog` -- apply blog-specific guidelines (if the section exists)
3. Read `## Identity` -- use mission and positioning for content alignment
4. If `--audience` is set, read `### Audience Voice Profiles` from brand guide and apply the matching register's vocabulary, explanation depth, and proof point selection rules. If `--audience` is not set, infer from `--path` or topic context (blog posts default to `technical`, landing pages and onboarding content default to `general`).

Generate a full article draft that:

- Follows the brand voice from `## Voice`
- Incorporates target keywords naturally (if `--keywords` provided)
- Follows the provided outline structure (if `--outline` provided)
- Includes complete Eleventy frontmatter:

  ```yaml
  ---
  title: "<Article Title>"
  date: "YYYY-MM-DD"
  description: "<Meta description, 120-160 characters, includes primary keyword>"
  tags:
    - <relevant-tag>
  ---
  ```

  Note: `layout: "blog-post.njk"` and `ogType: "article"` are inherited from `blog/blog.json` — do NOT add them to individual post frontmatter. The blog-post layout handles BlogPosting JSON-LD and OG meta tags automatically — do NOT generate inline JSON-LD in the post body.

- Generates a FAQ section with FAQPage schema if the topic naturally raises 2+ questions. Include the FAQ schema inline:

  ```html
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    "mainEntity": [
      {
        "@type": "Question",
        "name": "<question>",
        "acceptedAnswer": {
          "@type": "Answer",
          "text": "<answer>"
        }
      }
    ]
  }
  </script>
  ```

**If existing posts are present** in the target directory, read 1-2 of them to match frontmatter schema, layout name, and tag conventions.

## Phase 2.5: Citation Verification

<validation_gate>

After generating the draft, verify all factual claims before presenting to the user.

Invoke the fact-checker agent via the Task tool, passing the full draft content:

```text
Task fact-checker: "Verify this draft:

<full draft text>"
```

Parse the returned Verification Report. For each claim:

- **PASS**: No annotation needed
- **FAIL**: Insert `[FAIL: <reason>]` inline after the claim in the draft
- **UNSOURCED**: Insert `[UNSOURCED]` inline after the claim in the draft

If the fact-checker agent is unavailable (e.g., Task tool not accessible), warn: "Citation verification skipped -- fact-checker agent not available. Proceed with manual verification." Continue to Phase 3.

Re-verification runs after each Edit cycle in Phase 3 -- when the user selects "Edit" and the draft is regenerated in Phase 2, Phase 2.5 re-runs on the updated draft.

</validation_gate>

## Phase 3: User Approval

If Phase 2.5 produced a Verification Report, display the summary first (total claims, verified, failed, unsourced), then present the draft with any inline FAIL/UNSOURCED markers visible. If all claims passed, note "All citations verified." If verification was skipped, note "Citation verification was skipped -- manual review recommended."

**If `HEADLESS_MODE=true`:**

- If all citations are PASS/SOURCED, or verification was skipped: auto-select **Accept**. Proceed to Phase 4.
- If any citation has a FAIL marker: auto-select **Fix**. For each FAIL claim:
  1. Remove the unsupported statistic, quote, or claim entirely, OR
  2. Replace it with a verifiable alternative (search for a real source via WebSearch/WebFetch)
  3. Remove the `[FAIL: ...]` marker after fixing
- After fixing all FAIL claims, re-run Phase 2.5 (fact-checker) on the updated draft.
- If re-verification passes (all PASS/SOURCED): auto-select **Accept**. Proceed to Phase 4.
- If FAIL claims persist after 2 fix cycles: convert remaining `[FAIL: ...]` markers to `[UNSOURCED]`, remove the specific claim text, and **Accept** the article. Do not abort — an article with conservative claims is better than no article. Note the removed claims in the GitHub audit issue.

**If `HEADLESS_MODE` is not set (interactive mode):**

Present the generated draft with word count displayed. Use the **AskUserQuestion tool** with three options:

- **Accept** -- Write article to disk
- **Edit** -- Provide feedback to revise the draft (return to Phase 2 with feedback incorporated)
- **Reject** -- Discard the draft and exit

If "Edit" is selected, ask for specific feedback, then regenerate incorporating the changes. The user can choose Edit as many times as needed.

## Phase 4: Write to Disk

On acceptance, write the article to the output path.

Report: "Article written to `<path>`. Review and commit when ready."

## Phase 4.5: OG Image Generation

Every blog post must have a unique OG image for social sharing differentiation. After writing the article:

1. **Check for existing `ogImage`** in the frontmatter. If already set, skip.
2. **Generate a unique OG image** (1200x630px) using the `gemini-imagegen` skill or Pillow fallback:
   - Brand colors: dark background `#1a1a1a`, gold accent `#c4a35a`
   - Abstract/thematic visual matching the article topic -- no text in the image (og:title provides text)
   - Save to `plugins/soleur/docs/images/blog/og-<slug>.png`
3. **Add `ogImage` to frontmatter**: `ogImage: "blog/og-<slug>.png"`
4. The base template resolves this as `/images/{{ ogImage }}` for og:image meta tags

**Headless mode:** Auto-generate without prompting. **Interactive mode:** Show the generated image and ask for approval.

## Important Guidelines

- All content requires explicit user approval before writing -- no auto-write (unless `--headless` is passed, which auto-accepts on PASS citations and auto-fixes FAIL claims before accepting)
- Brand guide is a hard prerequisite. Without it, the skill cannot generate brand-consistent content.
- Read the brand guide Voice section during draft generation, not as a separate post-hoc validation pass
- If outline is provided, follow it. If not, generate a reasonable article structure from the topic.
- Do not scaffold blog infrastructure. If missing, direct the user to the docs-site skill.
- The blog-post.njk layout generates BlogPosting JSON-LD automatically. Do not duplicate it in the post body.
- Frontmatter fields should match existing posts in the target directory when possible. The `date:` field must be unquoted (e.g., `date: 2026-03-26`, not `date: "2026-03-26"`) -- Eleventy's `dateToRfc3339` filter requires a Date object, and quoted dates are parsed as strings.
- If the brand guide's `## Channel Notes > ### Blog` section is missing, generate content using only the `## Voice` section (no error).
- Every factual claim, statistic, and attributed quote must have a verifiable source URL. Phase 2.5 enforces this via the fact-checker agent -- claims without citations are flagged as UNSOURCED and claims with unsupporting sources are flagged as FAIL [enforced: fact-checker agent via Phase 2.5].
