#!/usr/bin/env bash
#
# OFFLINE T2 STATE-MOVE REHEARSAL (#9357, plan task 5.1, Guard 6).
#
# WHAT THIS IS. A STATE-ADDRESS rehearsal. It replays the EXACT forward `terraform state mv`
# sequence that knowledge-base/engineering/operations/runbooks/workspaces-luks-t2-collapse-9357.md
# prescribes (read out of the runbook by an extractor; the suite holds no second copy it executes)
# against a scratch Terraform root built from the built-in `terraform_data` type. It is NOT
# evidence about hcloud provider behaviour: no provider is loaded, and no volume, attachment or
# server exists in it. `terraform init` here downloads nothing (the built-in provider ships inside
# the binary; asserted below) and nothing in this file touches a real root, a real state or the
# network.
#
# THE HAZARD IT MAKES REAL. T2 dissolves the singleton `hcloud_volume.workspaces_luks` /
# `hcloud_volume_attachment.workspaces_luks` into the keyed family at ["web-1"]. If the HCL half
# merges before the state half, the plan DESTROYS the singleton, which holds the sole copy of every
# user workspace. Case (a) demonstrates that destroy, so a green (b) cannot be a plan that was
# simply never going to destroy anything.
#
# THE MIRROR. Addresses keep the real shape through a fixed mapping applied to the runbook's
# commands, because a resource's type cannot be faked:
#     hcloud_volume.NAME             -> terraform_data.hcloud_volume_NAME
#     hcloud_volume_attachment.NAME  -> terraform_data.hcloud_volume_attachment_NAME
# (bracket keys are preserved; `workspaces_luks` still shares its prefix with `workspaces`, which
# is the hazard the runbook's physical-id pin warns about).
#
# CASE LABELS match the runbook's own citations of this suite:
#   (a) anti-vacuity: as-is state + T2 config plans destroy+create of the sole-copy stand-in
#   (b) after the runbook's forward sequence the plan is empty; (d)-state: serial advanced,
#       lineage unchanged, ids preserved, other keys undisturbed
#   (c) a `moved` block under -target fails the plan (ADR-119 2026-09-28 measurement, re-proved)
#   (d) moving only ONE of the two addresses leaves a destroying plan
#   (e) the OCCUPIED ["web-1"] slots (pre-#9348 state) make the first move collide
#   (x) the extractor reads exactly the forward sequence and never the reverse rollback one
#
# Terraform is a REQUIRED tool here. CI installs it (setup-terraform in infra-validation.yml's
# deploy-script-tests legs, version = TERRAFORM_VERSION). Where it is absent this suite exits
# non-zero when CI is set (never a silent skip) and exits 0 loudly otherwise.
#
# HARNESS DISCIPLINE: independent `cases` counter incremented at the call site; the floor and the
# helper canary report through printf + exit directly, NOT through pass()/fail() (a floor enforced
# through the suspect cannot witness the suspect). Every mutation restores from a pristine copy and
# asserts it landed. No `producer | grep -q` under pipefail: greps run against files.
set -uo pipefail

# --- environment hygiene --------------------------------------------------------------------
# GIT_* (a hook/worktree parent can leak GIT_DIR and friends) and every TF_* knob that would
# change what terraform reads or where it phones home.
for _v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$_v"; done
for _v in $(env | sed -n 's/^\(TF_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$_v"; done
unset _v
export CHECKPOINT_DISABLE=1 TF_IN_AUTOMATION=1 TF_INPUT=0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../../.." && pwd)"
RUNBOOK="${ROOT}/knowledge-base/engineering/operations/runbooks/workspaces-luks-t2-collapse-9357.md"
APPLY_WF="${ROOT}/.github/workflows/apply-web-platform-infra.yml"

passes=0
fails=0
cases=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }

printf '\n=== workspaces-luks-t2-rehearsal ===\n\n'

# --- tooling gate: absent tool is a skip locally, a RED under CI -------------------------------
tool_missing() {
  if [ -n "${CI:-}" ]; then
    printf '[FATAL] %s is required but not on PATH, and CI is set: refusing to skip silently.\n' "$1" >&2
    exit 1
  fi
  printf 'SKIP: %s not on PATH (local run); this rehearsal needs it and RUNS in CI.\n' "$1"
  exit 0
}
command -v terraform >/dev/null 2>&1 || tool_missing terraform
command -v jq >/dev/null 2>&1 || tool_missing jq
[ -r "$RUNBOOK" ] || { printf '[FATAL] runbook not readable: %s\n' "$RUNBOOK" >&2; exit 1; }
[ -r "$APPLY_WF" ] || { printf '[FATAL] apply workflow not readable: %s\n' "$APPLY_WF" >&2; exit 1; }

