#!/usr/bin/env bash
# Exit-code + branch harness for zot-last-err-redact-7500.sh (#7500 delivery watch, tracker #7960).
#
# WHY THIS FILE EXISTS. The probe grades a MIXED-BOOT window for the first time on the one run
# that matters: the sweep immediately after a registry-host-replace. Nothing exercised that shape
# until 2026-09-17, and the probe got it wrong in the FAIL direction.
#
# WHAT THE FIRST REVISION OF THIS HARNESS GOT WRONG, recorded because the lesson is the file's
# whole value. It asserted EXIT CODES ONLY, against a probe with six distinct `exit 2` sites, so
# four of its six cases collapsed onto one integer. Measured consequences:
#   * deleting the no-boot_id guard — the named subject of one case — left the suite 6/0 green,
#     because the fixture then fell into Guard 1 and still produced a 2;
#   * deleting the trusted-region tail cut — the named subject of another — left the suite 6/0
#     green WHILE THE FORGE SUCCEEDED, the probe printing the forged boot_id;
#   * replacing `got="$(run_probe …)"` with `got="$want"` left the suite 6/0 green with the probe
#     never executed at all. One command substitution was the suite's only link to its subject.
# So every case now pins a BRANCH MARKER as well as the code, and `expect` asserts the probe ran.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): the envelope and field order mirror
# the producer's `LINE=` emitter and betterstack-query.sh's documented double-encoded `raw`;
# every uuid and sample string is fabricated.
#
# DELIVERY PROOF (#7960). The probe keys delivery on `err_redact_rev`, a field the producer emits
# on every row. The token is read FROM THE PRODUCER'S `LINE=` assignment below, never restated,
# so a producer rename reddens this suite before any case runs and a producer value of `0`
# reddens the field-keyed PASS case.
#
# KNOWN GAP, stated rather than left implicit: the probe scopes on boot_id and never reads
# `host=`. Two hosts POSTing this marker to the shared source would both satisfy the envelope
# anchor, so a second host's row could supply the "newest boot". Single-host by ADR-096; re-open
# this if a second host ever POSTs this marker to source 2457081.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SRC="$HERE/zot-last-err-redact-7500.sh"
[[ -f "$PROBE_SRC" ]] || { echo "FATAL: probe not found at $PROBE_SRC" >&2; exit 1; }

