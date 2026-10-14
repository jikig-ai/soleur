# Plan: peer-plugin-audit sub-mode in competitive-analysis skill

**Issue:** #2722 (primary), folds #2728 (Skill Library tier seed)
**Parent audit:** #2718
**Branch:** `feat-claude-skills-audit`
**Worktree:** `.worktrees/feat-claude-skills-audit/`
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-21-claude-skills-audit-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-claude-skills-audit/spec.md`

## Overview

Extend the existing `competitive-analysis` skill with a `peer-plugin-audit <repo-url>` sub-mode that, given a public GitHub repository URL, produces a 4-section markdown report (inventory, gaps, overlap, architectural patterns + recommendations) and seeds it into a new "Skill Library" tier of `knowledge-base/product/competitive-intelligence.md`. Backwards-compatible: existing `competitive-analysis` invocations (with or without `--tiers`) are unaffected.

**Post-review shape** (all three reviewers applied): one reference file (procedure + inline report template), no standalone RED smoke-test script, single-destination output (tier only), license handling reduced to one-line note, no speculative fallbacks. #2728 folded in per user choice; sibling description trimming stays in-PR with exact before/after text shown below.

## Research Insights

From the 2026-04-21 brainstorm and direct worktree inspection:

- **competitive-analysis today** (`plugins/soleur/skills/competitive-analysis/SKILL.md:1-41`): 41 lines; routes via `--tiers` arg; delegates to the `competitive-intelligence` agent; scheduled monthly via `scheduled-competitive-analysis.yml`.
- **No `references/` directory** exists for competitive-analysis today. Precedent: `plugins/soleur/skills/brainstorm/references/*.md` is the sub-procedure pattern.
- **Token budget state** (measured 2026-04-21, verified via `bun test plugins/soleur/test/components.test.ts` passing): exactly **1800/1800** words; zero headroom. Measurement: `desc.split(/\s+/).filter(Boolean).length` per skill, summed across 68 skills.
- **`/soleur:help` mechanism** (`plugins/soleur/commands/help.md`): reads skill descriptions dynamically via Glob on `**/SKILL.md`. Sub-modes are *not* listed explicitly — discoverability comes from mentioning the sub-mode in the parent skill's `description:` field. TR6 is satisfied by description-level mention.
- **CI report tier pattern** (`knowledge-base/product/competitive-intelligence.md`): current section order is Executive Summary → Tier 0 → Tier 3 → New Entrants → Recommendations → Cascade Results. New Skill Library tier placement decision: **between Tier 3 and New Entrants** (keeps tiers clustered; "New Entrants" and below are cross-tier sections).
- **Sampling methodology for large peer repos.** For repos with >50 SKILL.md files, procedure must use stratified sampling: (a) enumerate all SKILL.md paths via `gh api repos/<o>/<r>/git/trees/HEAD?recursive=1 | jq -r '.tree[].path | select(endswith("SKILL.md"))' | head -n 500`, (b) bucket by top-level directory, (c) pick 2-3 files per bucket for depth assessment. Deterministic, avoids random-10-fetch bias. For ≤50 SKILL.md files, fetch all.
- **Skill Compliance Checklist** (`plugins/soleur/AGENTS.md`): new SKILL.md edits must verify (a) `name:` matches directory, (b) `description:` uses third person ("This skill should be used when…"), (c) cumulative descriptions ≤1800 words via `bun test`, (d) individual descriptions ≤1024 chars, (e) references linked as `[file.md](./references/file.md)` (no bare backticks), (f) imperative/infinitive style in body. Phase 4 must cite this checklist before edit.
- **CPO gate** (brainstorm): no port recommendation ships without naming the specific founder outcome it unblocks — encoded in report template (inlined in reference file).
- **CMO framing** (brainstorm): bundle recommendations by ICP-expansion narrative, never individual skill-add posts — encoded as a single "Recommendations" section in the report template (no conditional-on-count logic per simplicity review).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| "Sub-mode listed in `/soleur:help`" (TR6) | `/soleur:help` reads skill `description:` dynamically; no sub-mode list surface today. | Satisfied by mentioning "peer-plugin-audit" in `competitive-analysis` description. |
| Output lands in new "Skill Library" tier of `competitive-intelligence.md` (FR1) | Tier does not exist yet; #2728 tracks creation. | Fold #2728: seed the tier in same PR; first entry is alirezarezvani/claude-skills. |
| "Existing competitive-analysis invocations unaffected" (TR7) | Current SKILL.md routes `--tiers` at Step 1. | Add new mode branch *before* the `--tiers` branch: "if args start with `peer-plugin-audit`, route to reference; else fall through." Order-sensitive — regression-guarded by grep check. |
| Token budget compliance (TR2) | Test at 1800/1800; zero headroom. | Trim `agent-native-audit` (37w→30w) + `growth` (37w→27w) = frees 17w. Expand `competitive-analysis` (23w→~30w) = uses 7w. Net surplus: +10w. Exact before/after shown in Phase 5. |
| MIT attribution (TR3) | N/A | Inline `<!-- Inspired by alirezarezvani/claude-skills (MIT, Copyright (c) 2025 Alireza Rezvani) -->` at top of new reference file. |
| No stdlib-Python-CLI (TR1) | Soleur convention: SKILL.md + bash. | Reference file is markdown-only; no Python. |

## Exhaustive FR/TR Mapping (Kieran gate)

| Requirement | Scope in this PR? | Where addressed |
|---|---|---|
| FR1 (sub-mode) | **YES** | Phases 2–4, 6 |
| FR2 (security scan) | No — issue #2719 | Out of scope |
| FR3 (promotion loop) | No — issue #2720 | Out of scope |
| FR4 (orchestration lanes) | No — issue #2721 | Out of scope |
| FR5 (5 new components) | No — issues #2723–#2727 | Out of scope |
| FR6 (Skill Library tier) | **YES** (folds #2728) | Phase 6 |
| FR7 (content piece) | No — issue #2729 | Out of scope |
| FR8 (RA/QM deferral) | Already filed as #2730 | Done |
| TR1 (no Python CLI) | **YES** | Reference file is markdown |
| TR2 (token budget) | **YES** | Phase 5 (exact trims) |
| TR3 (MIT attribution) | **YES** | Phase 3 (inline comment) |
| TR4 (security FAIL-by-default) | No — issue #2719 | Out of scope |
| TR5 (promotion manual-confirm) | No — issue #2720 | Out of scope |
| TR6 (discoverability) | **YES** | Phase 4 (description mention) |
| TR7 (backwards compat) | **YES** | Phase 4 (branch-before-tiers), Phase 7 (smoke test) |

All 15 requirements (FR1–FR8, TR1–TR7) explicitly classified. No silent drops.

## Architecture

```
plugins/soleur/skills/competitive-analysis/
├── SKILL.md                              # UPDATED: mode routing + description expansion
└── references/                           # NEW directory
    └── peer-plugin-audit.md              # NEW: procedure + inline 4-section report template
