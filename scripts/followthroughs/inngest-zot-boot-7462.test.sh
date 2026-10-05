#!/usr/bin/env bash
# Exit-code harness for inngest-zot-boot-7462.sh (#7462 / #7228).
#
# The probe's exit code auto-closes two P1 trackers, so every case below is a way the verdict can
# be wrong in the PASS direction — plus the TRANSIENT-direction wedges, because a probe stuck at
# TRANSIENT is a tracker that never closes and an alarm that never fires.
#
# FIXTURES ARE PRODUCTION-SHAPED, AND THAT IS LOAD-BEARING. betterstack-query.sh emits JSONEachRow
# whose `raw` column is a JSON-ENCODED STRING containing a JSON document. A fixture that emitted
# `raw` as a bare object would let a substring-matching parse pass every case here while failing in
# production — the sibling probe's harness paid for exactly that (see zot-fill-rate-7341.test.sh).
# So rows are built with jq and `raw` is genuinely double-encoded.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): the envelope and field shape mirror a
# measured emission, every host id, digest and timestamp is fabricated.
#
# THE STUB ASSERTS ITS ARGV. Without that, dropping --grep, adding --no-archive (which collapses
# the 7d window to a ~40-minute hot keyhole -> channel_dark forever, i.e. #6288 verbatim) or
# shrinking --limit all stay green.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/inngest-zot-boot-7462.sh"
fails=0
checks=0
pass() { printf '  PASS: %s\n' "$1"; checks=$((checks + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); checks=$((checks + 1)); }

[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/stub-query" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_RC:-0}" == "0" ]] || exit "${STUB_RC}"
argv="$*"
[[ "$argv" == *"--since"* ]] || { echo "stub: query missing --since (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--grep SOLEUR_INNGEST_BOOT_STAGE"* ]] || { echo "stub: query missing the marker --grep (argv: $argv)" >&2; exit 64; }
[[ "$argv" == *"--limit"* ]] || { echo "stub: query missing --limit (argv: $argv)" >&2; exit 64; }
# The archive arm is mandatory at a 7d window. --no-archive would truncate to the hot keyhole.
[[ "$argv" == *"--no-archive"* ]] && { echo "stub: --no-archive at a multi-day window (argv: $argv)" >&2; exit 64; }
cat "${STUB_ROWS:-/dev/null}"
STUB
chmod +x "$WORK/stub-query"

# row <stage> [marker] [message-override] — emits ONE production-shaped JSONEachRow line.
row() {
  local stage="$1" marker="${2:-SOLEUR_INNGEST_BOOT_STAGE}" msg="${3:-}"
  [[ -n "$msg" ]] || msg="SOLEUR_INNGEST_BOOT_STAGE stage=${stage} detail=synthetic"
  jq -cn --arg m "$marker" --arg s "$stage" --arg msg "$msg" \
    '{dt:"2026-08-20 10:00:00", raw: ({message:$msg, marker:$m, stage:$s, host:"soleur-inngest", shipper:"cloud-init-phone-home"} | tostring)}'
}

# run <fixture-file> -> sets RC / OUT
run() {
  OUT="$(BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
        INNGEST_ZOT_BOOT_QUERY_BIN="$WORK/stub-query" STUB_ROWS="$1" STUB_RC="${STUB_RC:-0}" \
        bash "$PROBE" 2>&1)"
  RC=$?
}

expect() { # expect <case> <want-rc> <want-substring>
  local name="$1" want_rc="$2" want_sub="$3"
  if [[ "$RC" -ne "$want_rc" ]]; then
    fail "$name — rc=$RC want=$want_rc :: $(printf '%s' "$OUT" | head -1)"
  elif ! grep -qF "$want_sub" <<<"$OUT"; then
    fail "$name — rc ok but missing '$want_sub' :: $(printf '%s' "$OUT" | head -1)"
  else
    pass "$name"
  fi
}

echo "== inngest-zot-boot-7462.sh exit-code harness =="

# --- C1 credentials absent is its own reason, never 'not delivered' -----------------------------
: > "$WORK/empty.jsonl"
OUT="$(INNGEST_ZOT_BOOT_QUERY_BIN="$WORK/stub-query" STUB_ROWS="$WORK/empty.jsonl" \
      env -u BETTERSTACK_QUERY_HOST -u BETTERSTACK_QUERY_USERNAME -u BETTERSTACK_QUERY_PASSWORD \
      bash "$PROBE" 2>&1)"; RC=$?
expect "C1 unprovisioned credentials -> TRANSIENT credentials_unprovisioned" 2 "reason=credentials_unprovisioned"
grep -qF "not_delivered" <<<"$OUT" \
  && fail "C1b credential failure must NOT mention not_delivered (opposite remedies)" \
  || pass "C1b credential failure is distinct from not_delivered"

# --- C2 query failure is TRANSIENT, and never a statement about the host -------------------------
STUB_RC=7 run "$WORK/empty.jsonl"; STUB_RC=0
expect "C2 query rc!=0 -> TRANSIENT query_failed" 2 "reason=query_failed"

# --- C3 channel dark ------------------------------------------------------------------------------
run "$WORK/empty.jsonl"
expect "C3 zero rows -> TRANSIENT channel_dark" 2 "reason=channel_dark"

# --- C4 booted on a pre-#7516 image ---------------------------------------------------------------
{ row runcmd-entered; row docker-restarted; row bootstrap-done; } > "$WORK/old.jsonl"
run "$WORK/old.jsonl"
expect "C4 boot markers without pre-zot-pull -> TRANSIENT not_delivered" 2 "reason=not_delivered"

