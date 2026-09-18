---
title: "feat(harness): WikiSkill Phase 1 — observable proposer, path-derived allowlist, additive pattern layer"
date: 2026-09-18
slug: feat-wikiskill-pattern-wiki-phase-1
branch: feat-wikiskill-skill-evolution
issue: 8281
closes: 8281
also_closes: 8274
lane: cross-domain
type: feat
domain: engineering
priority: p2-medium
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-wikiskill-skill-evolution/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-09-18-wikiskill-skill-evolution-brainstorm.md
source: https://arxiv.org/abs/2608.27454 (CC BY 4.0)
---

## Overview

Phase 1 of applying the WikiSkill method (arXiv 2608.27454, CC BY 4.0) to Soleur's compounding
loop. Three deliverables: make the weekly promotion proposer's outcome observable on every
terminal path; derive the diff allowlist the way `git apply` actually resolves paths (#8274); and
add an **additive** pattern layer over the learnings corpus with a **derived** index and a ledger
the proposer reads before proposing.

Phases 2 (gated new-skill creation) and 3 (moving `**Why:**` prose into `PURPOSE.md`) are out of
scope and gated on this phase producing observable proposals.

The research below changed the shape of this plan twice: most of what Phase 1 needs already
exists and is either misfiring or unread, so the work is **extending five existing primitives**,
not building a wiki.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited | Probe | Result |
|---|---|---|
| #8281 | `gh issue view` | OPEN — this plan's target |
| #8274 | `gh issue view` | OPEN — folded in (see Open Code-Review Overlap) |
| #6038, #6102 | `gh issue view` | OPEN, remain deferred; this plan supersedes neither |
| #6037 | `gh issue view` | CLOSED — shipped the weakness-miner this plan reuses |
| ADR-069 / 091 / 092 / 171 / 174 / 218 | read | All hold; constraints folded in below |
| Proposed mechanism vs ADR corpus | grep `decisions/` for index/consolidation/learnings | **One material hit — #5292, below** |

**The mechanism has prior art that was rejected once.** `knowledge-base/project/specs/feat-compound-consolidate/spec.md` (#5292) proposed a scheduled `compound --consolidate` pass that **merges and archives** learnings. CPO + CLO + CTO rejected it unanimously: the prior loop was dead (`promotion-log.md` 0 rows), recall was unmeasured, and "auto-consolidation is lossy by construction, threatening the verbatim/auditable moat."

This plan is **not** that mechanism, and the distinction is the whole design: the pattern layer is
**additive** (no learning is ever edited, moved, merged or deleted; pattern pages only *link* to
them), which is exactly what guardrail **G2** already requires. #5292's guardrails G1–G5 are
adopted verbatim as constraints (see Risks).

**#5292 was closed on 2026-07-24 by a polling bot, 20 days before its own gate could render.** Its
authoritative decision rule says a checkpoint fires on/after **2026-08-13** and "always produces a
verdict"; the issue's last comment is `soleur-ai: Maximum polling period reached (30 business
days). Stopping automated monitoring`, and the close timestamp is ~10s later. No verdict was ever
posted. `scripts/followthroughs/kb-consolidation-checkpoint.sh` still exists. **Disposition:** out
of scope here, recorded as a finding — the sweeper skips closed issues, so that gate is now
permanently unfired. Filed as a note on #5292 rather than reopened, because this plan's additive
layer does not depend on its verdict.

**The two redundancy measurements do not conflict.** `kb-staleness-metric.sh` reports **0.19%**
near-duplicate density (Jaccard ≥0.6 over title-tokens ∪ tags, 2026-06-14, 1550 files) — the
corpus is *not textually redundant*. `weakness-digest.md` (2026-09-13) shows **15 learnings in one
week** sharing ≥2 tags in one failure class — the corpus *is thematically recurrent*. These
measure different properties; neither refutes the other, and the plan must not cite the second as
though it contradicted the first.

### Property List / Cut List (Phase 0.6b)

| # | Property (observable outcome) | Already bought by | Verdict |
|---|---|---|---|
| P1 | The proposer's outcome is knowable from telemetry without SSH | nothing — all 7 terminal paths emit only `postSentryHeartbeat({ok:true})` | **BUILD** (payload change, ~6 lines + marker module) |
| P2 | The allowlist constrains what `git apply` writes | `TARGET_ALLOW_RE` exists but is keyed on `+++ b/` | **FIX** (#8274) |
| P3 | One consolidated root-cause+fix statement per recurring failure | `compound-capture` Step 7 **already prescribes** `learnings/patterns/common-solutions.md`; dir does not exist, 0 files ever written | **EXTEND a misfiring hook** |
| P4 | A rejected proposal is not re-proposed | `promotion-log.md` (append-only, cluster-hash, CLO non-repudiation) — 0 rows, nothing reads it | **EXTEND schema + add a reader** |
| P5 | The proposer's input is a sane prompt | nothing — it dumps all 2,309 learnings | **BUILD** (index-first read) |

**Cut List** — proposed or implied mechanisms removed here, not researched, not designed:

| Cut | Property it would buy | What already covers it |
|---|---|---|
| A new index generator + CI drift check | one-line-per-item index | `scripts/generate-kb-index.sh` already emits 3 artifacts, has `--out`/`--check`, a merge driver (`merge-kb-index.sh`) and lefthook wiring — add a 4th output |
| A new ledger file | append-only proposal record | `promotion-log.md` + its CLO non-repudiation argument |
| A new clustering algorithm | backfill cluster discovery | `weakness-miner.sh` (tag-pair co-occurrence) + `kb-staleness-metric.sh` (Jaccard merge candidates) |
| A new near-duplicate metric | "are these the same pattern" | `kb-staleness-metric.sh` — **reuse as-is** |
| A new Sentry monitor / new cron | zero-output detection | streak detection in the cron's own code + one `sentry_alert` (29 precedents) |
| A new search surface | retrieval over patterns | `kb-search` (tier-1/tier-2, `--tag`/`--category`) |
| Any archival step | pattern lifecycle | ADR-174 retired the benefit (index-time exclusion, not `git mv`) |
| A recurring recall benchmark | "did the layer improve recall" | `learning-retrieval-bench.sh` is a **one-shot** diagnostic; see Non-Goals |

### Value-Proposition Measurement (Phase 0.6c)

The "saves an expensive prompt" claim, measured rather than asserted:

- **Baseline:** the 2026-09-13 run made one Sonnet call with **516,512 input tokens / 7,623 output
  tokens** (`capture_status: ok`, `model: claude-sonnet-5`). Command:
  `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1500h --grep cron-compound-promote`,
  then decode the `SOLEUR_CLAUDE_COST` marker with `id: cron-compound-promote`.
- At Sonnet input pricing this is ~$1.5/run, ~$80/yr, **for zero output**.
- **The token saving is real but small in absolute terms and is NOT the justification.** The
  justification is P1+P4+P5 together: a loop that cannot be diagnosed cannot be fixed. Any plan
  text that leads with the cost saving is overstating it.
- Post-change input size is **not yet measurable** (the index does not exist). AC requires the
  first post-merge run's `SOLEUR_CLAUDE_COST` input_tokens to be recorded, not predicted.

### Verified code facts

- **7 terminal return paths** in `cronCompoundPromoteHandler` (`cron-compound-promote.ts:424-837`):
  `disabled` (:469), `deduped` (:496), `week-cap-reached` (:514), `empty-corpus` (:569),
  `anthropic-truncated`|`no-qualifying-clusters` (:642), `completed` (:821), `error` (:837). Every
  one returns a `status` string **that is never emitted anywhere**.
- **`git apply` strips one leading path component by default** — measured, not read:
  a patch whose header is `+++ x/target.txt` applied cleanly and rewrote `target.txt`, and
  `+++ w/evil.yml` created `evil.yml`, in a throwaway repo. Today's filter
  (`.filter(l => l.startsWith("+++ b/"))`, :672-680) sees **neither**, so `badPath` is `undefined`
  and the allowlist passes. `applyDiffToWorkspace` (:397-418) calls
  `spawnGit(["apply", diffFile])` with no `-p`. *(A research agent reported "defaults to -p0";
  that is wrong and the experiment above refutes it — the fix depends on this.)*
- **`reportSilentFallback`** (`observability.ts:216-275`) emits to pino **and** Sentry;
  a plain `logger.*` call reaches only container stdout.
- **Better Stack transit requires WARN+.** Precedent: `claude-cost-marker.ts:65` — "Emit one
  `SOLEUR_CLAUDE_COST` **WARN** marker." An `info`-level marker would not be queryable, which is
  the failure this plan exists to prevent, recreated.
- **`MARKER_RE` does not apply here.** It lives in `git-lock-marker-telemetry.ts:119` and gates
  *plugin/CLI stdout* markers (observability layer 7). This marker is emitted server-side from the
  web container. *(A research agent called adding to `MARKER_RE` "non-optional"; that constraint is
  scoped to a different surface.)*
- **Sentry IaC:** `sentry_alert` is the live form (**30** resources) vs `sentry_issue_alert` (2);
  provider `jianyuan/sentry ~> 0.15.7`. All 29 alerts in `issue-alerts.tf` carry a `tagged_event`
  filter — **there is no catch-all**, so `feature=cron-compound-promote` is currently unpaged.
  Copyable precedent with a multi-feature filter: `issue-alerts.tf:1965`.
- **`apply-sentry-infra.yml` applies FULL-ROOT** — its AC3 pins that *no* `-target=` survives in
  that file. The `-target` allowlist sweep Sharp Edge applies to the web-platform root, **not**
  here. Do not introduce a `-target`.
- **`c4-count-parity.test.sh`** derives its cron-monitor count from
  `grep -cF 'resource "sentry_cron_monitor"' cron-monitors.tf` — a new `sentry_alert` does not move
  it. The test still runs (see Architecture Decision).
- **`generate-kb-index.sh`** excludes `archive/` and flat non-spec files under `project/specs/`
  (ADR-174); a new directory under `learnings/` **is** auto-indexed. Facets come from frontmatter.
- **Corpus dump:** `collect-corpus` (:518-563) reads every non-archive learning, drops
  retired-rule and `PII_REGEX` matches, truncates each to `.slice(0, 10)` lines, and serializes via
  `JSON.stringify(corpus.entries)` into one message (:593).
- **Ledger append:** `:749-750` writes `| date | clusterHash | target | count | pending | tier | (PR pending) |`.
  Decision is **deliberately** not stored — derived at read time from PR state (CLO non-repudiation).
- **Tag substrate is noisy:** `kb-tags.txt` holds 4,345 tags polluted with paths, dates and bare
  integers. Tag-pairs are the backfill's clustering key, so this needs a normalization pass first.
- **Tests:** `apps/web-platform/test/server/inngest/cron-compound-promote{,-graymatter}.test.ts`
  exist and do **not** cover the allowlist. Runner is **vitest**
  (`cd apps/web-platform && ./node_modules/.bin/vitest run <path>`), include globs `test/**/*.test.ts`.

### Institutional constraints adopted

- **G1–G5** (`feat-compound-consolidate/spec.md`): G1 exempt classes (`compliance/`,
  `security-issues/`, incident/PIR) are non-mergeable/non-archivable; G2 additive-only, never edit
  or delete a learning body; G3 exempt evidence stays in place; G4 history-preserving moves only;
  G5 human PR gate affirming no source learning was rewritten or lost.
- **ADR-091:** produce the ledger where the data lives; append-only; never false-zero.
- **ADR-174:** flat-scope index allowlist discipline.
- **ADR-218 / ADR-096:** native Better Stack Logs alerts are for *stateless per-bucket counts*;
  windowed recurrence belongs in an in-repo poller. A 4-week absence is **not** a stateless count —
  hence streak detection in code + a Sentry tag, not a Logs alert.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR4 "a new `patterns/` layer" | `compound-capture` Step 7 already prescribes `learnings/patterns/common-solutions.md` (:253-254, :287, :562); the directory has never existed | Use the **prescribed path**; replace the dead aggregate-file instruction with a per-pattern upsert. No competing location. |
| FR5 "a one-line-per-pattern index" | `generate-kb-index.sh` already emits 3 artifacts with `--check` + merge driver | **Derive** the index from pattern frontmatter as a 4th output — never model-authored, so it cannot drift |
| FR9 "an append-only proposal ledger" | `promotion-log.md` exists with that contract and 0 rows | Extend its schema; preserve "decision derived at read time" |
| FR2 "Sentry alert after 4 zero-output weeks" | No absence-alert primitive; cron monitors detect *missed runs* and this cron runs fine | Detect the streak **in code** from the ledger, emit a tagged Sentry event, add one `sentry_alert` |
| FR3 "#8274 via `git apply --numstat -z`" | Confirmed correct; `-p` default measured | Adopt as specified |
| FR6 "full backfill of 2,309 learnings" | Clustering substrate (`kb-tags.txt`) is polluted | Add a tag-normalization task **before** clustering |

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --limit 200` (65 open), matched against this
plan's file list.

- **#8274** — `cron-compound-promote.ts` diff allowlist. **Fold in.** It is FR3; `also_closes: 8274`.
- **#2231** — `perf(kb-search): skip past frontmatter with nextfile in facet extraction`, touches
  `generate-kb-index.sh`, which this plan extends. **Acknowledge.** Different concern (awk
  performance in facet extraction vs. adding an output artifact); folding an unrelated perf change
  into a brand-critical PR widens the blast radius for no benefit. Left open.
- **#3321** — CODEOWNERS coverage for `knowledge-base/project/learnings/**`. **Defer with a note.**
  Directly relevant: the gitleaks `private-key` allowlist covers `learnings/.*\.md$`
  (`.gitleaks.toml:333`), and pattern pages land inside that subtree, inheriting the silencing this
  issue is about. This plan does **not** widen any allowlist, and pattern pages are prose linking to
  learnings. Add a re-evaluation note to #3321 naming `learnings/patterns/`.
- **#3829** — CI gate for new Sentry **monitor types** → `sentry-scrub.ts`. **Acknowledge.** This
  plan adds a `sentry_alert`, not a monitor type; the gate's trigger does not fire.

## User-Brand Impact

**If this lands broken, the user experiences:** a proposer-authored rule or skill edit that
silently narrows a guardrail protecting their repository, shipped in a plugin update they did not
review — or, in the failure mode this plan is fixing, a self-improvement loop that stays silently
dead while the product claims it compounds.

**If this leaks, the user's data is exposed via:** a pattern page or proposal diff that carries a
quoted secret or personal datum out of a learning and into every installed copy of the public
plugin; published copies cannot be recalled.

**Brand-survival threshold:** `single-user incident`. CPO sign-off required at plan time before
`/work`; carried forward from the brainstorm's framing (CPO + CLO + CTO assessed). The
`user-impact-reviewer` agent runs at review time.

## Implementation Phases

### Phase 0 — Preconditions (no code)

0.1 Re-verify `#8274` is open and unclaimed; re-derive the ADR ordinal against freshly-fetched
`origin/main` **and all `origin/*` refs** (ADR-225 was free across 80 refs at plan time; it is
provisional until merge).
0.2 Run `bash plugins/soleur/test/c4-count-parity.test.sh` and record the pre-change verdict.
0.3 Run `bash scripts/kb-staleness-metric.sh --json` to refresh the redundancy baseline against
today's 2,309-file corpus (the committed snapshot is 1,550 files from 2026-06-14).
0.4 Confirm `promotion-config.yml` still reads `enabled: true`.

### Phase 1 — Make the loop observable (ship-alone-able)

1.1 Add `apps/web-platform/server/compound-promote-outcome-marker.ts`, mirroring
`claude-cost-marker.ts`: one **WARN**-level pino marker, `SOLEUR_COMPOUND_PROMOTE_OUTCOME`, never
throws. Fields: `status`, `corpus_count`, `clusters_proposed`, `clusters_opened`, `refusals`
(per-reason counts), `week_cap_remaining`.
1.2 Call it on **all 7** terminal paths (:469, :496, :514, :569, :642, :821, :837).
1.3 Add the refusal counters the marker reports — increment at each existing refusal site
(`target-path-refused`, `diff-path-refused`, `diff-size-exceeded`, `git-apply-check-failed`,
`byte-budget-overflow`, `agents-core-hr-rule-edit-refused`) rather than adding new log lines.
1.4 **Guard 1** (below): a census test asserting every terminal return emits exactly one marker.

### Phase 2 — Close #8274 (independent of Phases 3-5)

2.1 Replace the `+++ b/` filter with derivation from git itself. **`--numstat` alone is not
sufficient and would ship a second bypass** — measured: for
`rename from AGENTS.rules.md / rename to plugins/soleur/skills/x/STOLEN.md`,
`git apply --numstat -z` reports **only** `plugins/soleur/skills/x/STOLEN.md` (fully allowlisted)
while the apply **deletes `AGENTS.rules.md`**. `git apply --summary` does report
`rename AGENTS.rules.md => …`. Derive the path set from **`--summary` plus `--numstat`**, taking
rename/copy **source** paths as well as destinations.
2.2 Check **every** derived path — sources included — against `TARGET_ALLOW_RE`; refuse when the
derived set is **empty** (today a header-less diff passes vacuously).
2.3 **Guard 2** (below) with its mutation matrix, written **before** the fix.

### Phase 3 — Pattern layer (additive)

3.1 Normalize the tag substrate: a pass over `kb-tags.txt` producing a clean tag vocabulary
(drop paths, ISO dates, bare integers). Clustering quality depends on this.
3.2 Define the pattern page contract at `knowledge-base/project/learnings/patterns/<slug>.md`:
frontmatter `problem`, `root_cause`, `fix`, `evidence` (list of learning paths), `first_seen`,
`last_seen`, plus optional `superseded_by` (the existing convention). Body = the paper's 10-30
lines.
3.3 Extend `generate-kb-index.sh` with a 4th output: `learnings/patterns/index.md`, one line per
pattern — `- [slug](slug.md): <problem> — <root_cause> — <fix>` — **derived from frontmatter**,
covered by the existing `--check` mode.
3.4 Rewrite `compound-capture` Step 7: replace the never-fired "if 3+ similar issues, append to
`common-solutions.md`" with a deterministic upsert — after the learning is written, resolve the
nearest pattern (tag-pair key + Jaccard) and either append an `evidence:` row or create a page.
Learnings are never edited (**G2**).
3.5 **Guard 3** (below): pattern↔index parity + every `evidence:` path resolves.

### Phase 4 — Backfill (chunked, reviewed, reversible)

4.1 Cluster the full corpus with existing tooling; emit a **candidate** list, no writes.
4.2 **Measure one batch before the rest**: run a single cluster batch end-to-end, record token cost
and human review time, and record the measured per-batch figures in the PR. If the measured cost
exceeds the estimate by >2×, stop and re-scope rather than continuing.
4.3 Process remaining batches; exempt classes (**G1**) are referenced but never merged or moved.
4.4 A wrong merge is repaired by editing one pattern page — no learning is touched (**G2/G5**).

### Phase 5 — Proposer reads the index and the ledger

5.1 Replace `collect-corpus`'s whole-corpus dump with an index read plus on-demand page reads.
5.2 Extend the `promotion-log.md` schema with `Content-Digest` (proposal body digest) while keeping
**Decision derived at read time** (CLO non-repudiation preserved).
5.3 Before proposing, the handler reads the ledger and resolves prior outcomes via the documented
`gh pr list --search "<cluster-hash>"` lookup; a cluster whose digest matches a closed-unmerged PR
is **not** re-proposed. `no_action` remains valid.
5.4 Streak detection: count consecutive zero-output rows; at ≥4 call `reportSilentFallback` with
`feature: "cron-compound-promote"`, `op: "zero-output-streak"`.
5.5 **Guard 4** (below): the assembled prompt contains the ledger digest.

### Phase 6 — Alert + ADR + C4

6.1 One `sentry_alert` in `issue-alerts.tf` filtered on `feature=cron-compound-promote` +
`op=zero-output-streak` (precedent :1965). Full-root apply; **no `-target`**.
6.2 Author **ADR-225**; update `.c4` only if the enumeration in Architecture Decision finds a gap;
re-run `c4-count-parity.test.sh`.
6.3 Enroll the soak follow-through (below).

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` — markers on 7 paths;
  `--numstat` path derivation; index-first corpus read; ledger read + streak detection
- `apps/web-platform/server/compound-promote-outcome-marker.ts` — **new**
- `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts` — extend
- `apps/web-platform/test/server/inngest/cron-compound-promote-allowlist.test.ts` — **new** (Guard 2)
- `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-census.test.ts` — **new** (Guard 1)
- `scripts/generate-kb-index.sh` — 4th output artifact
- `plugins/soleur/test/patterns-index-parity.test.sh` — **new** (Guard 3)
- `plugins/soleur/skills/compound-capture/SKILL.md` — Step 7 rewrite (body only; **no
  `description:` change**, so the 2,442/2,442-word budget is untouched)
- `knowledge-base/project/learnings/promotion-log.md` — schema extension (header only; rows stay append-only)
- `knowledge-base/project/learnings/patterns/` — **new** (pages + derived `index.md`)
- `apps/web-platform/infra/sentry/issue-alerts.tf` — one `sentry_alert`
- `knowledge-base/engineering/architecture/decisions/ADR-225-*.md` — **new**
- `scripts/followthroughs/compound-promote-outcome-8281.sh` — **new**
- `.github/workflows/scheduled-followthrough-sweeper.yml` — secrets wiring if not already present

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** Every terminal path emits exactly one `SOLEUR_COMPOUND_PROMOTE_OUTCOME` marker. Verify:
  the census test reports `unclassified == 0` **and** `classified >= 7` (a floor, not a pin — Phase
  5 may legitimately add an 8th return).
- **AC2** The marker is emitted at **WARN** level. Verify **in the census test**, by asserting the
  emitted record's level is `warn` — not by grepping for a token. (The precedent
  `claude-cost-marker.ts` calls `log.warn`, not `logger.warn`, so a token grep both false-fails a
  faithful mirror and reads stdin if the file argument is omitted.)
- **AC3** A diff whose header is `+++ x/.github/workflows/foo.yml` is **refused**. Verify: the
  allowlist test asserts refusal for `x/`, `w/`, `i/` prefixes and for a diff with no `+++` header.
- **AC4** A two-file diff whose first path is allowed and second is not is **refused** (the
  second-member row).
- **AC4b** A diff that **renames** `AGENTS.rules.md` to an allowlisted `SKILL.md` path is
  **refused**, and `AGENTS.rules.md` still exists after the attempt.
- **AC5** `patterns/index.md` is byte-identical after regeneration. Verify:
  `bash scripts/generate-kb-index.sh && git diff --exit-code -- knowledge-base/project/learnings/patterns/index.md`.
- **AC6** Every `evidence:` path in every pattern page resolves to a tracked file. Verify: the
  parity test reports `unresolved=0` and `patterns_checked` ≥1 (a zero-pattern run must FAIL, not
  pass vacuously).
- **AC7** No learning file body was modified by the backfill. Verify:
  `git diff origin/main...HEAD --name-only --exit-code -- knowledge-base/project/learnings/ ':!knowledge-base/project/learnings/patterns/' ':!knowledge-base/project/learnings/promotion-log.md'`
  exits 0. The `promotion-log.md` exclusion is load-bearing — it lives inside that pathspec and this
  plan edits it, so without it AC7 is RED by construction; `--stat` prints nothing on an empty diff,
  so "0 files changed" was not assertable as originally written.
- **AC8** No exempt-class learning (`compliance/`, `security-issues/`, incident/PIR) is merged or
  moved (**G1**). Verify: the same diff shows no renames under those paths.
- **AC9** The proposer's prompt contains the ledger digest and the pattern index, and **not** the
  whole-corpus dump. Verify: `grep -n 'collect-corpus' cron-compound-promote.ts` shows the
  index-first read, and the unit test asserts the assembled message contains the ledger section.
- **AC10** `promotion-log.md` rows remain append-only and **Decision** is still derived at read
  time (CLO non-repudiation preserved). Verify: the schema block still documents `pending`-only.
- **AC11** `bash plugins/soleur/test/c4-count-parity.test.sh` is green.
- **AC12** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` is green.
- **AC13** ADR-225 exists, its ordinal is free against freshly-fetched `origin/main`, and it records
  the #5292 rejection and the derived-index divergence from the paper in `## Alternatives Considered`.
- **AC14** Backfill batch-1 measured cost is recorded in the PR body (actual tokens + review time),
  not estimated.

### Post-merge (verified by the follow-through probe, not by a person)

- **AC15** The first weekly run after merge emits a `SOLEUR_COMPOUND_PROMOTE_OUTCOME` marker
  readable from Better Stack, and its `status` is recorded on #8281. This is **time-gated** (the
  cron fires Sunday 00:00 UTC) and is enrolled below — no operator step.

