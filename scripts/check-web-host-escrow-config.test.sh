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

SCR="$(mktemp -d "$TMPDIR/escrow-census.XXXXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
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

# The provisioner is owned by the 3.4 hardening work; the closed-set acceptance of the web config name lands
# there. The census REQUIRES the web name to appear in provisioner code (a provisioner that pins only the
# un-suffixed name leaves a web-class host dark at birth: cloud-init writes the _web name). Fixtures that are not
# about the provisioner therefore start from a tree whose provisioner already carries the closed set.
with_closed_set_provisioner() { # <root>: ensure the provisioner names the web config (idempotent)
  local f="$1/workspaces-luks-provision.sh"
  grep -qE 'prd_workspaces_luks_web' "$f" && return 0
  sed -i -E 's#^\[ "\$CFG" = prd_workspaces_luks \] \|\| fatal config 10 .*$#case "$CFG" in prd_workspaces_luks|prd_workspaces_luks_web) ;; *) fatal config 10 "doppler config is not a dedicated escrow config" ;; esac#' "$f"
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

# --- Positive control: the real tree (with the closed-set provisioner) is GREEN ------------------------
BASE="$(mk_tree)"; with_closed_set_provisioner "$BASE"
expect_green "S0 positive control: the repo tree satisfies the census (closed-set provisioner applied to the copy)" "$BASE"

# The REAL tree, un-copied, is the contract the PR ships. It depends on the provisioner's closed-set change; this row
# is therefore the integration check that the 3.4 provisioner change and this PR agree.
run_static "$REAL_INFRA"
if [[ "$RC" -eq 0 && "$OUT" == *"escrow-split-contract:ok"* ]]; then ok "S0b the real infra tree prints escrow-split-contract:ok"; else no "S0b the REAL tree fails the census (the provisioner closed-set change may not have landed yet): ${OUT:0:400}"; fi

# --- Guard 3 mutation matrix ------------------------------------------------------------------------
# row 1: cloud-init's printf reverted to web-1's config
T="$(mk_tree)"; with_closed_set_provisioner "$T"
mutate "$T" cloud-init.yml 's#(WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks)_web#\1#' && expect_red "G3-1 cloud-init printf reverted to prd_workspaces_luks" "$T" "cloud-init.yml" || no "G3-1 mutation did not land"

# row 2: a NEW web-class script hardcodes the web-1 config (an unclassified file with a bare occurrence)
T="$(mk_tree)"; with_closed_set_provisioner "$T"
printf '#!/usr/bin/env bash\ndoppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks\n' > "$T/web-new-reader.sh"
expect_red "G3-2 a new script hardcodes --config prd_workspaces_luks" "$T" "web-new-reader.sh"
# row 2b: the existing provisioner gains a literal read
T="$(mk_tree)"; with_closed_set_provisioner "$T"
printf 'doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks\n' >> "$T/workspaces-luks-provision.sh"
expect_red "G3-2b the provisioner gains a literal --config prd_workspaces_luks read" "$T" "workspaces-luks-provision.sh"
# row 2c: the reopen script hardcodes the config name instead of reading the boot env file
T="$(mk_tree)"; with_closed_set_provisioner "$T"
mutate "$T" workspaces-luks-reopen.sh 's#--config "\$WORKSPACES_DOPPLER_CONFIG"#--config prd_workspaces_luks#' && expect_red "G3-2c reopen hardcodes the config" "$T" "workspaces-luks-reopen.sh" || no "G3-2c mutation did not land"

# row 3: the fresh-boot token re-pointed back to web-1's config; and server.tf re-pointed at the pre-split token
T="$(mk_tree)"; with_closed_set_provisioner "$T"
mutate "$T" workspaces-luks-fresh-boot.tf '/"workspaces_luks_fresh_boot_web"/,/^}/ s/config([[:space:]]*)=([[:space:]]*)doppler_config\.workspaces_luks_web\.name/config\1=\2"prd_workspaces_luks"/' \
  && expect_red "G3-3 the web fresh-boot token re-pointed to prd_workspaces_luks" "$T" "workspaces-luks-fresh-boot.tf" || no "G3-3 mutation did not land"
T="$(mk_tree)"; with_closed_set_provisioner "$T"
mutate "$T" server.tf 's/doppler_service_token\.workspaces_luks_fresh_boot_web\.key/doppler_service_token.workspaces_luks_fresh_boot.key/' \
  && expect_red "G3-3b server.tf hands user_data the PRE-SPLIT token (still reads web-1's pair)" "$T" "server.tf" || no "G3-3b mutation did not land"

# row 4: a second literal read appended to luks-monitor.sh after the parameterized key read
T="$(mk_tree)"; with_closed_set_provisioner "$T"
printf 'key2="$(doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks 2>/dev/null || true)"\n' >> "$T/luks-monitor.sh"
expect_red "G3-4 a second literal --config prd_workspaces_luks key read after the parameterized one" "$T" "luks-monitor.sh"
T="$(mk_tree)"; with_closed_set_provisioner "$T"
mutate "$T" luks-monitor.sh 's#(WORKSPACES_LUKS_KEY --plain --config )"\$[A-Za-z_]+"#\1prd_workspaces_luks#' \
  && expect_red "G3-4b the monitor's key read reverted to the literal" "$T" "luks-monitor.sh" || no "G3-4b mutation did not land"
T="$(mk_tree)"; with_closed_set_provisioner "$T"
mutate "$T" luks-monitor.sh 's#(WORKSPACES_LUKS_HEARTBEAT_URL --plain --config )prd_workspaces_luks#\1prd_workspaces_luks_web#' \
  && expect_red "G3-4c the heartbeat read moved off prd_workspaces_luks (web-1 primary profile would lose its URL)" "$T" "luks-monitor.sh" || no "G3-4c mutation did not land"

# row 5: the census enumerates zero occurrences (path glob broken / wrong root) must be RED, never "nothing to check"
E="$SCR/empty-root"; mkdir -p "$E"
expect_red "G3-5 the census over an empty root" "$E" "census-empty"
T="$(mk_tree)"; with_closed_set_provisioner "$T"
for f in luks-monitor-token-refresh.sh workspaces-cutover.sh uptime-alerts.tf workspaces-luks.tf workspaces-luks-header.tf; do
  sed -i -E 's/prd_workspaces_luks([^_A-Za-z0-9]|$)/prd_gone\1/g' "$T/$f"
done
expect_red "G3-5b every web-1 path stops naming prd_workspaces_luks (stale exclusion list, or a broken scan, must not read as clean)" "$T" "web-1"

# H1: the harness, run against a tree with one injected violation, REPORTS it by file name (not just a bare rc)
T="$(mk_tree)"; with_closed_set_provisioner "$T"
printf 'WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks\n' > "$T/soleur-host-bootstrap-injected.sh"
run_static "$T"
if [[ "$RC" -ne 0 && "$OUT" == *"soleur-host-bootstrap-injected.sh"* ]]; then ok "H1 an injected violation is reported by file name (rc=$RC)"; else no "H1 the injected violation was not reported by name: rc=$RC ${OUT:0:300}"; fi

# H2 (must-PASS): a COMMENT naming the web-1 config in a web-class file does not trip the census
T="$(mk_tree)"; with_closed_set_provisioner "$T"
printf '  # web-1 keeps prd_workspaces_luks; this comment names it and must not trip the census\n' >> "$T/cloud-init.yml"
printf '# web-1 keeps `--config prd_workspaces_luks` for its own paths\n' >> "$T/luks-monitor.sh"
printf '# a comment: WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks\n' >> "$T/workspaces-luks-reopen.sh"
expect_green "H2 comments naming prd_workspaces_luks in web-class files" "$T"

# web-1 paths KEEP the un-suffixed name (check 17d's counterpart at census level): the SSH installer must not move
T="$(mk_tree)"; with_closed_set_provisioner "$T"
mutate "$T" workspaces-luks.tf "s#'prd_workspaces_luks'#'prd_workspaces_luks_web'#" \
  && expect_red "W1-1 web-1's SSH installer moved to the web config" "$T" "workspaces-luks.tf" || no "W1-1 mutation did not land"
T="$(mk_tree)"; with_closed_set_provisioner "$T"
mutate "$T" luks-monitor-token-refresh.sh 's#--config prd_workspaces_luks#--config prd_workspaces_luks_web#' \
  && expect_red "W1-2 the web-1-only token refresh moved to the web config" "$T" "luks-monitor-token-refresh.sh" || no "W1-2 mutation did not land"

# Provisioner closed set: a provisioner that names only the un-suffixed config leaves a web-class host dark at birth
T="$(mk_tree)"
sed -i -E 's/prd_workspaces_luks_web/prd_workspaces_luks_wXb/g' "$T/workspaces-luks-provision.sh"
printf '[ "$CFG" = prd_workspaces_luks ] || fatal config 10 "x"\n' >> "$T/workspaces-luks-provision.sh"
expect_red "P-1 the provisioner does not accept the web config name" "$T" "workspaces-luks-provision.sh"

# The reopen-failure unit's documented absent-file default is the ONE allowed bare occurrence there
T="$(mk_tree)"; with_closed_set_provisioner "$T"
mutate "$T" workspaces-luks-reopen-failure.service 's#\$\{WORKSPACES_DOPPLER_CONFIG:-prd_workspaces_luks\}#prd_workspaces_luks#' \
  && expect_red "RF-1 the failure unit hardcodes the config instead of the env-file default" "$T" "workspaces-luks-reopen-failure.service" || no "RF-1 mutation did not land"

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
  printf 'Unable to fetch secret names\nDoppler Error: This token does not have access to requested config\n' >&2; exit 1
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
live_expect() { # <label> <rc> <needle>
  if [[ "$RC" -eq "$2" && "$OUT" == *"$3"* ]]; then ok "$1 (rc=$RC)"; else no "$1: expected rc=$2 containing '$3', got rc=$RC: ${OUT:0:400}"; fi
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

# --- Anti-vacuity: an exact assertion count ------------------------------------------------------------
EXPECTED_PASSES=42
if [[ "$passes" -ne "$EXPECTED_PASSES" ]]; then no "count: ${passes} assertions passed, expected exactly ${EXPECTED_PASSES} — a block of rows was deleted or added without moving the number"; fi

echo ""
echo "=== check-web-host-escrow-config.test.sh: ${passes} passed, ${fails} failed ==="
[[ "$fails" -eq 0 ]]
