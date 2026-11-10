# shellcheck shell=bash
# Egress injector spike (#12517): harness primitives sourced by injector-spike-docker.test.sh. Test path only.
#
#   record_verdict <criterion 1-9> <pass|fail|unmeasurable> <observation-or-reason>
#       The ONE write path for verdicts (Guard 3 assembly). Appends one JSON record. A pass needs a non-empty
#       observation (verdict.mjs refuses a pass without one); an unmeasurable needs a reason.
#   harness_fail <TOKEN> <detail>
#       Prints `FAIL <TOKEN>: <detail>`, records every criterion that has no verdict yet as unmeasurable with that
#       token as its reason, finalizes the JSON (INCONCLUSIVE) and exits 1. Never a skip.
#   finalize
#       Computes the verdict with verdict.mjs over the records, writes INJECTOR_SPIKE_OUT, re-reads it through
#       verdict.mjs (the stored verdict must agree with the records) and exits with the verdict's exit code.
#   observe <arm> <json file>
#       Appends one raw-outcome object ({"arm": ..., ...the file's JSON}) to the observations the results JSON
#       carries. Raw outcomes are recorded whether or not the criterion reached a verdict (secrets are already
#       redacted by the producer; this never adds a value of its own).
#   mask <value>
#       Masks a generated value in the CI log (`::add-mask::`); a no-op outside Actions.
#   mint_session_ca <dir> <cn>
#       An ephemeral EC root with critical nameConstraints permitting the four inject hosts and excluding every IPv4
#       and IPv6 address, pathlen 0, 24 h validity (spec TR3). Writes <dir>/ca.pem and <dir>/ca.key (0600).
#   mint_leaf <ca-dir> <out-prefix> <san-list> [eku]
#       A leaf signed by that CA. `san-list` is an openssl subjectAltName value (DNS:a,DNS:b or IP:1.2.3.4).
#
# Nothing here prints a secret value. Callers must never enable xtrace (the suite refuses to start under it).

SPIKE_CRITERIA=(1 2 3 4 5 6 7 8 9)

_spike_json_record() { # criterion verdict text
  python3 -I -c '
import json, sys
c, v, t = int(sys.argv[1]), sys.argv[2], sys.argv[3]
rec = {"criterion": c, "verdict": v}
rec["reason" if v == "unmeasurable" else "observation"] = t
print(json.dumps(rec))
' "$1" "$2" "$3"
}

record_verdict() {
  local c="$1" v="$2" t="${3:-}"
  case "$v" in pass|fail|unmeasurable) ;; *) echo "FAIL RECORD_VERDICT: bad verdict '$v' for criterion $c"; exit 1 ;; esac
  case " ${SPIKE_CRITERIA[*]} " in *" $c "*) ;; *) echo "FAIL RECORD_VERDICT: unknown criterion '$c'"; exit 1 ;; esac
  [[ -n "$t" ]] || { echo "FAIL RECORD_VERDICT: criterion $c recorded with no observation or reason"; exit 1; }
  _spike_json_record "$c" "$v" "$t" >> "$SPIKE_RECORDS" || { echo "FAIL RECORD_VERDICT: cannot append to $SPIKE_RECORDS"; exit 1; }
  echo "SOLEUR_SPIKE_CRITERION criterion=$c verdict=$v"
}

_spike_has_record() {
  [[ -s "$SPIKE_RECORDS" ]] || return 1
  python3 -I -c '
import json, sys
want = int(sys.argv[2])
for line in open(sys.argv[1]):
    if line.strip() and json.loads(line).get("criterion") == want:
        sys.exit(0)
sys.exit(1)
' "$SPIKE_RECORDS" "$1"
}

harness_fail() {
  local token="$1" detail="${2:-}"
  echo "FAIL ${token}: ${detail}"
  [[ "${GITHUB_ACTIONS:-}" == "true" ]] && echo "::error title=injector spike harness::${token}: ${detail}"
  local c
  for c in "${SPIKE_CRITERIA[@]}"; do
    _spike_has_record "$c" || _spike_json_record "$c" unmeasurable "harness:${token}" >> "$SPIKE_RECORDS"
  done
  finalize
}

