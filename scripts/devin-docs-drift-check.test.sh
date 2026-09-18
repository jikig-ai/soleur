#!/usr/bin/env bash
# Behavioural gate for .github/workflows/scheduled-devin-docs-drift.yml (#8160).
#
# WHY THIS EXISTS. The workflow's header names the load-bearing property: a watch on
# the WRONG polarity is "blind while reporting healthy — the deepest failure here".
# The check step's anchors are the only thing standing between that failure and a
# green run, and nothing else executes them: the anchors fire on third-party doc
# text, so a polarity inversion or a dead regex is invisible until the day the watch
# was built for. This suite extracts the check step's `run:` body verbatim and drives
# it against synthesized fixtures — including the two directions that matter most:
# an affirmative cloud claim MUST fire, and a negated one MUST NOT.
#
# Harness notes (mirrors marketplace-drift-check.test.sh):
#   * the step declares no `shell:` key, so production runs it under `bash -e`
#     (errexit, NO pipefail). This suite runs it under `-eo pipefail` — STRICTER than
#     production, the safe direction for a guard (pipefail can only add failures).
#   * `curl` is a PATH shim keyed on the URL's full path; no scenario touches the
#     network and all fixtures are synthesized.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="${DEVIN_DOCS_DRIFT_WORKFLOW:-$REPO_ROOT/.github/workflows/scheduled-devin-docs-drift.yml}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [[ $# -lt 2 ]] || echo "        $2"; }

echo "=== devin-docs-drift-check ==="

[[ -f "$WORKFLOW" ]] || { fail "workflow exists at $WORKFLOW"; echo "=== Results: $PASS passed, $FAIL failed ==="; exit 1; }

# Extract the `check` step body — keyed on the step id, not on an index.
python3 - "$WORKFLOW" "$TMP/check.sh" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = wf["jobs"]["drift-check"]["steps"]
body = next(s["run"] for s in steps if s.get("id") == "check")
open(sys.argv[2], "w").write(body)
PY

# ---------------------------------------------------------------------------
# curl shim. fetch_doc invokes `curl <flags> <url> -o <outfile>`; the shim maps
# the URL's full path to a fixture file under $FIXTURE_DIR (basenames collide —
# plugins/overview.md vs release-notes/overview.md — so the key is the path).
# CURL_FAIL_RC, when exported, makes every fetch exit with that status.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
url="" out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
if [[ -n "${CURL_FAIL_RC:-}" ]]; then exit "$CURL_FAIL_RC"; fi
case "$url" in
  *product-guides/plugin-ecosystem.md) name="plugin-ecosystem.md" ;;
  *plugins/overview.md)              name="plugins-overview.md" ;;
  *hooks/overview.md)                name="hooks-overview.md" ;;
  *changelog/stable.md)              name="stable.md" ;;
  *release-notes/overview.md)        name="releases-overview.md" ;;
  *release-notes/2026.md)            name="releases-2026.md" ;;
  *) name="$(basename "$url")" ;;
esac
[[ -n "$out" && -f "$FIXTURE_DIR/$name" ]] && cp "$FIXTURE_DIR/$name" "$out"
exit 0
STUB
chmod +x "$TMP/bin/curl"

# ---------------------------------------------------------------------------
# Baseline fixtures — shaped like the live 2026-09-17 docs: hooks scoped local
# ("local Devin sessions" / "best effort and fail open"), subagents "not in
# cloud", the hooks reference page silent on cloud, and empty changelogs.
# ---------------------------------------------------------------------------
FX="$TMP/fixtures"
mkdir -p "$FX"

baseline_plugin_pages() {
  cat > "$FX/plugin-ecosystem.md" <<'EOF'
# Plugin ecosystem
* **Subagents** (`agents/<name>.md`) load in local Devin agents only (CLI and
  Devin Desktop), not in cloud sessions.
* **Hooks** are currently **best effort and fail open** — a hook that fails to
  load or run doesn't stop the session.
EOF
  cat > "$FX/plugins-overview.md" <<'EOF'
# Plugins overview
* Plugin subagents currently load in local Devin agents only — the CLI and
  Devin Desktop — not in cloud Devin sessions.
* **Hooks** — a `hooks.json` at the plugin root registers lifecycle hooks in
  local Devin sessions (the CLI and Devin Desktop). Plugin hooks are currently
  **best effort and fail open**.
EOF
  cat > "$FX/hooks-overview.md" <<'EOF'
# Hooks overview
Run custom logic when specific events occur during a session.
| `session_id` | Stable id for the agent session. |
EOF
}

baseline_plugin_pages
RECENT="$(date -d '2 days ago' '+%B %-d, %Y')"
cat > "$FX/stable.md" <<EOF
# Changelog
<Update label="v9.9.9" description="$RECENT">
* Unrelated improvement to session stability.
</Update>
EOF
cat > "$FX/releases-overview.md" <<EOF
# Release notes
<Update label="$RECENT">
* Unrelated improvement.
</Update>
EOF
cp "$FX/releases-overview.md" "$FX/releases-2026.md"

