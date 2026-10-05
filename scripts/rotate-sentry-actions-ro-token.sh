#!/usr/bin/env bash
# rotate-sentry-actions-ro-token.sh -- the capture -> normalise -> verify -> store -> shred
# chain for SENTRY_ACTIONS_RO_TOKEN, the org-level read-only Sentry Internal Integration
# token (`actions-read-prd`, ADR-031) that scripts/followthroughs/*.sh and the fresh-host
# boot-trail consume. Lives ONCE; the rotation runbook
# (knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md)
# invokes it and does not restate it. Ref #7946.
#
# The whole chain runs in ONE process so a single trap scope holds the plaintext from
# capture to shred. Bash tool calls do not share a shell, so a trap set in one call has
# already fired before the next call runs -- which is why the capture is a subprocess of
# THIS script (`agent-browser get value`), never a separate tool call.
#
# Modes
#   capture --selector <agent-browser selector>
#       `agent-browser get value <sel>` writes the readonly token textbox's value straight
#       into the trap directory (no snapshot, no screenshot, never argv).
#   capture --from-file <path>
#       The caller already holds the plaintext in a file it owns; it is copied into the trap
#       directory and the source is shredded in place (a cross-filesystem `mv` would leave
#       the source's blocks behind). Provenance of <path> is the caller's responsibility.
#   --dry-run --expect <sentinel>   (with either capture form)
#       Zero writes: normalise, `diff` the output against the sentinel byte-exact, prove
#       the `gh secret set` FORM with gh's no-store flag (prints the ciphertext length,
#       stores nothing), confirm the trap removed the directory. That flag appears in the
#       dry-run branch only.
#
# Rule D (ADR-202): every curl is `--disable --noproxy '*'` and every destination is a
# literal; the region host read back from the API is pinned against the one literal it may
# take. The bearer never rides argv: the header is written to a file in the trap directory
# and passed with `-H @file`, so nothing lands in /proc/*/cmdline.
#
# Exit: 0 chain complete (or dry run clean); 1 a verification failed (scopes, an endpoint,
#       the store, the shape); 2 usage / precondition; 78 xtrace refusal; 130/143 on
#       SIGINT/SIGTERM after the trap has shredded (the chain does NOT resume).

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
# finding, never accepted as a superset (plan AC-6). Every document that quotes the triple
# cites this constant; it is the one executable copy.
readonly EXPECTED_SCOPES='["event:read","org:read","project:read"]'
# Token shape bounds. Sentry's token format is not fixed across generations (the integration
# tokens on this org are 64 chars; org auth tokens are `sntrys_…`, longer), so nothing
# asserts hex or an exact length -- only "plausible", so a rotation is never blocked by a
# false format diagnosis. The dry run relaxes the floor to the sentinel's length.
readonly TOKEN_MINLEN=40
readonly TOKEN_MAXLEN=256

usage() { printf 'usage: %s capture (--selector S | --from-file F) [--dry-run --expect SENTINEL]\n' "$0" >&2; exit 2; }
MODE=""; SELECTOR=""; FROM_FILE=""; DRY_RUN=0; EXPECT=""
while (( $# > 0 )); do
  case "$1" in
    capture)     MODE="capture" ;;
    --selector)  SELECTOR="${2:-}";  [[ -n "$SELECTOR" ]]  || { printf 'usage error: --selector needs a value\n' >&2; exit 2; }; shift ;;
    --from-file) FROM_FILE="${2:-}"; [[ -n "$FROM_FILE" ]] || { printf 'usage error: --from-file needs a path\n' >&2; exit 2; }; shift ;;
    --dry-run)   DRY_RUN=1 ;;
    --expect)    EXPECT="${2:-}";    [[ -n "$EXPECT" ]]    || { printf 'usage error: --expect needs a sentinel\n' >&2; exit 2; }; shift ;;
    -h|--help)   awk 'NR > 1 { if ($0 !~ /^#/) exit; print }' "$0"; exit 0 ;;
    *) printf 'usage error: unknown argument %q\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
[[ "$MODE" == "capture" ]] || usage
if [[ -n "$SELECTOR" && -n "$FROM_FILE" ]] || [[ -z "$SELECTOR" && -z "$FROM_FILE" ]]; then
  printf 'usage error: capture takes exactly one of --selector or --from-file\n' >&2; exit 2
fi
if [[ "$DRY_RUN" == "1" && -z "$EXPECT" ]]; then
  printf 'usage error: --dry-run requires --expect <sentinel>\n' >&2; exit 2
fi
# Preflight every external tool BEFORE the trap scope, so a missing binary is named as such
# rather than surfacing as a misattributed "shape assertion" or "store form is wrong".
for t in gh curl jq python3 shred; do
  command -v "$t" >/dev/null 2>&1 || { printf '[FATAL] %s is not on PATH\n' "$t" >&2; exit 2; }
