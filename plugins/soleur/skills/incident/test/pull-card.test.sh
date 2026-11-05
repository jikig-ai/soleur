#!/usr/bin/env bash
# Coverage card for the incident skill pull. Synthesized fixtures only.
# No Doppler and no live readers. Headless stays skill prose: this file does
# not claim dry-run.sh implements --headless.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SKILL_DIR}/../../../.." && pwd)"

SKILL="${SKILL_DIR}/SKILL.md"
PRINTER="${SKILL_DIR}/scripts/pull-card.sh"
DRY_RUN="${SKILL_DIR}/scripts/dry-run.sh"
SENTINEL="${SKILL_DIR}/scripts/redact-sentinel.sh"
FIXTURE="${SCRIPT_DIR}/fixtures/pull-card-synthetic.json"
DRY_FIXTURE="${SCRIPT_DIR}/fixtures/dry-run-incident.json"
MARKER_TS="${REPO_ROOT}/apps/web-platform/server/git-lock-marker-telemetry.ts"

UUID_LIT='11111111-2222-4333-8444-555555555555'
IPV4_LIT='203.0.113.50'
EMAIL_LIT='fixture-pull@example.invalid'
TABLE='t520508_soleur_inngest_vector_prd_3_logs'

PASS=0
FAIL=0

# Byte-for-byte with plugins/soleur/test/test-helpers.sh. An inline case is not recognised.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

TMP_DIR="$(mktemp -d)"
assert_fixture_dir "$TMP_DIR"
trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM HUP

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

need_file() {
  if [[ -f "$1" ]]; then
    pass "present ${1##*/}"
  else
    fail "missing ${1##*/}"
  fi
}

# Fixed-string presence. The label is the needle.
has() {
  local needle="$1" file="$2"
  if grep -qF -- "$needle" "$file"; then
    pass "has ${needle}"
  else
    fail "missing ${needle}"
  fi
}

lacks() {
  local needle="$1" file="$2" label="$3"
  if grep -qF -- "$needle" "$file"; then
    fail "${label} contains ${needle}"
  else
    pass "${label} lacks ${needle}"
  fi
}

# --- skill text -----------------------------------------------------------
need_file "$SKILL"

has 'This skill should be used when scaffolding a redaction-gated post-incident report (PIR) after a production incident.' "$SKILL"
has 'doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h' "$SKILL"
has 'doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh --ref ifsccnjhymdmidffkzhl --since 24h' "$SKILL"
has 'doppler run -p soleur -c prd -- scripts/sentry-issue.sh' "$SKILL"
has "$TABLE" "$SKILL"
has 'limit=100' "$SKILL"
has 'soleur-inngest-prd' "$SKILL"
has 'pigsfuxruiopinouvjwy' "$SKILL"
has 'The word inngest alone does not add' "$SKILL"
has 'sentry: not-queried reason=no-issue-id' "$SKILL"
has 'window=n/a' "$SKILL"
has 'verdict=never-ran' "$SKILL"
has 'reason=usage' "$SKILL"
has 'reason=card-empty' "$SKILL"
has 'reason=card-redaction-failed' "$SKILL"
has 'reason=credential-refused' "$SKILL"
has 'reason=401' "$SKILL"
has 'reason=wrapper' "$SKILL"
has 'reason=reader-exit-' "$SKILL"
has 'stdout-empty' "$SKILL"
has 'hypotheses=none' "$SKILL"
has 'truncated=true' "$SKILL"
has '0600' "$SKILL"
has 'EXIT INT TERM HUP' "$SKILL"
has 'mktemp' "$SKILL"
has 'Do not `Read` or `cat` the temp' "$SKILL"
has '^[0-9]+[hmd]$' "$SKILL"
has '^[0-9]+[mhd]$' "$SKILL"
has 'Skill-side window allowlist' "$SKILL"
has '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$SKILL"
has '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' "$SKILL"
has '^[A-Za-z0-9_-]+$' "$SKILL"
has 'not executed' "$SKILL"
has 'does not exec' "$SKILL"
has 'reason=ZERO_SOURCE_COVERAGE_UNESTABLISHED' "$SKILL"
has 'not disproof' "$SKILL"
has 'do not print a pull time' "$SKILL"
has 'doppler login' "$SKILL"
has 'ensure-doppler.sh' "$SKILL"
has 'never passed as `--grep`' "$SKILL"
has 'Do not pass `--no-archive`' "$SKILL"
has 'SOLEUR_INCIDENT_PULL source=<betterstack|sentry|supabase>' "$SKILL"
has 'When the founder confirms the card, copy its one coverage sentence into the root-cause field.' "$SKILL"
has 'not `ACK-ART33`' "$SKILL"
has 'not `ACK-ART34`' "$SKILL"
has 'not `COMMIT-PIR`' "$SKILL"
has 'The card is not written under `post-mortems/`.' "$SKILL"
has 'No action items — incident fully resolved in the source PR with no residual work.' "$SKILL"

