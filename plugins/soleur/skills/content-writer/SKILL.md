---
name: content-writer
description: "This skill should be used when generating full article drafts with brand-consistent voice, Eleventy frontmatter, and structured data. It requires a brand guide and existing blog infrastructure."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# Content Writer

Generate full publication-ready article drafts with brand-consistent voice, Eleventy frontmatter, JSON-LD structured data, and optional FAQ sections. Content is validated against the brand guide and presented for user approval before writing to disk.

<!-- operator-typed-render:start -->
**Any message this skill PRINTS that tells the operator to run a skill or command renders at emit time.** The doc names it canonically (`soleur:<name>`, ADR-226); before printing, render it as the active harness's **operator-typed form** per `formatSkillInvocation` (`plugins/soleur/lib/harness.ts`), which owns the per-harness slash and sigil forms — the operator types that string into a fresh session where no routing contract is in context, so a bare canonical name is model-discretion there rather than a dispatch. This covers abort messages, `AskUserQuestion` prompts and options, `Display`/`echo` lines and resume prompts alike; an agent-read instruction stays canonical.
<!-- operator-typed-render:end -->

## Headless Mode Detection

If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true` and strip `--headless` from `$ARGUMENTS`. The remainder is the topic/arguments.

**Argument format:** `<topic> [--outline <outline>] [--keywords <keywords>] [--audience <audience>] [--headless]`

**Headless defaults for interactive gates:**

- Phase 2.4 (Blog Note Scan): leftover hits after 2 fix cycles, or a scan that could not run, are listed in the Phase 4 report; the draft is never blocked.
- Phase 3 (User Approval): auto-selects **Accept** when all citations are PASS or SOURCED. When any citation is FAIL, auto-selects **Fix** — removes or replaces the failed claims, re-runs soleur:marketing:fact-checker, and accepts only when all claims pass (max 2 fix cycles, then accepts with UNSOURCED markers for any remaining failures).
- If citation verification was skipped (soleur:marketing:fact-checker unavailable), auto-selects **Accept** with a warning in the issue.

## Phase 0: Prerequisites

<critical_sequence>

Before generating content, verify both prerequisites. If either fails, display the error message and stop.

### 1. Brand Guide

Check if `knowledge-base/marketing/brand-guide.md` exists.

**If missing:**
> No brand guide found. Run the soleur:marketing:brand-architect agent first to establish brand identity:
> `Use the soleur:marketing:brand-architect agent to define our brand.`

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
- `--audience "technical|general"` (optional): audience register from brand guide. `technical` uses engineering vocabulary and developer proof points. `general` uses plain language and business-outcome proof points. Blog posts use the register the brand guide's `## Channel Notes > ### Blog` note names. Without a Blog note, or when the note names no register, they default to `technical`, as before. Landing pages and onboarding content default to `general`. An explicit `--audience` is honored as given.

**Default output path** (if `--path` not provided): auto-generate from topic slug as `plugins/soleur/docs/blog/YYYY-MM-DD-<slug>.md`.

## Phase 2: Generate Draft

Read the brand guide sections that inform content generation:

1. Read `## Voice` -- apply brand voice, tone, do's and don'ts
2. Read `## Channel Notes > ### Blog` -- apply every rule in it, including any check it asks for before drafting and any rule for unattended runs (if the section exists). A Blog note never adds an abort. In headless mode it never adds a question either: follow its unattended-run rule.
3. Read `## Identity` -- use mission and positioning for content alignment
4. Resolve the register: `--audience` if set, otherwise the Phase 1 default (the register the Blog note names for blog posts, `technical` for blog posts when there is no Blog note or it names no register, `general` for landing pages and onboarding content). Then read `### Audience Voice Profiles` from brand guide and apply that register's vocabulary, explanation depth, and proof point selection rules.

Generate a full article draft that:

