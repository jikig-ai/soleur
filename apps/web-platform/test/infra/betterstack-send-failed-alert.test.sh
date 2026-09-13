#!/usr/bin/env bash
# Guard 1 for the Better Stack Logs alert that pages on SOLEUR_*_SEND_FAILED / _REFUSED rows
# from the web-1 monitor units (#8097, ADR-218).
#
# WHAT THIS PINS. Two chokepoints, read after string-aware comment stripping:
#
#   (1) THE PREDICATE — the single `sql_query` of `resource "logtail_exploration"
#       "monitor_send_failed"` in betterstack-logs-alerts.tf. It must carry the three anchors
#       (PRIORITY = '2', the `SOLEUR_` prefix, `multiSearchAny`), its needle list parsed AS A
#       SET must equal {_SEND_FAILED, _REFUSED} (order-free), and it must contain no `LIKE`
#       (a wildcard would let `SEND_SKIPPED` — a deliberate, never-paging class — match).
#       The alert's own attributes (treat_as_zero / paused=false / value=0 / higher_than /
#       email / the paid-tier ternary), the exploration's source id against vector.toml's
#       sink, and the digits-only `probe_rev` are pinned in the same pass.
#
#   (2) THE EMITTERS — every non-test infra/*.sh that DEFINES `emit_refusal()` is DISCOVERED
#       (not listed), so a fifth unit is found rather than assumed. A definer whose body calls
#       `logger` must call it at `-p user.crit` (journald PRIORITY 2 is the clause that keeps
#       every foreign `_REFUSED` marker out of the alert). A definer that never calls `logger`
#       cannot reach journald and must be NAMED in NON_CRIT_ALLOWLIST with a reason — a
#       silent exclusion is how a web-1 unit that never pages would ship. For every crit
#       emitter: each `SOLEUR_*_SEND_FAILED` / `SOLEUR_*_REFUSED` literal must match a needle
#       (positive coverage), and each `SOLEUR_*SKIPPED*` / `SOLEUR_*_HALT*` literal must match
#       NONE (the never-page classes). The synthetic probe line in server.tf is held to the
#       same two rules.
#
# NON-VACUITY FLOOR. The sweep must find at least SEND_FAILED_ALERT_MIN_CASES distinct crit
# markers (6 today: four units × their SEND_FAILED/REFUSED literals). A parse that silently
# matches nothing fails loudly instead of reporting a clean sweep of an empty set.
#
# Every assertion prints a DISTINCT [FAIL] string — the mutation battery
# (betterstack-send-failed-alert-mutation.test.sh) attributes each mutation to the check that
# caught it; a bare non-zero exit would credit crashes as detections.
#
# Seams (the battery points them at sandbox copies; CI never sets them):
#   GUARD_TF          betterstack-logs-alerts.tf
#   GUARD_SCRIPTS_DIR the directory whose non-test *.sh are scanned for emit_refusal()
#   GUARD_SERVER_TF   server.tf (the probe resource)
#   GUARD_VECTOR_TOML vector.toml (the sink uri the source id must equal)
#
# No credentials, no network: the suite reads repo files only.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 2
INFRA="$ROOT/apps/web-platform/infra"
GUARD_TF="${GUARD_TF:-$INFRA/betterstack-logs-alerts.tf}"
GUARD_SCRIPTS_DIR="${GUARD_SCRIPTS_DIR:-$INFRA}"
GUARD_SERVER_TF="${GUARD_SERVER_TF:-$INFRA/server.tf}"
GUARD_VECTOR_TOML="${GUARD_VECTOR_TOML:-$INFRA/vector.toml}"
MIN_CASES="${SEND_FAILED_ALERT_MIN_CASES:-6}"

for f in "$GUARD_TF" "$GUARD_SERVER_TF" "$GUARD_VECTOR_TOML"; do
  [[ -f "$f" ]] || { echo "FATAL: $f not found" >&2; exit 2; }
done
[[ -d "$GUARD_SCRIPTS_DIR" ]] || { echo "FATAL: $GUARD_SCRIPTS_DIR is not a directory" >&2; exit 2; }

python3 - "$GUARD_TF" "$GUARD_SCRIPTS_DIR" "$GUARD_SERVER_TF" "$GUARD_VECTOR_TOML" "$MIN_CASES" <<'PYEOF'
import os, re, sys

TF, SCRIPTS_DIR, SERVER_TF, VECTOR_TOML, MIN_CASES = sys.argv[1:6]
MIN_CASES = int(MIN_CASES)