# Pin: the version CI runs is the apply workflow's TERRAFORM_VERSION (single source; the single-use forget workflow that carried the same pin is deleted by #9348).
PINNED_TF="$(sed -n 's/^[[:space:]]*TERRAFORM_VERSION:[[:space:]]*"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}[[:space:]]*$/\1/p' "$APPLY_WF" | sed -n '1p')"
[ -n "$PINNED_TF" ] || { printf '[FATAL] could not read TERRAFORM_VERSION from %s\n' "$APPLY_WF" >&2; exit 1; }
INSTALLED_TF="$(terraform version -json 2>/dev/null | jq -r '.terraform_version // empty' 2>/dev/null)"
if [ "$INSTALLED_TF" != "$PINNED_TF" ]; then
  if [ -n "${CI:-}" ]; then
    printf '[FATAL] terraform %s installed but CI pins %s (TERRAFORM_VERSION in apply-web-platform-infra.yml).\n' "${INSTALLED_TF:-unknown}" "$PINNED_TF" >&2
    exit 1
  fi
  printf '  note terraform %s here, CI pins %s: local run is NOT version-pinned (CI enforces the pin).\n' "${INSTALLED_TF:-unknown}" "$PINNED_TF"
else
  printf '  note terraform %s (pinned to CI TERRAFORM_VERSION)\n' "$INSTALLED_TF"
fi

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
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/luks-t2-rehearsal.XXXXXXXX")" || exit 2
assert_fixture_dir "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT
: >"$SCRATCH/tfrc"                       # empty CLI config: no user plugin cache, no mirrors
export TF_CLI_CONFIG_FILE="$SCRATCH/tfrc"

# --- terraform wrapper -----------------------------------------------------------------------
# Runs in $1 with a per-directory TF_DATA_DIR; combined output lands in $1/.out with ANSI
# stripped (so message anchors are stable) and the rc is returned.
tf() {
  local d="$1" rc
  shift
  assert_fixture_dir "$d"
  (cd "$d" && TF_DATA_DIR="$d/.tfdata" terraform "$@" >"$d/.out.raw" 2>&1)
  rc=$?
  sed 's/\x1b\[[0-9;]*m//g' "$d/.out.raw" >"$d/.out"
  return "$rc"
}
# stdout-only variant for JSON (never mixes stderr into the document).
tfj() {
  local d="$1"
  shift
  (cd "$d" && TF_DATA_DIR="$d/.tfdata" terraform "$@" 2>/dev/null)
}

# --- fixture configs ---------------------------------------------------------------------------
# PRE: today's shape. Singleton volume + attachment (the LUKS sole copy), plus the keyed family
# whose ["web-1"] slots are OCCUPIED by the plaintext backstop (prevent_destroy).
cat >"$SCRATCH/pre.tf" <<'EOF'
resource "terraform_data" "hcloud_volume_workspaces_luks" {
  input = "SOLE-COPY-STANDIN"
}
resource "terraform_data" "hcloud_volume_attachment_workspaces_luks" {
  input = "ATTACH-LUKS-STANDIN"
}
resource "terraform_data" "hcloud_volume_workspaces" {
  for_each = toset(["web-1", "web-2"])
  input    = "plain-${each.key}"
  lifecycle {
    prevent_destroy = true
  }
}
resource "terraform_data" "hcloud_volume_attachment_workspaces" {
  for_each = toset(["web-1", "web-2"])
  input    = "attach-${each.key}"
}
EOF
# T2: the singleton dissolved into the keyed family. web-1's keyed instance carries the LUKS
# stand-in values, so a moved instance plans no change.
cat >"$SCRATCH/t2.tf" <<'EOF'
resource "terraform_data" "hcloud_volume_workspaces" {
  for_each = toset(["web-1", "web-2"])
  input    = each.key == "web-1" ? "SOLE-COPY-STANDIN" : "plain-${each.key}"
}
resource "terraform_data" "hcloud_volume_attachment_workspaces" {
  for_each = toset(["web-1", "web-2"])
  input    = each.key == "web-1" ? "ATTACH-LUKS-STANDIN" : "attach-${each.key}"
}
EOF
cat >"$SCRATCH/moved.tf" <<'EOF'
moved {
  from = terraform_data.hcloud_volume_workspaces_luks
  to   = terraform_data.hcloud_volume_workspaces["web-1"]
}
moved {
  from = terraform_data.hcloud_volume_attachment_workspaces_luks
  to   = terraform_data.hcloud_volume_attachment_workspaces["web-1"]
}
EOF

# new_scen NAME CONFIG STATE -> sets SCEN to an initialised scratch root holding that state.
SCEN=""
new_scen() {
  local name="$1" cfg="$2" st="$3" d
  d="$SCRATCH/s_$name"
  rm -rf "$d"
  mkdir -p "$d"
  cp "$cfg" "$d/main.tf"
  [ -n "$st" ] && cp "$st" "$d/terraform.tfstate"
  tf "$d" init -input=false >/dev/null || { printf '[FATAL] init failed in %s\n' "$d" >&2; head -20 "$d/.out" >&2; exit 1; }
  SCEN="$d"
}

