#!/usr/bin/env bash
# Exit-code harness for hostname-mislabel-web1-6616.sh (#6616 AC5).
#
# The follow-through's exit code IS its authorization artifact (sweep-followthroughs.sh
# closes #6616 on 0, comments+leaves-open on 1, retries on anything else). The cardinal
# sin is a vacuous exit 0 that auto-closes #6616 while the collision is live or the source
# is dark. Every case here pins one arm of the identity/liveness decision tree.
#
# SEAM: the script reads its Better Stack rows from the query script named by
# HOSTNAME_MISLABEL_BQ (default ../betterstack-query.sh). We point it at a mock that emits
# a fixture file's contents (JSONEachRow) and exits a controllable code — no network, no creds.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/hostname-mislabel-web1-6616.sh"
fails=0
pass() { printf '  PASS: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -f "$MOCK" 2>/dev/null; rm -rf "$WORK" 2>/dev/null' EXIT
MOCK="$WORK/mock-bq.sh"

# make_mock <fixture-file> <exit-rc> — a betterstack-query.sh stand-in that ignores its SQL
# arg, prints the fixture verbatim, and exits <exit-rc>. rc!=0 simulates a creds/query fault.
make_mock() {
  local fixture="$1" rc="$2"
  cat > "$MOCK" <<MOCKEOF
#!/usr/bin/env bash
cat "$fixture"
exit $rc
MOCKEOF
  chmod 0755 "$MOCK"
}

# run_case <desc> <expected-rc> — assert the SUT exits expected-rc with the current MOCK.
run_case() {
  local desc="$1" expected="$2" rc=0 out
  out="$(HOSTNAME_MISLABEL_BQ="$MOCK" "$SUT" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$expected" ]]; then
    pass "$desc (exit=$rc)"
  else
    fail "$desc — expected exit=$expected got exit=$rc :: ${out:0:200}"
  fi
}

# Fixtures (synthesized JSONEachRow — cq-test-fixtures-synthesized-only). `n` type is
# irrelevant to the decision; kept as a bare number to mirror ClickHouse count() output.

# 1. FAIL — a web host (soleur-web-platform = web-1) wears soleur-inngest-prd; dedicated node live.
cat > "$WORK/fx-fail.json" <<'EOF'
{"host_name":"soleur-inngest-prd","host":"soleur-web-platform","n":14993}
{"host_name":"soleur-inngest-prd","host":"soleur-inngest","n":5096}
EOF
make_mock "$WORK/fx-fail.json" 0
run_case "web host emits dedicated host_name -> FAIL" 1

# 2. PASS — post-recreate: soleur-inngest-prd only on the dedicated node; web-1 corrected; marker present.
cat > "$WORK/fx-pass.json" <<'EOF'
{"host_name":"soleur-inngest-prd","host":"soleur-inngest","n":5096}
{"host_name":"soleur-web-platform","host":"soleur-web-platform","n":14000}
EOF
make_mock "$WORK/fx-pass.json" 0
run_case "identity holds + marker present -> PASS" 0

# 3. PASS — dedicated node early-boot generic-hostname noise must NOT false-FAIL (the #6616 discovery:
#    Ubuntu-2404-noble-64-minimal is kernel-only early boot, not a web host).
cat > "$WORK/fx-pass-noise.json" <<'EOF'
{"host_name":"soleur-inngest-prd","host":"soleur-inngest","n":5096}
{"host_name":"soleur-inngest-prd","host":"Ubuntu-2404-noble-64-minimal","n":16}
{"host_name":"soleur-web-platform","host":"soleur-web-platform","n":14000}
EOF
make_mock "$WORK/fx-pass-noise.json" 0
run_case "generic early-boot noise (non-web) does not false-FAIL -> PASS" 0

# 4. TRANSIENT — creds unset / query fault (mock exits non-zero). Never PASS, never FAIL.
make_mock "$WORK/fx-pass.json" 3
run_case "creds/query fault -> TRANSIENT" 2

# 5. TRANSIENT — schema-liveness marker absent (no soleur-inngest row) and no web collision.
cat > "$WORK/fx-nomarker.json" <<'EOF'
{"host_name":"soleur-web-platform","host":"soleur-web-platform","n":14000}
EOF
make_mock "$WORK/fx-nomarker.json" 0
run_case "no dedicated-node liveness marker -> TRANSIENT (not PASS)" 2

# 6. TRANSIENT — host column all-empty (schema drift / field renamed); the vacuous-GREEN guard.
cat > "$WORK/fx-empty.json" <<'EOF'
{"host_name":"soleur-inngest-prd","host":"","n":5096}
{"host_name":"","host":"","n":40640}
EOF
make_mock "$WORK/fx-empty.json" 0
run_case "host column all-empty -> TRANSIENT (no vacuous PASS)" 2

# 7. FAIL — web-2 collision too (both web identities are keyed), dedicated node live.
cat > "$WORK/fx-fail-web2.json" <<'EOF'
{"host_name":"soleur-inngest-prd","host":"soleur-web-2","n":88}
{"host_name":"soleur-inngest-prd","host":"soleur-inngest","n":5096}
EOF
make_mock "$WORK/fx-fail-web2.json" 0
run_case "web-2 also keyed as a collision -> FAIL" 1

# 8. FAIL takes PRECEDENCE over the liveness gate — a live web collision while the dedicated
#    node is momentarily silent must be FAIL (exit 1), NOT TRANSIENT. Pins the documented
#    ordering (FAIL block before the liveness gate); a "check source health first" reorder
#    would turn this into a signal-suppressing TRANSIENT retry and this arm reddens on it.
cat > "$WORK/fx-fail-noliveness.json" <<'EOF'
{"host_name":"soleur-inngest-prd","host":"soleur-web-platform","n":14993}
EOF
make_mock "$WORK/fx-fail-noliveness.json" 0
run_case "web collision with dedicated node silent -> FAIL (not TRANSIENT)" 1

