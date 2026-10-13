---
title: "fix(infra): bake GHCR read-creds into web-host cloud-init ghcr_login + harden Doppler fallback (#6090)"
issue: 6090
branch: feat-one-shot-6090-ghcr-login-bake-creds
type: bug
classification: infra / sensitive-path
lane: cross-domain  # spec.md absent — defaulted to cross-domain (fail-closed, TR2)
brand_survival_threshold: none
requires_cpo_signoff: false
detail_level: MORE
ref: "#6090"
---

# fix(infra): bake GHCR read-creds into web-host cloud-init `ghcr_login` + harden Doppler fallback 🐛

> Spec lacks valid `lane:` (no `spec.md`) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

On a cold, fresh **web-2** boot the cloud-init extraction block's `ghcr_login` stage
fetches `GHCR_READ_USER` / `GHCR_READ_TOKEN` from Doppler with `timeout 15 doppler
secrets get … --config prd`. At that cold-boot instant Doppler answers **EMPTY** (the
API is reachable moments later — this is a boot-timing race, not a connectivity or
credential-validity problem). With empty creds, `docker login ghcr.io` is skipped, the
**private** seed-image pull goes out anonymous, GHCR returns **401**, and boot aborts at
`STAGE=pull` — so web-2 never binds `:9000`.

The fatal Sentry emit survives that failure only because the Sentry DSN is **baked** into
the host script via `${sentry_dsn}` (`cloud-init.yml` `_emit`, ~L306). `ghcr_login` has no
baked fallback — it depends solely on the cold-boot Doppler answer. The fix gives
`ghcr_login` the **same baked-cred treatment** the DSN already has, and hardens the Doppler
call that remains as fallback.

**Two changes, one PR:**

1. **Bake the creds.** Prefer baked `${ghcr_read_user}` / `${ghcr_read_token}` in the
   `ghcr_login` block; fall back to Doppler only when the bake is empty. Pass the two vars
   into the web-host `templatefile(...)` map in `server.tf`. The Terraform vars already
   exist in `ghcr-read-credential.tf` and are already `sensitive = true`.
2. **Harden the Doppler fallback.** Bump `timeout 15` → `timeout 45` and wrap each fetch in
   a 3-try retry loop mirroring the apt-block idiom already in this file (`cloud-init.yml`
   L356/L362).

The existing detail-tag capture (`ghcr_login_ok` / `ghcr_creds_missing` / `ghcr_login_fail`
/ `pull_err:` → `/run/soleur-stage-detail`) is **preserved verbatim** — it is the
verification signal for the operator's post-merge web-2 recreate.

### Why this is security-neutral

`user_data` already carries `${doppler_token}` (a service token that itself reads **all**
`prd` secrets), `${webhook_deploy_secret}`, and `${sentry_dsn}`. Baking a scoped,
read-only, single-machine-account GHCR `read:packages` PAT (governed by ADR-087 D1 /
ADR-088) adds **no new trust boundary** to a surface that already carries the strictly
stronger `doppler_token`. `user_data` is re-rendered on every `hcloud_server` create, so the
baked creds cannot go stale (a rotation lands on the next recreate). **web-1 is untouched**
(see Infrastructure §Apply path).

## Research Reconciliation — Spec vs. Codebase

