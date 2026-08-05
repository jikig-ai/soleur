#!/usr/bin/env bash
#
# (#7282) Render cloud-init-registry.yml exactly as zot-registry.tf does, and measure the
# STORED user_data the way Hetzner measures it.
#
# (#7299) "EXACTLY AS zot-registry.tf DOES" INCLUDES THE COMMENT STRIP, AND ORIGINALLY DID NOT.
# The .tf renders base64gzip(replace(templatefile(...), local.registry_rationale_strip, "")).
# This script rendered templatefile(...) RAW, so it measured a payload no host is ever given:
# 36,404 B against the 32,768 B cap — a phantom -3,636 B breach on a registry whose real stored
# artifact is ~9.4 kB with ~23.4 kB of headroom. #7299 was filed against that reading as an
# outage ("the registry host cannot be re-provisioned"); it could be re-provisioned the whole
# time. A measurement tool that is wrong in the FAIL-LOUD direction still costs an incident's
# worth of operator judgement, so the strip is now extracted from the .tf and applied here.
#
# WHY THIS IS A COMMITTED SCRIPT rather than a one-off command. Hetzner's user_data cap
# (32,768 bytes) is a HARD gate on `hcloud_server.registry`, and that resource carries NO
# `lifecycle.ignore_changes = [user_data]` by design — the replace IS the intended
# reprovision path. So user_data is ForceNew, and blowing the budget is not a plan-time
# warning: hcloud rejects the CREATE *after* the destroy has already succeeded, stranding
# the registry. On the sole pull path that is an outage, not an inconvenience.
#
# WHY IT RENDERS OFFLINE. templatefile()/base64gzip() are terraform BUILTINS, so an EMPTY
# scratch dir needs no providers, no S3 backend and no credentials, and never touches
# state. The real root's registry templatefile map consumes hcloud_volume.registry.id,
# doppler_service_token.registry.key and two betteruptime_heartbeat URLs — measuring on it
# would require Doppler prd_terraform and would be unrunnable on a fork PR. Stub LENGTHS
# are what a size check needs; the real ids/tokens/URLs are <= these.
# (Technique mirrored from git-data-userdata-budget.sh, which documents it at length.)
#
# `zot_image` is NOT stubbed — it is read from zot-registry.tf, because the pin's own
# length (the `:vX.Y.Z` tag this change adds) is part of what is being measured.
#
# MEASURE WITH TERRAFORM'S OWN `base64gzip`, NEVER `gzip -9`. They are different
# compression levels and `-9` OVERSTATES headroom. On a hard gate an optimistic
# measurement is worse than none.
#
# Exit 0 under cap, 1 over, 2 if the render itself failed.
#
# Usage: bash apps/web-platform/infra/registry-userdata-budget.sh [--json] [out-rendered]
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON=0
[ "${1:-}" = "--json" ] && { JSON=1; shift; }
OUT="${1:-}"

command -v terraform >/dev/null 2>&1 || {
  echo "registry-userdata-budget: SKIP — terraform not on PATH" >&2
  exit 0
}

# The amd64 branch of local.zot_image (registry_arch is amd64 for the cx23 default). Read
# from the .tf so the measurement tracks the real pin rather than a copy that can rot.
# Anchored on the ASSIGNMENT, like the staleness gate -- an unanchored grep is satisfied by
# a comment (e.g. a rollback annotation above the locals), which would measure the wrong
# reference length. Same fact, same parse rule, everywhere.
ZOT_IMAGE="$(grep -oE '^[[:space:]]*zot_image_amd64[[:space:]]*=[[:space:]]*"ghcr\.io/project-zot/zot-linux-amd64:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}"' "$DIR/zot-registry.tf" | grep -oE 'ghcr\.io[^"]*' | head -1)"
[ -n "$ZOT_IMAGE" ] || {
  echo "registry-userdata-budget: could not read local.zot_image_amd64 from zot-registry.tf" >&2
  exit 2
}

