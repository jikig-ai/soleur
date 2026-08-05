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
# are what a size check needs, and each stub is a length UPPER BOUND on its real value.
#
# Nine of the twelve are byte-identical copies of the real literal, so the bound is exact. The
# other three were asserted rather than checked until #7299's review: `doppler_token` stubs the
# config slug as `prd_registry` where the real slug is `prd` (+9 B of slack); `registry_volume_id`
# is 9 digits, matching every live hcloud volume id in-repo; and the two heartbeat URLs stub a
# 64-char token, widened from 24 because the real Better Stack token length is NOT derivable from
# anything in this repo (every in-tree sample is synthetic or redacted) — 64 exceeds any plausible
# value, so the bound is true by construction instead of by belief. `zot_memory_cap_mb` (4 digits
# at 8 GB, 5 at 16 GB) and the amd64-only `zot_image` read are exact only while those shapes hold;
# both are single-byte effects against ~23 kB of headroom.
# (Technique mirrored from git-data-userdata-budget.sh, which documents it at length.)
#
# `zot_image` is NOT stubbed — it is read from zot-registry.tf, because the pin's own
# length (the `:vX.Y.Z` tag this change adds) is part of what is being measured.
#
# MEASURE WITH TERRAFORM'S OWN `base64gzip`, NEVER `gzip -9`. They are different
# compression levels and `-9` OVERSTATES headroom. On a hard gate an optimistic
# measurement is worse than none.
#
# Exit 0 under cap, 1 over, 2 UNMEASURABLE. Exit 2 covers: terraform absent in CI; the zot pin
# unreadable; the strip declaration absent, duplicated, not a slash-delimited literal, missing
# `(?m)` or missing `^`; the strip not APPLIED at hcloud_server.registry.user_data; the render or
# base64gzip failing; a stored payload below the 4,000 B plausibility floor; or `#cloud-config`
# not surviving the strip.
#
# Usage: bash apps/web-platform/infra/registry-userdata-budget.sh [--json] [out-rendered]
#   out-rendered receives the STRIPPED render — the bytes that actually reach the host.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON=0
[ "${1:-}" = "--json" ] && { JSON=1; shift; }
OUT="${1:-}"

