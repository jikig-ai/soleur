<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed: this plan introduces NO new infrastructure. It edits the
  host-resident ci-deploy.sh, delivered to running hosts via the EXISTING
  apply-deploy-pipeline-fix.yml auto-apply (HTTPS /hooks/infra-config, no SSH).
  See the ## Infrastructure (IaC) section. No manual provisioning step exists.
-->
---
title: "fix(infra): deploy GHCR image_pull_failed — recover on pull-denial, not only login-failure (§1A gap)"
date: 2026-07-14
type: fix
issue: 6400
severity: P1
lane: cross-domain
brand_survival_threshold: aggregate pattern
refs: ["#6395", "#6396", "#6090", "#6031", "#6122", "ADR-088", "ADR-096", "ADR-087"]
---

# fix(infra): deploy GHCR `image_pull_failed` — recover on pull-denial, not only login-failure (§1A gap)

## Overview

The `web-platform-release` deploy job fails at the `deploy` step with
`ci-deploy.sh exited 1 (reason=image_pull_failed)`; Sentry `WEB-PLATFORM-59`
records `image pull failed (auth_denied)`. Prod (web-1) is frozen on the last
green build; every new merge fails the same way. PR #6395's §1A (re-fetch the
GHCR credential from Doppler + retry `docker login` on a login **FAILURE**, not
only on EMPTY) was applied to the host but the redeploy still `auth_denied` —
**necessary-but-insufficient**.

**Root cause (structural, confirmed by code + telemetry-of-record):** §1A's
recovery is gated on the outcome of `docker login`
(`ghcr_prelude_and_login`, `ci-deploy.sh:655-683`). But the production failure
surfaces one step later, at `docker pull` inside `pull_image_with_fallback`
(`ci-deploy.sh:750-782`, called at `:1439`), which has **no credential
re-fetch/relogin/retry** — it emits `pull_failure_event` and aborts. A
credential that **logs in successfully but cannot pull** therefore bypasses §1A
entirely: login succeeds → §1A is skipped → the pull denies →
`image_pull_failed`. Two independently-sufficient conditions produce exactly
this shape, and **the same fix covers both**:

1. **A GitHub App installation token is baked/used.** GHCR accepts App
   installation tokens for `docker login` but returns `denied` on `docker pull`
   of private repo-linked packages — a confirmed GitHub platform limitation
   (`knowledge-base/project/learnings/2026-07-06-ghcr-app-token-cannot-pull-and-oidc-needs-native-identity-source.md`;
   ADR-088 is **superseded** on exactly this fact). If the host's baked
   `/etc/default/soleur-ghcr-read` snapshot is an App token, login-ok + pull-deny
   is guaranteed and §1A never fires.
2. **A rotated/revoked PAT where the baked login nonetheless returns success**
   (edge case) — again login-ok, pull-deny, §1A skipped.

**The durable fix:** move the credential recovery to the site where pull
capability is actually proven — the pull itself. On a GHCR `docker pull`
classified `auth_denied`, re-fetch the CURRENT `prd` credential (the valid
pull-capable PAT — Doppler `prd` holds it and the host's `prd`-scoped
`DOPPLER_TOKEN` can read it), `docker login` again, and retry the pull **once**
before aborting. `login`-success is not proof of `pull` capability; only a pull
attempt is. This is delivered as an edit to the host-resident `ci-deploy.sh`,
which auto-applies to the running host on merge via
`apply-deploy-pipeline-fix.yml` (HTTPS `/hooks/infra-config` file delivery — **no
SSH, no image pull required to land the fix**); the next release deploy then
self-recovers. Zero human steps.

