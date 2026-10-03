#!/usr/bin/env bash
# check-web-host-escrow-config.test.sh -- behavioural suite for the web-host escrow-split contract
# checker (#9377, ADR-263 R4 narrowing; Guard 3 of the #9356/#9357/#9358/#9377/#9378 plan).
#
# THE PROPERTY UNDER TEST. Every path executed on a web-class host (a host born through the fresh-boot
# path) selects `prd_workspaces_luks_web` as its Doppler config, and web-1's paths keep
# `prd_workspaces_luks`. The static census is a CI guard, not production detection: it fails the PR that
# moves a web-class path back onto the config that holds web-1's escrow pair.
#
# MUTATION-PROVEN, never trusted green. Each row below applies ONE deliberate violation to a scratch copy of
# the infra tree and the checker must go RED, naming the file; the must-PASS rows (a comment that mentions the
# web-1 config name) must stay GREEN. A positive control (the real tree is GREEN) precedes the mutation rows:
# without it a "went red" row is indistinguishable from "was already red".
#
# THE DOPPLER STUB REPLAYS THE REAL CLI CONTRACT, it does not invent one:
#   - `doppler secrets --only-names -p P -c C` prints a TABLE (header `NAME`, a `----` rule, then one name per
#     row), per the repo's own recorded runs (learnings 2026-03-29-doppler-service-token-config-scope-mismatch.md,
#     2026-09-19-the-explained-pin-was-columns-not-members.md). The exact table furniture is not locally measurable
#     without a valid token, so the stub replays TWO shapes (plain header+rule, and a boxed table) and the checker
#     must parse both.
#   - a failed read exits 1 with `Unable to fetch secret names` + `Doppler Error: <reason>` on STDERR and nothing
#     on stdout (MEASURED against the real v3.76 CLI with an invalid token on 2026-10-02: rc=1, stdout empty;
#     `--json` writes {"error":"Invalid Auth token"} to stderr). A token scoped to another config fails with the
#     substring `does not have access to requested config` (scripts/check-cloudflare-token-drift.sh matches it).
#   - a missing -p / -c / --only-names is a HARD STUB ERROR (rc 64): the real CLI would bind whatever the
#     environment carried and grade another config's names, so a stub that answered anyway would let a dropped
#     `-c <cfg>` pass every verdict row (the check-cloudflare-token-drift.test.sh precedent).
#
# Run: bash scripts/check-web-host-escrow-config.test.sh
# NOT globbed: scripts/*.test.sh is registered by an explicit run_suite line in scripts/test-all.sh.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$SRC_ROOT/scripts/check-web-host-escrow-config.sh"
REAL_INFRA="$SRC_ROOT/apps/web-platform/infra"

passes=0
fails=0
ok() { passes=$((passes + 1)); echo "[ok] $1"; }
no() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

[[ -f "$SUT" ]] || { echo "[FAIL] SUT not found: $SUT (RED: the checker does not exist yet)" >&2; exit 1; }

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
SCR="$(mktemp -d "$TMPDIR/escrow-census.XXXXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SCR"
trap 'rm -rf "${SCR:?}"' EXIT

# ---------------------------------------------------------------------------------------------------
# Static census fixtures: a scratch copy of the infra tree (minus .terraform and the heavy rehearsal roots).
# ---------------------------------------------------------------------------------------------------
mk_tree() { # -> prints the path of a fresh copy (called in a subshell, so the name must not come from a counter)
  local d
  d="$(mktemp -d "$SCR/tree.XXXXXXXX")" || return 1
  ( cd "$REAL_INFRA" && tar --exclude=.terraform --exclude=rung2-rehearsal --exclude=git-data-root-key -cf - . ) | ( cd "$d" && tar -xf - )
  printf '%s' "$d"
}

# run_static <root> -> sets OUT, RC
run_static() {
  OUT="$(bash "$SUT" --static --root "$1" 2>&1)"; RC=$?
}

mutate() { # <root> <file> <sed-expr>: fail the suite row if the mutation did not land
  local before after
  before="$(cksum < "$1/$2")"
  sed -i -E "$3" "$1/$2"
  after="$(cksum < "$1/$2")"
  [[ "$before" != "$after" ]]
}

expect_red() { # <label> <root> <needle in output>
  run_static "$2"
  if [[ "$RC" -ne 0 && "$OUT" == *"$3"* ]]; then ok "$1 -> RED naming '$3' (rc=$RC)"; else no "$1: expected RED naming '$3', got rc=$RC: ${OUT:0:300}"; fi
}
expect_green() { # <label> <root>
  run_static "$2"
  if [[ "$RC" -eq 0 && "$OUT" == *"escrow-split-contract:ok"* ]]; then ok "$1 -> GREEN (rc=0)"; else no "$1: expected GREEN, got rc=$RC: ${OUT:0:300}"; fi
}

