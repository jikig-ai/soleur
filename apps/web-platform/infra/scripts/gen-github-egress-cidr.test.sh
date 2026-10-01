#!/usr/bin/env bash
# Unit tests for gen-github-egress-cidr.sh (#5284) — the self-refreshing GitHub
# /meta CIDR generator. Drives the generator offline against a synthesized
# fixture (cq-test-fixtures-synthesized-only); never touches live /meta.
#
# The carve (#9275): the fixture's `.packages` list models GitHub's Packages
# frontends. The membership oracle is python3 `ipaddress` (an implementation
# independent of the bash carve under test); instrument floors prove the oracle
# actually iterated addresses, and an oracle self-check proves it can go red.
#
# Run: bash apps/web-platform/infra/scripts/gen-github-egress-cidr.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPT_DIR/gen-github-egress-cidr.sh"
LOADER="$SCRIPT_DIR/../cron-egress-nftables.sh"
FIXTURE="$SCRIPT_DIR/../test-fixtures/github-meta-sample.json"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Hermetic DNS: the generator's DNS-sanity guard calls `getent`; a shim first on
# PATH answers from env (SHIM_GITHUB_COM / SHIM_API_GITHUB_COM, "FAIL" or unset =
# lookup failure) so no row depends on the runner's network.
SHIM_DIR="$WORK/shim"
mkdir -p "$SHIM_DIR"
cat > "$SHIM_DIR/getent" <<'EOF'
#!/usr/bin/env bash
[[ -n "${SHIM_LOG:-}" ]] && echo "$*" >> "$SHIM_LOG"
case "${2:-}" in
  github.com) v="${SHIM_GITHUB_COM:-FAIL}" ;;
  api.github.com) v="${SHIM_API_GITHUB_COM:-FAIL}" ;;
  *) exit 2 ;;
esac
[[ "$v" == "FAIL" ]] && exit 2
for ip in $v; do printf '%s      STREAM %s\n' "$ip" "$2"; done
EOF
chmod +x "$SHIM_DIR/getent"
export PATH="$SHIM_DIR:$PATH"

# Synthesized golden body: the (.git+.api) IPv4 union of the fixture minus the
# effective `.packages` holes (192.0.2.33, 192.0.2.34, 198.51.100.164/31,
# 203.0.113.200/31). 198.51.100.77/32 is a hole that equals an exact .git member
# (not carved); 233.252.0.9/32 lies outside every allow prefix (no-op). Derived
# once with python3 ipaddress.address_exclude, sorted as strings (LC_ALL=C order).
read -r -d '' EXPECTED_BODY <<'EOF'
192.0.2.0/27
192.0.2.128/25
192.0.2.32/32
192.0.2.35/32
192.0.2.36/30
192.0.2.40/29
192.0.2.48/28
192.0.2.64/26
198.51.100.0/25
198.51.100.128/27
198.51.100.160/30
198.51.100.166/31
198.51.100.168/29
198.51.100.176/28
198.51.100.192/26
198.51.100.77/32
203.0.113.10/32
203.0.113.11/32
EOF
read -r -d '' EXPECTED_HEADERS <<'EOF'
# Excluded (GitHub Packages frontends): 192.0.2.33/32
# Excluded (GitHub Packages frontends): 192.0.2.34/32
# Excluded (GitHub Packages frontends): 198.51.100.164/31
# Excluded (GitHub Packages frontends): 203.0.113.200/31
EOF
# The plain allow set (no carve) for rows whose holes are all non-effective.
read -r -d '' PLAIN_BODY <<'EOF'
192.0.2.0/24
198.51.100.0/24
198.51.100.77/32
203.0.113.10/32
203.0.113.11/32
203.0.113.200/32
203.0.113.201/32
EOF

# Independent oracle (python3 ipaddress). Property under test (Guard 1): X is in
# the generated list iff X is inside a .git/.api prefix and NOT inside an
# effective .packages hole (hole = .packages IPv4 minus exact .git/.web/.api
# members, prefix >= /28, overlapping the allow list). Prints CHECKED=<n> BAD=<m>.
ORACLE="$WORK/oracle.py"
cat > "$ORACLE" <<'EOF'
import bisect, ipaddress, json, sys
meta = json.load(open(sys.argv[1]))
lines = open(sys.argv[2]).read().splitlines()
v4 = lambda l: [x for x in l if ":" not in x]
allow = [ipaddress.ip_network(x, strict=False) for x in v4(meta["git"] + meta["api"])]
gwa = set(v4(meta["git"] + meta.get("web", []) + meta["api"]))
holes = set()
for x in v4(meta["packages"]):
    if x in gwa:
        continue
    try:
        n = ipaddress.ip_network(x, strict=False)  # leading-zero octets raise: generator skips them too
    except ValueError:
        continue
    if n.prefixlen >= 28 and any(n.overlaps(a) for a in allow):
        holes.add(n)
