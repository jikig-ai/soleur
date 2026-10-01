#!/usr/bin/env bash
# Exit-code + branch harness for registry-luks-live-8386.sh (#8386 delivery/posture watch).
#
# WHY THIS FILE EXISTS. The probe it guards decides, unattended and daily, whether to post a
# PUBLIC comment saying the container registry's volume is mounted unencrypted, and whether to
# tell a human the evidence is complete enough to flip a security ledger row. It runs for the
# first time on the one window that matters: the sweep after a registry-host replace that nobody
# can rehearse, because delivery IS the replace (ADR-096) and the replace is behind a workflow
# that is currently dead. These fixtures are the only rehearsal there will be.
#
# WHAT THE 7500 HARNESS'S HEADER RECORDS, restated because this suite is built to avoid it. Its
# first revision asserted EXIT CODES ONLY against a probe with six distinct `exit 2` sites, so
# four of six cases collapsed onto one integer. Measured there: deleting the no-boot_id guard —
# the named subject of one case — left the suite 6/0 green; deleting the trusted-region tail cut
# left it 6/0 green WHILE THE FORGE SUCCEEDED; replacing `got="$(run_probe …)"` with `got="$want"`
# left it 6/0 green with the probe never executed. This probe has NINE `exit 2` sites, EIGHT
# `exit 3` sites and TEN `exit 5` sites, so the same collapse is available here at three times
# the scale. Every case therefore pins a BRANCH MARKER as well as the code, and the floor on
# DISTINCT markers per exit code is DERIVED FROM THE SHIPPED PROBE rather than hand-counted — a
# hand-counted floor is a number that stops being true the moment a branch is added.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): every uuid, volume alias, device
# path and credential-shaped string below is fabricated. The envelope shape mirrors
# betterstack-query.sh's documented double-encoded `raw` column, and the field order mirrors the
# producer's `LINE=` emitter.
#
# THE FIELD NAMES ARE READ FROM THE PROBE, NOT RESTATED. The emitter contract is five field
# names; if the probe renames one, every fixture built from the old name would grade a field the
# probe no longer reads and this suite would report agreement it never checked. They are read
# from the probe's own constant block below, so a rename reddens this file before any case runs.
# The producer side of that seam (the emitter actually emitting those names) is pinned by
# registry-boot-guard.test.sh's field loop, not here — this file's subject is the CONSUMER.
#
# THE WALL CLOCK IS NEUTRALISED, deliberately. The probe's staleness escalation reads `earliest=`
# from its own tracker directive, so a suite that left the shipped date in place would grade
# differently in November than in September. run_probe ALWAYS rewrites that date in the copy it
# runs, and refuses to run if the rewrite did not land. Row ages are generated relative to `now`
# for the same reason.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_NAME="registry-luks-live-8386.sh"
PROBE_SRC="$HERE/$PROBE_NAME"
PARSE_LIB_SRC="$HERE/../lib/zot-telemetry-parse.sh"
[[ -f "$PROBE_SRC" ]] || { echo "FATAL: probe not found at $PROBE_SRC" >&2; exit 1; }
[[ -f "$PARSE_LIB_SRC" ]] || { echo "FATAL: parse lib not found at $PARSE_LIB_SRC" >&2; exit 1; }

# ── the emitter contract, read from the probe ─────────────────────────────────────────────────
probe_const() { # <NAME> -> the value of a top-level `NAME="value"` assignment in the probe
  grep -oE "^$1=\"[^\"]+\"" "$PROBE_SRC" | head -1 | cut -d'"' -f2
}
F_SRC="$(probe_const F_SRC)"
F_BACKING="$(probe_const F_BACKING)"
F_DEVID="$(probe_const F_DEVID)"
F_EXPECTED="$(probe_const F_EXPECTED)"
F_LUKS="$(probe_const F_LUKS)"
EXPECTED_SRC="$(probe_const EXPECTED_SRC)"
EXPECTED_HOST="$(probe_const EXPECTED_HOST)"
for _c in F_SRC F_BACKING F_DEVID F_EXPECTED F_LUKS EXPECTED_SRC EXPECTED_HOST; do
  if [[ -z "${!_c}" ]]; then
    printf 'FATAL: could not read %s from %s — every fixture below would be built from a field name the probe does not read.\n' "$_c" "$PROBE_SRC" >&2
    exit 1
  fi
done

# ── fabricated identities ─────────────────────────────────────────────────────────────────────
NEWBOOT="7d41c0b2-9e53-4a17-b8f6-21c5de0374aa"
OLDBOOT="2f90a6e4-13bd-4c88-9a02-6b7e4f15c3d1"
ALT1="5a1e7c93-44f0-4b26-8d71-0e9c2af6b538"
ALT2="c6b80d15-7a2e-4f39-91cd-38f04e7b6a22"
ALT3="91fe23a7-6c0b-4d85-ae14-72b9c5d03e6f"
ALT4="48c2d90b-5e71-4a63-bf28-19d7e06c4a53"
ALT5="b3079fa6-2d48-4e91-8c07-5fa1e2b94d60"
ALT6="0e5c8b71-9f34-42ad-b16e-7c308da5f294"
ALT7="a72d4e08-31c6-4b5f-9e02-64d18f7c0b35"
ALT8="6c1b9034-8e27-4f0a-b573-2d9e05c14f78"
ALT9="d40a71e5-0b93-4c27-8f61-35ae9d206b4c"
ALT10="1b6f39c8-7d04-4e52-a9b3-08c75fe21d96"
ALT11="e29470bd-5a18-4c63-90f7-4b1de803c675"
ALT12="35d8c1a9-6f72-4b04-8e19-a70c62d5f483"
ALT13="7fa1e46c-08d3-4295-b7e0-51c96da2704b"
ALT14="c80b53d7-42e9-4a16-8fb5-6d30791ec2a8"
ALT15="9d47f0b1-6e25-43ca-8071-3b52ce80af69"
ALT16="24e9b7c0-1f58-4d36-ab92-6c05f37e8d41"
ALT17="f16c805a-93d2-4e78-b405-2a71d69c3f50"
ALT18="58b3e970-c41d-4a62-8f19-e07b25d3a684"
VOL="scsi-0HC_Volume_100000003"
VOL_OTHER="scsi-0HC_Volume_100000009"
BACKING="/dev/sdb1"
# The credential-shaped token the query stub prints on BOTH streams in the rc-7 case. Fabricated;
# it exists so the probe's combined output can be searched for it.
FAKE_CRED="dp.ct.NOT_A_REAL_TOKEN_8386_synthetic"
CANARY="CANARY8386"

