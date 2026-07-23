---
feature: inngest-host-inplace-redelivery
issue: 6780
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
created: 2026-07-22
branch: feat-6780-inngest-inplace-redelivery
pr: 6839
spec: knowledge-base/project/specs/feat-6780-inngest-inplace-redelivery/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-07-22-inngest-host-inplace-redelivery-brainstorm.md
adr: ADR-135 (provisional — re-verify next-free ordinal at ship per the ADR-Ordinal Collision Gate)
---

# Plan: in-place signed redelivery channel for the dedicated Inngest host (#6780)

## Overview

Build a **pull-based signed config-refresh channel** so a change to a host-executed
`apps/web-platform/infra/*.sh` script reaches the dedicated Inngest host
(`soleur-inngest-prd`, 10.0.1.40, deny-all-public) **without** an
`apply_target=inngest-host-replace` of the sole production scheduler. A systemd timer on
the host resolves a **promoted digest pointer** (`INNGEST_CONFIG_DIGEST` in Doppler
`soleur-inngest/prd`), pulls a **keyless-cosign-signed OCI bundle** (DEEPEN-CORRECTION-1) of the refresh-set,
verifies (signature + per-file sha256 manifest + monotonic version gate), applies
**atomically/fail-closed** through the existing `infra-config-install.sh` STDIN root helper,
and reports **off-box** to Better Stack via the baked `inngest-boot-phone-home.sh`, paired
with an absence-heartbeat monitor. The host-side machinery is baked into
`cloud-init-inngest.yml` and therefore **rides the #6178 cutover provision** (bootstrap
paradox: the channel installs only through the replace it eliminates); the CI
build/sign/promote workflow and future bundle edits then flow through the channel itself.

