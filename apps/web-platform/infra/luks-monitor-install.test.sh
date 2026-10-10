#!/usr/bin/env bash
#
# #8706 — guards for the Terraform-owned delivery of web-1's daily LUKS at-rest probe and the
# Better Stack alert that proves it runs. Plan:
# knowledge-base/project/plans/2026-09-27-fix-luks-monitor-host-timer-never-installed-plan.md
# (§Guard Contract).
#
#   Guard 1 — logtail_exploration_alert.luks_monitor_host_timer_dark (betterstack-logs-alerts.tf):
#     the predicate counts ONLY the host unit's own `OK:` rows (_SYSTEMD_UNIT=luks-monitor.service),
#     so the verify job's SSH-driven rows can never keep it quiet — that masking is how the timer
#     stayed dark for nine weeks. Silence must page (treat_as_zero, lower_than 1) and the window must
#     cover a legitimate 24h30m gap between two timer runs.
#   Guard 2 — terraform_data.luks_monitor_install (workspaces-luks.tf): every delivered file is a
#     trigger operand, the destinations match the cutover tail's, the SSH apply targets it, and the
#     one probe kick is non-blocking and comes after the timer is armed and asserted.
#   Guard 3 — the inline DSN writer in that resource, run BEHAVIOURALLY: the exact bytes that ship
#     are decoded from the HCL and executed under sh against scratch files.
#   Guard 4 (#9045; plan 2026-09-28-fix-luks-deadman-host-canary-disarm-and-snapshot-411798619-release,
#     §Guard 3) — the installer's read-only forensic print, `inline = local.luks_monitor_forensic_print`:
#     inline_raw() resolves locals (an unresolvable one reds, never passes on emptiness), every
#     referenced local is hashed into triggers_replace, the step runs before the exit-17 freeze
#     refusal, every line is guarded, and the wider deny list (journalctl, systemctl cat/status, a
#     bare systemctl show, a raw ExecStart, raw fstab/crypttab, apt-config dump) holds over every
#     unsuppressed step. The decoded bytes are also RUN against scratch fixtures (hostile fstab rows,
#     a per-unit systemctl stub, an ExecStart with no argv[]), and their sha256 is PINNED: a deny list
#     cannot enumerate every leaking spelling, so any change to this public print reds until a
#     security re-review updates the pin. The dead-man unit name is read from arm_dead_man's --unit=
#     and must match the exit-17 guard, the forensic print and the state print.
#
# Mutation rows live at the bottom. They mutate COPIES and re-run this file against them through
# the LMI_* overrides, so tracked files are never written. rc 1 = the mutation was caught; rc 2 = a
# broken instrument, never counted as a catch.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
export LMI_LUKS_TF="${LMI_LUKS_TF:-$DIR/workspaces-luks.tf}"
export LMI_ALERTS_TF="${LMI_ALERTS_TF:-$DIR/betterstack-logs-alerts.tf}"
export LMI_WF="${LMI_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
export LMI_MONITOR_SH="${LMI_MONITOR_SH:-$DIR/luks-monitor.sh}"
export LMI_CUTOVER_SH="${LMI_CUTOVER_SH:-$DIR/workspaces-cutover.sh}"
export LMI_INFRA_DIR="${LMI_INFRA_DIR:-$DIR}"
export LMI_WF_DIR="${LMI_WF_DIR:-$REPO/.github/workflows}"
export LMI_EXTRA_SCAN="${LMI_EXTRA_SCAN:-}"
export LMI_EXTRA_TF="${LMI_EXTRA_TF:-}"
export LMI_INNGEST_TF="${LMI_INNGEST_TF:-$DIR/inngest-host.tf}"
export LMI_RUNBOOK="${LMI_RUNBOOK:-$REPO/knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md}"
export LMI_REPO="$REPO"

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

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing\n' >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { printf '[FATAL] python3 yaml module missing\n' >&2; exit 2; }
for f in "$LMI_LUKS_TF" "$LMI_ALERTS_TF" "$LMI_WF" "$LMI_MONITOR_SH" "$LMI_CUTOVER_SH" "$LMI_INNGEST_TF" "$LMI_RUNBOOK"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

SCRATCH="$(mktemp -d)"
assert_fixture_dir "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT
export LMI_SCRATCH="$SCRATCH"

rc=0
python3 - > "$SCRATCH/verdicts.tsv" <<'PY' || rc=$?
import os, re, stat, subprocess, sys, shutil
import yaml

E = os.environ
out = []
def check(name, cond, detail=""):
    out.append(("ok" if cond else "no", name, " ".join(str(detail).split())[:240]))
def fatal(msg):
    for v in out:
        print("\t".join(v))
    print("FATAL\t" + msg)
    sys.exit(2)

def strip(src):
    # Remove # and // comments outside double-quoted strings, line by line.
    res = []
    for line in src.splitlines():
        buf, q, i = [], False, 0
        while i < len(line):
            ch = line[i]
            if ch == '"' and (i == 0 or line[i - 1] != "\\"):
                q = not q
            if not q and (ch == "#" or line.startswith("//", i)):
                break
            buf.append(ch); i += 1
        res.append("".join(buf))
    return "\n".join(res)

def balanced(src, start):
    # src[start-1] is the opening "{"; return the body up to its matching "}".
    depth, i = 1, start
    while i < len(src) and depth:
        depth += {"{": 1, "}": -1}.get(src[i], 0); i += 1
    return src[start:i - 1]

def block(src, kind, name):
    # EXACT header: a renamed resource (luks_monitor_install_v2) must not be found, and the
    # token installer (luks_monitor_token_install) must never be mistaken for this one.
    m = re.search(r'(?m)^resource\s+"%s"\s+"%s"\s*\{' % (re.escape(kind), re.escape(name)), src)
    return balanced(src, m.end()) if m else None

def blocks(src, kind):
    return [(m.group(1), balanced(src, m.end()))
            for m in re.finditer(r'(?m)^resource\s+"%s"\s+"([A-Za-z0-9_]+)"\s*\{' % re.escape(kind), src)]

def provisioners(body):
    res = []
    for m in re.finditer(r'provisioner\s+"(file|remote-exec)"\s*\{', body):
        res.append((m.group(1), balanced(body, m.end())))
    return res

STR = r'"((?:[^"\\]|\\.)*)"'
def list_strings(text, start):
    # text[start-1] is a list's opening "["; return the raw (still HCL-escaped) string elements.
    depth, i = 1, start
    while i < len(text) and depth:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < len(text) and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            i = j + 1; continue
        depth += {"[": 1, "]": -1}.get(c, 0); i += 1
    return re.findall(STR, text[start:i - 1])

# #9045 — `inline = local.NAME` resolves through every list local of the module (locals are
# module-global in Terraform, so the definition may sit in any root .tf). Filled once the .tf text
# is read below. An unresolvable reference yields [] and the G4 dispatch row reds on it: a step
# whose lines this suite cannot see must never pass the leak checks on emptiness.
LOCAL_LISTS = {}
def local_lists(src):
    res = {}
    for m in re.finditer(r'(?m)^locals\s*\{', src):
        body = balanced(src, m.end())
        for lm in re.finditer(r'(?m)^\s*([A-Za-z0-9_]+)\s*=\s*\[', body):
            res[lm.group(1)] = list_strings(body, lm.end())
    return res

def inline_local(pbody):
    m = re.search(r'(?m)^\s*inline\s*=\s*local\.([A-Za-z0-9_]+)\s*$', pbody)
    return m.group(1) if m else None

def inline_raw(pbody):
    name = inline_local(pbody)
    if name is not None:
        return list(LOCAL_LISTS.get(name, []))
    m = re.search(r'inline\s*=\s*\[', pbody)
    if not m:
        return []
    return list_strings(pbody, m.end())

def hcl_unescape(s):
    # HCL string escapes. Anything outside this set is a broken instrument, never a guess.
    res, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\":
            n = s[i + 1] if i + 1 < len(s) else ""
            if n == "\\": res.append("\\")
            elif n == '"': res.append('"')
            elif n == "n": res.append("\n")
            else: fatal("unknown HCL escape \\%s in %r" % (n, s))
            i += 2; continue
        res.append(c); i += 1
    return "".join(res)

def attr(body, key):
    m = re.search(r'(?m)^\s*%s\s*=\s*(.+?)\s*$' % re.escape(key), body)
    return m.group(1) if m else None

def top_level(body):
    # Attribute lines at depth 0 of a block body (nested blocks such as escalation_target excluded).
    res, depth = {}, 0
    for line in body.splitlines():
        if depth == 0:
            m = re.match(r'^\s*([A-Za-z_]+)\s*=\s*(.+?)\s*$', line)
            if m:
                res[m.group(1)] = m.group(2)
        depth += line.count("{") - line.count("}")
    return res

luks_raw = open(E["LMI_LUKS_TF"]).read()
luks = strip(luks_raw)
alerts_raw = open(E["LMI_ALERTS_TF"]).read()
alerts = strip(alerts_raw)
monitor = open(E["LMI_MONITOR_SH"]).read()
cutover = open(E["LMI_CUTOVER_SH"]).read()
wf = yaml.safe_load(open(E["LMI_WF"]))
jobs = wf.get("jobs") or {}

# ─────────────────────────────── Guard 1 — the liveness alert ───────────────────────────────
# Every .tf in the root, not only the alerts file: a luks-monitor exploration placed elsewhere is in
# the assembly too. The alerts file and workspaces-luks.tf are read through their LMI_* copies.
def tf_text(path):
    b = os.path.basename(path)
    if os.path.abspath(os.path.dirname(path)) == os.path.abspath(E["LMI_INFRA_DIR"]):
        if b == "betterstack-logs-alerts.tf": return alerts_raw
        if b == "workspaces-luks.tf": return luks_raw
    return open(path).read()
root_tf = sorted(os.path.join(E["LMI_INFRA_DIR"], f) for f in os.listdir(E["LMI_INFRA_DIR"]) if f.endswith(".tf"))
if E.get("LMI_EXTRA_TF"):
    root_tf.append(E["LMI_EXTRA_TF"])
all_tf_raw = "\n".join(tf_text(p) for p in root_tf)
LOCAL_LISTS.update(local_lists(strip(all_tf_raw)))
sql_locals = dict(re.findall(r'(?ms)^\s*([a-z0-9_]+)_sql\s*=\s*<<-SQL\n(.*?)\n\s*SQL\s*$', all_tf_raw))
UNIT = "JSONExtractString(raw,'_SYSTEMD_UNIT')='luks-monitor.service'"
EXPECTED = {
    "dt BETWEEN {{start_time}} AND {{end_time}}",
    "JSONExtractString(raw,'SYSLOG_IDENTIFIER')='luks-monitor'",
    UNIT,
    "JSONExtractString(raw,'message') LIKE '%OK: /mnt/data is LUKS-backed%'",
    "JSONExtractString(raw,'host_name')='soleur-web-platform'",
}

def norm(s):
    s = " ".join(s.split())
    return re.sub(r'\s*([(),=])\s*', r'\1', s)

EXPECTED = {norm(x) for x in EXPECTED}
UNIT = norm(UNIT)

def conjuncts(where):
    parts, depth, cur, toks = [], 0, [], re.split(r'(\s+AND\s+|[()])', where)
    for t in toks:
        if t == "(": depth += 1
        if t == ")": depth -= 1
        if depth == 0 and re.fullmatch(r'\s+AND\s+', t or ""):
            parts.append("".join(cur)); cur = []
        else:
            cur.append(t or "")
    parts.append("".join(cur))
    merged, skip = [], False
    for i, p in enumerate(parts):
        if skip:
            skip = False; continue
        if re.search(r'\bBETWEEN\s+\S+\s*$', p) and i + 1 < len(parts):
            merged.append(p.strip() + " AND " + parts[i + 1].strip()); skip = True
        else:
            merged.append(p.strip())
    return [norm(p) for p in merged]

def predicate_ok(sql):
    flat = " ".join(sql.split())
    m = re.fullmatch(r'SELECT toDateTime\(\{\{end_time\}\}\) AS time, count\(\*\) AS value FROM \{\{source\}\} WHERE (.*)', flat)
    if not m:
        return False, "head is not the count-per-window shape: " + flat[:120]
    cs = conjuncts(m.group(1))
    return (len(cs) == len(EXPECTED) and set(cs) == EXPECTED), cs

explorations = []
for p_ in root_tf:
    explorations += blocks(strip(tf_text(p_)), "logtail_exploration")