# The delivery-proof token, read from the producer. Loose on purpose (`[^ "]+`, not `[1-9]…`): a
# producer value of `0` must REACH the fixtures and redden the field-keyed PASS case, not die here.
PRODUCER="$HERE/../../apps/web-platform/infra/cloud-init-registry.yml"
TOKEN="$(grep -F 'LINE="SOLEUR_ZOT_DISK' "$PRODUCER" 2>/dev/null | head -1 | grep -oE 'err_redact_rev=[^ "]+' || true)"
if [[ -z "$TOKEN" ]]; then
  printf 'FATAL: could not read the err_redact_rev token from the producer LINE= at %s -- every field-keyed case would be vacuous.\n' "$PRODUCER" >&2
  exit 1
fi
OLDBOOT="4b8e0d27-31c6-4f5a-a2d9-60e7c1f3b8aa"   # fabricated pre-delivery boot
NEWBOOT="9f2c41d6-5b7a-4e08-9c31-7ad0e2b41f55"   # fabricated post-replace boot
OTHER="1c3e55aa-77bb-4d21-8e90-3f0a1b2c4d5e"     # a second fabricated boot

fails=0
passes=0
# Incremented at the CALL SITE, never inside pass()/fail(). Verified insufficient on its own —
# see the positive control at the bottom, which drives both helpers and both counters.
cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── fixture builders ───────────────────────────────────────────────────────────────────────
# PRODUCTION SHAPE. betterstack-query.sh's header documents `raw` as DOUBLE-encoded, and the
# probe's envelope anchor greps the literal `"raw":"{\"message\":\"SOLEUR_ZOT_DISK `. A flat
# `{"raw":"SOLEUR_ZOT_DISK …"}` fixture — what the first revision used — cannot exercise the
# anchor at all, and pins a single-hop decoder the dependency's own contract contradicts.
# Field order mirrors the producer: zot_last_err_src [err_redact_rev] … boot_id … host …
# zot_last_err LAST.
rowt() { # <dt> <boot_id> <src> <proof-token or ""> <tail>
  local tok=""; [[ -n "$4" ]] && tok=" $4"
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 zot_last_err_src=%s%s boot_id=%s host=soleur-registry zot_last_err=%s\\"}"}\n' \
    "$1" "$3" "$tok" "$2" "$5"
}
row()  { rowt "$1" "$2" "$3" "" "$4"; }         # a PRE-field producer's row
rowf() { rowt "$1" "$2" "$3" "$TOKEN" "$4"; }   # a post-#7960 producer's row
# A row that merely QUOTES the marker — a Vector-shipped journald envelope, the measured 2026-07-15
# contamination shape. It carries the proof token because the producer's OWN journald echo of an
# egress failure (`[zot] SOLEUR_ZOT_DISK egress … FAILED: $LINE`) will. Must never select the boot
# or supply evidence — only the envelope anchor keeps it out.
foreign() { # <dt> <boot_id>
  printf '{"dt":"%s","raw":"{\\"PRIORITY\\":\\"6\\",\\"_HOSTNAME\\":\\"soleur-web-1\\",\\"message\\":\\"[zot] SOLEUR_ZOT_DISK egress FAILED: zot_last_err_src=fallback %s boot_id=%s zot_last_err=none CANARY7960\\"}"}\n' \
    "$1" "$TOKEN" "$2"
}
# The SECONDARY proof: a `suppressed` row, emitted only by the Phase B gate (96f5b6eb5), with NO
# err_redact_rev — so it proves delivery on its own. Its tail is `none`, exactly as the producer
# writes it (an emptied sample becomes ZOT_LAST_ERR=none with the `suppressed` tag kept); any other
# tail on a `suppressed` row is graded as a leak.
proof() { row "$1" "$2" suppressed none; }
# CANARY. Every non-`suppressed` tail carries CANARY7960 and expect() fails any case whose output
# contains it: nothing the probe prints on the PUBLIC issue may echo row content.
CLEAN_TAIL='level:info HTTP API request served in 3ms CANARY7960'
COOKIE_TAIL='level:info HTTP API {headers:{Cookie:abc123}} served CANARY7960'
CLIENTIP_TAIL='level:info HTTP API served clientIP:10.0.1.9 CANARY7960'

run_probe() { # <fixture-file> -> echoes exit code; combined output in $WORK/out
  local fixture="$1" root="$WORK/root"
  rm -rf "$root"; mkdir -p "$root/scripts/followthroughs" "$root/scripts/lib"
  cp "$PROBE_SRC" "$root/scripts/followthroughs/"
  cp "$HERE/../lib/zot-telemetry-parse.sh" "$root/scripts/lib/"
  cat > "$root/scripts/betterstack-query.sh" <<STUB
#!/usr/bin/env bash
argv="\$*"
# Assert the probe's query CONSTRUCTION, by value where a value is load-bearing. Presence-only
# assertions let \`--limit 1\` and a hardcoded \`--since 1h\` both pass silently.
case "\$argv" in
  *"--since 24h"*) : ;;
  *) echo "STUB: expected --since 24h, got: \$argv" >&2; exit 64 ;;
esac
case "\$argv" in
  *"--grep SOLEUR_ZOT_DISK"*) : ;;
  *) echo "STUB: probe dropped the SOLEUR_ZOT_DISK grep (argv: \$argv)" >&2; exit 64 ;;
esac
# --limit must be explicit and large. The default is 100, which silently reads ~8h of a 24h
# window while every message says 24h.
lim="\$(printf '%s\n' "\$argv" | sed -n 's/.*--limit \([0-9]*\).*/\1/p')"
if [[ -z "\$lim" || "\$lim" -lt 1000 ]]; then
  echo "STUB: probe must pass an explicit --limit >= 1000, got '\$lim' (argv: \$argv)" >&2; exit 64
