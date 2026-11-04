---
title: "feat: agent-readable surface over the egress audit summary (deferred from #9545)"
date: 2026-11-04
slug: agent-readable-egress-audit-surface
branch: feat-one-shot-11258-agent-readable-egress-audit-surface
issue: 11258
type: feat
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat: agent-readable surface over the egress audit summary (deferred from #9545)

## Enhancement Summary

**Deepened on:** 2026-11-04. **Method:** the deepen-plan mechanical gates (4.6 user-brand impact, 4.7 observability, 4.8 PAT
shapes, 4.11 guard contract via `scripts/lint-guard-contract.py`, 4.12 scope check) were run against this file, every cited
issue, path and rule id was re-verified live, and the plan-review panel (three engineering seats) plus two follow-up CTO consults
were folded in earlier. A full agent fan-out was not run: the plan changes one test and one ADR under a binding scope ruling,
and the per-section research would only repeat the two CTO consults and the CLO pass already recorded.

### Key improvements over the first draft
1. The ADR-parity arm was dropped: it would have forced the test into the always-run repo-wide project and a second file edit,
   and proved only same-diff consistency.
2. Arm (e) now uses hard-coded root anchors and a 90% count floor; a dropped scan root can no longer erase its own check.
3. The loader chokepoint is one regex over quoted import specifiers (verified: exactly the two pages), `.mjs` is scanned, and
   the lint command is the allowlist form the repo actually runs.

### New considerations discovered
- A test that reads `knowledge-base/` is not a unit-project test (repo-wide containment rule); the pin therefore reads only inside
  the app.
- `#9545` is now closed, so the amendment describes #11258 as a standalone open item under epic #9601; the plan cites #9545 only
  as the origin of the deferral.
- The window-closure lint fails repo-wide without its allowlist argument (18 grandfathered helpers); the AC uses the allowlist form.

## Overview

**Scope narrowing (binding CTO ruling, 2026-11-04).** Issue #11258 asks for an agent-readable surface over the workspace
egress audit summary. The CTO agent ruled that its deferral is still in force, so this PR does **not** build that surface.
It delivers ruling **B** only: (1) an amendment to ADR-288 that replaces the open-ended wording of accepted residual 5 with a
precise, falsifiable statement of today's state, the threat model, the constraints any future agent surface must meet and
the re-evaluation triggers restated exactly; and (2) one default-suite test that pins the current absence, so a later change
fails loudly instead of silently. There is **no** agent tool, **no** new RPC, **no** new grant, **no** migration, **no** route
and **no** MCP or platform tool in this PR. #11258 stays open (`Ref #11258` / `Ref #9601` only, no close keyword) until a
trigger fires.

The ruling is recorded as a `technical` row in `knowledge-base/project/specs/feat-one-shot-11258-agent-readable-egress-audit-surface/decision-challenges.md`
(with two follow-up rows: the CTO's test-design refinements and the CLO's wording review).

Why the deferral holds, measured on 2026-11-04:

- #3722 (promote read-only MCP tools to the Concierge router) is still open, and the egress audit collection flag stays off
  and operator-held, so neither re-evaluation criterion has fired.
- Nothing agent-reachable calls either member-read function today. In non-test source under
  `apps/web-platform/{server,lib,app,components}` (973 files) the two names occur in exactly three files: the page loader
  (the only caller), a type comment in the summary helper, and a comment in the DSAR allowlist.
- The gap is one tool away, not two: user-JWT tool clients (`getFreshTenantClient`) already exist in the conversations,
  email-triage, inbox, routines and workspace-settings tools, so nothing but the absence of someone writing the tool stands
  between an agent and a member-only function. That is why a pin is worth adding on top of prose.
- A real surface (ruling C) would give a prompt-injectable agent a read of its own egress record with no consumer and no data
  (collection is off for external organisations).

## Research Insights

**Premise validation (Phase 0.6).** Held: #11258 OPEN (p3, milestone Post-MVP / Later, labels type/feature and
domain/engineering); epic #9601 OPEN; #3722 OPEN with no closing PR; migrations 177 and 183, `server/egress-audit-read.ts`,
`lib/egress-audit/summary.ts` and the ADR-288 amendments of 2026-10-26 and 2026-11-03 exist on `origin/main`. Collision
pre-check: the only open change naming #11258 is this branch's own draft PR; two foreign `test-all.sh` processes run in other
worktrees (not blocking: this plan runs targeted tests only). Mechanism check against the ADR corpus: ADR-288's own accepted
residual 5 already records the gap as an "agent-readable surface parity gap" and defers it; no ADR rejects an absence pin.
Stale-in-issue claim found and reconciled below: "the cc-router Concierge exposes no platform tools today".

**Property List (Phase 0.6b).**

- P1. A reader of the public ADR can tell, from one dated statement, exactly what is and is not true today about agent access
  to the egress audit summary, and what was measured versus assumed.
- P2. Adding an agent tool, MCP server entry or tier-map key that can reach either member-read function or the rollup table
  fails a default-suite test before it merges.
- P3. A future change that legitimately builds the surface meets a failure message that points at the ADR record and its
  design constraints, and edits the pin's expected sets in the same diff (review is the independent anchor).
- P4. The re-evaluation triggers are falsifiable events, not "when the Concierge has tools" (which is already partly true).
- P5. No statement ahead of a measured control is made in the public repo.

**Cut List.** (mechanism, property, what already covers it)

- New agent/MCP tool over the summary (ruling C) cut: buys no property in the list that the pin does not; the data is absent for
  external orgs.
- New RPC, new grant or a limiter for member-callable aggregation RPCs cut: no surface to protect yet (ADR-288 residual 3 and
  the enablement blockers already carry the limiter).
