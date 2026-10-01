#!/usr/bin/env bash
# Guard 1 for the Better Stack Logs alert that pages on SOLEUR_*_SEND_FAILED / _REFUSED rows
# from the web-1 monitor units (#8097, ADR-218).
#
# THE PROPERTY, in one sentence: every PRIORITY-2 `SOLEUR_` row that can reach Logs source
# 2457081 is either a paging class ({_SEND_FAILED, _REFUSED}, emitted through a crit
# `emit_refusal()`) or a documented never-page class ({SKIPPED, _HALT}), the alert predicate
# matches exactly the paging classes at PRIORITY 2 and nothing wider, and the two artifacts
# that must agree with the predicate (the exploration's source, the probe line) do.
#
# THE ASSEMBLY — every path a marker can take, and the check that covers it:
#
#   (1) THE PREDICATE — the single `sql_query` of `resource "logtail_exploration"
#       "monitor_send_failed"`, resolved through its `local.<name>` heredoc. Three anchors
#       (PRIORITY = '2', the `SOLEUR_` prefix, exactly ONE `multiSearchAny`), the needle list
#       parsed AS A SET == {_SEND_FAILED, _REFUSED}, and a CONJUNCTION-only WHERE: no `OR`,
#       `NOT`, `LIKE`/`ILIKE`, `match(`, `position(`, `multiMatchAny`, `multiSearchAnyCase…`,
#       `hasAny` — an appended `OR multiSearchAny(…SKIPPED…)` leaves every anchor present and
#       is the exact widening the file's header forbids. The exploration's `variable.values`
#       must reference `local.vector_prd_source_id` (pinned to vector.toml's sink), its query's
#       `source_variable` must be that variable, and the alert's `exploration_id` must point at
#       THIS exploration — an identity that is present but re-pointed passes a presence check.
#
#   (2) THE EMITTERS — a repo-wide CRIT CENSUS over every non-test `infra/*.sh` and
#       `infra/cloud-init*.yml` (comment-stripped): every `logger` at crit in ANY form
#       (`-p user.crit`, `-p crit`, `-p 2`, `-p daemon.crit`, `--priority …`), every
#       `systemd-cat -p crit`, and every `'<0..2>'` SyslogLevelPrefix literal. Each `SOLEUR_`
#       token on such a line must be a paging class routed through `emit_refusal`, or a
#       never-page class; anything else is an UNCLASSIFIED crit marker (a new class that will
#       never page and is documented nowhere). A crit line carrying a `$variable` message
#       outside a recognised `emit_refusal()` body is a second emit path the definer check
#       cannot see. Definers are discovered in every shape bash accepts (`emit_refusal() {`,
#       `function emit_refusal {`, indented, one-liner); the LAST definition in a file wins,
#       as in bash; a file that MENTIONS `emit_refusal` (a caller sourcing it from a lib) with
#       no recognised definition fails loudly. A definer that never calls `logger` cannot reach
#       journald and must be NAMED in NON_CRIT_ALLOWLIST with a reason. Every paging-class
#       literal anywhere in the walk must sit on an `emit_refusal` call line in a crit-definer
#       file — or be in NON_PAGING_MARKERS (a `_REFUSED` that is deliberately emitted at
#       notice/stdout and must never become crit; the allowlist is checked for staleness and
#       for promotion). Direct ingest posters (`{"message":…}` payloads that bypass Vector) must
#       carry no `PRIORITY` key, or a host that runs no Vector could page through the rule.
#
#   (3) THE PROBE — `terraform_data.send_failed_alert_probe`'s `logger` line in server.tf must
#       be crit, carry a paging-class marker with `synthetic=1 probe_rev=${local…}`, and be
#       triggered only by `local.monitor_send_failed_probe_rev` (digits-only).
#
# NON-VACUITY: the census must find at least MIN_CASES distinct paging-class markers (6 today:
# four units × their SEND_FAILED/REFUSED literals) — a parse that silently matches nothing fails
# loudly instead of reporting a clean sweep of an empty set.
#
# Every assertion prints a DISTINCT [FAIL] string — the mutation battery
# (betterstack-send-failed-alert-mutation.test.sh) attributes each mutation to the check that
# caught it; a bare non-zero exit would credit crashes as detections.
#
# Seams (the battery points them at sandbox copies; CI never sets them):
#   GUARD_TF          betterstack-logs-alerts.tf
#   GUARD_SCRIPTS_DIR the infra directory whose non-test *.sh and cloud-init*.yml are walked
#   GUARD_SERVER_TF   server.tf (the probe resource)
#   GUARD_VECTOR_TOML vector.toml (the sink uri the source id must equal)
#   GUARD_POSTER_DIRS space-separated dirs whose non-test *.sh are scanned for direct-ingest
#                     payloads carrying a PRIORITY key (default: infra + scripts + followthroughs)
#
# Known limit, shared with the parity guard's stripper: an unbalanced apostrophe in an unquoted
# heredoc/regex desynchronises comment stripping for the rest of that file. Leaked comment lines
# are dropped by their leading `#` before any check reads them, so a commented-out crit logger
# cannot count as crit.
#
# No credentials, no network: the suite reads repo files only.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || exit 2
INFRA="$ROOT/apps/web-platform/infra"
GUARD_TF="${GUARD_TF:-$INFRA/betterstack-logs-alerts.tf}"
GUARD_SCRIPTS_DIR="${GUARD_SCRIPTS_DIR:-$INFRA}"
GUARD_SERVER_TF="${GUARD_SERVER_TF:-$INFRA/server.tf}"
GUARD_VECTOR_TOML="${GUARD_VECTOR_TOML:-$INFRA/vector.toml}"
GUARD_POSTER_DIRS="${GUARD_POSTER_DIRS:-$GUARD_SCRIPTS_DIR $ROOT/scripts $ROOT/scripts/followthroughs}"

