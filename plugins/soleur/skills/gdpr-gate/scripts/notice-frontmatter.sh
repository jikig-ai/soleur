#!/usr/bin/env bash
# notice-frontmatter.sh — pure-bash parser for the NOTICE YAML frontmatter.
#
# Subcommands:
#   field <name>      Print scalar value (upstream, pinned-commit,
#                     last-verified, registry).
#   days-stale        Integer days since last-verified. Future date / parse
#                     fail / missing frontmatter all return 999 (treat as
#                     stale immediately, per plan TR2 + SpecFlow P1.5).
#                     Always exits 0 — the gdpr-gate hook subshell-execs this
#                     and depends on the always-exit-0 advisory contract.
#   cron-run-stale    Integer days since the scheduled-content-vendor-drift
#                     workflow last succeeded (via `gh run list`). 999 on any
#                     failure mode (no GH_TOKEN, no gh CLI, network blocked,
#                     empty result, malformed timestamp, timeout). The
#                     `gdpr-gate.sh` caller computes MIN(days-stale,
#                     cron-run-stale) to defend against a backdated
#                     last-verified field (issue #3535).
#   lifted-files      One `<path>:<local-blob-sha>` per line. Local blob SHAs
#                     pin the file as it exists in this repo (post-attribution
#                     header) and are consumed by `vendor-pin-integrity.sh`.
#   upstream-files    One `<upstream-path>:<upstream-blob-sha>` per line.
#                     Upstream blob SHAs pin the file as it exists at
#                     `pinned-commit` and are consumed by the drift workflow.
#
# NOTICE location: $NOTICE_FILE if set, else <script-dir>/../NOTICE.
#
# `set -euo pipefail` is internal; subcommand wrappers catch failures so the
# caller (`gdpr-gate.sh`) can `bash notice-frontmatter.sh days-stale 2>/dev/null
# || echo 999` without aborting the gate on parser death.
#
# TR2: target p95 <50ms over 100 invocations of `days-stale`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTICE_FILE="${NOTICE_FILE:-$SCRIPT_DIR/../NOTICE}"

# Print only the YAML body between the first two `---` lines.
# Returns empty + exit 1 if no frontmatter.
extract_frontmatter() {
  [[ -f "$NOTICE_FILE" ]] || return 1
  awk '
    BEGIN { count=0; in_fm=0 }
    /^---[[:space:]]*$/ {
      count++
      if (count == 1) { in_fm = 1; next }
      if (count == 2) { in_fm = 0; exit }
    }
    in_fm { print }
    END { if (count < 2) exit 1 }
  ' "$NOTICE_FILE"
}

cmd_field() {
  local name="$1"
  local fm
  fm=$(extract_frontmatter) || return 1
  [[ -n "$fm" ]] || return 1
  # Match top-level scalar lines (`<name>: <value>`); skip indented (nested).
  printf '%s\n' "$fm" | awk -v key="$name" '
    /^[[:space:]]/ { next }
    {
      idx = index($0, ":")
      if (idx == 0) next
      k = substr($0, 1, idx - 1)
      v = substr($0, idx + 1)
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+$/, "", v)
      if (k == key) { print v; exit }
    }
  '
}

