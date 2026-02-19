---
name: growth
description: "This skill should be used when performing content strategy analysis, keyword research, content auditing for search intent alignment, content gap analysis, content planning, or AI agent consumability auditing. Triggers on \"keyword research\", \"content strategy\", \"content audit\", \"content plan\", \"growth audit\", \"growth plan\", \"aeo content\", \"search intent\"."
---

# Growth Strategy

Analyze content for keyword alignment, plan content to capture search traffic, and audit AI agent consumability. This skill delegates to the growth-strategist agent for content-level analysis.

## Sub-commands

| Command | Description |
|---------|-------------|
| `growth audit <url-or-path>` | Audit existing content for keyword alignment and search intent match |
| `growth plan <topic> [--site <url-or-path>] [--competitors url1,url2]` | Research keywords, analyze gaps, and produce a prioritized content plan |
| `growth aeo <url-or-path>` | Audit content for AI agent consumability (conversational readiness, FAQ structure, citation quality) |

If no sub-command is provided, display the table above and ask which sub-command to run.

---

## Sub-command: audit

Analyze existing site content for keyword alignment, search intent match, and readability. Produces a report with issues and rewrite suggestions.

### Steps

1. Parse the argument as a URL or local file/directory path. URLs start with `http://` or `https://`. Everything else is a local path.

2. Check for brand guide:

   ```bash
   if [[ -f "knowledge-base/overview/brand-guide.md" ]]; then
     echo "Brand guide found. Will use for voice alignment."
   fi
   ```

3. Launch the growth-strategist agent via the Task tool:

   ```
   Task growth-strategist: "Audit the content at <url-or-path> for keyword alignment,
   search intent match, and readability. <if brand guide exists: Also read
   knowledge-base/overview/brand-guide.md and align rewrite suggestions with the brand voice.>
   Produce a structured report with per-page analysis, issues found, and rewrite suggestions.
   Use WebFetch for URLs or Read/Glob for local paths."
   ```

4. Present the agent's report to the user.

---

## Sub-command: plan

Research keywords, analyze content gaps, and produce a prioritized content plan. This is a self-contained workflow that combines keyword research, gap analysis, and planning.

### Steps

1. Parse arguments:
   - `<topic>` (required): the topic or keyword space to research
   - `--site <url-or-path>` (optional): the user's existing site for gap analysis
   - `--competitors url1,url2` (optional): competitor URLs for comparison

2. Check for brand guide (same as audit step 2).

3. Launch the growth-strategist agent via the Task tool:

   ```
   Task growth-strategist: "Create a content plan for the topic '<topic>'.

   1. Research keywords related to this topic using WebSearch. Classify each by search
      intent (informational, navigational, commercial, transactional) and relevance.

   2. <if --site provided: Analyze the existing content at <site> to identify gaps --
      topics where the site has no coverage or only partial coverage.>

   3. <if --competitors provided: Fetch competitor sites at <urls> via WebFetch and
      compare their content coverage against the target keywords. Skip unreachable
      competitors and note them.>

   4. Produce a prioritized content plan: P1 (high impact), P2 (medium), P3 (future).
      Each piece should include content type, target keywords, search intent, and outline.

   <if brand guide exists: Read knowledge-base/overview/brand-guide.md and align
   keyword relevance and content priorities with the brand positioning.>"
   ```

4. Present the agent's report to the user.

---

## Sub-command: aeo

Audit content for AI agent consumability at the content level. Checks whether AI models can accurately extract, cite, and quote the content.

### Steps

1. Parse the argument as a URL or local path (same heuristic as audit).

2. Launch the growth-strategist agent via the Task tool:

   ```
   Task growth-strategist: "Audit the content at <url-or-path> for AI agent consumability.
   Check conversational readiness, FAQ structure quality, definition extractability,
   summary quality, and citation-friendly paragraph structure.
   Do NOT check JSON-LD, meta tags, sitemaps, or llms.txt format -- those belong to
   the seo-aeo-analyst agent. Focus only on content-level checks.
   Use WebFetch for URLs or Read/Glob for local paths."
   ```

3. Present the agent's report to the user.
4. If technical AEO checks are also needed, suggest: "Run `seo-aeo audit` for technical SEO and AEO checks (JSON-LD, meta tags, llms.txt)."

---

## Important Guidelines

- Each sub-command is independent. No sub-command requires a prior run of another.
- The `plan` sub-command performs its own keyword research internally -- no need to run a separate research step first.
- All output is inline (displayed in the conversation). No files are written to disk.
- The growth-strategist agent handles content-level analysis. For technical SEO (meta tags, JSON-LD, sitemaps, llms.txt), direct users to the `seo-aeo` skill instead.
