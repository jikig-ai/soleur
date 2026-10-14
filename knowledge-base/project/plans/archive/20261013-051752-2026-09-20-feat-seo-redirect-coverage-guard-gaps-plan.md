---
title: "feat(seo): close residual redirect-coverage guard gaps (reslug tombstones, runtime 301 monitor, zone-ruleset source pin)"
date: 2026-09-20
slug: feat-seo-redirect-coverage-guard-gaps
branch: feat-one-shot-8364-reslug-301-guard-gaps
issue: 8364
---

## Enhancement Summary

Deepen pass (2026-09-20, sequential-fallback — no Task tool; each review
lens applied inline). Key improvements and verified corrections:

- **Parser consumer list corrected** — `git grep` shows the real
  `bulk-redirect-pairs.ts` consumers are `seo-aeo-drift-guard.test.ts` and
  `marketing-content-drift.test.ts`; `validate-seo.test.ts` does not import
  it (earlier draft named it).
- **Helper lift confirmed, made unconditional** — `extractResourceBody`/
  `extractRuleBlocks` are file-local and already duplicated across
  `seo-rulesets-noindex.test.ts` and `seo-config-rules.test.ts`; the plan
  now lifts them once into `apps/web-platform/test/lib/terraform-hcl-blocks.ts`
  and migrates both existing suites (no third copy).
- **Guard 6 producer pinned precisely** — the freshness assertions run
  against the suite's mkdtemp Eleventy build (`tmpSite`), not a repo-root
  `_site/`.
- **Actionable RED output required** — the tombstone gate must print the
  derived URL set + a copy-paste-ready `tombstone_redirect_pairs` entry
  (spec-flow lens).
- **Second jq-filter consumer verified** — `apply-deploy-pipeline-fix.yml`
  also sources `destroy-guard-filter-web-platform.jq` (lines ~327, ~832);
  the clause change propagates to both workflows.
- **Domain skills checked** — `seo-aeo` skill confirmed the exact-match
  three-arm rationale and recorded the canonical-host-flip blind spot,
  which is now listed as an explicit out-of-scope residual rather than an
  over-claimed coverage.
- **Risks added** — generated `model.likec4.json` merge-conflict handling;
  canonical-flip blind spot; both cite verified learnings.

## Overview

Issue #8364 records the residual guard-coverage gaps surfaced by the
structural-enumeration review seat on PR #8358 (#3328 PR-B). That PR migrated
the docs site's redirects to Cloudflare edge 301s and repurposed the guards,
but the assembled guard surface still does not equal the property "every
legacy URL has a live edge 301". This plan closes the five recorded gaps: the
non-dated reslug/tombstone class (a history- or sitemap-derived expectation
set), the missing runtime 301 monitor on sampled bulk-redirect URLs (Better
Stack per ADR-204), a source-text pin for the `seo_page_redirects` zone
ruleset, a `cloudflare_list.item` clause in the apply-side `nested_deletes`
destroy guard, and two minor parser/glob correctness fixes (duplicate
`source_url` masking, non-recursive blog glob).

## Research Reconciliation — Issue vs. Codebase

Every claim in the issue body was re-measured against `origin/main` at
plan time (2026-09-20). No divergence found; two claims were sharpened.

