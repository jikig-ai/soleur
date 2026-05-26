---
title: Brainstorm framings citing register/ledger rows need citation verification; stale comments are canaries for sibling-call discovery; adjacent UI silent failures belong in data-residency PRs
date: 2026-05-16
category: workflow-issues
tags:
  - brainstorm-skill
  - premise-validation
  - article-30-register
  - sibling-call-discovery
  - stale-comments
  - pr-naming-collisions
  - silent-failure-adjacency
  - pr-d
  - pr-3244
related:
  - "#3244 (umbrella)"
  - "#3869 (PR-C deferrals tracker)"
  - "PR #3883 (PR-D draft)"
  - 2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd
  - 2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders
  - 2026-05-12-cite-prior-prs-by-actual-file-scope-not-umbrella-narrative
  - 2026-05-15-brainstorm-enumerate-umbrella-child-prs-before-leader-spawn
---

# Problem

PR-D brainstorm framing (provided by operator at session start) made four citation-style claims, of which three required correction during Phase 1.0.5 premise validation and one required CTO + repo-research reconciliation:

1. **"Required reading: `knowledge-base/legal/article-30-register.md` — PA1/PA2 TOM row, attachment-storage residency claim."** Premise validation read the file end-to-end and confirmed: PA1 mentions RLS-per-user-id as a generic TOM (line 50); PA2 covers conversation data but **never names** the `chat-attachments` bucket or `message_attachments` table. The cited row does not exist. If the brainstorm had carried the claim forward uncritically, the spec would have referenced a non-existent compliance baseline, and Phase 6 gdpr-gate would have flagged the gap mid-implementation (expensive pivot).

2. **"`cc-dispatcher.ts:1421` injects service-role into `persistAndDownloadAttachments`."** Grep for `persistAndDownloadAttachments` surfaced a **second** caller at `agent-runner.ts:2305` that the framing omitted entirely. The sibling had a stale `// SERVICE-ROLE: ...Migrated in PR-C alongside the rest of the attachment pipeline` comment that **falsely** claimed the migration was already done. The framing's single-call-site assumption would have produced a partial PR-D that left the agent-runner path on service-role, breaking the allowlist-shrink claim.

3. **"Tracker for review-derived deferrals: #3869 items 4–5."** Verified correctly. But #3869 also surfaced **item 6** (CI tenant-isolation job) which the framing didn't list — and which is a hard prerequisite for the PR-D test deliverables to actually fire under default CI. Without inspecting the tracker holistically (not just the cited item numbers), the brainstorm would have proposed `expect(data).toBeNull()` deny tests that silent-skip in CI.

