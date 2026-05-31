---
title: "chore(observability): provision write-scoped Sentry token so postmerge can auto-resolve fixed issues"
date: 2026-05-31
type: chore
issue: 4681
branch: feat-one-shot-4681-sentry-issue-rw-token
lane: cross-domain
brand_survival_threshold: none
status: planned
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# 🔧 chore(observability): write-scoped Sentry token + postmerge auto-resolve

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec.md exists for this branch; lane chosen by content (touches a skill + infra credential + docs).

## Overview

`/soleur:postmerge` Phase 3.6 ("Sentry Error-Count Delta") can **read** a linked Sentry issue's status/count/lastSeen, but it cannot **write** — it only *recommends* resolution in prose. Every fix that resolves a Sentry-tracked error therefore leaves the historical issue open in the active list until an operator resolves it by hand in the UI. All existing Doppler `prd` Sentry tokens (`SENTRY_AUTH_TOKEN`, `SENTRY_API_TOKEN`, `SENTRY_IAC_AUTH_TOKEN`) return **403** on the issue-update (`PUT .../issues/<id>/`) endpoint — they are scoped for release upload / IaC / event ingest / Discover-count reads, none carry `event:write`/`event:admin`.

This plan: (1) provisions a separate read/write-scoped Sentry **Internal Integration** token (operator-mint in the Sentry UI — see IaC section for why this is NOT Terraformable), stored in Doppler `soleur`/`prd` as `SENTRY_ISSUE_RW_TOKEN`; (2) documents it in `apps/web-platform/.env.example`; (3) extends `/soleur:postmerge` Phase 3.6 to PUT `status:"resolved"` on the linked Sentry issue **only when** the post-deploy event count is zero / lastSeen predates the deploy — preserving the existing WARN-only "still firing" path.

**Detail level:** MORE. Single skill edit + one Doppler secret + one `.env.example` line. The only non-trivial axis is the operator-credential dependency and the graceful-degradation contract.

Closes #4681 — but note the credential half is operator-only (mint + Doppler write); the **code** half (skill + docs) is what this PR ships. See Acceptance Criteria split (`Ref #4681`, not `Closes`).

## Premise Validation

Checked: (a) PR #4666 (the surfacing PR) is merged — confirmed via `gh`; #4681 cites it only as the recurrence that motivated the deferral, not as a blocker. (b) Issue #4681 is OPEN with zero `closedByPullRequestsReferences` — not already resolved. (c) `plugins/soleur/skills/postmerge/SKILL.md` exists and **already** has a Phase 3.6 that GETs `/issues/<id>/` — so this is an *extend* (add a write), not a *build*. (d) `apps/web-platform/.env.example` lists `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN`/`SENTRY_ORG=jikigai-eu` — the doc surface exists. (e) The `jianyuan/sentry` Terraform root (`apps/web-platform/infra/sentry/`) **consumes** an internal-integration token (`main.tf:21`) but exposes **no** `sentry_token` / `sentry_internal_integration` resource — confirming the mint is UI-only. No stale premises.

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Codebase reality | Plan response |
|---|---|---|
| "Store it in Doppler `soleur` / `prd` as `SENTRY_ISSUE_RW_TOKEN`" | postmerge reads tokens from Doppler `soleur`/`prd` via `doppler secrets get … -p soleur -c prd --plain` (SKILL.md:113-114). Correct store. | Adopt `SENTRY_ISSUE_RW_TOKEN` in `soleur`/`prd`; postmerge prefers it over `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN` for the write call only. |
| "an internal-integration token, or an org auth token" | ADR-031 + `main.tf:21` + learning `2026-05-21-…-disambiguation` establish Internal Integration as the canonical RW class for `jikigai-eu`. Org Auth tokens (`sntrys_`) carry no user identity and historically lack `event:admin`. | Prescribe **Internal Integration** token with `event:admin` (superset of `event:write` + read), `org:read`, `project:read`. |
| "Host is the org-specific EU subdomain `https://jikigai-eu.sentry.io/api/0`" | postmerge Phase 3.5/3.6 builds `API_HOST="${SENTRY_ORG}.sentry.io"` and Phase 3.5 *defaults* `SENTRY_ORG` to `jikigai` (SKILL.md:115) — but `.env.example:65` sets `SENTRY_ORG=jikigai-eu`. The bare `jikigai` default is stale for the EU org. | Plan does NOT touch the existing GET host logic (out of scope / no reported failure on read in `prd` where `SENTRY_ORG=jikigai-eu` is set), but the new PUT block reuses the SAME `API_HOST`/`SENTRY_ORG` resolution so it inherits the env-correct host. Add a Sharp Edge noting the stale `jikigai` fallback default. |
| "wire Phase 3.6 to PUT status resolved when post-deploy event count is zero" | Phase 3.6 currently ends WARN-only with a prose recommendation. | Add the PUT inside the existing "expected good outcome" branch (lastSeen < deploy OR status already resolved/ignored), gated on token availability. Leave the "still firing" branch unchanged (never auto-resolve a still-firing issue). |

