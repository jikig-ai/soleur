#!/usr/bin/env bash
# Tests for scripts/sentry-alert-live-fidelity.sh (#7650 §2.9) — the probe that
# notices one of the 28 adopted rules going dark WEEKS after the adopting apply.
#
# THE FAILURE THIS SUITE IS SHAPED AGAINST. A fidelity probe compares a document
# to itself for a living, and the degenerate implementation — return PASS —
# satisfies every happy-path test anyone writes. So the identity case is worth
# exactly one row here; the other rows are one per DRIFT CLASS the probe claims
# to detect, and the claim in its header is only true if each of them reds.
#
# Every mutant is derived from the committed capture by a single scoped `jq`
# edit and is asserted to have LANDED, so no row can report a pass from a
# fixture that differs for some second reason.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/sentry-alert-live-fidelity.sh"
# Tracks the PROBE's production default. Repointed to the Phase 3.4 capture with
# the probe itself (#7985): the 2026-09-04 Phase 2 capture pre-dates
# `git-data-boot-warning`, so a suite pinned to it would assert 27 while the probe
# it tests compares 28 — the suite would go red for the fixture, not the code.
CAPTURE="$REPO_ROOT/knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json"
pass=0; fail=0
# Must equal the number of `t_*` invocations in the call block at the foot of
# this file. Exact equality, not a floor: a floor cannot see a row that stopped
# being invoked.
EXPECTED_TESTS=21

TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

for f in "$PROBE" "$CAPTURE"; do
  [[ -f "$f" ]] || { echo "ERROR: $f does not exist — RED phase expected this." >&2; exit 1; }
done

# _run <live-fixture> — sets the globals $_rc and $_out (stdout+stderr merged).
#
# NOT `rc=$(_run …)`. A command substitution runs in a SUBSHELL, so the callee's
# assignment to `_out` would be discarded and every marker assertion below would
# grep an empty string — reporting "the probe failed to detect" for nine drift
# classes it detects correctly.
_out=""; _rc=0
_run() {
  _rc=0
  _out=$(SENTRY_AUTH_TOKEN=fixture SENTRY_ORG=fixture \
         SENTRY_FIXTURE_RULES="$1" bash "$PROBE" 2>&1) || _rc=$?
}

# _mutant <label> <jq-program> -> path to the mutated live payload.
# Asserts the edit CHANGED the document. A jq filter whose selector no longer
# matches (a renamed rule, a reshaped capture) returns the input unchanged, and
# the row built on it would compare the capture to itself and report the probe
# "failed to detect" — or, worse, pass its identity assertion.
_mutant() {
  # Separate statements, not `local a=$1 b="$TMPD/$a.json"`. Bash declares every
  # name in a `local` list before assigning any of them, so the second
  # expansion sees the *unset local*, not the argument — fatal under `set -u`.
  local label="$1"
  local prog="$2"
  local f="$TMPD/$label.json"
  jq -c "$prog" "$CAPTURE" > "$f" 2>/dev/null || { echo "JQFAIL"; return; }
  if jq -S -c . "$f" | cmp -s - <(jq -S -c . "$CAPTURE"); then
    echo "NOOP"
    return
  fi
  echo "$f"
}

_drift_case() { # $1=label $2=jq-program $3=expected-marker $4=human description
  local f; f=$(_mutant "$1" "$2")
  if [[ "$f" == "JQFAIL" || "$f" == "NOOP" ]]; then
    _report "$4" fail "the mutation did not land ($f) — this row compared the capture to itself and proves nothing"
    return
  fi
  _run "$f"
  if [[ "$_rc" -eq 1 ]] && grep -q "$3" <<<"$_out"; then
    _report "$4" ok
  else
    _report "$4" fail "rc=$_rc (want 1), marker '$3' not found. Output: $(head -c 400 <<<"$_out")"
  fi
}

