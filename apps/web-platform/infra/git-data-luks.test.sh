#!/usr/bin/env bash
#
# Drift guard for the git-data LUKS-at-rest cutover volume (Sub-PR 3.D / ADR-068,
# #5274 Phase 3). Asserts the SECURITY-LOAD-BEARING shape of the cloud-init LUKS
# block (cloud-init-git-data.yml) and git-data-luks.tf:
#   * cryptsetup `isLuks` idempotency guard present (2nd cloud-init run is a no-op);
#   * the LUKS passphrase is delivered via stdin (`--key-file -`) and NEVER appears
#     as a bare argv token on any luksFormat/luksOpen line (leak via `ps`/argv);
#   * the mapper /dev/mapper/git-data is mounted at /mnt/git-data-luks (the cutover
#     FRESH_ROOT git-data-cutover.sh asserts);
#   * fail-loud on an empty key — never an unencrypted fallback;
#   * the key arrives from the Doppler-injected env (doppler run), and the passphrase
#     literal is NOT baked into user_data (only random_password → doppler_secret).
#
# Also carries the #6570 DUAL-ARCH DERIVATION guards (A14-A17). git-data was pinned to
# `cax11`, a type orderable in 0 of 3 EU datacenters, so the host could never be born on
# its declared type. The repin to `cpx22` makes the host arch DERIVED from the type
# prefix, and these four assertions pin that derivation behaviorally:
#   * the Doppler URL is arch-interpolated with the $${shell}/${terraform} escaping split
#     correct (the silent direction renders an EMPTY arch and the render gate is blind);
#   * the per-arch checksum pair is byte-identical to the two live canon sites, IN ORDER;
#   * the derivation is ORIENTED correctly (replays the ternary — catches an inversion);
#   * the declared default is not a cax* type (#6570 regressing, statically).
#
# Each assertion is MUTATION-TESTED: the predicate is re-run against a deliberately
# broken copy and MUST flip to failing (a green test that cannot go red is worthless
# — the bash-gate-authoring foot-gun). Deliberately-nonzero commands are wrapped in
# `$(… || true)` command-subs so `set -e` never aborts the harness mid-suite.
#
# Run: bash apps/web-platform/infra/git-data-luks.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="${DIR}/cloud-init-git-data.yml"
LUKS_TF="${DIR}/git-data-luks.tf"
CUTOVER="${DIR}/git-data-cutover.sh"
PRERECEIVE="${DIR}/git-data-pre-receive.sh"
# #6570 dual-arch derivation (A14-A17). inngest-host.tf / zot-registry.tf are the CANON
# the checksum pair is derived from (never a second hardcoded literal); variables.tf holds
# the default.
#
# (#7025, R7) The derivation that selects WHICH BINARY is downloaded, and the checksum pair
# that verifies it, moved OUT of git-data.tf and into modules/git-data-userdata/main.tf —
# the single render both the production root and the rung-2 rehearsal root call. A15/A16/A18
# therefore read the MODULE, not the caller: pointed at git-data.tf they would assert
# against a file that no longer wires anything, and (for A15) against literals no consumer
# reads. git-data.tf declares NO arch of its own — the phantom-type precondition reads the
# module's derivation back as `module.git_data_userdata.arch` — so A16b asserts THAT WIRE,
# and the absence of a second derivation, where it once compared two ternaries as text.
GIT_DATA_TF="${DIR}/git-data.tf"
GIT_DATA_MODULE_TF="${DIR}/modules/git-data-userdata/main.tf"
INNGEST_HOST_TF="${DIR}/inngest-host.tf"
ZOT_TF="${DIR}/zot-registry.tf"
VARIABLES_TF="${DIR}/variables.tf"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; [ -n "${2:-}" ] && echo "      $2" >&2; return 0; }

[ -f "$CLOUD_INIT" ]   || { echo "FAIL: cloud-init-git-data.yml not found at $CLOUD_INIT" >&2; exit 1; }
[ -f "$LUKS_TF" ]      || { echo "FAIL: git-data-luks.tf not found at $LUKS_TF" >&2; exit 1; }
[ -f "$CUTOVER" ]      || { echo "FAIL: git-data-cutover.sh not found at $CUTOVER" >&2; exit 1; }
[ -f "$PRERECEIVE" ]   || { echo "FAIL: git-data-pre-receive.sh not found at $PRERECEIVE" >&2; exit 1; }
for f in "$GIT_DATA_TF" "$GIT_DATA_MODULE_TF" "$INNGEST_HOST_TF" "$ZOT_TF" "$VARIABLES_TF"; do
  [ -f "$f" ] || { echo "FAIL: required file not found: $f" >&2; exit 1; }
done

# --- Predicates (each takes a file, echoes "1" if the property holds, else "0") ---

# The luks_open heredoc, COMMENT-STRIPPED. Defined here rather than beside its first #7204
# caller further down because A1 and the B18 family both read it, and a shell function must
# be defined above the line that calls it.
_luks_slice() {
  awk '/^[[:space:]]*STAGE=luks_open[[:space:]]*$/{f=1} f&&/^[[:space:]]*LUKSEOF[[:space:]]*$/{f=0} f' "$1" \
    | grep -vE '^[[:space:]]*#' || true
}

# isLuks probe present. READS THE COMMENT-STRIPPED SLICE, NOT THE RAW FILE. As a whole-file
# grep this matched the prose explaining the guard exactly as readily as the guard itself, so
# deleting the real probe left it green (cq-assert-anchor-not-bare-token; the #7204 session's
# "four guards were satisfied by the comment I wrote to explain them"). #7216's own comment
# block names the pre-fix invocation literally, which is precisely the text that would have
# made this vacuous.
p_isluks() {
  if _luks_slice "$1" | grep -Eq 'cryptsetup[[:space:]]+isLuks'; then echo 1; else echo 0; fi
}

# Every luksFormat/luksOpen line pipes the key via `--key-file -` (stdin) AND carries
# NO `$GIT_DATA_LUKS_KEY` as an argv token (the key must arrive on stdin, not argv).
p_keyfile_stdin() {
  local f="$1" luks_args n_lines n_keyfile n_argvkey
  # Isolate the `cryptsetup luks…` command portion of each line (drop the legitimate
  # `printf '%s' "$GIT_DATA_LUKS_KEY" |` stdin-pipe PREFIX so it is not miscounted as
  # an argv occurrence). We assert against the cryptsetup argv ONLY.
  luks_args="$(grep -E 'cryptsetup[[:space:]]+luks(Format|Open)' "$f" | sed -E 's/.*(cryptsetup[[:space:]]+luks)/\1/' || true)"
  n_lines="$(printf '%s\n' "$luks_args" | grep -c 'cryptsetup' || true)"
  # Must have at least one luksFormat AND one luksOpen line.
  if [ "$n_lines" -lt 2 ]; then echo 0; return; fi
  # Every such cryptsetup argv must contain `--key-file -`.
  n_keyfile="$(printf '%s\n' "$luks_args" | grep -c -- '--key-file -' || true)"
  if [ "$n_keyfile" -ne "$n_lines" ]; then echo 0; return; fi
  # NO cryptsetup argv may carry the key var as a positional (the key belongs on
  # stdin via the printf pipe, NEVER on the cryptsetup command line / argv).
  n_argvkey="$(printf '%s\n' "$luks_args" | grep -c 'GIT_DATA_LUKS_KEY' || true)"
  if [ "$n_argvkey" -ne 0 ]; then echo 0; return; fi
  echo 1
}

# The key IS piped from a printf of $GIT_DATA_LUKS_KEY (proves stdin delivery exists).
p_printf_pipe() {
  if grep -Eq "printf[[:space:]]+'%s'[[:space:]]+\"\\\$GIT_DATA_LUKS_KEY\"[[:space:]]*\|[[:space:]]*cryptsetup" "$1"; then echo 1; else echo 0; fi
}

# Mapper mounted at the cutover FRESH_ROOT.
p_mapper_mount() {
  if grep -Eq 'mount[[:space:]]+/dev/mapper/git-data[[:space:]]+/mnt/git-data-luks' "$1"; then echo 1; else echo 0; fi
}

# Fail-loud on empty key (no unencrypted fallback).
p_fail_loud() {
  if grep -Eq '\[ -n "\$GIT_DATA_LUKS_KEY" \]' "$1"; then echo 1; else echo 0; fi
}

# Key sourced from the Doppler-injected env (doppler run wraps the LUKS setup).
p_doppler_run() {
  if grep -Eq 'doppler run .* -- bash' "$1"; then echo 1; else echo 0; fi
}

# The passphrase is generated (random_password) and pushed to Doppler — NEVER a
# hardcoded literal in the .tf.
p_tf_random() {
  if grep -Eq 'resource "random_password" "git_data_luks"' "$1" \
    && grep -Eq 'name[[:space:]]*=[[:space:]]*"GIT_DATA_LUKS_KEY"' "$1"; then echo 1; else echo 0; fi
}

# --- Cutover-script predicates (GAP-1/2/3 + DI-HIGH review) -----------------

# GAP-1: repoint_luks_mount exists AND re-points the mapper to the hardcoded path
# (/dev/mapper/git-data mounted at /mnt/git-data) AND rewrites /etc/fstab.
p_repoint() {
  if grep -Eq '^repoint_luks_mount\(\)' "$1" \
    && grep -Eq 'mount "\$LUKS_MAPPER" "\$OLD_ROOT"' "$1" \
    && grep -Eq '/etc/fstab' "$1"; then echo 1; else echo 0; fi
}

# GAP-1: a canary asserts /mnt/git-data's source device is the LUKS mapper, AND the
# DL-2 wipe is gated on it (CANARY_OK).
p_canary_gate() {
  if grep -Eq '^canary_luks_device\(\)' "$1" \
    && grep -Eq 'findmnt -no SOURCE "\$OLD_ROOT"' "$1" \
    && grep -Eq 'CANARY_OK' "$1" \
    && grep -Eq '\[ "\$CANARY_OK" != "1" \]' "$1"; then echo 1; else echo 0; fi
}

# GAP-2: prepare_luks_target idempotently luksOpens+mounts, key via stdin --key-file -
# (never argv), fail-loud on empty key.
p_prepare_luks() {
  local f="$1"
  if grep -Eq '^prepare_luks_target\(\)' "$f" \
    && grep -Eq 'cryptsetup luksOpen --key-file - "\$luks_dev"' "$f" \
    && grep -Eq 'GIT_DATA_LUKS_KEY.*empty' "$f" \
    && ! grep -Eq 'cryptsetup luks(Open|Format)[^|]*\$GIT_DATA_LUKS_KEY' "$f"; then echo 1; else echo 0; fi
}

# GAP-3: an EXIT trap auto-recovers (rollback on flip + release freeze), and a
# ROLLBACK-only mode exists.
p_trap_rollback() {
  if grep -Eq 'trap cleanup EXIT' "$1" \
    && grep -Eq 'FLIP_DONE" = "1" \].*rollback' "$1" \
    && grep -Eq '\[ "\$ROLLBACK" = "1" \]' "$1"; then echo 1; else echo 0; fi
}

# DI-HIGH: the delta-rsync + set-identity verify that gate the flip run AFTER the
# drain (acquire_freeze before delta_rsync before verify before flip in main()).
# Matches the indented call-sites (which carry trailing comments), not the col-0
# function definitions (`name() {`).
p_postdrain_gate() {
  local f="$1" a d v ff
  a="$(grep -nE '^[[:space:]]+acquire_freeze([[:space:]]|$)' "$f" | head -1 | cut -d: -f1)"
  d="$(grep -nE '^[[:space:]]+delta_rsync([[:space:]]|$)' "$f" | head -1 | cut -d: -f1)"
  v="$(grep -nE '^[[:space:]]+verify_set_identity([[:space:]]|$)' "$f" | head -1 | cut -d: -f1)"
  ff="$(grep -nE '^[[:space:]]+flip_flag_and_reload([[:space:]]|$)' "$f" | head -1 | cut -d: -f1)"
  if [ -n "$a" ] && [ -n "$d" ] && [ -n "$v" ] && [ -n "$ff" ] \
    && [ "$a" -lt "$d" ] && [ "$d" -lt "$v" ] && [ "$v" -lt "$ff" ]; then echo 1; else echo 0; fi
}

# DI-HIGH: the pre-receive hook honours the cutover freeze sentinel (fail-closed).
p_prereceive_freeze() {
  if grep -Eq 'cutover_freeze=' "$1" \
    && grep -Eq 'if \[ -e "\$cutover_freeze" \]; then' "$1"; then echo 1; else echo 0; fi
}

