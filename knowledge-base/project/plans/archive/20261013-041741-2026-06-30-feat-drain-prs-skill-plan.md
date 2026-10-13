---
title: "feat: drain-prs skill — triage and drain open remote GitHub PRs"
date: 2026-06-30
type: feat
lane: cross-domain
brand_survival_threshold: none
status: ready-for-work
semver: minor
references:
  - plugins/soleur/skills/drain-labeled-backlog/SKILL.md
  - "PR #5808 (learnings + ADR-033 §Registration checklist — in merge queue)"
---

# feat: `drain-prs` skill — triage and drain open remote GitHub PRs

## Overview

Add a new **operator-facing** Soleur skill `drain-prs` at `plugins/soleur/skills/drain-prs/SKILL.md` — the PR-counterpart to the existing issue-only `drain-labeled-backlog` skill. It enumerates all open **remote** GitHub PRs, triages them into mergeable tiers, confirms scope with the operator via a decision gate **before** merging anything, then per in-scope PR ensures CI is green via fix-recipes and squash-merges (the merge queue serializes when active; an update-branch → Monitor-wait → merge fallback covers the queue-inactive case).

This is **internal maintainer dev-tooling, operator-facing only**. The design is distilled from the 2026-06-30 open-PR drain session where 11 PRs were merged across tiers, and was validated by the operator. This plan does **not** re-scope the design — it encodes it and wires the new component per `plugins/soleur/AGENTS.md`.

Per `hr-new-skills`, CMO is omitted (no marketing/brand surface — the skill never reaches the user-facing product surface). CPO assessment was run (see Domain Review) and cleared the work at **ADVISORY (non-blocking)**.

## Research Reconciliation — Spec vs. Codebase

| Claim (from task / design) | Codebase reality (verified) | Plan response |
|---|---|---|
| Mirror `drain-labeled-backlog/SKILL.md` structure | Exists; ships `SKILL.md` + `scripts/group-by-area.sh` + `workflows/` + a test at `plugins/soleur/test/drain-labeled-backlog.test.sh`. Frontmatter `name` + third-person `description`; sections: When-to-use, `<decision_gate>`, Prerequisites, Arguments (incl. `--dry-run`), Workflow, Pipeline detection, Sharp edges, Test. | Mirror that exact shape. Ship a `scripts/triage-prs.sh` helper + a `plugins/soleur/test/drain-prs.test.sh` test, paralleling `group-by-area.sh` + its test. |
| Add a routing row to the `/soleur:go` **skill table** | `/soleur:go` is a **command** (`plugins/soleur/commands/go.md`), NOT a skill. The routing table is at `go.md:62`; the existing `drain` row (`go.md:65`) routes to `soleur:drain-labeled-backlog`. | Add a **distinct** `drain-prs` row to `commands/go.md` (intent "drain open PRs / merge all green PRs / clear the PR queue"), separate from the issue-backlog `drain` row. |
| Reference learnings `2026-06-30-update-branch-drifts-lockfiles-and-npm11-pin.md` and `2026-06-30-stale-bot-cron-pr-hallucinated-api-and-registration-sweep.md`; ADR-033 §Registration checklist | **None present on main yet.** All three live in **PR #5808** (`docs(learnings): PR-drain lockfile + stale-cron-PR hazards + ADR-033 cron registration checklist`) — state OPEN, mergeStateStatus CLEAN (in merge queue). | Reference all three **by path** as the task instructs; they will be on main before this PR merges. Do not block on their absence; add a Sharp Edge noting the dependency. |
| Bump README skills count 92 → 93 | `plugins/soleur/README.md:45` = `| Skills | 92 |`. Counts are **auto-derived** by `scripts/sync-readme-counts.sh` (`find skills -name SKILL.md | wc -l`); CI runs it with `--check`. The per-skill table is **curated** (`drain-labeled-backlog` is not individually listed). | Run `bash scripts/sync-readme-counts.sh` to rewrite the count to 93 (do not hand-edit). Optionally add a curated `drain-prs` row next to `merge-pr` (`README.md:270`) for discoverability. |
| `docs/_data` wiring for the eleventy build | No top-level `docs/_data`; the data dir is `plugins/soleur/docs/_data/` and `plugin.js` does **not** enumerate skills — skills are auto-discovered. | No manual `_data` list edit expected. Validate via the eleventy docs build (`soleur:deploy-docs`) at work time. |
| Merge queue active on main | Branch rulesets show `CI Required: active`, `CLA Required: active`, `Force Push Prevention: active` (server-side). The companion plan `2026-06-30-feat-adopt-github-merge-queue-for-main-plan.md` exists. | Encode **both** paths: queue-active (`gh pr merge --squash` enqueues; queue handles update-branch + serialization) and queue-inactive fallback (update-branch → Monitor-wait → merge). Robust to queue state. |
| Skill-description budget | `SKILL_DESCRIPTION_WORD_BUDGET = 2292` at `plugins/soleur/test/components.test.ts:15`; current cumulative total = **2292/2292 (zero headroom)**. | New description (~30–34 words) **requires** bumping the constant by exactly its word count, with an appended bump-note — the established convention (see existing bump log on that line). |
| `worktree-manager.sh cleanup-merged` | Exists at `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged` (used by `work/SKILL.md:43`). | Reference verbatim in the Cleanup step. |
| `rule-metrics.json` generated-file conflict recipe | Exists at `knowledge-base/project/rule-metrics.json`; owning script `scripts/rule-metrics-aggregate.sh`. | Cite as the canonical generated-file-regenerate example in the fix-recipes section. |