live_expect() { # <label> <rc> <needle>
  if [[ "$RC" -eq "$2" && "$OUT" == *"$3"* ]]; then ok "$1 (rc=$RC)"; else no "$1: expected rc=$2 containing '$3', got rc=$RC: ${OUT:0:400}"; fi
}
live_expect_line() { # <label> <rc> <exact output line>: a whole-line match, so a longer line that merely contains it does not count
  if [[ "$RC" -eq "$2" ]] && grep -qxF -- "$3" <<<"$OUT"; then ok "$1 (rc=$RC)"; else no "$1: expected rc=$2 with the exact line '$3', got rc=$RC: ${OUT:0:400}"; fi
}

# --- INSTRUMENT SELF-TEST ----------------------------------------------------------------------------------
# Every verdict below is owned by expect_red / expect_green / live_expect / live_expect_line. A helper that records a
# pass whatever the checker did would leave every row green, so each helper is driven once in BOTH directions here and
# must move the pass and fail counters by exactly one each. This block reports through printf + exit, never through
# the helpers it checks, and restores the counters so the exact count below is unaffected.
E0="$SCR/empty-root"; mkdir -p "$E0"
BASE="$(mk_tree)"; assert_fixture_dir "$BASE"
_p0=$passes; _f0=$fails
{
  expect_green "self-test" "$BASE";               expect_green "self-test" "$E0"
  expect_red "self-test" "$E0" "census-empty";    expect_red "self-test" "$BASE" "census-empty"
  RC=0; OUT="x"; live_expect "self-test" 0 "x";   live_expect "self-test" 1 "x"
  live_expect_line "self-test" 0 "x";             live_expect_line "self-test" 0 "y"
} >/dev/null 2>&1
if [[ "$passes" -ne $((_p0 + 4)) || "$fails" -ne $((_f0 + 4)) ]]; then
  printf '[FATAL] instrument self-test: expect_red/expect_green/live_expect/live_expect_line did not move the counters by +4 passes/+4 fails (passes %s->%s, fails %s->%s)\n' "$_p0" "$passes" "$_f0" "$fails" >&2
  exit 2
fi
passes=$_p0; fails=$_f0

# --- Positive control: the real tree is GREEN ------------------------------------------------------------
expect_green "S0 positive control: the repo tree satisfies the census" "$BASE"

# The REAL tree, un-copied, is the contract the PR ships.
run_static "$REAL_INFRA"
if [[ "$RC" -eq 0 && "$OUT" == *"escrow-split-contract:ok"* ]]; then ok "S0b the real infra tree prints escrow-split-contract:ok"; else no "S0b the REAL tree fails the census: ${OUT:0:400}"; fi

# --- Guard 3 mutation matrix ------------------------------------------------------------------------
# row 1: cloud-init's printf reverted to web-1's config
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" cloud-init.yml 's#(WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks)_web#\1#' && expect_red "G3-1 cloud-init printf reverted to prd_workspaces_luks" "$T" "cloud-init.yml" || no "G3-1 mutation did not land"

# row 2: a NEW web-class script hardcodes the web-1 config (an unclassified file with a bare occurrence)
T="$(mk_tree)"; assert_fixture_dir "$T"
printf '#!/usr/bin/env bash\ndoppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks\n' > "$T/web-new-reader.sh"
expect_red "G3-2 a new script hardcodes --config prd_workspaces_luks" "$T" "web-new-reader.sh"
# row 2b: the existing provisioner gains a literal read
T="$(mk_tree)"; assert_fixture_dir "$T"
printf 'doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks\n' >> "$T/workspaces-luks-provision.sh"
expect_red "G3-2b the provisioner gains a literal --config prd_workspaces_luks read" "$T" "workspaces-luks-provision.sh: hardcodes --config prd_workspaces_luks"
# row 2c: the reopen script hardcodes the config name instead of reading the boot env file
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" workspaces-luks-reopen.sh 's#--config "\$WORKSPACES_DOPPLER_CONFIG"#--config prd_workspaces_luks#' && expect_red "G3-2c reopen hardcodes the config" "$T" "workspaces-luks-reopen.sh" || no "G3-2c mutation did not land"

