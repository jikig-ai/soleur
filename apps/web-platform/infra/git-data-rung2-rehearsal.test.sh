#!/usr/bin/env bash
#
# (#7025) Drift-guards for the rung-2 rehearsal route.
#
# WHAT THIS PROTECTS. The rehearsal boots the real git-data cloud-init on a throwaway host so
# the FIRST real boot of that template is not the production host holding every connected
# user's source code. Its safety rests on a small number of properties that are individually
# cheap to break and collectively catastrophic to lose:
#
#   1. The rehearsal root references NO production git-data address. `-target` is TRANSITIVE
#      ON DEPENDENCIES, so a single reference could drag hcloud_server.git_data into a
#      rehearsal apply's plan closure — birthing production from a workflow whose approval
#      prompt said "rehearsal".
#   2. The workflow cannot commit its own evidence. A route that writes its own
#      gate-releasing file converts a two-human-gate birth into a one-dispatch birth.
#   3. The dry-run default. `dry_run: false` as a default makes "just check the plan" spend a
#      real host.
#   4. The concurrency literal. GitHub does not error on divergent group strings — they
#      silently fail to serialize — so a rehearsal and a birth would race the same R2 state
#      object, which has no lock (`use_lockfile = false`; R2 lacks conditional writes).
#   5. The rehearsal name prefix's TRAILING HYPHEN. `soleur-git-data` is a prefix of
#      `soleur-git-data-rehearsal-<id>`, so a match written without it reports the PRODUCTION
#      host as a leaked rehearsal — and the remedy an operator reaches for on that report is
#      a destroy.
#
# EVERY ASSERTION OVER HCL OR YAML STRIPS COMMENTS FIRST. This route's rationale legitimately
# NAMES the production addresses it must not reference (explaining why it does not reference
# them), and a bare grep would refuse the files for the sentences that make them reviewable.
# That is cq-assert-anchor-not-bare-token, and it is not hypothetical here: the four
# prod-address strings in rung2-rehearsal/*.tf are all prose.
#
# Registered as a step in .github/workflows/infra-validation.yml — the suite list is DERIVED
# from that workflow by run-registered-suites.sh, whose extraction character class excludes
# `/`, which is why this file is at the infra root and NOT inside rung2-rehearsal/. Nested,
# it would be silently underived AND exempt from the orphan report: invisible twice.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../../.." && pwd)"
REH="${DIR}/rung2-rehearsal"
MOD="${DIR}/modules/git-data-userdata"
WF="${ROOT}/.github/workflows/git-data-rung2-rehearsal.yml"
APPLY_WF="${ROOT}/.github/workflows/apply-web-platform-infra.yml"
DRIFT_WF="${ROOT}/.github/workflows/scheduled-terraform-drift.yml"
GATE="${ROOT}/tests/scripts/lib/git-data-birth-readiness-gate.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }

printf '\n=== git-data-rung2-rehearsal ===\n\n'

for f in "$WF" "$APPLY_WF" "$DRIFT_WF" "$GATE" "$MOD/main.tf"; do
  [[ -f "$f" ]] || { fail "required file missing: $f"; }
done
[[ -d "$REH" ]] || { fail "rehearsal root missing: $REH"; printf '\n=== git-data-rung2-rehearsal: %d passed, %d failed ===\n\n' "$passes" "$fails"; exit 1; }