# --- #6570 dual-arch derivation predicates (A14-A17) ------------------------
# git-data was pinned to `cax11` (ARM64/Ampere) — a type orderable in 0 of 3 EU
# datacenters, so the host could never be born on its declared type. #6570 repins to
# `cpx22` (amd64) and DERIVES the arch from the type prefix instead of hardcoding it.
#
# These four are deliberately BEHAVIORAL, not bare-fragment greps. inngest-host.test.sh
# §9b measured that 5 of 8 realistic mutations passed a `grep -qF '<fragment>'` guard —
# including bug #6178 itself — because a fragment only certifies that a substring exists
# SOMEWHERE in the file, so it stays green while the live expression is inverted or
# commented out. Each predicate below extracts the expression's OWN bytes and replays
# the decision the host actually makes, and each carries a non-vacuity guard: a failed
# extraction must return 0 (fail loudly), never silently pass every case.

# A14: the Doppler download URL is arch-INTERPOLATED, with the escaping split correct.
# `$${DOPPLER_VERSION}` is a SHELL variable Terraform must pass through literally;
# `${doppler_arch}` is a Terraform interpolation that must have a templatefile map key.
# Getting that split backwards is silent: `$${doppler_arch}` renders a literal that bash
# expands to EMPTY, and .github/scripts/validate-infra-templates.sh skips any `$${key}`
# BY DESIGN, so the render gate is blind to it. This exact-form grep is the only guard.
# Verbatim shape from inngest-host.test.sh:177 (the sibling dual-arch host).
# BOTH interpolations are pinned, not just the URL. The plan named the silent direction
# as this change's top risk, and it can land on EITHER line — a `$${doppler_sha256}`
# renders an empty checksum just as invisibly as a `$${doppler_arch}` renders an empty
# arch. Guarding only the URL would leave the checksum half covered by a one-shot PR
# acceptance grep and by nothing durable afterwards.
p_doppler_arch_url() {
  # Comment-stripped FIRST. This file now carries an ESCAPING: block that names
  # $${doppler_arch} / $${doppler_sha256} in prose, so a bare whole-file grep is
  # satisfiable by the explanatory comment alone — the assertion would survive a
  # full revert to the hardcoded arm64 build (cq-assert-anchor-not-bare-token).
  local src
  src="$(sed 's/#.*//' "$1")"
  printf '%s\n' "$src" | grep -qF 'doppler_$${DOPPLER_VERSION}_linux_${doppler_arch}.tar.gz' || { echo 0; return; }
  printf '%s\n' "$src" | grep -qF 'DOPPLER_SHA256="${doppler_sha256}"' || { echo 0; return; }
  # The digest must be CONSUMED, not merely assigned. Without this, deleting the
  # verification line entirely leaves the whole A14/A15 apparatus green: a correct
  # checksum is proven computed and proven assigned, and nothing proves it is ever
  # compared against the downloaded tarball.
  printf '%s\n' "$src" | grep -qF 'echo "$${DOPPLER_SHA256}' || { echo 0; return; }
  printf '%s\n' "$src" | grep -qF 'sha256sum -c -' || { echo 0; return; }
  echo 1
}

# Extract a file's per-arch Doppler checksum pair as "<arm64sha> <amd64sha>", read from
# the ternary's own bytes. Comments are stripped FIRST so a checksum eulogized in prose
# can neither stand in for a live literal nor be miscounted.
# Emits a NORMALIZED, order-independent binding "amd64=<sha>;arm64=<sha>".
# Reading the ternary's CONDITION is the whole point: comparing the two literals in
# textual order cannot see a checksum<->arch PAIRING SWAP. Flipping the condition to
# `== "amd64"` leaves both literals present in the same order, so an order-compare
# stays green while the host verifies the amd64 tarball against the arm64 digest —
# and because that runcmd carries no `set -e`, it then installs it anyway, with the
# supply-chain check silently disarmed. Normalizing also makes the guard robust to a
# semantically identical refactor that inverts the condition deliberately.
canon_doppler_pair() {
  local line condarch t f
  # Strip `#` and whitespace-preceded `//` comments (HCL supports both). The `//` arm
  # requires leading whitespace or line-start so a `https://` URL is never truncated.
  line="$(sed -E 's;(^|[[:space:]])//.*;;; s;#.*;;' "$1" \
    | grep -E 'doppler_sha256[[:space:]]*=' | grep -F '?' | head -1)"
  [ -n "$line" ] || { echo ""; return; }
  condarch="$(printf '%s' "$line" | grep -oE '==[[:space:]]*"[a-z0-9]+"' | grep -oE '[a-z0-9]+"$' | tr -d '"')"
  t="$(printf '%s' "$line" | grep -oE '\?[[:space:]]*"[0-9a-f]{64}"' | grep -oE '[0-9a-f]{64}')"
  f="$(printf '%s' "$line" | grep -oE ':[[:space:]]*"[0-9a-f]{64}"' | grep -oE '[0-9a-f]{64}')"
  { [ -n "$condarch" ] && [ -n "$t" ] && [ -n "$f" ]; } || { echo ""; return; }
  case "$condarch" in
    arm64) printf 'amd64=%s;arm64=%s\n' "$f" "$t" ;;
    amd64) printf 'amd64=%s;arm64=%s\n' "$t" "$f" ;;
    *)     echo "" ;;
  esac
}

# A15: git-data's checksum pair is byte-identical to BOTH live canon sites, in ORDER.
# Derived from inngest-host.tf + zot-registry.tf rather than hardcoding a fourth literal
# (the CANON_WEB_HOSTS idiom, inngest-host.test.sh:135-145): a future Doppler version bump
# that updates the canon sites red-lines this until git-data follows. Order matters — it
# is what pins each checksum to its OWN arch, so a pairing SWAP (arm64 sha on the amd64
# arm) fails here even though both literals are still "present".
p_doppler_checksum_parity() {
  local gd_pair ing_pair zot_pair p
  gd_pair="$(canon_doppler_pair "$1")"
  ing_pair="$(canon_doppler_pair "$INNGEST_HOST_TF")"
  zot_pair="$(canon_doppler_pair "$ZOT_TF")"
  # Non-vacuity: every side must be a fully-formed normalized binding. Without this an
  # empty extraction on all three would compare "" == "" and fake a clean parity.
  for p in "$gd_pair" "$ing_pair" "$zot_pair"; do
    printf '%s' "$p" | grep -qE '^amd64=[0-9a-f]{64};arm64=[0-9a-f]{64}$' || { echo 0; return; }
  done
  if [ "$gd_pair" = "$ing_pair" ] && [ "$gd_pair" = "$zot_pair" ]; then echo 1; else echo 0; fi
}

# The templatefile map is the WIRE between the derivation (A16) and its consumer (A14).
# A16 proves local.git_data_arch is computed correctly; A14 proves the cloud-init reads
# ${doppler_arch}. Neither sees the map that connects them, so hardcoding
# `doppler_arch = "arm64"` there reproduces the exact #6570 boot-brick — arm64 binary on
# an x86 host, doppler never runs, GIT_DATA_LUKS_KEY never arrives, volume never opens —
# with the precondition still green (local.git_data_arch is still correctly amd64).
p_templatefile_wiring() {
  local src
  src="$(sed -E 's;(^|[[:space:]])//.*;;; s;#.*;;' "$1")"
  printf '%s\n' "$src" | grep -qE '^[[:space:]]*doppler_arch[[:space:]]*=[[:space:]]*local\.git_data_arch[[:space:]]*$' || { echo 0; return; }
  printf '%s\n' "$src" | grep -qE '^[[:space:]]*doppler_sha256[[:space:]]*=[[:space:]]*local\.git_data_doppler_sha256[[:space:]]*$' || { echo 0; return; }
  echo 1
}

# The phantom/wrong-arch tripwire is load-bearing ONLY while hcloud_server.git_data
# REFERENCES the data source: terraform prunes an unreferenced data source under
# `-target=`, and every git-data dispatch is -targeted. Deleting the precondition
# therefore disarms the data source silently — the untargeted PR-time plan still reads
# it, so CI and `terraform validate` both stay green and the only signal is prose.
# Comment-stripped, because `data.hcloud_server_type.git_data` appears in the
# surrounding explanatory comments (a bare grep would be satisfied by those alone).
p_tripwire_edge() {
  local src cond
  src="$(sed -E 's;(^|[[:space:]])//.*;;; s;#.*;;' "$1")"
  printf '%s\n' "$src" | grep -qE '^data "hcloud_server_type" "git_data"' || { echo 0; return; }
  printf '%s\n' "$src" | grep -qE '^[[:space:]]*precondition[[:space:]]*\{' || { echo 0; return; }
  # THREE LINES, NOT FOUR. The 4th line of this window is `error_message`, which interpolates
  # `data.hcloud_server_type.git_data.architecture` — so the clause below was satisfiable by the
  # MESSAGE. Measured (#7066 review): re-pointing the CONDITION to
  # `data.hcloud_server_type.registry.architecture` (a real data source, declared in
  # zot-registry.tf in this same root, so the HCL stays valid and fmt-clean) left the suite
  # 101/0 — the tripwire silently reading another host's architecture. This file closed
  # prose-satisfaction for COMMENTS throughout; `error_message` is prose the comment-stripper
  # cannot see.
  cond="$(printf '%s\n' "$src" | grep -A 2 -E '^[[:space:]]*condition[[:space:]]*=' | head -3)"
  printf '%s' "$cond" | grep -qF 'data.hcloud_server_type.git_data.architecture' || { echo 0; return; }
  # The enums MUST be mapped, never compared: hcloud emits x86/arm, the derived token is
  # amd64/arm64, so a direct compare is false on every plan forever and wedges the root.
  printf '%s' "$cond" | grep -qF '"arm"' || { echo 0; return; }
  printf '%s' "$cond" | grep -qF '"x86"' || { echo 0; return; }
  # Re-pointed at the module output with the R7 follow-through. This clause names the thing
  # the condition may not be compared against directly, so it goes VACUOUS the moment that
  # thing is renamed: while it still said `local.git_data_arch` — a reference git-data.tf no
  # longer contains — it was unmatchable, and would have reported clean against the very
  # regression it exists for. A negative assertion fails OPEN, so it is only ever as live as
  # its anchor; the mutation arm on A19 below now pins that.
  printf '%s' "$cond" | grep -qE 'architecture[[:space:]]*==[[:space:]]*module\.git_data_userdata\.arch' && { echo 0; return; }
  echo 1
}

# A16: the arch derivation is ORIENTED correctly. This is the only assertion that catches
# an INVERTED ternary — `startswith(..., "cax") ? "amd64" : "arm64"` ships cpx22 -> arm64,
# fails `sha256sum -c -` at boot, and produces exactly the failure this change prevents.
# A bare "the local is declared" grep cannot see it. Extract the prefix + both branch
# values, then replay the decision over the real type space.
p_arch_derivation() {
  local expr pfx tval fval pair t exp got
  # Anchored on the ASSIGNMENT at line-start, which distinguishes a DECLARATION from a
  # reference. Written when the caller still held a second copy, where a bare
  # `git_data_arch[[:space:]]*=` also matched its precondition's
  # `local.git_data_arch == "arm64" ? "arm" : "x86"` and made the extraction order-coupled.
  # That copy is gone and this predicate now only reads the module — but the anchor is also
  # what p_precondition_arch_source reuses as a NEGATIVE on the caller, and there the
  # distinction is the whole assertion: `[[:space:]]*=` matches the first `=` of an `==`, so
  # an unanchored form would read any future `x = local.git_data_arch == …` REFERENCE as a
  # re-declared duplicate and fail on a correct file.
  expr="$(sed -E 's;(^|[[:space:]])//.*;;; s;#.*;;' "$1" | grep -E '^[[:space:]]*git_data_arch[[:space:]]*=' | head -1)"
  [ -n "$expr" ] || { echo 0; return; }
  pfx="$(printf '%s' "$expr" | grep -oE 'startswith\(var\.git_data_server_type,[[:space:]]*"[a-z]+"\)' | grep -oE '"[a-z]+"' | tr -d '"')"
  tval="$(printf '%s' "$expr" | grep -oE '\?[[:space:]]*"[a-z0-9]+"' | grep -oE '"[a-z0-9]+"' | tr -d '"')"
  fval="$(printf '%s' "$expr" | grep -oE ':[[:space:]]*"[a-z0-9]+"' | grep -oE '"[a-z0-9]+"' | tr -d '"')"
  # Non-vacuity: a partial extraction must fail loudly, never replay vacuously.
  { [ -n "$pfx" ] && [ -n "$tval" ] && [ -n "$fval" ]; } || { echo 0; return; }
  # cax* is Ampere/ARM; cpx*/cx*/ccx* are all x86. Synthesized types, not a live probe
  # (cq-test-fixtures-synthesized-only) — this pins the DERIVATION, not today's stock.
  # The arm64 class had cardinality 1 (cax11 alone) — a claim quantified over the ARM
  # line but sampled once. Hetzner's ARM lineup is cax11/21/31/41; all four are replayed
  # so a truncated prefix (e.g. "ca") cannot pass on a single lucky member.
  # `ca99` PINS THE PREFIX LENGTH. Measured (#7066 review): the comment above claimed four
  # cax members stop a truncated "ca" from passing, and it was false — cax11/21/31/41 all start
  # with "ca" and cpx/cx/ccx start with none of it, so widening the prefix to "ca" kept the
  # suite 101/0. Cardinality is not discrimination: four members of one shape are one member.
  # A synthesized type that starts with "ca" but is NOT Ampere is the only input that separates
  # the two prefixes, and synthesized is the convention here (cq-test-fixtures-synthesized-only)
  # — this pins the DERIVATION, not today's Hetzner stock.
  for pair in "cax11:arm64" "cax21:arm64" "cax31:arm64" "cax41:arm64" \
              "ca99:amd64" \
              "cpx22:amd64" "cx23:amd64" "ccx13:amd64"; do
    t="${pair%%:*}"; exp="${pair##*:}"
    case "$t" in "$pfx"*) got="$tval" ;; *) got="$fval" ;; esac
    [ "$got" = "$exp" ] || { echo 0; return; }
  done
  echo 1
}

