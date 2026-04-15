# Feature: Collapsible Navs + Recurring UX-Review Agent Loop

## Problem Statement

The web-platform has three fixed-width sidebars (main dashboard nav, Knowledge Base file tree, Team Settings) that consume 200–256px of horizontal space permanently, reducing reading/working width for all users — especially on ~1280px laptops. More systemically, some Soleur users (solo founders without a designer, the Phase 4 ICP) cannot reliably spot UX gaps on their own. Current tooling does not fill this gap: `ux-design-lead` produces Pencil wireframes but has no capability to audit existing HTML (documented in `2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md`).

## Goals

- Three sidebars collapse to an icon rail (or hide entirely) with state persisted per user in `localStorage`.
- A recurring `soleur:ux-audit` skill audits the live web-platform UI on UI-path PR merges (plus a monthly cron safety net) and files at most 5 GitHub issues per run, capped at 20 open `ux-audit` issues globally.
- Collapsible-navs appears in the first audit run's top-5 findings — used as the calibration signal that the loop is trustworthy.
- Agent-authored issues are publicly visible (`agent:ux-design-lead`, `ux-audit`, `domain/product` labels) and default to the `Post-MVP / Later` milestone until a human promotes them.

## Non-Goals

- No new UI primitive library (no shadcn/Radix migration). Build a minimal local `<CollapsibleSidebar>` primitive.
- No resize handles, drag-to-resize, or per-width user preference — collapsed/expanded is a binary state.
- No embedding-similarity dedup — hash-based dedup only, scoped to `{route}|{element-selector}|{issue-category}`.
- No auto-fix of agent-filed issues. Human founder decides what to work on.
- No bespoke "UX review log" page on the marketing site — link to the GitHub issue-tracker query instead.
- No breaking change to the existing mobile drawer on the main nav.

## Functional Requirements

### FR1: Collapsible main app nav (dashboard shell)

Primary users on desktop can toggle the main nav between expanded (`md:w-56`) and collapsed (icon-rail, e.g. `md:w-14`) states. State persists across reloads via `localStorage` under a stable key. Mobile drawer behavior unchanged.

### FR2: Collapsible Knowledge Base file-tree sidebar

On `/dashboard/kb/**`, users can toggle the KB sidebar between expanded and collapsed. Collapsed state hides the tree entirely (not just an icon rail, since file names are the primary content). A persistent rehydrate-trigger handle remains visible. Mobile class-swap behavior extended to include a drawer pattern.

### FR3: Collapsible Team Settings sidebar

On `/dashboard/settings/**`, users can toggle the settings sidebar the same way. Mobile bottom tab bar unchanged.

### FR4: Keyboard shortcut

`Cmd/Ctrl+B` toggles the contextually active sidebar. A minimal global keydown listener introduces the shortcut framework (no existing hotkey system).

### FR5: `soleur:ux-audit` skill

Given a route list and a bot-authenticated browser session, the skill navigates each route (authenticated + logged-out surfaces), captures screenshots, passes them to the `ux-design-lead` agent (in a new "audit screenshots → findings" mode), deduplicates against existing open `ux-audit` issues, and creates at most 5 new issues per run. Issues include: title, route, severity, finding category, one or more screenshots (attached to issue body), and a hidden HTML comment containing the dedup hash.

### FR6: Scheduled workflow for `soleur:ux-audit`

A GitHub Actions workflow runs the skill on: (a) push to main when paths include `apps/web-platform/app/**` or `apps/web-platform/components/**`; (b) monthly cron `0 9 1 * *`. Workflow uses the `soleur:schedule` skill template (per `2026-02-27-schedule-skill-template-gaps-first-consumer.md`) with `--headless` support, `--max-turns`, label pre-creation, `id-token: write`, and `--allowedTools`. On failure, `.github/actions/notify-ops-email` sends <ops@jikigai.com>.

### FR7: Dedup and governance

Before filing an issue, the skill (1) queries `gh issue list --label ux-audit --state all --search "<route>"` and (2) checks the candidate's `sha256({route}|{selector}|{category})` hash against hashes in existing issue bodies. If the global open-`ux-audit`-issue count is ≥ 20, the skill refuses to file and emits a warning. `ux-audit`-labeled issues are excluded from the auto-fix and auto-triage workflows by label filter.

### FR8: Bot account + fixtures

A dedicated `ux-audit-bot@jikigai.com` Supabase account is provisioned, seeded with representative KB entries, team members, and uploads. Credentials live in Doppler `prd` config (`UX_AUDIT_BOT_EMAIL`, `UX_AUDIT_BOT_PASSWORD`). Logged-out routes (landing, signup, pricing) are audited without auth.

### FR9: Public marketing-site link

