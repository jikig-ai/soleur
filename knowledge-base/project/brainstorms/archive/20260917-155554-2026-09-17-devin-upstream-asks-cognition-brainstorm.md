# Brainstorm: Upstream asks to Cognition (Devin Cloud capability parity)

**Date:** 2026-09-17
**Issue:** #8160 (parent: #8159, shipped via PR #8155 on 2026-09-16)
**Branch:** `feat-devin-upstream-asks-posture`
**Draft PR:** #8240
**Status:** Complete — ready for plan

## What We're Building

A structured, measured-evidence **upstream-request package to Cognition** covering the Devin Cloud capability gaps Soleur's Cloud Mode degrades around — filed through Cognition's documented channel (`support@cognition.ai` email + Devin CLI `/bug` for the defect arm), scrubbed for public-adjacent disclosure, and tracked by a scheduled docs-drift watcher so a shipped capability is detected, not noticed.

## Context

- #8159 ("Soleur Cloud Mode") shipped honest degradation on 2026-09-16. Three follow-ups were deferred from its brainstorm; the operator scoped this brainstorm to **#8160 only** (upstream asks). #8161 (Cognition DPA gate for personal-data cloud sessions) and #8162 (full-parity posture) remain parked.
- Evidence base is already measured and public: two-arm cloud probe (`specs/feat-devin-cloud-session-parity/cloud-probe.md`, sessions `4c574cf0…`/`b9cf2c02…`, 2026-09-15) and local envelope-capture (`specs/feat-settings-matcher-devin-audit/envelope-capture.md`). Headline finding: **zero hook dispatch on every registry surface** including a `matcher:""` catch-all — while official docs claim cloud runs `command` hooks for every event except SessionStart/SessionEnd. That makes the hooks ask a **doc-vs-measured discrepancy** (two resolution paths for Cognition: fix dispatch or fix docs), not a plain feature gap.
- Prior art: `upstream-reports.md` convention (measured evidence sections, prefer existing upstream threads, withdraw-on-nonreproduction, `scripts/upstream-report-scrub.sh` asserted on file AND posted body), `upstream-pencil-report.md` (filed to a vendor repo), and the follow-through convention for tracking.

## Why This Approach

