#!/usr/bin/env bash
# Guard 2 (#7500) — sink-side credential scrub before PUBLIC publication.
#
# PROPERTY. No credential-bearing header value derived from a warehouse row reaches any
# workflow-visible public surface — issue body, issue comment, or Actions run log.
#
# WHY THIS EXISTS. `scheduled-zot-restart-loop.yml` publishes this script's `ZOT_ALARM_CAUSE=`
# into a GitHub issue on a PUBLIC repository. Measured on #7272 (2026-09-08): 100 comments,
# 36 carrying a `headers` object, 13 carrying a `clientIP`. No credential leaked — all 23
# `Authorization` occurrences render `Authorization:[******]` because ZOT masks that ONE header
# upstream, and every `clientIP` was RFC1918. The exposure was bounded by a vendor default, not
# by anything this repository controls. That is the gap this guard closes.
#
# THIS LAYER IS A DENYLIST, PERMANENTLY — and the suite says so rather than discovering it later.
# By the time text reaches `emit_and_exit()` the producer's `tr -d '"\\'` has destroyed the JSON,
# so the structural allowlist `redact()` uses in `zot-log-shipper.sh` is unavailable here forever.
# Case G2-3b asserts that boundary as a MEASURED FACT rather than leaving it to be discovered by a
# regulator. Do not "fix" G2-3b by widening it into an absolute claim; fix it in Phase B, at the
# producer, which is where the allowlist can still see structure.
#
# ASSEMBLY. Asserted at the `emit_and_exit()` CHOKEPOINT, never at the single `last_err=` site.
# Every CAUSE / DETAIL / NIC_CAUSE / NIC_DETAIL leaves through that one function, so asserting
# there quantifies over all present AND FUTURE arms. A guard that enumerated today's arms would
# go green the day someone adds the eleventh.
#
# .test.sh foot-guns (work conventions): `set -uo pipefail` (NOT -e — the checker exits non-zero
# by contract). Every checker call captures rc via `|| rc=$?`. Never `producer | grep -q` under
# pipefail (early match -> SIGPIPE 141 -> false negative); this file greps FILES and herestrings.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/zot-restart-loop-alarm.sh"
WORKFLOW="$(cd "$SCRIPT_DIR/.." && pwd)/.github/workflows/scheduled-zot-restart-loop.yml"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Stub betterstack-query.sh (the ZOT_BQ_OVERRIDE seam, mirroring the sibling suite) ------
# Branches on query SHAPE. NIC is matched FIRST: the NIC lookback carries both "24h" and
# "SOLEUR_PRIVATE_NIC", so a "24h"-first ladder would hand it the ZOT fixture.
STUB="$TMP/bq-stub.sh"
cat > "$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
argv="$*"
if [[ "$argv" == *"SOLEUR_PRIVATE_NIC"* ]]; then
  if [[ "$argv" == *"24h"* ]]; then
    [[ -n "${NIC_FIX_LOOKBACK:-}" && -f "${NIC_FIX_LOOKBACK:-}" ]] && cat "$NIC_FIX_LOOKBACK"
    exit "${NIC_FIX_LOOKBACK_RC:-0}"
  fi
  [[ -n "${NIC_FIX_MAIN:-}" && -f "${NIC_FIX_MAIN:-}" ]] && cat "$NIC_FIX_MAIN"
  exit "${NIC_FIX_MAIN_RC:-0}"
elif [[ "$argv" == *"24h"* ]]; then
  [[ -n "${ZOT_FIX_LOOKBACK:-}" && -f "${ZOT_FIX_LOOKBACK:-}" ]] && cat "$ZOT_FIX_LOOKBACK"
  exit "${ZOT_FIX_LOOKBACK_RC:-0}"
elif [[ "$argv" == *"SOLEUR_ZOT_DISK"* ]]; then
  [[ -n "${ZOT_FIX_MAIN:-}" && -f "${ZOT_FIX_MAIN:-}" ]] && cat "$ZOT_FIX_MAIN"
  exit "${ZOT_FIX_MAIN_RC:-0}"
else
  [[ -n "${ZOT_FIX_CONTROL:-}" && -f "${ZOT_FIX_CONTROL:-}" ]] && cat "$ZOT_FIX_CONTROL"
  exit "${ZOT_FIX_CONTROL_RC:-0}"
