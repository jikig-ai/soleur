#!/usr/bin/env bash
# Guard 4 (#12937): the tunnel-zone authority step in .github/workflows/scheduled-terraform-drift.yml.
#
# PROPERTY. When the zone that carries the tunnel CNAMEs (TF output `cf_tunnel_zone_id`) is not
# `active`, or the public NS for its name (DoH, 1.1.1.1) differ from its `name_servers`, exactly
# one deduped `ci/tunnel-zone-authority` issue exists and its body says so. A check that could
# not measure (empty zone id, unreadable zone, failed DoH) files under the same label as
# `state=unavailable` — never clean, never a close. A healthy run closes an open issue.
#
# HOW. The step is selected with PyYAML and its `run:` body executed under
# `bash --noprofile --norc -eo pipefail` (the runner's invocation for a run: with no shell: key),
# with terraform, doppler, curl and gh stubbed on PATH. Every value is synthesized.
#
# MUTATION MATRIX (plan Guard 4) — run 2026-11-19 against pristine copies, restored after; every code row RED:
#   1  fixture zone `status: moved`                          RED-as-designed: Z1 files
#   2  fixture public NS laila/lennon vs zone NS bradley/nora RED-as-designed: Z2 files
#   3  DoH curl rc != 0                                      RED-as-designed: Z3 unavailable, never clean
#   4  zone id resolves empty                                RED-as-designed: Z4 refuses, no zone read
#   code mutations, each turns a row RED:
#   a  drop the status check                                 Z1
#   b  compare NS without sorting / as raw order             Z5 (must-pass, different order)
#   c  treat DoH failure as healthy                          Z3
#   d  compare when the zone id is empty                     Z4
#   e  close on `unavailable`                                Z6
#   f  create without the dedupe read                        Z7
#   g  bearer in argv                                        Z8
#   h  every row skipped                                     the row floor
#   i  an unavailable run rewrites the open issue            Z6
#   j  drift without ::error:: / no escalation output        Z10 / Z12
#   k  the email step loses a leg                            W3
#   l  drop the DoH type==2 filter                           Z11
#   m  drop the token charset refusal                        Z13
#   n  a failed close reports escalation ok                  Z5c
#   o  GH_TOKEN or DOPPLER_TOKEN dropped from the step env:   W4 (and every filing row)
#   p  the token refusal narrowed to one character class     the matching Z13 row
#
# Run: bash plugins/soleur/test/terraform-drift-tunnel-zone-authority.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${REPO_ROOT:?repo root resolved empty}"
WF="${TERRAFORM_DRIFT_WF:-$REPO_ROOT/.github/workflows/scheduled-terraform-drift.yml}"

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 missing; this suite asserted nothing"; exit 1; }
python3 -I -c 'import yaml' 2>/dev/null || { echo "FAIL: PyYAML missing; this suite asserted nothing"; exit 1; }