# F13 — THE LIVE API'S SHAPE, which every other row in this file structurally
# cannot see.
#
# Every fixture here is derived from the committed capture, so both sides of the
# comparison are already normalised and their shapes agree BY CONSTRUCTION. The
# real API does not look like that: it returns server-assigned fields (`id`,
# `conditionResult`, `organizationId` on triggers and conditions;
# `integrationId`, `status` on actions) and does not sort object keys. Measured
# against production on 2026-09-04, the probe reported 38 divergences on a
# completely healthy org — and this probe files a p1 and runs daily, so that is
# a 38-finding false alarm on its first scheduled run and every one after.
#
# This row rebuilds an API-SHAPED payload from the capture — server fields added
# back, key order reversed — and asserts the probe still reports PASS. It is the
# only row that would have caught it.
#
# WHAT IT PINS, precisely: the DEEP KEY CANONICALISATION. Mutation-tested —
# removing `canon` from the projection reds this row. The allowlist projection
# of `actions` does NOT red it, because `integrationId`/`status` are siblings of
# `config`/`data` and a `{type, config, data}` shorthand drops them anyway. The
# allowlist is therefore defence-in-depth against a FUTURE server field landing
# inside `config` or `data`, not something this row proves today. Said plainly so
# nobody reads a green F13 as coverage it does not give.
t_live_api_shape() {
  local shaped="$TMPD/api-shaped.json"
  # Reverse keys RECURSIVELY. The projection REBUILDS the outer objects, so their
  # input key order is irrelevant — but `comparison` is passed through verbatim by
  # the `{type, comparison}` shorthand, so ITS internal order survives into the
  # serialised string the probe compares. That is where the real 11 false
  # findings came from, and a top-level-only reversal reproduces none of it.
  jq -c '
    def deep_reverse_keys:
      walk(if type == "object" then (to_entries | reverse | from_entries) else . end);
    def add_server:
      walk(if type == "object" and has("type")
           then . + {id: "9999", conditionResult: true}
           else . end);
    map(
      add_server
      | .triggers += {id: "8888", organizationId: "1"}
      | .actionFilters = [ .actionFilters[] | .actions = [ .actions[] | . + {integrationId: null, status: "active"} ] ]
      | deep_reverse_keys
    )
  ' "$CAPTURE" > "$shaped" 2>/dev/null

  if [[ ! -s "$shaped" ]] || ! jq -e 'length == 31' "$shaped" >/dev/null 2>&1; then
    _report "F13 an API-shaped payload (server fields + unsorted keys) still PASSES" fail \
      "the shaped fixture was not built — this row proves nothing"
    return
  fi
  # Landing assert 1: it must differ from the capture as RAW BYTES (server fields
  # and key order), or it is the identity case F1 already covers.
  if jq -c . "$shaped" | cmp -s - <(jq -c . "$CAPTURE"); then
    _report "F13 an API-shaped payload still PASSES" fail \
      "the shaped fixture is byte-identical to the capture"
    return
  fi
  # Landing assert 2: it must be SEMANTICALLY equal (same data, different shape).
  # Without this the row could pass by feeding the probe genuinely different data.
  # Scoped to `triggers` and `actionFilters` ONLY. A blanket `del(.id, …)` also
  # strips each RULE's real workflow id (e.g. "566201"), which the capture
  # legitimately carries — so the two sides would differ for a reason that has
  # nothing to do with the shape under test. (This assert caught that in its own
  # first draft.)
  if ! jq -S -c 'map(
         .triggers      |= walk(if type=="object" then del(.id,.conditionResult,.organizationId) else . end)
       | .actionFilters |= walk(if type=="object" then del(.id,.conditionResult,.organizationId,.integrationId,.status) else . end)
       )' "$shaped" \
       | cmp -s - <(jq -S -c . "$CAPTURE"); then
    _report "F13 an API-shaped payload still PASSES" fail \
      "the shaped fixture is not semantically identical to the capture — it changes DATA, not just SHAPE, so a RED would not mean what this row claims"
    return
  fi

  _run "$shaped"
  if [[ "$_rc" -eq 0 ]] && grep -q 'in-scope rules match' <<<"$_out"; then
    _report "F13 an API-shaped payload (server fields + unsorted keys) still PASSES" ok
  else
    _report "F13 an API-shaped payload still PASSES" fail \
      "rc=$_rc — the projection is not normalising both sides, so the probe would open a false p1 on its first real run. Output: $(head -c 300 <<<"$_out")"
  fi
}