```

**SKILL.md routing** (pseudo):

```
Step 1: Detect invocation mode.
  - If args start with `peer-plugin-audit `, extract repo URL and
    read references/peer-plugin-audit.md — follow that procedure. Stop.
  - Else if args contain `--tiers`, use provided tiers (existing).
  - Else AskUserQuestion (existing).
Step 2..4: (unchanged)
```

**Agent reuse.** Reuse `competitive-intelligence` agent via Task spawn with an extended prompt template (the prompt lives in the reference file). No new agent — CPO's "improve existing > add new" applies.

**Layer clarification** (Kieran ambiguity catch): the *skill* invokes `Task competitive-intelligence: "<prompt from reference file>"` directly. The agent does not re-delegate. One Task hop.

## Files to Create

| Path | Purpose | Est. size |
|---|---|---|
| `plugins/soleur/skills/competitive-analysis/references/peer-plugin-audit.md` | Full procedure + inline 4-section report template + CPO gate + CMO framing + MIT attribution comment | ~220-300 lines |

## Files to Edit

| Path | Change |
|---|---|
| `plugins/soleur/skills/competitive-analysis/SKILL.md` | Description expansion (23w→~30w); add Step 1 mode branch for `peer-plugin-audit`; add Sub-Modes section in body. |
| `plugins/soleur/skills/agent-native-audit/SKILL.md` | Trim description 37w → 30w (exact text below). |
| `plugins/soleur/skills/growth/SKILL.md` | Trim description 37w → 27w (exact text below). |
| `knowledge-base/product/competitive-intelligence.md` | Insert new `## Skill Library Tier: Portable Skill Collections` section between Tier 3 and New Entrants; seed with alirezarezvani/claude-skills entry; update frontmatter dates. |

