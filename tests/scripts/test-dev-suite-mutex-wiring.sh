#!/usr/bin/env bash
# Wiring gate: the dev-suite advisory mutex (#7964) only serializes the
# tenant-integration critical section if the WORKFLOW wires it correctly —
# a green unit suite says nothing about YAML it never reads.
#
# What this pins (anchored, not bare tokens — a comment can satisfy a bare
# token, only emitted lines can satisfy these):
#   W1 acquire step invokes scripts/dev-suite-mutex.sh acquire under doppler
#   W2 release step invokes ... release under `if: always()` and NO doppler
#      (release must not depend on the secret store; comment at the step
#      explains why)
#   W3 ordering: acquire < drift probe < apply migrations < tenant tests <
#      post-section re-probe < release — a step moved outside the window
#      breaks the serialization it exists for
#   W4 detect-changes anchors scripts/dev-suite-mutex.sh and the probe
#      action dir — a mutex/probe edit must trigger this suite
#   W5 timeout-minutes vs the script's HOLD_S/WAIT_S defaults — the
#      HOLD_S > job-timeout coupling lives in comments only; this row pins
#      it as arithmetic
#   W6 identity env puts run_id FIRST in both acquire and release steps
#      (application_name truncates tail-first at 63 bytes)
#   W7 drift probe + post-section re-probe carry fail-on-ledger-drift scoped
#      to authoritative events (not bare `!= 'pull_request'`)
#   W8 the scheduled cron forwards fail-on-ledger-drift: 'true'
#
# Idiom follows tests/scripts/test-registry-d10-workflow-wiring.sh:
# `set -uo pipefail` + comment-stripped greps + anchored assertions +
# an anti-vacuity exact-count floor.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WF="${ROOT}/.github/workflows/tenant-integration.yml"
SCHED="${ROOT}/.github/workflows/scheduled-dev-migration-drift.yml"
SUT="${ROOT}/scripts/dev-suite-mutex.sh"
ACTION="${ROOT}/.github/actions/dev-migration-drift-probe/action.yml"

passes=0
fails=0
_report() {
  if [[ "$2" == "ok" ]]; then passes=$((passes + 1)); printf '  ok   %s\n' "$1"
  else fails=$((fails + 1)); printf '  FAIL %s%s\n' "$1" "${3:+ — $3}"; fi
}

for f in "$WF" "$SCHED" "$SUT" "$ACTION"; do
  [[ -f "$f" ]] || { printf 'harness: missing %s\n' "$f" >&2; exit 2; }
done

_strip() { grep -vE '^[[:space:]]*#'; }

# Stripped bodies materialized ONCE — `_strip | grep -q` in an `if` is a
# SIGPIPE race under pipefail (grep -q exits on first match and kills the
# upstream grep mid-write, propagating 141).
WF_BODY="$(_strip < "$WF")"
SCHED_BODY="$(_strip < "$SCHED")"

# _step_body <name> — the `- name: <name>` step's lines up to the next step
# boundary or job key, comments stripped.
_step_body() {
  awk -v want="$1" '
    index($0, "      - name: " want) == 1 { inb = 1; print; next }
    inb && /^      - name: / { inb = 0 }
    inb && /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ { inb = 0 }
    inb { print }
  ' "$WF" | _strip
}

# _line_of <pattern> — first matching line number in the comment-stripped
# workflow, or empty.
_line_of() { _strip < "$WF" | grep -nE "$1" | head -1 | cut -d: -f1; }

ACQ_BODY="$(_step_body 'Acquire dev-suite mutex')"
REL_BODY="$(_step_body 'Release dev-suite mutex')"
REPROBE_BODY="$(_step_body 'Re-probe dev-vs-main migration drift (post-section)')"

