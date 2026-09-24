#!/usr/bin/env bash
# Tests the Inngest bootstrap runcmd block added to cloud-init.yml in #4118.
#
# Asserts the structural invariants the runcmd block must satisfy:
#   - The pinned OCI image tag is present and well-formed (vX.Y.Z; the
#     bootstrap-script SHAPE version, NOT the inngest-cli version which is
#     sourced from Config.Env). The EXACT value is checked dynamically by the
#     AC6 drift-guard below (pin must equal the latest published vinngest-v*
#     git tag), so this file no longer hardcodes the current version (#4675).
#   - The block sources INNGEST_CLI_VERSION + INNGEST_CLI_SHA256 via `docker
#     inspect ... Config.Env` (rather than hardcoding them in cloud-init.yml).
#   - The block uses `trap cleanup EXIT` so a partial failure does not leave an
#     orphan EXTRACT_DIR or docker container.
#   - The block is positioned BEFORE the final `docker run -d --name
#     soleur-web-platform` so Inngest is listening on :8288 when the
#     web-platform container first resolves INNGEST_BASE_URL=...:8288.
#   - The embedded shell snippet is `bash -n` AND `dash -n` clean (POSIX-
#     portable; cloud-init runs `- |` blocks under /bin/sh = dash on Ubuntu).
#
# Static grep + AWK only — no docker required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="$SCRIPT_DIR/cloud-init.yml"

# NO `producer | grep -q` ANYWHERE IN THIS FILE. Under `set -o pipefail` (above) `grep -q`
# closes the pipe on its FIRST match, the producer takes SIGPIPE (141), and pipefail fails the
# pipeline EVEN THOUGH GREP MATCHED — a false NEGATIVE that fires only when the match is early
# enough for the producer to still be writing, so it presents as an unreproducible flake. Four
# sites carried it; one surfaced as the mutation battery's sandbox baseline going RED while the
# SAME assertion passed in the worktree seconds earlier. Use `grep -cE … -gt 0` (reads all
# input) or a herestring — never `| grep -q`.
PASS=0
FAIL=0
TOTAL=0

assert() {
  local description="$1"
  local condition="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$condition"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        condition: $condition"
  fi
}

# INSTRUMENT SELF-TEST (#7695). `assert` is the single point through which every claim in this
# file is dispatched. A vacuity audit neutered it -- `if eval "$condition"` -> `if true` -- and all
# 163 assertions passed with a summary byte-identical to green, WITH real defects present. No
# assertion here can catch that, because every assertion is downstream of it; and all five section
# floors (Guard 1, Row7, GuardA, GuardB, GuardD) are themselves `assert` calls, so one edit
# disarms the helper and every backstop at once. The bucket-swap variant
# (`fail() { PASS=$((PASS+1)); }`) is worse still: FAIL rows print on screen while the summary
# says 0 failed.
#
# So prove the dispatcher discriminates in BOTH directions, then reset. Reported with printf +
# exit (ADR-193), never through the helper it backstops. Both sibling suites already carry this.
assert "instrument self-test: a true condition must pass" "true" >/dev/null
assert "instrument self-test: a false condition must fail" "false" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 || "$TOTAL" -ne 2 ]]; then
  printf 'FATAL: assertion dispatcher is broken (PASS=%s FAIL=%s TOTAL=%s, expected 1/1/2).\n' \
    "$PASS" "$FAIL" "$TOTAL" >&2
  exit 1
fi
PASS=0; FAIL=0; TOTAL=0
# COND_ASSERTIONS CONTRACT. Four blocks in this suite are gated on a tool being installed
# (`dash`, `visudo`, `terraform`, and `cloud-init` nested inside terraform), so they contribute
# assertions on some hosts and none on others. Every such block is bracketed by
#   _COND_BEFORE=$TOTAL   ...   COND_ASSERTIONS=$(( COND_ASSERTIONS + TOTAL - _COND_BEFORE ))
# and the end-of-run floor subtracts the accumulator, so it measures only what EVERY environment
# runs. Add a new tool-gated block => bracket it the same way, or the floor becomes host-dependent
# again. Do NOT replace this with a per-tool constant: that is the same defect with more places
# to forget.
COND_ASSERTIONS=0

echo "=== cloud-init Inngest bootstrap (#4118 Tier 1) tests ==="
echo ""

# --- File existence ---
echo "--- File existence ---"
assert "cloud-init.yml exists" "[[ -f '$CLOUD_INIT' ]]"

# --- AC1: pinned OCI image tag ---
echo ""
echo "--- AC1: pinned OCI image tag ---"
# Shape-match only (vX.Y.Z) — the exact value is owned by the AC6 drift-guard.
# #6122: the pin lives in the IREF assignment. #8036 1d: IREF is the pin CARRIER only (the bump
# bot and AC6 read it) and is never pulled — the one pull is the zot ref "$ZIREF", and on a hit
# IREF is re-pointed at it, so the create/inspect consumers still reference "$IREF". A code line
# pulling "$IREF" would be the retired GHCR leg (comment lines are stripped before that check).
assert "IREF pin for soleur-inngest-bootstrap:vX.Y.Z exists" \
  "grep -qE '^[[:space:]]+IREF=ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' '$CLOUD_INIT'"
assert "inngest image pulled from zot via \"\$ZIREF\", and no code line pulls the \$IREF pin carrier" \
  "grep -qF 'docker pull \"\$ZIREF\"' '$CLOUD_INIT' && (( \$(grep -vE '^[[:space:]]*#' '$CLOUD_INIT' | grep -cF 'docker pull \"\$IREF\"' || true) == 0 ))"

# --- AC1: Config.Env sourcing ---
echo ""
echo "--- AC1: Config.Env sourcing ---"
assert "docker inspect ... Config.Env line exists" \
  "grep -qE 'docker inspect.*Config\.Env' '$CLOUD_INIT'"
assert "INNGEST_CLI_VERSION extracted from image env" \
  "grep -qE 'INNGEST_CLI_VERSION=\\\$\\(printf.*grep.*INNGEST_CLI_VERSION' '$CLOUD_INIT'"
assert "INNGEST_CLI_SHA256 extracted from image env" \
  "grep -qE 'INNGEST_CLI_SHA256=\\\$\\(printf.*grep.*INNGEST_CLI_SHA256' '$CLOUD_INIT'"

# --- AC1: trap cleanup ---
echo ""
echo "--- AC1: trap still calls cleanup (composite form OK, #6090) ---"
# #6090 turned this into a COMPOSITE trap ('rc=$?; cleanup; … || soleur-boot-emit …' EXIT)
# so a downstream boot failure also emits a NAMED Sentry fatal. The invariant preserved
# here is that the EXIT trap STILL runs cleanup (no orphaned extract container) — assert
# the composite-or-plain shape, not the exact 'trap cleanup EXIT' literal.
assert "Inngest block EXIT trap still calls cleanup" \
  "[ \"\$(awk '/Bootstrap Inngest server on first boot/,/^[^[:space:]]/' '$CLOUD_INIT' | grep -cE 'trap .*cleanup.* EXIT' || true)\" -gt 0 ]"

# --- AC2: drift comment ---
echo ""
echo "--- AC2: drift sentinel comment ---"
# The pin's drift-sentinel comment must clarify that the tag is the
# bootstrap-image SHAPE version (NOT the inngest-cli version) and MUST be
# bumped on each bootstrap-script change. (#4667 corrected the prior comment
# which misleadingly claimed the pin "tracks ...inngest_cli_version".)
assert "drift comment clarifies pin is bootstrap-image version, not inngest-cli version" \
  "grep -qE 'NOT the inngest-cli version' '$CLOUD_INIT' && grep -qiE 'MUST be bumped' '$CLOUD_INIT'"

