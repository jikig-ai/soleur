#!/usr/bin/env bash
# Guard 4 (#8408 (b)): zot cannot start off the LUKS filesystem, and recovers when it returns.
#
# PROPERTY. Every zot container start requires the bind source /var/lib/zot/.soleur-luks-sentinel,
# which exists only inside the opened LUKS filesystem. When the filesystem returns, zot is started
# within one NIC-guard tick.
#
# ASSEMBLY.
#   - every `docker run … --name zot` site (exactly one: set identity)
#   - the sentinel write: inside the findmnt conjunction, after the mount gate, before the run
#   - the NIC-guard recovery arm (behaviour: private-nic-guard.test.sh T12*)
#   - the luks-open arm vocabulary: writer (registry-luks-open.sh) == reader (the heartbeat)
#   - docker's start-time bind resolution, MEASURED by the docker-gated section below, because
#     the "a missing --mount source fails a RESTART" half is not documented anywhere.
#
# The docker-gated section FAILS CLOSED without a daemon (exit 3, `NO-DOCKER`), the same way
# zot-config-deadlines.test.sh does: a guard whose load-bearing half silently skipped would read
# as green. CI's deploy-script-tests job has a daemon. The probe image is built OFFLINE from the
# runner's own /bin/true and its shared libraries (`docker import`), so there is no network pull.

export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_YML="$SCRIPT_DIR/cloud-init-registry.yml"
SENT=/var/lib/zot/.soleur-luks-sentinel

TMP="$(mktemp -d "${TMPDIR}/luks-gate.XXXXXXXX")" || { printf 'FATAL: mktemp failed\n' >&2; exit 2; }
PROBE_TAG="soleur-luks-gate-probe:$$"
CNAMES=()
cleanup() {
  local c
  for c in "${CNAMES[@]:-}"; do [ -n "$c" ] && docker rm -f "$c" >/dev/null 2>&1; done
  docker image rm -f "$PROBE_TAG" >/dev/null 2>&1
  rm -rf "$TMP"
  return 0
}
trap cleanup EXIT

passes=0
fails=0
cases=0
check() { # <name> <condition>
  cases=$((cases + 1))
  if eval "$2" >/dev/null 2>&1; then passes=$((passes + 1)); printf 'ok   - %s\n' "$1"
  else fails=$((fails + 1)); printf 'FAIL - %s\n' "$1" >&2; fi
}

# Instrument self-test: check() must move each counter once. printf + exit, never through check().
check "self-test pass arm" "true"; check "self-test fail arm (this FAIL line is EXPECTED)" "false"
if [ "$passes" -ne 1 ] || [ "$fails" -ne 1 ] || [ "$cases" -ne 2 ]; then
  printf 'FATAL: instrument self-test: check() did not record one pass and one fail.\n' >&2
  exit 2
fi
passes=0; fails=0; cases=0

# --- Static: join backslash-continued lines, so a docker run is one logical line --------------
JOINED="$TMP/joined.txt"
awk '{ if (sub(/\\[[:blank:]]*$/, "")) { buf = buf $0; next } print NR ": " buf $0; buf = "" }' "$CI_YML" > "$JOINED"
ZOT_RUNS="$(grep -E 'docker run [^#]*--name zot( |$)' "$JOINED" || true)"
# Repo-wide, any spelling: `docker [container] run|create ... --name[= ]zot`, in every tracked
# script, template and workflow (not only this template). A second site in ANY file is a second
# way to start zot that the sentinel bind may not cover.
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null)"
ALL_ZOT_SITES="$(cd "$REPO_ROOT" && git ls-files -z -- '*.yml' '*.yaml' '*.sh' '*.tf' '*.tmpl' ':!*.test.sh' ':!knowledge-base/**' \
  | xargs -0 awk '{ if (sub(/\\[[:blank:]]*$/, "")) { buf = buf $0; next } line = buf $0; buf = "" }
      line ~ /^[[:blank:]]*#/ { next }
      line ~ /docker[[:blank:]]+(container[[:blank:]]+)?(run|create)[[:blank:]]/ && line ~ /--name[= ]zot([[:blank:]]|$)/ { print FILENAME }' 2>/dev/null | sort | uniq -c)"
