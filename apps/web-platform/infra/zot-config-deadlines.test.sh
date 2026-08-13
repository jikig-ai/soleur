#!/usr/bin/env bash
# Guard 3 (#7555) — the zot HTTP deadlines cannot ship in a split-brain, gc-unsafe, or
# unparseable shape.
#
# WHY THIS GUARDS THE *RENDERED* CONFIG. Delivery is a `user_data` ForceNew replace of the
# fleet's sole pull path, and the host is cloud-init-only (ADR-096) with no SSH edit path. A
# config zot rejects is therefore NOT a plan-time failure: the destroy succeeds, the create
# succeeds, and zot fails to start on a host nobody can reach. So this reads the bytes that
# ACTUALLY reach the host — `registry-userdata-budget.sh`'s stripped render — not the template.
# Nothing in the repo validated this before.
#
# THE PROPERTY. The rendered /etc/zot/config.json always carries BOTH deadlines, both at or
# above the largest-layer budget, both strictly below `gcDelay`, and is accepted by the PINNED
# zot digest.
#
# Each conjunct exists because dropping it is silent:
#   - BOTH keys: setting readTimeout alone was measured to yield a zot-side 202 with no
#     response to the client — a split-brain strictly worse than today's honest 500.
#   - BELOW gcDelay: the two live in the same document and are read by different subsystems;
#     a deadline at or above gcDelay lets gc reclaim staging for an upload still in flight.
#   - ACCEPTED BY THE DIGEST: without the negative control below, "zot accepted the config"
#     means nothing — a typo'd key must be shown to be REJECTED, or acceptance is unfalsifiable.
#
# Run via: bash apps/web-platform/infra/zot-config-deadlines.test.sh
# Registered in .github/workflows/infra-validation.yml (deploy-script-tests).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

finish() {
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  [[ "$FAIL" -eq 0 ]]
}

TMP=$(mktemp -d) || { echo "  FAIL: mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# THE LARGEST-LAYER BUDGET, derived from the #7555 measurement rather than chosen.
#
#   largest layer observed          703_724_542 B   (PATCH Content-Length, run 31740550632)
#   floor throughput observed         4_500_000 B/s (the 272_236_549 B layer also died at the
#                                                    60 s wall, so effective rate < 4.54 MB/s)
#   => a deadline below 703724542/4500000 = 157 s cannot carry the largest layer.
#
# Asserted as a FLOOR on the configured deadline. The guard enforces the relation, never the
# literal 1800s — see the H1 harness row.
# ---------------------------------------------------------------------------
LARGEST_LAYER_BYTES=703724542
FLOOR_THROUGHPUT_BPS=4500000
MIN_DEADLINE_S=$(( (LARGEST_LAYER_BYTES + FLOOR_THROUGHPUT_BPS - 1) / FLOOR_THROUGHPUT_BPS ))

# ---------------------------------------------------------------------------
# Render the bytes that reach the host, then extract /etc/zot/config.json from them.
# CONFIG_JSON_OVERRIDE lets the mutation battery point this guard at a synthesized render
# without re-running terraform; it is never set in CI.
# ---------------------------------------------------------------------------
CFG="$TMP/config.json"
if [[ -n "${CONFIG_JSON_OVERRIDE:-}" ]]; then
  if [[ ! -r "$CONFIG_JSON_OVERRIDE" ]]; then
    fail "CONFIG_JSON_OVERRIDE set to an unreadable path: $CONFIG_JSON_OVERRIDE"
    finish; exit $?
  fi
  cp "$CONFIG_JSON_OVERRIDE" "$CFG"
  echo "  (using CONFIG_JSON_OVERRIDE — mutation-battery mode)"
else
  RENDERED="$TMP/rendered.yml"
  if ! bash "$HERE/registry-userdata-budget.sh" "$RENDERED" > "$TMP/budget.log" 2>&1; then
    fail "could not render the registry user_data (see below) — the guard cannot read the host bytes"
    tail -5 "$TMP/budget.log" >&2
    finish; exit $?
  fi
  python3 - "$RENDERED" "$CFG" <<'PY' || { echo "  FAIL: could not extract /etc/zot/config.json from the render"; exit 1; }
import sys, yaml
src, dst = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(src))
for wf in doc.get("write_files", []):
    if wf.get("path") == "/etc/zot/config.json":
        open(dst, "w").write(wf["content"])
        sys.exit(0)
