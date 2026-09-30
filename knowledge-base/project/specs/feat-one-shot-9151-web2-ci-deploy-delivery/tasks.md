# Tasks — web-2 ci-deploy.sh delivery + parity (#9151)

Plan: `knowledge-base/project/plans/2026-09-29-fix-web-2-ci-deploy-delivery-plan.md`

## Phase 1 — Host-key pin + HCL plumbing

- [ ] Write `apps/web-platform/infra/web-2-ssh-host-key.pub` (header + single
      ECDSA-P256 line; capture evidence: keyscan 2026-09-29 from admin_ips
      egress 82.67.29.121 — re-verify against a fresh `ssh-keyscan
      204.168.189.200` before committing)
- [ ] `server.tf`: add `local.web_2_ssh_host_key` (twin of the web-1
      regex/`one()` shape, reading the new pin file)
- [ ] `outputs.tf`: add `output "web_2_server_ip"` for
      `hcloud_server.web["web-2"].ipv4_address`
- [ ] Add `apps/web-platform/infra/web-2-host-key-local.test.sh` (clone of
      `web-1-host-key-local.test.sh`) — RED first
- [ ] Add `scripts/capture-web-2-host-key.sh` (or generalize
      `capture-web-1-host-key.sh` → `capture-web-host-key.sh <name> <ip>`;
      keep the web-1 callers byte-stable) + its `.test.sh`
- [ ] `terraform validate` passes locally (canonical triplet invocation)

## Phase 2 — The sibling resource

- [ ] `server.tf`: add `resource "terraform_data" "deploy_pipeline_fix_web2"`
      — `connection { host = hcloud_server.web["web-2"].ipv4_address; host_key
      = local.web_2_ssh_host_key; private_key = var.ci_ssh_private_key; agent =
      var.ci_ssh_private_key == null; script_path = "/root/tf-deploy-pipeline-fix-web2-%RAND%.sh";
      timeout = "5m" }`
- [ ] `provisioner "file"` per on-disk artifact; `hooks.json` via remote-exec
      base64 heredoc (same mechanism as `infra_config_handler_bootstrap`);
      remote-exec asserts per-file `sha256sum` vs Terraform-side hashes,
      `chmod`/`chown` per FILE_MAP modes, `systemctl daemon-reload`,
      `systemctl try-restart webhook` + `is-active` assertion
- [ ] `triggers_replace = sha256(join(",", [...]))` over all delivered files +
      `local.hooks_json` + `hcloud_server.web["web-2"].id` +
      `file("web-2-ssh-host-key.pub")` + a sentinel string bumped on any inline
      remote-exec edit. EXCLUDE `local.webhook_doppler_token_env` and
      `push-infra-config.sh` (token not delivered; push script is runner-side)
