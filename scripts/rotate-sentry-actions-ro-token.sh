#!/usr/bin/env bash
# rotate-sentry-actions-ro-token.sh -- the capture -> normalise -> store -> verify -> shred
# chain for SENTRY_ACTIONS_RO_TOKEN, the org-level read-only Sentry Internal Integration
# token (`actions-read-prd`, ADR-031) that scripts/followthroughs/*.sh and the fresh-host
# boot-trail consume. Lives ONCE; the rotation runbook
# (knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md)
# invokes it and does not restate it. Ref #7946.
#
# The whole chain runs in ONE process so a single trap scope holds the plaintext from
# capture to shred. Bash tool calls do not share a shell, so a trap set in one call has
# already fired before the next call runs -- which is why the `agent-browser` path (capture
# is a subprocess of THIS script) is primary and the MCP path (capture is a separate tool
# call) only enters the trap scope AFTER capture, via `--from-file`.
#
# Modes
#   prepare
#       MCP path, pre-capture. Creates the 0700 token directory and a timestamp marker
#       and prints the directory path. No trap: the directory must outlive this call.
#   capture --selector <agent-browser selector> [--dir <dir>]
#       agent-browser path. `agent-browser get value <sel>` writes the readonly token
#       textbox's value straight to <dir>/tok (no snapshot, no screenshot, never argv).
#   capture --from-file <path> --dir <dir>
#       MCP path, post-capture. `browser_evaluate(filename: …)` cannot expand $TOKEN_DIR
#       and @playwright/mcp resolves the name under its own `.playwright-mcp/` output
#       directory, so the file is MOVED into <dir>/tok here (fails if absent), and every
#       file under `.playwright-mcp/` newer than the marker is shredded before continuing.
#   --dry-run --expect <sentinel>   (with either capture form)
#       Zero writes: normalise, `diff` the output against the sentinel byte-exact, prove
#       the `gh secret set` FORM with gh's no-store flag (prints the ciphertext length,
#       stores nothing), confirm the trap removed the directory. That flag appears in the
#       dry-run branch only.
#   --skip-store
#       Verify-only against a token already in <dir>/tok (used by the runbook's failure
#       table to re-probe a stored token without re-storing it).
#
# Rule D (ADR-202): every curl is `--disable --noproxy '*'` and every destination is a
# literal; the region host read back from the API is pinned against the one literal it may
# take. The bearer never rides argv: the header is written to a file in the trap directory
# and passed with `-H @file`, so nothing lands in /proc/*/cmdline.
#
# Exit: 0 chain complete (or dry run clean); 1 a verification failed (scopes, an endpoint,
#       the store, the shape); 2 usage / precondition; 78 xtrace refusal.

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Unconditional: this script ACQUIRES the credential at
# runtime, so a `${VAR:+x}` hatch would be open by construction. `$-` is the load-bearing
# arm -- bash applies an env-supplied SHELLOPTS/BASH_ENV before line 1.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

readonly SECRET_NAME="SENTRY_ACTIONS_RO_TOKEN"
readonly ORG="jikigai-eu"
readonly PROJECT="web-platform"
readonly ORG_HOST="https://jikigai-eu.sentry.io"
readonly CONTROL_HOST="https://sentry.io"
readonly REGION_HOST_PINNED="https://de.sentry.io"
# The permission set selected in the dashboard form (Issue & Event = Read, Organization =
# Read, Project = Read) must come back as EXACTLY these scopes -- an implied extra is a
# finding, never accepted as a superset (plan AC-6).
readonly EXPECTED_SCOPES='["event:read","org:read","project:read"]'
readonly MCP_OUT_DIR=".playwright-mcp"

MODE=""; SELECTOR=""; FROM_FILE=""; TOKEN_DIR=""; DRY_RUN=0; EXPECT=""; SKIP_STORE=0
while (( $# > 0 )); do
  case "$1" in
    prepare|capture) MODE="$1" ;;
    --selector)  SELECTOR="${2:?--selector needs a value}"; shift ;;
    --from-file) FROM_FILE="${2:?--from-file needs a path}"; shift ;;
    --dir)       TOKEN_DIR="${2:?--dir needs a path}"; shift ;;
    --dry-run)   DRY_RUN=1 ;;
    --expect)    EXPECT="${2:?--expect needs a sentinel}"; shift ;;
    --skip-store) SKIP_STORE=1 ;;
    -h|--help)   sed -n '2,45p' "$0"; exit 0 ;;
    *) printf 'usage error: unknown argument %q\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
