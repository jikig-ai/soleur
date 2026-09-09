#!/usr/bin/env bash
# Self-tests for the accessibility-snapshot credential redactor (#7947).
#
# Runs in the scripts shard — scripts/test-all.sh globs
# plugins/soleur/skills/*/test/*.test.sh, so this file carries NO run_suite line.
#
# Every fixture is synthesized. The sentinel ZZQP-SENTINEL-7947 is invented and
# is never a real credential (cq-test-fixtures-synthesized-only).
#
# The case list is derived from the Phase 0.1 measurement recorded at
# knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/phase-0-measurement.md
# and NOT from the plan's original structural assumption. Measured: neither
# agent-browser 0.22.3 nor the Playwright MCP serializes `type=`, so a
# structural "is this a password input" predicate is unimplementable and the
# accessible-name limb does all the work.
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
FILTER="$REPO_ROOT/plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py"
SENTINEL='ZZQP-SENTINEL-7947'

pass=0
fail=0
# Case counter. It is incremented inside assert_redacted/assert_preserved, NOT
# at the call sites -- an earlier comment here claimed otherwise and was wrong.
# That coupling means a stubbed or misrouted assert helper keeps the count
# reconciling while asserting nothing, which the floor cannot see. The helper
# control below is what closes that, by proving each verdict-owning helper can
# still REJECT.
cases=0

# Floor derived as a lower bound, not a snapshot of today's total:
#   6 redaction rows + 5 must-PASS rows + 3 shape rows + 3 failure-mode rows
#   + 13 review rows (round 1) + 12 review rows (round 2) = 42.
# The two instrument self-test rows are excluded: they run before the counters
# are zeroed, so they are a precondition on the harness, not coverage of the SUT.
MIN_ASSERTIONS=42

ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# Instrument self-test (runs BEFORE any real row).
# Drives both verdict helpers once each and refuses to continue unless both
# counters moved. A suite whose helpers are stubbed exits 0 having asserted
# nothing; this is the only row that can see that.
# ---------------------------------------------------------------------------
_p0=$pass; _f0=$fail
ok  "instrument self-test: ok() increments"
bad "instrument self-test: bad() increments (EXPECTED, not a real failure)"
if [[ $pass -ne $((_p0 + 1)) || $fail -ne $((_f0 + 1)) ]]; then
  printf 'INSTRUMENT BROKEN: ok()/bad() did not both move (pass %d->%d, fail %d->%d)\n' \
    "$_p0" "$pass" "$_f0" "$fail" >&2
  exit 1
fi
# Zero all three counters rather than retiring just the deliberate failure.
# Half-retiring it (dropping the fail but keeping its `cases` increment) breaks
# the pass+fail==cases reconciliation below — which is exactly what that
# reconciliation is for, and it caught this on the first run.
pass=0; fail=0; cases=0

# ---------------------------------------------------------------------------
# Helper control. The instrument self-test above proves ok()/bad() move their
# counters; it cannot see a helper that OWNS a verdict taking the wrong branch
# and then calling the correct-looking helper, nor one stubbed to always pass.
# Both survived a mutation battery until this was added.
#
# Each verdict-owning helper is driven once with an input it MUST reject, with
# the filter swapped for a passthrough so rejection is forced. Counters are
# unwound afterwards.
# ---------------------------------------------------------------------------
_helper_control() {
  local _saved; _saved="$(declare -f run_filter)"
  run_filter() { printf '%s' "$1"; }   # passthrough: leaks by construction
  local _p=$pass _f=$fail _c=$cases
  assert_redacted  'helper control: assert_redacted must REJECT a leak (EXPECTED)' \
    "- textbox \"Token\" [ref=e1]: $SENTINEL"
  assert_preserved 'helper control: assert_preserved must REJECT a loss (EXPECTED)' \
    '- textbox "x" [ref=e1]: y' 'THIS_NEEDLE_IS_NEVER_PRESENT'
  eval "$_saved"
  if [[ $fail -ne $((_f + 2)) ]]; then
    printf 'HELPER CONTROL BROKEN: assert_redacted/assert_preserved did not both reject (fail %d->%d)\n' \
      "$_f" "$fail" >&2
    exit 1
  fi
  pass=$_p; fail=$_f; cases=$_c
}

