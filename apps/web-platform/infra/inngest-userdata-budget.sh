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
# state. The real root's map consumes hcloud_volume.inngest_redis_luks.id,
# doppler_service_token.inngest.key and random_password.zot_pull.result — measuring on it would
# require Doppler prd_terraform and would be unrunnable on a fork PR. Stub LENGTHS are what a
# size check needs, and each stub below is a length UPPER BOUND on its real value.
#
# THE BOUNDS, each justified rather than asserted (the #7299 review's standard):
#   * `sdk_url`, `zot_registry_endpoint`, `zot_pull_user`, `web_host_private_ips` — byte-identical
#     copies of the real values, which are literals in this root (inngest-host.tf and
#     zot-registry.tf). Exact, not bounds.
#   * `zot_pull_token` — exactly 40, from `random_password.zot_pull { length = 40 }`. Exact in LENGTH; the
#     value is hash-derived (see the entropy note below), not repeated filler.
#   * the three `*_sha256` values — 64 hex, and BOTH arch branches are 64 hex, so exact.
#   * `inngest_luks_volume_id` — 9 digits, same reasoning (#6894's additive volume). It is
#     interpolated twice in the template (the first-boot resolver and the boot-reopen script).
#   * `doppler_arch` / `inngest_cli_arch` — "amd64" and "arm64" are both 5 B, so this render is
#     ARCH-NEUTRAL in length and the measurement holds for either `var.inngest_server_type`.
#   * `doppler_token` (the read-only BOOT token) and `doppler_flip_token` (the read/write FLIP token) —
#     `dp.st.<config>.<body>` service tokens on project `soleur-inngest`, config `prd` (ADR-282 addendum
#     2026-10-30, #9927 item 4). Each is stubbed with a 48-character body, over the ~43 B Doppler is
#     believed to emit (no repo fixture records a real body width: this is a belief, the stub is the bound),
#     58 characters in all.
#   * `betterstack_logs_token` — 64 B. The real Better Stack token length is NOT derivable from
#     anything in this repo (every in-tree sample is synthetic or redacted), so the bound is made
#     true by construction rather than by belief. Same reasoning, same width, as the registry
#     sibling's heartbeat-token stub.
#   * `sentry_dsn` (#6500) — 149 B, in the DSN shape. A Sentry DSN is
#     `https://<32-hex key>@o<org id>.ingest.<region>.sentry.io/<project id>`, about 90 B; the stub
#     widens the org and project ids well past any issued value, so it bounds the real one.
#
# STUB ENTROPY (all FIVE secret stubs). A length bound is not an entropy bound: a repeated filler run gzips
# to almost nothing, a real secret does not. So every secret stub (both Doppler tokens, the zot pull token,
# the Better Stack token and the DSN key) is a hash-derived, random-shaped string: base64sha512 of a label,
# `+` and `/` mapped to letters, cut to the stub width. Deterministic across runs, and no contiguous
# token-shaped literal sits in this source. Measured cost of the entropy: the boot token's stub alone moved the
# stored size by about +60 B (ADR-282 build record). The headroom this script reports is therefore measured
# with high-entropy stubs for all five secrets. It is a bound on the real value only as far as each stub's
# entropy and width bound the real one: the real Doppler body width is unverified.
#
# TWO DIFFERENT NUMBERS, NOT COMPARED. `INNGEST_GZIP_BUDGET` in
# plugins/soleur/test/cloud-init-user-data-size.test.ts is the TypeScript LENGTH model's budget (node zlib,
# x-run stand-ins for variable-length secrets). This script's stored figure is terraform's own
# base64gzip over hash-derived stubs. They are not tied to each other and neither is compared with the other.
# The floor below (384 B of cap headroom) is the only margin this script gates. Measured with the stubs
# above: 32,344 B stored, 424 B of cap headroom, i.e. 40 B over the floor. The stub-entropy bound for the
# first replace is about 424 B of headroom; the pessimistic bound is 324 B to the Hetzner cap.
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
# Usage: bash apps/web-platform/infra/inngest-userdata-budget.sh [--json] [--cap-only] [out-rendered]
#   --cap-only skips the 384 B headroom floor and keeps the over-cap (exit 1) and unmeasurable (exit 2)
#   exits. It is the form the `inngest_host_replace` workflow job runs: the floor is a CI maintenance
#   gate (the required `infra-validation` job runs it WITHOUT the flag), and must not block a recovery
#   dispatch that is otherwise under the Hetzner cap.
#   out-rendered receives the STRIPPED render — the bytes that actually reach the host.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON=0
CAP_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --cap-only) CAP_ONLY=1; shift ;;
    *) break ;;
  esac
