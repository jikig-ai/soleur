#!/usr/bin/env bash
# Guard 2 mutation battery for scripts/plugin-legacy-resolver-probe.sh (#7489).
#
# The probe answers ONE question: on this machine, does anything still resolve to
# jikig-ai/soleur? That question gates #7489's closing condition, so a false
# "clean" is the failure mode this battery exists to prevent — every row below is
# a shape that a naive implementation reports as clean.
#
# TMPDIR default mirrors scripts/test-all.sh: a DIRECT invocation of this suite
# (the inner loop while editing the probe) would otherwise inherit the bare /tmp
# tmpfs, and a full-tmpfs sandbox turns setup failures into confident wrong
# verdicts rather than missing ones.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$REPO_ROOT/scripts/plugin-legacy-resolver-probe.sh"

passes=0
fails=0
cases=0

pass() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '[FAIL] %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Fixture builder. Every fixture is SYNTHESIZED (cq-test-fixtures-synthesized-only)
# — nothing is copied from the operator's ~/.claude, which is also why the repo
# names below are invented rather than real local paths.
# ---------------------------------------------------------------------------

# new_fixture -> prints the fixture root. Layout:
#   <root>/home             scratch HOME
#   <root>/project          scratch project dir
#   <root>/managed.json     managed-policy file (probe is pointed at it explicitly)
new_fixture() {
  local root
  root="$(mktemp -d "${TMPDIR}/legacy-probe.XXXXXXXX")" || {
    echo "FATAL: mktemp failed — cannot build fixture sandbox" >&2
    exit 2
  }
  mkdir -p "$root/home/.claude/plugins" "$root/project/.claude" || {
    echo "FATAL: mkdir failed under $root" >&2
    exit 2
  }
  printf '%s' "$root"
}

# run_probe <fixture-root> [extra args...] -> stdout is the probe's JSON
run_probe() {
  local root="$1"
  shift
  HOME="$root/home" bash "$PROBE" --json \
    --home "$root/home" \
    --project "$root/project" \
    --managed "$root/managed.json" \
    "$@"
}

# Registration JSON for known_marketplaces.json, keyed by alias.
km_github() { # <alias> <repo> <autoUpdate>
  jq -n --arg a "$1" --arg r "$2" --argjson u "$3" \
    '{($a): {source: {source: "github", repo: $r}, autoUpdate: $u, installLocation: "x", lastUpdated: 1}}'
}

# settings.json carrying extraKnownMarketplaces
settings_ekm() { # <alias> <repo> <autoUpdate>
  jq -n --arg a "$1" --arg r "$2" --argjson u "$3" \
    '{extraKnownMarketplaces: {($a): {source: {source: "github", repo: $r}, autoUpdate: $u}}}'
}