# ── The identity row. ONE row, because it is the one a broken probe passes. ──
t_identity_passes() {
  _run "$CAPTURE"
  if [[ "$_rc" -eq 0 ]] && grep -q 'all 28 in-scope rules match' <<<"$_out"; then
    _report "F1 live == capture PASSES, and reports having compared all 28" ok
  else
    _report "F1 live == capture passes over all 28" fail "rc=$_rc; output: $(head -c 300 <<<"$_out")"
  fi
}

# ── One row per drift class the header claims. ─────────────────────────────
t_deleted() {
  _drift_case deleted 'map(select(.name != "byok-art-33-breach"))' 'DELETED or RENAMED' \
    "F2 a DELETED rule is detected (byok-art-33-breach — the GDPR Art. 33 control)"
}

# Anchored on the FINDING, not the token. The probe's epilogue prints "DISABLED
# and MONITOR UNBIND are live state an apply will not touch" on every failing
# run, and `enabled` ALSO reds through the generic per-field loop as
# `DRIFT: '…'.enabled` — so suppressing the dedicated DISABLED finding left this
# row green while the classification silently changed. That is not cosmetic: the
# drift issue routes DRIFT to "re-run the apply" and DISABLED to "an apply will
# NOT fix this", so a misclassified UI mute sends the operator down the wrong
# path. Verified by the review's mutation battery.
t_disabled() {
  _drift_case disabled 'map(if .name=="byok-art-33-breach" then .enabled=false else . end)' \
    "DISABLED: 'byok-art-33-breach'" \
    "F3 a rule muted in the UI is detected AND classified as DISABLED, not DRIFT"
}

t_detector_unbind() {
  _drift_case unbind 'map(if .name=="byok-art-33-breach" then .detectorIds=["9999999"] else . end)' 'MONITOR UNBIND' \
    "F4 a detector REBIND is detected (the rule watches nothing while looking healthy)"
}

t_detector_empty() {
  _drift_case unbind0 'map(if .name=="byok-art-33-breach" then .detectorIds=[] else . end)' 'MONITOR UNBIND' \
    "F5 a detector UNBIND to the empty set is detected"
}

t_logictype_flip() {
  _drift_case logicflip 'map(if .name=="byok-art-33-breach" then .triggers.logicType="all" else . end)' 'LOGICTYPE FLIP' \
    "F6 a triggers.logicType flip is detected"
}

# The narrow one. A renamed tag key leaves the rule present, enabled, bound and
# planning clean — and matching nothing. It is the reason this probe compares
# fields rather than existence.
t_tagged_event_key_drift() {
  _drift_case tagkey \
    'map(if .name=="byok-art-33-breach" then .actionFilters[0].conditions[0].comparison.key="renamed" else . end)' \
    'comparison.key' \
    "F7 a renamed tagged_event KEY is detected, and the finding names the leaf path"
}

t_comparison_value_drift() {
  _drift_case cmpvalue \
    'map(if .name=="auth-signout-burst" then .triggers.conditions[0].comparison.value=999 else . end)' \
    'comparison.value' \
    "F8 a changed comparison.value is detected"
}

t_comparison_interval_drift() {
  _drift_case cmpinterval \
    'map(if .name=="auth-signout-burst" then .triggers.conditions[0].comparison.interval="1h" else . end)' \
    'comparison.interval' \
    "F9 a changed comparison.interval is detected"
}

