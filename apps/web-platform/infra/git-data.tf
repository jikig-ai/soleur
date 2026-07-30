# Epic #5274 Phase 2 PR B / ADR-068 — the git-data host (multi-host /workspaces).
#
# A dedicated Hetzner host that stores the per-workspace BARE git repos (objects +
# refs) and enforces the writer-side CAS fence (ADR-068 §3). The web host keeps
# worktrees on local NVMe and pushes to this host over the private net
# (network.tf). At replicas=1 the fence is live-but-non-rejecting; it becomes
# load-bearing at Phase 3's second writer.
#
# Apply-path note: cloud-init-only (NO remote-exec provisioner). The CI runner
# cannot SSH either host, so any provisioner here would hang the merge-triggered
# auto-apply. `terraform apply` returns green on server CREATE without waiting for
# cloud-init; the post-merge readiness/cutover script (web-host-driven, over the
# private net) verifies git + bare-repo root + hook are live BEFORE cutover
# (hr-fresh-host-provisioning-reachable-from-terraform-apply).
#
# REPROVISION-PATH (ADR-103, #6242): git-data resources are OPERATOR_APPLIED_EXCLUSIONS
# (never touched per-PR), and the per-PR path bridges over SSH to the EXISTING web host so
# it cannot reprovision this host at all. A sanctioned dispatch-only `git-data-host-replace`
# `workflow_dispatch` path now exists (apply-web-platform-infra.yml, mirroring
# registry-host-replace / ADR-100 inngest-host-replace) to re-run this host's cloud-init
# WITHOUT SSH — a scoped, destroy-guarded `terraform apply -replace='hcloud_server.git_data'`
# that PRESERVES BOTH data volumes (hcloud_volume.git_data + hcloud_volume.git_data_luks) and
# the LUKS passphrase by OMISSION. It is a maintenance-window dispatch, not a per-PR apply;
# these resources remain excluded from the per-PR `-target=` list. Before it, git-data had
# ZERO non-SSH reprovision path (hr-prod-host-config-change-immutable-redeploy gap). The
# invariant that a boot-armed heartbeat needs such a path is mechanically enforced by
# plugins/soleur/test/heartbeat-reprovision-parity.test.ts.

# --- In-band transport keypair (ED25519) ------------------------------------
# DEDICATED key — NOT reused from tls_private_key.ci_ssh. Mirrors the ci-ssh-key.tf
# shape (tls_private_key.ci_ssh + the trimspace() local + doppler_secret). The
# public half goes onto the git-data host (cloud-init authorized_keys, git-shell
# forced-command); the private half goes to Doppler for git-auth.ts to consume.
#
# Intentionally a single throwaway shared key (the Phase-2 floor: one web host,
# git-shell-scoped). Phase 3's per-workspace_id mTLS (ADR-068 §6) REPLACES it; it
# is NOT a cluster-wide mount credential, so the Phase-3 swap is additive-then-
# remove (the Phase-3 plan must plan its removal).
resource "tls_private_key" "git_transport" {
  algorithm = "ED25519"
}

# --- In-band PROVISION keypair (ED25519) ------------------------------------
# A SECOND, dedicated key — SEPARATE from tls_private_key.git_transport (ADR-068
# amendment 2026-07-01 "PR B bare-repo provisioning"). Its cloud-init forced
# command is the FIXED `git-data-provision.sh` (idempotent `git init --bare`),
# NEVER git-shell. Provisioning authority and ref-write authority are separate
# credentials with separate blast radii (ADR-068 §6): a leaked transport key
# cannot fabricate repos, and a leaked provision key cannot write refs. Same OS
# `git` user (per-key command= overrides the login shell). Same throwaway-shape as
# git_transport; Phase 3's per-workspace_id mTLS replaces both.
resource "tls_private_key" "git_provision" {
  algorithm = "ED25519"
}

# --- In-band REMOVE keypair (ED25519) ---------------------------------------
# A THIRD, dedicated key — SEPARATE from git_transport AND git_provision (#5274
# Phase 3, ADR-068 GDPR Art. 17 / CLO DL-1). Its cloud-init forced command is the
# FIXED `git-data-remove.sh` (idempotent `rm -rf <id>.git`), NEVER git-shell.
# Provisioning, ref-write, and ERASURE authority are three separate credentials
# with separate blast radii (ADR-068 §6): a leaked transport/provision key cannot
# delete repos, and a leaked remove key cannot write refs. Same OS `git` user
# (per-key command= overrides the login shell). Same throwaway-shape as the
# siblings; Phase 3's per-workspace_id posture replaces all three.
resource "tls_private_key" "git_remove" {
  algorithm = "ED25519"
}

