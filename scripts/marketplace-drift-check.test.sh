#!/usr/bin/env bash
# Behavioural + structural gate for .github/workflows/scheduled-marketplace-drift.yml.
#
# WHY THIS EXISTS. AMENDED by #7493 — this header previously said `jikig-ai/soleur-marketplace`
# "has no CI, no required review and no CODEOWNERS, so every edit to it is unreviewed by
# construction", and that this workflow was "the ONLY control". Both were true when written and
# are now false: that repo carries the `Marketplace PR Required` ruleset, Terraform owns the
# manifest's contents, and `marketplace-manifest-guard` validates the source pre-merge here.
# This workflow is now the PUBLICATION verifier — it asserts what is actually being served, which
# no pre-merge gate can do. A drift checker that silently reports "no drift" is
# therefore worse than no checker — it converts an unguarded artifact into one that looks
# guarded. The scenarios below drive the checker's own logic against synthesized manifests and
# assert that every degenerate input (404, HTML error page, null `.plugins`, missing plugin
# manifest) lands on MISMATCH rather than on OK.
#
# HOW IT DRIVES THE CHECKER. The logic lives inline in the workflow's `check` step, so the step
# body IS the unit under test: it is extracted from the YAML and executed under the exact shell
# GitHub uses for a `run:` block with no `shell:` key — `bash --noprofile --norc -eo pipefail`.
# Running it under a plain `bash` would defeat the point: the inherited `-e` is the specific
# thing that has silently killed capture logic in this repo's workflows before (#7304), and a
# test that clears it cannot observe the defect it exists to catch.
#
# Network is stubbed with a `curl` shim on PATH, so no scenario touches the network and the
# fixtures are synthesized JSON rather than captured responses.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="${MARKETPLACE_DRIFT_WORKFLOW:-$REPO_ROOT/.github/workflows/scheduled-marketplace-drift.yml}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}
fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
  [[ $# -lt 2 ]] || echo "        $2"
}

echo "=== marketplace-drift-check ==="

if [[ ! -f "$WORKFLOW" ]]; then
  fail "workflow exists at $WORKFLOW"
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

# ---------------------------------------------------------------------------------------------
# Extract the `check` step body. Keyed on the step id, not on an index, so inserting a step
# above it does not silently start testing a different body.
# ---------------------------------------------------------------------------------------------
python3 - "$WORKFLOW" "$TMP/check.sh" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = wf["jobs"]["drift-check"]["steps"]
body = next(s["run"] for s in steps if s.get("id") == "check")
open(sys.argv[2], "w").write(body)
PY

# ---------------------------------------------------------------------------------------------
# curl shim. Selects a response per URL and records the flags it was invoked with, so the
# --fail / --max-time assertions observe the real call rather than a grep of the YAML.
# ---------------------------------------------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
url="${!#}"
printf '%s\n' "$*" >> "$CURL_ARGS_LOG"
case "$url" in
  *soleur-marketplace*) rc="${CURL_MANIFEST_RC:-0}"; body="${CURL_MANIFEST_BODY:-}" ;;
  *)                    rc="${CURL_PLUGIN_RC:-0}";   body="${CURL_PLUGIN_BODY:-}" ;;
esac
if [[ "$rc" -eq 0 ]]; then
  printf '%s' "$body"
fi
exit "$rc"
STUB
chmod +x "$TMP/bin/curl"

GOOD_PLUGIN='{"name":"soleur","description":"synthesized fixture"}'
GOOD_MANIFEST='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}}]}'

# run_check <manifest_body> <manifest_rc> <plugin_body> <plugin_rc>
# Leaves the parsed step outputs in VERDICT / FINDING_COUNT / FINDINGS and the raw
# $GITHUB_OUTPUT file at $TMP/out.txt.
run_check() {
  : > "$TMP/out.txt"
  : > "$TMP/curl-args.txt"
  local rc=0
  env PATH="$TMP/bin:$PATH" \
    GITHUB_OUTPUT="$TMP/out.txt" \
    CURL_ARGS_LOG="$TMP/curl-args.txt" \
    CURL_MANIFEST_BODY="$1" CURL_MANIFEST_RC="$2" \
    CURL_PLUGIN_BODY="$3" CURL_PLUGIN_RC="$4" \
    bash --noprofile --norc -eo pipefail "$TMP/check.sh" > "$TMP/log.txt" 2>&1 || rc=$?
  STEP_RC="$rc"
  VERDICT="$(sed -n 's/^verdict=//p' "$TMP/out.txt" | head -1)"
  FINDING_COUNT="$(sed -n 's/^finding_count=//p' "$TMP/out.txt" | head -1)"
  FINDINGS="$(sed -n '/^findings<</,/^MARKETPLACE_DRIFT_FINDINGS_EOF$/p' "$TMP/out.txt")"
  DISPATCH_ELIGIBLE="$(sed -n 's/^dispatch_eligible=//p' "$TMP/out.txt" | head -1)"
}

# Guard 2 (#7493). The reconcile predicate decides whether a drift verdict triggers an apply
# that REPUBLISHES the manifest. Both directions are load-bearing and they fail differently:
# dispatching on a verdict Terraform cannot fix rewrites an already-correct file every tick
# forever, while NOT dispatching on one it can leaves the published artifact wrong.
#
# The decision must be OBSERVABLE for any of this to be testable at all — that is the
# own-dispatch row. A predicate living in an Actions `if:` would be invisible to this harness
# (which runs only the check step's bash), so an unreadable output is itself a failure.
expect_dispatch() {
  local label="$1" want="$2"
  if [[ -z "$DISPATCH_ELIGIBLE" ]]; then
    fail "$label" "dispatch_eligible was not emitted at all — the decision is unobservable, so this suite cannot see the predicate (Guard 2 own-dispatch row)"
  elif [[ "$DISPATCH_ELIGIBLE" == "$want" ]]; then
    pass "$label"
  else
    fail "$label" "dispatch_eligible='$DISPATCH_ELIGIBLE' (want '$want'), findings: $(tr '\n' ' ' <<<"$FINDINGS" | cut -c1-300)"
  fi
}