# row 3: the fresh-boot token re-pointed back to web-1's config; and server.tf re-pointed at the pre-split token
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" workspaces-luks-fresh-boot.tf '/"workspaces_luks_fresh_boot_web"/,/^}/ s/config([[:space:]]*)=([[:space:]]*)doppler_config\.workspaces_luks_web\.name/config\1=\2"prd_workspaces_luks"/' \
  && expect_red "G3-3 the web fresh-boot token re-pointed to prd_workspaces_luks" "$T" "workspaces-luks-fresh-boot.tf" || no "G3-3 mutation did not land"
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" server.tf 's/doppler_service_token\.workspaces_luks_fresh_boot_web\.key/doppler_service_token.workspaces_luks_fresh_boot.key/' \
  && expect_red "G3-3b server.tf hands user_data the PRE-SPLIT token (still reads web-1's pair)" "$T" "server.tf" || no "G3-3b mutation did not land"

# row 4: a second literal read appended to luks-monitor.sh after the parameterized key read
T="$(mk_tree)"; assert_fixture_dir "$T"
printf 'key2="$(doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks 2>/dev/null || true)"\n' >> "$T/luks-monitor.sh"
expect_red "G3-4 a second literal --config prd_workspaces_luks key read after the parameterized one" "$T" "luks-monitor.sh"
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" luks-monitor.sh 's#(WORKSPACES_LUKS_KEY --plain --config )"\$[A-Za-z_]+"#\1prd_workspaces_luks#' \
  && expect_red "G3-4b the monitor's key read reverted to the literal" "$T" "luks-monitor.sh" || no "G3-4b mutation did not land"
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" luks-monitor.sh 's#(WORKSPACES_LUKS_HEARTBEAT_URL --plain --config )prd_workspaces_luks#\1prd_workspaces_luks_web#' \
  && expect_red "G3-4c the heartbeat read moved off prd_workspaces_luks (web-1 primary profile would lose its URL)" "$T" "luks-monitor.sh: the heartbeat read must stay on prd_workspaces_luks" || no "G3-4c mutation did not land"

# row 5: the census enumerates zero occurrences (path glob broken / wrong root) must be RED, never "nothing to check"
expect_red "G3-5 the census over an empty root" "$E0" "census-empty"
T="$(mk_tree)"; assert_fixture_dir "$T"
for f in luks-monitor-token-refresh.sh workspaces-cutover.sh uptime-alerts.tf workspaces-luks.tf workspaces-luks-header.tf; do
  sed -i -E 's/prd_workspaces_luks([^_A-Za-z0-9]|$)/prd_gone\1/g' "$T/$f"
done
expect_red "G3-5b every web-1 path stops naming prd_workspaces_luks (stale exclusion list, or a broken scan, must not read as clean)" "$T" "web-1"

# H1: the harness, run against a tree with one injected violation, REPORTS it by file name (not just a bare rc)
T="$(mk_tree)"; assert_fixture_dir "$T"
printf 'WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks\n' > "$T/soleur-host-bootstrap-injected.sh"
run_static "$T"
if [[ "$RC" -ne 0 && "$OUT" == *"soleur-host-bootstrap-injected.sh"* ]]; then ok "H1 an injected violation is reported by file name (rc=$RC)"; else no "H1 the injected violation was not reported by name: rc=$RC ${OUT:0:300}"; fi

# H2 (must-PASS): a COMMENT naming the web-1 config in a web-class file does not trip the census
T="$(mk_tree)"; assert_fixture_dir "$T"
printf '  # web-1 keeps prd_workspaces_luks; this comment names it and must not trip the census\n' >> "$T/cloud-init.yml"
printf '# web-1 keeps `--config prd_workspaces_luks` for its own paths\n' >> "$T/luks-monitor.sh"
printf '# a comment: WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks\n' >> "$T/workspaces-luks-reopen.sh"
expect_green "H2 comments naming prd_workspaces_luks in web-class files" "$T"

# web-1 paths KEEP the un-suffixed name (check 17d's counterpart at census level): the SSH installer must not move
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" workspaces-luks.tf "s#'prd_workspaces_luks'#'prd_workspaces_luks_web'#" \
  && expect_red "W1-1 web-1's SSH installer moved to the web config" "$T" "workspaces-luks.tf" || no "W1-1 mutation did not land"
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" luks-monitor-token-refresh.sh 's#--config prd_workspaces_luks#--config prd_workspaces_luks_web#' \
  && expect_red "W1-2 the web-1-only token refresh moved to the web config" "$T" "luks-monitor-token-refresh.sh" || no "W1-2 mutation did not land"

# Provisioner closed set: a provisioner that names only the un-suffixed config leaves a web-class host dark at birth
T="$(mk_tree)"; assert_fixture_dir "$T"
sed -i -E 's/prd_workspaces_luks_web/prd_workspaces_luks_wXb/g' "$T/workspaces-luks-provision.sh"
printf '[ "$CFG" = prd_workspaces_luks ] || fatal config 10 "x"\n' >> "$T/workspaces-luks-provision.sh"
expect_red "P-1 the provisioner does not accept the web config name" "$T" "workspaces-luks-provision.sh: does not accept prd_workspaces_luks_web"

# The reopen-failure unit's documented absent-file default is the ONE allowed bare occurrence there
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" workspaces-luks-reopen-failure.service 's#\$\{WORKSPACES_DOPPLER_CONFIG:-prd_workspaces_luks\}#prd_workspaces_luks#' \
  && expect_red "RF-1 the failure unit hardcodes the config instead of the env-file default" "$T" "workspaces-luks-reopen-failure.service" || no "RF-1 mutation did not land"

# --- Per-file census checks: one planted violation per check (each check removed alone must red its row) --------
plant_red() { # <label> <file> <code line appended to it> <needle: the check's own message, naming the file>
  local t; t="$(mk_tree)"; assert_fixture_dir "$t"
  printf '%s\n' "$3" >> "$t/$2"
  expect_red "$1" "$t" "$4"
}
plant_red "C-1 cloud-init.yml gains a bare prd_workspaces_luks code line" cloud-init.yml '  - echo prd_workspaces_luks' \
  "escrow-split-contract:FAIL cloud-init.yml: names web-1's prd_workspaces_luks in code"
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" workspaces-luks-provision.sh 's#--config "\$CFG"#--config "$KEYCFG"#' \
  && expect_red "C-2 the provisioner key read stops selecting --config \"\$CFG\"" "$T" "workspaces-luks-provision.sh: the key read must select the config from the boot env file" || no "C-2 mutation did not land"
plant_red "C-3 workspaces-luks-reopen.sh gains a bare prd_workspaces_luks code line" workspaces-luks-reopen.sh 'echo prd_workspaces_luks' \
  "escrow-split-contract:FAIL workspaces-luks-reopen.sh: names web-1's prd_workspaces_luks in code"
plant_red "C-4 workspaces-luks-reopen.service gains a bare prd_workspaces_luks code line" workspaces-luks-reopen.service 'Environment=CFG=prd_workspaces_luks' \
  "escrow-split-contract:FAIL workspaces-luks-reopen.service: names web-1's prd_workspaces_luks in code"
plant_red "C-5 luks-monitor.sh gains a SECOND heartbeat read (exactly one is allowed)" luks-monitor.sh \
  'hb2="$(doppler secrets get WORKSPACES_LUKS_HEARTBEAT_URL --plain --config prd_workspaces_luks 2>/dev/null || true)"' \
  "luks-monitor.sh: the heartbeat read must stay on prd_workspaces_luks (exactly one"
plant_red "C-6 luks-monitor.sh gains an undocumented bare prd_workspaces_luks line" luks-monitor.sh 'echo prd_workspaces_luks' \
  "luks-monitor.sh: an undocumented bare prd_workspaces_luks occurrence"
plant_red "C-7 workspaces-luks-fresh-boot.tf names prd_workspaces_luks outside the pre-split token resource" workspaces-luks-fresh-boot.tf \
  'locals { stray = "prd_workspaces_luks" }' \
  "workspaces-luks-fresh-boot.tf: names prd_workspaces_luks outside the pre-split token resource"
plant_red "C-8 server.tf gains a bare prd_workspaces_luks code line" server.tf 'locals { stray = "prd_workspaces_luks" }' \
  "escrow-split-contract:FAIL server.tf: names web-1's prd_workspaces_luks in code"
plant_red "C-9 soleur-host-bootstrap.sh gains a bare prd_workspaces_luks code line" soleur-host-bootstrap.sh 'echo prd_workspaces_luks' \
  "escrow-split-contract:FAIL soleur-host-bootstrap.sh: names web-1's prd_workspaces_luks in code"

# --- Token-address census (a templatefile map key / local / output re-pointed at a web-1-scoped token) -------------
plant_red "TK-1 a NEW .tf file addresses the PRE-SPLIT token (a templatefile map key re-pointed at it)" web-new-map.tf \
  'locals { vars = { workspaces_luks_fresh_boot_token = doppler_service_token.workspaces_luks_fresh_boot.key } }' \
  "escrow-split-contract:FAIL web-new-map.tf: addresses the pre-split token"
plant_red "TK-2 server.tf gains a second reference to the PRE-SPLIT token" server.tf \
  'locals { stray = doppler_service_token.workspaces_luks_fresh_boot.key }' \
  "escrow-split-contract:FAIL server.tf: addresses the pre-split token"
plant_red "TK-3 a NEW .tf file addresses web-1's token outside its definition file" web-new-map.tf \
  'locals { vars = { workspaces_luks_fresh_boot_token = doppler_service_token.workspaces_luks.key } }' \
  "escrow-split-contract:FAIL web-new-map.tf: addresses web-1's token doppler_service_token.workspaces_luks in code outside its definition file"
T="$(mk_tree)"; assert_fixture_dir "$T"
printf '%s\n' '# comment only: doppler_service_token.workspaces_luks_fresh_boot and doppler_service_token.workspaces_luks are not referenced here' \
  'locals { vars = { a = doppler_service_token.workspaces_luks_fresh_boot_web.key, b = doppler_service_token.workspaces_luks_marker_write.key } }' > "$T/web-new-ok.tf"
expect_green "TK-4 (must-pass) a comment, the _web token and the _marker_write token do not trip the token-address census" "$T"
T="$(mk_tree)"; assert_fixture_dir "$T"
sed -i -E 's/doppler_service_token\.workspaces_luks([^A-Za-z0-9_]|$)/doppler_service_token.workspaces_luks_gone\1/g' "$T/workspaces-luks.tf"
expect_red "TK-5 web-1's definition file stops addressing its token (a broken scan must not read as clean)" "$T" "the token-address census found no reference"

# --- Guard 1: the web-class passphrase is independent of web-1's (#9377 decision A1) ---------------------------
# The whole-tree census: the word-bounded address random_password.workspaces_luks (not _web) may appear in code only in
# workspaces-luks.tf. Value distinctness is NOT checkable offline; this proves no code path derives the web-class
# value from web-1's generator.
T="$(mk_tree)"; assert_fixture_dir "$T"
mutate "$T" workspaces-luks-header-web.tf 's/random_password\.workspaces_luks_web\.result/random_password.workspaces_luks.result/' \
  && expect_red "PW-1 the web-class key secret re-pointed at web-1's random_password" "$T" "workspaces-luks-header-web.tf: names web-1's random_password.workspaces_luks" || no "PW-1 mutation did not land"
plant_red "PW-2 a second reference to web-1's random_password in server.tf (a local laundering the value)" server.tf \
  'locals { stray = random_password.workspaces_luks.result }' \
  "escrow-split-contract:FAIL server.tf: names web-1's random_password.workspaces_luks"
plant_red "PW-2b a NEW .tf file outputs web-1's random_password" web-new-output.tf \
  'output "leak" { value = random_password.workspaces_luks.result }' \
  "escrow-split-contract:FAIL web-new-output.tf: names web-1's random_password.workspaces_luks"
plant_red "PW-2c a NEW .sh file names web-1's random_password" web-new-pw.sh \
  'echo random_password.workspaces_luks.result' \
  "escrow-split-contract:FAIL web-new-pw.sh: names web-1's random_password.workspaces_luks"
T="$(mk_tree)"; assert_fixture_dir "$T"
rm -f "$T/workspaces-luks-header-web.tf"
expect_red "PW-3 the web-class header file is missing from the root (census-empty, never a pass)" "$T" "census-empty: workspaces-luks-header-web.tf"
# must-PASS: a comment naming the address for contrast, the _web address itself, and web-1's own file naming its password
T="$(mk_tree)"; assert_fixture_dir "$T"
printf '# contrast: web-1 uses random_password.workspaces_luks; this file uses random_password.workspaces_luks_web\n' >> "$T/workspaces-luks-header-web.tf"
printf '# random_password.workspaces_luks is web-1-only\n' >> "$T/server.tf"
expect_green "PW-4 (must-pass) comments naming random_password.workspaces_luks, and the _web address in code" "$T"
if grep -qE 'random_password\.workspaces_luks_web\.result' "$T/workspaces-luks-header-web.tf" && grep -qE 'random_password\.workspaces_luks\.result' "$T/workspaces-luks.tf"; then ok "PW-4b the must-pass tree still carries the _web reference and web-1's own reference (the census is not vacuous)"; else no "PW-4b the must-pass tree lost one of the two references"; fi

# --- CLI contract of the checker itself ---------------------------------------------------------------
bash "$SUT" >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "U1 no mode given -> usage error rc=2"; else no "U1 expected rc=2 with no mode, got $rc"; fi
bash "$SUT" --bogus >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "U2 unknown mode -> usage error rc=2"; else no "U2 expected rc=2 for an unknown mode, got $rc"; fi

# ---------------------------------------------------------------------------------------------------
# Live mode against a stub doppler
# ---------------------------------------------------------------------------------------------------
STUB_DIR="$SCR/stubbin"; MOCK="$SCR/mock"; mkdir -p "$STUB_DIR" "$MOCK"
cat > "$STUB_DIR/doppler" <<'STUB'
#!/usr/bin/env bash
# Replays the real CLI's contract for `doppler secrets --only-names`. See the suite header.
printf '%s\n' "$*" >> "${MOCK_LOG:?}"
[[ "${1:-}" == "secrets" ]] || { echo "STUB ERROR: unexpected subcommand '$*'" >&2; exit 64; }
shift
only=0; proj=""; cfg=""
while (($#)); do
  case "$1" in
    --only-names) only=1 ;;
    -p|--project) proj="${2:-}"; shift ;;
    -c|--config)  cfg="${2:-}"; shift ;;
    --no-check-version) ;;
    *) echo "STUB ERROR: unexpected flag '$1'" >&2; exit 64 ;;
  esac
  shift