| Task premise | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| Fetch is at `cloud-init.yml` ~L443-444, un-hardened | Confirmed: `GHCR_USER=$(timeout 15 doppler secrets get GHCR_READ_USER --plain --project soleur --config prd 2>/dev/null \|\| true)` at ~L443, token at ~L444, inside a `( set +e … ) \|\| true` subshell (~L440-452). | Edit in place; keep the subshell + detail capture. |
| Mirror how `${sentry_dsn}` is baked (~L306) | Confirmed pattern: `DSN='${sentry_dsn}'; [ -n "$DSN" ] \|\| DSN=$(timeout 15 doppler …)`. | Mirror exactly for both GHCR vars, single-quoted interpolation. |
| Vars already exist in `ghcr-read-credential.tf` | Confirmed: `variable "ghcr_read_user"` + `variable "ghcr_read_token"` in `variables.tf` L284/L290, both **already `sensitive = true`**. | **No `sensitive = true` edit needed** — task's "if not already" resolves to already-done. |
| `TF_VAR_ghcr_read_*` available during apply | Confirmed: the two vars are ALREADY consumed by `doppler_secret.ghcr_read_{user,token}` in `ghcr-read-credential.tf`, so `TF_VAR_ghcr_read_*` are already resolved on every auto-apply (a missing one would already fail the whole apply). | Passing them into the templatefile adds **no new no-default provisioning requirement** — the sequencing sharp-edge (no-default TF var vs auto-applied IaC) does **not** apply here. |
| server.tf passes creds into web-host user_data | Confirmed the templatefile map (server.tf L137-159) passes `sentry_dsn`, `doppler_token`, `webhook_deploy_secret` — but **NOT** the two GHCR vars. | Add `ghcr_read_user = var.ghcr_read_user` + `ghcr_read_token = var.ghcr_read_token` to that map. |
| Size test needs the two new vars added | Confirmed `cloud-init-user-data-size.test.ts` derives its var map from `parseVarMap(extractTemplatefileMap(serverTf, "cloud-init.yml"))` — it reads server.tf, NOT a hardcoded map. Unknown `${…}` throws `references un-provided template var`. | **No edit to the size test** — as long as server.tf's map gains the two entries. The throw is a *coupling guard*: cloud-init.yml and server.tf must move together. Each new var models as `DEFAULT_REF_LEN` (80 B) → negligible gzipped. |
| `cloud-init-ghcr-seed-login.test.sh` asserts on the block | Confirmed L41 asserts `doppler secrets get GHCR_READ_USER` **and** `…GHCR_READ_TOKEN` remain present; L31 asserts `docker login ghcr.io -u "$GHCR_USER"` precedes the pull. | The Doppler fetch stays as the *fallback* (literal preserved) and the `docker login` line is unchanged, so this sibling test still passes with **no edit**. |
| web-2 recreate is a separate operator dispatch | Confirmed `apply-web-platform-infra.yml` `apply_target: web-2-recreate` = scoped `-replace` of web-2. | Do NOT plan any autonomous dispatch (operator-gated). |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — web-2 is a **weight-0,
  non-serving** warm-standby (Cloudflare LB weight 0 until GA per server.tf L180-184). A
  broken change would at worst leave web-2 unable to complete first boot, exactly the
  present state; **web-1 (the sole serving host) is never touched** by this change.
- **If this leaks, the user's data is exposed via:** no new exposure vector. The baked GHCR
  PAT is a scoped, read-only `read:packages` token on a machine account; the same
  `user_data` already carries the strictly-more-powerful `doppler_token` (reads all `prd`
  secrets). No additional secret class enters the surface.
- **Brand-survival threshold:** `none, reason: web-2 is weight-0 non-serving; web-1 is
  untouched (hcloud_server.web ignore_changes=[user_data]); no new secret class enters
  user_data.`

## Hypotheses (network-outage gate — fired on the "timeout" substring)

The `hr-ssh-diagnosis-verify-firewall` L3→L7 gate fired mechanically on the word `timeout`
(in `timeout 15 doppler …`). This plan makes **no SSH / connectivity hypothesis** — the
root cause is already isolated by the prior 4-PR observability arc to a single, named,
application-layer stage. The four layers are therefore N/A, not skipped:

- **L3 — Firewall allow-list:** N/A. No SSH is involved (hard constraint: no SSH). The host
  reaches Doppler's API successfully moments later in the same boot; there is no allow-list
  drift and no operator-egress-IP dependency in scope.
- **L3 — DNS / routing:** N/A. `ghcr.io` and Doppler both resolve and connect on the same
  boot — the 401 is an *auth* response (server reached), not a routing failure; the Doppler
  EMPTY is an application-timing race, not a resolution failure.
- **L7 — TLS / proxy:** N/A. GHCR returns a valid HTTP 401 (chain intact); off-host the
  token + image pull with HTTP 200. The failure is host-side credential *absence*, proven
  by the existing `ghcr_creds_missing` detail tag, not a TLS/proxy fault.
- **Service layer (root cause, pre-established):** Doppler answers EMPTY at the cold-boot
  instant → creds absent → `docker login` skipped → anonymous private-pull 401 → abort at
  `STAGE=pull`. The fix removes the cold-boot Doppler dependency (bake) and hardens the
  residual fallback (timeout+retry).

_No incident telemetry emitted for `hr-ssh-diagnosis-verify-firewall`: this plan proposes
no firewall/sshd/connectivity hypothesis, so recording a "rule applied" event would be a
false signal to the weekly aggregator._

## Files to Edit