finalize() {
  local draft="$SPIKE_WORK/results.draft.json" verdict rc
  # shellcheck disable=SC2034 # read by the suite's trap
  SPIKE_FINALIZED=1  # read by the suite's EXIT/TERM trap (a run that ends before this still writes its results)
  python3 -I - "$SPIKE_RECORDS" "$draft" <<'PY' || { echo "FAIL FINALIZE: cannot assemble results"; exit 1; }
import json, os, sys
records = [json.loads(l) for l in open(sys.argv[1]) if l.strip()] if os.path.exists(sys.argv[1]) else []
obs_path = os.environ.get("SPIKE_OBSERVATIONS", "")
observations = [json.loads(l) for l in open(obs_path) if l.strip()] if obs_path and os.path.exists(obs_path) else []
meta = {k: os.environ.get(v, "") for k, v in {
    "run_url": "INJECTOR_SPIKE_RUN_URL", "commit": "SPIKE_COMMIT", "date": "SPIKE_DATE", "machine": "SPIKE_MACHINE",
    "sdk_pin": "SPIKE_SDK_PIN", "iron_proxy_digest": "SPIKE_IRON_PROXY_DIGEST", "app_image": "SPIKE_APP_IMAGE"}.items()}
json.dump({"meta": meta, "records": records, "observations": observations}, open(sys.argv[2], "w"), indent=2)
PY
  verdict="$(node "$SPIKE_DIR/verdict.mjs" "$draft" 2>"$SPIKE_WORK/verdict.err" | sed -n 's/^verdict=//p')"
  [[ -n "$verdict" ]] || verdict="INCONCLUSIVE"
  python3 -I - "$draft" "$SPIKE_OUT" "$verdict" <<'PY' || { echo "FAIL FINALIZE: cannot write results"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
d = {"verdict": sys.argv[3], **d}
json.dump(d, open(sys.argv[2], "w"), indent=2)
open(sys.argv[2], "a").write("\n")
PY
  node "$SPIKE_DIR/verdict.mjs" "$SPIKE_OUT" > "$SPIKE_WORK/verdict.final" 2>&1
  rc=$?
  cat "$SPIKE_WORK/verdict.final"
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    python3 -I - "$SPIKE_OUT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for r in d["records"]:
    if r["verdict"] != "pass":
        print(f"::error title=injector spike criterion {r['criterion']}::{r['verdict']}: {r.get('reason') or r.get('observation')}")
PY
  fi
  # The verdict and one row per record on the run's summary page, so a reader (or an agent with the run URL) sees
  # the outcome without downloading the artifact. Records carry ids and reasons only, never a secret value.
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    python3 -I - "$SPIKE_OUT" "$SPIKE_WORK/verdict.final" >> "$GITHUB_STEP_SUMMARY" <<'PY' || echo "WARN finalize: could not write the step summary"
import json, sys
d = json.load(open(sys.argv[1]))
final = next((l.strip().split("=", 1)[1] for l in open(sys.argv[2]) if l.startswith("verdict=")), "INCONCLUSIVE")
cell = lambda s: str(s).replace("|", "\\|").replace("\n", " ")[:600]
print(f"## Egress injector spike: {final}\n")
print("| Criterion | Verdict | Observation or reason |")
print("|---|---|---|")
for r in sorted(d.get("records", []), key=lambda r: (r.get("criterion", 0), str(r.get("verdict")))):
    print(f"| {r.get('criterion')} | {r.get('verdict')} | {cell(r.get('reason') or r.get('observation') or '')} |")
print()
PY
  fi
  echo "INJECTOR_SPIKE_OUT=$SPIKE_OUT"
  exit "$rc"
}

observe() {
  python3 -I -c 'import json, sys
d = json.load(open(sys.argv[2]))
print(json.dumps({"arm": sys.argv[1], **(d if isinstance(d, dict) else {"value": d})}))' "$1" "$2" >> "$SPIKE_OBSERVATIONS" \
    || echo "WARN observe: could not record $1"
}

mask() {
  [[ "${GITHUB_ACTIONS:-}" == "true" ]] && printf '::add-mask::%s\n' "$1"
  return 0
}

mint_session_ca() {
  local dir="$1" cn="$2"
  mkdir -p "$dir" && chmod 700 "$dir" || return 1
  local nc="critical,permitted;DNS:github.com,permitted;DNS:api.github.com,permitted;DNS:uploads.github.com"
  nc+=",permitted;DNS:codeload.github.com,excluded;IP:0.0.0.0/0.0.0.0,excluded;IP:0:0:0:0:0:0:0:0/0:0:0:0:0:0:0:0"
  ( umask 077 && openssl ecparam -name prime256v1 -genkey -noout -out "$dir/ca.key" ) 2>/dev/null || return 1
  openssl req -x509 -new -key "$dir/ca.key" -sha256 -days 1 -subj "/CN=$cn" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "nameConstraints=$nc" -out "$dir/ca.pem" 2>/dev/null || return 1
}

mint_leaf() {
  local cadir="$1" out="$2" san="$3" eku="${4:-serverAuth}" cn
  cn="$(printf '%s' "$san" | sed -E 's/^(DNS|IP)://; s/,.*$//')"
  ( umask 077 && openssl ecparam -name prime256v1 -genkey -noout -out "$out.key" ) 2>/dev/null || return 1
  openssl req -new -key "$out.key" -subj "/CN=$cn" -out "$out.csr" 2>/dev/null || return 1
  printf 'subjectAltName=%s\nextendedKeyUsage=%s\nbasicConstraints=critical,CA:FALSE\n' "$san" "$eku" > "$out.ext"
  openssl x509 -req -in "$out.csr" -CA "$cadir/ca.pem" -CAkey "$cadir/ca.key" -CAcreateserial -days 1 -sha256 \
    -extfile "$out.ext" -out "$out.pem" 2>/dev/null || return 1
  rm -f "$out.csr" "$out.ext"
}

# A plain (unconstrained) root for the test upstream and for the hook's server and client roots.
mint_plain_root() {
  local dir="$1" cn="$2"
  mkdir -p "$dir" && chmod 700 "$dir" || return 1
  ( umask 077 && openssl ecparam -name prime256v1 -genkey -noout -out "$dir/ca.key" ) 2>/dev/null || return 1
  openssl req -x509 -new -key "$dir/ca.key" -sha256 -days 1 -subj "/CN=$cn" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out "$dir/ca.pem" 2>/dev/null || return 1
}

# Instrument self-test (run before any arm): the record path, the judged-record path, the floor and the verdict
# program must each be able to produce BOTH outcomes, or nothing downstream of them is evidence. A failure is
# reported with printf and exit, never through the helpers under test (a recorder or judge that always said `pass`
# would otherwise report its own failure as a pass). The results file it leaves is written with printf too.
_selftest_die() {
  printf 'FAIL SELFTEST: %s\n' "$1"
  [[ "${GITHUB_ACTIONS:-}" == "true" ]] && printf '::error title=injector spike harness::SELFTEST: %s\n' "$1"
  printf '{"verdict": "INCONCLUSIVE", "records": [], "harness": "SELFTEST"}\n' > "$SPIKE_OUT"
  # shellcheck disable=SC2034 # read by the suite's trap
  SPIKE_FINALIZED=1  # this file is the result; the suite's exit trap must not overwrite it through the helpers
  exit 1
}

# _selftest_verdict <records.jsonl> <out.json>: wraps the records the helpers appended and prints verdict.mjs's line.
_selftest_verdict() {
  python3 -I -c 'import json, sys
json.dump({"records": [json.loads(l) for l in open(sys.argv[1]) if l.strip()]}, open(sys.argv[2], "w"))' "$1" "$2" \
    || _selftest_die "cannot wrap $1"
  node "$SPIKE_DIR/verdict.mjs" "$2" 2>/dev/null
}

harness_selftest() {
  local t="$SPIKE_WORK/selftest" out c saved="$SPIKE_RECORDS"
  mkdir -p "$t" || _selftest_die "mkdir $t"
  printf '{"records":[]}\n' > "$t/empty.json"
  out="$(node "$SPIKE_DIR/verdict.mjs" "$t/empty.json" 2>/dev/null)"
  [[ "$out" == "verdict=INCONCLUSIVE" ]] || _selftest_die "empty records did not read INCONCLUSIVE ($out)"
  python3 -I -c '
import json
print(json.dumps({"records": [{"criterion": c, "verdict": "pass", "observation": "selftest"} for c in range(1, 10)]}))
' > "$t/go.json"
  out="$(node "$SPIKE_DIR/verdict.mjs" "$t/go.json" 2>/dev/null)"
  [[ "$out" == "verdict=GO" ]] || _selftest_die "nine passes did not read GO ($out)"
  # Through record_verdict: eight passes and one fail must read NO-GO; nine passes must read GO.
  SPIKE_RECORDS="$t/rv-fail.jsonl"; : > "$SPIKE_RECORDS"
  for c in 1 2 3 4 5 6 7 8; do record_verdict "$c" pass "selftest-observation" >/dev/null; done
  record_verdict 9 fail "selftest-observation" >/dev/null
  out="$(_selftest_verdict "$SPIKE_RECORDS" "$t/rv-fail.json")"
  [[ "$out" == "verdict=NO-GO" ]] || _selftest_die "a fail pushed through record_verdict did not read NO-GO ($out)"
  SPIKE_RECORDS="$t/rv-go.jsonl"; : > "$SPIKE_RECORDS"
  for c in 1 2 3 4 5 6 7 8 9; do record_verdict "$c" pass "selftest-observation" >/dev/null; done
  out="$(_selftest_verdict "$SPIKE_RECORDS" "$t/rv-go.json")"
  [[ "$out" == "verdict=GO" ]] || _selftest_die "nine passes through record_verdict did not read GO ($out)"
  # Through spike_record_judged (the path every arm's judge takes): a judged fail must read NO-GO, a judged pass GO.
  printf 'fail\nfailed: selftest check\n' > "$t/judge-fail.txt"
  printf 'pass\nall checks held: selftest check\n' > "$t/judge-pass.txt"
  SPIKE_RECORDS="$t/judged-fail.jsonl"; : > "$SPIKE_RECORDS"
  for c in 1 2 3 4 5 6 7 8; do record_verdict "$c" pass "selftest-observation" >/dev/null; done
  spike_record_judged 9 "$t/judge-fail.txt" >/dev/null
  out="$(_selftest_verdict "$SPIKE_RECORDS" "$t/judged-fail.json")"
  [[ "$out" == "verdict=NO-GO" ]] || _selftest_die "a fail pushed through spike_record_judged did not read NO-GO ($out)"
  SPIKE_RECORDS="$t/judged-pass.jsonl"; : > "$SPIKE_RECORDS"
  for c in 1 2 3 4 5 6 7 8; do record_verdict "$c" pass "selftest-observation" >/dev/null; done
  spike_record_judged 9 "$t/judge-pass.txt" >/dev/null
  out="$(_selftest_verdict "$SPIKE_RECORDS" "$t/judged-pass.json")"
  [[ "$out" == "verdict=GO" ]] || _selftest_die "a pass pushed through spike_record_judged did not read GO ($out)"
  SPIKE_RECORDS="$saved"
  echo "SOLEUR_SPIKE_SELFTEST ok"
}
