#!/usr/bin/env bash
# rotate-sentry-actions-ro-token.sh -- the capture -> normalise -> verify -> store -> shred
# chain for a Sentry Internal Integration token on org jikigai-eu (ADR-031). One chain, two
# profiles (the filename keeps its historical `ro` name):
#
#   --profile ro  (default) SENTRY_ACTIONS_RO_TOKEN, the read-only `actions-read-prd` token
#       that scripts/followthroughs/*.sh and the fresh-host boot-trail consume. Stored to the
#       GitHub repo secret only.
#   --profile iac SENTRY_IAC_AUTH_TOKEN, the `iac-terraform-prd` token that the Sentry
#       Terraform roots, the alert-drift fidelity check, the monitors audit and operator issue
#       reads consume. Stored to the GitHub repo secret, then Doppler soleur/prd, then Doppler
#       soleur/prd_terraform. Doppler branch configs here are INDEPENDENT copies (no live
#       inheritance from the root), so both are written and each is read back by digest.
#
# Lives ONCE; the rotation runbook
# (knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md)
# invokes it and does not restate it. Ref #7946. Needs GNU userland (shred, sed -z, sha256sum).
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
# Doppler's `secrets set` has no no-store mode, so the dry run cannot prove the Doppler store
# form without writing; it proves Doppler login and both target configs read-only, and the
# exact store argv + stdin is pinned by scripts/rotate-sentry-actions-ro-token.test.sh.
#
# Rule D (ADR-202): every curl is `--disable --noproxy '*'` and every destination is a
# literal; the ro profile's region host read back from the API is pinned against the one
# literal it may take. The bearer never rides argv: the header is written to a file in the
# trap directory and passed with `-H @file`, so nothing lands in /proc/*/cmdline. Doppler
# writes take the value on STDIN and discard the CLI's output (it prints every other secret
# of the config on a write); read-backs are compared by sha256 digest, never printed.
#
# Exit: 0 chain complete (or dry run clean); 1 a verification failed (scopes, an endpoint,
#       a store, the shape); 2 usage / precondition; 78 xtrace refusal; 130/143 on
#       SIGINT/SIGTERM after the trap has shredded (the chain does NOT resume).

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Unconditional: this script ACQUIRES the credential at
# runtime, so a `${VAR:+x}` hatch would be open by construction. `$-` is the load-bearing
# arm -- bash applies an env-supplied SHELLOPTS/BASH_ENV before line 1.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

readonly ORG="jikigai-eu"
readonly PROJECT="web-platform"
readonly ORG_HOST="https://jikigai-eu.sentry.io"
readonly CONTROL_HOST="https://sentry.io"
readonly REGION_HOST_PINNED="https://de.sentry.io"
readonly DOPPLER_PROJECT="soleur"
# sha256 of the empty string: a failed or empty Doppler read-back hashes to this, and it is
# a READ FAILURE, never a match.
readonly EMPTY_DIGEST="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
# Token shape bounds. Sentry's token format is not fixed across generations (the integration
# tokens on this org are 64 chars; org auth tokens are `sntrys_…`, longer), so nothing
# asserts hex or an exact length -- only "plausible", so a rotation is never blocked by a
# false format diagnosis. The dry run relaxes the floor to the sentinel's length.
readonly TOKEN_MINLEN=40
readonly TOKEN_MAXLEN=256

usage() { printf 'usage: %s capture (--selector S | --from-file F) [--profile ro|iac] [--dry-run --expect SENTINEL]\n' "$0" >&2; exit 2; }
MODE=""; SELECTOR=""; FROM_FILE=""; DRY_RUN=0; EXPECT=""; PROFILE="ro"
while (( $# > 0 )); do
  case "$1" in
    capture)     MODE="capture" ;;
    --selector)  SELECTOR="${2:-}";  [[ -n "$SELECTOR" ]]  || { printf 'usage error: --selector needs a value\n' >&2; exit 2; }; shift ;;
    --from-file) FROM_FILE="${2:-}"; [[ -n "$FROM_FILE" ]] || { printf 'usage error: --from-file needs a path\n' >&2; exit 2; }; shift ;;
    --profile)   PROFILE="${2:-}";   [[ "$PROFILE" == "ro" || "$PROFILE" == "iac" ]] || { printf 'usage error: --profile takes ro or iac\n' >&2; exit 2; }; shift ;;
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

