# shellcheck shell=bash
# Shared scrub_pat helper — redacts Supabase Management API personal access
# tokens (sbp_-prefixed) out of any string before it reaches a log, a
# $GITHUB_OUTPUT line, or a GitHub issue body.
#
# Why a shared lib: this helper is currently inlined in FOUR call sites
# (.github/workflows/apply-inngest-rls.yml, apply-inngest-rls-dev.yml,
# scheduled-inngest-health.yml, and scripts/). Bash functions do not cross
# GitHub-Actions step boundaries, which is why the workflow copies exist; a
# standalone script CAN source a lib, so new callers take this one and add no
# fifth copy. Mirrors scripts/lib/strip-log-injection.sh.
#
# The pre-existing inline copies are deliberately NOT migrated here — that is a
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