- A runtime assertion over `readCcMcpAllowlist` with the egress names cut (CTO follow-up): it would pin a Phase-1 stub that
  #3722 legitimately changes, so the test would fail for an unrelated reason. The tier-map and registered-names assertions
  stay.
- ADR-parity arm in the test cut (plan review plus CTO re-ruling): it proves only same-diff consistency and would move the test
  into the always-run `repo-wide` project; the CODEOWNERS default plus the failure message are the independent anchor.
- Import-specifier resolver (alias, relative, index) cut in favour of one regex over quoted specifiers ending in the loader name.
- A second guard over the SQL side cut: `test/supabase-migrations/183-egress-audit-window-summary.test.ts` already pins the
  member-readable readers of the rollup table to migrations 177 and 183 (database side); this PR pins the application side.
- Comment on or edit of the #11258 body: the body contains the held enablement reference; only a short new comment (no such
  reference) is allowed, at ship time.

**File anchors (verified on this branch).**

- `apps/web-platform/server/egress-audit-read.ts` is the only caller (`supabase.rpc(fn, args)` at the `call` helper; names at
  the page call and the card hint call). Imported only by `app/(dashboard)/dashboard/settings/scope-grants/page.tsx`
  (`loadEgressCardState`) and `.../scope-grants/egress-audit/page.tsx` (`loadEgressAudit`). A bare substring grep for
  `egress-audit-read` also hits `server/observability.ts` (a feature-name string, not an import), so the importer check must
  resolve import specifiers, not grep the substring.
- Agent-surface population measured: every `server/**/*-tool(s).ts` file (17) plus every file containing
  `createSdkMcpServer`, `mcp__soleur_platform__`, `TOOL_TIER_MAP`, `CC_MCP_ALLOWLIST`, `mcpServers:` or `canUseTool`:
  47 files in total; zero match `/egress[-_]?audit/i`. The loose form with an optional space also matches zero today, but the
  CTO ruled the space out (prose in a comment is not reachability).
- `apps/web-platform/server/tool-tiers.ts` exports `TOOL_TIER_MAP`; `apps/web-platform/server/cc-dispatcher.ts` exports
  `CC_REGISTERED_PLATFORM_TOOL_NAMES` (narrate, summarize; the C4 tool is appended per dispatch behind a flag) and
  `readCcMcpAllowlist` (throws on a denylisted or approval-required short name, otherwise returns `{}` in Phase 1).
  `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts` already imports both from the default suite, so the import is safe.
- Test project: `apps/web-platform/vitest.config.ts` project `unit` includes `test/**/*.test.ts`. Sibling pins to imitate:
  `test/supabase-migrations/183-egress-audit-window-summary.test.ts` (path resolution via `__dirname`, reader-set pin, anchored
  positive controls) and `test/approval/tools-census.test.ts` (non-vacuity rows).
