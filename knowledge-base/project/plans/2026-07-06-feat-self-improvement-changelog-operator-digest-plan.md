---
title: "feat: self-improvement changelog — operator-digest dogfood section"
date: 2026-07-06
issue: "#6039"
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-06-self-improvement-changelog-brainstorm.md
spec: knowledge-base/project/specs/feat-self-improvement-changelog/spec.md
deferred_followup: "#6102"
---

# Plan: Self-Improvement Changelog — operator-digest dogfood section ✨

## Overview

Add a fifth section, **"What got smarter this week,"** to the existing
`operator-digest` skill. It surfaces Soleur's *completed* self-improvement
activity — merged `self-healing/auto` promotion PRs + rules retired this week —
to the operator (Jean) in plain, platform-truthful language. This is the
dogfood-first re-scope of #6039: validate the framing and the real signal
volume on the operator before any founder-facing surface (deferred to #6102).

The entire change is prose edits to one file:
`plugins/soleur/skills/operator-digest/SKILL.md`. operator-digest runs headless
inside `claude-code-action` in the private `jikig-ai/operator-digest` repo with
the public `soleur` repo checked out at `$GITHUB_WORKSPACE`; the LLM reads the
skill and runs the source commands. No executable code, no new infra, no new
cron, no UI surface.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| Source = merged `self-healing/auto-*` PRs | Label is exactly `self-healing/auto` (`cron-compound-promote.ts:638`); branch shape is `self-healing/auto-<hash>-<date>`; **0 exist to date** | Query by **label** via List API; empty is the current real state |
| "resolve via promotion-log cluster-hash" | `promotion-log.md` maps cluster-hash→PR, but the List-API `--label` query returns the merged PRs directly | Use `--label` directly (simpler, no hash join); promotion-log stays the audit trail, not the digest's live source |
| Query the PRs | operator-digest **forbids `--search`** (Search API returns empty cross-repo under the App-installation token — documented at SKILL.md:78-85, 188-193) | Data source MUST be `gh pr list --label ... --json` (List API) + jq `mergedAt >= $SINCE`. **Never `--search`.** |
| TR3: "fallback tested against real-shape fixture" (from the digest-launch-quality learning) | operator-digest is a **prose skill with no executable code** — the 2026-06-11 learning was about `cron-weekly-release-digest.ts` (TS + fixtures). There is nothing to run a fixture through. | Re-interpret TR3: document the exact **production PR-title/label shape** (`self-healing(auto): promote cluster <hash> <date>`, label `self-healing/auto`) inside the skill as the LLM's grounding example. Empty state = current real production state (validated directly). Satisfies `cq-test-fixtures-synthesized-only`. |
| "N recurring mistakes fixed" per-item | PR titles carry only a cluster hash + target path (`AGENTS.core.md`/`SKILL.md`) — no human description; per-item detail lives in PR bodies | Render **count + PR links** ("N improvements shipped to the shared brain your agents run on — [links]"), NOT fabricated per-item descriptions (reading bodies would violate L2 summaries-only). |

## Implementation Phases

### Phase 1 — Add the fifth section to operator-digest/SKILL.md

1. **Intro (SKILL.md:14-15):** change "reads four sources … four sections" → "five sources … five sections."
2. **Scope guardrail L1 (SKILL.md:54):** "Read ONLY the four named sources" → "five named sources."
3. **New section body** after §4 ("Action needed from you"), before "Deterministic fallback":

   ```markdown
   ### 5. What got smarter this week

   Source: self-improvements the loop **completed** in the window —
   promotion PRs it merged, and rules it retired.

   ```bash
   # Merged self-improvement PRs. List API + --label (NOT --search: Search API
   # is empty cross-repo under the App token — same reason as §1). Filter
   # mergedAt >= $SINCE in synthesis. Production shape: title
   # "self-healing(auto): promote cluster <hash> <date>", label "self-healing/auto".
   gh pr list -R jikig-ai/soleur --state merged --label "self-healing/auto" \
     --json title,url,mergedAt --limit 100

   # Rules retired this week (additions to the retired list = retirements).
   git log --since="$SINCE" -p -- scripts/retired-rule-ids.txt
   ```

   Render as a **platform-level outcome**, never per-tenant: "Soleur got
   sharper this week — N improvements shipped to the shared brain your agents
   run on," with each improvement's PR link as its substantiation. If rules
   were retired, add "and M stale rules were retired." Do NOT invent per-item
   descriptions from the cluster hash — the count + link is the honest claim
   (the PR title carries only a hash + target file, not a human summary).
   **Never write "your workspace got smarter"** — the improvement is to the
   shared Soleur harness, not the operator's own workspace.
   ```
4. **Deterministic fallback (SKILL.md:175-178):** add
   "Section 5 → \"Nothing was promoted to the shared harness this week.\""
5. **Output section (SKILL.md:205):** "four `##` sections" → "five `##` sections."

The existing **Read-failure handling** (SKILL.md:38-50) and **L2 summaries-only**
(SKILL.md:56-64) apply to §5 unchanged — a non-zero `gh`/`git` exit renders the
⚠️ line (FR4), not the quiet-week fallback (FR3); PR titles/rule IDs are
summarized, never dumped raw.

## Files to Edit

- `plugins/soleur/skills/operator-digest/SKILL.md` — the five edits above (single file, prose only).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — `plugins/soleur/skills/operator-digest/SKILL.md` contains a `### 5. What got smarter this week` heading.
- [ ] AC2 — §5's PR query uses `gh pr list` with `--label "self-healing/auto"` and does **NOT** contain `--search` anywhere in §5 (`grep -n 'gh pr list' <file>` shows `--label`; `awk '/### 5\./{f=1;next}/^### /{f=0}/^## [^#]/{f=0}f' <file> | grep -c -- '--search'` returns 0).
- [ ] AC3 — §5 renders a platform-level outcome and the file's §5 body does **not** contain the string "your workspace" (`awk '/### 5\./{f=1;next}/^## [^#]/{f=0}f' <file> | grep -ci 'your workspace'` returns 0).
- [ ] AC4 — The deterministic-fallback list includes a Section 5 line: `grep -c 'Nothing was promoted to the shared harness' <file>` ≥ 1.
- [ ] AC5 — Intro (`five sources`/`five sections`), scope L1 (`five named sources`), and Output (`five ## sections`) all updated. Punctuation-safe total check: "four" appears in the skill ONLY in the four-sources/sections references (lines 14, 15, 54, 205), so `grep -ciw four <file>` returns 0 after the edit AND `grep -c 'five' <file>` ≥ 3. (Word-boundary `-w` avoids matching substrings; total-elimination sidesteps the backtick between "four" and "sections" in the Output line.)
- [ ] AC6 — `cd apps/web-platform && ./node_modules/.bin/vitest run test/components.test.ts` passes (skill description budget not exceeded — no `description:` change here, but confirm the skill still parses).
- [ ] AC7 — Data-source commands are List-API/git-log only (no `--search`); verified by AC2 + a repo-wide `awk` scoped to §5.

### Post-merge (operator)
- [ ] AC8 — On the next scheduled operator-digest run, §5 renders "Nothing was promoted to the shared harness this week." (the current real state — 0 promotions) OR a ⚠️ read-failure line — never a blank section. Verify by reading the next `Digest:` issue in `jikig-ai/operator-digest`. *(Automation: the private-repo cron fires the run; verification is reading the produced issue — read-only, no operator action beyond eyeballing the next digest.)*

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Marketing (carry-forward from brainstorm `## Domain Assessments`).

### Product (CPO)
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Dogfood via operator-digest; defer founder surface (#6102); per-tenant framing must not ship; signal too thin for a founder surface (0 promotions). This plan implements exactly that scope. CPO sign-off carried from brainstorm (`requires_cpo_signoff: true`).

### Legal (CLO)
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Permitted with wording guardrails. Platform-level framing (not "your workspace") — enforced by AC3. Data-minimization: source sanitized artifacts (PR titles/labels, retired rule IDs), never raw logs/bodies — enforced by reusing L2 summaries-only. Substantiation link per improvement (PR URL) — baked into §5 render.

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward + plan research)
**Assessment:** Data source is global-only (no per-tenant signal). This plan uses the List-API+label path (avoids the documented Search-API-under-App-token trap) and reuses operator-digest's read-failure + fallback discipline. No new infra/cron/web page. The future founder surface (fork `cron-weekly-release-digest.ts`) + its ADR are deferred to #6102.

### Marketing (CMO)
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** "Soleur / your agents / shared brain got sharper" framing; suppress empty weeks honestly (the fallback line is honest, not filler). Applies to the operator dogfood; founder channel/format decisions deferred to #6102.

### Product/UX Gate
**Tier:** none
**Decision:** N/A — no UI surface. Files-to-Edit is a single prose SKILL.md; the digest output is markdown in a private GitHub issue. No `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`; mechanical UI-surface override does not fire.
**Pencil available:** N/A (no UI surface)

## User-Brand Impact

**If this lands broken, the user experiences:** the weekly operator digest's "got smarter" section either renders a false "nothing happened" off a silently-failed read (Search-API trap), or overstates improvement — eroding the operator's trust in the digest as a comprehension tool.
**If this leaks, the user's data is exposed via:** a raw PR body / log line / retired-rule context copied into the digest instead of a sanitized summary (mitigated by inheriting L2 summaries-only + count+link-only rendering).
**Brand-survival threshold:** single-user incident.

CPO sign-off carried forward from brainstorm (Phase 0.1 `USER_BRAND_CRITICAL=true`). `user-impact-reviewer` will run at PR review time per review/SKILL.md.

## Observability

**Skipped — pure prose skill, no code-class file.** Files-to-Edit is only
`plugins/soleur/skills/operator-digest/SKILL.md` (docs class; not under
`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`), and
no new infra surface is introduced. The section's own read-failure observability
(a failed `gh`/`git` read → ⚠️ line in the digest) is inherited from the skill's
existing Read-failure-handling contract, which is itself the operator-facing
signal. Per Phase 2.9 skip criteria (pure-docs, no code/infra surface).

## Architecture Decision (ADR/C4)

**No architectural decision in this plan.** Adding a prose section to an
existing skill introduces no new substrate, tenancy boundary, or resolver
change; a competent engineer reading the existing ADRs + C4 would not be misled
about the system after this ships. The **future** founder-facing surface (fork
`cron-weekly-release-digest.ts` + per-tenant attribution) is the architectural
decision — it is owned by deferred issue #6102, whose body already names the
required ADR (delivery-surface & tenant attribution) as a build constraint.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` bodies contain no
reference to `operator-digest` (checked 2026-07-06).

## GDPR / Compliance Gate

Trigger (b) fires (brand-survival threshold `single-user incident` declared).
Assessed via `/soleur:gdpr-gate` against this plan (see gate output appended at
plan time). Surface is non-regulated: the §5 data is global harness self-edit
metadata (merged PR titles = cluster hash + target file path; retired rule
IDs) — no personal data, no founder BYOK, no schema/auth/API/`.sql` surface.
Data-minimization is structurally enforced by inheriting operator-digest's L2
summaries-only + "never copy a raw record" scope guardrails. CLO reviewed the
data-minimization posture in brainstorm.

## Test Scenarios

1. **Empty week (current real state):** 0 merged `self-healing/auto` PRs, 0 retired rules → §5 renders "Nothing was promoted to the shared harness this week." (not blank, not ⚠️).
2. **Populated week (grounded on production shape):** ≥1 merged `self-healing/auto` PR in window → §5 renders "Soleur got sharper this week — N improvements shipped … [PR links]" with no per-item hash jargon and no "your workspace".
3. **Read failure:** `gh pr list --label` exits non-zero → §5 renders the ⚠️ read-failure line, NOT the quiet-week fallback.
4. **Retired-rule-only week:** 0 PRs but rules added to `scripts/retired-rule-ids.txt` in window → §5 reports "M stale rules were retired" honestly.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6. This plan's section is filled.
- The single most important correctness trap: **§5 must never use `gh pr list --search`** — under the operator-digest App-installation token the Search API returns empty cross-repo, which would render "0 improvements" every week (a silent read-failure masquerading as a quiet week — the exact FR3/FR4 failure). Use `--label` (List API). Enforced by AC2.
- Do not render per-item descriptions from the cluster-hash PR title — it carries no human summary. Count + PR link is the honest, data-minimizing floor.