# ── clock ─────────────────────────────────────────────────────────────────────────────────────
iso()   { date -u -d "$1" '+%Y-%m-%dT%H:%M:%SZ'; }
rowdt() { date -u -d "$1" '+%Y-%m-%d %H:%M:%S'; }
DEFAULT_EARLIEST="$(iso '-5 days')"
FRESH_EARLIEST="$(iso '-1 hour')"
STALE_EARLIEST="$(iso '-40 days')"
DT_A="$(rowdt '-25 minutes')"
DT_B="$(rowdt '-20 minutes')"
DT_C="$(rowdt '-15 minutes')"
DT_D="$(rowdt '-10 minutes')"
DT_OLD="$(rowdt '-23 hours')"
DT_SILENT="$(rowdt '-2 hours')"

fails=0
passes=0
# Incremented at the CALL SITE, never inside pass()/fail(). Verified insufficient on its own —
# see the positive control at the bottom, which drives both helpers and both counters.
cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d -t regluks8386.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
case "$WORK" in
  /*) : ;;
  *)  echo "FATAL: scratch root is not absolute; refusing" >&2; exit 1 ;;
esac
trap 'rm -rf -- "$WORK"' EXIT

# Every asserted marker, and the verdict token inside it, accumulated per case. The floor at the
# bottom is computed against the SHIPPED PROBE's exit-site counts.
MARKER_LOG="$WORK/markers.tsv"
: > "$MARKER_LOG"

# ── fixture builders ──────────────────────────────────────────────────────────────────────────
# PRODUCTION SHAPE. betterstack-query.sh's header documents `raw` as DOUBLE-encoded, and the
# probe's envelope anchor greps the literal `"raw":"{\"message\":\"SOLEUR_ZOT_DISK `. A flat
# `{"raw":"SOLEUR_ZOT_DISK …"}` fixture cannot exercise the anchor at all and would pin a
# single-hop decoder the dependency's own contract contradicts.
posture() { # <luks> <src> <devid> <expected> <backing>
  printf '%s=%s %s=%s %s=%s %s=%s %s=%s ' \
    "$F_SRC" "$2" "$F_BACKING" "$5" "$F_DEVID" "$3" "$F_EXPECTED" "$4" "$F_LUKS" "$1"
}
good_posture() { posture yes "$EXPECTED_SRC" "$VOL" "$VOL" "$BACKING"; }

rowh() { # <dt> <host> <boot> <posture-block or ""> <tail>
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 zot_last_err_src=fallback err_redact_rev=1 boot_id=%s %shost=%s zot_last_err=%s\\"}"}\n' \
    "$1" "$3" "$4" "$2" "$5"
}
row()     { rowh "$1" "$EXPECTED_HOST" "$2" "$3" "level:info served in 3ms $CANARY"; }
rowtail() { rowh "$1" "$EXPECTED_HOST" "$2" "$3" "$4 $CANARY"; }
rowgood() { row "$1" "$2" "$(good_posture)"; }
rowbare() { row "$1" "$2" ""; }
rowluks() { row "$1" "$2" "$(posture "$3" "$EXPECTED_SRC" "$VOL" "$VOL" "$BACKING")"; }
# A row that merely QUOTES the marker — a Vector-shipped journald envelope, the 2026-07-15
# contamination shape the parse library's header records. It carries a GOOD posture block and a
# fabricated boot, so dropping the envelope anchor would let it select the boot and supply the
# evidence. Only the anchor keeps it out.
foreign() { # <dt> <boot>
  printf '{"dt":"%s","raw":"{\\"PRIORITY\\":\\"6\\",\\"_HOSTNAME\\":\\"soleur-web-1\\",\\"message\\":\\"[zot] SOLEUR_ZOT_DISK egress FAILED: boot_id=%s %shost=%s zot_last_err=none %s\\"}"}\n' \
    "$1" "$2" "$(good_posture)" "$EXPECTED_HOST" "$CANARY"
}

# ── the runner ────────────────────────────────────────────────────────────────────────────────
# Per-case seams, all read with a default so a case that sets none gets the canonical world:
#   CASE_EARLIEST   the tracker-directive date written into the copy (default: 5 days ago)
#   CASE_SWEEPER_EARLIEST  value of SOLEUR_FT_EARLIEST, the sweeper's forwarded clock (default:
#                   UNSET, i.e. the probe falls back to the header copy above)
#   CASE_PROBE_SED  a sed -E expression applied to the copy, asserted to have LANDED
#   CASE_LEDGER     available | other | malformed | absent   (default: other)
#   CASE_APPLY      byte size of the stub apply workflow     (default: 1000, i.e. UNDER)
#   CASE_NO_QUERY   1 -> no betterstack-query.sh in the stub root
#   CASE_NO_LIB     1 -> no scripts/lib/zot-telemetry-parse.sh in the stub root
#   CASE_UNSET      the name of one BETTERSTACK_QUERY_* to pass through empty
#   STUB_RC         the query stub's exit code (7 also prints the credential-shaped token)
run_probe() { # <fixture-file> -> echoes exit code; combined output in $WORK/out
  local fixture="$1" root="$WORK/root" probe
  probe="$root/scripts/followthroughs/$PROBE_NAME"
  rm -rf "$root"
  mkdir -p "$root/scripts/followthroughs" "$root/scripts/lib" "$root/.github/workflows"
  cp "$PROBE_SRC" "$probe"

  # THE CLOCK SEAM. Always applied, and always verified to have landed: a sed that silently
  # matched nothing would leave every staleness case grading the shipped date, which is exactly
  # the vacuous-green shape this file exists to refuse.
  sed -E -i "s/earliest=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/earliest=${CASE_EARLIEST:-$DEFAULT_EARLIEST}/" "$probe"
  if cmp -s "$PROBE_SRC" "$probe"; then
    printf 'HARNESS FATAL: the earliest= rewrite did not change the probe copy.\n' > "$WORK/out"
    echo 199; return
  fi
  if [[ -n "${CASE_PROBE_SED:-}" ]]; then
    cp "$probe" "$WORK/pre-sed"
    sed -E -i "$CASE_PROBE_SED" "$probe"
    if cmp -s "$WORK/pre-sed" "$probe"; then
      printf 'HARNESS FATAL: CASE_PROBE_SED matched nothing: %s\n' "$CASE_PROBE_SED" > "$WORK/out"
      echo 199; return
    fi
  fi

  [[ "${CASE_NO_LIB:-0}" == "1" ]] || cp "$PARSE_LIB_SRC" "$root/scripts/lib/"

  case "${CASE_LEDGER:-other}" in
    available) printf '{"stores":[{"store":"hcloud_volume.registry","at_rest":{"live_verification":"available"}}]}\n' > "$root/scripts/encryption-posture-ledger.json" ;;
    other)     printf '{"stores":[{"store":"hcloud_volume.registry","at_rest":{"live_verification":"unavailable: the emitter exists in code but has not been observed on a boot"}}]}\n' > "$root/scripts/encryption-posture-ledger.json" ;;
    malformed) printf '{"stores":[{"store": not-json\n' > "$root/scripts/encryption-posture-ledger.json" ;;
    absent)    : ;;
  esac

  head -c "${CASE_APPLY:-1000}" /dev/zero | tr '\0' 'x' > "$root/.github/workflows/apply-web-platform-infra.yml"

  if [[ "${CASE_NO_QUERY:-0}" != "1" ]]; then
    cat > "$root/scripts/betterstack-query.sh" <<STUB
#!/usr/bin/env bash
argv="\$*"
# Assert the probe's query CONSTRUCTION, by value where a value is load-bearing. Presence-only
# assertions let \`--limit 1\` and a hardcoded \`--since 1h\` both pass silently.
case "\$argv" in
  *"--since 24h"*) : ;;
  *) echo "STUB: expected --since 24h, got: \$argv" >&2; exit 64 ;;
esac
case "\$argv" in
  *"--grep SOLEUR_ZOT_DISK"*) : ;;
  *) echo "STUB: probe dropped the SOLEUR_ZOT_DISK grep (argv: \$argv)" >&2; exit 64 ;;
esac
lim="\$(printf '%s\n' "\$argv" | sed -n 's/.*--limit \([0-9]*\).*/\1/p')"
if [[ -z "\$lim" || "\$lim" -lt 1000 ]]; then
  echo "STUB: probe must pass an explicit --limit >= 1000, got '\$lim' (argv: \$argv)" >&2; exit 64