done
[[ -z "$SELECTOR" ]] || command -v agent-browser >/dev/null 2>&1 || { printf '[FATAL] agent-browser is not on PATH\n' >&2; exit 2; }

umask 077
TOKEN_DIR="$(mktemp -d)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
chmod 0700 "$TOKEN_DIR"

# THE TRAP SCOPE. From here to exit, every plaintext byte lives under $TOKEN_DIR and is
# shredded on any exit. A failed shred is LOGGED, not hidden: on tmpfs (this workstation's
# /tmp, measured) shred is effective; on a journaled or copy-on-write filesystem it is
# best-effort and the 0700 directory plus the seconds-long lifetime are the primary control.
# Signals shred and then EXIT with the signal's status -- a handler that returned would let
# the chain resume against a shredded directory and print a misleading verdict.
# shellcheck disable=SC2317  # invoked by trap
cleanup() {
  if [[ -d "$TOKEN_DIR" ]]; then
    find "$TOKEN_DIR" -mindepth 1 -type f -exec shred -u {} + 2>/dev/null \
      || printf '[WARN] shred of %s failed -- remove it by hand\n' "$TOKEN_DIR" >&2
    rmdir "$TOKEN_DIR" 2>/dev/null || printf '[WARN] could not remove %s\n' "$TOKEN_DIR" >&2
  fi
}
trap cleanup EXIT
trap 'cleanup; trap - EXIT; exit 130' INT
trap 'cleanup; trap - EXIT; exit 143' TERM HUP

TOK="$TOKEN_DIR/tok"
HDR="$TOKEN_DIR/hdr"

if [[ -n "$SELECTOR" ]]; then
  # `get value` writes the raw textbox value; it is the one read of the token panel that
  # is NOT a snapshot or a screenshot (#7947 discipline). On failure only the exit code and
  # the selector are reported -- agent-browser's stderr is not proven value-free.
  cap_rc=0
  agent-browser get value "$SELECTOR" > "$TOK" 2>/dev/null || cap_rc=$?
  if (( cap_rc != 0 )); then
    printf '[FATAL] agent-browser get value %q failed (rc=%s) -- is the Tokens panel open in the current session?\n' "$SELECTOR" "$cap_rc" >&2; exit 1
  fi
else
  [[ -f "$FROM_FILE" ]] || { printf '[FATAL] --from-file %q is absent: the capture did not land where expected; find and shred it before retrying\n' "$FROM_FILE" >&2; exit 1; }
  cp -- "$FROM_FILE" "$TOK" || { printf '[FATAL] could not copy the captured file into the trap directory\n' >&2; exit 1; }
  shred -u -- "$FROM_FILE" || printf '[WARN] shred of %s failed -- remove it by hand\n' "$FROM_FILE" >&2
fi
[[ -s "$TOK" ]] || { printf '[FATAL] captured file is empty\n' >&2; exit 1; }

# --- normalise: the two capture forms can write different bytes -------------------------
# A JSON-encoded capture (quotes around the value) and raw text are both accepted. One
# tolerant step, asserting non-empty / whitespace-free / plausible length and logging ONLY
# the length plus the last four characters -- the same four Sentry renders in its masked
# Tokens panel, so an agent can tell rows apart after the plaintext is gone.
minlen="$TOKEN_MINLEN"
[[ "$DRY_RUN" == "1" ]] && minlen=1
python3 - "$minlen" "$TOKEN_MAXLEN" "$TOK" > "$TOKEN_DIR/norm" <<'PY'
import sys, json
minlen, maxlen = int(sys.argv[1]), int(sys.argv[2])
s = open(sys.argv[3]).read()
v = json.loads(s) if s.lstrip().startswith('"') else s.strip()
assert isinstance(v, str) and minlen <= len(v) <= maxlen and not any(c.isspace() for c in v), "token shape"
sys.stderr.write("token length %d, ends ...%s\n" % (len(v), v[-4:] if len(v) > 8 else "?"))
sys.stdout.write(v)
PY
rc=$?
[[ "$rc" -eq 0 ]] || { printf '[FATAL] normalise failed (shape assertion, rc=%s) -- see the python message above\n' "$rc" >&2; exit 1; }
mv -f "$TOKEN_DIR/norm" "$TOK"
TAIL4="$(tail -c 4 "$TOK")"