# The other direction. A live in-scope rule the capture never saw is one nothing
# in this repo manages, and regenerating from the capture would not produce it.
t_unmanaged_new_rule() {
  _drift_case unmanaged \
    '. + [{"name":"created-in-the-ui","enabled":true,"detectorIds":["1213799"],"environment":null,"id":"999999","config":{"frequency":5},"triggers":{"logicType":"any-short","conditions":[{"type":"first_seen_event","comparison":true}],"actions":[]},"actionFilters":[]}]' \
    'UNMANAGED' \
    "F10 an in-scope live rule absent from the capture is reported as UNMANAGED"
}

# ── Anti-vacuity: the probe must refuse to certify having checked nothing. ──
t_empty_capture_refuses() {
  local cap="$TMPD/empty-capture.json"
  printf '[]' > "$cap"
  local rc=0
  local out
  out=$(SENTRY_AUTH_TOKEN=fixture SENTRY_ORG=fixture \
        SENTRY_CAPTURE_FILE="$cap" SENTRY_FIXTURE_RULES="$CAPTURE" bash "$PROBE" 2>&1) || rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'ZERO in-scope rules' <<<"$out"; then
    _report "F11 a capture yielding zero in-scope rules REFUSES to report a clean verdict" ok
  else
    _report "F11 a capture yielding zero in-scope rules refuses" fail \
      "rc=$rc (want 1); output: $(head -c 300 <<<"$out")"
  fi
}

# The two survivors must NOT be in scope. If the predicate ever widened to
# include them, this probe would alarm forever on rules it was never meant to
# cover — and the operator would mute it.
t_survivors_out_of_scope() {
  _run "$CAPTURE"
  local names_ok=1
  # 31 live workflows, 28 in scope: the vendor default plus the two carrying
  # `event_unique_user_frequency_count` are excluded by the predicate, not by a
  # name list. Assert the COUNT and that neither survivor is named in a finding.
  grep -q 'comparing 28 captured in-scope rule' <<<"$_out" || names_ok=0
  if [[ "$_rc" -eq 0 && "$names_ok" -eq 1 ]]; then
    _report "F12 scope is 28: the vendor default and the two survivors are excluded by predicate" ok
  else
    _report "F12 scope is 28, survivors excluded" fail \
      "rc=$_rc; expected 'comparing 28 captured in-scope rule' in: $(head -c 300 <<<"$_out")"
  fi
}

# ── Transport confinement + destination pinning (#7997). ───────────────────
# These four rows run NON-FIXTURE on purpose. `fetch_rules()` short-circuits on
# SENTRY_FIXTURE_RULES *before* it reads SENTRY_API_HOST, so a fixture-mode row
# asserts exactly nothing about the host adjudication — it would pass against a
# script with no adjudication at all. The stub `curl` on PATH is what makes a
# live-path run hermetic.
_stub_curl_dir() {
  local d="$TMPD/stub.$1"
  mkdir -p "$d"
  cat > "$d/curl" <<'STUB'
#!/usr/bin/env bash
: > "$STUB_ARGV"
for a in "$@"; do printf '%s\n' "$a" >> "$STUB_ARGV"; done
printf '%s\n' "${SSLKEYLOGFILE-<unset>}" > "$STUB_ENV"
printf '[]'
STUB
  chmod +x "$d/curl"
  printf '%s' "$d"
}

# _run_live <name> [env assignments...] -> _rc, _out, and $_argv / $_envf paths.
_run_live() {
  local name="$1"; shift
  local d; d=$(_stub_curl_dir "$name")
  _argv="$TMPD/$name.argv"; _envf="$TMPD/$name.env"
  : > "$_argv"; : > "$_envf"
  _rc=0
  _out=$(env -u SENTRY_FIXTURE_RULES \
           PATH="$d:$PATH" STUB_ARGV="$_argv" STUB_ENV="$_envf" \
           SENTRY_AUTH_TOKEN=fixture \
           "$@" bash "$PROBE" 2>&1) || _rc=$?
}

