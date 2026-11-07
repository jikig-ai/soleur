#!/usr/bin/env bash
# Harness for betterstack-incident-mirror.sh (#10390 WS1, Guard 1 — mirror filing correctness).
#
# WHAT THE MIRROR IS. It reads `GET uptime.betterstack.com/api/v2/incidents?resolved=false`
# with the read-only token and files/dedupes/auto-resolves `[ci/betterstack-incident]` GitHub
# issues — the channel the operator provably watches (the 2026-10-22 email-only failure). The
# failure this suite exists to stop is threefold: (a) an open incident with NO deduplicated
# issue (silent page), (b) a mirror-filed issue left open after the incident resolved upstream
# (stale alarm), (c) a read failure exiting 0 (silent green — the exact class this mirror
# exists to close). Exit 0 must mean exactly {mirrored, no_incidents}.
#
# DEDUPE KEYS ON THE INCIDENT-ID BODY MARKER, NEVER THE TITLE (#10918). Mirror-filed issues
# carry `<!-- betterstack-incident id=<n> -->`; a human-filed same-TITLE issue with no marker
# is left untouched AND a fresh mirror issue is filed beside it.
#
# RESOLVE IS ORDERED AFTER FILING (order/lifetime — Guard 1 row 3). The resolve pass closes
# mirror-filed open issues whose incident-id the filing pass did not TOUCH this run. A resolve
# that ran before filing would see an empty touched-ledger and close live issues; the harness
# commits that reorder as a mutation and requires it RED.
#
# THE FAKE TREE. The mirror is copied to $root/scripts/; $root/bin holds a stub curl (models
# exactly the incidents GET argv: token on stdin via `--config -`, body to `-o`, http_code on
# stdout) and a stub gh (records every argv line to calls.log, serves `issue list` from a
# fixture, copies `--body-file` payloads to bodies/ before the script's trap deletes them, and
# mints issue URLs). Refusals are logged with status 64 and every case asserts zero of them.
#
# THE INCIDENT FIXTURES CARRY A PING-URL SENTINEL (`SYNTHping9xK`) inside attributes the
# projection must drop; every case sweeps the output, the gh argv log and the copied bodies for
# it and for the token. Values are synthesized (cq-test-fixtures-synthesized-only).
#
# MUTATIONS ARE COMMITTED, NOT HAND-RUN. M1 (empty-list guard dispatch) and M3 (resolve-before-
# file reorder) are applied to scratch copies, asserted to have LANDED inside the target region,
# and expected to red for the predicted reason; known-positive/known-negative runs prove the
# red-detector first. Rows 2, 4, 5, 6 of the Guard-1 matrix are behavioral fixtures; row 7 is
# the label-argv must-PASS that proves the harness sees the filing.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
MIRROR_NAME="betterstack-incident-mirror.sh"
MIRROR_SRC="$HERE/$MIRROR_NAME"
WORKFLOW="$REPO/.github/workflows/scheduled-betterstack-incident-mirror.yml"
TABLE="$REPO/apps/web-platform/server/watchdog-dispatch-table.ts"
MONITORS_TF="$REPO/apps/web-platform/infra/sentry/cron-monitors.tf"

fails=0
passes=0
cases=0
gh_asserts=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$MIRROR_SRC" ]] || { echo "FATAL: mirror not found at $MIRROR_SRC" >&2; exit 1; }

# Canonical guard, copied byte-for-byte from plugins/soleur/test/test-helpers.sh.
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
WORK="$(mktemp -d "${TMPDIR}/betterstack-incident-mirror.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
assert_fixture_dir "$WORK"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/fx" "$WORK/mut"

BASH_BIN="$(type -P bash)"
# ── fabricated identities (synthesized; no live values, cq-test-fixtures-synthesized-only) ────
TOKEN="SYNTHtokenMirrorAbCd0123456789xyz"
GH_TOK="ghp_SYNTHmirror0000000000000000"
REPO_SLUG="synth-org/synth-repo"
RUN_URL="https://github.com/synth-org/synth-repo/actions/runs/4242"
PING_SENT="SYNTHping9xK"
TLS_NAMES="SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS"

# ── fixture builders ──────────────────────────────────────────────────────────────────────────
fx() { cat > "$WORK/fx/$1.json"; printf '%s' "$WORK/fx/$1.json"; }
inc() { # <id> <name> -> one incident object carrying fields the projection MUST drop
  jq -cn --arg id "$1" --arg n "$2" \
    '{id: ($id | tonumber), type: "incident",
      attributes: {name: $n, cause: "heartbeat missed its ping", started_at: "2026-10-22T03:14:00Z",
                   url: ("https://uptime.betterstack.com/incidents/" + $id),
                   ping_url: "https://uptime.betterstack.com/api/v1/heartbeat/SYNTHping9xK",
                   acknowledged_by: {email: "ops@example.com"}, resolved_at: null}}'
}
api_ok() { # incidents on stdin -> {data:[...], pagination:{}}
  jq -cn '{data: [inputs], pagination: {next: null}}'
}
api_paged() { # incidents on stdin -> {data:[...], pagination:{next:URL}}
  jq -cn --arg next "https://uptime.betterstack.com/api/v2/incidents?resolved=false&per_page=50&page=2" \
    '{data: [inputs], pagination: {next: $next}}'
}
issue() { # <number> <title> <body> -> one open-issue object
  jq -cn --argjson n "$1" --arg t "$2" --arg b "$3" '{number: $n, title: $t, body: $b}'
}
mirror_issue() { # <number> <incident-id> <name> -> mirror-filed open issue (marker in body)
  jq -cn --argjson n "$1" --arg id "$2" --arg name "$3" \
    --arg t "[ci/betterstack-incident] $3" \
    '{number: $n, title: $t,
      body: ("## Better Stack incident is open\n\n- **Incident id:** `" + $id + "`\n\n<!-- betterstack-incident id=" + $id + " -->\n")}'
}
degraded_issue() { # <number> -> mirror-filed degraded-class open issue (kind=paged marker)
  jq -cn --argjson n "$1" \
    '{number: $n, title: "[ci/betterstack-incident-mirror] Incident list is paged — mirror read page 1 only",
      body: "## Better Stack incident list is paged\n\n<!-- betterstack-incident-mirror kind=paged -->\n"}'
}
issues_json() { jq -cn '[inputs]'; }

# ── the runner ────────────────────────────────────────────────────────────────────────────────
# Per-case seams (reset_case clears them):
#   C_API     API body file         C_APICODE http code (200|401|500)   C_APIMODE ok|curlfail
#   C_ISSUES  issues.json file      C_GHMODE  ok|listfail               C_TOKEN __unset__|value
#   C_MIRROR  mirror source (default shipped)                          C_XTRACE 1 -> bash -x
#   C_ARGS    argv for the mirror   C_CREATES/C_COMMENTS/C_CLOSES/C_LISTS expected gh calls
reset_case() {
  C_API=""; C_APICODE=200; C_APIMODE="ok"; C_ISSUES=""; C_GHMODE="ok"; C_TOKEN="$TOKEN"
  C_MIRROR="$MIRROR_SRC"; C_XTRACE=0; C_ARGS=""
  C_CREATES=0; C_COMMENTS=0; C_CLOSES=0; C_LISTS=1
}
reset_case

