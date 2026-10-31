#!/usr/bin/env bash
# Guard 3 of the #11631 plan: no native Better Stack logs alert is created with a query_period above 900 s, and the
# two retired once-a-day dead-man alerts stay gone.
#
# WHY. A logtail_exploration_alert whose row arrives once a day cannot see its row: the retired
# luks_monitor_host_timer_dark (query_period 97200) and claude_cost_capture_dark (86400) read `Current value: 0`
# through 33 healthy nights. Alerts created since 2026-10-01 are measured against a 900 s ceiling (the table in
# betterstack-logs-alerts.tf); a dead-man that needs a longer window is an archive-fed heartbeat
# (scripts/deadman-heartbeat-feeder.sh), not a longer window here. This suite is the sentinel that keeps the next
# one from being written the old way.
#
# WHAT IT READS. Every logtail_exploration_alert resource block in every .tf under apps/web-platform/infra/ (the
# working tree: tracked plus not-yet-committed files, so a new file cannot dodge the scan), after lexing out `#`, `//`
# and /* */ comments and heredoc bodies (the file carries query_period values inside comments, e.g. a dated
# measurement table and `# query_period = 2592000`). query_period is parsed per block; a value that is not an
# integer literal is a FAILURE, never a pass. Ceiling: 900 for every alert except the live legacy ones, which are
# allowlisted BY NAME, each with its own ceiling (a renamed copy of an allowlisted alert is therefore RED).
# ALLOWLIST CHANGES ARE EDITS TO THIS FILE, which review sees; the alerts at origin/main are printed so a weakening
# shows up as a diff of printed names.
#
# ANTI-VACUITY. The number of blocks the lexer parsed must equal a naive count of
# `resource "logtail_exploration_alert` / `logtail_dashboard_alert` headers (prefix match, no closing quote, any
# whitespace, quoted or bare labels) AND a LINE-ANCHORED count over the unlexed text that shares no code with the
# lexer (anchored_headers: it does not track strings, so a quote desync that hides a block from the lexer cannot hide
# its header line from it), and be at least 1: a lexer that finds nothing, a desync, or a rename of the resource
# kind, is a failure. The lexer reads a quote inside `${...}` / `%{...}` as a NESTED string (skip_interp). Both kinds are held to the ceiling; .tf.json files are scanned too; a lifecycle
# ignore_changes over query_period (or all) is a failure; a duplicate query_period, an unterminated string,
# heredoc or block comment is a failure; the census entries must be LIVE lines inside INTENDED_DESTROYS.
# FLOORS are exact and compared with `!=` (EXPECT_BLOCKS, MIN_PASSES): adding OR removing a case or an alert means
# re-deriving them. ALLOW is keyed by (kind, file, name); a lifecycle ignore_changes list is bracket-matched.
# The two ALLOW entries are GRANDFATHERED, not creatable: the API refuses a new alert above 900 (commit 744396abbb).
#
# MUTATIONS ARE COMMITTED. Each row is applied to a scratch copy of the .tf files by an exact-string edit that must
# match once, and must go RED (or, for the must-PASS rows, stay GREEN). Harness rows: the same checker with the
# ceiling raised to 100000 turns mutation 1 GREEN (the sentinel reads the ceiling); a new alert at exactly 900 stays
# GREEN.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
INFRA_REL="apps/web-platform/infra"
APPLY_REL=".github/workflows/apply-web-platform-infra.yml"
CENSUS_REL="tests/scripts/test-infra-privileged-tier-census.sh"
PY="$(type -P python3)" || { echo "FATAL: python3 not found" >&2; exit 1; }

fails=0; passes=0; cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires the verbatim body).
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
WORK="$(mktemp -d "${TMPDIR}/logs-alert-ceiling.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
assert_fixture_dir "$WORK"
trap 'rm -rf -- "$WORK"' EXIT

# ── the checker ──────────────────────────────────────────────────────────────────────────────
cat > "$WORK/checker.py" <<'PYCHK'
import json, re, sys, os

DEFAULT_CEILING = 900
# (resource kind, file relative to the infra dir, name) -> its own ceiling. The live legacy alerts only; see the
# header. Keyed by all three, not by name alone: a same-named dashboard alert, or the same name in another file or in
# a .tf.json, is a DIFFERENT resource and gets the default ceiling.
# GRANDFATHERED, NOT CREATABLE: claude_cost_daily_burn (86400) and inngest_luks_wrong_volume (5400) exist from
# September. The API now REFUSES a new alert above 900 (the fourth Better Stack 422, commit 744396abbb: the
# key-probe alert asked for 5400 and was refused), so neither value can be copied into a new alert; an entry here
# keeps a live legacy resource from turning the sentinel red, it is not a precedent.
ALLOW = {
    ("logtail_exploration_alert", "betterstack-logs-alerts.tf", "claude_cost_daily_burn"): 86400,
    ("logtail_exploration_alert", "betterstack-logs-alerts.tf", "inngest_luks_wrong_volume"): 5400,
}
ALERT_KINDS = ("logtail_exploration_alert", "logtail_dashboard_alert")
RETIRED = ("luks_monitor_host_timer_dark", "claude_cost_capture_dark")
RETAINED_TARGETS = (
    "-target=logtail_exploration.claude_cost_capture_dark",
    "-target=logtail_exploration_alert.claude_cost_capture_dark",
    "-target=logtail_exploration.luks_monitor_host_timer_dark",
    "-target=logtail_exploration_alert.luks_monitor_host_timer_dark",
)
CENSUS_ENTRIES = (
    '"logtail_exploration.claude_cost_capture_dark": "#11631"',
    '"logtail_exploration_alert.claude_cost_capture_dark": "#11631"',
    '"logtail_exploration.luks_monitor_host_timer_dark": "#11631"',
    '"logtail_exploration_alert.luks_monitor_host_timer_dark": "#11631"',
)
LEX_PROBLEMS = []


def skip_interp(s, j):
    """s[j:j+2] is `${` or `%{`. Return the index just past the matching `}`. A quote inside opens a NESTED string
    (lexed by skip_string, so a `}` or a `"` inside it cannot move the depth or close the outer string), a nested
    `${`/`%{` opens a nested interpolation, and a plain `{` (an object constructor) is balanced."""
    depth, n = 1, len(s)
    j += 2
    while j < n:
        c = s[j]
        if c == '"':
            j = skip_string(s, j)
            continue
        if s.startswith("${", j) or s.startswith("%{", j):
            depth += 1
            j += 2
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    LEX_PROBLEMS.append("unterminated-interpolation")
    return n


def skip_string(s, i):
    """s[i] == '"'. Return the index just past the closing quote (len(s) if unterminated). `$${` and `%%{` are
    LITERAL escapes (not interpolation starts); `${` and `%{` open an interpolation or directive, which is lexed by
    skip_interp: strings nested inside it are strings, not delimiters of this one."""
    j, n = i + 1, len(s)
    while j < n:
        if s[j] == "\\":
            j += 2
            continue
        if s.startswith("$${", j) or s.startswith("%%{", j):
            j += 3
            continue
        if s.startswith("${", j) or s.startswith("%{", j):
            j = skip_interp(s, j)
            continue
        if s[j] == '"':
            return j + 1
        j += 1
    LEX_PROBLEMS.append("unterminated-string")
    return n


