#!/usr/bin/env bash
#
# (#7695) Render cloud-init-inngest.yml exactly as inngest-host.tf does, and measure the
# STORED user_data the way Hetzner measures it.
#
# WHY THIS EXISTS, AND WHY ITS ABSENCE WAS THE DEFECT. Both sibling base64gzip'd hosts have
# carried a committed byte gate for months — registry-userdata-budget.sh (#7282/#7299) and
# git-data-userdata-budget.sh (#5927). The inngest host never got one. On 2026-09-04, #7778
# (000fa471) grew this template past the cap; the merge apply's `-target=` allow-list contains
# no `hcloud_server.*`, so terraform never planned the resource and never submitted the payload
# to Hetzner for validation. Four days later an `inngest-host-replace` dispatch DESTROYED the
# host and Hetzner rejected the CREATE — `[user_data => [Length must be between 0 and 32768]]`
# — leaving the scheduler host stranded. The destroy-guard and the stock preflight both passed:
# they grade the plan's SHAPE and the datacenter's STOCK, and neither weighs the payload.
#
# So this gate closes two things at once: it measures the byte truth on every infra PR, and it
# gives the `-target`-scoped merge path a size check it structurally cannot get from the plan.
#
# WHY IT RENDERS OFFLINE. templatefile()/base64gzip()/replace() are terraform BUILTINS, so an
# EMPTY scratch dir needs no providers, no S3 backend and no credentials, and never touches
# state. The real root's map consumes hcloud_volume.inngest_redis.id,
# doppler_service_token.inngest.key and random_password.zot_pull.result — measuring on it would
# require Doppler prd_terraform and would be unrunnable on a fork PR. Stub LENGTHS are what a
# size check needs, and each stub below is a length UPPER BOUND on its real value.
#
# THE BOUNDS, each justified rather than asserted (the #7299 review's standard):
#   * `sdk_url`, `zot_registry_endpoint`, `zot_pull_user`, `web_host_private_ips` — byte-identical
#     copies of the real values, which are literals in this root (inngest-host.tf and
#     zot-registry.tf). Exact, not bounds.
#   * `zot_pull_token` — exactly 40, from `random_password.zot_pull { length = 40 }`. Exact.
#   * the three `*_sha256` values — 64 hex, and BOTH arch branches are 64 hex, so exact.
#   * `inngest_volume_id` — 9 digits, matching every live hcloud volume id in-repo.
#   * `inngest_expect_luks` — "false" (5 B) is the LONGER of the two `tostring(bool)` forms, so
#     it bounds the "true" recut branch too.
#   * `doppler_arch` / `inngest_cli_arch` — "amd64" and "arm64" are both 5 B, so this render is
#     ARCH-NEUTRAL in length and the measurement holds for either `var.inngest_server_type`.
#   * `ghcr_read_user` — 39 B, GitHub's maximum login length. True by construction.
#   * `ghcr_read_token` — 128 B, comfortably over a `github_pat_` fine-grained PAT (~93 B).
#   * `doppler_token` — a `dp.st.<config>.<body>` service token on project `soleur-inngest`,
#     config `prd`; stubbed with a 48 B body, over the ~43 B Doppler emits.
#   * `betterstack_logs_token` — 64 B. The real Better Stack token length is NOT derivable from
#     anything in this repo (every in-tree sample is synthetic or redacted), so the bound is made
#     true by construction rather than by belief. Same reasoning, same width, as the registry
#     sibling's heartbeat-token stub.
#
# MEASURE WITH TERRAFORM'S OWN `base64gzip`, NEVER `gzip -9`. They are different compression
# levels and `-9` OVERSTATES headroom. On a hard gate an optimistic measurement is worse
# than none.
#
# MEASURE BYTES, NOT CHARACTERS. The cap is a BYTE cap and terraform's `length()` counts grapheme
# clusters, so `length()` under-reports in the OPTIMISTIC direction — by ~278 B on this template,
# whose prose carries 157 non-ASCII characters. That is not hypothetical here: the first revision
# of this change reported "61,102 B of prose removed" in the .tf, which was the CHARACTER count
# and sat 183 B BELOW the provable byte floor. `wc -c` on the dumped render is the byte truth.
#
# Exit 0 under cap, 1 over, 2 UNMEASURABLE. Exit 2 covers: terraform absent in CI; the strip
# declaration absent, duplicated, not a slash-delimited literal, missing `(?m)` or missing `^`;
# any link of the render chain unwired; the plan-time `lifecycle.precondition` missing; the render
# or base64gzip failing; a stored payload below the 4,000 B plausibility floor; or `#cloud-config`
# not surviving the strip.
#
# Usage: bash apps/web-platform/infra/inngest-userdata-budget.sh [--json] [out-rendered]
#   out-rendered receives the STRIPPED render — the bytes that actually reach the host.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON=0
[ "${1:-}" = "--json" ] && { JSON=1; shift; }
OUT="${1:-}"

