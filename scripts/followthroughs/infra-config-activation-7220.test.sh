#!/usr/bin/env bash
# Exit-code harness for infra-config-activation-7220.sh's decision arms (#7220 review).
#
# WHY THIS EXISTS. sweep-followthroughs.sh CLOSES the tracked issue on exit 0, so the exit code
# IS the authorization artifact and the cardinal sin is exit 0. Review found the soak returning
# exactly that on a host where reconciliation was BROKEN:
#
#   * it counted every row matching the SUBSTRING `SOLEUR_INFRA_CONFIG_RESTART`, which also
#     matches the sibling diagnostic marker `SOLEUR_INFRA_CONFIG_RESTART_STDERR:`;
#   * it matched `vector.service` anywhere in the payload rather than in the `unit=` field;
#   * and it tested that single tally `>= 1` and reported PASS — so a row reading
#     `action=failed reason=sudo_denied`, the precise state this probe exists to detect,
#     satisfied its PASS condition and would have auto-closed the issue on the evidence of its
#     own recurrence.
#
# Plus: MIN_ELAPSED_SECS was enforced only inside the `frame_ok -eq 1` branch, so when the status
# endpoint was unreachable the PASS arm ran with no freshness guard at all.
#
# HARNESS SHAPE, following the zot-soak-6122 precedent: drive the REAL script through its real jq
# parse path and stub only what it shells out to. Two seams, because the soak uses two kinds of
# call — `betterstack-query.sh` is invoked by ABSOLUTE path derived from the script's own
# location, so it is stubbed by relocating the soak into a sandbox repo root; `curl` is PATH-resolved,
# so it is stubbed on PATH. (#9597, S2) The HMAC is no longer an `openssl` call: the REAL python3 signs,
# so the sandbox PATH resolves it, and the curl stub RECORDS its stdin: the credentials now travel as
# `header = "..."` config lines on stdin, so a stub that ignored stdin could not tell a probe that sends
# the three headers from one that sends none.
set -uo pipefail
# Canonical fixture-dir guard (BYTE-IDENTICAL to plugins/soleur/test/test-helpers.sh; fixture-dir-operand-assert.test.sh compares every copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}


HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOAK="$HERE/infra-config-activation-7220.sh"
PASS=0; FAIL=0
# CASES is the INDEPENDENT counter, incremented at every assertion CALL SITE and never inside
# pass()/fail(). A counter that lives inside the verdict helpers moves WITH the verdict, so
# stubbing fail() to a no-op drops the row and its count together and the accounting identity at
# the bottom still holds. PASS alone cannot serve either: it DEFLATES when verdicts are discarded,
# so a floor reading it fires with "too few assertions" and names the wrong fault.
#
# Never increment inside `$( )` — a subshell discards it. (mk_case runs in one; the increments
# below sit outside it, next to the `if` that decides the verdict.)
CASES=0
pass() { printf '  PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

[[ -f "$SOAK" ]] || { echo "FATAL: soak not found at $SOAK" >&2; exit 2; }

# Single owning trap for every sandbox (ADR-129 rule (c)); /tmp is a machine-global tmpfs shared
# by parallel worktrees, so a per-case leak is unbounded.
# One owning ROOT, not an array of children — `mk_case` is called as `D=$(mk_case …)`, so an
# array append inside it is discarded to the command substitution's subshell and the trap
# reclaims nothing. Measured leak: one sandbox per case on a shared tmpfs.
SANDBOX_ROOT="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
cleanup() { [[ -n "${SANDBOX_ROOT:-}" && -d "$SANDBOX_ROOT" ]] && rm -rf "$SANDBOX_ROOT"; return 0; }
trap cleanup EXIT INT TERM

# Build a sandbox repo root holding the real soak plus stubbed collaborators.
#   $1 = the journald message lines the query returns (one per line, already decoded)
#   $2 = the frame JSON body curl should return, or the literal string NOFRAME
#   $3 = end_ts offset in seconds into the PAST (only used when a frame is supplied)
mk_case() {
  local msgs="$1" frame="$2" age="${3:-7200}"
  local d; d=$(mktemp -d "$SANDBOX_ROOT/case.XXXXXX") || { echo "FATAL: mktemp failed" >&2; exit 2; }
  mkdir -p "$d/scripts/followthroughs" "$d/bin" || { echo "FATAL: sandbox mkdir failed" >&2; exit 2; }
  cp "$SOAK" "$d/scripts/followthroughs/" || { echo "FATAL: sandbox cp failed" >&2; exit 2; }

  # betterstack-query.sh: emit the rows in the shape the soak actually parses — one JSON object
  # per line with a `raw` column that is itself a JSON STRING (the soak does `.raw | fromjson?`).
  # A stub that emitted the decoded message directly would put the fixture seam ABOVE the parse
  # under test, so the field-isolation on SYSLOG_IDENTIFIER/host_name would never be exercised.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'while IFS= read -r m; do\n'
    printf '  [[ -n "$m" ]] || continue\n'
    printf '  inner=$(jq -cn --arg m "$m" \x27{SYSLOG_IDENTIFIER:"infra-config-apply",host_name:"soleur-web-platform",message:$m}\x27)\n'
    printf '  jq -cn --arg r "$inner" \x27{raw:$r}\x27\n'
    printf 'done <<\x27MSGS\x27\n%s\nMSGS\n' "$msgs"
    printf 'exit 0\n'
  } > "$d/scripts/betterstack-query.sh"
  chmod +x "$d/scripts/betterstack-query.sh"

  # python3: the REAL one (the soak signs with it). Symlinked so the sandbox PATH resolves it explicitly and a case can swap it for a failing stub.
  ln -s "$(command -v python3)" "$d/bin/python3" || { echo "FATAL: python3 symlink failed" >&2; exit 2; }

  # curl: RECORDS argv (curl.argv) and stdin (curl.stdin) per call, then answers. NOFRAME is a transport failure (exit 7).
  local rec; rec=$(printf '#!/usr/bin/env bash\nd="$(dirname "$0")/.."\nprintf "call\\n" >> "$d/curl.calls"\nprintf "%%s\\n" "$*" >> "$d/curl.argv"\ncat >> "$d/curl.stdin"\n')
  if [[ "$frame" == "NOFRAME" ]]; then
    printf '%s\nexit 7\n' "$rec" > "$d/bin/curl"
  else
    local end_ts; end_ts=$(( $(date -u +%s) - age ))
    # Substitute the sentinel so a case can ask for a frame with a specific end_ts age.
    printf '%s\ncat <<\x27JSON\x27\n%s\nJSON\nexit 0\n' "$rec" \
      "${frame//__END_TS__/$end_ts}" > "$d/bin/curl"
  fi
  chmod +x "$d/bin/curl"
  printf '%s' "$d"
}

# Synthetic credential values, distinct and long enough that "this value is in no argv" is a meaningful grep.
KEY_V="whsecret-7220-synthetic"; ID_V="cfid-7220-synthetic"; SEC_V="cfsecret-7220-synthetic"
run_case() {  # <sandbox-dir> [NAME=value ...]  (extra assignments win over the defaults; FLAGS=(...) adds bash flags)
  local d="$1"; shift
  env PATH="$d/bin:$PATH" \
    BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
    WEBHOOK_DEPLOY_SECRET="$KEY_V" CF_ACCESS_CLIENT_ID="$ID_V" CF_ACCESS_CLIENT_SECRET="$SEC_V" \
    INFRA_CONFIG_STATUS_URL="https://stub.invalid/hooks/infra-config-status" "$@" \
    bash ${FLAGS[@]+"${FLAGS[@]}"} "$d/scripts/followthroughs/infra-config-activation-7220.sh" >"$d/out.txt" 2>"$d/err.txt"
  RC=$?
  OUT=$(cat "$d/out.txt" "$d/err.txt")
}
FLAGS=()

FRAME_RECONCILED='{"schema_version":2,"end_ts":__END_TS__,"exit_code":0,"files_written":19,"files_total":19,"restarts":[{"unit":"vector.service","action":"restarted"}]}'
FRAME_EMPTY='{"schema_version":2,"end_ts":__END_TS__,"exit_code":0,"files_written":19,"files_total":19,"restarts":[]}'
FRAME_NO_END='{"schema_version":2,"exit_code":0,"files_written":19,"files_total":19,"restarts":[]}'