locals {
  # (#6982, W8) The host's stable private-net address, hoisted out of network.tf so
  # doppler_secret.git_data_ssh_host below can publish it WITHOUT referencing any
  # hcloud resource. Mirrors local.registry_private_ip (zot-registry.tf:40, #6415):
  # the host's own file owns the constant, network.tf consumes it.
  #
  # THIS BEING A STATIC LITERAL IS THE WHOLE POINT. ADR-149 cut this secret from #6977
  # because sourcing it from hcloud_server_network.git_data.ip (a COMPUTED attribute)
  # would drag hcloud_server.git_data into any -target closure that reached the secret,
  # and the natural remedy — a per-PR -target line — wedges every merge to main. A
  # literal has no such edge: the secret is plannable and appliable with the host
  # absent, which is exactly the state it must survive (see the resource comment).
  #
  # web = .10/.11, git-data = .20, registry = .30, inngest = .40.
  git_data_private_ip = "10.0.1.20"

  # trimspace() strips the trailing newline tls_private_key.public_key_openssh
  # carries — without it the cloud-init authorized_keys line renders with a
  # trailing blank, breaking the forced-command entry. Same rationale as
  # local.ci_ssh_pubkey (ci-ssh-key.tf).
  git_transport_pubkey = trimspace(tls_private_key.git_transport.public_key_openssh)
  git_provision_pubkey = trimspace(tls_private_key.git_provision.public_key_openssh)
  git_remove_pubkey    = trimspace(tls_private_key.git_remove.public_key_openssh)

  # Arch DERIVED from var.git_data_server_type (mirrors zot-registry.tf local.registry_arch
  # and inngest-host.tf local.inngest_arch): `cax*` (Ampere) → arm64, anything else
  # (`cpx*`/`cx*`/`ccx*`) → amd64. #6570: the host was pinned to cax11, orderable in 0 of 3
  # EU datacenters, so it could never be born on its declared type; deriving the arch is what
  # makes the repin to an x86 type safe rather than a boot-brick (the old cloud-init
  # hardcoded the arm64 build + its checksum).
  #
  # SCOPE, since #7025 R7: this local now feeds ONLY the phantom/wrong-arch precondition
  # below. The arch that selects WHICH BINARY cloud-init downloads is derived inside
  # modules/git-data-userdata (which both roots render through), because a derivation that
  # lived in each caller existed once per root and was compared by nothing. The two
  # derivations must still agree — a precondition validating a different arch than the one
  # downloaded is the #6570 boot-brick with the tripwire green — so git-data-luks.test.sh
  # A16b asserts the two ternaries are byte-identical.
  git_data_arch = startswith(var.git_data_server_type, "cax") ? "arm64" : "amd64"
}

# The git-data host's server type, read from the live Hetzner catalog. Read-only; creates
# nothing. Resolves at PLAN time, which makes it a PHANTOM-TYPE tripwire: #6288 set
# var.registry_server_type to `cx32`, a type that does not exist, and the apply DESTROYED
# the registry host before failing `server type cx32 not found` on the create. Mirrors
# zot-registry.tf's data.hcloud_server_type.registry.
#
# This data source is load-bearing ONLY because hcloud_server.git_data references it in a
# lifecycle.precondition below. Terraform PRUNES an unreferenced data source under
# `-target=` (probed against the pinned toolchain: -target an unrelated resource → the
# data source is never read, exit 0; add a precondition edge → it reads). EVERY git-data
# dispatch is -targeted, so without that referencing edge this tripwire would fire on
# ZERO production paths — live only in the untargeted PR-time plan. Do not "simplify" the
# precondition away and keep this block believing it still guards anything (#6570 R1).
data "hcloud_server_type" "git_data" {
  name = var.git_data_server_type
}