luks_explorations = []
LUKS_HINT = re.compile(r'luks[-_]monitor|LUKS-backed', re.I)
for name, body in explorations:
    q = attr(body, "sql_query") or ""
    ref = re.fullmatch(r'replace\(trimspace\(local\.([a-z0-9_]+)_sql\),\s*"/\\\\s\+/",\s*" "\)', q)
    lref = re.search(r'local\.([a-z0-9_]+?)(?:_sql)?\b', q)
    sql = sql_locals.get(ref.group(1)) if ref else None
    named = sql_locals.get(lref.group(1)) if lref else None
    if LUKS_HINT.search(q) or LUKS_HINT.search(body) or (sql and LUKS_HINT.search(sql)) \
       or (named and LUKS_HINT.search(named)) or (lref and LUKS_HINT.search(lref.group(1))):
        luks_explorations.append((name, body, ref, sql))
check("G1: at least one logtail_exploration reads a luks-monitor predicate", len(luks_explorations) >= 1,
      [n for n, *_ in luks_explorations])
# #9045 — the ONE named exception: the dead-man FIRE alert also reads the luks-monitor tag, but it is
# an event count (higher_than 0), not the liveness predicate. It is exempt from the liveness shape by
# its exact name only, and pinned to its own exact conjunct set here, so the exemption cannot be
# borrowed by a second exploration (G1-7) or used to widen this one. Its full guard is
# apps/web-platform/test/infra/workspaces-luks-deadman-fired-alert.test.sh.
DEADMAN_EXPLORATION = "workspaces_luks_deadman_fired"
DEADMAN_EXPECTED = {norm(x) for x in (
    "time BETWEEN {{start_time}} AND {{end_time}}",
    "JSONExtractString(raw,'SYSLOG_IDENTIFIER')='luks-monitor'",
    "JSONExtractString(raw,'host_name')='soleur-web-platform'",
    "startsWith(JSONExtractString(raw,'message'),'SOLEUR_WORKSPACES_LUKS_DEADMAN ')",
    "position(JSONExtractString(raw, 'message'), 'op=workspaces-luks-deadman result=fired') > 0",
)}
for name, body, ref, sql in [x for x in luks_explorations if x[0] == DEADMAN_EXPLORATION]:
    flat = " ".join((sql or "").split())
    dm = re.fullmatch(r'SELECT \{\{time\}\} AS time, count\(\*\) AS value FROM \{\{source\}\} WHERE (.*) GROUP BY time', flat)
    check("G1: the dead-man fire exploration is exactly tag AND host AND marker AND result=fired AND window",
          dm is not None and set(conjuncts(dm.group(1))) == DEADMAN_EXPECTED and len(conjuncts(dm.group(1))) == len(DEADMAN_EXPECTED),
          conjuncts(dm.group(1)) if dm else flat[:160])
luks_explorations = [x for x in luks_explorations if x[0] != DEADMAN_EXPLORATION]
for name, body, ref, sql in luks_explorations:
    check("G1: exploration %s reads its SQL from a *_sql local (whitespace-collapsed)" % name, ref is not None and sql is not None,
          attr(body, "sql_query"))
    if sql is not None:
        good, detail = predicate_ok(sql)
        check("G1: exploration %s's predicate is exactly identifier AND unit AND OK-needle AND window (no OR, no negation)" % name,
              good, detail)
        check("G1: exploration %s keeps the host-unit conjunct (the verify job's rows must never satisfy it)" % name,
              UNIT in (conjuncts(" ".join(sql.split()).split(" WHERE ", 1)[1]) if " WHERE " in " ".join(sql.split()) else []))

dark = block(alerts, "logtail_exploration", "luks_monitor_host_timer_dark")
check("G1: logtail_exploration.luks_monitor_host_timer_dark exists", dark is not None)
if dark:
    check("G1: it reads local.luks_monitor_host_timer_sql",
          re.search(r'local\.luks_monitor_host_timer_sql\b', attr(dark, "sql_query") or "") is not None, attr(dark, "sql_query"))
    vb = re.search(r'variable\s*\{([^}]*)\}', dark)
    vbody = vb.group(1) if vb else ""
    check("G1: its source variable is the prd Vector source (not another source)",
          re.search(r'(?m)^\s*values\s*=\s*\[\s*local\.vector_prd_source_id\s*\]\s*$', vbody) is not None, vbody)
    check("G1: its name is soleur-luks-monitor-host-timer-dark-prd",
          attr(dark, "name") == '"soleur-luks-monitor-host-timer-dark-prd"', attr(dark, "name"))

needle_in_sh = re.search(r'(?m)^\s*log "OK: /mnt/data is LUKS-backed \(', monitor) is not None
check("G1: luks-monitor.sh still logs the exact OK needle the predicate matches", needle_in_sh)

al = block(alerts, "logtail_exploration_alert", "luks_monitor_host_timer_dark")
check("G1: logtail_exploration_alert.luks_monitor_host_timer_dark exists", al is not None)
if al:
    a = top_level(al)
    check("G1: the alert watches ITS OWN exploration",
          a.get("exploration_id") == "logtail_exploration.luks_monitor_host_timer_dark.id", a.get("exploration_id"))
    check("G1: threshold alert, lower_than 1 (zero rows pages)",
          a.get("alert_type") == '"threshold"' and a.get("operator") == '"lower_than"' and a.get("value") == "1",
          (a.get("alert_type"), a.get("operator"), a.get("value")))
    check("G1: on_missing_data = treat_as_zero (silence FIRES)", a.get("on_missing_data") == '"treat_as_zero"', a.get("on_missing_data"))
    check("G1: paused = false", a.get("paused") == "false", a.get("paused"))
    check("G1: email = true", a.get("email") == "true", a.get("email"))
    try:
        qp, cp, ck = int(a.get("query_period", "x")), int(a.get("confirmation_period", "0")), int(a.get("check_period", "x"))
    except ValueError:
        qp = cp = ck = -1
    check("G1: query_period + confirmation_period covers a legitimate 24h30m (88200 s) gap between two timer runs",
          qp >= 86400 and qp + cp >= 88200, (qp, cp))
    check("G1: and pages within about 28 h of the last passing run (query_period + confirmation_period <= 100800)",
          0 < qp + cp <= 100800, (qp, cp))
    check("G1: the alert's name is soleur-luks-monitor-host-timer-dark-prd",
          a.get("name") == '"soleur-luks-monitor-host-timer-dark-prd"', a.get("name"))
    md = re.search(r'metadata\s*=\s*\{([^}]*)\}', al)
    check("G1: incident_cause and metadata.runbook both carry the runbook URL local",
          "${local.luks_monitor_runbook_url}" in (a.get("incident_cause") or "")
          and md is not None and re.search(r'runbook\s*=\s*local\.luks_monitor_runbook_url\b', md.group(1)) is not None)
    check("G1: evaluated at least hourly (check_period <= 3600)", 0 < ck <= 3600, ck)
    um = re.search(r'luks_monitor_runbook_url\s*=\s*"([^"]+)"', alerts_raw)
    frag = um.group(1).rsplit("#", 1)[1] if um and "#" in um.group(1) else None
    def gh_anchor(h):
        return re.sub(r'\s', "-", re.sub(r'[^\w\- ]', "", h.strip().lower()))
    heads = [gh_anchor(m.group(1)) for m in re.finditer(r'(?m)^#{1,6}\s+(.+?)\s*$', open(E["LMI_RUNBOOK"]).read())]
    check("G1: the runbook URL's fragment is a real heading anchor in the cutover runbook",
          frag is not None and frag in heads, frag)
    check("G1: the runbook URL names that runbook file",
          um is not None and um.group(1).split("#")[0].endswith("/" + os.path.relpath(E["LMI_RUNBOOK"], E["LMI_REPO"])), um.group(1) if um else None)

apply_job = jobs.get("apply") or {}
main_runs = [str(s.get("run", "")) for s in apply_job.get("steps") or [] if "-target=logtail_exploration" in str(s.get("run", ""))]
for t in ("logtail_exploration.luks_monitor_host_timer_dark", "logtail_exploration_alert.luks_monitor_host_timer_dark"):
    check("G1: the push-triggered apply job's MAIN plan targets %s" % t,
          any(re.search(r'(?m)^\s*-target=%s(\s*\\)?\s*$' % re.escape(t), r) for r in main_runs))

# Row 10: nothing else starts the unit. Its rows would carry _SYSTEMD_UNIT=luks-monitor.service
# and mask a dark timer exactly as the verify job's rows did.
# Every spelling that STARTS the unit: the start-class verbs, `enable --now`, with or without the
# .service suffix (systemctl treats a bare name as .service), and every unit-file directive that
# pulls it in. `luks-monitor(?:\.service)?(?![\w.-])` never matches luks-monitor.timer.
UNIT_RE = r'luks-monitor(?:\.service)?(?![\w.-])'
START = re.compile(r'\bsystemctl\b.*\b(?:start|restart|reload-or-restart|try-restart|try-reload-or-restart|enable\s+--now|--now\s+enable)\b.*' + UNIT_RE)
DEP = re.compile(r'^\s*(?:Wants|Requires|Requisite|BindsTo|PartOf|Upholds|OnFailure|OnSuccess|Unit|Also|Triggers)\s*=.*\bluks-monitor\.service\b')
BUS = re.compile(r'\b(?:busctl|dbus-send|gdbus)\b.*StartUnit.*' + UNIT_RE)
starters = []
scan = []
SCAN_EXT = (".sh", ".tf", ".yml", ".yaml", ".service", ".timer", ".path", ".socket", ".target", ".conf", ".tftpl", ".tmpl", ".json")
roots = [E["LMI_INFRA_DIR"], E["LMI_WF_DIR"], os.path.join(E["LMI_REPO"], ".github", "actions"), os.path.join(E["LMI_REPO"], "scripts")]
for root in roots:
    for dp, dn, fns in os.walk(root):
        dn[:] = [d for d in dn if d not in (".terraform", "node_modules", ".git")]
        for fn in fns:
            if fn.endswith((".md", ".test.sh", ".test.ts")) or not fn.endswith(SCAN_EXT):
                continue
            scan.append(os.path.join(dp, fn))
if E.get("LMI_EXTRA_SCAN"):
    scan.append(E["LMI_EXTRA_SCAN"])
for p in scan:
    try:
        if os.path.basename(p) == "workspaces-luks.tf" and os.path.dirname(os.path.abspath(p)) == os.path.abspath(E["LMI_INFRA_DIR"]):
            lines = luks_raw.splitlines()
        else:
            lines = open(p, errors="replace").read().splitlines()
    except OSError:
        continue
    for n, line in enumerate(lines, 1):
        # Only FULL-line comments are dropped: a `#` later on a line (a quoted "#x", a URL) must not
        # hide a start that follows it.
        code = "" if line.lstrip().startswith("#") else line
        if p.endswith(".tf"):
            code = strip(line)
        if START.search(code) or DEP.search(code) or BUS.search(code):
            starters.append("%s:%d" % (os.path.basename(p), n))
check("G1: scanned the workflow and infra trees (anti-vacuity)", len(scan) >= 50, len(scan))
check("G1: exactly one line anywhere starts luks-monitor.service — the installer's kick",
      len(starters) == 1 and starters[0].startswith("workspaces-luks.tf:"), starters)