R_OK='SOLEUR_INFRA_CONFIG_RESTART: unit=vector.service action=restarted reason=stale_config rc=0 active=active'
R_SKIP='SOLEUR_INFRA_CONFIG_RESTART: unit=vector.service action=skipped reason=not_stale rc=0 active=active'
R_DENIED='SOLEUR_INFRA_CONFIG_RESTART: unit=vector.service action=failed reason=sudo_denied rc=1 active=active'
R_STALLED='SOLEUR_INFRA_CONFIG_RESTART: unit=vector.service action=failed reason=restart_did_not_advance rc=0 active=active'
R_STDERR='SOLEUR_INFRA_CONFIG_RESTART_STDERR: unit=vector.service rc=1 detail=Interactive_authentication_required_vector.service'
R_OTHER_UNIT='SOLEUR_INFRA_CONFIG_RESTART: unit=inngest-heartbeat.service action=restarted reason=stale_config rc=0 active=active'
# The two rows that make the ANCHORING load-bearing rather than belt-and-braces. Both are
# representable on a real host: infra-config-apply.sh scrubs the _STDERR `detail=` field to
# `A-Za-z0-9 ._:/=-` , which INCLUDES `=` and letters, so free upstream systemctl/sudo text can
# legitimately contain the literal `action=failed`. Unanchored matching turns each into a
# spurious FAIL — paging the operator about a host that is fine, the inverse of the PASS bug but
# a defect all the same.
#
# (a) marker anchoring: a _STDERR row FOR vector.service whose detail quotes `action=failed`.
R_STDERR_TRAP='SOLEUR_INFRA_CONFIG_RESTART_STDERR: unit=vector.service rc=1 detail=systemd reported action=failed for a dependency'
# (b) unit-field anchoring: a genuine verdict row for a DIFFERENT unit whose NAME contains
#     `vector.service` as a substring. Realistic the moment RESTART_MAP gains a second unit.
R_SUBSTRING_UNIT='SOLEUR_INFRA_CONFIG_RESTART: unit=legacy-vector.service action=failed reason=sudo_denied rc=1 active=active'
FATAL='SOLEUR_INFRA_CONFIG_FATAL: line=642 rc=1 cmd=sudo_systemctl_daemon-reload'

echo "infra-config-activation-7220.test.sh"

# --- THE HEADLINE DEFECT: a denied restart must never be a PASS ----------------------------
D=$(mk_case "$R_DENIED" "$FRAME_EMPTY"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 1 ]]; then
  pass "action=failed reason=sudo_denied is a FAIL, not a PASS"
else fail "a denied restart returned rc=$RC — PASS auto-closes the issue on broken reconciliation"; fi
CASES=$((CASES + 1))
if grep -qF 'sudo_denied' <<<"$OUT"; then
  pass "the FAIL quotes the reason the host gave"
else fail "the FAIL does not quote the host's reason, so the remedy is unknowable"; fi

D=$(mk_case "$R_STALLED" "$FRAME_EMPTY"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 1 ]] && grep -qF 'restart_did_not_advance' <<<"$OUT"; then
  pass "action=failed reason=restart_did_not_advance is a FAIL and names its reason"
else fail "a stalled restart returned rc=$RC (reason quoted: $(grep -qF restart_did_not_advance <<<"$OUT" && echo yes || echo no))"; fi

# --- MARKER ANCHORING: the _STDERR sibling is not a verdict --------------------------------
# The old substring match counted this row and PASSed on it. There is no verdict here at all.
D=$(mk_case "$R_STDERR" "$FRAME_EMPTY"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -ne 0 ]]; then
  pass "a lone _STDERR diagnostic row is not read as a reconciliation verdict"
else fail "PASSed on a _STDERR row — the substring-match defect is still live"; fi

