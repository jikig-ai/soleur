---
title: "feat(harness): WikiSkill pattern layer + proposer index/ledger reader"
type: feat
date: 2026-10-24
slug: wikiskill-pattern-layer-proposer-index-ledger-reader
branch: feat-one-shot-8293-wikiskill-pattern-layer
issue: 8293
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat(harness): WikiSkill pattern layer + proposer index/ledger reader

> Spec lane: no spec.md exists for this branch (the 2026-09-18 spec is archived and its Phase 1 was
> narrowed at plan review), so `lane:` defaulted to `cross-domain` (fail-closed).
> PR body wording: `Ref #8293` (never `Closes`); `Ref #10552` only where relevant, never `Closes`.

## Overview

Phase 1 of the WikiSkill work deferred from #8281 and gated on #8293. It is deliberately small and
**dark-launched**: nothing changes on the scheduled path, so the 2026-10-25 run (the first that can
reach the gates) stays a clean baseline.

1. **A pattern layer** at the sibling top-level `knowledge-base/project/patterns/`: one markdown page
   per recurring failure pattern (root cause, fix, evidence links to existing learnings, an
   `open | closed` state). Seeded with **at most 8** curated pages, not backfilled.
2. **An `input` switch** on the manual-trigger event of `cron-compound-promote.ts`:
   `input: "patterns"` replaces the ~2,250-file learnings dump with the open-pattern index plus the
   first 10 lines of each pattern's evidence learnings. The scheduled path and the default stay `corpus`.
3. **A ledger reader, active on the patterns path only**: before the model call the handler reads prior
   proposal outcomes through Octokit (PR state of `self-healing/auto-*` branches) and, after the model
   call, suppresses a cluster whose recomputed hash was already proposed (open, merged, or closed
   within 60 days). Every suppression is a `ledger-suppressed` refusal in the outcome marker; an
   unreadable ledger ends the run as a loud `status=error`, never as silent zero output.
4. **One surface for three overlapping concepts**: `compound-capture` Step 7 (`common-solutions.md`),
   its "Add to Required Reading" option and `learnings-researcher` Step 3b (`critical-patterns.md`) all
   retarget to `patterns/`, read-only in Phase 1. Neither named file exists today and neither is created.