# --- plan classifier ---------------------------------------------------------------------------
# classify PLAN_JSON -> one "actions address" line per non-no-op change (actions joined by '+').
classify() {
  jq -r '.resource_changes[]? | select(.change.actions != ["no-op"]) | "\(.change.actions | join("+")) \(.address)"' "$1" 2>/dev/null | sort
}
# plan_has_delete LINES_FILE -> 0 when any change destroys (delete, delete+create, create+delete).
plan_has_delete() { grep -Eq '(^|\+)delete(\+| )' "$1"; }

# plan_in DIR [extra plan args] -> PLAN_RC; DIR/plan.lines holds the classified changes.
PLAN_RC=0
plan_in() {
  local d="$1"
  shift
  assert_fixture_dir "$d"
  tf "$d" plan -detailed-exitcode -input=false -out=tfplan "$@"
  PLAN_RC=$?
  : >"$d/plan.lines"
  if [ "$PLAN_RC" -ne 1 ]; then
    tfj "$d" show -json tfplan >"$d/plan.json"
    classify "$d/plan.json" >"$d/plan.lines"
  fi
}

# --- the runbook command extractor -------------------------------------------------------------
# extract_block RUNBOOK HEADING -> the lines of the SINGLE ```bash block inside the section whose
# heading line equals HEADING exactly (section ends at the next '## '). Non-zero when the heading
# is absent or the section does not hold exactly one bash block.
extract_block() {
  awk -v head="$2" '
    $0 == head { insec = 1; seen = 1; next }
    insec && /^## / { insec = 0 }
    insec && $0 == "```bash" { inblk = 1; blocks++; next }
    insec && inblk && $0 == "```" { inblk = 0; next }
    insec && inblk { print }
    END { if (!seen || blocks != 1) exit 3 }
  ' "$1"
}
FWD_HEAD='## State-move sequence (forward)'
REV_HEAD='## Rollback (reverse sequence)'
# The suite's independent statement of what each section must hold (case x).
EXPECT_FWD="terraform state mv 'hcloud_volume.workspaces_luks' 'hcloud_volume.workspaces[\"web-1\"]'
terraform state mv 'hcloud_volume_attachment.workspaces_luks' 'hcloud_volume_attachment.workspaces[\"web-1\"]'"
EXPECT_REV="terraform state mv 'hcloud_volume_attachment.workspaces[\"web-1\"]' 'hcloud_volume_attachment.workspaces_luks'
terraform state mv 'hcloud_volume.workspaces[\"web-1\"]' 'hcloud_volume.workspaces_luks'"

MV_RE="^terraform state mv '([^']+)' '([^']+)'$"
# map_addr ADDR -> the mirror address (see THE MIRROR above).
map_addr() {
  printf '%s\n' "$1" | sed -E 's/^hcloud_volume_attachment\./terraform_data.hcloud_volume_attachment_/; s/^hcloud_volume\./terraform_data.hcloud_volume_/'
}
# run_moves DIR CMDS_FILE -> executes each extracted command, mapped, against DIR. Strict: a line
# that is not exactly `terraform state mv '<src>' '<dst>'` is refused (rc 3); first failing move
# stops the sequence (rc 1, MV_DONE says how many ran).
MV_DONE=0
run_moves() {
  local d="$1" f="$2" line src dst rc
  # `mv` below is a terraform STATE verb on resource addresses, not a filesystem move; held in a
  # variable so the fixture-relative scanner does not read the address operands as paths.
  local verb=mv
  assert_fixture_dir "$d"
  MV_DONE=0
  while IFS= read -r line; do
    [[ "$line" =~ $MV_RE ]] || return 3
    src="$(map_addr "${BASH_REMATCH[1]}")"
    dst="$(map_addr "${BASH_REMATCH[2]}")"
    tf "$d" state "$verb" "$src" "$dst"
    rc=$?
    [ "$rc" -eq 0 ] || return 1
    MV_DONE=$((MV_DONE + 1))
  done <"$f"
  return 0
}

# state_meta DIR -> "serial lineage" via one field-selecting jq (state is never echoed).
state_meta() { tfj "$1" state pull | jq -r '"\(.serial) \(.lineage)"'; }
# inst_id DIR NAME KEY -> the instance id of a terraform_data resource (empty KEY = singleton).
inst_id() {
  tfj "$1" state pull | jq -r --arg n "$2" --arg k "$3" \
    '.resources[] | select(.type=="terraform_data" and .name==$n) | .instances[] | select((.index_key // "") == $k) | .attributes.id'
}

# ===================================================================================================
# 0. INSTRUMENT SELF-TEST (before any scenario is trusted)
# ===================================================================================================
# 0a. helper canary: driving pass()/fail() once each must move the counters by exactly one each.
_p0=$passes; _f0=$fails
pass "CANARY" >/dev/null
fail "CANARY" >/dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ]; then
  printf '[FATAL] CANARY: pass()/fail() no longer dispatch (passes %d->%d, fails %d->%d).\n' "$_p0" "$passes" "$_f0" "$fails" >&2
  exit 1