def lex(s):
    """Return s with comments and heredoc bodies blanked (newlines kept). Strings are preserved."""
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            j = skip_string(s, i)
            out.append(s[i:j])
            i = j
        elif c == "#" or s.startswith("//", i):
            j = s.find("\n", i)
            j = n if j == -1 else j
            i = j
        elif s.startswith("/*", i):
            j = s.find("*/", i + 2)
            if j == -1:
                LEX_PROBLEMS.append("unterminated-block-comment")
                j = n
            else:
                j += 2
            out.append("\n" * s.count("\n", i, j))
            i = j
        elif s.startswith("<<", i) and re.match(r"<<-?[A-Za-z_][A-Za-z0-9_]*[ \t]*\r?\n", s[i:]):
            m = re.match(r"<<(-?)([A-Za-z_][A-Za-z0-9_]*)[ \t]*\r?\n", s[i:])
            tag = m.group(2)
            j = i + m.end()
            out.append("<<HEREDOC\n")
            closed = False
            while j < n:
                k = s.find("\n", j)
                k = n if k == -1 else k
                line = s[j:k]
                j = k + 1
                out.append("\n")
                if line.strip() == tag:
                    closed = True
                    break
            if not closed:
                LEX_PROBLEMS.append("unterminated-heredoc")
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def find_close(s, i):
    """s[i] == '{'. Return the index of the matching '}' ignoring braces inside strings."""
    depth, j, n = 0, i, len(s)
    while j < n:
        c = s[j]
        if c == '"':
            j = skip_string(s, j)
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1


def header_re(kind):
    # Whitespace of any kind between the tokens, and quoted or bare labels (HCL accepts both).
    return re.compile(r'\bresource\s+"?' + kind + r'"?\s+"?([A-Za-z0-9_-]+)"?\s*\{')


def alerts_in(text):
    """-> (list of (name, kind, body-or-None-if-unbalanced), naive_count, raw_count)."""
    lexed = lex(text)
    # Independent of the block parser: a prefix match (no closing quote) over the comment- and heredoc-free text, so
    # a renamed resource kind or a header the block regex cannot read is counted here and missing there.
    naive = sum(len(re.findall(r'\bresource\s+"?' + k, lexed)) for k in ALERT_KINDS)
    raw = sum(len(re.findall(r'\bresource\s+"?' + k, text)) for k in ALERT_KINDS)
    found = []
    for k in ALERT_KINDS:
        for m in header_re(k).finditer(lexed):
            o = m.end() - 1
            c = find_close(lexed, o)
            found.append((m.group(1), k, lexed[o + 1:c] if c != -1 else None))
    return found, naive, raw


def skeleton(body):
    """The body with every string collapsed to "" so a brace inside a string cannot move the depth counter."""
    out, i = [], 0
    while i < len(body):
        if body[i] == '"':
            i = skip_string(body, i)
            out.append('""')
        else:
            out.append(body[i])
            i += 1
    return "".join(out)


def top_level_attrs(body, key):
    """Value texts of every `key = value` attribute at depth 0 of this block's body ({ [ ( all count as depth);
    strings are collapsed first, so a decoy inside a nested map or a brace inside a string cannot be mistaken."""
    sk = skeleton(body)
    depth, vals = 0, []
    for line in sk.split("\n"):
        if depth == 0:
            m = re.match(r"\s*" + re.escape(key) + r"\s*=\s*(.*?)\s*$", line)
            if m:
                vals.append(m.group(1))
        depth += sum(line.count(c) for c in "{[(") - sum(line.count(c) for c in "}])")
    return vals


def anchored_headers(text):
    """An independent, LINE-based count of alert headers in the unlexed text. It shares no code with lex(): it does
    not track strings at all, so a quote desync (the failure that hides a block from lex()) cannot hide a header from
    it. Lines that cannot declare a resource are skipped by line shape only: a line whose first non-blank text is `#`
    or `//`, a block comment OPENED at the start of a line (until a line containing `*/`), and heredoc bodies (opened
    by `<<TAG` / `<<-TAG` ending a line, closed by a line that is exactly TAG). A header written on a line that does
    not start with `resource`, or inside a block comment that opens mid-line, is not credited, so parsed > anchored
    fails closed."""
    n, tag, block = 0, None, False
    for line in text.split("\n"):
        st = line.strip()
        if tag is not None:
            if st == tag:
                tag = None
            continue
        if block:
            if "*/" in line:
                block = False
            continue
        if st.startswith("#") or st.startswith("//"):
            continue
        if st.startswith("/*"):
            if "*/" not in st[2:]:
                block = True
            continue
        m = re.search(r"<<-?([A-Za-z_][A-Za-z0-9_]*)[ \t]*\r?$", line)
        if m:
            tag = m.group(1)
        if re.match(r'[ \t]*resource\s+"?(?:' + "|".join(ALERT_KINDS) + r')\b', line):
            n += 1
    return n


def covers_query_period(elem):
    """One ignore_changes element: the attribute itself, or `all` / the legacy `*`, in the bare form, the legacy
    quoted form (`"query_period"`), or the `${...}` interpolation form."""
    e = elem.strip()
    if len(e) >= 2 and e[0] == e[-1] == '"':
        e = e[1:-1].strip()
    m = re.fullmatch(r"\$\{\s*(.*?)\s*\}", e, re.S)
    if m:
        e = m.group(1)
    return e in ("query_period", "all", "*")


def ignore_changes_values(body):
    """Every `ignore_changes = <value>` OUTSIDE strings, as ("list", [element text, ...]) or ("other", text). The list
    is BRACKET-MATCHED with strings skipped (so `name["x"]`, `metadata[0]` and a multi-line list with a trailing comma
    are one list, split at depth-1 commas); an unterminated list is "other"."""
    n, j = len(body), 0
    while j < n:
        c = body[j]
        if c == '"':
            j = skip_string(body, j)
            continue
        m = None
        if body.startswith("ignore_changes", j) and (j == 0 or not (body[j - 1].isalnum() or body[j - 1] in "_-")):
            m = re.compile(r"ignore_changes\s*=\s*").match(body, j)
        if not m:
            j += 1
            continue
        k = m.end()
        if k < n and body[k] == "[":
            q, depth, start, elems = k + 1, 1, k + 1, []
            while q < n:
                ch = body[q]
                if ch == '"':
                    q = skip_string(body, q)
                    continue
                if ch in "[{(":
                    depth += 1
                elif ch in "]})":
                    depth -= 1
                    if depth == 0:
                        break
                elif ch == "," and depth == 1:
                    elems.append(body[start:q])
                    start = q + 1
                q += 1
            if depth:
                yield ("other", body[k:k + 40])
                return
            elems.append(body[start:q])
            yield ("list", [e.strip() for e in elems if e.strip()])
            j = q + 1
        else:
            yield ("other", body[k:k + 40])
            j = k
    return