# A17: the declared default is not a `cax*` type — #6570 itself, statically. The whole
# `cax` line was orderable in 0 of 3 EU datacenters, so a regression here re-creates an
# unbornable host. stock-preflight-gate.sh covers the LIVE case at dispatch (it re-probes
# .server_types.available); this covers the SOURCE case at PR time, where no API is
# reachable. Block-scoped: a bare `grep 'default = "cpx22"'` on this file is green on the
# UNMODIFIED tree because inngest_server_type already defaults to cpx22.
p_default_not_cax() {
  local d
  # COMMENT-STRIPPED, AND THE VALUE TAKEN FROM THE ASSIGNMENT — never `$NF`. After
  # `gsub(/[",]/,"")`, `$NF` on `default = "cpx22" # regressed from cax11` is the COMMENT's
  # last word. Measured: `default = "cax11" # regressed from cpx22` made this predicate
  # return 1 on a file pinning an unbornable type (#6570: cax had stock in 0 of 3 EU DCs).
  # `_var_default` in git-data-rung2-rehearsal.test.sh already had this right; this is the
  # same extraction.
  d="$(sed 's/[[:space:]]#.*$//' "$1" \
       | awk '/^variable "git_data_server_type"/{i=1}
              i&&/^[[:space:]]*default[[:space:]]*=/{
                sub(/^[^=]*=[[:space:]]*/, ""); gsub(/[",[:space:]]/, ""); print; exit
              }
              i&&/^}/{exit}')"
  [ -n "$d" ] || { echo 0; return; }
  case "$d" in cax*) echo 0 ;; *) echo 1 ;; esac
}

# ---------------------------------------------------------------------------------
# #6982 — pre-birth hardening guards.
# ---------------------------------------------------------------------------------

# A20: EVERY `doppler run` names the config its service token is actually scoped to.
#
# THIS IS THE #6982 W0 REGRESSION GUARD. doppler_service_token.git_data is scoped to
# `prd_git_data`, but both invocations named `--config prd`. Measured under a token
# scoped exactly that way: exit 1, "This token does not have access to requested config
# 'prd'", GIT_DATA_LUKS_KEY absent. `doppler run` therefore exited BEFORE exec'ing the
# LUKS heredoc, so its `set -euo pipefail` ran zero times, luksOpen never ran, and the
# host booted dark with sshd up. A6 above asserts only that the STRING `doppler run`
# survives — it is blind to the scope, which is why this arm exists.
#
# (#7025, R1) THE TEMPLATE NO LONGER CARRIES THE CONFIG NAME AS A LITERAL. The rung-2
# rehearsal boots this same template against a SCRATCH Doppler config, and a token scoped
# to that config exits 1 against a hardcoded `prd_git_data` — the identical W0 failure, in
# the rehearsal instead of the birth. So the config name became `${doppler_config_name}`, a
# templatefile var, and this guard splits in two:
#
#   A20  (here)  — every `doppler run` in the TEMPLATE names the same interpolation, so the
#                  two invocations can never disagree with each other. A hardcoded `prd`
#                  still fails, which is the regression this arm was built for.
#   A20b (below) — the PRODUCTION caller binds that var to the config the service token is
#                  actually scoped to. Without A20b, A20 alone would be satisfied by a
#                  template that consistently names a variable pointing anywhere.
#
# The siblings keep the literal: they are plain scripts/units, never rendered.
p_doppler_config_scope() {
  local n_run n_scoped
  # Anchor on the COMMAND at line start. A bare 'doppler run' also matches the prose
  # comment above the bootstrap invocation, which made this 3-vs-2 and the guard
  # permanently red (cq-assert-anchor-not-bare-token).
  n_run=$(grep -Ec '^[[:space:]]*doppler run ' "$1" || true)
  n_scoped=$(grep -Ec '^[[:space:]]*doppler run --project soleur --config \$\{doppler_config_name\} ' "$1" || true)
  # Guard the SIBLINGS too. Scoping this to cloud-init alone let the identical W0 defect
  # survive in git-data-cutover.sh — a file that runs ON this host under the same
  # single-config token — because the guard structurally could not see it.
  for _sib in "${DIR}/git-data-cutover.sh" "${DIR}/git-data-gc-failure.service" \
           "${DIR}/git-data-gc.service"; do
    [ -f "$_sib" ] || continue
    n_run=$(( n_run + $(grep -Ec 'doppler run --project soleur ' "$_sib" || true) ))
    n_scoped=$(( n_scoped + $(grep -Ec 'doppler run --project soleur --config prd_git_data ' "$_sib" || true) ))
  done
  if [ "$n_run" -ge 2 ] && [ "$n_run" -eq "$n_scoped" ]; then echo 1; else echo 0; fi
}