fi
STUB_EOF
chmod +x "$STUB"

BOOT_NEW="aaaaaaaa-0000-0000-0000-000000000002"

# zline <dt> <boot> <restarts> <exit_code> <oom5m> <oomkilled> <lasterr>
# Envelope shape is load-bearing (captured from production 2026-07-15): the host POSTs
# {"message":"<marker> …"} and Better Stack stores THAT JSON as `raw`. A flat "raw":"SOLEUR…"
# fixture would validate nothing. zot_last_err is LAST (free-text), matching the real emit.
zline() {
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=1 zot_restarts=%s ping_rc=0 mem_total_mb=7751 zot_anon_mb=35 zot_oom_kills=0 state_status=running oom_killed=%s exit_code=%s oom_kills_5m=%s boot_id=%s host=soleur-registry zot_last_err=%s\\"}"}\n' \
    "$1" "$3" "$6" "$4" "$5" "$2" "$7"
}

# FIXTURE REALISM. These samples are QUOTE-FREE on purpose. The producer runs
# `tr -d '"\\'` over the sample before it is ever POSTed, so a warehouse row physically cannot
# contain the JSON quoting that zot emitted. A fixture carrying quotes here would be testing an
# input population that does not exist, and would let a quote-anchored scrub pass while the real
# quote-free rows sail through. This is the #7272 rendering, reproduced.
HDRS_COOKIE='{level:info,message:HTTP API,headers:{Authorization:[******] Cookie:[session=s3cr3t-COOKIE-VALUE]},clientIP:10.0.1.9}'
HDRS_DOUBLE='{level:info,message:HTTP API,headers:{Cookie:[first=AAA-FIRST-SECRET] X-Api-Key:[live_BBB-SECOND-SECRET]},clientIP:10.0.1.9}'
HDRS_UNANTICIPATED='{level:info,message:HTTP API,headers:{X-Secret:[UNANTICIPATED-HEADER-VALUE]},clientIP:10.0.1.9}'
HDRS_PROXY='{level:info,message:HTTP API,headers:{Proxy-Authorization:[Basic PROXY-SECRET] X-Amz-Security-Token:[AMZ-SECRET-TOKEN]}}'
ALREADY_REDACTED='{level:info,message:HTTP API,headers:{Authorization:REDACTED Cookie:REDACTED}}'
# The SECOND denylist limit, measured (#7500 CLO review finding d). The bare-form value class
# stops at whitespace, so `Cookie: a b` masks only `a`. The BRACKETED form zot actually emits
# is masked whole, which is why exposure is low -- but an undocumented limit is precisely what
# the scope-limit section exists to prevent, so it is pinned here rather than left to be found.
HDRS_BARE_SPACED='level:info message:HTTP API Cookie: BARE-FIRST BARE-SECOND-SURVIVES clientIP:10.0.1.30'
PANIC_TIER1='panic: runtime error: invalid memory address [signal SIGSEGV] goroutine 42'

# zline_src <dt> <boot> <restarts> <exit_code> <oom5m> <oomkilled> <src> <lasterr>
# As zline, but carries zot_last_err_src -- the tier tag the producer already emits
# (cloud-init-registry.yml). Field ORDER mirrors the real emitter: zot_last_err_src sits before
# boot_id, and zot_last_err stays LAST because it is the only free-text field and the parser's
# trusted-region strip cuts from it.
zline_src() {
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=1 zot_restarts=%s ping_rc=0 mem_total_mb=7751 zot_anon_mb=35 zot_oom_kills=0 state_status=running oom_killed=%s exit_code=%s oom_kills_5m=%s zot_last_err_src=%s boot_id=%s host=soleur-registry zot_last_err=%s\\"}"}\n' \
    "$1" "$3" "$6" "$4" "$5" "$7" "$2" "$8"
}

PASS=0; FAIL=0; CASES=0
VERDICTS=""
USED_assert_cause_masks=0
USED_assert_cause_contains=0
USED_assert_struct=0
USED_assert_field_nonempty=0