## Implementation Phases

### Phase 1 — Pre-flight (Measurement + Checklist Read)

- **1.1** Re-read `competitive-analysis/SKILL.md`, `agent-native-audit/SKILL.md`, `growth/SKILL.md` — may have shifted since 2026-04-21.
- **1.2** Re-measure total skill description words (one-liner from Research Insights). Confirm 1800/1800 or measure current headroom. Record baseline.
- **1.3** Read `plugins/soleur/AGENTS.md` Skill Compliance Checklist section. Confirm the Phase 4 description expansion will satisfy all checks (third person, ≤1024 chars, references linked).
- **1.4** Read full `knowledge-base/product/competitive-intelligence.md` to confirm section ordering (Tier 0 / Tier 3 / New Entrants / Recommendations / Cascade Results).

### Phase 2 — Verification guards (not TDD)

Per DHH + Simplicity reviewers: a grep-against-markdown check is a regression guard, not a test. Call it "verification" and keep it minimal.

- **2.1** Confirm `bun test plugins/soleur/test/components.test.ts` passes at baseline (GREEN pre-change).
- **2.2** Skip custom test-script creation. The regression risks are (a) token-budget violation — caught by `components.test.ts`, (b) routing-order reversal (new branch ends up after `--tiers`) — caught by a single in-plan acceptance-criterion grep that runs at PR review time, not as a unit test. See Acceptance Criteria.

### Phase 3 — Author `references/peer-plugin-audit.md`

Single file containing:

- **MIT attribution comment** at top: `<!-- Inspired by alirezarezvani/claude-skills methodology (MIT, Copyright (c) 2025 Alireza Rezvani) -->`.
- **Input validation section**: parse URL; reject non-`github.com` hosts; resolve via `gh repo view <owner>/<name> --json url,licenseInfo,description,isFork` (follows 301s); if no LICENSE detected, default recommendations to "inspire only" with a one-line note; if `isFork` is true, note it in the report's Inventory Summary (does not halt).
- **Procedure (5 steps)**:
  1. WebFetch repo README + LICENSE via `https://raw.githubusercontent.com/<o>/<r>/<default-branch>/README.md` + `/LICENSE`. If WebFetch 404s on LICENSE, note absence.
  2. Enumerate all SKILL.md paths via `gh api repos/<o>/<r>/git/trees/HEAD?recursive=1 | jq -r '.tree[].path | select(endswith("SKILL.md"))' | head -n 500`. Count.
  3. **Depth-assessment sampling** (deterministic): if count ≤ 50, fetch all; if > 50, bucket by top-level directory (`awk -F/ '{print $1}' | sort -u`), pick 2-3 SKILL.md per bucket (the alphabetically first 2-3 per bucket — deterministic, reproducible). Fetch each via WebFetch on `raw.githubusercontent.com` URL, piping through `| head -n 500` if any individual fetch is large.
  4. **Enumerate Soleur catalog** at invocation time: `ls plugins/soleur/skills/` + `find plugins/soleur/agents -name "*.md" -type f` + `ls plugins/soleur/commands/`. Pipe each through `| head -n 500`. This is the mapping target.
  5. **Semantic map** — Task spawn to `competitive-intelligence` agent with the inline prompt template (below). Agent produces the report.
