---
title: Inngest Routines management UI + Concierge delegation
date: 2026-06-15
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-routines-management
pr: "#5342"
---

# Brainstorm: Inngest Routines Management UI + Concierge Delegation

## What We're Building

An operator-facing **Routines** management surface in the Soleur web-platform (`apps/web-platform`)
that makes the company's 42 existing Inngest cron routines *visible and operable* from the web, plus
a deferred **Concierge** delegation path for authoring routines.

The 42 routines (`server/inngest/cron-manifest.ts` → `EXPECTED_CRON_FUNCTIONS`) already do real
autonomous work (daily triage, content publishing, legal audits, competitive analysis, payment-failure
handling). Today they can only be inspected by reading code and triggered via the `soleur:trigger-cron`
CLI/route. There is **no web UI**.

**Scope decision (operator, 2026-06-15): visibility-first, with the Concierge tab pulled into scope.**
Initial decision was visibility-first v1 with Concierge authoring deferred; operator follow-up
(2026-06-15) brought the **Concierge chat window** into scope ("Add the chat window with concierge to
add routines with concierge"). The engineering reality (Decision 2) is unchanged — the chat flow must
reflect the honest PR-scaffold path.

**In scope:**
- **Routines tab** — all routines grouped by domain; each row shows frequency (human-readable cron),
  last-run (status/date/duration), owner-role chip, On/Archived state, a **Run now** button, and an
  overflow menu.
- **Recent Runs tab** — reverse-chronological execution history across all routines, backed by a
  durable run-log (status, started-at, duration, trigger source: scheduled / manual / agent).
- **Debug mode** — manual off-schedule trigger ("Run now"), routed through the *existing*
  `manual-trigger-allowlist` + `POST /api/internal/trigger-cron`, with a deny-by-default confirmation
  gate for high-side-effect routines.
- **Concierge tab (chat window)** — delegate routine **create / edit / remove** to the Concierge agent
  via a chat surface. The conversation flow: operator describes the routine → Concierge proposes a
  **generated-routine review card** (name, domain, owner role, frequency + raw cron, target file,
  "what it will do") → operator reviews/edits → Concierge **tests it (dry-run, no real side-effects)**,
  reads back the app output, and **verifies correctness** → only then offers **confirmation → Open PR**.
  "Create" = the Concierge **opens a PR** scaffolding a new `cron-*.ts` (routines are deployed code; see
  Key Decision 2); it goes live on merge + deploy, NOT instantly. The test-verify loop runs a dry-run
  sandbox of the drafted logic for new routines; for **edit**, it re-runs the existing routine and
  verifies against live; **remove** opens a PR deleting the cron + its 5 registry entries.

**Sequencing note:** the visibility surface (Routines + Recent Runs + debug Run-now) is independently
shippable and lower-risk; the Concierge authoring path depends on a net-new agent capability (the
5-registry PR-scaffold — see Capability Gaps) that should be built before its "create" path is wired.
Recommend implementing as two PRs behind the same feature surface rather than one monolith.

## Why This Approach

Visibility is the daily value (CPO): "is the autonomous company actually running, and did the last run
succeed?" Today that answer requires reading code and Inngest logs. Authoring is the long tail and is a
materially larger, riskier build that depends on a new agent capability that does not yet exist. Shipping
the read + debug-trigger slice first delivers value in days, reuses backend primitives that already exist,
and lets us validate the surface before investing in PR-scaffold authoring.

The PR-scaffold create model is the only *honest* framing: routines are deployed code behind a CI/deploy
gate, so "instant live routine" would overpromise persistence the architecture does not have.

## User-Brand Impact

- **Artifact:** the Routines management surface + the `Run now` / manual-trigger path (`POST
  /api/internal/trigger-cron`) and the durable run-log.
- **Vector:** an off-schedule or agent-initiated run of a production-touching routine (content publish,
  payment handling, legal audit, external egress) fires real side-effects with no human in the loop, or
  a run-log/audit record that misattributes an agent action to the operator — eroding accountability for
  autonomous actions taken in the operator's name.
- **Threshold:** `single-user incident`.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Visibility-first v1**; Concierge authoring + verify loop deferred to v2 | CPO: observability is the daily value; authoring is larger/riskier and depends on an unbuilt capability. |
| 2 | **"Create routine" = Concierge opens a PR** scaffolding a `cron-*.ts` (not a runtime create) | CTO: routines are deployed code behind 5 lockstep registry edits + a hardcoded `routeEntries.length === 56` guard; runtime create is impossible. Verify-before-confirm only works for editing/re-running existing routines. |
| 3 | **Routine metadata via a sidecar map** `Record<fnId, {domain, ownerRole, scheduleLabel}>` in a new client-free leaf, with a parity test asserting `keys(sidecar) === EXPECTED_CRON_FUNCTIONS` | CTO: must NOT change the `EXPECTED_CRON_FUNCTIONS` array element type (breaks set-equality test + every importer); must NOT use per-function exports (forces importing modules that throw on missing `INNGEST_SIGNING_KEY` outside build — the reason the client-free leaf exists, #4734). |
| 4 | **Durable Supabase run-log** for execution history (+ WORM audit ledger) | `list-runs.ts` is hardwired to `finance.payment_failed` (not a cron-run lister); Inngest `/v1` is loopback-gated (`127.0.0.1:8288`) and retention-bounded — "full history" needs a durable store. Enables CLO's actor-class attribution. |
| 5 | **Audit ledger captures actor-class** (HUMAN operator vs CONCIERGE AGENT) + delegating principal + invocation mode (scheduled/manual/agent-test) + before/after diff for edits | CLO: Art. 5(2) accountability spine; an agent action is "operator-via-agent," never anonymous automation. Mirrors existing WORM patterns (`audit_byok_use`, `action_sends`). |
| 6 | **Debug-mode Run-now routes through the existing allowlist**, never a bypass endpoint; tighten financial/egress/deletion routines to deny-by-default (scheduled-only or per-routine confirmation) | CTO + CLO: off-schedule runs fire real prod work; the allowlist (currently derives from ALL crons) must gain a curated protected subset. Parity-tested (`trigger-cron-allowlist-parity.test.ts`). |
| 7 | **Concierge v2 test-runs are dry-run/sandbox by default** (block email/publish/financial/egress/delete) with a visible "DRY RUN — no external effects" marker | CLO: running an unapproved routine against real systems is the highest risk; real run only on explicit operator confirmation. |
| 8 | New internal/agent-callable routes registered in `PUBLIC_PATHS` in the same PR; heartbeats gated on final attempt | learnings: 2026-06-01 (PUBLIC_PATHS or 307→/login), 2026-06-12 (don't page on transient retry faults). |
| 9 | Visual design: `knowledge-base/product/design/routines/routines-management.pen` — 4 screens: (1) Routines tab grouped-by-domain, (2) Recent Runs, (3) Run-now confirm modal, (4) Concierge chat (draft → dry-run test+verify → Open PR) | Mock-confirmation gate before implementation; matches operator reference mock. Note: Concierge mock's target-file path is illustrative — real path is `apps/web-platform/server/inngest/functions/cron-*.ts`. |

## Open Questions

1. **"Concierge" naming.** "Concierge" is already the KB-chat agent surface (#3451/#3326). The
   routine-authoring chat tab likely *is* that same agent acting in a new mode — confirm whether the tab
   is literally "delegate to the existing Concierge" (preferred) or a distinct surface needing its own
   name. (Now in scope, so this needs resolution at plan time.)
2. **"Archived" semantics.** Is Archived a manifest/sidecar flag (display + Run-now disabled) or true
   deploy-time removal? v1 treats it as a display/disabled state; the durable toggle is a HOW decision.
3. **Run-log write path.** Does each `cron-*.ts` write its own run-log row (via shared helper in
   `_cron-shared.ts`), or does an Inngest middleware write it centrally? (HOW — plan time.)
4. **Inngest `/v1` reachability from the app container** — the existing runs proxy works server-side, but
   the loopback-gate learning (2026-05-31) means the run-log is the durable source of truth and `/v1` is
   at most an enrichment. Confirm at plan time.
5. **Owner-role source of truth** — the sidecar map (Decision 3); confirm the role taxonomy
   (COO/CTO/CMO/CLO/CFO/CRO/CCO/CPO) maps cleanly onto all 42 routines.

From the wireframe pass (ux-design-lead, flagged not invented):

6. **Overflow `…` menu contents (v1).** Likely View runs / Archive / Copy cron (Edit/authoring lives in
   the Concierge tab) — confirm the exact item set.
7. **"Protected" classification source.** Is the deny-by-default flag derived automatically (routine
   touches payments/egress/deletion) or set explicitly per-routine in the sidecar? CLO posture is shown;
   the trigger rule is unspecified.
8. **Run-now gating.** Prompt called Run-now a "debug-mode" trigger; the mock renders it always-visible.
   Confirm whether Run-now is hidden outside a debug mode, or always shown (with the protected gate).
9. **Group collapse.** Group headers imply collapsibility — confirm whether v1 ships collapse/expand or
   static groups.
10. **Sort / Group dimensions.** Rendered as buttons ("Sort: Last run", "Group: Domain") — confirm the
    available sort keys and group dimensions.
11. **Recent Runs pagination / run-log depth.** Infinite scroll vs. page size vs. date filter — the
    durable run-log's pagination model is unspecified.
12. **Sharp-corner vs `rounded-xl` reconciliation.** Wireframe followed the brand guide (sharp 0px
    corners); existing codebase modals use `rounded-xl`. Reconcile at implementation.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Routine metadata must be a sidecar map (not array-type change, not per-function export) with a
parity test; `list-runs.ts` is finance-specific and unusable for cron history; "create routine" is a
PR-scaffold (5 lockstep registry edits + hardcoded route-count guard), and the test-before-confirm step is
impossible for new routines; debug-trigger must extend the existing allowlist. Top risks: create-can't-be-
runtime, full-history exceeds `/v1`, manual-trigger blast radius.

### Product (CPO)

**Summary:** Internal operator tooling, unroadmapped (closest: 3.21 Agent work visualization, #2004). Lead
v1 with visibility; frame create honestly as "Draft a routine (opens a PR)"; defer the verify loop with the
authoring path. Agent-native parity: any Run/toggle/archive/overflow action needs a callable agent tool, not
just a UI handler. Naming collision: "Concierge" already taken by the KB-chat surface.

### Legal (CLO)

**Summary:** No inbound legal threshold tripped — stays founder-grade v1. Requires a WORM audit ledger with
HUMAN-vs-AGENT actor-class + delegating principal + invocation mode; Concierge test-runs must be dry-run/
sandbox by default blocking egress/financial/publish/delete; tighten the allowlist to deny-by-default for
compliance/financial/egress/deletion routines; flag `cfo-on-payment-failed` out-of-band execution for a
financial-controls note. Recommended downstream (post-build): `soleur:gdpr-gate` / legal-compliance-auditor
on the diff.

## Capability Gaps

- **Concierge routine-lifecycle authoring (v2, Engineering).** No existing agent/skill opens a `cron-*.ts`
  PR with all five lockstep edits (route handler + array, `cron-manifest` `EXPECTED_CRON_FUNCTIONS`,
  `function-registry-count.test.ts` count, `infra/sentry/cron-monitors.tf` resource, `apply-sentry-infra.yml`
  `-target=`). `soleur:trigger-cron` covers triggering, not authoring. **Evidence:** `grep -rn "manualTrigger\|EXPECTED_CRON_FUNCTIONS"` across `plugins/soleur/skills/` shows only trigger/list skills; the 5-registry
  lockstep is documented in `knowledge-base/project/learnings/2026-06-05-new-inngest-cron-requires-five-registry-lockstep.md`.
  This gap must be filled before the v2 "create" path is implementable.

## Session Errors

- None blocking. Note: `worktree-manager.sh` warns `session-state.sh missing` (lease/lock protection
  disabled in this worktree) — non-blocking for brainstorm.
- **Pencil `open_document` is destructive on `routines-management.pen`** (#3274 adapter parse-then-blank):
  it wiped the file to a 41-byte empty doc on open. ux-design-lead recovered from git and merged the new
  screen via temp-build + JSON-merge (screens 01-03 byte-identical to HEAD). Future Pencil iterations on
  this `.pen` must use the same temp-build + JSON-merge route, not `open_document`. Commit the `.pen`
  after every edit.
- Premature commit: I committed an early partial `.pen` + low-res screenshots before the first
  ux-design-lead agent finished; reconciled to the high-res finals. Fixed workflow captured in memory.