1. **`apps/web-platform/infra/cloud-init.yml`** (the `ghcr_login` block, ~L438-452, inside
   the `set -e` extraction runcmd). Two edits, both inside the existing
   `( set +e … ) || true` subshell, both preserving the detail-tag capture verbatim:

   Replace the current two un-hardened fetches:
   ```sh
   GHCR_USER=$(timeout 15 doppler secrets get GHCR_READ_USER --plain --project soleur --config prd 2>/dev/null || true)
   GHCR_TOKEN=$(timeout 15 doppler secrets get GHCR_READ_TOKEN --plain --project soleur --config prd 2>/dev/null || true)
   ```
   with baked-preferred + hardened-fallback (mirrors `${sentry_dsn}` bake at L306 and the
   apt retry idiom at L362):
   ```sh
   GHCR_USER='${ghcr_read_user}'
   [ -n "$GHCR_USER" ] || { n=0; until GHCR_USER=$(timeout 45 doppler secrets get GHCR_READ_USER --plain --project soleur --config prd 2>/dev/null); [ -n "$GHCR_USER" ]; do n=$((n+1)); [ "$n" -ge 3 ] && break; sleep 5; done; }
   GHCR_TOKEN='${ghcr_read_token}'
   [ -n "$GHCR_TOKEN" ] || { n=0; until GHCR_TOKEN=$(timeout 45 doppler secrets get GHCR_READ_TOKEN --plain --project soleur --config prd 2>/dev/null); [ -n "$GHCR_TOKEN" ]; do n=$((n+1)); [ "$n" -ge 3 ] && break; sleep 5; done; }
   ```
   - **Templatefile-escaping note:** `${ghcr_read_user}` / `${ghcr_read_token}` are Terraform
     interpolations (curly → substituted, exactly like `${sentry_dsn}`). `$(…)`, `$((n+1))`,
     and `$GHCR_USER` are bare `$` (no curly) and pass through templatefile untouched (same
     as the existing `$(seq 1 30)` and `N=$((N+1))` in this file). No `$$` escaping required.
   - Single-quote the interpolation (`'${ghcr_read_user}'`) exactly like `DSN='${sentry_dsn}'`.
     GHCR logins/PATs are `[A-Za-z0-9_]`-only, so no quote-injection risk.
   - `set +e` is active in the subshell, so a failed substitution inside the `until` guard
     does not abort — the `[ -n "$VAR" ]` guard drives the loop; on 3 misses it `break`s and
     the existing `ghcr_creds_missing` branch fires (non-fatal, as today).
   - **Preserve** the `if [ -z "$GHCR_USER" ] || [ -z "$GHCR_TOKEN" ]; then … ghcr_creds_missing …
     elif … docker login … ghcr_login_ok … else … ghcr_login_fail …` detail-capture block and
     the downstream `pull_err:` append — **unchanged**.

2. **`apps/web-platform/infra/server.tf`** (web-host `hcloud_server.web` templatefile map,
   L137-159). Add two entries alongside `sentry_dsn`:
   ```hcl
   ghcr_read_user  = var.ghcr_read_user
   ghcr_read_token = var.ghcr_read_token
   ```
   - Coupled to edit #1: templatefile requires every `${…}` in cloud-init.yml to appear in
     this map, and the size test enforces the same coupling.
   - No `git-data.tf` change — the git-data host is no-docker and has no `ghcr_login` stage.

3. **`apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`** — append **AC19**
   after AC18 (AC18 is currently the last block; the file ends with the pass/fail tally). AC19
   asserts three things (see Test Scenarios for exact greps):
   - baked `${ghcr_read_user}` / `${ghcr_read_token}` are preferred in the `ghcr_login` block;
   - the Doppler fallback is hardened (`timeout 45` + a `until … [ -n "$…" ] … sleep 5` retry loop);
   - `server.tf` passes both vars into the web-host templatefile map.

**No edit** to: `variables.tf` (vars exist + already sensitive), `ghcr-read-credential.tf`,
`cloud-init-user-data-size.test.ts` (map derived from server.tf), `cloud-init-ghcr-seed-login.test.sh`
(fallback literal + `docker login` line preserved), any git-data file, any web-1 provisioner.

## Files to Create