# A _STDERR row whose free-text detail QUOTES `action=failed`, alongside a genuine success.
# Without the trailing-colon anchor the diagnostic row is read as a failed verdict and a healthy
# host is graded FAIL — a false alarm on the one channel the operator is paged on.
D=$(mk_case "$(printf '%s\n%s' "$R_OK" "$R_STDERR_TRAP")" "$FRAME_RECONCILED"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 0 ]]; then
  pass "a _STDERR detail quoting 'action=failed' is not mistaken for a failed verdict"
else fail "graded rc=$RC — free upstream text inside detail= was read as a verdict (false alarm)"; fi

# --- FIELD ANCHORING: unit= , not the name anywhere in the payload -------------------------
D=$(mk_case "$R_OTHER_UNIT" "$FRAME_EMPTY"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -ne 0 ]]; then
  pass "a verdict for a DIFFERENT unit does not satisfy the vector.service control"
else fail "PASSed on another unit's verdict row"; fi

# A different unit whose NAME merely CONTAINS vector.service, failing, alongside a genuine
# vector.service success. Unanchored, the other unit's failure is attributed to vector.service.
D=$(mk_case "$(printf '%s\n%s' "$R_OK" "$R_SUBSTRING_UNIT")" "$FRAME_RECONCILED"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 0 ]]; then
  pass "another unit whose name CONTAINS vector.service is not attributed to vector.service"
else fail "graded rc=$RC — a substring unit match imported an unrelated unit's failure"; fi

# --- THE GENUINE PASSES -------------------------------------------------------------------
D=$(mk_case "$R_OK" "$FRAME_RECONCILED"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 0 ]]; then
  pass "action=restarted with a fresh frame and no failures is a PASS"
else fail "a genuine reconciliation returned rc=$RC — the probe cannot ever close (out=$OUT)"; fi

D=$(mk_case "$R_SKIP" "$FRAME_RECONCILED"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 0 ]]; then
  pass "action=skipped is also a PASS (the loop was reached; nothing needed restarting)"
else fail "action=skipped returned rc=$RC — a not_stale unit is a healthy outcome"; fi

# --- PRECEDENCE: a failure in the window wins over a success ------------------------------
D=$(mk_case "$(printf '%s\n%s' "$R_OK" "$R_DENIED")" "$FRAME_RECONCILED"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 1 ]]; then
  pass "a window holding BOTH a success and a failure grades FAIL"
else fail "graded rc=$RC on a window containing action=failed — the success masked it"; fi

D=$(mk_case "$(printf '%s\n%s' "$FATAL" "$R_OK")" "$FRAME_RECONCILED"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 1 ]]; then
  pass "a fatal row still wins over a reconciliation success"
else fail "graded rc=$RC with a SOLEUR_INFRA_CONFIG_FATAL row present"; fi

# --- THE HOISTED FRESHNESS GUARD ----------------------------------------------------------
# Reachable rows that WOULD pass, but no frame: previously PASS with no elapsed guard at all.
D=$(mk_case "$R_OK" NOFRAME); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 2 ]]; then
  pass "an unreachable status endpoint is TRANSIENT, not a PASS without the freshness guard"
else fail "graded rc=$RC with no frame — the elapsed guard was unenforceable and PASS auto-closes"; fi

# A death is still reported loudly even with no frame: that evidence is unambiguous.
D=$(mk_case "$FATAL" NOFRAME); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 1 ]]; then
  pass "a fatal row FAILs even when the status endpoint is down"
else fail "a fatal row graded rc=$RC with no frame — unambiguous evidence was downgraded"; fi

# Too recent: Vector batches at 10 events, so the window is half-written.
D=$(mk_case "$R_OK" "$FRAME_RECONCILED" 10); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 2 ]]; then
  pass "an apply that ended seconds ago is TRANSIENT, not graded"
else fail "graded rc=$RC on a 10s-old apply — a half-written window"; fi

# No end_ts at all: the guard has no reference point, so it cannot be satisfied.
D=$(mk_case "$R_OK" "$FRAME_NO_END"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 2 ]]; then
  pass "a frame with no parseable end_ts is TRANSIENT (the guard has no reference point)"
else fail "graded rc=$RC on a frame with no end_ts"; fi