def ignores_query_period(body):
    """True when a lifecycle ignore_changes can cover query_period. A value that is neither a list literal nor read to
    its end fails closed (counts as covering): Terraform only accepts a static list or `all`, so anything else is
    either a typo or an attempt to be clever."""
    for kind, val in ignore_changes_values(body):
        if kind == "other" or any(covers_query_period(e) for e in val):
            return True
    return False


def json_blocks(doc):
    """Yield (kind, name, body-dict) for every resource block of the tracked kinds in a .tf.json document."""
    res = doc.get("resource") if isinstance(doc, dict) else None
    for r in (res if isinstance(res, list) else [res]):
        if not isinstance(r, dict):
            continue
        for kind, named in r.items():
            for nm in (named if isinstance(named, list) else [named]):
                if not isinstance(nm, dict):
                    continue
                for name, body in nm.items():
                    for b in (body if isinstance(body, list) else [body]):
                        yield kind, name, b


def main(infra_dir, apply_path, census_path):
    bad, seen = [], []
    naive_total = parsed_total = raw_total = anchored_total = 0
    tf_files = []
    for root, _d, files in os.walk(infra_dir):
        for f in files:
            if f.endswith(".tf") or f.endswith(".tf.json"):
                tf_files.append(os.path.join(root, f))
    tf_files.sort()
    if not [p for p in tf_files if p.endswith(".tf")]:
        bad.append("no-tf-files-found")

    def judge(rel, kind, name, qp_vals, ignores):
        if len(qp_vals) > 1:
            bad.append("duplicate-query_period:%s:%s" % (rel, name))
            return
        raw = qp_vals[0] if qp_vals else None
        if ignores:
            bad.append("ignore_changes-covers-query_period:%s:%s" % (rel, name))
        if raw is None or not re.fullmatch(r"[0-9]+", str(raw)):
            bad.append("unparsable-query_period:%s:%s=%r" % (rel, name, raw))
            return
        qp = int(raw)
        ceiling = ALLOW.get((kind, rel, name), DEFAULT_CEILING)
        seen.append((name, qp, ceiling, rel, (kind, rel, name) in ALLOW))
        if qp > ceiling:
            bad.append("query_period-above-ceiling:%s:%s:%d>%d" % (rel, name, qp, ceiling))

    for p in tf_files:
        rel = os.path.relpath(p, infra_dir).replace(os.sep, "/")
        text = open(p, encoding="utf-8").read()
        if p.endswith(".tf.json"):
            try:
                doc = json.loads(text)
            except ValueError:
                bad.append("unparsable-tf-json:%s" % rel)
                continue
            for kind, name, b in json_blocks(doc):
                if name in RETIRED and kind in ("logtail_exploration", "logtail_exploration_alert", "logtail_dashboard_alert"):
                    bad.append("retired-resource-redeclared:%s.%s" % (kind, name))
                if kind not in ALERT_KINDS:
                    continue
                if not isinstance(b, dict):
                    bad.append("unparsable-tf-json-block:%s:%s" % (rel, name))
                    continue
                v = b.get("query_period")
                lc = b.get("lifecycle")
                ign = False
                for l in (lc if isinstance(lc, list) else [lc]):
                    if isinstance(l, dict):
                        ic = l.get("ignore_changes")
                        # A string or a list of strings, each bare or in the legacy `${...}` form; anything else fails closed.
                        if ic is not None and any((not isinstance(e, str)) or covers_query_period(e) for e in (ic if isinstance(ic, list) else [ic])):
                            ign = True
                judge(rel, kind, name, [] if v is None else [str(v) if isinstance(v, int) and not isinstance(v, bool) else repr(v)], ign)
            continue
        before = len(LEX_PROBLEMS)
        lexed = lex(text)
        del LEX_PROBLEMS[before:]
        before = len(LEX_PROBLEMS)
        found, naive, raw_n = alerts_in(text)
        for lp in sorted(set(LEX_PROBLEMS[before:])):
            bad.append("lex-problem:%s:%s" % (rel, lp))
        naive_total += naive
        parsed_total += len(found)
        raw_total += raw_n
        anchored_total += anchored_headers(text)
        for kind in ("logtail_exploration", "logtail_exploration_alert", "logtail_dashboard_alert"):
            for m in re.finditer(r'\bresource\s+"?' + kind + r'"?\s+"?([A-Za-z0-9_-]+)"?', lexed):
                if m.group(1) in RETIRED:
                    bad.append("retired-resource-redeclared:%s.%s" % (kind, m.group(1)))
        for name, kind, body in found:
            if body is None:
                bad.append("unbalanced-block:%s:%s" % (rel, name))
                continue
            judge(rel, kind, name, top_level_attrs(body, "query_period"), ignores_query_period(body))
    # naive comes from the SAME lexer as parsed (it sees the same text), so parsed == naive proves only that the block
    # regex agrees with the header regex; anchored comes from a different mechanism (see anchored_headers) and is the
    # check that notices a lexer desync hiding a header.
    if parsed_total != naive_total or parsed_total < 1 or parsed_total > raw_total or parsed_total != anchored_total:
        bad.append("anti-vacuity:parsed=%d naive=%d raw=%d anchored=%d" % (parsed_total, naive_total, raw_total, anchored_total))
    apply_text = open(apply_path, encoding="utf-8").read()
    for t in RETAINED_TARGETS:
        if re.search(r"(?m)^[ \t]*" + re.escape(t) + r"( \\)?[ \t]*$", apply_text) is None:
            bad.append("retained-destroy-target-missing:%s" % t)
    census_text = open(census_path, encoding="utf-8").read()
    # A LIVE entry: a non-comment line inside the INTENDED_DESTROYS dict, not a substring anywhere in the file (a
    # commented-out entry, or one moved to another dict, must not satisfy it).
    cm = re.search(r"(?ms)^INTENDED_DESTROYS = \{\n(.*?)^\}", census_text)
    # Only the lines under the `"apps/web-platform/infra"` key count: the same address under another root's key (or
    # another dict) is a claim about a different Terraform root.
    km = re.search(r'(?ms)^    "apps/web-platform/infra": \{\n(.*?)^    \},', cm.group(1) + "\n" if cm else "")
    live = [l.strip() for l in (km.group(1).split("\n") if km else []) if not l.strip().startswith("#")]
    for e in CENSUS_ENTRIES:
        if not any(re.fullmatch(re.escape(e) + r",?\s*(#.*)?", l) for l in live):
            bad.append("census-intended-destroy-missing:%s" % e.split(":")[0].strip('"'))
    for name, qp, ceiling, rel, grand in sorted(seen):
        print("alert %s query_period=%d ceiling=%d (%s)%s" % (name, qp, ceiling, rel, " grandfathered" if grand else ""))
    print("blocks parsed=%d naive=%d anchored=%d" % (parsed_total, naive_total, anchored_total))
    for b in bad:
        print("VIOLATION " + b)
    sys.exit(1 if bad else 0)


