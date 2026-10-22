---
title: The Inngest send path gets TLS from a host-local stunnel terminator, a Terraform-minted pinned certificate in Doppler, and a Doppler-flagged data-driven flip
status: adopting
date: 2026-10-18
amends: none
supersedes: none
issue: 10136
related: [10136, 10205, 10382, 10405, 10479, 9139]
related_adrs: [ADR-100, ADR-140, ADR-118, ADR-241]
brand_survival_threshold: single-user incident
---

# ADR-294: The Inngest send path gets TLS from a host-local stunnel terminator, a Terraform-minted pinned certificate in Doppler, and a Doppler-flagged data-driven flip

## Status

**Adopting — 2026-10-18 (#10136).** The decision is true of the **template and the pipeline** at merge, not of production. Merging is inert for running traffic: the resolver's default output is still `http://10.0.1.40:8288`, the new Terraform resources are unreferenced by any running process, and the Inngest host is not replaced by the merge apply (`hcloud_server.inngest` is not in the per-merge `-target` list). The decision becomes true in production through three owner-gated acts, in this order: the single `inngest-host-replace` dispatch (due 2026-11-05), the flag write through `inngest-link-flip.yml` behind a canary, and a 48 hour soak.

The status flips to `accepted` in the later ledger-and-legal-wording PR, on two pieces of evidence: the handshake evidence (a verified request succeeds, the same request without the pinned CA fails with a certificate-verification error) and `scripts/followthroughs/inngest-tls-soak-10136.sh` exiting 0 (a gap-free `tls-health` series for 48 hours on one boot, the `legacy_8288` packet delta exactly zero, and the `tls_8443` delta at least 90 percent of the expected probe cadence). Until then no published document and no ledger value claims TLS on this link.

This ADR covers **leg 1 only** of the three legs the legal ruling names (the app-to-Inngest send path on `:8288`). Leg 2 (the Inngest server polling the app's `sdk_url` over plain HTTP) is a dated disposition to 2026-12-10, tracked as #10538. Leg 3 (step calls through Cloudflare, with the Cloudflare-to-origin hop plain for `app.soleur.ai`, whose host rule sets SSL mode `flexible`; the Addendum below records what the repository does and does not show about the zone default) is blocked on #10479. Neither is solved here, and #10136 does not close with this PR.

## Context

The web-platform app talks to the dedicated Inngest host (`10.0.1.40`, ADR-100) over plain HTTP on the Hetzner private network. ADR-100's 2026-09-15 addendum recorded that as a conscious acceptance: "transport confidentiality on this link is accepted, not provided" (encryption-posture ledger row, exception tracked on #6897 and then #10136). That hop carries `INNGEST_EVENT_KEY` (in the `/e/<key>` path), the hashed signing key as a Bearer on run-list reads, and event payloads: user prompts and agent output. Any peer on `10.0.1.0/24` can read it.

The CTO and CLO rulings of 2026-10-18 on #10136 require TLS with certificate verification on this hop, live by 2026-11-12 (fallback 2026-11-19, CLO hard stop 2026-12-10). The owner go is recorded: build the PR, one Inngest host replace by 2026-11-05, and `INNGEST_SIGNING_KEY` rotation. ADR-140 makes encryption posture a design-time default enforced by a resolvable-evidence ledger, so a fix that cannot be evidenced at runtime does not count as one.

Constraints that shaped the decision, each verified against the code and not assumed:

- **Inngest v1.45.1 has no TLS flag.** `cmd/start/cmd.go` at that tag contains no `tls`, `ssl` or `cert` strings; the listener is plain HTTP and binds `--host 0.0.0.0`. A terminator has to sit in front of it.
- **The host has no inbound path and its code is replace-only** (ADR-100, addendum 2026-08-25). Every change to the template reaches the host only through a replace, which makes the scheduler unavailable for a bounded window and, while `INNGEST_CUTOVER_FLIP=done`, needs a human-approved `cutover-inngest.yml -f op=resume` afterwards.
- **`user_data` is nearly full.** Measured 2026-10-18 before this PR: 30,916 B stored against the 32,768 B Hetzner cap (headroom 1,852 B), and the repo test budget leaves 1,384 B. Hetzner rejects an oversize `user_data` at replace time, which strands the host (2026-09-08).
- **The merge queue forbids sync pushes**, so a second PR that flips a URL constant cannot follow the first without breaking the "one PR" requirement.
- **`tls_self_signed_cert` computes its validity window at apply time**, so a committed PEM cannot exist before the first apply, and a committed generator would pass the private key through an agent session.
- **Container egress on the web hosts is default-drop**; only `10.0.1.40:8288` is allowed today, so `:8443` would be silently dropped without a new accept.

## Considered Options

- **Option A: `stunnel4` terminator on the Inngest host, cert minted by Terraform and delivered through Doppler, CA as a host file mounted into the containers, URL chosen per deploy by a Doppler flag (chosen).** Smallest config, one apt package, no per-connection fork, and the lowest `user_data` cost. Flip and rollback need a Doppler write and a redeploy, never a code merge.
- **Option B: nginx stream, socat or caddy as the terminator.** Larger configuration or package surface for the same function; the byte budget favours stunnel. Rejected (CTO D1).
- **Option C: native TLS in Inngest.** Does not exist at v1.45.1. Rejected on the facts.
- **Option D: bake the CA into the app image.** Rollback would need an image rebuild, and the host-side probes need the file on disk anyway. Rejected.
- **Option E: a committed public certificate (the `proxy-tls.tf` precedent) or a committed generator script.** The certificate's validity is computed at apply, so a committed copy cannot exist before the first apply; a generator would pass the private key through an agent session. Rejected (CTO D2).
- **Option F: a code-line URL flip in a second PR.** Violates "one PR" under a no-sync-push merge queue. Rejected.
- **Option G: bind Inngest to `127.0.0.1` now.** Needs a bootstrap-image rebuild and a second replace. Deferred to the next unrelated replace, tracked as #10539.
- **Option H: a Terraform-managed flag versus a hand-run Doppler write.** The flag is a Terraform-managed secret (`doppler_secret.inngest_link_tls`, count-gated off, outside the per-merge `-target` list), changed only by a Tier-B `apply_target` job. No existing narrow Doppler write credential for `soleur/prd` exists, so a hand-run write would have needed a new token (CTO G1).

## Decision

Adopt Option A, with these properties:

1. **Terminator.** `stunnel4` in its own unit `soleur-inngest-tls.service`, accepting `10.0.1.40:8443` and connecting to `127.0.0.1:8288`, TLS 1.2 or higher. The unit is **not a dependency of `inngest-server`** and the scheduler never waits on it. The key and certificate are fetched at start from Doppler project `soleur-inngest`/`prd` into a tmpfs `RuntimeDirectory`; the unit carries no `EnvironmentFile=`, so the Doppler token never reaches the network-facing process.
2. **One certificate resource, three Doppler copies.** A Terraform `tls_private_key` and `tls_self_signed_cert` (ECDSA P-256, 10 years, `CA:FALSE`, SAN `IP:10.0.1.40` only, `prevent_destroy`) feed `INNGEST_TLS_KEY` and `INNGEST_TLS_CERT` in `soleur-inngest/prd` and `INNGEST_TLS_CA` (base64 of the certificate) in `soleur/prd`. Drift between the copies is structurally impossible; runtime verification (a handshake with `--cacert`, and the host's `tls-health` row carrying the served and Terraform certificate fingerprints) replaces a committed-copy check. No template variable of `inngest-host.tf` may reference these resources, so a certificate change can never force-replace the host.
3. **CA as a host file.** `ci-deploy.sh` installs the CA at `/mnt/data/inngest-link/inngest-ca.pem` **only when the flag resolves https** (`pending:<epoch>` or `1`). With the flag absent or a lapsed lease, `INNGEST_TLS_CA` is never read, validated or installed: the resolver only makes the docker bind source an empty placeholder file (created when missing; an empty directory or symlink is replaced at once; an already-empty file is left; a non-empty regular file, the pinned CA of an earlier https deploy, is left alone at resolve time because the previous https container is live through the canary and the cron drain and a restart of it re-mounts the path, and is reset to an empty placeholder atomically (new inode) only after the new production container started, for a verified scope; a failed reset is a `ca_reset_failed` warning, not a deploy failure), so a bad secret cannot fail a flag-off deploy. With https the order is: read the CA (the deploy's env snapshot, else Doppler with retries), **validate** it (at most 4 KiB, no private-key block, exactly one certificate block, parses, not expired, rejects `CA:TRUE` and a `Certificate Sign` key usage), prove the **candidate** with the host-side `curl --cacert` self-gate against the live listener, and only then install it (`mktemp` and `mv -fT`); a failed gate leaves the previous file untouched. Any of {CA read error, invalid CA, failed gate, failed install} fails the deploy. The same directory holds `inngest-link.env` and `last-scheme`. All three run sites bind-mount the file read-only at `/etc/soleur/inngest-ca.pem` inside the container and set `NODE_EXTRA_CA_CERTS`; `NODE_TLS_REJECT_UNAUTHORIZED` is pinned absent everywhere. The certificate becomes a trust anchor for all outbound TLS in the Node process, which is why a second certificate is refused and a `CA:TRUE` certificate is rejected. The host-side self-gate and the canary's CA-withheld negative control carry the SAN and purpose checks (the validator does not re-check them). The directory is under `/mnt/data` because `webhook.service` runs `User=deploy` under `ProtectSystem=strict` and `/mnt/data` is already in its `ReadWritePaths` and deploy-owned; `/etc/soleur` is root-owned and not writable, and widening the unit (CTO ruling 2026-10-18) would have needed changes to the unit, the installer pin and both host provisioners. `ci-deploy.sh` creates the directory, and cloud-init does the same with the empty bind-source file on a fresh host, so docker never creates a root-owned directory at the bind source.
4. **One chokepoint for the scheme.** `resolve_inngest_link` in `ci-deploy.sh` is the only place the Inngest base URL is chosen. The flag `INNGEST_LINK_TLS` is read from the `resolve_env_file` snapshot with the allowlist `^(1|pending:[0-9]{1,10})$` and a scope guard: the snapshot's `DOPPLER_PROJECT` and `DOPPLER_CONFIG` lines must be `soleur` and `prd` when present (present and wrong always fails; absent lines with the flag set fail closed; absent lines with the flag absent resolve http with a `scope_unverified` warning and record nothing, unless the host's `last-scheme` file says https, in which case they also fail closed, because a real `off` always has a verified scope). Absent resolves to `http://10.0.1.40:8288`; `1` resolves to `https://10.0.1.40:8443` and **fails closed**: with the flag on, a failed self-gate, an unreadable flag or an empty or invalid CA fails the deploy and the old container keeps serving, never a downgrade to http. `pending:<epoch>` is honoured only while `epoch <= now + 31 min` and inside a 30-minute lease; a lapsed lease resolves http by itself, while a future epoch beyond the 31-minute bound fails the deploy. A host remembers the scheme its last deploy actually started (`last-scheme`, written only after the production `docker run` succeeds), and https followed by http with a verified scope raises an `https_to_http` warning event at resolve time (it never fails the deploy; nothing routes it yet, #10556). The tuple gate (`lib/docker-run-tuple.py`) accepts exactly the resolver expansion for `INNGEST_BASE_URL`.
5. **Flip and rollback are data, not code.** `inngest-link-flip.yml` (`action=flip|off`) applies `pending:<epoch>`, dispatches the canary-then-prod release, verifies a five-check canary layer (an https URL in `docker inspect`, an in-container fetch of the handed URL, a real in-container `inngest.send` of a synthetic event no function listens on, a CA-withheld negative control, a non-empty registry over https) and only then applies `1`. Each flag change is the Tier-B `inngest_link_flag` job (it holds `DOPPLER_TOKEN_WRITE`). Step order: plan and gate the flag resource (the requested value is the plan's explicit `TF_VAR_inngest_link_tls`, empty for `off`), then, after the gate and immediately before the apply, record the **prior** state of the **source key** `INNGEST_LINK_TLS` in `soleur/prd_terraform` and write it (set and read back for `pending` and `1`; deleted, not swallowed, for `off`), apply the saved plan, verify the key matches the applied state, and on a failure or cancel restore the key to its prior state if the apply did not succeed (a cancel mid-apply can leave `prd` applied while the key is restored; `action=off` is the idempotent rollback). The key must exist because `prd_terraform` does not inherit a Terraform-written `prd` key created after the branch (measured 2026-10-19), so without it every untargeted plan would plan to destroy the live flag; writing it only after the gate keeps key and `prd` secret consistent for every earlier failure. `off` is **idempotent and convergent**: at most one delete (a zero-change plan is `already_absent`, in the apply run's step summary) and it always redeploys. The `pending:<epoch>` lease bounds how long a stuck `pending` can make NEW deploys resolve https; it does not touch a running container, whose `INNGEST_BASE_URL` is fixed at `docker run`. The revert step fires only after the first flag write and is best-effort. The redeploy is tracked by `track.sh`, which reads web-1 frames only, so web-2's swap and resolved scheme are not verifiable from CI; the closing line prints the Better Stack query for each host's `class=resolved` row. `infra-privileged` has no required reviewer, so the owner's dated go for a flag write is a process control.
6. **The legacy listener stays, counted.** `:8288` stays open for the soak. Two named nftables counters in `table inet soleur_inngest` (`legacy_8288`, a verdict-less counting rule before the unchanged accept; and `tls_8443`, the positive control) are read with `nft list counter` and shipped every 5 minutes as the `tls-health` stage through the allowlisted phone-home path. The `8288/8289` accept and drop lines stay byte-identical. Physically closing `:8288` rides the next unrelated host replace (tracked).
7. **Soak.** `scripts/followthroughs/inngest-tls-soak-10136.sh` is the single chokepoint that decides pass or fail over every row of the window; its anchor (T and the baseline row) is read from trusted-author comments, not from the script.

## Consequences

**Easier.** Confidentiality and authentication of the send path become measurable: the handshake evidence and the soak counters are queryable through `scripts/betterstack-query.sh` without SSH. Flip and rollback are one dispatch each and need no merge. The same mechanism (a pinned certificate delivered as a host file) is reusable for the `sdk_url` leg once the web hosts have a listener.

**Harder or accepted.**

- While the flag is on, **a broken gate blocks ordinary releases** (the resolver fails the deploy rather than downgrade). Rollback is `inngest-link-flip.yml` with `action=off` plus a redeploy. The runbook says so.
- **The TLS key is in the server's process environment.** `inngest-server`, `vector` and the heartbeat run under `doppler run --config` without `--only-secrets`, so `INNGEST_TLS_KEY` reaches their environments. The marginal exposure is small because a process that can read that environment already holds the signing and event keys. Follow-up: `--only-secrets` or a split config at the next image bake (CTO F2), tracked as #10541.
- **The certificate has no rotation cron.** Ten years, alert under 90 days. A re-mint forces a host replace (the key and certificate fetch) and a new web container (the CA file); the CA file holds **exactly one certificate**, so there is no overlap window and the sequence is `off`, publish the new certificate, replace the host, flip (the flip's own redeploy installs the new CA after the self-gate proves it).
- **The replace is a bounded disruption of the sole scheduler** and needs the human-approved `op=resume` while the cutover flag is `done`. A failed replace waits for a fresh owner go.
- **Events sent during the window can be lost or fail.** Several send paths are pre-existing weak points that this work makes more reachable (the Stripe `invoice.payment_failed` route swallows a send failure with its dedup row already claimed; the dashboard send archives the draft on a failed enqueue; the reminder arm returns 502 on a timeout). They are tracked as separate follow-ups (#10542 for the Stripe route, P1 and blocking the host-replace go; #10543 for the dashboard send) and one mapping is folded into this PR (timeouts and TLS causes map to the retryable 503 in `schedule-reminder`).
- **A sniffed `INNGEST_EVENT_KEY` stays valid after TLS.** TLS does not invalidate it; its rotation is a separate owner decision (due 2026-11-12), carried with the rotation apply route in #10540.
- **Residual plaintext remains** on leg 2 until the dated step (#10538) and on leg 3 until #10479.
- **A new web host starts its first container on the http literal** in `cloud-init.yml` until its first `ci-deploy` run resolves the flag, so a host created or replaced after the flip sends plaintext until that first deploy, and a new web host needs one deploy before `:8288` is ever closed.
- **The Inngest host's nft loader is not idempotent** (#10545): the unit must never be restarted on the host; a ruleset change is a host replace.
- **A `https_to_http` or `lease_expired` warning notifies nobody today**: no Sentry alert rule routes `op=inngest-link` (#10556). An intentional `off` is a warning event only, not a page.
- **A wedged `/mnt/data/inngest-link` (a non-empty directory or a root-owned path) has no no-SSH repair** (#10557).

## Cost Impacts

None. `stunnel4` is an apt package; the certificate, the three Doppler secrets and the flag add no paid service or tier change.

## NFR Impacts

Targets NFR-026 (Encryption In-Transit) for the Inngest leg. The register status is deliberately **not** changed here; it moves in the later ledger-and-legal-wording PR once the handshake and soak evidence exist. No impact on latency NFRs beyond one local TLS hop inside the private network.

## Principle Alignment

- AP-001 (Terraform-only infrastructure provisioning): Aligned. The certificate, the secrets, the flag and the host template are Terraform or cloud-init; the flip is a Tier-B `apply_target` job, not a hand-run write.
- AP-008 (Doppler for all secrets management): Aligned. Key and certificate travel only through Doppler; none is baked into `user_data` or committed.

## Related decisions

- **ADR-100** (dedicated single-host control plane). Its 2026-09-15 addendum recorded transport confidentiality on this link as "accepted, not provided". An addendum to ADR-100 points here: once the soak passes, this ADR supersedes that acceptance for the `:8288` send path only. ADR-100 stays `adopting` for its own reasons.
- **ADR-140** (encryption posture as a design-time default). The reason no ledger value or published wording changes in this PR: the posture is claimed only after resolvable evidence exists.
- **ADR-118** (a shared cert's SANs are the cluster roster). The precedent for Terraform-minted pinned certificates delivered through Doppler and pinned by the client. This certificate differs deliberately: one fixed SAN (`10.0.1.40`, no roster to track), and it is not count-gated, because ADR-118's gating existed to stop a proxy server from logging a silent fallback on mere presence of the material, and no process here reads it before the host replace.
- **ADR-241** (infra credential tiers). The flip job runs under `infra-privileged` and is added to the D8 census; it reuses the Tier-B write token bound to that environment to write the `prd_terraform` source key, and no new token is minted.

## Addendum (2026-10-19) - what the review changed, and what the repository does and does not show

The body above was brought in line with the code that shipped in this PR; the edits are these, so a reader of the 2026-10-18 text can
see what moved.

- **Flip actuator (Decision 5, Option H).** The 2026-10-18 ruling (G1) named a `prd_terraform` key as the flag's source of truth, and that
  is what ships. A mid-review draft dropped the key on the premise that `prd_terraform` inherits `prd`; the lead's names-only listing of
  2026-10-19 (170 names) falsified the premise for a Terraform-written key created after the branch: `REGISTRY_PUSH_ACCESS_TOKEN_ID`/`_SECRET`
  are in `prd` and absent from `prd_terraform` (also `tunnel.tf`, ADR-164, `scheduled-terraform-drift.yml`). So the source key is required and is written after the plan gate, just before the apply; otherwise every untargeted plan (drift detector,
  infra-validation, a full untargeted apply) plans a destroy of the live flag.
  The job plans with the value as an explicit `TF_VAR_inngest_link_tls`, so the gate is correct whichever way Doppler resolves, and a failed or cancelled apply restores the key to its prior state. `off` is
  idempotent and fails the job if the key survives the apply. The G1 phrase "the 30-minute lease is the real control" is superseded: the
  lease bounds only how long a stuck `pending` can make new deploys resolve https; the revert step and `action=off` are what move a running
  fleet back. Time budget: flip step 153 minutes, revert step 115, job 283 (the two plus 15 minutes of slack), redeploy ceiling 4800 s.
- **CA handling (Decision 3).** The CA is installed only for an https resolution and is validated, gated and then installed in that
  order; with the flag absent nothing about it is read, and a stale pinned CA is reset to an empty placeholder only after the new container started. The validator is the deny-list in Decision 3 (one certificate, not expired,
  no `CA:TRUE`, no `Certificate Sign`), not the 2026-10-18 "1-2 certificates, SAN exactly the IP, serverAuth only" form, and the path is
  `/mnt/data/inngest-link/`, not `/etc/soleur` (see the same-day addendum in `decision-challenges.md`).
- **Rotation (Consequences).** The earlier clause that the CA file "may hold two certificates" is removed: the validator refuses a second
  certificate, so there is no overlap window.
- **User-data headroom (Context).** The 1,852 B and 1,384 B figures in the Constraints list are the pre-PR measurements and stay as
  dated. The same script (`apps/web-platform/infra/inngest-userdata-budget.sh`) reports 32,420 B stored against the 32,768 B cap, a
  headroom of 348 B, for this branch on 2026-10-19. After the sibling Inngest-host changes landed on `main` (the nftables re-read
  emit and a pin bump), the merged tree measured 32,596 B (172 B) and the merge-time plan's size precondition failed in CI, because
  the CI render is larger than the offline one by an amount the offline script cannot see. Message prose was trimmed (no behaviour
  change) to 32,096 B stored, a headroom of 672 B offline on 2026-10-20.
- **Leg 3, the Cloudflare hop (Status).** The 2026-10-18 text said the Cloudflare-to-origin hop is plain "while the zone is `flexible`".
  The repository shows something narrower. `apps/web-platform/infra/seo-config-rules.tf` carries a rule with expression
  `(http.host eq "app.soleur.ai")` and `ssl = "flexible"`, and a comment in the same file records the zone default as strict, with
  `ssl = "full"` rules only for the two marketing hosts. So the plain hop is established for the `app.soleur.ai` host, which is the
  host #10479 names. The zone-level SSL mode is not set in Terraform (the `cloudflare_zone_settings_override` in `cloudflare-settings.tf` sets no `ssl`
  attribute) and was not read live; "the zone default is strict" rests on that comment.
- **Leg 2, what the `sdk_url` poll carries.** The CLO ruling's phrase "only an HMAC-signed request and public function metadata" is
  incomplete for the SDK this repository pins (`inngest` 3.54.2, `components/InngestCommHandler.js`). The in-band sync response
  (`inBandRegisterBody`) embeds an `inspection` object, and once the request signature validates in cloud mode it carries
  `event_key_hash` (a hash of `INNGEST_EVENT_KEY`), `signing_key_hash` (the first 12 characters of the hashed signing key) and the app id,
  environment and origins. These are key-derived values, not secrets in themselves, but the owner-signed leg-2 record (#10538) should
  list them. Not verified: which sync kind (in-band or out-of-band) Inngest server v1.45.1 sends on the `sdk_url` poll, and whether this
  deployment's SDK runs in the mode that fills `inspection`.
- **The owner's go is procedural.** `infra-privileged` has no required reviewer (ADR-241), so the dated go for a flag write is a process
  control; the typo-guard on `inngest-link-flip.yml` is not an authorization.
- **Filed follow-ups.** #10538 (`sdk_url` poll), #10539 (loopback bind), #10540 (key rotation apply route, including the event-key
  decision), #10541 (TLS key out of the server environment), #10542 (Stripe send swallow, P1, blocks the host-replace go), #10543
  (dashboard send), #10544 (`inngest-host-replace` confirm and id-pin), #10545 (nft loader idempotency), #10556 (Sentry alert rule for
  `op=inngest-link`), #10557 (no no-SSH repair for a wedged `/mnt/data/inngest-link`).

## Addendum (2026-10-22, #10783)

Authority for the two flag writes on `inngest-link-flip.yml` is split. The `flip` is an in-session per-command go (form (b)) only
because `delegation-verify.sh` denies `confirm=`, so no valid recorded Standing Delegation can cover it. `action=off` takes either
form, before A5 (the signing-key rotation): after A5 the new key would travel over plaintext `:8288` if the link were turned off, so
`action=off` after A5 is form (b) only. See "Production Envelope for the post-merge acts" in the Inngest server runbook. The dated go
quoted in the Consequences sentence "The owner's go is procedural" is superseded by the runbook's authority wording.

## Addendum (2026-10-22, the first flip attempt)

The first `flip` (workflow run 39817708732) failed at the canary's `inspect` check with `cause=none` on web-1. The revert (run 39817975968)
redeployed both hosts; that run's own verdict did not verify web-2's canary and swap or the scheme the running containers resolved, and both
hosts' `class=resolved ... state=http_default scheme=http` rows were read afterwards.

**What is established and what is not.** Reproduced locally (Docker 29.9, `docker-evidence.md`): `docker run` keeps an `--env-file` entry **and** a
`-e` entry for the same key, `docker inspect` lists both, and the `-e` value wins when the process starts. The canary requires exactly one
`INNGEST_BASE_URL=` and one `NODE_EXTRA_CA_CERTS=` line, so a Doppler snapshot that pins `INNGEST_BASE_URL` fails it exactly as observed. The
old check printed no counts (`cause=none`), so no production run has measured the line count, and the Doppler key set was never read: the pin is
the **most likely** cause, not an observed one. The first measurement is the next flip's `check=inspect cause=<token> url_lines= ...` row, and
the `-e`-wins behaviour was measured on one Docker version (the hosts' own is unknown). The mock docker reported the `-e` pairs only, so no
test could show the duplicate.

New invariant: **the `-e` flags are the only source of `INNGEST_BASE_URL` and `NODE_EXTRA_CA_CERTS` in the canary and prod containers.**
`ci-deploy.sh` scrubs both names from the env-file once per deploy (`inngest_link_scrub_env_file`, after the resolver, before the first
`docker run`). The `inspect` check stays strict and names its first failing condition
(`cause=inspect_failed|url_count|url_value|ca_count|ca_value` with four fixed counts) with its own deploy-state reason
`canary_inngest_link_inspect_failed`. A scrub fault aborts a strict (flag on) deploy with `inngest_env_scrub_failed` and is logged and continued
otherwise, so `action=off`, the flip's revert and any flag-off deploy are never blocked by it (with the flag on it blocks like a resolver fault).
Ruled by the CTO agent, 2026-10-22. Rejected alternatives: putting both names on `-e` for every variable (every Doppler secret would sit on the
docker argv); an `--env-file` allowlist (the prd key set is open-ended and owned by Doppler, so an allowlist silently drops new secrets);
de-duplicating at inspect time with last-wins (the proof would then depend on merge order and the Docker version, and a real duplicate would pass).
The scrub regex, `REQUIRED_ENV` in `lib/docker-run-tuple.py` and the two counts in `inngest_link_canary_check` name the same two variables; a
resolver-suite row pins that they agree.

Accepted residuals: the first-boot tuple in `cloud-init.yml` keeps its duplicate (no inspect check runs there; the next deploy replaces it), the
prod container is not inspected (the canary's proof transfers to it only for these two names, through the shared env-file), the image's own `ENV`
was not measured, a pinned `NODE_EXTRA_CA_CERTS` never reaches the scrub (the key overlay refuses it first), and the overlay's `grep` weakness
is tracked separately (#10855).