holes = sorted(holes)
body = [ipaddress.ip_network(l, strict=False) for l in lines if l and not l.startswith("#")]
pre = "# Excluded (GitHub Packages frontends): "
headers = [l[len(pre):] for l in lines if l.startswith(pre)]
bad = []
if sorted(headers) != sorted(str(h) for h in holes):
    bad.append("headers %r != holes %r" % (sorted(headers), sorted(str(h) for h in holes)))
for b in body:
    if not any(b.subnet_of(a) for a in allow):
        bad.append("body prefix %s not inside any allow prefix" % b)
def merge(nets):
    r = sorted((int(n.network_address), int(n.broadcast_address)) for n in nets)
    out = []
    for lo, hi in r:
        if out and lo <= out[-1][1] + 1:
            out[-1][1] = max(out[-1][1], hi)
        else:
            out.append([lo, hi])
    return out
def inside(m, starts, x):
    i = bisect.bisect_right(starts, x) - 1
    return i >= 0 and m[i][0] <= x <= m[i][1]
mb, ma, mh = merge(body), merge(allow), merge(holes)
sb, sa, sh = [r[0] for r in mb], [r[0] for r in ma], [r[0] for r in mh]
uni = set()
for n in allow + holes + body:
    lo, hi = int(n.network_address), int(n.broadcast_address)
    uni.update([lo, hi, lo - 1, hi + 1])
    if hi - lo < 4096:
        uni.update(range(lo, hi + 1))
for h in holes:
    lo = int(h.network_address)
    uni.update([lo - 256, lo + 256])
checked = 0
for x in sorted(uni):
    if x < 0 or x > 0xFFFFFFFF:
        continue
    checked += 1
    want = inside(ma, sa, x) and not inside(mh, sh, x)
    if want != inside(mb, sb, x):
        bad.append("%s want=%s" % (ipaddress.ip_address(x), want))
print("CHECKED=%d BAD=%d" % (checked, len(bad)))
for b in bad[:5]:
    print("  " + b)
EOF

# oracle_check <desc> <meta.json> <out.txt> <floor>
oracle_check() {
  local desc="$1" meta="$2" out="$3" floor="$4" res n b
  res="$(python3 "$ORACLE" "$meta" "$out" 2>&1)"
  n="$(printf '%s\n' "$res" | sed -n 's/^CHECKED=\([0-9]*\) BAD=.*/\1/p')"
  b="$(printf '%s\n' "$res" | sed -n 's/^CHECKED=[0-9]* BAD=\([0-9]*\)/\1/p')"
  if [[ -z "$n" || -z "$b" ]]; then
    fail "$desc (oracle produced no verdict: $(printf '%s' "$res" | head -c 200))"
  elif (( n < floor )); then
    fail "$desc (instrument floor: oracle checked $n addresses, floor $floor)"
  elif (( b != 0 )); then
    fail "$desc (oracle: $b mismatches; $(printf '%s' "$res" | tr '\n' ' ' | head -c 300))"
  else
    pass "$desc (oracle: $n addresses checked, 0 mismatches)"
  fi
}

# gen_ok <meta.json> <out> [env...]: run the generator, return its exit code, stderr in $WORK/err.txt
gen_run() { local meta="$1" out="$2"; shift 2; env "$@" META_JSON_FILE="$meta" OUT="$out" bash "$GEN" >/dev/null 2>"$WORK/err.txt"; }
# with_packages <name> <json-array>: write the fixture with `.packages` replaced
with_packages() { jq --argjson p "$2" '.packages = $p' "$FIXTURE" > "$WORK/$1.json"; }
body_of() { grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null; }

echo "--- gen-github-egress-cidr.sh tests ---"

echo "-- parse + presence --"
if bash -n "$GEN"; then pass "generator parses (bash -n)"; else fail "generator parses (bash -n)"; fi
if [[ -f "$FIXTURE" ]]; then pass "fixture exists"; else fail "fixture exists"; fi

echo "-- golden body + header markers --"
OUT1="$WORK/cidr-golden.txt"
if META_JSON_FILE="$FIXTURE" OUT="$OUT1" bash "$GEN" >/dev/null 2>&1; then
  pass "generates against fixture (exit 0)"