# ── W1: acquire step runs the script under doppler ───────────────────────────
if [[ -n "$ACQ_BODY" ]] \
  && grep -qE 'doppler run -p soleur -c dev_scheduled' <<<"$ACQ_BODY" \
  && grep -qE 'bash scripts/dev-suite-mutex\.sh acquire' <<<"$ACQ_BODY"; then
  _report "W1 acquire step invokes dev-suite-mutex.sh acquire under dev_scheduled" ok
else
  _report "W1 acquire step invokes dev-suite-mutex.sh acquire under dev_scheduled" fail "step body missing or miswired"
fi

# ── W2: release under if: always(), local-only (no doppler) ─────────────────
if [[ -n "$REL_BODY" ]] \
  && grep -qE '^[[:space:]]*if: always\(\)' <<<"$REL_BODY" \
  && grep -qE 'bash scripts/dev-suite-mutex\.sh release' <<<"$REL_BODY"; then
  _report "W2 release step runs under if: always() and calls release" ok
else
  _report "W2 release step runs under if: always() and calls release" fail "missing if: always() or the release call"
fi
if grep -qE 'doppler' <<<"$REL_BODY"; then
  _report "W2 release step is local-only (no doppler dependency)" fail "doppler appears in the release step — release would depend on the secret store"
else
  _report "W2 release step is local-only (no doppler dependency)" ok
fi

# ── W3: the critical-section ordering ────────────────────────────────────────
ln_acquire=$(_line_of 'Acquire dev-suite mutex')
ln_probe=$(_line_of 'Detect dev-vs-main migration drift')
ln_apply=$(_line_of 'Apply migrations to dev')
ln_tests=$(_line_of 'Run tenant-isolation tests')
ln_reprobe=$(_line_of 'Re-probe dev-vs-main migration drift')
ln_release=$(_line_of 'Release dev-suite mutex')
if [[ -n "$ln_acquire" && -n "$ln_probe" && -n "$ln_apply" \
   && -n "$ln_tests" && -n "$ln_reprobe" && -n "$ln_release" \
   && "$ln_acquire" -lt "$ln_probe" && "$ln_probe" -lt "$ln_apply" \
   && "$ln_apply" -lt "$ln_tests" && "$ln_tests" -lt "$ln_reprobe" \
   && "$ln_reprobe" -lt "$ln_release" ]]; then
  _report "W3 ordering: acquire < probe < apply < tests < re-probe < release" ok
else
  _report "W3 ordering: acquire < probe < apply < tests < re-probe < release" fail \
    "lines: acq=$ln_acquire probe=$ln_probe apply=$ln_apply tests=$ln_tests reprobe=$ln_reprobe rel=$ln_release"
fi

# ── W4: detect-changes anchors ───────────────────────────────────────────────
if grep -qE 'scripts/dev-suite-mutex\\\.sh' <<<"$WF_BODY"; then
  _report "W4 detect-changes anchors scripts/dev-suite-mutex.sh" ok
else
  _report "W4 detect-changes anchors scripts/dev-suite-mutex.sh" fail "mutex edits would not trigger the suite"
fi
if grep -qE 'dev-migration-drift-probe/' <<<"$WF_BODY"; then
  _report "W4 detect-changes anchors the drift-probe action dir" ok
else
  _report "W4 detect-changes anchors the drift-probe action dir" fail "probe edits would not trigger the suite"
fi

# ── W5: HOLD_S/WAIT_S vs timeout-minutes — the comment-coupled budget as code ─
timeout_min=$(sed -n '/^  tenant-integration:/,/^  tenant-integration-required:/p' "$WF" | grep -oE 'timeout-minutes: [0-9]+' | head -1 | grep -oE '[0-9]+')
hold_s=$(grep -oE '^HOLD_S="\$\{DEV_SUITE_MUTEX_HOLD_S:-[0-9]+\}"' "$SUT" | grep -oE ':-[0-9]+' | grep -oE '[0-9]+')
wait_s=$(grep -oE '^WAIT_S="\$\{DEV_SUITE_MUTEX_WAIT_S:-[0-9]+\}"' "$SUT" | grep -oE ':-[0-9]+' | grep -oE '[0-9]+')
if [[ -n "$timeout_min" && -n "$hold_s" && -n "$wait_s" ]]; then
  _report "W5 extracted timeout-minutes=$timeout_min HOLD_S=$hold_s WAIT_S=$wait_s" ok
