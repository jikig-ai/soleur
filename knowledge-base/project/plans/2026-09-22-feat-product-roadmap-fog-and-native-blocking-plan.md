---
title: "feat(product-roadmap): Not-Yet-Specified section + native issue blocking"
date: 2026-09-22
slug: feat-product-roadmap-fog-and-native-blocking
branch: feat-one-shot-8292-roadmap-fog-blocking
issue: 8292
closes: 8292
type: feature
lane: cross-domain
priority: p3-low
domain: product
brand_survival_threshold: none
---

## Overview

Bundle 5 of 5 from the mattpocock/skills peer-plugin audit. The roadmap records only scheduled work,
so a founder cannot tell work that is known to be coming but not yet phrasable apart from work that
was simply never written down. This plan adds three mechanics from the peer's wayfinder skill to the
product-roadmap skill and the roadmap document: a section for in-scope fog, a closed-issue convention
for ruled-out work, and GitHub-native blocking edges with a query for the takeable set.

## Research Insights

### Live dependency-API verdict (read-only, recorded verbatim, 2026-09-22)

GitHub's native issue-dependency API **is available** on `jikig-ai/soleur`, over REST, GraphQL and the
installed `gh` CLI. No prose fallback is needed or planned.

```text
$ gh api repos/jikig-ai/soleur/issues/8292/dependencies/blocked_by
[]
$ gh api repos/jikig-ai/soleur/issues/8292/dependencies/blocking
[]
$ gh api repos/jikig-ai/soleur/issues/8292/sub_issues
[]
$ gh api graphql -f query='query{repository(owner:"jikig-ai",name:"soleur"){issue(number:8292){number
    blockedBy(first:10){totalCount nodes{number}} blocking(first:10){totalCount nodes{number}}
    subIssues(first:10){totalCount nodes{number}}
    issueDependenciesSummary{blockedBy totalBlockedBy blocking totalBlocking}
    trackedIssues(first:5){totalCount}}}}'
{"data":{"repository":{"issue":{"number":8292,"blockedBy":{"totalCount":0,"nodes":[]},
 "blocking":{"totalCount":0,"nodes":[]},"subIssues":{"totalCount":0,"nodes":[]},
 "issueDependenciesSummary":{"blockedBy":0,"totalBlockedBy":0,"blocking":0,"totalBlocking":0},
 "trackedIssues":{"totalCount":0}}}}}
$ gh issue view 8292 --json blockedBy,blocking,parent,subIssues
{"blockedBy":{"nodes":[],"totalCount":0},"blocking":{"nodes":[],"totalCount":0},"parent":null,"subIssues":{"nodes":[],"totalCount":0}}
$ gh --version            # gh version 2.101.0 (2026-09-15)
$ gh issue edit --help    # --add-blocked-by / --remove-blocked-by / --add-blocking / --remove-blocking,
                          #   --add-sub-issue / --parent
$ gh issue create --help  # --blocked-by numbers / --blocking numbers / --parent number
```

What `gh` asks GitHub for when it renders `blockedBy` (captured with `GH_DEBUG=api`, identical for
`gh issue view` and `gh issue list --json number,assignees,blockedBy`):
`blockedBy(first:50){nodes{id,number,title,url,state,repository{nameWithOwner}},totalCount}` — every
node carries its own `state`, so "unblocked" is decidable from one `gh issue list` call without a
second query per blocker.

Four facts the plan is built on, each measured:

1. **The endpoints resolve, but zero issues in the repo carry an edge today.** A GraphQL sweep of
   issues for `issueDependenciesSummary.totalBlockedBy>0 or totalBlocking>0` returned nothing; the 118
   open Phase 4 issues report `blocked=0`. The feature starts from an empty graph. Consequence: the
   "open vs closed blocker" semantics cannot be observed on this repo before the first edge exists, so
   the frontier filter reads each blocker node's `state` directly rather than trusting the summary's
   `blocked_by` (open) vs `total_blocked_by` (all) split.
2. **The REST search qualifier `is:blocked` is not a dependency filter.** In-repo it returns 8 issues,
   which are exactly the 8 carrying the `blocked` **label**, each with
   `issue_dependencies_summary: {blocked_by:0, ...}`; globally `is:issue is:blocked -label:blocked`
   returns 176,807,862 results, i.e. the qualifier is ignored. The frontier therefore filters
   client-side; no search qualifier appears anywhere in the shipped prose.
3. **`gh issue list --json` exposes `blockedBy`, `blocking`, `parent`, `subIssues`, `assignees`** (from
   `gh issue list --json` with no field list). The field first appears in the **gh v2.94.0** release
   notes (scan of the last 40 `cli/cli` releases). An older `gh` rejects the field with
   `Unknown JSON field`, which the current script would silently turn into "no open issues" (fact 4).
4. **Two pre-existing defects in `product-roadmap next`, measured live:**
   - `bash plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh next` prints
     `roadmap-next: Phase 5 — next codeable item: #1423 feat: Electron/Tauri desktop app` while Phase 4
     is the active phase. Cause: phase selection reads the `## Current State` "X open, Y closed" cells,
     and Phase 4's row deliberately carries no frozen count ("counts are not frozen here — derive them
     from the milestone itself"), so `extract_phase_counts` skips it and Phase 5 (6 open) wins.
   - The issue fetch is `gh issue list --milestone "$mstitle" --state open --json number,title,labels`
     with no `--limit`: it returns **30** of Phase 4's **118** open issues (measured both ways), so
     "lowest-numbered open issue" is the lowest of the 30 most recent. And
     `2>/dev/null) || issues='[]'` turns any `gh` failure into "no open issues — no actionable next item".

   A frontier that composes with `next` inherits all three. See Research Reconciliation.

Sub-issues are available too, and **not used**: they express hierarchy, not order, and the frontier
is an ordering question. `trackedIssues` (the older tasklist relationship) resolves but is superseded
by native dependencies.

### Premise Validation (Phase 0.6)

