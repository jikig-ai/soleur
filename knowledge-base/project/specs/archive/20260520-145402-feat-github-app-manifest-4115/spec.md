---
name: feat-github-app-manifest-4115
issue: 4115
pr: 4121
branch: feat-github-app-manifest-4115
brainstorm: knowledge-base/project/brainstorms/2026-05-20-github-app-manifest-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
related_issues: [4115, 3244, 4066, 3187, 4114]
status: draft
---

# Feature: GitHub App Manifest — Committed-JSON Provisioning (Approach A)

## Problem Statement

PR-H (#3244 / #4066) provisions the GitHub App's Doppler secrets via
`apps/web-platform/infra/github-app.tf`, but the App itself is created by
the operator at `https://github.com/settings/apps/new` — a 12-field form
fill that takes ~10 minutes per environment and has a high paste-error
surface. `apps/web-platform/infra/github-app.tf:6-8` and
`ADR-036` both reference this as a deferred-automation gate per
`hr-never-label-any-step-as-manual-without`.

The original issue body proposed a full automation: HMAC-gated init route
+ callback that writes 5 credentials directly to Doppler `prd` via the
Doppler API. The brainstorm (`2026-05-20-github-app-manifest-brainstorm.md`)
surfaced that this online-write path breaks the existing drift-guard's
threat model, introduces the codebase's first server-side Doppler write
surface, has no atomic-write story across 5 secrets, and trades a
~9.5-min one-time saving at `n=1` environment for an ~1-1.5-week build
with mandatory ongoing attestation. **CTO and CPO independently
recommended scope-cutting to manifest-only.**

This spec scopes the manifest-only sub-shape that captures the
auditability and drift-detection wins without introducing the
online-write surface.

## Goals

- Commit `github-app-manifest.json` as the source-of-truth for the App's
  permissions, events, callback URLs, and webhook URL.
- Ship a tiny static init page that POSTs the committed manifest to
  `https://github.com/settings/apps/new`, reducing the operator's 12-field
  form-fill to a one-button click.
- Extend `scheduled-github-app-drift-guard.yml` to compare the committed
  manifest's `default_permissions` and `default_events` against the live
  App (`gh api /app`), filing `ci/auth-broken` on drift.
- Land a vitest parity test that asserts manifest-vs-Terraform symbol
  consistency (URLs, callback list, secret names).
- Amend `knowledge-base/legal/article-30-register.md` PA-17 TOMs and
  `knowledge-base/legal/compliance-posture.md` to reflect the
  manifest-as-code provisioning model.
- Soften the original issue's Article 32 framing to a trade-off rather
  than an unambiguous improvement.

## Non-Goals

- **No HMAC-gated init route.** The init page POSTs the manifest to
  GitHub without a `redirect_url` set — no callback handler exists.
- **No callback endpoint receiving credentials.** Operator continues to
  paste the 5 resulting values into Doppler UI manually.
- **No server-side Doppler write surface.** This would be the codebase's
  first such surface; out of scope for this spec.
- **No downloadable-artifact callback (Approach B).** Tracked as deferred
  issue with re-evaluation trigger.
- **No synthetic-replay attestation cron.** Premise (the callback)
  doesn't exist in this scope; tracked as deferred issue.
- **No change to existing `scheduled-github-app-drift-guard.yml` JWT
  mint, secret-triple loading, or leak-tripwire.** New manifest-diff
  step is additive.
- **No change to `apps/web-platform/infra/github-app.tf` `doppler_secret`
  resources or their `ignore_changes` blocks.**

## Functional Requirements

### FR1: Committed manifest JSON

`apps/web-platform/infra/github-app-manifest.json` exists as a
hand-authored, schema-valid GitHub App manifest. Contains:

- `name`, `url`, `description`, `public: false`.
- `hook_attributes.url = "https://${app_domain}/api/webhooks/github"`
  (placeholder substituted at init-page render time).
- `redirect_url`: **omitted** (per brainstorm Open Question 1; verify at
  implementation that GitHub accepts manifest POSTs without it; if
  required, set to the init page itself with code-discarding behavior).
- `callback_urls`: three entries per `2026-05-04-github-app-callback-url-three-entries.md`.
- `default_permissions`: explicitly includes `administration: "write"`
  (per `2026-04-06-github-app-org-repo-creation-endpoint-routing.md`),
  plus the existing PR-H subscription matrix.
- `default_events`: matches the events PR-H wires.
- `setup_url`, `setup_on_update: true` (`setup_action=update` arm per
  `2026-04-06-github-app-reinstall-flow-on-click-fetch-pattern.md`).

### FR2: Static init page

`apps/web-platform/app/internal/github-app-init/page.tsx` renders a
server-rendered page with:

- A heading: "Provision the Soleur GitHub App".
- A short narrative paragraph naming the 5 values the operator will
  paste into Doppler after the App is created.
- An HTML `<form method="POST" action="https://github.com/settings/apps/new">`
  containing a single hidden `<input name="manifest" value="<stringified-manifest>">`
  and a single submit button.
- No client-side JS required; no HMAC gating.
- Manifest stringification reads `apps/web-platform/infra/github-app-manifest.json`
  at build time and substitutes `${app_domain}` from `process.env.APP_DOMAIN`.

### FR3: Drift-guard extension

`.github/workflows/scheduled-github-app-drift-guard.yml` gains a new step
after the existing `id` + `client_id` immutability check that:

- Loads `apps/web-platform/infra/github-app-manifest.json` from the
  checkout.
- Calls `gh api /app` (already done by the existing step; reuse its JSON
  output via `outputs`).
- Diffs the manifest's `default_permissions` and `default_events`
  against the response's `permissions` and `events`.
- On any divergence: files / updates the existing `ci/auth-broken`
  issue with a `permission-drift` failure-mode tag.
- Reuses the existing leak-tripwire (no PEM/JWT bytes touched by the
  new diff step).

### FR4: Operator runbook update

`knowledge-base/engineering/ops/runbooks/github-app-provisioning.md`
(new file) documents:

- Operator opens `/internal/github-app-init` in the app.
- Operator clicks the button; GitHub form is pre-filled.
- Operator clicks "Create GitHub App" on GitHub's side.
- Operator copies 5 values from the resulting App settings page into
  Doppler UI (with `--silent` CLI alternative per `2026-05-18-supabase-custom-access-token-hook-discriminator.md` Leak-2).
- PEM must be base64-encoded before paste into `GITHUB_APP_PRIVATE_KEY_B64`.
- Operator runs `terraform apply` against `apps/web-platform/infra/`.

## Technical Requirements

### TR1: Manifest-vs-Terraform parity test

`apps/web-platform/test/infra/github-app-manifest-parity.test.ts`
(vitest) parses both `github-app-manifest.json` and `github-app.tf` and
asserts:

- Manifest's `hook_attributes.url` template equals `https://${var.app_domain}/api/webhooks/github`.
- Manifest's `callback_urls` is a superset of the three URLs the
  `2026-05-04-github-app-callback-url-three-entries.md` learning
  enumerates (Flow A Supabase, Flow B App-direct, setup-action reinstall).
- Every `doppler_secret.github_app_*` resource in
  `github-app.tf` is documented in the manifest's expected-outputs
  comment block (verify-by-name only; no semantic verification — that's
  what the drift cron is for).
- Manifest declares `administration: "write"` in `default_permissions`.

### TR2: Init page reads manifest at build time

Manifest JSON is statically imported (not fetched at runtime). The page
is fully server-rendered (no client component). `${app_domain}` is
interpolated from `process.env.APP_DOMAIN` at request time.

### TR3: Drift-guard extension uses existing scaffolding

No new JWT mint, no new secret loading, no new failure-mode label. The
new step reuses `secrets.GH_APP_DRIFTGUARD_*` and the existing `gh api /app`
response (via step output, not a second API call — avoid rate-limit
amplification). The new failure-mode tag is `permission-drift` under
the existing `ci/auth-broken` label.

### TR4: Legal register edits ship atomically

Same PR:

- `knowledge-base/legal/article-30-register.md` PA-17 (g) TOMs: append
  a new TOM for "manifest-as-code provisioning" (precise wording derived
  at implementation, NOT copied from CLO's full-flow assessment which
  assumed Approach C).
- `knowledge-base/legal/compliance-posture.md` line 111: amend
  "GitHub App creation + webhook URL wiring" to "GitHub App creation via
  committed manifest (#4115) + webhook URL wiring".

Per `wg-after-merging-a-pr-that-adds-or-modifies`.

### TR5: Article 32 framing — soften

PR body wording: replace the issue's "measurable Art. 32 improvement"
with: "Approach A enables permission-auditing and drift-detection
primitives. The operator paste step is intentionally preserved as the
airgap that bounds blast radius for the App's identity credentials."

### TR6: Brand-survival threshold inheritance

`brand_survival_threshold: single-user incident` from spec frontmatter
carries forward into plan, deepen-plan, preflight Check 6, and
`user-impact-reviewer` review-time agent. Per
`hr-weigh-every-decision-against-target-user-impact`.

### TR7: GDPR-gate at plan + work exit

Per `hr-gdpr-gate-on-regulated-data-surfaces`, run `/soleur:gdpr-gate`
on the diff at plan Phase 2.7 and work Phase 2 exit. The init page is a
new route that touches the App's identity credentials' provisioning
metadata; regulated-data surface even though no PII flows.

### TR8: Operator-only canonical list — no rule violation

The manifest flow is the structured form of the
`2026-05-15-operator-only-step-canonical-list.md` carve-out for OAuth-
consent flows. The operator still owns the App-create click; Soleur
drives everything downstream (manifest authorship, init page rendering,
drift detection). The rule's "single manual gate" requirement at
ADR-036 §Consequences is satisfied.

## Acceptance Criteria

- [ ] `apps/web-platform/infra/github-app-manifest.json` lands; parity
      test passes.
- [ ] `apps/web-platform/app/internal/github-app-init/page.tsx` renders;
      manual smoke test confirms one-button POST pre-fills GitHub's form
      correctly (verify Open Question 1 — `redirect_url` omission
      acceptance).
- [ ] `scheduled-github-app-drift-guard.yml` gains the manifest-diff
      step; cron runs successfully once; permission-drift detection
      verified via a deliberate temporary mismatch.
- [ ] Article 30 register PA-17 + compliance-posture amendments land in
      the same PR.
- [ ] Operator runbook collapses 12-field form-fill to "click button +
      paste 5 values" (~3 min target).
- [ ] PR body Article 32 framing softened per TR5.
- [ ] `/soleur:gdpr-gate` passes at PR exit.
- [ ] Two deferred-issue tracking issues filed (Approach B + attestation
      cron).

## Out of Scope

See Non-Goals. Tracked as deferred:

- Online callback writing 5 secrets to Doppler (original issue body
  Approach C).
- Downloadable-artifact callback (CTO's Approach B).
- Synthetic-replay attestation cron (CLO's Art. 32(1)(d) primitive).

## Risks

- **R1 (medium):** Manifest `redirect_url` omission — if GitHub rejects
  the POST without a `redirect_url`, fall back to setting it to the
  init page itself with explicit `?code=` discarding (does NOT redeem
  the temporary code; documented in runbook).
- **R2 (low):** Webhook secret field handling — verify
  `hook_attributes.secret` behavior when manifest omits it vs sets a
  placeholder. Today's `random_id`-derived secret is the source of
  truth; the manifest must not cause GitHub to overwrite it.
- **R3 (low):** Drift cron false-positive during a permission-change PR
  between merge and `terraform apply`. Mitigate by suppressing
  `permission-drift` for ≤24h after a manifest-touching PR merges (TBD
  at plan time).