else
  fail "generates against fixture (exit 0)"
fi
ACTUAL_BODY="$(grep -vE '^[[:space:]]*(#|$)' "$OUT1" 2>/dev/null)"
if [[ "$ACTUAL_BODY" == "$EXPECTED_BODY" ]]; then
  pass "body == expected (.git+.api) IPv4 union minus the .packages holes, sort -u"
else
  fail "body mismatch — got:[$ACTUAL_BODY]"
fi
grep -qF 'DO NOT EDIT' "$OUT1" && pass "header carries DO NOT EDIT" || fail "header carries DO NOT EDIT"
grep -qF 'gen-github-egress-cidr.sh' "$OUT1" && pass "header names the generator script" || fail "header names the generator script"
grep -qF 'https://api.github.com/meta' "$OUT1" && pass "header carries source URL" || fail "header carries source URL"
grep -qE '^# Snapshot:' "$OUT1" && pass "header carries a Snapshot: line" || fail "header carries a Snapshot: line"
# Assert the Generated: date SHAPE, not the exact value — a `date -u +%F` capture
# in the test process can differ from the generator's by a day across a UTC
# midnight boundary (rare tail flake). The no-op test below proves the date is
# stamped/not-advanced correctly; here we only need the line to exist + parse.
grep -qE '^# Generated: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$OUT1" && pass "header carries a Generated: YYYY-MM-DD line" || fail "header carries a Generated: date"
grep -qF '(.git+.api)[]|select(test(":")|not)' "$OUT1" && pass "header carries verbatim jq filter (AC2)" || fail "header carries verbatim jq filter"

echo "-- carve (#9275): golden headers, oracle, explicit membership --"
if [[ "$(grep -E '^# Excluded \(GitHub Packages frontends\): ' "$OUT1")" == "$EXPECTED_HEADERS" ]]; then
  pass "Excluded header lines == the effective holes (sorted, one per hole)"
else
  fail "Excluded header lines mismatch — got:[$(grep -E '^# Excluded' "$OUT1" | tr '\n' '|')]"
fi
if [[ "$(grep -cE '^# Excluded' "$OUT1")" -eq "$(grep -cE '^# Excluded \(GitHub Packages frontends\): [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]{1,2}$' "$OUT1")" ]]; then
  pass "every Excluded line matches the documented grep-able shape"
else
  fail "an Excluded line deviates from the documented shape"
fi
if [[ "$(grep -cF '# Excluded (GitHub Packages frontends): <cidr>' "$GEN")" -eq 1 ]]; then
  pass "header pattern documented exactly once in the generator header"
else
  fail "header pattern must be documented exactly once in the generator"
fi
if grep -qF '198.51.100.77/32' <(grep '^# Excluded' "$OUT1") || grep -qF '233.252.0.9' <(grep '^# Excluded' "$OUT1"); then
  fail "exact-overlap hole or outside-every-prefix hole produced an Excluded line"
else
  pass "hole equal to a .git /32 and hole outside every prefix: no Excluded line"
fi
oracle_check "fixture: python oracle over every fixture address" "$FIXTURE" "$OUT1" 500

# Explicit membership via python (independent of the oracle's generality): carved
# IPs denied, neighbours and non-carved fixture IPs admitted.
member() { python3 - "$1" "$2" <<'EOF'
import ipaddress, sys
ip = ipaddress.ip_address(sys.argv[2])
for l in open(sys.argv[1]):
    l = l.strip()
    if l and not l.startswith("#") and ip in ipaddress.ip_network(l, strict=False):
        sys.exit(0)
sys.exit(1)
EOF
}
DENIED_N=0; ADMIT_N=0
for ip in 192.0.2.33 192.0.2.34 198.51.100.164 198.51.100.165 203.0.113.200 203.0.113.201; do
  DENIED_N=$((DENIED_N + 1))
  if member "$OUT1" "$ip"; then fail "carved IP $ip is still admitted"; fi
done
for ip in 192.0.2.32 192.0.2.35 198.51.100.163 198.51.100.166 198.51.100.77 203.0.113.10 203.0.113.11 192.0.2.1 198.51.100.200; do
  ADMIT_N=$((ADMIT_N + 1))
  if ! member "$OUT1" "$ip"; then fail "non-carved IP $ip is no longer admitted"; fi
done
if (( DENIED_N == 6 && ADMIT_N == 9 )) && ! member "$OUT1" 233.252.0.9; then
  pass "carved IPs denied ($DENIED_N), neighbours/non-carved admitted ($ADMIT_N), outside IP never admitted"