- **Soleur catalog overlap examples** (preserve discipline from brainstorm): show 3 worked semantic mappings — their `senior-architect` → Soleur's `architecture-strategist` + `ddd-architect` + `cto`; their `financial-analyst` → Soleur's `revenue-analyst` + `financial-reporter`; their `content-creator` → Soleur's `copywriter` + `content-writer`. These are false-positive guards for the agent.
- **Inline Task prompt template** the skill hands to `competitive-intelligence`. Includes: audited repo metadata, Soleur catalog snapshot, report template instructions, CPO gate ("each port recommendation must name founder outcome unblocked — else converts to inspire-only"), CMO framing ("Recommendations section groups by ICP-expansion narrative").
- **Inline 4-section report template**:
  - Section 1: **Inventory Summary** — counts by category, fork status, license, quality distribution estimate (thin <50 lines / substantive 100-250 / heavy tooling 300+).
  - Section 2: **High-Value Gaps** — table columns: Their skill | Path | Purpose | Why-not-duplicated-in-Soleur | Effort-to-adapt | Founder outcome unblocked (CPO gate).
  - Section 3: **Overlap Table** — Their skill | Closest Soleur equivalent(s) | Which looks deeper | Notes.
  - Section 4: **Architectural Patterns + Recommendations** — patterns table (name | mechanism | Soleur fit); Recommendations section (single, unconditional per simplicity review) with ICP-expansion-bundle framing hint. All `#NNNN` PR/issue references wrapped in backticks per `cq-prose-issue-ref-line-start`.
- **Output routing**: write to the Skill Library tier of `knowledge-base/product/competitive-intelligence.md` only. Single destination (no `research/peer-plugin-audits/` dual-write per DHH + Simplicity).
- **Unbounded-output guards**: explicit `| head -n 500` on `gh api` tree listings (Step 2), `| head -n 500` on each WebFetch-to-stdout in Step 3, `| head -n 500` on each `ls`/`find` in Step 4, Task agent stdout bounded via prompt instruction ("produce report body ≤ 500 lines").
- **Error branches** (1-line notes, not logic trees):
  - WebFetch rate-limit → fall back to `gh api repos/<o>/<r>/contents/<path>` for individual file fetches.
  - `gh repo view` returns 401 → abort with message pointing to `gh auth status`.
  - Same-session retry returns cached WebFetch → note "results may be cached this session" in procedure header.

### Phase 4 — Update `competitive-analysis/SKILL.md`

- **4.1** Read `plugins/soleur/AGENTS.md` Skill Compliance Checklist again just before edit (per Phase 1.3).
- **4.2** Rewrite `description:`. **Proposed text (exact):**
  > `"This skill should be used when running competitive intelligence scans against tracked competitors, or auditing a peer skill-library repo via peer-plugin-audit. Produces structured knowledge-base reports."`

  **Word count:** 29 words. (Kieran caught the prior draft claimed 28; actual count: 29.)
- **4.3** Add Step 1 branch at top of existing Step 1, *before* the `--tiers` detection:

  ```markdown
  ### 1. Detect Invocation Mode

  **peer-plugin-audit sub-mode (checked first):**
  If arguments start with `peer-plugin-audit `:
  - Extract the repo URL (second arg).
  - Read [peer-plugin-audit.md](./references/peer-plugin-audit.md) and follow that procedure.
  - Stop (do not fall through to tier selection).

  **competitive intelligence mode (existing):**
  If arguments are present (non-empty): ...(existing content unchanged)...
  ```