main(sys.argv[1], sys.argv[2], sys.argv[3])
PYCHK
# Checker variants for the harness rows: each removes ONE defence so a fixture built for that defence can be shown
# to pass without it (the fixture CAN go green; the defence is what turns it red).
"$PY" -I - "$WORK/checker.py" "$WORK" <<'PYM'
import sys
s = open(sys.argv[1]).read()
def variant(name, old, new):
    assert s.count(old) == 1, (name, s.count(old))
    open("%s/%s" % (sys.argv[2], name), "w").write(s.replace(old, new))
variant("checker-wide.py", "DEFAULT_CEILING = 900", "DEFAULT_CEILING = 100000")
variant("checker-noesc.py", 'if s.startswith("$${", j) or s.startswith("%%{", j):', "if False:")
variant("checker-nostr.py", "sk = skeleton(body)", "sk = body")
variant("checker-noign.py", "if ignores:", "if False:")
# The lexer as it was before the interpolation fix: a quote inside `${...}`/`%{...}` is not a string, so a `}` inside
# it moves the depth and the next quote closes the outer string.
OLD_SKIP = r'''def skip_string(s, i):
    j, depth, n = i + 1, 0, len(s)
    while j < n:
        if s[j] == "\\":
            j += 2
            continue
        if s.startswith("$${", j) or s.startswith("%%{", j):
            j += 3
            continue
        if s.startswith("${", j) or s.startswith("%{", j):
            depth += 1
            j += 2
            continue
        if s[j] == "}" and depth:
            depth -= 1
        elif s[j] == '"' and depth == 0:
            return j + 1
        j += 1
    LEX_PROBLEMS.append("unterminated-string")
    return n


'''
a, b = s.index("def skip_interp(s, j):"), s.index("def lex(s):")
old_lexer = s[:a] + OLD_SKIP + s[b:]
open("%s/checker-oldlex.py" % sys.argv[2], "w").write(old_lexer)
noanchor = "or parsed_total != anchored_total:"
assert s.count(noanchor) == 1
open("%s/checker-noanchor.py" % sys.argv[2], "w").write(s.replace(noanchor, ":"))
assert old_lexer.count(noanchor) == 1
open("%s/checker-oldlex-noanchor.py" % sys.argv[2], "w").write(old_lexer.replace(noanchor, ":"))
variant("checker-oldign.py", "    for kind, val in ignore_changes_values(body):",
        "    return re.search(r\"ignore_changes\\s*=\\s*(?:all\\b|\\[[^\\]]*?\\bquery_period\\b[^\\]]*\\])\", body, re.S) is not None\n    for kind, val in ignore_changes_values(body):")
variant("checker-byname.py", "ceiling = ALLOW.get((kind, rel, name), DEFAULT_CEILING)",
        "ceiling = max([v for (_k, _r, nm), v in ALLOW.items() if nm == name] or [DEFAULT_CEILING])")
variant("checker-anykey.py", "live = [l.strip() for l in (km.group(1).split(\"\\n\") if km else [])",
        "live = [l.strip() for l in (cm.group(1).split(\"\\n\") if cm else [])")
PYM