- Follows the brand voice from `## Voice`
- Incorporates target keywords naturally (if `--keywords` provided)
- Follows the provided outline structure (if `--outline` provided)
- **Links every external source at its FIRST mention in the body** — when the article quotes a person, adopts a coined term/framework, or responds to an essay/study/announcement, hyperlink that source at the first reference or first quote, not only in a footer disclaimer or the citation list. Footer-only attribution buries the source readers (and AI engines) need at the point of the claim. A footer source line is additive, never a substitute for the inline link. **Why:** #5088 — the loop-engineering post linked Osmani's essay only in the footer; the inline link at first mention was added in review.
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

## Phase 2.4: Blog Note Scan

Run this phase only when **both** hold:

- the output is a blog post (the default output path, or a `--path` under a `blog/` directory), and
- the brand guide's `## Channel Notes > ### Blog` note contains the literal label `**Jargon limits.**`.

Otherwise skip it. A project whose Blog note sets no jargon limits gets no scan.

[blog-jargon-scan.sh](./scripts/blog-jargon-scan.sh) flags reader-visible lines that carry a backtick, a `<code>` or `<pre>` tag, a `--flag`, or a visible issue or PR number (`#` plus two or more digits). It reads the `title:`, `seoTitle:` and `description:` values (including folded, multi-line values) and the body, skipping JSON-LD blocks and markdown link targets. That is a **fixed subset** of what a Blog note may ban: indented code blocks, file paths, command or skill names, API names and bare numbers are not detected, whatever the note says. A clean scan therefore does not mean the note's jargon limits are met: before leaving this phase, check the draft against the rest of them too.

Scan the draft through a file, never by pasting it into a shell command: a heredoc is broken by a draft line equal to its delimiter, and re-pasting the whole draft on every re-scan costs its full length each time.

1. Create a scratch directory: `mktemp -d` (one Bash call; note the printed path).
2. Write the draft to `<that directory>/draft.md` with the **Write** tool.
3. Scan it (one Bash call):

   ```bash
   rc=0; bash "${CLAUDE_PLUGIN_ROOT}/skills/content-writer/scripts/blog-jargon-scan.sh" "<that directory>/draft.md" || rc=$?; echo "SCAN_RC=$rc"
   ```

4. Apply fixes to the draft file with the **Edit** tool, and re-run step 3. When a rewritten line also appears in the FAQPage JSON-LD (a question or an answer), edit the JSON-LD to match: the scan skips JSON-LD, and the Blog note's limits cover FAQ answers.
5. When the phase ends, Read `draft.md` back: it is the draft from here on (Phases 2.5 to 4). Then remove the directory (`rm -rf "<that directory>"`).

The script path is the bare plugin-root anchor, with no fallback (ADR-179): a fallback would resolve into the working repository and execute a file from it.

- **`SCAN_RC=0`:** no hits. Continue.
- **`SCAN_RC=1`:** rewrite each listed line in plain words, or move the detail into one closing technical link at the end of the post (add it if the draft has none; if the draft links several technical write-ups, keep the most relevant one there), whose URL may carry the number. Re-scan after each fix cycle, for at most 2 fix cycles per run of this phase. Keep any hits left after that, as the line's text without the scratch file's line number: interactive runs show them in Phase 3; headless runs list them in the Phase 4 report.
- **Any other value** (usage error, unreadable file, `127` for a missing script): print `blog-jargon-scan unavailable (rc=<N>)` in the Phase 4 report and continue. Never block a draft on a broken scan.
- **Any Bash call in this phase is refused** (a restricted runner, such as a scheduled job allowed only `gh` commands; usually step 1 is the first refusal): print `blog-jargon-scan unavailable (denied)` in the Phase 4 report, stop this phase without retrying, and keep the draft you hold in context. If `draft.md` was already written, Read it back first. A refused `rm` leaves the scratch directory behind; that is harmless. The Blog note's jargon limits still apply to the draft.

Re-run this phase every time Phase 2.5 re-runs (after each Phase 3 **Edit** or headless **Fix** cycle), so text rewritten by a citation fix is scanned too.

## Phase 2.5: Citation Verification

