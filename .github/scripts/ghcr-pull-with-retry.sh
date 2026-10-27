#!/usr/bin/env bash
# ghcr-pull-with-retry.sh — bounded, throttle-signature-gated retry around an
# argv command (the `supabase start` image-pull fan-out) — #10868.
#
# WHY. GHCR's anonymous pull path for the `supabase` org namespace shares an
# aggregate budget (`allowed: 44000/minute`, measured on run 40353999484).
# When it saturates, the rls-fuzz job dies at "Start local Supabase stack"
# before any test runs — the docker/login-action step ahead of this helper
# moves pulls onto the authenticated path, and this wrapper is the complement
# for the case where the namespace aggregate itself is the saturated
# resource.
#
# CONTRACT.
#   - Runs "$@" at most 3 attempts, sleeping `20 45` between them
#     (overridable via GHCR_PULL_RETRY_SLEEPS, whitespace-separated).
#   - Each attempt's combined output goes to a FRESH per-attempt log under
#     ${RUNNER_TEMP:-mktemp -d} via `cmd 2>&1 | tee <log>`; the command's rc
#     is read from ${PIPESTATUS[0]} — `rc=$?` would read tee's status.
#   - A retry fires only when ALL of: rc != 0, rc != 2 (the wrapped
#     supabase-local.sh deterministic not-started/unverified class — never a
#     pull failure), and the TAIL (~40 lines) of THIS attempt's log matches
#     `toomanyrequests` (case-insensitive). The tail scope matters: the token
#     can appear mid-attempt and recover before a later deterministic
#     failure — only the terminal region classifies.
#   - `Retrying after`, `failed to pull docker image` and
#     `failed to display json stream` are deliberately NOT in the gate: they
#     also fire on non-throttle failures (incl. post-login `denied`), so they
#     misclassify.
#   - Each retried attempt emits `::warning::` naming the measured signature
#     line; exhaustion emits `::error::`, re-emits the failing log's tail,
#     and exits with the command's rc. A non-signature (or rc 2) failure
#     emits `::error::` and exits on that attempt — failures stay visible
#     (ADR-166: messages name measured lines only).
set -uo pipefail

if (( $# == 0 )); then
  printf '::error::usage: %s <command> [args...]\n' "$(basename "$0")" >&2
  exit 2
fi

ATTEMPTS=3
# shellcheck disable=SC2206 # intentional word-split: env carries "20 45".
SLEEPS=(${GHCR_PULL_RETRY_SLEEPS:-20 45})
TAIL_LINES=40
REEMIT_LINES=200

log_dir="${RUNNER_TEMP:-$(mktemp -d)}"

# Annotation-safe one-liner: % -> %25, CR/LF stripped (the workflow-annotation
# protocol is line-oriented and % is its escape introducer).
sanitize() {
  local s="$1"
  s="${s//$'\r'/}"
  s="${s//$'\n'/}"
  printf '%s' "${s//%/%25}"
}

last_rc=0
attempt=1
while (( attempt <= ATTEMPTS )); do
  log="$log_dir/ghcr-pull-attempt-${attempt}.log"
  : > "$log"
  "$@" 2>&1 | tee "$log"
  last_rc=${PIPESTATUS[0]}
  if (( last_rc == 0 )); then
    exit 0
  fi

  # Classify THIS attempt: only its own log's tail may supply the signature —
  # a prior attempt's throttle cannot leak into a later attempt's verdict.
  sig_line="$(tail -n "$TAIL_LINES" "$log" | grep -i 'toomanyrequests' | head -1 || true)"

  if (( last_rc != 2 )) && [[ -n "$sig_line" ]]; then
    if (( attempt < ATTEMPTS )); then
      printf '::warning::attempt %d/%d failed on a measured pull throttle: %s\n' \
        "$attempt" "$ATTEMPTS" "$(sanitize "$sig_line")"
      sleep "${SLEEPS[$((attempt - 1))]:-0}"
      attempt=$((attempt + 1))
      continue
    fi
    printf '::error::command failed after %d attempts — last measured line: %s\n' \
      "$ATTEMPTS" "$(sanitize "$sig_line")"
    # Re-emit the failing log's tail: registry errors print at the end of the
    # pull stream, and head-truncation would clip the diagnostic.
    tail -n "$REEMIT_LINES" "$log"
    exit "$last_rc"
  fi

  # Deterministic failure (non-signature output, or the wrapper's rc-2
  # class): exit on this attempt, unchanged rc, symmetric attribution.
  last_line="$(tail -n 1 "$log")"
  printf '::error::%s failed (rc=%d) — last log line: %s\n' \
    "$*" "$last_rc" "$(sanitize "$last_line")"
  exit "$last_rc"
done

exit "$last_rc"