# MEASURED SHAPE, not the assumed one. `.plugins[<key>]` is an ARRAY of install
# records, not a single object: one plugin id can be installed at several
# project scopes at once. The first version of this fixture used a bare object,
# which passed the whole battery and then crashed against the real machine —
# the fixture instantiated one member of the shape-space and production had
# another. Both shapes are exercised below.
installed() { # <key> [projectPath...] ; one record per project path (default: one)
  local k="$1"; shift
  local paths=("$@")
  [[ ${#paths[@]} -gt 0 ]] || paths=("/synthetic/project")
  local recs
  recs="$(printf '%s\n' "${paths[@]}" | jq -R -s -c '
    split("\n") | map(select(length > 0)) | map({
      scope: "project", projectPath: ., installPath: "/synthetic/cache",
      version: "0.0.0-dev", installedAt: "2020-01-01T00:00:00.000Z",
      gitCommitSha: "0000000000000000000000000000000000000000"
    })')"
  jq -n --arg k "$k" --argjson recs "$recs" '{version: 1, plugins: {($k): $recs}}'
}

# The legacy pre-array spelling, kept as a fixture so the probe stays tolerant
# of a single-object record rather than crashing on it.
installed_object_shape() { # <key>
  jq -n --arg k "$1" \
    '{version: 1, plugins: {($k): {scope: "project", projectPath: "/synthetic/project", installPath: "/synthetic/cache", version: "0.0.0-dev", gitCommitSha: "0000000000000000000000000000000000000000"}}}'
}

# assert_jq <name> <json> <jq-filter> <expected>
assert_jq() {
  local name="$1" json="$2" filter="$3" expected="$4" actual
  cases=$((cases + 1))
  actual="$(jq -r "$filter" <<<"$json" 2>/dev/null || true)"
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name (expected '$expected', got '$actual')"
  fi
}

# ---------------------------------------------------------------------------
# Guard 2 row 1 — registered under a DIFFERENT local alias.
# Alias-key matching would miss it; the predicate must match on source.repo.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
km_github "legacy" "jikig-ai/soleur" true > "$r/home/.claude/plugins/known_marketplaces.json"
out="$(run_probe "$r")"
assert_jq "row1: aliased registration is reported"        "$out" '.verdict'                        "legacy-present"
assert_jq "row1: the local alias is named, not assumed"   "$out" '.matched_aliases | join(",")'    "legacy"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Guard 2 row 2 — declared ONLY in extraKnownMarketplaces in user settings.
# This is live on the operator's machine: the registration exists in TWO files
# and a known_marketplaces-only probe sees one of them.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
settings_ekm "soleur" "jikig-ai/soleur" true > "$r/home/.claude/settings.json"
out="$(run_probe "$r")"
assert_jq "row2: extraKnownMarketplaces-only is reported" "$out" '.verdict'                        "legacy-present"
assert_jq "row2: attributed to the user-settings site"    "$out" \
  '[.sites[] | select(.registrations[]?.matches_target) | .site] | join(",")' "user-settings"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Guard 2 row 3 — settings.local.json only. The site the plan-time enumeration
# missed; found by reading the CLI bundle rather than the machine.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
settings_ekm "soleur" "jikig-ai/soleur" true > "$r/home/.claude/settings.local.json"
out="$(run_probe "$r")"
assert_jq "row3: settings.local.json is walked"           "$out" '.verdict'                        "legacy-present"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Guard 2 row 4 — managed-policy file only. The precedence-winning site: a
# declaration here cannot be overridden, so a probe that skips it can report
# clean on the one machine state the operator cannot fix locally.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
settings_ekm "soleur" "jikig-ai/soleur" true > "$r/managed.json"
out="$(run_probe "$r")"
assert_jq "row4: managed-policy site is walked"           "$out" '.verdict'                        "legacy-present"
assert_jq "row4: attributed to the managed site"          "$out" \
  '[.sites[] | select(.registrations[]?.matches_target) | .site] | join(",")' "managed-settings"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Guard 2 row 5 — project-scope settings only, user scope clean. The live
# install IS project-scoped, so a user-scope-only walk is blind to the actual
# population this issue is about.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
settings_ekm "soleur" "jikig-ai/soleur" true > "$r/project/.claude/settings.json"
out="$(run_probe "$r")"
assert_jq "row5: project-scope site is walked"            "$out" '.verdict'                        "legacy-present"
assert_jq "row5: the project path is named"               "$out" \
  '[.sites[] | select(.site == "project-settings") | .path] | length'        "1"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Guard 2 row 6 — an install whose alias resolves to NO registration.
# installed_plugins.json carries no repo field, so the join has nothing to match
# on; reporting it clean is the exact false negative this guard prevents.
# Doubles as AC3.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
installed "soleur@soleur" > "$r/home/.claude/plugins/installed_plugins.json"
out="$(run_probe "$r")"
assert_jq "row6/AC3: dangling install is not clean"       "$out" '.verdict'                        "unknown-present"
assert_jq "row6/AC3: resolution is an explicit unknown"   "$out" \
  '[.installs[] | select(.alias == "soleur") | .resolution] | join(",")'     "unknown"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Guard 2 row 7 — a HOME with no .claude directory at all (guard's own
# dispatch). "No file" must render as an enumerated absence, never as
# "no legacy install".
# ---------------------------------------------------------------------------
r="$(new_fixture)"
rm -rf "$r/home/.claude"
out="$(run_probe "$r")"
assert_jq "row7: bare HOME still enumerates the sites"    "$out" '.sites | length >= 6'            "true"
assert_jq "row7: every site carries a read status"        "$out" \
  '[.sites[] | select(.status == null)] | length'                            "0"
assert_jq "row7: every site carries a resolved path"      "$out" \
  '[.sites[] | select((.path // "") == "")] | length'                        "0"
assert_jq "row7: absence is an explicit clean verdict"    "$out" '.verdict'                        "clean"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Guard 2 row 8 — autoUpdate flipped at one site, registration otherwise
# identical. Arm B's ONLY machine write is an autoUpdate value, so without this
# field arm B's execution is byte-indistinguishable from arm C's non-execution.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
km_github "soleur" "jikig-ai/soleur" true > "$r/home/.claude/plugins/known_marketplaces.json"
before="$(run_probe "$r")"
km_github "soleur" "jikig-ai/soleur" false > "$r/home/.claude/plugins/known_marketplaces.json"
after="$(run_probe "$r")"
assert_jq "row8: autoUpdate true is reported"             "$before" \
  '[.sites[] | .registrations[]? | select(.matches_target) | .autoUpdate | tostring] | join(",")'  "true"
assert_jq "row8: autoUpdate false is reported"            "$after" \
  '[.sites[] | .registrations[]? | select(.matches_target) | .autoUpdate | tostring] | join(",")'  "false"
cases=$((cases + 1))
if [[ "$before" != "$after" ]]; then
  pass "row8: the reading changes when only autoUpdate changes"
else
  fail "row8: reading is byte-identical across an autoUpdate flip — arm B would be unobservable"
fi
rm -rf "$r"

# ---------------------------------------------------------------------------
# AC1 — the sites array is derived from the precedence CHAIN, not from what
# happens to exist. Absent -> present must change the entry's STATUS while the
# array LENGTH stays constant (row 7 already requires absent sites to be listed,
# so length growth would be the wrong assertion).
# ---------------------------------------------------------------------------
r="$(new_fixture)"
absent_out="$(run_probe "$r")"
settings_ekm "soleur" "jikig-ai/soleur" true > "$r/home/.claude/settings.local.json"
present_out="$(run_probe "$r")"
assert_jq "AC1: status is 'absent' before"                "$absent_out" \
  '[.sites[] | select(.site == "user-settings-local") | .status] | join(",")'  "absent"
assert_jq "AC1: status is 'present' after"                "$present_out" \
  '[.sites[] | select(.site == "user-settings-local") | .status] | join(",")'  "present"
cases=$((cases + 1))
a_len="$(jq -r '.sites | length' <<<"$absent_out")"
p_len="$(jq -r '.sites | length' <<<"$present_out")"
if [[ "$a_len" == "$p_len" && "$a_len" != "0" ]]; then
  pass "AC1: site-array length is chain-derived (constant at $a_len across absent->present)"
else
  fail "AC1: site-array length changed ($a_len -> $p_len) — the list is machine-derived, not chain-derived"
fi
rm -rf "$r"

# ---------------------------------------------------------------------------
# Extra row (schema reality). One install key carrying MULTIPLE records — the
# same plugin installed at two project scopes. A probe that reads the record as
# a single object reports one install and is blind to the second, which is an
# under-report of exactly the population #7489 asks about.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
km_github "soleur" "jikig-ai/soleur" true > "$r/home/.claude/plugins/known_marketplaces.json"
installed "soleur@soleur" "/synthetic/one" "/synthetic/two" \
  > "$r/home/.claude/plugins/installed_plugins.json"
out="$(run_probe "$r")"
assert_jq "multi-record: both installs are reported"      "$out" \
  '[.installs[] | select(.alias == "soleur")] | length'                      "2"
assert_jq "multi-record: both resolve to the target"      "$out" \
  '[.installs[] | select(.resolution == "target")] | length'                 "2"
assert_jq "multi-record: each project path is named"      "$out" \
  '[.installs[] | .projectPath] | sort | join(",")'        "/synthetic/one,/synthetic/two"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Tolerance for the single-object record spelling. Must not crash, must still
# classify.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
km_github "soleur" "jikig-ai/soleur" true > "$r/home/.claude/plugins/known_marketplaces.json"
installed_object_shape "soleur@soleur" > "$r/home/.claude/plugins/installed_plugins.json"
cases=$((cases + 1))
if out="$(run_probe "$r" 2>/dev/null)"; then
  pass "object-shape record does not crash the probe"
else
  fail "object-shape record crashed the probe"
  out='{}'
fi
assert_jq "object-shape record still resolves to target"  "$out" \
  '[.installs[] | select(.resolution == "target")] | length'                 "1"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Extra row (schema reality, not in the plan's matrix). known_marketplaces.json
# on the operator machine carries TWO source shapes: {source:"github",repo:...}
# and {source:"git",url:"https://github.com/..."}. A repo-only predicate is
# blind to the url form, which is the same repository spelled differently.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
jq -n '{soleur: {source: {source: "git", url: "https://github.com/jikig-ai/soleur.git"}, autoUpdate: true}}' \
  > "$r/home/.claude/plugins/known_marketplaces.json"
out="$(run_probe "$r")"
assert_jq "url-form registration is reported"             "$out" '.verdict'                        "legacy-present"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Negative control. A machine carrying ONLY an unrelated marketplace must read
# clean — otherwise every assertion above passes for the wrong reason.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
km_github "other" "someone-else/other-plugins" true > "$r/home/.claude/plugins/known_marketplaces.json"
installed "other@other" > "$r/home/.claude/plugins/installed_plugins.json"
out="$(run_probe "$r")"
assert_jq "control: unrelated marketplace reads clean"    "$out" '.verdict'                        "clean"
assert_jq "control: unrelated install is not 'unknown'"   "$out" \
  '[.installs[] | select(.resolution == "unknown")] | length'                "0"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Unreadable site must be visible as 'unreadable', never collapse to 'absent'.
# A site that cannot be parsed is the shape where a clean verdict is a lie.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
printf '{ this is not json' > "$r/home/.claude/settings.json"
out="$(run_probe "$r")"
assert_jq "unparseable site reports 'unreadable'"         "$out" \
  '[.sites[] | select(.site == "user-settings") | .status] | join(",")'      "unreadable"
assert_jq "unparseable site does not read clean"          "$out" '.verdict'                        "unknown-present"
rm -rf "$r"

# ---------------------------------------------------------------------------
# Minimum-cardinality guard. If the fixture builder or the probe silently
# stopped producing cases, every loop above would vanish and the suite would
# exit 0 having asserted nothing.
# ---------------------------------------------------------------------------
if [[ "$cases" -lt 20 ]]; then
  fail "vacuity guard: only $cases assertions ran; expected >= 20"
fi

printf '\nTotal: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
[[ "$fails" -eq 0 ]]
