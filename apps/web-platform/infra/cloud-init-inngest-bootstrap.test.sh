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
  "awk '/Bootstrap Inngest server on first boot/,/^[^[:space:]]/' '$CLOUD_INIT' | grep -qE 'trap .*cleanup.* EXIT'"

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
if command -v dash >/dev/null 2>&1; then
  assert "snippet passes dash -n (POSIX portability)" "dash -n '$SNIPPET_FILE'"
else
  echo "  SKIP: dash not installed (POSIX portability check skipped — CI will exercise it)"
fi

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
if command -v visudo >/dev/null 2>&1; then
  assert "sudoers source parses via visudo -cf"          "visudo -cf '$SUDOERS_SRC' >/dev/null"
else
  echo "  SKIP: visudo not installed locally — CI will exercise the validation step"
fi

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
assert "new quiesce/enable alias argv are wildcard-free" "[[ -n \"\$QE_LINES\" ]] && ! printf '%s' \"\$QE_LINES\" | grep -qF '*'"

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
  "awk '/variable \"web_colocate_inngest\"/,/^}/' '$VARS_TF' | grep -qE 'type[[:space:]]*=[[:space:]]*bool'"

# --- AC7: web_colocate_inngest gate — terraform render authority ---
# The single behavioral authority for the gate's effect. A real `terraform templatefile`
# render is the ONLY thing that exercises the load-bearing `~}` whitespace-strip; the
# rendered-YAML validity property also lives here (not duplicated in AC3). SKIP locally
# when terraform is absent — CI's deploy-script-tests job supplies it via setup-terraform.
echo ""
echo "--- AC7: web_colocate_inngest gate — terraform render authority ---"
if command -v terraform >/dev/null 2>&1; then
  RENDER_SCRATCH=$(mktemp -d)
  # Render the web cloud-init into $2. $1 = web_colocate_inngest; $3 = web_tunnel_connector
  # (defaults true = web-1, the connector host, so AC7's call sites stay two-arg).
  # All map vars are placeholders EXCEPT the toggles; keep in sync with server.tf's
  # templatefile map — a new map var breaks this render (the intended tripwire).
  # stderr is NOT swallowed: a render error must surface, not present as an empty file
  # whose assertions fail with a misleading "OMITS" pass (#6425).
  render_ci() {
    local colocate="$1" out="$2" connector="${3:-true}"
    printf 'templatefile("%s", { image_name="i", fail2ban_sshd_local_b64="x", host_scripts_content_hash="h", tunnel_token="TT_SENTINEL_6425", webhook_deploy_secret="w", doppler_token="d", sentry_dsn="s", resend_api_key="r", ghcr_read_user="u", ghcr_read_token="g", ci_ssh_public_key_openssh="k", workspaces_volume_id="v", registry_endpoint="reg", web_colocate_inngest=%s, web_tunnel_connector=%s, host_name="soleur-web-platform", private_ip="10.0.1.10" })\n' \
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
INNGEST_CI_PROSE="$(grep -E '^[[:space:]]*#' "$INNGEST_CI_YML" | sed -E 's/^[[:space:]]*#[[:space:]]?//' | tr '\n' ' ' | tr -s ' ')"
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

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "OK"
