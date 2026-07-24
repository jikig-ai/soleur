locals {
  # Rendered hooks.json content, shared between cloud-init user_data (fresh servers)
  # and the deploy_pipeline_fix provisioner (existing server). Single source of truth
  # avoids drift between the two code paths (#2201).
  hooks_json = templatefile("${path.module}/hooks.json.tmpl", {
    webhook_deploy_secret = var.webhook_deploy_secret
  })

  # Fresh-host bootstrap assets baked into var.image_name and extracted by cloud-init.yml
  # at first boot (#5921). These 22 scripts + hooks.json.tmpl were REMOVED from cloud-init
  # write_files: — as base64 blobs they pushed the rendered Hetzner user_data to ~282 KB,
  # ~8.6x over the 32,768-byte cap. KEEP THIS LIST IN LOCKSTEP with the COPY into
  # /opt/soleur/host-scripts/ in apps/web-platform/Dockerfile (cloud-init-user-data-
  # size.test.ts asserts the two sets are identical). Running hosts continue to receive
  # these files via the unchanged SSH/webhook terraform_data provisioners below.
  host_script_files = [
    "ci-deploy.sh",
    "ci-deploy-wrapper.sh",
    "cat-deploy-state.sh",
    "canary-bundle-claim-check.sh",
    "disk-monitor.sh",
    "resource-monitor.sh",
    "container-restart-monitor.sh",
    "container-restart-monitor.service",
    "container-restart-monitor.timer",
    "infra-config-apply.sh",
    "infra-config-install.sh",
    "cat-infra-config-state.sh",
    "cron-egress-nftables.sh",
    "cron-egress-resolve.sh",
    "cron-egress-alarm.sh",
    "cron-egress-allowlist.txt",
    "cron-egress-allowlist-cidr.txt",
    "cron-egress-firewall.service",
    "cron-egress-resolve.service",
    "cron-egress-resolve.timer",
    "cron-egress-alarm@.service",
    "cron-egress-postapply-assert.sh",
    # Fresh-host POST-CONTAINER egress-enforcement probe (#5933 item 3). The SSH
    # provisioner's cron-egress-postapply-assert.sh SKIPS the container probes on a
    # fresh host (no container yet); this baked script runs them at boot AFTER the app
    # container starts (cloud-init.yml terminal block) and fail-closed poweroffs a host
    # whose container egress is not provably enforcing.
    "cron-egress-enforce-probe.sh",
    "hooks.json.tmpl",
    # journald drop-in — moved out of inline write_files: (its 2.4 KB base64 blob was the
    # biggest remaining user_data expansion). Still delivered to the running host byte-for-byte
    # by terraform_data.journald_persistent below (which reads the same on-disk file).
    "journald-soleur.conf",
    # The baked installer that cloud-init's minimal launcher runs AFTER the combined-hash
    # verify (moving the ~90-line install/verify/assert ceremony out of user_data — #5921).
    "soleur-host-bootstrap.sh",
    # Pinned cosign trusted root (#6005). Public trust material (NOT a secret), baked into
    # the HOST base image (NOT the app image cosign verifies — so no circular trust, ADR-087)
    # and installed to /etc/soleur/cosign-trusted-root.json by soleur-host-bootstrap.sh. Too
    # large (~6.8 KB) for cloud-init user_data (32,768-byte cap; already ~29.6 KB). The
    # running host gets it byte-for-byte from terraform_data.cosign_trusted_root below.
    "cosign-trusted-root.json",
    # Vector shipper config (#6396) — baked so the ungated web-host Vector install
    # (soleur-host-bootstrap.sh authors /usr/local/bin/soleur-vector-install, run fail-open
    # at end-of-cloud-init) can render + install it to /etc/vector/vector.toml. Carries the
    # @@HOST_NAME@@ sentinel resolved per-host at install. This decouples web-host log shipping
    # from web_colocate_inngest (default-false post-ADR-100), which otherwise ships NO logs.
    "vector.toml",
    # (#6629) Container-sandbox security-control profiles. Their ONLY prior delivery was the
    # SSH provisioners terraform_data.docker_seccomp_config / apparmor_bwrap_profile below,
    # which reach RUNNING hosts only — a FRESH host (web-1 replacement, or the web-2 warm
    # standby that never receives the web-1 SSH provisioners) came up with NEITHER file, so
    # cat-deploy-state reported seccomp_profile_host_present=false and the boot docker run
    # ran the tenant sandbox unenforced. Baked here (ADR-080/#5921 image-bake, NOT user_data —
    # seccomp-bwrap.json is 16,615 B and would red the WEB_GZIP_BUDGET cap), extracted +
    # installed + apparmor-loaded by soleur-host-bootstrap.sh, enforced at the boot docker run
    # with a fail-closed poweroff if absent. Restores the dual-delivery invariant
    # (hr-fresh-host-provisioning-reachable-from-terraform-apply). See ADR-122.
    "seccomp-bwrap.json",
    "apparmor-soleur-bwrap.profile",
    # (#6459 Phase 2.2) Fresh-boot parity for the last SSH-only host provisioners. A fresh cattle
    # host (web-2) never receives web-1's SSH provisioners, so these came up absent — the #6459
    # silent-boot gap. Baked here + installed by soleur-host-bootstrap.sh + enabled by cloud-init;
    # the SSH provisioners (terraform_data.orphan_reaper_install / the sysctl half of
    # docker_seccomp_config) are RETAINED for running-host rotation on the pet web-1 until Phase 5.
    # The unit bodies are byte-identical to those SSH heredocs (dual-delivery parity, drift-guarded).
    "orphan-reaper.sh",
    "orphan-reaper.service",
    "orphan-reaper.timer",
    "99-bwrap-userns.conf",
    "bwrap-userns-sysctl.service",
    # (#6459 Phase 2.2 PART 2) The 3 web-host probes (#6438/#6548): private-NIC guard, zot-consumer,
    # git-data reachability. Their ONLY prior delivery was the terraform_data.*_probe_install /
    # private_nic_guard_install SSH provisioners below (web-1 only), so a fresh cattle host (web-2)
    # came up with NO probe scripts/units and NO /etc/default/web-<probe> env files. Baked here +
    # installed by soleur-host-bootstrap.sh + env files written by web-probe-envwrite.sh (invoked by
    # cloud-init with the per-host token/IP/endpoints) + timers enabled by cloud-init. The SSH
    # provisioners are RETAINED for web-1 running-host rotation until Phase 5. The .service/.timer
    # bodies are byte-identical across both paths BY CONSTRUCTION (the SSH path delivers the SAME
    # repo files via `provisioner "file"`); env-file key-set parity is drift-guarded in
    # fresh-boot-parity.test.sh §12.
    "web-private-nic-guard.sh",
    "web-private-nic-guard.service",
    "web-private-nic-guard.timer",
    "web-zot-consumer-probe.sh",
    "web-zot-consumer-probe.service",
    "web-zot-consumer-probe.timer",
    "web-git-data-probe.sh",
    "web-git-data-probe.service",
    "web-git-data-probe.timer",
    "web-probe-envwrite.sh",
  ]

  # Combined content-hash over the baked set: each file's sha256 hex, sorted, joined
  # (no separator), hashed again. Injected into user_data (~64 B) and re-verified at boot
  # BEFORE install — a stale/mis-built image aborts the boot loudly instead of silently
  # installing old scripts (turns the ADR-080 image-bake stale trap into a loud failure).
  # The boot recompute is the shell equivalent in cloud-init.yml's extraction block:
  # `find … -exec sha256sum {} + | awk '{print $1}' | LC_ALL=C sort | tr -d '\n' | sha256sum`.
  #
  # THREAT MODEL (scope of this control): this is a STALENESS / COHERENCE control (does the
  # image's baked-file CONTENT match the applied Terraform commit?), NOT a supply-chain
  # control. It hashes the multiset of file CONTENTS (not names), so an actor who can push
  # to the public GHCR repo could in principle permute trusted contents across filenames and
  # pass this check — but that same push access already yields RCE via the app container
  # layers (`docker run … ${image_name}` runs the SAME unpinned image), so filename-binding
  # here raises no real bar. The honest supply-chain defense is pinning `var.image_name` to
  # an immutable digest + signature verification — tracked as a fresh-host provisioning
  # hardening on the #5887 cutover, not this cap-fix PR.
  host_scripts_content_hash = sha256(join("", sort([
    for f in local.host_script_files : filesha256("${path.module}/${f}")
  ])))
}

resource "hcloud_ssh_key" "default" {
  name       = "soleur-web-platform"
  public_key = file(var.ssh_key_path)

  # public_key is a create-time attribute that never changes via Terraform.
  # CI drift checks use a dummy key, so ignore to prevent false positives.
  lifecycle {
    ignore_changes = [public_key]
  }
}