- **4.4** Add "Sub-Modes" section in SKILL.md body below the existing steps:

  ```markdown
  ## Sub-Modes

  | Mode | Invocation | Purpose |
  |---|---|---|
  | Tier scan (default) | `skill: soleur:competitive-analysis [--tiers 0,3]` | Monthly competitive intel report |
  | Peer-plugin audit | `skill: soleur:competitive-analysis peer-plugin-audit <repo-url>` | Audit a peer skill library/plugin, seed Skill Library tier |
  ```
- **4.5** Reference link: `[peer-plugin-audit.md](./references/peer-plugin-audit.md)` (proper markdown link per Skill Compliance Checklist — no bare backticks).

### Phase 5 — Token budget surgery

Exact before/after shown in-plan (Kieran gate).

**5.1 Baseline measure.** Re-run the one-liner. Expect 1800/1800.

**5.2 Trim `agent-native-audit/SKILL.md`.**

Current (37w):
> `"This skill should be used when conducting a scored agent-native architecture review. It launches 8 parallel sub-agents to audit action parity, tools as primitives, context injection, shared workspace, CRUD completeness, UI integration, capability discovery, and prompt-native features."`

Proposed (30w):
> `"This skill should be used when conducting a scored agent-native architecture review. It launches 8 parallel sub-agents to audit action parity, context injection, CRUD completeness, capability discovery, and prompt-native features."`

**Words saved: 7.** Core routing signal (scored review + 8 sub-agents + key audit dimensions) preserved. Dropped dimensions (tools-as-primitives, shared-workspace, UI-integration) are implicit in the 8-sub-agent claim; reviewer routing won't suffer.

**5.3 Trim `growth/SKILL.md`.**

Current (37w):
> `"This skill should be used when performing content strategy analysis, keyword research, content auditing for search intent alignment, content gap analysis, content planning, or AI agent consumability auditing. It provides sub-commands for auditing, planning, and applying fixes."`

Proposed (27w):
> `"This skill should be used when performing content strategy analysis, keyword research, content auditing, content gap analysis, or AI agent consumability auditing. Sub-commands: auditing, planning, applying fixes."`

**Words saved: 10.** Dropped `"for search intent alignment"` (implied by content auditing), `"content planning"` (covered by sub-command `planning`), and compressed sub-commands clause. Routing signal preserved.

**5.4 Re-measure after both trims.** Expect: 1783/1800. Headroom: 17w. Safe to expand competitive-analysis.

**5.5 Apply competitive-analysis expansion from Phase 4.2 (+6w: 23→29).** Re-measure: expect 1789/1800. Final headroom: 11w.

**5.6 Run `bun test plugins/soleur/test/components.test.ts`** — expect GREEN.

### Phase 6 — Seed Skill Library tier (folds #2728)

