#!/usr/bin/env bash
# Hermetic tests for scripts/check-deploy-script-parity.sh (#9151). No network:
# the web-1 status arm reads --status-json-file, the Better Stack arm reads
# --bs-rows-file. The repo sha is the REAL sha of the checked-out ci-deploy.sh —
# fixtures are generated against it at test time, never hardcoded.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$REPO_ROOT/scripts/check-deploy-script-parity.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"
pass=0; fail=0; cases=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

[[ -x "$SUT" || -r "$SUT" ]] || { echo "FATAL: $SUT missing" >&2; exit 2; }
S="$(mktemp -d -t depparity.XXXXXXXX)" || exit 2
trap 'rm -rf "$S"' EXIT

REPO_SHA="$(sha256sum "$REPO_ROOT/apps/web-platform/infra/ci-deploy.sh" | cut -d' ' -f1)"
OLD_SHA="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
[[ "$REPO_SHA" != "$OLD_SHA" ]] || { echo "FATAL: fixture collision" >&2; exit 2; }

# Host set from the real variables.tf (web-1 → soleur-web-platform, web-2 → soleur-web-2).
mk_status() { printf '{"ci_deploy_sha256":"%s","host_id":"%s"}' "$1" "$2" > "$S/status.json"; }
mk_rows()  { : > "$S/rows.json"; }
add_row()  { # <host_name> <sha> <ident> <dt>
  printf '{"dt":"%s","raw":"{\\"SYSLOG_IDENTIFIER\\":\\"%s\\",\\"host_name\\":\\"%s\\",\\"message\\":\\"DEPLOY_SCRIPT_SHA sha256=%s\\"}"}\n' \
    "$4" "$3" "$1" "$2" >> "$S/rows.json"
}
run() { bash "$SUT" "$@" >"$S/out" 2>"$S/err"; RC=$?; }

# C0: --self-test needs no credentials or network.
cases=$((cases + 1)); run --self-test
if [[ "$RC" -eq 0 && "$(<"$S/out")" == *"self-test: ok"* ]]; then ok "C0: --self-test is a no-network pass"
else no "C0: --self-test (rc=$RC) $(<"$S/err")"; fi

# C1: happy path — matching sha on every arm.
cases=$((cases + 1))
mk_status "$REPO_SHA" "hetzner-1"; mk_rows
add_row "soleur-web-platform" "$REPO_SHA" "ci-deploy" "2026-09-30 10:00:00.000"
add_row "soleur-web-2"         "$REPO_SHA" "ci-deploy" "2026-09-30 10:01:00.000"
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json"
if [[ "$RC" -eq 0 && "$(<"$S/out")" == *"PARITY"* ]]; then ok "C1: matching sha on all arms is PARITY"
else no "C1: happy path (rc=$RC) $(<"$S/out") $(<"$S/err")"; fi

# C2: repo-ahead drift — web-2's newest row is the old sha.
cases=$((cases + 1))
mk_status "$REPO_SHA" "hetzner-1"; mk_rows
add_row "soleur-web-platform" "$REPO_SHA" "ci-deploy" "2026-09-30 10:00:00.000"
add_row "soleur-web-2"         "$OLD_SHA"  "ci-deploy" "2026-09-30 10:01:00.000"
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json"
if [[ "$RC" -ne 0 && "$(<"$S/err")" == *"soleur-web-2"* ]]; then ok "C2: web-2 stale-sha row is DRIFT, named"
else no "C2: stale row (rc=$RC) $(<"$S/out") $(<"$S/err")"; fi

# C3: newest-row-wins — an OLD sha followed by the NEW sha on the same host is parity.
cases=$((cases + 1))
mk_status "$REPO_SHA" "hetzner-1"; mk_rows
add_row "soleur-web-platform" "$OLD_SHA"  "ci-deploy" "2026-09-29 09:00:00.000"
add_row "soleur-web-platform" "$REPO_SHA" "ci-deploy" "2026-09-30 10:00:00.000"
add_row "soleur-web-2"         "$REPO_SHA" "ci-deploy" "2026-09-30 10:01:00.000"
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json"
if [[ "$RC" -eq 0 ]]; then ok "C3: newest row per host wins (old row behind a new one is fine)"
else no "C3: newest-wins (rc=$RC) $(<"$S/out") $(<"$S/err")"; fi

