# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8364-reslug-301-guard-gaps/knowledge-base/project/plans/2026-09-20-feat-seo-redirect-coverage-guard-gaps-plan.md
- Status: complete

### Errors
None blocking. Corrections applied during planning/deepening: fixed broken citations to ADR-204 and the www-redirect runbook; corrected the parser-consumer list (`validate-seo.test.ts` is not a consumer of `bulk-redirect-pairs.ts` — the real consumers are `seo-aeo-drift-guard.test.ts` and `marketing-content-drift.test.ts`); fixed `scripts/reconcile-live-heartbeats.ts` → `plugins/soleur/scripts/reconcile-live-heartbeats.ts`; pinned Guard 6's producer to the suite's mkdtemp Eleventy build (`tmpSite`) rather than repo-root `_site`; expanded the §2 monitor clone list to the full verified `soleur_www_redirect` attribute set (including `request_timeout`, `team_name`, `policy_id` ternary, `verify_ssl`, `paused`). Guard-contract linter passes (6 entries, rc=0); AC9 KB-path check passes; credential sweep clean; git status confirms only `knowledge-base/project/plans/` and `knowledge-base/project/specs/` artifacts touched.

### Decisions
- Tombstone expectation set derives from git history (`git log --diff-filter=RD -M --name-status 35259f264..HEAD -- plugins/soleur/docs/`) with a covered-or-exempt census, an explicit `TOMBSTONE_EXEMPT` map requiring issue refs, and a one-time seed audit back to the repo root commit — rejected a hand-maintained list and a sitemap-diff approach as structurally incapable.
- Runtime monitoring = three plain-static Better Stack `expected_status_code = 301` probes (one per redirect mechanism: zone ruleset, explicit list item, generated blog pair), deliberately not `for_each` because `parseMonitorBlocks` throws `UnresolvableDeclaration` on it and would break the ADR-222 live-inventory reconcile; per-URL monitoring of the full list rejected on unresolved free-tier quota.
- `cloudflare_list.item` nested-shrink clause added per-type (sentry scope-guard precedent) rather than a generic `walk()` over all arrays — verified the jq filter is consumed by both `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml`.
- Parser change: duplicate `source_url` throws before `Map.set` (last-wins → loud failure); blog enumeration moves to POSIX `find` for recursive coverage; shared HCL block-extraction helpers lifted to `apps/web-platform/test/lib/terraform-hcl-blocks.ts` (helpers confirmed duplicated across two existing suites).
- Canonical-host/`site.url` flip documented as an explicit out-of-scope residual blind spot rather than over-claiming coverage; #7883 stays open (status-code probes cannot assert `Location` targets).

