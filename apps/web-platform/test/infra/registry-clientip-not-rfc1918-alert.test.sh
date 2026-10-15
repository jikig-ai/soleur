#!/usr/bin/env bash
#
# Drift guard for the "#7530 a registry-plane clientIP that is not RFC1918" Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, Guard 2 of
# knowledge-base/project/plans/2026-10-14-fix-registry-phase2-batch-htpasswd-stdin-clientip-alert-plan.md).
#
# WHAT THE ALERT IS FOR. The CLO's 2026-08-13 ruling lets the registry log shipper ship zot's
# `clientIP` unredacted only while every observable value is RFC1918. Nothing enforced that. This
# alert fires (one email to the Better Stack team; free tier: betterstack_paid_tier = false, no escalation policy,
# the escalation target is `var.betterstack_paid_tier ? policy : null`) on the first shipped `SOLEUR_ZOT_LOG`
# envelope row or `SOLEUR_ZOT_DISK` row whose FIRST `clientIP` is address-shaped and outside 10/8, 172.16/12,
# 192.168/16 (any IPv6 that is not an IPv4-mapped RFC1918 value included). Detection, not prevention: the records
# say "alerts by email (free tier, no escalation policy)"; nothing here promises an escalation.
#
# WHAT THIS FILE PROTECTS, and why each row exists rather than "the SQL looks right":
#   * The predicate is pinned WHOLE (byte-exact after the same whitespace collapse the resource site
#     applies) AND piece by piece, so a failure names the piece; and the pinned predicate is then
#     EVALUATED OFFLINE (python `re`, same RE2-compatible syntax) over the 16-literal classification
#     table plus first-occurrence decoys, so a regex that parses but grades wrong still reds.
#   * Both producer shapes are anchored at offset 0 of the stored `raw` (the direct-POST envelope);
#     the envelope is also host-scoped (this source carries web-1 and web-2 too). A journald row that
#     merely QUOTES the marker starts `{"PRIORITY":` and cannot match. Weakening either prefix, its
#     trailing space, or turning `startsWith` into a substring match all red.
#   * Only the FIRST `clientIP` is graded (`extract`, never an any-occurrence function): zot writes
#     its own clientIP before method, path and headers, so a later client-controlled copy cannot hide
#     a real address.
#   * The alerting parameters (`paused = false`, `higher_than` 0, 300/900/0/1800, `treat_as_zero`), the
#     source variable, the runbook link and the incident text, and BOTH `-target=` lines in the
#     push-triggered apply job (#5566: an untargeted resource is never applied and never exists).
#   * The ZOT IMAGE DIGEST the field order was verified against. `treat_as_zero` makes a renamed or
#     reordered clientIP read as healthy forever, so a bump of `zot_image_amd64` in zot-registry.tf
#     fails this file until someone re-runs the live population check and updates VERIFIED_ZOT_IMAGE.
#   * This suite's own registration in infra-validation.yml (a suite that never runs guards nothing).
#   The live-probe counts in the .tf comment are the ENGINE-level evidence; this file is structural
#   plus the offline evaluation. Not covered, named: IPv4-mapped IPv6 beyond `::ffff:`, non-address
#   tokens (`default`), rows the shipper rate-caps away, a public address in a different top-level
#   field, and the Better Stack evaluator being unavailable (the heartbeats' concern).
#
# Mutation rows live at the bottom. They mutate COPIES in a temp dir and re-run this file against them
# through REGCIP_TF / REGCIP_WF / REGCIP_ZOT / REGCIP_IV: the tracked files are never written, so a
# concurrent edit to them cannot be clobbered by a restore.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${REGCIP_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${REGCIP_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
ZOT="${REGCIP_ZOT:-$REPO/apps/web-platform/infra/zot-registry.tf}"
IV="${REGCIP_IV:-$REPO/.github/workflows/infra-validation.yml}"
CI="${REGCIP_CI:-$REPO/apps/web-platform/infra/cloud-init-registry.yml}"
SUITE_NAME="registry-clientip-not-rfc1918-alert.test.sh"

# The zot image the clientIP field order (clientIP before method/path/headers) was verified against,
# live, on 2026-10-14. Bumping zot_image_amd64 without re-running that check and this pin is the point.
VERIFIED_ZOT_IMAGE="ghcr.io/project-zot/zot-linux-amd64:v2.1.22@sha256:46f688dc26315a35a247e1784368829e66a67bf91de94c7d8d1645044fac1d5b"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails, which would root
# $TF at `/` — and mutate_red() below writes to $TF on every row.
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

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing — the evaluator and the mutator need it\n' >&2; exit 2; }
for f in "$TF" "$WF" "$ZOT" "$IV" "$CI"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

MUT_DIR="$(mktemp -d -t regclientip.XXXXXX)"; trap 'rm -rf "$MUT_DIR"' EXIT
assert_fixture_dir "$MUT_DIR"

# ── HARNESS MARKER: the ONLY thing that makes a skip/pin seam honourable ────────────────────────────
# MUT_SKIP, REGCIP_NO_MUT and REGCIP_REPIN switch the mutation battery off, lower the floor and re-pin the exact
# predicate. A plain `export X=1` in an operator shell or a CI env must never do that silently, so the seams are
# honoured ONLY when REGCIP_CHILD_MARKER names a regular, non-symlink, user-owned, mode-600 file directly inside a
# regclientip.* temp dir whose first line is `regcip-harness-marker v1 token=<digits> parent=<pid>` with <pid>
# equal to THIS process's parent (so a stale or copied marker is no good). The parent creates one such file per
# run in its own MUT_DIR and hands its path to every mutation child. A seam set without a valid marker prints
# `[SEAM-IGNORED]` and the FULL suite runs; an honoured seam prints `[NO_MUT]` / `[REPIN]` loudly.
HARNESS_MARKER="$(mktemp "$MUT_DIR/harness-marker.XXXXXX")" || { printf '[FATAL] cannot create the harness marker\n' >&2; exit 2; }
chmod 600 "$HARNESS_MARKER"
printf 'regcip-harness-marker v1 token=%s%s%s%s parent=%s\n' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$$" >"$HARNESS_MARKER"
STALE_MARKER="$MUT_DIR/harness-marker.stale"
printf 'regcip-harness-marker v1 token=%s%s%s%s parent=0\n' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" >"$STALE_MARKER"
chmod 600 "$STALE_MARKER"

harness_marker_valid() {
  local m="${REGCIP_CHILD_MARKER:-}" line="" mode=""
  [ -n "$m" ] && [ -f "$m" ] && [ ! -L "$m" ] && [ -O "$m" ] || return 1
  [[ "$m" == */regclientip.*/harness-marker.* ]] || return 1
  mode="$(stat -c %a -- "$m" 2>/dev/null)" || return 1
  [ "$mode" = 600 ] || return 1
  IFS= read -r line <"$m" || [ -n "$line" ] || return 1
  [[ "$line" =~ ^regcip-harness-marker\ v1\ token=[0-9]{4,}\ parent=([0-9]+)$ ]] || return 1
  [ "${BASH_REMATCH[1]}" = "$PPID" ]
}

# The exact floors (assertions that must have run). A child run with a seam honoured runs only the base rows.
FLOOR_FULL=110
FLOOR_CHILD=37

SEAMS_SET=""
[ -n "${MUT_SKIP:-}" ] && SEAMS_SET="$SEAMS_SET MUT_SKIP"
[ -n "${REGCIP_NO_MUT:-}" ] && SEAMS_SET="$SEAMS_SET REGCIP_NO_MUT"
[ -n "${REGCIP_REPIN:-}" ] && SEAMS_SET="$SEAMS_SET REGCIP_REPIN"
E_SKIP=""; E_NOMUT=""; E_REPIN=""
if [ -n "$SEAMS_SET" ]; then
  if harness_marker_valid; then
    E_SKIP="${MUT_SKIP:-}"; E_NOMUT="${REGCIP_NO_MUT:-}"; E_REPIN="${REGCIP_REPIN:-}"
    printf '[SEAM] valid harness marker; honouring:%s\n' "$SEAMS_SET"
  else
    printf '[SEAM-IGNORED]%s set without a valid harness marker (REGCIP_CHILD_MARKER); running the FULL suite with every pin armed\n' "$SEAMS_SET"
  fi
fi
if [ -n "$E_SKIP$E_NOMUT" ]; then
  printf '[NO_MUT] honoured: the mutation battery is NOT run and the floor drops to the base rows (mutation harness child only)\n'
fi