done
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
printf '%s' "$STRIP_EXPR" | grep -c '(?m)' >/dev/null || {
  echo "inngest-userdata-budget: local.inngest_rationale_strip is not multiline-anchored ((?m)): ${STRIP_EXPR}" >&2
  exit 2
}
printf '%s' "$STRIP_EXPR" | grep -cF '^' >/dev/null || {
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
  printf '%s' "$TF_JOINED" | grep -cE "$1" >/dev/null || {
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
printf '%s' "$TF_JOINED" | grep -cF 'local.inngest_rationale_strip' >/dev/null || {
  echo "inngest-userdata-budget: inngest-host.tf never REFERENCES local.inngest_rationale_strip — it is declared but unused, so the stored payload is unstripped" >&2
  exit 2
}

# THE PLAN-TIME TRIPWIRE. This script runs on infra PRs; the `lifecycle.precondition` on
# hcloud_server.inngest is what refuses the DESTROY on the dispatch path itself, where no CI job
# is watching. They cover different moments and neither substitutes for the other, so removing
# the precondition must not leave a green gate behind.
printf '%s' "$TF_JOINED" | grep -cE 'precondition[[:space:]]*\{[[:space:]]*condition[[:space:]]*=[[:space:]]*length\([[:space:]]*local\.inngest_user_data_b64gz[[:space:]]*\)' >/dev/null || {
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
    inngest_luks_volume_id = "100000005"
    doppler_token          = join(".", ["dp", "st", "prd", substr(replace(replace(base64sha512("boot"), "+", "a"), "/", "b"), 0, 48)])
    doppler_flip_token     = join(".", ["dp", "st", "prd", substr(replace(replace(base64sha512("flip"), "+", "a"), "/", "b"), 0, 48)])
    inngest_doppler_config = "prd"
    sdk_url                = "http://10.0.1.10:3000/api/inngest"
    inngest_cli_arch       = "amd64"
    inngest_cli_sha256     = "52c07d837088a6712acd15b8edd4191f961b69884541f468a3c1b9bb4348a4e5"
    vector_sha256          = "8a3cc62d18ec88bb8433159d1d3455d3c77fefff73ce46d4f8cc464e100f65f1"
    doppler_arch           = "amd64"
    doppler_sha256         = "9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"
    zot_registry_endpoint  = "10.0.1.30:5000"
    zot_pull_user          = "zot-pull"
    zot_pull_token         = substr(replace(replace(base64sha512("zot"), "+", "a"), "/", "b"), 0, 40)
    web_host_private_ips   = "10.0.1.10,10.0.1.11"
    inngest_private_ip     = "10.0.1.40"
    betterstack_logs_token = substr(replace(replace(base64sha512("bs"), "+", "a"), "/", "b"), 0, 64)
    sentry_dsn             = join("", ["https://", substr(replace(replace(base64sha512("dsn"), "+", "a"), "/", "b"), 0, 32), "@o0000000000000000.ingest.us.sentry.io/0000000000000000000000000000000000000000000000000000000000000000000000"])
    # #6780 (ADR-135 amendment): the consumer's two baked payloads — measured against the
    # REAL repo files, in the same file() text shape inngest-host.tf passes them (an
    # "x"-run placeholder gzips ~1000:1 and would green an over-cap payload).
    infra_config_install_text = file("${DIR}/infra-config-install.sh")
    cosign_trusted_root_text  = file("${DIR}/cosign-trusted-root.json")
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
if [ -s "$TFDIR/err" ] || printf '%s' "$stripped_out" | grep -c 'known after apply' >/dev/null; then
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
head -1 "$rendered" | grep -cx '#cloud-config' >/dev/null || {
  echo "inngest-userdata-budget: the stripped render does not begin with '#cloud-config' — cloud-init would not execute it, and the host would boot dark" >&2
  exit 2
}

# OUT receives the STRIPPED render — the bytes that actually reach the host and boot it.
[ -n "$OUT" ] && cp "$rendered" "$OUT"

# THE CAP-HEADROOM FLOOR (flip-token split, ADR-282 addendum 2026-10-30, CTO N3 as amended by R7). Under the
# cap is not enough: every addition to this template spends the same few hundred bytes, the 2026-09-08 outage
# was a payload that crossed the line unnoticed, and a replace that lands within a few bytes of the cap has no
# room for the next token or comment-free line. The floor is 384 B of cap headroom (stored <= cap - 384),
# measured here, the only place that runs the real templatefile/base64gzip. The required `infra-validation.yml`
# job `inngest-userdata-budget` enforces it; the `inngest_host_replace` job runs this script with `--cap-only`
# BEFORE its plan step, which keeps exits 1 (over the cap) and 2 (unmeasurable) and skips the floor, so a
# recovery dispatch is never blocked by a maintenance margin. (On the first replace after the split both token
# keys are unknown at plan time, so the in-plan length precondition is deferred to apply, after the destroy.)
# If the floor is breached, shrink code: never raise INNGEST_GZIP_BUDGET and never add bytes.
# INNGEST_BUDGET_FLOOR_BYTES is a TEST SEAM that can only RAISE the floor (an empty or non-numeric value falls
# back to 384, and anything below 384 is clamped UP to it): cloud-init-user-data-size.test.ts raises it above
# the real headroom and asserts exit EXACTLY 1, so the exit is proven live instead of vacuous. Exit 1 here,
# 2 stays "unmeasurable". The effective floor is emitted in the --json output so a pin can read it.
FLOOR_MIN=384
floor_bytes="${INNGEST_BUDGET_FLOOR_BYTES:-$FLOOR_MIN}"
case "$floor_bytes" in ''|*[!0-9]*) floor_bytes="$FLOOR_MIN" ;; esac
[ "$floor_bytes" -lt "$FLOOR_MIN" ] && floor_bytes="$FLOOR_MIN"

if [ "$JSON" -eq 1 ]; then
  printf '{"raw_bytes":%s,"stripped_bytes":%s,"removed_bytes":%s,"stored_bytes":%s,"cap":%s,"headroom":%s,"floor":%s,"cap_only":%s}\n' \
    "$raw_bytes" "$stripped_bytes" "$removed_bytes" "$stored_bytes" "$cap" "$headroom" "$floor_bytes" "$CAP_ONLY"
else
  echo "inngest user_data budget"
  echo "  raw rendered    : ${raw_bytes} B"
  echo "  after strip     : ${stripped_bytes} B  (local.inngest_rationale_strip, extracted from inngest-host.tf)"
  echo "  prose removed   : ${removed_bytes} B"
  echo "  stored (b64gzip): ${stored_bytes} B"
  echo "  cap             : ${cap} B"
  echo "  headroom        : ${headroom} B"
  echo "  floor           : ${floor_bytes} B$([ "$CAP_ONLY" -eq 1 ] && echo ' (--cap-only: not enforced)')"
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

if [ "$CAP_ONLY" -eq 0 ] && [ "$headroom" -lt "$floor_bytes" ]; then
  echo "inngest-userdata-budget: HEADROOM FLOOR BREACHED — ${headroom} B of cap headroom is below the ${floor_bytes} B floor (stored ${stored_bytes} B of ${cap} B). Shed payload (prose is stripped for free, so what remains is code); do NOT raise INNGEST_GZIP_BUDGET and do NOT add bytes." >&2
  exit 1
fi
