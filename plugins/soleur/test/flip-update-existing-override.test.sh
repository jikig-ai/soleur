#!/usr/bin/env bash
# Regression test: flip.sh flip_segment_in_env on a flag whose segment override ALREADY EXISTS.
#
# flip_segment_in_env has two arms. The first-time arm creates the override
# (feature_states_to_create, feature_segment {segment}). The existing-override arm updates it
# (feature_states_to_update). Since the original flag-set-role feature (#4341) the update arm sent
# feature_segment {id} only; on 2026-10-23 Flagsmith answered {"feature_states_to_update":
# [{"feature_segment":{"segment":["This field is required."]}}]}, so a real flip of an existing
# override exited 3 with nothing written.
#
# The curl stub below REJECTS an update item whose feature_segment lacks `segment` with that exact
# JSON, so reverting the fix turns this suite red (a stub that answers 200 to everything cannot).
# Each accepted body is compared WHOLE against the expected body, with a different feature-segment
# row id per environment and a non-matching sibling row served first, so a hard-coded id, a
# first-row read, a cached row id, a dropped field or a wrong `enabled` all fail.
#
# The function is extracted from the script by CONTENT (flip.sh runs its main flow when sourced and
# its write path needs a typed `yes`, which the ack guard refuses inside an agent session by
# design). Calling the function directly needs no pty and reaches no audit row, no Doppler and no
# network: PATH is shadowed by a stub curl. The typed-yes plumbing around it stays covered by
# operator-ack-guard.test.sh and audit-flag-flip.test.sh.
#
# Overrides (used by the one-time mutation evidence recorded in the PR body, not by the suite):
# FLIP points at a mutated copy of flip.sh (it can sit anywhere, nothing is sourced relative to
# it); SKILLS_DIR is the tree the census scans and does NOT follow FLIP.
set -euo pipefail
if [[ -z "${FLIP:-}" ]]; then
  FLIP="$(git rev-parse --show-toplevel)/plugins/soleur/skills/flag-set-role/scripts/flip.sh"
fi
SKILLS_DIR="${SKILLS_DIR:-$(git rev-parse --show-toplevel)/plugins/soleur/skills}"
fail=0
checks=0

assert() { # <description> <command...>
  local desc="$1"; shift
  checks=$((checks + 1))
  if ! "$@"; then
    echo "flip-update-existing-override: FAIL — $desc" >&2
    fail=1
  fi
}

unset STUB_NO_OVERRIDE STUB_FORCE_REJECT STUB_DEV_SEG STUB_ROW_ID
STUB_DIR="$(mktemp -d)"; trap 'rm -rf "$STUB_DIR"' EXIT

# Flagsmith stub. Knobs: STUB_DEV_SEG (segment id of the override), STUB_ROW_ID (the dev env's
# feature-segment row id; the prd env's is +1000), STUB_NO_OVERRIDE=1 (no existing row -> create
# arm), STUB_FORCE_REJECT=1 (reject every version POST with the live error).
# The feature-segments read answers only the exact query flip.sh must send, and serves a
# non-matching sibling row FIRST, so a wrong query or a first-row read cannot pass.
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
url=""; method="GET"; data=""; prev=""
for a in "$@"; do
  case "$prev" in -X) method="$a" ;; -d) data="$a" ;; esac
  case "$a" in http*) url="$a" ;; esac
  prev="$a"
done
echo "$method $url" >> "${CURL_LOG:?CURL_LOG not set}"
SEG="${STUB_DEV_SEG:-102}"; ROW="${STUB_ROW_ID:-555}"
REJECT='{"feature_states_to_update": [{"feature_segment": {"segment": ["This field is required."]}}]}'
case "$url" in
  *"/feature-segments/"*)
    re='environment=(90722|90721)&feature=777'
    if [[ "${STUB_NO_OVERRIDE:-0}" == "1" || ! "$url" =~ $re ]]; then echo '{"results":[]}'; exit 0; fi
    row="$ROW"; [[ "${BASH_REMATCH[1]}" == "90721" ]] && row=$((ROW + 1000))
    printf '{"results":[{"id":9999,"segment":%s,"priority":2},{"id":%s,"segment":%s,"priority":1}]}' "$((SEG + 5000))" "$row" "$SEG"
    exit 0 ;;
  *"/versions/"*)
    if [[ "$method" != "POST" ]]; then echo '{"detail":"stub: unexpected non-POST versions request"}'; exit 0; fi
    if [[ "${STUB_FORCE_REJECT:-0}" == "1" ]]; then echo "$REJECT"; exit 0; fi
    verdict="$(DATA="$data" python3 -c '