if [[ ! -x "$FILTER" ]]; then
  printf 'FAIL - redactor missing or not executable at %s\n' "$FILTER"
  printf '\nRED: the filter does not exist yet. This is the expected pre-implementation state.\n'
  exit 1
fi

run_filter() { printf '%s' "$1" | python3 "$FILTER" 2>/dev/null; }

# assert_redacted <label> <input>
# The value must be gone from stdout AND the marker present. Asserting the
# NEGATIVE (the sentinel must never appear) is the load-bearing half: a
# positive "is <redacted> present" is satisfied by any arm that also leaks.
assert_redacted() {
  local label="$1" input="$2" out
  cases=$((cases + 1))
  out="$(run_filter "$input")"
  if [[ "$out" == *"$SENTINEL"* ]]; then
    bad "$label — sentinel survived in stdout"
  elif [[ "$out" != *"<redacted>"* ]]; then
    bad "$label — value removed but no <redacted> marker emitted"
  else
    ok "$label"
  fi
}

# assert_preserved <label> <input> <needle>
# The must-PASS side. A filter that redacts everything is as broken as one that
# redacts nothing, so every credential row above is paired against one of these.
assert_preserved() {
  local label="$1" input="$2" needle="$3" out
  cases=$((cases + 1))
  out="$(run_filter "$input")"
  if [[ "$out" == *"$needle"* ]]; then
    ok "$label"
  else
    bad "$label — benign value was redacted (over-aggressive filter)"
  fi
}

_helper_control

# ---------------------------------------------------------------------------
# Redaction rows — one per credential-shaped accessible name.
# "Token" is not decoration: it is the ONLY node agent-browser 0.22.3 leaks
# (it masks type=password as bullets), and it is the class with a recorded
# in-repo incident (2026-05-19-sentry-token-scope-probe-divergence.md).
# ---------------------------------------------------------------------------
assert_redacted 'agent-browser -i shape: textbox "Token"' \
  "- textbox \"Token\" [ref=e5]: $SENTINEL"

assert_redacted 'playwright-mcp shape: textbox "Enter your password"' \
  "- textbox \"Enter your password\" [ref=e3]: $SENTINEL"

assert_redacted 'credential name: "API key"' \
  "- textbox \"API key\" [ref=e2]: $SENTINEL"

assert_redacted 'credential name: "Client secret"' \
  "- textbox \"Client secret\" [ref=e2]: $SENTINEL"

assert_redacted 'credential name: "Passphrase"' \
  "- textbox \"Passphrase\" [ref=e2]: $SENTINEL"

# Indented node — the tree is nested in real output, so an anchor on ^- only
# would miss every node below the root.
assert_redacted 'indented node is still redacted' \
  "- generic [ref=e1]:
  - textbox \"Token\" [ref=e5]: $SENTINEL"

# ---------------------------------------------------------------------------
# must-PASS rows.
# ---------------------------------------------------------------------------
assert_preserved 'must-PASS: "Email address" value survives' \
  '- textbox "Email address" [ref=e6]: probe-user@example.invalid' \
  'probe-user@example.invalid'

assert_preserved 'must-PASS: "Search" value survives' \
  '- searchbox "Search" [ref=e2]: quarterly report' \
  'quarterly report'

assert_preserved 'must-PASS: "Username" is not a secret' \
  '- textbox "Username" [ref=e2]: alice' \
  'alice'

assert_preserved 'must-PASS: heading text is untouched' \
  '- heading "Reset your password" [level=1, ref=e1]' \
  'Reset your password'

assert_preserved 'must-PASS: non-credential node name containing "key" as a substring' \
  '- textbox "Keyboard shortcut" [ref=e2]: ctrl+k' \
  'ctrl+k'

# ---------------------------------------------------------------------------
# Shape rows — the serializations measured in Phase 0.1.
# ---------------------------------------------------------------------------

