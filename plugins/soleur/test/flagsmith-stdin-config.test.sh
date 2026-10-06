#!/usr/bin/env bash
# The four Flagsmith operator scripts (flag-create, flag-delete, flag-list, flag-set-role) send the
# management key on curl's STDIN config channel, never on its argument list (#9597): an
# `Authorization: Api-Key` header on argv is readable by every local user via /proc/<pid>/cmdline.
#
# These scripts are operator-run and write to production Flagsmith, so this suite never runs them.
# It extracts the shipped `_bearer_ok` + `fs_api` text from EACH script (anchored on the function
# markers, so the test follows the code and not a copy) and drives that exact text under a
# PATH-shim curl that records argv (NUL-delimited) and stdin. All tokens are synthesized.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to $REPO_ROOT" >&2; exit 2; }

TMPD="$(mktemp -d -t flagsmith-stdin.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT
case "$TMPD" in /*) : ;; *) echo "FATAL: scratch dir is not absolute" >&2; exit 2 ;; esac

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "[ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "[FAIL] $1" >&2; }

SCRIPTS=(
  plugins/soleur/skills/flag-create/scripts/create.sh
  plugins/soleur/skills/flag-delete/scripts/delete.sh
  plugins/soleur/skills/flag-list/scripts/list.sh
  plugins/soleur/skills/flag-set-role/scripts/flip.sh
)
FIXTURE="synthetic-flagsmith-key-0001"

# The shim: records argv and (only for `--config -`) stdin, exits 0.
SHIM="$TMPD/bin"; mkdir -p "$SHIM"
cat > "$SHIM/curl" <<'SHIM_EOF'
#!/usr/bin/env bash
d="${SHIM_DIR:?}"; n=0; [[ -r "$d/n" ]] && read -r n < "$d/n"; n=$((n + 1)); printf '%s\n' "$n" > "$d/n"
printf '%s\0' "$@" > "$d/$n.argv"
case " $* " in *" --config - "*) cat > "$d/$n.stdin" ;; esac
printf '{}'
SHIM_EOF
sed -i "1s|.*|#!$(type -P bash)|" "$SHIM/curl"; chmod +x "$SHIM/curl"

# extract_block <script> <outfile>: from the `_bearer_ok()` line through the closing `}` of fs_api().
extract_block() {
  awk '
    /^_bearer_ok\(\)/ { on = 1 }
    on { print }
    on && /^fs_api\(\)/ { inapi = 1 }
    on && inapi && /^}[[:space:]]*$/ { exit }
  ' "$1" > "$2"
  [[ -s "$2" ]] && grep -cF 'fs_api()' "$2" >/dev/null && grep -cF -e '--config -' "$2" >/dev/null
}

# drive <blockfile> <token> <rowdir>  -> rc of the harness; non-zero without a recorded call = refused
drive() {
  local block="$1" tok="$2" row="$3"
  mkdir -p "$row"
  env -i PATH="$SHIM:$(dirname "$(type -P bash)"):$(dirname "$(type -P cat)")" SHIM_DIR="$row" TOKEN="$tok" \
    "$(type -P bash)" -c 'set -u; . "$1"; _bearer_ok "$TOKEN" || exit 9; fs_api https://flagsmith.example.test/api/v1/features/' _ "$block" </dev/null >/dev/null 2>&1
}
argv_has() { grep -aqF -- "$2" "$1"; }

i=0
for s in "${SCRIPTS[@]}"; do
  i=$((i + 1)); name="$(basename "$s")"
  blk="$TMPD/$name.block"
  if extract_block "$s" "$blk"; then pass "$name: the shipped _bearer_ok + fs_api block is extractable and uses --config -"
  else fail "$name: could not extract an _bearer_ok + fs_api block that uses --config -"; continue; fi

  drive "$blk" "$FIXTURE" "$TMPD/r$i-ok"; rc=$?
  if [[ "$rc" -eq 0 && -e "$TMPD/r$i-ok/1.argv" ]] && ! argv_has "$TMPD/r$i-ok/1.argv" "$FIXTURE" \
     && ! argv_has "$TMPD/r$i-ok/1.argv" 'Api-Key' \
     && [[ "$(cat "$TMPD/r$i-ok/1.stdin" 2>/dev/null)" == "header = \"Authorization: Api-Key $FIXTURE\"" ]]; then
    pass "$name: a valid key is on curl's stdin config only (not in argv, no Api-Key header in argv)"
  else fail "$name: a valid key must be on stdin only (rc=$rc)"; fi

  hostile_ok=1
  for tok in $'syn-key\nurl = "http://127.0.0.1:9/x"' 'syn"key' 'syn key'; do
    j=$((j = ${j:-0} + 1)); drive "$blk" "$tok" "$TMPD/r$i-bad$j"; rc=$?
    # The extracted block carries the script's own `_bearer_ok "$TOKEN" || { …; exit 2; }` line, so a
    # refusal is rc 2 (the script's usage/prereq exit); the harness's own guard is rc 9. Either way no
    # curl call may have been recorded.
    if [[ "$rc" -eq 0 || -e "$TMPD/r$i-bad$j/1.argv" ]]; then hostile_ok=0; fi
  done
  if [[ "$hostile_ok" -eq 1 ]]; then pass "$name: a key with a newline+directive, a quote or a space is refused before any curl call"
  else fail "$name: a hostile key reached curl or was not refused"; fi

  # ordering + static pins on the real script text
  guard_line="$(grep -nF '_bearer_ok "$TOKEN"' "$s" | head -1 | cut -d: -f1)"
  first_use="$(grep -nE '^[^#]*\bfs_api (-|"|\$)' "$s" | grep -vE 'fs_api\(\)' | head -1 | cut -d: -f1)"
  if [[ -n "$guard_line" && -n "$first_use" && "$guard_line" -lt "$first_use" ]]; then pass "$name: the shape guard runs before the first fs_api call"
  else fail "$name: _bearer_ok must precede the first fs_api call (guard line '${guard_line:-none}', first use '${first_use:-none}')"; fi
  if [[ "$(grep -cE '^[^#]*-H "Authorization: Api-Key' "$s" || true)" == "0" ]]; then pass "$name: no curl carries an Authorization: Api-Key header on argv"
  else fail "$name: an Authorization: Api-Key header is back on a curl line"; fi
  # stdin is the curl CONFIG channel now: a body piped to `fs_api ... -d @-` would be parsed as config.
  if [[ "$(grep -cE '^[^#]*(\| *fs_api|fs_api[^|#]*(-d|--data[a-z-]*|-T) +@-)' "$s" || true)" == "0" ]]; then pass "$name: no fs_api call takes its body on stdin (stdin is the curl config channel)"
  else fail "$name: an fs_api call takes its body on stdin (-d @- / piped), which conflicts with the stdin config"; fi
done

# MUTATION: restoring the argv form in an extracted block must turn the valid-key assertion RED.
blk="$TMPD/mutant.block"
extract_block "${SCRIPTS[0]}" "$blk" || { echo "FATAL: cannot extract the mutation seed" >&2; exit 2; }
text="$(cat "$blk"; printf x)"; text="${text%x}"
from='< <(printf '"'"'header = "Authorization: Api-Key %s"\n'"'"' "$TOKEN")'
[[ "$text" == *"$from"* ]] || { echo "FATAL: mutation did not land (stdin form not found)" >&2; exit 2; }
printf '%s' "${text/"$from"/'-H "Authorization: Api-Key $TOKEN"'}" > "$blk"
drive "$blk" "$FIXTURE" "$TMPD/mut"; rc=$?
if [[ "$rc" -eq 0 ]] && argv_has "$TMPD/mut/1.argv" "$FIXTURE"; then pass "mutation: restoring the argv form puts the key in a recorded argv (the valid-key row would go RED)"
else fail "mutation: the argv-restored mutant did not show the key in argv (rc=$rc); the assertions cannot see the regression"; fi
# The mutant must also FAIL the shipped valid-key predicate (stdin carries the exact header line and the
# key is absent from argv) — proves the row above is red on the regression, not merely that the shim saw it.
if [[ "$(cat "$TMPD/mut/1.stdin" 2>/dev/null)" != "header = \"Authorization: Api-Key $FIXTURE\"" ]] && argv_has "$TMPD/mut/1.argv" 'Api-Key'; then pass "mutation: the valid-key predicate (exact stdin line, no Api-Key in argv) goes RED on the argv-restored mutant"
else fail "mutation: the argv-restored mutant still satisfies the valid-key predicate; the stdin-only assertion is vacuous"; fi

echo "=== flagsmith-stdin-config: $PASS passed, $FAIL failed ==="
if [[ "$((PASS + FAIL))" -lt 26 ]]; then
  printf 'anti-vacuity floor: ran %s assertions, expected at least 26 — an assertion row was deleted\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
