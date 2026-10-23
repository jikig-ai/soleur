#!/usr/bin/env bash
# Regression test: flip.sh flip_segment_in_env on a flag whose segment override ALREADY EXISTS.
#
# flip_segment_in_env has two arms. The first-time arm creates the override
# (feature_states_to_create, feature_segment {segment}). The existing-override arm updates it
# (feature_states_to_update). On 2026-10-23 the update arm sent feature_segment {id} only and
# Flagsmith answered {"feature_states_to_update":[{"feature_segment":{"segment":["This field is
# required."]}}]}, so a real flip of an existing override exited 3 with nothing written.
#
# The curl stub below REJECTS an update item whose feature_segment lacks `segment` with that exact
# JSON, so reverting the fix turns this suite red (a stub that answers 200 to everything cannot).
# It also parses each accepted body as JSON and requires BOTH ids to equal the stubbed row and
# segment, so a fix that hard-codes numbers or swaps the two fields fails too.
#
# The function is extracted from the script by CONTENT (flip.sh runs its main flow when sourced and
# its write path needs a typed `yes`, which the ack guard refuses inside an agent session by
# design). Calling the function directly needs no pty and reaches no audit row, no Doppler and no
# network: PATH is shadowed by a stub curl. The typed-yes plumbing around it stays covered by
# operator-ack-guard.test.sh and audit-flag-flip.test.sh.
#
# FLIP may be overridden to test a mutated copy; the copy can sit anywhere (nothing is sourced
# relative to it).
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
FLIP="${FLIP:-$REPO_ROOT/plugins/soleur/skills/flag-set-role/scripts/flip.sh}"
MIN_CHECKS=20
fail=0
checks=0

assert() { # <description> <command...>
  local desc="$1"; shift
  checks=$((checks + 1))
  if ! "$@"; then
    echo "update-override: FAIL — $desc" >&2
    fail=1
  fi
}

STUB_DIR="$(mktemp -d)"; trap 'rm -rf "$STUB_DIR"' EXIT

# Flagsmith stub. Knobs: STUB_DEV_SEG (the segment id served for the override row), STUB_ROW_ID (the
# existing feature-segment row id), STUB_NO_OVERRIDE=1 (no existing row -> create arm).
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
case "$url" in
  *"/feature-segments/"*)
    if [[ "${STUB_NO_OVERRIDE:-0}" == "1" ]]; then echo '{"results":[]}'
    else printf '{"results":[{"id":%s,"segment":%s,"priority":1}]}' "$ROW" "$SEG"; fi
    exit 0 ;;
  *"/versions/"*)
    if [[ "$method" != "POST" ]]; then echo '{"results":[{"uuid":"v-uuid","is_live":true}]}'; exit 0; fi
    verdict="$(DATA="$data" python3 -c '
import json, os, sys
try:
    d = json.loads(os.environ["DATA"])
except Exception:
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
  *) echo '{}'; exit 0 ;;
esac
STUB
chmod +x "$STUB_DIR/curl"

extract_fn() { # <name>: from the line "name() {" through the first line that is exactly "}"
  awk -v n="$1" '$0 ~ ("^" n "\\(\\) \\{") {p=1} p {print} p && /^}$/ {exit}' "$FLIP"
}

# Content anchors: refuse an extraction that lacks the constructs that define the function. A
# truncated or empty extraction still parses and answers, which is worse than an absent one.
has_construct() { [[ "$(extract_fn "$1")" == *"$2"* ]]; }
assert "extracted fs_api carries the curl call" has_construct fs_api 'curl'
assert "extracted read_feature_segment_id carries the feature-segments read" has_construct read_feature_segment_id 'feature-segments'
assert "extracted flip_segment_in_env carries the update arm" has_construct flip_segment_in_env 'feature_states_to_update'
assert "extracted flip_segment_in_env carries the create arm" has_construct flip_segment_in_env 'feature_states_to_create'

DRIVER="$STUB_DIR/driver.sh"
{
  echo 'TOKEN=fake-token; FLAGSMITH_API=https://api.flagsmith.com/api/v1'
  extract_fn fs_api
  extract_fn read_feature_segment_id
  extract_fn flip_segment_in_env
} > "$DRIVER"

new_logs() { CURL_LOG="$(mktemp)"; BODY_LOG="$(mktemp)"; }