# Comment-stripped HCL for every content assertion below.
REH_CODE="$(mktemp -t gdr2code.XXXXXXXX)" || exit 2
trap 'rm -f "$REH_CODE"' EXIT
sed 's/^[[:space:]]*#.*$//' "$REH"/*.tf > "$REH_CODE"

# ── 1. ROOT PURITY ─────────────────────────────────────────────────────────────────
n_prod=$(grep -cE 'hcloud_(server|volume|firewall)\.git_data\b|terraform_remote_state' "$REH_CODE" || true)
if [[ "$n_prod" -eq 0 ]]; then
  pass "the rehearsal root references NO production git-data address (comments stripped)"
else
  fail "the rehearsal root references ${n_prod} production git-data address(es)/remote state" \
    "$(grep -nE 'hcloud_(server|volume|firewall)\.git_data\b|terraform_remote_state' "$REH_CODE" | head -5)"
fi

# VERIFY-THE-VERIFIER. Without this, arm 1 is satisfied by a stripper that ate the whole
# file. Inject a violating line into a copy and require the same predicate to flip.
_mut="$(mktemp -t gdr2mut.XXXXXXXX)" || exit 2
{ cat "$REH_CODE"; printf 'volume_id = hcloud_volume.git_data.id\n'; } > "$_mut"
if [[ "$(grep -cE 'hcloud_(server|volume|firewall)\.git_data\b|terraform_remote_state' "$_mut" || true)" -ne 0 ]]; then
  pass "the purity predicate CAN fail (a synthetic prod reference is detected)"
else
  fail "the purity predicate is vacuous — a synthetic prod reference was not detected"
fi
rm -f "$_mut"

# THE ALLOWLIST FORM, not a deny-grep. A deny list enumerates the prod addresses someone
# thought of; the allowlist refuses anything that is not demonstrably rehearsal-scoped, which
# is the closed form. (The plan's original `grep -c … == 0` AC was BOTH false-failing on
# comments and blind to hcloud_volume.git_data_luks, doppler_service_token.git_data and five
# more — a deny list that had already missed seven addresses when it was written.)
_bad_addr=""
while IFS= read -r addr; do
  [[ -z "$addr" ]] && continue
  case "$addr" in
    rehearsal|rehearsal_*) ;;
    *) _bad_addr="${_bad_addr} ${addr}" ;;
  esac
done < <(grep -oE '^resource "(hcloud|doppler)_[a-z_]+" "[a-z0-9_]+"' "$REH_CODE" \
         | sed -E 's/.*" "([a-z0-9_]+)"$/\1/')
if [[ -z "$_bad_addr" ]]; then
  pass "every hcloud_*/doppler_* address in the rehearsal root is rehearsal-scoped"
else
  fail "non-rehearsal-scoped address(es) in the rehearsal root:${_bad_addr}"
fi

_n_addr=$(grep -cE '^resource "(hcloud|doppler)_[a-z_]+" "[a-z0-9_]+"' "$REH_CODE" || true)
if [[ "$_n_addr" -ge 10 ]]; then
  pass "the address enumeration is non-vacuous (${_n_addr} hcloud_*/doppler_* resources)"
else
  fail "only ${_n_addr} hcloud_*/doppler_* resources found (<10) — the extraction drifted, and an empty enumeration passes the allowlist arm above trivially"
fi

