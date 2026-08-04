# Runbook — `registry-luks-recut` (encrypt the zot store volume)

**What this does:** destroys the container registry's storage volume and rebuilds it encrypted.

> ## ⛔ THIS DISPATCH CANNOT CURRENTLY BE FIRED (2026-08-04)
>
> Its pre-destroy pull-path gate (D10) **refuses unconditionally** and has **no valid PASS
> condition**. There is no input that makes it pass. Verified live: run
> [30928016445](https://github.com/jikig-ai/soleur/actions/runs/30928016445) aborted in 28s with
>
> > `REFUSING — this gate's premise is retracted and it has no valid PASS condition (#7071).`
>
> **Do not spend time on the checklist below until that is resolved.** What has to change first is
> in [Why it is blocked](#why-it-is-blocked--read-this-before-anything-else).

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

## Why it is blocked — read this before anything else

The gate's own words:

> The recut destroys the zot store. That was acceptable only while GHCR covered the empty-store
> window. GHCR is no longer readable […] so the window is now a **TOTAL pull outage** until the
> next CI dual-push re-fills zot. Separately, this gate's most direct operand is dark:
> `ghcr-fallback` is emitted only inside the SUCCESS branch of a GHCR pull, so it can never fire
> and can never abort anything.
>
> The counts printed above are real, and they describe ZOT's health. They do not describe cover
> for zot's absence, because there is none.

Two distinct defects, and the second matters even after the first is fixed:

1. **The authorising premise is retracted.** "GHCR covers the gap" is no longer true.
2. **The operand is dark.** `ghcr-fallback` only ever emits on a *successful* GHCR pull, so the
   signal the gate keys on can never fire. A green reading from it was never evidence of anything.

To unblock, someone must re-derive what should authorize a destroy and encode it. The gate lists
the candidates and states plainly that **none has been chosen**:

- gate on a successful CI dual-push within N hours;
- pre-stage the live digests outside the destroyed volume and gate on a rehearsed restore;
- require a second mirror to exist;
- refuse until a GHCR pull credential is restored.

Note the first would *also* fail during a zot outage — a broken CI dual-push is usually exactly
why you are reading this runbook. ADR-096 clause (g) records that these restoration paths have no
tracker; see the Related section.

---

## Before the FIRST-EVER fire: cold-vehicle re-verification (REQUIRED)

This dispatch shipped with **zero live executions**. Its guard *logic* is well covered by tests,
but its *live* surfaces — two Hetzner API probes, one Sentry query, one Better Stack read — have
never run against production. They would otherwise first execute at the single highest-stakes
moment: an irreversible destroy of the store.

So the five checks below are **required before the first fire**, not advisory. If any fails, fix it
and re-verify. **Do not proceed with a degraded gate** — a gate that cannot fail is worse than no
gate, because it gets read as evidence.

1. **Pull-path query can go red.** Confirm the D10 signal still exists under the tags the gate
   queries:
   ```bash
   doppler run -p soleur -c prd_terraform -- \
     bash tests/scripts/test-registry-pull-path-health.sh
   ```
   That suite leads with a positive control. A renamed marker or rotated `SENTRY_AUTH_TOKEN` would
   turn a zero-tolerance gate into one that can never fire.

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
| `registry-pull-path-health: REFUSING … no valid PASS condition (#7071)` | **The current state.** The gate refuses unconditionally; see [Why it is blocked](#why-it-is-blocked--read-this-before-anything-else). The counters it prints are real but describe *zot's* health, not cover for zot's absence. | Nothing was destroyed. Do not re-fire — no input passes. The gate must be re-derived first. |
| `registry-pull-path-health: ABORT` | *(Historical — unreachable while the refusal above stands.)* Previously: "image pulls are already failing over to GHCR, and this recut leans on GHCR to cover the gap." **That premise is retracted** — nothing fails over to GHCR any more, because no host can read it. | Not actionable today. Retained only so an older log line remains interpretable. |
| `volume_provisioned=0` | The plan would **keep** the volume — the exact footgun above. | Do not force it. Re-fire this dispatch (it supplies the `-replace` flags). If it repeats, the resource is missing from state — reconcile before retrying. |
| `volume_id_mismatch=1` | The address points at a **different** volume than you authorized. | **Stop.** Do not re-fire with a different id until you know why state disagrees with reality. |
| `luks_key_touched=1` | The encryption key is not in the isolated Doppler config yet, so Terraform wants to create it. | Run the operator's untargeted apply (the `OPERATOR_APPLIED_EXCLUSIONS` contract) so the key lands, then re-fire. |
| `logs_secret_destroyed=1` | The plan would delete the logging token; the rebuilt host would fail to start without it. | Reconcile the plan. Do not proceed. |
| `out_of_scope=1` (or more) | The plan touches something outside the registry. | **Never widen the allow-set.** This is the only thing protecting the web host and the sole copy of `/mnt/data`. Reconcile the plan. |
| `stock-preflight ABORTED` | Hetzner has no capacity for the replacement host right now. | **Nothing was destroyed.** Wait and re-fire. If the type is unavailable in this region generally, use `registry-region-migrate` instead. |
| `probe` / `did not report the pinned volume absent` | The job saw a "resume" shaped plan but the volume still exists. | This is a state problem, not a recut. Reconcile with `terraform import` — never let it `create`. |

### If the apply itself fails partway

Re-fire the **same** command, with the **same** confirm token and the **same** id. The job detects a
part-finished recut on its own (it checks Hetzner directly to confirm the old volume is really gone)
and resumes. There is no special flag.

### If it finishes but the registry never comes back

The job waits for the rebuilt registry to check in and fails loudly if it does not. Two causes, and
they need different fixes:

- **It refused the volume.** Recoverable — the volume is encrypted now, so
  `registry-host-replace` is the right tool for this.
- **The disk was never attached in time** (`reason=device-absent`). This one **never self-heals**;
  it needs a full recut.

Tell them apart with:

```bash
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK
```

---

## The empty-store window

After a successful recut the store is **empty, and nothing covers it.**

> **Corrected 2026-08-04.** This section previously read *"Deploys still work — they pull from
> GHCR."* **They do not.** Since #7071 (2026-07-30) the host→GHCR edge is dead: the read PAT is
> revoked (401) and the minter is disabled (403 DENIED). `model.c4` calls it a "DEAD EDGE… every
> traversal ends `image_pull_failed`."

What the window actually costs:

- **Already-running containers keep serving.** The recut causes no user-facing outage by itself.
- **Nothing can pull.** Any host reboot, replacement, or new deploy has **no registry to pull
  from** for the whole window. There is no second source.
- The window "is not quiet" as before — but treat the alerting as secondary. The exposure is the
  absence of a pull path, not the noise.

Nothing you control ends it on its own: it lasts until a CI dual-push republishes the images into
the new store.

End it immediately:

```bash
gh workflow run web-platform-release.yml -f bump_type=patch
```

**Best practice: fire the recut immediately before a planned release**, so the window is bounded by a
release you were doing anyway.

---

## After it succeeds

The run summary prints the **new volume id**. Record it — any future recut needs it as the safety
pin, and re-deriving it means going back to Step 1.

---

## Related

**Unblocking this runbook:**

- **#7277** — the D10 gate has no valid PASS condition. **This runbook cannot be used until #7277
  lands.** It is the tracker ADR-096 clause (g) records as missing.
- **#7278** — the registry host has no in-place restart lever. Usually the thing you actually
  wanted; try it first once it exists, rather than reaching for a destroy.

**Context:**

- ADR-096 § *Guest-side LUKS at-rest for the store volume* — the decision, the accepted ordering
  windows, and why there is no key escrow here. Clause (g) records that the restoration paths had
  no tracker; that is now #7277.
- ADR-096 *Amendment 2026-07-30* — the change (#7071) that retracted this runbook's GHCR-cover
  premise. Read it before trusting any GHCR statement in an older document.
- `tests/scripts/lib/registry-luks-recut-gate.sh` — the guard, with its full rationale.
- #7247 — the 22h zot crash-loop where both this runbook and `registry-host-replace` turned out to
  be blocked, which is how the staleness above was found.
- #6946 — accepted residual: `registry-region-migrate` accepts a similar shape with no id-pin.