- **6.1** Read `competitive-intelligence.md` in full (done in Phase 1.4). Confirm insertion point.
- **6.2** Insert new tier between `## Tier 3` and `## New Entrants`:

  ```markdown
  ## Skill Library Tier: Portable Skill Collections

  A complementary category alongside workflow plugins. Skill libraries package reusable SKILL.md instructions (often with CLI tooling) that convert across multiple AI coding tools. They compete on inventory breadth and portability, not on workflow orchestration or compounding knowledge. Convergence risk to Soleur is typically low because the product shapes differ — but the category is worth tracking because a skill library with strong curation signals demand for the skill primitives Soleur orchestrates.

  ### Overlap Matrix

  | Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk |
  |---|---|---|---|---|
  | **[alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills)** | Soleur plugin (workflow orchestration vs. portable skill library — different product shape) | Low — structurally different (library vs. workflow lifecycle) | 235+ skills across 9 domains; 305 stdlib-Python CLI tools; converts to 12 AI coding tools (Claude Code, Cursor, Aider, Windsurf, etc.); MIT licensed; v2.0.0 (Mar 2026); 12.2k stars; 1.6k forks. No workflow orchestration, no compounding KB, no /one-shot pipeline, no domain leaders. | **Low** — complementary product shape. Watch for: new workflow or orchestration additions; any move toward stateful KB; cross-tool converter gaining traction that erodes Claude Code exclusivity. |

  ### Tier Analysis

  **Material changes since last review (initial entry, 2026-04-21):**

  First entry to this tier. Category added to the CI report following the 2026-04-21 comparative audit (see PR `#2734`, parent audit `#2718`). The `peer-plugin-audit` sub-mode of `competitive-analysis` (`#2722`) is the ongoing intake mechanism for new entries to this tier.

  **Soleur's advantages in this tier:**

  - Workflow lifecycle (brainstorm → plan → implement → review → compound → ship).
  - Compounding knowledge base across 8 business domains.
  - Domain leaders with cross-delegation.
  - Opinionated curation vs. inventory breadth.

  **Watch items:**

  - New portable skill libraries >10k stars (indicates category demand).
  - Existing libraries adding orchestration, KB, or workflow primitives.
  ```
- **6.3** Confirm all `#NNNN` references use backticks (per `cq-prose-issue-ref-line-start`). Visually verify: "PR `#2734`", "parent audit `#2718`", etc. ✓
- **6.4** Update frontmatter: `last_updated: 2026-04-21`, `last_reviewed: 2026-04-21`, `tiers_scanned: [0, 3, "skill-library"]`.
- **6.5** PR body update: add `Closes #2728` alongside `Closes #2722`.

### Phase 7 — Smoke test end-to-end

- **7.1** Invoke `skill: soleur:competitive-analysis peer-plugin-audit https://github.com/alirezarezvani/claude-skills` in worktree.
- **7.2** Verify report is generated with all 4 sections populated and written to the Skill Library tier of `competitive-intelligence.md`.
- **7.3** Backwards-compat: invoke `skill: soleur:competitive-analysis --tiers 0,3` — existing flow completes unchanged.
- **7.4** If smoke test fails (any section missing, tier not updated, backwards-compat broken): stop and fix. No "investigate-loop" placeholder — pass/fail only.

### Phase 8 — Validation & Ship prep

- **8.1** `bun test plugins/soleur/test/components.test.ts` → GREEN.
- **8.2** `npx markdownlint-cli2 --fix` on specific changed files only (per `cq-markdownlint-fix-target-specific-paths`): `plugins/soleur/skills/competitive-analysis/SKILL.md`, `plugins/soleur/skills/competitive-analysis/references/peer-plugin-audit.md`, `plugins/soleur/skills/agent-native-audit/SKILL.md`, `plugins/soleur/skills/growth/SKILL.md`, `knowledge-base/product/competitive-intelligence.md`.
- **8.3** `skill: soleur:review` (multi-agent plan review) before ready. Fix P0/P1 inline.
- **8.4** PR #2734 body: `Closes #2722`, `Closes #2728`; add `## Changelog` section; `gh pr edit 2734 --add-label semver:minor`.

## Acceptance Criteria

### Pre-merge (PR #2734)