[[ -n "$MODE" ]] || { printf 'usage: %s prepare | capture (--selector S | --from-file F --dir D) [--dry-run --expect SENTINEL] [--skip-store]\n' "$0" >&2; exit 2; }

# --- prepare: the MCP path's pre-capture half -------------------------------------------
if [[ "$MODE" == "prepare" ]]; then
  d="$(mktemp -d)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  chmod 0700 "$d"
  : > "$d/.marker"
  printf '%s\n' "$d"
  exit 0
fi

# --- capture ----------------------------------------------------------------------------
if [[ -n "$SELECTOR" && -n "$FROM_FILE" ]] || [[ -z "$SELECTOR" && -z "$FROM_FILE" ]]; then
  printf 'usage error: capture takes exactly one of --selector or --from-file\n' >&2; exit 2
fi
if [[ "$DRY_RUN" == "1" && -z "$EXPECT" ]]; then
  printf 'usage error: --dry-run requires --expect <sentinel>\n' >&2; exit 2
fi
if [[ -z "$TOKEN_DIR" ]]; then
  [[ -z "$FROM_FILE" ]] || { printf 'usage error: --from-file requires --dir (from prepare)\n' >&2; exit 2; }
  TOKEN_DIR="$(mktemp -d)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
  chmod 0700 "$TOKEN_DIR"
fi
[[ -d "$TOKEN_DIR" ]] || { printf '[FATAL] token dir %q does not exist\n' "$TOKEN_DIR" >&2; exit 2; }

# THE TRAP SCOPE. From here to exit, every plaintext byte lives under $TOKEN_DIR and is
# shredded on any exit. A failed shred is LOGGED, not hidden: on tmpfs (this workstation's
# /tmp, measured) shred is effective; on a journaled or copy-on-write filesystem it is
# best-effort and the 0700 directory plus the seconds-long lifetime are the primary control.
cleanup() {
  local rc=$?
  if [[ -d "$TOKEN_DIR" ]]; then
    find "$TOKEN_DIR" -mindepth 1 -type f -exec shred -u {} + 2>/dev/null \
      || printf '[WARN] shred of %s failed -- remove it by hand\n' "$TOKEN_DIR" >&2
    rmdir "$TOKEN_DIR" 2>/dev/null || printf '[WARN] could not remove %s\n' "$TOKEN_DIR" >&2
  fi
  return "$rc"
}
trap cleanup EXIT INT TERM HUP

TOK="$TOKEN_DIR/tok"
HDR="$TOKEN_DIR/hdr"

if [[ -n "$SELECTOR" ]]; then
  command -v agent-browser >/dev/null 2>&1 || { printf '[FATAL] agent-browser not on PATH\n' >&2; exit 2; }
  # `get value` writes the raw textbox value; it is the one read of the token panel that
  # is NOT a snapshot or a screenshot (#7947 discipline).
  agent-browser get value "$SELECTOR" > "$TOK" 2>"$TOKEN_DIR/capture.err" \
    || { printf '[FATAL] agent-browser get value failed: %s\n' "$(tr '\n' ' ' < "$TOKEN_DIR/capture.err" | head -c 300)" >&2; exit 1; }
else
  # MCP path. The file was written by browser_evaluate(filename:) under .playwright-mcp/;
  # it MUST be at the exact path given -- a missing file here means the capture wrote
  # somewhere else, and continuing would leave a plaintext file outside the trap scope.
  [[ -f "$FROM_FILE" ]] || { printf '[FATAL] --from-file %q is absent: the capture did not land where expected; find and shred it before retrying\n' "$FROM_FILE" >&2; exit 1; }
  mv -f "$FROM_FILE" "$TOK" || { printf '[FATAL] could not move the captured file into the trap directory\n' >&2; exit 1; }
  if [[ -d "$MCP_OUT_DIR" && -f "$TOKEN_DIR/.marker" ]]; then
    find "$MCP_OUT_DIR" -type f -newer "$TOKEN_DIR/.marker" -exec shred -u {} + 2>/dev/null || true
  fi