OUT="$WORK/out"
CALLS="$WORK/root/calls.log"
write_stubs() { # <root>
  local root="$1"
  assert_fixture_dir "$root"
  mkdir -p "$root/bin" "$root/scripts" "$root/bodies"
  local t p
  for t in jq date grep sed tr cut head tail sort wc mktemp rm cat cp dirname basename bash env awk paste diff cmp ls; do
    p="$(type -P "$t")" || { echo "FATAL: $t not found" >&2; exit 1; }
    ln -s "$p" "$root/bin/$t"
  done
  cat > "$root/bin/curl" <<STUB
#!$BASH_BIN
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
LOG="\$R/calls.log"
argv="\$*"
stdin="\$(cat)"
tok="\$(cat "\$R/token.txt")"
for n in $TLS_NAMES; do if [ -n "\${!n:-}" ]; then echo "refused env \$n" >> "\$LOG"; exit 64; fi; done
# The ONE request shape: incidents GET with the bearer on stdin config and the body to -o.
out=""; i=0; prev=""
for a in "\$@"; do
  if [[ "\$prev" == "-o" ]]; then out="\$a"; fi
  prev="\$a"
done
case "\$argv" in
  *"--config -"*"uptime.betterstack.com/api/v2/incidents"*) ;;
  *) echo "refused argv" >> "\$LOG"; exit 64 ;;
esac
if [[ "\$stdin" != "header = \"Authorization: Bearer \$tok\"" ]]; then echo "refused api-stdin" >> "\$LOG"; exit 64; fi
if [[ -z "\$out" ]]; then echo "refused no-out" >> "\$LOG"; exit 64; fi
echo api >> "\$LOG"
[[ "\$(cat "\$R/api.mode")" == curlfail ]] && exit 7
cat "\$R/api.body" > "\$out"
printf '%s' "\$(cat "\$R/api.code")"
exit 0
STUB
  chmod +x "$root/bin/curl"
  cat > "$root/bin/gh" <<STUB
#!$BASH_BIN
R="\$(cd "\$(dirname "\$0")/.." && pwd)"
LOG="\$R/calls.log"
printf 'gh %s\n' "\$*" >> "\$LOG"
verb="\${1:-}"; sub="\${2:-}"
# Collect the flag values the harness asserts on; --body is argv, --body-file is copied NOW
# (the script's EXIT trap deletes its temp dir after the call returns).
title=""; bodyfile=""; body=""; comment=""; n_arg=""
prev=""
for a in "\$@"; do
  case "\$prev" in
    --title) title="\$a" ;;
    --body-file) bodyfile="\$a" ;;
    --body) body="\$a" ;;
    --comment) comment="\$a" ;;
  esac
  prev="\$a"
done
case "\$verb \$sub" in
  "issue list")
    if [[ "\$(cat "\$R/gh.mode")" == listfail ]]; then echo "stub gh: list transport failure" >&2; exit 5; fi
    cat "\$R/issues.json"
    exit 0 ;;
  "issue create")
    n="\$(cat "\$R/nextnum")"; echo \$((n + 1)) > "\$R/nextnum"
    if [[ -n "\$bodyfile" ]]; then cp "\$bodyfile" "\$R/bodies/create_\$n.md"; fi
    printf 'https://github.com/%s/issues/%s\n' "$REPO_SLUG" "\$n"
    exit 0 ;;
  "issue comment") exit 0 ;;
  "issue close") exit 0 ;;
  "label create") exit 0 ;;
  *) echo "stub gh: unexpected verb \$verb \$sub" >> "\$LOG"; exit 64 ;;
esac
STUB
  chmod +x "$root/bin/gh"
}

run_mirror() { # -> echoes the status; combined output in $OUT
  local root="$WORK/root" mirror
  mirror="$root/scripts/$MIRROR_NAME"
  case "$root" in "$WORK"/root) rm -rf -- "$root" ;; *) echo 199; return ;; esac
  write_stubs "$root"
  cp "$C_MIRROR" "$mirror"
  : > "$CALLS"
  printf '%s' "$TOKEN" > "$root/token.txt"
  printf '%s' "$C_APIMODE" > "$root/api.mode"
  printf '%s' "$C_APICODE" > "$root/api.code"
  printf '%s' "$C_GHMODE" > "$root/gh.mode"
  printf '41' > "$root/nextnum"
  if [[ -n "$C_API" ]]; then cp "$C_API" "$root/api.body"; else printf '' | api_ok > "$root/api.body"; fi
  if [[ -n "$C_ISSUES" ]]; then cp "$C_ISSUES" "$root/issues.json"; else printf '' | issues_json > "$root/issues.json"; fi
  local -a envv=(PATH="$root/bin" HOME="$HOME" TMPDIR="$TMPDIR"
    GH_TOKEN="$GH_TOK" GH_REPO="$REPO_SLUG" RUN_URL="$RUN_URL")
  [[ "$C_TOKEN" == "__unset__" ]] || envv+=("BETTERSTACK_API_TOKEN_READONLY=$C_TOKEN")
  local -a sh=("$BASH_BIN")
  [[ "$C_XTRACE" == "1" ]] && sh=("$BASH_BIN" -x)
  # shellcheck disable=SC2086
  env -i "${envv[@]}" "${sh[@]}" "$mirror" $C_ARGS >"$OUT" 2>&1
  echo $?
}

markers_of() { grep -oE 'verdict=[a-z_]+' "$OUT" | cut -d= -f2 | paste -sd, - || true; }
count_calls() { { grep -cE "$1" "$CALLS" 2>/dev/null || true; } | head -1; }
count_creates() { count_calls '^gh issue create '; }
count_comments() { count_calls '^gh issue comment '; }
count_closes() { count_calls '^gh issue close '; }
count_lists() { count_calls '^gh issue list '; }

# The generic invariant: exit 0 if and only if the verdict is mirrored or no_incidents.
assert_exit_zero_iff_decided() { # <rc> <verdict-token> <label>
  local good=0
  [[ "$2" == mirrored || "$2" == no_incidents ]] && good=1
  if [[ "$1" == "0" && "$good" != 1 ]] || [[ "$1" != "0" && "$good" == 1 ]]; then
    fail "INVARIANT: rc=$1 with verdict=$2 ($3) — exit 0 must mean exactly {mirrored, no_incidents}"
    return 1
  fi
  return 0
}