- [ ] `plugins/soleur/skills/competitive-analysis/references/peer-plugin-audit.md` exists, contains: MIT attribution, input validation, 5-step procedure, 3 worked overlap examples (senior-architect / financial-analyst / content-creator), inline Task prompt template, inline 4-section report template with CPO gate ("Founder outcome unblocked" column) and CMO framing hint, unbounded-output guards on all gh/ls/find commands, error branches (1-liner notes) for WebFetch rate-limit / 401 / cached-results.
- [ ] `plugins/soleur/skills/competitive-analysis/SKILL.md` routes `peer-plugin-audit <url>` at Step 1 *before* the `--tiers` branch. Grep check: `grep -n 'peer-plugin-audit\|--tiers' SKILL.md` shows `peer-plugin-audit` on earlier line than `--tiers`.
- [ ] `competitive-analysis` `description:` contains literal `peer-plugin-audit` and stays ≤1024 chars.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes (total ≤1800 words).
- [ ] `agent-native-audit` description is 30 words (verified by one-liner); `growth` description is 27 words.
- [ ] `knowledge-base/product/competitive-intelligence.md` has `## Skill Library Tier: Portable Skill Collections` section between Tier 3 and New Entrants; contains alirezarezvani/claude-skills Overlap Matrix entry; frontmatter dates = 2026-04-21; all `#NNNN` refs wrapped in backticks.
- [ ] `npx markdownlint-cli2 --fix` (targeted paths) passes.
- [ ] PR #2734 body: `Closes #2722`, `Closes #2728`.
- [ ] PR has `semver:minor` label and `## Changelog` section.
- [ ] `skill: soleur:review` completes; no unresolved P0/P1 findings.
- [ ] End-to-end smoke test (Phase 7) passes: all 4 report sections generated, backwards-compat `--tiers` flow unchanged.

### Post-merge (operator)

- [ ] `/soleur:help` output (next invocation) surfaces peer-plugin-audit via the new `competitive-analysis` description.
- [ ] Within 2 weeks, invoke `peer-plugin-audit` against a second repo (e.g., `travisvn/awesome-claude-skills`) to validate sub-mode works beyond seeding corpus.
- [ ] Next monthly `scheduled-competitive-analysis.yml` run preserves the Skill Library tier (does not overwrite the seeded entry).

## Risks

1. **Token-budget regression during trimming.** Mitigation: exact before/after shown in Phase 5; routing signal preserved; `bun test` gates.
2. **Catalog-mapping false positives** (falsely claiming overlap where none). Mitigation: reference file's 3 worked examples; agent prompt includes discipline.
3. **Catalog-mapping false negatives** (falsely claiming "missing" where overlap exists). Mitigation: same as (2); reviewer sweep in Phase 7.
4. **Rate-limiting on deep repo scans.** Mitigation: 1-line `gh api` fallback note in reference file. No clone-based recovery (simplicity cut).
5. **Unbounded subagent output filling tmpfs** per `hr-never-run-commands-with-unbounded-output`. Mitigation: explicit `| head -n 500` on every gh/ls/find/WebFetch in the reference file (enumerated in Phase 3).

## Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| New standalone `peer-plugin-audit` skill | Clean separation | Surface-area inflation (CMO); description-budget pressure (CTO); forks CI tier output target | Rejected — brainstorm already picked sub-mode |
| Extend `functional-discovery` / `agent-finder` | Reuses agents | Blurs single-purpose /plan contracts | Rejected — scope mismatch |
| New `peer-plugin-auditor` agent | Cleanest subagent contract | Agent description budget; sub-mode suffices | Rejected — reuse `competitive-intelligence` with extended prompt |
| Inline everything in SKILL.md (no references/) | Single-file locality | SKILL.md grows 3-4×; violates sub-mode convention | Rejected — reference pattern established |
| Ship #2728 as 2-line pre-PR, then sub-mode PR | Halves review surface; kills ordering hazard | Two PRs to coordinate | Rejected by user — keep folded |
| Defer description trimming to separate chore PR | Decouples token-budget risk | Two PRs to coordinate | Rejected by user — keep in PR |
| Two reference files (procedure + template) | Explicit separation | Premature split for zero-invocation feature | Rejected — inline template per DHH + Simplicity |
| Dual-destination output (tier + `research/...`) | History | Stale-copy hazard, no consumer | Rejected per DHH + Simplicity |

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped for overlap against planned file paths (`plugins/soleur/skills/competitive-analysis/**`, `knowledge-base/product/competitive-intelligence.md`, `plugins/soleur/skills/agent-native-audit/SKILL.md`, `plugins/soleur/skills/growth/SKILL.md`). **None.**

