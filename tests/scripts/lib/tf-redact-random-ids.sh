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
# `id = "<redacted>"`. Inside a `# random_*.X will be/must be ...` plan block (modify/destroy
# diffs print the attributes un-redacted, and random_id's b64_*/hex/dec are NOT sensitive):
# every quoted value of an id/b64_std/b64_url/hex/dec/result/base64/b64 attribute, both sides of
# `->`. The address, the surrounding text and the line count are kept; other resources' ids
# (hetzner `[id=12345]`) are untouched. Input is `-no-color` output (no ANSI handling).
#
# CONTRACT. A pure filter: it never changes a producer's exit status; callers read
# `${PIPESTATUS[0]}` (or run under pipefail) exactly as for any `cmd | filter`.
#
# Sourced by EVERY workflow step that runs terraform plan/apply/refresh/destroy on a root that
# declares a key-bearing random_* (apply-web-platform-infra.yml, apply-deploy-pipeline-fix.yml,
# scheduled-terraform-drift.yml, infra-validation.yml, inngest-provision-rehearsal.yml);
# exercised by tests/scripts/test-tf-redact-random-ids.sh and swept over all workflows by
# plugins/soleur/test/terraform-target-parity.test.ts (a step on a root with none may skip it).

tf_redact_random_ids() {
  sed -E \
    -e '/(^|[^[:alnum:]_])random_(id|password|string|uuid|bytes)\./{
      s/\[id=[^]]*\]/[id=<redacted>]/g
      s/(\<id[[:space:]]+=[[:space:]]+)"[^"]*"/\1"<redacted>"/g
    }' \
    -e '/^[[:space:]]*# .*random_(id|password|string|uuid|bytes)\.[^[:space:]]+ (will|must) be/,/^    \}/{
      /^[^"]*[[:space:]](id|b64_std|b64_url|hex|dec|result|base64|b64)[[:space:]]+=/s/"[^"]*"/"<redacted>"/g
    }'
}