# ── a working-tree snapshot of the .tf files, the apply workflow and the census ───────────────
snap() { # <dest> -> copies the tracked-plus-untracked .tf files under the infra dir, the apply workflow, the census
  local dest="$1" f
  assert_fixture_dir "$dest"
  rm -rf -- "$dest"; mkdir -p "$dest/infra" "$dest/.github/workflows" "$dest/tests/scripts"
  while IFS= read -r f; do
    [[ -n "$f" && -f "$REPO/$f" ]] || continue
    mkdir -p "$dest/infra/$(dirname "${f#"$INFRA_REL"/}")"
    cp "$REPO/$f" "$dest/infra/${f#"$INFRA_REL"/}"
  done < <(git -C "$REPO" ls-files --cached --others --exclude-standard -- "$INFRA_REL/*.tf" "$INFRA_REL/*.tf.json")
  cp "$REPO/$APPLY_REL" "$dest/apply.yml"
  cp "$REPO/$CENSUS_REL" "$dest/census.sh"
}
run_checker() { # <snapshot-dir> [checker] -> rc; output in $WORK/out
  "$PY" -I "${2:-$WORK/checker.py}" "$1/infra" "$1/apply.yml" "$1/census.sh" > "$WORK/out" 2>&1
}
edit() { # <snapshot-dir> <relative-file> <old> <new> -> exact-once replace; returns 0 if landed
  "$PY" -I - "$1/$2" "$3" "$4" <<'PYE'
import sys
p = sys.argv[1]
s = open(p).read()
if s.count(sys.argv[2]) != 1:
    sys.stderr.write("edit: %d occurrences\n" % s.count(sys.argv[2]))
    sys.exit(3)
open(p, "w").write(s.replace(sys.argv[2], sys.argv[3]))
PYE
}
append() { # <snapshot-dir> <relative-file> <text>
  printf '\n%s\n' "$3" >> "$1/$2"
}

# own_ctl <label> <needle> <driver-fn> [args...]: run a verdict owner in a SUBSHELL (its counters die with it)
# against one wrong input; require EXACTLY ONE failure line carrying the needle and no pass line. Reported by
# printf and exit so a helper neutered to always-pass still stops the suite.
own_ctl() {
  local label="$1" needle="$2" out nf np
  shift 2
  out="$("$@" 2>&1)"
  nf="$(grep -c '^  FAIL:' <<<"$out" || true)"; np="$(grep -c '^  PASS:' <<<"$out" || true)"
  cases=$((cases + 1))
  if [[ "$nf" == 1 && "$np" == 0 ]] && grep -qF -- "$needle" <<<"$out"; then
    printf '  PASS: verdict-owner control: %s\n' "$label"; passes=$((passes + 1))
  else
    printf 'FATAL: verdict-owner control FAILED: %s (saw %s failure line(s) and %s pass line(s); wanted exactly one failure carrying: %s)\n' "$label" "$nf" "$np" "$needle" >&2
    sed 's/^/        | /' <<<"$out" >&2
    exit 1
  fi
}

# own_ctl is itself a verdict owner: the condition that grades every control in this file. Replacing it with
# `if true` would turn each of them green without a failure. own_meta runs own_ctl in a SUBSHELL against a driver of
# known behaviour and requires the exit status and text own_ctl must produce (exit 1 with its FATAL line for two
# failures, for a driver that fails nothing and for a wrong needle; a clean return with its PASS line for exactly one
# failure carrying the needle). It reports through printf and exit.
own_meta() { # <label> <want-rc> <want-text> <driver-fn>
  local label="$1" want_rc="$2" want_text="$3" out rc
  shift 3
  out="$( ( own_ctl "META-SUBJECT" "NEEDLE_THE_DRIVER_MUST_CARRY" "$@" ) 2>&1 )"; rc=$?
  cases=$((cases + 1))
  if [[ "$rc" == "$want_rc" ]] && grep -qF -- "$want_text" <<<"$out"; then
    printf '  PASS: own_ctl control: %s\n' "$label"; passes=$((passes + 1))
  else
    printf 'FATAL: own_ctl control FAILED: %s (exit %s, wanted %s; wanted the text: %s)\n' "$label" "$rc" "$want_rc" "$want_text" >&2
    sed 's/^/        | /' <<<"$out" >&2
    exit 1
  fi
}
meta_drv_two() { printf '  FAIL: first NEEDLE_THE_DRIVER_MUST_CARRY\n  FAIL: second\n' >&2; }
meta_drv_none() { printf '  PASS: nothing failed\n'; }
meta_drv_needle() { printf '  FAIL: one failure that carries something else\n' >&2; }
meta_drv_good() { printf '  FAIL: exactly one, NEEDLE_THE_DRIVER_MUST_CARRY\n' >&2; }
own_meta "two failures stop the suite with the FATAL line" 1 "saw 2 failure line(s)" meta_drv_two
own_meta "a driver that fails nothing stops the suite with the FATAL line" 1 "saw 0 failure line(s) and 1 pass line(s)" meta_drv_none
own_meta "a wrong needle stops the suite with the FATAL line" 1 "verdict-owner control FAILED: META-SUBJECT" meta_drv_needle
own_meta "exactly one failure carrying the needle returns cleanly with the PASS line" 0 "PASS: verdict-owner control: META-SUBJECT" meta_drv_good

BASE="$WORK/base"; snap "$BASE"

echo "== the shipped tree =="
cases=$((cases + 1))
if run_checker "$BASE"; then pass "no logtail_exploration_alert exceeds its ceiling; the retired alerts are absent; the retained destroy targets and census entries are present"
else fail "the shipped tree violates the sentinel"; sed 's/^/        | /' "$WORK/out" >&2; fi
sed 's/^/  | /' "$WORK/out"
cases=$((cases + 1))
_parsed="$(sed -n 's/^blocks parsed=\([0-9]*\) naive=.*/\1/p' "$WORK/out")"
# EXACT, not "at least": the measured count of alert blocks in the shipped tree. A removed block (a lexer that
# stopped seeing one) trips it; a legitimately added or removed alert means editing this number.
EXPECT_BLOCKS=17
if [[ "$_parsed" =~ ^[0-9]+$ ]] && (( _parsed == EXPECT_BLOCKS )); then pass "anti-vacuity: the lexer parsed exactly $EXPECT_BLOCKS alert blocks (the naive and the line-anchored counts agree)"
else fail "anti-vacuity: parsed '$_parsed' blocks, the exact count is $EXPECT_BLOCKS"; fi
cases=$((cases + 1))
if ! grep -q 'alert claude_cost_capture_dark\|alert luks_monitor_host_timer_dark' "$WORK/out"; then pass "neither retired alert is among the parsed blocks"
else fail "a retired alert block is present"; fi
for _n in claude_cost_daily_burn inngest_luks_wrong_volume; do
  cases=$((cases + 1))
  if grep -q "^alert $_n " "$WORK/out"; then pass "the allowlisted legacy alert $_n is present and within its own ceiling"
  else fail "the allowlisted legacy alert $_n was not found (a stale allowlist entry, or the alert was renamed)"; fi
done
echo "-- alerts at origin/main (printed so a weakening shows as a diff of names) --"
if git -C "$REPO" cat-file -e origin/main:"$INFRA_REL/betterstack-logs-alerts.tf" 2>/dev/null; then
  git -C "$REPO" show origin/main:"$INFRA_REL/betterstack-logs-alerts.tf" \
    | "$PY" -I -c '
import re, sys
s = sys.stdin.read()
print("  origin/main:", " ".join(sorted(re.findall(r"(?m)^resource \"logtail_exploration_alert\" \"([a-z0-9_]+)\"", s))))'
else
  echo "  (origin/main is not available in this checkout; nothing to print)"
fi

echo "== committed mutation rows =="
expect_red() { # <row> <dir> <violation-substring> [checker]
  cases=$((cases + 1))
  if run_checker "$2" "${4:-}"; then fail "mutation row $1 SURVIVED (the sentinel stayed green)"
  elif grep -q "VIOLATION .*$3" "$WORK/out"; then pass "mutation row $1 is RED as predicted ($3)"
  else fail "mutation row $1 went red for another reason"; sed 's/^/        | /' "$WORK/out" >&2; fi
}
expect_green() { # <row> <dir> [checker]
  cases=$((cases + 1))
  if run_checker "$2" "${3:-}"; then pass "mutation row $1 stays GREEN (must-PASS)"
  else fail "mutation row $1 went red but must stay green"; sed 's/^/        | /' "$WORK/out" >&2; fi
}
landed() { # <row> <rc-of-edit>
  cases=$((cases + 1))
  if [[ "$2" == 0 ]]; then pass "mutation row $1 landed"; else fail "mutation row $1 did NOT land (its verdict would be vacuous)"; fi
}
ALERT_TPL='resource "logtail_exploration_alert" "%s" {
  exploration_id = logtail_exploration.inngest_step_524.id
  name           = "%s"
  alert_type     = "threshold"
  operator       = "higher_than"
  value          = 0
  query_period   = %s%s
  check_period   = 60
  recovery_period = 60
}'
mk_alert() { printf "$ALERT_TPL" "$1" "$1" "$2" "${3:-}"; }