_None._

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` returned no issue whose body names
`cloud-init.yml`, `server.tf`, or `soleur-host-bootstrap-observability.test.sh` — verified at
plan time; if the deepen pass finds one, fold-in or acknowledge per the standard dispositions.)

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/server.tf` — two new keys in the `hcloud_server.web`
  `templatefile("${path.module}/cloud-init.yml", { … })` map: `ghcr_read_user`,
  `ghcr_read_token`. No new resource, provider, or backend change.
- Sensitive vars: `var.ghcr_read_user`, `var.ghcr_read_token` — **already declared**
  (`variables.tf` L284/L290), **already `sensitive = true`**, values sourced from Doppler
  `prd_terraform` as `TF_VAR_ghcr_read_{user,token}` (already provisioned; already resolved
  on every apply because `doppler_secret.ghcr_read_*` consume them). **No new mint, no new
  no-default variable, no operator provisioning step.**

### Apply path
- **(a) cloud-init-only, materialized on operator-gated `-replace`.** `hcloud_server.web`
  carries `lifecycle.ignore_changes = [user_data, …]` (server.tf L190), so the new
  `user_data` render is **inert on the merge auto-apply** (`apply-web-platform-infra.yml`
  push path — no in-place `user_data` change on either running instance; Hetzner cannot
  mutate `user_data` without replace regardless). The baked creds materialize **only** when
  the operator dispatches `apply-web-platform-infra.yml -f apply_target=web-2-recreate` (a
  scoped `-replace` of web-2 that re-runs first-boot cloud-init and binds `:9000`).
- **Blast radius:** web-2 only (weight-0, non-serving). **web-1 is never replaced** by this
  change. Expected downtime: none (web-1 keeps serving; web-2 is not in the LB pool).
- **Post-merge web-2 recreate + verification is OPERATOR-GATED** — this plan prescribes **no**
  autonomous dispatch. The positive verification signal is the terminal `cloud_init_complete`
  Sentry breadcrumb + the `:9000` bind (a green recreate). NOTE: the `ghcr_login_ok` string is
  written to `/run/soleur-stage-detail` but a *successful* `docker pull` clears that file (L467
  `: > /run/soleur-stage-detail`) before any emit reads it — so the `detail` tag carries a value
  ONLY on the failure paths (`ghcr_creds_missing` / `ghcr_login_fail` / `... | pull_err:`).

### Distinctness / drift safeguards
- `dev` is intentionally NOT provisioned for GHCR creds (host reads `--config prd` only —
  see `ghcr-read-credential.tf`); this change reads the same `prd` values, adding no dev
  surface.
- `ignore_changes = [user_data]` is the load-bearing safeguard that keeps web-1 and the
  live pool untouched; the change relies on it, does not alter it.
- The baked PAT value lands in `terraform.tfstate` (encrypted R2 backend) exactly as
  `doppler_token`/`sentry_dsn` already do — no new state-secret class.

### Vendor-tier reality check
- N/A — no new vendor resource; GHCR PAT + Doppler secrets already provisioned.

## Observability

```yaml
liveness_signal:
  what: web-2 first-boot reaches STAGE=pull success then binds :9000; healthy path emits
        the terminal `cloud_init_complete` breadcrumb (existing, AC9)
  cadence: per web-2 recreate (operator-gated -replace) — not continuous
  alert_target: Sentry (fresh-host boot project) via baked-DSN _emit; the recreate workflow's
                always()-run Sentry surface step (AC8b) shows the probe fired
  configured_in: apps/web-platform/infra/cloud-init.yml (_emit, on_err trap); baked ${sentry_dsn}
error_reporting:
  destination: Sentry `store` API via curl in _emit (baked DSN, fires even when doppler is broken)
  fail_loud: yes on the boot path — STAGE=pull failure runs `exit 1` which aborts the whole
             runcmd (fail-closed); the fatal on_err emit carries stage + detail tags
failure_modes:
  - mode: baked creds empty AND Doppler still empty after 3×(timeout 45) retries
    detection: /run/soleur-stage-detail = "ghcr_creds_missing user=? token=?" surfaced as the
               `detail` tag on the STAGE=pull fatal emit
    alert_route: Sentry fresh-host emit (detail tag names the exact sub-cause)
  - mode: creds present but docker login rejected (rotated/revoked PAT)
    detection: /run/soleur-stage-detail = "ghcr_login_fail: <tail of login stderr>"
    alert_route: Sentry fresh-host emit (detail tag)
  - mode: login ok but pull still fails (registry/network)
    detection: "ghcr_login_ok | pull_err: <tail of pull stderr>" appended on final pull attempt
    alert_route: Sentry fresh-host emit at STAGE=pull fatal
logs:
  where: /run/soleur-stage-detail, /run/soleur-ghcr-login.log, /run/soleur-pull.log on the host;
         mirrored into the Sentry emit `detail` tag (no SSH required to read the cause)
  retention: tmpfs (/run) for the boot; the Sentry event is the durable record
discoverability_test:
  command: gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate  # OPERATOR-GATED, not auto-dispatched; then read the Sentry detail tag via the workflow's always()-run Sentry surface step (no host shell access needed)
  expected_output: a terminal cloud_init_complete breadcrumb (web-2 bound :9000) = success; a failed boot instead emits a STAGE=pull fatal whose detail tag names the sub-cause (ghcr_creds_missing / ghcr_login_fail / pull_err)
```

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `cloud-init.yml` `ghcr_login` block prefers baked `${ghcr_read_user}` and
      `${ghcr_read_token}` (assignment precedes the Doppler fetch for each).