# The no-flag / -d N shape emits the value TWICE: once as the ": value" tail and
# again as a nested StaticText child. A tail-only filter is half a fix and this
# row is what proves it.
assert_redacted 'nested StaticText duplicate is redacted too' \
  "- textbox \"Token\" [ref=e5]: $SENTINEL
  - StaticText \"$SENTINEL\""

# --json wraps the same text in data.snapshot as an escaped string.
assert_redacted '--json shape: data.snapshot is redacted' \
  "{\"success\":true,\"data\":{\"snapshot\":\"- textbox \\\"Token\\\" [ref=e5]: $SENTINEL\"},\"error\":null}"

# A heading carries [level=1, ref=e1] — two attrs in one bracket. Confirm the
# attribute-bracket parse does not depend on a single-attr shape.
assert_redacted 'multi-attribute bracket parses' \
  "- textbox \"Token\" [level=2, ref=e5]: $SENTINEL"

# ---------------------------------------------------------------------------
# Review rows (round 1). Every one of these reproduced a live leak or a live
# over-redaction in the first shipped revision; they exist so the fixes are
# pinned rather than merely applied.
# ---------------------------------------------------------------------------

# Playwright appends [checked] [disabled] [expanded] [active] [invalid]
# [level=N] [pressed] [selected] before [ref=eN]. The first revision accepted
# exactly ONE bracket, so a node with any state attribute matched nothing at
# all. `[disabled]` is the standard shape of a "copy your new token" panel and
# `[active]` is the focused password field -- both leaked in clear.
assert_redacted 'multi-bracket: [active] before [ref]' \
  "- textbox \"Token\" [active] [ref=e5]: $SENTINEL"
assert_redacted 'multi-bracket: [disabled] (the credential-panel shape)' \
  "- textbox \"API key\" [disabled] [ref=e7]: $SENTINEL"

# English plurals and camelCase. "API Keys" and "Tokens" are the literal labels
# on the Cloudflare and Sentry token pages this filter was written for, and
# "Token" is the class with the recorded in-repo incident -- all three leaked on
# their own plural.
assert_redacted 'plural: "API Keys"'  "- textbox \"API Keys\" [ref=e1]: $SENTINEL"
assert_redacted 'plural: "Tokens"'    "- textbox \"Tokens\" [ref=e1]: $SENTINEL"
assert_redacted 'camelCase: "apiKey"' "- textbox \"apiKey\" [ref=e1]: $SENTINEL"

# The one-time-code family and the carriers that embed a password.
assert_redacted 'one-time-code family: "Verification code"' \
  "- textbox \"Verification code\" [ref=e1]: $SENTINEL"
assert_redacted 'carrier: "Connection string"' \
  "- textbox \"Connection string\" [ref=e1]: $SENTINEL"

# `agent-browser diff snapshot` emits additions with a `+` bullet. The first
# revision anchored on the list-dash, so the ADDED line -- the new value --
# passed through in clear while only the removed one was redacted.
assert_redacted 'diff addition line (+ bullet)' \
  "+ textbox \"Token\" [ref=e5]: $SENTINEL"

# The approved form is `... 2>&1 | python3 <this>`, so any agent-browser
# diagnostic lands AHEAD of the JSON. The first revision detected JSON with a
# whole-stream startswith(), so one stderr line defeated detection and the
# payload was emitted verbatim at exit 0 -- on the exact shape the guard
# prescribes.
assert_redacted 'stderr line ahead of --json still redacts' \
  "warn: daemon retry
{\"data\":{\"snapshot\":\"- textbox \\\"Token\\\" [ref=e5]: $SENTINEL\"}}"

# An unlabeled readonly box is the commonest shape of a credential panel and
# matched nothing at all before. Redacted on the fail-safe side.
assert_redacted 'unnamed text-input carrying a value' \
  "- textbox [ref=e5]: $SENTINEL"

cases=$((cases + 1))
nested="$(run_filter "- textbox \"Token\" [ref=e5]: $SENTINEL
  - textbox \"Confirm\" [ref=e6]: $SENTINEL")"
if [[ "$nested" == *"$SENTINEL"* ]]; then
  bad 'nested credential node: value must be redacted'
