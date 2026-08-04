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
trap 'rm -f "$REH_CODE" "${DRIFT_CODE:-}"' EXIT
sed 's/^[[:space:]]*#.*$//' "$REH"/*.tf > "$REH_CODE"

# ── 1. ROOT PURITY ─────────────────────────────────────────────────────────────────
#
# THE ALLOWLIST COVERS DECLARATIONS; `data`/`import`/`moved` REACH PRODUCTION WITHOUT ONE.
# Measured (#7066 review): appending
#   data "doppler_secrets" "prod_git_data" { project = "soleur"  config = "prd_git_data" }
# to rehearsal.tf left this suite 39/0 green while pulling production's GIT_DATA_LUKS_KEY
# into the rehearsal tfstate. `data` blocks resolve cross-root; managed `resource` references
# do not, which is why this is the live half. `import`/`moved` adopt production state into
# this root and carry no address the allowlist can score, so they are refused outright.
_adopt=$(grep -cE '^[[:space:]]*(import|moved)[[:space:]]*\{' "$REH_CODE" || true)
if [[ "$_adopt" -eq 0 ]]; then
  pass "the rehearsal root declares no import/moved block (it cannot adopt production state)"
else
  fail "the rehearsal root declares ${_adopt} import/moved block(s)" \
    "these adopt existing state into this root and are invisible to the address allowlist"
fi
# NO `\b` AFTER `git_data`. In an ERE `\b` is a word BOUNDARY and `_` is a word
# character, so `git_data\b` does not match `git_data_luks` — the production LUKS volume,
# which lines 87-89 of rehearsal.tf specifically name as an address this guard must catch.
# Dropping the anchor is safe here because every legitimate address in this root is
# `rehearsal`-scoped, so there is nothing beginning `git_data` that belongs.
n_prod=$(grep -cE 'hcloud_(server|volume|firewall)\.git_data|terraform_remote_state' "$REH_CODE" || true)
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
done < <(grep -oE '^[[:space:]]*(resource|data)[[:space:]]+"(hcloud|doppler)_[a-z_]+"[[:space:]]+"[a-z0-9_]+"' "$REH_CODE" \
         | sed -E 's/.*" *"([a-z0-9_]+)"$/\1/')
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

# The MUST-MATCH set is the sharp one: these change WHAT the host does, not WHICH host it is.
# `git_data_server_type` heads the list because the module derives the Doppler download arch
# AND its checksum from it (#7025 R7) — a divergence there rehearses a different boot-brick
# surface than production has (#6570).
#
# doppler_arch/doppler_sha256 are deliberately ABSENT: R7 removed them from the module's
# variable surface entirely, so pinning them here would assert that two names which can no
# longer exist are not on an allowlist — two arms that pass and can never meaningfully fail.
# 7d pins their absence structurally; this loop pins the inputs that DO exist.
for _pin in git_data_server_type sentry_dsn betterstack_ingest_url; do
  case " $GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST " in
    *" $_pin "*) fail "${_pin} is on the divergence allowlist — it changes WHAT the host does, not WHICH host it is" ;;
    *) pass "${_pin} is NOT permitted to diverge" ;;
  esac
done

# VARS WHOSE VALUE-PARITY IS PROVEN BELOW, accumulated BY THE PASSING ARM rather than
# declared. 7c compares the two roots' module bindings as TEXT, and two separate Terraform
# roots cannot reach a shared value by the same expression — the rehearsal reads `var.X`
# where production reads `local.Y`. Those are expression divergences that are not value
# divergences, and the arms below are what establish the difference. Granting the exemption
# from the proof (not from a literal) keeps it fail-closed: if arm 7 fails, betterstack is
# NOT exempt and 7c fails too, rather than one arm quietly excusing the other.
_value_proven=""

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
  _value_proven="${_value_proven} betterstack_ingest_url"
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
# COMMENTS STRIPPED, BLOCK HEADER ANCHORED, and the value taken from the ASSIGNMENT rather
# than from `$NF`. All three were live defects in the first version of this helper:
#
#   default = "fsn1" # must equal production hel1
#
# made `$NF` (after `gsub(/[",]/,"")`) evaluate to `hel1` — the comment's last word — so the
# guard reported "match production byte-for-byte" while the rehearsal was pinned to fsn1.
# Measured: 35/0 green with the divergence live. That is the exact defect this arm was added
# to catch, re-enabled by the single most likely accompanying edit (documenting the intended
# value). `index($0,v)` was also unanchored, so `variable "location_extra"` would match.
_var_default() {  # $1=file $2=variable name
  sed 's/[[:space:]]#.*$//' "$1" \
    | awk -v v="^variable \"$2\" \\{" '
        $0 ~ v {i=1; next}
        i && /^[[:space:]]*default[[:space:]]*=/{
          sub(/^[^=]*=[[:space:]]*/, ""); gsub(/[",[:space:]]/, ""); print; exit
        }
        i && /^}/{exit}'
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
  # DELIBERATELY NOT added to _value_proven. This arm compares variables.tf DEFAULTS; 7c
  # compares module BINDINGS. Granting a binding-level exemption on the strength of a
  # default-level proof is a category error, and `git_data_server_type` became a module
  # binding in this very change — so adding it here (which an earlier revision did, for
  # "consistency") put the one var that selects the download arch into 7c's exemption shadow.
  pass "location and git_data_server_type defaults match production byte-for-byte"
else
  fail "a MUST-MATCH default DIVERGED from production:${_mm_drift}" \
    "the rehearsal would boot on different hardware/DC than the host it attests for"
fi

# sentry_dsn IS COMPARED TOO. It is the fourth MUST-MATCH member and, until this arm, the one
# nothing checked: 7c sees `var.sentry_dsn` on both sides and calls that agreement, while a
# `default` on the rehearsal root's variable would silently point the fatal channel — the very
# channel the rehearsal exists to prove — at a different Sentry project. Both roots must leave
# it defaulted to the same value (prod's is ""), so the workflow's injected var is the only
# source. The suite header's own thesis applies: a description is not a guard.
_reh_dsn="$(_var_default "$REH/variables.tf" sentry_dsn)"
_prod_dsn="$(_var_default "$DIR/variables.tf" sentry_dsn)"
if [[ "$_reh_dsn" == "$_prod_dsn" ]]; then
  pass "sentry_dsn defaults agree between the two roots (the fatal channel cannot be silently re-pointed)"
else
  fail "the rehearsal's sentry_dsn default DIVERGED from production's" \
    "rehearsal='${_reh_dsn}' prod='${_prod_dsn}' — the rehearsal would prove a fatal channel production does not use"
fi

# ── 7c. THE DECLARED DIVERGENCE SET MATCHES WHAT ACTUALLY DIVERGES ─────────────────
#
# THE TAUTOLOGY, THIRD ATTEMPT. R6 refuses declared-divergence outside an identity-only
# allowlist. That is only meaningful if the DECLARED set tracks reality: the capture script
# originally echoed the allowlist back (allowlist ⊆ allowlist), the fix moved the literal
# into the workflow, and the workflow literal was then set byte-identical to the whole
# allowlist — so the tautology moved rather than closed. Measured both times.
#
# This arm DERIVES the divergence set: for every var the two roots' module blocks both
# bind, compare the bound expressions; the vars whose expressions differ ARE the
# divergence. Then assert the workflow's declared set equals it. A new divergence on a
# non-identity var (sentry_dsn, git_data_server_type) now changes the derived set, this arm
# fails, and the author must declare it — at which point R6 refuses it. The loop is closed by
# comparison against the artifacts, not by a literal anyone can edit to agree with itself.
#
# TWO KEYS ARE EXCLUDED, and neither exclusion is a hole — each is pinned harder elsewhere,
# which is the only reason it may be dropped here:
#
#   source — a module META-ARGUMENT, not a templatefile argument. The divergence set records
#     which ARGUMENTS the rehearsal diverged on (the axis the evidence hash does not bind);
#     `source` selects the module itself, and both roots' values are asserted by NAME above
#     (`../modules/git-data-userdata` and `./modules/git-data-userdata`), which is a stricter
#     check than "these two strings differ". Left in, it would sit in the derived set forever
#     and could only be silenced by declaring it — putting a non-identity key on the
#     allowlist R6 exists to keep closed.
#
#   value-proven vars — a second Terraform root cannot reference the parent root's `local`,
#     so `betterstack_ingest_url = var.betterstack_ingest_url` against
#     `= local.betterstack_logs_ingest_url` is an expression divergence that is NOT a value
#     divergence. Arm 7 compares the two VALUES; the exemption is granted by that arm passing
#     (see _value_proven), so a drift in the value fails arm 7 AND unexempts the var here.
# CONTINUATION-JOINED, because the tokenizer IS the membership rule. The first version read
# one physical line per binding, so any binding split across lines was invisible to the
# comparison — not flagged, not counted, silently exempt. Measured: writing
# `sentry_dsn = coalesce(` + a differing second line in the rehearsal root only left this arm
# reporting "the declared divergence set equals what actually diverges (11 vars compared)"
# while the two roots rendered DIFFERENT Sentry DSNs — a var the module's own variables.tf
# labels MUST MATCH PROD BYTE-FOR-BYTE. The same divergence written on one line was caught.
# The blindness was the tokenizer, not the arm's logic, which is the whole point: a claim
# about "every binding" enforced over "every binding I can lex" is a claim about my lexer.
#
# Bracket depth is tracked so a multi-line call/object collapses into its single logical
# binding, and an unbalanced tail fails the arm loudly rather than emitting a phantom key.
_module_binds() {  # $1 = .tf containing a `module "git_data_userdata"` block -> "key=expr" lines
  sed 's/[[:space:]]#.*$//' "$1" \
    | awk '
        /^module "git_data_userdata"/{i=1; next}
        # `k=""` before exit is load-bearing: awk RUNS THE END BLOCK on `exit`, so printing
        # here and again in END emitted the final binding TWICE — which then double-counted
        # it downstream (measured: the exemption set read betterstack,betterstack).
        i && /^}/{ if (k != "") print k "=" e; k=""; exit }
        i {
          line=$0
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
          if (line == "") next
          if (d == 0 && line ~ /^[a-z_]+[[:space:]]*=/) {
            if (k != "") print k "=" e
            k=line; sub(/[[:space:]]*=.*$/, "", k)
            e=line; sub(/^[^=]*=[[:space:]]*/, "", e)
          } else if (k != "") {
            e = e " " line
          }
          n=gsub(/[({[]/, "&", line); m=gsub(/[)}\]]/, "&", line)
          d += n - m
          if (d < 0) d = 0
        }
        END { if (k != "") print k "=" e }' | sort
}
_reh_binds="$(_module_binds "$REH/rehearsal.tf")"
_prod_binds="$(_module_binds "$DIR/git-data.tf")"