t_hostile_host_refused() {
  # Table-driven over all four hosts. attacker.tld is the obvious arm; the three
  # NEAR-MISSES are the ones that matter, because they authenticate and then
  # silently grade a different tenant -- ADR-031 records eu.sentry.io rewriting
  # slugs ending in `-eu`. A single-arm row would pass against an implementation
  # that only rejects unknown TLDs.
  local h bad=0 detail=""
  for h in attacker.tld eu.sentry.io de.sentry.io sentry.io; do
    _run_live "hostilehost.${h//./_}" SENTRY_ORG=jikigai-eu SENTRY_API_HOST="$h"
    if [[ "$_rc" -ne 2 ]] || ! grep -q 'refusing destination host' <<<"$_out" \
       || [[ -s "$_argv" ]]; then
      bad=$((bad + 1))
      detail+=" [$h rc=$_rc argv-bytes=$(wc -c <"$_argv")]"
    fi
  done
  if [[ "$bad" -eq 0 ]]; then
    _report "F14 all four non-pinned hosts REFUSED before any request (incl. the 3 near-misses)" ok
  else
    _report "F14 hostile SENTRY_API_HOST is refused" fail \
      "$bad of 4 arms wrong:$detail"
  fi
}

# --- F19/F20: the plan required these and they were not written. ---
t_org_locale_independent() {
  # M23 measured that without the subshell LC_ALL=C pin the a-z0-9 ranges admit
  # ~1,162 non-ASCII characters under a UTF-8 locale -- i.e. the guard is weaker
  # on the operator's laptop than in CI. Assert BOTH locales refuse.
  local lc bad=0 detail=""
  for lc in C en_US.UTF-8; do
    _run_live "loc.${lc//./_}" LC_ALL="$lc" LANG="$lc" \
      SENTRY_ORG='jikigaí' SENTRY_API_HOST=jikigai-eu.sentry.io
    if [[ "$_rc" -ne 2 ]] || ! grep -q 'refusing org' <<<"$_out"; then
      bad=$((bad + 1)); detail+=" [LC_ALL=$lc rc=$_rc]"
    fi
  done
  if [[ "$bad" -eq 0 ]]; then
    _report "F19 a non-ASCII org is refused under BOTH LC_ALL=C and en_US.UTF-8" ok
  else
    _report "F19 org refusal is locale-independent" fail "$bad of 2 locales wrong:$detail"
  fi
}

t_org_length_boundary() {
  # RFC 1035 sec 2.3.4: 63 octets. The regex is ^[a-z0-9][a-z0-9-]{0,62}$ -- one
  # leading char plus 62 = 63. Pin both sides of the boundary; an off-by-one here
  # either rejects a legitimate org or admits an over-long label.
  local ok63 rej64
  _run_live len63 SENTRY_ORG="a$(printf 'b%.0s' $(seq 62))" SENTRY_API_HOST=x.sentry.io
  ok63=$_rc; local out63="$_out"
  _run_live len64 SENTRY_ORG="a$(printf 'b%.0s' $(seq 63))" SENTRY_API_HOST=x.sentry.io
  rej64=$_rc
  # 63 must pass the ORG gate (it then fails the HOST gate, which is fine --
  # what matters is that it did not fail for being too long).
  if ! grep -q 'refusing org' <<<"$out63" && [[ "$rej64" -eq 2 ]]; then
    _report "F20 a 63-octet org slug passes the shape gate and a 64-octet one is refused" ok
  else
    _report "F20 org length boundary is 63/64" fail \
      "63-char refused-as-org=$(grep -c 'refusing org' <<<"$out63"); 64-char rc=$rej64 (want 2)"
  fi
}

