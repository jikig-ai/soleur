---
name: seo-aeo
description: "This skill should be used when auditing, fixing, or validating SEO and AEO (AI Engine Optimization) for Eleventy documentation sites. It provides sub-commands for running audits, applying fixes, and validating build output. Triggers on \"seo audit\", \"check seo\", \"aeo\", \"llms.txt\", \"validate seo\", \"seo fix\"."
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
   `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` to verify.
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

2. Run the validation script:

   ```bash
   bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site
   ```

3. Report results:
   - **Exit 0:** All SEO checks passed
   - **Exit 1:** Show failing checks and recommend running `seo-aeo fix`

Validation script: [validate-seo.sh](./scripts/validate-seo.sh)