This hardens the **interim GHCR PAT pull path** that ADR-096 (#6122) keeps live
as break-glass until the self-hosted `zot` registry soak completes. It does not
change the registry substrate, the token TTL, the minter (which stays disabled),
or the App permission set.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6400 / KB record) | Reality (verified this session) | Plan response |
|---|---|---|
| "`DOPPLER_TOKEN` may be **absent** in the webhook/deploy exec context → §1A skipped." | `DOPPLER_TOKEN` **is present**: `cloud-init.yml:408` writes it into `/etc/default/webhook-deploy` (deploy:deploy 0600); `webhook.service:7` sources it; sibling units use it to run `doppler … --config prd`. | Discard the "token absent" hypothesis. Fix does not depend on injecting a token; it depends on recovering at the pull site. Confirm at /work Phase 0 from Vector logs (PRELUDE lines), not by assumption. |
| "§1A re-fetches from `prd` (the deruelle **PAT**, long-lived); baked comes from `prd_terraform` (**App-minted**, expiring) — different cred **classes**." | `prd.GHCR_READ_TOKEN` = valid pull-capable **PAT** (HTTP-200 live-pull proof + App-tokens-can't-pull fact + **minter disabled** `GHCR_MINTER_DISABLED=true`, `cron-ghcr-token-minter.ts:74-89`). `var.ghcr_read_token` (baked source, from `prd_terraform`) is documented as the **same machine-account PAT** (`variables.tf:335-345`, `ghcr-read-credential.tf`). | The re-fetch **class** is correct (both PAT). The real gap is not class-mismatch on re-fetch but that recovery never runs on a login-ok/pull-deny cred. The baked value is a **boot snapshot** never re-baked on a running host (`server.tf` `lifecycle.ignore_changes=[user_data]`), so it can drift stale/App even when the source is a PAT. |
| Learning `2026-07-13-…-stale-baked-cred.md:71` asserts `var.ghcr_read_token` is "the ADR-088 App-installation-minted read cred." | Contradicts `variables.tf:335-345` (PAT) AND the HTTP-200 pull proof in the same learning file (:30-32). It is a stale/incorrect "reconciled false positive." | In-PR doc fix: correct that line to "machine-account read:packages PAT (interim, ADR-087 D1); App-minted minter is disabled (can't pull GHCR)." Prevents future misdiagnosis. |
| Remediation option 4: "Land #6396 observability FIRST." | #6396 is **merged** (commit `c749e4e6a`): Vector ships host journald→Better Stack + `pull_failure_event` carries `host_id`. | The blind spot is closed. /work Phase 0 pulls this telemetry to confirm which branch executed before/while shipping the fix (diagnosis-first). |

## User-Brand Impact

**If this lands broken, the user experiences:** no direct new breakage — the fix
is **fail-open** (a recovery attempt that, on failure, leaves the identical
`image_pull_failed` terminal state as today). Worst case is "still frozen," never
"more broken." The user-visible harm is the *pre-existing* one this fixes: prod
stays frozen on an old build, so no feature/fix/security patch can reach the one
prod host serving all users.

**If this leaks, the user's data is exposed via:** no new exposure vector. The
change handles a GHCR read credential that is piped to `docker login` via
`--password-stdin` only, never argv/logs, and unset after use (unchanged
discipline). No user data, schema, or PII surface is touched.

**Brand-survival threshold:** `aggregate pattern` — a fleet-wide deploy-pipeline
availability regression, not a per-single-user data incident. The fix's fail-open
design bounds the blast radius of a bad change to "no change from current frozen
state." (Sensitive-path note: touches `apps/web-platform/infra/*.sh` — a
credential-handling surface — so the section is mandatory and present;
`reason: fleet-wide deploy reliability, fail-open, no data surface`.)

## Hypotheses (L3→L7 — network-outage checklist honored)

The issue text contains "SSH"/"timeout" tokens, triggering the network-outage
checklist. The symptom is **L7 auth (HTTP 401/`denied`)**, not L3/L4
connectivity — but the checklist's L3-first discipline is honored by explicitly
ruling out the lower layers with artifacts:

1. **L3 firewall / egress — RULED OUT (artifact).** The credential pulls the
   exact denied tags off-host to **HTTP 200** (issue evidence) and the registry
   returns HTTP status codes (`401`/`200`), not `ECONNREFUSED`/`EHOSTUNREACH`/
   timeout. A registry that answers HTTP is reachable; egress-IP/firewall drift
   would produce a connect failure, not an auth denial. No firewall change is
   proposed.
