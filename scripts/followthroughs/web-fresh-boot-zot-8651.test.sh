#!/usr/bin/env bash
# web-fresh-boot-zot-8651.test.sh — fixture test for the issue-8651 closure probe.
# A PATH-stubbed `gh` serves run lists, job JSON and job logs in GitHub's real `--log` shape
# (job<TAB>step<TAB>timestamp text), including the echoed `run:` source lines GitHub prints with
# an ANSI prefix. The stub REFUSES any argv it was not written for (exit 64), so a probe that
# asks GitHub the wrong question cannot read the right fixture. Every sweeper exit code is
# driven, each verdict pinned by BOTH its exit code and its leading word.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$DIR/web-fresh-boot-zot-8651.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

BIN="$WORK/bin"; mkdir -p "$BIN" "$WORK/fx"
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
FX="$GH_FX"
case "$*" in
  "run list --repo jikig-ai/soleur --workflow apply-web-platform-infra.yml --event workflow_dispatch -L 40 --json databaseId --jq .[].databaseId")
    [ -f "$FX/list.fail" ] && exit 1; cat "$FX/list"; exit 0 ;;
  "run view "*" --repo jikig-ai/soleur --json jobs")
    id="${3}"; [ -f "$FX/jobs.$id" ] || { echo "stub: no jobs fixture $id" >&2; exit 64; }; cat "$FX/jobs.$id"; exit 0 ;;
  "run view --repo jikig-ai/soleur --job "*" --log")
    jid="${6}"; [ -f "$FX/log.$jid.fail" ] && exit 1
    [ -f "$FX/log.$jid" ] || { echo "stub: no log fixture $jid" >&2; exit 64; }; cat "$FX/log.$jid"; exit 0 ;;
esac
echo "stub gh: unexpected argv: $*" >&2; exit 64
STUB
chmod +x "$BIN/gh"

S="Surface fresh-host Sentry breadcrumb trail (best-effort — R2/R3/R4/R5)"
TS="2026-09-24T10:00:00.0000000Z"
l() { printf 'web_host_replace\t%s\t%s %s\n' "${2:-$S}" "$TS" "$1"; }            # a step output line
src() { printf 'web_host_replace\t%s\t%s \033[36;1m%s\n' "$S" "$TS" "$1"; }        # an echoed-source line
PTR="web-host-replace web-2 — fresh-host Sentry pointer (job=success)"
ZOT='- image-origin (`soleur-web-2`, since run anchor): `stage=app_zot host=soleur-web-2 time=2026-09-24T10:05:00Z detail=zot_login=ok ghcr_login=fail nic=ready:0 zot=[login=ok,n=1,cause=other]`'
READY="fresh-host boot reached fresh_boot_ready — the host booted clean and reported ready."

reset_fx() { rm -rf "$WORK/fx"; mkdir -p "$WORK/fx"; }
job() {  # <run-id> <job-id> <name> <conclusion>
  printf '{"jobs":[{"databaseId":1,"name":"preflight","conclusion":"success"},{"databaseId":%s,"name":"%s","conclusion":"%s"}]}\n' "$2" "$3" "$4" > "$WORK/fx/jobs.$1"
}
run() {  # <want-rc> <want-word> <label>
  local out rc=0
  out=$(PATH="$BIN:$PATH" GH_FX="$WORK/fx" bash "$PROBE" 2>&1) || rc=$?
  if [ "$rc" = "$1" ] && grep -q "^$2" <<<"$out"; then ok "$3 → exit $1 ($2)"
  else no "$3: want exit $1 + '$2', got exit $rc: $(tr '\n' ' ' <<<"$out" | head -c 260)"; fi
}

reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success
{ l "$PTR"; l "$ZOT"; l "$READY"; } > "$WORK/fx/log.9001";              run 0 PASS "zot-served boot with fresh_boot_ready"
{ l "$PTR"; l "$READY"; } > "$WORK/fx/log.9001";                         run 2 "NOT YET" "newest run predates the fixed trail (no image-origin line)"
{ l "$PTR"; l "$ZOT"; l '##[error]web-2 (soleur-web-2) booted DARK at stage pull: nic=ready:0 zot=[login=ok,n=3,cause=manifest] ghcr=[login=fail,pull=not-attempted] pull_err: x'; } > "$WORK/fx/log.9001"
run 1 FAIL "fixed trail, booted DARK"
{ l "$PTR"; l "$ZOT"; l '##[error]web-2 (soleur-web-2) did not reach cloud_init_complete within 960s'; } > "$WORK/fx/log.9001"
run 1 FAIL "fixed trail, no terminal event (timeout)"
{ l "$PTR"; l '- image-origin (`soleur-web-2`, since run anchor): `stage=app_ghcr_served host=soleur-web-2 time=t detail=zot_login=fail ghcr_login=ok`'; l "$READY"; } > "$WORK/fx/log.9001"
run 1 FAIL "GHCR served the boot"
{ l "$PTR"; l "$ZOT"; l "Booted, readiness unconfirmed."; } > "$WORK/fx/log.9001";   run 2 "NOT YET" "inconclusive: app_zot but no fresh_boot_ready"
{ l "$PTR"; l "${ZOT/zot_login=ok/zot_login=fail}"; l "$READY"; } > "$WORK/fx/log.9001"; run 2 "NOT YET" "app_zot without zot_login=ok is not a pass"
{ l "$PTR"; l "- image-origin read FAILED (HTTP 500 or no data array) — UNKNOWN, not 'none'."; l "$READY"; } > "$WORK/fx/log.9001"
run 2 "NOT YET" "image-origin read failed on the fixed trail"
# DECOYS: the pass-shaped text appears only in echoed run-block SOURCE, or in another step.
{ l "$PTR"; src "$ZOT"; src "$READY"; l '- image-origin (`soleur-web-2`, since run anchor): `stage=none host=- time=- detail=-`'; l "Booted, readiness unconfirmed."; } > "$WORK/fx/log.9001"
run 2 "NOT YET" "echoed-source decoy lines are not graded (graded, they would read as a PASS)"
{ l "$PTR"; l "$ZOT" "Dispatch summary"; l "$READY" "Dispatch summary"; } > "$WORK/fx/log.9001"
run 2 "NOT YET" "pass-shaped lines in another step are not graded"
# Host selection: a newer web-1 run is skipped; the older web-2 run is the one graded.
reset_fx; printf '901\n900\n' > "$WORK/fx/list"; job 901 9011 web_host_replace success; job 900 9001 web_host_replace success
{ l "web-host-replace web-1 — fresh-host Sentry pointer (job=success)"; l '##[error]web-1 booted DARK at stage pull: x'; } > "$WORK/fx/log.9011"
{ l "$PTR"; l "$ZOT"; l "$READY"; } > "$WORK/fx/log.9001";              run 0 PASS "a newer web-1 run is skipped, web-2 graded"
# A newer web-2 run that went dark wins over an older passing one.
{ l "$PTR"; l "$ZOT"; l '##[error]web-2 (soleur-web-2) booted DARK at stage extract: x'; } > "$WORK/fx/log.9011"
run 1 FAIL "the NEWEST web-2 run decides (dark after an earlier pass)"
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace skipped
run 2 "NOT YET" "a skipped replace job is not evidence"
reset_fx; : > "$WORK/fx/list";                                              run 2 "NOT YET" "no dispatch runs at all"
reset_fx; touch "$WORK/fx/list.fail";                                       run 3 TRANSIENT "gh run list fails"
reset_fx; echo 900 > "$WORK/fx/list"; job 900 9001 web_host_replace success; touch "$WORK/fx/log.9001.fail"
run 3 TRANSIENT "job log read fails"
rc=0; GH_FX="$WORK/fx" PATH="$BIN:$PATH" bash -x "$PROBE" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] && ok "refuses to run under xtrace (exit 78)" || no "xtrace refusal: rc=$rc"

MIN_CASES=17
if [ $((pass + fail)) -lt "$MIN_CASES" ]; then
  printf 'assertion floor: %d < %d — a case stopped running\n' $((pass + fail)) "$MIN_CASES"; exit 1
fi
echo "=== web-fresh-boot-zot-8651: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