# A20b (#7025, R1): the PRODUCTION render binds ${doppler_config_name} to the config the
# boot service token is actually scoped to.
#
# This is the half A20 structurally cannot see. Once the config name is a variable, the
# template is internally consistent no matter WHAT the caller passes — so the binding is
# where the W0 failure now lives. Both sides are extracted by shape from their own files
# rather than compared against a hardcoded "prd_git_data": a literal here would pass while
# the token moved, which is the drift this whole arm exists to catch.
#
# $1 = git-data.tf (the caller). The token's config is read from git-data-luks.tf, which
# declares doppler_config.git_data_prd and points doppler_service_token.git_data at it.
p_doppler_config_binding() {
  local bound declared
  bound="$(grep -oE '^[[:space:]]*doppler_config_name[[:space:]]*=[[:space:]]*"[^"]+"' "$1" \
           | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  # Same extraction as A17 and `_var_default`, for the same reason: `$NF` after
  # `gsub(/[",]/,"")` reads a TRAILING COMMENT's last word. Measured: regressing the config to
  # `name = "prd" # the boot service token is scoped to prd_git_data` made `declared` read
  # back as `prd_git_data` and the whole suite reported 101/0 — while the host would run
  # `doppler run --config prd` under a token scoped to `prd_git_data`, exit 1, never reach
  # `cryptsetup luksOpen`, and boot dark with sshd up. That is #6982 W0 verbatim.
  declared="$(sed 's/[[:space:]]#.*$//' "$DIR/git-data-luks.tf" \
              | awk '/^resource "doppler_config" "git_data_prd"/{i=1}
                     i&&/^[[:space:]]*name[[:space:]]*=/{
                       sub(/^[^=]*=[[:space:]]*/, ""); gsub(/[",[:space:]]/, ""); print; exit
                     }
                     i&&/^}/{exit}')"
  if [ -n "$bound" ] && [ -n "$declared" ] && [ "$bound" = "$declared" ]; then
    echo 1
  else
    echo 0
  fi
}

# A21: the boot emitter exists, is delivered as an executable file, and the FATAL channel
# reads the BAKED DSN rather than Doppler (a DSN fetched from Doppler is dark exactly
# when Doppler is the broken stage).
p_emitter_present() {
  if grep -Eq '^[[:space:]]*- path: /usr/local/bin/git-data-emit$' "$1" \
     && grep -Eq "^[[:space:]]*DSN='\\\$\\{sentry_dsn\\}'" "$1"; then echo 1; else echo 0; fi
}

# A22: every `trap ... EXIT` arming site carries the rc guard. Without it `trap EXIT`
# fires on a SUCCESSFUL exit too, so every healthy boot emits level=fatal and the whole
# fatal channel inverts into noise (R7/AC36/T17). Anchored on the guard's syntax, and the
# count is compared against the number of arming sites so a NEW unguarded trap fails.
p_trap_rc_guard() {
  local n_trap n_guard n_bind n_first
  n_trap=$(grep -Ec '^[[:space:]]*trap [a-z_]+ EXIT$' "$1" || true)
  n_guard=$(grep -Ec '^[[:space:]]*\[ "\$rc" -eq 0 \] && exit 0$' "$1" || true)
  # The BINDING, not just the guard line. `rc=0` satisfies every count-based assertion while
  # making `[ "$rc" -eq 0 ] && exit 0` ALWAYS fire — so no handler can emit a fatal at any
  # stage and every failing stage exits 0. Measured: that mutation left all three suites green.
  n_bind=$(grep -Ec '^[[:space:]]*rc=\$\?$' "$1" || true)
  # And `rc=$?` must be the FIRST statement in each handler: `$?` is clobbered by any command
  # before it, so a guard placed after the emit reads the emit's status, not the failure's.
  n_first=$(grep -A1 -E '^[[:space:]]*[a-z_]+\(\) \{$' "$1" | grep -Ec '^[[:space:]]*rc=\$\?$' || true)
  # FLOOR 3 -> 2 (#7227): bootstrap_err was deleted. It was byte-identical to on_err but for
  # a title $STAGE already supplies, and it was never disarmed — so a gc_timer failure emitted
  # "git-data bootstrap FAILED". Two arming sites remain: on_err (parent) and luks_err (the
  # doppler child). The floor is non-vacuity only; the PROPERTY is the three equalities below,
  # which are unchanged and still bind every site that exists.
  if [ "$n_trap" -ge 2 ] && [ "$n_guard" -eq "$n_trap" ] \
     && [ "$n_bind" -eq "$n_trap" ] && [ "$n_first" -ge "$n_trap" ]; then echo 1; else echo 0; fi
}

# A23: the delivery assertion (AC34) — the ONE emit call with no `|| true`, gated by an
# `if !` so a non-delivering emitter fails the boot LOUDLY instead of silently.
p_delivery_assert() {
  # ANCHORED AT LINE START and stripped of comments: the previous form was an unanchored
  # substring match that a prose line could satisfy. Pins all three parts of the contract:
  # the executable precondition, the rc capture, and the refusal on the STRUCTURAL class
  # only (rc 2) — a blanket `if ! emit` would make a Sentry 429 a permanent boot abort.
  local src
  src="$(sed 's/#.*//' "$1")"
  printf '%s\n' "$src" | grep -Eq '^[[:space:]]*if \[ ! -x /usr/local/bin/git-data-emit \]; then' || { echo 0; return; }
  printf '%s\n' "$src" | grep -Eq '^[[:space:]]*_emit_rc=\$\?$' || { echo 0; return; }
  printf '%s\n' "$src" | grep -Eq '^[[:space:]]*if \[ "\$_emit_rc" -eq 2 \]; then' || { echo 0; return; }
  echo 1
}

# A24: sshd slot bounding lands INSIDE the 01-hardening.conf write_files block (AC5) —
# anchored on the block, not on a bare token that a comment could satisfy.
p_sshd_limits() {
  local block
  block=$(awk '/- path: \/etc\/ssh\/sshd_config.d\/01-hardening.conf/,/permissions:/' "$1")
  if printf '%s' "$block" | grep -Eq '^[[:space:]]*MaxStartups[[:space:]]+[0-9]' \
     && printf '%s' "$block" | grep -Eq '^[[:space:]]*MaxSessions[[:space:]]+[0-9]' \
     && printf '%s' "$block" | grep -Eq '^[[:space:]]*ClientAliveInterval[[:space:]]+60$'; then echo 1; else echo 0; fi
}

# A25: `set -e` is armed in runcmd, and the checksum block is UNDER it — the supply-chain
# half of issue item 3. Asserted by ORDER: `set -e` must appear before `sha256sum -c -`.
p_set_e_before_checksum() {
  # STRIP COMMENTS FIRST. A bare `grep -n 'sha256sum -c -'` matches the STAGE prose comment
  # that quotes the command, so the ordering was measured against a comment and the real
  # block was never seen — `|| true` on the actual checksum line left this GREEN.
  local src l_sete l_sum
  src="$(sed 's/#.*//' "$1")"
  l_sete=$(printf '%s\n' "$src" | grep -n '^[[:space:]]*set -e$' | head -1 | cut -d: -f1)
  l_sum=$(printf '%s\n' "$src" | grep -n 'sha256sum -c -' | head -1 | cut -d: -f1)
  [ -n "$l_sete" ] && [ -n "$l_sum" ] && [ "$l_sete" -lt "$l_sum" ] || { echo 0; return; }
  # And the checksum must not be TOLERATED. `set -e` before a `|| true`-suffixed command
  # aborts nothing; the ordering alone is not the property.
  printf '%s\n' "$src" | grep -E 'sha256sum -c -' | grep -qE '\|\|[[:space:]]*true' && { echo 0; return; }
  echo 1
}

# A26: no BARE terraform directive anywhere (AC4). The doubled form `curl -w` would need
# must still pass, so the pattern is negative-lookbehind, not a plain substring.
p_no_bare_directive() {
  # NOT `grep -cP … | grep -q '^0$'`: grep -c PRINTS 0 but EXITS 1 when there are no
  # matches, and this file runs under `set -o pipefail`, so that pipeline fails on a
  # CLEAN file and the guard reports the opposite of the truth.
  local n
  n=$(grep -cP '(?<!%)%\{' "$1" || true)
  if [ "$n" -eq 0 ]; then echo 1; else echo 0; fi
}

# A27: the DELIVERY MECHANISM of every plain-text-delivered script.
#
# NOT byte-identity — it was named that and is not. This is a STATIC check on the raw
# template: it never renders and never compares a byte, so a block-scalar chomp (`|` -> `|-`),
# a trailing-whitespace strip, or an indent() that swallowed a blank line all pass it while
# shipping a script that differs from the repo's. The real comparison is B1 in
# git-data-runcmd-rehearsal.test.sh, which renders, parses, and sha256s each payload against
# its source file (mutation-proven: chomping one payload's scalar turns it red).
#
# What A27 does pin, which is worth pinning on its own: #6982 moved five scripts off
# `encoding: b64` because base64 defeats gzip and cost 57 % of the 32 KB user_data budget.
# The re-scan hazard base64 was guarding against does not exist (templatefile does not
# re-scan an interpolated VALUE), so each script must be delivered via the indent+file
# interpolation, and NONE may still carry a b64 encoding line.
p_plain_script_delivery() {
  local f n_indent
  # The TEMPLATE var names are underscored (git_data_bootstrap), not the hyphenated
  # filenames — matching on hyphens found nothing and the guard was vacuously red.
  for f in git_data_bootstrap git_data_provision git_data_transport_wrapper \
           git_data_remove git_data_pre_receive_placeholder; do
    grep -Eq "indent\\(6, ${f}\\)" "$1" || { echo 0; return; }
  done
  n_indent=$(grep -Ec '^[[:space:]]*encoding: b64$' "$1" || true)
  if [ "$n_indent" -eq 0 ]; then echo 1; else echo 0; fi
}

# --- Assertion + mutation harness ---
# assert_holds <name> <predicate-fn> <file>            -> predicate MUST be 1
# assert_mutation <name> <predicate-fn> <file> <sed>   -> after the sed mutation the
#                                                          predicate MUST flip to 0
assert_holds() {
  local name="$1" fn="$2" file="$3" got
  got="$($fn "$file")"
  if [ "$got" = "1" ]; then pass; else fail "$name: property does not hold on the real file"; fi
}
assert_mutation() {
  local name="$1" fn="$2" file="$3" sed_expr="$4" tmp got
  tmp="$(mktemp "${TMPDIR:-/tmp}/gdluks-mut.XXXXXX")"
  # (#7204) THE MUTATION MUST LAND BEFORE ITS RESULT MEANS ANYTHING.
  #
  # This wrapper previously ran `sed -E "$sed_expr" "$file" > "$tmp"` and went straight to
  # the predicate. Both failure modes below are SILENT FALSE PASSES, and they are the exact
  # misattribution this suite's own S1/T5 arms exist to prevent — one level up, in the
  # harness itself:
  #
  #   (1) sed ERRORS (a BRE `\(...\)` written for an -E/ERE expression, a delimiter clash
  #       such as `|` used both as separator and inside `||`). The redirect has already
  #       truncated $tmp, so the predicate runs against an EMPTY FILE, finds nothing, and
  #       returns 0 — which this function reads as "the mutation flipped the check". Every
  #       such arm reports PASS while testing nothing at all. Measured: two arms added for
  #       #7204 did exactly this before the guard below existed.
  #   (2) sed SUCCEEDS but matches nothing (a re-anchored predicate, a renamed symbol), so
  #       the "mutant" is byte-identical to the original. A predicate that legitimately
  #       returns 0 on the real file then reports a passing mutation arm forever.
  #
  # Both now fail LOUD, and the message names which one — because "the mutation did not
  # land" and "the guard cannot detect this defect" demand opposite fixes.
  if ! sed -E "$sed_expr" "$file" > "$tmp" 2>"${tmp}.err"; then
    fail "$name: MUTATION SED FAILED — $(head -1 "${tmp}.err" 2>/dev/null)" \
         "The expression is invalid (note: this harness uses sed -E, so BRE '\\(...\\)' and a '|' delimiter around '||' are both errors). An errored sed leaves an EMPTY mutant, on which most predicates return 0 — so this arm would have reported PASS while asserting nothing."
    rm -f "$tmp" "${tmp}.err"; return
  fi
  if cmp -s "$file" "$tmp"; then
    fail "$name: MUTATION DID NOT LAND — the expression matched nothing and the mutant is byte-identical" \
         "Re-anchor the expression against the CURRENT text. As written this arm certifies nothing."
    rm -f "$tmp" "${tmp}.err"; return
  fi
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION did not flip the check to failing (predicate still passed on a broken copy)"; fi
  rm -f "$tmp" "${tmp}.err"
}

# A1: isLuks idempotency guard.
assert_holds   "A1 isLuks-guard" p_isluks "$CLOUD_INIT"
assert_mutation "A1 isLuks-guard" p_isluks "$CLOUD_INIT" 's/cryptsetup isLuks/cryptsetup NOTisLuks/'

# A2: key via --key-file - stdin, never argv.
assert_holds   "A2 key-file-stdin" p_keyfile_stdin "$CLOUD_INIT"
# Mutation: rewrite a luksFormat to take the key as a positional argv token.
assert_mutation "A2 key-file-stdin" p_keyfile_stdin "$CLOUD_INIT" \
  's#cryptsetup luksFormat --batch-mode --type luks2 --key-file - "\$DEV"#cryptsetup luksFormat --batch-mode --type luks2 "\$GIT_DATA_LUKS_KEY" "\$DEV"#'

# A3: printf-pipe stdin delivery present.
assert_holds   "A3 printf-pipe" p_printf_pipe "$CLOUD_INIT"
assert_mutation "A3 printf-pipe" p_printf_pipe "$CLOUD_INIT" "s/printf '%s'/printf 'X%sX'/"

# A4: mapper mounted at FRESH_ROOT.
assert_holds   "A4 mapper-mount" p_mapper_mount "$CLOUD_INIT"
assert_mutation "A4 mapper-mount" p_mapper_mount "$CLOUD_INIT" 's#/mnt/git-data-luks#/mnt/git-data#g'

# A5: fail-loud on empty key.
assert_holds   "A5 fail-loud" p_fail_loud "$CLOUD_INIT"
assert_mutation "A5 fail-loud" p_fail_loud "$CLOUD_INIT" 's/\[ -n "\$GIT_DATA_LUKS_KEY" \]/true/'

# A6: doppler run wraps the setup (Doppler-injected env).
assert_holds   "A6 doppler-run" p_doppler_run "$CLOUD_INIT"
assert_mutation "A6 doppler-run" p_doppler_run "$CLOUD_INIT" 's/doppler run/doppler_run/g'

# A7: passphrase is random_password → doppler_secret (no literal in .tf).
assert_holds   "A7 tf-random-secret" p_tf_random "$LUKS_TF"
assert_mutation "A7 tf-random-secret" p_tf_random "$LUKS_TF" 's/random_password/static_password/g'

# A8 (GAP-1): repoint_luks_mount re-points the mapper to the hardcoded path.
assert_holds    "A8 repoint-mount" p_repoint "$CUTOVER"
assert_mutation "A8 repoint-mount" p_repoint "$CUTOVER" 's#mount "\$LUKS_MAPPER" "\$OLD_ROOT"#mount "\$LUKS_MAPPER" "\$FRESH_ROOT"#'

# A9 (GAP-1): canary asserts the LUKS device AND gates the wipe on CANARY_OK.
assert_holds    "A9 canary-gate" p_canary_gate "$CUTOVER"
assert_mutation "A9 canary-gate" p_canary_gate "$CUTOVER" 's/CANARY_OK/CANARY_NOPE/g'

# A10 (GAP-2): prepare_luks_target unlocks via stdin --key-file -, key never argv.
assert_holds    "A10 prepare-luks" p_prepare_luks "$CUTOVER"
assert_mutation "A10 prepare-luks" p_prepare_luks "$CUTOVER" \
  's#cryptsetup luksOpen --key-file - "\$luks_dev" git-data#cryptsetup luksOpen "\$GIT_DATA_LUKS_KEY" "\$luks_dev" git-data#'

# A11 (GAP-3): EXIT-trap auto-rollback + ROLLBACK-only mode.
assert_holds    "A11 trap-rollback" p_trap_rollback "$CUTOVER"
assert_mutation "A11 trap-rollback" p_trap_rollback "$CUTOVER" 's/trap cleanup EXIT/trap - EXIT/'

# A12 (DI-HIGH): the flip-gating rsync+verify run AFTER the drain (main() order).
assert_holds    "A12 postdrain-gate" p_postdrain_gate "$CUTOVER"
# Mutation: neutralize the drain call-site so the ordered gate can no longer be
# proven (models the pre-fix "verify races live writers" arrangement) → flips to 0.
assert_mutation "A12 postdrain-gate" p_postdrain_gate "$CUTOVER" \
  's/^([[:space:]]+)acquire_freeze([[:space:]])/\1XdrainX\2/'

# A13 (DI-HIGH): the pre-receive hook denies receive-pack while the freeze sentinel exists.
assert_holds    "A13 prereceive-freeze" p_prereceive_freeze "$PRERECEIVE"
assert_mutation "A13 prereceive-freeze" p_prereceive_freeze "$PRERECEIVE" 's/cutover_freeze=/cutover_nofreeze=/g'

# --- #6570 dual-arch derivation (A14-A17) ---

# A14: arch-interpolated Doppler URL with the $${shell} / ${terraform} split correct.
assert_holds    "A14 doppler-arch-url" p_doppler_arch_url "$CLOUD_INIT"
# Mutation: revert to the pre-#6570 hardcoded arm64 build — the actual regression.
assert_mutation "A14 doppler-arch-url" p_doppler_arch_url "$CLOUD_INIT" \
  's/_linux_[^"]*\.tar\.gz/_linux_arm64.tar.gz/'
# Mutation: the SILENT escaping direction — a double-$ on the TERRAFORM var renders a
# literal ${doppler_sha256} that bash expands to EMPTY, so `sha256sum -c -` is handed a
# blank digest. terraform validate stays green and validate-infra-templates.sh skips
# $${key} BY DESIGN, so this assertion is the only thing between that typo and a boot.
assert_mutation "A14 doppler-arch-url (silent \$\$ escape)" p_doppler_arch_url "$CLOUD_INIT" \
  's;DOPPLER_SHA256="\$\{;DOPPLER_SHA256="$$\{;'

# A15: checksum pair byte-equals the two canon sites, in arm64-then-amd64 order.
# Read from the MODULE: since #7025 R7 that is the only place the pair exists, and it is
# the copy the download actually verifies against.
assert_holds    "A15 doppler-checksum-parity" p_doppler_checksum_parity "$GIT_DATA_MODULE_TF"
# Mutation: collapse the arm64 arm onto the amd64 checksum (models a pairing swap /
# copy-paste of one literal over both arms) -> the pair no longer equals canon.
assert_mutation "A15 doppler-checksum-parity" p_doppler_checksum_parity "$GIT_DATA_MODULE_TF" \
  's/f1954f3717fe4c5b65e906a3c6dfe0d20e97b032af35e43db41250931302e143/9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db/'

# A16: derivation orientation (the inverted-ternary catcher), on the SINGLE derivation.
#
# Since the R7 follow-through there is exactly one, in modules/git-data-userdata/main.tf —
# the render both roots call. It picks the binary AND, through the module's `arch` output,
# the arch the phantom-type precondition validates. So an inversion here is #6570 itself:
# `startswith(..., "cax") ? "amd64" : "arm64"` ships cpx22 -> arm64, `sha256sum -c -` fails
# at boot, and every "the local is declared" grep stays green. A bare declaration grep
# cannot see it — extract the prefix and both branch values, replay the real type space.
assert_holds    "A16 arch-derivation (module)" p_arch_derivation "$GIT_DATA_MODULE_TF"
assert_mutation "A16 arch-derivation (module)" p_arch_derivation "$GIT_DATA_MODULE_TF" \
  's/\? "arm64" : "amd64"/? "amd64" : "arm64"/'

# A16b: the precondition CONSUMES that derivation, and the caller declares no second one.
#
# An earlier revision of R7 kept a byte-equal copy of the ternary in git-data.tf to feed the
# phantom/wrong-arch precondition, and held the two copies equal with four arms comparing
# them as text. The caller now reads `module.git_data_userdata.arch`, which makes "the arch
# you validate differs from the arch you download" UNEXPRESSIBLE rather than policed: there
# is one ternary, and A16 covers inverting it.
#
# That retires the parity comparison, not the coverage. The refactor MOVES the drift class
# onto the WIRE — re-introduce a local and point the condition at it, or drop a literal in
# its place, and the precondition is once again validating an arch the render never
# selected, with A16 green because the module's ternary is untouched. Same relationship A18
# guards between the derivation and the templatefile map, and the same reason A15/A16/A18
# read the module: the assertion has to sit where the value actually flows.
p_precondition_arch_source() {
  local src cond
  src="$(sed -E 's;(^|[[:space:]])//.*;;; s;#.*;;' "$1")"
  # Scoped to the CONDITION, spanning exactly the three lines it occupies. A 4-line window
  # would swallow `error_message`, which interpolates the SAME reference — and the M1
  # mutation below leaves that message intact, so the wider window would read a re-pointed
  # condition as clean. Comment-stripped for the same reason: the resource's own prose names
  # `module.git_data_userdata.arch` three times (cq-assert-anchor-not-bare-token).
  cond="$(printf '%s\n' "$src" | grep -A 2 -E '^[[:space:]]*condition[[:space:]]*=' | head -3)"
  # Non-vacuity: a missing or truncated extraction must fail loudly, never assert on nothing.
  printf '%s\n' "$cond" | grep -qE '^[[:space:]]*condition[[:space:]]*=' || { echo 0; return; }
  printf '%s\n' "$cond" | grep -qF 'module.git_data_userdata.arch' || { echo 0; return; }
  # Negative space: NO second derivation in the caller. Anchored on the ASSIGNMENT at
  # line-start, so neither the module reference above nor the locals block's explanation of
  # why the local is absent can satisfy it.
  printf '%s\n' "$src" | grep -qE '^[[:space:]]*git_data_arch[[:space:]]*=' && { echo 0; return; }
  echo 1
}
# AND THIS ARM IS WHAT KEEPS A19'S NEGATIVE CLAUSE ALIVE — the coupling is load-bearing and
# was undocumented. A19's direct-compare check is a NEGATIVE, so it fails OPEN the moment its
# anchor stops matching anything: that is exactly how it went vacuous when the refactor deleted
# `local.git_data_arch` while the clause still named it. Re-pointing it at
# `module.git_data_userdata.arch` fixed the instance; what stops it recurring is that A16b
# asserts the SAME reference POSITIVELY. Rename the module and A16b reddens immediately, so the
# negative can never again be left silently naming something that does not exist.
assert_holds    "A16b precondition-arch-source" p_precondition_arch_source "$GIT_DATA_TF"
# Mutation 1: re-point the condition at a caller-side local, leaving `error_message` reading
# the module output. Visible ONLY to the condition-scoped extraction — a whole-file grep for
# `module.git_data_userdata.arch` is satisfied by the untouched message.
assert_mutation "A16b precondition-arch-source (condition re-pointed)" \
  p_precondition_arch_source "$GIT_DATA_TF" \
  's/module\.git_data_userdata\.arch == "arm64"/local.git_data_arch == "arm64"/'
# Mutation 2: the duplicate ternary returns to the caller's locals while the condition still
# reads the module output — the exact half-migrated state the R7 follow-through removed, and
# the one the two copies used to drift apart from. Visible ONLY to the negative-space clause.
#
# Anchored on the `trimspace(` binding, not a bare `git_remove_pubkey`: that name also
# appears as a module ARGUMENT further down, and the loose anchor injected a `locals`
# declaration into the middle of the module block too. Both insertions trip the clause, so
# the arm passed either way — but a mutation should model the drift it is named for, not
# also produce HCL nobody would write.
assert_mutation "A16b precondition-arch-source (duplicate local restored)" \
  p_precondition_arch_source "$GIT_DATA_TF" \
  's;^([[:space:]]*)git_remove_pubkey([[:space:]]*)= trimspace\((.*)$;\1git_remove_pubkey\2= trimspace(\3\n\1git_data_arch = startswith(var.git_data_server_type, "cax") ? "arm64" : "amd64";'

# A17: the git_data_server_type default is not an (unorderable) cax* type.
assert_holds    "A17 default-not-cax" p_default_not_cax "$VARIABLES_TF"
# Mutation: regress the default to cax11 (#6570 itself).
assert_mutation "A17 default-not-cax" p_default_not_cax "$VARIABLES_TF" \
  's/default([[:space:]]*)=[[:space:]]*"cpx22"/default\1= "cax11"/'

# A18: the templatefile map wires BOTH derived locals through to the cloud-init.
# The map moved into the module with the render it belongs to (#7025 R7); asserted there,
# because git-data.tf no longer contains a templatefile call to wire anything through.
assert_holds    "A18 templatefile-wiring" p_templatefile_wiring "$GIT_DATA_MODULE_TF"
# Mutation: the #6570 regression, relocated from the cloud-init to the var map.
assert_mutation "A18 templatefile-wiring" p_templatefile_wiring "$GIT_DATA_MODULE_TF" \
  's;^([[:space:]]*)doppler_arch([[:space:]]*)=[[:space:]]*local\.git_data_arch[[:space:]]*$;\1doppler_arch\2= "arm64";'

# A19: the tripwire's referencing edge survives, and the enums stay MAPPED not compared.
assert_holds    "A19 tripwire-edge" p_tripwire_edge "$GIT_DATA_TF"
# Mutation: drop the precondition — the data source is then pruned under -target= and the
# phantom-type guard fires on zero production paths, silently.
assert_mutation "A19 tripwire-edge" p_tripwire_edge "$GIT_DATA_TF" \
  's;^([[:space:]]*)precondition([[:space:]]*)\{;\1notaprecondition\2{;'
# Mutation: compare the enums DIRECTLY instead of mapping them. `"amd64" == "x86"` is false
# on every plan forever, so this wedges the whole root including unrelated applies. Detected
# by the direct-compare clause ALONE — the "arm"/"x86" greps still match the orphaned
# mapping line below it — which is the point: that clause is a negative, so it fails OPEN,
# and until the R7 follow-through re-pointed it at the module output it named a reference
# git-data.tf no longer contains and could not have fired on this at all.
assert_mutation "A19 tripwire-edge (enums compared, not mapped)" p_tripwire_edge "$GIT_DATA_TF" \
  's;architecture == \($;architecture == module.git_data_userdata.arch;'

# --- #6982 assertions ---------------------------------------------------------------

# A20: the W0 config-scope regression guard.
assert_holds    "A20 doppler-config-scope" p_doppler_config_scope "$CLOUD_INIT"
# Mutation: revert to the pre-#6982 `--config prd`, the exact form measured to boot dark.
# Targets the #7025 interpolation, because that is what the template carries now — the old
# `s/--config prd_git_data/…/` expression would match NOTHING here and assert_mutation would
# report the predicate as un-flippable rather than the guard as absent.
assert_mutation "A20 doppler-config-scope" p_doppler_config_scope "$CLOUD_INIT" \
  's/--config \$\{doppler_config_name\}/--config prd/g'

# A20b (#7025, R1): the production caller binds that interpolation to the token's own config.
assert_holds    "A20b doppler-config-binding" p_doppler_config_binding "$GIT_DATA_TF"
# Mutation: bind the render to `prd` — the full-prd config the boot token cannot read. This
# is the #6982 W0 failure relocated from the template to the caller, and it is invisible to
# A20, which would stay green because the template is still internally consistent.
assert_mutation "A20b doppler-config-binding" p_doppler_config_binding "$GIT_DATA_TF" \
  's/doppler_config_name([[:space:]]*)=([[:space:]]*)"prd_git_data"/doppler_config_name\1=\2"prd"/'

# A21: the emitter exists and reads the BAKED DSN.
assert_holds    "A21 emitter-present" p_emitter_present "$CLOUD_INIT"
# Mutation: point the fatal channel at Doppler instead of the baked value — dark exactly
# when Doppler is the broken stage.
assert_mutation "A21 emitter-present" p_emitter_present "$CLOUD_INIT" \
  's;^([[:space:]]*)DSN=.*;\1DSN=@FROMDOPPLER@;'

# A22: every trap arming site carries the rc guard (a healthy boot emits zero fatals).
assert_holds    "A22 trap-rc-guard" p_trap_rc_guard "$CLOUD_INIT"
# Mutation: drop the guard — every SUCCESSFUL boot would then emit level=fatal.
assert_mutation "A22 trap-rc-guard" p_trap_rc_guard "$CLOUD_INIT" \
  's;^([[:space:]]*)\[ "\$rc" -eq 0 \] && exit 0$;\1true;'

# A23: the AC34 delivery assertion.
assert_holds    "A23 delivery-assert" p_delivery_assert "$CLOUD_INIT"
# Mutation: make the one checking call fail-open like every other call site.
assert_mutation "A23 delivery-assert" p_delivery_assert "$CLOUD_INIT" \
  's#^([[:space:]]*)if \[ "\$_emit_rc" -eq 2 \]; then#\1if false; then#'

# A24: sshd slot bounding, inside the drop-in block.
assert_holds    "A24 sshd-limits" p_sshd_limits "$CLOUD_INIT"
# Mutation: revert ClientAliveInterval to the 300 that lets a wedged connection hold a
# slot ~10 minutes.
assert_mutation "A24 sshd-limits" p_sshd_limits "$CLOUD_INIT" \
  's;^([[:space:]]*)ClientAliveInterval 60$;\1ClientAliveInterval 300;'

# A22b: the rc BINDING (not just the guard line).
assert_holds    "A22b trap-rc-binding" p_trap_rc_guard "$CLOUD_INIT"
# Mutation: bind rc=0 — every count-based assertion still passes, but no handler can ever
# emit a fatal. This is the mutation that survived the first battery.
assert_mutation "A22b trap-rc-binding" p_trap_rc_guard "$CLOUD_INIT" \
  's;^([[:space:]]*)rc=\$\?$;\1rc=0;'

# A25: `set -e` precedes the checksum block (issue item 3).
assert_holds    "A25 set-e-before-checksum" p_set_e_before_checksum "$CLOUD_INIT"
# Mutation: disarm it — `tar xzf` + `chmod +x` would again run on an unverified tarball.
assert_mutation "A25 set-e-before-checksum" p_set_e_before_checksum "$CLOUD_INIT" \
  's;^([[:space:]]*)set -e$;\1set +e;'
# Mutation: TOLERATE the checksum. Ordering alone is not the property — `set -e` before a
# `|| true`-suffixed command aborts nothing, and this mutation survived the first battery.
# RE-ANCHORED (#7227): the checksum line now carries `2>>"$GIT_DATA_RUNCMD_DETAIL"`, so the
# old `$`-anchored form matched nothing and reported MUTATION DID NOT LAND — an arm that
# certifies nothing, which is exactly what assert_mutation's landing guard exists to surface.
assert_mutation "A25 checksum-not-tolerated" p_set_e_before_checksum "$CLOUD_INIT" \
  's;(sha256sum -c -.*)$;\1 || true;'

# A26: no bare terraform directive (AC4).
assert_holds    "A26 no-bare-directive" p_no_bare_directive "$CLOUD_INIT"
# Mutation: introduce one — the render would fail, and it is invisible to a plain
# substring check because the doubled form is legitimate.
assert_mutation "A26 no-bare-directive" p_no_bare_directive "$CLOUD_INIT" \
  's;^packages:$;packages: %{ if true }x%{ endif };'

# A27: plain-text delivery MECHANISM (not byte-identity — that is B1 in the rehearsal).
assert_holds    "A27 plain-script-delivery" p_plain_script_delivery "$CLOUD_INIT"
# Mutation: revert one script to a b64 blob — the budget regression, caught structurally.
assert_mutation "A27 plain-script-delivery" p_plain_script_delivery "$CLOUD_INIT" \
  's;^([[:space:]]*)content: \|$;\1encoding: b64;'

# --- A28: the passphrase must stay unreachable from the SHARED log -------------------
#
# `_devalue` (git-data-emit) is the passphrase's ONLY defence: it is 40 chars of
# alphanumeric and matches no pattern rule in the redactor chain. It is armed only when
# GIT_DATA_LUKS_KEY is in the emitter's environment — which is true for `luks_err` and the
# bootstrap trap (both children of `doppler run`) and FALSE for the parent `on_err` and
# `bootstrap_err`, which run outside that boundary. All four traps ship the SAME
# /var/log/cloud-init-output.log as their detail.
#
# So the invariant that keeps this safe is not the redactor — it is that the passphrase
# never reaches that log in the first place. Audited: every use is either `[ -n "$VAR" ]`
# (a test, no output) or `printf '%s' "$VAR" | cryptsetup … --key-file -` (stdin, never
# argv, never echoed), and nothing in the boot path enables shell tracing. That makes the
# unarmed-trap path unreachable TODAY, and this pair of guards is what keeps it that way:
# a future `set -x`, or a key moved onto a command line, would put it in the log where two
# of the four traps cannot scrub it.
#
# Fixing the asymmetry directly would mean giving the parent traps the passphrase — moving
# key material to widen who holds it, to defend a path that is closed. Guarding the closure
# is the cheaper and safer half, and it costs zero user_data bytes.
p_no_shell_tracing() {
  # No `set -x`/`sh -x`/`bash -x` anywhere in the boot path.
  # `-[a-z]*x[a-z]*` on BOTH sides of the x: the realistic drift is `set -exuo pipefail`,
  # where x sits mid-flag. An anchor requiring whitespace immediately after the x misses
  # exactly that form — measured: the mutation below did not flip the predicate.
  if grep -Eq '(^|[[:space:]])(set|(ba)?sh)[[:space:]]+-[a-z]*x[a-z]*([[:space:]]|$)' "$1"; then
    echo 0; else echo 1; fi
}
# THE QUANTIFIER IS THE WHOLE BOOT PATH, NOT JUST THE TEMPLATE.
#
# A28a/A28b originally scanned $CLOUD_INIT alone. But the template is not the only place the
# passphrase appears: git-data-bootstrap.sh is the SECOND GIT_DATA_LUKS_KEY site (it re-asserts
# the LUKS mount idempotently), and it is a `file()`-injected script, so it was outside the
# quantifier while the property was stated over the boot path. Measured: changing its
# `set -euo pipefail` to `set -exuo pipefail` left this suite 62/62 GREEN, with every
# expansion — including the key — traced into /var/log/cloud-init-output.log, which two of the
# four traps ship verbatim with `_devalue` unarmed. That is precisely the failure this pair of
# guards exists to prevent.
#
# The file list is DERIVED from the render module's file() bindings rather than hardcoded, so
# a new injected script is covered the day it is added rather than the day someone remembers.
#
# (#7025, R7) The bindings moved from git-data.tf to modules/git-data-userdata/main.tf, and
# `${path.module}` there resolves TWO LEVELS DOWN — so each extracted path is `../../<name>`
# and must be resolved against the MODULE directory, not $DIR. Resolving against the old base
# yields apps/web-platform/<name>, which does not exist, so every payload would silently drop
# out of the quantifier and leave A28a/A28b asserting the property over the template alone —
# the exact gap the floor below exists to catch, which is why the floor is not optional.
GIT_DATA_USERDATA_MODULE="$DIR/modules/git-data-userdata"
boot_path_files() {
  printf '%s\n' "$CLOUD_INIT"
  # git-data-cutover.sh is NOT file()-bound into user_data (it ships via the deploy pipeline),
  # so the derivation below cannot see it — yet it references GIT_DATA_LUKS_KEY six times and
  # runs on the same host against the same shared log. The property A28 asserts is about the
  # PASSPHRASE, not about user_data membership, so the quantifier has to include it explicitly.
  [ -f "$CUTOVER" ] && printf '%s\n' "$CUTOVER"
  sed -nE 's/^[[:space:]]*[a-z_]+[[:space:]]*=[[:space:]]*(replace\()?file\("\$\{path\.module\}\/([^"]+)".*/\2/p' \
    "$GIT_DATA_USERDATA_MODULE/main.tf" | sort -u | while read -r f; do
      [ -n "$f" ] && [ -f "$GIT_DATA_USERDATA_MODULE/$f" ] && printf '%s\n' "$GIT_DATA_USERDATA_MODULE/$f"
    done
}

# A floor, because a derivation that silently returned only the template would re-create the
# exact gap this fix closes while every arm below still reported green.
_bp_count=$(boot_path_files | wc -l)
if [ "$_bp_count" -ge 11 ]; then pass; else
  fail "A28 boot-path derivation: only $_bp_count file(s) found (expected the template + 9 injected + the cutover script)"
fi

for _bp in $(boot_path_files); do
  assert_holds "A28a no-shell-tracing ($(basename "$_bp"))" p_no_shell_tracing "$_bp"
done
# Mutation: arm tracing on the LUKS heredoc — every expansion, including the key, lands in
# the shared log that the two unarmed traps ship verbatim.
assert_mutation "A28a no-shell-tracing" p_no_shell_tracing "$CLOUD_INIT" \
  's/^([[:space:]]*)set -euo pipefail$/\1set -exuo pipefail/'
# And the same mutation on the script that was outside the quantifier until this change. Its
# `set -euo pipefail` is at column 0, which is why the template mutation above (indented,
# inside a heredoc) never reached it.
assert_mutation "A28a no-shell-tracing (bootstrap)" p_no_shell_tracing \
  "$DIR/git-data-bootstrap.sh" 's/^set -euo pipefail$/set -exuo pipefail/'

p_key_never_on_argv() {
  # Every GIT_DATA_LUKS_KEY EXPANSION in an executable line must be one of the two audited
  # shapes. The emitter's own `_devalue` body is matched by the `[ -n` / `printf '%s'` forms.
  #
  # IT MATCHES THE EXPANSION, NOT THE BARE TOKEN. A line that merely NAMES the variable
  # cannot leak its value — `log "FATAL: GIT_DATA_LUKS_KEY empty"` prints the eleven-character
  # name, not the passphrase. Anchoring on the bare token made this predicate report that
  # exact line in git-data-bootstrap.sh as a violation the moment the scan was widened past
  # the template (cq-assert-anchor-not-bare-token). Comment lines are still dropped first, so
  # a commented-out expansion does not count either.
  local bad
  bad=$(grep -nE '\$+\{?GIT_DATA_LUKS_KEY' "$1" \
        | grep -vE '^[0-9]+:[[:space:]]*#' \
        | grep -vE '\[[[:space:]]+-n[[:space:]]+"\$+\{?GIT_DATA_LUKS_KEY' \
        | grep -vE "printf '%s' \"\\\$+\{?GIT_DATA_LUKS_KEY" \
        | grep -cE '.' || true)
  if [ "$bad" -eq 0 ]; then echo 1; else echo 0; fi
}
for _bp in $(boot_path_files); do
  assert_holds "A28b key-never-on-argv ($(basename "$_bp"))" p_key_never_on_argv "$_bp"
done
# Mutation: echo the key. This is the shape that actually puts it in the shared log.
assert_mutation "A28b key-never-on-argv" p_key_never_on_argv "$CLOUD_INIT" \
  's;^([[:space:]]*)mkdir -p /mnt/git-data-luks.*$;\1echo "key=$GIT_DATA_LUKS_KEY";'
# Same shape in the second key site, which the template-only scan could not see.
assert_mutation "A28b key-never-on-argv (bootstrap)" p_key_never_on_argv \
  "$DIR/git-data-bootstrap.sh" 's;^LUKS_ROOT="/mnt/git-data-luks"$;echo "key=$GIT_DATA_LUKS_KEY";'

# --- A2: the gc units must NOT source their env file in a shell -----------------------
#
# `/bin/sh` is DASH, where `.` is a POSIX SPECIAL BUILTIN: a failed source kills the shell
# outright. Both gc units used to open with `set -a; . /etc/default/git-data-doppler; set +a`,
# and that env file is mode 0600 written in runcmd AFTER stages that can abort — so on a host
# whose Doppler stage failed, the FAILURE REPORTER died at its own first line, before either
# arm of its `||` fallback. The one component whose job is reporting failures was guaranteed
# silent on its most likely failure.
#
# This had NO regression guard until now. Measured: reverting either unit to the sourcing form
# left this suite 87/87 GREEN, `systemd-analyze verify` green (it does not model dash's
# special-builtin abort), and the ADR-152 parity suite green. Sibling units ARE guarded —
# cron-egress-firewall.test.sh pins its `EnvironmentFile=-`, workspaces-luks-header.test.sh
# pins luks-monitor's — these two were the gap.
p_env_file_not_sourced() {
  # The directive must be present with the leading `-` (tolerate absence), and the shell
  # source of that same file must be gone. Anchored on the directive at line start, so a
  # comment mentioning either shape cannot satisfy or break it.
  if grep -Eq '^EnvironmentFile=-/etc/default/git-data-doppler$' "$1" \
    && ! grep -Eq '^[^#]*(^|[[:space:];])\.[[:space:]]+/etc/default/git-data-doppler' "$1"; then
    echo 1; else echo 0; fi
}
for _u in "${DIR}/git-data-gc.service" "${DIR}/git-data-gc-failure.service"; do
  assert_holds "A2 env-file-not-sourced ($(basename "$_u"))" p_env_file_not_sourced "$_u"
done
# Both directions, per unit: dropping the directive, and reintroducing the dash-fatal source.
assert_mutation "A2 env-file directive present (gc.service)" p_env_file_not_sourced \
  "${DIR}/git-data-gc.service" 's|^EnvironmentFile=-/etc/default/git-data-doppler$|Environment=X=1|'
assert_mutation "A2 env-file directive present (gc-failure.service)" p_env_file_not_sourced \
  "${DIR}/git-data-gc-failure.service" 's|^EnvironmentFile=-/etc/default/git-data-doppler$|Environment=X=1|'
assert_mutation "A2 no shell source (gc.service)" p_env_file_not_sourced \
  "${DIR}/git-data-gc.service" "s|^ExecStart=/bin/sh -c 'exec |ExecStart=/bin/sh -c 'set -a; . /etc/default/git-data-doppler; set +a; exec |"
assert_mutation "A2 no shell source (gc-failure.service)" p_env_file_not_sourced \
  "${DIR}/git-data-gc-failure.service" "s|^ExecStart=/bin/sh -c 'set -- |ExecStart=/bin/sh -c 'set -a; . /etc/default/git-data-doppler; set +a; set -- |"

# --- B16 (RE-AIMED, #7204): the birth mkfs invocation's PRECONDITIONS -----------------
#
# WHAT CHANGED AND WHY. B16 previously pinned `-O quota,project` on the grounds that the
# flags were MIGRATION-FORCING. Two things were wrong with that.
#
# First, the premise — but ONLY for `quota`. `tune2fs(8)` sets and clears both features on an
# unmounted filesystem, so "adding them later needs a replace plus an rsync of every user's
# objects" was false as stated. It is NOT a licence to add `project` later: measured,
# `tune2fs -O project` on a plain filesystem ADDS `quota` implicitly, which is the bit that
# makes this volume unmountable on the target image. For `project`, birth-or-never HOLDS —
# see B16c. A maintainer who reads only the first sentence and reaches for tune2fs re-bricks
# the host.
# Second, and fatally: `quota` made the volume UNMOUNTABLE on the target image. Setting the
# ext4 `quota` RO_COMPAT bit makes ext4_fill_super call ext4_enable_quotas() on every mount
# (v6.8 fs/ext4/super.c gates it on the feature bit alone), which needs the `quota_v2`
# module; Ubuntu builds it =m and ships it only in linux-modules-extra-*, absent from the
# 24.04 cloud image => -ESRCH, mount(8) rc=32, dark boot. B16's FIRST mutation arm was
# literally `s/-O quota,project/-O project/` — the correct fix, encoded as the drift to
# catch. The guard was not wrong to exist; it was aimed at the wrong invariant.
#
# So B16 is RE-AIMED, not deleted — deleting it would leave the invariant unguarded on every
# machine without docker (see the authority split below).
#
# AUTHORITY SPLIT (AP-018), WITH THE CAVEAT THAT MAKES IT HONEST. R1 in
# git-data-runcmd-rehearsal.test.sh is the AUTHORITATIVE gate: it creates the filesystem and
# classifies the resulting superblock against a committed allowlist. B16 is a static
# PRE-FILTER over R1's preconditions and owns no feature semantics beyond the one tripwire
# below. AP-018 presumes the runtime gate always runs — and here it does not: the rung-1
# suite `exit 0`s when docker is absent, so ON A DOCKER-LESS MACHINE B16 IS THE ONLY
# COVERAGE THAT EXISTS. CI is the only environment where both run. Do not delete B16 on the
# reading that "R1 covers it"; R1 is authoritative WHEN IT RUNS.
#
# Slice the STAGE=luks_open heredoc once. Comment lines are stripped BEFORE matching,
# because this file's own #7204 comment block names the pre-fix invocation literally — a
# body-grep that saw comments would match it and report the defect it just fixed
# (cq-assert-anchor-not-bare-token).
# The classified feature allowlist R1 machine-reads. B16b derives its denied set from this
# same file so the static and runtime layers cannot disagree about what "module-dep" means.
FIX_FILE="${DIR}/git-data-birth-fs-fingerprint.txt"
# `_luks_slice` is defined once, up beside p_isluks — A1 and B18 call it before this point.
_mkfs_lines() { _luks_slice "$1" | grep -E '^[[:space:]]*mkfs\.ext4[[:space:]]' || true; }

# B16a — EXACTLY ONE mkfs invocation, inside the luks_open heredoc, not on a comment line.
# This is R1's extraction precondition: R1 asserts `len(...) == 1` on the render, so a second
# invocation (or a rename to `mke2fs -t ext4`) makes R1 fail to extract rather than fail to
# hold, and the real cause gets buried.
p_mkfs_once() {
  n=$(_mkfs_lines "$1" | grep -c . || true)
  if [ "${n:-0}" -eq 1 ]; then echo 1; else echo 0; fi
}
assert_holds    "B16a mkfs-exactly-once" p_mkfs_once "$CLOUD_INIT"
assert_mutation "B16a mkfs-exactly-once (duplicated invocation)" p_mkfs_once "$CLOUD_INIT" \
  's#^([[:space:]]*)mkfs\.ext4 -q -O project /dev/mapper/git-data.*$#&\n\1mkfs.ext4 -q /dev/mapper/git-data#'

# B16b — THE TRIPWIRE. No quota feature on the birth mkfs. This is the one feature-semantics
# assertion B16 keeps, precisely because it is the only coverage on a docker-less machine.
# DERIVED from git-data-birth-fs-fingerprint.txt's `module-dep` rows, not hardcoded. A
# hardcoded `quota` token meant adding a SECOND module-dep feature to the fixture reddened R1
# only — B16b stayed green, and B16 is the layer documented as the sole coverage on a
# docker-less machine. The two layers now share one source of truth (the AP-018 third element
# this split was missing). Fails CLOSED if the fixture is unreadable or yields no rows.
_module_dep_feats() {
  awk -F'\t' '/^[a-z_]+\t/ && $2 == "module-dep" { print $1 }' "$FIX_FILE" 2>/dev/null || true
}
p_mkfs_no_quota() {
  feats="$(_module_dep_feats)"
  [ -n "$feats" ] || { echo 0; return; }   # no fixture / no rows => fail closed
  lines="$(_mkfs_lines "$1")"
  [ -n "$lines" ] || { echo 1; return; }   # B16a owns the disappearance case
  for f in $feats; do
    n=$(printf '%s\n' "$lines" | grep -cE -- "-O[[:space:]]*[a-z,]*${f}" || true)
    [ "${n:-0}" -eq 0 ] || { echo 0; return; }
  done
  echo 1
}
assert_holds    "B16b mkfs-no-quota-feature" p_mkfs_no_quota "$CLOUD_INIT"
assert_mutation "B16b mkfs-no-quota-feature (quota re-introduced)" p_mkfs_no_quota "$CLOUD_INIT" \
  's/-O project /-O quota,project /'

# B16c — `project` is set AT BIRTH. Not decoration: measured 2026-08-03, `tune2fs -O project`
# on a plain filesystem ADDS `quota` implicitly, so adding it later would set the exact bit
# that bricks the mount. On this image project is a birth-time choice or nothing.
p_mkfs_project() {
  n=$(_mkfs_lines "$1" | grep -cE -- '-O[[:space:]]+[a-z,]*project' || true)
  if [ "${n:-0}" -ge 1 ]; then echo 1; else echo 0; fi
}
assert_holds    "B16c mkfs-project-at-birth" p_mkfs_project "$CLOUD_INIT"
assert_mutation "B16c mkfs-project-at-birth (project dropped)" p_mkfs_project "$CLOUD_INIT" \
  's#^([[:space:]]*mkfs\.ext4[^#]*) -O project#\1#'

# --- B17 (#7204, D3): the mount NEVER falls through to an unencrypted device ----------
#
# This is the plan's highest-stakes invariant and it was enforced only by a hand-run grep
# over ONE pull request's diff — which protects that PR and nothing after it. The next author
# is the threat: a `|| true` added to "stop the boot failing" would let the birth proceed and
# put real user source code on a plaintext device while every artifact attests encryption.
# That is strictly worse than the unstarted promise (#6588).
#
# THE PREDICATE ANCHORS ON WHAT FOLLOWS THE MOUNT, not on "no || near mount". The shipped
# line is `mountpoint -q /mnt/git-data-luks || mount /dev/mapper/git-data /mnt/git-data-luks`
# — it legitimately CONTAINS `||` before the mount verb, so a naive test is wrong in both
# directions: it would fail on the correct line and pass on `mount … || true` written across
# a continuation.
p_mount_no_fallthrough() {
  slice="$(_luks_slice "$1")"
  # FOLD LINE CONTINUATIONS FIRST. `after` is computed from a grep-matched physical line, so
  # anything past a trailing `\` was invisible — measured: `mount … \` + `|| true` on the next
  # line left the suite 107/107 green. That is the single most likely way a future author adds
  # a fall-through, and the previous comment claimed this predicate covered it.
  folded="$(printf '%s\n' "$slice" | sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba' -e '}')"
  line="$(printf '%s\n' "$folded" | grep -E 'mount[[:space:]]+/dev/mapper/git-data[[:space:]]+/mnt/git-data-luks' || true)"
  [ -n "$line" ] || { echo 0; return; }   # the mount vanished entirely — not a pass
  after="${line#*mount /dev/mapper/git-data /mnt/git-data-luks}"
  # `||` AND `;`-separated continuations both let the boot proceed past a failed mount.
  case "$after" in
    *'||'*) echo 0; return ;;
    *';'*)  echo 0; return ;;
  esac
  # An `if mount …; then … else … fi` wrapper suppresses errexit without ever writing `||`.
  case "$line" in
    *'if '*'mount /dev/mapper/git-data'*) echo 0; return ;;
  esac
  # `set +e` anywhere in the stage disarms errexit for the mount.
  n_sete=$(printf '%s\n' "$folded" | grep -cE '^[[:space:]]*set \+e([[:space:]]|$)' || true)
  [ "${n_sete:-0}" -eq 0 ] || { echo 0; return; }
  echo 1
}

