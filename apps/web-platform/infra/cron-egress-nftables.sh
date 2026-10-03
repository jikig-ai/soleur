#!/usr/bin/env bash
# cron-egress-nftables.sh — install the DOCKER-USER container egress firewall
# (#5046 PR-2 / cron-egress-firewall).
#
# Default-drop egress allowlist for the soleur-web-platform container (and its
# canary) on the default Docker bridge. Contains the 4 live spawn("bash")
# crons that bypass the #5018 PreToolUse hook (ADR-033 I7) and makes the
# hook's Task/Skill relax-minimal safe: a compromised cron can no longer dial
# an arbitrary host — only the grep-enumerated allowlist resolves.
#
# Design (plan §Phase 2.B, arch-confirmed):
#   - All soleur rules live in OUR OWN chain `SOLEUR-EGRESS` (table ip filter);
#     DOCKER-USER carries exactly ONE rule: `iifname "docker0" jump
#     SOLEUR-EGRESS`. Re-asserting = atomically flush+repopulate OUR chain —
#     never surgical handle math in, nor a flush of, the shared DOCKER-USER
#     chain (Docker never flushes DOCKER-USER, so the jump survives dockerd
#     restarts; a REBOOT clears nftables entirely, which is why the
#     cron-egress-firewall.service oneshot re-runs this script every boot).
#   - Container→HOST traffic (host-gateway Inngest :8288) traverses INPUT,
#     not FORWARD/DOCKER-USER — the explicit :8288 accept below is
#     belt-and-braces, not load-bearing. Host OUTPUT (cloudflared tunnel,
#     Vector→Better Stack, GHCR, apt) is never touched.
#   - ORDER MATTERS (availability): the allowlist sets are POPULATED (via
#     cron-egress-resolve.sh) BEFORE the default-drop rules install. If
#     resolution fails, this script aborts WITHOUT installing the drop —
#     fail-open-on-bootstrap is deliberate (app availability > containment;
#     the unit's OnFailure= alarm pages the operator).
set -euo pipefail

BRIDGE_IF="docker0"
LOG_TAG="cron-egress-nftables"
RESOLVE_SCRIPT="${RESOLVE_SCRIPT:-/usr/local/bin/cron-egress-resolve.sh}"

log() { echo "[$LOG_TAG] $*"; }
die() { log "ERROR: $*"; exit 1; }

command -v nft >/dev/null || die "nft binary not found (apt-get install nftables)"
ip link show "$BRIDGE_IF" >/dev/null 2>&1 || die "bridge interface $BRIDGE_IF not found"

# IPv6 bypass guard: the rules below are IPv4 (table ip). If the default
# bridge ever enables IPv6, container egress could bypass the allowlist over
# v6 — fail loudly rather than silently half-contain.
if command -v docker >/dev/null && docker network inspect bridge >/dev/null 2>&1; then
  V6="$(docker network inspect bridge -f '{{.EnableIPv6}}' 2>/dev/null || echo unknown)"
  [[ "$V6" == "false" ]] || die "default bridge EnableIPv6=$V6 — IPv6 egress would bypass the v4 allowlist"
fi

# Host-gateway address for the explicit Inngest :8288 accept. Derived, never
# hardcoded (a daemon.json bip/default-address-pools change shifts it).
BRIDGE_GW="$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
[[ -n "$BRIDGE_GW" ]] || BRIDGE_GW="172.17.0.1"

# Static CIDR allowlist for hosts that LB git/web traffic across a rotating IP
# pool the per-tick single-IP resolver cannot cover (GitHub git ranges). These
# are populated into an INTERVAL set (type ipv4_addr + flags interval) — the
# dynamic single-IP set (soleur_egress_allow) is left untouched. See
# cron-egress-allowlist-cidr.txt. Empty/missing file → empty set (no effect).
CIDR_FILE="${CIDR_FILE:-/etc/soleur/cron-egress-allowlist-cidr.txt}"
CIDR_ELEMENTS=""