# --- AMBIGUITY IS NEVER A PASS ------------------------------------------------------------
D=$(mk_case "" "$FRAME_EMPTY"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 1 ]]; then
  pass "zero verdict rows AND an empty frame restarts[] is a FAIL (delivered, activated nothing)"
else fail "graded rc=$RC on an apply that reconciled nothing"; fi

D=$(mk_case "" "$FRAME_RECONCILED"); run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 2 ]]; then
  pass "zero verdict rows but a populated frame restarts[] is TRANSIENT (log lag), not a defect"
else fail "graded rc=$RC when the frame reported verdicts the log window had not shipped"; fi

# --- THE CREDENTIAL TRANSPORT (#9597, S2): the recorded stdin, not just "a curl happened" ------------------------------
# A frame request that reaches curl must carry EXACTLY the three header lines on stdin (a 64-hex digest equal to the independent
# openssl oracle over the empty body, then the Cloudflare Access id, then the secret) and no credential on argv. A stub that
# ignored stdin would let a probe that sends no credential pass every verdict case above.
command -v openssl >/dev/null 2>&1 || { echo "FATAL: openssl is the independent oracle for the signature" >&2; exit 2; }
WANT_SIG=$(printf '' | openssl dgst -sha256 -hmac "$KEY_V" | sed 's/.*= //')
D=$(mk_case "$R_OK" "$FRAME_RECONCILED"); run_case "$D"
mapfile -t STDIN_LINES < <(grep -v '^$' "$D/curl.stdin" 2>/dev/null)
HDR_SIG_RE='^header = "X-Signature-256: sha256=([0-9a-f]{64})"$'
HDR_ID_PFX='header = "CF-Access-Client-Id: '
HDR_SEC_PFX='header = "CF-Access-Client-Secret: '
CASES=$((CASES + 1))
if [[ "$RC" -eq 0 && "${#STDIN_LINES[@]}" -eq 3 \
      && "${STDIN_LINES[0]}" =~ $HDR_SIG_RE && "${BASH_REMATCH[1]}" == "$WANT_SIG" \
      && "${STDIN_LINES[1]}" == "${HDR_ID_PFX}${ID_V}\"" && "${STDIN_LINES[2]}" == "${HDR_SEC_PFX}${SEC_V}\"" ]]; then
  pass "the frame request carries exactly the three header lines on curl's stdin (64-hex digest equal to the openssl oracle, the id, the secret)"
else fail "frame request stdin was not the three expected header lines (rc=$RC lines=${#STDIN_LINES[@]})"; fi
CASES=$((CASES + 1))
ARGV_REC=$(cat "$D/curl.argv" 2>/dev/null)
if [[ "$ARGV_REC" != *"$KEY_V"* && "$ARGV_REC" != *"$ID_V"* && "$ARGV_REC" != *"$SEC_V"* && "$ARGV_REC" != *"$WANT_SIG"* && "$ARGV_REC" != *"-H "* \
      && "$ARGV_REC" == "--disable --noproxy *"* && "$ARGV_REC" == *"--config -"* ]]; then
  pass "no credential, digest or -H header is on curl's argv; --disable --noproxy '*' come first and the config comes from stdin"
else fail "curl argv carries a credential or lost its prologue"; fi
CASES=$((CASES + 1))
if ! grep -qE "$KEY_V|$ID_V|$SEC_V" "$D/out.txt" "$D/err.txt"; then pass "no credential value reaches the probe's stdout or stderr"
else fail "a credential value reached the probe's output"; fi

# A malformed Cloudflare Access value is refused BEFORE curl: exit 2 (TRANSIENT, never the FAIL verdict 1), one value-free marker, nothing echoed.
for spec in "id|CF_ACCESS_CLIENT_ID|SYNTHMARK1\"x" "secret|CF_ACCESS_CLIENT_SECRET|SYNTHMARK2"$'\n'"url = \"http://evil.example.test/second" "space|CF_ACCESS_CLIENT_SECRET|SYNTHMARK3 x"; do
  IFS='|' read -r _l _v _x <<< "$spec"; _val="${spec#*|*|}"
  D=$(mk_case "$R_OK" "$FRAME_RECONCILED"); run_case "$D" "$_v=$_val"
  CASES=$((CASES + 1))
  if [[ "$RC" -eq 2 && ! -e "$D/curl.calls" && "$(grep -cxF 'SOLEUR_CREDENTIAL_REFUSED script=infra-config-activation-7220 reason=token_shape' "$D/err.txt")" -eq 1 ]] \
     && ! grep -qF 'SYNTHMARK' "$D/out.txt" "$D/err.txt"; then
    pass "a hostile Cloudflare Access $_l value is refused before curl (rc 2, zero calls, the marker once, nothing echoed)"
  else fail "hostile $_l value: rc=$RC calls=$([[ -e "$D/curl.calls" ]] && echo yes || echo none)"; fi