fi
if [[ "\${STUB_RC:-0}" != "0" ]]; then
  # A tool that dies mid-auth can print the credential on EITHER stream. Both are covered.
  echo "betterstack-query: auth failed for user=stub password=$FAKE_CRED" >&2
  echo "curl: (22) https://stub/?token=$FAKE_CRED"
  exit "\${STUB_RC}"
fi
cat "$fixture"
STUB
    chmod +x "$root/scripts/betterstack-query.sh"
  fi

  # THE SWEEPER'S CLOCK CHANNEL. Unset by default, so an ordinary case grades the header copy
  # exactly as a standalone run does; `+x` (not `:-`) so a case can drive the SET-BUT-EMPTY state,
  # which is a distinct branch from unset. The value is the one the sweep gated on -- see the
  # probe's THE STALENESS CLOCK block for why the header is the fallback and not the source.
  local -a sweeper_env=()
  if [[ -n "${CASE_SWEEPER_EARLIEST+x}" ]]; then
    sweeper_env=("SOLEUR_FT_EARLIEST=$CASE_SWEEPER_EARLIEST")
  else
    sweeper_env=("-u" "SOLEUR_FT_EARLIEST")
  fi

  # env -u mirrors the `env -i` the sweeper runs probes under: no ambient SOLEUR_FT_* may reach
  # the probe, or the stub's --since/--limit assertions above would grade the harness's shell.
  env -u SOLEUR_FT_WINDOW -u SOLEUR_FT_LIMIT "${sweeper_env[@]}" \
    STUB_RC="${STUB_RC:-0}" \
    BETTERSTACK_QUERY_HOST="$([[ "${CASE_UNSET:-}" == BETTERSTACK_QUERY_HOST ]] && echo "" || echo stub)" \
    BETTERSTACK_QUERY_USERNAME="$([[ "${CASE_UNSET:-}" == BETTERSTACK_QUERY_USERNAME ]] && echo "" || echo stub)" \
    BETTERSTACK_QUERY_PASSWORD="$([[ "${CASE_UNSET:-}" == BETTERSTACK_QUERY_PASSWORD ]] && echo "" || echo stub)" \
    bash "$probe" >"$WORK/out" 2>&1
  echo $?
}

# ── the verdict helper ────────────────────────────────────────────────────────────────────────
# Optional extra seams, read with defaults:
#   CASE_REQUIRE  a literal the output MUST contain (message-text assertions)
#   CASE_FORBID   a literal the output must NOT contain (the public-comment withholding rules)
expect() { # <name> <expected-rc> <fixture-file> <branch-marker>
  cases=$((cases + 1))
  local name="$1" want="$2" fixture="$3" marker="$4" got ok=1 token
  got="$(run_probe "$fixture")"
  # The probe MUST have run. Without this, `got="$want"` passes every case with the subject never
  # executed — measured on the 7500 harness's first revision.
  [[ -s "$WORK/out" ]] || { fail "$name — probe produced NO output; did it run?"; return; }
  [[ "$got" == "$want" ]] || ok=0
  grep -qF -- "$marker" "$WORK/out" || ok=0
  # THE WITHHOLDING RULE, unconditionally. The sweeper posts this output into a PUBLIC comment,
  # and the probe repeats daily, so a single verdict printing the Hetzner volume alias defeats
  # the withholding on every other verdict in the same thread. Asserted here rather than per
  # case: a per-case forbid covered 3 of 8 exit-1 cases and none of V6/V7 (#8386 review).
  if grep -qF -- "$VOL" "$WORK/out"; then
    ok=0; printf '        | LEAKED the volume alias into public output\n' >&2
  fi
  if grep -qF "$CANARY" "$WORK/out"; then
    fail "$name — the probe ECHOED ROW CONTENT ($CANARY) into its output; the public issue gets counts only"
    return
  fi
  if grep -qF "$FAKE_CRED" "$WORK/out"; then
    fail "$name — the probe passed the query tool's CREDENTIAL-SHAPED output through into a public comment"
    return
  fi
  if [[ -n "${CASE_REQUIRE:-}" ]] && ! grep -qF -- "${CASE_REQUIRE}" "$WORK/out"; then
    ok=0; printf '        | missing required text: %s\n' "${CASE_REQUIRE}" >&2
  fi
  if [[ -n "${CASE_FORBID:-}" ]] && grep -qF -- "${CASE_FORBID}" "$WORK/out"; then
    fail "$name — output contains '${CASE_FORBID}', which this verdict must WITHHOLD from a public comment"
    return
  fi
  # The verdict TOKEN, for the derived per-exit-code floor. `verdict=` on a branch, `branch=` on
  # a staleness escalation.
  token="$(printf '%s\n' "$marker" | grep -oE '(verdict|branch)=[a-z0-9_]+' | head -1 | cut -d= -f2)"
  printf '%s\t%s\t%s\n' "$want" "$token" "$marker" >> "$MARKER_LOG"
  if (( ok )); then
    pass "$name (exit $got, branch: ${marker:0:52})"
  else
    fail "$name — expected exit $want + marker '${marker:0:52}', got exit $got"
    sed 's/^/        | /' "$WORK/out" >&2
  fi
}