## User-Brand Impact

**If this lands broken, the user experiences:** a postmerge run that *incorrectly* PUTs `resolved` on a still-firing Sentry issue (false-resolve), hiding an active production error from the operator's active-issue list — OR a noisy 403/permission error in the postmerge report that erodes trust in the pipeline. (Soleur operators are non-technical founders; a silently-hidden live error is the worse failure.)
**If this leaks, the user's data / workflow is exposed via:** the `SENTRY_ISSUE_RW_TOKEN` carries `event:admin` on `jikigai-eu` — leak would let a holder resolve/ignore/delete issues and read event payloads (which may contain pseudonymized userIds per the residency work). Blast radius is bounded to one org's issue stream; the token is stored only in Doppler `soleur`/`prd` (same trust boundary as the existing Sentry tokens) and never echoed.
**Brand-survival threshold:** none.

> `threshold: none, reason:` postmerge is an internal operator-only verification skill; it touches no end-user data surface, no auth flow, no migration, and no API route. The token is a new Doppler secret of the same class as three existing Sentry tokens. A single-user breach of this surface does not damage the brand — the failure mode is operator-facing noise or a hidden internal error, recoverable by the operator on the next postmerge run.

## Implementation Phases

### Phase 1 — Operator: mint the Internal Integration token (operator-only; see Automation note)

**Automation: not feasible because** Sentry Internal Integration tokens are minted only through the org developer-settings UI (`https://jikigai-eu.sentry.io/settings/jikigai-eu/developer-settings/`); the `jianyuan/sentry` Terraform provider exposes no token-creation resource (it *consumes* such a token), and there is no Sentry MCP server loaded. This is the same operator-only class as interactive OAuth consent — automatable up to the UI gate, not through it.

Operator steps (record in PR body under Post-merge / operator, NOT inline `Closes`):

1. Sentry UI → `jikigai-eu` org → Settings → Developer Settings → **New Internal Integration** named `postmerge-issue-rw`.
2. Scopes: **`event:admin`** (resolve/ignore/delete + read — superset of `event:write`), **`org:read`**, **`project:read`**.
3. Copy the generated token (64-hex, no prefix — an Internal Integration token per learning `2026-05-21-…-disambiguation`).
4. Doppler write the minted value into `SENTRY_ISSUE_RW_TOKEN` on `soleur`/`prd` (Doppler dashboard or `doppler secrets set`; also `-c dev` if a dev postmerge path exists). Value originates from the UI mint above — there is no Terraform-resource path for it (see IaC section).

> **Why a separate secret, not widening an existing token:** per the issue's blast-radius argument — keep `event:admin` isolated from the release-upload / IaC / Discover tokens so a leak of any one stays narrowly scoped. The IaC token (`SENTRY_IAC_AUTH_TOKEN`) is a *GitHub repo secret*, not Doppler, per ADR-031 secret-store divergence — do NOT reuse it.

### Phase 2 — Document the new secret in `.env.example`