done

# A signature that cannot be computed (python3 failing) is refused before curl, never sent unsigned; this used to be a silent skip of the frame arm.
D=$(mk_case "$R_OK" "$FRAME_RECONCILED"); assert_fixture_dir "$D"; rm -f "$D/bin/python3"; printf '#!/usr/bin/env bash\nexit 1\n' > "$D/bin/python3"; chmod +x "$D/bin/python3"
run_case "$D"
CASES=$((CASES + 1))
if [[ "$RC" -eq 2 && ! -e "$D/curl.calls" && "$(grep -cxF 'SOLEUR_CREDENTIAL_REFUSED script=infra-config-activation-7220 reason=token_shape' "$D/err.txt")" -eq 1 ]]; then
  pass "an uncomputable signature is refused before curl (rc 2, zero calls, the marker once), not skipped silently and not sent unsigned"
else fail "failing python3: rc=$RC calls=$([[ -e "$D/curl.calls" ]] && echo yes || echo none)"; fi

# xtrace with a live credential: refused before anything is expanded into the trace.
D=$(mk_case "$R_OK" "$FRAME_RECONCILED"); FLAGS=(-x); run_case "$D"; FLAGS=()
CASES=$((CASES + 1))
if [[ "$RC" -eq 78 && ! -e "$D/curl.calls" ]] && ! grep -qF "$KEY_V" "$D/out.txt" "$D/err.txt"; then pass "refuses xtrace with a live credential (rc 78, zero calls, the key not on output)"
else fail "xtrace: rc=$RC"; fi

# --- ACCOUNTING CONSERVATION ---------------------------------------------------------------
# Deliberately placed BEFORE the floor. This is the arm that catches a NEUTERED verdict helper,
# and the floor cannot: CASES keeps its full value when fail() is a no-op, so the floor stays
# quiet while the verdicts it was floored on have silently evaporated. Ordering matters because
# a floor reading a verdict-derived counter would otherwise fire first and blame "too few
# assertions" for what is really a discarded verdict.
#
# Every counted case records exactly one verdict, so PASS+FAIL MUST equal CASES. Reported with
# `printf >&2` + `exit 1` DIRECTLY, never through fail() or a bare `FAIL=$((FAIL + 1))`: both
# move the counter the exit status reads, and a check enforced through the suspect cannot
# witness the suspect.
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: PASS+FAIL (%d) != CASES (%d).\n' "$((PASS + FAIL))" "$CASES" >&2
  if [[ $((PASS + FAIL)) -lt "$CASES" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `CASES=$((CASES + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions) ==="
  exit 1
fi

# --- ASSERTION FLOOR ----------------------------------------------------------------------
# Zero headroom, so deleting a case is loud. Ratchet when adding one.
#
# Floored on CASES, not PASS. PASS deflates whenever a verdict is discarded, so a floor on it
# reports a vacuity that did not happen and hides the one that did. CASES moves only with the
# call sites, which is exactly what a floor is about.
#
# Reported directly for the same reason as the conservation check above: the old arm did
# `FAIL=$((FAIL + 1))`, which routes the floor through the very counter a neutered verdict
# helper is corrupting.
ACTIVATION_MIN_ASSERTIONS=25
if [[ "$CASES" -lt "$ACTIVATION_MIN_ASSERTIONS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$CASES" "$ACTIVATION_MIN_ASSERTIONS" >&2
  echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions) ==="
  exit 1
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions) ==="
[[ "$FAIL" -eq 0 ]] || exit 1