npass = nfail = 0
def ok(m):
    global npass; npass += 1; print(f"[ok] {m}")
def no(m):
    global nfail; nfail += 1; print(f"[FAIL] {m}", file=sys.stderr)

# ── Comment stripping: string-aware, trailing-comment-aware (parity-guard convention) ───
# A `#` starts a comment only outside a quoted string and at line-start or after whitespace
# (protects `http://x#y` and `${VAR#pfx}`); `//` likewise for HCL. Backslash escapes inside
# strings do not desynchronise the scanner.
def strip_comments(text):
    out = []; i = 0; n = len(text); in_str = False; quote = ''
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(text[i + 1]); i += 2; continue
            if c == quote: in_str = False
            i += 1; continue
        if c in '"\'':
            in_str = True; quote = c; out.append(c); i += 1; continue
        if c == '#' and (i == 0 or text[i - 1] in ' \t\n'):
            while i < n and text[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '/' and (i == 0 or text[i - 1] in ' \t\n'):
            while i < n and text[i] != '\n': i += 1
            continue
        out.append(c); i += 1
    return ''.join(out)

def read(p): return open(p, encoding="utf-8").read()

# Brace-matched HCL block extraction by resource type + name. Returns list of bodies.
def hcl_blocks(text, kind, name):
    out = []
    for m in re.finditer(r'resource\s+"%s"\s+"%s"\s*\{' % (re.escape(kind), re.escape(name)), text):
        i = m.end(); depth = 1
        while i < len(text) and depth:
            if text[i] == '{': depth += 1
            elif text[i] == '}': depth -= 1
            i += 1
        out.append(text[m.end():i - 1])
    return out

# ── §1. The predicate ────────────────────────────────────────────────────────────────
NEEDLES_EXPECTED = {"_SEND_FAILED", "_REFUSED"}
tf = strip_comments(read(TF))

# The heredoc body is a LOCAL consumed by the resource; resolve it through the resource's
# `sql_query` attribute so a renamed/removed resource is caught at the resource, not at the
# local (M5). Accept either a direct heredoc, a quoted string, or a `local.<name>` reference.
def resolve_sql(res_body, whole):
    m = re.search(r'\bsql_query\s*=\s*(.+)', res_body)
    if not m: return None
    rhs = m.group(1).strip()
    lm = re.match(r'local\.([A-Za-z0-9_]+)\s*$', rhs)
    if lm:
        loc = lm.group(1)
        hm = re.search(r'\b%s\s*=\s*<<-?\s*([A-Z_][A-Z0-9_]*)\n(.*?)\n\s*\1\b' % re.escape(loc), whole, re.S)
        if hm: return hm.group(2)
        qm = re.search(r'\b%s\s*=\s*"((?:[^"\\]|\\.)*)"' % re.escape(loc), whole)
        return qm.group(1) if qm else None
    hm = re.match(r'<<-?\s*([A-Z_][A-Z0-9_]*)\s*$', rhs)
    if hm:
        tag = hm.group(1)
        hb = re.search(r'\bsql_query\s*=\s*<<-?\s*%s\n(.*?)\n\s*%s\b' % (tag, tag), res_body, re.S)
        return hb.group(1) if hb else None
    qm = re.match(r'"((?:[^"\\]|\\.)*)"', rhs)
    return qm.group(1) if qm else None

expl = hcl_blocks(tf, "logtail_exploration", "monitor_send_failed")
sqls = [s for s in (resolve_sql(b, tf) for b in expl) if s and s.strip()]
if len(sqls) != 1:
    no(f"sql_query: expected exactly 1 extraction, got {len(sqls)} (resource logtail_exploration.monitor_send_failed with a non-empty sql_query)")
    sql = ""
else:
    ok("sql_query: exactly 1 extraction from logtail_exploration.monitor_send_failed")
    sql = sqls[0]

# Whitespace-insensitive anchors (H3): compare with all whitespace removed on both sides.
nows = re.sub(r'\s+', '', sql)
def anchor(label, literal):
    if re.sub(r'\s+', '', literal) in nows: ok(f"anchor present: {label}")
    else: no(f"anchor absent: {label}")
if sql:
    anchor("PRIORITY", "JSONExtractString(raw, 'PRIORITY') = '2'")
    anchor("SOLEUR_ prefix", "startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_')")
    anchor("multiSearchAny", "multiSearchAny(JSONExtractString(raw, 'message'), [")
    if re.search(r'\bLIKE\b', sql, re.I): no("predicate contains LIKE (wildcards let SEND_SKIPPED match)")
    else: ok("predicate contains no LIKE")

needles = set()
nm = re.search(r"multiSearchAny\(JSONExtractString\(raw,'message'\),\[(.*?)\]\)", nows)
if nm:
    needles = set(re.findall(r"'([^']*)'", nm.group(1)))
if sql:
    if needles == NEEDLES_EXPECTED:
        ok(f"needle set {{{','.join(sorted(needles))}}} == {{{','.join(sorted(NEEDLES_EXPECTED))}}}")
    else:
        no(f"needle set {{{','.join(sorted(needles))}}} != {{{','.join(sorted(NEEDLES_EXPECTED))}}}")
# Downstream checks use the needles AS WRITTEN (even when wrong) so a widened needle set is
# attributed by the forbidden-match check too, not only by the set-equality check.
needles_eff = needles if needles else NEEDLES_EXPECTED

# ── §1b. The alert's attributes and the two locals ───────────────────────────────────
alerts = hcl_blocks(tf, "logtail_exploration_alert", "monitor_send_failed")
if len(alerts) != 1:
    no(f"alert: expected exactly 1 logtail_exploration_alert.monitor_send_failed, got {len(alerts)}")
    ab = ""
else:
    ok("alert: exactly 1 logtail_exploration_alert.monitor_send_failed")
    ab = alerts[0]
if ab:
    for label, pat in [
        ("on_missing_data = treat_as_zero", r'\bon_missing_data\s*=\s*"treat_as_zero"'),
        ("paused = false", r'\bpaused\s*=\s*false\b'),
        ("value = 0", r'\bvalue\s*=\s*0\b'),
        ("operator = higher_than", r'\boperator\s*=\s*"higher_than"'),
        ("email = true", r'\bemail\s*=\s*true\b'),
        ("escalation_target ternary on var.betterstack_paid_tier",
         r'escalation_target\s*\{[^}]*var\.betterstack_paid_tier[^}]*\}'),
    ]:
        if re.search(pat, ab, re.S): ok(f"alert attribute: {label}")
        else: no(f"alert attribute absent: {label}")

sm = re.search(r'\bvector_prd_source_id\s*=\s*"([^"]*)"', tf)
vt = strip_comments(read(VECTOR_TOML))
um = re.search(r'\[sinks\.betterstack\](.*?)(?=\n\[|\Z)', vt, re.S)
sink_id = None
if um:
    uu = re.search(r'\buri\s*=\s*"https://s(\d+)\.', um.group(1))
    sink_id = uu.group(1) if uu else None
if not sm:
    no("source id: local.vector_prd_source_id absent")
elif sink_id is None:
    no("source id: could not parse the s<id>. host from vector.toml [sinks.betterstack] uri")
elif sm.group(1) != sink_id:
    no(f"source id != vector.toml sink ({sm.group(1)} vs {sink_id})")
else:
    ok(f"source id == vector.toml sink ({sink_id})")

pm = re.search(r'\bmonitor_send_failed_probe_rev\s*=\s*("[^"]*"|\S+)', tf)
if not pm:
    no("probe_rev: local.monitor_send_failed_probe_rev absent")
elif not re.fullmatch(r'"[0-9]+"', pm.group(1)):
    no(f"probe_rev not digits ({pm.group(1)})")
else:
    ok(f"probe_rev is digits-only ({pm.group(1)})")

# ── §2. The emitters, discovered by definition ───────────────────────────────────────
# A definer whose emit_refusal() never calls `logger` cannot reach journald and therefore
# cannot page; it must be NAMED here with a reason, so the exclusion is a reviewable diff
# rather than a silent gap. A listed script that no longer exists, or that now calls
# logger, fails as STALE.
NON_CRIT_ALLOWLIST = {
    "resend-inbound-bootstrap.sh":
        "runs in GitHub Actions (infra-validation.yml), not on web-1; its emit_refusal() is "
        "stdout/stderr only and its _REFUSED marker never enters journald",
}
CRIT_RE = re.compile(r'\bSOLEUR_[A-Z0-9_]*(?:_SEND_FAILED|_REFUSED)[A-Z0-9_]*')
FORBID_RE = re.compile(r'\bSOLEUR_[A-Z0-9_]*(?:SKIPPED|_HALT)[A-Z0-9_]*')
DEF_RE = re.compile(r'^emit_refusal\s*\(\)\s*\{\s*\n(.*?)^\}', re.S | re.M)

crit_markers = set()
definers = []
for fn in sorted(os.listdir(SCRIPTS_DIR)):
    if not fn.endswith(".sh") or fn.endswith(".test.sh"): continue
    body_all = strip_comments(read(os.path.join(SCRIPTS_DIR, fn)))
    dm = DEF_RE.search(body_all)
    if not dm: continue
    definers.append(fn)
    fbody = dm.group(1)
    calls_logger = re.search(r'\blogger\b', fbody) is not None
    if calls_logger:
        if re.search(r'\blogger\s+-p\s+user\.crit\b', fbody):
            ok(f"emitter crit: {fn}")
        else:
            no(f"emitter not crit: {fn} (emit_refusal() calls logger without -p user.crit)")
            continue
    else:
        if fn in NON_CRIT_ALLOWLIST:
            ok(f"emitter non-crit (allowlisted): {fn}")
        else:
            no(f"emitter not crit: {fn} (emit_refusal() never calls logger and is not in NON_CRIT_ALLOWLIST)")
        continue
    # Crit emitter: positive coverage + never-page classes.
    for tok in sorted(set(CRIT_RE.findall(body_all))):
        crit_markers.add(tok)
        if any(nd in tok for nd in needles_eff): ok(f"crit marker matches a needle: {tok}")
        else: no(f"crit marker matches no needle: {tok}")
    for tok in sorted(set(FORBID_RE.findall(body_all))):
        if any(nd in tok for nd in needles_eff): no(f"forbidden match: {tok}")
        else: ok(f"never-page class matches no needle: {tok}")

for fn in sorted(NON_CRIT_ALLOWLIST):
    if fn not in definers:
        no(f"non-crit allowlist stale: {fn} defines no emit_refusal() (or is absent)")
    else:
        fb = DEF_RE.search(strip_comments(read(os.path.join(SCRIPTS_DIR, fn)))).group(1)
        if re.search(r'\blogger\b', fb):
            no(f"non-crit allowlist stale: {fn} now calls logger — remove the entry")

if not definers:
    no("emitters: discovered 0 emit_refusal() definers — the sweep found nothing")

# ── §3. The synthetic probe in server.tf ─────────────────────────────────────────────
srv = strip_comments(read(SERVER_TF))
probes = hcl_blocks(srv, "terraform_data", "send_failed_alert_probe")
if len(probes) != 1:
    no(f"probe: expected exactly 1 terraform_data.send_failed_alert_probe, got {len(probes)}")
else:
    pb = probes[0]
    lm = re.search(r'"(logger\b[^"]*)"', pb)
    if not lm:
        no("probe line absent: no logger command inside terraform_data.send_failed_alert_probe")
    else:
        line = lm.group(1)
        if re.search(r'\blogger\s+-p\s+user\.crit\b', line): ok("probe line is crit")
        else: no("probe line not crit")
        toks = CRIT_RE.findall(line)
        if toks and all(any(nd in t for nd in needles_eff) for t in toks): ok(f"probe marker matches a needle: {toks[0]}")
        else: no("probe marker matches no needle")
        if 'synthetic=1' in line and 'probe_rev=${local.monitor_send_failed_probe_rev}' in line: ok("probe line carries synthetic=1 probe_rev=<rev>")
        else: no("probe line lacks synthetic=1 probe_rev=${local.monitor_send_failed_probe_rev}")
    if re.search(r'\btriggers_replace\s*=\s*local\.monitor_send_failed_probe_rev\b', pb): ok("probe trigger is local.monitor_send_failed_probe_rev")
    else: no("probe trigger not probe_rev")
    if re.search(r'timestamp\(\)|\brandom_', pb): no("probe block carries a per-run value (timestamp()/random_)")
    else: ok("probe block carries no per-run value")

# ── §4. Non-vacuity floor over the DISCOVERED crit markers ───────────────────────────
cases = len(crit_markers)
if cases < MIN_CASES: no(f"markers={cases} < floor {MIN_CASES}")  # SEND_FAILED_ALERT_FLOOR_CHECK
else: ok(f"markers={cases} >= floor {MIN_CASES}")

print(f"=== Summary: {npass} passed, {nfail} failed ({cases} cases) ===")
sys.exit(1 if nfail else 0)
PYEOF