fi
[[ -s "$TOK" ]] || { printf '[FATAL] captured file is empty\n' >&2; exit 1; }

# --- normalise: the two surfaces write different bytes ----------------------------------
# `browser_evaluate(filename:)` JSON-encodes (quotes around the value); `agent-browser get
# value` writes raw text. One tolerant step, asserting non-empty / whitespace-free /
# plausible length and logging ONLY the length. Nothing asserts hex: Sentry's token format
# is not fixed across generations, and a wrong format assertion blocks a rotation with a
# false diagnosis. The dry run relaxes the length bound to the sentinel's.
MINLEN=40
[[ "$DRY_RUN" == "1" ]] && MINLEN=1
python3 - "$MINLEN" "$TOK" > "$TOKEN_DIR/norm" <<'PY'
import sys, json
minlen = int(sys.argv[1])
s = open(sys.argv[2]).read()
v = json.loads(s) if s.lstrip().startswith('"') else s.strip()
assert isinstance(v, str) and minlen <= len(v) <= 256 and not any(c.isspace() for c in v), "token shape"
sys.stderr.write("token length %d\n" % len(v))
sys.stdout.write(v)
PY
rc=$?
[[ "$rc" -eq 0 ]] || { printf '[FATAL] normalise failed (shape assertion) -- see stderr\n' >&2; exit 1; }
mv -f "$TOKEN_DIR/norm" "$TOK"

# --- dry run: zero writes, exits here --------------------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
  if ! diff -q <(printf '%s' "$EXPECT") "$TOK" >/dev/null; then
    printf '[FAIL] dry run: normalised output is not byte-identical to the sentinel\n' >&2; exit 1
  fi
  printf '[ok] dry run: normalised output is byte-identical to the sentinel (%d bytes)\n' "$(wc -c < "$TOK")"
  # Prove the STORE FORM without storing: the value on STDIN with no body flag at all --
  # gh has no body-file flag, and a body of `-` stores the literal `-` (measured, #7946).
  # The no-store flag prints the base64 ciphertext instead of writing it: libsodium
  # sealed box = 48 bytes overhead + plaintext, base64-expanded.
  n="$(gh secret set ZZ_DRYRUN_7946 --no-store < "$TOK" | wc -c)"  # the only no-store site
  want=$(( ( (48 + $(wc -c < "$TOK")) + 2 ) / 3 * 4 + 1 ))
  if [[ "$n" == "$want" ]]; then
    printf '[ok] dry run: gh secret set (no-store) ciphertext length %d matches the computed %d (nothing written)\n' "$n" "$want"
  else
    printf '[FAIL] dry run: ciphertext length %d, computed %d -- the store form is wrong\n' "$n" "$want" >&2; exit 1
  fi
  exit 0
fi

# --- store: the value on stdin, never as a flag argument (visible in ps and under -x) ----
if [[ "$SKIP_STORE" != "1" ]]; then
  if ! gh secret set SENTRY_ACTIONS_RO_TOKEN < "$TOK"; then
    printf '[FATAL] gh secret set %s failed. A live token exists that nothing holds: REVOKE IT IN-PAGE NOW (the integration'"'"'s Tokens panel), then retry.\n' "$SECRET_NAME" >&2
    exit 1
  fi
  if [[ "$(gh secret list 2>/dev/null | grep -c "^${SECRET_NAME}\b")" != "1" ]]; then
    printf '[FATAL] %s is not listed after the write -- revoke the token in-page and investigate\n' "$SECRET_NAME" >&2; exit 1
  fi
  printf '[ok] stored %s (GitHub cannot read it back; the value is proven by the post-merge sweeper dispatch)\n' "$SECRET_NAME"
fi

# --- verify: the header rides a FILE, never argv ---------------------------------------
{ printf 'Authorization: Bearer '; cat "$TOK"; } > "$HDR"
get() { # get <url> -> prints http code; body to $TOKEN_DIR/body
  curl --disable --noproxy '*' -sS --max-time 25 -o "$TOKEN_DIR/body" -w '%{http_code}' -H @"$HDR" "$1" 2>/dev/null || printf '000'
}
fails=0
code="$(get "${ORG_HOST}/api/0/")"
if [[ "$code" != "200" ]]; then printf '[FAIL] %s/api/0/ -> HTTP %s\n' "$ORG_HOST" "$code" >&2; fails=$((fails + 1)); fi
scopes="$(jq -c '.auth.scopes | sort' "$TOKEN_DIR/body" 2>/dev/null || echo '[]')"
if [[ "$scopes" == "$EXPECTED_SCOPES" ]]; then
  printf '[ok] .auth.scopes == %s\n' "$scopes"
