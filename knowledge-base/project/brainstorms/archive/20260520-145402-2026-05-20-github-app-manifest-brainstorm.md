---
date: 2026-05-20
topic: github-app-manifest
related_issues: [4115, 3244, 4066, 3187, 4114]
related_prs: [4121]
status: brainstorm-complete
lane: cross-domain
brand_survival_threshold: single-user incident
---

# GitHub App Manifest — Committed-JSON Provisioning (Approach A)

## What We're Building

A committed `github-app-manifest.json` + a tiny static init page that lets the
operator pre-fill GitHub's "Create a new App" form via the [App-Manifest
flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)
without introducing a server-side credential-write callback.

1. **`apps/web-platform/infra/github-app-manifest.json`** — committed JSON
   declaring the App's `name`, `url`, `hook_attributes.url`, `callback_urls`
   (three entries per `2026-05-04-github-app-callback-url-three-entries.md`
   learning), `default_permissions` (including `administration:write` per
   `2026-04-06-github-app-org-repo-creation-endpoint-routing.md`), and
   `default_events`. Authoritative source of truth for the App's permission
   contract.
2. **`apps/web-platform/app/internal/github-app-init/page.tsx`** — static
   server-rendered page with a single HTML form that POSTs the committed
   manifest JSON to `https://github.com/settings/apps/new`. **No
   `redirect_url` set** in the manifest payload → no callback to forge →
   no online Doppler write surface introduced. Operator clicks one button;
   GitHub pre-fills the App-create form; operator clicks Create; operator
   manually pastes the 5 resulting values into Doppler UI (same hop as
   today, but the 12-field form-fill collapses).
3. **Extension to `scheduled-github-app-drift-guard.yml`** — adds a
   manifest-vs-live-App diff step that compares the committed manifest's
   `default_permissions` and `default_events` against the `gh api /app`
   response. Files `ci/auth-broken` issue on permission drift. Same JWT
   mint, same secret triple, single workflow.
4. **Parity test** — vitest unit test that parses
   `github-app-manifest.json` + `github-app.tf` and asserts: (a) manifest
   `hook_attributes.url` equals `https://${var.app_domain}/api/webhooks/github`,
   (b) every `GITHUB_APP_*` and `OAUTH_PROBE_GITHUB_CLIENT_ID` consumer the
   TF `doppler_secret` resources expect is the manifest's expected output
   shape, (c) callback URLs include all three from the 2026-05-04 learning.

Operator-time win: 12-field form-fill (~10 min) → one button click +
5 Doppler pastes (~3 min). Net 7-min reduction at `n=1` environment today,
amortized across future `stg` / per-tenant deploys.

## User-Brand Impact

- **Artifact:** GitHub App's 5 identity credentials (App ID, PEM, webhook
  secret, Client ID, Client Secret) at the moment of provisioning.
- **Vector A — Credential plant:** If we introduced an online callback that
  wrote these 5 values to Doppler on receipt of a POST from GitHub, an
  attacker who acquires the init-route's HMAC key + initiates a parallel
  App-create against our callback URL could plant their App's credentials in
  Doppler `prd`. The sibling drift-guard's `id`+`client_id` immutability check
  silently regresses (it reads from the same Doppler config the attack just
  wrote to, mediated through Terraform → GH Actions secrets propagation).
  **Approach A avoids this vector entirely** — no callback handler exists;
  no online write path to Doppler exists; the operator's manual paste step
  remains the airgap.
- **Vector B — Permission drift between manifest and live App:** A merged
  PR that changes the manifest's `default_permissions` could mismatch the
  live App if not applied; conversely, an operator who edits permissions
  in the GitHub dashboard creates silent divergence. **Mitigated** by the
  extended drift-guard cron (hourly).
- **Vector C — Manifest fingerprint forgery / replay:** Approach A's init
  page POSTs to `github.com/settings/apps/new` without `state` because
  there is no callback to verify back against. No CSRF surface introduced
  because the init page has no inbound POST; only the GitHub-side form
  receives the manifest. Operator's browser is the only client.
- **Threshold:** `single-user incident`. One App-credential compromise
  during founder-cohort recruitment is brand-ending — but Approach A's
  blast radius is bounded by the same one already-accepted operator-paste
  surface that exists today. The drift-guard extension is the new
  detection primitive that closes the Art. 33 latency gap CLO flagged.

## Why This Approach