# --- C5 delivered, zot missed ---------------------------------------------------------------------
{ row runcmd-entered; row pre-zot-pull; row inngest_ghcr_fallback; } > "$WORK/missed.jsonl"
run "$WORK/missed.jsonl"
expect "C5 pre-zot-pull without inngest_zot -> TRANSIENT zot_leg_missed" 2 "reason=zot_leg_missed"

# --- C6 zot served but image never ran ------------------------------------------------------------
{ row pre-zot-pull; row inngest_zot; row pre-bootstrap-run; } > "$WORK/nobootstrap.jsonl"
run "$WORK/nobootstrap.jsonl"
expect "C6 inngest_zot without bootstrap-done -> TRANSIENT bootstrap_incomplete" 2 "reason=bootstrap_incomplete"

# --- C7 a fallback alongside success is still a downgrade -----------------------------------------
{ row pre-zot-pull; row inngest_zot; row bootstrap-done; row inngest_ghcr_fallback; } > "$WORK/mixed.jsonl"
run "$WORK/mixed.jsonl"
expect "C7 fallback alongside success -> TRANSIENT fallback_observed (not PASS)" 2 "reason=fallback_observed"

# --- C8 the only PASS ------------------------------------------------------------------------------
{ row runcmd-entered; row pre-zot-pull; row inngest_zot; row pre-bootstrap-run; row bootstrap-done; } > "$WORK/good.jsonl"
run "$WORK/good.jsonl"
expect "C8 zot-served + bootstrap-done, no failure markers -> PASS" 0 "PASS: the dedicated inngest host booted zot-primary"

# --- C9 all-legs-failed is the one FAIL, and it outranks every other arm ---------------------------
{ row pre-zot-pull; row oci-pull-ALL-LEGS-FAILED; } > "$WORK/broken.jsonl"
run "$WORK/broken.jsonl"
expect "C9 oci-pull-ALL-LEGS-FAILED -> FAIL" 1 "reason=all_legs_failed"
{ row pre-zot-pull; row inngest_zot; row bootstrap-done; row oci-pull-ALL-LEGS-FAILED; } > "$WORK/broken2.jsonl"
run "$WORK/broken2.jsonl"
expect "C9b all-legs-failed outranks an otherwise-PASSing window" 1 "reason=all_legs_failed"

# --- C10 FIELD ISOLATION: a row that merely CONTAINS a stage name must not count -------------------
# The message says inngest_zot; the .stage field says something else. A substring parse PASSes here.
{ row runcmd-entered; row pre-zot-pull;
  row docker-restarted SOLEUR_INNGEST_BOOT_STAGE "SOLEUR_INNGEST_BOOT_STAGE stage=inngest_zot detail=echoed-in-prose";
  row bootstrap-done; } > "$WORK/spoof.jsonl"
run "$WORK/spoof.jsonl"
expect "C10 stage name in the MESSAGE does not satisfy the .stage anchor" 2 "reason=zot_leg_missed"

# --- C11 foreign marker rows are ignored ------------------------------------------------------------
{ row runcmd-entered; row pre-zot-pull;
  row inngest_zot SOLEUR_ZOT_DISK;
  row bootstrap-done; } > "$WORK/foreign.jsonl"
run "$WORK/foreign.jsonl"
expect "C11 a different marker's row cannot supply inngest_zot" 2 "reason=zot_leg_missed"

# --- C12 undecodable rows are dropped, not fatal ----------------------------------------------------
{ echo '{"dt":"2026-08-20 10:00:00","raw":"not-json-at-all"}'; echo 'total garbage'; \
  row pre-zot-pull; row inngest_zot; row bootstrap-done; } > "$WORK/garbage.jsonl"
run "$WORK/garbage.jsonl"
expect "C12 undecodable rows are skipped, valid ones still counted -> PASS" 0 "PASS: the dedicated inngest host"

# --- C13 PASS output publishes COUNTS, never row values ---------------------------------------------
run "$WORK/good.jsonl"
if grep -qE 'detail=|10\.0\.1\.|sha256:' <<<"$OUT"; then
  fail "C13 PASS output leaked a row value (sweeper posts this to a PUBLIC issue)"
else
  pass "C13 PASS output is counts-only — no detail=, no 10.0.1.x, no digest"
fi

# --- C14 the banned ${VAR:?} form would turn an unset secret into a daily false-FAIL ----------------
# Pattern and comment-scoping BOTH mirror scripts/lint-followthrough-varq-ban.sh verbatim: it greps
# the raw file for line numbers and then drops FULL-LINE comments. Diverging here would either
# false-positive on the header paragraph that documents the ban (measured: it does) or, worse,
# pass something the real CI lint rejects.
if grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' "$PROBE" | grep -qvE '^[0-9]+:[[:space:]]*#'; then
  fail "C14 probe uses the banned \${VAR:?} form in CODE (aborts rc=1 -> reads as FAIL)"
else
  pass "C14 probe avoids the banned \${VAR:?} form in code"
fi

# --- C15 anti-vacuity: the harness ran its whole inventory -------------------------------------------
# EXACT, not >=. A floor that only catches shrinkage still lets a case be silently replaced.
if [[ "$checks" -ne 16 ]]; then
  fail "C15 anti-vacuity: expected 16 checks before this one, ran $checks"
else
  pass "C15 anti-vacuity: full inventory ran (16 checks + this one)"
fi

echo
if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails of $checks checks" >&2
  exit 1
fi
echo "OK: all $checks exit-code checks correct"
