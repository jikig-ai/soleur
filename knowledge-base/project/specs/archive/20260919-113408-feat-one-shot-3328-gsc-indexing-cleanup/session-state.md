# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-18-feat-blog-redirects-edge-migration-plan.md
- Status: complete (plan + deepen-plan, all gates resolved inline — sequential-fallback, disclosed in plan). **Re-selected as PR-B authority on 2026-09-19 resume** — frontmatter `branch:` matched; `## Acceptance Criteria` present → finished plan, not re-authored.
- Evidence: knowledge-base/project/specs/feat-one-shot-3328-gsc-indexing-cleanup/gsc-evidence.md (live GSC pull 2026-09-18, all 76 URLs curl-verified)
- Follow-up filed during planning: #8332 (GSC re-verification ~2–4 weeks post-merge)
- 2026-09-19 premise refresh (PR-B planning resume, cheap pass — no re-research):
  - PR-A #8331 MERGED 2026-09-18T19:52:20Z; `blog_redirect_pairs` + `dynamic "item"` present on this branch via main (`seo-bulk-redirects.tf:67,:291`).
  - No merged PR landed PR-B scope: `gh pr list --search "3328 in:body" --state merged` → only #8331/#5082/#3296; `gh pr list --state merged --search "validate-seo OR pillars.js OR pageRedirects"` → nothing newer than the plan date touching the PR-B file list.
  - All 4 deletion files exist; all 9 PR-B edit targets exist with their plan anchors intact (validate-seo.sh:143 skip block; validate-blog-links.sh:84–98 stub-existence block; drift-guard tests at :487/:507; validate-seo.test.ts:308; stale `page-redirects.njk` refs at sitemap.njk:9, SKILL.md:127, seo-bulk-redirects.tf:27).
  - Issue #3328 still OPEN.
  - Live verification 2026-09-19: all 19 `pageRedirects` `from` paths → 301 with correct targets; spot-check of new blog date-slug 301s (all 3 URL shapes) green; `www.` single-hop green; canonical → 200.

### Errors
- None blocking. `gh issue create` needed filing-gate fields (resolved → #8332). Two plan claims self-corrected in deepen (include_subdomains enumeration; #3379 status → closed).

### Decisions
- Static `local.blog_redirect_pairs` + `dynamic "item"` inside existing `cloudflare_list.legal_redirects` (avoids exactly-2-rules guard; zone quota full 10/10 → account-level Bulk Redirects).
- Two-merge sequencing: PR-A additive infra → verify 69/69 live 301s → PR-B deletions + guards + internal links. This branch = PR-A scope.
- api.soleur.ai X-Robots-Tag = no work (rule exists, dormant on DNS-only CNAME, #3379 closed).
- Internal links via existing machinery: 2 new pillars.js series + 2 footerLegal entries + `pillar:` frontmatter on 14 posts.

### Components Invoked
- soleur:plan (SKILL.md executed manually — no skill tool in subagent harness)
- soleur:deepen-plan (same, gates 4.4–4.11 inline)
- lint-guard-contract.py (PASS), lefthook lint-infra-no-human-steps (PASS)
- gh issue create → #8332

## Work Phase
- Status: **PR-A MERGED via #8331 (2026-09-18T19:52:20Z) and verified live** — 69/69 blog date-slug URLs → 301 (see 2026-09-18 comment on #3328; tasks.md 1.3/1.4 checked 2026-09-19). `seo-bulk-redirects.tf` on main carries the 23-pair map + `dynamic "item"` block (69 generated + 13 explicit = 82 items).
- Review Phase (PR-A): 4-agent panel (pattern, security, git-history, code-quality) — 8 findings, all P3, all fixed inline before merge.
- **This branch is now PR-B scope** (Phase 2, tasks.md 2.1–2.7): delete the 4 meta-refresh files, repurpose CI guards (Guard 1 parity + Guard 2 zero-stub fence), remove the validate-seo skip block, land internal-link equity edits (pillars.js ×2 series, site.json footerLegal ×2, `pillar:` frontmatter on 14 posts). Plan remains the authority — all PR-B anchors re-verified present 2026-09-19.
- PR-B merge precondition satisfied: Phase-1 apply verified live (69/69). Per-item `pageRedirects` re-curl (2.1) green at planning-resume; must be re-run and pasted into PR evidence at implementation time.
- **PR-B implementation complete 2026-09-19** (tasks.md 2.1–2.6 all checked):
  - 2.1 re-curl: 19/19 `from` paths → 301 green immediately pre-deletion (FAILURES=0).
  - 5 files deleted (4 prescribed + `pages/articles.njk` — scope expansion, see tasks 2.2.5): a 5th hand-maintained stub the plan missed, found by the Guard-2 `_site` walk. Migrated to `cloudflare_list.legal_redirects` (+3 items `/articles/` shapes → `/blog/`) + deleted same-PR.
  - Guard 1 (parity) rewritten in `validate-blog-links.sh` — bidirectional + anti-vacuity floor; both mutation directions killed live.
  - Guard 2 (zero-stub fence) + tf-source assertions landed in `seo-aeo-drift-guard.test.ts`; `validate-seo.sh` skip block removed; flipped test in `validate-seo.test.ts`.
  - Internal-link equity: 2 new `pillars.js` series + `pillar:` on 14 posts (16 keys total incl. 2 pre-existing) + 2 `footerLegal` entries. In-prose links declined.
  - Verify: clean `_site` build (needed `rm -rf _site` — eleventy doesn't prune), zero `http-equiv="refresh"`, asides + footer rendered, host-mangle clean, bun 69/0, parity green, `terraform validate` green.
  - Phase-2 exit: GDPR gate skipped (diff matches no canonical-regex path); touched-shard gate REFUSED (2 sibling full-gate runs) → per-suite substitutes all green (validate-seo + drift-guard 69/0, canonicalizer 41/41, ssl-mitigation 10/10, canonicalizer-mutation 28/28, workflow-model-pins 12/0, lint-shell-capture-exit 25/0); infra shard deferred to ship Phase 4.
