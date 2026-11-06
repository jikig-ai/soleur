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
has 'doppler run -p soleur -c prd_terraform -- env -u BS_TABLE -u BS_TABLE_S3 scripts/betterstack-query.sh --table t520508_soleur_inngest_vector_prd_3_logs --since 1h' "$SKILL"
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

  printf '%s\n' 'log line verdict=COVERED reason=FULLY_COVERED rows=4' > "${TMP_DIR}/last-pair.txt"
  printf '%s\n' 'verdict=INCONCLUSIVE reason=ZERO_SOURCE_COVERAGE_UNESTABLISHED' >> "${TMP_DIR}/last-pair.txt"
  run_printer "supabase last pair" supabase 0 "${TMP_DIR}/last-pair.txt"
  cp "${TMP_DIR}/printer.out" "${TMP_DIR}/sb-last.out"
  has 'supabase verdict=INCONCLUSIVE reason=ZERO_SOURCE_COVERAGE_UNESTABLISHED' "${TMP_DIR}/sb-last.out"
  lacks 'FULLY_COVERED' "${TMP_DIR}/sb-last.out" "last pair"
  lacks 'rows=' "${TMP_DIR}/sb-last.out" "last pair"

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
if grep -qF 'SOLEUR_INCIDENT_PULL' < <(grep -F 'const WEDGE_RE' "$MARKER_TS"); then
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

# Execute the Phase 0 fence. A stub doppler does not exec the readers.
fence="${TMP_DIR}/phase0-fence.sh"
awk '
  /^```bash$/ { n++; if (n==1) grab=1; next }
  /^```$/ && grab { exit }
  grab { print }
' "$SKILL" > "$fence"
if [[ -s "$fence" ]]; then
  pass "extracted the phase 0 fence"
else
  fail "could not extract the phase 0 fence"
fi
stub_bin="${TMP_DIR}/bin"
mkdir -p "$stub_bin"
printf '%s\n' '#!/bin/bash' 'exit 0' > "${stub_bin}/doppler"
chmod 755 "${stub_bin}/doppler"
printf '%s\n' '#!/bin/bash' 'exit 2' > "${TMP_DIR}/sentinel-exit-2.sh"
printf '%s\n' '#!/bin/bash' 'exit 0' > "${TMP_DIR}/sentinel-exit-0.sh"
chmod 755 "${TMP_DIR}/sentinel-exit-2.sh" "${TMP_DIR}/sentinel-exit-0.sh"
plugin_root="${REPO_ROOT}/plugins/soleur"
(
  cd "$REPO_ROOT" || exit 99
  PATH="${stub_bin}:${PATH}" \
    CLAUDE_PLUGIN_ROOT="$plugin_root" \
    SENTINEL="${TMP_DIR}/sentinel-exit-2.sh" \
    INCIDENT_SUPABASE_PROJECT=soleur-inngest-prd \
    INCIDENT_COMPLAINT='checkout button failed' \
    BS_TABLE=not_the_card_table \
    bash -x "$fence" >"${TMP_DIR}/fence-halt.out" 2>"${TMP_DIR}/fence-halt.err"
  printf '%s\n' "$?" > "${TMP_DIR}/fence-halt.rc"
)
halt_rc="$(cat "${TMP_DIR}/fence-halt.rc")"
if [[ "$halt_rc" -eq 2 ]]; then
  pass "fence exits 2 when the complaint sentinel exits 2"
else
  fail "fence complaint halt rc=${halt_rc}"
fi
if grep -qx 'SOLEUR_INCIDENT_HALT reason=sentinel-exit-2' "${TMP_DIR}/fence-halt.out"; then
  pass "complaint halt is on stdout"
else
  fail "complaint halt missing from stdout"
fi
if grep -qF 'checkout button failed' "${TMP_DIR}/fence-halt.out"; then
  fail "complaint text reached stdout"
else
  pass "complaint text stayed off stdout"
fi
if grep -qF 'checkout button failed' "${TMP_DIR}/fence-halt.err"; then
  fail "complaint text reached the trace"
else
  pass "complaint text stayed off the trace"
fi
python3 - "${TMP_DIR}/fence-halt.err" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(errors="replace")
a = "ref=ifsccnjhymdmidffkzhl"
b = "ref=pigsfuxruiopinouvjwy"
lines = text.splitlines()
ok = False
for i, ln in enumerate(lines):
    if a in ln and b in ln:
        ia = ln.find(a)
        ib = ln.find(b, ia + len(a))
        if ib != -1 and "\\n" in ln[ia + len(a):ib]:
            # Bash 5.3 keeps the traced newline as a one-line \n escape.
            ok = True
    elif a in ln and b not in ln and i + 1 < len(lines):
        # Bash 5.2 prints that newline raw, so the assignment spans two trace
        # lines and the opening quote is still open. A finished line (even
        # quote count) is a separate command; a space join stays one line.
        nxt = lines[i + 1]
        if b in nxt and a not in nxt and ln.count("'") % 2 == 1:
            ok = True
sys.exit(0 if ok else 1)
PY
if [[ $? -eq 0 ]]; then
  pass "xtrace keeps the two supabase refs on separate lines"
