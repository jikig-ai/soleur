---
title: "Bundle-brainstorm patterns: deliberate-revert for fabrication risk, fixture sourceUrl as legal record, leader-refresh on in-flight features"
date: 2026-05-11
category: best-practices
module: brainstorm, plan, review
related_issues: [3472, 3473, 3474, 3436, 3440]
related_files:
  - plugins/soleur/commands/go.md
  - plugins/soleur/skills/brainstorm/SKILL.md
  - apps/web-platform/scripts/spike/pdf-outline-fixtures.json
tags: [brainstorm, ux-of-shipping, prompt-contract-laundering, legal-record, leader-carry-forward]
---

# Three Bundle-Brainstorm Patterns

Captured from the 2026-05-11 brainstorm of #3472 + #3473 + #3474 (PDF chapter-chunking Phase 3.B bundle). Three patterns are generalizable beyond this feature.

## Pattern 1 — Deliberate-Revert as a Brand-Survival Mitigation

### What

When a feature has two layers that must ship together to avoid a fabrication-class user impact — a **contract surface** (system prompt directive, MIME-type promise, response prefix) and a **dispatch surface** (code path that fulfills the contract) — and only the contract layer is ready in the current PR, **deliberately revert the contract surface** in that PR. Ship the foundations underneath, but keep the user-visible promise unmade until the dispatch layer lands.

### When this applies

The pattern is load-bearing when the contract layer, shipped alone, would **launder** a downstream failure mode through user trust. Example from this session: a `[Answering from chapter N]` prefix instructs the model that an authoritative chapter content block was attached. If the prefix ships before dispatch wiring, the model emits the prefix anyway — confidently citing a chapter that was never loaded. The fabrication acquires institutional voice through the prefix.

Signals to look for:
- The contract surface promises a property of the response (provenance, attribution, completeness, freshness).
- The dispatch surface produces the data that property describes.
- Shipping the contract without the dispatch produces a confidently-wrong response, not an obvious error.

### How

1. Foundations PR ships the dispatch-layer scaffolding (router module, types, resolver wiring) plus the contract-layer code as `*-prompt.ts` / template strings.
2. Same PR **explicitly does NOT consume** the contract-layer template in any code path. Both runners (Concierge + Leader, in this session) fall through to a pre-existing bridge.
3. Tests are added that pin the **fall-through invariant** — these tests are negative assertions ("directive REVERTED, bridge is what fires"). They flip to positive assertions in the follow-up PR.
4. Follow-up PR re-introduces the contract directive and the dispatch attachment in **one commit**. Single-commit invariant is verifiable via `git log --oneline -- <files>` showing no intermediate state.

### Why not gate it with a feature flag

A feature flag for the contract surface would require runtime branching in the prompt itself — every read of the system prompt would carry the flag's risk. A revert is cheaper and easier to audit: `git diff` between PRs shows the exact bytes that fulfilled the contract.

### Source

PR #3440 multi-agent review (architecture-strategist F1, data-integrity-guardian P1+P2, user-impact-reviewer F1+F3+F4+F5). Plan section: `knowledge-base/project/plans/2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md` §Status lines 55-56.

### Placement

**No AGENTS.md rule.** This is a pattern for engineering judgment at PR scope, not a per-turn invariant. The current `hr-weigh-every-decision-against-target-user-impact` and `single-user incident` threshold already create the pressure that surfaces this pattern when needed. Learning file is the right home.

---

## Pattern 2 — Fixture `sourceUrl` as a Legal Written Record

### What

`cq-test-fixtures-synthesized-only` scopes its enforcement to committed binaries (golden files, `__goldens__/**`, etc.). But fixture **manifests** that reference uncommitted binaries can also create a legal written record when their `sourceUrl` (or equivalent provenance field) points to copyrighted material. The committed JSON/YAML file is the artifact; the binary being `.gitignore`d does not erase the record.

### When this applies

- Fixture manifest committed to repo (JSON/YAML/TOML descriptors).
- Manifest contains a `source` / `sourceUrl` / `provider` / `vendor` field.
- That field points to copyrighted content (publisher purchases, paid courses, private corpora).
- Even if the binary is `.gitignore`d, the manifest is searchable by anyone with repo access — including auditors and litigation discovery.

### How to mitigate

- Generate the fixture programmatically when possible (lorem-ipsum + structural metadata). Synthesizer scripts go in `scripts/spike/` alongside the probe scripts.
- For fixtures that must be realistic, use public-domain sources (pre-1929 US, CC0, government documents) and record the canonical archive URL in `sourceUrl`.
- Never paste an example `sourceUrl` pointing at a copyrighted source even as a hint — the example becomes the path of least resistance for the next operator.

### Source