for f in "$GUARD_TF" "$GUARD_SERVER_TF" "$GUARD_VECTOR_TOML"; do
  [[ -f "$f" ]] || { echo "FATAL: $f not found" >&2; exit 2; }
done
[[ -d "$GUARD_SCRIPTS_DIR" ]] || { echo "FATAL: $GUARD_SCRIPTS_DIR is not a directory" >&2; exit 2; }

python3 - "$GUARD_TF" "$GUARD_SCRIPTS_DIR" "$GUARD_SERVER_TF" "$GUARD_VECTOR_TOML" "$GUARD_POSTER_DIRS" <<'PYEOF'
import os, re, sys

TF, SCRIPTS_DIR, SERVER_TF, VECTOR_TOML, POSTER_DIRS = sys.argv[1:6]
MIN_CASES = 6

npass = nfail = 0
def ok(m):
    global npass; npass += 1; print(f"[ok] {m}")
def no(m):
    global nfail; nfail += 1; print(f"[FAIL] {m}", file=sys.stderr)

# ── Comment stripping: string-aware, trailing-comment-aware (parity-guard convention) ───
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

def drop_leaked_comments(text):
    """A desynchronised stripper leaks whole comment lines; they still start with `#`. Backslash
    continuations are joined so a `logger … \\` + `"SOLEUR_…"` pair is ONE line to the census."""
    text = re.sub(r'\\\n[ \t]*', ' ', text)
    return '\n'.join(l for l in text.split('\n') if not l.lstrip().startswith('#'))

def read(p): return open(p, encoding="utf-8").read()
def stripped(p): return drop_leaked_comments(strip_comments(read(p)))

# String-aware, brace-matched HCL block extraction by resource type + name → list of bodies.
def hcl_blocks(text, kind, name):
    out = []
    for m in re.finditer(r'resource\s+"%s"\s+"%s"\s*\{' % (re.escape(kind), re.escape(name)), text):
        i = m.end(); depth = 1; in_str = False
        while i < len(text) and depth:
            c = text[i]
            if in_str:
                if c == '\\': i += 1
                elif c == '"': in_str = False
            elif c == '"': in_str = True
            elif c == '{': depth += 1
            elif c == '}': depth -= 1
            i += 1
        out.append(text[m.end():i - 1])
    return out

# ── §1. The predicate ────────────────────────────────────────────────────────────────
NEEDLES_EXPECTED = {"_SEND_FAILED", "_REFUSED"}
tf = stripped(TF)

def resolve_sql(res_body, whole):
    """The `sql_query` attribute → the SQL text. Accepts `local.<name>` anywhere in the RHS
    (so a `replace(trimspace(local.x), …)` normalisation resolves) or a direct heredoc."""
    m = re.search(r'\bsql_query\s*=\s*([^\n]+)', res_body)
    if not m: return None
    rhs = m.group(1).strip()
    lm = re.search(r'\blocal\.([A-Za-z0-9_]+)', rhs)
    if lm:
        loc = lm.group(1)
        hm = re.search(r'\b%s\s*=\s*<<-?\s*([A-Za-z_][A-Za-z0-9_]*)[ \t]*\n(.*?)\n[ \t]*\1[ \t]*$' % re.escape(loc), whole, re.S | re.M)
        return hm.group(2) if hm else None
    hm = re.match(r'<<-?\s*([A-Za-z_][A-Za-z0-9_]*)\s*$', rhs)
    if hm:
        tag = hm.group(1)
        hb = re.search(r'\bsql_query\s*=\s*<<-?\s*%s[ \t]*\n(.*?)\n[ \t]*%s[ \t]*$' % (tag, tag), res_body, re.S | re.M)
        return hb.group(1) if hb else None
    return None

