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
# KNOWN GAP, stated rather than left implicit: the probe scopes on boot_id and never reads
# `host=`. Two hosts POSTing this marker to the shared source would both satisfy the envelope
# anchor, so a second host's row could supply the "newest boot". The registry is single-host
# today; tracked with the delivery-key work rather than papered over here.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SRC="$HERE/zot-last-err-redact-7500.sh"
[[ -f "$PROBE_SRC" ]] || { echo "FATAL: probe not found at $PROBE_SRC" >&2; exit 1; }

# Read from the probe rather than duplicated, so a rebaseline cannot leave this asserting against
# a constant that no longer exists.
BASELINE="$(sed -n 's/^BASELINE_AT_MERGE=\(.*\)$/\1/p' "$PROBE_SRC" | tail -1)"
[[ -n "$BASELINE" ]] || { echo "FATAL: could not read BASELINE_AT_MERGE from the probe" >&2; exit 1; }
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
# Field order mirrors the producer: zot_last_err_src … boot_id … host … zot_last_err LAST.
row() { # <dt> <boot_id> <src> <tail>
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 zot_last_err_src=%s boot_id=%s host=soleur-registry zot_last_err=%s\\"}"}\n' \
    "$1" "$3" "$2" "$4"
}
# A row that merely QUOTES the marker — a Vector-shipped journald envelope, the measured 2026-07-15
# contamination shape. Must never select the boot or supply evidence.
foreign() { # <dt> <boot_id>
  printf '{"dt":"%s","raw":"{\\"PRIORITY\\":\\"6\\",\\"_HOSTNAME\\":\\"soleur-web-1\\",\\"message\\":\\"[zot] SOLEUR_ZOT_DISK egress FAILED: zot_last_err_src=fallback boot_id=%s zot_last_err=none\\"}"}\n' \
    "$1" "$2"
}
# A Phase-B-exclusive proof row. `suppressed` is emitted only by the Phase B gate (96f5b6eb5),
# so its presence on a boot PROVES the new producer is running there. Every case asserting an
# AUTHORITATIVE verdict (exit 0 or exit 1) must carry one, because the probe now refuses to close
# the tracker or call the redaction broken on boot drift alone.
proof() { row "$1" "$2" suppressed ""; }
CLEAN_TAIL='level:info HTTP API request served in 3ms'
COOKIE_TAIL='level:info HTTP API {headers:{Cookie:abc123}} served'
CLIENTIP_TAIL='level:info HTTP API served clientIP:10.0.1.9'

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
  # env -u mirrors the `env -i` the sweeper runs probes under. Without it an operator with
  # SOLEUR_FT_BASELINE_BOOT exported — exactly who debugs this probe — gets 2 passed / 4 failed.
  env -u SOLEUR_FT_BASELINE_BOOT -u SOLEUR_FT_WINDOW -u SOLEUR_FT_LIMIT \
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
  if (( ok )); then
    pass "$name (exit $got, branch: ${marker:0:46})"
  else
    fail "$name — expected exit $want + marker '${marker:0:46}', got exit $got"
    sed 's/^/        | /' "$WORK/out" >&2
  fi
}

# ── Case 1: THE LIVE SHAPE. Replace landed mid-window; old boot leaks, new boot clean. ─────
{
  row "2026-09-17 10:00:00" "$BASELINE" fallback "$COOKIE_TAIL"
  row "2026-09-17 10:05:00" "$BASELINE" fallback "$COOKIE_TAIL"
  row   "2026-09-17 12:00:00" "$NEWBOOT" fallback "$CLEAN_TAIL"
  proof "2026-09-17 12:05:00" "$NEWBOOT"
} > "$WORK/f1"
expect "mixed-boot window, delivered host clean -> PASS" 0 "$WORK/f1" "PASS: producer delivered"

# ── Case 2: the genuine red must survive the scoping. ──────────────────────────────────────
{
  row "2026-09-17 10:00:00" "$BASELINE" fallback "$COOKIE_TAIL"
  row   "2026-09-17 12:00:00" "$NEWBOOT" fallback "$COOKIE_TAIL"
  proof "2026-09-17 12:05:00" "$NEWBOOT"
} > "$WORK/f2"
expect "delivered host STILL leaking -> FAIL" 1 "$WORK/f2" "STILL carry header content"

