---
title: SOL-40 — Redesign C4 Architecture Diagrams
type: feat
date: 2026-05-13
linear_issue: SOL-40
related_pr: https://github.com/jikig-ai/soleur/pull/3713
brainstorm: knowledge-base/project/brainstorms/2026-05-13-c4-diagram-visual-redesign-brainstorm.md
spec: knowledge-base/project/specs/feat-sol-40-redesign-c4-model/spec.md
worktree: .worktrees/feat-sol-40-redesign-c4-model/
branch: feat-sol-40-redesign-c4-model
deferred_followups: ["#3714", "#3715", "#3716", "#3717", "#3718"]
lane: cross-domain
brand_survival_threshold: none (internal architecture documentation)
requires_cpo_signoff: false
status: ready
---

# SOL-40 — Redesign C4 Architecture Diagrams

## Overview

Restructure the source of three Mermaid C4 diagrams in `knowledge-base/engineering/architecture/diagrams/` so each rendered block lands within Mermaid's auto-layout ceiling. Source format, filenames, and rendering surface stay unchanged. Folded detail moves into a prose `## Details` section per file so semantic content stays grep-able.

Three deeper concerns (content staleness, missing views, hand-author drift) are out of scope and filed as deferred issues #3714 / #3715 / #3716 / #3717 / #3718.

## Problem Statement

The three diagrams render with overlapping arrows, label collisions, and boundary frames that visually do not contain their declared components. L3 Component is functionally illegible at 18 visible nodes. CTO assessment (brainstorm): Mermaid's C4 renderer is the auto-layout ceiling — not a source defect. Source restructure can land each rendered block under the ceiling; renderer swap (deferred #3718) is the alternative if restructure proves insufficient.

## Research Reconciliation — Spec vs. Codebase

Plan-time recount via `grep -cE '^[[:space:]]*(Person|Container|Component|System_Ext|System|SystemDb|ContainerDb)\(' <file>` exposed gaps in the spec's node-count assumption. The spec is amended in this PR to align with reality.

| Diagram | Spec v1 budget | Actual nodes | Spec v2 budget | Folds applied | Final visible |
|---|---|---|---|---|---|
| L1 system-context | ≤ 8 | 11 | **≤ 9** | discord+stripe+plausible → `thirdparty` (saves 2) | **9** |
| L2 container | ≤ 10 | 19 | **≤ 11** | 4 per-boundary collapses + thirdparty external fold (saves 8) | **11** |
| L3 component-plugin | ≤ 8 | 18 | ≤ 8 (unchanged) | entry-points (3→1) + workflow-skills (8→1) + leaders (4→1) (saves 12) | **6** |

L1 keeps `doppler` distinct (ADR-007 architectural significance). L2 keeps `doppler` distinct for the same reason — spec G2 amended to ≤ 11 rather than fold doppler. Spec FR1/FR2 also amended to quote `UpdateLayoutConfig` values (per `c4-reference.md:77` — unquoted values fail silently) and to enumerate the additional L2 folds.

**Verified cross-reference counts** (post-plan-write grep, excluding this plan/spec/brainstorm from the count):

- `system-context.md`: **4 consumers** — `INDEX.md`, 2 plans, 1 spec tasks.md
- `container.md`: **12 consumers** — `INDEX.md`, `nfr-register.md`, `nfr-reference.md`, 6 plans, 1 archived plan, 2 learnings, 1 spec tasks.md, 1 archived spec tasks.md
- `component-plugin.md`: **1 consumer** — `INDEX.md`

Filenames stay stable so no sweep is required. The verification re-runs at AC4.

## User-Brand Impact

- **If this lands broken, the user experiences:** architecture diagrams render with overlap → contributor confusion during onboarding. No live user surface.
- **If this leaks, the user's data is exposed via:** N/A — diagrams describe public architecture already documented in ADRs.
- **Brand-survival threshold:** `none` (internal architecture documentation, no end-user touch point)

Sensitive-path check: diff touches `knowledge-base/engineering/architecture/diagrams/*.md` + `knowledge-base/project/specs/feat-sol-40-redesign-c4-model/spec.md`. Neither matches preflight Check 6 patterns. No scope-out bullet required.