CLO refresh assessment on the S2 fixture manifest in this session. Manifest at `apps/web-platform/scripts/spike/pdf-outline-fixtures.json` shipped with example `sourceUrl: "TODO: operator records source URL (e.g., a Manning/O'Reilly purchase ...)"` — even though the binary is `.gitignore`d, the manifest's example sourceUrl pointed at copyrighted material.

### Placement

**No AGENTS.md rule.** Refinement of an existing rule (`cq-test-fixtures-synthesized-only`). The rule already covers committed fixtures; this pattern is a one-line extension to its full-body description in `.github/workflows/secret-scan.yml` comments or the rule's linked learning. Tagged here so it surfaces in future fixture-manifest reviews.

---

## Pattern 3 — Leader Refresh Pattern for In-Flight Features

### What

When a brainstorm is invoked on a feature that **already has a plan** with domain-leader carry-forward sign-offs, the brainstorm skill's Phase 0.5 should offer two choices:

- **Carry-forward only** — reuse the plan's existing CPO/CLO/CTO sign-offs verbatim. user-impact-reviewer at PR review remains the load-bearing gate.
- **Focused refresh** — spawn leaders with prompts scoped to: (a) does the User-Brand Impact still hold given the new scope decision, (b) any code drift on main since the plan, (c) the specific delta this brainstorm introduces.

### When this applies

- A plan with `brand_survival_threshold` and explicit `## Domain Review (carry-forward)` sections exists for the feature.
- The current brainstorm is scoping a delivery decision (bundle shape, PR split, deferral) rather than re-designing the feature.
- The new brainstorm session is days-to-weeks after the original.

### What the refresh actually finds

The 2026-05-11 refresh of the 2026-05-07 plan surfaced four real deltas in <60 seconds of agent runtime:

1. **CPO** — cross-document disambiguation gap not covered by AC #5 (single-PDF assumption).
2. **CLO** — fixture `sourceUrl` written-record risk (Pattern 2 above).
3. **CTO** — three underspecified edges in the dispatch spec (mid-stream cap, buffer source, stale-context invalidation).
4. **CPO** — bundle-shape risk: S1 outcome flip mid-review needs re-review trigger, not commit-and-merge.

None of these required re-running the original brainstorm. All four were carry-forward deltas the original plan author didn't have visibility into because the bundle decision was new.

### How to scope the refresh prompts

- Lead with: "FOCUSED REFRESH ASSESSMENT (not a fresh brainstorm)."
- Pin the carry-forward signpost: "You signed off on the plan via X on YYYY-MM-DD."
- Ask 3-4 narrow questions, each tied to a specific plan line range or AC number.
- Cap response at 250-350 words per agent.
- Forbid sub-agent spawning.

### Source

The brainstorm skill's Phase 0.5 today spawns full assessments without distinguishing first-pass from refresh. The 2026-05-11 session demonstrated the refresh shape produces better signal-to-token-cost than a full re-assessment of an in-flight feature.

### Placement — Route to brainstorm skill

**Route-to-Definition target:** `plugins/soleur/skills/brainstorm/SKILL.md` Phase 0.5 (Domain Leader Assessment) — add a sub-step: "If the feature description references an existing plan with carry-forward sign-offs (detected via `gh issue view <N> --json body | grep -i 'brainstorm:.*md'` or by referenced plan path in the feature description), offer the user a choice between carry-forward and focused-refresh modes before spawning leaders." Bounded single-bullet addition. NOT an AGENTS.md rule.

---

## Session Errors

1. **Skipped `cleanup-merged` at session start.** AGENTS.md `wg-at-session-start-run-bash-plugins-soleur` requires `worktree-manager.sh cleanup-merged && git worktree list` at session start. `/soleur:go` Step 1 only runs `pwd` and a worktree-context check; the cleanup gate is invisible to operators entering via `/soleur:go`. **Recovery:** none required (no merged worktrees were lingering). **Prevention:** add cleanup-merged + .mcp.json refresh as a session-start preamble to `/soleur:go` Step 0 (before the worktree-context check).

2. **Skipped `.mcp.json` refresh at bare root.** AGENTS.md `wg-at-session-start-after-cleanup-merged` requires `git show main:.mcp.json > .mcp.json` at the bare root after cleanup-merged. Same root cause as #1 — `/soleur:go` doesn't enforce it. **Recovery:** no-op for this brainstorm (no MCP tools were exercised). **Prevention:** same skill edit as #1.

3. **One `cd .worktrees/...` failure.** Assumed I was at the bare root when `worktree-manager.sh feature` had already moved CWD into the worktree path on the parent shell. Recovered via `pwd` check. Discoverable via clear error — no rule warranted.

## Tags

category: best-practices
module: brainstorm, plan, review
