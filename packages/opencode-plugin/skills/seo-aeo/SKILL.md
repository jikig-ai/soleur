---
name: seo-aeo
description: "This skill should be used when auditing, fixing, or validating SEO and AEO (AI Engine Optimization) for Eleventy documentation sites. It provides sub-commands for running audits, applying fixes, and validating build output."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

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

Run a comprehensive SEO/AEO audit using the soleur:marketing:seo-aeo-analyst agent.

### Steps

1. Launch the soleur:marketing:seo-aeo-analyst agent via the Task tool:

   ```
   Task soleur:marketing:seo-aeo-analyst: "Audit this Eleventy documentation site for SEO and AEO issues.
   Read the site configuration, templates, and data files. Produce a structured report
   with critical issues, warnings, and passed checks. Do NOT make any changes."
   ```

2. Present the agent's report to the user
3. Offer next steps: "Run `seo-aeo fix` to apply recommended fixes, or `seo-aeo validate` to check the built output."

---

## Sub-command: fix

Analyze gaps and apply targeted fixes to source files.

### Steps

1. Launch the soleur:marketing:seo-aeo-analyst agent via the Task tool with fix instructions:

   ```
   Task soleur:marketing:seo-aeo-analyst: "Audit this Eleventy documentation site for SEO and AEO issues.
   For each issue found, apply a fix to the source files. Read each file before editing.
   After all fixes, build the site with `npx @11ty/eleventy` and run
   `bash "${CLAUDE_PLUGIN_ROOT}/skills/seo-aeo/scripts/validate-seo.sh" _site` and
   `bash "${CLAUDE_PLUGIN_ROOT}/skills/seo-aeo/scripts/validate-csp.sh" _site` to verify.
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
   bash "${CLAUDE_PLUGIN_ROOT}/skills/seo-aeo/scripts/validate-seo.sh" _site
   bash "${CLAUDE_PLUGIN_ROOT}/skills/seo-aeo/scripts/validate-csp.sh" _site
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

- **Bare-relative href sweep target list.** When dropping `<base href="/">` (or any change that defeats relative-href resolution), the sweep file list is `pages/**/*.njk`, `_includes/**/*.njk`, `index.njk`, **`404.njk`**, `llms.txt.njk`, `sitemap.njk`, and `blog/**/*.md` (`page-redirects.njk` was deleted in #3328 — the meta-refresh redirect machinery now lives entirely at the Cloudflare edge). Siblings of `index.njk` at the docs root are easy to miss because they don't live under `pages/`. Verify post-sweep: `grep -rnE 'href="[a-z][a-z-]*/' plugins/soleur/docs/ | grep -vE 'https?:|mailto:|//'` must be empty. Inline `@font-face` `url('fonts/...')` and preload `href="css/..."` resolve against the document URL too — convert those to absolute in the same edit. See PR #2973.
- **Bulk URL change in `_data/site.json` requires Nunjucks consumer sweep.** Root-slashing nav URLs breaks any template predicate that concatenates `'/' + item.url` (silent — `aria-current` simply stops activating). Grep `_includes/**/*.njk` for every place the field is consumed (`item.url`, `link.url`) and verify each comparison still computes against the new shape. Same class as the sweep rules in AGENTS.md (`cq-raf-batching-sweep-test-helpers` et al). See PR #2973.
- **Eleventy custom date filters must guard falsy input.** `new Date(undefined).toISOString()` throws `RangeError`. Any custom Eleventy filter that delegates to the Date constructor must return null on falsy input AND the calling template must wrap its JSON-LD line in `{% if page.date %}` so a null result does not emit invalid schema.org. Example: `dateToRfc3339` in `eleventy.config.js`.
- **`validate-seo.sh` per-page substitutions need `|| true`.** Inside the per-page loop under `set -euo pipefail`, `count=$(grep -oE 'X' "$f" | wc -l)` aborts the script on zero matches because pipefail propagates grep's exit 1. Use `count=$(grep -cE 'X' "$f" || true)` — `grep -c` returns the count (0 on no match) and the rescue keeps the script alive.
- **A GSC "Page with redirect" cluster is usually Google's historical memory, not a live sitemap leak.** The affected-URL list is dominated by URLs Google learned before a canonicalization (www→apex, `.html`→clean, `?ref=` query forms) that now 3xx **correctly** — it self-heals server-side as Google re-crawls; there is no repo defect to chase. The only actionable repo condition is a *redirecting* URL present in the *built `sitemap.xml`*. Verify THAT specific condition against a fresh `npx @11ty/eleventy` build (`grep -oE '<loc>[^<]+</loc>' _site/sitemap.xml | grep -E '(\.html$|/pages/)'` must be empty); do not treat the GSC URL list as a bug list. The redirect-stub gate in `validate-seo.sh` enforces it at deploy/CI time. See `knowledge-base/project/learnings/2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build.md`.
- **A GSC "Duplicate, Google chose different canonical than user" report on a `www` (or other non-canonical-variant) URL is the same benign class** — Google followed the variant's 301 to the apex, read the apex page's correct self-canonical, and consolidated the variant onto it (working correctly). Verify via live `curl`: variant → `301` → apex, apex → `200`, apex canonical self-referential. The fix is operator **VALIDATE FIX** in GSC + wait ~2-4 weeks, NOT a code change — and never "correct" `site.url` to `www` (the inverse of the #4573 apex flip; would emit a redirecting canonical site-wide). The per-page canonical-host gate in `validate-seo.sh` asserts each page's canonical host matches the sitemap host (catches a template regression; a uniform `site.url` flip is covered by NEITHER uptime monitor, and saying otherwise is the defect #7798 exists to fix. A flip changes the canonical tags the site EMITS; it does not touch the Cloudflare Bulk Redirect, so `betteruptime_monitor.soleur_www_redirect` still sees www 301 to the apex and stays green, as does the Sentry reachability probe. The predecessor claim named `sentry_uptime_monitor.soleur_www`, which additionally could never pass at all. A uniform flip is caught at review, not by an alarm). See `knowledge-base/project/learnings/2026-06-12-gsc-duplicate-canonical-on-www-variant-is-benign-consolidation.md`.
- **Cloudflare Bulk Redirects match `http.request.full_uri` exactly — enumerate every client-reachable shape, not the shapes the replaced machinery emits.** Migrating an origin redirect to `seo-bulk-redirects.tf` needs one item per form: `/<path>/`, `/<path>/index.html`, AND the bare `/<path>` (no trailing slash). The origin's trailing-slash normalization masks a missing bare item today; deleting the origin stub removes the mask and that form 404s. See `knowledge-base/project/learnings/2026-09-18-exact-match-bulk-redirects-need-the-bare-shape-too.md`.
- **Deleting a build input does not delete its output — verify stub/template removal on a clean `_site`, and fence the emitted signature, not the file size.** Eleventy incremental builds never prune removed templates, so a deleted `articles.njk` still served `_site/articles/index.html` until `rm -rf _site && bunx @11ty/eleventy`. The oracle for "no stubs remain" is a semantic grep over a fresh build (`grep -rl 'http-equiv="refresh"' _site` must be empty) at any size — a byte-threshold predicate lets a layout-wrapped meta refresh escape, and a plan's enumerated file list missed a fifth stub the grep found. See `knowledge-base/project/learnings/workflow-issues/guard-content-not-mechanism-stub-deletion-20260919.md`.