# ─────────────────────────────── Guard 2 — the installer ───────────────────────────────
inst = block(luks, "terraform_data", "luks_monitor_install")
check("G2: terraform_data.luks_monitor_install exists (exact header)", inst is not None)
ARM = "systemctl enable --now luks-monitor.timer"
KICK = re.compile(r'^systemctl\s+(?:--no-block\s+start|start\s+--no-block)\s+luks-monitor\.service$')
writer_cmds = None
if inst:
    trig = attr(inst, "triggers_replace") or ""
    # triggers_replace spans several lines; take everything up to its closing "]))".
    tm = re.search(r'triggers_replace\s*=\s*sha256\(join\(",",\s*\[(.*?)\]\)\)', inst, re.S)
    ops = tm.group(1) if tm else ""
    trig_files = set(re.findall(r'file\("\$\{path\.module\}/([^"]+)"\)', ops))
    check("G2: triggers_replace is sha256(join(...)) over file() operands", tm is not None and len(trig_files) >= 1, trig)
    check("G2: the DSN hash is a trigger operand (a DSN rotation re-writes the line)",
          "nonsensitive(sha256(var.sentry_dsn))" in ops, ops)
    provs = provisioners(inst)
    files = [(re.search(r'source\s*=\s*"([^"]+)"', b), re.search(r'destination\s*=\s*"([^"]+)"', b)) for k, b in provs if k == "file"]
    srcs = [s.group(1) for s, d in files if s]
    src_names = set(re.sub(r'^\$\{path\.module\}/', "", s) for s in srcs)
    check("G2: every file provisioner ships from ${path.module}", all(s.startswith("${path.module}/") for s in srcs), srcs)
    check("G2: file() trigger operands == file provisioner sources (a delivered file that is not hashed is never re-delivered)",
          trig_files == src_names and len(src_names) == 4, (sorted(trig_files), sorted(src_names)))
    # Destinations must match the cutover tail's, or the two installers drift.
    emit = re.search(r'(?m)^EMIT="\$\{SELF_DIR\}/([^"]+)"', cutover)
    tail = {}
    for m in re.finditer(r'(?m)^\s*install -D -m \d+ "([^"]+)" (\S+)', cutover):
        s = m.group(1)
        s = emit.group(1) if (s == "$EMIT" and emit) else re.sub(r'^\$\{SELF_DIR\}/', "", s)
        tail[s] = m.group(2)
    mine = {re.sub(r'^\$\{path\.module\}/', "", s.group(1)): d.group(1) for s, d in files if s and d}
    check("G2: install destinations equal the cutover tail's for the same sources",
          len(tail) == 4 and mine == tail, (mine, tail))

    conn = re.search(r'connection\s*\{([^}]*)\}', inst)
    cb = conn.group(1) if conn else ""
    check("G2: the connection dials web-1 as root", re.search(r'(?m)^\s*host\s*=\s*hcloud_server\.web\["web-1"\]\.ipv4_address\s*$', cb) is not None
          and re.search(r'(?m)^\s*user\s*=\s*"root"\s*$', cb) is not None, cb)
    check("G2: the connection pins web-1's host key", re.search(r'(?m)^\s*host_key\s*=\s*local\.web_1_ssh_host_key\s*$', cb) is not None)
    check("G2: inline scripts upload under /root, not world-readable /tmp",
          re.search(r'(?m)^\s*script_path\s*=\s*"/root/[^"]*%RAND%[^"]*"\s*$', cb) is not None, cb)
    check("G2: depends_on serializes after the token installer and the Vector reload",
          re.search(r'depends_on\s*=\s*\[[^\]]*terraform_data\.luks_monitor_token_install', inst) is not None
          and re.search(r'depends_on\s*=\s*\[[^\]]*terraform_data\.journald_persistent', inst) is not None)
    check("G2: no lifecycle.ignore_changes (a silenced installer is the defect this closes)",
          re.search(r'ignore_changes', inst) is None)
    # The same expression inngest-host.tf applies to var.sentry_dsn, read from that file.
    ing = strip(open(E["LMI_INNGEST_TF"]).read())
    ic = re.findall(r'(?m)^\s*condition\s*=\s*(nonsensitive\(var\.sentry_dsn\b.*?)\s*$', ing)
    pre = re.search(r'precondition\s*\{([^}]*)\}', inst)
    cond = attr(pre.group(1), "condition") if pre else None
    check("G2: the DSN precondition is exactly the expression inngest-host.tf applies to var.sentry_dsn",
          len(ic) == 1 and cond == ic[0], (cond, ic))

    # Ordered command stream: (provisioner index, kind, command).
    stream, remote = [], []
    for idx, (k, b) in enumerate(provs):
        if k == "file":
            stream.append((idx, "file", b))
        else:
            cmds = inline_raw(b)
            remote.append((idx, cmds))
            for c in cmds:
                stream.append((idx, "cmd", c))
    def first(pred):
        for n, (idx, k, c) in enumerate(stream):
            if k == "cmd" and pred(c):
                return n
        return None
    arm = first(lambda c: c == ARM)
    en = first(lambda c: re.fullmatch(r'systemctl is-enabled luks-monitor\.timer', c) is not None)
    ac = first(lambda c: re.fullmatch(r'systemctl is-active luks-monitor\.timer', c) is not None)
    dr = first(lambda c: c == "systemctl daemon-reload")
    frz = first(lambda c: re.search(r'systemctl show -p SubState --value workspaces-luks-deadman\.timer\b', c) is not None
                and "!= waiting" in c and re.search(r'\bexit 17\b', c) is not None)
    check("G2: daemon-reload runs before the timer is armed", None not in (dr, arm) and dr < arm, (dr, arm))
    check("G2: a live cutover freeze (dead-man SubState=waiting) is refused with exit 17 before arming",
          None not in (frz, arm) and frz < arm, (frz, arm))
    if arm is not None:
        aidx = stream[arm][0]
        acmds = [c for idx, k, c in stream if k == "cmd" and idx == aidx]
        check("G2: the arm provisioner starts with set -e (its asserts are fatal)", acmds[:1] == ["set -e"], acmds[:1])
        check("G2: no `|| true` softens an arm-provisioner command", not any("|| true" in c for c in acmds), acmds)
    # Every binary the cutover tail installs 0755 is chmodded 0755 by a set -e provisioner, before arming.
    tail_x = {m.group(2) for m in re.finditer(r'(?m)^\s*install -D -m (\d+) "[^"]+" (\S+)', cutover) if m.group(1) == "0755"}
    chm = [(n, set(c.split()[2:])) for n, (idx, k, c) in enumerate(stream) if k == "cmd" and re.match(r'chmod 0755 ', c)]
    chm_set = set().union(*[x for _, x in chm]) if chm else set()
    chm_ok = bool(chm) and all([c for i2, k2, c in stream if k2 == "cmd" and i2 == stream[n][0]][:1] == ["set -e"] for n, _ in chm)
    check("G2: the installer chmods exactly the tail's 0755 binaries, in a set -e provisioner, before arming",
          chm_set == tail_x and len(tail_x) == 2 and chm_ok and arm is not None and max(n for n, _ in chm) < arm,
          (sorted(chm_set), sorted(tail_x)))
    check("G2: nothing in the installer stops, disables, masks or kills luks-monitor",
          not any(re.search(r'systemctl\b.*\b(stop|disable|mask|kill)\b.*luks-monitor', c) for i2, k2, c in stream if k2 == "cmd"))
    kicks = [n for n, (idx, k, c) in enumerate(stream) if k == "cmd" and re.search(r'systemctl\b.*\b(start|restart)\b.*luks-monitor\.service', c)]
    check("G2: the installer arms the timer with the exact manifest line", arm is not None)
    check("G2: it asserts is-enabled and is-active after arming", None not in (arm, en, ac) and arm < en and arm < ac, (arm, en, ac))
    check("G2: exactly one start of luks-monitor.service, and it is --no-block",
          len(kicks) == 1 and KICK.match(stream[kicks[0]][2]) is not None, [stream[k][2] for k in kicks])
    check("G2: the kick comes after the arm and both asserts",
          len(kicks) == 1 and None not in (arm, en, ac) and kicks[0] > max(arm, en, ac), (arm, en, ac, kicks))
    lastfile = max([n for n, (i, k, c) in enumerate(stream) if k == "file"] or [10**9])
    check("G2: every file is delivered before the timer is armed", arm is not None and lastfile < arm, (lastfile, arm))
    dsn_provs = [(idx, cmds) for idx, cmds in remote if any("var.sentry_dsn" in c for c in cmds)]
    check("G2: exactly one remote-exec carries var.sentry_dsn (the DSN writer)", len(dsn_provs) == 1, len(dsn_provs))
    if len(dsn_provs) == 1:
        widx = dsn_provs[0][0]
        armidx = stream[arm][0] if arm is not None else -1
        check("G2: the DSN line is written before the timer is armed (the first run can reach Sentry)", widx < armidx, (widx, armidx))
        for idx, cmds in remote:
            if idx != widx:
                check("G2: remote-exec #%d carries no var./sensitive reference (its output stays visible)" % idx,
                      not any(re.search(r'\$\{(var|doppler_service_token|random_password)\.', c) for c in cmds))
        writer_cmds = dsn_provs[0][1]
    widx = dsn_provs[0][0] if len(dsn_provs) == 1 else None
    state = " ".join(c for idx, cmds in remote if idx != widx for c in cmds)
    check("G2: the state print shows the timer's LoadState/UnitFileState/ActiveState/NextElapse",
          re.search(r'systemctl show -p LoadState,UnitFileState,ActiveState,NextElapseUSecRealtime', state) is not None)
    check("G2: the state print shows the dead-man units", "workspaces-luks-deadman.timer" in state and "workspaces-luks-deadman.service" in state)
    check("G2: counts-only env-file diagnostics exist", "grep -c '^SOLEUR_SENTRY_DSN='" in state and "grep -c '^DOPPLER_TOKEN='" in state)
    check("G2: the state print reads luks-monitor.service's own state (catches a 203/EXEC from the kick)",
          re.search(r'systemctl show -p Id,ActiveState,SubState,Result,ExecMainStatus luks-monitor\.service\b', state) is not None)
    check("G2: stale root-owned /tmp/terraform_*.sh are removed, but only ones older than 60 min",
          re.search(r"find /tmp -maxdepth 1 -name 'terraform_\*\.sh' -user root -mmin \+60 -size \+0c -delete", state) is not None)

# The manifest greps the arming string on a view that drops only lines STARTING with "#".
view = "\n".join(l for l in luks_raw.splitlines() if not l.lstrip().startswith("#"))
check("G2: the arming string occurs exactly once outside full-line comments (heartbeat manifest evidence)",
      view.count(ARM) == 1, view.count(ARM))
check("G2: and that occurrence is live code inside the installer",
      inst is not None and ('"%s",' % ARM) in inst)
tok = block(luks, "terraform_data", "luks_monitor_token_install")
check("G2: the token installer also uploads its inline scripts under /root",
      tok is not None and re.search(r'(?m)^\s*script_path\s*=\s*"/root/[^"]*%RAND%[^"]*"\s*$', tok) is not None)
# DIAGNOSTICS ALLOWLIST over both installers: in every remote-exec that carries no secret reference,
# the env file may appear ONLY as a `stat -c '%F %a %U'` or a `grep -c '^KEY='` operand. Anything else
# (cat, grep ., sed -n p, head, source, awk) could print a value into an unsuppressed apply log.
DIAG_OK = re.compile(r"stat -c '%F %a %U' /etc/default/luks-monitor|grep -c '\^(?:DOPPLER_TOKEN|SOLEUR_SENTRY_DSN)=' /etc/default/luks-monitor")
# #9045 — the wider deny list. Each form below can put a command line, a journal tail (a transient
# unit's journal echoes its command line and possibly personal data), a credential or an
# unfiltered host file into the PUBLIC Actions log. The approved spellings are removed first; any
# residue of the named token is a leak. ExecStart is allowed only as `| grep -q` or as the pinned
# argv[] extraction piped into sha256sum; fstab only through the exact-field awk select; crypttab
# only as a COUNT; apt-config only as the one Automatic-Reboot key (a dump prints proxy credentials).
EXECSTART_SRC = "systemctl show -p ExecStart --value workspaces-luks-deadman.service 2>/dev/null | "
# One substitution with both anchors: a property that lacks either one extracts NOTHING (so the
# print says argv_sha256=none) instead of hashing a half-parsed fragment such as "{ path=/bin/sh".
ARGV_SED = r"sed -n 's/^.*argv[[][]]=\(.*\) ; ignore_errors=.*$/\1/p'"
# The argv[] text lands in $av and is only ever hashed (an empty extraction prints `none`, never the
# empty-string digest e3b0c442…). ARGV_HASH is the one consumer of $av (a G4 row pins that).
ARGV_ASSIGN = "av=$(" + EXECSTART_SRC + ARGV_SED + " || true)"
ARGV_HASH = """if [ -n "$av" ]; then printf '%s\\n' "$av" | sha256sum | cut -c1-64; else echo none; fi"""
APPROVED = [
    re.compile(re.escape(EXECSTART_SRC) + r"grep -q '[^']*'"),
    re.compile(re.escape(ARGV_ASSIGN)),
    re.compile(r"""awk '\$1 !~ /\^#/ && \$2 == "/mnt/data"[^']*' /etc/fstab"""),
    re.compile(r"grep -c '\^workspaces' /etc/crypttab"),
    re.compile(r"apt-config shell AR Unattended-Upgrade::Automatic-Reboot"),
]
FORBIDDEN = [
    ("journalctl", re.compile(r'\bjournalctl\b')),
    ("systemctl cat/status", re.compile(r'\bsystemctl(?:\s+-{1,2}[\w=.-]+)*\s+(?:cat|status)\b')),
    ("systemctl show with no -p", re.compile(r'\bsystemctl(?:\s+-{1,2}[\w=.-]+)*\s+show\b(?!\s+-p\s)')),
    ("ExecStart outside the hash/grep -q forms", re.compile(r'\bExecStart')),
    ("/etc/fstab outside the exact-field awk select", re.compile(r'/etc/fstab\b')),
    ("/etc/crypttab beyond a count", re.compile(r'/etc/crypttab\b')),
    ("apt-config beyond the one Automatic-Reboot key", re.compile(r'\bapt-config\b')),
]
leaks, forbidden = [], []
etc_default, status_verb, globs = [], [], []
def read_path_globs(c):
    # Single-quoted spans are literal to the shell (the awk/sed programs, find -name patterns), so
    # they are removed first; any remaining word that names a path and carries a glob metacharacter
    # would let the shell pick the file (`cat /etc/default/luks-m*`, `/proc/*/cmdline`).
    bare = re.sub(r"'[^']*'", "''", c)
    return [w for w in bare.split() if "/" in w and re.search(r'[*?\[]', w)]