# Private half → Doppler. Consumed at RUNTIME by the web host's git-auth.ts, which
# is configured from Doppler `prd` (prd values are baked into the container env at
# start) — NOT `prd_terraform` (that config feeds the CI/terraform deploy pipeline,
# which is where doppler_secret.deploy_ssh_private_key correctly lives because it is
# a DEPLOY-time key). This is a RUNTIME key, so it belongs in `prd`. The TF doppler
# token demonstrably writes `prd` (see doppler_secret.git_data_heartbeat_url_prd
# below). NOT cloud-init — the web host carries ignore_changes=[user_data], so
# cloud-init can never reach the running container.
resource "doppler_secret" "git_transport_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_TRANSPORT_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_transport.private_key_openssh
  visibility = "masked"

  # (#6977) Ordering only: a partial apply must not publish a runtime key for a host that
  # does not exist, or the consumer resolves a 10.0.1.20 that nothing answers on. The
  # Art. 17 ARMING-SWITCH argument does NOT apply to this key — see the canonical block
  # above `doppler_secret.git_remove_ssh_private_key`, which is the only key whose mere
  # presence arms erasure. NO-CYCLE and REACHABILITY-RESIDUAL notes are recorded there too
  # and hold identically for this edge.
  depends_on = [hcloud_server.git_data]
}

# Provision key private half → Doppler `prd` (RUNTIME key; same rationale as
# git_transport above). Consumed by git-data-replication.ts (sshWithPrivateKeyAuth)
# to reach the `git-data-provision.sh` forced command before the first push.
resource "doppler_secret" "git_provision_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_PROVISION_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_provision.private_key_openssh
  visibility = "masked"

  # (#6977) Ordering only, same as git_transport above: do not publish a runtime key ahead
  # of the host it authenticates to. The Art. 17 ARMING-SWITCH argument does NOT apply
  # here either — the canonical block above `doppler_secret.git_remove_ssh_private_key`
  # explains why that reasoning is specific to the remove key, and carries the NO-CYCLE
  # and REACHABILITY-RESIDUAL notes that hold for all three edges.
  depends_on = [hcloud_server.git_data]
}

# Remove key private half → Doppler `prd` (RUNTIME key; same rationale as the
# siblings). Consumed by account-delete.ts / workspace-delete (3.D) to reach the
# `git-data-remove.sh` forced command over the private net for Art. 17 erasure.
resource "doppler_secret" "git_remove_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_REMOVE_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_remove.private_key_openssh
  visibility = "masked"

  # (#6977, Defect 2) The remove key's PRESENCE is the arming switch for Art. 17 erasure.
  #
  # `removeGitDataRepo` is deliberately NOT gated on `isGitDataStoreEnabled()` — flag-
  # gating erasure would strand a user's PII across a rollback window, which is a worse
  # Art. 17 gap than the one this guards. It gates on the remove key being present
  # instead. But this secret has no dependency on the host, so a partial apply could land
  # it while the server create fails; every subsequent account deletion would then call
  # resolveGitDataSshHost(), throw, and file a FALSE "Art. 17 erasure failed" Sentry event
  # for a store that does not exist — alarm fatigue on the one signal that must stay
  # trustworthy.
  #
  # NO CYCLE: the server reaches tls_private_key.git_* through local.git_*_pubkey (the
  # PUBLIC halves, baked into user_data). Nothing in the server's graph reaches these
  # doppler_secret resources, so the edge only ever points this way. Verified
  # independently by two reviewers and by `terraform validate`.
  #
  # RESIDUAL, recorded rather than claimed fixed: this anchors on the server OBJECT, not
  # on REACHABILITY. A birth where the server lands but hcloud_server_network.git_data
  # does not still arms the key against an unroutable 10.0.1.20. ADR-149 carries it.
  #
  # (#6982) The ANTIDOTE edge. This key's presence is the Art. 17 arming switch, and
  # `removeGitDataRepo` resolves GIT_DATA_SSH_HOST at the same call site — so the arming
  # switch must never land without it. Fewer-dependencies makes the antidote eligible
  # earlier but does NOT order it (terraform orders only by edges, and -parallelism=10
  # schedules both at once); a transient Doppler 5xx on the ssh-host write would otherwise
  # leave the switch armed and the antidote missing, and every account deletion from that
  # instant files a FALSE "erasure failed" event. No cycle: git_data_ssh_host reads a
  # static local and has no upstream at all.
  depends_on = [hcloud_server.git_data, doppler_secret.git_data_ssh_host]
}

