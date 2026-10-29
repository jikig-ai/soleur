---
title: Inngest key rotation runs through a dedicated dispatch-only workflow in two Terraform phases, derives the app copy from the dedicated random_id, and restarts the scheduler with a Hetzner soft reboot
status: active
date: 2026-10-27
supersedes: none
issue: 10540
related: [10540, 10205, 10382, 10136, 11215, 11218, 11292, 11293, 11294]
related_adrs: [ADR-100, ADR-294, ADR-241, ADR-280]
brand_survival_threshold: single-user incident
tags: [inngest, secrets, rotation, terraform, doppler, hetzner, ci]
---

# ADR-307: Inngest key rotation runs through a dedicated dispatch-only workflow in two Terraform phases, derives the app copy from the dedicated random_id, and restarts the scheduler with a Hetzner soft reboot

## Context

`INNGEST_SIGNING_KEY` and `INNGEST_EVENT_KEY` are one shared app-to-host channel credential (ADR-100 Decision 4, as corrected by its 2026-07-24 amendment). Two copies exist and must be equal: the dedicated host's `soleur-inngest/prd` and the web app's `soleur/prd`. Step A5 of the TLS rollout (#10136) is a rotation of the signing key, and #10540 asks for the repository-side route that an owner-authorised rotation travels through. This record is the single place that holds the rationale for that route. The runbook (`inngest-server.md`), the workflow header and the owner-ask probe point here and do not restate it.

Five facts found while planning shaped the decision. Each was verified against the repository, not assumed.

1. **The issue's "minimal `apply_target`" does not fit the existing workflow.** `apply-web-platform-infra.yml` sits within a few hundred bytes of its 490,000-byte size gate. Its `inngest_host` job is additive-only: the shape gate refuses a `generated_secret_touched` plan, so it cannot replace a `random_id`.
2. **The runbook's restart lever does not reach the dedicated host.** `restart-inngest-server.yml` goes through the `/hooks` channel, which terminates on web-1. Web-1's quiesced scheduler unit refuses a restart (`ci-deploy.sh`, the `inngest_quiesced_restart_refused` path), and `deploy-status` reports web-1, not `10.0.1.40`. The only no-SSH lever that reaches the dedicated host is a Hetzner control-plane soft reboot.
3. **The app copy cannot be written by a CI token.** No CI token writes the `soleur/prd` root generically: `DOPPLER_TOKEN_WRITE` is bound to `prd_terraform`, `DOPPLER_TOKEN_INNGEST_ARM` to `soleur-inngest/prd`, and `DOPPLER_TOKEN_GIT_DATA_FLAG` is purpose-limited. The Terraform Doppler provider token already writes `soleur/prd`. "Copied out of band", as `inngest.tf` and the runbook said, therefore had no automated carrier.
4. **Terraform prints key bytes, and the repository is public.** A `random_id`'s `id` is the key in base64url and `hex` is not sensitive, so a plan, an apply or a refresh prints key material. Existing dispatch jobs that print Terraform output unfiltered may already have published the dedicated pair; that audit is filed as #11294 (type/security, p1) and is not part of this change.
5. **The link canary proves the new key.** Before the swap, `ci-deploy.sh` runs a canary against the scheduler (`/health`, `/v1/events` with the hashed-signing-key bearer, a real event send, a registry read). It returns 200 only when the scheduler holds the same keys as the app copy, and a failure keeps the old containers. The order "scheduler first, then redeploy" is therefore mandatory.

## Considered Options

- **Option A: a new `apply_target` job in `apply-web-platform-infra.yml`.** Pros: the issue's literal wording. Cons: the byte gate leaves no room; extracting prose to make room is an unrelated refactor inside a production-credential change; the shape gate would need a rotation exception.
- **Option B: a dedicated workflow (chosen).** Pros: precedent (`workspaces-luks-cutover.yml`, `inngest-link-flip.yml`); a minimal Terraform target set; its own credential bindings and census row. Cons: one more Tier-B workflow to register.
- **Option C: copy the host value into `soleur/prd` with the Doppler CLI.** Pros: no Terraform change. Cons: plaintext through a shell, and a write token for the `soleur/prd` root does not exist.
- **Option D: a new narrow write token, or reuse of `DOPPLER_TOKEN_GIT_DATA_FLAG`.** Cons: new credential surface, or a token bound to another environment with unverified scope.
- **Option E: restart through `restart-inngest-server.yml`.** Cons: cannot reach `10.0.1.40`; it would try to start web-1's quiesced scheduler.
- **Option F: restart through `inngest-host-replace`.** Cons: owner-gated twice and far heavier than a key change (a new host and a LUKS volume).
- **Option G: a new in-place FSM state delivered by the signed config-refresh bundle.** Cons: new code on the sole scheduler's start path; larger than a minimal route.
- **Option H: a two-key rotation with `INNGEST_SIGNING_KEY_FALLBACK`.** Cons: the self-hosted-server flag is unverified and the event key has no fallback at all.
- **Option I: a separate `mode=reboot-check` before `rotate`.** Cons: a second sole-scheduler downtime for the same LUKS-reopen risk; the two-phase order already separates a host problem from the app key.
- **Option J: hard-block `inngest-link-flip.yml action=off` after a rotation.** Cons: removes the incident rollback; an extra explicit confirm gives the same protection against the silent case.

## Decision

**Rotate through a dedicated, dispatch-only workflow `.github/workflows/inngest-key-rotate.yml`, orchestrated by `scripts/inngest-key-rotate.sh`, in two Terraform phases with a Hetzner soft reboot and a Better Stack verification between them. The app copy is derived from the dedicated `random_id`.** Ruled by the CTO agent, 2026-10-27 (`decision-challenges.md` F1-F7, R1-R5).

1. **Route shape.** Inputs `mode` (`plan`, `rotate`, `converge`), `keys` (`signing`, `event`, `both`; no default), `confirm`, `reason`, `rotated_at` (converge only, optional, cross-checked) and `quiet_window`. Environment `infra-privileged`; dispatch-only, with a path-scoped push trigger that exists solely to register the workflow and every job guarded on `workflow_dispatch`. `mode=plan` is the read-only rehearsal. `mode=converge` finishes a rotation that failed after its first apply and never mints a key.
2. **The app copy is Terraform-derived.** `doppler_secret.inngest_{signing,event}_key_prd` take their value from `random_id.inngest_{signing,event}_key_dedicated` (the same expressions the dedicated secrets use). `ignore_changes = [value]` stays on the app secrets, so a per-merge plan still shows no diff. A rotation is `-replace` on the dedicated `random_id`s, which updates the dedicated secrets in place, and then `-replace` on the app secrets, which are recreated with the new value because `ignore_changes` covers updates, not creates. Equality of the two copies holds by construction and is also checked at runtime by hashing on a pipe (booleans only). The orphaned `random_id.inngest_{signing,event}_key_prd` stay declared and unreferenced; their removal is tracked in #11293.
3. **Two phases, in this order.** `guard` (no writes), `apply1` (the dedicated pair), `reboot` (one POST, then verification), `apply2` (the app secrets), `redeploy` (canary-then-prod fleet redeploy through `track.sh`). The `soleur/prd` key that unrelated deploys read is untouched until the scheduler is verified SERVING, so a failed reboot leaves web running on the old app key. Between the two phases the copies legitimately differ, and the cutover `op=arm` G3.5 parity gate fails closed in that window.
4. **The restart lever is a Hetzner soft reboot.** The reboot job resolves exactly one server by name `soleur-inngest` and private IP `10.0.1.40`, makes at most one `POST /v1/servers/<id>/actions/reboot` per run (a per-process latch refuses a second), and polls the action. `success` means only that the ACPI request reached the guest, so the evidence is a new `boot_id` within 10 minutes, then `inngest-host-state.sh` `SERVING=yes` and a `tls-health` row with that `boot_id` and `listener=1`, read from Better Stack (rows pinned by the `host` field `soleur-inngest`, marker `SOLEUR_INNGEST_BOOT_STAGE`, stage `tls-health`, shipper `cloud-init-phone-home`; that `host` field's presence on the live rows is unverified, and a row without it yields no verdict, never a NOT SERVING claim). No new `boot_id` is `host_silent`; a missing field is "no verdict", never a NOT SERVING claim. The route never hard-resets and never retries; a hard reset is a separate owner go. A rotation is forward-only: after phase 1 no copy of the old key exists, so recovery is `converge`, not a rollback.
5. **Refusal ladder.** `guard` refuses `rotate` and `converge` unless all hold: `github.run_attempt` is 1 (a GitHub re-run reuses the inputs and would bypass the owner's go; "Re-run all jobs" is refused by the guard, "Re-run failed jobs" is refused by every write job, and only `plan` may be re-run); inputs and the typed confirm are well-formed; `quiet_window` is attested; the link flag (`INNGEST_LINK_TLS`, listed with `doppler secrets --only-names` and read with `doppler secrets get INNGEST_LINK_TLS --plain -p soleur -c prd_terraform`) resolves to `1`; tracker #11215 is closed as completed; no related run is in flight; exactly one server is named `soleur-inngest` at `10.0.1.40`; for `rotate`, the pre-reboot host reads SERVING. `mode=plan` reports each of these as a boolean and refuses on none. The guard job has no environment and holds the read-only Hetzner token; only the reboot POST step holds the write token.
6. **The typed confirm and `quiet_window` are not the authorization.** The authorization is the owner's fresh in-session go naming the exact command (mode, keys, typed confirm). A go on another issue does not count, no delegation covers it, and agents never dispatch `rotate` or `converge`. The workflow prints the `S5-A5-DONE` line for keys `signing` or `both`, and never posts it: the owner posts it themselves on #10136, and an agent-posted line does not satisfy the owner record.
7. **Rollback guard (Guard 3).** `rotate` refuses unless the link flag is `1`, so the new key never rides plaintext `:8288`. `scripts/inngest-link-flip.sh` requires `OFF-AFTER-ROTATION` (workflow input `confirm_off_after_rotation`) at the chokepoint `flip_apply_flag off`, and for `flip` as well, once any non-`plan` run of `inngest-key-rotate.yml` exists. `flip` can start from a flag already at `1` and its failure revert is `off`, so it takes the same confirm. The `revert` step is never given the confirm and logs the refusal through its existing warning branch. The run test matches `displayTitle` over the last 200 runs, counts a rotate that applied and then failed (it already holds the new key; a false positive costs one extra confirm), and fails closed when the run list cannot be read.
8. **Lock topology.** Workflow group `inngest-key-rotate` (never cancelled); `terraform-apply-web-platform-host` on the two Terraform jobs; `deploy-inngest-restart` (the shared inngest mutex) on the reboot job. `web-platform-release` has a per-SHA group and is not serialized against the route, which is why the in-flight-run refusal runs again as the first act of every write job.
9. **No Terraform stream reaches a log (Guard 2).** Every Terraform call goes through one wrapper (`kr_tf`) that sends stdout and stderr to a private file, unsets `TF_LOG`, and prints nothing; the plan, the plan JSON and the temp dir are never printed or uploaded. On failure only an exit code and jq-derived addresses and actions are printed. The one remaining scrub covers short Hetzner, Better Stack and `gh` error bodies.
10. **Plan gates (Guard 1).** Gate A (phase 1) and Gate B (phase 2) are built from one table in the script, so the `-target` list, the `-replace` flags and the jq allowlist applied to `terraform show -json` cannot drift. Gate A allows only the dedicated `random_id`s as `["delete","create"]` and the dedicated secrets as `["update"]`; Gate B allows only the app secrets as `["delete","create"]` (or the bare-`create` recovery shape with `before` null) with the dedicated addresses as no-ops. Exact address equality, an exact `actions` array and an exact change count are required, so an empty plan fails; any `hcloud_*` address, a bare `create` of a dedicated `random_id`, or an unselected pair changing is refused.

**Anchor statement for Guard 1.** The allowlist table and `terraform-target-parity.test.ts` pin the same set. Both live in this repository, so the guard proves consistency, not integrity. Integrity rests on `infra-privileged` being main-only and on required review.

## Consequences

**Easier.**

- A rotation is one owner-authorised dispatch with fixed verdict tokens (`bash scripts/inngest-key-rotate.sh --print-contract` lists them), value-free evidence, and a defined recovery (`converge`).
- The app copy is derived from the host copy's source, so it cannot drift from it; the separate copy step is gone.
- The reboot lever is automated and reaches the dedicated host, which the runbook's earlier lever could not.

**Harder, and unverified or residual.**

- **The production host has never been rebooted with its LUKS volume and live scheduler.** This is unverified. The sole scheduler is down for the boot (minutes), one cron tick inside the boot gap may be skipped (it is unverified whether Inngest backfills it), and the owner's go must name this residual in plain words. The dedicated unit has no Doppler fallback cache across a reboot, so a cold boot depends on the live Doppler read; a stale boot key fails the redeploy canary, which keeps the old containers (the safe detector).
- **Key-mismatch window.** From the reboot until the redeploy completes (up to the 4800-second pipeline ceiling), the scheduler holds the new key and old web containers hold the old one. An approved Concierge action or a Stripe `invoice.payment_failed` event can be rejected with 401 and lost or retried late. The `quiet_window` attestation covers claude crons, Concierge actions in flight, pending `payment_failed` and an Art. 15 request mid-response. A merge or release that deploys between the phases reads the old app key against the new scheduler and fails its canary (a red release, not an outage); the in-flight-run refusal covers it.
- **The `-replace` of an app `doppler_secret` is destroy-then-create.** There are a few seconds with no key in `soleur/prd`; running containers keep their baked environment.
- **Forward-only.** There is no old key to restore. `converge` resumes from observed state: copies unequal means phase 1 is done; the newest boot starting after `rotated_at` means no second reboot POST; a Hetzner reboot action running or finished after `rotated_at` also means none.
- **Accepted residuals of Guard 3.** (a) GitHub's default 90-day run retention expires the marker, so after 90 days without a retained run the off confirm no longer fires. (b) Deleted run history resets it. (c) Dispatching `apply-web-platform-infra.yml apply_target=inngest-link-flag inngest_link_value=off` directly bypasses the script and so the confirm. All three are accepted because a hard block would remove the incident rollback.
- **Terraform key exposure outside this route.** Existing dispatch jobs that print Terraform output may already have published the dedicated key pair in a public log (#11294). Rotation retires whatever value those logs carried; the audit itself is separate.
- **Deferred, tracked.** An HTTP-level "old key rejected" check (#11292; a single-key server refuses the old key by construction and the old value exists nowhere after rotation); removal of the two orphaned `_prd` `random_id`s (#11293, their destroy handling in the shape gate and parity tests is unverified).
- The route is a long script and a long static suite for an operation done a few times a year; the brand-survival threshold (`single-user incident`) is the reason. Cut order if scope must shrink: `converge` first, then the off-after-rotation confirm.

## Amendments

### 2026-10-29 (CTO rulings and corrections found while finishing the route)

Ruled by CTO agent, 2026-10-29 (`decision-challenges.md`, rows dated 2026-10-29):

- **Fix A (redaction of the `random_id` `[id=` log lines, #11294) ships as its own PR**, owned by another agent, and is not cherry-picked into this branch. The unredacted `tunnel_secret` exposure does not block this PR, because the route itself never lets a Terraform stream reach a log (Guard 2).
- **Key exposure order.** Treat the current dedicated key pair as compromised (existing dispatch jobs print Terraform output unfiltered in a public repository). The rotation waits for this route and Fix A to merge, then runs as owner-gated step A5 after the soak (A4) passes and before 2026-11-12.
- **The soak FAIL is real.** The A4 soak reported `legacy_8288` +12, which is not benign: the soak is re-anchored and re-run, and `rotate` stays refused (`soak_open`) until tracker #11215 is closed as completed.

Corrections to the record above, found by reading `scripts/inngest-key-rotate.sh`:

- **R4, the converge source.** `converge` derives `keys` and `rotated_at` from the newest earlier `rotate` run only (never an older one; a run titled `converge` and any `plan` run are skipped), and that run's `apply1` job must have concluded `success`. It is **not** unbounded in age: a source whose first apply finished more than 24 hours ago is refused as `converge_stale`. A `rotate` whose first apply failed is not resumable (`converge_source_missing`); its recovery is a fresh `rotate` under a fresh go, and the stop sentence says so. The earlier wording "no age limit" in R4 is superseded.
- **Re-run wording.** See Decision item 5: the guard refuses "Re-run all jobs", every write job refuses "Re-run failed jobs".
- **The link flag read and the host pin** are as stated in Decision items 4 and 5 (the earlier text named a `doppler run` read and a `host_role` pin that the script does not use).
- **Unverified at merge time, disclosed.** (a) Whether `-replace` on a `doppler_secret` carrying `ignore_changes = [value]` recreates it with the new value (the premise of Decision item 2; `value_unchanged` is the detector). (b) A production reboot of the dedicated host with its LUKS volume and live scheduler. (c) The `host` field on the live `tls-health` rows. (d) The no-SSH hard-reset verb does not exist: a `host_silent` host has no automated next lever, tracked as #11484.

## Cost Impacts

None. No new vendor, tier or credential. The Hetzner reboot and the Doppler and Better Stack reads use existing accounts.

## NFR Impacts

None moved in the register. This improves the operability of key rotation (a defined, evidenced, recoverable path) and keeps NFR-026 (Encryption In-Transit) honest by refusing a rotation while the link is plaintext, but changes no NFR status.

## Principle Alignment

- AP-001 (Terraform-only infrastructure provisioning): Aligned. The key material, the app-copy derivation and both phases are Terraform; the reboot is a control-plane API call because the hcloud provider has no reboot action (precedent: the reboot step of `inngest-provision-rehearsal.yml`).
- AP-008 (Doppler for all secrets management): Aligned. No value leaves Doppler or Terraform state except through a pipe into a hash; no value is printed.

## Related decisions

- **ADR-100** (dedicated single-host control plane). Decision 4 and its 2026-07-24 amendment make the keys a shared channel credential; the 2026-10-27 addendum there records that the app copy is now derived, not copied.
- **ADR-294** (link TLS terminator and flagged flip). Its flag is the route's precondition and its `off` path is what the rollback guard protects. A one-line pointer to this ADR sits in ADR-294.
- **ADR-241** (infra credential tiers). The apply jobs run under `infra-privileged` through the tiered loader; the guard uses the read-only Hetzner key.
- **ADR-280** (bearer-curl). The Hetzner and Better Stack calls reuse its helper discipline.