**What this plan does NOT claim.** The proposer has opened zero draft PRs. The refusals that explain
that sat downstream of the prompt (`diff-underivable-apply`, fixed server-side in #10553; sub-quorum
clusters, fixed in #10673), and the first post-fix scheduled run is 2026-10-25. The premise "the
2,309-file dump is why ten weeks produced zero PRs" is **untested**; neither this plan nor its PR body
asserts it. The layer's effect is unmeasured until #10552 clears; `## Effect Measurement Plan` says
how it is measured afterwards.

**Out of scope, by instruction:** commenting on or closing #10552; starting #10550 (Phase 2) or #10551
(Phase 3). **Deferred by ruling (tracked, see Phase 7):** `dry_run`, the measurement probe, the cron
default flip, slot top-up, near-duplicate overlap suppression, a rejection label, `/compound` upsert,
a PR-body convention footer.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (verified 2026-10-24) | Plan response |
|---|---|---|
| "seed from `weakness-digest.md` (~18 clusters)" | The committed digest is a 7-day window: 1 cluster, 3 learnings. It is rewritten weekly by `weakness-miner.yml`. The same miner at `SOLEUR_WM_WINDOW_DAYS=90` into a scratch path yields 218 heavily overlapping tag-pair clusters (e.g. `guards + mutation-testing - 62`) | Seed from the digest's own generator at 90 days (scratch path), curated by hand into at most 8 pages. The clusters are tag co-occurrence groups, not root-cause patterns |
| "2,309-file corpus dump" | 2,979 tracked non-archived learnings files today; the 2026-09-20 production run read 2,248 entries / 1,214,087 bytes (PII and retired-rule exclusions apply) | Quote only measured figures with their date; re-measure with `git ls-files` at work time |
| "exclude `patterns/` from all four corpus readers" | The sibling location excludes it by construction from `walkDir` (roots at `learnings/`), `kb-staleness-metric.sh` (`LEARNINGS_ROOT`) and `weakness-miner.sh` (`git log -- $LEARNINGS_DIR`). `generate-kb-index.sh`'s facet pass (`kb-tags.txt`, `kb-categories.txt`) is also learnings-only, but its `INDEX.md` listing (`find "$KB_DIR"`, L103-107) would list `project/patterns/*.md` | `generate-kb-index.sh` is not edited (constraint 9). The listing is an ordinary page list in a gitignored cache (`knowledge-base/INDEX.md`, ADR-235): no merge livelock. Pins: `allowedPaths`/`TARGET_ALLOW_RE` refuse `patterns/`; a fixture shows patterns tags never reach `kb-tags.txt`. Readers rooted above `learnings/` are classified in the ADR (see `### Reader classification`) |
| "ledger row must land independently of the proposal's fate" | The row rides the PR commit (`allowedPaths` includes `promotion-log.md`). ADR-054 makes `safeCommitAndPr` the sole bot write path, so a second row-landing PR is a forbidden second write path | **Ruled by CTO agent, 2026-10-24 (F1a):** the row stays in the PR; GitHub PR state is the system of record for rejection; `promotion-log.md` is documented as accepted-or-pending only. The property the constraint protects (a reader that sees rejected proposals) is delivered by the Octokit reader |
| "no ledger schema change" | Holds; **no PR-body change either** (round-2 ruling C1) | `promotion-log.md` header text only |
| "a fail-closed ledger read would recreate the silent-zero-output bug" | The bug was *silence*. Fail-closed that ends `status=error` with `ledger_read:"failed"` and a Sentry mirror is loud | **Ruled by CTO agent, 2026-10-24 (F3):** fail-closed-loud on the patterns path. Recorded in `decision-challenges.md` because it reads against the issue's literal wording |
| "`critical-patterns.md` is read by `learnings-researcher.md:90`" | Read at Step 3b with no existence guard; **neither** `critical-patterns.md` nor `common-solutions.md` exists on disk or in any git ref | Create neither; retarget both to `patterns/` frontmatter (F6) |
| "Octokit not `gh`" | The handler already uses `new Octokit({auth})` from `@octokit/core` and `GET /search/issues` (dedup, week-cap). `@octokit/core` has **no `paginate`** (`cron-content-vendor-drift.ts:543` says so). `promotion-log.md` header and the runbook still cite `gh pr list` and a nonexistent `scheduled-compound-promote.yml` | Manual `octokit.request` page loop; header text corrected |
| "the PR body carries `Cluster-Hash:`" (round-2 ruling C1 premise) | `Cluster-Hash: <hash>` is a **commit trailer** (handler L2110), not a PR-body line; the body has it inline mid-sentence (L2115). The PR **title** is `self-healing(auto): promote cluster <hash> <date>` | Parse the hash from the title with an anchored regex built from one shared builder/parser pair, and pin builder and parser together in a test. No body change |
| "proposer clusters over the whole corpus" | The server enforces `PROMOTION_QUORUM = 5` over `source_learnings` that are **keys of the collected corpus** (`corpusSummaries`) | Patterns arm keeps a corpus-key map: evidence learnings are the keys, so the quorum is unchanged |
| "Inngest functions run on the Inngest server" | `model.c4` L759: `inngest -> api` invokes steps; every function executes on the web host | The C4 edge for the cron's PR-state read is `api -> github`, not `inngest -> github` |
| "FR2 streak alert" | Deferred in the spec itself | Not built |

## Research Insights

**Premise Validation (Phase 0.6).** #8293 OPEN (updated 2026-10-19); #10552 OPEN with a merged fix
(#10553) and an enrolled probe (`scripts/followthroughs/compound-promote-draft-edit-10552.sh`, first
eligible 2026-10-25T06:00Z); #10550 and #10551 OPEN and untouched; #8281 CLOSED (2026-09-28). Cited
paths all exist on `origin/main`. ADR corpus grep (`wikiskill|pattern wiki|promotion-log|compound-promote`):
ADR-054 (sole bot write path - constrains the ledger), ADR-092 (additive-only edit boundary - unchanged),
ADR-027, ADR-108, ADR-151, ADR-235 (INDEX.md is an untracked cache). No ADR rejects a pattern layer or
a PR-state ledger. Stale premises found: digest size, corpus size, the nonexistent `common-solutions.md`
/ `critical-patterns.md`, and "the trailer is in the PR body".

**Property List (Phase 0.6b).**
- P1: the proposer's prompt input can be a small curated set, measurable in bytes.
- P2: a cluster already proposed (open, merged, or recently closed) is not re-proposed on the patterns path.
- P3: an unreadable prior-outcome ledger is loud, never silent.
- P4: a bare close suppresses for a bounded time (issue constraint 6: expire OR explicit marker; expiry chosen).
- P5: a pattern page whose failure is fixed leaves the prompt (close state).
- P6: pattern pages are unreachable by the corpus readers and are scanned in full by gitleaks.
- P7: one surface, not three, for pattern / critical-pattern / common-solution knowledge.
- P8: the layer's effect is measurable after #10552 clears without crediting it for #10553/#10673.

**Cut List (Phase 0.6b, extended by plan-review and CTO round 2).**
- Full 2,309-file backfill -> P1 is bought by a <=8-page seed (issue constraint 8).
- A `patterns-index.md` artifact / extending `generate-kb-index.sh` -> glob `patterns/*.md` frontmatter at prompt-assembly time (constraint 9).
- `Content-Digest` ledger column -> `Cluster-Hash` already keys the PR title/branch (constraint 4).
- A separate bot PR to land ledger rows -> forbidden second write path (ADR-054); PR state already covers P2.
- A "previously rejected" list in the model prompt -> PR-derived text in a prompt is an injection path.
- Legacy-corpus fallback when no pattern is open -> hides a broken seed, corrupts the A/B.
- Proposer-written pattern pages -> a model-authored publication surface (CLO).
- `gh` CLI reader -> absent in the runtime image.
- **Round 2 (CTO, 2026-10-24):** near-duplicate overlap suppression and `Ledger-Target`/`Ledger-Sources` PR-body lines (speculative hash evasion); the `self-healing/rejected` label and its creation step (TTL satisfies "expire OR marker"); slot top-up; `dry_run`, `clusters_drafted`, `patterns_digest`, the notify-only probe and its tracker (deferred to the flip tracker); the repo-wide reader census (flaky, ~234 files name the path); `/compound` upsert; `closed_reason` enum and the 40-page cap; `patterns_count`; per-hit PR detail fetches; the PR-body convention footer.

**Value-proposition measurement (Phase 0.6c).** The saving claimed is prompt input. Measured baseline:
`corpus_input_bytes = 1,214,087` over `corpus_count = 2,248` (mean ~540 B/entry), from the
`SOLEUR_COMPOUND_PROMOTE_OUTCOME` row of 2026-09-20 05:39Z (#8293 ruling comment). Estimated patterns
arm: 8 pages x >=5 evidence x ~540 B = ~22-30 KB (~2% of baseline) - an **estimate from the mean**,
measured on the first manual patterns run. What the layer buys in *PR yield* is not measurable at plan
time and is not asserted.

**Institutional learnings that bind this plan** (under `knowledge-base/project/learnings/`):
- `2026-09-18-the-loop-was-not-failing-it-was-succeeding-at-nothing-and-said-ok.md` - every exit emits the marker; `ledger-suppressed` must reach it.
- `2026-10-20-a-threshold-that-lives-only-in-a-prompt-is-a-request-not-a-constraint.md` - reuse the census-pinned vocabulary; no second memoized step per cluster.
- `2026-06-12-inngest-cron-heartbeat-gate-on-final-attempt-and-step-memoization.md`, `2026-06-14-inngest-regenerate-cron-consolidate-write-and-commit-in-one-step.md` - `step.run` memoizes returns; fs writes are not memoized.
- `2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md` - `gh` is not in the runtime image.
- `2026-09-21-widening-who-reaches-an-evidence-check-inherits-what-the-evidence-is-keyed-on.md` - a name-keyed lookup must bind author and repo.
- `2026-07-30-every-green-signal-i-had-certified-a-gate-with-six-fail-open-paths.md` - enumerate API-down, rate-limit, 404, partial page.
- `2026-09-20-every-guard-pinned-the-artifact-and-none-pinned-the-wire.md` - name the one-line edit that unwires the reader and prove a test reds.
- `2026-05-30-fix-source-of-recurring-artifact-but-verify-source-can-self-clean.md` - the branch-cleanup allowlist excludes `self-healing/`; do not make expiry depend on branch existence.
- `2026-05-12-brainstorm-write-mostly-artifact-diagnosis-and-lifecycle-prereq.md` (#2723) - a write-mostly knowledge surface needs a close mechanic.

**Related, not folded.** Open code-review issues #2231 and #3321: see `## Open Code-Review Overlap`.

## Problem Statement

`cron-compound-promote` has produced no draft PR since it was enabled on 2026-07-06. Observability was
fixed in #8281/#8344 and two server-side defects in #10553/#10673, so the *next* scheduled run is the
first that can reach the gates. Independently of why it was silent, two gaps remain: (a) it clusters
over a ~1.2 MB prompt of near-duplicate session learnings (15 learnings in one week describe one
failure class), and (b) nothing reads a closed or merged proposal, so a rejected cluster can be
re-proposed. This plan builds the curated alternative for (a) and the reader for (b), both behind the
`input: "patterns"` switch, without moving the production default.

## Proposed Solution

```text
 weekly cron (input=corpus, unchanged)        manual {input:"patterns"}
        |                                            |
   dedup -> week-cap ----------------------> ledger-read (Octokit search, fail-closed-loud)
        |                                            |
   collect-corpus (legacy, unchanged)        collect-patterns (open pages + evidence)
        \______________ anthropic-cluster (unchanged call shape) ______/
                                   |
        normalise (hoisted above the empty check) -> recompute clusterHash
                                   |        \-> patterns path: exact-hash suppression
                                   |            -> record(hash, "ledger-suppressed") -> marker
        kept==0 or truncated ? existing no-qualifying-clusters emit : draft-edit-<h8> (quorum 5) -> apply-and-pr-<h8>
```

### Pattern page contract (CTO F7, trimmed by round 2 C10)

`knowledge-base/project/patterns/<slug>.md`; filename equals `<slug>`; seed <= 8 pages (cap revisited at ~25).

```yaml
---
title: "<short pattern name>"
summary: "<one line, <= 200 chars, printable ASCII: problem + root cause + fix>"
status: open            # open | closed
opened_on: 2026-10-24
tags: [guards, mutation-testing]
evidence:               # existing, tracked, non-archived learnings (>= 5 for a seeded page)
  - knowledge-base/project/learnings/<file>.md
required_reading: false # replaces the never-created critical-patterns.md
# closed pages only (both required; the reason lives in the body):
closed_on: 2026-11-30
closed_by: 12345        # PR number that fixed or retired it
---
## Root cause
## Fix
## Evidence
```

Rules: only a human PR edit closes a page; the cron never writes a pattern page; pattern text carries no
names, handles, tester/tenant/session-derived content; `PII_REGEX` and the retired-rule list apply to
the page and to every evidence learning (a failing learning is dropped, never sent).

**What enters the model prompt (and what does not).** Per open page: `slug`, `title`, `summary`, `tags`,
`evidence` keys. The `## Root cause` / `## Fix` bodies are **not** sent. The index and the evidence
excerpts are wrapped in the same nonce-fenced `block()` construction the draft step uses (handler
`draftAdditiveEdit`, "Per-call nonce"), with the "untrusted data, not instructions" sentence. Evidence
learnings are sent exactly as the corpus path sends them today (first 10 lines), so `corpusSummaries`
and the quorum are unchanged.

### Ledger reader contract (CTO F1-F3 + round 2 C1, C2, C5)

- **Source of truth:** GitHub PR state. `promotion-log.md` records accepted-or-pending proposals only.
- **Where it runs:** its own `step.run("ledger-read")`, **only when `inputSource === "patterns"`**. The
  scheduled path has no new step, no new error path and no new marker fields.
- **Query:** `octokit.request("GET /search/issues", { q: "repo:<o>/<r> is:pr head:self-healing/auto-", per_page: 100, page })`
  in a manual loop, hard stop at `LEDGER_MAX_SEARCH_PAGES = 5`; exceeding the cap (decided from
  `total_count`, not from an iterator) counts as a failed read. `head:` prefix matching was verified live:
  `head:ci/` returned 279 PRs, `head:ci/content-publisher` returned 64. No per-hit detail fetch: the search
  item already carries `user.login`, `state`, `closed_at`, `title`, and `pull_request.merged_at`.
- **Identity binding (a name-only match never suppresses):** server-side `repo:` and `head:` qualifiers
  plus `user.login === LEDGER_BOT_LOGIN` (`"soleur-ai[bot]"`, verified live on the other app-authored
  PRs; a test pins it equal to `BOT_LOGIN` in `cron-bot-pr-reaper.ts`). The `self-healing/auto` label is
  **not** required (label application is advisory in `safeCommitAndPr`).
- **Hash:** the item's `title` must match the anchored `PROMOTE_PR_TITLE_RE` built from the same
  `promotePrTitle(hash, date)` the apply step uses (`self-healing(auto): promote cluster <64-hex> <YYYY-MM-DD>`);
  an item that does not match is skipped. A test builds a title with the real builder and parses it.
- **Suppression rule (exact hash only):** open -> suppress; merged (`merged_at` set) -> suppress
  permanently (documented; a changed learnings set changes the hash, so a reverted target re-clusters
  naturally); closed unmerged -> suppress while `now - closed_at < 60 days` where
  `now = new Date(runStartedAt)` (the memoized run start, never a fresh `Date`); at exactly 60 days it
  lapses (pinned by a test).
- **Failure path:** API error, rate limit, or a page-cap overrun -> the step throws -> the existing
  `status=error` marker with `ledger_read:"failed"` + `reportSilentFallback` (op `ledger-read-failed`).
  Inngest's single retry (`retries: 1`) applies. A stage variable (not a nested catch) tells the outer
  catch which stage died, so no `return { ok` is added.
- **Placement:** normalisation of the model's clusters is hoisted above the existing empty/truncated
  check; suppression runs there. When nothing is left the existing `no-qualifying-clusters` emit fires
  (now carrying `refusals`/`refusal_detail` and the ledger fields). **No new terminal return.**
  `clusters_proposed` stays pre-suppression.

### Marker additions (patterns path only; numbers and closed enums)

`input_source: "corpus"|"patterns"`, `patterns_open`, `ledger_read: "ok"|"failed"`, `ledger_suppressed`,
`ledger_prs_scanned`. `CompoundPromoteStatus` stays at 8; `ledger-suppressed` is a per-cluster refusal
reason with a `refusal_detail` entry `{cluster_hash, reason}`. On the scheduled path the field set is
byte-identical to today (pinned by a test).

### Trigger option

`event.data.input` accepts `"corpus"` or `"patterns"`. On `trigger === "manual"` any other present value
ends the run `status=error` (`invalid-run-option`, closed enum) instead of silently coercing; on `cron`
it is ignored. The existing trigger route forwards caller `data` untouched and each cron validates its own
fields (`app/api/internal/trigger-cron/route.ts`, #4742), so no route change is needed.

## Technical Considerations

- **Replay safety.** Octokit and fs reads stay inside `step.run` (handler invariant I1). The ledger step
  returns a bounded list (<= 500 entries of `{hash, state, closed_at}`), no free text.
- **Quorum unchanged.** `corpusSummaries` is keyed by evidence learning paths in the patterns arm.
- **Census.** `cron-compound-promote-outcome-census.test.ts` pins one marker emit before each terminal
  return (the handler has 7 `return { ok:` sites; this plan adds none) and requires `return { kind: ...}`
  at least 9 times (16 today). It also pins exactly **two** `TARGET_ALLOW_RE.test(` sites in the handler,
  so the ledger and patterns modules take injected inputs and add no third site. `PII_REGEX` and
  `TARGET_ALLOW_RE` are exported from the handler file, so the patterns module receives `piiRegex` by
  injection (no import cycle).
- **No third-party free text.** Per #8427 the marker carries no model- or reviewer-authored text. The
  reader never reads PR comments or bodies.
- **Art. 30 / DPIA coupling.** The marker field set is coupled to PA-31 and DPIA memo trigger 15 (see Legal).
- **Dark launch, stated honestly.** Default `input` is `corpus`; the scheduled path gets no new step, no
  new error path, no new marker field. Its code deltas are exactly two, both behaviour-identical and
  I/O-free: the PR title now comes from `promotePrTitle` (same string, pinned against the old literal), and
  cluster normalisation moves above the empty/truncated check (a pure function of the memoized model
  output; for zero clusters it produces an empty list, as before). No existing step id or return shape
  changes, so a run in flight at deploy resumes on the new code safely (new steps exist only on the
  patterns path). Merge order relative to the 2026-10-25 run therefore does not matter. Consequence, accepted: until the flip, the legacy path has no suppression, so a rejected
  cluster can recur there.
- **Attack-surface enumeration (suppression is a trust boundary).** Paths that can make the reader
  suppress: a bot PR (intended); a human renaming a bot PR title (org member; limited to suppressing);
  a fork PR or a human-authored PR with the branch prefix (blocked by the `user.login` binding). Paths
  that can make it under-suppress: title drift (pinned builder/parser), search-index lag (weekly
  cadence), >500 bot PRs (fails closed at the cap; ~5 years at 2 per week - switch to state-split queries
  then, noted in the flip tracker).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Land a ledger row on main via a second bot PR (constraint 3 read literally) | Second write path (ADR-054); records proposals nobody reviewed; PR state already provides the data |
| `pulls?state=all` + client filter | Newest-first over the repo's whole history; a 5-page cap silently misses older bot PRs |
| `head:` search + per-hit detail fetch | Detail budget becomes a time bomb (merged PRs accumulate); search items already carry the bound fields |
| Tell the model which clusters were rejected | PR-derived text in a prompt is an injection path |
| Overlap-based suppression and `Ledger-*` body lines | Speculative evasion defence; changes the gated PR-body write path |
| Rejection label | TTL already satisfies "expire OR explicit marker"; the label adds a repo write and a failure path |
| Ledger on all paths from day one | Perturbs the 2026-10-25 baseline run with a new `error` path |
| Flip the cron default in this PR | Destroys the clean baseline and the controlled comparison |
| Full backfill / proposer-written pages | Constraint 8 / CLO; recall cost accepted and measured |

## User-Brand Impact

- **If this lands broken, the user experiences:** the weekly proposer opens a draft PR proposing an
  edit to `AGENTS.rules.md` or a `SKILL.md` that the maintainer would have rejected last week, or opens
  none while reporting success, so recurring failure classes keep costing review rounds.
- **If this leaks, the user's workflow is exposed via:** pattern-page text or evidence excerpts that
  carry a name, handle, credential shape or tester/tenant detail into the Anthropic prompt and a public
  repo, then into proposer-authored edits shipped in every installed copy of the plugin.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** carried forward from the brainstorm and confirmed by the CPO
  (2026-10-24): Phase 1 adds no write path to `plugins/`, but the pages are new prompt input to the same
  proposer and the controls (PII pass, human-reviewed draft gate) are proven on this slice before
  Phase 2 widens it; `aggregate pattern` was judged defensible only in isolation.

CPO sign-off: **conditional**; conditions folded into ACs: PII test, read-only index/ledger, fail-closed
with Sentry mirror, `user-impact-reviewer` at review, a measurement section, "nothing is measurable until
#10552 clears" stated above.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_COMPOUND_PROMOTE_OUTCOME WARN row on every terminal exit; on the patterns path it also carries input_source, patterns_open, ledger_read, ledger_suppressed, ledger_prs_scanned (Sentry cron monitor scheduled-compound-promote unchanged)"
  cadence: "weekly (0 0 * * 0) plus every manual trigger"
  alert_target: "Sentry cron monitor scheduled-compound-promote; Better Stack row read by scripts/followthroughs/compound-promote-outcome-8281.sh"
  configured_in: "apps/web-platform/server/compound-promote-marker.ts and apps/web-platform/server/inngest/functions/cron-compound-promote.ts"
error_reporting:
  destination: "Sentry web-platform via reportSilentFallback (feature cron-compound-promote), mirrored to pino/Better Stack"
  fail_loud: "status=error marker with ledger_read=failed and Sentry op ledger-read-failed; invalid-run-option error on a malformed manual trigger; one Sentry message per dropped pattern page (op pattern-page-dropped)"
failure_modes:
  - mode: "GitHub search fails, rate-limits, or exceeds the page cap during ledger-read (patterns path)"
    detection: "marker status=error with ledger_read=failed; Sentry op ledger-read-failed"
    alert_route: "Sentry cron-monitor failure plus the 8281 outcome probe counting an error week"
  - mode: "patterns path finds zero open pages (broken seed, all closed)"
    detection: "marker status=empty-corpus with input_source=patterns and patterns_open=0; Sentry op patterns-empty"
    alert_route: "Sentry issue"
  - mode: "suppression swallows every cluster (rejected top cluster inside its 60 days)"
    detection: "marker status=no-qualifying-clusters with ledger_suppressed greater than 0"
    alert_route: "visible on the next manual patterns run; reviewed in the flip tracker"
  - mode: "a pattern page or evidence learning matches PII_REGEX or violates the schema"
    detection: "CI live-tree test fails before merge; at runtime the page is dropped and Sentry op pattern-page-dropped fires"
    alert_route: "CI (vitest) before merge; Sentry at runtime"
logs:
  where: "Better Stack source reached by the pino WARN path (component compound-promote)"
  retention: "per the Better Stack source retention already used by the 8281 probe"
discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 7d --no-archive --limit 1"
  expected_output: "SOLEUR_COMPOUND_PROMOTE_OUTCOME"
  credentials_required: "BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD read-only - no unauthenticated substitute exposes production log rows (same declaration as the 8281 probe)"
```

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-297** (provisional ordinal - `soleur:ship` re-verifies the next free ordinal against
`origin/main`; on renumber sweep `grep -rn 'ADR-297' knowledge-base/project/{plans,specs}/feat-one-shot-8293-wikiskill-pattern-layer/`)
via `soleur:architecture create`: *"Pattern wiki as a sibling knowledge surface; GitHub PR state is the
proposal ledger of record."* Decision: (1) `knowledge-base/project/patterns/` is the sole surface for
pattern, required-reading and common-solution knowledge; (2) the ledger of record for proposal outcomes
is PR state read through Octokit, `promotion-log.md` records accepted-or-pending only and is never
extended; (3) the reader contract (exact hash, 60-day TTL, bot-author binding, fail-closed-loud, patterns
path only); (4) phase gating (`input` default `corpus` until the A/B passes; status `adopting`);
(5) ADR-054 and ADR-092 are unchanged because `patterns/` is provably outside `TARGET_ALLOW_RE` and
`allowedPaths` (cite the test). `## Alternatives Considered` carries the Cut List and the Alternative
Approaches table. Attribution: structure adapted from WikiSkill (arXiv 2608.27454, CC BY 4.0) with a
link, the licence and an indication of changes.

#### Reader classification (in the ADR)

| Reader | Root | Sees `patterns/`? | Disposition |
|---|---|---|---|
| handler `walkDir` | `learnings/` | no, by construction | pinned by handler test |
| `kb-staleness-metric.sh`, `weakness-miner.sh` | `learnings/` | no | by construction |
| `generate-kb-index.sh` facet pass | `learnings/` | no | fixture pin |
| `generate-kb-index.sh` INDEX listing | whole KB | yes | intended: ordinary page list in a gitignored cache |
| `kb-drift-walker.sh`, `kb-reader.ts`, `kb-search`, `learning-retrieval-bench.sh`, `backfill-frontmatter.py` | verify at work time | classify each as intended or excluded | recorded in the ADR |

### C4 views

All three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` were read.
Checked against the feature: (a) external human actor - the public GitHub reader (`model.c4` L58-67,
"publication surface") already covers committed pages; the maintainer who closes a PR is the existing
operator actor; (b) external systems - `anthropic` (L369) and `github` (L377) are modeled, and the same
two systems are called as today; (c) containers/data stores - `kb` (L182) holds learnings, plans, ADRs;
(d) actor-surface access - unchanged (maintainer-only merge). Two edits: **`kb` description** (L184) gains
"pattern wiki (project/patterns)"; and, because the patterns path now has a fatal dependency on GitHub
PR-state reads, a sibling **`api -> github`** edge (functions execute in `api`, `inngest -> api` L759;
the model has no `inngest -> github` edge and `model.c4` L668 says the Inngest layer opens no git
workspace) describing "cron-compound-promote reads bot-PR state through Octokit search (patterns path)".
Confirm the hosting container at implementation. Regenerate `model.likec4.json` if the render test
requires it and run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and
`plugins/soleur/test/c4-count-parity.test.sh` (green on this tree before any edit: `ALL TESTS PASSED`).

### Sequencing

The ADR describes the target state, `status: adopting` until the A/B flips the cron default. Authored
in this PR, not deferred.

## Encryption Posture

Skipped: no persistent store and no new cross-component connection. The reader reuses the existing HTTPS
Octokit connection to GitHub already used by `dedup-check` and `week-cap`; no `.tf`, migration,
cloud-init or compose file is touched.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (sign-off only; no UI surface)

### Engineering (CTO)

**Status:** reviewed (round 1 forks F1-F8; round 2 rulings C1-C13 after the six-seat plan-review panel)
**Assessment:** See `## Decision Record`. Round 2 cut the near-duplicate overlap rule, the rejection
label, slot top-up, `dry_run`/probe/digest, the repo-wide census, `/compound` upsert, and gated the
ledger to the patterns path so the 2026-10-25 baseline is untouched.

### Legal (CLO)

**Status:** reviewed
**Assessment:** No PA-31 category, purpose, recipient or retention changes (input becomes a subset;
GitHub already a recipient). Required in this PR: a one-line dated, merge-conditioned note on PA-31 §(c)
in `knowledge-base/legal/article-30-register.md`; an addendum to
`knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md` (trigger 15 - marker field
set - fires on the patterns path; trigger 2 arguably fires), with a `Superseded <date>` marker under the
memo's §2 "Outcome marker ... unchanged" paragraph and under the trigger-15 row in `compliance-posture.md`
(~L169); the addendum states it does not cure the unmet 2026-10-25 and 2026-11-19 conditions. Art. 5(1)(e):
pages are persistent derived text in a public repo - mitigated by curation (<=8), no names, closed pages
add no personal data. Run `soleur:gdpr-gate` over the diff at ship. Hard constraints encoded as ACs: PII
pass on pages and evidence; proposer never writes pages; marker = counts and closed enums; GitHub App
auth, no PAT; CC BY 4.0 attribution; the ledger reads no PR or comment text.

### Product (CPO)

**Status:** reviewed - conditional sign-off
**Assessment:** Maturity "building, unproven producer". Keep `single-user incident`. Measurement gated
and confound-controlled (see `## Effect Measurement Plan`). Positioning: "Soleur got sharper", never
"your workspace got smarter"; no outward wording until #6102 unless the CMO reviews it.

No Product/UX Gate: no UI-surface path in Files to Create / Edit.

## Decision Record

Persisted in `knowledge-base/project/specs/feat-one-shot-8293-wikiskill-pattern-layer/decision-challenges.md`.

| Item | Class | Ruling |
|---|---|---|
| F1 ledger row vs ADR-054 | technical | Ruled by CTO agent, 2026-10-24: row stays in PR; PR state is the system of record |
| F2/C2 expiry and marker | technical | Ruled by CTO agent, 2026-10-24 (round 2 changed F2): TTL only, 60 days from `closed_at`; no label |
| F3 failure path | technical | Ruled by CTO agent, 2026-10-24: fail-closed-loud, patterns path only (C5) |
| F4/C1 suppression | technical | Ruled by CTO agent, 2026-10-24 (round 2 changed F4): exact recomputed hash only; no overlap rule, no PR-body lines |
| F5 input / C4 | technical | Ruled by CTO agent, 2026-10-24: `input` kept; `dry_run`, digest, probe deferred to the flip tracker |
| F6/C7 three concepts | technical | Ruled by CTO agent, 2026-10-24: `patterns/` sole surface; retarget read-only; upsert deferred |
| F7/C8/C10 page schema, seed | technical | Ruled by CTO agent, 2026-10-24: `status`, `closed_on`, `closed_by`; seed <= 8, ship fewer if fewer qualify; no 40 cap |
| C3 | technical | Ruled by CTO agent, 2026-10-24: slot top-up cut |
| C5 | technical | Ruled by CTO agent, 2026-10-24: ledger-read only on `input=patterns` |
| C6 | technical | Ruled by CTO agent, 2026-10-24: repo-wide census cut; by-construction pins + classification table |
| C9 | technical | Ruled by CTO agent, 2026-10-24: marker fields `input_source`, `patterns_open`, `ledger_read`, `ledger_suppressed`, `ledger_prs_scanned` |
| C11 | technical | Ruled by CTO agent, 2026-10-24: ADR-297 yes; C4 = kb description + edge on the hosting container (plan resolves to `api -> github`) |
| C12 | technical | Ruled by CTO agent, 2026-10-24: merged suppression permanent, documented; vacuity fix in the flip tracker text |
| C13 | technical | Ruled by CTO agent, 2026-10-24: one PR, commit order fixed (see Phases) |
| Plan refinement | technical | Hash parsed from the anchored PR **title** via a shared builder/parser, because `Cluster-Hash:` is a commit trailer and not a PR-body line |
| Threshold `single-user incident` | operator (legal-risk) | Carried from brainstorm; CPO confirmed 2026-10-24 |
| CODEOWNERS line for `patterns/` (architecture review) | taste | Not adopted here; separate decision alongside #3321 |

## Implementation Phases

Commit order inside the single PR follows the CTO ruling (C13). Test-first throughout
(`cq-write-failing-tests-before`): each phase lands RED tests, then code.

### Phase 0 - Preconditions (no commit)

- 0.1 Re-verify at work time: `gh issue view 10552 --json state` (read only; do not comment), `git ls-files knowledge-base/project/learnings | grep -v /archive/ | wc -l`, ADR next free ordinal, and that `apps/web-platform` vitest for `test/server/inngest/cron-compound-promote*` is green before edits. Confirm the PR author login of an app-authored PR is `soleur-ai[bot]` and which container hosts the handler (for the C4 edge).
- 0.2 Run `bash plugins/soleur/test/c4-count-parity.test.sh` and record green.

### Phase 1 - ADR, C4, docs (commit 1)

- 1.1 ADR-297 via `soleur:architecture create`; 1.2 `model.c4` `kb` description + sibling `api -> github` edge (+ regenerate/validate); 1.3 `promotion-log.md` header (accepted-or-pending; Octokit lookup; drop the nonexistent workflow reference); 1.4 `compound-promote-runbook.md` (the `input` option, reading the new fields, the stale workflow reference at ~L208); 1.5 `betterstack-log-query.md` marker field list; 1.6 legal notes (PA-31 §(c) note, DPIA addendum, `Superseded` markers in `compliance-posture.md`).

### Phase 2 - Pattern module, schema, lint (commit 2; RED then GREEN)

- 2.1 `apps/web-platform/server/compound-promote-patterns.ts`: `parsePatternPage(text, path)`, `loadOpenPatterns({repoRoot, piiRegex, retiredPaths})` -> `{patterns[], evidenceEntries[], open, dropped[]}`, `renderPatternIndex()` (fenced block). Pure fs reads; no writes, no network, no `safeCommitAndPr` import.
- 2.2 `apps/web-platform/test/server/compound-promote-patterns.test.ts` and `...-patterns-live-tree.test.ts` (validator over the real `knowledge-base/project/patterns/`): schema, filename = slug, `summary` length and charset, `evidence[]` in `git ls-files` and not archived, closed pages carry `closed_on` and `closed_by`, open pages carry neither, `PII_REGEX` on title/summary/tags/evidence, `required_reading` boolean.
- 2.3 `plugins/soleur/skills/compound-capture/assets/pattern-page-template.md` (linked from SKILL.md).

### Phase 3 - Ledger reader (commit 3; RED then GREEN)

- 3.1 `apps/web-platform/server/compound-promote-ledger.ts`: `promotePrTitle(hash, date)`, `PROMOTE_PR_TITLE_RE`, `LEDGER_BOT_LOGIN`, `LEDGER_TTL_DAYS = 60`, `LEDGER_MAX_SEARCH_PAGES = 5`, `readLedger({octokit, owner, repo})` (manual `request` loop), `decideSuppression({entries, hash, now})`. No imports from the handler file.
- 3.2 `apps/web-platform/test/server/compound-promote-ledger.test.ts` (see Test Scenarios; mock only `Octokit.request`).

### Phase 4 - Handler wiring (commit 4)

- 4.1 `cron-compound-promote.ts`: `readRunOptions(event, trigger)` (`input` enum; invalid manual value -> `invalid-run-option` error); hoisted `inputSource`, `patternsOpen`, `ledgerRead`, `ledgerScanned`, `ledgerSuppressed`, `stage` (above the `try`, so the error marker carries them).
- 4.2 `step.run("ledger-read")` after `week-cap`, only when `inputSource === "patterns"`; sets `stage` before, `ledgerRead = "ok"` after; the outer catch maps `stage === "ledger-read"` to `ledgerRead = "failed"`.
- 4.3 `collect-patterns` replaces `collect-corpus` on the patterns path (same `entries` shape); zero open pages -> `empty-corpus` with `input_source:"patterns"` and Sentry `patterns-empty`; no fallback.
- 4.4 `anthropic-cluster`: patterns arm sends the fenced index plus the evidence entries; the call shape and `remaining` slice are unchanged.
- 4.5 Hoist cluster normalisation above the empty/truncated check; on the patterns path run `decideSuppression` per proposal (`record(hash, {kind:"refused", reason:"ledger-suppressed"})`, `ledgerSuppressed++`); `kept` replaces `proposals` downstream; the existing `no-qualifying-clusters` emit gains `refusals`, `refusal_detail` and the ledger fields. No new return.
- 4.6 `apply-and-pr`: title built with `promotePrTitle` (behaviour-identical string). `allowedPaths` unchanged.
- 4.7 `compound-promote-marker.ts`: the five fields as typed literal unions/numbers; the emitter picks them explicitly; a marker test asserts an emitted row contains no key outside an allowlist. Update `cron-compound-promote-outcome-marker.test.ts` and the census.

### Phase 5 - Seed (commit 5; <= 8 pages)

- 5.1 Candidates: `SOLEUR_WM_WINDOW_DAYS=90 SOLEUR_WM_DIGEST_PATH=<scratchpad>/dg90.md bash scripts/weakness-miner.sh` (scratch path only; never overwrite the tracked digest).
- 5.2 Dedupe the overlapping tag-pair clusters by member-set Jaccard > 0.5; keep those with >= 5 evidence learnings; read the learnings; write `summary`, Root cause and Fix by hand. LLM-assisted, every page reviewed by the PR author. **Exit rule:** ship however many qualify (up to 8); if fewer than 3 qualify, the flip tracker records the seed as insufficient and the patterns arm is not graded.
- 5.3 Each page cites only tracked non-archived learnings, carries no names or handles, and passes the live-tree test. Cluster provenance goes in the PR body, not the page.

### Phase 6 - Retarget the three concepts (commit 6; read-only)

- 6.1 `compound-capture/SKILL.md` Step 7: replace the `common-solutions.md` heredoc with "point the maintainer to `assets/pattern-page-template.md`; a pattern page is added or extended by a reviewed PR". Replace "Add to Required Reading" (three menu copies) with "propose a pattern page with `required_reading: true` in a reviewed PR". Net word count must not grow; no `description:` edit, so no skill-description budget impact.
- 6.2 Delete `assets/critical-pattern-template.md`; sweep its one reference (SKILL.md L291).
- 6.3 `learnings-researcher.md` Step 3b: glob `knowledge-base/project/patterns/*.md`, read frontmatter, report pages with `status: open` and `required_reading: true`; guard for an absent directory; rename the output heading.
- 6.4 `grep -rn 'critical-patterns\|common-solutions' plugins/ scripts/ AGENTS.md AGENTS.rules.md knowledge-base/project/constitution.md` returns zero live hits (archive and learnings prose excluded).

### Phase 7 - Measurement prose and tracker issues (commit 7)

- 7.1 File **one flip-tracker issue** (label `follow-through` only if a probe is later enrolled; milestone from the roadmap), `Ref #8293`, carrying `## Effect Measurement Plan` below and these deferred deliverables with their re-evaluation triggers: `dry_run` (manual-only, stops after a successful draft, `dry_run:true`, every probe filters `dry_run != true`), `clusters_drafted`, `patterns_digest`, the notify-only comparison probe, the cron-default flip, applying the ledger to the scheduled path, slot top-up (trigger: marker shows suppression eating a week's slots), near-duplicate overlap (trigger: an observed one-learning evasion), a rejection label and a PR-body convention footer (trigger: TTL proves too blunt), state-split search queries (trigger: >400 bot PRs), a CODEOWNERS line. `gh issue edit --add-blocked-by` is not applicable (no blocker issue); cite #10552 in the body as context only (`Ref #10552`, never `Closes`).
- 7.2 File a second issue: "`/compound` upsert of pattern pages" (deferral of FR7), milestone from the roadmap, with the spec-flow gaps as its design inputs (closed-page recurrence, slug collision, archived evidence breaking CI).

## Effect Measurement Plan

**Nothing about the layer's effect is claimed or measurable until #10552 clears.** The PR body says so
and does not attribute the zero-PR history to the dump. This section is the PR's statement of *how*; the
flip tracker (7.1) owns the build of the machinery.

1. **Frozen baseline.** Pre-change markers: the four G-a rows (2026-09-27 ... 10-18), the 2026-09-20 row
   (`corpus_input_bytes` 1,214,087; 2,248 entries), and the 2026-10-25 run. A zero-PR baseline is a
   baseline for "opens at all", nothing more.
2. **Gate.** Effect on PR yield is read only after #10552's probe passes (a scheduled run whose proposal
   reached the gates) **and** at least four post-clear weekly runs exist. Before that: "unmeasured".
3. **Controlled input comparison** (built in the flip tracker; same day and same build, so #10553/#10673
   are held constant). Three pairs on separate days, each = `{input:"corpus", dry_run:true}` then
   `{input:"patterns", dry_run:true}` via `soleur:trigger-cron`. Per arm: `corpus_input_bytes`, input
   tokens (`SOLEUR_CLAUDE_COST` row for the same `run_id`), `clusters_proposed`, `clusters_drafted`
   (reached the gates), refusal distribution, `patterns_digest`. `dry_run` must precede any use because
   a real run opens PRs and trips `week-cap` for the second arm.
4. **Decision rule (a hypothesis to tighten).** Flip the cron default (one constant, separate PR) only if
   in at least 2 of 3 pairs `clusters_drafted(patterns) >= 1` **and** `>= clusters_drafted(corpus)` **and**
   `corpus_input_bytes(patterns) <= 10%` of the corpus arm; otherwise the verdict is `inconclusive`
   (the vacuous `0 >= 0` pass is excluded). A rollback criterion is recorded with the flip: two consecutive
   weeks of `empty-corpus` or `clusters_opened == 0` with `ledger_suppressed == 0`.
5. **After the flip.** Four weekly cron runs: `clusters_opened`, merge rate of opened drafts, suppression
   correctness (re-proposals of a cluster inside its TTL = 0), index precision (share of proposals mapping
   to an open page), `patterns_digest` so a seed change is not credited as an effect, and the north-star
   proxy: recurrence of a closed pattern's tags in new learnings in the 4 weeks after `closed_on` against
   the 4 weeks before. Guardrails: net skill count and the description-word budget.
6. **Honest limit.** The seed covers ~2% of the corpus by evidence count, so the patterns arm can only
   cluster what was seeded; a lower `clusters_proposed` is an expected cost, not a defect.

## Files to Create

- `apps/web-platform/server/compound-promote-patterns.ts`
- `apps/web-platform/server/compound-promote-ledger.ts`
- `apps/web-platform/test/server/compound-promote-patterns.test.ts`
- `apps/web-platform/test/server/compound-promote-patterns-live-tree.test.ts`
- `apps/web-platform/test/server/compound-promote-ledger.test.ts`
- `apps/web-platform/test/server/inngest/cron-compound-promote-patterns-handler.test.ts`
- `knowledge-base/project/patterns/<slug>.md` x up to 8 (seed pages)
- `plugins/soleur/skills/compound-capture/assets/pattern-page-template.md`
- `knowledge-base/engineering/architecture/decisions/ADR-297-pattern-wiki-and-pr-state-proposal-ledger.md` (ordinal provisional)
- `knowledge-base/project/specs/feat-one-shot-8293-wikiskill-pattern-layer/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-8293-wikiskill-pattern-layer/decision-challenges.md`

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
- `apps/web-platform/server/compound-promote-marker.ts`
- `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-census.test.ts`
- `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-marker.test.ts`
- `plugins/soleur/skills/compound-capture/SKILL.md`
- `plugins/soleur/agents/engineering/research/learnings-researcher.md`
- `knowledge-base/project/learnings/promotion-log.md` (header text only; no schema change)
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `model.likec4.json` if regeneration is required)
- `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md`, `knowledge-base/legal/compliance-posture.md` (dated notes only)
- `plugins/soleur/test/generate-kb-index.test.sh` (one pinning case; `scripts/generate-kb-index.sh` itself is NOT edited)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` 76 -> 77 with the PLACEMENT / TRUTH / NO SUBSTITUTE comment; this plan's `credentials_required` declaration moves the repo-global ratchet the moment it is committed - re-read the value at work time because sibling PRs bump it too)

**Deleted:** `plugins/soleur/skills/compound-capture/assets/critical-pattern-template.md`.

All paths verified: each existing path resolves with `git ls-files`; the two `knowledge-base/legal`
register files were read by the CLO and the third is a dated comment edit. No `.gitleaks.toml`,
`generate-kb-index.sh`, `_cron-safe-commit.ts` or reaper edit.

## Open Code-Review Overlap

Two open `code-review` issues name planned or adjacent files:

- #2231 (`perf(kb-search): skip past frontmatter with nextfile in facet extraction`) - `scripts/generate-kb-index.sh`,
  which this plan deliberately does not edit. **Acknowledge** - different concern, needs its own cycle.
- #3321 (`review: add CODEOWNERS coverage for knowledge-base/project/learnings/ subtree`) - names
  `.gitleaks.toml`, which this plan does not edit (patterns are *not* added to the allowlists).
  **Acknowledge**: a CODEOWNERS line for `patterns/` is a separate decision (listed in the flip tracker).

## Test Scenarios

Pyramid layer in brackets; all `unit` unless stated.

**Patterns module**
- Given a valid open page, when loaded, then it appears in the index with `title`, `summary`, `tags`, evidence keys and **not** its Root cause/Fix bodies. [unit]
- Given `status: closed` with `closed_on` and `closed_by`, then it is excluded from the prompt but valid; given `closed` missing `closed_by`, or `open` carrying `closed_on`, then the live-tree test fails. [unit]
- Given an evidence path that is archived, untracked or absent, then the page is invalid. [unit]
- Given an evidence learning matching `PII_REGEX` (synthesized email), then that learning is dropped, the page loads with fewer keys, and a page left under 5 keys is dropped with `pattern-page-dropped`. [unit]
- Given a `summary` over 200 chars or containing a control character, then the page is invalid. [unit]
- Given the real tree, then every committed page passes. [integration - reads the repo]

**Ledger reader** (mock only `Octokit.request`)
- Given zero hits -> entries = [], `ledger_prs_scanned = 0`, no suppression. [unit]
- Given an open PR with the same hash -> suppress. Given merged -> suppress at +400 days. [unit]
- Given closed-unmerged at +59 d -> suppress; at **exactly 60 d** -> not suppressed (pins `<`); at +61 d -> not suppressed. [unit]
- Given the same hash from a different author (`user.login` human) or a title not matching `PROMOTE_PR_TITLE_RE` -> never suppresses. [unit]
- Given a title built by the real `promotePrTitle` -> `PROMOTE_PR_TITLE_RE` parses the same hash and date (builder/parser pin). [unit]
- Given search 502, rate limit (403), or `total_count` implying a 6th page -> `readLedger` throws a typed error. [unit]
- Property: for any entries and any hash, `decideSuppression` returns suppress only when an entry has that exact hash and (open | merged | closed within TTL). [unit, property-based]
- `LEDGER_BOT_LOGIN` equals the `BOT_LOGIN` literal in `cron-bot-pr-reaper.ts` (source-read pin). [unit]

**Handler** (extends the `draft-handler` real-git harness: mocked `Octokit` class, mocked `postAnthropicMessage`, real cloned repo)
- Given a cron event with `data.input = "patterns"` -> ignored: `corpus` path, marker field set identical to today (no `input_source`, no ledger fields), **no `ledger-read` step**. [integration]
- Given manual `{input:"patterns"}` and 3 open seeded pages -> prompt contains the fenced index, `entries` are evidence keys, quorum 5 passes, `corpus_input_bytes` < 10% of the same fixture's corpus arm, `input_source:"patterns"`, `ledger_read:"ok"`. [integration]
- Given manual `{input:"patterns"}` and zero open pages -> `empty-corpus`, no corpus fallback. [integration]
- Given manual `{input:"pattern"}` (typo) -> `status:"error"`, `error_class` names `invalid-run-option`, no Anthropic call. [integration]
- Given the ledger read throws -> `status:"error"`, `ledger_read:"failed"`, no Anthropic call. [integration]
- Given the top proposed cluster's hash was proposed (open PR) -> `refusals` contains `ledger-suppressed`, `ledger_suppressed:1`, no `draft-edit` step for it; given every cluster suppressed -> status `no-qualifying-clusters` carrying the refusals and ledger fields. [integration]
- Given a whole-handler replay with memoized steps -> counts identical (accumulation in the handler body). [integration]
- Given `allowedPaths` of any `safeCommitAndPr` call -> never contains `knowledge-base/project/patterns/`; `TARGET_ALLOW_RE` rejects such a target. [unit]
- Given pattern text containing a closing fence marker -> the nonce fence is not closable. [unit]

**Readers and plugin**
- Given a `patterns/` fixture with a unique tag -> `kb-tags.txt` and `kb-categories.txt` from `generate-kb-index.sh` do not contain it. [integration - `generate-kb-index.test.sh`]
- `grep` for `critical-patterns|common-solutions` over live plugin/script paths returns nothing. [integration]
- `learnings-researcher` Step 3b text handles an absent `patterns/` directory (string test on the agent file). [unit]

## Guard Contract

### Guard 1 - Ledger suppression boundary

**Property.** On the patterns path a cluster is suppressed if and only if an identity-bound prior
proposal with the same recomputed hash is open, merged, or closed within the TTL, and an unreadable
ledger never degrades to "suppress nothing" without a loud `status=error`.

**Assembly.** Every path by which a prior outcome becomes a suppression decision: the search loop, the
page cap, the title parse (`PROMOTE_PR_TITLE_RE` and its builder), the `user.login` binding, the TTL
clock (`runStartedAt`), and the single call site in the handler where hoisted normalisation feeds the
draft loop. Chokepoint: `decideSuppression()` is the only function that returns a suppression verdict,
and the handler consults it for **every** proposal in the list (the loop, not the first element), on the
patterns path only; the `input` gate is the second chokepoint and is itself under test.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `decideSuppression` call in the handler (unwire the reader) | RED (suppression integration case) |
| 2 | Make `readLedger` return `[]` on a thrown 502 instead of throwing (fail-open) | RED (ledger-read failure case) |
| 3 | Check only the first proposal for suppression; leave later clusters unchecked | RED (second-cluster case) |
| 4 | Drop the `user.login` binding | RED (human-author case) |
| 5 | Change `<` to `<=` in the TTL comparison | RED (exactly-60-day case) |
| 6 | Make the page cap silently ignore a 6th page | RED (page-cap case) |
| 7 | Change the title format in `promotePrTitle` without the regex | RED (builder/parser pin) |
| 8 | Run `ledger-read` on the scheduled path (remove the `input` gate) | RED (cron-ignores-input case) |
| 9 | Make `decideSuppression` always return `suppress:false` (a guard that suppresses nothing) | RED (open/merged cases - the vacuity row) |

**Harness rows.** Edit the suite: replace the mocked `Octokit.request` with one that always returns an
empty page -> the suppression cases must RED (the suite can see an empty reader). Must-PASS inputs that
are not the canonical: an item whose `title` differs in case or has trailing whitespace is skipped (not
suppressing), and a lower-case 64-hex title suppresses while an upper-case one does not.

**Anchor.** The stored value is PR state on GitHub. A weakening needs a change outside the commit to move
(a maintainer reopening or retitling PRs, an auditable GitHub event); one diff cannot edit both the reader
and the PR history.

### Guard 2 - Pattern directory containment

**Property.** No bot write path can stage a file under `knowledge-base/project/patterns/`, and pattern
tags never reach the facet files the clustering key reads.

**Assembly.** The write side: the single `allowedPaths` literal in `apply-and-pr`, `TARGET_ALLOW_RE`
(both handler sites) and `safeCommitAndPr`'s own allowlist. The read side: the facet pass of
`generate-kb-index.sh` (`kb-tags.txt`, `kb-categories.txt`), the handler `walkDir` root, and the
readers-above-`learnings/` classification table in ADR-297 (documented, not census-tested - a repo-wide
census was rejected as flaky, ~234 files name the learnings path).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a `patterns` path to `allowedPaths` | RED |
| 2 | Widen `TARGET_ALLOW_RE` to admit `knowledge-base/project/patterns/` | RED |
| 3 | Add `patterns/` tags to the facet pass of `generate-kb-index.sh` | RED (kb-tags fixture) |
| 4 | Point the handler `walkDir` at `knowledge-base/project` | RED (corpus excludes-patterns case) |
| 5 | Make the fixture contain no pattern file (vacuous scan) | RED (fixture self-check asserts the pattern file exists and is indexed in INDEX listing) |

**Harness rows.** Edit the suite: delete the assertion that the fixture pattern tag is absent -> the
harness self-check must RED; must-PASS: a learnings fixture with the same tag is present in `kb-tags.txt`
(proves the scanner works).

**Anchor.** `TARGET_ALLOW_RE` and the `allowedPaths` literal are pinned in the existing census (two
`TARGET_ALLOW_RE.test(` sites); a widening shows as a diff in a CODEOWNERS-default-reviewed file.

### Guard 3 - Marker closed vocabulary and scheduled-path invariance

**Property.** The new marker fields carry only numbers and closed enums, appear only on the patterns
path, and every terminal return still emits exactly one marker.

**Assembly.** `CompoundPromoteOutcome`, `emitOutcomeMarker`, every `emitOutcomeMarker(` call in the
handler (7 terminal `return { ok:` sites, none added), the census regex, and the runbook/Better Stack
field lists.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a terminal `return { ok: ...}` without a preceding emit | RED (census) |
| 2 | Emit `input_source` on the scheduled path | RED (scheduled-path field-set pin) |
| 3 | Add a string-typed free-text field to the outcome and the emitter | RED (allowlisted-keys test on the emitted row) |
| 4 | Add a ninth `CompoundPromoteStatus` literal | RED (status-count pin) |
| 5 | Spread `...entry` for `refusal_detail` so a future field relays | RED (existing rebuild test) |

**Harness rows.** Edit the suite: weaken `MIN_TERMINAL_RETURNS` to 0 -> RED on the dispatch row;
must-PASS: a synthetic handler source with 7 classified returns plus the new emit inside the existing
branch.

**Anchor.** The status union is compiler-checked; the allowed key list lives in the test; the runbook list
moves with it by convention (stated, not claimed as enforced).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement Phase 1 of the WikiSkill epic as tracked by #8293 (WikiSkill pattern layer + proposer index/ledger reader)" [brief] | Phases 1-7; Files to Create/Edit | mapped |
| 2 | "Do not comment on or close #10552 and do not start #10550 or #10551" [brief] | Overview out-of-scope; Phase 0.1 reads state only | mapped |
| 3 | "patterns at sibling top-level knowledge-base/project/patterns/, excluded from all four corpus readers" [issue #8293] | Phases 2, 5; Guard 2 | mapped |
| 4 | "ledger row must land independently of the proposal's fate" [issue #8293] | Phase 3-4; CTO F1 | mapped - delivered through PR state as ledger of record, not by relocating the row (Research Reconciliation) |
| 5 | "no ledger schema change" [issue #8293] | `promotion-log.md` header text only; no PR-body change | mapped |
| 6 | "read prior outcomes via Octokit not gh with a defined failure path and a ledger-suppressed reason in the outcome marker" [brief] | Phase 3, 4.2, 4.5, 4.7; Guard 1, 3 | mapped |
| 7 | "closed-unmerged suppression must expire or need an explicit rejection marker" [brief] | 60-day TTL | mapped |
| 8 | "pattern pages need a close state" [brief] | Page contract `status`, `closed_on`, `closed_by` | mapped |
| 9 | "seed from weakness-digest.md rather than a full 2,309-file backfill" [brief] | Phase 5 (via the digest's own miner at 90 d) | mapped - the committed digest holds 1 cluster, so the generator is used |
| 10 | "do not extend generate-kb-index.sh" [brief] | not edited; one test case in `generate-kb-index.test.sh` | mapped |
| 11 | "resolve the three overlapping common-solutions/critical-patterns concepts together" [brief] | Phase 6 | mapped |
| 12 | "PR body uses Ref #8293 (not Closes) and Ref #10552 only if relevant, never Closes" [brief] | Ship-phase PR body; Phase 7 issues | mapped |
| 13 | "merge-queue PRs are never synced or pushed to; technical forks go to the CTO agent, not the operator; a single gh pr merge per call; no secrets in argv" [brief] | Decision Record; ship/work execution rules | mapped |
| 14 | "the plan must state how the layer's effect will be measured after #10552 clears, and the PR must not claim the 2,309-file dump is the cause of zero PRs" [brief] | `## Effect Measurement Plan`; Overview; Phase 7.1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `compound-promote-patterns.ts` + seed pages | "patterns at sibling top-level knowledge-base/project/patterns/" | asked |
| `compound-promote-ledger.ts` | "read prior outcomes via Octokit not gh with a defined failure path" | asked |
| `input` trigger option and `collect-patterns` step | "a compact index the proposer reads instead of the 2,309-file corpus dump" [issue #8293] | asked |
| `invalid-run-option` error on a malformed manual `input` | — | inferred - justification: a silently coerced typo would run the corpus arm while the maintainer believes it is the patterns arm, corrupting the only measurement the brief asks for |
| Title builder/parser pair (`promotePrTitle`, `PROMOTE_PR_TITLE_RE`) | "read prior outcomes via Octokit not gh with a defined failure path" | inferred - justification: `Cluster-Hash:` is a commit trailer, not a PR-body line, so the hash must be read from the title and the builder and parser must not drift |
| Flip tracker with the deferred deliverables (Phase 7.1) | "the plan must state how the layer's effect will be measured after #10552 clears" | asked |
| `/compound` upsert deferral issue (Phase 7.2) | "resolve the three overlapping common-solutions/critical-patterns concepts together" | inferred - justification: `wg-when-deferring-a-capability-create-a` requires a tracking issue for a deferred capability |
| ADR-297, C4 `kb` description and `api -> github` edge | — | inferred - justification: `wg-architecture-decision-is-a-plan-deliverable` (plan Phase 2.10) makes the ADR and C4 update deliverables of the plan that makes the decision |
| Legal notes (PA-31, DPIA addendum, compliance-posture) | — | inferred - justification: the DPIA memo's trigger 15 fires on a marker-field change and the CLO found the register note due on merge; deferring it would leave the Art. 30 record stale |
| `pattern-page-template.md`, deletion of `critical-pattern-template.md` | "resolve the three overlapping common-solutions/critical-patterns concepts together" | asked |
| Containment pins (Guard 2) | "excluded from all four corpus readers" | asked |

### Split Assessment

- Subsystems touched: 4 - `apps/web-platform`, `plugins/soleur`, `knowledge-base`, `scripts` (the `scripts` root is touched only through the existing `generate-kb-index` test under `plugins/soleur/test`, so effectively 3)
- Planned files: ~29 (11 create incl. up to 8 seed data pages counted as 8 -> 18, 13 edit, 1 delete) | Estimated changed lines: ~1,300 (code+tests ~750, seed pages ~350, docs ~200)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - over the file and line thresholds, kept single by CTO ruling C13: one plan is one pipeline PR, the handler change is dark and independently revertible, and a fixed commit order (ADR/C4/docs, patterns module, ledger, handler, seed, retarget, trackers) makes it reviewable. If review capacity objects, the cut line is PR A = commits 1-4 (needs no seed pages) and PR B = commits 5-7.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] `knowledge-base/project/patterns/` exists with 3-8 pages (fewer than 3 qualifying clusters is recorded in the PR body and the flip tracker), each `status: open`, >= 5 tracked non-archived evidence learnings, passing the live-tree test. No page contains a name, handle, credential shape or session/tenant detail; PII test fixtures are synthesized (`cq-test-fixtures-synthesized-only`).
- [ ] `knowledge-base/project/learnings/patterns/` is **not** created; `common-solutions.md` and `critical-patterns.md` are not created; `git grep -nE 'critical-patterns|common-solutions' -- plugins scripts AGENTS.md AGENTS.rules.md knowledge-base/project/constitution.md ':!knowledge-base/project/plans'` returns nothing (the plan and ADR, which quote the names while explaining the retirement, are outside that scope; at plan time the live hits are exactly the three files Phase 6 edits or deletes).
- [ ] The scheduled path is unchanged: with `event.name === "inngest/scheduled.timer"` and any `data.input`, the run uses `corpus`, executes no `ledger-read` step and emits the same marker field set as before (test).
- [ ] `input` accepts only `corpus|patterns`; a malformed manual value ends `status=error` (`invalid-run-option`) before any Anthropic call (test).
- [ ] The patterns-path ledger read is a `step.run`, fail-closed-loud (`status:"error"`, `ledger_read:"failed"`, Sentry op `ledger-read-failed`), with a test per failure shape (502, 403 rate limit, page cap).
- [ ] Suppression matches the contract: exact hash; open, merged, closed within 60 days; bot-author binding; the +59 / exactly-60 / +61-day cases pass; `now` derives from the memoized `runStartedAt`.
- [ ] `ledger-suppressed` appears in `refusals[]` and `refusal_detail[]` with `{cluster_hash, reason}` only; `CompoundPromoteStatus` still has 8 members; the census passes unmodified except its pinned additions; no `return { ok:` site added; `TARGET_ALLOW_RE.test(` count in the handler remains 2.
- [ ] No `promotion-log.md` column and no PR-body change; `promotePrTitle` yields the same string as the previous literal title (test against the old format).
- [ ] `scripts/generate-kb-index.sh`, `.gitleaks.toml`, `_cron-safe-commit.ts` and `cron-bot-pr-reaper.ts` are unmodified: `git diff --quiet origin/main...HEAD -- scripts/generate-kb-index.sh .gitleaks.toml apps/web-platform/server/inngest/functions/_cron-safe-commit.ts apps/web-platform/server/inngest/functions/cron-bot-pr-reaper.ts` exits 0 (merge-base form, measured rc 0 at plan time); `allowedPaths` never includes `patterns/` (test).
- [ ] The five marker fields are in the marker type, the allowed-keys test, `compound-promote-runbook.md` and `betterstack-log-query.md`.
- [ ] ADR-297 written (provisional ordinal re-verified at ship) incl. the reader classification table; `model.c4` `kb` description and the `api -> github` edge added; `c4-code-syntax`, `c4-render` and `c4-count-parity` tests green.
- [ ] Legal notes landed (PA-31 §(c) dated note, DPIA addendum with the `does not cure` sentence, `Superseded` markers); `soleur:gdpr-gate` run over the diff at ship.
- [ ] `soleur:engineering:review:user-impact-reviewer` invoked at review (threshold `single-user incident`); the observability-coverage reviewer run (server code touched).
- [ ] PR body: `Ref #8293`, no `Closes`; states the effect is unmeasured until #10552 clears and makes no claim that the dump caused the zero PRs; carries the `## Changelog` section and the seed-cluster provenance. #10552, #10550, #10551 untouched.
- [ ] Lints green: `python3 scripts/lint-guard-contract.py <this plan>`; the vitest shard for `cron-compound-promote*` and the new modules; `bash plugins/soleur/test/generate-kb-index.test.sh`; the preflight-discoverability ratchet suite (G1) at the bumped baseline; the orphan-suite census (`lint-orphan-test-suites.sh`) reports every new test file registered (vitest globs `test/**/*.test.ts` under `apps/web-platform`).

### Post-merge

- [ ] The two tracker issues (Phase 7) are filed, each `Ref #8293`, with the deferred deliverables and re-evaluation triggers listed above.
- [ ] After the 2026-10-25 scheduled run, the marker's field set matches the pre-change shape (verified with the existing Better Stack reader; no behavioural change).

## Risks

- **Recall.** 8 pages x >=5 evidence is ~2% of the corpus; the patterns arm can only cluster what was seeded. Accepted and measured in the flip tracker.
- **Seed quality.** The miner's clusters are tag co-occurrence, not root causes; page quality depends on the authoring pass and the review of each page.
- **Hash evasion.** One added or removed learning changes the hash; the 60-day TTL bounds how often it reaches a reviewer; `ledger_suppressed` keeps it visible. Overlap suppression is a tracked contingency.
- **Title as identity.** The title is the only identity contract; drift or a retitled PR fails open into a duplicate PR. Mitigated by the shared builder/parser pin and weekly cadence.
- **No suppression on the scheduled path** until the flip. Accepted for baseline integrity.
- **Co-moving artifacts.** The marker field list lives in the type, the allowed-keys test, and two runbook docs; the AC lists them.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. This one is filled.
- `step.run` returns are persisted: keep ledger entries free of PR text and bounded.
- Do not add a `TARGET_ALLOW_RE.test(` site to the handler, a `return { ok:` without a marker, or a spread of marker entries.
- The `Cluster-Hash:` line the CTO ruling cited is a commit trailer; the identity contract is the PR title.
- Confirm at implementation which container hosts the handler before writing the C4 edge.
- A scripted edit of this plan must anchor headings at line start and re-count sections afterwards (a heading literal also appears in prose).
- The `discoverability_test` was not executed at plan time (it needs the Better Stack credential); it is a literal copy of the form `scripts/followthroughs/compound-promote-outcome-8281.sh` already runs. Run it once at work time and paste the output into the PR.

## References

- Issue #8293 (body + comments through 2026-10-19); brainstorm and spec archived under `knowledge-base/project/{brainstorms,specs}/archive/20260918-160549-*`.
- #10552 (open; fix #10553; probe `scripts/followthroughs/compound-promote-draft-edit-10552.sh`), #10673 (server quorum), #8281 / #8344 / #8427 (marker), #5292 / #2723 (prior art).
- ADR-054, ADR-092, ADR-235; arXiv 2608.27454 (CC BY 4.0).