t_hostile_org_refused() {
  # One member per forbidden character CLASS, so a partial widening of the regex
  # cannot survive. The original single fixture used '@evil.tld/x' -- and '@' is
  # outside even a widened [a-z0-9./-] class, so it could not discriminate:
  # measured, widening the class to admit '.' and '/' left the suite 20/20 green.
  # The org is interpolated into `organizations/${SENTRY_ORG}/`, so '/' is path
  # injection on a URL that carries the bearer.
  local o bad=0 detail=""
  for o in '@evil.tld/x' 'jikigai.evil.tld' 'jikigai/../../evil' 'jikigai%2fx' 'JIKIGAI' '-leading' ''; do
    # The HOST is derived from the org so the host pin CANNOT be what refuses --
    # otherwise this row short-circuits on a different guard than the one it
    # names. Measured: with a fixed host, widening the org class left this row
    # green because the singleton case stopped matching and refused first.
    _run_live "hostileorg.$bad" SENTRY_ORG="$o" SENTRY_API_HOST="${o}.sentry.io"
    if [[ "$_rc" -eq 0 ]] || [[ -s "$_argv" ]]; then
      bad=$((bad + 1)); detail+=" [org='$o' rc=$_rc argv-bytes=$(wc -c <"$_argv")]"
    fi
  done
  if [[ "$bad" -eq 0 ]]; then
    _report "F15 every non-RFC-1035 org shape is REFUSED before any request" ok
  else
    _report "F15 hostile SENTRY_ORG is refused" fail "$bad shape(s) reached the wire:$detail"
  fi
}

t_transport_flags_first() {
  _run_live flags SENTRY_ORG=jikigai-eu SENTRY_API_HOST=jikigai-eu.sentry.io
  # Position is the whole property: --disable aborts ~/.curlrc parsing and is a
  # no-op anywhere but first.
  local a1 a2 a3 a4
  a1=$(sed -n '1p' "$_argv"); a2=$(sed -n '2p' "$_argv")
  a3=$(sed -n '3p' "$_argv"); a4=$(sed -n '4p' "$_argv")
  if [[ "$a1" == "--disable" && "$a2" == "--noproxy" && "$a3" == '*' \
        && "$a4" == "--proto" ]] && grep -qx -- '=https' "$_argv" && grep -qx -- '-g' "$_argv"; then
    _report "F16 the credentialed curl is transport-confined, flags FIRST" ok
  else
    _report "F16 transport flags are first" fail \
      "argv[1..4]=[$a1 $a2 $a3 $a4]; want [--disable --noproxy * --proto]. Full argv: $(head -c 300 "$_argv" | tr '\n' ' ')"
  fi
}

t_transport_not_reopened_by_suffix() {
  # F16 pins a PREFIX. A prefix pin cannot express the property, which is "no
  # argument RE-OPENS what the prefix closed" -- measured: appending
  # `--proxy http://exfil.tld:8080 -k` to the pinned call site kept F16 green and
  # the whole suite at 20/20, while sending the bearer through an attacker proxy
  # with certificate verification off. The suffix is the half nobody asserts, so
  # assert it as a NEGATIVE over the WHOLE argv (ADR-193): name the values that
  # must never appear rather than the ones expected to.
  _run_live suffix SENTRY_ORG=jikigai-eu SENTRY_API_HOST=jikigai-eu.sentry.io
  local a bad="" n_noproxy=0 n_proto=0
  while IFS= read -r a; do
    case "$a" in
      # re-opens proxying, which --noproxy '*' closed
      -x|--proxy|--proxy1.0|--preproxy|--socks4|--socks4a|--socks5 \
        |--socks5-hostname|--socks5-basic|--socks5-gssapi) bad+=" $a" ;;
      # re-reads a config file, which --disable aborted
      -K|--config) bad+=" $a" ;;
      # widens the protocol set, which --proto '=https' closed
      --proto-default|--proto-redir) bad+=" $a" ;;
      # re-points the destination behind the host pin (Host header preserved)
      --resolve|--connect-to|--unix-socket|--abstract-unix-socket|--url) bad+=" $a" ;;
      # weakens or re-anchors TLS, or leaks the bearer across a redirect
      -k|--insecure|--proxy-insecure|--ssl-no-revoke|--cacert|--capath \
        |--doh-url|--doh-insecure|--location-trusted) bad+=" $a" ;;
      # re-enables glob interpretation of the URL, which -g closed
      --no-globoff) bad+=" $a" ;;
    esac
    [[ "$a" == "--noproxy" ]] && n_noproxy=$((n_noproxy + 1))
    [[ "$a" == "--proto"   ]] && n_proto=$((n_proto + 1))
  done < "$_argv"
  # A SECOND --noproxy/--proto silently overrides the first; one occurrence each
  # is the only shape in which the prefix pin means anything.
  [[ "$n_noproxy" -eq 1 ]] || bad+=" --noproxy x${n_noproxy}"
  [[ "$n_proto"   -eq 1 ]] || bad+=" --proto x${n_proto}"
  if [[ -z "$bad" && -s "$_argv" ]]; then
    _report "F21 no later argument re-opens the transport the prefix closed" ok
  else
    _report "F21 the argv SUFFIX re-opens confinement" fail \
      "offending token(s):${bad:-<none>}; argv-bytes=$(wc -c <"$_argv"). Full argv: $(head -c 300 "$_argv" | tr '\n' ' ')"
  fi
}