# 9. TRANSIENT — zero rows entirely (source dark: mock emits an empty file, exit 0). Distinct
#    from arm 6 (rows present with empty host VALUES); this is the canonical no-rows case.
: > "$WORK/fx-zero.json"
make_mock "$WORK/fx-zero.json" 0
run_case "zero rows (source dark) -> TRANSIENT (not vacuous PASS)" 2

# 10. TRANSIENT — invalid window string (guard before any query).
rc=0; out="$(HOSTNAME_MISLABEL_BQ="$MOCK" HOSTNAME_MISLABEL_WINDOW="bogus" "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then pass "invalid HOSTNAME_MISLABEL_WINDOW -> TRANSIENT (exit=$rc)"
else fail "invalid window — expected exit=2 got exit=$rc :: ${out:0:160}"; fi

# 11. TRANSIENT — the query script itself missing/non-executable.
rc=0; out="$(HOSTNAME_MISLABEL_BQ="$WORK/does-not-exist.sh" "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then pass "missing/non-executable BQ -> TRANSIENT (exit=$rc)"
else fail "missing BQ — expected exit=2 got exit=$rc :: ${out:0:160}"; fi

# --- Parity battery: the three IaC-replicated pinned constants must still match their
#     authoritative sources. The asymmetric risk is a silent rename that converts the probe
#     into a rubber-stamp (false PASS auto-closing #6616 while the collision is live), so a
#     drift reddens CI here. Anchored on the production syntax (sed shape / resource-name value
#     / ternary), never a bare token that a comment could satisfy.
INFRA="$(cd "$HERE/../../apps/web-platform/infra" 2>/dev/null && pwd)"
if [[ -z "$INFRA" || ! -d "$INFRA" ]]; then
  fail "parity: could not locate apps/web-platform/infra from $HERE"
else
  # Extract the SUT's pinned constants (single source of truth for the assertions below).
  sut_mislabel="$(grep -E '^MISLABEL_HOST_NAME=' "$SUT" | sed -E 's/^[^"]*"([^"]+)".*/\1/')"
  sut_dedicated="$(grep -E '^DEDICATED_HOST=' "$SUT" | sed -E 's/^[^"]*"([^"]+)".*/\1/')"
  # SUT WEB_HOSTS array literal → newline-separated set.
  sut_web="$(grep -E '^WEB_HOSTS=' "$SUT" | grep -oE '"[^"]+"' | tr -d '"' | sort -u)"

  # (a) MISLABEL literal is the inngest-bootstrap sed replacement target.
  if grep -qF "sed -i 's|@@HOST_NAME@@|${sut_mislabel}|g'" "$INFRA/inngest-bootstrap.sh"; then
    pass "parity: MISLABEL_HOST_NAME '$sut_mislabel' matches inngest-bootstrap.sh sed"
  else
    fail "parity: MISLABEL_HOST_NAME '$sut_mislabel' NOT the inngest-bootstrap.sh sed target — IaC drift"
  fi

  # (b) DEDICATED_HOST is an exact hcloud_server resource-name value.
  if grep -qE "^[[:space:]]*name[[:space:]]*=[[:space:]]*\"${sut_dedicated}\"[[:space:]]*$" "$INFRA/inngest-host.tf"; then
    pass "parity: DEDICATED_HOST '$sut_dedicated' matches an inngest-host.tf resource name"
  else
    fail "parity: DEDICATED_HOST '$sut_dedicated' NOT a resource name in inngest-host.tf — IaC drift"
  fi

  # (c) Derive the EXPECTED web-host identity set from server.tf's ternary + var.web_hosts keys
  #     (web-1 → the ternary literal; every other key K → soleur-K), then require the SUT's
  #     WEB_HOSTS to equal it exactly. Catches both a renamed web-1 literal AND a grown fleet.
  web1_literal="$(grep -oE 'each\.key == "web-1" \? "[^"]+"' "$INFRA/server.tf" | head -1 | sed -E 's/.*\? "([^"]+)"/\1/')"
  web_keys="$(grep -oE '"web-[0-9]+"[[:space:]]*=[[:space:]]*\{' "$INFRA/variables.tf" | grep -oE 'web-[0-9]+' | sort -u)"
  expected_web=""
  if [[ -z "$web1_literal" || -z "$web_keys" ]]; then
    fail "parity: could not extract web-1 ternary literal / var.web_hosts keys from server.tf+variables.tf"
  else
    while IFS= read -r k; do
      [[ -z "$k" ]] && continue
      if [[ "$k" == "web-1" ]]; then expected_web+="${web1_literal}"$'\n'; else expected_web+="soleur-${k}"$'\n'; fi
    done <<< "$web_keys"
    expected_web="$(printf '%s' "$expected_web" | grep -v '^$' | sort -u)"
    exp_disp="$(printf '%s' "$expected_web" | tr '\n' ' ')"
    sut_disp="$(printf '%s' "$sut_web" | tr '\n' ' ')"
    if [[ "$sut_web" == "$expected_web" ]]; then
      pass "parity: WEB_HOSTS matches server.tf ternary + var.web_hosts keys [${exp_disp}]"
    else
      fail "parity: WEB_HOSTS drift — SUT pins [${sut_disp}] but IaC derives [${exp_disp}]"
    fi
  fi
fi

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails case(s)" >&2
  exit 1
fi
echo "OK: all hostname-mislabel-web1-6616 arms passed"
