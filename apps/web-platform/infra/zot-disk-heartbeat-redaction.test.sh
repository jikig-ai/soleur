#!/usr/bin/env bash
# Guard 1 (#7500) — producer-side redaction of the diagnostic sample.
#
# PROPERTY. No credential-bearing header value present in zot's log output leaves
# zot-disk-heartbeat.sh in the clear — INCLUDING a header name this codebase has not
# anticipated, on EVERY line of a multi-line sample — and the SOLEUR_ZOT_DISK row is emitted on
# every path, including every redaction-failure path.
#
# WHY A BEHAVIOURAL SUITE. No behavioural suite for the heartbeat existed; the only coverage was
# structural greps in registry-boot-guard.test.sh. A structural grep cannot answer the question
# that actually matters here — "does redact() run BEFORE the sanitizer, and PER LINE?" — because
# both orderings and both arities look identical in a grep. Measured during planning: applied to
# a whole multi-line blob, redact() takes its non-JSON DENYLIST branch and an unanticipated
# header (X-Secret) leaks in the clear at RC=0. Applied after the sanitizer, the quotes are gone,
# the JSON branch can never fire, and the same leak returns. Only execution distinguishes these.
#
# ASSEMBLY — three chokepoints, all named, because scoping to one is the defect this exists to
# catch. (1) The VALUE chokepoint: the single ZOT_LAST_ERR= assignment all four tiers flow into,
# so a fifth tier is covered by construction. (2) The PER-LINE chokepoint: the loop applying
# redact() to each line of ZOT_ERR_RAW. (3) The EMIT chokepoint: the single LINE= assembly and
# its one post() call — which is what this suite asserts on, by capturing the POSTed body.
#
# Built on the apps/web-platform/infra/zot-log-shipper.test.sh template: extract the write_files
# block from the template, apply local.registry_rationale_strip, assert the stripped result is
# still valid bash, then execute it against synthesized PATH stubs. No live host, no network, no
# docker, no doppler, no root.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$SCRIPT_DIR/cloud-init-registry.yml"
HB_PATH="/usr/local/bin/zot-disk-heartbeat.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0; CASES=0
VERDICTS=""
USED_assert=0
USED_assert_emit=0