# ── Case 3: delivered, tier 4 not yet on the new boot. Must name DELIVERY HAS LANDED. ──────
{
  row "2026-09-17 10:00:00" "$BASELINE" fallback "$COOKIE_TAIL"
  row "2026-09-17 12:00:00" "$NEWBOOT"  regex    "$CLEAN_TAIL"
} > "$WORK/f3"
expect "delivered, no tier-4 yet on new boot -> TRANSIENT naming delivery" 2 "$WORK/f3" "DELIVERY HAS LANDED"

# ── Case 4: not yet delivered. Regression guard on the branch that ran for 8 days. ─────────
{
  row "2026-09-17 10:00:00" "$BASELINE" fallback "$COOKIE_TAIL"
  row "2026-09-17 10:05:00" "$BASELINE" fallback "$COOKIE_TAIL"
} > "$WORK/f4"
expect "un-replaced host still leaking -> TRANSIENT (not FAIL)" 2 "$WORK/f4" "NOT YET DELIVERED"

# ── Case 5: boot_id=unknown is the /proc fallback, not an identity. ────────────────────────
# Pre-fix this exited 0 and CLOSED the tracker while the real host was still leaking.
{
  row "2026-09-17 10:00:00" "$BASELINE" fallback "$COOKIE_TAIL"
  row "2026-09-17 12:00:00" unknown     fallback "$CLEAN_TAIL"
} > "$WORK/f5"
expect "boot_id=unknown is not a delivered identity -> not a PASS" 2 "$WORK/f5" "NOT YET DELIVERED"

# ── Case 6: no boot_id at all -> CANNOT ESTABLISH (exit 3), never a pass, never NOT-YET. ───
printf '{"dt":"2026-09-17 10:00:00","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 zot_last_err_src=fallback host=soleur-registry zot_last_err=%s\\"}"}\n' "$CLEAN_TAIL" > "$WORK/f6"
expect "no boot_id anywhere -> CANNOT ESTABLISH" 3 "$WORK/f6" "CANNOT ESTABLISH: no usable boot_id"

# ── Case 7: a foreign row quoting the marker must not select the boot or supply evidence. ──
# Pre-anchor this exited 0: the injected row became the entire evidence base.
{
  row     "2026-09-17 10:00:00" "$BASELINE" fallback "$COOKIE_TAIL"
  foreign "2026-09-17 12:00:00" "$OTHER"
} > "$WORK/f7"
expect "marker-quoting foreign row cannot close the tracker" 2 "$WORK/f7" "NOT YET DELIVERED"

# ── Case 8: EVERY row is foreign -> no producer envelope at all. ───────────────────────────
foreign "2026-09-17 12:00:00" "$OTHER" > "$WORK/f8"
expect "no producer envelope in the window -> TRANSIENT" 2 "$WORK/f8" "NONE carries the"

# ── Case 9: the tier field cannot be spoofed from the untrusted tail. ──────────────────────
# A genuine tier-2 row whose free text mentions the tier-4 token must not be graded as tier 4.
{
  row "2026-09-17 10:00:00" "$BASELINE" fallback "$COOKIE_TAIL"
  row "2026-09-17 12:00:00" "$NEWBOOT"  regex    "restart context: zot_last_err_src=fallback seen earlier"
} > "$WORK/f9"
expect "tier spoofed in the tail is not tier 4" 2 "$WORK/f9" "DELIVERY HAS LANDED"

# ── Case 10: a second ` zot_last_err=` must not truncate the leak out of the measurement. ──
# The greedy read graded this CLEAN and exited 0 on a genuinely leaking delivered host.
{
  row   "2026-09-17 12:00:00" "$NEWBOOT" fallback "level:info {headers:{Cookie:secret}} gc failed for zot_last_err=ok"
  proof "2026-09-17 12:05:00" "$NEWBOOT"
} > "$WORK/f10"
expect "second zot_last_err= cannot hide a leak" 1 "$WORK/f10" "STILL carry header content"