- Legal posture: `knowledge-base/legal/audits/2026-10-15-dpia-screening-addendum-egress-audit-rollup.md` section 12.6 states that
  a second member read path, or any widening of the reader set, is a fresh t6 and t7 trigger. An agent surface is such a path.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-11-03-the-comment-stripper-i-wrote-to-close-a-guard-gap-opened-two-more.md`: the
  text-lint class. Two-pass regex stripping is itself a bypass. This test scans for names and import specifiers, not for SQL
  comments, so it does not strip comments at all (a comment mention of an RPC name in an agent file is exactly what should
  fail), and it runs the new matchers against the unmutated tree before any mutant. Also: never edit a migration once CI may have
  applied it to dev (no migration is touched); run `bash scripts/markdown-lint.sh --repo-sweep` before the first push of
  markdown; the DSAR allowlist file is off limits (any edit demands four legal documents).
- `knowledge-base/project/learnings/2026-09-30-an-absence-pin-over-hcl-must-compare-the-whole-shape-not-the-kinds-i-was-guarding.md`:
  an absence pin written against the kinds the author was thinking of misses every other axis. Hence the population is derived
  structurally (three arms), the check is set equality on both the name set and the importer set, and the Guard Contract below
  lists the axes the matrix edits.
- The window-closure lint (`scripts/lint-window-closure-assertion.py`) examines helper identifiers ending in `Window`, `Region`
  or `Section`. The test therefore names its helpers `agentSurface`, `scanRoots` and similar, never `*Window/*Region/*Section`.

## Research Reconciliation: Spec vs. Codebase

| Claim (issue, brief or ADR) | Reality (measured 2026-11-04) | Plan response |
|---|---|---|
| Issue: "no agent, MCP or platform tool exposes it" | Holds: the two names are not referenced by any file that builds or registers an agent tool. | State it as a dated, scoped, pinned fact, not a standing guarantee. |
| Issue: "The cc-router Concierge exposes no platform tools today (#3722)" | Imprecise. The router always registers the narrate and summarize tools and, behind a flag, the C4 editing tool; `readCcMcpAllowlist` returns `{}` for every input that does not throw. The leader-surface runner registers platform tools from a dozen `*-tools` builders, several of which use user-JWT clients. | The amendment states the precise version. Trigger (2) is keyed to "read-only platform tools promoted to the Concierge router (#3722)", and trigger (1) is the falsifiable event the test enforces. |
| Issue and ADR residual 5: "the RPC" (singular) | Two member-read functions exist: 177 (card hint, fixed 30 days) and 183 (page, 24h/7d/30d). | The amendment and the test cover both names. |
| Brief: both functions "REVOKEd from anon/service_role/PUBLIC and GRANTed to authenticated only" | True in migration source (`REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role`, then `GRANT EXECUTE ... TO authenticated`). Live grants were not re-measured (no production access in this item). | The amendment says "per migrations 177 and 183; live grants were not re-measured" (CLO rewrite). |
| CTO first draft trigger: "or any agent tool with a user-JWT Supabase client is added" | Already true on day one (`getFreshTenantClient` in five tool files), so that trigger would be satisfied at once. | CTO follow-up accepted the three-trigger version in which trigger (1) is "a change adds a tool, server entry or allowlist outcome able to reach either function or the table". |
| Brief: the enablement reference appears in ADR-288 context lines | Yes, in residual 1, the status paragraph and the 2026-11-03 amendment heading. | Edits touch only residual 5 (in place) and one appended section; AC5 greps the diff additions so no such reference is added. |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "THE FIRST TASK OF THE PLAN PHASE is a binding CTO ruling on scope: spawn `soleur:engineering:cto`" [brief] | Overview; decision-challenges.md rows 1-2; Phase 0 | mapped |
| 2 | "record `Ruled by CTO agent, 2026-11-04: <decision> - <rationale>` as a row of the `\| Item \| Class \| Ruling \|` table" [brief] | decision-challenges.md (created in planning) | mapped |
| 3 | "If the CTO rules the deferral still in force, the plan covers deliverable A or B only and says so plainly in its Overview" [brief] | Overview "Scope narrowing" paragraph | mapped |
| 4 | "(A) a design and threat-model record only (an ADR-288 amendment plus the plan), with NO agent-exposed tool, NO new RPC and NO new grant, NO MCP or platform tool, and the re-evaluation triggers restated precisely" [brief] | Phase 2, Appendix A, Files to Edit entry 1 | mapped |
| 5 | "(B) the same plus a default-suite test that pins the current absence (no MCP/platform tool or agent allowlist entry can reach either egress-audit RPC)" [brief] | Phase 1, Guard Contract, Files to Create entry 1 | mapped |
| 6 | "(C) an actual agent-readable surface" [brief] | not built | descoped - justification: CTO ruling B (neither trigger fired; no consumer; a prompt-injectable agent would read its own egress record) |
| 7 | "An agent-readable surface over the workspace egress audit summary" [issue #11258] | the amendment's constraints plus the pin; the surface itself is not built | descoped - justification: same CTO ruling; the issue stays open until a trigger fires |
| 8 | "A CLO prepare-and-review pass over any wording is allowed; legal sign-off at flag-on stays with the operator." [brief] | Phase 2 wording, Domain Review (CLO), decision-challenges.md row 3 | mapped |
| 9 | "run `bash scripts/markdown-lint.sh --repo-sweep` before any push of markdown" [brief] | Phase 3 | mapped |
| 10 | "PR text uses only `Ref #11258` / `Ref #9601`, no close keyword" [brief] | Phase 4, AC8 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| ADR-288 amendment (Files to Edit 1) | "an ADR-288 amendment plus the plan" | asked (ask 4) |
| Residual 5 marked superseded in place (same file) | "the re-evaluation triggers restated precisely" | inferred - justification: the old residual 5 text would otherwise keep standing beside the new statement and the two would disagree (CLO review) |
| Absence-pin test (Files to Create 1) | "a default-suite test that pins the current absence" | asked (ask 5) |
| decision-challenges.md (created in planning) | "record `Ruled by CTO agent, 2026-11-04: <decision> - <rationale>`" | asked (ask 2) |
| tasks.md (Files to Create 2) | the plan skill's Save Tasks step (workflow contract) | inferred - justification: the work phase reads it; the pipeline contract requires it |
| Comment on #11258 at ship (Phase 4) | "the re-evaluation triggers restated precisely" | inferred - justification: the issue body still carries the old trigger wording; a comment (not a body edit, because the body holds the held reference) is the narrowest correction |

### Split Assessment

- Subsystems touched: 2 - `apps/web-platform` (one test), `knowledge-base` (ADR, plan, spec)
- Planned files: 5 (1 test, 1 ADR edit, plan, tasks.md, decision-challenges.md) | Estimated changed lines: about 330
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing at runtime (no runtime path changes). The failure shapes are a red CI check on an unrelated pull request (a false-positive pin) or, worse, a green pin that sees nothing, so a later agent tool over a workspace's egress record merges unnoticed.
- **If this leaks, the user's workflow data is exposed via:** no data path is added or changed. The exposure the pin guards is a future agent tool reading a workspace's recorded outbound-host aggregate through the member's own JWT; the amendment itself publishes only reasoning already public in the ADR's residuals.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because this PR ships no runtime path, data or grant; not `none` because the wording and the guard concern a surface the ADR rates single-user incident, and a false public statement or a vacuous pin would be a credibility defect that repeats across amendments.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-288 (`knowledge-base/engineering/architecture/decisions/ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md`),
no new ordinal: append `## Amendment 2026-11-04 (#11258): the agent-readable surface stays deferred, and its absence is pinned` and
mark residual 5 superseded in place. Decision in one line: no agent-exposed surface now, the absence is pinned by a default-suite
test, the re-evaluation triggers are three falsifiable events. The full text is Appendix A and is a work-phase deliverable
(this planning phase may only edit plans and specs). Use the `soleur:architecture` skill conventions; the ADR status stays
`adopting`.

### C4 views

No change. Completeness mandate satisfied by reading `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
(1273 lines in total) and enumerating: (a) external human actors: workspace member (already modelled; reads the audit page),
no new actor; (b) external systems/vendors: none added (Vector, Better Stack and Supabase are already modelled; the model edge
`webapp -> supabase` already describes the member egress-audit read path, naming both functions and "no HTTP route"); (c)
containers/data stores: the rollup table is already covered by that edge; (d) actor-to-surface access relationships: the
change adds none (it records an absence; an absence has no edge). The derived-cardinality gate is confirmed by running
`bash plugins/soleur/test/c4-count-parity.test.sh` (see AC9), because that gate moves on counts the actor rubric does not reach.

### Sequencing

Nothing waits on a later slice. The status stays `adopting` for the reasons already in the ADR (owner notice and the enablement
steps), which this item does not touch.

## Files to Edit

1. `knowledge-base/engineering/architecture/decisions/ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md`:
   append the amendment (Appendix A) and add a superseded marker to residual 5 (item 5 of "Accepted residuals (read path)").
   No other line changes. Never add the enablement reference to any added line.

## Files to Create

1. `apps/web-platform/test/egress-audit-agent-surface-absence.test.ts` (new; default `unit` project).
2. `knowledge-base/project/specs/feat-one-shot-11258-agent-readable-egress-audit-surface/tasks.md` (derived at plan end).
3. (Already created in planning) `knowledge-base/project/specs/feat-one-shot-11258-agent-readable-egress-audit-surface/decision-challenges.md`.

**Must not change:** `apps/web-platform/server/dsar-export-allowlist.ts` (the test only reads it), any migration, `docs/legal`,
`plugins/soleur/docs`, `scripts`, `.github`, any feature-flag or environment file, `ci/main-broken`.

## Open Code-Review Overlap

None. Queried the open `code-review` issues (96) for the ADR-288 path, the new test path and the plan path: no matches.

## Implementation Phases

### Phase 0 - Re-verify at work start (no code)

- `git fetch origin && git merge origin/main` clean; `gh issue view 3722 --json state` still OPEN and #11258 still OPEN; if either
  changed, STOP and re-rule via the CTO (a fired trigger changes the scope).
- On a clean tree, cross-check the test's file walk against an independent enumerator: the number of files the `node:fs` walk
  scans (`.ts`, `.tsx`, `.mjs`) equals `git ls-files server lib app components | grep -E '\.(ts|tsx|mjs)$' | grep -v -E
  '\.test\.(ts|tsx|mjs)$|/__tests__/' | wc -l` (973 for `.ts`/`.tsx` on 2026-11-04; `.mjs` adds a few). Record the figure; the
  test's floor is at most 90% of it.
- Re-run the measurements in Research Insights against the merged tree: the three-file name set, the two importers, and the
  agent-surface population (floor values come from this run, rounded down).

### Phase 1 - The pin test, written first (`cq-write-failing-tests-before`)

Write `apps/web-platform/test/egress-audit-agent-surface-absence.test.ts`. It reads source with `node:fs` only inside
`apps/web-platform` and resolves paths from `__dirname` (the `183` test's pattern). It must NOT read `knowledge-base/` or any
path outside the app: a test that escapes the app is forced into the always-run `repo-wide` project and must be listed in
`test/repo-wide-suites.ts` (`test/repo-wide-containment.test.ts` enforces it); this test stays in the diff-gated `unit`
project, which is the right gate for a pin over app source. It imports `TOOL_TIER_MAP` from `@/server/tool-tiers` and
`CC_REGISTERED_PLATFORM_TOOL_NAMES` from `@/server/cc-dispatcher`. Shape (names are load-bearing; none ends in `Window`,
`Region` or `Section`):

```ts
// Header: the property, the residual (see "What the pin does not see" in ADR-288's 2026-11-04 amendment, one-line pointer).
const SCAN_ROOTS = ["server", "lib", "app", "components"];          // under apps/web-platform; .ts, .tsx, .mjs
const RPC_NAME = /get_egress_audit_(window_)?summary/;
const EGRESS_AUDIT = /egress[-_]?audit/i;                            // camelCase loadEgressAudit and the table name included
const LOADER_IMPORT = /(?:from|import\s*\(|require\s*\()\s*["'][^"']*egress-audit-read["']/;
const EXPECTED_NAME_FILES = [
  "lib/egress-audit/summary.ts", "server/dsar-export-allowlist.ts", "server/egress-audit-read.ts",
];
const EXPECTED_LOADER_IMPORTERS = [
  "app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page.tsx",
  "app/(dashboard)/dashboard/settings/scope-grants/page.tsx",
];
const ROOT_ANCHORS = {            // hard-coded, independent of SCAN_ROOTS
  server: "server/egress-audit-read.ts", lib: "lib/egress-audit/summary.ts",
  app: "app/(dashboard)/dashboard/settings/scope-grants/page.tsx", components: "components/settings/egress-audit-view.tsx",
};
```

Arms (each a separate `it`; each asserts full set equality or an empty offender list, never "first mismatch"):

- (a) Name set: non-test source files containing `RPC_NAME` equal `EXPECTED_NAME_FILES` exactly (sorted `toEqual`).
- (b) Loader chokepoint: files matching `LOADER_IMPORT` (one regex over quoted import specifiers ending in `egress-audit-read`;
  verified on the real tree to yield exactly the two pages and to exclude `server/observability.ts`, which only mentions the name
  as a string) equal `EXPECTED_LOADER_IMPORTERS`. The loader file itself does not match.
- (c) Agent surface: population = every `server/**/*-tool(s).ts` file plus every file containing one of `createSdkMcpServer`,
  `mcp__soleur_platform__`, `TOOL_TIER_MAP`, `CC_MCP_ALLOWLIST`, `mcpServers:`, `canUseTool`. Offenders = population files
  matching `EGRESS_AUDIT`. Must be `[]`. This also catches a direct read of the rollup table through any client.
- (d) Runtime anchor: no key of `TOOL_TIER_MAP` and no entry of `CC_REGISTERED_PLATFORM_TOOL_NAMES` matches `EGRESS_AUDIT`
  (covers a computed key that arm (c) cannot see as text). No assertion over `readCcMcpAllowlist` (a Phase-1 stub that #3722
  legitimately changes).
- (e) Anti-vacuity: every `ROOT_ANCHORS` file exists and is in the scanned set (a dropped root fails here, independent of
  `SCAN_ROOTS`); the scanned-file count is at least 90% of the figure measured at work start (a floor with margin, not an exact
  count); the population contains at least one file from each of the filename arm and the marker arm; every `EXPECTED_*` member
  exists on disk; the matchers are exercised on synthetic strings: must-match `get_egress_audit_window_summary`,
  `loadEgressAudit(`, `egress_audit_rollup`, `from("workspace_egress_audit_rollup")`, `import("@/server/egress-audit-read")`,
  `from "../server/egress-audit-read"`; must-not-match `web_egress`, `egress gateway`, `egress-forwarder`,
  `WEB_EGRESS_PROMPT_ADDENDUM`.

Failure messages name the offending files (all of them) and say: "ADR-288, amendment 2026-11-04: building this surface needs
legal and security review and an edit of this test's expected sets in the same PR; see the amendment's constraints."

Expected state when written: arms (a)-(e) are all GREEN on the unmutated tree (measure this first, and record the run before
any mutant). The RED evidence is the mutation battery of Phase 3, not an artificially failing arm.

### Phase 2 - The ADR-288 amendment (CLO wording pass already folded into Appendix A)

Append Appendix A to the ADR and add the superseded marker to residual 5. Scrub check (AC5). Run the banned-wording grep (AC11).
The amendment lists the expected consumer paths and the test file name as plain prose (informational; no test reads the ADR).

### Phase 3 - Mutation battery and lints (targeted, not the full `--affected` battery)

- Run the Guard Contract matrix against the committed tree, one mutant at a time, restoring after each (a scratch copy of the
  tree or `git checkout --` of the mutated file; never `git stash`). Summarise row, result and the failing arm in the PR body.
- `cd apps/web-platform && npx vitest run test/egress-audit-agent-surface-absence.test.ts` (and `cc-mcp-tier-allowlist` to prove
  the import does not disturb it).
- `python3 scripts/lint-window-closure-assertion.py --allowlist scripts/lint-window-closure-assertion.allowlist.txt` (the form
  `scripts/test-all.sh` runs; repo-wide, no path argument; without the allowlist it reports 18 grandfathered helpers),
  `python3 scripts/lint-guard-contract.py` on this plan,
  `bash scripts/markdown-lint.sh --repo-sweep` before the first push of markdown, `bash plugins/soleur/test/c4-count-parity.test.sh`.
- CI is the ship gate for the rest; the local `--affected` battery takes 30+ minutes under load and adds nothing for a
  one-file test plus a markdown edit.

### Phase 4 - Ship

- Commit trailers: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01GFjtgCLNJLuLXoUHkQcjhw`. PR body: `Ref #11258`, `Ref #9601`, the rendered
  decision-challenges table, the mutation-battery record, the line `Net issue flow: 0 (no issue filed)`, and it ends with
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. No `Closes`, `Fixes` or `Resolves`. No Standing Delegation.
- After merge: one short comment on #11258 restating the three triggers and linking the amendment. It carries no reference to
  the held enablement issue and the #11258 body is not edited. #11258 stays open.
- No post-merge verification beyond CI: nothing deploys, no flag or environment is touched.

## Guard Contract

### Guard 1 - Egress-audit agent-surface absence pin

**Property.** No file that builds or registers an agent tool, MCP server entry, tier-map key or router-registered tool name in
`apps/web-platform` source references either member-read egress-audit function, the loader module or the rollup table, and only
the two Scope Grants pages import the loader.

**Assembly.** The property quantifies over three chokepoints, all named, none a list of current members: (i) the RPC name literal
across every non-test `.ts/.tsx/.mjs` under `server`, `lib`, `app`, `components` (set equality with `EXPECTED_NAME_FILES`); (ii) the
loader module's importers, matched as quoted import specifiers ending in `egress-audit-read` (set equality with
`EXPECTED_LOADER_IMPORTERS`); (iii) the agent-surface population, derived structurally by three arms - `*-tool(s).ts` filename,
marker content (`createSdkMcpServer`, `mcp__soleur_platform__`, `TOOL_TIER_MAP`, `CC_MCP_ALLOWLIST`, `mcpServers:`,
`canUseTool`), and the two runtime registries (`TOOL_TIER_MAP` keys, `CC_REGISTERED_PLATFORM_TOOL_NAMES`). Not seen, stated in the
ADR: runtime-assembled names, plugin-supplied MCP servers, an environment-supplied `CC_MCP_ALLOWLIST` value, database-side
changes, deployed configuration.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `server/zz-probe-tools.ts` containing `supabase.rpc("get_egress_audit_window_summary", {})` (also covers the RPC name in a comment only: the test does not strip comments) | RED (arms a and c) |
| 2 | Drop `components` from `SCAN_ROOTS` and add an offending file there (the guard's own dispatch: a scan that loses a root, or scans zero files, must not read green) | RED (arm e: the hard-coded root anchor is absent from the scanned set) |
| 3 | Add two offending files after the three legitimate name files (a second member after a compliant first) | RED, and the message lists both files (full-set comparison, not first mismatch) |
| 4 | Add a file that imports the loader and is not one of the two pages, spelled `"@/server/egress-audit-read"`, `"../server/egress-audit-read"` and `await import("@/server/egress-audit-read")` in three files, with no RPC name | RED (arm b only, all three spellings) |
| 5 | Add `from("workspace_egress_audit_rollup")` to `server/agent-runner.ts` (table read, no function name) | RED (arm c) |
| 6 | Add a tier-map key as a literal `"mcp__soleur_platform__egress_audit_summary": "auto-approve"`; then, separately, as a computed key `["mcp__soleur_platform__egress"+"_audit"]` | RED (literal: arms c and d; computed: arm d only) |
| 7 | Add `server/zz-tools.ts` with no marker content that reads the table (the filename arm alone must place it in the population) | RED (arm c via the filename arm) |
| 8 | Add `server/zz-runner.ts`, not named `*-tools`, that contains `createSdkMcpServer` and an egress-audit string (the marker arm alone) | RED (arm c via the marker arm) |
| 9 | Add a `.mjs` file under `server/` that contains the RPC name | RED (arm a: the extension set includes `.mjs`) |

**Harness rows.** H1 (edit the suite, not the guard): remove `server/egress-audit-read.ts` from `EXPECTED_NAME_FILES` - RED
(arm a set equality; arm e's "every expected member exists" does not fire for a removal and is not claimed). H2 (must-PASS input
that is not the canonical tree): a synthetic population in which an agent-surface file contains `web_egress`, `egress gateway`,
`egress-forwarder` and `WEB_EGRESS_PROMPT_ADDENDUM` - the matcher stays quiet, and a name-file that holds the RPC name only in a
comment (the DSAR allowlist today) still passes arm a. H3 (positive controls): each must-match synthetic string in arm e is
matched, so a matcher that rejects nothing or everything fails the suite. No reorder or lifetime row: the property is static.

**Anchor.** The expected sets and the ADR record sit in the same repository, so one diff can edit both: this guard proves a
change is visible, not that it is blessed. What sits outside the commit is review: `.github/CODEOWNERS` assigns every path to the
owner by default, and the failure message states that a legitimate change needs legal and security review under the amendment's
constraints. Enforcement of CODEOWNERS review is a branch-protection setting held by the operator and is not asserted here.

## Acceptance Criteria

- [x] AC1. ADR-288 contains exactly one `## Amendment 2026-11-04 (#11258)` heading, and under it the statements of Appendix A
  (state, what the pin does not see, threat model, constraints, triggers, expected consumers, alternatives); status line still
  `adopting`.
- [x] AC2. Residual 5 carries a "Superseded in part by the 2026-11-04 amendment" marker; its original text is unchanged.
- [x] AC3. `apps/web-platform/test/egress-audit-agent-surface-absence.test.ts` exists, reads nothing outside `apps/web-platform`
  (so it stays in the `unit` project and `test/repo-wide-containment.test.ts` stays green without a `repo-wide-suites.ts` edit),
  and passes: `cd apps/web-platform && npx vitest run test/egress-audit-agent-surface-absence.test.ts test/repo-wide-containment.test.ts` exits 0.
- [x] AC4. The nine mutation rows and three harness rows of Guard 1 were each run against the committed tree and went RED/PASS as
  stated; a summary is in the PR body. The unmutated run precedes the first mutant.
- [x] AC5. No added line carries the held enablement reference:
  `git diff origin/main...HEAD | grep '^+' | grep -E '112[0-9]{2}' | grep -v '11258'` prints nothing (inspect any hit); the same
  holds for the plan, tasks.md, decision-challenges.md, the PR body and every commit message.
- [x] AC6. `git diff --name-only origin/main...HEAD` lists only the ADR, the new test, and files under
  `knowledge-base/project/{plans,specs}/`; in particular not `apps/web-platform/server/dsar-export-allowlist.ts`, any migration,
  `docs/legal`, `plugins/soleur/docs`, `scripts`, `.github`. Files the pipeline itself writes (a regenerated
  `knowledge-base/INDEX.md`, `specs/<branch>/session-state.md`, a committed run record) are expected and listed in the PR body.
- [x] AC7. `bash scripts/markdown-lint.sh --repo-sweep`, `python3 scripts/lint-guard-contract.py <this plan>` and
  `python3 scripts/lint-window-closure-assertion.py --allowlist scripts/lint-window-closure-assertion.allowlist.txt` exit 0.
- [ ] AC8. PR text has `Ref #11258` and `Ref #9601` and no `Closes|Fixes|Resolves`; ends with the generation line; commit trailers as
  specified; no issue filed (net issue flow 0).
- [x] AC9. `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0 (no C4 file changed).
- [ ] AC10. #11258 is still open after merge, and a comment restating the three triggers was posted (no held reference).
- [x] AC11. Banned wording absent from added ADR lines:
  `git diff origin/main...HEAD -- <ADR> | grep '^+' | grep -i -E 'tamper|cannot be evaded|agents cannot|no agent can|secure|guarantee|prevents'`
  prints nothing; the phrase "not a forensic or exfiltration-detection control" is present.
- [x] AC12. `decision-challenges.md` carries the three rows (CTO scope ruling, CTO test-design refinements, CLO wording review),
  each in the exact `Ruled by CTO agent|CLO agent, 2026-11-04: <decision> - <rationale>` shape. (Verified at work time: four rows, the fourth
  being the CTO's later drop of the ADR-parity arm; all in the exact shape, and the technical-ruling gate passes.)

## Test Scenarios

- Given the unmutated tree, when the new test runs, then arms (a)-(e) are green.
- Given a new `*-tools.ts` file that calls either function, then the suite fails on arms (a) and (c) naming that file.
- Given a new module that imports the loader and is not one of the two pages, then arm (b) fails even with no RPC name present.
- Given an agent file that reads the rollup table by name, then arm (c) fails.
- Given an edit that adds an egress-audit key to the tier map, then arm (d) fails.
- Given an edit that empties the scan roots, then the suite fails (anti-vacuity), it never reports a green over zero files.
- Given a legitimate future change, then the editor sees a failure message that points at the ADR amendment and must edit the
  expected sets and the record in the same PR.

## Domain Review

**Domains relevant:** engineering, legal

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled (2026-11-04) the deferral is still in force and the narrowest honest deliverable is B; a
follow-up consult corrected the first draft of the trigger wording (it would have been satisfied on day one), cut the
`readCcMcpAllowlist` runtime assertion, tightened the matcher (no space alternative), and kept the tier-map arm. A third consult (after plan review) dropped the ADR-parity arm (it forced the test out of the `unit` project and proved only same-diff consistency), simplified the loader matcher to one regex, added `.mjs` to the scan, replaced the exact count floor by a 90% floor plus hard-coded root anchors, and cut the matrix to nine rows. All three are
are recorded in decision-challenges.md.

### Legal

**Status:** reviewed
**Assessment:** CLO agent reviewed the draft amendment wording (prepare-and-review only). Rewrites folded into Appendix A: "none of
the three triggers", "per migrations ... live grants were not re-measured", "on 2026-11-04 the scan found", the cross-member
visibility sentence reframed as "every current member already sees it; what changes is the absence of per-read intent", the
decoy sentence reframed as probing "what the log retains (residual 2)", and the DPIA addendum 12.6 re-screen named in the
constraints. No change to `docs/legal`, the compliance-posture file, the DPIA or the Art. 30 register is required, because there is
no processing change, no new recipient and no new surface; the DPIA tripwires fire only when a second read path or a wider reader
set is built. Publishing the threat-model paragraph is acceptable (residual 2 already publishes the decoy-host evasion). Legal
sign-off at flag-on stays with the operator.

Product/UX Gate: not relevant (no UI-surface path in the Files lists; the mechanical override did not fire). GDPR gate
(Phase 2.7): not invoked - no canonical-regex surface is touched and none of the four expansion triggers holds (no new
processing, no `single-user incident` threshold, no cron reading learnings or specs, no new distribution surface); the CLO
answered the register question above.

## Observability

The only executable artifact is a test, so the "signal" is its CI verdict. No runtime code is added.

```yaml
liveness_signal:
  what: the egress-audit absence pin runs in the vitest unit project on every pull request that touches apps/web-platform
  cadence: per pull request
  alert_target: the required CI check on the pull request (red check blocks the merge)
  configured_in: apps/web-platform/vitest.config.ts (project unit includes test/**/*.test.ts)
error_reporting:
  destination: vitest failure output in the CI job log, naming every offending file and pointing at the ADR-288 amendment
  fail_loud: true
failure_modes:
  - mode: an agent tool, MCP entry or tier-map key reaches either egress-audit function or the table
    detection: arms (a)-(d) of the pin fail
    alert_route: red CI check on the introducing pull request
  - mode: the scan silently covers nothing (a dropped root or a changed layout)
    detection: arm (e) hard-coded root anchors and count floor fail
    alert_route: red CI check
  - mode: the agent surface moves to a place the population arms do not reach
    detection: not detected by this pin (stated residual in the ADR amendment); held by review
    alert_route: reviewer on the pull request
logs:
  where: CI job log of the unit project
  retention: the CI provider's default job-log retention
discoverability_test:
  command: grep -c 'include: \["test/\*\*/\*.test.ts", "lib/\*\*/\*.test.ts"\]' apps/web-platform/vitest.config.ts
  expected_output: "1"
```

## Sharp Edges

- Observability: plan Phase 2.9 does not require a section (no code-class file under `apps/*/server/`, `apps/*/src/`,
  `apps/*/infra/` or `plugins/*/scripts/`, no new infrastructure, no autonomous task), but deepen-plan Phase 4.7 treats a
  `apps/web-platform/test/` file as non-docs, so a compact `## Observability` section for the test itself is carried above.
- The spec directory had no `spec.md` (headless one-shot, no brainstorm), so `lane:` defaulted to `cross-domain` (fail-closed).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will
  fail `deepen-plan` Phase 4.6. This one declares `aggregate pattern` with a stated reason.
- The held enablement reference must not appear in any added line, including this plan, the tasks file, the PR body, commit
  messages and comments. When quoting ADR-288, replace any such number with "the enablement issue" (the scrub is AC5).
- The test must not strip comments: a comment that mentions an RPC name in an agent file is a finding, not noise (the
  learning on two-pass strippers applies to the opposite design).
- A bare substring grep for the loader name over-counts (`server/observability.ts`); arm (b) resolves import specifiers.
- Do not rename helpers to end in `Window`, `Region` or `Section` (the window-closure lint then demands a declaration).
- The test deliberately does not read the ADR: reading `knowledge-base/` would move it into the always-run `repo-wide` project and
  require a `repo-wide-suites.ts` edit. The record is held by review and by the CLO-reviewed text in Appendix A.
- An absence grep over added ADR lines (AC11) is only valid because the amendment text legitimately contains none of the banned
  words; if a review round adds a prohibition sentence that quotes one, flip the AC to assert the guardrail's presence.

## Appendix A - ADR-288 amendment text (work-phase deliverable; wording already reviewed by the CLO)

Append after the last amendment of the ADR, without the enablement reference anywhere in the added text:

```markdown
## Amendment 2026-11-04 (#11258): the agent-readable surface stays deferred, and its absence is pinned

**Decision.** No agent-exposed surface over the egress audit summary is built now, and no migration, grant, route or tool
changes. None of the three re-evaluation triggers below has occurred. This amendment supersedes accepted residual 5 (marked in
place); the other residuals are unchanged.

- **State on 2026-11-04.** Per migrations 177 and 183, `EXECUTE` on the two member-read functions is granted to `authenticated` and
  revoked from `anon` and `service_role`; live grants were not re-measured for this amendment. On this date a scan of non-test
  source under `apps/web-platform/{server,lib,app,components}` found the two function names in three files only:
  `server/egress-audit-read.ts` (the only caller), `lib/egress-audit/summary.ts` (a type comment) and
  `server/dsar-export-allowlist.ts` (a comment). It found `server/egress-audit-read.ts` imported only by the two server-rendered
  Scope Grants pages, and found no reference to either function, the loader or the rollup table in any file that builds or
  registers an agent tool, in any tier-map key, or in the router's registered platform tool names. The router registers the
  narrate and summarize tools and, behind a flag, the C4 editing tool; `readCcMcpAllowlist` throws on a denylisted or
  approval-required short name and otherwise returns `{}` in its current phase (#3722). The leader-surface runner registers
  platform tools built from the `server/*-tools.ts` files; none of them reads egress audit data.
- **What the pin does not see.** `apps/web-platform/test/egress-audit-agent-surface-absence.test.ts` is a text scan of repository
  source plus two runtime assertions over the tier map and the router's registered tool names. It does not see a function name
  assembled at runtime, a plugin-supplied MCP server, an environment-supplied `CC_MCP_ALLOWLIST` value, a database-side change or
  a deployed configuration. It is designed to fail first when a surface is added; it is not a proof that none exists.
- **Threat model for a future surface.** An agent acting for a member would hold that member's authority, which both functions
  scope to the whole workspace rather than to the calling session. Every current member already sees that aggregate in the view;
  what changes is that an agent would exercise the read without the member's per-read intent, and could read what other members'
  agent sessions contacted. A compromised agent could also use repeated reads to probe what the log retains (residual 2). The log
  remains a transparency log for members, not a forensic or exfiltration-detection control, and this amendment does not change that.
- **Constraints any future agent surface must meet.** Member user-JWT client only, never service-role (the functions are revoked
  from it). Calls only the existing functions: no generic SQL tool, no call-any-RPC tool, no new grant. Read-only and
  aggregate-only: no `source_host`, no per-request rows, windows of 24h, 7d or 30d only. Rate-limited per member and per session;
  the agent's own reads are audited and shown to the member. Tiered `gated` with an approval classification in the same PR.
  Output treated as untrusted. Legal and security review before it merges, including the DPIA addendum re-screen
  (`knowledge-base/legal/audits/2026-10-15-dpia-screening-addendum-egress-audit-rollup.md`, section 12.6: a second member read
  path is a fresh t6 and t7 trigger). The absence test and the expected paths below are updated in the same PR.
- **Re-evaluation triggers (first to occur).** (1) A change adds an agent tool, MCP server entry or allowlist outcome able to reach
  either function or the rollup table; the absence test is designed to fail first and points here. (2) Read-only platform tools
  are promoted to the Concierge router (#3722). (3) The first external-organization enablement of egress audit collection, which
  stays operator-held. Until one occurs, #11258 stays open and no agent-readable surface is built.
- **Expected consumers (informational; the test header lists the same sets).** `server/egress-audit-read.ts`,
  `lib/egress-audit/summary.ts`, `server/dsar-export-allowlist.ts`, and the loader's only importers,
  `app/(dashboard)/dashboard/settings/scope-grants/page.tsx` and
  `app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page.tsx`.
- **Alternatives considered.** Building the surface now: rejected, no consumer exists and collection is off for external
  organisations. A prose-only record with no pin: rejected, member user-JWT clients already exist in the platform tool files.

The status stays **Adopting**.
```

Marker for residual 5 (added as a new line directly under its last line, same indentation as the item text):

```markdown
   *Superseded in part by the 2026-11-04 amendment below: the follow-up is #11258, which stays open, and the absence is pinned by a default-suite test.*
```

## Addendum — 2026-11-04 (review round 1, #11258)

The review panel found the scan window narrower than the property the pin names. The as-built test supersedes the arm layout
sketched above (the sketch is kept as the planning record):

- The scan now covers every top-level directory of `apps/web-platform` except an explicit exclusion list (dependencies, build
  output, tests, browser tests, static assets, docs, SQL), over all JS/TS extensions, and refuses symlinks. This replaces
  `SCAN_ROOTS` and `ROOT_ANCHORS` (anti-vacuity arm (e1) and the existence arm (e4) were removed as redundant with the expected sets
  and the file-count floor, now about 95% of the 1049 measured, with per-directory minimums).
- New arms: (f) the rollup table name occurs only in the three expected files; (g) no production file imports a test-named module.
  The loader-import matcher accepts extension, subpath, backtick and bare-import spellings. The agent-surface population adds the
  Agent SDK import specifier and drops the `server/` restriction on the filename arm.
- Anti-vacuity: named arm members instead of non-empty checks; the composed predicate is driven with synthetic must-trip rows; a
  last test fails if any arm was skipped or emptied. Expected sets carry a reason per entry, and a failure reports added and
  removed entries separately with stop-and-escalate wording.
- "Default-suite" in the text above means the diff-gated `unit` project; the ADR amendment says so and lists what the pin does not
  see. The ADR amendment also gained the AP-004 exception record, the DPIA-derived constraints and the unresolved cross-member scope.

Round 2 (fix-range review of the commit above) added: build-output and report directories to the exclusion list; per-directory
minimum file counts; import matchers that accept block comments before the specifier, `require.resolve(` and `new URL(`, and a
whitespace-run linearity check; arm (g) now also refuses production imports of modules in the excluded source directories (one
reasoned exception, the test-runner config); camelCase and `tools/` agent file names; a separate message for scan-integrity
failures; and ADR wording changes from the legal re-review (cross-session scope, persisted output, record of agent reads,
disclosure minimisation), the service-role gate's real scope, and operator sign-off ownership.