expect() { # <name> <rc> <verdict> [extra-token]
  cases=$((cases + 1))
  local name="$1" want="$2" verdict="$3" extra="${4:-}" got ok=1 all
  got="$(run_mirror)"
  [[ -s "$OUT" ]] || { fail "$name — the mirror produced NO output; did it run?"; return; }
  all="$(cat "$OUT")"
  assert_exit_zero_iff_decided "$got" "$verdict" "$name" || return
  [[ "$got" == "$want" ]] || ok=0
  grep -qE "verdict=${verdict}( |\$)" "$OUT" || ok=0
  if [[ -n "$extra" ]] && ! grep -qF -- "$extra" "$OUT"; then
    ok=0; printf '        | missing required token: %s\n' "$extra" >&2
  fi
  local creates comments closes lists refused
  creates="$(count_creates)"; comments="$(count_comments)"; closes="$(count_closes)"; lists="$(count_lists)"
  refused="$(count_calls 'refused')"
  gh_asserts=$((gh_asserts + 1))
  [[ "$creates" != "$C_CREATES" ]] && { ok=0; printf '        | gh issue create: expected %s, saw %s\n' "$C_CREATES" "$creates" >&2; }
  [[ "$comments" != "$C_COMMENTS" ]] && { ok=0; printf '        | gh issue comment: expected %s, saw %s\n' "$C_COMMENTS" "$comments" >&2; }
  [[ "$closes" != "$C_CLOSES" ]] && { ok=0; printf '        | gh issue close: expected %s, saw %s\n' "$C_CLOSES" "$closes" >&2; }
  [[ "$lists" != "$C_LISTS" ]] && { ok=0; printf '        | gh issue list: expected %s, saw %s\n' "$C_LISTS" "$lists" >&2; }
  [[ "$refused" != 0 ]] && { ok=0; printf '        | the stubs REFUSED %s call(s): %s\n' "$refused" "$(grep 'refused' "$CALLS" | paste -sd, -)" >&2; }
  # No token, bearer or ping-URL sentinel anywhere the public channel can see: stdout, the gh
  # argv log, and every copied issue body.
  local s
  for s in "$TOKEN" "$GH_TOK" "$PING_SENT"; do
    if grep -qF -- "$s" <<<"$all" || grep -qF -- "$s" "$CALLS" || grep -rqF -- "$s" "$WORK/root/bodies" 2>/dev/null; then
      ok=0; printf '        | sentinel %s leaked into output, argv log or an issue body\n' "${s:0:12}…" >&2
    fi
  done
  if (( ok )); then
    pass "$name (status $got, verdict $verdict)"
  else
    fail "$name — expected status $want + verdict=$verdict, got status $got [$(markers_of)]"
    sed 's/^/        | /' "$OUT" >&2
    sed 's/^/        | gh: /' "$CALLS" >&2
  fi
}

# ── self-tests of the machinery ───────────────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass "SELFTEST pass() moves its counter"
fail "SELFTEST fail() moves its counter (expected, reversed below)" 2>/dev/null
assert_exit_zero_iff_decided 0 read_failed SELFTEST 2>/dev/null
if (( passes != _p0 + 1 || fails != _f0 + 2 )); then
  echo "FATAL: the verdict helpers do not move their counters — every assertion below is unbacked." >&2
  exit 1
fi
passes=$_p0; fails=$_f0

echo "== private PATH canary =="
cases=$((cases + 1))
reset_case; _c="$(run_mirror)"
if [[ "$(PATH="$WORK/root/bin" type -P curl)" == "$WORK/root/bin/curl" && "$(PATH="$WORK/root/bin" type -P gh)" == "$WORK/root/bin/gh" ]]; then
  pass "canary: curl and gh resolve inside the private PATH"
else fail "canary: curl or gh resolves OUTSIDE the private PATH"; fi
cases=$((cases + 1))
if ! PATH="$WORK/root/bin" type -P nc >/dev/null 2>&1 && ! PATH="$WORK/root/bin" type -P wget >/dev/null 2>&1; then
  pass "canary: no other network client on the private PATH"
else fail "canary: nc or wget is reachable from the private PATH"; fi

echo "== verdict-owning helper controls =="
ctl() { # <label> <needle> <expect args...>
  local label="$1" needle="$2" out nf np
  shift 2
  out="$(expect "$@" 2>&1)"
  nf="$(grep -c '^  FAIL:' <<<"$out" || true)"; np="$(grep -c '^  PASS:' <<<"$out" || true)"
  cases=$((cases + 1))
  if [[ "$nf" -ge 1 && "$np" == 0 ]] && grep -qF -- "$needle" <<<"$out"; then pass "expect() control: $label"
  else fail "expect() control: $label — expected failure(s) ($needle), saw $nf failures / $np passes"; sed 's/^/        | /' <<<"$out" >&2; fi
}
reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx c1)"; C_CREATES=1
ctl "a wrong expected status is a failure" "expected status 3 + verdict=mirrored, got status 0" "x" 3 mirrored
reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx c2)"; C_CREATES=1
ctl "a wrong expected verdict is a failure" "expected status 0 + verdict=no_incidents, got status 0 [mirrored]" "x" 0 no_incidents
reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx c3)"; C_CREATES=1
ctl "a missing required extra token is a failure" "missing required token: NO_SUCH_TOKEN" "x" 0 mirrored "NO_SUCH_TOKEN"
reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx c4)"; C_CREATES=0
ctl "a wrong create-count is a failure" "gh issue create: expected 0, saw 1" "x" 0 mirrored
# A mirror that leaks the token in its marker line must be caught by the sentinel sweep.
M="$WORK/mut/ctl-leak.sh"
sed -E 's/^marker\(\) \{/marker() { printf "%s\\n" "$BETTERSTACK_API_TOKEN_READONLY";/' "$MIRROR_SRC" > "$M"
cases=$((cases + 1))
if ! cmp -s "$MIRROR_SRC" "$M"; then pass "control mutant ctl-leak landed"; else fail "control mutant ctl-leak did NOT land"; fi
reset_case; C_MIRROR="$M"; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx c5)"; C_CREATES=1
ctl "a mirror that prints the token is a failure" "leaked into output, argv log or an issue body" "x" 0 mirrored

echo "== static: exit contract and credential shape =="
allowlist_violations() {
  sed -E 's/^[[:space:]]*#.*$//' "$1" \
    | grep -noE "\bexit\b[[:space:]]*[^[:space:];)'\"]*" \
    | sed -E 's/[[:space:]]+$//' \
    | grep -vE ':exit[[:space:]]+(0|3|4|64|78)$' || true
}
cases=$((cases + 1))
_v="$(allowlist_violations "$MIRROR_SRC")"
if [[ -z "$_v" ]]; then pass "mirror: every exit token is in {0,3,4,64,78}"
else fail "mirror: non-allowlisted exit token(s): $_v"; fi
STRIPPED="$(sed -E 's/^[[:space:]]*#.*$//' "$MIRROR_SRC")"
cases=$((cases + 1))
if grep -qxF 'trap on_exit EXIT' "$MIRROR_SRC" && [[ "$(grep -cE '(^|[;&|[:space:]])trap[[:space:]]' <<<"$STRIPPED" || true)" == 1 ]]; then
  pass "mirror: exactly one trap statement, the EXIT trap"
