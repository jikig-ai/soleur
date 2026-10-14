#!/usr/bin/env bash
# Guard 3's REQUIRED-SHARD half (#7555).
#
# WHY THIS EXISTS SEPARATELY FROM apps/web-platform/infra/zot-config-deadlines.test.sh.
# That suite is the strong one: it validates the RENDERED bytes and boots the pinned zot digest
# against them, with a negative control. But it is registered in `deploy-script-tests`, and NO
# infra job is in this repo's required set — verified against
# scripts/ci-required-ruleset-canonical-required-status-checks.json, which lists `test` but
# neither `infra-validate-required` nor `deploy-script-tests`. That is a deliberate repo-wide
# decision (#6480: an 8-minute docker build on every docs-only PR), not an oversight, and
# re-litigating it does not belong in this PR.
#
# The consequence is still real: a RED Guard 3 does not block merge, so the guard that exists to
# stop an unbootable config reaching a host with NO SSH cannot actually stop it. This file is the
# defence-in-depth half — the same invariants, asserted against the TEMPLATE, needing only python3
# and PyYAML, so it rides the auto-globbed `plugins/soleur/test/*.test.sh` set inside the required
# `test` context.
#
# It is DELIBERATELY WEAKER and says so: it reads the template, not the render, so it cannot see a
# render-time strip, a duplicate write_files entry, or a config the digest rejects. Those stay with
# the infra suite. What it does guarantee is that the two deadlines cannot be removed, split, or
# pushed outside their bounds without a REQUIRED check going red.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
CI_YML="$REPO_ROOT/apps/web-platform/infra/cloud-init-registry.yml"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

if [[ ! -r "$CI_YML" ]]; then
  echo "  FAIL: $CI_YML not readable"; echo "=== Results: 0/1 passed, 1 failed ==="; exit 1
fi
if ! python3 -c 'import yaml' 2>/dev/null; then
  # A missing dependency must be its own outcome, never a silent pass.
  echo "  SKIP: PyYAML unavailable — the required-shard deadline guard did NOT run."
  echo "=== Results: 0/0 passed, 0 failed (DECLINED: no PyYAML) ==="
  exit 0
fi

READ_S="$(python3 - "$CI_YML" <<'PY'
import sys, yaml, json, re
doc = yaml.safe_load(open(sys.argv[1]))
out = {"rt": None, "wt": None, "gc": None, "n": 0}
for wf in doc.get("write_files", []):
    if wf.get("path") == "/etc/zot/config.json":
        out["n"] += 1
        cfg = json.loads(wf["content"])
        out["rt"] = cfg.get("http", {}).get("readTimeout")
        out["wt"] = cfg.get("http", {}).get("writeTimeout")
        out["gc"] = cfg.get("storage", {}).get("gcDelay")
def secs(v):
    if not isinstance(v, str): return None
    m = re.fullmatch(r"(\d+)(s|m|h)", v.strip())
    if not m: return None
    return int(m.group(1)) * {"s": 1, "m": 60, "h": 3600}[m.group(2)]
print(json.dumps({"n": out["n"], "rt": secs(out["rt"]), "wt": secs(out["wt"]),
                  "gc": secs(out["gc"]), "rt_raw": out["rt"], "wt_raw": out["wt"]}))
PY
)"
[[ -n "$READ_S" ]] || { echo "  FAIL: could not parse $CI_YML"; echo "=== Results: 0/1 passed, 1 failed ==="; exit 1; }

g() { python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('$1') if json.loads(sys.argv[1]).get('$1') is not None else '')" "$READ_S"; }
N="$(g n)"; RT="$(g rt)"; WT="$(g wt)"; GC="$(g gc)"

# DERIVE the floor, and duplicate the OPERANDS — never the product.
#
# This file hard-coded `157`. ADR-190 requires the layer size to be re-measured on every zot
# bump, and a re-measurement updates the infra suite's derivation while leaving a stale literal
# here — in the guard that is actually REQUIRED. The required check would then pass a config the
# advisory check fails, which inverts the tiering: the weaker guard decides the merge, on a
# number nobody re-derived. Duplicating the two operands makes the drift visible; the assertion
# below makes it fail.
LARGEST_LAYER_BYTES=703724542
FLOOR_THROUGHPUT_BPS=4500000
MIN_DEADLINE_S=$(( (LARGEST_LAYER_BYTES + FLOOR_THROUGHPUT_BPS - 1) / FLOOR_THROUGHPUT_BPS ))