Edit `apps/web-platform/.env.example` (after the existing `SENTRY_API_TOKEN=` line, ~L63): add

```bash
# SENTRY_ISSUE_RW_TOKEN: Internal Integration token (event:admin) used ONLY by
# /soleur:postmerge to auto-resolve a linked Sentry issue when post-deploy
# event count is zero. Minted in the jikigai-eu org developer-settings UI;
# NOT Terraformed (the provider exposes no token resource). Doppler soleur/prd.
SENTRY_ISSUE_RW_TOKEN=
```

### Phase 3 — Extend `/soleur:postmerge` Phase 3.6 with the auto-resolve PUT

Edit `plugins/soleur/skills/postmerge/SKILL.md` Phase 3.6 (currently ends at the WARN-only interpretation block, ~L148):

- **Token resolution (new, write-only):** before the PUT, resolve a dedicated write token, falling back to skip (NOT to a read token — a read token will 403 and pollute the report):
  ```bash
  SENTRY_RW_TOKEN=$(doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain 2>/dev/null || true)
  ```
- **Guard:** the PUT runs **only** in the existing "expected good outcome" branch — `lastSeen` older than the deploy timestamp **OR** `status` already `resolved`/`ignored` — AND only when `SENTRY_RW_TOKEN` is non-empty AND the issue is not already resolved. Never PUT in the "still firing" branch.
- **The write:**
  ```bash
  curl -sfS -X PUT \
    -H "Authorization: Bearer ${SENTRY_RW_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"status":"resolved"}' \
    "https://${API_HOST}/api/0/organizations/${SENTRY_ORG}/issues/${ISSUE_ID}/" \
    | jq '{shortId, status}'
  ```
  Reuse the SAME `API_HOST`/`SENTRY_ORG` resolution as the GET above (inherits the env-correct `jikigai-eu` host from Doppler `prd`).
- **Report line:** extend the Phase 3.6 outcome vocabulary so Phase 6 / Phase 7 can print `AUTO-RESOLVED` in addition to `STOPPED`/`STILL-FIRING`/`SKIPPED`. On PUT failure (403/non-200): warn (`Sentry issue auto-resolve failed (<http>): resolve manually in the UI`) and continue — never block.
- **Graceful Degradation table:** add a row — `No SENTRY_ISSUE_RW_TOKEN | Skip auto-resolve; keep read-only delta (recommend manual resolution as today)`.

> Phase 3.6 stays **advisory / non-blocking** end to end. The write is additive: with the token absent, behavior is byte-identical to today (read + recommend).

## Open Code-Review Overlap

1 open code-review issue mentions the sentry infra surface:
- **#3829** (CI gate: new Sentry monitor type → `sentry-scrub.ts` must change) — **Acknowledge.** Different concern (PII-scrub carve-out enforcement on monitor *types*); this plan adds an issue-resolve write and touches neither `sentry-scrub.ts` nor monitor definitions. Remains open.

## Infrastructure (IaC)

This plan introduces a new **secret** (`SENTRY_ISSUE_RW_TOKEN`), which trips the Phase 2.8 `doppler secrets set` detector — so the gate is evaluated explicitly here. The IaC-routing-ack comment is set in the frontmatter because both the Sentry mint and the Doppler write are genuinely operator-only (justified below).

### Terraform changes
**None.** The credential is a Sentry Internal Integration token. The `jianyuan/sentry` provider (`apps/web-platform/infra/sentry/versions.tf`) provisions monitors/alerts but **has no token-creation resource** — `main.tf:21` documents that the integration token is minted at the org developer-settings UI and supplied *to* Terraform, never created *by* it. There is no IaC representation to add. This is the same class as the existing `SENTRY_IAC_AUTH_TOKEN` (a GitHub repo secret minted by hand per ADR-031) — Sentry tokens are an operator-mint surface by Sentry's own design. A `doppler_secret` Terraform resource is inapplicable because the *value* does not exist until the operator completes the UI mint; there is no plan-time source to feed a `.tf` resource.