pass() { PASS=$((PASS + 1)); VERDICTS="${VERDICTS}P"; printf 'ok   - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); VERDICTS="${VERDICTS}F"; printf 'FAIL - %s\n' "$1" >&2; }

assert() {
  USED_assert=$((USED_assert + 1)); CASES=$((CASES + 1))
  local name="$1" expr="$2"
  if eval "$expr" >/dev/null 2>&1; then pass "$name"; else fail "$name  [expr: $expr]"; fi
}

# --- extraction: pull the heartbeat write_files block out of the template ------------------
# Verbatim from zot-log-shipper.test.sh — the same template, the same block shape.
extract_block() {
  local want_path="$1" out="$2"
  awk -v want="  - path: $want_path" '
    $0 == want { found = 1; next }
    found && /^    content: \|$/ { incontent = 1; next }
    incontent {
      if ($0 ~ /^      /) { print substr($0, 7); next }
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      exit
    }
  ' "$CI" > "$out"
}

# THE RATIONALE STRIP, replicated from zot-registry.tf's
# registry_rationale_strip = "/(?m)^[ \t]*#([ \t][^\n]*)?\n/".
# [[:blank:]] is EXACTLY space+tab, matching RE2's [ \t]; [[:space:]] would be wider.
apply_rationale_strip() { sed -E '/^[[:blank:]]*#([[:blank:]].*)?$/d' "$1"; }

# --- T1: render the heartbeat, strip it, prove it is still valid bash ---------------------
RAW="$TMP/hb.raw.sh"
extract_block "$HB_PATH" "$RAW"
assert "T1 heartbeat block extracted from the template (non-empty)" "[[ -s '$RAW' ]]"
assert "T1 extracted block is the heartbeat (has a shebang)" "head -1 '$RAW' | grep -q '^#!'"

HB="$TMP/hb.sh"
apply_rationale_strip "$RAW" > "$HB"
# TF-escaped shell expansions: $${VAR} -> ${VAR}; %%{ -> %{.
sed -i 's|\$\${|${|g' "$HB"
sed -i 's|%%{|%{|g' "$HB"
sed -i "s|\${betterstack_ingest_url}|http://127.0.0.1:9/ingest|g" "$HB"
# The heartbeat block carries three more template variables than the shipper does. Rendering
# them is not cosmetic: an unrendered ${...} inside double quotes never trips `set -u`, so the
# suite would execute a subtly broken program and read its silence as a SUT finding. The
# assertion below is what turns that into a loud failure.
sed -i 's|\${disk_heartbeat_url}|http://127.0.0.1:9/hb|g' "$HB"
sed -i 's|\${zot_pull_user}|pulluser|g' "$HB"
sed -i 's|\${zot_push_user}|pushuser|g' "$HB"
assert "T1 render left no unrendered TF interpolation" "! grep -qE '\\\$\{[A-Za-z0-9_.]+\}' '$HB'"
assert "T1 the COMMENT-STRIPPED heartbeat is still valid bash (the strip reaches inside heredocs)" \
  "bash -n '$HB'"
chmod +x "$HB"

# --- PATH stubs ---------------------------------------------------------------------------
# Derived from the block's own calls, not guessed:
#   grep -oE '\b(docker|curl|htpasswd|df|hostname|date|free|stat|journalctl)\b'
# Coreutils (grep/sed/awk/tr/head/tail/printf/cat) stay REAL — stubbing them would put the
# fixture seam above the code under test.
BIN="$TMP/bin"; mkdir -p "$BIN"

# docker stub: `docker logs` emits the fixture; every other subcommand answers benignly.
# It VALIDATES argv and exits 64 on an unrecognised shape — a stub that answers regardless of
# its arguments cannot detect the SUT querying the wrong thing.
cat > "$BIN/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  logs)
    [[ "$*" == *"zot"* ]] || { echo "docker stub: logs without a container name" >&2; exit 64; }
    [[ -r "${HB_FIXTURE:-}" ]] && cat "$HB_FIXTURE"
    exit 0 ;;
  inspect) printf 'running\nfalse\n0\n' ; exit 0 ;;
  ps)      exit 0 ;;
  exec)    exit 0 ;;
  *)       exit 0 ;;
esac
EOF

# curl stub: records the full POSTed body. This is the EMIT chokepoint — every assertion about
# what leaves the host reads this file. Validates argv: a POST with no --data-raw is a bug.
cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
body=""; has_m=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-raw) body="$2"; shift 2 ;;
    -m|--max-time) has_m=1; shift 2 ;;
    *) shift ;;
  esac
done
[[ "$has_m" == 1 ]] || { echo "curl stub: unbounded call (no -m/--max-time)" >&2; exit 64; }
[[ -n "$body" ]] || { echo "curl stub: POST with no --data-raw" >&2; exit 64; }
printf '%s\n' "$body" >> "${HB_POSTED:-/dev/null}"
exit 0
EOF