fi
passes=$_p0; fails=$_f0

# 0b. H1 harness: the classifier MUST flag a plan that deletes (a delete it cannot see would make
# every "no destroy" verdict below vacuous), and MUST NOT flag a no-op plan (control).
printf '{"resource_changes":[{"address":"x.y","change":{"actions":["delete"]}},{"address":"x.z","change":{"actions":["no-op"]}}]}' >"$SCRATCH/h1_del.json"
printf '{"resource_changes":[{"address":"x.z","change":{"actions":["no-op"]}}]}' >"$SCRATCH/h1_ok.json"
printf '{"resource_changes":[{"address":"x.r","change":{"actions":["delete","create"]}}]}' >"$SCRATCH/h1_repl.json"
classify "$SCRATCH/h1_del.json" >"$SCRATCH/h1_del.lines"
classify "$SCRATCH/h1_ok.json" >"$SCRATCH/h1_ok.lines"
classify "$SCRATCH/h1_repl.json" >"$SCRATCH/h1_repl.lines"
cases=$((cases + 1))
if plan_has_delete "$SCRATCH/h1_del.lines"; then pass "H1: classifier flags a plan with a delete"; else fail "H1: classifier missed a delete" "$(cat "$SCRATCH/h1_del.lines")"; fi
cases=$((cases + 1))
if plan_has_delete "$SCRATCH/h1_repl.lines"; then pass "H1: classifier flags a replace (delete+create)"; else fail "H1: classifier missed a replace"; fi
cases=$((cases + 1))
if plan_has_delete "$SCRATCH/h1_ok.lines"; then fail "H1 control: classifier flagged a no-op plan"; else pass "H1 control: classifier leaves a no-op plan alone"; fi

# ===================================================================================================
# 1. EXTRACTOR (case x) — reads exactly the forward sequence
# ===================================================================================================
FWD_RAW="$SCRATCH/fwd.cmds"
REV_RAW="$SCRATCH/rev.cmds"
extract_block "$RUNBOOK" "$FWD_HEAD" >"$FWD_RAW"; _rc_f=$?
extract_block "$RUNBOOK" "$REV_HEAD" >"$REV_RAW"; _rc_r=$?
cases=$((cases + 1))
if [ "$_rc_f" -eq 0 ] && [ "$(cat "$FWD_RAW")" = "$EXPECT_FWD" ]; then
  pass "x: extractor reads exactly the two forward commands, in order"
else
  fail "x: forward extraction differs from the suite's statement of the forward sequence" "rc=$_rc_f got: $(head -5 "$FWD_RAW")"
fi
cases=$((cases + 1))
if [ "$_rc_r" -eq 0 ] && [ "$(cat "$REV_RAW")" = "$EXPECT_REV" ]; then
  pass "x: rollback section holds exactly the reversed pair (and is a distinct block)"
else
  fail "x: rollback extraction differs from the expected reverse sequence" "rc=$_rc_r got: $(head -5 "$REV_RAW")"
fi
cases=$((cases + 1))
if ! grep -Eq "^terraform state mv '[^']*\\[" "$FWD_RAW" && [ "$(wc -l <"$FWD_RAW")" -eq 2 ]; then
  pass "x: no forward command moves FROM a keyed address (the reverse shape is absent)"
else
  fail "x: a forward command sources a keyed address, or the count is not 2"
fi
# every extracted line must parse strictly (the executor refuses anything else)
_n_parse=0
while IFS= read -r _l; do [[ "$_l" =~ $MV_RE ]] && _n_parse=$((_n_parse + 1)); done <"$FWD_RAW"
cases=$((cases + 1))
if [ "$_n_parse" -eq 2 ]; then pass "x: both forward lines parse as exactly 'terraform state mv <src> <dst>'"; else fail "x: only $_n_parse of 2 forward lines parse strictly"; fi

# ===================================================================================================
# 2. FIXTURE — build today's state offline, derive the post-#9348 state
# ===================================================================================================
new_scen fx "$SCRATCH/pre.tf" ""
FX="$SCEN"
tf "$FX" apply -auto-approve -input=false >/dev/null; _rc=$?
cases=$((cases + 1))
if [ "$_rc" -eq 0 ]; then pass "fixture: pre-T2 root applies offline"; else fail "fixture: pre-T2 apply failed" "$(head -10 "$FX/.out")"; fi
cases=$((cases + 1))
if ! grep -Eq 'Installing|Finding' "$FX/.out.raw"; then pass "fixture: no provider was downloaded (built-in terraform_data only)"; else fail "fixture: init/apply fetched a provider"; fi
tf "$FX" plan -detailed-exitcode -input=false >/dev/null; _rc=$?
cases=$((cases + 1))
if [ "$_rc" -eq 0 ]; then pass "fixture: pre-T2 config vs its own state plans no change"; else fail "fixture: pre-T2 plan not clean (rc=$_rc)"; fi
tfj "$FX" state list | sort >"$SCRATCH/pre.list"
cases=$((cases + 1))
if [ "$(wc -l <"$SCRATCH/pre.list")" -eq 6 ] \
   && grep -Fxq 'terraform_data.hcloud_volume_workspaces["web-1"]' "$SCRATCH/pre.list" \
   && grep -Fxq 'terraform_data.hcloud_volume_attachment_workspaces["web-1"]' "$SCRATCH/pre.list" \
   && grep -Fxq 'terraform_data.hcloud_volume_workspaces_luks' "$SCRATCH/pre.list"; then
  pass "fixture: OCCUPIED keyed web-1 slots and both singletons are in state"