expl = hcl_blocks(tf, "logtail_exploration", "monitor_send_failed")
sqls = [s for s in (resolve_sql(b, tf) for b in expl) if s and s.strip()]
if len(sqls) != 1:
    no(f"sql_query: expected exactly 1 extraction, got {len(sqls)} (resource logtail_exploration.monitor_send_failed with a non-empty sql_query)")
    sql = ""
else:
    ok("sql_query: exactly 1 extraction from logtail_exploration.monitor_send_failed")
    sql = sqls[0]

nows = re.sub(r'\s+', '', sql)
def anchor(label, literal):
    if re.sub(r'\s+', '', literal) in nows: ok(f"anchor present: {label}")
    else: no(f"anchor absent: {label}")

needles = set()
if sql:
    anchor("PRIORITY", "JSONExtractString(raw, 'PRIORITY') = '2'")
    anchor("SOLEUR_ prefix", "startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_')")
    n_msa = len(re.findall(r'multiSearchAny\(', nows))
    if n_msa == 1: ok("anchor present: exactly one multiSearchAny")
    else: no(f"anchor absent: multiSearchAny (expected exactly 1 occurrence, got {n_msa})")
    # CONJUNCTION ONLY. The WHERE body runs from WHERE to GROUP BY; the template variables carry
    # no operators, so any disjunction / negation / wildcard function is a widening.
    wm = re.search(r'\bWHERE\b(.*?)(\bGROUP\s+BY\b|$)', sql, re.S | re.I)
    where = wm.group(1) if wm else sql
    for label, pat in [
        ("OR", r'\bOR\b'), ("NOT", r'\bNOT\b'), ("LIKE/ILIKE", r'\bI?LIKE\b'),
        ("match(", r'\bmatch\('), ("position(", r'\bposition\('), ("multiMatchAny", r'\bmultiMatchAny'),
        ("multiSearchAnyCaseInsensitive", r'\bmultiSearchAnyCaseInsensitive'), ("hasAny", r'\bhasAny\b'),
    ]:
        if re.search(pat, where, re.I): no(f"predicate widened: {label} in WHERE")
        else: ok(f"predicate has no {label}")
    nm = re.search(r"multiSearchAny\(JSONExtractString\(raw,'message'\),\[(.*?)\]\)", nows)
    if nm: needles = set(re.findall(r"'([^']*)'", nm.group(1)))
    if needles == NEEDLES_EXPECTED:
        ok(f"needle set {{{','.join(sorted(needles))}}} == {{{','.join(sorted(NEEDLES_EXPECTED))}}}")
    else:
        no(f"needle set {{{','.join(sorted(needles))}}} != {{{','.join(sorted(NEEDLES_EXPECTED))}}}")
needles_eff = needles if needles else NEEDLES_EXPECTED

# ── §1b. Identities: exploration ↔ source local ↔ alert, plus the alert's attributes ─────
if len(expl) == 1:
    eb = expl[0]
    if re.search(r'\bvalues\s*=\s*\[\s*local\.vector_prd_source_id\s*\]', eb): ok("exploration source variable references local.vector_prd_source_id")
    else: no("exploration source not pinned: variable.values must be [local.vector_prd_source_id]")
    if re.search(r'\bvariable_type\s*=\s*"source"', eb) and re.search(r'\bname\s*=\s*"source"', eb) and re.search(r'\bsource_variable\s*=\s*"source"', eb):
        ok("exploration query reads the `source` variable")
    else: no("exploration query/variable wiring: expected variable name=\"source\" type=\"source\" and query source_variable=\"source\"")
alerts = hcl_blocks(tf, "logtail_exploration_alert", "monitor_send_failed")
if len(alerts) != 1:
    no(f"alert: expected exactly 1 logtail_exploration_alert.monitor_send_failed, got {len(alerts)}")
    ab = ""
else:
    ok("alert: exactly 1 logtail_exploration_alert.monitor_send_failed")
    ab = alerts[0]
if ab:
    if re.search(r'\bexploration_id\s*=\s*logtail_exploration\.monitor_send_failed\.id\b', ab): ok("alert exploration_id points at logtail_exploration.monitor_send_failed")
    else: no("alert exploration_id not pinned to logtail_exploration.monitor_send_failed.id")
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