# THE CALLER→MODULE BINDING IS PINNED SEPARATELY, and this is the assertion whose absence was
# the sharpest finding of the #7025 R7 review. A16b (git-data-luks.test.sh) compares the two
# arch ternaries as TEXT — and both sides literally spell `var.git_data_server_type`, in
# DIFFERENT SCOPES. Text equality of the expressions says nothing about equality of their
# inputs, so nothing observed what each root actually BINDS into the module.
#
# Measured on a sandbox: changing only `git_data_server_type = "cax11"` at the two call sites,
# with the roots' own `server_type` left at cpx22, kept BOTH suites fully green (luks 101/0,
# rung2 38/0) while the module derived arm64, downloaded the arm64 Doppler tarball, and
# verified it against the CORRECT arm64 checksum. The phantom-arch precondition passed too —
# it reads the root local, which was still amd64. The result is an arm64 ELF on an x86 host:
# `doppler` never execs, so the `doppler run` heredoc holding `cryptsetup luksFormat` runs
# zero times and the host boots dark. That is #6570 verbatim, through the one seam the R7
# module extraction opened: A18 used to pin `doppler_arch = local.git_data_arch` IN git-data.tf
# and thereby guarded this edge incidentally; moving it into the module left the edge bare.
_bind_drift=""
for _f in "$DIR/git-data.tf" "$REH/rehearsal.tf"; do
  grep -qE '^[[:space:]]*git_data_server_type[[:space:]]*=[[:space:]]*var\.git_data_server_type[[:space:]]*$' \
    <(sed 's/[[:space:]]#.*$//' "$_f") \
    || _bind_drift="${_bind_drift} $(basename "$_f")"
done
if [[ -z "$_bind_drift" ]]; then
  pass "both roots bind git_data_server_type = var.git_data_server_type into the module (the arch the precondition validates IS the arch the module derives)"
else
  fail "a root does not bind git_data_server_type from its own var:${_bind_drift}" \
    "the module would derive an arch the caller's phantom-arch precondition never validates — #6570 with the tripwire green"
fi

# LEG 3: THE SERVER'S OWN `server_type`. The arm above pins var -> MODULE; the phantom-arch
# precondition pins var -> DATA SOURCE. Both legs key on `var.git_data_server_type`, and
# NEITHER says anything about the type the server is actually CREATED with — a third,
# independent reference to the same var.
#
# Measured on a sandbox: pinning `server_type = "cax11"` on hcloud_server.git_data while the
# var stayed cpx22 kept git-data-luks.test.sh at 101/0. The data source still reads the var
# (cpx22 -> x86), the module still derives amd64, so the precondition compares x86 == x86 and
# passes; the host is ARM and downloads the amd64 tarball, which verifies against the amd64
# checksum the same wrong derivation selected. #6570 verbatim, every guard green — the
# identical class the arm above closed, through the leg it did not cover.
#
# `^[[:space:]]*server_type` cannot match the module-input line, which starts with
# `git_data_server_type`. Scoped to the hcloud_server block so a match elsewhere in the root
# cannot satisfy it, and comment-stripped (trailing form included) so prose cannot either.
_srv_drift=""
for _pair in "$DIR/git-data.tf:git_data" "$REH/rehearsal.tf:rehearsal"; do
  _f="${_pair%%:*}"; _res="${_pair##*:}"
  _blk="$(sed 's/[[:space:]]#.*$//; s/^[[:space:]]*#.*$//' "$_f" \
          | awk -v r="$_res" '$0 ~ "^resource \"hcloud_server\" \""r"\"" {i=1} i; i&&/^}/{exit}')"
  if [[ -z "$_blk" ]]; then
    _srv_drift="${_srv_drift} $(basename "$_f")(no hcloud_server.${_res} block)"
  elif ! printf '%s\n' "$_blk" | grep -qE '^[[:space:]]*server_type[[:space:]]*=[[:space:]]*var\.git_data_server_type[[:space:]]*$'; then
    _srv_drift="${_srv_drift} $(basename "$_f")"
  fi
done
if [[ -z "$_srv_drift" ]]; then
  pass "both roots create the server with server_type = var.git_data_server_type (the arch validated IS the arch the host is born on)"
else
  fail "a root pins its server_type independently of its own var:${_srv_drift}" \
    "the host would be born on a type the precondition never validated — #6570 with every guard green"
fi

_derived=""
_common=0
_exempted_keys=""
_onesided=""
while IFS= read -r _line; do
  [[ -z "$_line" ]] && continue
  _k="${_line%%=*}"; _rexpr="${_line#*=}"
  # `source` is a module META-ARGUMENT, not a templatefile argument, and both roots' values
  # are asserted BY NAME in arm 5 — a stricter check than "these two strings differ".
  [[ "$_k" == "source" ]] && continue
  _pexpr="$(printf '%s\n' "$_prod_binds" | grep -E "^${_k}=" | head -1 | sed "s/^${_k}=//")"
  # A ONE-SIDED binding is a divergence, not a skip. The original `continue` meant any input
  # the rehearsal overrides and production does not (or vice versa) never entered _derived,
  # never entered _common, and so could never reach REHEARSAL_DIVERGENCE for R6 to refuse.
  if [[ -z "$_pexpr" ]]; then
    _onesided="${_onesided} ${_k}"
    _derived="${_derived}${_derived:+,}${_k}"
    continue
  fi
  _common=$((_common + 1))
  if [[ "$_rexpr" != "$_pexpr" ]]; then
    case " $_value_proven " in
      *" $_k "*) _exempted_keys="${_exempted_keys} ${_k}" ;;
      *) _derived="${_derived}${_derived:+,}${_k}" ;;
    esac
  fi
done <<< "$_reh_binds"
# Production-side one-sided bindings too — the loop above only walks the rehearsal's keys.
while IFS= read -r _line; do
  [[ -z "$_line" ]] && continue
  _k="${_line%%=*}"
  [[ "$_k" == "source" ]] && continue
  printf '%s\n' "$_reh_binds" | grep -qE "^${_k}=" && continue
  _onesided="${_onesided} ${_k}"
  _derived="${_derived}${_derived:+,}${_k}"