# M1: add an alert with query_period = 3600
M1="$WORK/m1"; snap "$M1"; append "$M1" infra/betterstack-logs-alerts.tf "$(mk_alert synth_over_ceiling 3600)"; landed M1 0
expect_red M1 "$M1" 'query_period-above-ceiling:.*synth_over_ceiling:3600>900'
# Controls of the verdict owners (see own_ctl): each is driven with ONE deliberately wrong input and must report
# exactly one failure with its own diagnostic, through printf and exit rather than through the helpers under test.
red_drv_survivor() { expect_red CTL-RED "$BASE" 'query_period-above-ceiling'; }
red_drv_wrongreason() { expect_red CTL-RED "$M1" 'retired-resource-redeclared'; }
green_drv_red() { expect_green CTL-GREEN "$M1"; }
landed_drv_fail() { landed CTL-LANDED 3; }
own_ctl "expect_red() reports SURVIVED when handed an UNMUTATED tree" "SURVIVED" red_drv_survivor
own_ctl "expect_red() reports another-reason for a tree that is red for a different violation" "went red for another reason" red_drv_wrongreason
own_ctl "expect_green() fails for a tree that is red" "went red but must stay green" green_drv_red
own_ctl "landed() fails when the edit did not land" "did NOT land" landed_drv_fail
# M2: a compliant alert first, an over-limit one in a DIFFERENT file (not first-hit)
M2="$WORK/m2"; snap "$M2"; append "$M2" infra/betterstack-logs-alerts.tf "$(mk_alert synth_compliant 900)"
printf '%s\n%s\n' "$(mk_alert synth_second_ok 300)" "$(mk_alert synth_second_over 7200)" > "$M2/infra/zz-synth-extra.tf"; landed M2 0
expect_red M2 "$M2" 'zz-synth-extra.tf:synth_second_over:7200>900'
# M3: rename an allowlisted alert to a new name at 86400
M3="$WORK/m3"; snap "$M3"
edit "$M3" infra/betterstack-logs-alerts.tf 'resource "logtail_exploration_alert" "claude_cost_daily_burn"' 'resource "logtail_exploration_alert" "claude_cost_daily_burn_renamed"'; landed M3 $?
expect_red M3 "$M3" 'claude_cost_daily_burn_renamed:86400>900'
# M4: re-add a retired exploration, and (M4b) a retired alert
M4="$WORK/m4"; snap "$M4"; append "$M4" infra/betterstack-logs-alerts.tf 'resource "logtail_exploration" "luks_monitor_host_timer_dark" {
  name = "x"
}'; landed M4 0
expect_red M4 "$M4" 'retired-resource-redeclared:logtail_exploration.luks_monitor_host_timer_dark'
M4B="$WORK/m4b"; snap "$M4B"; append "$M4B" infra/betterstack-logs-alerts.tf "$(mk_alert claude_cost_capture_dark 900)"; landed M4b 0
expect_red M4b "$M4B" 'retired-resource-redeclared:logtail_exploration_alert.claude_cost_capture_dark'
# M5: remove one of the four retained -target lines
M5="$WORK/m5"; snap "$M5"
"$PY" -I - "$M5/apply.yml" <<'PYD'
import re, sys
p = sys.argv[1]
s = open(p).read()
lines = s.split("\n")
idx = [i for i, l in enumerate(lines) if l.strip().startswith("-target=logtail_exploration_alert.luks_monitor_host_timer_dark")]
if len(idx) != 1:
    sys.exit(3)
del lines[idx[0]]
open(p, "w").write("\n".join(lines))
PYD
landed M5 $?
expect_red M5 "$M5" 'retained-destroy-target-missing:-target=logtail_exploration_alert.luks_monitor_host_timer_dark'
M5B="$WORK/m5b"; snap "$M5B"
edit "$M5B" census.sh '"logtail_exploration.claude_cost_capture_dark": "#11631"' '"logtail_exploration.claude_cost_capture_dark_x": "#11631"'; landed M5b $?
expect_red M5b "$M5B" 'census-intended-destroy-missing'
# M6: the discovery finds zero alert blocks (the resource kind is renamed)
M6="$WORK/m6"; snap "$M6"
"$PY" -I - "$M6/infra/betterstack-logs-alerts.tf" <<'PYR'
import sys
p = sys.argv[1]
s = open(p).read()
n = s.count('resource "logtail_exploration_alert" ')
if n < 1:
    sys.exit(3)
open(p, "w").write(s.replace('resource "logtail_exploration_alert" ', 'resource "logtail_exploration_alertx" '))
PYR
landed M6 $?
expect_red M6 "$M6" 'anti-vacuity'
# M7: a query_period = 86400 appearing ONLY inside a comment, a heredoc and a block comment (must-PASS)
M7="$WORK/m7"; snap "$M7"
append "$M7" infra/betterstack-logs-alerts.tf '# query_period = 86400
// query_period = 86400
/* resource "logtail_exploration_alert" "in_block_comment" {
  query_period = 86400
} */
locals {
  synth_note = <<-NOTE
    resource "logtail_exploration_alert" "in_heredoc" {
      query_period = 86400
    }
  NOTE
}'
append "$M7" infra/betterstack-logs-alerts.tf "$(mk_alert synth_commented 900 ' # query_period = 86400 is not the value')"; landed M7 0
expect_green M7 "$M7"
# M8: a real over-limit block carrying a trailing comment is still parsed
M8="$WORK/m8"; snap "$M8"; append "$M8" infra/betterstack-logs-alerts.tf "$(mk_alert synth_trailing 3600 ' # a note')"; landed M8 0
expect_red M8 "$M8" 'synth_trailing:3600>900'
# M9: a value that is not an integer literal is unparsable (a failure, not a pass)
M9="$WORK/m9"; snap "$M9"; append "$M9" infra/betterstack-logs-alerts.tf "$(mk_alert synth_expr 'local.some_window')"; landed M9 0
expect_red M9 "$M9" 'unparsable-query_period:.*synth_expr'
# M10: an unbalanced block is a failure
M10="$WORK/m10"; snap "$M10"; append "$M10" infra/betterstack-logs-alerts.tf 'resource "logtail_exploration_alert" "synth_unbalanced" {
  query_period = 300'; landed M10 0
expect_red M10 "$M10" 'unbalanced-block'