expect_verdict() {
  local label="$1" want="$2"
  if [[ "$VERDICT" == "$want" ]]; then
    pass "$label"
  else
    fail "$label" "verdict='$VERDICT' (want '$want'), step rc=$STEP_RC, log: $(tr '\n' ' ' < "$TMP/log.txt" | cut -c1-300)"
  fi
}

expect_finding() {
  local label="$1" token="$2"
  if grep -q "$token" <<<"$FINDINGS"; then
    pass "$label"
  else
    fail "$label" "no '$token' in findings: $(tr '\n' ' ' <<<"$FINDINGS" | cut -c1-300)"
  fi
}

# ---------------------------------------------------------------------------------------------
# Behavioural scenarios
# ---------------------------------------------------------------------------------------------

run_check "$GOOD_MANIFEST" 0 "$GOOD_PLUGIN" 0
expect_verdict "a conforming manifest reports OK" "OK"
[[ "$FINDING_COUNT" == "0" ]] && pass "a conforming manifest reports zero findings" \
  || fail "a conforming manifest reports zero findings" "finding_count='$FINDING_COUNT'"
[[ "$STEP_RC" == "0" ]] && pass "the check step always exits 0 (the verdict travels as data)" \
  || fail "the check step always exits 0 (the verdict travels as data)" "rc=$STEP_RC"

# THE ASSERTION THE WORKFLOW EXISTS FOR. One added key, no other change, no visible symptom.
VERSIONED='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","version":"1.2.3","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}}]}'
run_check "$VERSIONED" 0 "$GOOD_PLUGIN" 0
expect_verdict "a hand-added version key is drift" "MISMATCH"
expect_finding "the version-key finding names the key" "version_key_present"

# The assertion is written as `!= "false"` rather than as a `== "true"` negation, and the
# difference is only observable when the jq invocation itself fails: no manifest content can
# make `has("version")` return anything but true or false, so a broken jq is the ONLY producer
# of the empty third value. Under `== "true"` that empty value reads as a pass — the checker
# would report the artifact healthy on the one assertion it exists for, having measured nothing.
REAL_JQ="$(command -v jq)"
cat > "$TMP/bin/jq" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in *'has("version")'*) exit 5 ;; esac
done
exec "$REAL_JQ" "\$@"
STUB
chmod +x "$TMP/bin/jq"
run_check "$GOOD_MANIFEST" 0 "$GOOD_PLUGIN" 0
rm -f "$TMP/bin/jq"
expect_verdict "a jq failure on the version query fails CLOSED rather than reading as absent" "MISMATCH"
expect_finding "the failed version query is reported as the version assertion, not swallowed" "version_key_present"

WRONG_PATH='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur-next"}}]}'
run_check "$WRONG_PATH" 0 "$GOOD_PLUGIN" 0
expect_verdict "a changed source.path is drift" "MISMATCH"
expect_finding "the path finding names source_path" "source_path"

WRONG_URL='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/someone-else/soleur.git","path":"plugins/soleur"}}]}'
run_check "$WRONG_URL" 0 "$GOOD_PLUGIN" 0
expect_verdict "a repointed source.url is drift" "MISMATCH"
expect_finding "the url finding names source_url" "source_url"

# The ssh spelling and the suffix-less form are the SAME repository, not drift. Without this
# the alarm would cry wolf on a cosmetic edit, and an alarm that cries wolf gets muted.
SSH_URL='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"git@github.com:jikig-ai/soleur","path":"plugins/soleur"}}]}'
run_check "$SSH_URL" 0 "$GOOD_PLUGIN" 0
expect_verdict "an equivalent spelling of the same repo URL is not drift" "OK"

# ---- One case per assertion added after the first review pass. Each fixture differs from
# GOOD_MANIFEST in EXACTLY the property under test, so a green run means that assertion
# discriminated — not that some other assertion happened to fire.
# Measured before these existed: every one of the four mutations below reported OK.
WRONG_TYPE='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","source":{"source":"github","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}}]}'
run_check "$WRONG_TYPE" 0 "$GOOD_PLUGIN" 0
expect_verdict "a non-git-subdir source type is drift (it restores the whole-repo clone)" "MISMATCH"
expect_finding "the source-type finding names source_type" "source_type"

PINNED='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur","ref":"v0.9.0"}}]}'
run_check "$PINNED" 0 "$GOOD_PLUGIN" 0
expect_verdict "a ref pin is drift (a constant pin is the version sentinel in other clothes)" "MISMATCH"
expect_finding "the pin finding names source_pinned" "source_pinned"

PINNED_SHA='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur","sha":"deadbeef"}}]}'
run_check "$PINNED_SHA" 0 "$GOOD_PLUGIN" 0
expect_verdict "a sha pin is drift too — the probe covers every pin spelling" "MISMATCH"

APPENDED='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}},{"name":"evil","source":{"source":"git-subdir","url":"https://github.com/attacker/evil.git","path":"plugins/evil"}}]}'
run_check "$APPENDED" 0 "$GOOD_PLUGIN" 0
expect_verdict "an APPENDED second entry is drift — every other assertion reads .plugins[0]" "MISMATCH"
expect_finding "the appended-entry finding names entry_count" "entry_count"