fi
[[ "\${STUB_RC:-0}" == "0" ]] || exit "\${STUB_RC}"
cat "$fixture"
STUB
  chmod +x "$root/scripts/betterstack-query.sh"
  # env -u mirrors the `env -i` the sweeper runs probes under.
  env -u SOLEUR_FT_WINDOW -u SOLEUR_FT_LIMIT \
    BETTERSTACK_QUERY_HOST=stub \
    BETTERSTACK_QUERY_USERNAME=stub \
    BETTERSTACK_QUERY_PASSWORD=stub \
    bash "$root/scripts/followthroughs/zot-last-err-redact-7500.sh" >"$WORK/out" 2>&1
  echo $?
}

expect() { # <name> <expected-rc> <fixture-file> <branch-marker>
  cases=$((cases + 1))
  local name="$1" want="$2" fixture="$3" marker="$4" got ok=1
  got="$(run_probe "$fixture")"
  # The probe MUST have run. Without this, `got="$want"` passes every case with the subject never
  # executed — measured on the first revision of this file.
  [[ -s "$WORK/out" ]] || { fail "$name — probe produced NO output; did it run?"; return; }
  [[ "$got" == "$want" ]] || ok=0
  grep -qF -- "$marker" "$WORK/out" || ok=0
  if grep -qF CANARY7960 "$WORK/out"; then
    fail "$name — the probe ECHOED ROW CONTENT (CANARY7960) into its output; the public issue must get counts only"
    return
  fi
  if (( ok )); then
    pass "$name (exit $got, branch: ${marker:0:46})"
  else
    fail "$name — expected exit $want + marker '${marker:0:46}', got exit $got"
    sed 's/^/        | /' "$WORK/out" >&2
  fi
}

# ── Case 1: THE LIVE SHAPE. Replace landed mid-window; old boot leaks, new boot clean. ─────
# Proven by the SECONDARY key alone (a `suppressed` row, no err_redact_rev anywhere).
{
  row "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  row "2026-09-17 10:05:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  row   "2026-09-17 12:00:00" "$NEWBOOT" fallback "$CLEAN_TAIL"
  proof "2026-09-17 12:05:00" "$NEWBOOT"
} > "$WORK/f1"
expect "mixed-boot window, proven by suppressed, delivered host clean -> PASS" 0 "$WORK/f1" "(proof: suppressed)"

# ── Case 2: the genuine red must survive the scoping. ──────────────────────────────────────
{
  row "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  row   "2026-09-17 12:00:00" "$NEWBOOT" fallback "$COOKIE_TAIL"
  proof "2026-09-17 12:05:00" "$NEWBOOT"
} > "$WORK/f2"
expect "delivered host STILL leaking -> FAIL" 1 "$WORK/f2" "STILL carry header content"

# ── Case 3: a new boot with NO proof and no tier-4 row is not "delivered". ─────────────────
{
  row "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  row "2026-09-17 12:00:00" "$NEWBOOT" regex    "$CLEAN_TAIL"
} > "$WORK/f3"
expect "new boot, no proof, no tier-4 -> CANNOT ESTABLISH" 3 "$WORK/f3" "lacks err_redact_rev"

# ── Case 3b: the same, but the new boot carries the field on a NON-tier-4 row. ─────────────
# The field is on EVERY row, so proof must be read across all newest-boot rows, not tier-4 only.
{
  row  "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  rowf "2026-09-17 12:00:00" "$NEWBOOT" regex    "$CLEAN_TAIL"
} > "$WORK/f3b"
expect "proven boot, no tier-4 yet -> NOT YET naming DELIVERY PROVEN" 2 "$WORK/f3b" "DELIVERY PROVEN"

# ── Case 4: an un-proven single boot still leaking is not a FAIL. ──────────────────────────
{
  row "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  row "2026-09-17 10:05:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
} > "$WORK/f4"
expect "un-proven host still leaking -> CANNOT ESTABLISH (not FAIL)" 3 "$WORK/f4" "lacks err_redact_rev"

# ── Case 5: boot_id=unknown is the /proc fallback, not an identity. ────────────────────────
# INVARIANT: the `unknown` row carries the token in its HEAD, in producer field order, and sorts
# NEWEST — so a probe that accepted `unknown` as a boot would reach a real false close (exit 0),
# not an accidental one.
{
  row  "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  rowf "2026-09-17 12:00:00" unknown    fallback "$CLEAN_TAIL"
} > "$WORK/f5"
# The marker pins the SELECTED BOOT, not R4's generic text: with only "lacks err_redact_rev" this
# case passed even when the unknown-exclusion was deleted, because the probe then fell to R4 for a
# different reason. Naming $OLDBOOT asserts the newest REAL boot was graded.
expect "boot_id=unknown is not a delivered identity -> not a PASS" 3 "$WORK/f5" "boot $OLDBOOT lacks err_redact_rev"

