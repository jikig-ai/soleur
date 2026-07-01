#!/usr/bin/env bash
# Drift-guard for the container egress firewall (#5046 PR-2).
#
# Locks the load-bearing invariants of the DOCKER-USER egress allowlist:
#   1. server.tf DELIVERS every firewall artifact (anchored on the delivery
#      construct `source = "${path.module}/<file>"` + its destination — never
#      a bare path, which false-passes when it also appears in chmod/comment
#      lines; see 2026-06-02 drift-guard learning).
#   2. triggers_replace folds BOTH the artifact hashes AND the server id
#      (hr-fresh-host-provisioning — a replaced VM must re-provision).
#   3. The apply workflow -targets the new resource in the SSH block
#      (terraform-target-parity.test.ts enforces the union; this pins the
#      specific block).
#   4. Script safety invariants: sets populate BEFORE default-drop installs
#      (availability ordering); additive-then-prune (no `flush set`);
#      fail-safe-on-empty; DNS pin + fail-loud drop logging present.
#   5. Units alarm on failure (OnFailure=) and the timer survives reboots.
#   6. cloud-init fresh-host mirror carries the artifacts.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_TF="$SCRIPT_DIR/server.tf"
CLOUD_INIT="$SCRIPT_DIR/cloud-init.yml"
WORKFLOW="$SCRIPT_DIR/../../../.github/workflows/apply-web-platform-infra.yml"
LOADER="$SCRIPT_DIR/cron-egress-nftables.sh"
RESOLVER="$SCRIPT_DIR/cron-egress-resolve.sh"
ALARM="$SCRIPT_DIR/cron-egress-alarm.sh"
ALLOWLIST="$SCRIPT_DIR/cron-egress-allowlist.txt"
# Post-apply assertion block, extracted to its own delivered script (#5289) so
# an edit to it changes config_hash and re-provisions — inline-block edits were
# silent no-ops (the hash folded only the 9 artifacts, not the inline block).
ASSERT_SCRIPT="$SCRIPT_DIR/cron-egress-postapply-assert.sh"

PASS=0
FAIL=0

assert_grep() {
  local description="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (pattern not found in $(basename "$file"): $pattern)"
  fi
}

assert_not_grep() {
  local description="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (forbidden pattern present in $(basename "$file"): $pattern)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  fi
}

assert_cmd() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description ($*)"
  fi
}

echo "--- cron-egress firewall drift-guard ---"

echo "-- artifacts exist + parse --"
for f in "$LOADER" "$RESOLVER" "$ALARM" "$ALLOWLIST" \
  "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt" \
  "$SCRIPT_DIR/cron-egress-firewall.service" \
  "$SCRIPT_DIR/cron-egress-resolve.service" \
  "$SCRIPT_DIR/cron-egress-resolve.timer" \
  "$SCRIPT_DIR/cron-egress-alarm@.service" \
  "$ASSERT_SCRIPT"; do
  assert_cmd "exists: $(basename "$f")" test -f "$f"
done
assert_cmd "loader parses (bash -n)" bash -n "$LOADER"
assert_cmd "resolver parses (bash -n)" bash -n "$RESOLVER"
assert_cmd "alarm parses (bash -n)" bash -n "$ALARM"
assert_cmd "post-apply assert script parses (bash -n)" bash -n "$ASSERT_SCRIPT"

echo "-- server.tf delivery (anchored on the file-provisioner construct) --"
assert_grep "resource exists" 'resource "terraform_data" "cron_egress_firewall"' "$SERVER_TF"
for f in cron-egress-nftables.sh cron-egress-resolve.sh cron-egress-alarm.sh \
  cron-egress-allowlist.txt cron-egress-allowlist-cidr.txt cron-egress-firewall.service \
  cron-egress-resolve.service cron-egress-resolve.timer cron-egress-postapply-assert.sh; do
  assert_grep "delivers $f (source=)" "source += +\"\\\$\\{path\\.module\\}/$f\"" "$SERVER_TF"
  assert_grep "trigger folds $f hash" "file\\(\"\\\$\\{path\\.module\\}/$f\"\\)" "$SERVER_TF"