done
[[ "$only" == 1 ]] || { echo "STUB ERROR: only --only-names reads are modelled" >&2; exit 64; }
[[ -n "$proj" ]] || { echo "STUB ERROR: --only-names invoked with no -p <project>" >&2; exit 64; }
[[ -n "$cfg" ]] || { echo "STUB ERROR: --only-names invoked with no -c <config>" >&2; exit 64; }
# Measured against the real CLI: no/invalid token -> rc 1, message on STDERR, stdout empty.
if [[ -z "${DOPPLER_TOKEN:-}" || "${DOPPLER_TOKEN}" == "bogus" ]]; then
  printf 'Unable to fetch secret names\nDoppler Error: Invalid Auth token\n' >&2; exit 1
fi
if [[ ",${MOCK_UNREADABLE:-}," == *",${cfg},"* ]]; then
  printf 'Unable to fetch secret names\nDoppler Error: This token does not have access to requested config%s\n' "${MOCK_LEAKTOK:+ (token ${MOCK_LEAKTOK})}" >&2; exit 1
fi
file="${MOCK_DIR:?}/${cfg}.names"
[[ -f "$file" ]] || { printf 'Unable to fetch secret names\nDoppler Error: Could not find requested config\n' >&2; exit 1; }
case "${MOCK_SHAPE:-plain}" in
  plain) printf 'NAME\n----\n'; cat "$file" ;;
  boxed) printf '┌────────────┐\n│ NAME       │\n├────────────┤\n'; while read -r l; do [[ -n "$l" ]] && printf '│ %-10s │\n' "$l"; done < "$file"; printf '└────────────┘\n' ;;
  noheader) cat "$file" ;;   # an unrecognised shape: the checker must refuse it, never read it as "no names"