4. **"#3660 referenced as predecessor."** `#3660` is `feat(chat): rail-level cohort indicator on conversations-rail (PR-D, deferred from PR-B)` — a UI badge feature belonging to the chat-RAIL/transcript-hardening track (parent #3603), **not** the runtime tenant-isolation track. Two coincidentally-overlapping "PR-A/B/C/D" letterings exist in the repo. Carrying the cross-umbrella name collision forward would have orphaned the actual runtime-PR-D scope under a UI-feature tracking shadow.

Separately, a research agent surfaced `apps/web-platform/components/chat/attachment-display.tsx` swallowing fetch errors with `.catch(() => {})` and rendering a **permanent skeleton loader** indefinitely on `/api/attachments/url` failures. This UI silent-failure mode is technically OUT of the data-residency surface PR-D was scoped to address — but it's INSIDE the same user-flow ("founder attaches file → bytes flow through tenant-RLS → preview renders"). A botched RLS migration manifests to the user as "skeleton-forever"; if the UI fix is deferred to a follow-up PR, the first user incident of a botched migration is also the discovery of the skeleton bug.

# Root cause

Three distinct framing-class failures:

**(A) Register/ledger citation as authority.** Brainstorm framings written by an operator who saw a register row "in the past" (or who is generalizing from a sibling artifact) can cite rows that were planned but not landed, or that exist in adjacent files. The standard premise-validation checklist (`gh issue view`, `gh pr view`, file-existence) covers GitHub artifacts but doesn't explicitly cover **register/ledger row** citations (Article 30, technical-debt ledger, deferred-scope-out backlog, ADR registry). These markdown-table rows look like authoritative compliance baselines; treating them as such without `grep` confirmation propagates a phantom constraint into the spec.

**(B) Single-call-site assumption.** A framing that cites one call site for a helper function implicitly claims it's the only caller. Standard sibling-grep discovery catches the second caller — but the **stale comment** on the sibling (`// Migrated in PR-C`) is itself a higher-signal canary than the call site alone. Stale-narrative markers (`Migrated in PR-`, `pending PR-`, `TODO PR-`, `as of PR-`) are written at one point in time and rot when the actual migration is deferred or split. The comment IS the bug report, not just adjacent context.

**(C) Cross-umbrella name collision.** Multi-stage feature umbrellas commonly use Greek-letter or alphabetic suffixes (PR-A/B/C/D) inside a single umbrella body. Two umbrellas running in parallel can re-use the same letters; the `gh issue list --search "PR-D"` result set will contain BOTH tracks and the carrier-pigeon framing can pick up the wrong one. The brainstorm needs an explicit umbrella-disambiguation step ("which umbrella owns each PR-X reference?") that catches the collision before leader spawn.

**(D) Adjacent silent-failure scoping.** Data-residency PRs are typically scoped to "the data path." UI surfaces that consume the data path are typically considered "out of scope" by reflex. But the user incident class is "founder attaches file and nothing happens" — which subsumes both the residency miss AND the UI silent failure. The scope boundary should be drawn by **user-incident class**, not by code-area taxonomy.

# Solution

Four additions to brainstorm Phase 1.1 premise validation (`plugins/soleur/skills/brainstorm/SKILL.md`):

**(A) Register/ledger citation verification.** When the framing cites a row in any of:
- `knowledge-base/legal/article-30-register.md` (PA-N rows)
- `knowledge-base/project/technical-debt/` ledger entries
- `knowledge-base/engineering/architecture/decisions/` ADRs
- `knowledge-base/legal/tenant-dpa-register.md`
- `knowledge-base/product/roadmap.md` phase milestones

…grep the actual file for the cited row identifier (PA1, PA2, ADR-NNN, etc.) AND for the cited subject (`chat-attachments`, `message_attachments`, etc.). If the cited row exists but doesn't contain the cited subject, the framing is asserting a *planned-but-unlanded* state — flag as Open Question, not as constraint.

**(B) Sibling-call discovery via stale-comment canary.** When the framing cites a single call site for a helper, run:

```bash
# Find all callers
git grep -n "<helperName>" -- '*.ts' '*.tsx'

# Find stale-narrative markers in caller files
git grep -nE '(Migrated|migrated|completed|deferred|pending|TODO) in PR-[A-Z0-9]' -- '*.ts' '*.tsx'
```

Each result in the second grep is a high-signal candidate for "the migration didn't actually happen" or "the comment is from a different track." Cross-check against `git log -S "<comment-marker>" --` to see when the comment was written and whether the PR it references actually landed.

**(C) Umbrella disambiguation for PR-X letterings.** When the framing references `PR-A/B/C/D/E/...` Greek-letter labels:

```bash
# Find all umbrellas that use the cited PR-X label
gh issue list --search "PR-D in:body" --state all --json number,title,body | \
  jq -r '.[] | "\(.number): \(.title)"' | head -20

# Check parent linkage of each result
for n in <result-numbers>; do gh issue view $n --json title,body --jq '.body' | head -30; done
```

If multiple distinct umbrellas surface, add an explicit "PR-X scope confirmation" item to the brainstorm Open Questions and disambiguate before leader spawn.

**(D) User-incident-class scope boundary.** For data-residency PRs, in addition to the data-path surface inventory (CTO grep sweep for `.storage.upload/.download/.from(table)`), spawn a research agent (or operator does it) that enumerates the **user-facing consumption path** for the residency-protected data. Any silent-failure mode in the consumption path that would manifest identically to a botched residency migration belongs INSIDE the residency PR scope — not deferred to a UI cleanup follow-up. Specifically: grep for `.catch(() => {})` / `.catch(noop)` / `void` in the consumption-path files; any swallow-without-fallback is an in-scope adjacency.

# Prevention

The four additions above land as skill-content edits to `plugins/soleur/skills/brainstorm/SKILL.md` Phase 1.1 (Research). Bounded surface: four short sub-bullets under the existing "Verifying ..." paragraphs, each ~80-120 words with a grep command.

These additions compose with — do not replace — the existing premise-validation checklist (file-existence, `gh pr view` referenced PRs, `git grep` cited symbols/flags, leader-substrate cross-check). The new (A), (B), (C), (D) cover citation classes the existing checklist does not target by name.

# Session Errors

- **AskUserQuestion called with no parameters** — InputValidationError on first invocation. Recovery: re-called with proper `questions` array including `question`, `header`, `multiSelect`, `options`. Prevention: when invoking AskUserQuestion (or any tool with required parameters that take complex JSON), construct the parameter object first and only then make the tool call.

- **TaskCreate/TaskUpdate not in initial tool surface** — required ToolSearch to load deferred-tool schemas. Recovery: `ToolSearch select:TaskCreate,TaskUpdate,TaskList`. Prevention: when starting a multi-phase skill where the skill itself recommends task tracking, pre-load TaskCreate/TaskUpdate via ToolSearch at Phase 0 setup instead of waiting for the system-reminder.

# References

- Predecessor learnings (extended by this one):
  - `2026-05-12-cite-prior-prs-by-actual-file-scope-not-umbrella-narrative.md` (covers narrative-vs-file-scope drift; this learning adds the stale-comment-as-canary)
  - `2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders.md` (covers symbol citations; this learning adds register/ledger-row citations)
  - `2026-05-15-brainstorm-enumerate-umbrella-child-prs-before-leader-spawn.md` (covers child-PR enumeration; this learning adds cross-umbrella PR-X collision detection)

- This session's artifacts:
  - Brainstorm: `knowledge-base/project/brainstorms/2026-05-16-pr-d-attachments-storage-tenant-rls-brainstorm.md`
  - Spec: `knowledge-base/project/specs/feat-pr-d-attachments-storage-tenant-rls/spec.md`
  - Draft PR: #3883
  - PR-E tracking issue: #3887