# ══ GUARD CHAIN — every exit-2 site ═══════════════════════════════════════════════════════════

: > "$WORK/empty"
rowgood "$DT_D" "$NEWBOOT" > "$WORK/one_good"

CASE_UNSET=BETTERSTACK_QUERY_PASSWORD \
expect "an unprovisioned secret is TRANSIENT, never FAIL" 2 "$WORK/one_good" \
  "verdict=g1_secret_unset secret=BETTERSTACK_QUERY_PASSWORD"

CASE_NO_QUERY=1 \
expect "no betterstack-query.sh in the checkout -> TRANSIENT" 2 "$WORK/one_good" \
  "verdict=g2_query_missing"

# AC-P2b: the query tool's stdout AND stderr both carry a credential-shaped token and it exits 7.
# expect() greps the probe's combined output for that token on EVERY case; this is the case that
# makes the grep non-vacuous. The xtrace refusal covers tracing, not output pass-through.
STUB_RC=7 \
expect "query exit 7 -> TRANSIENT, and the credential-shaped output is NOT passed through" 2 "$WORK/one_good" \
  "verdict=g3_query_failed"

expect "zero rows -> channel_dark, never 'clean by absence'" 2 "$WORK/empty" \
  "verdict=g4_channel_dark"

CASE_NO_LIB=1 \
expect "the mirrored parse library is unreadable -> TRANSIENT" 2 "$WORK/one_good" \
  "verdict=g5_parse_lib_unreadable"

# Envelope-only: rows quoting the marker with a GOOD posture block and a fabricated boot. If the
# anchor were dropped this file alone would read as a confident PASS.
{ foreign "$DT_C" "$ALT1"; foreign "$DT_D" "$ALT1"; } > "$WORK/f_foreign"
expect "marker-quoting rows with no producer envelope -> TRANSIENT" 2 "$WORK/f_foreign" \
  "verdict=g6_envelope_absent rows=2"

# Anchored, but the inner document does not decode: `fromjson?` yields nothing and the marker
# grep then drops the row. Matching the UNDECODED form would look exactly like an undelivered
# emitter, which is a different verdict with a different disposition.
printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 boot_id=%s host=%s"}\n' \
  "$DT_D" "$NEWBOOT" "$EXPECTED_HOST" > "$WORK/f_nodecode"
expect "envelope present but undecodable -> TRANSIENT" 2 "$WORK/f_nodecode" \
  "verdict=g7_decode_failed"

# Host scoping precedes boot selection: a producer-shaped row from a DIFFERENT host must not
# supply the evidence base.
{
  rowh "$DT_C" "soleur-registry-2" "$ALT2" "$(good_posture)" "level:info $CANARY"
  rowh "$DT_D" "soleur-registry-2" "$ALT2" "$(good_posture)" "level:info $CANARY"
} > "$WORK/f_otherhost"
expect "every producer row is from another host -> TRANSIENT" 2 "$WORK/f_otherhost" \
  "verdict=g8_host_filter_empty decoded=2"

# ══ GUARD CHAIN — the exit-3 sites ════════════════════════════════════════════════════════════

# `unknown` is the producer's /proc-unreadable DEFAULT, not an identity: accepting it would scope
# every count to a pseudo-boot, so a /proc read failure alone could drive a verdict.
{ row "$DT_C" unknown "$(good_posture)"; row "$DT_D" unknown "$(good_posture)"; } > "$WORK/f_noboot"
expect "boot_id=unknown is not an identity -> CANNOT ESTABLISH" 3 "$WORK/f_noboot" \
  "verdict=g9_no_boot_id"

# `dt` is the only ingest-assigned field in the row. If it cannot be parsed, producer liveness
# cannot be established and a stale window would grade as a current one.
rowh "ZZZZ-NOT-A-TIMESTAMP" "$EXPECTED_HOST" "$ALT3" "$(good_posture)" "level:info $CANARY" > "$WORK/f_baddt"
expect "an unparseable ingest timestamp -> CANNOT ESTABLISH" 3 "$WORK/f_baddt" \
  "verdict=g10_dt_unreadable boot=$ALT3"

# producer_silent: a perfect boot whose newest row is two hours old. Without this guard a host
# that stopped emitting is indistinguishable from one that is healthy right now.
{
  rowgood "$(rowdt '-2 hours 15 minutes')" "$ALT4"
  rowgood "$(rowdt '-2 hours 10 minutes')" "$ALT4"
  rowgood "$(rowdt '-2 hours 5 minutes')"  "$ALT4"
  rowgood "$DT_SILENT" "$ALT4"
} > "$WORK/f_silent"
CASE_LEDGER=available \
expect "a perfect boot that stopped emitting 2h ago -> producer_silent, never V7" 3 "$WORK/f_silent" \
  "verdict=g11_producer_silent boot=$ALT4"

# The integer guard. The ONLY way to reach it is a grading pass that emits nothing — a dialect
# error, a changed row shape — so the case breaks the probe COPY's awk END block on purpose and
# asserts the sed landed. Without this guard an empty count reads as "no plaintext rows".
{ rowgood "$DT_C" "$ALT5"; rowgood "$DT_D" "$ALT5"; } > "$WORK/f_intguard"
CASE_LEDGER=available \
CASE_PROBE_SED='s/END \{ print d, y, p, luks, src, devid, expd, bdev \}/END { }/' \
expect "the grading pass emits nothing -> CANNOT ESTABLISH, never a graded verdict" 3 "$WORK/f_intguard" \
  "verdict=g12_no_counts boot=$ALT5"

# ══ V2 — the undelivered family, all three exits ══════════════════════════════════════════════

{ rowbare "$DT_C" "$ALT6"; rowbare "$DT_D" "$ALT6"; } > "$WORK/f_undelivered"

CASE_EARLIEST="$FRESH_EARLIEST" CASE_REQUIRE="UNDER" \
expect "undelivered on the first sweep past earliest -> NOT YET" 2 "$WORK/f_undelivered" \
  "verdict=v2_undelivered_fresh boot=$ALT6"

CASE_REQUIRE="UNDER" \
expect "undelivered after the first sweep -> CANNOT ESTABLISH" 3 "$WORK/f_undelivered" \
  "verdict=v2_undelivered boot=$ALT6"

