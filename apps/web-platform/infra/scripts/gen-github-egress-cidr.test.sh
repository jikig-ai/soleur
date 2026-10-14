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
CASES=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
# Every verdict in this file goes through ok()/no(), the CALL-SITE counter: CASES moves at the
# call site, independent of what pass()/fail() do, so the PASS+FAIL==CASES conservation check at
# the bottom catches a neutered pass()/fail() (a stubbed fail() still leaves CASES moving, and
# the discarded verdict shows up as PASS+FAIL < CASES). Without it a no-op fail() plus a seeded
# defect reported "all passed" (review finding C5).
ok() { CASES=$((CASES + 1)); pass "$1"; }
no() { CASES=$((CASES + 1)); fail "$1"; }

# Positive control: drive each verdict path once and require BOTH counters (and the call-site
# counter) to move, then unwind so the control is not itself a verdict. Reported with printf +
# exit, never through the machinery it witnesses.
_pc_p=$PASS; _pc_f=$FAIL; _pc_c=$CASES
ok "positive control" >/dev/null
no "positive control" >/dev/null
if (( PASS != _pc_p + 1 || FAIL != _pc_f + 1 || CASES != _pc_c + 2 )); then
  printf '[FATAL] positive control: pass()/fail() did not move their counters (PASS %d->%d, FAIL %d->%d, CASES %d->%d)\n' \
    "$_pc_p" "$PASS" "$_pc_f" "$FAIL" "$_pc_c" "$CASES" >&2
  exit 2
fi
PASS=$_pc_p; FAIL=$_pc_f; CASES=$_pc_c

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
# 203.0.113.200/31). Three .packages entries equal an exact member of ONE list each and
# are never carved: 198.51.100.77/32 (.git), 198.51.100.90/32 (.web ONLY) and
# 203.0.113.50/32 (.api ONLY); 233.252.0.9/32 lies outside every allow prefix (no-op). Derived
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
203.0.113.50/32
EOF
read -r -d '' EXPECTED_HEADERS <<'EOF'
# Excluded (GitHub Packages frontends): 192.0.2.33/32
# Excluded (GitHub Packages frontends): 192.0.2.34/32
# Excluded (GitHub Packages frontends): 198.51.100.164/31
# Excluded (GitHub Packages frontends): 203.0.113.200/31
EOF
# Fixture with ONE effective hole (192.0.2.33/32) plus one outside-prefix hole
# (233.252.0.9/32): the body is the plain allow set carved for the effective one only.
# Derived with python3 ipaddress.address_exclude.
read -r -d '' ONEHOLE_BODY <<'EOF'
192.0.2.0/27
192.0.2.128/25
192.0.2.32/32
192.0.2.34/31
192.0.2.36/30
192.0.2.40/29
192.0.2.48/28
192.0.2.64/26
198.51.100.0/24
198.51.100.77/32
203.0.113.10/32
203.0.113.11/32
203.0.113.200/32
203.0.113.201/32
203.0.113.50/32
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
    no "$desc (oracle produced no verdict: $(printf '%s' "$res" | head -c 200))"
  elif (( n < floor )); then
    no "$desc (instrument floor: oracle checked $n addresses, floor $floor)"
  elif (( b != 0 )); then
    no "$desc (oracle: $b mismatches; $(printf '%s' "$res" | tr '\n' ' ' | head -c 300))"
  else
    ok "$desc (oracle: $n addresses checked, 0 mismatches)"
  fi
}

# gen_ok <meta.json> <out> [env...]: run the generator, return its exit code, stderr in $WORK/err.txt
gen_run() { local meta="$1" out="$2"; shift 2; env "$@" META_JSON_FILE="$meta" OUT="$out" bash "$GEN" >/dev/null 2>"$WORK/err.txt"; }
# with_packages <name> <json-array>: write the fixture with `.packages` replaced
with_packages() { jq --argjson p "$2" '.packages = $p' "$FIXTURE" > "$WORK/$1.json"; }
body_of() { grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null; }

echo "--- gen-github-egress-cidr.sh tests ---"

echo "-- parse + presence --"
if bash -n "$GEN"; then ok "generator parses (bash -n)"; else no "generator parses (bash -n)"; fi
if [[ -f "$FIXTURE" ]]; then ok "fixture exists"; else no "fixture exists"; fi

echo "-- golden body + header markers --"
OUT1="$WORK/cidr-golden.txt"
if META_JSON_FILE="$FIXTURE" OUT="$OUT1" bash "$GEN" >/dev/null 2>&1; then
  ok "generates against fixture (exit 0)"
else
  no "generates against fixture (exit 0)"
fi
ACTUAL_BODY="$(grep -vE '^[[:space:]]*(#|$)' "$OUT1" 2>/dev/null)"
if [[ "$ACTUAL_BODY" == "$EXPECTED_BODY" ]]; then
  ok "body == expected (.git+.api) IPv4 union minus the .packages holes, sort -u"
else
  no "body mismatch — got:[$ACTUAL_BODY]"
