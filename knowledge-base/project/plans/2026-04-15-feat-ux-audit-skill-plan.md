---
title: "feat: soleur:ux-audit — recurring UX-review agent loop"
type: feat
date: 2026-04-15
issue: 2341
blocks: [2342]
related: [2343, 2344]
branch: collapsible-navs-ux-review
worktree: .worktrees/collapsible-navs-ux-review/
pr: 2346
spec: knowledge-base/project/specs/feat-collapsible-navs-ux-review/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-04-15-collapsible-navs-ux-review-brainstorm.md
---

# feat: soleur:ux-audit — recurring UX-review agent loop

## Overview

Build a recurring agent loop that audits the live web-platform UI as a logged-in bot user (and anonymous visitor), captures screenshots, delegates analysis to `ux-design-lead` in a new "audit" mode, deduplicates against prior findings, and files ≤ 5 GitHub issues per run (global cap 20 open). Triggered event-driven on PR merges to main that touch `apps/web-platform/app/**` or `apps/web-platform/components/**`, plus a monthly cron `0 9 1 * *` safety net.

This plan owns issue #2341 (critical path). #2342 (collapsible navs) is blocked on #2341's first calibrated run. #2343 (shared route manifest) and #2344 (exclude agent-authored from auto-fix) are scoped as deferred/inline respectively — decided below.

## Problem Statement

A documented coverage gap exists in the agent roster: `ux-design-lead` produces `.pen` wireframes but has no capability for auditing live HTML (`knowledge-base/project/learnings/2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md`). The Phase 4 ICP — solo founders without a designer — cannot reliably spot UX gaps themselves, and `/soleur:qa` is merge-gated (only runs against diffs). There is no standing capability that watches the live UI and surfaces decay.

