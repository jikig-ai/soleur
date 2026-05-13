# Tasks: SOL-40 — Redesign C4 Architecture Diagrams

Source plan: `knowledge-base/project/plans/2026-05-13-feat-sol-40-redesign-c4-diagrams-plan.md`

## Phase 0: Amend spec.md

- [ ] 0.1 Edit `knowledge-base/project/specs/feat-sol-40-redesign-c4-model/spec.md`:
  - [ ] 0.1.1 G2: change `L1 ≤ 8` → `L1 ≤ 9`; `L2 ≤ 10` → `L2 ≤ 11`. Add inline note: "Amended 2026-05-13 after plan-time recount; ADR-007 importance keeps doppler distinct at both levels."
  - [ ] 0.1.2 FR1: change `UpdateLayoutConfig($c4ShapeInRow=3, $c4BoundaryInRow=2)` → `UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")`. Annotate the quoting rationale (per `c4-reference.md:77`, unquoted values fail silently).
  - [ ] 0.1.3 FR1: rewrite the conditional-fold prose to: "fold `discord` + `stripe` + `plausible` into a single `thirdparty` external; preserve semantic detail in `## Details` section below the Mermaid block."
  - [ ] 0.1.4 FR2: change `UpdateLayoutConfig` values to quoted strings (`"2"`, `"2"`).
  - [ ] 0.1.5 FR2: extend the fold list beyond `Plugin Resources` to enumerate the four boundary-level folds — Web App (`webapp`), CLI Engine (`engine`), Plugin (`plugin`), Compute & Tunnel (`compute`) — plus the `thirdparty` external fold.
  - [ ] 0.1.6 FR3: change `UpdateLayoutConfig` values to quoted strings (`"1"`, `"1"`).
- [ ] 0.2 `git commit -m "spec: amend node budgets and UpdateLayoutConfig quoting for SOL-40"`

## Phase 1: Restructure L1 (`system-context.md`)

- [ ] 1.1 Replace the existing `System_Ext(discord, ...)` + `System_Ext(stripe, ...)` + `System_Ext(plausible, ...)` triplet with a single `System_Ext(thirdparty, "Third-Party Services", "Discord + Stripe + Plausible")`.
- [ ] 1.2 Replace `Rel(webapp, stripe, "Checkout and billing", "HTTPS")` + `Rel(stripe, webapp, "Payment webhooks", "HTTPS")` + `Rel(webapp, plausible, "Page view events", "JS snippet")` with single `BiRel(webapp, thirdparty, "Checkout / webhooks / page events", "HTTPS")`.
- [ ] 1.3 Replace `Rel(engine, discord, "Notifications", "Webhook")` with `Rel(engine, thirdparty, "Notifications", "Webhook")`.
- [ ] 1.4 Reorder declaration top-to-bottom: Person → Enterprise_Boundary block → `cloudflare` → `doppler` → `anthropic` → `github` → `thirdparty`.
- [ ] 1.5 Add `UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")` directly after the `title` line in the Mermaid block.
- [ ] 1.6 Append `## Details` section below the Mermaid block listing original aliases `discord`, `stripe`, `plausible` with role descriptions (template in plan Phase 1).
- [ ] 1.7 Update first-line stamp: `Generated: 2026-05-13 (visual redesign per SOL-40, was 2026-03-27)`.
- [ ] 1.8 Commit + push: `git commit -m "diagrams: restructure L1 system-context for Mermaid layout ceiling"` then `git push`.
- [ ] 1.9 **Visual gate:** open `https://github.com/jikig-ai/soleur/pull/3713/files`, locate the new `system-context.md` render, confirm 9 visible nodes with no crossing arrows and no label collisions at desktop viewport (≥1200 px, 100% zoom). If pass, advance to Phase 2. If fail, hand-tweak boundary order / `UpdateLayoutConfig` values until pass.

## Phase 2: Restructure L2 (`container.md`)

- [ ] 2.1 Inside `Container_Boundary(web, ...)` collapse `dashboard` + `api` + `auth` into a single `Container(webapp, "Web Application", "Next.js PWA", "Dashboard UI + API routes + Supabase Auth")`. Delete the now-unused boundary or rename to enclose just `webapp`.
- [ ] 2.2 Inside `Container_Boundary(cli, ...)` collapse `claude` + `skillloader` + `hooks` into a single `Container(engine, "Cloud CLI Engine", "Claude Code", "Agent runtime + plugin discovery + hook engine")`.
- [ ] 2.3 Inside `Container_Boundary(plugin, ...)` collapse `skills` + `agents` + `kb` into a single `Container(plugin, "Soleur Plugin", "Markdown", "Skills + Agents + Knowledge Base — see L3")`.
- [ ] 2.4 Inside `Container_Boundary(infra, ...)` collapse `tunnel` + `hetzner` into a single `Container(compute, "Compute & Tunnel", "Hetzner Cloud + Cloudflare Tunnel", "Docker containers behind zero-trust tunnel")`. Keep `ContainerDb(supabase, ...)` separate.
- [ ] 2.5 Externals: replace `System_Ext(discord)` + `System_Ext(stripe)` + `System_Ext(plausible)` with single `System_Ext(thirdparty, ...)` (matches Phase 1).
- [ ] 2.6 Rewrite the `Rel(...)` block: drop the internal `dashboard→api→auth` chain (covered by `webapp` fold); change `Rel(api, claude, ...)` → `Rel(webapp, engine, "Spawns agent sessions", "WebSocket")`; collapse the four `claude→skillloader→skills/agents` + `hooks→claude` edges into `Rel(engine, plugin, "Loads + guards", "File I/O + event hook")`; bundle the three externals into `thirdparty`.
- [ ] 2.7 Reorder boundaries top-to-bottom: Person → Web App → CLI Engine → Plugin → Infrastructure (supabase + compute) → externals.
- [ ] 2.8 Add `UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="2")` after the `title` line.
- [ ] 2.9 Append `## Details` section per plan Phase 2 template (preserves original aliases `dashboard`, `api`, `auth`, `claude`, `skillloader`, `hooks`, `skills`, `agents`, `kb`, `tunnel`, `hetzner`).
- [ ] 2.10 Update first-line stamp.
- [ ] 2.11 Commit + push: `git commit -m "diagrams: restructure L2 container for Mermaid layout ceiling"` then `git push`.
- [ ] 2.12 **Visual gate:** confirm ≤ 11 visible nodes, no crossing arrows, no label collisions, boundaries visually contain their containers. If pass, advance. If fail, hand-tweak.