else
  fail "explicit membership loop did not run to completion"
fi

echo "-- oracle self-check (the oracle can go RED) --"
cp "$OUT1" "$WORK/tampered.txt"
echo '192.0.2.33/32' >> "$WORK/tampered.txt"
if python3 "$ORACLE" "$FIXTURE" "$WORK/tampered.txt" | grep -qE '^CHECKED=[0-9]+ BAD=[1-9]'; then
  pass "oracle flags a re-admitted carved IP"
else
  fail "oracle did not flag a re-admitted carved IP (vacuous oracle)"
fi
cp "$OUT1" "$WORK/tampered2.txt"
sed -i '/^203.0.113.10\/32$/d' "$WORK/tampered2.txt"
if python3 "$ORACLE" "$FIXTURE" "$WORK/tampered2.txt" | grep -qE '^CHECKED=[0-9]+ BAD=[1-9]'; then
  pass "oracle flags a dropped allow IP"
else
  fail "oracle did not flag a dropped allow IP"
fi

echo "-- IPv6 drop + dedup --"
if ! printf '%s' "$ACTUAL_BODY" | grep -c ':' >/dev/null; then pass "IPv6 entries dropped (no ':' in body)"; else fail "IPv6 entries dropped"; fi
# 203.0.113.10/32 is listed twice in .api (192.0.2.0/24, the .git duplicate, is
# now carved, so it no longer survives to the body).
DUP_N="$(grep -cxF '203.0.113.10/32' "$OUT1")"
if [[ "$DUP_N" -eq 1 ]]; then pass "duplicate collapsed (203.0.113.10/32 once)"; else fail "duplicate collapsed (got $DUP_N)"; fi

echo "-- fail-loud on bad input (file untouched, exit non-zero) --"
assert_reject() { # $1 desc, $2 meta-json-content
  local desc="$1" content="$2"
  local guard="$WORK/guard-$RANDOM.txt"
  printf 'SENTINEL\n' > "$guard"
  local bad="$WORK/bad-$RANDOM.json"
  printf '%s' "$content" > "$bad"
  if META_JSON_FILE="$bad" OUT="$guard" bash "$GEN" >/dev/null 2>&1; then
    fail "$desc (should exit non-zero)"
  elif [[ "$(cat "$guard")" == "SENTINEL" ]] && [[ -z "$(ls "$guard".* 2>/dev/null)" ]]; then
    pass "$desc (rejected; output untouched; no stray tmp)"
  else
    fail "$desc (output mutated or stray tmp left)"
  fi
}
# Each inline row carries a valid .packages so it keeps proving the case it was
# written for rather than tripping the new .packages shape guard first.
assert_reject "non-JSON body"        'not json at all'
assert_reject "empty object {}"      '{}'
assert_reject "missing .api key"     '{"git":["192.0.2.0/24"],"packages":["233.252.0.9/32"]}'
assert_reject "IPv6-only (empty extraction)" '{"git":["2001:db8::/48"],"api":["2001:db8:1::/48"],"packages":["233.252.0.9/32"]}'
assert_reject "over-broad 0.0.0.0/0" '{"git":["0.0.0.0/0"],"api":["203.0.113.10/32"],"packages":["233.252.0.9/32"]}'
assert_reject "over-broad /4 prefix" '{"git":["10.0.0.0/4"],"api":["203.0.113.10/32"],"packages":["233.252.0.9/32"]}'
assert_reject "nft-injection shape"  '{"git":["192.0.2.0/24}; add rule x"],"api":["203.0.113.10/32"],"packages":["233.252.0.9/32"]}'

echo "-- date-header no-op (body unchanged → byte-identical, date not advanced) --"
OUT2="$WORK/cidr-noop.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT2" bash "$GEN" >/dev/null 2>&1
# Backdate the Generated: line to prove a no-op re-run does NOT restamp it.
sed -i -E 's/^# Generated: .*/# Generated: 2000-01-01/' "$OUT2"
BEFORE="$(cat "$OUT2")"
META_JSON_FILE="$FIXTURE" OUT="$OUT2" bash "$GEN" >/dev/null 2>&1
AFTER="$(cat "$OUT2")"
if [[ "$BEFORE" == "$AFTER" ]]; then
  pass "no-op re-run leaves file byte-identical (date not advanced)"
else
  fail "no-op re-run rewrote the file (date churn)"
fi