<validation_gate>

After generating the draft, verify all factual claims before presenting to the user.

Invoke the soleur:marketing:fact-checker agent via the Task tool, passing the full draft content:

```text
Task soleur:marketing:fact-checker: "Verify this draft:

<full draft text>"
```

Parse the returned Verification Report. For each claim:

- **PASS**: No annotation needed
- **FAIL**: Insert `[FAIL: <reason>]` inline after the claim in the draft
- **UNSOURCED**: Insert `[UNSOURCED]` inline after the claim in the draft

If the soleur:marketing:fact-checker agent is unavailable (e.g., Task tool not accessible), warn: "Citation verification skipped -- soleur:marketing:fact-checker agent not available. Proceed with manual verification." Continue to Phase 3.

Re-verification runs after each Edit cycle in Phase 3 -- when the user selects "Edit" and the draft is regenerated in Phase 2, Phase 2.5 re-runs on the updated draft.

</validation_gate>

## Phase 3: User Approval

If Phase 2.5 produced a Verification Report, display the summary first (total claims, verified, failed, unsourced), then present the draft with any inline FAIL/UNSOURCED markers visible, followed by any Phase 2.4 scan hits left after its fix cycles. If all claims passed, note "All citations verified." If verification was skipped, note "Citation verification was skipped -- manual review recommended."

**If `HEADLESS_MODE=true`:**

- If all citations are PASS/SOURCED, or verification was skipped: auto-select **Accept**. Proceed to Phase 4.
- If any citation has a FAIL marker: auto-select **Fix**. For each FAIL claim:
  1. Remove the unsupported statistic, quote, or claim entirely, OR
  2. Replace it with a verifiable alternative (search for a real source via WebSearch/WebFetch)
  3. Remove the `[FAIL: ...]` marker after fixing
- After fixing all FAIL claims, re-run Phase 2.5 (soleur:marketing:fact-checker) on the updated draft.
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

If Phase 2.4 ran, add after that sentence the `blog-jargon-scan unavailable (rc=<N>)` or `blog-jargon-scan unavailable (denied)` line if the scan could not run. In a headless run, also add one line per leftover scan hit, in the form `blog-jargon-scan leftover: <line text>` (interactive runs already showed them in Phase 3).

## Phase 4.5: OG Image Generation

Every blog post must have an `ogImage` for social sharing differentiation. This is **mandatory, not optional** — `plugins/soleur/test/seo-aeo-drift-guard.test.ts` (#4753) FAILS CI for any post without an `ogImage` frontmatter field. A post that reaches CI without it red-lights the build. After writing the article:

1. **Check for existing `ogImage`** in the frontmatter. If already set, skip.
2. **Generate a unique OG image** (1200x630px) using the `gemini-imagegen` skill or Pillow fallback:
   - Brand colors: dark background `#1a1a1a`, gold accent `#c4a35a`
   - Abstract/thematic visual matching the article topic -- no text in the image (og:title provides text)
   - Save to `plugins/soleur/docs/images/blog/og-<slug>.png`
   - **Fallback if generation is unavailable (never omit the field):** reuse the closest on-theme existing card — `ls plugins/soleur/docs/images/blog/og-*.png` and pick the nearest topical match (precedent: `2026-06-01-claude-code-plugin-vs-skill-vs-mcp.md` reuses `og-best-claude-code-plugins-2026.png`). A reused on-theme card beats a missing field (CI red) or the site default (the #4753 guard rejects the default for a bespoke-image post).
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
- If the brand guide's `## Channel Notes > ### Blog` section is missing, generate content using only the `## Voice` section (no error), and keep the `technical` blog default; the scan runs only when the note sets jargon limits.
- Every factual claim, statistic, and attributed quote must have a verifiable source URL. Phase 2.5 enforces this via the soleur:marketing:fact-checker agent -- claims without citations are flagged as UNSOURCED and claims with unsupporting sources are flagged as FAIL [enforced: soleur:marketing:fact-checker agent via Phase 2.5].