# ── §2. The emitters — repo-wide crit census + definer discovery ───────────────────────
NON_CRIT_ALLOWLIST = {
    "resend-inbound-bootstrap.sh":
        "runs in GitHub Actions (infra-validation.yml), not on web-1; its emit_refusal() is "
        "stdout/stderr only and its _REFUSED marker never enters journald",
}
# Paging-class LITERALS that are deliberately emitted BELOW crit (never page) — each must stay
# below crit; promoting one to crit makes it page and fails here.
NON_PAGING_MARKERS = {
    "SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED": "inngest-cutover-flip.sh: bare `logger -t` (user.notice, PRIORITY 5) — a cutover seam refusal, not a send failure",
    "SOLEUR_RESEND_INBOUND_BOOTSTRAP_REFUSED": "resend-inbound-bootstrap.sh: CI-only, stdout only (see NON_CRIT_ALLOWLIST)",
    "SOLEUR_INNGEST_LUKS_CUTOVER_SEAM_REFUSED": "inngest-luks-cutover.sh (#6894): bare `logger -t` (user.notice, PRIORITY 5) — the same shape and the same class as the flip's seam refusal above: a fixture-seam name was present in the environment without --fixture-seams and was ignored. It is a provisioning/config finding, not a failed send, and the class that DOES page for this host is the wrong-volume alert in betterstack-logs-alerts.tf",
}
SOLEUR_RE = re.compile(r'\bSOLEUR_[A-Z0-9_]+')
CRIT_RE = re.compile(r'\bSOLEUR_[A-Z0-9_]*(?:_SEND_FAILED|_REFUSED)[A-Z0-9_]*')
FORBID_RE = re.compile(r'\bSOLEUR_[A-Z0-9_]*(?:SKIPPED|_HALT)[A-Z0-9_]*')
# Every spelling of "log at crit": logger -p/--priority with an optional facility, crit or 2;
# systemd-cat -p crit|2; a SyslogLevelPrefix literal '<0>'..'<2>'.
CRIT_LINE_RE = re.compile(
    r'\blogger\b[^\n|]*?(?:-p[ \t]*=?[ \t]*|--priority[ \t=]+)(?:[a-z0-9]+\.)?(?:crit|2)\b'
    r'|\bsystemd-cat\b[^\n|]*?-p[ \t]*=?[ \t]*(?:[a-z0-9]+\.)?(?:crit|2)\b'
    r'|[\'"]<[0-2]>')
USER_CRIT_RE = re.compile(r'\blogger\b[^\n|]*?(?:-p[ \t]*=?[ \t]*|--priority[ \t=]+)user\.crit\b')
DEF_RE = re.compile(
    r'^[ \t]*(?:function[ \t]+)?emit_refusal[ \t]*(?:\(\))?[ \t]*\{[ \t]*\n(.*?)^[ \t]*\}[ \t]*$'
    r'|^[ \t]*(?:function[ \t]+)?emit_refusal[ \t]*(?:\(\))?[ \t]*\{([^\n]*?)\}[ \t]*$',
    re.S | re.M)
# `\"PRIORITY\":` inside a bash double-quoted payload keeps its escaping backslashes.
PRIORITY_KEY_RE = re.compile(r'\\?["\']PRIORITY\\?["\'][ \t]*:')

def walk(d, exts):
    if not os.path.isdir(d): return []
    return sorted(f for f in os.listdir(d) if any(f.endswith(e) for e in exts) and not f.endswith(".test.sh"))

files = {}
for fn in walk(SCRIPTS_DIR, (".sh",)) + [f for f in walk(SCRIPTS_DIR, (".yml", ".yaml")) if f.startswith("cloud-init")]:
    files[fn] = stripped(os.path.join(SCRIPTS_DIR, fn))

crit_markers = set()
definers = {}            # fn -> body of the LAST recognised definition
crit_definer_files = set()
definer_body_lines = {}  # fn -> set of stripped lines inside the definer body
for fn, body_all in files.items():
    defs = DEF_RE.findall(body_all)
    if defs:
        d = defs[-1]; fbody = d[0] if d[0] else d[1]
        definers[fn] = fbody
        definer_body_lines[fn] = {l.strip() for l in fbody.split('\n') if l.strip()}
        if re.search(r'\blogger\b', fbody):
            if USER_CRIT_RE.search(fbody) or CRIT_LINE_RE.search(fbody):
                ok(f"emitter crit: {fn}"); crit_definer_files.add(fn)
            else:
                no(f"emitter not crit: {fn} (emit_refusal() calls logger without a crit priority)")
        elif fn in NON_CRIT_ALLOWLIST:
            ok(f"emitter non-crit (allowlisted): {fn}")
        else:
            no(f"emitter not crit: {fn} (emit_refusal() never calls logger and is not in NON_CRIT_ALLOWLIST)")
    elif re.search(r'\bemit_refusal\b', body_all):
        no(f"emitter unparseable: {fn} mentions emit_refusal but no recognised definition shape (sourced from a lib? unusual shape?)")

