#!/usr/bin/env bash
# Guard 1 (#7500) — producer-side redaction of the diagnostic sample.
#
# PROPERTY. No credential-bearing header value present in zot's log output leaves
# zot-disk-heartbeat.sh in the clear — INCLUDING a header name this codebase has not
# anticipated, on EVERY line of a multi-line sample — and the SOLEUR_ZOT_DISK row is emitted on
# every path, including every redaction-failure path.
#
# WHY A BEHAVIOURAL SUITE. No behavioural suite for the heartbeat existed; the only coverage was
# structural greps in registry-boot-guard.test.sh. A structural grep cannot answer the question
# that actually matters here — "does redact() run BEFORE the sanitizer, and PER LINE?" — because
# both orderings and both arities look identical in a grep. Measured during planning: applied to
# a whole multi-line blob, redact() takes its non-JSON DENYLIST branch and an unanticipated
# header (X-Secret) leaks in the clear at RC=0. Applied after the sanitizer, the quotes are gone,
# the JSON branch can never fire, and the same leak returns. Only execution distinguishes these.
#
# ASSEMBLY — three chokepoints, all named, because scoping to one is the defect this exists to
# catch. (1) The VALUE chokepoint: the single ZOT_LAST_ERR= assignment all four tiers flow into,
# so a fifth tier is covered by construction. (2) The PER-LINE chokepoint: the loop applying
# redact() to each line of ZOT_ERR_RAW. (3) The EMIT chokepoint: the single LINE= assembly and
# its one post() call — which is what this suite asserts on, by capturing the POSTed body.
#
# Built on the apps/web-platform/infra/zot-log-shipper.test.sh template: extract the write_files
# block from the template, apply local.registry_rationale_strip, assert the stripped result is
# still valid bash, then execute it against synthesized PATH stubs. No live host, no network, no
# docker, no doppler, no root.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_YML="$SCRIPT_DIR/cloud-init-registry.yml"   # NOT `CI`: runners export CI=1 and the export attribute survives reassignment
HB_PATH="/usr/local/bin/zot-disk-heartbeat.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0; CASES=0
VERDICTS=""
USED_assert=0
USED_assert_emit=0
USED_assert_field=0

# (#8386) THE ANTI-VACUITY FLOOR IS SPLIT PER PROPERTY. This file now covers TWO properties --
# zot_last_err redaction (#7500) and the at-rest posture emitter (#8386) -- and one integer over
# their sum is not a floor for either: deleting every posture case still clears a raised total
# because the redaction cases alone exceed it. Each property carries its own counter and its own
# literal floor, reported with printf + exit, never through the helpers they backstop (ADR-193).
PHASE=redact
CASES_REDACT=0
CASES_POSTURE=0
_bump_cases() {
  CASES=$((CASES + 1))
  if [ "$PHASE" = posture ]; then CASES_POSTURE=$((CASES_POSTURE + 1))
  else CASES_REDACT=$((CASES_REDACT + 1)); fi
}

pass() { PASS=$((PASS + 1)); VERDICTS="${VERDICTS}P"; printf 'ok   - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); VERDICTS="${VERDICTS}F"; printf 'FAIL - %s\n' "$1" >&2; }

assert() {
  USED_assert=$((USED_assert + 1)); _bump_cases
  local name="$1" expr="$2"
  if eval "$expr" >/dev/null 2>&1; then pass "$name"; else fail "$name  [expr: $expr]"; fi
}

# --- extraction: pull the heartbeat write_files block out of the template ------------------
# Verbatim from zot-log-shipper.test.sh — the same template, the same block shape.
extract_block() {
  local want_path="$1" out="$2"
  awk -v want="  - path: $want_path" '
    $0 == want { found = 1; next }
    found && /^    content: \|$/ { incontent = 1; next }
    incontent {
      if ($0 ~ /^      /) { print substr($0, 7); next }
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      exit
    }
  ' "$CI_YML" > "$out"
}

# THE RATIONALE STRIP, replicated from zot-registry.tf's
# registry_rationale_strip = "/(?m)^[ \t]*#([ \t][^\n]*)?\n/".
# [[:blank:]] is EXACTLY space+tab, matching RE2's [ \t]; [[:space:]] would be wider.
apply_rationale_strip() { sed -E '/^[[:blank:]]*#([[:blank:]].*)?$/d' "$1"; }

# --- T1: render the heartbeat, strip it, prove it is still valid bash ---------------------
RAW="$TMP/hb.raw.sh"
extract_block "$HB_PATH" "$RAW"
assert "T1 heartbeat block extracted from the template (non-empty)" "[[ -s '$RAW' ]]"
assert "T1 extracted block is the heartbeat (has a shebang)" "head -1 '$RAW' | grep -q '^#!'"

HB="$TMP/hb.sh"
apply_rationale_strip "$RAW" > "$HB"
# TF-escaped shell expansions: $${VAR} -> ${VAR}; %%{ -> %{.
sed -i 's|\$\${|${|g' "$HB"
sed -i 's|%%{|%{|g' "$HB"
sed -i "s|\${betterstack_ingest_url}|http://127.0.0.1:9/ingest|g" "$HB"
# The heartbeat block carries three more template variables than the shipper does. Rendering
# them is not cosmetic: an unrendered ${...} inside double quotes never trips `set -u`, so the
# suite would execute a subtly broken program and read its silence as a SUT finding. The
# assertion below is what turns that into a loud failure.
sed -i 's|\${disk_heartbeat_url}|http://127.0.0.1:9/hb|g' "$HB"
sed -i 's|\${zot_pull_user}|pulluser|g' "$HB"
sed -i 's|\${zot_push_user}|pushuser|g' "$HB"
# (#8386) The FIFTH template variable: store_expected_devid carries the Terraform-rendered
# volume alias. Without this line the T1 assertion below fails by construction, and every
# posture case would run against a script whose LINE= still holds an unrendered ${...}.
sed -i 's|\${registry_volume_id}|100000003|g' "$HB"
# (#8417) The TF-interpolation check runs on a copy where every ESCAPED `$$` is masked, and the
# same five template-variable substitutions are applied. It used to run on the rendered copy and
# match any `${word}` -- which was only sound while no shell expansion in the block was written
# in the braced `$${word}` form. The #8417 fix writes `$${_cs_rc}`, which renders to a legitimate
# SHELL `${_cs_rc}`; the only thing that can be an unrendered TERRAFORM interpolation is a
# single-dollar `${` in the template source.
TFCHK="$TMP/hb.tfcheck"
apply_rationale_strip "$RAW" | sed -e 's|[$][$]|__ESCAPED_DD__|g' \
  -e 's|\${betterstack_ingest_url}|x|g' -e 's|\${disk_heartbeat_url}|x|g' \
  -e 's|\${zot_pull_user}|x|g' -e 's|\${zot_push_user}|x|g' -e 's|\${registry_volume_id}|x|g' > "$TFCHK"
assert "T1 render left no unrendered TF interpolation" "[[ -s '$TFCHK' ]] && ! grep -qF '\${' '$TFCHK'"
assert "T1 the COMMENT-STRIPPED heartbeat is still valid bash (the strip reaches inside heredocs)" \
  "bash -n '$HB'"
chmod +x "$HB"

# --- PATH stubs ---------------------------------------------------------------------------
# Derived from the block's own calls, not guessed:
#   grep -oE '\b(docker|curl|htpasswd|df|hostname|date|free|stat|journalctl)\b'
# Coreutils (grep/sed/awk/tr/head/tail/printf/cat) stay REAL — stubbing them would put the
# fixture seam above the code under test.
BIN="$TMP/bin"; mkdir -p "$BIN"

# docker stub: `docker logs` emits the fixture; every other subcommand answers benignly.
# It VALIDATES argv and exits 64 on an unrecognised shape — a stub that answers regardless of
# its arguments cannot detect the SUT querying the wrong thing.
cat > "$BIN/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  logs)
    [[ "$*" == *"zot"* ]] || { echo "docker stub: logs without a container name" >&2; exit 64; }
    [[ -r "${HB_FIXTURE:-}" ]] && cat "$HB_FIXTURE"
    exit 0 ;;
  inspect) printf 'running\nfalse\n0\n' ; exit 0 ;;
  ps)      exit 0 ;;
  exec)    exit 0 ;;
  *)       exit 0 ;;
esac
EOF

# curl stub: records the full POSTed body. This is the EMIT chokepoint — every assertion about
# what leaves the host reads this file. Validates argv: a POST with no --data-raw is a bug.
cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
body=""; has_m=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-raw) body="$2"; shift 2 ;;
    -m|--max-time) has_m=1; shift 2 ;;
    *) shift ;;
  esac