lacks 'BETTERSTACK_LOGS_TOKEN' "$SKILL" "skill"

# Reader command lines do not carry --grep, --no-archive, or the wrong Doppler config.
cmd_bad=0
while IFS= read -r line; do
  case "$line" in
    *'--grep'*|*'--no-archive'*) cmd_bad=1 ;;
  esac
  case "$line" in
    *betterstack-query.sh*)
      case "$line" in
        *prd_terraform*) ;;
        *) cmd_bad=1 ;;
      esac
      ;;
    *supabase-logs-query.sh*|*sentry-issue.sh*)
      case "$line" in
        *prd_terraform*) cmd_bad=1 ;;
      esac
      ;;
  esac
done < <(grep -F 'doppler run' "$SKILL" || true)
if [[ "$cmd_bad" -eq 0 ]]; then
  pass "reader commands use the Doppler split and carry no --grep or --no-archive"
else
  fail "a reader command uses the wrong Doppler config or carries --grep or --no-archive"
fi

# The pull commands sit before both blockquotes' diagnose ladder and before the field list.
awk '
  /^## Phase 0 / { phase=NR }
  /betterstack-query.sh/ && !cmd { cmd=NR }
  /No-SSH fact-pulling/ && !nossh { nossh=NR }
  /Unreachable host/ && !host { host=NR }
  /^1\. `title`/ && !field { field=NR }
  END {
    if (phase && cmd && nossh && host && field && phase < cmd && cmd < nossh && nossh < host && host < field)
      print "ok"
    else
      print "bad phase=" phase " cmd=" cmd " nossh=" nossh " host=" host " field=" field
  }
' "$SKILL" > "${TMP_DIR}/order.txt"
if grep -qx 'ok' "${TMP_DIR}/order.txt"; then
  pass "pull command precedes the diagnose ladder and the nineteen-field list"
else
  fail "pull order $(cat "${TMP_DIR}/order.txt")"
fi

awk '
  /^## Phase 0 / { grab=1 }
  /^## Phase 1 / { grab=0 }
  grab { print }
' "$SKILL" > "${TMP_DIR}/phase0.txt"
for needle in '0600' 'mktemp' 'EXIT INT TERM HUP' 'prd_terraform' 'stdout-empty' 'reason=card-empty'; do
  if grep -qF -- "$needle" "${TMP_DIR}/phase0.txt"; then
    pass "phase 0 has ${needle}"
  else
    fail "phase 0 missing ${needle}"
  fi
done

anchor='${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh'
anchor_n=$(grep -Fc "$anchor" "$SKILL" || true)
if [[ "$anchor_n" -eq 1 ]]; then
  pass "deployed-root sentinel anchor appears once"
else
  fail "deployed-root sentinel anchor count=${anchor_n}"
fi

action='No action items — incident fully resolved in the source PR with no residual work.'
action_n=$(grep -Fc "$action" "$SKILL" || true)
if [[ "$action_n" -eq 1 ]]; then
  pass "no-action-items sentence appears once"
else
  fail "no-action-items sentence count=${action_n}"
fi

# card-empty and card-redaction-failed do not halt; exit 2 does.
python3 - "$SKILL" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
sys.exit(0 if "reason=card-empty" in text and "does not print `SOLEUR_INCIDENT_HALT`" in text else 1)
PY
if [[ $? -eq 0 ]]; then
  pass "card-empty does not print the halt marker"
else
  fail "card-empty halt prohibition missing"
fi
python3 - "$SKILL" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
ok = "reason=card-redaction-failed" in text and "prints no offset line" in text and "does not print `SOLEUR_INCIDENT_HALT`" in text
sys.exit(0 if ok else 1)
PY
if [[ $? -eq 0 ]]; then
  pass "card redaction failure prints no offset and no halt"
