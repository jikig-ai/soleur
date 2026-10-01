#!/usr/bin/env bash
# cron-egress-nftables.test.sh — the REAL cron-egress-nftables.sh run against a stateful stub `nft` (#9378).
#
# WHY. A fresh web host's Doppler read token travels in cloud-init user_data, which the host can read back
# from the link-local metadata endpoint 169.254.169.254. ADR-263 accepts that residual ONLY because containers
# sit behind the default-drop egress firewall and nothing it installs can admit a link-local address.
# cron-egress-metadata-endpoint.test.sh bounds that at the level of the two allowlist FILES (text only); this
# suite exercises the LOADER (the rendered ruleset and the CIDR gate) and the RESOLVER (no address in
# 169.254.0.0/16 reaches either nft set, from any feeder), both for real against stub binaries.
#
# SHAPE. The loader runs for real. `nft` is a stub on a scratch PATH that logs every call and keeps STATE across
# calls (a stateful `list chain` and `list set`, so "exactly one DOCKER-USER jump insert" means something across
# two loader runs); `ip`, `docker`, `getent` and `curl` are stubs. For the loader tests the resolver is a stub
# script and CIDR_FILE a scratch file; for the resolver tests `getent` serves per-host answers and the container's
# view comes from the `docker exec` stub. The scratch PATH carries no real nft, ip, docker, getent or curl.
# Assertions are over what was RENDERED (each `nft -f -` transaction body, the chain and set state it produced),
# never over a value compared with the thing it protects.
# Mutation rows mutate COPIES of the loader and re-run this file against them (CEN_SCRIPT): rc 1 = caught,
# rc 0 = SURVIVED, rc 2 = a broken instrument (never counted as a catch).
# shellcheck disable=SC2034  # the happy-path rule indexes are read by the eval'd all() strings
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
PRISTINE="$DIR/cron-egress-nftables.sh"
SUT="${CEN_SCRIPT:-$PRISTINE}"
# Instrument seams (suite-only; the mutation rows drive them):
#   CEN_MUTANT=1       inner run of a mutation row: skips the mutation rows themselves.
#   CEN_STUB_NOLOG=1   the stub nft records nothing (the "0 calls checked" harness row).
#   CEN_MUT_JOBS=<n>   how many mutation rows run at once (default 3; the infra runner is already -P4).
CEN_MUTANT="${CEN_MUTANT:-}"

pass=0; fail=0; FAILED=()
ok() { if [ "$1" -eq 0 ]; then pass=$((pass + 1)); printf '[ok] %s\n' "$2"; else fail=$((fail + 1)); FAILED+=("$2"); printf '[FAIL] %s\n' "$2"; fi; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }
expect() { local n="$1"; shift; if "$@"; then ok 0 "$n"; else ok 1 "$n"; fi; }
all() { local _c; for _c in "$@"; do eval "$_c" || return 1; done; } # one scored command; the first false string is the verdict

# INSTRUMENT SELF-TEST: the helpers must move their own counters before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok 0 "self-test"; no "self-test"; expect "self-test" all 'test 1 -eq 2' 'true'; expect "self-test" all 'true' 'true'; } >/dev/null
if [ "$pass" -ne $((_p0 + 2)) ] || [ "$fail" -ne $((_f0 + 2)) ] || [ "${#FAILED[@]}" -ne 2 ]; then
  printf '[FATAL] instrument self-test: ok()/no()/all() did not move their counters\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