# --- the sentinel's own defences (each row has a checker variant without that defence that lets the fixture through) ---
# M11: whitespace of any kind between the header tokens; M12: bare labels
M11="$WORK/m11"; snap "$M11"; append "$M11" infra/betterstack-logs-alerts.tf "$(mk_alert synth_tab 3600 | sed "s/^resource \"logtail_exploration_alert\" /resource$(printf '\t')\"logtail_exploration_alert\"$(printf '\t')/")"; landed M11 0
expect_red M11 "$M11" 'synth_tab:3600>900'
M12="$WORK/m12"; snap "$M12"; append "$M12" infra/betterstack-logs-alerts.tf "$(mk_alert synth_bare 3600 | sed 's/^resource "logtail_exploration_alert" "synth_bare"/resource logtail_exploration_alert synth_bare/')"; landed M12 0
expect_red M12 "$M12" 'synth_bare:3600>900'
# M13: a literal `$${` inside a string must not open an interpolation: with the old lexer the string ran on, the
# quote parity flipped, the real string "/*" became a comment opener and swallowed the over-limit block below it.
M13="$WORK/m13"; snap "$M13"
append "$M13" infra/betterstack-logs-alerts.tf 'locals { esc = "$${" }
locals { c = "/*" }'
append "$M13" infra/betterstack-logs-alerts.tf "$(mk_alert synth_evil_desync 86400)"
append "$M13" infra/betterstack-logs-alerts.tf '/* an ordinary comment */'; landed M13 0
expect_red M13 "$M13" 'synth_evil_desync:86400>900'
expect_red "M13x (the same fixture under a checker WITHOUT the $\${ escape: the interpolation lexer swallows the file, a lex-problem)" "$M13" 'lex-problem:.*unterminated-' "$WORK/checker-noesc.py"
# M14: a nested map holding a decoy query_period, after a string that holds a lone brace
M14="$WORK/m14"; snap "$M14"
append "$M14" infra/betterstack-logs-alerts.tf 'resource "logtail_exploration_alert" "synth_decoy" {
  name = "}"
  metadata = {
    query_period = 1
  }
  query_period = 3600
}'; landed M14 0
expect_red M14 "$M14" 'synth_decoy:3600>900'
expect_green "M14x (the same fixture under a checker that is not string-aware: the decoy wins)" "$M14" "$WORK/checker-nostr.py"
# M15: .tf.json files are scanned
M15="$WORK/m15"; snap "$M15"
printf '{"resource":{"logtail_exploration_alert":{"synth_json_over":{"query_period":3600,"name":"x"}}}}\n' > "$M15/infra/zz-synth.tf.json"; landed M15 0
expect_red M15 "$M15" 'synth_json_over:3600>900'
M15B="$WORK/m15b"; snap "$M15B"
printf '{"resource":[{"logtail_exploration_alert":{"synth_json_ok":[{"query_period":900,"name":"x"}]}}]}\n' > "$M15B/infra/zz-synth.tf.json"
expect_green M15b "$M15B"
M15C="$WORK/m15c"; snap "$M15C"; printf '{"resource": ' > "$M15C/infra/zz-synth.tf.json"
expect_red M15c "$M15C" 'unparsable-tf-json'
# M16: a dashboard alert is held to the same ceiling
M16="$WORK/m16"; snap "$M16"; append "$M16" infra/betterstack-logs-alerts.tf "$(mk_alert synth_dash 3600 | sed 's/logtail_exploration_alert/logtail_dashboard_alert/')"; landed M16 0
expect_red M16 "$M16" 'synth_dash:3600>900'
# M17: lifecycle ignore_changes over query_period lets the live value drift above the ceiling
M17="$WORK/m17"; snap "$M17"; append "$M17" infra/betterstack-logs-alerts.tf "$(mk_alert synth_ign 900 | sed '$ d')
  lifecycle {
    ignore_changes = [query_period]
  }
}"; landed M17 0
expect_red M17 "$M17" 'ignore_changes-covers-query_period:.*synth_ign'
expect_green "M17x (the same fixture under a checker WITHOUT the ignore_changes defence)" "$M17" "$WORK/checker-noign.py"
M17B="$WORK/m17b"; snap "$M17B"; append "$M17B" infra/betterstack-logs-alerts.tf "$(mk_alert synth_ignall 900 | sed '$ d')
  lifecycle {
    ignore_changes = all
  }
}"
expect_red M17b "$M17B" 'ignore_changes-covers-query_period:.*synth_ignall'
M17C="$WORK/m17c"; snap "$M17C"; append "$M17C" infra/betterstack-logs-alerts.tf "$(mk_alert synth_ignname 900 | sed '$ d')
  lifecycle {
    ignore_changes = [name]
  }
}"
expect_green "M17c (ignore_changes over another attribute, must-PASS)" "$M17C"
# M18: a census entry that is only a COMMENT is not a live entry
M18="$WORK/m18"; snap "$M18"
edit "$M18" census.sh '        "logtail_exploration.claude_cost_capture_dark": "#11631",' '        # "logtail_exploration.claude_cost_capture_dark": "#11631",'; landed M18 $?
expect_red M18 "$M18" 'census-intended-destroy-missing:logtail_exploration.claude_cost_capture_dark'
# M19: an unterminated block comment would hide everything after it
M19="$WORK/m19"; snap "$M19"; append "$M19" infra/betterstack-logs-alerts.tf "/* never closed
$(mk_alert synth_hidden 86400)"; landed M19 0
expect_red M19 "$M19" 'lex-problem:.*unterminated-block-comment'
# M20: two top-level query_period attributes
M20="$WORK/m20"; snap "$M20"; append "$M20" infra/betterstack-logs-alerts.tf "$(mk_alert synth_dup 900 | sed '$ d')
  query_period = 3600
}"; landed M20 0
expect_red M20 "$M20" 'duplicate-query_period:.*synth_dup'

# --- review round 2: the interpolation lexer, the independent count, the parser misses ------------------------------------
# M21: a quote inside an interpolation. `"${format("%s}", "a")}"` used to close the string at the `}` inside the nested
# string, flip the quote parity, turn the real string "/*" into a comment opener and hide the over-limit block below.
M21="$WORK/m21"; snap "$M21"
append "$M21" infra/betterstack-logs-alerts.tf 'locals { x = "${format("%s}", "a")}" }
locals { c = "/*" }'
append "$M21" infra/betterstack-logs-alerts.tf "$(mk_alert synth_evil_interp 86400)"
append "$M21" infra/betterstack-logs-alerts.tf '/* an ordinary comment */'; landed M21 0
expect_red M21 "$M21" 'synth_evil_interp:86400>900'
expect_red "M21x (the old lexer: the line-anchored count notices the hidden header)" "$M21" 'anti-vacuity:.*anchored=' "$WORK/checker-oldlex.py"
expect_green "M21y (the old lexer AND no anchored count: the block is hidden, parsed == naive)" "$M21" "$WORK/checker-oldlex-noanchor.py"
# M22: the same shape through a template DIRECTIVE (`%{ ... }`).
M22="$WORK/m22"; snap "$M22"
append "$M22" infra/betterstack-logs-alerts.tf 'locals { y = "%{ for s in ["}"] }${s}%{ endfor }" }
locals { c = "/*" }'
append "$M22" infra/betterstack-logs-alerts.tf "$(mk_alert synth_evil_directive 86400)"
append "$M22" infra/betterstack-logs-alerts.tf '/* an ordinary comment */'; landed M22 0
expect_red M22 "$M22" 'synth_evil_directive:86400>900'
expect_red "M22x (the old lexer: the line-anchored count notices the hidden header)" "$M22" 'anti-vacuity:.*anchored=' "$WORK/checker-oldlex.py"
expect_green "M22y (the old lexer AND no anchored count: the block is hidden)" "$M22" "$WORK/checker-oldlex-noanchor.py"
# M22b: nested interpolation inside a nested string inside an interpolation, then a real block (must-PASS: both counts agree)
M22B="$WORK/m22b"; snap "$M22B"
append "$M22B" infra/betterstack-logs-alerts.tf 'locals { z = "${join("-", ["a", "${format("%s}", "b")}"])}" }'
append "$M22B" infra/betterstack-logs-alerts.tf "$(mk_alert synth_nested_ok 900)"; landed M22b 0
expect_green M22b "$M22B"
# M22c: an interpolation that never closes is a lex problem, not a pass. (The must-PASS side of the anchored count,
# a header inside a heredoc and one inside a leading block comment, is M7.)
M22C="$WORK/m22c"; snap "$M22C"; append "$M22C" infra/betterstack-logs-alerts.tf 'locals { u = "${format("a")'; landed M22c 0
expect_red M22c "$M22C" 'lex-problem:.*unterminated-'