- **#8292** is OPEN, not closed by any PR. Premise holds.
- **PR #8284** (cited by the issue as where the audit "landed") is **still OPEN**; on `origin/main`,
  `knowledge-base/product/competitive-intelligence.md` has no mattpocock entry (`grep -i mattpocock`
  returns nothing). The audit's Tier 1 row exists only on that PR's branch. This does not block the
  plan (the issue body is the source of truth, and the NOTICE entry for mattpocock/skills already
  exists on main with bundles 1-4 in `Used in:`), but no shipped file may cite the competitive-
  intelligence entry as if it were on main.
- **"`product-roadmap` Phase 0.6 verifies blocked-by citations for staleness"** (issue body, *Why*):
  **stale attribution.** `product-roadmap/SKILL.md` has no Phase 0.6; the staleness check on cited
  `#N` / "blocked by #N" is `plan/SKILL.md` Phase 0.6 item 1. The underlying claim (blocking is prose
  today) holds.
- **"`plan` Phase 0.7 bans TODO/TBD/N/A/placeholder"**: partially accurate. Phase 0.7's literal ban
  (`plan/SKILL.md:254-256`) is on the **skeleton's placeholder prose**; the plan-wide bans live in
  Phase 2.6 Step 4 (User-Brand Impact) and the Observability / Encryption / Guard-contract reject
  conditions enforced by `deepen-plan`. The routing note therefore goes beside the Phase 0.7 sentence
  (the one the issue names) and speaks of "the token bans", not of one phase.
- **Peer source** read at the NOTICE-pinned SHA:
  `gh api repos/mattpocock/skills/contents/skills/engineering/wayfinder/SKILL.md?ref=c55ee46073ed923f86ce59a5eb3b6d895095d1b7`.
  The three mechanics are in its §The map body, §Tickets (blocking + frontier), §Fog of war and
  §Out of scope. The attribution path convention on main is
  `mattpocock/skills/skills/engineering/<skill>/SKILL.md` (the repo nests a `skills/` directory; see
  the ten existing comments, e.g. `plugins/soleur/skills/reproduce-bug/SKILL.md:6`).
- **Follow-ups #8506, #8497, #8499, #8505, #8486** are all OPEN and none touches the files in this
  plan. Not relevant; not mentioned in shipped files.

### Property List (Phase 0.6b)

- **P1.** A reader of `roadmap.md` can see in-scope work that is coming but not yet phrasable, and
  can tell it apart from scheduled work, deliberately-later work and ruled-out work.
- **P2.** Anything that sits in none of those places is, by construction, forgotten — so "not decided
  yet" and "forgot" are distinguishable (the CPO gate).
- **P3.** Ruled-out work is unambiguously off the frontier and never re-enters it silently.
- **P4.** Ruled-out work does not pollute the record of decisions actually made.
- **P5.** Blocking between roadmap issues is machine-readable and visible in GitHub's own UI.
- **P6.** The founder can list what is takeable now (open, unblocked, unclaimed) and `next` recommends
  from that set, never a blocked or claimed issue.
- **P7.** Plans stay TBD-free: unphrasable questions are routed up to the roadmap, not down into plans.
- **P8.** Peer-derived prose is attributed per file and in NOTICE.

### Cut List (Phase 0.6b)

- **A new skill / wayfinder import** → buys nothing P1-P8 need; the issue forbids it. Cut.
- **Peer "map" issue + child tickets + `wayfinder:*` labels** → P5/P6 are bought by native edges on
  the roadmap's existing issues and milestones. Cut.
- **Ticket claiming by self-assignment as a new workflow** → P6 only needs to *read* assignment
  ("unclaimed" = no assignee); no claiming step is added. Cut.
- **Sub-issues** → buy hierarchy, which the phase milestones already provide. Cut.
- **A new top-level `frontier` sub-command** → a `--frontier` flag on `next` buys P6 with no skill
  `description:` change (the description names `next`), keeping `SKILL_DESCRIPTION_WORD_BUDGET`
  untouched. Cut in favour of the flag.
- **A "Decisions so far" section in roadmap.md** → the roadmap already has `### Architecture Decision:`
  subsections, `## Domain Review Summary`, and ADRs; P4 is met by keeping Out-of-Scope lines out of
  those, not by adding another. Cut.
- **Search-qualifier frontier (`is:blocked`, `no:assignee`)** → measured unreliable (fact 2). Cut.
- **A cron-roadmap-review prompt change** → the cron's rules quantify over "each roadmap phase table"
  and "each feature row"; bullet-list sections are outside its reach (read at
  `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts:118-185`). Not needed for P1-P8.
  Cut (recorded under Risks).

### Value-proposition measurement (Phase 0.6c)

No cost or performance saving is claimed. Skipped.

### Relevant files (all read)

- `plugins/soleur/skills/product-roadmap/SKILL.md` — 276 lines; description (unchanged by this plan):
  `"This skill should be used when roadmapping. Sub-commands: validate (...) and next (...)."`
- `plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh` — 195 lines, read-only module;
  public functions `extract_phase_counts`, `reconcile_counts`, `pick_next_action`; `main` dispatches
  `validate|next`, `*` prints `usage: roadmap-reconcile.sh [validate|next]` and returns 64.
- `plugins/soleur/test/roadmap-reconcile.test.sh` — 154 lines, hermetic (sources the module, feeds
  synthesized JSON), TS1-TS7; TS6 covers `pick_next_action`.
- `knowledge-base/product/roadmap.md` — 501 lines; sections: Strategic Context (+ Themes,
  Architecture Decisions), Domain Review Summary, Current State, Phases (tables), Post-MVP / Later,
  Generated footer. Open PR #6987 also touches it (weekly CPO count sync).
- `plugins/soleur/skills/plan/SKILL.md` — 1144 lines, **119,300 bytes against a 120,000-byte ceiling**
  (`plugins/soleur/test/skill-body-budget.json`, enforced by `scripts/lint-skill-body-budget.py` from the
  merge base: 700 bytes of headroom, and the ceiling cannot be raised in the same diff).
- `plugins/soleur/NOTICE` — mattpocock/skills entry at lines 126-158, `Used in:` ends with
  `skills/skill-creator/references/authoring-levers.md (#8290)`.
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — roadmap writer (PRs); reads
  phase tables only.

### Consumers of the changed surfaces (grep of plans/, specs/, skills, agents, apps)

- `roadmap-reconcile.sh validate` — called by `plugins/soleur/skills/brainstorm/SKILL.md:146` (Phase
  0.25). **Unchanged** by this plan; `validate` keeps its exact output.