# C4: a marker PRINTED by a non-ci-deploy emitter does not count.
cases=$((cases + 1))
mk_status "$REPO_SHA" "hetzner-1"; mk_rows
add_row "soleur-web-platform" "$REPO_SHA" "ci-deploy" "2026-09-30 10:00:00.000"
add_row "soleur-web-2"         "$REPO_SHA" "doppler"   "2026-09-30 10:01:00.000"
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json"
if [[ "$RC" -ne 0 && "$(<"$S/err")" == *"soleur-web-2"* ]]; then ok "C4: wrong-emitter rows are ignored (missing, not parity)"
else no "C4: emitter isolation (rc=$RC) $(<"$S/out") $(<"$S/err")"; fi

# C5: missing BS row for a host is DRIFT unless --allow-missing-bs.
cases=$((cases + 1))
mk_status "$REPO_SHA" "hetzner-1"; mk_rows
add_row "soleur-web-platform" "$REPO_SHA" "ci-deploy" "2026-09-30 10:00:00.000"
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json"
if [[ "$RC" -ne 0 && "$(<"$S/err")" == *"no DEPLOY_SCRIPT_SHA row for soleur-web-2"* ]]; then
  ok "C5a: missing row for web-2 is DRIFT"
else no "C5a: missing row (rc=$RC) $(<"$S/err")"; fi
cases=$((cases + 1))
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json" --allow-missing-bs
if [[ "$RC" -eq 0 && "$(<"$S/out")" == *"WARN(bs)"* ]]; then ok "C5b: --allow-missing-bs downgrades to WARN"
else no "C5b: allow-missing (rc=$RC) $(<"$S/out") $(<"$S/err")"; fi

# C6: status body lacking ci_deploy_sha256 (old cat-deploy-state.sh) is DRIFT.
cases=$((cases + 1))
printf '{"host_id":"hetzner-1"}' > "$S/status.json"; mk_rows
add_row "soleur-web-platform" "$REPO_SHA" "ci-deploy" "2026-09-30 10:00:00.000"
add_row "soleur-web-2"         "$REPO_SHA" "ci-deploy" "2026-09-30 10:01:00.000"
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json"
if [[ "$RC" -ne 0 && "$(<"$S/err")" == *"lacks ci_deploy_sha256"* ]]; then ok "C6: missing status field is DRIFT (old reporter)"
else no "C6: missing field (rc=$RC) $(<"$S/err")"; fi

# C7: status sha mismatch is DRIFT even when the BS arm is clean.
cases=$((cases + 1))
mk_status "$OLD_SHA" "hetzner-1"; mk_rows
add_row "soleur-web-platform" "$REPO_SHA" "ci-deploy" "2026-09-30 10:00:00.000"
add_row "soleur-web-2"         "$REPO_SHA" "ci-deploy" "2026-09-30 10:01:00.000"
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json"
if [[ "$RC" -ne 0 && "$(<"$S/err")" == *"ci_deploy_sha256=$OLD_SHA"* ]]; then ok "C7: status sha mismatch is DRIFT"
else no "C7: status mismatch (rc=$RC) $(<"$S/err")"; fi

# C8: a third web host in var.web_hosts widens the check — mutation-proven by the
# derivation being exercised, not by editing the repo: a rows file covering a
# synthetic third name can only PARITY-pass if the derived set asks for it.
# (The real test is that absent derived hosts fail; C5a already proves web-2 is
# independently asserted rather than the loop collapsing to one host.)
cases=$((cases + 1))
mk_status "$REPO_SHA" "hetzner-1"; mk_rows
add_row "soleur-web-platform" "$REPO_SHA" "ci-deploy" "2026-09-30 10:00:00.000"
add_row "soleur-web-2"         "$REPO_SHA" "ci-deploy" "2026-09-30 10:01:00.000"
add_row "soleur-web-3"         "$REPO_SHA" "ci-deploy" "2026-09-30 10:02:00.000"
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json"
if [[ "$RC" -eq 0 ]]; then ok "C8: extra (non-derived) host rows are inert — no over-reach"
else no "C8: extra rows (rc=$RC) $(<"$S/err")"; fi