# The apply-file byte count is MESSAGE CONTENT, never a branch: the same fixture at a size over
# GitHub's workflow limit must produce the SAME verdict and DIFFERENT text. A rename or a repair
# of that workflow (#8361, #8362) must not be able to move a verdict.
{ rowbare "$DT_C" "$ALT7"; rowbare "$DT_D" "$ALT7"; } > "$WORK/f_undelivered_big"
CASE_APPLY=520000 CASE_REQUIRE="OVER" \
expect "undelivered with the apply workflow OVER the limit -> same verdict, different text" 3 "$WORK/f_undelivered_big" \
  "verdict=v2_undelivered boot=$ALT7"

CASE_EARLIEST="$STALE_EARLIEST" CASE_REQUIRE="delivery failure, not a wait" \
expect "undelivered past 30 days -> ACTION REQUIRED" 5 "$WORK/f_undelivered" \
  "verdict=v2_undelivered_stale boot=$ALT6"

# THE HEAD CUT. Three rows whose HEADS carry no posture field at all and whose TAILS carry a
# complete, well-formed, matching posture block — the shape a crafted zot log line produces,
# since `zot_last_err` is free text influenced by request headers on the private net. With the
# trusted-region cut the correct reading is "undelivered"; without it, this file reads as
# evidence complete on a good boot and the ledger below says `available`.
{
  rowtail "$DT_B" "$ALT8" "" "$(good_posture)"
  rowtail "$DT_C" "$ALT8" "" "$(good_posture)"
  rowtail "$DT_D" "$ALT8" "" "$(good_posture)"
} > "$WORK/f_forgedtail"
CASE_LEDGER=available \
expect "a forged posture block in the free-text tail is not evidence" 3 "$WORK/f_forgedtail" \
  "verdict=v2_undelivered boot=$ALT8"

# ══ V3 — a partial producer row is not a FAIL ═════════════════════════════════════════════════
{
  rowgood "$DT_B" "$ALT9"
  rowgood "$DT_C" "$ALT9"
  rowbare "$DT_D" "$ALT9"
} > "$WORK/f_v3"
CASE_LEDGER=available \
expect "the newest row carries no store_luks= -> CANNOT ESTABLISH, never a public FAIL" 3 "$WORK/f_v3" \
  "verdict=v3_newest_field_absent boot=$ALT9"

# ══ V4b — a tool-refused or race reading is not a public FAIL ════════════════════════════════
# The emitter distinguishes four store_luks states and `unknown` means "the TOOL refused"
# (cryptsetup rc 127/124, empty blkid, a sentinel base), not "the bytes are plaintext". Before
# V3b, V4 published exactly that to a PUBLIC tracker while V1's counting layer — which counts
# `no` only — refused to call it plaintext fifty lines earlier. These two cases pin that the
# probe cannot contradict itself, in BOTH indeterminate spellings.
{
  rowgood "$DT_B" "$ALT13"
  rowgood "$DT_C" "$ALT13"
  rowluks "$DT_D" "$ALT13" unknown
} > "$WORK/f_v3b_unknown"
CASE_LEDGER=available \
expect "a tool-refused 'unknown' on the newest row -> CANNOT ESTABLISH, never a public FAIL" 3 "$WORK/f_v3b_unknown" \
  "verdict=v4b_newest_indeterminate value=unknown boot=$ALT13"

# THE REAL MOUNT-RACE SHAPE, not a hand-built one. The emitter sets store_luks=absent ONLY on
# its __NOMOUNT__ path, where the mount source and the devid are both sentinels — so the race
# trips two INDEPENDENT disjuncts and is a FAIL, which is the residual this probe's header
# states rather than hides. An earlier revision of this case fixtured `absent` beside a GOOD
# mount source and asserted V4b covered it: a row the producer cannot emit, and therefore a
# green assertion about coverage the code did not have.
{
  rowgood "$DT_B" "$ALT14"
  rowgood "$DT_C" "$ALT14"
  row "$DT_D" "$ALT14" "$(posture absent __NOMOUNT__ n/a "$VOL" n/a)"
} > "$WORK/f_race"
CASE_LEDGER=available \
expect "the post-replace mount race is the documented FAIL, not a V4b cannot-establish" 1 "$WORK/f_race" \
  "verdict=v4_not_encrypted reason=mount_src_unexpected,devid_mismatch boot=$ALT14"

# ══ V5 — the evidence-depth floor, and boot scoping ═══════════════════════════════════════════
# The OLDER boot's three confirming rows are emitted LAST in the file and carry OLDER dt values.
# Two invariants ride on this one fixture: the dt sort (file order must not select the boot) and
# the boot scope (an older boot's rows must not top up the newest boot's evidence depth).
{
  rowgood "$DT_D" "$NEWBOOT"
  rowgood "$DT_OLD" "$OLDBOOT"
  rowgood "$(rowdt '-23 hours 5 minutes')" "$OLDBOOT"
  rowgood "$(rowdt '-23 hours 10 minutes')" "$OLDBOOT"
} > "$WORK/f_v5"
CASE_LEDGER=available \
expect "one confirming row on the newest boot -> too young, even with an older boot's three" 3 "$WORK/f_v5" \
  "verdict=v5_boot_too_young boot=$NEWBOOT confirming=1 required=3"

# ══ V6 ledger reader — three states, never two ════════════════════════════════════════════════
{ rowgood "$DT_B" "$ALT10"; rowgood "$DT_C" "$ALT10"; rowgood "$DT_D" "$ALT10"; } > "$WORK/f_good10"
CASE_LEDGER=absent \
expect "the ledger file is missing -> CANNOT ESTABLISH, never 'not yet flipped'" 3 "$WORK/f_good10" \
  "verdict=v6_ledger_unreadable boot=$ALT10"

{ rowgood "$DT_B" "$ALT11"; rowgood "$DT_C" "$ALT11"; rowgood "$DT_D" "$ALT11"; } > "$WORK/f_good11"
CASE_LEDGER=malformed \
expect "the ledger JSON is malformed -> CANNOT ESTABLISH" 3 "$WORK/f_good11" \
  "verdict=v6_ledger_unreadable boot=$ALT11"

# ══ V1 / V4 — the FAIL verdicts, and what they must WITHHOLD ══════════════════════════════════

# V1 IS FIRST, DELIBERATELY. The newest row is perfect, three rows confirm, the ledger reads
# `available` — every ingredient of V7 — and ONE earlier row on the same boot read `no`. A real
# plaintext window must not be suppressed by a later arm, and must not be graded away by the
# ledger read.
{
  rowluks "$DT_A" "$ALT12" no
  rowgood "$DT_B" "$ALT12"
  rowgood "$DT_C" "$ALT12"
  rowgood "$DT_D" "$ALT12"
} > "$WORK/f_v1"
CASE_LEDGER=available CASE_FORBID="$VOL" \
expect "an earlier 'no' on the graded boot -> FAIL, even under a perfect newest row" 1 "$WORK/f_v1" \
  "verdict=v1_plaintext_on_boot boot=$ALT12 plaintext_rows=1 confirming=3"

