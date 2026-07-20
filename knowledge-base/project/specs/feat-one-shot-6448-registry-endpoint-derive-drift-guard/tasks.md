# Tasks — fix(infra) #6448: derive docker insecure-registries + non-self-referential drift guard

lane: single-domain
Plan: `knowledge-base/project/plans/2026-07-17-fix-registry-endpoint-derive-drift-guard-plan.md`

Locate all constructs by content (line numbers shifted after PR #6458). Endpoint VALUE stays `10.0.1.30:5000`; the change is derivation + guard, not value. The `.tmpl` MUST render byte-identical to the current file (zero apply churn).

## Phase 1 — Templatefile source

- [x] 1.1 `git mv apps/web-platform/infra/docker-daemon.json apps/web-platform/infra/docker-daemon.json.tmpl`
- [x] 1.2 In `docker-daemon.json.tmpl`, change only the value line: `"insecure-registries": ["10.0.1.30:5000"]` → `"insecure-registries": ["${registry_endpoint}"]`. Preserve every other byte (indent, key order, trailing `]\n}\n`).
- [x] 1.3 Verify byte-identity: `templatefile(".../docker-daemon.json.tmpl", { registry_endpoint = "10.0.1.30:5000" })` == the pre-change file bytes.

## Phase 2 — Derive local + rewire resource (`server.tf`)

- [x] 2.1 Add `local.docker_daemon_json = templatefile("${path.module}/docker-daemon.json.tmpl", { registry_endpoint = local.registry_endpoint })`.
- [x] 2.2 `triggers_replace = sha256(file("${path.module}/docker-daemon.json"))` → `sha256(local.docker_daemon_json)`.
- [x] 2.3 `provisioner "file"`: `source = "${path.module}/docker-daemon.json"` → `content = local.docker_daemon_json` (keep `destination = "/etc/docker/daemon.json"`).
- [x] 2.4 Update the resource leading comment so it no longer implies a static `file()` copy; cite `local.registry_endpoint`. Keep ADR-096 / `-target` / reload-not-restart rationale.

## Phase 3 — Derive remote-exec probe (`server.tf`), preserve HIGH-RISK invariants

- [x] 3.1 Probe: `grep -q '10.0.1.30:5000'` → `grep -qF '${local.registry_endpoint}'` (Terraform interpolation; `-qF` fixed-string).
- [x] 3.2 Verify preserved: `"set -e"` first inline element; `python3 ... json.load` malformed-JSON guard before reload; `chown/chmod`; SIGHUP reload (reload, not restart); probe stays terminal command of its inline array.

## Phase 4 — Derive fresh-host inline daemon.json (`cloud-init.yml` + map)

- [x] 4.1 `server.tf` cloud-init templatefile map (the `templatefile("${path.module}/cloud-init.yml", { ... })` call): add `registry_endpoint = local.registry_endpoint`.
- [x] 4.2 `cloud-init.yml`: `"insecure-registries": ["10.0.1.30:5000"]` → `"insecure-registries": ["${registry_endpoint}"]`.
- [x] 4.3 Confirm the daemon.json write is not inside a `%{ if }` directive (it is not) → key required + present.

## Phase 5 — Rebuild drift guard (`registry-insecure-config.test.sh`) — core

- [x] 5.1 Structural asserts (grep server.tf): local is `templatefile(...docker-daemon.json.tmpl...)` passing `registry_endpoint = local.registry_endpoint`; `triggers_replace = sha256(local.docker_daemon_json)`; provisioner uses `content = local.docker_daemon_json`; probe greps `${local.registry_endpoint}` (interpolation token, not literal).
- [x] 5.2 Template shape: `docker-daemon.json.tmpl` insecure-registries value is `${registry_endpoint}`, no `10.0.1.30:5000` literal; valid-JSON check runs against the RENDERED doc, not the raw template.
- [x] 5.3 cloud-init derivation asserts: `cloud-init.yml` value is `${registry_endpoint}` + server.tf map passes the var.
- [x] 5.4 **THE mutation test — shape-based residual scan** (adapt `private-nic-guard.test.sh:490-499`): non-comment count of any `IP:5000`-shape literal (`[0-9]{1,3}(\.[0-9]{1,3}){3}:5000`) across `docker-daemon.json.tmpl` + `cloud-init.yml` + `server.tf` == 0. Match by SHAPE, not the pinned value `10.0.1.30:5000` (renumber-proof; learning 2026-06-11). A reintroduced hardcoded copy → RED. Add an inline comment: single source is `zot-registry.tf:44` `local.registry_endpoint`.
- [x] 5.5 Preserve still-valid asserts: resource-block extraction, reload-not-restart, JSON-guard-precedes-reload, every-remote-exec-opens-`set -e`, `-target` membership, and the `#6497` credential-convergence section (touch only if an anchor shifts).
- [x] 5.6 Do NOT add a `terraform console` render leg here (dropped at deepen-plan per code-simplicity review): render/JSON validity is covered by `validate-infra-templates.sh` (Phase 7) + the apply-time `python3 json.load` guard. Anchor on construct not bare substring; assert rendered (not raw) for interpolated values (learnings 2026-06-02 / 2026-06-03 / 2026-05-06 / 2026-06-11).

## Phase 6 — Fix stale forward-reference (`private-nic-guard.test.sh`)

- [x] 6.1 Update the note (content-anchored on the `:5000` deferral prose) to record #6448 resolved + point to `registry-insecure-config.test.sh`. Do NOT widen private-nic-guard's own asserts.

## Phase 7 — Verify (no workflow edit)

- [x] 7.1 `bash apps/web-platform/infra/registry-insecure-config.test.sh` → 0 failed.
- [x] 7.2 `bash apps/web-platform/infra/private-nic-guard.test.sh` → 0 failed.
- [x] 7.3 `bash apps/web-platform/infra/server-tf-set-e.test.sh` → passes.
- [x] 7.4 `bash .github/scripts/validate-infra-templates.sh apps/web-platform/infra` → `rendered+validated N/N`, output names `docker-daemon.json.tmpl`.
- [x] 7.5 `bash .github/scripts/test/fixtures-validate-infra-templates.sh` → passes.
- [x] 7.6 `cd apps/web-platform/infra && terraform fmt -check && terraform validate` → pass.
- [x] 7.7 Mutation-test sanity (optional, one-time): temporarily hardcode an `IP:5000` literal into `docker-daemon.json.tmpl` (or the server.tf probe) → confirm `registry-insecure-config.test.sh` goes RED on the shape scan; revert → GREEN. (Automated by AC 5.4; this is a one-time human confirmation the self-referential green is gone.)
