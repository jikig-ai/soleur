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
