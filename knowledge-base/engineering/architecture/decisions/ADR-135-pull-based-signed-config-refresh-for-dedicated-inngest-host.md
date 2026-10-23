---
title: Pull-based signed config-refresh channel for the dedicated Inngest host
status: adopting
date: 2026-07-22
---

# ADR-135: Pull-based signed config-refresh channel for the dedicated Inngest host

> Status `adopting`: the CI producer, the promoted digest pointer, and the off-box
> drift comparator land in this PR (#6839, `Ref #6780`). The host-side consumer —
> the verify+apply script, the systemd timer/service, the baked cosign material, and
> the isolation self-check edit — is baked into `cloud-init-inngest.yml` and therefore
> rides the #6178 cutover provision (PR #6348). This ADR is `active` once that bake
> lands and the first `SOLEUR_INFRA_PULL_APPLIED` marker reaches Better Stack off-box.

## Context

The dedicated Inngest host (`soleur-inngest-prd`, 10.0.1.40, deny-all-public, ADR-100
/ #6178) is the **sole** production scheduler — every statutory-deadline and
notification cron fires from it. It is an immutable-redeploy host: today a change to a
host-executed `apps/web-platform/infra/*.sh` script reaches it only through an
`inngest-host-replace` of the one production scheduler, gated by a maintenance window
and a Redis-AOF-volume re-attach (#5450). `hr-prod-host-config-change-immutable-redeploy`
makes that the default, and for the *image* it is correct. But the host also runs a set
of `*.sh` operational scripts whose content is orthogonal to the pinned bootstrap image;
replacing the sole scheduler to ship a one-line script fix is disproportionate and, worse,
couples every such fix to the blast radius of a full host rebirth.

We want host-script changes to reach the box **in-place** — no replace, zero downtime —
while preserving the security properties that justify the immutable-redeploy default: no
new inbound surface, no arbitrary-code path, no silent staleness, and no SSH state
mutation (AP-002). The threat that makes this hard is explicit in the plan's
`## User-Brand Impact`: an unsigned / forged / rolled-back bundle executing on the sole
scheduler is a full-compromise RCE, and a silently dead refresh timer masks an
undelivered fix (the #6594 / #6536 latched-false-green class).

Three existing decisions already supply most of the machinery:

- **ADR-087** — the app-deploy path already runs `cosign verify --offline` against a
  baked, committed `cosign-trusted-root.json` with a workflow-pinned identity regexp, no
  live Fulcio/Rekor egress at verify time. This is the air-gapped keyless verify pattern.
- **ADR-096** — dual-push (GHCR + self-hosted zot) with the host pulling the same
  `@sha256` digest and cosign verifying offline; GHCR is the atomic fallback.
- **ADR-128** — digest-pinned coherence: the mutable control input is a promoted digest
  pointer, not a floating tag.

`ADR-052` blocks *host* egress to Fulcio/Rekor, which an earlier framing read as "keyless
is impossible here." That is imprecise: air-gapped keyless *verify* needs no host egress
(it reads the baked trusted root), and only the *sign* step (in CI, which has egress)
touches Fulcio/Rekor. So keyless is available on exactly the terms ADR-087 already proves.

## Considered Options

- **Option A — pull-based, air-gapped keyless cosign, GHCR-direct host pull (chosen).**
  CI packages the refresh-set into an OCI bundle carrying a signed manifest, keyless-signs
  it (`cosign sign-blob`, OIDC → Fulcio/Rekor at sign-time), and dual-pushes to zot + GHCR.
  A promoted `INNGEST_CONFIG_DIGEST` pointer in the isolated `soleur-inngest/prd` names the
  digest. A host systemd timer resolves the pointer, pulls `@sha256` GHCR-direct, verifies
  offline (`cosign verify-blob` against the baked trusted root + a config-workflow identity
  regexp), checks a per-file sha256 manifest, enforces a **monotonic version read only from
  the signed bytes**, and applies atomically through the existing `infra-config-install.sh`
  root helper. Off-box markers + an absence-heartbeat + a drift comparator close the
  false-green class. Pros: reuses ADR-087/096/128 verbatim; **no private key to custody**
  (the residual root shrinks to "who can run the signing workflow"); no new isolated-Doppler
  secret beyond the pointer (GHCR-direct, no `ZOT_*` on the host); no operator secret-mint
  step (`hr-tf-variable-no-operator-mint-default` is satisfied — the pointer is Doppler-managed,
  no keypair is minted). Cons: the host-side consumer is net-new capability on this host and
  must ride the #6178 cutover to install (bootstrap paradox).

- **Option B — pull-based, cosign STATIC keypair.** As A, but CI signs with a static private
  key (`COSIGN_CONFIG_SIGNING_KEY` in `soleur/prd`) and a committed public verify key is baked.
  Pros: verify is a plain `--key` check with no trusted-root/identity-regexp surface. Cons:
  introduces a private-key-custody problem (rotation = an overlap dance, no revocation — a
  leak forces an emergency `inngest-host-replace` with a new baked pubkey), an operator
  secret-mint step this PR cannot perform autonomously, and a HARD-7 "cosign private key"
  residual-root line that Option A dissolves. Kept as the **documented fallback** if the
  host-side offline `verify-blob` proves impractical at the cutover Phase-0 probe.

- **Option C — push-based (SSH / webhook to the host).** Reuse the web-host webhook/sudoers
  apparatus to push scripts to the inngest host. Rejected: it opens an inbound/deploy-writable
  path on a deny-all-public sole scheduler, violates AP-002 (SSH state mutation) and
  `hr-no-ssh-fallback-in-runbooks`, and widens the deploy-user's authority on the box that
  touches user-facing cron delivery. The pull direction keeps the timer outbound-only and the
  verifier root-owned.

- **Option D — status quo (image-replace-only for `*.sh` too).** Rejected: couples every
  script fix to a full sole-scheduler rebirth; the disproportion is the motivating problem.

## Decision

**Option A** — a pull-based, air-gapped keyless-cosign config-refresh channel, GHCR-direct
host pull in v1. This carves a **narrow `*.sh`-only exception** to the image-replace-only rule
(`hr-prod-host-config-change-immutable-redeploy`): the config *bundle* is a distinct artifact
from the pinned *bootstrap image*, so the four image pin sites (`cloud-init.yml:699/705`,
`cloud-init-inngest.yml:390`, `inngest-bootstrap.sh:492`) are out of scope and untouched.

Binding invariants (each maps to an AC/test; the plan's HARD-1…HARD-12):

1. **The channel engine is outside its own refresh-set (HARD-1).** The verify+apply script,
   the cosign binary, the baked verify anchor, the `.timer`/`.service` units, and
   `applied.version` MUST NOT be members of the refresh-set or `DEST_SPEC`/`FILE_MAP`. They
   change only via host replace. Otherwise one validly-signed bundle replaces the verifier
   with an accept-all shim (signed-once → bypass-forever).
2. **Version is a signed field (HARD-2).** The monotonic version integer lives **inside the
   cosign-signed bytes** (a `VERSION` line in the signed manifest) and is read **only after**
   `cosign verify-blob` succeeds — never from an OCI tag/annotation or the Doppler pointer.
3. **Fail-closed arms (HARD-10).** Each gate is explicit fail-closed: verify rc≠0, sha mismatch,
   a missing/non-integer `applied.version` (fail-closed to a hard floor, never parse-to-0), and
   `infra-config-install rc=3`. Logging/phone-home may `|| true`; a *decision* behind `|| true`
   may not.
4. **Set-atomic apply (HARD-5).** `infra-config-install.sh` is per-file atomic; the channel
   stages+verifies ALL files, swaps all, and advances `applied.version` only after the last
   file lands.
5. **Promotion is Terraform, distinct from signing (HARD-6/HARD-7).** The pointer is written by
   `terraform apply` of a `doppler_secret` (no standing CI write-token into the isolated project).
   The signing workflow is gated behind a GitHub **environment with a required-reviewer set**,
   OIDC-scoped — CI-workflow compromise is the named top residual RCE path, and the monotonic
   gate does nothing against a *fresh* forgery, so the human gate on the signer is load-bearing.
6. **Rejection-as-signal, not silent no-op (HARD-8/HARD-9).** A pull rejected as ≤ current, or a
   pointer-below-baked-floor inversion, emits an explicit marker; the off-box drift comparator
   alarms on `applied_digest ≠ pointer` beyond N windows; the boot-floor marker is distinguishable
   (`version=floor`) so it cannot satisfy the absence-heartbeat while a delta never pulled.

**Signing is keyless** (Option A), per the plan's DEEPEN-CORRECTION-1 and the ADR-087 precedent.
The host-side offline `verify-blob` feasibility against the baked trusted root is re-probed at the
#6178 cutover Phase-0; Option B (static key) is the documented fallback if that probe fails.

**Drift-comparator substrate (refines DEEPEN-CORRECTION-2).** The comparator reads the Doppler
pointer AND queries Better Stack for the latest `APPLIED` marker. Better Stack's ClickHouse query
credentials (`BETTERSTACK_QUERY_*`) live in `soleur/prd_terraform` and are queried from GitHub
Actions via `scripts/betterstack-query.sh` — they are deliberately NOT on the app/Inngest server
(the same reason `cron-terraform-drift` is dispatch-hybrid: parking cloud-admin creds on the prod
host is a security regression). So the comparator is a **dispatch-hybrid**: an Inngest
`cron-inngest-config-drift.ts` is the SCHEDULER (ADR-033, jitter-free) that dispatches a
`inngest-config-drift.yml` EXECUTOR which owns the Better Stack query + comparison. This
is the working shape for a credential-heavy infra cron, not a `.github/workflows/scheduled-*.yml`
on a GHA `schedule:` trigger.

## Consequences

**Easier** (once the host-side consumer lands at the #6178 cutover — see the status banner; the
verbs below are the target steady state, not merged behavior). A host-script fix will ship
in-place: edit the `*.sh` → CI signs + publishes → a Terraform `apply` promotes the pointer → the
host timer will pull, verify, and swap atomically → the change is confirmed off-box via
`SOLEUR_INFRA_PULL_APPLIED` in Better Stack, no SSH, no host replace, zero downtime. Future
host-script changes never again replace the sole scheduler.

**Harder.** The channel installs only through the replace it eliminates (bootstrap paradox): the
host-side machinery rides the #6178 cutover and cannot be exercised before it. The isolation
self-check on the isolated `soleur-inngest/prd` is **exact-set** (`n_total -ne n_inngest`), so the
pointer secret and the regex/floor must move together at the cutover or the host fail-closes on
boot — a partial edit bricks the box. CI-workflow compromise remains the top residual RCE path,
mitigated (not eliminated) by the required-reviewer environment gate on the signer — which is only
real once `inngest-config-signing.tf` is applied (wired into the `apply-web-platform-infra.yml`
`-target=` allow-list; an unapplied environment is auto-created by GitHub WITHOUT reviewers on
first dispatch). Static keys have no revocation, so the Option-B fallback carries a leak →
emergency-replace residual documented in the runbook.

**Observability trust residual (fail-open direction).** The off-box drift comparator treats the
`SOLEUR_INFRA_PULL_APPLIED` marker as *observability, not authority for the digest* — a compromised
host (or anything able to inject a journald/Vector line) can emit a forged marker naming the
*public* promoted pointer digest and mask a stuck/hostile scheduler as `OK`. This is inherent to
off-box monitoring and is an accepted tradeoff: the marker never grants trust — integrity comes
from the host-side signed-bundle verify + monotonic-version gate (HARD-2/HARD-10), which the marker
only *reports on*. The comparator's non-adversarial paths are all fail-closed (empty/unparseable
marker → DIVERGED; query outage → QUERY_UNAVAILABLE). Named here and in the runbook so a future
reader does not mistake a green comparator for cryptographic proof of a current host.

**Scope guard.** The config bundle is a distinct artifact from the bootstrap image; the four image
pin sites and the `vinngest-v*` semver-max guard are Non-Goals here. The shared `DEST_SPEC` widening
(every refresh-set dest becomes grantable on web hosts too, since `infra-config-install.sh` is
cross-host) is noted for the cutover PR, not this one.

## Cost Impacts

None material. Reuses existing GHCR + self-hosted zot (ADR-096, no new registry), the existing
Sigstore public-good keyless path (ADR-087, no vendor cost), and the existing Better Stack Logs
source + Sentry-Crons monitors. The absence-heartbeat monitor rides the current Better Stack tier
(gated on `var.betterstack_paid_tier` if the monitor type requires it — vendor-tier reality check
at apply). Reference `knowledge-base/operations/expenses.md` — no line moves.

## NFR Impacts

- **NFR-026 (Encryption In-Transit): Aligned** — GHCR pull is HTTPS; the zot leg is plain-HTTP on
  the private net with integrity supplied by cosign digest-pinning, not TLS (the established
  ADR-096 posture).
- **NFR-001 / NFR-033 (Logging / Unified Format): Improved** (at the cutover) — every timer run
  will emit a structured off-box marker (`SOLEUR_INFRA_PULL_APPLIED` / `…_VERIFY_FAIL`) to the
  shared Logs source; the drift comparator (shipped now, dormant) makes staleness observable
  without host login (`hr-no-dashboard-eyeball-pull-data-yourself`).
- **NFR-014 (Access Control): Aligned** — no new inbound rule; the timer is outbound-only; the
  verifier runs `root`-owned outside any deploy-writable `$PATH`; promotion and signing are split
  principals.

## Principle Alignment

- **AP-007 (Exhaust automation before manual steps): Aligned** — the channel replaces the manual
  `inngest-host-replace` toil for every host-script change with an automated in-place pull.
- **AP-002 (No SSH state mutation): Aligned** — the pull direction keeps the host deny-all-public
  and outbound-only; no webhook/sudoers/SSH push path is added.
- **AP-001 (Terraform-only provisioning): Aligned** — the pointer and the monitor are Terraform
  `doppler_secret` / Better Stack resources; the host bake is cloud-init under the normal apply path.
- **AP-011 (ADRs for architecture decisions): Aligned** — this record carves the `*.sh`-only
  exception to the immutable-redeploy rule and fixes the keyless-vs-static and dispatch-hybrid
  substrate choices a future author would otherwise re-litigate.
- **AP-016 (GHCR read credential): Aligned** — the host pulls the config bundle GHCR-direct by
  digest on the same baked read credential it already uses for the bootstrap image (no new
  isolated-Doppler secret in v1).

## Amendment — 2026-10-13 (#6780 host-side consumer lands)

**Status change: producer-complete → channel complete.** The host-side consumer this ADR
specified — deferred through the #6178 cutover — is now baked into `cloud-init-inngest.yml`
(`inngest-config-refresh.sh`, `inngest-config-refresh.{service,timer}`,
`/etc/soleur/cosign-trusted-root.json`, `/var/lib/inngest-config/applied.version`). It reaches
`soleur-inngest` on the next sanctioned `inngest-host-replace`; first promotion remains a
deferred operator apply (#9060). Three reality corrections against the original decision text:

1. **Host pull is ZOT-DIRECT, not GHCR-direct.** The v1 text chose GHCR-direct because it
   needed no `ZOT_*` credential on the host. #8036 item 1d inverted the credential set: the
   dedicated host's GHCR read bake was deleted and `/etc/default/soleur-zot-read` (the
   zot pull credential the bootstrap image pull already uses) is now the ONLY registry read
   left on the box. The consumer therefore pulls
   `$ZOT_EP/jikig-ai/soleur-inngest-config@sha256:<pointer>` over the private net, sourced
   from that same env file. The security properties the decision actually depends on are
   unchanged: integrity stays digest-pinned, provenance stays offline `cosign verify-blob`
   against the baked trusted root, and the GHCR-first/zot-mirror publish step already
   guarantees digest parity (crane copy preserves the digest). The `continue-on-error` on the
   zot mirror step stays because the consumer is not yet production-wired; first promotion
   requires the mirror to have run. **Consequence reversal:** GHCR is now the CI/audit copy;
   zot is the host-authoritative copy — the inverse of the v1 framing.
2. **Marker channel authority.** The named off-box rows are the `SOLEUR_INFRA_PULL_*`
   family (`APPLIED`, `VERIFY_FAIL`, `FLOOR`, `NOOP`, plus the seam-refusal row). The
   marker emitter of record is `inngest-boot-phone-home.sh` (the pre-existing
   Better-Stack-over-HTTPS POST path), extended so `sha256=<64hex>`-labeled digests survive
   its hex redactor; journald → Vector Source 4 (`inngest-config-refresh` tag) is the
   durable on-host channel and ships the same rows off-box. The drift executor greps the
   whole `SOLEUR_INFRA_PULL_` family and feeds only STATE rows (APPLIED/NOOP/FLOOR) to the
   comparator — failure rows carry `reason=`/`offered=`/`rejver=` deliberately never
   `version=`/`sha256=` labels so a rejected offer can never parse as applied state.
3. **Refresh-set v1 membership is the five dedicated-host carriers** (`inngest-redis-bootstrap.sh`,
   `inngest-cutover-flip.sh`, `inngest-server-flip-guard.sh`, `cat-inngest-cutover-state.sh`,
   `inngest-luks-cutover.sh`), scripts-only — correcting the seeded web-host list, which was a
   producer-contract placeholder (those eight are not dedicated-host dests). `DEST_SPEC` +
   `FILE_MAP` + the push payload widened in lockstep; on web hosts the five are inert dead
   files. Units/`vector.toml` stay out of v1 (unit swaps need daemon-reload/restart semantics
   the channel deliberately lacks).
4. **Payload delivery is `indent(6, file())` text-embed, not b64.** D12's ordered fallbacks —
   `base64encode(file())` then `base64encode(replace(file(), strip, ""))` — were measured
   ~4.5 kB heavier stored and overflowed the 32 KiB user_data cap (the b64 alphabet defeats
   the outer gzip). The template instead lands the two repo files verbatim inside
   `content: |` scalars via templatefile `indent(6, …)` (the established git-data idiom):
   single-source `file()` reads, byte-identical to the repo bytes modulo the payload's own
   comment-line strip. Byte-authoritative measure at commit: 31,868 B stored / 900 B
   headroom (inngest-userdata-budget.sh).

Deferred operators unchanged: no host replace, no first promotion, no drift-executor secret
wiring, no monitor wiring in this PR.

## Addendum - 2026-10-14 (#7243): the GHCR-direct host pull no longer holds

The record above says the host pulls the config bundle GHCR-direct by digest on a baked GHCR read
credential (Option A, the AP-016 line). That premise is superseded in effect by ADR-096: its
2026-07-30 amendment records AP-016 as lapsed (the GHCR read PAT is revoked, so a GHCR pull answers
401) and its later amendments deny `ghcr.io` by name on the dedicated host, with zot the only
boot-time read path (`cloud-init-inngest.yml`: zot is the only pull). A host consumer for this
bundle, when it lands (HARD-11, with the #6178 cutover), therefore has to resolve the bundle through
zot, which makes the zot copy written by `build-inngest-config-bundle.yml` load-bearing rather than a
convenience.

Consequences, stated without editing the sections above: the mirror step in that workflow is
interim-soft (it degrades loudly and exits 0, `SOLEUR-DEBT` marker in its comment) because no host
reads the bundle yet, and it must become blocking, as `reusable-release.yml`'s mirror is, when the
consumer reads zot only. The body of this ADR keeps its original wording as the record of the
decision at the time; amend it in full when the consumer is built.

## Addendum 2026-10-21 — defect 2: the verifier image itself was un-mirrored

The "zot is the ONLY registry read on this host" claim was one image short: the refresh
tick ran `docker run --network none gcr.io/projectsigstore/cosign@sha256:57c0e93a…`, whose
daemon-side implicit pull needs the public egress this host does not have. The verify path
had never run (v1 died at extract, v2 reached verify and died at the pull), and the failure
emitted as `reason=signature` — a fetch failure misattributed to provenance. Fix: the
bundle producer's `zot_mirror` step now also copies the pinned cosign image to
`127.0.0.1:5000/jikig-ai/cosign:v3.1.1` and equality-checks the mirrored digest; the host's
`COSIGN_IMAGE` default resolves to `${ZOT_EP}/jikig-ai/cosign@sha256:57c0e93a…` after
`ZOT_EP`, staged by an explicit bounded pull that reports `reason=pull
member=cosign-image`. The claim is now literally true. The gcr ref remains correct on the
web hosts, which have public egress (ADR-096 amendment 2026-09-28).

## Addendum 2026-10-22 — defect 3: honest rejects were undebuggable (stderr swallowed)

The verify path ran `docker run … verify-blob … >/dev/null 2>&1`, mapping EVERY non-zero
exit — cryptographic reject, cosign flag-parse error, docker daemon error, `timeout` kill —
onto `reason=signature`. When the promoted v3 bundle began rejecting honestly on the host,
the channel carried no evidence of why, and the three plausible suspects (tlog reach under
`--network none`, trusted-root staleness, identity-regexp drift) could not be separated
without a host login.

Two measurements close the suspects without one: the baked trusted root is key-identical
to Sigstore's live root, and a v0.3 bundle reconstructed from the real Rekor entry verifies
`Verified OK` under the verbatim `--network none` invocation — the offline machinery is
sound. The remaining hypothesis class is bundle-load (`sgbundle.LoadJSONFromPath`, which
cosign v3.1.1 gates `--trusted-root` on) or host-state divergence, discriminated by
evidence rather than flags.

Fix (this PR): the tick now captures stderr to a bounded on-host `$STATE_DIR/verify.stderr`
(4 KiB, 0600, last-failure-only) — around the `timeout` wrapper so rc=124 still lands it —
and classifies it into a `[a-z-]{1,24}` `detail=` token (`flag-newbundle|tlog|identity|
chain|timeout|docker|other`) appended additively to the VERIFY_FAIL row, which survives the
phone-home redaction and the drift summarizer's allowlist. A kept dispatch-only workflow
(`diagnose-inngest-verify.yml`) reproduces the verbatim invocation in CI with stderr
visible. No verification-relaxing flag (`--insecure-ignore-tlog`, `--insecure-ignore-sct`,
`--key`, `--new-bundle-format`) was added — adopting one is a posture change requiring an
amendment here, not a patch (HARD-10's spirit extended: diagnosability must not cost
fail-closed).