# ── Case 6: no boot_id at all -> CANNOT ESTABLISH (exit 3), never a pass, never NOT-YET. ───
printf '{"dt":"2026-09-17 10:00:00","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 zot_last_err_src=fallback host=soleur-registry zot_last_err=%s\\"}"}\n' "$CLEAN_TAIL" > "$WORK/f6"
expect "no boot_id anywhere -> CANNOT ESTABLISH" 3 "$WORK/f6" "CANNOT ESTABLISH: no usable boot_id"

# ── Case 7: a foreign row quoting the marker must not select the boot or supply evidence. ──
# INVARIANT: the foreign row carries the token in its head and sorts NEWEST, so dropping the
# envelope anchor would make it the whole evidence base and close the tracker (exit 0).
{
  row     "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  foreign "2026-09-17 12:00:00" "$OTHER"
} > "$WORK/f7"
expect "marker-quoting foreign row cannot close the tracker" 3 "$WORK/f7" "lacks err_redact_rev"

# ── Case 8: EVERY row is foreign -> no producer envelope at all. ───────────────────────────
foreign "2026-09-17 12:00:00" "$OTHER" > "$WORK/f8"
expect "no producer envelope in the window -> TRANSIENT" 2 "$WORK/f8" "NONE carries the"

# ── Case 9: the tier field cannot be spoofed from the untrusted tail. ──────────────────────
# A genuine tier-2 row on a PROVEN boot whose free text mentions the tier-4 token: a spoof would
# PASS (0), the correct reading is proven-but-ungraded (2).
{
  row  "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  rowf "2026-09-17 12:00:00" "$NEWBOOT" regex    "restart context: zot_last_err_src=fallback seen earlier CANARY7960"
} > "$WORK/f9"
expect "tier spoofed in the tail is not tier 4" 2 "$WORK/f9" "DELIVERY PROVEN"

# ── Case 10: a second ` zot_last_err=` must not truncate the leak out of the measurement. ──
{
  row   "2026-09-17 12:00:00" "$NEWBOOT" fallback "level:info {headers:{Cookie:secret}} gc failed for zot_last_err=ok CANARY7960"
  proof "2026-09-17 12:05:00" "$NEWBOOT"
} > "$WORK/f10"
expect "second zot_last_err= cannot hide a leak" 1 "$WORK/f10" "STILL carry header content"

# ── Case 11/12: each leak shape is pinned INDEPENDENTLY. ───────────────────────────────────
{ row "2026-09-17 12:00:00" "$NEWBOOT" fallback "$COOKIE_TAIL"; proof "2026-09-17 12:05:00" "$NEWBOOT"; } > "$WORK/f11"
expect "a header map alone is a leak" 1 "$WORK/f11" "STILL carry header content"
{ row "2026-09-17 12:00:00" "$NEWBOOT" fallback "$CLIENTIP_TAIL"; proof "2026-09-17 12:05:00" "$NEWBOOT"; } > "$WORK/f12"
expect "an address-valued clientIP alone is a leak" 1 "$WORK/f12" "STILL carry header content"

# ── Case 13: a suppressed row counts as "the subject ran" and cannot leak. ─────────────────
{
  row "2026-09-17 10:00:00" "$OLDBOOT" fallback   "$COOKIE_TAIL"
  row "2026-09-17 12:00:00" "$NEWBOOT"  suppressed none
} > "$WORK/f13"
expect "suppressed tier-4 row satisfies the subject guard -> PASS" 0 "$WORK/f13" "(proof: suppressed)"

# ── Case 14: a legitimate message mentioning 'headers' in prose is not a leak. ─────────────
{ row "2026-09-17 12:00:00" "$NEWBOOT" fallback "level:error cannot parse headers CANARY7960"; proof "2026-09-17 12:05:00" "$NEWBOOT"; } > "$WORK/f14"
expect "prose mentioning headers is not a leak" 0 "$WORK/f14" "PASS: producer delivered"