sys.exit(1)
PY
fi

if [[ ! -s "$CFG" ]]; then
  fail "extracted config.json is empty — the guard would otherwise pass vacuously"
  finish; exit $?
fi

# ---------------------------------------------------------------------------
# Static half. Durations are Go-style ("1800s", "30m", "1h"); parse to seconds so the
# comparisons are on the RELATION and not on string equality.
# ---------------------------------------------------------------------------
read_field() { # $1=jq-ish path via python; prints value or empty
  python3 - "$CFG" "$1" <<'PY'
import sys, json
cfg = json.load(open(sys.argv[1]))
cur = cfg
for part in sys.argv[2].split("."):
    if not isinstance(cur, dict) or part not in cur:
        sys.exit(0)
    cur = cur[part]
print(cur if not isinstance(cur, (dict, list)) else "")
PY
}

to_seconds() { # $1=Go duration; prints integer seconds, or nothing if unparseable
  python3 - "$1" <<'PY'
import sys, re
v = sys.argv[1].strip()
m = re.fullmatch(r"(\d+)(s|m|h)", v)
if not m:
    sys.exit(0)
n, unit = int(m.group(1)), m.group(2)
print(n * {"s": 1, "m": 60, "h": 3600}[unit])
PY
}

RT_RAW="$(read_field http.readTimeout)"
WT_RAW="$(read_field http.writeTimeout)"
GC_RAW="$(read_field storage.gcDelay)"

# --- both keys present (the Arm C split-brain) ---
if [[ -n "$RT_RAW" && -n "$WT_RAW" ]]; then
  pass "both http.readTimeout and http.writeTimeout are set (rt=$RT_RAW wt=$WT_RAW)"
else
  fail "SPLIT-BRAIN: readTimeout='${RT_RAW:-<unset>}' writeTimeout='${WT_RAW:-<unset>}' — both must move together; readTimeout alone yields a zot-side 202 with no response to the client"
fi

RT_S="$(to_seconds "${RT_RAW:-}")"
WT_S="$(to_seconds "${WT_RAW:-}")"
GC_S="$(to_seconds "${GC_RAW:-}")"

if [[ -z "$GC_S" ]]; then
  fail "storage.gcDelay ('${GC_RAW:-<unset>}') did not parse as a duration — the upper bound is unknowable, so this fails closed"
else
  pass "storage.gcDelay parses (${GC_RAW} = ${GC_S}s)"
fi

for pair in "readTimeout:$RT_RAW:$RT_S" "writeTimeout:$WT_RAW:$WT_S"; do
  name="${pair%%:*}"; rest="${pair#*:}"; raw="${rest%%:*}"; secs="${rest#*:}"
  if [[ -z "$raw" ]]; then
    continue   # already reported by the split-brain assertion above
  fi
  if [[ -z "$secs" ]]; then
    fail "$name ('$raw') did not parse as a Go duration — an unparseable deadline is not a deadline"
    continue
  fi
  # --- floor: at or above the largest-layer budget ---
  if [[ "$secs" -ge "$MIN_DEADLINE_S" ]]; then
    pass "$name ${raw} (${secs}s) >= largest-layer budget ${MIN_DEADLINE_S}s"
  else
    fail "$name ${raw} (${secs}s) is BELOW the largest-layer budget ${MIN_DEADLINE_S}s (${LARGEST_LAYER_BYTES} B at ${FLOOR_THROUGHPUT_BPS} B/s) — the layer that blocked the release still cannot land"
  fi
  # --- ceiling: strictly below gcDelay ---
  if [[ -n "$GC_S" ]]; then
    if [[ "$secs" -lt "$GC_S" ]]; then
      pass "$name ${raw} (${secs}s) < gcDelay ${GC_RAW} (${GC_S}s)"
    else
      fail "$name ${raw} (${secs}s) is >= gcDelay ${GC_RAW} (${GC_S}s) — gc could reclaim staging for an upload still in flight"
    fi
  fi