Design is settled from the brainstorm (11 decisions). This plan is the HOW. **Signing is air-gapped
keyless cosign** (chosen — see DEEPEN-CORRECTION-1 below + ADR-135 Option A; the earlier "keyless
ruled out (ADR-052)" framing was imprecise — ADR-052 blocks *host* egress, and keyless *verify* is
offline against the baked trusted root). Static-key is the **documented fallback** (Option B), not
the primary. Extends ADR-087 (air-gapped verify) + ADR-128 (digest-pinned coherence) + ADR-096
(zot-first/GHCR-fallback).

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Reality (verified vs `feat-6780…` worktree) | Plan response |
|---|---|---|
| Reuse `infra-config-install.sh` verbatim | Exists; STDIN payload (#4827), **15 hardcoded** dests in `DEST_SPEC`, `rc=3`, mode/owner from the table not caller (`:59-88`) | Reuse the helper, but the refresh-set scripts must be **added to `DEST_SPEC`** (+ its `FILE_MAP` lockstep). Phase 4 task. |
| Off-box marker via `inngest-boot-phone-home.sh` | NOT a standalone infra file — baked in `cloud-init-inngest.yml` `write_files:114`, used across boot stages | Emit a new marker verb through the SAME baked script; no new emitter. |
| Add `INNGEST_CONFIG_DIGEST` to isolation self-check (5→6) | Confirmed at `cloud-init-inngest.yml:315-333`: regex `^(INNGEST_(SIGNING_KEY\|EVENT_KEY\|REDIS_PASSWORD\|POSTGRES_URI\|HEARTBEAT_URL)\|BETTERSTACK_LOGS_TOKEN)$`, floor `-lt 5`, **AND `n_total -ne n_inngest` (exact-set)**. The `-lt 5` is a *lower bound*: dark=5, live=6 (`INNGEST_HEARTBEAT_URL` arrives only at cutover). | The **exact-set** `n_total -ne n_inngest` is the real gate. Extend the regex alternation to include the pointer; the floor is dark/live-timing-dependent — **do NOT flatly bump to `-lt 6`** (bricks dark boot if the pointer is cutover-only). See **DEC-FLOOR** below: decide whether `INNGEST_CONFIG_DIGEST` is dark-present (TF-provisioned pre-cutover, floor→6) or cutover-only (floor stays 5, exact-set count rises). |
| Publish to zot too, GHCR fallback (operator) | Web-host zot-first pull (`cloud-init.yml:507-520`, ADR-096) authenticates with `ZOT_*` from Doppler **soleur/prd**. The dedicated host's Doppler is the **isolated soleur-inngest/prd**, whose self-check **FATALs on any foreign secret**. | **Publish-to-both is unconditional (CI side).** Host **zot-first pull** requires `ZOT_*` admitted into `soleur-inngest/prd` → isolation floor grows further (6→~9). See **Decision D-ZOT** below — recommend GHCR-direct host pull in v1, zot-first host pull as a flagged fast-follow. |
| cosign verify on the dedicated host | The dedicated host **digest-pins only**; it does not cosign-verify its bootstrap image today (`cloud-init-inngest.yml:390` is `@sha256` pinned). `cosign verify` exists on the app-deploy path (`ci-deploy.sh`, ADR-087). | cosign-verify-blob is **net-new capability on this host** — bake the cosign binary + baked trusted public key. Tooling/pattern exists (ADR-087, `cosign-trusted-root.json`). |
| Four pin sites untouched | Confirmed: `cloud-init.yml:699/705` (web IREF/ZIREF), `cloud-init-inngest.yml:390` (dedicated IREF@sha256), `inngest-bootstrap.sh:492` (comment). Coupled by the `vinngest-v*` semver-max guard. | Config bundle is a **distinct artifact** from the bootstrap image → the four pins are out of scope (Non-Goal). |

## User-Brand Impact

**If this lands broken, the user experiences:** the sole Inngest scheduler runs stale or no host
scripts — the host that fires every statutory-deadline / notification cron — so a user's
deadline reminder or notification silently never fires, OR a dead refresh timer masks an
undelivered fix.
**If this leaks / is subverted, the user's workflow is exposed via:** an unsigned/forged/rolled-back
bundle executing arbitrary code on the sole scheduler (RCE) — full compromise of the host that
touches user-facing cron delivery.
**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true`. CPO sign-off is required at plan time (tiered model: framing done at
brainstorm, locked here). The brainstorm spawned CTO + platform-strategist + infra-security (not
CPO/CLO) because this is pure internal infra with no product/legal surface — **CPO sign-off to be
confirmed at the plan-review confirmation gate**; `user-impact-reviewer` runs at PR review.

## Decision D-ZOT (User-Challenge — surface at confirmation gate)

The operator chose "publish to Zot as well, GHCR fallback." Publishing to both registries in CI is
free and unconditional. The **host-side zot-first pull**, however, requires `ZOT_REGISTRY_URL/USER/TOKEN`
in the **isolated** `soleur-inngest/prd`, which grows the boot isolation self-check floor from 6 to ~9
and widens the isolated-credential surface on the sole scheduler.

- **Recommended (v1):** CI publishes the signed bundle to **both zot + GHCR**; the **host pulls GHCR-direct
  by digest** (matching how it already pulls its bootstrap image — no new isolated-Doppler secrets, no
  further isolation-floor growth). File **host zot-first pull** as a flagged fast-follow (its own task)
  once `ZOT_*` admission into the isolated project is designed.
- **Alternative (operator literal):** host pulls **zot-first → GHCR fallback** in v1 → include the
  `ZOT_*` admission + isolation-floor bump (6→~9) as Phase 3 work.

This diverges from a literal reading of the operator's answer, so it is surfaced, not silently applied
(ADR-084). Confirm at the apply gate.

## Plan-Review Hardening (P0/P1 — binding; from architecture + spec-flow + security-sentinel)

These are load-bearing constraints the implementation MUST satisfy; each maps to a new AC/test.

- **HARD-1 (TCB boundary — P0).** The channel **engine** — the verify+apply script (`inngest-config-refresh.sh`), the cosign binary, the baked public verify key, the `.timer`/`.service` units, and the `applied.version` file — MUST NOT be members of the refresh-set or `DEST_SPEC`/`FILE_MAP`. They change **only** via host replace. Otherwise one validly-signed bundle replaces the verifier with an accept-all shim (signed-once → bypass-forever). Test-assert these paths are absent from `DEST_SPEC`.
- **HARD-2 (version is a SIGNED field — P0).** The monotonic version integer MUST live **inside the cosign-signed bytes** (e.g., a `VERSION` line in the signed manifest) and be read **only after** `cosign verify-blob` succeeds — never from an OCI tag/annotation or the Doppler pointer. Otherwise a registry/pointer writer replays an old-but-validly-signed (since-patched) bundle under a forged-high version. Test: old-signed bundle re-published at a higher pointer version is still rejected.
- **HARD-3 (`applied.version` seed + ownership — P1).** cloud-init MUST seed `applied.version` to the baked floor's version at bake time (shared numbering space with the bundle), and create `/var/lib/inngest-config` + the version file **`root:root`** (NOT under the deploy-writable `/var/lib/inngest` which is `deploy:deploy`). Absent seeding → downgrade below the running floor; deploy-writable → a deploy-user (the identity inngest runs as) resets the floor and forces a downgrade. Test ownership/mode + fresh-host first-pull.
- **HARD-4 (run as root — P1).** The verify+apply `.service` runs `User=root` (baked, root-owned); it invokes `infra-config-install` directly (no deploy→sudoers grant). Keep the deploy sudoers grant to the existing webhook path only. The verifier must not execute in a deploy-writable `$PATH`/tempdir.
- **HARD-5 (set-atomic apply — P1).** `infra-config-install.sh` is **per-file** atomic, not set-atomic. Stage+verify ALL files, then swap all; advance `applied.version` **only after the last file lands**; on mid-set failure, re-apply next tick (do not latch a torn mixed-version set). Add a generation marker crons can read to refuse a mixed set.
- **HARD-6 (promotion credential — P1).** Promotion writes `INNGEST_CONFIG_DIGEST` via **`terraform apply` of the `doppler_secret`** (no standing CI write-token into the isolated `soleur-inngest/prd`), OR the write-token surface is explicitly justified in ADR-135. The signing principal and the promotion principal SHOULD be distinct (no single job both signs and promotes).
- **HARD-7 (CI = total-compromise root — P1).** ADR-135 names CI-workflow compromise as the top residual RCE path (whoever compromises the release workflow can sign + promote a fresh bundle; the monotonic gate does nothing against a *fresh* forgery). **As-shipped (keyless):** gate the signing **job** behind a GitHub **environment with a non-empty required-reviewer set** (`inngest-config-signing`, `inngest-config-signing.tf`, wired into the `apply-web-platform-infra.yml` `-target=` allow-list so the reviewer rule actually exists before any dispatch — an unapplied environment is auto-created WITHOUT reviewers on first use), OIDC-scoped (`id-token: write` on that job only). Keyless dissolves the "cosign private key custody" line entirely (there is no key to name/store). **Fallback (Option B, static key):** name the cosign key distinctly (`COSIGN_CONFIG_SIGNING_KEY`), in the CI/`soleur/prd` project only — NEVER the isolated project.
- **HARD-8 (drift comparator is a deliverable — P1).** The absence-heartbeat only catches a *dead* timer, and the baked floor's own boot marker can *satisfy* it while the delta never pulled. Ship a concrete off-box comparator (a CI/cron job reads the Doppler pointer + queries Better Stack for the latest `APPLIED` marker, alarms on `applied_digest ≠ pointer` beyond N windows). The boot-floor marker MUST be distinguishable (`version=floor`) so it does not mask a stuck delta.
- **HARD-9 (pointer-below-floor inversion — P1).** If a cutover bakes a floor whose version exceeds the last-promoted pointer, the first pull is rejected forever → silent stale. Gate promotion to require `pointer.version > baked-floor.version`, AND emit an explicit alarm when a pull is rejected as ≤ current (rejection-as-signal, not silent no-op).
- **HARD-10 (fail-closed arms — P1).** The verify+apply script MUST NOT inherit the bootstrap's ambient `set +e` / `|| true`. Each gate is explicit fail-closed: `cosign verify-blob` rc≠0, `sha256sum -c` rc≠0, a **missing/non-integer** `applied.version` (fail-closed to a hard floor, never parse-to-0-accept-all), `infra-config-install` `rc=3`. Logging/phone-home may `|| true`; a *decision* behind `|| true` may not.
- **HARD-11 (runbook channel-live precondition — P1).** The runbook is INVALID pre-cutover (promoting a pointer no host reads = believing a fix shipped when it silently didn't). Gate it on a "channel-live" assertion (a fresh `SOLEUR_INFRA_PULL_APPLIED` marker exists post-cutover) and add the #6178-scheduled linkage or a loud "channel not yet live" state.
- **HARD-12 (Phase-0 evidence — P2→gates P1s).** Verify the baked GHCR creds can pull the **config-bundle OCI repo** specifically (not just the bootstrap-image repo) — a repo-scope mismatch 401s every pull → permanent fail-closed. `infra-config-install.sh` is NOT currently baked in `cloud-init-inngest.yml`; it must be newly baked, root-invoked-only, WITHOUT importing the web-host webhook/sudoers apparatus. Note the shared-`DEST_SPEC` cross-host widening (every refresh-set dest becomes grantable on web hosts too).

## Deepen-Plan Enhancements (2026-07-22)

Precedent-diff (Phase 4.4) + halt gates run against the real infra. Corrections below; each
either changes a prior decision (surface at confirmation) or hardens a phase.

### Precedent-diff (verified against `feat-6780…` worktree)
| Plan element | Established precedent | Adopt |
|---|---|---|
| cosign verify on host | `ci-deploy.sh:43-99` (ADR-087): **air-gapped KEYLESS** — `COSIGN_TRUSTED_ROOT_HOST=/etc/soleur/cosign-trusted-root.json` (baked) + `COSIGN_IDENTITY_REGEXP` (pins the CI workflow) + `COSIGN_OIDC_ISSUER`, pinned `COSIGN_IMAGE@sha256` v3.1.1, no live Fulcio/Rekor at verify | See **DEEPEN-CORRECTION-1**: reuse this pattern via `cosign verify-blob` — dissolves the static-key custody problem (OQ4). |
| zot-first/GHCR-fallback | `cloud-init.yml:505-525` (ADR-096): `ZOT_REGISTRY_URL/ZOT_PULL_USER/ZOT_PULL_TOKEN` from Doppler `soleur/prd` → `docker login` → resolve effective REF (`/v2/` reachable ? zot : GHCR), "Dark-safe: unset/unreachable zot ⇒ GHCR" | **D-ZOT confirmed**: zot-first on the isolated host needs those **3** secrets in `soleur-inngest/prd` → isolation floor 6→**9**. GHCR-direct v1 stands. |
| `doppler_secret` pointer | `inngest-betterstack-token.tf` | mirror (copy into `prd_terraform` → verify read-only → apply). |
| systemd timer/service | `.timer` units exist in `cloud-init-registry.yml`, `cloud-init.yml` | NOT novel — mirror an existing unit shape. |
| scheduled drift comparator | 51 Inngest `cron-*.ts` functions (ADR-033) | See **DEEPEN-CORRECTION-2**: the HARD-8 comparator is an Inngest `cron-*.ts`, not a GH Actions cron (it reads app secrets + Better Stack). The CI **build/sign/publish** workflow stays GH Actions (git/CI-scoped artifact production). |

### DEEPEN-CORRECTION-1 (signing — supersedes D4/OQ4; surface at confirmation)
Adopt **air-gapped keyless cosign** (the `ci-deploy.sh`/ADR-087 host precedent) rather than a bespoke
static key: **CI signs the bundle keyless** (`cosign sign-blob`, Fulcio/Rekor at sign-time — CI has egress);
**the host verifies offline** (`cosign verify-blob --certificate-identity-regexp <config-workflow> --certificate-oidc-issuer … --trusted-root /etc/soleur/cosign-trusted-root.json`) against the **already-baked trusted root** — no host egress to Fulcio/Rekor, no private key to custody. This **dissolves OQ4** (rotation = edit the identity regexp; no key overlap dance) and removes HARD-7's "cosign private key" custody line (the residual root shrinks to "who can run the signing workflow"). The prior "ADR-052 blocks keyless" framing was imprecise — ADR-052 blocks *host* egress; air-gapped keyless *verify* needs none. **Phase-0 probe (HARD-12 addendum):** confirm `cosign verify-blob` keyless-offline succeeds against the baked trusted root on the pinned cosign image before committing to this path; **static-key remains the documented fallback** if the offline blob-verify proves impractical. HARD-2 (version is a *signed field*) is unchanged and applies to either signer.

### DEEPEN-CORRECTION-2 (drift comparator substrate)
The HARD-8 off-box drift comparator is a new scheduled job that reads Doppler + Better Stack → **Inngest
`cron-inngest-config-drift.ts`** (ADR-033), NOT a `.github/workflows/scheduled-*.yml`. Wire it beside the
existing 51 cron functions; it alarms when `applied_digest ≠ promoted pointer` beyond N windows.

## Downtime & Cutover

**The channel IS the zero-downtime mechanism** — its entire purpose is to deliver host-script changes
*in-place* (systemd timer, atomic swap) so future changes never replace the sole scheduler. Ongoing
refreshes incur **zero downtime**.

The **one-time install** of the channel (timer + verify script + baked cosign material + isolation
self-check edit) is baked into `cloud-init-inngest.yml` and therefore **rides the #6178 cutover's
already-planned `inngest-host-replace`** — it adds **no downtime beyond what the #6178 cutover already
incurs** (that replace is #6178's cost, gated by its own maintenance window and Redis-AOF-volume
re-attach). This feature introduces **no new independent replace**. Non-host Terraform (the
`doppler_secret`, the Better Stack monitor, the Inngest drift-comparator function) applies via the
normal path with no downtime. Residual-downtime justification: none added by this feature; the install
piggybacks the #6178 window. Rollback: the baked floor is the last-known-good; a failed first pull
retains it (HARD-3/HARD-5).

## Implementation Phases (contract-first ordering)

**Phase 0 — Preconditions & enumeration (verify, no code).**
- Enumerate the exact host-executed `*.sh` refresh-set on 10.0.1.40 (OQ2): the scripts that run ON the
  dedicated host vs web-host-only. Source of truth = `cloud-init-inngest.yml` `write_files`/`runcmd` +
  `inngest-bootstrap.sh` references.
- Confirm host egress reachability for the chosen substrate: the boot self-check already runs
  `doppler run --project soleur-inngest --config prd` at boot, so `api.doppler.com` + GHCR (baked creds)
  are proven; record the evidence in the plan.
- Audit the `DEST_SPEC`/`FILE_MAP` gap in `infra-config-install.sh` for the refresh-set dests.

**Phase 1 — ADR-135 + C4 (architectural decision is a deliverable).**
- Author `ADR-135-pull-based-signed-config-refresh-for-dedicated-inngest-host.md` via `/soleur:architecture`:
  the new trust boundary + pull control channel; carves the `*.sh`-only exception to the image-replace-only
  rule; extends ADR-087 (verify), ADR-128 (digest coherence), ADR-096 (zot). Status: `adopting` (true after
  the cutover provision lands). Re-verify the next-free ordinal at ship (Collision Gate).
- C4: read all three `.c4` files; add the CI **signer** (external system, `#external`), the
  **zot/GHCR registry** edge to the inngest host if not modeled, and the config-refresh relationship
  (CI → registry → host). Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

**Phase 2 — CI build + keyless-cosign sign + publish (producer contract). [As-shipped: keyless per DEEPEN-CORRECTION-1 — the static-keypair provisioning below is the Option-B fallback, NOT what shipped.]**
- ~~Provision a cosign static keypair~~ **(fallback only).** As-shipped there is **no keypair to mint**:
  keyless sign uses the CI OIDC id-token; verify uses the already-committed `cosign-trusted-root.json`
  + a config-workflow identity regexp (rotation = edit the regexp / re-capture the trusted root per
  ADR-087, no overlap dance). The static-key path (private key → Doppler `prd`, public key committed +
  baked, accept-both-during-overlap) is retained only as the documented fallback if the host-side
  offline `verify-blob` proves impractical at the cutover Phase-0 probe.
- New workflow (`.github/workflows/build-inngest-config-bundle.yml`): package refresh-set + per-file sha256 **manifest** + a
  **monotonic version** into a bundle; `cosign sign-blob` **keyless**; publish the OCI artifact to
  **both zot and GHCR**. (`workflow_dispatch` for a new workflow cannot be verified from a feature branch —
  wire the build as a job in an existing `pull_request` workflow OR test the packaging logic as a
  locally-runnable script; do NOT plan a temporary `workflow_dispatch` test workflow.)

**Phase 3 — Promoted digest pointer + isolation self-check (contract).**
- Add `INNGEST_CONFIG_DIGEST` to `soleur-inngest/prd` via the `inngest-betterstack-token.tf` `doppler_secret`
  pattern (copy into `soleur/prd_terraform` for `TF_VAR` → verify read-only → apply). Digest published
  **only on promotion** (D7): a CI gate / short soak after landing on main advances the pointer; never
  raw main-latest.
- Extend the boot isolation self-check (`cloud-init-inngest.yml:317-325`): add `INNGEST_CONFIG_DIGEST` to
  the regex alternation and bump the floor `-lt 5` → `-lt 6`. **(If D-ZOT alternative chosen: also admit
  `ZOT_REGISTRY_URL/USER/TOKEN` → regex + floor → ~9.)**

**Phase 4 — Host verify+apply script + systemd timer/service + cosign pubkey (consumer; RIDES #6178 cutover).**
- Bake into `cloud-init-inngest.yml`: (a) the cosign binary + baked public verify key; (b) the verify+apply
  script (resolve digest from Doppler → pull `@sha256` GHCR-direct [v1] → `cosign verify-blob --key <pub>` →
  verify per-file sha256 vs manifest → **monotonic version gate** [reject ≤ last-applied, persisted at
  `/var/lib/inngest-config/applied.version`] → atomic stage+swap via `infra-config-install.sh`); (c) a
  systemd `.service` + `.timer` (cadence per OQ3). Add refresh-set dests to `DEST_SPEC`/`FILE_MAP`.
- Fail-closed: any verify/version/fetch failure keeps last-known-good, touches no live script, emits the
  off-box fail marker.

**Phase 5 — Off-box observability.**
- Marker verbs through `inngest-boot-phone-home.sh`: `SOLEUR_INFRA_PULL_APPLIED version=… sha256=… verify=ok`
  every run; `SOLEUR_INFRA_PULL_VERIFY_FAIL …` on failure.
- Terraform: a Better Stack **absence-heartbeat** monitor (alerts on missing refresh — the #6536 lesson) +
  an `OnFailure=` Sentry-Crons/Resend alarm (mirror `cron-egress-alarm.sh`). Off-box **audit**: host state
  file `{applied_version, bundle_sha256, signer_keyid, per_file_sha256[], applied_ts, verify_result}` read
  via a `cat-infra-config-state.sh`-style reader; applied digest cross-checkable against the CI-logged
  signed-artifact digest.

**Phase 6 — Tests + runbook.**
- `.test.sh` (mirror `inngest-host.test.sh` convention): verify the isolation-check regex+floor change; the
  monotonic gate rejects a lower version; fail-closed keeps last-known-good; the cosign-verify arm rejects an
  unsigned/wrong-key bundle; the `DEST_SPEC` additions. Deterministic invocation (no LLM, no live prod writes).
- Runbook: how to ship a host-script change (edit `*.sh` → CI signs+publishes → promote the pointer →
  timer applies → verify off-box via `betterstack-query.sh`), the batching/promotion cadence, and the
  rotation recipe.

## Files to Create
- `.github/workflows/<inngest-config-bundle>.yml` (or a job in an existing workflow) — build+sign+publish.
- `apps/web-platform/infra/inngest-config-refresh.sh` — host verify+apply script (baked via cloud-init).
- `apps/web-platform/infra/inngest-config-pubkey.pem` (or embedded in cloud-init) — cosign public verify key.
- `apps/web-platform/infra/inngest-config-digest.tf` — `doppler_secret` for `INNGEST_CONFIG_DIGEST` (mirror `inngest-betterstack-token.tf`).
- `apps/web-platform/infra/inngest-config-refresh.test.sh` — host-side tests.
- `knowledge-base/engineering/architecture/decisions/ADR-135-*.md`.
- Runbook under `knowledge-base/engineering/operations/runbooks/`.

## Files to Edit
- `apps/web-platform/infra/cloud-init-inngest.yml` — timer/service/pubkey/verify-apply bake; isolation self-check regex+floor.
- `apps/web-platform/infra/infra-config-install.sh` — `DEST_SPEC` + `FILE_MAP` refresh-set dests.
- `apps/web-platform/infra/inngest-host.tf` — Better Stack absence-heartbeat monitor; any nft/egress note (no new inbound).
- `.c4` model/views/spec — signer + registry→host edges.
- `README`/counts as applicable (none expected — no plugin component).

## Infrastructure (IaC)

### Terraform changes
- `inngest-config-digest.tf` (`doppler_secret` for `INNGEST_CONFIG_DIGEST`, `soleur-inngest/prd`); Better
  Stack absence-heartbeat monitor in `inngest-host.tf` (gate on `var.betterstack_paid_tier` if the monitor
  type requires it — vendor-tier reality check). Sensitive vars: cosign private key (CI/Doppler `prd`, never
  on host); `INNGEST_CONFIG_DIGEST` value (Doppler-managed).
### Apply path
- **cloud-init + `inngest-host-replace`** for the host-side bake (it rides the #6178 cutover provision — the
  ONLY time the host is (re)born). Non-host Terraform (the `doppler_secret`, the monitor) applies via the
  normal `apply-web-platform-infra.yml` path. No standalone host replace is spent solely to add the channel.
### Distinctness / drift safeguards
- Deny-all-public preserved (no new inbound; the timer is outbound-only). The digest pointer is the only
  mutable control input; cosign signature + monotonic version + per-file sha256 bound its authority.
### Vendor-tier reality check
- Confirm the Better Stack absence-heartbeat/monitor type is available on the current tier before `apply`
  (mirror the `betteruptime_policy` free-tier gate pattern).

## Observability

```yaml
liveness_signal:
  what: SOLEUR_INFRA_PULL_APPLIED marker (version + applied sha256) every timer run
  cadence: every timer tick (OQ3)
  alert_target: Better Stack absence-heartbeat monitor (alarms on MISSING refresh)
  configured_in: cloud-init-inngest.yml (emit) + inngest-host.tf (monitor)
error_reporting:
  destination: Better Stack (SOLEUR_INFRA_PULL_VERIFY_FAIL) + Sentry-Crons/Resend OnFailure
  fail_loud: true (fail-closed keeps last-known-good AND emits off-box alarm)
failure_modes:
  - {mode: bad/missing signature, detection: cosign verify-blob non-zero → VERIFY_FAIL marker, alert_route: Better Stack + OnFailure}
  - {mode: version rollback/replay, detection: monotonic gate reject → VERIFY_FAIL marker, alert_route: Better Stack}
  - {mode: manifest sha mismatch, detection: per-file sha256 compare fail → VERIFY_FAIL marker, alert_route: Better Stack}
  - {mode: dead timer (silent), detection: Better Stack absence-heartbeat (no APPLIED marker in window), alert_route: Better Stack}
  - {mode: stale re-baked floor (#6594), detection: applied-digest marker vs promoted pointer drift, alert_route: Better Stack}
logs:
  where: journald → vector → Better Stack; host state file /var/lib/inngest-config/
  retention: Better Stack default
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --grep SOLEUR_INFRA_PULL_APPLIED
  expected_output: a marker line with version= and sha256= within the last timer window (no host login required)
```

## Architecture Decision (ADR/C4)
### ADR
- **Create ADR-135** (provisional) — pull-based signed config-refresh for the dedicated Inngest host.
  Extends ADR-087 / ADR-128 / ADR-096; carves the `*.sh`-only in-place exception to image-replace-only.
### C4 views
- Container/Component: add the CI **signer** (`#external`), the **config artifact** flow through
  zot/GHCR to the inngest host, and the **refresh** relationship. Edit `.c4` directly; run the C4 tests.
### Sequencing
- ADR authored now with `status: adopting`; true once the cutover provision bakes the channel.

## Acceptance Criteria

> **Scope split (PR #6839).** This PR ships the **un-gated foundations** — ADR-135 + C4, the CI
> keyless-sign/dual-publish producer (workflow + tested packager), the `INNGEST_CONFIG_DIGEST`
> `doppler_secret` (authored; applied at the cutover), and the dormant drift comparator (Inngest
> dispatcher + GHA executor + tested core). The **host-side consumer** — the verify+apply script,
> the systemd timer/service, the baked cosign material, the isolation self-check regex+floor edit,
> and the `DEST_SPEC`/`FILE_MAP` additions — is baked into `cloud-init-inngest.yml` and **rides the
> #6178 cutover** (PR #6348). So AC1/AC2/AC3/AC10/AC12–AC18 (host verify+apply arms, DEST_SPEC) land
> with that cutover, not here. **Signing reconciliation (DEEPEN-CORRECTION-1):** AC5/AC17 are
> satisfied via **keyless** cosign (no static key minted; the committed `cosign-trusted-root.json` +
> a config-workflow identity regexp are the verify anchor), which also means no operator secret-mint
> step. **DEC-FLOOR / D-ZOT:** dark-present pointer + GHCR-direct host pull (v1) — both host-side, so
> their AC1/floor + zot-pull assertions ride the cutover.

### Pre-merge (PR)
- [ ] AC1: `cloud-init-inngest.yml` isolation self-check includes `INNGEST_CONFIG_DIGEST` in the regex AND floor `-lt 6` (grep-assert both).
- [ ] AC2: The host verify+apply script (a) `cosign verify-blob --key`s before apply, (b) rejects version ≤ last-applied, (c) verifies per-file sha256 vs manifest, (d) applies only via `infra-config-install.sh` (no arbitrary dest). `.test.sh` asserts each arm.
- [ ] AC3: A bundle failing verify/version/manifest leaves live scripts untouched AND emits `SOLEUR_INFRA_PULL_VERIFY_FAIL` (test asserts fail-closed).
- [ ] AC4: No new inbound rule added to the inngest host nftables (grep the nft set; deny-all-public preserved).
- [ ] AC5 (keyless — DEEPEN-CORRECTION-1 supersedes "static key"; workflow present, runtime-unverifiable on a feature branch): The CI workflow **keyless**-signs the bundle manifest (`cosign sign-blob`, OIDC id-token) and publishes to **both** zot (best-effort) and GHCR (authoritative); the verify anchor is the already-committed `cosign-trusted-root.json` + a config-workflow identity regexp (no static keypair minted, no separate pubkey committed). The deterministic packaging core (HARD-2) is tested; the sign+publish steps mirror `reusable-release.yml` and run first at the #6178 cutover.
- [ ] AC6: `INNGEST_CONFIG_DIGEST` `doppler_secret` + monitor `terraform plan` shows only the intended adds (no create of `hcloud_server`/host, no destroy).
- [x] AC7: ADR-135 exists with the four required headings; C4 tests green; `.c4` renders the new signer/registry/host edges.
- [ ] AC8: `PR body uses Ref #6780` (NOT Closes — the channel is only proven after it rides the #6178 cutover provision; close #6780 post-cutover with off-box marker evidence).
- [ ] AC10 (HARD-1): a test asserts the engine paths (`inngest-config-refresh.sh`, cosign binary, pubkey, `.timer`/`.service`, `applied.version`) are NOT in `DEST_SPEC`/`FILE_MAP`.
- [ ] AC11 (HARD-2): a test asserts an old-signed bundle re-published under a higher pointer/annotation version is REJECTED (version read only from the verified signed bytes).
- [ ] AC12 (positive apply-path, spec-flow #1): a test asserts that after a valid higher-version bundle, on-disk file content changed AND `applied.version` advanced — not merely that a marker was emitted.
- [ ] AC13 (HARD-3): a test asserts `/var/lib/inngest-config` + `applied.version` are `root:root`, and fresh-host first-pull applies the delta above the seeded floor.
- [ ] AC14 (HARD-5): a test asserts a mid-set apply failure leaves NO torn mixed-version set (stage-all-then-swap-all; `applied.version` advances only after the last file).
- [ ] AC15 (HARD-10, replaces flat AC3): per-arm fail-closed tests — unsigned, wrong-key, sha-mismatch, lower-version, corrupt/empty `applied.version`, empty/truncated bundle — each keeps last-known-good AND emits `SOLEUR_INFRA_PULL_VERIFY_FAIL`.
- [ ] AC16 (HARD-4): the verify+apply `.service` runs `User=root`, no deploy→sudoers grant for this unit.
- [ ] AC17 (keyless — supersedes the "static key round-trip"): keyless has no key-A-sign/key-B-bake mismatch class (there is no minted keypair; trust is the committed `cosign-trusted-root.json` + identity regexp, staleness-gated by `cosign-trusted-root-staleness.test.sh`). The hermetic round-trip that remains is the deterministic packager (`inngest-config-bundle-pack.test.sh`, HARD-2 VERSION-in-signed-bytes); the keyless sign/verify-blob round-trip is exercised at the #6178 cutover Phase-0 probe (offline verify against the baked root).
- [ ] AC18 (spec-flow #13): a test asserts every refresh-set dest resolves in BOTH `DEST_SPEC` and `FILE_MAP` with matching mode/owner (lockstep).
- [x] AC19 (HARD-8): the off-box drift comparator exists (reads pointer + latest `APPLIED` marker, alarms on divergence); the boot-floor marker is distinguishable (`version=floor`).

### Post-merge (operator / follow-through)
- [ ] AC9 ⏳: after the #6178 cutover provision bakes the channel, a host-script edit → CI sign+publish → pointer promote → timer applies, verified by `SOLEUR_INFRA_PULL_APPLIED` reaching Better Stack (off-box). Enroll as a **follow-through** (soak) with a verification script under `scripts/followthroughs/` — `/ship` Phase 5.5 gate.

## Domain Review

**Domains relevant:** Engineering (carry-forward from brainstorm).

### Engineering
**Status:** reviewed (carry-forward). **Assessment:** CTO — minimal delta over machinery the host already
runs; config bundle distinct from the four image pins; hazards = RCE (→cosign + dest allowlist) and
#6594/#6536 latched-false-green (→monotonic gate + off-box applied-digest + absence-heartbeat); rides the
cutover provision. platform-strategist — GHCR-direct is the host's proven pull path (no zot branch today);
Doppler-digest aligns ADR-128; isolation self-check +1 (or +ZOT). infra-security — asymmetric static-key
(not shared HMAC), cosign keyless out (ADR-052), verify-before-activate + atomic swap + dest allowlist +
monotonic version; fail-closed keeps last-known-good + off-box alarm, never SSH.

### Product/UX Gate
Not applicable — no UI-surface file in Files to Create/Edit (pure infra/CI). Tier: NONE.

## Open Questions (for deepen-plan / confirmation)
1. **D-ZOT** (above) — host zot-first pull (isolation floor 6→~9) vs GHCR-direct v1 + zot fast-follow. **Recommend v1 GHCR-direct.**
2. **DEC-FLOOR** (from plan-review) — is `INNGEST_CONFIG_DIGEST` **dark-present** (TF-provisioned pre-cutover → floor moves to 6) or **cutover-only** like `HEARTBEAT_URL` (floor stays 5, exact-set count rises at cutover)? Decides the AC1 assertion. Recommend **dark-present** so the timer is armed from first boot; requires the `doppler_secret` applied + verified as a precondition of the #6178 cutover provision (HARD gate — a partial edit bricks dark boot).
3. **OQ3** — timer cadence + promotion mechanism (CI gate vs fixed soak window). Blocks the absence-heartbeat grace window (must match cadence).
4. **OQ4** — cosign static-key custody + rotation recipe specifics (ADR-087 re-capture shape); leak → emergency `inngest-host-replace` with new baked pubkey (static keys have no revocation — residual, state in runbook).
5. **CPO sign-off** — confirm at the plan-review gate (pure-infra; low product surface).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/TBD fails deepen-plan Phase 4.6 — filled above.
- The boot isolation self-check is **exact-set** (`n_total -ne n_inngest`): every secret added to the isolated
  project MUST be in the regex or the host **fail-closes on boot**. Adding the digest pointer AND (if chosen)
  zot creds means the regex+floor must move together — a partial edit bricks the host at next replace.
- The four image pin sites are the **bootstrap image**, NOT the config bundle — do not touch them here.
- Use `Ref #6780` not `Closes` — closure is post-cutover-verification (see AC8/AC9).
