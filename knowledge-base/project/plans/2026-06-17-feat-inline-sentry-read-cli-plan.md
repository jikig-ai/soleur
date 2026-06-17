---
title: "feat: Inline Sentry read CLI + observability runbook wiring"
issue: 5495
branch: feat-5495-inline-observability-read
pr: 5496
date: 2026-06-17
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-031 (amend)
---

# feat: Inline Sentry read CLI + observability runbook wiring (#5495)

## Enhancement Summary

**Deepened:** 2026-06-17 · **Agents:** security-sentinel, observability-coverage-reviewer, best-practices-researcher (Sentry API), Explore (precedent-diff + verify-the-negative). Gates passed: User-Brand Impact, Observability, PAT-shaped, UI-wireframe.

### Key hardenings folded in
1. **GET-only invariant rewritten allowlist-not-denylist** (security P1): fixed-method `GET` + no-body + two-endpoint URL allowlist + **issue-id charset validation** (`^[A-Za-z0-9_-]+$`) — closes path/endpoint-injection (load-bearing given the EU slug-rewrite trap). Test runs hostile inputs + covers the RW-fallback path.
2. **Token-handling invariants** (security P1): no `set -x`; stderr/stdout never contain the token (asserted); Playwright capture via `browser_evaluate` not screenshot; Doppler write via stdin (no argv/history); mock both `curl` and `doppler` in the test.
3. **RW-fallback removal trigger** — once the RO token exists the fallback branch is removed; must not become steady-state.
4. **PII/AC6 reframe**: v1 prints unredacted by design; the stderr banner is accountability not a transfer control; optional `--redact` flag; gdpr PR-diff re-run checks `user.*` tags.
5. **Observability `layer:` citation** added per failure mode (`none — operator-invoked CLI, fail-loud`).

### Conflict resolved
**EU host:** generic web docs said `de.sentry.io`; **ADR-031 (repo-specific, Sentry-support-confirmed) wins** — `de.sentry.io` is ingest-only (404s on `/api/`); the API host is the org-subdomain `jikigai-eu.sentry.io`. Plan unchanged. The `sentry-apps` creation endpoint/scope is **unconfirmed** in public docs → reinforces Playwright-primary mint.

## Overview

