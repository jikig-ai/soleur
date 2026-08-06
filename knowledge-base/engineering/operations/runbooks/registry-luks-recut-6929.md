# Runbook — `registry-luks-recut` (encrypt the zot store volume)

**What this does:** destroys the container registry's storage volume and rebuilds it encrypted.

**What you lose:** the store's entire contents, with **no cover while it is empty**. See
[The empty-store window](#the-empty-store-window).

> **Corrected 2026-08-04.** This line previously read *"nothing permanent… that volume is a mirror
> of images that also live in GHCR; it refills automatically. You do lose a window where deploys
> pull from GHCR instead."* **That is false and was the most dangerous sentence in this file** — it
> is the first thing a reader sees, and it told them the destroy was covered. GHCR stopped being
> readable on 2026-07-30 (#7071): the read PAT is revoked (401) and the minter is disabled (403
> DENIED). The images *are* still in GHCR and CI can still read them, but **no host can**, so
> nothing pulls from GHCR during the window. This runbook's ordering windows were accepted
> 2026-07-24, six days before that change, and nothing re-read it afterwards.

**Everything below runs from GitHub Actions. There is no SSH in this runbook.**

---

## What authorizes a recut

**In one sentence:** a recut is authorized only when CI has just proven, *by executing it*, that
every image reference production depends on can be re-materialised into an empty registry from
GHCR — a source that survives the destroy. The full reasoning, the three rejected candidates and
the per-predicate fail-open analysis are in
[ADR-169](../../architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md).

This **replaced** the previous condition rather than repairing it. The old gate authorized a
destroy on "GHCR covers the empty-store window"; #7071 retracted that premise (the host→GHCR read
PAT is revoked and the minter is disabled), and the operand that measured it went permanently dark.
Between 2026-07-30 and #7277 the gate refused unconditionally — it could not be fired at all,
including during the incident it exists to recover from.

### 🚧 The remaining blocker — this dispatch is still not necessarily fireable