# --- the profile table: the ONLY writer of SECRET_NAME, EXPECTED_SCOPES and probes -------
# EXPECTED_SCOPES: the permission set selected in the integration's dashboard form must come
# back as EXACTLY these scopes -- an implied extra is a finding, never accepted as a superset
# (plan AC-6). Every document that quotes a set cites the constant here; it is the one
# executable copy.
case "$PROFILE" in
  ro)
    SECRET_NAME="SENTRY_ACTIONS_RO_TOKEN"
    INTEGRATION="actions-read-prd"
    # Issue & Event = Read, Organization = Read, Project = Read.
    EXPECTED_SCOPES='["event:read","org:read","project:read"]'
    # One probe per (host, endpoint class, consumer): org events on both hosts the
    # followthroughs use (nine callers on sentry.io; anthropic-admin-key-6297 on the org host
    # -- `field=` is REQUIRED, HTTP 400 without it), the cron check-in endpoint on both hosts
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
    ;;
  iac)
    SECRET_NAME="SENTRY_IAC_AUTH_TOKEN"
    INTEGRATION="iac-terraform-prd"
    # ADR-031 §"Why a dedicated Internal Integration" -- this constant is its executable copy.
    EXPECTED_SCOPES='["alerts:read","alerts:write","event:read","org:read","project:admin","project:read","project:write"]'
    # One read-only GET per IaC consumer class, all on the org-subdomain host (every IaC
    # consumer uses it: the terraform provider's base_url is https://<org>.sentry.io/api/, and
    # sentry-audit-gate.yml pins SENTRY_API_HOST to the same host).
    probes=(
      # project read: terraform data.sentry_project; apps/web-platform/scripts/sentry-monitors-audit.sh
      "${ORG_HOST}/api/0/projects/${ORG}/${PROJECT}/"
      # alert rules read: terraform sentry_alert; scripts/sentry-alert-live-fidelity.sh; the audit
      "${ORG_HOST}/api/0/organizations/${ORG}/workflows/?per_page=1"
      # monitors read: terraform sentry_cron_monitor; the audit
      "${ORG_HOST}/api/0/organizations/${ORG}/monitors/?per_page=1"
      # org issues search: operator/agent issue reads (AGENTS.rules.md hr-no-dashboard-eyeball-pull-data-yourself)
      "${ORG_HOST}/api/0/organizations/${ORG}/issues/?query=is:unresolved&limit=1&statsPeriod=24h"
    )
    ;;
esac
readonly PROFILE SECRET_NAME INTEGRATION EXPECTED_SCOPES

# Preflight every external tool BEFORE the trap scope, so a missing binary is named as such
# rather than surfacing as a misattributed "shape assertion" or "store form is wrong".
tools=(gh curl jq python3 shred)
[[ "$PROFILE" == "iac" ]] && tools+=(doppler sha256sum sed)
for t in "${tools[@]}"; do
  command -v "$t" >/dev/null 2>&1 || { printf '[FATAL] %s is not on PATH\n' "$t" >&2; exit 2; }
done
[[ -z "$SELECTOR" ]] || command -v agent-browser >/dev/null 2>&1 || { printf '[FATAL] agent-browser is not on PATH\n' >&2; exit 2; }

# --- iac Doppler preflight: read-only, BEFORE the capture, in dry run and live alike ------
# Proves Doppler login and that both target configs exist with the expected shape, so a
# Doppler problem is found before anything holds the plaintext or any store happens. The
# config list and the secret NAMES are metadata, not secrets.
STALE_COPIES=()
if [[ "$PROFILE" == "iac" ]]; then
  preflight_fail() {
    printf '[FATAL] doppler preflight failed (%s) -- nothing was stored\n' "$1" >&2
    if [[ -n "$FROM_FILE" ]]; then
      printf '[FATAL] %s still holds the plaintext; shred it (shred -u %s) or re-run\n' "$FROM_FILE" "$FROM_FILE" >&2
    fi
    exit 2
  }
  cfgs_rc=0
  cfgs="$(doppler configs -p "$DOPPLER_PROJECT" --json 2>/dev/null)" || cfgs_rc=$?
  (( cfgs_rc == 0 )) || preflight_fail "doppler configs -p ${DOPPLER_PROJECT} rc=${cfgs_rc}; run doppler login"
  jq -e 'type == "array"' >/dev/null 2>&1 <<<"$cfgs" || preflight_fail "doppler configs returned no config list"
  jq -e 'any(.[]; .name == "prd" and .root == true)' >/dev/null <<<"$cfgs" \
    || preflight_fail "${DOPPLER_PROJECT}/prd is absent or not a root config"
  jq -e 'any(.[]; .name == "prd_terraform" and .root == false and .environment == "prd")' >/dev/null <<<"$cfgs" \
    || preflight_fail "${DOPPLER_PROJECT}/prd_terraform is absent or not a prd branch config"
  # Other prd configs that carry their own copy of the key. No repo code reads it from them;
  # they are reported (not written, not blocking) so the operator knows they keep the old
  # value. Removal is tracked in #12740.
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    names_rc=0
    names="$(doppler secrets -p "$DOPPLER_PROJECT" -c "$c" --only-names --json 2>/dev/null)" || names_rc=$?
    if (( names_rc != 0 )); then
      STALE_COPIES+=("${c} (names unreadable)")
    elif jq -e --arg k "$SECRET_NAME" 'has($k)' >/dev/null 2>&1 <<<"$names"; then
      STALE_COPIES+=("$c")
    fi
  done < <(jq -r '.[] | select(.environment == "prd" and .name != "prd" and .name != "prd_terraform") | .name' <<<"$cfgs")
  printf '[ok] doppler preflight: %s/prd (root) and %s/prd_terraform (branch) present\n' "$DOPPLER_PROJECT" "$DOPPLER_PROJECT"