done

# ---------------------------------------------------------------------------
# Digest half. The pinned zot must ACCEPT the rendered config, and — the control that
# gives that acceptance meaning — must REJECT an unknown key under HTTP.
#
# Declining is an explicit, printed verdict, never a silent pass (ADR-181).
# ---------------------------------------------------------------------------
if [[ "${SOLEUR_ZOT_GUARD_NO_DIGEST:-0}" == "1" ]]; then
  echo "  DECLINED: digest acceptance half not run (SOLEUR_ZOT_GUARD_NO_DIGEST=1)."
  echo "            The static relations above were checked; ACCEPTANCE BY ZOT WAS NOT OBTAINED."
else
  ZOT_IMAGE="$(grep -oE 'ghcr\.io/project-zot/zot-linux-amd64:[^"]+' "$REPO_ROOT/apps/web-platform/infra/zot-registry.tf" | head -1)"
  if [[ -z "$ZOT_IMAGE" ]]; then
    fail "could not read the pinned zot image from zot-registry.tf — acceptance cannot be tested against an unpinned digest"
  elif ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    fail "docker is unavailable, so the pinned digest could not adjudicate the config. This guard FAILS CLOSED: set SOLEUR_ZOT_GUARD_NO_DIGEST=1 to decline the half explicitly rather than have it pass silently."
  else
    zot_verify() { # $1=config path -> prints combined output; returns zot's rc
      timeout 300 docker run --rm -v "$1:/tmp/zot-guard.json:ro" "$ZOT_IMAGE" verify /tmp/zot-guard.json 2>&1
    }

    OUT="$(zot_verify "$CFG")"; RC=$?
    if [[ "$RC" -eq 0 ]] && grep -qF 'config file is valid' <<<"$OUT"; then
      pass "the pinned zot digest ACCEPTS the rendered config"
    else
      fail "the pinned zot digest REJECTED the rendered config (rc=$RC): $(tail -2 <<<"$OUT" | tr '\n' ' ')"
    fi

    # NEGATIVE CONTROL. Without this, "zot accepted it" is unfalsifiable — a verify that
    # accepts everything would report the same green.
    python3 - "$CFG" "$TMP/bogus.json" <<'PY'
import sys, json
cfg = json.load(open(sys.argv[1]))
cfg.setdefault("http", {})["zzzboguskey"] = "x"
json.dump(cfg, open(sys.argv[2], "w"), indent=2)
PY
    BOUT="$(zot_verify "$TMP/bogus.json")"; BRC=$?
    if [[ "$BRC" -ne 0 ]] && grep -qF "'HTTP' has invalid keys: zzzboguskey" <<<"$BOUT"; then
      pass "negative control: the pinned digest REJECTS an unknown key under HTTP"
    else
      fail "negative control FAILED (rc=$BRC): the digest did not reject 'zzzboguskey', so its acceptance of the real config proves nothing"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Anti-vacuity floor, DERIVED rather than written down, so it cannot drift out of step with
# the assertions above:
#   1  split-brain (both keys present)
#   1  gcDelay parses
#   2  deadlines x 2 relations each (>= largest-layer budget, < gcDelay)
#   2  digest acceptance + its negative control   [only when the digest half runs]
# A short count means an early `continue` fired or an unpopulated config slipped through as
# green — both of which look identical to a pass from the summary line alone.
# ---------------------------------------------------------------------------
DEADLINE_KEYS=2
RELATIONS_PER_KEY=2
EXPECTED_MIN=$(( 1 + 1 + (DEADLINE_KEYS * RELATIONS_PER_KEY) ))
[[ "${SOLEUR_ZOT_GUARD_NO_DIGEST:-0}" != "1" ]] && EXPECTED_MIN=$(( EXPECTED_MIN + 2 ))
TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt "$EXPECTED_MIN" ]]; then
  fail "anti-vacuity: ran $TOTAL assertions, expected >= $EXPECTED_MIN. Fix the extraction, do not lower the floor."
fi

finish