## Guard Contract

### Guard 1 — outcome-marker census

**Property.** Every terminal return of `cronCompoundPromoteHandler` emits exactly one outcome
marker, for all present and future returns.
**Assembly.** Not the 7 currently-known statuses (that is a snapshot). The chokepoint is the set of
`return {` statements inside the handler function body; the census walks them and buckets each as
*classified* (preceded by a marker emit) or *unclassified*, and **any unclassified member is RED**.
`MIN_CASES=7` is the floor, not the definition.
**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | Add an 8th early return with no marker | RED — census finds an unclassified member |
| 2 | Delete the marker call on `no-qualifying-clusters` | RED |
| 3 | Emit a marker with a `status` outside the known set | RED |
| 4 | *Dispatch row:* stub the return-statement scanner to yield `[]` | RED — a census reporting "0 checked" must fail, not pass |
**Harness rows.** (a) Mutate the suite so the assertion is `expect(true)` → a suite-integrity check
must RED. (b) Must-PASS non-canonical: a handler refactored so two returns share one marker helper
still passes (the contract is one marker per return, not one literal per return).

### Guard 2 — diff path derivation (#8274)

**Property.** No path outside `TARGET_ALLOW_RE` can be written by an applied proposal diff.
**Assembly.** Every site that turns proposal text into file writes — `applyDiffToWorkspace`
(:397-418) and any other `spawnGit(["apply"…])` call site; the guard greps for `"apply"` argv
occurrences so a second, later-added apply site is caught rather than assumed absent.
**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | `+++ x/.github/workflows/foo.yml` (non-`b/` prefix, **measured to apply today**) | RED |
| 2 | Diff with no `+++` header at all | RED — empty derived set must refuse, not pass |
| 3 | Two-file diff, first allowed + second forbidden | RED — second-member row |
| 4 | **`rename from AGENTS.rules.md` → an allowlisted `SKILL.md` path** (**measured**: `--numstat` reports only the destination and the apply deletes the source) | RED — rename/copy **source** must be allowlist-checked |
| 5 | `copy from` variant of row 4 | RED |
| 6 | *Dispatch row:* stub the derivation to return `[]` | RED |
**Harness rows.** (a) A RED fixture produced by editing the canonical must not be the only RED —
include one fixture written from scratch. (b) Must-PASS non-canonical: a legitimate two-file diff
touching `AGENTS.rules.md` **and** a `SKILL.md` must PASS.
**Anchor.** The derived path set comes from `git apply` itself, not from a stored list, so there is
no value a single diff can edit to weaken both the guard and the thing it guards.

