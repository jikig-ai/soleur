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
# #6570 dual-arch derivation (A14-A17). git-data.tf carries the derivation + the
# per-arch checksum pair; inngest-host.tf / zot-registry.tf are the CANON the pair
# is derived from (never a second hardcoded literal); variables.tf holds the default.
GIT_DATA_TF="${DIR}/git-data.tf"
INNGEST_HOST_TF="${DIR}/inngest-host.tf"
ZOT_TF="${DIR}/zot-registry.tf"
VARIABLES_TF="${DIR}/variables.tf"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$CLOUD_INIT" ]   || { echo "FAIL: cloud-init-git-data.yml not found at $CLOUD_INIT" >&2; exit 1; }
[ -f "$LUKS_TF" ]      || { echo "FAIL: git-data-luks.tf not found at $LUKS_TF" >&2; exit 1; }
[ -f "$CUTOVER" ]      || { echo "FAIL: git-data-cutover.sh not found at $CUTOVER" >&2; exit 1; }
[ -f "$PRERECEIVE" ]   || { echo "FAIL: git-data-pre-receive.sh not found at $PRERECEIVE" >&2; exit 1; }
for f in "$GIT_DATA_TF" "$INNGEST_HOST_TF" "$ZOT_TF" "$VARIABLES_TF"; do
  [ -f "$f" ] || { echo "FAIL: required file not found: $f" >&2; exit 1; }
done

# --- Predicates (each takes a file, echoes "1" if the property holds, else "0") ---

# isLuks idempotency guard present.
p_isluks() {
  if grep -Eq 'cryptsetup[[:space:]]+isLuks' "$1"; then echo 1; else echo 0; fi
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
  cond="$(printf '%s\n' "$src" | grep -A 3 -E '^[[:space:]]*condition[[:space:]]*=' | head -4)"
  printf '%s' "$cond" | grep -qF 'data.hcloud_server_type.git_data.architecture' || { echo 0; return; }
  # The enums MUST be mapped, never compared: hcloud emits x86/arm, the local is
  # amd64/arm64, so a direct compare is false on every plan forever and wedges the root.
  printf '%s' "$cond" | grep -qF '"arm"' || { echo 0; return; }
  printf '%s' "$cond" | grep -qF '"x86"' || { echo 0; return; }
  printf '%s' "$cond" | grep -qE 'architecture[[:space:]]*==[[:space:]]*local\.git_data_arch' && { echo 0; return; }
  echo 1
}