else
  printf '[FAIL] .auth.scopes is %s, expected exactly %s -- edit the integration'"'"'s permissions in-page and re-read on the SAME token; if it does not change, revoke, recreate, re-run\n' "$scopes" "$EXPECTED_SCOPES" >&2
  fails=$((fails + 1))
fi
# Region host: read back from the ORG endpoint (`/api/0/` carries no `.links`; measured
# 2026-09-11), then PINNED against the one literal it may take (Rule D).
code="$(get "${CONTROL_HOST}/api/0/organizations/${ORG}/")"
region="$(jq -r '.links.regionUrl // empty' "$TOKEN_DIR/body" 2>/dev/null | sed 's#/$##')"
if [[ "$code" != "200" || "$region" != "$REGION_HOST_PINNED" ]]; then
  printf '[FAIL] org read HTTP %s, regionUrl is %q, pinned to %s -- refusing an unpinned destination\n' "$code" "$region" "$REGION_HOST_PINNED" >&2; fails=$((fails + 1))
fi
# Every consumer's EXACT host + org + path (plan Phase 2.3). Never reason from one
# endpoint's 200 to another's. The org-events endpoint REQUIRES `field=` (HTTP 400 "No
# columns selected" without it -- every real caller passes one). ghcr-minter-live-6031's
# monitor (`scheduled-ghcr-token-minter`) is deliberately absent: it does not exist until
# that cutover, and a 404 on a nonexistent monitor says nothing about the token; the
# check-in endpoint CLASS is covered by the nine rows below.
probes=(
  "${CONTROL_HOST}/api/0/organizations/${ORG}/"
  "${CONTROL_HOST}/api/0/organizations/${ORG}/events/?per_page=1&field=title&field=timestamp"
  "${ORG_HOST}/api/0/organizations/${ORG}/events/?field=count()&statsPeriod=1h"
  "${REGION_HOST_PINNED}/api/0/organizations/${ORG}/monitors/scheduled-community-monitor/checkins/?per_page=1"
  "${CONTROL_HOST}/api/0/organizations/${ORG}/monitors/scheduled-terraform-drift/checkins/?limit=5"
  "${CONTROL_HOST}/api/0/organizations/${ORG}/monitors/scheduled-oauth-probe/checkins/?limit=5"
  "${CONTROL_HOST}/api/0/organizations/${ORG}/monitors/scheduled-github-app-drift-guard/checkins/?limit=5"
  "${CONTROL_HOST}/api/0/organizations/${ORG}/monitors/scheduled-daily-triage/checkins/?limit=5"
  "${CONTROL_HOST}/api/0/organizations/${ORG}/monitors/scheduled-realtime-probe/checkins/?limit=5"
  "${CONTROL_HOST}/api/0/organizations/${ORG}/monitors/scheduled-skill-freshness/checkins/?limit=5"
  "${CONTROL_HOST}/api/0/organizations/${ORG}/monitors/scheduled-content-vendor-drift/checkins/?limit=5"
  "${CONTROL_HOST}/api/0/organizations/${ORG}/monitors/scheduled-community-monitor/checkins/?limit=5"
  "${REGION_HOST_PINNED}/api/0/projects/${ORG}/${PROJECT}/issues/?limit=1"
  "${REGION_HOST_PINNED}/api/0/projects/${ORG}/${PROJECT}/events/?per_page=1"
)
for u in "${probes[@]}"; do
  code="$(get "$u")"
  if [[ "$code" == "200" ]]; then
    printf '[ok] 200 %s\n' "${u%%\?*}"
  else
    printf '[FAIL] %s %s\n' "$code" "${u%%\?*}" >&2; fails=$((fails + 1))
  fi
done
if (( fails > 0 )); then
  printf '[FAIL] %d verification failure(s) -- the cutover is BLOCKED until every row is 200 and the scopes match\n' "$fails" >&2
  exit 1
fi
printf '[ok] verified: scopes exact, every consumer endpoint 200. The trap shreds the plaintext on exit.\n'
exit 0