# The same shape again, asserting the OTHER withheld value: the mount source.
CASE_LEDGER=available CASE_FORBID="$EXPECTED_SRC" \
expect "the V1 comment withholds the mount source too" 1 "$WORK/f_v1" \
  "verdict=v1_plaintext_on_boot boot=$ALT12 plaintext_rows=1"

# V4 disjunct 1 — two matching SENTINELS. Equality alone would pass here; the shape check is
# what refuses it.
mk_v4() { # <boot> <luks> <src> <devid> <expected>
  local b="$1"
  { row "$DT_B" "$b" "$(posture "$2" "$3" "$4" "$5" "$BACKING")"
    row "$DT_C" "$b" "$(posture "$2" "$3" "$4" "$5" "$BACKING")"
    row "$DT_D" "$b" "$(posture "$2" "$3" "$4" "$5" "$BACKING")"; }
}
mk_v4 "$ALT13" yes "$EXPECTED_SRC" __UNREADABLE__ __UNREADABLE__ > "$WORK/f_v4a"
CASE_LEDGER=available \
expect "V4: two matching __UNREADABLE__ sentinels are not a match" 1 "$WORK/f_v4a" \
  "verdict=v4_not_encrypted reason=expected_devid_malformed boot=$ALT13"

# V4 disjunct 1 again — the MALFORMED RENDERED ALIAS. An empty registry_volume_id renders
# `scsi-0HC_Volume_` into registry-luks-open.sh's DEV too, so that host genuinely has no opened
# mapper: FAIL is the true reading, not a separate "cannot establish" arm.
mk_v4 "$ALT14" yes "$EXPECTED_SRC" scsi-0HC_Volume_ scsi-0HC_Volume_ > "$WORK/f_v4b"
CASE_LEDGER=available \
expect "V4: an empty-id rendered alias is a FAIL, not its own arm" 1 "$WORK/f_v4b" \
  "verdict=v4_not_encrypted reason=expected_devid_malformed boot=$ALT14"

# V4 disjunct 2 — measured, and not LUKS-confident.
mk_v4 "$ALT15" unknown "$EXPECTED_SRC" "$VOL" "$VOL" > "$WORK/f_v4c"
CASE_LEDGER=available \
expect "store_luks=unknown with every other field as declared -> CANNOT ESTABLISH, not a FAIL" 3 "$WORK/f_v4c" \
  "verdict=v4b_newest_indeterminate value=unknown boot=$ALT15"

# V4 disjunct 3 — LUKS, but not through the declared mapper.
mk_v4 "$ALT16" yes /dev/sdb1 "$VOL" "$VOL" > "$WORK/f_v4d"
CASE_LEDGER=available CASE_FORBID="$VOL" \
expect "V4: a LUKS reading on an undeclared mount source is not a PASS" 1 "$WORK/f_v4d" \
  "verdict=v4_not_encrypted reason=mount_src_unexpected boot=$ALT16"

# V4 disjunct 4 — the right shape on the WRONG volume.
mk_v4 "$ALT17" yes "$EXPECTED_SRC" "$VOL_OTHER" "$VOL" > "$WORK/f_v4e"
CASE_LEDGER=available \
expect "V4: encrypted, but not on the declared volume" 1 "$WORK/f_v4e" \
  "verdict=v4_not_encrypted reason=devid_mismatch boot=$ALT17"

# V4 — the newest row reads `absent`. Stated residual: a sweep landing inside the post-replace
# mount race posts one FAIL on a correct boot. Fail-loud in the safe direction, self-correcting.
{
  rowgood "$DT_B" "$ALT18"
  rowgood "$DT_C" "$ALT18"
  row "$DT_D" "$ALT18" "$(posture absent __NOMOUNT__ n/a "$VOL" n/a)"
} > "$WORK/f_v4f"
CASE_LEDGER=available \
expect "an 'absent' row with nothing mounted still FAILs on its INDEPENDENT disjuncts" 1 "$WORK/f_v4f" \
  "verdict=v4_not_encrypted reason=mount_src_unexpected,devid_mismatch boot=$ALT18"

# The narrowing is bounded: an indeterminate store_luks must NOT suppress a disjunct measured
# independently of it. Without this row, moving the V4b arm ahead of the V4 disjuncts would stay
# green while hiding a definitively-wrong volume behind "cannot establish".
mk_v4 "$ALT16" unknown "$EXPECTED_SRC" scsi-0HC_Volume_90000001 "$VOL" > "$WORK/f_v4b_masks"
CASE_LEDGER=available \
expect "an indeterminate store_luks does NOT mask an independently-measured devid mismatch" 1 "$WORK/f_v4b_masks" \
  "verdict=v4_not_encrypted reason=devid_mismatch boot=$ALT16"


# ══ V6 / V7 ═══════════════════════════════════════════════════════════════════════════════════
{ rowgood "$DT_B" "$NEWBOOT"; rowgood "$DT_C" "$NEWBOOT"; rowgood "$DT_D" "$NEWBOOT"; } > "$WORK/f_v6"
CASE_LEDGER=other CASE_REQUIRE="live_coverage_floor to 2" \
expect "evidence complete, ledger not yet flipped -> ACTION REQUIRED with the two-part instruction" 5 "$WORK/f_v6" \
  "verdict=v6_flip_ledger boot=$NEWBOOT confirming=3"

CASE_LEDGER=available CASE_REQUIRE="REVIEWED decision" \
expect "evidence complete AND ledger available -> ACTION REQUIRED, deliberately not an auto-close" 5 "$WORK/f_v6" \
  "verdict=v7_evidence_complete boot=$NEWBOOT confirming=3 ledger=available"

# ══ STALENESS — every exit-3 branch escalates, not just V2 ════════════════════════════════════
# Scoping the clock to V2 would leave a STRUCTURALLY BROKEN probe parked on V3 / V5 / the integer
# guard / producer_silent forever, all exit 3, indistinguishable from one legitimately waiting.

CASE_EARLIEST="$STALE_EARLIEST" \
expect "stale: no usable boot_id -> ACTION REQUIRED" 5 "$WORK/f_noboot" \
  "escalation=stale branch=g9_no_boot_id"

CASE_EARLIEST="$STALE_EARLIEST" \
expect "stale: unparseable dt -> ACTION REQUIRED" 5 "$WORK/f_baddt" \
  "escalation=stale branch=g10_dt_unreadable"

CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available \
expect "stale: producer_silent -> ACTION REQUIRED" 5 "$WORK/f_silent" \
  "escalation=stale branch=g11_producer_silent"