for nm, bd in (("luks_monitor_install", inst), ("luks_monitor_token_install", tok)):
    for k, b in provisioners(bd or ""):
        if k != "remote-exec":
            continue
        cmds = [hcl_unescape(c) for c in inline_raw(b)]
        if any(re.search(r'\$\{(var|doppler_service_token|random_password)\.', c) for c in cmds):
            continue
        for c in cmds:
            if "/etc/default/luks-monitor" in DIAG_OK.sub("", c):
                leaks.append("%s: %s" % (nm, c))
            if "/etc/default" in DIAG_OK.sub("", c):
                etc_default.append("%s: %s" % (nm, c[:120]))
            if re.search(r'\bstatus\b', c):
                status_verb.append("%s: %s" % (nm, c[:120]))
            if read_path_globs(c):
                globs.append("%s: %s" % (nm, read_path_globs(c)))
            residue = c
            for a in APPROVED:
                residue = a.sub("", residue)
            for label, rx in FORBIDDEN:
                if rx.search(residue):
                    forbidden.append("%s [%s]: %s" % (nm, label, c[:120]))
check("G2: unsuppressed provisioners touch the env file only through counts-only forms", not leaks, leaks)
check("G4: no /etc/default reference in an unsuppressed step beyond the counts-only env-file reads",
      not etc_default, etc_default)
check("G4: no `status` word in an unsuppressed step (systemctl -M .host status, service … status)",
      not status_verb, status_verb)
check("G4: no glob in a read path of an unsuppressed step (cat /etc/default/luks-m*, /proc/*/cmdline)",
      not globs, globs)
check("G2: unsuppressed provisioners use no forbidden diagnostic (journalctl, systemctl cat/status, bare show, raw ExecStart, raw fstab/crypttab, apt-config dump)",
      not forbidden, forbidden)
check("G2: each secret-bearing remote-exec deletes its own uploaded script (rm -f -- \"$0\")",
      all(any(hcl_unescape(c) == 'rm -f -- "$0"' for c in inline_raw(b))
          for bd in (inst, tok) for k, b in provisioners(bd or "")
          if k == "remote-exec" and any(re.search(r'\$\{(var|doppler_service_token)\.', c) for c in inline_raw(b))))

ssh_targets = set()
for s in apply_job.get("steps") or []:
    run = str(s.get("run", ""))
    if "terraform_data.web_1_host_key_probe" in run:
        ssh_targets |= set(re.findall(r"-target=(terraform_data\.[a-z0-9_]+)", run))
check("G2: the per-merge SSH apply targets terraform_data.luks_monitor_install",
      "terraform_data.luks_monitor_install" in ssh_targets, sorted(ssh_targets)[:4])

# ─────────────────────── Guard 4 — the forensic print (#9045, plan Guard 3) ───────────────────────
# Property: every edit to the installer's forensic print re-fires terraform_data.luks_monitor_install,
# and the print executes BEFORE the exit-17 freeze refusal (a live freeze cannot suppress it). The
# print is read-only and public (no var. reference, so Terraform does not suppress its output).
FORENSIC = "luks_monitor_forensic_print"
DEADMAN_PROPS = ("LoadState", "ActiveState", "SubState", "Result", "LastTriggerUSec",
                 "ExecMainStartTimestamp", "ExecMainExitTimestamp", "ExecMainStatus", "InvocationID")

def tmpl_live(c):
    # An unescaped ${ or %{ is an interpolation Terraform would evaluate into the public log.
    d = hcl_unescape(c)
    return "${" in d.replace("$${", "") or "%{" in d.replace("%%{", "")

def tmpl_decode(c):
    # HCL-unescape, then Terraform's template escapes: the bytes the host actually runs.
    return hcl_unescape(c).replace("$${", "${").replace("%%{", "%{")

def subst_bodies(c):
    # Top-level $( … ) bodies of a shell line (nested ones ride inside their parent).
    res, i = [], 0
    while True:
        j = c.find("$(", i)
        if j < 0:
            return res
        depth, k = 1, j + 2
        while k < len(c) and depth:
            depth += {"(": 1, ")": -1}.get(c[k], 0); k += 1
        res.append(c[j + 2:k - 1]); i = k

def guarded(c):
    # A line may neither fail the step nor taint the resource: it ends in `|| true`, or it is an echo
    # whose every top-level substitution carries its own `|| echo …` / `|| true` fallback, or a
    # literal single-quoted echo.
    c = c.strip()
    if re.search(r'\|\|\s*true$', c):
        return True
    if c.startswith("echo "):
        subs = subst_bodies(c)
        if not subs:
            return re.fullmatch(r"echo '[^']*'", c) is not None
        return all(re.search(r'\|\|\s*(?:echo\s|true\b)', s) for s in subs)
    return False

forensic_raw = LOCAL_LISTS.get(FORENSIC, [])
forensic_lines = [tmpl_decode(c) for c in forensic_raw]
if inst:
    provs_g4 = provisioners(inst)
    local_refs = [(idx, inline_local(b)) for idx, (k, b) in enumerate(provs_g4) if k == "remote-exec" and inline_local(b)]
    fidx = [idx for idx, n in local_refs if n == FORENSIC]
    check("G4: exactly one installer step runs inline = local.%s" % FORENSIC, len(fidx) == 1, local_refs)
    unresolved = [n for idx, n in local_refs if not LOCAL_LISTS.get(n)]
    check("G4: every inline = local.X in the installer resolves to lines (no lines resolved = FAIL, never a pass on emptiness)",
          bool(local_refs) and not unresolved, unresolved or local_refs)
    tm4 = re.search(r'triggers_replace\s*=\s*sha256\(join\(",",\s*\[(.*?)\]\)\)', inst, re.S)
    ops4 = tm4.group(1) if tm4 else ""
    unhashed = [n for idx, n in local_refs if not re.search(r'join\("\\n",\s*local\.%s\)' % re.escape(n), ops4)]
    check("G4: every referenced local is hashed into triggers_replace as join(\"\\n\", local.X) (an edit re-fires the installer)",
          bool(local_refs) and not unhashed, unhashed)
    frz_idx = stream[frz][0] if frz is not None else None
    check("G4: the forensic step precedes the exit-17 freeze-refusal step (a live freeze cannot suppress it)",
          len(fidx) == 1 and frz_idx is not None and fidx[0] < frz_idx, (fidx, frz_idx))
F = forensic_lines
check("G4: the forensic print has lines", len(F) >= 5, len(F))
check("G4: the forensic print references no var./sensitive value and no live interpolation (its output must stay visible)",
      bool(forensic_raw) and not any(tmpl_live(c) or re.search(r'\bvar\.', c) for c in forensic_raw),
      [c[:80] for c in forensic_raw if tmpl_live(c) or re.search(r'\bvar\.', c)])
unguarded = [c[:100] for c in F if not guarded(c)]
check("G4: every forensic line carries an `|| true` / `|| echo` guard (a missing value cannot fail the step)",
      bool(F) and not unguarded, unguarded)
for unit in ("workspaces-luks-deadman.timer", "workspaces-luks-deadman.service"):
    missing = [p for p in DEADMAN_PROPS
               if not any(unit in c and re.search(r'\bsystemctl show -p\b', c) and re.search(r'\b%s\b' % p, c) for c in F)]
    check("G4: the print reads every dead-man property of %s through systemctl show -p" % unit, not missing, missing)
check("G4: ExecStart is read only as fired_cmd (grep -q result=fired) and an argv[] sha256 (none when empty), else exec=not-loaded",
      any(EXECSTART_SRC + "grep -q 'result=fired'" in c and "fired_cmd=" in c for c in F)
      and any(ARGV_ASSIGN in c and ("argv_sha256=$(" + ARGV_HASH) in c for c in F)
      and any("exec=not-loaded" in c for c in F))
av_residue = [c[:100] for c in F if "$av" in c.replace(ARGV_ASSIGN, "").replace(ARGV_HASH, "")]
check("G4: the extracted argv ($av) is consumed only by the sha256 pipe (never echoed)",
      any(ARGV_ASSIGN in c for c in F) and not av_residue, av_residue)
check("G4: the /mnt/data fstab entry is selected by exact field; device and options are allowlisted, else <redacted-device>/<redacted-options>, and has_nofail is printed",
      any("""awk '$1 !~ /^#/ && $2 == "/mnt/data\"""" in c and "<redacted-device>" in c and "<redacted-options>" in c
          and "has_nofail=" in c and "/etc/fstab" in c for c in F))
check("G4: crypttab is read only as a COUNT of ^workspaces lines", any("grep -c '^workspaces' /etc/crypttab" in c for c in F))
check("G4: the print carries uptime -s, reboot-required=yes|no and automatic-reboot=true|false|unset",
      any("uptime -s" in c for c in F) and any("reboot-required=" in c and "/var/run/reboot-required" in c for c in F)
      and any("automatic-reboot=" in c and "apt-config shell AR Unattended-Upgrade::Automatic-Reboot" in c for c in F))
check("G4: no journalctl and no /etc/default/luks-monitor read in the forensic print",
      not any(re.search(r'\bjournalctl\b', c) or "/etc/default/luks-monitor" in c for c in F))

# Behavioural: run the exact decoded bytes under the host shell against scratch fixtures, once with
# every probe failing (the step must still exit 0 and print every label) and once with a fired
# dead-man loaded (the command line must never reach the output; the fstab options are redacted).
g4_shell = shutil.which("dash") or shutil.which("sh")
g4_dir = os.path.join(E["LMI_SCRATCH"], "forensic"); os.makedirs(g4_dir, exist_ok=True)
g4_script = "\n".join(F) + "\n"
syn = subprocess.run([g4_shell, "-n"], input=g4_script, capture_output=True, text=True, timeout=30)
check("G4: the decoded forensic print parses under %s -n" % os.path.basename(g4_shell or "sh"), bool(F) and syn.returncode == 0, syn.stderr[-160:])
ARGV = ("/bin/sh -c logger -t luks-monitor -- 'SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman "
        "result=fired reason=timer_elapsed'; docker stop -t 30 soleur-web-platform 2>/dev/null; SECRET-ARGV-TEXT")
EXECSTART_VAL = "{ path=/bin/sh ; argv[]=%s ; ignore_errors=no ; start_time=[Mon 2026-07-20 22:42:13 UTC] ; stop_time=[Mon 2026-07-20 22:42:14 UTC] ; pid=4242 ; code=exited ; status=0 }" % ARGV
NOARGV_VAL = "{ path=/bin/sh ; ignore_errors=no ; start_time=[Mon 2026-07-20 22:42:13 UTC] ; pid=4242 ; code=exited ; status=0 }"
# Every hostile /mnt/data row must print only <redacted-device>/<redacted-options>; none of these may
# reach the (public) output. Mixed case on purpose: the allowlist compares lowercased options.
FSTAB_SECRETS = ("hunter", "Password", "PASSWORD", "pw=", "credentials", "smbcred", "token=", "tok-", "secret=",
                 "username", "alice", "bob", "s3cret", "dav.example", "https", "//srv", "$(id)", "COMMENTED-OUT", "OTHER-MOUNT")