# Strict IPv4-CIDR validator. $CIDR_ELEMENTS is interpolated VERBATIM into the
# `add element ... { $CIDR_ELEMENTS }` nft heredoc below, so any non-comment line
# containing `}`, an nft keyword, whitespace, a newline, or command-substitution
# would be injected into the ruleset (e.g. `0.0.0.0/0` silently allow-all, or
# `}; add rule ... accept`). This gate rejects that surface AND range-checks octets
# (<= 255) / prefix (<= 32) so a malformed allowlist fails loud rather than
# half-installing the firewall. The CIDR file is repo-controlled config — a bad
# line means the committed file is wrong → reject-whole-file (vs. the resolver's
# filter-and-drop, which is correct for untrusted DNS input; see plan precedent-diff).
#
# LINK-LOCAL (#9378): the instance-metadata endpoint 169.254.169.254 serves cloud-init user_data (a
# Doppler read token), so NO CIDR whose range overlaps 169.254.0.0/16 may become an element — not only
# the spellings someone thought of: 0.0.0.0/0, 128.0.0.0/1, 160.0.0.0/3, 169.0.0.0/8 and
# 169.254.0.0/15 all cover it. Decided by RANGE ARITHMETIC on the numeric range, never prefix matching.
# The loader's Phase 3 also carries a literal link-local drop ahead of every accept, so the invariant
# does not rest on this validator alone.
LL_LO=$((0xA9FE0000))  # 169.254.0.0
LL_HI=$((0xA9FEFFFF))  # 169.254.255.255
is_valid_ipv4_cidr() {
  local cidr="$1" prefix o1 o2 o3 o4 part ip size lo hi
  [[ "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]] || return 1
  o1=${BASH_REMATCH[1]}; o2=${BASH_REMATCH[2]}; o3=${BASH_REMATCH[3]}
  o4=${BASH_REMATCH[4]}; prefix=${BASH_REMATCH[5]}
  # A leading zero (010, 08) is refused outright: bash arithmetic would read it as OCTAL (010 == 8),
  # so the range check below would be computed on a different number than nft parses.
  for part in "$o1" "$o2" "$o3" "$o4" "$prefix"; do
    [[ "$part" =~ ^0[0-9] ]] && return 1
  done
  # Range-check the (leading-zero-free) octets and prefix; any value out of range REJECTS the line.
  (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32 )) || return 1
  ip=$(( (10#$o1 << 24) | (10#$o2 << 16) | (10#$o3 << 8) | 10#$o4 ))
  size=$(( 1 << (32 - 10#$prefix) ))
  # Align down to the network address: nft masks host bits when it stores an interval element (169.255.0.0/15 is
  # stored as 169.254.0.0/15), so the overlap test must run on the MASKED range, not on the literal address.
  lo=$(( ip / size * size )); hi=$(( lo + size - 1 ))
  (( hi < LL_LO || lo > LL_HI )) || return 1
  return 0
}

if [[ -f "$CIDR_FILE" ]]; then
  # `read -r` retains a trailing \r, so a CRLF-saved file fails the $-anchored regex
  # and the whole file is rejected (fail-loud) — intentional: the old paste-build
  # silently injected the \r into the nft heredoc. `|| [[ -n "$line" ]]` keeps the
  # final line when the file has no trailing newline.
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    is_valid_ipv4_cidr "$line" \
      || die "invalid CIDR in $CIDR_FILE: '$line' (reject-whole-file; refusing to build nft elements)"
    CIDR_ELEMENTS+="${CIDR_ELEMENTS:+,}$line"
  done < "$CIDR_FILE"
fi

# --- Phase 1: declare table/sets/chains (additive, idempotent) -----------------
# `nft -f` table declarations MERGE into existing state — safe to re-run.
# DOCKER-USER is declared too so this works even before dockerd starts
# (Docker reuses an existing chain; it never flushes DOCKER-USER).
nft -f - <<EOF
table ip filter {
  set soleur_egress_allow {
    type ipv4_addr
  }
  set soleur_egress_allow_cidr {
    type ipv4_addr
    flags interval
  }
  set soleur_egress_dns {
    type ipv4_addr
  }
  chain SOLEUR-EGRESS {
  }
  chain DOCKER-USER {
  }
}
EOF

# --- Phase 1.5: populate the static CIDR set (atomic flush+repopulate) ----------
# Unlike the dynamic single-IP set (whose flush would open an empty-drop window
# mid-tick), this set is STATIC, so an atomic one-transaction flush+add is safe
# and idempotent across loader re-runs (avoids "element already exists" on the
# interval set). Skipped when the file is empty/absent.
if [[ -n "$CIDR_ELEMENTS" ]]; then
  nft -f - <<EOF
flush set ip filter soleur_egress_allow_cidr
add element ip filter soleur_egress_allow_cidr { $CIDR_ELEMENTS }
EOF
fi

# --- Phase 2: populate the sets BEFORE any drop rule exists --------------------
# CRON_EGRESS_FROM_LOADER=1 suppresses the resolver's enforcement self-heal
# (the rules are legitimately absent at this point — that's the availability
# ordering, not drift) so loader→resolver→loader cannot recurse.
CRON_EGRESS_FROM_LOADER=1 "$RESOLVE_SCRIPT" || die "allowlist resolution failed — NOT installing default-drop (fail-open bootstrap; OnFailure alarms)"

# --- Phase 3: (re)install our rules atomically ----------------------------------
# One transaction: flush OUR chain + add the ordered rules. First-match-wins,
# drop LAST. Everything in this chain arrived via the iifname-scoped jump, so
# per-rule iifname repeats are unnecessary. The link-local drop (instance metadata,
# #9378) is the FIRST DROP/ACCEPT-class rule, ahead of every accept: no set element or
# later rule can admit 169.254.0.0/16. It is NOT silent: a rate-limited log rule for the
# same range, with the SAME `egress-blocked: ` prefix as the default-drop log, sits
# immediately BEFORE it so a container probing the metadata endpoint still reaches the
# egress_blocked page (cron-egress-resolve.sh counts that prefix). The log is a separate
# rule from the drop (never limit+log+drop in one rule): a `limit` that is exceeded makes
# the rule fall through, and the unconditional drop right after still drops every packet.
nft -f - <<EOF
flush chain ip filter SOLEUR-EGRESS
add rule ip filter SOLEUR-EGRESS ip daddr 169.254.0.0/16 limit rate 6/minute burst 10 packets log prefix "egress-blocked: " level notice comment "soleur-egress: link-local (instance metadata) probe log"
add rule ip filter SOLEUR-EGRESS ip daddr 169.254.0.0/16 counter drop comment "soleur-egress: link-local (instance metadata) drop"
add rule ip filter SOLEUR-EGRESS ct state established,related accept comment "soleur-egress: return traffic"
add rule ip filter SOLEUR-EGRESS oifname "$BRIDGE_IF" accept comment "soleur-egress: intra-bridge (canary<->app)"
add rule ip filter SOLEUR-EGRESS udp dport 53 ip daddr @soleur_egress_dns accept comment "soleur-egress: pinned DNS"
add rule ip filter SOLEUR-EGRESS tcp dport 53 ip daddr @soleur_egress_dns accept comment "soleur-egress: pinned DNS tcp"
add rule ip filter SOLEUR-EGRESS udp dport 53 limit rate 10/minute burst 50 packets log prefix "egress-dns-exfil: " comment "soleur-egress: dns exfil log"
add rule ip filter SOLEUR-EGRESS udp dport 53 counter drop comment "soleur-egress: dns exfil drop"
add rule ip filter SOLEUR-EGRESS tcp dport 53 limit rate 10/minute burst 50 packets log prefix "egress-dns-exfil: " comment "soleur-egress: dns exfil log tcp"
add rule ip filter SOLEUR-EGRESS tcp dport 53 counter drop comment "soleur-egress: dns exfil drop tcp"
add rule ip filter SOLEUR-EGRESS ip daddr $BRIDGE_GW tcp dport 8288 accept comment "soleur-egress: host-gateway inngest"
# 10.0.1.40 = inngest-host.tf:33 inngest_private_ip (bash literal, NOT injected from the
# Terraform local; if that IP changes, update this rule + inngest-registry-probe.sh +
# inngest-doublefire-probe.sh together). Dedicated Inngest host egress for the #6178 /
# ADR-100 cutover (INNGEST_BASE_URL repoint to http://10.0.1.40:8288, PR #6348).
add rule ip filter SOLEUR-EGRESS ip daddr 10.0.1.40 tcp dport 8288 accept comment "soleur-egress: dedicated inngest host (#6178)"
add rule ip filter SOLEUR-EGRESS ip daddr @soleur_egress_allow accept comment "soleur-egress: allowlist"
add rule ip filter SOLEUR-EGRESS ip daddr @soleur_egress_allow_cidr accept comment "soleur-egress: cidr allowlist (github git LB ranges)"
add rule ip filter SOLEUR-EGRESS limit rate 10/minute burst 50 packets log prefix "egress-blocked: " level notice comment "soleur-egress: default drop log"
add rule ip filter SOLEUR-EGRESS counter drop comment "soleur-egress: default drop"
EOF

# --- Phase 4: ensure the single DOCKER-USER jump exists -------------------------
# Capture-then-match, not `nft list | grep -q` under pipefail (#9392): a grep -q early exit
# (SIGPIPE, status 141) or a failed nft read looks like "no jump" and used to insert a DUPLICATE
# rule on every self-heal re-run. An unreadable chain is retried once; if it stays unreadable
# the jump is inserted anyway and a WARN names the read failure: a duplicate jump is inert (the
# chain ends in an unconditional drop), a missing jump leaves egress open until the next tick,
# so this fails toward enforcement. The jump is matched by its target token, so a rule
# naming `SOLEUR-EGRESS-OLD` does not count.
jump_re='jump[[:space:]]+SOLEUR-EGRESS([[:space:]]|$)'
retry_sleep="${NFT_RETRY_SLEEP:-1}"
[[ "$retry_sleep" =~ ^[0-9]+$ ]] || retry_sleep=1
jump_rc=0; docker_user_rules="$(nft list chain ip filter DOCKER-USER 2>/dev/null)" || jump_rc=$?
if (( jump_rc != 0 )); then
  sleep "$retry_sleep"
  jump_rc=0; docker_user_rules="$(nft list chain ip filter DOCKER-USER 2>/dev/null)" || jump_rc=$?
fi
if (( jump_rc != 0 )); then
  log "WARN: cannot read the DOCKER-USER chain (nft rc=$jump_rc): inserting the jump anyway (a duplicate is inert, a missing jump is not)"
  docker_user_rules=""
fi
if [[ ! "$docker_user_rules" =~ $jump_re ]]; then
  nft insert rule ip filter DOCKER-USER iifname "$BRIDGE_IF" counter jump SOLEUR-EGRESS comment '"soleur-egress: jump"'
  log "installed DOCKER-USER jump rule"
fi

log "OK: SOLEUR-EGRESS active (bridge=$BRIDGE_IF gw=$BRIDGE_GW)"