echo "-- idempotent (two fresh runs byte-identical) --"
OUT3="$WORK/cidr-a.txt"; OUT4="$WORK/cidr-b.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT3" bash "$GEN" >/dev/null 2>&1
META_JSON_FILE="$FIXTURE" OUT="$OUT4" bash "$GEN" >/dev/null 2>&1
if diff -q "$OUT3" "$OUT4" >/dev/null; then pass "two fresh runs byte-identical"; else fail "two fresh runs differ"; fi

echo "-- --check mode --"
OUT5="$WORK/cidr-check.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT5" bash "$GEN" >/dev/null 2>&1
if META_JSON_FILE="$FIXTURE" OUT="$OUT5" bash "$GEN" --check >/dev/null 2>&1; then
  pass "--check exits 0 when committed body matches /meta"
else
  fail "--check exits 0 when matches"
fi
# Mutate the body → drift → --check must exit 1.
sed -i 's#203.0.113.11/32#203.0.113.99/32#' "$OUT5"
if META_JSON_FILE="$FIXTURE" OUT="$OUT5" bash "$GEN" --check >/dev/null 2>&1; then
  fail "--check exits 1 on body drift"
else
  pass "--check exits 1 on body drift"
fi

echo "-- .packages shape guard (rows 1.2): refuse to write a file that silently stops carving --"
shape_row() { # $1 desc, $2 jq program applied to the fixture, $3 regex the die message must match
  local desc="$1" bad="$WORK/shape-$RANDOM.json" guard="$WORK/shape-guard-$RANDOM.txt"
  jq "$2" "$FIXTURE" > "$bad"
  printf 'SENTINEL\n' > "$guard"
  if gen_run "$bad" "$guard"; then
    fail "$desc (should exit non-zero)"
  elif ! grep -qE "ERROR:.*$3" "$WORK/err.txt"; then
    fail "$desc (rejected, but not by the intended guard; wanted ERROR:.*$3, got: $(head -c 200 "$WORK/err.txt"))"
  elif [[ "$(cat "$guard")" == "SENTINEL" ]] && [[ -z "$(ls "$guard".* 2>/dev/null)" ]]; then
    pass "$desc (rejected; output untouched; no stray tmp)"
  else
    fail "$desc (output mutated or stray tmp left)"
  fi
}
shape_row ".packages absent"                    'del(.packages)' '\.packages'
shape_row ".packages null"                      '.packages = null' '\.packages'
shape_row ".packages a string"                  '.packages = "192.0.2.33/32"' '\.packages'
shape_row ".packages an object"                 '.packages = {"a":"192.0.2.33/32"}' '\.packages'
shape_row ".packages empty array"               '.packages = []' '\.packages'
shape_row ".packages IPv6-only (empty IPv4 extraction)" '.packages = ["2001:db8:pkg::/48"]' '\.packages'
shape_row ".packages holds a non-string"        '.packages = ["192.0.2.33/32", 7]' '\.packages'
shape_row ".web present but not an array"       '.web = "192.0.2.0/24"' '\.web'
shape_row "invalid hole CIDR (garbage)"         '.packages = ["not-a-cidr"]' 'invalid CIDR in /meta \.packages'
shape_row "invalid hole CIDR (nft-injection shape)" '.packages = ["192.0.2.33/32}; add rule x"]' 'invalid CIDR in /meta \.packages'
shape_row "invalid hole CIDR (octet > 255)"     '.packages = ["192.0.2.256/32"]' 'invalid CIDR in /meta \.packages'

echo "-- missing .web is tolerated: (.web // []) --"
jq 'del(.web)' "$FIXTURE" > "$WORK/noweb.json"
if gen_run "$WORK/noweb.json" "$WORK/noweb.out"; then
  pass "meta without .web generates (exit 0)"
  oracle_check "no-.web fixture" "$WORK/noweb.json" "$WORK/noweb.out" 500
else
  fail "meta without .web must still generate (shape guard only requires git/api)"
fi

echo "-- must-PASS: only holes outside every allow prefix / equal to exact members (zero effective) --"
with_packages zero-eff '["233.252.0.9/32","198.51.100.77/32","2001:db8:pkg::/48"]'
if gen_run "$WORK/zero-eff.json" "$WORK/zero-eff.out"; then
  pass "zero effective holes exits 0 (availability over containment)"
else
  fail "zero effective holes must exit 0"
fi
if [[ "$(body_of "$WORK/zero-eff.out")" == "$PLAIN_BODY" ]]; then
  pass "zero effective holes: body equals the plain allow set"
else
  fail "zero effective holes: body differs from the plain allow set — got:[$(body_of "$WORK/zero-eff.out" | tr '\n' ' ')]"