fi
grep -qF 'DO NOT EDIT' "$OUT1" && ok "header carries DO NOT EDIT" || no "header carries DO NOT EDIT"
grep -qF 'gen-github-egress-cidr.sh' "$OUT1" && ok "header names the generator script" || no "header names the generator script"
grep -qF 'https://api.github.com/meta' "$OUT1" && ok "header carries source URL" || no "header carries source URL"
grep -qE '^# Snapshot:' "$OUT1" && ok "header carries a Snapshot: line" || no "header carries a Snapshot: line"
# Assert the Generated: date SHAPE, not the exact value — a `date -u +%F` capture
# in the test process can differ from the generator's by a day across a UTC
# midnight boundary (rare tail flake). The no-op test below proves the date is
# stamped/not-advanced correctly; here we only need the line to exist + parse.
grep -qE '^# Generated: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$OUT1" && ok "header carries a Generated: YYYY-MM-DD line" || no "header carries a Generated: date"
grep -qF '(.git+.api)[]|select(test(":")|not)' "$OUT1" && ok "header carries verbatim jq filter (AC2)" || no "header carries verbatim jq filter"

echo "-- carve (#9275): golden headers, oracle, explicit membership --"
if [[ "$(grep -E '^# Excluded \(GitHub Packages frontends\): ' "$OUT1")" == "$EXPECTED_HEADERS" ]]; then
  ok "Excluded header lines == the effective holes (sorted, one per hole)"
else
  no "Excluded header lines mismatch — got:[$(grep -E '^# Excluded' "$OUT1" | tr '\n' '|')]"
fi
if [[ "$(grep -cE '^# Excluded' "$OUT1")" -eq "$(grep -cE '^# Excluded \(GitHub Packages frontends\): [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]{1,2}$' "$OUT1")" ]]; then
  ok "every Excluded line matches the documented grep-able shape"
else
  no "an Excluded line deviates from the documented shape"
fi
if [[ "$(grep -cF '# Excluded (GitHub Packages frontends): <cidr>' "$GEN")" -eq 1 ]]; then
  ok "header pattern documented exactly once in the generator header"
else
  no "header pattern must be documented exactly once in the generator"
fi
# Exact-member protection is a UNION over .git/.web/.api (plan Design item 1): a .packages
# entry /meta also lists as the same range in ANY of the three lists is never carved. That
# includes a .web-ONLY member, although .web is not an allow source, so the protection is a
# deliberate proxy (198.51.100.90/32 stays admitted via its covering .git /24). The runtime
# probe, not this generator, is the control for that residual; this row pins the behaviour so
# it can only change on purpose. The .api-ONLY member (203.0.113.50/32) is the same shape and
# there the carve would otherwise delete the only entry admitting it.
if grep '^# Excluded' "$OUT1" | grep -cE '198\.51\.100\.77/32|198\.51\.100\.90/32|203\.0\.113\.50/32|233\.252\.0\.9' >/dev/null; then
  no "exact-member hole (.git / .web-only / .api-only) or outside-every-prefix hole produced an Excluded line"
else
  ok "holes equal to an exact .git, .web-only or .api-only member, and a hole outside every prefix: no Excluded line"
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
DENIED_N=0; ADMIT_N=0; MEMBER_BAD=""
for ip in 192.0.2.33 192.0.2.34 198.51.100.164 198.51.100.165 203.0.113.200 203.0.113.201; do
  DENIED_N=$((DENIED_N + 1))
  if member "$OUT1" "$ip"; then MEMBER_BAD="$MEMBER_BAD carved-IP-$ip-still-admitted"; fi
done
for ip in 192.0.2.32 192.0.2.35 198.51.100.163 198.51.100.166 198.51.100.77 198.51.100.90 203.0.113.10 203.0.113.11 203.0.113.50 192.0.2.1 198.51.100.200; do
  ADMIT_N=$((ADMIT_N + 1))
  if ! member "$OUT1" "$ip"; then MEMBER_BAD="$MEMBER_BAD non-carved-IP-$ip-no-longer-admitted"; fi
done
if member "$OUT1" 233.252.0.9; then MEMBER_BAD="$MEMBER_BAD outside-IP-admitted"; fi
if (( DENIED_N != 6 || ADMIT_N != 11 )); then
  no "explicit membership loop did not run to completion (denied=$DENIED_N admit=$ADMIT_N)"
elif [[ -n "$MEMBER_BAD" ]]; then
  no "explicit membership wrong:$MEMBER_BAD"
else
  ok "carved IPs denied ($DENIED_N), neighbours/exact-member/non-carved admitted ($ADMIT_N), outside IP never admitted"
fi

echo "-- oracle self-check (the oracle can go RED) --"
cp "$OUT1" "$WORK/tampered.txt"
echo '192.0.2.33/32' >> "$WORK/tampered.txt"
if python3 "$ORACLE" "$FIXTURE" "$WORK/tampered.txt" | grep -cE '^CHECKED=[0-9]+ BAD=[1-9]' >/dev/null; then
  ok "oracle flags a re-admitted carved IP"
else
  no "oracle did not flag a re-admitted carved IP (vacuous oracle)"
fi
cp "$OUT1" "$WORK/tampered2.txt"
sed -i '/^203.0.113.10\/32$/d' "$WORK/tampered2.txt"
if python3 "$ORACLE" "$FIXTURE" "$WORK/tampered2.txt" | grep -cE '^CHECKED=[0-9]+ BAD=[1-9]' >/dev/null; then
  ok "oracle flags a dropped allow IP"
else
  no "oracle did not flag a dropped allow IP"
fi

echo "-- IPv6 drop + dedup --"
if ! printf '%s' "$ACTUAL_BODY" | grep -c ':' >/dev/null; then ok "IPv6 entries dropped (no ':' in body)"; else no "IPv6 entries dropped"; fi
# 203.0.113.10/32 is listed twice in .api (192.0.2.0/24, the .git duplicate, is
# now carved, so it no longer survives to the body).
DUP_N="$(grep -cxF '203.0.113.10/32' "$OUT1")"
if [[ "$DUP_N" -eq 1 ]]; then ok "duplicate collapsed (203.0.113.10/32 once)"; else no "duplicate collapsed (got $DUP_N)"; fi