- [ ] The Doppler fallback for each uses `timeout 45` (not `timeout 15`) and a
      `until … ; [ -n "$…" ]; do … sleep 5; done` retry loop (≤3 tries, `break` not `exit`).
- [ ] The detail-tag capture is preserved: `ghcr_creds_missing`, `ghcr_login_ok`,
      `ghcr_login_fail`, and `pull_err:` all still write to `/run/soleur-stage-detail`.
- [ ] `server.tf` web-host templatefile map contains `ghcr_read_user = var.ghcr_read_user`
      and `ghcr_read_token = var.ghcr_read_token`.
- [ ] AC19 added to `soleur-host-bootstrap-observability.test.sh` and the suite passes
      (`$fail -eq 0`).
- [ ] `cloud-init schema` validates the rendered file (see Test Scenarios render recipe).
- [ ] `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` passes (web gzip
      budget still under cap; the two new `${…}` vars resolve via the server.tf map).
- [ ] Sibling infra tests green: `server-tf-set-e.test.sh`, `cron-egress-enforce-probe.test.sh`,
      `cloud-init-ghcr-seed-login.test.sh`, `cloud-init-plugin-seed.test.sh`.
- [ ] `actionlint` clean; `terraform fmt -check` + `terraform validate` clean for the
      `apps/web-platform/infra` root.
- [ ] `git grep -c 'timeout 15 doppler secrets get GHCR_READ' cloud-init.yml` == 0 (no stale
      un-hardened fetch left behind).
- [ ] PR body uses `Ref #6090` (NOT `Closes` — the real closure is the operator's post-merge
      web-2 recreate) + `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

### Post-merge (operator)
- [ ] Operator dispatches `apply-web-platform-infra.yml -f apply_target=web-2-recreate`
      (OPERATOR-GATED — not auto-dispatched). Automation: not feasible in-session because
      the recreate replaces a live cluster host inside a maintenance window and is
      deliberately human-gated (weight-0 standby, but a `-replace` of prod infra).
- [ ] Verify via the recreate's terminal `cloud_init_complete` breadcrumb (web-2 bound `:9000`)
      — read from Sentry, **no SSH**. Success clears the detail file, so a green recreate + bind
      IS the positive signal; a `detail` tag only appears on a failed boot (names the sub-cause).
- [ ] `gh issue close 6090` after the recreate confirms the bind.

## Domain Review

**Domains relevant:** Engineering/Infra, Security (both low-touch, threshold `none`).

### Engineering / Infra
**Status:** reviewed (inline; deepen-plan spawns the eng panel).
**Assessment:** Pure infra hardening on an existing surface. The edit mirrors two patterns
already in the same file (the `${sentry_dsn}` bake and the apt retry loop), so it introduces
no new mechanism. The size-test coupling (map derived from server.tf) and the `ignore_changes`
inert-on-merge behavior are the two facts a reviewer must confirm; both are documented above.

### Security
**Status:** reviewed (inline).
**Assessment:** Security-neutral by construction — `user_data` already carries `doppler_token`
(reads all `prd` secrets), so baking a scoped read-only GHCR PAT strictly reduces, never
expands, the effective secret power on the surface. Governed by ADR-087 D1 / ADR-088 (the
GHCR credential auth-model decision — unchanged by this PR). No secrets are ever echoed; all
reads are command-substitution. Value lands in encrypted-backend `tfstate` exactly as the
existing baked secrets do.

### Product/UX Gate
**Tier:** none — no `## Files to Create`/`Edit` matches a UI-surface path; infra/tooling only.

