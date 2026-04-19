# Tasks: Fix JSON-LD dump filter escaping (#2609)

Plan: `knowledge-base/project/plans/2026-04-19-fix-jsonld-dump-filter-plan.md`

## 1. Setup

1.1. Verify `bun --version` and `npx @11ty/eleventy --version` work in worktree.
1.2. Confirm the base.njk (lines 29-113) and blog-post.njk (lines 9-42) JSON-LD blocks match the plan's enumeration (31 total interpolations: 19 + 12). Read both files fresh; if the counts have drifted, update the plan counts before proceeding.

## 2. RED — Failing Test

2.1. Create fixture directory `plugins/soleur/test/fixtures/jsonld-escaping/` with:
   2.1.1. `_data/site.json` (minimal stub — name/url/github/x/linkedinCompany/bluesky/discord/author/description required by template).
   2.1.2. `_data/plugin.js` (stub returning `{ version: "1.2.3" }`).
   2.1.3. `_includes/base.njk` and `_includes/blog-post.njk` — copied from production (pre-fix state).
   2.1.4. `test-post.njk` with weaponized title and description (see plan Research Insights).
   2.1.5. Minimal `eleventy.config.js` that registers the `dateToRfc3339` filter.
2.2. Create `plugins/soleur/test/jsonld-escaping.test.ts` with the five test cases from plan Research Insights:
   2.2.1. JSON.parse succeeds on all homepage JSON-LD blocks.
   2.2.2. BlogPosting headline and description round-trip byte-for-byte to weaponized input (use `.toBe(...)` — pin exact post-state).
   2.2.3. Forbidden-entity drift-guard (`&quot;`, `&amp;`, `&lt;`, `&gt;`, `&#39;`) absent from every JSON-LD block.
   2.2.4. Empty-string-field drift-guard (catches retained outer quote bug).
   2.2.5. Source-file interpolation-coverage assertion (every `{{...}}` inside the JSON-LD block matches `| dump | safe`).
2.3. Run `bun test plugins/soleur/test/jsonld-escaping.test.ts`. Verify RED (tests 2.2.1, 2.2.2, 2.2.3, 2.2.5 fail; 2.2.4 passes trivially against the pre-fix template).
2.4. Commit the RED state: `test(docs): add JSON-LD escaping regression tests (RED)`.

## 3. GREEN — Template Fix

3.1. Edit `plugins/soleur/docs/_includes/base.njk` lines 29-113:
   3.1.1. Replace each direct interpolation (`"name": "{{ site.name }}"`) with `"name": {{ site.name | dump | safe }}` — **drop the outer quotes**.
   3.1.2. Replace each concatenation (`"url": "{{ site.url }}{{ page.url }}"`) with `"url": {{ (site.url + page.url) | dump | safe }}` — parenthesize before `| dump`.
   3.1.3. Handle all five `sameAs` URL entries identically (github, x, linkedinCompany, bluesky, discord).
   3.1.4. Add leading comment inside the `<script>` block: `{# All string interpolations MUST use | dump | safe — see #2609 #}`.
3.2. Edit `plugins/soleur/docs/_includes/blog-post.njk` lines 9-42:
   3.2.1. Replace the 12 interpolations following the same rules.
   3.2.2. Handle the `dateModified` ternary: `{{ (updated | dateToRfc3339 if updated else date | dateToRfc3339) | dump | safe }}`.
   3.2.3. Handle the `jobTitle` concat: `{{ (site.author.role + " of " + site.name) | dump | safe }}`.
   3.2.4. Add the same leading comment.
3.3. Run `bun test plugins/soleur/test/jsonld-escaping.test.ts`. Verify GREEN — all five cases pass.
3.4. Commit the GREEN state: `fix(docs): JSON-safe escape all JSON-LD interpolations via | dump filter`.

## 4. Hygiene Sweep Verification

4.1. Run the Phase 3 grep from the plan against `base.njk` and `blog-post.njk`. Paste both outputs into a local scratch file for inclusion in the PR body.
4.2. Run `npx @11ty/eleventy` locally. Confirm exit 0 and `_site/index.html` + `_site/blog/<any-post>/index.html` both exist.
4.3. Run a spot-check `node -e` one-liner extracting each JSON-LD block from each emitted HTML file and `JSON.parse`-ing them.

## 5. Full Suite + Build

5.1. `cd <worktree> && bash scripts/test-all.sh`. Must be fully green.
5.2. Re-verify `plugins/soleur/test/validate-seo.test.ts` unchanged (it greps JSON-LD shape, so it is the adjacent regression guard).

## 6. Ship

6.1. Run `skill: soleur:compound` to capture any session learnings.
6.2. Run `skill: soleur:ship` — it will:
   6.2.1. Set `semver:patch` label (bug fix).
   6.2.2. Write the PR body including the hygiene-sweep grep output + `Closes #2609`.
   6.2.3. Push branch and open the PR.
6.3. Poll `gh pr view <N> --json state --jq .state` until MERGED, then run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`.

## 7. Post-Merge Operator Tasks

7.1. Verify Cloudflare Pages deploy succeeded for `soleur.ai`.
7.2. Run Google Rich Results test against `https://soleur.ai/` — confirm WebSite + WebPage + Organization + SoftwareApplication nodes detected.
7.3. Run Rich Results test against any `https://soleur.ai/blog/<post>/` — confirm BlogPosting detected.
7.4. In 14 days, check Google Search Console → Enhancements for any drop in Organization/Article coverage. If drop detected, file a follow-up issue (not expected — `dump` produces standards-compliant JSON).

## Hard-Rule Compliance Checklist

- [ ] `cq-write-failing-tests-before` — test committed in step 2.4 before fix in step 3.4.
- [ ] `cq-mutation-assertions-pin-exact-post-state` — `.toBe(WEAPONIZED_TITLE)` in test 2.2.2.
- [ ] `cq-in-worktrees-run-vitest-via-node-node` — N/A (bun:test, not vitest).
- [ ] `cq-always-run-npx-markdownlint-cli2-fix-on` — markdownlint run on plan + tasks before commit.
- [ ] `cq-docs-cli-verification` — every CLI token in the plan (`npx @11ty/eleventy`, `bun test`) verified via `package.json` scripts and live-executed Nunjucks check. No fabricated flags.
- [ ] `wg-when-a-pr-includes-database-migrations` — N/A (no migrations).
- [ ] Post-merge ops steps listed under `### Post-merge (operator)` in the plan's Acceptance Criteria.