RENAMED='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur-next","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}}]}'
run_check "$RENAMED" 0 "$GOOD_PLUGIN" 0
expect_verdict "a renamed entry is drift — the name is the '@' half of every install command" "MISMATCH"
expect_finding "the rename finding names entry_name" "entry_name"

# ---- marketplace identity (#7493 review) -----------------------------------------------------
# `.name` and `.owner` are properties of the marketplace DOCUMENT, not of .plugins[0], and both
# were unasserted on the published side. They are not redundant with Guard 4: that gate reads the
# SOURCE, and the ruleset's human bypasses are `always` (spec G5's emergency path), so a hand-edit
# to the published file is reachable and would be invisible to every other check here.
MP_RENAMED='{"name":"evil-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}}]}'
run_check "$MP_RENAMED" 0 "$GOOD_PLUGIN" 0
expect_verdict "a renamed MARKETPLACE is drift — it is the '@' half of install AND update" "MISMATCH"
expect_finding "the marketplace-rename finding names marketplace_name" "marketplace_name"
expect_dispatch "marketplace_name DOES dispatch (a republish restores it)" "true"

MP_OWNER='{"name":"soleur-marketplace","owner":{"name":"Mallory","email":"mallory@evil.tld"},"plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}}]}'
run_check "$MP_OWNER" 0 "$GOOD_PLUGIN" 0
expect_verdict "a substituted owner is drift — a phishing surface the byte-diff cannot report" "MISMATCH"
expect_finding "the owner finding names marketplace_owner" "marketplace_owner"
expect_dispatch "marketplace_owner DOES dispatch (a republish restores it)" "true"

# An ABSENT owner must not read as clean: `jq` yields "" for a missing key, and comparing an
# empty string against the expected value is what makes absence a finding rather than a pass.
MP_NO_OWNER='{"name":"soleur-marketplace","plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}}]}'
run_check "$MP_NO_OWNER" 0 "$GOOD_PLUGIN" 0
expect_verdict "an ABSENT owner is drift, not a pass" "MISMATCH"
expect_finding "the absent-owner finding names marketplace_owner" "marketplace_owner"

# ---- fail-closed paths ----------------------------------------------------------------------
# Each of these is a state where the checker CANNOT SEE the artifact. Every one must report
# MISMATCH: "I could not look" is not "nothing is wrong".
run_check "" 22 "$GOOD_PLUGIN" 0
expect_verdict "an HTTP error on the manifest fails CLOSED" "MISMATCH"
expect_finding "the fetch failure is named and carries curl's exit code" "manifest_fetch_failed"

run_check '<!DOCTYPE html><html><body>404: Not Found</body></html>' 0 "$GOOD_PLUGIN" 0
expect_verdict "an HTML error page served with status 200 fails CLOSED" "MISMATCH"
expect_finding "the unparseable body is named" "manifest_unparseable"

run_check "" 0 "$GOOD_PLUGIN" 0
expect_verdict "an empty 200 body fails CLOSED" "MISMATCH"

# `null | length` is 0 and `jq -e` exits 0 on a `0` — the two traps that turn a missing array
# into a passing check. The shape gate must run before any value is trusted.
run_check '{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":null}' 0 "$GOOD_PLUGIN" 0
expect_verdict "a null .plugins fails CLOSED rather than reading as empty" "MISMATCH"
expect_finding "the shape failure is named" "manifest_shape"

run_check '{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[]}' 0 "$GOOD_PLUGIN" 0
expect_verdict "an empty .plugins array fails CLOSED" "MISMATCH"

run_check '{"plugins":[{"source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":null}}]}' 0 "$GOOD_PLUGIN" 0
expect_verdict "a null source.path fails CLOSED" "MISMATCH"
if grep -q "source.path is 'null'" <<<"$FINDINGS"; then
  fail "a null source.path is not reported as the four-character string 'null'" "finding: $(tr '\n' ' ' <<<"$FINDINGS" | cut -c1-200)"
else
  pass "a null source.path is not reported as the four-character string 'null'"
fi

# ---- the second GET: the drift the marketplace repo cannot observe about itself --------------
run_check "$GOOD_MANIFEST" 0 "" 22
expect_verdict "an unresolvable plugin manifest is drift even when the marketplace manifest is perfect" "MISMATCH"
expect_finding "the monorepo-reorg case is named" "plugin_manifest_unresolvable"

run_check "$GOOD_MANIFEST" 0 '<!DOCTYPE html>404' 0
expect_verdict "an HTML page in place of plugin.json is drift" "MISMATCH"
expect_finding "the unparseable plugin manifest is named" "plugin_manifest_unparseable"

run_check "$GOOD_MANIFEST" 0 '{"description":"no name key"}' 0
expect_verdict "a plugin.json without a string .name is drift" "MISMATCH"

# ---- untrusted-input handling ---------------------------------------------------------------
# The marketplace repo is unreviewed, so its string values are attacker-controlled for this
# purpose. A workflow-command prefix must not survive into the run log, and an embedded newline
# must not break out of the heredoc-delimited $GITHUB_OUTPUT write.
INJECT='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"##[set-env name=X]evil\nverdict=OK"}}]}'
run_check "$INJECT" 0 "$GOOD_PLUGIN" 0
expect_verdict "a manifest carrying a workflow-command prefix still reports MISMATCH" "MISMATCH"
if grep -qF '##[' "$TMP/log.txt" || grep -qF '##[' "$TMP/out.txt"; then
  fail "the '##[' workflow-command prefix is neutralised before it is echoed"