done
[[ "$has_m" == 1 ]] || { echo "curl stub: unbounded call (no -m/--max-time)" >&2; exit 64; }
[[ -n "$body" ]] || { echo "curl stub: POST with no --data-raw" >&2; exit 64; }
printf '%s\n' "$body" >> "${HB_POSTED:-/dev/null}"
exit 0
EOF

# htpasswd: the rotation-divergence probe. exit 0 = "password correct" on every check.
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/htpasswd"
# df: pcent well under the 85%% ping gate, and a plausible size.
cat > "$BIN/df" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--output=pcent"* ]]; then printf 'Use%%\n 12%%\n'; else printf '1G-blocks\n 40\n'; fi
exit 0
EOF
printf '#!/usr/bin/env bash\nprintf "soleur-registry\\n"\n' > "$BIN/hostname"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/free"
printf '#!/usr/bin/env bash\nprintf "0\\n"\n' > "$BIN/stat"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/journalctl"

# --- (#8386) at-rest posture: the four measurement stubs ------------------------------------
# All four VALIDATE argv and exit 64 on any other shape. A stub that answers regardless of its
# arguments cannot detect the SUT asking the wrong question -- and "which device did blkid read?"
# is precisely the question mutation 3 turns on.
cat > "$BIN/findmnt" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "-no SOURCE /var/lib/zot" ]] || { echo "findmnt stub: unexpected argv: $*" >&2; exit 64; }
[[ -n "${HB_FINDMNT_OUT:-}" ]] && printf '%s\n' "$HB_FINDMNT_OUT"
exit "${HB_FINDMNT_RC:-0}"
EOF

# `-inso NAME` ONLY: -i (ASCII glyphs) and -s (inverse tree) with NO -d are the invariant the
# leaf count rests on, so a mutant that drops either must not get an answer out of this stub.
# PER-SUBJECT, like blkid below. Validating only the FLAG shape leaves the stub answering the
# same tree whatever device it is asked about -- so the emitter could walk a hardcoded /dev/sda,
# or (worse) the DECLARED expected alias, and stay green. The second makes store_mount_devid
# equal store_expected_devid BY CONSTRUCTION, so the probe's devid_mismatch disjunct -- the whole
# "is the store on the volume we declared?" question -- could never fire on a live host while
# every suite passed. HB_LSBLK_SUBJ pins which device the walk must ask about (#8386 review).
cat > "$BIN/lsblk" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "-inso" && "$2" == "NAME" && -n "${3:-}" ]] || { echo "lsblk stub: unexpected argv: $*" >&2; exit 64; }
if [[ -n "${HB_LSBLK_SUBJ:-}" && "$3" != "$HB_LSBLK_SUBJ" ]]; then
  echo "lsblk stub: walked '$3' but the fixture only maps '$HB_LSBLK_SUBJ'" >&2; exit 64
fi
[[ -n "${HB_LSBLK_OUT:-}" ]] && printf '%s\n' "$HB_LSBLK_OUT"
exit "${HB_LSBLK_RC:-0}"
EOF

# PER-SUBJECT for the same reason: `cryptsetup status <name>` must be asked about the mapper the
# store is actually mounted from, not a hardcoded name.
cat > "$BIN/cryptsetup" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "status" && $# -eq 2 && -n "$2" ]] || { echo "cryptsetup stub: unexpected argv: $*" >&2; exit 64; }
if [[ -n "${HB_CRYPT_SUBJ:-}" && "$2" != "$HB_CRYPT_SUBJ" ]]; then
  echo "cryptsetup stub: asked about '$2' but the fixture only maps '$HB_CRYPT_SUBJ'" >&2; exit 64
fi
[[ -n "${HB_CRYPT_OUT:-}" ]] && printf '%s\n' "$HB_CRYPT_OUT"
exit "${HB_CRYPT_RC:-0}"
EOF

# PER-DEVICE, deliberately. HB_BLKID_MAP is a space-separated <dev>=<type> map, so the
# partitioned fixture can answer crypto_LUKS for /dev/sdb1 and NOTHING for /dev/sdb -- which is
# what makes "blkid reads the cryptsetup `device:` line, not /dev/$STORE_MOUNT_BASE" falsifiable.
# An unmapped device exits 2, blkid's own "nothing found" status.
cat > "$BIN/blkid" <<'EOF'
#!/usr/bin/env bash
dev=""; want_value=0; want_type=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) [[ "${2:-}" == value ]] && want_value=1; shift 2 ;;
    -s) [[ "${2:-}" == TYPE ]] && want_type=1; shift 2 ;;
    *)  dev="$1"; shift ;;
  esac
done
[[ "$want_value" == 1 && "$want_type" == 1 && -n "$dev" ]] || { echo "blkid stub: unexpected argv" >&2; exit 64; }
for kv in ${HB_BLKID_MAP:-}; do
  [[ "${kv%%=*}" == "$dev" ]] || continue
  [[ -n "${kv#*=}" ]] && printf '%s\n' "${kv#*=}"
  exit 0
done
exit 2
EOF