# THE STRUCTURALLY-BROKEN PROBE. Its awk emits nothing and its tracker has been open 40 days: a
# permanently broken probe must not read as one legitimately waiting.
CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available \
CASE_PROBE_SED='s/END \{ print d, y, p, luks, src, devid, expd, bdev \}/END { }/' \
expect "stale: a structurally broken probe escalates past 30 days" 5 "$WORK/f_intguard" \
  "escalation=stale branch=g12_no_counts"

CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available \
expect "stale: the newest row lacks the field -> ACTION REQUIRED" 5 "$WORK/f_v3" \
  "escalation=stale branch=v3_newest_field_absent"

# The clock now reaches the STRUCTURAL exit-2 guards too. Its own rationale names "a jq upgrade",
# which lands on g7 -- an exit-2 branch that previously parked on NOT YET forever, getting
# MILDER the longer it stayed broken. g1/g2/g4 stay unclocked deliberately: an unprovisioned
# secret and a missing query script are pre-enrolment states, and a dark channel is owned by
# scheduled-zot-restart-loop.yml's PRODUCER_SILENT/INGEST_DARK alarm (#8386 review).
CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available STUB_RC=7 \
expect "stale: a query that has failed for 30 days is a defect, not a wait" 5 "$WORK/one_good" \
  "escalation=stale branch=g3_query_failed"

CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available CASE_NO_LIB=1 \
expect "stale: an unreadable parse library past the horizon -> ACTION REQUIRED" 5 "$WORK/one_good" \
  "escalation=stale branch=g5_parse_lib_unreadable"

CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available \
expect "stale: 30 days of marker-quoting rows with no envelope -> ACTION REQUIRED" 5 "$WORK/f_foreign" \
  "escalation=stale branch=g6_envelope_absent"

CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available \
expect "stale: 30 days undecodable (the jq upgrade the clock's rationale names) -> ACTION REQUIRED" 5 "$WORK/f_nodecode" \
  "escalation=stale branch=g7_decode_failed"

CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available \
expect "stale: 30 days of rows from another host only -> ACTION REQUIRED" 5 "$WORK/f_otherhost" \
  "escalation=stale branch=g8_host_filter_empty"

CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available \
expect "stale: a boot stuck below the evidence floor -> ACTION REQUIRED" 5 "$WORK/f_v5" \
  "escalation=stale branch=v5_boot_too_young"

CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available \
expect "stale: a host parked on 'unknown' past the horizon -> ACTION REQUIRED" 5 "$WORK/f_v3b_unknown" \
  "escalation=stale branch=v4b_newest_indeterminate"

CASE_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=absent \
expect "stale: an unreadable ledger -> ACTION REQUIRED" 5 "$WORK/f_good10" \
  "escalation=stale branch=v6_ledger_unreadable"

# ══ WHOSE CLOCK — the sweeper's earliest beats this file's header ═════════════════════════════
# sweep-followthroughs.sh parses `earliest=` from the ISSUE BODY and gates the run on it; it never
# reads this script. So the header copy is a SECOND copy, and it drifts the moment a body directive
# is re-baselined or a second tracker enrols this same probe with its own `earliest=`. The sweeper
# now forwards what it gated on as SOLEUR_FT_EARLIEST.
#
# BOTH DIRECTIONS ARE LOAD-BEARING. A single "stale env -> escalates" case is satisfied by a probe
# that ORs the two sources, or that reads whichever happens to be stale; only the fresh-env /
# stale-header direction can tell "prefers the sweeper" from "escalates if either is old". The pair
# pins the precedence, and each row reds on its own mutation.
#
# THREE OF THESE ASSERT THE PROVENANCE LINE, NOT A BRANCH MARKER, and that is deliberate. They
# exercise branches other cases already own (v3 at exit 3, v3-stale at exit 5), so asserting the
# branch marker again would trip the marker-uniqueness guard below — correctly: a second case on
# the same literal reads as double coverage. `clock=` carries no `verdict=`/`branch=` token, so
# expect() logs an EMPTY floor token and these rows add nothing to any per-exit-code bucket. The
# floors stay exact and the property under test is the one asserted.

CASE_EARLIEST="$FRESH_EARLIEST" CASE_SWEEPER_EARLIEST="$STALE_EARLIEST" CASE_LEDGER=available \
CASE_REQUIRE="clock=sweeper" \
expect "sweeper says 40 days, header says 1 -> escalates on the sweeper's clock" 5 "$WORK/f_v3" \
  "escalation=stale branch=v3_newest_field_absent days=40 clock=sweeper"

CASE_EARLIEST="$STALE_EARLIEST" CASE_SWEEPER_EARLIEST="$FRESH_EARLIEST" CASE_LEDGER=available \
CASE_FORBID="escalation=stale" CASE_REQUIRE="verdict=v3_newest_field_absent" \
expect "sweeper says 1 day, header says 40 -> the stale HEADER does not escalate" 3 "$WORK/f_v3" \
  "clock=sweeper days=0"

# MALFORMED IS A REFUSAL, NOT A FALLBACK. `date -d` accepts "next friday", "@0" and "yesterday",
# so the shape regex is the validator. Falling back to the header here would restore the drift in
# the one case where the two values are KNOWN to disagree, so the clock is disabled instead: the
# header is 40 days stale and must still not produce an ACTION REQUIRED out of a bad directive.
CASE_EARLIEST="$STALE_EARLIEST" CASE_SWEEPER_EARLIEST="next friday" CASE_LEDGER=available \
CASE_FORBID="escalation=stale" \
expect "malformed sweeper clock -> refused, and the stale header is NOT substituted" 3 "$WORK/f_v3" \
  "clock=refused reason=malformed_sweeper_earliest"

# SET-BUT-EMPTY is the shape a directive with no `earliest=` produces: the sweeper forwards
# `${earliest:-}` unconditionally, so the probe sees "" rather than an unset variable. Empty fails
# the shape regex, so it lands on the same refusal — never on a silent header fallback.
CASE_EARLIEST="$STALE_EARLIEST" CASE_SWEEPER_EARLIEST="" CASE_LEDGER=available \
CASE_FORBID="escalation=stale" \
expect "sweeper forwarded an empty earliest -> refused, not the stale header" 3 "$WORK/f_v3" \
  "clock=refused reason=empty_sweeper_earliest"

# ══ MUST-PASS CONTROLS — the other half of the battery ════════════════════════════════════════
# Counting these in a "caught N of N" mutation tally would overstate it; they are here because a
# guard that reddens on a correct tree is worse than no guard.