else
  pass "the '##[' workflow-command prefix is neutralised before it is echoed"
fi
if [[ "$(grep -c '^verdict=' "$TMP/out.txt")" == "1" ]]; then
  pass "an embedded newline cannot forge a second verdict= line in \$GITHUB_OUTPUT"
else
  fail "an embedded newline cannot forge a second verdict= line in \$GITHUB_OUTPUT" \
    "$(grep -c '^verdict=' "$TMP/out.txt") verdict lines"
fi
if [[ "$(grep -c '^MARKETPLACE_DRIFT_FINDINGS_EOF$' "$TMP/out.txt")" == "1" ]]; then
  pass "the findings heredoc delimiter is not forgeable from manifest content"
else
  fail "the findings heredoc delimiter is not forgeable from manifest content"
fi

# ---- curl invocation shape ------------------------------------------------------------------
run_check "$GOOD_MANIFEST" 0 "$GOOD_PLUGIN" 0
if [[ "$(wc -l < "$TMP/curl-args.txt")" -eq 2 ]]; then
  pass "the checker performs exactly two GETs"
else
  fail "the checker performs exactly two GETs" "$(wc -l < "$TMP/curl-args.txt") call(s)"
fi
bad_flags=0
while IFS= read -r args; do
  [[ "$args" =~ (^|[[:space:]])(-[a-zA-Z]*f[a-zA-Z]*|--fail)([[:space:]]|$) ]] || bad_flags=1
  [[ "$args" == *"--max-time"* ]] || bad_flags=1
done < "$TMP/curl-args.txt"
if [[ "$bad_flags" -eq 0 ]]; then
  pass "every GET carries --fail (so an error status is not parsed as a body) and --max-time"
else
  fail "every GET carries --fail (so an error status is not parsed as a body) and --max-time" \
    "$(tr '\n' ' ' < "$TMP/curl-args.txt" | cut -c1-300)"
fi

# ---------------------------------------------------------------------------------------------
# Guard 2 — the reconcile dispatch predicate (#7493). Behavioural: these drive the real check
# step and read the decision it emits, rather than grepping the `if:` text.
# ---------------------------------------------------------------------------------------------

# A clean run must not dispatch. Without this the "always dispatch" implementation passes every
# other row here.
run_check "$GOOD_MANIFEST" 0 "$GOOD_PLUGIN" 0
expect_verdict "G2 control: a clean manifest is OK" "OK"
expect_dispatch "G2 control: a clean manifest does not dispatch a reconcile" "false"

# A content finding Terraform CAN fix -> dispatch.
VERSIONED_MANIFEST='{"name":"soleur-marketplace","owner":{"name":"Jean Deruelle","email":"jean.deruelle@jikigai.com"},"plugins":[{"name":"soleur","version":"1.0.0","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}}]}'
run_check "$VERSIONED_MANIFEST" 0 "$GOOD_PLUGIN" 0
expect_verdict "G2.2 a version key is MISMATCH" "MISMATCH"
expect_dispatch "G2.2 a version key dispatches a reconcile" "true"

# GET-2-ONLY: the marketplace manifest is perfect and plugin.json is unresolvable. Republishing
# the manifest cannot fix this — it would rewrite a correct file on every tick while the real
# breakage (a moved plugins/soleur in THIS repo) persists.
run_check "$GOOD_MANIFEST" 0 "" 22
expect_verdict "G2.1 an unresolvable plugin manifest is MISMATCH" "MISMATCH"
expect_dispatch "G2.1 a plugin_manifest_unresolvable-ONLY verdict does NOT dispatch" "false"

# The SECOND GET-2 key. A denylist naming only `plugin_manifest_unresolvable` is short by one and
# would dispatch a pointless daily apply here; the PREFIX form covers it, which is the whole
# reason the predicate is written as a prefix.
run_check "$GOOD_MANIFEST" 0 'not json at all' 0
expect_verdict "G2.3 an unparseable plugin manifest is MISMATCH" "MISMATCH"
expect_dispatch "G2.3 a plugin_manifest_UNPARSEABLE-only verdict does NOT dispatch (second-member row)" "false"

# MIXED: a GET-2 finding alongside a real content finding. This is the case an unanchored
# `contains(findings, 'plugin_manifest_unresolvable')` gets WRONG — it would suppress a dispatch
# that is needed, leaving the published manifest broken.
run_check "$VERSIONED_MANIFEST" 0 "" 22
expect_verdict "G2.4 a mixed verdict is MISMATCH" "MISMATCH"
expect_dispatch "G2.4 a MIXED verdict (GET-2 + content) DOES dispatch" "true"

# Substring soundness in the other direction: `manifest_unparseable` (the MARKETPLACE manifest,
# fixable) is a proper substring of `plugin_manifest_unparseable` (the monorepo's, not fixable).
# An unanchored match would classify this fixable finding as un-dispatchable.
run_check 'not json at all' 0 "$GOOD_PLUGIN" 0
expect_verdict "G2.5 an unparseable MARKETPLACE manifest is MISMATCH" "MISMATCH"
expect_dispatch "G2.5 manifest_unparseable DOES dispatch (it is not plugin_manifest_unparseable)" "true"