fi
if grep -q '^# Excluded' "$WORK/zero-eff.out"; then fail "zero effective holes: unexpected Excluded line"; else pass "zero effective holes: no Excluded line"; fi
if grep -qE 'WARN.*no effective' "$WORK/err.txt"; then pass "zero effective holes: WARN on stderr"; else fail "zero effective holes: WARN missing (stderr: $(head -c 200 "$WORK/err.txt"))"; fi
oracle_check "zero-effective fixture" "$WORK/zero-eff.json" "$WORK/zero-eff.out" 500

echo "-- DNS sanity: github.com / api.github.com must never resolve into a hole --"
dns_die_row() { # $1 desc, $2.. env assignments
  local desc="$1" guard="$WORK/dns-guard-$RANDOM.txt"; shift
  printf 'SENTINEL\n' > "$guard"
  if gen_run "$FIXTURE" "$guard" "$@"; then
    fail "$desc (should exit non-zero)"
  elif ! grep -qF 'ghcr-carve-would-cut-github' "$WORK/err.txt"; then
    fail "$desc (died without the distinct message ghcr-carve-would-cut-github: $(head -c 200 "$WORK/err.txt"))"
  elif [[ "$(cat "$guard")" == "SENTINEL" ]] && [[ -z "$(ls "$guard".* 2>/dev/null)" ]]; then
    pass "$desc (died ghcr-carve-would-cut-github; output untouched)"
  else
    fail "$desc (output mutated or stray tmp left)"
  fi
}
dns_die_row "github.com resolves into a /32 hole"  SHIM_GITHUB_COM="192.0.2.33"
dns_die_row "api.github.com resolves into a /32 hole" SHIM_API_GITHUB_COM="192.0.2.34"
dns_die_row "api.github.com resolves into a /31 hole (second address)" SHIM_API_GITHUB_COM="198.51.100.165"
dns_die_row "one clean answer then one inside a hole" SHIM_GITHUB_COM="192.0.2.1 203.0.113.201"
dns_ok_row() { # $1 desc, $2.. env assignments
  local desc="$1" out="$WORK/dns-ok-$RANDOM.txt"; shift
  : > "$WORK/shim.log"
  if gen_run "$FIXTURE" "$out" SHIM_LOG="$WORK/shim.log" "$@" && [[ "$(body_of "$out")" == "$EXPECTED_BODY" ]]; then
    pass "$desc (file written, golden body)"
  else
    fail "$desc (should write the golden body; stderr: $(head -c 200 "$WORK/err.txt"))"
  fi
}
dns_ok_row "answers outside every hole (neighbours .32/.35/.163/.166)" SHIM_GITHUB_COM="192.0.2.32 192.0.2.35" SHIM_API_GITHUB_COM="198.51.100.163 198.51.100.166"
if grep -qF 'github.com' "$WORK/shim.log" && grep -qF 'api.github.com' "$WORK/shim.log"; then
  pass "DNS guard consulted getent for both github.com and api.github.com"
else
  fail "DNS guard did not consult getent for both names (log: $(head -c 120 "$WORK/shim.log"))"
fi
dns_ok_row "lookup failure only warns" SHIM_GITHUB_COM=FAIL SHIM_API_GITHUB_COM=FAIL
if grep -qE 'WARN.*(lookup|getent)' "$WORK/err.txt"; then pass "failed lookup logged as WARN"; else fail "failed lookup produced no WARN"; fi
dns_ok_row "answer is IPv6/garbage (ignored, not a hole hit)" SHIM_GITHUB_COM="2001:db8::1 not-an-ip"

# getent absent from PATH: a minimal tool dir with everything the generator
# needs except getent (the cron's minimal image may lack it).
NOGETENT="$WORK/nogetent"; mkdir -p "$NOGETENT"
for t in jq sort comm sed cat mktemp mv rm date dirname awk grep tr head timeout; do
  tp="$(command -v "$t" 2>/dev/null)" && ln -sf "$tp" "$NOGETENT/$t"
done
if env PATH="$NOGETENT" META_JSON_FILE="$FIXTURE" OUT="$WORK/nogetent.out" "$(command -v bash)" "$GEN" >/dev/null 2>"$WORK/err.txt" \
   && [[ "$(body_of "$WORK/nogetent.out")" == "$EXPECTED_BODY" ]] && grep -qE 'WARN.*getent' "$WORK/err.txt"; then
  pass "getent absent: WARN, file still written (guard degrades)"
else
  fail "getent absent must WARN and still write (stderr: $(head -c 200 "$WORK/err.txt"))"
fi