### Guard 3 — pattern ↔ index parity

**Property.** The index states exactly the set of pattern pages, and every `evidence:` link resolves.
**Assembly.** A census over `learnings/patterns/*.md` (not a name list), plus the generated index.
**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | Add a pattern page without regenerating the index | RED |
| 2 | Break one `evidence:` path | RED — `unresolved` ≥1 |
| 3 | Hand-edit one index line so it disagrees with frontmatter | RED |
| 4 | *Dispatch row:* empty `patterns/` directory | RED — `patterns_checked=0` must fail |
**Harness rows.** Must-PASS non-canonical: a pattern page carrying `superseded_by` still passes.

### Guard 4 — ledger is actually read

**Property.** The proposer's assembled prompt contains the prior-proposal digest.
**Assembly.** The single prompt-assembly site (:570-600).
**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | Remove the ledger section from prompt assembly | RED |
| 2 | Assemble the prompt with a silently-empty ledger read | RED — must be distinguishable from a genuine "no rows" |
| 3 | Make the ledger read throw | RED — fail-closed, no proposal without the ledger |
**Harness rows.** Must-PASS: a ledger with zero rows on a fresh repo assembles a prompt whose
ledger section explicitly says "no prior proposals" rather than being absent.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_COMPOUND_PROMOTE_OUTCOME (WARN, one per run) + existing Sentry cron heartbeat
  cadence: weekly (cron "0 0 * * 0")
  alert_target: sentry_alert on feature=cron-compound-promote, op=zero-output-streak
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf
error_reporting:
  destination: Sentry via reportSilentFallback (feature=cron-compound-promote) + pino WARN to Better Stack
  fail_loud: true — the marker module never throws, but a missing marker fails Guard 1 in CI