def g4_run(mode):
    d = os.path.join(g4_dir, mode); b = os.path.join(d, "bin"); os.makedirs(b)
    paths = {"/etc/fstab": os.path.join(d, "fstab"), "/etc/crypttab": os.path.join(d, "crypttab"),
             "/var/run/reboot-required": os.path.join(d, "reboot-required")}
    body = g4_script
    for real, fake in paths.items():
        body = body.replace(real, fake)
    if mode in ("fired", "noargv"):
        open(paths["/etc/fstab"], "w").write(
            "# /dev/sdz /mnt/data ext4 COMMENTED-OUT 0 2\n"
            "/dev/disk/by-id/scsi-0HC_Volume_1 /mnt/data ext4 discard,nofail,defaults 0 0\n"
            "/dev/sdb /mnt/data2 ext4 OTHER-MOUNT 0 0\n"
            "/dev/sdc /mnt/data ext4 x-opt=$(id) 0 0\n"
            "/dev/sdd /mnt/data ext4 defaults,password=hunter2 0 0\n"
            "/dev/sde /mnt/data ext4 nofail,Password=hunter3 0 0\n"
            "/dev/sdf /mnt/data ext4 PASSWORD=hunter4 0 0\n"
            "/dev/sdg /mnt/data ext4 pw=hunter5 0 0\n"
            "/dev/sdh /mnt/data cifs credentials=/root/.smbcred,nofail 0 0\n"
            "/dev/sdi /mnt/data ext4 token=tok-hunter6 0 0\n"
            "/dev/sdj /mnt/data ext4 secret=hunter7 0 0\n"
            "//srv/share /mnt/data cifs username=alice,nofail 0 0\n"
            "https://bob:s3cret@dav.example/ /mnt/data davfs defaults,nofail 0 0\n"
            "UUID=0a1b-2c3d /mnt/data ext4 NOATIME,x-systemd.device-timeout=10s 0 2\n"
            "LABEL=workspaces_plain /mnt/data ext4 errors=remount-ro,_netdev 0 2\n")
        open(paths["/etc/crypttab"], "w").write("workspaces_luks UUID=abc none luks\n# workspaces_old UUID=d none luks\nother UUID=e none luks\n")
        open(paths["/var/run/reboot-required"], "w").write("*** System restart required ***\n")
        # Answers PER UNIT (the last argument): a loop labelled with one unit that reads the other
        # prints the wrong unit's name in its value, so the pairing below catches it (I-M1).
        stubs = {
            "systemctl": 'for a; do case "$prev" in -p) prop="$a" ;; esac; prev="$a"; unit="$a"; done\n'
                         'case "$prop:$unit" in ExecStart:*.service) cat "%s" ;; LoadState:*.service) echo loaded ;; *) echo "$unit/$prop" ;; esac\n'
                         % os.path.join(d, "execstart"),
            "apt-config": "echo \"AR='true'\"\n",
            "uptime": "echo '2026-07-01 00:00:00'\n",
        }
        open(os.path.join(d, "execstart"), "w").write((EXECSTART_VAL if mode == "fired" else NOARGV_VAL) + "\n")
    else:
        stubs = {n: "exit 1\n" for n in ("systemctl", "apt-config", "uptime")}
    for n, s in stubs.items():
        p = os.path.join(b, n); open(p, "w").write("#!/bin/sh\n" + s); os.chmod(p, 0o755)
    sp = os.path.join(d, "forensic.sh"); open(sp, "w").write(body)
    p = subprocess.run([g4_shell, sp], env={"PATH": b + ":/usr/bin:/bin", "HOME": d}, capture_output=True, text=True, timeout=60)
    return p.returncode, p.stdout, p.stderr
if F and g4_shell:
    rc_f, out_f, err_f = g4_run("dark")
    check("G4: with every probe failing and no host files, the print still exits 0 (it can never taint the resource)", rc_f == 0, (rc_f, err_f[-120:]))
    check("G4: …and prints every label, each dead-man property included",
          all(("%s=" % p) in out_f for p in DEADMAN_PROPS) and "exec=not-loaded" in out_f
          and "reboot-required=no" in out_f and "automatic-reboot=unset" in out_f and "=none" in out_f, out_f[-240:])
    rc_x, out_x, err_x = g4_run("fired")
    argv_sha = __import__("hashlib").sha256((ARGV + "\n").encode()).hexdigest()
    check("G4: with a fired dead-man loaded, the print exits 0 and reads fired_cmd=yes and the argv[] sha256",
          rc_x == 0 and "fired_cmd=yes" in out_x and ("argv_sha256=%s" % argv_sha) in out_x, (rc_x, out_x[-240:], err_x[-120:]))
    check("G4: …and never prints the command line, its pid or its start time",
          not any(t in out_x for t in ("SOLEUR_WORKSPACES_LUKS_DEADMAN", "SECRET-ARGV-TEXT", "docker stop", "pid=4242", "argv[]")), out_x[-240:])
    want_fstab = [
        "/dev/disk/by-id/scsi-0HC_Volume_1 /mnt/data ext4 discard,nofail,defaults 0 0 has_nofail=yes;",
        "/dev/sdc /mnt/data ext4 <redacted-options> 0 0 has_nofail=no;",
        "/dev/sdd /mnt/data ext4 <redacted-options> 0 0 has_nofail=no;",
        "/dev/sde /mnt/data ext4 <redacted-options> 0 0 has_nofail=yes;",
        "/dev/sdf /mnt/data ext4 <redacted-options> 0 0 has_nofail=no;",
        "/dev/sdg /mnt/data ext4 <redacted-options> 0 0 has_nofail=no;",
        "/dev/sdh /mnt/data cifs <redacted-options> 0 0 has_nofail=yes;",
        "/dev/sdi /mnt/data ext4 <redacted-options> 0 0 has_nofail=no;",
        "/dev/sdj /mnt/data ext4 <redacted-options> 0 0 has_nofail=no;",
        "<redacted-device> /mnt/data cifs <redacted-options> 0 0 has_nofail=yes;",
        "<redacted-device> /mnt/data davfs defaults,nofail 0 0 has_nofail=yes;",
        "UUID=0a1b-2c3d /mnt/data ext4 NOATIME,x-systemd.device-timeout=10s 0 2 has_nofail=no;",
        "LABEL=workspaces_plain /mnt/data ext4 errors=remount-ro,_netdev 0 2 has_nofail=no;",
    ]
    fline = next((l for l in out_x.splitlines() if l.startswith("luks-monitor forensic fstab /mnt/data=")), "")
    check("G4: …the live /mnt/data fstab entries print, commented and other mounts do not, hostile devices/options are redacted, has_nofail is reported",
          all(w in fline for w in want_fstab) and fline.count("has_nofail=") == len(want_fstab)
          and not [t for t in FSTAB_SECRETS if t in out_x],
          ([w for w in want_fstab if w not in fline], [t for t in FSTAB_SECRETS if t in out_x], fline[:200]))
    check("G4: …crypttab is a count (1), reboot-required=yes, automatic-reboot=true",
          "crypttab-workspaces-lines=1" in out_x and "reboot-required=yes" in out_x and "automatic-reboot=true" in out_x, out_x[-300:])
    xlines = set(out_x.splitlines())
    mispaired = ["%s %s" % (u, p_) for u in ("workspaces-luks-deadman.timer", "workspaces-luks-deadman.service") for p_ in DEADMAN_PROPS
                 if "luks-monitor forensic %s %s=%s" % (u, p_, "loaded" if (p_ == "LoadState" and u.endswith(".service")) else "%s/%s" % (u, p_)) not in xlines]
    check("G4: …each dead-man property line reads the unit its label names (per-unit stub; a .timer label over a .service read fails)",
          not mispaired, mispaired[:4])
    rc_n, out_n, err_n = g4_run("noargv")
    check("G4: with a loaded dead-man whose ExecStart carries no argv[], argv_sha256=none (never the empty-string digest)",
          rc_n == 0 and "argv_sha256=none" in out_n and "e3b0c442" not in out_n and "01ba4719" not in out_n, (rc_n, out_n[-200:], err_n[-120:]))

# CHANGE-DETECTOR (#9045 review). The forensic print goes to the PUBLIC Actions log, and a deny list
# cannot enumerate every leaking spelling (`cat /etc/default/luks-m*`, `systemctl -M .host show`,
# `apt-config shell AR … P Acquire::http::Proxy`, `/proc/*/cmdline`, `/var/log/syslog`,
# `journal''ctl`). So the exact decoded bytes are pinned: ANY change to the print, however
# harmless-looking, reds here until a security re-review signs it off and updates the pin.
# Regenerate: LMI_MUTANT=1 bash apps/web-platform/infra/luks-monitor-install.test.sh | grep change-detector
# prints actual=<sha>; paste it below only after the re-review.
FORENSIC_PRINT_SHA256 = "9686b7fdc5f0b1b91b115d212469248cc5056171455a3e676b2c16271ec96400"
g4_sha = __import__("hashlib").sha256(g4_script.encode()).hexdigest()
check("G4: change-detector: the public-log forensic print is byte-identical to the security-reviewed version (sha256 pin)",
      bool(F) and g4_sha == FORENSIC_PRINT_SHA256,
      "actual=%s: any change to the public-log forensic print requires security re-review and a pin update (FORENSIC_PRINT_SHA256)" % g4_sha)

# UNIT-NAME PARITY (#9045 review). The dead-man unit is named once, by arm_dead_man's systemd-run
# --unit= in workspaces-cutover.sh. The installer's exit-17 guard, forensic print and state print all
# read it by name; a rename on one side would leave them reading a unit that never exists.
am = re.search(r'(?ms)^arm_dead_man\(\)\s*\{\n(.*?)^\}', cutover)
am_body = "\n".join(l for l in (am.group(1) if am else "").splitlines() if not l.lstrip().startswith("#"))
dm_units = re.findall(r'--unit=([A-Za-z0-9@_.-]+)', am_body)
check("G4: arm_dead_man's systemd-run names exactly one --unit= (positive control: the extractor finds it)",
      len(dm_units) == 1, dm_units)
DM = dm_units[0] if len(dm_units) == 1 else "@@no-unit@@"
UNIT_TOK = re.compile(r'[A-Za-z0-9@_.-]+\.(?:timer|service)\b')
frz_units = set(UNIT_TOK.findall(stream[frz][2])) if (inst and frz is not None) else set()
f_units = set(u for c in F for u in UNIT_TOK.findall(c))
st_units = set()
if inst:
    for idx, cmds in remote:
        if any(re.search(r'systemctl show -p Id,ActiveState,SubState,Result ', c) for c in cmds):
            st_units |= set(u for c in cmds for u in UNIT_TOK.findall(c)) - {"luks-monitor.timer", "luks-monitor.service"}
check("G4: the exit-17 guard, forensic print and state print read the unit arm_dead_man creates (%s.timer/.service)" % DM,
      frz_units == {DM + ".timer"} and f_units == {DM + ".timer", DM + ".service"} and st_units == {DM + ".timer", DM + ".service"},
      (DM, sorted(frz_units), sorted(f_units), sorted(st_units)))

# ─────────────────────────────── Guard 3 — the DSN writer ───────────────────────────────
# Census: every Terraform-driven writer of the env file, including through a delivered script.
tf_files = [os.path.join(E["LMI_INFRA_DIR"], f) for f in sorted(os.listdir(E["LMI_INFRA_DIR"])) if f.endswith(".tf")]
if E.get("LMI_EXTRA_TF"):
    tf_files.append(E["LMI_EXTRA_TF"])
writers = set()
for p in tf_files:
    s = strip(open(p).read())
    if os.path.abspath(p) == os.path.abspath(os.path.join(E["LMI_INFRA_DIR"], "workspaces-luks.tf")):
        s = luks
    for kind in ("terraform_data", "null_resource"):
        for name, body in blocks(s, kind):
            hit = False
            for k, b in provisioners(body):
                # Any text of the block that names the file: an inline command, a file provisioner's
                # destination or content, or a remote-exec script(s) argument.
                if "/etc/default/luks-monitor" in b:
                    hit = True
                # …or a local-sourced inline list (#9045): the text lives in the local, not here.
                if k == "remote-exec" and any("/etc/default/luks-monitor" in c for c in inline_raw(b)):
                    hit = True
                # Any script the block ships or runs: a file provisioner's source, or a remote-exec
                # script / scripts entry, read from disk. WRITER-vs-READER (#9123): the census
                # quantifies over WRITES, and an `EnvironmentFile=[-]/etc/default/luks-monitor`
                # line in a shipped unit is systemd READING the file at unit start — a
                # read-only consumer (workspaces-luks-reopen.service and -failure.service both
                # carry it; terraform_data.workspaces_boot_unlock_install ships them). Only a
                # line that IS just the declaration is exempted — a line with anything else on it
                # (`EnvironmentFile=-/etc/default/luks-monitor; echo x >> ...`) still hits. Every
                # other non-comment mention stays a hit too: the token helper's ENVF= anchor,
                # the emit helper's `. /etc/default/luks-monitor`, redirects, sed -i, tee, mv.
                READER_LINE = re.compile(r'^[ \t]*EnvironmentFile=-?/etc/default/luks-monitor[ \t]*$')
                for sm in re.finditer(r'(?:source|script)\s*=\s*"\$\{path\.(?:module|root)\}/([^"]+)"|"\$\{path\.(?:module|root)\}/([^"]+)"', b):
                    rel = sm.group(1) or sm.group(2)
                    sp = os.path.join(os.path.dirname(p), rel)
                    if os.path.isfile(sp) and any(
                        re.match(r'[^#]*/etc/default/luks-monitor', l)
                        and READER_LINE.match(l) is None
                        for l in open(sp, errors="replace").read().splitlines()):
                        hit = True
            if hit:
                writers.add(name)
check("G3: the env-file writers are exactly the token installer and this installer",
      writers == {"luks_monitor_token_install", "luks_monitor_install"}, sorted(writers))

# The precondition's regex, applied to hostile DSNs. It is interpolated into a single-quoted shell
# printf and the file is SOURCED as root, so a quote, $( ) or backtick must never pass.
pre_re = None
if inst:
    m = re.search(r'can\(regex\("([^"]+)", var\.sentry_dsn\)\)', inst)
    # Terraform's regex() is RE2, whose "$" matches only at the very end of the text; Python's also
    # matches before a final newline, so translate the trailing anchor or a DSN ending in "\n" reads
    # as accepted here while Terraform rejects it.
    pre_re = re.sub(r'\$$', r'\\Z', hcl_unescape(m.group(1))) if m else None