else
  fail "card redaction failure prose missing"
fi

# --- dry-run --------------------------------------------------------------
need_file "$DRY_RUN"
lacks 'doppler run' "$DRY_RUN" "dry-run.sh"
lacks 'betterstack-query.sh' "$DRY_RUN" "dry-run.sh"
lacks 'supabase-logs-query.sh' "$DRY_RUN" "dry-run.sh"
lacks 'sentry-issue.sh' "$DRY_RUN" "dry-run.sh"
headless_n=$(grep -Fc -- '--headless' "$DRY_RUN" || true)
if [[ "$headless_n" -eq 1 ]] && grep -qF 'compound-capture --headless' "$DRY_RUN"; then
  pass "dry-run.sh names --headless only on the compound-capture handoff"
else
  fail "dry-run.sh --headless count=${headless_n} (the harness does not implement headless)"
fi

for src in betterstack sentry supabase; do
  if grep -qF "echo \"SOLEUR_INCIDENT_PULL source=${src} verdict=never-ran\"" "$DRY_RUN"; then
    pass "dry-run.sh echoes never-ran for ${src} with no leading indent"
  else
    fail "dry-run.sh missing column-0 never-ran echo for ${src}"
  fi
done

if [[ -x "$DRY_RUN" || -f "$DRY_RUN" ]]; then
  dry_out="${TMP_DIR}/dry.out"
  if bash "$DRY_RUN" "$DRY_FIXTURE" >"$dry_out" 2>"${TMP_DIR}/dry.err"; then
    dry_rc=0
  else
    dry_rc=$?
  fi
  if [[ "$dry_rc" -eq 0 ]]; then
    pass "dry-run exits 0"
  else
    fail "dry-run exits ${dry_rc}"
  fi
  awk '
    /=== Phase 0: facts captured ===/ { found=1; exit }
    /SOLEUR_INCIDENT_PULL source=betterstack verdict=never-ran/ { b=1 }
    /SOLEUR_INCIDENT_PULL source=sentry verdict=never-ran/ { s=1 }
    /SOLEUR_INCIDENT_PULL source=supabase verdict=never-ran/ { u=1 }
    END { print (found && b && s && u) ? "ok" : "bad" }
  ' "$dry_out" > "${TMP_DIR}/dry-order.txt"
  if grep -qx ok "${TMP_DIR}/dry-order.txt"; then
    pass "three never-ran markers precede the Phase 0 facts marker"
  else
    fail "dry-run marker order"
  fi
  if grep -qF 'affected_user_count: 1' "$dry_out"; then
    pass "dry-run affected_user_count stays the fixture value"
  else
    fail "dry-run affected_user_count is not the fixture value"
  fi
fi

# --- printer --------------------------------------------------------------
need_file "$FIXTURE"
if grep -qF "$UUID_LIT" "$FIXTURE" && grep -qF "$IPV4_LIT" "$FIXTURE" && grep -qF "$EMAIL_LIT" "$FIXTURE" \
   && grep -qF 'event_message' "$FIXTURE" && grep -qF '\"message\"' "$FIXTURE"; then
  pass "fixture carries the synthesized secret shapes inside event_message and message"
else
  fail "fixture is missing a synthesized secret shape"
fi
if grep -qF 'rows=' "$FIXTURE"; then
  fail "fixture pairs a coverage line with rows="
else
  pass "fixture has no rows= value"
fi

if [[ ! -f "$PRINTER" ]]; then
  fail "pull-card.sh missing — printer cases not executed"