else fail "mirror: expected exactly one 'trap on_exit EXIT'"; fi
cases=$((cases + 1))
if ! grep -qE '(^|[;&|[:space:](])(exec|kill)([[:space:]]|$)' <<<"$STRIPPED"; then pass "mirror: no exec or kill (both bypass the EXIT trap's remap)"
else fail "mirror: exec/kill found"; fi
cases=$((cases + 1))
if grep -qE '^set -uo pipefail$' "$MIRROR_SRC" && ! grep -qE '^set -e' "$MIRROR_SRC"; then pass "mirror uses set -uo pipefail, never -e"
else fail "mirror must use 'set -uo pipefail' and no -e"; fi
cases=$((cases + 1))
if [[ -x "$MIRROR_SRC" ]]; then pass "mirror is executable"; else fail "mirror is not executable"; fi
cases=$((cases + 1))
if ! grep -q 'rev-parse' "$MIRROR_SRC" && ! grep -qE '(^|[;&|[:space:]])cd\b' "$MIRROR_SRC"; then
  pass "mirror is location-independent (no git rev-parse, no cd — --repo on every gh)"
else fail "mirror must not depend on a repo root or cwd"; fi
cases=$((cases + 1))
if [[ "$(grep -cE '^DECIDED=0$' <<<"$STRIPPED" || true)" == 1 && "$(grep -cE '^[[:space:]]*DECIDED=1$' <<<"$STRIPPED" || true)" == 2 ]] \
   && [[ "$(awk '/^[[:space:]]*DECIDED=1$/{getline n; if (n ~ /^[[:space:]]*exit 0$/) c++} END{print c+0}' <<<"$STRIPPED")" == 2 ]]; then
  pass "DECIDED starts 0, set to 1 at exactly two sites, each directly before exit 0 (selftest + verdict)"
else fail "DECIDED=0 / DECIDED=1 sites changed"; fi
cases=$((cases + 1))
# The token must reach curl through stdin config, never argv: no `-H 'Authorization'` and no
# bare `$BETTERSTACK_API_TOKEN_READONLY` outside the config printf.
if [[ "$(grep -cE '\| curl --disable --noproxy' <<<"$STRIPPED" || true)" -ge 1 ]] \
   && ! grep -qE "curl .*-H ['\"]?Authorization" <<<"$STRIPPED"; then
  pass "every credentialed curl is stdin-config (--config -), no Authorization on argv"
else fail "a credentialed curl does not match the stdin-config shape"; fi
cases=$((cases + 1))
if ! grep -qE 'curl [^|]*\$BETTERSTACK_API_TOKEN_READONLY' <<<"$STRIPPED" \
   && grep -qF 'Authorization: Bearer %s' "$MIRROR_SRC"; then
  pass "the bearer is bound via printf to curl's --config - stdin"
else fail "the bearer reaches curl some other way"; fi
cases=$((cases + 1))
if grep -qE "unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS" "$MIRROR_SRC"; then
  pass "TLS/DNS subversion environment is scrubbed (parity with the feeder)"
else fail "the TLS-subversion scrub is missing"; fi
cases=$((cases + 1))
if grep -qE '\*x\*' "$MIRROR_SRC" && grep -q 'xtrace' "$MIRROR_SRC"; then
  pass "xtrace refusal prologue present (#7797)"
else fail "xtrace refusal missing"; fi

echo "== selftest and usage =="
cases=$((cases + 1))
_t0=$SECONDS
_o="$(env -i PATH=/usr/bin:/bin "$BASH_BIN" "$MIRROR_SRC" --selftest 2>&1)"; _rc=$?
if [[ "$_rc" == 0 && "$_o" == "betterstack-incident-mirror selftest: ok" ]] && (( SECONDS - _t0 < 15 )); then
  pass "--selftest under env -i prints 'betterstack-incident-mirror selftest: ok' inside the 15 s cap"
else fail "--selftest: rc=$_rc output=[$_o]"; fi
cases=$((cases + 1))
# The selftest must touch NO network and NO credential: run it inside the stub tree with the
# token unset and assert the exact line and zero gh/curl calls.
reset_case; C_ARGS="--selftest"; C_TOKEN="__unset__"; C_LISTS=0
_rc="$(run_mirror)"
if [[ "$_rc" == 0 && "$(cat "$OUT")" == "betterstack-incident-mirror selftest: ok" ]] \
   && [[ "$(count_creates)" == 0 && "$(count_calls '^api$')" == 0 ]]; then
  pass "--selftest with no credentials set prints the exact ok line and calls nothing"
else fail "--selftest (no creds): rc=$_rc output=[$(cat "$OUT")]"; fi
reset_case; C_ARGS="--whatever"; C_LISTS=0
expect "any other argument" 64 usage
reset_case; C_ARGS="--selftest extra"; C_LISTS=0
expect "--selftest with an extra argument" 64 usage
reset_case; C_XTRACE=1; C_LISTS=0
expect "traced with a credential set" 78 xtrace_refused

echo "== credential and read failures (never a silent green) =="
reset_case; C_TOKEN="__unset__"; C_LISTS=0
expect "read-only token unset" 3 read_failed "token_unset"
reset_case; C_TOKEN="bad token with spaces"; C_LISTS=0
expect "read-only token malformed" 3 read_failed "token_malformed"
reset_case; C_TOKEN="__unset__"; C_LISTS=0
expect "token unset reaches zero gh calls" 3 read_failed
reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx a401)"; C_APICODE=401; C_LISTS=0
expect "API answers 401" 3 read_failed "http=401"
reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx a500)"; C_APICODE=500; C_LISTS=0
expect "API answers 500" 3 read_failed "http=500"
reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx acf)"; C_APIMODE="curlfail"; C_LISTS=0
expect "API curl fails outright" 3 read_failed "api_unreadable"
reset_case; printf '<html>502 Bad Gateway</html>' > "$WORK/fx/notjson.json"; C_API="$WORK/fx/notjson.json"; C_LISTS=0
expect "API answers a non-JSON body" 3 read_failed "api_malformed"
reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx amis)"; C_GHMODE="listfail"; C_CREATES=0; C_LISTS=1
expect "gh issue list transport failure mid-run (Guard 1 row 5)" 3 read_failed "issues_unreadable"

echo "== filing, dedupe, resolve =="
# Row: open incident -> exactly one issue with the incident-id marker and the three labels.
reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx open1)"; C_CREATES=1; C_LISTS=1
expect "open incident files one issue" 0 mirrored "created=1"
cases=$((cases + 1))
if grep -qE "gh issue create .*--title .?\[ci/betterstack-incident\] soleur-inngest-consumer-prd" "$CALLS" \
   && grep -q 'create_41.md' <(ls "$WORK/root/bodies") 2>/dev/null \
   && grep -qF 'betterstack-incident id=900001' "$WORK/root/bodies/create_41.md" \
   && grep -qF 'soleur-inngest-consumer-prd' "$WORK/root/bodies/create_41.md"; then
  pass "filed body carries the incident-id marker and the monitor name (dedupe key is the marker)"
