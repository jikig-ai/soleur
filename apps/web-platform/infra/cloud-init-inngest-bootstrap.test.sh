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
# #6122: the pin now lives in the IREF assignment (zot-primary + GHCR fallback); the
# three consumers (pull/create/inspect) reference "$IREF".
assert "IREF pin for soleur-inngest-bootstrap:vX.Y.Z exists" \
  "grep -qE '^[[:space:]]+IREF=ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' '$CLOUD_INIT'"
assert "inngest image pulled via resolved IREF" \
  "grep -qF 'docker pull \"\$IREF\"' '$CLOUD_INIT'"

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
    printf 'templatefile("%s", { image_name="i", fail2ban_sshd_local_b64="x", host_scripts_content_hash="h", tunnel_token="TT_SENTINEL_6425", webhook_deploy_secret="w", doppler_token="d", sentry_dsn="s", resend_api_key="r", ghcr_read_user="u", ghcr_read_token="g", ci_ssh_public_key_openssh="k", workspaces_volume_id="v", registry_endpoint="reg", web_colocate_inngest=%s, web_tunnel_connector=%s, host_name="soleur-web-platform", private_ip="10.0.1.10", web_probes_token="t", expected_ip="10.0.1.10", web_host_key="hk", zot_probe_repo="zr", betterstack_ingest_url="bs", soleur_doppler_token_env_b64="RE9QUExFUl9UT0tFTj1k" })\n' \
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
# PROPERTY. The dedicated inngest host resolves its bootstrap image from zot whenever zot is
# configured and serving that digest; every registry outcome is reported off-box; and no
# registry outcome yields a boot worse than today's GHCR-only path.
#
# ASSEMBLY. The chokepoint is the single ref-resolution region that computes the effective
# ref before `pre-oci-pull`. Every consumer of the image ref DOWNSTREAM of that point must
# read the resolved value rather than re-derive it. The plan named three consumers (pull,
# extract container, /etc/default record); the file carries a FOURTH — `docker inspect
# "$IREF"`, which sources INNGEST_CLI_VERSION/SHA256 from the image env. The guard quantifies
# over all FOUR, because a second consumer re-deriving the GHCR literal is precisely how a
# "zot-primary" change ships while still pulling from GHCR. Enumerating the CLASS (every site
# that consumes the ref) rather than the plan's example list is the point.
#
# WHY THE COUNT AND THE SET ARE BOTH ASSERTED. `GHCR_LITERAL_COUNT == 1` is blind to a rename
# (a consumer switched from "$IREF" to "$SOMETHING_ELSE" keeps the count at 1), so the four
# per-consumer greps assert the SET. Neither alone is sufficient.
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
L_PRE=$(zg_line 'inngest-boot-phone-home\.sh pre-oci-pull')
L_IPULL=$(zg_line 'docker pull "\$IREF"')
L_DAEMON=$(zg_line 'insecure-registries')
# Anchored on the RESTART ITSELF, not on the runcmd-item form it happened to have. The restart
# was a bare `- systemctl restart docker` item until it was wrapped to report its own failure
# (it had no off-box channel: `cloud-init` is not in vector.toml's Source-4 allowlist and Vector
# ships inside the image this boot has not pulled). A `^\s*- ` anchor pinned the YAML shape
# rather than the command, so making the restart OBSERVABLE reddened the guard — the anchor
# tracked the wrong thing. `^\s*(- )?(if )?systemctl restart docker` accepts either form and
# still cannot be satisfied by a comment.
L_DOCKER_RESTART=$(zg_line '^[[:space:]]*(- )?(if )?systemctl restart docker')

assert "Row1 offsets: the GHCR seed assignment was found" "[[ -n '$L_IREF_SEED' ]]"
assert "Row1 offsets: the zot ref assignment (ZIREF=) was found" "[[ -n '$L_ZIREF' ]]"
assert "Row1 offsets: the zot leg's docker pull was found" "[[ -n '$L_ZPULL' ]]"
assert "Row1 offsets: the pre-oci-pull emit was found" "[[ -n '$L_PRE' ]]"
assert "Row1 offsets: the effective docker pull \"\\\$IREF\" was found" "[[ -n '$L_IPULL' ]]"

# --- Row 1: zot is PRIMARY — the GHCR ref must not be attempted first ----------------------
# The seed assignment must precede the zot leg (so the fallback is a single atomic
# reassignment, never a re-derivation), the zot pull must precede `pre-oci-pull` (the plan's
# "resolve the effective ref ONCE, before pre-oci-pull"), and the effective pull must follow
# the resolution. Swapping the two legs inverts all three.
# EVERY arithmetic comparison is guarded on BOTH operands being non-empty. bash arithmetic
# coerces an empty string to 0, so a bare `(( L_ZPULL < L_PRE ))` with an unmatched L_ZPULL
# evaluates `0 < 583` and reports PASS — a guard that certifies an ordering between a line
# that exists and one that does not. Measured on this very suite's first RED run: two
# ordering rows passed while the code they order had not been written yet.
assert "Row1: the GHCR ref is SEEDED before the zot leg runs (atomic fallback, not a re-derivation)" \
  "[[ -n '$L_IREF_SEED' && -n '$L_ZPULL' ]] && (( L_IREF_SEED < L_ZPULL ))"