# The comment strip, EXTRACTED from zot-registry.tf — never restated here. That file declares
# it ONCE and both consumers (this script and plugins/soleur/test/cloud-init-user-data-size.
# test.ts) read it from there, so the "ONE COPY" invariant the .tf asserts is enforced by
# construction rather than by a parity comparator. git-data needs a parity suite because it
# genuinely has two COPIES; there is nothing here to keep equal.
#
# The raw SOURCE TEXT is re-emitted verbatim (quotes included) into the scratch locals block,
# so HCL's own escape handling produces a byte-identical string — \t and \n are unescaped once,
# by terraform, exactly as they are in the real root.
#
# FAIL CLOSED on anything ambiguous. Exit 2 (unmeasurable), never 0 (fits) and never 1 (over):
# an absent or duplicated declaration means we cannot know what production stores, and reading
# that as "fits" is the precise failure #7299 was filed against, inverted.
STRIP_DECLS="$(grep -cE '^[[:space:]]*registry_rationale_strip[[:space:]]*=' "$DIR/zot-registry.tf")"
[ "$STRIP_DECLS" = "1" ] || {
  echo "registry-userdata-budget: expected exactly ONE local.registry_rationale_strip assignment in zot-registry.tf, found ${STRIP_DECLS}" >&2
  exit 2
}
STRIP_EXPR="$(grep -oE '^[[:space:]]*registry_rationale_strip[[:space:]]*=[[:space:]]*"[^"]*"' "$DIR/zot-registry.tf" | sed -e 's/^[^=]*=[[:space:]]*//')"
case "$STRIP_EXPR" in
  '"/'*'/"') ;;
  *)
    echo "registry-userdata-budget: local.registry_rationale_strip is not a slash-delimited terraform regex literal: ${STRIP_EXPR}" >&2
    exit 2
    ;;
esac
# Line-anchored multiline is what makes the strip safe (it cannot touch a substituted single-line
# scalar). If that anchor ever disappears the measurement is no longer the one being reasoned
# about, so refuse rather than measure something else.
printf '%s' "$STRIP_EXPR" | grep -q '(?m)' || {
  echo "registry-userdata-budget: local.registry_rationale_strip is not multiline-anchored ((?m)): ${STRIP_EXPR}" >&2
  exit 2
}

TFDIR=$(mktemp -d -t regbudget.XXXXXXXX)
trap 'rm -rf "$TFDIR"' EXIT

# The expression lives in a `locals` block because `terraform console` reads ONE expression
# per LINE and collapsing a multi-line HCL object produces "Missing attribute separator".
cat > "$TFDIR/main.tf" <<EOF
locals {
  vars = {
    registry_volume_id     = "100000003"
    doppler_token          = join(".", ["dp", "st", "prd_registry", "STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTU"])
    zot_image              = "${ZOT_IMAGE}"
    zot_pull_user          = "zot-pull"
    zot_push_user          = "zot-push"
    doppler_arch           = "amd64"
    doppler_sha256         = "9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"
    zot_memory_cap_mb      = 3072
    private_ip             = "10.0.1.30"
    # Built by join() rather than written as one literal, mirroring the doppler_token
    # treatment in git-data-userdata-budget.sh. A contiguous
    # uptime.betterstack.com/api/v1/heartbeat/<id> string is a real heartbeat-URL SHAPE, and
    # inngest.test.sh 1.6.2 fails-closed on that shape appearing in any NON-.test.sh file
    # under infra/ — correctly, since a baked heartbeat URL in a delivered artifact would arm
    # a SECOND pusher on one monitor (the dual-pusher state #6552 exists to prevent). This
    # script is a local measurement tool and ships to no host, but the guard cannot know that
    # and should not be widened to trust filenames. join() keeps the rendered LENGTH identical
    # — which is all a size check needs — without putting a matchable literal in the file.
    disk_heartbeat_url     = join("/", ["https://uptime.betterstack.com/api/v1/heartbeat", "STUBSTUBSTUBSTUBSTUBSTUB"])
    liveness_heartbeat_url = join("/", ["https://uptime.betterstack.com/api/v1/heartbeat", "STUBSTUBSTUBSTUBSTUBSTUB"])
    betterstack_ingest_url = "https://s2457081.eu-fsn-3.betterstackdata.com/"
  }

  registry_rationale_strip = ${STRIP_EXPR}

  # The three-stage chain zot-registry.tf performs, in the same order. The strip runs AFTER
  # templatefile so the substituted values above — ids, digests, tokens, all single-line
  # scalars — cannot be touched by a line-anchored match.
  rendered = templatefile("${DIR}/cloud-init-registry.yml", local.vars)
  stripped = replace(local.rendered, local.registry_rationale_strip, "")
  stored   = base64gzip(local.stripped)
}
EOF