else
  if grep -qF 'echo "SOLEUR_INCIDENT_PULL' "$PRINTER" || grep -qF "printf 'SOLEUR_INCIDENT_PULL" "$PRINTER"; then
    fail "pull-card.sh echoes SOLEUR_INCIDENT_PULL"
  else
    pass "pull-card.sh does not echo SOLEUR_INCIDENT_PULL"
  fi

  run_printer() {
    local label="$1" source_name="$2" code="$3" body="$4"
    if bash "$PRINTER" "$source_name" "$code" "$body" >"${TMP_DIR}/printer.out" 2>"${TMP_DIR}/printer.err"; then
      pass "${label} exits 0"
    else
      fail "${label} exits $?"
    fi
  }

  empty="${TMP_DIR}/empty-body.txt"
  : > "$empty"
  run_printer "betterstack empty" betterstack 0 "$empty"
  cp "${TMP_DIR}/printer.out" "${TMP_DIR}/bs-empty.out"
  has "betterstack table=${TABLE} limit=100 exit=0 stdout-empty" "${TMP_DIR}/bs-empty.out"
  lacks 'no rows' "${TMP_DIR}/bs-empty.out" "empty betterstack"
  lacks 'archive' "${TMP_DIR}/bs-empty.out" "empty betterstack"
  lacks 'absent' "${TMP_DIR}/bs-empty.out" "empty betterstack"
  lacks "$TMP_DIR" "${TMP_DIR}/bs-empty.out" "empty betterstack"

  run_printer "betterstack fixture" betterstack 0 "$FIXTURE"
  cp "${TMP_DIR}/printer.out" "${TMP_DIR}/bs-fix.out"
  has "betterstack table=${TABLE} limit=100 exit=0 raw=1" "${TMP_DIR}/bs-fix.out"
  lacks 'truncated=true' "${TMP_DIR}/bs-fix.out" "one-line betterstack"
  lacks "$UUID_LIT" "${TMP_DIR}/bs-fix.out" "betterstack fixture"
  lacks "$IPV4_LIT" "${TMP_DIR}/bs-fix.out" "betterstack fixture"
  lacks "$EMAIL_LIT" "${TMP_DIR}/bs-fix.out" "betterstack fixture"
  lacks 'rows=' "${TMP_DIR}/bs-fix.out" "betterstack fixture"
  lacks "$TMP_DIR" "${TMP_DIR}/bs-fix.out" "betterstack fixture"
  lacks 'affected_user_count' "${TMP_DIR}/bs-fix.out" "betterstack fixture"

  run_printer "betterstack exit 3" betterstack 3 "$FIXTURE"
  cp "${TMP_DIR}/printer.out" "${TMP_DIR}/bs-3.out"
  has "betterstack table=${TABLE} limit=100 exit=3" "${TMP_DIR}/bs-3.out"
  lacks 'raw=' "${TMP_DIR}/bs-3.out" "betterstack exit 3"
  lacks "$UUID_LIT" "${TMP_DIR}/bs-3.out" "betterstack exit 3"
  lacks 'stdout-empty' "${TMP_DIR}/bs-3.out" "betterstack exit 3"

  hundred="${TMP_DIR}/hundred.txt"
  : > "$hundred"
  n=0
  while [[ "$n" -lt 100 ]]; do
    printf '%s\n' '{"dt":"t","raw":"{}"}' >> "$hundred"
    n=$((n + 1))
  done
  run_printer "betterstack truncated" betterstack 0 "$hundred"
  cp "${TMP_DIR}/printer.out" "${TMP_DIR}/bs-100.out"
  has "betterstack table=${TABLE} limit=100 exit=0 raw=100 truncated=true" "${TMP_DIR}/bs-100.out"

  run_printer "supabase fixture" supabase 0 "$FIXTURE"
  cp "${TMP_DIR}/printer.out" "${TMP_DIR}/sb.out"
  has 'supabase verdict=COVERED reason=FULLY_COVERED' "${TMP_DIR}/sb.out"
  lacks 'rows=' "${TMP_DIR}/sb.out" "supabase fixture"
  lacks "$UUID_LIT" "${TMP_DIR}/sb.out" "supabase fixture"
  lacks "$EMAIL_LIT" "${TMP_DIR}/sb.out" "supabase fixture"
  lacks 'absent' "${TMP_DIR}/sb.out" "supabase fixture"
  lacks 'disproof' "${TMP_DIR}/sb.out" "supabase fixture"

  printf '%s\n' 'verdict=COVERED reason=FULLY_COVERED rows=0' > "${TMP_DIR}/bad-covered.txt"
  run_printer "supabase covered-with-rows" supabase 0 "${TMP_DIR}/bad-covered.txt"
  cp "${TMP_DIR}/printer.out" "${TMP_DIR}/sb-bad.out"
  lacks 'rows=' "${TMP_DIR}/sb-bad.out" "covered-with-rows"
  lacks 'absent' "${TMP_DIR}/sb-bad.out" "covered-with-rows"

  printf '%s\n' 'rows=4 evidence' > "${TMP_DIR}/stderr-shape.txt"
  printf '%s\n' 'verdict=INCONCLUSIVE reason=ZERO_SOURCE_COVERAGE_UNESTABLISHED' >> "${TMP_DIR}/stderr-shape.txt"
  run_printer "supabase zero-source" supabase 3 "${TMP_DIR}/stderr-shape.txt"
  cp "${TMP_DIR}/printer.out" "${TMP_DIR}/sb-zero.out"
  has 'supabase verdict=INCONCLUSIVE reason=ZERO_SOURCE_COVERAGE_UNESTABLISHED' "${TMP_DIR}/sb-zero.out"
  lacks 'rows=' "${TMP_DIR}/sb-zero.out" "zero-source"
  lacks 'disproof' "${TMP_DIR}/sb-zero.out" "zero-source"
  lacks 'absent' "${TMP_DIR}/sb-zero.out" "zero-source"

  run_printer "sentry fixture" sentry 0 "$FIXTURE"
  cp "${TMP_DIR}/printer.out" "${TMP_DIR}/sy.out"
  has 'sentry exit=0 window=n/a' "${TMP_DIR}/sy.out"
  lacks "$UUID_LIT" "${TMP_DIR}/sy.out" "sentry"
  lacks "$IPV4_LIT" "${TMP_DIR}/sy.out" "sentry"
  lacks "$EMAIL_LIT" "${TMP_DIR}/sy.out" "sentry"
  lacks "$TMP_DIR" "${TMP_DIR}/sy.out" "sentry"
  lacks 'affected_user_count' "${TMP_DIR}/sy.out" "sentry"

  if [[ -f "$SENTINEL" ]]; then
    if bash "$SENTINEL" "$FIXTURE" >"${TMP_DIR}/sentinel-raw.out" 2>&1; then
      fail "raw fixture did not trip the sentinel — the secret assertion is vacuous"
    else
      raw_rc=$?
      if [[ "$raw_rc" -eq 1 ]]; then
        pass "raw fixture trips the sentinel"
      else
        fail "raw fixture sentinel rc=${raw_rc}"
      fi
    fi
    if bash "$SENTINEL" "${TMP_DIR}/bs-fix.out" >"${TMP_DIR}/sentinel-card.out" 2>&1; then
      pass "printer stdout passes the sentinel"
    else
      fail "printer stdout fails the sentinel rc=$?"
    fi
  else
    fail "sentinel missing"
  fi
