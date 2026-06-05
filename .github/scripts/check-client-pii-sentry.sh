#!/usr/bin/env bash
# check-client-pii-sentry.sh — SIGNAL-QUALITY CI/lefthook gate (#3703).
#
# Fails if client-importable code passes userId / user_id / email inside an
# `extra: { ... }` object to a DIRECT Sentry.captureException / captureMessage
# call. The point is PR-AUTHOR VISIBILITY: the L3 `stripUserContextFromEvent`
# beforeSend backstop (sentry.client.config.ts, from #3696/#3700) already
# guarantees the production posture at runtime — this gate is NOT a security
# control and production PII has never been at risk. It only surfaces the
# bypass in the PR diff, which today only shows up as a `piiStripped` sentinel
# in Sentry dashboards (invisible to the regressing author).
#
# Boundary vs siblings (do NOT collapse):
#   - userid-bypass-lint (#3698): scopes logger.* on the server/app surface.
#   - pii-grep: scans for Linear CDN URLs in the PR diff.
#   - this gate: direct Sentry.capture* extra-object on the CLIENT surface.
#
# Multi-line-aware by design: all real call sites write the call across several
# lines, so a single-line grep would be vacuous against the exact regression
# class this gate exists for. We scan the call's argument span (call line + up
# to 8 following lines) with a bounded `[^}]*` window under mawk-portable
# character-class boundaries.
set -uo pipefail

# Inputs: explicit paths (lefthook {staged_files}) OR, with no args (CI mirror),
# the client-importable roots.
if [[ "$#" -gt 0 ]]; then
  CANDIDATES=("$@")
else
  mapfile -t CANDIDATES < <(
    find \
      apps/web-platform/lib \
      apps/web-platform/components \
      apps/web-platform/app \
      -type f \( -name '*.ts' -o -name '*.tsx' \) 2>/dev/null
  )
fi

# Exclusions: app/api/ (server routes), and the sanctioned client-observability
# helper (mirrors the issue's `grep -v '/api/'` + `grep -v 'client-observability.ts'`).
is_excluded() {
  case "$1" in
    */api/*) return 0 ;;                # server API routes (issue: grep -v '/api/')
    *client-observability.ts) return 0 ;;  # sanctioned client helper
  esac
  return 1
}

OFFENDERS=""
for f in "${CANDIDATES[@]}"; do
  [[ -f "$f" ]] || continue
  case "$f" in *.ts|*.tsx) ;; *) continue ;; esac
  is_excluded "$f" && continue

  # Multi-line window detector. Verified working under mawk 1.3.4.
  hits=$(awk '
    /Sentry\.(captureException|captureMessage)\(/ { win=1; buf=""; n=0 }
    win {
      buf = buf " " $0; n++
      padded = " " buf " "
      if (padded ~ /extra[[:space:]]*:[[:space:]]*\{[^}]*[^A-Za-z_](userId|user_id|email)[^A-Za-z_]/) {
        print FILENAME ":" FNR
        win = 0
      }
      if (n >= 8) win = 0
    }
  ' "$f" 2>/dev/null)

  if [[ -n "$hits" ]]; then
    while IFS= read -r loc; do
      [[ -z "$loc" ]] && continue
      ln="${loc##*:}"
      snippet=$(sed -n "${ln}p" "$f" 2>/dev/null | sed 's/^[[:space:]]*//')
      OFFENDERS+="${loc}: ${snippet}"$'\n'
    done <<<"$hits"
  fi
done

if [[ -n "$OFFENDERS" ]]; then
  echo "client-pii-grep: client-importable code passes userId/user_id/email in 'extra:' to a direct Sentry.capture* call." >&2
  echo "  This bypasses the stripPiiKeys helper. The L3 beforeSend backstop still strips it at runtime (prod is safe)," >&2
  echo "  but route this through lib/client-observability.ts / stripPiiKeys so the PR diff is clean. Offenders:" >&2
  printf '%s' "$OFFENDERS" | sed 's/^/    /' >&2
  exit 1
fi

exit 0
