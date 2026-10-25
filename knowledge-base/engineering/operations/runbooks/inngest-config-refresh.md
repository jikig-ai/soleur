# Runbook: shipping a host-script change through the Inngest config-refresh channel

**TL;DR:** Edit the host-executed `*.sh` → merge to main → run the
[`build-inngest-config-bundle`](../../../../.github/workflows/build-inngest-config-bundle.yml)
workflow (keyless-signs + dual-publishes, emits `IMAGE@DIGEST`) → promote the digest through
Terraform (manual targeted apply; #9060 automates it per-merge) → the host's config-refresh timer pulls, verifies, and applies it in-place. Confirm
off-box with [`scripts/betterstack-query.sh`](../../../../scripts/betterstack-query.sh). No host
login, no host replace (ADR-135, #6780).

## ⚠️ CHANNEL-LIVE PRECONDITION (HARD-11) — check this FIRST

**The channel is DORMANT until the host-side consumer bake rides the #6178 cutover (PR #6348).**
Before trusting any step below, assert the channel is live off-box:

```bash
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh --since 48h --grep SOLEUR_INFRA_PULL_ --limit 10
```

Read the LATEST state rows by meaning — do not grep APPLIED alone: in the healthy
baked-but-unpromoted state the host emits only `SOLEUR_INFRA_PULL_NOOP reason=empty-pointer`
every 300 s, so an APPLIED-only check reports a live channel as dead.

- **No `SOLEUR_INFRA_PULL_` rows at all ⇒ the channel is NOT live.** The host-side timer +
  verify+apply script + pointer admission arrive with the #6178 cutover. Stop.
- **`NOOP reason=empty-pointer` (or `FLOOR`) rows ⇒ live but unpromoted** — the timer is ticking;
  proceed to promotion and the next tick applies.
- **`VERIFY_FAIL` rows ⇒ live and rejecting** — go to the failure table below; the `reason=`
  token names the cause.
- **`APPLIED` rows ⇒ live and promoted**; proceed.

The [`inngest-config-drift`](../../../../.github/workflows/inngest-config-drift.yml) comparator
(dispatched by `cron-inngest-config-drift`) enforces the same gate mechanically: it returns
`PENDING` (green) while no pointer is promoted, and alarms only once a promoted pointer diverges
from the applied digest.

## Ship a host-script change

1. **Edit** the host-executed script under `apps/web-platform/infra/`. If it is a NEW member of the
   refresh-set, add its path to
   [`inngest-config-refresh-set.txt`](../../../../apps/web-platform/infra/inngest-config-refresh-set.txt)
   — and confirm it is already an inngest-host dest in `infra-config-install.sh` `DEST_SPEC` (the
   channel reuses that root helper; it never widens the dest set — HARD-1). Merge to main.

2. **Build + sign + publish.** Trigger the producer workflow at the next monotonic version (it MUST
   exceed the current applied version / baked floor — HARD-9):

   ```bash
   gh workflow run build-inngest-config-bundle.yml -f version=<N+1>
   ```

   Dispatch only from the **default branch** (no `-r` flag): the host pins
   `@refs/heads/main` in its identity regexp, so a branch-dispatched bundle verifies at the
   producer gate but fails the host's check (`reason=signature`, `detail=identity`).

   The run is held for reviewer approval (the `inngest-config-signing` environment — HARD-7), then
   `cosign sign-blob`s the manifest (VERSION is a signed field — HARD-2) and dual-publishes to GHCR +
   zot. Its job summary prints `IMAGE@DIGEST`.

   Producer contract (#10390 defect 3): the sign step pins the emit surface via
   `--signing-config apps/web-platform/infra/inngest-signing-config.json` — a committed
   signingconfig v0.2 document (Fulcio v1 + oauth2.sigstore.dev v1 + Rekor v1 only, **no
   `tsaUrls`**; shape-pinned by `inngest-config-bundle-mirror.test.sh`'s jq rows) — and
   normalizes the emitted `.sigstore.json` to mode 0644, because cosign writes it 0600
   and the consumer's nonroot verifier container reads the bind-mounted member EACCES
   (the measured defect-3 root cause, not an envelope defect). A "Verify produced
   bundle before publish" step then runs the PINNED cosign image over a bind mount and
   hard-fails unless it prints `Verified OK`; if that step is red the artifact never
   reaches GHCR/zot — read the step log's cosign error and fix the producer, never
   re-dispatch past it.

3. **Promote the pointer (separate principal — HARD-6).** The interim route is a MANUAL targeted
   apply in an authorized window — set the Doppler secret `INNGEST_CONFIG_DIGEST=<IMAGE@DIGEST
   sha256>` in `soleur/prd_terraform`, then apply `doppler_secret.inngest_config_digest` (the
   `count`-gated resource springs to life on a non-empty value). The tf-var transformer surfaces
   the secret to terraform as `TF_VAR_inngest_config_digest`; do NOT create a secret literally
   named `TF_VAR_inngest_config_digest` — under the transformer it arrives as
   `TF_VAR_tf_var_inngest_config_digest`, undeclared-var noise (the mis-set observed 2026-10-24).
   The apply is a state write, so its `AWS_*` must come from `TF_STATE_AWS_*` in
   `soleur-infra-privileged/prd` per
   [`infra-credential-tiers-8209.md`](./infra-credential-tiers-8209.md) §Local Terraform
   invocation — the `prd_terraform` pair is read-only and 403s the state push. Verify the secret
   landed with `doppler secrets get INNGEST_CONFIG_DIGEST -p soleur -c prd_terraform --plain`. The
   regex+floor admission already LANDED (regex at #8754; floor 5→6 in the defect-3 producer
   fix) — what survives is the ordering gate: between that merge and this apply, NO dispatch
   that renders and boots merged cloud-init may run (cloud-init-inngest.yml). #9060 automates this per-merge (`-target` route); its absence does not block
   the manual promotion — `doppler_secret.inngest_config_digest` is on no job's `-target` list
   (pinned by `plugins/soleur/test/terraform-target-parity.test.ts`), so no merge reaches it.
   Terraform is the writer, so no standing CI token can write the isolated `soleur-inngest/prd`.

4. **Confirm off-box** (no host login):

   ```bash
   doppler run -p soleur -c prd_terraform -- \
     scripts/betterstack-query.sh --since 1h --grep SOLEUR_INFRA_PULL_APPLIED --limit 1
   ```

   A `SOLEUR_INFRA_PULL_APPLIED version=<N+1> sha256=<digest> verify=ok` line within the timer window
   is the applied-and-verified signal. A `SOLEUR_INFRA_PULL_VERIFY_FAIL` line means the host rejected
   the bundle and kept last-known-good (fail-closed — HARD-10); read the reason and re-cut.

## Batching & promotion cadence

The producer version is monotonic, not per-commit: batch several host-script edits into one bundle
and promote once. Promotion (step 3) is the single mutable control input — the cosign signature, the
per-file sha256 manifest, and the monotonic version bound its authority, so a mis-promotion is caught
(rejected, not silently applied). Keep the absence-heartbeat grace window ≥ the timer cadence so a
skipped promotion does not read as a dead timer.

## Signing rotation (keyless — ADR-135 / ADR-087)

Signing is air-gapped keyless cosign: there is no private key to custody. To rotate the trust anchor,
follow the ADR-087 trusted-root re-capture recipe (re-capture `cosign-trusted-root.json` under the
pinned verifier container; the staleness gate `cosign-trusted-root-staleness.test.sh` tracks it), and
update the host verify identity regexp to the config-bundle workflow. There is no key-overlap dance.

**Static-key fallback residual (Option B, ADR-135):** if the host offline `verify-blob` proves
impractical at the cutover Phase-0 probe and the static-key fallback is adopted instead, note that
static keys have no revocation — a leaked signing key requires an emergency host replace
(`gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason=<why>`)
with a freshly baked public key. That residual does not apply to the chosen keyless path.

## Failure modes → where they surface (all off-box)

| Mode | Detection | Signal |
|---|---|---|
| bad/missing signature | host `cosign verify-blob` non-zero. Since the defect-3 fix the row carries a `detail=` token classifying the swallowed stderr: `flag-newbundle` (bundle fails `sgbundle.LoadJSONFromPath` — cosign's `--trusted-root` gate), `tlog` (log-inclusion/rekor), `identity` (identity/SAN/issuer), `chain` (certificate chain/x509), `timeout` (rc=124), `docker` (daemon error), `other`. The captured stderr lives on-host at `/var/lib/inngest-config/verify.stderr` behind a `# ts=`/`offered=`/`rc=` binding header (bounded ~4 KiB, last failure only) — the `detail=` token is a first-match triage hypothesis, not a verdict: confirm against the stderr body or the diagnose workflow before fixing; reproduce off-box via `gh workflow run diagnose-inngest-verify.yml -f digest=<sha256>` — source the digest from the drift comparator summary's `sha256=` field or the producer run's `IMAGE@DIGEST` output (the workflow's `default` goes stale on the next promotion; the row's `offered=` is truncated to 12 hex and cannot supply it) | `SOLEUR_INFRA_PULL_VERIFY_FAIL` |
| verifier image unfetchable | zot pull of `jikig-ai/cosign@sha256:…` fails before the verify run — `reason=pull` with `member=cosign-image` distinguishes it from a bundle-pull miss; PRE-FIX `reason=signature` could also mean this (the daemon-side pull inside `docker run` misattributed to provenance — #10390 defect 2). Remediation: re-dispatch `build-inngest-config-bundle.yml` — its `zot_mirror` leg re-mirrors the verifier image unconditionally (check the run's step output for `mirror_status=ok`, not just conclusion: a degraded leg still exits 0) | `SOLEUR_INFRA_PULL_VERIFY_FAIL` |
| version rollback/replay | monotonic gate reject (version read only from signed bytes) | `SOLEUR_INFRA_PULL_VERIFY_FAIL` |
| manifest sha mismatch | per-file sha256 compare fail | `SOLEUR_INFRA_PULL_VERIFY_FAIL` |
| dead timer (silent) | Better Stack absence-heartbeat (no APPLIED marker in window) | absence alarm |
| stale re-baked floor (#6594) | `inngest-config-drift` comparator: applied digest ≠ promoted pointer; the boot-floor marker is distinguishable (`version=floor`) so it cannot mask a stuck delta | drift alarm |
| Better Stack query outage | `inngest-config-drift` executor distinguishes a query failure from a dead timer | `QUERY_UNAVAILABLE` (attributed to the instrument, not the host) |

The full marker family is `SOLEUR_INFRA_PULL_{NOOP,FLOOR,APPLIED,REPAIRED,VERIFY_FAIL,SEAM_REFUSED}`
plus the refusal `SEAM_REFUSED` (a `REFRESH_*` fixture-seam name in the environment; provisioning
finding, not a channel failure). `VERIFY_FAIL` `reason=` tokens are enumerated at the emit sites in
`cloud-init-inngest.yml` (`pointer-malformed`, `pull-endpoint-absent`, `pull-login`,
`pull-creds-absent`, `pull`, `extract`, `manifest-absent`, `signature`, `manifest-version`,
`rollback-or-replay`, `manifest-empty`, `manifest-member-name`, `sha`, `install`, `version-write`,
`ledger-write`). `REPAIRED` means the host detected a torn ledger (`applied.version` ahead of
`applied.json`) and self-healed it with the verified bundle — audit, not action.

**Torn-state recovery.** If `applied.json` is lost while `applied.version` survives, the same
`VERSION` promotion is permanently `rollback-or-replay`-rejected by design — the repair arm
recovers it automatically on the next promotion attempt of that version (same VERSION + different
digest = the torn-ledger signature; it installs and rewrites both files). A *newer* promotion also
heals it. Worst case, deleting `applied.version` re-seeds floor 0 and re-drives the pending
promotion — the FLOOR row makes that state distinguishable off-box.

**Trust residual (fail-open direction).** The drift comparator treats the `SOLEUR_INFRA_PULL_APPLIED`
marker as **observability, not authority for the digest**. The promoted pointer digest is public, so a
compromised host — or anything able to inject a journald/Vector log line — can emit a forged
`SOLEUR_INFRA_PULL_APPLIED … sha256=<current-public-pointer>` and mask a stuck/hostile scheduler as
`OK`. This is inherent to off-box monitoring: a green comparator is **not** cryptographic proof of a
current host. Integrity comes from the host-side signed-bundle `cosign verify-blob` + monotonic-version
gate (which the marker only reports on), never from the marker. All non-adversarial paths fail closed
(empty/unparseable marker → drift alarm; query outage → `QUERY_UNAVAILABLE`).
