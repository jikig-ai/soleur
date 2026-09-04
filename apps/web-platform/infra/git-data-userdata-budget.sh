#!/usr/bin/env bash
#
# (#6982) Render cloud-init-git-data.yml exactly as modules/git-data-userdata does, and
# measure the STORED user_data the way Hetzner measures it.
#
# (#7025, R7) The render moved OUT of git-data.tf and into modules/git-data-userdata/main.tf
# so the rung-2 rehearsal root can call the same one. This script still hand-mirrors that
# map rather than calling the module, and that is deliberate: calling it would require
# `terraform init` in the scratch dir, where today an EMPTY dir with no providers, no
# backend and no credentials is enough. git-data-render-strip-parity.test.sh is retargeted
# at the module and is what keeps this copy equal to it.
#
# WHY THIS IS A COMMITTED SCRIPT rather than a one-off command. Hetzner's user_data cap
# (32,768 bytes) is a HARD gate on `hcloud_server.git_data`, and every byte of the
# template plus all five injected scripts counts toward it. The file has no
# `lifecycle.ignore_changes = [user_data]`, so it is ForceNew: the first person to learn
# they blew the budget would otherwise learn it from a failing birth apply.
#
# MEASURE WITH TERRAFORM'S OWN `base64gzip`, NEVER `gzip -9`. They are different
# compression levels and `-9` OVERSTATES headroom — the plan for #6982 quoted ~10.8 KB of
# headroom measured with `-9`; the real figure at that commit was 9,052 B. On a hard gate
# an optimistic measurement is worse than none.
#
# Exit 0 under cap, 1 over, 2 if the render itself failed.
#
# Usage: bash apps/web-platform/infra/git-data-userdata-budget.sh [--json] [out-rendered] [out-raw]
#   out-rendered receives the STRIPPED render — the bytes the host is actually given, after
#                local.git_data_template_rationale_strip. This is the host-truth artifact and
#                is what every boot-fidelity predicate must read.
#   out-raw      receives the UNSTRIPPED render. Optional. Its consumer is
#                git-data-template-strip.test.sh, which needs both documents to compare them
#                (shebang survival, the saving bound, and the per-entry diff). An earlier
#                version of this comment claimed it existed so the runcmd rehearsal could
#                "keep one arm on a corpus that still contains comments" -- that suite reads
#                it only for a comment-count sanity check, and no predicate arm runs against
#                it, so the discriminating power that sentence promised does not exist.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON=0
[ "${1:-}" = "--json" ] && { JSON=1; shift; }
OUT="${1:-}"
RAW_OUT="${2:-}"

command -v terraform >/dev/null 2>&1 || {
  echo "git-data-userdata-budget: SKIP — terraform not on PATH" >&2
  exit 0
}

TFDIR=$(mktemp -d -t gdbudget.XXXXXXXX)
trap 'rm -rf "$TFDIR"' EXIT

# templatefile()/base64gzip() are builtins, so an EMPTY scratch dir needs no providers, no
# backend and no credentials — this never touches state. The expression lives in a
# `locals` block because `terraform console` reads ONE expression per LINE and collapsing
# a multi-line HCL object produces "Missing attribute separator".
#
# Stub values match the SHAPE git-data.tf passes; arch/sha256 are the amd64 branch of
# local.git_data_arch (cpx22 default). Stub LENGTHS are what matter for a size check, and
# the real pubkeys/ids/token are all shorter than or equal to these.
cat > "$TFDIR/main.tf" <<EOF
locals {
  git_data_rationale_strip          = "/(?m)^[ \\t]*#([^!\\n][^\\n]*)?\\n/"
  git_data_template_rationale_strip = "/(?m)^[ \\t]*#([ \\t][^\\n]*)?\\n/"
  vars = {
    git_data_bootstrap               = replace(file("${DIR}/git-data-bootstrap.sh"), local.git_data_rationale_strip, "")
    git_data_pre_receive_placeholder = replace(file("${DIR}/git-data-pre-receive-placeholder.sh"), local.git_data_rationale_strip, "")
    git_data_provision               = replace(file("${DIR}/git-data-provision.sh"), local.git_data_rationale_strip, "")
    git_data_transport_wrapper       = replace(file("${DIR}/git-data-transport-wrapper.sh"), local.git_data_rationale_strip, "")
    git_data_remove                  = replace(file("${DIR}/git-data-remove.sh"), local.git_data_rationale_strip, "")
    git_data_gc                      = replace(file("${DIR}/git-data-gc.sh"), local.git_data_rationale_strip, "")
    git_data_gc_service              = replace(file("${DIR}/git-data-gc.service"), local.git_data_rationale_strip, "")
    git_data_gc_failure_service      = replace(file("${DIR}/git-data-gc-failure.service"), local.git_data_rationale_strip, "")
    git_data_gc_timer                = replace(file("${DIR}/git-data-gc.timer"), local.git_data_rationale_strip, "")
    git_transport_pubkey             = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISTUBTRANSPORTKEYAAAAAAAAAAAAAAAAAAAAA"
    git_provision_pubkey             = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISTUBPROVISIONKEYAAAAAAAAAAAAAAAAAAAAA"
    git_remove_pubkey                = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISTUBREMOVEKEYAAAAAAAAAAAAAAAAAAAAAAAA"
    git_data_volume_id               = "100000001"
    git_data_luks_volume_id          = "100000002"
    # Built by join() rather than written as one literal: a contiguous dp.<type>.<...>
    # string is a real Doppler-service-token SHAPE, and GitHub Push Protection blocks the
    # push on it even though the value is synthetic (cq-test-fixtures-synthesized-only
    # still applies — this keeps the shape and length, which is all a size check needs,
    # without putting a matchable literal in the file).
    doppler_token                    = join(".", ["dp", "st", "prd_git_data", "STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTU"])
    doppler_config_name              = "prd_git_data"
    doppler_arch                     = "amd64"
    doppler_sha256                   = "9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"
    sentry_dsn                       = "https://stubkey0000000000000000000000@o1234567.ingest.de.sentry.io/7654321"
    betterstack_ingest_url           = "https://s2734275.eu-central-1a.betterstackdata.com/"
    betterstack_logs_token           = "stub-betterstack-ingest-token-0000000000"
    host_name                        = "soleur-git-data"
  }

  rendered = templatefile("${DIR}/cloud-init-git-data.yml", local.vars)
  stripped = replace(local.rendered, local.git_data_template_rationale_strip, "")
  stored   = base64gzip(local.stripped)
}
EOF