# SPLIT OUT (was folded into p_mount_no_fallthrough, where the `||` arm tripped first and left
# it with no independent mutation). Covers the OTHER way to end up with an unencrypted
# filesystem at the LUKS mountpoint: mounting a raw device rather than the mapper. `$DEV` is
# bound earlier in the stage to the by-id path, so it is matched explicitly — the literal
# `/dev/disk/by-id` alone missed the most convenient spelling.
p_mount_no_raw_device() {
  slice="$(_luks_slice "$1")"
  n=$(printf '%s\n' "$slice" | grep -cE 'mount[[:space:]]+([^|]*[[:space:]])?(/dev/disk/by-id|/dev/sd[a-z]|"?\$DEV"?)' || true)
  if [ "${n:-0}" -eq 0 ]; then echo 1; else echo 0; fi
}

assert_holds    "B17 mount-no-fallthrough" p_mount_no_fallthrough "$CLOUD_INIT"
assert_mutation "B17 mount-no-fallthrough (|| true)" p_mount_no_fallthrough "$CLOUD_INIT" \
  's#(mount /dev/mapper/git-data /mnt/git-data-luks)(.*)$#\1\2 || true#'
assert_mutation "B17 mount-no-fallthrough (|| : )" p_mount_no_fallthrough "$CLOUD_INIT" \
  's#(mount /dev/mapper/git-data /mnt/git-data-luks)(.*)$#\1\2 || :#'