else
  fail "fixture: state shape is not 6 addresses with occupied web-1 slots" "$(cat "$SCRATCH/pre.list")"
fi
cp "$FX/terraform.tfstate" "$SCRATCH/pre.tfstate"
# post-#9348: the forget flow removes exactly the two occupied keyed addresses.
tf "$FX" state rm 'terraform_data.hcloud_volume_workspaces["web-1"]' 'terraform_data.hcloud_volume_attachment_workspaces["web-1"]'; _rc=$?
cases=$((cases + 1))
if [ "$_rc" -eq 0 ]; then pass "fixture: post-#9348 state derived (two occupied slots forgotten)"; else fail "fixture: state rm failed" "$(head -10 "$FX/.out")"; fi
cp "$FX/terraform.tfstate" "$SCRATCH/post.tfstate"
cp "$SCRATCH/post.tfstate" "$SCRATCH/post.pristine"      # pristine copy: mutations restore from here

# ===================================================================================================
# 3. (a) ANTI-VACUITY — without the state move the T2 config destroys the sole copy
# ===================================================================================================
# hazard_demonstrated DIR -> 0 iff the plan destroys the singleton volume AND creates the keyed one.
hazard_demonstrated() {
  plan_in "$1"
  [ "$PLAN_RC" -eq 2 ] \
    && grep -Fxq 'delete terraform_data.hcloud_volume_workspaces_luks' "$1/plan.lines" \
    && grep -Fxq 'create terraform_data.hcloud_volume_workspaces["web-1"]' "$1/plan.lines"
}
new_scen a "$SCRATCH/t2.tf" "$SCRATCH/post.tfstate"
SA="$SCEN"
cases=$((cases + 1))
if hazard_demonstrated "$SA"; then
  pass "(a) as-is state + T2 config: plan DESTROYS the sole-copy stand-in and CREATES the keyed one"
else
  fail "(a) the hazard was NOT demonstrated: the rehearsal would be vacuous" "rc=$PLAN_RC $(cat "$SA/plan.lines")"
fi
cases=$((cases + 1))
if grep -Fxq 'delete terraform_data.hcloud_volume_attachment_workspaces_luks' "$SA/plan.lines"; then
  pass "(a) the singleton attachment stand-in is destroyed too"
else
  fail "(a) attachment destroy absent" "$(cat "$SA/plan.lines")"
fi

# ===================================================================================================
# 4. (b) FORWARD SEQUENCE — exact runbook commands, then an empty plan
# ===================================================================================================
# forward_clean DIR CMDS -> 0 iff every command runs and the follow-up plan is exactly "no change".
forward_clean() {
  run_moves "$1" "$2" || return 1
  plan_in "$1"
  [ "$PLAN_RC" -eq 0 ] && [ ! -s "$1/plan.lines" ]
}
new_scen b "$SCRATCH/t2.tf" "$SCRATCH/post.tfstate"
SB="$SCEN"
_meta0="$(state_meta "$SB")"
_vol_before="$(inst_id "$SB" hcloud_volume_workspaces_luks "")"
_att_before="$(inst_id "$SB" hcloud_volume_attachment_workspaces_luks "")"
_w2_before="$(inst_id "$SB" hcloud_volume_workspaces web-2)"
tfj "$SB" state list | sort >"$SCRATCH/b_before.list"
cases=$((cases + 1))
if forward_clean "$SB" "$FWD_RAW"; then
  pass "(b) the runbook's exact forward sequence leaves a plan with NO change"
else
  fail "(b) forward sequence did not yield an empty plan" "moves=$MV_DONE rc=$PLAN_RC $(cat "$SB/plan.lines") $(head -5 "$SB/.out")"
