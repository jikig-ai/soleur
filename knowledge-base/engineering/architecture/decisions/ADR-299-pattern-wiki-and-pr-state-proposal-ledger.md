---
title: Pattern wiki as a sibling knowledge surface; GitHub PR state is the proposal ledger of record
status: adopting
date: 2026-10-24
amends: none
supersedes: none
issue: 8293
related: [8293, 8281, 10552, 10553, 10673, 2720, 2723]
related_adrs: [ADR-054, ADR-092, ADR-235]
brand_survival_threshold: single-user incident
---

# ADR-299: Pattern wiki as a sibling knowledge surface; GitHub PR state is the proposal ledger of record

## Status

**Adopting — 2026-10-24 (#8293, Phase 1 of the WikiSkill work deferred from #8281).** The decision is true of the code and content at merge, not of the production default. `cron-compound-promote` keeps `input: "corpus"` as the scheduled-path default; the patterns path is reachable only through the manual trigger option `input: "patterns"`. The status flips to `accepted` in the later PR that moves the cron default, and that PR is gated on the controlled input comparison recorded in the plan's `## Effect Measurement Plan` and tracked by the flip-tracker issue filed in Phase 7 of the plan. Nothing about the layer's effect on proposal yield is claimed here: the proposer has opened zero draft PRs, the first post-fix scheduled run is 2026-10-25, and #10552 is open. This ADR neither asserts nor implies that the size of the learnings corpus caused that history.

## Context

The weekly `cron-compound-promote` proposer clusters recurring learnings and drafts additive edits to `AGENTS.rules.md` or a `SKILL.md` for human review. Two gaps remain after the observability work in #8281 and the server-side fixes in #10553 and #10673:

1. **Its input is the whole learnings directory.** On 2026-10-24 the tree held 2,979 tracked non-archived learnings files; the production run of 2026-09-20 read 2,248 entries / 1,214,087 bytes (PII and retired-rule exclusions apply to what is read). Many entries are near-duplicate session records of one failure class. There is no curated, root-cause-level unit for the proposer to read.
2. **Nothing reads a closed or merged proposal.** `promotion-log.md` rows ride the proposal's own commit and are never mutated, so they cannot record a rejection, and a rejected cluster can be proposed again.

Three overlapping concepts also compete for the same job: `compound-capture` Step 7 writes to a `common-solutions.md`, its "Add to Required Reading" option and `learnings-researcher` Step 3b point at a `critical-patterns.md`. Neither file exists on disk or in any git ref on 2026-10-24; the names are retired here and only quoted in this ADR to explain the retirement.

Binding constraints, cited and not restated: ADR-054 makes `safeCommitAndPr` the sole write path for bot cron PRs (so a second PR that lands ledger rows is a forbidden second write path); ADR-092 bounds proposer edits to an additive-only allowlist; ADR-235 treats `knowledge-base/INDEX.md` as an untracked, regenerated cache.

## Considered Options

See `## Alternatives Considered` below for the full Cut List and the alternative-approaches table. The decision options in short:

- **Option A: sibling pattern wiki + PR-state ledger read through Octokit (chosen).**
- **Option B: land a ledger row on `main` through a second bot PR.** Rejected: second write path (ADR-054).
- **Option C: extend `generate-kb-index.sh` / add a `Content-Digest` ledger column.** Rejected: widens a shared script and a schema for a property the PR title already carries.

## Decision

1. **`knowledge-base/project/patterns/` is the sole surface for pattern, required-reading and common-solution knowledge.** One markdown page per recurring failure pattern (root cause, fix, evidence links to existing learnings, an `open | closed` state). It is a sibling of `learnings/`, not a child, so every reader rooted at `learnings/` excludes it by construction. A page carries `required_reading: true` in place of the retired `critical-patterns.md`; a page is added or extended by a reviewed PR. The cron never writes a pattern page (a model-authored publication surface was rejected). The page contract is defined by `plugins/soleur/skills/compound-capture/assets/pattern-page-template.md` (author-facing) and enforced by the loader in `apps/web-platform/server/compound-promote-patterns.ts` and a live-tree test; it is not restated here. Every page needs at least 5 evidence entries. The seed is at most 8 curated pages, not a backfill.
2. **The ledger of record for proposal outcomes is GitHub PR state, read through Octokit.** `promotion-log.md` rows ride the proposal's own commit (a `pending` row reaches `main` only when its proposal PR merges) and the log is never extended: no column, no schema change, and no PR-body change. Rejection state is read from the PR, not from the log.
3. **Reader contract** (patterns path only):
   - Query: `GET /search/issues` for `is:pr head:self-healing/auto-` in the repository, paged through the existing `fetchAllPages` over at most 10 pages of 100, which throws if the last page is full, so the usable ceiling is 999 hits; no `gh` CLI (absent from the runtime image).
   - Identity: a hit counts only if `user.login` equals the bot login (`soleur-ai[bot]`, one shared export) and its title matches the anchored title regex built from the same `promotePrTitle(hash, date)` the apply step uses. The hash is read from the title, because `Cluster-Hash:` is a commit trailer and not a PR-body line.
   - Suppression: exact recomputed cluster hash only. Open: suppress. Merged (`merged_at` set): suppress permanently. Closed unmerged: suppress while `now - closed_at < 60 days`, with `now` derived from the memoized run start; at exactly 60 days it lapses.
   - Failure: an unreadable ledger (API or network error, rate limit, page-cap overrun, `incomplete_results`, an unparseable `closed_at`, `drift`, or a transport failure) ends the run as a loud `status=error` with `ledger_read:"failed"` and a Sentry message; it never degrades to "suppress nothing". `drift` fires only when a bot-authored hit exists and no bot hit parses as a promote title (all bot PRs retitled); foreign-only hits (a fork or human PR on a `self-healing/auto-*` branch) and a zero-hit read are accepted as an empty ledger. The reader reads no PR comments or bodies, and the marker carries counts and closed enums only.
   - Scope: the reader runs only when `input === "patterns"`. The scheduled path gets no new step, error path or marker field.
4. **Phase gating.** `input` defaults to `corpus` until the A/B comparison in the plan passes; the cron-default flip is a separate, single-constant PR. Until then the legacy path has no suppression, and that consequence is accepted to keep the 2026-10-25 run a clean baseline. Status stays `adopting` until the flip.
5. **ADR-054 and ADR-092 are unchanged.** `knowledge-base/project/patterns/` is provably outside `TARGET_ALLOW_RE` and the `allowedPaths` literal in `apply-and-pr` (pinned by `apps/web-platform/test/server/inngest/cron-compound-promote-allowlist.test.ts`, and by the patterns-containment assertion added with the handler change in this PR). The bot has no write path to the wiki.

### Reader classification

Readers whose root is above `learnings/` were classified by reading each on 2026-10-24. "Intended" means seeing `patterns/` is correct behaviour; "excluded" means it cannot see it.

| Reader | Root | Sees `patterns/`? | Disposition |
|---|---|---|---|
| handler `walkDir` | `learnings/` | no, by construction | excluded; pinned by handler test |
| `kb-staleness-metric.sh`, `weakness-miner.sh` | `learnings/` | no | excluded by construction |
| `generate-kb-index.sh` facet pass (`kb-tags.txt`, `kb-categories.txt`) | `learnings/` | no | excluded; fixture pin |
| `generate-kb-index.sh` INDEX listing | whole KB | yes | intended: ordinary page list in a gitignored cache (ADR-235) |
| `scripts/kb-drift-walker.sh` | check 1 (broken intra-KB `.md` links): whole `knowledge-base/` minus `archive/`; check 2 (code anchors): `AGENTS*.md` plus `learnings/` | check 1 yes; check 2 no | intended for check 1 (pattern pages cite learnings by relative link, and a dead link on a published page should be reported); check 2 excluded by construction |
| `apps/web-platform/server/kb-reader.ts` (KB viewer tree, content and search routes) | the workspace `knowledge-base/` root, every `.md` | yes | intended: the viewer treats a page like any other KB file; it applies no pattern semantics and is read-only |
| `soleur:kb-search` (skill and `kb-search-cache.sh`) | facet flags scope to `learnings/`; Tier 1 filters `INDEX.md` links rooted at `knowledge-base/project/learnings/`; Tier 2 greps `learnings/` | no | excluded by construction: pattern tags never reach `--tag` facets, and pattern pages are not search hits (they are read by the proposer and by `learnings-researcher` Step 3b through the `patterns/` glob instead) |
| `scripts/learning-retrieval-bench.sh` | `LEARNINGS_ROOT`; all three callers of the corpus ranker pass `learnings-only`, and tier 1 anchors `INDEX.md` hits to the learnings prefix | no | excluded. A `kb-wide` scope exists in the ranker with no caller on 2026-10-24; if one is added, the bench would then see `patterns/` and must be re-classified |
| `scripts/backfill-frontmatter.py` | `LEARNINGS_DIR` (`os.walk`) | no | excluded; it would otherwise rewrite pattern-page frontmatter to the learnings schema |
| `.github/workflows/review-reminder.yml` | `knowledge-base/` | yes | inert: it reads `last_reviewed` / `review_cadence`, which are forbidden keys on pattern pages |
| `plugins/soleur/scripts/write-kb-coverage.ts` | `knowledge-base/` | yes | intended: counts the pages |
| markdown-lint and lefthook | repository `.md` files | yes | intended: pages are linted like any other markdown |
| `scripts/ensure-kb-index.sh` | `knowledge-base/` | yes | intended: fingerprints the pages for the regenerated INDEX cache (ADR-235) |
| `.claude/hooks/kb-domain-allowlist-guard.sh` | top-level domain directory only | yes (domain `project` is allowed) | inert: it checks the top-level domain, not subdirectories |
| `apps/web-platform/server/kb-share.ts`, `kb-document-resolver.ts`, `project-scanner.ts`, `app/api/kb/*` | workspace `knowledge-base/` | yes | intended: same family as `kb-reader.ts`, a viewer over the whole KB |
| `scripts/test-affected-kb-consumers.test.sh` | existing KB-consumer census | n/a | the existing census of KB readers; this table extends it |
| `scripts/compound-promote.sh` (legacy driver) | `learnings/` | no | excluded by construction |
| `.gitleaks.toml` | repository | yes | `patterns/` is not allowlisted, so pages are scanned in full |

## Consequences

- **Easier.** The proposer can be pointed at a small curated input (an estimate of about 22-30 KB for 8 pages with at least 5 evidence learnings, against the 1,214,087 bytes read on 2026-09-20; measured on the first manual patterns run, not asserted here). A rejected or already-proposed cluster stops being re-proposed on the patterns path. Three overlapping concepts collapse into one surface.
- **Harder or accepted.**
  - Recall is bounded by the seed: the patterns arm can only cluster what was curated.
  - Suppression is by exact hash. One added or removed evidence learning changes the hash; the 60-day TTL bounds how often that reaches a reviewer. Overlap-based suppression is a tracked contingency, not built.
  - A merged cluster stays suppressed permanently. The cluster hash is sha256 over the sorted evidence paths the model cited, and the slug is not part of it, so closing and reopening a page under a new slug does not lift a suppression. The escape hatch is a human changing the page's evidence so the model's cited set differs (a new hash); it is documented in the compound-promote runbook.
  - The PR **title** is the only identity contract. A human-retitled bot PR stops suppressing; this is counted by `ledger_title_skipped` and does not fail the read by itself (if every bot PR was retitled the read fails `drift`).
  - A first manual patterns run opens real draft PRs from an unproven seed (`dry_run` is deferred), so an interim operating rule keeps it after the 2026-10-25 scheduled run's marker is recorded and while no `self-healing/auto` PR is open (runbook).
  - Pattern pages are persistent derived text in a public repo. They carry no names, handles or tester/tenant/session-derived content. The runtime screen is `PII_REGEX` over the page text and each evidence file plus schema, path, size and symlink checks; CI additionally runs the handle, UUID and host denylist over the page text. Names or handles inside an evidence excerpt are not machine-screened: curation only. Closing a page removes it from the prompt, not from git history.
- **Residual.** The legacy corpus path has no suppression until the flip.
- **Accepted residuals (patterns path).**
  - A zero-hit ledger read is accepted as an empty ledger (the live search returns 0 today). Search-index lag can briefly return 0 after a PR opens; the consequence is at most one duplicate DRAFT PR, bounded by the week cap and human review.
  - Slot starvation: the model's clusters are sliced to the week-cap `remaining` (at most 2) before suppression, and the model is not told which hashes are suppressed, so a repeatedly proposed rejected or merged cluster can occupy the slots and end a week `no-qualifying-clusters` with `ledger_suppressed >= 1`. The slot top-up was cut by ruling.
  - Subset evasion: the model may cite any subset of at least 5 from the open pages' evidence union, so exact-hash suppression can be evaded by citing a different subset (tracked in #10977).
  - The skill-conflict guard posts a cluster's diff as a comment on an unrelated open PR and returns `skill-conflict-guard`; no PR opens, so the ledger never sees it and the same cluster can re-comment weekly while that PR stays open.
  - Per-key evidence attrition (archived, retired, PII, unreadable) is reported to Sentry only (op `pattern-evidence-dropped`); the marker does not carry it.

## Cost Impacts

None. No new vendor or billing tier. The reader reuses the existing HTTPS Octokit connection to GitHub already used by the dedup and week-cap steps; the patterns arm sends less text to the same Anthropic call.

## NFR Impacts

None moved. The ledger read is a fail-closed-loud step on a manual path only; the scheduled path's reliability profile is unchanged.

## Principle Alignment

ADR-054 (sole bot write path): Aligned — no second write path; PR state is read, not written. ADR-092 (additive-only edit boundary): Aligned — the boundary is unchanged and `patterns/` is outside it. ADR-235 (untracked regenerated cache): Aligned — the INDEX listing of pattern pages is an ordinary entry in a gitignored cache. No AP-NNN deviation.

## Diagram

The container view gains one edge and one description change in `knowledge-base/engineering/architecture/diagrams/model.c4`: the `kb` store now includes the pattern wiki (`project/patterns`), and `api -> github` is described as "cron-compound-promote reads bot-PR state through Octokit search (patterns path)". Inngest functions execute in the `api` container (`inngest -> api` invokes steps), so the edge originates there and not from `inngest`.

## Alternatives Considered

### Cut List

- Full backfill of the learnings corpus (2,979 tracked non-archived files on 2026-10-24): the size reduction is bought by a seed of at most 8 pages instead (issue constraint 8).
- A `patterns-index.md` artifact / extending `generate-kb-index.sh`: glob `patterns/*.md` frontmatter at prompt-assembly time (issue constraint 9).
- `Content-Digest` ledger column: `Cluster-Hash` already keys the PR title and branch (issue constraint 4).
- A separate bot PR to land ledger rows: forbidden second write path (ADR-054); PR state already covers the property.
- A "previously rejected" list in the model prompt: PR-derived text in a prompt is an injection path.
- Legacy-corpus fallback when no pattern is open: hides a broken seed and corrupts the A/B.
- Proposer-written pattern pages: a model-authored publication surface (legal ruling).
- `gh` CLI reader: absent from the runtime image.
- Round 2 CTO cuts, 2026-10-24: near-duplicate overlap suppression and `Ledger-Target` / `Ledger-Sources` PR-body lines (speculative hash evasion); the `self-healing/rejected` label and its creation step (the TTL satisfies "expire OR explicit marker"); slot top-up; `dry_run`, `clusters_drafted`, `patterns_digest`, the notify-only probe and its tracker (deferred to the flip tracker); a repo-wide reader census (flaky: about 234 files name the learnings path); `/compound` upsert; a `closed_reason` enum and a 40-page cap; `patterns_count`; per-hit PR detail fetches; a PR-body convention footer.

### Alternative approaches

| Approach | Why not |
|---|---|
| Land a ledger row on main via a second bot PR (constraint 3 read literally) | Second write path (ADR-054); records proposals nobody reviewed; PR state already provides the data |
| `pulls?state=all` + client filter | Newest-first over the repository's whole history; a 5-page cap silently misses older bot PRs |
| `head:` search + per-hit detail fetch | The detail budget becomes a time bomb as merged PRs accumulate; search items already carry the bound fields |
| Tell the model which clusters were rejected | PR-derived text in a prompt is an injection path |
| Overlap-based suppression and `Ledger-*` body lines | Speculative evasion defence; changes the gated PR-body write path |
| Rejection label | The TTL already satisfies "expire OR explicit marker"; the label adds a repo write and a failure path |
| Ledger on all paths from day one | Perturbs the 2026-10-25 baseline run with a new `error` path |
| Flip the cron default in this PR | Destroys the clean baseline and the controlled comparison |
| Full backfill / proposer-written pages | Constraint 8 and the legal ruling; the recall cost is accepted and measured |

## Attribution

The pattern-wiki structure (one curated page per recurring pattern, an open/closed lifecycle, evidence links, and an index the consumer reads instead of the raw corpus) is adapted from **WikiSkill**, arXiv:2608.27454 (<https://arxiv.org/abs/2608.27454>), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Changes made: the design is adapted to this repository's learnings corpus and proposer; the page schema (`status`, `closed_on`, `closed_by`, `required_reading`), the PR-state ledger reader, the exact-hash suppression rule, the fail-closed-loud failure path and the dark-launch gating are original to this decision and are not claimed to come from the source.

## References

- Plan: `knowledge-base/project/plans/2026-10-24-feat-wikiskill-pattern-layer-proposer-index-ledger-reader-plan.md` (page contract, reader contract, marker additions, effect measurement plan).
- ADR-054, ADR-092, ADR-235.
- #8293 (this work), #8281 (observability), #10553 and #10673 (server-side fixes), #10552 (open), #2720 (promotion loop), #2723 (write-mostly knowledge surfaces need a close mechanic).

## Follow-ups

The flip decision, the effect measurement and the deferred deliverables are tracked in #10977; `/compound` upserting pattern pages is tracked in #10978. Neither is a prerequisite of this decision.