import json, os, sys
try:
    d = json.loads(os.environ["DATA"])
except Exception:
    print("BADJSON"); sys.exit(0)
if not isinstance(d, dict):
    print("BADJSON"); sys.exit(0)
errs = []
for item in d.get("feature_states_to_update", []):
    fs = item.get("feature_segment") or {}
    if "segment" not in fs:
        errs.append({"feature_segment": {"segment": ["This field is required."]}})
print(json.dumps({"feature_states_to_update": errs}) if errs else "OK")
')"
    if [[ "$verdict" == "OK" ]]; then
      echo "$data" >> "${BODY_LOG:?BODY_LOG not set}"
      echo '{"uuid":"v-uuid"}'
    elif [[ "$verdict" == "BADJSON" ]]; then
      echo '{"detail":"body is not valid JSON"}'
    else
      echo "$verdict"
    fi
    exit 0 ;;
  *) echo '{"detail":"stub: unexpected request"}'; exit 0 ;;
esac
STUB
chmod +x "$STUB_DIR/curl"

extract_fn() { # <name>: from the line "name() {" through the first line that is exactly "}"
  awk -v n="$1" '$0 ~ ("^" n "\\(\\) \\{") {p=1} p {print} p && /^}$/ {exit}' "$FLIP"
}

# Content anchors: refuse an extraction that lacks the constructs that define the function. A
# truncated or empty extraction still parses and answers, which is worse than an absent one.
has_construct() { [[ "$(extract_fn "$1")" == *"$2"* ]]; }
assert "extracted fs_api carries the curl call" has_construct fs_api 'curl --'
assert "extracted read_feature_segment_id carries the feature-segments read" has_construct read_feature_segment_id 'feature-segments'
assert "extracted flip_segment_in_env carries the existing-row selector" has_construct flip_segment_in_env 'existing_fs_id'
assert "extracted flip_segment_in_env carries the version POST" has_construct flip_segment_in_env 'versions/'

DRIVER="$STUB_DIR/driver.sh"
{
  echo 'TOKEN=fake-token; FLAGSMITH_API=https://api.flagsmith.com/api/v1'
  extract_fn fs_api
  extract_fn read_feature_segment_id
  extract_fn flip_segment_in_env
} > "$DRIVER"
assert "the extracted driver parses" bash -n "$DRIVER"

new_logs() { CURL_LOG="$(mktemp "$STUB_DIR/curl.XXXXXX")"; BODY_LOG="$(mktemp "$STUB_DIR/body.XXXXXX")"; }

# One flip per environment, exactly as the role path does (dev env first, then prd env), under
# the same shell options as flip.sh.
run_flips() { # caller sets STUB_* knobs; <segment-id> <enabled>
  PATH="$STUB_DIR:$PATH" CURL_LOG="$CURL_LOG" BODY_LOG="$BODY_LOG" \
    STUB_DEV_SEG="${STUB_DEV_SEG:-}" STUB_ROW_ID="${STUB_ROW_ID:-}" STUB_NO_OVERRIDE="${STUB_NO_OVERRIDE:-0}" \
    STUB_FORCE_REJECT="${STUB_FORCE_REJECT:-0}" \
    bash -c 'set -euo pipefail; source "$1"; flip_segment_in_env 90722 777 "$2" "$3" >/dev/null; flip_segment_in_env 90721 777 "$2" "$3" >/dev/null' \
    _ "$DRIVER" "$1" "$2"
}

# Every captured body is ONE valid JSON object equal to the whole expected body (dev env first).
bodies_ok() { # <dev-row-id> <prd-row-id> <segment-id> <true|false>
  python3 - "$BODY_LOG" "$1" "$2" "$3" "$4" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
rows, seg, en = [int(sys.argv[2]), int(sys.argv[3])], int(sys.argv[4]), sys.argv[5] == "true"
def want(row):
    return {
        "feature_states_to_create": [],
        "feature_states_to_update": [{
            "feature_segment": {"id": row, "segment": seg},
            "enabled": en,
            "feature_state_value": {"type": "unicode", "string_value": None, "integer_value": None, "boolean_value": None},
        }],
        "segment_ids_to_delete_overrides": [],
        "publish_immediately": True,
    }
if len(lines) != 2:
    print("expected 2 bodies, got %d" % len(lines), file=sys.stderr); sys.exit(1)
for l, row in zip(lines, rows):
    if json.loads(l) != want(row):
        print("body mismatch:\n  got  %s\n  want %s" % (l, json.dumps(want(row))), file=sys.stderr); sys.exit(1)
PY
}

