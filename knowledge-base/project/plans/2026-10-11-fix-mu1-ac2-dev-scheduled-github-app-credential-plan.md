---
title: "fix: MU1 AC-2 dev_scheduled GitHub App credential repair + shape audit"
type: fix
date: 2026-10-11
slug: mu1-ac2-dev-scheduled-github-app-credential
branch: feat-one-shot-9995-mu1-dev-scheduled-token-401
issue: 9995
closes: 9995
priority: p1-high
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Rationale for the ack — see ## Infrastructure (IaC): a doppler_secret
TF resource would write the App private key into terraform.tfstate
(branch-readable per ADR-241 D3/D4), which is the exact exposure #8609's
operator-hand precedent exists to avoid; the GitHub provider has no
app-creation resource; MU1_FIXTURE_* secrets are deliberately not
TF-managed. -->

# fix: MU1 AC-2 dev_scheduled GitHub App credential repair + shape audit

Spec lacks valid `lane:` (no spec.md — pipeline entry without brainstorm)
— defaulted to cross-domain (TR2 fail-closed).

## Overview

The `MU1_INTEGRATION` nightly leg of `scheduled-integration-suites.yml` —
`apps/web-platform/test/mu1.integration.test.ts` AC-2
`provisionWorkspaceWithRepo clones fixture` — fails minting a GitHub
installation token: GitHub returns `401 "A JSON web token could not be
decoded"` (appId 3261325, installationId 122213433, pemFingerprint
`8246898e`; run 38130672233). Live shape probes run during planning proved
the root cause: `soleur/dev_scheduled`'s `GITHUB_APP_PRIVATE_KEY` is a
syntactically valid RSA PEM whose JWT `GET /app` rejects with 401 — a key
not registered on the soleur-ai App — while the keys in `soleur/prd` and
`soleur-github-app/prd` both mint 200. This plan repairs the credential the
least-privilege way (a dedicated `soleur-ci-fixture` App with `contents:read`
on `jikig-ai/mu1-fixture` only, rather than copying a Tier-B soleur-ai
runtime key into a dev config), adds a mint-liveness canary inside the mu1
leg, runs the mandated dev_scheduled credential-shape audit, and
re-dispatches the nightly leg.

## Problem Statement / Motivation

Nightly MU1 AC-2 coverage (the signup→clone path) is dark. The April
`ops-mu1-fixture-repo-and-ac2-test` plan plumbed `GITHUB_APP_*` into
`soleur/dev` by copying `soleur/prd`'s then-current key; the October
dormant-integration plan verified only the secret *names* existed in
`dev_scheduled` (`doppler secrets --only-names`, 2026-10-10), never the
values. Whatever key `dev`/`dev_scheduled` holds is a third fingerprint
(`8246898e` / `f35e6274`) — not the pre-rotation prd key (`ff669d84`), not
the isolated live key (`adcd5760`) — and it is not registered on App
3261325, so every signed JWT fails GitHub's verification. This is the
second dev-config credential-shape failure in a week (#9972 was the first,
fixed by #9991 — a different mechanism, a too-strict token-shape regex on
*output* tokens), so a one-time shape audit of the whole `dev_scheduled`
config is in scope.

### Planning-time forensic evidence (already executed, shape-only)

JWT-mint liveness probe (`GET /app`, iss=3261325; never printed a value):

