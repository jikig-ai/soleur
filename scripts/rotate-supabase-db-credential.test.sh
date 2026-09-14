#!/usr/bin/env bash
# rotate-supabase-db-credential.test.sh — end-to-end run of the rotation script
# against stub doppler/curl/docker on PATH. No network, no real credential.
#
# WHY IT EXISTS. Until #7966 the script had never completed a run: its hash
# verification read os.environ['TARGETS'] while `export TARGETS` sat two lines
# BELOW that block. The python KeyError'd, the verify block reported "at least
# one secret does NOT carry the new password", and the script bailed with exit 7
# AFTER the PATCH and the Doppler rewrite. So every run rotated the database and
# then skipped both the connectivity proof and the --leaked session sweep, and
# no test existed to notice. This one drives the whole sequence to "==> DONE".
#
# Every fixture value is synthesized (cq-test-fixtures-synthesized-only).
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/rotate-supabase-db-credential.sh"
cases=0; failures=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; failures=$((failures + 1)); }

REF=abcdefghijklmnopqrst
OLDPW=synthOldPw0000000000
# Scheme held in a variable so the fixture DSNs are not literal URL-with-password
# shapes (gitleaks database-url-with-password); they are synthesized regardless.
SCHEME=postgresql
POOL="${SCHEME}://postgres.${REF}:${OLDPW}@pooler.invalid:6543/postgres"
DIRECT="${SCHEME}://postgres:${OLDPW}@db.${REF}.invalid:5432/postgres"

# One owning trap: T names the current case's dir; each case rm's its own on the
# happy path, and this catches a case that dies mid-run.
T=""
trap 'rm -rf "${T:-}"' EXIT INT TERM HUP

setup() {
  T="$(mktemp -d)"
  mkdir -p "$T/bin" "$T/tmpdir"
  jq -n --arg p "$POOL" --arg d "$DIRECT" '{
    DATABASE_URL_POOLER: {computed: $p, raw: $p},
    DATABASE_URL:        {computed: $d, raw: $d},
    UNRELATED:           {computed: "nothing-here", raw: "nothing-here"}
  }' > "$T/secrets.json"

  # doppler: `secrets get NAME --plain`, `secrets --json`, `secrets set NAME`
  # (value on stdin), `configs --json`. Token lookups return a synthesized value.
  cat > "$T/bin/doppler" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
S="$STUB_STATE/secrets.json"
case "$1 ${2:-}" in
  "configs -p") echo '[{"name":"dev"}]' ;;
  "secrets get")
    name="$3"
    if [[ "$name" == SUPABASE_ACCESS_TOKEN ]]; then echo -n synth-token; exit 0; fi
    jq -e -j --arg k "$name" '.[$k].computed' "$S" 2>/dev/null || exit 1 ;;
  "secrets set")
    name="$3"; val="$(cat)"
    jq --arg k "$name" --arg v "$val" '.[$k] = {computed:$v, raw:$v}' "$S" > "$S.new" && mv "$S.new" "$S" ;;
  "secrets -p") cat "$S" ;;
  *) echo "stub doppler: unhandled: $*" >&2; exit 9 ;;
esac
STUB

  # curl: PATCH -> 200 with an empty body file; anything else -> the project list.
  cat > "$T/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; patch=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) [[ "$2" == PATCH ]] && patch=1; shift 2 ;;
    *) shift ;;
  esac
done
if [[ "$patch" -eq 1 ]]; then echo '{}' > "$out"; printf '%s' "${STUB_PATCH_CODE:-200}"; exit 0; fi
printf '[{"id":"%s"}]' "$STUB_REF"
STUB

  # docker: the connectivity probe prints 1; the sweep prints a count.
  cat > "$T/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_STATE/docker.log"
if [[ "$*" == *" -i "* ]]; then
  cat >/dev/null
  [[ -n "${STUB_SWEEP_FAIL:-}" ]] && { echo "ERROR:  permission denied" >&2; exit 3; }
  echo 2
else echo 1; fi
STUB
  chmod +x "$T/bin/"*
}

