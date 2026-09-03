# (#7025, R7) THE SINGLE RENDER OF git-data's user_data, called by BOTH roots.
#
# WHY THIS IS A MODULE AND NOT A THIRD COPY. The rung-2 rehearsal boots the git-data
# cloud-init on a throwaway host so the FIRST real boot of that template is not the
# production host holding every connected user's source code. The evidence it produces is
# bound by a hash — but that hash is over SOURCE FILES, so if the rehearsal root carried its
# own copy of the templatefile map and its own `git_data_rationale_strip`, a divergence
# between the two copies yields a BYTE-IDENTICAL hash for a DIFFERENT render. The
# self-invalidation property the gate exists to provide does not fire on that class at all:
# the rehearsal would attest a payload it did not boot, and the attestation would verify.
#
# A parity test comparing two copies was the alternative, and it is structurally a
# two-file comparator being asked to keep three files equal. One render, called twice, has
# no drift to detect.
#
# WHAT STILL HAS A SECOND COPY, deliberately: git-data-userdata-budget.sh hand-mirrors this
# map to measure the Hetzner 32,768 B cap from an empty scratch dir with no `terraform init`.
# git-data-render-strip-parity.test.sh keeps that copy equal to THIS one, and is retargeted
# here (it used to target git-data.tf).
#
# PATHS ARE `${path.module}/../../`, and that is load-bearing rather than incidental. The
# nine payloads and the template live in apps/web-platform/infra/; this module lives two
# levels below it. The rung-2 gate derives its hash-input set by grepping THIS FILE for
# `file("${path.module}/…")` and resolving each hit against this directory — see
# tests/scripts/lib/git-data-birth-readiness-gate.sh. Moving a payload without moving the
# reference trips that gate's floor-of-10 ABORT rather than silently narrowing what the
# evidence is bound to.

# (#6982, ADR-152) THE RATIONALE STRIP. Removes whole-line `#` comments from the nine
# injected scripts/units AT RENDER TIME, so the repo keeps its rationale and user_data does
# not pay for it. Hetzner's cap is a hard 32,768 B ForceNew gate and comments were 61% of the
# raw payload; without this, every safety comment competes with a fail-closed invariant for
# space, which on a host where a green apply and a dark host are indistinguishable is the
# wrong trade.
#
# THE TEMPLATE IS NOW STRIPPED TOO, BY A SECOND AND DELIBERATELY DIFFERENT EXPRESSION
# (#7264). ADR-152 rules that these two expressions are "deliberately not shared, and must
# not be", and gives the reason: the nine payloads have no `#`-directive but do have a
# shebang, so preserving `#!` alone is correct for them — and WRONG for a cloud-init
# template, because `#cloud-config` is a directive that is a comment by syntax. Stripping it
# does not fail: the apply succeeds, the host boots, and cloud-init never recognises the
# payload, so none of it runs — the dark-host indistinguishability ADR-149 names, reached
# through the mechanism ADR-152 introduced. `git_data_template_rationale_strip` below is the
# registry's expression (zot-registry.tf), which preserves `#!` AND any `#`-directive by
# construction rather than by enumeration. Do not merge the two.
#
# ANCHORED AT LINE START, and `#!` is preserved by construction. `${var#...}` and other
# mid-line `#` are untouched because the match must begin the line; a `#`-anywhere rule
# (`s/#.*//`) breaks four of the six scripts on parameter expansion — measured.
# Preserving `#!` is not cosmetic: git-data-provision.sh, -remove.sh and -transport-wrapper.sh
# are invoked via authorized_keys `command="..."`, so a lost shebang does NOT fail loudly —
# it silently falls back to dash.
#
# TWO INVARIANTS THIS EXPRESSION MUST KEEP, both load-bearing for downstream parsers in
# plugins/soleur/test/cloud-init-user-data-size.test.ts: it contains NO brace (that file
# counts brace depth to find the templatefile map), and every map entry below stays on ONE
# physical line (its var parser is line-based). git-data-userdata-budget.sh mirrors this
# expression byte-for-byte; git-data-render-strip-parity.test.sh is what keeps them equal.
locals {
  git_data_rationale_strip          = "/(?m)^[ \t]*#([^!\n][^\n]*)?\n/"
  git_data_template_rationale_strip = "/(?m)^[ \t]*#([ \t][^\n]*)?\n/"
}