# M1 — the real post-delivery steady state, with everything a live window carries that a
# hand-built fixture omits: unknown extra fields, one earlier `unknown` measurement among the
# confirming rows, a Vector-shipped row merely quoting the marker at the NEWEST timestamp, and an
# apply workflow at 400,000 B.
{
  row "$(rowdt '-30 minutes')" "$NEWBOOT" "$(posture unknown __UNREADABLE__ __UNREADABLE__ "$VOL" __UNREADABLE__)"
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 future_field_9=42 boot_id=%s %sanother_new_field=x host=%s zot_last_err=level:info %s\\"}"}\n' \
    "$DT_B" "$NEWBOOT" "$(good_posture)" "$EXPECTED_HOST" "$CANARY"
  rowgood "$DT_C" "$NEWBOOT"
  rowgood "$DT_D" "$NEWBOOT"
  foreign "$(rowdt '-1 minute')" "$ALT1"
} > "$WORK/m1"
CASE_LEDGER=available CASE_APPLY=400000 \
expect "M1 must-PASS: a realistic delivered window still grades V7" 5 "$WORK/m1" \
  "verdict=v7_evidence_complete boot=$NEWBOOT confirming=3"

# M2 — the boot race. The mount arrives through a `nofail` fstab line plus a oneshot, so the
# first tick of a legitimate boot can read `absent`. Counting that as plaintext would FAIL every
# correct replace.
{
  row "$DT_A" "$ALT2" "$(posture absent __NOMOUNT__ n/a "$VOL" n/a)"
  rowgood "$DT_B" "$ALT2"
  rowgood "$DT_C" "$ALT2"
  rowgood "$DT_D" "$ALT2"
} > "$WORK/m2"
CASE_LEDGER=available \
expect "M2 must-PASS: an early-boot 'absent' tick is not a plaintext reading" 5 "$WORK/m2" \
  "verdict=v7_evidence_complete boot=$ALT2 confirming=3"

# ── reject control for expect(), the VERDICT-OWNING helper ────────────────────────────────────
# pass()/fail() are dispatch; `expect` is what DECIDES. A control that drives only pass()/fail()
# proves the dispatch works while `expect` decides nothing — measured on the sibling suite:
# neutering expect's two comparisons left it fully green with the probe never consulted. Drive
# expect once with a deliberately wrong code AND a wrong marker, require `fails` to have moved,
# then unwind (counters AND the case tally, so the floor stays exact). Reports via printf/exit,
# never through expect().
_e_p0=$passes; _e_f0=$fails; _e_c0=$cases
expect "expect() reject control (this FAIL line is expected, not a real failure)" 99 "$WORK/empty" \
  "__A_MARKER_NO_BRANCH_EVER_PRINTS__"
if (( fails != _e_f0 + 1 )); then
  printf 'FATAL: expect() did not register a failure for a deliberately wrong code+marker -- every case above is unbacked.\n' >&2
  exit 1
fi
passes=$_e_p0; fails=$_e_f0; cases=$_e_c0
# The reject control's row must not pollute the marker ledger either.
grep -v '__A_MARKER_NO_BRANCH_EVER_PRINTS__' "$MARKER_LOG" > "$MARKER_LOG.tmp" && mv "$MARKER_LOG.tmp" "$MARKER_LOG"

# ── positive control for the verdict helpers ──────────────────────────────────────────────────
# An assertion-count floor cannot see a rewritten fail() that still counts. Drive both helpers
# once and confirm BOTH counters moved, then unwind.
_p0=$passes; _f0=$fails
pass "verdict-helper positive control (this line is the control)"
fail "verdict-helper positive control (expected FAIL line, not a real failure)"
if (( passes != _p0 + 1 || fails != _f0 + 1 )); then
  printf 'FATAL: verdict helpers do not both move their counters — every assertion above is unbacked.\n' >&2
  exit 1
fi
passes=$_p0; fails=$_f0

# ── DERIVED BRANCH-MARKER FLOOR ───────────────────────────────────────────────────────────────
# Per-exit-code coverage is asserted against the SHIPPED PROBE, never against a number typed
# here. A hand-counted floor stops being true the moment a branch is added, and the failure is
# silent: the new branch simply has no case. Comment lines are stripped before counting, so
# prose about an exit code does not inflate the floor.
exit_sites() { # <code>
  grep -vE '^[[:space:]]*#' "$PROBE_SRC" \
    | grep -cE "(^|[^[:alnum:]_])exit $1([[:space:]]|;|\$)" || true
}
distinct_tokens() { # <code>
  awk -F'\t' -v c="$1" '$1 == c { print $2 }' "$MARKER_LOG" | sort -u | grep -c . || true
}
floor_ok=1
for _code in 1 2 3 5; do
  _sites="$(exit_sites "$_code")"
  _tokens="$(distinct_tokens "$_code")"
  if (( _tokens < _sites )); then
    printf 'FATAL: exit %s has %s branch site(s) in the probe but only %s distinct branch marker(s) exercised — the uncovered branches are unasserted.\n' \
      "$_code" "$_sites" "$_tokens" >&2
    floor_ok=0
  else
    printf '  floor: exit %s — %s probe site(s), %s distinct branch marker(s) exercised\n' "$_code" "$_sites" "$_tokens"
  fi
done
(( floor_ok )) || exit 1

# MARKER UNIQUENESS ACROSS CASES. Two cases asserting the identical marker string do not
# distinguish two branches; they assert the same one twice while reading as double coverage.
_dupes="$(cut -f3 "$MARKER_LOG" | sort | uniq -d)"
if [[ -n "$_dupes" ]]; then
  printf 'FATAL: these branch markers are asserted by more than one case, so those cases do not distinguish branches:\n%s\n' "$_dupes" >&2
  exit 1
fi

# ── conservation ──────────────────────────────────────────────────────────────────────────────
echo
echo "=== $passes passed, $fails failed, $cases cases ==="
if (( passes + fails != cases )); then
  printf 'FATAL: verdict conservation violated — %s+%s != %s cases.\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
# BOUND, not inlined. scripts/guard-vacuity-floor.test.sh builds its mutant by slicing the floor
# block together with its THRESHOLD BINDINGS; a floor whose threshold is a bare literal is
# unconstructible, so the suite silently leaves that meta-guard's covered population. The VALUE
# stays a literal: binding it to a variable expansion re-creates the same unconstructible shape.
MIN_CASES=53
if (( cases < MIN_CASES )); then
  # PHRASING IS LOAD-BEARING, not style. guard-vacuity-floor.test.sh classifies a mutant as FIRES
  # only when its output carries a floor-shaped sentinel from a fixed vocabulary; `only %s cases
  # ran` is the sibling's phrasing and matches `only [0-9]`.
  printf 'FATAL: only %s cases ran, below the floor of %s -- the suite was truncated, so a 0-failure tally proves nothing.\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
echo "All $cases cases passed."