command -v terraform >/dev/null 2>&1 || {
  # FAIL CLOSED IN CI, matching both siblings. exit 0 here would be the only path that reports
  # GREEN having measured nothing — a silently-degraded setup-terraform step would turn the gate
  # off while it looks healthy. Local dev keeps the SKIP so the suite stays runnable.
  if [ -n "${CI:-}" ]; then
    echo "inngest-userdata-budget: terraform is REQUIRED in CI and is not on PATH — refusing to report a pass without measuring" >&2
    exit 2
  fi
  echo "inngest-userdata-budget: SKIP — terraform not on PATH (local dev; fails closed in CI)" >&2
  exit 0
}

# The comment strip, EXTRACTED from inngest-host.tf — never restated here. That file declares it
# ONCE and all three consumers (this script, plugins/soleur/test/cloud-init-user-data-size.test.ts
# and the render itself) read it from there, so the "ONE COPY" invariant is enforced by
# construction rather than by a parity comparator.
#
# The raw SOURCE TEXT is re-emitted verbatim (quotes included) into the scratch locals block, so
# HCL's own escape handling produces a byte-identical string — \t and \n are unescaped once, by
# terraform, exactly as they are in the real root.
#
# FAIL CLOSED on anything ambiguous: exit 2 (unmeasurable), never 0 (fits) and never 1 (over).
STRIP_DECLS="$(grep -cE '^[[:space:]]*inngest_rationale_strip[[:space:]]*=' "$DIR/inngest-host.tf")"
[ "$STRIP_DECLS" = "1" ] || {
  echo "inngest-userdata-budget: expected exactly ONE local.inngest_rationale_strip assignment in inngest-host.tf, found ${STRIP_DECLS}" >&2
  exit 2
}
STRIP_EXPR="$(grep -oE '^[[:space:]]*inngest_rationale_strip[[:space:]]*=[[:space:]]*"[^"]*"' "$DIR/inngest-host.tf" | sed -e 's/^[^=]*=[[:space:]]*//')"
case "$STRIP_EXPR" in
  '"/'*'/"') ;;
  *)
    echo "inngest-userdata-budget: local.inngest_rationale_strip is not a slash-delimited terraform regex literal: ${STRIP_EXPR}" >&2
    exit 2
    ;;
esac
# LINE-ANCHORED MULTILINE is what makes the strip safe on a production boot document — it cannot
# touch a substituted single-line scalar. That safety needs BOTH the `(?m)` flag and the `^`
# anchor, so check both.
printf '%s' "$STRIP_EXPR" | grep -q '(?m)' || {
  echo "inngest-userdata-budget: local.inngest_rationale_strip is not multiline-anchored ((?m)): ${STRIP_EXPR}" >&2
  exit 2
}
printf '%s' "$STRIP_EXPR" | grep -qF '^' || {
  echo "inngest-userdata-budget: local.inngest_rationale_strip has no ^ line anchor, so it could match mid-line inside a substituted scalar: ${STRIP_EXPR}" >&2
  exit 2
}

# THE STRIP IS DECLARED — IS IT APPLIED? Independent facts; asserting only the first is a
# FAIL-OPEN. This host's render is a THREE-LINK locals chain (hoisted so the precondition below
# can weigh it, since a precondition cannot reference `self`), and breaking ANY link silently
# reverts production to storing the unstripped ~91 kB payload while a declaration-only check
# still reports ~10 kB and exit 0 — certifying a tree on which the host cannot be created.
# ADR-152 records this class and states the rule: assert on the RENDER EXPRESSION, not on a
# string in a file. All three links are checked, plus the reference to the strip itself.
#
# RESIDUAL SCOPE, stated honestly: these are regexes, not a paren-balancing scan, so they prove
# the chain EXISTS and that the strip is referenced — not that the reference sits inside THAT
# expression. The paren-balanced form lives in cloud-init-user-data-size.test.ts
# (inngestStripIsApplied), which runs in the REQUIRED `test` context; this is the cheap
# fail-closed half.
TF_JOINED="$(tr '\n' ' ' < "$DIR/inngest-host.tf")"
chain_link() {
  printf '%s' "$TF_JOINED" | grep -qE "$1" || {
    echo "inngest-userdata-budget: the render chain is UNWIRED — $2. The comment strip is not applied to what Hetzner stores, so this measurement would not describe production" >&2
    exit 2
  }
}
chain_link 'inngest_user_data_plain[[:space:]]*=[[:space:]]*replace\([[:space:]]*templatefile\(' \
  'local.inngest_user_data_plain is not replace(templatefile(...))'