# --- The git-data host's address → Doppler prd (#6982 W8 / ADR-149 §5, Residual 2) ---
#
# `resolveGitDataSshHost()` (git-data-replication.ts) reads GIT_DATA_SSH_HOST and THROWS in
# production when it is unset. `removeGitDataRepo` — the Art. 17 erasure path — calls it. So
# without this secret, from the instant the host exists EVERY account deletion throws and
# files a "git-data Art. 17 erasure failed" Sentry event for a store that is fine. That is
# 100 % false alarms on the one signal that must stay trustworthy, and it is why ADR-149
# lists this as checklist item 5 rather than a nicety.
#
# NO `depends_on` — and that is deliberate, load-bearing, and the opposite of its three
# sibling key secrets above (#6982 R9). ADR-149 Residual 2 corrected exactly this reasoning:
# `depends_on` guarantees the value CO-LANDS with the server, and for the REMOVE KEY
# co-landing is the harmful state (its presence is the arming switch for erasure). This
# secret is the ANTIDOTE, not the poison — it is the thing that makes erasure work — so
# co-landing is precisely what must NOT be required. Two consequences, both wanted:
#
#   1. AC35 is pinned by the explicit edge on the REMOVE key (see
#      `doppler_secret.git_remove_ssh_private_key`), which is a mechanism rather than a
#      scheduling accident. An earlier draft of this comment claimed ordering "BY
#      CONSTRUCTION" from wave-eligibility; that was false — Terraform orders only by
#      dependency edges, and under the default -parallelism=10 both are scheduled
#      concurrently, so a transient Doppler 5xx on THIS write in an apply where the server
#      and the remove key both succeed leaves the arming switch on with the antidote absent.
#   2. It carries no edge that drags hcloud_server.git_data into any `-target` closure that
#      EXISTS — the wedge ADR-149 feared when it cut this resource from #6977. Note this is
#      now an argument about the actual -target lines, not about having no upstream: since
#      DC-3 (below) the value reads `hcloud_server_network.git_data.ip`, so the resource DOES
#      have an upstream and is no longer first-wave. The birth job already targets both
#      `hcloud_server.git_data` and `hcloud_server_network.git_data`, so the edge drags
#      nothing new in. An earlier revision of this block asserted "no upstream at all" and
#      "no edge" as unconditional facts; both were falsified by DC-3 and are corrected here
#      rather than left standing ten lines above the note that contradicts them.
#
# NO `lifecycle { ignore_changes = [value] }` either (#6982 R38): every sibling
# doppler_secret in this root lets Terraform own the value, and pinning it here would
# freeze a stale address the day the NIC's IP moves — silently re-creating the drift that
# this single-sourcing exists to remove.
resource "doppler_secret" "git_data_ssh_host" {
  project = "soleur"
  config  = "prd"
  name    = "GIT_DATA_SSH_HOST"
  # DC-3's MANDATED source. #6982's first draft shipped local.git_data_private_ip and
  # recorded the mandate as "not satisfiable pre-birth"; review refuted that. The secret's
  # ONLY -target line is the birth job, which already targets hcloud_server.git_data AND
  # hcloud_server_network.git_data -- so the edge drags nothing new into any plan that
  # exists, and there is no pre-birth window to protect because the secret is created BY
  # the dispatch, not before it. The mandated form is also strictly stronger: it closes the
  # residual above (a birth landing the server but not the NIC can no longer publish an
  # address nothing answers on).
  value      = hcloud_server_network.git_data.ip
  visibility = "masked"
}

# --- The git-data host -------------------------------------------------------
# (#7025, R7) THE RENDER MOVED TO ./modules/git-data-userdata.
#
# It used to be an inline `templatefile()` map here, plus a byte-for-byte duplicate of
# `local.git_data_rationale_strip` kept equal by git-data-render-strip-parity.test.sh. The
# rung-2 rehearsal root (apps/web-platform/infra/rung2-rehearsal/) needs the SAME render, and
# a third copy is not safe the way the second one was: the rung-2 evidence hash is over
# SOURCE FILES, so two copies that drift produce a BYTE-IDENTICAL hash for a DIFFERENT
# render. The rehearsal would attest a payload it did not boot, and the attestation would
# verify. One module called twice has no drift to detect.
#
# The strip expression and the map now live in modules/git-data-userdata/main.tf. The
# rung-2 gate derives its hash-input set by grepping THAT file — see
# tests/scripts/lib/git-data-birth-readiness-gate.sh.
module "git_data_userdata" {
  source = "./modules/git-data-userdata"