command -v terraform >/dev/null 2>&1 || {
  # FAIL CLOSED IN CI. A bare SKIP was tolerable while the job carried `continue-on-error: true`;
  # now that it hard-fails, exit 0 here is the ONLY remaining path that reports GREEN having
  # measured nothing — a silently-degraded setup-terraform step would turn the gate off while it
  # looks healthy. Local dev keeps the SKIP so the suite stays runnable without terraform.
  if [ -n "${CI:-}" ]; then
    echo "registry-userdata-budget: terraform is REQUIRED in CI and is not on PATH — refusing to report a pass without measuring" >&2
    exit 2
  fi
  echo "registry-userdata-budget: SKIP — terraform not on PATH (local dev; fails closed in CI)" >&2
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
# LINE-ANCHORED MULTILINE is what makes the strip safe — it cannot touch a substituted
# single-line scalar. That safety needs BOTH the `(?m)` flag and the `^` anchor, so check both:
# checking only `(?m)` (as this did until #7299's review) left the comment above asserting a
# property the code did not enforce, which is this PR's own defect class.
printf '%s' "$STRIP_EXPR" | grep -q '(?m)' || {
  echo "registry-userdata-budget: local.registry_rationale_strip is not multiline-anchored ((?m)): ${STRIP_EXPR}" >&2
  exit 2
}
printf '%s' "$STRIP_EXPR" | grep -qF '^' || {
  echo "registry-userdata-budget: local.registry_rationale_strip has no ^ line anchor, so it could match mid-line inside a substituted scalar: ${STRIP_EXPR}" >&2
  exit 2
}

# THE STRIP IS DECLARED — IS IT APPLIED? These are independent facts, and asserting only the
# first is a FAIL-OPEN. Deleting the `replace(...)` wrapper from `hcloud_server.registry` leaves
# the local orphaned (terraform accepts that silently; `validate` stays green), production
# reverts to storing the unstripped 36,404 B payload, and a script that only reads the
# declaration still reports 9,404 B and exit 0 — certifying a tree on which the host cannot be
# created. ADR-152 records this as a MEASURED defect and states the rule: "Assert on the RENDER
# EXPRESSION, not on a string in a file."
#
# The anchor below is the wrapper chain itself, so unwiring it fails closed. Lines are joined
# first because the real expression spans ~40 lines. RESIDUAL SCOPE, stated honestly: this is a
# regex, not a paren-balancing scan, so it proves the chain EXISTS and that the strip is
# referenced — it does not prove the reference sits inside THAT expression. The paren-balanced
# form lives in plugins/soleur/test/cloud-init-user-data-size.test.ts (registryStripIsApplied),
# which runs in the REQUIRED `test` context; this is the cheap fail-closed half.
TF_JOINED="$(tr '\n' ' ' < "$DIR/zot-registry.tf")"
printf '%s' "$TF_JOINED" | grep -qE 'user_data[[:space:]]*=[[:space:]]*base64gzip\([[:space:]]*replace\([[:space:]]*templatefile\(' || {
  echo "registry-userdata-budget: hcloud_server.registry.user_data is not base64gzip(replace(templatefile(...))) — the comment strip is NOT applied to what Hetzner stores, so this measurement would not describe production" >&2
  exit 2
}
printf '%s' "$TF_JOINED" | grep -qF 'local.registry_rationale_strip' || {
  echo "registry-userdata-budget: zot-registry.tf never REFERENCES local.registry_rationale_strip — it is declared but unused, so the stored payload is unstripped" >&2
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
    disk_heartbeat_url     = join("/", ["https://uptime.betterstack.com/api/v1/heartbeat", "STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUB"])
    liveness_heartbeat_url = join("/", ["https://uptime.betterstack.com/api/v1/heartbeat", "STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUB"])
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

raw_out=$(console 'local.rendered')
raw_file="$TFDIR/raw.yml"
printf '%s\n' "$raw_out" | sed -e '1{/^<<EOT$/d}' -e '${/^EOT$/d}' > "$raw_file"

stored=$(console 'local.stored' | tr -d '"')

# RE-CHECK stderr after the LAST console call. The probe above only covered the first one, and
# console() appends (2>>), so a failure in any later call accumulated into a file nothing read —
# emitting `{"raw_bytes":,...}` (malformed JSON) while still exiting 0. That is the same
# fail-open shape this script exists to close, on the figures the fix introduced.
if [ -s "$TFDIR/err" ]; then
  echo "registry-userdata-budget: a terraform console call FAILED after the render probe" >&2
  sed 's/\x1b\[[0-9;]*m//g' "$TFDIR/err" >&2
  exit 2
fi
[ -n "$stored" ] || { echo "registry-userdata-budget: base64gzip failed" >&2; exit 2; }

# MEASURE BYTES, NOT CHARACTERS. The cap is a BYTE cap, and terraform's length() counts grapheme
# clusters — this template carries 152 non-ASCII characters (301 bytes), 23 of which survive the
# strip, so length() under-reports in the OPTIMISTIC direction the header forbids.
#
# An earlier revision of this fix used length() and justified it with "console wraps in <<EOT and
# re-escapes, so the dump is ~300 B larger". That was FALSE: console does not re-escape, and the
# ~300 B being blamed on framing WAS the UTF-8 delta. Measured — length() 74152, dump-minus-EOT
# 74454, real file 74453; the only dump overhead is the single trailing newline printf adds,
# which is what the -1 removes. `wc -c` on the dumped render is also what the git-data sibling
# does, and this script's header claims to mirror it.
raw_bytes=$(( $(wc -c < "$raw_file") - 1 ))
stripped_bytes=$(( $(wc -c < "$rendered") - 1 ))
stored_bytes=${#stored}
cap=32768
headroom=$(( cap - stored_bytes ))

# NON-VACUITY FLOOR (mirrors REGISTRY_GZIP_FLOOR in cloud-init-user-data-size.test.ts). Every
# other assertion here is a CEILING, so a measurement that drifts toward "smaller and safer" is
# invisible — and that is the direction that strands the host. A strip widened to `/(?m)^.*\n/`
# eats the whole payload; base64gzip("") is 40 chars, which reports MAXIMUM headroom and exit 0
# while `#cloud-config` is gone and the host boots dark (LUKS locked, zot never started).
if [ "$stored_bytes" -lt 4000 ]; then
  echo "registry-userdata-budget: stored payload is only ${stored_bytes} B — implausibly small (floor 4000 B). The strip is eating real content, or the render lost its substitutions. A near-empty user_data boots a DARK host, which presents as a green apply." >&2
  exit 2
fi

# The strip preserves `#cloud-config` by construction (no space after `#`), and that one line is
# what makes cloud-init execute the file at all. Assert it survived rather than trusting the
# construction — a dark host is the failure mode with no signal of its own.
head -1 "$rendered" | grep -qx '#cloud-config' || {
  echo "registry-userdata-budget: the stripped render does not begin with '#cloud-config' — cloud-init would not execute it, and the host would boot dark" >&2
  exit 2
}

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
  echo "registry-userdata-budget: OVER CAP by $(( stored_bytes - cap )) bytes — hcloud would reject the CREATE *after* the DESTROY succeeded, stranding the sole pull path." >&2
  # DISCRIMINATE THE TWO CAUSES. Naming only one sends the operator down a days-long path for a
  # one-character defect. If the strip matched (almost) nothing, raw ≈ stripped — the regex is
  # broken (e.g. `#` changed to `//`), which passes every extraction gate above because those
  # check the expression's SHAPE, never that it still matches anything.
  if [ "$stripped_bytes" -ge $(( raw_bytes / 2 )) ]; then
    echo "  CAUSE: the strip matched almost nothing (raw ${raw_bytes} B -> stripped ${stripped_bytes} B). Check local.registry_rationale_strip in zot-registry.tf — this is a broken regex, NOT payload growth." >&2
  else
    echo "  CAUSE: the strip is working (raw ${raw_bytes} B -> stripped ${stripped_bytes} B), so this is real payload growth. Bake new host logic into the image instead of inlining it (the ADR-080/#5921 pattern)." >&2
  fi
  exit 1
fi