# Pure-bash helpers (no pipes): has LITERAL TEXT -> TEXT contains LITERAL; cnt LITERAL TEXT -> occurrences.
has() { [[ "$2" == *"$1"* ]]; }
cnt() { local t="${2//"$1"/}"; printf '%s' $(( (${#2} - ${#t}) / ${#1} )); }

# ── The predicate: found through the exploration's own reference, not a hard-coded local name ──
EXP_BLOCK="$(awk '/^resource "logtail_exploration" "registry_clientip_not_rfc1918"/,/^}/' "$TF")"
ALR_BLOCK="$(awk '/^resource "logtail_exploration_alert" "registry_clientip_not_rfc1918"/,/^}/' "$TF")"

SQL_LOCAL=""
if [[ "$EXP_BLOCK" =~ sql_query\ =\ replace\(trimspace\(local\.([a-z0-9_]+)\),\ \"/\\\\s\+/\",\ \"\ \"\) ]]; then
  SQL_LOCAL="${BASH_REMATCH[1]}"
fi

# The predicate as the provider receives it: the heredoc, whitespace-collapsed exactly as the resource
# site's replace(trimspace(…), "/\\s+/", " ") does. A reflow of the heredoc is invisible.
LOCAL_SQL=""
if [ -n "$SQL_LOCAL" ]; then
  LOCAL_SQL="$(awk -v k="$SQL_LOCAL" '$1==k && $2=="=" && $3=="<<-SQL"{f=1;next} f&&/^  SQL$/{f=0} f' "$TF")"
fi
FLAT="$(printf '%s' "$LOCAL_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"

# H1: an extractor that finds nothing would make every row below vacuous — so it must find the
# anchors of BOTH producers, not merely "something".
if [ -n "$SQL_LOCAL" ] && has "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry " "$FLAT" && has "SOLEUR_ZOT_DISK " "$FLAT"; then
  ok "the exploration references a predicate local this guard can read, and it carries both producer anchors"
else
  no "the exploration's predicate local was not found or is anchorless — every row below would be vacuous"
fi

has 'sql_query = replace(trimspace(local.' "$EXP_BLOCK" && has '), "/\\s+/", " ")' "$EXP_BLOCK" \
  && ok "the exploration carries the predicate collapsed to one line (the siblings' perpetual-diff rule)" \
  || no "the exploration does not carry the predicate through replace(trimspace(...), \"/\\\\s+/\", \" \")"

# EXACT PIN. The per-piece rows below say WHY each piece matters; this row says nothing else is
# there. Arithmetic on a comparison, a zeroed aggregate or an extra disjunct all keep every per-piece
# substring present, and only a whole-predicate pin sees them.
IFS= read -r -d '' EXPECTED_FLAT <<'EOF' || true
SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND (startsWith(raw, '{"message":"SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry ') OR startsWith(raw, '{"message":"SOLEUR_ZOT_DISK ')) AND arrayExists(n -> (match(n, '^[0-9]{1,3}([.][0-9]{1,3}){3}') AND NOT match(n, '^(10[.]|192[.]168[.]|172[.](1[6-9]|2[0-9]|3[01])[.])')) OR length(n) - length(replaceAll(n, ':', '')) >= 2, [replaceRegexpOne(extract(JSONExtractString(raw, 'message'), 'clientIP[:=]"?([^ ,}"]+)'), '^[[]?(::ffff:)?', '')]) GROUP BY time
EOF
EXPECTED_FLAT="${EXPECTED_FLAT%$'\n'}"
# REPIN MODE (mutation rows E1-E4 only): the exact pin is re-pinned to whatever predicate is on disk, so a
# mutated predicate passes the whole-text pin and the offline evaluator below must catch it. Honoured ONLY with a
# valid harness marker (E_REPIN is empty without one) AND MUT_SKIP: a stray REGCIP_REPIN in an operator shell or a
# CI env would otherwise turn the byte-exact row into a self-comparison. Either way the choice is printed.
if [ -n "${REGCIP_REPIN:-}" ]; then
  if [ -n "$E_REPIN" ] && [ -n "$E_SKIP" ]; then
    EXPECTED_FLAT="$FLAT"
    printf '[REPIN] honoured: the exact predicate pin is neutralised for this child run (mutation harness only)\n'
  else
    printf '[REPIN] ignored: REGCIP_REPIN is honoured only under a valid harness marker AND MUT_SKIP; the exact predicate pin stays armed\n'
  fi
fi
[ "$FLAT" = "$EXPECTED_FLAT" ] \
  && ok "the whole predicate is byte-exact (SELECT, aggregate, both anchors, the lambda, GROUP BY)" \
  || no "the predicate drifted from the pinned text — diff FLAT against EXPECTED_FLAT"

# Column form: every message read is JSONExtractString(raw, 'message'); a bare column is an
# unknown-identifier error at query time, i.e. a rule that never fires.
_M="JSONExtractString(raw, 'message')"
if [ "$(cnt "$_M" "$FLAT")" -eq 1 ] && ! [[ "$FLAT" =~ (^|[^A-Za-z_])msg([^A-Za-z_]|$) ]]; then
  ok "the clientIP is read from JSONExtractString(raw, 'message') exactly once; no bare msg column"
else
  no "column form drifted: $(cnt "$_M" "$FLAT") message reads, or a bare msg column"
fi

# An HCL heredoc plus a regex: a backslash would need escaping twice. The predicate has none by design.
has '\' "$FLAT" \
  && no "the predicate carries a backslash — the heredoc and the regexes avoid them by design ([.], [[], [^ ,}\"])" \
  || ok "the predicate carries no backslash (the regexes use [.] and [[] instead)"

# Both producers, each anchored at OFFSET 0 of raw through startsWith, in ONE OR group.
if has "AND (startsWith(raw, '{\"message\":\"SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry ') OR startsWith(raw, '{\"message\":\"SOLEUR_ZOT_DISK ')) AND arrayExists(" "$FLAT" \
  && [ "$(cnt 'startsWith(raw, ' "$FLAT")" -eq 2 ]; then
  ok "both producers are startsWith-anchored at offset 0 of raw, one OR group (a journald row quoting the marker cannot match)"
else
  no "the producer anchors drifted: want exactly two startsWith(raw, ...) conjuncts in one OR group"
fi
if has "host=soleur-registry ')" "$FLAT" && has "SOLEUR_ZOT_DISK ')" "$FLAT"; then
  ok "both anchor literals keep their TRAILING SPACE and the envelope is host-scoped to soleur-registry"
else
  no "an anchor literal lost its trailing space or the envelope lost host=soleur-registry"
fi
if ! has 'position(raw' "$FLAT" && ! has 'LIKE' "$FLAT" && ! has 'like(' "$FLAT" && ! has 'multiSearch' "$FLAT" && ! has 'positionCaseInsensitive' "$FLAT"; then
  ok "no substring-style producer match (position/LIKE/multiSearch) stands in for the offset-0 anchor"
else
  no "a substring-style match appears in the predicate — a row QUOTING the marker could satisfy it"
fi

# The private alternation and its negation.
has "AND NOT match(n, '^(10[.]|192[.]168[.]|172[.](1[6-9]|2[0-9]|3[01])[.])')" "$FLAT" \
  && [ "$(cnt 'NOT match(' "$FLAT")" -eq 1 ] \
  && ok "the three private ranges are the negated alternation (10/8, 192.168/16, 172.16/12 with 3[01])" \
  || no "the private-range negation drifted (a missing NOT would fire on the whole private population)"

has "match(n, '^[0-9]{1,3}([.][0-9]{1,3}){3}')" "$FLAT" \
  && ok "the dotted-IPv4 shape gate is present (non-address tokens such as default stay quiet)" \
  || no "the dotted-IPv4 shape gate is missing"

has "OR length(n) - length(replaceAll(n, ':', '')) >= 2," "$FLAT" \
  && ok "the IPv6 clause (two or more colons after the :port-free strip) fires" \
  || no "the IPv6 colon-count clause is missing or changed"

# First-occurrence grade: one extract(), no any-occurrence function, one clientIP reference.
if [ "$(cnt 'extract(' "$FLAT")" -eq 1 ] && [ "$(cnt 'clientIP' "$FLAT")" -eq 1 ] \
  && ! has 'extractAll' "$FLAT" && ! has 'multiMatch' "$FLAT" && ! has 'arrayMap' "$FLAT" && ! has 'splitByChar' "$FLAT"; then
  ok "the grade is the FIRST clientIP only (a single extract(), no any-occurrence function)"
else
  no "the first-occurrence pin broke: an any-occurrence function or a second clientIP reference is present"
fi
has "'clientIP[:=]\"?([^ ,}\"]+)'" "$FLAT" && has "'^[[]?(::ffff:)?', '')" "$FLAT" \
  && ok "the extract pattern and the [ / ::ffff: prefix strip are the pinned literals" \
  || no "the extract pattern or the prefix strip drifted"

has 'SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND' "$FLAT" \
  && has ' GROUP BY time' "$FLAT" \
  && ok "the count is bucketed by time over the window macros" \
  || no "SELECT/FROM/WHERE time BETWEEN/GROUP BY drifted"

# ── OFFLINE EVALUATION: the pinned predicate, executed over the classification table ───────────
# (RFC 5737 / 3849 documentation addresses and RFC1918 estate values only; synthetic, never from logs.)
LITS_ZERO='10.0.1.10:54321 172.16.0.1:1 172.31.255.255:9 192.168.1.1:80 ::ffff:10.0.0.5 default'
LITS_ONE='198.51.100.7:443 127.0.0.1:5000 172.15.0.1:1 172.32.0.1:9 192.169.0.1:80 169.254.169.254:80 100.64.0.1:80 [2001:db8::1]:80 2001:db8::1 ::ffff:198.51.100.7'
# OFFLINE-ONLY literals: graded by the python evaluator below and NOT by the live engine (the .tf comment
# records only the 16 live literals above). They close the table's blind spots: 2-colon IPv6, a public IPv4
# that EMBEDS a private prefix, a prefix `10` followed by a digit, an uppercase IPv4-mapped value (the strip
# is case-sensitive, so it fires conservatively), and a non-address token that merely CONTAINS a dotted quad
# (the shape gate's ^ keeps it quiet). Synthetic values only.
OFFLINE_ZERO='via-198.51.100.7:80'
OFFLINE_ONE='::1 fe80::1 45.10.20.30:80 110.1.2.3:80 100.10.0.1:80 ::FFFF:10.0.0.5'
SEM_OUT="$MUT_DIR/sem.out"
FLAT_SQL="$FLAT" LITS_ZERO="$LITS_ZERO" LITS_ONE="$LITS_ONE" OFFLINE_ZERO="$OFFLINE_ZERO" OFFLINE_ONE="$OFFLINE_ONE" python3 -I -W ignore - >"$SEM_OUT" 2>&1 <<'PY'
import os, re, sys

flat = os.environ["FLAT_SQL"]
m = re.search(
    r"arrayExists\(n -> \(match\(n, '(?P<shape>[^']+)'\) AND NOT match\(n, '(?P<priv>[^']+)'\)\)"
    r" OR length\(n\) - length\(replaceAll\(n, ':', ''\)\) >= (?P<thr>\d+),"
    r" \[replaceRegexpOne\(extract\(JSONExtractString\(raw, 'message'\), '(?P<ext>[^']+)'\),"
    r" '(?P<strip>[^']+)', ''\)\]\)",
    flat,
)
if not m:
    print("PARSE: the lambda no longer has the pinned shape")
    sys.exit(1)
shape, priv, ext, strip = (m.group(k) for k in ("shape", "priv", "ext", "strip"))
thr = int(m.group("thr"))


def flagged(message):
    e = re.search(ext, message)
    value = e.group(1) if e else ""
    value = re.sub(strip, "", value, count=1)
    private_miss = bool(re.search(shape, value)) and not re.search(priv, value)
    return int(private_miss or (len(value) - len(value.replace(":", ""))) >= thr)


head = "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry "
bad = 0
for expect, key in ((0, "LITS_ZERO"), (1, "LITS_ONE")):
    for lit in os.environ[key].split():
        got = flagged(head + "component:session,clientIP:" + lit + ",method:GET,path:/v2/")
        if got != expect:
            bad += 1
            print("TABLE: %s expected %d got %d" % (lit, expect, got))

# OFFLINE-ONLY literals (python `re` evaluation of the pinned lambda; no engine run is claimed).
for expect, key in ((0, "OFFLINE_ZERO"), (1, "OFFLINE_ONE")):
    for lit in os.environ[key].split():
        got = flagged(head + "component:session,clientIP:" + lit + ",method:GET,path:/v2/")
        if got != expect:
            bad += 1
            print("OFFLINE: %s expected %d got %d" % (lit, expect, got))

# First-occurrence decoys: a later copy (path, header) must neither hide nor create a verdict.
cases = [
    (1, "component:session,clientIP:198.51.100.7:443,method:GET,path:/v2/,headers:{X:clientIP:10.0.1.10}"),
    (0, "component:session,clientIP:10.0.1.10:5,method:GET,path:/v2/?clientIP=198.51.100.7,headers:{X:clientIP:198.51.100.7}"),
    (0, "component:session,method:GET,path:/v2/"),
    (1, "clientIP=198.51.100.7 method=GET"),
    (0, "clientIP=10.0.1.10 method=GET"),
]
for expect, text in cases:
    if flagged(head + text) != expect:
        bad += 1
        print("DECOY: expected %d for a first-occurrence case" % expect)
sys.exit(1 if bad else 0)
PY
sem_rc=$?
[ "$sem_rc" -eq 0 ] \
  && ok "OFFLINE EVAL: the pinned predicate grades all 16 table literals, 7 OFFLINE-ONLY literals (evaluator-only, not live) and 5 first-occurrence cases correctly" \
  || no "OFFLINE EVAL: the predicate mis-grades (rc=$sem_rc): $(tr '\n' ' ' <"$SEM_OUT" | cut -c1-300)"

TF_TEXT="$(cat "$TF")"
_all_lits=1
for lit in $LITS_ZERO $LITS_ONE; do
  has "$lit" "$TF_TEXT" || _all_lits=0
done
[ "$_all_lits" -eq 1 ] \
  && ok "all 16 classification literals are recorded in the .tf comment (the live table the probe re-runs)" \
  || no "the .tf comment no longer records the 16-literal classification table"

# ── Resource blocks ────────────────────────────────────────────────────────────────────────────
has 'name      = "soleur-registry-clientip-not-rfc1918-prd"' "$EXP_BLOCK" \
  && has 'name           = "soleur-registry-clientip-not-rfc1918-prd"' "$ALR_BLOCK" \
  && ok "both resources are named soleur-registry-clientip-not-rfc1918-prd" \
  || no "the exploration or alert name drifted from soleur-registry-clientip-not-rfc1918-prd"

has 'values        = [local.vector_prd_source_id]' "$EXP_BLOCK" \
  && has 'source_variable = "source"' "$EXP_BLOCK" \
  && ok "the exploration reads local.vector_prd_source_id (the source the registry host POSTs to)" \
  || no "the exploration's source variable is not local.vector_prd_source_id"

has 'exploration_id = logtail_exploration.registry_clientip_not_rfc1918.id' "$ALR_BLOCK" \
  && ok "the alert is attached to this exploration" \
  || no "the alert's exploration_id does not reference logtail_exploration.registry_clientip_not_rfc1918"

has $'\n  paused = false\n' "$ALR_BLOCK"$'\n' \
  && ok "paused = false (the rule is quiet on the live fleet, so it arms at merge)" \
  || no "the alert is not 'paused = false' — it would exist and never fire"

alr_kv() { awk -v k="$1" '$1==k && $2=="=" { $1=""; $2=""; sub(/^ +/, ""); print; exit }' <<<"$ALR_BLOCK"; }
[ "$(alr_kv alert_type)" = '"threshold"' ] && [ "$(alr_kv operator)" = '"higher_than"' ] && [ "$(alr_kv value)" = "0" ] \
  && ok "threshold higher_than 0: ONE shipped public row fires (no transient-row tolerance)" \
  || no "threshold drifted: type=$(alr_kv alert_type) operator=$(alr_kv operator) value=$(alr_kv value)"
[ "$(alr_kv check_period)" = "300" ] && [ "$(alr_kv query_period)" = "900" ] \
  && ok "check_period = 300 and query_period = 900" \
  || no "windows drifted: check=$(alr_kv check_period) query=$(alr_kv query_period)"
[ "$(alr_kv confirmation_period)" = "0" ] && [ "$(alr_kv recovery_period)" = "1800" ] \
  && ok "confirmation_period = 0 and recovery_period = 1800 (fire at once; two windows to resolve)" \
  || no "confirmation/recovery drifted: confirmation=$(alr_kv confirmation_period) recovery=$(alr_kv recovery_period)"
[ "$(alr_kv on_missing_data)" = '"treat_as_zero"' ] \
  && ok "treat_as_zero, so an open incident can observe recovery (silence is the heartbeats' job)" \
  || no "on_missing_data is $(alr_kv on_missing_data), want \"treat_as_zero\""
[ "$(alr_kv email)" = "true" ] && [ "$(alr_kv push)" = "false" ] && [ "$(alr_kv call)" = "false" ] \
  && [ "$(alr_kv sms)" = "false" ] && [ "$(alr_kv critical_alert)" = "false" ] \
  && ok "channels are the siblings' (email only)" \
  || no "the channel settings drifted from the siblings' email-only shape"

has 'policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null' "$ALR_BLOCK" \
  && has 'team_name = var.betterstack_paid_tier ? null : "Your team"' "$ALR_BLOCK" \
  && ok "escalation_target is the siblings' free/paid-tier ternary" \
  || no "escalation_target drifted from the siblings' routing"

# The incident text and the metadata carry ONE runbook local; its URL names a file that exists.
INC="$(alr_kv incident_cause)"
RB_LOCAL=""
if [[ "$INC" =~ \$\{local\.([a-z0-9_]+)\}\"$ ]]; then RB_LOCAL="${BASH_REMATCH[1]}"; fi
RB_URL=""
if [ -n "$RB_LOCAL" ]; then
  RB_URL="$(awk -v k="$RB_LOCAL" '$1==k && $2=="=" { gsub(/"/, "", $3); print $3; exit }' "$TF")"
fi
RB_REL="${RB_URL#*/blob/main/}"
INC_FULL="${INC//\$\{local.$RB_LOCAL\}/$RB_URL}"
INC_FULL="${INC_FULL#\"}"; INC_FULL="${INC_FULL%\"}"
if [ -n "$RB_LOCAL" ] && [ -n "$RB_URL" ] && has "runbook = local.$RB_LOCAL" "$ALR_BLOCK" \
  && [ "$RB_REL" = "knowledge-base/engineering/operations/runbooks/registry-clientip-rfc1918-7530.md" ] && [ -f "$REPO/$RB_REL" ]; then
  ok "incident_cause ends with the runbook URL, metadata.runbook is the same local, and the runbook file exists"
else
  no "the runbook link is broken: local=$RB_LOCAL rel=$RB_REL (incident_cause must end Runbook: \${local.<url>} and metadata.runbook must match)"
fi
if [ "${#INC_FULL}" -gt 0 ] && [ "${#INC_FULL}" -le 520 ] && has 'Runbook: ' "$INC"; then
  ok "incident_cause interpolates to ${#INC_FULL} characters (limit 520) and carries a Runbook: pointer"
else
  no "incident_cause is ${#INC_FULL} characters (want 1..520) or lacks a Runbook: pointer"
fi
RB_TEXT=""
[ -f "$REPO/$RB_REL" ] && RB_TEXT="$(cat "$REPO/$RB_REL")"
if has 'Art. 4(1)' "$RB_TEXT" && has 'breach-notice-triage' "$RB_TEXT" && has '90 days' "$RB_TEXT" && has 'firewall' "$RB_TEXT"; then
  ok "the runbook states the legal consequence (Art. 4(1), 90-day retention, breach-notice triage) and the cause-first fix"
else
  no "the runbook lost a legal-consequence anchor (Art. 4(1), 90 days, breach-notice-triage, firewall)"
fi

# The engine-level evidence lives in the .tf comment; its absence means the SQL was never run.
if [[ "$TF_TEXT" =~ $'\n#   (ii)'[[:space:]]+'as written'[[:space:]]+'->'[[:space:]]+0[[:space:]] ]] \
  && [[ "$TF_TEXT" =~ $'\n#   (iii)'[[:space:]]+'positive control'[^$'\n']*'->'[[:space:]]+[1-9][0-9]* ]] \
  && [[ "$TF_TEXT" =~ $'\n#   (i)'[[:space:]]+'population'[^$'\n']*'->'[[:space:]]+[1-9][0-9]* ]]; then
  ok "the live-probe population, as-written 0 and the positive control are recorded with non-zero population"
else
  no "the live-probe counts (population, as written 0, positive control) are not recorded in the .tf comment"
fi

# Both -target lines, INSIDE the push-triggered `apply:` job (not a dispatch-only job).
APPLY_JOB="$(awk '/^  apply:$/{f=1; print; next} f && /^  [A-Za-z0-9_-]+:$/{f=0} f' "$WF")"
has $'\n              -target=logtail_exploration.registry_clientip_not_rfc1918 \\\n' "$APPLY_JOB"$'\n' \
  && has $'\n              -target=logtail_exploration_alert.registry_clientip_not_rfc1918 \\\n' "$APPLY_JOB"$'\n' \
  && ok "both resources are in the push-triggered apply job's -target allowlist (#5566)" \
  || no "one or both -target= lines are missing from the apply job — the alert would never exist"

# The field-order contract: the zot image the order was verified against.
ZOT_IMG="$(awk '$1=="zot_image_amd64" && $2=="=" { gsub(/"/, "", $3); print $3; exit }' "$ZOT")"
if [ "$ZOT_IMG" = "$VERIFIED_ZOT_IMAGE" ]; then
  ok "zot_image_amd64 is the digest the clientIP field order was verified against"
else
  no "zot_image_amd64 moved: re-run the live clientIP population and field-order check (clientIP before method/path/headers), then update VERIFIED_ZOT_IMAGE and the .tf comment"
fi
has "FIELD ORDER VERIFIED AGAINST zot v2.1.22 @sha256:${VERIFIED_ZOT_IMAGE##*@sha256:}" "$TF_TEXT" \
  && ok "the .tf comment records the same verified digest" \
  || no "the .tf comment's 'FIELD ORDER VERIFIED AGAINST' digest differs from VERIFIED_ZOT_IMAGE"

# This suite is registered (a suite that never runs guards nothing): an uncommented step, once.
REG_RUN="        run: bash apps/web-platform/test/infra/$SUITE_NAME"
if [ "$(cnt "$REG_RUN"$'\n' "$(cat "$IV")"$'\n')" -eq 1 ]; then
  ok "this suite is registered in infra-validation.yml (exactly one uncommented run step)"
else
  no "infra-validation.yml does not run $SUITE_NAME exactly once"
fi

# A CI-dead guard must not pass. The step: no continue-on-error, no `if:`, and ONLY the keys name + run (a `shell:`,
# `env:`, `working-directory:` ... on it can neuter or redirect the run without being `if`/`continue-on-error`). The
# HOSTING JOB is derived from the step's position (the last job header above the registered run line, a header with a
# trailing comment or a quoted id included), never named here, and is read WHOLE (header, steps, anything after them:
# YAML key order is free): its `if:` must be the one known literal, `continue-on-error` must appear nowhere in it, its
# `needs`/`runs-on` must be the known literals, and its own keys are the known set (no `defaults`, `env`, `container`,
# `strategy`, `services` ...). Finally the verdict must REACH the aggregator: the one job that lists the hosting job in
# `needs:` must run under `if: always()` and read `needs.<job>.result` AND carry `"<job>:` in its entries array, so
# dropping the leg from the aggregator is not a quiet way to make this guard CI-dead. Comments are ignored.
# The workflow itself must carry no top-level `defaults:` and no REGCIP_* / MUT_SKIP seam in executable text.
# hdr LINE -> the job id when LINE is a `jobs:`-level key header (`  id:`, `  "id":`, `  id: # note`), else "".
AWK_HDR='function hdr(l,   n) { if (l ~ /^  [\047"]?[A-Za-z0-9_-]+[\047"]?:[ \t]*(#.*)?$/) { n = l; sub(/^  [\047"]?/, "", n); sub(/[\047"]?:.*$/, "", n); return n } return "" }'
STEP_BLOCK="$(awk -v r="$REG_RUN" "$AWK_HDR"'
  function flush() { if (blk != "" && index(blk, r "\n") > 0) printf "%s", blk; blk = "" }
  /^      - / || hdr($0) != "" { flush() }
  { if ($0 !~ /^[[:space:]]*#/) blk = blk $0 "\n" }
  END { flush() }' "$IV")"
HOST_JOB="$(awk -v r="$REG_RUN" "$AWK_HDR"'{ h = hdr($0); if (h != "") j = h } $0 == r { print j; exit }' "$IV")"
JOB_BLOCK=""
[ -n "$HOST_JOB" ] && JOB_BLOCK="$(awk -v j="$HOST_JOB" "$AWK_HDR"'{ h = hdr($0) } h != "" && h == j { f = 1; print; next } f && h != "" { exit } f && !/^[[:space:]]*#/ { print }' "$IV")"
JOB_IF="$(awk '/^    if:/ { print }' <<<"$JOB_BLOCK")"
JOB_NEEDS="$(awk '/^    needs:/ { print }' <<<"$JOB_BLOCK")"
JOB_RUNS_ON="$(awk '/^    runs-on:/ { print }' <<<"$JOB_BLOCK")"
# Key allowlists: the step is `- name:` + `run:`; the job is the known set. Anything else (or an unrecognised line shape) is listed.
STEP_BAD="$(awk -v allow=" name run " 'NF == 0 { next } { k = "?" }
  /^      - [A-Za-z_-]+:/ { k = $0; sub(/^      - /, "", k); sub(/:.*/, "", k) }
  /^        [A-Za-z_-]+:/ { k = $0; sub(/^        /, "", k); sub(/:.*/, "", k) }
  index(allow, " " k " ") == 0 { print k }' <<<"$STEP_BLOCK")"
JOB_BAD="$(awk -v allow=" name needs if runs-on permissions timeout-minutes steps " '/^    [A-Za-z_-]+:/ { k = $0; sub(/^    /, "", k); sub(/:.*/, "", k); if (index(allow, " " k " ") == 0) print k }' <<<"$JOB_BLOCK")"
IV_CODE="$(awk '!/^[[:space:]]*#/' "$IV")"
WF_BAD=""
[[ $'\n'"$IV_CODE" == *$'\ndefaults:'* ]] && WF_BAD="$WF_BAD top-level-defaults"
{ has 'REGCIP_' "$IV_CODE" || has 'MUT_SKIP' "$IV_CODE"; } && WF_BAD="$WF_BAD suite-seam-in-workflow"
# The aggregator: every job (other than the host) whose `needs:` names the host; one of them must carry the facts.
AGG_CANDS="$(awk -v host="$HOST_JOB" "$AWK_HDR"'
  function emit(l,   n, t, i) { sub(/[ \t]#.*$/, "", l); gsub(/[\[\],"\047]/, " ", l); n = split(l, t, /[ \t]+/); for (i = 1; i <= n; i++) if (t[i] == host && job != host) print job }
  /^[[:space:]]*#/ { next }
  { h = hdr($0); if (h != "") { job = h; innd = 0; next } }
  job == "" { next }
  /^    needs:/ { innd = 1; l = $0; sub(/^    needs:/, "", l); emit(l); next }
  innd && /^      -/ { l = $0; sub(/^      -/, "", l); emit(l); next }
  /^    [A-Za-z_-]+:/ { innd = 0 }' <<<"$IV_CODE")"
AGG_OK=0; AGG_NAMES=""
if [ -n "$HOST_JOB" ]; then
  while IFS= read -r _agg; do
    [ -n "$_agg" ] || continue
    AGG_NAMES="$AGG_NAMES $_agg"
    _agg_block="$(awk -v j="$_agg" "$AWK_HDR"'{ h = hdr($0) } h != "" && h == j { f = 1; print; next } f && h != "" { exit } f { print }' <<<"$IV_CODE")"
    if [[ $'\n'"$_agg_block" == *$'\n    if: always()'* ]] && has "needs.${HOST_JOB}.result" "$_agg_block" && has "\"${HOST_JOB}:\$" "$_agg_block"; then AGG_OK=1; fi
  done <<<"$AGG_CANDS"
fi
if [ -n "$STEP_BLOCK" ] && [[ "$STEP_BLOCK" != *continue-on-error* ]] && ! [[ "$STEP_BLOCK" =~ $'\n'[[:space:]]+if: ]] && ! [[ "$STEP_BLOCK" =~ ^[[:space:]]*-[[:space:]]+if: ]] \
   && [ -z "$STEP_BAD" ] && [ -n "$HOST_JOB" ] && [ -n "$JOB_BLOCK" ] && [[ "$JOB_BLOCK" != *continue-on-error* ]] && [ -z "$JOB_BAD" ] && [ -z "$WF_BAD" ] \
   && [ "$JOB_IF" = "    if: needs.detect-changes.outputs.pr_duplicate != 'true'" ] \
   && [ "$JOB_NEEDS" = "    needs: detect-changes" ] && [ "$JOB_RUNS_ON" = "    runs-on: ubuntu-24.04" ] && [ "$AGG_OK" -eq 1 ]; then
  ok "the registered step has only name+run (no continue-on-error / if: / shell / env / ...), its hosting job '$HOST_JOB' (derived from the step's position) has the one known if:, needs and runs-on, the known key set and no continue-on-error anywhere, and its verdict reaches the aggregator ('${AGG_NAMES# }': if: always(), the leg's result, its entries slot): it cannot be skipped, non-blocking, redirected or dropped"
else
  no "the registered step or its hosting job '$HOST_JOB' is conditional, non-blocking, redirected or unaggregated (step keys beyond name/run: '${STEP_BAD//$'\n'/ }'; job keys beyond the known set: '${JOB_BAD//$'\n'/ }'; workflow:${WF_BAD:- none}; aggregator ok=$AGG_OK; continue-on-error anywhere in the job; an if:/needs/runs-on other than the known literals), or could not be located"
fi

# ── Producer <-> alert parity: the anchors the predicate matches are what the producers emit ────
# (a) the envelope anchor's host literal equals the registry server's terraform name; (b) the shipper emits
# exactly the anchored prefix, with the host taken from hostname; (c) the disk heartbeat starts SOLEUR_ZOT_DISK
# and carries host=$(hostname) in its head, all on ONE line; (d) BOTH emitters wrap the line in the envelope whose
# offset 0 is `{"message":"` (the other half of each startsWith anchor). Without this row, renaming the shipper tag
# or the server, or the envelope key, makes the alert match nothing and treat_as_zero reads that as healthy.
# Every literal is looked up in COMMENT-STRIPPED, ENTRY-SCOPED text (a write_files entry with its whole-line comments
# removed), so a comment or a sibling entry quoting the literal cannot stand in for the real emitter.
# NOT covered, by design ("sampled coverage", see the runbook): the unanchored emitters SOLEUR_ZOT_LOG_DROPPED,
# SOLEUR_ZOT_LOG_BOOT and SOLEUR_PRIVATE_NIC. Their text starts differently (an underscore where anchor 1 has a space),
# the anchors do not match them, and adding rows for them would claim a coverage the predicate does not give.
ANCHOR_PFX="SOLEUR_ZOT_LOG shipper=zot-log-shipper host="
ANCHOR_HOST=""
if [[ "$FLAT" =~ SOLEUR_ZOT_LOG\ shipper=zot-log-shipper\ host=([a-z0-9-]+)\ \' ]]; then ANCHOR_HOST="${BASH_REMATCH[1]}"; fi
SRV_NAME="$(awk '/^resource "hcloud_server" "registry" \{$/{f=1;next} f&&/^}$/{exit} f&&$1=="name"&&$2=="="{gsub(/"/,"",$3);print $3;exit}' "$ZOT")"
# entry_with MARKER FILE: the write_files entry (comment lines dropped) that contains MARKER. The marker travels via
# the environment, because awk -v would interpret the backslashes the envelope literals carry.
entry_with() { ENTRY_MARK="$1" awk 'function fl() { if (blk != "" && index(blk, ENVIRON["ENTRY_MARK"]) > 0) printf "%s", blk; blk = "" } /^  - path: / { fl() } !/^[[:space:]]*#/ { blk = blk $0 "\n" } END { fl() }' "$2"; }
# shellcheck disable=SC2016  # literal $HOST_NAME_V / $(hostname) are the template's own text, not expansions
SHIP_ENTRY="$(entry_with 'ship "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=$HOST_NAME_V ' "$CI")"
# shellcheck disable=SC2016
DISK_ENTRY="$(entry_with 'LINE="SOLEUR_ZOT_DISK pcent=' "$CI")"
# The three disk-arm literals must sit on ONE line of the emitter (a split or a comment copy proves nothing).
_disk_one_line=0
while IFS= read -r _l; do
  # shellcheck disable=SC2016
  if has 'LINE="SOLEUR_ZOT_DISK pcent=' "$_l" && has ' host=$(hostname) zot_last_err=$ZOT_LAST_ERR"' "$_l"; then _disk_one_line=1; fi
done <<<"$DISK_ENTRY"
# shellcheck disable=SC2016
if [ -n "$ANCHOR_HOST" ] && [ "$ANCHOR_HOST" = "$SRV_NAME" ] && [ -n "$SHIP_ENTRY" ] && [ -n "$DISK_ENTRY" ] \
   && has "ship \"${ANCHOR_PFX}\$HOST_NAME_V " "$SHIP_ENTRY" && has 'HOST_NAME_V="$(hostname)"' "$SHIP_ENTRY" \
   && [ "$_disk_one_line" -eq 1 ]; then
  ok "PRODUCER PARITY: the anchored host literal equals hcloud_server.registry's name, the shipper emits '${ANCHOR_PFX}\$HOST_NAME_V' (hostname) and the disk heartbeat starts SOLEUR_ZOT_DISK with host=\$(hostname) zot_last_err on one line (all in code, not comments)"
else
  no "producer parity broken: anchor host='$ANCHOR_HOST' server name='$SRV_NAME' (or the shipper/disk emitter literal, comment-stripped and on one line, in cloud-init-registry.yml no longer matches the alert anchors)"
fi
# shellcheck disable=SC2016  # the envelope literals are the template's own text
if [ -n "$SHIP_ENTRY" ] && [ -n "$DISK_ENTRY" ] \
   && has 'body="{\"message\":\"$line\"}"' "$SHIP_ENTRY" \
   && has '--data-raw "{\"message\":\"$LINE\"}"' "$DISK_ENTRY"; then
  ok "ENVELOPE PARITY: the shipper's ship() body and the disk heartbeat's --data-raw both start the stored row with {\"message\":\" (offset 0 of raw, the other half of both startsWith anchors)"
else
  no "envelope parity broken: the shipper's body=\"{\\\"message\\\":\\\"\$line\\\"}\" or the disk heartbeat's --data-raw \"{\\\"message\\\":\\\"\$LINE\\\"}\" changed, so both startsWith anchors would match nothing"
fi

# ── Mutation rows: each must make the rows above RED (the must-pass rows must stay GREEN) ──────
if [ -z "$E_SKIP" ] && [ -z "$E_NOMUT" ]; then
  SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
  # Python prelude shared by every mutation program. Quotes inside programs use Q / chr(34).
  MUT_PRE='import re, sys
p = sys.argv[1]
s = open(p).read()
Q = chr(39)
DQ = chr(34)
M = "JSONExtractString(raw, " + Q + "message" + Q + ")"
SQLH = "registry_clientip_not_rfc1918_sql = <<-SQL"
def rep(old, new, n=1):
    global s
    assert s.count(old) == n, ("anchor", old, s.count(old))
    s = s.replace(old, new)
def sql(old, new, n=1):
    global s
    i = s.index(SQLH); j = s.index("\n  SQL\n", i)
    blk = s[i:j]
    assert blk.count(old) == n, ("sql anchor", old, blk.count(old))
    s = s[:i] + blk.replace(old, new) + s[j:]
def block(kind, old, new, n=1):
    global s
    i = s.index("resource " + DQ + kind + DQ + " " + DQ + "registry_clientip_not_rfc1918" + DQ)
    j = s.index("\n}\n", i)
    blk = s[i:j]
    assert blk.count(old) == n, ("block anchor", kind, old, blk.count(old))
    s = s[:i] + blk.replace(old, new) + s[j:]
'
  MUT_RAN=0
  # mutate <expect red|green|eval|norepin> <label> <tf|wf|zot|iv|ci> <python-body-on-s>
  # `eval` = run the child in REPIN mode and require the OFFLINE EVAL row (not the exact pin) to be the red row.
  mutate() {
    local expect="$1" label="$2" which="$3" prog="$4" rc=0 src
    assert_fixture_dir "$MUT_DIR"   # P1b: every arm below writes into $MUT_DIR
    MUT_RAN=$((MUT_RAN + 1))
    cp "$TF" "$MUT_DIR/alerts.tf"; cp "$WF" "$MUT_DIR/apply.yml"; cp "$ZOT" "$MUT_DIR/zot.tf"; cp "$IV" "$MUT_DIR/iv.yml"; cp "$CI" "$MUT_DIR/ci.yml"
    case "$which" in
      tf) src="$MUT_DIR/alerts.tf" ;;
      wf) src="$MUT_DIR/apply.yml" ;;
      zot) src="$MUT_DIR/zot.tf" ;;
      iv) src="$MUT_DIR/iv.yml" ;;
      ci) src="$MUT_DIR/ci.yml" ;;
      *) no "mutation '$label': unknown target $which"; return 0 ;;
    esac
    { printf '%s\n' "$MUT_PRE"; printf '%s\n' "$prog"; printf 'open(p, %sw%s).write(s)\n' '"' '"'; } >"$MUT_DIR/mut.py"
    python3 -I "$MUT_DIR/mut.py" "$src" >"$MUT_DIR/mut.log" 2>&1 || { no "mutation '$label' did not land (anchor drifted): $(tr '\n' ' ' <"$MUT_DIR/mut.log" | cut -c1-200)"; return 0; }
    # Child env, set EXPLICITLY for every kind so a stray REGCIP_REPIN / REGCIP_NO_MUT in the parent's environment can never leak in:
    #   eval    -> MUT_SKIP=1 REGCIP_REPIN=1       (the only mode that honours the re-pin)
    #   norepin -> REGCIP_NO_MUT=1 REGCIP_REPIN=1  (REPIN WITHOUT MUT_SKIP: must be ignored; NO_MUT only stops the child recursing)
    #   others  -> MUT_SKIP=1 REGCIP_REPIN=
    #   ambient -> MUT_SKIP=1 REGCIP_REPIN=1 REGCIP_NO_MUT=1 and NO marker: every seam must be ignored, the FULL suite runs
    #   forged  -> the same trio with a marker file that is well-formed but STALE (parent=0): ignored the same way
    # Every kind other than ambient/forged carries the harness marker; ambient/forged carry REGCIP_AMBIENT_NESTED so the
    # nested full run does not spawn ambient children of its own (its two ambient rows then fail closed by design).
    local c_skip=1 c_repin="" c_nomut="" c_marker="$HARNESS_MARKER" c_nested=""
    [ "$expect" = eval ] && c_repin=1
    if [ "$expect" = norepin ]; then c_skip=""; c_repin=1; c_nomut=1; fi
    if [ "$expect" = ambient ]; then c_repin=1; c_nomut=1; c_marker=""; c_nested=1; fi
    if [ "$expect" = forged ]; then c_repin=1; c_nomut=1; c_marker="$STALE_MARKER"; c_nested=1; fi
    REGCIP_TF="$MUT_DIR/alerts.tf" REGCIP_WF="$MUT_DIR/apply.yml" REGCIP_ZOT="$MUT_DIR/zot.tf" REGCIP_IV="$MUT_DIR/iv.yml" REGCIP_CI="$MUT_DIR/ci.yml" \
      MUT_SKIP="$c_skip" REGCIP_REPIN="$c_repin" REGCIP_NO_MUT="$c_nomut" REGCIP_CHILD_MARKER="$c_marker" REGCIP_AMBIENT_NESTED="$c_nested" bash "$SELF" >"$MUT_DIR/child.log" 2>&1 || rc=$?
    if [ "$expect" = eval ]; then
      # EVALUATOR-ONLY RED: the exact pin was re-pinned to the mutated text (so it is GREEN), and the OFFLINE
      # EVAL row is RED. This is the proof the evaluator, not the whole-text pin, catches the perturbation.
      local clog; clog="$(cat "$MUT_DIR/child.log")"
      if [ "$rc" -ne 0 ] && has '[FAIL] OFFLINE EVAL' "$clog" && ! has '[FAIL] the predicate drifted from the pinned text' "$clog"; then
        ok "evaluator RED (exact pin re-pinned): $label"
      else
        no "evaluator did NOT red with the exact pin neutralised: $label (child rc=$rc)"
      fi
    elif [ "$expect" = ambient ] || [ "$expect" = forged ]; then
      # AMBIENT SEAMS: the trio set without a valid marker must change NOTHING: [SEAM-IGNORED] is printed, no [NO_MUT] /
      # [REPIN] honoured line, the exact pin reds on the mutated predicate, and the child ran the FULL floor.
      local alog; alog="$(cat "$MUT_DIR/child.log")"
      if [ "$rc" -ne 0 ] && has '[SEAM-IGNORED]' "$alog" && has '[FAIL] the predicate drifted from the pinned text' "$alog" \
         && ! has '[REPIN] honoured' "$alog" && ! has '[NO_MUT]' "$alog" && ! has '[FATAL]' "$alog" \
         && has "($FLOOR_FULL assertions, floor $FLOOR_FULL) ===" "$alog"; then
        ok "ambient seams ignored, FULL suite ran, exact pin RED ($expect): $label"
      else
        no "an ambient/forged seam was honoured, or the child did not run the full $FLOOR_FULL: $label (child rc=$rc)"
      fi
    elif [ "$expect" = norepin ]; then
      # REGCIP_REPIN WITHOUT MUT_SKIP must be ignored: the exact-pin row still reds on the mutated predicate, and the
      # child says so loudly instead of silently self-comparing.
      local nlog; nlog="$(cat "$MUT_DIR/child.log")"
      if [ "$rc" -ne 0 ] && has '[FAIL] the predicate drifted from the pinned text' "$nlog" && ! has '[REPIN] honoured' "$nlog"; then
        ok "REPIN ignored without MUT_SKIP (exact pin still RED): $label"
      else
        no "REGCIP_REPIN was honoured outside MUT_SKIP (the exact pin was switched off): $label (child rc=$rc)"
      fi
    elif [ "$expect" = red ]; then
      # RED means a ROW failed in the child, not that the child tripped its own floor or crashed.
      if [ "$rc" -ne 0 ] && has '[FAIL]' "$(cat "$MUT_DIR/child.log")"; then
        ok "mutation RED: $label"
      else
        no "mutation SURVIVED: $label — the rows above pin nothing (child rc=$rc)"
      fi
    else
      [ "$rc" -eq 0 ] && ok "must-pass GREEN: $label" || no "must-pass went RED: $label — the guard is reflow-fragile"
    fi
  }

  # 1 — the negation
  mutate red "M1 drop the NOT of the private negation (private ranges would fire)" tf \
    'sql("AND NOT match(n, ", "AND match(n, ")'
  # 2 — the alternation
  mutate red "M2a drop the 172.16/12 arm of the private alternation" tf \
    'sql("|172[.](1[6-9]|2[0-9]|3[01])[.]", "")'
  mutate red "M2b narrow 3[01] to 3[0]" tf \
    'sql("3[01]", "3[0]")'
  mutate red "M2c drop the 192.168/16 arm" tf \
    'sql("|192[.]168[.]", "")'
  # 3 — the IPv6 clause
  mutate red "M3 remove the IPv6 colon-count clause" tf \
    'sql("OR length(n) - length(replaceAll(n, " + Q + ":" + Q + ", " + Q + Q + ")) >= 2", "OR 0 = 1")'
  # 4 — one producer member
  mutate red "M4a remove the SOLEUR_ZOT_DISK startsWith member (envelope stays)" tf \
    'sql("OR startsWith(raw, " + Q + "{" + DQ + "message" + DQ + ":" + DQ + "SOLEUR_ZOT_DISK " + Q + ")", "OR 0 = 1")'
  mutate red "M4b remove the SOLEUR_ZOT_LOG envelope member (disk stays)" tf \
    'sql("startsWith(raw, " + Q + "{" + DQ + "message" + DQ + ":" + DQ + "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry " + Q + ")", "0 = 1")'
  # 5 — first match -> any occurrence
  mutate red "M5 first-match extract becomes an any-occurrence extractAll over every clientIP" tf \
    'i = s.index(SQLH); j = s.index("\n  SQL\n", i)
blk = s[i:j]
pat = Q + "clientIP[:=]" + DQ + "?([^ ,}" + DQ + "]+)" + Q
old = "[replaceRegexpOne(extract(" + M + ", " + pat + "), " + Q + "^[[]?(::ffff:)?" + Q + ", " + Q + Q + ")]"
assert blk.count(old) == 1, "anchor"
new = "arrayMap(x -> replaceRegexpOne(x, " + Q + "^[[]?(::ffff:)?" + Q + ", " + Q + Q + "), extractAll(" + M + ", " + pat + "))"
s = s[:i] + blk.replace(old, new) + s[j:]'
  # 6 — the envelope prefix
  mutate red "M6a drop host=soleur-registry from the envelope prefix" tf \
    'sql("shipper=zot-log-shipper host=soleur-registry ", "shipper=zot-log-shipper ")'
  mutate red "M6b envelope prefix loses its trailing space" tf \
    'sql("host=soleur-registry " + Q + ")", "host=soleur-registry" + Q + ")")'
  mutate red "M6c disk marker loses its trailing space" tf \
    'sql("SOLEUR_ZOT_DISK " + Q + "))", "SOLEUR_ZOT_DISK" + Q + "))")'
  mutate red "M6d startsWith becomes a substring (positionCaseInsensitive) match" tf \
    'sql("startsWith(raw, ", "positionCaseInsensitive(raw, ", 2)'
  mutate red "M6e the offset-0 envelope opener {message: is dropped" tf \
    'sql("{" + DQ + "message" + DQ + ":" + DQ, "", 2)'
  # 7 — the -target lines
  mutate red "M7a delete the logtail_exploration -target= line" wf \
    'rep("              -target=logtail_exploration.registry_clientip_not_rfc1918 \\\n", "")'
  mutate red "M7b delete the logtail_exploration_alert -target= line" wf \
    'rep("              -target=logtail_exploration_alert.registry_clientip_not_rfc1918 \\\n", "")'
  # 8 — the alerting parameters
  mutate red "M8a paused = true" tf \
    'block("logtail_exploration_alert", "  paused = false\n", "  paused = true\n")'
  mutate red "M8b higher_than becomes lower_than" tf \
    'block("logtail_exploration_alert", DQ + "higher_than" + DQ, DQ + "lower_than" + DQ)'
  mutate red "M8c value above 0" tf \
    'block("logtail_exploration_alert", "value               = 0", "value               = 1")'
  mutate red "M8d confirmation_period above 0" tf \
    'block("logtail_exploration_alert", "confirmation_period = 0", "confirmation_period = 60")'
  mutate red "M8e check_period changed" tf \
    'block("logtail_exploration_alert", "check_period        = 300", "check_period        = 60")'
  mutate red "M8f query_period changed" tf \
    'block("logtail_exploration_alert", "query_period        = 900", "query_period        = 600")'
  mutate red "M8g recovery_period changed" tf \
    'block("logtail_exploration_alert", "recovery_period     = 1800", "recovery_period     = 600")'
  mutate red "M8h on_missing_data no longer treat_as_zero" tf \
    'block("logtail_exploration_alert", DQ + "treat_as_zero" + DQ, DQ + "treat_as_unknown" + DQ)'
  # 9 — source, window, grouping, runbook, incident text
  mutate red "M9a the exploration source is re-pointed to a literal" tf \
    'block("logtail_exploration", "values        = [local.vector_prd_source_id]", "values        = [" + DQ + "2734275" + DQ + "]")'
  mutate red "M9b the time BETWEEN window is dropped" tf \
    'sql("WHERE time BETWEEN {{start_time}} AND {{end_time}}", "WHERE 1 = 1")'
  mutate red "M9c GROUP BY time is dropped" tf \
    'sql("GROUP BY time", "")'
  mutate red "M9d metadata.runbook is removed" tf \
    'block("logtail_exploration_alert", "  metadata = {\n    runbook = local.registry_clientip_not_rfc1918_runbook_url\n  }\n", "")'
  mutate red "M9e incident_cause is removed" tf \
    'i = s.index("resource " + DQ + "logtail_exploration_alert" + DQ + " " + DQ + "registry_clientip_not_rfc1918" + DQ)
j = s.index("\n}\n", i)
blk = s[i:j]
blk2 = re.sub(r"\n  incident_cause = [^\n]*\n", "\n", blk)
assert blk2 != blk, "anchor"
s = s[:i] + blk2 + s[j:]'
  mutate red "M9f incident_cause loses its Runbook: pointer" tf \
    'block("logtail_exploration_alert", " Runbook: ${local.registry_clientip_not_rfc1918_runbook_url}" + DQ, DQ)'
  # 10 — a zot digest bump without re-verifying the field order
  mutate red "M10 zot_image_amd64 is bumped but the suite pin is not" zot \
    'm = re.search(r"(\n  zot_image_amd64 = " + DQ + r"[^" + DQ + r"]*@sha256:)([0-9a-f]{63})([0-9a-f])" + DQ, s)
assert m, "anchor"
s = s[:m.start()] + m.group(1) + m.group(2) + ("0" if m.group(3) != "0" else "1") + DQ + s[m.end():]'
  # 11 — the registration
  mutate red "M11 this suite's registration is removed from infra-validation.yml" iv \
    'rep("        run: bash apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh\n", "        run: echo removed\n")'
  mutate red "M11b this suite's registration is commented out" iv \
    'rep("        run: bash apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh\n", "        # run: bash apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh\n")'
  mutate red "M11c the registered step becomes non-blocking (continue-on-error: true)" iv \
    'rep("        run: bash apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh\n", "        continue-on-error: true\n        run: bash apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh\n")'
  mutate red "M11d the registered step becomes conditional (if: false)" iv \
    'rep("      - name: Run registry non-RFC1918 clientIP alert drift guard (#7530)\n", "      - name: Run registry non-RFC1918 clientIP alert drift guard (#7530)\n        if: false\n")'
  mutate red "M11e the registered step's JOB becomes unconditional-false (job-level if: false)" iv \
    'rep("  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != " + Q + "true" + Q + "\n", "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: false\n")'
  mutate red "M11f the registered step is MOVED under notify-main-failure (a conditional job that never runs on a PR)" iv \
    'run = "        run: bash apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh\n"
a = s.index("      # (#7530) The registry non-RFC1918 clientIP Logs alert:")
b = s.index(run) + len(run)
step = s[a:b]
s = s[:a] + s[b:]
assert s.rstrip("\n").rsplit("\n", 1)[-1].startswith("          resend-api-key"), "notify-main-failure is no longer the last job"
s = s.rstrip("\n") + "\n\n" + step'
  mutate red "M11g a job-level continue-on-error is placed AFTER the job's steps (key order is free in YAML)" iv \
    'rep("          fi\n\n  # Aggregator (#8736): the single verdict", "          fi\n    continue-on-error: true\n\n  # Aggregator (#8736): the single verdict")'
  mutate red "M11h the hosting job's runs-on changes" iv \
    'rep("  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != " + Q + "true" + Q + "\n    runs-on: ubuntu-24.04\n", "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != " + Q + "true" + Q + "\n    runs-on: self-hosted\n")'
  # 11 (continued) — the CI-dead guard reads the step's and the job's KEYS, the header shape and the aggregator.
  # RUN/HOSTH are shared by the rows below. A header with a trailing comment or a quoted id is still the same job.
  IV_PRE='RUN = "        run: bash apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh\n"
HOSTH = "  deploy-script-tests-fixed:\n    needs: detect-changes\n    if: needs.detect-changes.outputs.pr_duplicate != " + Q + "true" + Q + "\n    runs-on: ubuntu-24.04\n"
AFTER = "          fi\n\n  # Aggregator (#8736): the single verdict"
'
  mutate red "S1 the registered step gets shell: /bin/true {0} (the run line is untouched, the suite never executes)" iv \
    "$IV_PRE"'rep(RUN, RUN + "        shell: /bin/true {0}\n")'
  mutate red "S2 the hosting job gets defaults.run.shell: /bin/true {0}" iv \
    "$IV_PRE"'rep(HOSTH, HOSTH + "    defaults:\n      run:\n        shell: /bin/true {0}\n")'
  mutate red "S3 the registered step gets an env: that redirects REGCIP_TF" iv \
    "$IV_PRE"'rep(RUN, RUN + "        env:\n          REGCIP_TF: /dev/null\n")'
  mutate red "S4 the registered step gets a working-directory:" iv \
    "$IV_PRE"'rep(RUN, RUN + "        working-directory: /tmp\n")'
  mutate red "S5 the hosting job gets a container: (a different runtime for the guard)" iv \
    "$IV_PRE"'rep(HOSTH, HOSTH + "    container: alpine\n")'
  mutate red "S6 the workflow gets a top-level defaults.run.shell" iv \
    'rep("\nenv:\n  TERRAFORM_VERSION", "\ndefaults:\n  run:\n    shell: /bin/true {0}\nenv:\n  TERRAFORM_VERSION")'
  mutate red "S7 the workflow-level env names a suite seam (REGCIP_TF)" iv \
    'rep("env:\n  TERRAFORM_VERSION: " + DQ + "1.10.5" + DQ + "\n", "env:\n  TERRAFORM_VERSION: " + DQ + "1.10.5" + DQ + "\n  REGCIP_TF: /dev/null\n")'
  mutate green "HC1 the hosting job header carries a trailing comment (the step must still attach to THIS job)" iv \
    "$IV_PRE"'rep(HOSTH, HOSTH.replace("fixed:\n", "fixed: # hosts the infra drift guards\n", 1))'
  mutate green "HQ1 the hosting job header is a quoted id" iv \
    "$IV_PRE"'rep(HOSTH, HOSTH.replace("  deploy-script-tests-fixed:", "  " + DQ + "deploy-script-tests-fixed" + DQ + ":", 1))'
  mutate red "HC2 header with a trailing comment AND a job-level continue-on-error after the steps (must not attach to the previous job)" iv \
    "$IV_PRE"'rep(HOSTH, HOSTH.replace("fixed:\n", "fixed: # note\n", 1))
rep(AFTER, "          fi\n    continue-on-error: true\n\n  # Aggregator (#8736): the single verdict")'
  mutate red "HQ2 quoted header AND if: false on the job" iv \
    "$IV_PRE"'rep(HOSTH, HOSTH.replace("  deploy-script-tests-fixed:", "  " + DQ + "deploy-script-tests-fixed" + DQ + ":", 1).replace("!= " + Q + "true" + Q, "!= " + Q + "true" + Q + " && false", 1))'
  mutate red "A1 the aggregator no longer lists the hosting job in needs:" iv \
    'rep("needs: [detect-changes, deploy-script-tests, deploy-script-tests-fixed]", "needs: [detect-changes, deploy-script-tests]")'
  mutate red "A2 the aggregator entries array drops the hosting job" iv \
    'rep(" " + DQ + "deploy-script-tests-fixed:$FIXED_RESULT" + DQ, "")'
  mutate red "A3 the aggregator no longer reads the hosting job's result" iv \
    'rep("          FIXED_RESULT: ${{ needs.deploy-script-tests-fixed.result }}\n", "")'
  mutate red "A4 the aggregator loses its always() (an upstream failure would skip it)" iv \
    'rep("if: always() && needs.detect-changes", "if: needs.detect-changes")'
  # 12 — evaluator-only rows: the exact pin is re-pinned, only the offline evaluator can red
  mutate eval "E1 the dotted-IPv4 shape gate loses its ^ anchor (evaluator reds with the pin neutralised)" tf \
    'sql("match(n, " + Q + "^[0-9]{1,3}([.]", "match(n, " + Q + "[0-9]{1,3}([.]")'
  mutate eval "E2 the private alternation loses its ^ anchor (evaluator reds with the pin neutralised)" tf \
    'sql("NOT match(n, " + Q + "^(10[.]|", "NOT match(n, " + Q + "(10[.]|")'
  mutate eval "E3 the IPv6 colon threshold becomes >= 3 (evaluator reds with the pin neutralised)" tf \
    'sql(">= 2,", ">= 3,")'
  mutate eval "E4 the private 10 arm loses its dot, so 100.x.y.z is private (evaluator reds with the pin neutralised)" tf \
    'sql("^(10[.]|", "^(10|")'
  # 13 — the re-pin seam is honoured ONLY under MUT_SKIP: with REGCIP_REPIN set and MUT_SKIP unset the exact pin still reds
  mutate norepin "N1 REGCIP_REPIN=1 without MUT_SKIP on a mutated predicate (IPv6 threshold >= 3)" tf \
    'sql(">= 2,", ">= 3,")'
  # 13b — AMBIENT seams: the trio set in a plain shell (no marker, or a stale one) is ignored. The child runs the FULL suite on a
  # predicate that can never fire (an aggregate-clause drift: the exact pin is the only red row for it), so a seam that
  # was honoured would exit 0 with the base rows only. Each of these two rows costs one full child run.
  if [ -n "${REGCIP_AMBIENT_NESTED:-}" ]; then
    printf '[NESTED] REGCIP_AMBIENT_NESTED is set: the ambient-seam rows cannot nest, so they fail closed here (expected only inside their own child run)\n'
    no "ambient-seam row cannot run nested (REGCIP_AMBIENT_NESTED is set)"
    no "forged-marker row cannot run nested (REGCIP_AMBIENT_NESTED is set)"
  else
    mutate ambient "F3a MUT_SKIP=1 REGCIP_REPIN=1 REGCIP_NO_MUT=1 with no marker, GROUP BY time HAVING count(*) > 100000 (never fires)" tf \
      'sql("GROUP BY time", "GROUP BY time HAVING count(*) > 100000")'
    mutate forged "F3b the same trio with a well-formed but STALE marker (parent=0)" tf \
      'sql("GROUP BY time", "GROUP BY time HAVING count(*) > 100000")'
  fi
  # 14 — producer parity
  mutate red "P1 the shipper tag in cloud-init-registry.yml is renamed (the anchor would match nothing)" ci \
    'rep("ship " + DQ + "SOLEUR_ZOT_LOG shipper=zot-log-shipper host=", "ship " + DQ + "SOLEUR_ZOT_LOG shipper=zot-log-shipper2 host=")'
  mutate red "P2 the registry server is renamed in zot-registry.tf (the host-scoped anchor would match nothing)" zot \
    'i = s.index("resource " + DQ + "hcloud_server" + DQ + " " + DQ + "registry" + DQ)
j = s.index("name        = " + DQ + "soleur-registry" + DQ, i)
s = s[:j] + "name        = " + DQ + "soleur-registry-2" + DQ + s[j + len("name        = " + DQ + "soleur-registry" + DQ):]'
  mutate red "P3a the shipper's envelope key is renamed (body={message: -> {msg:), so offset 0 no longer starts {message:" ci \
    'rep("body=" + DQ + "{" + chr(92) + DQ + "message" + chr(92) + DQ + ":" + chr(92) + DQ + "$line" + chr(92) + DQ + "}" + DQ, "body=" + DQ + "{" + chr(92) + DQ + "msg" + chr(92) + DQ + ":" + chr(92) + DQ + "$line" + chr(92) + DQ + "}" + DQ)'
  mutate red "P3b the disk heartbeat's envelope key is renamed (its own --data-raw body)" ci \
    'o = "--data-raw " + DQ + "{" + chr(92) + DQ + "message" + chr(92) + DQ + ":" + chr(92) + DQ + "$LINE" + chr(92) + DQ + "}" + DQ
i = s.index(o)
s = s[:i] + o.replace("message", "msg") + s[i + len(o):]'
  mutate red "P4 another key is put FIRST in the disk heartbeat's envelope (offset 0 is no longer {message:)" ci \
    'o = "--data-raw " + DQ + "{" + chr(92) + DQ + "message" + chr(92) + DQ + ":" + chr(92) + DQ + "$LINE" + chr(92) + DQ + "}" + DQ
i = s.index(o)
n = "--data-raw " + DQ + "{" + chr(92) + DQ + "level" + chr(92) + DQ + ":" + chr(92) + DQ + "info" + chr(92) + DQ + "," + chr(92) + DQ + "message" + chr(92) + DQ + ":" + chr(92) + DQ + "$LINE" + chr(92) + DQ + "}" + DQ
s = s[:i] + n + s[i + len(o):]'
  mutate red "P5a the real disk-heartbeat LINE= assignment is commented out (its literal survives, in a comment)" ci \
    'o = "      LINE=" + DQ + "SOLEUR_ZOT_DISK pcent="
assert s.count(o) == 1, "anchor"
s = s.replace(o, "      # LINE=" + DQ + "SOLEUR_ZOT_DISK pcent=")'
  mutate red "P5b the disk head literals are split across two lines (adjacent to nothing on one line)" ci \
    'o = " host=$(hostname) zot_last_err=$ZOT_LAST_ERR" + DQ
assert s.count(o) == 1, "anchor"
s = s.replace(o, DQ + "\n      LINE=" + DQ + "$LINE host=$(hostname) zot_last_err=$ZOT_LAST_ERR" + DQ)'
  # extractor and instrument
  mutate red "H1 the heredoc the extractor reads is renamed (extracted SQL empty)" tf \
    'rep(SQLH, "registry_clientip_not_rfc1918_sql_v2 = <<-SQL")'
  mutate red "H4 a semantic edit that keeps every substring: 172.15 joins the private arm" tf \
    'sql("172[.](1[6-9]|2[0-9]|3[01])[.]", "172[.](1[5-9]|2[0-9]|3[01])[.]")'
  # must-pass: reflow, rename, comment-only and incident wording
  mutate green "H2 whitespace reflow of the heredoc (joined lines, extra blank lines, new indentation)" tf \
    'sql("\n      AND (startsWith", " AND\n\n\n          (startsWith")
sql("\n        OR startsWith", "   OR     startsWith")
sql("\n    FROM {{source}}", "\n\n  FROM    {{source}}")'
  # H3 is must-pass for THIS suite only: it finds the predicate through the exploration's own reference. A
  # rename ALSO needs the follow-through probe's hard-coded LOCAL updated; the local_parity row in
  # scripts/followthroughs/registry-clientip-alert-7530.test.sh enforces that, not this file.
  mutate green "H3 the predicate local is renamed everywhere (the resource still references it; the probe's LOCAL must follow, see local_parity)" tf \
    'rep("registry_clientip_not_rfc1918_sql", "regcip_predicate", 2)'
  mutate green "H5 a comment-only edit to the .tf" tf \
    'rep("# WHAT IT DETECTS. zot logs", "# WHAT IT DETECTS (reworded). zot logs")'
  mutate green "H6 the incident wording changes but keeps its Runbook: pointer" tf \
    'block("logtail_exploration_alert", "The registry plane shipped a clientIP outside RFC1918", "A non-private client address was shipped by the registry plane")'
fi

_floor=$FLOOR_FULL
[ -n "$E_SKIP$E_NOMUT" ] && _floor=$FLOOR_CHILD
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== registry-clientip-not-rfc1918-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