fi
cases=$((cases + 1))
if [ "$MV_DONE" -eq 2 ]; then pass "(b) both forward moves executed"; else fail "(b) executed $MV_DONE of 2 moves"; fi
_meta1="$(state_meta "$SB")"
_ser0="${_meta0%% *}"; _lin0="${_meta0#* }"
_ser1="${_meta1%% *}"; _lin1="${_meta1#* }"
cases=$((cases + 1))
if [ -n "$_ser0" ] && [ "$_ser1" -gt "$_ser0" ] 2>/dev/null; then pass "(d) state serial advanced ($_ser0 -> $_ser1)"; else fail "(d) serial did not advance" "$_ser0 -> $_ser1"; fi
cases=$((cases + 1))
if [ -n "$_lin0" ] && [ "$_lin0" = "$_lin1" ]; then pass "(d) lineage unchanged"; else fail "(d) lineage changed or empty" "$_lin0 -> $_lin1"; fi
cases=$((cases + 1))
if [ -n "$_vol_before" ] && [ "$(inst_id "$SB" hcloud_volume_workspaces web-1)" = "$_vol_before" ] \
   && [ -n "$_att_before" ] && [ "$(inst_id "$SB" hcloud_volume_attachment_workspaces web-1)" = "$_att_before" ]; then
  pass "(b) moved instances keep their pinned ids (volume and attachment)"
else
  fail "(b) a moved instance id changed"
fi
cases=$((cases + 1))
if [ -n "$_w2_before" ] && [ "$(inst_id "$SB" hcloud_volume_workspaces web-2)" = "$_w2_before" ]; then
  pass "(b) the web-2 keyed member is undisturbed"
else
  fail "(b) web-2 changed across the move"
fi
tfj "$SB" state list | sort >"$SCRATCH/b_after.list"
sed -e 's/^terraform_data.hcloud_volume_workspaces_luks$/terraform_data.hcloud_volume_workspaces["web-1"]/' \
    -e 's/^terraform_data.hcloud_volume_attachment_workspaces_luks$/terraform_data.hcloud_volume_attachment_workspaces["web-1"]/' \
    "$SCRATCH/b_before.list" | sort >"$SCRATCH/b_expect.list"
cases=$((cases + 1))
if cmp -s "$SCRATCH/b_expect.list" "$SCRATCH/b_after.list"; then
  pass "(b) state list is the old list with exactly the two singletons re-addressed"
else
  fail "(b) state list drifted beyond the two re-addressed entries" "$(diff "$SCRATCH/b_expect.list" "$SCRATCH/b_after.list" | head -6)"
fi

# ===================================================================================================
# 5. (c) `moved` under -target fails the plan
# ===================================================================================================
TARGET='terraform_data.hcloud_volume_workspaces["web-2"]'
new_scen c0 "$SCRATCH/t2.tf" "$SCRATCH/post.tfstate"
SC0="$SCEN"
tf "$SC0" plan -input=false "-target=$TARGET"; _rc_c0=$?
cases=$((cases + 1))
if [ "$_rc_c0" -eq 0 ]; then pass "(c) control: the same -target plan succeeds with no moved block"; else fail "(c) control -target plan failed without a moved block" "rc=$_rc_c0 $(head -8 "$SC0/.out")"; fi
new_scen c1 "$SCRATCH/t2.tf" "$SCRATCH/post.tfstate"
SC1="$SCEN"
cp "$SCRATCH/moved.tf" "$SC1/moved.tf"
tf "$SC1" plan -input=false "-target=$TARGET"; _rc_c1=$?
cases=$((cases + 1))
if [ "$_rc_c1" -ne 0 ] && grep -Fq 'do not fully cover' "$SC1/.out"; then
  pass "(c) a moved block under -target FAILS the plan (-target does not cover the move's instances)"
else
  fail "(c) a moved block under -target did not fail the plan" "rc=$_rc_c1 $(head -8 "$SC1/.out")"
fi

# ===================================================================================================
# 6. (d) moving only ONE of the two addresses still destroys; (e) occupied slots collide
# ===================================================================================================
head -n 1 "$FWD_RAW" >"$SCRATCH/one.cmds"
new_scen d "$SCRATCH/t2.tf" "$SCRATCH/post.tfstate"
SD="$SCEN"
cases=$((cases + 1))
if forward_clean "$SD" "$SCRATCH/one.cmds"; then
  fail "(d) moving only the volume left a CLEAN plan: the attachment stand-in is no longer guarded"
else
  if grep -Fxq 'delete terraform_data.hcloud_volume_attachment_workspaces_luks' "$SD/plan.lines" && [ "$MV_DONE" -eq 1 ]; then
    pass "(d) volume-only move: plan still destroys the orphaned attachment singleton"
  else
    fail "(d) volume-only move failed for the wrong reason" "moves=$MV_DONE $(cat "$SD/plan.lines")"
  fi
fi

new_scen e "$SCRATCH/t2.tf" "$SCRATCH/pre.tfstate"
SE="$SCEN"
cases=$((cases + 1))
if run_moves "$SE" "$FWD_RAW"; then
  fail "(e) the forward move succeeded onto an OCCUPIED slot (no collision)"
else
  if [ "$MV_DONE" -eq 0 ] && grep -Fq 'already a resource instance at that address' "$SE/.out"; then
    pass "(e) pre-#9348 state: the first move COLLIDES with the occupied [\"web-1\"] slot"
  else
    fail "(e) the first move failed, but not with the collision error" "moves=$MV_DONE $(head -6 "$SE/.out")"
  fi