Issue #2728 is not labeled `code-review` but is a logical overlap. Disposition: **Fold in.** Phase 6 seeds the tier.

## Domain Review

**Domains relevant:** Engineering, Marketing, Product (carried forward from 2026-04-21 brainstorm `## Domain Assessments`)

### Engineering

**Status:** reviewed (carried forward)
**Assessment:** Three meta-patterns identified as highest leverage; peer-plugin-audit sub-mode productizes this session's methodology. Token budget at zero headroom — plan includes surgical trim-then-expand with exact text. Reuse `competitive-intelligence` agent, do not spawn new one.

### Marketing

**Status:** reviewed (carried forward)
**Assessment:** Sub-mode feeds the new Skill Library CI tier CMO requested. Tier-seeding folded into same PR. No content-opportunity trigger at sub-mode level.

### Product

**Status:** reviewed (carried forward)
**Assessment:** CPO's top-priority bucket (c) "improve existing" — this plan fits exactly. CPO-gate-as-code: every port recommendation names a founder outcome, encoded in report template.

### Product/UX Gate

**Tier:** none
**Decision:** skipped
**Rationale:** No new user-facing pages, no UI, no flow changes. Mechanical escalation check (`components/**/*.tsx`, `app/**/page.tsx`): NONE matches.

### Brainstorm-recommended specialists

None beyond those invoked for the parent audit session.

### Skipped specialists

None.

## Test Scenarios

1. **Happy-path routing** — `skill: soleur:competitive-analysis peer-plugin-audit https://github.com/alirezarezvani/claude-skills`. Expect: 4-section report, tier updated.
2. **Backwards-compat, no args** — `skill: soleur:competitive-analysis`. Expect: interactive tier prompt (existing).
3. **Backwards-compat, `--tiers` flag** — `skill: soleur:competitive-analysis --tiers 0,3`. Expect: monthly-scan flow unchanged.
4. **Invalid URL (non-github)** — `skill: soleur:competitive-analysis peer-plugin-audit https://not-github.com/foo`. Expect: validation error; no report generation attempted.
5. **Missing URL** — `skill: soleur:competitive-analysis peer-plugin-audit`. Expect: error or AskUserQuestion for URL.
6. **No-LICENSE repo** — (Kieran edge case). Invoke against a repo without LICENSE. Expect: report generates; recommendations default to "inspire only" with one-line note; Inventory Summary flags license absent.
7. **No-skills-folder repo** — (Kieran edge case). Invoke against a repo without `**/SKILL.md`. Expect: Step 2 enumeration returns 0; reference procedure classifies as "non-skill-library repo" and produces a short report explaining "category mismatch; no audit produced"; no tier entry written.
8. **Large repo (>50 SKILL.md)** — (Kieran edge case). Invoke against a repo with 200 SKILL.md files. Expect: stratified sampling (2-3 per top-level directory) kicks in; depth assessment note says "sampled 15 of 200"; not non-deterministic.
9. **Skill Library tier present** — post-Phase-6 grep `competitive-intelligence.md` for `## Skill Library Tier`. Expect: present.
10. **Token budget** — `bun test plugins/soleur/test/components.test.ts`. Expect: GREEN, total ≤1800.
11. **Routing-order regression guard** — grep `competitive-analysis/SKILL.md` such that `peer-plugin-audit` mention precedes `--tiers` mention. Expect: line number of `peer-plugin-audit` < line number of `--tiers`.

## Resume Prompt

```
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-04-21-feat-peer-plugin-audit-sub-mode-plan.md
Branch: feat-claude-skills-audit. Worktree: .worktrees/feat-claude-skills-audit/. Issue: #2722 (+ folds #2728). PR: #2734 (draft). Parent: #2718. Plan reviewed and revised per DHH + Kieran + Simplicity reviewers, implementation next.
```