# ── Case 15: empty corpus is channel_dark, never clean. ────────────────────────────────────
: > "$WORK/f15"
expect "zero rows -> channel_dark, not a pass" 2 "$WORK/f15" "channel_dark"

# ── Case 16: ordering is not inherited from the query. ─────────────────────────────────────
# Emitted newest-first. Without the dt sort, tail -1 is the OLDEST row.
{
  proof "2026-09-17 12:05:00" "$NEWBOOT"
  row   "2026-09-17 12:00:00" "$NEWBOOT"  fallback "$CLEAN_TAIL"
  row   "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
} > "$WORK/f16"
expect "newest-first input still grades the newest boot" 0 "$WORK/f16" "(proof: suppressed)"

# ── Case 18/19: boot drift WITHOUT proof is not an authoritative verdict. ──────────────────
# A reboot of an un-replaced host flips boot_id with the OLD user_data in place.
{
  row "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  row "2026-09-17 12:00:00" "$NEWBOOT" fallback "$COOKIE_TAIL"
} > "$WORK/f18"
expect "drift without proof, leaking -> CANNOT ESTABLISH, not FAIL" 3 "$WORK/f18" "lacks err_redact_rev"
{
  row "2026-09-17 10:00:00" "$OLDBOOT" fallback "$COOKIE_TAIL"
  row "2026-09-17 12:00:00" "$NEWBOOT" fallback "$CLEAN_TAIL"
} > "$WORK/f19"
expect "drift without proof, clean -> CANNOT ESTABLISH, not PASS" 3 "$WORK/f19" "lacks err_redact_rev"

# ── Case 17: a non-zero query exit is not a clean window. ──────────────────────────────────
cases=$((cases + 1))
cp "$WORK/f1" "$WORK/f17"
if [[ "$(STUB_RC=7 run_probe "$WORK/f17")" == "2" ]] && grep -q 'channel_dark or auth failure' "$WORK/out" \
   && ! grep -qF CANARY7960 "$WORK/out"; then
  pass "query exit 7 -> TRANSIENT, not a pass"
else
  fail "query exit 7 -> expected TRANSIENT with the auth-failure branch"
  sed 's/^/        | /' "$WORK/out" >&2
fi

# ══ #7960: the field-keyed delivery proof ═════════════════════════════════════════════════

# N1 — the field alone proves delivery; no `suppressed` row anywhere.
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "$CLEAN_TAIL" > "$WORK/n1"
expect "N1 field + clean fallback, no suppressed -> PASS" 0 "$WORK/n1" "(proof: err_redact_rev)"

# N2 — the field alone makes a leak an authoritative FAIL.
{
  rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "$CLEAN_TAIL"
  rowf "2026-09-18 12:05:00" "$NEWBOOT" fallback "$COOKIE_TAIL"
} > "$WORK/n2"
expect "N2 field + a leaking fallback, no suppressed -> FAIL" 1 "$WORK/n2" "STILL carry header content"

# N4 — the field forged ONLY in the untrusted tail (after the row's own ` zot_last_err=`).
row "2026-09-18 12:00:00" "$NEWBOOT" fallback "$CLEAN_TAIL $TOKEN" > "$WORK/n4"
expect "N4 field forged in the tail is not proof" 3 "$WORK/n4" "lacks err_redact_rev"

# N5 — the field on an OLDER boot only; the newest boot lacks it.
{
  rowf "2026-09-18 10:00:00" "$OLDBOOT" fallback "$CLEAN_TAIL"
  row  "2026-09-18 12:00:00" "$NEWBOOT" fallback "$CLEAN_TAIL"
} > "$WORK/n5"
expect "N5 field on an older boot only is not proof for the newest" 3 "$WORK/n5" "lacks err_redact_rev"

# N7 — a revision of 0 is not a delivered gate.
rowt "2026-09-18 12:00:00" "$NEWBOOT" fallback "err_redact_rev=0" "$CLEAN_TAIL" > "$WORK/n7"
expect "N7 err_redact_rev=0 is not proof" 3 "$WORK/n7" "lacks err_redact_rev"