## Domain Review

**Domains relevant:** Engineering, Operations (both carried forward from brainstorm)

### Engineering

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Mermaid C4 is the layout ceiling; source restructure reduces density but cannot fully fix L3. Renderer swap is technically low-risk (zero docs-site coupling) but adds a second toolchain. Diagrams are LLM-hand-authored and will drift from code — tracked as #3717.

### Operations

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Likec4 is the lowest-friction alternative if swap is later adopted. Stay-on-Mermaid is the zero-cost baseline this plan executes. Renderer evaluation captured as #3718.

### Product/UX Gate

Not invoked — Product domain was NONE in brainstorm (no user-facing surfaces, no UI, no copy changes).

## Open Code-Review Overlap

**None.** Queried 75 open `code-review`-labeled issues against the three planned-edit diagram files + the spec. Zero matches.

## Files to Edit

| File | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/diagrams/system-context.md` | L1 restructure + Details section + stamp |
| `knowledge-base/engineering/architecture/diagrams/container.md` | L2 restructure + Details section + stamp |
| `knowledge-base/engineering/architecture/diagrams/component-plugin.md` | L3 restructure + Details section + stamp |
| `knowledge-base/project/specs/feat-sol-40-redesign-c4-model/spec.md` | Amend G2 budgets to ≤9/≤11/≤8; quote UpdateLayoutConfig values; enumerate L2 boundary folds in FR2 |

## Files to Create

None.

## Technical Considerations

- **Architecture impact:** none. No new components, no behavior change.
- **NFR impact:** none. Diagrams are descriptive artifacts.
- **Cross-references preserved:** filenames stable; no consumer-file sweep needed.
- **Mermaid `UpdateLayoutConfig` semantics:** `$c4ShapeInRow="N"` / `$c4BoundaryInRow="M"` — values are **quoted strings** per `c4-reference.md:77`. Unquoted values fail silently (keep defaults).

## Implementation Phases

### Phase 0: Amend spec.md

Update `knowledge-base/project/specs/feat-sol-40-redesign-c4-model/spec.md`:

- G2: `L1 ≤ 8` → `L1 ≤ 9`; `L2 ≤ 10` → `L2 ≤ 11`. Add note: "Amended 2026-05-13 after plan-time recount; ADR-007 importance keeps doppler distinct."
- FR1: change `UpdateLayoutConfig($c4ShapeInRow=3, $c4BoundaryInRow=2)` → `UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")`. Note the quoting rationale inline.
- FR1: replace "if exceeds 8, fold plausible+discord into Analytics & Notifications" with "fold discord+stripe+plausible into single `thirdparty` external for visual budget; preserve semantic detail in `## Details`".
- FR2: change `UpdateLayoutConfig` values to quoted strings (`"2"`, `"2"`).
- FR2: enumerate the four additional boundary-level folds (Web App / CLI Engine / Plugin Resources / Compute & Tunnel) beyond just `Plugin Resources`.
- FR3: change `UpdateLayoutConfig` values to quoted strings (`"1"`, `"1"`).

These amendments make spec and plan agree before Phases 1-3 execute. Commit at end of Phase 0; subsequent phases share the same PR commit chain.

### Phase 1: Restructure L1 — `system-context.md`

**Target:** 9 visible nodes, ≤ 10 Rel edges, top-to-bottom flow.

**Fold map (folds only; everything else stays):**

| Current | Action |
|---|---|
| `System_Ext(discord)` + `System_Ext(stripe)` + `System_Ext(plausible)` | **Fold to one:** `System_Ext(thirdparty, "Third-Party Services", "Discord + Stripe + Plausible")` |

Visible after: founder, webapp, engine, supabase, anthropic, github, cloudflare, doppler, thirdparty = **9**.

**Relation bundling:** combine `Rel(webapp, stripe, ...)` + `Rel(stripe, webapp, ...)` + `Rel(webapp, plausible, ...)` into one `BiRel(webapp, thirdparty, "Checkout / webhooks / page events", "HTTPS")`. Bundle `Rel(engine, discord, ...)` into the same `thirdparty` target.

**Boundary-flow ordering:** Person → Enterprise_Boundary → cloudflare → doppler → anthropic → github → thirdparty.