echo "-- fail-loud on bad input (file untouched, exit non-zero) --"
assert_reject() { # $1 desc, $2 meta-json-content, $3 optional regex the die message must match
  local desc="$1" content="$2" want="${3:-}"
  local guard="$WORK/guard-$RANDOM.txt"
  printf 'SENTINEL\n' > "$guard"
  local bad="$WORK/bad-$RANDOM.json"
  printf '%s' "$content" > "$bad"
  if META_JSON_FILE="$bad" OUT="$guard" bash "$GEN" >/dev/null 2>"$WORK/err.txt"; then
    no "$desc (should exit non-zero)"
  elif [[ -n "$want" ]] && ! grep -qE "ERROR:.*$want" "$WORK/err.txt"; then
    no "$desc (rejected, but not by the intended guard; wanted ERROR:.*$want, got: $(head -c 200 "$WORK/err.txt"))"
  elif [[ "$(cat "$guard")" == "SENTINEL" ]] && [[ -z "$(ls "$guard".* 2>/dev/null)" ]]; then
    ok "$desc (rejected; output untouched; no stray tmp)"
  else
    no "$desc (output mutated or stray tmp left)"
  fi
}
# Each inline row carries a valid .packages so it keeps proving the case it was
# written for rather than tripping the new .packages shape guard first.
assert_reject "non-JSON body"        'not json at all' 'missing \.git/\.api'
assert_reject "empty object {}"      '{}' 'missing \.git/\.api'
assert_reject "missing .api key"     '{"git":["192.0.2.0/24"],"packages":["233.252.0.9/32"]}' 'missing \.git/\.api'
assert_reject "IPv6-only (empty extraction)" '{"git":["2001:db8::/48"],"api":["2001:db8:1::/48"],"packages":["233.252.0.9/32"]}' 'empty extraction'
assert_reject "over-broad 0.0.0.0/0" '{"git":["0.0.0.0/0"],"api":["203.0.113.10/32"],"packages":["233.252.0.9/32"]}' 'over-broad CIDR'
assert_reject "over-broad /4 prefix" '{"git":["10.0.0.0/4"],"api":["203.0.113.10/32"],"packages":["233.252.0.9/32"]}' 'over-broad CIDR'
assert_reject "nft-injection shape"  '{"git":["192.0.2.0/24}; add rule x"],"api":["203.0.113.10/32"],"packages":["233.252.0.9/32"]}' 'invalid CIDR from /meta'

echo "-- date-header no-op (body unchanged → byte-identical, date not advanced) --"
OUT2="$WORK/cidr-noop.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT2" bash "$GEN" >/dev/null 2>&1
# Backdate the Generated: line to prove a no-op re-run does NOT restamp it.
sed -i -E 's/^# Generated: .*/# Generated: 2000-01-01/' "$OUT2"
BEFORE="$(cat "$OUT2")"
META_JSON_FILE="$FIXTURE" OUT="$OUT2" bash "$GEN" >/dev/null 2>&1
AFTER="$(cat "$OUT2")"
if [[ "$BEFORE" == "$AFTER" ]]; then
  ok "no-op re-run leaves file byte-identical (date not advanced)"
else
  no "no-op re-run rewrote the file (date churn)"
fi

echo "-- idempotent (two fresh runs byte-identical) --"
OUT3="$WORK/cidr-a.txt"; OUT4="$WORK/cidr-b.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT3" bash "$GEN" >/dev/null 2>&1
META_JSON_FILE="$FIXTURE" OUT="$OUT4" bash "$GEN" >/dev/null 2>&1
if diff -q "$OUT3" "$OUT4" >/dev/null; then ok "two fresh runs byte-identical"; else no "two fresh runs differ"; fi

echo "-- --check mode --"
OUT5="$WORK/cidr-check.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT5" bash "$GEN" >/dev/null 2>&1
if META_JSON_FILE="$FIXTURE" OUT="$OUT5" bash "$GEN" --check >/dev/null 2>&1; then
  ok "--check exits 0 when committed body matches /meta"
else
  no "--check exits 0 when matches"
fi
# Mutate the body → drift → --check must exit 1.
sed -i 's#203.0.113.11/32#203.0.113.99/32#' "$OUT5"
if META_JSON_FILE="$FIXTURE" OUT="$OUT5" bash "$GEN" --check >/dev/null 2>&1; then
  no "--check exits 1 on body drift"
else
  ok "--check exits 1 on body drift"
fi