# ── 2. A DISTINCT STATE KEY — the control, not a guard ─────────────────────────────
reh_key="$(grep -oE '^[[:space:]]*key[[:space:]]*=[[:space:]]*"[^"]+"' "$REH_CODE" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
par_key="$(sed 's/^[[:space:]]*#.*$//' "$DIR/main.tf" | grep -oE '^[[:space:]]*key[[:space:]]*=[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
if [[ -n "$reh_key" && -n "$par_key" && "$reh_key" != "$par_key" ]]; then
  pass "the rehearsal backend key (${reh_key}) is DISTINCT from the parent root's (${par_key})"
else
  fail "the rehearsal and parent roots share a backend key, or one could not be extracted" \
    "rehearsal='${reh_key}' parent='${par_key}'"
fi

# ── 3. NO NETWORK ATTACHMENT (R2) ──────────────────────────────────────────────────
# Dropping the private-net attachment removes the leak vector structurally rather than
# guarding it. hcloud_firewall.git_data's own comment records that the firewall never covered
# the private surface anyway ("open by network membership"), so re-adding an attachment
# behind a deny-all firewall would restore the vector while looking like a control.
if ! grep -qE '^[[:space:]]*resource "hcloud_server_network"' "$REH_CODE"; then
  pass "the rehearsal root attaches to NO private network (R2)"
else
  fail "the rehearsal root declares hcloud_server_network — the prod private net is reachable from a rehearsal host"
fi

# ── 4. NO ignore_changes ANYWHERE ──────────────────────────────────────────────────
# The host is cattle by construction. Suppressing user_data drift in particular would let a
# rehearsal re-report a stale boot as a fresh one.
if ! grep -qE 'ignore_changes' "$REH_CODE"; then
  pass "the rehearsal root suppresses no drift (no ignore_changes)"
else
  fail "the rehearsal root carries ignore_changes — a stale boot could re-report as fresh"
fi

# ── 5. BOTH ROOTS CALL THE ONE MODULE ──────────────────────────────────────────────
# This is what makes the evidence meaningful: the bytes that boot on the rehearsal host are
# the same template and the same nine payloads the rung-2 gate hashes. If either root stopped
# calling the module, the hash would attest a render that root does not produce.
if grep -qE 'source[[:space:]]*=[[:space:]]*"\.\./modules/git-data-userdata"' "$REH_CODE"; then
  pass "the rehearsal root renders through the SHARED module"
else
  fail "the rehearsal root does not call ../modules/git-data-userdata — it would attest a render it does not produce"
fi
# Herestring, not a pipe: under pipefail an early match makes `sed | grep -q` return the
# producer's SIGPIPE rather than grep's success once the body passes 64 KiB (#6649).
_git_data_code="$(sed 's/^[[:space:]]*#.*$//' "$DIR/git-data.tf")"
if grep -qE 'source[[:space:]]*=[[:space:]]*"\./modules/git-data-userdata"' <<<"$_git_data_code"; then
  pass "the production root renders through the SAME shared module"
else
  fail "git-data.tf does not call ./modules/git-data-userdata"
fi

# ── 6. THE DIVERGENCE SET THE REHEARSAL PASSES IS THE SET THE GATE PERMITS ──────────
#
# The gate refuses any declared divergence outside its identity-only allowlist. The rehearsal
# root is what actually diverges. If the root diverged on a var the gate refuses, a perfect
# rehearsal would produce evidence that cannot release — a real host spent for nothing.
# shellcheck source=/dev/null
source "$GATE"
_module_block="$(awk '/^module "git_data_userdata"/{i=1} i{print} i&&/^}/{exit}' "$REH_CODE")"
# The vars the rehearsal binds to something OTHER than a var./literal shared with prod are
# the ones that diverge. Read them by shape from the block's own assignments.
_declared_div=""
while IFS= read -r k; do
  [[ -z "$k" ]] && continue
  case " $GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST " in
    *" $k "*) _declared_div="${_declared_div} ${k}" ;;
  esac
done < <(printf '%s\n' "$_module_block" | grep -oE '^[[:space:]]+[a-z_]+[[:space:]]*=' | tr -d ' =')
if [[ -n "$_declared_div" ]]; then
  pass "the rehearsal binds$(printf '%s' "$_declared_div") — all on the gate's divergence allowlist"
else
  fail "no allowlisted divergence var found in the rehearsal's module block — the extraction drifted"
fi

# The MUST-MATCH set is the sharp one: doppler_arch/doppler_sha256 select which binary is
# downloaded and which checksum verifies it, so a divergence there rehearses a different
# boot-brick surface than production has (#6570).
for _pin in doppler_arch doppler_sha256 sentry_dsn betterstack_ingest_url; do
  case " $GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST " in
    *" $_pin "*) fail "${_pin} is on the divergence allowlist — it changes WHAT the host does, not WHICH host it is" ;;
    *) pass "${_pin} is NOT permitted to diverge" ;;
  esac
done