resource "hcloud_server" "web" {
  # Multi-host web cluster (#5274 Phase 3, ADR-068). web-1 is the PRE-EXISTING
  # host; its name/server_type/location come from var.web_hosts pinned to current
  # state so the `moved` migration below is 0-destroy (a location change would
  # force-REPLACE the live prod host). web-2 is fresh — provisioned entirely by
  # cloud-init at boot (the 11 SSH provisioners below stay web-1-scoped, mirroring
  # the git-data host's cloud-init-only shape, so a web-2 that is not yet
  # SSH-reachable never hangs the merge-triggered auto-apply).
  for_each    = var.web_hosts
  name        = each.key == "web-1" ? "soleur-web-platform" : "soleur-${each.key}"
  server_type = each.value.server_type
  location    = each.value.location
  image       = "ubuntu-24.04"
  keep_disk   = true
  ssh_keys    = [hcloud_ssh_key.default.id]

  # Spread across distinct physical hosts within the EU location (HA). Attaching to
  # the RUNNING web-1 forces a power-off → maintenance-window apply (an in-place
  # reboot, NOT a replace — verify `0 to destroy` in the plan before applying).
  # A Hetzner placement group is LOCATION-scoped: a host in a different DC than web-1
  # cannot join web_spread, so it gets null. That is not a downgrade — a cross-DC host
  # is already spread from web-1 at the DC level (stronger HA than same-DC spread), and
  # it stays placeable when web-1's DC is capacity-starved (2026-07-13: web-2 hel1→fsn1).
  placement_group_id = each.value.location == var.web_hosts["web-1"].location ? hcloud_placement_group.web_spread.id : null

  # #5921 — the 22 bootstrap scripts + hooks.json were REMOVED from this map (they blew
  # the 32,768-byte Hetzner user_data cap). They are now baked into var.image_name and
  # extracted at boot by cloud-init.yml (see local.host_script_files above). ONLY the
  # keep-inline set (fail2ban/journald, consumed pre-Docker) + non-file args remain, plus
  # host_scripts_content_hash for the boot integrity check. hooks.json is rendered on-host
  # from the baked hooks.json.tmpl with webhook_deploy_secret injected at boot.
  # gzip-first (#6090). The web host's rendered cloud-config reached the raw 31,500-byte
  # sub-cap budget organically (~31.3 KB), and the #6090 fresh-boot observability additions
  # (readiness gates + emit call-sites that CANNOT be baked — they run IN cloud-init,
  # post-install) pushed it over. #5921's bake-and-extract (ADR-080) is RETAINED underneath —
  # the host scripts stay baked into var.image_name; base64gzip() is layered ON TOP of the
  # residual launcher + call-sites, exactly as git-data adopted it in #5927. NOT a reversal
  # of #5921.
  #
  # Decode contract (identical to git-data.tf, same ubuntu-24.04 image): Hetzner base64-decodes
  # the stored string (DataSourceHetzner.maybe_b64decode, ≥20.3) → raw gzip bytes (magic 1f 8b)
  # → cloud-init auto-gunzips → byte-identical #cloud-config, so every runcmd / write_files /
  # ${host_scripts_content_hash} runs unchanged. base64 is MANDATORY on Hetzner, which makes
  # base64gzip() the intended path, not a datasource gamble. web-1 carries
  # ignore_changes=[user_data], so ONLY a fresh create (the web-2 recreate this PR instruments)
  # receives the gzipped form; its readiness gates fail-closed if decode ever produced a
  # non-#cloud-config. Byte-exact size is confirmed at `terraform plan`. See ADR-080 (amended
  # for the web host).
  # (#6454) cloud-init.yml is a Terraform templatefile() SOURCE, not literal YAML: it
  # carries a `%{ if web_colocate_inngest ~}` directive at column 1, and YAML reads a
  # leading '%' as a directive indicator — so schema-checking that file RAW always fails.
  # CI renders it via `terraform console` and schema-checks the RENDERED document; see
  # .github/scripts/validate-infra-templates.sh. Both directive arms are validated, and
  # the false arm (variables.tf default) is the doc real web hosts boot.
  #
  # This note lives HERE, at the call site, and deliberately NOT inside cloud-init.yml:
  # that file is baked into user_data against Hetzner's 32,768-byte cap, and the
  # base64gzip'd budget (plugins/soleur/test/cloud-init-user-data-size.test.ts,
  # WEB_GZIP_BUDGET) has under ~300 bytes of headroom — an 8-line comment there costs
  # ~276 gzipped bytes and reds that test. cloud-init.yml is effectively comment-frozen;
  # .tf files cost nothing.
  user_data = base64gzip(templatefile("${path.module}/cloud-init.yml", {
    image_name = var.image_name
    # Keep-inline: fail2ban is reloaded early (at the package-audit stage, before Docker) so
    # its drop-in cannot come from the post-Docker image extraction. journald was ALSO inline
    # historically, but its 2.4 KB base64 blob was the biggest remaining user_data expansion,
    # so #5921 moved it into the baked set (its only consumer, the --log-driver journald app
    # container, starts last — safe to configure post-extraction). fail2ban's b64 arg stays;
    # journald's was removed (dropping it while cloud-init.yml still interpolated the var would
    # fail templatefile()).
    fail2ban_sshd_local_b64   = base64encode(file("${path.module}/fail2ban-sshd.local"))
    host_scripts_content_hash = local.host_scripts_content_hash
    tunnel_token              = cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token
    # #6425 — gates `cloudflared service install` (the tunnel REGISTRATION, not the apt
    # install) to the designated ingress host. ADR-114 I1/I2: Cloudflare binds ingress to a
    # TUNNEL and then selects a connector per edge colo, so with two connectors every
    # `localhost:` ingress rule means "whichever replica answered", not "this host" — and
    # only /hooks/deploy fans out, so deploy-status, infra-config (a WRITE) and ssh. all
    # land coin-flipped. One connector ⇒ deterministic by construction.
    #
    # The predicate is `each.key == "web-1"` — the in-file idiom (`name` above, `host_name`
    # below) — NOT a variable. A knob here would look like a promotion switch and isn't:
    # `web["web-1"]` is pinned 23 times across 5 files (`grep -c 'web\["web-1"\]' *.tf`:
    # server.tf 15 provisioner/attachment hosts, outputs.tf 4, placement-group.tf 2,
    # dns.tf 1 (the app A record), ci-ssh-key.tf 1). Promotion must move all of them in
    # lockstep; a lone connector flip would put the connector on web-2 while the A record
    # still points at web-1 — ingress split, at 3am. The coupling is recorded in ADR-068.
    # (No load balancer exists yet — ADR-068 §(c)'s LB weight is future-tense, so it is NOT
    # part of this coupling today. Fold it in when the LB actually lands.)
    #
    # `tunnel_token` above stays in this map unconditionally and is NOT ternary'd to "":
    # templatefile pre-checks expr.Variables() across BOTH branches of the `if` directive, so
    # omitting the key errors even for a gated-off host. And a second predicate could diverge
    # from this one — web-1 rendering gate-on with an empty token would `service install `,
    # fail the readiness poll, and boot the LIVE host with deploy+ssh+registry dark. One
    # predicate, one place.
    web_tunnel_connector = each.key == "web-1"
    # webhook_deploy_secret stays: hooks.json is no longer rendered into user_data, but the
    # secret is injected at boot into the extracted hooks.json.tmpl (small, ~64 B).
    webhook_deploy_secret = var.webhook_deploy_secret
    doppler_token         = var.doppler_token
    # #6459: Better Stack Logs ingest URL for the fresh-boot readiness marker's direct-curl channel
    # (the token is sourced from Doppler at boot; this URL is the same public endpoint the nic-guard
    # env file and the Vector sink use — local.betterstack_logs_ingest_url, single source of truth).
    betterstack_ingest_url = local.betterstack_logs_ingest_url
    # Baked so the fresh-boot fatal Sentry emit does not depend on doppler (which may be the
    # broken stage). Semi-public DSN (already in the client bundle). See on_err in cloud-init.yml.
    sentry_dsn     = var.sentry_dsn
    resend_api_key = var.resend_api_key
    # (#6090) Baked so the cold-boot ghcr_login does not depend on doppler answering at the
    # first-boot instant (an empty answer skipped docker login → anonymous private pull → 401
    # → abort at stage=pull). Scoped read:packages PAT; user_data already carries the strictly
    # stronger doppler_token, so this adds no new trust boundary. See cloud-init.yml ghcr_login.
    ghcr_read_user  = var.ghcr_read_user
    ghcr_read_token = var.ghcr_read_token
    # Fresh-host parity for the CI SSH keypair generated in
    # ci-ssh-key.tf. local.ci_ssh_pubkey is trimspaced — see locals{}
    # block in ci-ssh-key.tf for the rationale.
    ci_ssh_public_key_openssh = local.ci_ssh_pubkey
    # #6178 — gates the "Bootstrap Inngest server on first boot" runcmd item via a
    # templatefile `%{ if web_colocate_inngest }` directive. Default false (dedicated
    # scheduler, ADR-100). Bool is load-bearing (see variables.tf).
    web_colocate_inngest = var.web_colocate_inngest
    # #6396 — TF-derived per-host Better Stack host_name, injected into the bootstrap
    # invocation (SOLEUR_HOST_NAME) and rendered into the ungated web-host vector.toml's
    # @@HOST_NAME@@ sentinel. MUST equal each host's server name (`name` above) so web-1 and
    # web-2 resolve to DISTINCT sources in the shared Logs source 2457081 — a generic/duplicate
    # OS hostname would collapse them. NOT runtime $(hostname): cloud-init sets no explicit
    # hostname:/fqdn: and relies on Hetzner seeding hostname=server-name, which is not guaranteed
    # distinct on a re-imaged host.
    host_name = each.key == "web-1" ? "soleur-web-platform" : "soleur-${each.key}"
    # #6448 — the fresh-host inline daemon.json derives its insecure-registries allowlist from
    # local.registry_endpoint (the single source, zot-registry.tf:44), same as the running-host
    # terraform_data.registry_insecure_config delivery. A subnet renumber propagates to both
    # host classes instead of drifting from a hardcoded copy.
    registry_endpoint = local.registry_endpoint
    # (#6459 Phase 2.2 PART 2) Per-host inputs for web-probe-envwrite.sh, which writes the 3
    # /etc/default/web-<probe> EnvironmentFiles on a fresh cattle host (the SSH remote-exec path
    # only reaches web-1). Values single-sourced from the SAME expressions the SSH provisioners use:
    #   web_probes_token — the read-scoped doppler_service_token.web_probes.key (adds ZERO marginal
    #     exposure over the full-prd doppler_token already in this map — web-probe-read-token.tf).
    #   expected_ip      — this host's declared private IP (the nic-guard's EXPECTED baseline; never
    #     the live NIC, which would defeat the guard). var.web_hosts[each.key].private_ip.
    #   web_host_key     — each.key ("web-1"/"web-2"); the env-writer upper-cases it to name the
    #     per-host Better Stack heartbeat URL var (WEB_NIC_GUARD_URL_WEB_2, …), matching the SSH
    #     provisioner's upper(replace(each.key,"-","_")).
    #   zot_probe_repo   — local.zot_probe_repo (web-probe.tf:22), the ZOT_PROBE_REPO env value.
    # betterstack_ingest_url + registry_endpoint are already in this map (reused, not re-added).
    web_probes_token = doppler_service_token.web_probes.key
    expected_ip      = var.web_hosts[each.key].private_ip
    web_host_key     = each.key
    zot_probe_repo   = local.zot_probe_repo
    # #6604 — pin /mnt/data to THIS host's workspaces volume by stable by-id device
    # (/dev/disk/by-id/scsi-0HC_Volume_${workspaces_volume_id}), never the scsi-0HC_Volume_*
    # glob: once the LUKS volume attaches, the glob matches TWO devices and the "which is LUKS"
    # predicate binds to the wrong one. Same by-id + nofail shape as cloud-init-git-data.yml,
    # cloud-init-inngest.yml, cloud-init-registry.yml (web-platform was the lone glob holdout).
    workspaces_volume_id = hcloud_volume.workspaces[each.key].id
    # #6441 — the address the first-boot NIC gate waits on, before `cloudflared service
    # install` registers this host as the tunnel's sole connector (ADR-114 I1). Single-sourced
    # from var.web_hosts per ADR-115's single-definition doctrine: a hardcoded literal in
    # cloud-init.yml would drift silently from variables.tf on a subnet renumber, and the gate
    # would then wait out its whole budget on an address that will never appear.
    #
    # NOT sourced from /etc/default/web-private-nic-guard: that file is written by an SSH
    # provisioner (below) which reaches RUNNING hosts only, so on the fresh boot this gate
    # exists for it does not yet exist. Reusing it would work on web-1 today and fail silently
    # on any future host — the worst failure shape.
    private_ip = each.value.private_ip
  }))

  # cloud-init and ssh_keys are create-time attributes. After import,
  # template interpolation differs from the original user_data, and
  # ssh_keys forces replacement. Both are safe to ignore (#967).
  # TODO: remove ignore_changes after clean reprovisioning (import artifact)
  #
  # placement_group_id — TEMPORARY GA-deferral (#5887, ADR-068 blue-green ingress
  # prereqs). web-1 pre-dates the web_spread group; attaching it to the RUNNING host
  # forces a Hetzner power-off reboot (see the placement_group_id comment above).
  # Ignoring it keeps the pending 0 -> web_spread attach OUT of every plan so the
  # destroy-guard `reboot_updates` counter (#5911) does not halt the targeted CI
  # applies — unwedging #5887 with ZERO reboot. web-2 was born INTO the group at
  # create time, so this defers ONLY web-1. REMOVE this entry in the GA maintenance-
  # window PR as its FIRST diff, then take the reboot on a drained host (blue-green).
  # Guarded by plugins/soleur/test/terraform-target-parity.test.ts so it is not
  # dropped silently.
  #
  # HARD GATE (ADR-068 §(c) / ADR-141 D3, the anti-pooling LB-weight gate) — the deferred cutover
  # orchestrator must NOT remove this entry or shift web-2's Cloudflare LB weight above 0 until the
  # programmatic gate (REBUILT 2026-07-24 with ADR-141 D3 / #6459 as `lb-weight-gate.sh`, after
  # #6575 deleted the original 2026-07-20 — see ADR-068 §(c) CORRECTION + ADR-141) exits 0 AND its
  # separate runtime-bind probe passes. The rebuilt gate is a fail-closed serving-weight TOP-GUARD:
  # web-2 weight==0/not-in-rotation PASSES (the standby state a correct pre-flip config is in — the
  # #6575 polarity flaw is fixed); web-2 weight>0 pre-flip runs the flip-authorization shape and
  # FAILS unless (1) owner-side relay active (SOLEUR_PROXY_BIND / SOLEUR_PROXY_PEER_ALLOWLIST /
  # SOLEUR_HOST_ROSTER), (2) git-data store cut over (GIT_DATA_STORE_ENABLED==true + GIT_DATA_LUKS
  # soak marker), AND (3) web-2 /workspaces LUKS-backed (WORKSPACES_LUKS soak marker — ADR-141 D3
  # coupling #2, so a plaintext web-2 cannot be pooled). Pooling web-2 before all three = a request
  # lands on a host without that user's /workspaces → empty workspace → "workspace-gone" single-user
  # incident. SHAPE-ONLY (prints requires_runtime_bind_probe=true) so exit 0 is NOT weight authorization.
  # Committed-config anti-pooling (dns.tf web-1-only, connector excludes web-2, no LB pools web-2) is
  # Condition C in lb-weight-gate.test.sh. See ADR-068 §(c) + ADR-141 + moved-block-wedge-cutover-5887.md §Scope B.
  lifecycle {
    ignore_changes = [user_data, ssh_keys, image, placement_group_id]
  }

  labels = {
    app = "soleur-web-platform"
  }
}