  host_name               = "soleur-git-data"
  git_data_volume_id      = hcloud_volume.git_data.id
  git_data_luks_volume_id = hcloud_volume.git_data_luks.id
  doppler_token           = doppler_service_token.git_data.key
  # (#7025, R1) The literal this template carried until #7025, now passed explicitly. It
  # MUST name the config doppler_service_token.git_data is scoped to.
  doppler_config_name    = "prd_git_data"
  git_data_server_type   = var.git_data_server_type
  sentry_dsn             = var.sentry_dsn
  betterstack_ingest_url = local.betterstack_logs_ingest_url
  git_transport_pubkey   = local.git_transport_pubkey
  git_provision_pubkey   = local.git_provision_pubkey
  git_remove_pubkey      = local.git_remove_pubkey
}

resource "hcloud_server" "git_data" {
  name = "soleur-git-data"
  # Arch is DERIVED from this value (local.git_data_arch), never assumed — see the local.
  # Default cpx22 (amd64): the cax line was orderable in 0 of 3 EU DCs, so the previous
  # cax11 pin made this host unbornable (#6570).
  server_type = var.git_data_server_type
  location    = var.location
  image       = "ubuntu-24.04"
  keep_disk   = true
  ssh_keys    = [hcloud_ssh_key.default.id]

  # P0 — public IPv4/IPv6 for EGRESS only (apt + GitHub during cloud-init). A
  # no-public-IP host has NO internet (no NAT gateway exists in this account), so
  # `apt-get install git` in the bootstrap would fail. INGRESS on the public
  # interface is denied by hcloud_firewall.git_data below; transport is private-
  # net only.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # gzip-first (#5927). Post-#5918 the rendered cloud-config is ~41.7 KB — OVER
  # Hetzner's 32,768-byte user_data cap. git-data runs NO docker and pulls NO image,
  # so #5921's web-host bake-and-extract mechanism (ADR-080) does NOT transfer here.
  # Instead wrap the WHOLE render in base64gzip(): the highly-compressible shell
  # payload gzips to ~16.4 KB, and the base64 of that (~21.9 KB) is what Hetzner
  # stores against the cap — under it with ~10 KB headroom.
  #
  # Decode contract: Hetzner does NOT accept binary user-data, so it base64-decodes
  # the stored string before cloud-init sees it (cloud-init's
  # DataSourceHetzner.maybe_b64decode, added ≥20.3; Ubuntu 24.04 ships far newer) →
  # raw gzip bytes (magic 1f 8b) → cloud-init auto-gunzips → byte-identical
  # #cloud-config. base64 is therefore MANDATORY on Hetzner, which makes base64gzip()
  # the intended path, not a datasource gamble. The template + all 5 injected scripts
  # stay byte-identical; only this expression changed. Byte-exact size is confirmed at
  # #5887's first `terraform plan`; fail-closed at first provisioning if decode fails
  # (web-host readiness check finds no git/bare-repo, blocks cutover). See ADR-080.
  user_data = base64gzip(module.git_data_userdata.rendered)

  # PHANTOM/WRONG-ARCH TRIPWIRE (#6570). Two jobs, and the second is why this block is
  # MANDATORY rather than a nicety:
  #   1. It is the referencing edge that keeps data.hcloud_server_type.git_data alive under
  #      `-target=`. Unreferenced, that data source is PRUNED and never read, so the
  #      phantom-type guard would fire on zero production paths (every git-data dispatch is
  #      -targeted). Deleting this precondition silently disarms the data source above.
  #   2. It catches a MIS-DERIVED arch at plan time, and NOTHING DOWNSTREAM CAN — including
  #      after #6982. The checksum is selected BY local.git_data_arch, so a wrong derivation
  #      verifies the tarball it just chose and `sha256sum -c -` passes. That is a property
  #      of the selection, not of error handling, so no amount of failing closed reaches it.
  #      This precondition remains the only guard that fires on that case.
  #
  #      What #6982 DID change, so the rest of this note is not read as still true: the
  #      runcmd path is now armed with a top-level `trap`/`set -e` ahead of the checksum
  #      block, so a GENUINE checksum failure aborts instead of continuing into `tar xzf`
  #      and `chmod +x` on an unverified tarball (the supply-chain half). It used to say
  #      "NOTHING ABORTS" here, and that is no longer the case. The LUKS block's
  #      `set -euo pipefail` still is not a backstop — it is line 1 of the heredoc
  #      `doppler run` executes, so on a missing or wrong-arch binary that line runs ZERO
  #      times — and the host now reports the failure off-host via /usr/local/bin/git-data-emit
  #      rather than only into on-host /var/log/cloud-init-output.log.
  #
  # The enums are DELIBERATELY mapped, not compared. hcloud reports architecture as
  # `x86`/`arm`, while local.git_data_arch is the download token `amd64`/`arm64`. Comparing
  # them directly is `"amd64" == "x86"` → false on EVERY plan forever, which would wedge
  # this whole root including unrelated applies.
  #
  # This block carries a precondition ONLY. Still deliberately NO
  # lifecycle.ignore_changes=[user_data]: the web host carries that only as an IMPORT
  # ARTIFACT (server.tf:66-72); a FRESH host has no spurious diff, and omitting it
  # preserves a clean replace-to-reprovision path during the fence-iteration window (P1).
  lifecycle {
    precondition {
      condition = data.hcloud_server_type.git_data.architecture == (
        local.git_data_arch == "arm64" ? "arm" : "x86"
      )
      error_message = "git_data_server_type=${var.git_data_server_type} derives ${local.git_data_arch}, but Hetzner reports architecture=${data.hcloud_server_type.git_data.architecture} (enum: x86|arm). The Doppler CLI download would be wrong-arch."
    }

    # `ssh_keys` is a CREATE-TIME attribute (Hetzner injects it at first boot and never
    # re-reads it), so a changed key ID is unappliable to a running host and Terraform
    # resolves it as a REPLACE. Rotating `hcloud_ssh_key.default` — an operator credential
    # rotation, not an infra change — would therefore force-replace this host and cascade
    # to its LUKS volume attachment. Mirrors server.tf. Deliberately NOT widened to
    # user_data: that replace is the intended replace-to-reprovision path (comment above).
    ignore_changes = [ssh_keys]
  }

  # (#6977, P13) Order the LUKS passphrase BEFORE the host boots.
  #
  # There was no edge in EITHER direction between this server and
  # doppler_secret.git_data_luks_key. doppler_service_token.git_data IS upstream (its
  # .key is baked into user_data), but the token is only an authorization to READ the
  # config — it says nothing about the config CONTAINING the key. So terraform was free
  # to create the host first; it would boot, `doppler run` would return a config with no
  # GIT_DATA_LUKS_KEY, and `cryptsetup luksOpen` would fail.
  #
  # AND NOTHING WOULD REPORT IT. The Doppler install runcmd has no `set -e`, and the LUKS
  # block's `set -euo pipefail` is line 1 of the heredoc that `doppler run` EXECUTES — so
  # if the binary is missing or wrong-arch it never runs at all. The boot "succeeds" with
  # /mnt/git-data-luks unmounted: at-rest encryption absent while every artifact claims it
  # is present. `runcmd` is once-per-instance so no reboot repairs it, and ADR-115
  # excludes git-data from the reboot primitive anyway — the host must be REPLACED.
  #
  # Low probability, unrecoverable, no signal. That combination is what makes an explicit
  # ordering edge worth more than the arithmetic it costs.
  #
  # CROSS-PATH CONSEQUENCE: this puts the passphrase pair UPSTREAM of the server, so it
  # now enters the git-data-host-REPLACE job's closure as a `no-op`. That gate's
  # `luks_passphrase_touched` counter filters on the four mutating verbs, so a no-op does
  # not trip it — asserted as a regression arm in test-git-data-host-replace-gate.sh
  # rather than left to inference.
  depends_on = [doppler_secret.git_data_luks_key]

  labels = {
    app = "soleur-web-platform"
  }
}