elif [[ "$nested" != *'"Confirm"'* ]]; then
  bad 'nested credential node: the NAME must survive (the first revision redacted the name and kept the value -- the exact inversion)'
else
  ok 'nested credential node: value redacted, name preserved'
fi

cases=$((cases + 1))
labels="$(run_filter '- combobox "Primary key" [ref=e2]: users_pkey
  - option "id" [ref=e3]
  - option "email" [ref=e4]')"
if [[ "$labels" == *'"id"'* && "$labels" == *'"email"'* ]]; then
  ok 'option LABELS survive under a redacted parent'
else
  bad 'option labels were destroyed — the agent can no longer pick an option, and no credential was protected'
fi

assert_preserved 'must-PASS: an unnamed STRUCTURAL node is untouched' \
  '- generic [ref=e1]:' '- generic [ref=e1]:'

# ---------------------------------------------------------------------------
# Review rows (round 2) — axes the round-1 battery never edited.
# ---------------------------------------------------------------------------

# ROLE-SET CARDINALITY. `textbox` carried every redaction row, so truncating
# TEXT_INPUT_ROLES to it alone was invisible -- and a member (`textarea`) had
# already silently left the set during round 1 and was leaking.
assert_redacted 'role: combobox'   "- combobox \"Token\" [ref=e2]: $SENTINEL"
assert_redacted 'role: spinbutton' "- spinbutton \"PIN\" [ref=e2]: $SENTINEL"
assert_redacted 'role: textarea'   "- textarea \"Token\" [ref=e2]: $SENTINEL"

# NAME-LIST CARDINALITY. These alternatives had no fixture, so truncating the
# regex to the covered subset survived.
assert_redacted 'name: "Bearer"'      "- textbox \"Bearer\" [ref=e1]: $SENTINEL"
assert_redacted 'name: "OTP"'         "- textbox \"OTP\" [ref=e1]: $SENTINEL"
assert_redacted 'name: "Mnemonic"'    "- textbox \"Mnemonic\" [ref=e1]: $SENTINEL"
assert_redacted 'name: "Seed phrase"' "- textbox \"Seed phrase\" [ref=e1]: $SENTINEL"
assert_redacted 'name: "Credential"'  "- textbox \"Credential\" [ref=e1]: $SENTINEL"

# JSON must-PASS. Every preserved-row fed the TEXT shape, so the JSON arm was
# pinned in one direction only: an arm that emitted just `<redacted>` and
# destroyed the whole envelope satisfied every assertion.
cases=$((cases + 1))
json_out="$(run_filter "{\"success\":true,\"data\":{\"snapshot\":\"- textbox \\\"Token\\\" [ref=e5]: $SENTINEL\"},\"error\":null}")"
if [[ "$json_out" == *"$SENTINEL"* ]]; then
  bad 'JSON must-PASS: sentinel survived'
elif ! printf '%s' "$json_out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  bad 'JSON must-PASS: output is no longer valid JSON'
elif [[ "$json_out" != *'"success"'* || "$json_out" != *'"error"'* ]]; then
  bad 'JSON must-PASS: benign sibling fields were destroyed'
else
  ok 'JSON arm redacts the snapshot and preserves the rest of the envelope'
fi

# A snapshot nested inside an ARRAY -- the list branch of the JSON walker had
# no fixture, so returning the node unchanged survived.
assert_redacted 'JSON: snapshot nested in an array' \
  "{\"data\":{\"results\":[{\"snapshot\":\"- textbox \\\"Token\\\" [ref=e5]: $SENTINEL\"}]}}"

# The fail-closed contract declares three refusal reasons; the UTF-8 one had no
# fixture, so deleting it (decode with errors="replace") survived and leaked.
cases=$((cases + 1))
u_out="$(printf '\xff\xfe- textbox "Token" [ref=e5]: %s' "$SENTINEL" | python3 "$FILTER" 2>/dev/null)"; u_rc=$?
if [[ $u_rc -eq 2 && -z "$u_out" ]]; then
  ok 'non-UTF-8 input: exit 2, stdout empty'
else
  bad "non-UTF-8 input must refuse (rc=$u_rc, out='${u_out:0:30}')"