# Deploy disk-monitor.sh and systemd timer to the existing server.
# Cloud-init handles new servers; this provisioner handles the existing one
# (ignore_changes on user_data means cloud-init changes do not apply to it).
# Shows as "will be created" in CI drift reports -- expected behavior (#1409).
resource "terraform_data" "disk_monitor_install" {
  triggers_replace = sha256(join(",", [
    var.resend_api_key,
    file("${path.module}/disk-monitor.sh"),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "file" {
    source      = "${path.module}/disk-monitor.sh"
    destination = "/usr/local/bin/disk-monitor.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/disk-monitor.sh",
      "printf 'RESEND_API_KEY=%s\\n' '${var.resend_api_key}' > /etc/default/disk-monitor",
      "chmod 600 /etc/default/disk-monitor",
      "cat > /etc/systemd/system/disk-monitor.service << 'UNITEOF'\n[Unit]\nDescription=Disk space monitor\nAfter=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/disk-monitor.sh\nUNITEOF",
      "cat > /etc/systemd/system/disk-monitor.timer << 'TIMEREOF'\n[Unit]\nDescription=Run disk monitor every 5 minutes\n\n[Timer]\nOnBootSec=5min\nOnUnitActiveSec=5min\nPersistent=true\n\n[Install]\nWantedBy=timers.target\nTIMEREOF",
      "systemctl daemon-reload",
      "systemctl enable --now disk-monitor.timer",
      "systemctl list-timers disk-monitor.timer --no-pager",
    ]
  }
}

# Deploy resource-monitor.sh and systemd timer to the existing server.
# Cloud-init handles new servers; this provisioner handles the existing one
# (ignore_changes on user_data means cloud-init changes do not apply to it).
# Shows as "will be created" in CI drift reports -- expected behavior (#1052).
# Mirror of disk_monitor_install: same connection, trigger hash shape, and
# file/remote-exec invocation order. Keep both in sync.
resource "terraform_data" "resource_monitor_install" {
  triggers_replace = sha256(join(",", [
    var.resend_api_key,
    file("${path.module}/resource-monitor.sh"),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "file" {
    source      = "${path.module}/resource-monitor.sh"
    destination = "/usr/local/bin/resource-monitor.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/resource-monitor.sh",
      "printf 'RESEND_API_KEY=%s\\n' '${var.resend_api_key}' > /etc/default/resource-monitor",
      "chmod 600 /etc/default/resource-monitor",
      "cat > /etc/systemd/system/resource-monitor.service << 'UNITEOF'\n[Unit]\nDescription=Host CPU/RAM/session monitor\nAfter=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/resource-monitor.sh\nUNITEOF",
      "cat > /etc/systemd/system/resource-monitor.timer << 'TIMEREOF'\n[Unit]\nDescription=Run resource monitor every 5 minutes\n\n[Timer]\nOnBootSec=5min\nOnUnitActiveSec=5min\nPersistent=true\n\n[Install]\nWantedBy=timers.target\nTIMEREOF",
      "systemctl daemon-reload",
      "systemctl enable --now resource-monitor.timer",
      "systemctl list-timers resource-monitor.timer --no-pager",
    ]
  }
}

# Deploy container-restart-monitor.sh + units to the existing server (#5417).
# Cloud-init handles new servers; this provisioner handles the existing one
# (ignore_changes on user_data means cloud-init changes do not apply to it).
# Shows as "will be created" in CI drift reports -- expected behavior (#5417).
# Mirror of resource_monitor_install: same connection + trigger-hash shape. The
# .service/.timer are SHIPPED AS FILES (not heredoc'd) because the doppler-
# wrapped ExecStart's nested single-quotes do not survive a terraform inline
# heredoc; file() keeps triggers_replace and the delivered content in lockstep.
resource "terraform_data" "container_restart_monitor_install" {
  triggers_replace = sha256(join(",", [
    var.resend_api_key,
    file("${path.module}/container-restart-monitor.sh"),
    file("${path.module}/container-restart-monitor.service"),
    file("${path.module}/container-restart-monitor.timer"),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "file" {
    source      = "${path.module}/container-restart-monitor.sh"
    destination = "/usr/local/bin/container-restart-monitor.sh"
  }

  provisioner "file" {
    source      = "${path.module}/container-restart-monitor.service"
    destination = "/etc/systemd/system/container-restart-monitor.service"
  }

  provisioner "file" {
    source      = "${path.module}/container-restart-monitor.timer"
    destination = "/etc/systemd/system/container-restart-monitor.timer"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/container-restart-monitor.sh",
      "printf 'RESEND_API_KEY=%s\\n' '${var.resend_api_key}' > /etc/default/container-restart-monitor",
      "chmod 600 /etc/default/container-restart-monitor",
      "systemctl daemon-reload",
      "systemctl enable --now container-restart-monitor.timer",
      "systemctl list-timers container-restart-monitor.timer --no-pager",
    ]
  }
}

# --- #6438/#6548: web-host private-net consumer-probe + §3 NIC-guard delivery (web-1) ----------
# TERMINOLOGY (#6538 reconciliation, CPO C3): "unrebuildable" below means web-1 cannot be rebuilt
# by any AUTOMATED path. It does NOT contradict #6538, whose table lists
# `soleur-web-platform / cx33 / hel1 / rebuildable_in_place_today: YES` — that column is about the
# host's LOCATION being viable (web-2 was NO only because it sat in fsn1), not about a CI route
# existing. Both are true: an operator-local full `terraform apply` would succeed, and no
# CI/dispatch route reaches it. As of #6718 every automated route that can reach
# hcloud_server.web HALTs on host_creates > 0 — enumerated: apply-web-platform-infra.yml's
# `apply` (#6416), workspaces_luks_cutover (gate requires zero actions on the web-1
# server), and apply-deploy-pipeline-fix.yml (#6718). The warm_standby and
# web_2_recreate routes were REMOVED with the web-2 dispatch sweep (#6575,
# 2026-07-20), so the enumeration is three, not five. Scope: WEB hosts — inngest_host legitimately births a
# host and is unaffected. The gap is tracked by #6730 (it violates
# hr-fresh-host-provisioning-reachable-from-terraform-apply).
#
# The SSH terraform_data provisioner is the SOLE path that arms web-1 (see the terminology note
# above — "unrebuildable" here means no AUTOMATED path, not a stock constraint):
# ignore_changes=[user_data] (above) means cloud-init changes never reach it, and ci-deploy.sh
# re-seed installs NO host systemd units (verified :2331-2355). cloud-init.yml bakes the SAME
# scripts+units for FUTURE fresh hosts (#6459, A5). All three mirror disk_monitor_install (same
# connection + trigger-hash shape); units ship as FILES because their doppler-wrapped ExecStart's
# nested single-quotes do not survive a terraform inline heredoc (container_restart_monitor
# precedent, :357). Shows "will be created" in CI drift reports — expected (#1409-class).
#
# The `systemctl enable --now web-*.timer` lines below are the ARMING CONSTRUCTS that
# heartbeat-manifest.ts cites as executable feeder evidence (the parity guard greps them here).

# §3 private-NIC self-report (detect+emit+alarm, NO reboot). Its liveness beat (web_nic_guard) is
# pinged every healthy run so the SOLEUR_PRIVATE_NIC emitter is observable-when-healthy.
resource "terraform_data" "private_nic_guard_install" {
  # Reload Vector (Source 4 live on web-1) BEFORE (re)enabling the probe timers, so the first post-fix
  # FATAL/canary line ships instead of waiting a timer tick (probe-first intent; #6438/#6548 review).
  depends_on = [terraform_data.journald_persistent]

  triggers_replace = sha256(join(",", [
    file("${path.module}/web-private-nic-guard.sh"),
    file("${path.module}/web-private-nic-guard.service"),
    file("${path.module}/web-private-nic-guard.timer"),
    var.web_hosts["web-1"].private_ip,
    local.betterstack_logs_ingest_url,
    # Hash the read-scoped probe token so a `-replace` rotation re-fires delivery of the new key
    # into /etc/default/web-private-nic-guard. nonsensitive() on a one-way digest of the token
    # reveals nothing while keeping triggers_replace readable in plan output (#6438/#6548).
    nonsensitive(sha256(doppler_service_token.web_probes.key)),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key
    agent       = var.ci_ssh_private_key == null
  }

  provisioner "file" {
    source      = "${path.module}/web-private-nic-guard.sh"
    destination = "/usr/local/bin/web-private-nic-guard.sh"
  }
  provisioner "file" {
    source      = "${path.module}/web-private-nic-guard.service"
    destination = "/etc/systemd/system/web-private-nic-guard.service"
  }
  provisioner "file" {
    source      = "${path.module}/web-private-nic-guard.timer"
    destination = "/etc/systemd/system/web-private-nic-guard.timer"
  }
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/web-private-nic-guard.sh",
      # DOPPLER_TOKEN (read-scoped web_probes) + HOME=/root on the unit are the two-fold fix for the
      # unit-start failure: the root `doppler run` needs both to authenticate. No DOPPLER_CONFIG_DIR
      # (root uses /root/.doppler, never /tmp/.doppler — the #6536 clash surface). VERSION_CHECK off
      # matches every fleet doppler env file (avoids a per-fire egress version-check warning shipping
      # to Source 4 as noise). #6438 §3.
      # umask 0137 so the file is NEVER created world/group-readable — the env file now holds a live
      # prd read token (before this fix it held only URL key-names). Closes the sub-ms TOCTOU window
      # between create-at-default-umask and chmod (security review; precedent cloud-init-inngest.yml).
      "( umask 0137 && printf 'EXPECTED_IP=%s\\nBETTERSTACK_INGEST_URL=%s\\nWEB_NIC_GUARD_URL_KEY=%s\\nDOPPLER_TOKEN=%s\\nDOPPLER_ENABLE_VERSION_CHECK=false\\n' '${var.web_hosts["web-1"].private_ip}' '${local.betterstack_logs_ingest_url}' 'WEB_NIC_GUARD_URL_${upper(replace("web-1", "-", "_"))}' '${doppler_service_token.web_probes.key}' > /etc/default/web-private-nic-guard )",
      "chmod 600 /etc/default/web-private-nic-guard",
      "systemctl daemon-reload",
      "systemctl enable --now web-private-nic-guard.timer",
      "systemctl list-timers web-private-nic-guard.timer --no-pager",
    ]
  }
}

# §1 zot consumer serviceability probe.
resource "terraform_data" "zot_consumer_probe_install" {
  # Reload Vector before (re)enabling the timer (see private_nic_guard_install; probe-first ordering).
  depends_on = [terraform_data.journald_persistent]

  triggers_replace = sha256(join(",", [
    file("${path.module}/web-zot-consumer-probe.sh"),
    file("${path.module}/web-zot-consumer-probe.service"),
    file("${path.module}/web-zot-consumer-probe.timer"),
    local.registry_endpoint,
    local.zot_probe_repo,
    # Hash the read-scoped probe token so a `-replace` rotation re-fires delivery (see nic-guard).
    nonsensitive(sha256(doppler_service_token.web_probes.key)),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key
    agent       = var.ci_ssh_private_key == null
  }

  provisioner "file" {
    source      = "${path.module}/web-zot-consumer-probe.sh"
    destination = "/usr/local/bin/web-zot-consumer-probe.sh"
  }
  provisioner "file" {
    source      = "${path.module}/web-zot-consumer-probe.service"
    destination = "/etc/systemd/system/web-zot-consumer-probe.service"
  }
  provisioner "file" {
    source      = "${path.module}/web-zot-consumer-probe.timer"
    destination = "/etc/systemd/system/web-zot-consumer-probe.timer"
  }
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/web-zot-consumer-probe.sh",
      # DOPPLER_TOKEN (read-scoped web_probes) + HOME=/root on the unit are the two-fold unit-start
      # fix — see the web-private-nic-guard install above. #6438 §1.
      # umask 0137: never world/group-readable — the env file now holds a live prd read token (see nic-guard install).
      "( umask 0137 && printf 'ZOT_ENDPOINT=%s\\nZOT_PROBE_REPO=%s\\nWEB_ZOT_CONSUMER_URL_KEY=%s\\nDOPPLER_TOKEN=%s\\nDOPPLER_ENABLE_VERSION_CHECK=false\\n' '${local.registry_endpoint}' '${local.zot_probe_repo}' 'WEB_ZOT_CONSUMER_URL_${upper(replace("web-1", "-", "_"))}' '${doppler_service_token.web_probes.key}' > /etc/default/web-zot-consumer-probe )",
      "chmod 600 /etc/default/web-zot-consumer-probe",
      "systemctl daemon-reload",
      "systemctl enable --now web-zot-consumer-probe.timer",
      "systemctl list-timers web-zot-consumer-probe.timer --no-pager",
    ]
  }
}

# #6548 git-data reachability probe (fail-soft; arms the existing git_data_prd).
resource "terraform_data" "git_data_probe_install" {
  # Reload Vector before (re)enabling the timer (see private_nic_guard_install; probe-first ordering).
  depends_on = [terraform_data.journald_persistent]

  triggers_replace = sha256(join(",", [
    file("${path.module}/web-git-data-probe.sh"),
    file("${path.module}/web-git-data-probe.service"),
    file("${path.module}/web-git-data-probe.timer"),
    # Hash the read-scoped probe token so a `-replace` rotation re-fires delivery (see nic-guard).
    nonsensitive(sha256(doppler_service_token.web_probes.key)),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key
    agent       = var.ci_ssh_private_key == null
  }

  provisioner "file" {
    source      = "${path.module}/web-git-data-probe.sh"
    destination = "/usr/local/bin/web-git-data-probe.sh"
  }
  provisioner "file" {
    source      = "${path.module}/web-git-data-probe.service"
    destination = "/etc/systemd/system/web-git-data-probe.service"
  }
  provisioner "file" {
    source      = "${path.module}/web-git-data-probe.timer"
    destination = "/etc/systemd/system/web-git-data-probe.timer"
  }
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/web-git-data-probe.sh",
      # GIT_DATA_ENDPOINT mirrors the git-data SSH transport (git-data.tf); the script also defaults
      # to it. GIT_DATA_HEARTBEAT_URL is a SINGLE (non-for_each) secret, so the KEY is unsuffixed.
      # DOPPLER_TOKEN (read-scoped web_probes) + HOME=/root on the unit are the two-fold unit-start
      # fix — see the web-private-nic-guard install above. #6548.
      # umask 0137: never world/group-readable — the env file now holds a live prd read token (see nic-guard install).
      "( umask 0137 && printf 'GIT_DATA_ENDPOINT=%s\\nGIT_DATA_HEARTBEAT_URL_KEY=%s\\nDOPPLER_TOKEN=%s\\nDOPPLER_ENABLE_VERSION_CHECK=false\\n' '10.0.1.20:22' 'GIT_DATA_HEARTBEAT_URL' '${doppler_service_token.web_probes.key}' > /etc/default/web-git-data-probe )",
      "chmod 600 /etc/default/web-git-data-probe",
      "systemctl daemon-reload",
      "systemctl enable --now web-git-data-probe.timer",
      "systemctl list-timers web-git-data-probe.timer --no-pager",
    ]
  }
}

# Deploy fail2ban sshd tuning drop-in to the existing server (issue #2654).
# Caps bantime.increment recidivism at 1h so an operator typo against
# AllowUsers does not snowball into a multi-hour (or multi-day) SSH lockout.
# Cloud-init handles fresh servers; this provisioner handles the existing one
# (ignore_changes on user_data means cloud-init changes do not apply to it).
# Source of truth for jail content: fail2ban-sshd.local (sibling file).
# Shows as "will be created" in CI drift reports -- expected behavior.
# Runbook for acute lockout recovery: knowledge-base/engineering/operations/runbooks/ssh-fail2ban-unban.md
#
# Why the jail carries `ignoreip = ... 10.0.1.0/24` (#6594). The rationale lives here, not in
# the .local file: that file is base64'd into user_data whole (see the keep-inline note above),
# so its comments are byte-budgeted while .tf comments are free.
#
# Until #6594 pinned the tunnel ingress, `ssh.` resolved to `ssh://localhost:22`, so sshd saw
# every tunnelled CI login as 127.0.0.1 — covered by fail2ban's default loopback ignore. Pinning
# the ingress to web-1's private IP means a PEER connector (web-2, 10.0.1.11) now proxies in from
# a REAL source address, which `ignoreself` does not cover (it covers only web-1's own IPs).
#
# Without the grant, a key-mismatch window (`-replace=tls_private_key.ci_ssh`, or a fresh web-1
# before root_authorized_keys lands) puts >=5 failures in 10m from 10.0.1.11 and bans it —
# killing `ssh.` for the ~half of CF colos routed via that connector, for 10m rising to 1h. That
# is a failure AMPLIFIER on the one path with no in-band recovery: ssh-fail2ban-unban.md calls a
# fail2ban lockout "the one operator task where the Hetzner Cloud Console (noVNC) is the only
# tool".
#
# The private net is not an attack surface fail2ban should police: it is unreachable from the
# internet (firewall.tf admits only 22/80/443/icmp on the public interface), and its only members
# are our own hosts.
#
# SCOPE: this grant exists because a peer connector proxies to web-1. It is web-2-lifetime-scoped.
# #6538 retired the fsn1 .11 orphan (removing the only peer, making the clause momentarily
# vestigial), but web-2 was RE-ADDED 2026-07-24 (ADR-141, #6459) as a fresh cattle standby at
# 10.0.1.11 — so the 10.0.1.0/24 grant is LIVE again (a peer connector from web-2 must not be
# fail2ban-banned). Re-evaluate only if web-2 is ever removed.
resource "terraform_data" "fail2ban_tuning" {
  triggers_replace = sha256(file("${path.module}/fail2ban-sshd.local"))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  # Ensure fail2ban is installed before dropping the jail.d override. The
  # existing server is an import-era artifact -- cloud-init's `packages:`
  # step never re-ran after import (ignore_changes = [user_data]), and the
  # initial run appears to have failed silently (#2680). `dpkg -s` makes this
  # idempotent: on servers where fail2ban is already installed (fresh
  # cloud-init provisioning) the install branch is skipped.
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "dpkg -s fail2ban >/dev/null 2>&1 || { export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq fail2ban; }",
      # Positive post-install re-verification mirrors the cloud-init audit
      # (see runcmd in cloud-init.yml). Catches the rare case where apt
      # reports success but dpkg leaves the package in a half-configured
      # state; also gives a clear error message if a future edit breaks the
      # install branch above (e.g., a typo'd package name).
      "dpkg -s fail2ban >/dev/null 2>&1 || { echo 'FATAL: fail2ban still not installed after install attempt' >&2; exit 1; }",
    ]
  }

  # The `remote-exec` above ensures the package is installed first. On the
  # existing server (which was imported with ignore_changes = [user_data])
  # cloud-init's packages: step never re-ran, so fail2ban may be missing (#2680).
  provisioner "file" {
    source      = "${path.module}/fail2ban-sshd.local"
    destination = "/etc/fail2ban/jail.d/soleur-sshd.local"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chown root:root /etc/fail2ban/jail.d/soleur-sshd.local",
      "chmod 0644 /etc/fail2ban/jail.d/soleur-sshd.local",
      # Reload picks up jail.d drop-ins without dropping active bans; fall back
      # to restart if the installed fail2ban version does not support reload of
      # bantime.* keys (some 0.10.x builds required restart; 1.0.2 on 24.04 is fine).
      "systemctl reload fail2ban || systemctl restart fail2ban",
      # Diagnostic dump (informational; printed to CI drift logs).
      "fail2ban-client -d | grep -A5 '\\[sshd\\]' | head -20 || true",
      # Positive assertions: if the drop-in did NOT take effect, these values
      # would still report the defaults-debian.conf values. Asserting the
      # literal expected values fails the provisioner when the override is
      # silently ignored (jail.d load-order regression, syntax error swallowed
      # by reload, etc.). 600s = 10m; 3600s = 1h.
      "test \"$(fail2ban-client get sshd bantime)\" = '600'",
      "test \"$(fail2ban-client get sshd maxretry)\" = '5'",
      "test \"$(fail2ban-client get sshd findtime)\" = '600'",
    ]
  }
}

# Make systemd-journald persistent + bounded on the existing server (#4792, #4773).
# PR #4786 moved the soleur-web-platform container to `--log-driver journald`, so
# the host journal must persist across reboots (else Vector's 3 journald sources
# read an empty /var/log/journal post-reboot) and be sized so it can never fill /.
# Cloud-init handles fresh servers; this provisioner handles the existing one
# (ignore_changes on user_data means cloud-init changes never apply to it — so a
# cloud-init-only edit would land dead config; this SSH path is the sole live-prod
# apply path). Source of truth for the drop-in: journald-soleur.conf (sibling
# file, also rendered into cloud-init via base64encode(file()) — keep both in
# sync). Shows as "will be created" in CI drift reports -- expected behavior, same
# as the 6 sibling SSH provisioners. SSH connection precedent: disk_monitor_install.
# Positive-assertion precedent: fail2ban_tuning (prove persistence took, don't
# just observe it). Apply-path firewall note: SSH:22 is allowlisted to
# var.admin_ips only (firewall.tf; CI-deploy SSH rule removed in #749), so the
# handshake succeeds iff the operator/CI egress IP ∈ admin_ips. A
# `connection reset by peer` here is admin-IP drift (fix: /soleur:admin-ip-refresh,
# runbook admin-ip-drift.md), NOT an sshd/journald fault — per hr-ssh-diagnosis-verify-firewall.
resource "terraform_data" "journald_persistent" {
  # Also hashes vector.toml so an edit to the Vector config (e.g. adding the web-host probe
  # SyslogIdentifiers to Source 4) re-fires this provisioner and re-delivers + reloads Vector on
  # the running web-1. web-1 installs Vector ONLY at cloud-init boot and never re-runs cloud-init
  # (ignore_changes=[user_data]), so without this fold a vector.toml change is file-only, never live
  # on the host — the exact gap that kept the 3 probe units' FATAL stderr off Better Stack. #6438/#6548.
  triggers_replace = sha256(join(",", [
    file("${path.module}/journald-soleur.conf"),
    file("${path.module}/vector.toml"),
  ]))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  # The drop-in dir does NOT exist by default on Ubuntu — systemd ships
  # /etc/systemd/journald.conf but not the journald.conf.d/ subdir, and the
  # `file` provisioner (scp) does not create remote parents. On the existing
  # host cloud-init's write_files (which would create the dir) never runs
  # (ignore_changes=[user_data]), so this mkdir is load-bearing: without it the
  # very first apply fails at scp `No such file or directory`. Mirrors the
  # fail2ban_tuning pre-`file` remote-exec that guarantees its target dir exists.
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "mkdir -p /etc/systemd/journald.conf.d",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/journald-soleur.conf"
    destination = "/etc/systemd/journald.conf.d/00-soleur.conf"
  }

  # #6438/#6548: stage the shared vector.toml (with the @@HOST_NAME@@ sentinel) so the remote-exec
  # below can render THIS host's Better Stack host_name and re-deliver it to the running Vector
  # agent. Same live-prod-only apply path as the journald drop-in above.
  provisioner "file" {
    source      = "${path.module}/vector.toml"
    destination = "/tmp/soleur-vector.toml.staged"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chown root:root /etc/systemd/journald.conf.d/00-soleur.conf",
      "chmod 0644 /etc/systemd/journald.conf.d/00-soleur.conf",
      # Create the persistent journal dir with journald's expected ownership +
      # ACLs. systemd-tmpfiles applies the packaged tmpfiles.d/systemd.conf rule
      # for /var/log/journal (0755 root:systemd-journal + setgid + read ACLs);
      # mkdir -p first so the rule has a dir to adjust. Both idempotent.
      "mkdir -p /var/log/journal",
      "systemd-tmpfiles --create --prefix /var/log/journal",
      # Restart picks up the Storage=persistent + cap drop-in; flush migrates the
      # volatile /run journal into /var/log/journal. Sub-second daemon restart;
      # buffered logs are flushed, not lost. No container/app/Vector restart:
      # Vector's journald sources read by sd_journal cursor (not file path) and
      # are restart/rotation-tolerant, so they resume from their stored cursor
      # with no gap beyond the sub-second window. Resumption is verified
      # out-of-band (no SSH) post-apply via the cat-deploy-state webhook —
      # vector_journal_tail non-empty + journald_storage.persistent=true.
      "systemctl restart systemd-journald",
      "journalctl --flush",
      # Diagnostic dump (informational; printed to CI drift logs).
      "systemd-analyze cat-config systemd/journald.conf | grep -E '^(Storage|SystemMaxUse|SystemKeepFree|RuntimeMaxUse)=' || true",
      # Positive assertions (fail2ban_tuning pattern): if the drop-in did NOT take
      # effect, journald would still be volatile and these would fail the
      # provisioner instead of silently shipping dead config.
      "test -d /var/log/journal",
      # --header lists active journal files with their paths; a persistent journal
      # has files under /var/log/journal. Volatile-only journals list /run paths.
      "journalctl --header | grep -q '/var/log/journal'",
      "test \"$(systemctl is-active systemd-journald)\" = 'active'",
      # --- #6438/#6548: re-deliver vector.toml + reload the Vector agent on the running web-1 ------
      # Render the @@HOST_NAME@@ sentinel to THIS host's TF-derived Better Stack host_name (the SAME
      # value cloud-init passes as SOLEUR_HOST_NAME → soleur-host-bootstrap.sh; server.tf:237), write
      # it to /etc/vector/vector.toml, and restart the agent so Source 4's new probe SyslogIdentifiers
      # (web-zot-consumer-probe / web-git-data-probe / web-nic-guard) go live. Vector's journald
      # sources read by sd_journal cursor and resume after a sub-second restart with no gap. The
      # positive assertions below fail the apply loud if the probe tags did not land or the agent did
      # not come back — never ship dead config (the fail2ban_tuning/journald positive-assert pattern).
      "install -d -m 0755 /etc/vector /opt/soleur",
      "sed 's|@@HOST_NAME@@|${hcloud_server.web["web-1"].name}|g' /tmp/soleur-vector.toml.staged > /opt/soleur/vector.toml",
      # Render-sanity gate BEFORE we touch the live agent: a botched render (empty sed output,
      # unsubstituted sentinel, missing sink) must fail the apply while the RUNNING vector stays up —
      # a dead vector on web-1 darkens ALL host observability, a far bigger blast than the 3 probes.
      # (A full `vector validate` is not used here: it would false-fail on the unset
      # ${BETTERSTACK_LOGS_TOKEN} env interpolation — vector.service injects it via doppler run, this
      # remote-exec has no such env. The committed vector.toml is already CI-validated TOML, and the
      # only runtime transform is the @@HOST_NAME@@ string substitution.) #6438/#6548 review.
      "test -s /opt/soleur/vector.toml",
      "! grep -q '@@HOST_NAME@@' /opt/soleur/vector.toml",
      "grep -q '\\[sinks.betterstack\\]' /opt/soleur/vector.toml",
      "grep -q 'web-zot-consumer-probe' /opt/soleur/vector.toml",
      "install -m 0644 /opt/soleur/vector.toml /etc/vector/vector.toml",
      "rm -f /tmp/soleur-vector.toml.staged",
      "systemctl restart vector.service",
      "grep -q 'web-zot-consumer-probe' /etc/vector/vector.toml",
      "grep -q 'web-git-data-probe' /etc/vector/vector.toml",
      "grep -q 'web-nic-guard' /etc/vector/vector.toml",
      "test \"$(systemctl is-active vector.service)\" = 'active'",
    ]
  }
}

# #6005: deliver the pinned cosign trusted root to the RUNNING host byte-for-byte
# (the fresh-host copy comes from the baked host_script_files set + soleur-host-
# bootstrap.sh). ci-deploy.sh mounts /etc/soleur/cosign-trusted-root.json :ro into
# the ephemeral cosign verifier (ADR-087). Public trust material, not a secret.
# Mirrors terraform_data.journald_persistent: file() keeps triggers_replace and the
# delivered content in lockstep; the pre-`file` mkdir is load-bearing because the
# `file` provisioner (scp) does not create remote parents and cloud-init's write_files
# never re-runs on the existing host (ignore_changes=[user_data]).
resource "terraform_data" "cosign_trusted_root" {
  triggers_replace = sha256(file("${path.module}/cosign-trusted-root.json"))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "mkdir -p /etc/soleur",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/cosign-trusted-root.json"
    destination = "/etc/soleur/cosign-trusted-root.json"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chown root:root /etc/soleur/cosign-trusted-root.json",
      "chmod 0644 /etc/soleur/cosign-trusted-root.json",
      # Positive assertions: the file landed and is a valid sigstore trusted root
      # (has certificateAuthorities) — a truncated/empty scp would else ship silently
      # and every deploy's cosign verify would fail-open in WARN.
      "test -s /etc/soleur/cosign-trusted-root.json",
      "grep -q certificateAuthorities /etc/soleur/cosign-trusted-root.json",
    ]
  }
}