done <<< "$_prod_binds"
# PIN THE EXEMPTION SET, NOT ITS CARDINALITY. A count catches the set GROWING; it does not
# catch the slot being REASSIGNED. Measured: making the rehearsal's betterstack binding
# byte-identical to production's (so it stops being divergent and frees the slot) while
# diverging git_data_server_type left `_exempted == 1` and the whole suite green, with the
# rehearsal deriving arm64 and production amd64 — the exemption transferred to a var whose
# value-parity proof (arm 7b, over variables.tf DEFAULTS) says nothing about a BINDING that
# references neither default.
_exempted_sorted="$(printf '%s' "${_exempted_keys# }" | tr ' ' '\n' | sort | paste -sd, - )"
if [[ "$_exempted_sorted" != "betterstack_ingest_url" && -n "$_exempted_sorted" ]]; then
  fail "the value-proven exemption was consumed by an unexpected var: ${_exempted_sorted}" \
    "only betterstack_ingest_url's exemption is justified (arm 7 compares its VALUES); every other var must diverge into the declared set"
fi
if [[ -n "$_onesided" ]]; then
  fail "module input(s) bound by only ONE root:${_onesided}" \
    "a one-sided binding is a render divergence; counted into the derived set so R6 must refuse it rather than never seeing it"
fi
_declared="$(grep -oE '^[[:space:]]*REHEARSAL_DIVERGENCE:[[:space:]]*\S+' "$WF" | head -1 | awk '{print $2}')"
# Sort both sides: the derived set comes out of `sort`, the declared literal is hand-ordered.
_derived_sorted="$(printf '%s' "$_derived" | tr ',' '\n' | sort | paste -sd, -)"
_declared_sorted="$(printf '%s' "$_declared" | tr ',' '\n' | sort | paste -sd, -)"
if [[ "$_common" -lt 8 ]]; then
  fail "module-binding comparison found only ${_common} shared var(s) (<8)" \
    "the awk extraction drifted; an empty comparison makes this arm vacuous"
elif [[ "$_derived_sorted" == "$_declared_sorted" ]]; then
  pass "the workflow's declared divergence set equals what actually diverges (${_common} vars compared)"
else
  fail "REHEARSAL_DIVERGENCE does not match the actual divergence between the two module blocks" \
    "declared=${_declared_sorted} derived=${_derived_sorted}"
fi

# ── 7d. THE DOPPLER CHECKSUM PAIR IS UNEXPRESSIBLE PER-ROOT, NOT MERELY EQUAL ──────
#
# The defect: each root derived doppler_arch/doppler_sha256 with its OWN ternary and passed
# the result in, so the checksum literals existed in git-data.tf AND in rehearsal.tf,
# compared by nothing. The existing A15 parity predicate reads the canon sites
# (inngest-host.tf, zot-registry.tf) — never this root. Measured: a Doppler version bump
# applied to git-data.tf alone left EVERY suite green (54/0, 28/0, 35/0, 97/0, 129/0) while
# the rehearsal downloaded and verified a DIFFERENT binary than production. That is the
# #6570 boot-brick class, in the rehearsal that exists to rule it out, and R6 cannot see it
# either because doppler_sha256 is not a divergence anyone declares.
#
# The fix DERIVES the pair inside the shared module, so this arm asserts the STRUCTURAL
# property rather than an equality between two copies: the literals live in the module and
# in neither caller, and the pair is not on the module's variable surface — so a caller
# cannot reintroduce the divergence even by trying, and it can never appear in
# RUNG2_VAR_DIVERGENCE. An equality check between two copies would still pass the day
# someone adds a third.
# GLOBBED, NOT ENUMERATED, and COMMENT-STRIPPED. Both were live holes. The first version read
# exactly three named files, so appending a `locals` block holding a divergent 64-hex to
# rung2-rehearsal/main.tf — or a 64-hex output to the module's outputs.tf — satisfied it at
# 38/0; and it did not strip comments, contradicting this file's own header, so gutting the
# real derivation while leaving both literals in a trailing comment also passed. A claim
# quantified over "anywhere in either root" cannot be enforced over three filenames.
_shas() { sed 's/[[:space:]]#.*$//' "$@" 2>/dev/null | grep -oE '[0-9a-f]{64}' | sort -u; }
_n_mod="$(_shas "$MOD"/*.tf | grep -c . || true)"
_n_reh="$(_shas "$REH"/*.tf | grep -c . || true)"
_n_prod="$(_shas "$DIR"/git-data.tf | grep -c . || true)"
if [[ "$_n_mod" -ne 2 ]]; then
  fail "the shared module carries ${_n_mod} distinct sha256 literal(s) across its *.tf; the per-arch Doppler pair is exactly 2" \
    "either the derivation left the module (each caller is then an uncompared copy) or a third literal joined it"
elif [[ "$_n_reh" -ne 0 || "$_n_prod" -ne 0 ]]; then
  fail "a caller root carries a sha256 literal (rehearsal=${_n_reh} prod=${_n_prod}); both must be 0" \
    "a per-root literal is a copy nothing compares — the exact shape that let a version bump land on one root only"
else
  pass "the Doppler checksum pair exists exactly once, in the shared module's *.tf, and nowhere in either caller root"
fi
# THE MODULE'S INPUT SURFACE IS PINNED WHOLE, not screened against two forbidden names.
#
# The first version grepped for `variable "doppler_arch"|"doppler_sha256"` — a two-name
# DENY-LIST behind a claim of unexpressibility. Measured: adding `variable "doppler_sha256_pin"`
# and threading it through a nested ternary in the module reopened the exact divergence at
# 38/0, because a deny-list only ever refuses the names someone already thought of. A deny
# list cannot make anything unexpressible; only a closed input surface can. Any NEW module
# input is now RED until it is added here deliberately — which is the point at which someone
# has to argue that it may diverge, in front of R6's identity-only allowlist.
# `[A-Za-z0-9_-]`, NOT `[a-z_]`. The first version's character class had no DIGITS, so the
# very mutation this arm exists to catch — `variable "doppler_sha256_pin"` — did not match the
# extraction at all and the arm reported "exactly the pinned 11" against a 12-input module.
# Measured. Terraform identifiers admit digits, hyphens and capitals; a pin whose pattern is
# narrower than the namespace it pins is a pin over the names I happened to imagine, which is
# the same defect one level down as the two-name deny-list this arm replaced.
#
# The trailing count check is the non-vacuity control: an extraction that silently matched
# NOTHING would compare "" against the expected list and fail loudly, but an extraction that
# matched a SUBSET is exactly what the digit hole produced, so the count is asserted too.
_mod_var_names="$(sed 's/[[:space:]]#.*$//' "$MOD"/*.tf 2>/dev/null \
  | grep -oE '^variable "[A-Za-z0-9_-]+"' | sed -E 's/^variable "//; s/"$//' | sort | paste -sd, -)"
_mod_var_declared="$(sed 's/[[:space:]]#.*$//' "$MOD"/*.tf 2>/dev/null | grep -cE '^variable "' || true)"
_mod_var_extracted="$(printf '%s' "$_mod_var_names" | tr ',' '\n' | grep -c . || true)"
if [[ "$_mod_var_declared" -ne "$_mod_var_extracted" ]]; then
  fail "the module-input extraction saw ${_mod_var_extracted} of ${_mod_var_declared} declared variable blocks" \
    "the name pattern is narrower than the identifiers actually in use; the set comparison below would be over a subset"
fi
_mod_var_expected="betterstack_ingest_url,doppler_config_name,doppler_token,git_data_luks_volume_id,git_data_server_type,git_data_volume_id,git_provision_pubkey,git_remove_pubkey,git_transport_pubkey,host_name,sentry_dsn"
if [[ "$_mod_var_names" == "$_mod_var_expected" ]]; then
  pass "the module's input surface is exactly the pinned 11 — no doppler arch/checksum input exists, and no new input can appear unreviewed"
else
  fail "the module's input surface drifted from the pinned set" \
    "expected=${_mod_var_expected} actual=${_mod_var_names}"
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
# JOB-LEVEL permissions OVERRIDE workflow-level, and EVERY job counts. Measured (#7066
# review): adding `permissions: {contents: write}` to the rehearse job, and separately
# appending a whole second job that git-commits the evidence, each left this suite 39/0 green
# while it printed "structurally CANNOT commit its own evidence". Merge the workflow-level map
# with every job-level map so any write scope anywhere is visible.
perms = dict(d.get("permissions") or {})
for _jn, _j in (d.get("jobs") or {}).items():
    for _k, _v in (_j.get("permissions") or {}).items():
        perms["%s@%s" % (_k, _jn)] = _v
print("PERMS=%s" % ",".join("%s:%s" % kv for kv in sorted(perms.items())))
print("JOBS=%s" % ",".join(sorted((d.get("jobs") or {}).keys())))
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
  # The map now merges workflow-level with EVERY job-level block, so a job-scoped
  # `contents: write` shows up as `contents@<job>:write` and breaks this exact-match.
  [[ "$(_wf PERMS)" == "contents:read" ]] \
    && pass "permissions are contents:read ONLY — the workflow structurally CANNOT commit its own evidence" \
    || fail "workflow permissions are '$(_wf PERMS)', not exactly contents:read — it may be able to commit the file that releases the birth interlock"
  # AND THE JOB SET IS PINNED. Every job-scoped arm below reads d["jobs"]["rehearse"], so an
  # APPENDED job is unexamined by all of them: measured, a second job carrying contents:write,
  # an unpinned checkout, no environment, and `git commit && git push` left this suite green.
  # A new job is a deliberate change; it should have to come here and say so.
  [[ "$(_wf JOBS)" == "rehearse" ]] \
    && pass "the workflow declares exactly one job (rehearse) — no unexamined sibling job" \
    || fail "the workflow declares jobs '$(_wf JOBS)', expected exactly 'rehearse'" \
         "every job-scoped assertion in this suite reads the rehearse job only, so a sibling job is unexamined"

  [[ "$(_wf ENVIRONMENT)" == "web-platform-infra-apply" ]] \
    && pass "the job declares the reviewed environment (DP-11 F8: a zero-reviewer environment auto-approves)" \
    || fail "environment is '$(_wf ENVIRONMENT)', not web-platform-infra-apply"

  [[ -z "$(_wf UNPINNED)" ]] \
    && pass "every action is SHA-pinned" \
    || fail "unpinned action(s): $(_wf UNPINNED)"

  # ── 13. THE CAPTURE POLL ACTUALLY POLLS (behavioural — this arm EXECUTES the step) ──
  #
  # THE 43 ASSERTIONS THAT PRECEDED THIS ARM WERE ALL GREEN AGAINST A POLL THAT COULD NOT
  # POLL. Measured (production run 30560266736, dry_run=false): the capture step printed
  # exactly one `--- capture attempt 1/20 ---` and exited 2 FOUR SECONDS after it started.
  # GitHub invokes a bare `run:` as `bash -e {0}`, and the step's own `set -uo pipefail` does
  # NOT clear that inherited -e — omitting a flag from `set` cannot unset what the invocation
  # already applied. With pipefail on, the TRANSIENT rc=2 that this poll EXISTS to retry
  # killed the step on attempt 1. Everything after the pipeline was dead code on that path:
  # the PIPESTATUS read, the doppler-auth-vs-boot sentinel, attempts 2..20, the deadline
  # break, capture_rc, the whole summary block, and `exit "$rc"`. Confirmed downstream — the
  # upload step evaluated `steps.capture.outputs.capture_rc == '0'` against an EMPTY string.
  #
  # A NAIVE TEXT GUARD CANNOT SEE THIS. Measured: grep counts for `seq 1 N`, `PIPESTATUS`
  # and `capture_rc` are IDENTICAL (1/1/1) in the fixed body and the broken one. A CAREFUL
  # text guard can — arm 13d, below, catches both known shapes statically. What only an
  # EXECUTING guard catches is an arbitrary NEW errexit landmine anywhere in this body, and
  # given this rule has now recurred despite four learnings and eight in-workflow comments,
  # the next instance will not be a PIPESTATUS-adjacency violation.
  #
  # KEYED ON `id: capture`, NOT THE STEP NAME. The name is free text with zero consumers, so
  # keying on it would make this guard one cosmetic rename away from a spurious red. The id
  # is load-bearing: the upload step gates on `steps.capture.outputs.capture_rc`, so renaming
  # it breaks the workflow visibly and independently of this suite.
  #
  # THESE ARMS SHARE THE BODY'S HARDCODED /tmp/rung2 and therefore CANNOT RUN CONCURRENTLY
  # with each other or with a real dispatch on the same runner. Each clears it first.
  _CAP_RUNROOT="$(mktemp -d -t gdr2runs.XXXXXXXX)" || exit 2
  trap 'rm -f "$REH_CODE" "${DRIFT_CODE:-}"; rm -rf "${_CAP_RUNROOT:-}"' EXIT
  _cap_body="$(mktemp -t gdr2cap.XXXXXXXX)" || exit 2
  _cap_env="$(mktemp -t gdr2env.XXXXXXXX)" || exit 2
  python3 - "$WF" "$_cap_body" "$_cap_env" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
j = d["jobs"]["rehearse"]
step = next((s for s in j["steps"] if s.get("id") == "capture"), None)
if step is None or not step.get("run"):
    sys.exit(3)
open(sys.argv[2], "w").write(step["run"])
# The env is DERIVED from workflow|job|step scope rather than hardcoded: the seven values the
# body reads come from three different places (REHEARSAL_DIVERGENCE is workflow-level,
# REHEARSAL_HOST is step-level, the GITHUB_* are runner-provided), so a single added `env:`
# reference would otherwise fail the arm under `set -u` pointing at the wrong thing.
env = {}
for scope in (d.get("env") or {}, j.get("env") or {}, step.get("env") or {}):
    env.update(scope)
with open(sys.argv[3], "w") as fh:
    for k, v in sorted(env.items()):
        v = str(v)
        if "${{" in v:            # a runner-substituted expression -> fixture placeholder
            v = "fixture-" + k.lower()
        fh.write("%s='%s'\n" % (k, v.replace("'", "'\\''")))
PY
  _cap_extract_rc=$?

  if [[ "$_cap_extract_rc" -ne 0 || ! -s "$_cap_body" ]]; then
    fail "could not extract the capture step body keyed on 'id: capture'" \
      "an empty extraction must FAIL, never silently skip — the upload step gates on steps.capture.outputs.capture_rc, so that id is load-bearing"
  else
    # Executes the extracted body under `bash -e` (what GitHub actually uses) with `doppler`
    # and `sleep` stubbed on PATH. EXECUTED, never sourced: `deadline=$(( SECONDS + 16*60 ))`
    # reads the shell's own SECONDS, and sourcing would leak this suite's elapsed time and
    # could fire the deadline immediately.
    # Echoes: "<exit>|<attempt-count>|<stub-invocations>|<outdir>".
    _run_capture() {
      local body="$1" mode="$2" outdir rc attempts invocations
      # Under ONE reaped root. An un-removed `mktemp -d` per call leaked ~6 dirs per suite
      # run into TMPDIR, and this suite runs on every infra-validation.
      outdir="$(mktemp -d -p "$_CAP_RUNROOT" run.XXXXXXXX)" || return 2
      mkdir -p "$outdir/bin"
      {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'n=$(( $(cat "$STUB_COUNT" 2>/dev/null || echo 0) + 1 )); printf "%s" "$n" > "$STUB_COUNT"'
        printf '%s\n' 'case "$STUB_MODE" in'
        # TRANSIENT twice, then PASS — so a body that stops early can never reach the PASS.
        printf '%s\n' '  pass_on_3) if [ "$n" -lt 3 ]; then echo "RUNG2_CAPTURE_VERDICT=2"; exit 2; fi'
        printf '%s\n' '             echo "RUNG2_CAPTURE_VERDICT=0"; exit 0 ;;'
        # A wrapper auth failure: rc=1 and NO verdict sentinel, which is exactly how the
        # step's own comment says doppler reports a bad token.
        printf '%s\n' '  wrapper_auth) echo "doppler: unable to authenticate"; exit 1 ;;'
        # A GENUINE HOST FAIL: rc=1 WITH the sentinel. It differs from wrapper_auth by exactly
        # the byte the sentinel block keys on, which is why the FAIL branch needs its own
        # fixture: without one, deleting the sentinel test reports a real host failure as a
        # credential problem and nothing reds.
        printf '%s\n' '  host_fail) echo "RUNG2_CAPTURE_VERDICT=1"; exit 1 ;;'
        # ONE wrapper blip, then a real verdict. The far-side-of-the-fast-fail fixture: the
        # only shape that can show the fast-fail is not TOO aggressive.
        printf '%s\n' '  blip_then_pass) if [ "$n" -eq 1 ]; then echo "doppler: transient"; exit 1; fi'
        printf '%s\n' '                  if [ "$n" -eq 2 ]; then echo "RUNG2_CAPTURE_VERDICT=2"; exit 2; fi'
        printf '%s\n' '                  echo "RUNG2_CAPTURE_VERDICT=0"; exit 0 ;;'
        printf '%s\n' 'esac'
      } > "$outdir/bin/doppler"
      printf '%s\n%s\n' '#!/usr/bin/env bash' 'exit 0' > "$outdir/bin/sleep"
      chmod +x "$outdir/bin/doppler" "$outdir/bin/sleep"
      : > "$outdir/count"
      rm -rf /tmp/rung2
      (
        cd "$ROOT" || exit 2
        export PATH="$outdir/bin:$PATH"
        export STUB_COUNT="$outdir/count" STUB_MODE="$mode"
        export GITHUB_OUTPUT="$outdir/gh_output" GITHUB_STEP_SUMMARY="$outdir/gh_summary"
        export GITHUB_SERVER_URL="https://github.com"
        export GITHUB_REPOSITORY="jikig-ai/soleur"
        export GITHUB_RUN_ID="30560266736"
        set -a; . "$_cap_env"; set +a
        bash -e "$body"
      ) > "$outdir/stdout" 2>&1
      rc=$?
      attempts=$(grep -c -- '--- capture attempt' "$outdir/stdout" || true)
      invocations=$(cat "$outdir/count" 2>/dev/null || echo 0)
      printf '%s|%s|%s|%s\n' "$rc" "$attempts" "${invocations:-0}" "$outdir"
      return 0
    }

    # Every field is DEFAULTED. `[[ "" -eq 0 ]]` and `[[ "" -le 2 ]]` are both TRUE in bash
    # arithmetic, so an aborted `_run_capture` (a failed mktemp returns with no stdout) made
    # two assertions pass VACUOUSLY on a total harness failure — verified by injecting an
    # early return. A sentinel that cannot be mistaken for a real rc closes that.
    _cap_field() { local v="${1:-}"; printf '%s' "${v:-99999}"; }

    # ── Arm 13 — the poll polls, and reaches the terminal PASS on attempt 3. ──────────
    _cap_t0=$SECONDS
    _r13="$(_run_capture "$_cap_body" pass_on_3)"
    _rc13="$(_cap_field "${_r13%%|*}")"; _rest13="${_r13#*|}"
    _att13="$(_cap_field "${_rest13%%|*}")"; _rest13="${_rest13#*|}"
    _inv13="$(_cap_field "${_rest13%%|*}")"; _out13="${_rest13#*|}"
    _cap_elapsed=$(( SECONDS - _cap_t0 ))

    # THE SLEEP STUB, ASSERTED BY WALL CLOCK rather than by `command -v`. The previous form
    # built a throwaway dir, put a `sleep` in it, and checked that PATH lookup found it —
    # a property of bash, constant-true, and it never touched the dir `_run_capture` uses.
    # The real body sleeps 30 s between attempts, so three attempts unstubbed is 60 s+.
    [[ "$_cap_elapsed" -lt 10 ]] \
      && pass "arm 13's three attempts completed in ${_cap_elapsed}s — the sleep stub is genuinely shadowing (unstubbed would be 60s+)" \
      || fail "arm 13 took ${_cap_elapsed}s — the sleep stub is NOT shadowing, so this arm is silently a minute-long test"

    if grep -q -- '--- capture attempt 2/20' "$_out13/stdout"; then
      pass "the capture poll REACHES ATTEMPT 2 (the whole defect: production stopped at 1/20)"
    else
      fail "the capture poll never reached attempt 2/20 (ran ${_att13} attempt(s))" \
        "GitHub runs this step as \`bash -e {0}\`; without an explicit \`set +e\` the TRANSIENT rc=2 this poll exists to retry kills it on attempt 1"
    fi

    [[ "$_rc13" -eq 0 ]] \
      && pass "a terminal PASS exits 0 (the poll ran to a real verdict instead of dying on a retryable one)" \
      || fail "the capture body exited ${_rc13} on a stub that PASSes on attempt 3"

    if grep -q '^capture_rc=0$' "$_out13/gh_output" 2>/dev/null; then
      pass "capture_rc=0 is written to \$GITHUB_OUTPUT (the upload step's gate reads exactly this)"
    else
      fail "capture_rc was not written as 0 to \$GITHUB_OUTPUT" \
        "in production it was never written at all, so the upload gate compared against an empty string"
    fi

    if grep -q 'Rung-2 rehearsal: PASS' "$_out13/gh_summary" 2>/dev/null; then
      pass "the PASS verdict reaches \$GITHUB_STEP_SUMMARY"
    else
      fail "no PASS line reached \$GITHUB_STEP_SUMMARY"
    fi

    # Without this, a future edit that drops `doppler run` entirely leaves the stub unused and
    # the arm passes for reasons that have nothing to do with the poll.
    [[ "${_inv13:-0}" -gt 0 ]] \
      && pass "the doppler stub was actually invoked (${_inv13}x) — the arm is exercising the real call, not an empty loop" \
      || fail "the doppler stub was never invoked — arm 13 passed without executing the capture call"

    # ── Arm 13b — MUTATION: strip `set +e`. Must collapse to the production failure. ──
    # Discharges "first prove the check can fail; then care that it didn't".
    _mut_b="$(mktemp -t gdr2mutb.XXXXXXXX)" || exit 2
    grep -v '^[[:space:]]*set +e[[:space:]]*$' "$_cap_body" > "$_mut_b"
    _rb="$(_run_capture "$_mut_b" pass_on_3)"
    _rcb="${_rb%%|*}"; _restb="${_rb#*|}"; _attb="${_restb%%|*}"; _outb="${_restb#*|}"; _outb="${_outb#*|}"
    if [[ "$_attb" -eq 1 && "$_rcb" -ne 0 ]]; then
      pass "MUTATION 13b (set +e stripped): collapses to 1 attempt and exits ${_rcb} — the guard can go RED"
    else
      fail "MUTATION 13b did NOT reproduce the bug: ${_attb} attempt(s), exit ${_rcb}" \
        "a guard that cannot fail is not a guard; this mutation IS the production defect"
    fi
    rm -f "$_mut_b"

    # ── Arm 13c — MUTATION: re-arm `set -e` BEFORE the PIPESTATUS read. ──────────────
    # THE SINGLE MOST DANGEROUS EDIT ANYONE CAN MAKE TO THE FIXED STEP, and it fails silently
    # toward PASS. `set -e` is a builtin — therefore a pipeline — so bash RESETS PIPESTATUS
    # after it. Re-arming before the read makes rc always 0: exit 0, one attempt,
    # capture_rc=0, a green PASS summary, on a host that never booted. Strictly worse than
    # the bug being fixed, which at least fails loudly.
    _mut_c="$(mktemp -t gdr2mutc.XXXXXXXX)" || exit 2
    python3 - "$_cap_body" "$_mut_c" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
# Swap the adjacent `rc=${PIPESTATUS[0]}` / `set -e` pair so the re-arm precedes the read.
pat = re.compile(r'^([ \t]*)(rc=\$\{PIPESTATUS\[0\]\})[ \t]*\n([ \t]*)(set -e)[ \t]*$', re.M)
out, n = pat.subn(lambda m: "%s%s\n%s%s" % (m.group(3), m.group(4), m.group(1), m.group(2)), src)
open(sys.argv[2], "w").write(out)
sys.exit(0 if n == 1 else 4)
PY
    _mut_c_rc=$?
    if [[ "$_mut_c_rc" -ne 0 ]]; then
      fail "could not construct mutation 13c (no adjacent 'rc=\${PIPESTATUS[0]}' + 'set -e' pair found)" \
        "the ordering this arm protects is not present in the extracted body — the fix is missing or was reshaped"
    else
      _rcc_all="$(_run_capture "$_mut_c" pass_on_3)"
      _rcc="${_rcc_all%%|*}"; _restc="${_rcc_all#*|}"; _attc="${_restc%%|*}"; _restc="${_restc#*|}"; _outc="${_restc#*|}"
      if [[ "$_attc" -eq 1 && "$_rcc" -eq 0 ]] || grep -q 'Rung-2 rehearsal: PASS' "$_outc/gh_summary" 2>/dev/null; then
        pass "MUTATION 13c (set -e before the read): produces the SILENT FALSE PASS — ${_attc} attempt(s), exit ${_rcc}; the ordering is load-bearing and pinned"
      else
        fail "MUTATION 13c did not reproduce the false-PASS shape (${_attc} attempt(s), exit ${_rcc})" \
          "if this stops reproducing, the ordering guarantee this arm exists to pin has moved — re-derive it before deleting the arm"
      fi
    fi
    rm -f "$_mut_c"

    # ── Arm 13e — a WRAPPER auth failure stops fast instead of burning a paid host. ──
    # The sentinel correctly detects a doppler auth failure (rc=1, no verdict) and downgrades
    # it to 2 so it is not mis-blamed on the host — but 2 means "retry", and an auth failure
    # is not transient. Measured against the patched body without this fast-fail: ALL 20
    # ATTEMPTS BURNED, ~16 minutes on a paid Hetzner host, reporting the least actionable of
    # the verdicts. Pre-fix a bad token died in 4 seconds.
    _re="$(_run_capture "$_cap_body" wrapper_auth)"
    _rce="$(_cap_field "${_re%%|*}")"; _reste="${_re#*|}"
    _atte="$(_cap_field "${_reste%%|*}")"; _reste="${_reste#*|}"; _oute="${_reste#*|}"
    # `-eq 2`, NOT `-le 2`: the loose form also passes at ONE attempt, which is the original
    # errexit bug's signature — so arm 13e would have stayed green if that bug returned.
    if [[ "$_atte" -eq 2 ]]; then
      pass "a no-sentinel rc=1 (wrapper auth failure) stops after exactly 2 attempts, not 20 — no 16-minute burn on a paid host"
    else
      fail "a wrapper auth failure ran ${_atte} attempt(s), expected exactly 2" \
        "more means retrying a bad credential for ~16 minutes on a paid Hetzner host; ONE means the errexit bug is back"
    fi
    # The NUMERIC contract of the new class, not just its display prose: a copy edit to the
    # summary should not be the only thing this arm can detect.
    [[ "$_rce" -eq 3 ]] \
      && pass "the wrapper-failure class exits 3 (distinct from 1 FAIL and 2 TRANSIENT)" \
      || fail "the wrapper-failure path exited ${_rce}, expected 3"
    if grep -q '^capture_rc=3$' "$_oute/gh_output" 2>/dev/null; then
      pass "capture_rc=3 is written to \$GITHUB_OUTPUT"
    else
      fail "capture_rc=3 was not written to \$GITHUB_OUTPUT"
    fi
    if grep -q 'WRAPPER FAILURE' "$_oute/gh_summary" 2>/dev/null; then
      pass "the wrapper failure gets its own summary class, naming the credential rather than the host"
    else
      fail "no WRAPPER FAILURE summary class — a bad doppler token reports as TRANSIENT" \
        "whose own text says 'This is NOT evidence the host booted dark', sending the operator to the one place the answer is not"
    fi

    # ── Arm 13f — a GENUINE host FAIL is terminal, exits 1, and says FAIL. ───────────
    # Without this fixture the whole FAIL branch was unexercised, and three single-token
    # mutations survived: deleting the `! grep -q RUNG2_CAPTURE_VERDICT=` sentinel (a real
    # host failure then reports as WRAPPER FAILURE, sending the operator to check a
    # credential while the template is broken), renaming the `elif [[ "$rc" -eq 1 ]]` branch
    # so FAIL falls through to TRANSIENT, and — worst — `exit "$rc"` -> `exit 0`, which makes
    # the JOB GO GREEN on a host that booted dark. That last one is the exact outcome this
    # whole interlock exists to prevent, and nothing in the suite could see it.
    _rf="$(_run_capture "$_cap_body" host_fail)"
    _rcf="$(_cap_field "${_rf%%|*}")"; _restf="${_rf#*|}"
    _attf="$(_cap_field "${_restf%%|*}")"; _restf="${_restf#*|}"; _outf="${_restf#*|}"
    [[ "$_rcf" -eq 1 ]] \
      && pass "a host FAIL (rc=1 WITH the verdict sentinel) exits 1 — the step goes red, so the job cannot report success over a dark boot" \
      || fail "a host FAIL exited ${_rcf}, expected 1" \
           "if this is 0 the job goes GREEN on a host that booted dark — the failure the interlock exists to catch"
    [[ "$_attf" -eq 1 ]] \
      && pass "a host FAIL is TERMINAL — it is not retried (retrying a real finding would turn it into a timeout)" \
      || fail "a host FAIL ran ${_attf} attempts; a terminal verdict must not be retried"
    if grep -q 'Rung-2 rehearsal: FAIL' "$_outf/gh_summary" 2>/dev/null; then
      pass "a host FAIL reports the FAIL class, not TRANSIENT or WRAPPER FAILURE"
    else
      fail "a host FAIL did not print the FAIL summary class" \
        "it is being reported as some other class — the sentinel or the rc branch has drifted"
    fi

    # ── Arm 13g — ONE wrapper blip must NOT stop the poll. ──────────────────────────
    # The far side of the fast-fail. Every other arm asserts "stop" or "keep going" from one
    # direction only, so nothing could show the fast-fail was not TOO aggressive: deleting
    # the `else wrapper_fails=0` reset (making the counter cumulative rather than
    # consecutive) and tightening `-ge 2` to `-ge 1` BOTH left the suite fully green, and
    # either would abort a live paid rehearsal on a single transient blip.
    _rg="$(_run_capture "$_cap_body" blip_then_pass)"
    _rcg="$(_cap_field "${_rg%%|*}")"; _restg="${_rg#*|}"
    _attg="$(_cap_field "${_restg%%|*}")"; _restg="${_restg#*|}"; _outg="${_restg#*|}"
    [[ "$_rcg" -eq 0 ]] \
      && pass "a single wrapper blip followed by a real verdict still reaches PASS (the fast-fail is consecutive, not cumulative)" \
      || fail "one wrapper blip aborted the run (exit ${_rcg}) — the fast-fail is too aggressive" \
           "a transient doppler failure on attempt 1 would end a rehearsal that has already spent a paid host"
    [[ "$_attg" -ge 3 ]] \
      && pass "the poll continued past the blip (${_attg} attempts) instead of treating it as terminal" \
      || fail "the poll stopped after ${_attg} attempt(s) on a single blip"

    rm -rf /tmp/rung2
  fi
  rm -f "$_cap_body" "$_cap_env"

  # ── 13d. IN-WORKFLOW ERREXIT POSTURE (text-level, THIS workflow only) ─────────────
  #
  # Scoped deliberately. A standalone repo-wide lint was measured over 631 `run:` bodies and
  # cut: its rule matches exactly ONE body — this bug — and none of the three sibling bugs
  # this PR fixes. It also CERTIFIES the false-PASS shape (set +e -> pipeline -> set -e ->
  # read satisfies "contains set +e before the read" while being exactly arm 13c's mutation),
  # which is why this arm keys on the NEAREST PRECEDING TOGGLE, not on mere presence.
  _posture="$(python3 - "$WF" <<'PY'
import re, sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
scanned = violations = matched = 0
for jn, j in (d.get("jobs") or {}).items():
    for s in j.get("steps") or []:
        body = s.get("run")
        if not body:
            continue
        scanned += 1
        # COMMENT-STRIPPED, like every other assertion in this file. Measured while writing
        # it: an audit script over the whole workflow directory reported this exact rule
        # matching a body in follow-through-closure-guard.yml whose ONLY `PIPESTATUS[` was
        # inside a comment explaining why that site deliberately uses `|| true` instead of a
        # bracket. The fix for this class documents the class, and a bare-token scan then
        # reports the documentation as the violation (cq-assert-anchor-not-bare-token).
        # DROPPED, not blanked: a comment or a blank line between the pipeline and the read
        # is harmless at runtime, so adjacency is computed over real COMMANDS only.
        lines = [ln for ln in body.splitlines()
                 if ln.strip() and not re.match(r'^[ \t]*#', ln)]
        for i, ln in enumerate(lines):
            if "PIPESTATUS[" not in ln:
                continue
            matched += 1
            # ANY `set` line that changes errexit counts, not just a bare `set +e`/`set -e`.
            # An earlier version matched only the bare forms, so `set +e` ... `set -euo
            # pipefail` ... PIPESTATUS resolved to `+e` and PASSED -- the false-PASS
            # direction -- because the re-arming line was invisible to it.
            toggle = None
            for prev in reversed(lines[:i]):
                m = re.match(r'^[ \t]*set\s+([-+])([a-uw-z]*e[a-uw-z]*)(\s|$)', prev)
                if m:
                    toggle = m.group(1) + "e"
                    break
                m = re.match(r'^[ \t]*set\s+([-+])o\s+errexit(\s|$)', prev)
                if m:
                    toggle = m.group(1) + "e"
                    break
            if toggle != "+e":
                violations += 1
                print("VIOLATION=%s/%s: nearest toggle before a PIPESTATUS read is %r"
                      % (jn, s.get("id") or s.get("name"), toggle))
                continue
            # NOTHING may sit between the pipeline and the read -- and "nothing" means NO
            # COMMAND AT ALL, not merely no `set`. EVERY simple command resets PIPESTATUS,
            # which is the same fact arm 13c pins. Measured:
            #   bash -c 'set +e; (exit 7) | cat; echo marker; echo "${PIPESTATUS[*]}"'  -> 0
            #   ...without the echo                                                     -> 7 0
            # An earlier version of this check tested `prev_cmd.startswith("set ")`, which
            # reported VIOLATIONS=0 against a body with `echo` between the pipeline and the
            # read -- a clean pass on the exact silent-false-PASS shape, from an assertion
            # whose message said "with nothing between". So require the previous command to
            # BE the pipeline: an unquoted `|` outside quotes.
            prev_cmd = lines[i - 1].strip() if i else ""
            depth = {"'": False, '"': False}
            piped = False
            for ch in prev_cmd:
                if ch == "'" and not depth['"']:
                    depth["'"] = not depth["'"]
                elif ch == '"' and not depth["'"]:
                    depth['"'] = not depth['"']
                elif ch == "|" and not depth["'"] and not depth['"']:
                    piped = True
            if not piped:
                violations += 1
                print("VIOLATION=%s/%s: the command before the PIPESTATUS read is not the "
                      "pipeline (%r) -- it resets PIPESTATUS"
                      % (jn, s.get("id") or s.get("name"), prev_cmd))
print("SCANNED=%d VIOLATIONS=%d MATCHED=%d" % (scanned, violations, matched))
PY
)"
  _scanned="$(printf '%s' "$_posture" | sed -n 's/.*SCANNED=\([0-9]*\).*/\1/p')"
  _violations="$(printf '%s' "$_posture" | sed -n 's/.*VIOLATIONS=\([0-9]*\).*/\1/p')"
  _matched="$(printf '%s' "$_posture" | sed -n 's/.*MATCHED=\([0-9]*\).*/\1/p')"
  # SCANNED alone is the WRONG denominator: it counts `run:` bodies, and this workflow has 12
  # of them while exactly ONE reads PIPESTATUS. So "SCANNED=12, VIOLATIONS=0" is satisfied by
  # a workflow containing ZERO PIPESTATUS reads -- the rule would fire zero times and still
  # report clean. MATCHED counts the reads actually examined, which is what the rule
  # quantifies over.
  [[ "${_matched:-0}" -ge 1 ]] \
    && pass "the errexit-posture rule examined ${_matched} PIPESTATUS read(s) across ${_scanned} run: bodies (non-vacuous)" \
    || fail "the errexit-posture rule examined ZERO PIPESTATUS reads (scanned ${_scanned:-0} bodies) — a vacuous pass" \
         "the capture step must read \${PIPESTATUS[0]}; if it no longer does, this arm is guarding nothing"
  [[ "${_violations:-1}" -eq 0 ]] \
    && pass "every PIPESTATUS read in this workflow sits under \`set +e\` with nothing between the pipeline and the read" \
    || fail "${_violations} run: body/bodies read PIPESTATUS under the wrong errexit posture" \
         "$(printf '%s' "$_posture" | grep VIOLATION= | head -3)"

  # ── 13h. EVERY NON-PASS-GATED STEP CARRIES A STATUS FUNCTION ─────────────────────
  #
  # A step `if:` containing no status-check function (`always()`, `failure()`,
  # `!cancelled()`) has `success()` implicitly ANDed by GitHub. The capture step ends
  # `exit "$rc"`, so EVERY path where `capture_rc != '0'` is a path where that step FAILED —
  # making `success() && capture_rc != '0'` a contradiction. Shipped that way, the capture-log
  # upload and its redaction step were skipped on 100% of the runs they exist for, while the
  # job summary and the runbook both told the operator to download the artifact.
  #
  # The sibling evidence upload needs no status function: its `== '0'` gate coincides with a
  # green capture step, which is exactly why THAT one worked and hid the class.
  _statusfn_bad=""
  while IFS=$'\t' read -r _sname _sif; do
    [[ "$_sif" == *"capture_rc != '0'"* ]] || continue
    [[ "$_sif" == *"always()"* || "$_sif" == *"failure()"* || "$_sif" == *"cancelled()"* ]] \
      || _statusfn_bad="${_statusfn_bad} ${_sname}"
  done < <(python3 - "$WF" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for s in d["jobs"]["rehearse"]["steps"]:
    if s.get("if"):
        print("%s\t%s" % (s.get("name") or s.get("id"), " ".join(str(s["if"]).split())))
PY
)
  [[ -z "$_statusfn_bad" ]] \
    && pass "every step gated on a NON-PASS capture_rc carries a status function — none is silently ANDed with success()" \
    || fail "step(s) gated on capture_rc != '0' with no status function:${_statusfn_bad}" \
         "GitHub ANDs an implicit success(); the capture step exits non-zero on exactly those paths, so the gate is a contradiction and the step never runs"

  # THE COUPLING THAT ACTUALLY FAILED IN PRODUCTION: the upload gates on capture_rc, and
  # capture_rc is written by the step this suite's arm 13 executes. Retained from the review's
  # cut of a speculative continue-on-error assertion — this one is measured, not hypothesised.
  if grep -qE "steps\.capture\.outputs\.capture_rc == '0'" "$WF"; then
    pass "the evidence upload still gates on steps.capture.outputs.capture_rc == '0'"
  else
    fail "the evidence upload no longer gates on steps.capture.outputs.capture_rc == '0'" \
      "in production that comparison ran against an empty string because the step died before writing it"
  fi
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
# THE TERRAFORM COPY IS THE ONE THAT NAMES THE HOST, and it was shape-checked but never
# COMPARED to the two literals the sweeps match against. Measured (#7066 review): renaming
# rehearsal.tf's host to `soleur-gitdata-r2-rehearsal-${var.rehearsal_run_id}` kept this suite
# 39/0 while BOTH sweeps went on matching `soleur-git-data-rehearsal-` — against zero servers,
# each printing "teardown verified / no survivors" while a paying host with a LUKS volume ran
# on. A shape check cannot see a prefix change; only a comparison can.
if [[ "$_pfx_tf" == "${_pfx_wf}"* ]]; then
  pass "the Terraform host name starts with the prefix both sweeps match on (${_pfx_wf})"