# UNMEASURED-STATE ROW (AP-021). `manifest_fetch_failed` fires when the fetch itself failed, so
# the check's own finding text says "no body was read, so no assertion below could be evaluated".
# Dispatching on it therefore acts on an explicitly UNKNOWN state rather than a known-bad one,
# which AP-021 normally forbids. It is deliberate here and pinned so it is not rediscovered as a
# surprise: the apply is deterministic from this repo's .tf files at main and NEVER consumes the
# fetched body, so a spurious reconcile is a no-op for the manifest. The alternative — treating a
# transient CDN 5xx as "nothing to do" — is the fail-open shape this workflow exists to refuse,
# and a deleted manifest (which also lands here) is exactly what a reconcile SHOULD restore.
run_check "" 22 "$GOOD_PLUGIN" 0
expect_verdict "G2.6 an unfetchable marketplace manifest is MISMATCH" "MISMATCH"
expect_dispatch "G2.6 manifest_fetch_failed DOES dispatch (deliberate AP-021 deviation: the apply never reads the fetched body)" "true"

# ---------------------------------------------------------------------------------------------
# Structural assertions on the workflow itself. These cover the parts GitHub evaluates, which
# no runtime driver can reach.
# ---------------------------------------------------------------------------------------------
structural="$(python3 - "$WORKFLOW" <<'PY'
import sys, re, yaml

src = open(sys.argv[1]).read()
wf = yaml.safe_load(src)
job = wf["jobs"]["drift-check"]
steps = job["steps"]
problems = []

# The `check` step's run body — the block this harness also extracts and executes elsewhere.
check_body = next((st.get("run", "") for st in steps if st.get("id") == "check"), "")
if not check_body:
    problems.append("no step with id 'check' carrying a run body")

if "<!-- gate-override: new-scheduled-cron-prefer-inngest -->" not in src:
    problems.append("missing the ADR-033 gate-override marker")

# `on` parses as the boolean True in YAML 1.1 unless quoted.
triggers = wf.get("on", wf.get(True, {}))
crons = [c["cron"] for c in triggers.get("schedule", [])]
if len(crons) != 1 or not re.fullmatch(r"\d+ \d+ \* \* \*", crons[0]):
    problems.append(f"expected exactly one daily cron, got {crons}")

# Every consumer of the check step's outputs must pair the value gate with the outcome
# conjunct: an unset output is '', which Actions coerces, so a step that never ran otherwise
# reads as a verdict. And any step that writes to the issue tracker needs a status-check
# function or it inherits an implicit success() and skips exactly when the alarm fired.
STATUS_FN = re.compile(r"\b(always|failure|success|cancelled)\s*\(")

# #7493 — the reconcile dispatch is EXEMPT from the status-function rule below, and the
# exemption is the opposite of a weakening. That rule exists because an ALARM-DELIVERY step
# inheriting an implicit success() would skip exactly when an earlier step failed, i.e. when
# the alarm matters most. The dispatch step's requirement is the mirror image: it must NOT run
# when the issue step failed, because it republishes the manifest and erases the drifted bytes.
# Copying `!cancelled()` down to it — which is what a reader following the rule literally would
# do — would let remediation outrun its own evidence. So the exemption is paired with a
# POSITIVE pin below that is strictly stronger than the generic rule it replaces.
DISPATCH_STEP = "Dispatch the reconcile apply"

for s in steps:
    cond = s.get("if", "")
    body = s.get("run", "")
    name = s.get("name")
    if "steps.check.outputs" in cond and "steps.check.outcome == 'success'" not in cond:
        problems.append(f"step {name!r} gates on a check output without the outcome conjunct")
    if (
        name != DISPATCH_STEP
        and re.search(r"gh issue (create|comment|close|edit)\b", body)
        and not STATUS_FN.search(cond)
    ):
        problems.append(f"issue-writing step {name!r} has no status-check function in its if:")

# The dispatch step's `if:` is pinned POSITIVELY: it must depend on the issue having been
# delivered, must be gated on reconcile-eligibility, and must NOT carry a status function that
# would let it run past a failed alarm. Each clause is a distinct way the evidence-before-
# remediation ordering can be lost, so each is asserted separately rather than as one blob.
dispatch = next((s for s in steps if s.get("name") == DISPATCH_STEP), None)
if dispatch is None:
    problems.append(f"missing the {DISPATCH_STEP!r} step (the reconcile arm is absent)")
else:
    dcond = dispatch.get("if", "")
    if "steps.issue.outputs.delivered == '1'" not in dcond:
        problems.append("dispatch step does not require the drift issue to have been DELIVERED — remediation could erase the drifted bytes with no record")
    if "steps.check.outputs.dispatch_eligible == 'true'" not in dcond:
        problems.append("dispatch step does not gate on dispatch_eligible — it would reconcile verdicts Terraform cannot fix")
    if STATUS_FN.search(dcond):
        problems.append("dispatch step carries a status-check function; the IMPLICIT success() is load-bearing here (see the exemption note above)")
    di = next((i for i, s in enumerate(steps) if s.get("name") == DISPATCH_STEP), -1)
    ii = next((i for i, s in enumerate(steps) if s.get("id") == "issue"), -1)
    if not (ii >= 0 and di > ii):
        problems.append("dispatch step does not run AFTER the issue-filing step — evidence must precede remediation")

    # THE BODY, not only the `if:` and the position. Everything above pins the step's GATING;
    # nothing read what the step actually does, so replacing the entire body with `echo` left
    # this suite at 58/58 — and so did rewriting the run-detection poll, which is how the stale
    # -run defect below survived review-by-harness.
    dbody = dispatch.get("run") or ""
    if "gh workflow run apply-github-infra.yml" not in dbody:
        problems.append("dispatch step does not actually dispatch apply-github-infra.yml — its body is unpinned, so the gating above guards nothing")
    if "--ref main" not in dbody:
        problems.append("dispatch step does not pin --ref main; a reconcile from any other ref would apply an unreviewed tree")
    # The run-detection poll. `gh workflow run` exits 0 on ACCEPTANCE and returns no run id, so
    # without a poll a disabled/renamed/quota-blocked workflow leaves the job green with no
    # reconcile. And the poll must identify OUR run: the first draft took `.[0].databaseId` off
    # an unbounded listing and was satisfied by a run from three months earlier, ~6s in.
    if "before_id" not in dbody:
        problems.append("dispatch step does not baseline the newest run BEFORE dispatching — its poll cannot distinguish a new run from a historical one")
    if "select(. > ${before_id})" not in dbody:
        problems.append("dispatch step's poll does not require a run id strictly greater than the pre-dispatch baseline — a stale run would satisfy it")
    if "::error::" not in dbody:
        problems.append("dispatch step cannot fail loud when no run appears — an accept-then-nothing dispatch would report green")