### Apply path
N/A (no Terraform resource). The Doppler write is the only "apply"; it is operator-only (see Phase 1 Automation note) because the value comes from a UI-only mint. Consumed at runtime by the postmerge skill via `doppler secrets get`.

### Distinctness / drift safeguards
`dev != prd`: postmerge reads from `-c prd`. If a dev postmerge path is used, the secret must exist in whichever config postmerge runs against (issue-resolve is idempotent, so a shared or separate token both work). No Terraform state stores this value (it lives only in Doppler), so there is no `terraform.tfstate` leak vector.

### Vendor-tier reality check
Sentry Internal Integrations are available on all paid tiers `jikigai-eu` already uses for IaC; no tier gate. `event:admin` is a standard scope, not an add-on.

## Observability

```yaml
liveness_signal:
  what: postmerge Phase 7 report prints "Sentry error-count delta: AUTO-RESOLVED | STOPPED | STILL-FIRING | SKIPPED"
  cadence: per merged PR that links a Sentry issue (every postmerge run)
  alert_target: operator reading the postmerge report (interactive skill, not a cron)
  configured_in: plugins/soleur/skills/postmerge/SKILL.md Phase 3.6 + Phase 7
error_reporting:
  destination: postmerge report stdout (WARN line) — the skill is operator-interactive, not a server process; failures surface in the run output, not Sentry
  fail_loud: true  # PUT 403/non-200 emits an explicit "auto-resolve failed (<http>): resolve manually" WARN in the Phase 7 report
failure_modes:
  - mode: SENTRY_ISSUE_RW_TOKEN absent
    detection: doppler get returns empty
    alert_route: Phase 7 "Sentry error-count delta: SKIPPED (no RW token)" + Graceful Degradation row
  - mode: PUT returns 403 (token under-scoped / wrong org)
    detection: curl -sfS non-zero exit / non-200
    alert_route: Phase 7 WARN "auto-resolve failed (403): verify token has event:admin on jikigai-eu"
  - mode: false-resolve risk (resolving a still-firing issue)
    detection: PUT is structurally gated to the lastSeen<deploy / already-resolved branch ONLY — never reachable from the still-firing branch
    alert_route: N/A — prevented by guard, not detected after the fact
logs:
  where: postmerge skill run transcript (operator session) + the gh issue comment written in Phase 6
  retention: session transcript ephemeral; the Phase 6 issue comment is permanent on the GitHub issue
discoverability_test:
  command: "doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain >/dev/null && curl -sfS -o /dev/null -w '%{http_code}' -H \"Authorization: Bearer $(doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain)\" https://jikigai-eu.sentry.io/api/0/ ; echo"
  expected_output: "200 (token present and accepted by the jikigai-eu API surface)"
```

## Acceptance Criteria

### Pre-merge (PR — this ships in-PR, no prod write)
- [ ] `apps/web-platform/.env.example` contains a `SENTRY_ISSUE_RW_TOKEN=` line with the documenting comment (grep: `grep -c '^SENTRY_ISSUE_RW_TOKEN=' apps/web-platform/.env.example` returns 1).
- [ ] `plugins/soleur/skills/postmerge/SKILL.md` Phase 3.6 contains a `PUT` to `/issues/${ISSUE_ID}/` with `{"status":"resolved"}` (grep: `grep -c '"status":"resolved"' plugins/soleur/skills/postmerge/SKILL.md` returns ≥1) AND the PUT is preceded by a `SENTRY_ISSUE_RW_TOKEN` resolution line.
- [ ] The PUT appears textually inside the "expected good outcome" branch, NOT the "still firing" branch (manual read: the `STILL-FIRING` interpretation bullet is unchanged).
- [ ] Graceful Degradation table has a `No SENTRY_ISSUE_RW_TOKEN` row.
- [ ] Phase 7 report vocabulary includes `AUTO-RESOLVED`.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes (postmerge SKILL `description:` is unchanged → no budget impact; verify the suite still green after the body edit).
- [ ] No new dependency, no migration, no Terraform change (this PR is docs + skill text only).