assert_mutation "B17 mount-no-fallthrough (; true separator)" p_mount_no_fallthrough "$CLOUD_INIT" \
  's#(mount /dev/mapper/git-data /mnt/git-data-luks)(.*)$#\1\2 ; true#'
assert_mutation "B17 mount-no-fallthrough (backslash continuation)" p_mount_no_fallthrough "$CLOUD_INIT" \
  's#(mount /dev/mapper/git-data /mnt/git-data-luks)(.*)$#\1\2 \\\n      || true#'
assert_mutation "B17 mount-no-fallthrough (if-wrapper suppresses errexit)" p_mount_no_fallthrough "$CLOUD_INIT" \
  's#mountpoint -q /mnt/git-data-luks \|\| (mount /dev/mapper/git-data /mnt/git-data-luks)(.*)$#if \1\2; then :; else echo WARN; fi#'
assert_mutation "B17 mount-no-fallthrough (set +e disarms errexit)" p_mount_no_fallthrough "$CLOUD_INIT" \
  's#^([[:space:]]*)(mountpoint -q /mnt/git-data-luks)#\1set +e\n\1\2#'

assert_holds    "B17r mount-no-raw-device" p_mount_no_raw_device "$CLOUD_INIT"
assert_mutation "B17r mount-no-raw-device (by-id fallback)" p_mount_no_raw_device "$CLOUD_INIT" \
  's#(mount /dev/mapper/git-data /mnt/git-data-luks)(.*)$#\1\2 || mount /dev/disk/by-id/scsi-0HC_Volume_x /mnt/git-data-luks#'