pass() { PASS=$((PASS + 1)); VERDICTS="${VERDICTS}P"; printf 'ok   - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); VERDICTS="${VERDICTS}F"; printf 'FAIL - %s\n' "$1" >&2; }

# run_alarm: emits the checker's stdout for the currently-exported fixture env.
# rc is captured, never asserted here — this suite is about what gets PRINTED, and the sibling
# suite already owns the rc/verdict contract. Conflating them would make a scrub regression and a
# verdict regression indistinguishable.
run_alarm() {
  local out
  # `|| true`, NOT a captured-and-discarded rc. The checker exits non-zero BY CONTRACT (a FIRE
  # is rc=1), so the call must not abort the suite -- but capturing a verdict nothing reads is
  # an assertion defect wearing a comment: shellcheck flags it SC2034, and it reads as though
  # the exit code were being checked when it is not. The rc/verdict contract belongs to
  # zot-restart-loop-alarm.test.sh; this suite owns what gets PRINTED. A checker that dies
  # before emitting is still caught here, by the empty-field branch in assert_cause_masks.
  out="$(ZOT_BQ_OVERRIDE="$STUB" bash "$CHECKER" 2>&1)" || true
  printf '%s' "$out"
}

# field_of <output> <KEY> -> the value of the single `KEY=` line.
# Anchored at ^ so a KEY name appearing INSIDE another field's free text cannot be mistaken for
# the field itself — the trusted-region discipline this repo already applies at the parser.
field_of() { sed -n "s/^$2=//p" <<<"$1" | head -1; }

# assert_cause_masks <name> <field> <secret-substring>
# The CORE assertion: the secret must NOT appear anywhere in the published field.
assert_cause_masks() {
  USED_assert_cause_masks=$((USED_assert_cause_masks + 1))
  CASES=$((CASES + 1))
  local name="$1" field="$2" secret="$3" out val
  out="$(run_alarm)"
  val="$(field_of "$out" "$field")"
  if [[ -z "$val" ]]; then
    fail "$name: $field was empty — the arm never fired, so this case asserted nothing"
    return
  fi
  if [[ "$val" == *"$secret"* ]]; then
    fail "$name: $field leaked '$secret' to a PUBLIC surface -- $val"
  else
    pass "$name: $field carries no '$secret'"
  fi
}

# assert_cause_contains <name> <field> <substring>
# The complement. Without it, a scrub that blanks the whole field passes every masking row.
assert_cause_contains() {
  USED_assert_cause_contains=$((USED_assert_cause_contains + 1))
  CASES=$((CASES + 1))
  local name="$1" field="$2" want="$3" out val
  out="$(run_alarm)"
  val="$(field_of "$out" "$field")"
  if [[ "$val" == *"$want"* ]]; then
    pass "$name: $field retains '$want'"
  else
    fail "$name: $field lost '$want' — the scrub destroyed diagnostic value -- $val"
  fi
}

# assert_field_nonempty <name> <field>
# Asserts only that the field is emitted and non-empty. Deliberately weaker than naming a
# value: WHICH verdict the NIC stream reaches is the sibling suite's contract. This row exists
# to prove the NIC block rides THIS exit path, so that "the scrub covers NIC_CAUSE too" is a
# testable claim rather than an assertion about an arm that never runs here.
assert_field_nonempty() {
  USED_assert_field_nonempty=$((USED_assert_field_nonempty + 1))
  CASES=$((CASES + 1))
  local name="$1" field="$2" out val
  out="$(run_alarm)"
  val="$(field_of "$out" "$field")"
  if [[ -n "$val" ]]; then
    pass "$name ($field=$val)"
  else
    fail "$name: $field absent or empty — the block did not ride this exit path"
  fi
}

# assert_struct <name> <file> <ere> <min-count>
assert_struct() {
  USED_assert_struct=$((USED_assert_struct + 1))
  CASES=$((CASES + 1))
  local name="$1" file="$2" ere="$3" min="$4" n
  n="$(LC_ALL=C grep -cE -- "$ere" "$file" 2>/dev/null || true)"
  [[ -n "$n" ]] || n=0
  if [[ "$n" -ge "$min" ]]; then
    pass "$name (matches=$n >= $min)"
  else
    fail "$name: expected >= $min matches of /$ere/ in $(basename "$file"), got $n"
  fi
}

reset_fix() {
  unset ZOT_FIX_MAIN ZOT_FIX_LOOKBACK ZOT_FIX_CONTROL NIC_FIX_MAIN NIC_FIX_LOOKBACK
  unset ZOT_FIX_MAIN_RC ZOT_FIX_LOOKBACK_RC ZOT_FIX_CONTROL_RC NIC_FIX_MAIN_RC NIC_FIX_LOOKBACK_RC
  export ZOT_FIX_CONTROL="$TMP/control.json"
}
printf '{"dt":"2026-09-08T10:00:00Z","raw":"probe"}\n' > "$TMP/control.json"

# crash_loop_fixture <lasterr-sample> -> writes a climbing-restart MAIN fixture (condition B:
# >= CLIMB_N=3 strictly-increasing samples, no OOM signal) so the non-OOM arm that splices
# zot_last_err into CAUSE is the arm that fires.
crash_loop_fixture() {
  local sample="$1" f="$TMP/main.json"
  {
    zline "2026-09-08T10:00:00Z" "$BOOT_NEW" 1 0 0 false "$sample"
    zline "2026-09-08T10:05:00Z" "$BOOT_NEW" 2 0 0 false "$sample"
    zline "2026-09-08T10:10:00Z" "$BOOT_NEW" 3 0 0 false "$sample"
  } > "$f"
  export ZOT_FIX_MAIN="$f"
  export ZOT_FIX_LOOKBACK="$f"
}

# crash_loop_fixture_src <src> <sample>: as crash_loop_fixture, with the tier tag present.
crash_loop_fixture_src() {
  local src="$1" sample="$2" f="$TMP/main.json"
  {
    zline_src "2026-09-08T10:00:00Z" "$BOOT_NEW" 1 0 0 false "$src" "$sample"
    zline_src "2026-09-08T10:05:00Z" "$BOOT_NEW" 2 0 0 false "$src" "$sample"
    zline_src "2026-09-08T10:10:00Z" "$BOOT_NEW" 3 0 0 false "$src" "$sample"
  } > "$f"
  export ZOT_FIX_MAIN="$f"
  export ZOT_FIX_LOOKBACK="$f"
}

# oom_fixture: exit_code=137 -> an OOM arm, whose CAUSE is static text + trusted numerics.
# oom_kills_5m=0 is LOAD-BEARING: with a non-zero value the FIRST arm fires ("host/kernel OOM
# — exit_code=137 AND oom_kills_5m=N") and the assertion below, which names the THIRD arm's
# text, would fail against a perfectly healthy scrub. Measured, not assumed — the first draft
# of this fixture used 2 and produced exactly that false RED.
oom_fixture() {
  local f="$TMP/main.json"
  {
    zline "2026-09-08T10:00:00Z" "$BOOT_NEW" 1 137 0 false "none"
    zline "2026-09-08T10:05:00Z" "$BOOT_NEW" 2 137 0 false "none"
  } > "$f"
  export ZOT_FIX_MAIN="$f"
  export ZOT_FIX_LOOKBACK="$f"
}

echo "=== Guard 2 — sink-side scrub before public publication (#7500) ==="

# --- Row 3: a Cookie value must be masked in the published CAUSE ---------------------------
reset_fix; crash_loop_fixture "$HDRS_COOKIE"
assert_cause_masks "G2-3 cookie" ZOT_ALARM_CAUSE "s3cr3t-COOKIE-VALUE"

# --- Row 5: a SECOND credential header after a compliant first — both masked ---------------
# RED if the scrub stops at the first match (a missing /g).
reset_fix; crash_loop_fixture "$HDRS_DOUBLE"
assert_cause_masks "G2-5 first of two" ZOT_ALARM_CAUSE "AAA-FIRST-SECRET"
reset_fix; crash_loop_fixture "$HDRS_DOUBLE"
assert_cause_masks "G2-5 second of two" ZOT_ALARM_CAUSE "BBB-SECOND-SECRET"

# --- Row 5b: the other two denylist members, so the class is covered not sampled ------------
reset_fix; crash_loop_fixture "$HDRS_PROXY"
assert_cause_masks "G2-5b proxy-authorization" ZOT_ALARM_CAUSE "PROXY-SECRET"
reset_fix; crash_loop_fixture "$HDRS_PROXY"
assert_cause_masks "G2-5b x-amz-security-token" ZOT_ALARM_CAUSE "AMZ-SECRET-TOKEN"

# --- Row 3b: the DENYLIST BOUNDARY, asserted as a measured fact ----------------------------
# An unanticipated header name SURVIVES this layer. That is not a bug to be fixed here: the
# producer's `tr -d '"\\'` removed the structure an allowlist needs, so this control cannot be
# one. Phase B closes it at the producer. Asserting the recorded boundary — rather than an
# absolute — is what keeps the ADR and the Art. 30 bracket honest.
reset_fix; crash_loop_fixture "$HDRS_UNANTICIPATED"
assert_cause_contains "G2-3b denylist boundary is REAL (unanticipated header survives)" \
  ZOT_ALARM_CAUSE "UNANTICIPATED-HEADER-VALUE"

# --- G2-3c: the SECOND denylist limit, asserted as a measured boundary ----------------------
reset_fix; crash_loop_fixture "$HDRS_BARE_SPACED"
assert_cause_masks "G2-3c bare-form value IS masked up to the first space" \
  ZOT_ALARM_CAUSE "BARE-FIRST"
reset_fix; crash_loop_fixture "$HDRS_BARE_SPACED"
assert_cause_contains "G2-3c bare-form residual AFTER a space SURVIVES (recorded limit, not an absolute)" \
  ZOT_ALARM_CAUSE "BARE-SECOND-SURVIVES"

# --- Harness row (b), must-PASS: the OOM arm is untouched ----------------------------------
# The scrub must not corrupt arms that were never the problem.
reset_fix; oom_fixture
assert_cause_contains "G2-b OOM arm intact" ZOT_ALARM_CAUSE "OOM exit"

# --- Harness row (c), must-PASS: idempotency against post-Phase-B input --------------------
# Without this row Guard 2 stays green forever against an input population that stops existing
# the moment Phase B lands.
reset_fix; crash_loop_fixture "$ALREADY_REDACTED"
assert_cause_contains "G2-c idempotent on already-redacted input" ZOT_ALARM_CAUSE "REDACTED"

# --- Must-PASS: a tier-1 panic keeps its diagnostic header ---------------------------------
reset_fix; crash_loop_fixture "$PANIC_TIER1"
assert_cause_contains "G2-panic keeps 'panic:'" ZOT_ALARM_CAUSE "panic:"

# --- Chokepoint quantification: the NIC block leaves through the same function --------------
# The scrub covers NIC_CAUSE/NIC_DETAIL because a chokepoint is cheaper than an exception. The
# PROPERTY claims nothing about them ($NIC_ADDRS is `ip -4 -o addr show` output), but the arm
# must still be reachable and non-empty, or "we scrub it" is untestable.
reset_fix; crash_loop_fixture "$HDRS_COOKIE"
assert_field_nonempty "G2-nic verdict rides the crash-loop exit path" NIC_ALARM_VERDICT
reset_fix; crash_loop_fixture "$HDRS_COOKIE"
assert_field_nonempty "G2-nic cause rides the crash-loop exit path" NIC_ALARM_CAUSE

# --- Row 1 + Row 2: the scrub lives AT the chokepoint --------------------------------------
# Row 1 (remove the scrub) is covered behaviourally above. This is the structural complement:
# the scrub must be applied inside emit_and_exit, so a NEW arm assigning CAUSE is covered by
# construction. Anchored on the function-call shape, never a bare token that a comment can carry.
assert_struct "G2-1 scrub helper defined" "$CHECKER" '^scrub_public\(\) \{' 1
assert_struct "G2-2 scrub applied at the emit chokepoint" "$CHECKER" '\$\(scrub_public ' 4

# --- Row 4: the workflow publication boundary ----------------------------------------------
# AP-025: the script chokepoint protects one consumer of stdout; the workflow is a SECOND
# producer into $out. Both layers, or the property is only half true.
assert_struct "G2-4 workflow boundary scrubs before publication" "$WORKFLOW" 'scrub_public|SCRUB_CRED_HDRS' 1

# --- Tier provenance (#7500 task 2.5/2.7) --------------------------------------------------
# ADR-166: never name an unmeasured cause. The producer already tags which of its four tiers
# produced the sample, but nothing rendered that tag -- so a tier-4 `fallback` sample (a routine
# HTTP/gc line that names NO cause) was published in the same "zot_last_err tail:" framing as a
# tier-1 panic. The workflow parses only ^ZOT_ALARM_CAUSE=, so the tag has to travel INSIDE it.

# A matched diagnostic line may be presented as diagnostic.
reset_fix; crash_loop_fixture_src "panic" "$PANIC_TIER1"
assert_cause_contains "G2-tier1 names its tier" ZOT_ALARM_CAUSE "tier=panic"

# A tier-4 fallback sample must NOT be framed as a cause. This is the ~100%-of-exposure,
# ~0%-of-value tier the plan measured over a 21-hour crash loop.
reset_fix; crash_loop_fixture_src "fallback" "$HDRS_COOKIE"
assert_cause_contains "G2-tier4 refuses to present a fallback sample as a cause" \
  ZOT_ALARM_CAUSE "names NO cause"

# LEGACY ROWS -- the rule, recorded rather than left implicit. A row with no zot_last_err_src
# (a pre-#7247 emitter) is a THIRD state, not a missing fourth. Fail-open would present an
# unknown-provenance tail as a cause, which is the ADR-166 defect this change removes;
# fail-closed would discard a tail that may be the only evidence available. Neither: show the
# tail and say the provenance is unknown.
reset_fix; crash_loop_fixture "$PANIC_TIER1"
assert_cause_contains "G2-legacy row declares unknown provenance" ZOT_ALARM_CAUSE "PROVENANCE UNKNOWN"
reset_fix; crash_loop_fixture "$PANIC_TIER1"
assert_cause_contains "G2-legacy row still carries the tail" ZOT_ALARM_CAUSE "panic:"

# --- Row 6 / harness (a): the guard's own dispatch ------------------------------------------
# A suite whose helpers were never called reports 0 passed / 0 failed and exits 0 — which is
# byte-identical to a healthy run. These counters make "the loop ran" observable.
for _w in assert_cause_masks assert_cause_contains assert_struct assert_field_nonempty; do
  _u="USED_${_w}"
  if [[ "${!_u}" -lt 1 ]]; then
    printf '\n[FATAL] harness: %s was never dispatched — a wrapper that does not run asserts nothing.\n' "$_w" >&2
    printf 'cases=%s pass=%s fail=%s\n' "$CASES" "$PASS" "$FAIL"
    exit 1
  fi
done

# Directional transcript: conservation (PASS+FAIL == CASES) cannot see a MISROUTE, where a
# failing case increments pass(). The verdict string can.
_v_pass="${VERDICTS//F/}"; _v_fail="${VERDICTS//P/}"
if [[ "${#_v_pass}" -ne "$PASS" || "${#_v_fail}" -ne "$FAIL" ]]; then
  printf '\n[FATAL] harness: verdict transcript disagrees with the counters (P=%s F=%s vs pass=%s fail=%s).\n' \
    "${#_v_pass}" "${#_v_fail}" "$PASS" "$FAIL" >&2
  exit 1
fi

# Anti-vacuity floor. Reported with printf + exit, NEVER through fail() — a floor that calls the
# helper it backstops is disarmed by the same edit that disarms the helper (ADR-193).
EXPECTED_MIN=20
if [[ "$CASES" -lt "$EXPECTED_MIN" ]]; then
  printf '\n[FATAL] cardinality: only %s cases ran (expected >= %s) — a case was silently skipped.\n' \
    "$CASES" "$EXPECTED_MIN" >&2
  printf 'cases=%s pass=%s fail=%s\n' "$CASES" "$PASS" "$FAIL"
  exit 1
fi
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] conservation: pass+fail (%s) != cases (%s).\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi

printf '\ncases=%s pass=%s fail=%s\n' "$CASES" "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo "RESULT: FAIL ($FAIL/$CASES assertions failed)" >&2
  exit 1
fi
echo "RESULT: PASS ($PASS/$CASES assertions)"
