# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-12-fix-gsc-duplicate-canonical-best-plugins-plan.md
- Status: complete

### Errors
None. CWD verified as the worktree (not bare-root). Branch safety passed (not main). All deepen-plan halt gates (4.6/4.7/4.8/4.9) passed. All cited file/learning paths resolve. Plan + tasks committed and pushed.

### Decisions
- Both routing-brief premises FALSIFIED by live evidence: (1) `base.njk:7` `{{ site.url }}` = apex `https://soleur.ai`, NOT `www`; apex self-canonical is correct. (2) `distribution-content` file is outbound social promotion (UTM links back to soleur.ai), not republished article text — no external syndicated copy lacking canonical-back. Web search found only independent competing listicles.
- Root cause = benign `www→apex` 301 consolidation (live `curl` confirmed www→301→apex per #4584 canonicalizer; apex→200 self-canonical). GSC "Google chose different canonical than user" = Google correctly consolidated the www variant onto the apex self-canonical. Matches precedent `2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build.md`.
- Outcome: NO required repo code change. Resolution = operator clicks GSC VALIDATE FIX + wait (~2-4 weeks; report only 6 days old). VALIDATE FIX has no API and is SSO/CAPTCHA-gated — a sanctioned operator-only step.
- One OPTIONAL CI hardening (Phase 2, fold-in or defer): `validate-seo.sh` per-page canonical check asserts presence only, not that href host = apex — a future `site.url`→www regression would pass silently. ~10-line host-value gate available.
- Out-of-scope confirmed clean: PR #4729 (Page-with-redirect class) still MERGED; AC5 asserts sitemap still emits zero redirecting locs — no regression, no new action.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Agent: soleur:engineering:research:learnings-researcher
- Agent: Explore
- WebSearch, WebFetch, Bash curl probes, gh pr view
