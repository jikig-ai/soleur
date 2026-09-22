#!/usr/bin/env bash
# Tests for scripts/sentry-alert-live-fidelity.sh (#7650 §2.9) — the probe that
# notices a declared `sentry_alert` going dark WEEKS after the adopting apply.
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
PROJ="$REPO_ROOT/tests/scripts/lib/sentry-alert-projection.jq"
# THE FROZEN LIVE FIXTURE. Since #8050 the probe's production reference is
# `apps/web-platform/infra/sentry/alert-reference.json` (a projection of the
# Terraform plan), not this capture. The capture stays here as the LIVE side of
# every row — fixtures may be frozen — and the suite's reference is DERIVED from
# it at start (below), so the two sides agree by construction and each drift
# row is a single scoped edit to one of them. 28 in-scope rules is therefore a
# fixture constant, not a claim about production.
CAPTURE="$REPO_ROOT/knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json"
COMMITTED_REF="$REPO_ROOT/apps/web-platform/infra/sentry/alert-reference.json"
pass=0; fail=0
EXPECTED_TESTS=59

export TMPDIR="${TMPDIR:-/var/tmp}"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

for f in "$PROBE" "$CAPTURE" "$PROJ" "$COMMITTED_REF"; do
  [[ -f "$f" ]] || { echo "ERROR: $f does not exist — RED phase expected this." >&2; exit 1; }
done

# The suite's reference: the capture pushed through the LIVE side of the module
# and then the REFERENCE side, exactly as production data would be. Non-vacuity
# on the derivation itself, and N is COMPUTED, never typed.
REFERENCE="$TMPD/reference.json"
jq --arg side live -f "$PROJ" "$CAPTURE" | jq -S --arg side reference -f "$PROJ" > "$REFERENCE" \
  || { echo "ERROR: could not derive the suite reference from the capture." >&2; exit 1; }
N=$(jq 'length' "$REFERENCE")
[[ "$N" =~ ^[0-9]+$ && "$N" -gt 0 ]] || { echo "ERROR: the derived reference holds $N rules." >&2; exit 1; }