run() {
  set +e
  STUB_STATE="$T" STUB_REF="$REF" TMPDIR="$T/tmpdir" PATH="$T/bin:$PATH" \
    bash "$SCRIPT" "$@" > "$T/out" 2>&1
  rc=$?
  set -e
}

newpw_of() { jq -r --arg k "$1" '.[$k].computed' "$T/secrets.json" | sed -nE 's#^[a-z]+://[^:]+:([^@]*)@.*#\1#p'; }

echo "== T1: full --leaked run completes and rewrites both URLs"
setup; run --config dev --leaked
cases=$((cases + 1)); [[ "$rc" -eq 0 ]] && pass "exit 0" || { fail "exit $rc (want 0)"; sed 's/^/       | /' "$T/out"; }
cases=$((cases + 1)); grep -q '^==> DONE' "$T/out" && pass "reached DONE" || fail "did not reach DONE"
p="$(newpw_of DATABASE_URL_POOLER)"; d="$(newpw_of DATABASE_URL)"
cases=$((cases + 1)); [[ -n "$p" && "$p" != "$OLDPW" ]] && pass "pooler URL carries a new password" || fail "pooler URL not rotated"
cases=$((cases + 1)); [[ "$p" == "$d" ]] && pass "direct URL carries the same new password" || fail "direct and pooler diverge"
cases=$((cases + 1)); [[ "$(jq -r .UNRELATED.computed "$T/secrets.json")" == nothing-here ]] && pass "unrelated secret untouched" || fail "unrelated secret modified"
cases=$((cases + 1)); grep -q 'matches-new=True' "$T/out" && ! grep -q 'matches-new=False' "$T/out" && pass "hash verification ran and matched" || fail "hash verification did not report a match"
cases=$((cases + 1)); grep -q -- '--leaked: sweeping' "$T/out" && grep -q 'terminated=2' "$T/out" && pass "session sweep ran" || fail "session sweep did not run"
cases=$((cases + 1)); [[ -z "$(ls -A "$T/tmpdir" | grep soleur-rotation-recovery || true)" ]] && pass "no recovery file left behind" || fail "recovery file left behind on success"
cases=$((cases + 1)); ! grep -qF "$p" "$T/out" && ! grep -qF "$OLDPW" "$T/out" && pass "neither password printed" || fail "a password reached the output"
rm -rf "$T"

echo "== T2: a failed PATCH exits 6 and leaves Doppler untouched"
setup; STUB_PATCH_CODE=422; export STUB_PATCH_CODE; run --config dev; unset STUB_PATCH_CODE
cases=$((cases + 1)); [[ "$rc" -eq 6 ]] && pass "exit 6" || fail "exit $rc (want 6)"
cases=$((cases + 1)); [[ "$(newpw_of DATABASE_URL_POOLER)" == "$OLDPW" ]] && pass "Doppler unchanged" || fail "Doppler modified after failed PATCH"
rm -rf "$T"

echo "== T3: a failed --leaked sweep is loud (exit 8) and leaves no recovery file"
setup; STUB_SWEEP_FAIL=1; export STUB_SWEEP_FAIL; run --config dev --leaked; unset STUB_SWEEP_FAIL
cases=$((cases + 1)); [[ "$rc" -eq 8 ]] && pass "exit 8" || { fail "exit $rc (want 8)"; sed 's/^/       | /' "$T/out"; }
cases=$((cases + 1)); grep -q 'session sweep FAILED' "$T/out" && pass "failure is named" || fail "sweep failure not reported"
cases=$((cases + 1)); ! grep -q '^==> DONE' "$T/out" && pass "does not claim DONE" || fail "claimed DONE after a failed sweep"
cases=$((cases + 1)); [[ -z "$(ls -A "$T/tmpdir" | grep soleur-rotation-recovery || true)" ]] && pass "no recovery file left behind" || fail "recovery file left behind"
rm -rf "$T"

echo
echo "cases=$cases failures=$failures"
[[ "$failures" -eq 0 ]]