# One flip per environment, exactly as the role path does (dev env first, then prd env).
run_flips() { # caller sets STUB_* knobs; <segment-id> <enabled>
  PATH="$STUB_DIR:$PATH" CURL_LOG="$CURL_LOG" BODY_LOG="$BODY_LOG" \
    STUB_DEV_SEG="${STUB_DEV_SEG:-}" STUB_ROW_ID="${STUB_ROW_ID:-}" STUB_NO_OVERRIDE="${STUB_NO_OVERRIDE:-0}" \
    bash -c 'source "$1"; flip_segment_in_env 90722 777 "$2" "$3" >/dev/null; flip_segment_in_env 90721 777 "$2" "$3" >/dev/null' \
    _ "$DRIVER" "$1" "$2"
}

bodies_ok() { # <expected-count> <row-id> <segment-id>; every captured body is ONE valid JSON object
  python3 - "$BODY_LOG" "$1" "$2" "$3" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
want, row, seg = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
if len(lines) != want:
    sys.exit(1)
for l in lines:
    d = json.loads(l)
    ups = d["feature_states_to_update"]
    if d["feature_states_to_create"] != [] or len(ups) != 1 or ups[0]["feature_segment"] != {"id": row, "segment": seg}:
        sys.exit(1)
PY
}

create_bodies_ok() { # <expected-count> <segment-id>: the create arm still sends {segment} only
  python3 - "$BODY_LOG" "$1" "$2" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
want, seg = int(sys.argv[2]), int(sys.argv[3])
if len(lines) != want:
    sys.exit(1)
for l in lines:
    d = json.loads(l)
    cr = d["feature_states_to_create"]
    if d["feature_states_to_update"] != [] or len(cr) != 1 or cr[0]["feature_segment"] != {"segment": seg}:
        sys.exit(1)
PY
}

is_equal() { [[ "$1" == "$2" ]]; }
contains() { [[ "$1" == *"$2"* ]]; }
only_stubbed_hosts() { ! grep -vE '^(GET|POST) https://api\.flagsmith\.com/' "$CURL_LOG"; }

# --- 0. instrument: the stub must be in force, and must be able to return the bad answer ------
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

# --- 1. override exists in both envs: update arm, two POSTs, both ids correct ----------------
new_logs
rc=0; STUB_DEV_SEG=102 STUB_ROW_ID=555 run_flips 102 true || rc=$?
assert "existing-override flip exits 0 (pre-fix this exits 3 on the live 400)" is_equal "$rc" 0
assert "two update POSTs, one per environment, each one valid JSON with id=555 segment=102" bodies_ok 2 555 102
assert "dev env 90722 got a version POST" grep -q 'POST .*/environments/90722/features/777/versions/' "$CURL_LOG"
assert "prd env 90721 got a version POST" grep -q 'POST .*/environments/90721/features/777/versions/' "$CURL_LOG"
assert "only the stubbed Flagsmith host was contacted" only_stubbed_hosts

# --- 2. H2: different ids -> the bodies carry THOSE ids (no hard-coded canonical numbers) ------
new_logs
rc=0; STUB_DEV_SEG=202 STUB_ROW_ID=777 run_flips 202 true || rc=$?
assert "flip with other ids exits 0" is_equal "$rc" 0
assert "bodies carry id=777 segment=202" bodies_ok 2 777 202

# --- 3. disabling goes through the same arm with the same ids -------------------------------
new_logs
rc=0; STUB_DEV_SEG=102 STUB_ROW_ID=555 run_flips 102 false || rc=$?
assert "disable flip exits 0" is_equal "$rc" 0
assert "disable bodies carry id=555 segment=102" bodies_ok 2 555 102
assert "disable bodies set enabled=false" grep -q '"enabled":false' "$BODY_LOG"

# --- 4. no existing override: the create arm is unchanged ({segment} only, no update item) ----
new_logs
rc=0; STUB_NO_OVERRIDE=1 STUB_DEV_SEG=102 run_flips 102 true || rc=$?
assert "first-time override flip exits 0" is_equal "$rc" 0
assert "create arm sends feature_segment {segment:102} and no update item" create_bodies_ok 2 102

# anti-vacuity: the floor is reported without the assert helper it backstops
if (( checks < MIN_CHECKS )); then
  printf 'update-override: FAIL — only %d checks ran (floor %d)\n' "$checks" "$MIN_CHECKS" >&2
  exit 1
fi
if (( fail != 0 )); then
  printf 'update-override: FAILED (%d checks)\n' "$checks" >&2
  exit 1
fi
printf 'update-override: %d checks passed\n' "$checks"