else
  fail "xtrace did not keep the two supabase refs on separate lines"
fi
if grep -qF -- '--table t520508_soleur_inngest_vector_prd_3_logs' "${TMP_DIR}/fence-halt.err" \
  && grep -qF -- 'env -u BS_TABLE -u BS_TABLE_S3' "${TMP_DIR}/fence-halt.err"; then
  pass "xtrace pins the betterstack table and unsets BS_TABLE"
else
  fail "xtrace did not pin the betterstack table"
fi
(
  cd "$REPO_ROOT" || exit 99
  PATH="${stub_bin}:${PATH}" \
    CLAUDE_PLUGIN_ROOT="$plugin_root" \
    SENTINEL="${TMP_DIR}/sentinel-exit-0.sh" \
    INCIDENT_WINDOW='999w' \
    bash -x "$fence" >"${TMP_DIR}/fence-usage.out" 2>"${TMP_DIR}/fence-usage.err"
)
if grep -qF 'reason=usage' "${TMP_DIR}/fence-usage.out" \
  && ! grep -qF '999w' "${TMP_DIR}/fence-usage.out" \
  && ! grep -qF 'window=1h' "${TMP_DIR}/fence-usage.out" \
  && ! grep -qF 'window=24h' "${TMP_DIR}/fence-usage.out"; then
  pass "a refused window is usage and is not printed"
else
  fail "refused window leaked or was not usage"
fi
(
  cd "$REPO_ROOT" || exit 99
  PATH="${stub_bin}:${PATH}" \
    CLAUDE_PLUGIN_ROOT="$plugin_root" \
    SENTINEL="${TMP_DIR}/sentinel-exit-0.sh" \
    INCIDENT_SENTRY_ISSUE_ID='--redact' \
    bash -x "$fence" >"${TMP_DIR}/fence-dash.out" 2>"${TMP_DIR}/fence-dash.err"
)
if grep -qF 'sentry verdict=never-ran reason=usage' "${TMP_DIR}/fence-dash.out" \
  && ! grep -qF 'sentry-issue.sh' "${TMP_DIR}/fence-dash.err" \
  && ! grep -qF -- '--redact' "${TMP_DIR}/fence-dash.out"; then
  pass "a leading-dash issue id is usage and is not executed"
else
  fail "leading-dash issue id was executed or printed"
fi
(
  cd "$REPO_ROOT" || exit 99
  env -u CLAUDE_PLUGIN_ROOT \
    PATH="${stub_bin}:${PATH}" \
    SENTINEL="${TMP_DIR}/sentinel-exit-0.sh" \
    bash -x "$fence" >"${TMP_DIR}/fence-root.out" 2>"${TMP_DIR}/fence-root.err"
  printf '%s\n' "$?" > "${TMP_DIR}/fence-root.rc"
)
root_rc="$(cat "${TMP_DIR}/fence-root.rc")"
if [[ "$root_rc" -eq 2 ]] \
  && grep -qx 'SOLEUR_INCIDENT_HALT reason=plugin-root-unverified' "${TMP_DIR}/fence-root.out" \
  && ! grep -qF 'betterstack-query.sh' "${TMP_DIR}/fence-root.err"; then
  pass "an empty plugin root halts before a reader"
else
  fail "empty plugin root did not halt before a reader rc=${root_rc}"
fi

# TERM during the Better Stack read must exit 143 and must not start Supabase.
printf '%s\n' '#!/bin/bash' 'if [[ "$*" == *betterstack-query.sh* ]]; then sleep 30; fi' 'exit 0' > "${stub_bin}/doppler"
chmod 755 "${stub_bin}/doppler"
python3 - "$fence" "$stub_bin" "$plugin_root" "${TMP_DIR}/sentinel-exit-0.sh" "$REPO_ROOT" <<'PY'
import os, signal, subprocess, sys, time
fence, stub_bin, plugin_root, sentinel, repo = sys.argv[1:]
env = os.environ.copy()
env["PATH"] = stub_bin + os.pathsep + env.get("PATH", "")
env["CLAUDE_PLUGIN_ROOT"] = plugin_root
env["SENTINEL"] = sentinel
for key in ("INCIDENT_WINDOW", "INCIDENT_SENTRY_ISSUE_ID", "INCIDENT_COMPLAINT", "INCIDENT_SUPABASE_PROJECT"):
    env.pop(key, None)
proc = subprocess.Popen(
    ["bash", fence], cwd=repo, env=env,
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True, text=True,
)
deadline = time.time() + 3
while time.time() < deadline:
    if proc.poll() is not None:
        break
    time.sleep(0.05)
os.killpg(proc.pid, signal.SIGTERM)
rc = proc.wait(timeout=5)
out = proc.stdout.read() if proc.stdout is not None else ""
bad = rc != 143 or "source=supabase" in out
sys.exit(1 if bad else 0)
PY
if [[ $? -eq 0 ]]; then
  pass "TERM during the pull exits 143 and does not start supabase"
else
  fail "TERM during the pull did not stop the later readers"
fi
printf '%s\n' '#!/bin/bash' 'exit 0' > "${stub_bin}/doppler"
chmod 755 "${stub_bin}/doppler"

echo "pull-card.test.sh: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