# ── 7. THE BETTER STACK INGEST URL IS THE PRODUCTION ONE ───────────────────────────
#
# A SECOND COPY of a literal, so it is guarded rather than trusted. Both sides extracted BY
# SHAPE from their own file: a hardcoded expectation here would pass while prod moved.
reh_ingest="$(sed 's/^[[:space:]]*#.*$//' "$REH/variables.tf" \
  | awk '/^variable "betterstack_ingest_url"/{i=1} i&&/^[[:space:]]*default[[:space:]]*=/{print;exit} i&&/^}/{exit}' \
  | sed 's/.*"\([^"]*\)".*/\1/')"
prod_ingest="$(sed 's/^[[:space:]]*#.*$//' "$DIR/zot-registry.tf" \
  | grep -oE 'betterstack_logs_ingest_url[[:space:]]*=[[:space:]]*"[^"]+"' | head -1 \
  | sed 's/.*"\([^"]*\)"$/\1/')"
if [[ -n "$reh_ingest" && -n "$prod_ingest" && "$reh_ingest" == "$prod_ingest" ]]; then
  pass "the rehearsal's betterstack_ingest_url default matches production's literal"
else
  fail "betterstack ingest URL DRIFTED between the rehearsal default and prod's local" \
    "rehearsal='${reh_ingest}' prod='${prod_ingest}'"
fi

# ── 7b. MUST-MATCH DEFAULTS ARE COMPARED, NOT JUST DESCRIBED ───────────────────────
#
# Caught in review: `location` carried the description "MUST match prod's" and shipped as
# `fsn1` against production's `hel1`. Nothing compared them, so the rehearsal would have booted
# in the wrong datacenter and the evidence would have been silent about it. A description is
# not a guard.
#
# Both sides extracted BY SHAPE from their own variables.tf — a hardcoded expectation here
# would pass while production moved.
_var_default() {  # $1=file $2=variable name
  awk -v v="variable \"$2\"" '
    index($0,v){i=1; next}
    i && /^[[:space:]]*default[[:space:]]*=/{gsub(/[",]/,""); print $NF; exit}
    i && /^}/{exit}' "$1"
}
_mm_drift=""; _mm_checked=0
for _v in location git_data_server_type; do
  _rv="$(_var_default "$REH/variables.tf" "$_v")"
  _pv="$(_var_default "$DIR/variables.tf" "$_v")"
  [[ -z "$_rv" || -z "$_pv" ]] && continue
  _mm_checked=$((_mm_checked + 1))
  [[ "$_rv" != "$_pv" ]] && _mm_drift="${_mm_drift} ${_v}(rehearsal=${_rv},prod=${_pv})"
done
if [[ "$_mm_checked" -lt 2 ]]; then
  fail "MUST-MATCH default extraction found only ${_mm_checked} of 2 variables" \
    "the awk extraction drifted; an empty comparison is vacuous"
elif [[ -z "$_mm_drift" ]]; then
  pass "location and git_data_server_type defaults match production byte-for-byte"
else
  fail "a MUST-MATCH default DIVERGED from production:${_mm_drift}" \
    "the rehearsal would boot on different hardware/DC than the host it attests for"
fi

# ── 8. THE WORKFLOW CONTRACT ───────────────────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
  _wf_out="$(python3 - "$WF" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True) or d.get("on")
ins = on["workflow_dispatch"]["inputs"]
print("TRIGGERS=%s" % ",".join(sorted(on.keys())))
print("DRYRUN_DEFAULT=%s" % ins.get("dry_run", {}).get("default"))
print("TEARDOWN_PRESENT=%s" % ("dry_run" in ins and "teardown_only" in ins))
print("FAULT_INJECTION=%s" % ("fault_injection" in ins))
print("GROUP=%s" % d.get("concurrency", {}).get("group"))
print("CANCEL=%s" % d.get("concurrency", {}).get("cancel-in-progress"))
perms = d.get("permissions") or {}
print("PERMS=%s" % ",".join("%s:%s" % kv for kv in sorted(perms.items())))
j = d["jobs"]["rehearse"]
print("ENVIRONMENT=%s" % j.get("environment"))
unpinned = [s["uses"] for s in j["steps"]
            if "uses" in s and (("@" not in s["uses"]) or len(s["uses"].split("@")[1]) != 40)]
print("UNPINNED=%s" % ",".join(unpinned))
PY
)" || _wf_out=""

  _wf() { printf '%s\n' "$_wf_out" | sed -n "s/^$1=//p"; }

  [[ "$(_wf TRIGGERS)" == "workflow_dispatch" ]] \
    && pass "the rehearsal workflow is workflow_dispatch ONLY (no push/schedule can fire it)" \
    || fail "the rehearsal workflow has non-dispatch triggers: $(_wf TRIGGERS)"

  [[ "$(_wf DRYRUN_DEFAULT)" == "True" ]] \
    && pass "dry_run defaults to TRUE (a default-false makes 'just check the plan' spend a real host)" \
    || fail "dry_run does not default to true (got '$(_wf DRYRUN_DEFAULT)')"

  [[ "$(_wf TEARDOWN_PRESENT)" == "True" ]] \
    && pass "the teardown_only recovery arm exists (R12 — detection without recovery leaves a paying host)" \
    || fail "the teardown_only input is missing — teardown failure would have no automated remedy"

  [[ "$(_wf FAULT_INJECTION)" == "False" ]] \
    && pass "no fault_injection input (cut: injecting a fault alters what boots, so the output can never be evidence)" \
    || fail "a fault_injection input is present — it is incoherent with the hash binding"

  # THE CONCURRENCY LITERAL, compared against the birth jobs' rather than hardcoded. A
  # distinct group PERMITS a rehearsal and a birth to run at once, which inverts the point.
  _birth_groups=$(grep -cE '^[[:space:]]{6}group: git-data-state[[:space:]]*$' "$APPLY_WF" || true)
  if [[ "$(_wf GROUP)" == "git-data-state" && "$_birth_groups" -eq 2 ]]; then
    pass "the rehearsal JOINS the birth/replace concurrency group (git-data-state, ${_birth_groups} sibling jobs)"
  else
    fail "concurrency group mismatch: rehearsal='$(_wf GROUP)', sibling jobs on git-data-state=${_birth_groups}" \
      "GitHub does not error on divergent group strings — they silently fail to serialize"
  fi
  [[ "$(_wf CANCEL)" == "False" ]] \
    && pass "cancel-in-progress is false (cancelling mid-apply orphans a half-created host)" \
    || fail "cancel-in-progress is not false (got '$(_wf CANCEL)')"

  # THE STRUCTURAL NO-AUTO-COMMIT GUARANTEE. Evidence is the release artifact for the birth
  # interlock; a workflow that could push it to main would be self-approving.
  [[ "$(_wf PERMS)" == "contents:read" ]] \
    && pass "permissions are contents:read ONLY — the workflow structurally CANNOT commit its own evidence" \
    || fail "workflow permissions are '$(_wf PERMS)', not exactly contents:read — it may be able to commit the file that releases the birth interlock"

  [[ "$(_wf ENVIRONMENT)" == "web-platform-infra-apply" ]] \
    && pass "the job declares the reviewed environment (DP-11 F8: a zero-reviewer environment auto-approves)" \
    || fail "environment is '$(_wf ENVIRONMENT)', not web-platform-infra-apply"

  [[ -z "$(_wf UNPINNED)" ]] \
    && pass "every action is SHA-pinned" \
    || fail "unpinned action(s): $(_wf UNPINNED)"
else
  fail "python3 absent — the workflow-contract arms did NOT run" \
    "a gate that cannot run must not report success"
fi

# ── 9. THE CONFIRM TOKEN IS DISTINCT FROM THE BIRTH TOKEN ──────────────────────────
#
# So a token typed for a rehearsal can never authorize a birth, and vice versa.
#
# ANCHORED ON THE COMPARISON, NOT ON THE BARE TOKEN, and this suite MEASURED why: the first
# form here was `grep -q REHEARSE-GIT-DATA && ! grep -q BIRTH-GIT-DATA`, and it FAILED against
# a correct workflow — because the step's own error message explains that the token is
# "distinct from the birth path's BIRTH-GIT-DATA". A bare-token deny-grep cannot tell a
# comparison from the sentence explaining it, so it refuses the file for being documented.
# That is cq-assert-anchor-not-bare-token, caught by this suite on its own author.
if grep -qE '\!=[[:space:]]*"REHEARSE-GIT-DATA"' "$WF"; then
  pass "the rehearsal workflow COMPARES the confirm input against REHEARSE-GIT-DATA"
else
  fail "no confirm-token comparison against REHEARSE-GIT-DATA in the rehearsal workflow"
fi
if ! grep -qE '[=!]=[[:space:]]*"BIRTH-GIT-DATA"' "$WF"; then
  pass "the rehearsal workflow never COMPARES against the birth token (prose mentioning it is fine)"
else
  fail "the rehearsal workflow compares against BIRTH-GIT-DATA — a token typed for one path could authorize the other"
fi

# ── 10. THE PREFIX LITERAL AND ITS TRAILING HYPHEN ─────────────────────────────────
#
# Replicated across three files by necessity (a Terraform local, a workflow env, a scheduled
# sweep) and compared here rather than trusted. The TRAILING HYPHEN is the load-bearing part:
# `soleur-git-data` is a prefix of the rehearsal names, so a match written without it reports
# the PRODUCTION host as a leaked rehearsal.
_pfx_tf="$(grep -oE 'rehearsal_host_name[[:space:]]*=[[:space:]]*"[^"]*"' "$REH_CODE" | head -1 | sed 's/.*"\(.*\)"$/\1/')"
_pfx_wf="$(grep -oE '^[[:space:]]*REHEARSAL_PREFIX:[[:space:]]*\S+' "$WF" | head -1 | awk '{print $2}')"
_pfx_drift="$(grep -oE '^[[:space:]]*REHEARSAL_PREFIX:[[:space:]]*\S+' "$DRIFT_WF" | head -1 | awk '{print $2}')"
if [[ "$_pfx_wf" == "soleur-git-data-rehearsal-" && "$_pfx_drift" == "soleur-git-data-rehearsal-" ]]; then
  pass "the rehearsal prefix agrees in the dispatch workflow and the orphan sweep"
else
  fail "rehearsal prefix DRIFTED: workflow='${_pfx_wf}' drift-sweep='${_pfx_drift}'"
fi
for _p in "$_pfx_wf" "$_pfx_drift"; do
  case "$_p" in
    *-) : ;;
    *) fail "rehearsal prefix '${_p}' has NO trailing hyphen — it would also match the production host soleur-git-data" ;;
  esac
done
if [[ "$_pfx_wf" == *- && "$_pfx_drift" == *- ]]; then
  pass "both prefixes carry the load-bearing trailing hyphen"
fi
if [[ "$_pfx_tf" == *"rehearsal-\${var.rehearsal_run_id}"* ]]; then
  pass "the Terraform host name is prefix + run id (unique per rehearsal, so a leak cannot be adopted)"
else
  fail "the rehearsal host name is not prefix+run_id (got '${_pfx_tf}')"
fi

# ── 11. THE PARENT APPLY DOES NOT FIRE ON A REHEARSAL-ONLY EDIT (R10) ──────────────
if grep -qE '^[[:space:]]*-[[:space:]]*"!apps/web-platform/infra/rung2-rehearsal/\*\*"' "$APPLY_WF"; then
  pass "the parent apply's push filter EXCLUDES the rehearsal subdir (R10)"
else
  fail "apply-web-platform-infra.yml still fires on apps/web-platform/infra/** without excluding rung2-rehearsal/" \
    "a rehearsal-only edit would trigger a PRODUCTION apply of the parent root"
fi
# The module must NOT be excluded — the production host really does render from it, so an
# edit there is a genuine production change.
if grep -qE 'rung2-rehearsal' "$APPLY_WF" && ! grep -qE '!apps/web-platform/infra/modules' "$APPLY_WF"; then
  pass "modules/ is NOT excluded from the parent apply (the production host renders from it)"
else
  fail "the parent apply excludes modules/ — a real production render change would not trigger an apply"
fi

# ── 11b. PROVIDER VERSIONS ARE PINNED TO THE PARENT ROOT'S, NOT MERELY CONSTRAINED ──
#
# main.tf claims the rehearsal is "PINNED TO THE PARENT ROOT'S VERSIONS", and a `~> 1.49`
# CONSTRAINT does not deliver that — the LOCK does. Measured while building this: a fresh
# `terraform init` in the rehearsal root resolved hetznercloud/hcloud to 1.68.0 while the
# parent's lock pins 1.63.0, so the two roots would have rendered and attached under
# DIFFERENT provider versions while the ADR claimed they matched.
#
# Both sides extracted BY SHAPE from their own lock file; a hardcoded expectation here would
# pass while the parent moved. Compared over the INTERSECTION, since the parent legitimately
# carries providers this root does not (cloudflare, github, better-uptime).
_lock_par="$DIR/.terraform.lock.hcl"
_lock_reh="$REH/.terraform.lock.hcl"
if [[ ! -f "$_lock_par" || ! -f "$_lock_reh" ]]; then
  fail "a committed .terraform.lock.hcl is missing" "parent=${_lock_par} rehearsal=${_lock_reh}"
else
  _lock_ver() {  # $1=lockfile $2=provider path -> version
    awk -v p="provider \"registry.terraform.io/$2\" {" '
      index($0,p){i=1; next} i && /version[[:space:]]*=/{gsub(/[",]/,""); print $NF; exit}' "$1"
  }
  _drift=""; _checked=0
  for _prov in hetznercloud/hcloud hashicorp/random hashicorp/tls dopplerhq/doppler; do
    _pv="$(_lock_ver "$_lock_par" "$_prov")"
    _rv="$(_lock_ver "$_lock_reh" "$_prov")"
    [[ -z "$_pv" || -z "$_rv" ]] && continue
    _checked=$((_checked + 1))
    [[ "$_pv" != "$_rv" ]] && _drift="${_drift} ${_prov}(parent=${_pv},rehearsal=${_rv})"
  done
  if [[ "$_checked" -lt 4 ]]; then
    fail "provider-lock parity extraction found only ${_checked} shared provider(s) (<4)" \
      "the awk extraction drifted; an empty intersection makes the comparison below vacuous"
  elif [[ -z "$_drift" ]]; then
    pass "all ${_checked} shared provider versions are locked identically in both roots"
  else
    fail "provider-lock DRIFT between the rehearsal root and production:${_drift}" \
      "the rehearsal would render/attach under a different provider than the host it attests for"
  fi
fi

# ── 12. THE ORPHAN SWEEP EXISTS AND FAILS CLOSED ───────────────────────────────────
# `terraform plan` reports on resources IN STATE, so a host the rehearsal state has forgotten
# is invisible to every plan in this repository. Only Hetzner can see it.
if grep -q 'rung2-rehearsal-orphan-sweep' "$DRIFT_WF"; then
  pass "the scheduled drift workflow carries a rung-2 orphan sweep"
else
  fail "no rung-2 orphan sweep — a leaked rehearsal host would be invisible to every terraform plan"
fi
if grep -q 'api.hetzner.cloud/v1/servers' "$DRIFT_WF"; then
  pass "the sweep asks HETZNER, not terraform state (state cannot see what it has forgotten)"
else
  fail "the orphan sweep does not query the Hetzner API"
fi

# ── Minimum-cardinality floor ──────────────────────────────────────────────────────
# A floor, not an equality: developer-incremented, so `-eq` would redden the suite on every
# legitimately added arm and train the next person to bump it unread. Counts passes+fails so
# a genuine failure reports as a failure rather than as an empty suite.
_ran=$((passes + fails))
if [[ "$_ran" -lt 28 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 28. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 28)\n' "$_ran"
fi

printf '\n=== git-data-rung2-rehearsal: %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