fi

# A JSON envelope truncated BEFORE the "snapshot" key. The round-1 fix keyed on
# that literal being present, so a partial envelope -- exactly what a killed
# agent-browser produces -- fell through to the text path and was emitted
# verbatim at exit 0.
cases=$((cases + 1))
t_out="$(printf 'agent-browser: reconnecting\n{"success":true,"data":{"snapsho":"- textbox \\"Token\\" [ref=e5]: %s' "$SENTINEL" | python3 "$FILTER" 2>/dev/null)"; t_rc=$?
if [[ $t_rc -eq 2 && -z "$t_out" ]]; then
  ok 'truncated envelope before the snapshot key: exit 2, stdout empty'
elif [[ "$t_out" == *"$SENTINEL"* ]]; then
  bad 'truncated envelope leaked the sentinel (fail-open)'
else
  bad "truncated envelope must refuse (rc=$t_rc)"
fi

# ---------------------------------------------------------------------------
# Failure-mode rows — the fail-closed contract (ADR-095 shape).
# On refusal: exit 2, stdout EMPTY, stderr non-empty and sentinel-free. The
# third clause is the one that matters: a filter that echoes the offending
# input into its own error message re-opens the leak it exists to close.
# ---------------------------------------------------------------------------
cases=$((cases + 1))
over_cap="$(python3 -c "print('- textbox \"Token\" [ref=e1]: $SENTINEL' * 400000)")"
oc_out="$(printf '%s' "$over_cap" | python3 "$FILTER" 2>/tmp/rd_err.$$)"; oc_rc=$?
oc_err="$(cat /tmp/rd_err.$$ 2>/dev/null)"; rm -f /tmp/rd_err.$$
if [[ $oc_rc -ne 2 ]]; then
  bad "over-cap input must exit 2 (got $oc_rc)"
elif [[ -n "$oc_out" ]]; then
  bad "over-cap input must leave stdout empty"
elif [[ -z "$oc_err" ]]; then
  bad "over-cap input must write a reason to stderr"
elif [[ "$oc_err" == *"$SENTINEL"* ]]; then
  bad "over-cap stderr leaked the sentinel"
else
  ok "over-cap input: exit 2, stdout empty, stderr non-empty and sentinel-free"
fi

cases=$((cases + 1))
mal_out="$(printf '%s' "{\"data\":{\"snapshot\": " | python3 "$FILTER" 2>/tmp/rd_err2.$$)"; mal_rc=$?
mal_err="$(cat /tmp/rd_err2.$$ 2>/dev/null)"; rm -f /tmp/rd_err2.$$
if [[ $mal_rc -ne 2 ]]; then
  bad "truncated JSON must exit 2 (got $mal_rc)"
elif [[ -n "$mal_out" ]]; then
  bad "truncated JSON must leave stdout empty"
elif [[ -z "$mal_err" ]]; then
  bad "truncated JSON must write a reason to stderr"
else
  ok "truncated JSON: exit 2, stdout empty, stderr non-empty"
fi

cases=$((cases + 1))
empty_out="$(printf '' | python3 "$FILTER" 2>/dev/null)"; empty_rc=$?
if [[ $empty_rc -eq 0 && -z "$empty_out" ]]; then
  ok "empty input is a clean no-op (exit 0, empty stdout)"
else
  bad "empty input should be a clean no-op (rc=$empty_rc, out='${empty_out:0:40}')"
fi

# ---------------------------------------------------------------------------
# Verdict. Reported with printf + exit, never through ok()/bad() — the floor
# must not be dispatched through the helpers it backstops (ADR-193).
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed, %d cases\n' "$pass" "$fail" "$cases"

if [[ $((pass + fail)) -ne $cases ]]; then
  printf 'VACUITY: pass+fail (%d) != cases (%d) — a row did not report\n' \
    "$((pass + fail))" "$cases" >&2
  exit 1
fi
if [[ $cases -lt $MIN_ASSERTIONS ]]; then
  printf 'VACUITY: %d cases is below the floor of %d\n' "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ $fail -eq 0 ]] || exit 1
exit 0