console() { printf '%s\n' "$1" | terraform -chdir="$TFDIR" console 2>>"$TFDIR/err"; }

raw=$(console 'local.rendered')
# A render FAILURE still prints a warning banner and "(known after apply)" on stdout, so
# emptiness is not the tell — look for the diagnostic explicitly. Fail-closed: an
# unmeasurable template must never read as one that fits.
if [ -s "$TFDIR/err" ] || printf '%s' "$raw" | grep -q 'known after apply'; then
  echo "git-data-userdata-budget: RENDER FAILED" >&2
  sed 's/\x1b\[[0-9;]*m//g' "$TFDIR/err" >&2
  exit 2
fi

raw_render="$TFDIR/raw.yml"
printf '%s\n' "$raw" | sed -e '1{/^<<EOT$/d}' -e '${/^EOT$/d}' > "$raw_render"

# The STRIPPED render is the host-truth artifact. Read it from terraform rather than
# re-implementing the strip here: a second implementation is exactly the restatement
# ADR-152's registry precedent records as the defect that produced a phantom cap breach.
stripped_raw=$(console 'local.stripped')
# CHECKED, because the guard below would otherwise blame the wrong thing. A failed console
# here yields an empty render, the `#cloud-config` header guard fires, and it tells the
# reader to go look at local.git_data_template_rationale_strip -- for a terraform fault. The
# sibling `stored` read is guarded; this one was not.
if [ -z "$stripped_raw" ] || [ -s "$TFDIR/err" ]; then
  echo "git-data-userdata-budget: terraform console failed evaluating local.stripped" >&2
  sed 's/\x1b\[[0-9;]*m//g' "$TFDIR/err" >&2
  exit 2
fi
rendered="$TFDIR/rendered.yml"
printf '%s\n' "$stripped_raw" | sed -e '1{/^<<EOT$/d}' -e '${/^EOT$/d}' > "$rendered"

stored=$(console 'local.stored' | tr -d '"')
[ -n "$stored" ] || { echo "git-data-userdata-budget: base64gzip failed" >&2; exit 2; }

raw_bytes=$(wc -c < "$raw_render")
stripped_bytes=$(wc -c < "$rendered")
stored_bytes=${#stored}
cap=32768
headroom=$(( cap - stored_bytes ))

# THE HEADER GUARD. `#cloud-config` is a directive that is a comment by syntax, so a strip
# expression one character too permissive deletes it. Nothing downstream fails loudly: the
# apply succeeds, the host boots, and cloud-init never recognises the payload. Assert the
# first line of the STRIPPED render, because that is the document the host is handed.
if [ "$(head -1 "$rendered")" != "#cloud-config" ]; then
  echo "git-data-userdata-budget: the stripped render does not begin with '#cloud-config' — cloud-init would not execute it and the host would boot dark. Check local.git_data_template_rationale_strip." >&2
  exit 1
fi

# THE NOT-A-NO-OP GUARD (ADR-152's third verification arm). A strip that matched nothing
# satisfies every preservation check while delivering none of the saving, and the only
# symptom is a cap breach much later.
if [ "$stripped_bytes" -ge "$raw_bytes" ]; then
  echo "git-data-userdata-budget: the strip removed nothing (raw ${raw_bytes} B -> stripped ${stripped_bytes} B). local.git_data_template_rationale_strip is not matching." >&2
  exit 1
fi

[ -n "$OUT" ] && cp "$rendered" "$OUT"
[ -n "$RAW_OUT" ] && cp "$raw_render" "$RAW_OUT"

if [ "$JSON" -eq 1 ]; then
  printf '{"raw":%s,"stripped":%s,"stored":%s,"cap":%s,"headroom":%s}\n' \
    "$raw_bytes" "$stripped_bytes" "$stored_bytes" "$cap" "$headroom"
else
  echo "git-data user_data: stored=${stored_bytes} B / cap=${cap} B (headroom ${headroom} B, raw ${raw_bytes} B, stripped ${stripped_bytes} B)"
fi

if [ "$stored_bytes" -ge "$cap" ]; then
  echo "git-data-userdata-budget: OVER CAP by $(( -headroom )) bytes — the birth apply would fail." >&2
  exit 1
fi