cmd_days_stale() {
  local last_verified last_epoch today_epoch days
  last_verified=$(cmd_field last-verified 2>/dev/null) || { echo 999; return 0; }
  [[ -n "$last_verified" ]] || { echo 999; return 0; }
  # Strict ISO-8601 date guard. `date -d` otherwise accepts "now",
  # "yesterday", etc., letting a malicious NOTICE PR set last-verified to
  # any natural-language value and pin days-stale at 0 forever.
  [[ "$last_verified" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo 999; return 0; }
  # Anchor to UTC midnight so the comparison against `date -u +%s` is
  # consistent across timezones (otherwise a UTC+12 host computes a day
  # off the UTC-anchored today_epoch).
  last_epoch=$(date -u -d "${last_verified}T00:00:00Z" +%s 2>/dev/null) || { echo 999; return 0; }
  today_epoch=$(date -u +%s)
  days=$(( (today_epoch - last_epoch) / 86400 ))
  # Future date → treat as stale immediately (per SpecFlow P1.5).
  if (( days < 0 )); then
    echo 999
  else
    echo "$days"
  fi
}

_emit_files() {
  # Args: $1 = path-key ("path" | "upstream-path"), $2 = sha-key
  # ("local-blob-sha" | "upstream-blob-sha"). Walks the lifted-files block
  # and prints `<path-value>:<sha-value>` per entry.
  local path_key="$1"
  local sha_key="$2"
  local fm
  fm=$(extract_frontmatter) || return 0
  [[ -n "$fm" ]] || return 0
  printf '%s\n' "$fm" | awk -v path_key="$path_key" -v sha_key="$sha_key" '
    BEGIN { in_block=0; cur_path=""; cur_sha="" }
    /^lifted-files:[[:space:]]*$/ { in_block=1; next }
    /^[A-Za-z]/ { in_block=0 }
    in_block {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      n = split(line, tok, /[[:space:]]+/)
      # New entry sentinel: `- path: <value>` always opens a record. Flush
      # the previous record before starting the new one.
      # Normalize `key : value` (YAML-legal space-before-colon) to `key:`.
      # Without this, tok[1] is the bare key and tok[2] is `:`, silently
      # dropping the entry from the registry view.
      sub(/[[:space:]]+:[[:space:]]+/, ": ", line)
      n = split(line, tok, /[[:space:]]+/)
      if (n >= 3 && tok[1] == "-" && tok[2] == "path:") {
        if (cur_path != "" && cur_sha != "") print cur_path ":" cur_sha
        cur_path = ""
        cur_sha = ""
        if (path_key == "path") cur_path = tok[3]
      } else if (n >= 2 && tok[1] == path_key ":") {
        # tok layout for `path:` and `upstream-path:` lines without leading dash.
        cur_path = tok[2]
      } else if (n >= 2 && tok[1] == sha_key ":") {
        cur_sha = tok[2]
      }
    }
    END {
      if (cur_path != "" && cur_sha != "") print cur_path ":" cur_sha
    }
  '
}

cmd_cron_run_stale() {
  # Days since the scheduled-content-vendor-drift workflow last succeeded,
  # via `gh run list ... --json updatedAt`. Always exits 0 — any failure
  # mode (no token, no gh, network blocked, empty result, malformed
  # timestamp, non-zero clock skew) resolves to 999 so the caller's
  # subshell-exec contract holds. Wrap network call with `timeout 5s` to
  # bound the runtime-banner wall clock.
  #
  # Workflow filename is hard-coded; renaming the workflow silently breaks
  # this binding (falls through to 999 → operator-attested-mode banner).
  # See SKILL.md "Sharp edges" for the workflow-rename mitigation.
  local token raw ts cron_epoch today_epoch days
  token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  [[ -n "$token" ]] || { echo 999; return 0; }
  command -v gh >/dev/null 2>&1 || { echo 999; return 0; }
  # `// empty` collapses the literal `null` (empty result set) to empty
  # string. Belt-and-suspenders with the strict-ISO regex below — a
  # softened guard alone would silently slip `null` through.
  raw=$(GH_TOKEN="$token" timeout 5s gh run list \
          --workflow=scheduled-content-vendor-drift.yml \
          --status=success --limit=1 \
          --json updatedAt --jq '.[0].updatedAt // empty' \
          2>/dev/null) || { echo 999; return 0; }
  ts="${raw%%[[:space:]]*}"
  [[ -n "$ts" ]] || { echo 999; return 0; }
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    || { echo 999; return 0; }
  cron_epoch=$(date -u -d "$ts" +%s 2>/dev/null) || { echo 999; return 0; }
  today_epoch=$(date -u +%s)
  days=$(( (today_epoch - cron_epoch) / 86400 ))
  if (( days < 0 )); then echo 999; else echo "$days"; fi
}

cmd_lifted_files() {
  _emit_files path local-blob-sha
}

cmd_upstream_files() {
  _emit_files upstream-path upstream-blob-sha
}

case "${1:-}" in
  field)
    cmd_field "${2:-}" || true
    ;;
  days-stale)
    cmd_days_stale
    ;;
  cron-run-stale)
    cmd_cron_run_stale
    ;;
  lifted-files)
    cmd_lifted_files
    ;;
  upstream-files)
    cmd_upstream_files
    ;;
  *)
    echo "Usage: $0 {field <name>|days-stale|cron-run-stale|lifted-files|upstream-files}" >&2
    exit 2
    ;;
esac

exit 0