# ── Case 11/12: each leak token is pinned INDEPENDENTLY. ───────────────────────────────────
# One fixture carrying both tokens lets either half of the alternation be deleted silently.
{ row "2026-09-17 12:00:00" "$NEWBOOT" fallback "$COOKIE_TAIL"; proof "2026-09-17 12:05:00" "$NEWBOOT"; } > "$WORK/f11"
expect "headers alone is a leak" 1 "$WORK/f11" "STILL carry header content"
{ row "2026-09-17 12:00:00" "$NEWBOOT" fallback "$CLIENTIP_TAIL"; proof "2026-09-17 12:05:00" "$NEWBOOT"; } > "$WORK/f12"
expect "clientIP alone is a leak" 1 "$WORK/f12" "STILL carry header content"

# ── Case 13: a suppressed row counts as "the subject ran" and cannot leak. ─────────────────
# Phase B re-tags a fully-suppressed tier-4 sample to `suppressed`. A fallback-only selector made
# Guard 1 permanently unsatisfiable on a delivered host whose gate works at its strongest.
{
  row "2026-09-17 10:00:00" "$BASELINE" fallback   "$COOKIE_TAIL"
  row "2026-09-17 12:00:00" "$NEWBOOT"  suppressed ""
} > "$WORK/f13"
expect "suppressed tier-4 row satisfies Guard 1 -> PASS" 0 "$WORK/f13" "PASS: producer delivered"

# ── Case 14: a legitimate message mentioning 'headers' in prose is not a leak. ─────────────
{ row "2026-09-17 12:00:00" "$NEWBOOT" fallback "level:error cannot parse headers"; proof "2026-09-17 12:05:00" "$NEWBOOT"; } > "$WORK/f14"
expect "prose mentioning headers is not a leak" 0 "$WORK/f14" "PASS: producer delivered"

# ── Case 15: empty corpus is channel_dark, never clean. ────────────────────────────────────
: > "$WORK/f15"
expect "zero rows -> channel_dark, not a pass" 2 "$WORK/f15" "channel_dark"

# ── Case 16: ordering is not inherited from the query. ─────────────────────────────────────
# Emitted newest-first. Without the dt sort, tail -1 is the OLDEST row and a delivered host
# reports NOT YET DELIVERED forever.
{
  proof "2026-09-17 12:05:00" "$NEWBOOT"
  row   "2026-09-17 12:00:00" "$NEWBOOT"  fallback "$CLEAN_TAIL"
  row   "2026-09-17 10:00:00" "$BASELINE" fallback "$COOKIE_TAIL"
} > "$WORK/f16"
expect "newest-first input still grades the newest boot" 0 "$WORK/f16" "PASS: producer delivered"

# ── Case 18: boot drift WITHOUT a Phase-B token is not an authoritative verdict. ───────────
# A reboot of the un-replaced host flips boot_id with the OLD user_data in place. Neither exit 0
# (closes a live leak tracker) nor exit 1 ("the redaction shipped and is not working") may be
# emitted on evidence that cannot tell a reboot from a replace.
{
  row "2026-09-17 10:00:00" "$BASELINE" fallback "$COOKIE_TAIL"
  row "2026-09-17 12:00:00" "$NEWBOOT"  fallback "$COOKIE_TAIL"
} > "$WORK/f18"
expect "drift without a Phase-B token -> CANNOT ESTABLISH, not FAIL" 3 "$WORK/f18" "boot drift is a REBOOT, not a REPLACE"

{
  row "2026-09-17 10:00:00" "$BASELINE" fallback "$COOKIE_TAIL"
  row "2026-09-17 12:00:00" "$NEWBOOT"  fallback "$CLEAN_TAIL"
} > "$WORK/f19"
expect "drift without a Phase-B token -> CANNOT ESTABLISH, not PASS" 3 "$WORK/f19" "delivery is inferred, not proven"

# ── Case 17: a non-zero query exit is not a clean window. ──────────────────────────────────
cases=$((cases + 1))
cp "$WORK/f1" "$WORK/f17"
if [[ "$(STUB_RC=7 run_probe "$WORK/f17")" == "2" ]] && grep -q 'channel_dark or auth failure' "$WORK/out"; then
  pass "query exit 7 -> TRANSIENT, not a pass"
else
  fail "query exit 7 -> expected TRANSIENT with the auth-failure branch"
  sed 's/^/        | /' "$WORK/out" >&2
fi

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
MIN_CASES=19
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