chmod +x "$BIN"/*

# The sbin-only fixture (E5): the SAME four stubs reachable ONLY through the literal PATH append
# the emitter ships. $BIN itself is off the PATH for that case, so if the append is deleted the
# tools are unreachable and store_luks collapses to unknown.
mkdir -p "$BIN/sbin"
for _m in findmnt lsblk cryptsetup blkid; do cp "$BIN/$_m" "$BIN/sbin/$_m"; done

# --- (#8386) RENDER-TIME SEAMS, never runtime ones ------------------------------------------
# The heartbeat runs as root under `doppler run --project soleur-registry --config prd`, which
# injects EVERY secret in that config as an environment variable. An env-overridable sbin dir or
# by-id root would therefore let a config-store write own root's first resolution of cryptsetup
# and blkid, every five minutes. So the script ships two LITERALS and the seams live HERE, in the
# same render step that already substitutes the template variables above. Applied after the
# bash -n / no-unrendered-interpolation assertions, because neither literal is TF interpolation.
# The PATH assignment is substituted WHOLE, not by its sbin suffix. The shipped form PREPENDS
# the trusted dirs and only appends the inherited value ($${PATH:+:$$PATH}), which is the point
# of the #8386 review fix: a `PATH` secret in the config store can no longer win first
# resolution. That also means the harness can no longer inject stubs THROUGH the environment --
# the real /usr/bin would beat them -- so the seam has to replace the whole line.
sed -i "s|^PATH=.*|PATH=\"$BIN:$BIN/sbin:\$PATH\"|" "$HB"
sed -i "s|/dev/disk/by-id/|$TMP/by-id/|g" "$HB"
# (#8408) the per-boot tmpfs state dir, re-rooted the same way (a render-time literal seam).
sed -i "s|/run/soleur-registry/|$TMP/run-soleur-registry/|g" "$HB"
mkdir -p "$TMP/run-soleur-registry"
# (#8408 (c)) the escrow state dir, re-rooted the same way.
sed -i "s|/var/lib/soleur-registry/|$TMP/var-lib-soleur-registry/|g" "$HB"
mkdir -p "$TMP/var-lib-soleur-registry"
# Non-vacuity for BOTH seams: if either literal is renamed in the template these substitutions
# silently no-op and the sbin-only / devid cases would pass against an unseamed script.
PHASE=posture   # both seams belong to the #8386 property, not to the #7500 floor
assert "T1 PATH seam landed (the stub dirs now win first resolution)" \
  "grep -qF 'PATH=\"$BIN:$BIN/sbin:\$PATH\"' '$HB'"
# The RENDERED copy deliberately still inherits, so per-case `PATH=` overrides (the no-jq tier-4
# cases) keep working. The SHIPPED template must NOT: it prepends the trusted dirs so a `PATH`
# secret in the config store cannot win first resolution as root. That property belongs to the
# template, so it is asserted against the template here rather than against this rendered copy.
#
# (#8417) EVALUATED, not grepped. The assert this replaces pinned the SPELLING
# `$${PATH:+:$$PATH}` -- and that spelling was the defect: Terraform renders `$${` to `${` but
# leaves a bare `$$` verbatim, so bash expanded it to `:<PID>PATH` and the inherited PATH was
# never appended at all. A grep of the spelling was green over the bug for its whole life. So
# render the shipped line the way templatefile does, run it, and assert what PATH BECOMES.
_SHIPPED_PATH_LINE="$(grep -E '^[[:blank:]]+PATH="/usr/local/sbin:' "$CI_YML" | head -1 | sed -E 's/^[[:blank:]]+//; s/[$][$][{]/${/g')"
_TRUSTED='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
_EVAL_INHERIT="$(env -i /bin/bash --noprofile --norc -c "PATH=/inherited/dir; $_SHIPPED_PATH_LINE; printf '%s' \"\$PATH\"" 2>/dev/null)"
_EVAL_UNSET="$(env -i /bin/bash --noprofile --norc -c "unset PATH; $_SHIPPED_PATH_LINE; printf '%s' \"\$PATH\"" 2>/dev/null)"
assert "the SHIPPED PATH line was found in the template (non-empty extraction)" \
  "[[ -n \"\$_SHIPPED_PATH_LINE\" ]]"
assert "the SHIPPED template prepends trusted dirs (a PATH secret cannot win first resolution)" \
  "[[ \"\$_EVAL_INHERIT\" == \"\$_TRUSTED:\"* ]]"
assert "(#8417) the SHIPPED template APPENDS the inherited PATH (evaluated: exact result)" \
  "[[ \"\$_EVAL_INHERIT\" == \"\$_TRUSTED:/inherited/dir\" ]]"
assert "(#8417) the evaluated PATH carries no PID-shaped token (a bare \$\$ renders as <pid>PATH)" \
  "! grep -qE '[0-9]+PATH' <<<\"\$_EVAL_INHERIT\""
assert "(#8417) with PATH unset the SHIPPED line yields exactly the trusted list (no stray colon)" \
  "[[ \"\$_EVAL_UNSET\" == \"\$_TRUSTED\" ]]"
assert "the SHIPPED template pins LC_ALL=C (the guards below are locale-defined character classes)" \
  "grep -qF 'export LC_ALL=C' '$CI_YML'"
assert "T1 by-id seam landed (the shipped reverse map now walks the fixture dir)" \
  "grep -qF '$TMP/by-id/scsi-0HC_Volume_' '$HB'"
assert "T1 luks-open arm seam landed (the reader now reads the fixture dir)" \
  "grep -qF '$TMP/run-soleur-registry/luks-open.arm' '$HB'"
PHASE=redact

# run_hb <fixture-content> [extra-env...] -> prints the emitted SOLEUR_ZOT_DISK row.
# Captures at the POST, which is the single emit chokepoint the whole property funnels through.
run_hb() {
  local fixture="$1"; shift
  local fx="$TMP/fixture.log" posted="$TMP/posted.log"
  printf '%s\n' "$fixture" > "$fx"
  : > "$posted"
  env PATH="$BIN:$PATH" HB_FIXTURE="$fx" HB_POSTED="$posted" \
      BETTERSTACK_LOGS_TOKEN="test-token-not-a-secret" "$@" \
      bash "$HB" >/dev/null 2>&1 || true
  cat "$posted"
}

# last_err_of <posted-body> -> the zot_last_err value (emitted LAST, free-text).
last_err_of() { sed -n 's/.* zot_last_err=//p' <<<"$1" | sed 's/\\"}"*$//' | head -1; }

# assert_emit <name> <fixture> <mode:absent|present> <needle> [extra-env...]
assert_emit() {
  USED_assert_emit=$((USED_assert_emit + 1)); _bump_cases
  local name="$1" fixture="$2" mode="$3" needle="$4"; shift 4
  local out
  out="$(run_hb "$fixture" "$@")"
  if [[ -z "$out" ]]; then
    fail "$name: NO row was emitted — the heartbeat must ship on every path, including failure paths"
    return
  fi
  case "$mode" in
    absent)
      if [[ "$out" == *"$needle"* ]]; then fail "$name: emitted row leaked '$needle' -- $out"
      else pass "$name: emitted row carries no '$needle'"; fi ;;
    present)
      if [[ "$out" == *"$needle"* ]]; then pass "$name: emitted row carries '$needle'"
      else fail "$name: emitted row lost '$needle' -- $out"; fi ;;
  esac
}

# --- (#8386) at-rest posture helpers --------------------------------------------------------
# The by-id fixture. `readlink -f` resolves each alias to a real path whose BASENAME is what the
# emitter's reverse map compares against, so the targets are real files under $TMP/dev.
BYID="$TMP/by-id"; DEVROOT="$TMP/dev"
mkdir -p "$BYID" "$DEVROOT"
for _d in sdb sdb1 sdc; do : > "$DEVROOT/$_d"; done
# set_byid <alias>:<target-basename> ... -- repopulates the fixture dir for the case about to run.
set_byid() {
  rm -f "$BYID"/* 2>/dev/null || true
  local spec
  for spec in "$@"; do ln -s "$DEVROOT/${spec#*:}" "$BYID/${spec%%:*}"; done
}

# ROW / HEAD are set by posture_case and read by assert_field. HEAD is the TRUSTED region: the
# row up to the first ` zot_last_err=`, which is where all five posture fields must live.
ROW=""; HEAD=""; HB_EXIT=0; HB_POSTS=0
POSTURE_FIXTURE=""

_head_tokens_ok() {
  # Quantified over EVERY token in the trusted head, not over a fixed five (M1): a sixth field
  # added later inherits this contract instead of escaping it.
  #   - no quote and no backslash anywhere in the head (the row is POSTed unescaped inside
  #     {"message":"..."}, so either byte corrupts the JSON envelope);
  #   - every token is `key=value`, which is how a SPACE inside a value is caught: the space
  #     splits it into a bare word carrying no `=`.
  # Emptiness is NOT asserted here -- several pre-existing fields legitimately render empty
  # against these stubs (zot_restarts=, state_status=), and the five posture fields are pinned
  # to exact values by assert_field anyway.
  case "$HEAD" in *'"'*|*'\'*) return 1 ;; esac
  local t
  for t in $HEAD; do
    [ "$t" = "SOLEUR_ZOT_DISK" ] && continue
    case "$t" in *=*) : ;; *) return 1 ;; esac
  done
  return 0
}

# DERIVED from the LINE= assembly, never restated. A hand-listed set is a claim about which
# fields exist, and it is wrong the moment one is added: `store_mount_base` was emitted in the
# #8386 review and sat OUTSIDE this check until the review's structural-enumeration seat found
# it, because the list said five and the row carried six. Deriving means a new posture field
# joins the trusted-region ordering requirement by existing.
POSTURE_FIELDS="$(grep -F 'LINE="SOLEUR_ZOT_DISK' "$CI_YML" | head -1 \
  | grep -oE 'store_[a-z_]+=' | sed 's/=$//' | sort -u)"
[ -n "$POSTURE_FIELDS" ] || { printf '  FATAL: derived ZERO posture fields from LINE= -- the extraction broke, so every ordering assertion below would pass vacuously.\n' >&2; exit 2; }
POSTURE_FIELD_N="$(printf '%s\n' "$POSTURE_FIELDS" | wc -l | tr -d ' ')"
[ "$POSTURE_FIELD_N" -ge 6 ] || { printf '  FATAL: derived only %s posture field(s); the floor is 6 (fix the emitter, do not lower this).\n' "$POSTURE_FIELD_N" >&2; exit 2; }
_posture_fields_in_head() {
  local f
  for f in $POSTURE_FIELDS; do
    case " $HEAD " in *" $f="*) : ;; *) return 1 ;; esac
  done
  return 0
}

# posture_case <label> [env assignments...] -- runs the rendered heartbeat once against the
# current stub environment, captures the POSTed row, and asserts the per-case invariant bundle
# (exactly one POST, exit 0, charset, and all five fields inside the trusted region).
posture_case() {
  local name="$1"; shift
  local fx="$TMP/fixture.log" posted="$TMP/posted.log"
  printf '%s\n' "${POSTURE_FIXTURE:-$TIER2_BENIGN}" > "$fx"
  : > "$posted"
  env PATH="$BIN:$PATH" HB_FIXTURE="$fx" HB_POSTED="$posted" \
      BETTERSTACK_LOGS_TOKEN="test-token-not-a-secret" "$@" \
      bash "$HB" >/dev/null 2>&1
  HB_EXIT=$?
  HB_POSTS="$(grep -c . "$posted" || true)"
  # Strip the JSON envelope the producer wraps the row in: the property is about the ROW, and
  # the envelope's own quotes would otherwise satisfy the charset check vacuously.
  ROW="$(head -1 "$posted" | sed -e 's|^{"message":"||' -e 's|"}$||')"
  HEAD="${ROW%% zot_last_err=*}"
  assert "$name | exactly ONE row POSTed (the emit is unconditional, never doubled)" \
    "[ '$HB_POSTS' -eq 1 ]"
  assert "$name | the heartbeat exits 0 (the 5-min cron must never wedge)" "[ $HB_EXIT -eq 0 ]"
  assert "$name | every trusted-head token is key=<non-empty>, no space/quote/backslash" \
    "_head_tokens_ok"
  assert "$name | all $POSTURE_FIELD_N posture fields precede ' zot_last_err='" "_posture_fields_in_head"
}

# assert_field <name> <key> <expected> -- EXACT TOKEN equality on the trusted head.
# assert_emit is substring-only, so `store_luks=yes` also matches `store_luks=yesX` and every
# posture expectation written through it would be satisfiable by a longer wrong value.
_field_value() {
  local k="$1" t
  for t in $HEAD; do
    case "$t" in "$k="*) printf '%s' "${t#*=}"; return 0 ;; esac
  done
  return 1
}
assert_field() {
  USED_assert_field=$((USED_assert_field + 1)); _bump_cases
  local name="$1" key="$2" want="$3" got
  if ! got="$(_field_value "$key")"; then
    fail "$name: field '$key' is absent from the trusted head -- $HEAD"
    return
  fi
  if [ "$got" = "$want" ]; then pass "$name: $key=$want"
  else fail "$name: $key expected '$want', got '$got'"; fi
}

# --- Fixtures ------------------------------------------------------------------------------
# zot emits zerolog JSON, one object per line, under --log-driver journald.
# Tier-4 shaped (level:info matches no tier 1-3). Used by G1-6b below to prove the TIER GATE
# withholds an unanticipated header -- a distinct property from G1-2's allowlist check, which
# needs a tier-2 fixture to reach redact() at all.
JSON_XSECRET='{"level":"info","message":"HTTP API","headers":{"X-Secret":["UNANTICIPATED-VALUE"],"Content-Type":["application/json"]},"clientIP":"10.0.1.9"}'
JSON_COOKIE='{"level":"error","message":"PatchBlobUpload i/o timeout","headers":{"Cookie":["session=COOKIE-SECRET"]},"clientIP":"10.0.1.9"}'
PANIC_LINE='panic: runtime error: invalid memory address'
# Row 2b — the MIXED blob: a panic frame (non-JSON) beside a JSON row. Measured during planning:
# applied to the blob as ONE string, redact() takes the non-JSON denylist branch and X-Secret
# leaves in the clear at RC=0. This fixture is what discriminates per-line application.
#
# EVERY LINE HERE MUST MATCH THE SAME TIER, and that is not a detail. The producer selects its
# sample with `grep -aE '<tier pattern>' | head -n N`, so a fixture whose second line does not
# match the tier is simply NOT IN THE SAMPLE -- the assertion then passes because the header was
# never there to leak, not because anything redacted it. The first draft of this fixture had
# exactly that bug: it paired a `panic:` line with a `"level":"info"` row, tier 1 selected only
# the panic line, and G1-2b reported ok against a program with no redaction in it at all.
# The JSON row below therefore carries `runtime error`, which is a tier-1 pattern -- and is a
# shape zot really produces, since a zerolog row can carry a runtime-error string in a field.
MIXED_BLOB="${PANIC_LINE}
{\"level\":\"info\",\"message\":\"HTTP API\",\"headers\":{\"X-Secret\":[\"UNANTICIPATED-VALUE\"]},\"error\":\"runtime error\"}"
# Row 2c — the same property, all-JSON multi-line. BOTH lines are level:error so BOTH are
# selected by tier 2; a mixed-tier pair would reintroduce the vacuity described above.
ALLJSON_BLOB="${JSON_COOKIE}
{\"level\":\"error\",\"message\":\"HTTP API\",\"headers\":{\"X-Secret\":[\"UNANTICIPATED-VALUE\"]}}"
# Tier-2: a benign level:error line with NO headers object. Must pass through unredacted.
TIER2_BENIGN='{"level":"error","message":"PatchBlobUpload i/o timeout","caller":"zotregistry.dev/x.go:1"}'
# Tier-4: nothing matches tiers 1-3, so the fallback tail fires. This is the ~100%-of-exposure,
# ~0%-of-value tier.
TIER4_HEADERS='{"level":"info","message":"HTTP API","headers":{"Cookie":["session=TIER4-SECRET"]},"clientIP":"10.0.1.9"}'
# Row 4: a NON-OBJECT headers value. redact()'s jq program errors ("nonobj headers") -> RC=1,
# which must degrade the FIELD without dropping the ROW.
JSON_NONOBJ='{"level":"error","message":"boom","headers":"NOT-AN-OBJECT-RC1-TRIGGER"}'

# --- Fixture non-vacuity control ------------------------------------------------------------
# Asserts the multi-line fixtures survive the producer's OWN tier selection. Without this, a
# fixture whose lines straddle two tiers silently shrinks to one line and every downstream
# "the header was masked" assertion passes because the header was never sampled. This control
# is the reason G1-2b/G1-2c mean anything.
# DERIVED FROM THE SUT, not copied. An earlier revision hardcoded the producer's tier regexes
# here, which made the control a shadow re-implementation: it validated the fixture against the
# TEST's model of tier selection while the producer is what decides. Measured — dropping
# `|runtime error` from the producer's tier-1 grep alone left this suite 29/29 green with the
# needle no longer in the sample at all, so G1-2b passed because nothing was there rather than
# because anything masked it. Extracting the pattern from $RAW makes producer drift red it.
_tier_re() { sed -n "s/.*grep -a$2E '\([^']*\)'.*/\1/p" "$RAW" | sed -n "$1p"; }
TIER1_RE="$(_tier_re 1 '')"
TIER2_RE="$(_tier_re 2 '')"
assert "T1 tier-1 selector was extracted from the producer" "[[ -n '$TIER1_RE' ]]"
assert "T1 tier-2 selector was extracted from the producer" "[[ -n '$TIER2_RE' ]]"
tier1_of() { grep -aE "$TIER1_RE" <<<"$1" | head -n 4; }
tier2_of() { grep -aE "$TIER2_RE" <<<"$1" | head -n 3; }
assert "G1-fixture MIXED_BLOB is >1 line AFTER tier-1 selection" \
  "[[ \$(tier1_of \"\$MIXED_BLOB\" | wc -l) -ge 2 ]]"