# #6122/ADR-096 (Edge A, RUNNING hosts): deliver the canonical docker daemon.json — which
# now allowlists the plain-HTTP private-net zot registry under insecure-registries — to the
# ALREADY-RUNNING web host and hot-reload dockerd. The allowlisted endpoint is DERIVED from
# local.registry_endpoint (the single source, zot-registry.tf:44) via local.docker_daemon_json
# below: the delivered daemon.json is rendered from docker-daemon.json.tmpl, so a subnet
# renumber propagates here automatically instead of drifting from a hardcoded copy (#6448).
# Fresh hosts get the same DERIVED content from cloud-init.yml's daemon.json write (task 3.0a);
# a running host has NO cloud-init re-run path (lifecycle ignore_changes=[user_data]), so this
# SSH provisioner is the ONLY running-host delivery — mirrors terraform_data.journald_persistent
# / cosign_trusted_root. HIGH-RISK (mutates the prod docker daemon), so:
#   (a) validate the delivered JSON parses BEFORE reloading — a malformed daemon.json makes
#       dockerd refuse the reload AND fail the NEXT restart (boot-bricking); the guard aborts
#       the apply with dockerd untouched (still on its valid in-memory config); and
#   (b) `systemctl reload docker` (SIGHUP) — NOT restart — so running containers
#       (app/inngest/redis) are NOT bounced mid-deploy; dockerd applies insecure-registries
#       on reload.
# This is the ONE #6122 resource that is CI-`-target`ed: it bridges over SSH to the existing
# host (like journald), so it rides the apply-web-platform-infra.yml SSH `-target` list + the
# terraform-target-parity SSH-provisioned set — NOT OPERATOR_APPLIED_EXCLUSIONS (the git-data
# model of the other 24 #6122 resources). See apply-path-cto-ruling.md §"Two load-bearing
# conditions" #1: an SSH-provisioned terraform_data MUST be in the `-target` list.
locals {
  # #6448 — the delivered docker daemon.json derives its insecure-registries allowlist from
  # local.registry_endpoint (the single source, zot-registry.tf:44), so a subnet renumber
  # propagates to every copy automatically instead of drifting silently (the #6400 shape).
  # docker-daemon.json.tmpl renders BYTE-IDENTICAL to the prior static file at the current
  # endpoint value, so sha256(local.docker_daemon_json) == the prior sha256(file(...)) value
  # ⇒ triggers_replace is unchanged ⇒ zero replace/churn on the running fleet.
  docker_daemon_json = templatefile("${path.module}/docker-daemon.json.tmpl", {
    registry_endpoint = local.registry_endpoint
  })
}