assert_mutation "B17r mount-no-raw-device (\$DEV fallback)" p_mount_no_raw_device "$CLOUD_INIT" \
  's#(mount /dev/mapper/git-data /mnt/git-data-luks)(.*)$#\1\2 || mount "$DEV" /mnt/git-data-luks#'

# --- B18 (#7216): the isLuks probe BRANCHES ON ITS EXIT CODE; rc 1 is the ONLY format ------
#
# `if ! cryptsetup isLuks "$DEV"` reads EVERY non-zero exit as "not yet LUKS" and answers with
# luksFormat. Measured against the pinned image (cryptsetup 2.7.0): no-header = 1, ABSENT
# device = 4, not-on-PATH = 127. So a probe that could not RUN was indistinguishable from one
# that ran and said no, and the destructive branch got taken because the measurement was
# MISSING rather than because the answer was negative. `runcmd` is once-per-instance, so the
# reachable trigger is a host REPLACEMENT (this template carries no `ignore_changes
# = [user_data]`) against a volume that persists and re-attaches already-LUKS — which
# luksFormat answers by overwriting the header and every key slot. Unrecoverable: the old
# passphrase opens nothing.
#
# SIX predicates, because the shipped fix has six separable ways to regress:
#   (a) the `if !` truthiness form does not come back
#   (b) rc is captured with `|| _isluks_rc=$?`, NEVER the naked `; _isluks_rc=$?` the issue
#       proposed — this stage is under `set -euo pipefail`, where the naked form aborts
#       BEFORE the assignment on rc=1, so a blank volume at birth could never be formatted
#       at all. (The sshd_config stage's naked capture is legal only because it sits ABOVE
#       that stage's `set -e`, ~30 lines up. Mirror the discipline, not the two lines.)
#   (c) the branch is a `case` on the captured rc
#   (d) EXACTLY ONE arm reaches luksFormat, anchored on `cryptsetup[[:space:]]+luksFormat`
#       rather than the bare token so no arm's prose can satisfy it
#   (e) the catch-all `*)` reaches `exit 1` — refusing to format beats guessing
#   (f) THE PROBE LINE CARRIES NO `2>>`. This is the one that matters. A failed redirection
#       on a simple command means the command NEVER RUNS and the shell reports rc 1:
#         $ ( set -euo pipefail; _rc=0; /bin/true 2>>/proc/sys/nonexistent/x || _rc=$?; \
#             echo "rc=$_rc" )
#         rc=1
#       On an unwritable or full /run — a state this very stage's fallbacks enumerate — a
#       `2>>` on the probe FORGES the single rc that means "format it" while the probe never
#       executed, reconstructing #7216 inside the patch that closes it. Stderr is therefore
#       captured through a command SUBSTITUTION, with the append a separately tolerated
#       statement that cannot influence the measured rc.
p_isluks_rc_branch() {
  local slice probe n
  slice="$(_luks_slice "$1")"
  # (a)
  if printf '%s\n' "$slice" | grep -Eq 'if[[:space:]]+![[:space:]]*cryptsetup[[:space:]]+isLuks'; then echo 0; return; fi
  # (b)
  if ! printf '%s\n' "$slice" | grep -Eq '\|\|[[:space:]]*_isluks_rc=\$\?'; then echo 0; return; fi
  # (c)
  if ! printf '%s\n' "$slice" | grep -Eq 'case[[:space:]]+"\$_isluks_rc"[[:space:]]+in'; then echo 0; return; fi
  # (d)
  n=$(printf '%s\n' "$slice" | grep -cE 'cryptsetup[[:space:]]+luksFormat' || true)
  if [ "${n:-0}" -ne 1 ]; then echo 0; return; fi
  # (e)
  if ! printf '%s\n' "$slice" | grep -Eq '^[[:space:]]*\*\).*exit[[:space:]]+1'; then echo 0; return; fi
  # (f)
  probe="$(printf '%s\n' "$slice" | grep -E 'cryptsetup[[:space:]]+isLuks' || true)"
  if [ -z "$probe" ]; then echo 0; return; fi
  if printf '%s\n' "$probe" | grep -q '2>>'; then echo 0; return; fi
  echo 1
}
assert_holds    "B18 isLuks-rc-branch" p_isluks_rc_branch "$CLOUD_INIT"
# One arm per predicate, each anchored so the mutation actually LANDS (assert_mutation fails
# loud on a byte-identical mutant, which is how a re-anchored predicate stops certifying).
# (a) the truthiness form comes back. NOT a single-token s/// — the `if !` shape has to
# replace the rc capture, so anchor on the whole `_isluks_rc=0` line.
assert_mutation "B18 isLuks-rc-branch (revert to \`if !\`)" p_isluks_rc_branch "$CLOUD_INIT" \
  's/^([[:space:]]*)_isluks_rc=0$/\1if ! cryptsetup isLuks "$DEV"; then :; fi/'
