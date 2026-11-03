#!/usr/bin/env bash
# tf-redact-random-ids.sh -- stdin->stdout filter that blanks the key material Terraform prints
# for random_{id,password,string,uuid,bytes} resources (#11294; CTO ruling 2026-10-29: Fix A ships on its own).
#
# WHY. A random_id's `id` IS the base64url of its bytes, and inngest.tf derives the live Inngest
# signing/event keys (doppler_secret.inngest_*_key_*) from random_id.inngest_*_key_*.hex.
# `terraform plan` prints `random_id.X: Refreshing state... [id=<key>]` for every random_* in the
# refresh set, and `terraform apply` prints `Creation complete ... [id=<key>]`, straight to a
# PUBLIC Actions log (or, for the scheduled drift plan, into a public issue body). The key is the
# line's content, so masking cannot be left to ::add-mask:: (the value is never a secret to the
# runner), and the fix cannot be a -target change (a targeted plan refreshes the dependency).
#
# WHAT. On a line naming a random_* address: `[id=...]` -> `[id=<redacted>]` and `id = "..."` ->
# `id = "<redacted>"`. Inside a plan block opened by a plan comment line (`# ...`) that names a random_* address
# at a word boundary, followed by whitespace or end of line (the text after the address is never matched, so no
# verb is enumerated: created/updated/destroyed/replaced, `is tainted, so must be replaced`,
# `(deposed object ...) will be destroyed`, `has changed`, a bare `# random_id.k`) and closed by the first `    }`:
# every quoted value of an id/b64_std/b64_url/hex/dec/result/base64/b64 attribute, both sides of `->`.
# random_id's id/b64_*/hex/dec are NOT sensitive to Terraform (hex and b64_* ARE the key bytes: inngest.tf derives
# the live keys from random_id.*.hex), so the plan prints them in clear; where the provider marks an attribute
# sensitive Terraform prints `(sensitive value)` and there is nothing to lose. SECOND RANGE, the `terraform show` /
# `state show` shape (header `# random_id.k:`, column-0 body): it closes ONLY at a column-0 `}`, because a nested map
# (`keepers = { ... }`) closes at 4 spaces there and must not end the range early (CTO ruling 2026-11-03, option A:
# two disjoint ranges; the plan range excludes an address ending in `:`). The address, the surrounding text and the
# line count are kept; other resources' ids
# (hetzner `[id=12345]`) are untouched. Input is `-no-color` output; CSI colour sequences are stripped first.
# FAIL-SAFE DIRECTION: a block that never closes (closer at another indent, truncated log) stays open to the end
# of input, so a LATER `id = "..."` line is redacted too (over-redaction), never the other way round.
#
# CONTRACT. A pure filter: it never changes a producer's exit status; callers read
# `${PIPESTATUS[0]}` (or run under pipefail) exactly as for any `cmd | filter`.
#
# Sourced by EVERY workflow step that runs terraform plan/apply/refresh/destroy on a root that
# declares a key-bearing random_* (apply-web-platform-infra.yml, apply-deploy-pipeline-fix.yml,
# scheduled-terraform-drift.yml, infra-validation.yml, inngest-provision-rehearsal.yml, cf-lb-overlay.yml);
# exercised by tests/scripts/test-tf-redact-random-ids.sh and swept over all workflows by
# plugins/soleur/test/terraform-target-parity.test.ts (a step on a root with none may skip it).

tf_redact_random_ids() {
  # ANSI first (#11294 follow-up): a step without -no-color prints `ESC[0mESC[1mrandom_id.X: ... [id=<key>]ESC[0m`, and the
  # `m` that ends ESC[1m is alphanumeric, so the address anchor below never matched and the line passed through. Colour
  # carries no information the log needs; the CSI sequences are removed so every rule sees the plain line (line count kept).
  local esc=$'\033'
  sed -E \
    -e "s/${esc}\[[0-9;?]*[A-Za-z]//g" \
    -e '/(^|[^[:alnum:]_])random_(id|password|string|uuid|bytes)\./{
      s/\[id=[^]]*\]/[id=<redacted>]/g
      s/(\<id[[:space:]]+=[[:space:]]+)"[^"]*"/\1"<redacted>"/g
    }' \
    -e '/^[[:space:]]*# ((.*[^[:alnum:]_])?)random_(id|password|string|uuid|bytes)\.[^[:space:]]*[^[:space:]:]([[:space:]]|$)/,/^    \}/{
      /^[^"]*[[:space:]](id|b64_std|b64_url|hex|dec|result|base64|b64)[[:space:]]+=/s/"[^"]*"/"<redacted>"/g
    }' \
    -e '/^[[:space:]]*# ((.*[^[:alnum:]_])?)random_(id|password|string|uuid|bytes)\.[^[:space:]]+:$/,/^\}/{
      /^[^"]*[[:space:]](id|b64_std|b64_url|hex|dec|result|base64|b64)[[:space:]]+=/s/"[^"]*"/"<redacted>"/g
    }'
}