## Architecture Decision (ADR/C4)

**Skipped** — no architectural decision. This is a bug fix / reliability hardening on an
existing surface: it changes *where* the GHCR token is read at one boot stage (baked vs
cold-boot Doppler), same token, same credential flow, same trust boundary already documented
by ADR-087/ADR-088 and #6005. No new external actor, external system, data store, or
access-relationship is introduced (GHCR, Doppler, Sentry are all already in the flow), so no
`.c4` edit is warranted. A competent engineer reading the existing ADRs + C4 would **not** be
misled about the system after this ships.

## Test Scenarios

Run from repo root unless noted.

1. **Observability suite (incl. new AC19):**
   `bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` → `$fail -eq 0`.

   AC19 grep shape (author against `CI=apps/web-platform/infra/cloud-init.yml`,
   `TF=apps/web-platform/infra/server.tf`):
   - baked preference: `grep -qF "GHCR_USER='\${ghcr_read_user}'" "$CI"` **and**
     `grep -qF "GHCR_TOKEN='\${ghcr_read_token}'" "$CI"`.
   - hardened fallback: `grep -qE 'timeout 45 doppler secrets get GHCR_READ_USER' "$CI"` **and**
     `grep -qE 'until GHCR_USER=\$\(timeout 45 doppler.*GHCR_READ_USER' "$CI"` (retry loop present)
     **and** `grep -qc 'timeout 15 doppler secrets get GHCR_READ' "$CI"` returns 0 (no stale form).
   - server.tf passthrough: `grep -qE '^\s*ghcr_read_user\s*=\s*var\.ghcr_read_user' "$TF"` **and**
     `grep -qE '^\s*ghcr_read_token\s*=\s*var\.ghcr_read_token' "$TF"`.
   - (Use the file's existing `ok`/`no` helpers and increment the tally; place after the AC18 block.)

2. **cloud-init schema validity** (render the interpolations away, then validate):
   ```sh
   sed -E 's/\$\{[a-zA-Z0-9_]+\}/dummyval/g; s/\$\$\{/${/g' \
     apps/web-platform/infra/cloud-init.yml > /tmp/ci-rendered.yml
   cloud-init schema --config-file /tmp/ci-rendered.yml   # expect: Valid schema
   ```

3. **user_data size budget:**
   `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → web gzip'd render under
   `WEB_GZIP_BUDGET`; must not throw `references un-provided template var` (proves the two new
   `${…}` are present in the server.tf map).

4. **Sibling infra tests:**
   `bash apps/web-platform/infra/server-tf-set-e.test.sh`,
   `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh`,
   `bash apps/web-platform/infra/cloud-init-ghcr-seed-login.test.sh`,
   `bash apps/web-platform/infra/cloud-init-plugin-seed.test.sh` — all green.

5. **Terraform + actionlint:**
   `terraform -chdir=apps/web-platform/infra fmt -check`,
   `terraform -chdir=apps/web-platform/infra validate`, `actionlint`.

## Risks & Sharp Edges

- **Templatefile / size-test coupling.** Adding `${ghcr_read_user}`/`${ghcr_read_token}` to
  cloud-init.yml WITHOUT adding them to the server.tf map fails `terraform validate` **and**
  throws `references un-provided template var` in the size test. This is a feature (a
  coupling guard), not a hazard — but the two files MUST land in the same commit.
- **A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO, or omits the
  threshold will fail `deepen-plan` Phase 4.6.** This plan's threshold is `none` with a
  non-empty scope-out reason (sensitive-path requirement satisfied).
- **`Ref` not `Closes`.** The issue's real closure is the operator's post-merge recreate; a
  `Closes #6090` would auto-close at merge before web-2 is proven to bind `:9000` (ops-remediation class).
- **Do not touch web-1 or the LB weight.** The change relies on `ignore_changes=[user_data]`
  to keep web-1 and the serving pool untouched; do not alter that lifecycle block.
- **`set +e` inside the subshell is load-bearing.** The `until … ; [ -n "$VAR" ]` guard must
  run under `set +e` so a failed Doppler substitution does not abort the boot; the block stays
  wrapped in `( set +e … ) || true` and stays non-fatal (a creds miss still lets STAGE=pull emit).