else fail "filed body missing the id marker or the name"; sed 's/^/        | /' "$WORK/root/bodies/"create_*.md 2>/dev/null >&2; fi
# Guard 1 row 7 (must-PASS): the create argv carries the exact label set, order-insensitive.
cases=$((cases + 1))
_c="$(grep '^gh issue create ' "$CALLS" | head -1)"
if grep -qF -- '--label ci/betterstack-incident' <<<"$_c" && grep -qF -- '--label action-required' <<<"$_c" && grep -qF -- '--label priority/p1-high' <<<"$_c"; then
  pass "row 7: gh issue create carries ci/betterstack-incident + action-required + priority/p1-high"
else fail "row 7: create argv lacks the label set: $_c"; fi

# Row: rerun of the same open incident -> comment, never a duplicate.
reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx open2)" \
  C_ISSUES="$(mirror_issue 41 900001 soleur-inngest-consumer-prd | issues_json | fx iss1)" \
  C_COMMENTS=1; C_CREATES=0
expect "same incident still open: comment on the marker-matched issue" 0 mirrored "commented=1"
cases=$((cases + 1))
if grep -qE '^gh issue comment 41 ' "$CALLS" && grep -qF 'Still open' "$CALLS"; then
  pass "dedupe comments the existing issue by number"
else fail "dedupe did not comment issue 41"; sed 's/^/        | /' "$CALLS" >&2; fi

# Row: resolved incident -> resolve comment + close on the mirror-filed issue only.
reset_case; C_API="$(printf '' | api_ok | fx empty1)" \
  C_ISSUES="$(mirror_issue 42 900002 soleur-inngest-server-prd | issues_json | fx iss2)" \
  C_CLOSES=1; C_CREATES=0
expect "incident resolved upstream: close with a resolved comment" 0 mirrored "resolved=1"
cases=$((cases + 1))
if grep -qE '^gh issue close 42 ' "$CALLS" && grep -qF 'resolved upstream' "$CALLS"; then
  pass "resolve closes the mirror-filed issue with 'resolved upstream'"
else fail "resolve did not close issue 42 with the resolved comment"; sed 's/^/        | /' "$CALLS" >&2; fi

# Guard 1 row 4: a human-filed same-TITLE issue with no marker is untouched; a NEW mirror issue
# is filed beside it (dedupe keys on the body marker, never the title).
reset_case; C_API="$(inc 900003 soleur-inngest-consumer-prd | api_ok | fx open3)" \
  C_ISSUES="$(issue 43 "[ci/betterstack-incident] soleur-inngest-consumer-prd" "Human notes: investigating the heartbeat page." | issues_json | fx iss3)" \
  C_CREATES=1; C_COMMENTS=0; C_CLOSES=0
expect "human same-title issue without the marker: untouched, new mirror issue filed" 0 mirrored "created=1"
cases=$((cases + 1))
if ! grep -qE '^gh issue (comment|close) 43 ' "$CALLS"; then
  pass "row 4: the human issue #43 was never commented or closed"
else fail "row 4: the human issue was touched"; sed 's/^/        | /' "$CALLS" >&2; fi

# Guard 1 row 2: two open incidents on DIFFERENT heartbeats -> two distinct issues.
reset_case; C_API="$( { inc 900004 soleur-inngest-consumer-prd; inc 900005 soleur-inngest-server-prd; } | api_ok | fx two)" \
  C_CREATES=2
expect "two open incidents on different heartbeats: two distinct issues" 0 mirrored "created=2"
cases=$((cases + 1))
if grep -qF 'soleur-inngest-consumer-prd' "$WORK/root/bodies/create_41.md" 2>/dev/null \
   && grep -qF 'soleur-inngest-server-prd' "$WORK/root/bodies/create_42.md" 2>/dev/null; then
  pass "row 2: each incident filed under its own monitor name"
else fail "row 2: the two filings did not carry distinct names"; fi

# Guard 1 row 3 (the fixture the reorder mutation must fail): an open incident with a live
# mirror issue AND a resolved incident's mirror issue — comment the live one, close the stale
# one, create nothing.
reset_case; C_API="$(inc 900010 soleur-inngest-consumer-prd | api_ok | fx open4)" \
  C_ISSUES="$( { mirror_issue 50 900010 soleur-inngest-consumer-prd; mirror_issue 51 900009 soleur-inngest-server-prd; } | issues_json | fx iss4)" \
  C_COMMENTS=1; C_CLOSES=1; C_CREATES=0
expect "row 3 fixture: live incident commented, stale incident resolved, none created" 0 mirrored "resolved=1"
cases=$((cases + 1))
if grep -qE '^gh issue comment 50 ' "$CALLS" && grep -qE '^gh issue close 51 ' "$CALLS" && ! grep -qE '^gh issue close 50 ' "$CALLS"; then
  pass "row 3: the live issue is commented, the stale issue closed, the live one NOT closed"
else fail "row 3 ordering: wrong comment/close pattern"; sed 's/^/        | /' "$CALLS" >&2; fi

# Guard 1 row 6: pagination.next non-null -> annotation emitted AND page 1 processed AND the
# degraded class filed (distinct title from incident class).
reset_case; C_API="$(inc 900006 soleur-inngest-consumer-prd | api_paged | fx paged1)" \
  C_CREATES=2; C_LISTS=1
expect "pagination.next present: annotated, page 1 processed, degraded issue filed" 0 mirrored "paged=1"
cases=$((cases + 1))
if grep -qF '[ci/betterstack-incident-mirror]' "$CALLS"; then
  pass "row 6: the degraded class filed under its own title prefix"
else fail "row 6: no degraded-class filing"; sed 's/^/        | /' "$CALLS" >&2; fi
cases=$((cases + 1))
if grep -qF 'betterstack-incident-mirror kind=paged' "$WORK/root/bodies/create_42.md" 2>/dev/null; then
  pass "row 6: the degraded issue carries the kind=paged marker"
else fail "row 6: degraded body lacks the kind=paged marker"; fi
# P1 regression (review seat): a paged read is a PROVABLE subset only — a mirror issue for a
# page-2 incident must survive the run (resolve is gated on PAGED=0).
reset_case; C_API="$(inc 900006 soleur-inngest-consumer-prd | api_paged | fx paged_live)" \
  C_ISSUES="$(printf '[{"number":77,"title":"[ci/betterstack-incident] soleur-other-prd","body":"<!-- betterstack-incident id=900099 -->"}]' | fx iss_page2)" \
  C_CREATES=2; C_LISTS=1; C_CLOSES=0
