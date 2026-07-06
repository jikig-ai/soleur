#!/usr/bin/env bash
# taste-profile-update.test.sh — fixture harness for the context-keyed taste-profile
# helper (#5990 · FR7 · ADR-090). Pattern mirrors .claude/hooks/skill-context-queries.test.sh.
#
# jq + bash only. Each test builds a fresh fixture profile in a temp dir, runs the
# helper, and asserts on the resulting file (or exit code). No network, no git needed.
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HELPER="$SCRIPT_DIR/taste-profile-update.sh"

pass=0
fail=0
pass() { printf '  \033[0;32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
fail() { printf '  \033[0;31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Build a fresh seed profile; echoes its path.
mk_profile() {
  local d p
  d="$(mktemp -d "$TMP_ROOT/prof.XXXXXX")"
  p="$d/taste-profile.md"
  cat > "$p" <<'EOF'
---
last_updated: 2026-07-01
last_reviewed: 2026-07-01
review_cadence: quarterly
owner: CPO
---
# Design Taste Profile

<!-- Machine block owned by plugins/soleur/scripts/taste-profile-update.sh — do not hand-edit. -->
<!-- taste-profile:data:start -->
```json
{"schema":1,"entries":[],"contradictions":[]}
```
<!-- taste-profile:data:end -->

## Reinforced Aesthetics

_None yet._

## Contradiction Flags

_None yet._
EOF
  echo "$p"
}

# Extract the JSON machine block from a profile file.
data_of() {
  awk '/taste-profile:data:start/{f=1;next} /taste-profile:data:end/{f=0} f' "$1" \
    | sed -e '/^```/d'
}

echo "== taste-profile-update.sh =="

# 1. Upsert + reinforce (reinforce_count increments; recency date set)
p="$(mk_profile)"
bash "$HELPER" "$p" dashboard aesthetic-direction minimalist 2026-07-05 >/dev/null 2>&1
bash "$HELPER" "$p" dashboard aesthetic-direction minimalist 2026-07-06 >/dev/null 2>&1
n=$(data_of "$p" | jq '[.entries[] | select(.context=="dashboard" and .value=="minimalist")] | length' 2>/dev/null)
c=$(data_of "$p" | jq '.entries[] | select(.context=="dashboard" and .value=="minimalist") | .reinforce_count' 2>/dev/null)
lr=$(data_of "$p" | jq -r '.entries[] | select(.context=="dashboard" and .value=="minimalist") | .last_reinforced' 2>/dev/null)
if [[ "$n" == "1" && "$c" == "2" && "$lr" == "2026-07-06" ]]; then
  pass "upsert+reinforce (one entry, count=2, recency updated)"
else fail "upsert+reinforce (got n=$n count=$c lr=$lr)"; fi

# 2. Same-context contradiction: differing value → contradictions[] entry + supersede
p="$(mk_profile)"
bash "$HELPER" "$p" landing-page aesthetic-direction editorial 2026-07-05 >/dev/null 2>&1
bash "$HELPER" "$p" landing-page aesthetic-direction maximalist 2026-07-06 >/dev/null 2>&1
cval=$(data_of "$p" | jq -r '.entries[] | select(.context=="landing-page") | .value' 2>/dev/null)
flag=$(data_of "$p" | jq '[.contradictions[] | select(.context=="landing-page" and .old_value=="editorial" and .new_value=="maximalist")] | length' 2>/dev/null)
if [[ "$cval" == "maximalist" && "$flag" == "1" ]]; then
  pass "same-context contradiction flag fires + supersedes (old=editorial→new=maximalist)"
else fail "same-context contradiction (got value=$cval flag=$flag)"; fi

# 3. Cross-context is NOT a contradiction (dashboard + landing coexist)
p="$(mk_profile)"
bash "$HELPER" "$p" dashboard aesthetic-direction minimalist 2026-07-05 >/dev/null 2>&1
bash "$HELPER" "$p" landing-page aesthetic-direction maximalist 2026-07-06 >/dev/null 2>&1
ecount=$(data_of "$p" | jq '.entries | length' 2>/dev/null)
ccount=$(data_of "$p" | jq '.contradictions | length' 2>/dev/null)
if [[ "$ecount" == "2" && "$ccount" == "0" ]]; then
  pass "cross-context NON-contradiction (2 entries, 0 flags)"
else fail "cross-context (got entries=$ecount contradictions=$ccount)"; fi

# 4. Reject out-of-allowlist context (preserve original)
p="$(mk_profile)"; before="$(cat "$p")"
if bash "$HELPER" "$p" 'prod; rm -rf /' aesthetic-direction minimalist 2026-07-05 >/dev/null 2>&1; then
  fail "reject bad context (helper returned 0)"
else
  [[ "$(cat "$p")" == "$before" ]] && pass "reject bad context + preserve original" || fail "bad context mutated file"
fi

# 5. Reject out-of-allowlist axis
p="$(mk_profile)"; before="$(cat "$p")"
if bash "$HELPER" "$p" dashboard color-temperature minimalist 2026-07-05 >/dev/null 2>&1; then
  fail "reject bad axis (helper returned 0)"
else
  [[ "$(cat "$p")" == "$before" ]] && pass "reject out-of-allowlist axis + preserve" || fail "bad axis mutated file"
fi

# 6. Reject metachar/whitespace value
p="$(mk_profile)"; before="$(cat "$p")"
if bash "$HELPER" "$p" dashboard aesthetic-direction 'max; touch /tmp/x' 2026-07-05 >/dev/null 2>&1; then
  fail "reject metachar value (helper returned 0)"
else
  [[ "$(cat "$p")" == "$before" ]] && pass "reject metachar value + preserve" || fail "bad value mutated file"
fi

# 7. Reject malformed date
p="$(mk_profile)"; before="$(cat "$p")"
if bash "$HELPER" "$p" dashboard aesthetic-direction minimalist 'yesterday' >/dev/null 2>&1; then
  fail "reject bad date (helper returned 0)"
else
  [[ "$(cat "$p")" == "$before" ]] && pass "reject malformed date + preserve" || fail "bad date mutated file"
fi

# 8. Freshness: last_updated bumped, last_reviewed byte-unchanged
p="$(mk_profile)"
rev_before=$(awk -F': ' '/^last_reviewed:/{print $2; exit}' "$p")
bash "$HELPER" "$p" docs aesthetic-direction editorial 2026-07-09 >/dev/null 2>&1
upd=$(awk -F': ' '/^last_updated:/{print $2; exit}' "$p")
rev_after=$(awk -F': ' '/^last_reviewed:/{print $2; exit}' "$p")
if [[ "$upd" == "2026-07-09" && "$rev_after" == "$rev_before" ]]; then
  pass "freshness: last_updated bumped, last_reviewed unchanged"
else fail "freshness (last_updated=$upd last_reviewed=$rev_after expected_rev=$rev_before)"; fi

# 9. --validate: passes on a clean profile, fails on a tampered one
p="$(mk_profile)"
bash "$HELPER" "$p" app-ui aesthetic-direction brutalist 2026-07-05 >/dev/null 2>&1
if bash "$HELPER" --validate "$p" >/dev/null 2>&1; then pass "--validate passes on clean profile"; else fail "--validate rejected a clean profile"; fi
# tamper: inject an out-of-allowlist axis directly into the JSON
python3 - "$p" <<'PY' 2>/dev/null || true
import re,sys,json
f=sys.argv[1]; s=open(f).read()
m=re.search(r'```json\n(.*?)\n```', s, re.S)
d=json.loads(m.group(1)); d["entries"].append({"context":"docs","axis":"evil-axis","value":"x","last_reinforced":"2026-07-05","reinforce_count":1})
s=s[:m.start(1)]+json.dumps(d)+s[m.end(1):]; open(f,"w").write(s)
PY
if bash "$HELPER" --validate "$p" >/dev/null 2>&1; then fail "--validate passed a tampered profile"; else pass "--validate fails on tampered profile"; fi

# 9b. --validate also covers contradictions[] (not just entries[]) — the consumer
# read-path trust gate must certify the whole machine block (security P3-1 / user-impact F2).
p="$(mk_profile)"
bash "$HELPER" "$p" landing-page aesthetic-direction editorial 2026-07-05 >/dev/null 2>&1
python3 - "$p" <<'PY' 2>/dev/null || true
import re,sys,json
f=sys.argv[1]; s=open(f).read()
m=re.search(r'```json\n(.*?)\n```', s, re.S)
d=json.loads(m.group(1)); d["contradictions"].append({"context":"landing-page","axis":"aesthetic-direction","old_value":"editorial; rm -rf /","new_value":"maximalist","old_count":1,"date":"2026-07-06"})
s=s[:m.start(1)]+json.dumps(d)+s[m.end(1):]; open(f,"w").write(s)
PY
if bash "$HELPER" --validate "$p" >/dev/null 2>&1; then fail "--validate passed a poisoned contradictions[] entry"; else pass "--validate fails on poisoned contradictions[] (whole-block coverage)"; fi

# 10. No decay/confidence tokens in the helper source (recency, not numeric decay)
if grep -qiE 'halflife|confidence|decay_' "$HELPER" 2>/dev/null; then
  fail "helper contains decay/confidence tokens"
else pass "helper is recency-only (no decay/confidence tokens)"; fi

echo ""
echo "== $pass passed, $fail failed =="
[[ "$fail" -eq 0 ]] || exit 1