echo "-- .packages shape guard (rows 1.2): refuse to write a file that silently stops carving --"
shape_row() { # $1 desc, $2 jq program applied to the fixture, $3 regex the die message must match
  local desc="$1" bad="$WORK/shape-$RANDOM.json" guard="$WORK/shape-guard-$RANDOM.txt"
  jq "$2" "$FIXTURE" > "$bad"
  printf 'SENTINEL\n' > "$guard"
  if gen_run "$bad" "$guard"; then
    no "$desc (should exit non-zero)"
  elif ! grep -qE "ERROR:.*$3" "$WORK/err.txt"; then
    no "$desc (rejected, but not by the intended guard; wanted ERROR:.*$3, got: $(head -c 200 "$WORK/err.txt"))"
  elif [[ "$(cat "$guard")" == "SENTINEL" ]] && [[ -z "$(ls "$guard".* 2>/dev/null)" ]]; then
    ok "$desc (rejected; output untouched; no stray tmp)"
  else
    no "$desc (output mutated or stray tmp left)"
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
  # Without .web the 198.51.100.90/32 entry is no longer an exact member of ANY list, so it is
  # an ordinary effective hole: the oracle (which also reads .web only when present) agrees.
  oracle_check "meta without .web generates (exit 0); the former .web-only member is now carved" "$WORK/noweb.json" "$WORK/noweb.out" 500
else
  no "meta without .web must still generate (shape guard only requires git/api)"
fi

echo "-- one effective hole + one outside-prefix hole: must PASS, carved for the effective one only --"
with_packages onehole '["192.0.2.33/32","233.252.0.9/32","2001:db8:pkg::/48"]'
if gen_run "$WORK/onehole.json" "$WORK/onehole.out"; then
  ok "one effective + one outside-prefix hole exits 0"
else
  no "one effective + one outside-prefix hole must exit 0 (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
if [[ "$(body_of "$WORK/onehole.out")" == "$ONEHOLE_BODY" ]]; then
  ok "one effective hole: body carved for the effective hole only"
else
  no "one effective hole: body wrong — got:[$(body_of "$WORK/onehole.out" | tr '\n' ' ')]"
fi
if [[ "$(grep -c '^# Excluded' "$WORK/onehole.out")" -eq 1 ]] \
   && grep -qxF '# Excluded (GitHub Packages frontends): 192.0.2.33/32' "$WORK/onehole.out"; then
  ok "one effective hole: exactly one Excluded header (the outside-prefix hole is not listed)"
else
  no "one effective hole: header count/content wrong ($(grep '^# Excluded' "$WORK/onehole.out" | tr '\n' '|'))"
fi
oracle_check "one-effective-hole fixture" "$WORK/onehole.json" "$WORK/onehole.out" 500

echo "-- ZERO effective holes DIES (ghcr-carve-no-effective-holes): never land an uncarved file --"
# A file with no effective hole is an uncarved allow list. The post-apply assertion would fail
# every apply on it and an unreviewed daily direct-merge cron PR could silently drop the whole
# carve, so the generator refuses: the refresh freezes and the stale carved file keeps serving.
noeff_row() { # $1 desc, $2 jq program applied to the fixture
  local desc="$1" bad="$WORK/noeff-$RANDOM.json" guard="$WORK/noeff-guard-$RANDOM.txt"
  jq "$2" "$FIXTURE" > "$bad"
  printf 'SENTINEL\n' > "$guard"
  if gen_run "$bad" "$guard"; then
    no "$desc (should exit non-zero)"
  elif ! grep -qF 'ghcr-carve-no-effective-holes' "$WORK/err.txt"; then
    no "$desc (died, but not by ghcr-carve-no-effective-holes: $(head -c 200 "$WORK/err.txt"))"
  elif [[ "$(cat "$guard")" == "SENTINEL" ]] && [[ -z "$(ls "$guard".* 2>/dev/null)" ]]; then
    ok "$desc (died ghcr-carve-no-effective-holes; existing output untouched, no stray tmp)"
  else
    no "$desc (output replaced or stray tmp left)"
  fi
}
noeff_row "all holes outside every allow prefix (plus IPv6)" '.packages = ["233.252.0.9/32","233.252.0.10/32","2001:db8:pkg::/48"]'
noeff_row "only exact .git/.web-only/.api-only members" '.packages = ["198.51.100.77/32","198.51.100.90/32","203.0.113.50/32"]'
noeff_row "only /27-or-shorter holes (skipped with WARN)" '.packages = ["192.0.0.0/8","0.0.0.0/0","192.0.2.0/27","192.0.2.0/24"]'
if grep -qE 'WARN.*(/28|shorter|too broad|skip)' "$WORK/err.txt"; then
  ok "only /27-or-shorter holes: skipped entries were WARNed before the die"
else
  no "only /27-or-shorter holes: no skip WARN (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
noeff_row "only leading-zero (ambiguous) holes (skipped with WARN)" '.packages = ["192.0.2.033/32","192.0.2.08/32","192.0.2.09/32","192.0.02.5/32"]'
if grep -qiE 'value too great|invalid arithmetic|octal' "$WORK/err.txt"; then
  no "leading-zero octet leaked an octal arithmetic error: $(head -c 200 "$WORK/err.txt")"
elif grep -qiE 'WARN.*(leading|non-canonical)' "$WORK/err.txt"; then
  ok "only leading-zero holes: skipped with WARN, no octal abort"
else
  no "only leading-zero holes: expected the skip WARN (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
noeff_row "the old fail-open fixture (outside-prefix + exact .git member + IPv6)" '.packages = ["233.252.0.9/32","198.51.100.77/32","2001:db8:pkg::/48"]'
# No existing file: the die must not CREATE one either (no output at all, no stray tmp).
jq '.packages = ["233.252.0.9/32"]' "$FIXTURE" > "$WORK/noeff-fresh.json"
NF_OUT="$WORK/noeff-fresh-out.txt"; rm -f "$NF_OUT"
if gen_run "$WORK/noeff-fresh.json" "$NF_OUT"; then
  no "zero effective holes with no prior output must exit non-zero"
elif [[ ! -e "$NF_OUT" ]] && [[ -z "$(ls "$NF_OUT".* 2>/dev/null)" ]]; then
  ok "zero effective holes: no output file created, no stray tmp"
else
  no "zero effective holes created an output file or stray tmp"
fi

echo "-- DNS sanity: github.com / api.github.com must never resolve into a hole --"
dns_die_row() { # $1 desc, $2.. env assignments
  local desc="$1" guard="$WORK/dns-guard-$RANDOM.txt"; shift
  printf 'SENTINEL\n' > "$guard"
  if gen_run "$FIXTURE" "$guard" "$@"; then
    no "$desc (should exit non-zero)"
  elif ! grep -qF 'ghcr-carve-would-cut-github' "$WORK/err.txt"; then
    no "$desc (died without the distinct message ghcr-carve-would-cut-github: $(head -c 200 "$WORK/err.txt"))"
  elif [[ "$(cat "$guard")" == "SENTINEL" ]] && [[ -z "$(ls "$guard".* 2>/dev/null)" ]]; then
    ok "$desc (died ghcr-carve-would-cut-github; output untouched)"
  else
    no "$desc (output mutated or stray tmp left)"
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
    ok "$desc (file written, golden body)"
  else
    no "$desc (should write the golden body; stderr: $(head -c 200 "$WORK/err.txt"))"
  fi
}
dns_ok_row "answers outside every hole (neighbours .32/.35/.163/.166)" SHIM_GITHUB_COM="192.0.2.32 192.0.2.35" SHIM_API_GITHUB_COM="198.51.100.163 198.51.100.166"
if grep -qF 'github.com' "$WORK/shim.log" && grep -qF 'api.github.com' "$WORK/shim.log"; then
  ok "DNS guard consulted getent for both github.com and api.github.com"
else
  no "DNS guard did not consult getent for both names (log: $(head -c 120 "$WORK/shim.log"))"
fi
dns_ok_row "lookup failure only warns" SHIM_GITHUB_COM=FAIL SHIM_API_GITHUB_COM=FAIL
if grep -qE 'WARN.*(lookup|getent)' "$WORK/err.txt"; then ok "failed lookup logged as WARN"; else no "failed lookup produced no WARN"; fi
dns_ok_row "answer is IPv6/garbage (ignored, not a hole hit)" SHIM_GITHUB_COM="2001:db8::1 not-an-ip"

# getent absent from PATH: a minimal tool dir with everything the generator
# needs except getent (the cron's minimal image may lack it).
NOGETENT="$WORK/nogetent"; mkdir -p "$NOGETENT"
for t in jq sort comm sed cat mktemp mv rm date dirname awk grep tr head timeout; do
  tp="$(command -v "$t" 2>/dev/null)" && ln -sf "$tp" "$NOGETENT/$t"
done
if env PATH="$NOGETENT" META_JSON_FILE="$FIXTURE" OUT="$WORK/nogetent.out" "$(command -v bash)" "$GEN" >/dev/null 2>"$WORK/err.txt" \
   && [[ "$(body_of "$WORK/nogetent.out")" == "$EXPECTED_BODY" ]] && grep -qE 'WARN.*getent' "$WORK/err.txt"; then
  ok "getent absent: WARN, file still written (guard degrades)"
else
  no "getent absent must WARN and still write (stderr: $(head -c 200 "$WORK/err.txt"))"
fi

echo "-- hostile .packages (rows 1.2.4): the daily direct-merge run treats /meta as untrusted --"
# Hostile broad holes ride along with ONE real hole: the broad ones (/8, /0, /27, /24) are
# skipped with a WARN and only the /32 is carved. (Alone they are the zero-effective die above.)
with_packages broad '["192.0.0.0/8","0.0.0.0/0","192.0.2.0/27","192.0.2.0/24","192.0.2.33/32"]'
if gen_run "$WORK/broad.json" "$WORK/broad.out"; then
  [[ "$(body_of "$WORK/broad.out")" == "$ONEHOLE_BODY" ]] && [[ "$(grep -c '^# Excluded' "$WORK/broad.out")" -eq 1 ]] \
    && grep -qE 'WARN.*(/28|shorter|too broad|skip)' "$WORK/err.txt" \
    && ok "holes shorter than /28 (/8, /0, /27, /24) skipped with WARN; only the /32 carved" \
    || no "hostile broad holes: body/headers/WARN wrong (stderr: $(head -c 200 "$WORK/err.txt"))"
else
  no "hostile broad holes must be skipped, not abort (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
oracle_check "broad-hole fixture" "$WORK/broad.json" "$WORK/broad.out" 500

with_packages boundary28 '["192.0.2.16/28"]'
if gen_run "$WORK/boundary28.json" "$WORK/boundary28.out"; then
  oracle_check "a /28 hole is the shortest applied (boundary)" "$WORK/boundary28.json" "$WORK/boundary28.out" 500
  grep -qxF '# Excluded (GitHub Packages frontends): 192.0.2.16/28' "$WORK/boundary28.out" \
    && ok "/28 hole listed in the header" || no "/28 hole missing from the header"
else
  no "a /28 hole must generate"
fi

with_packages unaligned '["192.0.2.33/31"]'
if gen_run "$WORK/unaligned.json" "$WORK/unaligned.out"; then
  grep -qxF '# Excluded (GitHub Packages frontends): 192.0.2.32/31' "$WORK/unaligned.out" \
    && ok "hole with host bits set is canonicalised (192.0.2.33/31 -> 192.0.2.32/31)" \
    || no "unaligned hole not canonicalised in the header"
  oracle_check "unaligned-hole fixture" "$WORK/unaligned.json" "$WORK/unaligned.out" 500
else
  no "an unaligned hole must generate"
fi

with_packages nested '["192.0.2.32/28","192.0.2.33/32","192.0.2.32/30","192.0.2.32/28"]'
if gen_run "$WORK/nested.json" "$WORK/nested.out"; then
  oracle_check "nested + duplicate holes" "$WORK/nested.json" "$WORK/nested.out" 500
else
  no "nested holes must generate (stderr: $(head -c 200 "$WORK/err.txt"))"
fi

with_packages leadzero '["192.0.2.033/32","192.0.2.08/32","192.0.2.09/32","192.0.02.5/32","192.0.2.33/32"]'
if gen_run "$WORK/leadzero.json" "$WORK/leadzero.out"; then
  if grep -qiE 'value too great|invalid arithmetic|octal' "$WORK/err.txt"; then
    no "leading-zero octet leaked an octal arithmetic error: $(head -c 200 "$WORK/err.txt")"
  elif [[ "$(body_of "$WORK/leadzero.out")" == "$ONEHOLE_BODY" ]] && grep -qiE 'WARN.*(leading|non-canonical)' "$WORK/err.txt"; then
    ok "leading-zero octets skipped with WARN (no octal abort); only the canonical /32 carved"
  else
    no "leading-zero holes: expected one-hole body + WARN (stderr: $(head -c 200 "$WORK/err.txt"))"
  fi
else
  no "leading-zero holes must be skipped, not abort (stderr: $(head -c 200 "$WORK/err.txt"))"
fi

# A leading-zero octet inside an ALLOW prefix (the validator accepts 010 silently,
# as octal 8) must be read as decimal 10 (10# arithmetic) so the carve agrees with
# the exact-match hole 198.51.100.10/32 and removes it; octal reading would keep it.
jq -n '{git:["198.51.100.010/32","192.0.2.0/24"],api:["203.0.113.10/32"],packages:["198.51.100.10/32"]}' > "$WORK/leadallow.json"
if gen_run "$WORK/leadallow.json" "$WORK/leadallow.out"; then
  if grep -qiE 'value too great|invalid arithmetic|octal' "$WORK/err.txt"; then
    no "leading-zero allow octet leaked an octal arithmetic error"
  elif [[ "$(body_of "$WORK/leadallow.out")" == "$(printf '192.0.2.0/24\n203.0.113.10/32')" ]] \
       && grep -qxF '# Excluded (GitHub Packages frontends): 198.51.100.10/32' "$WORK/leadallow.out"; then
    ok "leading-zero allow octet (010) read as decimal 10: carved by the matching hole"
  else
    no "leading-zero allow octet misparsed (body: $(body_of "$WORK/leadallow.out" | tr '\n' ' '))"
  fi
else
  no "leading-zero allow octet 010 must generate (stderr: $(head -c 200 "$WORK/err.txt"))"
fi

# Holes cap: 64 effective holes pass, 65 die.
hole_json() { python3 -c 'import json,sys; print(json.dumps(["192.0.2.%d/32" % (i + 100) for i in range(int(sys.argv[1]))]))' "$1"; }
with_packages holes64 "$(hole_json 64)"
if gen_run "$WORK/holes64.json" "$WORK/holes64.out"; then
  grep -c '^# Excluded' "$WORK/holes64.out" | grep -cx 64 >/dev/null && ok "64 effective holes accepted (cap boundary)" || no "64 holes: header count != 64"
  oracle_check "64-hole fixture" "$WORK/holes64.json" "$WORK/holes64.out" 500
else
  no "64 effective holes must be accepted (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
with_packages holes65 "$(hole_json 65)"
HG="$WORK/holes65-guard.txt"; printf 'SENTINEL\n' > "$HG"
if gen_run "$WORK/holes65.json" "$HG"; then
  no "65 effective holes must die (cap 64)"
elif ! grep -qE 'ERROR:.*65 effective Packages holes' "$WORK/err.txt"; then
  no "65 holes died, but not by the effective-holes cap (stderr: $(head -c 200 "$WORK/err.txt"))"
elif [[ "$(cat "$HG")" == "SENTINEL" ]]; then
  ok "65 effective holes die (cap 64); output untouched"
else
  no "65 holes: output mutated"
fi

# Raw .packages entry cap (C2): the O(P x A) overlap loop must never see a hostile /meta's
# thousands of entries. 512 raw IPv4 entries (1 effective + 511 outside every allow prefix) are
# accepted; 513 die at the RAW count, before the loop, with their own message (an effective hole
# is present in both rows so a removed cap would NOT die at all and the 513 row goes red).
pkg_json() { python3 -c '
import json, sys
n = int(sys.argv[1])
print(json.dumps(["192.0.2.33/32"] + ["233.252.%d.%d/32" % (i >> 8 & 255, i & 255) for i in range(n - 1)]))' "$1"; }
with_packages pkgs512 "$(pkg_json 512)"
if gen_run "$WORK/pkgs512.json" "$WORK/pkgs512.out" && [[ "$(grep -c '^# Excluded' "$WORK/pkgs512.out")" -eq 1 ]]; then
  ok "512 raw .packages IPv4 entries accepted (cap boundary)"
else
  no "512 raw .packages entries must be accepted (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
with_packages pkgs513 "$(pkg_json 513)"
PG="$WORK/pkgs513-guard.txt"; printf 'SENTINEL\n' > "$PG"
if gen_run "$WORK/pkgs513.json" "$PG"; then
  no "513 raw .packages entries must die (cap 512)"
elif ! grep -qE 'ERROR:.*\.packages has 513 IPv4 entries \(> 512' "$WORK/err.txt"; then
  no "513 raw .packages entries died, but not by the raw-count cap (stderr: $(head -c 200 "$WORK/err.txt"))"
elif [[ "$(cat "$PG")" == "SENTINEL" ]]; then
  ok "513 raw .packages entries die (cap 512) before the overlap loop; output untouched"
else
  no "513 raw .packages entries: output mutated"
fi

# Output cap. The fixture carries ONE real hole (a /28 inside an api /24, which carves the
# /24 into 4 prefixes), so a zero-effective die can never masquerade as a cap die: output
# lines = n + 4. 2048 pass; 2049 die in the carve cap; an extraction above 2048 dies earlier.
big_json() { python3 -c '
import json, sys
n = int(sys.argv[1])
ips = ["10.%d.%d.%d/32" % (i >> 16 & 255, i >> 8 & 255, i & 255) for i in range(n)]
print(json.dumps({"git": ips, "api": ["203.0.113.0/24"], "packages": ["203.0.113.64/28"]}))' "$1"; }
big_json 2044 > "$WORK/big2048.json"   # 2044 + 4 carved prefixes = 2048 lines
if gen_run "$WORK/big2048.json" "$WORK/big2048.out" && [[ "$(body_of "$WORK/big2048.out" | wc -l)" -eq 2048 ]]; then
  ok "2048 output lines accepted (cap boundary)"
else
  no "2048 output lines must be accepted (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
big_json 2045 > "$WORK/big2049.json"   # 2045 + 4 carved prefixes = 2049 lines
BG="$WORK/big-guard.txt"; printf 'SENTINEL\n' > "$BG"
if gen_run "$WORK/big2049.json" "$BG"; then
  no "2049 output lines must die (cap 2048)"
elif ! grep -qE 'ERROR:.*carve produced 2049 ranges' "$WORK/err.txt"; then
  no "2049 output lines died, but not by the carve output cap (stderr: $(head -c 200 "$WORK/err.txt"))"
elif [[ "$(cat "$BG")" == "SENTINEL" ]]; then
  ok "2049 output lines die (cap 2048); output untouched"
else
  no "2049 lines: output mutated"
fi
big_json 2048 > "$WORK/bigext.json"    # 2048 + 1 api prefix = 2049 extracted
EG="$WORK/bigext-guard.txt"; printf 'SENTINEL\n' > "$EG"
if gen_run "$WORK/bigext.json" "$EG"; then
  no "2049 extracted ranges must die (cap 2048)"
elif ! grep -qE 'ERROR:.*extraction has 2049 ranges' "$WORK/err.txt"; then
  no "2049 extracted ranges died, but not by the extraction cap (stderr: $(head -c 200 "$WORK/err.txt"))"
elif [[ "$(cat "$EG")" == "SENTINEL" ]]; then
  ok "2049 extracted ranges die (extraction cap 2048); output untouched"
else
  no "2049 extracted ranges: output mutated"
fi

echo "-- carve left no ranges (C3): the guard must be reachable and name itself --"
# git/api are two /32s and the single hole (a /28 that is NOT an exact member) swallows both.
# The old guard tested printf output (an empty array still prints one empty line), so it never
# fired and the failure surfaced as the misleading "invalid CIDR from /meta: ''".
jq -n '{git:["192.0.2.32/32"],api:["192.0.2.33/32"],packages:["192.0.2.32/28"]}' > "$WORK/nothing-left.json"
NL="$WORK/nothing-left-guard.txt"; printf 'SENTINEL\n' > "$NL"
if gen_run "$WORK/nothing-left.json" "$NL"; then
  no "a carve that removes every range must die"
elif ! grep -qE 'ERROR:.*carve left no ranges' "$WORK/err.txt"; then
  no "carve-left-nothing died with the wrong message (stderr: $(head -c 200 "$WORK/err.txt"))"
elif grep -qF "invalid CIDR from /meta: ''" "$WORK/err.txt"; then
  no "carve-left-nothing surfaced the misleading empty-CIDR message"
elif [[ "$(cat "$NL")" == "SENTINEL" ]]; then
  ok "carve left no ranges: dies with its own message; output untouched"
else
  no "carve-left-nothing: output mutated"
fi

echo "-- allow-prefix floor boundary (/8 accepted, /7 rejected) --"
jq -n '{git:["10.0.0.0/8"],api:["203.0.113.10/32"],packages:["10.1.2.0/28"]}' > "$WORK/slash8.json"
if gen_run "$WORK/slash8.json" "$WORK/slash8.out" && grep -qxF '# Excluded (GitHub Packages frontends): 10.1.2.0/28' "$WORK/slash8.out"; then
  oracle_check "a /8 allow prefix is the broadest accepted (carved around a /28 hole)" "$WORK/slash8.json" "$WORK/slash8.out" 30
else
  no "a /8 allow prefix must be accepted and carved (stderr: $(head -c 200 "$WORK/err.txt"))"
fi
shape_row "a /7 allow prefix is rejected (prefix < /8 floor)" '.git += ["10.0.0.0/7"]' 'over-broad CIDR'

echo "-- exact-member protection is a union over .git/.web/.api (explicit, not silent) --"
# `.web` is NOT in the allow set, so subtracting .web exact members from the holes is a PROXY:
# a .packages entry /meta also lists under .web stays admitted when a .git prefix covers it.
# That is the plan's deliberate Design item 1 (protect an entry listed as the same range in ANY
# of the three lists); the runtime probe is the control for the residual, not this generator.
jq -n '{git:["192.0.2.0/24"],web:["192.0.2.33/32"],api:["203.0.113.10/32"],packages:["192.0.2.33/32","192.0.2.34/32"]}' > "$WORK/webonly.json"
if gen_run "$WORK/webonly.json" "$WORK/webonly.out" \
   && [[ "$(grep '^# Excluded' "$WORK/webonly.out")" == '# Excluded (GitHub Packages frontends): 192.0.2.34/32' ]] \
   && member "$WORK/webonly.out" 192.0.2.33 && ! member "$WORK/webonly.out" 192.0.2.34; then
  ok ".web-only /32 equal to a .packages entry is NOT carved (admitted by .git; proxy documented); the sibling is carved"
else
  no ".web-only exact member handling changed (header: $(grep '^# Excluded' "$WORK/webonly.out" | tr '\n' '|'); stderr: $(head -c 200 "$WORK/err.txt"))"
fi
oracle_check "web-only-member fixture" "$WORK/webonly.json" "$WORK/webonly.out" 100
# .api-ONLY member (no .git prefix covers it): carving it would delete its only admitting entry.
jq -n '{git:["198.51.100.0/24"],api:["203.0.113.50/32"],packages:["203.0.113.50/32","198.51.100.34/32"]}' > "$WORK/apionly.json"
if gen_run "$WORK/apionly.json" "$WORK/apionly.out" \
   && [[ "$(grep '^# Excluded' "$WORK/apionly.out")" == '# Excluded (GitHub Packages frontends): 198.51.100.34/32' ]] \
   && member "$WORK/apionly.out" 203.0.113.50 && ! member "$WORK/apionly.out" 198.51.100.34; then
  ok ".api-only /32 equal to a .packages entry is NOT carved; the sibling is carved"
else
  no ".api-only exact member handling changed (header: $(grep '^# Excluded' "$WORK/apionly.out" | tr '\n' '|'); stderr: $(head -c 200 "$WORK/err.txt"))"
fi
oracle_check "api-only-member fixture" "$WORK/apionly.json" "$WORK/apionly.out" 100

echo "-- --check covers the Excluded header (consumers read it) --"
OUT6="$WORK/cidr-check-hdr.txt"
META_JSON_FILE="$FIXTURE" OUT="$OUT6" bash "$GEN" >/dev/null 2>&1
sed -i '0,/^# Excluded/{//d}' "$OUT6"
if META_JSON_FILE="$FIXTURE" OUT="$OUT6" bash "$GEN" --check >/dev/null 2>&1; then
  no "--check must exit 1 when an Excluded header line is dropped"
else
  ok "--check exits 1 when an Excluded header line is dropped"
fi

echo "-- validator parity with the loader (#5268) --"
# The generator's validator is EQUIVALENT to the loader's is_valid_ipv4_cidr (not a shared
# copy): these two rows are what keep the regex literal and the range arithmetic identical.
CIDR_RE='([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})'
CIDR_RANGE='o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32'
if grep -qF -- "$CIDR_RE" "$GEN" && grep -qF -- "$CIDR_RE" "$LOADER"; then
  ok "CIDR regex literal pinned identically in generator and loader"
else
  no "CIDR regex literal drift between generator and loader"
fi
if grep -qF -- "$CIDR_RANGE" "$GEN" && grep -qF -- "$CIDR_RANGE" "$LOADER"; then
  ok "CIDR range-check arithmetic pinned identically in generator and loader"
else
  no "CIDR range-check drift between generator and loader"
fi

echo "-- atomic-write invariants (source-shape) --"
grep -qF "trap 'rm -f" "$GEN" && ok "EXIT trap removes the temp file on failure" || no "EXIT trap present"
grep -qE 'mktemp .*\$\{?OUT' "$GEN" && ok "mktemp in the target dir (atomic mv, same fs)" || no "mktemp in the target dir"
# Anchored on the LIVE curl invocation, comment-stripped: the emit_file heredoc and the header
# comment both quote a `curl -fsS --max-time 30` recipe, which a bare grep would accept even
# with the real fetch unbounded.
if grep -vE '^[[:space:]]*#' "$GEN" | grep -cE '^[[:space:]]*meta_json="\$\(curl -fsS --max-time 30 "\$META_URL"\)"' >/dev/null; then
  ok "live fetch is bounded (the meta_json= curl invocation carries --max-time 30, AC11)"
else
  no "live fetch bounded (no comment-stripped meta_json=\"\$(curl -fsS --max-time 30 \"\$META_URL\")\" line)"
fi

echo ""
echo "RESULT: $PASS passed, $FAIL failed ($CASES cases)"
# Conservation: CASES moves at every ok()/no() call site, independent of what pass()/fail()
# do, so a verdict that was discarded (a neutered pass()/fail()) shows up here. Reported with
# printf + exit, never through the pass()/fail() accounting it backstops.
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: pass+fail (%d) != cases (%d): a verdict was discarded\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi
# Anti-vacuity floor (ADR-193): CI reads only the exit status, so a deleted row would vanish
# green. Ratchet when adding rows.
if [[ $((PASS + FAIL)) -lt 95 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d verdict(s) recorded, expected >= 95. A row was deleted.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