resource "terraform_data" "registry_insecure_config" {
  triggers_replace = sha256(local.docker_daemon_json)

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "mkdir -p /etc/docker",
    ]
  }

  provisioner "file" {
    # content= (not source=): the delivered daemon.json is RENDERED from the .tmpl (a string),
    # so it cannot be shipped as an on-disk source. content scps the rendered string over the
    # same connection {}. This is the first content= file-provisioner in this repo — non-secret
    # rendered content, so no base64 heredoc (that pattern exists only to protect SECRET
    # interpolation; a public host:port needs no such guard). See #6448.
    content     = local.docker_daemon_json
    destination = "/etc/docker/daemon.json"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      # Malformed-JSON guard: parse the DELIVERED file before touching dockerd. A config
      # that does not parse makes `systemctl reload docker` a no-op AND bricks the next
      # restart — abort here (file delivered, daemon untouched) rather than reload a
      # broken config. python3 is base-Ubuntu-guaranteed on the Hetzner image.
      "python3 -c 'import json; json.load(open(\"/etc/docker/daemon.json\"))'",
      "chown root:root /etc/docker/daemon.json",
      "chmod 0644 /etc/docker/daemon.json",
      # SIGHUP reload (NOT restart): dockerd applies insecure-registries live without
      # bouncing running containers. A restart would kill the app/inngest/redis mid-deploy.
      "systemctl reload docker",
      # Assert dockerd now honors the private-net zot registry as insecure (fail loud if
      # the reload silently did not pick it up). Endpoint DERIVED from local.registry_endpoint
      # (#6448) so this probe follows a subnet renumber automatically; -qF = fixed-string so
      # the '.'/':' are literal.
      "docker info 2>/dev/null | grep -qF '${local.registry_endpoint}'",
    ]
  }
}