ALL_ZOT_N="$(printf '%s\n' "$ALL_ZOT_SITES" | awk 'NF { s += $1 } END { print s + 0 }')"
ZOT_RUN_N="$(grep -c . <<<"$ZOT_RUNS" || true)"
[ -n "$ZOT_RUNS" ] || ZOT_RUN_N=0
check "exactly ONE \`docker run … --name zot\` site in the template (set identity; found $ZOT_RUN_N)" \
  "[ '$ZOT_RUN_N' -eq 1 ]"
check "repo-wide, exactly ONE zot run/create site of any spelling, and it is this template (found: $(tr -s ' \n' ' ' <<<"$ALL_ZOT_SITES"))" \
  "[ '$ALL_ZOT_N' -eq 1 ] && grep -qE '^ *1 apps/web-platform/infra/cloud-init-registry.yml$' <<<\"\$ALL_ZOT_SITES\""
check "the zot run binds the sentinel with --mount type=bind (a missing source refuses the start)" \
  "grep -qF -- '--mount type=bind,source=$SENT,target=/run/soleur-luks-sentinel,readonly' <<<\"\$ZOT_RUNS\""
check "the zot run never binds the sentinel with -v (which would CREATE a missing source)" \
  "! grep -qE -- '-v[[:blank:]]+$SENT' <<<\"\$ZOT_RUNS\""

# Ordering, on physical line numbers: gate < conjunction < write < run.
GATE_LN="$(grep -nF 'findmnt -no SOURCE /var/lib/zot | grep -cx /dev/mapper/registry >/dev/null ||' "$CI_YML" | sed -n '1p' | cut -d: -f1)"
CONJ_LN="$(grep -nF 'if [ "$(findmnt -no SOURCE /var/lib/zot)" = /dev/mapper/registry ]; then' "$CI_YML" | sed -n '1p' | cut -d: -f1)"
WRITE_LN="$(grep -nE "install -m 0444 -o root -g root /dev/null $SENT( \|\| true)?\$" "$CI_YML" | sed -n '1p' | cut -d: -f1)"
FI_LN="$(awk -v s="${CONJ_LN:-0}" 'NR > s && /^[[:blank:]]*fi[[:blank:]]*$/ { print NR; exit }' "$CI_YML")"
RUN_LN="$(grep -nE '^[[:blank:]]*docker run -d --name zot ' "$CI_YML" | sed -n '1p' | cut -d: -f1)"
check "the first-boot findmnt gate, the sentinel conjunction, the write and the zot run were all located" \
  "[ -n '$GATE_LN' ] && [ -n '$CONJ_LN' ] && [ -n '$WRITE_LN' ] && [ -n '$FI_LN' ] && [ -n '$RUN_LN' ]"
check "the sentinel write sits INSIDE the findmnt = /dev/mapper/registry conjunction (never on the root disk)" \
  "[ '${CONJ_LN:-0}' -lt '${WRITE_LN:-0}' ] && [ '${WRITE_LN:-0}' -lt '${FI_LN:-0}' ]"
check "order: mount gate < sentinel write < zot docker run" \
  "[ '${GATE_LN:-0}' -lt '${CONJ_LN:-0}' ] && [ '${FI_LN:-0}' -lt '${RUN_LN:-0}' ]"
check "exactly one sentinel write in the template (no second, unconditional copy)" \
  "[ \"\$(grep -cE 'install [^#]*$SENT' '$CI_YML')\" -eq 1 ]"

# The recovery arm (its behaviour is pinned in private-nic-guard.test.sh T12*).
check "the NIC guard's recovery arm reads .State.Running AND .State.Restarting of an EXISTING container" \
  "grep -qF \"_zst=\\\"\\\$(docker inspect -f '{{.State.Running}} {{.State.Restarting}}' zot 2>/dev/null)\\\"\" '$CI_YML' && grep -qF 'if [ -n \"\$_zst\" ] && [ \"\$_zst\" = \"false false\" ]' '$CI_YML'"
