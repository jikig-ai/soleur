---
date: 2026-07-04
topic: multica-primitives-adaptation
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
source_intel: knowledge-base/product/competitive-intelligence.md (Tier 3 — Multica, added 2026-07-04)
related_issues: [4672, 4673, 4674, 5292]
assessed_domains: [Product, Engineering, Marketing, Legal, Operations]
---

# Brainstorm — Adapting Multica's Product Primitives into Soleur

## What We're Building

A **sequenced program** (not one feature) that adapts a handful of Multica's *design primitives* into Soleur's hosted Command Center (`apps/web-platform`), to make Soleur's domain agents (a 68-agent roster surfaced through ~9 routable C-suite leaders) legible as accountable work — without importing Multica's shape (an engineering-team, multi-provider, daemon-fleet platform) or any of its source.

Multica (`multica-ai/multica`, ~39k stars) is an open-source "managed agents platform" where coding agents are first-class teammates on a Linear-style board. Its ICP is **engineering teams**; it has **zero business-domain agents**. So we steal primitives, not architecture. Full competitive record: `knowledge-base/product/competitive-intelligence.md` Tier 3.

**The governing design principle** (converged across CPO + CMO + COO): a non-technical founder hired Soleur to *not* run a company. So agents appear as **accountable outcomes and ambient proof**, never as **staff to dispatch**. Autopilot is the default motion; the board is opt-in observability; the inbox is the attention spine. This is the guardrail that stops every item below from recreating the "manager job" we promised to remove.

## User-Brand Impact

- **Artifact:** the Command Center surfaces touched — the severity inbox, the autopilot run path, and the workstream board actor/timeline model.
- **Vector:** a scheduled agent takes a real-world action (send/spend/publish) the founder never approved, or the inbox silently drops an `action_required` item, so the founder learns of a brand-damaging act after the fact.
- **Threshold:** `single-user incident`. Inherited by every plan derived from this brainstorm.

## Why This Sequence (reconciliation)

Original proposal led with **agents-as-teammates on the board** as "#1, highest leverage." The domain review overturned that ordering:

- **CPO:** the board has the highest *ceiling* but hands the founder a fleet to supervise — a job, not relief. The **severity inbox wins first**: pure read/notify, no new mental model, and it becomes the delivery spine for everything else.
- **CMO:** the board strengthens positioning *now* but is table-stakes within ~2 quarters; the moat is *what's on it* (finance/legal/sales agents no rival has), not the board. **Autopilot is the strongest demo** ("a company running unattended"). Board = opt-in observability; autopilot = default.
- **COO:** autopilot is a win *only* in its minimal shape — enable a curated read-only template on a cron, result lands in the inbox. Hide the trigger×mode×concurrency matrix.
- **CTO (code-grounded):** severity inbox is **S–M** (web-push already shipped; `email_triage_items` already pins by statutory class — add a severity rank + reuse the dispatch path). The board is **L** and needs an architecture ADR (no board DB table exists today — it's a pure GitHub-issue mapper). Autopilot's *full* data-driven-routines rebuild is **L**, but the minimal template-on-cron slice rides the existing `routine_runs` WORM ledger and is **M**.
- **Learnings (locked ADRs):** the substrate is already decided — inherit, don't reinvent. ADR-066 (inbox at workspace grain, multi-owner) is the direct precedent for "teammates"; ADR-005 (SDK-resume-first) already gives durable sessions; ADR-046 (registered-functions-only) means autopilot is *enable a curated template*, not *author arbitrary crons* — which is exactly the minimal shape the COO wanted.

Net: **inbox → minimal autopilot → onboarding → session-key → board (ADR-gated)**. Value and demo land in the first two; the highest-risk/highest-ceiling item comes last, deliberately.

## Key Decisions

| # | Decision | Rationale | Size | Tracker |
|---|----------|-----------|------|---------|
| D1 | **Severity inbox first**, as the notification spine | Fastest time-to-value; no fleet-management burden; reuses shipped web-push | S–M | new issue |
| D2 | Inbox = **extend** `email_triage_items`/ADR-066, add a `severity` rank (`action_required`/`attention`/`info`) + wire existing `server/notifications.ts` push to inbox events + auto-subscribe | ADR-066 already workspace-grain multi-owner; do not build a second queue | — | — |
| D3 | **Do not build two queues** — HITL approval-queue (#4672) items ARE the `action_required` tier of the inbox | CPO + COO; #4672 is the first populating source | — | #4672 |
| D4 | **Minimal autopilot** = founder enables a *curated registered template skill* on a cron → result to inbox. `run_only`/read-only first, concurrency = **skip**, run-ledger invisible | COO minimal shape; ADR-046 registered-functions-only; ADR-030 singleton-per-founder already gives skip | M | #4674 |
| D5 | Starter autopilot templates (read-only): **operator-digest, competitive-analysis, community digest, ux-audit** | Highest founder value, zero action-risk | — | — |
| D6 | **Action-taking autopilots gate through HITL #4672**; kill-switch + run-budget cap mandatory; inherit `actor:"platform"` tag + jitter-guard + "drafts everywhere/sends nowhere" | COO safety rails + ADR-030/033 invariants | — | #4672 |
| D7 | **Questionnaire onboarding pulled forward** (Tier-2 → ahead of the board): role × use_case → recommend which agents/templates to light up | De-risks the fleet-overwhelm that makes the board dangerous | S | new issue |
| D8 | **(agent, work-item) session resumption** = extend the existing `leaderId`-keyed session (ADR-005), add a durable `(leaderId, work_item_id)→session` mapping | Continuity across re-engagement; prerequisite persistence for the board | M | new issue |
| D9 | **Agents-as-teammates on the board is LAST and ADR-gated.** Read-only first (show which agent is on each work-item + timeline); assignment is a later phase | Highest ceiling, highest clone/fleet risk; no board DB table exists — needs an actor+timeline model decision | L | new issue + ADR |
| D10 | **Clone-risk mitigation:** business framing on the board (Departments → Work in Motion → Decisions Needing You), never Linear-style Todo/In-Progress/Done columns | CMO | — | — |
| D11 | **Clean-room posture (CLO GO-with-guardrails):** adapt designs only; do not read Multica Go source to write our TS; no verbatim names/schema/prose; no "Multica" trademark; no vendoring | Ideas aren't copyrightable; keeps us clean vs the "Other" license | — | this doc = G2 provenance |

## The Sequenced Program (per-item design)

### 1. Severity Inbox — the spine (S–M) · *new issue*
- **Exists:** `email_triage_items` (mig 102/111) with `statutory_class` pinning unacknowledged rows first; web-push fully shipped (`server/notifications.ts`, `push_subscriptions` mig 020, `sw-register.tsx`). Inbox is workspace-grain, multi-owner (ADR-066).
- **Gap:** binary pin, not a ranked scale; push wired to review-gate events, not inbox; no auto-subscription.
- **Build:** add a `severity` column (`action_required|attention|info`); generalize the inbox item source beyond email (task-completion, autopilot-run, approval-required); reuse the push dispatch; auto-subscribe the founder to anything they touched.
- **Risk:** low. Main call is whether to generalize `email_triage_items` or introduce a superset `inbox_item` table — decide in the plan.

### 2. Minimal Autopilot — the demo (M) · *extends #4674*
- **Exists:** `routine_runs` WORM ledger with `trigger_source` (scheduled|manual|agent) + `actor_class`; `routine-metadata.ts` `manualTrigger: allowed|confirm`; 48 registered Inngest crons; jitter-guard `cron_run_ledger`.
- **Gap:** founder can't enable/schedule a template themselves; no observe-vs-act mode surfaced; concurrency policy not modeled at the product layer.
- **Build (minimal):** a founder-facing "turn on this routine" surface over a **curated registered set** (D5), cron or manual trigger, `run_only`/read-only, result → inbox as `info`. Full user-authored triggers + act-mode + declared concurrency = the deferred **L** rebuild that #4674 tracks.
- **Constraints (inherit, don't reinvent):** ADR-046 registered-functions-only (no arbitrary-spec executor); ADR-033 `actor:"platform"` tag + deny-by-default PreToolUse; ADR-030 "drafts everywhere/sends nowhere" CHECK; concurrency = **skip** (D4).
- **Risk:** medium — scope discipline (resist the full rebuild); action-taking templates must wait for #4672.

### 3. Questionnaire Onboarding (S) · *new issue*
- role × use_case → recommend a starter set of domain agents + autopilot templates to light up. Directly answers "which of 68?" — the overwhelm that makes the board dangerous. Cheap; de-risks item 5.

### 4. (agent, work-item) Session Resumption (M) · *new issue*
- **Exists:** durable resume via `conversations.session_id` → SDK resume w/ replay fallback (ADR-005); `agent-session-registry.ts` keys on `userId:conversationId[:leaderId]` — `leaderId` already a segment.
- **Build:** durable `(leaderId, work_item_id) → conversation/session_id` mapping so re-engaging a work-item resumes the same agent thread.
- **Risk:** medium — worktree contention if two agents resume the same work-item concurrently; single-flight guard needed.

### 5. Agents-as-Teammates on the Board (L) · *new issue + ADR* — LAST
- **Exists:** `WorkstreamIssue` derives an `assigneeRole` chip from `domain/*` labels + a `user` from GitHub login; the board has **no DB table** (pure GitHub-issue mapper). Prior art: Brainstorm 2026-04-13 already gave domain leaders badges/icons + per-message `leader_id`.
- **Gap:** agents aren't first-class — no profile/presence, no comments, no timeline, no per-agent identity record.
- **Scope correction (repo-research):** the board surfaces the **~9 routable C-suite leaders** (`server/domain-leaders.ts`: cto/cmo/cfo/cpo/cro/coo/clo/cco/ceo), with the other specialists spawned *under* a leader — so it's ≈9 teammate chips, not 68. This makes the actor set far more tractable than "68 agents" implies.
- **Blocking decision (ADR):** source of truth for board actors + timeline — map bot logins → agent-actors on GitHub, **or** introduce DB `board_actors`/`board_timeline` tables. Hot-path timeline table is a WAL-risk surface → `/soleur:architecture create 'Board actor & timeline model'` before building.
- **Phasing:** read-only visibility first (which agent is on each item + timeline); assignment ("give this to the CMO") is a later phase, gated on evidence founders want the wheel.

## Tier 2 — Disposition

| Item | Verdict | Why |
|------|---------|-----|
| Questionnaire onboarding (#5) | **Pulled into the program** (item 3) | De-risks the board; cheap |
| Squads / leader-routed delegation | **Hold** | Depends on the board (item 5) + autonomous delegation → must ride HITL #4672; anti-self-loop design (task-scoped tokens + `is_leader_task`) copied only if/when delegation becomes autonomous |
| Channels (Slack/Gmail) — #4673 | **Hold** | A delivery channel for an inbox that must exist first; revisit after item 1 ships |

## Tier 3 — Explicitly NOT Adopting (recorded)

- **Multi-provider runtime (14 CLIs)** — dilutes Soleur's Claude-native vertical depth; BYOK already covers own-key/own-endpoint needs.
- **Daemon-on-user-hardware distributed execution** — wrong shape for a hosted, non-technical founder; Soleur's execution is the hosted sandbox / Agent SDK runner.
- **iOS app** — defer behind the whole Tier-1 program; a mobile `action_required` surface may matter once the inbox exists, not before.
- **Skill-import-from-URL marketplace** — Soleur's *executable* skills + `skill-security-scan` + `skills-lock` supply-chain pin already lead Multica's static-doc skills.

## Clean-Room Provenance (CLO G2)

These primitives are industry-common priors, independently derived from public patterns — **not** from Multica's source:
- **Polymorphic actor (human OR agent as assignee/author):** Linear, GitHub Actions bot actors, Jira automation.
- **Severity-ranked inbox:** email, PagerDuty, GitHub notifications.
- **Autopilot scheduled automation:** cron, GitHub Actions, Zapier.
- **(agent, work-item) session resumption:** standard checkpoint/idempotency-key pattern.

Guardrails the plans MUST encode (CLO G1–G5): (G1) do not read Multica Go source to write our TS — work from public README/behavior; (G2) this section is the independent-derivation record; (G3) no verbatim names/prose/error strings/config keys/DB schemas — Soleur-native vocabulary only; (G4) no "Multica" trademark in code/docs/UI/marketing; (G5) no vendoring/forking/`go get` of any Multica package. BSL competing-service clause: **no conflict** (it governs third parties hosting Soleur, not Soleur ingesting design ideas). 5-min patent/TM scan on "autopilot"-style agent scheduling before any public launch.

## Positioning (CMO)

> **"Not a team you manage — a company that runs itself, and shows its work."**

Ship the board as the *display case* for the moat (business agents), not the moat itself. Autopilot is the sellable narrative; the board makes it believable.

## Domain Assessments

**Assessed:** Product, Engineering, Marketing, Legal, Operations *(Sales, Finance, Support — not relevant to this internal-platform scope)*

### Product (CPO)
**Summary:** Inbox first (fastest time-to-value, no fleet burden); autopilot second; agents-as-teammates last and read-only. Pull questionnaire onboarding forward. Biggest risk: the board converts "company-as-a-service" into "a team you manage" — mitigate by showing accountable outcomes, not dispatchable staff.

### Engineering (CTO)
**Summary:** Severity inbox is S–M (web-push shipped, statutory pinning exists). Board is L with no DB table today → needs an actor+timeline ADR (WAL-risk). Autopilot minimal slice rides the existing `routine_runs` ledger (M); full data-driven rebuild is L (#4674). Session-key on (agent, work-item) is an M extension of ADR-005.

### Marketing (CMO)
**Summary:** The board strengthens positioning now, table-stakes in ~2 quarters; the moat is what's on it. Autopilot is the strongest demo. Board = opt-in observability, autopilot = default. Clone risk mitigated by business framing (not Linear columns).

### Legal (CLO)
**Summary:** GO-WITH-GUARDRAILS. Adapting these four industry-common design patterns is safe regardless of Multica's "Other" license (ideas aren't copyrightable). Encode G1–G5 clean-room guardrails; no BSL conflict; 5-min patent/TM check before launch.

### Operations (COO)
**Summary:** Autopilot is a win only in minimal shape (cron + template + result-to-inbox; hide the matrix). Read-only templates first; action-taking gates through HITL #4672; concurrency default = skip; kill-switch + run-budget cap mandatory.

## Capability Gaps
None net-new — every proposed item maps to an existing surface + a locked ADR to inherit (inbox → ADR-066 + `email_triage_items`; autopilot → `routine_runs` + ADR-030/033/046; sessions → ADR-005; board actors → Brainstorm 2026-04-13 + a new ADR). The board actor/timeline **decision** (not a capability gap) is the only genuinely new architecture, deliberately deferred to an ADR.

## Open Questions
1. Inbox: generalize `email_triage_items` in place, or introduce a superset `inbox_item` table? (plan-time)
2. Board actors: GitHub-bot-actor mapping vs DB `board_actors`/`board_timeline` — the ADR question; WAL impact is the deciding factor.
3. Autopilot budget cap: per-run token ceiling vs per-period spend cap vs both? (tie to the recurring-cost workflow gate.)

## Productize Candidate
`autopilot-template` — a registered-function template contract so any read-only Soleur skill (operator-digest, competitive-analysis, ux-audit, community) can be exposed as a founder-schedulable autopilot without bespoke wiring. File as follow-up when item 2 is planned.

## Next
Turn items 1–2 into plans first (inbox spine, then minimal autopilot). Items 3–5 enter the backlog with this brainstorm as the source of truth; item 5 opens with an architecture ADR.
