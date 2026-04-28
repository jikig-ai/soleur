---
name: seo-aeo
description: "This skill should be used when auditing, fixing, or validating SEO and AEO (AI Engine Optimization) for Eleventy documentation sites. It provides sub-commands for running audits, applying fixes, and validating build output."
---

# SEO & AEO for Eleventy Docs

Audit, fix, and validate SEO and AEO (AI Engine Optimization) for Eleventy documentation sites. This skill routes to sub-commands for analysis, remediation, and CI validation.

## Sub-commands

| Command | Description |
|---------|-------------|
| `seo-aeo audit` | Audit the site for SEO/AEO issues and produce a report |
| `seo-aeo fix` | Analyze gaps and apply fixes to source files |
| `seo-aeo validate` | Run the validation script against built output |

If no sub-command is provided, display the table above and ask which sub-command to run.

---

## Phase 0: Prerequisites

<critical_sequence>

Before executing any sub-command, verify the Eleventy site structure exists.

**Required: Eleventy config**

```bash
if [[ ! -f "eleventy.config.js" ]] && [[ ! -f ".eleventy.js" ]]; then
  echo "No Eleventy config found. This skill works with Eleventy documentation sites."
  # Stop execution
fi
```

**Required for validate: Built output**

The `validate` sub-command requires a built `_site/` directory. If missing:

> No `_site/` directory found. Run `npx @11ty/eleventy` first, then re-run validate.

</critical_sequence>

---

## Sub-command: audit

Run a comprehensive SEO/AEO audit using the seo-aeo-analyst agent.

### Steps

1. Launch the seo-aeo-analyst agent via the Task tool:

   ```
   Task seo-aeo-analyst: "Audit this Eleventy documentation site for SEO and AEO issues.
   Read the site configuration, templates, and data files. Produce a structured report
   with critical issues, warnings, and passed checks. Do NOT make any changes."
   ```

2. Present the agent's report to the user
3. Offer next steps: "Run `seo-aeo fix` to apply recommended fixes, or `seo-aeo validate` to check the built output."

---

## Sub-command: fix

Analyze gaps and apply targeted fixes to source files.

### Steps

1. Launch the seo-aeo-analyst agent via the Task tool with fix instructions:

   ```
   Task seo-aeo-analyst: "Audit this Eleventy documentation site for SEO and AEO issues.
   For each issue found, apply a fix to the source files. Read each file before editing.
   After all fixes, build the site with `npx @11ty/eleventy` and run
   `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` and
   `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site` to verify.
   Report what was changed and whether validation passed."
   ```

2. Present the agent's report showing changes made
3. If validation failed, show the failing checks and offer to re-run fix

---

## Sub-command: validate

Run the standalone validation script against built output.

### Steps

1. Verify `_site/` exists. If not, build first:

   ```bash
   npx @11ty/eleventy
   ```

2. Run the validation scripts:

   ```bash
   bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site
   bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site
   ```

3. Report results:
   - **Exit 0 on both:** All SEO and CSP checks passed
   - **Exit 1:** Show failing checks and recommend running `seo-aeo fix`

Validation scripts:

- [validate-seo.sh](./scripts/validate-seo.sh) -- SEO/AEO element checks
- [validate-csp.sh](./scripts/validate-csp.sh) -- Content-Security-Policy hash integrity checks

**Known limitations:**

- validate-seo.sh only checks named AI bot entries -- wildcard `User-agent: *` blocks are not detected. A site blocking all bots via wildcard will pass validation.
- validate-csp.sh requires Python 3 for reliable multi-line HTML parsing and SHA-256 hash computation.

## Sharp edges

- **Bare-relative href sweep target list.** When dropping `<base href="/">` (or any change that defeats relative-href resolution), the sweep file list is `pages/**/*.njk`, `_includes/**/*.njk`, `index.njk`, **`404.njk`**, `llms.txt.njk`, `sitemap.njk`, `page-redirects.njk`, and `blog/**/*.md`. Siblings of `index.njk` at the docs root are easy to miss because they don't live under `pages/`. Verify post-sweep: `grep -rnE 'href="[a-z][a-z-]*/' plugins/soleur/docs/ | grep -vE 'https?:|mailto:|//'` must be empty. Inline `@font-face` `url('fonts/...')` and preload `href="css/..."` resolve against the document URL too — convert those to absolute in the same edit. See PR #2973.
- **Bulk URL change in `_data/site.json` requires Nunjucks consumer sweep.** Root-slashing nav URLs breaks any template predicate that concatenates `'/' + item.url` (silent — `aria-current` simply stops activating). Grep `_includes/**/*.njk` for every place the field is consumed (`item.url`, `link.url`) and verify each comparison still computes against the new shape. Same class as the sweep rules in AGENTS.md (`cq-raf-batching-sweep-test-helpers` et al). See PR #2973.
- **Eleventy custom date filters must guard falsy input.** `new Date(undefined).toISOString()` throws `RangeError`. Any custom Eleventy filter that delegates to the Date constructor must return null on falsy input AND the calling template must wrap its JSON-LD line in `{% if page.date %}` so a null result does not emit invalid schema.org. Example: `dateToRfc3339` in `eleventy.config.js`.
- **`validate-seo.sh` per-page substitutions need `|| true`.** Inside the per-page loop under `set -euo pipefail`, `count=$(grep -oE 'X' "$f" | wc -l)` aborts the script on zero matches because pipefail propagates grep's exit 1. Use `count=$(grep -cE 'X' "$f" || true)` — `grep -c` returns the count (0 on no match) and the rescue keeps the script alive.