assert "G1-fixture MIXED_BLOB still carries the needle after tier-1 selection" \
  "tier1_of \"\$MIXED_BLOB\" | grep -q UNANTICIPATED-VALUE"
assert "G1-fixture ALLJSON_BLOB is >1 line AFTER tier-2 selection" \
  "[[ \$(tier2_of \"\$ALLJSON_BLOB\" | wc -l) -ge 2 ]]"
assert "G1-fixture ALLJSON_BLOB still carries the needle after tier-2 selection" \
  "tier2_of \"\$ALLJSON_BLOB\" | grep -q UNANTICIPATED-VALUE"

echo "=== Guard 1 — producer-side redaction of the diagnostic sample (#7500) ==="

# --- Row 2: the ALLOWLIST property — an unanticipated header name is masked ----------------
# A Cookie fixture CANNOT discriminate here: Cookie is on the denylist, so a denylist-only
# implementation passes it. That is the defect this plan already made once, caught at review.
# TIER-2 shaped, deliberately. The earlier fixture was `"level":"info"`, so it matched no
# tier 1-3, fell to tier 4, and was withheld by the TIER GATE -- the row passed against a
# program with no redaction in it, measuring what G1-6 already measures.
JSON_XSECRET_T2='{"level":"error","message":"PatchBlobUpload i/o timeout","headers":{"X-Secret":["UNANTICIPATED-VALUE"],"Content-Type":["application/json"]}}'
assert_emit "G1-2 unanticipated header masked (allowlist, single-line JSON at tier 2)" \
  "$JSON_XSECRET_T2" absent "UNANTICIPATED-VALUE"
assert_emit "G1-2 the same line's ALLOWLISTED content survives (not a blanket drop)" \
  "$JSON_XSECRET_T2" present "PatchBlobUpload"

# --- Row 2b: the SAME fixture as a MIXED multi-line blob -----------------------------------
assert_emit "G1-2b unanticipated header masked in a MIXED multi-line blob (per-line)" \
  "$MIXED_BLOB" absent "UNANTICIPATED-VALUE"

# --- Row 2c: all-JSON multi-line ----------------------------------------------------------
assert_emit "G1-2c unanticipated header masked in an all-JSON multi-line blob" \
  "$ALLJSON_BLOB" absent "UNANTICIPATED-VALUE"
assert_emit "G1-2c denylisted header also masked in the same blob" \
  "$ALLJSON_BLOB" absent "COOKIE-SECRET"

# --- Row 4: RC=1 degrades the FIELD, never drops the ROW -----------------------------------
# RED if the row is dropped, AND RED if the suite asserts only "it still ships" — that passes a
# mutant shipping the raw field. Both halves are asserted.
assert_emit "G1-4 RC=1 still emits the row (primary disk signal survives)" \
  "$JSON_NONOBJ" present "pcent="
assert_emit "G1-4 RC=1 preserves boot_id" "$JSON_NONOBJ" present "boot_id="
assert_emit "G1-4 RC=1 emits the placeholder" "$JSON_NONOBJ" present "REDACTION_FAILED"
assert_emit "G1-4 RC=1 leaves NO residual of the input" \
  "$JSON_NONOBJ" absent "NOT-AN-OBJECT-RC1-TRIGGER"