check("G3: the precondition carries a regex this guard can read", pre_re is not None)
if pre_re:
    good = "https://0123456789abcdef@o0.ingest.example.io/42"
    bad = ["https://k@h/1'; id; '", "https://$(id)@h.example/1", "https://`id`@h.example/1",
           "https://k@h.example/1 ", "https://k@h.example/1\n", "http://k@h.example/1", "https://k@h.example/abc"]
    check("G3: the precondition accepts a well-formed DSN", re.search(pre_re, good) is not None)
    check("G3: the precondition rejects quotes, $( ), backticks, whitespace and non-numeric projects",
          all(re.search(pre_re, b) is None for b in bad), [b for b in bad if re.search(pre_re, b)])

# Behavioural: run the shipped bytes. A missing installer block is a Guard 2 verdict (RED); a
# present block with no extractable writer is a broken instrument (rc 2).
if writer_cmds is None and inst is None:
    check("G3: the DSN writer can be run (the installer block is missing, so it cannot)", False)
    for v in out:
        print("\t".join(v))
    sys.exit(0)
if writer_cmds is None:
    fatal("no DSN writer extracted — Guard 3 cannot run")
DSN = "https://0123456789abcdef@o0.ingest.example.io/42"
decoded, subs = [], 0
for c in writer_cmds:
    d = hcl_unescape(c)
    n = d.count("${var.sentry_dsn}")
    subs += n
    d = d.replace("${var.sentry_dsn}", "\0DSN\0")
    if "${" in d.replace("$${", "") or "%{" in d.replace("%%{", ""):
        fatal("an unexpected template sequence in the writer: %r" % c)
    d = d.replace("$${", "${").replace("%%{", "%{").replace("\0DSN\0", "@@DSN@@")
    decoded.append(d)
if subs != 1:
    fatal("var.sentry_dsn must appear exactly once in the writer, saw %d" % subs)
script = "\n".join(decoded) + "\n"
if script.count("f=/etc/default/luks-monitor\n") != 1:
    fatal("the scratch-path rewrite anchor f=/etc/default/luks-monitor is not present exactly once")

scratch = E["LMI_SCRATCH"]
bindir = os.path.join(scratch, "bin"); os.makedirs(bindir, exist_ok=True)
real_grep = shutil.which("grep")
chown_log = os.path.join(scratch, "chown.log")
chown_argv = os.path.join(scratch, "chown.argv")
with open(os.path.join(bindir, "chown"), "w") as fh:
    fh.write('#!/bin/sh\nfor a; do last="$a"; done\nstat -c %%a "$last" >> %s\nprintf "%%s\\n" "$*" >> %s\nexit 0\n' % (chown_log, chown_argv))
with open(os.path.join(bindir, "grep"), "w") as fh:
    fh.write('#!/bin/sh\nfor a; do last="$a"; done\n'
             'if [ -n "${LMI_GREP_FAIL_PATH:-}" ] && [ "$last" = "$LMI_GREP_FAIL_PATH" ]; then echo "grep: $last: Input/output error" >&2; exit 2; fi\n'
             'exec %s "$@"\n' % real_grep)
for b in ("chown", "grep"):
    os.chmod(os.path.join(bindir, b), 0o755)
shell = shutil.which("dash") or shutil.which("sh")

case_n = [0]
def run(seed=None, dsn=DSN, kind="file", env_extra=None, planted_tmp=None):
    case_n[0] += 1
    d = os.path.join(scratch, "case%d" % case_n[0]); os.makedirs(d)
    f = os.path.join(d, "luks-monitor")
    victim = os.path.join(d, "victim")
    open(victim, "w").write("VICTIM=untouched\n")
    if kind == "file" and seed is not None:
        open(f, "w").write(seed); os.chmod(f, 0o600)
    elif kind == "symlink":
        os.symlink(victim, f)
    elif kind == "dir":
        os.mkdir(f)
    if planted_tmp == "symlink":
        os.symlink(victim, f + ".dsn.tmp")
    body = script.replace("f=/etc/default/luks-monitor\n", "f=%s\n" % f).replace("@@DSN@@", dsn)
    if "/etc/default/" in body:
        fatal("the scratch-path rewrite did not remove every /etc/default/ reference")
    sp = os.path.join(d, "writer.sh"); open(sp, "w").write(body)
    for lg in (chown_log, chown_argv):
        if os.path.exists(lg):
            os.remove(lg)
    env = {"PATH": bindir + ":/usr/bin:/bin", "HOME": d}
    env.update({k: (f if v == "__SELF__" else v) for k, v in (env_extra or {}).items()})
    old = os.umask(0o022)
    try:
        p = subprocess.run([shell, sp], env=env, capture_output=True, text=True, timeout=30)
    finally:
        os.umask(old)
    content = open(f).read() if os.path.isfile(f) and not os.path.islink(f) else None
    mode = stat.S_IMODE(os.stat(f).st_mode) if content is not None else None
    tmpmodes = open(chown_log).read().split() if os.path.exists(chown_log) else []
    argv = open(chown_argv).read().splitlines() if os.path.exists(chown_argv) else []
    leftover = sorted(x for x in os.listdir(d) if x.startswith("luks-monitor.") and x != "luks-monitor")
    return {"rc": p.returncode, "content": content, "mode": mode, "victim": open(victim).read(),
            "tmpmodes": tmpmodes, "argv": argv, "f": f, "err": p.stderr.strip()[-160:],
            "link": os.path.islink(f), "leftover": leftover, "self_deleted": not os.path.exists(sp)}

L = "SOLEUR_SENTRY_DSN=%s\n" % DSN
r = run(seed="DOPPLER_TOKEN=x\n")
check("G3: token-only file -> rc 0, token line kept, exactly one DSN line appended", r["rc"] == 0 and r["content"] == "DOPPLER_TOKEN=x\n" + L, r)
check("G3: the result is mode 0600", r["mode"] == 0o600, oct(r["mode"] or 0))
check("G3: the temp file is BORN 0600 even under umask 022 (umask 077 is load-bearing)", r["tmpmodes"] == ["600"], r["tmpmodes"])
check("G3: the temp file is chowned root:root before it replaces the env file",
      r["argv"] == ["root:root %s.dsn.tmp" % r["f"]], r["argv"])
check("G3: the writer deletes its own uploaded script (a refusal cannot leave the DSN on disk)", r["self_deleted"], r)

r1 = run(seed="DOPPLER_TOKEN=x\n")
r2 = run(seed=r1["content"] or "")
check("G3: a second run is idempotent (still exactly one DSN line)", r2["rc"] == 0 and r2["content"] == "DOPPLER_TOKEN=x\n" + L, r2)

r = run(seed="B=2\nSOLEUR_SENTRY_DSN=https://old@o0.ingest.example.io/1\nSOLEUR_SENTRY_DSN_X=keep\nDOPPLER_TOKEN=x")
check("G3: only the DSN line changes; SOLEUR_SENTRY_DSN_X= and every other line survive in order (no trailing newline seed)",
      r["rc"] == 0 and r["content"] == "B=2\nSOLEUR_SENTRY_DSN_X=keep\nDOPPLER_TOKEN=x\n" + L, r)

r = run(seed=None)
check("G3: absent file -> created 0600 holding only the DSN line", r["rc"] == 0 and r["content"] == L and r["mode"] == 0o600, r)

r = run(seed="DOPPLER_TOKEN=x\n", dsn="")
check("G3: empty DSN -> refused with exit 10, file unchanged", r["rc"] == 10 and r["content"] == "DOPPLER_TOKEN=x\n", r)

r = run(kind="symlink")
check("G3: symlink at the path -> refused with exit 11, target untouched", r["rc"] == 11 and r["link"] and r["victim"] == "VICTIM=untouched\n", r)

r = run(kind="dir")
check("G3: directory at the path -> refused with exit 12", r["rc"] == 12, r)

r = run(seed="DOPPLER_TOKEN=x\n", env_extra={"LMI_GREP_FAIL_PATH": "__SELF__"})
check("G3: a read error on the file -> refused with exit 13, never an emptied file", r["rc"] == 13 and r["content"] == "DOPPLER_TOKEN=x\n", r)
check("G3: a refusal leaves no temp copy (of the token line) behind", r["leftover"] == [], r["leftover"])

r = run(seed="DOPPLER_TOKEN=x\n", planted_tmp="symlink")
check("G3: a planted temp-file symlink is removed, never written through", r["rc"] == 0 and r["victim"] == "VICTIM=untouched\n"
      and r["content"] == "DOPPLER_TOKEN=x\n" + L, r)
check("G3: behavioural cases ran (anti-vacuity)", case_n[0] >= 9, case_n[0])

for v in out:
    print("\t".join(v))
PY
if [ "$rc" -ne 0 ]; then
  cat "$SCRATCH/verdicts.tsv"
  printf '[FATAL] the checker exited %s — a broken instrument, not a verdict\n' "$rc" >&2
  exit 2
fi
_before=$((pass + fail)); verdict_lines=0
while IFS=$'\t' read -r v name detail; do
  [[ -n "${v:-}" ]] || continue
  verdict_lines=$((verdict_lines + 1))
  if [[ "$v" == ok ]]; then ok "$name"; else no "$name${detail:+ ($detail)}"; fi
done < "$SCRATCH/verdicts.tsv"
# Accounting conservation: every verdict the checker printed must have moved exactly one counter.
if [[ $((pass + fail - _before)) -ne "$verdict_lines" ]]; then
  printf '[FATAL] %s verdicts read but the counters moved %s — ok()/no() were tampered with\n' "$verdict_lines" "$((pass + fail - _before))" >&2
  exit 2
fi