fi
# join_or_none <items...>: "a; b" or "(none)".
join_or_none() { if (( $# == 0 )); then printf '(none)'; else local IFS=';'; printf '%s' "$*" | sed 's/;/; /g'; fi; }
stale_copies_line() {
  local list
  if (( ${#STALE_COPIES[@]} == 0 )); then list="(none)"
  else list="$(printf '%s, ' "${STALE_COPIES[@]}")"; list="${list%, } -- not written; removal tracked in #12740"; fi
  printf 'STALE COPIES (no known reader in repo): %s\n' "$list"
}

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
  if [[ "$PROFILE" == "iac" ]]; then
    printf '[ok] dry run: Doppler login and %s/prd + %s/prd_terraform verified read-only; Doppler has no no-store mode -- store form pinned by the test (nothing written)\n' "$DOPPLER_PROJECT" "$DOPPLER_PROJECT"
    stale_copies_line
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
if [[ "$PROFILE" == "ro" ]]; then
  # Region host: read back from the ORG endpoint (`/api/0/` carries no `.links`; measured
  # 2026-09-11), then PINNED against the one literal it may take (Rule D). The iac profile
  # touches only the org host, so it has no region to pin.
  code="$(get "${CONTROL_HOST}/api/0/organizations/${ORG}/")"
  region="$(jq -r '.links.regionUrl // empty' "$TOKEN_DIR/body" 2>/dev/null | sed 's#/$##')"
  if [[ "$code" != "200" || "$region" != "$REGION_HOST_PINNED" ]]; then
    printf '[FAIL] org read HTTP %s, regionUrl is %q, pinned to %s -- refusing an unpinned destination\n' "$code" "$region" "$REGION_HOST_PINNED" >&2; fails=$((fails + 1))
  fi
fi
for u in "${probes[@]}"; do
  code="$(get "$u")"
  if [[ "$code" == "200" ]]; then
    printf '[ok] 200 %s\n' "${u%%\?*}"
  else
    printf '[FAIL] %s %s\n' "$code" "${u%%\?*}" >&2; fails=$((fails + 1))
  fi
done
if (( fails > 0 )); then
  printf '[FAIL] %d verification failure(s) -- the cutover is BLOCKED until every row is 200 and the scopes match; nothing was stored. Revoke this token in-page before retrying.\n' "$fails" >&2
  exit 1
fi
printf '[ok] verified: scopes exact, every consumer endpoint class 200 -- storing.\n'

# --- store: AFTER verification, so a token that fails the scope or endpoint checks never
# overwrites the previous secret (GitHub cannot read a secret back, so an overwrite is
# unrecoverable and the next sweep would run on the rejected token). The value rides stdin,
# never a flag argument (visible in ps and under -x). -------------------------------------
if [[ "$PROFILE" == "ro" ]]; then
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
fi

# iac: three targets, in this order. Every target is in exactly one of three lists: HOLD
# NEW (written and proven), UNVERIFIED (written or possibly written, value unknown), or
# STILL HOLD OLD (derived: neither of the others). A failure after any target holds the new
# value means BOTH tokens are live somewhere, so the old one must not be revoked yet.
T_GH="GitHub repo secret ${SECRET_NAME}"; T_PRD="Doppler ${DOPPLER_PROJECT}/prd"; T_PTF="Doppler ${DOPPLER_PROJECT}/prd_terraform"
TARGETS=("$T_GH" "$T_PRD" "$T_PTF")
HOLD_NEW=(); UNVERIFIED=()
store_fail() { # store_fail <what failed>: the partial-state report; exits 1
  printf '[FATAL] %s\n' "$1" >&2
  if (( ${#HOLD_NEW[@]} == 0 && ${#UNVERIFIED[@]} == 0 )); then
    printf '[FATAL] nothing holds the new token: REVOKE THE NEW TOKEN (ends ...%s) IN-PAGE NOW (the %s Tokens panel), then retry.\n' "$TAIL4" "$INTEGRATION" >&2
    exit 1
  fi
  local t x old=()
  for t in "${TARGETS[@]}"; do
    for x in "${HOLD_NEW[@]}" "${UNVERIFIED[@]}"; do [[ "$x" == "$t" ]] && continue 2; done
    old+=("$t")
  done
  printf 'HOLD THE NEW TOKEN (...%s): %s\n' "$TAIL4" "$(join_or_none "${HOLD_NEW[@]}")" >&2
  printf 'UNVERIFIED (value unknown): %s\n' "$(join_or_none "${UNVERIFIED[@]}")" >&2
  printf 'STILL HOLD THE OLD TOKEN: %s\n' "$(join_or_none "${old[@]}")" >&2
  printf 'do NOT revoke the old token yet -- re-run the rotation with a freshly minted token, then revoke both the old token and this new token (...%s) in-page\n' "$TAIL4" >&2
  exit 1
}
want_digest="$(sha256sum < "$TOK" | cut -d' ' -f1)"
dig_of() { # dig_of <config>: the sha256 of the stored value (the CLI's appended LF stripped).
  # Returns 1 on a failed or empty read. The value is never printed or held in a variable.
  local d rc=0
  d="$(doppler secrets get "$SECRET_NAME" -p "$DOPPLER_PROJECT" -c "$1" --plain 2>/dev/null | sed -z 's/\n$//' | sha256sum | cut -d' ' -f1)" || rc=$?
  if (( rc != 0 )) || [[ -z "$d" || "$d" == "$EMPTY_DIGEST" ]]; then return 1; fi
  printf '%s' "$d"
}
dop_store() { # dop_store <config> <target label>
  local cfg="$1" label="$2" got w_rc=0 r_rc=0
  # Value on stdin; the CLI prints every other secret of the config on a write, so its
  # stdout and stderr go nowhere and only the exit code is read.
  doppler secrets set SENTRY_IAC_AUTH_TOKEN -p "$DOPPLER_PROJECT" -c "$cfg" --no-interactive < "$TOK" >/dev/null 2>&1 || w_rc=$?
  if (( w_rc != 0 )); then
    # A refused write may still have landed server-side: read back before classifying. A
    # different readable value means this target still holds the old token.
    got="$(dig_of "$cfg")" || r_rc=$?
    if (( r_rc != 0 )); then UNVERIFIED+=("$label")
    elif [[ "$got" == "$want_digest" ]]; then HOLD_NEW+=("$label"); fi
    store_fail "Doppler write to ${DOPPLER_PROJECT}/${cfg} failed (rc=${w_rc})"
  fi
  if ! got="$(dig_of "$cfg")"; then
    UNVERIFIED+=("$label"); store_fail "Doppler ${DOPPLER_PROJECT}/${cfg} read-back failed after the write -- the write may have landed"
  fi
  if [[ "$got" != "$want_digest" ]]; then
    UNVERIFIED+=("$label"); store_fail "Doppler ${DOPPLER_PROJECT}/${cfg} read-back digest does not match the new token"
  fi
  HOLD_NEW+=("$label")
  printf '[ok] stored %s in Doppler %s/%s (read-back digest matches)\n' "$SECRET_NAME" "$DOPPLER_PROJECT" "$cfg"
}

if ! gh secret set SENTRY_IAC_AUTH_TOKEN < "$TOK"; then  # literal: the counted store form
  store_fail "gh secret set ${SECRET_NAME} failed"
fi
if ! listing="$(gh secret list 2>"$TOKEN_DIR/list.err")"; then
  UNVERIFIED+=("$T_GH")
  store_fail "gh secret list failed after the write ($(tr '\n' ' ' < "$TOKEN_DIR/list.err" | head -c 200)) -- the store may have landed"
fi
if [[ "$(grep -c "^${SECRET_NAME}\b" <<<"$listing")" != "1" ]]; then
  UNVERIFIED+=("$T_GH"); store_fail "${SECRET_NAME} is not listed after a successful write"
fi
HOLD_NEW+=("$T_GH")
printf '[ok] stored %s (GitHub cannot read it back -- listed by name)\n' "$T_GH"
dop_store prd "$T_PRD"
dop_store prd_terraform "$T_PTF"

if (( ${#HOLD_NEW[@]} == ${#TARGETS[@]} )); then
  printf '[ok] all three targets hold the new token (...%s): %s\n' "$TAIL4" "$(join_or_none "${HOLD_NEW[@]}")"
  printf '[ok] next: prove it, then revoke the PREVIOUS token by its masked last four -- the runbook'"'"'s IaC section, step "Prove, then revoke".\n'
fi
stale_copies_line
printf '[ok] done. The trap shreds the plaintext on exit.\n'
exit 0