# --- Row 6: the tier gate — a tier-4 sample must not ship its raw line ----------------------
assert_emit "G1-6 tier-4 raw header line does not ship" "$TIER4_HEADERS" absent "TIER4-SECRET"
# X-Secret is on NEITHER list, so this row discriminates the tier gate from the denylist --
# a Cookie fixture cannot, because the denylist would mask it even with the gate deleted.
assert_emit "G1-6b tier-4 withholds an UNANTICIPATED header too (gate, not denylist)" \
  "$JSON_XSECRET" absent "UNANTICIPATED-VALUE"

# --- Row 7: degrade CLOSED without jq ------------------------------------------------------
# Unspecified degradation here would restore ~100% of the measured exposure while the ADR
# records the gate as removing it. With jq absent the tier-4 sample must become `none`.
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"
for c in docker curl htpasswd df hostname free stat journalctl; do cp "$BIN/$c" "$NOJQ/$c"; done
printf '#!/usr/bin/env bash\nexit 127\n' > "$NOJQ/jq"; chmod +x "$NOJQ"/*
assert_emit "G1-7 tier-4 degrades CLOSED when jq is unavailable" \
  "$TIER4_HEADERS" absent "TIER4-SECRET" PATH="$NOJQ:/usr/bin:/bin"

# --- G1-8: SUPPRESSED is not SILENT (ADR-166) ----------------------------------------------
# When the tier gate yields no extractable `message`, the sample is withheld -- but zot DID
# produce output. Collapsing that to `zot_last_err_src=none` makes the alarm publish "zot
# produced no log output to sample", which is false in exactly this path, on a public issue.
# That is an unmeasured causal claim newly created by the change that exists to remove them.
# The tier tag must distinguish suppressed-by-us from nothing-to-see.
assert_emit "G1-8 a suppressed tier-4 sample is tagged suppressed, not none (flat enum, no colon grammar)" \
  "$TIER4_HEADERS" present "zot_last_err_src=suppressed" PATH="$NOJQ:/usr/bin:/bin"
assert_emit "G1-8 a suppressed sample does NOT claim the tier was none" \
  "$TIER4_HEADERS" absent "zot_last_err_src=none" PATH="$NOJQ:/usr/bin:/bin"

# --- Harness (b), must-PASS: a benign tier-2 line passes through unredacted -----------------
# NOTE the tier. An earlier draft used `gc successfully completed` here, which is a TIER-4
# sample the tier gate suppresses — so the row would have asserted a behaviour this same change
# removes. Caught at plan review; kept as a comment so it is not reintroduced.
assert_emit "G1-b benign tier-2 line survives unredacted" "$TIER2_BENIGN" present "PatchBlobUpload"

# --- Harness (c), must-PASS: a tier-1 panic keeps its header -------------------------------
# NOT byte-identity at the wire: every sample still passes tr/head -c afterwards, so row-level
# byte-identity is unsatisfiable by construction. The claim is that redact() introduces no
# substitution into a credential-free panic.
assert_emit "G1-c tier-1 panic header survives to the emitted row" "$PANIC_LINE" present "panic:"

# --- Structural: ORDER and ARITY, which behaviour alone cannot pin -------------------------
# Anchored on syntax a comment cannot produce (^\s*KEY=, a call shape), never a bare token.
assert "G1-s redact() is defined in the heartbeat block" "grep -qE '^[[:space:]]*redact\(\) \{' '$RAW'"
assert "G1-s CRED_HDRS is defined in the heartbeat block" "grep -qE \"^[[:space:]]*CRED_HDRS='\" '$RAW'"
assert "G1-s HDR_KEEP is defined in the heartbeat block" "grep -qE '^[[:space:]]*HDR_KEEP=' '$RAW'"
# ARITY, and anchored on a name only this feature introduces. The first draft of this line
# grepped for `while IFS=...read`, which matches loops that already existed in this block -- it
# passed before the feature was written, which is the definition of a vacuous guard.
assert "G1-s a per-line loop applies redact() (arity, not just presence)" \
  "grep -qE '^[[:space:]]*redact_sample_lines\(\) \{' '$RAW'"
assert "G1-s the per-line helper is actually CALLED" \
  "grep -qE 'redact_sample_lines[[:space:]]+' '$RAW'"
# -eq, not -ge. The name claims "exactly ONE" and the operator said "at least one", so a
# second competing degrade branch left the suite green -- the single-carrier invariant this
# file and the boot guard both claim to protect was unasserted. Counted on the comment-stripped
# program so the rationale above it cannot inflate the total.
assert "G1-s exactly ONE degrade branch funnels all three RC=1 paths" \
  "[[ \$(grep -cE '^[[:space:]]*ZOT_ERR_RAW=REDACTION_FAILED\$' '$HB') -eq 1 ]]"
# The tier must NOT be overloaded with the redaction outcome: the sentinel in the field is the
# single carrier, and a second one on zot_last_err_src would be two carriers for one fact.
assert "G1-s the degrade path does NOT re-tag the tier" \
  "! grep -qE 'ZOT_ERR_SRC=.*redact_failed' '$RAW'"

# --- Guard 2 (#7960): the delivery-proof field -------------------------------------------------
# err_redact_rev is what the #7960 follow-through probe keys delivery on, so it must be on EVERY
# row and in the TRUSTED region (before the first ` zot_last_err=`, the attacker-influenceable
# free-text tail). The probe's fixtures read the token from this same LINE= assignment.
_LINE_ASSIGN="$(grep -F 'LINE="SOLEUR_ZOT_DISK' "$RAW" | head -1)"
# Bounded on the HEAD with ( |$), not on a trailing space: a trailing space would silently pin
# "some field must follow err_redact_rev", so moving the token to the end of the trusted region
# would red this with a message about the VALUE CLASS rather than about placement.
assert "G2-s exactly ONE SOLEUR_ZOT_DISK LINE= assignment, and it carries err_redact_rev (>=1)" \
  "[[ \$(grep -cF 'LINE=\"SOLEUR_ZOT_DISK' '$RAW') -eq 1 ]] && grep -qE '(^| )err_redact_rev=[1-9][0-9]*( |\$)' <<<\"\$_LINE_ASSIGN\""
# PLACEMENT, asserted separately from the value class: the token is in the trusted head.
assert "G2-t err_redact_rev is in the TRUSTED region (before the first zot_last_err=)" \
  "grep -qE '(^| )err_redact_rev=' <<<\"\${_LINE_ASSIGN%% zot_last_err=*}\""
# Emit-level, on the suppressed (no-jq) path. Asserted on the row's HEAD, not via assert_emit,
# which matches the whole body and so could be satisfied by a token in the free-text tail.
_G2_OUT="$(run_hb "$TIER4_HEADERS" PATH="$NOJQ:/usr/bin:/bin")"
assert "G2-e the POSTed row carries err_redact_rev in its trusted region (suppressed path)" \
  "[[ -n \"\$_G2_OUT\" ]] && grep -qE '(^| )err_redact_rev=[1-9][0-9]*( |$)' <<<\"\${_G2_OUT%% zot_last_err=*}\""
# Must-PASS, non-canonical path: the tier-1 panic sample carries the field too.
assert_emit "G2-p the tier-1 panic row carries err_redact_rev" "$PANIC_LINE" present "err_redact_rev="
# THE FALLBACK PATH had no field assertion at all. `fallback` is the tier the #7960 probe's T and L
# counts key on, so a tier-conditional strip in the producer would blind the probe on exactly the
# rows it grades while G2-s (source text), G2-e (suppressed path) and G2-p (panic path) all stayed
# green. Asserted on the row HEAD, not the whole body.
_G2_FB="$(run_hb "$TIER4_HEADERS")"
assert "G2-f a fallback-tagged row carries err_redact_rev in its trusted region" \
  "[[ -n \"\$_G2_FB\" ]] && grep -qE '(^| )zot_last_err_src=fallback( |\$)' <<<\"\$_G2_FB\" && grep -qE '(^| )err_redact_rev=[1-9][0-9]*( |\$)' <<<\"\${_G2_FB%% zot_last_err=*}\""
# The #7960 probe grades ANY `suppressed` row whose tail is not exactly `none` as a leak -> a public
# FAIL. That is safe only because the producer forces ZOT_LAST_ERR=none while preserving the tag.
# Nothing asserted that invariant, so a producer edit could make the probe accuse a clean host.
assert "G2-n a suppressed row's zot_last_err is exactly none (the probe grades any other tail as a leak)" \
  "grep -qE ' zot_last_err=none[\"}]*\$' <<<\"\$_G2_OUT\""

# ============================================================================================
# (#8386) Guard 2 — the at-rest posture emitter.
#
# PROPERTY. For every fixture shape, the shipped heartbeat POSTs exactly one row whose TRUSTED
# head carries all five posture fields with the value the fixture dictates, exits 0, and keeps
# every value a single space-free token.
#
# THE CEILING (AC-E7) IS DEGRADED, DELIBERATELY AND ON THE RECORD. Phase 0.8 asks for one live
# Better Stack row and the vendor's documented per-message ingest limit; this suite is hermetic
# and holds no Better Stack credential, so the limit could not be established here. Per the
# plan's own instruction, AC-E7 therefore degrades to PRESENCE AND ORDER -- asserted by
# posture_case's `_posture_fields_in_head` on every case -- rather than to an invented number.
# A ceiling picked from nothing is a guard whose number means nothing.
# ============================================================================================
PHASE=posture
echo "=== Guard 2 — at-rest posture of the zot store (#8386) ==="

# The rendered volume alias: ${registry_volume_id} -> 100000003 (the fifth render line above).
EXP_DEVID="scsi-0HC_Volume_100000003"
LSBLK_MAPPER="registry
\`-sdb"
LSBLK_PART="registry
\`-sdb1
  \`-sdb"
LSBLK_FORK="md0
|-sdb
\`-sdc"
LSBLK_RAW="sdb"
CRYPT_LUKS="/dev/mapper/registry is active and is in use.
  type:    LUKS2
  cipher:  aes-xts-plain64
  device:  /dev/sdb
  sector size:  512"
CRYPT_LUKS_PART="/dev/mapper/registry is active and is in use.
  type:    LUKS2
  device:  /dev/sdb1"
CRYPT_LUKS_NODEV="/dev/mapper/registry is active and is in use.
  type:    LUKS2"
CRYPT_PLAIN="/dev/mapper/vgroot-lv is active.
  type:    n/a
  device:  /dev/sdb"

set_byid "$EXP_DEVID:sdb"

# --- fixture DIRECTION: a value that VIOLATES the charset contract -------------------------
# Every other posture fixture sits on the same side of the emitter's charset guards, so all
# three (STORE_LUKS, STORE_BACKING_DEV, STORE_MOUNT_DEVID) were free to delete at full green --
# and they are what stop a space-bearing value from splitting one field into two tokens and
# corrupting the row the probe parses. cryptsetup reports a device: line carrying a space here;
# the emitter must refuse it rather than ship it (#8386 review, test-design seat Finding 3).
posture_case "P-space-in-backing" \
  HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_RC=0 \
  HB_CRYPT_OUT="$(printf 'type:    LUKS2\n  device:  /dev/sd b\n')"
assert_field "P-space-in-backing backing" store_backing_dev "__UNREADABLE__"

# --- E1 healthy: mapper over a LUKS volume on the declared alias ---------------------------
# SUBJECT-PINNED. Without HB_LSBLK_SUBJ/HB_CRYPT_SUBJ the stubs answer the same tree whatever
# device they are asked about, so three mutations of the emitter stayed green: walking a
# hardcoded /dev/sda, asking cryptsetup about a hardcoded name, and -- the dangerous one --
# walking the DECLARED expected alias, which makes store_mount_devid == store_expected_devid by
# construction and renders the probe's devid_mismatch disjunct unfirable on a live host while
# every suite passes. These two pins kill all three (#8386 review, test-design seat R1/R2/R2b).
posture_case "P-healthy" \
  HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_SUBJ="/dev/mapper/registry" HB_CRYPT_SUBJ="registry" \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-healthy src"      store_mount_src      "/dev/mapper/registry"
assert_field "P-healthy backing"  store_backing_dev    "/dev/sdb"
assert_field "P-healthy devid"    store_mount_devid    "$EXP_DEVID"
assert_field "P-healthy expected" store_expected_devid "$EXP_DEVID"
assert_field "P-healthy luks"     store_luks           "yes"
# store_mount_base IS emitted (CTO ruling, #8386 review). It is the only field that makes a
# __NOMATCH__ row auditable: on a partitioned plain mount src and backing_dev are both the
# PARTITION, and nothing else in the row names the DISK the by-id map failed to match -- the
# difference between "failed open onto the root disk" and "attached to some other volume",
# which are opposite remedies. The sibling books the same field as a required audit column.
assert_field "P-healthy base"     store_mount_base     "sdb"

# --- E2 no mount: findmnt rc 1 AND empty output. The __NOMOUNT__ arm is a CONJUNCTION -------
posture_case "P-nomount" HB_FINDMNT_OUT="" HB_FINDMNT_RC=1
assert_field "P-nomount src"     store_mount_src   "__NOMOUNT__"
assert_field "P-nomount luks"    store_luks        "absent"
assert_field "P-nomount devid"   store_mount_devid "n/a"
assert_field "P-nomount backing" store_backing_dev "n/a"

# ... and its COMPLEMENT, both halves, because a conjunction that is never falsified on either
# side is indistinguishable from `[ -z "$out" ]` alone.
posture_case "P-findmnt-timeout" HB_FINDMNT_OUT="" HB_FINDMNT_RC=124
assert_field "P-findmnt-timeout src"  store_mount_src "__UNREADABLE__"
assert_field "P-findmnt-timeout luks" store_luks      "unknown"

posture_case "P-findmnt-rc0-empty" HB_FINDMNT_OUT="" HB_FINDMNT_RC=0
assert_field "P-findmnt-rc0-empty src"  store_mount_src "__UNREADABLE__"
assert_field "P-findmnt-rc0-empty luks" store_luks      "unknown"

posture_case "P-findmnt-rc1-nonempty" HB_FINDMNT_OUT="/dev/sdb" HB_FINDMNT_RC=1
assert_field "P-findmnt-rc1-nonempty src"  store_mount_src "__UNREADABLE__"
assert_field "P-findmnt-rc1-nonempty luks" store_luks      "unknown"

# --- E3 raw ext4 on a plain block device: no mapper, so no LUKS container -------------------
posture_case "P-raw-ext4" HB_FINDMNT_OUT="/dev/sdb" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_RAW" HB_BLKID_MAP="/dev/sdb=ext4"
assert_field "P-raw-ext4 src"     store_mount_src   "/dev/sdb"
assert_field "P-raw-ext4 luks"    store_luks        "no"
assert_field "P-raw-ext4 devid"   store_mount_devid "$EXP_DEVID"
assert_field "P-raw-ext4 backing" store_backing_dev "/dev/sdb"

# --- non-LUKS mapper: cryptsetup answers, and the answer is not a LUKS mapping --------------
posture_case "P-mapper-not-luks" HB_FINDMNT_OUT="/dev/mapper/vgroot-lv" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_PLAIN" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=ext4"
assert_field "P-mapper-not-luks luks" store_luks "no"

# --- THE CASE THAT MAKES THE blkid CONJUNCT LOAD-BEARING ------------------------------------
# cryptsetup exits 0, prints a LUKS `type:` AND a `device:` line -- and blkid on that device
# says ext4. Without this case, deleting `&& blkid ... = crypto_LUKS` leaves every other case
# green, because a cryptsetup exit code says the tool refused, never what the bytes are.
posture_case "P-blkid-disagrees" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=ext4"
assert_field "P-blkid-disagrees luks"    store_luks        "no"
assert_field "P-blkid-disagrees backing" store_backing_dev "/dev/sdb"

# --- cryptsetup rc 4 ("wrong device specified"): blkid discriminates ------------------------
posture_case "P-crypt-rc4-ext4" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="" HB_CRYPT_RC=4 \
  HB_BLKID_MAP="/dev/mapper/registry=ext4"
assert_field "P-crypt-rc4-ext4 luks" store_luks "no"

posture_case "P-crypt-rc4-silent" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="" HB_CRYPT_RC=4 HB_BLKID_MAP=""
assert_field "P-crypt-rc4-silent luks" store_luks "unknown"

# --- every other cryptsetup rc is a REFUSAL, never a plaintext verdict ----------------------
posture_case "P-crypt-rc1" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="" HB_CRYPT_RC=1 \
  HB_BLKID_MAP="/dev/mapper/registry=ext4"
assert_field "P-crypt-rc1 luks" store_luks "unknown"

posture_case "P-crypt-rc127" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="" HB_CRYPT_RC=127 HB_BLKID_MAP=""
assert_field "P-crypt-rc127 luks" store_luks "unknown"
assert_field "P-crypt-rc127 src (the row still ships with the tool absent)" \
  store_mount_src "/dev/mapper/registry"

# --- LUKS `type:` with no `device:` line: a positive verdict has nothing to rest on ----------
posture_case "P-luks-no-device-line" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS_NODEV" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-luks-no-device-line luks"    store_luks        "unknown"
assert_field "P-luks-no-device-line backing" store_backing_dev "__UNREADABLE__"

# --- lsblk unreadable: the base is what the devid pin rests on, so no confident answer -------
posture_case "P-lsblk-rc127" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="" HB_LSBLK_RC=127 HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-lsblk-rc127 devid" store_mount_devid "__UNREADABLE__"
assert_field "P-lsblk-rc127 luks"  store_luks        "unknown"

posture_case "P-lsblk-rc32" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="" HB_LSBLK_RC=32 HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-lsblk-rc32 devid" store_mount_devid "__UNREADABLE__"
assert_field "P-lsblk-rc32 luks"  store_luks        "unknown"

# --- a FORKED inverse tree is a measured multiplicity, never a confident pin -----------------
set_byid "$EXP_DEVID:sdb" "scsi-0HC_Volume_100000004:sdc"
posture_case "P-forked-tree" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_FORK" HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-forked-tree devid" store_mount_devid "__AMBIGUOUS__"
assert_field "P-forked-tree luks"  store_luks        "unknown"

# --- TWO aliases for ONE base: the reverse map COUNTS, it does not take the first match ------
set_byid "$EXP_DEVID:sdb" "scsi-0HC_Volume_100000009:sdb"
posture_case "P-two-aliases" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-two-aliases devid" store_mount_devid "__AMBIGUOUS__"

# --- ZERO aliases: attached to something that is not a Hetzner volume -----------------------
set_byid
posture_case "P-zero-aliases" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-zero-aliases devid" store_mount_devid "__NOMATCH__"
# The __NOMATCH__ path is exactly where store_backing_dev earns its place: it is the only field
# naming the device the verdict was taken against.
assert_field "P-zero-aliases backing" store_backing_dev "/dev/sdb"

set_byid "$EXP_DEVID:sdb"

# --- E6 PARTITIONED CHAIN: the signature is on sdb1 while the base disk is sdb ---------------
# blkid answers for /dev/sdb1 and NOTHING for /dev/sdb, so a blkid read pointed at
# /dev/$STORE_MOUNT_BASE reads `unknown` on a correctly encrypted store.
posture_case "P-partitioned" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_PART" HB_CRYPT_OUT="$CRYPT_LUKS_PART" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb1=crypto_LUKS"
assert_field "P-partitioned luks"    store_luks        "yes"
assert_field "P-partitioned backing" store_backing_dev "/dev/sdb1"
assert_field "P-partitioned devid"   store_mount_devid "$EXP_DEVID"

# --- a MAPPER NAMED SOMETHING ELSE still measures yes: the emitter reads the DEVICE ----------
# Pinned so the emitter/probe seam is explicit -- the probe is what requires the name to be
# `registry` (V4's store_mount_src disjunct); the emitter never encodes that expectation.
CRYPT_LUKS_OTHER="/dev/mapper/zotstore is active and is in use.
  type:    LUKS2
  device:  /dev/sdb"
posture_case "P-other-mapper-name" HB_FINDMNT_OUT="/dev/mapper/zotstore" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS_OTHER" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-other-mapper-name luks" store_luks      "yes"
assert_field "P-other-mapper-name src"  store_mount_src "/dev/mapper/zotstore"

# --- a BRACKETED bind-mount source is a shape this emitter does not decode -------------------
posture_case "P-bracketed-src" HB_FINDMNT_OUT="/dev/sdb[/zot]" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_RAW" HB_BLKID_MAP="/dev/sdb=ext4"
assert_field "P-bracketed-src src"  store_mount_src "__UNREADABLE__"
assert_field "P-bracketed-src luks" store_luks      "unknown"

# --- E4 every measurement tool absent (rc 127): sentinels, ONE row, exit 0 -------------------
posture_case "P-all-tools-absent" HB_FINDMNT_OUT="" HB_FINDMNT_RC=127 \
  HB_LSBLK_OUT="" HB_LSBLK_RC=127 HB_CRYPT_OUT="" HB_CRYPT_RC=127 HB_BLKID_MAP=""
assert_field "P-all-tools-absent src"     store_mount_src   "__UNREADABLE__"
assert_field "P-all-tools-absent luks"    store_luks        "unknown"
# The source read itself failed, so NOTHING downstream was measured. All three carry the
# sentinel, never the `n/a` initialiser: `n/a` passes the charset guard unchanged, so shipping
# it here would be indistinguishable on the wire from a measurement (#8386 review).
assert_field "P-all-tools-absent base"    store_mount_base  "__UNREADABLE__"
assert_field "P-all-tools-absent devid"   store_mount_devid "__UNREADABLE__"
assert_field "P-all-tools-absent backing" store_backing_dev "__UNREADABLE__"

# --- E5 SBIN-ONLY: the four tools are reachable ONLY through the shipped PATH append ---------
# cron's own PATH is /usr/bin:/bin and carries neither cryptsetup nor blkid, so without the
# append every row on the live host would read store_luks=unknown forever -- an R2 FAIL that
# costs a second host replace behind a dispatcher that is currently dead.
CORE="$TMP/core"; mkdir -p "$CORE"
for _c in docker curl htpasswd df hostname free stat journalctl; do cp "$BIN/$_c" "$CORE/$_c"; done
for _c in awk bash basename cat cut date dirname env grep head id jq mktemp printf readlink \
          rm sed sh sleep sort tail timeout tr uniq wc; do
  _cp="$(command -v "$_c" 2>/dev/null || true)"
  [ -n "$_cp" ] && ln -sf "$_cp" "$CORE/$_c"
done
assert "P-sbin-only | the CORE dir carries none of the four measurement tools (non-vacuity)" \
  "[ ! -e '$CORE/findmnt' ] && [ ! -e '$CORE/lsblk' ] && [ ! -e '$CORE/cryptsetup' ] && [ ! -e '$CORE/blkid' ]"
assert "P-sbin-only | the four tools ARE in the seamed sbin dir the append points at" \
  "[ -x '$BIN/sbin/findmnt' ] && [ -x '$BIN/sbin/lsblk' ] && [ -x '$BIN/sbin/cryptsetup' ] && [ -x '$BIN/sbin/blkid' ]"
posture_case "P-sbin-only" PATH="$CORE" \
  HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-sbin-only luks"  store_luks        "yes"
assert_field "P-sbin-only devid" store_mount_devid "$EXP_DEVID"

# --- M2 must-PASS: the tail is free text by contract, and a 10-digit alias is still an alias --
# (a) a 3 KB zot panic sample: only the HEAD's shape is asserted, never the tail's.
POSTURE_FIXTURE="panic: $(head -c 3000 /dev/zero | tr '\0' 'x')"
posture_case "P-M2-big-tail" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-M2-big-tail luks" store_luks "yes"
POSTURE_FIXTURE=""
# (b) a TEN-digit volume id: the reverse map reads the alias it finds, it does not validate the
# id's length, and the mismatch against store_expected_devid is the PROBE's verdict to take.
set_byid "scsi-0HC_Volume_1000000034:sdb"
posture_case "P-M2-ten-digit-alias" HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
  HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
  HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
assert_field "P-M2-ten-digit-alias devid"    store_mount_devid    "scsi-0HC_Volume_1000000034"
assert_field "P-M2-ten-digit-alias expected" store_expected_devid "$EXP_DEVID"
assert_field "P-M2-ten-digit-alias luks"     store_luks           "yes"
set_byid "$EXP_DEVID:sdb"

# --- (#8408 (b)) luks_open_arm: which arm registry-luks-open.sh last took this boot ---------
# The reopen script is fail-open on every arm; this trusted-head field is the only off-box
# record of which one fired. Closed vocabulary; absent file = none; anything else = __UNREADABLE__.
LOA="$TMP/run-soleur-registry/luks-open.arm"
_loa_case() { # <label> <file-content|__ABSENT__> <expected>
  rm -f "$LOA"
  [ "$2" = __ABSENT__ ] || printf '%s\n' "$2" > "$LOA"
  posture_case "P-loa-$1" \
    HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
    HB_LSBLK_SUBJ="/dev/mapper/registry" HB_CRYPT_SUBJ="registry" \
    HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
    HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
  assert_field "P-loa-$1 luks_open_arm" luks_open_arm "$3"
}
_loa_case absent __ABSENT__ none
_loa_case opened opened opened
_loa_case already already_open already_open
_loa_case open-failed open_failed open_failed
_loa_case garbage 'opened; rm -rf /' __UNREADABLE__
rm -f "$LOA"
assert "P-loa luks_open_arm precedes ' zot_last_err=' in the LINE= assembly" \
  "grep -qE 'store_luks=[^ ]+ luks_open_arm=' <<<\"\$(grep -F 'LINE=\"SOLEUR_ZOT_DISK' '$RAW' | head -1 | sed 's/ zot_last_err=.*//')\""