# _run <live-fixture> — sets the globals $_rc and $_out (stdout+stderr merged).
#
# NOT `rc=$(_run …)`. A command substitution runs in a SUBSHELL, so the callee's
# assignment to `_out` would be discarded and every marker assertion below would
# grep an empty string — reporting "the probe failed to detect" for nine drift
# classes it detects correctly.
# `SENTRY_REFERENCE_FILE` points at the derived reference; a second argument
# overrides it for the reference-side rows.
_out=""; _rc=0
_run() {
  _rc=0
  _out=$(SENTRY_AUTH_TOKEN=fixture SENTRY_ORG=fixture \
         SENTRY_REFERENCE_FILE="${2:-$REFERENCE}" \
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
# A WIRING test: the reference is derived from the capture two lines above, so
# this proves the probe reads both sides through the module and prints the
# fixture-mode verdict with the computed count — nothing about production.
t_identity_passes() {
  _run "$CAPTURE"
  local want="PASS (FIXTURE — not live) (all ${N} in-scope rules match the committed reference field-for-field)"
  if [[ "$_rc" -eq 0 ]] && grep -qF -- "$want" <<<"$_out"; then
    _report "F1 live == derived reference PASSES with the FIXTURE token and the computed count (${N})" ok
  else
    _report "F1 live == derived reference passes (wiring)" fail "rc=$_rc; want '$want'; output: $(head -c 300 <<<"$_out")"
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
# The complement of F3: a rule the ROOT declares `enabled = false` and live holds
# disabled is in its desired state and must NOT be reported DISABLED (which would
# red every apply and every daily run for as long as the declaration stands — the
# #8050 shape one attribute over). Built by deriving a reference from a capture
# whose byok-art-33-breach is disabled, then probing that same disabled live copy.
t_declared_disabled_is_not_a_finding() {
  local f; f=$(_mutant decldisabled 'map(if .name=="byok-art-33-breach" then .enabled=false else . end)')
  if [[ "$f" == "JQFAIL" || "$f" == "NOOP" ]]; then _report "F34 declared-disabled rule is not DISABLED" fail "the mutation did not land ($f)"; return; fi
  local r="$TMPD/decldisabled.reference.json"
  jq --arg side live -f "$PROJ" "$f" | jq -S --arg side reference -f "$PROJ" > "$r" || { _report "F34 declared-disabled rule is not DISABLED" fail "could not derive the reference"; return; }
  jq -e '."byok-art-33-breach".enabled == false' "$r" >/dev/null || { _report "F34 declared-disabled rule is not DISABLED" fail "derived reference does not carry enabled:false"; return; }
  _run "$f" "$r"
  if [[ "$_rc" -eq 0 ]] && grep -q 'live fidelity: PASS' <<<"$_out" && ! grep -q 'DISABLED:' <<<"$_out"; then
    _report "F34 a rule declared enabled=false and live-disabled PASSES with no DISABLED finding (DISABLED is judged against the declared value)" ok
  else
    _report "F34 declared-disabled rule is not DISABLED" fail "rc=$_rc (want 0); DISABLED $(grep -q 'DISABLED:' <<<"$_out" && echo present || echo absent). Output: $(head -c 300 <<<"$_out")"
  fi
}
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
    "F6 a THREE-trigger rule's logicType flip (any-short → all) is detected — the pair of F26"
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
    "UNMANAGED: 'created-in-the-ui' is live and in scope but declared nowhere" \
    "F10 an in-scope live rule absent from the reference is reported as UNMANAGED (= undeclared)"
}

# ── Anti-vacuity: the probe must refuse to certify having checked nothing. ──
# `{}` passes the module's shape floor (shape is not cardinality), so this row
# reaches the probe's OWN zero-rules floor rather than the module's — the two
# floors are distinct and each has its row (see F23 for the shape floor).
t_empty_reference_refuses() {
  local ref="$TMPD/empty-reference.json"
  printf '{}' > "$ref"
  _run "$CAPTURE" "$ref"
  if [[ "$_rc" -eq 1 ]] && grep -q 'ZERO in-scope rules' <<<"$_out" && ! grep -q 'live fidelity: PASS' <<<"$_out"; then
    _report "F11 a reference holding zero rules REFUSES to report a clean verdict (never PASS (all 0)" ok
  else
    _report "F11 a zero-rule reference refuses" fail \
      "rc=$_rc (want 1); output: $(head -c 300 <<<"$_out")"
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
  grep -q 'comparing 28 declared rule' <<<"$_out" || names_ok=0
  if [[ "$_rc" -eq 0 && "$names_ok" -eq 1 ]]; then
    _report "F12 scope is 28: the vendor default and the two survivors are excluded by predicate" ok
  else
    _report "F12 scope is 28, survivors excluded" fail \
      "rc=$_rc; expected 'comparing 28 declared rule' in: $(head -c 300 <<<"$_out")"
  fi
}

# ── #8050 rows — the reference side, the pins, and the normalisations. ────────

# (b) The reverse direction from the REFERENCE side: a rule the reference lacks
# is undeclared to the probe even though live has it.
t_reference_minus_one_rule() {
  local ref="$TMPD/ref-minus-one.json"
  jq 'del(.["auth-signout-burst"])' "$REFERENCE" > "$ref"
  jq -e 'has("auth-signout-burst") | not' "$ref" >/dev/null || { _report "F22 reference minus one rule" fail "mutation did not land"; return; }
  _run "$CAPTURE" "$ref"
  if [[ "$_rc" -eq 1 ]] && grep -qF -- "UNMANAGED: 'auth-signout-burst'" <<<"$_out"; then
    _report "F22 a rule removed from the reference is reported UNMANAGED (the live side still has it)" ok
  else
    _report "F22 reference minus one rule → UNMANAGED" fail "rc=$_rc; output: $(head -c 300 <<<"$_out")"
  fi
}

# (c) An API-shaped capture handed to the probe AS THE REFERENCE — the exact
# mistake a reader of the old capture-file override contract would make.
t_capture_as_reference_refused() {
  _run "$CAPTURE" "$CAPTURE"
  if [[ "$_rc" -eq 1 ]] && grep -q 'not a name-indexed projection object' <<<"$_out" && ! grep -q 'live fidelity: PASS' <<<"$_out"; then
    _report "F23 an API-shaped capture passed as the reference is refused at the shape floor, before any comparison" ok
  else
    _report "F23 capture-as-reference refused" fail "rc=$_rc; output: $(head -c 300 <<<"$_out")"
  fi
}

# (j) The shape floor at the leaf: one rule missing one required key.
t_reference_missing_key_refused() {
  local ref="$TMPD/ref-missing-key.json"
  jq 'del(.["auth-signout-burst"].triggerLogicType)' "$REFERENCE" > "$ref"
  jq -e '.["auth-signout-burst"] | has("triggerLogicType") | not' "$ref" >/dev/null || { _report "F24 missing key" fail "mutation did not land"; return; }
  _run "$CAPTURE" "$ref"
  if [[ "$_rc" -eq 1 ]] && grep -q 'not a name-indexed projection object' <<<"$_out"; then
    _report "F24 a reference with one rule's triggerLogicType key deleted is refused at the shape floor" ok
  else
    _report "F24 reference missing key refused" fail "rc=$_rc; output: $(head -c 300 <<<"$_out")"
  fi
}

# THE PINS are covered by F14/F15 below (#8023's rows, adapted: rc 2 and the
# `refusing destination host` / `refusing org` anchors the drift workflow greps).
# This shim records argv AND stdin so the end-to-end row can assert the bearer
# header travels on stdin, which #8023's stub cannot see.
_shim_dir=""
_install_curl_shim() { # $1 = file to serve on a real call
  _shim_dir="$TMPD/shim.$RANDOM"
  mkdir -p "$_shim_dir"
  : > "$_shim_dir/calls.log"
  : > "$_shim_dir/stdin.log"
  cat > "$_shim_dir/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$_shim_dir/calls.log"
printf '%s\0' "\$@" >> "$_shim_dir/argv.bin"
cat >> "$_shim_dir/stdin.log"
cat "$1"
EOF
  chmod +x "$_shim_dir/curl"
}
# (f) END TO END THROUGH THE PINNED PATH. Host and org equal the literals; the
# shim asserts curl's argv shape (#7997: `--disable` literally first, `--noproxy
# '*'`, the bearer header fed on stdin via `--header @-` so the token never
# appears in argv) and serves the capture; the probe must print the LIVE PASS
# line (no FIXTURE token) over all 28.
t_pinned_path_end_to_end() {
  _install_curl_shim "$CAPTURE"
  local rc=0 out
  out=$(PATH="$_shim_dir:$PATH" SENTRY_AUTH_TOKEN=fixture-token SENTRY_ORG=jikigai-eu \
        SENTRY_API_HOST=jikigai-eu.sentry.io SENTRY_REFERENCE_FILE="$REFERENCE" bash "$PROBE" 2>&1) || rc=$?
  local why=()
  [[ "$rc" -eq 0 ]] || why+=("rc=$rc")
  grep -qF -- "sentry_alert live fidelity: PASS (all ${N} in-scope rules match the committed reference field-for-field)" <<<"$out" || why+=("no live PASS line")
  grep -q 'FIXTURE' <<<"$out" && why+=("FIXTURE token present on a live-branch run")
  [[ "$(wc -l < "$_shim_dir/calls.log")" -gt 0 ]] || why+=("curl was never invoked")
  # argv[1] must be `--disable`, LITERALLY FIRST (curl reads it only there).
  local first; first=$(tr '\0' '\n' < "$_shim_dir/argv.bin" | head -1)
  [[ "$first" == "--disable" ]] || why+=("argv[1]='$first', want --disable")
  tr '\0' '\n' < "$_shim_dir/argv.bin" | grep -qx -- '--noproxy' || why+=("--noproxy absent")
  tr '\0' '\n' < "$_shim_dir/argv.bin" | grep -qx -- '\*' || why+=("noproxy '*' absent")
  tr '\0' '\n' < "$_shim_dir/argv.bin" | grep -qx -- '@-' || why+=("--header @- absent")
  grep -q 'fixture-token' "$_shim_dir/argv.bin" && why+=("the token appeared in curl argv")
  grep -q '^Authorization: Bearer fixture-token$' "$_shim_dir/stdin.log" || why+=("the bearer header was not fed on stdin")
  # The pinned URL must be the ONLY URL-shaped argument, with the page size the
  # `>= 100` ceiling assumes; and the call must be a plain GET.
  local urls; urls=$(tr '\0' '\n' < "$_shim_dir/argv.bin" | grep -E '^[a-z]+://' || true)
  [[ "$urls" == "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/workflows/?per_page=100" ]] || why+=("URL set is not exactly the pinned URL: $(tr '\n' ' ' <<<"$urls")")
  tr '\0' '\n' < "$_shim_dir/argv.bin" | grep -qxE -- '-X|--request|-d|--data|--data-binary|--data-raw|--data-urlencode|-F|--form|-L|--location|-T|--upload-file' && why+=("a method/body/redirect flag is present")
  tr '\0' '\n' < "$_shim_dir/argv.bin" | grep -qx -- '-fsS' || why+=("-fsS absent")
  tr '\0' '\n' < "$_shim_dir/argv.bin" | grep -qx -- '--max-time' || why+=("--max-time absent")
  tr '\0' '\n' < "$_shim_dir/argv.bin" | grep -qx -- '--proto' || why+=("--proto absent")
  if [[ ${#why[@]} -eq 0 ]]; then
    _report "F25 with host and org pinned, curl gets exactly the pinned URL (GET, --disable --noproxy '*' --proto, -fsS --max-time, --header @- with the token on stdin) and the probe prints the LIVE PASS over ${N}" ok
  else
    _report "F25 pinned path end to end" fail "${why[*]}; output: $(head -c 300 <<<"$out")"
  fi
}


# ── #8023's rows F14–F21 (transport confinement + destination pin), adapted ──
# to this probe: the reference is the derived one, the org pin is a LITERAL
# (so a 63-octet org passes the SHAPE gate and is refused by the PIN), and every
# refusal exits 2 with the anchor the drift workflow greps.
_stub_curl_dir() {
  local d="$TMPD/stub.$1"
  mkdir -p "$d"
  cat > "$d/curl" <<'STUB'
: > "$STUB_ARGV"
for a in "$@"; do printf '%s\n' "$a" >> "$STUB_ARGV"; done
printf '%s\n' "${SSLKEYLOGFILE-<unset>}" > "$STUB_ENV"
cat >/dev/null
printf '[]'
STUB
  chmod +x "$d/curl"
  printf '%s' "$d"
}
_argv=""; _envf=""
_run_live() {
  local name="$1"; shift
  local d; d=$(_stub_curl_dir "$name")
  _argv="$TMPD/$name.argv"; _envf="$TMPD/$name.env"
  : > "$_argv"; : > "$_envf"
  _rc=0
  _out=$(env -u SENTRY_FIXTURE_RULES \
           PATH="$d:$PATH" STUB_ARGV="$_argv" STUB_ENV="$_envf" \
           SENTRY_AUTH_TOKEN=fixture SENTRY_REFERENCE_FILE="$REFERENCE" \
           "$@" bash "$PROBE" 2>&1) || _rc=$?
}
t_hostile_host_refused() {
  local h bad=0 detail=""
  for h in attacker.tld eu.sentry.io de.sentry.io sentry.io jikigai-eu.sentry.io.evil.example; do
    _run_live "hostilehost.${h//./_}" SENTRY_ORG=jikigai-eu SENTRY_API_HOST="$h"
    if [[ "$_rc" -ne 2 ]] || ! grep -q '^ERROR: refusing destination host' <<<"$_out" \
       || [[ -s "$_argv" ]]; then
      bad=$((bad + 1))
      detail+=" [$h rc=$_rc argv-bytes=$(wc -c <"$_argv")]"
    fi
  done
  if [[ "$bad" -eq 0 ]]; then
    _report "F14 all five non-pinned hosts REFUSED (rc 2, anchored) before any request (incl. the near-misses)" ok
  else
    _report "F14 hostile SENTRY_API_HOST is refused" fail "$bad of 5 arms wrong:$detail"
  fi
}
t_hostile_org_refused() {
  local o bad=0 detail="" i=0
  for o in '@evil.tld/x' 'jikigai.evil.tld' 'jikigai/../../evil' 'jikigai%2fx' 'JIKIGAI' '-leading' '' 'jikigai-eu2'; do
    i=$((i + 1))
    _run_live "hostileorg.$i" SENTRY_ORG="$o" SENTRY_API_HOST="jikigai-eu.sentry.io"
    # The empty org exits 1 at the `:?` guard; every other shape must exit 2
    # with the anchor (from the shape gate or the literal pin), and none may
    # reach the wire.
    if [[ "$_rc" -eq 0 ]] || [[ -s "$_argv" ]] \
       || { [[ -n "$o" ]] && { [[ "$_rc" -ne 2 ]] || ! grep -q '^ERROR: refusing org' <<<"$_out"; }; }; then
      bad=$((bad + 1)); detail+=" [org='$o' rc=$_rc argv-bytes=$(wc -c <"$_argv")]"
    fi
  done
  if [[ "$bad" -eq 0 ]]; then
    _report "F15 every non-RFC-1035 org shape AND a well-formed non-pinned org are REFUSED (rc 2, anchored) before any request" ok
  else
    _report "F15 hostile SENTRY_ORG is refused" fail "$bad shape(s) wrong:$detail"
  fi
}
t_transport_flags_first() {
  _run_live flags SENTRY_ORG=jikigai-eu SENTRY_API_HOST=jikigai-eu.sentry.io
  local a1 a2 a3 a4
  a1=$(sed -n '1p' "$_argv"); a2=$(sed -n '2p' "$_argv")
  a3=$(sed -n '3p' "$_argv"); a4=$(sed -n '4p' "$_argv")
  if [[ "$a1" == "--disable" && "$a2" == "--noproxy" && "$a3" == '*' \
        && "$a4" == "--proto" ]] && grep -qx -- '=https' "$_argv" && grep -qx -- '-g' "$_argv"; then
    _report "F16 the credentialed curl is transport-confined, flags FIRST (--disable --noproxy * --proto =https -g)" ok
  else
    _report "F16 transport flags are first" fail \
      "argv[1..4]=[$a1 $a2 $a3 $a4]; want [--disable --noproxy * --proto]. Full argv: $(head -c 300 "$_argv" | tr '\n' ' ')"
  fi
}
t_resolver_env_scrubbed() {
  _run_live scrub SENTRY_ORG=jikigai-eu SENTRY_API_HOST=jikigai-eu.sentry.io \
    SSLKEYLOGFILE=/tmp/should-not-survive
  if grep -qx '<unset>' "$_envf"; then
    _report "F17 resolver / trust-anchor / keylog env is scrubbed before the request" ok
  else
    _report "F17 resolver env is scrubbed" fail \
      "the child saw SSLKEYLOGFILE=$(cat "$_envf") — the unset prologue did not run"
  fi
}
t_fixture_mode_still_passes() {
  _run "$CAPTURE"
  if [[ "$_rc" -eq 0 ]] && grep -q "all ${N} in-scope rules match" <<<"$_out"; then
    _report "F18 fixture mode still PASSES with the guards in place" ok
  else
    _report "F18 fixture mode still passes" fail "rc=$_rc; output: $(head -c 300 <<<"$_out")"
  fi
}
t_org_locale_independent() {
  local lc bad=0 detail=""
  for lc in C en_US.UTF-8; do
    _run_live "loc.${lc//./_}" LC_ALL="$lc" LANG="$lc" \
      SENTRY_ORG='jikigaí' SENTRY_API_HOST=jikigai-eu.sentry.io
    if [[ "$_rc" -ne 2 ]] || ! grep -q '^ERROR: refusing org' <<<"$_out"; then
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
  # A 63-octet slug passes the SHAPE gate and is then refused by the literal
  # PIN (its message carries `(pinned:`); a 64-octet one never reaches the pin.
  _run_live len63 SENTRY_ORG="a$(printf 'b%.0s' $(seq 62))" SENTRY_API_HOST=jikigai-eu.sentry.io
  local rc63=$_rc out63="$_out"
  _run_live len64 SENTRY_ORG="a$(printf 'b%.0s' $(seq 63))" SENTRY_API_HOST=jikigai-eu.sentry.io
  local rc64=$_rc out64="$_out"
  if [[ "$rc63" -eq 2 ]] && grep -q '^ERROR: refusing org .*(pinned: jikigai-eu)' <<<"$out63" \
     && [[ "$rc64" -eq 2 ]] && grep -q '^ERROR: refusing org' <<<"$out64" && ! grep -q '(pinned:' <<<"$out64"; then
    _report "F20 a 63-octet org passes the shape gate (refused by the PIN); a 64-octet one is refused by the shape gate" ok
  else
    _report "F20 org length boundary is 63/64" fail \
      "63: rc=$rc63 pinned=$(grep -c '(pinned:' <<<"$out63"); 64: rc=$rc64 pinned=$(grep -c '(pinned:' <<<"$out64")"
  fi
}
t_transport_not_reopened_by_suffix() {
  _run_live suffix SENTRY_ORG=jikigai-eu SENTRY_API_HOST=jikigai-eu.sentry.io
  local a bad="" n_noproxy=0 n_proto=0
  while IFS= read -r a; do
    case "$a" in
      -x|--proxy|--proxy1.0|--preproxy|--socks4|--socks4a|--socks5 \
        |--socks5-hostname|--socks5-basic|--socks5-gssapi) bad+=" $a" ;;
      -K|--config) bad+=" $a" ;;
      --proto-default|--proto-redir) bad+=" $a" ;;
      --resolve|--connect-to|--unix-socket|--abstract-unix-socket|--url) bad+=" $a" ;;
      -k|--insecure|--proxy-insecure|--ssl-no-revoke|--cacert|--capath \
        |--doh-url|--doh-insecure|--location-trusted|-L|--location) bad+=" $a" ;;
      --no-globoff) bad+=" $a" ;;
    esac
    [[ "$a" == "--noproxy" ]] && n_noproxy=$((n_noproxy + 1))
    [[ "$a" == "--proto"   ]] && n_proto=$((n_proto + 1))
  done < "$_argv"
  [[ "$n_noproxy" -eq 1 ]] || bad+=" --noproxy x${n_noproxy}"
  [[ "$n_proto"   -eq 1 ]] || bad+=" --proto x${n_proto}"
  if [[ -z "$bad" && -s "$_argv" ]]; then
    _report "F21 no later argument re-opens the transport the prefix closed" ok
  else
    _report "F21 the argv SUFFIX re-opens confinement" fail \
      "offending token(s):${bad:-<none>}; argv-bytes=$(wc -c <"$_argv"). Full argv: $(head -c 300 "$_argv" | tr '\n' ' ')"
  fi
}