assert "Row1: the zot leg is attempted BEFORE pre-oci-pull (zot-primary, not GHCR-first)" \
  "[[ -n '$L_ZPULL' && -n '$L_PRE' ]] && (( L_ZPULL < L_PRE ))"
assert "Row1: the effective pull runs AFTER the resolution region" \
  "[[ -n '$L_PRE' && -n '$L_IPULL' ]] && (( L_PRE < L_IPULL ))"
assert "Row1: the zot ref is ASSIGNED before it is pulled" \
  "[[ -n '$L_ZIREF' && -n '$L_ZPULL' ]] && (( L_ZIREF < L_ZPULL ))"

# --- Row 2: the digest pin governs BOTH legs ----------------------------------------------
# `crane copy` is digest-preserving, so the SAME @sha256 resolves on both registries. A
# mutable-tag zot ref would hand a root-executed shell script's identity back to whoever can
# re-point the tag — the exact control the GHCR leg's pin exists to provide.
ZG_GHCR_REF=$(grep -oE 'ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' "$DED_CODE_FILE" | head -1 || true)
ZG_GHCR_DIGEST="${ZG_GHCR_REF##*@}"
ZG_ZOT_LINE=$(grep -E '^[[:space:]]*ZIREF=' "$DED_CODE_FILE" | head -1 || true)
ZG_ZOT_DIGEST=$(grep -oE 'sha256:[0-9a-f]{64}' <<<"$ZG_ZOT_LINE" | head -1 || true)
assert "Row2: the GHCR leg carries a full sha256 digest pin" \
  "[[ '$ZG_GHCR_DIGEST' =~ ^sha256:[0-9a-f]{64}$ ]]"
assert "Row2: the zot leg carries a full sha256 digest pin (no mutable-tag form)" \
  "[[ '$ZG_ZOT_DIGEST' =~ ^sha256:[0-9a-f]{64}$ ]]"
assert "Row2: both legs pin the SAME digest (crane copy is digest-preserving)" \
  "[[ -n '$ZG_ZOT_DIGEST' && '$ZG_ZOT_DIGEST' == '$ZG_GHCR_DIGEST' ]]"

# --- Row 3: every registry outcome is reported off-box ------------------------------------
# This host has NO `soleur-boot-emit` (grep: zero occurrences) — that emitter is delivered by
# the WEB host's host-script bundle. Its only channel is inngest-boot-phone-home.sh, whose
# signature is `<stage> [detail]` with NO severity argument, so the STAGE NAME carries the
# whole signal. The names match the web host's (`inngest_zot`, `inngest_ghcr_fallback`) — but
# that does NOT mean one query covers both, and an earlier draft of this comment said it did:
# `soleur-boot-emit` POSTs to Sentry only, this emitter to Better Stack only, so no single
# query in either system sees both hosts.
assert "Row3: a zot HIT emits inngest_zot" \
  "grep -qF 'inngest-boot-phone-home.sh inngest_zot' '$DED_CODE_FILE'"
assert "Row3: the zot->GHCR flip emits inngest_ghcr_fallback (the fallback-rate signal)" \
  "grep -qF 'inngest-boot-phone-home.sh inngest_ghcr_fallback' '$DED_CODE_FILE'"
L_ZOTHIT=$(zg_line 'inngest-boot-phone-home\.sh inngest_zot')
L_FALLBACK=$(zg_line 'inngest-boot-phone-home\.sh inngest_ghcr_fallback')
assert "Row3: both registry-outcome emits sit INSIDE the resolution region (after the zot pull, before pre-oci-pull)" \
  "[[ -n '$L_ZOTHIT' && -n '$L_FALLBACK' && -n '$L_ZPULL' && -n '$L_PRE' ]] && (( L_ZPULL < L_ZOTHIT && L_ZOTHIT < L_PRE && L_ZPULL < L_FALLBACK && L_FALLBACK < L_PRE ))"
assert "Row3: the hit and the flip are DIFFERENT emit sites (one line cannot report both outcomes)" \
  "[[ '$L_ZOTHIT' != '$L_FALLBACK' ]]"

# --- Row 4: one resolution, every consumer follows it -------------------------------------
# OCCURRENCES, not lines. `grep -c` counts matching LINES, so a second literal appended to the
# same line kept this at 1 and the whole "one resolution, every consumer follows it" property
# was evadable by a one-line edit. Measured: two literals on one line -> grep -c returns 1.
ZG_GHCR_LITERALS=$(grep -oE 'ghcr\.io/jikig-ai/soleur-inngest-bootstrap' "$DED_CODE_FILE" | wc -l || true)
assert "Row4: exactly ONE GHCR literal survives comment-stripping (the IREF seed); found $ZG_GHCR_LITERALS" \
  "(( ZG_GHCR_LITERALS == 1 ))"