# --- Bare-repo block volume --------------------------------------------------
# The bare repos AND the per-(workspace,worktree) fence sidecar/lock live here —
# never tmpfs (a reboot resetting the fence max to 0 would let a stale writer
# win). Shape mirrors hcloud_volume.workspaces (server.tf:926-940).
resource "hcloud_volume" "git_data" {
  name     = "soleur-git-data-store"
  size     = var.git_data_volume_size
  location = var.location
  format   = "ext4"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_volume_attachment" "git_data" {
  volume_id = hcloud_volume.git_data.id
  server_id = hcloud_server.git_data.id
}

# --- Deny-all PUBLIC ingress firewall ----------------------------------------
# ZERO inbound rules = deny-all on the PUBLIC interface (P1). Hetzner firewalls
# filter only the public interface; intra-hcloud_network traffic (the web host's
# git transport + liveness probe on 10.0.1.0/24) is open by network membership
# and needs NO allow rule. NO inbound SSH/git rule on the public interface —
# private-net transport only. Egress (apt/GitHub) is unaffected by inbound rules.
resource "hcloud_firewall" "git_data" {
  name = "soleur-git-data"

  labels = {
    app = "soleur-web-platform"
  }
}

# Separate attachment resource (mirrors hcloud_firewall_attachment.web,
# firewall.tf:91-94) rather than an inline apply_to block.
resource "hcloud_firewall_attachment" "git_data" {
  firewall_id = hcloud_firewall.git_data.id
  server_ids  = [hcloud_server.git_data.id]
}