for fn in sorted(NON_CRIT_ALLOWLIST):
    if fn not in definers: no(f"non-crit allowlist stale: {fn} defines no emit_refusal() (or is absent)")
    elif re.search(r'\blogger\b', definers[fn]): no(f"non-crit allowlist stale: {fn} now calls logger — remove the entry")

# The census.
seen_non_paging = set()
for fn, body_all in files.items():
    in_def = definer_body_lines.get(fn, set())
    for line in body_all.split('\n'):
        s = line.strip()
        if not s: continue
        is_crit = bool(CRIT_LINE_RE.search(s))
        toks = SOLEUR_RE.findall(s)
        if is_crit:
            for tok in sorted(set(toks)):
                if tok in NON_PAGING_MARKERS:
                    no(f"allowlisted non-paging marker emitted at crit: {tok} ({fn})")
                elif any(nd in tok for nd in needles_eff):
                    no(f"needle marker not routed through emit_refusal: {tok} ({fn}) — a crit logger carrying a paging-class literal directly")
                elif FORBID_RE.search(tok):
                    ok(f"never-page class at crit: {tok} ({fn})")
                else:
                    no(f"unclassified crit marker: {tok} ({fn}) — a PRIORITY-2 SOLEUR_ class that is neither paging nor a documented never-page class")
            if not toks and s not in in_def and re.search(r'\$', s):
                no(f"crit logger with a variable message outside emit_refusal: {fn}: {s[:80]}")
        for tok in sorted(set(CRIT_RE.findall(s))):
            if tok in NON_PAGING_MARKERS:
                seen_non_paging.add(tok)
                if is_crit: pass  # already reported above
                else: ok(f"non-paging marker stays below crit: {tok} ({fn})")
                continue
            if fn in crit_definer_files and re.search(r'\bemit_refusal\b', s) and s not in in_def:
                crit_markers.add(tok)
                if any(nd in tok for nd in needles_eff): ok(f"crit marker matches a needle: {tok}")
                else: no(f"crit marker matches no needle: {tok}")
            elif fn in NON_CRIT_ALLOWLIST and re.search(r'\bemit_refusal\b', s):
                no(f"needle marker routed through a NON-crit emit_refusal and not in NON_PAGING_MARKERS: {tok} ({fn})")
            else:
                no(f"needle marker not routed through emit_refusal: {tok} ({fn})")
        for tok in sorted(set(FORBID_RE.findall(s))):
            if fn in crit_definer_files and re.search(r'\bemit_refusal\b', s):
                if any(nd in tok for nd in needles_eff): no(f"forbidden match: {tok}")
                else: ok(f"never-page class matches no needle: {tok}")
for tok in sorted(NON_PAGING_MARKERS):
    if tok not in seen_non_paging: no(f"non-paging allowlist stale: {tok} no longer emitted anywhere in the walk")

# Direct-ingest posters: a JSON payload with a PRIORITY key would page from a host with no Vector.
for d in POSTER_DIRS.split():
    for fn in walk(d, (".sh",)):
        text = files[fn] if (d == SCRIPTS_DIR and fn in files) else stripped(os.path.join(d, fn))
        if PRIORITY_KEY_RE.search(text):
            no(f"direct-ingest payload carries a PRIORITY field: {fn} ({d})")
ok("no direct-ingest payload carries a PRIORITY key")

if not definers:
    no("emitters: discovered 0 emit_refusal() definers — the sweep found nothing")

# ── §3. The synthetic probe in server.tf ─────────────────────────────────────────────
srv = stripped(SERVER_TF)
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
        if USER_CRIT_RE.search(line): ok("probe line is crit")
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

# ── §4. Non-vacuity floor over the DISCOVERED paging-class markers ───────────────────
cases = len(crit_markers)
if cases < MIN_CASES: no(f"markers={cases} < floor {MIN_CASES}")  # SEND_FAILED_ALERT_FLOOR_CHECK
else: ok(f"markers={cases} >= floor {MIN_CASES}")

print(f"=== Summary: {npass} passed, {nfail} failed ({cases} cases) ===")
sys.exit(1 if nfail else 0)
PYEOF