echo "-- hostile .packages (rows 1.2.4): the daily direct-merge run treats /meta as untrusted --"
with_packages broad '["192.0.0.0/8","0.0.0.0/0","192.0.2.0/27","192.0.2.0/24"]'
if gen_run "$WORK/broad.json" "$WORK/broad.out"; then
  [[ "$(body_of "$WORK/broad.out")" == "$PLAIN_BODY" ]] && ! grep -q '^# Excluded' "$WORK/broad.out" \
    && grep -qE 'WARN.*(/28|shorter|too broad|skip)' "$WORK/err.txt" \
    && pass "holes shorter than /28 (/8, /0, /27, /24) skipped with WARN; nothing carved" \
    || fail "hostile broad holes: body/headers/WARN wrong (stderr: $(head -c 200 "$WORK/err.txt"))"
else
  fail "hostile broad holes must be skipped, not abort (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
oracle_check "broad-hole fixture" "$WORK/broad.json" "$WORK/broad.out" 500

with_packages boundary28 '["192.0.2.16/28"]'
if gen_run "$WORK/boundary28.json" "$WORK/boundary28.out"; then
  oracle_check "a /28 hole is the shortest applied (boundary)" "$WORK/boundary28.json" "$WORK/boundary28.out" 500
  grep -qxF '# Excluded (GitHub Packages frontends): 192.0.2.16/28' "$WORK/boundary28.out" \
    && pass "/28 hole listed in the header" || fail "/28 hole missing from the header"
else
  fail "a /28 hole must generate"
fi

with_packages unaligned '["192.0.2.33/31"]'
if gen_run "$WORK/unaligned.json" "$WORK/unaligned.out"; then
  grep -qxF '# Excluded (GitHub Packages frontends): 192.0.2.32/31' "$WORK/unaligned.out" \
    && pass "hole with host bits set is canonicalised (192.0.2.33/31 -> 192.0.2.32/31)" \
    || fail "unaligned hole not canonicalised in the header"
  oracle_check "unaligned-hole fixture" "$WORK/unaligned.json" "$WORK/unaligned.out" 500
else
  fail "an unaligned hole must generate"
fi

with_packages nested '["192.0.2.32/28","192.0.2.33/32","192.0.2.32/30","192.0.2.32/28"]'
if gen_run "$WORK/nested.json" "$WORK/nested.out"; then
  oracle_check "nested + duplicate holes" "$WORK/nested.json" "$WORK/nested.out" 500
else
  fail "nested holes must generate (stderr: $(head -c 200 "$WORK/err.txt"))"
fi

with_packages leadzero '["192.0.2.033/32","192.0.2.08/32","192.0.2.09/32","192.0.02.5/32"]'
if gen_run "$WORK/leadzero.json" "$WORK/leadzero.out"; then
  if grep -qiE 'value too great|invalid arithmetic|octal' "$WORK/err.txt"; then
    fail "leading-zero octet leaked an octal arithmetic error: $(head -c 200 "$WORK/err.txt")"
  elif [[ "$(body_of "$WORK/leadzero.out")" == "$PLAIN_BODY" ]] && grep -qiE 'WARN.*(leading|non-canonical)' "$WORK/err.txt"; then
    pass "leading-zero octets skipped with WARN (no octal abort, nothing carved)"
  else
    fail "leading-zero holes: expected plain body + WARN (stderr: $(head -c 200 "$WORK/err.txt"))"
  fi
else
  fail "leading-zero holes must be skipped, not abort (stderr: $(head -c 200 "$WORK/err.txt"))"
fi

# A leading-zero octet inside an ALLOW prefix (the validator accepts 010 silently,
# as octal 8) must be read as decimal 10 (10# arithmetic) so the carve agrees with
# the exact-match hole 198.51.100.10/32 and removes it; octal reading would keep it.
jq -n '{git:["198.51.100.010/32","192.0.2.0/24"],api:["203.0.113.10/32"],packages:["198.51.100.10/32"]}' > "$WORK/leadallow.json"
if gen_run "$WORK/leadallow.json" "$WORK/leadallow.out"; then
  if grep -qiE 'value too great|invalid arithmetic|octal' "$WORK/err.txt"; then
    fail "leading-zero allow octet leaked an octal arithmetic error"
  elif [[ "$(body_of "$WORK/leadallow.out")" == "$(printf '192.0.2.0/24\n203.0.113.10/32')" ]] \
       && grep -qxF '# Excluded (GitHub Packages frontends): 198.51.100.10/32' "$WORK/leadallow.out"; then
    pass "leading-zero allow octet (010) read as decimal 10: carved by the matching hole"
  else
    fail "leading-zero allow octet misparsed (body: $(body_of "$WORK/leadallow.out" | tr '\n' ' '))"
  fi
