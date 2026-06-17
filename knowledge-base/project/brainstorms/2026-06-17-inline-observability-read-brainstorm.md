# Brainstorm: Inline Better Stack + Sentry read for workflow debugging (#5495)

**Date:** 2026-06-17
**Issue:** #5495
**Branch:** feat-5495-inline-observability-read
**PR:** #5496 (draft)
**Lane:** cross-domain
**Brand-survival threshold:** single-user incident

## What We're Building

An agent-facing **inline Sentry "read issue/event by id" CLI** with a dedicated
**read-only, auto-minted** Sentry token, a Sentry-read runbook, and wiring of both
the new and the *existing* Better Stack runbook into the four debugging skills so
agents reach for them unprompted when a no-SSH failure needs diagnosis.

This is **internal agent/operator-facing tooling**, not a user-facing product surface.

## Why This Approach (premise correction)

Issue #5495 was filed after the #5492 cutover-enumerate HTTP 500 "could not be
queried inline." Its premise — "there is no inline Better Stack log-query path, and
Sentry access is partial" — is **substantially stale**:

- **Better Stack inline read already shipped (#4751):** `scripts/betterstack-query.sh`
  (ClickHouse SQL over Doppler `prd_terraform`, read-only `BETTERSTACK_QUERY_*` creds)
  + runbook `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`.
  **No rebuild.**
- **Sentry issue-read already exists in app code:** `apps/web-platform/lib/inngest/sentry-issue-rate.ts`
  reads issues via `SENTRY_ISSUE_RW_TOKEN`; `apps/web-platform/scripts/audit-sentry-extra-text-references.sh`
  hits the org API. What's missing is a **thin, named CLI** an agent invokes mid-debug.
- **The real #5492 root cause was discoverability, not capability:** the Better Stack
  tool existed but no debugging skill wired it in, so the agent never reached for it.

Operator decision (2026-06-17): **narrow to the real gaps.** The genuine residual work
is (a) the Sentry read-by-id CLI + a read-only token, (b) skill wiring, (c) a deferred
Better Stack host-stderr coverage gap.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Do NOT rebuild Better Stack read.** `betterstack-query.sh` + runbook already ship inline read. | Verified shipped in #4751; YAGNI. |
| D2 | Build `scripts/sentry-issue.sh` — **bash-under-Doppler**, GET-only, mirroring `betterstack-query.sh`. | Matches the existing inline-read idiom; agent-invocable with no build step. |
| D3 | **Read-by-id only** (issue detail, latest event, event-by-id, by short-id). Defer read-by-tag. | #5492 pain was id/event-specific; `query=` keyword search already in `reproduce-bug`. YAGNI (CPO + repo-research). |
| D4 | **Mint a dedicated read-only Sentry token** (Issue&Event:Read, Org:Read) — **automated by a Soleur script via the Sentry API, NOT an operator UI mint.** | Operator decision (option 2 + "done by Soleur per our workflow rules"): least-privilege GDPR posture (CLO) **without** an operator hand-off (`hr-exhaust-all-automated-options-before`, `hr-never-label-any-step-as-manual-without`, never-defer-operator-actions). "Not Terraform-mintable" ≠ "not automatable" — a script hitting the Sentry internal-integration API is automation. |
| D5 | Host EU org-subdomain `jikigai-eu.sentry.io` (NOT `eu.sentry.io` — slug-rewrite trap); detect region via DSN cluster substring. | `2026-05-17-sentry-eu-region-host-rewrites-slugs`; `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency`. |
| D6 | **Wire both runbooks into the four skills.** Upgrade `reproduce-bug`/`incident`/`postmerge` (already cite raw curl) to the named CLI; close the **real gap** in `observability-coverage-reviewer` (producer-side today — never tells the agent it can *query* mid-review). | Wiring is the load-bearing half (#5492 root cause). repo-research: 3 of 4 already partially wired; reviewer is net-new. |
| D7 | **Run `soleur:gdpr-gate` at plan AND PR.** Add an Art. 30 RoPA PA8 touch (inline-read purpose + RO token identity). Runbook must NOT imply Sentry inline reads are as scrubbed as Better Stack. | New read surface over regulated EU telemetry; `sentry-scrub.ts` is key-name-only — residual PII lives in message/breadcrumb/tag *values* (CLO). `hr-gdpr-gate-on-regulated-data-surfaces`. |
| D8 | Sentry runbook obeys observability hard-rules: **no SSH** (`hr-no-ssh-fallback-in-runbooks`), **layer-citation** (`hr-observability-layer-citation`), **pull-don't-eyeball** (`hr-no-dashboard-eyeball-pull-data-yourself`). | Enforced by `ship-runbook-ssh-gate.sh` + `observability-coverage-reviewer`. |

## Open Questions (resolve at plan time)

1. **Sentry internal-integration auto-mint path.** Confirm the Sentry API supports
   creating an internal integration + generating its token programmatically, and which
   bootstrap credential authorizes it (`SENTRY_AUTH_TOKEN` scope check). If any sub-step
   genuinely cannot be automated, exhaust alternatives before any operator hand-off
   (`hr-exhaust-all-automated-options-before`) and only then file it correctly.
   Reference audits: `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md`,
   `.../2026-05-21-sentry-token-t3-resolution.md`.
2. **Token storage config:** Doppler `soleur/prd` vs `prd_terraform` (Better Stack query
   creds live in `prd_terraform`).
3. **Value-level redaction for Sentry inline reads** — does the CLI need a scrub pass (or
   an explicit operator-facing PII warning) for message/breadcrumb/tag fields the
   ingest-time key-scrub misses? (gdpr-gate load-bearing check.)

## Deferred (file as follow-up issues)

- **DEF-1 (#5499): Host `logger -t` → Better Stack coverage gap.** Arbitrary host-script stderr at
  WARN priority is NOT queryable (Vector `system_journald` ships only PRIORITY 0–2 / CRIT+;
  app-container source is WARN+ but container-only). Fixing = Vector config change with
  quota implications (`2026-06-10-betterstack-quota-diagnosis...`). The #5492 sibling
  worktree already routes *that* specific cause to gh-run Actions logs, so this is a
  general infra follow-up, not a #5495 blocker.
- **DEF-2 (#5500): Sentry read-by-tag/search CLI mode** — deferred per D3 (YAGNI).
- **DEF-3 (Productize candidate):** if read-only-token auto-mint recurs for other vendors,
  consider a generic `provision-readonly-token` skill. Not in scope now.

## User-Brand Impact

- **Artifact:** the inline Sentry read CLI (`scripts/sentry-issue.sh`), its read-only
  auto-minted Sentry token, and the Sentry-read runbook.
- **Vector:** an over-scoped or leaked observability token grants write/delete or
  cross-tenant access to production telemetry; OR an inline read surfaces un-scrubbed
  user PII (Sentry event message/breadcrumb/tag values) into agent/operator context.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering (CTO), Legal (CLO), Product (CPO). Marketing/Operations/Sales/
Finance/Support not relevant (internal agent-facing tooling; `hr-new-skills` CMO-omission
rationale: operator-facing-only CLI, no user-facing surface).

### Engineering (CTO)

**Summary:** Build `scripts/sentry-issue.sh` as a bash-under-Doppler GET-only wrapper
pinned to the org-subdomain EU host; `SENTRY_API_TOKEN` 403s on issues so it can't be
reused; the host-`logger -t` Better Stack gap is real but out of scope (sibling #5492
routes its cause to gh-run logs); wire both runbooks via the existing prose-link pattern.

### Legal (CLO)

**Summary:** An inline read CLI over Sentry/Better Stack is GDPR-defensible as a read-only
EU-resident debugging path, but it is a new disclosure surface for residual un-scrubbed PII
(message/breadcrumb/exception values the key-scrub misses) — warrants a `gdpr-gate` review
at plan/PR and an Art. 30 register (PA8) touch; do NOT reuse the RW/admin token for a read path.

### Product (CPO)

**Summary:** Affirms the agent-native parity gap (an agent debugging a no-SSH failure must
read what landed in Sentry/Better Stack); wiring is the load-bearing half and the only true
remaining wiring gap is `observability-coverage-reviewer`; ship read-by-id only, no MCP/platform.

## Capability Gaps

None. `soleur:gdpr-gate` and the `legal-compliance-auditor` agent cover the required review;
no missing agent/skill. (Each leader confirmed via repo grep.)