# N9 — must-PASS, non-canonical: the field on only the LAST newest-boot row.
{
  row  "2026-09-18 12:00:00" "$NEWBOOT" fallback "$CLEAN_TAIL"
  row  "2026-09-18 12:05:00" "$NEWBOOT" fallback "$CLEAN_TAIL"
  rowf "2026-09-18 12:10:00" "$NEWBOOT" fallback "$CLEAN_TAIL"
} > "$WORK/n9"
expect "N9 field on only the last newest-boot row -> PASS" 0 "$WORK/n9" "(proof: err_redact_rev)"

# N11 — prose that names `headers:` is not structure. Field-keyed proof makes exit 1 reachable
# on ordinary messages for the first time, so this must stay 0.
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:error invalid headers: malformed request CANARY7960" > "$WORK/n11"
expect "N11 prose 'invalid headers: …' is not a leak" 0 "$WORK/n11" "(proof: err_redact_rev)"

# N12 — a `suppressed` row must carry `none`; anything else is a gate regression.
rowf "2026-09-18 12:00:00" "$NEWBOOT" suppressed "{level:info,headers:{Cookie:[x]}} CANARY7960" > "$WORK/n12"
expect "N12 a suppressed row with a non-none tail is a leak" 1 "$WORK/n12" "STILL carry header content"

# Leak side — each pattern branch pinned independently.
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:info headers=map[Cookie:[x]] CANARY7960" > "$WORK/n13"
expect "N13 Go map rendering of headers is a leak" 1 "$WORK/n13" "STILL carry header content"
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:info clientIP:[fe80::1]:443 CANARY7960" > "$WORK/n14"
expect "N14 an IPv6 clientIP is a leak" 1 "$WORK/n14" "STILL carry header content"
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:info Headers:{Accept:[x]} CANARY7960" > "$WORK/n15"
expect "N15 the header map is matched case-insensitively" 1 "$WORK/n15" "STILL carry header content"
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:info Cookie:[abc] CANARY7960" > "$WORK/n16"
expect "N16 a bare credential header with no wrapper is a leak" 1 "$WORK/n16" "STILL carry header content"

# N20 — MUST-PASS, and the shape the delivered host actually emits. The post-#7960 producer puts
# err_redact_rev on EVERY row and a `suppressed` row is a tier-4 row, so the steady state after
# delivery is BOTH proofs present. That is the message the closing run prints, and until this case
# existed it was the one branch of PROOF_SRC with no fixture at all.
{
  rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback   "$CLEAN_TAIL"
  rowf "2026-09-18 12:05:00" "$NEWBOOT" suppressed none
} > "$WORK/n20"
expect "N20 both proofs present (the real post-delivery steady state) -> PASS" 0 "$WORK/n20" "(proof: err_redact_rev+suppressed)"

# N21 — MUST-PASS. `[REDACTED` is the PRODUCER'S OWN redaction output, so grading it as a leak
# would post a daily public FAIL on precisely the hosts where the redaction is working. N19 covers
# zot's `[******` mask; this covers ours. Both halves of the exclusion need a fixture or half of it
# can be deleted silently.
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:info Authorization:[REDACTED] served CANARY7960" > "$WORK/n21"
expect "N21 the producer's own [REDACTED] is not a leak" 0 "$WORK/n21" "(proof: err_redact_rev)"

# N22 — MUST-FAIL, cardinality TWO. Every other credential fixture carries ONE header, where
# `1-of-1` cannot distinguish the scanning loop from a single `if`. The loop exists so a MASKED
# header cannot shadow a real one later in the same map, which is an ordinary zot header map.
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:info Authorization:[******] Cookie:[sid=abc] CANARY7960" > "$WORK/n22"
expect "N22 a masked header does not shadow a later real one" 1 "$WORK/n22" "STILL carry header content"

# Clean side — shapes the old bare-word discriminator graded as leaks.
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:info clientIP: default CANARY7960" > "$WORK/n17"
expect "N17 clientIP without an address is not a leak" 0 "$WORK/n17" "(proof: err_redact_rev)"
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:error invalid headers: [Content-Type] CANARY7960" > "$WORK/n18"
expect "N18 a list of header NAMES is not a leak" 0 "$WORK/n18" "(proof: err_redact_rev)"
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:info Authorization:[******] CANARY7960" > "$WORK/n19"
expect "N19 a zot-masked credential header is not a leak" 0 "$WORK/n19" "(proof: err_redact_rev)"