# --- (#8408 (c)) store_escrow: the daily escrow re-test's verdict, READ (never run) here ---------
ESC="$TMP/var-lib-soleur-registry/escrow.state"
_esc_case() { # <label> <file-content|__ABSENT__> <expected-token> <expected-age: exact|pos>
  rm -f "$ESC"
  [ "$2" = __ABSENT__ ] || printf '%s\n' "$2" > "$ESC"
  posture_case "P-esc-$1" \
    HB_FINDMNT_OUT="/dev/mapper/registry" HB_FINDMNT_RC=0 \
    HB_LSBLK_SUBJ="/dev/mapper/registry" HB_CRYPT_SUBJ="registry" \
    HB_LSBLK_OUT="$LSBLK_MAPPER" HB_CRYPT_OUT="$CRYPT_LUKS" HB_CRYPT_RC=0 \
    HB_BLKID_MAP="/dev/sdb=crypto_LUKS"
  assert_field "P-esc-$1 store_escrow" store_escrow "$3"
  if [ "$4" = pos ]; then
    assert "P-esc-$1 store_escrow_age_s is a non-negative integer" \
      "[[ \"\$(_field_value store_escrow_age_s)\" =~ ^[0-9]+\$ ]]"
  else
    assert_field "P-esc-$1 store_escrow_age_s" store_escrow_age_s "$4"
  fi
}
_now="$(date +%s)"
_esc_case absent __ABSENT__ none -1
_esc_case fresh-ok "result=ok at=$((_now - 60))" ok pos
_esc_case fail-pass "result=fail_passphrase at=$((_now - 60))" fail_passphrase pos
_esc_case fail-header "result=fail_header at=$((_now - 60))" fail_header pos
_esc_case fail-key "result=fail_key_absent at=$((_now - 60))" fail_key_absent pos
_esc_case indet "result=indeterminate at=$((_now - 60))" indeterminate pos
# 26 h plus one minute: a dead escrow job must surface as stale within a day, not hide as ok.
_esc_case stale-ok "result=ok at=$((_now - 93660))" stale pos
_esc_case three-days "result=ok at=$((_now - 259200))" stale pos
_esc_case offvocab "result=okay at=$((_now - 60))" __UNREADABLE__ pos
_esc_case bad-epoch "result=ok at=yesterday" __UNREADABLE__ -1
_esc_case future "result=ok at=$((_now + 3600))" ok -1
rm -f "$ESC"
_ESC_LINE_HEAD="$(grep -F 'LINE="SOLEUR_ZOT_DISK' "$RAW" | head -1 | sed 's/ zot_last_err=.*//')"
assert "P-esc store_escrow and store_escrow_age_s precede ' zot_last_err=' in the LINE= assembly" \
  "grep -qE 'store_escrow=[^ ]+ store_escrow_age_s=[^ ]+ host=' <<<\"\$_ESC_LINE_HEAD\""