chain_link 'inngest_user_data_b64gz[[:space:]]*=[[:space:]]*base64gzip\([[:space:]]*local\.inngest_user_data_plain[[:space:]]*\)' \
  'local.inngest_user_data_b64gz is not base64gzip(local.inngest_user_data_plain)'
chain_link 'user_data[[:space:]]*=[[:space:]]*local\.inngest_user_data_b64gz' \
  'hcloud_server.inngest.user_data does not read local.inngest_user_data_b64gz'
printf '%s' "$TF_JOINED" | grep -qF 'local.inngest_rationale_strip' || {
  echo "inngest-userdata-budget: inngest-host.tf never REFERENCES local.inngest_rationale_strip — it is declared but unused, so the stored payload is unstripped" >&2
  exit 2
}

# THE PLAN-TIME TRIPWIRE. This script runs on infra PRs; the `lifecycle.precondition` on
# hcloud_server.inngest is what refuses the DESTROY on the dispatch path itself, where no CI job
# is watching. They cover different moments and neither substitutes for the other, so removing
# the precondition must not leave a green gate behind.
printf '%s' "$TF_JOINED" | grep -qE 'precondition[[:space:]]*\{[[:space:]]*condition[[:space:]]*=[[:space:]]*length\([[:space:]]*local\.inngest_user_data_b64gz[[:space:]]*\)' || {
  echo "inngest-userdata-budget: hcloud_server.inngest has lost its user_data lifecycle.precondition. That is the only check standing between an over-cap payload and a destroy-then-fail-to-create on the workflow_dispatch path, where this script does not run." >&2
  exit 2
}

TFDIR=$(mktemp -d -t inngestbudget.XXXXXXXX)
trap 'rm -rf "$TFDIR"' EXIT

# The expression lives in a `locals` block because `terraform console` reads ONE expression per
# LINE and collapsing a multi-line HCL object produces "Missing attribute separator".
cat > "$TFDIR/main.tf" <<EOF
locals {
  vars = {
    inngest_volume_id      = "100000004"
    inngest_expect_luks    = "false"
    doppler_token          = join(".", ["dp", "st", "prd", "STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUB"])
    sdk_url                = "http://10.0.1.10:3000/api/inngest"
    inngest_cli_arch       = "amd64"
    inngest_cli_sha256     = "d023b26659275fdbe9348b6518077ce1ea9906a449898e49ddced91bfc6fd757"
    vector_sha256          = "8a3cc62d18ec88bb8433159d1d3455d3c77fefff73ce46d4f8cc464e100f65f1"
    doppler_arch           = "amd64"
    doppler_sha256         = "9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"
    ghcr_read_user         = "STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTU"
    ghcr_read_token        = join("_", ["github", "pat", "STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUB"])
    zot_registry_endpoint  = "10.0.1.30:5000"
    zot_pull_user          = "zot-pull"
    zot_pull_token         = "STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUB"
    web_host_private_ips   = "10.0.1.10,10.0.1.11"
    betterstack_logs_token = "STUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUBSTUB"
  }

  inngest_rationale_strip = ${STRIP_EXPR}

  # The three-stage chain inngest-host.tf performs, in the same order. The strip runs AFTER
  # templatefile so the substituted values above — ids, digests, tokens, all single-line
  # scalars — cannot be touched by a line-anchored match.
  rendered = templatefile("${DIR}/cloud-init-inngest.yml", local.vars)
  stripped = replace(local.rendered, local.inngest_rationale_strip, "")
  stored   = base64gzip(local.stripped)
}
EOF

console() { printf '%s\n' "$1" | terraform -chdir="$TFDIR" console 2>>"$TFDIR/err"; }

# Render the STRIPPED form — the artifact actually delivered — so this probe exercises
# templatefile AND replace, and a strip that breaks the render is caught here rather than
# silently producing a smaller "passing" number.
stripped_out=$(console 'local.stripped')
# A render FAILURE still prints a warning banner and "(known after apply)" on stdout, so
# emptiness is not the tell — look for the diagnostic explicitly.
if [ -s "$TFDIR/err" ] || printf '%s' "$stripped_out" | grep -q 'known after apply'; then
  echo "inngest-userdata-budget: RENDER FAILED" >&2
  sed 's/\x1b\[[0-9;]*m//g' "$TFDIR/err" >&2
  exit 2
fi

rendered="$TFDIR/rendered.yml"
printf '%s\n' "$stripped_out" | sed -e '1{/^<<EOT$/d}' -e '${/^EOT$/d}' > "$rendered"

raw_out=$(console 'local.rendered')
raw_file="$TFDIR/raw.yml"
printf '%s\n' "$raw_out" | sed -e '1{/^<<EOT$/d}' -e '${/^EOT$/d}' > "$raw_file"

