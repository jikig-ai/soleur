# shellcheck shell=bash
# Shared scrub_pat helper — redacts Supabase Management API personal access
# tokens (sbp_-prefixed) out of any string before it reaches a log, a
# $GITHUB_OUTPUT line, or a GitHub issue body.
#
# Why a shared lib: this helper is already inlined in FOUR places —
#   .github/workflows/apply-inngest-rls.yml
#   .github/workflows/apply-inngest-rls-dev.yml
#   .github/workflows/scheduled-inngest-health.yml
#   apps/web-platform/scripts/postgrest-reload-schema.sh
# Bash functions do not cross GitHub-Actions step boundaries, which is why the
# three workflow copies exist; postgrest-reload-schema.sh is a script and could
# source this instead. A standalone script CAN source a lib, so new callers take
# this one and add no fifth copy. Mirrors scripts/lib/strip-log-injection.sh.
#
# The drift this exists to stop is already real, not hypothetical: a FIFTH copy
# at .github/workflows/cutover-inngest.yml (PAT_SCRUB) shares this regex but
# substitutes a DIFFERENT token ([REDACTED-PAT] vs sbp_REDACTED). Same intent,
# divergent output — which is what happens to a redaction rule maintained by
# copy-paste.
#
# The pre-existing copies are deliberately NOT migrated here — that is a
# separate sweep. The obligation this lib discharges is only "add no new copy".
#
# Signature: a STDIN FILTER, matching strip-log-injection.sh's convention
# (`printf '%s' "$x" | strip_log_injection`) rather than the workflow copies'
# argument form. The sed expression itself is byte-identical to the inline
# original; only the plumbing differs, so the redaction behavior cannot drift.
#
# Why {20,} and not a fixed length: Supabase has shipped more than one PAT
# length; a lower bound redacts every observed shape without needing an update
# when the vendor changes it. It is a redaction floor, not a validator.
#
# NOTE — do NOT "modernize" this to a \xHH byte-set. POSIX/GNU/uutils `tr`
# interpret `\NNN` OCTAL but not `\xHH` hex (see
# knowledge-base/project/learnings/2026-05-11-tr-does-not-interpret-hex-escapes.md
# and cq-regex-unicode-separators-escape-only). This lib uses sed, not tr, but
# the sibling strip_log_injection it is paired with does — keep them consistent.

scrub_pat() {
  sed -E 's/sbp_[A-Za-z0-9]{20,}/sbp_REDACTED/g'
}