### Post-merge (operator)
- [ ] Operator mints the `postmerge-issue-rw` Internal Integration token on `jikigai-eu` with `event:admin` + `org:read` + `project:read`.
- [ ] The minted value is written to `SENTRY_ISSUE_RW_TOKEN` on Doppler `soleur`/`prd`; `discoverability_test.command` above returns `200`.
- [ ] On the next postmerge run that links a stopped Sentry issue, the report prints `AUTO-RESOLVED` and the issue shows `resolved` in the Sentry UI.
- [ ] `gh issue close 4681` after the first successful auto-resolve (use `Ref #4681` in the PR body, NOT `Closes` — the capability is only fully live after the operator credential step).

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Pure observability/tooling change to an internal operator skill plus a new scoped credential. Architecturally low-risk: additive write behind a token-availability guard, structurally prevented from false-resolving a still-firing issue, fully backward-compatible when the token is absent. The only durable decision is the credential-isolation choice (separate `event:admin` token vs. widening an existing one) — the plan correctly chooses isolation per the issue's blast-radius argument and ADR-031's secret-store divergence. No Product/UX surface (no user-facing page/flow). No GDPR surface beyond the existing Sentry event-data trust boundary (the token reads events that already flow to Sentry today; no new processing). Recommend no additional specialists.

### Product/UX Gate
NONE — no user-facing surface (internal operator skill + credential + docs).

## Test Scenarios

1. **Token present, issue stopped:** Phase 3.6 GET shows `lastSeen` < deploy → PUT resolves → report `AUTO-RESOLVED`, Sentry UI shows `resolved`.
2. **Token present, issue still firing:** GET shows `lastSeen` > deploy → no PUT → report `STILL-FIRING` (unchanged behavior).
3. **Token absent:** `doppler get` empty → no PUT → report `SKIPPED (no RW token)` + degradation row fires; identical to today's read-only behavior.
4. **Token under-scoped (403):** PUT returns 403 → WARN `auto-resolve failed (403)` → pipeline continues, never blocks.
5. **Issue already resolved:** GET shows `status:resolved` → guard short-circuits the PUT (idempotent), report `STOPPED`/`AUTO-RESOLVED` consistent.

## Sharp Edges

- `/soleur:postmerge` Phase 3.5 defaults `SENTRY_ORG` to the bare `jikigai` (SKILL.md:115) while `.env.example` sets `jikigai-eu`. The new PUT reuses the same `API_HOST`/`SENTRY_ORG` resolution, so in `prd` (where `SENTRY_ORG=jikigai-eu` is set) it targets the correct EU host — but if a caller runs postmerge with `SENTRY_ORG` unset, both the GET and the new PUT will hit `jikigai.sentry.io`, which 401s/403s per the residency learnings. Out of scope to fix the default here (no read failure reported in `prd`), but flagged.
- Use `event:admin`, not `event:write` alone — the issue lists `event:write OR event:admin`; `event:admin` is the superset that also covers the GET read the same phase performs, so a single token serves both halves of Phase 3.6 (avoids a second token for the read).
- The credential is operator-only by Sentry design (UI-mint). Do NOT attempt to Terraform it — `apps/web-platform/infra/sentry/` consumes a token, it cannot create one. Any future "automate the mint" idea is blocked at the Sentry UI, the same as interactive OAuth consent.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above.)

## References

- Issue: #4681 (surfaced via merged PR #4666)
- Skill: `plugins/soleur/skills/postmerge/SKILL.md` (Phase 3.6 + Graceful Degradation + Phase 7)
- Docs: `apps/web-platform/.env.example` (L62-66 Sentry token block)
- Infra context (no change): `apps/web-platform/infra/sentry/main.tf:21`, `.github/workflows/apply-sentry-infra.yml` header (ADR-031 secret-store divergence)
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`
- Learnings: `knowledge-base/project/learnings/2026-05-21-sentry-internal-integration-vs-user-auth-token-disambiguation.md`, `knowledge-base/project/learnings/2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md`