# PIN THE TWO COPIES TOGETHER. Without this the duplication above is just a second place to be
# wrong. Read the infra suite's operands and require agreement; if that file moves or stops
# declaring them, say so rather than silently skipping (a vacuous pass here is the whole failure
# class this PR exists to close).
INFRA_GUARD="$REPO_ROOT/apps/web-platform/infra/zot-config-deadlines.test.sh"
if [[ -r "$INFRA_GUARD" ]]; then
  _ib="$(grep -oE '^LARGEST_LAYER_BYTES=[0-9]+' "$INFRA_GUARD" | head -1 | cut -d= -f2)"
  _it="$(grep -oE '^FLOOR_THROUGHPUT_BPS=[0-9]+' "$INFRA_GUARD" | head -1 | cut -d= -f2)"
  if [[ -z "$_ib" || -z "$_it" ]]; then
    fail "could not read LARGEST_LAYER_BYTES/FLOOR_THROUGHPUT_BPS from the infra guard — the two floors can now drift undetected"
  elif [[ "$_ib" == "$LARGEST_LAYER_BYTES" && "$_it" == "$FLOOR_THROUGHPUT_BPS" ]]; then
    pass "the required and advisory guards derive the floor from the SAME operands (${LARGEST_LAYER_BYTES}B / ${FLOOR_THROUGHPUT_BPS}Bps => ${MIN_DEADLINE_S}s)"
  else
    fail "floor operands DRIFTED: required guard has ${LARGEST_LAYER_BYTES}B/${FLOOR_THROUGHPUT_BPS}Bps, infra guard has ${_ib}B/${_it}Bps. Re-measure once and update both, per ADR-190."
  fi
else
  fail "infra guard not readable at $INFRA_GUARD — cannot confirm the two floors still agree"
fi

if [[ "$N" == "1" ]]; then
  pass "exactly one /etc/zot/config.json write_files entry (cloud-init applies the LAST; a duplicate would win on the host)"
else
  fail "expected exactly 1 /etc/zot/config.json entry, found '${N}'"
fi

if [[ -n "$RT" && -n "$WT" ]]; then
  pass "both http deadlines are set and parse (read=${RT}s write=${WT}s)"
else
  fail "SPLIT-BRAIN or unparseable: read='${RT:-<unset>}' write='${WT:-<unset>}'. readTimeout alone yields a zot-side 202 with no response to the client — silent success, worse than an honest 500."
fi

if [[ -n "$GC" ]]; then
  pass "storage.gcDelay parses (${GC}s)"
else
  fail "storage.gcDelay did not parse — the upper bound is unknowable, so this fails closed"
fi

for pair in "readTimeout:$RT" "writeTimeout:$WT"; do
  name="${pair%%:*}"; v="${pair#*:}"
  if [[ -z "$v" ]]; then
    fail "$name absent, so its floor cannot hold"
    fail "$name absent, so its gcDelay ceiling cannot hold"
    continue
  fi
  if [[ "$v" -ge "$MIN_DEADLINE_S" ]]; then
    pass "$name ${v}s >= largest-layer budget ${MIN_DEADLINE_S}s"
  else
    fail "$name ${v}s is BELOW the largest-layer budget ${MIN_DEADLINE_S}s — the layer that blocked the release still cannot land"
  fi
  if [[ -n "$GC" ]]; then
    if [[ "$v" -lt "$GC" ]]; then
      pass "$name ${v}s < gcDelay ${GC}s"
    else
      fail "$name ${v}s >= gcDelay ${GC}s — gc could reclaim staging for an upload still in flight"
    fi
  fi
done

# Harness canary + a floor that does NOT dispatch through the helper it guards.
_cp=$PASS; _cf=$FAIL
pass "canary: a true condition registers as PASS"
fail "canary: a false condition MUST register as FAIL (this line is EXPECTED)"
if [[ "$PASS" -ne $((_cp + 1)) || "$FAIL" -ne $((_cf + 1)) ]]; then
  echo "  FATAL: the assertion helpers are not counting — every verdict above is void." >&2
  exit 2
fi
FAIL=$((FAIL - 1))

TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt 9 ]]; then
  echo "  FATAL: anti-vacuity — ran $TOTAL assertions, expected >= 9. Fix the extraction, do not lower the floor." >&2
  exit 2
fi

echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