The marketing site surfaces a lightweight "Built by agents, in public" link pointing to the GitHub issue-tracker query for `label:agent:ux-design-lead`. No bespoke page — link only.

### FR10: Expense ledger entry

`knowledge-base/operations/expenses.md` gains an "Automated Claude runs — ux-audit" line with estimated ~$15/month (≤3 runs × ~$5/run).

## Technical Requirements

### TR1: Collapsible primitive

Introduce `apps/web-platform/components/ui/collapsible-sidebar.tsx` (new) exporting a thin wrapper component driven by a `useSidebarState(key: string)` hook. The hook uses `useSyncExternalStore` for SSR-safe `localStorage` access (matches existing `PaymentWarningBanner` pattern in `apps/web-platform/app/(dashboard)/layout.tsx:9–49`). Parent layouts compose this primitive; no grid, no resize handle.

### TR2: State persistence keys

Three stable `localStorage` keys: `ui.sidebar.dashboard`, `ui.sidebar.kb`, `ui.sidebar.settings`. Values are `"expanded" | "collapsed"`. Default on first load: `expanded`. Tests must cover SSR-safe hydration (no flash on first paint).

### TR3: Keyboard shortcut handling

Global keydown listener in the dashboard shell (`app/(dashboard)/layout.tsx`). Contextually routes `Cmd/Ctrl+B` to the active sidebar based on pathname. Input-field focus suppresses the shortcut.

### TR4: Skill architecture (competitive-intelligence split)

`soleur:ux-audit` lives at `plugins/soleur/skills/ux-audit/SKILL.md`. Skill owns: route enumeration, Playwright navigation, screenshot capture, dedup query, `gh issue create` orchestration, `--headless` mode. The `ux-design-lead` agent gets a new "UX Audit" section wired in (the skeleton already exists per CTO research). Agent owns: vision analysis, finding categorization, severity scoring, finding writeup.

### TR5: Route manifest

A new `apps/web-platform/src/routes.manifest.ts` enumerates routes with `{ path, authRequired, fixtureDependencies }`. Consumed by `soleur:ux-audit` for route enumeration and by future QA skills (CTO capability gap). Scope decision (in-feature vs deferred) made during `soleur:plan`.

### TR6: Playwright in CI

Reuse `microsoft/playwright-github-action` already in use. Absolute paths passed to Playwright MCP per `hr-mcp-tools-playwright-etc-resolve-paths`. `--isolated` mode retained per `cq-playwright-mcp-uses-isolated-mode-mcp`. `browser_close` called at end per `cq-after-completing-a-playwright-task-call`.

### TR7: Issue-filing injection safety

Per `2026-04-13-codeql-alert-triage-and-issue-automation.md`: pass finding data through `env:` variables, never interpolate in `run:` steps. Issue title prefix `ux:` to integrate with existing auto-label workflow. `gh --jq` does NOT accept `--arg`/`--argjson` per `2026-03-03-scheduled-bot-fix-workflow-patterns.md`.

### TR8: Cost + failure-mode tracking

Log Anthropic API usage per run to workflow output. If a run exceeds $15, it logs a WARN and continues (does not abort). Failure mode: email-on-failure via `.github/actions/notify-ops-email`. No Discord per `hr-github-actions-workflow-notifications`.

### TR9: Dedup hash format

`sha256(utf8("{route}|{element-selector}|{issue-category}"))`. Embedded in issue body as `<!-- ux-audit-hash: <hash> -->`. Dedup check parses this tag from existing open issues before creating a new one.

### TR10: Labels + milestone pre-creation

Workflow pre-creates labels `agent:ux-design-lead`, `ux-audit`, `domain/product` if missing (per `2026-02-27-schedule-skill-template-gaps-first-consumer.md` — label pre-creation is auto in `soleur:schedule`). Default milestone `Post-MVP / Later` passed via `--milestone "Post-MVP / Later"` (title, not ID, per `cq-gh-issue-create-milestone-takes-title`).

## Acceptance Criteria

- [ ] All three sidebars collapse + expand via UI control and `Cmd/Ctrl+B`.
- [ ] State persists across page reloads per sidebar independently.
- [ ] No hydration flash on first paint in any of the three shells.
- [ ] `soleur:ux-audit` runs end-to-end against the live UI with bot auth.
- [ ] First scheduled run files ≥ 1 issue.
- [ ] First scheduled run's top-5 findings include a "sidebars consume too much space / no collapse control" issue (calibration check).
- [ ] Dedup prevents the same finding being filed twice across two consecutive runs on an unchanged UI.
- [ ] Global cap: the 21st open `ux-audit` issue is NOT filed; workflow logs a WARN.
- [ ] On workflow failure, <ops@jikigai.com> receives an email.
- [ ] Marketing site shows a "Built by agents, in public" link pointing to the label query.
- [ ] Expense ledger includes the ux-audit line.