# ─────────────────────────────── mutation rows ───────────────────────────────
# Each row edits a COPY (asserting the edit landed) and re-runs this file against it. Skipped in
# the child run, so rows never recurse.
if [[ -z "${LMI_MUTANT:-}" ]]; then
  MUT="$SCRATCH/mut"
  mkdir -p "$MUT"
  assert_fixture_dir "$MUT"
  # mutate <label> <want-rc> <env-var> <source> <python replace expr on s>
  mutate() {
    local label="$1" want="$2" var="$3" src="$4" expr="$5" copy got
    copy="$MUT/$(basename "$src").$RANDOM$RANDOM"
    if ! MUT_SRC="$src" MUT_DST="$copy" MUT_EXPR="$expr" python3 - <<'PY'
import os, sys
s = open(os.environ["MUT_SRC"]).read()
t = eval(os.environ["MUT_EXPR"], {"s": s, "re": __import__("re")})
if t == s:
    print("mutation did not land", file=sys.stderr); sys.exit(3)
open(os.environ["MUT_DST"], "w").write(t)
PY
    then
      no "mutation $label: could not be applied (instrument)"; return
    fi
    got=0
    env "$var=$copy" LMI_MUTANT=1 bash "$SELF" >"$copy.log" 2>&1 || got=$?
    grade "$label" "$want" "$got" "$copy.log"
  }
  # A caught mutation is rc 1 AND the named check's own [FAIL] line; rc alone would credit any
  # unrelated failure (or a crash) to the row. rc 0 / rc 2 rows are must-PASS / instrument rows.
  grade() {
    local label="$1" want="$2" got="$3" log="$4" key exp
    key="${label%% *}"; exp="${EXPECT_FAIL[$key]:-}"
    mut_rows=$((mut_rows + 1))
    if [[ "$got" != "$want" ]]; then
      no "mutation $label: want rc $want, got $got (log $(tail -3 "$log" | tr '\n' ' '))"; return
    fi
    if [[ "$want" == 1 ]]; then
      if [[ -z "$exp" ]]; then no "mutation $label: no expected [FAIL] name registered (instrument)"; return; fi
      if ! grep -F '[FAIL]' "$log" | grep -cF >/dev/null -- "$exp"; then
        no "mutation $label: rc 1 but not through the named check [$exp]"; return
      fi
      # ONLY rows: the named check must be the SOLE failure (it proves no other row sees the edit).
      if [[ -n "${EXPECT_ONLY[$key]:-}" ]] && [[ "$(grep -c '^\[FAIL\]' "$log")" -ne 1 ]]; then
        no "mutation $label: [$exp] failed, but so did other rows (want it to be the only [FAIL])"; return
      fi
    fi
    ok "mutation $label -> rc $got${exp:+ via [$exp]}"
  }
  # extra-file rows: <label> <want> <env-var> <content>
  extra() {
    local label="$1" want="$2" var="$3" content="$4" f got
    f="$MUT/extra.$RANDOM$RANDOM${5:-.yml}"
    printf '%s\n' "$content" > "$f"
    got=0
    env "$var=$f" LMI_MUTANT=1 bash "$SELF" >"$f.log" 2>&1 || got=$?
    grade "$label" "$want" "$got" "$f.log"
  }
  declare -A EXPECT_FAIL=(
    [G1-1]="keeps the host-unit conjunct" [G1-2]="on_missing_data = treat_as_zero"
    [G1-4]="covers a legitimate 24h30m" [G1-5a]="predicate is exactly" [G1-5b]="still logs the exact OK needle"
    [G1-6]="predicate is exactly" [G1-6b]="predicate is exactly" [G1-7]="exploration luks_monitor_extra"
    [G1-8]="MAIN plan targets logtail_exploration_alert" [G1-9]="watches ITS OWN exploration"
    [G1-10]="exactly one line anywhere starts" [G1-11]="predicate is exactly" [G1-12]="pages within about 28 h"
    [G1-13]="incident_cause and metadata.runbook" [G1-14]="exactly one line anywhere starts"
    [G1-15]="exactly one line anywhere starts" [G1-16]="reads its SQL from a *_sql local"
    [G1-17]="fragment is a real heading anchor" [G1-H1]="reads its SQL from a *_sql local"
    [G2-1]="file() trigger operands" [G2-2]="file() trigger operands" [G2-4]="the kick comes after"
    [G2-7]="arming string occurs exactly once" [G2-8]="install destinations equal"
    [G2-9]="exactly one start of luks-monitor.service" [G2-10]="luks_monitor_install exists"
    [G2-11]="arming string occurs exactly once" [G2-12]="SSH apply targets terraform_data.luks_monitor_install"
    [G2-13]="arm provisioner starts with set -e" [G2-14]="softens an arm-provisioner command"
    [G2-15]="chmods exactly the tail's 0755 binaries" [G2-16]="cutover freeze" [G2-17]="counts-only forms"
    [G2-18]="stops, disables, masks or kills" [G2-19]="deletes its own uploaded script"
    [G3-1]="token-only file" [G3-2]="second run is idempotent" [G3-3]="BORN 0600"
    [G3-4]="symlink at the path" [G3-5]="only the DSN line changes" [G3-6]="read error on the file"
    [G3-7]="planted temp-file symlink" [G3-8]="precondition rejects quotes" [G3-9]="env-file writers are exactly"
    [G3-10]="chowned root:root" [G3-11]="env-file writers are exactly" [G3-12]="READS the env file"
    [G4-1]="every referenced local is hashed" [G4-2]="precedes the exit-17 freeze-refusal"
    [G4-3]="resolves to lines" [G4-4]="every referenced local is hashed" [G4-5]="counts-only forms"
    [G4-6]="forbidden diagnostic" [G4-7]="forbidden diagnostic" [G4-8]="forbidden diagnostic"
    [G4-9]="forbidden diagnostic" [G4-10]="forbidden diagnostic" [G4-11]="forbidden diagnostic"
    [G4-12]="guard (a missing value cannot fail the step)" [G4-13]="forbidden diagnostic"
    [G4-14]="hostile devices/options are redacted" [G4-15]="references no var." [G4-16]="forbidden diagnostic"
    [G4-17]="exactly one installer step runs inline = local" [G4-H1]="change-detector"
    [G4-18]="hostile devices/options are redacted" [G4-19]="hostile devices/options are redacted"
    [G4-20]="hostile devices/options are redacted" [G4-21]="argv_sha256=none"
    [G4-22]="reads the unit its label names" [G4-23]="no /etc/default reference"
    [G4-24]="word in an unsuppressed step" [G4-25]="no glob in a read path"
    [G4-26]="change-detector" [G4-27]="change-detector"
    [G4-P1]="read the unit arm_dead_man creates" [G4-P2]="read the unit arm_dead_man creates"
  )
  # Rows whose named check must be the ONLY failure: the edit is invisible to every other row.
  declare -A EXPECT_ONLY=([G4-H1]=1 [G4-26]=1 [G4-27]=1)
  mut_rows=0
  A="$LMI_ALERTS_TF"; T="$LMI_LUKS_TF"; W="$LMI_WF"
  ARM_LINE="systemctl enable --now luks-monitor.timer"
  SHOW_LINE="systemctl show -p LoadState,UnitFileState,ActiveState,NextElapseUSecRealtime,LastTriggerUSec luks-monitor.timer --no-pager || true"
  UNITC="      AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service'\n"
  # Guard 1
  mutate "G1-1 drop the host-unit conjunct" 1 LMI_ALERTS_TF "$A" "s.replace(\"$UNITC\", '', 1)"
  mutate "G1-2 on_missing_data no longer treat_as_zero" 1 LMI_ALERTS_TF "$A" "re.sub(r'(luks_monitor_host_timer_dark\" \{(?:.|\n)*?on_missing_data\s*=\s*)\"treat_as_zero\"', r'\1\"keep_last_value\"', s, 1)"
  mutate "G1-4 query_period 86400 with confirmation 0" 1 LMI_ALERTS_TF "$A" "s.replace('query_period        = 97200', 'query_period        = 86400', 1)"
  mutate "G1-5a reword the needle in the SQL only" 1 LMI_ALERTS_TF "$A" "s.replace(\"'%OK: /mnt/data is LUKS-backed%'\", \"'%OK: /mnt/data is encrypted%'\", 1)"
  mutate "G1-5b reword the OK line in luks-monitor.sh only" 1 LMI_MONITOR_SH "$LMI_MONITOR_SH" "s.replace('log \"OK: /mnt/data is LUKS-backed (', 'log \"OK: /mnt/data is encrypted (', 1)"
  mutate "G1-6 join the unit conjunct with OR" 1 LMI_ALERTS_TF "$A" "s.replace(\"      AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service'\", \"      OR JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service'\", 1)"
  mutate "G1-6b negate the unit conjunct" 1 LMI_ALERTS_TF "$A" "s.replace(\"'_SYSTEMD_UNIT') = 'luks-monitor.service'\", \"'_SYSTEMD_UNIT') != 'luks-monitor.service'\", 1)"
  mutate "G1-7 a second luks-monitor exploration lacking the unit conjunct" 1 LMI_ALERTS_TF "$A" "s + '''