fi
cases=$((cases + 1))
plan_in "$SE"
if plan_has_delete "$SE/plan.lines" && grep -Fxq 'delete terraform_data.hcloud_volume_workspaces_luks' "$SE/plan.lines"; then
  pass "(e) and the singleton sole copy is still slated for destroy (the recipe must start post-#9348)"
else
  fail "(e) expected a destroying plan on the unmoved occupied state" "$(cat "$SE/plan.lines")"
fi

# ===================================================================================================
# 7. MUTATION MATRIX (Guard 6). Each mutation restores from a pristine copy, asserts it LANDED,
#    then asserts the suite's check goes RED on it.
# ===================================================================================================
landed() { # LABEL PRISTINE MUTATED
  cases=$((cases + 1))
  if cmp -s "$2" "$3"; then fail "$1: mutation did NOT land (mutated == pristine): UN-RUN, not caught"; else pass "$1: mutation landed"; fi
}

# M1 — hazard neutralised: the singleton is still declared, so nothing is destroyed. The
# anti-vacuity check (a) must report the hazard as NOT demonstrated.
cp "$SCRATCH/t2.tf" "$SCRATCH/m1.tf"
cat >>"$SCRATCH/m1.tf" <<'EOF'
resource "terraform_data" "hcloud_volume_workspaces_luks" {
  input = "SOLE-COPY-STANDIN"
}
resource "terraform_data" "hcloud_volume_attachment_workspaces_luks" {
  input = "ATTACH-LUKS-STANDIN"
}
EOF
landed "M1" "$SCRATCH/t2.tf" "$SCRATCH/m1.tf"
new_scen m1 "$SCRATCH/m1.tf" "$SCRATCH/post.tfstate"
cases=$((cases + 1))
if hazard_demonstrated "$SCEN"; then fail "M1: anti-vacuity stayed green with no destroy in the plan (vacuous)"; else pass "M1: anti-vacuity goes RED when the plan shows no destroy"; fi

# M2 — only one of the two moves (volume without attachment) must not pass forward_clean.
head -n 1 "$FWD_RAW" >"$SCRATCH/m2.cmds"
landed "M2" "$FWD_RAW" "$SCRATCH/m2.cmds"
new_scen m2 "$SCRATCH/t2.tf" "$SCRATCH/post.tfstate"
cases=$((cases + 1))
if forward_clean "$SCEN" "$SCRATCH/m2.cmds"; then fail "M2: a volume-only move passed the forward check"; else pass "M2: volume-only move is RED"; fi
# M2b — the other half (attachment without volume).
sed -n '2p' "$FWD_RAW" >"$SCRATCH/m2b.cmds"
landed "M2b" "$FWD_RAW" "$SCRATCH/m2b.cmds"
new_scen m2b "$SCRATCH/t2.tf" "$SCRATCH/post.tfstate"
cases=$((cases + 1))
if forward_clean "$SCEN" "$SCRATCH/m2b.cmds"; then fail "M2b: an attachment-only move passed the forward check"; else pass "M2b: attachment-only move is RED"; fi

# M3 — a second keyed member added after a compliant first: the family's plan is no longer empty.
sed 's/toset(\["web-1", "web-2"\])/toset(["web-1", "web-2", "web-3"])/' "$SCRATCH/t2.tf" >"$SCRATCH/m3.tf"
landed "M3" "$SCRATCH/t2.tf" "$SCRATCH/m3.tf"
new_scen m3 "$SCRATCH/m3.tf" "$SCRATCH/post.tfstate"
cases=$((cases + 1))
if forward_clean "$SCEN" "$FWD_RAW"; then fail "M3: an added web-3 key still read as a clean plan"; else pass "M3: an added keyed member makes the post-move plan RED (and web-2 stays undisturbed in (b))"; fi