# THE DOPPLER ARCH PAIR IS DERIVED HERE, and that location is the point.
#
# Both roots previously received `doppler_arch` and `doppler_sha256` as module INPUTS, each
# computing them with its own ternary — so the checksum literals existed in git-data.tf AND in
# rung2-rehearsal/rehearsal.tf, uncompared. Measured: applying a Doppler version bump to
# git-data.tf only left EVERY suite green (54/0, 28/0, 35/0, 97/0, 129/0) while the rehearsal
# downloaded and verified a DIFFERENT binary than production — the #6570 boot-brick class, in
# the rehearsal that exists to rule it out.
#
# Deriving inside the module makes that divergence UNEXPRESSIBLE rather than merely tested:
# there is one ternary, one pair of literals, and callers pass a server type. It also removes
# the pair from the module's variable surface, so it cannot appear in RUNG2_VAR_DIVERGENCE at
# all — a structural guarantee in place of a declaration the gate had to police.
locals {
  git_data_arch           = startswith(var.git_data_server_type, "cax") ? "arm64" : "amd64"
  git_data_doppler_sha256 = local.git_data_arch == "arm64" ? "f1954f3717fe4c5b65e906a3c6dfe0d20e97b032af35e43db41250931302e143" : "9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"
}

locals {
  rendered = replace(templatefile("${path.module}/../../cloud-init-git-data.yml", {
    git_data_bootstrap               = replace(file("${path.module}/../../git-data-bootstrap.sh"), local.git_data_rationale_strip, "")
    git_data_pre_receive_placeholder = replace(file("${path.module}/../../git-data-pre-receive-placeholder.sh"), local.git_data_rationale_strip, "")
    # The FIXED provision forced-command wrapper (git init --bare), delivered to
    # /usr/local/bin like the bootstrap (ADR provisioning amendment).
    git_data_provision = replace(file("${path.module}/../../git-data-provision.sh"), local.git_data_rationale_strip, "")
    # The TRANSPORT allowlist forced-command wrapper (Sub-PR 3.D) — replaces the raw
    # git-shell forced command; delivered to /usr/local/bin like the others.
    git_data_transport_wrapper = replace(file("${path.module}/../../git-data-transport-wrapper.sh"), local.git_data_rationale_strip, "")
    # The FIXED erasure forced-command wrapper (rm -rf <id>.git), Art. 17 (3.A;
    # app-side call lands in 3.D). Delivered to /usr/local/bin like the others.
    git_data_remove = replace(file("${path.module}/../../git-data-remove.sh"), local.git_data_rationale_strip, "")
    # (#6982, W4) The bounded maintenance unit set. Plain text like its siblings, so it
    # gzips instead of paying base64's 33 % inflation against the 32 KB user_data cap.
    git_data_gc                 = replace(file("${path.module}/../../git-data-gc.sh"), local.git_data_rationale_strip, "")
    git_data_gc_service         = replace(file("${path.module}/../../git-data-gc.service"), local.git_data_rationale_strip, "")
    git_data_gc_failure_service = replace(file("${path.module}/../../git-data-gc-failure.service"), local.git_data_rationale_strip, "")
    git_data_gc_timer           = replace(file("${path.module}/../../git-data-gc.timer"), local.git_data_rationale_strip, "")
    # trimspace()'d by the CALLER — see local.git_transport_pubkey in git-data.tf.
    git_transport_pubkey = var.git_transport_pubkey
    git_provision_pubkey = var.git_provision_pubkey
    git_remove_pubkey    = var.git_remove_pubkey
    # Mount the bare-repo volume by its specific id (server.tf/cloud-init.yml
    # by-id pattern). Known at plan time; the attachment is a separate resource.
    git_data_volume_id = var.git_data_volume_id
    # The FRESH LUKS-at-rest cutover volume (Sub-PR 3.D, git-data-luks.tf). Guest-side
    # cryptsetup luksOpens + mounts it at /mnt/git-data-luks. by-id like the plaintext one.
    git_data_luks_volume_id = var.git_data_luks_volume_id
    # Doppler service token → 0600 root env file so the boot-time `doppler run` can read
    # GIT_DATA_LUKS_KEY and (since #6982) BETTERSTACK_LOGS_TOKEN. SCOPED read-only token
    # for ONE config — NOT the full-prd var.doppler_token (3.D security review MEDIUM /
    # CTO ruling: a git-data-host compromise must not yield service-role / GIT_REMOVE /
    # PROXY_TLS material). The passphrase itself is NEVER in this user_data.
    doppler_token = var.doppler_token
    # (#7025, R1) The config the two boot-time `doppler run` invocations name, and the
    # config var.doppler_token must be scoped to. THESE TWO MUST AGREE — measured under an
    # identically-scoped token, naming a config the token does not cover exits 1 with the
    # key ABSENT, so `doppler run` never execs the LUKS heredoc, its `set -euo pipefail`
    # runs ZERO times, luksOpen never runs, and the host boots dark with sshd up (#6982 W0).
    # Prod passes "prd_git_data"; the rehearsal passes its scratch config, which is the ONE
    # reason this is a variable rather than the literal it was until #7025.
    doppler_config_name = var.doppler_config_name
    # Dual-arch Doppler CLI download (#6570). BOTH are derived HERE, ten lines above, from
    # var.git_data_server_type — by the caller until #7025 R7 moved the derivation into this
    # module so both roots render through one copy — the cloud-init hardcoded the arm64 build and its checksum,
    # which boot-bricks the moment the type moves to an x86 arm. `${doppler_arch}` is a
    # TERRAFORM interpolation (single-$) in the template; `$${DOPPLER_VERSION}` beside it is
    # a SHELL variable (double-$) that must pass through literally.
    #
    # These are on the rung-2 MUST-MATCH set, not the divergence allowlist: they select
    # WHICH BINARY is downloaded and WHICH CHECKSUM verifies it, so a rehearsal that
    # diverged here would rehearse a boot-brick class (#6570) the production boot does not
    # have, or miss the one it does.
    doppler_arch   = local.git_data_arch
    doppler_sha256 = local.git_data_doppler_sha256
    # (#6982, W1) The off-host emitter's three inputs.
    #
    # sentry_dsn is BAKED, and that is the point: it is the ONE channel that still works
    # when Doppler is the broken stage, which on this host is the most likely stage to
    # break. It is semi-public (already in the client bundle; variables.tf says so) and
    # lands in tfstate + metadata-retrievable user_data — accepted, and the reason the
    # LUKS passphrase is deliberately NOT baked.
    #
    # SUPERSEDED IN PART BY #7460 (ADR-198): the Better Stack INGEST token IS now baked, and
    # this comment used to name it alongside the LUKS passphrase. That sentence sat INSIDE a
    # digest input — main.tf is one of the files the evidence hash binds — so leaving it would
    # have attested a falsehood. The two credentials are NOT the same case: the ingest token's
    # ceiling is write-only append to a telemetry sink, while the passphrase decrypts every
    # user's source at rest AND defends a control the privacy policy publicly claims. ADR-198
    # states that as a three-part capability test rather than as a derivability argument,
    # because the derivability argument licenses baking the passphrase too.
    #
    # This interpolation is also the birth-readiness INTERLOCK's sentinel:
    # git-data-birth-readiness-gate.sh refuses to plan while `${sentry_dsn}` is absent
    # from non-comment template text. `templatefile` fails on an unsupplied variable, so
    # threading it here IS the work — the sentinel cannot be faked by a comment.
    sentry_dsn             = var.sentry_dsn
    betterstack_ingest_url = var.betterstack_ingest_url
    betterstack_logs_token = var.betterstack_logs_token
    # Baked at RENDER time, so it is a create-time constant rather than a runtime-
    # guaranteed invariant — it discriminates git-data's rows from its siblings on the
    # shared Better Stack source 2457081. The rehearsal diverges here BY DESIGN: it is
    # what lets the capture script isolate a rehearsal boot's rows from prod's.
    host_name = var.host_name
  }), local.git_data_template_rationale_strip, "")
}