export TMPDIR="${TMPDIR:-/var/tmp}"
TMP=$(mktemp -d -t tunnel-zone-auth.XXXXXXXX) || { echo "FATAL: cannot create scratch dir" >&2; exit 2; }
[[ -n "$TMP" && "$TMP" == /* && -d "$TMP" ]] || { echo "FATAL: bad scratch dir" >&2; exit 2; }
trap 'rm -rf -- "$TMP"' EXIT

PASS=0
FAIL=0
ROWS=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { if [[ "$2" == "1" ]]; then pass "$1"; else fail "$1"; fi; }
# Instrument self-test: one pass and one fail through `check` must move both counters, then are subtracted.
_p0=$PASS; _f0=$FAIL
check "self-test" 1 >/dev/null; check "self-test" 0 >/dev/null
(( PASS == _p0 + 1 && FAIL == _f0 + 1 )) || { printf 'FATAL: check/pass/fail do not move their counters\n' >&2; exit 1; }
PASS=$_p0; FAIL=$_f0

BODY="$TMP/step.sh"
STEP_META="$TMP/step.meta"
STEP_ENV="$TMP/step.env"
# The step's env: map is DERIVED from the YAML (never hand-copied): each ${{ }} expression maps to one synthetic
# value, an unknown expression is fatal, and the body runs with exactly that env.
python3 -I - "$WF" "$BODY" "$STEP_META" "$STEP_ENV" <<'PY' || { echo "FATAL: tunnel_zone step not found in $WF (or its env: has an unmapped expression)" >&2; exit 2; }
import sys, yaml
wf, out, meta, envf = sys.argv[1:5]
SYNTH = {"${{ github.token }}": "synthetic-gh", "${{ github.server_url }}": "https://github.example",
         "${{ github.repository }}": "o/r", "${{ github.run_id }}": "1", "${{ secrets.DOPPLER_TOKEN }}": "synthetic-doppler"}
for name, job in yaml.safe_load(open(wf))["jobs"].items():
    for st in job.get("steps") or []:
        if st.get("id") == "tunnel_zone":
            open(out, "w").write(st["run"])
            open(meta, "w").write("job=%s\nif=%s\ncoe=%s\nwd=%s\n" % (name, st.get("if"), st.get("continue-on-error"), st.get("working-directory")))
            with open(envf, "w") as f:
                for k, v in (st.get("env") or {}).items():
                    v = str(v)
                    if "${{" in v and v not in SYNTH:
                        raise SystemExit(3)
                    f.write("%s=%s\t%s\n" % (k, SYNTH.get(v, v), v))
            raise SystemExit(0)
raise SystemExit(2)
PY
[[ -s "$BODY" ]] || { echo "FATAL: empty run body" >&2; exit 2; }
STEP_ENV_ARGS=()
while IFS=$'\t' read -r _kv _expr; do STEP_ENV_ARGS+=("$_kv"); done < "$STEP_ENV"

STUB="$TMP/bin"; mkdir -p "$STUB"
mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$STUB/$1"; chmod +x "$STUB/$1"; }
ZID="0123456789abcdef0123456789abcdef"
CF_SENTINEL="synthcf$((6 * 7))tokenNOTREAL"
mk terraform '[[ "$*" == "output -raw cf_tunnel_zone_id" ]] || exit 64; [[ "${MOCK_TF_RC:-0}" == 0 ]] || exit "$MOCK_TF_RC"; printf "%s" "${MOCK_ZONE_ID}"'
# The stubs refuse without the credentials the real CLIs need, so a dropped env: mapping turns rows red.
mk doppler '[[ -n "${DOPPLER_TOKEN:-}" && "${DOPPLER_PROJECT:-}" == soleur && "${DOPPLER_CONFIG:-}" == prd_terraform ]] || exit 1; printf "%s" "${MOCK_CF_TOKEN:-}"'
# curl: log argv + stdin config; the zone read writes MOCK_ZONE_JSON to -o; DoH prints MOCK_DOH_JSON.
# Quoted heredoc so the canonical assert_fixture_dir can be copied in byte-for-byte: the -o
# operand comes from the workflow under test, so the stub refuses a relative or degenerate one
# before writing to it.
cat > "$STUB/curl" <<'CURL_STUB'
#!/usr/bin/env bash
case " $* " in *" --config - "*) cat >> "$MOCK_LOG.stdin" ;; esac
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
printf "%s\n" "$*" >> "$MOCK_LOG.curl"
out=""; url=""; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in -o) out="${args[$((i+1))]}" ;; https://*) url="${args[$i]}" ;; esac
done
case "$url" in
  https://api.cloudflare.com/*)
    [[ "${MOCK_ZONE_RC:-0}" == 0 ]] || exit "$MOCK_ZONE_RC"
    assert_fixture_dir "$out"
    printf "%s" "$MOCK_ZONE_JSON" > "$out" ;;
  https://1.1.1.1/dns-query*)   [[ "${MOCK_DOH_RC:-0}" == 0 ]] || exit "$MOCK_DOH_RC"; printf "%s" "$MOCK_DOH_JSON" ;;
  *) exit 64 ;;
esac
CURL_STUB
chmod +x "$STUB/curl"
mk gh '
[[ -n "${GH_TOKEN:-}" ]] || exit 4
printf "%s\n" "$*" >> "$MOCK_LOG.gh"
case "$1 $2" in
  "issue list") [[ "${MOCK_LIST_RC:-0}" == 0 ]] || exit "$MOCK_LIST_RC"; printf "%s" "${MOCK_EXISTING:-}" ;;
  "issue create") [[ "${MOCK_CREATE_RC:-0}" == 0 ]] || exit "$MOCK_CREATE_RC" ;;&
  "issue comment") [[ "${MOCK_COMMENT_RC:-0}" == 0 ]] || exit "$MOCK_COMMENT_RC"; exit 0 ;;
  "issue close") [[ "${MOCK_CLOSE_RC:-0}" == 0 ]] || exit "$MOCK_CLOSE_RC" ;;&
  "issue create"|"issue edit"|"issue close"|"label create")
    for ((i=1; i<=$#; i++)); do [[ "${!i}" == --body-file ]] && { j=$((i+1)); cp "${!j}" "$MOCK_LOG.body"; }; done
    exit 0 ;;
esac
exit 0'

zone_json() { # status, ns...
  local st="$1"; shift
  local ns="" n
  for n in "$@"; do ns="${ns:+$ns,}\"$n\""; done
  printf '{"success":true,"result":{"id":"%s","name":"soleur.ai","status":"%s","name_servers":[%s]}}' "$ZID" "$st" "$ns"
}
doh_json() { # ns...
  local a="" n
  for n in "$@"; do a="${a:+$a,}{\"name\":\"soleur.ai\",\"type\":2,\"TTL\":300,\"data\":\"$n.\"}"; done
  printf '{"Status":0,"Answer":[%s]}' "$a"
}
OK_ZONE="$(zone_json active laila.ns.cloudflare.com lennon.ns.cloudflare.com)"
OK_DOH="$(doh_json lennon.ns.cloudflare.com laila.ns.cloudflare.com)"   # different ORDER, same set

RC=""; LOG=""; GHOUT=""; OUT=""
run_step() { # <label> VAR=value ...
  local label="$1"; shift
  LOG="$TMP/$label"; GHOUT="$TMP/$label.ghout"; OUT="$TMP/$label.out"
  : > "$LOG.curl"; : > "$LOG.gh"; : > "$LOG.stdin"; : > "$GHOUT"; rm -f "$LOG.body"
  mkdir -p "$TMP/rt-$label"
  env -i PATH="$STUB:/usr/bin:/bin" HOME="$TMP" TMPDIR="$TMPDIR" RUNNER_TEMP="$TMP/rt-$label" \
    GITHUB_OUTPUT="$GHOUT" "${STEP_ENV_ARGS[@]}" \
    MOCK_LOG="$LOG" MOCK_ZONE_ID="$ZID" MOCK_CF_TOKEN="$CF_SENTINEL" \
    MOCK_ZONE_JSON="$OK_ZONE" MOCK_DOH_JSON="$OK_DOH" "$@" \
    bash --noprofile --norc -eo pipefail "$BODY" > "$OUT" 2>&1
  RC=$?
}
state() { grep -E '^state=' "$GHOUT" | tail -1 | cut -d= -f2; }
created() { grep -c '^issue create' "$LOG.gh" || true; }
closed() { grep -c '^issue close' "$LOG.gh" || true; }
edited() { grep -cE '^issue edit [0-9]+ --title' "$LOG.gh" || true; }
commented() { grep -c '^issue comment' "$LOG.gh" || true; }
escalation() { grep -E '^escalation=' "$GHOUT" | tail -1 | cut -d= -f2; }

echo "=== wiring ==="
ROWS=$((ROWS + 1))
_ok=1
grep -qxF 'job=drift-check' "$STEP_META" || _ok=0
grep -qxF "if=always() && matrix.directory == 'apps/web-platform/infra'" "$STEP_META" || _ok=0
grep -qxF 'coe=True' "$STEP_META" || _ok=0
grep -qxF 'wd=apps/web-platform/infra' "$STEP_META" || _ok=0
grep -qF '${{' "$BODY" && _ok=0
check "W1: one step in drift-check, infra leg only, always(), continue-on-error, no \${{ }} in the body" "$_ok"

ROWS=$((ROWS + 1))
_ok=1
for _m in 'GH_TOKEN=synthetic-gh	${{ github.token }}' 'DOPPLER_TOKEN=synthetic-doppler	${{ secrets.DOPPLER_TOKEN }}' \
          'DOPPLER_PROJECT=soleur	soleur' 'DOPPLER_CONFIG=prd_terraform	prd_terraform' 'SERVER_URL=https://github.example	${{ github.server_url }}' \
          'REPOSITORY=o/r	${{ github.repository }}' 'RUN_ID=1	${{ github.run_id }}'; do
  grep -qxF "$_m" "$STEP_ENV" || _ok=0
done
check "W4: the step env: declares every mapping its body reads (GH_TOKEN, DOPPLER_*, SERVER_URL, REPOSITORY, RUN_ID)" "$_ok"

ROWS=$((ROWS + 1))
_ok=1
# Linted in a sandbox root holding ONLY this workflow, so the row measures this file.
mkdir -p "$TMP/lintroot/.github/workflows" && cp "$WF" "$TMP/lintroot/.github/workflows/scheduled-terraform-drift.yml" || _ok=0
_lint="$(python3 -I "$REPO_ROOT/scripts/lint-gh-dedupe-shape.py" --root "$TMP/lintroot" 2>&1)" || _ok=0
[[ "$_lint" == *"unclassified: 0"* ]] || _ok=0
[[ "$_lint" =~ scanned\ 1\ file ]] || _ok=0
check "W2: the dedupe capture passes scripts/lint-gh-dedupe-shape.py" "$_ok"

ROWS=$((ROWS + 1))
# The step is continue-on-error, so its only other channel is an email gated on drift, a failed issue write, or a failed step.
_w3="$(python3 -I - "$WF" <<'PY'
import sys, yaml
for job in yaml.safe_load(open(sys.argv[1]))["jobs"].values():
    st = job.get("steps") or []
    for i, s in enumerate(st):
        if s.get("id") == "tunnel_zone":
            for e in st[i + 1:]:
                cond = " ".join(str(e.get("if", "")).split())
                if e.get("uses") == "./.github/actions/notify-ops-email" and "steps.tunnel_zone" in cond:
                    print(cond)
                    raise SystemExit(0)
PY
)"
_ok=1
[[ "$_w3" == "always() && ("* ]] || _ok=0
for _leg in "steps.tunnel_zone.outputs.state == 'drift'" "steps.tunnel_zone.outputs.escalation == 'failed'" "steps.tunnel_zone.outcome == 'failure'"; do
  [[ "$_w3" == *"$_leg"* ]] || _ok=0
done
check "W3: a notify-ops email follows the step, gated on drift, escalation=failed or a failed step (got: ${_w3:-none})" "$_ok"

echo "=== must-pass ==="
ROWS=$((ROWS + 1))
run_step z5
_ok=1
[[ "$RC" == "0" && "$(state)" == healthy ]] || _ok=0
[[ "$(created)" == 0 && "$(closed)" == 0 ]] || _ok=0
check "Z5: active zone, NS sets equal in a different order -> healthy, nothing filed (rc=$RC, state=$(state))" "$_ok"

ROWS=$((ROWS + 1))
run_step z5b MOCK_EXISTING=42
_ok=1
[[ "$(state)" == healthy && "$(closed)" == 1 && "$(created)" == 0 ]] || _ok=0
grep -q '^issue close 42 ' "$LOG.gh" || _ok=0
check "Z5b: a healthy run closes the open issue" "$_ok"

ROWS=$((ROWS + 1))
run_step z5c MOCK_EXISTING=9 MOCK_CLOSE_RC=1
_ok=1
[[ "$(state)" == healthy && "$(escalation)" == failed ]] || _ok=0
grep -qF 'tunnel_zone_close_failed' "$OUT" || _ok=0
check "Z5c: a healthy zone whose open issue cannot be closed reports escalation=failed (got $(escalation))" "$_ok"

echo "=== matrix ==="
ROWS=$((ROWS + 1))
run_step z1 MOCK_ZONE_JSON="$(zone_json moved laila.ns.cloudflare.com lennon.ns.cloudflare.com)"
_ok=1
[[ "$RC" == "0" && "$(state)" == drift && "$(created)" == 1 ]] || _ok=0
grep -q -- '--label ci/tunnel-zone-authority' "$LOG.gh" || _ok=0
grep -qF "status 'moved'" "$LOG.body" || _ok=0
check "Z1: status moved -> one ci/tunnel-zone-authority issue naming the status (state=$(state))" "$_ok"

ROWS=$((ROWS + 1))
run_step z2 MOCK_ZONE_JSON="$(zone_json active bradley.ns.cloudflare.com nora.ns.cloudflare.com)"
_ok=1
[[ "$(state)" == drift && "$(created)" == 1 ]] || _ok=0
grep -qF 'laila.ns.cloudflare.com,lennon.ns.cloudflare.com' "$LOG.body" || _ok=0
grep -qF 'bradley.ns.cloudflare.com,nora.ns.cloudflare.com' "$LOG.body" || _ok=0
check "Z2: public NS laila/lennon vs zone NS bradley/nora -> filed, both sets in the body" "$_ok"

ROWS=$((ROWS + 1))
run_step z2b MOCK_ZONE_JSON="$(zone_json active bradley.ns.cloudflare.com nora.ns.cloudflare.com)" MOCK_EXISTING=7
_ok=1
[[ "$(created)" == 0 && "$(edited)" == 1 ]] || _ok=0
check "Z2b: a second drift run rewrites the open issue rather than filing another" "$_ok"

ROWS=$((ROWS + 1))
run_step z3 MOCK_DOH_RC=28
_ok=1
[[ "$(state)" == unavailable && "$(created)" == 1 ]] || _ok=0
grep -qF 'state=unavailable' "$LOG.body" || _ok=0
check "Z3: a failed DoH query is unavailable and files, never clean (state=$(state))" "$_ok"

ROWS=$((ROWS + 1))
run_step z3b MOCK_DOH_JSON='{"Status":2,"Answer":[]}'
check "Z3b: a SERVFAIL DoH answer is unavailable (state=$(state))" "$([[ "$(state)" == unavailable ]] && echo 1 || echo 0)"

ROWS=$((ROWS + 1))
run_step z4 MOCK_ZONE_ID=""
_ok=1
[[ "$(state)" == unavailable && "$(created)" == 1 ]] || _ok=0
grep -q 'api.cloudflare.com' "$LOG.curl" && _ok=0
check "Z4: an empty zone id refuses: unavailable, no zone read, no comparison of empty sets" "$_ok"

ROWS=$((ROWS + 1))
run_step z4b MOCK_TF_RC=1
check "Z4b: a failed terraform output is unavailable (state=$(state))" "$([[ "$(state)" == unavailable ]] && echo 1 || echo 0)"

ROWS=$((ROWS + 1))
run_step z4c MOCK_ZONE_JSON='{"success":false,"errors":[{"code":9109}]}'
check "Z4c: a token that cannot read the zone is unavailable (state=$(state))" "$([[ "$(state)" == unavailable ]] && echo 1 || echo 0)"

ROWS=$((ROWS + 1))
run_step z4d MOCK_ZONE_JSON="$(zone_json active)"
check "Z4d: a zone with empty name_servers is unavailable, never compared (state=$(state))" "$([[ "$(state)" == unavailable ]] && echo 1 || echo 0)"

ROWS=$((ROWS + 1))
run_step z6 MOCK_DOH_RC=28 MOCK_EXISTING=9
_ok=1
[[ "$(closed)" == 0 && "$(edited)" == 0 && "$(commented)" == 1 && "$(escalation)" == ok ]] || _ok=0
grep -q -- '--body-file' "$LOG.gh" && _ok=0
[[ -e "$LOG.body" ]] && _ok=0
grep -qF 'issue comment 9 --body state=unavailable' "$LOG.gh" || _ok=0
check "Z6: an unavailable run never closes or rewrites the open (drift) issue; it only comments" "$_ok"

ROWS=$((ROWS + 1))
run_step z6b MOCK_DOH_RC=28 MOCK_EXISTING=9 MOCK_COMMENT_RC=1
check "Z6b: a refused unavailable comment reports escalation=failed (got $(escalation))" "$([[ "$(escalation)" == failed ]] && echo 1 || echo 0)"

ROWS=$((ROWS + 1))
run_step z7 MOCK_ZONE_JSON="$(zone_json moved laila.ns.cloudflare.com lennon.ns.cloudflare.com)" MOCK_LIST_RC=1
_ok=1
[[ "$RC" == "0" && "$(created)" == 0 ]] || _ok=0
grep -qF 'tunnel_zone_list_failed' "$OUT" || _ok=0
check "Z7: an unreadable dedupe list declines to file a possible duplicate, loudly" "$_ok"

ROWS=$((ROWS + 1))
run_step z10 MOCK_ZONE_JSON="$(zone_json moved laila.ns.cloudflare.com lennon.ns.cloudflare.com)"
_ok=1
grep -qF "::error::tunnel_zone_drift — zone soleur.ai" "$OUT" || _ok=0
[[ "$(escalation)" == ok ]] || _ok=0
check "Z10: drift prints an ::error:: annotation and a filed issue reports escalation=ok" "$_ok"

ROWS=$((ROWS + 1))
run_step z12 MOCK_ZONE_JSON="$(zone_json moved laila.ns.cloudflare.com lennon.ns.cloudflare.com)" MOCK_CREATE_RC=1
_ok=1
[[ "$(escalation)" == failed ]] || _ok=0
grep -qF 'tunnel_zone_escalation_failed' "$OUT" || _ok=0
run_step z12b MOCK_LIST_RC=1
[[ "$(escalation)" == failed ]] || _ok=0
run_step z12c
[[ "$(escalation)" == ok ]] || _ok=0
check "Z12: a refused create or list reports escalation=failed; a clean healthy run reports ok" "$_ok"

echo "=== hostile and malformed input ==="
ROWS=$((ROWS + 1))
run_step z11 MOCK_DOH_JSON='{"Status":0,"Answer":[{"name":"soleur.ai","type":2,"data":"laila.ns.cloudflare.com."},{"name":"soleur.ai","type":1,"data":"1.2.3.4"},{"name":"soleur.ai","type":2,"data":"lennon.ns.cloudflare.com."}]}'
_ok=1
[[ "$(state)" == healthy ]] || _ok=0
run_step z11b MOCK_DOH_JSON='{"Status":0,"Answer":[{"name":"soleur.ai","type":5,"data":"elsewhere.example."}]}'
[[ "$(state)" == unavailable ]] || _ok=0
check "Z11: non-NS DoH answers are ignored (an A record beside the NS set stays healthy; CNAME-only is unavailable)" "$_ok"

# One row per refused character, each token carrying only that one (a two-cause fixture proves neither).
z13_row() { # <label> <what> <token>
  ROWS=$((ROWS + 1))
  run_step "$1" MOCK_CF_TOKEN="$3"
  _ok=1
  [[ "$(state)" == unavailable ]] || _ok=0
  grep -q 'api.cloudflare.com' "$LOG.curl" && _ok=0
  [[ -s "$LOG.stdin" ]] && _ok=0
  grep -qF 'evil.example' "$OUT" && _ok=0
  check "Z13 ($2): a token carrying only a $2 is refused before any curl and never echoed (state=$(state))" "$_ok"
}
z13_row z13a quote 'synth"Host: evil.example'
z13_row z13b backslash 'synth\Host: evil.example'
z13_row z13c newline $'synth\nHost: evil.example'

ROWS=$((ROWS + 1))
run_step z14 MOCK_ZONE_ID="0123456789abcdef/../../accounts"
_ok=1
[[ "$(state)" == unavailable ]] || _ok=0
grep -q 'api.cloudflare.com' "$LOG.curl" && _ok=0
check "Z14: a non-empty malformed zone id is unavailable and never reaches the zone URL (state=$(state))" "$_ok"

ROWS=$((ROWS + 1))
run_step z8 MOCK_ZONE_JSON="$(zone_json moved laila.ns.cloudflare.com lennon.ns.cloudflare.com)"
_ok=1
grep -qF "$CF_SENTINEL" "$LOG.curl" && _ok=0
grep -qF "header = \"Authorization: Bearer ${CF_SENTINEL}\"" "$LOG.stdin" || _ok=0
grep -qF "$CF_SENTINEL" "$LOG.body" && _ok=0
grep -qF "::add-mask::${CF_SENTINEL}" "$OUT" || _ok=0
check "Z8: the bearer rides curl's stdin config only, is masked, and is in no argv or issue body" "$_ok"

ROWS=$((ROWS + 1))
run_step z9 MOCK_CF_TOKEN=""
check "Z9: no CF token at all is unavailable (state=$(state))" "$([[ "$(state)" == unavailable ]] && echo 1 || echo 0)"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# Conservation: every row reports exactly once, so a neutered pass()/fail() breaks the
# equality even when the row counter is intact.
if (( ROWS < 28 || PASS + FAIL != ROWS )); then
  echo "FATAL: only ${ROWS} rows / $((PASS + FAIL)) assertions ran, expected >= 28." >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