## User-Brand Impact

**If this lands broken, the user experiences:** a maintainer-only tooling failure — at worst a PR is mis-triaged into the wrong tier, surfacing a confusing tier table at the decision gate. The operator confirms scope before any merge, so a triage bug surfaces as a visible wrong-tier listing, not a silent bad merge.

**If this leaks, the user's data is exposed via:** N/A. The skill reads only PR metadata via the operator's own `gh` auth and merges via GitHub's API; it introduces no persistence, no user data, and no new credential surface.

**Brand-survival threshold:** `none`, reason: the skill is a convenience orchestrator layered over existing, independently-enforced protections — a mandatory operator decision gate before any merge, GitHub branch protection (`CI Required` is server-side, so the skill cannot squash-merge a red PR past required checks), the merge queue's serialization, and `/soleur:review` delegation for feature PRs. It adds no new bypass of any existing gate. No Files-to-Edit path matches the preflight sensitive-path regex (no schema/migration/auth/API-route/`.sql`).

## Open Code-Review Overlap

None. Queried open `code-review` issues for bodies referencing `skills/drain-prs`, `commands/go.md`, `components.test.ts`, `sync-readme-counts`, and `drain-labeled-backlog` — zero matches.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

1. Confirm `gh` authenticated, `jq` on PATH, CWD is a git worktree (not bare root) — mirror `drain-labeled-backlog` §Prerequisites step 1.
2. Confirm PR #5808 is merged to main (or note it as a merge-order dependency). The two learning files + ADR-033 §Registration checklist must be on main before THIS PR merges so the SKILL.md path references resolve. Glob-verify both learning paths and the ADR section at ship time.
3. Re-measure `SKILL_DESCRIPTION_WORD_BUDGET` headroom: `bun test plugins/soleur/test/components.test.ts`. Confirm baseline still 2292/2292 (or current value) so the budget bump in Phase 3 is sized correctly.

### Phase 1 — `plugins/soleur/skills/drain-prs/SKILL.md`

Mirror `drain-labeled-backlog/SKILL.md` exactly. Sections:

- **Frontmatter:** `name: drain-prs`; third-person `description` (~30–34 words, "This skill should be used when draining open remote GitHub PRs… PR-counterpart to drain-labeled-backlog."). Keep ≤ 1024 chars, no `<example>` block.
- **When to use:** open remote PR backlog has accumulated; operator wants to triage + drain mergeable PRs in one pass. Disambiguate from `merge-pr` (single-PR) and `drain-labeled-backlog` (issues, not PRs).
- **`<decision_gate>` block (load-bearing — runs BEFORE any merge):** confirm tier scope with the operator via AskUserQuestion. Per CPO refinements: (a) the gate offers **per-PR opt-out within a tier**, not just per-tier accept/reject; (b) one-line copy makes explicit that **confirming = code lands on main** (merges, not a preview); (c) include an **API-budget note** (fixing/reviewing PRs may delegate to `/soleur:review`, which spends Anthropic credit against the session key — mirror the sibling's BSL-1.1 runtime-cost framing, paren-safe phrasing per the CI-sentinel sharp edge). Respects `wg-zero-agents-until-user-confirms` (merging is outward-facing).
- **Prerequisites:** `gh` auth, `jq`, git worktree.
- **Arguments + optional flags:** `--tiers <list>` (restrict to named tiers), `--dry-run` (print the full tier table with zero merges — parity with the sibling; more valuable here because the skill merges), optionally `--pr <N,…>` (restrict to explicit PRs). Document `$ARGUMENTS` passthrough.
- **Workflow:**
  1. **Enumerate:** `gh pr list --state open --json number,title,headRefName,isDraft,mergeable,reviewDecision,labels,author,createdAt,statusCheckRollup` (delegate to the helper — Phase 2).
  2. **Triage into tiers:** ready-green (`mergeable` + CI green) / needs-lockfile-fix (deps PRs failing on `bun.lock` or lockfile-sync) / needs-conflict-resolution (`CONFLICTING`) / needs-review (bot-fix/`review-required` + feature PRs) / drafts (skip — author-owned WIP) / broken (conflicting + many failing checks).
  3. **Decision gate** (above).
  4. **Per in-scope PR:** ensure green via fix-recipes → `gh pr merge --squash`. If the merge queue is active, the queue handles update-branch + serialization automatically; otherwise fall back to update-branch → wait-for-CI (use the **Monitor** tool for CI waits — NEVER a backgrounded poll loop, per `hr-monitor-not-run-in-background-for-polling`) → merge.
  5. **Review delegation:** feature PRs → `/soleur:review`; single-file bot-fixes → inline diff review.
  6. **Cleanup:** `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged` after merges.
  7. **Report drain delta:** before/after open-PR count + per-tier outcome.
- **Fix-recipes (reference section, link the two #5808 learnings by path):**
  - (a) **Lockfile drift on deps PRs** — `cd apps/web-platform && bun install && bun install --frozen-lockfile` for `bun.lock`; `npx --yes npm@11 install --package-lock-only` for `package-lock.json` (the lockfile-sync gate pins npm@11).
  - (b) **Generated-file conflicts** (e.g. `knowledge-base/project/rule-metrics.json`) — regenerate from current main via the owning script (`scripts/rule-metrics-aggregate.sh`); do NOT hand-merge conflict markers.
  - (c) **Stale bot PR (esp. crons)** — rebase to re-validate; check for hallucinated substrate API (`tsc`) + missing registration locations per **ADR-033 §Registration checklist** (the cron-registration ADR; section lands with #5808).
- **Pipeline detection:** if `$ARGUMENTS` contains a `RETURN CONTRACT`, run headless (skip interactive confirmation / `--dry-run` prompts) — mirror the sibling.
- **Sharp edges:** drafts are always skipped (author-owned); `gh pr merge --squash` cannot bypass server-side required checks (a mis-triaged red PR fails loudly at merge, not silently); the two learning files + ADR section depend on #5808 being on main first; Monitor (not a poll loop) for CI waits.
- **Test:** link `plugins/soleur/test/drain-prs.test.sh`.

### Phase 2 — Helper script + test

- **`plugins/soleur/skills/drain-prs/scripts/triage-prs.sh`** — runs the `gh pr list … --json …` query, classifies each PR into the six tiers (`mergeable`, `isDraft`, `reviewDecision`, `labels`, `statusCheckRollup`), emits tier-grouped JSON. Prefer a single pure-`jq` pipeline (per the sibling's sharp edge — avoid multi-language round-trips). Use two-stage `gh --json … | jq` (never `gh --jq` with `--arg`, per learning `2026-04-15-gh-jq-does-not-forward-arg-to-jq`). Validate `gh` auth + worktree up front; fail fast with readable errors.
- **`plugins/soleur/test/drain-prs.test.sh`** — mirror `drain-labeled-backlog.test.sh`. Synthetic PR-list JSON fixtures only (per `cq-test-fixtures-synthesized-only`): one PR per tier (ready-green, lockfile-fail, conflicting, review-required, draft, broken), an empty-list case, and the JSON output-shape/sort assertions. Drive `triage-prs.sh` against fixtures via stdin/env (no live `gh` call in tests).

### Phase 3 — Wiring (per `plugins/soleur/AGENTS.md`)

1. **README count:** `bash scripts/sync-readme-counts.sh` (rewrites `| Skills | 92 |` → `93`). Optionally add a curated `drain-prs` row beside `merge-pr` (`README.md:270`).
2. **`/soleur:go` router:** add a distinct row to `commands/go.md:62` table — `drain-prs` | "drain open PRs", "merge all green PRs", "clear the PR queue", "triage open pull requests" | `soleur:drain-prs`. Keep separate from the issue `drain` row (line 65). Add no label-extraction note (that's drain-labeled-backlog-specific).
3. **Budget bump:** in `components.test.ts:15`, raise `SKILL_DESCRIPTION_WORD_BUDGET` from 2292 by **exactly** the new description's word count (~34 → ~2326); append a bump-note to the inline comment in the existing format (`bumped +N for #<PR> (drain-prs skill description, N words, against a 2292/2292 zero-headroom baseline)`).
4. **PR body:** include a `## Changelog` section; apply the `semver:minor` label (new skill = MINOR — label verified to exist).

### Phase 4 — Validation

- `bash scripts/sync-readme-counts.sh --check` passes (readme-counts CI gate).
- `bun test plugins/soleur/test/components.test.ts` passes (budget bump correct).
- `bash plugins/soleur/test/drain-prs.test.sh` passes.
- Eleventy docs build (`soleur:deploy-docs`) passes (skills auto-discovered; confirm no `_data` edit needed).
- Skill compliance: third-person `description`, all `scripts/` links use markdown form, `name` matches dir.

## Files to Create

- `plugins/soleur/skills/drain-prs/SKILL.md`
- `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh`
- `plugins/soleur/test/drain-prs.test.sh`

## Files to Edit

- `plugins/soleur/README.md` (count 92→93 via sync script; optional curated row)
- `plugins/soleur/commands/go.md` (router row)
- `plugins/soleur/test/components.test.ts` (budget constant bump)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/skills/drain-prs/SKILL.md` exists with `name: drain-prs`, third-person `description` (≤1024 chars, no `<example>`), and a `<decision_gate>` block that (a) gates all merges behind operator confirmation, (b) supports per-PR opt-out within a tier, (c) states confirming = merges to main, (d) carries the API-budget note.
- [ ] SKILL.md encodes the 6-tier triage, the merge-queue-active + fallback merge paths (Monitor for CI waits, no background poll loop), the 3 fix-recipes, the review-delegation split, and the `cleanup-merged` step.
- [ ] SKILL.md references both `2026-06-30-*` learnings and ADR-033 §Registration checklist **by path**.
- [ ] `triage-prs.sh` classifies the `gh pr list` JSON into the 6 tiers; `drain-prs.test.sh` passes against synthetic fixtures covering one PR per tier + empty-list.
- [ ] `bash scripts/sync-readme-counts.sh --check` reports the skills count as **93** and exits 0.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes; `SKILL_DESCRIPTION_WORD_BUDGET` bumped by exactly the new description word count with an appended bump-note.
- [ ] `commands/go.md` has a `drain-prs` router row distinct from the issue `drain` row.
- [ ] Eleventy docs build passes.
- [ ] PR body has a `## Changelog` section; PR carries the `semver:minor` label.

### Post-merge (operator)

- [ ] Verify on main that the two `#5808` learnings + ADR-033 §Registration checklist resolve (Glob/Read). All automatable — no manual operator-only step.

## Domain Review

**Domains relevant:** Product (CPO — required by `hr-new-skills`). Marketing omitted with rationale. Others: none.

### Product/UX Gate

**Tier:** none (no UI surface; `Files to Create/Edit` match no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` glob — mechanical UI-surface override does not fire). CPO ran as the `hr-new-skills` assessment, not as a UI gate.
**Decision:** reviewed
**Agents invoked:** cpo
**Skipped specialists:** none (ux-design-lead / spec-flow-analyzer / copywriter N/A — no UI surface)
**Pencil available:** N/A (no UI surface)

#### Findings

CPO advisory: **ADVISORY (non-blocking)**. Operator-facing/dev-tooling classification **confirmed**; CMO omission justified (`brand-guide.md` Positioning governs the CaaS product surface, which this internal tooling never reaches). Three low-severity flow refinements, all folded into Phase 1: (1) add `--dry-run` preview — more valuable here than the sibling because this skill *merges*; (2) per-PR sub-selection within a tier at the decision gate (per learning `2026-04-17-cleanup-scope-outs-sub-cluster-selection`); (3) gate copy must state that confirming = code lands on main (higher irreversibility than the issue-drain, which ends at PR-opened). No capability gaps; no re-scope.

### Marketing (CMO) — omitted

Per `hr-new-skills`: internal maintainer dev-tooling with no marketing/brand/copy/pricing surface. CMO assessment omitted with this rationale; CPO assessment was still performed.

## Observability

Skip (justified). Files-to-Edit introduce no server/infra runtime surface: SKILL.md (prose), a helper bash script under `plugins/soleur/skills/drain-prs/scripts/` (operator-run CLI, deeper than the `plugins/*/scripts/` trigger glob), README/router/test edits. No new error path is reachable from Sentry/Better Stack because there is no new server code. Mirrors the sibling `drain-labeled-backlog`, which ships no observability section. The skill's runtime actions (`gh`, `git`, Monitor) surface failures directly in the operator's terminal.

## Architecture Decision (ADR/C4)

Skip (justified). A new operator-facing tooling skill makes no architectural decision — no ownership/tenancy boundary move, no new substrate/integration pattern, no resolver/dispatch/trust-boundary change, no reversal/extension of an existing ADR. It introduces no new external actor, external system, container/data-store, or access relationship to the C4 model (it uses the operator's existing `gh`/`git`). A competent engineer reading the existing ADRs + C4 would not be misled about the system after this ships. (Note: this skill *references* ADR-033 §Registration checklist as a fix-recipe pointer; it does not create or amend an ADR.)

## Test Scenarios

- Triage: a fixture PR per tier (ready-green, deps-with-`bun.lock`-fail, `CONFLICTING`, `review-required`/bot-fix, draft, conflicting+many-failing-checks) classifies into the correct tier; empty open-PR list yields an empty table and clean exit.
- `--dry-run`: prints the full tier table and performs zero merges.
- Decision gate: with no operator confirmation, zero merges occur (the gate is the only merge entry point).
- Merge path: queue-active enqueues via `gh pr merge --squash`; queue-inactive falls back to update-branch → Monitor-wait → merge.
- Budget: `components.test.ts` fails if the constant is not bumped; passes after the exact bump.
- README: `sync-readme-counts.sh --check` fails before the new skill dir, passes after, reporting 93.

## Sharp Edges

- **#5808 merge-order dependency.** The two `2026-06-30-*` learnings and ADR-033 §Registration checklist do not exist on main yet — they ship in PR #5808 (in the merge queue). Reference them by path; verify resolution at ship time. If #5808 is somehow not merged first, the SKILL.md path references will dangle — gate the merge of this PR on #5808.
- **`/soleur:go` is a command, not a skill** — the router row goes in `commands/go.md`, not a (non-existent) `skills/go/SKILL.md`.
- **README skills table is curated, the count is the gate.** `drain-labeled-backlog` is not individually listed; the load-bearing requirement is the auto-derived count (92→93 via `sync-readme-counts.sh`). Do not hand-edit the count.
- **Budget is at zero headroom (2292/2292).** Any new description word count must be added to `SKILL_DESCRIPTION_WORD_BUDGET` with a bump-note, or `components.test.ts` fails — this is the established convention, not an exception.
- **Monitor, never a background poll loop** for CI waits (`hr-monitor-not-run-in-background-for-polling`).
- A plan whose `## User-Brand Impact` section is empty or omits the threshold will fail `deepen-plan` Phase 4.6 — this section is filled (threshold `none` with reason).

## PR body reminder

Include a `## Changelog` section (per `plugins/soleur/AGENTS.md`); set the `semver:minor` label. Do NOT edit `plugin.json` version or `marketplace.json`.
