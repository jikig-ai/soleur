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

- [x] 0.1 Confirm Doppler `soleur/prd` reachable inline (`doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain` non-empty).
- [x] 0.2 Confirm Sentry API host `jikigai-eu.sentry.io` (org-subdomain) + region-detect via DSN cluster substring. Reuse `.test.sh` convention (`container-restart-monitor.test.sh`).

## Phase 1 — `scripts/sentry-issue.sh` (GET-only CLI; TDD)

- [x] 1.1 Write failing `scripts/sentry-issue.test.sh` (mock **both** `curl` and `doppler` per `container-restart-monitor.test.sh` `curl_args`-log; synthesized fake token): per-invocation GET + no `-d`/`--data*`/`-F`/`-T` + URL matches two-endpoint allowlist; **hostile issue-id** (`/`,`?`,`;`,`..`) rejected; assertions run with **both** RO and RW tokens; error-path stderr never contains the token; source has no `set -x`; token RO→RW fallback + warning; `--latest-event` org-scoped URL.
- [x] 1.2 Implement `scripts/sentry-issue.sh` mirroring `betterstack-query.sh` (`curl -sS --fail-with-body --max-time 30 -H "Authorization: Bearer $TOKEN"`, `set -uo pipefail`, never `set -x`):
  - [x] 1.2.1 `<issue-id>` → `GET /api/0/organizations/<org>/issues/<id>/`.
  - [x] 1.2.2 `--latest-event <issue-id>` → `GET /api/0/organizations/<org>/issues/<id>/events/latest/` (org-scoped); surface `exception.values[].value` + `stacktrace.frames[]`.
  - [x] 1.2.3 Token resolution: read `SENTRY_ISSUE_RO_TOKEN` from `doppler run -p soleur -c prd` env (`: "${VAR:?}"` guard); fall back to `SENTRY_ISSUE_RW_TOKEN` GET-only with stderr warning. RW-fallback removal trigger once RO exists.
  - [x] 1.2.4 GET-only HARDENING: fixed-method GET, no body, URL-allowlist, issue-id charset `^[A-Za-z0-9_-]+$` validated before interpolation; applies to RW path too. Map 403 → "token lacks event:read"; 401 → scope-not-ownership hint (ADR-031 glossary). Host = org-subdomain `jikigai-eu.sentry.io` (NOT `de.sentry.io`).
  - [x] 1.2.5 stderr PII banner (incl. `user.*`); optional `--redact` flag (default OFF).
- [x] 1.3 GREEN: `scripts/sentry-issue.test.sh` passes.

## Phase 2 — Auto-mint read-only token (UNVERIFIED automation)

- [~] 2.1 (API path verified unavailable — no org:admin) Attempt API mint (`POST /api/0/organizations/jikigai-eu/sentry-apps/`, `inline-read-prd`, scopes `[event:read, org:read]`) — only if an org:admin bootstrap credential is available.
- [~] 2.2 (Playwright reached authenticated form, no human gate; tool-instability → #5506) Else Playwright mint via `eu.sentry.io` dashboard (Settings → Developer Settings → New Internal Integration); capture token via `browser_evaluate` (NO screenshot of token field); record `playwright-attempt:` evidence with token redacted.
- [ ] 2.3 (blocked on #5506) Write token to Doppler `soleur/prd` as `SENTRY_ISSUE_RO_TOKEN` via stdin (no argv/history; never echo); add to `.env.example` with scope comment.
- [ ] 2.4 (blocked on #5506) CLI defaults to `SENTRY_ISSUE_RO_TOKEN`. Document working mint path in runbook re-mint section.

## Phase 3 — Runbook

- [x] 3.1 `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md`: copy-paste GET commands, layer-citation, zero SSH, "Re-minting the read-only token" section, PII-asymmetry caveat vs Better Stack.
- [x] 3.2 Verify passes `.claude/hooks/ship-runbook-ssh-gate.sh`.

## Phase 4 — Skill wiring (read each file first; heading+substring anchors)

- [x] 4.1 `observability-coverage-reviewer.md`: new step after Step-1 inventory — reviewer can query Better Stack + Sentry mid-review (the net-new gap).
- [x] 4.2 `reproduce-bug/SKILL.md`: one-line `sentry-issue.sh` + runbook pointer at the observability-first block.
- [x] 4.3 `incident/SKILL.md`: one-line pointer + update token list to prefer `SENTRY_ISSUE_RO_TOKEN`.
- [x] 4.4 `postmerge/SKILL.md`: one-line pointer at the Production Debugging note.

## Phase 5 — ADR + Art. 30

- [x] 5.1 Amend `ADR-031-sentry-as-iac.md` (`## Decision` + dated amendment): `inline-read-prd` read-only credential class + inline read-CLI pattern; Doppler `soleur/prd` storage; no C4 change.
- [x] 5.2 Art. 30 PA8 touch in `knowledge-base/legal/article-30-register.md` (inline-read purpose + RO token identity).

## Phase 6 — gdpr-gate + verification

- [x] 6.1 (gdpr work-gate: diff has no regulated-data surface — plan-time verdict stands, no Critical) Re-run `/soleur:gdpr-gate` on the PR diff; add value-level redaction only if it shows raw values without the warning.
- [x] 6.2 (scripts 115/115 incl sentry-issue 16/16; bun exit 0) Run AC verification suite (AC1–AC7).