**Cross-leader convergence forced the scope cut.** CTO and CPO independently
recommended deferring the online callback in the original issue body. CLO
recommended `proceed with conditions` only with the callback's mandatory
attestation cron + Doppler write-token scoping + atomic register edits —
all of which become unnecessary once the callback itself is deferred.

The decisive architectural concern (CTO R1): introducing an online callback
that writes to Doppler converts a previously offline credential surface into
an online one, breaking the threat model that justifies the existing
drift-guard (`scheduled-github-app-drift-guard.yml`). The guard's value is
precisely that App credentials cannot be rewritten by an online actor;
adding a route that rewrites them — even HMAC-gated — collapses that
invariant unless the guard's "expected" side moves to a signed, out-of-band
source. Approach A preserves the invariant.

The decisive product concern (CPO): a one-time-per-environment ~9.5-min
saving at `n=1` environment today, with no `stg` on the T1 roadmap inside
90 days. **#4114** (apply-web-platform-infra.yml) saves 3 steps per PR —
~20–50× more leveraged short-term. Approach A captures 60–70% of the
strategic value (auditable manifest + drift-detection primitive) at ~10%
of the build cost.

The decisive compliance concern (CLO): the issue body's Article 32 framing
("credentials never transit a screenshot or paste-buffer") is overstated as
written. Approach A is more honestly framed as "we commit the manifest as
code so future provisioning is auditable and permission-diffable; the
operator continues to paste credentials manually."

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Scope: manifest JSON + init page only.** No callback handler, no Doppler write surface. | CTO + CPO converge. Avoids the codebase's first server-side Doppler write. Preserves drift-guard invariant. |
| 2 | **Init UX: tiny static page POSTs the manifest.** `apps/web-platform/app/internal/github-app-init/page.tsx` with a one-button HTML form. No HMAC gating needed — no callback to forge. | One-click UX win; minimal new surface. |
| 3 | **Drift cron: extend existing.** Add a manifest-vs-live-App permission/event diff step inside `scheduled-github-app-drift-guard.yml`. | Single canonical App watchdog. CLO's Art. 33 detection primitive. |
| 4 | **Parity: hand-authored manifest, vitest parity test against TF.** Lint asserts symbol parity (URL ↔ `${var.app_domain}`, callback URLs ↔ three-entries learning, secret names ↔ TF `doppler_secret` resources). Permissions stay hand-authored. | Repo-research confirms TF naming contract (`TF_VAR_<lower>`). Permissions are App contract, not derived. |
| 5 | **Manifest must declare `administration:write`.** Per `2026-04-06-github-app-org-repo-creation-endpoint-routing.md`. | Org-install repo-creation breaks without it. |
| 6 | **Three callback URLs in the manifest.** Per `2026-05-04-github-app-callback-url-three-entries.md`. | Flow A (Supabase) + Flow B (App-direct) + `setup_action` reinstall arm. |
| 7 | **PEM lands in Doppler as `GITHUB_APP_PRIVATE_KEY_B64`.** Operator base64-encodes during paste step. | Required by drift-guard (`2026-05-05-github-app-drift-guard-brainstorm.md`); also avoids multi-line value corruption through the Doppler UI. |
| 8 | **GH Actions secret triple stays sourced from `var.github_actions_token`** (drift-guard reads `GH_APP_DRIFTGUARD_APP_ID`, `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64`, `OAUTH_PROBE_GITHUB_CLIENT_ID`). | Repo-research confirmed propagation path. No change. |
| 9 | **Soften the Article 32 framing.** PR body must NOT claim "measurable Art. 32 improvement". Frame as "manifest-as-code enables permission auditing + drift detection; operator paste step intentionally preserved as airgap." | CLO finding. |
| 10 | **Defer Approach B (downloadable-artifact callback) + attestation cron** to tracking issues with explicit re-evaluation triggers. | `wg-when-deferring-a-capability-create-a`. Preserves option value if env-provisioning cadence changes. |

## Open Questions

1. Does GitHub's manifest form-POST endpoint accept the manifest without a
   `redirect_url`? The docs describe the redirect_url as part of the
   complete flow but don't explicitly disallow omitting it. Verify at
   implementation time; if required, set it to `/internal/github-app-init`
   itself and have that page render "Now copy the 5 values into Doppler"
   instructions on receiving GitHub's `?code=<temp>` query — discard the
   code. (Out of scope: redeeming the code, which would reintroduce the
   callback surface.)
2. Where does the init page live in the route tree if not behind the
   existing operator-only HMAC layer? Public-but-unlinked is acceptable
   (the page does nothing harmful — only POSTs to GitHub) but should
   probably sit at `/internal/github-app-init` for discoverability
   alongside other operator-only surfaces. Operator-auth gating can be
   added later without changing the contract.