Give agents a thin, named, GET-only inline path to **read a Sentry issue/event by id**
during no-SSH debugging, backed by a dedicated **read-only** Sentry token that Soleur
mints by automation (not an operator UI step). Author a Sentry-read runbook and wire it
— plus the **existing** Better Stack query runbook (`scripts/betterstack-query.sh`, #4751)
— into the four debugging skills so agents reach for these unprompted.

Scope was narrowed after premise validation: Better Stack inline read already ships
(#4751), and Sentry issue-read already exists in app code (`lib/inngest/sentry-issue-rate.ts`).
The real gaps are the agent-facing Sentry CLI, the read-only token, and skill discoverability
(the actual #5492 root cause).

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "No inline Better Stack log-query path" (issue #5495) | `scripts/betterstack-query.sh` + runbook shipped #4751 | Do NOT rebuild; wire the existing runbook into skills (NG1). |
| Reuse `SENTRY_API_TOKEN` for issue reads | `SENTRY_API_TOKEN`/`SENTRY_AUTH_TOKEN` **403 on `/issues/<id>/`** — Discover/ingest scope, no `event:read` (`postmerge/SKILL.md:141`) | CLI needs an `event:read` token; only `SENTRY_ISSUE_RW_TOKEN` (event:admin) reads issues today → mint a least-privilege `event:read`+`org:read` token (D4). |
| Token "auto-minted via Sentry API" | Creating an Internal Integration needs **`org:admin`**; the broadest existing token (`SENTRY_IAC_AUTH_TOKEN`) is only `project:admin` (ADR-031). No org:admin bootstrap in Doppler. | Primary mint path = **Playwright dashboard** (presumptively automatable per #5480); API path only if an org:admin bootstrap is found. Mark `automation-status: UNVERIFIED` — /work MUST attempt Playwright before any operator handoff. |
| Token storage in Doppler `prd_terraform` (Better Stack's) | Sentry runtime tokens live in Doppler `soleur/prd` (`postmerge` reads `-c prd`); `SENTRY_IAC_AUTH_TOKEN` mirrored to `soleur/prd` | Read-only token → **Doppler `soleur/prd`** as `SENTRY_ISSUE_RO_TOKEN`. |
| Sentry API host | EU org-subdomain `jikigai-eu.sentry.io` (NOT `eu.sentry.io` — `-eu` slug-rewrite trap; ADR-031 glossary) | Pin host to org-subdomain; region via DSN cluster substring. |
| **EU host conflict** (deepen-plan): generic web docs suggested `de.sentry.io` | ADR-031 (repo-specific, Sentry-support-confirmed, documents a real PIR): `de.sentry.io` is **ingest-only — 404s on `/api/`**; org-scoped API paths MUST use the org-subdomain. Live repo code (`event-scheduled-reminder.ts`, TF provider `base_url`, `sentry-monitors-audit.sh`) uses the org-subdomain and works in prod. | **Keep `jikigai-eu.sentry.io`** — ADR-031 authoritative over generic docs; do NOT switch to `de.sentry.io`. |
| `POST /api/0/organizations/<org>/sentry-apps/` exists + needs org:admin | Best-practices-researcher could not confirm the endpoint or scope in public docs (UNVERIFIED) | Reinforces **Playwright-primary** mint (the API path is unconfirmed); marked `automation-status: UNVERIFIED` regardless. |

## User-Brand Impact

**If this lands broken, the user experiences:** an agent that still can't read the
production Sentry error during a no-SSH failure — diagnosis stalls exactly as it did in
#5492, and the user's incident stays unresolved longer.

**If this leaks, the user's data is exposed via:** (a) an over-scoped or leaked Sentry
token granting write/delete or cross-tenant read of production telemetry; (b) the inline
read surfacing un-scrubbed user PII (Sentry event message/breadcrumb/tag **values** the
ingest-time key-name scrub misses) into agent context (a sub-processor disclosure to Anthropic).

**Brand-survival threshold:** single-user incident.

> CPO sign-off: carried forward from the brainstorm `## Domain Assessments` (CPO reviewed
> the narrowed scope). `user-impact-reviewer` runs at PR review.

## Implementation Phases

### Phase 0 — Preconditions (read-only verification)

- **TR-B.** Confirm Doppler `soleur/prd` is reachable inline (`doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain` returns non-empty) and is where `SENTRY_ISSUE_RO_TOKEN` will land.
- **TR-C.** Confirm Sentry API host = `jikigai-eu.sentry.io` (org-subdomain) and region-detect via `NEXT_PUBLIC_SENTRY_DSN` cluster substring (`ingest.de.sentry.io` → EU). Cite ADR-031 glossary. (The `event:read` 403 constraint is already documented `postmerge/SKILL.md:141`; reuse the `.test.sh` shell-test convention — `container-restart-monitor.test.sh` — do NOT introduce a new framework.)

### Phase 1 — `scripts/sentry-issue.sh` (GET-only CLI; TDD)

Mirror `scripts/betterstack-query.sh` structure (bash-under-Doppler). Write the failing
`scripts/sentry-issue.test.sh` first (mock `curl`), then implement.

- **Two read-by-id modes** (CPO: read-by-id only; `--short-id`/`--event`/by-tag deferred to #5500):
  - `<issue-id>` → issue detail: `GET /api/0/organizations/<org>/issues/<id>/`
  - `--latest-event <issue-id>` → latest event (the stack/exception): `GET /api/0/organizations/<org>/issues/<id>/events/latest/` (**org-scoped** — Kieran P0-1; the org-less form hits the EU slug-rewrite trap).
  - Output JSON (pretty or `--raw`); non-zero exit on API failure. Both endpoints are `event:read` — no `project:read` needed (the `/projects/.../events/<id>/` shape that would need `project:read` is the deferred `--event` mode).
- **Token resolution (explicit mechanism):** read the token from the env injected by `doppler run -p soleur -c prd` (mirror `betterstack-query.sh:38` `: "${VAR:?…}"` guard — do NOT do an inner `doppler secrets get`, or the `-c prd` is cosmetic). Prefer `SENTRY_ISSUE_RO_TOKEN`; fall back to `SENTRY_ISSUE_RW_TOKEN` with a stderr warning `using RW token GET-only; mint SENTRY_ISSUE_RO_TOKEN (see runbook)`. (Lets the CLI work before Phase 2 mints the RO token; the fallback is real, not dead code.) **RW-fallback removal trigger:** once `SENTRY_ISSUE_RO_TOKEN` exists in Doppler the fallback branch is removed (file a follow-up if the Phase 2 mint defers on an MFA gate — the RW path must not become steady-state; §Risks).
- curl form mirrors `betterstack-query.sh:47`: `curl -sS --fail-with-body --max-time 30 -H "Authorization: Bearer $TOKEN" …` under `set -uo pipefail`.
- **GET-only invariant (hardened — security P1-2; allowlist not denylist):** the request is built from a **fixed method constant `GET`**, carries **no body** (`-d`/`--data*`/`-F`/`-T`/`--upload-file` never constructed), and the URL must match the **two-endpoint allowlist** `^/api/0/organizations/<org>/issues/[A-Za-z0-9_-]+/(events/latest/)?$`. Validate the issue-id arg against `^[A-Za-z0-9_-]+$` BEFORE interpolation (closes path/endpoint-injection — load-bearing given the EU slug-rewrite trap). The GET-only + allowlist guard applies on the **RW-fallback path too** (it is the only thing between a bug and a write with an `event:admin` token).
- **Token-handling invariants (security P1-1):** never `set -x`/`bash -x` (would trace the Bearer header to stderr); error paths print the HTTP status + body but the test asserts stderr/stdout never contain the token substring; `cq-test-fixtures-synthesized-only` — the `.test.sh` mocks BOTH `curl` and `doppler` with a synthesized fake token (never touches `soleur/prd`).
- Host pinning (org-subdomain `jikigai-eu.sentry.io`, NOT `de.sentry.io`/`eu.sentry.io` — see Research Reconciliation EU-host row) + region-detect; map 403 → "token lacks event:read"; treat 401 as scope-not-ownership (ADR-031 glossary) — print the scope-probe hint, don't infer ownership.
- **Exception field path** (best-practices-researcher, confirmed): the real error lives at `exception.values[].value` (message) + `exception.values[].stacktrace.frames[]` (stack) in the event JSON — surface these for `--latest-event` and document in the runbook.
- **PII banner to stderr** (accountability/operator-hygiene, NOT a transfer control — the PII is in stdout the agent consumes): "Sentry event bodies may contain residual user PII (message/breadcrumb/tag/`user.*` values) not removed by the ingest key-scrub — do not paste into shared/persistent contexts." Optional `--redact` flag (default OFF) masks `email`/bearer-token/`Authorization` patterns for shared-context use.

### Phase 2 — Auto-mint the read-only token (`automation-status: UNVERIFIED`)

Per #5480, /work MUST attempt automation before ANY operator handoff. Attempt in order:

1. **API path (preferred if feasible):** probe whether any available credential carries
   `org:admin`. If yes, `POST /api/0/organizations/jikigai-eu/sentry-apps/` to create
   Internal Integration `inline-read-prd` with **Issue&Event=Read, Organization=Read,
   everything else No Access** (`scopes = [event:read, org:read]`), then retrieve its token.
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
2. **Playwright path (primary expected path):** drive `https://eu.sentry.io` dashboard
   (Settings → Developer Settings → New Internal Integration) via Playwright MCP to create
   `inline-read-prd` with the same permission set; capture the generated token via a targeted
   `browser_evaluate` on the token field piped straight to the secret write — **no screenshot of
   the post-creation page** (the token renders in the DOM; a snapshot would persist it to PR/logs).
   Record `playwright-attempt:` evidence with the token field redacted (navigated URL; reached form / or named human gate).
3. **Write the token** to Doppler `soleur/prd` as `SENTRY_ISSUE_RO_TOKEN` (`printf '%s' … | doppler secrets set … -p soleur -c prd --no-interactive`; value piped via stdin so it never appears in argv/history; never echo). Add to `apps/web-platform/.env.example` with a scope comment. The runbook's re-mint section documents ONLY this no-argv stdin form.
4. **Swap CLI default** to `SENTRY_ISSUE_RO_TOKEN` (Phase 1 already prefers it).
5. **Only if** the Playwright attempt reaches a genuine human gate (MFA/CAPTCHA/passkey),
   record it as a verified single-interaction operator step with `playwright-attempt:` evidence
   — never an a-priori "console-gated" assertion.

Document the working mint path in the runbook's "Re-minting the read-only token" section.

### Phase 3 — Runbook `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md`

- Copy-paste GET commands for each subcommand; **zero SSH** (`hr-no-ssh-fallback-in-runbooks`). The **first step under any `Triage`/`Diagnosis`/`Debug` heading must be the no-SSH `scripts/sentry-issue.sh <id>` probe** (the `ship-runbook-ssh-gate.sh` hook flags the first content line under those headings); the Playwright re-mint section uses browser-driving prose, not SSH.
- **Layer-citation** per signal (`hr-observability-layer-citation`): which layer/source each field comes from (Sentry issue/event vs Better Stack ClickHouse).
- "Re-minting the read-only token" section (mirror `betterstack-log-query.md` re-mint section) — the Phase 2 working path.
- PII caveat: Sentry inline reads are **NOT** as scrubbed as Better Stack (which passes Vector's 3-stage `pii_scrub`); event bodies carry residual value-level PII.

### Phase 4 — Skill wiring (the load-bearing half)

Re-anchor every edit by **section heading + quoted substring** (not line numbers — Kieran P1-1; read each file first).

- **`observability-coverage-reviewer.md` (the true net-new gap):** add a new step *after* the Step-1 diff-inventory (the agent is producer-side today and never told it can read) instructing the reviewer it **can itself query** Better Stack (`scripts/betterstack-query.sh`) and Sentry (`scripts/sentry-issue.sh`) mid-review. This is the substantive edit.
- **The other 3 already carry working Sentry/Better Stack curl** (Simplicity #2 + CPO) → append a **one-line pointer** only (not a rewrite of working curl):
  - `reproduce-bug/SKILL.md` — at the existing Sentry-query block ("Check the observability layer FIRST"): add `scripts/sentry-issue.sh <id>` + the `sentry-issue-read.md` runbook link.
  - `incident/SKILL.md` — at the `hr-no-dashboard-eyeball` blockquote that lists `SENTRY_IAC_AUTH_TOKEN`/`SENTRY_ISSUE_RW_TOKEN`: add the named CLI + runbook link **and update the token list to prefer the least-privilege `SENTRY_ISSUE_RO_TOKEN`** (Kieran P2-4 — else the wiring is half-done).
  - `postmerge/SKILL.md` — at the "Production Debugging" note: add the named CLI + runbook link.

### Phase 5 — ADR-031 amendment + Art. 30 PA8 touch

- **Amend `ADR-031-sentry-as-iac.md`** — execute the amendment specified in the `## Architecture Decision (ADR/C4)` section below.
- **Art. 30 register PA8 touch** (`knowledge-base/legal/article-30-register.md`): note the
  inline-read purpose + the RO token identity for §5(2) accountability.

### Phase 6 — gdpr-gate + verification

- **Plan-time gdpr-gate verdict (2026-06-17):** one `Important` Chapter-V finding — the inline read surfaces residual value-level PII (Sentry event message/breadcrumb/tag values the key-name scrub misses) into agent context, a transfer **covered by the existing Anthropic DPA**. **No Critical.** v1 value-scrubber NOT required; the stderr PII banner + Art. 30 PA8 touch + least-privilege RO token are the proportionate controls.
- **PR-diff re-run (AC6):** re-run `/soleur:gdpr-gate` on the actual diff; add a thin email/token regex redaction in the CLI **only if** the diff shows raw values printed without the warning.
- Run the AC verification suite.

## Files to Create

- `scripts/sentry-issue.sh` — GET-only inline Sentry read CLI.
- `scripts/sentry-issue.test.sh` — mocked-curl unit test (GET-only invariant, token resolution, host pinning).
- `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md` — runbook.

## Files to Edit

- `apps/web-platform/.env.example` — add `SENTRY_ISSUE_RO_TOKEN` with scope comment.
- `plugins/soleur/skills/reproduce-bug/SKILL.md` — name the CLI + runbook pointer.
- `plugins/soleur/skills/incident/SKILL.md` — name the CLI + runbook pointer.
- `plugins/soleur/skills/postmerge/SKILL.md` — name the CLI + runbook pointer.
- `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` — "you can query" instruction.
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — amendment.
- `knowledge-base/legal/article-30-register.md` — PA8 touch.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `scripts/sentry-issue.sh <issue-id>` returns issue-detail JSON (read-only) under Doppler, no SSH; `--latest-event <issue-id>` returns the latest event's exception value via the **org-scoped** endpoint.
- [ ] AC2: `scripts/sentry-issue.test.sh` passes (mock-`curl` `curl_args`-log convention per `container-restart-monitor.test.sh`; mock `doppler` too): for every recorded curl invocation — method is GET, **no** `-d`/`--data*`/`-F`/`-T`, URL matches the two-endpoint allowlist; **hostile issue-id inputs** (`/`, `?`, `;`, `..`) are rejected (non-zero exit); the GET-only assertions run with **both** RO and RW tokens selected; error-path stderr never contains the (fake) token; script source contains no `set -x`; token preference (RO → RW fallback with warning); org-subdomain host pinning.
- [ ] AC3: `sentry-issue-read.md` exists, cites the observability layer per signal, contains **zero** SSH steps (passes `.claude/hooks/ship-runbook-ssh-gate.sh`), and has a "Re-minting the read-only token" section.
- [ ] AC4: `observability-coverage-reviewer.md` instructs the agent it can query Better Stack/Sentry mid-review (grep asserts **both** `betterstack-query.sh` AND `sentry-issue.sh` present); `reproduce-bug`/`incident`/`postmerge` each carry a one-line `scripts/sentry-issue.sh` + runbook pointer; `incident` token list prefers `SENTRY_ISSUE_RO_TOKEN`.
- [ ] AC5: ADR-031 amended with the `inline-read-prd` read-only credential class; Art. 30 PA8 touched.
- [ ] AC6: `/soleur:gdpr-gate` re-run on the PR diff returns no Critical (or any Critical is folded in), and specifically checks the `user.*` tag surface. v1 prints unredacted event values **by design** (the agent needs the stack/message to debug); the proportionate controls are least-privilege + the stderr banner (accountability, not a transfer control) + Art. 30 + the optional `--redact` flag. A value-level default-on scrubber is deferred to a named follow-up, not gated on a self-satisfying "if raw values appear" trigger.

### Post-merge (operator) / deferred

- [ ] AC7 (Soleur-automated, not operator): `SENTRY_ISSUE_RO_TOKEN` exists in Doppler `soleur/prd`, scopes = `[event:read, org:read]` only, minted via Playwright/API with `playwright-attempt:` evidence recorded; CLI defaults to it. **Automation:** attempted in-session at Phase 2; only a real MFA/CAPTCHA gate may defer the single interaction. PR body uses `Closes #5495`.

## Observability

```yaml
liveness_signal: none — operator-invoked CLI, no standing liveness; mint success asserted by AC7 (token present + CLI returns an issue)
error_reporting: CLI exits non-zero and prints the Sentry HTTP status/body to stderr (fail-loud); no silent fallback
failure_modes:
  - {mode: "token missing/absent", detection: "CLI stderr 'mint SENTRY_ISSUE_RO_TOKEN'", layer: "none — operator-invoked CLI, fail-loud to stderr (no standing layer)", alert_route: "operator-facing CLI message"}
  - {mode: "401 scope-not-ownership", detection: "CLI prints scope-probe hint (ADR-031 glossary)", layer: "none — operator-invoked CLI, fail-loud to stderr", alert_route: "CLI stderr"}
  - {mode: "403 on /issues/<id>/ (wrong token class)", detection: "CLI maps 403 to 'token lacks event:read'", layer: "none — operator-invoked CLI, fail-loud to stderr", alert_route: "CLI stderr"}
logs: none persisted — read-only client; output is the agent's stdout
discoverability_test:
  command: "doppler run -p soleur -c prd -- scripts/sentry-issue.sh <known-issue-id>"
  expected_output: "issue-detail JSON with culprit + latest-event exception value"
```

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The `doppler secrets set SENTRY_ISSUE_RO_TOKEN` step is genuinely required and cannot route
through a `doppler_secret` Terraform resource: (1) the `jianyuan/sentry` provider exposes no
internal-integration/token resource, so the token is not Terraform-mintable; (2) its value is
minted out-of-band at runtime (Playwright/API, Phase 2) and is unknowable at apply time; (3) this
matches the established Sentry-token-in-Doppler precedent (SENTRY_IAC_AUTH_TOKEN, SENTRY_ISSUE_RW_TOKEN)
per ADR-031's authentication/secret-store divergence. No `*.tf` is touched, so no merge-applied root fires. -->

### Terraform changes
None. The `jianyuan/sentry` provider exposes **no** internal-integration/token resource
(verified: `apps/web-platform/infra/sentry/*.tf` manages only monitors/alerts/uptime). Sentry
tokens are not Terraform-mintable — consistent with ADR-031.

### Apply path
The read-only token is provisioned by **automation script/Playwright** (Phase 2), not `terraform apply`.
Stored in Doppler `soleur/prd`. No auto-applied infra root is touched (no `*.tf` change), so
there is **no merge-triggered apply** and the `#5468` no-default-TF-var sequencing trap does NOT apply.

### Distinctness / drift safeguards
`dev != prd`: the token is a `prd` Sentry credential; no dev counterpart is minted (debugging
reads target prod telemetry). Least-privilege `[event:read, org:read]` — no write/admin scope.

### Vendor-tier reality check
Sentry Internal Integrations are free-tier; no paid gate on creation. EU org `jikigai-eu`.

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-031** (`## Decision` + dated amendment) to record the read-only `inline-read-prd`
Internal Integration (`[event:read, org:read]`) and the inline read-CLI pattern as a distinct
read-only credential class alongside the existing IaC token. New decision, not a reversal —
extends ADR-031's credential taxonomy. Author via the `architecture` skill / Edit, committed in this feature's lifecycle. Note in the amendment that the inline read CLI is a **read path, not a sixth observability layer** — so `observability-coverage-reviewer` does not start accepting "CLI stderr" as a layer citation (prevents citation-rule erosion).

### C4 views
None. A CLI + a scoped token introduces no new container or trust-boundary edge in the C4 model
(the read path is operator/agent → Sentry REST, already an existing external edge).

### Sequencing
The ADR amendment ships in this PR (Phase 5); the token's existence is asserted by AC8.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (carried forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward)
**Assessment:** bash-under-Doppler GET-only wrapper; `SENTRY_API_TOKEN` 403s on issues; host-stderr Better Stack gap is real but out of scope (#5499); wire via prose-link pattern.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** GDPR-defensible read-only EU-resident path, but a new disclosure surface for residual value-level PII the key-scrub misses → gdpr-gate at plan/PR + Art. 30 PA8 touch; do NOT reuse the RW/admin token.

### Product/UX Gate
**Tier:** none
**Decision:** N/A — no UI-surface file in Files to Create/Edit (scripts, SKILL.md bodies, agent/runbook/ADR/register markdown). Internal agent-facing tooling.
**Pencil available:** N/A (no UI surface)

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned no issue body referencing any edit-target file.

## Test Scenarios

1. `sentry-issue.sh <issue-id>` with RO token set → issue JSON; with only RW token → same output + stderr warning; with neither → non-zero exit + mint hint.
2. `--latest-event <issue-id>` hits the org-scoped path (test asserts the URL contains `/organizations/<org>/issues/<id>/events/latest/`).
3. GET-only invariant: test asserts the script never constructs a non-GET curl.
4. 403 path (read token) → mapped to "token lacks event:read" message.
5. Runbook passes `ship-runbook-ssh-gate.sh` (zero SSH).
6. `observability-coverage-reviewer` edit: grep requires **both** `betterstack-query.sh` AND `sentry-issue.sh` (two separate assertions, not an OR-union — Kieran P2-3).

## Risks & Sharp Edges

- **Token mint is `automation-status: UNVERIFIED` (#5480).** /work MUST run a Playwright attempt against the Sentry dashboard before any operator handoff; an a-priori "no creation API / console-gated" claim is NOT acceptable evidence. Only a real MFA/CAPTCHA gate defers the single interaction, recorded with `playwright-attempt:` evidence.
- **`event:read` is mandatory.** Reusing `SENTRY_API_TOKEN`/`SENTRY_AUTH_TOKEN` is impossible (403 on `/issues/<id>/`); reusing `SENTRY_ISSUE_RW_TOKEN` is the GET-only stopgap until the RO token is minted — never the permanent posture.
- **EU host trap.** Use `jikigai-eu.sentry.io` (org-subdomain), never `eu.sentry.io` (`-eu` slug-rewrite → 302/401 cascade; ADR-031 glossary).
- **PII posture asymmetry.** The runbook/CLI must NOT imply Sentry inline reads are as scrubbed as Better Stack; `sentry-scrub.ts` is key-name-only.
- A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6 — it is filled above.
- **Build-order vs final-state.** Phase 1 (CLI with RW fallback) precedes Phase 2 (RO mint) for ship-something resilience; the operator's "mint first" intent is honored as the **final state** (AC8: CLI defaults to the RO token), not a strict build-order.