else
  fail "the Terraform host name '${_pfx_tf}' does not start with the sweeps' prefix '${_pfx_wf}'" \
    "both orphan sweeps would match zero servers and report success while a rehearsal host runs"
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
# A FOURTH COPY (#7227 item 4): the evidence-capture script now refuses any --host-name that
# does not carry this prefix, so its regex is a consumer of the same literal and drifts the
# same way. Folded into this existing chain rather than given its own arm — the comparison
# here is already "every replica of one literal agrees", and a fourth comparand costs one
# extraction, where a parallel arm would duplicate the rationale and the mutation.
_pfx_cap="$(grep -oE '\^soleur-git-data-rehearsal-' \
  "${ROOT}/scripts/followthroughs/git-data-rung2-evidence-capture.sh" | head -1 | sed 's/^\^//')"
if [[ "$_pfx_cap" == "$_pfx_wf" ]]; then
  pass "the evidence-capture script's --host-name constraint pins the same rehearsal prefix"
else
  fail "the evidence-capture --host-name constraint does not pin the rehearsal prefix (got '${_pfx_cap:-none}', want '${_pfx_wf}')" \
    "Unconstrained, the capture script can be aimed at the production host soleur-git-data and project its boot telemetry into a PUBLIC Actions log."
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
#
# COMMENT-STRIPPED, like every other assertion in this file. Measured (#7066 review): these
# were the only two greps that read $DRIFT_WF raw, so replacing the whole sweep job body with
# `run: echo "noop"` while leaving a comment that named the job and the URL kept this suite
# 39/0 green — the guard was satisfied by prose describing the thing it had just lost.
DRIFT_CODE="$(mktemp -t gdr2drift.XXXXXXXX)" || exit 2
sed 's/^[[:space:]]*#.*$//; s/[[:space:]]#.*$//' "$DRIFT_WF" > "$DRIFT_CODE"
if grep -q 'rung2-rehearsal-orphan-sweep' "$DRIFT_CODE"; then
  pass "the scheduled drift workflow carries a rung-2 orphan sweep"
