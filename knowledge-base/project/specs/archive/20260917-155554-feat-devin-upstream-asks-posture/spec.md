---
title: "Upstream asks to Cognition — Devin Cloud capability parity"
status: draft
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-17-devin-upstream-asks-cognition-brainstorm.md
issue: 8160
created: 2026-09-17
---

# Spec: Upstream asks to Cognition (Devin Cloud capability parity)

## Problem Statement

Soleur Cloud Mode (#8159, shipped via PR #8155) degrades honestly around Devin Cloud capabilities that only Cognition can close — plugin subagents, plugin/repo hook dispatch, an interactive ask primitive, and several unverified contract surfaces. Issue #8160 tracks filing and tracking the upstream requests; nothing has been filed yet, no channel is documented, and nothing detects when upstream ships. The measured evidence (two-arm probe 2026-09-15) is already public in this repo — the work is packaging it into filings Cognition can act on, sending them through the documented channel, and arming detection.

## Goals

- **G1.** A committed `upstream-asks.md` evidence package in this spec directory, following the `upstream-reports.md` convention (measured sections, each citing the command/probe that produced it), carrying three asks: (a) hook dispatch as a doc-vs-measured discrepancy across ALL registries and events, (b) plugin subagents parity FR naming the per-arm substrate divergence, (c) a contract-semantics documentation bundle.
- **G2.** The package passes `scripts/upstream-report-scrub.sh` AND the CLO disclosure guardrails (capability deltas only; no org/account IDs, session IDs/URLs, VM internals, env-marker enumeration, or billing posture; one-line DPA disclaimer; capability gap, never vulnerability framing).
- **G3.** Filings land: full package emailed to `support@cognition.ai`; the hook-dispatch arm additionally filed via Devin CLI `/bug`. Agent drives submission to the identity boundary; operator completes send/authenticate only.
- **G4.** A scheduled docs-drift watcher (established `scheduled-*-drift.yml` pattern) diffs `docs.devin.ai` plugin-ecosystem §Current limitations + the Devin CLI changelog, alerting when an upstream capability ships or docs change.
- **G5.** #8160 records the posting log (destinations, URLs, dates) and a `<!-- soleur:followthrough … -->` directive binding the drift watch; the INSTRUCTIONS.md upstream-requests register is updated with filed-status.

## Non-Goals

- **NG1.** No DPA/processor negotiation with Cognition (#8161 — separate legal track).
- **NG2.** No full-parity posture re-evaluation (#8162 — deferred design alternative).
- **NG3.** No new probe arms — unmeasured items (`requiredPlugins` clean-account, `PostCompaction`, `/handoff` `.devin/` sync) file as documentation requests; measurement stays in #8172.
- **NG4.** No changes to shipped Cloud Mode detection/fallback code.
- **NG5.** No new upstream-ask productization — `Productize Candidate: upstream-ask skill` is a deferred-item filing, not scope.

## Functional Requirements

- **FR1. Evidence package.** `knowledge-base/project/specs/feat-devin-upstream-asks-posture/upstream-asks.md` with a section-to-filing mapping table (upstream-reports.md convention) and three sections:
  - **§1 Hook dispatch (defect arm).** All registries (plugin `hooks.json`, `.devin/config.json`, `.claude/settings.json`), all events incl. PostCompaction. Frames the doc-vs-measured discrepancy: official docs claim cloud runs `command` hooks for every event except SessionStart/SessionEnd; two-arm probe measured zero dispatch incl. `matcher:""` catch-all. Cites `cloud-probe.md` + `envelope-capture.md` by artifact, not transcript.
  - **§2 Plugin subagents (parity FR).** `agents/**/*.md` roster loadable as cloud subagent types; names the substrate divergence (`run_subagent`/`run_workflow` present in web-app arm, absent from DRS sandbox catalog, `subagents_enabled` key).
  - **§3 Contract-semantics bundle (documentation request).** `permissionDecision:"ask"/"defer"` behavior, `PermissionRequest` event dispatch, `.cwd` envelope field parity, SessionStart source-matcher semantics (measured dead locally — `""`-only), `ask_user_question` unattended semantics (blocking `message_user` stalls indefinitely — document intended behavior; auto-approve would fail the ack gate open), `requiredPlugins` marginal effect / manifest precedence.
- **FR2. Scrub + legal gate.** `scripts/upstream-report-scrub.sh` exits 0 on the artifact; a manual pass asserts the CLO guardrails (identifier classes above) and the DPA disclaimer line is present verbatim: *"capability-parity request only; any personal-data workflows remain subject to a separate Art. 28 DPA."*
- **FR3. Filing.** Email the package to `support@cognition.ai` (documented FR channel per `docs.devin.ai/admin/security`); file the §1 arm via `/bug`. Posting log recorded in the artifact (destination, date, URL/conversation ID when returned).
- **FR4. Drift watch.** New `.github/workflows/scheduled-devin-docs-drift.yml` on the `scheduled-*-drift.yml` pattern: scheduled diff of the plugin-ecosystem §Current limitations page and the CLI changelog; on change, file/alert per the established drift-report convention (a GitHub issue or an entry on the drift register the sibling watchers use).
- **FR5. Tracking metadata.** #8160 body gains the posting log + `<!-- soleur:followthrough script=… earliest=… -->` directive pointing at the drift watch; `plugins/soleur/devin/INSTRUCTIONS.md` upstream-requests block updated to "filed" status with the filing date/channel.

## Technical Requirements

- **TR1.** All evidence citations point at committed repo artifacts (`cloud-probe.md`, `envelope-capture.md`, `devin/INSTRUCTIONS.md` §Cloud Mode) — no transcript excerpts, no session URLs, no measurement that isn't already public in this repo.
- **TR2.** The drift watcher is a NEW non-blocking check — it follows `wg-dark-launch-deploy-gates` posture: observes and reports, never gates a deploy.
- **TR3.** Filings cite `docs.devin.ai` pages with fetch date (vendor-terms-drift convention).
- **TR4.** Email submission: agent composes and drives to the identity boundary (vendor-tickets-are-playwright-driveable precedent); operator handoff is limited to send/authenticate — never "paste this whole thing yourself" as a designed step.

## Observability

- **Surface:** the drift watcher IS the observability surface for "upstream shipped."
- **signal:** scheduled workflow run result + drift report issue/entry.
- **alert_channel:** GitHub issue notification (existing scheduled-*.yml convention).
- **discoverability_test:** `gh run list --workflow=scheduled-devin-docs-drift.yml --limit 5` — runs without SSH.
- **owner:** engineering (issue #8160).

## Acceptance Criteria

- [ ] `upstream-asks.md` committed, scrub-clean (script exit 0), CLO guardrail pass recorded
- [ ] Email sent to `support@cognition.ai` with the full package; `/bug` report filed for §1
- [ ] `scheduled-devin-docs-drift.yml` merged and observed running (non-blocking) at least once
- [ ] #8160 updated: posting log + followthrough directive; INSTRUCTIONS.md register shows filed status
- [ ] Deferred-item issues filed: `upstream-ask` productize candidate; #8159 residual-scope reconciliation noted

## User-Brand Impact

- **Artifact:** the Cognition upstream-request package + the Devin cloud posture decision
- **Vector:** mis-scoped filing could imply sub-processor intent for personal data before an Art. 28 DPA exists; overclaimed evidence in a permanent filing damages vendor credibility.
- **Threshold:** `single-user incident`

## Domain Review (carry-forward)

- **Product:** two asks (defect + parity FR), tracked under #8160 — agreed.
- **Legal:** clean to file; scrub identifier classes; DPA disclaimer line mandatory.
- **Engineering:** doc-vs-measured framing for hooks; contract bundle as documentation request; drift-watch + `conflicting-evidence` arm for detection — agreed.