### Components Invoked
`plan` skill (skeleton → full plan), `deepen-plan` pass applied inline via sequential-fallback (no Task tool available — each review lens applied manually and disclosed in the plan's Enhancement Summary), `gh issue view` / `gh pr view` queries, live `curl` probes of three redirect URLs, `scripts/lint-guard-contract.py`, path/learnings/rule-ID verification greps, `seo-aeo` and `docs-site` skill reviews for domain constraints, and reads of `plan-sharp-edges.md`, the ADRs, workflows, Terraform files, and test suites cited in the plan.

## Work Phase
- Status: implementation complete, all suites green; review/QA/ship pending.

### Delivered
- Guard 1: `tombstone-census.ts` + `redirect-tombstones.test.ts` (14/14) — history census over `git log --diff-filter=RD -M` vs baseline `35259f264`, covered/exempt/live classification, 8-arm mutation battery, 3 parser-mutation arms.
- Guard 2/5a: `bulk-redirect-pairs.ts` — duplicate `source_url` throws naming both items; `extractLocalMap`, `expandPrefixShapes`, `allDeclaredSources` (cross-set collision throw); `seo-aeo-drift-guard` extended (freshness + collision, 52/52); `marketing-content-drift` unaffected-green (8/8).
- `seo-bulk-redirects.tf`: `tombstone_redirect_pairs` (5 seeds, issue refs #5215/#1851/#118, live-404 verified 2026-09-20) + `tombstone_redirect_items` + `redirect_items` concat + `dynamic "item"`. `terraform fmt` clean.
- Guard 3 (agent 2cbc8eb2): shared `test/lib/terraform-hcl-blocks.ts`; `seo-page-redirects-ruleset.test.ts` 13 tests; helper migrations — vitest 36/36 across the three files.
- Guard 4 (agent 67e8034c): three static `betteruptime_monitor.seo_redirect_*` (verbatim `soleur_www_redirect` clones, [301]/no-follow/cookies-off); workflow `-target=` wiring; `seo-redirect-monitors.test.sh` 41/41; runbook `seo-redirect-alarm.md`; ADR-204 second amendment; model.c4 + regenerated `model.likec4.json` (freshness test green); canonicalizer block-scoped `_sub_monitor` fix + `eq_case 3→6`.
- Guard 4b: `destroy-guard-filter-web-platform.jq` `cf_list_item_count` + `cloudflare_list` nested-delete clause; removal fixture; shrink-RED/growth-GREEN arms — 77/77 + floor ratchet.
- Guard 6: `validate-blog-links.sh` recursive `find` (subdir-aware `file_paths`); mutation demonstrated red on unmapped nested post.
- CI registration: `seo-redirect-monitors.test.sh` step added to `infra-validation.yml` (explicit-list registration surface; `lint-orphan-test-suites` = 0 orphaned).

### Ratchets green
fixture-relative-assert 62/62 · guard-vacuity-floor 23/23 · lint-trap-tempfile 20/20 · plan-gate-preamble 41/41 · destroy-guard 77/77 · c4-model-freshness PASS · validate-blog-links all-pass · terraform fmt clean.

### Known notes
- Recursive-enumeration mutation fixture lacked `date:` frontmatter → Eleventy `dateToRfc3339` error is expected noise; the load-bearing signal (parity FAIL on unmapped nested post) fired correctly.
- Pre-existing unrelated reconcile mismatch (`soleur-git-data-prd` absent-live) untouched — not this issue's scope.
- PR #8430 body is placeholder; ship step must write `Closes #8364` + `Ref #7883` + `## Changelog`.

## Review Phase (11-seat panel + Semgrep + ShellCheck)
- Semgrep 79 rules / 0 findings; ShellCheck `-S error` clean on all three shell suites.
- **P1 fixed — comment-spoofable guards**: `seo-page-redirects-ruleset.test.ts` extracted from RAW tf (a `/* */`-wrapped `rules {}` still counted). Fix: `stripHclComments` lifted into `test/lib/terraform-hcl-blocks.ts` (deduping seo-config-rules.test.ts's local copy, plus `quotedAttr`/`escapeRegExp`), all consumers strip before extracting, two raw-source mutation arms added (block-comment around a rule, `#`-commented resource header).
- **P2 fixed — census holes**: `enumeratePermalinkEvents` replaces the removal-only scan — any `permalink:` diff line triggers a commit^/commit URL-set diff, so reslug-by-ADDITION is caught. Nested `blog/sub/` posts derive via fileSlug (`/blog/<slug>/`, never `/blog/<sub>/`). Renames landing OUTSIDE docsPrefix re-serve nothing. `permalink: false` emits nothing. `core.quotePath=false` + loud throw on still-quoted paths. `--is-shallow-repository` check added to the anchor preflight. Dead `range` param removed; `TOMBSTONE_BASELINE` renamed `HISTORY_ANCHOR`.
- **Real catch**: the widened census found 12 genuinely stranded URLs — the `/pages/legal/<slug>/` dir families died at 871fc0583 (#1865) when permalinks were added; the bulk list only covered the `.html` file-shape. Four `tombstone_redirect_pairs` entries added.
- **P2 fixed — dynamic item unpinned**: `dynamicItemBlock(tf)` extractor + attribute pins (for_each, source/target wiring, 301, subdomains, query-string) in the drift guard's expansion test.
- **P2 fixed — monitor source scoping**: `LITERAL_SOURCES` now scoped to `cloudflare_list.legal_redirects` (was file-wide — the `www_canonical` list could satisfy it); `PAIR_SOURCES` scoped to `blog_redirect_pairs` (was `*_redirect_pairs`, conflating tombstones). `strip_comments` gained `/* */` handling in both shell suites (kept identical). Cadence pins added per probe (check_frequency/timeout/confirmation/recovery/verify_ssl/https scheme) — 41→59 cases.
- **P3 fixed**: `validate-blog-links.sh` tf reads moved to a comment-stripped copy; dated-basename collisions across nested dirs now fail loudly.
- **Filed as residual** (out of scope, documented): `heartbeat-live-reconcile.ts` doesn't diff `expected_status_codes` on the live side; merge-commit-only deletions invisible to `git log -p`; `_data`/`eleventyComputed` death classes need a design pass; `allDeclaredSources` scope is single-file.
- Post-fix suites green: tombstones 18/18, ruleset pins 38/38 (vitest), monitors 59/59, canonicalizer 41/41 + mutation 28/28, blog parity all-pass, drift guard 52/52.