else
  fail "no rung-2 orphan sweep — a leaked rehearsal host would be invisible to every terraform plan"
fi
# Anchored on the CALL, not on a bare URL: the sweep now iterates resource kinds
# (servers/volumes/ssh_keys/firewalls) because a partial teardown strands volumes and the
# scratch Doppler config far more often than it strands the box.
if grep -qE 'api\.hetzner\.cloud/v1/\$\{_kind\}' "$DRIFT_CODE"; then
  pass "the sweep asks HETZNER, not terraform state (state cannot see what it has forgotten)"
else
  fail "the orphan sweep does not query the Hetzner API"
fi

# ── 14. THIS SUITE RUNS WHEN THE WORKFLOWS IT GUARDS ARE EDITED ────────────────────
#
# infra-validation.yml is `paths:`-filtered. Every assertion above reads one of three
# workflows, and NONE of the three was in that filter until #7025 -- so a PR editing only
# `git-data-rung2-rehearsal.yml` did not run the suite whose entire job is protecting it.
# PR #7094 ran it only incidentally, because it also touched apps/web-platform/infra/.
#
# That is the same defect the #6454 and #6178 comments in infra-validation.yml already
# describe ("the job that proves the gate works would be skipped by the very PR changing the
# gate") -- patched three times for other workflows and still open for this one. Derived from
# the SUITE's own variables rather than a hardcoded list, so adding a fourth workflow to this
# file reds here until its path is registered.
INFRA_VALIDATION_WF="${ROOT}/.github/workflows/infra-validation.yml"
if [[ ! -f "$INFRA_VALIDATION_WF" ]]; then
  fail "infra-validation.yml is missing — cannot verify this suite is registered against the workflows it reads"
