---
date: 2026-05-09
issue: "#3489"
type: docs-cleanup
classification: docs-only
requires_cpo_signoff: false
related_pr: "#3486"
related_learning: "knowledge-base/project/learnings/2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md"
deepened: 2026-05-09
---

# Fix: Retired-rule-id sweep for `cq-gh-issue-label-verify-name`

## Enhancement Summary

**Deepened on:** 2026-05-09
**Sections enhanced:** 4 (Acceptance Criteria, Risks, Sharp Edges, Implementation Notes)
**Research agents used:** none — focused-deepen (small docs-only PR with established PR #3486 pattern)

### Key Improvements

1. **Confirmed canonical replacement target.** `plugins/soleur/skills/ship/references/ci-workflow-authoring.md` exists, is 25 lines, and contains all 4 retired GitHub Actions rules under `(ex-…)` breadcrumbs (verified with `Read`). The runbook's pointer is load-bearing — file existence verified pre-implementation.
2. **Live retirement-status verification of all 5 IDs.** Ran `grep -qE "^${id} " scripts/retired-rule-ids.txt` for each: all 5 retired, all in `2026-04-23` / `2026-04-24` window. Issue body claim holds.
3. **Live grep-count verification of citations.** Confirmed exactly 5 citations exist (1 in `go.md`, 2 in `drain-labeled-backlog/SKILL.md`, 1 in `plan/SKILL.md`, 1 line in `cloud-scheduled-tasks.md` containing 5 retired IDs).
4. **Self-check on plan-internal rule citations.** Plan's own only active-rule citation (`wg-use-closes-n-in-pr-body-not-title-to`) verified active in AGENTS.md. The 5 retired IDs cited in the plan body appear only as **subjects of the sweep** (the IDs being removed from elsewhere), not as load-bearing rationale — this is the correct usage pattern post-#3486.

### New Considerations Discovered

- The runbook line at `cloud-scheduled-tasks.md:375` enumerates 6 rule IDs total; 5 are retired. The remaining one (`cq-gh-issue-create-milestone-takes-title`) is also retired (verified). The plan should drop ALL 6 from the line, not just the 5 named — see updated AC below. This widens the original issue scope by one ID but keeps the line's fix complete.
- The plan-skill Sharp Edges entry at `plan/SKILL.md:721` and `deepen-plan/SKILL.md:556` together form the canonical home for the label-verify convention. The drain-skill `SKILL.md` lines 30/64 are the third leg. After this sweep, the convention will live in 3 plain-language locations with no stale rule-ID attribution anywhere.

## Overview

The AGENTS.md rule `cq-gh-issue-label-verify-name` was retired on 2026-04-23 (per `scripts/retired-rule-ids.txt`: "gh rejects invalid --label with clear error before issue creation"). Five active citations remain in skill, command, and runbook files that still treat it as if it were a live AGENTS.md rule. The convention the rule encoded (verify GitHub labels exist before citing) is still valid — it now lives in the planning skills as Sharp Edges and as `deepen-plan` AC items. PR #3486 established the inline-fix pattern on `deepen-plan/SKILL.md:556`. This plan sweeps the remaining four active files using the same pattern.

A separate finding surfaced during planning: the runbook line that contains the target citation also contains **four other retired rule IDs** (`cq-ci-steps-polling-json-endpoints-under`, `cq-workflow-pattern-duplication-bug-propagation`, `hr-in-github-actions-run-blocks-never-use`, `hr-github-actions-workflow-notifications`). Folding them into the same edit is the right call (same line, same fabrication class, same fix shape — see Open Code-Review Overlap below).

Historical citations under `knowledge-base/project/{learnings,plans}/**` are out of scope and remain as-of-their-date accurate.

## User-Brand Impact

**If this lands broken, the user experiences:** No user-facing impact — these are operator-facing skill, command, and runbook files. Worst case is a broken-link-style citation in an internal doc the operator may grep.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no user data, auth, or payment surfaces touched. Pure documentation cleanup.

**Brand-survival threshold:** none

**Reason (threshold=none + sensitive-path scan):** Edits are restricted to `plugins/soleur/{commands,skills}/*.md` and `knowledge-base/engineering/ops/runbooks/*.md`. No `apps/`, no auth/payment paths, no schema. Sensitive-path regex from preflight Check 6 does not match.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Reality | Plan response |
|---|---|---|
| 5 active citations across 4 files | Verified — `grep -rEn "cq-gh-issue-label-verify-name"` in `plugins/`, `knowledge-base/engineering/` returns exactly 5 hits (after excluding the already-fixed `deepen-plan/SKILL.md:556` from PR #3486). | Use the issue's enumerated list verbatim. |
| Pattern to follow: PR #3486 inline fix on `deepen-plan/SKILL.md:556` | Verified — `Read deepen-plan/SKILL.md:556` shows: dropped attribution, parenthetical noting retirement, **Why** still cites the canonical PR. | Replicate this shape per site. |
| Historical citations in `knowledge-base/project/{learnings,plans}/**` predate retirement, leave alone | Verified by inspection — these are point-in-time records of what an AGENTS.md rule said when the plan/learning was authored. | Out of scope, no edits to these directories. |
| Issue lists 1 retired rule on `cloud-scheduled-tasks.md:375` | **Reality is wider — ALL 6 IDs on the line are retired.** Same line contains 5 other retired rule IDs: `cq-ci-steps-polling-json-endpoints-under` (2026-04-24), `cq-workflow-pattern-duplication-bug-propagation` (2026-04-24), `hr-in-github-actions-run-blocks-never-use` (2026-04-24), `hr-github-actions-workflow-notifications` (2026-04-24), `cq-gh-issue-create-milestone-takes-title` (2026-04-23). Verified live via `grep "^${id} " scripts/retired-rule-ids.txt`. The entire `AGENTS.md rules:` enumeration on this line is dead. | Fold all 5 sibling retirements into the same edit. The whole line gets replaced with pointers to canonical owners (`plugins/soleur/skills/ship/references/ci-workflow-authoring.md` for the 4 GH Actions rules, planning-skill citations for the 2 `gh issue` rules). |

## Files to Edit

1. `plugins/soleur/commands/go.md` — line 40 (1 citation)
2. `plugins/soleur/skills/drain-labeled-backlog/SKILL.md` — lines 30 and 64 (2 citations)
3. `plugins/soleur/skills/plan/SKILL.md` — line 721 (1 citation, inside a Sharp Edges entry)
4. `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` — line 375 (5 retired rule IDs on the same line)

## Files to Create

None.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each planned file path against issue bodies.

- **#3489 (this issue)** explicitly names all four files. Self-referential — closes on merge.
- No other open `code-review` issues touch these paths. The `cloud-scheduled-tasks.md` widening (4 sibling retired IDs) is a fold-in decision, not a separate scope-out — it's the same fabrication class on the same line, and review of this PR would flag it anyway. Not filing a separate issue: the cost of folding in is one extra edit; the cost of deferring is a second PR for the same line.

**Disposition:** **Fold in** — extend scope to include the 4 sibling retired rule IDs on `cloud-scheduled-tasks.md:375`. Same line, same retirement window (2026-04-23 / 2026-04-24), same fix shape.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/commands/go.md:40` — `cq-gh-issue-label-verify-name` citation removed; rationale inlined ("verified via `gh label list`") or replaced with a pointer to the convention's living home in the planning skills. No AGENTS.md attribution remains.
- [ ] `plugins/soleur/skills/drain-labeled-backlog/SKILL.md:30` and `:64` — both citations removed. Replace with inline rationale referencing `gh label list` validation. The drain-labeled-backlog skill now owns this convention; no upstream attribution needed.
- [ ] `plugins/soleur/skills/plan/SKILL.md:721` — the `Cited rule: cq-gh-issue-label-verify-name (...)` parenthetical is rewritten to drop the retired ID. Add a brief note that the convention now lives in the deepen-plan AC (line 556). The `**Why:** PR #3378` block is preserved verbatim.
- [ ] `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md:375` — **all 6 retired rule IDs** removed from the `AGENTS.md rules:` enumeration (the issue scope was 1 ID; deepen-plan widened to 6 after `grep "^${id} " scripts/retired-rule-ids.txt` confirmed each was retired). Each replaced with a pointer to its canonical owner per `scripts/retired-rule-ids.txt`:
  - `hr-in-github-actions-run-blocks-never-use` → `plugins/soleur/skills/ship/references/ci-workflow-authoring.md` (verified: file exists, 25 lines, contains the rule under `(ex-…)` breadcrumb at line 9)
  - `hr-github-actions-workflow-notifications` → same reference (line 10)
  - `cq-ci-steps-polling-json-endpoints-under` → same reference (line 14)
  - `cq-workflow-pattern-duplication-bug-propagation` → same reference (line 16)
  - `cq-gh-issue-label-verify-name` → drop AGENTS.md attribution; convention now lives in `plan/SKILL.md` Sharp Edges + `deepen-plan/SKILL.md:556` AC.
  - `cq-gh-issue-create-milestone-takes-title` → drop AGENTS.md attribution; the constraint is discoverable via `gh`'s own clear error (per the retirement breadcrumb: "gh rejects numeric milestone/no-subcommand with clear error"). Inline a one-clause note pointing to `gh issue create --milestone "<title>"` usage if the runbook still benefits from a callout, or drop entirely if context already covers it.
- [ ] Verification grep passes: `grep -rEn "cq-gh-issue-label-verify-name" --include="*.md" plugins/ knowledge-base/engineering/` returns zero hits after the sweep. (Citations under `knowledge-base/project/{learnings,plans}/**` are out of scope and remain.)
- [ ] Sibling-retired-ID verification grep passes for the runbook line: `grep -E "(cq-ci-steps-polling-json-endpoints-under|cq-workflow-pattern-duplication-bug-propagation|hr-in-github-actions-run-blocks-never-use|hr-github-actions-workflow-notifications|cq-gh-issue-create-milestone-takes-title)" knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` returns zero hits.
- [ ] Plan-internal rule-ID self-check: every `\b(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]+\b` token in the **edited files** (after the sweep) that is cited as **active rationale** must resolve to an active AGENTS.md rule. Tokens that appear as **subjects of replacement** (e.g., the retired ID being removed from a citation, named in a `(ex-…)` breadcrumb) are exempt — they are documenting the retirement, not citing as live.
- [ ] `lefthook run pre-commit` passes (covers `lint-rule-ids.py`, markdown lint, etc.).
- [ ] PR body uses `Closes #3489` on its own body line. No auto-close keywords elsewhere in title or body. (Per `wg-use-closes-n-in-pr-body-not-title-to`.)

### Post-merge (operator)

None — this is a docs-only PR with no operator actions, terraform applies, or external service syncs.

## Test Strategy

No new tests added. The verification path is the two grep commands in Acceptance Criteria — they prove the absence of every retired ID at the file scope. The `lint-rule-ids.py` lefthook hook covers AGENTS.md immutability invariants on the rule registry side; this PR does not modify AGENTS.md or `scripts/retired-rule-ids.txt`.

The existing convention is preserved by the deepen-plan rule-ID verification AC (`deepen-plan/SKILL.md:557`) — any future plan citing a retired ID will be caught at deepen-plan time.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a documentation-only sweep correcting retired-ID citations in skill, command, and runbook files. No product, marketing, legal, finance, sales, support, or operations decisions involved. CTO-domain implications are nil because no architecture, code, schema, or runtime behavior changes.

## Risks

- **Low — wording drift across the 4 sites.** Mitigation: each replacement uses the same shape (drop AGENTS.md attribution, point to the convention's living home, preserve any PR/learning citation). Reviewer can compare the four edits side-by-side.
- **Low — sibling retired IDs in `cloud-scheduled-tasks.md` not in original issue scope.** Deepen-plan discovered all 6 IDs on the line are retired, not 5 as initially scoped. Mitigation: documented in Research Reconciliation table and Open Code-Review Overlap section. Folding in is justified by the cost calculus (one edit vs. a future third PR for the same line).
- **Low — runbook semantic loss.** The `cloud-scheduled-tasks.md:375` line previously gave the operator a one-line index of every applicable rule. After the sweep, the line should still serve that purpose, just pointing to canonical owners. The replacement should not be deletion of the line; it should be replacement of dead-citations with live-pointers.
- **Low — drain-skill citation removal.** The drain-labeled-backlog skill currently uses the retired ID to authorize its own validator step. Dropping the citation means the skill's validator stands on its own authority. Mitigation: the inline rationale (`Validated against gh label list before querying`) is sufficient — the skill *is* the convention's owner now.
- **None for blast radius.** Files touched are operator-facing only; no production code, no auth, no schema.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with an explicit reason — meets the gate.
- When dropping an AGENTS.md rule citation, do not silently delete the surrounding rationale. The cited behavior is still load-bearing for the reader; rewrite the prose so the rationale stands without the citation. Pattern from PR #3486: drop the `(rule cq-...)` parenthetical, inline a one-clause justification, and (where helpful) point to where the convention now lives.
- The runbook citation includes 5 retired sibling rules from the GitHub Actions / CI / `gh issue` domains. Their canonical replacement is `plugins/soleur/skills/ship/references/ci-workflow-authoring.md` (for the 4 GH Actions rules) — **verified during deepen-plan** that the file exists (25 lines) and contains all 4 rules under `(ex-…)` breadcrumbs. The 2 `gh issue` rules (`-label-verify-name`, `-create-milestone-takes-title`) do not have a single canonical replacement file; their conventions are inlined in the planning skills and the discoverability of the underlying `gh` errors.
- Do not extend scope to `knowledge-base/project/{learnings,plans}/**` even if a grep pulls in matches. Those are point-in-time historical records and editing them rewrites the past — a different anti-pattern.
- This PR adds 5 retired-rule-ID *strings* to the runbook in the form of `(ex-…)` breadcrumbs (or equivalent prose). The `lint-rule-ids.py` hook only enforces immutability on AGENTS.md rule definitions — it does not parse markdown citations. But review agents (`code-quality-analyst`) DO grep for fabricated/retired IDs in citations. Make sure each retired ID, where it appears post-sweep, is contextually clear as a *retired* ID being referenced for breadcrumb purposes, not as an active citation. The PR #3486 inline-fix pattern handles this with the parenthetical "(retired YYYY-MM-DD; convention now lives in <path>)".
- The PR body MUST place `Closes #3489` on its own line and use `Ref` for any other issue references. This is per `wg-use-closes-n-in-pr-body-not-title-to` (verified active in AGENTS.md). Auto-close keywords elsewhere (in code blocks, checkboxes, prose) trigger anyway.

## Implementation Notes

The four edits are mechanical and independent. Suggested order (lightest first to warm up the pattern, runbook last because it has the most replacements):

1. `plugins/soleur/commands/go.md:40` — single occurrence, simplest case.
2. `plugins/soleur/skills/drain-labeled-backlog/SKILL.md:30, 64` — two occurrences in same file.
3. `plugins/soleur/skills/plan/SKILL.md:721` — single occurrence inside a Sharp Edges entry; preserve the surrounding **Why** block verbatim.
4. `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md:375` — 5 retired IDs on one line; replace each with its canonical owner pointer.

Each edit is small enough to fit in one `Edit` tool call. Total expected diff: ~40-60 lines changed across 4 files.
