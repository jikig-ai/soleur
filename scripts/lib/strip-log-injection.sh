# shellcheck shell=bash
# Shared strip_log_injection helper for scheduled-audit scripts.
#
# Strips bytes that would let a crafted upstream string (PR title,
# headRefName, JSON-quoted API field) break out of a $GITHUB_OUTPUT
# key=value line, forge a `::warning::` / `::error::` runner directive,
# or smuggle ANSI escapes into a human-readable stdout/stderr log.
#
# Stripped bytes (single source of truth across all audit scripts):
#   - C0 control characters whose octal escapes tr supports:
#       \r (CR, octal 015)
#       \n (LF, octal 012)
#       \f (FF, octal 014)
#       \v (VT, octal 013)
#       \033 (ESC — ANSI escape introducer)
#       \177 (DEL)
#   - U+0085 NEL  (UTF-8: \xc2\x85)
#   - U+2028 LS   (UTF-8: \xe2\x80\xa8)
#   - U+2029 PS   (UTF-8: \xe2\x80\xa9)
#
# Why octal not hex: POSIX/GNU/uutils `tr` interpret `\NNN` octal but
# NOT `\xHH` hex — `tr -d '\x7f'` would strip literal x/7/f bytes.
# See knowledge-base/project/learnings/2026-05-11-tr-does-not-interpret-hex-escapes.md.
#
# Why a shared lib: this helper appears in three call sites today
# (scheduled-github-app-drift-guard.yml inline, scripts/audit-ruleset-bypass.sh,
# scripts/audit-bot-codeql-coverage.sh). Issue #3561 tracks the hex-vs-octal
# divergence in the drift-guard precedent; extracting the lib closes the
# drift class. Mirrors scripts/lib/canonicalize-bypass-actors.sh pattern.

strip_log_injection() {
  tr -d '\r\n\f\v\033\177' \
    | sed -e 's/\xc2\x85//g' -e 's/\xe2\x80\xa8//g' -e 's/\xe2\x80\xa9//g'
}