# --- Liveness (PUSH heartbeat) -----------------------------------------------
# Better Stack cannot PULL a deny-all-public-ingress host, so liveness is a PUSH
# heartbeat: a web-host cron probes git-data over the private net (git ls-remote /
# ssh) and pings this heartbeat URL on success; absence-of-ping alerts. Shape
# mirrors betteruptime_heartbeat.inngest_prd (inngest.tf:268-298).
#
# paused = true initially (same rationale as inngest_prd): until the web-host
# probe cron is wired + deployed, the gap between apply (Better Stack starts
# expecting a ping within `grace`) and the first ping would fire a false alert.
# Unpause via the Better Stack UI (or flip in a follow-up) once the probe ships.
resource "betteruptime_heartbeat" "git_data_prd" {
  name   = "soleur-git-data-prd"
  period = 60
  # grace relaxed 30 → 180 (#6548 / #5274 PR C): git-data is fail-soft ("an OVERLAY, not a hard
  # dependency", ensure-workspace-repo.ts:332), so a single transient reachability blip must NOT
  # page. The web-host probe (web-git-data-probe.sh) pings on every reachable run; 180s of grace
  # means paging fires only on a SUSTAINED (multi-window) break, not a one-off.
  grace     = 180
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  # Literal name of the only team in this Better Stack workplace (case-sensitive
  # provider lookup) — see inngest.tf:277-281.
  team_name  = "Your team"
  policy_id  = var.betterstack_paid_tier ? betteruptime_policy.inngest[0].id : null
  paused     = true
  sort_index = 0

  lifecycle {
    # Operator unpause via UI MUST NOT be reverted by subsequent applies (mirrors
    # betteruptime_heartbeat.inngest_prd).
    ignore_changes = [paused]
  }
}

# Heartbeat URL → Doppler prd, so the (follow-up) web-host probe cron can read it
# via the server's existing `doppler secrets download` flow. Mirrors
# doppler_secret.inngest_heartbeat_url_prd (inngest.tf:323-329).
#
# TODO(#5274 PR C / follow-up): the web-host probe cron itself (git ls-remote over
# the private net to 10.0.1.20, then curl GIT_DATA_HEARTBEAT_URL on success) needs
# ci-deploy wiring (a systemd timer like inngest-heartbeat.timer). This resource +
# the URL secret are the IaC deliverable here; the probe script is the follow-up.
#
# This TODO is honest — unlike its registry counterpart, which claimed the probe had shipped and
# left the monitor inert for 9 days (#6537). It is now ENFORCED rather than merely accurate:
# heartbeat-manifest.ts declares this row `feeder: {kind:"none", url_secret:"GIT_DATA_HEARTBEAT_URL"}`
# and the parity guard asserts that secret still has zero dereferencing consumers — so the day PR C
# ships the probe, CI goes red and forces the row (and the arming decision) to be reconciled.
# See ADR-117. Live-absence of this heartbeat is tracked separately in #6548.
resource "doppler_secret" "git_data_heartbeat_url_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_DATA_HEARTBEAT_URL"
  value      = betteruptime_heartbeat.git_data_prd.url
  visibility = "masked"
}