locals {
  luks_monitor_extra_sql = <<-SQL
    SELECT toDateTime({{end_time}}) AS time, count(*) AS value
    FROM {{source}}
    WHERE dt BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'
  SQL
}
resource \"logtail_exploration\" \"luks_monitor_extra\" {
  name = \"x\"
  query {
    sql_query = replace(trimspace(local.luks_monitor_extra_sql), \"/\\\\\\\\s+/\", \" \")
  }
}
'''"
  mutate "G1-8 alert target dropped from the MAIN plan" 1 LMI_WF "$W" "re.sub(r'(?m)^\s*-target=logtail_exploration_alert\.luks_monitor_host_timer_dark \\\\\n', '', s, 1)"
  mutate "G1-9 the alert watches another exploration" 1 LMI_ALERTS_TF "$A" "s.replace('exploration_id = logtail_exploration.luks_monitor_host_timer_dark.id', 'exploration_id = logtail_exploration.claude_cost_capture_dark.id', 1)"
  extra "G1-10 a second starter of luks-monitor.service" 1 LMI_EXTRA_SCAN "      - run: ssh web-1 systemctl start luks-monitor.service"
  mutate "G1-H1 the SQL local renamed away (extractor finds nothing)" 1 LMI_ALERTS_TF "$A" "s.replace('  luks_monitor_host_timer_sql = <<-SQL', '  luks_monitor_host_timer_sqlx = <<-SQL', 1)"
  mutate "G1-H2 conjuncts reordered and reflowed (must PASS)" 0 LMI_ALERTS_TF "$A" "s.replace(\"      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'\n$UNITC\", \"      AND JSONExtractString( raw,'_SYSTEMD_UNIT' )   =   'luks-monitor.service'\n      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'\n\", 1)"
  # Guard 2
  mutate "G2-1 the timer is no longer a trigger operand" 1 LMI_LUKS_TF "$T" "s.replace('    file(\"\${path.module}/luks-monitor.timer\"),\n', '', 1)"
  mutate "G2-2 a fifth, unhashed file provisioner" 1 LMI_LUKS_TF "$T" "s.replace('    destination = \"/etc/systemd/system/luks-monitor.timer\"\n  }\n', '    destination = \"/etc/systemd/system/luks-monitor.timer\"\n  }\n  provisioner \"file\" {\n    source      = \"\${path.module}/luks-monitor-token-refresh.sh\"\n    destination = \"/usr/local/bin/x\"\n  }\n', 1)"
  mutate "G2-4 the kick moved above the arm" 1 LMI_LUKS_TF "$T" "s.replace('      \"$ARM_LINE\",\n', '      \"systemctl start --no-block luks-monitor.service\",\n      \"$ARM_LINE\",\n', 1).replace('      \"systemctl start --no-block luks-monitor.service\",\n    ]', '    ]', 1)"
  mutate "G2-7 the arming line moved into a comment" 1 LMI_LUKS_TF "$T" "s.replace('      \"$ARM_LINE\",\n', '      # \"$ARM_LINE\",\n', 1)"
  mutate "G2-8 a destination drifts from the cutover tail" 1 LMI_LUKS_TF "$T" "s.replace('destination = \"/usr/local/bin/luks-monitor\"', 'destination = \"/usr/local/bin/luks-monitor.sh\"', 1)"
  mutate "G2-9 a second, blocking start in the state print" 1 LMI_LUKS_TF "$T" "s.replace('      \"$SHOW_LINE\",\n', '      \"$SHOW_LINE\",\n      \"systemctl start luks-monitor.service\",\n', 1)"
  mutate "G2-10 the resource renamed" 1 LMI_LUKS_TF "$T" "s.replace('resource \"terraform_data\" \"luks_monitor_install\" {', 'resource \"terraform_data\" \"luks_monitor_install_v2\" {', 1)"
  mutate "G2-11 a trailing comment repeats the arming string" 1 LMI_LUKS_TF "$T" "s.replace('      \"$ARM_LINE\",\n', '      \"$ARM_LINE\", # $ARM_LINE\n', 1)"
  mutate "G2-12 the SSH apply stops targeting the installer" 1 LMI_WF "$W" "re.sub(r'(?m)^\s*-target=terraform_data\.luks_monitor_install( \\\\)?\n', '', s, 1)"
  mutate "G2-H2 trigger reorder, an extra echo, swapped kick flags (must PASS)" 0 LMI_LUKS_TF "$T" "s.replace('    file(\"\${path.module}/luks-monitor.sh\"),\n    file(\"\${path.module}/workspaces-luks-emit.sh\"),\n', '    file(\"\${path.module}/workspaces-luks-emit.sh\"),\n    file(\"\${path.module}/luks-monitor.sh\"),\n', 1).replace('      \"$SHOW_LINE\",\n', '      \"echo state\",\n      \"$SHOW_LINE\",\n', 1).replace('systemctl start --no-block luks-monitor.service', 'systemctl --no-block start luks-monitor.service', 1)"
  # Guard 3
  mutate "G3-1 the filter drops the token line" 1 LMI_LUKS_TF "$T" "s.replace(\"      \\\"rc=0; grep -v '^SOLEUR_SENTRY_DSN='\", \"      \\\"rc=0; grep -v '^DOPPLER_TOKEN='\", 1)"
  mutate "G3-2 no filter: the old DSN line is carried over" 1 LMI_LUKS_TF "$T" "s.replace(\"      \\\"rc=0; grep -v '^SOLEUR_SENTRY_DSN=' \\\\\\\"\$f\\\\\\\" > \", \"      \\\"rc=0; cat \\\\\\\"\$f\\\\\\\" > \", 1)"
  mutate "G3-3 umask 077 removed" 1 LMI_LUKS_TF "$T" "s.replace('      \"umask 077\",\n', '', 1)"
  mutate "G3-4 the symlink refusal removed" 1 LMI_LUKS_TF "$T" "re.sub(r'(?m)^      \"\[ ! -L .*\n', '', s, 1)"
  mutate "G3-5 the = dropped from the filter" 1 LMI_LUKS_TF "$T" "s.replace(\"      \\\"rc=0; grep -v '^SOLEUR_SENTRY_DSN='\", \"      \\\"rc=0; grep -v '^SOLEUR_SENTRY_DSN'\", 1)"
  mutate "G3-6 the read-error arm removed" 1 LMI_LUKS_TF "$T" "re.sub(r'(?m)^      \"\[ \\\\\"\\\$rc\\\\\" -le 1 \].*\n', '', s, 1)"
  mutate "G3-7 the stale temp file is no longer removed" 1 LMI_LUKS_TF "$T" "re.sub(r'(?m)^      \"rm -f \\\\\"\\\$t\\\\\"\",\n', '', s, 1)"
  mutate "G3-8 the precondition widened to [^@/]+ classes" 1 LMI_LUKS_TF "$T" "s.replace('^https://[A-Za-z0-9]+@[A-Za-z0-9.-]+/[0-9]+\$', '^https://[^@/]+@[^/]+/[^/?#]+\$', 1)"
  extra "G3-9 a second writer of the env file" 1 LMI_EXTRA_TF 'resource "terraform_data" "rogue" {
  provisioner "remote-exec" {
    inline = ["echo X=1 >> /etc/default/luks-monitor"]
  }
}' .tf
  # Review round (2026-09-27): rows for every guard added after the first panel.
  mutate "G1-11 drop the host_name conjunct (web-2 rows would count)" 1 LMI_ALERTS_TF "$A" "$(cat <<'X'
s.replace("      AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'\n", '', 1)
X
)"
  mutate "G1-12 a 10-day window (pages far too late)" 1 LMI_ALERTS_TF "$A" "s.replace('query_period        = 97200', 'query_period        = 864000', 1)"
  mutate "G1-13 the incident text loses the runbook link" 1 LMI_ALERTS_TF "$A" "$(cat <<'X'
s.replace(' Runbook: ${local.luks_monitor_runbook_url}"', ' Runbook: see the cutover runbook"', 1)
X
)"
  extra "G1-14 a suffixless starter (systemctl start luks-monitor)" 1 LMI_EXTRA_SCAN "      - run: ssh web-1 systemctl start luks-monitor"
  extra "G1-15 a unit that Wants= the service" 1 LMI_EXTRA_SCAN $'[Unit]\nWants=luks-monitor.service' .service
  extra "G1-16 a luks exploration elsewhere with inline SQL" 1 LMI_EXTRA_TF 'resource "logtail_exploration" "rogue_luks" {
  name = "x"
  query {
    sql_query = "SELECT count(*) AS value FROM {{source}} WHERE JSONExtractString(raw, '"'"'message'"'"') LIKE '"'"'%OK: /mnt/data is LUKS-backed%'"'"'"
  }
}' .tf
  mutate "G1-17 the runbook heading renamed (the email link would dangle)" 1 LMI_RUNBOOK "$LMI_RUNBOOK" "s.replace('### Host-timer liveness alert (#8706)', '### Host timer liveness (#8706)', 1)"
  mutate "G2-13 the arm step without set -e" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('      "set -e",\n      "[ \\"$(systemctl show -p SubState', '      "[ \\"$(systemctl show -p SubState', 1)
X
)"
  mutate "G2-14 is-enabled softened with || true" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('      "systemctl is-enabled luks-monitor.timer",\n', '      "systemctl is-enabled luks-monitor.timer || true",\n', 1)
X
)"
  mutate "G2-15 the chmod dropped (203/EXEC on the next run)" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('      "chmod 0755 /usr/local/bin/luks-monitor /usr/local/bin/workspaces-luks-emit.sh",\n', '', 1)
X
)"
  mutate "G2-16 the cutover-freeze refusal dropped" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
re.sub(r'(?m)^      "\[ \\"\$\(systemctl show -p SubState.*\n', '', s, 1)
X
)"
  mutate "G2-17 a diagnostic prints the env file's values" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('      "df -P /etc | tail -1 || true",\n', '      "df -P /etc | tail -1 || true",\n      "grep . /etc/default/luks-monitor || true",\n', 1)
X
)"
  mutate "G2-18 the timer disabled after arming" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('      "find /root -maxdepth 1', '      "systemctl disable --now luks-monitor.timer || true",\n      "find /root -maxdepth 1', 1)
X
)"
  mutate "G2-19 the writer keeps its uploaded script (DSN left on disk)" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('      "rm -f -- \\"$0\\"",\n      "umask 077",', '      "umask 077",', 1)
X
)"
  mutate "G3-10 the temp file chowned to a non-root owner" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('      "chown root:root \\"$t\\"",', '      "chown nobody:nogroup \\"$t\\"",', 1)
X
)"
  extra "G3-11 a file provisioner writing the env file by destination" 1 LMI_EXTRA_TF 'resource "terraform_data" "rogue2" {
  provisioner "file" {
    content     = "X=1"
    destination = "/etc/default/luks-monitor"
  }
}' .tf
  # #9123 — the reader side of the census distinction: a resource that ships a unit READING
  # the env file via EnvironmentFile= is a consumer, NOT a writer (the boot-unlock installer's
  # shape). Must PASS — if the READER_LINE exemption is lost, this resource trips the census.
  printf '[Service]\nEnvironmentFile=-/etc/default/luks-monitor\n' > "$MUT/consumer-reader.service"
  extra "G3-12 a resource shipping a unit that READS the env file via EnvironmentFile (consumer)" 0 LMI_EXTRA_TF 'resource "terraform_data" "reader_only" {
  provisioner "file" {
    source      = "${path.module}/consumer-reader.service"
    destination = "/etc/systemd/system/reader-only.service"
  }
}' .tf
  mutate "G3-H1 the scratch-path rewrite cannot land (instrument)" 2 LMI_LUKS_TF "$T" "s.replace('\"f=/etc/default/luks-monitor\",', '\"f=\\\\\"/etc/default/luks-monitor\\\\\"\",', 1)"
  mutate "G3-H2 the writer split differently across inline entries (must PASS)" 0 LMI_LUKS_TF "$T" "s.replace('      \"umask 077\",\n      \"f=/etc/default/luks-monitor\",\n', '      \"umask 077; f=/etc/default/luks-monitor\",\n', 1)"
  # Guard 4 (#9045) — the forensic print. Every row edits a COPY of workspaces-luks.tf; a "forbidden"
  # line is inserted as the local's FIRST element, so the leak checks must read local-sourced steps.
  FL='  luks_monitor_forensic_print = ['
  fins() {  # fins <label> <HCL string literal, already escaped> — insert as the local's first line
    mutate "$1" 1 LMI_LUKS_TF "$T" "s.replace('$FL\n', '$FL\n    ' + $2 + ',\n', 1)"
  }
  mutate "G4-1 the forensic local dropped from triggers_replace" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('    join("\\n", local.luks_monitor_forensic_print),\n', '', 1)
X
)"
  mutate "G4-2 the forensic step moved after the exit-17 arm step" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
(lambda blk: s.replace(blk, '', 1).replace('  # State into the apply log.', blk + '  # State into the apply log.', 1) if s.count(blk) == 1 else s)('  provisioner "remote-exec" {\n    inline = local.luks_monitor_forensic_print\n  }\n')
X
)"
  mutate "G4-3 the local renamed away (inline_raw resolves nothing)" 1 LMI_LUKS_TF "$T" "s.replace('$FL', '  luks_monitor_forensic_printx = [', 1)"
  mutate "G4-4 a second local-sourced step whose local is not hashed" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('    inline = local.luks_monitor_forensic_print\n  }\n', '    inline = local.luks_monitor_forensic_print\n  }\n  provisioner "remote-exec" {\n    inline = local.luks_monitor_other_print\n  }\n', 1) + '\nlocals {\n  luks_monitor_other_print = [\n    "echo other || true",\n  ]\n}\n'
X
)"
  fins "G4-5 the forensic print cats the env file" "'\"cat /etc/default/luks-monitor || true\"'"
  fins "G4-6 a journalctl tail added" "'\"journalctl -u workspaces-luks-deadman.service -n 20 --no-pager || true\"'"
  fins "G4-7 the raw ExecStart printed" "'\"systemctl show -p ExecStart --value workspaces-luks-deadman.service || true\"'"
  fins "G4-8 systemctl cat of the dead-man unit" "'\"systemctl cat workspaces-luks-deadman.service || true\"'"
  fins "G4-9 a systemctl show with no -p" "'\"systemctl show workspaces-luks-deadman.service --no-pager || true\"'"
  fins "G4-10 cat /etc/fstab" "'\"cat /etc/fstab || true\"'"
  fins "G4-11 apt-config dump" "'\"apt-config dump || true\"'"
  fins "G4-12 an unguarded line" "'\"echo \\\\\"x=\$(uptime -s)\\\\\"\"'"
  mutate "G4-13 ExecStart smuggled into the property loop" 1 LMI_LUKS_TF "$T" "s.replace('for p in LoadState ', 'for p in ExecStart LoadState ', 1)"
  mutate "G4-14 the fstab options redaction removed" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('o = bad ? \\"<redacted-options>\\" : $4; ', 'o = $4; ', 1)
X
)"
  fins "G4-15 a var. reference in the forensic print" "'\"echo \$\${var.betterstack_paid_tier} || true\"'.replace('\$\$', '\$')"
  fins "G4-16 systemctl status of the dead-man unit" "'\"systemctl status workspaces-luks-deadman.service --no-pager || true\"'"
  mutate "G4-17 the forensic step deleted" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('  provisioner "remote-exec" {\n    inline = local.luks_monitor_forensic_print\n  }\n', '', 1)
X
)"
  # Every structural row is order-blind (this edit fails ONLY the change-detector pin): a reorder
  # of the public print is still a change a security re-review has to sign off.
  mutate "G4-H1 the forensic lines reordered (only the pin reds)" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
(lambda m: s[:m.start()] + m.group(2) + m.group(1) + s[m.end():])(re.search(r'(    "echo \\"luks-monitor forensic uptime-s=[^\n]*\n)(    "echo \\"luks-monitor forensic reboot-required=[^\n]*\n)', s))
X
)"
  # #9045 review: fstab allowlists, argv none, per-unit stub (I-M1), leak rows, pin, unit parity.
  mutate "G4-18 the option allowlist accepts any key=value" 1 LMI_LUKS_TF "$T" "s.replace('|user_xattr|acl|', '|user_xattr|acl|[a-z]+=.*|', 1)"
  mutate "G4-19 the device allowlist bypassed" 1 LMI_LUKS_TF "$T" "s.replace('if (d !~ ', 'if (0 && d !~ ', 1)"
  mutate "G4-20 has_nofail never set" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('if (a[i] == \\"nofail\\") nf = \\"yes\\"; ', '', 1)
X
)"
  mutate "G4-21 an empty argv hashed (the e3b0c442 digest again)" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('if [ -n \\"$av\\" ]; then printf', 'if true; then printf', 1)
X
)"
  mutate "G4-22 the .timer-labelled loop reads the .service (I-M1)" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('--value workspaces-luks-deadman.timer 2>/dev/null || echo none)\\"; done', '--value workspaces-luks-deadman.service 2>/dev/null || echo none)\\"; done', 1)
X
)"
  fins "G4-23 a glob read of /etc/default" "'\"cat /etc/default/luks-m* || true\"'"
  fins "G4-24 systemctl -M .host status" "'\"systemctl -M .host status workspaces-luks-deadman.service --no-pager || true\"'"
  fins "G4-25 a /proc/*/cmdline glob" "'\"cat /proc/*/cmdline || true\"'"
  mutate "G4-26 journal''ctl (no deny row sees it; only the pin)" 1 LMI_LUKS_TF "$T" "$(cat <<'X'
s.replace('  luks_monitor_forensic_print = [\n', '  luks_monitor_forensic_print = [\n    "journal' + "''" + 'ctl -u workspaces-luks-deadman.service --no-pager || true",\n', 1)
X
)"
  mutate "G4-27 apt-config proxy key appended (no deny row sees it; only the pin)" 1 LMI_LUKS_TF "$T" "s.replace('apt-config shell AR Unattended-Upgrade::Automatic-Reboot 2>', 'apt-config shell AR Unattended-Upgrade::Automatic-Reboot P Acquire::http::Proxy 2>', 1)"
  mutate "G4-P1 the dead-man unit renamed in workspaces-cutover.sh only" 1 LMI_CUTOVER_SH "$LMI_CUTOVER_SH" "re.sub(r'--unit=workspaces-luks-deadman\\b', '--unit=workspaces-luks-deadman-v2', s, 1)"
  mutate "G4-P2 the state print names another dead-man service" 1 LMI_LUKS_TF "$T" "s.replace('workspaces-luks-deadman.timer workspaces-luks-deadman.service --no-pager', 'workspaces-luks-deadman.timer workspaces-luks-deadman-old.service --no-pager', 1)"
  # A deleted row must not pass silently: 20 Guard 1 + 17 Guard 2 + 14 Guard 3 + 30 Guard 4 rows.
  MUT_ROWS_EXPECTED=81
  if [[ "$mut_rows" -ne "$MUT_ROWS_EXPECTED" ]]; then
    printf 'FAIL - %s mutation rows ran, expected %s\n' "$mut_rows" "$MUT_ROWS_EXPECTED"
    exit 1
  fi
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"

# Anti-vacuity floor. The threshold sits on the line directly above its `if`. It is EXACT: 118 is the
# measured inner-run (LMI_MUTANT=1) assertion count, and the outer run adds the 81 mutation rows
# (MUT_ROWS_EXPECTED), so deleting any one check, not only a whole block, trips it. Adding a check
# means raising 118 here.
_lmi_mut_floor="${LMI_MUTANT:+0}"
MIN_ASSERTIONS=$((118 + ${_lmi_mut_floor:-81}))
if [[ "$pass" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FAIL - only %s assertions passed (floor %s) — a block stopped running\n' "$pass" "$MIN_ASSERTIONS"
  exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