Building this before the collapsible-nav implementation (#2342) calibrates the loop: if the agent's first run does not surface the nav-real-estate problem as a top-5 finding, the rubric is miscalibrated and we fix that before trusting it on less-obvious UX issues. The collapsible-nav artifact also becomes the concrete first example for the CMO blog post ("We gave our UX reviewer a cron job") — `B → A` is the sequence that gives us a falsifiable proof point.

## Proposed Solution

**Architecture:** A new `plugins/soleur/skills/ux-audit/` skill (thin orchestrator) delegates to an existing `plugins/soleur/agents/product/design/ux-design-lead.md` agent with a new "audit mode" branch. This matches the `competitive-analysis` skill / `competitive-intelligence` agent split already established (`plugins/soleur/skills/competitive-analysis/SKILL.md`).

**Execution surface:** A new `.github/workflows/scheduled-ux-audit.yml` workflow, generated via `soleur:schedule`, runs the skill on the event-driven trigger described above. Bot creds live in Doppler `prd_scheduled` (matches `scheduled-community-monitor.yml:56` convention; service token `DOPPLER_TOKEN_SCHEDULED`).

**Audit flow per run:**

1. Skill enumerates routes from `plugins/soleur/skills/ux-audit/references/route-list.yaml`.
2. For each route, a Playwright MCP session authenticates as `ux-audit-bot@jikigai.com` (or visits anonymously for logged-out routes), screenshots the page at `1440×900` (see TR7), writes PNGs to `${{ github.workspace }}/tmp/ux-audit/<route-slug>.png`.
3. Skill invokes `ux-design-lead` in audit mode via Task tool, passing screenshot absolute paths and the route metadata. The agent returns a JSON array of structured findings: `{route, selector, category, severity, title, description, fix_hint}`.
4. Skill deduplicates findings against existing issues via a single-layer hash search (see TR3).
5. Skill caps findings to top-5 by severity, refuses to file if global open-`ux-audit` cap (`CAP_OPEN_ISSUES = 20`) reached.
6. Skill files each surviving finding as a GitHub issue via `gh issue create`, attaching the screenshot to the issue body and embedding a dedup hash in an HTML comment.

**Single dry-run mechanism:** A `workflow_dispatch.inputs.dry_run` (default `true`) sets `UX_AUDIT_DRY_RUN` env; the skill reads the env var and either writes findings to stdout OR files issues. One knob, one plumbing path. Cron/push invocations default `UX_AUDIT_DRY_RUN=false` once calibration passes (Phase 3 Calibration sub-section).

**Governance:** `ux-audit`-labeled issues are excluded from auto-fix (`scheduled-bug-fixer.yml`) and auto-triage (`scheduled-daily-triage.yml`) via one-line jq filter additions in those workflows. Default milestone `Post-MVP / Later`, labels `ux-audit`, `agent:ux-design-lead`, `domain/product`.

## Technical Approach

### Architecture

```text
┌─────────────────────────────────────────────────────────────────────┐
│  .github/workflows/scheduled-ux-audit.yml                           │
│  Triggers: push (paths + branches: [main]) + cron + dispatch        │
│  Steps: checkout → Doppler load → Playwright install (pinned) →    │
│         run skill → notify-ops-email on failure                     │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ claude-code-action
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Skill: plugins/soleur/skills/ux-audit/SKILL.md                     │
│  Phases (reads UX_AUDIT_DRY_RUN env):                               │
│    1. Load route list + bot creds                                   │
│    2. Global-cap check (count open ux-audit issues)                 │
│    3. For each route:                                               │
│       - Playwright auth + navigate + screenshot (absolute paths)    │
│       - Task(ux-design-lead, mode=audit, screenshots=[...])         │
│       - Receive structured findings JSON                            │
│    4. Dedup (single-layer hash search)                              │
│    5. Severity-rank, cap at 5                                       │
│    6. If not dry-run: gh issue create with attachment + hash comment│
│       If dry-run: write findings JSON to stdout + workflow artifact │
│    7. browser_close                                                 │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ Task tool (screenshots mode)
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Agent: plugins/soleur/agents/product/design/ux-design-lead.md      │
│  New section: "## UX Audit (Screenshots)"                           │
│  Mode switch: if input is screenshot paths → audit mode (skip Pencil│
│  workflow). 5-category rubric (see TR2).                            │
│  Output: JSON array of findings.                                    │
└─────────────────────────────────────────────────────────────────────┘
```

### Implementation Phases

#### Phase 1: Foundation (Supabase bot + Doppler + fixture)

**Goal:** Bot account can log in and render authenticated routes with representative content.

**Deliverables:**

- [x] Create Supabase auth user `ux-audit-bot@jikigai.com` via Supabase Admin API (not Terraform — application-data-plane user). Password: `openssl rand -base64 32`, stored in Doppler `prd_scheduled` as `UX_AUDIT_BOT_PASSWORD`. **Done:** user id `7dff92fd-3460-4ccf-bfa6-5be6f631cdb1`, `email_confirm: true`, signin verified via `/auth/v1/token?grant_type=password`.
- [x] Add `UX_AUDIT_BOT_EMAIL` and `UX_AUDIT_BOT_PASSWORD` to Doppler `prd_scheduled`.
- [x] Verify `DOPPLER_TOKEN_SCHEDULED` service token reads the new secrets — GH Actions secret exists (created 2026-03-25).
- [ ] Write `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` with subcommands `seed` and `reset`. **Scope: DB-only v1.** Content spec:
  - **KB tree: DEFERRED to #2351.** KB files live in GitHub under `<workspace>/knowledge-base/`, not Supabase Storage. Seeding a 6-file tree requires workspace repo provisioning + GitHub App install — out of scope for Phase 1. `/dashboard/kb` renders empty under bot auth. Calibration target (#2342 collapsible-nav) is `/dashboard` sidebar, visible with or without KB content.
  - Team: 2 synthetic seed members (`teammate-1@example.com`, `teammate-2@example.com` — `example.com` is IANA-reserved, no real mailbox)
  - Chat: 2 prior conversations with ≥ 3 messages each (so `/dashboard/chat` has non-empty state)
  - Services: 1 mocked connected integration (env-var flag `UX_AUDIT_FIXTURE_CLOUDFLARE=1`; no real token wired)
  - Billing: `users.subscription_status='active'` via direct DB update with synthetic `stripe_customer_id`/`stripe_subscription_id` placeholders. Real Stripe test-mode customer deferred with #2351.
  - **Fixture invariants:** no real email addresses (except bot's own `ux-audit-bot@jikigai.com`), no real API keys, no real payment info, no strings matching Stripe/GitHub/AWS secret-detection patterns (per `2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md`).
  - **Onboarding completeness:** the seed script MUST complete onboarding flow for the bot (accept T&Cs at current version, skip connect-repo if optional, confirm billing) so `middleware.ts` auth + T&C + billing guards all pass. Route `/dashboard` must return 200, not redirect.
- [ ] Document fixture spec inline in `plugins/soleur/skills/ux-audit/SKILL.md` (reviewer-requested consolidation — no separate `bot-fixture-spec.md`).

**Success criteria:** `doppler run -c prd_scheduled -- node plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts seed` completes idempotently; bot signs in via Supabase JS; `/dashboard` returns 200 under bot auth.

**Effort:** 0.5–1 day.

#### Phase 2: Skill + audit-mode agent extension

**Goal:** `UX_AUDIT_DRY_RUN=true` local invocation of the skill against `/dashboard` prints a JSON array of findings, and a golden-set of 3 past UX issues is reliably surfaced by the agent.

**Deliverables:**

- [ ] Create `plugins/soleur/skills/ux-audit/SKILL.md` with third-person description ≤ 200 chars, phased workflow (load routes → per-route capture → delegate → dedup → cap → file-or-stdout), inline rubric, inline fixture spec, linked `route-list.yaml`. Compliance per `plugins/soleur/AGENTS.md` Skill Compliance Checklist: `name:` matches directory, third-person description, token budget under 1800 words cumulative, all references linked via `[filename](./references/filename)` syntax.
- [ ] Create `plugins/soleur/skills/ux-audit/references/route-list.yaml` — hardcoded list (~15–20 routes) scoped to THIS skill; shared manifest deferred to #2343 (see TR5). Schema:

  ```yaml
  routes:
    - path: /
      auth: anonymous
      viewport: {w: 1440, h: 900}
    - path: /login
      auth: anonymous
      viewport: {w: 1440, h: 900}
    - path: /dashboard
      auth: bot
      fixture_prereqs: [onboarding_complete, tcs_accepted, billing_active]
      viewport: {w: 1440, h: 900}
    - path: /dashboard/kb
      auth: bot
      fixture_prereqs: [onboarding_complete, tcs_accepted, billing_active, kb_tree_6_files]
      viewport: {w: 1440, h: 900}
    # ... etc
  ```

  `fixture_prereqs` makes the route list self-documenting: if a prereq isn't met at run-time, the route is skipped with a logged reason (not aborted).

- [ ] Add `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts` (or fold into `bot-fixture.ts` with `signin` subcommand — implementer's choice): logs in via `@supabase/supabase-js` `signInWithPassword`, writes storage state to `${workspace}/tmp/ux-audit/storage-state.json` (absolute path). Pattern source: `apps/web-platform/e2e/global-setup.ts`.
- [ ] Edit `plugins/soleur/agents/product/design/ux-design-lead.md`:
  - Add a mode branch at top of `## Workflow`: documentation instructing the agent to route on input type. If invocation provides `screenshots: [...]` and `mode: audit`, skip Pencil Steps 1–3 and enter "## UX Audit (Screenshots)" section. (Note: this is prompt engineering, not control flow — the agent infers routing from the prompt structure.)
  - Add new `## UX Audit (Screenshots)` section AFTER existing `## UX Audit (Existing HTML Pages)` (L54–62). Contents:
    - 5-category rubric (dropped the "error/empty/loading states" 6th category — not reliably observable in happy-path static captures):
      1. Screen real estate (fixed-width elements, wasted horizontal space on 1440×900)
      2. Information architecture (nav ordering, redundant entries, page necessity)
      3. Cross-section visual consistency (buttons, spacing, typography)
      4. Responsive behavior (drawer/collapse patterns, mobile parity)
      5. 30-second first-user comprehension (what is this page?)
    - Output contract: JSON array, one object per finding: `{route, selector, category, severity: "critical"|"high"|"medium"|"low", title, description, fix_hint, screenshot_ref}`. No prose outside the JSON.
  - **Prompt-engineering budget:** allot 1 additional engineer-day for rubric-prompt iteration. The agent mode is load-bearing and is where Phase 3 calibration most likely fails.
  - Do NOT modify `description:` frontmatter (token-budget gate per `plugins/soleur/AGENTS.md` "Agent Compliance Checklist"). Disambiguation text already present.
- [ ] Build a golden-set test: 3 historical UX issues that `ux-design-lead` audit-mode MUST surface from their relevant screenshots. Issues picked from the repo's issue tracker (`gh issue list --label ux --state closed --limit 20`) with a clear before-screenshot in the issue body. Rubric-prompt is considered ready when all 3 appear in top-5 of their respective runs. This test replaces the "3-iteration budget" from the first plan draft — deterministic, not ceremonial.
- [ ] Implement skill's global-cap check in SKILL.md workflow:

  ```bash
  OPEN_COUNT=$(gh issue list --label ux-audit --state open --json number --jq 'length')
  if [ "$OPEN_COUNT" -ge 20 ]; then
    echo "::warning::Global ux-audit cap reached ($OPEN_COUNT open). Refusing to file new issues."
    exit 0
  fi
  ```

  Constant name: `CAP_OPEN_ISSUES = 20` (inline in SKILL.md as a named value, not a config knob).

- [ ] Implement dedup (single-layer, see TR3).
- [ ] Implement env-var dry-run: if `UX_AUDIT_DRY_RUN=true`, write findings JSON to stdout; else `gh issue create`. Single plumbing.
- [ ] Implement `--route <path>` local dev affordance (not gated in acceptance criteria) — keeps local iteration fast during prompt tuning.

**Success criteria:** Local run `UX_AUDIT_DRY_RUN=true doppler run -c prd_scheduled -- claude code --skill soleur:ux-audit --route /dashboard` emits a well-formed JSON findings array; the 3 golden-set issues appear in top-5 on their test runs.

**Effort:** 2–3 days (includes 1 day prompt-engineering budget).

#### Phase 3: Workflow + governance + calibration

**Goal:** Scheduled workflow runs end-to-end on push/cron, dedup works across consecutive runs, auto-fix and auto-triage exclude `ux-audit` issues, first dry-run passes calibration.

**Deliverables:**

- [ ] Run `soleur:schedule` to scaffold `.github/workflows/scheduled-ux-audit.yml`. Template source: `.github/workflows/scheduled-competitive-analysis.yml`.
- [ ] Edit generated workflow:
  - Triggers:

    ```yaml
    on:
      push:
        branches: [main]
        paths: [apps/web-platform/app/**, apps/web-platform/components/**]
      schedule: [{cron: '0 9 1 * *'}]
      workflow_dispatch:
        inputs:
          dry_run:
            type: boolean
            default: true
    ```

    `branches: [main]` is critical — without it, every feature-branch push triggers the audit against prod (Kieran review finding #9).

  - `timeout-minutes: 45` at job level.
  - Doppler load gated on `secrets.DOPPLER_TOKEN_SCHEDULED` (mirror `scheduled-community-monitor.yml:49–60`).
  - Playwright setup with pinned version: read the exact version from `apps/web-platform/package.json` `devDependencies.playwright` and pass to `npx playwright@<version> install chromium --with-deps` (per `2026-03-20-playwright-shared-cache-version-coupling.md`).
  - Env to skill step: `UX_AUDIT_DRY_RUN: ${{ inputs.dry_run || 'false' }}` (push/cron defaults to `false` once calibration passes; dispatch defaults `true`).
  - `claude_args: '--model ... --max-turns 60 --allowedTools Bash,Read,Write,Edit,Glob,Grep,Task,mcp__playwright__*'`.
  - All agent-generated finding data passes through `env:` vars before `gh issue create` (per `hr-in-github-actions-run-blocks-never-use` and `2026-04-13-codeql-alert-triage-and-issue-automation.md`).
  - `if: failure()` step invoking `./.github/actions/notify-ops-email` with constructed HTML `body` input.
  - Labels pre-creation step: `gh label create <name> --color <hex> --description "<desc>" 2>/dev/null || true` × 3 labels. Pattern consistent with `scheduled-bug-fixer.yml:52–70` (reviewer Kieran flagged `|| true` masking; we keep it for convention consistency — tradeoff acknowledged).
- [ ] Edit `.github/workflows/scheduled-daily-triage.yml:76` — extend jq filter to exclude `ux-audit`:

  ```bash
  gh issue list --state open --limit 200 --json number,title,labels \
    --jq 'map(select(.labels | map(.name) | index("ux-audit") | not))'
  ```

- [ ] Edit `.github/workflows/scheduled-bug-fixer.yml:96–106` — extend existing `select()` jq filter to also exclude `ux-audit`:

  ```bash
  --jq 'map(select((.labels | map(.name) | index("bot-fix/attempted") | not)
                  and (.labels | map(.name) | index("ux-audit") | not)))'
  ```

- [ ] Add expense ledger line to `knowledge-base/operations/expenses.md`:

  ```text
  | Anthropic API (ux-audit) | Anthropic | api | ~$15/month | active | - | Event-driven + monthly cron. ~$3–$12/run × ≤3/month. See scheduled-ux-audit.yml |
  ```

- [ ] Pin the TR5 decision on #2343 via `gh issue comment 2343 --body "First consumer ships at plugins/soleur/skills/ux-audit/references/route-list.yaml. Extract to apps/web-platform/src/routes.manifest.ts when a second consumer (e.g. /soleur:qa, /soleur:test-browser) arrives. Keeping separate until shape pressure exists."`
- [ ] Update `plugins/soleur/README.md` skill count (via `soleur:release-docs` skill at ship time).
- [ ] Update `plugins/soleur/plugin.json` `description:` to mention `ux-audit`. Do NOT touch `version` field (frozen sentinel). Same for `marketplace.json` description.

**Calibration (sub-section, replaces the former Phase 4):**

- [ ] Manual `gh workflow run scheduled-ux-audit.yml --ref collapsible-navs-ux-review --field dry_run=true`. Download the findings JSON artifact.
- [ ] Check: do the top-5 findings include one categorized as `real-estate` or `ia` whose `title`/`description` references sidebars consuming fixed width without a collapse affordance?
  - **PASS** → flip push/cron default to `dry_run=false`; commit learning file `knowledge-base/project/learnings/2026-04-<day>-ux-audit-calibration.md` capturing which rubric phrasing made it pass.
  - **MISS** → tune the rubric once (adjust wording, reorder priorities). Re-run dry.
  - **STILL MISS** → ship the workflow with `dry_run` permanently `true` (filing disabled). File `gh issue create --title "ux-audit calibration failed" --milestone "Post-MVP / Later" --body "..."` with rubric attempts captured. Unblock #2342 manually (collapsible-navs ships on the founder's judgment, not the agent's). Revisit at next phase re-eval.

**Success criteria:** Workflow runs end-to-end; calibration produces one of the three paths above; `ux-audit`-labeled issues do not appear in the next `scheduled-daily-triage.yml` or `scheduled-bug-fixer.yml` run lists.

**Effort:** 1–2 days (workflow wiring) + 0.5 day (calibration + optional tune).

**Excluded from this plan (follow-up issues):**

- Marketing-site "Built by agents, in public" link (FR9 in spec) — file as follow-up issue after first calibrated filing. Reviewer flagged the file-path as TBD; not worth blocking the skill on a marketing edit whose location is unresolved. Follow-up issue title: `feat(marketing-site): 'Built by agents, in public' link to ux-audit issue query`.
- Blog post "We gave our UX reviewer a cron job" — follows first calibrated filing. `/ship` Phase 5.5 CMO content-opportunity gate triggers on `plugins/soleur/skills/ux-audit/**` file-path match.

### TR1: Skill file layout

```text
plugins/soleur/skills/ux-audit/
├── SKILL.md                          # Third-person description, phased workflow,
│                                     # inline rubric, inline fixture spec, linked yaml
├── references/
│   └── route-list.yaml               # Routes: {path, auth, fixture_prereqs, viewport}
└── scripts/
    ├── bot-fixture.ts                # Subcommands: seed | reset (idempotent)
    └── bot-signin.ts                 # Supabase signIn → storageState.json
```

Single reference file and two scripts. `audit-rubric.md` and `bot-fixture-spec.md` are NOT separate files — their content lives in SKILL.md per reviewer consensus.

### TR2: Agent extension — `ux-design-lead.md`

- Add a mode branch at top of `## Workflow` (prompt-level routing, not runtime control flow).
- Add `## UX Audit (Screenshots)` section AFTER existing `## UX Audit (Existing HTML Pages)` (L54–62). 5-category rubric (no 6th "error/empty/loading states"). JSON output contract.
- Do NOT modify `description:` frontmatter.
- **Prompt-engineering risk:** this is the most-likely calibration failure point. 1 extra engineer-day + golden-set test (3 past UX issues) budgeted in Phase 2.

### TR3: Dedup (single-layer hash search)

Hash format:

```text
sha256(utf8("{route}|{selector}|{category}"))
```

- `{route}`: e.g. `/dashboard/kb`
- `{selector}`: CSS selector of the primary flagged element (e.g., `aside.sidebar`). If agent returns empty, skill coarsens to `*` → effectively one finding per `{route, category}`.
- `{category}`: one of `real-estate | ia | consistency | responsive | comprehension` (5 categories, no `state`).

Embedded in issue body:

```html
<!-- ux-audit-hash: 7f83b1657ff1fc53b92dc18148a1d65dfc2d4b1fa3d677284addd200126d9069 -->
```

Dedup check (single GitHub API call — GitHub's issue search indexes body text):

```bash
DEDUP_QUERY="ux-audit-hash: $HASH"
EXISTS=$(gh issue list --label ux-audit --state all --search "$DEDUP_QUERY" --json number --jq 'length')
if [ "$EXISTS" -gt 0 ]; then
  echo "dedup-suppressed: $HASH"
  continue
fi
```

**Rule:** if any issue with this hash exists in any state (open OR closed), skip. Closed ≠ re-file. If the founder wants to resurface a closed finding, they reopen it — that's the re-signal path. No time-based expiry logic. (Reviewer consensus: 180-day `wontfix` expiry was imagined complexity.)

### TR4: Route list scope (Open Question #1 decision — stays in-skill)

**Decision: defer shared manifest to #2343. Ship hardcoded `route-list.yaml` in the skill.**

Rationale: #2343 is justified only if a second consumer exists. Building shared `apps/web-platform/src/routes.manifest.ts` now solves only the `soleur:ux-audit` case — premature abstraction. Shared manifest has richer design considerations (auth roles, feature flags, fixture deps, per-route performance budgets) that benefit from a second concrete consumer driving the shape. YAGNI: co-locate routes with skill; extract when `/soleur:qa`, `/soleur:test-browser`, or monitoring wants the same list.

Decision pinned via `gh issue comment 2343` deliverable in Phase 3.

### TR5: Screenshot handling (Open Question #5 decision)

- **Scale:** `1x` at viewport `1440×900`. Rationale: token-economical; rubric targets IA/real-estate/consistency readable at standard density. No `--scale` flag (removed per reviewer consensus — YAGNI).
- **Storage:** Attach directly to GitHub issue body via `gh issue create --body-file`. Screenshots written under `${{ github.workspace }}/tmp/ux-audit/<route-slug>.png` at absolute paths (per `hr-mcp-tools-playwright-etc-resolve-paths`). Repo-wide `*.png` gitignore means they never commit (per `2026-03-10-gitignore-blanket-rules-with-negation.md`).
- **PII redaction:** None active in v1. Three stacked reasons:
  1. Bot fixture is synthetic — invariants in Phase 1 forbid real creds/emails/payment.
  2. Screenshots attach to issues (not committed) — `git-push-protection` not a concern (per `2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md`).
  3. Public repo issues are publicly readable, but bot account has no real-user data.

  **Re-evaluation trigger:** if skill ever audits pages rendering real user content (shared-link pages, admin panels), re-evaluate with redaction step.

### TR6: Max-turns budget

`--max-turns 60`. Plugin overhead ~10 + setup ~5 + per-route 4 turns × 15 routes = ~75 upper bound, 60 is reasonable given skill exits early on empty findings. Matches daily-triage budget (per `2026-03-20-claude-code-action-max-turns-budget.md`).

### TR7: Viewport

`1440×900` only. Matches the ICP's standard laptop. Mobile viewport not in scope (future consideration).

### TR8: Injection safety

All agent-generated finding data passes through `env:` variables before `gh issue create`:

```yaml
- name: File finding
  env:
    TITLE: ${{ steps.audit.outputs.title }}
    BODY_FILE: ${{ steps.audit.outputs.body_file }}
  run: |
    gh issue create \
      --title "ux: $TITLE" \
      --body-file "$BODY_FILE" \
      --label ux-audit,agent:ux-design-lead,domain/product \
      --milestone "Post-MVP / Later"
```

Title prefix `ux:` integrates with existing auto-label workflow. Milestone passed by title (per `cq-gh-issue-create-milestone-takes-title`).

### TR9: Skill invocation mechanism

Workflow invokes the skill via `claude-code-action` (same step pattern as `scheduled-competitive-analysis.yml`). For local dev:

```bash
UX_AUDIT_DRY_RUN=true doppler run -c prd_scheduled -- claude code --skill soleur:ux-audit --route /dashboard
```

`--skill soleur:ux-audit` is the canonical invocation. Skill reads `UX_AUDIT_DRY_RUN` env var; `--route <path>` is a dev-only convenience.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Extend `soleur:qa` with audit mode | `/soleur:qa` is merge-gated and scoped to diffs. ux-audit runs against the full UI. Mixing modes muddies `/soleur:qa`'s contract. |
| Extend `soleur:test-browser` with audit mode | `test-browser` captures and reports but has no "file issues" output path. Adding audit triples its responsibilities. |
| Reuse `ux-design-lead` without a mode switch | Conflates Pencil wireframe flow (produces `.pen`) with HTML-audit flow (produces findings JSON). Mode branch cleanly separates. |
| Weekly cron instead of event-driven + monthly cron | Pays audit cost in quiet weeks. Event-driven ties cost to UI churn. |
| Vercel preview URL instead of prod | Preview sites have no seed data; empty-state audits misleading. Bot-auth'd prod is the only way to audit real user view. |
| Supabase Storage or R2 for screenshots | Adds storage surface with no clear win. GitHub attachment is simpler; issues double as audit log. |
| Embedding-similarity dedup | Overkill. Hash on `{route, selector, category}` catches exact re-findings; UI doesn't produce fuzzy-similar findings needing semantic match. |
| In-feature `routes.manifest.ts` | See TR4 — rejected pending second consumer. |
| 180-day `wontfix` expiry on dedup | Rejected. Imagined complexity for a loop that's never run. Simple rule: closed = no re-file; founder reopens to resurface. |
| Two-layer dedup (search-by-route + hash) | Rejected. GitHub issue search indexes body text; one `--search "ux-audit-hash: $HASH"` call suffices. Route-narrowing was premature optimization. |
| `--dry-run` CLI flag AND env gate | Rejected. Pick one. Chose env (`UX_AUDIT_DRY_RUN`) wired from `workflow_dispatch.inputs.dry_run`. Single plumbing. |
| Separate `audit-rubric.md` + `bot-fixture-spec.md` files | Rejected. Both are short enough to live inline in SKILL.md — fragmenting them made the skill harder to maintain. |
| 6th rubric category "error/empty/loading states" | Rejected. Happy-path bot screenshots won't reliably surface these. Add when capture strategy for those states exists. |
| Phase 4 as standalone phase | Rejected. Calibration is a smoke test of Phase 3, collapsed into Phase 3's Calibration sub-section. |
| 3-iteration pre-declared rubric-tuning budget | Rejected. Ceremony. Replaced with: tune once, if still missing ship dry-only and file tracking issue. |
| `prd` Doppler config for bot creds | `prd_scheduled` is convention for automated/bot secrets (per `scheduled-community-monitor.yml:56`). |

## Acceptance Criteria

### Functional Requirements

- [ ] FR1 — `plugins/soleur/skills/ux-audit/SKILL.md` exists, passes `plugins/soleur/AGENTS.md` Skill Compliance Checklist (third-person description ≤ 200 chars, `name:` kebab-case, references linked via `[filename](./references/filename)`, cumulative description under 1800-word plugin budget).
- [ ] FR2 — `ux-design-lead.md` has new "## UX Audit (Screenshots)" section AFTER existing HTML-audit section; `description:` frontmatter unchanged; 5-category rubric, JSON output contract.
- [ ] FR3 — `scheduled-ux-audit.yml` triggers on `push` (branches: `[main]`, paths: web-platform app/components), `schedule` (monthly cron), `workflow_dispatch` (with `dry_run` input).
- [ ] FR4 — Doppler `prd_scheduled` contains `UX_AUDIT_BOT_EMAIL`, `UX_AUDIT_BOT_PASSWORD`; workflow loads via `DOPPLER_TOKEN_SCHEDULED`.
- [ ] FR5 — Supabase user `ux-audit-bot@jikigai.com` exists; `scripts/bot-fixture.ts seed` is idempotent; running `seed` twice does not create duplicates.
- [ ] FR6 — Skill enforces `CAP_OPEN_ISSUES = 20` (global, refuses to file when reached) and per-run cap of 5.
- [ ] FR7 — Dedup verification: run #1 in file-mode against a fresh state creates N issues; run #2 (no UI changes) in file-mode reports `dedup-suppressed: N, filed: 0`.
- [ ] FR8 — Filing-mode first run files ≥ 1 issue tagged `ux-audit + agent:ux-design-lead + domain/product`, milestoned `Post-MVP / Later`, with a screenshot attached and `<!-- ux-audit-hash: ... -->` in body.
- [ ] FR9 — `scheduled-daily-triage.yml` and `scheduled-bug-fixer.yml` skip `ux-audit`-labeled issues (verified by running each workflow with a test `ux-audit` issue open and inspecting its candidate list).
- [ ] FR10 — `notify-ops-email` fires on workflow failure (verified on a test branch with a deliberate failure step).
- [ ] FR11 — `knowledge-base/operations/expenses.md` contains the ux-audit line.
- [ ] FR12 — `plugin.json` `description:` mentions `ux-audit`; `marketplace.json` description updated; README.md skill count updated via `/soleur:release-docs`.
- [ ] FR13 — `gh issue comment 2343` pinning the TR4 decision executed.
- [ ] FR14 — Golden-set test: 3 past UX issues appear in top-5 of their respective audit-mode runs before live calibration.
- [ ] FR15 — Phase 3 Calibration completes via PASS / MISS-tune-retry / STILL-MISS-ship-dry path.

### Non-Functional Requirements

- [ ] NFR1 (performance) — Single run ≤ 30 minutes (15 routes × ~2 min); workflow `timeout-minutes: 45` provides buffer.
- [ ] NFR2 (security) — All finding data flows through `env:` vars; no finding content interpolated in `run:` blocks.
- [ ] NFR3 (security) — Bot fixture passes the fixture-invariant audit (no real emails except bot's own, no secrets, no payment info).
- [ ] NFR4 (observability) — Workflow run emits structured log lines: route count, findings count, dedup-suppressed count, filed count, dry-run flag.
- [ ] NFR5 (governance) — Auto-fix and auto-triage workflows exclude `ux-audit` (prevents agent-filed → auto-triage → auto-fix self-loop).
- [ ] NFR6 — `/soleur:architecture assess` run against `knowledge-base/engineering/architecture/nfr-register.md`; output attached to PR body.
- [ ] NFR7 — `/ship` Phase 5.5 CMO content-opportunity gate verified to fire at this PR (file-path match: `plugins/soleur/skills/ux-audit/**`, `.github/workflows/scheduled-ux-audit.yml`).

**Cost monitoring (not gating):** Run cost logged to workflow output. Target: ≤ $12/run. Unexpected spend (> $15) logs `::warning::`; does not abort. Validated as monitoring metric, not pre-merge AC, because claude-code-action does not natively report per-run Anthropic spend — can approximate via tokens × price parsed from action output.

### Quality Gates

- [ ] Unit test: dedup hash computation (`sha256({route}|{selector}|{category})`).
- [ ] Integration test: `UX_AUDIT_DRY_RUN=true claude code --skill soleur:ux-audit --route /` in dev Doppler config returns well-formed findings JSON.
- [ ] Integration test: golden-set — 3 past UX issues surfaced in top-5 (FR14).
- [ ] Manual post-merge: `gh workflow run scheduled-ux-audit.yml --ref main --field dry_run=true` succeeds within 45 min (per `wg-after-merging-a-pr-that-adds-or-modifies`).
- [ ] Documentation complete: SKILL.md (with inline rubric + fixture spec), route-list.yaml, bot-fixture.ts, bot-signin.ts, ux-design-lead.md section.
- [ ] PR body: `Closes #2341`, `Ref #2343`, `Ref #2344`, `## Changelog` section with `semver:minor` label.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- **Given** `workflow_dispatch` with `dry_run=true` **when** skill completes **then** workflow produces a JSON findings artifact with ≥ 1 finding per route and no `gh issue create` call.
- **Given** an existing `ux-audit`-labeled issue (any state) with body containing `<!-- ux-audit-hash: ABC -->` **when** skill generates a finding with hash `ABC` **then** finding is skipped and log emits `dedup-suppressed: ABC`.
- **Given** 20 open `ux-audit` issues **when** skill generates a new finding **then** skill logs `::warning::global cap reached` and does not file.
- **Given** dry-run #1 produces N findings in file-mode and dry-run #2 follows with UI unchanged **when** #2 runs in file-mode **then** #2 logs `dedup-suppressed: N, filed: 0` (FR7 verification).
- **Given** workflow fails at the Playwright step **when** `if: failure()` runs **then** `ops@jikigai.com` receives email with failure URL.
- **Given** `scheduled-daily-triage.yml` runs **when** 3 open `ux-audit` issues exist **then** none appear in triage-candidate list.
- **Given** `scheduled-bug-fixer.yml` runs **when** 2 open `ux-audit` issues have `priority/p1` **then** neither is selected for auto-fix.
- **Given** 3 historical UX issues with known-good screenshots **when** `ux-design-lead` audit-mode runs on each **then** each appears in its run's top-5 findings (golden set, FR14).

### Regression Tests

- **Given** `ux-design-lead` invoked without `mode: audit` **when** agent runs **then** existing Pencil workflow executes unchanged.
- **Given** `/soleur:qa` runs on a PR diff **when** diff includes UI changes **then** `/soleur:qa` behaves identically to pre-ux-audit baseline.

### Edge Cases

- **Given** a route's `fixture_prereqs` are not all met **when** skill navigates **then** skill logs `route skipped: missing prereq <name>` and continues.
- **Given** Playwright cannot authenticate (expired bot creds) **when** skill runs `bot-signin.ts` **then** skill fails fast; failure triggers `notify-ops-email`.
- **Given** `ux-design-lead` returns malformed JSON **when** skill parses **then** skill logs `::error::malformed agent output`, files no issues from that route, continues to next.
- **Given** finding's selector is empty **when** hash is computed **then** skill coarsens to `{route}|*|{category}`.
- **Given** push to feature branch touching `apps/web-platform/app/**` **when** feature branch is NOT main **then** workflow does NOT trigger (verified by `branches: [main]` filter).

### Integration Verification (for `/soleur:qa`)

- **API verify:** `gh issue list --label ux-audit --state open --json number --jq 'length'` expects `≤ 20` at all times.
- **API verify:** `doppler secrets get UX_AUDIT_BOT_EMAIL --project soleur --config prd_scheduled --plain` expects `ux-audit-bot@jikigai.com`.
- **Browser:** sign in as bot → `/dashboard/kb` → verify ≥ 6 KB files present (fixture health).
- **Workflow verify:** `gh workflow run scheduled-ux-audit.yml --ref main --field dry_run=true` expects `conclusion=success` within 45 min.
- **Cleanup:** `doppler run -c prd_scheduled -- node plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts reset` for re-seed between calibration iterations.

## Success Metrics

- **Calibration result:** PASS / MISS-tune-retry / STILL-MISS-ship-dry.
- **Close rate ≥ 60%** on filed issues over 3 months (CPO acceptance signal).
- **Cost per run ≤ $12** (COO target; monitored, not gated).
- **Throughput:** ≥ 3 event-driven runs per month given typical UI-path PR frequency.
- **Dedup efficacy:** after 5 consecutive runs on unchanged UI, ≤ 1 duplicate filed.

## Dependencies & Prerequisites

- **Blocks:** #2342 (collapsible navs). If calibration FAILs three ways, #2342 unblocks manually (ships on founder judgment, not agent). If PASS or MISS-tune, collapsible-navs ships after the first filed calibration finding.
- **Related:** #2343 (route manifest — deferred, TR4). #2344 (auto-fix/triage exclusion — Phase 3 one-liners satisfy).
- **External:** Supabase (bot account), GitHub Actions (claude-code-action, playwright-github-action), Doppler (`prd_scheduled`), Anthropic API.
- **Internal:** `plugins/soleur/skills/schedule/` (scaffolds workflow), `.github/actions/notify-ops-email`, `plugins/soleur/agents/product/design/ux-design-lead.md` (extended Phase 2).

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Agent produces noisy findings (close rate < 30%) | Medium | High | Golden-set test (FR14) + Phase 3 calibration gate. `dry_run` default `true` until calibration passes. STILL-MISS path = ship with filing off. |
| ux-design-lead audit-mode prompt underperforms | High | High | 1 extra engineer-day budget + golden-set test runs before Phase 3 calibration. |
| Cost runaway | Low | Medium | `--max-turns 60`. Cost-log step. Warning at >$15. |
| Bot creds leak into screenshots/commit | Low | High | Fixture invariants (no real creds). `env:` var discipline. Screenshots attach (not commit). |
| Infinite loop (agent fixes its own findings) | Low | High | Exclusion jq filter (FR9). Acceptance test verifies. |
| GitHub rate limit on `gh issue list` | Low | Medium | Caps 5/run + 20 global → ≤ 20 list calls/run. Well under limit. |
| Playwright flakiness in CI | Medium | Low | Retry once per route. One route failure does not abort. `--isolated` mode. Version pinned to `apps/web-platform/package.json`. |
| Malformed JSON from agent | Medium | Low | Parse-guard logs `::error::` and skips to next route. |
| `DOPPLER_TOKEN_SCHEDULED` revoked/rotated | Low | High | Workflow gates on secret existence; failure → `notify-ops-email`. |
| ux-design-lead Pencil regression from mode branch | Low | Medium | Regression test (Phase 2). Mode branch is documentation-level — missing branch still runs Pencil flow. |
| Supabase schema drift breaks seeder silently | Medium | Medium | `bot-fixture.ts seed` in Phase 1 tries to assert schema; any seeder failure emails ops; consider adding to web-platform CI smoke test in a follow-up. |
| `push: paths:` triggers on feature branches | Low (mitigated) | High (if not mitigated) | `branches: [main]` in `push:` block (FR3, Phase 3 Deliverables). Acceptance test verifies. |

## Resource Requirements

- **Effort total:** ~4.5–6.5 engineer-days across Phases 1–3 (was 5–7 before consolidating Phase 4).
- **Infrastructure:** One Supabase user, uses existing `DOPPLER_TOKEN_SCHEDULED`, no new hosted services.
- **Ongoing cost:** ~$15/month Anthropic API.

## Future Considerations

- **Mobile audit pass.** Add `375×812` variant once ICP includes more mobile-first users. Separate rubric.
- **Role-scoped audits.** Bot is solo-founder persona; future "admin" persona fixture for admin panels.
- **Route manifest extraction (#2343).** When `/soleur:qa` or monitoring wants the same list, extract `route-list.yaml` → `apps/web-platform/src/routes.manifest.ts`.
- **Regression-specific audit.** Diff-scoped audit mode — overlaps `/soleur:qa`, re-evaluate scope then.
- **Redaction hooks.** When audit expands beyond synthetic bot, add pre-attachment redaction.
- **Cost reporting.** Parse `usage` from claude-code-action output and post per-run cost as workflow summary or Slack/Discord digest.

## Documentation Plan

- [ ] `plugins/soleur/skills/ux-audit/SKILL.md` — full skill doc including inline rubric and fixture spec.
- [ ] `plugins/soleur/skills/ux-audit/references/route-list.yaml` — data file.
- [ ] `plugins/soleur/agents/product/design/ux-design-lead.md` — new "## UX Audit (Screenshots)" section.
- [ ] `knowledge-base/operations/expenses.md` — ux-audit line.
- [ ] `knowledge-base/project/learnings/2026-04-<day>-ux-audit-calibration.md` — after calibration (Phase 3 PASS or tune path).
- [ ] `plugins/soleur/README.md` — skill count (via `/soleur:release-docs`).
- [ ] `plugins/soleur/plugin.json` — description mentions `ux-audit` (do NOT edit `version`).
- [ ] `marketplace.json` — description update (do NOT edit `version`).
- [ ] PR body: `Closes #2341`, `Ref #2343`, `Ref #2344`, `## Changelog` section, `semver:minor` label.

## Domain Review

**Domains relevant:** Product (CPO), Marketing (CMO), Engineering (CTO), Operations (COO)

Carried forward from brainstorm `## Domain Assessments` (2026-04-15 brainstorm, L63–77). Legal/Sales/Finance/Support assessed as not-relevant and remain so.

### Product (CPO)

**Status:** reviewed (carry-forward)
**Assessment:** High user value for #2342; medium for #2341 (depends on signal quality). Phase 3 fits; materially de-risks Phase 4's unassisted-usage trigger. **Plan alignment:** owned by this plan, calibration gate inside Phase 3, close-rate metric in Success Metrics.

### Marketing (CMO)

**Status:** reviewed (carry-forward)
**Assessment:** Most credible concrete artifact for agent-native positioning. **Plan alignment:** labels (FR8), `/ship` Phase 5.5 CMO gate verified (NFR7). Marketing-site link + blog post deferred to follow-up issues (post-calibration — no value in shipping marketing copy against an uncalibrated agent).

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** New skill (not extend), event-driven + monthly cron, fixture-seeded bot, hash dedup, 20-issue cap, exclude from auto-fix/auto-triage. Two capability gaps flagged (route manifest #2343, new skill). **Plan alignment:** all addressed; `#2343` pinned via comment deliverable.

### Operations (COO)

**Status:** reviewed (carry-forward)
**Assessment:** GitHub Actions schedule, Doppler `prd_scheduled`, ~$15/month max, attach to issues (no new storage), email-on-failure. **Plan alignment:** FR3, FR4, FR10, FR11.

### Brainstorm-recommended specialists

None named by agent-name in brainstorm assessments. No carry-forward specialist invocation required.

### Product/UX Gate

**Tier:** NONE
**Rationale:** Plan creates infrastructure (skill + workflow + Supabase user + agent mode extension + 2 one-line workflow edits + expense ledger line). No new `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`. Collapsible-nav UI is OUT of scope — it lives in #2342 with its own Product/UX Gate.

## References & Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-15-collapsible-navs-ux-review-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-collapsible-navs-ux-review/spec.md`
- Canonical workflow template: `.github/workflows/scheduled-competitive-analysis.yml`
- Doppler `prd_scheduled` pattern: `.github/workflows/scheduled-community-monitor.yml:49–60`
- Thin-skill + agent-mode pattern: `plugins/soleur/skills/competitive-analysis/SKILL.md`
- Failure-handler pattern: `plugins/soleur/skills/fix-issue/SKILL.md:143–173`
- Label pre-creation pattern: `.github/workflows/scheduled-bug-fixer.yml:52–70`
- Existing HTML-audit section: `plugins/soleur/agents/product/design/ux-design-lead.md:54–62`
- Public/auth split: `apps/web-platform/middleware.ts:73–123`, `apps/web-platform/lib/routes.ts`
- Playwright e2e: `apps/web-platform/playwright.config.ts`, `apps/web-platform/e2e/global-setup.ts`
- Auto-fix workflow: `.github/workflows/scheduled-bug-fixer.yml:96–106`
- Auto-triage workflow: `.github/workflows/scheduled-daily-triage.yml:76`
- Expense ledger: `knowledge-base/operations/expenses.md`
- Skill Compliance Checklist: `plugins/soleur/AGENTS.md` (Skill Compliance Checklist section)

### Learnings (cited inline above)

- `2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md` — rubric source
- `2026-02-27-schedule-skill-template-gaps-first-consumer.md` — workflow template gaps
- `2026-04-13-codeql-alert-triage-and-issue-automation.md` — env-var injection safety
- `2026-03-03-scheduled-bot-fix-workflow-patterns.md` + `2026-03-04-gh-jq-does-not-support-arg-flag.md` — `gh --jq` semantics
- `2026-03-29-doppler-service-token-config-scope-mismatch.md` — config-scoped secret naming
- `2026-04-02-playwright-mcp-isolated-mode-for-parallel-sessions.md` — keep `--isolated`
- `2026-02-17-playwright-screenshots-land-in-main-repo.md` — absolute paths in CI
- `workflow-issues/2026-04-03-playwright-browser-cleanup-on-session-exit.md` — explicit `browser_close`
- `2026-03-20-playwright-shared-cache-version-coupling.md` — pin Playwright version
- `2026-03-20-claude-code-action-max-turns-budget.md` — `--max-turns 60`
- `2026-04-13-codeql-to-issues-invalid-workflow-trigger.md` — `push: paths:` validity
- `2026-02-21-github-actions-workflow-security-patterns.md` — SHA-pin actions
- `2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md` — attach-not-commit
- `2026-04-10-e2e-authenticated-dashboard-tests-mock-supabase.md` — bot signin pattern
- `2026-03-10-gitignore-blanket-rules-with-negation.md` — `*.png` gitignored

### Related Work

- Issue #2341 (this plan owns) — feat: soleur:ux-audit recurring UX-review agent loop
- Issue #2342 (blocked by this) — feat: collapsible sidebars
- Issue #2343 (deferred, pinned via comment) — feat: shared route manifest
- Issue #2344 (one-liners satisfy) — feat: exclude agent-authored from auto-fix/triage
- PR #2346 — this branch's PR

## Open Questions — Resolved

1. **Route manifest scope:** Deferred to #2343. Ship hardcoded `route-list.yaml` in skill. Pin decision via `gh issue comment 2343`. [TR4]
2. **Bot fixture content:** Specified in Phase 1 Deliverables. KB (6 files, diverse types), team (2 synthetic `@example.com` members), chat (2 conversations), services (1 mocked), billing (Stripe test). Fixture invariants forbid real creds/emails/payment. Onboarding+T&Cs+billing pre-completed. [Phase 1]
3. **First-run calibration criterion:** Collapsed into Phase 3 Calibration sub-section (no separate Phase 4). PASS = collapsible-navs in top-5. MISS = tune rubric once. STILL MISS = ship `dry_run=true` + tracking issue. Backed by a golden-set test of 3 past UX issues that must surface before live calibration. [Phase 3]
4. **Dedup hash expiry:** None. Closed (any state) = no re-file. Founder reopens to resurface. [TR3]
5. **Screenshot scale + PII redaction:** 1x at 1440×900 (no `--scale` flag — YAGNI). No active redaction (synthetic fixture; attach-not-commit; no real user data). Re-evaluate when auditing pages with real user content. [TR5]