create_bodies_ok() { # <segment-id> <true|false>: the create arm still sends {segment} only
  python3 - "$BODY_LOG" "$1" "$2" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
seg, en = int(sys.argv[2]), sys.argv[3] == "true"
want = {
    "feature_states_to_create": [{
        "feature_segment": {"segment": seg},
        "enabled": en,
        "feature_state_value": {"type": "unicode", "string_value": None, "integer_value": None, "boolean_value": None},
    }],
    "feature_states_to_update": [],
    "segment_ids_to_delete_overrides": [],
    "publish_immediately": True,
}
if len(lines) != 2:
    print("expected 2 bodies, got %d" % len(lines), file=sys.stderr); sys.exit(1)
for l in lines:
    if json.loads(l) != want:
        print("create body mismatch:\n  got  %s\n  want %s" % (l, json.dumps(want)), file=sys.stderr); sys.exit(1)
PY
}

is_equal() { [[ "$1" == "$2" ]]; }
contains() { [[ "$1" == *"$2"* ]]; }
only_stubbed_hosts() {
  [[ -s "$CURL_LOG" ]] || return 1
  ! grep -qvE '^(GET|POST) https://api\.flagsmith\.com/' "$CURL_LOG"
}
# Best-effort sweep for the printf spelling only (a jq/python builder would not match it). No id-only feature_segment printf body survives anywhere in the skill scripts (a second builder
# of the rejected shape would be outside the extracted window), and the fixed shape is present
# (so the sweep cannot pass vacuously).
no_id_only_builder() { ! grep -rqE --include='*.sh' 'feature_segment":\{"id":%d\}' "$SKILLS_DIR"; }
fixed_builder_present() { grep -rqE --include='*.sh' 'feature_segment":\{"id":%d,"segment":%d\}' "$SKILLS_DIR"; }
# assert must be able to go red: run it on a failing command and require its failure flag to move.
assert_can_fail() { local fail=0 checks=0; assert "control" false 2>/dev/null; [[ "$fail" -eq 1 ]]; }

# --- 0. instrument: the stub must be in force, and must be able to return the bad answer ------
# Reported without the assert helper it guards: a neutered assert would otherwise report this
# control's own failure through itself and leave the suite green.
checks=$((checks + 1))
if ! assert_can_fail; then
  printf 'flip-update-existing-override: FAIL — assert cannot go red (its failure flag never moved)\n' >&2
  exit 1
fi
assert "curl resolves to the stub dir" is_equal "$(PATH="$STUB_DIR:$PATH" command -v curl)" "$STUB_DIR/curl"
new_logs
seg_less='{"feature_states_to_create":[],"feature_states_to_update":[{"feature_segment":{"id":555},"enabled":true}],"segment_ids_to_delete_overrides":[],"publish_immediately":true}'
reject="$(CURL_LOG="$CURL_LOG" BODY_LOG="$BODY_LOG" \
  "$STUB_DIR/curl" -X POST -d "$seg_less" "https://example.invalid/environments/90722/features/777/versions/")"
assert "stub rejects an update body without feature_segment.segment (the live 2026-10-23 error)" \
  contains "$reject" '"segment": ["This field is required."]'
assert "stub did not record the rejected body as accepted" test ! -s "$BODY_LOG"
full='{"feature_states_to_create":[],"feature_states_to_update":[{"feature_segment":{"id":555,"segment":102},"enabled":true}],"segment_ids_to_delete_overrides":[],"publish_immediately":true}'
accept="$(CURL_LOG="$CURL_LOG" BODY_LOG="$BODY_LOG" \
  "$STUB_DIR/curl" -X POST -d "$full" "https://example.invalid/environments/90722/features/777/versions/")"
assert "stub accepts the id+segment body" contains "$accept" '"uuid":"v-uuid"'
new_logs
sibling="$(CURL_LOG="$CURL_LOG" BODY_LOG="$BODY_LOG" STUB_DEV_SEG=102 STUB_ROW_ID=555 \
  "$STUB_DIR/curl" "https://api.flagsmith.com/api/v1/features/feature-segments/?environment=90721&feature=777")"
assert "stub serves a non-matching sibling row first and a per-env row id second" \
  contains "$sibling" '{"id":9999,"segment":5102,"priority":2},{"id":1555,"segment":102,"priority":1}'