2. **L3 DNS / routing — RULED OUT.** `ghcr.io` resolves and completes a TLS
   handshake (the 401/200 responses prove the request reached GHCR's origin).
3. **L7 TLS/proxy — N/A.** Pull is direct host→ghcr.io over the host's
   unrestricted egress (ADR-087 B′); no CF edge on this path.
4. **L7 application/auth — THE FAULT.** `pull_result=auth_denied` is a
   credential capability failure (login-capable, pull-incapable cred, or a
   revoked baked snapshot). Fix at this layer. Verification artifact at /work
   Phase 0: Better Stack Vector query for the `ci-deploy` PRELUDE lines + Sentry
   `op:image-pull pull_result:auth_denied` grouped by `host_id`.

## Root-cause verification gate (/work Phase 0 — diagnosis-first, no SSH)

Per the recurring-prod-symptom discipline (a fix that survived a prior fix must
be pinned to the executing path from production observability, not code-reading
alone), Phase 0 MUST establish **which branch executed** before relying on the
fix targeting it — now possible because #6396 shipped the telemetry:

- **Sentry (API, no dashboard eyeballing):** query `op:image-pull` events since
  the incident window, grouped by `host_id` and `pull_result`. Confirms
  `auth_denied` and per-host attribution.
- **Better Stack Vector logs** (`betterstack-query.sh`, source 2457081): pull the
  `ci-deploy` `PRELUDE:` lines for the failing host+window. The decisive
  discriminator:
  - `docker login … ok (private-package pull authenticated)` **followed by**
    `IMAGE_PULL_FAIL … auth_denied` ⇒ **login-ok / pull-deny** (Scenario 1/2) —
    the exact gap this fix closes.
  - `docker login … FAILED …` + `re-fetch … STILL FAILED` ⇒ §1A ran and the
    re-fetch itself failed ⇒ additionally investigate the `prd` value/scope
    before relying on the pull-site recovery (same helper still applies).
- **Current prod state:** `curl -s https://app.soleur.ai/health | jq .version`.
  If prod has already been hand-recovered (re-bake/recreate) since filing, the
  deliverable is the **durable structural hardening** so the class cannot recur;
  the fix ships regardless.

If Phase 0 shows **zero** `op:image-pull auth_denied` events on any live host
(fully self-recovered and no recurrence), record it and still ship the
structural fix — the login-ok/pull-deny gap is real in the code regardless of
whether it is currently firing.

## Implementation Phases

### Phase 1 — Extract a shared GHCR re-fetch/relogin helper (`ci-deploy.sh`)

Factor the credential recovery out of §1A's inline retry into a reusable helper
so the pull site can call the identical logic (no duplication):

```bash
# refetch_ghcr_and_relogin: re-fetch the CURRENT prd GHCR read cred and re-run
# docker login. Returns 0 on a successful login, 1 otherwise. Fail-open callers.
# Token via --password-stdin only; never argv/logs; unset after. Re-exports
# GHCR_READ_USER so the :ro cosign docker config (mounted at verify) authenticates
# with the retried cred. Guarded on doppler + DOPPLER_TOKEN (prd-root scoped).
refetch_ghcr_and_relogin() { ... }   # body mirrors ci-deploy.sh:669-679
```

Replace the inline body at `ci-deploy.sh:669-679` (§1A) with a call to this
helper — behavior byte-identical, one source of truth.

### Phase 2 — Recover at the pull site (`pull_image_with_fallback`, `ci-deploy.sh:750-782`)

On a **GHCR** `docker pull` failure classified `auth_denied`, attempt recovery
before giving up. Applies to BOTH GHCR pull branches (the zot→GHCR atomic
fallback at `:765` and the zot-dark GHCR path at `:775`):

```bash
# after a GHCR `docker pull … 2>"$perr"` fails:
if _pull_result_is_auth_denied "$perr" && refetch_ghcr_and_relogin; then
  if docker pull "${IMAGE}:${TAG}" 200>&- 2>"$perr"; then
    pull_auth_recovery_event "${IMAGE}:${TAG}" recovered   # discriminating breadcrumb
    return 0
  fi
fi
pull_auth_recovery_event "${IMAGE}:${TAG}" not_recovered   # only when a recovery was attempted
pull_failure_event "${IMAGE}:${TAG}" "$(tail -c 400 "$perr")"
return 1
```

- `_pull_result_is_auth_denied` reuses the existing classifier regex in
  `pull_failure_event` (`ci-deploy.sh:525`) — extract it to a tiny predicate so
  the two agree by construction (do NOT duplicate the regex).
- **zot** pull failures are NOT auth-recovered here — the atomic GHCR fallback
  already covers zot-down, and the zot cred is a different class/registry; recovery
  targets only the GHCR credential. (zot is dark in prod today anyway.)
- Retry the pull exactly **once** (no loop). Fail-open: on recovery miss, the
  terminal state is the unchanged `image_pull_failed` — never worse than today.

### Phase 3 — Discriminating recovery telemetry (`pull_auth_recovery_event`)

Add a fail-open, env-guarded Sentry breadcrumb (mirror `pull_failure_event`'s
transport + `host_id` tag) fired ONLY when a pull-site auth recovery is
attempted. One event answers, without SSH, the exact question the incident was
blind to: **did recovery fire, and did it succeed?**

- Tags: `feature:supply-chain op:image-pull-recovery host_id:<id> outcome:{recovered|not_recovered}`.
- `level`: `info` on `recovered`, `warning` on `not_recovered`.
- This is the affected-surface (host, operator-blind) discriminating probe
  mandated by plan Phase 2.9.2 — it decides the root cause the moment it ships.

### Phase 4 — Boot-path parity (`cloud-init.yml` seed `ghcr_login`, `:471-498`) — secondary

Mirror the pull-denial tolerance in the cold-boot seed-pull block (the boot
variant of the same class, per #6090's dual-site precedent: on a seed `docker
pull` denial, re-fetch `prd` + relogin + retry once). **Effect is deferred to
host recreate** — `cloud-init.yml` is baked `user_data` with
`ignore_changes=[user_data]`, so this does NOT land on running hosts and is NOT
delivered by `apply-deploy-pipeline-fix.yml`. Included for parity so the next
fresh host boots self-healing; the acute deploy-path fix is Phases 1-3.

### Phase 5 — Config-source reconciliation (verification, not re-plumb)

The baked snapshot is only a boot cache; the durable recovery is the re-fetch.
Reconcile the source anyway so a fresh recreate bakes a pull-capable cred:

- /work verify (read-only, API): confirm `prd_terraform.GHCR_READ_TOKEN` (the
  `TF_VAR_ghcr_read_token` baked source) is the **same pull-capable PAT** as
  `prd.GHCR_READ_TOKEN`. If it diverges (e.g. an App token left from #6031
  minter experiments), file a follow-up to re-align `prd_terraform` (no code
  change; the recovery already covers the running fleet).
- In-PR doc fix: correct the stale App-minted claim in
  `2026-07-13-…-stale-baked-cred.md:71` (see Research Reconciliation).

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` — extract `refetch_ghcr_and_relogin`
  (Phase 1); pull-site auth recovery in `pull_image_with_fallback` (Phase 2);
  `pull_auth_recovery_event` + `_pull_result_is_auth_denied` predicate (Phase 3).
- `apps/web-platform/infra/ci-deploy.test.sh` — RED-first tests (see Test Scenarios).
- `apps/web-platform/infra/cloud-init.yml` — seed-pull denial tolerance (Phase 4, parity).
- `apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh` — parity test for Phase 4.
- `knowledge-base/engineering/architecture/decisions/ADR-088-control-plane-installation-token-minter-for-private-ghcr-reads.md` — amend the staleness section (see ADR/C4).
- `knowledge-base/project/learnings/2026-07-13-web-2-fsn1-fresh-boot-image-pull-auth-denied-stale-baked-cred.md` — correct line 71 (stale App-minted claim).

## Files to Create

- `scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh` — soak probe (see
  Follow-Through Enrollment). No other new file — helper + breadcrumb live inside
  `ci-deploy.sh`; no new Terraform resource, secret, vendor, or workflow.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 (RED→GREEN):** `ci-deploy.test.sh` adds a mock-`docker` case where
  `docker login` **succeeds** but the first GHCR `docker pull` returns
  `denied`, and a second `docker pull` (after a re-fetch/relogin) **succeeds**.
  Assert `pull_image_with_fallback web` returns 0 and the trace shows exactly one
  re-login + one pull retry. (Fails on `main` where §1A never fires on a
  login-ok/pull-deny cred.)
- **AC2:** a mock case where BOTH pulls deny (recovery miss) → `pull_image_with_fallback`
  returns 1, `final_write_state 1 "image_pull_failed"` path is reached (terminal
  state unchanged from today — fail-open proven).
- **AC3:** the auth-denied classifier used by the pull-site retry is the SAME
  predicate `pull_failure_event` uses (grep proves one regex, not two).
- **AC4:** zot-active mock: a zot pull failure still falls back to GHCR (existing
  behavior) and the new recovery does NOT fire on the zot leg (recovery is
  GHCR-cred-scoped).
- **AC5:** `pull_auth_recovery_event` fires with `host_id` + `outcome` tag only
  when a recovery is attempted; asserted via the Sentry-store mock-trace harness
  (deterministic, no live network).
- **AC6:** `refetch_ghcr_and_relogin` never places the token on argv or in logs
  (grep the function body: token reaches `docker login` only via
  `--password-stdin`, and is unset after) — reuses §1A's discipline.
- **AC7:** `bash -n` on `ci-deploy.sh` + the `cloud-init.yml` extracted `run:`
  snippet; `ci-deploy.test.sh` + `cloud-init-ghcr-seed-login.test.sh` pass locally
  (invoke via `bash <file>.test.sh` — the repo convention; verify at /work).
- **AC8:** ADR-088 amendment + the corrected learning line committed in the same PR.
- **AC9:** `ship-deploy-pipeline-fix-gate.test.ts` parity: `ci-deploy.sh` is in
  both `apply-deploy-pipeline-fix.yml`'s `paths:` filter and `server.tf`'s
  `deploy_pipeline_fix` `triggers_replace` set (both already true — assert
  unchanged so the fix auto-applies on merge).

### Post-merge (automated — no human step)

- **AC10 (auto):** merging fires `apply-deploy-pipeline-fix.yml` → `ci-deploy.sh`
  lands on the host (`files_written == files_total`, `files_failed == 0`) via the
  HTTPS `/hooks/infra-config` path. No SSH; verified by the workflow itself.
- **AC11 (auto):** the subsequent `web-platform-release` deploy completes
  (`reason=ok`), prod `https://app.soleur.ai/health` `.version` advances past the
  frozen build; no `pull_result=auth_denied` on the winning deploy.
- **AC12 (soak, follow-through):** zero `op:image-pull pull_result:auth_denied`
  events fleet-wide for 3 days post-deploy (enrolled follow-through, below).
  `Ref #6400` in the PR body; the follow-through sweeper closes #6400 when the
  soak holds.

## Observability

```yaml
liveness_signal:
  what: "web-platform-release deploy job reaches reason=ok AND prod /health .version advances; recovery events show outcome=recovered when the gap is exercised"
  cadence: "every deploy (per merge to main touching apps/web-platform/**)"
  alert_target: "Sentry WEB-PLATFORM-59 (image pull failed auth_denied) — existing; recovery breadcrumb narrows next occurrence"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (pull_failure_event, pull_auth_recovery_event); .github/workflows/web-platform-release.yml (deploy gate)"
error_reporting:
  destination: "Sentry (op:image-pull, op:image-pull-recovery) + Better Stack via #6396 Vector host-journald shipping"
  fail_loud: "pull_failure_event on total failure (unchanged); pull_auth_recovery_event outcome=not_recovered (level=warning) when recovery was attempted and missed"
failure_modes:
  - mode: "baked/first cred logs in but cannot pull (App token or revoked snapshot)"
    detection: "PRELUDE 'docker login … ok' followed by IMAGE_PULL_FAIL auth_denied (Vector->Better Stack); recovery breadcrumb outcome tag"
    alert_route: "Sentry WEB-PLATFORM-59; recovery outcome=recovered downgrades to info"
  - mode: "prd cred itself invalid/rotated-away (recovery re-fetch also fails)"
    detection: "pull_auth_recovery_event outcome=not_recovered + pull_failure_event auth_denied, both host_id-tagged"
    alert_route: "Sentry WEB-PLATFORM-59 (error) — escalate to prd GHCR_READ_TOKEN rotation"
  - mode: "DOPPLER_TOKEN unreadable in deploy exec context (regression)"
    detection: "PRELUDE 'doppler/DOPPLER_TOKEN unavailable' line in Vector logs"
    alert_route: "Better Stack log query (no native alert); surfaced in deploy-status reason"
logs:
  where: "host journald (ci-deploy tag) -> Vector -> Better Stack Logs source 2457081 (#6396); Sentry store API"
  retention: "Better Stack Logs default; Sentry event retention"
discoverability_test:
  command: "scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh  (Sentry API: count op:image-pull pull_result:auth_denied since deploy) ; curl -s https://app.soleur.ai/health | jq .version"
  expected_output: "auth_denied count == 0 over the soak; .version advanced past the frozen build — NO ssh"
```

### Follow-Through Enrollment (soak-gated close — plan Phase 2.9.1)

- **Script:** `scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh` — exit 0
  when Sentry reports zero `op:image-pull pull_result:auth_denied` events since a
  `start=` pinned strictly after deploy (mirror
  `reconcile-ff-only-sentry-4977.sh`).
- **Tracker directive:** `<!-- soleur:followthrough script=scripts/followthroughs/deploy-ghcr-pull-recovery-6400.sh earliest=<deploy+3d> secrets=SENTRY_* -->`
  on #6400 + the `follow-through` label.
- **Sweeper wiring:** add any new `secrets=` to
  `.github/workflows/scheduled-followthrough-sweeper.yml` (reuse existing
  `SENTRY_*` if already wired).

## Infrastructure (IaC)

No new Terraform resource, secret, vendor, cron, DNS, or host. Delivery uses the
**existing** auto-apply path:

- **Terraform changes:** none. `ci-deploy.sh` is a host-resident script hashed in
  `server.tf`'s `terraform_data.deploy_pipeline_fix` `triggers_replace`.
- **Apply path:** `apply-deploy-pipeline-fix.yml` fires on merge (paths filter
  already includes `ci-deploy.sh`) and delivers the new script over HTTPS
  `/hooks/infra-config` (no SSH, no image pull needed to land it). The workflow's
  "Redeploy to load applied profile" step no-ops for a script-only change
  (seccomp unchanged); the concurrent/next `web-platform-release` deploy exercises
  the new recovery path. `cloud-init.yml` (Phase 4) is **not** auto-applied —
  `ignore_changes=[user_data]` means it lands only on host recreate.
- **Drift / distinctness safeguards:** the running fleet is recovered by the
  re-fetch at deploy time (baked snapshot is a cache); no state file touched.
- **Vendor-tier reality check:** none — no provider resource created.

## Architecture Decision (ADR/C4)

This refines the **credential-recovery contract** established by ADR-088's
#6090/#6395 staleness amendment — it is an amendment, not a new ADR and not a
deferred issue.

### ADR

Amend `ADR-088-…` staleness section (the existing "#6090 recurrence,
2026-07-13" amendment) to add: *"Login-success is not proof of pull capability. A
credential that `docker login`s but cannot `docker pull` (a GitHub App
installation token, or any login/pull capability split) makes login-outcome-gated
recovery a false gate. Consumers MUST also re-fetch + relogin + retry on a
`docker pull` **auth-denial**, not only on a login **failure**."* Status stays
`superseded` (ADR-096/zot is the forward path); this hardens the interim GHCR path
ADR-096 keeps as break-glass through soak.

### C4 views

**No C4 impact.** Enumeration checked against all three `.c4` files: external
human actors (operator, untrusted PR author — unchanged); external systems
(`ghcr` `model.c4:254` already modeled with the authenticated `hetzner -> ghcr`
`read:packages` pull edge `:380`; `zotRegistry` `:258`; `doppler` already
modeled) — no new vendor/system; data stores (Doppler `prd` already modeled) —
none new; access relationships — the host→GHCR authenticated pull edge already
exists; this change alters only *how the host recovers the credential within that
existing edge*, not the topology. No element, tag, or `view include` line changes.

### Sequencing

The ADR amendment + code land together in this PR.

## Domain Review

**Domains relevant:** engineering (infrastructure) only.

Infrastructure/tooling reliability change to a host-resident deploy script. No
user-facing surface, no UI file in Files-to-Edit (mechanical UI-surface override
does not fire), no schema/migration/auth-flow, no pricing/legal/marketing/support
implication.

### Product/UX Gate

**Tier:** none — no UI surface (no `components/**`, `app/**/page.tsx`, or
UI-surface path in Files-to-Edit).

Cross-cutting engineering review is provided by deepen-plan's research triad
(data-integrity / security / architecture) and the standard `/review` panel at PR
time (credential-handling diff → security-sentinel + observability-coverage-reviewer
will run).

## Open Code-Review Overlap

None — no open `code-review`-labeled issue names `ci-deploy.sh`,
`cloud-init.yml`, or the ADR/learning files in scope (verify at /work with the
two-stage `gh issue list --json` + standalone `jq --arg` pattern before freezing).

## Test Scenarios

1. **login-ok / pull-deny → recovered:** mock `docker login` success + first
   GHCR pull `denied` + second pull success ⇒ deploy proceeds (AC1). *This is the
   scenario `main` fails.*
2. **login-ok / pull-deny / re-fetch-login fails:** recovery attempted, second
   pull still denies ⇒ `image_pull_failed`, fail-open, `outcome=not_recovered`
   breadcrumb (AC2/AC5).
3. **§1A path unchanged:** baked `docker login` FAILS → §1A (now via
   `refetch_ghcr_and_relogin`) recovers → login ok → pull ok. Regression parity
   with existing §1A tests.
4. **zot active, zot pull fails:** atomic GHCR fallback still works; recovery
   does not fire on the zot leg (AC4).
5. **token hygiene:** grep-assert `--password-stdin`-only + unset (AC6).
6. **boot-path parity (Phase 4):** `cloud-init-ghcr-seed-login.test.sh` login-ok
   / seed-pull-deny → retry-after-relogin.

## Alternatives Considered

| Alternative | Why not (now) |
|---|---|
| Re-bake fresh creds via full `apply-web-platform-infra` / host recreate | Requires a human-run apply; transient (bakes another snapshot that re-stales), and does not fix the structural login-ok/pull-deny gap. `ignore_changes=[user_data]` means only recreate re-bakes. Rejected as the durable fix; recovery-at-pull is substrate-independent. |
| Inject/verify `DOPPLER_TOKEN` in the deploy exec context | Premise false — the token is present and `prd`-scoped (Research Reconciliation). No-op. |
| Probe-pull inside `ghcr_prelude_and_login` to test pull capability after login | Wasteful extra pull on every deploy; recovering at the real pull site is simpler and covers zot/ghcr uniformly. |
| Wait for zot (#6122/ADR-096) to retire GHCR | Correct long-term substrate fix, but it is soak-gated and does not unfreeze prod now; GHCR stays break-glass through soak, so the interim path must be hardened regardless. |
| Enable the ADR-088 minter | Superseded/infeasible — App tokens can't pull GHCR. Minter stays disabled. |

## Sharp Edges

- The fix is **fail-open by contract**: a recovery miss MUST leave the exact
  `final_write_state 1 "image_pull_failed"` terminal state as today — never a new
  failure mode. Assert in AC2.
- **Do not** auth-recover the zot pull leg — recovery is GHCR-credential-scoped;
  zot-down is already handled by the atomic GHCR fallback.
- Retry the pull **exactly once** — no loop (a loop against a genuinely-invalid
  `prd` cred would burn the deploy window).
- Reuse `pull_failure_event`'s classifier regex via one extracted predicate — a
  second copy will drift (`cq`/paren-safety class).
- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  deepen-plan Phase 4.6 — this one is filled.
- The `cloud-init.yml` parity fix (Phase 4) lands only on host recreate — do not
  claim it recovers running hosts.