# C9: malformed row lines are tolerated, not fatal.
cases=$((cases + 1))
mk_status "$REPO_SHA" "hetzner-1"; mk_rows
printf 'not-json-at-all\n{"dt":"x","raw":"still-not-json"}\n' >> "$S/rows.json"
add_row "soleur-web-platform" "$REPO_SHA" "ci-deploy" "2026-09-30 10:00:00.000"
add_row "soleur-web-2"         "$REPO_SHA" "ci-deploy" "2026-09-30 10:01:00.000"
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json"
if [[ "$RC" -eq 0 ]]; then ok "C9: malformed rows are skipped, valid rows still adjudicated"
else no "C9: malformed rows (rc=$RC) $(<"$S/err")"; fi

# C10: both arm-selectors off is a usage error — never a vacuous PARITY.
cases=$((cases + 1))
run --status-only --bs-only
if [[ "$RC" -eq 2 && "$(<"$S/err")" == *"no arms enabled"* ]]; then ok "C10: --status-only + --bs-only refuses (exit 2)"
else no "C10: both-arms-off (rc=$RC) $(<"$S/out") $(<"$S/err")"; fi

# C11: a missing fixture file is FATAL (exit 2), not a skipped arm.
cases=$((cases + 1))
run --status-json-file "$S/does-not-exist.json"
if [[ "$RC" -eq 2 && "$(<"$S/err")" == *"missing or empty"* ]]; then ok "C11: missing --status-json-file refuses (exit 2)"
else no "C11: missing fixture (rc=$RC) $(<"$S/err")"; fi

# C12: an EMPTY --bs-rows-file is FATAL too (an empty rows file would sweep zero
# evidence behind whatever the other arm said).
cases=$((cases + 1))
mk_status "$REPO_SHA" "hetzner-1"; : > "$S/empty-rows.json"
run --status-json-file "$S/status.json" --bs-rows-file "$S/empty-rows.json"
if [[ "$RC" -eq 2 && "$(<"$S/err")" == *"missing or empty"* ]]; then ok "C12: empty --bs-rows-file refuses (exit 2)"
else no "C12: empty rows fixture (rc=$RC) $(<"$S/err")"; fi

# C13: a .raw that decodes to a NON-OBJECT (number) must not abort the jq stream —
# rows before AND after it are still adjudicated (the poison row sits between two
# valid rows, newest for its host is the later one).
cases=$((cases + 1))
mk_status "$REPO_SHA" "hetzner-1"; mk_rows
add_row "soleur-web-platform" "$OLD_SHA"  "ci-deploy" "2026-09-29 09:00:00.000"
printf '{"dt":"2026-09-29 12:00:00.000","raw":"5"}\n' >> "$S/rows.json"
add_row "soleur-web-platform" "$REPO_SHA" "ci-deploy" "2026-09-30 10:00:00.000"
add_row "soleur-web-2"         "$REPO_SHA" "ci-deploy" "2026-09-30 10:01:00.000"
run --status-json-file "$S/status.json" --bs-rows-file "$S/rows.json"
if [[ "$RC" -eq 0 ]]; then ok "C13: a non-object .raw is skipped, not a stream abort"
else no "C13: non-object raw (rc=$RC) $(<"$S/err")"; fi

if (( pass + fail != cases )); then
  printf '[FATAL] accounting: pass+fail (%d) != cases (%d)\n' "$((pass + fail))" "$cases" >&2; exit 1
fi
FLOOR=15
if (( cases < FLOOR )); then
  printf '[FATAL] anti-vacuity floor: %d cases ran, expected >= %d\n' "$cases" "$FLOOR" >&2; exit 1
fi
echo "=== check-deploy-script-parity: $pass passed, $fail failed ($cases cases) ==="
[[ "$fail" -eq 0 ]]