## Phase 3: Restructure L3 (`component-plugin.md`)

- [ ] 3.1 Inside `Container_Boundary(plugin, ...)` collapse `Component(go)` + `Component(sync)` + `Component(help)` into `Component(entry, "Entry-Point Commands", "Markdown", "go, sync, help")`.
- [ ] 3.2 Collapse the eight workflow-skill components (`brainstorm`, `plan`, `work`, `review`, `compound`, `ship`, `oneshot`, `architecture`) into `Component(workflows, "Workflow Skills", "Markdown", "8 skills — see Details")`.
- [ ] 3.3 Collapse the four leader/reviewer components (`cto`, `cmo`, `cpo`, `archstrat`) into `Component(leaders, "Domain Leaders & Reviewers", "Markdown", "4 visible; see Details")`.
- [ ] 3.4 Keep `Container(claude)`, `Container(hooks)`, `ContainerDb(kb)` as external context outside the boundary.
- [ ] 3.5 Rewrite the `Rel(...)` block:
  - [ ] 3.5.1 Drop all `Rel(go|sync|help, *)` and `Rel(oneshot, plan|work|review|compound|ship)` — orchestration is documented in `## Details`.
  - [ ] 3.5.2 Collapse `Rel(brainstorm|plan|review, cto|cmo|cpo|archstrat)` into single `Rel(workflows, leaders, "Phase 0.5 / 2.5 / review assessments", "Task spawn")`.
  - [ ] 3.5.3 Collapse `Rel(cto|archstrat, architecture)` into single `Rel(leaders, workflows, "Recommend ADR / coverage check", "Task spawn")`.
  - [ ] 3.5.4 Add: `Rel(claude, entry, "User invokes /soleur:<cmd>")`, `Rel(hooks, claude, "Guards tool calls")`, `Rel(workflows, kb, "Reads + writes")`, `Rel(leaders, kb, "Reads")`.
  - [ ] 3.5.5 Final Rel count: 6.
- [ ] 3.6 Reorder declaration: external `claude` + `hooks` at top → `Container_Boundary(plugin)` containing `entry` → `workflows` → `leaders` → external `kb` at bottom.
- [ ] 3.7 Add `UpdateLayoutConfig($c4ShapeInRow="1", $c4BoundaryInRow="1")` after the `title` line.
- [ ] 3.8 Append `## Details` section per plan Phase 3 template — preserve original aliases `go`, `sync`, `help`, `brainstorm`, `plan`, `work`, `review`, `compound`, `ship`, `oneshot`, `architecture`, `cto`, `cmo`, `cpo`, `archstrat`; include explicit mention that `clo`, `coo`, `cfo`, `cro`, `cco` exist but are folded for visual budget (link to #3714).
- [ ] 3.9 Update first-line stamp.
- [ ] 3.10 Commit + push: `git commit -m "diagrams: restructure L3 component-plugin for Mermaid layout ceiling"` then `git push`.
- [ ] 3.11 **Visual gate:** confirm 6 visible nodes, no crossing arrows, no label collisions. If pass, advance to Phase 4 (finalize PR). **If fail and escalation sequence (drop low-signal edge, reverse declaration order) does not resolve within 30 minutes:**
  - [ ] 3.11.1 Open delta-issue on #3718 with L3 evidence (screenshot of overlap).
  - [ ] 3.11.2 Prepend a one-line known-limitation note to `component-plugin.md` directly under the title.
  - [ ] 3.11.3 Mark AC3 partially-met in PR body; link the delta-issue.
  - [ ] 3.11.4 Commit + push; advance to Phase 4.

## Phase 4: Finalize PR

- [ ] 4.1 Re-run the cross-reference verification grep (AC4); confirm 4 / 12 / 1 counts unchanged. Investigate any drift.
- [ ] 4.2 Capture rendered Mermaid screenshots from the PR diff view (one per diagram, AFTER state). Linear SOL-40 already holds the BEFORE state.
- [ ] 4.3 Update PR #3713 body's `## Test plan` checklist with AC1 / AC2 / AC3 / AC4 status, attach Before/After screenshots.
- [ ] 4.4 Mark PR ready for review: `gh pr ready 3713`.