- [ ] Comment block at the resource: `apply-deploy-pipeline-fix.yml` is its
      sole carrier (apply-web-platform-infra's bridge has no web-2 forward)

## Phase 3 — CI reachability + workflow wiring

- [ ] `apply-deploy-pipeline-fix.yml`: "web-2 forward" step after the existing
      bridge (0600 keyfile, `ssh -N -o ExitOnForwardFailure=yes -o
      StrictHostKeyChecking=yes -o UserKnownHostsFile=<bridge known_hosts> -i
      <keyfile> -L 127.0.0.1:2223:10.0.1.11:22 root@127.0.0.1 -p 2222`,
      bounded listener poll ≤30 s, `iptables -t nat -A OUTPUT -d $WEB_2_IP -p
      tcp --dport 22 -j REDIRECT --to-ports 2223` with WEB_2_IP from
      `terraform output -raw web_2_server_ip`)
- [ ] Teardown (`if: always()`): delete the second NAT rule + kill the forward
      PID, tolerant of pre-forward failure
- [ ] `-target=terraform_data.deploy_pipeline_fix_web2` in plan + apply
- [ ] Add `apps/web-platform/infra/web-2-ssh-host-key.pub` to the workflow's
      `paths:` AND `TRIGGER_FILES` in `ship-deploy-pipeline-fix-gate.test.ts`
      + the gate's bash array (lockstep)
- [ ] Verify `terraform-target-parity.test.ts` union semantics (per-workflow
      vs across-both); allowlist entry in apply-web-platform-infra if needed —
      never a bare `-target` there
- [ ] Belt: `command -v ssh` in the forward step; `sshd -T` allowtcpforwarding
      pre-check documented (ADR-220 `-W` channel is the live precedent)

## Phase 4 — Parity emission + assertion

- [ ] `ci-deploy.sh`: emit `DEPLOY_SCRIPT_SHA sha256=<sha>` at startup
      (`logger -t "$LOG_TAG"`, adjacent to SOLEUR_DEPLOY_INVOCATION)
- [ ] `cat-deploy-state.sh`: add `ci_deploy_sha256` field (live sha256sum,
      `|| ""` contract)
- [ ] `scripts/check-deploy-script-parity.sh`: repo sha vs web-1
      `/hooks/deploy-status` (`curl --max-time 20`, HMAC + CF Access env) vs
      per-host Better Stack `DEPLOY_SCRIPT_SHA` via `betterstack-query.sh`
      under `doppler run -p soleur -c prd_terraform`; host set derived from
      `var.web_hosts`; `--self-test` prints `ok` unauthenticated
- [ ] `apply-deploy-pipeline-fix.yml` verify step runs the web-1 arm
- [ ] Tests: `ci-deploy.test.sh`, `cat-deploy-state.test.sh`, parity-script
      test (`scripts/check-deploy-script-parity.test.sh` or tests/scripts/)
      with mutation rows: repo-ahead drift, missing marker, missing field,
      third host added

## Phase 5 — Guard/test updates + records

- [ ] `web-host-provisioner-parity.test.sh`: web-2 sibling class (web-2-dialing
      resources pin `local.web_2_ssh_host_key`), FLOOR_RESOURCES 18→19,
      FLOOR_DESTS bump, ALLOWED_HOST_KEYS extension, dials-web-2 counterpart
      rule
- [ ] `web-host-provisioner-parity.test.sh` gains a credential-exclusion scan
      over web-2-dialing blocks: no `webhook_doppler_token_env` /
      `SOLEUR_DOPPLER_TOKEN` / `soleur-doppler-token` reference
- [ ] `web-host-provisioner-parity-mutation.test.sh`: new rows — sibling
      unpinned, sibling pinned to web-1 key, sibling repointed to web-1 host,
      sibling referencing the token env
- [ ] Check `ship-deploy-pipeline-fix-gate.test.ts` triggers_replace sweep
      scope; comment/document either way
- [ ] ADR-114 addendum (one-SSHable-host constraint lifted for web-2 via the
      web-1 `-L` forward; rejected `ssh-web-2.` ingress recorded);
      ADR-237 context touch-up (web-2 joins the committed-pin set)
- [ ] `model.c4`: `github -> hetzner` SSH edge gains the web-2 hop + tunnel
      description note; verify `c4-count-parity.test.sh` counts unaffected
- [ ] Runbook note naming `web-2-ssh-host-key.pub` + capture script
- [ ] PR body: first line answers "does merging alone mutate production?"
      (YES — apply writes web-2 files); `Ref #7103`, `Ref #9151`

## Post-merge verification (outside this PR's CI)

- [ ] Merge-triggered apply green; sha assertions printed (PM1)
- [ ] `check-deploy-script-parity.sh` exits 0 both hosts (PM2)
- [ ] Better Stack: `IMAGE_VERIFY: ok` (gcr.io ref) + `IMAGE_FRESHNESS: ok` +
      `DEPLOY_SCRIPT_SHA` from `host_name=soleur-web-2` on the next web deploy;
      then `gh issue close 9151` (PM3)

## Constraints

- `TMPDIR=/data/scratch-9097` for tests
- Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test,web-platform-typecheck`
- No SSH mutation outside the terraform apply path; no manual prod writes