# M4 — the extractor/runbook divergence classes.
cp "$RUNBOOK" "$SCRATCH/m4a.md"
sed -i 's/^## State-move sequence (forward)$/## State-move sequence/' "$SCRATCH/m4a.md"
landed "M4a" "$RUNBOOK" "$SCRATCH/m4a.md"
extract_block "$SCRATCH/m4a.md" "$FWD_HEAD" >"$SCRATCH/m4a.out"; _rc=$?
cases=$((cases + 1))
if [ "$_rc" -ne 0 ]; then pass "M4a: a runbook without the forward heading makes the extractor fail"; else fail "M4a: extractor read a section that is not there"; fi
# reverse picked up under the forward heading
cp "$RUNBOOK" "$SCRATCH/m4b.md"
sed -i -e 's/^## State-move sequence (forward)$/## State-move sequence (old)/' -e 's/^## Rollback (reverse sequence)$/## State-move sequence (forward)/' "$SCRATCH/m4b.md"
landed "M4b" "$RUNBOOK" "$SCRATCH/m4b.md"
extract_block "$SCRATCH/m4b.md" "$FWD_HEAD" >"$SCRATCH/m4b.out"
cases=$((cases + 1))
if [ "$(cat "$SCRATCH/m4b.out")" = "$EXPECT_FWD" ]; then fail "M4b: extractor picked up the reverse sequence and the comparison stayed green"; else pass "M4b: extractor reading the reverse sequence is RED against the forward statement"; fi
# a third command slipped into the forward block
cp "$RUNBOOK" "$SCRATCH/m4c.md"
sed -i "/^terraform state mv 'hcloud_volume_attachment.workspaces_luks'/a terraform state mv 'hcloud_volume.extra' 'hcloud_volume.workspaces[\"web-9\"]'" "$SCRATCH/m4c.md"
landed "M4c" "$RUNBOOK" "$SCRATCH/m4c.md"
extract_block "$SCRATCH/m4c.md" "$FWD_HEAD" >"$SCRATCH/m4c.out"
cases=$((cases + 1))
if [ "$(cat "$SCRATCH/m4c.out")" = "$EXPECT_FWD" ]; then fail "M4c: an extra forward command went unnoticed"; else pass "M4c: an extra forward command is RED against the forward statement"; fi
# a non-conforming line (flag injection) is refused by the executor, never run
printf "terraform state mv -backup=- 'hcloud_volume.workspaces_luks' 'hcloud_volume.workspaces[\"web-1\"]'\n" >"$SCRATCH/m4d.cmds"
new_scen m4d "$SCRATCH/t2.tf" "$SCRATCH/post.tfstate"
run_moves "$SCEN" "$SCRATCH/m4d.cmds"; _rc=$?
cases=$((cases + 1))
if [ "$_rc" -eq 3 ] && [ "$MV_DONE" -eq 0 ]; then pass "M4d: a command outside the strict 'state mv <src> <dst>' shape is refused, not executed"; else fail "M4d: executor ran a non-conforming command (rc=$_rc moves=$MV_DONE)"; fi

# M5 — occupied slots not cleared first: the forward check must be RED.
cp "$SCRATCH/pre.tfstate" "$SCRATCH/m5.tfstate"
cases=$((cases + 1))
if cmp -s "$SCRATCH/post.pristine" "$SCRATCH/m5.tfstate"; then fail "M5: mutation did NOT land (occupied state == cleared state)"; else pass "M5: mutation landed (occupied state differs from the cleared state)"; fi
new_scen m5 "$SCRATCH/t2.tf" "$SCRATCH/m5.tfstate"
cases=$((cases + 1))
if forward_clean "$SCEN" "$FWD_RAW"; then fail "M5: the forward sequence went green onto occupied slots"; else pass "M5: uncleared occupied slots are RED (collision)"; fi

# H2 — must-PASS: an unrelated attribute difference plans an update but NO destroy.
sed 's/"plain-\${each.key}"/"plain-${each.key}-edited"/' "$SCRATCH/t2.tf" >"$SCRATCH/h2.tf"
landed "H2" "$SCRATCH/t2.tf" "$SCRATCH/h2.tf"
new_scen h2 "$SCRATCH/h2.tf" "$SCRATCH/post.tfstate"
SH2="$SCEN"
run_moves "$SH2" "$FWD_RAW"; _rc=$?
plan_in "$SH2"
cases=$((cases + 1))
if [ "$_rc" -eq 0 ] && [ "$PLAN_RC" -eq 2 ] && grep -Eq '^update terraform_data\.hcloud_volume_workspaces\["web-2"\]$' "$SH2/plan.lines" && ! plan_has_delete "$SH2/plan.lines"; then
  pass "H2: an unrelated attribute difference plans an update and NO destroy (classifier is not over-eager)"
else
  fail "H2: unrelated drift misclassified" "moves-rc=$_rc plan-rc=$PLAN_RC $(cat "$SH2/plan.lines")"
fi

# ===================================================================================================
# TRAILER — reconciliation, floor, verdict. The floor and the accounting identity report through
# printf + exit directly: a floor enforced through pass()/fail() cannot witness a neutered helper.
# ===================================================================================================
if [ $((passes + fails)) -ne "$cases" ]; then
  printf '\n[FATAL] accounting: %d passed + %d failed = %d, but %d case(s) were counted.\n' "$passes" "$fails" "$((passes + fails))" "$cases" >&2
  printf '  An arm counted itself and reached neither pass() nor fail().\n' >&2
  exit 1
fi
MIN_CASES=45
if [ "$cases" -lt "$MIN_CASES" ]; then
  printf '\n[FATAL] anti-vacuity floor: only %d case(s) ran, expected >= %d. Coverage was lost.\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
printf '\n%d passed, %d failed (%d cases; floor %d)\n' "$passes" "$fails" "$cases" "$MIN_CASES"
if [ "$fails" -ne 0 ]; then
  exit 1
fi
printf 'ok anti-vacuity floor: %d cases ran\n' "$cases"
exit 0
