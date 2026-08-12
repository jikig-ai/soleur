#!/usr/bin/env bash
# Behavioural + structural gate for .github/workflows/scheduled-marketplace-drift.yml.
#
# WHY THIS EXISTS. That workflow is the ONLY control on the published marketplace manifest:
# `jikig-ai/soleur-marketplace` has no CI, no required review and no CODEOWNERS, so every edit
# to it is unreviewed by construction. A drift checker that silently reports "no drift" is
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
GOOD_MANIFEST='{"name":"soleur-marketplace","plugins":[{"name":"soleur","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}}]}'

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
VERSIONED='{"name":"soleur-marketplace","plugins":[{"name":"soleur","version":"1.2.3","source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur"}}]}'
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

WRONG_PATH='{"plugins":[{"source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"plugins/soleur-next"}}]}'
run_check "$WRONG_PATH" 0 "$GOOD_PLUGIN" 0
expect_verdict "a changed source.path is drift" "MISMATCH"
expect_finding "the path finding names source_path" "source_path"

WRONG_URL='{"plugins":[{"source":{"source":"git-subdir","url":"https://github.com/someone-else/soleur.git","path":"plugins/soleur"}}]}'
run_check "$WRONG_URL" 0 "$GOOD_PLUGIN" 0
expect_verdict "a repointed source.url is drift" "MISMATCH"
expect_finding "the url finding names source_url" "source_url"

# The ssh spelling and the suffix-less form are the SAME repository, not drift. Without this
# the alarm would cry wolf on a cosmetic edit, and an alarm that cries wolf gets muted.
SSH_URL='{"plugins":[{"source":{"source":"git-subdir","url":"git@github.com:jikig-ai/soleur","path":"plugins/soleur"}}]}'
run_check "$SSH_URL" 0 "$GOOD_PLUGIN" 0
expect_verdict "an equivalent spelling of the same repo URL is not drift" "OK"

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
run_check '{"name":"soleur-marketplace","plugins":null}' 0 "$GOOD_PLUGIN" 0
expect_verdict "a null .plugins fails CLOSED rather than reading as empty" "MISMATCH"
expect_finding "the shape failure is named" "manifest_shape"

run_check '{"name":"soleur-marketplace","plugins":[]}' 0 "$GOOD_PLUGIN" 0
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
INJECT='{"plugins":[{"source":{"source":"git-subdir","url":"https://github.com/jikig-ai/soleur.git","path":"##[set-env name=X]evil\nverdict=OK"}}]}'
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
for s in steps:
    cond = s.get("if", "")
    body = s.get("run", "")
    if "steps.check.outputs" in cond and "steps.check.outcome == 'success'" not in cond:
        problems.append(f"step {s.get('name')!r} gates on a check output without the outcome conjunct")
    if re.search(r"gh issue (create|comment|close|edit)\b", body) and not STATUS_FN.search(cond):
        problems.append(f"issue-writing step {s.get('name')!r} has no status-check function in its if:")

# Unauthenticated by design; the only credential is the automatic token.
for secret in set(re.findall(r"secrets\.([A-Za-z0-9_]+)", src)):
    if secret != "GITHUB_TOKEN":
        problems.append(f"unexpected secret consumed: {secret}")

if "raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json" not in src:
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

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