console() { printf '%s\n' "$1" | terraform -chdir="$TFDIR" console 2>>"$TFDIR/err"; }

# Render the STRIPPED form — the artifact that is actually delivered — so this probe exercises
# templatefile AND replace, and a strip that breaks the render is caught here rather than
# silently producing a smaller "passing" number.
stripped_out=$(console 'local.stripped')
# A render FAILURE still prints a warning banner and "(known after apply)" on stdout, so
# emptiness is not the tell — look for the diagnostic explicitly. Fail-closed: an
# unmeasurable template must never read as one that fits.
if [ -s "$TFDIR/err" ] || printf '%s' "$stripped_out" | grep -q 'known after apply'; then
  echo "registry-userdata-budget: RENDER FAILED" >&2
  sed 's/\x1b\[[0-9;]*m//g' "$TFDIR/err" >&2
  exit 2
fi

rendered="$TFDIR/rendered.yml"
printf '%s\n' "$stripped_out" | sed -e '1{/^<<EOT$/d}' -e '${/^EOT$/d}' > "$rendered"

stored=$(console 'local.stored' | tr -d '"')
[ -n "$stored" ] || { echo "registry-userdata-budget: base64gzip failed" >&2; exit 2; }

# Sizes come from terraform's own length(), NOT `wc -c` on the console dump: console wraps a
# multi-line string in <<EOT/EOT and re-escapes, so the dump is ~300 B larger than the string.
# For an informational figure that is noise; for the two numbers a reader compares it is drift.
raw_bytes=$(console 'length(local.rendered)')
stripped_bytes=$(console 'length(local.stripped)')
stored_bytes=${#stored}
cap=32768
headroom=$(( cap - stored_bytes ))

# OUT receives the STRIPPED render — the bytes that actually reach the host and boot it.
[ -n "$OUT" ] && cp "$rendered" "$OUT"

if [ "$JSON" -eq 1 ]; then
  printf '{"raw_bytes":%s,"stripped_bytes":%s,"stored_bytes":%s,"cap":%s,"headroom":%s,"zot_image":"%s"}\n' \
    "$raw_bytes" "$stripped_bytes" "$stored_bytes" "$cap" "$headroom" "$ZOT_IMAGE"
else
  echo "registry user_data budget"
  echo "  raw rendered : ${raw_bytes} B"
  echo "  after strip  : ${stripped_bytes} B  (local.registry_rationale_strip, extracted from zot-registry.tf)"
  echo "  stored (b64gzip): ${stored_bytes} B"
  echo "  cap          : ${cap} B"
  echo "  headroom     : ${headroom} B"
  echo "  zot_image    : ${ZOT_IMAGE}"
fi

# -ge, matching git-data-userdata-budget.sh: at EXACTLY the cap the sibling fails and this
# must not disagree. And say what is wrong -- in --json mode the bare test exited 1 with no
# explanation, on the path that is live today.
if [ "$stored_bytes" -ge "$cap" ]; then
  echo "registry-userdata-budget: OVER CAP by $(( stored_bytes - cap )) bytes — hcloud would reject the CREATE *after* the DESTROY succeeded, stranding the sole pull path. The comment strip is ALREADY applied (raw ${raw_bytes} B -> ${stripped_bytes} B), so this is real payload growth, not unstripped prose: bake new host logic into the image instead of inlining it (the ADR-080/#5921 pattern)." >&2
  exit 1
fi