# (b) the naked capture the issue proposed — aborts under `set -euo pipefail` on rc=1.
# `#` delimiter, not `|`: the pattern contains `||`.
assert_mutation "B18 isLuks-rc-branch (naked rc capture)" p_isluks_rc_branch "$CLOUD_INIT" \
  's#\|\| _isluks_rc=\$\?#; _isluks_rc=$?#'
# (d) a SECOND arm reaches luksFormat — i.e. an already-LUKS device (rc 0) gets reformatted.
assert_mutation "B18 isLuks-rc-branch (rc 0 also formats)" p_isluks_rc_branch "$CLOUD_INIT" \
  's#^([[:space:]]*)0\) : ;;#\1 0) printf "%s" "$GIT_DATA_LUKS_KEY" | cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV" ;;#'
# (e) the catch-all stops refusing. Anchored on `\*\)` so it cannot also hit the empty-key
# guard, which is a `||`-chained brace group with no case arm.
assert_mutation "B18 isLuks-rc-branch (catch-all no longer exits)" p_isluks_rc_branch "$CLOUD_INIT" \
  's#^([[:space:]]*)\*\).*$#\1*) : ;;#'
# (f) THE ONE THAT MATTERS — `2>>` back on the probe line. A failed redirect returns 1
# WITHOUT running the command, so on an unwritable /run this forges the single rc that means
# "format it". This arm is why the capture is a substitution and not a redirect.
assert_mutation "B18 isLuks-rc-branch (2>> forges rc=1 on the probe)" p_isluks_rc_branch "$CLOUD_INIT" \
  's#cryptsetup isLuks "\$DEV" 2>&1#cryptsetup isLuks "$DEV" 2>>"$GIT_DATA_LUKS_DETAIL"#'

# --- B19 (#7227): Decision clause B, mechanized -------------------------------------------
#
# The parent-shell detail file is safe to ship unredacted because of a TWO-CLAUSE invariant,
# and only clause A is structural. Clause A: parent commands provably do not hold
# GIT_DATA_LUKS_KEY, so they cannot leak it. Clause B covers the two `doppler run` children,
# which DO hold it, and is BEHAVIOURAL — it rests on three facts that a future edit could
# silently revoke. Behavioural bounds that nothing checks are how a redactor bypass ships, so
# each fact gets an assertion:
#
#   1. the passphrase is `special = false` (alphanumeric), so it carries no regex
#      metacharacter and cannot malform the `sed` _devalue constructs from it;
#   2. there is no `set -x` in the template or the bootstrap payload, so no command echo
#      can put the key on a stream;
#   3. every key-consuming cryptsetup call takes it on stdin via `--key-file -`, never argv.
#
# (3) overlaps A2 deliberately: A2 asserts it for the TEMPLATE's luksFormat/luksOpen, while
# clause B's bound has to hold for the bootstrap payload's luksOpen too, which A2 never reads.
BOOTSTRAP_SH="${DIR}/git-data-bootstrap.sh"
[ -f "$BOOTSTRAP_SH" ] || { echo "FAIL: git-data-bootstrap.sh not found at $BOOTSTRAP_SH" >&2; exit 1; }

p_luks_key_alnum() {
  # Region-scoped to the resource block: a `special = false` on ANY other random_password
  # would otherwise satisfy a file-global grep.
  awk '/^resource "random_password" "git_data_luks"/{f=1} f&&/^}/{f=0; print; next} f' "$1" \
    | grep -Eq '^[[:space:]]*special[[:space:]]*=[[:space:]]*false[[:space:]]*$' && echo 1 || echo 0
}
assert_holds    "B19a luks-key-alphanumeric" p_luks_key_alnum "$LUKS_TF"
assert_mutation "B19a luks-key-alphanumeric (special re-enabled)" p_luks_key_alnum "$LUKS_TF" \
  's/^([[:space:]]*)special([[:space:]]*)=([[:space:]]*)false$/\1special\2=\3true/'

p_no_set_x() {
  # Comment-stripped: the word appears in prose in both files.
  if sed 's/#.*//' "$1" | grep -Eq '(^|[[:space:];])set[[:space:]]+(-[a-z]*x|-o[[:space:]]+xtrace)'; then echo 0; else echo 1; fi
}
assert_holds    "B19b no-set-x (template)" p_no_set_x "$CLOUD_INIT"
assert_mutation "B19b no-set-x (template)" p_no_set_x "$CLOUD_INIT" \
  's/^([[:space:]]*)set -euo pipefail$/\1set -euxo pipefail/'
assert_holds    "B19c no-set-x (bootstrap payload)" p_no_set_x "$BOOTSTRAP_SH"
assert_mutation "B19c no-set-x (bootstrap payload)" p_no_set_x "$BOOTSTRAP_SH" \
  's/^([[:space:]]*)set -euo pipefail$/\1set -euxo pipefail/'

p_bootstrap_keyfile_stdin() {
  local n_key n_stdin
  n_key=$(grep -cE 'cryptsetup[[:space:]]+luks(Format|Open)' "$1" || true)
  [ "${n_key:-0}" -ge 1 ] || { echo 0; return; }
  n_stdin=$(grep -E 'cryptsetup[[:space:]]+luks(Format|Open)' "$1" | grep -c -- '--key-file -' || true)
  # And the key must not appear as a cryptsetup argv positional.
  if [ "$n_stdin" -ne "$n_key" ]; then echo 0; return; fi
  if grep -E 'cryptsetup[[:space:]]+luks(Format|Open)' "$1" | sed -E 's/.*(cryptsetup[[:space:]]+luks)/\1/' | grep -q 'GIT_DATA_LUKS_KEY'; then echo 0; return; fi
  echo 1
}
assert_holds    "B19d bootstrap-key-file-stdin" p_bootstrap_keyfile_stdin "$BOOTSTRAP_SH"
assert_mutation "B19d bootstrap-key-file-stdin (key moved to argv)" p_bootstrap_keyfile_stdin "$BOOTSTRAP_SH" \
  's#cryptsetup luksOpen --key-file - "\$luks_dev"#cryptsetup luksOpen "$GIT_DATA_LUKS_KEY" "$luks_dev"#'

# --- B20 (#7227): the bootstrap payload's log() writes to fd 2 -----------------------------
#
# The parent runcmd routes this script's STDERR into the per-stage scoped detail file. On
# stdout, all 19 of its `log "FATAL: …"` sentences were invisible to on_err, so the bootstrap
# stage's fatal shipped a detail that knew nothing about the invariant that actually failed —
# the stage is the host's other major failure surface and it was the one with no cause.
#
# REGION-SCOPED to the log() body: a `>&2` anywhere else in this file (there are several)
# would satisfy a file-global grep while log() itself went back to stdout.
p_bootstrap_log_stderr() {
  awk '/^log\(\)[[:space:]]*\{/{f=1} f&&/^\}/{f=0} f' "$1" \
    | grep -vE '^[[:space:]]*#' \
    | grep -Eq '^[[:space:]]*echo "\[git-data-bootstrap\] \$\*"[[:space:]]+>&2[[:space:]]*$' && echo 1 || echo 0
}
assert_holds    "B20 bootstrap-log-to-stderr" p_bootstrap_log_stderr "$BOOTSTRAP_SH"
assert_mutation "B20 bootstrap-log-to-stderr (back to stdout)" p_bootstrap_log_stderr "$BOOTSTRAP_SH" \
  's#^([[:space:]]*echo "\[git-data-bootstrap\] \$\*") >&2$#\1#'

# --- Minimum-cardinality guard (a silent-empty harness must fail loud) ---
#
# RAISED 113 -> 129 WITH THE ARMS THAT MADE IT NECESSARY (#7216 + #7227). Itemised, because a
# floor that does not move with the suite only ever guards the work that predates it:
#   B18 isLuks-rc-branch        1 hold + 5 mutations = 6
#     (revert-to-`if !`, naked rc capture, rc 0 also formats, catch-all no longer exits,
#      and `2>>` back on the probe — the forged-rc-1 arm, which is the reason the capture
#      is a command substitution rather than a redirect)
#   B19a luks-key-alphanumeric  1 hold + 1 mutation  = 2
#   B19b no-set-x (template)    1 hold + 1 mutation  = 2
#   B19c no-set-x (bootstrap)   1 hold + 1 mutation  = 2
#   B19d bootstrap-key-file     1 hold + 1 mutation  = 2
#   B20  bootstrap-log-to-fd-2  1 hold + 1 mutation  = 2
#   113 + 6 + 2 + 2 + 2 + 2 + 2 = 129. Measured: 129 passed, 0 failed.
# A22's own non-vacuity floor moved 3 -> 2 in the same change (bootstrap_err deleted); that
# is inside the predicate, not here, and changes no assertion count.
#
# RAISED 107 -> 113 at review (#7204): B17 widened from 3 mutation arms to 6 (`; true`,
# backslash-continuation and `if`-wrapper each shipped a fall-through past a 107/107 green
# suite), and the raw-device property split out as B17r with its own hold + 2 arms — folded
# into B17 it was unreachable, because the `||` arm always tripped first.
#
# RAISED 101 -> 107 WITH THE ARMS THAT MADE IT NECESSARY (#7204): B16 re-aimed from one
# flag-pin (1 hold + 3 mutations = 4) to three precondition predicates (B16a exactly-once,
# B16b no-quota-feature, B16c project-at-birth = 3 holds + 3 mutations = 6), plus B17
# mount-no-fallthrough (1 hold + 3 mutations = 4). Net 101 - 4 + 6 + 4 = 107.
#
# RAISED 95 -> 101 WITH THE ARMS THAT MADE IT NECESSARY (#7025 R7). A floor whose slack
# equals the size of the change it was added for detects nothing about that change: at 95,
# deleting every assertion the R7 commit added to this suite left it at 97 and EXIT 0 —
# measured. The floor must move with the suite or it only ever guards the work that
# predates it.
#
# It stays at 101 across the R7 follow-through because that change re-pointed arms rather
# than dropping them: the two caller-side derivation arms and the two parity arms went away
# with the caller-side ternary they read, and A16b's three arms plus A19's direct-compare
# mutation replaced them one for one. Deleting the follow-through's coverage outright still
# lands under the floor.
#
# A floor (`-lt`), never an equality: the count is developer-incremented, so `-eq` would
# redden the suite on every legitimate new arm and teach the next author to edit the guard
# instead of trusting it.
total=$((passes + fails))
if [ "$total" -lt 129 ]; then
  echo "FAIL: ran only ${total} assertions (<129) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-luks: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
