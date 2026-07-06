---
title: "feat: Kanban board ↔ Workstream tab sync — GitHub Project v2 as canonical issue Status"
type: feature
lane: cross-domain
brand_survival_threshold: aggregate pattern
status: draft
created: 2026-07-02
branch: feat-kanban-board-workstream-sync
issue: TBD
adr: ADR-091 (allocate at write time — main HEAD max is ADR-074; re-confirm the next free number, unmerged branches may race)
plan_review: applied (DHH + Kieran + code-simplicity, 2026-07-02) — see "Plan Review Applied"
---

# ✨ Kanban board ↔ Workstream tab sync

Make the **GitHub Project v2 board "Soleur Kanban"** (`jikig-ai/projects/2`) the canonical
place issue Status lives, drive cards through its columns automatically as issues are
processed, and make the in-app **Workstream tab** a faithful *reader* of that board.

## Overview

The operator added two columns to the org Project board — **Blocked** and **Pending** —
and wants (1) every processed issue to flow through the board columns to reflect its
state, and (2) the app's Workstream tab to mirror the board.

A 4-agent investigation (2026-07-02) established the starting point:

- **Zero repo-side automation touches the Project v2 board.** A full `main` `git grep`
  found no `add-to-project`, no `updateProjectV2ItemFieldValue`, no `gh project`, no
  project token. The 497/512 cards stuck in **Backlog** come from GitHub's built-in
  "Auto-add → Backlog" workflow (Project Settings UI, not in the repo). The only automatic
  move that fires is GitHub's built-in "issue closed → Done." **Blocked / Pending have no
  handling anywhere.**