failure_modes:
  - mode: proposer produces zero output indefinitely (the state this plan fixes)
    detection: outcome marker status + consecutive-zero streak counted from the ledger
    alert_route: Sentry alert at streak >= 4
  - mode: every cluster refused by a guard
    detection: marker `refusals` per-reason counts
    alert_route: same marker; non-zero refusals with zero opens is visible per-run
  - mode: pattern index drifts from pages
    detection: generate-kb-index.sh --check in lefthook/CI
    alert_route: CI red
  - mode: backfill writes a wrong pattern page
    detection: human PR review (G5) + evidence-path parity
    alert_route: CI red / review
  - mode: allowlist bypass via prefix-variant diff
    detection: Guard 2 mutation matrix
    alert_route: CI red
logs:
  where: Better Stack (soleur-inngest-vector-prd, host discriminator) via pino WARN+
  retention: source default (90d on the git-data source; shared source per vendor config)
discoverability_test:
  command: >
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh
    --since 200h --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 20
  expected_output: >
    at least one row whose decoded message carries status=<one of the 7 known values>;
    zero rows after a completed weekly run is the failure this plan fixes
  credentials_required: >
    Better Stack ClickHouse read (Doppler prd_terraform, BETTERSTACK_QUERY_*) — the property is
    "the marker reached the log sink", and no unauthenticated probe can verify that a
    container-emitted WARN line was ingested. A local grep verifies code shape only, which is
    exactly the substitution that produced the unobservable loop.