expect "paged read: page-2 mirror issue is NOT closed" 0 mirrored "paged=1"
cases=$((cases + 1))
if grep -qF 'issue close 77' "$CALLS" 2>/dev/null || grep -qF '"77"' <(grep 'close' "$CALLS") 2>/dev/null; then
  fail "P1: resolve ran under PAGED=1 and closed a live page-2 mirror issue"; sed 's/^/        | /' "$CALLS" >&2
else pass "P1: page-2 mirror issue survives a paged run"; fi

# pagination cleared -> the degraded issue auto-resolves.
reset_case; C_API="$(printf '' | api_ok | fx clear)" \
  C_ISSUES="$(degraded_issue 44 | issues_json | fx iss5)" \
  C_CLOSES=1
expect "pagination cleared: the degraded issue auto-closes" 0 mirrored "degraded=closed"

# Empty open list AND nothing to resolve -> the explicit no_incidents marker, never a bare 0.
reset_case; C_API="$(printf '' | api_ok | fx empty2)"; C_LISTS=1
expect "no open incidents, nothing stale: no_incidents marker" 0 no_incidents

echo "== workflow step behaviour (the real run: block against a stubbed mirror) =="
WF_RUN="$WORK/wf.run.sh"
python3 - "$WORKFLOW" "$WF_RUN" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
step = [s for s in wf["jobs"]["mirror"]["steps"] if s.get("id") == "mirror"][0]
open(sys.argv[2], "w").write(step["run"])
PY
wf_run() { # <stub body | __missing__> -> WF_RC; $d/out.txt and $d/log.txt hold outputs/log
  local d="$WORK/wf" body="$1"; shift
  assert_fixture_dir "$d"
  case "$d" in "$WORK"/wf) rm -rf -- "$d" ;; *) echo "FATAL: wf dir" >&2; exit 2 ;; esac
  mkdir -p "$d/scripts"
  if [[ "$body" != "__missing__" ]]; then printf '%s\n' "$body" > "$d/scripts/$MIRROR_NAME"; fi
  : > "$d/out.txt"
  WF_RC=0
  ( cd "$d" && env -i PATH="$PATH" HOME="$HOME" GITHUB_OUTPUT="$d/out.txt" "$@" "$BASH_BIN" --noprofile --norc -eo pipefail "$WF_RUN" > "$d/log.txt" 2>&1 ) || WF_RC=$?
}
wf_check() { # <name> <cond-description> <exit-status-of-condition>
  cases=$((cases + 1))
  if [[ "$3" == 0 ]]; then pass "$1: $2"; else fail "$1: $2"; sed 's/^/        | /' "$WORK/wf/log.txt" >&2; fi
}
wf_run 'printf "betterstack-incident-mirror: verdict=mirrored created=1 commented=0 resolved=0 paged=0 degraded=none\n"; echo "MIRRORED: noise line"; exit 0'
wf_check "workflow step, mirrored" "step exits 0 and writes exit_code=0 verdict=mirrored" "$([[ "$WF_RC" == 0 ]] && grep -qx 'exit_code=0' "$WORK/wf/out.txt" && grep -qx 'verdict=mirrored' "$WORK/wf/out.txt"; echo $?)"
wf_check "workflow step, mirrored" "only the marker line is echoed (the summary line is dropped)" "$(grep -q 'verdict=mirrored created=1' "$WORK/wf/log.txt" && ! grep -q 'noise line' "$WORK/wf/log.txt"; echo $?)"
wf_run 'printf "::set-output name=x::y\n"; printf "betterstack-incident-mirror: verdict=read_failed reason=api_http http=401\n"; exit 3'
wf_check "workflow step, read failure" "step exits 0, writes exit_code=3 verdict=read_failed, and a ::error:: annotation" "$([[ "$WF_RC" == 0 ]] && grep -qx 'exit_code=3' "$WORK/wf/out.txt" && grep -qx 'verdict=read_failed' "$WORK/wf/out.txt" && grep -q '^::error::' "$WORK/wf/log.txt"; echo $?)"
wf_check "workflow step, read failure" "a mirror line that starts with :: never reaches the log as a command" "$(! grep -q '^::set-output' "$WORK/wf/log.txt"; echo $?)"
wf_run 'printf "betterstack-incident-mirror: verdict=weird\n"; exit 0'
wf_check "workflow step, exit 0 without a deciding verdict" "an ::error:: annotation, not a notice" "$(grep -q '^::error::' "$WORK/wf/log.txt" && ! grep -q '^::notice::' "$WORK/wf/log.txt"; echo $?)"
wf_run __missing__
wf_check "workflow step, mirror missing" "step exits 0, exit_code=127, verdict=no_marker, and the cause is named in the log" "$([[ "$WF_RC" == 0 ]] && grep -qx 'exit_code=127' "$WORK/wf/out.txt" && grep -qx 'verdict=no_marker' "$WORK/wf/out.txt" && grep -q 'verdict=no_marker rc=127' "$WORK/wf/log.txt"; echo $?)"
wf_run 'printf "betterstack-incident-mirror: verdict=no_incidents \033[31mred\033[0m\n"; exit 0'
wf_check "workflow step, control characters" "an escape sequence in a mirror line is stripped before it is printed" "$(! LC_ALL=C grep -q $'\033' "$WORK/wf/log.txt"; echo $?)"

echo "== mutation runner self-test =="
verdict_holds() { [[ "$1" == "$LAST_RC" ]] && grep -qE "verdict=$2( |\$)" "$OUT"; }
run_case() { LAST_RC="$(run_mirror)"; }
landed_within() { # <orig> <mutant> "<lo>-<hi> ..."
  local hunks
  hunks="$(diff "$1" "$2" | grep -E '^[0-9]' || true)"
  [[ -n "$hunks" ]] || return 1
  awk -v ranges="$3" '
    BEGIN { n = split(ranges, R, " ") }
    { split($0, p, /[acd]/); k = split(p[1], ab, ","); a = ab[1] + 0; b = (k > 1) ? ab[2] + 0 : a
      ok = 0
      for (i = 1; i <= n; i++) { split(R[i], lh, "-"); if (a >= lh[1] + 0 && b <= lh[2] + 0) ok = 1 }
      if (!ok) bad = 1 }
    END { if (bad) print "out" }' <<<"$hunks" | grep -c out >/dev/null && return 1
  return 0
}
fn_range() { awk -v f="$2" '$0 == f "() {" { s = NR } s && !e && NR > s && $0 == "}" { e = NR } END { if (s && e) print s "-" e }' "$1"; }
line_of() { grep -nxF -- "$2" "$1" | cut -d: -f1; }
line_of_sub() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }
MUT_TABLE="$WORK/mutations.tsv"; : > "$MUT_TABLE"
expect_red() { # <row> <name> <orig-rc> <orig-verdict> <mutant-rc> <mutant-verdict>
  cases=$((cases + 1))
  run_case
  local seen; seen="$(markers_of)"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${seen:-none}" "$LAST_RC" >> "$MUT_TABLE"
  if verdict_holds "$3" "$4"; then fail "mutation row $1 ($2) SURVIVED: still status $3 + verdict=$4"
  elif ! verdict_holds "$5" "$6"; then
    fail "mutation row $1 ($2) went red for another reason: status $LAST_RC verdicts [$seen], expected $5 + verdict=$6"
  else pass "mutation row $1 ($2) is RED as predicted: status $LAST_RC, verdicts [$seen]"; fi
}
assert_landed() { # <row> <mutant> <ranges>
  cases=$((cases + 1))
  if landed_within "$MIRROR_SRC" "$2" "$3"; then pass "mutation row $1 landed inside $3"
  else fail "mutation row $1 did NOT land inside $3 — its RED would be vacuous"; fi
}