elif ! command -v python3 >/dev/null 2>&1; then
  fail "python3 absent — the path-registration arm did NOT run" \
    "a gate that cannot run must not report success"
else
  # ASK THE OPERATIONAL QUESTION, not a textual one: "would a PR editing ONLY this file
  # trigger this workflow?" Ten mutations defeated the textual form and every one is
  # realistic: the path in a COMMENT (this file is dense with comments naming paths, so
  # deleting an entry while leaving its rationale comment read as registered); the path in
  # a `run:` body; `- "!<path>"`, GitHub's EXCLUSION idiom used two files away in
  # apply-web-platform-infra.yml, which makes the entry never fire while the substring is
  # still present; `paths:` renamed to `paths-ignore:`, inverting the filter for the WHOLE
  # workflow; and the three entries moved to a `push:` block, so the suite runs only after
  # merge — when the route is already broken.
  #
  # Matching against the PARSED pull_request filter with fnmatch closes all of them by
  # construction, and mirrors the in-repo instrument infra-validation.yml's own comment
  # block cites: apply-inngest-rls-dev-workflow.test.sh's `routes()`.
  #
  # The guarded set is DERIVED by grepping this file's own `*_WF=` assignments — not a
  # restated triple. An earlier version hardcoded three variable NAMES while its comment
  # claimed derivation; adding a fourth `*_WF` left it reporting "all 3" and silently
  # uncovered, and pointing two vars at one file left it counting 3 distinct when there
  # were 2.
  _paths_probe="$(python3 - "$INFRA_VALIDATION_WF" "$0" <<'PY'
