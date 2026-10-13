---
plan: feat-one-shot-6031-ghcr-installation-token-minter
issue: 6031
title: "feat(supply-chain): control-plane Inngest installation-token minter for private-GHCR reads (ADR-086)"
type: feature
labels: [domain/engineering, type/security]
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
depends_on: 6011   # PR for #6005 — ships ghcr-read-credential.tf, the consumers, variables.tf, ADR-086
supersedes_decision: "ADR-085 D1 (interim machine-account PAT)"
date: 2026-07-05
---

# feat(supply-chain): control-plane Inngest installation-token minter for private-GHCR reads (ADR-086)

## Enhancement Summary

**Deepened on:** 2026-07-05
**Research agents:** repo-research-analyst, learnings-researcher, framework-docs-researcher,
scoped strong-model advisor (fable), security-sentinel, architecture-strategist.

### Key improvements applied
1. **Phase-0 reshaped from binary halt → package-linkage test matrix** (advisor): the Actions
   `GITHUB_TOKEN` *is* an installation token, so a GHCR pull rejection is usually a package↔repo
   linkage config gap, not a dead mechanism. Only a linked-and-granted (matrix arm b) failure halts.
2. **Doppler write scope narrowed to a dedicated `prd_ghcr` config** (advisor, highest-leverage): a
   `prd`-scoped read/write token *reads* every prd secret → compromised minter = full prd
   exfiltration, failing the threshold. Cross-config secret referencing keeps consumers on `--config
   prd` unchanged.
3. **Reuse verified:** `generateInstallationToken(id,{permissions:{packages:"read"}})` already
   supports the scoped mint (`github-app.ts:749`), and `createAppJwt()` already pins `exp=now+540s`
   (`github-app.ts:148`) under GitHub's 600s ceiling — no new JWT code.
4. **5-registry Inngest lockstep** made explicit (route/manifest/count-test/sentry-tf/apply-workflow),
   all paths verified to exist; monitor slug `scheduled-ghcr-token-minter` per convention.

### New considerations discovered
- **Blocking:** GHCR-installation-token viability is contested → Phase-0 empirical gate is plan-defining.
- **Hard dependency on PR #6011** (issue #6005) — ships ADR-086 + consumers + `ghcr-read-credential.tf`;
  #6031 must rebase onto post-#6011 main and must not re-author those artifacts.
- **Stale C4:** `model.c4:242` still calls GHCR "Public" — corrected as a Phase-6 deliverable.