check "the recovery arm requires a REGULAR-file, non-symlink sentinel (the bind-source escape)" \
  "grep -qF '&& [ -f \"\$R$SENT\" ] && [ ! -L \"\$R$SENT\" ]; then' '$CI_YML'"
check "the launch block removes a symlinked sentinel and makes the sentinel immutable (+i)" \
  "grep -qF '[ -L $SENT ] && rm -f $SENT' '$CI_YML' && grep -qF 'chattr +i $SENT' '$CI_YML'"
check "the recovery arm starts zot (docker start, not a re-run)" \
  "grep -qF 'if docker start zot >/dev/null 2>&1; then ZOT_START_ACTION=start_ok; else ZOT_START_ACTION=start_failed; fi' '$CI_YML'"
check "zot_start_action rides the POSTed SOLEUR_PRIVATE_NIC line, before zot_last_err=" \
  "grep -qE 'LINE=\"SOLEUR_PRIVATE_NIC [^\"]* zot_start_action=\\\$ZOT_START_ACTION [^\"]* zot_last_err=' '$CI_YML'"

# The luks-open arm vocabulary: every token the writer can emit is one the reader admits, and
# the reader admits nothing the writer cannot emit (set identity, derived from both sides).
# Call sites only: non-comment lines, `arm <token>` at statement start or after `{`/`;`. The
# word "arm" in prose must not count, or the derivation measures comments.
WRITTEN="$(sed -E '/^[[:blank:]]*#/d' "$CI_YML" | grep -oE '(^[[:blank:]]*|[{;][[:blank:]]*)arm [a-z_]+' | awk '{print $NF}' | sort -u)"
# shellcheck disable=SC2034  # read inside check()'s eval'd condition string
READ_SET="$(grep -E '^[[:blank:]]+already_open \| opened' "$CI_YML" | sed -n '1p' | sed -E 's/\).*//; s/[|]/ /g' | tr -s ' ' '\n' | grep . | sort -u)"
check "the writer emits all six luks-open arms (derived: $(tr '\n' ' ' <<<"$WRITTEN"))" \
  "[ \"\$(grep -c . <<<\"\$WRITTEN\")\" -eq 6 ]"
check "writer set == reader set (a token the reader rejects would read __UNREADABLE__ forever)" \
  "[ \"\$WRITTEN\" = \"\$READ_SET\" ]"
ARM_DEFS="$(grep -E '^[[:blank:]]*arm\(\) \{' "$CI_YML" | sed -E 's/^[[:blank:]]+//')"
check "arm() is defined exactly twice (outer script + the doppler heredoc) and the two are byte-identical" \
  "[ \"\$(grep -c . <<<\"\$ARM_DEFS\")\" -eq 2 ] && [ \"\$(sort -u <<<\"\$ARM_DEFS\" | grep -c .)\" -eq 1 ]"
check "the reader reads the SAME path every arm() writer renames into" \
  "grep -qF 'mv -f /run/soleur-registry/luks-open.arm.tmp /run/soleur-registry/luks-open.arm' <<<\"\$ARM_DEFS\" && grep -qF '[ -e /run/soleur-registry/luks-open.arm ]' '$CI_YML'"
check "the arm file lives on tmpfs (/run), so it can never carry a previous boot's answer" \
  "grep -qF 'printf '\\''%s\\n'\\'' \"\$1\" > /run/soleur-registry/luks-open.arm.tmp' '$CI_YML'"

STATIC_CASES="$cases"

# --- Behavioural, docker-gated: docker's start-time bind resolution --------------------------
if ! docker info >/dev/null 2>&1; then
  printf '\nNO-DOCKER: the docker-gated half of this guard did not run (static: %s passed, %s failed).\n' \
    "$passes" "$fails" >&2
  printf 'This fails CLOSED by design -- see the header. CI deploy-script-tests has a daemon.\n' >&2
  exit 3