wrong_query="$(CURL_LOG="$CURL_LOG" BODY_LOG="$BODY_LOG" \
  "$STUB_DIR/curl" "https://api.flagsmith.com/api/v1/features/feature-segments/?environment=0&feature=0")"
assert "stub answers an empty result for a query flip.sh must not send" is_equal "$wrong_query" '{"results":[]}'

# --- 1. override exists in both envs: update arm, two POSTs, whole body correct -------------
new_logs
rc=0; STUB_DEV_SEG=102 STUB_ROW_ID=555 run_flips 102 true || rc=$?
assert "existing-override flip exits 0 (pre-fix this exits 3 on the live 400)" is_equal "$rc" 0
assert "two update bodies equal the expected whole body: dev row 555, prd row 1555, segment 102, enabled" bodies_ok 555 1555 102 true
assert "dev env 90722 got a version POST" grep -q 'POST .*/environments/90722/features/777/versions/' "$CURL_LOG"
assert "prd env 90721 got a version POST" grep -q 'POST .*/environments/90721/features/777/versions/' "$CURL_LOG"
assert "only the stubbed Flagsmith host was contacted" only_stubbed_hosts

# --- 2. different ids -> the bodies carry THOSE ids (no hard-coded canonical numbers) --------
new_logs
rc=0; STUB_DEV_SEG=202 STUB_ROW_ID=777 run_flips 202 true || rc=$?
assert "flip with other ids exits 0" is_equal "$rc" 0
assert "bodies carry dev row 777, prd row 1777, segment 202" bodies_ok 777 1777 202 true

# --- 3. disabling goes through the same arm with the same ids --------------------------------
new_logs
rc=0; STUB_DEV_SEG=102 STUB_ROW_ID=555 run_flips 102 false || rc=$?
assert "disable flip exits 0" is_equal "$rc" 0
assert "disable bodies equal the expected whole body with enabled=false in both" bodies_ok 555 1555 102 false

# --- 4. no existing override: the create arm is unchanged ({segment} only, no update item) ----
new_logs
rc=0; STUB_NO_OVERRIDE=1 STUB_DEV_SEG=102 run_flips 102 true || rc=$?
assert "first-time override flip exits 0" is_equal "$rc" 0
assert "create arm sends the whole expected create body (feature_segment {segment:102})" create_bodies_ok 102 true

# --- 5. a rejected version POST surfaces as exit 3 and records no accepted body --------------
new_logs
rc=0; STUB_FORCE_REJECT=1 STUB_DEV_SEG=102 STUB_ROW_ID=555 run_flips 102 true 2>/dev/null || rc=$?
assert "a rejected version POST exits 3 (the 2026-10-23 symptom)" is_equal "$rc" 3
assert "a rejected version POST leaves no accepted body" test ! -s "$BODY_LOG"

# --- 6. the input guards refuse before any request is sent ---------------------------------
new_logs
rc=0; STUB_DEV_SEG=102 STUB_ROW_ID=555 run_flips abc true 2>/dev/null || rc=$?
assert "a non-integer segment id is refused with exit 1" is_equal "$rc" 1
assert "a refused segment id sends no request" test ! -s "$CURL_LOG"
new_logs
rc=0; STUB_DEV_SEG=102 STUB_ROW_ID=555 run_flips 102 maybe 2>/dev/null || rc=$?
assert "a non-boolean enabled value is refused with exit 1" is_equal "$rc" 1
assert "a refused enabled value sends no request" test ! -s "$CURL_LOG"

# --- 7. census: no second builder of the rejected shape in the skill scripts -----------------
assert "no id-only feature_segment body is built anywhere in the skill scripts" no_id_only_builder
assert "the fixed id+segment body is present in the skill scripts (census is not vacuous)" fixed_builder_present

# anti-vacuity: the floor is reported without the assert helper it backstops. Its bound is a
# literal directly above the test, set to the current count: raise it in the same edit that adds a
# check (the meta-guard requires a `-lt` floor, so adding one without raising it passes silently).
MIN_CHECKS=31
if [[ "$checks" -lt "$MIN_CHECKS" ]]; then
  printf 'flip-update-existing-override: FAIL — only %d assertions ran (anti-vacuity floor %d)\n' "$checks" "$MIN_CHECKS" >&2
  exit 1
fi
if (( fail != 0 )); then
  printf 'flip-update-existing-override: FAILED (%d checks)\n' "$checks" >&2
  exit 1
fi
printf 'flip-update-existing-override: %d checks passed\n' "$checks"
