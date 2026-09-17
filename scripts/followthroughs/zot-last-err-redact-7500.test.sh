#!/usr/bin/env bash
# Exit-code harness for zot-last-err-redact-7500.sh (#7500 delivery watch, tracker #7960).
#
# WHY THIS FILE EXISTS. The probe grades a MIXED-BOOT window for the first time on the one run
# that matters: the sweep immediately after a registry-host-replace. Until 2026-09-17 nothing
# exercised that shape, and the probe got it wrong in the FAIL direction — `NEWEST_BOOT` described
# the newest row while `LEAKY` counted every tier-4 row in the 24h window, so the first post-
# replace sweep would select the delivered branch and grade ~24h of PRE-replace output against it.
# Case 1 is that input. It exits 1 ("the redaction shipped and is not working") against the
# pre-fix probe and 0 against the fixed one.
#
# Every case below is a way the verdict can be wrong about WHICH HOST it describes. That is the
# axis this probe is uniquely exposed on: it is the only followthrough whose subject is replaced
# mid-window by design (ADR-096 — the registry host is cloud-init-only, so delivery IS a replace).
#
# NO ENV SEAM IS ADDED TO THE PROBE FOR THIS. `QUERY` is derived from the probe's own location
# (`$REPO_ROOT/scripts/betterstack-query.sh`), so the harness builds a throwaway repo-root layout
# and copies the probe into it. A seam that lets a caller substitute the warehouse is exactly the
# "manufacture a clean verdict" power the sibling registry preflight refuses on its production
# path; this file gets the same isolation without granting it.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): the envelope and field shape mirror
# a measured emission, every uuid and sample string is fabricated.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_SRC="$HERE/zot-last-err-redact-7500.sh"
[[ -f "$PROBE_SRC" ]] || { echo "FATAL: probe not found at $PROBE_SRC" >&2; exit 1; }

# The baked-in merge-time baseline. Read from the probe rather than duplicated, so a future
# rebaseline cannot leave this harness asserting against a constant that no longer exists.
BASELINE="$(sed -n 's/^BASELINE_AT_MERGE=\(.*\)$/\1/p' "$PROBE_SRC" | tail -1)"
[[ -n "$BASELINE" ]] || { echo "FATAL: could not read BASELINE_AT_MERGE from the probe" >&2; exit 1; }
NEWBOOT="9f2c41d6-5b7a-4e08-9c31-7ad0e2b41f55"   # fabricated post-replace boot

fails=0
passes=0
# Incremented at the CALL SITE, never inside pass()/fail() — so stubbing a verdict helper drops
# the assertion WITHOUT dropping its count, and the conservation check at the bottom catches it.
cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── fixture builders ───────────────────────────────────────────────────────────────────────
# A production-shaped decoded row. `zot_last_err` is emitted LAST and is free text, which is the
# whole reason the probe cuts the tail before reading boot_id.
row() { # <boot_id> <src> <tail>
  printf '{"raw":"SOLEUR_ZOT_DISK host=registry-1 pcent=8 boot_id=%s zot_last_err_src=%s zot_last_err=%s"}\n' "$1" "$2" "$3"
}
CLEAN_TAIL='level:info HTTP API request served in 3ms'
LEAKY_TAIL='level:info HTTP API {headers:{Cookie:abc123,User-Agent:curl}} clientIP:10.0.1.9'

run_probe() { # <fixture-file> -> echoes exit code, stderr+stdout to $WORK/out
  local fixture="$1" root="$WORK/root"
  rm -rf "$root"; mkdir -p "$root/scripts/followthroughs"
  cp "$PROBE_SRC" "$root/scripts/followthroughs/"
  cat > "$root/scripts/betterstack-query.sh" <<STUB
#!/usr/bin/env bash
# Assert the probe's query construction before answering: a probe that silently stopped
# scoping --grep or --since would otherwise stay green through every case in this file.
argv="\$*"
case "\$argv" in
  *--since*) : ;;
  *) echo "STUB: probe dropped --since (argv: \$argv)" >&2; exit 64 ;;
esac
case "\$argv" in
  *--grep*SOLEUR_ZOT_DISK*) : ;;
  *) echo "STUB: probe dropped the SOLEUR_ZOT_DISK grep (argv: \$argv)" >&2; exit 64 ;;