# UNBOUND-VARIABLE LINT (#7493 review). Every step here runs under `set -u`, so a reference to a
# name the step does not define is not a typo — it aborts the step. The failure is silent in the
# worst way: it fires AFTER the useful work, so the step's own assertions all pass first, and the
# next step is then skipped by its implicit success().
#
# This is not hypothetical and it is not one bug. The same review found `${mp_checked}` in
# apply-github-infra.yml — assigned nowhere, on the LAST line of the verify step — which aborted
# every apply after all assertions passed and silently skipped the published-manifest verifier on
# every run. And writing the fix for THIS file reintroduced the identical shape: a remediation
# branch reading `$dispatch_eligible`, which is computed in the `check` step's shell and does not
# exist in the `issue` step's. Two instances, two files, one review. So it gets a lint.
#
# A name counts as defined if the step's env declares it, or the workflow/job env does, or the
# body assigns it, or it is a runner/GitHub builtin.
BUILTIN_ENV = {
    "GITHUB_OUTPUT", "GITHUB_ENV", "GITHUB_PATH", "GITHUB_STEP_SUMMARY", "GITHUB_WORKSPACE",
    "GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_RUN_ID", "GITHUB_SHA", "GITHUB_REF",
    "GITHUB_EVENT_NAME", "GITHUB_TOKEN", "GITHUB_ACTOR", "GITHUB_API_URL",
    "RUNNER_TEMP", "RUNNER_OS", "RUNNER_ARCH", "HOME", "PATH", "TMPDIR", "IFS", "SECONDS",
}
wf_env = set((wf.get("env") or {}).keys()) | set((job.get("env") or {}).keys())
# CASE-INSENSITIVE, deliberately. The first draft of this lint matched uppercase names only and
# therefore did NOT catch the bug it was written for: `dispatch_eligible` is lowercase, like every
# shell local in these steps. It caught the `mp_checked` shape and missed its own motivating case
# — a lint whose alphabet excludes the defect class it exists to find.
VAR_REF = re.compile(r'\$\{([A-Za-z_]\w*)(?::-[^}]*)?\}|\$([A-Za-z_]\w+)\b')
# `name=`, `local name=`, `export name=`, `for name in`, `read -r name`, `name+=(`
VAR_DEF = re.compile(
    r'(?:^|\n)\s*(?:local\s+|export\s+|declare\s+(?:-\w+\s+)*)?([A-Za-z_]\w*)\s*(?:\+?=|\()'
    r'|(?:^|\n)\s*for\s+([A-Za-z_]\w*)\s+in\b'
    r'|read\s+(?:-\w+\s+)*([A-Za-z_]\w*)'
)
# `local a=1 b=2 c=3` declares THREE names; the pattern above anchors at line start and so
# captures only `a`. The remaining names then read as unbound and the lint reports a step that
# is perfectly correct — which is worse than missing a bug, because a false positive on a
# hand-written guard is what trains the next reader to disable the lint. Extended for #7490,
# whose `file_or_update()` opens `local TITLE="$1" FIND="$2" PREAMBLE="$3" REMEDIATION="$4"`.
VAR_DEF_MULTI = re.compile(r'(?:^|\n)\s*(?:local|declare|export|typeset)\s+((?:-\w+\s+)*)(.+)')
def _multi_names(body):
    out = set()
    for m in VAR_DEF_MULTI.finditer(body):
        for tok in m.group(2).split():
            if '=' in tok:
                nm = tok.split('=', 1)[0]
            else:
                nm = tok
            if re.fullmatch(r'[A-Za-z_]\w*', nm):
                out.add(nm)
    return out
for st in steps:
    body = st.get("run") or ""
    if not body:
        continue
    name = st.get("name") or st.get("id") or "<unnamed>"
    defined = set(BUILTIN_ENV) | wf_env | set((st.get("env") or {}).keys())
    for m in VAR_DEF.finditer(body):
        defined.update(g for g in m.groups() if g)
    defined |= _multi_names(body)
    referenced = set()
    for m in VAR_REF.finditer(body):
        # A `${VAR:-default}` reference is explicitly guarded; it cannot abort under -u.
        if m.group(1) and ":-" in (m.group(0) or ""):
            continue
        referenced.add(m.group(1) or m.group(2))
    unbound = sorted(referenced - defined)
    if unbound:
        problems.append(
            f"step {name!r} references {unbound} which it neither declares in `env:` nor assigns; "
            "under `set -u` that aborts the step AFTER its assertions pass, and silently skips "
            "every step gated on its success"
        )

# The reconcile predicate must be computed in the `check` step's bash, not in an Actions
# expression. Actions has no split/regex/iteration, so `contains(findings, ...)` cannot tell a
# GET-2-only verdict from a MIXED one — and those need opposite decisions. Computing it in the
# step body is also what puts it inside the block this harness extracts and executes.
if "dispatch_eligible=" not in check_body:
    problems.append("dispatch_eligible is not computed in the check step body (an Actions if: cannot express the predicate, and the harness cannot drive it)")

