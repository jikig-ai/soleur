# Decision Challenges — feat-one-shot-6497-docker-login-readonly-cred

Headless-persisted decision divergences (plan Step 4.5 / plan-review). `ship` renders these into the PR body and files an `action-required` issue.

## DC-1 — Recommended fix diverges from the ARGUMENTS' presumptive Option 1

**Class:** user-challenge (measured architecture recommendation; ARGUMENTS explicitly asked to "evaluate in the plan")

**Operator's stated direction (default):** the ARGUMENTS listed **Option 1** first as the "minimal, same-shape-as-existing-entries" fix — add `/home/deploy/.docker` to `webhook.service` `ReadWritePaths`.

**Plan's recommendation:** **Option 2** — relocate the deploy-user `DOCKER_CONFIG` onto `/mnt/data/deploy-docker` (already a `ReadWritePath`, already mounted) via a single exported `DOCKER_CONFIG` in `ci-deploy.sh`.

**Measured grounds for the divergence:**
1. Learning `2026-04-06-doppler-protecthome-readonly-config-dir-fix.md` is direct precedent: for `ProtectHome=read-only` + a home config-dir write, **relocate to a writable path rather than punch ProtectHome** — and it names `~/.docker` explicitly.
2. Option 1 is **not** actually a one-line same-shape change: `/home/deploy/.docker` does not exist on a fresh host (deploy user via cloud-init `users:`; makes `/home/deploy`, not `.docker`). A hard `ReadWritePath` on an absent dir `226/NAMESPACE`s webhook.service (deploy listener DOWN); a `-`-prefixed path stays read-only (still EROFS). So it needs a boot `mkdir` + edits to **both** `cloud-init.yml:264` and standalone `webhook.service:48` in lockstep.
3. The `infra-config` hot-push path (web-1) cannot deliver a boot `mkdir` — risking a bricked webhook.service if the unit is hot-pushed before the dir exists.
4. Option 2 reaches web-1 via the `ci-deploy.sh` hot-push with **no power-off**; Option 1's systemd-unit half needs a web-1 maintenance-window power-off.

**Disposition:** surfaced, not silently applied. Operator may prefer Option 1 despite the above; if so, the plan's Option 1 section carries the full edit set (both unit copies + boot mkdir + gzip-budget/templatefile caveats).

## DC-2 — Repair soak groups by `_MACHINE_ID`, not the plan's "host_id beacon field"

**Class:** mechanical (the plan's mechanism was blocked by measured telemetry reality; one correct resolution)

**Plan's wording (Phase 3):** the repair soak asserts per-host coverage using "the `host_id` beacon field (`ci-deploy.sh:137-162`)".

**What I implemented:** the soak (`scripts/followthroughs/zot-login-gate-erofs-repaired-6565.sh`) groups by journald-native `_MACHINE_ID`, extracted from each Better Stack record.

**Measured grounds (traced at /work, not assumed):**
1. `HOST_ID` is emitted ONLY to **Sentry** — the `zot_gate_degraded_event` payload `host_id` tag (`ci-deploy.sh:1104`) and the `#6396` pull-failure Sentry beacons. It is **NOT** written into the journald `ZOT_GATE`/`PRELUDE` logger lines (`:1248/1258/1349/1359` etc.), which are the plane the soak reads via `betterstack-query.sh`. So a per-`host_id` soak against Better Stack keys on a field that is not there.
2. `host_name` (Vector-computed) is MISLABELED per `#6616` — uniformly `soleur-inngest-prd` on both web hosts — so it cannot distinguish web-1 from web-2.
3. `_MACHINE_ID` is journald-native (the host's `/etc/machine-id`), present verbatim in every Better Stack record, distinct per host, and mints fresh on a web-2 `-replace` recreate (correct for fleet coverage). It is the only reliable per-host discriminator in this no-SSH plane today.

**Why not add `host_id` to the logger lines instead:** that would expand the fix into the `#6497` instrument's logger lines (regression risk to the instrument soak + classifier fixtures) for marginal benefit over `_MACHINE_ID`. Keeping `ci-deploy.sh` to the single `DOCKER_CONFIG` relocation (the blast-radius discipline that motivated Option 2) is the disciplined choice. Emitting `host_id` into Better Stack lines is a reasonable future observability enhancement, tracked as a possible follow-up, not required for a correct per-host close criterion.

**Disposition:** applied (mechanical). Recorded here for transparency; the soak header documents the same rationale inline.