else
  fail "leading-zero allow octet 010 must generate (stderr: $(head -c 200 "$WORK/err.txt"))"
fi

# Holes cap: 64 effective holes pass, 65 die.
hole_json() { python3 -c 'import json,sys; print(json.dumps(["192.0.2.%d/32" % (i + 100) for i in range(int(sys.argv[1]))]))' "$1"; }
with_packages holes64 "$(hole_json 64)"
if gen_run "$WORK/holes64.json" "$WORK/holes64.out"; then
  grep -c '^# Excluded' "$WORK/holes64.out" | grep -qx 64 && pass "64 effective holes accepted (cap boundary)" || fail "64 holes: header count != 64"
  oracle_check "64-hole fixture" "$WORK/holes64.json" "$WORK/holes64.out" 500
else
  fail "64 effective holes must be accepted (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
with_packages holes65 "$(hole_json 65)"
HG="$WORK/holes65-guard.txt"; printf 'SENTINEL\n' > "$HG"
if gen_run "$WORK/holes65.json" "$HG"; then
  fail "65 effective holes must die (cap 64)"
elif [[ "$(cat "$HG")" == "SENTINEL" ]]; then
  pass "65 effective holes die (cap 64); output untouched"
else
  fail "65 holes: output mutated"
fi

# Output cap: 2048 lines pass, 2049 die (an allow list this large is not GitHub's /meta).
big_json() { python3 -c '
import json, sys
n = int(sys.argv[1])
ips = ["10.%d.%d.%d/32" % (i >> 16 & 255, i >> 8 & 255, i & 255) for i in range(n)]
print(json.dumps({"git": ips, "api": ["203.0.113.10/32"], "packages": ["233.252.0.9/32"]}))' "$1"; }
big_json 2047 > "$WORK/big2048.json"   # 2047 + 1 api = 2048 lines
if gen_run "$WORK/big2048.json" "$WORK/big2048.out" && [[ "$(body_of "$WORK/big2048.out" | wc -l)" -eq 2048 ]]; then
  pass "2048 output lines accepted (cap boundary)"
else
  fail "2048 output lines must be accepted (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
big_json 2048 > "$WORK/big2049.json"   # 2048 + 1 api = 2049 lines
BG="$WORK/big-guard.txt"; printf 'SENTINEL\n' > "$BG"
if gen_run "$WORK/big2049.json" "$BG"; then
  fail "2049 output lines must die (cap 2048)"
elif [[ "$(cat "$BG")" == "SENTINEL" ]]; then
  pass "2049 output lines die (cap 2048); output untouched"
else
  fail "2049 lines: output mutated"
fi

echo "-- --check covers the Excluded header (consumers read it) --"
OUT6="$WORK/cidr-check-hdr.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT6" bash "$GEN" >/dev/null 2>&1
sed -i '0,/^# Excluded/{//d}' "$OUT6"
if META_JSON_FILE="$FIXTURE" OUT="$OUT6" bash "$GEN" --check >/dev/null 2>&1; then
  fail "--check must exit 1 when an Excluded header line is dropped"
else
  pass "--check exits 1 when an Excluded header line is dropped"
fi

echo "-- validator parity with the loader (#5268) --"
# The generator must carry the loader's is_valid_ipv4_cidr regex byte-for-byte.
CIDR_RE='([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})'
CIDR_RANGE='o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32'
if grep -qF -- "$CIDR_RE" "$GEN" && grep -qF -- "$CIDR_RE" "$LOADER"; then
  pass "CIDR regex literal pinned identically in generator and loader"
else
  fail "CIDR regex literal drift between generator and loader"
fi
if grep -qF -- "$CIDR_RANGE" "$GEN" && grep -qF -- "$CIDR_RANGE" "$LOADER"; then
  pass "CIDR range-check arithmetic pinned identically in generator and loader"
else
  fail "CIDR range-check drift between generator and loader"
fi

echo "-- atomic-write invariants (source-shape) --"
grep -qF "trap 'rm -f" "$GEN" && pass "EXIT trap removes the temp file on failure" || fail "EXIT trap present"
grep -qE 'mktemp .*\$\{?OUT' "$GEN" && pass "mktemp in the target dir (atomic mv, same fs)" || fail "mktemp in the target dir"
grep -qF 'curl -fsS --max-time 30' "$GEN" && pass "live fetch is bounded (curl --max-time 30, AC11)" || fail "live fetch bounded"

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