- **The Workstream tab already exists and shipped** (PR #5659, MERGED), at
  `/dashboard/workstream`. It reads the active workspace's connected-repo **issues via
  REST** (`server/workstream/get-workstream-issues.ts` → `listRepoIssues` in
  `server/github-read-tools.ts`, ADR-044 installation token) and **derives** columns
  client-side in `lib/workstream.ts` `deriveColumn()`. It does **not** read the Project
  board. Card moves in the UI are optimistic, **local-only**. Route is GET-only.
- **Column vocabularies mismatch.** App enum
  `backlog|todo|in_progress|in_review|blocked|done|cancelled`; board
  `Backlog|Ready|In progress|In review|Blocked|Pending|Done`.
- **The labels the app derives from are never applied** by any skill/workflow, so today
  every open issue collapses to Backlog and every closed one to Done/Cancelled.

**Directional decision (operator-confirmed):** the **GitHub Project v2 board is
canonical**; the app tab becomes a reader of its Status field. Build on the merged #5659
foundation; the board link is net-new work on top, not a rewrite.

## Plan Review Applied

Three reviewers (DHH, Kieran, code-simplicity) reviewed the first draft; all applied:
- **Scope cut (DHH + simplicity):** dropped the per-workspace migration/column → env-resolve
  the single board; dropped the standalone skill-wiring PR; dropped `ready`-label
  automation and the secondary-rate-limit retry; trimmed observability (fail-loud + `gh
  run list`, no auto-filed tracking issue); GitHub's **built-in** Project workflows handle
  `issue closed → Done` (they already do — that's the current behavior). 4 PRs → **3**.
- **Correctness (Kieran):** added `reopened` and `PR closed-unmerged` mappings (were
  stuck-in-Done bugs); specified **PR → linked-issue resolution** (the tab reads issues,
  and Soleur bot PRs use `Ref #N` not `Closes #N`, so `closingIssuesReferences` is empty →
  must parse `Ref #N`); added `workstream-tools.ts` (hardcoded old-vocab **string**) to
  Phase 0; recompute derives from PR draft/ready state (addresses In-review/Ready
  reconstruction); expanded test scenarios; noted not_planned→Done in User-Brand Impact.
- **Deviation from reviewers:** simplicity suggested 2 PRs (writer+reader combined); kept
  writer and reader as **separate** PRs (Phase 1/Phase 2) for reviewability — they are
  independent and separately valuable. Minor.

## Research Reconciliation — Spec vs. Codebase

| Claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "link this kanban to the workstream tab" | Tab reads *issues*, not the *board*; columns label-derived | Phase 2 adds a GraphQL board-Status read; `deriveColumn` prefers board Status |
| "Soleur should deal with each column" | No repo automation writes board Status; Blocked/Pending unhandled | Phase 1 workflow writes Status on lifecycle events |
| Token: provision a PAT | Repo uses a **GitHub App** (Doppler `prd_terraform`); `hr-github-app-auth-not-pat` forbids PAT | Grant the App `organization_projects: read+write`; one grant unblocks write+read |
| Default `GITHUB_TOKEN` moves cards | FALSE — repo-scoped; org Projects out of boundary | Workflow mints an App installation token |
| PR carries `Closes #N` → linked issue | Soleur bot PRs use `Ref #N` (fix-issue SKILL:199) → `closingIssuesReferences` EMPTY | Workflow parses `Ref #N` ∪ `closingIssuesReferences` |
| App column set matches board | Mismatch (`todo`/`cancelled` vs `ready`/`pending`) | Phase 0 vocab alignment |

## User-Brand Impact

**If this lands broken, the user experiences:** a Workstream tab column disagreeing with
the GitHub board (cosmetic, read-only), or a card that fails to advance (stays put — the
pre-existing status quo). No data loss: Project Status is reversible metadata. **Semantic
note:** folding `cancelled → done` means wontfix/duplicate closed issues render under
**Done** (the board has no Cancelled column); acceptable under board-canonical, called out
here so the "completed" reading is a known, intended simplification.

**If this leaks:** nothing new — the board read surfaces issue titles/state the shipped
tab already exposes for the same connected repo. No new personal data; no new credential
(the project number is a non-secret integer resolved from env config).

**Brand-survival threshold:** `aggregate pattern` — internal ops/board surface; no
per-user financial/auth/destructive path; broken behavior degrades to label derivation.
Sensitive-path scope-out: `reason: no migration/regulated surface in this cut; board read
reuses issue data already exposed by #5659.`

## Architecture Decision (ADR/C4)

ADR + C4 update are **deliverables of this plan** (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR
Create **ADR-091: GitHub Project v2 board is the canonical issue-Status store** (re-confirm
the next free number: `git ls-tree -r main -- knowledge-base/engineering/architecture/decisions/ | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -1`; main HEAD max is ADR-074).
- `## Decision`: the org board "Soleur Kanban" is the single source of truth for issue
  Status. A GitHub Actions workflow advances cards on lifecycle events via the GitHub App
  (`organization_projects`). The Workstream tab reads the board Status and prefers it over
  label derivation (fallback for issues not on a board).
- `## Alternatives Considered`: (a) **App-webhook ingress writes the board from the web
  server** (ADR-036) — generalizes to per-workspace boards, deferred until non-Soleur
  users maintain their own boards; (b) app-labels canonical — rejected (keeps two
  writers); (c) PAT — rejected (`hr-github-app-auth-not-pat`).

### C4 views
Read all three (`model.c4`, `views.c4`, `spec.c4`). Enumeration: operator editing the
board = existing `founder`; the board = facet of existing `github` (no new system); store
= existing `supabase`. **Add the missing `api -> github` edge** (verified absent — only
`engine`/`claude`/`contributor -> github` exist), which the Phase-2 read needs:
```
api -> github "Workstream tab: reads connected-repo issues (REST) + Project v2 board Status (GraphQL); board is canonical Status store (ADR-091)" { technology "HTTPS (REST + GraphQL)" }
```
**State explicitly** in the ADR/C4 note that the Phase-1 **write** path (GitHub Actions →
ProjectV2) is *github-internal* (both inside the `github` boundary) and correctly has no
cross-boundary edge. No `spec.c4`/`views.c4` change (reuses `#external`; both endpoints
already in the views). Run `c4-code-syntax.test.ts` + `c4-render.test.ts` after.

## Infrastructure (IaC)
No Terraform resource created. The one dependency is a **GitHub App permission grant**
(`organization_projects: Read and write`) on the existing Soleur App (not IaC-managed
today; `infra/github/*.tf` manages only `github_repository_ruleset`).

**Apply path / consent gate:** granting an installed App a new permission requires
**org-owner approval** — a consent-class human gate, not Terraform-applicable.
`automation-status: UNVERIFIED — /work MUST run a Playwright attempt first`: the permission
*request* on the App page runs under an authenticated session (presumptively
Playwright-automatable); the **org approval** is the consent gate. /work attempts the
request via Playwright, then hands org-approval to the operator with a `playwright-attempt:`
evidence line. **Live-403 validation:** confirm `organization_projects: write` actually
authorizes ProjectV2 GraphQL mutations on the org-owned `jikig-ai/projects/2` (historically
this key covered classic Projects) — the post-merge real-event AC exercises this.

**Distinctness:** targets the **prd** org project; App creds from Doppler `prd_terraform`
(the `apply-github-infra.yml` source). No new secret.

## Observability

```yaml
liveness_signal:
  what: GitHub Actions run of board-status-sync.yml on each issue/PR/label event
  cadence: per-event
  alert_target: workflow step fails loud (non-zero) — visible in gh run list; no auto-filed issue (internal low-volume board)
  configured_in: .github/workflows/board-status-sync.yml
error_reporting:
  destination: GitHub Actions run log (fail-loud); web read path degrades + mirrors via reportSilentFallback (Sentry)
  fail_loud: true  # GraphQL 4xx/5xx fails the step; post-mutation re-read asserts the option actually applied
failure_modes:
  - mode: App lacks organization_projects permission (403)
    detection: GraphQL 403 + post-mutation re-read mismatch
    alert_route: workflow step fails non-zero (visible in gh run list)
  - mode: board option-id drift (a column renamed/removed)
    detection: Status field discovery returns no option matching the target name
    alert_route: workflow fails loud (no silent no-op)
  - mode: web read of board Status fails (Phase 2)
    detection: GraphQL error in the board-read
    alert_route: fall back to label derivation + reportSilentFallback (never throw)
logs:
  where: GitHub Actions run logs (repo retention ~90d); Sentry for the web read path
  retention: GitHub default; Sentry per project
discoverability_test:
  command: gh run list --workflow=board-status-sync.yml -L 5 --json conclusion,headBranch,event
  expected_output: recent runs conclusion=success (NO ssh)
```

## Status-value mapping tables

### Board Status → app `WorkstreamStatus` (Phase 0 + Phase 2 read)

| GitHub board Status | app `WorkstreamStatus` (after Phase 0) | Change |
|---|---|---|
| Backlog | `backlog` | 1:1 |
| Ready | `ready` | **rename** `todo` → `ready` |
| In progress | `in_progress` | 1:1 |
| In review | `in_review` | 1:1 |
| Blocked | `blocked` | 1:1 |
| Pending | `pending` | **new** |
| Done | `done` | 1:1 |
| — (no Cancelled) | *(removed)* | **fold** `cancelled` → `done` |

### Fallback derivation (issues NOT on a board — `deriveColumn`)
closed → `done`; open `blocked` → `blocked`; `pending` → `pending`; `in-progress` →
`in_progress`; `review`/`needs-review` → `in_review`; `ready`/`todo` → `ready`; else
`backlog`. Board Status, when present, **wins**.

### Lifecycle event → board Status write (Phase 1)
The workflow moves the **linked issue's** card (the tab reads issues). PR→issue linkage =
`closingIssuesReferences` ∪ `Ref #N` parsed from the PR body/title (Soleur bot PRs use
`Ref #N`). `recompute(issue)` derives the correct open-issue column from current state:
`blocked` label → Blocked; else `pending` → Pending; else open linked PR ready-for-review
→ In review; else open linked PR (draft) → In progress; else `ready` label → Ready; else
Backlog.

| Trigger | Board Status set | Handled by |
|---|---|---|
| issue `closed` | Done | **GitHub built-in** (Item closed → Done) |
| PR `merged` → issue closes (Ref/Closes) | Done | built-in (on the resulting issue close) |
| issue `reopened` | `recompute(issue)` | custom workflow |
| `blocked` label added / removed | Blocked / `recompute` | custom workflow |
| `pending` label added / removed | Pending / `recompute` | custom workflow |
| PR `opened`/`ready_for_review`/`converted_to_draft` | linked issues → In review if PR ready, else In progress | custom workflow |
| PR `closed` & **not** merged | linked issues → `recompute` | custom workflow |

**Limitations (noted):** `recompute` reconstructs In review vs In progress from PR
draft/ready state; it cannot recover a manual `Ready`/`Pending` that had no label. Fork PRs
carry no secrets → their events won't move cards (Soleur bot PRs are same-repo — fine).

## Implementation Phases

### Phase 0 — Align app column vocabulary (PR 1, no external dep)

**Files to Edit:**
- `apps/web-platform/lib/workstream.ts` — `WorkstreamStatus`: `todo`→`ready`, add
  `pending`, remove `cancelled`. Update `COLUMNS` (Todo→Ready, add Pending before Done,
  drop Cancelled), `statusPillClass`, `CLOSED_STATUSES` (→ `{done}`), `deriveColumn`
  (closed→`done`; add `pending` branch; `todo`→`ready`).
- `apps/web-platform/server/workstream/workstream-tools.ts` — **the agent read tool's
  description string (`:44-45`) hardcodes the OLD vocab** `(backlog|todo|…|cancelled)`;
  update to the 7 new statuses. (Kieran P1-4 — a string literal `tsc` can't catch.)
- `apps/web-platform/components/workstream/issue-detail-sheet.tsx`,
  `apps/web-platform/components/workstream/workstream-board.tsx` — any `WorkstreamStatus`
  reference / optimistic-move code.
- Tests: `test/workstream-helpers.test.ts`, `test/workstream-filters.test.ts`,
  `test/components/workstream/issue-card.test.tsx`.

**Cross-consumer sweep (`hr-type-widening-cross-consumer-grep`):** run BOTH
`grep -rlnE 'WorkstreamStatus|CLOSED_STATUSES' apps/web-platform/{lib,components,server,app,test}`
AND an **unquoted** enum sweep `grep -rnE 'backlog\|todo\||\|cancelled\)' apps/web-platform`
(catches the tool-description string). **Carve-out:** the `"cancelled"` token is ALSO Stripe
subscription status (`lib/stripe-subscription-statuses.ts`, `components/settings/
billing-section.tsx`, `app/api/webhooks/stripe/route.ts`, their tests) — MUST NOT touch.
Then `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (compiler enumerates the
type consumers; the sweep enumerates the string consumers).

### Phase 1 — Board writer: lifecycle → Status automation (PR 2; needs App grant to function)

**Files to Create:**
- `scripts/board/set-board-status.sh` — extracted mutation logic (a new workflow can't be
  `workflow_dispatch`-tested from a branch — `2026-04-21-workflow-dispatch-requires-default-branch.md`).
  Contract: `set-board-status.sh <issue-node-id> <StatusName>` + a `recompute <issue-node-id>`
  entry + a `resolve-linked-issues <pr-node-id>` helper (`closingIssuesReferences` ∪ `Ref #N`
  from the PR body). Two-phase GraphQL (discover projectId + Status field id + option ids
  **once**, cache option ids as workflow env → avoids the 500k node cost cap,
  `2026-05-11-gh-graphql-cost-cap-and-branch-attribution.md`), look up/add the projectItem
  (`addProjectV2ItemById`), `updateProjectV2ItemFieldValue`, then **re-read** and exit
  non-zero on mismatch (200-without-apply, `2026-04-10-github-security-enablement-api-patterns.md`).
  Validate node ids `^[A-Za-z0-9_=-]+$`; `printf '%s\n'` + strip `\n\r` for `$GITHUB_OUTPUT`.
- `.github/workflows/board-status-sync.yml` — triggers `issues: [reopened, labeled,
  unlabeled]` + `pull_request: [opened, reopened, ready_for_review, converted_to_draft,
  closed]`; minimal `permissions`; `concurrency` per issue/PR node; mints an App
  installation token via the inline-JWT pattern
  (`2026-05-25-app-jwt-inline-mint-for-workflow-gh-api-administration-read.md`: openssl
  preflight, PEM masking, trap cleanup) from Doppler `prd_terraform` `GITHUB_APP_*`; calls
  the script. Fail-loud only (no auto-filed tracking issue). Match `auto-label-security.yml`
  house style. `issue closed → Done` stays a **GitHub built-in** (already configured).
- `scripts/board/set-board-status.test.sh` — thin: mocks `gh`, asserts event→Status for the
  logic-carrying cases (blocked add/remove, pending, reopened recompute, PR ready vs draft,
  PR closed-unmerged, PR→issue `Ref #N` resolution). Use the repo's `.test.sh` convention
  (verify `ls plugins/*/test`, `find . -name '*.test.sh'`).

**Operator prerequisite (blocks *function*, not merge):** App `organization_projects: Read
and write` grant + org consent (IaC section). Until then the workflow fails loud (403).

### Phase 2 — App Workstream tab reads the real board Status (PR 3; needs App read grant)

**No migration.** Resolve the single board from config:
`SOLEUR_KANBAN_PROJECT_NUMBER` (=2) + `SOLEUR_KANBAN_ORG` (=jikig-ai) in `.env.example` +
Doppler. (The per-workspace `workspaces.github_project_v2_number` column is **deferred** —
tracked below — added only when a second board exists.)

**Files to Edit:**
- `apps/web-platform/server/github-read-tools.ts` — add a bounded GraphQL read (Octokit
  `.graphql()`, precedent `server/inngest/functions/_cron-safe-commit.ts`) fetching each
  issue's `projectItems(first:5){ nodes { project { number } fieldValueByName(name:"Status"){ ... on ProjectV2ItemFieldSingleSelectValue { name } } } }`;
  return the Status name for the configured project number. Needs App `organization_projects:
  read` (same grant).
- `apps/web-platform/server/workstream/get-workstream-issues.ts` — when the configured
  project number is set, fetch board Status; degrade-safe: a board-read failure falls back
  to label derivation + `reportSilentFallback` (never throw).
- `apps/web-platform/lib/workstream.ts` — extend `BoardIssueInput` with optional
  `boardStatus?: string`; `deriveColumn` **prefers** a mapped board Status; add
  `boardStatusToWorkstreamStatus` (board name → enum).
- `apps/web-platform/components/workstream/workstream-board.tsx` — refresh-failure UI via
  `error && data` (`2026-06-26-swr-refresh-failed-keep-stale-data-use-error-and-data.md`).
- C4: add the `api -> github` edge to `model.c4`.
- Tests: `test/workstream-helpers.test.ts` (board-prefers + fallback), `test/server/*get-workstream-issues*`.

## Deferred (create tracking issues — `wg-when-deferring-a-capability-create-a`)
1. **Per-workspace board resolution** (`workspaces.github_project_v2_number` migration +
   `getWorkspaceProjectNumber` accessor) — when a non-Soleur workspace maintains its own
   board. Re-eval: first second-board request.
2. **Skill auto-labeling** — one-shot/fix/ship auto-apply `blocked`/`pending`/`ready`
   labels at fork/deferral/plan-approved moments. Manual labels work meanwhile.
3. **`ready`-column automation** (plan-approved → Ready) — lowest-signal trigger; `ready`
   stays a manual label.
4. **`ci/board-sync-broken` auto-issue** — add only if fail-loud + `gh run list` proves
   insufficient.

## Acceptance Criteria

### Pre-merge — Phase 0
- [ ] `WorkstreamStatus` = `backlog|ready|in_progress|in_review|blocked|pending|done`;
      `grep -c '"cancelled"' apps/web-platform/lib/workstream.ts` = 0.
- [ ] `workstream-tools.ts` tool description lists the 7 new statuses; `grep -c 'cancelled' apps/web-platform/server/workstream/workstream-tools.ts` = 0.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] Stripe files unchanged (`git diff --name-only` contains none of `stripe-subscription-statuses.ts`, `billing-section.tsx`, `webhooks/stripe/route.ts`).
- [ ] `./node_modules/.bin/vitest run test/workstream-helpers.test.ts test/workstream-filters.test.ts` green.

### Pre-merge — Phase 1
- [ ] `bash scripts/board/set-board-status.test.sh` green, incl. `reopened`, `PR closed-unmerged`, `blocked`-removed recompute, and `Ref #N` PR→issue resolution.
- [ ] `actionlint .github/workflows/board-status-sync.yml` clean; embedded shell `bash -n` on the extracted script.
- [ ] `grep -c 'GITHUB_TOKEN' .github/workflows/board-status-sync.yml` = 0 for the mutation step (App token only).
- [ ] `set-board-status.sh` re-reads Status post-mutation and exits non-zero on mismatch.

### Pre-merge — Phase 2
- [ ] `deriveColumn` unit test: `boardStatus:"Pending"` → `pending` even when labels derive `backlog`; no `boardStatus` → label fallback.
- [ ] Board-read failure → label-derived issues + `reportSilentFallback`, no throw.
- [ ] `tsc --noEmit` clean; `c4-code-syntax.test.ts` + `c4-render.test.ts` green after the `api -> github` edge.

### Post-merge (operator)
- [ ] **[consent-gated]** Grant the Soleur GitHub App `organization_projects: Read and write`; org owner approves. `automation-status: UNVERIFIED` — /work Playwright-attempts the request first, then hands org-approval to the operator with a `playwright-attempt:` line.
- [ ] After the grant: close a test issue / add `blocked` / open a draft PR with `Ref #N` and confirm the **issue** card moves; `gh run list --workflow=board-status-sync.yml -L 3` = `conclusion=success`.
- [ ] ADR-091 committed + `api -> github` C4 edge renders in the containers view.

## Domain Review
**Domains relevant:** Product (advisory), Engineering/Architecture (via ADR section).

### Product/UX Gate
**Tier:** advisory. **Decision:** auto-accepted — data-plumbing + vocabulary change to the
already-designed board (#5659, operator-signed-off 2026-06-26); no new page/component/
interactive surface (Phase 0 edits `lib/workstream.ts` + a generic column renderer; Phase 2
edits server read path). Column count stays 7; styling unchanged. Mechanical UI-surface
override did NOT fire. **Agents invoked:** none. **Skipped specialists:** ux-design-lead
(N/A — no new UI surface), copywriter (no user-facing copy). **Pencil available:** N/A.

### GDPR / Compliance (2.7)
Advisory, no critical findings. No migration in this cut; board read exposes issue
titles/state already exposed by #5659. No new special-category data or lawful-basis
trigger.

## Risks & Sharp Edges
- **PR→issue linkage:** Soleur bot PRs use `Ref #N`, so `closingIssuesReferences` is empty
  — parse `Ref #N` from the PR body/title (∪ closingIssuesReferences for `Closes` PRs).
- **New workflow can't be pre-merge dispatch-tested** — mutation logic in a script with a
  mocked-`gh` test; verify end-to-end post-merge via a real event.
- **App may lack `organization_projects`** (`2026-05-04-...app-token-lacks-actions-write.md`)
  — the one operator consent step; workflow fails loud until granted.
- **GraphQL 500k node cost cap** — two-phase fetch; cache field/option ids in workflow env.
- **GitHub returns 200 without applying** — always re-read Status after the mutation.
- **`$GITHUB_OUTPUT` / log injection** — `printf '%s\n'` + strip `\n\r`; validate node ids.
- **`cancelled` shared with Stripe** — Phase 0 sweep excludes stripe/billing files.
- **`recompute` lossiness** — can't reconstruct a manual Ready/Pending; derives In review vs
  In progress from PR draft/ready state.
- **ADR number race** — re-confirm the next free number at write time.
- **Two divergent kanbans** — resolved by board-canonical + app *prefers* board Status.

## Test Scenarios
1. Phase 0: open + `priority/p2-medium` → `backlog`; closed not_planned → `done` (not
   `cancelled`); open + `pending` → `pending`; `workstream_issues_list` tool description
   shows the 7 statuses.
2. Phase 1: fixture events → correct Status: `blocked` add → Blocked; `blocked` remove →
   recompute; issue reopened → recompute; PR opened draft (`Ref #N`) → linked issue In
   progress; PR ready → In review; PR closed-unmerged → recompute; PR merged → issue closes
   → Done (built-in).
3. Phase 1 idempotency: re-firing an event yields the same Status.
4. Phase 2: `boardStatus:"Ready"` overrides label-derived `backlog`; unset project number →
   label fallback; board-read 5xx → fallback + `reportSilentFallback`, no throw.