Measured discrepancies get actioned; unevidenced feature requests get queued. The probe record is already committed publicly, so the package's marginal disclosure risk is low and scrub-able. `support@cognition.ai` is the only documented FR channel (no public tracker or RFC process exists; Slack Connect is Teams-tier). A docs-drift watcher is the cheapest mechanism that converts "vendor ships it" from an unmonitored hope into a detected event — it reuses the established `scheduled-*-drift.yml` pattern.

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Scope | #8160 only — upstream asks | Operator selection. #8161 (DPA) and #8162 (parity posture) stay parked; each notes this brainstorm as context. |
| 2 | Packaging | Two asks + contract bundle | (a) **Hook dispatch** — filed as measured defect/doc-discrepancy covering ALL registries (plugin `hooks.json`, `.devin/config.json`, `.claude/settings.json`) and ALL events incl. PostCompaction; (b) **plugin subagents** — parity FR naming the per-surface substrate divergence (`run_subagent`/`run_workflow` exist in web-app arm, absent from DRS sandbox catalog); (c) **contract-semantics bundle** — `permissionDecision:"ask"/"defer"`, `PermissionRequest` event, `.cwd` envelope field, SessionStart source-matchers, `ask_user_question` unattended semantics, `requiredPlugins` marginal effect. CPO+CTO consensus: mixing a defect report with FRs in one body weakens both. |
| 3 | Channel | `support@cognition.ai` email + `/bug` | Email carries the full three-part evidence package; the hook-dispatch arm additionally goes through Devin CLI's built-in `/bug` (it is arguably a defect, not just an FR). In-app Feedback rejected — weaker for multi-part evidence. |
| 4 | Detection | Scheduled docs-drift watch | New `scheduled-*-drift.yml`-pattern workflow diffing `docs.devin.ai` plugin-ecosystem §Current limitations + CLI changelog. Complements (not replaces) `cloud-detect.sh`'s `conflicting-evidence` arm (ADR-221 forward-defense for partial landing) and the #8172 re-probe checklist. |
| 5 | Disclosure discipline | Scrub + capability-delta text only | CLO guardrails: no org/account IDs, session URLs/IDs, VM internals (`/opt/.devin/*`), env-marker enumeration, or billing posture. Cite the public capability matrix, not transcripts. One-line DPA disclaimer: *"capability-parity request only; any personal-data workflows remain subject to a separate Art. 28 DPA."* `upstream-report-scrub.sh` on the artifact; grep for third-party undertakings (hr-third-party-content-grep-on-undertaking). |
| 6 | Tracking | #8160 stays the register | Posting log (destinations + URLs/date) appended to #8160 with a `<!-- soleur:followthrough … -->` directive pointing at the drift watch. No new register doc — #3163/#3835/#7490 precedent tracks upstream asks as issues. |
| 7 | Filing mechanics | Agent drafts + drives to auth boundary | Vendor-ticket precedent: agent composes and drives submission; the only operator step is identity (send from operator mailbox / authenticate the session). Not "operator pastes and submits." |
| 8 | Productize candidate | `upstream-ask` skill | Third recurrence of the same workflow (pencil #4859, claude-code #7490, now Cognition #8160): draft measured-evidence package → scrub → post → log. File as deferred-item issue; NOT this brainstorm's scope. |

## User-Brand Impact

- **Artifact:** the Cognition upstream-request package + the Devin cloud posture decision
- **Vector:** worst case — a mis-scoped ask or posture commits Jikigai to running user personal data through an uncontracted sub-processor (Cognition), an Art. 28 breach for even one beta user; secondary — overclaimed evidence in a permanent public-adjacent filing damages credibility with the vendor Soleur depends on.
- **Threshold:** `single-user incident` (auto, per #5175)

## Open Questions

- Cognition's response behavior is unknown — no SLA on `support@cognition.ai` FRs; the drift watch is the detection backstop either way.
- Unmeasured asks in the contract bundle (`requiredPlugins` clean-account arm, `PostCompaction`, `/handoff` `.devin/` sync) ship as *documentation requests*, not defect claims — their probe arms live in #8172.
- Cognition ToS/AUP was never formally reviewed (CLO flagged, documentary gap only — probe stayed within acceptable use). If plan wants it closed rather than flagged, `recommended-tools.md#ai-vendor-terms` applies.
- #8159's GitHub issue is still OPEN despite PR #8155 merging — reconcile residual scope or close during this work.

## Non-Goals

- No DPA/processor negotiation with Cognition (#8161 — separate legal track).
- No full-parity posture re-evaluation (#8162 — deferred design alternative).
- No new probe arms — measurement gaps route to #8172.
- No changes to shipped Cloud Mode code; this feature produces filings + a watcher + tracking metadata.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Two separate asks — hooks filed as a measured defect, subagents as an ecosystem-parity FR — tracked under #8160; the INSTRUCTIONS.md upstream-requests block already functions as the register-of-record. Filing itself is an operator-account action (personal tenant channel).

### Legal (CLO)

**Summary:** CLEAN to file — an FR is not processing; keep text to capability deltas, scrub identifiers, add the one-line DPA disclaimer, prefer the public/trackable channel, and never frame a capability gap as a vulnerability.

### Engineering (CTO)

**Summary:** Asks correctly scoped; file hooks as a doc-vs-measured discrepancy with the probe repro attached, bundle the unverified contract items as documentation requests, and detect landing via docs-drift watch + the `conflicting-evidence` convergence arm.

## Capability Gaps

None reported by any domain leader — this is tracking/process work correctly labeled `type/chore`. Documentary gap noted by CLO (no Cognition ToS memo on file) is an Open Question, not a blocker.