# ── Live-side floors that were missing (#8069 review) ──────────────────────
# A live in-scope duplicate name, an empty name, and a multi-trigger workflow
# with no logicType each REFUSE (exit 1, no PASS line, the module's own error
# text) — each was measured PASS at rc 0 before these floors existed.
_live_refusal() { # $1=label $2=jq-program over the capture $3=marker $4=description
  local f; f=$(_mutant "$1" "$2")
  if [[ "$f" == "JQFAIL" || "$f" == "NOOP" ]]; then _report "$4" fail "the mutation did not land ($f)"; return; fi
  _run "$f"
  if [[ "$_rc" -eq 1 ]] && grep -qF -- "$3" <<<"$_out" && ! grep -q 'live fidelity: PASS' <<<"$_out"; then
    _report "$4" ok
  else
    _report "$4" fail "rc=$_rc (want 1), marker '$3' $(grep -qF -- "$3" <<<"$_out" && echo present || echo ABSENT). Output: $(head -c 300 <<<"$_out")"
  fi
}
t_live_duplicate_name_refused() {
  _live_refusal livedup \
    '. + [ (map(select(.name=="byok-art-33-breach"))[0] | .enabled=false) ]' \
    'duplicate in-scope workflow name(s): byok-art-33-breach' \
    "F29 a disabled same-name live copy of byok-art-33-breach makes the probe REFUSE, never PASS (order-independent)"
}
t_live_empty_name_refused() {
  _live_refusal liveempty \
    'map(if .name=="auth-signout-burst" then .name="" else . end)' \
    'empty or non-string name' \
    "F30 a live in-scope workflow with an empty name is REFUSED rather than dropped from the UNMANAGED loop"
}
t_live_multi_trigger_null_logictype_refused() {
  _live_refusal livenull \
    'map(if .name=="byok-art-33-breach" then del(.triggers.logicType) else . end)' \
    'carries no triggers.logicType; refusing to default it' \
    "F31 a 3-trigger live workflow with no logicType is REFUSED, never defaulted to the TF side's any-short"
}
# The probe's compared-field list is hardcoded; `frequency` had no drift row, so
# dropping it from the list left the suite green (review mutation).
t_frequency_drift() {
  _drift_case freq 'map(if .name=="auth-signout-burst" then .config.frequency=999 else . end)' \
    "DRIFT: 'auth-signout-burst'.frequency declared=" \
    "F32 a changed config.frequency is detected and named"
}