# --- dry run: zero writes, exits here --------------------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
  if ! diff -q <(printf '%s' "$EXPECT") "$TOK" >/dev/null; then
    printf '[FAIL] dry run: normalised output is not byte-identical to the sentinel\n' >&2; exit 1
  fi
  printf '[ok] dry run: normalised output is byte-identical to the sentinel (%d bytes)\n' "$(wc -c < "$TOK")"
  # Prove the STORE FORM without storing: the value on STDIN with no body flag at all --
  # gh has no body-file flag, and a body of `-` stores the literal `-` (measured in
  # scripts/rotate-x-api-secret-bootstrap.sh's header). The no-store flag prints the base64
  # ciphertext instead of writing it: libsodium sealed box = 48 bytes overhead + plaintext,
  # base64-expanded, plus gh's trailing newline (the `+ 1`).
  cipher="$(gh secret set ZZ_DRYRUN_7946 --no-store < "$TOK")"  # the only no-store site
  gh_rc=$?
  [[ "$gh_rc" -eq 0 ]] || { printf '[FATAL] dry run: gh secret set (no-store) failed rc=%s -- authenticate gh / run from the repo, then retry\n' "$gh_rc" >&2; exit 1; }
  n=$(( ${#cipher} + 1 ))
  want=$(( ( (48 + $(wc -c < "$TOK")) + 2 ) / 3 * 4 + 1 ))
  if [[ "$n" == "$want" ]]; then
    printf '[ok] dry run: gh secret set (no-store) ciphertext length %d matches the computed %d (nothing written)\n' "$n" "$want"
  else
    printf '[FAIL] dry run: ciphertext length %d, computed %d -- the store form is wrong\n' "$n" "$want" >&2; exit 1
  fi
  exit 0
fi

# --- verify: the header rides a FILE, never argv ---------------------------------------
{ printf 'Authorization: Bearer '; cat "$TOK"; } > "$HDR"
get() { # get <url> -> prints http code (000 + the curl error on a transport failure); body to $TOKEN_DIR/body
  local code
  code="$(curl --disable --noproxy '*' -sS --max-time 25 -o "$TOKEN_DIR/body" -w '%{http_code}' -H @"$HDR" "$1" 2>"$TOKEN_DIR/curl.err")"
  if [[ -z "$code" || "$code" == "000" ]]; then
    printf '000 (%s)' "$(tr '\n' ' ' < "$TOKEN_DIR/curl.err" | head -c 160)"
  else
    printf '%s' "$code"
  fi
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
# One probe per (host, endpoint class, consumer): org events on both hosts the followthroughs
# use (nine callers on sentry.io; anthropic-admin-key-6297 on the org host -- `field=` is
# REQUIRED, HTTP 400 without it), the cron check-in endpoint on both hosts
# (sentry-checkins-3859 / ghcr-minter-live-6031 on sentry.io; community-monitor-checkin-
# soak-5728 on the region host), project issues (sync-health-residual-5689) and project
# events (the boot-trail). Monitor slugs are sampled, not enumerated: a moved slug is the
# consumer's own 404 TRANSIENT, not a scope question.
probes=(
  "${CONTROL_HOST}/api/0/organizations/${ORG}/events/?per_page=1&field=title&field=timestamp"
  "${ORG_HOST}/api/0/organizations/${ORG}/events/?field=count()&statsPeriod=1h"
  "${CONTROL_HOST}/api/0/organizations/${ORG}/monitors/scheduled-terraform-drift/checkins/?limit=5"
  "${REGION_HOST_PINNED}/api/0/organizations/${ORG}/monitors/scheduled-community-monitor/checkins/?per_page=1"
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
  printf '[FAIL] %d verification failure(s) -- the cutover is BLOCKED until every row is 200 and the scopes match; the repo secret was NOT touched. Revoke this token in-page before retrying.\n' "$fails" >&2
  exit 1
fi
printf '[ok] verified: scopes exact, every consumer endpoint class 200 -- storing.\n'

# --- store: AFTER verification, so a token that fails the scope or endpoint checks never
# overwrites the previous repo secret (GitHub cannot read a secret back, so an overwrite is
# unrecoverable and the next sweep would run on the rejected token). The value rides stdin,
# never a flag argument (visible in ps and under -x). -------------------------------------
if ! gh secret set SENTRY_ACTIONS_RO_TOKEN < "$TOK"; then  # literal: AC-12 counts this exact form
  printf '[FATAL] gh secret set %s failed. A live token exists that nothing holds: REVOKE IT IN-PAGE NOW (the integration'"'"'s Tokens panel), then retry.\n' "$SECRET_NAME" >&2
  exit 1
fi
# The list read is a SEPARATE instrument from the write: a failed list (expired auth, rate
# limit, network) must not be read as "not stored" and turned into a revoke instruction.
if ! listing="$(gh secret list 2>"$TOKEN_DIR/list.err")"; then
  printf '[FATAL] gh secret list failed after the write (%s) -- the store may have landed; re-run the list before revoking anything\n' "$(tr '\n' ' ' < "$TOKEN_DIR/list.err" | head -c 200)" >&2
  exit 1
fi
if [[ "$(grep -c "^${SECRET_NAME}\b" <<<"$listing")" != "1" ]]; then
  printf '[FATAL] %s is not listed after a successful write -- revoke the token in-page and investigate\n' "$SECRET_NAME" >&2; exit 1
fi
printf '[ok] stored %s (token ends ...%s; GitHub cannot read it back -- the value is proven by the sweeper dispatch)\n' "$SECRET_NAME" "$TAIL4"

printf '[ok] done. The trap shreds the plaintext on exit.\n'
exit 0