3. PA-17 TOM register: which exact wording change? CLO's recommended text
   assumed the full callback flow. The Approach A edit is smaller —
   re-derive at spec time.
4. Manifest `webhook_secret` field — should we omit it (let GitHub
   generate) and let the operator paste the generated value, OR set it
   to a placeholder the operator overrides on the App settings page after
   creation? The current `github-app.tf` provisions the webhook secret
   via `random_id` → so we want GitHub to NOT generate one, and instead
   read the Terraform-managed value. Verify GitHub's behavior when
   `hook_attributes.secret` is omitted vs explicitly null.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Recommended defer/alternative shape. Online callback that
writes 5 creds to Doppler breaks the existing drift-guard's invariant
(planted-credentials attack on the source-of-truth the guard reads from);
introduces the codebase's first server-side Doppler write surface (no
existing helper); has no atomic-write story (Doppler API non-transactional
across 5 secrets). Approach A (this brainstorm's chosen scope) addresses
all of these by removing the online write path.

### Legal (CLO)

**Summary:** Article 32 framing in the original issue body is overstated.
"Credentials never transit a screenshot or paste-buffer" is literally true
for the full automation but trades operator-endpoint exposure for callback
attestability — a net trade-off, not unambiguous improvement. PA-17 TOM
register at `knowledge-base/legal/article-30-register.md:299` needs
amendment regardless of approach choice; PR body wording must soften.
Approach A is materially easier to defend than the full automation.

### Product (CPO)

**Summary:** Recommended sub-scope (a) only. T1 critical path is
user-facing cloud platform; this is internal toil reduction at `n=1`
environment. Manifest JSON captures 60-70% of strategic value at ~10%
build cost. Drift cron is pre-beta-cohort gate (not optional, not
deferrable indefinitely). Operator-paste surface is acceptable airgap
until a second environment is imminent.

## Capability Gaps

None for Approach A. All required scaffolding exists:

- HMAC route precedent at `apps/web-platform/app/api/internal/kb-drift-ingest/route.ts:15-64`
  (not needed for Approach A's init page, but available if future scopes
  reopen the callback path).
- Drift-guard cron at `.github/workflows/scheduled-github-app-drift-guard.yml`
  (498 lines) — extensible for manifest-vs-live diff.
- Terraform provisioning at `apps/web-platform/infra/github-app.tf`
  (88 lines, full file) — unchanged by Approach A; the manifest declares
  what the TF inputs eventually populate.
- Legal register at `knowledge-base/legal/article-30-register.md:285-301`
  (PA-17) — edit-only, no schema change.

## Deferred Items (file tracking issues)

1. **feat: downloadable-artifact callback for App provisioning (Approach B)**
   - Re-evaluation trigger: second environment (`stg`) on T1 roadmap OR
     App-rotation cadence > 1/quarter.
   - Scope on revival: HMAC-gated init + callback routes; callback writes
     credentials to a one-time encrypted downloadable artifact (NOT Doppler);
     operator downloads and pastes into Doppler UI. Preserves airgap;
     achieves the 30-sec operator UX.
2. **feat: synthetic-replay attestation cron for App-Manifest callback**
   - Re-evaluation trigger: Approach B issue closing (transitions to
     `feat-github-app-manifest-callback-attestation` issue at that point).
   - Scope on revival: `scheduled-github-app-manifest-callback-attestation.yml`
     (weekly) POSTs a forged callback against the production endpoint with
     an invalid HMAC; asserts 401. Art. 32(1)(d) "regular testing" primitive.

## References

- Issue #4115 (this brainstorm's parent)
- Sibling brainstorm: `knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md`
- ADR-036: `knowledge-base/engineering/architecture/decisions/ADR-036-github-app-webhook-as-second-multi-source-ingress.md` (the "single manual gate" line Approach A modernizes)
- Paired issue #4114 (apply-web-platform-infra.yml — orthogonal scope)
- Learning: `knowledge-base/project/learnings/integration-issues/2026-05-04-github-app-callback-url-three-entries.md`
- Learning: `knowledge-base/project/learnings/2026-04-06-github-app-org-repo-creation-endpoint-routing.md`
- Learning: `knowledge-base/project/learnings/2026-05-15-operator-only-step-canonical-list.md`
- Legal register: `knowledge-base/legal/article-30-register.md:285-301` (PA-17)