reset_case; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx kp)"; C_CREATES=1; run_case
cases=$((cases + 1))
if verdict_holds 0 mirrored; then pass "runner known-positive: shipped mirror + open fixture holds"
else fail "runner known-positive: got status $LAST_RC"; fi
reset_case; C_API="$(printf '' | api_ok | fx kn)"; run_case
cases=$((cases + 1))
if ! verdict_holds 0 mirrored; then pass "runner known-negative: an empty list does not read as mirrored"
else fail "runner known-negative: the detector reports mirrored on an empty fixture"; fi

PROJ_LINE="$(line_of_sub "$MIRROR_SRC" 'projected="$(jq -c')"
cases=$((cases + 1))
if [[ -n "$PROJ_LINE" ]]; then pass "mutation seam located (projection line $PROJ_LINE)"
else fail "projection line not found — the M1 mutation would be vacuous"; fi

echo "== committed mutation rows =="
# Guard 1 row 1: the mirror reads an empty incident list while the fixture presents one open
# incident (the guard's own dispatch — a projection that yields nothing).
M="$WORK/mut/m1.sh"; sed -E '/projected="\$\(jq -c/s/\.data\[\]/empty/' "$MIRROR_SRC" > "$M"
assert_landed M1 "$M" "$PROJ_LINE-$PROJ_LINE"
reset_case; C_MIRROR="$M"; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx m1)"; C_CREATES=0
expect_red M1 "projection yields an empty list" 0 mirrored 0 no_incidents
# Guard 1 row 3 (order/lifetime): resolve moved BEFORE the filing pass — the touched-ledger is
# empty, so the still-open incident's mirror issue is closed alongside the stale one. The
# mutant keeps rc 0 + verdict=mirrored, so the RED evidence is the wrongly-closed live issue.
M="$WORK/mut/m3.sh"; sed -e '/resolve_stale_issues; fi$/d' -e 's/^file_open_incidents$/resolve_stale_issues\nfile_open_incidents/' "$MIRROR_SRC" > "$M"
FILE_LINE="$(line_of "$MIRROR_SRC" 'file_open_incidents')"; RES_LINE="$(line_of "$MIRROR_SRC" 'if [[ "$PAGED" -eq 0 ]]; then resolve_stale_issues; fi')"
cases=$((cases + 1))
if [[ -n "$FILE_LINE" && -n "$RES_LINE" ]] && ! cmp -s "$MIRROR_SRC" "$M" \
   && [[ "$(grep -nxF 'resolve_stale_issues' "$M" | head -1 | cut -d: -f1)" -lt "$(grep -nxF 'file_open_incidents' "$M" | head -1 | cut -d: -f1)" ]]; then
  pass "mutation row M3 landed (resolve now precedes filing)"
else fail "mutation row M3 did NOT land as a reorder"; fi
reset_case; C_MIRROR="$M" \
  C_API="$(inc 900010 soleur-inngest-consumer-prd | api_ok | fx m3)" \
  C_ISSUES="$( { mirror_issue 50 900010 soleur-inngest-consumer-prd; mirror_issue 51 900009 soleur-inngest-server-prd; } | issues_json | fx m3iss)"
LAST_RC="$(run_mirror)"
cases=$((cases + 1))
if grep -qE '^gh issue close 50 ' "$CALLS"; then
  printf 'M3\tresolve-before-file reorder\t%s\t%s\n' "$(markers_of)" "$LAST_RC" >> "$MUT_TABLE"
  pass "mutation row M3 is RED as predicted: the reorder closed the LIVE issue (empty touched-ledger)"
else
  fail "mutation row M3 (resolve-before-file) SURVIVED — the live issue was not closed; the ordering is not load-bearing"
  sed 's/^/        | /' "$CALLS" >&2
fi
# Dedupe mutant: the marker requirement dropped from the map build -> every open issue maps an
# empty id -> a rerun creates a duplicate instead of commenting. Same rc/verdict; the RED
# evidence is a `gh issue create` where the shipped mirror comments.
MAP_LINE="$(line_of_sub "$MIRROR_SRC" 'scan("betterstack-incident id=')"
cases=$((cases + 1))
if [[ -n "$MAP_LINE" ]]; then pass "mutation seam located (dedupe map line $MAP_LINE)"
else fail "dedupe map line not found"; fi
M="$WORK/mut/mdedupe.sh"; sed -E 's|scan\("betterstack-incident id=[^)]+"\)|scan(".")|' "$MIRROR_SRC" > "$M"
assert_landed MD "$M" "$MAP_LINE-$MAP_LINE"
reset_case; C_MIRROR="$M"; C_API="$(inc 900001 soleur-inngest-consumer-prd | api_ok | fx md)" \
  C_ISSUES="$(mirror_issue 41 900001 soleur-inngest-consumer-prd | issues_json | fx mdiss)"
LAST_RC="$(run_mirror)"
cases=$((cases + 1))
if [[ "$LAST_RC" == 0 ]] && grep -qE '^gh issue create ' "$CALLS" && ! grep -qE '^gh issue comment ' "$CALLS"; then
  printf 'MD\tdedupe marker requirement dropped\t%s\t%s\n' "$(markers_of)" "$LAST_RC" >> "$MUT_TABLE"
  pass "mutation row MD is RED as predicted: a rerun created a duplicate instead of commenting"
else
  fail "mutation row MD (dedupe-drop) SURVIVED or crashed — rc=$LAST_RC, create/comment pattern wrong"
  sed 's/^/        | /' "$CALLS" >&2