[ -r "$SUT" ] || { printf '[FATAL] unreadable: %s\n' "$SUT" >&2; exit 2; }
for t in python3 grep cat awk; do command -v "$t" >/dev/null 2>&1 || { printf '[FATAL] %s is required\n' "$t" >&2; exit 2; }; done
SCRATCH="$(mktemp -d)"
case "$SCRATCH" in ""|/|/proc/*|/sys/*|/dev/*|*..*|[!/]*) printf '[FATAL] bad scratch dir: %s\n' "$SCRATCH" >&2; exit 2 ;; esac
trap 'rm -rf "$SCRATCH"' EXIT

# ── stubs ─────────────────────────────────────────────────────────────────────────────────────
STUBS="$SCRATCH/stubs"; mkdir -p "$STUBS"
# nft: logs argv; for `-f -` also logs the body and writes it to $FX/txn.<n>; keeps the SOLEUR-EGRESS and
# DOCKER-USER chains and the set elements in $FX/st so a second run (and `list chain`) sees the first one's state.
cat > "$STUBS/nft" <<'EOF'
#!/bin/bash
st="$FX/st"
[ -n "${CEN_STUB_NOLOG:-}" ] || printf 'nft %s\n' "$*" >> "$FX/log"
case "$1" in
  -f)
    body=$(cat)
    n=$(( $(cat "$st/txn.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$st/txn.n"
    if [ -z "${CEN_STUB_NOLOG:-}" ]; then printf '%s\n' "$body" > "$FX/txn.$n"; printf '<<< txn %s\n%s\n>>>\n' "$n" "$body" >> "$FX/log"; fi
    while IFS= read -r l; do
      case "$l" in
        "flush chain ip filter SOLEUR-EGRESS") : > "$st/chain.SOLEUR-EGRESS" ;;
        "add rule ip filter SOLEUR-EGRESS "*) printf '%s\n' "${l#add rule ip filter SOLEUR-EGRESS }" >> "$st/chain.SOLEUR-EGRESS" ;;
        "add element ip filter "*)
          printf '%s\n' "$l" >> "$st/elements"
          nm="${l#add element ip filter }"; nm="${nm%% *}"; pl="${l#*\{ }"; pl="${pl%% \}*}"
          IFS=, read -ra ea <<< "$pl"; printf '%s\n' "${ea[@]}" >> "$st/set.$nm" ;;
        "delete element ip filter "*)
          nm="${l#delete element ip filter }"; nm="${nm%% *}"; pl="${l#*\{ }"; pl="${pl%% \}*}"
          IFS=, read -ra ea <<< "$pl"
          for x in "${ea[@]}"; do grep -vxF -- "$x" "$st/set.$nm" > "$st/set.tmp" 2>/dev/null; cat "$st/set.tmp" > "$st/set.$nm"; done ;;
      esac
    done <<< "$body" ;;
  -j) # nft -j list set ip filter NAME: the stub's elements as the JSON shape the resolver parses
    nm="$6"; el=""
    while IFS= read -r x; do [ -z "$x" ] || el="${el:+$el,}\"$x\""; done < "$st/set.$nm" 2>/dev/null
    printf '{"nftables":[{"set":{"family":"ip","name":"%s","elem":[%s]}}]}\n' "$nm" "$el" ;;
  insert) case "$*" in *"jump SOLEUR-EGRESS"*) printf 'iifname "docker0" counter jump SOLEUR-EGRESS\n' >> "$st/chain.DOCKER-USER" ;; esac ;;
  list) [ -f "$st/chain.$5" ] && cat "$st/chain.$5" ;;
esac
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$STUBS/ip"
cat > "$STUBS/docker" <<'EOF'
#!/bin/bash
case "$1" in
  network)
    case "$*" in
      *EnableIPv6*) printf '%s\n' "${CEN_V6:-false}" ;;
      *Gateway*) printf '172.17.0.1\n' ;;
    esac ;;
  ps) [ -f "$FX/container.up" ] && printf 'soleur-web-platform\n' ;;
  exec) # the resolver's two container reads: the getent loop (hosts on stdin) and resolv.conf
    case "$*" in
      *"cat /etc/resolv.conf"*) cat "$FX/resolv.conf" 2>/dev/null ;;
      *) cat > /dev/null; cat "$FX/cview" 2>/dev/null ;;
    esac ;;
esac
exit 0
EOF
cat > "$STUBS/getent" <<'EOF'
#!/bin/bash
# getent ahostsv4 <host>: one "IP STREAM host" line per answer in $FX/dns/<host>; an unknown host is rc 2 (NXDOMAIN)
[ -f "$FX/dns/$2" ] || exit 2
while IFS= read -r ip; do printf '%s STREAM %s\n' "$ip" "$2"; done < "$FX/dns/$2"
EOF
cat > "$STUBS/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >> "$FX/curl.log"
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$STUBS/journalctl"
cat > "$STUBS/resolve.sh" <<'EOF'
#!/bin/bash
[ -n "${CEN_STUB_NOLOG:-}" ] || printf 'resolver from_loader=%s\n' "${CRON_EGRESS_FROM_LOADER:-}" >> "$FX/log"
exit "${CEN_RESOLVE_RC:-0}"
EOF
chmod 0755 "$STUBS"/*

new_fx() { # builds a fixture; sets FX (a scratch PATH: the stubs plus grep and cat, NO real nft, ip or docker)
  FX="$(mktemp -d "$SCRATCH/fx.XXXXXXXX")"
  mkdir -p "$FX/bin" "$FX/st"; : > "$FX/log"
  cp "$STUBS/nft" "$STUBS/ip" "$STUBS/docker" "$STUBS/getent" "$STUBS/curl" "$STUBS/journalctl" "$FX/bin/"; cp "$STUBS/resolve.sh" "$FX/resolve.sh"
  ln -s "$(command -v grep)" "$FX/bin/grep"; ln -s "$(command -v cat)" "$FX/bin/cat"
  : > "$FX/cidr.txt"
}
run_loader() { # runs the loader in $FX; sets RC
  RC=0
  env -i PATH="$FX/bin" FX="$FX" CEN_STUB_NOLOG="${CEN_STUB_NOLOG:-}" CEN_V6="${CEN_V6:-false}" CEN_RESOLVE_RC="${CEN_RESOLVE_RC:-0}" \
    CIDR_FILE="$FX/cidr.txt" RESOLVE_SCRIPT="$FX/resolve.sh" "$BASH" "${1:-$SUT}" > "$FX/out" 2>&1 < /dev/null || RC=$?
}

# ── handles on what the loader rendered ───────────────────────────────────────────────────────
LL_RE='^add rule ip filter SOLEUR-EGRESS ip daddr 169\.254\.0\.0/16 counter drop( comment "[^"]*")?$'
rules_txn() { grep -l '^flush chain ip filter SOLEUR-EGRESS' "$1"/txn.* 2>/dev/null | head -1; } # the Phase 3 transaction of fixture dir $1
chain() { cat "$FX/st/chain.SOLEUR-EGRESS" 2>/dev/null; } # the SOLEUR-EGRESS chain as the stub holds it
ridx() { chain | grep -nE -- "$1" | head -1 | cut -d: -f1; } # 1-based index of the first rule matching an ERE
calls() { grep -c -E -- "$1" "$FX/log" || true; }
# CENSUS: every rendered line naming 169.254 (all transactions of fixture dir $1): exactly one, it is the literal
# link-local drop, and in the rules transaction it precedes every accept. 0 = clean.
ll_clean() {
  local d="$1" r
  [ "$(cat "$d"/txn.* 2>/dev/null | grep -c '169\.254')" = 1 ] || return 1
  cat "$d"/txn.* | grep '169\.254' | grep -qE -- "$LL_RE" || return 1
  r=$(rules_txn "$d"); [ -n "$r" ] || return 1
  RE="$LL_RE" awk '$0 ~ ENVIRON["RE"] { seen = 1 } /accept/ && !seen { bad = 1 } END { exit bad }' "$r"
}
elems() { cat "$FX/st/elements" 2>/dev/null; }

# ── 1. the happy path: the rendered ruleset ───────────────────────────────────────────────────
new_fx
printf '# 169.254.0.0/16 is named only in this comment: a comment line is not an element\n203.0.113.0/24\n198.51.100.7/32\n' > "$FX/cidr.txt"
run_loader
HAPPY="$FX"
r_ll=$(ridx '^ip daddr 169\.254\.0\.0/16 counter drop'); r_ret=$(ridx 'ct state established,related accept'); r_dns=$(ridx '@soleur_egress_dns accept')
r_log=$(ridx 'egress-blocked: '); r_last=$(chain | grep -c .)
expect "happy: rc 0 and the stub recorded the run (a loader that never ran must not pass vacuously)" all 'test "$RC" -eq 0' 'test -s "$FX/log"' 'test "$(calls "^nft -f -$")" -eq 3'
expect "happy: transaction order: the CIDR elements, then the resolver, then the Phase 3 rules, then the DOCKER-USER probe" all 'test "$(grep -n "add element" "$FX/log" | head -1 | cut -d: -f1)" -lt "$(grep -n "^resolver " "$FX/log" | head -1 | cut -d: -f1)"' 'test "$(grep -n "^resolver " "$FX/log" | head -1 | cut -d: -f1)" -lt "$(grep -n "^flush chain ip filter SOLEUR-EGRESS" "$FX/log" | head -1 | cut -d: -f1)"' 'test "$(grep -n "^flush chain ip filter SOLEUR-EGRESS" "$FX/log" | head -1 | cut -d: -f1)" -lt "$(grep -n "^nft list chain ip filter DOCKER-USER" "$FX/log" | head -1 | cut -d: -f1)"'
expect "happy: the resolver ran under the loader guard (CRON_EGRESS_FROM_LOADER=1), so loader -> resolver -> loader cannot recurse" grep -qx 'resolver from_loader=1' "$FX/log"
expect "happy: the Phase 3 chain starts with the link-local drop, then return traffic, then the pinned DNS accept" all 'test "$r_ll" = 1' 'test "$r_ret" = 2' 'test -n "$r_dns" -a "$r_dns" -gt "$r_ret"'
expect "happy: the default-drop log then the default drop are the LAST two rules" all 'test -n "$r_log"' 'test "$r_log" -eq "$((r_last - 1))"' 'chain | tail -n 1 | grep -q "^counter drop comment \"soleur-egress: default drop\"$"'
expect "happy: the CIDR elements reached nft as one flush+add transaction before the rules" all 'test "$(elems | grep -c "^add element ip filter soleur_egress_allow_cidr { 203.0.113.0/24,198.51.100.7/32 }$")" -eq 1' 'grep -q "^flush set ip filter soleur_egress_allow_cidr$" "$HAPPY"/txn.2'
expect "happy: census: the only rendered line naming 169.254 is the literal link-local drop, ordered before every accept" ll_clean "$HAPPY"
expect "happy: no add-element payload names a link-local address" test "$(elems | grep -c '169\.254')" -eq 0
# exactly one DOCKER-USER jump insert across TWO loader runs (the stub's list chain keeps the first run's jump)
run_loader
expect "happy: a second loader run on the same state re-asserts the chain but inserts NO second jump (exactly one in total)" all 'test "$RC" -eq 0' 'test "$(calls "^nft insert rule ip filter DOCKER-USER")" -eq 1' 'test "$(chain | grep -c "^counter drop comment \"soleur-egress: default drop\"$")" -eq 1' 'test "$(grep -c "jump SOLEUR-EGRESS" "$FX/st/chain.DOCKER-USER")" -eq 1'

# ── 2. the CIDR gate: any range that overlaps 169.254.0.0/16 refuses the WHOLE file before nft is touched ──
cidr_refused() { # <cidr>: a compliant first line, then the bad one
  new_fx; printf '203.0.113.0/24\n%s\n' "$1" > "$FX/cidr.txt"; run_loader
  [ "$RC" -eq 1 ] && grep -q 'invalid CIDR in' "$FX/out" && [ ! -s "$FX/log" ] && [ ! -s "$FX/st/elements" ]
}
for c in 169.254.0.0/16 169.254.169.254/32 169.0.0.0/8 0.0.0.0/0 128.0.0.0/1 160.0.0.0/3 169.254.0.0/15 169.254.255.255/32 169.254.0.0/32 010.0.0.0/8 08.1.1.1/8 1.1.1.1/08; do
  expect "gate: $c is refused as a whole file: rc 1, the reason names the CIDR, NO nft call at all (so no flush chain and no add element: the previous ruleset stays)" cidr_refused "$c"
done
cidr_accepted() { # <cidr>
  new_fx; printf '%s\n' "$1" > "$FX/cidr.txt"; run_loader
  [ "$RC" -eq 0 ] && elems | grep -qF -- "{ $1 }" && ll_clean "$FX"
}
for c in 169.253.255.255/32 169.255.0.0/16 203.0.113.0/24 168.0.0.0/8; do
  expect "gate: must-pass: $c does not overlap 169.254.0.0/16 and installs normally (rc 0, element rendered, census clean)" cidr_accepted "$c"
done
new_fx; printf '169.254.0.0/16' > "$FX/cidr.txt"; run_loader
expect "gate: a final line with no trailing newline is still read and refused" all 'test "$RC" -eq 1' 'test ! -s "$FX/log"'
new_fx; printf '203.0.113.0/24\r\n' > "$FX/cidr.txt"; run_loader
expect "gate: a CRLF-saved file is refused (the old paste-build injected the CR into the heredoc)" all 'test "$RC" -eq 1' 'test ! -s "$FX/log"'

# ── 3. failure arms keep the previous ruleset ─────────────────────────────────────────────────
new_fx; CEN_RESOLVE_RC=1 run_loader
expect "arms: a failed resolution aborts before the drop rules (rc 1, no flush chain, no jump): fail-open bootstrap" all 'test "$RC" -eq 1' 'test "$(calls "flush chain")" -eq 0' 'test "$(calls "nft insert")" -eq 0'
new_fx; CEN_V6=true run_loader
expect "arms: a bridge with IPv6 enabled is refused loudly (the v4 table would be bypassed over v6): rc 1, no nft call" all 'test "$RC" -eq 1' 'test ! -s "$FX/log"'

# ── 4. the RESOLVER: no address in 169.254.0.0/16 reaches either set, from any feeder ──────────
RPRISTINE="$DIR/cron-egress-resolve.sh"
RSUT="${CEN_RESOLVER:-$RPRISTINE}"
[ -r "$RSUT" ] || { printf '[FATAL] unreadable: %s\n' "$RSUT" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf '[FATAL] jq is required (the resolver parses `nft -j` with it)\n' >&2; exit 2; }
new_rfx() { # a resolver fixture: the loader fixture plus the coreutils the resolver calls (still NO real nft/docker/getent/curl)
  local t; new_fx
  for t in jq awk sort comm paste tr cut basename find date rm mkdir timeout head tail wc sed uniq; do ln -s "$(command -v "$t")" "$FX/bin/$t" 2>/dev/null || true; done
  mkdir -p "$FX/dns" "$FX/seen" "$FX/fc"
  printf 'a.example.test\nb.example.test\n' > "$FX/allow.txt"
  printf '203.0.113.1\n' > "$FX/dns/sentry.invalid"; printf '203.0.113.2\n' > "$FX/dns/db.example.test"
  printf '203.0.113.7\n' > "$FX/dns/a.example.test"; printf '203.0.113.9\n' > "$FX/dns/b.example.test"
  printf '198.51.100.250\n' > "$FX/st/set.soleur_egress_allow" # a stale element: a prune tick deletes it, an additive-only tick must not
}
run_resolver() { # [script]: one resolver tick in $FX; sets RC
  RC=0
  env -i PATH="$FX/bin" FX="$FX" CRON_EGRESS_LOCKED=1 CRON_EGRESS_FROM_LOADER=1 ALLOWLIST_FILE="$FX/allow.txt" SEEN_DIR="$FX/seen" \
    FAILCOUNT_DIR="$FX/fc" LOADER=/nonexistent GRACE_WINDOW_SECS=86400 SENTRY_INGEST_DOMAIN=sentry.invalid SENTRY_PROJECT_ID=1 SENTRY_PUBLIC_KEY=k \
    NEXT_PUBLIC_SUPABASE_URL=https://db.example.test SUPABASE_URL=https://db.example.test "$BASH" "${1:-$RSUT}" > "$FX/out" 2>&1 < /dev/null || RC=$?
}
adds() { grep -h "^add element ip filter $1 {" "$FX"/txn.* 2>/dev/null | sed -e 's/^[^{]*{ //' -e 's/ }$//' | tr ',' '\n'; } # every address added to set $1
dels() { grep -h "^delete element ip filter $1 {" "$FX"/txn.* 2>/dev/null | sed -e 's/^[^{]*{ //' -e 's/ }$//' | tr ',' '\n'; }
ll_events() { grep -c 'resolve_link_local' "$FX/curl.log" 2>/dev/null || true; } # Sentry events posted for a link-local answer
no_ll_added() { [ -z "$(adds soleur_egress_allow | grep '^169\.254\.')" ] && [ -z "$(adds soleur_egress_dns | grep '^169\.254\.')" ]; } # nothing link-local reached either set
ticked() { [ "$RC" -eq 0 ] && grep -q 'OK: allow=' "$FX/out"; } # the tick completed (so an empty add-list is not a crash)

new_rfx; run_resolver
expect "resolver: must-pass: an ordinary tick installs the answer 203.0.113.7, prunes the stale element, and posts no link-local event" all 'ticked' 'adds soleur_egress_allow | grep -qx 203.0.113.7' 'dels soleur_egress_allow | grep -qx 198.51.100.250' 'no_ll_added' 'test "$(ll_events)" -eq 0'
new_rfx; printf '169.254.169.254\n' > "$FX/dns/a.example.test"; run_resolver
expect "resolver: a host whose ONLY answer is 169.254.169.254: nothing link-local is added, the tick counts it as a failure (additive-only: the stale element is NOT pruned), one Sentry event" all 'ticked' 'no_ll_added' '! dels soleur_egress_allow | grep -q .' 'grep -q "every record was link-local" "$FX/out"' 'grep -q "ADDITIVE-ONLY" "$FX/out"' 'test "$(ll_events)" -eq 1'
cp "$FX/out" "$FX/out.tick1"; run_resolver
expect "resolver: the Sentry event is posted once per source, not once per tick (a second identical tick adds none)" test "$(ll_events)" -eq 1
printf '203.0.113.7\n' > "$FX/dns/a.example.test"; run_resolver
expect "resolver: once the host answers clean the marker clears: the next tick prunes again and the next link-local answer would post again" all 'ticked' 'test ! -e "$FX/fc/.ll-a.example.test"' 'dels soleur_egress_allow | grep -qx 198.51.100.250'
new_rfx; printf '169.254.169.254\n203.0.113.7\n' > "$FX/dns/a.example.test"; run_resolver
expect "resolver: a host with one link-local and one good record keeps the good one, drops the other, and is NOT a failure (the stale element is pruned)" all 'ticked' 'adds soleur_egress_allow | grep -qx 203.0.113.7' 'no_ll_added' 'dels soleur_egress_allow | grep -qx 198.51.100.250' 'test "$(ll_events)" -eq 1'
new_rfx; printf '169.254.0.7\n169.254.255.254\n203.0.113.7\n' > "$FX/dns/a.example.test"; run_resolver
expect "resolver: the whole /16 is refused, not just the metadata address (169.254.0.7 and 169.254.255.254)" all 'ticked' 'no_ll_added' 'adds soleur_egress_allow | grep -qx 203.0.113.7'
new_rfx; printf '::ffff:169.254.169.254\n' > "$FX/dns/a.example.test"; run_resolver
expect "resolver: the v4-mapped spelling ::ffff:169.254.169.254 is link-local too: nothing added, counted as a failure (additive-only), one event" all 'ticked' 'no_ll_added' '! dels soleur_egress_allow | grep -q .' 'test "$(ll_events)" -eq 1'
new_rfx; printf '%s %s\n' 169.254.169.254 x > /dev/null; now=$(date +%s); printf '%s\n' "$now" > "$FX/seen/169.254.169.254"; printf '%s\n' "$now" > "$FX/seen/203.0.113.50"; run_resolver
expect "resolver: a planted seen/169.254.169.254 (inside the 24 h grace window) is PURGED, never re-added; a legitimate seen entry is still retained" all 'ticked' 'test ! -e "$FX/seen/169.254.169.254"' 'no_ll_added' 'adds soleur_egress_allow | grep -qx 203.0.113.50' 'test -e "$FX/seen/203.0.113.50"'
new_rfx; : > "$FX/container.up"; printf '169.254.169.254\n203.0.113.77\n' > "$FX/cview"; run_resolver
expect "resolver: the container's own getent view is a feeder too: its link-local answer is dropped and never recorded, its good answer is added, one event" all 'ticked' 'no_ll_added' 'adds soleur_egress_allow | grep -qx 203.0.113.77' 'test ! -e "$FX/seen/169.254.169.254"' 'test "$(ll_events)" -eq 1'
new_rfx; : > "$FX/container.up"; printf 'nameserver 169.254.169.253\nnameserver 203.0.113.53\n' > "$FX/resolv.conf"; run_resolver
expect "resolver: a link-local nameserver in the container's resolv.conf never reaches the DNS pin set (203.0.113.53 and Docker's 8.8.8.8 do)" all 'ticked' 'no_ll_added' 'adds soleur_egress_dns | grep -qx 203.0.113.53' 'adds soleur_egress_dns | grep -qx 8.8.8.8'

# ── 5. harness rows: the instrument must be able to fail ──────────────────────────────────────
SEED="$SCRATCH/seeded"; mkdir -p "$SEED"
cp "$HAPPY"/txn.* "$SEED/"; printf 'add rule ip filter SOLEUR-EGRESS ip daddr 169.254.169.254 accept\n' >> "$SEED/txn.9"
expect "harness: the 169.254 census run against a transcript SEEDED with a link-local accept reports it dirty" test "$(ll_clean "$SEED" && echo clean || echo dirty)" = dirty
SEED2="$SCRATCH/seeded2"; mkdir -p "$SEED2"; r=$(rules_txn "$HAPPY")
{ grep -v -E -- "$LL_RE" "$r" | awk '{ print } /ct state established,related accept/ { print "add rule ip filter SOLEUR-EGRESS ip daddr 169.254.0.0/16 counter drop" }'; } > "$SEED2/txn.2"
cp "$HAPPY"/txn.1 "$SEED2/txn.1"
expect "harness: the census reports a link-local drop that sits AFTER an accept as dirty" test "$(ll_clean "$SEED2" && echo clean || echo dirty)" = dirty

# The suite asserts its own run: an instrument that records nothing must RED the suite, never pass vacuously.
if [ -n "${CEN_STUB_NOLOG:-}" ]; then printf 'FAIL - the stub nft recorded 0 calls; every rendered-ruleset assertion above is vacuous\n'; exit 1; fi

# ── mutation rows (outer run only) ────────────────────────────────────────────────────────────
if [ -z "$CEN_MUTANT" ]; then
  mut_rows=0
  MUT="$SCRATCH/mut"; mkdir -p "$MUT"
  MAXJ="${CEN_MUT_JOBS:-3}"
  declare -a MUT_NAME MUT_WANT MUT_LAND
  # MUT_TARGET picks what the next rows mutate: the loader (CEN_SCRIPT) or the resolver (CEN_RESOLVER).
  MUT_TARGET=loader
  tbase() { if [ "$MUT_TARGET" = resolver ]; then printf '%s' "$RPRISTINE"; else printf '%s' "$PRISTINE"; fi; }
  tenv() { if [ "$MUT_TARGET" = resolver ]; then printf 'CEN_RESOLVER'; else printf 'CEN_SCRIPT'; fi; }
  throttle() { while [ "$(jobs -rp | wc -l)" -ge "$MAXJ" ]; do wait -n; done; }
  # <name> <caught|survive> <python expression over s producing the mutated source, or statements assigning `new`>
  mutate() {
    local name="$1" want="$2" expr="$3" n=$((mut_rows + 1)) m base ev
    m="$MUT/m$n.sh"; base="$(tbase)"; ev="$(tenv)"
    mut_rows=$n; MUT_NAME[n]="$name"; MUT_WANT[n]="$want"; MUT_LAND[n]=""
    cp "$base" "$m"
    CEN_M="$m" CEN_EXPR="$expr" python3 - <<'PY' || { MUT_LAND[n]=python; return; }
import os
p = os.environ["CEN_M"]
s = open(p).read()
ns = {"s": s}
src = os.environ["CEN_EXPR"]
try:
    new = eval(src, {}, ns)
except SyntaxError:
    exec(src, {}, ns)
    new = ns["new"]
assert new != s, "mutation produced identical source"
open(p, "w").write(new)
PY
    cmp -s "$base" "$m" && { MUT_LAND[n]=identical; return; }
    bash -n "$m" 2>/dev/null || { MUT_LAND[n]=syntax; return; }
    throttle
    ( rc=0; env CEN_MUTANT=1 "$ev=$m" bash "$SELF" > "$MUT/out.$n" 2>&1 || rc=$?; echo "$rc" > "$MUT/rc.$n" ) &
  }
  msub() { # <name> <caught|survive> <old literal> <new literal>: replace the first occurrence (it must exist)
    local name="$1" want="$2" n=$((mut_rows + 1)) m base ev
    m="$MUT/m$n.sh"; base="$(tbase)"; ev="$(tenv)"
    mut_rows=$n; MUT_NAME[n]="$name"; MUT_WANT[n]="$want"; MUT_LAND[n]=""
    cp "$base" "$m"
    CEN_M="$m" CEN_OLD="$3" CEN_NEW="$4" python3 - <<'PY' || { MUT_LAND[n]=python; return; }
import os
p = os.environ["CEN_M"]
s = open(p).read()
old, new = os.environ["CEN_OLD"], os.environ["CEN_NEW"]
assert old in s, "mutation anchor not found"
open(p, "w").write(s.replace(old, new, 1))
PY
    cmp -s "$base" "$m" && { MUT_LAND[n]=identical; return; }
    bash -n "$m" 2>/dev/null || { MUT_LAND[n]=syntax; return; }
    throttle
    ( rc=0; env CEN_MUTANT=1 "$ev=$m" bash "$SELF" > "$MUT/out.$n" 2>&1 || rc=$?; echo "$rc" > "$MUT/rc.$n" ) &
  }
  envrow() { # <name> <want-rc> <ENV=val>
    local n=$((mut_rows + 1))
    mut_rows=$n; MUT_NAME[n]="harness row: $1"; MUT_WANT[n]="env:$2"; MUT_LAND[n]=""
    throttle
    ( rc=0; env CEN_MUTANT=1 "$3" bash "$SELF" > "$MUT/out.$n" 2>&1 || rc=$?; echo "$rc" > "$MUT/rc.$n" ) &
  }
  score_rows() {
    local n rc want
    wait
    for ((n = 1; n <= mut_rows; n++)); do
      want="${MUT_WANT[n]}"
      case "${MUT_LAND[n]}" in
        python) no "mutation did NOT land (python): ${MUT_NAME[n]}"; continue ;;
        identical) no "mutation did NOT land (identical bytes): ${MUT_NAME[n]}"; continue ;;
        syntax) no "mutation does not parse (bash -n): ${MUT_NAME[n]}"; continue ;;
      esac
      rc=$(cat "$MUT/rc.$n" 2>/dev/null || echo missing)
      case "$want" in
        env:*) [ "$rc" != 0 ] && [ "$rc" = "${want#env:}" ] && ok 0 "${MUT_NAME[n]}" || ok 1 "${MUT_NAME[n]} (rc=$rc)" ;;
        *)
          case "$rc" in
            1) [ "$want" = caught ] && ok 0 "mutation caught: ${MUT_NAME[n]}" || ok 1 "mutation caught but expected to survive: ${MUT_NAME[n]}" ;;
            0) [ "$want" = survive ] && ok 0 "harmless variant stays green: ${MUT_NAME[n]}" || ok 1 "mutation SURVIVED: ${MUT_NAME[n]}" ;;
            *) no "broken instrument (rc=$rc): ${MUT_NAME[n]}" ;;
          esac ;;
      esac
    done
  }

  # Guard 2 rows 1, 6: the overlap predicate and its boundaries.
  msub "1 the overlap check is removed from is_valid_ipv4_cidr" caught \
    '  (( hi < LL_LO || lo > LL_HI )) || return 1
' ''
  msub "1b the overlap check is prefix matching on 169.254. instead of range arithmetic" caught \
    '  (( hi < LL_LO || lo > LL_HI )) || return 1' \
    '  [[ "$cidr" == 169.254.* ]] && return 1'
  msub "1c the upper bound is off by one (169.254.255.255/32 passes)" caught \
    'LL_HI=$((0xA9FEFFFF))' 'LL_HI=$((0xA9FEFFFE))'
  msub "1d the lower bound is off by one (169.254.0.0/32 passes)" caught \
    'LL_LO=$((0xA9FE0000))' 'LL_LO=$((0xA9FE0001))'
  msub "1e the leading-zero refusal is removed (010.0.0.0/8 is read as octal 8)" caught \
    '    [[ "$part" =~ ^0[0-9] ]] && return 1' '    :'
  # Guard 2 row 5: the literal rules of the Phase 3 heredoc.
  msub "5a the literal link-local drop is deleted from the Phase 3 heredoc" caught \
    'add rule ip filter SOLEUR-EGRESS ip daddr 169.254.0.0/16 counter drop comment "soleur-egress: link-local (instance metadata) drop"
' ''
  mutate "5b the link-local drop is moved AFTER the return-traffic accept" caught \
    'll = "add rule ip filter SOLEUR-EGRESS ip daddr 169.254.0.0/16 counter drop comment \"soleur-egress: link-local (instance metadata) drop\"\n"
ret = "add rule ip filter SOLEUR-EGRESS ct state established,related accept comment \"soleur-egress: return traffic\"\n"
assert ll in s and ret in s
new = s.replace(ll, "", 1).replace(ret, ret + ll, 1)'
  msub "5c a literal accept for the metadata endpoint is added to the heredoc" caught \
    'add rule ip filter SOLEUR-EGRESS ct state established,related accept comment "soleur-egress: return traffic"' \
    'add rule ip filter SOLEUR-EGRESS ip daddr 169.254.169.254 accept comment "x"
add rule ip filter SOLEUR-EGRESS ct state established,related accept comment "soleur-egress: return traffic"'
  msub "5d the default drop is no longer the last rule" caught \
    'add rule ip filter SOLEUR-EGRESS counter drop comment "soleur-egress: default drop"' \
    'add rule ip filter SOLEUR-EGRESS counter drop comment "soleur-egress: default drop"
add rule ip filter SOLEUR-EGRESS ip daddr @soleur_egress_allow accept comment "late"'
  # Guard 2 row 7: a CIDR-validation die must not touch the live ruleset.
  mutate "7 the CIDR-validation die path flushes the live chain before dying" caught \
    "s.replace('|| die \"invalid CIDR in', '|| { nft flush chain ip filter SOLEUR-EGRESS; die \"invalid CIDR in', 1).replace('refusing to build nft elements)\"', 'refusing to build nft elements)\"; }', 1)"
  # The single DOCKER-USER jump.
  msub "8 the DOCKER-USER jump is inserted on every run (the existence probe is dropped)" caught \
    "if ! nft list chain ip filter DOCKER-USER | grep -q 'jump SOLEUR-EGRESS'; then" 'if true; then'
  mutate "9 harmless: a comment-only edit must stay green" survive \
    "s.replace('declare table/sets/chains', 'declare the table, sets and chains', 1)"
  # Guard 2 rows 2 and 6: the resolver's feeders (host answers, container view, grace pool, pin set).
  MUT_TARGET=resolver
  msub "R1 the link-local predicate never matches (the filter is removed)" caught \
    '  (( 10#${BASH_REMATCH[1]} == 169 && 10#${BASH_REMATCH[2]} == 254 ))' '  return 1'
  msub "R2 the predicate matches only the metadata address, not the /16" caught \
    '  (( 10#${BASH_REMATCH[1]} == 169 && 10#${BASH_REMATCH[2]} == 254 ))' '  [[ "$a" == 169.254.169.254 ]]'
  msub "R3 the v4-mapped prefix is not normalised" caught \
    '  local a="${1#::[fF][fF][fF][fF]:}"' '  local a="$1"'
  msub "R4 the per-host strip is removed (an all-link-local host no longer counts as a failure, so the tick prunes)" caught \
    '    ips="$(printf '"'"'%s\n'"'"' "$ips" | ll_strip)"' '    :'
  msub "R5 the grace-pool purge is removed (a planted seen/169.254.169.254 stays on disk)" caught \
    '      rm -f "$seen_file"
      log "WARN: purged link-local entry $ip from the grace-window store"
      continue' '      continue'
  msub "R6 the final chokepoint no longer strips the resolver pin set (a link-local nameserver is allowlisted)" caught \
    'DNS_IPS="$(printf '"'"'%s\n'"'"' "$DNS_IPS" | ll_strip)"' ':'
  msub "R7 the link-local Sentry event is never posted (silent drop)" caught \
    '  [[ -e "$marker" ]] && return 0' '  return 0'
  msub "R8 the once-per-source marker is never created (an event every tick)" caught \
    '  : > "$marker"' '  :'
  msub "R9 only the container-view merge-time strip is removed: the grace-pool purge and the final chokepoint still keep it out (layered, so this variant stays green)" survive \
    'DESIRED_ALLOW="$(printf '"'"'%s\n'"'"' "$DESIRED_ALLOW" | ll_strip)"' ':'
  MUT_TARGET=loader
  # Guard 2 row 4 / H1: the instrument must be able to fail.
  envrow "4 the stub nft records nothing (the loader 'ran' with 0 calls checked)" 1 "CEN_STUB_NOLOG=1"

  score_rows
  MUT_ROWS_EXPECTED=22
  [ "$mut_rows" -eq "$MUT_ROWS_EXPECTED" ] || { printf 'FAIL - %s mutation rows ran, expected %s\n' "$mut_rows" "$MUT_ROWS_EXPECTED"; exit 1; }
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
# Anti-vacuity floor (EXACT: 41 inner assertions + 22 mutation rows; raise it with every added check). The threshold sits on the line directly above its `if`.
_cen_rows="${CEN_MUTANT:+0}" # an inner (mutant) run has no mutation rows of its own
MIN_ASSERTIONS=$((41 + ${_cen_rows:-22}))
if [ "$pass" -lt "$MIN_ASSERTIONS" ]; then
  printf 'FAIL - only %s assertions passed (floor %s) - a block stopped running\n' "$pass" "$MIN_ASSERTIONS"; exit 1
fi
[ "$fail" -eq 0 ] || { printf 'failed: %s\n' "${FAILED[@]}"; exit 1; }
printf 'all assertions passed\n'
exit 0