# Handler-bootstrap bridge: deliver infra-config-apply.sh (the /hooks/infra-config
# webhook handler) + cat-infra-config-state.sh + the rendered hooks.json directly
# to the running host over SSH (#4811, Ref #4804).
#
# WHY THIS EXISTS (the chicken-and-egg this closes): the handler reaches the host
# only via (1) cloud-init write_files — dead on the existing host because
# hcloud_server.web carries ignore_changes=[user_data], so cloud-init never
# re-applies — and (2) deploy_pipeline_fix's triggers_replace hash, which re-fires
# push-infra-config.sh. But push-infra-config.sh pushes the OTHER 7 files and does
# NOT send infra-config-apply.sh (the handler is not in its payload nor in the
# handler's own FILE_MAP — it cannot deliver itself by construction). Net: a
# handler/hooks.json drift on the host was UNRECOVERABLE through the webhook path,
# because the recovery itself routes through the stale handler (the #4804 freeze).
# SSH is the only path that can deliver the handler TO a host where the handler is
# broken. PR #4805 made the handler fail loud, but a fix can only take effect on a
# host that receives the new handler — this resource is that delivery path.
#
# WHY SSH IS NOT A #3756 REGRESSION: #3756 replaced ONLY deploy_pipeline_fix's SSH
# provisioner with the webhook, to keep the *routine* deploy-config push HTTPS-only.
# SSH was never removed from the stack — 8 sibling terraform_data resources here
# still use connection{type="ssh"} today (disk_monitor_install, resource_monitor_install,
# fail2ban_tuning, journald_persistent, docker_seccomp_config, apparmor_bwrap_profile,
# orphan_reaper_install). This is a HYBRID of the established siblings: the
# connection block + positive post-write assertions + service restart are
# journald_persistent's shape, while the multi-input `sha256(join(...))`
# triggers_replace and the base64 secret-render are deploy_pipeline_fix's /
# disk_monitor_install's (a secret-bearing local.hooks_json cannot be a single
# `file()`). Do NOT "simplify" the multi-input trigger to journald's single-file()
# form — it legitimately tracks 3 inputs. NOT a reversal of #3756's routine-push
# decision.
#
# RUNNING-HOST-ONLY: unlike deploy_pipeline_fix this resource has NO cloud-init
# mirror — fresh hosts get the handler from cloud-init write_files
# (cloud-init.yml, search "path: /usr/local/bin/infra-config-apply.sh") directly.
# Do NOT add a redundant cloud-init block.
#
# DUAL-FIRE IS INTENTIONAL: infra-config-apply.sh, cat-infra-config-state.sh, and
# local.hooks_json appear in BOTH this triggers_replace AND deploy_pipeline_fix's.
# A handler edit re-fires both — deploy_pipeline_fix re-pushes the other 7 files,
# while THIS resource is the only one that actually delivers the handler. Do not
# "dedupe" them.
#
# SYNCHRONOUS RESTART: the webhook restart below is direct (systemctl restart),
# unlike the handler's own deferred self-restart (systemd-run --on-active=3s). The
# handler must defer because it IS exec'd by the webhook binary (killing webhook
# kills the in-flight response). This SSH path is independent of the webhook
# process (SSH = root over :22; webhook = deploy user on 127.0.0.1:9000), so it
# can restart + assert active immediately. Do NOT copy the deferred-restart dance.
#
# Shows as "will be created" in CI drift reports -- expected behavior, same as the
# 8 sibling SSH provisioners. Apply-path firewall note: SSH:22 is allowlisted to
# var.admin_ips only (firewall.tf) for DIRECT-IP dials. The OPERATOR-LOCAL apply
# dials the direct IP, so its handshake succeeds iff the operator egress IP ∈
# admin_ips. A `connection reset by peer` on the operator path is admin-IP drift
# (fix: /soleur:admin-ip-refresh, runbook admin-ip-drift.md), NOT an sshd/handler
# fault — per hr-ssh-diagnosis-verify-firewall.
#
# #4829 — CI ACCESS IS VIA THE CLOUDFLARE TUNNEL, NOT admin_ips. The GitHub-hosted
# runner egress IP is non-static and NOT in admin_ips, so `apply-deploy-pipeline-fix.yml`
# reaches this bridge over the existing CF Tunnel SSH route (tunnel.tf: ssh://localhost:22
# ingress + CF Access ci_ssh service token) instead of the firewall-gated direct IP.
# The runner opens a `cloudflared access tcp` localhost forward and an
# `iptables -t nat OUTPUT REDIRECT` rule rewrites SERVER_IP:22 → 127.0.0.1:2222,
# so the inbound SSH arrives at sshd via the host-side cloudflared daemon and never
# traverses the :22 admin_ips ingress rule (firewall byte-unchanged). This bridge IS
# now in apply-deploy-pipeline-fix.yml's -target= set; a CI handshake failure here is
# either a missing/stale CI key in root's authorized_keys (terraform_data.root_authorized_keys,
# operator-local-apply only) or an expired ci_ssh CF Access token — NOT admin-IP drift.
#
# #4827 ADDITION: this bridge also delivers infra-config-install.sh (the pinned
# root-run escalation helper) + the updated deploy-inngest-bootstrap.sudoers (with
# the INFRA_CONFIG_INSTALL grant) over root SSH. This is load-bearing for the
# chicken-and-egg: the webhook handler's prod-mode escalation needs BOTH the helper
# binary AND the sudoers alias present on-host before `sudo infra-config-install`
# is permitted — but the handler cannot deliver either (the helper is deliberately
# OUT of the webhook FILE_MAP, and writing the sudoers itself requires the alias).
# Root SSH is the only non-circular bootstrap path. #4829 — deploy_pipeline_fix does
# NOT depends_on this resource; both are listed as explicit -target=s in
# apply-deploy-pipeline-fix.yml and apply on the same CI run. Ordering between the SSH
# helper/sudoers delivery and the webhook push is handled by the handler's per-file
# install_rejected self-heal (see the deploy_pipeline_fix depends_on rationale below).
resource "terraform_data" "infra_config_handler_bootstrap" {
  triggers_replace = sha256(join(",", [
    file("${path.module}/infra-config-apply.sh"),
    file("${path.module}/infra-config-install.sh"),
    file("${path.module}/deploy-inngest-bootstrap.sudoers"),
    file("${path.module}/cat-infra-config-state.sh"),
    local.hooks_json,
  ]))

  # #4829 — DUAL-CONTEXT connection. Two apply paths reach this bridge:
  #   (1) operator-local full `terraform apply` — var.ci_ssh_private_key is unset
  #       (null), so agent = true uses the operator's ssh-agent (their key is
  #       already in root's authorized_keys). Byte-equivalent to the pre-#4829
  #       behavior.
  #   (2) CI `apply-deploy-pipeline-fix.yml` over the Cloudflare Tunnel —
  #       TF_VAR_ci_ssh_private_key carries Doppler DEPLOY_SSH_PRIVATE_KEY, so
  #       agent = false and the Go SSH client authenticates with that explicit
  #       key. The runner has no ssh-agent; the host trusts the matching pubkey
  #       via terraform_data.root_authorized_keys (ci-ssh-key.tf).
  # connection.host stays the literal ipv4_address in BOTH paths — the CI runner
  # transparently redirects SERVER_IP:22 → 127.0.0.1:2222 (the cloudflared TCP
  # forward) via an `iptables -t nat OUTPUT REDIRECT` rule, invisible to the Go
  # SSH client (which does NOT read ~/.ssh/config / ProxyCommand — see learning
  # 2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md).
  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  # The two scripts are on-disk files → straight scp. hooks.json is NOT: it is a
  # templatefile() render with var.webhook_deploy_secret interpolated (the on-disk
  # file is the .tmpl, not the rendered output — same trap push-infra-config.sh
  # documents), so it cannot be a provisioner "file" source. It is written via the
  # remote-exec base64 heredoc below, exactly as push-infra-config.sh passes
  # HOOKS_JSON_B64.
  provisioner "file" {
    source      = "${path.module}/infra-config-apply.sh"
    destination = "/usr/local/bin/infra-config-apply.sh"
  }

  provisioner "file" {
    source      = "${path.module}/cat-infra-config-state.sh"
    destination = "/usr/local/bin/cat-infra-config-state.sh"
  }

  # #4827 — the escalation helper. Delivered here (root SSH) because the webhook
  # handler that depends on it cannot deliver it (it is OUT of the FILE_MAP).
  provisioner "file" {
    source      = "${path.module}/infra-config-install.sh"
    destination = "/usr/local/bin/infra-config-install"
  }

  # #4827 — the sudoers grant (with the new INFRA_CONFIG_INSTALL alias). Staged to
  # a temp path then visudo-validated + installed below; writing it directly would
  # risk a half-written file in /etc/sudoers.d. The handler ALSO carries this file
  # in its FILE_MAP, but the webhook self-heal of the sudoers is circular on the
  # first apply (escalating its write needs the alias this file adds), so root SSH
  # bootstraps it.
  provisioner "file" {
    source      = "${path.module}/deploy-inngest-bootstrap.sudoers"
    destination = "/tmp/deploy-inngest-bootstrap.sudoers.staged"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      # Render hooks.json from the secret-bearing local value (base64 so the
      # interpolated content survives the inline string; sensitive interpolation
      # in remote-exec is the same mechanism disk_monitor_install uses for
      # var.resend_api_key — Terraform only refuses it in local-exec's command).
      "printf '%s' '${base64encode(local.hooks_json)}' | base64 -d > /etc/webhook/hooks.json",
      # Ownership/permissions: scripts root:root 0755, hooks.json root:deploy 0640
      # (match cloud-init.yml write_files for these paths).
      "chown root:root /usr/local/bin/infra-config-apply.sh /usr/local/bin/cat-infra-config-state.sh /usr/local/bin/infra-config-install",
      "chmod 0755 /usr/local/bin/infra-config-apply.sh /usr/local/bin/cat-infra-config-state.sh /usr/local/bin/infra-config-install",
      "chown root:deploy /etc/webhook/hooks.json",
      "chmod 0640 /etc/webhook/hooks.json",
      # #4827 — validate then atomically install the sudoers grant. visudo -cf
      # gates a malformed file from disabling sudo entirely; install does an
      # owner/mode-correct atomic placement. Fail the provisioner on a bad file
      # rather than ship a broken /etc/sudoers.d.
      "visudo -cf /tmp/deploy-inngest-bootstrap.sudoers.staged",
      "install -o root -g root -m 0440 /tmp/deploy-inngest-bootstrap.sudoers.staged /etc/sudoers.d/deploy-inngest-bootstrap",
      "rm -f /tmp/deploy-inngest-bootstrap.sudoers.staged",
      # Synchronous restart (safe — this SSH path is not the webhook process).
      "systemctl restart webhook",
      # Positive post-write assertions (journald_persistent / fail2ban_tuning
      # pattern): prove the bootstrap took, don't just observe it. A failed
      # assertion fails the provisioner instead of silently shipping dead config.
      "test -x /usr/local/bin/infra-config-apply.sh",
      "test -x /usr/local/bin/cat-infra-config-state.sh",
      "test -x /usr/local/bin/infra-config-install",
      # The sudoers grant landed and parses (the INFRA_CONFIG_INSTALL alias is
      # what makes the webhook handler's prod-mode escalation work).
      "grep -q INFRA_CONFIG_INSTALL /etc/sudoers.d/deploy-inngest-bootstrap",
      # #5934 — the char-device sweep grant landed (without it ci-deploy.sh's
      # pre-canary sweep is sudo-denied and the durable #5912 wedge remediation is
      # a silent no-op). Fail the provisioner loud rather than ship it missing.
      "grep -q GIT_LOCK_CHARDEVICE_SWEEP /etc/sudoers.d/deploy-inngest-bootstrap",
      # hooks.json re-registers the status hook + maps the state-reporter key (the
      # exact host drift that caused the #4804 freeze: stale hooks.json had neither).
      "grep -q infra-config-status /etc/webhook/hooks.json",
      "grep -q cat_infra_config_state_sh_b64 /etc/webhook/hooks.json",
      # The webhook listener restarted cleanly and is serving.
      "test \"$(systemctl is-active webhook)\" = 'active'",
    ]
  }
}