esac
exit 0
STUB
chmod +x "$STUB_DIR/doppler"
MOCK_LOG="$SCR/doppler.log"

seed_web()   { printf '%s\n' DOPPLER_PROJECT DOPPLER_ENVIRONMENT DOPPLER_CONFIG WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY SENTRY_DSN > "$MOCK/prd_workspaces_luks_web.names"; }
seed_prd()   { printf '%s\n' DOPPLER_PROJECT DOPPLER_CONFIG SENTRY_DSN CF_API_TOKEN DATABASE_URL SOME_SECRET > "$MOCK/prd.names"; }
reset_mock() { rm -f "$MOCK"/*.names "$MOCK_LOG"; : > "$MOCK_LOG"; seed_web; seed_prd; }

run_live() { # [env assignments...]
  OUT="$(env PATH="$STUB_DIR:$PATH" MOCK_DIR="$MOCK" MOCK_LOG="$MOCK_LOG" DOPPLER_TOKEN=tok "$@" bash "$SUT" --live 2>&1)"; RC=$?
}
reset_mock; run_live
live_expect "L1 all five names present in the web config, the R2 pair absent from prd -> contract holds" 0 "escrow-split-contract:live-ok"
if [[ "$(grep -c -- '--only-names' "$MOCK_LOG")" -ge 2 ]] && grep -qE -- '-c prd_workspaces_luks_web' "$MOCK_LOG" && grep -qE -- '-c prd( |$)' "$MOCK_LOG" && ! grep -qE -- 'get |run|download' "$MOCK_LOG"; then
  ok "L1b live mode reads NAMES only (--only-names on the web config and on the prd root; never get/run/download)"
else
  no "L1b live mode did not use names-only reads on exactly the two configs: $(tr '\n' ';' < "$MOCK_LOG")"
fi

reset_mock; run_live MOCK_SHAPE=boxed
live_expect "L2 the boxed-table shape parses identically" 0 "escrow-split-contract:live-ok"

for missing in WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY; do
  reset_mock; grep -vx "$missing" "$MOCK/prd_workspaces_luks_web.names" > "$MOCK/w.tmp"; mv "$MOCK/w.tmp" "$MOCK/prd_workspaces_luks_web.names"
  run_live
  live_expect "L3 ${missing} absent from the web config -> RED naming it" 1 "$missing"
done

for leaked in WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY WORKSPACES_LUKS_KEY; do
  reset_mock; echo "$leaked" >> "$MOCK/prd.names"
  run_live
  live_expect "L4 ${leaked} present in the prd root (a branch config would inherit it) -> RED" 1 "$leaked"
done

reset_mock; printf '%s\n' R2_BACKUP_TOKEN AWS_ACCESS_KEY_ID CLOUDFLARE_ZONE_ID >> "$MOCK/prd.names"
run_live
live_expect "L5 advisory scan lists prd names matching R2|CLOUDFLARE|AWS_ without failing" 0 "advisory: R2_BACKUP_TOKEN"
if [[ "$OUT" == *"advisory: CLOUDFLARE_ZONE_ID"* && "$OUT" == *"advisory: AWS_ACCESS_KEY_ID"* ]]; then ok "L5b the advisory scan names every match"; else no "L5b advisory scan incomplete: ${OUT:0:300}"; fi

# L5c: the advisory scan also covers the names most dangerous to a leaked fresh-host token; advisory only (rc stays 0), and
# an unrelated name is not listed (the scan is a filter, not "print everything").
reset_mock; printf '%s\n' HCLOUD_TOKEN HETZNER_DNS_KEY CF_DNS_TOKEN GITHUB_PAT DOPPLER_SA_TOKEN >> "$MOCK/prd.names"
run_live
if [[ "$RC" -eq 0 && "$OUT" == *"escrow-split-contract:live-ok"* && "$OUT" == *"advisory: HCLOUD_TOKEN"* && "$OUT" == *"advisory: HETZNER_DNS_KEY"* \
   && "$OUT" == *"advisory: CF_DNS_TOKEN"* && "$OUT" == *"advisory: GITHUB_PAT"* && "$OUT" == *"advisory: DOPPLER_SA_TOKEN"* && "$OUT" != *"advisory: SOME_SECRET"* ]]; then
  ok "L5c the advisory scan also lists HCLOUD|HETZNER|CF_|GITHUB|DOPPLER names, never changes the rc, and skips unrelated names"
else
  no "L5c advisory widening wrong (rc=$RC): ${OUT:0:500}"
fi

# L3d: the presence check is by EXACT name. A web config holding only decorated copies of a required name (suffix,
# prefix, digit) must read as MISSING that name; deleting the name (L3) never proves this.
for req in WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY; do
  reset_mock; grep -vx "$req" "$MOCK/prd_workspaces_luks_web.names" > "$MOCK/w.tmp"; mv "$MOCK/w.tmp" "$MOCK/prd_workspaces_luks_web.names"
  printf '%s\n' "${req}_OLD" "OLD_${req}" "${req}2" >> "$MOCK/prd_workspaces_luks_web.names"
  run_live
  live_expect_line "L3d only decorated near-names of ${req} in the web config -> RED naming the exact missing name" 1 "escrow-split-contract:FAIL missing in prd_workspaces_luks_web: ${req}"
done

# CM: the one-line CAUSE map on failure (#9377 decision B1; it lives in the checker's output ONLY, the runbooks point at it).
# A missing Terraform-created name means the web-platform push-apply has not created it; a missing R2 pair name means the live mint
# has not been done. The cause lines are exact whole-line matches, and a name of the OTHER family must not select the wrong cause.
CAUSE_TF='escrow-split-contract:CAUSE a missing WORKSPACES_LUKS_KEY, WORKSPACES_HEADER_BUCKET or WORKSPACES_HEADER_R2_ENDPOINT means the web-platform push-apply (apply-web-platform-infra.yml) has not created it yet'
CAUSE_R2='escrow-split-contract:CAUSE a missing WORKSPACES_HEADER_R2_ACCESS_KEY_ID or WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY means the live R2 credential mint (#9377) has not been done yet'
cause_expect() { # <label> <missing name(s)...>: the cause lines the failure must carry (set CM_TF / CM_R2 to 1 or 0 first)
  local lbl="$1"; shift
  reset_mock; for m in "$@"; do grep -vx "$m" "$MOCK/prd_workspaces_luks_web.names" > "$MOCK/w.tmp"; mv "$MOCK/w.tmp" "$MOCK/prd_workspaces_luks_web.names"; done
  run_live
  local has_tf=0 has_r2=0
  grep -qxF -- "$CAUSE_TF" <<<"$OUT" && has_tf=1
  grep -qxF -- "$CAUSE_R2" <<<"$OUT" && has_r2=1
  if [[ "$RC" -eq 1 && "$has_tf" == "$CM_TF" && "$has_r2" == "$CM_R2" ]]; then ok "$lbl (push-apply cause=$has_tf, mint cause=$has_r2)"; else no "$lbl: expected rc=1 tf=$CM_TF r2=$CM_R2, got rc=$RC tf=$has_tf r2=$has_r2: ${OUT:0:400}"; fi
}
CM_TF=1; CM_R2=0
cause_expect "CM1 WORKSPACES_LUKS_KEY missing -> the push-apply cause only" WORKSPACES_LUKS_KEY
cause_expect "CM1b WORKSPACES_HEADER_BUCKET missing -> the push-apply cause only" WORKSPACES_HEADER_BUCKET
cause_expect "CM1c WORKSPACES_HEADER_R2_ENDPOINT missing -> the push-apply cause only" WORKSPACES_HEADER_R2_ENDPOINT
CM_TF=0; CM_R2=1
cause_expect "CM2 the R2 access key id missing -> the mint cause only" WORKSPACES_HEADER_R2_ACCESS_KEY_ID
cause_expect "CM2b the R2 secret missing -> the mint cause only" WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY
CM_TF=1; CM_R2=1
cause_expect "CM3 a name of each family missing -> both cause lines" WORKSPACES_LUKS_KEY WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY
reset_mock; run_live
if [[ "$RC" -eq 0 && "$OUT" != *"escrow-split-contract:CAUSE"* ]]; then ok "CM4 a passing contract prints no cause line"; else no "CM4 the passing run carried a cause line (rc=$RC): ${OUT:0:300}"; fi

# L4d: the prd-root leak check is by EXACT name too: a decorated near-name in prd is not the leaked credential.
reset_mock; printf '%s\n' WORKSPACES_LUKS_KEY_X X_WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY_OLD >> "$MOCK/prd.names"
run_live
live_expect "L4d decorated near-names of the leak-list names in the prd root do not read as a leak" 0 "escrow-split-contract:live-ok"

# A failed read is NEVER an absence: an unreadable prd root must not read as "the R2 pair is absent from prd"
reset_mock; run_live MOCK_UNREADABLE=prd
live_expect "L6 the prd root unreadable (token scoped elsewhere) -> exit 3, not a pass" 3 "unreadable"
reset_mock; run_live MOCK_UNREADABLE=prd_workspaces_luks_web
live_expect "L6b the web config unreadable -> exit 3" 3 "unreadable"
reset_mock; : > "$MOCK/prd.names"
run_live
live_expect "L7 an EMPTY prd listing is refused (a zero count from a failed read is not absence)" 3 "unreadable"
reset_mock; run_live MOCK_SHAPE=noheader
live_expect "L8 an unrecognised output shape (no NAME header) is refused, never read as zero names" 3 "unrecognised"
reset_mock; OUT="$(env PATH="$STUB_DIR:$PATH" MOCK_DIR="$MOCK" MOCK_LOG="$MOCK_LOG" DOPPLER_TOKEN=bogus bash "$SUT" --live 2>&1)"; RC=$?
live_expect "L9 an invalid token (the measured CLI failure) -> exit 3 naming the reason" 3 "Invalid Auth token"
reset_mock; OUT="$(env -u DOPPLER_TOKEN PATH="$STUB_DIR:$PATH" MOCK_DIR="$MOCK" MOCK_LOG="$MOCK_LOG" bash "$SUT" --live 2>&1)"; RC=$?
live_expect "L10 no DOPPLER_TOKEN in the environment -> usage rc=2 (the checker never falls back to an ambient login)" 2 "DOPPLER_TOKEN"
# L11: the token value is never echoed, on the success path and on a failed read.
reset_mock; run_live DOPPLER_TOKEN=dp.st.SECRETVALUE9f2c
if [[ "$OUT" != *SECRETVALUE9f2c* ]]; then ok "L11 the token value is never echoed on success"; else no "L11 the token leaked into the success output"; fi
reset_mock; run_live DOPPLER_TOKEN=dp.st.SECRETVALUE9f2c MOCK_UNREADABLE=prd
if [[ "$OUT" != *SECRETVALUE9f2c* && "$RC" -eq 3 ]]; then ok "L11b the token value is never echoed on a failed read"; else no "L11b the token leaked into the failure output (rc=$RC)"; fi

# L12: the stderr echo of a failed read is redacted: a Doppler token shape in the CLI's error body (a future CLI that
# echoes the credential it was handed) must never reach the CI log, and the reason text around it must survive.
reset_mock; run_live MOCK_UNREADABLE=prd MOCK_LEAKTOK=dp.st.PLANTEDleak7731
if [[ "$RC" -eq 3 && "$OUT" != *PLANTEDleak7731* && "$OUT" == *"dp.REDACTED"* && "$OUT" == *"does not have access to requested config"* ]]; then ok "L12 a dp.st.* token in the Doppler error body is redacted from the echo (reason kept)"; else no "L12 the planted token reached the output or the reason was lost (rc=$RC): ${OUT:0:400}"; fi
reset_mock; run_live MOCK_UNREADABLE=prd_workspaces_luks_web MOCK_LEAKTOK=dp.ct.Planted_Leak-7731.TAIL9
if [[ "$RC" -eq 3 && "$OUT" != *Planted_Leak* && "$OUT" != *TAIL9* && "$OUT" == *"dp.REDACTED"* ]]; then ok "L12b a dp.ct.* token with punctuation in its body is redacted whole"; else no "L12b the punctuated token reached the output (rc=$RC): ${OUT:0:400}"; fi

# --- Anti-vacuity: an exact assertion count ------------------------------------------------------------
EXPECTED_PASSES=79
if [[ "$passes" -ne "$EXPECTED_PASSES" ]]; then no "count: ${passes} assertions passed, expected exactly ${EXPECTED_PASSES} — a block of rows was deleted or added without moving the number"; fi

echo ""
echo "=== check-web-host-escrow-config.test.sh: ${passes} passed, ${fails} failed ==="
[[ "$fails" -eq 0 ]]