**Layout:** `UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")`.

**`## Details` section** (alias-preserving, with source paths for #3714's future audit):

```markdown
## Details

**`thirdparty` group contains** (original Mermaid aliases preserved):

- `discord` — Discord — community notifications and release announcements
- `stripe` — Stripe — payment processing and subscription billing (test mode)
- `plausible` — Plausible Analytics — privacy-focused page-view tracking
```

**Stamp:** `Generated: 2026-05-13 (visual redesign per SOL-40, was 2026-03-27)`.

**Visual gate:** push, view `https://github.com/jikig-ai/soleur/pull/3713/files`, confirm no crossing arrows and no label collisions on GitHub's rendered Mermaid view at desktop viewport. If pass, advance.

### Phase 2: Restructure L2 — `container.md`

**Target:** 11 visible nodes, ≤ 12 Rel edges, top-to-bottom flow.

**Fold map (folds only):**

| Boundary | Action |
|---|---|
| Web Application (dashboard + api + auth) | **Fold to 1:** `Container(webapp, "Web Application", "Next.js PWA", "Dashboard UI + API routes + Supabase Auth")` |
| Cloud CLI Engine (claude + skillloader + hooks) | **Fold to 1:** `Container(engine, "Cloud CLI Engine", "Claude Code", "Agent runtime + plugin discovery + hook engine")` |
| Soleur Plugin (skills + agents + kb) | **Fold to 1:** `Container(plugin, "Soleur Plugin", "Markdown", "Skills + Agents + Knowledge Base — see L3")` |
| Infrastructure (tunnel + hetzner) | **Fold to 1:** `Container(compute, "Compute & Tunnel", "Hetzner Cloud + Cloudflare Tunnel", "Docker containers behind zero-trust tunnel")`. Keep `ContainerDb(supabase, ...)` separate. |
| Externals: discord + stripe + plausible | **Fold to 1:** `System_Ext(thirdparty, ...)` (matches Phase 1 fold) |

Visible after: founder, webapp, engine, plugin, supabase, compute, anthropic, github, cloudflare, doppler, thirdparty = **11**.

**Relation bundling:** dashboard→api→auth chain disappears with the fold. `api→claude` becomes `webapp→engine`. `claude→skillloader→skills/agents` + `hooks→claude` collapse to `Rel(engine, plugin, "Loads + guards", "File I/O + event hook")`. Externals bundle into `thirdparty` per Phase 1.

**Boundary-flow ordering:** Person → Web App → CLI Engine → Plugin → Infrastructure (supabase + compute) → externals.

**Layout:** `UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="2")`.

**`## Details`** enumerates per-folded-boundary contents with original aliases:

```markdown
## Details

**`webapp` (Web Application) — folded from L2 source:**

- `dashboard` (React, Next.js) — conversation UI, KB viewer, session management
- `api` (Next.js API) — REST endpoints for auth, sessions, agent control
- `auth` (Supabase Auth) — JWT, OAuth providers, session tokens

**`engine` (Cloud CLI Engine) — folded from L2 source:**

- `claude` (Claude Code) — executes agent workflows
- `skillloader` (Plugin Discovery) — loads skills, agents, commands
- `hooks` (PreToolUse Guards) — enforces syntactic rules, blocks dangerous tool calls

**`plugin` (Soleur Plugin) — see L3 `component-plugin.md` for decomposition:**

- `skills` — workflow skills (brainstorm, plan, work, review, compound, ship, one-shot, …)
- `agents` — domain agents across 8 departments
- `kb` — Markdown + YAML conventions, learnings, ADRs, specs, plans, brainstorms

**`compute` (Compute & Tunnel) — folded from L2 source:**

- `tunnel` (cloudflared) — zero-trust inbound access (ADR-008)
- `hetzner` (Hetzner Cloud) — Docker containers running web app + CLI engine (ADR-006)

**`thirdparty` (Third-Party Services) — see L1 Details** (same fold).
```

**Stamp:** updated per Phase 1 convention.

**Visual gate:** same as Phase 1.

### Phase 3: Restructure L3 — `component-plugin.md`

**Target:** 6 visible nodes, ≤ 8 Rel edges.

**Fold map (folds only):**

| Current | Action |
|---|---|
| `Component(go)` + `Component(sync)` + `Component(help)` | **Fold to 1:** `Component(entry, "Entry-Point Commands", "Markdown", "go, sync, help")` |
| `Component(brainstorm)` + `Component(plan)` + `Component(work)` + `Component(review)` + `Component(compound)` + `Component(ship)` + `Component(oneshot)` + `Component(architecture)` | **Fold to 1:** `Component(workflows, "Workflow Skills", "Markdown", "8 skills — see Details")` |
| `Component(cto)` + `Component(cmo)` + `Component(cpo)` + `Component(archstrat)` | **Fold to 1:** `Component(leaders, "Domain Leaders & Reviewers", "Markdown", "4 visible; see Details")` |

External `claude`, `hooks`, `kb` containers kept as-is. Visible: 3 inside boundary + 3 external = **6**.

**Relation bundling:** all `Rel(go|sync|help, *)` collapse under `entry`. `Rel(oneshot, plan|work|review|compound|ship)` (5 edges) drop — orchestration is documented in `## Details`, not the diagram. `Rel(brainstorm|plan|review, cto|cmo|cpo|archstrat)` (6 edges) collapse to `Rel(workflows, leaders, "Phase 0.5 / 2.5 / review assessments", "Task spawn")`. `Rel(cto|archstrat, architecture)` collapse to `Rel(leaders, workflows, "Recommend ADR / coverage check", "Task spawn")`. `Rel(claude, entry, "User invokes /soleur:<cmd>")`. `Rel(hooks, claude, "Guards tool calls")`. `Rel(workflows, kb, "Reads + writes")`. `Rel(leaders, kb, "Reads")`.

Final Rel count: 6.

**Boundary-flow ordering:** external `claude` + `hooks` at top → `Container_Boundary(plugin)` containing entry → workflows → leaders → `kb` at bottom.

**Layout:** `UpdateLayoutConfig($c4ShapeInRow="1", $c4BoundaryInRow="1")`.

**`## Details`** is the most substantive of the three files — full list with aliases:

```markdown
## Details

**`entry` (Entry-Point Commands)** — `plugins/soleur/commands/`:

- `go` — classifies intent and routes to workflow skills
- `sync` — populates knowledge-base from existing codebase
- `help` — lists all commands, skills, and agents

**`workflows` (Workflow Skills)** — `plugins/soleur/skills/`:

- `brainstorm` — explores requirements with domain leader assessment
- `plan` — creates implementation plans with research and domain review
- `work` — executes plans with incremental commits and test-first
- `review` — multi-agent code review
- `compound` — captures learnings and promotes to constitution
- `ship` — validates artifacts, creates PR, manages merge lifecycle
- `one-shot` — full autonomous pipeline (orchestrates plan → work → review → compound → ship as Steps 1-5)
- `architecture` — ADR lifecycle and C4 diagram generation

**`leaders` (Domain Leaders & Reviewers)** — `plugins/soleur/agents/`:

- `cto` — engineering assessment, architecture decision detection
- `cmo` — marketing assessment, content opportunities
- `cpo` — product strategy, UX flow analysis
- `architecture-strategist` — architectural compliance and ADR coverage check at review time

Other domain leaders exist (`clo`, `coo`, `cfo`, `cro`, `cco`) — folded out for visual budget; tracked in #3714.

**External containers:** `claude` (Agent Runtime), `hooks` (Hook Engine), `kb` (Knowledge Base) — defined at L2.
```

**Stamp:** same convention.

**Visual gate:** push, view on PR. **If L3 still has overlap after the trim:**

1. Drop the `Rel(leaders, workflows, "Recommend ADR / coverage check")` edge (lowest signal — the relationship is captured in Details).
2. Reverse boundary declaration order to place `kb` first and externals last; Mermaid C4 places earlier declarations higher in the layout grid.
3. **Fallback (≥ 30 min hand-tweak):** file a delta-issue on #3718 (renderer evaluation) and prepend a one-line known-limitation note to `component-plugin.md` directly under the title. Mark AC3 partially-met in PR body, ship L1+L2. Drafting the banner takes ~2 minutes if/when it fires; not pre-specified here.

Spec NG4 ("renderer evaluation out of scope") does NOT forbid filing the deferred-issue delta — it forbids running the evaluation in this PR.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — L1 visual gate.** `system-context.md` renders on GitHub PR diff view at desktop viewport with no crossing arrows and no label-on-label or label-on-box collisions; visible node count = 9. `## Details` section enumerates every folded node by its **original Mermaid alias** verbatim. `Generated:` stamp updated.
- [ ] **AC2 — L2 visual gate.** `container.md` same gate; visible node count ≤ 11; `## Details` present with original aliases; stamp updated.
- [ ] **AC3 — L3 visual gate.** `component-plugin.md` same gate; visible node count ≤ 8; `## Details` present with original aliases; stamp updated. **Fallback branch:** if AC3 fails the visual gate after Phase 3's escalation sequence + 30-min cap, AC3 is partially-met IF (a) a delta-issue against #3718 is filed with L3 evidence, (b) a known-limitation note is prepended to `component-plugin.md`, (c) the PR body documents the partial-success.
- [ ] **AC4 — Cross-references intact.** Re-run the verification grep and confirm the same counts as plan-time (4 / 12 / 1). Command (note: three separate `:!` excludes — git pathspec does not support brace expansion):

  ```bash
  git grep -l "system-context\.md" \
    -- ':!knowledge-base/engineering/architecture/diagrams/' \
       ':!knowledge-base/project/brainstorms/2026-05-13-c4-diagram-visual-redesign-brainstorm.md' \
       ':!knowledge-base/project/specs/feat-sol-40-redesign-c4-model/spec.md' \
       ':!knowledge-base/project/plans/2026-05-13-feat-sol-40-redesign-c4-diagrams-plan.md' \
    | sort -u | wc -l   # expect 4
  ```

  Repeat for `container\.md` (expect 12) and `component-plugin\.md` (expect 1). Drift requires investigation before merge.

### Post-merge

None — docs-only change.

## Test Scenarios

- Given the redesigned `system-context.md` on the PR's diff view, when viewed at desktop viewport, then 9 nodes appear with zero crossing arrows and zero label collisions.
- Given the redesigned `container.md` on the PR's diff view, when viewed at desktop viewport, then ≤ 11 nodes appear grouped into 4 boundaries that visually contain their declared containers.
- Given the redesigned `component-plugin.md` on the PR's diff view, when viewed at desktop viewport, then ≤ 8 nodes appear and the Soleur Plugin boundary visibly contains entry, workflows, and leaders.
- Given any of the three files, when scrolled below the Mermaid block, then `## Details` enumerates every folded element with its **original Mermaid alias**.
- Given Phase 3's escalation cap is hit, when the fallback fires, then a delta-issue on #3718 is filed, the known-limitation note is added, and AC3 is marked partially-met in the PR body.

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| L3 still illegible after the fold map | Medium | Phase 3 escalation sequence + 30-min cap + fallback to delta-issue on #3718. |
| Visual gate is subjective | Low | AFTER screenshots in PR body are the tiebreaker; PR diff view at desktop viewport is the source of truth. |

## References

**Internal:** brainstorm, spec, `c4-reference.md`, `architecture` skill, prior decision `2026-03-27-architecture-as-code-brainstorm.md` open question #5 (deferred Structurizr DSL).

**External:** https://c4model.com, https://mermaid.js.org/syntax/c4.html

**Related:** PR #3713 (draft) | Linear SOL-40 | Deferred follow-ups #3714 / #3715 / #3716 / #3717 / #3718

## Sharp Edges

- `UpdateLayoutConfig` values must be **quoted strings** (`"3"`, not `3`) per `c4-reference.md:77`. Unquoted values fail silently — Mermaid keeps defaults.
- `BiRel()` does not always reduce arrow count — renderer may emit two arrows depending on Mermaid version. If the visual gate shows two arrows where one was expected, fall back to separate `Rel()` calls.
- Git pathspec exclude (`:!path`) does NOT support brace expansion. AC4's verification grep lists each excluded path on its own `:!` line. Compact forms like `':!a/{x,y}'` are silently ineffective — both `x` and `y` leak back into results.