# Unauthenticated against the WATCHED artifact by design. The only repo credential is the
# automatic token; the three Sentry values are write-only Crons INGEST identifiers (a public
# DSN's components), forwarded because the composite declares them `required: true` and Actions
# does not enforce that — they were omitted for the workflow's whole life, so the check-in never
# delivered. See the amended gate-override clause (iii).
# Unauthenticated by design. This stays a CLOSED ALLOWLIST rather than becoming a
# prefix match or being dropped: the property it protects is that a drift alarm
# cannot quietly grow into a credential consumer.
#
# The three SENTRY_* entries were added with the heartbeat repair (#7490). They are
# the components of a Sentry DSN, which is public by construction -- the same values
# ship inside browser bundles -- so admitting them does not widen the credential
# surface in the way the assertion exists to prevent. They are enumerated
# individually for that reason; `SENTRY_*` as a wildcard would also admit an auth
# token, which is a real secret.
ALLOWED_SECRETS = {
    "GITHUB_TOKEN",
    "SENTRY_INGEST_DOMAIN",
    "SENTRY_PROJECT_ID",
    "SENTRY_PUBLIC_KEY",
}
for secret in set(re.findall(r"secrets\.([A-Za-z0-9_]+)", src)):
    if secret not in ALLOWED_SECRETS:
        problems.append(f"unexpected secret consumed: {secret}")

# The heartbeat must actually be able to deliver. Asserting the three inputs are FORWARDED is
# the check that would have caught the silent no-op: the composite's own `required: true` is
# unenforced, so a missing input degrades to a ::warning:: and exit 0.
hb = next((s for s in steps if "sentry-heartbeat" in str(s.get("uses", ""))), None)
if hb is None:
    problems.append("missing the sentry-heartbeat step (no liveness channel)")
else:
    hw = hb.get("with", {}) or {}
    for req in ("sentry-ingest-domain", "sentry-project-id", "sentry-public-key"):
        if req not in hw:
            problems.append(f"sentry-heartbeat does not forward {req!r}; the composite degrades to a warning and exit 0, so the check-in silently never delivers")

if not re.search(r'^\s*MANIFEST_URL="https://raw\.githubusercontent\.com/jikig-ai/soleur-marketplace/main/\.claude-plugin/marketplace\.json"', src, re.M):
    problems.append("does not read the published marketplace manifest over raw.githubusercontent.com")
if "raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/.claude-plugin/plugin.json" not in src:
    problems.append("does not confirm plugins/soleur/.claude-plugin/plugin.json resolves at main")

if job.get("timeout-minutes") is None:
    problems.append("job has no timeout-minutes")
if wf.get("concurrency", {}).get("cancel-in-progress") is not False:
    problems.append("concurrency must not cancel in progress (racing ticks file duplicate issues)")
if wf.get("permissions", {}).get("issues") != "write":
    problems.append("job cannot open an issue: permissions.issues is not write")

print("\n".join(problems))
PY
)"
if [[ -z "$structural" ]]; then
  pass "the workflow's schedule, gating, permissions and URLs are all as specified"
else
  while IFS= read -r p; do fail "structural: $p"; done <<<"$structural"
fi

# ---- The alarm needs a DESTINATION, and the destination needs to be re-armed ------------
# Measured: deleting the entire "File or update the drift issue" step, or the entire close
# step, left this suite at 34/34 green. A detector whose filing step is gone still detects and
# tells nobody; a detector whose CLOSE step is gone files once and then dedupes against its own
# stale issue forever, suppressing every later episode. Both are the alarm failing open, and
# neither is observable through the check step this suite otherwise drives.
filing_structural="$(python3 - "$WORKFLOW" <<'ALARMPY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
# Name the job explicitly. This read used to be `list(wf["jobs"].values())[0]`,
# which silently became "whichever job is declared first" -- so adding the
# `canary` job above `drift-check` would have pointed every assertion below at a
# job that files no issues, and they would all have failed for a reason that has
# nothing to do with the property they test. A positional selector over a
# multi-job workflow is a latent misattribution, not a shortcut.
steps = wf["jobs"]["drift-check"]["steps"]
problems = []

# KEYED BY NAME, never `list(wf["jobs"].values())[0]`. This extractor used the positional form
# while the two other extractors in this file key on "drift-check", and the two disagreeing is
# the whole defect: adding a decoy job ABOVE drift-check (any job at all, even an empty one)
# repointed this block at the decoy, every `step_with()` returned nothing... and the alarm
# assertions below would then be evaluated against the wrong job. Measured during #7493 review:
# gutting the real filing step AND adding a decoy left this suite 58/58 green.
if "drift-check" not in wf.get("jobs", {}):
    problems.append("the workflow has no `drift-check` job - this suite's extractors key on it by name")
    steps = []