**#7277 was necessary but is not sufficient** (and is now closed, by PR #7290). After the D10 gate
authorizes, the recut still runs `stock_preflight_gate`, and the registry server type must be
orderable **in this host's datacenter**, AND RE-MEASURED EVERY TIME — availability moves in both
directions on a days timescale (`cx23` in `hel1-dc2` changed direction twice across twelve days,
once inside 24 hours — series and sources at `zot-registry.tf`, anchor "STOCK REALITY"), so a
reading from a previous dispatch authorizes nothing. **The type this gate probes is `cpx22` as of
#7309 — probe THAT, not `cx23`.** Firing this dispatch is also what converts the repin from
declared to billing: +€14.00/mo (`expenses.md`, the `CPX22 (registry)` row). Measured 2026-08-05: `cx23` was orderable in `nbg1-dc3`
but **not** in `hel1-dc2`, where this host runs (#6460). A recut dispatched while that holds aborts
at the stock gate.

**Re-probe rather than trusting that date.** Stock moves without notice and a revert needs a
*second* successful create, so the reading that matters is the one taken immediately before firing.
Read `.server_types.available` (never `.supported` — the type stays supported while availability is
zero, which is the whole distinction); `apps/web-platform/infra/zot-registry.tf` carries the last
recorded probe and the command shape. The durable fix is #7309.

> ### ⚠️ Do NOT route around it with `registry-region-migrate`
>
> When the stock gate aborts, both the recut's abort text and older revisions of this runbook point
> onward to `registry-region-migrate`. **That dispatch has none of this one's guards**: no typed
> confirm token, no volume id-pin, no live posture probe, and **no D10 authorization gate at all**
> (ADR-096 accepted residual, #6946). It accepts a similar bare-create shape and will get the same
> destroy through unguarded.
>
> Deleting the old blocked-state banner removed what used to stop an operator at line 5, so this
> caveat is stated here deliberately: the banner's removal must not convert a hard stop into a
> signpost toward the unguarded path.

#### And check the `user_data` budget FIRST — this one fails *after* the destroy

The stock gate above is the survivable blocker: it aborts before anything is destroyed. The
`user_data` size cap is **not**. Hetzner rejects a server CREATE whose stored `user_data` exceeds
**32,768 B**, and the recut's create runs *after* its destroy — so an over-cap config strands the
sole pull path with the store already gone.

Run this before dispatching. It needs no credentials and touches nothing, but it **does need
`terraform` on `PATH`** — it measures with terraform's own `templatefile`/`base64gzip`, which is
the method Hetzner measures by (never `gzip -9`, which overstates headroom), and since PR #7300
(merged 2026-08-06) it renders the same `replace(..., local.registry_rationale_strip, "")`
expression `hcloud_server.registry` renders. Both halves matter; see the caution below for what
happened when only the first was true.

```bash
bash apps/web-platform/infra/registry-userdata-budget.sh; echo "exit=$?"
```

Read the **verdict**, not a remembered number. Re-run it; do not trust a figure quoted here or in
an issue, because the payload changes with every `cloud-init-registry.yml` or pin edit.

| Exit | Meaning | Action |
|---|---|---|
| `0` | Under cap | Precondition clear — **provided the run actually measured**; see the SKIP trap below. |
| `1` | Over cap | **Do not dispatch.** Read the `CAUSE:` line the gate prints — it distinguishes a broken strip regex from real payload growth, and they need different fixes. |
| `2` | Unmeasurable, or the render failed a sanity assertion | **Do not dispatch.** Unmeasured. |

`headroom` must be **> 0**, strictly. The gate fails at `stored_bytes -ge cap`, so a headroom of
exactly `0` is a FAILURE — an earlier revision of this section said `≥ 0`.

> **The SKIP trap — the one way this check lies to you.** With `terraform` absent the script prints
> `SKIP — terraform not on PATH` and **exits `0`**. Exit `0` is also what "under cap" looks like, so
> a shell without terraform produces a *clear* precondition having measured nothing at all. Read the
> output, never just `$?`. If you see `SKIP`, the precondition is **UNMEASURED, not cleared** —
> install terraform and re-run before dispatching anything destructive.

> **A superseded measurement, kept as a caution.** This section used to read *"Measured 2026-08-05
> on `main`: 36,404 B stored, −3,636 B headroom — OVER CAP"*, and told the operator that #7299 would
> fix it by extending `registry_rationale_strip`. Both were wrong: the strip
> was **already applied** — the gate was rendering `templatefile(...)` bare, so it measured a payload
> terraform never produces. Re-measured against the real expression the same tree stores roughly
> **9.4 kB, with ~23 kB of headroom**. Deliberately imprecise — `base64gzip` is Go's `compress/gzip`,
> so the exact byte count is terraform-build-dependent (9,404 B and 9,408 B were both measured, on
> different builds, during this change). A figure quoted to the byte is what this section is trying
> to stop being.
>
> **The gate itself was fixed by PR #7300 (merged 2026-08-06).** It now extracts the strip from
> `zot-registry.tf`, applies it, prints an `after strip` figure, and fails closed on a strip it
> cannot parse. So the discriminator that used to be needed here is gone — the numbers above are
> history, not a live caveat.
>
> That is why this section quotes a command and a verdict shape instead of a byte count: the
> hard-coded figure is what told operators the recut "must not be dispatched at all" for days.

This check is deliberately **not** a D10 predicate: D10 authorizes on the *pull path* being
re-materialisable, and a property of the host the destroy replaces cannot gate that destroy without
violating the independence criterion (ADR-169). It is a dispatch precondition, and it lives here.

### What the gate now checks

| | Predicate | On failure |
|---|---|---|
| **A0** | Inventory derived from production's own `/health` version + `build_sha` and committed pins, with zero reads of zot | ABORT |
| **A1** | Every required pin resolves at GHCR | ABORT, classified |
| **A2** | **The restore is rehearsed into a throwaway registry and blob-verified** — this is the pass condition | ABORT |
| **A3** | Non-vacuity floor: the required set is fully resolved | ABORT |
| **A4** | Sink credential graded live at the Cloudflare Access edge | ABORT only on a **measured** dead count |

**Nothing in this gate observes production zot before destroying it, and that is deliberate.** A
draft carried a live write probe ("A5") against prod zot. It was removed by architecture ruling
(ADR-169) because its only distinctive abort arm — an htpasswd credential rejection — fires on a
divergence the recut itself repairs: `/etc/zot/htpasswd` is baked at boot from Doppler, and the
recut replaces the host, re-baking it from the same value in the same apply. A5 would have blocked
the recovery on the condition the recovery cures, and sent you to "rotate `ZOT_PUSH_*`" when the
remedy was the dispatch you were already running.

What still covers each half: the **Cloudflare Access edge** credential survives the destroy and is
graded pre-destroy by A4, which ABORTS on a measured dead count. The **htpasswd** credential does
not survive the destroy, and is exercised post-destroy by `registry_store_restore` against the host
it actually applies to — with a non-retryable exit `5` that names rotation as the remedy (see the
restore exit-code table below).

---

## Before the FIRST-EVER fire: cold-vehicle re-verification (REQUIRED)

This dispatch shipped with **zero live executions**. Its guard *logic* is well covered by tests,
but its *live* surfaces have never run against production. Since #7277 those surfaces are: two
Hetzner API probes, one Better Stack read, **GHCR-read-from-a-runner under `packages: read`**, the
**throwaway-zot rehearsal**, the **`/health` parse**, and — highest-stakes of all, because it runs
*after* the irreversible step — the **post-destroy real restore over the CF Tunnel**. (The Sentry
query that used to be listed here no longer exists.) They would otherwise first execute at the single highest-stakes
moment: an irreversible destroy of the store.

So the five checks below are **required before the first fire**, not advisory. If any fails, fix it
and re-verify. **Do not proceed with a degraded gate** — a gate that cannot fail is worse than no
gate, because it gets read as evidence.

1. **The D10 gate can go BOTH red and green.** The suite leads with the green row — the
   criterion whose absence let an unpassable gate ship — and carries one positive control per
   abort class:
   ```bash
   bash tests/scripts/test-registry-pull-path-health.sh
   bash tests/scripts/test-registry-restore-from-ghcr.sh
   ```
   No Doppler wrapper and no `SENTRY_AUTH_TOKEN`: **the gate no longer reads Sentry at all.** The
   previous version of this check ran the suite under `doppler run -c prd_terraform` and named a
   rotated `SENTRY_AUTH_TOKEN` as the failure mode; both stopped describing the gate at #7277.

   **Also check the gate's LIVE INPUT, not only its logic.** The suites above are hermetic — they
   would stay green against a workflow wired to a source that does not exist, which is exactly
   what shipped. Run the derivation itself and confirm it yields a bare base domain whose
   `/health` answers:
   ```bash
   bash scripts/derive-app-domain-base.sh            # expect: soleur.ai (stdout), resolution line on stderr
   bash scripts/derive-app-domain-base.test.sh       # the derivation's own unit suite
   bash tests/scripts/test-registry-d10-workflow-wiring.sh   # proves the workflow USES it
   curl -s -o /dev/null -w '%{http_code}\n' "https://app.$(bash scripts/derive-app-domain-base.sh)/health"
   ```
   The `curl` must print `200`, and it must be built from the script's own output rather than a
   typed domain — a hand-typed URL tests your typing, not the gate's input.

   **Assert no Terraform override is in play.** The derivation honours `TF_VAR_app_domain_base`
   ahead of the committed default, mirroring Terraform's own precedence. Absent an override the
   committed `variables.tf` value IS what Terraform applied; if one appears, that is the value
   production runs on and the base changes with it:
   ```bash
   [[ -z "${TF_VAR_app_domain_base:-}" ]] && echo "no exported override"   # tier 1 reads the PROCESS ENV
   doppler secrets -p soleur -c prd_terraform --only-names | grep -c APP_DOMAIN_BASE || true   # expect 0
   ```
   The first line is the one that matches this step's heading: the derivation's override tier
   reads `TF_VAR_app_domain_base` from the environment, so a Doppler check alone would pass
   while an exported override silently drove the `curl` above it. Measured 2026-08-06: no
   export, and `APP_DOMAIN_BASE` absent from **all 13** configs. The secret the old gate read
   never existed anywhere.

   **Also assert the host variable has not drifted.** `app_domain` and `app_domain_base` are
   INDEPENDENT Terraform variables, and `app_domain` is the one with a live lever — `APP_DOMAIN`
   IS present in `prd_terraform` (`app.soleur.ai`), so `TF_VAR_app_domain` is injected on every
   apply. A domain move performed the only way it can be performed today would shift production
   while the gate kept measuring the old host:
   ```bash
   doppler secrets get APP_DOMAIN -p soleur -c prd_terraform --plain   # expect app.<derived base>
   ```
   The derivation aborts on a *committed* divergence by itself; this covers the live-override
   half, which it deliberately cannot see (reading Doppler is what this change removed from the
   gate).

2. **Both Hetzner probes return the shape the gate parses.**
   ```bash
   HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)
   curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
     'https://api.hetzner.cloud/v1/volumes?name=soleur-registry-store' | jq '.volumes[0].id'
   curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $HCLOUD_TOKEN" \
     'https://api.hetzner.cloud/v1/servers?name=soleur-registry'
   ```
   An API change here makes the id-pin's provenance step fail *after* you have already typed the
   confirm token.

3. **The heartbeat is still where the poller looks, with the timings it assumes.** Confirm
   `betteruptime_heartbeat.registry_prd` exists in state and that `zot-registry.tf` still declares
   `period = 60` / `grace = 30`. The poller's residual window is derived from those numbers.

4. **Re-read the ordering-window records** in the ADR-096 amendment against the current
   `zot-registry.tf` and `cloud-init-registry.yml`. They were accepted as of 2026-07-24; if either
   file changed since, the accepted windows may no longer be the real ones.

5. **Schedule the fire immediately before a planned release** — see
   [The empty-store window](#the-empty-store-window).

---

## Do NOT use `registry-host-replace` for this

`registry-host-replace` **keeps** the storage volume. The volume is currently unencrypted, and the
new boot code refuses to mount an unencrypted volume — by design, so it can never silently wipe
your data. The result is that the registry **goes dark** and stays dark.

The same happens if a hand-rolled `terraform apply -replace` misses the volume.

`registry-luks-recut` exists so that cannot happen: it supplies all three `-replace` targets itself,
as one atomic apply.

> **After a successful recut this reverses.** The volume is then encrypted, so
> `registry-host-replace` becomes the *correct* tool for an ordinary boot problem. The warning above
> applies only while the volume is still unencrypted.
>
> **Until then, `registry-host-replace` is blocked too** (verified 2026-08-04,
> [run 30926215332](https://github.com/jikig-ai/soleur/actions/runs/30926215332)): the #6929 LUKS
> resources are declared but absent from Terraform state, so a replace pulls them in and its
> destroy-guard aborts with `out_of_scope=2`. **Both** levers are currently unavailable — see
> #7278 for the missing in-place restart lever, which is usually what you actually wanted.

---

## Step 1 — Get the volume id

One command. (Do **not** look for this in a drift run's logs — it is not there. The drift workflow
captures its plan into a variable, so the `Refreshing state... [id=...]` line never reaches the log.)

```bash
HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)
curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
  'https://api.hetzner.cloud/v1/volumes?name=soleur-registry-store' | jq -r '.volumes[0].id'
```

## Step 2 — Fire it

```bash
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=registry-luks-recut \
  -f confirm=RECUT-REGISTRY-LUKS \
  -f expected_registry_store_volume_id=<the id from Step 1> \
  -f reason='encrypt the zot store volume (#6929)'
```

The id you pass is a **safety pin**: the job refuses to run if that address turns out to point at a
different physical volume than the one you named.

---

## If it stops: what each failure means and what to do

The job prints a line of counters before it decides. Find your case here.

| What you see | What it means | What to do |
|---|---|---|
| `requires confirm=RECUT-REGISTRY-LUKS` | Typo, or you used the *workspaces* recut token. | Re-fire with the right token. Nothing happened. |
| `requires expected_registry_store_volume_id` | The id was missing or not a plain number. | Re-run Step 1 and re-fire. Nothing happened. |
| `registry-pull-path-health: A0 ABORT` | Could not derive the restore inventory: `/health` unreachable, unparseable, or missing `version`/`build_sha`. | **Nothing was destroyed.** This names the HTTP read, which is the only thing A0 measures. `/health` is served by already-running containers and survives a zot outage, so it is not a zot symptom — check that `app.<domain>/health` answers. Do **not** go looking for `APP_DOMAIN_BASE` in Doppler: it is not there, in any config, and was never the source. A base-domain problem surfaces as the separate `derive-app-domain-base` error below, not as A0. |
| `::error::derive-app-domain-base[D10-PREPARE]: …` or `[D10-VERDICT]` | The base domain could not be derived from `apps/web-platform/infra/variables.tf` — the file is missing, `variable "app_domain_base"` has no readable `default =`, or the value is malformed (a scheme, a slash, whitespace, no dot, or an `app.` prefix). | **Nothing was destroyed** — the bracketed phase says so. The message names the file and the variable. This is a committed-config problem, not a credential one: no token to rotate, no secret to set. |
| `::error::derive-app-domain-base[registry-bridge]: …` | Same derivation, but from the **refill leg** (`registry_store_restore`), which runs AFTER the destroy. | **The store is already gone.** Do NOT read this as a pre-destroy abort — go to the restore-failure rows below, not the ones above. The same marker also appears in `reusable-release.yml` and the two inngest image builds, which have nothing to do with a recut. |
| `registry-pull-path-health: A1 ABORT` | A required image could not be resolved at GHCR. The message carries the classified cause. | **Nothing was destroyed.** On `NOTFOUND`, note the wording: GHCR returns the same error for *absent* and *not visible to this credential*, so check the job's `packages: read` permission before concluding a tag was deleted. |
| `registry-pull-path-health: A2 ABORT` | The **rehearsed restore failed**, so the pass condition was never established. The message names the restore engine's exit code. | **Nothing was destroyed.** Map the code with the restore table below — the rehearsal exercises the same engine the real restore uses. |
| `registry-pull-path-health: A3 ABORT` | The inventory came in below its declared floor — fewer required images resolved than production depends on. | **Nothing was destroyed.** This is the anti-vacuity guard; the message names which pin was missed. Do not lower the floor to get past it. |
| `registry-pull-path-health: A4 ABORT` | The registry-push Cloudflare Access token is **measured dead**. | **Nothing was destroyed.** This is the one arm where rotation genuinely is the remedy. Rotate the CF Access service token, then re-fire. `unverifiable`/`unmeasured` do **not** abort and are not accusations — do not rotate on those. |
| `volume_provisioned=0` | The plan would **keep** the volume — the exact footgun above. | Do not force it. Re-fire this dispatch (it supplies the `-replace` flags). If it repeats, the resource is missing from state — reconcile before retrying. |
| `volume_id_mismatch=1` | The address points at a **different** volume than you authorized. | **Stop.** Do not re-fire with a different id until you know why state disagrees with reality. |
| `luks_key_touched=1` | The encryption key is not in the isolated Doppler config yet, so Terraform wants to create it. | Run the operator's untargeted apply (the `OPERATOR_APPLIED_EXCLUSIONS` contract) so the key lands, then re-fire. |
| `logs_secret_destroyed=1` | The plan would delete the logging token; the rebuilt host would fail to start without it. | Reconcile the plan. Do not proceed. |
| `out_of_scope=1` (or more) | The plan touches something outside the registry. | **Never widen the allow-set.** This is the only thing protecting the web host and the sole copy of `/mnt/data`. Reconcile the plan. |
| `stock-preflight ABORTED` | Hetzner has no capacity for the replacement host right now. | **Nothing was destroyed.** Wait and re-fire. If the type is unavailable in this datacenter generally (#6460), see the caveat in [What authorizes a recut](#what-authorizes-a-recut) **before** reaching for `registry-region-migrate` — that dispatch has no confirm token, no id-pin, no posture probe and no D10 gate (#6946). |
| `probe` / `did not report the pinned volume absent` | The job saw a "resume" shaped plan but the volume still exists. | This is a state problem, not a recut. Reconcile with `terraform import` — never let it `create`. |

### If the apply itself fails partway

Re-fire the **same** command, with the **same** confirm token and the **same** id. The job detects a
part-finished recut on its own (it checks Hetzner directly to confirm the old volume is really gone)
and resumes. There is no special flag.

### If it finishes but the registry never comes back

The job waits for the rebuilt registry to check in and fails loudly if it does not. Three causes,
and they need different fixes:

- **The restore failed after the store was destroyed.** *This is the highest-stakes failure mode in
  the design, and it was missing from this list before #7277.* The host may be perfectly healthy
  while the store is empty or partial — a partial store is **worse than an empty one**, because tag
  lookups succeed for some refs and fail for others, so the symptom presents as a confusing
  per-image outage rather than an obvious total one. Look at the `registry_store_restore` job, map
  its exit code in the table below, then **re-run that job** (the engine is resumable).

- **It refused the volume.** Recoverable — *after a successful recut* the volume is encrypted, so
  `registry-host-replace` is the right tool for this. (It is **not** available before one: while
  the volume is still plaintext, that dispatch aborts `out_of_scope=2` — see the callout above.)
- **The disk was never attached in time** (`reason=device-absent`). This one **never self-heals**;
  it needs a full recut.

Tell them apart with:

```bash
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK
```

#### Restore exit codes — one operator action each

`scripts/registry-restore-from-ghcr.sh` enumerates every failure it can have. Six codes consumed
as a single boolean would be a contract nobody can act on, so each maps to exactly one action.
The **rehearsal** (D10 A2) runs the same engine, so the same table reads both.

| Code | Meaning | What to do |
|---|---|---|
| `0` | Every required reference restored **and** blob-verified, signature present. | Nothing. The window is closed. |
| `2` | **Source unavailable** — GHCR could not be read. | Nothing was written. Check the job's `packages: read` permission and GHCR status. **Not** proof the images were deleted: GHCR returns the same error for *absent* and *not visible to this credential*. |
| `3` | **Sink unavailable** — the registry did not accept the write. **Retryable**, and the job already retries it: a replaced host can outrun the Cloudflare Tunnel's re-convergence. | If it exhausted its retries, confirm the registry host is serving, then re-run the job. |
| `4` | **Verification failed** — a digest mismatched, a blob is missing, or a signature is absent. | **Do not deploy.** The store contents are not trustworthy. Re-run the job and read the per-entry lines; a repeat means the copy is landing wrong, not that it was interrupted. |
| `5` | **Credential unusable** — absent, empty, or **rejected** by the sink. **Not** retryable. | Retrying only burns the window. **Do NOT start by rotating anything** — see "If the sink rejects the credential" immediately below. |
| `6` | **Could not classify** — a failure shape the engine does not recognise. | Read the crane stderr in the per-entry line before acting. Do **not** assume the images are absent. Worth filing alongside the recovery: an unenumerated failure is itself a defect. |

### If the sink rejects the credential (exit `5`, or a bridge `docker login` failure)

**Read this before touching Doppler.** The obvious move — rotate `ZOT_PUSH_*` — is the one that can
make this permanent. `/etc/zot/htpasswd` is baked **once, at boot**, from the Doppler tokens
(`cloud-init-registry.yml` §2g). A rotation therefore leaves the running host authenticating
against a value no client still presents: it converts a possibly-transient rejection into a
guaranteed one, until the host is replaced again. Hand-editing Doppler does **not** re-bake a
running host — and note the exit-5 message names `soleur/prd` while the host bakes from the
isolated `soleur-registry/prd`.

**This also covers a bridge failure, which is the more likely way you meet this.** The
`cf-tunnel-registry-bridge` step runs BEFORE the restore engine and its `docker login` is the first
thing that authenticates against the rebuilt htpasswd — so an htpasswd divergence usually surfaces
there, as a fail-closed bridge error, not as exit 5. That error deliberately says a
`websocket: bad handshake` does **not** by itself distinguish an edge refusal from an origin that
is down or restarting. It is telling you the truth: do not guess. Measure.

**Measure first — no SSH required.** The host reports the divergence itself:

```bash
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK
```

Read `htpasswd_push_matches` on the most recent line:

| value | what it means | what to do |
|---|---|---|
| `true` | The host agrees with Doppler. The rejection is **not** an htpasswd divergence. | **Do not rotate.** Treat it as an edge/availability fault: confirm the registry host is serving, then re-run the restore job (it is resumable). |
| `false` | The bake has diverged from Doppler. | The remedy is a **re-bake, not a rotation**: dispatch `registry-host-replace`. It re-runs the registry cloud-init and **preserves the store volume**, so it costs nothing you have already restored. Then re-run the restore job. |
| `unknown`, or no line at all | The host is not reporting. `unknown` is the DEFAULT here, deliberately — "cannot tell" is never conflated with "does not match". | **Do not rotate on an unmeasured signal.** Establish why the heartbeat is silent first. |

A rotation is correct **only** as a Terraform-mediated change followed by a host replace, so that
the new value and the bake move together. That is a deliberate operation, never a first response to
a red job.

---

## The empty-store window

After the destroy the store is **empty**, and the chained `registry_store_restore` job refills it
automatically in the same run. The window is now **bounded by that job** rather than by the next
release.

> **Corrected 2026-08-04, superseded 2026-08-05 (#7277).** This section once read *"Deploys still
> work — they pull from GHCR."* They do not: since #7071 the host→GHCR edge is dead (read PAT 401,
> minter 403 DENIED), and `model.c4` calls it a DEAD EDGE where *"every traversal ends
> `image_pull_failed`"*. That correction still holds — what changed is that the window now has an
> automatic, fail-loud ending.

What the window costs while it is open:

- **Nothing can pull.** Any host reboot, replacement or new deploy has no registry to pull from.
  There is still no second source; the restore is CI-mediated, not a mirror.
- **Already-running containers keep serving**, so there is no *immediate* user-facing outage. Do
  not over-read that: the fleet is **one restart away** from one — an OOM kill, a Hetzner host
  event, a Docker daemon restart or a kernel update during the window turns it into a hard outage.
- **The window is SILENT.** It is not marked by a `ghcr-fallback` alert: that signal fires only
  inside the *success* branch of a GHCR pull, so with GHCR unreadable it cannot fire at all.
  **Absence of alerts during this window is not evidence of health.** Watch the
  `registry_store_restore` job instead — that is the signal.
- **Rollback narrows.** The restore carries only the **required** pin set, so immediately
  afterwards there is no older image in the store to roll back to, even though `ci-deploy.sh`
  treats rollback to an older image as a supported path. Re-run the restore with a wider set if
  you need one. Nothing goes red for this — it degrades on the *success* path.

**How long is it open?** Not measured. The per-pass wall-clock for the full pin set on a
GitHub-hosted runner is an open residual (ADR-169), so the bound is *structural* — an explicit job
timeout plus a resumable engine — not numeric. Do not quote a duration that nobody measured.

### If the restore job fails

Read its `::error::`; it names one operator action per exit code (table above). Then **re-run that
job**. The engine is resumable by contract: a second pass over an already-restored target is a
clean no-op, so a partial or timed-out restore is recovered by re-running rather than by repairing
state.

> **Do NOT reach for `gh workflow run web-platform-release.yml -f bump_type=patch`.** Older
> revisions of this runbook and of the dispatch summary told you to end the window that way. That
> pipeline was measured failing **nine consecutive times** as of 2026-08-05 — its zot-push half is
> precisely what the recut exists to repair — so it is not a working exit.

**Scheduling:** firing immediately before a planned release is still sensible, but it is now a
preference rather than the load-bearing mitigation it used to be.

---

## After it succeeds

The run summary prints the **new volume id**. Record it — any future recut needs it as the safety
pin, and re-deriving it means going back to Step 1.

---

## Related

**Unblocking this runbook:**

- ~~**#7277**~~ — the D10 gate has no valid PASS condition. **CLOSED by PR #7290**, which is this
  runbook's current merge base. It was necessary but never sufficient: the recut also runs a
  stock-preflight gate, and the stock blocker below has since been CLEARED by the #7309 repin.
- **#7309** — RESOLVED 2026-08-06. `var.registry_server_type` now defaults to `cpx22`.
  The issue's premise (`cx23` unorderable in `hel1-dc2`) was measured FALSE on 2026-08-06; what
  justified the repin is that `cx23` availability there changed direction twice across twelve
  days, once inside 24 hours, while `cpx22`
  held at every probe. The original text, for the record only — none of it is current:
  > `var.registry_server_type` defaults to `cx23`, which is unorderable in `hel1-dc2`,
  > the datacenter this host runs in. Repinning to `cpx22` is the only walkable lever past it
  > (Hetzner inventory is not closable by any issue), and it carries a **+€14.00/mo** cost decision.
  > This is the live blocker.

  (That last sentence had lost its `>` prefix, so it read as a current claim two lines below
  `RESOLVED` — restored into the quote rather than deleted, since the original text is a dated
  record.)

## Addendum — 2026-08-06: two further blockers, both since cleared

Neither was listed above when this runbook said the stock gate was the remaining blocker. Both
were found by verifying preconditions rather than reading them.

- **The D10 gate read a secret that does not exist.** Both arms read `APP_DOMAIN_BASE` from
  Doppler `soleur/prd` with no fallback and failed closed on empty. It is absent from **all 13**
  configs of the `soleur` project. The dispatch therefore aborted at D10 PREPARE *before* it
  could reach its own destroy-guard — unfireable during exactly the incident it exists to
  recover from. Fixed by deriving the base from `apps/web-platform/infra/variables.tf`, the
  causal source (`server.tf` sets the host env var from it).
- **`REGISTRY_LUKS_KEY` was absent from `soleur-registry/prd`.** The #6929 LUKS resources were
  declared in code but never applied, so the destroy-guard aborted with `luks_key_touched=2`.
  **Cleared 2026-08-06** by a targeted apply of `doppler_secret.registry_luks_key` (2 to add, 0
  to change, 0 to destroy — `random_password.registry_luks` came in via the dependency edge).
  Re-planned against live state afterwards, the guard returns **PASS**:
  `out_of_scope=0 logs_secret_destroyed=0 luks_key_touched=0 volume_id_mismatch=0
  server_provisioned=1 volume_provisioned=1 attachment_created=1 nic_created=1 firewall_ok=1`.

Store volume id at that measurement: **106286457** (`volume_id_mismatch=0` confirms the pin).

### The recut is not the only instrument — do not read a fixed gate as an endorsement

This dispatch was built for **encryption-at-rest**, not disk pressure. It is being reached for
because `/var/lib/zot` is full, and that is a different problem from the one it was designed to
solve. Two measurements bear on the choice:

- The store's manifest-referenced content is **~14.78 GB** against ~56 GB used — roughly **41 GB
  unaccounted** (measured by the read-only disk-inventory lever, PR #7343; an incomplete sweep,
  so that is a lower bound). The retained keep-set is therefore *not* what filled the volume.
- GC completes for `soleur-inngest-bootstrap` but **never once** for `soleur-web-platform` in a
  6-hour window, while zot panics in `pkg/scheduler/scheduler.go`. The unaccounted bytes are
  reclaimable garbage that GC cannot finish reclaiming.

So a recut buys a clean slate and does not address why the disk filled. The reversible
alternative — growing `var.registry_volume_size` — is blocked today by a circularity rather than
by physics: the filesystem only grows via `resize2fs` on the next immutable redeploy, a redeploy
replaces the host, and a replaced host meets a still-plaintext ext4 volume and hits the `blkid`
FATAL refuse. zot's `accessControl` grants no user `delete`, so nothing can reclaim over the
existing ingress either. Breaking that circularity is what the recut actually buys. Record the
post-recut fill rate before concluding the incident is closed.
- **#7278** — the registry host has no in-place restart lever. Usually the thing you actually
  wanted; try it first once it exists, rather than reaching for a destroy. #7287 additionally
  declares it a **rollback dependency**, not merely a prerequisite.

**Context:**

- `scripts/registry-pull-path-health.sh` — **the D10 gate quoted above.** This is the file whose
  refusal blocks the runbook; its header carries the full rationale. (Note its header still
  describes the store as "a DISPOSABLE GHCR MIRROR — pulls fall through to GHCR while it
  re-fills", which is the same retracted premise corrected in this document. The refusal it now
  emits is correct; that header comment is not.)
- ADR-096 § *Guest-side LUKS at-rest for the store volume* — the decision, the accepted ordering
  windows, and why there is no key escrow here. Clause (g) records a **broader** debt than #7277
  ("one registry and no fallback"; restoration = a zero-touch-mintable GHCR pull credential, or a
  second mirror) and still reads "no dedicated tracker". #7277 covers only the gate's
  authorization condition — closing it does **not** close clause (g). #6126 is the closer fit for
  the second-mirror arm.
- ADR-096 *Amendment 2026-07-30* — the change (#7071) that retracted this runbook's GHCR-cover
  premise. Read it before trusting any GHCR statement in an older document.
- `tests/scripts/lib/registry-luks-recut-gate.sh` — the **plan destroy-guard** (`volume_provisioned`,
  `out_of_scope`, the id-pin). A different gate from the D10 pull-path one above: this is the guard
  that reads the Terraform plan, and it is not the thing currently blocking the dispatch.
- #7247 — the 22h zot crash-loop where both this runbook and `registry-host-replace` turned out to
  be blocked, which is how the staleness above was found.
- #6946 — accepted residual: `registry-region-migrate` accepts a similar shape with no id-pin.