t_resolver_env_scrubbed() {
  _run_live scrub SENTRY_ORG=jikigai-eu SENTRY_API_HOST=jikigai-eu.sentry.io \
    SSLKEYLOGFILE=/tmp/should-not-survive
  # --noproxy and a host pin do not touch the resolver or the trust anchor;
  # the prologue is what closes them, and only the child can testify.
  if grep -qx '<unset>' "$_envf"; then
    _report "F17 resolver / trust-anchor / keylog env is scrubbed before the request" ok
  else
    _report "F17 resolver env is scrubbed" fail \
      "the child saw SSLKEYLOGFILE=$(cat "$_envf") — the unset prologue did not run"
  fi
}

t_fixture_mode_still_passes() {
  # The guards must not break the path the other 13 rows exercise.
  _run "$CAPTURE"
  if [[ "$_rc" -eq 0 ]] && grep -q 'all 28 in-scope rules match' <<<"$_out"; then
    _report "F18 fixture mode still PASSES with the guards in place" ok
  else
    _report "F18 fixture mode still passes" fail "rc=$_rc; output: $(head -c 300 <<<"$_out")"
  fi
}

t_identity_passes
t_live_api_shape
t_deleted
t_disabled
t_detector_unbind
t_detector_empty
t_logictype_flip
t_tagged_event_key_drift
t_comparison_value_drift
t_comparison_interval_drift
t_unmanaged_new_rule
t_empty_capture_refuses
t_survivors_out_of_scope
t_hostile_host_refused
t_hostile_org_refused
t_transport_flags_first
t_transport_not_reopened_by_suffix
t_resolver_env_scrubbed
t_fixture_mode_still_passes
t_org_locale_independent
t_org_length_boundary

echo "=== $pass passed, $fail failed ==="

# HARNESS SELF-TEST. EXPECTED_TESTS catches a row that stopped being INVOKED; it
# is blind to a row that stopped DISCRIMINATING -- measured, making _report's FAIL
# branch increment `pass` left this suite 18/18 green with `ran` conserved.
_h_p=$pass; _h_f=$fail
{ _report "harness self-test (unwound)" ok; _report "harness self-test (unwound)" fail "x"; } >/dev/null 2>&1
if [[ "$pass" -ne $((_h_p + 1)) || "$fail" -ne $((_h_f + 1)) ]]; then
  printf 'FATAL: _report cannot conclude — pass %s->%s (want +1), fail %s->%s (want +1).\n' \
    "$_h_p" "$pass" "$_h_f" "$fail" >&2
  exit 1
fi
pass=$_h_p; fail=$_h_f

ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS — a suite that silently stops running its assertions reports green" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]