fi

# --- marker ---------------------------------------------------------------
if grep -qF 'SOLEUR_INCIDENT_PULL\b' "$MARKER_TS"; then
  pass "MARKER_RE names SOLEUR_INCIDENT_PULL word-boundary"
else
  fail "MARKER_RE missing SOLEUR_INCIDENT_PULL word-boundary"
fi
python3 - "$MARKER_TS" <<'PY'
import pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
idx = next((i for i, line in enumerate(lines) if r"SOLEUR_INCIDENT_PULL\b" in line), None)
window = "\n".join(lines[idx:idx + 16]) if idx is not None else ""
ok = "MIRRORED-NOT-PAGED" in window and "PostToolUse(Bash)" in window
sys.exit(0 if ok else 1)
PY
if [[ $? -eq 0 ]]; then
  pass "marker comment names the PostToolUse hook beside the new alternation"
else
  fail "marker comment missing beside SOLEUR_INCIDENT_PULL"
fi
if grep -F 'const WEDGE_RE' "$MARKER_TS" | grep -qF 'SOLEUR_INCIDENT_PULL'; then
  fail "WEDGE_RE contains SOLEUR_INCIDENT_PULL"
else
  pass "WEDGE_RE does not contain SOLEUR_INCIDENT_PULL"
fi

# Temp idiom the skill requires: outside the repo, mode 0600, gone after EXIT.
repo_phys="$(cd "$REPO_ROOT" && pwd -P)"
trap_path="${TMP_DIR}/trap-path.txt"
bash -c 'f=$(mktemp); chmod 0600 "$f"; trap "rm -f \"\$f\"" EXIT INT TERM HUP; printf "%s\n" "$f"' > "$trap_path"
held="$(cat "$trap_path")"
assert_fixture_dir "$(dirname "$held")"
if [[ ! -e "$held" ]]; then
  pass "trap removed the temp"
else
  fail "trap left ${held}"
  rm -f "$held"
fi
case "$held" in
  "$repo_phys"/*) fail "temp was inside the repo" ;;
  /*) pass "temp was outside the repo" ;;
  *) fail "temp path was not absolute" ;;
esac

echo "pull-card.test.sh: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
