---
title: Inline Sentry read CLI + observability runbook wiring
issue: 5495
branch: feat-5495-inline-observability-read
pr: 5496
date: 2026-06-17
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
---

# Spec: Inline Sentry read for workflow debugging (#5495)

## Problem Statement

When an agent workflow hits a no-SSH production failure (e.g. the #5492
cutover-enumerate HTTP 500), the real error often lands in Sentry or Better Stack
but the agent cannot read it at the moment of debugging — so diagnosis stalls at
"exited non-zero, cause unknown."

Better Stack inline read already exists (`scripts/betterstack-query.sh` + runbook,
#4751) and Sentry issue-read exists in app code (`lib/inngest/sentry-issue-rate.ts`),
but there is **no thin, named, agent-invocable Sentry read CLI**, no **read-only
least-privilege Sentry token**, and the existing tooling is **not wired into the
debugging skills**, so agents never reach for it.

## Goals

- G1: An agent can, inline, read a Sentry issue/event **by id or short-id** (read-only).
- G2: A dedicated **read-only** Sentry token is provisioned **by automation (Soleur
  script via Sentry API), not an operator UI mint**, and stored in Doppler.
- G3: A Sentry-read runbook exists and obeys the observability hard-rules.
- G4: Both runbooks (existing Better Stack + new Sentry) are wired into the four
  debugging skills so agents reach for them unprompted.
- G5: The new read surface passes a GDPR review and is recorded in the Art. 30 register.

## Non-Goals

- NG1: Rebuilding Better Stack inline read (already ships — #4751).
- NG2: Sentry read-by-tag / saved-search CLI mode (deferred, DEF-2).
- NG3: Closing the host-`logger -t` → Better Stack coverage gap (deferred, DEF-1; Vector
  config + quota change; #5492 sibling already routes its cause to gh-run logs).
- NG4: A Sentry MCP server or any observability "platform" surface.
- NG5: Any user-facing UI.

## Functional Requirements

- FR1: `scripts/sentry-issue.sh` — bash-under-Doppler, GET-only, mirroring
  `betterstack-query.sh`'s flag/output conventions (JSONEachRow-friendly output,
  non-zero exit on API failure). Supports: issue detail by id/short-id, latest event
  for an issue, event by id. (G1, D2, D3)
- FR2: Host pinned to the EU org-subdomain `jikigai-eu.sentry.io` (NOT `eu.sentry.io`);
  region detected via DSN cluster substring; 401 = scope-not-ownership probe path. (D5)
- FR3: A Soleur provisioning path (script or runbook-driven automated step) that creates
  a read-only Sentry internal integration (Issue&Event:Read, Org:Read) via the Sentry
  API and stores the token in Doppler — **no operator UI mint**. (G2, D4)
- FR4: Runbook `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md` —
  copy-paste authenticated read commands, layer-citation, zero SSH steps. (G3, D8)
- FR5: Wire references to the named Sentry CLI + both runbooks into:
  `plugins/soleur/skills/reproduce-bug`, `incident`, `postmerge`, and
  `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`
  (the last is the true net-new wiring gap). (G4, D6)
- FR6: Art. 30 register PA8 touch noting the inline-read purpose + RO token identity. (G5, D7)

## Technical Requirements

- TR1: Token least-privilege — read-only scopes only; do NOT reuse `SENTRY_ISSUE_RW_TOKEN`
  (event:admin) or `SENTRY_AUTH_TOKEN` (project:write) for the read path. (D4, CLO)
- TR2: `SENTRY_API_TOKEN` 403s on the issues endpoint — not reusable for issue reads. (CTO)
- TR3: No operator-mint blocking step (`wg-block-pr-ready-on-undeferred-operator-steps`);
  if a bootstrap sub-step resists automation, exhaust alternatives first
  (`hr-exhaust-all-automated-options-before`) before filing it correctly.
- TR4: Observability hard-rules: `hr-no-ssh-fallback-in-runbooks`,
  `hr-observability-layer-citation`, `hr-no-dashboard-eyeball-pull-data-yourself`.
- TR5: Sentry inline-read PII posture — the CLI/runbook must not imply Sentry reads are
  as scrubbed as Better Stack; `sentry-scrub.ts` is key-name-only, residual PII lives in
  message/breadcrumb/tag values. gdpr-gate decides if a value-level scrub/warning is needed. (D7)

## Acceptance Criteria

- [ ] AC1: `scripts/sentry-issue.sh <issue-id>` returns the issue detail + latest-event
      stderr inline (read-only), under Doppler, no SSH. (G1)
- [ ] AC2: A read-only Sentry token exists in Doppler, minted by automation with no
      operator UI step; its scopes are Issue&Event:Read + Org:Read only. (G2)
- [ ] AC3: `sentry-issue-read.md` runbook exists, cites the observability layer per signal,
      and contains zero SSH steps (passes `ship-runbook-ssh-gate.sh`). (G3)
- [ ] AC4: `observability-coverage-reviewer` instructs the agent it can query Better
      Stack/Sentry mid-review; `reproduce-bug`/`incident`/`postmerge` reference the named CLI. (G4)
- [ ] AC5: `soleur:gdpr-gate` run clean on the plan and on the PR diff; Art. 30 PA8 updated. (G5)
- [ ] AC6: Deferred items DEF-1 / DEF-2 filed as issues; PR body uses `Closes #5495`.

## Open Questions

See brainstorm `## Open Questions` — Sentry internal-integration auto-mint API path +
bootstrap credential; Doppler config choice; value-level redaction decision.