else:
    steps = wf["jobs"]["drift-check"]["steps"]
    # A second job is legitimate (the dispatch may be narrowed into its own job), but it must
    # never silently take over this extractor. Assert the set of jobs explicitly so ADDING one
    # is a decision this harness sees rather than a change it absorbs.
    known_jobs = {"drift-check", "canary"}
    unexpected = set(wf["jobs"]) - known_jobs
    # The canary is REGISTERED, so it must also be COVERED — registering it without assertions
    # is how a job with wider permissions slips past a harness that only counts job names. It
    # holds `contents: read` ONLY (the write-capable `issues: write` stays with drift-check,
    # which consumes the canary's verdict through job outputs and never executes what the canary
    # downloaded), and it must own a timeout.
    canary = wf["jobs"].get("canary")
    if canary is not None:
        perms = canary.get("permissions")
        if perms != {"contents": "read"}:
            problems.append(
                f"canary job permissions are {perms!r}, expected exactly {{'contents': 'read'}} — "
                "it materialises executable plugin content, so it must never hold a write scope")
        if "timeout-minutes" not in canary:
            problems.append("canary job has no timeout-minutes; a hung CLI download would pin the alarm open")
        if not (canary.get("outputs") or {}).get("verdict"):
            problems.append("canary job emits no `verdict` output — the alarm's conjunct would read empty and pass")
    if unexpected:
        problems.append(
            f"unexpected job(s) {sorted(unexpected)} - add them to known_jobs AND extend the "
            "structural assertions to cover them; an unreviewed job can hold permissions or "
            "steps this suite never inspects"
        )

def step_with(substr):
    return [st for st in steps if substr in (st.get("run") or "")]

filing = step_with("gh issue create")
if not filing:
    problems.append("no step runs `gh issue create` - a detected drift reaches the run log and nobody else")
else:
    cond = str(filing[0].get("if", ""))
    body = filing[0].get("run") or ""
    if "MISMATCH" not in cond:
        problems.append("the issue-filing step is not gated on verdict == MISMATCH")
    if "cancelled" not in cond:
        problems.append("the issue-filing step lacks a status function, so GitHub ANDs success() in")
    if "exit 1" not in body:
        problems.append("the issue-filing step cannot fail the job, so a drift whose alarm did not deliver stays green")

closing = step_with("gh issue close")
if not closing:
    problems.append("no step runs `gh issue close` - a standing issue would suppress every later episode")
elif "OK" not in str(closing[0].get("if", "")):
    problems.append("the issue-closing step is not gated on verdict == OK")

hb = [st for st in steps if "sentry-heartbeat" in str(st.get("uses", ""))]
if not hb:
    problems.append("no Sentry heartbeat - a job that stops running entirely produces no signal at all")
elif "delivered" not in str(hb[0].get("with", {}).get("status", "")):
    problems.append("the heartbeat status omits the delivered conjunct, so an undelivered alarm reports healthy")

print("\n".join(problems))
ALARMPY
)"
if [[ -z "$filing_structural" ]]; then
  pass "the alarm has a destination, a re-arm, and a liveness channel"
else
  while IFS= read -r p; do fail "alarm-structure: $p"; done <<<"$filing_structural"
fi

echo "=== Results: $PASS passed, $FAIL failed ==="

# ---- Anti-vacuity floor -----------------------------------------------------------------
# Measured: deleting every assertion call left "0 passed, 0 failed" and exit 0, and neutering
# fail()'s counter increment printed four FAIL lines and still exited 0. The exit code is the
# ONLY thing scripts/test-all.sh reads, so both are CI-green having asserted nothing.
#
# A FLOOR, not equality: an added assertion must not become a spurious failure. Derived from a
# green run, ratcheted upward deliberately. Treat slack between this and the measured count as
# attack budget rather than padding.
MIN_ASSERTIONS=66
if [[ "$PASS" -lt "$MIN_ASSERTIONS" ]]; then
  echo "ANTI-VACUITY: only $PASS assertions ran, expected at least $MIN_ASSERTIONS." >&2
  echo "Either assertions were deleted or short-circuited, or the floor needs a deliberate bump." >&2
  exit 1
fi

# ---- Second floor: the PREDICATES the structural blocks evaluate --------------------------
# The floor above counts pass()/fail() calls, and the three embedded python blocks make exactly
# THREE of them between them while evaluating ~35 predicates. So that floor is blind to the
# thing it looks like it protects: deleting the entire dispatch-pin block, or the unbound-variable
# lint, or every alarm-structure check, changes $PASS by at most one and can change it by zero —
# measured during #7493 review, where removing a whole block left the suite at 58/58 green.
#
# WHAT THIS DOES AND DOES NOT PROVE. It is a static count of `problems.append(` sites, so it
# catches DELETION — the failure mode that actually happens when a block is refactored or a
# conflict is resolved badly. It does not prove each predicate is reachable or meaningful; a dead
# append would satisfy it. That is the same guarantee MIN_ASSERTIONS gives, applied to the layer
# MIN_ASSERTIONS cannot see, and it is stated rather than implied so the next reader does not
# over-trust it.
MIN_PREDICATES=35
# `|| true` is load-bearing, not defensive. `grep -c` exits 1 on a zero count, and this suite
# runs under `set -euo pipefail` — so with every predicate deleted (the exact state this floor
# exists to catch) the script would DIE here instead of reporting the floor breach. The
# anti-vacuity check would itself have been vacuous.
#
# `|| true` and NOT `|| echo 0`: grep -c PRINTS `0` before exiting 1, so an `echo` appends a
# SECOND line and the variable becomes "0\n0", which breaks the -lt comparison below. Both the
# original bug and the wrong first fix were caught by scripts/lint-shell-capture-exit.py (S1
# then S2), which is written for exactly this pair of mistakes.
predicate_count="$(grep -c 'problems\.append(' "${BASH_SOURCE[0]}" || true)"
if [[ "$predicate_count" -lt "$MIN_PREDICATES" ]]; then
  echo "ANTI-VACUITY: the structural blocks declare only $predicate_count predicates, expected at least $MIN_PREDICATES." >&2
  echo "A python block was deleted or gutted; \$PASS cannot see that, because those blocks report through a single pass() call each." >&2
  exit 1
fi

[[ "$FAIL" -eq 0 ]]