assert "Row4: consumer 1/4 — the pull reads \$IREF" \
  "grep -qF 'docker pull \"\$IREF\"' '$DED_CODE_FILE'"
assert "Row4: consumer 2/4 — the extract container reads \$IREF" \
  "grep -qF 'docker create --name soleur-inngest-bootstrap-extract \"\$IREF\"' '$DED_CODE_FILE'"
assert "Row4: consumer 3/4 — /etc/default/soleur-inngest-image records \$IREF" \
  "grep -qE 'INNGEST_BOOTSTRAP_IMAGE=%s.*\"\\\$IREF\".*/etc/default/soleur-inngest-image' '$DED_CODE_FILE'"
assert "Row4: consumer 4/4 — the Config.Env inspect reads \$IREF" \
  "grep -qF 'docker inspect \"\$IREF\"' '$DED_CODE_FILE'"

# --- Row 5: a total pull failure names which legs were tried and why each failed -----------
# #7462's whole diagnosis rode on `oci-pull-rc-1`'s incidental tail. Make that explicit.
assert "Row5: a distinct all-legs-failed stage exists" \
  "grep -qF 'inngest-boot-phone-home.sh oci-pull-ALL-LEGS-FAILED' '$DED_CODE_FILE'"
ZG_ALLLEGS_LINE=$(grep -F 'inngest-boot-phone-home.sh oci-pull-ALL-LEGS-FAILED' "$DED_CODE_FILE" | head -1 || true)
assert "Row5: the all-legs-failed detail names the zot leg" \
  "grep -qF 'zot=' <<<\"\$ZG_ALLLEGS_LINE\""
assert "Row5: the all-legs-failed detail names the ghcr leg" \
  "grep -qF 'ghcr=' <<<\"\$ZG_ALLLEGS_LINE\""

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
  assert "Phase5: phone-home stage '$_zs' is emitted (mirrors the GHCR trio)" \
    "grep -qF 'inngest-boot-phone-home.sh $_zs' '$DED_CODE_FILE'"
done

# --- Dark-safety: an unconfigured endpoint must degrade to TODAY's path, never to a worse one
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
# The pull log tail is SHIPPED off-box by `oci-pull-rc-N`. inngest-redact.sh redacts by KNOWN
# VALUE, so a credential absent from its value list is a credential that ships in clear on an
# auth failure — which is exactly the failure mode that produces a log tail worth shipping.
# SCOPED to the script body, not the file. `ZOT_PULL_TOKEN` occurs 4x in the yml (the bake
# printf, the login item, the redact list), so a whole-file grep stayed green with the redact
# line deleted — a cq-assert-anchor-not-bare-token violation on SCOPE rather than on comments.
ZG_REDACT_BODY="$(awk '/^  - path: \/usr\/local\/bin\/inngest-redact\.sh$/{f=1;next} f&&/^  - path: /{f=0} f' "$INNGEST_CI_YML")"
assert "the zot pull token is in inngest-redact.sh's known-value list" \
  "grep -qF 'ZOT_PULL_TOKEN' <<<\"\$ZG_REDACT_BODY\""
assert "the zot token reaches that list via the same sourced-file shape as GHCR_READ_TOKEN" \
  "grep -qF 'ZOT_PULL_TOKEN' <<<\"\$ZG_REDACT_BODY\" && grep -qF 'GHCR_READ_TOKEN' <<<\"\$ZG_REDACT_BODY\""

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
ZG_SECTION_ASSERTIONS=$(( TOTAL - ZG_TOTAL_BEFORE ))
assert "Guard 1 anti-vacuity: the section ran its full assertion inventory (expected 50, ran $ZG_SECTION_ASSERTIONS)" \
  "(( ZG_SECTION_ASSERTIONS == 50 ))"

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
UNCONDITIONAL_ASSERTIONS=$(( TOTAL - COND_ASSERTIONS ))
BOOTSTRAP_MIN_ASSERTIONS=123
if [[ "$UNCONDITIONAL_ASSERTIONS" -lt "$BOOTSTRAP_MIN_ASSERTIONS" ]]; then
  printf 'FAIL: assertion-count floor: only %s unconditional assertions ran (%s total, %s from tool-gated blocks), expected >= %s — a block was skipped or emptied.\n' \
    "$UNCONDITIONAL_ASSERTIONS" "$TOTAL" "$COND_ASSERTIONS" "$BOOTSTRAP_MIN_ASSERTIONS" >&2
  exit 1
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
echo "BOOTSTRAP_SUITE_OK unconditional=$UNCONDITIONAL_ASSERTIONS floor=$BOOTSTRAP_MIN_ASSERTIONS total=$TOTAL"