- `roadmap-reconcile.sh next` / `pick_next_action` — no programmatic caller outside the skill and its
  test. Historical plans/specs naming it (`knowledge-base/project/plans/2026-06-30-feat-roadmap-program-layer-plan.md`,
  `knowledge-base/project/specs/feat-roadmap-program-layer/{spec,tasks}.md`) are executed records; FR3 there
  ("the single next action") still holds.
- `roadmap.md` readers: `plugins/soleur/agents/product/cpo.md:23` (Current State), brainstorm Phase 0.25,
  `cron-roadmap-review.ts`, `cron-growth-audit.ts` (milestone lookup + row updates),
  `apps/web-platform/server/conversations-tools.ts:68` (path string). None parses by section list;
  adding two bullet-list sections breaks none.

### Institutional learnings that bind this plan

- `knowledge-base/project/learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` and
  `2026-03-04-gh-jq-does-not-support-arg-flag.md` — any variable in a jq filter goes through a standalone
  `jq --arg`, never `gh --jq` with `--arg`.
- `knowledge-base/project/learnings/2026-03-24-gh-api-paginate-concatenated-arrays.md` — use
  `gh issue list --limit`, not `gh api --paginate`, for the issue fetch (one JSON array).
- `knowledge-base/project/learnings/2026-04-03-milestone-roadmap-integrity-audit.md` — the cron's
  bidirectional rule ("every phase-table row has an issue") is why fog must not be a table.
- `knowledge-base/project/learnings/workflow-patterns/2026-05-29-net-issue-flow-gate-at-filing-site-not-just-ship.md`
  — every issue filed while doing this work goes on the PR's `Filed:` line.
- Bundle-4 lessons carried by the brief: consumers grepped (above); no link to `specs/feat-*/` from a
  shipped file; a constrained dry run of the rewritten skill prose is a task (Phase 4).

### Functional overlap (Phase 1.5b)

`soleur:engineering:discovery:functional-discovery` found partial overlap only, none worth installing:
`gastownhall/beads` (own tracker + ready-work query, not GitHub-native), `aiskillstore/marketplace`
managing-relationships (GraphQL blocking-edge CRUD, no frontier), `github/awesome-copilot` github-issues,
`marcusgoll/Spec-Flow` roadmap-integration, `shipshitdev/skills` roadmap-to-milestones. Nothing covers
the Not-Yet-Specified or Out-of-Scope mechanics. Nothing installed.

### Research decision (Phase 1.6)

Strong local context and a live-verified API; no external research agents. The peer source was read
directly at the pinned SHA.

## Research Reconciliation — Issue Body vs. Codebase

| Issue / brief claim | Reality (measured) | Plan response |
|---|---|---|
| "blocking in Soleur is prose (`blocked by #N`) that `product-roadmap` Phase 0.6 verifies" | product-roadmap has no Phase 0.6; that check is `plan/SKILL.md` Phase 0.6 item 1 | No product-roadmap text cites a Phase 0.6. The plan note sits in `plan/SKILL.md`. |
| "`plan` Phase 0.7 bans TODO/TBD/N/A/placeholder" | Phase 0.7 bans them in skeleton stub prose (`:254-256`); plan-wide bans are Phase 2.6 / 2.9 / 2.11 / 2.12 via `deepen-plan` | The note sits beside the Phase 0.7 sentence and says "the token bans", covering both. |
| "Fix-Size: 160 lines / 3 files" | Composing a frontier with `next` requires touching `roadmap-reconcile.sh` and its test (two defects plus the frontier itself live there) | Estimate restated: about 95 prose lines across the 3 named files + NOTICE, plus about 70 script lines and about 90 test lines. Called out in the PR body. |
| Audit Tier 1 entry "landed via PR #8284" | PR #8284 is OPEN; main's competitive-intelligence.md has no mattpocock entry | No shipped file links or quotes that entry. NOTICE's existing pinned SHA is the provenance anchor. |
| "`product-roadmap next` already picks exactly one next issue deterministically" | It picks deterministically, from the wrong phase (Phase 5 instead of Phase 4) and from the 30 most recent issues only | Fold both fixes into this PR as their own commit with a named acceptance check (CPO and CTO both concur; see Domain Review). |
| "Native blocking edges ... plus a frontier query" (verify API) | Available: REST `dependencies/blocked_by`, GraphQL `blockedBy`, `gh issue edit --add-blocked-by`, `gh issue list --json blockedBy` (gh >= 2.94.0) | Adopt the native relationship. Filter client-side (the `is:blocked` search qualifier is not honored). |

## User-Brand Impact

**If this lands broken, the user experiences:** `product-roadmap next` recommends a blocked or claimed
issue, or reports "nothing takeable" for a phase that has takeable work; or the roadmap's
Not-Yet-Specified / Out-of-Scope sections mislead the founder about what has been decided.

**If this leaks, the user's workflow is exposed via:** nothing new. The change reads public issue
metadata already fetched by `gh`, and writes only to issues and `roadmap.md` in the founder's own
repository, through the interactive workshop that already writes both.

**Brand-survival threshold:** none

- threshold: none, reason: the diff touches plugin skill prose, a read-only reporting script, and a
  product document; no credentials, user data, auth, payments, or infrastructure path is touched.

## Design Decisions

### D1 — Four places, one rule for "forgotten"