# run_check — executes the extracted step body; outputs land in $TMP/out.txt.
run_check() {
  : > "$TMP/out.txt"
  local rc=0
  env PATH="$TMP/bin:$PATH" \
    GITHUB_OUTPUT="$TMP/out.txt" \
    FIXTURE_DIR="$FX" \
    bash --noprofile --norc -eo pipefail "$TMP/check.sh" > "$TMP/log.txt" 2>&1 || rc=$?
  STEP_RC="$rc"
  VERDICT="$(sed -n 's/^verdict=//p' "$TMP/out.txt" | head -1)"
  FINDINGS="$(sed -n '/^findings<</,/^DEVIN_DOCS_DRIFT_FINDINGS_EOF$/p' "$TMP/out.txt")"
}

expect_verdict() {
  local label="$1" want="$2"
  if [[ "$VERDICT" == "$want" ]]; then pass "$label"
  else fail "$label" "verdict='$VERDICT' (want '$want'), step_rc=$STEP_RC, findings: $(tr '\n' ' ' <<<"$FINDINGS" | cut -c1-300)"; fi
}
expect_finding() {
  local label="$1" key="$2"
  if grep -q "$key" <<<"$FINDINGS"; then pass "$label"
  else fail "$label" "expected finding key '$key' absent; findings: $(tr '\n' ' ' <<<"$FINDINGS" | cut -c1-300)"; fi
}
expect_no_finding() {
  local label="$1" key="$2"
  if grep -q "$key" <<<"$FINDINGS"; then fail "$label" "unexpected finding key '$key' present: $(tr '\n' ' ' <<<"$FINDINGS" | cut -c1-300)"
  else pass "$label"; fi
}

# --- Scenario 1: baseline docs → clean verdict -------------------------------
run_check
expect_verdict "baseline docs verdict OK" "OK"
[[ "$STEP_RC" == "0" ]] && pass "baseline step exits 0 (verdict-as-data)" || fail "baseline step exits 0" "rc=$STEP_RC"

# --- Scenario 2: affirmative cloud-hook claim on the hooks reference page ----
printf '* Hooks now run in cloud sessions as well as local sessions.\n' >> "$FX/hooks-overview.md"
run_check
expect_verdict "affirmative hook+cloud claim → DRIFT" "DRIFT"
expect_finding "fires hooks_cloud_claimed" "hooks_cloud_claimed"

# --- Scenario 3: NEGATED claims must not fire ---------------------------------
baseline_plugin_pages
printf '* Hooks do not run in cloud sessions.\n' >> "$FX/hooks-overview.md"
printf '* Plugin subagents are not supported in cloud sessions.\n' >> "$FX/hooks-overview.md"
run_check
expect_verdict "negated claims stay OK" "OK"
expect_no_finding "no hooks_cloud_claimed on negation" "hooks_cloud_claimed"
expect_no_finding "no subagent_cloud_claimed on negation" "subagent_cloud_claimed"

# --- Scenario 4: additive subagent claim alongside surviving limitation -------
baseline_plugin_pages
printf '* Plugin subagents are now also available in cloud sessions.\n' >> "$FX/plugins-overview.md"
run_check
expect_verdict "additive subagent claim → DRIFT" "DRIFT"
expect_finding "fires subagent_cloud_claimed" "subagent_cloud_claimed"

# --- Scenario 5: PRESENT anchors removed → claims-changed findings ------------
cat > "$FX/plugin-ecosystem.md" <<'EOF'
# Plugin ecosystem
* Plugins extend Devin in many ways.
EOF
run_check
expect_verdict "gutted limitations page → DRIFT" "DRIFT"
expect_finding "fires hooks_locality_claim_changed" "hooks_locality_claim_changed"
expect_finding "fires subagent_limitation_changed" "subagent_limitation_changed"

# --- Scenario 6: changelog capability entry inside the window -----------------
baseline_plugin_pages
cat > "$FX/stable.md" <<EOF
# Changelog
<Update label="v9.9.9" description="$RECENT">
* Plugin hooks now dispatch in cloud sessions.
</Update>
EOF
run_check
expect_verdict "recent capability entry → DRIFT" "DRIFT"
expect_finding "fires capability_entry" "capability_entry"

# --- Scenario 7: 'webhook' substring must not match the hook anchor -----------
cat > "$FX/stable.md" <<EOF
# Changelog
<Update label="v9.9.9" description="$RECENT">
* Webhook deliveries to cloud endpoints are more reliable.
</Update>
EOF
run_check
expect_verdict "webhook+cloud item stays OK" "OK"
expect_no_finding "no capability_entry on webhook" "capability_entry"

# --- Scenario 8: whole-block false-positive guard ------------------------------
# A hook item and an unrelated cloud item in DIFFERENT bullets must not pair.
cat > "$FX/stable.md" <<EOF
# Changelog
<Update label="v9.9.9" description="$RECENT">
* Improved plugin hooks reliability locally.
* Cloud session stability improved.
</Update>
EOF
run_check
expect_verdict "split hook/cloud items stay OK" "OK"
expect_no_finding "no capability_entry on split items" "capability_entry"

# --- Scenario 9: fetch failure is a finding, never green -----------------------
cat > "$FX/stable.md" <<EOF
# Changelog
<Update label="v9.9.9" description="$RECENT">
* Unrelated improvement.
</Update>
EOF
export CURL_FAIL_RC=22
run_check
unset CURL_FAIL_RC
expect_verdict "transport failure → DRIFT" "DRIFT"
expect_finding "fires fetch_failed" "fetch_failed"

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