fi

# Build the probe image offline from the runner's own /bin/true and its libraries.
ROOTFS="$TMP/rootfs"
mkdir -p "$ROOTFS/bin"
TRUE_BIN="$(readlink -f /bin/true)"
cp "$TRUE_BIN" "$ROOTFS/bin/true"
while IFS= read -r lib; do
  [ -n "$lib" ] && [ -e "$lib" ] && cp --parents -L "$lib" "$ROOTFS"
done < <(ldd "$TRUE_BIN" 2>/dev/null | grep -oE '/[^ ]+' | sort -u)
IMPORT_RC=0
tar -C "$ROOTFS" -c . | docker import - "$PROBE_TAG" >/dev/null 2>&1 || IMPORT_RC=$?
check "probe image imported offline from the runner's /bin/true (rc=$IMPORT_RC)" "[ '$IMPORT_RC' -eq 0 ]"

mk() { # <name> <mount-args...>
  local n="$1"; shift
  CNAMES+=("$n")
  docker create --name "$n" "$@" "$PROBE_TAG" /bin/true >/dev/null 2>&1
}
start_rc() { local rc=0; docker start -a "$1" >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }
restart_rc() { local rc=0; docker restart "$1" >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }

# The gate: --mount type=bind of a FILE inside a directory standing in for the LUKS filesystem.
G="gate-mount-$$"
: > "$TMP/sentinel"
MK_RC=0; mk "$G" --mount "type=bind,source=$TMP/sentinel,target=/run/soleur-luks-sentinel,readonly" || MK_RC=$?
check "--mount container created while the sentinel exists" "[ '$MK_RC' -eq 0 ]"
check "--mount: start SUCCEEDS with the sentinel present" "[ \"\$(start_rc '$G')\" -eq 0 ]"
rm -f "$TMP/sentinel"
check "--mount: start FAILS once the sentinel is gone (the closed-mapper reboot)" "[ \"\$(start_rc '$G')\" -ne 0 ]"
check "--mount: restart FAILS once the sentinel is gone (the NIC guard's docker restart)" "[ \"\$(restart_rc '$G')\" -ne 0 ]"
check "--mount: the missing source was NOT auto-created by the failed starts" "[ ! -e '$TMP/sentinel' ]"
: > "$TMP/sentinel"
check "--mount: start SUCCEEDS again once the sentinel returns (the recovery leg)" "[ \"\$(start_rc '$G')\" -eq 0 ]"

# Negative control: -v behaves differently, which is exactly why the gate must be --mount. If
# this control ever fails, the suite can no longer tell the two mount kinds apart.
V="gate-v-$$"
: > "$TMP/sentinel-v"
MKV_RC=0; mk "$V" -v "$TMP/sentinel-v:/run/soleur-luks-sentinel:ro" || MKV_RC=$?
check "-v control container created" "[ '$MKV_RC' -eq 0 ]"
rm -f "$TMP/sentinel-v"
check "-v NEGATIVE CONTROL: start still SUCCEEDS after the source is deleted (docker recreates it)" \
  "[ \"\$(start_rc '$V')\" -eq 0 ]"

# --- Anti-vacuity floors: printf + exit, never through check() (ADR-193) ------------------------
MIN_STATIC=18
if [ "$STATIC_CASES" -lt "$MIN_STATIC" ]; then
  printf '\n[FATAL] floor: only %s static cases ran (expected >= %s).\n' "$STATIC_CASES" "$MIN_STATIC" >&2
  exit 1
fi
MIN_CASES=27
if [ "$cases" -lt "$MIN_CASES" ]; then
  printf '\n[FATAL] floor: only %s cases ran (expected >= %s).\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [ $((passes + fails)) -ne "$cases" ]; then
  printf '\n[FATAL] conservation: pass+fail (%s) != cases (%s).\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi
printf '\n%s passed, %s failed (%s cases)\n' "$passes" "$fails" "$cases"
[ "$fails" -eq 0 ]