# --- AC4: positional ordering ---
echo ""
echo "--- AC4: positioned BEFORE soleur-web-platform docker run ---"
BOOTSTRAP_LINE=$(grep -nE '^[[:space:]]+IREF=ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$CLOUD_INIT" | head -1 | cut -d: -f1)
WEBPLATFORM_LINE=$(grep -nE '^[[:space:]]+--name soleur-web-platform' "$CLOUD_INIT" | head -1 | cut -d: -f1)
assert "bootstrap line found in cloud-init.yml"      "[[ -n '$BOOTSTRAP_LINE' ]]"
assert "soleur-web-platform run line found"          "[[ -n '$WEBPLATFORM_LINE' ]]"
assert "bootstrap block precedes web-platform start" "(( BOOTSTRAP_LINE < WEBPLATFORM_LINE ))"

# --- AC4: extracted shell snippet is POSIX clean ---
echo ""
echo "--- AC4: extracted shell snippet POSIX-portable ---"
SNIPPET_FILE=$(mktemp /tmp/inngest-runcmd-XXXXXX.sh)
trap 'rm -f "$SNIPPET_FILE"' EXIT

# Extract the runcmd block following the Inngest bootstrap comment.
# The block ends at the next YAML sibling key (line starting with `  - |`
# at the same indent or any drop in indent below the 4-space body indent).
# Blank-line termination is too fragile — a future maintainer adding a blank
# line inside the block would truncate the snippet and bash -n would
# trivially pass on the prefix.
awk '
  /Bootstrap Inngest server on first boot/ { found = 1; next }
  found && /^[[:space:]]+- \|/ && !in_block { in_block = 1; next }
  in_block && /^[[:space:]]+- \|/ { exit }
  in_block && /^[^[:space:]]/ { exit }
  in_block { sub(/^    /, ""); print }
' "$CLOUD_INIT" > "$SNIPPET_FILE"

# Prepend shebang so the syntax-check tools have a clean target.
{ echo "#!/bin/sh"; cat "$SNIPPET_FILE"; } > "$SNIPPET_FILE.tmp" && mv "$SNIPPET_FILE.tmp" "$SNIPPET_FILE"

assert "extracted snippet is non-empty" "[[ -s '$SNIPPET_FILE' ]]"
assert "snippet passes bash -n"         "bash -n '$SNIPPET_FILE'"
_COND_BEFORE=$TOTAL
if command -v dash >/dev/null 2>&1; then
  assert "snippet passes dash -n (POSIX portability)" "dash -n '$SNIPPET_FILE'"
else
  echo "  SKIP: dash not installed (POSIX portability check skipped — CI will exercise it)"
fi
COND_ASSERTIONS=$(( COND_ASSERTIONS + TOTAL - _COND_BEFORE ))

# --- AC3: YAML round-trip (raw source, templatefile directives stripped) ---
# #6178: cloud-init.yml now carries col-0 `%{ if web_colocate_inngest ~}` / `%{ endif ~}`
# templatefile directives. YAML rejects `%` at column 0 (directive indicator → ScannerError),
# so strip those directive lines before parsing the NON-rendered source. Rendered-state YAML
# validity is asserted once, in the AC7 terraform-render leg — the single home for that property.
echo ""
echo "--- AC3: cloud-init.yml YAML round-trip (directives stripped) ---"
assert "cloud-init.yml (templatefile directives stripped) parses as valid YAML" \
  "grep -v '^%{' '$CLOUD_INIT' | python3 -c \"import sys,yaml; yaml.safe_load(sys.stdin)\""

# --- AC5: sudoers byte-parity between source file and cloud-init inline (#4144) ---
# The same Cmnd_Alias/Defaults/deploy lines live in three places:
#   (a) apps/web-platform/infra/deploy-inngest-bootstrap.sudoers
#   (b) apps/web-platform/infra/cloud-init.yml write_files inline (this file)
#   (c) apps/web-platform/infra/ci-deploy.sh exec path
# (a) and (b) MUST be byte-identical or fresh hosts drift from existing
# hosts on the next /etc/sudoers.d/ reload. (c) is checked by grep.
echo ""
echo "--- AC5: sudoers parity (deploy-inngest-bootstrap) ---"
SUDOERS_SRC="$SCRIPT_DIR/deploy-inngest-bootstrap.sudoers"
SUDOERS_CONTENT_ONLY=$(grep -vE '^\s*#|^\s*$' "$SUDOERS_SRC")
# Extract the inline sudoers body (#4665 fix). The prior version's two real
# defects: (1) it compared the raw inline block (WITH comments + blanks) against
# the source's content-only form (`grep -vE '^\s*#|^\s*$'` above) → never matched
# even though the alias content is byte-identical; (2) the non-empty assert
# value-embedded the block (`[[ -n '$VAR' ]]`), which the eval mishandles on
# special chars. Fix: pipe the extracted block through the SAME content-only
# filter, and assert by-name (`[[ -n "$VAR" ]]`) below. The added
# `^[[:space:]]*-[[:space:]]` exit (next write_files `- path:` item) is
# defense-in-depth — the existing `[a-z]+:` exit already stops at the entry's
# trailing `owner:`/`permissions:` keys.
CLOUD_INIT_SUDOERS=$(awk '
  /path: \/etc\/sudoers\.d\/deploy-inngest-bootstrap/ { found = 1; next }
  found && /^[[:space:]]+content:[[:space:]]*\|/      { in_body = 1; next }
  in_body && /^[[:space:]]*-[[:space:]]/              { exit }
  in_body && /^[[:space:]]+[a-z]+:/                   { exit }
  in_body { sub(/^      /, ""); print }
' "$CLOUD_INIT" | grep -vE '^\s*#|^\s*$')
assert "deploy-inngest-bootstrap.sudoers exists"         "[[ -s '$SUDOERS_SRC' ]]"
assert "cloud-init inline block is non-empty"            "[[ -n \"\$CLOUD_INIT_SUDOERS\" ]]"
assert "sudoers source and cloud-init inline match"      "[[ \"\$SUDOERS_CONTENT_ONLY\" == \"\$CLOUD_INIT_SUDOERS\" ]]"
assert "ci-deploy.sh invokes the sudoers-pinned path"    "grep -qE '/usr/bin/bash /tmp/inngest-extract/inngest-bootstrap.sh' '$SCRIPT_DIR/ci-deploy.sh'"
_COND_BEFORE=$TOTAL
if command -v visudo >/dev/null 2>&1; then
  assert "sudoers source parses via visudo -cf"          "visudo -cf '$SUDOERS_SRC' >/dev/null"
else
  echo "  SKIP: visudo not installed locally — CI will exercise the validation step"
fi
COND_ASSERTIONS=$(( COND_ASSERTIONS + TOTAL - _COND_BEFORE ))

# --- #6178 no-SSH web-host quiesce/enable grants (INNGEST_QUIESCE + INNGEST_ENABLE) ---
# The dedicated-host cutover 2.2 gap: operators have no SSH, so `op=quiesce-web`
# stop+disables the co-located web scheduler and `op=rollback` re-enables it, both via
# ci-deploy.sh handlers over the deploy webhook (mirrors INNGEST_RESTART #4538). Assert
# the two NEW verbs (disable via INNGEST_QUIESCE; enable via INNGEST_ENABLE) pin the EXACT
# fully-resolved /usr/bin/systemctl argv (no wildcards — sudo-rs safe) + NOPASSWD to deploy.
# `stop` reuses the pre-existing INNGEST_STOP (#5450) overlap; `start` (enable handler)
# reuses the pre-existing INNGEST_START (#5450) grant — no new start grant is added.
echo ""
echo "--- #6178 INNGEST_QUIESCE / INNGEST_ENABLE pinned grants ---"
assert "INNGEST_QUIESCE alias defined"                    "grep -qE '^Cmnd_Alias INNGEST_QUIESCE = ' '$SUDOERS_SRC'"
assert "INNGEST_QUIESCE pins exact stop argv (wildcard-free)"    "grep -qF '/usr/bin/systemctl stop inngest-server.service' '$SUDOERS_SRC'"
assert "INNGEST_QUIESCE pins exact disable argv (wildcard-free)" "grep -qF '/usr/bin/systemctl disable inngest-server.service' '$SUDOERS_SRC'"
assert "INNGEST_QUIESCE granted NOPASSWD to deploy"       "grep -qE '^deploy ALL=\\(root\\) NOPASSWD: INNGEST_QUIESCE\$' '$SUDOERS_SRC'"
assert "INNGEST_ENABLE alias pins exact enable argv"      "grep -qE '^Cmnd_Alias INNGEST_ENABLE = /usr/bin/systemctl enable inngest-server.service\$' '$SUDOERS_SRC'"
assert "INNGEST_ENABLE granted NOPASSWD to deploy"        "grep -qE '^deploy ALL=\\(root\\) NOPASSWD: INNGEST_ENABLE\$' '$SUDOERS_SRC'"
# sudo-rs rejects wildcards — the new alias lines must contain no literal '*'.
QE_LINES=$(grep -E '^Cmnd_Alias INNGEST_(QUIESCE|ENABLE) = ' "$SUDOERS_SRC" || true)
assert "new quiesce/enable alias argv are wildcard-free" "[[ -n \"\$QE_LINES\" ]] && ! grep -qF '*' <<<\"\$QE_LINES\""

# --- AC6: pin matches latest published vinngest-v* git tag (#4675 drift-guard) ---
# Durable mechanical replacement for the manual "bump the cloud-init pin on each
# bootstrap-image release" step — forgotten 10 consecutive times (v1.0.1…v1.1.10)
# before #4669. The pin MUST equal the semver-max published `vinngest-v*` git
# tag: that tag is the authoritative "a new soleur-inngest-bootstrap image was
# published" signal (build-inngest-bootstrap-image.yml is
# `on: push: tags: ['vinngest-v*.*.*']`). sort -V (semver), NOT lexicographic —
# plain `sort` ranks v1.1.9 above v1.1.10, the exact bug class that hid the drift.
echo ""
echo "--- AC6: pin drift-guard vs latest published vinngest-v* tag ---"
# `|| true`: under `set -euo pipefail` a zero-match grep exits 1 and pipefail
# would abort the whole script here (before AC6b + the results summary) if the
# image ref is ever renamed. Let the empty PIN fall through to a clean FAIL.
PIN=$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$CLOUD_INIT" | head -1 | sed 's/.*://' || true)
# git -C "$SCRIPT_DIR" (NOT `git rev-parse --show-toplevel`, which resolves to
# the bare-repo parent in a worktree). Any failure (no git, no tags, not a repo)
# collapses to an empty result → visible SKIP, never a false-green.
LATEST_TAG=$(git -C "$SCRIPT_DIR" tag --list 'vinngest-v*' 2>/dev/null \
  | sed 's/^vinngest-//' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V | tail -1 || true)
if [[ -z "$LATEST_TAG" ]]; then
  if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
    # In CI the deploy-script-tests checkout fetches tags (fetch-depth: 0 +
    # fetch-tags: true). An empty tag set in CI means that wiring regressed —
    # FAIL loudly rather than SKIP, so the guard can never silently disarm.
    assert "vinngest-v* tags reachable in CI (guard must not silently disarm)" "false"
    echo "        No vinngest-v* tags in a CI checkout — verify fetch-depth: 0 +"
    echo "        fetch-tags: true on deploy-script-tests in infra-validation.yml."
  else
    echo "  SKIP: no vinngest-v* git tags reachable (shallow clone / tagless checkout);"
    echo "        drift comparison skipped (CI fetches tags via fetch-tags: true)."
  fi
else
  assert "cloud-init pin ($PIN) matches latest published vinngest-v* tag ($LATEST_TAG)" \
    "[[ '$PIN' == '$LATEST_TAG' ]]"
  if [[ "$PIN" != "$LATEST_TAG" ]]; then
    echo "        DRIFT: cloud-init.yml pins $PIN but the latest published tag is $LATEST_TAG."
    echo "        Fix: bump every 'soleur-inngest-bootstrap:<tag>' ref in"
    echo "        apps/web-platform/infra/cloud-init.yml to $LATEST_TAG."
  fi

  # #6536: the DEDICATED host's pin was guarded by NOTHING. This guard read only
  # cloud-init.yml (the web host), so cloud-init-inngest.yml silently sat on v1.1.19
  # while the web host moved to v1.1.20 — and the two hosts extract inngest-bootstrap.sh
  # + vector.toml from whatever image THEIR OWN file pins.
  #
  # That gap is not cosmetic; it is how a fix reaches main and never reaches the host.
  # The dedicated host is delivered by `apply_target=inngest-host-replace`, whose
  # `terraform plan -replace=` force-replaces REGARDLESS of any user_data diff — so the
  # rebuild boots the pinned image whether or not the pin moved. #6539 measured v1.1.19
  # and v1.1.20 to contain NONE of the #6536 fix: dispatching the replace against a
  # stale pin would have rebuilt the dark host pre-fix, left the bug live, and spent the
  # zero-downtime window (free only while the host is dark, a cron outage after #6178
  # arms the flip). The guard above would have stayed green throughout — it was watching
  # the other file.
  #
  # Same authoritative signal (semver-max published tag), same failure text shape.
  # `|| true` mirrors the PIN extraction above: a rename must FAIL cleanly, not abort
  # the run under pipefail before the results summary.
  DED_CLOUD_INIT="$SCRIPT_DIR/cloud-init-inngest.yml"
  DED_PIN=$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$DED_CLOUD_INIT" | head -1 | sed 's/.*://' || true)
  assert "dedicated-host cloud-init pin ($DED_PIN) matches latest published vinngest-v* tag ($LATEST_TAG)" \
    "[[ '$DED_PIN' == '$LATEST_TAG' ]]"
  if [[ "$DED_PIN" != "$LATEST_TAG" ]]; then
    echo "        DRIFT: cloud-init-inngest.yml pins $DED_PIN but the latest published tag is $LATEST_TAG."
    echo "        Fix: bump every 'soleur-inngest-bootstrap:<tag>' ref in"
    echo "        apps/web-platform/infra/cloud-init-inngest.yml to $LATEST_TAG."
    echo "        This is the DEDICATED inngest host. Its replace is dispatch-only and"
    echo "        force-replaces regardless of user_data, so a stale pin here means the"
    echo "        rebuild boots a pre-fix image and the dispatch changes nothing (#6536)."
  fi
fi

# --- AC6b: all pin refs present AND share one tag (catches a partial bump) ---
# #6122: the pin literal now appears in exactly 2 places — the IREF assignment (GHCR
# ref) and the ZIREF assignment (its zot equivalent, `$ZURL/jikig-ai/…:vX.Y.Z`); the
# create/inspect consumers follow "$IREF". Assert BOTH count==2 AND distinct==1: the
# count catches a partial bump (IREF bumped but ZIREF left stale → the fresh-boot zot
# pull would 404 a nonexistent tag), and distinct==1 catches a divergent value.
echo ""
echo "--- AC6b: pin-consistency (all soleur-inngest-bootstrap refs present + agree) ---"
PIN_REF_COUNT=$(grep -coE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$CLOUD_INIT" || true)
DISTINCT_PINS=$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$CLOUD_INIT" | sort -u | wc -l)
assert "both soleur-inngest-bootstrap pin refs (IREF + ZIREF) present and share one tag (found $PIN_REF_COUNT refs, $DISTINCT_PINS distinct)" \
  "(( PIN_REF_COUNT == 2 && DISTINCT_PINS == 1 ))"

# --- AC7: web_colocate_inngest gate (#6178) — structural smoke ---
# The "Bootstrap Inngest server on first boot" runcmd item is wrapped in a col-0
# templatefile `%{ if web_colocate_inngest ~}` / `%{ endif ~}` directive pair so a
# freshly-created web host with the toggle false does NOT co-locate inngest.
echo ""
echo "--- AC7: web_colocate_inngest gate — structural ---"
VARS_TF="$SCRIPT_DIR/variables.tf"
assert "exactly one col-0 '%{ if web_colocate_inngest ~}' directive" \
  "(( \$(grep -cE '^%\{ if web_colocate_inngest ~\}$' '$CLOUD_INIT') == 1 ))"
# #6425 added a SECOND col-0 pair (web_tunnel_connector), so a global `endif == 1` count is
# no longer the invariant — BALANCE is. `%{ endif ~}` is anonymous, so per-block closure is
# pinned by locating this block's own endif relative to its if-line (below), not by counting.
assert "col-0 '%{ if ~}' / '%{ endif ~}' directives balance" \
  "(( \$(grep -cE '^%\{ if .+ ~\}$' '$CLOUD_INIT') == \$(grep -cE '^%\{ endif ~\}$' '$CLOUD_INIT') ))"
# #6425's connector gate — asserted here (not in the render block) so it still gates where
# terraform is absent. Column 0 is load-bearing: an indented directive leaves its leading
# spaces behind after the `~` trim and corrupts the runcmd: list.
assert "exactly one col-0 '%{ if web_tunnel_connector ~}' directive (#6425)" \
  "(( \$(grep -cE '^%\{ if web_tunnel_connector ~\}$' '$CLOUD_INIT') == 1 ))"
IF_LINE=$(grep -nE '^%\{ if web_colocate_inngest ~\}$' "$CLOUD_INIT" | head -1 | cut -d: -f1)
COMMENT_LINE=$(grep -nE 'Bootstrap Inngest server on first boot' "$CLOUD_INIT" | head -1 | cut -d: -f1)
# The first endif AT OR AFTER this block's if — `head -1` of the file would since #6425 return
# the web_tunnel_connector pair's endif (which sits earlier) and false-FAIL the ordering assert.
ENDIF_LINE=$(awk -v s="$IF_LINE" 'NR > s && /^%\{ endif ~\}$/ { print NR; exit }' "$CLOUD_INIT")
TRAP_DISARM_LINE=$(grep -nE 'disarm, else the composite trap' "$CLOUD_INIT" | head -1 | cut -d: -f1)
assert "if-directive precedes the bootstrap comment"        "(( IF_LINE < COMMENT_LINE ))"
assert "endif-directive follows the block's trap disarm"    "(( ENDIF_LINE > TRAP_DISARM_LINE ))"
# `type = bool` is LOAD-BEARING: Terraform's `%{ if }` directive HCL-bool-converts its
# operand — the canonical string "false" coerces to boolean false (the rollback route
# TF_VAR_web_colocate_inngest="false"), and a non-bool string fails CLOSED at plan time
# ("condition must be of type bool"). `type = bool` pins the variable-boundary contract;
# the render leg's "false" (string) case exercises the coercion end-to-end.
assert "web_colocate_inngest declared type = bool (load-bearing string→bool coercion)" \
  "[ \"\$(awk '/variable \"web_colocate_inngest\"/,/^}/' '$VARS_TF' | grep -cE 'type[[:space:]]*=[[:space:]]*bool' || true)\" -gt 0 ]"

# --- AC7: web_colocate_inngest gate — terraform render authority ---
# The single behavioral authority for the gate's effect. A real `terraform templatefile`
# render is the ONLY thing that exercises the load-bearing `~}` whitespace-strip; the
# rendered-YAML validity property also lives here (not duplicated in AC3). SKIP locally
# when terraform is absent — CI's deploy-script-tests job supplies it via setup-terraform.
echo ""
echo "--- AC7: web_colocate_inngest gate — terraform render authority ---"
# ENVIRONMENT-CONDITIONAL BLOCK (see the COND_ASSERTIONS contract near the top of this file).
_COND_BEFORE=$TOTAL
TF_AVAILABLE=0
if command -v terraform >/dev/null 2>&1; then
  TF_AVAILABLE=1
  RENDER_SCRATCH=$(mktemp -d)
  # Render the web cloud-init into $2. $1 = web_colocate_inngest; $3 = web_tunnel_connector
  # (defaults true = web-1, the connector host, so AC7's call sites stay two-arg).
  # All map vars are placeholders EXCEPT the toggles; keep in sync with server.tf's
  # templatefile map — a new map var breaks this render (the intended tripwire).
  # stderr is NOT swallowed: a render error must surface, not present as an empty file
  # whose assertions fail with a misleading "OMITS" pass (#6425).
  render_ci() {
    local colocate="$1" out="$2" connector="${3:-true}"
    printf 'templatefile("%s", { image_name="i", fail2ban_sshd_local_b64="x", host_scripts_content_hash="h", tunnel_token="TT_SENTINEL_6425", webhook_deploy_secret="w", doppler_token="d", sentry_dsn="s", resend_api_key="r", ci_ssh_public_key_openssh="k", workspaces_volume_id="v", registry_endpoint="reg", web_colocate_inngest=%s, web_tunnel_connector=%s, host_name="soleur-web-platform", private_ip="10.0.1.10", web_probes_token="t", expected_ip="10.0.1.10", web_host_key="hk", zot_probe_repo="zr", betterstack_ingest_url="bs", soleur_doppler_token_env_b64="RE9QUExFUl9UT0tFTj1k", zot_pull_user="zp", zot_pull_token="zt" })\n' \
      "$CLOUD_INIT" "$colocate" "$connector" | terraform -chdir="$RENDER_SCRATCH" console > "$out"
    # A truncated/empty render makes every `! grep` assertion pass vacuously.
    [[ -s "$out" ]] || { echo "  FATAL: render produced no output (colocate=$colocate connector=$connector)"; return 1; }
  }
  # yaml.safe_load a rendered doc, stripping terraform console's `<<EOT … EOT` heredoc wrapper.
  render_yaml_ok() {
    python3 - "$1" <<'PY'
import sys, yaml
L = open(sys.argv[1]).read().splitlines()
body = "\n".join(L[1:-1]) if (L and L[0].lstrip().startswith("<<")) else "\n".join(L)
yaml.safe_load(body)
PY
  }
  # --- #6446: the raw-source step is KEPT, and must stay directive-stripped ---
  # An earlier draft of this PR DELETED infra-validation.yml's raw-source step and guarded
  # its absence. #6426 landed on main mid-pipeline with a different fix for the same issue:
  # keep the step, strip the col-0 `%{` directive lines, validate the remainder. The two are
  # complementary, not competing, so both are kept (operator call) — main's step catches
  # schema errors in the non-gate body WITHOUT needing terraform; the rendered check below
  # catches what it structurally cannot see.
  #
  # So the invariant flipped: the guard is no longer "the step is gone" but "the step never
  # points at the UNSTRIPPED template again". Anchored on `-c <path>` so the workflow's own
  # explanatory comment (which names the old broken form) cannot satisfy it.
  INFRA_VALIDATION_WF="$SCRIPT_DIR/../../../.github/workflows/infra-validation.yml"
  assert "infra-validation.yml schema-checks the STRIPPED render, never the raw template (#6446/#6426)" \
    "! grep -qE '^[[:space:]]*cloud-init schema -c cloud-init\.yml[[:space:]]*$' '$INFRA_VALIDATION_WF'"
  # The POSITIVE half asserts schema coverage EXISTS. It is a two-item ALLOWLIST, NOT a general
  # "any mechanism" check — a workflow-text grep structurally cannot verify that a script it
  # merely CALLS performs the check, so an allowlist is the honest ceiling. It accepts main's
  # stripped step or a line-leading `bash …validate-infra-templates.sh` (#6458's current path).
  # A third mechanism, or #6458 renaming its script, reds this and must be added here.
  # Pinning `-c /tmp/cloud-init.stripped.yml` ALONE would pin main's *implementation* (a
  # temp-file path) and red #6458 for a deliberate UPGRADE of the coverage this guard protects.
  # A drift guard must fail on SILENT LOSS of coverage, never on an upgrade of it.
  #
  # Anchored on a line-leading command: prose cannot produce one, and BOTH workflows name these
  # tokens in explanatory comments (the instance-4 trap in 2026-07-15-narrowing-is-not-anchoring…
  # — a bare substring here would be vacuous). `[^-]` after `bash ` rejects lint-only decoys:
  # `bash -n <script>` syntax-checks and validates nothing.
  assert "infra-validation.yml still schema-checks a NON-raw cloud-init source (#6426 stripped | #6458 rendered)" \
    "grep -qE '^[[:space:]]*(cloud-init schema -c /tmp/cloud-init\.stripped\.yml|bash [^-].*validate-infra-templates\.sh)' '$INFRA_VALIDATION_WF'"
  # The second alternate is SELF-VALIDATING: naming the script is not evidence it schema-checks.
  # Without this, swapping the stripped step for a `bash …validate-infra-templates.sh` line
  # greens the guard while coverage is GONE (the script does not exist on this branch) — a
  # silent loss, the exact thing the contract above forbids. `bash <missing>` would red the
  # `validate` matrix job, but that job's check name is dynamic and cannot be a required
  # context — the "red for days, nobody blocked" pathology this guard backstops (see #6473).
  # Conditional, so it costs nothing until #6458 lands.
  VALIDATE_TEMPLATES_SH="$SCRIPT_DIR/../../../.github/scripts/validate-infra-templates.sh"
  if grep -qE '^[[:space:]]*bash [^-].*validate-infra-templates\.sh' "$INFRA_VALIDATION_WF"; then
    assert "validate-infra-templates.sh exists and actually runs cloud-init schema (#6458)" \
      "[[ -x '$VALIDATE_TEMPLATES_SH' ]] && grep -q 'cloud-init schema' '$VALIDATE_TEMPLATES_SH'"
  fi

  # --- #6446: cloud-init schema on the RENDERED doc ---
  # infra-validation.yml used to run `cloud-init schema -c cloud-init.yml` against the RAW
  # templatefile() source. That is structurally incapable: the file is a Terraform template,
  # not YAML. It survived for years only because `${...}` interpolations sit inside values and
  # parse as ordinary scalars — false-green. The first column-0 `%{ if ... ~}` directive turned
  # it false-RED (`%` is YAML's reserved directive indicator, so the parser aborts before
  # cloud-init ever sees the doc), and it stayed red on every infra PR because `validate` is
  # not a required check. This leg already holds the only real render, so the check belongs
  # here — the schema is a property of the RENDERED state, which is what boots a host.
  # Deleting the raw-source step without this would drop the coverage entirely.
  cloud_init_schema_ok() {
    local stripped="$1.schema.yml"
    # Same heredoc-strip as render_yaml_ok — terraform console wraps output in `<<EOT … EOT`.
    python3 - "$1" "$stripped" <<'PY'
import sys
L = open(sys.argv[1]).read().splitlines()
body = "\n".join(L[1:-1]) if (L and L[0].lstrip().startswith("<<")) else "\n".join(L)
open(sys.argv[2], "w").write(body + "\n")
PY
    # Warnings (e.g. no datasource) are expected; only a non-zero exit is a failure.
    cloud-init schema -c "$stripped"
  }
  # Resolve availability ONCE and SKIP visibly — never fold the absence into a passing
  # assert, which would read as coverage that never ran (the #6446 failure mode itself).
  HAVE_CLOUD_INIT=0
  if command -v cloud-init >/dev/null 2>&1; then
    HAVE_CLOUD_INIT=1
  elif [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
    # In CI the binary is installed by deploy-script-tests, so its absence means that
    # wiring regressed — FAIL loudly rather than SKIP. A bare SKIP false-greens here:
    # proven by masking cloud-init off PATH with CI=true, which exited 0 ("50/50 passed,
    # OK") with the 3 schema asserts silently gone. "Visible in a green advisory job's
    # log" is not visible. That is #6446's own failure mode — coverage that isn't there —
    # reintroduced with a longer fuse, so this arm IS the drift guard for the install step.
    # Mirrors the AC6 tag-reachability precedent above.
    assert "cloud-init installed in CI (rendered-schema guard must not silently disarm)" "false"
    echo "        cloud-init absent in a CI run — verify the 'Install cloud-init' step on"
    echo "        deploy-script-tests in .github/workflows/infra-validation.yml."
  else
    echo "  SKIP: cloud-init not installed locally (rendered-schema checks skipped — CI installs it and FAILs if absent)"
  fi

  # false (bool) and "false" (string, the rollback route) must BOTH gate off.
  for CASE in 'false' '"false"'; do
    OUT="$RENDER_SCRATCH/render.txt"
    render_ci "$CASE" "$OUT"
    assert "render web_colocate_inngest=$CASE OMITS soleur-inngest-bootstrap image pull" \
      "! grep -qF 'soleur-inngest-bootstrap' '$OUT'"
    assert "render web_colocate_inngest=$CASE OMITS the inngest-bootstrap.sh invocation" \
      "! grep -qF 'EXTRACT_DIR/inngest-bootstrap.sh' '$OUT'"
    assert "render web_colocate_inngest=$CASE RETAINS --name soleur-web-platform (app bring-up)" \
      "grep -qF 'name soleur-web-platform' '$OUT'"
    assert "render web_colocate_inngest=$CASE RETAINS INNGEST_BASE_URL" \
      "grep -qF 'INNGEST_BASE_URL' '$OUT'"
    # Retention token = the poweroff item's UNIQUE fail-closed action string (cloud-init.yml
    # ~:710), NOT the bare 'soleur-hostscripts.ok' (which also appears in pre-gate comments
    # :440/:527 and would match regardless of endif placement — user-impact-review hardening
    # against a vacuous retention assertion).
    assert "render web_colocate_inngest=$CASE RETAINS fail-closed 'refusing to start app' poweroff gate" \
      "grep -qF 'refusing to start app' '$OUT'"
    # #6396: the Vector shipper is DECOUPLED from web_colocate_inngest — a fresh ungated web host
    # installs Vector via the end-of-chain soleur-vector-install runcmd (baked in
    # soleur-host-bootstrap.sh), NOT the gated inngest path. This RETAINS on the gated-OFF render.
    assert "render web_colocate_inngest=$CASE RETAINS ungated 'soleur-vector-install' (#6396)" \
      "grep -qF 'soleur-vector-install' '$OUT'"
    assert "render web_colocate_inngest=$CASE is valid YAML" "render_yaml_ok '$OUT'"
    # #6446: YAML-parseable is necessary but NOT sufficient — a doc can safe_load and
    # still be rejected by cloud-init's own schema (a malformed write_files entry, a
    # bad runcmd shape). This is the check infra-validation.yml was structurally unable
    # to perform against the raw template.
    if (( HAVE_CLOUD_INIT )); then
      assert "render web_colocate_inngest=$CASE passes cloud-init schema" \
        "cloud_init_schema_ok '$OUT'"
    fi
  done
  # true (bool) keeps the co-located bootstrap.
  TRUE_OUT="$RENDER_SCRATCH/render-true.txt"
  render_ci true "$TRUE_OUT"
  assert "render web_colocate_inngest=true INCLUDES soleur-inngest-bootstrap image pull" \
    "grep -qF 'soleur-inngest-bootstrap' '$TRUE_OUT'"
  assert "render web_colocate_inngest=true INCLUDES the inngest-bootstrap.sh invocation" \
    "grep -qF 'EXTRACT_DIR/inngest-bootstrap.sh' '$TRUE_OUT'"
  assert "render web_colocate_inngest=true is valid YAML" "render_yaml_ok '$TRUE_OUT'"
  if (( HAVE_CLOUD_INIT )); then
    assert "render web_colocate_inngest=true passes cloud-init schema" \
      "cloud_init_schema_ok '$TRUE_OUT'"
  fi

  # --- AC5 (#6425): web_tunnel_connector gate — terraform render authority ---
  # ONE connector per tunnel is the invariant (ADR-114 I1/I2). Cloudflare binds ingress
  # to a TUNNEL and then picks a connector per edge colo, so a second cloudflared replica
  # makes every `localhost:` / `ssh.` ingress mean "whichever replica answered" rather than
  # "this host". Gating registration to the designated ingress host makes it deterministic
  # BY CONSTRUCTION — this render is the only authority that exercises the `~}` trim.
  echo ""
  echo "--- AC5: web_tunnel_connector gate — terraform render authority (#6425) ---"
  CONN_ON="$RENDER_SCRATCH/render-conn-on.txt"
  render_ci false "$CONN_ON" true
  assert "render web_tunnel_connector=true INCLUDES the cloudflared service install" \
    "grep -qF 'cloudflared service install' '$CONN_ON'"
  assert "render web_tunnel_connector=true INCLUDES the tunnel token" \
    "grep -qF 'TT_SENTINEL_6425' '$CONN_ON'"
  assert "render web_tunnel_connector=true INCLUDES the cloudflared readiness poll" \
    "grep -qF 'soleur-wait-ready service cloudflared' '$CONN_ON'"
  assert "render web_tunnel_connector=true is valid YAML" "render_yaml_ok '$CONN_ON'"
  # #6441 (ADR-114 I1): the first-boot NIC gate. THIS is the only place the "inside the
  # `%{ if }` block" property is checkable — a raw-source grep passes identically if the line
  # lands OUTSIDE the directive pair, which would run a NIC wait on a future non-connector
  # host (waiting out the full budget on an address it will never hold, then emitting a
  # spurious private_nic_timeout). The sibling nic-wait-gate.test.sh owns the helper's
  # BEHAVIOUR; the gating is owned here, where the render actually happens.
  assert "render web_tunnel_connector=true INCLUDES the NIC wait with the interpolated IP" \
    "grep -qF 'soleur-wait-nic 10.0.1.10' '$CONN_ON'"
  # Adjacency, not mere presence: the wait must sit IMMEDIATELY before the install so its
  # budget is SEQUENTIAL with the downstream cloudflared_ready gate rather than nested inside
  # it. A wait that drifts below the install would spend cloudflared_ready's ~60 s budget and
  # detonate that gate's pre-existing `|| exit 1` — the CF-5 abort this gate exists to prevent.
  NIC_IDX=$(grep -nF 'soleur-wait-nic 10.0.1.10' "$CONN_ON" | head -1 | cut -d: -f1 || true)
  INS_IDX=$(grep -nF 'cloudflared service install' "$CONN_ON" | head -1 | cut -d: -f1 || true)
  assert "rendered NIC wait immediately precedes cloudflared service install" \
    "[[ -n '$NIC_IDX' && -n '$INS_IDX' && \$(( INS_IDX - NIC_IDX )) -eq 1 ]]"

  CONN_OFF="$RENDER_SCRATCH/render-conn-off.txt"
  render_ci false "$CONN_OFF" false
  assert "render web_tunnel_connector=false OMITS the cloudflared service install" \
    "! grep -qF 'cloudflared service install' '$CONN_OFF'"
  # The security half of the gate: a de-pooled host's rendered user_data must not carry
  # the live tunnel token at all (user_data is readable from the host's own metadata service).
  assert "render web_tunnel_connector=false OMITS the tunnel token entirely" \
    "! grep -qF 'TT_SENTINEL_6425' '$CONN_OFF'"
  assert "render web_tunnel_connector=false OMITS the cloudflared readiness poll" \
    "! grep -qF 'soleur-wait-ready service cloudflared' '$CONN_OFF'"
  # A non-connector host must not run the NIC wait at all: it never registers a connector, so
  # the gate has nothing to gate, and on a host that legitimately holds no private IP it would
  # burn the full budget and emit a false private_nic_timeout.
  assert "render web_tunnel_connector=false OMITS the NIC wait entirely (#6441)" \
    "! grep -qF 'soleur-wait-nic' '$CONN_OFF'"
  # The apt install stays UNGATED — only tunnel REGISTRATION is gated, so a de-pooled host
  # keeps the binary and stays promotable without an image change.
  assert "render web_tunnel_connector=false RETAINS ungated 'apt-get install -y cloudflared'" \
    "grep -qF 'apt-get install -y cloudflared' '$CONN_OFF'"
  # RETENTION TOKENS BELOW THE endif — the assertions above cannot constrain the gate's LOWER
  # boundary, because the apt-install token sits ABOVE the `%{ if }`. Without these, moving the
  # `%{ endif ~}` DOWN swallows the webhook install + its fail-closed :9000 poll and every
  # assertion here still passes — a de-pooled host would boot permanently undeployable and
  # would not even fail closed (the poll it needs to fail on is inside the swallowed region).
  # AC7 gets this for free (all four of its retention tokens sit below its endif); this gate's
  # geometry does not, so the lower boundary must be pinned explicitly.
  assert "render web_tunnel_connector=false RETAINS the webhook install (gate must not over-reach)" \
    "grep -qF 'webhook-linux-amd64.tar.gz' '$CONN_OFF'"
  assert "render web_tunnel_connector=false RETAINS the webhook checksum fail-closed guard" \
    "grep -qF 'soleur-boot-emit webhook_checksum fatal' '$CONN_OFF'"
  # Column-0 hazard: an indented `%{ if ~}` leaves its leading spaces after the `~` trim and
  # corrupts runcmd: list indentation. safe_load is what catches it.
  assert "render web_tunnel_connector=false is valid YAML (column-0 directive hazard)" \
    "render_yaml_ok '$CONN_OFF'"
  # The render cannot see WHICH host maps to which toggle value — and that mapping is the
  # risk that darkens web-1 (AC5's inverted-predicate catastrophe). Pin it at the source.
  assert "server.tf pins the connector predicate to web-1 (each.key == \"web-1\")" \
    "grep -qE 'web_tunnel_connector[[:space:]]*=[[:space:]]*each\.key[[:space:]]*==[[:space:]]*\"web-1\"' '$SCRIPT_DIR/server.tf'"

  rm -rf "$RENDER_SCRATCH"
else
  echo "  SKIP: terraform not installed (render authority skipped — CI deploy-script-tests provides it via setup-terraform)"
fi

COND_ASSERTIONS=$(( COND_ASSERTIONS + TOTAL - _COND_BEFORE ))

echo ""
echo "--- The cosign correction comment must itself be true (#6617 / plan CF-2) ---"
# This PR exists because a false comment ("the cold-boot OCI pull is signature-verified")
# propagated into a plan and then into an acceptance criterion. The correction that replaced
# it introduced a NEW false claim in the same breath — that real verification exists in
# `cloud-init-registry.yml` — so the correction needs the same guard the original lacked.
#
# Ground truth: cloud-init-registry.yml contains ZERO cosign INVOCATIONS. Every `cosign`
# occurrence in it is a comment about zot's `sha256-*` tag RETENTION policy, i.e. keeping the
# signature tags around so ci-deploy.sh's verify can fetch them. Retaining a signature is not
# verifying one.
INNGEST_CI_YML="$SCRIPT_DIR/cloud-init-inngest.yml"
REGISTRY_CI_YML="$SCRIPT_DIR/cloud-init-registry.yml"
# Strip comments (full-line and trailing) before looking for an invocation, so the file's own
# prose about cosign cannot satisfy this (cq-assert-anchor-not-bare-token).
REGISTRY_COSIGN_CODE="$(sed -E 's/#.*$//' "$REGISTRY_CI_YML" | grep -c 'cosign' || true)"
assert "cloud-init-registry.yml runs cosign ZERO times (every occurrence is a retention comment)" \
  "[[ '$REGISTRY_COSIGN_CODE' -eq 0 ]]"
assert "cloud-init-registry.yml's cosign mentions are about sha256-* signature-tag retention" \
  "grep -qE '^[[:space:]]*#.*sha256-\*' '$REGISTRY_CI_YML'"
# The claim under guard. The sentence WRAPS across comment lines, so a line-based grep
# matches nothing and passes vacuously against the false text — measured. Flatten the comment
# prose to one line first, then assert on the joined sentence.
# `|| true` INSIDE the substitution, mirroring the convention AC6's PIN extraction already
# uses. Without it a zero-match grep exits 1, pipefail promotes the pipeline, the assignment
# fails and `set -e` kills the WHOLE script here — before the anti-vacuity accounting below and
# before the results summary, so the run exits 1 having printed no `=== Results ===` line and
# no failing assertion at all. Measured while mutation-proving Guard 1: pointing this file at
# an empty source produced exactly that silent abort, which is strictly worse than a named
# FAIL because it destroys the diagnosis rather than reporting it.
INNGEST_CI_PROSE="$(grep -E '^[[:space:]]*#' "$INNGEST_CI_YML" | sed -E 's/^[[:space:]]*#[[:space:]]?//' | tr '\n' ' ' | tr -s ' ' || true)"
assert "harness non-vacuity: the flattened prose carries the cosign correction sentence at all" \
  "grep -qF 'verification exists only in' <<<\"\$INNGEST_CI_PROSE\""
# Asserted on the false CONJUNCTION rather than on proximity: the corrected sentence still
# names cloud-init-registry.yml (to say what it actually does), so a distance-based regex
# would fire on the fix too. Listing it as a second place verification "exists" — "... and
# cloud-init-registry.yml" — is precisely the error.
assert "the cosign correction does NOT list cloud-init-registry.yml as a verification site" \
  "! grep -qF 'and cloud-init-registry.yml' <<<\"\$INNGEST_CI_PROSE\""
assert "the cosign correction names ci-deploy.sh as the sole real verification path" \
  "grep -qF 'verification exists only in ci-deploy.sh' <<<\"\$INNGEST_CI_PROSE\""
assert "the cosign correction states registry's role is RETAINING the sha256-* tags verify depends on" \
  "grep -qF 'cloud-init-registry.yml only retains the sha256-* signature tags' <<<\"\$INNGEST_CI_PROSE\""

# =========================================================================================
# GUARD 1 (#7462) — zot-primary bootstrap pull arm on the DEDICATED inngest host
# =========================================================================================
# PROPERTY. The dedicated inngest host resolves its bootstrap image from zot and from zot ONLY
# (#8036 item 1d / ADR-096 5.3b-i: the GHCR read leg is gone, because the read PAT it presented
# is revoked and no GHCR arm could succeed); every registry outcome is reported off-box; and a
# zot miss ENDS the boot and pages as `inngest_pull_fatal` rather than falling through to a
# second registry that does not exist.
#
# ASSEMBLY. The chokepoint is the single ref-resolution region: `IREF=` (the digest-pin
# CARRIER, never pulled — the bump bot and the AC6 drift guard read it), `ZIREF=`, the one
# `docker pull "$ZIREF"`, and `IREF="$ZIREF"` on a hit. Every consumer of the image ref
# DOWNSTREAM of that point must read the resolved value rather than re-derive it: the extract
# container, the /etc/default record and `docker inspect "$IREF"` (which sources
# INNGEST_CLI_VERSION/SHA256 from the image env). A second consumer re-deriving the GHCR literal
# is precisely how a "zot-only" change ships while still reading from GHCR.
#
# WHY THE COUNT AND THE SET ARE BOTH ASSERTED. `GHCR_LITERAL_COUNT == 1` is blind to a rename
# (a consumer switched from "$IREF" to "$SOMETHING_ELSE" keeps the count at 1), so the
# per-consumer greps assert the SET. Neither alone is sufficient.
#
# WHAT IS NOT HERE. Order and LIFETIME of the miss arm (fatal emit, then a non-zero exit that
# ends the whole runcmd, with no later pull/create) are asserted by EXECUTING the rendered item
# under stubs — Guard 4 below. A grep cannot see that an `exit` sits inside a subshell.
#
# ALL GREPS RUN OVER A COMMENT-STRIPPED COPY. This file's prose names `ghcr.io/jikig-ai/
# soleur-inngest-bootstrap`, `insecure-registries` and every stage literal below, so a
# body-grep over the raw source is satisfied by the explanation of the thing rather than the
# thing (cq-assert-anchor-not-bare-token). Line numbers survive the strip (`sed s/#.*$//`
# rewrites lines in place, never deletes them), so the ORDERING assertions below are computed
# against real file offsets.
echo ""
ZG_TOTAL_BEFORE="$TOTAL"
echo "--- Guard 1 (#7462): zot-primary bootstrap pull arm (dedicated host) ---"

DED_CODE_FILE="$(mktemp -t inngest-ci-code-XXXXXX.yml)"
DED_BLOCK_FILE="$(mktemp -t inngest-ci-block-XXXXXX.sh)"
# The existing EXIT trap already removes SNIPPET_FILE; extend it rather than replace it.
trap 'rm -f "$SNIPPET_FILE" "$DED_CODE_FILE" "$DED_BLOCK_FILE"' EXIT
sed -E 's/^[[:space:]]*#.*$//' "$INNGEST_CI_YML" > "$DED_CODE_FILE"

# The bootstrap runcmd block, isolated. Used ONLY for the anti-vacuity floor: every other
# assertion runs against the whole comment-stripped file, because the zot LOGIN and the
# docker-daemon allowlist deliberately live in earlier runcmd items (they must precede the
# pull, which is the whole point of Phase 5).
awk '
  /^  # --- Extract \+ run inngest-bootstrap\.sh from the baked OCI image/ { found = 1 }
  found && /^  - \|/ && !in_block { in_block = 1; next }
  in_block && /^  - / { exit }
  in_block && /^[^[:space:]]/ { exit }
  in_block { print }
' "$INNGEST_CI_YML" > "$DED_BLOCK_FILE"

# --- Row 6 (anti-vacuity): the guard must be unable to certify zero input -----------------
# A guard whose extraction silently yields nothing reports a clean PASS on every assertion
# below (`grep -q` over an empty file is simply false, and a `! grep -q` NEGATIVE passes).
# So the input is accounted for explicitly, and the floor is a LINE COUNT rather than
# `-s`: a one-line extract is non-empty and still proves nothing.
ZG_FILES_CHECKED=0
for _zf in "$INNGEST_CI_YML" "$DED_CODE_FILE" "$DED_BLOCK_FILE"; do
  [[ -s "$_zf" ]] && ZG_FILES_CHECKED=$((ZG_FILES_CHECKED + 1))
done
ZG_BLOCK_LINES=$(wc -l < "$DED_BLOCK_FILE")
assert "Row6 anti-vacuity: the guard examined all 3 of its inputs (a guard over zero files certifies nothing)" \
  "(( ZG_FILES_CHECKED == 3 ))"
assert "Row6 anti-vacuity: the bootstrap block extraction is substantive (>=40 lines, found $ZG_BLOCK_LINES)" \
  "(( ZG_BLOCK_LINES >= 40 ))"
assert "Row6 anti-vacuity: the comment strip preserved line numbering (code file line count == source line count)" \
  "(( \$(wc -l < '$DED_CODE_FILE') == \$(wc -l < '$INNGEST_CI_YML') ))"

# --- Offsets the ordering rows are computed from ------------------------------------------
# `|| true` on every extraction: under `set -euo pipefail` a zero-match grep would abort the
# whole script here, before the results summary. Let an empty offset fall through to a
# clean FAIL (the same convention AC6 above already uses for PIN).
zg_line() { grep -nE "$1" "$DED_CODE_FILE" | head -1 | cut -d: -f1 || true; }
L_IREF_SEED=$(zg_line '^[[:space:]]*IREF=ghcr\.io/jikig-ai/soleur-inngest-bootstrap:')
L_ZLOGIN=$(zg_line 'docker login "\$ZOT_EP"')
L_ZPULL=$(zg_line 'docker pull "\$ZIREF"')
L_ZIREF=$(zg_line '^[[:space:]]*ZIREF=')
L_PREZOT=$(zg_line 'inngest-boot-phone-home\.sh pre-zot-pull')
L_RECORD=$(zg_line "INNGEST_BOOTSTRAP_IMAGE=%s")
L_DAEMON=$(zg_line 'insecure-registries')
# Anchored on the RESTART ITSELF, not on the runcmd-item form it happened to have. The restart
# was a bare `- systemctl restart docker` item until it was wrapped to report its own failure
# (it had no off-box channel: `cloud-init` is not in vector.toml's Source-4 allowlist and Vector
# ships inside the image this boot has not pulled). A `^\s*- ` anchor pinned the YAML shape
# rather than the command, so making the restart OBSERVABLE reddened the guard — the anchor
# tracked the wrong thing. `^\s*(- )?(if )?systemctl restart docker` accepts either form and
# still cannot be satisfied by a comment.
L_DOCKER_RESTART=$(zg_line '^[[:space:]]*(- )?(if )?systemctl restart docker')

assert "Row1 offsets: the IREF pin-carrier assignment was found" "[[ -n '$L_IREF_SEED' ]]"
assert "Row1 offsets: the zot ref assignment (ZIREF=) was found" "[[ -n '$L_ZIREF' ]]"
assert "Row1 offsets: the zot leg's docker pull was found" "[[ -n '$L_ZPULL' ]]"
assert "Row1 offsets: the pre-zot-pull emit was found" "[[ -n '$L_PREZOT' ]]"
assert "Row1 offsets: the INNGEST_BOOTSTRAP_IMAGE record was found" "[[ -n '$L_RECORD' ]]"

# --- Row 1: zot is the ONLY pull, bracketed by pre-zot-pull and an outcome emit -------------
# The pin carrier is assigned before the zot leg (so the hit is a single atomic reassignment,
# never a re-derivation), `pre-zot-pull` precedes the pull it brackets (a pre-zot-pull with no
# outcome marker = hung), and the pull precedes the record every consumer reads.
# EVERY arithmetic comparison is guarded on BOTH operands being non-empty. bash arithmetic
# coerces an empty string to 0, so a bare `(( L_ZPULL < L_PRE ))` with an unmatched L_ZPULL
# evaluates `0 < 583` and reports PASS — a guard that certifies an ordering between a line
# that exists and one that does not. Measured on this very suite's first RED run: two
# ordering rows passed while the code they order had not been written yet.
assert "Row1: the IREF pin carrier is assigned before the zot leg runs (atomic reassignment, not a re-derivation)" \
  "[[ -n '$L_IREF_SEED' && -n '$L_ZPULL' ]] && (( L_IREF_SEED < L_ZPULL ))"
assert "Row1: pre-zot-pull is emitted BEFORE the zot pull it brackets" \
  "[[ -n '$L_PREZOT' && -n '$L_ZPULL' ]] && (( L_PREZOT < L_ZPULL ))"
assert "Row1: the zot pull runs BEFORE the INNGEST_BOOTSTRAP_IMAGE record" \
  "[[ -n '$L_ZPULL' && -n '$L_RECORD' ]] && (( L_ZPULL < L_RECORD ))"
assert "Row1: the zot ref is ASSIGNED before it is pulled" \
  "[[ -n '$L_ZIREF' && -n '$L_ZPULL' ]] && (( L_ZIREF < L_ZPULL ))"
# Exactly ONE image pull in the whole file, and it is the zot ref. The retired shape pulled a
# second time on "$IREF" to reach the GHCR-seeded ref; any second pull is that leg coming back.
ZG_PULL_LINES=$(grep -cE '(^|[[:space:];|&(])docker[[:space:]]+pull[[:space:]]' "$DED_CODE_FILE" || true)
ZG_ZPULL_LINES=$(grep -cE '(^|[[:space:];|&(])docker[[:space:]]+pull[[:space:]]+"\$ZIREF"' "$DED_CODE_FILE" || true)
assert "Row1: exactly ONE docker pull code line, and it pulls \"\$ZIREF\" (pulls $ZG_PULL_LINES, zot $ZG_ZPULL_LINES)" \
  "(( ZG_PULL_LINES == 1 && ZG_ZPULL_LINES == 1 ))"

# --- Row 2: the digest pin governs the carrier AND the zot ref -----------------------------
# `crane copy` is digest-preserving, so the SAME @sha256 the build signed resolves on zot. A
# mutable-tag zot ref would hand a root-executed shell script's identity back to whoever can
# re-point the tag, over plain HTTP — the pin is the only integrity control on that payload.
ZG_GHCR_REF=$(grep -oE 'ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' "$DED_CODE_FILE" | head -1 || true)
ZG_GHCR_DIGEST="${ZG_GHCR_REF##*@}"
ZG_ZOT_LINE=$(grep -E '^[[:space:]]*ZIREF=' "$DED_CODE_FILE" | head -1 || true)
ZG_ZOT_DIGEST=$(grep -oE 'sha256:[0-9a-f]{64}' <<<"$ZG_ZOT_LINE" | head -1 || true)
assert "Row2: the IREF pin carrier carries a full sha256 digest pin" \
  "[[ '$ZG_GHCR_DIGEST' =~ ^sha256:[0-9a-f]{64}$ ]]"
assert "Row2: the zot leg carries a full sha256 digest pin (no mutable-tag form)" \
  "[[ '$ZG_ZOT_DIGEST' =~ ^sha256:[0-9a-f]{64}$ ]]"
assert "Row2: the pin carrier and the zot ref pin the SAME digest (crane copy is digest-preserving)" \
  "[[ -n '$ZG_ZOT_DIGEST' && '$ZG_ZOT_DIGEST' == '$ZG_GHCR_DIGEST' ]]"

# --- Row 3: every registry outcome is reported off-box ------------------------------------
# The Better Stack half. inngest-boot-phone-home.sh's signature is `<stage> [detail]` with NO
# severity argument, so the STAGE NAME carries the whole signal. The same outcomes ALSO reach
# Sentry through a host-local soleur-boot-emit (#6500); that half is Guard 1b below, which pins
# the call sites per ARM rather than per file. `inngest_pull_fatal` shares no prefix with
# `inngest_zot`: Better Stack greps are substring matches, so an `inngest_zot…` failure stage
# would count a dark boot as a zot-served one.
L_ZOTHIT=$(zg_line 'inngest-boot-phone-home\.sh inngest_zot')
L_MISS=$(zg_line 'inngest-boot-phone-home\.sh inngest_pull_fatal "zot miss')
assert "Row3: a zot HIT phone-homes inngest_zot" "[[ -n '$L_ZOTHIT' ]]"
assert "Row3: a zot MISS phone-homes inngest_pull_fatal (the terminal-boot signal)" "[[ -n '$L_MISS' ]]"
assert "Row3: both outcome emits sit AFTER the zot pull and BEFORE the INNGEST_BOOTSTRAP_IMAGE record" \
  "[[ -n '$L_ZOTHIT' && -n '$L_MISS' && -n '$L_ZPULL' && -n '$L_RECORD' ]] && (( L_ZPULL < L_ZOTHIT && L_ZOTHIT < L_RECORD && L_ZPULL < L_MISS && L_MISS < L_RECORD ))"
assert "Row3: the hit and the miss are DIFFERENT emit sites (one line cannot report both outcomes)" \
  "[[ -n '$L_ZOTHIT' && '$L_ZOTHIT' != '$L_MISS' ]]"
ZG_BAD_STAGE=$(grep -oE '(inngest-boot-phone-home\.sh|soleur-boot-emit)[[:space:]]+inngest_zot[A-Za-z0-9_]+' "$DED_CODE_FILE" | wc -l || true)
assert "Row3: no emitted stage EXTENDS inngest_zot (a substring-matched Better Stack grep would count it as served; found $ZG_BAD_STAGE)" \
  "(( ZG_BAD_STAGE == 0 ))"

# --- Row 4: one resolution, every consumer follows it -------------------------------------
# OCCURRENCES, not lines. `grep -c` counts matching LINES, so a second literal appended to the
# same line kept this at 1 and the whole "one resolution, every consumer follows it" property
# was evadable by a one-line edit. Measured: two literals on one line -> grep -c returns 1.
ZG_GHCR_LITERALS=$(grep -oE 'ghcr\.io/jikig-ai/soleur-inngest-bootstrap' "$DED_CODE_FILE" | wc -l || true)
assert "Row4: exactly ONE GHCR literal survives comment-stripping (the IREF pin carrier); found $ZG_GHCR_LITERALS" \
  "(( ZG_GHCR_LITERALS == 1 ))"
L_REPOINT=$(zg_line '^[[:space:]]*IREF="\$ZIREF"$')
assert "Row4: consumer 1/4 — IREF is re-pointed at the zot ref (IREF=\"\$ZIREF\") after the pull and before the record" \
  "[[ -n '$L_REPOINT' && -n '$L_ZPULL' && -n '$L_RECORD' ]] && (( L_ZPULL < L_REPOINT && L_REPOINT < L_RECORD ))"
assert "Row4: consumer 2/4 — the extract container reads \$IREF" \
  "grep -qF 'docker create --name soleur-inngest-bootstrap-extract \"\$IREF\"' '$DED_CODE_FILE'"
assert "Row4: consumer 3/4 — /etc/default/soleur-inngest-image records \$IREF" \
  "grep -qE 'INNGEST_BOOTSTRAP_IMAGE=%s.*\"\\\$IREF\".*/etc/default/soleur-inngest-image' '$DED_CODE_FILE'"
assert "Row4: consumer 4/4 — the Config.Env inspect reads \$IREF" \
  "grep -qF 'docker inspect \"\$IREF\"' '$DED_CODE_FILE'"

# --- Row 5 (#8036 1d): the retired GHCR leg is gone, as CODE -------------------------------
# Residual-zero over the comment-stripped file. Each token is the retired leg's own marker: the
# baked read credential and its file, the `docker login ghcr.io` item, the second pull's
# bracket, and the fallback stage. Comments may still NAME them (history); code may not.
for _rz in 'ghcr_read_' 'GHCR_READ_' 'soleur-ghcr-read' 'inngest_ghcr_fallback' 'pre-oci-pull' 'oci-pull-rc' 'oci-pull-ALL-LEGS-FAILED' 'ghcr-login-' 'ghcr-creds-EMPTY'; do
  _n=$(grep -cF -- "$_rz" "$DED_CODE_FILE" || true)
  assert "Row5 residual-zero: no code line carries '$_rz' (found $_n)" "(( _n == 0 ))"
done
# Any flag order: `docker login -u x --password-stdin ghcr.io` is the same credential presentation.
ZG_GHCR_LOGIN=$(grep -cE 'docker([[:space:]]+[^|;&]*)?[[:space:]]login([[:space:]][^|;&]*)?[[:space:]]"?ghcr\.io' "$DED_CODE_FILE" || true)
assert "Row5 residual-zero: no code line logs in to ghcr.io, in any flag order (found $ZG_GHCR_LOGIN)" \
  "(( ZG_GHCR_LOGIN == 0 ))"

# --- Phase 4: docker must be willing to talk to a plain-HTTP private-net registry ----------
# Without the allowlist the zot leg cannot succeed even with correct credentials, so a
# "zot-primary" arm would fall back on EVERY boot and the change would be inert-by-accident.
assert "Phase4: the docker daemon config allowlists an insecure registry" \
  "grep -qF 'insecure-registries' '$DED_CODE_FILE'"
assert "Phase4: the allowlisted entry is the BAKED endpoint, never a hardcoded address" \
  "[ \"\$(grep -E 'insecure-registries' '$DED_CODE_FILE' | grep -cF 'ZOT_EP' || true)\" -gt 0 ]"
assert "Phase4: docker is RESTARTED after the daemon config is written (the package starts it during \`packages:\`, before runcmd)" \
  "[[ -n '$L_DAEMON' && -n '$L_DOCKER_RESTART' ]] && (( L_DAEMON < L_DOCKER_RESTART && L_DOCKER_RESTART < L_ZPULL ))"

# --- Phase 5: the zot login must precede the pull it authorizes ----------------------------
# Load-bearing placement: the bootstrap image's OWN zot_login runs too late to authorize the
# pull that fetches that very image.
assert "Phase5: the host logs in to zot from the baked creds" "[[ -n '$L_ZLOGIN' ]]"
assert "Phase5: the zot login precedes the zot pull" \
  "[[ -n '$L_ZLOGIN' ]] && (( L_ZLOGIN < L_ZPULL ))"
for _zs in zot-login-ok zot-login-FAILED zot-creds-EMPTY; do
  assert "Phase5: phone-home stage '$_zs' is emitted (each login outcome reports its own stage)" \
    "grep -qF 'inngest-boot-phone-home.sh $_zs' '$DED_CODE_FILE'"
done

# --- The resolution gate: a CONFIGURED endpoint runs the zot leg --------------------------
# (#8036 1d: an UNCONFIGURED endpoint is no longer "today's path" — there is no second registry,
# so the gate's else arm is fatal `inngest_pull_fatal`; Guard 4 executes that arm.)
# ANCHORED TO THE GATE THAT GUARDS THE ARM, not to any occurrence of the token. `[ -n "$ZOT_EP" ]`
# appears three times (docker daemon config, zot login, ref resolution), so the previous
# whole-file grep was satisfied by any of them — and inverting the ONE that gates the resolution
# region to `[ -z ... ]`, which runs the zot leg only when zot is UNCONFIGURED and skips it
# exactly when zot is configured, left the ENTIRE suite green at 117/117 and the mutation
# battery at 9/9. Measured, not hypothesised. That inversion negates every property this arm
# claims, so the gate is pinned positionally: it must be the `if [` immediately preceding the
# ZIREF assignment. This is the placement-vs-behaviour class — the old assertion pinned that a
# token existed somewhere, never that the branch it controls has the right sense.
ZG_ARM_GATE="$(grep -B2 '^[[:space:]]*ZIREF=' "$DED_CODE_FILE" | grep -E '^[[:space:]]*if \[' | tail -1 || true)"
assert "Dark-safe: the resolution region's OWN gate was found (an unmatched gate must not pass vacuously)" \
  "[[ -n \"\$ZG_ARM_GATE\" ]]"
assert "Dark-safe: that gate is a NON-EMPTY test (an inverted gate runs the arm only when zot is unconfigured)" \
  "grep -qE '\\[ -n \"\\\$ZOT_EP\" \\]' <<<\"\$ZG_ARM_GATE\""

# --- The baked pull credential must be redactable ------------------------------------------
# The zot pull log tail is SHIPPED off-box by `inngest_pull_fatal`. inngest-redact.sh redacts by KNOWN
# VALUE, so a credential absent from its value list is a credential that ships in clear on an
# auth failure — which is exactly the failure mode that produces a log tail worth shipping.
# SCOPED to the script body, not the file. `ZOT_PULL_TOKEN` occurs 4x in the yml (the bake
# printf, the login item, the redact list), so a whole-file grep stayed green with the redact
# line deleted — a cq-assert-anchor-not-bare-token violation on SCOPE rather than on comments.
ZG_REDACT_BODY="$(awk '/^  - path: \/usr\/local\/bin\/inngest-redact\.sh$/{f=1;next} f&&/^  - path: /{f=0} f' "$INNGEST_CI_YML")"
assert "the zot pull token is in inngest-redact.sh's known-value list" \
  "grep -qF 'ZOT_PULL_TOKEN' <<<\"\$ZG_REDACT_BODY\""
# #8036 1d: the GHCR read file is no longer baked, so the redactor must not source it — a code
# line naming it is the retired leg's credential path surviving in a root-run script.
assert "the zot token reaches that list from the baked soleur-zot-read file, and no redactor CODE line still sources soleur-ghcr-read / GHCR_READ_TOKEN" \
  "grep -qE '^[^#]*\\. /etc/default/soleur-zot-read.*ZOT_PULL_TOKEN' <<<\"\$ZG_REDACT_BODY\" && ! grep -qE '^[^#]*(soleur-ghcr-read|GHCR_READ_TOKEN)' <<<\"\$ZG_REDACT_BODY\""

# --- Pin consistency on the DEDICATED file (AC6b's sibling) --------------------------------
# AC6b asserts count==2 && distinct==1 for cloud-init.yml (web host: IREF + ZIREF). The
# dedicated host now has the same two-ref shape, so it inherits the same partial-bump risk:
# bumping IREF and leaving ZIREF stale would 404 the zot leg on every fresh boot and fall
# back silently to GHCR forever.
DED_PIN_REF_COUNT=$(grep -coE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$DED_CODE_FILE" || true)
DED_DISTINCT_PINS=$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$DED_CODE_FILE" | sort -u | wc -l || true)
assert "dedicated-host pin-consistency: both refs (IREF + ZIREF) present and share one tag (found $DED_PIN_REF_COUNT refs, $DED_DISTINCT_PINS distinct)" \
  "(( DED_PIN_REF_COUNT == 2 && DED_DISTINCT_PINS == 1 ))"

# --- Guard B (#7695): tag<->digest binding across EVERY pin site -------------------------
# The block above pins the two DEDICATED-host legs. It could not see `cloud-init.yml`, whose
# two sites were TAG-ONLY -- the silent-downgrade state that let #7630 pin a v1.1.25 tag to
# v1.1.24's bytes. This extension quantifies over all four sites in one sweep.
#
# WHAT THIS GUARD DOES AND DOES NOT PROVE. It proves cross-site AGREEMENT: one tag, one
# digest, no tag-only site. Agreement alone would pass on four CONSISTENTLY WRONG digests.
# The correctness half is carried by Guard A (the pinned tag's tree IS HEAD's carriers) and
# by AC5 (the digest was read by command from the run that signed it). The three are sound
# only together; none of them is sufficient alone. See `## Guard Contract` row B6.
#
# Test fixtures fall outside the swept population; see the note below on exactly how, and on
# which assertion is the actual control:
# `cloud-init-inngest-zot-pull-mutation.test.sh` pins a deliberately stale
# v1.1.24@sha256:6cdaa63d... as a NEGATIVE CONTROL, and a sweep that "helpfully" updates it
# destroys the control.
GB_BEFORE="$TOTAL"
# THE POPULATION IS DERIVED, NOT ENUMERATED, and that is a correction. An earlier revision named
# two files explicitly (`--include='cloud-init.yml' --include='cloud-init-inngest.yml'`) with a
# hardcoded `== 4`. That does not quantify over pin sites -- it quantifies over two filenames, so
# a NEW `cloud-init-*.yml` carrying a stale tag-only pin was completely invisible (measured: an
# added cloud-init-inngest-worker.yml pinned to v1.1.19 produced zero delta). Four sibling
# cloud-init-*.yml already exist in this directory.
#
# So sweep the GLOB and derive the expected count from what was swept.
#
# HOW THE NEGATIVE CONTROL IS PROTECTED, STATED ACCURATELY. An earlier revision of this comment
# claimed an "explicit EXCLUDE, which is a rule" -- there is NO --exclude in this guard, and
# crediting a control that is not in the code is worse than crediting none, because the next
# reader who adds a `cloud-init-*.yml` fixture with a deliberately stale pin will trust a rule
# that does not exist. What actually keeps cloud-init-inngest-zot-pull-mutation.test.sh (pinning
# a deliberately stale v1.1.24@sha256:6cdaa63d...) out of the population is that a `.test.sh`
# cannot match the `cloud-init*.yml` glob. That is weak on its own, so the real guarantee is the
# POSITIVE assertion at the end of this block: it reds if the stale pin is ever "helpfully"
# updated, which is the failure that would destroy the control.
GB_SITES_FILE="$(mktemp -t inngest-pin-sites-XXXXXX.txt)"
GB_FILES="$(grep -rlE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' \
             --include='cloud-init*.yml' "$SCRIPT_DIR" 2>/dev/null | sort -u || true)"
grep -rhoE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+(@sha256:[0-9a-f]{64})?' \
  --include='cloud-init*.yml' "$SCRIPT_DIR" > "$GB_SITES_FILE" 2>/dev/null || true
GB_SITE_COUNT=$(grep -c . "$GB_SITES_FILE" || true)
GB_FILE_COUNT=$(printf '%s\n' "$GB_FILES" | grep -c . || true)
# Own dispatch. A FLOOR of 4 (the two files known to carry pins, two legs each) catches a sweep
# that found too few; the assertions below then quantify over however many exist, so an added
# file is covered without a guard edit rather than being silently outside the population.
assert "GuardB dispatch: the pin sweep found at least the 4 known sites across $GB_FILE_COUNT file(s) (found $GB_SITE_COUNT)" \
  "[[ '$GB_SITE_COUNT' =~ ^[0-9]+$ ]] && (( GB_SITE_COUNT >= 4 ))"
# Row 4: a site carrying a tag but no digest is the silent downgrade. Counted directly.
GB_TAG_ONLY=$(grep -cE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+$' "$GB_SITES_FILE" || true)
assert "GuardB: no pin site is tag-only (found $GB_TAG_ONLY tag-only site(s))" \
  "(( GB_TAG_ONLY == 0 ))"
# Rows 1-3: one tag and one digest across every site. Distinctness catches a partial bump at
# ANY site, including a second site after a compliant first.
GB_DISTINCT_TAGS=$(grep -oE ':v[0-9]+\.[0-9]+\.[0-9]+' "$GB_SITES_FILE" | sort -u | wc -l || true)
GB_DISTINCT_DIGESTS=$(grep -oE 'sha256:[0-9a-f]{64}' "$GB_SITES_FILE" | sort -u | wc -l || true)
GB_DIGEST_COUNT=$(grep -coE 'sha256:[0-9a-f]{64}' "$GB_SITES_FILE" || true)
assert "GuardB: every pin site names the SAME tag ($GB_DISTINCT_TAGS distinct)" \
  "(( GB_DISTINCT_TAGS == 1 ))"
assert "GuardB: every pin site carries a digest ($GB_DIGEST_COUNT of $GB_SITE_COUNT)" \
  "(( GB_DIGEST_COUNT == GB_SITE_COUNT ))"
assert "GuardB: every pin site names the SAME digest ($GB_DISTINCT_DIGESTS distinct)" \
  "(( GB_DISTINCT_DIGESTS == 1 ))"
# H2 (must-PASS, non-canonical): the ZIREF legs' differing quoting and registry prefix
# ("$ZOT_EP/..." and "$ZURL/...") versus IREF's bare ghcr.io/... is a PERMITTED difference --
# the sweep matches from `soleur-inngest-bootstrap:` rightward, so prefix and quoting are out
# of scope by construction. It is the tag and the digest that must not differ.
GB_PREFIX_SHAPES=$(grep -rhoE '(ghcr\.io|\$ZOT_EP|\$ZURL)/jikig-ai/soleur-inngest-bootstrap:' \
  --include='cloud-init.yml' --include='cloud-init-inngest.yml' "$SCRIPT_DIR" 2>/dev/null | sort -u | wc -l || true)
assert "GuardB H2: differing registry prefixes across legs are permitted, not flagged ($GB_PREFIX_SHAPES shapes)" \
  "(( GB_PREFIX_SHAPES >= 2 ))"
# The negative control must stay stale. Asserted POSITIVELY so that "helpfully" bumping it
# reds here rather than silently removing the only fixture that proves the sweep discriminates.
GB_NEGCTL="$SCRIPT_DIR/cloud-init-inngest-zot-pull-mutation.test.sh"
assert "GuardB: the deliberately-stale negative control is untouched by the sweep" \
  "[[ ! -f '$GB_NEGCTL' ]] || (( \$(grep -cF 'soleur-inngest-bootstrap:v1.1.24@sha256:' '$GB_NEGCTL' || true) >= 1 ))"
rm -f "$GB_SITES_FILE"

# --- GuardB row 6 (#7695): the tag MOVED but the digest DID NOT --------------------------------
# THE MEASURED BYPASS THIS CLOSES. Guard A resolves the pinned TAG and compares its tree to HEAD;
# Guard B compares the four sites to EACH OTHER. So writing `v1.1.26@sha256:<v1.1.25's digest>` at
# all four sites satisfies both -- one tag, one digest, no tag-only site, and the tag's tree IS
# HEAD's carriers -- while the host boots the OLD bytes. Measured on this branch: 161/161 green.
# That is the #7630 shape verbatim, and it is the shape an operator produces by bumping the tag
# and forgetting to re-resolve the digest.
#
# Binding a digest to a tag needs a registry read, which no PR-gating job here can do. But the
# DEFECT is hermetically detectable: if this branch moves the tag relative to the merge base and
# leaves the digest untouched, that is the bug, and git can see it.
#
# origin/main is a moving ref. Post-merge it carries this same pin, so old == new and the check
# becomes a no-op rather than inverting -- the safe direction. If it is unresolvable the row
# SKIPs loudly rather than passing silently: "could not compare" must not read as "compared".
GB_BASE_PIN=""
if git -C "$SCRIPT_DIR" rev-parse -q --verify origin/main >/dev/null 2>&1; then
  GB_BASE_PIN="$(git -C "$SCRIPT_DIR" show origin/main:apps/web-platform/infra/cloud-init-inngest.yml 2>/dev/null \
    | grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' | head -1 || true)"
fi
GB_HEAD_PIN="$(grep -ohE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' \
  "$SCRIPT_DIR/cloud-init-inngest.yml" 2>/dev/null | head -1 || true)"
# THE ASSERTION COUNT MUST NOT DEPEND ON THE ENVIRONMENT. An earlier revision put the
# no-comparable-base case in its own branch emitting ONE assert where the live path emits TWO --
# so in the zot-pull mutation sandbox (a throwaway `git init` repo with no `origin/main`) the
# section ran 8 instead of 9, both anti-vacuity floors redded, and the battery's BASELINE went
# red. That turns a real verdict into the unresolved class and is exactly what an exact floor
# cannot tolerate. So: always two asserts, with unavailability carried as a VALUE in the message
# and short-circuited inside the condition, never as a different arm.
GB_ROW6_NOTE="base=${GB_BASE_PIN:-UNAVAILABLE} head=${GB_HEAD_PIN:-UNAVAILABLE}"
GB_BASE_TAG="${GB_BASE_PIN%%@*}"; GB_BASE_DIG="${GB_BASE_PIN##*@}"
GB_HEAD_TAG="${GB_HEAD_PIN%%@*}"; GB_HEAD_DIG="${GB_HEAD_PIN##*@}"
assert "GuardB row6: the tag moved only alongside a moved digest [$GB_ROW6_NOTE]" \
  "[[ -z '$GB_BASE_PIN' || -z '$GB_HEAD_PIN' ]] || [[ '$GB_BASE_TAG' == '$GB_HEAD_TAG' || '$GB_BASE_DIG' != '$GB_HEAD_DIG' ]]"
assert "GuardB row6: the digest moved only alongside a moved tag [$GB_ROW6_NOTE]" \
  "[[ -z '$GB_BASE_PIN' || -z '$GB_HEAD_PIN' ]] || [[ '$GB_BASE_DIG' == '$GB_HEAD_DIG' || '$GB_BASE_TAG' != '$GB_HEAD_TAG' ]]"

# GUARD B'S OWN ANTI-VACUITY FLOOR. Previously these asserts were pooled into the ZG span's
# floor of 47, of which only 7 belong to Guard B -- so deleting a Guard B assert and adding an
# unrelated filler anywhere in that 266-line span kept the floor green while a real production
# RED vanished. Measured. A floor that spans two unrelated inventories is fungible between them.
GUARDB_ASSERTIONS=$(( TOTAL - GB_BEFORE ))
assert "GuardB anti-vacuity: the section ran its full inventory (expected 9, ran $GUARDB_ASSERTIONS)" \
  "(( GUARDB_ASSERTIONS == 9 ))"

# --- Guard 1 anti-vacuity FLOOR: the section's own assertion count ------------------------
# Row6 above floors the guard's INPUTS. Nothing floored its ASSERTIONS, so deleting every
# `assert` in this section left the suite exit 0 with a clean summary — the headline claim
# ("the arm is pinned") resting on nothing. Measured. EXACT rather than `>=`: a `>=` floor with
# slack is attack budget, and one derived from what it guards descends with it. When you add an
# assertion here, bump this number in the same edit — that is the point, not friction.
# 50 -> 59 (#8036 1d): Row1 +1 (the one-pull row), Row3 +1 (no stage extends inngest_zot), Row5
# +7 (the all-legs rows became ten residual-zero rows for the retired GHCR leg).
ZG_SECTION_ASSERTIONS=$(( TOTAL - ZG_TOTAL_BEFORE ))
assert "Guard 1 anti-vacuity: the section ran its full assertion inventory (expected 59, ran $ZG_SECTION_ASSERTIONS)" \
  "(( ZG_SECTION_ASSERTIONS == 59 ))"

# --- Guard 1b (#6500): each pull-outcome ARM reports on the Sentry `stage:` schema ----------
# zot-soak-6122.sh counts `stage:"inngest_zot"`/`"inngest_pull_fatal"` in Sentry and anchors
# its #6500 corroboration on `^\s*soleur-boot-emit inngest_zot ` / `... inngest_pull_fatal `.
# (#8036 1d renamed the miss arm's stage from inngest_ghcr_fallback and raised it to FATAL: the
# miss is terminal now, not a fallback.)
# A file-level grep would accept both calls in ONE arm, so the zot `if` is split at its own
# `if [ "$zot_rc" -eq 0 ]` / `else` / `fi` and each ARM is asserted separately. The arms are
# comment-stripped: DED_BLOCK_FILE is extracted from the raw file, and a commented-out call must
# not count.
echo ""
echo "--- Guard 1b (#6500): per-arm Sentry stage emits (dedicated host) ---"
G1B_BEFORE="$TOTAL"
ARM_ZOT="$(mktemp -t inngest-arm-zot-XXXXXX)"
ARM_FB="$(mktemp -t inngest-arm-fb-XXXXXX)"
trap 'rm -f "$SNIPPET_FILE" "$DED_CODE_FILE" "$DED_BLOCK_FILE" "$ARM_ZOT" "$ARM_FB"' EXIT
# DEPTH-AWARE (review P1-2/P2-3): the split happens only at nesting depth 0, and only depth-0
# statements are emitted into an arm file, because a statement inside a nested block (`if false;
# then … fi`, a `case`, a loop) is not an unconditional statement of the arm. A nested `else` must
# not flip arms and a nested `fi` must not end the extraction. Heredoc bodies are data, not code,
# and are skipped whole (`: <<'OFF' … OFF` is the other way to write dead code).
sed -E '/^[[:space:]]*#/d' "$DED_BLOCK_FILE" | awk -v Z="$ARM_ZOT" -v F="$ARM_FB" '
  hd != "" { t = $0; sub(/^[[:space:]]+/, "", t); if (t == hd) hd = ""; next }
  !arm && /^[[:space:]]*if \[ "\$zot_rc" -eq 0 \]; then$/ { arm = "z"; d = 0; next }
  !arm { next }
  match($0, /<<-?[[:space:]]*\047?[A-Za-z_]+\047?/) {
    hd = substr($0, RSTART, RLENGTH); gsub(/[<\047 -]/, "", hd); next
  }
  /^[[:space:]]*(if|case|while|until|for)[[:space:]]/ { d++; next }
  /^[[:space:]]*(fi|esac|done)([[:space:]]|;|$)/ {
    if (d == 0) { if (arm == "f") exit; next }
    d--; next
  }
  d == 0 && arm == "z" && /^[[:space:]]*else$/ { arm = "f"; next }
  d > 0 { next }
  arm == "z" { print > Z }
  arm == "f" { print > F }
'
G1B_ZOT_LINES=$(grep -c . "$ARM_ZOT" || true)
G1B_FB_LINES=$(grep -c . "$ARM_FB" || true)
# Dispatch floor (row 12): an anchor that drifted yields an EMPTY arm, and every negative below
# would then pass over nothing.
assert "G1b dispatch: the served (zot) arm was extracted (>=3 code lines, found $G1B_ZOT_LINES)" \
  "(( G1B_ZOT_LINES >= 3 ))"
assert "G1b dispatch: the missed (fatal) arm was extracted (>=3 code lines, found $G1B_FB_LINES)" \
  "(( G1B_FB_LINES >= 3 ))"
G1B_ZOT_OK=$(grep -cE '^[[:space:]]*soleur-boot-emit inngest_zot info "ep=\$ZOT_EP" \|\| true$' "$ARM_ZOT" || true)
G1B_FB_OK=$(grep -cE '^[[:space:]]*soleur-boot-emit inngest_pull_fatal fatal "rc=\$zot_rc" \|\| true$' "$ARM_FB" || true)
G1B_ZOT_ANY=$(grep -c 'soleur-boot-emit' "$ARM_ZOT" || true)
G1B_FB_ANY=$(grep -c 'soleur-boot-emit' "$ARM_FB" || true)
assert "G1b: the served arm emits inngest_zot exactly once, bare name, foreground, || true (found $G1B_ZOT_OK)" \
  "(( G1B_ZOT_OK == 1 ))"
assert "G1b: the missed arm emits inngest_pull_fatal at FATAL exactly once, bare name, foreground, || true (found $G1B_FB_OK)" \
  "(( G1B_FB_OK == 1 ))"
assert "G1b: each arm carries exactly ONE soleur-boot-emit call (served $G1B_ZOT_ANY, missed $G1B_FB_ANY)" \
  "(( G1B_ZOT_ANY == 1 && G1B_FB_ANY == 1 ))"
assert "G1b: no soleur-boot-emit call is backgrounded (it could outlive cloud-final and be killed with its cgroup)" \
  "! grep -qE '^[[:space:]]*soleur-boot-emit .*&[[:space:]]*\$' '$DED_CODE_FILE'"
# The write_files half: the emitter is delivered executable, the DSN file 0600, and the DSN file
# carries the templatefile variable. Each entry is sliced to its own `- path:` block so a
# permissions line from the NEXT entry cannot satisfy it.
wf_block() { awk -v p="  - path: $1" '$0==p{f=1;print;next} f&&/^  - path: /{f=0} f' "$INNGEST_CI_YML"; }
assert "G1b: write_files delivers /usr/local/bin/soleur-boot-emit 0755" \
  "wf_block /usr/local/bin/soleur-boot-emit | grep -qxF \"    permissions: '0755'\""
assert "G1b: write_files delivers /etc/default/soleur-sentry-dsn 0600 (the DSN never world-readable)" \
  "wf_block /etc/default/soleur-sentry-dsn | grep -qxF \"    permissions: '0600'\""
assert "G1b: the DSN file is the templatefile sentry_dsn value" \
  "wf_block /etc/default/soleur-sentry-dsn | grep -qxF \"      SOLEUR_SENTRY_DSN='\\\${sentry_dsn}'\""
assert "G1b: inngest-host.tf threads sentry_dsn = var.sentry_dsn into this template" \
  "grep -qE '^[[:space:]]*sentry_dsn[[:space:]]*=[[:space:]]*var\.sentry_dsn\$' '$SCRIPT_DIR/inngest-host.tf'"
G1B_ASSERTIONS=$(( TOTAL - G1B_BEFORE ))
assert "G1b anti-vacuity: the section ran its full inventory (expected 10, ran $G1B_ASSERTIONS)" \
  "(( G1B_ASSERTIONS == 10 ))"

# --- Row 7: a failed bootstrap must say WHY, on the one channel that still works -----------
# The failure that kills the bootstrap also kills Vector, which is installed BY the bootstrap. So
# on a non-zero exit the failing unit's stderr exists ONLY in journald on a host that
# hr-no-ssh-fallback-in-runbooks forbids logging into. Measured 2026-08-16 (#7462 delivery): the
# zot leg served the image, `bootstrap-exit-1` shipped systemd's generic "see journalctl", Better
# Stack held zero journald rows for the host, and the cause cost a full replace cycle to not learn.
R7_BEFORE="$TOTAL"
L_R7_EXIT=$(zg_line '^[[:space:]]*exit "\$boot_rc"')
L_R7_EMIT=$(zg_line 'inngest-boot-phone-home\.sh bootstrap-failure-journal')
L_R7_JOURNAL=$(zg_line 'journalctl -xu inngest-server\.service')
L_R7_FAILED=$(zg_line 'systemctl --failed')

assert "Row7: the failure path emits a bootstrap-failure-journal marker" \
  "[[ -n \"\$L_R7_EMIT\" ]]"
assert "Row7: it captures the failing unit's journal (journalctl -xu inngest-server.service)" \
  "[[ -n \"\$L_R7_JOURNAL\" ]]"
assert "Row7: it names WHICH unit failed (systemctl --failed), not only inngest-server" \
  "[[ -n \"\$L_R7_FAILED\" ]]"
# ORDERING IS THE PROPERTY, not presence. A capture emitted after `exit` is dead code that every
# presence-only assertion above would still certify green — the exact vacuity class #7516 shipped.
assert "Row7: the journal capture runs BEFORE exit \$boot_rc (after it is unreachable)" \
  "[[ -n \"\$L_R7_JOURNAL\" && -n \"\$L_R7_EXIT\" ]] && (( L_R7_JOURNAL < L_R7_EXIT ))"
assert "Row7: the marker is emitted BEFORE exit \$boot_rc" \
  "[[ -n \"\$L_R7_EMIT\" && -n \"\$L_R7_EXIT\" ]] && (( L_R7_EMIT < L_R7_EXIT ))"
# The journal carries env-delivered Postgres/Redis URIs and signing keys on a failed ExecStart,
# and this lands in a source the whole team reads.
assert "Row7: the journal is scrubbed through inngest-redact.sh before shipping" \
  "grep -qE 'journalctl -xu inngest-server\\.service.*inngest-redact\\.sh' \"\$DED_CODE_FILE\""
assert "Row7: both captures are BOUNDED (head -c), so one runaway unit cannot fill the channel" \
  "(( \$(grep -cE 'head -c (300|1200)' \"\$DED_CODE_FILE\") >= 2 ))"

R7_ASSERTIONS=$(( TOTAL - R7_BEFORE ))
assert "Row7 anti-vacuity: the section ran its full inventory (expected 7, ran $R7_ASSERTIONS)" \
  "(( R7_ASSERTIONS == 7 ))"


# =========================================================================================
# Guard A (#7695) — carrier coherence: the pinned tag's tree IS this tree's carriers
# =========================================================================================
# PROPERTY. Every file the image bakes is byte-identical, at the PINNED tag, to HEAD's copy.
#
# WHY THIS GUARD IS THE DURABLE ONE. The image is a CONTENT CARRIER: an edit to a baked file
# reaches the host only if the image was built from a commit that already contained it. Merge
# A (#7778) added the probe_schema=3 emitter to inngest-bootstrap.sh and bumped no pin, so the
# live host has run pre-emitter bytes ever since. This guard makes that state RED instead of
# silent.
#
# HERMETIC AND GIT-ONLY. No network, no registry auth, no new binary — `git show <tag>:<path>`
# against the working copy. deploy-script-tests checks out with fetch-depth: 0 and
# fetch-tags: true, so the tag is present. A live registry re-resolution CANNOT run here:
# `crane` is not provisioned in this job and adding it would red every PR permanently. The
# live arm lives on the apply path, which already holds GHCR credentials.
#
# WHAT IT PROVES, AND THE THREE RESIDUALS IT DOES NOT CLOSE. Soundness chain: pinned digest
# (immutable bytes) <- the build run of tag T <- the git tree at tag T <- byte-identical to
# HEAD's carriers. That binds TAG->SOURCE, never the registry bytes. Residuals, all requiring
# repo write: (1) a default workflow_dispatch re-runs docker build and re-pushes the same tag,
# so the tag's GHCR digest MOVES (only mirror_only cannot move it); (2) git tags are mutable
# and no ruleset here protects them; (3) actions/checkout resolves a bare ref: to a remote
# BRANCH before a tag, so a branch named vinngest-vX.Y.Z would build from the branch head.
# Cosign is NOT a mitigation: the workflow's own header says the signature is "not a provenance
# claim any consumer verifies", and the inngest deploy branch never calls verification.
GUARDA_BEFORE="$TOTAL"
GA_WF="$SCRIPT_DIR/../../../.github/workflows/build-inngest-bootstrap-image.yml"
assert "GuardA: the build workflow is readable" "[[ -r '$GA_WF' ]]"

# Repo paths come from the `cp` STAGING lines, which carry real paths. Deriving from COPY
# would smuggle in an unstated apps/web-platform/infra/ prefix assumption.
GA_CP_PATHS=$(grep -oE '^[[:space:]]*cp apps/web-platform/infra/[A-Za-z0-9._-]+ ' "$GA_WF" 2>/dev/null | awk '{print $2}' | sort -u || true)
# Baked basenames come from the COPY lines, parsed STRICTLY: exactly two operands. A third
# field (a --chmod flag, a second source) is a form the extractor must not silently accept.
GA_COPY_NAMES=$(grep -E '^[[:space:]]*COPY [^ ]+ [^ ]+[[:space:]]*$' "$GA_WF" 2>/dev/null | awk '{print $2}' | sort -u || true)
# Counted PERMISSIVELY. This is the load-bearing line: any COPY form the strict pattern cannot
# read shows up as "parsed 9 of 10" and REDS, rather than reporting ten-of-ten while quietly
# guarding one file fewer. An extractor that counted only what it could parse is structurally
# unable to report its own blindness.
GA_TOTAL_COPY=$(grep -cE '^[[:space:]]*COPY ' "$GA_WF" 2>/dev/null || true)
GA_N_COPY=$(printf '%s\n' "$GA_COPY_NAMES" | grep -c . || true)
GA_N_CP=$(printf '%s\n' "$GA_CP_PATHS" | grep -c . || true)
# `grep -c ... || true` yields "" on an unreadable file, and (( "" == "" )) is a vacuous 0 == 0
# that PASSES. Pin the count's own shape here rather than relying on a sibling assert to red.
assert "GuardA dispatch: the COPY count is a positive integer (got '$GA_TOTAL_COPY')" \
  "[[ '$GA_TOTAL_COPY' =~ ^[0-9]+$ ]] && (( GA_TOTAL_COPY > 0 ))"
assert "GuardA dispatch: every COPY form parsed (parsed $GA_N_COPY of $GA_TOTAL_COPY)" \
  "(( GA_N_COPY == GA_TOTAL_COPY ))"
assert "GuardA dispatch: cp/COPY cardinality agrees ($GA_N_CP staged vs $GA_TOTAL_COPY baked)" \
  "(( GA_N_CP == GA_TOTAL_COPY ))"
# Same FILES, not merely the same count — a swap keeps cardinality intact.
GA_CP_BASES=$(printf '%s\n' "$GA_CP_PATHS" | xargs -n1 basename 2>/dev/null | sort -u || true)
assert "GuardA: the staged set and the baked set name the SAME files" \
  "[[ \"\$(printf '%s\n' \"\$GA_CP_BASES\")\" == \"\$(printf '%s\n' \"\$GA_COPY_NAMES\")\" ]]"

# The tag is read from the pin literal, so the guard FOLLOWS the pin rather than a hardcoded
# version. A hardcoded tag would drift silently the first time the pin moved.
GA_PIN_TAG=$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$SCRIPT_DIR/cloud-init-inngest.yml" 2>/dev/null | head -1 | sed 's/.*://' || true)
assert "GuardA: the pinned tag was read from the pin literal (found '$GA_PIN_TAG')" \
  "[[ '$GA_PIN_TAG' =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]"
GA_TAG_REF="vinngest-$GA_PIN_TAG"
# Row 4: an unresolvable tag REDS naming itself. "Nothing to compare, pass" is the failure
# mode this row exists to make impossible — an unfetched tag and a nonexistent one take the
# same git show path and are one row deliberately.
# `git -C "$SCRIPT_DIR"`, NOT bare `git`: AC6 in this same file was deliberately hardened this way,
# and Guard A was not. Bare git resolves against the PROCESS CWD while the working-copy comparand
# is SCRIPT_DIR-relative, so a CWD/SCRIPT_DIR split silently pairs one repo's tag blobs with
# another tree's files and reports eleven greens assembled from two different trees.
git -C "$SCRIPT_DIR" rev-parse -q --verify "refs/tags/$GA_TAG_REF^{commit}" >/dev/null 2>&1 && GA_TAG_OK=1 || GA_TAG_OK=0
assert "GuardA: the pinned tag $GA_TAG_REF resolves in git (never 'nothing to compare, pass')" \
  "(( GA_TAG_OK == 1 ))"

# The comparison. CONTENT-ONLY: mtime and mode are permitted to differ (H2) — a guard that
# reds on mtime is a guard nobody keeps. Second-member-after-a-compliant-first is the failure
# this repo actually had, so the loop never stops at the first file.
# THE COMPARISON PRIMITIVE, AND ITS INSTRUMENT SELF-TEST.
#
# GA_COMPARED counts LOOP TRIPS, not comparisons performed, so on its own it is structurally
# incapable of witnessing a HOLLOWED comparison: replacing the body with `if false` keeps the
# count at ten while comparing nothing, and the section stays green. Measured -- an earlier
# revision of this guard claimed the exact count caught that, and it did not.
#
# The count is a DELETION floor. What catches HOLLOWING is driving the comparison primitive over
# a known-identical and a known-different pair and refusing to continue unless BOTH verdicts
# moved. Route the loop through the same function so the two cannot drift apart.
ga_cmp() { # ga_cmp <fileA> <fileB> -> "same" | "differs"
  if diff -q "$1" "$2" >/dev/null 2>&1; then printf 'same'; else printf 'differs'; fi
}
GA_ST="$(mktemp -d -t guarda-selftest-XXXXXX)"
printf 'alpha\n' > "$GA_ST/a"; printf 'alpha\n' > "$GA_ST/b"; printf 'beta\n' > "$GA_ST/c"
GA_ST_SAME="$(ga_cmp "$GA_ST/a" "$GA_ST/b")"
GA_ST_DIFF="$(ga_cmp "$GA_ST/a" "$GA_ST/c")"
rm -rf "$GA_ST"
assert "GuardA instrument self-test: the comparison reports BOTH verdicts (same=$GA_ST_SAME differs=$GA_ST_DIFF)" \
  "[[ '$GA_ST_SAME' == 'same' && '$GA_ST_DIFF' == 'differs' ]]"

GA_COMPARED=0
GA_DRIFTED=""
GA_UNRESOLVED=""
if (( GA_TAG_OK == 1 )); then
  _ga_tmp="$(mktemp -t guarda-blob-XXXXXX)"
  while IFS= read -r _p; do
    [[ -n "$_p" ]] || continue
    if ! git -C "$SCRIPT_DIR" show "$GA_TAG_REF:$_p" > "$_ga_tmp" 2>/dev/null; then
      GA_UNRESOLVED="$GA_UNRESOLVED $(basename "$_p")"
      continue
    fi
    GA_COMPARED=$((GA_COMPARED + 1))
    if [[ "$(ga_cmp "$_ga_tmp" "$SCRIPT_DIR/../../../$_p")" == "differs" ]]; then
      GA_DRIFTED="$GA_DRIFTED $(basename "$_p")"
    fi
  done <<< "$GA_CP_PATHS"
  rm -f "$_ga_tmp"
fi
# A carrier that exists at HEAD but not at the tag is NOT "nothing to compare, pass" -- it is a
# file the image cannot contain. Reported separately so the message does not misdirect.
assert "GuardA: every carrier resolves at $GA_TAG_REF (unresolved:${GA_UNRESOLVED:- none})" \
  "[[ -z '$GA_UNRESOLVED' ]]"
assert "GuardA: every baked carrier is byte-identical at $GA_TAG_REF (drifted:${GA_DRIFTED:- none})" \
  "[[ -z '$GA_DRIFTED' ]]"
# H1 (must-RED, mutates the SUITE): hollowing the comparison to return success must still red.
# An exact cross-derived count is what sees it; a >= 1 floor would not.
assert "GuardA anti-vacuity: compared exactly the cross-derived carrier set ($GA_COMPARED of $GA_TOTAL_COPY)" \
  "(( GA_COMPARED == GA_TOTAL_COPY ))"

GUARDA_ASSERTIONS=$(( TOTAL - GUARDA_BEFORE ))
assert "GuardA anti-vacuity: the section ran its full inventory (expected 11, ran $GUARDA_ASSERTIONS)" \
  "(( GUARDA_ASSERTIONS == 11 ))"

# =========================================================================================
# Guard D (#7695) — quoted delimiters on generated artifacts
# =========================================================================================
# PROPERTY. Every heredoc that writes a generated host artifact uses a NON-EXPANDING
# delimiter, so no value in its body can be interpolated or executed at render time.
#
# ASSEMBLY IS ONE PASS OVER THE HEREDOC OPERATOR ITSELF, and that is a correction. An earlier
# revision used two greps -- one requiring the redirection `>` BEFORE the `<<` on the line, the
# other anchoring the delimiter word to end-of-line. Their blind spots intersected on the most
# idiomatic forms, and all three of these wrote a generated artifact with live command
# substitution while the section reported green (measured):
#     cat <<A > /etc/default/x          # redirect AFTER the operator
#     { cat <<B; } > /etc/default/x     # compound command
#     tee /etc/default/x <<C            # tee, which the old prose CLAIMED to cover
#     cat > /etc/default/x <<D  # note  # anything after the word hides it from an $ anchor
# So: find every `<<` / `<<-` operator ANYWHERE on a line and classify the delimiter as quoted or
# unquoted. Position of the redirection is not consulted at all, because it is not part of the
# property. `<<<` is neutralised first -- a herestring is not a heredoc and would otherwise be
# read as `<<` followed by `<`.
#
# SCOPED TO THIS ONE FILE. The build workflow's Dockerfile heredoc is legitimately unquoted --
# it must expand ${INNGEST_VERSION} -- so a repo-wide rule reds the build on day one.
#
# THIS GUARD'S GUARANTEE IS CONDITIONAL ON GUARD A BEING GREEN. It reads the WORKING COPY and
# says nothing about the bytes the pinned image actually carries: at vinngest-v1.1.25 this file
# still has the unquoted HEARTBEATEOF that HEAD fixed, so D is green on source while the
# deployed artifact violates its property. Only the composition (A green AND D green) covers the
# running host.
GUARDD_BEFORE="$TOTAL"
GD_SRC="$SCRIPT_DIR/inngest-bootstrap.sh"
assert "GuardD: the bootstrap script is readable" "[[ -r '$GD_SRC' ]]"
# Row 5 / own dispatch: an EXACT count. A pattern that matched nothing must RED reporting
# "0 heredocs found", never certify a scan that inspected nothing.
# THE PERMISSIVE/STRICT SPLIT, and why Guard D needs it as much as Guard A does. An earlier
# revision used ONE regex as both census and classifier, so a delimiter the alternation cannot
# read was subtracted from the inventory AND from the population in the same stroke -- it did not
# red, it disappeared. Measured: `cat > /usr/local/bin/soleur-injected.sh <<7EOF` with `$(id -un)`
# in the body is a live, expanding, root-executed render-time substitution, and it left all eight
# Guard D asserts green with the dispatch still reporting "found 10". A digit-initial delimiter is
# valid bash and is invisible to `[A-Za-z_][A-Za-z0-9_]*`.
#
# So count the OPERATOR permissively and parse the DELIMITER strictly, exactly as Guard A counts
# `COPY` permissively and parses its operands strictly. Any form the classifier cannot read now
# surfaces as "parsed 10 of 11" and reds.
GD_SRC_NOHERE="$(sed 's/<<</\x01/g' "$GD_SRC" 2>/dev/null || true)"
GD_ALL_PERMISSIVE=$(printf '%s\n' "$GD_SRC_NOHERE" | grep -coE '<<-?' || true)
GD_SCAN="$(printf '%s\n' "$GD_SRC_NOHERE" \
           | grep -oE "<<-?[[:space:]]*(\"[^\"]*\"|'[^']*'|[A-Za-z_][A-Za-z0-9_]*)" || true)"
GD_ALL=$(printf '%s\n' "$GD_SCAN" | grep -c . || true)
assert "GuardD dispatch: the operator count is a positive integer (got '$GD_ALL_PERMISSIVE')" \
  "[[ '$GD_ALL_PERMISSIVE' =~ ^[0-9]+$ ]] && (( GD_ALL_PERMISSIVE > 0 ))"
assert "GuardD dispatch: every heredoc operator parsed (parsed $GD_ALL of $GD_ALL_PERMISSIVE)" \
  "(( GD_ALL == GD_ALL_PERMISSIVE ))"
assert "GuardD dispatch: the heredoc scan found the full inventory (found $GD_ALL)" \
  "(( GD_ALL == 10 ))"
# Rows 1-3: the unquoted set. Row 2 (an unquoted delimiter AFTER several compliant ones) is
# why this counts every match rather than inspecting the first.
# Unquoted == the delimiter carries neither ' nor ". Derived from the SAME scan as the
# dispatch, so the two can never disagree about what was inspected.
# SITES, NOT NAMES. `sort -u` collapsed two unquoted heredocs sharing a delimiter into one
# member, so a SECOND `<<DOPPLEREOF` kept the count at 1, kept the name-based exemption satisfied,
# and redirected the content assertion below onto the FIRST body -- letting a live `$(id -un)` sit
# in the real /etc/default/inngest-server heredoc with every Guard D assert green. Measured.
# Count occurrences; dedupe only for the human-readable message.
GD_UNQ_SITES=$(printf '%s\n' "$GD_SCAN" | grep -vE "['\"]" | grep -c . || true)
GD_UNQ_NAMES=$(printf '%s\n' "$GD_SCAN" | grep -vE "['\"]" | sed -E "s/^<<-?[[:space:]]*//" | grep -E '.' | sort -u || true)
GD_UNQ_COUNT=$(printf '%s\n' "$GD_UNQ_NAMES" | grep -c . || true)
assert "GuardD: exactly one unquoted heredoc SITE remains (found $GD_UNQ_SITES)" \
  "(( GD_UNQ_SITES == 1 ))"
assert "GuardD: exactly one unquoted delimiter NAME remains (found $GD_UNQ_COUNT: ${GD_UNQ_NAMES:-none})" \
  "(( GD_UNQ_COUNT == 1 ))"
# THE ONE EXEMPTION, identified by NAME rather than by line. A line-anchored exemption breaks
# on any refactor that moves the write, turning an unrelated edit into a red suite.
#
# WHY DOPPLEREOF STAYS UNQUOTED, AND WHY "FIXING" IT WOULD BE A REGRESSION. It is unquoted
# deliberately, to interpolate $TOKEN and $DOPPLER_PROJECT into the env file. It is wrapped in
# ( umask 0137 && cat > ... ) precisely so the Doppler token never lands in a world-readable
# file even momentarily. A sentinel rewrite writes a temp file and renames it, destroying that
# guarantee -- it would regress CWE-732 to fix nothing. Do not "fix" this.
assert "GuardD: the sole unquoted delimiter is the named exemption (DOPPLEREOF)" \
  "[[ '$(printf '%s' "$GD_UNQ_NAMES" | tr -d '[:space:]')' == 'DOPPLEREOF' ]]"
# Row 4: the exemption grants "may interpolate", NEVER "may execute". The content assertion is
# what keeps it honest and stops it widening silently if that body later gains a backtick.
# The awk below stops at the FIRST DOPPLEREOF body, so it is only a statement about "the"
# exemption while exactly one exists. Pin that first.
GD_EXEMPT_SITES=$(grep -cE '<<-?DOPPLEREOF([[:space:]]|$)' "$GD_SRC" 2>/dev/null || true)
assert "GuardD: the exemption is a single site, so the body assertion cannot be redirected (found $GD_EXEMPT_SITES)" \
  "(( GD_EXEMPT_SITES == 1 ))"
GD_EXEMPT_BODY=$(awk '/<<-?DOPPLEREOF([[:space:]]|$)/{f=1;next} f&&/^[[:space:]]*DOPPLEREOF[[:space:]]*$/{exit} f' "$GD_SRC" 2>/dev/null || true)
GD_EXEMPT_LINES=$(printf '%s\n' "$GD_EXEMPT_BODY" | grep -c . || true)
# FLOOR THE EXTRACTION BEFORE COUNTING IN IT. Measured: rewriting the exemption as `<<-DOPPLEREOF`
# made the old awk match nothing, so the body came back EMPTY and `grep -c` over nothing returned
# 0 -- the assert written to catch an injected $( ) passed while one was sitting in the body.
# An empty extraction is a broken instrument, never a clean result.
assert "GuardD: the exempt body was actually extracted ($GD_EXEMPT_LINES lines)" \
  "(( GD_EXEMPT_LINES >= 3 ))"
GD_EXEC_CHARS=$(printf '%s' "$GD_EXEMPT_BODY" | grep -cE '`|\$\(' || true)
assert "GuardD: the exempt body can interpolate but NOT execute (no backtick, no \$( ) )" \
  "(( GD_EXEC_CHARS == 0 ))"
# H2 (must-PASS, non-canonical): the exempt write itself -- unquoted, the opposite of every
# other delimiter in the file -- must PASS. A real permitted difference, not a fixture.
assert "GuardD H2: the exempt DOPPLEREOF write is present and permitted" \
  "(( \$(grep -cF 'cat > /etc/default/inngest-server <<DOPPLEREOF' '$GD_SRC' || true) == 1 ))"

GUARDD_ASSERTIONS=$(( TOTAL - GUARDD_BEFORE ))
assert "GuardD anti-vacuity: the section ran its full inventory (expected 11, ran $GUARDD_ASSERTIONS)" \
  "(( GUARDD_ASSERTIONS == 11 ))"

# =======================================================================================
# NIC-G1 (#8539) — the private-NIC fallback is present, reloaded, and gates the zot login.
# (The plan names this "Guard 1"; prefixed NIC-G1 here because this file already has a
# Guard 1, #7462.)
#
# PROPERTY. Every rendered inngest user_data carries exactly one fallback `.network` file whose
# [Match] excludes eth0 and non-virtio links, a `networkctl reload` item that runs BEFORE the NIC
# wait, and exactly one NIC-wait call, carrying the templated `${inngest_private_ip}`, placed
# immediately before the FIRST private-net use in runcmd.
#
# WHICH COPY EACH ROW READS. Order, presence and the derived set (rows 1-4, 6-9, 11) read the
# RENDERED + STRIPPED user_data — the bytes that reach the host — produced by
# inngest-userdata-budget.sh (terraform's own templatefile + local.inngest_rationale_strip).
# Order is compared on PARSED runcmd LIST POSITIONS (yaml.safe_load), never line numbers: the zot
# login sits inside a multi-line `- |` item. Row 5 (templated, not literal) is a property of the
# SOURCE the render erases, so it reads cloud-init-inngest.yml raw, anchored on the call
# CONSTRUCT. Row 10 reads inngest-host.tf raw, scoped to the cloud-init-inngest.yml templatefile
# map (the budget render uses its own stub map and cannot see that binding).
#
# THE DERIVED "FIRST PRIVATE-NET USE". Private-net ACTIONS only: `docker login|pull`, or
# curl/nc/ping naming a 10.0.1.x address other than the host's own 10.0.1.40; the NIC-wait call
# line itself is excluded. Config WRITES that merely name the endpoint (the ZOT_EP daemon.json
# write, the soleur-zot-read creds bake) are NOT uses. One narrowing beyond the plan's wording:
# a `docker login|pull` whose target is an explicit PUBLIC hostname (`docker login ghcr.io`) is
# not a private-net use — scored literally, the GHCR login two items above the call would be the
# "first use" and the unchanged file would red. A variable target (`"$ZOT_EP"`, `"$IREF"`) is
# scored as a use, conservatively. It is derived, not assumed to be the zot login, so a future
# item that touches the private net earlier reds row 8.
# =======================================================================================
echo ""
echo "--- NIC-G1 (#8539): private-NIC fallback, reload, and the wait before the first private-net use ---"
NG1_BEFORE="$TOTAL"

# Row 5 (raw source): the call construct carries the template var, never a literal. Anchored on
# the runcmd list-item construct, so a comment naming the helper cannot satisfy it.
NG1_RAW_CALLS=$(grep -cE '^[[:space:]]*-[[:space:]]+/usr/local/bin/soleur-inngest-nic-wait ' "$INNGEST_CI_YML" || true)
NG1_RAW_TEMPLATED=$(grep -cE '^[[:space:]]*-[[:space:]]+/usr/local/bin/soleur-inngest-nic-wait \$\{inngest_private_ip\} \|\| true$' "$INNGEST_CI_YML" || true)
assert "NIC-G1 row5: the one NIC-wait call site passes \${inngest_private_ip}, not a literal (calls $NG1_RAW_CALLS, templated $NG1_RAW_TEMPLATED)" \
  "(( NG1_RAW_CALLS == 1 && NG1_RAW_TEMPLATED == 1 ))"
NG1_RAW_LITERAL=$(grep -v '^[[:space:]]*#' "$INNGEST_CI_YML" | grep -c '10\.0\.1\.40' || true)
assert "NIC-G1 row5: no CODE line of cloud-init-inngest.yml hardcodes 10.0.1.40 (found $NG1_RAW_LITERAL)" \
  "(( NG1_RAW_LITERAL == 0 ))"

# Row 10 (raw .tf): the templatefile map for cloud-init-inngest.yml binds the key to the single
# definition, local.inngest_private_ip. Scoped to that map so the `locals` literal and every
# other root's map cannot satisfy it.
NG1_TF_MAP="$(awk '/templatefile\("\$\{path\.module\}\/cloud-init-inngest\.yml"/ { f = 1 } f { print } f && /^[[:space:]]*\}\), local\.inngest_rationale_strip/ { exit }' "$SCRIPT_DIR/inngest-host.tf")"
NG1_TF_MAP_LINES=$(printf '%s\n' "$NG1_TF_MAP" | grep -c . || true)
NG1_TF_KEY=$(printf '%s\n' "$NG1_TF_MAP" | grep -cE '^[[:space:]]*inngest_private_ip[[:space:]]*=' || true)
NG1_TF_BOUND=$(printf '%s\n' "$NG1_TF_MAP" | grep -cE '^[[:space:]]*inngest_private_ip[[:space:]]*=[[:space:]]*local\.inngest_private_ip[[:space:]]*$' || true)
assert "NIC-G1 row10: the cloud-init-inngest.yml map binds inngest_private_ip = local.inngest_private_ip exactly once (map $NG1_TF_MAP_LINES lines, key $NG1_TF_KEY, bound $NG1_TF_BOUND)" \
  "(( NG1_TF_MAP_LINES >= 20 && NG1_TF_KEY == 1 && NG1_TF_BOUND == 1 ))"

# The rendered rows below run against inngest-userdata-budget.sh's STUB variable map, whose
# inngest_private_ip is a hand-written literal. Nothing compared it to the Terraform local, so
# changing local.inngest_private_ip to 10.0.1.41 left all 15 rendered rows GREEN while the bytes
# that boot the host carried the other address -- and check.py's own OWN_IP then excluded the
# wrong one. Measured at review. Pin the two copies to each other.
NG1_TF_IP=$(grep -oE '^[[:space:]]*inngest_private_ip[[:space:]]*=[[:space:]]*"[0-9.]+"' "$SCRIPT_DIR/inngest-host.tf" \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
NG1_STUB_IP=$(grep -oE 'inngest_private_ip[[:space:]]*=[[:space:]]*"[0-9.]+"' "$SCRIPT_DIR/inngest-userdata-budget.sh" \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
assert "NIC-G1 row10b: the budget stub's inngest_private_ip equals local.inngest_private_ip (tf=${NG1_TF_IP:-none} stub=${NG1_STUB_IP:-none})" \
  "[[ -n \"\$NG1_TF_IP\" && \"\$NG1_TF_IP\" == \"\$NG1_STUB_IP\" ]]"

# EMIT/ROUTE LOCKSTEP (#8539, mirroring nic-wait-gate.test.sh for the web host). An emitted
# stage that matches no alert filter is not a smaller version of observability -- it is the
# silence the emit was built to end. And the inverse matters here too: these two stage names are
# REUSED verbatim from web-1, and the rule they match carries no host condition, so the inngest
# host inherits its routing. That inheritance is the intended behaviour and must not be silently
# broken by a future edit to either side. Anchored on the HCL tagged_event CONSTRUCT, so the
# rule file's own prose cannot satisfy it.
NG1_ALERTS="$SCRIPT_DIR/sentry/issue-alerts.tf"
assert "NIC-G1 route: the Sentry issue-alert config is present" "[[ -f \"\$NG1_ALERTS\" ]]"
for _stage in private_nic_timeout private_nic_probe_fault; do
  _n=$(grep -cE "tagged_event[[:space:]]*=[[:space:]]*\{[^}]*key[[:space:]]*=[[:space:]]*\"stage\"[^}]*value[[:space:]]*=[[:space:]]*\"${_stage}\"" "$NG1_ALERTS" || true)
  assert "NIC-G1 route: stage '$_stage' is a live tagged_event filter, not prose (found $_n)" \
    "(( _n >= 1 ))"
  _m=$(grep -cE "^[[:space:]]*emit ${_stage}( |$)" "$INNGEST_CI_YML" || true)
  assert "NIC-G1 route: stage '$_stage' is actually emitted by the inngest helper (found $_m)" \
    "(( _m >= 1 ))"
done

NG1_RAW_ASSERTIONS=$(( TOTAL - NG1_BEFORE ))
assert "NIC-G1 anti-vacuity (raw rows): the section ran its full inventory (expected 9, ran $NG1_RAW_ASSERTIONS)" \
  "(( NG1_RAW_ASSERTIONS == 9 ))"

# Rendered rows. Tool-gated on terraform (the render is terraform's own templatefile), so the
# block is bracketed into COND_ASSERTIONS per the contract at the top of this file.
_COND_BEFORE=$TOTAL
if command -v terraform >/dev/null 2>&1; then
  NG1_DIR="$(mktemp -d -t nicg1-XXXXXX)"
  trap 'rm -rf "$NG1_DIR"' EXIT
  NG1_RENDER="$NG1_DIR/rendered.yml"
  bash "$SCRIPT_DIR/inngest-userdata-budget.sh" "$NG1_RENDER" > "$NG1_DIR/budget.log" 2>&1 || true
  NG1_RENDER_BYTES=$(wc -c < "$NG1_RENDER" 2>/dev/null | tr -cd '0-9' || true)
  NG1_RENDER_BYTES=${NG1_RENDER_BYTES:-0}
  assert "NIC-G1 dispatch: the stripped render was produced ($NG1_RENDER_BYTES B)" \
    "(( NG1_RENDER_BYTES > 0 ))"
  # The checker emits KEY=VALUE facts (shell-safe tokens only); every assertion below reads one.
  cat > "$NG1_DIR/check.py" <<'PY'
import re, sys, yaml
EXPECTED_FALLBACK = (
    "[Match]\nDriver=virtio_net\nName=!eth0\n\n[Link]\nRequiredForOnline=no\n\n"
    "[Network]\nDHCP=ipv4\nLinkLocalAddressing=no\nIPv6AcceptRA=no\n\n"
    "[DHCPv4]\nUseMTU=yes\nUseDNS=no\nUseDomains=no\nUseHostname=no\nUseNTP=no\n"
    "SendHostname=no\nRouteMetric=1024\n"
)
OWN_IP = "10.0.1.40"
try:
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    d = {}
if not isinstance(d, dict):
    d = {}
rc = d.get("runcmd") or []
wf = d.get("write_files") or []
def text(x):
    if isinstance(x, list):
        return " ".join(str(y) for y in x)
    return str(x)
def code(t):
    return [l for l in t.split("\n") if l.strip() and not l.lstrip().startswith("#")]
SCRIPTS = {str(w.get("path", "")): str(w.get("content", ""))
           for w in wf if isinstance(w, dict)}
INVOKE = re.compile(r"(^|[\s;&|(])(/usr/local/bin/[A-Za-z0-9._-]+)(\s|$)")
def expand(t):
    seen, body = set(), [t]
    for l in t.split("\n"):
        for m in INVOKE.finditer(l):
            q = m.group(2)
            if q in SCRIPTS and q not in seen and q != "/usr/local/bin/soleur-inngest-nic-wait":
                seen.add(q)
                body.append(SCRIPTS[q])
    return "\n".join(body)
BOOTN = len(d.get("bootcmd") or [])
items = [expand(text(x)) for x in (d.get("bootcmd") or [])] + [expand(text(x)) for x in rc]
CALL = re.compile(r"(^|[\s;&|(])(/usr/local/bin/)?soleur-inngest-nic-wait(\s|$)")
RELOAD = re.compile(r"^\s*networkctl\s+reload(\s|$)")
DOCKER = re.compile(r"\bdocker\b(?:\s+--?[^\s]+(?:\s+[^\s-][^\s]*)?)*\s+(?:image\s+|manifest\s+)?(login|pull|push|inspect)\b(.*)")
PROBE = re.compile(r"(^|[\s;&|(`$]|/)(curl|wget|nc|ncat|netcat|ping|ping6|getent|nslookup|dig|host|openssl|redis-cli|psql|mysql|mongosh|skopeo|crane|podman|nerdctl|rsync|scp|sftp|telnet|socat|nmap|showmount|mount\.nfs)(\s|$)")
ADDR = re.compile(r"(?<![0-9.])10\.0\.[0-9]{1,3}\.[0-9]{1,3}(?![0-9])")
PUBLIC = re.compile(r"^(ghcr\.io|docker\.io|registry-1\.docker\.io|index\.docker\.io|quay\.io|public\.ecr\.aws)([/:].*)?$")
VARTGT = re.compile(r"\$\{?(ZOT[A-Z_]*|[A-Z_]*ZOT|[A-Z_]*REGISTRY[A-Z_]*|[A-Z_]*ENDPOINT|Z?IREF|[A-Z_]*PRIVATE[A-Z_]*|SDK_URL)\b")
VALUE_FLAGS = {"-u", "--username", "-p", "--password", "--config", "-c"}


def docker_target(rest):
    skip = False
    for tok in rest.split():
        if skip:
            skip = False
            continue
        if tok in VALUE_FLAGS:
            skip = True
            continue
        if tok.startswith("-"):
            continue
        return tok.strip("\"'")
    return ""
calls, reloads, uses, config_writes = [], [], [], []
scanned = 0
for i, t in enumerate(items):
    scanned += 1
    is_use = False
    for l in code(t):
        if CALL.search(l):
            calls.append((i, l.strip()))
            continue
        if RELOAD.search(l):
            reloads.append(i)
        m = DOCKER.search(l)
        if m and not PUBLIC.match(docker_target(m.group(2))):
            is_use = True
        if PROBE.search(l) and (any(a != OWN_IP for a in ADDR.findall(l))
                                or VARTGT.search(l)):
            is_use = True
    if is_use:
        uses.append(i)
    elif any(a != OWN_IP for a in ADDR.findall(t)):
        config_writes.append(i)
# report every position in runcmd space so the adjacency row is unchanged by the bootcmd scan
calls = [(i - BOOTN, l) for i, l in calls]
reloads = [i - BOOTN for i in reloads]
uses = [i - BOOTN for i in uses]
config_writes = [i - BOOTN for i in config_writes]
call_pos = calls[0][0] if calls else -1
first_use = uses[0] if uses else -1
out = {
    "ITEMS": len(items) - BOOTN,
    "SCANNED": scanned - BOOTN,
    "CALLS": len(calls),
    "CALL_POS": call_pos,
    "CALL_EXACT": int(len(calls) == 1 and calls[0][1] == "/usr/local/bin/soleur-inngest-nic-wait " + OWN_IP + " || true"),
    "RELOADS": len(reloads),
    "RELOAD_POS": reloads[0] if reloads else -1,
    "USES": len(uses),
    "FIRST_USE": first_use,
    "USES_BEFORE_CALL": sum(1 for u in uses if call_pos < 0 or u < call_pos),
    "FIRST_USE_IS_ZOT_LOGIN": int(first_use >= 0 and 'docker login "$ZOT_EP"' in items[first_use]),
    "CONFIG_WRITES_BEFORE_CALL": sum(1 for c in config_writes if 0 <= call_pos and c < call_pos),
}
# Everything that can change what networkd does. /run and /usr/lib outrank /etc for the same
# basename, a `.network.d/*.conf` drop-in overrides the parent wholesale, and a `.link`
# renames the very link the fallback's [Match] is written against.
NETD = re.compile(r"^/(etc|run|usr/lib)/systemd/network/.+")
netd_all = [str(w.get("path", "")) for w in wf
            if isinstance(w, dict) and NETD.match(str(w.get("path", "")))]
nets = [w for w in wf if isinstance(w, dict)
        and re.match(r"^/etc/systemd/network/[^/]+\.network$", str(w.get("path", "")))]
netd_other = [q for q in netd_all
              if q != "/etc/systemd/network/99-soleur-private-fallback.network"]
out["NETWORK_FILES"] = len(nets)
out["NETD_OTHER"] = len(netd_other)
fb = nets[0] if len(nets) == 1 else {}
base = str(fb.get("path", "")).rsplit("/", 1)[-1]
out["FB_NAME_OK"] = int(base == "99-soleur-private-fallback.network")
out["FB_OWNER"] = str(fb.get("owner", "none")).replace(" ", "_") or "none"
out["FB_MODE"] = str(fb.get("permissions", "none")) or "none"
content = str(fb.get("content", ""))
match, sect = [], None
for l in content.split("\n"):
    s = l.strip()
    if s.startswith("[") and s.endswith("]"):
        sect = s
        continue
    if sect == "[Match]" and s:
        match.append(s)
out["MATCH_OK"] = int(match == ["Driver=virtio_net", "Name=!eth0"])
out["FB_BYTES_EQ"] = int(content == EXPECTED_FALLBACK)
helpers = [w for w in wf if isinstance(w, dict) and w.get("path") == "/usr/local/bin/soleur-inngest-nic-wait"]
out["HELPERS"] = len(helpers)
hp = helpers[0] if len(helpers) == 1 else {}
out["HELPER_OWNER"] = str(hp.get("owner", "none")).replace(" ", "_") or "none"
out["HELPER_MODE"] = str(hp.get("permissions", "none")) or "none"
for k, v in out.items():
    print("%s=%s" % (k, v))
PY
  declare -A NG1=()
  while IFS='=' read -r _k _v; do
    if [[ "$_k" =~ ^[A-Z_]+$ ]]; then NG1[$_k]="$_v"; fi
  done < <(python3 "$NG1_DIR/check.py" "$NG1_RENDER" 2>"$NG1_DIR/check.err" || true)
  NG1_ITEMS=${NG1[ITEMS]:-0};           NG1_SCANNED=${NG1[SCANNED]:--1}
  NG1_CALLS=${NG1[CALLS]:-0};           NG1_CALL_POS=${NG1[CALL_POS]:--1}
  NG1_CALL_EXACT=${NG1[CALL_EXACT]:-0}
  NG1_RELOADS=${NG1[RELOADS]:-0};       NG1_RELOAD_POS=${NG1[RELOAD_POS]:--1}
  NG1_USES=${NG1[USES]:-0};             NG1_FIRST_USE_POS=${NG1[FIRST_USE]:--1}
  NG1_USES_BEFORE_CALL=${NG1[USES_BEFORE_CALL]:--1}
  NG1_FIRST_USE_IS_ZOT=${NG1[FIRST_USE_IS_ZOT_LOGIN]:-0}
  NG1_CONFIG_WRITES=${NG1[CONFIG_WRITES_BEFORE_CALL]:-0}
  NG1_NETWORK_FILES=${NG1[NETWORK_FILES]:-0}; NG1_FB_NAME_OK=${NG1[FB_NAME_OK]:-0}
  NG1_NETD_OTHER=${NG1[NETD_OTHER]:--1}
  NG1_FB_OWNER=${NG1[FB_OWNER]:-none};  NG1_FB_MODE=${NG1[FB_MODE]:-none}
  NG1_MATCH_OK=${NG1[MATCH_OK]:-0};     NG1_FB_BYTES_EQ=${NG1[FB_BYTES_EQ]:-0}
  NG1_HELPERS=${NG1[HELPERS]:-0}
  NG1_HELPER_OWNER=${NG1[HELPER_OWNER]:-none}; NG1_HELPER_MODE=${NG1[HELPER_MODE]:-none}

  # Row 9 / own dispatch: an empty runcmd is a broken instrument, never a clean result. Every
  # item must have gone through the derived-set scan.
  assert "NIC-G1 anti-vacuity: $NG1_ITEMS runcmd items were scanned (must be > 0)" \
    "(( NG1_ITEMS > 0 ))"
  # The fallback is only the fallback if nothing else in write_files can outrank or override it.
  # /run and /usr/lib beat /etc for the same basename, a .network.d/*.conf drop-in overrides the
  # parent wholesale, and a .link renames the link the [Match] targets. All five shapes were
  # GREEN before this row (review, measured).
  assert "NIC-G1 row7b: write_files delivers NO other networkd file that could shadow the fallback (found $NG1_NETD_OTHER)" \
    "(( NG1_NETD_OTHER == 0 ))"
  # Row 4: exactly one NIC-wait call, and it is the exact rendered construct.
  assert "NIC-G1 row4: runcmd carries exactly ONE NIC-wait call (found $NG1_CALLS)" \
    "(( NG1_CALLS == 1 ))"
  assert "NIC-G1 row4: the call renders as '/usr/local/bin/soleur-inngest-nic-wait 10.0.1.40 || true'" \
    "(( NG1_CALL_EXACT == 1 ))"
  # Row 3: presence of the reload (a delete, distinct from the reorder in row 2).
  assert "NIC-G1 row3: runcmd carries exactly ONE networkctl reload item (found $NG1_RELOADS)" \
    "(( NG1_RELOADS == 1 ))"
  # Row 2: order of the reload against the call, by list position.
  assert "NIC-G1 row2: networkctl reload (pos $NG1_RELOAD_POS) runs BEFORE the NIC-wait call (pos $NG1_CALL_POS)" \
    "(( NG1_RELOAD_POS >= 0 && NG1_RELOAD_POS < NG1_CALL_POS ))"
  # Row 1: placement, by list position. THE ORDER COMPARISON the battery's harness row neuters.
  assert "NIC-G1 row1: the NIC-wait call (pos $NG1_CALL_POS) sits immediately before the first private-net use (pos $NG1_FIRST_USE_POS)" \
    "(( NG1_CALL_POS >= 0 && NG1_CALL_POS + 1 == NG1_FIRST_USE_POS ))"
  # Row 8: the derived set. No private-net ACTION may precede the call.
  assert "NIC-G1 row8: no private-net action precedes the NIC-wait call ($NG1_USES uses derived, $NG1_USES_BEFORE_CALL before the call)" \
    "(( NG1_USES > 0 && NG1_USES_BEFORE_CALL == 0 ))"
  assert "NIC-G1 AC2: the first private-net use is the zot login (docker login \"\$ZOT_EP\")" \
    "(( NG1_FIRST_USE_IS_ZOT == 1 ))"
  # Must-PASS (ii), made non-vacuous: the endpoint-naming config writes DO precede the call and
  # were scanned and NOT scored as uses. If this count drops to 0 the exclusion is untested.
  assert "NIC-G1 must-PASS: >= 2 endpoint-naming config writes precede the call and are not uses (found $NG1_CONFIG_WRITES)" \
    "(( NG1_CONFIG_WRITES >= 2 ))"
  # Rows 6, 7, 11 and the write_files mode/owner asserts.
  assert "NIC-G1 row7: exactly one networkd file in write_files, named 99-soleur-private-fallback.network (sorts after 10-netplan-*) (files $NG1_NETWORK_FILES)" \
    "(( NG1_NETWORK_FILES == 1 && NG1_FB_NAME_OK == 1 ))"
  assert "NIC-G1 row6: the fallback [Match] is exactly Driver=virtio_net + Name=!eth0" \
    "(( NG1_MATCH_OK == 1 ))"
  assert "NIC-G1 row11: the fallback content equals the Phase 2 block byte-for-byte" \
    "(( NG1_FB_BYTES_EQ == 1 ))"
  assert "NIC-G1 write_files: the fallback .network is root:root 0644 (got $NG1_FB_OWNER $NG1_FB_MODE)" \
    "[[ \"\$NG1_FB_OWNER\" == 'root:root' && \"\$NG1_FB_MODE\" == '0644' ]]"
  assert "NIC-G1 write_files: /usr/local/bin/soleur-inngest-nic-wait is delivered once, root:root 0755 (count $NG1_HELPERS, got $NG1_HELPER_OWNER $NG1_HELPER_MODE)" \
    "(( NG1_HELPERS == 1 )) && [[ \"\$NG1_HELPER_OWNER\" == 'root:root' && \"\$NG1_HELPER_MODE\" == '0755' ]]"

  NG1_RENDER_ASSERTIONS=$(( TOTAL - _COND_BEFORE ))
  assert "NIC-G1 anti-vacuity (rendered rows): the section ran its full inventory (expected 16, ran $NG1_RENDER_ASSERTIONS)" \
    "(( NG1_RENDER_ASSERTIONS == 16 ))"
  rm -rf "$NG1_DIR"
else
  echo "  SKIP: terraform not installed (NIC-G1 rendered rows skipped — CI deploy-script-tests provides it via setup-terraform)"
fi
COND_ASSERTIONS=$(( COND_ASSERTIONS + TOTAL - _COND_BEFORE ))

# =======================================================================================
# GUARD 4 (#8036 item 1d) — a zot miss is TERMINAL and LOUD on the dedicated inngest host
# =======================================================================================
# PROPERTY. On any bootstrap-pull failure (a zot miss of any rc, a timeout, or no endpoint baked)
# the host emits `inngest_pull_fatal` to Better Stack (phone-home) AND to Sentry at level FATAL
# (soleur-boot-emit) BEFORE it exits non-zero; the exit ends the WHOLE runcmd (cloud-init
# shellify()s every item into ONE /bin/sh, so an `exit` in a subshell would let the next line
# run); and no further `docker pull`/`docker create` is attempted — there is no second registry.
# A phone-home that fails must not cost the Sentry emit (both calls are `|| true` under set -e).
#
# WHY EXECUTED, NOT GREPPED. The property is about ORDER and LIFETIME. A grep sees that an emit
# line and an `exit` line exist; it cannot see the emit placed after the exit, an exit inside a
# subshell whose status is swallowed, or a fall-through into `docker create`. So the pull item is
# taken from the TERRAFORM-RENDERED + STRIPPED user_data (inngest-userdata-budget.sh — the bytes
# that reach the host), sliced from the item's first line through `docker create --name
# soleur-inngest-bootstrap-extract`, path-rewritten into a scratch root, followed by a sentinel
# line standing for "any later runcmd byte", and run under /bin/sh with stubbed docker/timeout/
# soleur-boot-emit/phone-home/redact that write one call log. The pull item is the LAST runcmd
# item, so the sentinel is the honest stand-in for the rest of the runcmd shell.
#
# The colocated web-host block (cloud-init.yml, gated off by web_colocate_inngest=false) is the
# web template's own suite's concern; this section covers the dedicated host.
_COND_BEFORE=$TOTAL
if command -v terraform >/dev/null 2>&1; then
  echo ""
  echo "--- Guard 4 (#8036 1d): a zot miss is terminal and loud (executed rendered pull item) ---"
  G4_DIR="$(mktemp -d -t g4pull-XXXXXX)"
  G4_RENDER="$G4_DIR/rendered.yml"
  G4_FX="$G4_DIR/fx"
  bash "$SCRIPT_DIR/inngest-userdata-budget.sh" "$G4_RENDER" > "$G4_DIR/budget.log" 2>&1 || true
  # Slice + rewrite. Prints G4_ITEMS=<n> G4_SLICE_LINES=<n>; writes item.sh only on a clean slice.
  G4_FACTS="$(python3 - "$G4_RENDER" "$G4_DIR" "$G4_FX" 2>"$G4_DIR/slice.err" <<'PY' || true
import re, sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    d = {}
rc = (d.get("runcmd") or []) if isinstance(d, dict) else []
items = [x for x in rc if isinstance(x, str)
         and "soleur-inngest-bootstrap-extract" in x and re.search(r"^\s*IREF=", x, re.M)]
print("G4_ITEMS=%d" % len(items))
if len(items) != 1:
    print("G4_SLICE_LINES=0"); sys.exit(0)
lines = items[0].split("\n")
end = next((i for i, l in enumerate(lines)
            if re.match(r'^\s*docker create --name soleur-inngest-bootstrap-extract ', l)), -1)
if end < 0:
    print("G4_SLICE_LINES=0"); sys.exit(0)
fx = sys.argv[3]
body = "\n".join(lines[:end + 1]) + "\n"
for a, b in (("/usr/local/bin/", fx + "/bin/"), ("/etc/default/", fx + "/etc/"),
             ("/var/log/", fx + "/log/"), ("/run/", fx + "/run/")):
    body = body.replace(a, b)
# tee, not an append redirect: the fixture-relative scanner cannot see a heredoc inside $(...)
# and would read a redirect in this Python string as a shell write.
body += 'echo RUNCMD_CONTINUED | tee -a "$G4_LOG" >/dev/null\n'
open(sys.argv[2] + "/item.sh", "w").write(body)
print("G4_SLICE_LINES=%d" % (end + 1))
PY
)"
  G4_ITEMS="$(sed -n 's/^G4_ITEMS=//p' <<<"$G4_FACTS")"; G4_ITEMS="${G4_ITEMS:-0}"
  G4_SLICE_LINES="$(sed -n 's/^G4_SLICE_LINES=//p' <<<"$G4_FACTS")"; G4_SLICE_LINES="${G4_SLICE_LINES:-0}"
  # The shell cloud-init uses. `dash` where present (Ubuntu's /bin/sh), else sh.
  G4_SH="$(command -v dash || command -v sh)"
  mkdir -p "$G4_FX/bin"
  cat > "$G4_FX/bin/docker" <<'STUB'
#!/bin/sh
printf 'docker %s\n' "$*" >> "$G4_LOG"
case "$1" in pull) exit "${G4_PULL_RC:-0}" ;; esac
exit 0
STUB
  cat > "$G4_FX/bin/timeout" <<'STUB'
#!/bin/sh
shift
exec "$@"
STUB
  cat > "$G4_FX/bin/soleur-boot-emit" <<'STUB'
#!/bin/sh
printf 'emit %s\n' "$*" >> "$G4_LOG"
exit 0
STUB
  cat > "$G4_FX/bin/inngest-boot-phone-home.sh" <<'STUB'
#!/bin/sh
printf 'phone %s\n' "$*" >> "$G4_LOG"
[ -n "${G4_PH_FAIL:-}" ] && [ "$1" = "$G4_PH_FAIL" ] && exit 3
exit 0
STUB
  printf '#!/bin/sh\ncat\n' > "$G4_FX/bin/inngest-redact.sh"
  chmod +x "$G4_FX/bin/"*
  # g4_run <scenario> <endpoint> <pull rc> <phone-home stage that fails, or ''>; echoes the rc.
  # env -i: the item sources files and reads variables; nothing from this shell may leak in.
  g4_run() {
    local n="$1"
    rm -rf "$G4_FX/run" "$G4_FX/etc" "$G4_FX/log" "$G4_FX/tmp"
    mkdir -p "$G4_FX/run" "$G4_FX/etc" "$G4_FX/log" "$G4_FX/tmp"
    : > "$G4_FX/run/soleur-inngest-doppler.ok"
    printf 'ZOT_REGISTRY_ENDPOINT=%s\nZOT_PULL_USER=zu\nZOT_PULL_TOKEN=zt\n' "$2" > "$G4_FX/etc/soleur-zot-read"
    : > "$G4_DIR/$n.log"
    ( cd "$G4_DIR" && env -i PATH="$G4_FX/bin:$PATH" HOME="$G4_DIR" TMPDIR="$G4_FX/tmp" \
        G4_LOG="$G4_DIR/$n.log" G4_PULL_RC="$3" G4_PH_FAIL="$4" "$G4_SH" "$G4_DIR/item.sh" ) \
      > "$G4_DIR/$n.out" 2>&1
    echo $?
  }
  g4_has() { grep -qE "$2" "$G4_DIR/$1.log"; }
  g4_count() { grep -cE "$2" "$G4_DIR/$1.log" || true; }
  # line number of the first match in a scenario's call log (empty when absent)
  g4_at() { grep -nE "$2" "$G4_DIR/$1.log" | head -1 | cut -d: -f1 || true; }
  # after the first failed pull, count further pull/create calls
  g4_after_pull() {
    awk 'seen && /^docker (pull|create)( |$)/ { n++ } /^docker pull / && !seen { seen = 1 } END { print n + 0 }' "$G4_DIR/$1.log"
  }

  assert "G4 dispatch: exactly ONE rendered runcmd item carries the bootstrap pull (found $G4_ITEMS)" \
    "(( G4_ITEMS == 1 ))"
  assert "G4 dispatch: the item was sliced through its docker create (>= 20 lines, found $G4_SLICE_LINES)" \
    "(( G4_SLICE_LINES >= 20 )) && [[ -s '$G4_DIR/item.sh' ]]"

  ZEP=10.0.1.30:5000
  # --- hit (the must-PASS arm): served by zot, no fatal, extraction proceeds ---------------------
  G4_HIT_RC="$(g4_run hit "$ZEP" 0 '')"
  assert "G4 harness: the stubs are live — the hit scenario logged exactly ONE docker pull (found $(g4_count hit '^docker pull '))" \
    "(( \$(g4_count hit '^docker pull ') == 1 ))"
  assert "G4 hit: exits 0 and the runcmd continues past the item (rc=$G4_HIT_RC)" \
    "[[ '$G4_HIT_RC' == 0 ]] && g4_has hit '^RUNCMD_CONTINUED$'"
  assert "G4 hit: emits inngest_zot info on both channels and NO inngest_pull_fatal" \
    "g4_has hit '^phone inngest_zot ' && g4_has hit '^emit inngest_zot info ' && ! g4_has hit 'inngest_pull_fatal'"
  assert "G4 hit: extraction proceeds on the ZOT ref (docker create + the INNGEST_BOOTSTRAP_IMAGE record both name $ZEP/...)" \
    "g4_has hit '^docker create --name soleur-inngest-bootstrap-extract $ZEP/jikig-ai/soleur-inngest-bootstrap:v[0-9.]+@sha256:[0-9a-f]{64}$' && grep -qE '^INNGEST_BOOTSTRAP_IMAGE=$ZEP/' '$G4_FX/etc/soleur-inngest-image'"

  # --- miss: rc=1 --------------------------------------------------------------------------------
  G4_MISS_RC="$(g4_run miss "$ZEP" 1 '')"
  G4_M_PULL="$(g4_at miss '^docker pull ')"
  G4_M_PH="$(g4_at miss '^phone inngest_pull_fatal ')"
  G4_M_EMIT="$(g4_at miss '^emit inngest_pull_fatal fatal rc=1$')"
  assert "G4 miss: phone-home inngest_pull_fatal is sent (the Better Stack channel)" \
    "[[ -n '$G4_M_PH' ]]"
  assert "G4 miss: soleur-boot-emit inngest_pull_fatal fatal rc=1 is sent (the Sentry channel, level FATAL)" \
    "[[ -n '$G4_M_EMIT' ]]"
  assert "G4 miss: order — the failed pull, then the phone-home, then the Sentry emit (pull $G4_M_PULL, phone $G4_M_PH, emit $G4_M_EMIT)" \
    "[[ -n '$G4_M_PULL' && -n '$G4_M_PH' && -n '$G4_M_EMIT' ]] && (( G4_M_PULL < G4_M_PH && G4_M_PH < G4_M_EMIT ))"
  assert "G4 miss: the item exits NON-ZERO (rc=$G4_MISS_RC)" \
    "[[ '$G4_MISS_RC' =~ ^[0-9]+$ ]] && (( G4_MISS_RC != 0 ))"
  assert "G4 miss: no docker pull/create after the failed pull (no second registry; found $(g4_after_pull miss))" \
    "(( \$(g4_after_pull miss) == 0 ))"
  assert "G4 miss: the miss arm ends the WHOLE runcmd (nothing after the item runs, no image record written)" \
    "! g4_has miss '^RUNCMD_CONTINUED$' && [[ ! -e '$G4_FX/etc/soleur-inngest-image' ]]"

  # --- timeout: rc=124 takes the same path -------------------------------------------------------
  G4_TO_RC="$(g4_run timeout "$ZEP" 124 '')"
  assert "G4 timeout: rc=124 emits inngest_pull_fatal fatal rc=124, exits non-zero and ends the runcmd (rc=$G4_TO_RC)" \
    "g4_has timeout '^emit inngest_pull_fatal fatal rc=124$' && (( G4_TO_RC != 0 )) && ! g4_has timeout '^RUNCMD_CONTINUED$'"

  # --- phone-home fails: the Sentry emit must still happen ---------------------------------------
  G4_PH_RC="$(g4_run phfail "$ZEP" 1 inngest_pull_fatal)"
  assert "G4 phone-home-fails: the Sentry emit inngest_pull_fatal fatal still runs when the phone-home exits non-zero" \
    "g4_has phfail '^phone inngest_pull_fatal ' && g4_has phfail '^emit inngest_pull_fatal fatal rc=1$'"
  assert "G4 phone-home-fails: the item still exits non-zero and the runcmd ends (rc=$G4_PH_RC)" \
    "(( G4_PH_RC != 0 )) && ! g4_has phfail '^RUNCMD_CONTINUED$'"

  # --- no endpoint baked: fatal, never a pull ----------------------------------------------------
  G4_NE_RC="$(g4_run noep '' 0 '')"
  assert "G4 noendpoint: phone-home + soleur-boot-emit inngest_pull_fatal fatal rc=noendpoint" \
    "g4_has noep '^phone inngest_pull_fatal ' && g4_has noep '^emit inngest_pull_fatal fatal rc=noendpoint$'"
  assert "G4 noendpoint: exits non-zero with NO docker pull/create at all and the runcmd ends (rc=$G4_NE_RC)" \
    "(( G4_NE_RC != 0 )) && (( \$(g4_count noep '^docker (pull|create) ') == 0 )) && ! g4_has noep '^RUNCMD_CONTINUED$'"

  G4_ASSERTIONS=$(( TOTAL - _COND_BEFORE ))
  assert "G4 anti-vacuity: the section ran its full inventory (expected 17, ran $G4_ASSERTIONS)" \
    "(( G4_ASSERTIONS == 17 ))"
  rm -rf "$G4_DIR"
else
  echo "  SKIP: terraform not installed (Guard 4 executed rows skipped — CI deploy-script-tests provides it via setup-terraform)"
fi
COND_ASSERTIONS=$(( COND_ASSERTIONS + TOTAL - _COND_BEFORE ))

# ASSERTION-COUNT FLOOR (#7695). The five SECTION floors live INSIDE their sections, so deleting
# a whole section deletes its own floor: a vacuity audit removed the entire Guard A block and this
# suite reported `149/149 passed`, exit 0 -- and removed Guard A AND Guard D for `137/137 passed`.
# The zot-pull mutation battery does not backstop it either (it still reported 9/9 killed with
# Guard A gone). Reported with printf + exit (ADR-193), never through `assert`.
#
# THE FLOOR COUNTS UNCONDITIONAL ASSERTIONS ONLY. It was a flat `TOTAL >= 163`, which is the
# environment-varying-count defect this same PR fixed in Guard B row6 and then reintroduced here:
# four blocks in this file are gated on a tool being installed (`dash`, `visudo`, `terraform`,
# and `cloud-init` nested inside terraform), so TOTAL is a property of the HOST as much as of the
# suite. Measured: 164 with the full toolchain, 126 with terraform hidden and nothing else
# changed, 124 in /ship Check 10's bwrap sandbox (no terraform, no visudo) -- all three green
# suites, two of them failing a flat floor for a reason that has nothing to do with the code.
# Subtracting the measured conditional deltas makes the floor invariant WITHOUT hardcoding a
# per-tool number for each arm, which would only relocate the same defect.
# #8539: re-measured from a green run after NIC-G1 landed (134 unconditional before it, + its 4
# raw-source asserts = 138; the rendered NIC-G1 rows are terraform-gated and counted in
# COND_ASSERTIONS). The prior 123 had drifted 11 below the measured count.
# #8036 1d: 144 -> 153, re-measured from a green run (Guard 1 grew 50 -> 59; the executed Guard 4
# rows are terraform-gated and counted in COND_ASSERTIONS, like the rendered NIC-G1 rows).
UNCONDITIONAL_ASSERTIONS=$(( TOTAL - COND_ASSERTIONS ))
BOOTSTRAP_MIN_ASSERTIONS=153
if [[ "$UNCONDITIONAL_ASSERTIONS" -lt "$BOOTSTRAP_MIN_ASSERTIONS" ]]; then
  printf 'FAIL: assertion-count floor: only %s unconditional assertions ran (%s total, %s from tool-gated blocks), expected >= %s — a block was skipped or emptied.\n' \
    "$UNCONDITIONAL_ASSERTIONS" "$TOTAL" "$COND_ASSERTIONS" "$BOOTSTRAP_MIN_ASSERTIONS" >&2
  exit 1
fi

if command -v terraform >/dev/null 2>&1; then
  BOOTSTRAP_GATED=ran
elif [[ -n "${CI:-}" ]]; then
  printf 'FAIL: terraform is absent under CI, so the rendered NIC-G1 and executed Guard 4 inventories did not run. This job pins the toolchain (setup-terraform); its absence is a broken runner, not a skip — and "OK" here would certify 33 assertions that never executed.\n' >&2
  exit 1
else
  BOOTSTRAP_GATED=SKIPPED-no-terraform
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "OK"
# Machine-readable success sentinel, printed ONLY on a fully green run and NOWHERE else in this
# file. `/ship` preflight Check 10 substring-matches the plan's `expected_output` against this
# suite's stdout, and every candidate token already present fails one of two ways: `163/163
# passed` is host-dependent (163 with the full toolchain, 125 without terraform), and a bare `OK`
# is not success-specific -- measured, it appears twice in a FAILING run ("composite form OK" in
# a section header, and inside GHCR_READ_TOKEN). Keep this line unique and keep it last.
echo "BOOTSTRAP_SUITE_OK unconditional=$UNCONDITIONAL_ASSERTIONS floor=$BOOTSTRAP_MIN_ASSERTIONS total=$TOTAL rendered=$BOOTSTRAP_GATED"