# Fix deploy pipeline: push current ci-deploy.sh, update webhook.service
# (EnvironmentFile + ReadWritePaths=/var/lock), and delete stale /mnt/data/.env.
# Cloud-init handles new servers; this provisioner fixes the existing one
# (ignore_changes on user_data means cloud-init changes do not apply to it).
# Shows as "will be created" in CI drift reports -- expected behavior (#1409).
# Source of truth for webhook.service: cloud-init.yml (search "path: /etc/systemd/system/webhook.service").
# The standalone webhook.service file keeps triggers_replace and the file provisioner in sync.
#
# NOTE (#2205): ci-deploy.sh, cat-deploy-state.sh, canary-bundle-claim-check.sh,
# and hooks.json are ALSO provisioned via cloud-init write_files for fresh
# servers. See cloud-init.yml (search "path: /usr/local/bin/ci-deploy.sh",
# "/usr/local/bin/cat-deploy-state.sh", "/usr/local/bin/canary-bundle-claim-check.sh").
# Both paths must stay in sync — a change here without updating cloud-init.yml
# means new servers provisioned from scratch will miss the change.
resource "terraform_data" "deploy_pipeline_fix" {
  # AppArmor profile must be loaded before ci-deploy.sh references it (#1570).
  #
  # #5515 — DO depend on the infra_config_handler_bootstrap bridge. Both are
  # applied by `apply-deploy-pipeline-fix.yml` (it lists each EXPLICITLY in its
  # `-target=` set), but `-target` does NOT impose ordering — Terraform orders
  # only by the declared dependency graph. With no edge, the two terraform_data
  # resources applied in arbitrary/graph-parallel order, so on a merge that BOTH
  # adds a new webhook-written FILE_MAP file (a new entry in infra-config-apply.sh's
  # FILE_MAP + a new env key in hooks.json) AND fires this push, the push could run
  # against the host's STALE handler+hooks.json. The new file's env var is then
  # unset on the stale hooks.json, so the handler's per-file `missing_env` arm
  # (infra-config-apply.sh:106-112, the #4804 self-heal window) records a failure,
  # the file does not land, and the op that reads it (e.g. op=inventory) 500s — it
  # lands ONE APPLY LATE, on the next unrelated apply. The bridge is the SOLE
  # delivery path for the handler + hooks.json, so this edge forces Terraform to
  # recreate the bridge (current handler + current hooks.json) BEFORE the push.
  #
  # This is a CORRECTION, not a reversal of a still-valid decision. The earlier
  # #4827/#4829 rationale (no edge; the per-file install_rejected self-heal handles
  # ordering) is STILL TRUE for the helper + sudoers files — those
  # are root-managed, NOT in the webhook FILE_MAP, and their missing-on-host failure
  # mode IS `install_rejected`. But the webhook-written FILE_MAP file class only
  # appeared with the #5492 inngest cutover scripts, AFTER that comment was written;
  # those files fail via the DIFFERENT `missing_env` arm, which self-heals only once
  # the bridge-delivered hooks.json + handler are current. So the old comment was
  # silent on this ordering, not wrong about helper/sudoers.
  #
  # Accepted trade-off (the over-coupling the old comment feared): an operator-local
  # full apply that replaces deploy_pipeline_fix now also recreates the idempotent,
  # assertion-gated bridge — including a sub-second bounce of the `webhook` listener
  # restart (server.tf:529) — even when only an UNRELATED hashed trigger changed
  # (e.g. a ci-deploy.sh edit, one of this resource's ~18 hashed triggers). This is
  # acceptable: a handler edit ALREADY re-fires both via the dual-fire triggers_replace
  # (server.tf:396-400), and the bridge's remote-exec is idempotent.
  #
  # Secondary benefit: the edge also serializes the bridge's synchronous
  # webhook-listener restart (server.tf:529, an existing Terraform-managed remote-exec)
  # BEFORE this push's `provisioner "local-exec"` below. This NARROWS the connection-
  # reset window but does NOT close it — the ordering is a happens-before on Terraform's
  # graph, not a wait-for-ready on the listener. nonce-1 (#6313, 2026-07-10;
  # push-infra-config.sh:25-31) is the counterexample: the bridge's `systemctl restart
  # webhook` returned ~10ms BEFORE the push fired, yet the webhook was still coming up,
  # so the push RACED the mid-flight restart — it got HTTP 202 from the restarting
  # listener but the async handler exec was disrupted and no files landed. The race is
  # real; the edge only makes it less likely, it is not a guarantee.
  #
  # The apparmor_bwrap_profile element is unchanged (#1570, see the note above).
  # Do NOT "simplify" either element away — see ship-deploy-pipeline-fix-gate.test.ts.
  depends_on = [terraform_data.apparmor_bwrap_profile, terraform_data.infra_config_handler_bootstrap]

  # hcloud_server.web has ignore_changes=[user_data], so cloud-init never re-applies
  # to the existing server. This resource is the sole path for pushing ci-deploy.sh,
  # webhook.service, cat-deploy-state.sh, canary-bundle-claim-check.sh, and
  # hooks.json updates to production (#2185, #3033).
  # Sentinel string at the end forces re-recreation when the inline
  # remote-exec list itself changes (terraform_data doesn't auto-detect
  # provisioner-block content drift; only triggers_replace is consulted).
  # Bump the sentinel suffix in lockstep with any inline edit so the
  # remote host re-receives + re-runs the updated commands.
  triggers_replace = sha256(join(",", [
    file("${path.module}/ci-deploy.sh"),
    file("${path.module}/ci-deploy-wrapper.sh"),
    file("${path.module}/webhook.service"),
    file("${path.module}/cat-deploy-state.sh"),
    file("${path.module}/canary-bundle-claim-check.sh"),
    # NOTE (#4827): the sudoers is no longer webhook-delivered (removed from
    # push-infra-config.sh + FILE_MAP; it is root-managed via the
    # infra_config_handler_bootstrap SSH bridge). It is kept in THIS hash so a
    # sudoers change still re-fires deploy_pipeline_fix (harmless — re-pushes the
    # unchanged 7 webhook files) AND keeps the deploy-pipeline-fix drift guard
    # (plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts TRIGGER_FILES +
    # the ship-skill DEPLOY_PIPELINE_FIX_TRIGGERS) in sync without a 3-way edit.
    file("${path.module}/deploy-inngest-bootstrap.sudoers"),
    file("${path.module}/infra-config-apply.sh"),
    # NOTE (#4829): infra-config-install.sh is delivered by the
    # infra_config_handler_bootstrap SSH bridge (root-managed escalation helper),
    # NOT this webhook path. It is kept in THIS hash for the same reason as the
    # sudoers above: so a helper-only change re-fires deploy_pipeline_fix (harmless
    # — re-pushes the unchanged 7 webhook files) AND keeps the deploy-pipeline-fix
    # drift guard (plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts
    # TRIGGER_FILES + the ship-skill DEPLOY_PIPELINE_FIX_TRIGGERS array) in sync,
    # so the ship gate fires + notifies the operator on a helper-only change.
    file("${path.module}/infra-config-install.sh"),
    file("${path.module}/push-infra-config.sh"),
    file("${path.module}/cat-infra-config-state.sh"),
    # NOTE (#5492): the four inngest cutover host scripts ARE webhook-delivered
    # (push-infra-config.sh payload + FILE_MAP + DEST_SPEC). Registering them here
    # makes a body-only edit to any one re-fire deploy_pipeline_fix so the fix
    # reaches /usr/local/bin — without this, #5492's enumerate fix would NOT have
    # deployed (no hashed file changed). Keep in lockstep with the ship
    # DEPLOY_PIPELINE_FIX_TRIGGERS array + DPF_REGEX + the gate test.
    file("${path.module}/inngest-enumerate-reminders.sh"),
    file("${path.module}/inngest-rearm-reminders.sh"),
    file("${path.module}/inngest-wiped-volume-verify.sh"),
    file("${path.module}/cat-inngest-verify-state.sh"),
    file("${path.module}/inngest-inventory.sh"),
    # #6178 — the two web-host Inngest cutover probes are webhook-delivered
    # (push-infra-config.sh payload + FILE_MAP + DEST_SPEC). inngest-registry-probe
    # is the 2.0 empty-registry pre-flight; inngest-doublefire-probe is the 2.6
    # exactly-once run-enumeration (both POST the dedicated host 10.0.1.40:8288 GQL
    # over the private net). Registering them here makes a body-only edit re-fire
    # deploy_pipeline_fix so the fix reaches /usr/local/bin (same #5492 rationale as
    # the inngest scripts above). Keep in lockstep with the ship
    # DEPLOY_PIPELINE_FIX_TRIGGERS array + DPF_REGEX + the gate test.
    file("${path.module}/inngest-registry-probe.sh"),
    file("${path.module}/inngest-doublefire-probe.sh"),
    # #5934 — the privileged char-device config.lock substrate sweep is
    # webhook-delivered (push-infra-config.sh payload + FILE_MAP + DEST_SPEC), so a
    # body-only edit must re-fire deploy_pipeline_fix to reach /usr/local/bin (same
    # #5492 rationale as the inngest scripts above). Keep in lockstep with the ship
    # DEPLOY_PIPELINE_FIX_TRIGGERS array + DPF_REGEX + the gate test.
    file("${path.module}/git-lock-chardevice-sweep.sh"),
    local.hooks_json,
  ]))

  # #3756 — replaced SSH provisioners (connection + file + remote-exec) with
  # an HTTPS POST through the existing CF Tunnel. push-infra-config.sh sends
  # base64-encoded file payloads to /hooks/infra-config; the webhook handler
  # (infra-config-apply.sh) writes them atomically on the host.
  #
  # Sensitive values are passed via the environment {} block (Terraform >=1.0
  # accepts sensitive values here but refuses to interpolate them into the
  # command string).
  provisioner "local-exec" {
    command = "${path.module}/push-infra-config.sh"

    environment = {
      WEBHOOK_SECRET   = var.webhook_deploy_secret
      CF_ACCESS_ID     = var.cf_access_client_id
      CF_ACCESS_SECRET = var.cf_access_client_secret
      APP_DOMAIN_BASE  = var.app_domain_base
      INFRA_DIR        = path.module
      HOOKS_JSON_B64   = base64encode(local.hooks_json)
    }
  }
}

