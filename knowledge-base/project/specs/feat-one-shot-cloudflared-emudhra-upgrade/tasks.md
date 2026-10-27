# Tasks — fix: cloudflared >= 2026.10.2 fleet-wide (eMudhra)

Derived from `knowledge-base/project/plans/2026-10-27-fix-cloudflared-emudhra-upgrade-plan.md`.

## Phase 1 — Grounding (work Phase 0)

- 1.1 Re-verify latest cloudflared release + compute sha256 of the real
  `cloudflared-linux-amd64` asset AND `cloudflared-linux-amd64.deb` (curl +
  sha256sum; never paste — per composite-action headers). Record both in PR body.
- 1.2 Probe cpx22 stock in hel1 (`GET /v1/datacenters` `.server_types.available`)
  — the web-host-replace dispatch fails closed on a miss.
- 1.3 Grep for other consumers of the Cloudflare apt source/`cf_apt_key` stage in
  cloud-init.yml before removal.

## Phase 2 — WS-A: CI pin bump

- 2.1 Bump `CLOUDFLARED_VERSION`/`CLOUDFLARED_SHA256` env pairs to 2026.10.4 in:
  workspaces-luks-verify.yml:157, workspaces-luks-cutover.yml:93,
  git-data-cutover.yml:126, apply-web-platform-infra.yml:270,
  apply-deploy-pipeline-fix.yml:219.
- 2.2 Bump literal call-site pins in: reusable-release.yml:889,
  registry-zot-inventory.yml:243, build-inngest-config-bundle.yml:202,
  build-inngest-bootstrap-image.yml:617, apply-web-platform-infra.yml:3598.
- 2.3 Update `e.g. 2026.5.0` comment refs in
  `.github/actions/cf-tunnel-{ssh,registry}-bridge/action.yml` (:118, :98).

## Phase 3 — WS-B: deterministic provisioning

- 3.1 Replace `apt-get update`/`apt-get install -y cloudflared` in
  `apps/web-platform/infra/cloud-init.yml` with pinned `.deb` download +
  `sha256sum -c` + `soleur-boot-emit cloudflared_checksum fatal` (webhook-block
  shape).
- 3.2 Remove the Cloudflare apt source list write_file + `cf_apt_key` stage (if
  1.3 confirms sole consumer). Re-run user_data size test budget.
- 3.3 Update `soleur-host-bootstrap-observability.test.sh` + any test asserting
  the apt-install lines.

## Phase 4 — WS-C: connector migration (code)

- 4.1 `server.tf`: `web_tunnel_connector` → `each.key == "web-2"`.
- 4.2 Update asserting suites: scheduled-inngest-health remediation prose (:1390),
  census fixtures, lb-weight/nic-wait/cloud-init suites as needed.
- 4.3 tunnel.tf comment refresh where prose names web-1 as connector host.

## Phase 5 — WS-D: detection + guards

- 5.1 `scripts/tunnel-connector-census.sh`: add version-floor classifier
  (`conns[].client_version`, field-wise numeric; `below_floor` /
  `version_unreadable` verdicts) + extend `.test.sh` fixtures per Guard 3 matrix.
- 5.2 `scheduled-inngest-health.yml`: emit floor verdict + `version_unreadable`
  output; new `ci/tunnel-connector-version` `action-required` filing arm.
- 5.3 `plugins/soleur/test/terraform-target-parity.test.ts`: replace hardcoded
  PIN_WORKFLOWS with a glob census over `.github/` (env + literal forms); add
  mutation-matrix assertions (Guard 1).
- 5.4 New `apps/web-platform/infra/cloudflared-pin-staleness.test.sh` (0/10/2 +
  floor) + `cloudflared.provenance.md` + `rule-audit.yml` "Detect cloudflared pin
  staleness" poll step (Guard 2).
- 5.5 New `scripts/cloudflared-compliance-probe.sh` printing `PINS_OK`.

## Phase 6 — Architecture record

- 6.1 Author ADR "Tunnel connector placement lives on a replaceable host" via
  soleur:architecture (amends ADR-114 placement assumption; provisional ordinal —
  re-check at ship).
- 6.2 `model.c4` tunnel container + `hetzner -> tunnel` edge → web-2 connector;
  check `views.c4`/`spec.c4`; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 7 — Ship artifacts

- 7.1 Follow-through issue (or ship block) with the authorized sequence O1–O4:
  tunnel `-replace` → `web-host-replace` web-2 dispatch → `/connections` census
  verify → operator dev-machine note (macOS ≥2026.10.3).
- 7.2 Confirm `terraform plan` shows no `hcloud_server.web[*]` diff for the code
  merge itself.