| Issue claim | Measured reality | Consequence |
|---|---|---|
| "guards pin a snapshot of dated-post pairs and explicit redirect items" | `plugins/soleur/test/lib/bulk-redirect-pairs.ts` parses `seo-bulk-redirects.tf`, expands `local.blog_redirect_pairs` into 3 source shapes per pair and maps literal `item` blocks; `seo-aeo-drift-guard.test.ts` asserts a fixed expected map. | The expectation set is **static**: nothing enumerates URLs that *used* to exist. Confirmed gap 1. |
| "a reslugged non-dated post … can strand the old URL as a 404 while all guards stay green" | Verified constructively: `plugins/soleur/docs/blog/2026-06-12-ai-agents-cron-without-exfiltrating-secrets.md` was added and removed the same day (PRs #5205/#5215); no `source_url` covers `blog/ai-agents-cron-without-exfiltrating-secrets`. Live canonical URLs are undated (`/blog/soleur-vs-anthropic-cowork/` in sitemap) while dated aliases 301 at the edge (verified `curl` 2026-09-20). | Real, not theoretical. Seed audit corpus: `git log --diff-filter=RD -M --name-status -- plugins/soleur/docs/` returns **28** D/R events. |
| "uptime monitoring asserts 301 only for `soleur_www_redirect`" | `uptime-alerts.tf` holds exactly one `expected_status_code` monitor (`soleur_www_redirect`, `follow_redirects = false`). | Confirmed gap 2. |
| "eight `/pages/<slug>.html` rules plus Rule 9 and Rule 10 can lose a `rules {}` block silently" | `seo-rulesets.tf` `cloudflare_ruleset.seo_page_redirects` = 8 page rules (agents, skills, vision, community, getting-started, legal, pricing, changelog) + ToS rename + HTTPS/ACME catch-all = 10 `rules {}` blocks, no source-text pin exists for this ruleset (the `seo-rulesets-noindex.test.ts` precedent pins a *different* ruleset). | Confirmed gap 3. |
| "`cloudflare_list.item` shrinkage not counted by `nested_deletes`" | `tests/scripts/lib/destroy-guard-filter-web-platform.jq` header enumerates 5 nested surfaces + 1 reboot surface; `cloudflare_list` is absent. | Confirmed gap 4. |
| "duplicate `source_url` items are masked by `Map.set` last-wins" | `bulk-redirect-pairs.ts` uses `Map.set` keyed on `source_url`; the file's own comments name this a known residual. | Confirmed minor gap. |
| "non-recursive blog glob" | `scripts/validate-blog-links.sh:57` iterates `"$BLOG_DIR"/YYYY-MM-DD-*.md` — top-level only. | Confirmed minor gap. |

Sharpened facts the issue did not state:

- `apps/web-platform/infra/www-apex-canonicalizer.test.sh` pins the sibling
  `pronounceable_name` count at exactly `3` (`eq_case '3'`). Adding monitor
  resources to `uptime-alerts.tf` **reds this suite** unless the pin moves.
- `plugins/soleur/lib/heartbeat-live-reconcile.ts` `parseMonitorBlocks`
  **throws `UnresolvableDeclaration` on `for_each`** (only `count =
  var.<bool> ? 1 : 0` is resolved). A `for_each` monitor would break the
  ADR-222 live-inventory reconcile — monitors must be plain static blocks.
- `uptime-alerts.tf`'s header records that the #7798 amendment "extends no
  further" than `soleur_www_redirect`; adding sampled deep-URL probes requires
  a deliberate ADR-204 amendment, not just new resources.
- The `apply-web-platform-infra.yml` `-target=` allow-list is prose-maintained
  (`ALLOW-LIST MAINTENANCE` comment, ~line 574); `terraform-target-parity.test.ts`
  is one-directional over SSH `terraform_data` only — nothing mechanically
  forces a new monitor's `-target=` line. The pin test must assert it.
- `git ls-files '*.test.sh'` is the orphan-lint producer repo-wide; infra
  suites auto-register via `run-registered-suites.sh`'s
  `git ls-files "${SOLEUR_INFRA_DIR}/*.test.sh"` — a new infra `.test.sh`
  needs no hand registration but MUST be `git add`ed.
- `fetch-depth: 0` is already set on every ci.yml shard including the `bun`
  group (line ~903, marked LOAD-BEARING) — a git-history-derived gate can run
  inside the existing `bun test plugins/soleur/` suite with full history.

## Problem Statement

The property the migration was supposed to guarantee — "every legacy URL has
a live edge 301" — is enforced by guards whose expectation sets are
*hand-written snapshots*. Three of the five gaps share one root cause: the
protected set is enumerated by a human at guard-authoring time, so any URL
class nobody wrote down (reslugs, permalink changes, deleted pages) escapes
by construction. The fourth gap (no runtime monitor) means even a correct
source set is only *apply-time* protected: a post-apply edge failure (emptied
list, token scope loss, dashboard edit) pages nobody. The fifth
(`nested_deletes` blind spot on `cloudflare_list.item`) means the apply-side
guard itself doesn't cover the resource type that carries the bulk of the
redirect set.

## Proposed Solution

Five workstreams, each closing one recorded gap. Order is dependency-driven
(G5 parser change lands first because G1 consumes it).

### §1 — History-derived tombstone gate (gap 1)

New `plugins/soleur/test/redirect-tombstones.test.ts` (bun:test; auto-runs
inside the existing `run_suite "plugins/soleur" bun test plugins/soleur/`).

**Expectation source is git history, not a hand-maintained list** (the issue
explicitly requires this). Baseline constant `TOMBSTONE_BASELINE` = `35259f264`
(the PR-B squash merge `feat(seo): delete meta-refresh stubs + repurpose
guards (PR-B) (#8358)`, verified via `git cat-file -e`). The gate enumerates
`git log --diff-filter=RD -M --name-status <baseline>..HEAD` scoped to
`plugins/soleur/docs/` and derives, per event, the set of public URLs that
stopped being served:

- `D blog/YYYY-MM-DD-<slug>.md` → **both** families die: canonical
  `/blog/<slug>{,/,/index.html}` (fileSlug strips the date prefix; live
  sitemap confirms undated canonicals) and dated alias
  `/blog/<YYYY-MM-DD-slug>{,/,/index.html}` (live under the old GitHub Pages
  scheme — this is why `blog_redirect_pairs` exists at all). Six source
  shapes must be covered.
- `D blog/<slug>.md` (non-dated post) → `/blog/<slug>` family (3 shapes).
- `D`/`R` of any other page-emitting file under `plugins/soleur/docs/**`
  (`*.md`, `*.njk`, `*.html`; `_data/`, `_includes/`, `images/`, `css/`,
  `blog.json`, `CNAME`, `sitemap.njk`, `feed*.njk`, `llms.txt.njk` excluded)
  → read the file's `permalink:` frontmatter from the baseline blob
  (`git show <baseline>:<path>`); that path is the URL requiring coverage.
- `R` where old-derived-URL ≠ new-derived-URL → old URL requires coverage.
  A date-only rename of a dated post (`2026-03-16-x.md` → `2026-03-17-x.md`)
  keeps the canonical but strands `/blog/2026-03-16-x/` — the gate must
  require coverage of the old dated family (this is the reslug case the
  issue names and today's parity guard misses).
- Permalink **value changes** on surviving files: parse removed
  `permalink:` lines from `git log -p -G'permalink:' <baseline>..HEAD --
  plugins/soleur/docs/`; each removed value is a URL requiring coverage.

Coverage set = the union of (a) literal `source_url` items, (b)
`blog_redirect_pairs` expansion, (c) new `local.tombstone_redirect_pairs`
expansion, (d) `http.request.uri.path eq "…"` literals in
`seo_page_redirects` — all obtained by extending `bulk-redirect-pairs.ts`
rather than re-implementing an HCL parse in the test.

Every enumerated event must classify as **covered** or **exempt**; an
unclassified event is red (census, not name-list — plan-sharp-edges #11).
Exemptions live in a `TOMBSTONE_EXEMPT` map in the test file, keyed on the
deleted path, each carrying an issue ref justifying "never live" (e.g., a
draft deleted before deploy). **Failure output must be actionable** (spec-flow
lens): on red the gate prints the derived URL set, the file event that
produced it, and a copy-paste-ready `tombstone_redirect_pairs` entry —
"assert true" alone is not sufficient, per the `verify-redirect` precedent of
reporting all mismatches before exiting. Pre-baseline stragglers (the
`ai-agents-cron` case and anything else the seed audit finds) are seeded as
explicit `tombstone_redirect_pairs` entries whose source URLs are *pinned*
in `seo-aeo-drift-guard.test.ts`'s expected map — baseline..HEAD enumeration
cannot see them, so persistence is enforced by the pin, discovery by the
one-time audit.

**Seed audit (one-time, at /work):** run the gate's enumerator with
`TOMBSTONE_BASELINE` overridden to the repo root commit
(`git rev-list --max-parents=0 HEAD`) to walk all 28 all-time D/R events;
each lands in `tombstone_redirect_pairs` (with a `# tombstone: <issue/PR>`
comment) or the exemption map. Known seed: `blog/ai-agents-cron-without-exfiltrating-secrets → https://soleur.ai/blog/`.

**Terraform shape:** new `local.tombstone_redirect_pairs` map in
`seo-bulk-redirects.tf` (`source-prefix → target_url`), expanded through the
same 3-arm shape as `blog_redirect_pairs`, and `concat`'d into the local that
feeds `cloudflare_list.legal_redirects`' `dynamic "item"` block. To keep
names honest the list-feeding local is renamed `blog_redirect_items` →
`redirect_items` (= `concat(<dated expansion>, <tombstone expansion>)`);
the two existing pin sites (`seo-aeo-drift-guard.test.ts`'s
`for_each = local\.blog_redirect_items` regex and the
`dynamic "item"` presence grep in `validate-blog-links.sh`) are updated in
the same commit.

**Sharp-edge constraints honored:** git *reports* are input shapes — the
mutation matrix below exercises each `--name-status` output shape (D, R###,
delete+add pair below the `-M` threshold, `-G` permalink removal) against a
synthesized repo, per plan-sharp-edges #5. HEAD-state assertions, not
per-commit pairing, per #135. Baseline reachability is asserted loudly
(`git merge-base --is-ancestor` / `git cat-file -e` fail → gate fails, never
skips) — a shallow local clone reds rather than vacuously greens.

### §2 — Sampled runtime 301 monitors (gap 2)

Three **plain static** `betteruptime_monitor` resources in
`uptime-alerts.tf` — deliberately NOT `for_each` (the ADR-222 reconcile
parser `parseMonitorBlocks` throws `UnresolvableDeclaration` on `for_each`;
only `count = var.<bool> ? 1 : 0` is resolved). One probe per failure class:

| Resource | URL (verified live 301, 2026-09-20) | Class guarded |
|---|---|---|
| `seo_redirect_zone_ruleset` | `https://soleur.ai/pages/agents.html` → `/agents/` | `seo_page_redirects` rules{}-block loss |
| `seo_redirect_bulk_item` | `https://soleur.ai/pages/legal/privacy-policy.html` → `/legal/privacy-policy/` | `cloudflare_list` emptied / explicit-item loss |
| `seo_redirect_blog_pair` | `https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/` → `/blog/soleur-vs-anthropic-cowork/` | generated dated-pair expansion breakage end-to-end |

Attributes cloned verbatim from `soleur_www_redirect` (read in full during
the deepen pass): `monitor_type = "expected_status_code"`,
`expected_status_codes = [301]`, `follow_redirects = false`,
`remember_cookies = false` (vendor REFUSES the create without it — HTTP 422,
measured at #7798), `check_frequency = 180`, `request_timeout = 10`,
`confirmation_period = 1200`, `recovery_period = 60`, `email = true` /
`call/sms/push = false`, `team_name = "Your team"`, the
`policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null`
ternary (file convention — omitting it silently excludes the monitor from
escalation on a future paid-tier flip), `verify_ssl = true`,
`paused = false`. Each gets a distinct `pronounceable_name` (the monitor's
only operator-facing string — Better Stack has no `description` field). No
`count`/`for_each`/`lifecycle` on these blocks (W10/W11 traps documented in
the existing suite).

Edits this forces, all in the same PR:

- `.github/workflows/apply-web-platform-infra.yml`: three `-target=` lines
  beside the existing `betteruptime_monitor.*` entries (~line 706-710).
  Nothing mechanically enforces this today — the new pin test asserts it.
- `www-apex-canonicalizer.test.sh`: sibling-count pin `'3'` → `'6'` with
  updated comment; check `www-apex-canonicalizer-mutation.test.sh` for the
  same pin.
- `uptime-alerts.tf` header + ADR-204: the #7798 amendment says it "extends
  no further" than `soleur_www_redirect`; this plan adds a second amendment
  paragraph recording that sampled deep-URL 301 probes are likewise
  capability-grounded (Sentry's checker follows redirects; only Better
  Stack's `follow_redirects = false` can assert an intermediate 301) — and
  *still* not coverage grounds: three samples, not the full list.
- Quota: free-tier object cap is unresolved; per the file's own note, /work
  MUST read the `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY` marker output before
  merging the IaC (13 objects measured 2026-09-15 → +3 here).
- New runbook `knowledge-base/engineering/operations/runbooks/seo-redirect-alarm.md`
  modeled on `www-redirect-alarm.md` (which resource, what the 301 means,
  where the edge config lives, first actions). Canonical `doppler run`
  triplet verbatim per sharp edge #130.
- `model.c4` betterstack element description enumerates owned monitors —
  refresh it and regenerate `model.likec4.json` via
  `scripts/regenerate-c4-model.sh` (freshness is guarded by
  `c4-model-freshness.test.sh`).

**Why three probes, not N or one:** the issue asks for a *sampled* monitor.
Three is the smallest set that separates the three independent failure
mechanisms (zone ruleset, explicit list item, generated list item) — a
single probe on a list item cannot distinguish "list emptied" from "one
rule dropped", and zero probes on the zone ruleset leaves the issue's own
gap-3 runtime half unwatched. Per-URL monitoring of the full list is
explicitly rejected (quota unresolved; drift-guard already covers source
completeness).

**#7883 note:** `expected_status_code` cannot assert the `Location` target —
that issue stays open, but these probes now provide the "a Cloudflare-side
change reached prod un-applied" detection its re-evaluation was gated on;
the plan amends ADR-204 to say so.

### §3 — `seo_page_redirects` source-text pin (gap 3)

New `apps/web-platform/test/seo-page-redirects-ruleset.test.ts` (vitest —
`vitest.config.ts:87` collects `test/**/*.test.ts`, verified). Extracts
`resource "cloudflare_ruleset" "seo_page_redirects"` by brace counting —
the same technique as `seo-rulesets-noindex.test.ts`. Deepen finding: the
extraction helpers (`extractResourceBody`, `extractRuleBlocks`) are
**file-local and already duplicated** across `seo-rulesets-noindex.test.ts`
(:46, :73) and `seo-config-rules.test.ts` (:156, :186) — so the plan lifts
them once into a new shared `apps/web-platform/test/lib/terraform-hcl-blocks.ts`
(dir exists), migrates both existing suites to the import (two small edits),
and the new suite consumes the same module — no third copy.

Assertions (each independently mutation-load-bearing):

- `kind = "zone"`, `phase = "http_request_dynamic_redirect"`.
- Exactly **10** `rules {}` blocks.
- Rules 1-8: each carries its path literal in `expression`
  (`http.request.uri.path eq "/pages/<slug>.html"` for agents, skills,
  vision, community, getting-started, legal, pricing, changelog),
  `status_code = 301`, and a `target_url` whose value/expression resolves
  to the documented target (`/<slug>/`).
- Rule 9: `/pages/legal/terms-of-service.html` → `/legal/terms-and-conditions/`
  rename, `status_code = 301`.
- Rule 10 is **last** (ordering is load-bearing — the catch-all must trail
  the specific redirects): `not ssl` in expression, the
  `.well-known/acme-challenge` carve-out preserved, host-preserving
  `concat()` target.
- Host set `{ "soleur.ai" "www.soleur.ai" }` present in the page-rule
  expressions (both hosts redirect apex-ward per the 2026-05-18 fix).

### §4 — `cloudflare_list.item` in `nested_deletes` (gap 4)

`tests/scripts/lib/destroy-guard-filter-web-platform.jq`: add
`cf_list_item_count($side)` (`($side // {}) | [.item[]?] | length`) and a
`select(.type == "cloudflare_list")` clause inside the `nested_deletes` sum,
mirroring the existing `cf_ruleset_rules_count` arm. The filter is consumed
inline by `apply-web-platform-infra.yml` and — verified during the deepen
pass — also sourced directly by `apply-deploy-pipeline-fix.yml` at lines
~327 and ~832, so the clause propagates to both apply paths without
workflow edits.

`tests/scripts/test-destroy-guard-counter-web-platform.sh`: header
enumeration 5→6 nested surfaces; new synthesized fixture
`tests/scripts/fixtures/tfplan-cf-list-item-removal.json`
(`cq-test-fixtures-synthesized-only` — model on
`tfplan-cf-ruleset-rule-removal.json`'s shape with
`type = "cloudflare_list"` and a shrunken `item` array); a shrink arm
(nested_deletes ≥ 1 → gate reds) and a control arm (item *addition* →
nested_deletes stays 0 — additions must not page the destroy guard).

### §5 — Parser and glob correctness (minor gaps)

- `plugins/soleur/test/lib/bulk-redirect-pairs.ts`: duplicate `source_url`
  now throws `Error` naming both occurrences (last-wins masking → loud
  failure). Verify at /work that zero duplicates exist today (visual scan
  of `seo-bulk-redirects.tf` shows unique sources; the parser change itself
  is the enforcement). Both consumers (`seo-aeo-drift-guard.test.ts`,
  `marketing-content-drift.test.ts` — verified via `git grep`, NOT
  `validate-seo.test.ts`) keep working on the happy path.
- `scripts/validate-blog-links.sh:57`: non-recursive glob →
  `find "$BLOG_DIR" -type f -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md'`
  (portable POSIX find; no GNU-only flags). A dated post under a
  subdirectory then participates in parity like any top-level one.

## Technical Considerations

- **SpecFlow edge cases for the tombstone gate** (enumerated input shapes,
  one mutation row each): plain `D`; `R### old new` above `-M` threshold;
  rename below threshold arriving as `D`+`A` pair (must be treated as
  delete+create — the `D` arm already requires coverage, so this is safe by
  construction); `permalink:` removal on a surviving file; file moved out of
  `docs/` (shows as `D` under the path filter — the `ai-agents-cron` case);
  deletion of a *non-page* input (`_data`, `blog.json`) — excluded scope;
  `404.njk`/`index.njk` deletion — page-emitting, in scope (strands
  `/404.html` resp. `/`); merge-commit geometry — squash-merged main is
  linear, but the gate walks `baseline..HEAD` which includes PR-branch
  commits; `-M` rename detection applies to both.
- **False-positive discipline:** a rename whose old and new derivations are
  identical (date-only change with same fileSlug) must NOT demand a
  tombstone for the canonical URL — only for the dated family. The gate
  compares derived URL *sets*, not paths.
- **Portability (sharp edge #3):** the gate runs in CI (Linux) and locally
  on macOS — use `git log --name-status` parsing only, POSIX `find`, no
  `sed -i`/`date -d`/`readlink -f`. All prescribed commands were executed
  live during planning (see Research Insights).
- **Empty-input honesty:** `grep` with no matches exits 1 under
  `set -euo pipefail` — use the `awk 'NF'` capture idiom documented in
  `www-apex-canonicalizer.test.sh` W14; never `|| true` over an extraction
  (swallows real failures — `lint-shell-capture-exit` precedent).
- **Baseline rot:** if history is ever rewritten (it won't be, but), the
  `git cat-file -e $TOMBSTONE_BASELINE` preflight fails loudly rather than
  silently scoping the range to nothing.

## Alternative Approaches Considered

| Alternative | Rejected because |
|---|---|
| Hand-maintained `LEGACY_URLS` snapshot list (extend the existing pin pattern) | This IS the defect — issue requires a history- or sitemap-derived expectation set; another static pin strands the next reslug the same way. |
| Sitemap-diff gate (committed `_site/sitemap.xml` baseline) | Sitemap records *current* URLs; a deleted page vanishes from it, so "was live, now gone" is exactly what it cannot distinguish from "never existed". Git history is the only artifact that records both states. |
| Single `for_each` monitor over a probe map | `parseMonitorBlocks` throws `UnresolvableDeclaration` on `for_each` — would break the ADR-222 live-inventory reconcile. Three static blocks cost ~30 lines and zero machinery. |
| Monitor the full redirect list (one monitor per source) | Free-tier object quota unresolved; runtime monitoring's job is *edge-health sampling*, source completeness is already the guards' job. |
| Sentry uptime monitors instead of Better Stack | ADR-204: Sentry's checker follows redirects and asserts on the terminal response — `equals 301` is unwritable there. Capability grounds, re-confirmed. |
| Extend `nested_deletes` generically (walk all arrays) | A blanket `walk()` shrink detector would page on benign reorderings and every provider's computed arrays; the sentry scope-guard pattern (per-type clauses + enumerated coverage) is the codebase's chosen trade-off. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a 404 on a legacy URL —
  a prospect clicking an old search result, a shared link, or a stale
  bookmark hits a dead page instead of the 301 that should carry them to
  current content. Silent trust erosion on the public marketing surface.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  no data exposure — all artifacts are guards, monitors, and source pins on
  public marketing URLs; the runtime probes read three public pages.
- **Brand-survival threshold:** `single-user incident` — the property being
  guarded ("every legacy URL has a live edge 301") exists precisely because
  a stranded URL is invisible until a real visitor trips it.

## Guard Contract

### Guard 1 — redirect tombstones (history-derived coverage)

**Property.** Every page-emitting file deleted, renamed, or permalink-changed
under `plugins/soleur/docs/` since the PR-B baseline has all of its derived
public URL shapes present in the declared redirect source set, or carries a
reasoned exemption — the "every legacy URL has a live edge 301" property at
the content-history boundary.

**Assembly.** The chokepoints are two: (a) the git enumeration
(`git log --diff-filter=RD -M --name-status <baseline>..HEAD` +
`-G'permalink:'` removal lines) that produces the complete event census over
`plugins/soleur/docs/{blog,pages,*.njk,*.md,*.html}` minus non-page inputs
(`_data/`, `_includes/`, `images/`, `css/`, `blog.json`, `CNAME`,
`sitemap.njk`, `feed*.njk`, `llms.txt.njk`); and (b) the declared-source set
produced by `bulk-redirect-pairs.ts` (literal items ∪ `blog_redirect_pairs`
expansion ∪ `tombstone_redirect_pairs` expansion) unioned with the
zone-ruleset path literals. Every event must land in covered or
`TOMBSTONE_EXEMPT`; the classification is total, not a name-list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Synthetic repo: `D blog/2026-01-01-x.md` with no covering redirect source | RED |
| 2 | Same `D` with `blog/x` + `blog/2026-01-01-x` tombstoned | GREEN (control — proves the assert isn't vacuous) |
| 3 | `R` `2026-01-01-x.md` → `2026-01-02-x.md` (date-only rename; canonical unchanged) | RED unless the old dated family is covered |
| 4 | `-permalink: /old/` removal on a surviving file | RED unless `/old/` covered |
| 5 | `D` under `_data/` or `images/` | GREEN (scope exclusion works) |
| 6 | `TOMBSTONE_BASELINE` unreachable (`git cat-file -e` fails) | RED — never a silent skip |
| 7 | Delete a `tombstone_redirect_pairs` entry from a copied `seo-bulk-redirects.tf` | RED via Guard 6's expected-map pin |

### Guard 2 — sampled runtime 301 monitors

**Property.** Three independent edge-redirect mechanisms (zone ruleset rule,
explicit bulk-list item, generated dated-pair item) each have a live Better
Stack `expected_status_code = 301` probe on a declared source URL — the only
layer that detects a post-apply edge failure.

**Assembly.** The chokepoint is `uptime-alerts.tf`'s
`betteruptime_monitor` resource set (all Better Stack uptime monitors live
there) cross-read against two declaration sites —
`seo-bulk-redirects.tf` source URLs and `seo-rulesets.tf` path literals —
plus the `apply-web-platform-infra.yml` `-target=` allow-list that is the
only path the resources reach prod through. The probe-URL ⊆ declared-source
assertion is what keeps the sample anchored to the redirect set rather than
drifting to arbitrary URLs.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove one `seo_redirect_*` monitor block | RED |
| 2 | `expected_status_codes = [200]` or `follow_redirects = true` on any probe | RED |
| 3 | Point a probe URL at a path not in the declared source set | RED |
| 4 | Remove one `-target=betteruptime_monitor.seo_redirect_*` line | RED |
| 5 | Add a fourth probe with no matching declaration | RED (membership, not count) |

### Guard 3 — `seo_page_redirects` ruleset source pin

**Property.** `cloudflare_ruleset.seo_page_redirects` keeps exactly 10
`rules {}` blocks in load-bearing order — eight page redirects, the ToS
rename, and the HTTPS/ACME catch-all last — each with its path expression,
`status_code = 301`, and target preserved.

**Assembly.** The chokepoint is the single `resource "cloudflare_ruleset"
"seo_page_redirects"` block in `seo-rulesets.tf` (the zone phase entrypoint
— a whole-list replacement at apply, so the source text IS the live set).
Extraction is brace-counted per the `seo-rulesets-noindex.test.ts`
precedent; ordering is asserted because Rule 10's catch-all must trail the
specific redirects and carry the `.well-known/acme-challenge` carve-out.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete any one `rules {}` block | RED (count = 9) |
| 2 | Move Rule 10 above the first page rule | RED (ordering) |
| 3 | `status_code = 302` on a page rule | RED |
| 4 | Drop `.well-known/acme-challenge` from Rule 10's expression | RED |
| 5 | Change a page rule's target path | RED |

### Guard 4 — `cloudflare_list.item` nested-delete clause

**Property.** A Terraform plan that shrinks any `cloudflare_list`'s `item[]`
array increments `nested_deletes` and trips the apply-side destroy guard
(`[ack-destroy]` path), closing the last uncovered nested-block type in the
web-platform filter.

**Assembly.** The chokepoint is `destroy-guard-filter-web-platform.jq`'s
`nested_deletes` sum — the single counter `apply-web-platform-infra.yml`
(and the shared `apply-deploy-pipeline-fix.yml` path) reads before
permitting a non-acked apply. The clause is type-scoped
(`select(.type == "cloudflare_list")`) per the sentry scope-guard pattern;
the counter-test header's surface enumeration goes 5→6 so a future type
without a clause is loud.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture plan JSON with a `cloudflare_list` `item` removed | `nested_deletes` ≥ 1 → gate RED |
| 2 | Fixture with an `item` added | `nested_deletes` = 0 → GREEN (additions don't page) |
| 3 | Fixture with `item` reordered only | `nested_deletes` = 0 → GREEN (count-based, order-insensitive) |

### Guard 5 — parser duplicate + recursive glob

**Property.** (a) No two declared redirect entries resolve to the same
`source_url` — `Map.set` last-wins masking becomes a loud parse failure.
(b) The blog-parity enumerator covers dated posts at any depth under
`blog/`, not just top-level.

**Assembly.** (a) The chokepoint is `bulk-redirect-pairs.ts`'s item
construction — every consumer (`seo-aeo-drift-guard.test.ts`,
`marketing-content-drift.test.ts`, the new tombstone gate) reads the
redirect set through it, so the throw propagates to every guard that trusts
the map.
(b) The chokepoint is `validate-blog-links.sh`'s file enumeration — the
single producer of the file side of the parity check; `find -name` replaces
the one-level glob.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Second `item` with an existing `source_url` in a copied tf | RED (parse throws naming both sites) |
| 2 | Dated post `git mv`'d into `blog/sub/` in a sandbox | RED before fix, GREEN after (parity now sees it) |
| 3 | `tombstone_redirect_pairs` key colliding with a `blog_redirect_pairs` expansion | RED (dupes across sources throw too) |

### Guard 6 — drift-guard freshness extensions

**Property.** The declared redirect set is internally fresh: every bulk-list
`source_url` path is absent from the suite's built Eleventy output (no
live-page shadowing), and every `target_url` resolves to a built page (no
redirect-to-404 rot).

**Assembly.** The chokepoints are the same two the existing guard already
uses — `bulk-redirect-pairs.ts` as the single source-set producer, and the
suite's mkdtemp Eleventy build (`tmpSite`; `seo-aeo-drift-guard.test.ts:60`
spawns `npx @11ty/eleventy --output=<tmp>`) as the single live-URL producer —
extended so each source is checked against the build in both directions
(dead source, live target).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-create a docs page whose URL is a declared `source_url` | RED (shadowing detected) |
| 2 | Point a `target_url` at a path absent from the built site | RED (target freshness) |
| 3 | Drop one tombstone expansion arm (e.g. bare-path shape) | RED (expansion pin) |

## Implementation Phases

Phase order is dependency-driven (sharp edge #133 — contract-changing edits
before consumers).

- **Phase 0 — verification of premises.** `git cat-file -e 35259f264`;
  re-run the three probe `curl --max-time 15` checks; run the all-history
  enumerator (`git log --diff-filter=RD -M --name-status --
  plugins/soleur/docs/`) and capture its output as the audit input; read the
  latest `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY` count.
- **Phase 1 — parser (G5a, G1 precondition, RED→GREEN).** Duplicate-throw +
  tombstone expansion in `bulk-redirect-pairs.ts`; consumer updates.
- **Phase 2 — tombstone mechanism (G1, G6, RED→GREEN).**
  `redirect-tombstones.test.ts`; `seo-bulk-redirects.tf` tombstone local +
  concat + rename; seed audit results into `tombstone_redirect_pairs` +
  `TOMBSTONE_EXEMPT`; drift-guard extensions (G6) + the two pin-site updates.
- **Phase 3 — zone-ruleset pin (G3, RED→GREEN).** New vitest file; lift
  extraction helpers if needed.
- **Phase 4 — runtime monitors (G2, RED→GREEN).** Three resources,
  `-target=` lines, pin test, `sib_n` 3→6 update, runbook, ADR-204 +
  uptime-alerts.tf header amendments, `model.c4` + regenerated
  `model.likec4.json`.
- **Phase 5 — destroy-guard clause + glob fix (G4, G5b, RED→GREEN).** jq
  clause, counter-test header + fixture + arms, `find` in
  `validate-blog-links.sh`.

## Files to Edit

- `plugins/soleur/test/lib/bulk-redirect-pairs.ts` — duplicate throw;
  tombstone-pair expansion.
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts` — G6 extensions;
  `for_each = local\.redirect_items` pin rename; expected-map tombstone
  entries.
- `plugins/soleur/test/marketing-content-drift.test.ts` — verify consumer
  still green after the parser duplicate-throw (no signature change
  expected; the throw is additive).
- `apps/web-platform/test/seo-rulesets-noindex.test.ts` — consume the shared
  `terraform-hcl-blocks.ts` helpers (delete file-local copies).
- `apps/web-platform/test/seo-config-rules.test.ts` — same migration.
- `apps/web-platform/infra/seo-bulk-redirects.tf` — `tombstone_redirect_pairs`
  local, `redirect_items` concat, comments citing this issue.
- `apps/web-platform/infra/uptime-alerts.tf` — three monitor resources +
  header amendment paragraph.
- `apps/web-platform/infra/www-apex-canonicalizer.test.sh` — `sib_n` '3'→'6'.
- `apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh` — same
  pin if present (verify at Phase 4).
- `.github/workflows/apply-web-platform-infra.yml` — three `-target=` lines
  (~line 709, beside `betteruptime_monitor.app_health`).
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq` —
  `cf_list_item_count` + clause.
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` — header
  5→6 surfaces, new fixture arms.
- `scripts/validate-blog-links.sh` — recursive `find` at line 57.
- `knowledge-base/engineering/architecture/decisions/ADR-204-redirect-health-moves-to-better-stack-because-sentry-cannot-express-it.md`
  — amendment paragraph (sampled probes; #7883 re-eval gate now satisfied
  for detection, target assertion still open).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — betterstack
  element description refresh (then `bash scripts/regenerate-c4-model.sh`).

## Files to Create

- `plugins/soleur/test/redirect-tombstones.test.ts`
- `apps/web-platform/test/seo-page-redirects-ruleset.test.ts`
- `apps/web-platform/infra/seo-redirect-monitors.test.sh` (auto-registers;
  must be `git add`ed — orphan lint producer is `git ls-files '*.test.sh'`)
- `tests/scripts/fixtures/tfplan-cf-list-item-removal.json` (synthesized)
- `knowledge-base/engineering/operations/runbooks/seo-redirect-alarm.md`
- `apps/web-platform/test/lib/terraform-hcl-blocks.ts` — shared
  `extractResourceBody`/`extractRuleBlocks` (deepen-verified: the helpers are
  file-local and already duplicated across `seo-rulesets-noindex.test.ts` and
  `seo-config-rules.test.ts`).

## Open Code-Review Overlap

None. ~65 open issues were scanned during planning; #7883 (redirect target
assertion) and #8332 (GSC re-verification) are adjacent but not conflicting —
#7883 stays open with a new note; #8332 is unaffected (these probes are
additional requests, ~1.4k/day, invisible to GSC).

## Acceptance Criteria

### Pre-merge (PR)

- AC1: `bun test plugins/soleur/test/redirect-tombstones.test.ts` green,
  including the synthetic-repo mutation arms (uncovered `D` → FAIL,
  covered `D` → PASS, missing baseline → FAIL).
- AC2: `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` green with
  the extended expected map, source-dead, and target-fresh assertions.
- AC3: `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/seo-page-redirects-ruleset.test.ts` green (10 rules, ordering, ACME).
- AC4: `bash apps/web-platform/infra/seo-redirect-monitors.test.sh` green —
  incl. the probe-URL ⊆ declared-source-set cross-file assertion and the
  three `-target=` lines present in `apply-web-platform-infra.yml`.
- AC5: `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`
  green with the new `cloudflare_list.item` shrink arm FAILING closed and
  the growth arm passing.
- AC6: `bash scripts/validate-blog-links.sh` green; sandbox mutation
  (dated post in `blog/subdir/`) demonstrated red→green in the test log.
- AC7: `bash apps/web-platform/infra/www-apex-canonicalizer.test.sh` and
  `…-mutation.test.sh` green with the updated sibling-count pin.
- AC8: `bash scripts/test-all.sh scripts` and `bun` groups green (or the
  diff-scoped shard set per `/work` Phase 2 exit), incl. orphan-suite lint.
- AC9: Every `knowledge-base/` path cited in this plan either exists or is
  listed under `## Files to Create`
  (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.(md|c4|json)' <plan> |
  while read p; do [[ -f "$p" ]] || grep -qF "$p" <(sed -n '/^## Files to
  Create/,/^## /p' <plan>) || echo "BROKEN: $p"; done`) — sharp edge #43.
- AC10: `git log --diff-filter=RD -M --name-status 35259f264..HEAD --
  plugins/soleur/docs/` on the PR branch produces zero *unclassified*
  events under the gate's classifier.

### Post-merge (auto-applied; verification via gh, no operator steps)

- AC11: The `apply-web-platform-infra.yml` run for the merge commit
  succeeds (`gh run list --workflow apply-web-platform-infra.yml`).
- AC12: The next `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY`/monitors reconcile
  shows the three new monitors `matched` with zero `absent-live` /
  `unmanaged-live` violations for them.
- AC13: One synthetic probe per monitor — `curl -s -o /dev/null --max-time 15
  -w '%{http_code}' <probe-url>` returns `301` — remains true (this is what
  the monitors now assert continuously).

## Test Scenarios

The Guard Contract table is the battery; per-suite scenario lists live in
each new test file's header. Headline end-to-end scenario: *rename
`case-study-foo.md` to `case-study-bar.md` on a throwaway branch* → G1
enumerates `R`, derives `/blog/case-study-foo/` (or `pages/...` permalink),
finds no tombstone → RED; add `case-study-foo → https://soleur.ai/blog/` to
`tombstone_redirect_pairs` → GREEN. That red-to-green arc is the exact
failure the issue describes.

## Success Metrics

- The five issue-enumerated gaps each have a named, mutation-tested guard.
- Zero unclassified docs-history events at baseline..HEAD on merge day.
- Three live Better Stack monitors asserting 301 on sampled legacy URLs,
  visible in the reconcile inventory.
- No new flaky surface: all guards are deterministic source/history reads;
  no network in tests.

## Dependencies & Risks

- **Baseline assumption:** `35259f264` (PR-B squash) is the cutoff — events
  before it are the one-time audit's job; after it, the gate is self-arming.
  Risk: audit misclassifies a never-live deletion as needing a tombstone
  (harmless: an extra redirect) or vice versa (a live URL exempted —
  mitigated by requiring an issue ref per exemption).
- **Quota risk:** +3 Better Stack objects on an unresolved free-tier cap;
  mitigated by the mandated inventory read in Phase 0 and the option to
  drop to 2 probes (zone + one list item) if the cap binds.
- **History rewrite** would invalidate the baseline — the gate fails loudly
  (`cat-file -e`), never vacuously.
- **jq clause blast radius:** the `cloudflare_list` clause applies to every
  list in the web-platform root (`legal_redirects`, `www_canonical`) — a
  *legitimate* item removal now needs `[ack-destroy]`; that is the intended
  semantics (issue gap 4), and the ack path already exists.
- **for_each vs. static blocks:** chosen static to keep the ADR-222
  reconcile working; recorded so a future maintainer doesn't "clean it up"
  into a `for_each` and break `parseMonitorBlocks`.
- **Generated-artifact merge conflict (learning
  `2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict`):**
  `model.likec4.json` is a regenerated artifact — if sibling PRs touch
  `model.c4` first, regenerate after rebase rather than hand-resolving the
  JSON.
- **Documented residual blind spot (out of scope, consistent with the
  `seo-aeo` skill note):** a uniform `site.url`/canonical-host flip emits
  wrong canonicals while every 301 stays green — none of these layers (or
  the existing monitors) catch it; it is caught at review. Recorded so the
  plan doesn't over-claim coverage.

## Domain Review

- **Engineering/infra (IaC routing):** all Terraform edits land in the
  existing `apps/web-platform/infra` root — no new root
  (`hr-every-new-terraform-root-must-include-an` N/A). The apply path is the
  existing `-target=`-scoped auto-apply; three new `-target` lines are the
  only workflow change. No new `TF_VAR_*`, no minted credentials.
- **Marketing/SEO (domain/marketing label):** the guard semantics are the
  marketing property "no legacy URL 404s"; no content changes.
- **GDPR:** N/A — no personal data; probe URLs are public marketing pages;
  Better Stack sees request metadata for three static URLs (already a
  sub-processor under the existing monitors).
- **Observability (`hr-observability-as-plan-quality-gate`):** this plan IS
  an observability change — the §2 probes are the runtime layer; runbook +
  reconcile integration included. No silent-fallback code paths touched
  (`cq-silent-fallback-must-mirror-to-sentry` N/A).
- **Encryption posture:** N/A — no credential, no secret, no crypto surface;
  `scripts/encryption-posture-ledger.json` untouched.

## Architecture Decision (ADR/C4)

- **ADR:** amend ADR-204 in place (amendment paragraph, not a new ADR — the
  decision "Better Stack, because only it can assert an intermediate 301" is
  unchanged; the amendment widens *which* URLs ride that capability and
  records that the #7883 detection precondition is now met). All three C4
  model files were read for impact (`model.c4`, `views.c4`, `spec.c4`):
  `betterstack` already exists as an element and renders in both views; the
  change is a **description refresh** on that element (owned monitors list),
  no new elements/edges.
- **C4 edit:** `model.c4` betterstack element description; then
  `bash scripts/regenerate-c4-model.sh` (freshness guarded by
  `c4-model-freshness.test.sh`).

## Research Insights

- PR #8358 is `MERGED` (2026-09-19T13:17:59Z); #8364 is the residual-gap
  follow-up it spawned. #3328/#3367 closed; #8332 (GSC re-verify) open.
- Live-verified during planning (2026-09-20, `curl --max-time 15`):
  `/pages/agents.html` → 301 `/agents/`; `/pages/legal/privacy-policy.html`
  → 301 `/legal/privacy-policy/`; `/blog/2026-03-16-soleur-vs-anthropic-cowork/`
  → 301 `/blog/soleur-vs-anthropic-cowork/`. The edge works; the guards are
  what's missing.
- Canonical blog URLs are undated (`fileSlug` strips `YYYY-MM-DD-`); dated
  forms are the legacy alias family — both must be tombstoned on deletion.
- `git log --diff-filter=RD -M --name-status -- plugins/soleur/docs/` → 28
  all-time events; zero since `35259f264`. Prescribed git forms were
  live-executed at plan time (sharp edge #164).
- `www-apex-canonicalizer.test.sh` W12 pins sibling `pronounceable_name`
  count at exactly 3 — a hard trap for any new monitor in the same file.
- `parseMonitorBlocks` rejects `for_each` (`UnresolvableDeclaration`) —
  static blocks are the only compatible shape.
- Orphan-suite lint producer is repo-wide `git ls-files '*.test.sh'`;
  infra `.test.sh` suites self-register through
  `run-registered-suites.sh`'s glob — new files must be committed, nothing
  more.
- No cost/perf-savings claim is made (Phase 0.6c N/A): the plan's value is
  coverage closure on a silent-404 risk class, not a measured saving.
- Learnings applied (verified to exist):
  `2026-09-18-exact-match-bulk-redirects-need-the-bare-shape-too` (the
  three-arm expansion exists because `http.request.full_uri` matches
  exactly — tombstone expansion must inherit all three arms, not two);
  `2026-09-07-the-guard-i-wrote-died-on-the-case-it-was-written-to-catch`
  (the tombstone enumerator must not errexit-abort on empty/missing
  history — the awk-NF / explicit-empty-set idiom, already in Technical
  Considerations);
  `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop`
  (why the jq nested-delete clause and the `-target=` additions are both
  load-bearing, not redundant);
  `2026-05-29-verify-redirect-ownership-before-codifying-in-terraform`
  (probe URLs were live-curled during planning, above);
  `2026-09-11-a-post-write-probe-cannot-be-referenced-to-a-capture-taken-before-the-write`
  (post-merge verification reads live state, never the plan-time capture);
  `2026-06-09-cloudflare-bulk-redirects-v4-schema-and-phase-order`
  (schema/phase assumptions confirmed against the existing resources).

## Observability

The deliverable is itself observability for the edge-redirect surface; the
four layers below are the mechanism map, and the schema block declares the
operator-facing probe.

| Layer | Mechanism | Detects |
|---|---|---|
| Source (pre-merge) | G1/G3/G5/G6 static + history gates | redirect source deleted/renamed without tombstone; ruleset block loss; dup masking; subdirectory escape |
| Apply (merge) | G4 `nested_deletes` clause + existing `[ack-destroy]` gate | `cloudflare_list.item` shrinkage in plan JSON |
| Runtime (post-apply) | G2 three Better Stack `expected_status_code=301` probes | emptied list, token/scope loss, dashboard edit, ruleset loss — the class nothing else reaches |
| Inventory (12h) | ADR-222 reconcile (`SOLEUR_HEARTBEAT_RECONCILE_*`) | monitor drift/absence, unmanaged live monitors |

```yaml
liveness_signal:
  what: "Better Stack expected_status_code monitors on three sampled legacy URLs (seo_redirect_zone_ruleset, seo_redirect_bulk_item, seo_redirect_blog_pair)"
  cadence: "180s per probe"
  alert_target: "operator email (same channel as betteruptime_monitor.soleur_www_redirect)"
  configured_in: "apps/web-platform/infra/uptime-alerts.tf"

error_reporting:
  destination: "Better Stack email alert on failed check; pre-merge failures surface as red test-all.sh suites (redirect-tombstones, seo-page-redirects-ruleset, seo-redirect-monitors, destroy-guard counter)"
  fail_loud: "monitor DOWN alert email naming the probe's pronounceable_name; CI suite FAIL lines"

failure_modes:
  - mode: "edge 301 stops firing (list emptied, rules{} lost, token scope loss, dashboard edit)"
    detection: "Better Stack probe sees non-301 → confirmation_period 1200s → page"
    alert_route: "operator email; runbook knowledge-base/engineering/operations/runbooks/seo-redirect-alarm.md"
  - mode: "monitor resource itself deleted or drifted"
    detection: "SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors (ADR-222 reconcile) + destroy guard on the .tf delete"
    alert_route: "operator email via reconcile run"

logs:
  where: "Better Stack monitor history (per-probe); CI run logs for the static gates"
  retention: "vendor-retained (Better Stack); GitHub Actions 90d for suite logs"

discoverability_test:
  command: "grep -c 'resource \"betteruptime_monitor\" \"seo_redirect' apps/web-platform/infra/uptime-alerts.tf"
  expected_output: "3"
```

## Encryption Posture

Fires because `## Files to Edit` contains `.tf` paths. No new persistent
store and no new credential is introduced; the one new cross-component
connection is the Better Stack uptime checker probing three additional
public URLs on the same vendor→edge path `soleur_www_redirect` already uses.

```yaml
at_rest: []   # no new persistent store — monitors, guards and a jq clause only
in_transit:
  - connection: "Better Stack uptime checker -> soleur.ai edge (HTTPS GET on 3 public legacy URLs)"
    enforced_at: "apps/web-platform/infra/uptime-alerts.tf (betteruptime_monitor.seo_redirect_* url = https://…)"
    tls: "HTTPS via Cloudflare edge, TLS 1.2+ (zone settings minimum)"
    cert_verification: "on (vendor-side default; no option to disable on expected_status_code monitors)"
    does_not_defend: "redirect target correctness (#7883 — the probe asserts status 301, not the Location body); anything about the page content"
    disclosed_as: "not-publicly-claimed — no docs/legal posture cites this probe path"
```

No `exception` block — `cert_verification` is on and no
`plaintext-exception` mechanism is declared.

## References

- Issue #8364 (this work); PR #8358 (merged 2026-09-19, PR-B); issues
  #3328, #3367, #8332, #7883, #7884.
- `apps/web-platform/infra/seo-bulk-redirects.tf`, `seo-rulesets.tf`,
  `uptime-alerts.tf`, `www-apex-canonicalizer{,-mutation}.test.sh`.
- `plugins/soleur/test/lib/bulk-redirect-pairs.ts`,
  `seo-aeo-drift-guard.test.ts`, `terraform-target-parity.test.ts`,
  `plugins/soleur/lib/heartbeat-live-reconcile.ts`,
  `plugins/soleur/scripts/reconcile-live-heartbeats.ts`.
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq`,
  `tests/scripts/test-destroy-guard-counter-web-platform.sh`,
  `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` (per-type-clause
  precedent), `scripts/validate-blog-links.sh`,
  `scripts/lint-orphan-test-suites.sh`,
  `apps/web-platform/infra/run-registered-suites.sh`.
- ADR-204 (`knowledge-base/engineering/architecture/decisions/ADR-204-redirect-health-moves-to-better-stack-because-sentry-cannot-express-it.md`),
  ADR-222 (`knowledge-base/engineering/architecture/decisions/ADR-222-better-stack-database-readiness-pager-and-live-inventory.md`),
  ADR-130 (credential-scope probe precedent — not needed here:
  `betteruptime_monitor` is an already-provisioned type on the existing
  token).
- Runbook precedent:
  `knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md`.
- Prior plan:
  `knowledge-base/project/plans/archive/20260919-113408-2026-09-18-feat-blog-redirects-edge-migration-plan.md`.
- Plan sharp edges applied: #3 (portability), #5 (tool-report input
  shapes), #11 (census not name-list), #41 (vitest globs), #43 (KB path
  verification), #62 (target-allowlist sweep), #82 (operator-step
  automation gate — none needed, all automatable), #114 (`curl
  --max-time`), #130 (canonical doppler triplet in runbook), #133
  (phase ordering), #135 (HEAD-state not per-commit), #152 (beta-provider
  caveat — N/A, betteruptime provider stable), #164 (live-executed
  commands), #172 (absence-grep self-reference).