# N23 — MUST-PASS, a SHORTER asterisk mask. The sibling zot-log-channel-7440.sh accepts
# `\[(\*{3,}|REDACTED)`; POSIX awk has no intervals, so this probe uses a three-asterisk prefix.
# Without this fixture that prefix can be narrowed back to a six-asterisk literal silently, and a
# 3/4/5-asterisk mask would then post a public FAIL on a correctly-masked host.
rowf "2026-09-18 12:00:00" "$NEWBOOT" fallback "level:info Authorization:[***] CANARY7960" > "$WORK/n23"
expect "N23 a shorter asterisk mask is still a mask, not a leak" 0 "$WORK/n23" "(proof: err_redact_rev)"

# ── reject control for expect(), the VERDICT-OWNING helper ─────────────────────────────────
# pass()/fail() are dispatch; `expect` is what DECIDES. A control that drives only pass()/fail()
# proves the dispatch works while `expect` decides nothing — measured: neutering expect's two
# comparisons left this suite 35/35 green with the probe never consulted. Drive expect once with a
# deliberately wrong code AND a wrong marker, require `fails` to have moved, then unwind (counters
# AND the case tally, so MIN_CASES stays exact). Reports via printf/exit, never through expect().
_e_p0=$passes; _e_f0=$fails; _e_c0=$cases
expect "expect() reject control (this FAIL line is expected, not a real failure)" 99 "$WORK/f15" "__A_MARKER_NO_BRANCH_EVER_PRINTS__"
if (( fails != _e_f0 + 1 )); then
  printf 'FATAL: expect() did not register a failure for a deliberately wrong code+marker -- every case above is unbacked.\n' >&2
  exit 1
fi
passes=$_e_p0; fails=$_e_f0; cases=$_e_c0

# ── positive control for the verdict helpers ───────────────────────────────────────────────
# An assertion-count floor cannot see a rewritten fail() that still counts. Drive both helpers
# once and confirm BOTH counters moved, then unwind. Reports via printf/exit, never through the
# helpers it is testing.
_p0=$passes; _f0=$fails
pass "verdict-helper positive control (this line is the control)"
fail "verdict-helper positive control (expected FAIL line, not a real failure)"
if (( passes != _p0 + 1 || fails != _f0 + 1 )); then
  printf 'FATAL: verdict helpers do not both move their counters — every assertion above is unbacked.\n' >&2
  exit 1
fi
passes=$_p0; fails=$_f0

# ── conservation ───────────────────────────────────────────────────────────────────────────
echo
echo "=== $passes passed, $fails failed, $cases cases ==="
if (( passes + fails != cases )); then
  printf 'FATAL: verdict conservation violated — %s+%s != %s cases.\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
# BOUND, not inlined. scripts/guard-vacuity-floor.test.sh builds its mutant by slicing the
# floor block together with its THRESHOLD BINDINGS; a floor whose threshold is a bare literal
# is unconstructible, so the suite silently leaves that meta-guard's covered population — it is
# reported as a construction failure, not as a fired floor. Both siblings that pass it bind the
# threshold first (markdown-lint.test.sh, zot-fill-rate-7341.test.sh). The VALUE stays a
# literal: binding it to a variable expansion re-creates the same unconstructible shape.
MIN_CASES=39
if (( cases < MIN_CASES )); then
  # PHRASING IS LOAD-BEARING, not style. guard-vacuity-floor.test.sh classifies a mutant as
  # FIRES only when its output carries a floor-shaped SENTINEL from a fixed vocabulary
  # (`[FATAL]` with literal brackets, `FAIL:`, `vacuit`, `cardinality`, `assertion floor`,
  # `only <n>`, `assertions ran`, ...). A floor that fires correctly but reports in other words
  # is classified CONSTRUCTION — indistinguishable from one that never ran — and the suite
  # silently leaves that meta-guard's covered population. `only %s cases ran` is the sibling's
  # phrasing and matches `only [0-9]`.
  printf 'FATAL: only %s cases ran, below the floor of %s -- the suite was truncated, so a 0-failure tally proves nothing.\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
echo "All $cases cases passed."