assert "P-esc the heartbeat never RUNS the escrow (no luksOpen / test-passphrase in its body)" \
  "! grep -qE 'luksOpen|test-passphrase' '$HB'"

# --- Structural: the order pin, on the source text rather than one rendered row --------------
_P_LINE="$(grep -F 'LINE="SOLEUR_ZOT_DISK' "$RAW" | head -1)"
assert "P-s all five posture fields precede ' zot_last_err=' in the LINE= assembly" \
  "grep -qE 'store_mount_src=.*store_backing_dev=.*store_mount_devid=.*store_expected_devid=.*store_luks=' <<<\"\${_P_LINE%% zot_last_err=*}\""
assert "P-s store_expected_devid is the SINGLE-dollar templatefile variable, not a shell one" \
  "grep -qF 'store_expected_devid=scsi-0HC_Volume_\${registry_volume_id}' <<<\"\$_P_LINE\""

PHASE=redact

# --- Reject controls for the VERDICT-OWNING wrappers ---------------------------------------
# USED_* proves the wrappers RAN and EXPECTED_MIN proves they ran N times; neither can see a
# wrapper that always takes the pass branch. Measured: an `assert()` rewritten to `CASES++; pass`
# and an `assert_emit` with both verdict branches inverted each left this suite fully green. Drive
# each wrapper once with an input that MUST fail, require FAIL to have moved, then unwind the
# counters, the transcript and the case tally so the floor stays exact. printf/exit, never through
# the wrapper under test.
_c_p0=$PASS; _c_f0=$FAIL; _c_c0=$CASES; _c_v0="$VERDICTS"
_c_cr0=$CASES_REDACT; _c_cp0=$CASES_POSTURE
assert "reject control for assert() (this FAIL line is EXPECTED)" "false"
assert_emit "reject control for assert_emit() (this FAIL line is EXPECTED)" "$TIER2_BENIGN" absent "pcent="
# assert_field is EXACT-TOKEN where assert_emit is substring-only, so it needs its own control:
# `store_luks=yes` is a substring of `store_luks=yesX`, and every posture expectation written
# through assert_emit would have been satisfiable by a longer wrong value.
assert_field "reject control for assert_field() (this FAIL line is EXPECTED)" store_luks "yesX"
# --- reject controls for the two PREDICATE helpers -------------------------------------------
# Neither is reachable through assert()/assert_emit()/assert_field()'s controls above: they OWN
# the verdict for the two assertions posture_case emits, so a `return 0` in either silently
# unbacked ~64 posture assertions. Drive each with an input that MUST fail.
_HEAD_SAVE="$HEAD"
HEAD='SOLEUR_ZOT_DISK store_mount_src=/dev/mapper/registry a="b" store_luks=yes'
assert "reject control for _head_tokens_ok() (this FAIL line is EXPECTED)" "_head_tokens_ok"
HEAD='SOLEUR_ZOT_DISK store_luks=yes'
assert "reject control for _posture_fields_in_head() (this FAIL line is EXPECTED)" "_posture_fields_in_head"
HEAD="$_HEAD_SAVE"
if [[ "$FAIL" -ne $((_c_f0 + 5)) ]]; then
  printf '\n[FATAL] harness: a verdict wrapper did not register a failure for an input that MUST fail (FAIL %s -> %s) -- every assertion above is unbacked.\n' "$_c_f0" "$FAIL" >&2
  exit 1