# (g)/(h) THE PROVIDER CONSTANT. The provider hard-codes trigger logicType
# `any-short` on every write (resource_alert_impl.go 803/835 @ v0.15.7); a
# single-trigger rule imported as `all` becomes `any-short` on its first edit,
# and that must NOT read as a flip — one condition has no logic. A THREE-trigger
# rule flipping to `all` still must.
t_single_trigger_logictype_is_not_a_flip() {
  # `all → any-short`: the provider's post-apply value. (`all → all` would be a
  # NOOP the landing check rejects.)
  local f; f=$(_mutant single-any 'map(if .name=="auth-signout-burst" then .triggers.logicType="any-short" else . end)')
  if [[ "$f" == "JQFAIL" || "$f" == "NOOP" ]]; then _report "F26 single-trigger logicType" fail "mutation did not land ($f)"; return; fi
  _run "$f"
  if [[ "$_rc" -eq 0 ]] && ! grep -q 'LOGICTYPE FLIP' <<<"$_out"; then
    _report "F26 a single-trigger rule whose live logicType becomes any-short (the provider's write) is NOT a flip" ok
  else
    _report "F26 single-trigger any-short is not a flip" fail "rc=$_rc; output: $(head -c 300 <<<"$_out")"
  fi
}
# F6 already flips the THREE-trigger byok-art-33-breach to `all` and asserts
# LOGICTYPE FLIP; that row is (h). Kept there, referenced here so the pair reads
# together.