# A16: the arch derivation is ORIENTED correctly. This is the only assertion that catches
# an INVERTED ternary — `startswith(..., "cax") ? "amd64" : "arm64"` ships cpx22 -> arm64,
# fails `sha256sum -c -` at boot, and produces exactly the failure this change prevents.
# A bare "the local is declared" grep cannot see it. Extract the prefix + both branch
# values, then replay the decision over the real type space.
p_arch_derivation() {
  local expr pfx tval fval pair t exp got
  # Anchored on the ASSIGNMENT at line-start. A bare `git_data_arch[[:space:]]*=` also
  # matches the precondition's `local.git_data_arch == "arm64" ? "arm" : "x86"`, so the
  # extraction was order-coupled — correct today only because `locals` precedes the
  # resource in the file.
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
  for pair in "cax11:arm64" "cax21:arm64" "cax31:arm64" "cax41:arm64" \
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
  d="$(awk '/^variable "git_data_server_type"/{i=1} i&&/^[[:space:]]*default[[:space:]]*=/{gsub(/[",]/,"");print $NF;exit} i&&/^}/{exit}' "$1")"
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
p_doppler_config_scope() {
  local n_run n_scoped
  # Anchor on the COMMAND at line start. A bare 'doppler run' also matches the prose
  # comment above the bootstrap invocation, which made this 3-vs-2 and the guard
  # permanently red (cq-assert-anchor-not-bare-token).
  n_run=$(grep -Ec '^[[:space:]]*doppler run ' "$1" || true)
  n_scoped=$(grep -Ec '^[[:space:]]*doppler run --project soleur --config prd_git_data ' "$1" || true)
  # Guard the SIBLINGS too. Scoping this to cloud-init alone let the identical W0 defect
  # survive in git-data-cutover.sh — a file that runs ON this host under the same
  # single-config token — because the guard structurally could not see it.
  for _sib in "${DIR}/git-data-cutover.sh" "${DIR}/git-data-gc-failure.service"; do
    [ -f "$_sib" ] || continue
    n_run=$(( n_run + $(grep -Ec 'doppler run --project soleur ' "$_sib" || true) ))
    n_scoped=$(( n_scoped + $(grep -Ec 'doppler run --project soleur --config prd_git_data ' "$_sib" || true) ))
  done
  if [ "$n_run" -ge 2 ] && [ "$n_run" -eq "$n_scoped" ]; then echo 1; else echo 0; fi
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
  if [ "$n_trap" -ge 3 ] && [ "$n_guard" -eq "$n_trap" ] \
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
  sed -E "$sed_expr" "$file" > "$tmp"
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION did not flip the check to failing (predicate still passed on a broken copy)"; fi
  rm -f "$tmp"
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
assert_holds    "A15 doppler-checksum-parity" p_doppler_checksum_parity "$GIT_DATA_TF"
# Mutation: collapse the arm64 arm onto the amd64 checksum (models a pairing swap /
# copy-paste of one literal over both arms) -> the pair no longer equals canon.
assert_mutation "A15 doppler-checksum-parity" p_doppler_checksum_parity "$GIT_DATA_TF" \
  's/f1954f3717fe4c5b65e906a3c6dfe0d20e97b032af35e43db41250931302e143/9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db/'

# A16: derivation orientation (the inverted-ternary catcher).
assert_holds    "A16 arch-derivation" p_arch_derivation "$GIT_DATA_TF"
# Mutation: invert the ternary. This ships cpx22 -> arm64 and is the precise defect the
# assertion exists for; every "the local is declared" grep stays green against it.
assert_mutation "A16 arch-derivation" p_arch_derivation "$GIT_DATA_TF" \
  's/\? "arm64" : "amd64"/? "amd64" : "arm64"/'

# A17: the git_data_server_type default is not an (unorderable) cax* type.
assert_holds    "A17 default-not-cax" p_default_not_cax "$VARIABLES_TF"
# Mutation: regress the default to cax11 (#6570 itself).
assert_mutation "A17 default-not-cax" p_default_not_cax "$VARIABLES_TF" \
  's/default([[:space:]]*)=[[:space:]]*"cpx22"/default\1= "cax11"/'

# A18: the templatefile map wires BOTH derived locals through to the cloud-init.
assert_holds    "A18 templatefile-wiring" p_templatefile_wiring "$GIT_DATA_TF"
# Mutation: the #6570 regression, relocated from the cloud-init to the var map.
assert_mutation "A18 templatefile-wiring" p_templatefile_wiring "$GIT_DATA_TF" \
  's;^([[:space:]]*)doppler_arch([[:space:]]*)=[[:space:]]*local\.git_data_arch[[:space:]]*$;\1doppler_arch\2= "arm64";'

# A19: the tripwire's referencing edge survives, and the enums stay MAPPED not compared.
assert_holds    "A19 tripwire-edge" p_tripwire_edge "$GIT_DATA_TF"
# Mutation: drop the precondition — the data source is then pruned under -target= and the
# phantom-type guard fires on zero production paths, silently.
assert_mutation "A19 tripwire-edge" p_tripwire_edge "$GIT_DATA_TF" \
  's;^([[:space:]]*)precondition([[:space:]]*)\{;\1notaprecondition\2{;'

# --- #6982 assertions ---------------------------------------------------------------

# A20: the W0 config-scope regression guard.
assert_holds    "A20 doppler-config-scope" p_doppler_config_scope "$CLOUD_INIT"
# Mutation: revert to the pre-#6982 `--config prd`, the exact form measured to boot dark.
assert_mutation "A20 doppler-config-scope" p_doppler_config_scope "$CLOUD_INIT" \
  's/--config prd_git_data/--config prd/g'

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
assert_mutation "A25 checksum-not-tolerated" p_set_e_before_checksum "$CLOUD_INIT" \
  's;(sha256sum -c -)$;\1 || true;'

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
assert_holds    "A28a no-shell-tracing" p_no_shell_tracing "$CLOUD_INIT"
# Mutation: arm tracing on the LUKS heredoc — every expansion, including the key, lands in
# the shared log that the two unarmed traps ship verbatim.
assert_mutation "A28a no-shell-tracing" p_no_shell_tracing "$CLOUD_INIT" \
  's/^([[:space:]]*)set -euo pipefail$/\1set -exuo pipefail/'

p_key_never_on_argv() {
  # Every GIT_DATA_LUKS_KEY expansion in an EXECUTABLE line must be one of the two audited
  # shapes. Comment lines are excluded (they name the variable in prose by design); the
  # emitter's own `_devalue` body is matched by the `[ -n` / `printf '%s'` forms already.
  local bad
  bad=$(grep -nE 'GIT_DATA_LUKS_KEY' "$1" \
        | grep -vE '^[0-9]+:[[:space:]]*#' \
        | grep -vE '\[[[:space:]]+-n[[:space:]]+"\$+\{?GIT_DATA_LUKS_KEY' \
        | grep -vE "printf '%s' \"\\\$+\{?GIT_DATA_LUKS_KEY" \
        | grep -cE '.' || true)
  if [ "$bad" -eq 0 ]; then echo 1; else echo 0; fi
}
assert_holds    "A28b key-never-on-argv" p_key_never_on_argv "$CLOUD_INIT"
# Mutation: echo the key. This is the shape that actually puts it in the shared log.
assert_mutation "A28b key-never-on-argv" p_key_never_on_argv "$CLOUD_INIT" \
  's;^([[:space:]]*)mkdir -p /mnt/git-data-luks$;\1echo "key=$GIT_DATA_LUKS_KEY";'

# --- Minimum-cardinality guard (a silent-empty harness must fail loud) ---
total=$((passes + fails))
if [ "$total" -lt 62 ]; then
  echo "FAIL: ran only ${total} assertions (<62) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-luks: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