# L4(a): ignore_changes parsed as a bracket-matched list, not by a regex that stops at the first `]`.
mk_ign() { # <name> <ignore_changes value text> -> an alert whose lifecycle carries it
  mk_alert "$1" 900 | sed '$ d'
  printf '  lifecycle {\n    ignore_changes = %s\n  }\n}' "$2"
}
M26="$WORK/m26"; snap "$M26"; append "$M26" infra/betterstack-logs-alerts.tf "$(mk_ign synth_ign_index '[name["x"], query_period]')"; landed M26 0
expect_red M26 "$M26" 'ignore_changes-covers-query_period:.*synth_ign_index'
expect_green "M26x (the old regex stops at the first ] inside name[\"x\"] and misses query_period)" "$M26" "$WORK/checker-oldign.py"
M27="$WORK/m27"; snap "$M27"; append "$M27" infra/betterstack-logs-alerts.tf "$(mk_ign synth_ign_multi '[
      metadata[0],
      query_period,
    ]')"; landed M27 0
expect_red M27 "$M27" 'ignore_changes-covers-query_period:.*synth_ign_multi'
expect_green "M27x (the old regex stops at metadata[0])" "$M27" "$WORK/checker-oldign.py"
M28="$WORK/m28"; snap "$M28"; append "$M28" infra/betterstack-logs-alerts.tf "$(mk_ign synth_ign_quoted '["query_period"]')"; landed M28 0
expect_red M28 "$M28" 'ignore_changes-covers-query_period:.*synth_ign_quoted'
M28B="$WORK/m28b"; snap "$M28B"; append "$M28B" infra/betterstack-logs-alerts.tf "$(mk_ign synth_ign_expr 'local.keep')"; landed M28b 0
expect_red M28b "$M28B" 'ignore_changes-covers-query_period:.*synth_ign_expr'
M28C="$WORK/m28c"; snap "$M28C"; append "$M28C" infra/betterstack-logs-alerts.tf "$(mk_ign synth_ign_decoy '[name["query_period"], metadata[0]]')"; landed M28c 0
expect_green "M28c (query_period only inside an index string is not the attribute: must-PASS)" "$M28C"
M28D="$WORK/m28d"; snap "$M28D"
append "$M28D" infra/betterstack-logs-alerts.tf "$(mk_alert synth_str_decoy 900 | sed 's/  name           = "synth_str_decoy"/  name           = "ignore_changes = [query_period]"/')"; landed M28d 0
expect_green "M28d (the words ignore_changes = [query_period] inside a STRING are not a lifecycle block: must-PASS)" "$M28D"
# L4(d): the .tf.json interpolation form.
M30="$WORK/m30"; snap "$M30"
printf '{"resource":{"logtail_exploration_alert":{"synth_json_ign":{"query_period":900,"name":"x","lifecycle":{"ignore_changes":["${query_period}"]}}}}}\n' > "$M30/infra/zz-synth.tf.json"; landed M30 0
expect_red M30 "$M30" 'ignore_changes-covers-query_period:.*synth_json_ign'
M30B="$WORK/m30b"; snap "$M30B"
printf '{"resource":{"logtail_exploration_alert":{"synth_json_ign2":{"query_period":900,"name":"x","lifecycle":{"ignore_changes":["${name}"]}}}}}\n' > "$M30B/infra/zz-synth.tf.json"; landed M30b 0
expect_green "M30b (a .tf.json ignore_changes over another attribute: must-PASS)" "$M30B"

# L4(b): the allowlist is keyed by (kind, file, name).
M23="$WORK/m23"; snap "$M23"; append "$M23" infra/betterstack-logs-alerts.tf "$(mk_alert claude_cost_daily_burn 86400 | sed 's/logtail_exploration_alert/logtail_dashboard_alert/')"; landed M23 0
expect_red M23 "$M23" 'claude_cost_daily_burn:86400>900'
expect_green "M23x (allowlisted by NAME only: a same-named dashboard alert at 86400 slips through)" "$M23" "$WORK/checker-byname.py"
M24="$WORK/m24"; snap "$M24"
printf '{"resource":{"logtail_exploration_alert":{"inngest_luks_wrong_volume":{"query_period":5400,"name":"x"}}}}\n' > "$M24/infra/zz-synth.tf.json"; landed M24 0
expect_red M24 "$M24" 'zz-synth.tf.json:inngest_luks_wrong_volume:5400>900'
M25="$WORK/m25"; snap "$M25"; printf '%s\n' "$(mk_alert inngest_luks_wrong_volume 5400)" > "$M25/infra/zz-synth-extra.tf"; landed M25 0
expect_red M25 "$M25" 'zz-synth-extra.tf:inngest_luks_wrong_volume:5400>900'
expect_green "M25x (allowlisted by NAME only: the same name in another file slips through)" "$M25" "$WORK/checker-byname.py"

# L4(c): the four census entries must sit under the "apps/web-platform/infra" key of INTENDED_DESTROYS.
M29="$WORK/m29"; snap "$M29"
edit "$M29" census.sh '    "apps/web-platform/infra": {
        "doppler_secret.ghcr_read_user"' '    "apps/other-root": {
        "doppler_secret.ghcr_read_user"'; landed M29 $?
expect_red M29 "$M29" 'census-intended-destroy-missing'
expect_green "M29x (any key in INTENDED_DESTROYS satisfies the census check)" "$M29" "$WORK/checker-anykey.py"

echo "== harness rows =="
# (a) the sentinel reads its ceiling: with the ceiling at 100000, M1 goes GREEN.
cases=$((cases + 1))
if ! cmp -s "$WORK/checker.py" "$WORK/checker-wide.py"; then pass "harness: the wide-ceiling checker differs from the real one (landed)"; else fail "harness: the wide-ceiling checker did not land"; fi
expect_green "H1 (ceiling 100000 turns M1 green)" "$M1" "$WORK/checker-wide.py"
# (b) a new alert at exactly 900 stays green with the real checker.
H2="$WORK/h2"; snap "$H2"; append "$H2" infra/betterstack-logs-alerts.tf "$(mk_alert synth_at_ceiling 900)"
expect_green "H2 (a new alert at exactly 900 s)" "$H2"
H3="$WORK/h3"; snap "$H3"; append "$H3" infra/betterstack-logs-alerts.tf "$(mk_alert synth_at_901 901)"
expect_red H3 "$H3" 'synth_at_901:901>900'
# (c) the real checker is not vacuously green: it rejects an empty infra dir.
mkdir -p "$WORK/empty/infra"; cp "$BASE/apply.yml" "$BASE/census.sh" "$WORK/empty/"
expect_red "H4 (an empty infra dir)" "$WORK/empty" 'no-tf-files-found'

echo
echo "=== $passes passed, $fails failed, $cases cases ==="
if (( passes + fails != cases )); then
  printf 'FATAL: verdict conservation violated — %s+%s != %s cases.\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
# EXACT floor: the measured pass count of this file, compared with `!=` (a case deleted, a block that stopped
# running, AND an unaccounted case added all trip it). Changing a case means setting it to the count printed above.
MIN_PASSES=110
if (( passes != MIN_PASSES )); then
  printf 'FATAL: %s passes, the exact floor is %s -- the suite was truncated or extended; re-derive the floor.\n' "$passes" "$MIN_PASSES" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
echo "All $cases cases passed."