else
  _report "W5 extracted timeout-minutes/HOLD_S/WAIT_S" fail "extraction empty — the coupling check is vacuous without all three"
fi
if [[ -n "$timeout_min" && -n "$hold_s" ]] && (( hold_s > timeout_min * 60 )); then
  _report "W5 HOLD_S ($hold_s) exceeds the job timeout (${timeout_min}min) — holder outlives cancellation" ok
else
  _report "W5 HOLD_S ($hold_s) exceeds the job timeout (${timeout_min}min)" fail "holder would die at the pg_sleep ceiling mid-section — silent unserialization"
fi
if [[ -n "$timeout_min" && -n "$wait_s" ]] && (( wait_s + 300 < timeout_min * 60 )); then
  _report "W5 WAIT_S ($wait_s) leaves >=5min of section budget inside the job timeout" ok
else
  _report "W5 WAIT_S ($wait_s) leaves >=5min of section budget inside the job timeout" fail "a full-budget wait cannot leave a viable section window"
fi

# ── W6: run_id first in both identities ──────────────────────────────────────
ident_re='DEV_SUITE_MUTEX_IDENTITY: ti-\$\{\{ github\.run_id \}\}-\$\{\{ github\.ref_name \}\}'
if grep -qE "$ident_re" <<<"$ACQ_BODY" && grep -qE "$ident_re" <<<"$REL_BODY"; then
  _report "W6 acquire+release identities put run_id first (truncation-safe)" ok
else
  _report "W6 acquire+release identities put run_id first" fail "identity must lead with run_id — PGAPPNAME truncates at 63 bytes tail-first"
fi

# ── W7: fail-closed scoped to authoritative events on BOTH probes ────────────
probe_body="$(_step_body 'Detect dev-vs-main migration drift')"
failclosed_re="fail-on-ledger-drift: .*event_name == 'push'"
if grep -qE "$failclosed_re" <<<"$probe_body" && grep -qE "$failclosed_re" <<<"$REPROBE_BODY"; then
  _report "W7 both probes carry fail-on-ledger-drift scoped to authoritative events" ok
else
  _report "W7 both probes carry fail-on-ledger-drift scoped to authoritative events" fail "expected the push/main-dispatch-scoped expression, not bare != pull_request"
fi
if [[ -n "$REPROBE_BODY" ]] && grep -qE '^[[:space:]]*if: always\(\)' <<<"$REPROBE_BODY"; then
  _report "W7 post-section re-probe runs under if: always()" ok
else
  _report "W7 post-section re-probe runs under if: always()" fail "section-end drift would go unobserved on failure paths"
fi

# ── W8: scheduled cron forwards the flag ─────────────────────────────────────
if grep -qE "fail-on-ledger-drift: 'true'" <<<"$SCHED_BODY"; then
  _report "W8 scheduled cron forwards fail-on-ledger-drift: 'true'" ok
else
  _report "W8 scheduled cron forwards fail-on-ledger-drift: 'true'" fail "the only cadence-independent detector would stay warning-only"
fi

# ── Anti-vacuity assertion floor ─────────────────────────────────────────────
EXPECTED_ASSERTIONS=13
if [[ "$fails" -eq 0 && "$passes" -ne "$EXPECTED_ASSERTIONS" ]]; then
  printf '  FAIL anti-vacuity: %d assertions passed, expected exactly %d — rows were added, removed, or silenced\n' \
    "$passes" "$EXPECTED_ASSERTIONS"
  fails=$((fails + 1))
fi

printf '\n=== %d passed, %d failed ===\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