| Config | PEM bytes | fp (sha256 of env-form PEM, [:8]) | `GET /app` |
|---|---|---|---|
| `soleur/dev_scheduled` | 1679 | `8246898e` ← **exact match to CI's logged pemFingerprint** | **401** |
| `soleur/dev` | 1679 | `8246898e` | **401** |
| `soleur/prd` | 1675 | `cd7aef45` | 200 (`soleur-ai`) |
| `soleur-github-app/prd` (isolated live key, #8609) | 1679 | `8958d113` | 200 (`soleur-ai`) |
| `soleur-github-app/prd_retired` `..._RETIRED` (pre-rotation key) | 1675 | `cd7aef45` | 200 (still registered — R7 not yet run) |

Reads: `GITHUB_APP_ID` = `3261325` in both dev_scheduled and prd (correct);
`MU1_FIXTURE_REPO_URL` = `https://github.com/jikig-ai/mu1-fixture.git`;
`MU1_FIXTURE_INSTALLATION_ID` = `122213433` (the soleur-ai org-wide
installation — `apps/web-platform/infra/main.tf` `:102` comment).

## Research Insights

**Relevant file paths.**

- `.github/workflows/scheduled-integration-suites.yml` — mu1 step (`id:
  mu1`, ~line 292) runs `doppler run -p soleur -c dev_scheduled -- env
  MU1_INTEGRATION=1 npm run test:ci -- test/mu1.integration.test.ts`.
  The `OUT_*` env block in `Aggregate suite outcomes` is the SINGLE
  enumeration point for suite steps — folding the mint probe *inside* the
  mu1 step avoids touching that census; a skipped/failed mu1 already flows
  to `failed_md` and the `if: always()` aggregator is fail-closed
  (`outcome != "success"` → `status=error`).
- `apps/web-platform/server/github-app.ts` — `getPrivateKey()` expands
  `\\n`→`\n` and warns on missing BEGIN marker; `getAppId()` validates via
  `readAppId`; `createAppJwt()` signs RS256; `generateInstallationToken`
  logs `pemFingerprint` = sha256(pem)[:8] on failure (this is how the
  8246898e match was made).
- `apps/web-platform/server/github/app-private-key.ts` —
  `normalizeAppPrivateKey`/`readAppId` comments document this exact error
  class: `"A JSON web token could not be decoded"` is GitHub's opaque
  verdict for signature-verification failure (CRLF/escaped-`\n` PEM,
  trailing-newline appId, client_id confusion, or wrong/revoked key).
- `apps/web-platform/infra/github-board-app-manifest.json` — the
  least-privilege second-App precedent (#8209 O1b: "a write-capable App
  mint reachable from a lower tier gets its own least-privilege App").
- `knowledge-base/engineering/operations/runbooks/github-app-provisioning.md`
  — manifest-prefilled App creation; single operator gate = the
  App-create click (OAuth-consent class).
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
  §Runtime App key (#8609) — R0–R9: the soleur-ai runtime key was moved to
  isolated project `soleur-github-app`; a `soleur/*` config holding
  `${soleur-github-app.` references is explicitly forbidden (R1/R6 count
  check); `github_app_key_isolated` is still `false` in
  `apps/web-platform/infra/server.tf`, so `soleur/prd` still holds the
  pre-rotation key pending R6/R7.
- `scripts/assert-dev-doppler-scope.sh` — the existing dev_scheduled
  names-only scope assertion (sibling convention for the audit script).
- `apps/web-platform/test/mu1.integration.test.ts` — AC-2 gate chain:
  `MU1_INTEGRATION=1` opt-in + `MU1_FIXTURE_*` pair canary; comment
  documents that `dev`'s App creds "can't mint a token for the fixture
  installation" (true — dead key).

**Premise Validation (Phase 0.6).** Cited issues verified live: #9855
CLOSED, #9947 MERGED (the PR that shipped this leg), #9993 OPEN (the
nightly tracker the filer updates), #9972 CLOSED via #9991, draft PR
#10038 OPEN on this branch. Cited files all exist on `origin/main`
(`mu1.integration.test.ts`, `server/github-app.ts` with
`generateInstallationToken`, `scheduled-integration-suites.yml`). The
issue's suggested mechanism — "compare dev_scheduled against prd" — was
executed at plan time and is **partially stale**: `soleur/prd`'s key mints
200 today but is the *pre-rotation* key parked in `prd_retired`, due to die
at #8609 R7; and post-R6 `soleur/prd` stops carrying the key entirely.
Neither repair-by-copy option survives the ADR-241 tiering audit: the
isolated live key must never re-enter a `soleur/*` config (that is the
whole D10 isolation), and `dev_scheduled`/`dev` are reachable by
dev-scoped tokens plus every personal `soleur` reader. No external
premises left unvalidated.

**Property List (Phase 0.6b).**

1. MU1 AC-2's live installation-token mint succeeds under `dev_scheduled`
   (mu1 leg green on next dispatch).
2. The credential in `dev_scheduled` does not re-open the #8609 isolation:
   no soleur-ai runtime key in a `soleur/*` dev config — a dev_scheduled
   leak must be harmless (ADR-241 least-privilege, soleur-board precedent).
3. A dead/mismatched credential fails fast with a named error before
   suite time is spent, not as an opaque 401 buried in vitest output
   (diagnosability; this is the second shape failure in a week).
4. The rest of `dev_scheduled`'s secrets get a one-time shape audit with
   follow-up issues for failures (mandate-declared scope; #9972 shape).

**Cut List (Phase 0.6b).**

- Copy `soleur/prd` or `soleur-github-app/prd` key into dev_scheduled →
  buys property 1 — CUT: violates ADR-241 D10 (the isolated key must not
  re-enter `soleur/*`); prd's copy additionally dies at R7.
- Terraform `doppler_secret` for the fixture creds → buys property 1 —
  CUT: writing a private key through `doppler_secret` lands the value in
  `terraform.tfstate`, which ADR-241 D3/D4 makes branch-readable — the
  exact exposure #8609's operator-hand precedent exists to prevent; and
  GitHub App private keys cannot be minted by Terraform at all —
  GitHub-side generation IS the provider-side mint
  `hr-tf-variable-no-operator-mint-default` prefers.
- Repair `soleur/dev`'s identical dead key → buys nothing for property 1 —
  CUT: `dev` feeds local runtime flows that expect the soleur-ai app
  identity (`NEXT_PUBLIC_GITHUB_APP_SLUG`); swapping dev's app identity
  makes local mints *succeed for the wrong app*, worse than the current
  loud dead key. Audit reports it; no change.
- Cron-scheduled audit job → buys property 4 — CUT: the on-demand script
  plus the in-leg probe cover it; scheduling is a follow-up issue, not
  this PR.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (verified at plan time) | Plan response |
|---|---|---|
| "compare dev_scheduled `GITHUB_APP_*` against prd (which mints successfully)" | prd mints 200 — but holds the *pre-rotation* key (fp `cd7aef45` = `prd_retired`'s value), slated for R7 deletion; dev_scheduled holds a third, unregistered key (fp `8246898e`, proven by mint probe) | Use the mint-liveness probe + fingerprint comparison (both already executed) as the permanent diagnostic instead of a byte-count compare |
| "repair via provider-side mint or credential reuse" | Credential reuse = copy a Tier-B soleur-ai key into a dev config — re-opens #8609's D10 isolation; prd's key dies at R7 anyway | Provider-side mint: a dedicated `soleur-ci-fixture` App (soleur-board/O1b precedent), installed on `jikig-ai/mu1-fixture` only |
| "the `GITHUB_APP_PRIVATE_KEY` (or PEM) is malformed, truncated, or belongs to a different app" | It is a *valid, parseable* PKCS#1 PEM (1679 bytes, BEGIN RSA marker, 0 backslashes, 0 CRs) that is simply **not registered** on App 3261325 — wrong key, not malformed bytes | Fix is credential replacement, not byte surgery |

## Proposed Solution

1. **New least-privilege GitHub App `soleur-ci-fixture`** created via the
   manifest flow (`apps/web-platform/infra/github-ci-fixture-app-manifest.json`,
   modeled on `github-board-app-manifest.json`): `contents: read`,
   `metadata: read`, `public: false`, webhook inactive. Installed on
   `jikig-ai/mu1-fixture` only (repo-scoped installation). Its private key
   in `dev_scheduled` is harmless on leak — read-only clone rights on one
   fixture repo — which is exactly what a dev-scoped config should hold.
2. **Doppler update** — `soleur/dev_scheduled` gets the fixture app's
   `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, and its installation id in
   `MU1_FIXTURE_INSTALLATION_ID` (replacing 122213433, the soleur-ai org
   installation the fixture app does not own).
3. **Mint-liveness canary** — `scripts/probe-github-app-mint.sh`
   (bash+openssl+curl): signs a JWT from `GITHUB_APP_ID` +
   `GITHUB_APP_PRIVATE_KEY` in env, calls `GET /app`, prints
   `GITHUB_APP_MINT status=200 slug=<slug> fp=<sha256(pem)[:8]>` (never
   the key or the JWT) or `::error::` + exit 1. Invoked inside the
   workflow's mu1 step before vitest under the same `doppler run` env —
   reads exactly what the test reads.
4. **Shape audit** — `scripts/audit-dev-scheduled-shapes.sh` iterates
   `doppler secrets --only-names -p soleur -c dev_scheduled`, checks every
   value against its declared shape class (PEM parse, URL scheme, numeric
   id, token prefix, no-CR/control-byte floor — the #9972 `token_shape`
   class), prints a name→verdict table (never values), exits nonzero on
   any FAIL. Findings table posted to #9995; non-GITHUB_APP failures get
   their own issues.
5. **Verify** — `gh workflow run scheduled-integration-suites.yml` on the
   branch shows the mu1 leg green; re-check on main post-merge.

### Operator gates (consent-class, canonical list)

Three clicks are operator-gated; everything else — manifest POST page,
Playwright navigation, Doppler pipes, fingerprint verification — is
agent-driven. The `github-app-provisioning.md` runbook already
classifies the App-create submit as the canonical single operator gate
(OAuth-consent-class carve-out, `operator-only canonical list` case b);
the install submit is the same consent class.

- **G1 App-create click**: GitHub's "Create GitHub App" submit on the
  manifest-prefilled form (org: `jikig-ai`).
  `Automation: not feasible — OAuth-consent-class per the operator-only
  canonical list (github-app-provisioning.md precedent: the App-create
  click is its one named manual gate).`
- **G2 Private-key generation click** on the new App's settings page;
  `automation-status: UNVERIFIED — soleur:work MUST run a Playwright
  attempt first` (the R1 precedent in
  `infra-credential-tiers-8209.md` records the click as Playwright-driven
  with the download landing on `$XDG_RUNTIME_DIR` tmpfs under
  `umask 077`; PEM never echoed).
- **G3 Install click**:
  `https://github.com/apps/soleur-ci-fixture/installations/new` scoped
  to `jikig-ai/mu1-fixture` only. `Automation: not feasible —
  org-admin OAuth consent, same class as G1.`

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing new — the MU1
  AC-2 nightly leg stays red (it is already red); users see no artifact.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  the *only* credential this change introduces to `dev_scheduled` is the
  fixture App key — `contents:read` on `jikig-ai/mu1-fixture`; a leak
  exposes fixture content only. The rejected alternative (copying the
  soleur-ai key down) would have exposed every user's workspace-auth path
  to a dev-scoped token leak — that is the #8609 blast radius this plan
  deliberately does not recreate.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the deliverable is a CI
  credential repair whose security posture *improves* on the status quo;
  no user-facing surface or user-data path changes.

*Scope-out override:* `threshold: none, reason: the touched
apps/web-platform/infra/ path is a committed GitHub App manifest JSON
(fixture app, contents:read on one fixture repo) — it is test
infrastructure, not a user-affecting runtime surface.`

## Alternative Approaches Considered

| Option | Verdict |
|---|---|
| Copy `soleur/prd` `GITHUB_APP_PRIVATE_KEY` into dev_scheduled (issue's "credential reuse" arm) | Rejected — prd's key is the *retired* key (fp `cd7aef45`, parked in `prd_retired`); #8609 R7 deletes it at GitHub and the leg re-breaks. Also re-opens the D10 isolation the key was moved out of `soleur/*` to create. |
| Copy `soleur-github-app/prd` (isolated live key) into dev_scheduled | Rejected — strictly worse: this is the post-R7 sole live disconnect-every-user key; placing it behind `DOPPLER_TOKEN_DEV_SCHEDULED` + every personal `soleur` reader is the exact exposure ADR-241 paid to remove. |
| Doppler cross-project reference `${soleur-github-app.prd.GITHUB_APP_PRIVATE_KEY}` in dev_scheduled | Rejected — explicitly forbidden by #8609 R1/R6's "zero `${soleur-github-app.` references in `soleur` configs" check. |
| Reuse `soleur-board` App (already least-privilege) | Rejected — it lacks `contents` entirely and is reachable from `pull_request` (O1b's own caution); widening it couples MU1 to board-sync's permission budget. |
| Reuse `soleur-infra` App | Rejected — `secrets:write` + broad repo scope is the opposite of least-privilege for a read-only clone. |
| Make the fixture repo public and skip the mint | Rejected — `provisionWorkspaceWithRepo` mints the installation token unconditionally before clone; the live mint IS the coverage the leg exists to verify. |
| **Dedicated `soleur-ci-fixture` App** | **Chosen** — soleur-board (O1b) precedent; survives soleur-ai key rotations forever; harmless on leak. |

## Implementation Phases

### Phase 1: Fixture App provisioning (consent-gated clicks + agent automation)

1.1. Commit `apps/web-platform/infra/github-ci-fixture-app-manifest.json`
(name "Soleur CI Fixture", `contents:read` + `metadata:read`,
`public:false`, `hook_attributes.active:false`, description citing #9995
and the least-privilege rationale).
1.2. Render the manifest-POST page locally (hidden `<input
name="manifest">` form targeting
`https://github.com/organizations/jikig-ai/settings/apps/new`), open via
Playwright → consent gate G1 submits GitHub's **Create GitHub App** form.
1.3. Playwright to the App's settings page → consent gate G2 generates a
private key; PEM downloads to `$XDG_RUNTIME_DIR` tmpfs under `umask 077`.
1.4. Playwright to
`https://github.com/apps/soleur-ci-fixture/installations/new` → consent
gate G3 installs on `jikig-ai/mu1-fixture` only.
1.5. Read ids (names/numbers only, never the key):
`gh api apps/soleur-ci-fixture --jq .id`,
`gh api repos/jikig-ai/mu1-fixture/installation --jq .id`.
1.6. Pipe credentials into `soleur/dev_scheduled` per the Doppler write
discipline in Dependencies & Risks (every write stdout-redirected, PEM
streamed from tmpfs, deleted only after the read-back fingerprint matches
the download's).
1.7. Record shapes as a comment on #9995 and in
`knowledge-base/project/specs/feat-one-shot-9995-mu1-dev-scheduled-token-401/credential-evidence.md`
(ship folds durable artifacts into the PR body): new PEM byte count +
sha256[:8] fingerprint, app id, installation id. Never a value.

### Phase 2: Mint-liveness canary (RED drill → workflow step)

2.1. Create `scripts/probe-github-app-mint.sh` +
`scripts/probe-github-app-mint.test.sh`.
2.2. **RED drill before the swap**: run the probe under
`doppler run -p soleur -c dev_scheduled` — expect exit 1 printing fp
`8246898e` (reproduces the CI failure locally, proves the probe reads what
the test reads).
2.3. Edit `.github/workflows/scheduled-integration-suites.yml`: inside the
`Run MU1_INTEGRATION suites` step, run the probe under the same
`doppler run` before the vitest invocation; refresh the step comment
(GITHUB_APP_* is now the `soleur-ci-fixture` App, not soleur-ai).
2.4. GREEN check after Phase 1.6: probe prints
`GITHUB_APP_MINT status=200 slug=soleur-ci-fixture fp=<new>`.

### Phase 3: dev_scheduled credential-shape audit

3.1. Create `scripts/audit-dev-scheduled-shapes.sh` +
`scripts/audit-dev-scheduled-shapes.test.sh` (shape-class table; names
from `doppler secrets --only-names`; per-name verdict line; nonzero exit
on any FAIL; fail-closed on empty/unreadable census).
3.2. Run the audit; post the name→verdict table to #9995.
3.3. File a follow-up issue for every non-GITHUB_APP FAIL (`--milestone
"Post-MVP / Later"`, label `ci/integration-suites`); the known `dev`
config dead-key observation is recorded in the #9995 comment (no change —
see Cut List).

### Phase 4: Docs + verification dispatch

4.1. Update `mu1-signup-workspace-verification.md` (AC-2 evidence row:
fixture App + probe) and the header comment in
`apps/web-platform/test/mu1.integration.test.ts` (name the fixture App;
`dev`'s documented-expected 401 stays accurate).
4.2. `gh workflow run scheduled-integration-suites.yml --ref
feat-one-shot-9995-mu1-dev-scheduled-token-401` — arm a Monitor on the run
(hr-dispatch-async-must-arm-watch); assert `mu1` outcome `success`.
4.3. Post-merge: `gh workflow run scheduled-integration-suites.yml` on
main — mu1 leg green (the issue's AC).

## Files to Create

- `apps/web-platform/infra/github-ci-fixture-app-manifest.json` — fixture
  App manifest (contents:read, metadata:read).
- `scripts/probe-github-app-mint.sh` — JWT mint liveness probe (bash,
  openssl, curl; prints status+slug+fingerprint only; portable — no
  `timeout`/`date -d`/GNU-only flags so it also runs on operator macOS
  hosts, or it uses the repo's `timeout`→`gtimeout`→bare pattern from
  `.claude/hooks/git-commit-secret-scan.sh`).
- `scripts/probe-github-app-mint.test.sh` — battery driving the Guard-1
  mutation matrix.
- `scripts/audit-dev-scheduled-shapes.sh` — shape-table audit over the
  dev_scheduled census.
- `scripts/audit-dev-scheduled-shapes.test.sh` — battery driving the
  Guard-2 mutation matrix.

## Files to Edit

- `.github/workflows/scheduled-integration-suites.yml` — mint-probe
  invocation inside the `Run MU1_INTEGRATION suites` step + comment
  refresh (~line 292).
- `apps/web-platform/test/mu1.integration.test.ts` — header comment names
  the `soleur-ci-fixture` App (behavior unchanged).
- `knowledge-base/engineering/operations/runbooks/mu1-signup-workspace-verification.md`
  — AC-2 evidence row + credential provenance.

## Infrastructure (IaC)

Phase 2.8 reviewed — no Terraform resources change, and none should:

- **GitHub App creation has no Terraform resource** — the GitHub provider
  manages app *installations*, not app creation; the repo's provisioning
  path is the manifest-prefilled UI POST (`github-app-provisioning.md`).
- **`doppler_secret` for `GITHUB_APP_PRIVATE_KEY` is the wrong vehicle by
  the repo's own ADR-241 reasoning**: a TF-managed secret writes the value
  into `terraform.tfstate`, and this root's state is branch-readable by
  Tier-A `prd_terraform` backend keys — `github-app-runtime-project.tf`'s
  header states the rule verbatim ("anything Terraform mints or reads
  here is branch-readable … the operator puts the key in by hand"). The
  Doppler CLI write path is therefore the *sanctioned* infra path for App
  keys, not an operator shortcut.
- GitHub-side private-key generation IS the provider-side mint
  `hr-tf-variable-no-operator-mint-default` prefers — there is no API to
  mint App keys, so GitHub UI is the provider.
- `MU1_FIXTURE_*` secrets are deliberately not TF-managed
  (dormant-integration plan precedent).
- No hosts, volumes, cron, DNS, or firewall changes — no apply path, no
  host fan-out, no vendor tier gates.

## Observability

```yaml
liveness_signal:
  what: "mu1 suite-step outcome in scheduled-integration-suites.yml plus the in-leg probe line `GITHUB_APP_MINT status=200 slug=soleur-ci-fixture`"
  cadence: nightly cron + on-demand workflow_dispatch
  alert_target: "tracker #9993 via the workflow's file-or-comment tracking-issue step"
  configured_in: ".github/workflows/scheduled-integration-suites.yml (mu1 step + Aggregate suite outcomes + File or comment tracking issue)"
error_reporting:
  destination: "workflow run log; roll-up into #9993"
  fail_loud: "::error::GITHUB_APP_* cannot mint a valid JWT for app <id> (status <n>) printed before vitest runs"
failure_modes:
  - mode: "fixture-app key revoked/deleted at GitHub, or Doppler value corrupted"
    detection: "in-leg probe exits 1 → mu1 outcome=failure → failed_md names `mu1`"
    alert_route: "#9993 filed/updated by the tracking-issue step"
  - mode: "non-GITHUB_APP dev_scheduled secret shape drift (#9972 class)"
    detection: "scripts/audit-dev-scheduled-shapes.sh reports `FAIL <name> <class>` (on-demand)"
    alert_route: "audit output → follow-up issue (Phase 3.3)"
logs:
  where: "`gh run view <run-id> --log` for scheduled-integration-suites.yml"
  retention: "GitHub Actions default retention"
discoverability_test:
  command: bash scripts/probe-github-app-mint.sh
  expected_output: "GITHUB_APP_MINT"
  credentials_required: "dev-scoped Doppler token (DOPPLER_TOKEN scoped to soleur/dev_scheduled) — no unauthenticated probe can verify a private key's mint liveness; the script prints only status, slug and fingerprint"
```

## Encryption Posture

No new persistent store. No new cross-component connection class: the mu1
leg already calls `api.github.com` over TLS-verified HTTPS for the
installation-token mint and clone; the probe uses the same endpoint.
`skip: no-store-no-new-connection`.

## Architecture Decision (ADR/C4)

No new ADR — the dedicated least-privilege fixture App is an *application*
of ADR-241's tiering and the soleur-board (O1b) precedent, not a new
decision; it creates no tenancy/ownership move, no new substrate, no
trust-boundary change a reader of the existing ADRs would be surprised
by.

### C4 views

No C4 impact. Enumeration performed against all three model files
(`model.c4`, `views.c4`, `spec.c4`): (a) external human actors — none new
(the operator is already modeled); (b) external systems — GitHub is
already modeled as `system "GitHub"` (`model.c4` github element); a
CI-only fixture App is a credential inside that system, not a new
external system; (c) containers/data-stores — none touched; (d)
access relationships — the CI→GitHub-API edge already exists; the
fixture App narrows it, it does not add one.

## Guard Contract

### Guard 1 — `scripts/probe-github-app-mint.sh` (in-leg mint canary)

**Property.** Before suite time is spent, the `GITHUB_APP_ID` +
`GITHUB_APP_PRIVATE_KEY` pair the test will read must mint a JWT that
`GET /app` accepts (HTTP 200); anything else exits 1 with a named error.

**Assembly.** The one consumer path: the `Run MU1_INTEGRATION suites`
step in `scheduled-integration-suites.yml`, which invokes the probe under
the identical `doppler run -p soleur -c dev_scheduled` environment the
vitest call uses — there is no second env path for these names in that
job. Local/manual runs through `doppler run` are the same chokepoint.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Point env at a valid RSA PEM not registered on the app (the current dead key — this is today's live state) | RED (401 → exit 1) |
| 2 | `GITHUB_APP_PRIVATE_KEY` unset/empty in env — probe must not vacuously pass | RED |
| 3 | A second credential shape after a compliant first: valid registered key for app A but `GITHUB_APP_ID` set to app B's id | RED (signature/app mismatch → 401) |
| 4 | Harness: `.test.sh` stubs `curl` to emit `{}` with status 000 — probe must fail, not print a 200 line | RED |
| 5 | Must-PASS: PEM stored with literal `\n` escapes (Doppler encoding variant the code tolerates) still mints | PASS |

### Guard 2 — `scripts/audit-dev-scheduled-shapes.sh` (shape audit)

**Property.** Every secret value in `soleur/dev_scheduled` either matches
its declared shape class or is reported by name; an empty or unreadable
census fails, never greens.

**Assembly.** The full `doppler secrets --only-names -p soleur -c
dev_scheduled` census — every name, not a curated list; each name maps to
a shape class (PEM-parse, URL-scheme, numeric-id, token-prefix,
no-control-bytes floor). One chokepoint: the census→shape loop.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Inject a value with CR/control bytes into a `*_TOKEN`-class name | RED (named in output) |
| 2 | `doppler secrets --only-names` returns empty or permission error — "0 checked" must never exit 0 | RED |
| 3 | First name in census conforms, second is malformed — the FAIL line must name the second (no stop-at-first) | RED |
| 4 | Harness: `.test.sh` feeds a census fixture where every name conforms except one name whose class is absent from the table — unclassified names must verdict `UNCLASSIFIED`, not `ok` | RED-on-misclassify |
| 5 | Must-PASS: a value in a permitted variant (e.g. `*_B64` suffix value in strict base64 alphabet) | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Compare the dev_scheduled `GITHUB_APP_*` entries against prd (which mints successfully) — `doppler secrets get GITHUB_APP_PRIVATE_KEY --plain \| wc -c` shape check only, never print the value." | Research Insights forensic table + Phase 2.2/2.4 probe drills | mapped — executed at plan time and encoded as the durable probe |
| 2 | "If malformed: re-mint/re-paste via the operator secret path or Terraform provider-side per `hr-tf-variable-no-operator-mint-default`." | Phase 1 (fixture App = provider-side mint; operator secret path for the Doppler write) | mapped |
| 3 | "AC: next `gh workflow run scheduled-integration-suites.yml` dispatch shows the `mu1` leg green." | Acceptance Criteria + Phase 4.2/4.3 | mapped |
| 4 | "a dev_scheduled credential-shape audit is in scope" (planner mandate, citing #9972's related shape) | Phase 3 audit script + findings | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `github-ci-fixture-app-manifest.json` + App provisioning (Phase 1) | "re-mint/re-paste via the operator secret path or Terraform provider-side" | asked — provider-side mint arm; dedicated App chosen because credential *reuse* fails the ADR-241 tiering audit (see Alternatives) |
| `scripts/probe-github-app-mint.sh` + workflow step | — | inferred — property 3: a dead credential must fail named before suite time; the issue's own failure took 5s of vitest plus a human log-read to diagnose |
| `scripts/audit-dev-scheduled-shapes.sh` (+ .test.sh) | "a dev_scheduled credential-shape audit is in scope" | asked |
| mu1 step probe invocation + comment (workflow edit) | "AC: next `gh workflow run scheduled-integration-suites.yml` dispatch shows the `mu1` leg green" | inferred — the step is where the canary must live to read the identical env; justification in Guard 1 assembly |
| Runbook + test-comment edits | — | inferred — docs must name the new credential owner or they lie |

### Split Assessment

- Subsystems touched: 4 — `.github`, `scripts`, `apps/web-platform`,
  `knowledge-base`
- Planned files: 8 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root count overstates: this is one
  mechanism (fixture credential + its canary + its audit); the
  knowledge-base and workflow edits are comment-sized. Splitting a
  credential repair across PRs strands the verification dispatch.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI credential repair
applying the already-decided ADR-241 least-privilege pattern. Product:
NONE (no UI surface — Files lists contain no `components/**/*.tsx`,
`app/**/page.tsx`, or UI-term paths). Operations-adjacent (credential
provisioning) but every step follows existing runbooks
(`github-app-provisioning.md`, `infra-credential-tiers-8209.md`); no
vendor/expense/legal surface. The credential-class decision is recorded
in Alternatives + the #8609 citations rather than deferred to a leader
spawn unavailable in this harness.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/infra/github-ci-fixture-app-manifest.json`
      committed; live App slug `soleur-ci-fixture` exists under jikig-ai
      with `contents:read` only, installed on `jikig-ai/mu1-fixture` only
      (verified: `gh api apps/soleur-ci-fixture` + installation id query).
- [ ] `soleur/dev_scheduled` `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY`/
      `MU1_FIXTURE_INSTALLATION_ID` all point at the fixture App and its
      installation; verified by
      `doppler run -p soleur -c dev_scheduled -- bash scripts/probe-github-app-mint.sh`
      printing `status=200 slug=soleur-ci-fixture` — fingerprints recorded
      in `credential-evidence.md` + a #9995 comment, no value ever printed.
- [ ] The mu1 step in `scheduled-integration-suites.yml` runs the probe
      before vitest; RED drill output (dead key → exit 1 with fp
      `8246898e`) recorded in `credential-evidence.md`.
- [ ] `scripts/probe-github-app-mint.sh` + `.test.sh` and
      `scripts/audit-dev-scheduled-shapes.sh` + `.test.sh` committed and
      their batteries green; audit table posted to #9995; every
      non-GITHUB_APP FAIL has a follow-up issue (or the report states
      none found).
- [ ] `gh workflow run scheduled-integration-suites.yml` dispatched on
      the branch shows the `mu1` step outcome `success` (verifiable
      pre-merge: the leg reads Doppler at runtime, branch-independent).
- [ ] `mu1-signup-workspace-verification.md` and the mu1 test-file header
      comment name the `soleur-ci-fixture` App.
- [ ] PR body carries `Closes #9995`.

### Post-merge (operator)

- [ ] `gh workflow run scheduled-integration-suites.yml` on `main` shows
      the `mu1` leg green on its next scheduled or dispatched run
      (issue's AC; ship's post-merge verification or the next nightly).

## Test Scenarios

- **unit** — probe: given env with a valid registered key, when the probe
  runs, then stdout contains `GITHUB_APP_MINT` + `status=200` + the slug.
- **unit** — probe: given a valid unregistered PEM / empty var /
  appId-vs-key mismatch / curl-status-000 stub, then exit 1 and the
  `::error::` line names the credential (Guard-1 matrix rows 1-4).
- **unit** — audit: given a census fixture with a CR-corrupted `*_TOKEN`,
  an empty census, a compliant-first+malformed-second pair, and an
  unclassified name, then FAIL lines name the offenders and empty census
  exits nonzero (Guard-2 matrix).
- **integration** — given the repaired `dev_scheduled`, when
  `MU1_INTEGRATION=1 doppler run -p soleur -c dev_scheduled --
  npm run test:ci -- test/mu1.integration.test.ts --project unit` runs,
  then AC-2 mints and clones (6/6 file tests pass).
- **integration** — dispatch `gh workflow run
  scheduled-integration-suites.yml` → `mu1` outcome `success`
  (deterministic per the workflow's own `steps.mu1.outcome`).
- **API verify** — `gh api repos/jikig-ai/mu1-fixture/installation --jq
  .id` returns the fixture App's installation id matching
  `MU1_FIXTURE_INSTALLATION_ID`.

## Success Metrics

- mu1 leg green on the next scheduled run (and on both verification
  dispatches).
- Probe line `GITHUB_APP_MINT status=200 slug=soleur-ci-fixture` present
  in the mu1 step log.
- Zero `soleur-ai` private-key material in `soleur/dev_scheduled`
  (fingerprint of stored value ≠ all three soleur-ai fingerprints).

## Dependencies & Risks

- **Consent gates G1–G3** (app create, key generation, install) are
  OAuth-consent-class clicks — canonical operator-only steps; all other
  work is agent-driven. The scripts + manifest + docs ship even if the
  clicks lag, but the issue's AC requires the live repair; flagged per
  `wg-block-pr-ready-on-undeferred-operator-steps`.
- **`MU1_FIXTURE_INSTALLATION_ID` change**: the id moves from the
  soleur-ai org installation (122213433) to the fixture App's repo-scoped
  installation — only the mu1 leg reads it (verified: no other
  dev_scheduled suite consumes `GITHUB_APP_*`; AC-2 is the sole mint
  caller).
- **`dev` config keeps its dead key deliberately** — documented in the
  #9995 audit comment; its documented-expected local 401 is unchanged.
- **App name collision**: if `soleur-ci-fixture` slug is taken globally,
  fall back to `soleur-mu1-fixture` (same plan, name substitution only).
- Secret-handling discipline: `doppler secrets` write calls redirect
  stdout to `/dev/null` (the CLI echoes the full config otherwise);
  fingerprints/`wc -c` only — never values.

## References & Research

- Issue: #9995 (this), tracker #9993, related shape #9972→#9991,
  dormant-integration plan `2026-10-10-feat-dormant-integration-ci-plan.md`,
  fixture plan `archive/20260419-122400-2026-04-19-ops-mu1-fixture-repo-and-ac2-test-plan.md`.
- Runbooks: `github-app-provisioning.md`, `infra-credential-tiers-8209.md`
  (§Runtime App key, R0–R9), `github-app-drift.md`,
  `mu1-signup-workspace-verification.md`.
- ADR-241 (`terraform-credentials-are-tiered…`), #8609/PR-B isolation,
  `github_app_key_isolated=false` in `apps/web-platform/infra/server.tf`.
- Code: `apps/web-platform/server/github-app.ts`
  (`getPrivateKey`/`createAppJwt`/`generateInstallationToken`),
  `server/github/app-private-key.ts` (`normalizeAppPrivateKey`/`readAppId`
  failure-class comments), `infra/github-board-app-manifest.json`,
  `scripts/assert-dev-doppler-scope.sh`.
- Failing run: `https://github.com/jikig-ai/soleur/actions/runs/38130672233`.

## Open Code-Review Overlap

None — 88 open `code-review` issues searched for
`scheduled-integration-suites.yml`, `mu1.integration.test.ts`,
`probe-github-app-mint`, `audit-dev-scheduled-shapes`,
`fixture-app-manifest`, `mu1-signup-workspace-verification`,
`dev_scheduled`, `GITHUB_APP`; zero hits.

## Non-Goals

- Repairing `soleur/dev`'s identical dead key (documented-expected local
  failure; see Cut List).
- Any soleur-ai key rotation, R6 eviction, or R7 deletion — owned by
  #8609's R-steps, not this plan.
- Scheduling the audit script (follow-up issue if wanted).
- Changing `MU1_FIXTURE_REPO_URL`, the fixture repo's content, or any
  product code path in `server/`.