# Deploy custom seccomp profile for per-container use (#1557, #1569).
# Enables bubblewrap sandbox inside containers by allowing CLONE_NEWUSER.
# ci-deploy.sh applies the profile via --security-opt seccomp=<path>;
# this resource only provisions the profile file and kernel sysctl.
# Shows as "will be created" in CI drift reports -- expected behavior.
resource "terraform_data" "docker_seccomp_config" {
  # Keyed on BOTH the seccomp-profile hash AND the host id. The hash alone is
  # identical on a replaced VM, so a bare `sha256(file(...))` trigger is the
  # classic terraform_data fresh-host trap (hr-fresh-host-provisioning-
  # reachable-from-terraform-apply): a new host keeps the old hash, the
  # provisioner is skipped, and the userns sysctl is never asserted on it —
  # the root cause of the 2026-06-04 cron silent-producer incident
  # (#4927/#4928), where bwrap could not mount /proc and EVERY Bash tool call
  # in a cron spawn failed. Folding the server id in re-runs the provisioner
  # whenever the host is replaced.
  triggers_replace = {
    seccomp_profile = sha256(file("${path.module}/seccomp-bwrap.json"))
    server_id       = hcloud_server.web["web-1"].id
  }

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "mkdir -p /etc/docker/seccomp-profiles",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/seccomp-bwrap.json"
    destination = "/etc/docker/seccomp-profiles/soleur-bwrap.json"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      # Ubuntu 24.04 kernel restricts uid_map writes inside unprivileged user
      # namespaces even with apparmor=unconfined. Without this sysctl, bwrap
      # (the Claude Code Bash sandbox) cannot mount /proc and EVERY Bash tool
      # call in a cron spawn fails (#1557).
      #
      # A one-time `sysctl -w` is NOT drift-proof — it is lost on reboot, and a
      # bare /etc/sysctl.d drop-in can be re-restricted by an apparmor package
      # update or fail to apply on a degraded (full-disk) boot. Install a
      # boot-persistent oneshot unit that re-asserts the sysctl on EVERY boot,
      # and keep the sysctl.d drop-in as belt-and-braces. This closes the
      # reboot-drift half of the 2026-06-04 incident (#4927/#4928); the
      # fresh-host half is closed by the server_id trigger above.
      "echo 'kernel.apparmor_restrict_unprivileged_userns=0' > /etc/sysctl.d/99-bwrap-userns.conf",
      "cat > /etc/systemd/system/bwrap-userns-sysctl.service << 'UNITEOF'\n[Unit]\nDescription=Assert bwrap unprivileged-userns sysctl for the Claude Code Bash sandbox\nAfter=multi-user.target\n\n[Service]\nType=oneshot\nRemainAfterExit=yes\nExecStart=/usr/sbin/sysctl -w kernel.apparmor_restrict_unprivileged_userns=0\n\n[Install]\nWantedBy=multi-user.target\nUNITEOF",
      "systemctl daemon-reload",
      "systemctl enable --now bwrap-userns-sysctl.service",
      "echo 'Seccomp profile provisioned; bwrap userns sysctl asserted via boot-persistent unit'",
    ]
  }
}

# Deploy custom AppArmor profile for bwrap sandbox (#1570).
# Replaces apparmor=unconfined with a scoped profile that allows
# mount/umount/pivot_root while maintaining Docker's other restrictions.
# Shows as "will be created" in CI drift reports -- expected behavior.
resource "terraform_data" "apparmor_bwrap_profile" {
  # (#6629) server_id fold-in — parity with docker_seccomp_config. A bare
  # sha256(file(...)) trigger is hash-only: on a host REPLACEMENT the profile content is
  # unchanged, so the trigger does NOT re-fire and the new VM never gets the AppArmor
  # profile SSH-delivered (the exact fresh-host trap the #4927/#4928 precedent + the
  # docker_seccomp_config comment warn about). The boot-time image-bake (host_script_files)
  # closes the FRESH-host half; this closes the running-host re-apply half.
  triggers_replace = {
    apparmor_profile = sha256(file("${path.module}/apparmor-soleur-bwrap.profile"))
    server_id        = hcloud_server.web["web-1"].id
  }

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "file" {
    source      = "${path.module}/apparmor-soleur-bwrap.profile"
    destination = "/etc/apparmor.d/soleur-bwrap"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "apparmor_parser -r /etc/apparmor.d/soleur-bwrap",
      "echo 'AppArmor profile soleur-bwrap loaded'",
    ]
  }
}

# Deploy orphan-reaper.sh and systemd timer to clean up stale .orphaned-*
# workspace directories under /mnt/data/workspaces/. workspace.ts moves
# root-owned dirs aside but nothing cleans them up (#1640).
# Shows as "will be created" in CI drift reports -- expected behavior (#1409).
resource "terraform_data" "orphan_reaper_install" {
  triggers_replace = sha256(file("${path.module}/orphan-reaper.sh"))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  provisioner "file" {
    source      = "${path.module}/orphan-reaper.sh"
    destination = "/usr/local/bin/orphan-reaper.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/orphan-reaper.sh",
      "cat > /etc/systemd/system/orphan-reaper.service << 'UNITEOF'\n[Unit]\nDescription=Orphaned workspace directory reaper\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/orphan-reaper.sh\nUNITEOF",
      "cat > /etc/systemd/system/orphan-reaper.timer << 'TIMEREOF'\n[Unit]\nDescription=Run orphan reaper every 6 hours\n\n[Timer]\nOnBootSec=10min\nOnUnitActiveSec=6h\nPersistent=true\n\n[Install]\nWantedBy=timers.target\nTIMEREOF",
      "systemctl daemon-reload",
      "systemctl enable --now orphan-reaper.timer",
      "systemctl list-timers orphan-reaper.timer --no-pager",
    ]
  }
}

# Container egress firewall for the web-platform container (#5046 PR-2).
# Default-drop DOCKER-USER allowlist: contains the 4 live spawn("bash") crons
# that bypass the #5018 PreToolUse hook (ADR-033 I7) and makes the hook's
# Task/Skill relax-minimal safe. Applied via SSH because cloud-init is dead on
# the running host (ignore_changes=[user_data]); cloud-init.yml mirrors the
# artifacts for fresh hosts. Post-apply asserts include a LIVE positive +
# negative container probe — `nft -f` exits 0 on an inert ruleset, so only a
# real probe proves enforcement (the silent-green guard, AC-P2.8).
# Shows as "will be created" in CI drift reports -- expected behavior.
resource "terraform_data" "cron_egress_firewall" {
  # Keyed on every delivered artifact AND the host id (hr-fresh-host-
  # provisioning: a replaced VM keeps identical hashes — folding the server id
  # re-runs the provisioner so the firewall is never silently absent).
  triggers_replace = {
    config_hash = sha256(join(",", [
      file("${path.module}/cron-egress-nftables.sh"),
      file("${path.module}/cron-egress-resolve.sh"),
      file("${path.module}/cron-egress-alarm.sh"),
      file("${path.module}/cron-egress-allowlist.txt"),
      file("${path.module}/cron-egress-allowlist-cidr.txt"),
      file("${path.module}/cron-egress-firewall.service"),
      file("${path.module}/cron-egress-resolve.service"),
      file("${path.module}/cron-egress-resolve.timer"),
      file("${path.module}/cron-egress-alarm@.service"),
      # #5289: fold the post-apply assertion block (now a delivered script) into
      # the hash so an edit to it re-provisions — inline-block edits were silent
      # no-ops (the block lived in the 2nd remote-exec, outside this hash).
      file("${path.module}/cron-egress-postapply-assert.sh"),
    ]))
    server_id = hcloud_server.web["web-1"].id
  }

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key         # null in operator-local context
    agent       = var.ci_ssh_private_key == null # agent locally, explicit key in CI
  }

  # `file` (scp) does NOT create remote parents and /etc/soleur is not shipped
  # by any base package (2026-06-02 cloned-provisioner learning). nftables is
  # in the base Ubuntu 24.04 image but assert anyway (idempotent).
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "mkdir -p /etc/soleur",
      "command -v nft >/dev/null || (apt-get update && apt-get install -y nftables)",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-nftables.sh"
    destination = "/usr/local/bin/cron-egress-nftables.sh"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-resolve.sh"
    destination = "/usr/local/bin/cron-egress-resolve.sh"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-alarm.sh"
    destination = "/usr/local/bin/cron-egress-alarm.sh"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-allowlist.txt"
    destination = "/etc/soleur/cron-egress-allowlist.txt"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-allowlist-cidr.txt"
    destination = "/etc/soleur/cron-egress-allowlist-cidr.txt"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-firewall.service"
    destination = "/etc/systemd/system/cron-egress-firewall.service"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-resolve.service"
    destination = "/etc/systemd/system/cron-egress-resolve.service"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-resolve.timer"
    destination = "/etc/systemd/system/cron-egress-resolve.timer"
  }

  provisioner "file" {
    source      = "${path.module}/cron-egress-alarm@.service"
    destination = "/etc/systemd/system/cron-egress-alarm@.service"
  }

  # #5289: the post-apply assertion block was extracted from the inline
  # remote-exec below into this delivered script so an edit to it changes
  # config_hash and re-provisions (inline-block edits were silent no-ops). The
  # script body owns `set -e` and the ASSERT-FAILED sentinels; the runner below
  # just chmods + executes it. Same loader/resolver/orphan-reaper delivery shape.
  provisioner "file" {
    source      = "${path.module}/cron-egress-postapply-assert.sh"
    destination = "/usr/local/bin/cron-egress-postapply-assert.sh"
  }

  provisioner "remote-exec" {
    # `set -e` FIRST: terraform joins `inline` into ONE script with NO implicit
    # errexit, and the provisioner fails only on the LAST command's exit — so
    # without it the `bash …` failure could be masked by a trailing command.
    # The assertion logic itself lives in cron-egress-postapply-assert.sh (also
    # `set -e`-first, folded into config_hash above); this runner only delivers
    # errexit + chmod + execute.
    inline = [
      "set -e",
      "chmod +x /usr/local/bin/cron-egress-postapply-assert.sh",
      "bash /usr/local/bin/cron-egress-postapply-assert.sh",
    ]
  }
}

# Per-host local worktree volume (multi-host /workspaces, #5274 Phase 3). Each web
# host has its OWN /workspaces block volume (per-user worktrees live host-local on
# NVMe — ADR-068 §1). web-1 keeps its exact current name/location so the `moved`
# migration below is 0-destroy (a volume location change would force-replace and
# drop the live data).
resource "hcloud_volume" "workspaces" {
  for_each = var.web_hosts
  name     = each.key == "web-1" ? "soleur-web-platform-data" : "soleur-web-platform-data-${each.key}"
  size     = var.volume_size
  location = each.value.location
  format   = "ext4"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_volume_attachment" "workspaces" {
  for_each  = var.web_hosts
  volume_id = hcloud_volume.workspaces[each.key].id
  server_id = hcloud_server.web[each.key].id
}