🔐 **Security / supply-chain.** Replace the interim machine-account `read:packages` **PAT**
(shipped by #6005 / PR #6011, recorded in ADR-085 D1) with a **platform-owned Inngest
function** that mints a short-lived (1h) GitHub **App installation access token** scoped to
`packages:read` and publishes it to Doppler `soleur/prd` as `GHCR_READ_TOKEN`. This makes
private-GHCR credential provisioning **zero-touch** (no browser + 2FA PAT mint), the
prerequisite for multi-tenant (Concierge) onboarding. Authority: **ADR-086** (authored in
PR #6011, `knowledge-base/engineering/architecture/decisions/ADR-086-control-plane-installation-token-minter-for-private-ghcr-reads.md`).

## Overview

The running host and every fresh (cold-boot) host authenticate to the now-**private**
`ghcr.io/jikig-ai/soleur-*` packages with two Doppler secrets — `GHCR_READ_USER` +
`GHCR_READ_TOKEN` — and `docker login ghcr.io … --password-stdin` (running host:
`ci-deploy.sh:561-563`; cold boot: `soleur-host-bootstrap.sh:181-184`, both on PR #6011).
The credential plumbing is **source-agnostic**: only *who writes the value* changes, not the
consumers.

This plan builds the writer. A new Inngest function reuses the existing
`generateInstallationToken(installationId, { permissions: { packages: "read" } })`
(`server/github-app.ts:749`) to mint a 1h `packages:read` token from the Doppler-stored App
key, then writes `GHCR_READ_TOKEN` + `GHCR_READ_USER=x-access-token` to Doppler `soleur/prd`
via the Doppler REST API. It runs on a **~20-min cron floor** (≤ TTL/3 → Doppler always holds
a live <40-min token) plus an **event-driven mint** on provision/deploy. A one-time
prerequisite adds `packages: read` to the App manifest → one org-owner re-consent.

**Scope boundary (per ADR-086):** control-plane *physical separation* from tenant hosts is
**NOT built here** — web-1 is simultaneously control plane and only workload today, and the
App key is already co-resident there (`github-app.tf`), so running the minter on web-1's
existing Inngest runtime adds zero marginal blast radius. The separation is a **hard gate
tied to #5274** (first tenant host) and is recorded as a gate, not implemented in this PR.

### ⚠️ Blocking risk that gates the entire approach (resolve in Phase 0 before any build)

External research surfaced a credible report that **GHCR `docker pull` may reject GitHub App
*installation* tokens** (community discussion github.com/orgs/community/discussions/171423),
accepting only classic PATs and the Actions `GITHUB_TOKEN`. If true, ADR-086's core mechanism
(`docker login ghcr.io -u x-access-token` with an installation token) **does not work** and
the entire plan is invalid. This is **not** resolvable from documentation — GitHub's behavior
here is package-linkage-dependent and under-documented. **Phase 0 is a hard empirical
go/no-go spike** that mints a real scoped token and attempts a real `docker login` + `docker
pull` of the private package. No build proceeds until the pull succeeds. If it fails, the plan
halts and the finding is surfaced to the operator as a decision-challenge (keep the PAT, or
pursue GitHub package-level fine-grained access) — see Phase 0 and Risks.

## Dependency & Sequencing (HARD)

**#6031 is hard-blocked-by #6011 (issue #6005).** PR #6011 — *still OPEN* — ships every
surface this plan layers onto: `ghcr-read-credential.tf` (the `doppler_secret` resources with
`ignore_changes = [value]`), the two consumers (`ci-deploy.sh` docker login,
`soleur-host-bootstrap.sh` doppler-get), `variables.tf` (the interim PAT vars), and **ADR-086
itself**. None of these exist on `origin/main` today.

- **Phase 0 precondition gate (fail-closed):** before `/work` builds anything, verify
  `origin/main` contains `apps/web-platform/infra/ghcr-read-credential.tf` **and**
  `knowledge-base/engineering/architecture/decisions/ADR-086-*.md`. If absent, PR #6011 has
  not merged — **halt** and rebase this branch onto post-#6011 `main`. Do NOT recreate #6011's
  artifacts here (that would double-author `ghcr-read-credential.tf` + ADR-086 and collide at
  merge). This mirrors the foundations-PR sequencing learning
  (`2026-05-07-foundations-pr-must-not-declare-downstream-contracts.md`).
- The interim PAT must remain the live `GHCR_READ_TOKEN` value **until** the minter is verified
  writing valid tokens (Phase 6 cutover). Do not revoke it before the minter's first
  end-to-end deploy + fresh-boot pass.

## Research Reconciliation — Spec vs. Codebase

The issue body was written against the **post-#6011 tree**, so several claims are false against
current `origin/main`. Reconciled:

| Issue / spec claim | Reality (verified) | Plan response |
|---|---|---|
| "`github-app-manifest.json` — absent today" | **Exists** at `apps/web-platform/infra/github-app-manifest.json`; a parity test (`test/github-app-manifest-parity.test.ts`) pins its permission set. `packages` is the only *absent* key. | Phase 1 **edits** the existing manifest (add `packages: read`) + updates the parity test's expected-permission set. Not a new file. |
| "per ADR-086" (cited as authority) | ADR-086 does **not** exist on `origin/main`; it is authored in PR #6011 (`status: active`, dated 2026-07-05). Highest ADR on main is ADR-085. | Do **not** create ADR-086. Phase 6 **confirms/amends** its status once the minter is live (issue "Done when: ADR-086 status confirmed"). No new ordinal. |
| "shipped in #6005 / ADR-085 D1" | The repo's `ADR-085` is *operational-inbox*, unrelated. "ADR-085 D1" is the credential-choice **section inside ADR-086** (which supersedes it); the tf comment in `ghcr-read-credential.tf` records the D1 PAT decision. | Treat ADR-086 as the sole authority; "ADR-085 D1" = the interim-PAT decision it supersedes. |
| "`ci-deploy.sh:561-563` + `soleur-host-bootstrap.sh:181-184` keep reading the two keys" | On `origin/main` those lines contain unrelated code and the host-bootstrap file is only ~150 lines. The cited lines are **correct against PR #6011**, where the docker-login/doppler-get consumers live. | Consumers are **unchanged** by this plan (correct once #6011 merges). No consumer edits. |
| "`ghcr-read-credential.tf` keeps `ignore_changes=[value]`" | Absent on main; present on PR #6011 with `ignore_changes = [value]` on both `doppler_secret` resources. | Correct — the minter owns value churn; terraform will not clobber. No tf edit to that file. |
| Installation token → `docker login ghcr.io` works | **UNVERIFIED / contested** (community report says installation tokens are rejected by GHCR pull). | **Phase 0 empirical go/no-go gate.** See blocking risk above. |
| "1h TTL, `packages:read` scoping, re-consent on new permission, JWT `exp` ≤ 600s" | **All confirmed** by framework research (GitHub REST docs). `createAppJwt()` already sets `exp = now + 540s`, `iat = now-60s` — safely under the ceiling. | Reuse `generateInstallationToken` / `createAppJwt` verbatim; no JWT changes. |

## User-Brand Impact

**If this lands broken, the user experiences:** every deploy (`ci-deploy.sh`) and every
fresh-host boot (`soleur-host-bootstrap.sh`) fails `docker login ghcr.io` → `docker pull`
returns "access denied" → **the platform cannot deploy or provision new hosts**. Because the
minter writes to the same Doppler key all hosts read, a bad write (empty/invalid token)
poisons the credential for *every* host at once.

**If this leaks, the user's [credentials / infrastructure] is exposed via:** (a) the minted
token — bounded: `packages:read`-only, single-install, 1h TTL, low blast radius; (b) **the
material this plan newly co-locates in app memory** — the write-capable Doppler service token
(scoped to `prd_ghcr` per Phase 2, so at-rest exposure is one throwaway config; runtime
compromise still reaches the App key) and the org-wide-**WRITE** App private key (already
resident on web-1, but the minter now signs with it on a schedule — the dominant surface); (c)
**the App *permission set* widening** — `packages:read` on the shared App is a per-installation
standing grant, so post-multi-tenant a key leak reads every consenting tenant's packages. These
are the real blast-radius surfaces, not the read token.

**Brand-survival threshold:** `single-user incident` — a broken or leaked credential path on
the deploy/provision critical line is a brand-survival event; `requires_cpo_signoff: true`.
CPO sign-off required at plan time before `/work`; `user-impact-reviewer` runs at review-time
(review skill conditional-agent block). This threshold also mandates `deepen-plan` (run next in
this pipeline) whose data-integrity + security-sentinel + architecture triad catches the
substance-class issues (Doppler-write-token scope, atomicity of the two-key write, missed-tick
staleness math) that style-only plan-review is blind to.

## Implementation Phases

### Phase 0 — Empirical GHCR go/no-go gate + #6011 precondition (BLOCKING, no build until green)

0.1 **#6011 precondition:** assert `origin/main` has `ghcr-read-credential.tf` + `ADR-086-*.md`
    (Dependency & Sequencing above). Halt + rebase if absent.
0.2 **GHCR installation-token spike — a package-linkage TEST MATRIX, not a binary halt**
    (advisor-refined). The Actions `GITHUB_TOKEN` that provably pulls GHCR *is itself* an
    installation token, so the mechanism is **not categorically invalid** — community rejection
    reports usually trace to the package not being *linked/granted* to a repo the App installation
    covers, or the installation's repo scope excluding it. A single failed pull would produce a
    **false-negative halt** and a wrong decision-challenge. Run the matrix (throwaway script, not
    committed): mint via `generateInstallationToken(<jikig-ai org install id>, { permissions: {
    packages: "read" } })`, then `printf '%s' "$TOKEN" | docker login ghcr.io -u x-access-token
    --password-stdin` + `docker pull ghcr.io/jikig-ai/soleur-web-platform@<known digest>` under:
    - **(a) package as-is** (current settings).
    - **(b) package explicitly linked to a repo the App installation covers, with that repo granted
      read in package settings.**
    - **(c) org-scoped vs repo-scoped installation** (if the two differ for jikig-ai).
    Record each outcome in the spec's Phase-0 evidence note.
    - **(b) PASS** → proceed. If (a) failed but (b) passed, the deliverable is **"add package↔repo
      linkage to provisioning"** — a config task folded into Phase 5/6, **not** an ADR-086 reversal.
    **Spike hygiene (security review):** the script mints a REAL 1h token — keep it uncommitted and
    never echo the token into CI logs/artifacts/terminal scrollback. **Scope-delta note:** if a pull
    succeeds only when the token also carries `contents:read` (repo-linked package visibility
    sometimes requires it), surface that as a **scope delta** (add `contents:read` to the mint +
    manifest) rather than a linkage-only fix — record which scopes the successful pull actually
    required.
    - **(b) FAIL** (installation tokens rejected even when correctly linked) → **halt the plan.**
      Persist a decision-challenge to `knowledge-base/project/specs/<branch>/decision-challenges.md`:
      "ADR-086's installation-token mechanism is rejected by GHCR pull even with correct package
      linkage; options: (a) retain the machine-account PAT interim + re-scope tenant onboarding,
      (b) GHCR package-level fine-grained access, (c) escalate to GitHub support." `ship` renders it
      into the PR body + files an `action-required` issue.
0.3 Confirm the **org installation id** to mint against (the `jikig-ai` org installation that owns
    the packages) — resolve via `findInstallationByAccountLogin("jikig-ai")`
    (`server/github-app.ts:646`) or a pinned `GITHUB_APP_INSTALLATION_ID`. Record it.
0.4 **Cross-config resolution + isolation assertion (HIGH — gates the Phase-2 `prd_ghcr` default;
    architecture review Q3).** "Tier supports referencing" is NOT the load-bearing question —
    whether a `prd`-**read** token *resolves* a value referenced from `prd_ghcr` is. Two failure
    shapes the design must exclude: (a) resolution needs the reader to also hold `prd_ghcr` access →
    the consumer's `prd` token gets an **empty** `GHCR_READ_TOKEN` → `docker login` fails on every
    host (the exact single-user incident); (b) Doppler resolves transitively → the `prd` read token
    can now reach into `prd_ghcr`, **silently defeating the isolation** Phase 2 exists to create.
    Empirically assert, with the **actual consumer `prd`-scoped token**: `doppler secrets download
    --config prd` returns the *resolved* `GHCR_READ_TOKEN` value **AND** that same token **cannot**
    enumerate/download `prd_ghcr`. Only if BOTH hold does the `prd_ghcr` cross-config default stand;
    else fall back to the `prd`-scoped write token with the R2 blast radius documented + a
    security-sentinel sign-off (Phase 2 contingency).

### Phase 1 — App manifest `packages: read` + parity test (prerequisite, org re-consent)

1.1 Edit `apps/web-platform/infra/github-app-manifest.json`: add `"packages": "read"` to
    `default_permissions`. **Blast-radius note (security review MEDIUM): this is a PER-INSTALLATION
    standing grant on the SHARED App, not "single-org."** Adding `packages:read` to
    `default_permissions` means every installation that re-consents grants `packages:read` on the
    shared App — and since this plan is the prerequisite for multi-tenant Concierge onboarding, a
    `GITHUB_APP_PRIVATE_KEY` leak would then read *every consenting tenant's* packages, not just
    jikig-ai's. Document this in ADR-086 (Consequences) and require explicit CPO acceptance that the
    shared App gains a cross-tenant `packages:read` standing grant. (The minted *token* is still
    1h/single-install/read-only; it is the App *permission set* that widens.)
1.2 Update `apps/web-platform/test/github-app-manifest-parity.test.ts` — add `packages: "read"`
    to the expected-permission assertion set (the test pins the exact set; an un-updated test
    fails on the new key).
1.3 **Three-plane grant (learnings `2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md`):**
    adding a permission to the App requires **org-owner re-consent** to activate the *installation
    grant* (plane c) — the manifest declaration (plane a) alone does not scope tokens. This is a
    genuine GitHub-console consent action. Per the automation-feasibility gate: attempt via
    Playwright against the App settings "review & accept new permissions" page; if a human gate
    (org-owner auth) is reached, record `playwright-attempt:` evidence and mark the re-consent a
    `### Post-merge (operator)` step. Verify plane-c post-consent by minting a scoped token and
    asserting `response.permissions.packages == "read"`.

### Phase 2 — Dedicated `prd_ghcr` Doppler config + narrow-scoped write token (IaC)

**Architecture (advisor-refined — the throwaway-config path is the DEFAULT, not a fallback).**
A `prd`-scoped `read/write` service token is worse than "can rewrite any prd secret": a
read/write token also **reads every `prd` secret** (incl. `GITHUB_APP_PRIVATE_KEY`), so a
compromised minter runtime = **full prd exfiltration** — which fails this plan's own
`single-user incident` threshold. Isolate to a throwaway config instead:

2.1 New Doppler **config `prd_ghcr`** (holds only the GHCR credential). New Terraform
    `doppler_service_token` scoped to `config = "prd_ghcr"`, `access = "read/write"` — its total
    read+write blast radius is that one config, nothing else.
2.2 **Cross-config secret referencing** so consumers stay unchanged: in `prd`, define
    `GHCR_READ_TOKEN = ${soleur.prd_ghcr.GHCR_READ_TOKEN}` and `GHCR_READ_USER =
    ${soleur.prd_ghcr.GHCR_READ_USER}` (one-time Doppler setup). Consumers keep reading
    `--config prd` (no #6011 change). The minter writes GHCR_READ_TOKEN/USER into `prd_ghcr`.
    **Verify Doppler plan tier supports secret referencing** before committing (framework probe);
    if unsupported, fall back to the `prd`-scoped token with the R2/R3 blast-radius documented and
    a security-sentinel sign-off in deepen-plan.
2.3 Publish the `prd_ghcr` write token `.key` **into the runtime — via DIRECT `prd_ghcr`
    injection, NOT a cross-config reference back into `prd` (security review MEDIUM).** Store it as
    a `prd_ghcr` secret `GHCR_MINTER_DOPPLER_TOKEN` and inject `prd_ghcr` directly into the minter
    runtime (dedicated mount/env). Do **not** mirror it into `prd` via `${soleur.prd_ghcr.…}` — that
    would let every `prd`-scoped *read* credential (the broad terraform token, CI) read the write
    token and poison `GHCR_READ_TOKEN` for all hosts, reintroducing the exact `prd`→`prd_ghcr`
    escalation the throwaway config exists to remove. (Only the two *read-only* consumer secrets
    `GHCR_READ_TOKEN`/`GHCR_READ_USER` are cross-referenced into `prd` per 2.2; the write token is
    never.) The App private key the minter signs with is injected by the **existing** path
    (`GITHUB_APP_PRIVATE_KEY` from `prd`) — different scope from the Doppler-write credential.
2.4 No new *no-default operator-mint* var (provider-minted by tf, `hr-tf-variable-no-operator-mint-default`).
    Confirm `apply-web-platform-infra.yml` auto-apply resolves cleanly (add to `-target` set if the
    root uses targeted apply). `dev` not provisioned (`hr-dev-prd-distinct`).

### Phase 3 — The minter Inngest function

3.1 New `apps/web-platform/server/inngest/functions/cron-ghcr-token-minter.ts`. Template:
    `cron-anthropic-credit-probe.ts` (id `cron-ghcr-token-minter` + `concurrency` + `retries`, a
    `[{ cron }, { event }]` trigger array, a handler taking `{ step, logger }`).
    - Trigger array: `[{ cron: "*/20 * * * *" }, { event: "ghcr/token-minter.mint-now" }]`
      (≤ TTL/3 floor + event-driven).
    - **Single `step.run("mint-and-write", …)` — do NOT split mint and write across two steps
      (security review HIGH).** Inngest persists every `step.run` return value to its state store to
      memoize across replays (the plan's own "Inngest run history" log surface); a `mint-token`
      step that *returns the token* serializes the raw 1h token into Inngest run state, readable in
      the run-output view — and the key-name-based Sentry scrubber (`server/sentry-scrub.ts`) does
      not touch Inngest's state store. So the token must **never cross a step boundary**: mint +
      Doppler-write happen inside one `step.run`, which returns **only non-secret metadata**
      (`{ dopplerStatus, permissionKeys, expiresAt }`) — never the token.
    - Inside that step: `generateInstallationToken(orgInstallId, { permissions: { packages:
      "read" } })`. **Mint FRESH — bypass/ignore the token cache OR assert `expires_at − now ≥ 40
      min` before writing (architecture review HIGH Q4):** the cache can return a token with ~25 min
      left, which would expire before the next 20-min tick's miss-margin, collapsing the ≤40<60
      staleness guarantee. Every written token must have ≥40 min remaining.
    - Then `POST https://api.doppler.com/v3/configs/config/secrets` with `{ project: "soleur",
      config: "prd_ghcr", secrets: { GHCR_READ_TOKEN: <token>, GHCR_READ_USER: "x-access-token" } }`,
      `Authorization: Bearer $GHCR_MINTER_DOPPLER_TOKEN`. This is a **partial named-secrets upsert** —
      it merges the two keys and leaves `GHCR_MINTER_DOPPLER_TOKEN` (co-resident in `prd_ghcr`)
      intact; never a full-config replace/PUT (security LOW — a replace would delete the minter's own
      credential). New capability — **no existing app code writes Doppler** (repo research GAP).
      Deliver the token via env, never argv (`2026-06-18-inngest-secrets-env-not-argv…`).
    - **Output-aware heartbeat** (`2026-06-01-output-aware-cron-heartbeat…`): a single terminal
      Sentry check-in `ok` **only if the Doppler write returned 2xx**; `error` otherwise. No
      two-step in_progress→ok pattern (`2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`).
3.2 Both keys are written **in one Doppler request** (atomic) so a partial write never leaves
    `x-access-token` paired with a stale token or vice-versa.
3.3 Fail-loud but **secret-safe capture (security review MEDIUM-HIGH):** a mint 401/403 or non-2xx
    Doppler write throws (Inngest `retries` + terminal `error` heartbeat) — never a silent fallback
    (`cq-silent-fallback-must-mirror-to-sentry`). The Doppler REST request AND its 2xx response body
    both echo the token value, and the scrubber is **key-name-based, not value-based**, so a token
    embedded in a captured `extra.body` string or `Error.message` is NOT redacted. Captures on the
    failure path read the **numeric HTTP status ONLY** — never the request or response body, never
    the token — enforced by AC + unit assertion (AC-Sec below).

### Phase 4 — Five-registry Inngest lockstep (all in this PR)

Per `2026-06-05-new-inngest-cron-requires-five-registry-lockstep.md`, a new cron is not "done"
until all five are updated with a byte-identical slug:
1. `apps/web-platform/app/api/inngest/route.ts` — import + add to the served function array.
2. `apps/web-platform/server/inngest/cron-manifest.ts` — add slug to `EXPECTED_CRON_FUNCTIONS`.
3. `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — bump the count.
4. `apps/web-platform/infra/sentry/cron-monitors.tf` — new `sentry_cron_monitor` (slug ==
   handler's `SENTRY_MONITOR_SLUG` byte-for-byte; per the `scheduled-<name>` convention
   (`cron-anthropic-credit-probe.ts:42` → `"scheduled-anthropic-credit-probe"`) use
   **`scheduled-ghcr-token-minter`**; schedule matches `*/20 * * * *`). Reuse the existing
   `postSentryHeartbeat({ ok, sentryMonitorSlug, cronName, logger })` helper.
5. `.github/workflows/apply-sentry-infra.yml` — add `-target=sentry_cron_monitor.<name>`.
   (Verify against `2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md`: also
   sweep any sentry `-target` scope-guard test for the new monitor type.)

### Phase 5 — Event-driven mint on provision/deploy

5.1 Emit `ghcr/token-minter.mint-now` (via `inngest.send`) at the provision/deploy trigger point
    so a host provisioned between cron ticks gets a fresh token immediately. Identify the existing
    deploy/provision event surface (e.g. the deploy webhook / release path) and add the send;
    if no clean in-app surface exists, document that the ~20-min floor already bounds staleness to
    ≤40 min < 60-min TTL and defer the event-driven optimization to a tracked follow-up (do not
    invent a surface).

### Phase 6 — Cutover, PAT revocation, ADR/C4 confirm, #6023 close (post-merge, gated)

6.1 After the minter is live and has written a valid token, verify **a real deploy** and **a
    fresh-host boot** both authenticate with the minted token (read the `docker login` success in
    ci-deploy / cloud-init telemetry — no SSH).
6.2 Only then **revoke the interim machine-account PAT** (GitHub console — automation-feasibility:
    Playwright attempt; a fine-grained-PAT revoke page may be reachable, else operator step with
    `playwright-attempt:` evidence). `Ref #6005` (not `Closes`) since revocation is post-merge.
6.3 **Confirm/amend ADR-086 status** — note the minter is shipped (issue "Done when"). No new ADR.
6.4 **C4** — see Architecture Decision section.
6.5 **Close #6023's proactive-PAT-expiry alarm item as moot** (a 1h auto-refreshed token has no
    ≤1yr silent-expiry SPOF; a failed refresh pages via the terminal `error` heartbeat within one
    cron tick). `gh issue` comment on #6023 noting the alarm sub-item is moot per ADR-086.

## Files to Edit / Create

**Create:**
- `apps/web-platform/server/inngest/functions/cron-ghcr-token-minter.ts` — the minter.
- `apps/web-platform/infra/ghcr-minter-doppler-token.tf` — the `prd_ghcr` config, a
  `prd_ghcr`-scoped read/write `doppler_service_token`, its `doppler_secret` publish
  (`GHCR_MINTER_DOPPLER_TOKEN`), and the `prd` cross-config references
  (`GHCR_READ_TOKEN`/`GHCR_READ_USER = ${soleur.prd_ghcr.…}`).
- (test) `apps/web-platform/test/server/inngest/cron-ghcr-token-minter.test.ts` — deterministic
  (mock the Doppler fetch + `generateInstallationToken`, no live GitHub —
  `2026-04-19-llm-sdk-security-tests…`): mint-scope body; atomic two-key write; output-aware
  heartbeat ok/error; **single-`step.run` metadata-only return (AC-Sec1)**; **token string absent
  from every captured Sentry field (AC-Sec2)**; **≥40-min freshness floor (AC-Sec3)**; partial-upsert
  (not full-replace) Doppler write.

**Edit:**
- `apps/web-platform/infra/github-app-manifest.json` — add `packages: read`.
- `apps/web-platform/test/github-app-manifest-parity.test.ts` — expected-permission set.
- `apps/web-platform/app/api/inngest/route.ts` — serve the new function.
- `apps/web-platform/server/inngest/cron-manifest.ts` — `EXPECTED_CRON_FUNCTIONS` slug.
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — count bump.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — `sentry_cron_monitor`.
- `.github/workflows/apply-sentry-infra.yml` — `-target` for the monitor.
- (Phase 5, conditional) the deploy/provision event surface — `inngest.send("ghcr/token-minter.mint-now")`.
- `knowledge-base/engineering/architecture/decisions/ADR-086-*.md` — status confirm (Phase 6).
- `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4}` — minter edges + ghcr
  description (Architecture Decision section).

**Do NOT edit** (owned by #6011): `ghcr-read-credential.tf`, `ci-deploy.sh`,
`soleur-host-bootstrap.sh`, `variables.tf` (interim PAT vars).

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor 'scheduled-ghcr-token-minter' terminal check-in each run (output-aware: ok only on 2xx Doppler write)"
  cadence: "every 20 min (*/20 * * * *)"
  alert_target: "Sentry cron-monitor missed/errored check-in → existing Sentry alert routing"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf + handler SENTRY_MONITOR_SLUG"
error_reporting:
  destination: "Sentry (captureException) on mint 401/403 or non-2xx Doppler write"
  fail_loud: "handler throws → Inngest retry + terminal 'error' heartbeat; no silent fallback"
failure_modes:
  - mode: "GitHub mint returns 401/403 (JWT/clock-skew or grant missing)"
    detection: "in-function Sentry captureException with {installationId, status}; existing generateInstallationToken 401-retry exhausts then throws"
    alert_route: "Sentry issue alert + missed cron check-in"
  - mode: "Doppler write non-2xx (token scope wrong / API down)"
    detection: "in-function captureException with {dopplerStatus}; terminal heartbeat 'error'"
    alert_route: "Sentry cron-monitor errored check-in"
  - mode: "Silent stale token (function green but wrote nothing / same value)"
    detection: "output-aware heartbeat gates 'ok' on actual 2xx write; a run that skips the write emits 'error' not 'ok'"
    alert_route: "Sentry missed-checkin if no ok within 40 min"
logs:
  where: "Inngest run history (loopback :8288) + Sentry breadcrumbs; run-log middleware"
  retention: "Inngest run history + Sentry default retention"
discoverability_test:
  command: "gh api / Inngest run-list + Sentry monitor status; freshness via `doppler secrets get GHCR_READ_TOKEN --config prd` presence (NOT value in logs)"
  expected_output: "monitor status=ok within last 20 min; GHCR_READ_TOKEN present and non-empty"
```

**Soak follow-through (Phase 2.9.1):** the "Done when" post-deploy criterion (a real deploy +
fresh-host boot authenticate with the minted token) is a soak-gated close. Enroll a
`scripts/followthroughs/ghcr-minter-live-6031.sh` (exit 0 when the Sentry monitor has ≥1 `ok`
check-in AND the most recent deploy's `docker login` telemetry succeeded post-cutover) + a
`<!-- soleur:followthrough script=… earliest=<deploy+1d> -->` tracker directive with the
`follow-through` label, so the interim-PAT-revoked closure is automated, not memory-gated.

## Infrastructure (IaC)

### Terraform changes
- New `apps/web-platform/infra/ghcr-minter-doppler-token.tf`: a `doppler_config` `prd_ghcr`, a
  `doppler_service_token` (`project = "soleur"`, `config = "prd_ghcr"`, `access = "read/write"`),
  a `doppler_secret` `GHCR_MINTER_DOPPLER_TOKEN` publishing its `.key`, and the `prd` cross-config
  reference secrets. Total token blast radius = the `prd_ghcr` config only (not all of `prd`).
  Providers: `doppler` (already used). Sensitive: the token `.key` lands in `terraform.tfstate`
  (R2 encrypted backend — same posture as `doppler-write-token.tf`). No new no-default operator var.
- Edit `apps/web-platform/infra/sentry/cron-monitors.tf` + `.github/workflows/apply-sentry-infra.yml`
  (`-target`).

### Apply path
- (b) cloud-init + idempotent auto-apply: `apply-web-platform-infra.yml` fires on `infra/*.tf`
  merge; `apply-sentry-infra.yml` on the sentry `-target`. No SSH. The runtime picks up
  `GHCR_MINTER_DOPPLER_TOKEN` on the next container restart (release pipeline restarts on
  `apps/web-platform/**` merge — no separate operator restart).

### Distinctness / drift safeguards
- `ghcr-read-credential.tf` keeps `ignore_changes = [value]` (owned by #6011) — the minter's
  Doppler writes do not cause terraform drift. `dev` intentionally NOT provisioned (hosts read
  `--config prd` only; `hr-dev-prd-distinct-supabase-projects`).

### Vendor-tier reality check
- Doppler API writes + GitHub App mint are on existing paid/included tiers. ~72 mint calls/day —
  negligible vs GitHub App rate limits. No paid-tier gate.

## Architecture Decision (ADR/C4)

### ADR
- **ADR-086** already exists (PR #6011). This plan makes **no new ADR** and claims no new
  ordinal. Phase 6 amends ADR-086: flip status language from "interim/staged-hybrid" to record
  the minter as shipped, and append the Phase-2.3 Doppler-write-token blast-radius consequence.
  (If Phase 0 fails, ADR-086 is instead amended to record the GHCR-installation-token rejection
  and the chosen fallback.)

### C4 views
Read all three (`model.c4`, `views.c4`, `spec.c4`) — completeness mandate. External systems &
edges the minter changes:
- **ghcr** (`model.c4:242-244`) description currently says **"Public GHCR registry"** — now
  **stale** (going private via #6011). Update to private + token-authed pulls (coordinate with
  #6011; if #6011 already corrected it, no-op). External actors: none new (machine-to-machine).
- New edges to add in `model.c4` + ensure rendered in `views.c4` (github, doppler, ghcr, inngest
  are already in the view include list at `views.c4:14,33,36`):
  - `inngest -> github "Mints packages:read installation token (ADR-086)" { technology "HTTPS (GitHub App JWT → access_tokens)" }`
  - `inngest -> doppler "Writes GHCR_READ_TOKEN (1h scoped)" { technology "HTTPS (Doppler API)" }`
  - annotate the existing `hetzner -> ghcr` pull edge (`model.c4:321`) as token-authed.
- Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after editing (a
  `view include` of an undefined element fails there, not at `tsc`).

## Domain Review

**Domains relevant:** Engineering (primary — infra/security/CI). No Product/UX (no UI surface:
Files-to-Create/Edit contain zero `components/**`, `app/**/page.tsx`, `app/**/layout.tsx` — the
mechanical UI-surface override does not fire → Product **NONE**). No Legal/GDPR (machine
credentials only, no personal data). Operations touched (Doppler/Inngest infra) but folded into
Engineering.

### Engineering
**Status:** reviewed (carried to plan-review + deepen-plan)
**Assessment:** Credential-minting on the deploy/provision critical path at `single-user
incident` threshold. Primary CTO/architecture concerns — (1) the Phase-0 GHCR-installation-token
viability gate, (2) the `prd`-scoped Doppler write token's config-wide blast radius, (3) atomic
two-key write, (4) missed-tick staleness math (≤40 < 60 min) — are routed to the `deepen-plan`
data-integrity + security-sentinel + architecture triad (mandatory at this threshold) and the
5-agent plan-review panel (incl. CTO devex lens). No separate domain-leader spawn; coverage is
the review pipeline.

### Product/UX Gate
**Tier:** none — no user-facing surface.

## Acceptance Criteria

### Pre-merge (PR)
- AC1 **Phase-0 gate recorded PASS.** The spec's Phase-0 evidence note shows a real
  `packages:read` installation token successfully `docker login`'d + `docker pull`'d the private
  package (or, on FAIL, the plan halted and a decision-challenge was filed — no minter shipped).
- AC2 `github-app-manifest.json` `default_permissions.packages == "read"`; parity test updated
  and green (`vitest run test/github-app-manifest-parity.test.ts` via
  `cd apps/web-platform && ./node_modules/.bin/vitest run …`).
- AC3 The minter mints with the **scoped** body only: a unit test asserts the serialized
  `access_tokens` request carries `{"permissions":{"packages":"read"}}` and that the Doppler
  write request carries **both** `GHCR_READ_TOKEN` and `GHCR_READ_USER: "x-access-token"` in **one**
  request (atomicity).
- AC4 Output-aware heartbeat: unit test proves the handler emits terminal `ok` **only** when the
  Doppler write mock returns 2xx, and `error` on non-2xx / mint throw.
- AC-Sec1 **Token never crosses a step boundary:** the handler uses a **single** `step.run`
  (mint+write) that returns only non-secret metadata (`{dopplerStatus, permissionKeys, expiresAt}`);
  a test asserts no `step.run` return value contains the token string.
- AC-Sec2 **No token in captures:** the Doppler-write failure path captures the numeric HTTP status
  only; a unit test asserts the token value string never appears in any captured Sentry field
  (`extra`/`tags`/`message`).
- AC-Sec3 **Freshness floor (Q4):** a test asserts the minter writes only a token with
  `expires_at − now ≥ 40 min` (fresh mint, not a stale cache hit).
- AC-Sec4 **Cross-config isolation (Phase 0.4):** evidence note shows the consumer `prd`-scoped
  token resolves `GHCR_READ_TOKEN` via `prd` AND cannot enumerate `prd_ghcr` (else the fallback
  `prd`-scoped form with security sign-off is used).
- AC5 **Five-registry lockstep** all present in the diff: `route.ts` serves it, `cron-manifest.ts`
  `EXPECTED_CRON_FUNCTIONS` has `cron-ghcr-token-minter`, `function-registry-count.test.ts` count
  bumped and green, `cron-monitors.tf` monitor `name`/`SENTRY_MONITOR_SLUG == "scheduled-ghcr-token-minter"`
  byte-for-byte, `apply-sentry-infra.yml` `-target` added.
- AC6 `ghcr-minter-doppler-token.tf` declares the `prd_ghcr` config, a `prd_ghcr`-scoped
  `read/write` `doppler_service_token`, `GHCR_MINTER_DOPPLER_TOKEN`, and the `prd` cross-config
  reference secrets; `terraform validate`/`tofu validate` passes; blast-radius comment present.
  (If Doppler tier lacks secret referencing, the fallback `prd`-scoped form ships only with a
  recorded security-sentinel sign-off.)
- AC7 `tsc --noEmit` (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`) and full test
  suite green.
- AC8 C4: `model.c4` has the two minter edges + corrected ghcr description; `c4-code-syntax.test.ts`
  + `c4-render.test.ts` green.
- AC9 PR body uses `Ref #6005` / `Ref #6023` (not `Closes`) — closures are post-merge/soak-gated.

### Post-merge (operator / gated)
- AC10 Org-owner **re-consent** to the App's new `packages: read` permission activated (plane-c);
  a scoped mint returns `permissions.packages == "read"`.
- AC11 Minter live: Sentry monitor `scheduled-ghcr-token-minter` shows `ok` within 20 min;
  `GHCR_READ_TOKEN` in `prd` resolves to a fresh installation token (`x-access-token` user).
- AC12 A real deploy **and** a fresh-host boot both authenticate with the minted token (ci-deploy
  / cloud-init `docker login` telemetry success — no SSH).
- AC13 Interim machine-account PAT **revoked** (only after AC12); ADR-086 status amended; #6023
  proactive-expiry alarm item closed as moot.

## Test Scenarios
- Unit (deterministic, mocked): scoped-mint body; atomic two-key Doppler write; heartbeat
  ok-only-on-2xx; heartbeat error on mint-throw and on Doppler-non-2xx.
- Registry: `function-registry-count.test.ts` reflects +1; manifest parity green.
- IaC: `terraform validate` on the new tf; sentry monitor slug parity.
- C4: syntax + render tests.
- **No** integration test hits live GitHub/GHCR/Doppler in CI (Phase-0 spike is a one-time manual
  gate; `hr-dev-prd-distinct` — no prod-write synthetic test paths).

## Risks & Mitigations
- **R1 (P0, plan-defining): GHCR rejects installation tokens for pull.** → Phase-0 empirical gate;
  halt + decision-challenge on fail. Verified live before any build; not assumed from docs.
- **R2: Doppler write token blast radius.** A `prd`-scoped read/write token can *read AND write*
  every prd secret → **at-rest** exfiltration surface (tfstate, Doppler dashboard, isolated leak).
  → **Resolved to the `prd_ghcr` throwaway-config default** (Phase 2), gated on the Phase-0.4
  cross-config resolution+isolation assertion, with direct `prd_ghcr` runtime injection (not a
  `prd` mirror) per 2.3. **Benefit scope (security LOW-MEDIUM): `prd_ghcr` narrowing helps
  token-AT-REST only, NOT runtime compromise** — 2.3 keeps `GITHUB_APP_PRIVATE_KEY` (org-wide WRITE)
  in the same process env, the dominant runtime surface regardless of Doppler scope; do not overclaim
  "compromised minter ≠ prd exfiltration." Contingency: if Phase 0.4 fails, fall back to the `prd`
  write token with a security-sentinel sign-off.
- **R2b: token cache vs staleness (architecture HIGH Q4).** A cache hit can write a token with <40
  min remaining, expiring before the next tick's miss-margin. → mint fresh / assert ≥40 min remaining
  before writing (Phase 3.1); reconciled with the cache Sharp Edge.
- **R2c: token leak via Inngest step-state / Sentry capture (security HIGH + MEDIUM-HIGH).** →
  single `step.run` returning metadata-only (3.1); failure-path captures read numeric status only
  (3.3); unit assertion the token string never appears in any Sentry field (AC-Sec).
- **R3: partial write pairs `x-access-token` with a stale token** → single atomic Doppler request
  (AC3); partial named-secrets upsert preserves `GHCR_MINTER_DOPPLER_TOKEN` (never full-config replace).
- **R4: missed cron tick** → 20-min floor (≤ TTL/3) survives one miss (≤40 < 60 min); a second
  consecutive miss pages via missed-checkin before TTL expiry.
- **R5: manifest permission added but installation grant not re-consented** (three-plane drift) →
  AC10 verifies plane-c by asserting `response.permissions.packages`.
- **R6: revoking the PAT before the minter is proven** → Phase 6 gates revocation on AC12.

## Sharp Edges
- The `## User-Brand Impact` threshold is `single-user incident` → `deepen-plan` Phase 4.6 will
  **halt** if that section is empty/placeholder. It is filled; keep it.
- ADR-086 ordinal is **claimed by #6011** — do not author a new ADR-086 here, and do not renumber.
  `ship`'s ADR-ordinal collision gate assumes new ADRs; this plan has none.
- Doppler service tokens are **config-scoped, not secret-scoped** — the *only* way to bound the
  minter's blast radius is the separate `prd_ghcr` config (Phase 2). A `prd`-scoped read/write
  token also **reads** every prd secret, not just writes — do not frame it as write-only.
- `createAppJwt()` already sets `exp = now+540s` — do **not** re-introduce a 600s `exp` in any new
  minting code (`2026-05-28-github-app-jwt-exp-at-600s-ceiling…`).
- Cron token cache: `generateInstallationToken` keys its cache on scope
  (`installationTokenCacheKey(id, permissions, repositories)`) — the scoped `packages:read` call
  gets its own entry. **But the minter must NOT write a stale cached token** (architecture HIGH Q4):
  a cache hit can be <40 min from expiry, which breaks the ≤40<60 staleness guarantee. The minter
  either bypasses the cache or asserts `expires_at − now ≥ 40 min` before writing to Doppler. (Other
  callers keep the cache; only the minter's *write* path needs the freshness floor.)

## Open Code-Review Overlap
Checked planned files against 61 open `code-review` issues. One incidental hit: **#2246**
(low-severity KB polish) mentions `github-app.ts` — unrelated to the minter logic (types/dead-prop
cleanup elsewhere in the file). **Acknowledge** (different concern, remains open). No other
overlap.

## Alternatives / Non-Goals
- **Non-goal: physical control-plane separation from tenant hosts.** Deferred to the #5274 cutover
  gate per ADR-086 (web-1 already co-hosts the App key; zero marginal blast radius today). **Record
  the gate as a committed artifact, NOT a GitHub-issue comment (architecture review MEDIUM Q2 — an
  issue comment is the durability anti-pattern):** fold the separation gate into the Phase-6 ADR-086
  amendment (already being edited), and have it **enumerate BOTH control-plane-resident credentials
  the cutover must relocate — the `GITHUB_APP_PRIVATE_KEY` AND the new `prd_ghcr`
  `GHCR_MINTER_DOPPLER_TOKEN`** (this PR newly co-locates the second on the shared host; an issue
  comment could silently omit it). A `#5274` reference is fine as a pointer, but the ADR is the SoT.
- **Rejected: on-host mint (ADR-086 Option A)** — forces the org-wide-WRITE App key onto every
  fresh tenant host; fails cold-boot. **Rejected: revert to public GHCR (Option C)** — operator/CPO
  confirmed keep-private (ADR-085 context).
- **Deferred (conditional): event-driven mint (Phase 5)** if no clean in-app deploy/provision event
  surface exists — the 20-min floor already bounds staleness; file a follow-up rather than invent a
  surface.