import fnmatch, os, re, sys, yaml

wf_file, suite_file = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(wf_file))
on = d.get(True) or d.get("on") or {}
pr = on.get("pull_request") or {}
declared = [str(x) for x in (pr.get("paths") or [])]

def routes(path):
    """Would a PR whose ONLY changed file is `path` trigger this workflow?"""
    if any(fnmatch.fnmatch(path, p[1:]) for p in declared if p.startswith("!")):
        return False                      # an explicit `!` exclusion wins
    return any(fnmatch.fnmatch(path, p) for p in declared if not p.startswith("!"))

# Derive the guarded workflows from the suite's OWN assignments.
src = open(suite_file).read()
guarded = set()
for m in re.finditer(r'^[A-Z_]*WF="\$\{ROOT\}/(\.github/workflows/[^"]+)"', src, re.M):
    guarded.add(m.group(1))

print("DECLARED=%d" % len(declared))
print("GUARDED=%d" % len(guarded))
for g in sorted(guarded):
    if not os.path.isfile(os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(wf_file))), g)):
        print("NOFILE=%s" % g)
    elif not routes(g):
        print("MISSING=%s" % g)
# NEGATIVE CONTROL: a path that must NOT route, so a filter that matched everything
# (paths-ignore, a stray "**") cannot satisfy this arm vacuously.
print("CONTROL_ROUTES=%d" % (1 if routes("README.md") else 0))
PY
)" || _paths_probe="PROBE_FAILED=1"
  _pguarded="$(printf '%s\n' "$_paths_probe" | sed -n 's/^GUARDED=//p')"
  _pmissing="$(printf '%s\n' "$_paths_probe" | sed -n 's/^MISSING=//p' | tr '\n' ' ')"
  _pnofile="$(printf '%s\n' "$_paths_probe" | sed -n 's/^NOFILE=//p' | tr '\n' ' ')"
  _pcontrol="$(printf '%s\n' "$_paths_probe" | sed -n 's/^CONTROL_ROUTES=//p')"
  if printf '%s' "$_paths_probe" | grep -q 'PROBE_FAILED=1'; then
    fail "could not parse infra-validation.yml's pull_request filter — refusing to read an unparseable filter as coverage"
  elif [[ "${_pguarded:-0}" -lt 3 ]]; then
    fail "derived only ${_pguarded:-0} guarded workflow(s) from this suite's own *_WF= assignments (expected >= 3)" \
      "the extraction drifted; this arm is comparing against an incomplete set and would pass over an unregistered workflow"
  elif [[ "${_pcontrol:-1}" -ne 0 ]]; then
    fail "NEGATIVE CONTROL FAILED: a PR touching only README.md would trigger infra-validation" \
      "the filter matches everything (paths-ignore, or a stray '**'), so this arm's pass would be vacuous"
  elif [[ -n "$_pnofile" ]]; then
    fail "a *_WF= assignment names a file that does not exist: ${_pnofile}" \
      "cannot verify registration for a workflow that is not on disk"
  elif [[ -z "$_pmissing" ]]; then
    pass "a PR editing ONLY any of the ${_pguarded} workflows this suite reads WOULD trigger infra-validation (parsed filter, negative control held)"
  else
    fail "editing ONLY these workflow(s) would NOT trigger infra-validation: ${_pmissing}" \
      "this suite guards them, so a PR changing one would skip the guard entirely — check for a missing entry, a '!' exclusion, paths-ignore, or a push-only block"
  fi
fi