fi
PASS=$_c_p0; FAIL=$_c_f0; CASES=$_c_c0; VERDICTS="$_c_v0"
CASES_REDACT=$_c_cr0; CASES_POSTURE=$_c_cp0

# --- Row 8 / harness (a): the guard's own dispatch ------------------------------------------
for _w in assert assert_emit assert_field; do
  _u="USED_${_w}"
  if [[ "${!_u}" -lt 1 ]]; then
    printf '\n[FATAL] harness: %s was never dispatched — a wrapper that does not run asserts nothing.\n' "$_w" >&2
    printf 'cases=%s pass=%s fail=%s\n' "$CASES" "$PASS" "$FAIL"
    exit 1
  fi
done

_v_pass="${VERDICTS//F/}"; _v_fail="${VERDICTS//P/}"
if [[ "${#_v_pass}" -ne "$PASS" || "${#_v_fail}" -ne "$FAIL" ]]; then
  printf '\n[FATAL] harness: verdict transcript disagrees with the counters.\n' >&2
  exit 1
fi

# Anti-vacuity floor — printf + exit, never through fail() (ADR-193).
# ONE FLOOR PER PROPERTY. A single total would let every posture case be deleted while the
# redaction cases alone still cleared it, which is the vacuity these floors exist to refuse.
CASES_REDACT_MIN=39
CASES_POSTURE_MIN=269
if [[ "$CASES_REDACT" -lt "$CASES_REDACT_MIN" ]]; then
  printf '\n[FATAL] cardinality (#7500 redaction): only %s cases ran (expected >= %s).\n' \
    "$CASES_REDACT" "$CASES_REDACT_MIN" >&2
  exit 1
fi
if [[ "$CASES_POSTURE" -lt "$CASES_POSTURE_MIN" ]]; then
  printf '\n[FATAL] cardinality (#8386 at-rest posture): only %s cases ran (expected >= %s).\n' \
    "$CASES_POSTURE" "$CASES_POSTURE_MIN" >&2
  exit 1
fi
if [[ $((CASES_REDACT + CASES_POSTURE)) -ne "$CASES" ]]; then
  printf '\n[FATAL] conservation: the per-property counters (%s + %s) do not sum to cases (%s).\n' \
    "$CASES_REDACT" "$CASES_POSTURE" "$CASES" >&2
  exit 1
fi
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] conservation: pass+fail (%s) != cases (%s).\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi

printf '\ncases=%s (redaction=%s posture=%s) pass=%s fail=%s\n' \
  "$CASES" "$CASES_REDACT" "$CASES_POSTURE" "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo "RESULT: FAIL ($FAIL/$CASES assertions failed)" >&2
  exit 1
fi
echo "RESULT: PASS ($PASS/$CASES assertions)"