```

### Soak Follow-Through Enrollment

AC15 is time-gated on the Sunday cron, so it is enrolled rather than left to memory:

- Script: `scripts/followthroughs/compound-promote-outcome-8281.sh` — exit 0 when a
  `SOLEUR_COMPOUND_PROMOTE_OUTCOME` row exists after the merge timestamp; exit 1 while still
  waiting (the convention's "still soaking" semantic).
- Tracker directive on #8281, with the `follow-through` label:

```
<!-- soleur:followthrough
  script=scripts/followthroughs/compound-promote-outcome-8281.sh
  earliest=<merge date + 8 days>T00:00:00Z
  secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD
-->
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/issue-alerts.tf`: **one** `sentry_alert` resource,
  `feature=cron-compound-promote` + `op=zero-output-streak`, modelled on :1965.
- Provider already pinned: `jianyuan/sentry ~> 0.15.7`. No new provider, no new variable, **no
  operator mint** — the alert carries no secret.

### Apply path

`apply-sentry-infra.yml` auto-applies the sentry root **full-root on push to main** (its AC3 pins
that no `-target=` appears in that file). Adding a resource of an **existing** type needs no
workflow change and no guard-suite sweep. Blast radius: one new alert rule; no downtime.

### Distinctness / drift safeguards

Sentry infra is prd-only (no dev/prd split for alerts). Existing alerts carry
`lifecycle { ignore_changes = [environment] }`; the new resource follows suit.

### Vendor-tier reality check

`sentry_alert` is a standard-plan resource with 29 existing instances — no tier gate applies.

## Encryption Posture

Detection fires (a `.tf` file is edited), so this section is stated rather than skipped:

- **`at_rest`:** no new persistent store. Pattern pages are repository markdown under the existing
  committed-KB posture; no database, bucket, volume or queue is introduced.
- **`in_transit`:** no new cross-component connection. The Sentry alert is configuration on the
  **existing** Terraform→Sentry API connection (HTTPS, provider-verified certs), and the proposer's
  Anthropic call already exists — this plan changes its **payload size**, not its transport.
- **`exception`:** none — no plaintext exception, no `cert_verification: off`.

## Architecture Decision (ADR/C4)

### ADR

**ADR-225 — "The pattern layer is additive and its index is derived."** Provisional ordinal (free
across all 80 `origin/*` refs at plan time; re-verify before merge). Decision: recurring-failure
knowledge is consolidated into pattern pages that **link** learnings rather than merging them, and
the index is **generated from frontmatter** rather than authored.

`## Alternatives Considered` must record:
1. **#5292's lossy merge/archive pass** — rejected by CPO+CLO+CTO; this ADR explains why the
   additive layer is not that mechanism (and notes #5292 was bot-closed before its gate rendered).
2. **A model-maintained index** (the paper's design, where the Wiki Maintainer rewrites `index.md`
   each iteration and index quality is called "the MOST IMPORTANT part") — rejected: a derived index
   cannot drift, needs no LLM call, and removes the paper's own stated failure mode.
3. **A new top-level `knowledge-base/project/patterns/`** — rejected in favour of the path
   `compound-capture` Step 7 already prescribes, so the existing instruction becomes true rather
   than contradicted. Records the consequence: the gitleaks `private-key` allowlist covers that
   subtree (#3321).
4. **A Better Stack Logs alert for the zero-output streak** — rejected per ADR-096/ADR-218: those
   are for stateless per-bucket counts; a 4-week absence is windowed state.

Attribution: WikiSkill is CC BY 4.0; the ADR and any adapted prompt text carry the citation.

### C4 views

Enumeration against all three of `model.c4`, `views.c4`, `spec.c4` (the completeness mandate —
not a keyword grep):

- **External human actors:** none added. The operator is already modelled; no new correspondent,
  reviewer or recipient.
- **External systems:** none added. Anthropic (the proposer's LLM call) and Sentry are both already
  modelled, including `github -> sentry` and the Anthropic edge; this plan adds no vendor.
- **Containers / data stores:** none added. Pattern pages live inside the already-modelled
  knowledge-base repository artifact; no database, bucket or queue.
- **Access relationships:** unchanged — same actor, same repo, same human-gated draft-PR path.
- **Derived cardinalities:** `c4-count-parity.test.sh` derives its cron-monitor count from
  `grep -cF 'resource "sentry_cron_monitor"' cron-monitors.tf`; a `sentry_alert` does not move it.
  The parity test is nonetheless run at Phase 0.2 (pre) and Phase 6.2 (post) — a green run is the
  evidence, not this reasoning.

**Conclusion: no `.c4` edit required**, backed by the enumeration above plus the parity run — not
by an unsupported "None".

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The backfill merges two genuinely distinct patterns | Additive by construction (**G2**): no learning is touched, so a wrong merge is repaired by editing one pattern page. Batch-reviewed (**G5**). |
| This re-runs #5292's rejected mechanism | It does not merge, archive or rewrite learnings. G1–G5 adopted verbatim; AC7/AC8 assert it mechanically. |
| The pattern layer becomes another write-mostly artifact | Phase 5 gives it a **reader** in the same PR (the proposer). The #2723/#5292 lesson is that a producer without a live consumer dies — so producer and consumer ship together. |
| Backfill cost overruns | Phase 4.2 measures one batch and stops at >2× the estimate. |
| Pattern pages inside `learnings/` inherit **two** gitleaks rule blindings | **Corrected after review — the original mitigation here was false.** `knowledge-base/project/learnings/.*\.md$` appears in the `paths =` allowlist of **two** rules, not one: the `database-url-with-password` rule *and* the separate `id = "private-key"` rule. And `PII_REGEX` runs inside `collect-corpus` — it filters the proposer's **prompt input**, not any write path — so it does **not** cover pattern-page content. A machine-written, unbounded file set would inherit both blindings with no compensating control. **Resolution: place the layer at a sibling top-level `knowledge-base/project/patterns/`**, which no allowlist path predicate matches, so pattern pages are fully scanned. |
| The new marker is emitted at `info` and never reaches Better Stack | AC2 pins WARN; precedent `claude-cost-marker.ts`. |
| ADR-225 ordinal collides before merge | Re-derived at Phase 0.1 and again at ship; treated as provisional throughout. |
| The streak detector fires on a legitimately quiet corpus | The streak is about **zero output**, not zero merges; `no_action` with a recorded reason is still output. Threshold 4 weeks, tunable in one constant. |

## Non-Goals

- **NG1** No new-skill creation (Phase 2 of the spec) — gated on this phase producing proposals.
- **NG2** No moving `**Why:**` prose into `PURPOSE.md` (Phase 3).
- **NG3** No raw-trace layer; nothing is retained or transmitted beyond today's committed content
  (CLO P1).
- **NG4** No recurring recall benchmark. `learning-retrieval-bench.sh` is a one-shot diagnostic
  (~$2.68, ~50 min); its two runs swung 56–104% in 24h, which is below the noise floor for a gate.
  It may be run **once** before/after as a diagnostic, but it is not an acceptance criterion.
- **NG5** No reopening of #5292 and no consolidation pass.
- **NG6** No auto-merge; every proposal remains a human-reviewed draft PR.
- **NG7** No change to any SKILL.md `description:` line (the 2,442/2,442-word budget is untouched).

## Domain Review

**Domains relevant:** Product, Legal, Engineering (carried forward from the 2026-09-18 brainstorm's
`## Domain Assessments`; scope is unchanged — same artifact, same threshold, narrowed to Phase 1).

### Product

**Status:** reviewed (carry-forward)
**Assessment:** Beneficiary is the operator's own harness, not tenant workspaces — no per-tenant
scoping exists, so "Soleur got sharper" is the honest framing and "your workspace got smarter" is
barred. First step must be diagnosis, not a build: the loop has produced 0 PRs in ~10 weeks. North
star is recurrence-after-fix; leading indicator is accepted proposals per month; guardrail is net
skill count and description budget. Phase 1 is exactly the diagnosis-first increment.

### Legal

**Status:** reviewed (carry-forward)
**Assessment:** The method, the layer, the proposer and the gate are covered by the existing
register **provided they read only already-committed content** — which Phase 1 does (NG3). The raw
layer stays out of scope; had it been in scope, PA-31 §(g)(8) applies (a ReAct trace reader has no
prompt-assembly chokepoint to scrub). Paper ideas are not copyrightable and the arXiv listing is
CC BY 4.0 (verified), so adapted prompt text is permitted with attribution. `/soleur:gdpr-gate` is
**not** triggered: no new regulated-data surface, no retained or transmitted trace, no tenant
source — the proposer's Anthropic payload gets smaller and stays inside the same PA-31 activity.

### Engineering

**Status:** reviewed (carry-forward + this plan's research)
**Assessment:** The top gap is that the only machine writer produces nothing and cannot be
observed; pattern consolidation is second; skill creation waits for both. Procedural skills have no
train/val split, so the honest gate is human-merged draft PR + deterministic lints + a lagging
recurrence check (deferred to Phase 2 with the creation capability it tunes). Research added: five
of the six mechanisms already exist and are misfiring or unread, which turns this from a build into
an extension.

**Brainstorm-recommended specialists:** none named beyond the triad (all carried forward).

### Product/UX Gate

Not applicable — the mechanical UI-surface scan over `## Files to Edit` / `## Files to Create`
matches no UI-surface path (no `components/**/*.tsx`, no `app/**/page.tsx`, no layout). Tier:
**NONE**. This plan implements harness, CI and knowledge-base infrastructure only.

## Test Scenarios

1. Handler returns `disabled` → exactly one marker with `status=disabled`.
2. Handler returns `no-qualifying-clusters` → marker carries `clusters_proposed=0`.
3. Handler throws → marker with `status=error` **and** `reportSilentFallback` fires.
4. Diff `+++ x/.github/workflows/foo.yml` → refused, `diff-path-refused` counted.
5. Diff with no `+++` header → refused (empty derived set).
6. Two-file diff, second path forbidden → refused.
7. Legitimate two-file diff (`AGENTS.rules.md` + a `SKILL.md`) → **applies**.
8. Pattern page added without regenerating index → parity test RED.
9. `evidence:` path pointing at a deleted learning → parity RED with `unresolved=1`.
10. Empty `patterns/` dir → parity RED (`patterns_checked=0`), never green-by-vacuity.
11. Ledger contains a closed-unmerged PR digest → the same cluster is not re-proposed.
12. Ledger read throws → no proposal is made (fail-closed).
13. Four consecutive zero-output ledger rows → `op=zero-output-streak` Sentry event.
14. Backfill batch on a fixture corpus → no learning body modified (AC7 diff is empty).
