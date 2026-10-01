#!/usr/bin/env bash
# Suite for workspaces-plaintext-hold-9348.sh: drives every exit arm through a stub gh and a fixed clock.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/workspaces-plaintext-hold-9348.sh"
SUITE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/ft-hold-9348.XXXXXX")
trap 'rm -rf "$SUITE_TMP"' EXIT

pass=0; failc=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
no() { failc=$((failc + 1)); printf 'FAIL %s\n' "$1"; }

# Reporter self-test: each helper must move its own counter, or the verdict below means nothing.
ok "selftest-ok" >/dev/null; no "selftest-no" >/dev/null
if [ "$pass" -ne 1 ] || [ "$failc" -ne 1 ]; then
  printf 'INSTRUMENT FAIL: pass/fail=%s/%s after one call each\n' "$pass" "$failc" >&2
  exit 2
fi
pass=0; failc=0

# Stub gh: PR_OUT / PR_RC answer `pr view`; RUN_OUT / RUN_RC answer `run list`.
STUB="$SUITE_TMP/gh"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view")  printf '%s' "${PR_OUT:-}";  exit "${PR_RC:-0}" ;;
  "run list") printf '%s' "${RUN_OUT:-}"; exit "${RUN_RC:-0}" ;;
esac
exit 99
STUBEOF
chmod +x "$STUB"

BEFORE=$(date -u -d '2026-10-05T12:00:00Z' +%s)
AFTER=$(date -u -d '2026-10-15T00:00:00Z' +%s)
OPEN='{"state":"OPEN","mergedAt":null}'

# case <name> <want-rc> <want-substring> [VAR=val ...]
case_() {
  local name=$1 want=$2 sub=$3; shift 3
  local out rc
  out=$(env GH_BIN="$STUB" "$@" bash "$PROBE" 2>&1); rc=$?
  if [ "$rc" -eq "$want" ] && [[ "$out" == *"$sub"* ]]; then ok "$name"
  else no "$name (rc=$rc want=$want out=${out:0:160})"; fi
}

case_ merged            0 "PASS"             PR_OUT='{"state":"MERGED","mergedAt":"2026-10-03T10:00:00Z"}' NOW_EPOCH="$AFTER"
case_ closed-unmerged   5 "WITHOUT merging"  PR_OUT='{"state":"CLOSED","mergedAt":null}' NOW_EPOCH="$BEFORE"
case_ open-at-deadline  5 "2026-10-15"       PR_OUT="$OPEN" RUN_OUT='[]' NOW_EPOCH="$AFTER"
case_ open-no-forget    2 "NOT YET"          PR_OUT="$OPEN" RUN_OUT='[]' NOW_EPOCH="$BEFORE"
case_ forget-recent     2 "<48 h"            PR_OUT="$OPEN" RUN_OUT='[{"databaseId":1,"updatedAt":"2026-10-05T00:00:00Z"}]' NOW_EPOCH="$BEFORE"
case_ forget-stale      5 ">48 h"            PR_OUT="$OPEN" RUN_OUT='[{"databaseId":1,"updatedAt":"2026-10-03T11:59:59Z"}]' NOW_EPOCH="$BEFORE"
case_ forget-at-bound   2 "<48 h"            PR_OUT="$OPEN" RUN_OUT='[{"databaseId":1,"updatedAt":"2026-10-03T12:00:00Z"}]' NOW_EPOCH="$BEFORE"
case_ pr-view-fails     3 "CANNOT ESTABLISH" PR_RC=1 NOW_EPOCH="$BEFORE"
case_ pr-state-garbage  3 "CANNOT ESTABLISH" PR_OUT='not json' NOW_EPOCH="$BEFORE"
case_ run-list-fails    3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_RC=1 NOW_EPOCH="$BEFORE"
case_ run-list-garbage  3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_OUT='nope' NOW_EPOCH="$BEFORE"
case_ forget-bad-date   3 "CANNOT ESTABLISH" PR_OUT="$OPEN" RUN_OUT='[{"databaseId":1,"updatedAt":"yesterday-ish"}]' NOW_EPOCH="$BEFORE"

# Source pins: read-only — the probe never writes through gh.
if grep -vE '^\s*#' "$PROBE" | grep -qE '"\$GH" (pr (merge|close|edit|ready)|workflow run|issue (close|edit)|api)'; then
  no "probe-read-only (a gh write verb appears)"
else ok "probe-read-only"; fi

printf '\n%s passed, %s failed\n' "$pass" "$failc"
if [ "$pass" -lt 13 ]; then
  printf 'FAIL: ran only %s passing assertions (<13)\n' "$pass" >&2
  exit 1
fi
[ "$failc" -eq 0 ]
