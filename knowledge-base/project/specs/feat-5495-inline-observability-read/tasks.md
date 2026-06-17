---
title: "Tasks: Inline Sentry read CLI + observability runbook wiring"
issue: 5495
branch: feat-5495-inline-observability-read
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-17-feat-inline-sentry-read-cli-plan.md
---

# Tasks — feat-5495-inline-observability-read

Phases are contract-before-consumer ordered. Token mint is `automation-status: UNVERIFIED` —
/work MUST attempt Playwright before any operator handoff (#5480).

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Confirm Doppler `soleur/prd` reachable inline (`doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain` non-empty).
- [ ] 0.2 Confirm Sentry API host `jikigai-eu.sentry.io` (org-subdomain) + region-detect via DSN cluster substring. Reuse `.test.sh` convention (`container-restart-monitor.test.sh`).

## Phase 1 — `scripts/sentry-issue.sh` (GET-only CLI; TDD)

- [ ] 1.1 Write failing `scripts/sentry-issue.test.sh` (mock curl): GET-only invariant, token RO→RW fallback + warning, org-subdomain host pinning, `--latest-event` org-scoped URL.
- [ ] 1.2 Implement `scripts/sentry-issue.sh` mirroring `betterstack-query.sh`:
  - [ ] 1.2.1 `<issue-id>` → `GET /api/0/organizations/<org>/issues/<id>/`.
  - [ ] 1.2.2 `--latest-event <issue-id>` → `GET /api/0/organizations/<org>/issues/<id>/events/latest/` (org-scoped).
  - [ ] 1.2.3 Token resolution: read `SENTRY_ISSUE_RO_TOKEN` from `doppler run -c prd` env (`: "${VAR:?}"` guard); fall back to `SENTRY_ISSUE_RW_TOKEN` GET-only with stderr warning.
  - [ ] 1.2.4 GET-only guard; map 403 → "token lacks event:read"; 401 → scope-not-ownership hint (ADR-031 glossary).
  - [ ] 1.2.5 stderr PII banner.
- [ ] 1.3 GREEN: `scripts/sentry-issue.test.sh` passes.

## Phase 2 — Auto-mint read-only token (UNVERIFIED automation)

- [ ] 2.1 Attempt API mint (`POST /api/0/organizations/jikigai-eu/sentry-apps/`, `inline-read-prd`, scopes `[event:read, org:read]`) — only if an org:admin bootstrap credential is available.
- [ ] 2.2 Else Playwright mint via `eu.sentry.io` dashboard (Settings → Developer Settings → New Internal Integration); record `playwright-attempt:` evidence.
- [ ] 2.3 Write token to Doppler `soleur/prd` as `SENTRY_ISSUE_RO_TOKEN` (never echo); add to `.env.example` with scope comment.
- [ ] 2.4 CLI defaults to `SENTRY_ISSUE_RO_TOKEN`. Document working mint path in runbook re-mint section.

## Phase 3 — Runbook

- [ ] 3.1 `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md`: copy-paste GET commands, layer-citation, zero SSH, "Re-minting the read-only token" section, PII-asymmetry caveat vs Better Stack.
- [ ] 3.2 Verify passes `.claude/hooks/ship-runbook-ssh-gate.sh`.

## Phase 4 — Skill wiring (read each file first; heading+substring anchors)

- [ ] 4.1 `observability-coverage-reviewer.md`: new step after Step-1 inventory — reviewer can query Better Stack + Sentry mid-review (the net-new gap).
- [ ] 4.2 `reproduce-bug/SKILL.md`: one-line `sentry-issue.sh` + runbook pointer at the observability-first block.
- [ ] 4.3 `incident/SKILL.md`: one-line pointer + update token list to prefer `SENTRY_ISSUE_RO_TOKEN`.
- [ ] 4.4 `postmerge/SKILL.md`: one-line pointer at the Production Debugging note.

## Phase 5 — ADR + Art. 30

- [ ] 5.1 Amend `ADR-031-sentry-as-iac.md` (`## Decision` + dated amendment): `inline-read-prd` read-only credential class + inline read-CLI pattern; Doppler `soleur/prd` storage; no C4 change.
- [ ] 5.2 Art. 30 PA8 touch in `knowledge-base/legal/article-30-register.md` (inline-read purpose + RO token identity).

## Phase 6 — gdpr-gate + verification

- [ ] 6.1 Re-run `/soleur:gdpr-gate` on the PR diff; add value-level redaction only if it shows raw values without the warning.
- [ ] 6.2 Run AC verification suite (AC1–AC7).