# ── 20 (#7204). THE FAIL ARTIFACT MUST CARRY A CAUSE, NOT ONLY A VERDICT ───────────
#
# Rehearsal run 30649892865 reported `stage:luks_open level:fatal` and nothing else. The
# cause — mount(2) returning ESRCH — was in the same Better Stack row the whole time;
# HOST_SQL simply never projected it, so diagnosing a FAIL required hand-writing a new query.
# These arms pin the projection so the artifact stays self-diagnosing.
_CAP="${ROOT}/scripts/followthroughs/git-data-rung2-evidence-capture.sh"
if [[ -r "$_CAP" ]]; then
  # Slice HOST_SQL so a `detail` appearing anywhere else in the script (prose, the FAIL-arm
  # message) cannot satisfy these — cq-assert-anchor-not-bare-token.
  _hostsql="$(awk '/^HOST_SQL="/{f=1} f{print} f&&/FORMAT JSONEachRow"/{exit}' "$_CAP")"

  if printf '%s' "$_hostsql" | grep -qE "JSONExtractString\(raw,'detail'\)"; then
    pass "20a HOST_SQL projects detail"
  else
    fail "20a HOST_SQL does not project detail" \
         "A FAIL artifact then carries a verdict with no cause — the #7204 defect."
  fi
  if printf '%s' "$_hostsql" | grep -qE "JSONExtractString\(raw,'rc'\)"; then
    pass "20b HOST_SQL projects rc"
  else
    fail "20b HOST_SQL does not project rc" \
         "rc rides in \$TAGS, which the emitter concatenates at TOP LEVEL of the Better Stack body, so raw.rc resolves. It is the mount(8) exit status — 32 for the ESRCH class."
  fi

  # MUTATION for both: strip the projections and prove the arms flip. Without this the two
  # greps above are satisfied by any file that happens to contain the strings.
  _mut="$(printf '%s' "$_hostsql" | sed -E "/JSONExtractString\(raw,'(detail|rc)'\)/d")"
  if printf '%s' "$_mut" | grep -qE "JSONExtractString\(raw,'(detail|rc)'\)"; then
    fail "20c MUTATION did not land — the projections survived deletion" \
         "20a/20b certify nothing; re-anchor the slice."
  else
    pass "20c MUTATION lands (projections are deletable, so 20a/20b are real)"
  fi

  # ── D11: HOST_SQL's key set ⊆ the keys something actually EMITS ──────────────────
  # A static grep for `detail` proves the column is SELECTED, never that it is POPULATED:
  # rename the emitter's field and the SQL keeps selecting an always-empty column with this
  # suite still green. So every projected key must be traceable to a producer.
  #
  # Producers: cloud-init-git-data.yml's git-data-emit writes a FLAT Better Stack body
  # (message/stage/level/host_name/detail) with $TAGS concatenated at top level; tag keys
  # come from its callers — `rc=` from the luks_err trap, and the four assertion booleans
  # from git-data-bootstrap.sh's boot_complete emit.
  #
  # KNOWN EXCEPTION, enumerated rather than left as folklore: luks_mounted/repo_root/
  # hooks_path/provision are emitted ONLY on a stage:boot_complete row. They are structurally
  # empty on every FAIL row, so their presence in the projection is not evidence about how far
  # a failed boot got. #7204's source brief read four blanks as "died before mount" — the
  # `stage` tag is the only positional fact in a FAIL row.
  _emit_src="${DIR}/cloud-init-git-data.yml"
  _boot_src="${DIR}/git-data-bootstrap.sh"
  # ANCHORED ON THE EMISSION SITE, not on a bare-token scan of two whole files. The previous
  # form `grep -cE "\"${_k}\"|${_k}="` was satisfied by shell locals and prose: renaming the
  # Better Stack `detail` field to `diag` — which makes JSONExtractString(raw,'detail')
  # permanently empty — still matched 3x via `_detail=` in luks_err and via `"detail"` in the
  # SENTRY body, a channel HOST_SQL never reads. `rc` matched 16x, mostly `rc=$?` locals and
  # a comment reading "measured: dash rc=2". The arm whose stated purpose is "a static grep
  # proves the column is SELECTED, never that it is POPULATED" reproduced exactly that.
  #
  # A key is PRODUCED iff it appears either:
  #   (a) as a field of the BETTER STACK body — the `--data-raw` line, which is what
  #       betterstack-query.sh reads (the Sentry body nests under "tags" and is NOT queried), or
  #   (b) as a k=v TAG ARGUMENT at a git-data-emit call site, i.e. the literal `"<key>=`.
  # The body is a shell-escaped JSON literal (\"detail\":\"$DETAIL\"), so strip backslashes
  # before matching — otherwise every field reads as unproduced and 20d fails CLOSED on a
  # correct emitter, which is the opposite error but still a broken gate.
  _bs_body="$(grep -F -- '--data-raw' "$_emit_src" 2>/dev/null | tr -d '\\' || true)"
  if [[ -z "$_bs_body" ]]; then
    fail "20d could not locate the emitter's --data-raw line in ${_emit_src}" \
         "The producer scan has no anchor; treating that as 'all keys produced' would be the fail-open this arm exists to close."
  else
  _unproduced=""
  while IFS= read -r _k; do
    [[ -n "$_k" ]] || continue
    _in_body=$(printf '%s\n' "$_bs_body" | grep -cF -- "\"${_k}\":" || true)
    _in_tags=$(cat "$_emit_src" "$_boot_src" 2>/dev/null | grep -cF -- "\"${_k}=" || true)
    [[ "${_in_body:-0}" -ge 1 || "${_in_tags:-0}" -ge 1 ]] || _unproduced="${_unproduced} ${_k}"
  done < <(printf '%s' "$_hostsql" | sed -nE "s/.*JSONExtractString\(raw,'([a-z_]+)'\).*/\1/p" | sort -u)
  if [[ -z "$_unproduced" ]]; then
    pass "20d every HOST_SQL key is produced by the emitter body or a tag argument"
  else
    fail "20d HOST_SQL projects key(s) nothing emits:${_unproduced}" \
         "An always-empty column reads as 'the host did not report it' rather than 'we never asked correctly'. Either wire the producer or drop the column."
  fi
  fi
  # LOOSENESS CONTROL — `_detail` is a real shell local in luks_err (`_detail="$GIT_DATA_...`)
  # and is NOT an emitted field. Under the old bare-token scan it matched and would have been
  # reported as produced; under the anchored scan it must not. A maximally-implausible token
  # (`zzz_no_such_field`) could only ever prove the scan is not matching literally everything —
  # it cannot detect looseness against locals or prose, which is the actual failure mode.
  _ctl_body=$(printf '%s\n' "$_bs_body" | grep -cF -- '"_detail":' || true)
  _ctl_tags=$(cat "$_emit_src" "$_boot_src" 2>/dev/null | grep -cF -- '"_detail=' || true)
  _ctl_loose=$(cat "$_emit_src" "$_boot_src" 2>/dev/null | grep -cE '"_detail"|_detail=' || true)
  if [[ "${_ctl_body:-0}" -eq 0 && "${_ctl_tags:-0}" -eq 0 && "${_ctl_loose:-0}" -ge 1 ]]; then
    pass "20e LOOSENESS control: a shell local (_detail) is correctly NOT counted as a producer"
  else
    fail "20e LOOSENESS control failed (body=${_ctl_body:-?} tags=${_ctl_tags:-?} loose=${_ctl_loose:-?})" \
         "Expected: _detail present in the files (loose>=1) but NOT counted as an emitted field (body=0, tags=0). A non-zero body/tags means 20d's scan is still matching locals; loose=0 means the control itself no longer exercises anything."
  fi
else
  fail "20 capture script not readable at ${_CAP}"
  fail "20: skipped (capture script missing)"; fail "20: skipped (capture script missing)"
  fail "20: skipped (capture script missing)"; fail "20: skipped (capture script missing)"
fi

# ── Minimum-cardinality floor ──────────────────────────────────────────────────────
# A floor, not an equality: developer-incremented, so `-eq` would redden the suite on every
# legitimately added arm and train the next person to bump it unread. Counts passes+fails so
# a genuine failure reports as a failure rather than as an empty suite.
#
# RAISED 65 -> 70 WITH THE ARMS THAT MADE IT NECESSARY (#7204: arms 20a-20e — HOST_SQL
# projects detail and rc, the projections are deletable so those greps are real, and every
# projected key is traceable to a producer with an unproduced-key control).
#
# RAISED 28 -> 39 -> 43 -> 65 WITH THE ARMS THAT MADE IT NECESSARY (#7025 R7; the 43 -> 56
# step is the behavioural capture-poll block, arms 13/13b/13c/13d/13e). At 28 the slack had grown
# to exceed the work it was guarding: deleting arms 6, 7, 7b, 7c and 7d — every arm that
# compares the two roots, i.e. the suite's entire reason for existing — landed on exactly 28
# and printed `ok anti-vacuity floor: 28 assertions ran`, exit 0. Measured. A floor that does
# not move with the suite only ever guards the work that predates it, and the deletion it
# most needs to catch is the one that removes the arms someone just argued for.
#
# RAISED 70 -> 71 WITH THE ARM THAT MADE IT NECESSARY (#7227 item 4): arm 10's comparison
# chain gained a FOURTH replica of the rehearsal prefix — the evidence-capture script's
# `--host-name` constraint, which is now a consumer of the same literal and drifts the same
# way. Folded into the existing chain rather than given its own arm plus mutation, because
# that chain's whole property is already "every replica of one literal agrees".
# 70 + 1 = 71. Measured: 71 passed, 0 failed.
_ran=$((passes + fails))
if [[ "$_ran" -lt 71 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 71. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 71)\n' "$_ran"
fi

printf '\n=== git-data-rung2-rehearsal: %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