# (k) NORMALISE IS ORDER-INSENSITIVE AND DATA-SENSITIVE. Swapping the VALUES of
# two conditions with DIFFERENT keys changes the data (the set of (key,value)
# pairs), so `sort_by(tostring)` must not hide it. zot-mirror-fallback-rate has
# five action-filter conditions; [0] is registry=ghcr-fallback and [2] is
# stage=inngest_ghcr_fallback.
t_value_swap_is_drift() {
  _drift_case valueswap \
    'map(if .name=="zot-mirror-fallback-rate" then
           (.actionFilters[0].conditions[0].comparison.value) as $a
           | (.actionFilters[0].conditions[2].comparison.value) as $b
           | .actionFilters[0].conditions[0].comparison.value = $b
           | .actionFilters[0].conditions[2].comparison.value = $a
         else . end)' \
    'comparison.value' \
    "F27 swapping comparison.value between two differently-keyed conditions is DRIFT (order-insensitive, data-sensitive)"
}

# (i) TF/LIVE SHAPE PARITY — the structural anchor for the module's `tf` side,
# against REAL data on both sides: the COMMITTED reference (projected from the
# real plan) and the LIVE projection of the frozen capture. For every common
# rule the SET of (leaf path with numeric indices erased, leaf TYPE) must be
# equal. A dropped `comparison: true`, a null `targetIdentifier` becoming a
# string, or a string-vs-array `detectorIds` reds here; a threshold edit or an
# added condition does not (no value ledger — that is what the live probe is
# for). `common >= 20` is the floor that keeps this row from passing on a near-
# empty intersection.
t_tf_live_shape_parity() {
  local live_proj="$TMPD/live-proj.json"
  jq --arg side live -f "$PROJ" "$CAPTURE" > "$live_proj"
  local report
  report=$(jq -r -n --slurpfile t "$COMMITTED_REF" --slurpfile l "$live_proj" '
    def shapes: [ paths(type != "array" and type != "object") as $p
                  | [ ($p | map(if type == "number" then "[]" else . end) | join(".")), (getpath($p) | type) ] ]
                | unique;
    $t[0] as $T | $l[0] as $L
    | (($T | keys) - (($T | keys) - ($L | keys))) as $common
    | "common=\($common | length)",
      ( $common[] as $n
        | ($T[$n] | shapes) as $a | ($L[$n] | shapes) as $b
        | select($a != $b)
        | "MISMATCH \($n): tf-only=\(($a - $b) | tojson) live-only=\(($b - $a) | tojson)" )
  ')
  local common; common=$(sed -n 's/^common=//p' <<<"$report")
  local mism; mism=$(grep -c '^MISMATCH' <<<"$report" || true)
  if [[ "$common" =~ ^[0-9]+$ && "$common" -ge 20 && "$mism" -eq 0 ]]; then
    _report "F28 tf/live shape parity over ${common} common rules (>= 20): every leaf path and type agrees between the committed tf-projected reference and the live projection" ok
  else
    _report "F28 tf/live shape parity" fail "common=${common:-?} mismatches=$mism: $(grep '^MISMATCH' <<<"$report" | head -3 | cut -c1-300)"
  fi
}

# (l) H4 — THE HARNESS ROW. `_mutant` with a selector matching nothing must
# report NOOP so the row built on it FAILS on landing rather than comparing the
# capture to itself and passing an identity assertion.
t_h4_mutant_noop_is_detected() {
  local f; f=$(_mutant noop 'map(if .name=="this-rule-does-not-exist" then .enabled=false else . end)')
  if [[ "$f" == "NOOP" ]]; then
    _report "H4 _mutant reports NOOP when the selector matches nothing, so a row built on it fails on landing" ok
  else
    _report "H4 _mutant NOOP detection" fail "got '$f' (want NOOP)"
  fi
}

# ── Guard 4 — the frozen-rule live pin (#8451) ───────────────────────────────
# The workflows whose trigger type is in the projection's `excluded` set are
# outside BOTH projection sides, so every row above is blind to them by
# construction. After #8451 two of them are also `ignore_changes = all` in
# Terraform, so a UI edit plans "0 changes". The probe's frozen-rule pass pins
# every rule TERRAFORM FREEZES (a `sentry_alert` block carrying
# `legacy_trigger_conditions`, derived from the .tf) to the committed capture
# entry of the same name, on every field that decides paging: enabled,
# detectorIds, the full trigger {type, comparison} set, triggers.logicType,
# config.frequency, environment and the canonicalised actionFilters. Every other
# excluded-type live workflow is a census member: in the capture = Sentry's own
# unmanaged default (not pinned), absent from it = UNMANAGED-FROZEN.
#
# Expected counts are DERIVED here, independently of the probe (a grep of the
# .tf, not the probe's awk; capture minus the live projection). Never typed.
FROZEN_N=$(( $(jq 'length' "$CAPTURE") - N ))
FROZEN_NAMES_JSON=$(jq -c --slurpfile r "$REFERENCE" '[ .[].name | select(. as $n | $r[0] | has($n) | not) ]' "$CAPTURE")
FROZEN_TF_N=$(cat "$REPO_ROOT"/apps/web-platform/infra/sentry/*.tf | grep -cE '^[[:space:]]*legacy_trigger_conditions[[:space:]]*=[[:space:]]*\[[[:space:]]*"')
# _run_env <live-fixture> VAR=val… — `_run` with extra probe environment.
_run_env() {
  local fx="$1"; shift
  _rc=0
  _out=$(env SENTRY_AUTH_TOKEN=fixture SENTRY_ORG=fixture \
         SENTRY_REFERENCE_FILE="$REFERENCE" \
         SENTRY_FIXTURE_RULES="$fx" "$@" bash "$PROBE" 2>&1) || _rc=$?
}

t_g4_identity_pins_census() {
  _run "$CAPTURE"
  local want="frozen-rule pin: compared ${FROZEN_TF_N} of ${FROZEN_TF_N} Terraform-frozen rule(s) against the committed capture"
  if [[ "$FROZEN_TF_N" -ge 2 && "$FROZEN_N" -gt "$FROZEN_TF_N" ]] && [[ "$_rc" -eq 0 ]] && grep -qF -- "$want" <<<"$_out" \
     && grep -q 'live fidelity: PASS' <<<"$_out" && ! grep -q 'FROZEN\|UNMANAGED-FROZEN' <<<"$_out"; then
    _report "G4-6 a live fixture equal to the capture PASSES and the frozen pin compares the ${FROZEN_TF_N} Terraform-frozen rules (grep of the .tf), fewer than the ${FROZEN_N} excluded-type captured workflows" ok
  else
    _report "G4-6 identity passes the frozen pin" fail "FROZEN_TF_N=$FROZEN_TF_N FROZEN_N=$FROZEN_N rc=$_rc; want '$want'. Output: $(head -c 400 <<<"$_out")"
  fi
}
t_g4_comparison_true() {
  _drift_case g4cmptrue \
    'map(if .name=="sandbox-startup-failure" then .triggers.conditions[0].comparison=true else . end)' \
    "FROZEN DRIFT: 'sandbox-startup-failure'.triggerConditions" \
    "G4-1 a frozen rule's trigger comparison replaced by 'true' is detected"
}
t_g4_threshold_changed() {
  _drift_case g4threshold \
    'map(if .name=="sandbox-startup-failure" then .triggers.conditions[0].comparison.value=50 else . end)' \
    "FROZEN DRIFT: 'sandbox-startup-failure'.triggerConditions" \
    "G4-1b a frozen rule re-thresholded in the UI (comparison.value 2 -> 50) is detected"
}
# SECOND MEMBER: the first frozen rule is correct, the second is not. A pass
# that stops at the first excluded-type workflow (or only checks one) greens.
t_g4_second_member_disabled() {
  local f; f=$(_mutant g4disabled 'map(if .name=="sandbox-startup-failure" then .enabled=false else . end)')
  if [[ "$f" == "JQFAIL" || "$f" == "NOOP" ]]; then _report "G4-3 second member disabled" fail "the mutation did not land ($f)"; return; fi
  _run "$f"
  if [[ "$_rc" -eq 1 ]] && grep -qF -- "FROZEN DISABLED: 'sandbox-startup-failure'" <<<"$_out" \
     && ! grep -q "'auth-per-user-loop'" <<<"$_out" && grep -q 'live fidelity FAILED' <<<"$_out"; then
    _report "G4-3 auth-per-user-loop correct, then sandbox-startup-failure enabled=false: RED on the second member only" ok
  else
    _report "G4-3 second member disabled" fail "rc=$_rc (want 1). Output: $(head -c 400 <<<"$_out")"
  fi
}
t_g4_no_email_action() {
  _drift_case g4noemail \
    'map(if .name=="auth-per-user-loop" then .actionFilters |= map(.actions = []) else . end)' \
    "FROZEN DRIFT: 'auth-per-user-loop'.actionFilters" \
    "G4-4 a frozen rule stripped of its email action is detected (full actions comparison, not '>= 1 email')"
}
t_g4_detector_changed() {
  _drift_case g4detector \
    'map(if .name=="sandbox-startup-failure" then .detectorIds=["9999999"] else . end)' \
    "FROZEN MONITOR UNBIND: 'sandbox-startup-failure'" \
    "G4-5 a frozen rule re-bound to another detector is detected"
}
t_g4_unknown_frozen_rule() {
  _drift_case g4unknown \
    '. + [ (map(select(.name=="auth-per-user-loop"))[0] | .name="new-frozen-rule" | .id="999998") ]' \
    "UNMANAGED-FROZEN: 'new-frozen-rule'" \
    "G4-7 an excluded-type live workflow absent from the capture is UNMANAGED-FROZEN"
}
t_g4_compared_nothing() {
  _drift_case g4none \
    "map(select(.name | IN(${FROZEN_NAMES_JSON}[]) | not))" \
    'frozen-rule pin compared nothing' \
    "G4-2 zero excluded-type live workflows while the capture holds ${FROZEN_N}: RED ('compared nothing')"
}
# The capture is the anchor; an unreadable one must refuse, never skip the pin.
t_g4_capture_unreadable_refuses() {
  _rc=0
  _out=$(SENTRY_AUTH_TOKEN=fixture SENTRY_ORG=fixture SENTRY_REFERENCE_FILE="$REFERENCE" \
         SENTRY_FROZEN_CAPTURE_FILE="$TMPD/no-such-capture.json" \
         SENTRY_FIXTURE_RULES="$CAPTURE" bash "$PROBE" 2>&1) || _rc=$?
  if [[ "$_rc" -eq 1 ]] && grep -q 'frozen-rule capture not readable' <<<"$_out" && ! grep -q 'live fidelity: PASS' <<<"$_out"; then
    _report "G4-8 an unreadable frozen-rule capture REFUSES (rc 1), never skips the pin" ok
  else
    _report "G4-8 unreadable capture refuses" fail "rc=$_rc (want 1). Output: $(head -c 300 <<<"$_out")"
  fi
}

# ── Guard 4 review rows (#8451 review) ───────────────────────────────────────
t_g4_one_frozen_deleted() {
  _drift_case g4del1 'map(select(.name != "sandbox-startup-failure"))' \
    "FROZEN DELETED: 'sandbox-startup-failure'" \
    "G4-9 ONE of the two Terraform-frozen rules deleted live (the other intact) is FROZEN DELETED, not a quiet census shrink"
}
t_g4_fallthrough_noone() {
  _drift_case g4fallthrough \
    'map(if .name=="auth-per-user-loop" then .actionFilters[0].actions[0].data.fallthroughType="NoOne" else . end)' \
    "FROZEN DRIFT: 'auth-per-user-loop'.actionFilters" \
    "G4-10 a frozen rule's email fallthroughType ActiveMembers -> NoOne (still an email action, pages nobody) is detected"
}
t_g4_tag_filter_emptied() {
  _drift_case g4tagempty \
    'map(if .name=="sandbox-startup-failure" then .actionFilters[0].conditions=[] else . end)' \
    "FROZEN DRIFT: 'sandbox-startup-failure'.actionFilters" \
    "G4-11 a frozen rule's tag filter emptied (now pages on every event) is detected"
}
t_g4_frequency_changed() {
  _drift_case g4freq \
    'map(if .name=="auth-per-user-loop" then .config.frequency=1440 else . end)' \
    "FROZEN DRIFT: 'auth-per-user-loop'.frequency" \
    "G4-12 a frozen rule's config.frequency changed (30 -> 1440) is detected"
}
t_g4_trigger_logictype_changed() {
  _drift_case g4logic \
    'map(if .name=="sandbox-startup-failure" then .triggers.logicType="none" else . end)' \
    "FROZEN DRIFT: 'sandbox-startup-failure'.triggerLogicType" \
    "G4-13 a frozen rule's triggers.logicType changed (all -> none, inverts the trigger) is detected"
}
# Sentry's own default workflow is excluded-type and IN the capture, but
# Terraform does not manage it: pinning it filed a p1 over a vendor default.
t_g4_vendor_default_not_pinned() {
  local f; f=$(_mutant g4vendor 'map(if .name=="Send a notification for high priority issues" then .enabled=false else . end)')
  if [[ "$f" == "JQFAIL" || "$f" == "NOOP" ]]; then _report "G4-14 vendor default not pinned" fail "the mutation did not land ($f)"; return; fi
  _run "$f"
  if [[ "$_rc" -eq 0 ]] && grep -q 'live fidelity: PASS' <<<"$_out" && ! grep -q 'FROZEN' <<<"$_out"; then
    _report "G4-14 Sentry's default 'Send a notification for high priority issues' (566201, not Terraform-managed) disabled live PASSES: not pinned" ok
  else
    _report "G4-14 vendor default not pinned" fail "rc=$_rc (want 0). Output: $(head -c 400 <<<"$_out")"
  fi
}
t_g4_unknown_vendor_shaped() {
  _drift_case g4unknown2 \
    '. + [ (map(select(.name=="Send a notification for high priority issues"))[0] | .name="another-high-priority-copy" | .id="999997") ]' \
    "UNMANAGED-FROZEN: 'another-high-priority-copy'" \
    "G4-15 an unknown excluded-type workflow (high-priority trigger, not a frozen name, not in the capture) is UNMANAGED-FROZEN"
}
# #8267: Sentry created the Seer default on 2026-09-17, after the 2026-09-09
# capture, with a trigger type the provider cannot express (v0.15.7 reads it into
# legacy_trigger_conditions and writes comparison=true). It is registered in
# vendor-default-workflows.json, never appended to the dated capture. The live
# fixture below is the capture plus that workflow, built from the registry's own
# {id, name} so the rows track the file they test.
REGISTRY="$REPO_ROOT/apps/web-platform/infra/sentry/vendor-default-workflows.json"
SEER_NAME="Send a notification when pull requests are ready"
_seer_live() { # $1=out $2=id override (default: the registered id)
  local id="${2:-$(jq -r --arg n "$SEER_NAME" '.[] | select(.name == $n) | .id' "$REGISTRY")}"
  jq --arg n "$SEER_NAME" --arg i "$id" \
    '. + [ (map(select(.name=="Send a notification for high priority issues"))[0]
           | .name=$n | .id=$i
           | .triggers.conditions=[{"type":"seer_activity_trigger","comparison":["pr_ready_for_review"]}]) ]' \
    "$CAPTURE" > "$1"
}
# Both halves, one row each direction: registered (type excluded + {id, name} in
# the registry) PASSES; the same live payload with an EMPTY registry is
# UNMANAGED-FROZEN, not plain UNMANAGED (so the type half is what took it out of
# scope). Dropping the type from `def excluded` makes the first run UNMANAGED.
t_g4_seer_default_registered() {
  local live="$TMPD/live-seer.json" empty="$TMPD/registry-empty.json"
  _seer_live "$live"; printf '[]\n' > "$empty"
  jq -e --arg n "$SEER_NAME" 'map(select(.name == $n)) | length == 1' "$live" >/dev/null \
    || { _report "G4-20 Seer default registered" fail "the live fixture did not land"; return; }
  _run_env "$live"
  local rc_reg=$_rc out_reg="$_out"
  _run_env "$live" SENTRY_VENDOR_DEFAULTS_FILE="$empty"
  if [[ "$rc_reg" -eq 0 ]] && grep -q 'live fidelity: PASS' <<<"$out_reg" && ! grep -q 'UNMANAGED' <<<"$out_reg" \
     && [[ "$_rc" -eq 1 ]] && grep -qF -- "UNMANAGED-FROZEN: '$SEER_NAME'" <<<"$_out" \
     && ! grep -qF -- "UNMANAGED: '$SEER_NAME'" <<<"$_out"; then
    _report "G4-20 the registered Seer default PASSES; with an empty registry it is UNMANAGED-FROZEN (out of scope by type, unknown by registry)" ok
  else
    _report "G4-20 Seer default registered" fail "registered rc=$rc_reg (want 0); empty-registry rc=$_rc (want 1). Output: $(head -c 400 <<<"$_out")"
  fi
}
# A workflow borrowing a registered default's NAME under another id is not that
# default: matching by name alone was an evasion (#8545 review).
t_g4_seer_name_other_id() {
  local live="$TMPD/live-seer-otherid.json"; _seer_live "$live" 999111
  _run_env "$live"
  if [[ "$_rc" -eq 1 ]] && grep -qF -- "UNMANAGED-FROZEN: '$SEER_NAME' (id \"999111\") carries the name of a registered Sentry default under a DIFFERENT id" <<<"$_out"; then
    _report "G4-21 a registered default's name under a different id is UNMANAGED-FROZEN (identity is id AND name)" ok
  else
    _report "G4-21 name under another id" fail "rc=$_rc (want 1). Output: $(head -c 400 <<<"$_out")"
  fi
}
t_g4_seer_duplicate_name() {
  local live="$TMPD/live-seer-dup.json" dup="$TMPD/live-seer-dup2.json"
  _seer_live "$live"
  jq --arg n "$SEER_NAME" '. + [ (map(select(.name == $n))[0] | .id = "999112") ]' "$live" > "$dup"
  _run_env "$dup"
  if [[ "$_rc" -eq 1 ]] && grep -qF -- "UNMANAGED-FROZEN DUPLICATE: '$SEER_NAME' names more than one" <<<"$_out"; then
    _report "G4-22 a registered default's name live twice is UNMANAGED-FROZEN DUPLICATE, even when one copy has the registered id" ok
  else
    _report "G4-22 duplicate registered name" fail "rc=$_rc (want 1). Output: $(head -c 400 <<<"$_out")"
  fi
}
# The capture half of KNOWN is id-matched too: the high-priority default under a
# new id is no longer accepted by name.
t_g4_capture_default_other_id() {
  _drift_case g4hpid \
    'map(if .name=="Send a notification for high priority issues" then .id="999113" else . end)' \
    "UNMANAGED-FROZEN: 'Send a notification for high priority issues' (id \"999113\") carries the name of a registered Sentry default under a DIFFERENT id" \
    "G4-23 the captured high-priority default under a different id is UNMANAGED-FROZEN"
}
t_g4_registry_malformed_refuses() {
  local bad="$TMPD/registry-bad.json"; printf '[{"name":"x"}]\n' > "$bad"
  _run_env "$CAPTURE" SENTRY_VENDOR_DEFAULTS_FILE="$bad"
  if [[ "$_rc" -eq 1 ]] && grep -q 'vendor-default registry' <<<"$_out" && ! grep -q 'live fidelity: PASS' <<<"$_out"; then
    _report "G4-24 a registry entry without a string id REFUSES (rc 1), never a silent census" ok
  else
    _report "G4-24 malformed registry refuses" fail "rc=$_rc (want 1). Output: $(head -c 400 <<<"$_out")"
  fi
}
t_g4_zero_frozen_names_refuses() {
  local d="$TMPD/tf-nofrozen"; mkdir -p "$d"
  printf 'resource "sentry_alert" "x" {\n  name = "x"\n  trigger_conditions = []\n}\n' > "$d/a.tf"
  _run_env "$CAPTURE" SENTRY_FROZEN_TF_DIR="$d"
  if [[ "$_rc" -eq 1 ]] && grep -q 'derived ZERO frozen rule' <<<"$_out" && ! grep -q 'live fidelity: PASS' <<<"$_out"; then
    _report "G4-16 a .tf set from which ZERO frozen names derive REFUSES (rc 1), never passes a pin that compared nothing" ok
  else
    _report "G4-16 zero frozen names refuses" fail "rc=$_rc (want 1). Output: $(head -c 400 <<<"$_out")"
  fi
}
t_g4_frozen_name_without_capture_refuses() {
  local d="$TMPD/tf-extra"; mkdir -p "$d"
  cp "$REPO_ROOT"/apps/web-platform/infra/sentry/*.tf "$d/"
  printf '\nresource "sentry_alert" "not_captured" {\n  name              = "frozen-but-not-captured"\n  trigger_conditions        = []\n  legacy_trigger_conditions = ["event_unique_user_frequency_count"]\n  lifecycle {\n    ignore_changes = all\n  }\n}\n' >> "$d/issue-alerts.tf"
  _run_env "$CAPTURE" SENTRY_FROZEN_TF_DIR="$d"
  if [[ "$_rc" -eq 1 ]] && grep -qF -- "'frozen-but-not-captured'" <<<"$_out" && grep -q 'no entry in the committed capture' <<<"$_out" \
     && ! grep -q 'live fidelity: PASS' <<<"$_out"; then
    _report "G4-17 a Terraform-frozen name with no capture entry REFUSES (the pin has no anchor for it)" ok
  else
    _report "G4-17 frozen name without capture refuses" fail "rc=$_rc (want 1). Output: $(head -c 400 <<<"$_out")"
  fi
}
t_g4_environment_changed() {
  _drift_case g4env \
    'map(if .name=="auth-per-user-loop" then .environment="staging" else . end)' \
    "FROZEN DRIFT: 'auth-per-user-loop'.environment" \
    "G4-19 a frozen rule bound to an environment (null -> staging, matches only that environment) is detected"
}
# M11: every trigger condition is compared, not [0]. A SYNTHESIZED capture gives
# sandbox-startup-failure two excluded-type trigger conditions; the identity run
# over it must PASS (so the RED below is caused by the second condition alone),
# then conditions[1].comparison.value is moved in the live copy only.
t_g4_second_trigger_condition() {
  local cap2="$TMPD/capture-2trig.json" live2="$TMPD/live-2trig.json"
  jq 'map(if .name=="sandbox-startup-failure" then .triggers.conditions += [{"type":"event_unique_user_frequency_count","comparison":{"value":9,"interval":"1d"}}] else . end)' "$CAPTURE" > "$cap2"
  jq 'map(if .name=="sandbox-startup-failure" then .triggers.conditions[1].comparison.value=90 else . end)' "$cap2" > "$live2"
  jq -e 'map(select(.name=="sandbox-startup-failure"))[0].triggers.conditions | length == 2 and .[1].comparison.value == 9' "$cap2" >/dev/null \
    || { _report "G4-18 second trigger condition" fail "the synthesized two-trigger capture did not land"; return; }
  cmp -s "$cap2" "$live2" && { _report "G4-18 second trigger condition" fail "the live mutation did not land"; return; }
  _run_env "$cap2" SENTRY_FROZEN_CAPTURE_FILE="$cap2"
  local rc_id=$_rc out_id="$_out"
  _run_env "$live2" SENTRY_FROZEN_CAPTURE_FILE="$cap2"
  if [[ "$rc_id" -eq 0 ]] && grep -q 'live fidelity: PASS' <<<"$out_id" \
     && [[ "$_rc" -eq 1 ]] && grep -qF -- "FROZEN DRIFT: 'sandbox-startup-failure'.triggerConditions" <<<"$_out"; then
    _report "G4-18 a frozen rule with TWO trigger conditions: identity PASSES, moving only conditions[1] is FROZEN DRIFT (all conditions compared, not [0])" ok
  else
    _report "G4-18 second trigger condition" fail "identity rc=$rc_id (want 0); mutant rc=$_rc (want 1). Output: $(head -c 400 <<<"$_out")"
  fi
}

t_identity_passes
t_live_api_shape
t_deleted
t_disabled
t_declared_disabled_is_not_a_finding
t_detector_unbind
t_detector_empty
t_logictype_flip
t_tagged_event_key_drift
t_comparison_value_drift
t_comparison_interval_drift
t_unmanaged_new_rule
t_empty_reference_refuses
t_survivors_out_of_scope
t_hostile_host_refused
t_hostile_org_refused
t_transport_flags_first
t_resolver_env_scrubbed
t_fixture_mode_still_passes
t_org_locale_independent
t_org_length_boundary
t_transport_not_reopened_by_suffix
t_reference_minus_one_rule
t_capture_as_reference_refused
t_reference_missing_key_refused
t_pinned_path_end_to_end
t_single_trigger_logictype_is_not_a_flip
t_value_swap_is_drift
t_tf_live_shape_parity
t_live_duplicate_name_refused
t_live_empty_name_refused
t_live_multi_trigger_null_logictype_refused
t_frequency_drift
t_h4_mutant_noop_is_detected
t_g4_identity_pins_census
t_g4_comparison_true
t_g4_threshold_changed
t_g4_second_member_disabled
t_g4_no_email_action
t_g4_detector_changed
t_g4_unknown_frozen_rule
t_g4_compared_nothing
t_g4_capture_unreadable_refuses
t_g4_one_frozen_deleted
t_g4_fallthrough_noone
t_g4_tag_filter_emptied
t_g4_frequency_changed
t_g4_trigger_logictype_changed
t_g4_vendor_default_not_pinned
t_g4_unknown_vendor_shaped
t_g4_seer_default_registered
t_g4_seer_name_other_id
t_g4_seer_duplicate_name
t_g4_capture_default_other_id
t_g4_registry_malformed_refuses
t_g4_zero_frozen_names_refuses
t_g4_frozen_name_without_capture_refuses
t_g4_second_trigger_condition
t_g4_environment_changed

echo "=== $pass passed, $fail failed ==="

ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS — a suite that silently stops running its assertions reports green" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]