done
# The template unit's `@` needs its own anchors (regex-escaping differs).
assert_grep "delivers cron-egress-alarm@.service (source=)" 'source += +"\$\{path\.module\}/cron-egress-alarm@\.service"' "$SERVER_TF"
SERVER_BLOCK="$(awk '/resource "terraform_data" "cron_egress_firewall"/,/^}/' "$SERVER_TF")"
if echo "$SERVER_BLOCK" | grep -qE 'server_id += +hcloud_server\.web\["web-1"\]\.id'; then
  PASS=$((PASS + 1)); echo "  PASS: cron_egress_firewall trigger folds hcloud_server.web[\"web-1\"].id"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: cron_egress_firewall trigger does not fold hcloud_server.web[\"web-1\"].id"
fi
if echo "$SERVER_BLOCK" | grep -q 'mkdir -p /etc/soleur'; then
  PASS=$((PASS + 1)); echo "  PASS: parent dir created before file provisioners (scp does not mkdir)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: missing 'mkdir -p /etc/soleur' before file provisioners"
fi
# Live positive+negative probe (AC-P2.8 iii — the silent-green guard: nft -f
# exits 0 on an inert ruleset; only a real container probe proves enforcement).
# These constructs moved from the inline remote-exec to the delivered
# cron-egress-postapply-assert.sh (#5289); assert against the script now.
# Anchor on the ASSERT-FAILED: sentinel (executable line only) NOT the bare
# 'egress-probe-*' literal, which also appears in the script's comment prose —
# a bare grep would false-pass if the executable probe line were deleted but
# its comment kept (comment-prose false-match class, 2026-06-03 learning).
if grep -qE 'ASSERT-FAILED: egress-probe-negative' "$ASSERT_SCRIPT"; then
  PASS=$((PASS + 1)); echo "  PASS: post-apply negative container probe present"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: post-apply negative container probe missing"
fi
if grep -qE 'ASSERT-FAILED: egress-probe-positive' "$ASSERT_SCRIPT"; then
  PASS=$((PASS + 1)); echo "  PASS: post-apply positive container probe present"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: post-apply positive container probe missing"
fi
# The service is Type=oneshot/RemainAfterExit=yes, so `enable --now` no-ops on an
# already-active unit and the loader never re-reads a freshly-provisioned CIDR file
# (the inert-fix bug behind incident 5516336). The assert script MUST `restart` to
# re-run the loader so file changes actually load into the live nft set.
if grep -q 'systemctl restart cron-egress-firewall\.service' "$ASSERT_SCRIPT"; then
  PASS=$((PASS + 1)); echo "  PASS: provisioner restarts the firewall service (reloads new CIDR; not a no-op enable --now)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: provisioner must 'systemctl restart cron-egress-firewall.service' — enable --now no-ops on the active oneshot and a new CIDR file never loads"
fi

echo "-- apply workflow SSH -target --"
assert_grep "workflow -targets cron_egress_firewall" 'target=terraform_data\.cron_egress_firewall' "$WORKFLOW"

echo "-- loader safety invariants --"
# Availability ordering: the resolve (set population) line must precede the
# default-drop install (flush chain + add rules) — proven by line order.
RESOLVE_LINE="$(grep -n '"\$RESOLVE_SCRIPT"' "$LOADER" | head -1 | cut -d: -f1)"
DROP_LINE="$(grep -n 'flush chain ip filter SOLEUR-EGRESS' "$LOADER" | head -1 | cut -d: -f1)"
if [[ -n "$RESOLVE_LINE" && -n "$DROP_LINE" && "$RESOLVE_LINE" -lt "$DROP_LINE" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: sets populate BEFORE the default-drop installs (line $RESOLVE_LINE < $DROP_LINE)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: resolve must run before the drop rules install (resolve=$RESOLVE_LINE drop=$DROP_LINE)"
fi
assert_grep "default-drop log is rate-limited (no journald self-DoS)" 'limit rate 10/minute burst 50 packets log prefix "egress-blocked: " level notice' "$LOADER"
assert_grep "default-drop terminal rule present" 'counter drop comment "soleur-egress: default drop"' "$LOADER"
assert_grep "DNS pin accept rule" 'udp dport 53 ip daddr @soleur_egress_dns accept' "$LOADER"
assert_grep "DNS exfil drop is logged" 'egress-dns-exfil' "$LOADER"
assert_grep "host-gateway :8288 accept" 'tcp dport 8288 accept' "$LOADER"
assert_grep "bridge gateway derived, not hardcoded" 'docker network inspect bridge' "$LOADER"
assert_grep "IPv6 bypass guard" 'EnableIPv6' "$LOADER"
assert_grep "jump rule scoped to the bridge interface" 'iifname "\$BRIDGE_IF" counter jump SOLEUR-EGRESS' "$LOADER"
assert_not_grep "never flushes the shared DOCKER-USER chain" 'flush chain ip filter DOCKER-USER' "$LOADER"

# GitHub LB-range fix: a static interval CIDR set parallel to the single-IP set.
assert_grep "declares interval CIDR set" 'set soleur_egress_allow_cidr' "$LOADER"
assert_grep "CIDR set uses flags interval" 'flags interval' "$LOADER"
assert_grep "CIDR allowlist accept rule present" 'ip daddr @soleur_egress_allow_cidr accept' "$LOADER"
assert_grep "loader reads the CIDR allowlist file" 'cron-egress-allowlist-cidr.txt' "$LOADER"
assert_grep "CIDR file carries GitHub git /20" '140.82.112.0/20' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt"
# api.github.com round-robins DNS across BOTH the 4 big git/pages blocks AND ~48
# Azure 20.x/4.x /32 hosts (api.github.com/meta `.git`+`.api`). The 4-block-only
# file left those /32s uncovered → a fire landing on one was default-dropped →
# missed cron check-in (incident 5516336, scheduled-ruleset-bypass-audit,
# 2026-06-14). The CIDR file MUST carry the Azure /32s for api.github.com.
assert_grep "CIDR file carries >=1 Azure 20.x /32 (api.github.com LB pool)" '^20[.][0-9]+[.][0-9]+[.][0-9]+/32$' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt"
assert_grep "CIDR file carries >=1 Azure 4.x /32 (api.github.com LB pool)" '^4[.][0-9]+[.][0-9]+[.][0-9]+/32$' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt"
# Structural drift-guard (de-magicked + de-circularized, #5284). The old exact
# `count == 52` guard was itself a staleness trap: a /meta rotation that swaps one
# /32 for another keeps the count at 52 while the ranges are wrong. The file is
# now generated by apps/web-platform/infra/scripts/gen-github-egress-cidr.sh and
# auto-refreshed by the cron-github-cidr-refresh Inngest cron. Generator
# DETERMINISM (fixture-in -> golden-out) is asserted in gen-github-egress-cidr.test.sh;
# live coverage by the runbook `comm -23` probe + the cron at runtime. This offline
# guard asserts ONLY the structural invariants a hand-edit / partial-revert /
# truncation breaks (it does NOT call live /meta and does NOT assert the committed
# file equals the synthetic fixture — those would be flaky / always-fail).
assert_grep "CIDR file carries the generated DO-NOT-EDIT header (not a hand-edit)" 'DO NOT EDIT .+ regenerate via .+gen-github-egress-cidr\.sh' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt"
# Floor count: a partial revert to just the 4 big git/pages blocks (the
# incident-5516336 regression) drops far below the Azure /32 pool size. A floor is
# NOT a staleness trap — rotations keep the count ~constant; only truncation trips it.
CIDR_COUNT="$(grep -vcE '^[[:space:]]*#|^[[:space:]]*$' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt")"
if [[ "$CIDR_COUNT" -ge 40 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: CIDR allowlist range count is $CIDR_COUNT (floor >= 40; partial-revert/truncation guard)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: CIDR allowlist range count is $CIDR_COUNT (below the floor of 40 — a partial revert/truncation to the 4 big blocks; regenerate via gen-github-egress-cidr.sh)"
fi
# Over-broad reject: both the generator's and the loader's validators accept a
# structurally-valid 0.0.0.0/0; the prefix-floor (>= /8) is the breadth defense
# the one allow-all egress vector needs. No committed line may have prefix < /8.
OVERBROAD="$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt" | awk -F/ '$2 < 8 {print}')"
if [[ -z "$OVERBROAD" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: no committed CIDR has an over-broad prefix (< /8)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: over-broad CIDR(s) with prefix < /8 present (allow-all vector): $OVERBROAD"
fi

echo "-- CIDR validation (nft-injection hardening, #5242) --"
# The CIDR file is interpolated VERBATIM into the `add element ... { $CIDR_ELEMENTS }`
# nft heredoc. An unvalidated line containing `}`, an nft keyword, whitespace, or
# command-substitution is injected into the ruleset (e.g. `0.0.0.0/0` allow-all, or
# `}; add rule ... accept`). The loader MUST validate every non-comment line against
# a strict IPv4-CIDR shape and reject the WHOLE file (die/exit 1) on any mismatch —
# fail-loud (operator paged via OnFailure=) over half-installing a firewall.
#
# Source-shape drift guards (RED→GREEN with the loader edit):
assert_grep "validator function defined" 'is_valid_ipv4_cidr\(\)' "$LOADER"
assert_grep "reject-whole-file on invalid line (die, not skip)" '\|\| die "invalid CIDR in' "$LOADER"
assert_not_grep "old unvalidated paste -sd, build removed" 'paste -sd,' "$LOADER"
# Anchor on the executable arithmetic form (`o1 <= 255`, present ONLY on the
# `(( ... ))` code line), NOT the bare `<= 255` which also appears in the loader's
# explanatory comment — a bare-pattern assert false-passes if the range-check code is
# deleted but the comment kept (comment-prose false-match class, 2026-06-03 learning).
assert_grep "octet/prefix range-check (defense in depth)" 'o1 <= 255' "$LOADER"

# Cross-file predicate parity: the test's behavioral copy (below) must carry the EXACT
# predicate the loader ships, else the copy drifts silently (same convention as
# SENTRY_SLUG/drop-prefix parity above). grep -F = fixed string (literal). Pin BOTH
# halves of the predicate — the regex shape AND the octet/prefix range-check arithmetic
# — so a `<= 255`→`<= 254` (or `<= 32`→`<= 128`) drift in either file fails the suite.
CIDR_RE='([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})'
CIDR_RANGE='o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32'
if grep -qF -- "$CIDR_RE" "$LOADER" && grep -qF -- "$CIDR_RE" "${BASH_SOURCE[0]}"; then
  PASS=$((PASS + 1)); echo "  PASS: CIDR regex literal pinned identically in loader and test"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: CIDR regex literal drift between loader and test (loader must carry: $CIDR_RE)"
fi
if grep -qF -- "$CIDR_RANGE" "$LOADER" && grep -qF -- "$CIDR_RANGE" "${BASH_SOURCE[0]}"; then
  PASS=$((PASS + 1)); echo "  PASS: CIDR range-check arithmetic pinned identically in loader and test"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: CIDR range-check drift between loader and test (loader must carry: $CIDR_RANGE)"
fi

# Behavioral exercise of the validator. `nft` is absent on CI runners and the full
# loader aborts at `command -v nft` before reaching the CIDR parse, so the script
# cannot run end-to-end here. Pin a COPY of the exact predicate (guarded byte-for-byte
# by the literal-parity assert above) and exercise it against crafted lines.
test_is_valid_ipv4_cidr() {
  local cidr="$1" prefix o1 o2 o3 o4
  [[ "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]] || return 1
  o1=${BASH_REMATCH[1]}; o2=${BASH_REMATCH[2]}; o3=${BASH_REMATCH[3]}
  o4=${BASH_REMATCH[4]}; prefix=${BASH_REMATCH[5]}
  (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32 )) || return 1
  return 0
}
assert_cidr_accept() {
  if test_is_valid_ipv4_cidr "$1"; then
    PASS=$((PASS + 1)); echo "  PASS: accepts $2"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: should accept $2 ('$1')"
  fi
}
assert_cidr_reject() {
  if test_is_valid_ipv4_cidr "$1"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: should REJECT $2 ('$1')"
  else
    PASS=$((PASS + 1)); echo "  PASS: rejects $2"
  fi
}
# AC2 — the 4 real allowlist ranges accept:
assert_cidr_accept "140.82.112.0/20" "real GitHub git /20"
assert_cidr_accept "185.199.108.0/22" "real GitHub pages /22"
assert_cidr_accept "192.30.252.0/22" "real GitHub /22"
assert_cidr_accept "143.55.64.0/20"  "real GitHub /20"
# Representative api.github.com Azure LB /32 (api.github.com/meta `.api`):
assert_cidr_accept "20.201.28.151/32" "real GitHub api Azure /32"
assert_cidr_accept "4.208.26.197/32"  "real GitHub api Azure /32"
# Structurally valid (allow-all breadth is a content concern, out of scope — see plan Non-Goals):
assert_cidr_accept "0.0.0.0/0" "structurally valid CIDR"
# AC1 — injection / command-substitution / whitespace shapes reject:
assert_cidr_reject "140.82.112.0/20}; add rule ip filter SOLEUR-EGRESS accept" "nft-injection (} + add rule)"
assert_cidr_reject "; nft flush ruleset" "nft keyword line"
assert_cidr_reject '$(curl evil)' "command-substitution shape"
assert_cidr_reject " 140.82.112.0/20" "leading whitespace"
assert_cidr_reject "140.82.112.0/20 " "trailing whitespace"
assert_cidr_reject $'1.1.1.0/24\nevil' "embedded newline"
# AC1 (malformed shape) reject:
assert_cidr_reject "0.0.0.0" "no prefix"
assert_cidr_reject "140.82.112/20" "3 octets"
assert_cidr_reject "garbage" "non-CIDR text"
# AC4 — octet/prefix range (the issue's bare regex would WRONGLY accept these):
assert_cidr_reject "999.999.999.999/99" "octets and prefix out of range"
assert_cidr_reject "256.1.1.1/8" "first octet > 255"
assert_cidr_reject "1.1.1.1/33" "prefix > 32"

# AC3 — comment/blank lines are skipped by the loop guard, never validated:
COMMENT_SKIP_RE='^[[:space:]]*(#|$)'
assert_grep "loop skips comment/blank lines before validation" "$COMMENT_SKIP_RE" "$LOADER"

echo "-- resolver safety invariants --"
# Anchored on the executable form (`flush set ip filter …`), not the bare
# phrase — the resolver's own comment legitimately SAYS "never flush set"
# (comment-prose false-match class, 2026-06-03 learning).
assert_not_grep "never flush-set (additive-then-prune only)" 'flush set ip filter' "$RESOLVER"
# Behavior anchors (executable constructs, NOT prose — a kept comment must
# not green a deleted code path; 2026-06-03 comment-prose learning):
assert_grep "fail-safe on empty resolution (guard construct)" 'refusing to touch the sets' "$RESOLVER"
assert_grep "additive-only tick on partial failure (PRUNE flip construct)" 'PRUNE="no-prune"' "$RESOLVER"
assert_grep "absent dynamic env counts as failed host (no prune on Doppler drift)" 'dynamic-host env .var unset' "$RESOLVER"
if grep -qF "DNS_IPS=$'8.8.8.8" "$RESOLVER"; then
  PASS=$((PASS + 1)); echo "  PASS: DNS pin always unions Docker substitution pair"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: DNS pin must unconditionally seed Docker's 8.8.8.8/8.8.4.4 substitution pair"
fi
assert_grep "container-view resolution unioned (resolver-divergence guard)" 'CONTAINER_VIEW' "$RESOLVER"
assert_grep "self-heal: re-runs loader when enforcement rules missing" 'enforcement rules missing' "$RESOLVER"
assert_grep "self-heal recursion guard (loader sets the env)" 'CRON_EGRESS_FROM_LOADER=1' "$LOADER"
assert_grep "concurrent runs serialized via flock" 'flock -w 120' "$RESOLVER"
assert_grep "BOTH drop prefixes counted toward the Sentry event" "egress-.blocked.dns-exfil.: " "$RESOLVER"
assert_grep "single atomic nft -f batch apply" 'nft -f -' "$RESOLVER"
assert_grep "Sentry Crons ok check-in (dead-timer detection)" 'sentry_checkin ok' "$RESOLVER"
assert_grep "Sentry Crons error check-in on failure" 'sentry_checkin error' "$RESOLVER"

echo "-- resolver grace-window retention (LB-rotation fix) --"
# Source-anchored guards (executable constructs, NOT comment prose — 2026-06-03
# false-match class). LB-fronted allowlisted hosts (Cloudflare/AWS/Google) rotate
# across large pools; the single-A-record snapshot pins only the current tick's
# IPs, so a connect to a freshly-rotated IP before the next tick is default-dropped.
# The resolver must RETAIN every IP seen for an allowlisted host within a window.
assert_grep "retention: GRACE_WINDOW_SECS constant (env-overridable, 24h default)" 'GRACE_WINDOW_SECS="\$\{GRACE_WINDOW_SECS:-86400\}"' "$RESOLVER"
assert_grep "retention: SEEN_DIR store constant (env-overridable, /var/lib)" 'SEEN_DIR="\$\{SEEN_DIR:-/var/lib/cron-egress-resolve/seen\}"' "$RESOLVER"
assert_grep "retention: store dir created beside FAILCOUNT_DIR" 'mkdir -p "\$SEEN_DIR"' "$RESOLVER"
assert_grep "retention: records every current-tick IP's last-seen (every tick)" 'echo "\$NOW_EPOCH" > "\$SEEN_DIR/\$ip"' "$RESOLVER"
assert_grep "retention: within-window stored IPs union into RETAINED" 'age <= GRACE_WINDOW_SECS' "$RESOLVER"
assert_grep "retention: store readback via basename (store-union path)" 'basename "\$seen_file"' "$RESOLVER"
assert_grep "retention: strict-mode last-seen timestamp guard" '\[\[ "\$ts" =~ \^\[0-9\]\+\$ \]\]' "$RESOLVER"
assert_grep "retention: eviction gated on prune tick (FAILED_HOSTS==0, no-prune suppresses)" 'FAILED_HOSTS" -eq 0' "$RESOLVER"
assert_grep "retention: RETAINED set feeds the ALLOW_SET batch (not raw DESIRED_ALLOW)" 'build_batch "\$ALLOW_SET" "\$RETAINED"' "$RESOLVER"
assert_grep "retention: OK log carries retained= count" 'retained=' "$RESOLVER"
# Ordering: the fail-safe-on-empty guard MUST precede the store-record line, so a
# zero-resolution tick aborts BEFORE the store is ever read (a DNS outage must not
# be papered over by stale store IPs). Proven by line order (loader-precedent shape).
FAILSAFE_LINE="$(grep -n 'refusing to touch the sets' "$RESOLVER" | head -1 | cut -d: -f1)"
RETAIN_LINE="$(grep -n 'SEEN_DIR/\$ip' "$RESOLVER" | head -1 | cut -d: -f1)"
if [[ -n "$FAILSAFE_LINE" && -n "$RETAIN_LINE" && "$FAILSAFE_LINE" -lt "$RETAIN_LINE" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: fail-safe-on-empty guard precedes the store-record block (line $FAILSAFE_LINE < $RETAIN_LINE)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: store-record must run AFTER the fail-safe-on-empty guard (failsafe=$FAILSAFE_LINE retain=$RETAIN_LINE)"
fi

# Cross-file predicate parity: the retention_build() copy below must carry the EXACT
# load-bearing fragments the resolver ships, else the copy drifts silently while its
# scenarios keep passing (same convention as the CIDR validator parity above). The
# source-anchored guards pin the RESOLVER's constructs; these pin that the test COPY
# matches. grep -qF = fixed literal. Both fragments are executable-only (the `$frag`
# echo line and the escaped source-anchor asserts above do not contain them verbatim),
# so a deleted code line cannot be masked by a comment/echo match (2026-06-03 class).
for frag in '(( age <= ' ' -eq 0 ]]; then'; do
  if grep -qF -- "$frag" "$RESOLVER" && grep -qF -- "$frag" "${BASH_SOURCE[0]}"; then
    PASS=$((PASS + 1)); echo "  PASS: retention fragment pinned identically in resolver + test copy ($frag)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: retention fragment drift between resolver and test copy ($frag)"
  fi
done

# Behavioral exercise (nft absent on CI; exercise the retain/evict set-building in
# isolation against a tmp store + tiny window). Mirrors the test_is_valid_ipv4_cidr
# copy convention — the source-anchored guards above pin that the resolver ships
# this exact logic.
retention_build() {
  # args: seen_dir now window failed_hosts ; stdin = current-tick IPs (one/line)
  local seen_dir="$1" now="$2" window="$3" failed_hosts="$4"
  local desired retained ip ts age seen_file
  desired="$(cat | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)"
  while IFS= read -r ip; do
    [[ -n "$ip" ]] || continue
    echo "$now" > "$seen_dir/$ip"
  done <<< "$desired"
  retained="$desired"
  if [[ -d "$seen_dir" ]]; then
    while IFS= read -r seen_file; do
      [[ -n "$seen_file" ]] || continue
      ip="$(basename "$seen_file")"
      [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      ts="$(cat "$seen_file" 2>/dev/null || echo 0)"
      [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
      age=$(( now - ts ))
      if (( age <= window )); then
        retained+=$'\n'"$ip"
      elif [[ "$failed_hosts" -eq 0 ]]; then
        rm -f "$seen_file"
      fi
    done < <(find "$seen_dir" -type f 2>/dev/null)
  fi
  echo "$retained" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true
}

# (a) retention within window: stored-but-not-re-resolved IP is RETAINED.
T1="$(mktemp -d)"; echo "100" > "$T1/104.18.24.159"
OUT1="$(printf '10.0.0.1\n' | retention_build "$T1" 150 100 0)"
if echo "$OUT1" | grep -qx '104.18.24.159' && echo "$OUT1" | grep -qx '10.0.0.1'; then
  PASS=$((PASS + 1)); echo "  PASS: within-window stored IP retained though not re-resolved this tick"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: within-window stored IP should be retained (got: $(echo "$OUT1" | tr '\n' ' '))"
fi

# (b) eviction after window (prune tick): past-window IP dropped AND store entry removed.
T2="$(mktemp -d)"; echo "100" > "$T2/198.51.100.7"
OUT2="$(printf '10.0.0.1\n' | retention_build "$T2" 300 100 0)"
if ! echo "$OUT2" | grep -qx '198.51.100.7' && [[ ! -f "$T2/198.51.100.7" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: past-window IP evicted and store entry removed on prune tick"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: past-window IP should be evicted + file removed on prune tick"
fi

# (c) no-prune (FAILED_HOSTS>0) suppresses eviction: past-window store entry KEPT.
T3="$(mktemp -d)"; echo "100" > "$T3/203.0.113.9"
printf '10.0.0.1\n' | retention_build "$T3" 300 100 1 >/dev/null  # scenario asserts on store-file state, not output
if [[ -f "$T3/203.0.113.9" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: no-prune tick keeps past-window store entry (defers eviction)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: no-prune tick must NOT evict the past-window store entry"
fi

# (d) no-prune STILL records (refresh ts) + unions (within-window stored IP).
T4="$(mktemp -d)"; echo "100" > "$T4/198.18.0.5"
OUT4="$(printf '198.18.0.9\n' | retention_build "$T4" 150 100 1)"
if echo "$OUT4" | grep -qx '198.18.0.5' && [[ "$(cat "$T4/198.18.0.9" 2>/dev/null)" == "150" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: no-prune still unions within-window store IP and refreshes current-tick ts"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: no-prune must still record (refresh ts) and union within-window store IPs"
fi

# (e) readback re-filter: a non-dotted-quad store file never reaches the set.
T5="$(mktemp -d)"; echo "100" > "$T5/not-an-ip"; echo "100" > "$T5/1.2.3.4"
OUT5="$(printf '10.0.0.1\n' | retention_build "$T5" 150 100 0)"
if echo "$OUT5" | grep -qx '1.2.3.4' && ! echo "$OUT5" | grep -q 'not-an-ip'; then
  PASS=$((PASS + 1)); echo "  PASS: non-IPv4 store filename re-filtered out of the batch"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: non-IPv4 store filename must be re-filtered out"
fi
# (f) boundary: age == GRACE_WINDOW exactly is RETAINED (pins `<=`, not `<`).
T6="$(mktemp -d)"; echo "100" > "$T6/192.0.2.50"
OUT6="$(printf '10.0.0.1\n' | retention_build "$T6" 200 100 0)"   # age = 200-100 = 100 == window
if echo "$OUT6" | grep -qx '192.0.2.50'; then
  PASS=$((PASS + 1)); echo "  PASS: IP at exactly age==window is retained (inclusive boundary, <= not <)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: IP at age==window must be retained (a <=→< regression would drop it)"
fi
rm -rf "$T1" "$T2" "$T3" "$T4" "$T5" "$T6"

echo "-- unit invariants --"
assert_grep "firewall unit alarms on failure" 'OnFailure=cron-egress-alarm@%n\.service' "$SCRIPT_DIR/cron-egress-firewall.service"
assert_grep "resolve unit alarms on failure" 'OnFailure=cron-egress-alarm@%n\.service' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "firewall unit re-asserts every boot" 'WantedBy=multi-user\.target' "$SCRIPT_DIR/cron-egress-firewall.service"
assert_grep "timer survives reboots (Persistent)" 'Persistent=true' "$SCRIPT_DIR/cron-egress-resolve.timer"
assert_grep "resolve runs doppler-wrapped (env for Sentry + dynamic hosts)" 'run --project soleur --config prd' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "resolve unit sources the doppler token env file" 'EnvironmentFile=-/etc/default/inngest-server' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "resolve unit sets HOME (doppler os.UserHomeDir requirement)" 'Environment=HOME=/root' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "resolve unit bounded (no infinite activating hang)" 'TimeoutStartSec=' "$SCRIPT_DIR/cron-egress-resolve.service"
# Grace-window retention store must persist across reboots (a tmpfs /run would
# wipe the accumulated rotation pool and re-open the outage for up to a window).
# StateDirectory= creates /var/lib/cron-egress-resolve (root-owned) before ExecStart.
assert_grep "resolve unit declares persistent StateDirectory for the retention store" 'StateDirectory=cron-egress-resolve' "$SCRIPT_DIR/cron-egress-resolve.service"

echo "-- cross-file literal parity (replicated literals drift silently) --"
SLUG_RESOLVE="$(grep -oE 'SENTRY_SLUG="[^"]+"' "$RESOLVER" | head -1)"
SLUG_ALARM="$(grep -oE 'SENTRY_SLUG="[^"]+"' "$ALARM" | head -1)"
if [[ -n "$SLUG_RESOLVE" && "$SLUG_RESOLVE" == "$SLUG_ALARM" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: SENTRY_SLUG identical in resolver + alarm ($SLUG_RESOLVE)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: SENTRY_SLUG drift (resolver=$SLUG_RESOLVE alarm=$SLUG_ALARM)"
fi
SLUG_VAL="$(echo "$SLUG_RESOLVE" | sed -E 's/SENTRY_SLUG="([^"]+)"/\1/')"
assert_grep "Sentry monitor name matches the scripts' slug" "name += +\"$SLUG_VAL\"" "$SCRIPT_DIR/sentry/cron-monitors.tf"
# Drop-prefix parity: the resolver's journal grep must match the loader's
# nft log prefixes, else drops keep happening while the alert goes dark.
for prefix in 'egress-blocked: ' 'egress-dns-exfil: '; do
  if grep -qF "$prefix" "$LOADER" && grep -qE "egress-.blocked.dns-exfil.: " "$RESOLVER"; then
    PASS=$((PASS + 1)); echo "  PASS: drop prefix '$prefix' present in loader and covered by resolver grep"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: drop prefix '$prefix' parity broken between loader and resolver"
  fi
done

echo "-- alarm content invariants --"
assert_grep "alarm posts Sentry error check-in" 'status=error' "$ALARM"
assert_grep "alarm emails via Resend (disk-monitor precedent)" 'api\.resend\.com/emails' "$ALARM"
assert_grep "alarm email cooldown (no per-tick inbox storm)" 'EMAIL_COOLDOWN_SECS' "$ALARM"

echo "-- allowlist completeness (grep-enumerated runtime hosts) --"
for host in api.anthropic.com github.com api.github.com api.doppler.com \
  edge.api.flagsmith.com api.x.com api.linkedin.com bsky.social discord.com \
  plausible.io api.resend.com api.buttondown.com api.cloudflare.com \
  api.stripe.com api.hetzner.cloud fcm.googleapis.com \
  updates.push.services.mozilla.com web.push.apple.com \
  soleur.ai app.soleur.ai api.soleur.ai api.supabase.com; do
  # -Fxq = exact full-line literal (dots are NOT wildcards)
  if grep -Fxq -- "$host" "$ALLOWLIST"; then
    PASS=$((PASS + 1)); echo "  PASS: allowlists $host"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: allowlists $host (exact line not found)"
  fi
done
# Exact-set guard: a NEW host (the firewall's entire attack-surface dial)
# must force a deliberate edit here carrying its evidence.
# Count is 23 since #5199 (restore 7 Tier-2 crons) grew the allowlist with
# evidence-gated hosts (e.g. hn.algolia.com, plausible.io) but did not bump
# this guard — drift fixed here. The CIDR ranges live in a SEPARATE interval
# set/file (cron-egress-allowlist-cidr.txt) and are NOT counted here.
HOST_COUNT="$(grep -vcE '^[[:space:]]*#|^[[:space:]]*$' "$ALLOWLIST")"
if [[ "$HOST_COUNT" -eq 23 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: allowlist host count is exactly 23"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: allowlist host count is $HOST_COUNT (expected 23 — update BOTH the allowlist and this test with evidence)"
fi
assert_not_grep "Better Stack is HOST egress (must not be in the container allowlist)" '^(logs\.)?(betterstack|betteruptime)' "$ALLOWLIST"
assert_not_grep "GHCR is HOST egress (must not be in the container allowlist)" '^ghcr\.io$' "$ALLOWLIST"

echo "-- cloud-init fresh-host mirror --"
assert_grep "cloud-init writes the loader" '/usr/local/bin/cron-egress-nftables\.sh' "$CLOUD_INIT"
assert_grep "cloud-init writes the resolver" '/usr/local/bin/cron-egress-resolve\.sh' "$CLOUD_INIT"
assert_grep "cloud-init writes the post-apply assert script" '/usr/local/bin/cron-egress-postapply-assert\.sh' "$CLOUD_INIT"
assert_grep "cloud-init writes the allowlist" '/etc/soleur/cron-egress-allowlist\.txt' "$CLOUD_INIT"
assert_grep "cloud-init enables the firewall unit" 'systemctl enable --now cron-egress-firewall\.service' "$CLOUD_INIT"
assert_grep "cloud-init enables the resolve timer" 'systemctl enable --now cron-egress-resolve\.timer' "$CLOUD_INIT"
assert_grep "cloud-init installs nftables" '^ *- nftables$' "$CLOUD_INIT"

echo "-- Phase 2.1: assertion-block self-reporting sentinels (#5279) --"
# The post-apply assertion block (server.tf, the 2nd remote-exec) runs under
# `set -e` with terraform's inline stdout SUPPRESSED — so a bare failing
# assertion exits 1 with NO indication of WHICH check failed (the root reason
# #5247 took 3 PRs to chase a one-line format mismatch nobody could see). Every
# assertion MUST self-report via a unique `ASSERT-FAILED: <name>` sentinel
# echoed BEFORE `exit 1`, so terraform's captured-on-error output names the
# culprit even with stdout suppressed (no SSH; hr-no-ssh-fallback-in-runbooks).
# Block = from the `chmod +x` line through `echo host-egress-ok`. The block now
# lives in its own delivered script (#5289 — folded into config_hash so edits
# re-provision); the awk markers are unchanged, only the source file moved from
# $SERVER_TF to the script.
ASSERT_BLOCK="$(awk '
  /chmod \+x \/usr\/local\/bin\/cron-egress-nftables\.sh/ { grab=1 }
  grab { print }
  /echo host-egress-ok/ { grab=0 }
' "$ASSERT_SCRIPT")"

SENTINEL_COUNT="$(echo "$ASSERT_BLOCK" | grep -cE 'ASSERT-FAILED:')"
if [[ "$SENTINEL_COUNT" -ge 15 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: assertion block carries $SENTINEL_COUNT ASSERT-FAILED sentinels (>=15)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: only $SENTINEL_COUNT ASSERT-FAILED sentinels in the assertion block (expected >=15 — every assertion must self-report)"
fi

# No bare command may remain: EVERY executable line in the block (chmod, every
# systemctl verb, nft-list, docker-network, leading-`curl`) must carry a
# sentinel guard. The command-detection regex covers the setup lines too
# (chmod / daemon-reload / enable / restart) — without that, those sentinels
# could be silently stripped while the floor's slack masked the count drop
# (PR #5280 review P2). The `echo host-egress-ok` success marker and the
# `if docker ps … fi` probe line (which carries its own two sentinels) are
# intentionally not command-shaped here. The leading-`curl` arm anchors on the
# bare script form (`^curl`, #5289 — no HCL quote now the block is a real .sh).
UNGUARDED="$(echo "$ASSERT_BLOCK" | grep -nE '(chmod \+x|systemctl (daemon-reload|enable|restart|is-active)|nft list|docker network inspect|^[[:space:]]*curl )' | grep -v 'ASSERT-FAILED' || true)"
if [[ -z "$UNGUARDED" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: no bare (sentinel-less) command remains in the block"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: unguarded command(s) without ASSERT-FAILED sentinel:"; echo "$UNGUARDED"
fi

# The service-RESTART sentinel (the LEAD failure 4c — `restart` re-runs the
# Type=oneshot loader and propagates its `die`) must ALSO surface the loader's
# journalctl tail, so the next apply names the loader `die` directly in the
# Actions log (no SSH). `enable` (symlink only) does not run the loader.
if echo "$ASSERT_BLOCK" | grep -qE 'ASSERT-FAILED: firewall-restart' \
  && echo "$ASSERT_BLOCK" | grep -q 'journalctl -u cron-egress-firewall.service'; then
  PASS=$((PASS + 1)); echo "  PASS: firewall-restart sentinel surfaces journalctl tail"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: firewall-restart sentinel must surface 'journalctl -u cron-egress-firewall.service'"
fi

# Protected-invariant sentinels (plan AC3/AC4 set) — each load-bearing
# containment check names itself distinctly so the failing one is unambiguous.
for sentinel in docker-user-jump default-drop bridge-ipv6 egress-probe-negative egress-probe-positive; do
  if echo "$ASSERT_BLOCK" | grep -qE "ASSERT-FAILED: $sentinel"; then
    PASS=$((PASS + 1)); echo "  PASS: sentinel present for $sentinel"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: missing ASSERT-FAILED sentinel for $sentinel"
  fi
done

# Runbook parity (PR #5280 review P2): every sentinel NAME in the block must be
# documented in the cron-egress-blocked runbook, so a rename in server.tf that
# leaves the runbook stale fails the build instead of silently desyncing the
# operator's no-SSH diagnosis table. Names are extracted from the block; the
# trailing parenthetical detail (e.g. "firewall-restart (loader die …)") is
# stripped so only the bare name is matched.
RUNBOOK="$SCRIPT_DIR/../../../knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md"
SENTINEL_NAMES="$(echo "$ASSERT_BLOCK" | grep -oE "ASSERT-FAILED: [a-z0-9-]+" | sed -E 's/ASSERT-FAILED: //' | sort -u)"
if [[ -f "$RUNBOOK" ]]; then
  MISSING_RUNBOOK=""
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    grep -qF -- "$name" "$RUNBOOK" || MISSING_RUNBOOK+="$name "
  done <<< "$SENTINEL_NAMES"
  if [[ -z "$MISSING_RUNBOOK" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: every sentinel name is documented in cron-egress-blocked.md"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: sentinel name(s) absent from cron-egress-blocked.md (runbook drift): $MISSING_RUNBOOK"
  fi
else
  FAIL=$((FAIL + 1)); echo "  FAIL: runbook not found at $RUNBOOK"
fi

# Behavioral non-vacuity: the sentinel pattern under `set -e` must emit the
# sentinel AND halt (not fall through). Proves the guard actually fires rather
# than being decorative.
SENTINEL_OUT="$(bash -c 'set -e; false || { echo "ASSERT-FAILED: probe"; exit 1; }; echo SHOULD-NOT-REACH' 2>&1 || true)"
if echo "$SENTINEL_OUT" | grep -qF 'ASSERT-FAILED: probe' && ! echo "$SENTINEL_OUT" | grep -qF 'SHOULD-NOT-REACH'; then
  PASS=$((PASS + 1)); echo "  PASS: sentinel pattern emits name and halts under set -e (non-vacuous)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: sentinel pattern did not emit+halt as expected (got: $SENTINEL_OUT)"
fi

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