esac
cat "$fixture"
STUB
  chmod +x "$root/scripts/betterstack-query.sh"
  BETTERSTACK_QUERY_HOST=stub \
  BETTERSTACK_QUERY_USERNAME=stub \
  BETTERSTACK_QUERY_PASSWORD=stub \
    bash "$root/scripts/followthroughs/zot-last-err-redact-7500.sh" >"$WORK/out" 2>&1
  echo $?
}

expect() { # <name> <expected-rc> <fixture-file>
  cases=$((cases + 1))
  local name="$1" want="$2" fixture="$3" got
  got="$(run_probe "$fixture")"
  if [[ "$got" == "$want" ]]; then
    pass "$name (exit $got)"
  else
    fail "$name — expected exit $want, got $got"
    sed 's/^/        | /' "$WORK/out" >&2
  fi
}

# ── Case 1: THE LIVE SHAPE. Replace landed mid-window; old boot leaks, new boot is clean. ──
# Pre-fix this exits 1 and posts "the redaction shipped and is not working" on the one sweep
# that first observes a working redaction.
{
  row "$BASELINE" fallback "$LEAKY_TAIL"
  row "$BASELINE" fallback "$LEAKY_TAIL"
  row "$NEWBOOT"  fallback "$CLEAN_TAIL"
} > "$WORK/f1"
expect "mixed-boot window, delivered host clean -> PASS" 0 "$WORK/f1"

# ── Case 2: the genuine red must survive the scoping. ──────────────────────────────────────
{
  row "$BASELINE" fallback "$LEAKY_TAIL"
  row "$NEWBOOT"  fallback "$LEAKY_TAIL"
} > "$WORK/f2"
expect "delivered host STILL leaking -> FAIL" 1 "$WORK/f2"

# ── Case 3: delivered, but tier 4 has not occurred on the new boot yet. ────────────────────
# Ungraded. Must be neither PASS (no evidence from the delivered host) nor FAIL (the leaky rows
# belong to a host that no longer exists).
{
  row "$BASELINE" fallback "$LEAKY_TAIL"
  row "$NEWBOOT"  regex    "$CLEAN_TAIL"
} > "$WORK/f3"
expect "delivered, no tier-4 row yet on the new boot -> TRANSIENT" 2 "$WORK/f3"

# ── Case 4: not yet delivered. Regression guard on the branch that ran for 8 days. ─────────
{
  row "$BASELINE" fallback "$LEAKY_TAIL"
  row "$BASELINE" fallback "$LEAKY_TAIL"
} > "$WORK/f4"
expect "un-replaced host still leaking -> TRANSIENT (not FAIL)" 2 "$WORK/f4"

# ── Case 5: delivery unmeasurable. No boot_id on any row. ──────────────────────────────────
printf '{"raw":"SOLEUR_ZOT_DISK host=registry-1 pcent=8 zot_last_err_src=fallback zot_last_err=%s"}\n' "$CLEAN_TAIL" > "$WORK/f5"
expect "no boot_id anywhere -> TRANSIENT, never graded" 2 "$WORK/f5"

# ── Case 6: the tail cannot forge the boot. ────────────────────────────────────────────────
# A tier-4 row on the BASELINE boot whose free-text tail contains a fake ` boot_id=`. If the tail
# were trusted it would win `tail -1`'s greedy read, select the delivered branch, and — with the
# tail also carrying header content — close or red the tracker on a host never replaced.
{
  row "$BASELINE" fallback "level:info HTTP API boot_id=$NEWBOOT {headers:{Cookie:zzz}}"
} > "$WORK/f6"
expect "spoofed boot_id in the untrusted tail -> TRANSIENT (not delivered)" 2 "$WORK/f6"

# ── conservation ───────────────────────────────────────────────────────────────────────────
echo
echo "=== $passes passed, $fails failed, $cases cases ==="
if (( passes + fails != cases )); then
  echo "FATAL: verdict conservation violated — $passes+$fails != $cases cases. A verdict helper" >&2
  echo "       was stubbed or an assertion returned without resolving." >&2
  exit 1
fi
(( cases >= 6 )) || { echo "FATAL: case floor is 6, found $cases (coverage removed?)" >&2; exit 1; }
(( fails == 0 )) || exit 1
echo "All $cases cases passed."