Every known piece of in-scope work sits in exactly one of four places; anything in none is forgotten.
Post-MVP is defined by **milestone membership**, not by having a table row (CPO: the Post-MVP
milestone holds 1,207 open issues against about 32 table rows, so "has a row" would label about 1,175
issues forgotten). An open issue with **no milestone** is named as the unsorted set (209 today, per
the CPO's count). This is the mechanism for the CPO gate; the sections alone would not deliver it.

### D2 — The graduation test is the peer's, glossed in plain words

The rule stays the issue's wording ("can you state the question precisely now — not can you answer it
now"). The CPO's plain-language gloss ("can you write the issue title today?") is added beside it,
because a non-technical founder applies that more reliably. The gloss never replaces the rule.

### D3 — Fog and scope are bullet lists, never tables

`cron-roadmap-review.ts` enforces "every feature in a roadmap phase table MUST have a linked GitHub
issue". A Not-Yet-Specified entry has no issue by definition, so a table would be flagged
`MISSING_ISSUE` weekly. Both sections are bullet lists, which the cron's phase-table rules do not
reach.

### D4 — `--frontier` is a flag on `next`, not a new sub-command

It keeps the skill `description:` unchanged (so `SKILL_DESCRIPTION_WORD_BUDGET` needs no re-measure)
and makes the composition literal: **`next` prints the first item of `next --frontier`**, an invariant
the test asserts.

### D5 — The frontier fails closed

- A blocker counts as resolved only when its node `state == "CLOSED"` (one jq clause; any other value
  holds the issue back).
- If `blockedBy.totalCount` exceeds the returned nodes, the issue is held back. The realistic case is a
  blocker in a repository the token cannot read (the node is omitted, the count is not); the same
  clause covers the 50-node page.
- `gh` failure exits 2 with its stderr. An old `gh` fails this way, not by returning JSON without the
  field (fact 3), so the script matches `Unknown JSON field` in the captured stderr and prints
  `requires gh >= 2.94.0 (upgrade: https://github.com/cli/cli#installation)`. A defensive
  `all(.[]; has("blockedBy") and has("assignees"))` check runs before filtering (in jq `null > 0` is
  false, so a missing field would otherwise read as unblocked).
- An empty frontier prints NONE with the phase and the held-back counts, so a fully blocked phase never
  reads as finished. It **stays on that phase**; it never falls through to the next one.
- `--limit 1000` is a ceiling well above the largest phase (118 open). No limit-equality exit is added
  (cut at review: no current case).

### D6 — Phase selection comes from live milestones, in a pure function

`pick_phase` returns the lowest-numbered **open** milestone whose title matches `^Phase [0-9]+[:( ]`
and whose `open_issues > 0`, comparing numbers numerically (`Phase 10` after `Phase 2`). `Post-MVP /
Later` can never match. `validate` is untouched: it still keys off Current State cells, which is its
contract with brainstorm Phase 0.25.

### D7 — Attribution only where peer prose lands

Only `plugins/soleur/skills/product-roadmap/SKILL.md` takes peer prose (the rules, including the
quoted graduation test), so only it carries the comment and only it joins NOTICE `Used in:`. The two
roadmap.md section intros and the plan note are Soleur-authored and share no 8-word shingle with the
peer file (checked in Phase 4). This follows bundle 3's recorded precedent in NOTICE ("Nothing under
knowledge-base/ carries the comment ... attributing them would be a false attribution").

### D8 — Headless mode writes nothing new

The workshop's existing Headless Mode section already skips prompts and uses KB-derived defaults; one
sentence is added to it: in headless mode, never graduate a Not-Yet-Specified entry, close an issue
as out of scope, or add a blocking edge (these are founder decisions); report counts only.

## Files to Edit

1. **`plugins/soleur/skills/product-roadmap/SKILL.md`** (about +45 lines; description unchanged). Each
   rule is stated once; other places point to it.
   - Sub-commands table, `next` row: "report the next action for the first incomplete phase, chosen
     from its frontier; `next --frontier` lists the whole frontier."
   - `### Sub-command: next`: the code block shows both `... roadmap-reconcile.sh next` and
     `... roadmap-reconcile.sh next --frontier`, and the dispatch sentence says the remaining arguments
     after `next` are passed through to the script. The paragraph states, once: the phase is the lowest
     open `Phase N` milestone with open issues; the **frontier** is its open issues with no open blocker
     and no assignee; `next` names the lowest-numbered frontier issue; `--frontier` prints a summary line
     first, then every frontier issue; exit 2 means the data could not be trusted (old `gh`, fetch
     failure), never "nothing to do".
   - New section `## Where Work Lives on the Roadmap` between `## Sub-commands` and `## Roadmap
     Context`, carrying the attribution comment as its first line:
     `<!-- Inspired by mattpocock/skills/skills/engineering/wayfinder/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->`
     Content, in this order:
     - The four-places table (D1): phase row = "we are building this in this phase" (open issue,
       `Phase N` milestone); Post-MVP / Later = "we know exactly what to build; we chose not to build it
       yet" (open issue in that milestone; the table lists highlights only); Not Yet Specified = "we know
       we will need something here; we cannot yet say what question it answers" (no issue); Out of Scope
       = "we decided no" (issue closed `not planned`). Then one line: work in none of these places was
       forgotten; an open issue with no milestone is unsorted.
     - `### Not Yet Specified`: the test (D2), with the gloss "can you write the issue title today?";
       file an issue when the question is sharp even if blocked (and add the edge); do not pre-slice fog
       into row-sized pieces (one entry may become several issues, or none); graduation = file the issue
       with `--milestone` (and `--blocked-by` when known), add the row, delete the entry.
     - `### Out of Scope`: scope, not sharpness, puts work here (beyond the Strategic Themes); close with
       `gh issue close <N> --reason "not planned" --comment "Out of scope: <reason>"` and add
       `- [#<N> <title>](<url>) — <reason>`; it never graduates (a redrawn theme means a new issue); it
       stays out of the decisions record (no `### Architecture Decision` subsection, ADR or Domain
       Review Summary row).
     - `### Blocking Edges`: `gh issue edit <N> --add-blocked-by <M>` / `--remove-blocked-by <M>`, wired
       in a second pass once every issue exists (this is also where workshop Phase 3 points); use
       dependencies, not sub-issues (phases give hierarchy; blocking is order); requires gh >= 2.94.0;
       a prose "blocked by #M" may keep the human reason, but the edge is what the frontier reads.
   - Phase 1: new `### 1.6 Fog and Scope Walk` after 1.5 Gap Check: gaps the founder cannot yet phrase
     become Not-Yet-Specified entries; each existing entry → graduate / keep / rule out; each
     Out-of-Scope line → confirm the issue is still closed
     (`gh issue view <N> --json state --jq .state`) and put a reopened one back to the founder.
   - Phase 2 Generate, **Required sections**: add `## Not Yet Specified` and `## Out of Scope` as
     bullet lists (D3), written with an explicit empty-state line when empty.
   - Phase 3: one sentence after 3.2: record dependencies surfaced in the workshop as blocking edges
     (see Blocking Edges), then show the founder `next --frontier`.
   - Headless Mode section: the one sentence in D8.
2. **`plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh`** (about +55 lines)
   - Header comment: add `pick_phase` and `filter_frontier` to the public-function list, and note that
     `pick_phase` depends on milestones being titled `Phase N: ...`.
   - `_milestones_json`: add `state` to the projected fields (`{title, state, open_issues, closed_issues}`).
     `reconcile_counts` ignores it; `validate` verdicts are unchanged.
   - New `pick_phase MILESTONES_JSON_FILE` → `N|title` or empty (D6). One jq pass.
   - New `filter_frontier ISSUES_JSON_FILE` → one JSON object
     `{frontier:[...sorted by number], blocked:<n>, claimed:<n>}` (D5). `blocked` counts every issue held
     back by a blocker, assigned or not; `claimed` counts unblocked issues with an assignee. Returns 2
     when the field check fails. **One jq invocation**: callers pass FIFOs (`<(printf ...)`), which a
     second read would find empty (the trap the comment at `roadmap-reconcile.sh:66-68` records).
   - `pick_next_action`: unchanged (it receives the frontier array).
   - `main next`: parse an optional `--frontier` (any other extra argument → usage, exit 64); phase
     from `pick_phase`; fetch with
     `if ! issues="$(gh issue list --milestone "$mstitle" --state open --limit 1000 --json number,title,labels,assignees,blockedBy 2>"$errf")"; then ...; return 2; fi`
     (`local issues` declared on its own line so `set -e` does not mask the status; stderr to a
     `mktemp` file, matched for `Unknown JSON field`). Rendering: `next` keeps today's three output
     shapes (CODEABLE / OPERATOR / none), plus `(N blocked, M claimed)` on the phase line;
     `--frontier` prints `roadmap-frontier: Phase N — F ready, B blocked, C claimed` first, then one
     `CODEABLE|#N|title` or `OPERATOR|#N|title` line per frontier issue, classified in a single jq pass
     (not one `pick_next_action` call per issue). Usage line becomes
     `usage: roadmap-reconcile.sh [validate|next [--frontier]]`.
   - jq variables go through standalone `jq --arg` / `--argjson`, never `gh --jq` with `--arg`.
3. **`plugins/soleur/test/roadmap-reconcile.test.sh`** (about +90 lines) — scenarios TS8-TS17 below;
   TS7 (zero writes) extended to call `pick_phase` and `filter_frontier`. `main` is exercised through a
   **fake `gh`** script written to a temp dir placed first on `PATH` (it prints fixture JSON per
   subcommand, or exits 1 with a chosen stderr), so rendering and exit codes are tested hermetically.
4. **`knowledge-base/product/roadmap.md`** (about +16 lines) — two sections after `### Post-MVP / Later`
   and before `## Pricing`, each preceded by the file's `---` separator:
   - `## Not Yet Specified` — one Soleur-authored sentence ("In scope and coming, but not yet sharp
     enough to file as an issue; each entry moves into a phase or Post-MVP row once its question is
     clear. Rules live in the product-roadmap skill.") then `_None recorded._`
   - `## Out of Scope` — one sentence ("Work ruled out of this roadmap. Each line links an issue
     closed as not planned and says why; these entries never move back.") then `_None recorded._`
   - Frontmatter: bump `last_updated` only, never `last_reviewed` (ADR-094).
   - No entries are seeded. The CPO named two candidates (the post-validation pricing model; what
     happens if Phase 4 validation fails) and was explicit that writing them is a founder decision; the
     workshop's 1.6 walk raises them.
5. **`plugins/soleur/skills/plan/SKILL.md`** (+2 lines, **must stay under 120,000 bytes**; 700 bytes
   of headroom) — after the Phase 0.7 "Stub no conditional section" paragraph, this text (about 210
   bytes; no attribution comment, D7):

   ```markdown
   **Fog belongs in the roadmap.** A question you cannot yet state precisely goes under `## Not Yet Specified` in `knowledge-base/product/roadmap.md` (`soleur:product-roadmap`), never into a plan `TBD`.
   ```
6. **`plugins/soleur/NOTICE`** (about +8 lines, matching the Bundle 1-4 paragraph shape) — in the mattpocock/skills entry: append
   `skills/product-roadmap/SKILL.md (#8292)` to `Used in:`; add a "Bundle 5 (#8292, from
   skills/engineering/wayfinder/SKILL.md at the same HEAD)" paragraph after Bundle 4 naming the three
   imported mechanics (the Not-Yet-Specified fog section with its state-the-question test and
   no-pre-slicing rule; out-of-scope-as-closed-issue kept out of the decisions record; native blocking
   edges with an open/unblocked/unclaimed frontier) and the elements deliberately NOT imported: the
   map issue with child decision tickets and `wayfinder:*` labels, the four ticket types, claim-by-
   self-assignment, one-ticket-per-session, refer-by-name, and sub-issue hierarchy (one clause each);
   plus one sentence that roadmap.md and the plan note carry no comment because they take no peer prose.

## Files to Create

None.

## Explicitly NOT edited

- `plugins/soleur/skills/product-roadmap/SKILL.md` frontmatter `description:` (so no budget re-measure).
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` (D3 keeps fog out of its reach).
- `plugins/soleur/skills/brainstorm/SKILL.md` (calls `validate`, which is unchanged).
- `AGENTS.rules.md` (any rule edit goes to a separate PR).
- `knowledge-base/product/competitive-intelligence.md` (the audit row belongs to PR #8284).

## Open Code-Review Overlap

1 open scope-out touches these files: #4133 (schema parity test for the `## Observability` block,
names `plugins/soleur/skills/plan/SKILL.md`). **Acknowledge:** different concern (Observability
schema parity), and this plan adds one paragraph in Phase 0.7 that touches no schema text. Remains open.

## Implementation Phases

### Phase 0 — Preconditions (no writes to shipped files)

1. `gh --version` reports >= 2.94.0, and
   `GH_DEBUG=api gh issue list --state open --limit 1 --json number,assignees,blockedBy 2>&1 | grep -c 'state,repository'`
   prints at least 1 (the list query requests each blocker node's `state` and the connection's
   `totalCount`; verified 2026-09-22). No issue in the repo has an edge, so no live fixture with real
   blockers exists; the test fixtures are synthesized in exactly that captured shape
   (`{"blockedBy":{"nodes":[{"number":N,"state":"OPEN","repository":{"nameWithOwner":"o/r"}}],"totalCount":1}}`).
2. Record baselines: `wc -c plugins/soleur/skills/plan/SKILL.md` (119,300);
   `bash plugins/soleur/test/roadmap-reconcile.test.sh` (all pass);
   `bun test plugins/soleur/test/components.test.ts` (pass);
   capture milestones once and the pre-change roadmap for the Phase 3 comparison:
   `gh api 'repos/{owner}/{repo}/milestones?state=all&per_page=100' --jq '[ .[] | {title, open_issues, closed_issues} ]' > "$SCRATCH/ms.json"`,
   `git show origin/main:knowledge-base/product/roadmap.md > "$SCRATCH/roadmap-before.md"`
   (`$SCRATCH` = a `mktemp -d` directory).

### Phase 1 — Script: tests first, then code (own commit)

1. Write TS8-TS17 against the not-yet-existing functions; run; confirm they fail for the right reason,
   not a harness error. The suite runs under `set -euo pipefail`, so each new block first checks
   `declare -F pick_phase >/dev/null || fail "pick_phase not defined"` (likewise `filter_frontier`),
   and every exit-code capture uses `rc=0; out="$(... 2>&1)" || rc=$?`.
2. Implement `pick_phase`, `filter_frontier`, the `next` rewrite and `--frontier`.
3. Run the suite green. Run live, read-only: `roadmap-reconcile.sh next` names an issue from the lowest
   open `Phase N` milestone with open issues (Phase 4 as of 2026-09-22), and
   `roadmap-reconcile.sh next --frontier` shows the same issue first (informational; the gate is the
   fake-`gh` tests).
4. Commit: `fix(product-roadmap): next picks from the live phase and the unblocked frontier`
   (body names the Phase-5 mis-selection and the 30-issue truncation as pre-existing defects).

### Phase 2 — Skill prose (product-roadmap/SKILL.md)

Write the edits in Files to Edit item 1. Keep the section in Soleur's voice except the quoted test.

### Phase 3 — roadmap.md, plan note, NOTICE

Files to Edit items 4-6. Re-measure `plan/SKILL.md` bytes (< 120,000) and run
`python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`. Then, in one
shell with the module sourced, diff
`reconcile_counts "$SCRATCH/roadmap-before.md" "$SCRATCH/ms.json"` against
`reconcile_counts knowledge-base/product/roadmap.md "$SCRATCH/ms.json"`: identical (same milestone
snapshot on both sides, so no live drift can flip it).

### Phase 4 — Verification of prose

1. **Constrained dry run of the rewritten prose.** Spawn a subagent with ONLY the new/changed
   product-roadmap SKILL.md sections, the new roadmap.md sections and the plan note as its input, and
   three synthetic situations: (a) "we'll need some story for team billing but don't know what yet";
   (b) "#9999 desktop tray icon — founder says never"; (c) "#9001 can't start until #9000 ships".
   It must state, for each, which place the work goes, the exact `gh` command it would run (without
   running any), and list every sentence it could not follow or found ambiguous. Every reported
   sentence is rewritten before commit; the PR body lists the count of flagged sentences and how each
   was resolved. Also ask it to classify one sharp-but-blocked question (expected: file an issue plus
   an edge, not fog).
2. **Shingle check** (backs D7's no-peer-prose claim and the NOTICE sentence): fetch the peer file to
   `$SCRATCH/wayfinder.md` with
   `gh api 'repos/mattpocock/skills/contents/skills/engineering/wayfinder/SKILL.md?ref=c55ee46073ed923f86ce59a5eb3b6d895095d1b7' --jq .content | base64 -d`,
   write each new text (the two roadmap.md section intros, the plan note, the SKILL.md section) to its
   own file, then per file run
   `bun -e 'import {shingles} from "./plugins/soleur/test/lib/shingles.ts"; const fs=require("fs"); const [a,b]=process.argv.slice(1).map(f=>shingles(fs.readFileSync(f,"utf8"))); console.log(a.size, [...a].filter(x=>b.has(x)).length)' "$SCRATCH/<new>.txt" "$SCRATCH/wayfinder.md"`.
   Expected: 0 shared for the roadmap.md intros and the plan note; for the SKILL.md section, shared
   shingles only inside the quoted test sentence. The roadmap intros and plan note are short, so they
   are also combined into one file that must yield at least 10 shingles (non-vacuity floor).
3. Targeted suites only (never `scripts/test-all.sh`):
   `bash plugins/soleur/test/roadmap-reconcile.test.sh`,
   `bun test plugins/soleur/test/components.test.ts`,
   `bun test plugins/soleur/test/plan-skeleton-checkpoint.test.ts`,
   `bun test plugins/soleur/test/devin-cloud-mode.test.ts`,
   `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`.
   Commits use `LEFTHOOK_EXCLUDE=bun-test`.

### Phase 5 — PR

PR body: `Closes #8292` (only); the live API verdict; the two pre-existing `next` defects and why they
are folded in; the line-count restatement; `Filed:` line listing every issue filed during the work
(expected: none).

## Test Scenarios

All hermetic (synthesized JSON, sourced module), added to `plugins/soleur/test/roadmap-reconcile.test.sh`:

- **TS8 pick_phase** — milestones: Phase 1 closed 0 open; Phase 4 open 118; Phase 5 open 6;
  `Post-MVP / Later` open 1207 → `4|Phase 4: Validate + Scale`.
- **TS8c** — `Phase 10` open and `Phase 2` open → Phase 2 (numeric sort).
- **TS8d** — only `Post-MVP / Later` open with issues → empty (all phases complete).
- **TS8e** — `Phase 4` closed with open issues left → skipped (open milestones only).
- **TS9 open blocker** — issue blocked by a node `{state:"OPEN"}` → not in frontier, `blocked == 1`.
- **TS10 closed blocker** — node `{state:"CLOSED"}` → in frontier.
- **TS11 assigned** — unblocked, one assignee → not in frontier, `claimed == 1`.
- **TS11b blocked and assigned** — counts toward `blocked`, not `claimed`.
- **TS12 unreadable blocker** — `nodes: []`, `totalCount: 1` → held back.
- **TS13 end-to-end via fake `gh`** — mixed fixture (one blocked, one claimed, two ready): `next` names
  the lower ready issue and prints `(1 blocked, 1 claimed)`; `next --frontier` prints the summary line
  `2 ready, 1 blocked, 1 claimed` and its first item line carries the same `#N`. The fixture roadmap's
  Phase 4 row has no count cell and Phase 4 still wins over Phase 5 (the live defect, tested through
  `main`).
- **TS14 empty frontier via fake `gh`** — all blocked/claimed → the NONE line names the phase and both
  counts; output never contains "no open issues" and names no issue from another phase.
- **TS15 old gh via fake `gh`** — fake exits 1 with `Unknown JSON field: "blockedBy"` on stderr → exit 2
  and output contains `requires gh >= 2.94.0`.
- **TS15b fetch failure** — fake exits 1 with other stderr → exit 2, no "requires gh" text.
- **TS15c missing field** — fake returns issues without `blockedBy` → exit 2 (defensive check).
- **TS16 usage** — `bash "$MODULE" bogus` and `bash "$MODULE" next --bogus` both exit 64; stderr
  contains `next [--frontier]`.
- **TS17 validate unchanged** — `reconcile_counts` on the existing fixture gives the same verdicts
  with milestone JSON that now carries `state`.
- **TS7 extended** — zero file writes after calling `pick_phase` and `filter_frontier`.

Live, read-only (Phase 1 step 3, informational only): `next` names a Phase 4 issue and
`next --frontier` lists it first.

## Observability

```yaml
liveness_signal:
  what: roadmap-reconcile.sh prints a one-line verdict on every run ("roadmap-next: Phase N — ...")
  cadence: on demand (founder runs product-roadmap next)
  alert_target: the founder's terminal (plugin runs on the founder's own machine; observability layer 7)
  configured_in: plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh main()
error_reporting:
  destination: stderr plus a non-zero exit code (2 = data not trustworthy, 64 = usage)
  fail_loud: true — the `2>/dev/null || issues='[]'` swallow is removed; old gh, fetch failure and a
    a missing field all exit 2 with a message naming the cause
failure_modes:
  - mode: gh older than 2.94.0 (no blockedBy field)
    detection: jq field check on the fetched JSON
    alert_route: stderr "requires gh >= 2.94.0", exit 2
  - mode: gh auth or network failure
    detection: non-zero gh exit
    alert_route: stderr, exit 2
  - mode: every issue blocked or claimed
    detection: empty frontier with non-zero held-back counts
    alert_route: stdout names the phase and the counts (not an error; never reads as "finished")
logs:
  where: stdout/stderr of the founder's session; nothing persisted (read-only module)
  retention: session only
discoverability_test:
  command: grep -c -e '^pick_phase()' -e '^filter_frontier()' plugins/soleur/skills/product-roadmap/scripts/roadmap-reconcile.sh
  expected_output: "2"
```

(The live signal needs `gh` credentials and network, which preflight Check 10's sandbox does not have,
and the usage line goes to stderr, which Check 10 does not match; so the probe discovers the two
functions the frontier is built from. No shell-active characters.)

## Architecture Decision (ADR/C4)

Skipped: no architectural decision. The change uses the GitHub edge the skill already uses (`gh`) and
keeps ADR-054's writer contract (sub-commands read-only; the workshop remains the interactive writer;
the cron remains the reviewed-PR writer). A reader of the ADRs and C4 model is not misled after this
ships.

## Infrastructure (IaC), GDPR, Encryption Posture, Guard Contract

Not triggered: no infrastructure, no regulated-data surface, no persistent store or new connection, and
the deliverable contains no guard, gate, lint or CI check (the new tests test behaviour; they are not a
guard over a property of the repository).

## Non-Goals

- Importing wayfinder's map issue, ticket types, claiming workflow or session rules (cut in Research
  Insights).
- Ranking roadmap-row issues ahead of internal-tooling issues in the frontier (CPO suggestion). The
  issue asks for the frontier to compose with `next`'s existing deterministic lowest-number pick;
  changing the ordering is a separate product decision. Recorded in `decision-challenges.md`.
- A `validate` check for out-of-scope links pointing at reopened issues (CPO suggestion). Covered by
  the workshop's 1.6 walk instead, which keeps `validate`'s output contract with brainstorm Phase 0.25
  unchanged.
- Counting no-milestone issues in `validate` (same reason).
- A Phase-5 trigger check in `pick_phase`: the trigger is prose in roadmap.md, not machine-readable.

## Risks and Sharp Edges

- **Open PR #6987 also edits roadmap.md** (weekly CPO count sync). The new sections sit between
  Post-MVP and Pricing, away from the Current State rows it edits; rebase if it merges first.
- **The cron could still edit the new sections** in a free-form "roadmap.md updates" PR. Its rules do
  not reach bullet lists (D3), and every cron edit arrives as a reviewed PR (ADR-054). Accepted.
- **`next` behaviour changes visibly:** it will name a Phase 4 issue instead of #1423. That is the fix,
  and the PR body says so.
- **"Unassigned" filters nothing today** (0 of 118 Phase 4 issues are assigned). Kept because the
  frontier definition needs it the moment a second contributor claims work.
- **`plan/SKILL.md` has 700 bytes of headroom** and the ceiling is read from the merge base; the note
  must stay about 210 bytes. If a sibling PR lands first and eats the headroom, shorten the note, do not
  touch the ceiling.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6.

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering

**Status:** reviewed
**Assessment:** (CTO) Small, single-module change; no ADR. Fold the phase-selection fix in, as a pure
`pick_phase` function. Fail closed on truncation (`totalCount` greater than returned nodes) and on
unknown blocker states; check that `blockedBy` is present so an old `gh` cannot make every issue look
unblocked; filter open milestones, anchor `^Phase [0-9]+[:( ]`, sort numerically; fail loudly at the
limit; an empty frontier prints NONE plus held-back counts. Its required tests are adopted as
TS7-TS17, except the limit-equality exit (cut at plan review).

### Product/UX Gate

**Tier:** none (no UI surface; `roadmap.md` is a document and the output is CLI text). CPO consulted
because the issue names a CPO gate.
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO: approve with three fixes, all adopted — define Post-MVP by milestone membership (D1); name the
unsorted set (open issues with no milestone) so "forgotten" has one rule (D1); use plain wording in
the four-places table and keep the peer test with a plain gloss (D2). Seed no entries; the workshop
raises the two real candidates (D8, Files to Edit item 4). Folding the `next` fix is acceptable as its
own commit with its own acceptance check (Phase 1 step 4, AC5). Headless must stay write-free (D8,
AC8). Two suggestions declined as Non-Goals (frontier ranking; `validate` out-of-scope drift check).

## Acceptance Criteria

- **AC1** — `bash plugins/soleur/test/roadmap-reconcile.test.sh` exits 0 with `0 failed` on its final
  line, and each of TS8-TS17 appears as an `echo "TS…` block in the suite.
- **AC2** — `grep -c '^## Where Work Lives on the Roadmap' plugins/soleur/skills/product-roadmap/SKILL.md`
  prints 1; the section contains the strings `Not Yet Specified`, `Out of Scope`, `--add-blocked-by`,
  `not planned`, `next --frontier`, `state the question precisely`, and `write the issue title today`.
- **AC3** — `grep -c 'Inspired by mattpocock/skills/skills/engineering/wayfinder/SKILL.md' plugins/soleur/skills/product-roadmap/SKILL.md`
  prints 1, and the same grep over `knowledge-base/product/roadmap.md` and
  `plugins/soleur/skills/plan/SKILL.md` prints 0 (D7).
- **AC4** — `plugins/soleur/NOTICE` contains `skills/product-roadmap/SKILL.md (#8292)` and a
  `Bundle 5 (#8292` paragraph.
- **AC5** — TS13 passes: with a fixture whose Phase 4 Current State row has no count cell, `next`
  selects Phase 4 over Phase 5 and names the same `#N` as the first `next --frontier` item line.
- **AC6** — `reconcile_counts` over the pre-change and post-change roadmap.md, against the single
  milestone snapshot captured in Phase 0, produces identical output (Phase 3).
- **AC7** — `knowledge-base/product/roadmap.md` has exactly one `## Not Yet Specified` and one
  `## Out of Scope` heading, both between `### Post-MVP / Later` and `## Pricing`, neither containing a
  line starting with `|`; `last_reviewed` is unchanged.
- **AC8** — the SKILL.md Headless Mode section contains the D8 sentence (it names graduating an entry,
  closing an issue as out of scope, and adding a blocking edge).
- **AC9** — `wc -c < plugins/soleur/skills/plan/SKILL.md` is below 120000 and
  `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` exits 0; the
  plan note contains `Not Yet Specified` and `soleur:product-roadmap`.
- **AC10** — the product-roadmap `description:` line is unchanged (`git diff origin/main -- plugins/soleur/skills/product-roadmap/SKILL.md | grep -c '^[-+]description:'`
  prints 0) and `bun test plugins/soleur/test/components.test.ts` passes.
- **AC11** — the shingle check reports 0 shared 8-word shingles for the roadmap.md intros and the plan
  note, and the PR body states how many sentences the Phase 4 dry run flagged and how each was resolved.
- **AC12** — the PR body says `Closes #8292` and closes nothing else, and carries a `Filed:` line.

## Plan Review (2026-09-22)

Panel: `soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`,
`soleur:engineering:review:code-simplicity-reviewer` (eng), plus `soleur:product:cpo` and
`soleur:engineering:cto` (named panel; product and devex language in the plan). Threshold `none`, so no
5-agent escalation. Standing check (no AC depends on concurrent processes): AC5 and AC6 originally read
live GitHub state; both were rewritten onto fixtures (AC5 → fake-`gh` TS13, AC6 → one milestone
snapshot on both sides).

**Applied (Mechanical):**
- Cut the empty-frontier "name the lowest held-back issue" rendering (DHH + simplicity), which also
  removes the Kieran P0 that no function produced it. NONE plus phase plus counts remains.
- Cut the limit-equality exit, the pass-count floor, TS8b (could not fail independently) and TS10b
  (`MERGED` is not an issue state; the `== "CLOSED"` clause stays).
- Kept the `totalCount > nodes` hold-back as one clause, re-tested as the realistic case (a blocker in
  an unreadable repo: `nodes: []`, `totalCount: 1`).
- Old-`gh` detection moved to stderr matching of `Unknown JSON field` (CTO H1); the field check stays
  as a defensive `all(has(...))` (Kieran P1).
- `main` made testable through a fake `gh` on `PATH` (Kieran P0-2); exit-2 capture form spelled out
  (Kieran P1-3); single jq pass for FIFO inputs (Kieran P1-5); TDD red step guarded with `declare -F`
  (CTO H2); `--frontier` output format fixed with the summary line first (CTO M1); SKILL dispatch
  passes remaining arguments (CTO M2); a ready `bun -e` command for the shingle check (CTO L2).
- SKILL prose cut from about +75 to about +45 lines, each rule stated once; step 3.3 folded into
  Blocking Edges; the headless rule put in the existing Headless Mode section (DHH, simplicity).
- Plan note shortened to about 210 bytes (DHH); NOTICE paragraph kept to the Bundle 1-4 shape.
- The plain-language gloss added to AC2 (CPO 7).

**Kept against a reviewer:** the constrained dry run (DHH asked to cut it; the operator's brief
requires it), and the shingle check (DHH and simplicity asked to cut it; D7's decision not to attribute
roadmap.md and the plan note rests on it, and bundles 2-4 ran the same check).

**Persisted as Taste to `knowledge-base/project/specs/feat-one-shot-8292-roadmap-fog-blocking/decision-challenges.md`
(headless; not applied):** CPO 1-6 (walk the unsorted set in step 1.6; empty-state wording; the
four-places rule stated in roadmap.md itself; Post-MVP wording; "changed your mind?" line; plain
words in `next` output) and the earlier CPO frontier-ranking suggestion; simplicity's suggestion to
split `pick_phase` into its own PR.