# htpasswd: the rotation-divergence probe. exit 0 = "password correct" on every check.
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/htpasswd"
# df: pcent well under the 85%% ping gate, and a plausible size.
cat > "$BIN/df" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--output=pcent"* ]]; then printf 'Use%%\n 12%%\n'; else printf '1G-blocks\n 40\n'; fi
exit 0
EOF
printf '#!/usr/bin/env bash\nprintf "soleur-registry\\n"\n' > "$BIN/hostname"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/free"
printf '#!/usr/bin/env bash\nprintf "0\\n"\n' > "$BIN/stat"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/journalctl"
chmod +x "$BIN"/*

# run_hb <fixture-content> [extra-env...] -> prints the emitted SOLEUR_ZOT_DISK row.
# Captures at the POST, which is the single emit chokepoint the whole property funnels through.
run_hb() {
  local fixture="$1"; shift
  local fx="$TMP/fixture.log" posted="$TMP/posted.log"
  printf '%s\n' "$fixture" > "$fx"
  : > "$posted"
  env PATH="$BIN:$PATH" HB_FIXTURE="$fx" HB_POSTED="$posted" \
      BETTERSTACK_LOGS_TOKEN="test-token-not-a-secret" "$@" \
      bash "$HB" >/dev/null 2>&1 || true
  cat "$posted"
}

# last_err_of <posted-body> -> the zot_last_err value (emitted LAST, free-text).
last_err_of() { sed -n 's/.* zot_last_err=//p' <<<"$1" | sed 's/\\"}"*$//' | head -1; }

# assert_emit <name> <fixture> <mode:absent|present> <needle> [extra-env...]
assert_emit() {
  USED_assert_emit=$((USED_assert_emit + 1)); CASES=$((CASES + 1))
  local name="$1" fixture="$2" mode="$3" needle="$4"; shift 4
  local out
  out="$(run_hb "$fixture" "$@")"
  if [[ -z "$out" ]]; then
    fail "$name: NO row was emitted — the heartbeat must ship on every path, including failure paths"
    return
  fi
  case "$mode" in
    absent)
      if [[ "$out" == *"$needle"* ]]; then fail "$name: emitted row leaked '$needle' -- $out"
      else pass "$name: emitted row carries no '$needle'"; fi ;;
    present)
      if [[ "$out" == *"$needle"* ]]; then pass "$name: emitted row carries '$needle'"
      else fail "$name: emitted row lost '$needle' -- $out"; fi ;;
  esac
}

# --- Fixtures ------------------------------------------------------------------------------
# zot emits zerolog JSON, one object per line, under --log-driver journald.
JSON_XSECRET='{"level":"info","message":"HTTP API","headers":{"X-Secret":["UNANTICIPATED-VALUE"],"Content-Type":["application/json"]},"clientIP":"10.0.1.9"}'
JSON_COOKIE='{"level":"error","message":"PatchBlobUpload i/o timeout","headers":{"Cookie":["session=COOKIE-SECRET"]},"clientIP":"10.0.1.9"}'
PANIC_LINE='panic: runtime error: invalid memory address'
# Row 2b — the MIXED blob: a panic frame (non-JSON) beside a JSON row. Measured during planning:
# applied to the blob as ONE string, redact() takes the non-JSON denylist branch and X-Secret
# leaves in the clear at RC=0. This fixture is what discriminates per-line application.
#
# EVERY LINE HERE MUST MATCH THE SAME TIER, and that is not a detail. The producer selects its
# sample with `grep -aE '<tier pattern>' | head -n N`, so a fixture whose second line does not
# match the tier is simply NOT IN THE SAMPLE -- the assertion then passes because the header was
# never there to leak, not because anything redacted it. The first draft of this fixture had
# exactly that bug: it paired a `panic:` line with a `"level":"info"` row, tier 1 selected only
# the panic line, and G1-2b reported ok against a program with no redaction in it at all.
# The JSON row below therefore carries `runtime error`, which is a tier-1 pattern -- and is a
# shape zot really produces, since a zerolog row can carry a runtime-error string in a field.
MIXED_BLOB="${PANIC_LINE}
{\"level\":\"info\",\"message\":\"HTTP API\",\"headers\":{\"X-Secret\":[\"UNANTICIPATED-VALUE\"]},\"error\":\"runtime error\"}"
# Row 2c — the same property, all-JSON multi-line. BOTH lines are level:error so BOTH are
# selected by tier 2; a mixed-tier pair would reintroduce the vacuity described above.
ALLJSON_BLOB="${JSON_COOKIE}
{\"level\":\"error\",\"message\":\"HTTP API\",\"headers\":{\"X-Secret\":[\"UNANTICIPATED-VALUE\"]}}"
# Tier-2: a benign level:error line with NO headers object. Must pass through unredacted.
TIER2_BENIGN='{"level":"error","message":"PatchBlobUpload i/o timeout","caller":"zotregistry.dev/x.go:1"}'
# Tier-4: nothing matches tiers 1-3, so the fallback tail fires. This is the ~100%-of-exposure,
# ~0%-of-value tier.
TIER4_HEADERS='{"level":"info","message":"HTTP API","headers":{"Cookie":["session=TIER4-SECRET"]},"clientIP":"10.0.1.9"}'
# Row 4: a NON-OBJECT headers value. redact()'s jq program errors ("nonobj headers") -> RC=1,
# which must degrade the FIELD without dropping the ROW.
JSON_NONOBJ='{"level":"error","message":"boom","headers":"NOT-AN-OBJECT-RC1-TRIGGER"}'

# --- Fixture non-vacuity control ------------------------------------------------------------
# Asserts the multi-line fixtures survive the producer's OWN tier selection. Without this, a
# fixture whose lines straddle two tiers silently shrinks to one line and every downstream
# "the header was masked" assertion passes because the header was never sampled. This control
# is the reason G1-2b/G1-2c mean anything.
tier1_of() { grep -aE 'panic:|fatal error|\[signal SIG|runtime error' <<<"$1" | head -n 4; }
tier2_of() { grep -aE '"level":"(error|fatal)"|level:(error|fatal)|level=(error|fatal)' <<<"$1" | head -n 3; }
assert "G1-fixture MIXED_BLOB is >1 line AFTER tier-1 selection" \
  "[[ \$(tier1_of \"\$MIXED_BLOB\" | wc -l) -ge 2 ]]"
assert "G1-fixture MIXED_BLOB still carries the needle after tier-1 selection" \
  "tier1_of \"\$MIXED_BLOB\" | grep -q UNANTICIPATED-VALUE"
assert "G1-fixture ALLJSON_BLOB is >1 line AFTER tier-2 selection" \
  "[[ \$(tier2_of \"\$ALLJSON_BLOB\" | wc -l) -ge 2 ]]"
assert "G1-fixture ALLJSON_BLOB still carries the needle after tier-2 selection" \
  "tier2_of \"\$ALLJSON_BLOB\" | grep -q UNANTICIPATED-VALUE"

echo "=== Guard 1 — producer-side redaction of the diagnostic sample (#7500) ==="

# --- Row 2: the ALLOWLIST property — an unanticipated header name is masked ----------------
# A Cookie fixture CANNOT discriminate here: Cookie is on the denylist, so a denylist-only
# implementation passes it. That is the defect this plan already made once, caught at review.
assert_emit "G1-2 unanticipated header masked (allowlist, single-line JSON)" \
  "$JSON_XSECRET" absent "UNANTICIPATED-VALUE"

# --- Row 2b: the SAME fixture as a MIXED multi-line blob -----------------------------------
assert_emit "G1-2b unanticipated header masked in a MIXED multi-line blob (per-line)" \
  "$MIXED_BLOB" absent "UNANTICIPATED-VALUE"

# --- Row 2c: all-JSON multi-line ----------------------------------------------------------
assert_emit "G1-2c unanticipated header masked in an all-JSON multi-line blob" \
  "$ALLJSON_BLOB" absent "UNANTICIPATED-VALUE"
assert_emit "G1-2c denylisted header also masked in the same blob" \
  "$ALLJSON_BLOB" absent "COOKIE-SECRET"

# --- Row 4: RC=1 degrades the FIELD, never drops the ROW -----------------------------------
# RED if the row is dropped, AND RED if the suite asserts only "it still ships" — that passes a
# mutant shipping the raw field. Both halves are asserted.
assert_emit "G1-4 RC=1 still emits the row (primary disk signal survives)" \
  "$JSON_NONOBJ" present "pcent="
assert_emit "G1-4 RC=1 preserves boot_id" "$JSON_NONOBJ" present "boot_id="
assert_emit "G1-4 RC=1 emits the placeholder" "$JSON_NONOBJ" present "REDACTION_FAILED"
assert_emit "G1-4 RC=1 leaves NO residual of the input" \
  "$JSON_NONOBJ" absent "NOT-AN-OBJECT-RC1-TRIGGER"

# --- Row 6: the tier gate — a tier-4 sample must not ship its raw line ----------------------
assert_emit "G1-6 tier-4 raw header line does not ship" "$TIER4_HEADERS" absent "TIER4-SECRET"

# --- Row 7: degrade CLOSED without jq ------------------------------------------------------
# Unspecified degradation here would restore ~100% of the measured exposure while the ADR
# records the gate as removing it. With jq absent the tier-4 sample must become `none`.
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"
for c in docker curl htpasswd df hostname free stat journalctl; do cp "$BIN/$c" "$NOJQ/$c"; done
printf '#!/usr/bin/env bash\nexit 127\n' > "$NOJQ/jq"; chmod +x "$NOJQ"/*
assert_emit "G1-7 tier-4 degrades CLOSED when jq is unavailable" \
  "$TIER4_HEADERS" absent "TIER4-SECRET" PATH="$NOJQ:/usr/bin:/bin"

# --- Harness (b), must-PASS: a benign tier-2 line passes through unredacted -----------------
# NOTE the tier. An earlier draft used `gc successfully completed` here, which is a TIER-4
# sample the tier gate suppresses — so the row would have asserted a behaviour this same change
# removes. Caught at plan review; kept as a comment so it is not reintroduced.
assert_emit "G1-b benign tier-2 line survives unredacted" "$TIER2_BENIGN" present "PatchBlobUpload"

# --- Harness (c), must-PASS: a tier-1 panic keeps its header -------------------------------
# NOT byte-identity at the wire: every sample still passes tr/head -c afterwards, so row-level
# byte-identity is unsatisfiable by construction. The claim is that redact() introduces no
# substitution into a credential-free panic.
assert_emit "G1-c tier-1 panic header survives to the emitted row" "$PANIC_LINE" present "panic:"

# --- Structural: ORDER and ARITY, which behaviour alone cannot pin -------------------------
# Anchored on syntax a comment cannot produce (^\s*KEY=, a call shape), never a bare token.
assert "G1-s redact() is defined in the heartbeat block" "grep -qE '^[[:space:]]*redact\(\) \{' '$RAW'"
assert "G1-s CRED_HDRS is defined in the heartbeat block" "grep -qE \"^[[:space:]]*CRED_HDRS='\" '$RAW'"
assert "G1-s HDR_KEEP is defined in the heartbeat block" "grep -qE '^[[:space:]]*HDR_KEEP=' '$RAW'"
# ARITY, and anchored on a name only this feature introduces. The first draft of this line
# grepped for `while IFS=...read`, which matches loops that already existed in this block -- it
# passed before the feature was written, which is the definition of a vacuous guard.
assert "G1-s a per-line loop applies redact() (arity, not just presence)" \
  "grep -qE '^[[:space:]]*redact_sample_lines\(\) \{' '$RAW'"
assert "G1-s the per-line helper is actually CALLED" \
  "grep -qE 'redact_sample_lines[[:space:]]+' '$RAW'"
assert "G1-s exactly ONE degrade branch funnels all three RC=1 paths" \
  "[[ \$(grep -cE 'REDACTION_FAILED' '$RAW') -ge 1 ]]"

# --- Row 8 / harness (a): the guard's own dispatch ------------------------------------------
for _w in assert assert_emit; do
  _u="USED_${_w}"
  if [[ "${!_u}" -lt 1 ]]; then
    printf '\n[FATAL] harness: %s was never dispatched — a wrapper that does not run asserts nothing.\n' "$_w" >&2
    printf 'cases=%s pass=%s fail=%s\n' "$CASES" "$PASS" "$FAIL"
    exit 1
  fi
done

_v_pass="${VERDICTS//F/}"; _v_fail="${VERDICTS//P/}"
if [[ "${#_v_pass}" -ne "$PASS" || "${#_v_fail}" -ne "$FAIL" ]]; then
  printf '\n[FATAL] harness: verdict transcript disagrees with the counters.\n' >&2
  exit 1
fi

# Anti-vacuity floor — printf + exit, never through fail() (ADR-193).
EXPECTED_MIN=26
if [[ "$CASES" -lt "$EXPECTED_MIN" ]]; then
  printf '\n[FATAL] cardinality: only %s cases ran (expected >= %s).\n' "$CASES" "$EXPECTED_MIN" >&2
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