stored=$(console 'local.stored' | tr -d '"')

# RE-CHECK stderr after the LAST console call. console() appends (2>>), so a failure in any later
# call would otherwise accumulate into a file nothing read — emitting malformed JSON while still
# exiting 0, which is the fail-open shape this script exists to close.
if [ -s "$TFDIR/err" ]; then
  echo "inngest-userdata-budget: a terraform console call FAILED after the render probe" >&2
  sed 's/\x1b\[[0-9;]*m//g' "$TFDIR/err" >&2
  exit 2
fi
[ -n "$stored" ] || { echo "inngest-userdata-budget: base64gzip failed" >&2; exit 2; }

# BYTES, per the header. The -1 removes the single trailing newline printf added to the dump.
# `stored` is base64, hence ASCII, so ${#stored} is a byte count there.
raw_bytes=$(( $(wc -c < "$raw_file") - 1 ))
stripped_bytes=$(( $(wc -c < "$rendered") - 1 ))
stored_bytes=${#stored}
removed_bytes=$(( raw_bytes - stripped_bytes ))
cap=32768
headroom=$(( cap - stored_bytes ))

# NON-VACUITY FLOOR (mirrors INNGEST_GZIP_FLOOR in cloud-init-user-data-size.test.ts). Every
# other assertion here is a CEILING, so a measurement drifting toward "smaller and safer" is
# invisible — and that is the direction that strands the host. A strip widened to `/(?m)^.*\n/`
# eats the whole payload; base64gzip("") is 40 chars, which reports MAXIMUM headroom and exit 0
# while `#cloud-config` is gone and the host boots dark.
if [ "$stored_bytes" -lt 4000 ]; then
  echo "inngest-userdata-budget: stored payload is only ${stored_bytes} B — implausibly small (floor 4000 B). The strip is eating real content, or the render lost its substitutions. A near-empty user_data boots a DARK host, which presents as a green apply." >&2
  exit 2
fi

# The strip preserves `#cloud-config` by construction — the regex requires `#` followed by a
# space or tab (or end of line), and `#cloud-config` has neither. That one line is what makes
# cloud-init execute the file at all, so assert it survived rather than trusting the
# construction: a dark host is the failure mode with no signal of its own.
head -1 "$rendered" | grep -qx '#cloud-config' || {
  echo "inngest-userdata-budget: the stripped render does not begin with '#cloud-config' — cloud-init would not execute it, and the host would boot dark" >&2
  exit 2
}

# OUT receives the STRIPPED render — the bytes that actually reach the host and boot it.
[ -n "$OUT" ] && cp "$rendered" "$OUT"

if [ "$JSON" -eq 1 ]; then
  printf '{"raw_bytes":%s,"stripped_bytes":%s,"removed_bytes":%s,"stored_bytes":%s,"cap":%s,"headroom":%s}\n' \
    "$raw_bytes" "$stripped_bytes" "$removed_bytes" "$stored_bytes" "$cap" "$headroom"
else
  echo "inngest user_data budget"
  echo "  raw rendered    : ${raw_bytes} B"
  echo "  after strip     : ${stripped_bytes} B  (local.inngest_rationale_strip, extracted from inngest-host.tf)"
  echo "  prose removed   : ${removed_bytes} B"
  echo "  stored (b64gzip): ${stored_bytes} B"
  echo "  cap             : ${cap} B"
  echo "  headroom        : ${headroom} B"
fi

# -ge, matching both siblings: at EXACTLY the cap they fail and this must not disagree.
if [ "$stored_bytes" -ge "$cap" ]; then
  echo "inngest-userdata-budget: OVER CAP by $(( stored_bytes - cap )) bytes — hcloud rejects the CREATE *after* the DESTROY has already succeeded, stranding the scheduler host. This is the 2026-09-08 outage, exactly." >&2
  # DISCRIMINATE THE TWO CAUSES. Naming only one sends the operator down a days-long path for a
  # one-character defect. If the strip matched (almost) nothing, raw ≈ stripped — the regex is
  # broken, which passes every extraction gate above because those check the expression's SHAPE,
  # never that it still matches anything.
  if [ "$stripped_bytes" -ge $(( raw_bytes / 2 )) ]; then
    echo "  CAUSE: the strip matched almost nothing (raw ${raw_bytes} B -> stripped ${stripped_bytes} B). Check local.inngest_rationale_strip in inngest-host.tf — this is a broken regex, NOT payload growth." >&2
  else
    echo "  CAUSE: the strip is working (raw ${raw_bytes} B -> stripped ${stripped_bytes} B), so this is real payload growth. Bake new host logic into the image instead of inlining it (the ADR-080/#5921 pattern)." >&2
  fi
  exit 1
fi
