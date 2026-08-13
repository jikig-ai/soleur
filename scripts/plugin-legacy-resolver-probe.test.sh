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
# ONE owning trap for every fixture this suite allocates (ADR-129). Registering
# inside new_fixture would not work: it is called in a command substitution, so
# an array append there happens in a SUBSHELL and is discarded — the same
# subshell-loses-state shape that makes `x=$(fn)` drop everything but stdout.
# Allocating a single parent up front and nesting each fixture under it gives
# the trap one thing to own, and the per-case `rm -rf` calls below still work.
SUITE_TMP="$(mktemp -d "${TMPDIR}/legacy-probe-suite.XXXXXXXX")" || {
  echo "FATAL: mktemp failed — cannot build the suite sandbox" >&2
  exit 2
}
cleanup_suite() {
  if [[ -n "${SUITE_TMP:-}" && -d "$SUITE_TMP" ]]; then rm -rf "$SUITE_TMP" || true; fi
  return 0
}
trap cleanup_suite EXIT

new_fixture() {
  local root
  root="$(mktemp -d "${SUITE_TMP}/legacy-probe.XXXXXXXX")" || {
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
# ---------------------------------------------------------------------------
# CASE FOLDING. GitHub repository names are case-insensitive, so `JiKiG-AI/Soleur`
# denotes the same repository as `jikig-ai/soleur`. The probe normalises with
# ascii_downcase; nothing exercised it, and review demonstrated the consequence:
# with the fold removed this machine reads `clean` while a legacy registration is
# live. A false clean here is not a test nicety -- the probe verdict is the
# evidence #7489 closes on.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
km_github "soleur" "JiKiG-AI/Soleur" true > "$r/home/.claude/plugins/known_marketplaces.json"
out="$(run_probe "$r")"
assert_jq "case-fold: a differently-cased repo is still the target" "$out" '.verdict' "legacy-present"
assert_jq "case-fold: the alias is reported"                        "$out" '.matched_aliases | join(",")' "soleur"
rm -rf "$r"

# Direction control: a genuinely different repository that merely shares a prefix
# must NOT fold into the target.
r="$(new_fixture)"
km_github "other" "jikig-ai/soleur-marketplace" true > "$r/home/.claude/plugins/known_marketplaces.json"
out="$(run_probe "$r")"
assert_jq "case-fold control: a different repo is not the target" "$out" '.verdict' "clean"
rm -rf "$r"

# ---------------------------------------------------------------------------
# THE enabledPlugins JOIN. `enabledPlugins` is a `plugin@alias` boolean map and is
# the third site a machine can resolve to the target from. Review demonstrated
# that emptying the join makes a machine carrying
# `enabledPlugins: {"soleur@soleur": true}` read `clean`.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
jq -n '{enabledPlugins: {"soleur@soleur": true}}' > "$r/home/.claude/settings.json"
out="$(run_probe "$r")"
assert_jq "enabledPlugins: an enabled plugin is not clean"   "$out" '.verdict' "unknown-present"
assert_jq "enabledPlugins: the entry resolves as an unknown" "$out" '[.enabled[] | select(.alias == "soleur") | .resolution] | join(",")' "unknown"
rm -rf "$r"

# When the alias DOES resolve to the target, the enabled entry must be reported
# as a target hit and counted, not merely as an unknown.
r="$(new_fixture)"
km_github "soleur" "jikig-ai/soleur" true > "$r/home/.claude/plugins/known_marketplaces.json"
jq -n '{enabledPlugins: {"soleur@soleur": true}}' > "$r/home/.claude/settings.json"
out="$(run_probe "$r")"
assert_jq "enabledPlugins: a resolvable enabled plugin is a target hit" "$out" '[.enabled[] | select(.alias == "soleur") | .resolution] | join(",")' "target"
assert_jq "enabledPlugins: it counts toward the summary"                "$out" '.summary.target_enabled_count' "1"
rm -rf "$r"

# ---------------------------------------------------------------------------
# REDACTION (`--redact`). Untested before this block, though it is the function
# that keeps the operator's home path and the names of UNRELATED local
# repositories out of `measurements.md` and out of bodies posted upstream. Its
# correctness is a disclosure property, so "it seemed to work when I ran it" is
# not evidence.
#
# THE ORDERING ARM IS THE POINT. `redact_path` tries the project prefix BEFORE
# the home prefix, because a project normally lives UNDER the home directory and
# a home-first substitution would consume it — the project branch could then
# never match. Every other fixture in this suite makes `home` and `project`
# SIBLINGS under the fixture root, so none of them can exercise that ordering at
# all: with siblings, either order gives the same answer. This arm nests the
# project inside the home so the two orders disagree, and pins the right one.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
mkdir -p "$r/home/nested-project/.claude"
km_github "soleur" "jikig-ai/soleur" true > "$r/home/.claude/plugins/known_marketplaces.json"
# Point the probe at a project that lives INSIDE the home dir. `--managed` is also
# aimed under the home root here, deliberately: the DEFAULT managed path is a fixed
# system location (/etc/claude-code/... or the macOS equivalent) that is byte-identical
# on every machine and so discloses nothing about the operator — it is correctly left
# unredacted, and is not one of the four categories redaction covers. Passing a temp
# path for it would put a string in the output that no production run ever produces,
# and the whole-output sweep below would then fail on the harness's own artefact
# rather than on a real disclosure.
out="$(HOME="$r/home" bash "$PROBE" --json --redact \
  --home "$r/home" --project "$r/home/nested-project" \
  --managed "$r/home/.claude/managed-settings.json")"
assert_jq "redact: a nested project is redacted as <project>, not swallowed by <home>" \
  "$out" '[.sites[] | select(.site == "project-settings") | .path] | join(",")' \
  "<project>/.claude/settings.json"
assert_jq "redact: a home-rooted site still redacts to <home>" \
  "$out" '[.sites[] | select(.site == "user-settings") | .path] | join(",")' \
  "<home>/.claude/settings.json"
# The whole point of redaction: no real path may survive anywhere in the output.
cases=$((cases + 1))
if grep -qF -- "$r" <<<"$out"; then
  fail "redact: the fixture's real absolute path leaked into --redact output"
else
  pass "redact: no real absolute path survives anywhere in the --redact output"
fi
rm -rf "$r"

# CONTROL: without --redact the real paths MUST be present. Without this, a
# `redact_path` that returned the empty string for everything would satisfy the
# leak assertion above and look like perfect redaction.
r="$(new_fixture)"
km_github "soleur" "jikig-ai/soleur" true > "$r/home/.claude/plugins/known_marketplaces.json"
out="$(run_probe "$r")"
cases=$((cases + 1))
if grep -qF -- "$r/home/.claude/settings.json" <<<"$out"; then
  pass "redact control: without --redact the real path IS reported (redaction is doing work)"
else
  fail "redact control: the unredacted run does not carry the real path — the leak assertion above proves nothing"
fi
rm -rf "$r"

# An UNRELATED local project (outside the probed project) must be reported as a
# stable placeholder, never by name. This is the second disclosure category and
# it is separate from the home/project prefixes.
r="$(new_fixture)"
km_github "soleur" "jikig-ai/soleur" true > "$r/home/.claude/plugins/known_marketplaces.json"
installed "soleur@soleur" "/somewhere/else/a-private-client-repo" \
  > "$r/home/.claude/plugins/installed_plugins.json"
out="$(HOME="$r/home" bash "$PROBE" --json --redact \
  --home "$r/home" --project "$r/project" --managed "$r/managed.json")"
cases=$((cases + 1))
if grep -qF 'a-private-client-repo' <<<"$out"; then
  fail "redact: an unrelated repository NAME leaked into --redact output"
else
  pass "redact: an unrelated repository name is replaced by a placeholder"
fi
assert_jq "redact: the unrelated project gets a stable numbered placeholder" \
  "$out" '[.installs[] | .projectPath] | join(",")' "<unrelated-local-project-1>"
rm -rf "$r"

# ---------------------------------------------------------------------------
# SITE-CHAIN COVERAGE. The probe declares SEVEN precedence sites; before this
# block only four were ever named in an assertion, so `project-settings-local`,
# `known-marketplaces` and `installed-plugins` could be deleted from the chain
# and all 38 assertions still passed — the probe would silently stop reading the
# sites it exists to read, which is the under-coverage shape it was written to
# catch in OTHERS.
#
# THE EXPECTED LIST IS PINNED, NOT DERIVED, and that is load-bearing. Deriving it
# from the probe's own `site_json` calls would make a DELETION shrink both sides
# at once and pass — the mistake this block exists to prevent. So:
# The join below covers BOTH directions on its own, because `site_json` emits one
# object per site UNCONDITIONALLY (probe, "Emits one JSON object per site, ALWAYS"):
# a deleted site shortens the joined list, an ADDED one lengthens it, and either is
# a mismatch against the literal. An earlier revision carried a second arm grepping
# `site_json "..."` out of the probe source to "catch additions"; review established
# that claim was false (the join already does), that the grep was comment-blind, and
# that its `[a-z-]+` would false-red on any future site name carrying a digit or
# underscore. Removed rather than repaired.
#
# Cardinality alone would NOT do: a renamed site keeps the count. These compare
# the joined NAMES, in the probe's own precedence order.
EXPECTED_SITES="managed-settings,user-settings,user-settings-local,project-settings,project-settings-local,known-marketplaces,installed-plugins"

r="$(new_fixture)"
out="$(run_probe "$r")"
assert_jq "sites: every declared site appears in --json, in precedence order" \
  "$out" '[.sites[].site] | join(",")' "$EXPECTED_SITES"

# Each site must carry the two fields an operator reads to act on it. A site
# present as a bare name, with no resolved path or read status, is not a reading.
# PATHS, not just non-emptiness. A non-empty check is satisfied by ANY path, so
# re-aiming a site at another file (project-settings-local -> settings.json) left
# all 48 assertions green — the site was "present" while reading the wrong file.
# Verified by mutation during review.
assert_jq "sites: each one reports a resolved path and a read status" \
  "$out" '[.sites[] | select((.path // "") != "" and (.status // "") != "")] | length' "7"
assert_jq "sites: each site resolves to its OWN documented file, not merely to something" \
  "$out" '[.sites[] | "\(.site)=\(.path | sub("^.*/(?<t>(\\.claude|managed)[^ ]*)$"; "\(.t)"))"] | join(",")' \
  "managed-settings=managed.json,user-settings=.claude/settings.json,user-settings-local=.claude/settings.local.json,project-settings=.claude/settings.json,project-settings-local=.claude/settings.local.json,known-marketplaces=.claude/plugins/known_marketplaces.json,installed-plugins=.claude/plugins/installed_plugins.json"

# Absent-vs-unreadable must stay distinguishable per site. On a fresh fixture
# nothing exists, so every site is `absent` — never `unreadable` (which means the
# probe found something and could not read it) and never silently omitted.
assert_jq "sites: an untouched machine reports every site absent, none unreadable" \
  "$out" '[.sites[] | select(.status == "absent")] | length' "7"
rm -rf "$r"

# Minimum-cardinality guard. If the fixture builder or the probe silently
# stopped producing cases, every loop above would vanish and the suite would
# exit 0 having asserted nothing.
# ---------------------------------------------------------------------------
#
# NOT ROUTED THROUGH `fail` — see the identical note in plugin-delivery-canary.test.sh.
# `fail` increments `fails` and the exit status below reads `fails`, so a neutered
# `fail` would silence every row above AND this floor, leaving the suite to exit 0
# having asserted nothing. Report and exit DIRECTLY, so the floor survives the exact
# fault it exists to detect. Proven by scripts/guard-vacuity-floor.test.sh.
if [[ "$cases" -lt 48 ]]; then
  printf '\n[FATAL] vacuity guard: only %d assertions ran; expected >= 48.\n' "$cases" >&2
  printf 'Either assertions were deleted or short-circuited, or the floor needs a deliberate bump.\n' >&2
  printf 'Total: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
  exit 1
fi

# ACCOUNTING CONSERVATION — the arm that actually catches a neutered `fail()`.
# The floor above catches "no assertions RAN". It cannot catch "assertions ran and
# their verdicts were discarded", because `cases` is incremented by the assert
# HELPERS and never by `fail` — so stubbing `fail` to a no-op leaves `cases` at its
# full value, the floor is satisfied, and the suite exits 0 with real failures
# silenced. Measured during review: `fail() { :; }` plus a genuine defect printed
# `45 passed, 0 failed (48 assertions)` and RC=0.
#
# Every assertion must record exactly one verdict, so passes+fails MUST equal cases.
# Reported directly, never through `fail`, for the same reason as the floor.
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d) — an assertion was counted but its verdict was not recorded. That is what a neutered pass()/fail() looks like.\n' \
    "$((passes + fails))" "$cases" >&2
  exit 1
fi

printf '\nTotal: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
[[ "$fails" -eq 0 ]]