fi
# Pagination mutant (Guard 1 row 6): the pagination.next detection removed -> paged silently
# ignored. Same rc/verdict class; the RED evidence is paged=0 and no degraded-class filing.
PAG_SEAM="$(line_of_sub "$MIRROR_SRC" 'PAGED=0')"
cases=$((cases + 1))
if [[ -n "$PAG_SEAM" ]]; then pass "mutation seam located (PAGED line $PAG_SEAM)"
else fail "PAGED detection line not found"; fi
M="$WORK/mut/mpaged.sh"; sed -E '/then PAGED=1; fi$/d' "$MIRROR_SRC" > "$M"
cases=$((cases + 1))
if ! cmp -s "$MIRROR_SRC" "$M"; then pass "mutation row MP landed"; else fail "pagination mutant did not land"; fi
reset_case; C_MIRROR="$M"; C_API="$(inc 900006 soleur-inngest-consumer-prd | api_paged | fx mp)"
LAST_RC="$(run_mirror)"
cases=$((cases + 1))
if [[ "$LAST_RC" == 0 ]] && ! grep -q 'paged=1' "$OUT" && ! grep -qF '[ci/betterstack-incident-mirror]' "$CALLS"; then
  printf 'MP\tpagination.next detection removed\t%s\t%s\n' "$(markers_of)" "$LAST_RC" >> "$MUT_TABLE"
  pass "mutation row MP is RED as predicted: paged silently ignored (no annotation, no degraded filing)"
else
  fail "mutation row MP SURVIVED or misbehaved — rc=$LAST_RC [$(markers_of)]"
  sed 's/^/        | /' "$CALLS" >&2
fi
# Undecided fall-off: an exit 0 that no verdict produced is remapped to 3, never 0. The
# mutant short-circuits emit_verdict before DECIDED is set.
M="$WORK/mut/falloff.sh"; awk '$0 == "emit_verdict() {" { print; print "  DECIDED=0; exit 0"; next } { print }' "$MIRROR_SRC" > "$M"
if ! cmp -s "$MIRROR_SRC" "$M"; then
  reset_case; C_MIRROR="$M"; C_API="$(printf '' | api_ok | fx fo)"; run_case
  cases=$((cases + 1))
  if [[ "$LAST_RC" == 3 ]] && grep -qE 'verdict=trap_remapped( |$)' "$OUT"; then pass "an undecided exit 0 is remapped to 3 trap_remapped, never 0"
  else fail "undecided exit 0: expected 3 trap_remapped, got $LAST_RC [$(markers_of)]"; fi
else
  cases=$((cases + 1)); fail "falloff mutant did not land"
fi

echo
echo "== measured mutation verdicts (row, edit, verdicts seen, status) =="
sed 's/^/  /' "$MUT_TABLE"

echo "== workflow wiring (parsed) =="
cases=$((cases + 1))
if python3 - "$WORKFLOW" <<'PY'
import sys, yaml, re
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get(True) or wf.get("on")
assert set(on) == {"schedule", "workflow_dispatch"}, "triggers must be exactly schedule + workflow_dispatch: %r" % set(on)
assert on["workflow_dispatch"] in ({}, None), "workflow_dispatch takes no inputs"
assert [c["cron"] for c in on["schedule"]] == ["*/15 * * * *"], "fallback cron"
assert wf["concurrency"]["group"] == "scheduled-betterstack-incident-mirror" and wf["concurrency"]["cancel-in-progress"] is False
assert wf["permissions"] == {"contents": "read", "issues": "write"}
assert "env" not in wf and "env" not in wf["jobs"]["mirror"], "no workflow- or job-level env"
assert wf["jobs"]["mirror"]["timeout-minutes"] == 6
steps = wf["jobs"]["mirror"]["steps"]
mirror = [s for s in steps if s.get("id") == "mirror"][0]
assert "continue-on-error" not in mirror and "if" not in mirror, "the mirror step must not be skippable or tolerated"
assert mirror["env"] == {
    "BETTERSTACK_API_TOKEN_READONLY": "${{ secrets.BETTERSTACK_API_TOKEN_READONLY }}",
    "GH_TOKEN": "${{ github.token }}",
    "GH_REPO": "${{ github.repository }}",
    "RUN_URL": "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}",
}, "the mirror step env must be exactly the token + gh trio + run URL"
run = mirror["run"]
assert "bash scripts/betterstack-incident-mirror.sh" in run, "pattern on a run line"
assert re.search(r'out="\$\(bash scripts/betterstack-incident-mirror\.sh 2>&1\)" \|\| rc=\$\?', run), "|| rc=$? capture"
assert "exit_code=${rc}" in run and 'verdict=${verdict}' in run, "both step outputs are written"
sent = steps[-1]
assert sent["uses"] == "./.github/actions/sentry-heartbeat" and sent["with"]["monitor-slug"] == "scheduled-betterstack-incident-mirror"
want = "${{ (steps.mirror.outputs.exit_code == '0' && (steps.mirror.outputs.verdict == 'mirrored' || steps.mirror.outputs.verdict == 'no_incidents')) && 'ok' || 'error' }}"
assert sent["with"]["status"] == want, "the Sentry status expression must equal the pinned one: %r" % sent["with"]["status"]
assert sent.get("if") == "always()" and sent.get("continue-on-error") is True
PY
then pass "workflow wiring: triggers, concurrency, run line, || rc=\$? capture, Sentry status expression"
else fail "workflow wiring assertions failed"; fi
cases=$((cases + 1))
if [[ "$(grep -cE '^[^#]*bash scripts/betterstack-incident-mirror\.sh' "$WORKFLOW" || true)" == 1 ]]; then
  pass "the mirror run pattern appears once, on the run line"
else fail "the run pattern must appear exactly once outside comments"; fi
cases=$((cases + 1))
if grep -qF 'workflowFile: "scheduled-betterstack-incident-mirror.yml"' "$TABLE" \
   && grep -qF 'monitorSlug: "scheduled-betterstack-incident-mirror"' "$TABLE" \
   && grep -qF 'intervalMinutes: 15' "$TABLE"; then
  pass "a WATCHDOG_DISPATCH_TABLE row exists (workflowFile + monitorSlug + 15-min slot)"
else fail "no dispatch-table row for the workflow"; fi
cases=$((cases + 1))
if grep -qE 'resource "sentry_cron_monitor" "scheduled_betterstack_incident_mirror"' "$MONITORS_TF"; then
  pass "sentry_cron_monitor.scheduled_betterstack_incident_mirror is declared"
else fail "the Sentry monitor resource is missing from cron-monitors.tf"; fi

# ── conservation and the floors ───────────────────────────────────────────────────────────────
echo
echo "=== $passes passed, $fails failed, $cases cases, $gh_asserts gh-call assertions ==="
if (( passes + fails != cases )); then
  printf 'FATAL: verdict conservation violated — %s+%s != %s cases.\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
# A HARD-CODED floor: a runtime-derived one falls when a case is deleted.
MIN_PASSES=60
MIN_GH_ASSERTS=14
if (( passes < MIN_PASSES )); then
  printf 'FATAL: only %s passes, below the floor of %s -- the suite was truncated, so a 0-failure tally proves nothing.\n' "$passes" "$MIN_PASSES" >&2
  exit 1
fi
if (( gh_asserts < MIN_GH_ASSERTS )); then
  printf 'FATAL: only %s gh-call assertions, below the floor of %s.\n' "$gh_asserts" "$MIN_GH_ASSERTS" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
echo "All $cases cases passed."
